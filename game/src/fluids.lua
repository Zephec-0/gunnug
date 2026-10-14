-- Volumetric gas, water, fire and smoke (design doc §6c). A sparse grid of
-- 2-px cells per substance (nearly pixel-fine: the baseline for every liquid
-- and gas added later), simulated only around the hunter (everything else is
-- frozen as it was) and drawn from the same grid:
--   gas    concentration 0..1 that diffuses slowly through open space, a little
--          faster downward (it is heavy), thinning as it spreads; vents on the
--          floors of the Sulfur Vents keep feeding it. Poisons the hunter.
--          Burns: a fire cell next to gas ignites it, and the flame runs
--          through the cloud, turning it to fire and smoke.
--   water  cellular water: falls, slides off slopes and flows toward lower
--          ground, settling flat. Slows the hunter and puts out fire.
--   fire   short-lived flames (they live as long as their fuel, otherwise a
--          fraction of a second). Hurt the hunter, set monsters alight and
--          ignite gas. Created by incendiary rounds, explosions, wisps.
--   smoke  drifts up and thins out; fire and steam make it.
-- Terrain is read from the world; nothing here changes it.
local audio = require("src.audio")
local effects = require("src.effects")

local fluids = {}

local C = 2 -- cell size in pixels
local HALF = C / 2
local POOL_CELL = 4 -- cavegen's pools come on a coarser grid: each of its cells fills several of ours
local WATER_STEP = 0.025 -- water moves a cell per step: 80 px/s falling
local SPREAD = 12 -- water slides sideways toward a drop up to this many cells away
local SWEEP = 1.5 -- every so often all water near the hunter is woken (terrain may have changed)
local K = 2048 -- key stride: key = gy * K + gx
local RANGE_X, RANGE_Y = 400, 270 -- the simulated region around the hunter

local GAS_COLOR = { 0.72, 0.86, 0.26 }
local TICK = 0.5 -- seconds between damage ticks while in gas or fire
local GAS_DAMAGE = 3
local FIRE_DAMAGE = 5
local DROWN_DAMAGE = 4 -- per tick (every half second) once the breath has run out
local BREATH_BUBBLES = 3 -- bubbles over his head; one pops each second he is under

local world
local gas, water, fire, smoke = {}, {}, {}, {}
local vents = {} -- { k, x, y }
local braziers = {} -- { k, x, y }: bowls of fire that never go out
local columns = {} -- vertical columns of dense gas: { x0, x1, top, bottom, age, warn, life }
local COLUMN_DAMAGE = 9 -- per tick inside a column (a thin cloud of gas does about 3-5)
local accWater, accSlow, accPurge, accSmoke, accSweep = 0, 0, 0, 0, 0
local active = {} -- water cells that may move this step; resting water sleeps
-- How many cells of water and of gas each grid row holds, so drawing and the
-- gas step skip empty rows
local waterRows, gasRows = {}, {}
local gasTimer, fireTimer = TICK, TICK
local drownTimer = TICK
local breathPlayer -- the hunter, for drawing his bubbles
local clock = 0

-- 0..1: how deep in gas the hunter has been lately (tints the screen)
fluids.exposure = 0

function fluids.clear()
  gas, water, fire, smoke, vents, braziers, columns = {}, {}, {}, {}, {}, {}, {}
  active, waterRows, gasRows = {}, {}, {}
  gasTimer, fireTimer, drownTimer = TICK, TICK, TICK
  breathPlayer = nil
  fluids.exposure = 0
  world = nil
end

local floor = math.floor

local function key(gx, gy)
  return gy * K + gx
end

local function cellOf(x, y)
  return key(floor(x / C), floor(y / C))
end

local function coords(k)
  local gx = k % K
  return gx, (k - gx) / K
end

local function solidAt(k)
  local gx, gy = coords(k)
  return world:isSolid(gx * C + HALF, gy * C + HALF)
end

local function rowOf(k)
  return (k - k % K) / K
end

-- Every change to water or gas goes through these, to keep the row counts
local function setWater(k, v)
  local had = water[k] ~= nil
  if v and not had then
    local r = rowOf(k)
    waterRows[r] = (waterRows[r] or 0) + 1
  elseif not v and had then
    local r = rowOf(k)
    waterRows[r] = waterRows[r] - 1
  end
  water[k] = v or nil
end

local function setGas(k, v)
  local had = gas[k] ~= nil
  if v and not had then
    local r = rowOf(k)
    gasRows[r] = (gasRows[r] or 0) + 1
  elseif not v and had then
    local r = rowOf(k)
    gasRows[r] = gasRows[r] - 1
  end
  gas[k] = v
end

-- Free of terrain and water
local function open(k)
  return not water[k] and not solidAt(k)
end

-- Setup ----------------------------------------------------------------------

-- Adds an area's pools: info.gas and info.water from cavegen (lists of pools,
-- each { cells = { x, y, ... } top-left pixel corners of C-px cells, vent })
function fluids.add(w, info)
  world = w
  local sub = POOL_CELL / C
  for _, p in ipairs(info.gas or {}) do
    for i = 1, #p.cells, 2 do
      local gx, gy = p.cells[i] / C, p.cells[i + 1] / C
      for oy = 0, sub - 1 do
        for ox = 0, sub - 1 do
          if not solidAt(key(gx + ox, gy + oy)) then
            setGas(key(gx + ox, gy + oy), 0.85)
          end
        end
      end
    end
    local vx, vy = p.vent[1], p.vent[2]
    vents[#vents + 1] = { k = cellOf(vx, vy - 2), x = vx, y = vy }
  end
  for _, p in ipairs(info.water or {}) do
    for i = 1, #p.cells, 2 do
      local gx, gy = p.cells[i] / C, p.cells[i + 1] / C
      for oy = 0, sub - 1 do
        for ox = 0, sub - 1 do
          local k = key(gx + ox, gy + oy)
          if not solidAt(k) then
            setWater(k, true)
            active[k] = true
          end
        end
      end
    end
  end
end

-- Water over the open cells between x0 and x1 from `level` down to the ground
-- (a pond in a hollow of the terrain)
function fluids.fillWater(w, x0, x1, level)
  world = world or w
  for gx = floor(x0 / C), floor(x1 / C) do
    local gy = floor(level / C)
    while gy < floor(level / C) + 60 * 4 / C and not w:isSolid(gx * C + HALF, gy * C + HALF) do
      setWater(key(gx, gy), true)
      active[key(gx, gy)] = true
      gy = gy + 1
    end
  end
end

-- A brazier: a bowl of fire at (x, y) (its rim), always burning. Gas that
-- drifts into it ignites, and the flash runs through the whole cloud.
function fluids.addBrazier(x, y)
  braziers[#braziers + 1] = { k = cellOf(x, y - 14), x = x, y = y }
end

-- A column of dense gas: after a `warn` seconds of warning (vents crack open
-- and it glows), gas at full strength pours up through the whole of its
-- height from x - w/2 to x + w/2 for `life` seconds. Walking through it hurts
-- a lot, so it walls off that part of the arena until it thins out. It is
-- still gas: it can be burned.
function fluids.addColumn(x, w, top, bottom, warn, life)
  columns[#columns + 1] = { x0 = x - w / 2, x1 = x + w / 2, top = top, bottom = bottom, age = 0, warn = warn, life = life }
end

-- Is the point inside a column that is pouring?
function fluids.inColumn(x, y)
  for _, c in ipairs(columns) do
    if c.age >= c.warn and x >= c.x0 and x <= c.x1 and y >= c.top and y <= c.bottom then
      return true
    end
  end
  return false
end

function fluids.setWorld(w)
  world = w
end

-- Adding things ---------------------------------------------------------------

-- (a puff covers a 4-px patch, so it reads the same at any cell size)
function fluids.addSmoke(x, y, amount)
  local k = cellOf(x, y)
  for _, d in ipairs({ 0, 1, K, K + 1 }) do
    smoke[k + d] = math.min(1, (smoke[k + d] or 0) + amount)
  end
end

-- A cloud of gas around (x, y): concentration `amount` fading toward `radius`
function fluids.addGas(x, y, amount, radius)
  if not world then
    return
  end
  local r = floor(radius / C)
  local cx, cy = floor(x / C), floor(y / C)
  for dy = -r, r do
    for dx = -r, r do
      local d = math.sqrt(dx * dx + dy * dy)
      if d <= r then
        local k = key(cx + dx, cy + dy)
        if open(k) then
          setGas(k, math.min(1, (gas[k] or 0) + amount * (1 - 0.5 * d / math.max(1, r))))
        end
      end
    end
  end
end

local function igniteCell(k, c)
  setGas(k, nil)
  fire[k] = 0.25 + c * 0.9
  smoke[k - K] = math.min(1, (smoke[k - K] or 0) + c * 0.35)
end

-- A spark at (x, y): ignites gas in and around its cell. Without gas it
-- makes a small flame there too, unless onlyGas. Returns true if gas caught.
function fluids.ignite(x, y, power, onlyGas)
  if not world then
    return false
  end
  local gx, gy = floor(x / C), floor(y / C)
  local caught = false
  for dy = -1, 1 do
    for dx = -1, 1 do
      local k = key(gx + dx, gy + dy)
      local c = gas[k]
      if c and c > 0.08 then
        igniteCell(k, c)
        caught = true
      end
    end
  end
  if not caught and not onlyGas then
    -- A small flame, a 4-px patch
    for _, d in ipairs({ 0, 1, -K, -K + 1 }) do
      local k = key(gx, gy) + d
      if open(k) then
        fire[k] = math.max(fire[k] or 0, 0.2 + 0.2 * (power or 1))
      end
    end
  end
  return caught
end

-- An explosion lights every gas cell it reaches and throws up flames and smoke
function fluids.explosion(x, y, radius)
  if not world then
    return
  end
  local r = floor(radius / C) + 1
  local cx, cy = floor(x / C), floor(y / C)
  for dy = -r, r do
    for dx = -r, r do
      if dx * dx + dy * dy <= r * r then
        local k = key(cx + dx, cy + dy)
        local c = gas[k]
        if c then
          igniteCell(k, c)
        elseif love.math.random() < 0.18 * C / 4 and open(k) then
          fire[k] = 0.2 + love.math.random() * 0.25
        end
      end
    end
  end
  for _ = 1, 3 do
    fluids.addSmoke(x + (love.math.random() - 0.5) * radius, y - love.math.random() * radius * 0.5, 0.6)
  end
end

-- Queries ---------------------------------------------------------------------

function fluids.gasAt(x, y)
  return gas[cellOf(x, y)] or 0
end

function fluids.waterAt(x, y)
  return water[cellOf(x, y)] == true
end

-- Is any part of the box (head, middle or feet) in water?
function fluids.waterTouching(x, y, w, h)
  return water[cellOf(x + w / 2, y + 1)] ~= nil or water[cellOf(x + w / 2, y + h / 2)] ~= nil or water[cellOf(x + w / 2, y + h - 1)] ~= nil
end

-- Wakes the water around a region (src.destruction calls this when terrain
-- is removed), so it starts to flow at once instead of at the next sweep
function fluids.wake(x0, y0, x1, y1)
  local gx0, gy0, gx1, gy1 = floor(x0 / C) - 2, floor(y0 / C) - 2, floor(x1 / C) + 2, floor(y1 / C) + 2
  for gy = gy0, gy1 do
    if (waterRows[gy] or 0) > 0 then
      for gx = gx0, gx1 do
        local k = gy * K + gx
        if water[k] then
          active[k] = true
        end
      end
    end
  end
end

function fluids.fireAt(x, y)
  return fire[cellOf(x, y)] ~= nil
end

-- Counts, for tests
function fluids.count()
  local function n(t)
    local c = 0
    for _ in pairs(t) do
      c = c + 1
    end
    return c
  end
  return n(gas), n(water), n(fire), n(smoke)
end

-- Simulation --------------------------------------------------------------------

local function region(px, py)
  return floor((px - RANGE_X) / C), floor((py - RANGE_Y) / C), floor((px + RANGE_X) / C), floor((py + RANGE_Y) / C)
end

-- Gas diffuses toward emptier neighbours: slowly sideways, faster down, a
-- little up. Thin traces vanish. (The weights are for 2-px cells.)
local GAS_OFFSETS = { K, -1, 1, -K }
local GAS_WEIGHTS = { 0.24, 0.14, 0.14, 0.08 }
local function stepGas(gx0, gy0, gx1, gy1)
  for _, v in ipairs(vents) do
    local gx, gy = coords(v.k)
    if gx >= gx0 and gx <= gx1 and gy >= gy0 and gy <= gy1 and not water[v.k] then
      for _, d in ipairs({ 0, -1, 1, -K }) do
        if (gas[v.k + d] or 0) < 0.9 and open(v.k + d) then
          setGas(v.k + d, math.min(0.95, (gas[v.k + d] or 0) + 0.08))
        end
      end
    end
  end
  local delta, openCache = {}, {}
  for gy = gy0, gy1 do
    if (gasRows[gy] or 0) > 0 then
      for gx = gx0, gx1 do
        local k = gy * K + gx
        local c = gas[k]
        if c then
          if water[k] then
            setGas(k, nil)
          else
            for i = 1, 4 do
              local nk = k + GAS_OFFSETS[i]
              local diff = c - (gas[nk] or 0)
              if diff > 0.012 then
                local o = openCache[nk]
                if o == nil then
                  o = open(nk)
                  openCache[nk] = o
                end
                if o then
                  local f = diff * GAS_WEIGHTS[i]
                  delta[k] = (delta[k] or 0) - f
                  delta[nk] = (delta[nk] or 0) + f
                end
              end
            end
          end
        end
      end
    end
  end
  for k, d in pairs(delta) do
    local v = (gas[k] or 0) + d
    setGas(k, (v >= 0.012) and math.min(1, v) or nil)
  end
end

-- Flames: ignite neighbouring gas (reaching two cells, so a burning cloud
-- flares across quickly), die down, leave smoke, and are put out by water
local FIRE_REACH = { -1, 1, -K, K, -2, 2, -2 * K, 2 * K, -3, 3, -4, 4, -3 * K, -4 * K }
local function stepFire(dt, near)
  local keys = {}
  for k in pairs(fire) do
    keys[#keys + 1] = k
  end
  local r = love.math.random
  for _, k in ipairs(keys) do
    local life = fire[k]
    if life then
      if water[k] or water[k + K] or water[k - 1] and water[k + 1] then
        fire[k] = nil
        smoke[k] = math.min(1, (smoke[k] or 0) + 0.3) -- steam
      else
        for _, d in ipairs(FIRE_REACH) do
          local n = k + d
          local c = gas[n]
          if c and c > 0.1 and r() < 0.75 then
            igniteCell(n, c)
          end
        end
        if r() < 0.12 then
          smoke[k - K] = math.min(1, (smoke[k - K] or 0) + 0.25)
        end
        life = life - dt
        if life <= 0 then
          fire[k] = nil
          if r() < 0.5 then
            smoke[k - K] = math.min(1, (smoke[k - K] or 0) + 0.3)
          end
        else
          fire[k] = life
          if near and r() < 0.06 then
            local gx, gy = coords(k)
            effects.particle(gx * C + HALF, gy * C, (r() - 0.5) * 14, -20 - r() * 20, 0.5, { 1, 0.55 + r() * 0.3, 0.15 }, -30, true)
          end
        end
      end
    end
  end
end

-- Smoke rises, wanders and thins (stepped twice as often as before, on
-- cells half the size, so it drifts as fast as ever)
local function stepSmoke(gx0, gy0, gx1, gy1)
  local cells = {}
  for k in pairs(smoke) do
    local gx = k % K
    local gy = (k - gx) / K
    if gx >= gx0 and gx <= gx1 and gy >= gy0 and gy <= gy1 then
      cells[#cells + 1] = k
    end
  end
  local r = love.math.random
  for _, k in ipairs(cells) do
    local v = smoke[k]
    if v then
      v = v * 0.9875 - 0.002
      if v < 0.05 then
        smoke[k] = nil
      else
        smoke[k] = v
        local side = r() < 0.5 and -1 or 1
        local target
        local roll = r()
        if roll < 0.6 then
          target = k - K
        elseif roll < 0.8 then
          target = k - K + side
        else
          target = k + side
        end
        if open(target) then
          local merged = (smoke[target] or 0) + v
          if merged <= 1 then
            smoke[target] = merged
            smoke[k] = nil
          end
        end
      end
    end
  end
end

-- Water: falls, then slides down-slope, then flows sideways toward a drop
-- within a few cells; otherwise rests. Only cells in `active` are looked at:
-- one that can't move goes to sleep until a neighbour moves (or the periodic
-- sweep wakes it), so still pools cost nothing.
local NEIGHBOURS = { -K - 1, -K, -K + 1, -1, 1, K - 1, K, K + 1 }
local function free(k)
  return not water[k] and not solidAt(k)
end

local function stepWater(gx0, gy0, gx1, gy1)
  local r = love.math.random
  local list = {}
  for k in pairs(active) do
    local gx = k % K
    local gy = (k - gx) / K
    if gx >= gx0 and gx <= gx1 and gy >= gy0 and gy <= gy1 then
      list[#list + 1] = k
    end
  end
  if #list == 0 then
    return
  end
  -- Bottom rows first; each row swept left or right at random
  if r() < 0.5 then
    table.sort(list, function(a, b)
      return a > b
    end)
  else
    table.sort(list, function(a, b)
      local ra, rb = a - a % K, b - b % K
      if ra ~= rb then
        return ra > rb
      end
      return a < b
    end)
  end
  local moved = {}
  local function move(k, n)
    setWater(k, nil)
    setWater(n, true)
    moved[n] = true
    setGas(n, nil)
    fire[n] = nil
    active[k] = nil
    active[n] = true
    for _, d in ipairs(NEIGHBOURS) do
      if water[k + d] then
        active[k + d] = true
      end
    end
  end
  for _, k in ipairs(list) do
    if water[k] and not moved[k] then
      local below = k + K
      local done = false
      if free(below) then
        move(k, below)
        done = true
      else
        local side = r() < 0.5 and -1 or 1
        for _, d in ipairs({ side, -side }) do
          if free(below + d) and free(k + d) then
            move(k, below + d)
            done = true
            break
          end
        end
        if not done then
          for _, d in ipairs({ side, -side }) do
            for i2 = 1, SPREAD do
              local c = k + d * i2
              if not free(c) then
                break
              end
              if free(c + K) then
                move(k, k + d)
                done = true
                break
              end
            end
            if done then
              break
            end
          end
        end
      end
      if not done then
        active[k] = nil
      end
    elseif not water[k] then
      active[k] = nil
    end
  end
end

-- Per frame ------------------------------------------------------------------------

-- player: the hunter; enemies: the enemies module (for fire and water on monsters)
function fluids.update(dt, player, enemies)
  if not world then
    return
  end
  clock = clock + dt
  local b = player.body
  local px, py = b.x + b.w / 2, b.y + b.h / 2
  local gx0, gy0, gx1, gy1 = region(px, py)

  accSweep = accSweep + dt
  if accSweep >= SWEEP then
    -- Wake the water near the hunter, in case the rock under it was dug away
    accSweep = 0
    for gy = gy0, gy1 do
      if (waterRows[gy] or 0) > 0 then
        for gx = gx0, gx1 do
          local k = gy * K + gx
          if water[k] then
            active[k] = true
          end
        end
      end
    end
  end
  accWater = accWater + dt
  local steps = 0
  while accWater >= WATER_STEP and steps < 2 do
    accWater = accWater - WATER_STEP
    steps = steps + 1
    stepWater(gx0, gy0, gx1, gy1)
  end
  accWater = math.min(accWater, WATER_STEP)
  accSmoke = accSmoke + dt
  if accSmoke >= 0.05 then
    accSmoke = 0
    stepSmoke(gx0, gy0, gx1, gy1)
  end
  accSlow = accSlow + dt
  if accSlow >= 0.1 then
    local step = accSlow
    accSlow = 0
    for _, br in ipairs(braziers) do
      local bx, by = coords(br.k)
      if bx >= gx0 and bx <= gx1 and by >= gy0 and by <= gy1 then
        for dk = -2, 3 do
          fire[br.k + dk] = math.max(fire[br.k + dk] or 0, 0.6)
        end
      end
    end
    for i = #columns, 1, -1 do
      local c = columns[i]
      c.age = c.age + step
      if c.age >= c.warn and c.age <= c.warn + c.life then
        for gy = floor(c.top / C), floor(c.bottom / C) do
          for gx = floor(c.x0 / C), floor(c.x1 / C) do
            local k = key(gx, gy)
            if open(k) then
              setGas(k, 1)
            end
          end
        end
      elseif c.age < c.warn and love.math.random() < 0.7 then
        -- The warning: dust and wisps jump up from the floor
        effects.particle(c.x0 + love.math.random() * (c.x1 - c.x0), c.bottom, (love.math.random() - 0.5) * 20, -40 - love.math.random() * 60, 0.7, { 0.85, 0.92, 0.35 }, 60, true)
      elseif c.age > c.warn + c.life + 1 then
        table.remove(columns, i)
      end
    end
    stepGas(gx0, gy0, gx1, gy1)
    stepFire(step, true)
    -- Wisps of gas in view drift up as little puffs
    if love.math.random() < 0.3 then
      local x = px + (love.math.random() - 0.5) * 500
      local y = py + (love.math.random() - 0.5) * 300
      local k = cellOf(x, y)
      if gas[k] and gas[k] > 0.3 then
        effects.particle(x, y, (love.math.random() - 0.5) * 6, -4, 1.0, { 0.62, 0.78, 0.22 }, 0, true)
      end
    end
  end
  accPurge = accPurge + dt
  if accPurge > 2 then
    accPurge = 0
    for k in pairs(smoke) do
      local x, y = coords(k)
      if x < gx0 - 20 or x > gx1 + 20 or y < gy0 - 20 or y > gy1 + 20 then
        smoke[k] = nil
      end
    end
  end

  -- The hunter: gas, fire and water
  local headK, midK = cellOf(px, b.y + 3), cellOf(px, py)
  local inCol = fluids.inColumn(px, py)
  local inGas = not player.dead and (inCol or math.max(gas[headK] or 0, gas[midK] or 0) > 0.12)
  if inGas then
    gasTimer = gasTimer - dt
    if gasTimer <= 0 then
      gasTimer = TICK
      local c = math.max(gas[headK] or 0, gas[midK] or 0)
      player:hurtOverTime(inCol and COLUMN_DAMAGE or math.floor(GAS_DAMAGE * (0.6 + c) + 0.5), GAS_COLOR, "gas")
      audio.play("hurt", 0.35)
    end
    if love.math.random() < dt * 6 then
      effects.particle(px + player.facing * 3, b.y + 5, player.facing * 14, -10, 0.6, GAS_COLOR, -20, true)
    end
  else
    gasTimer = math.min(TICK, gasTimer + dt)
  end
  fluids.exposure = fluids.exposure + ((inGas and 1 or 0) - fluids.exposure) * math.min(1, dt * 4)

  local inFire = false
  for _, y in ipairs({ b.y + 2, py, b.y + b.h - 2 }) do
    if fire[cellOf(px, y)] or fire[cellOf(px - 4, y)] or fire[cellOf(px + 4, y)] then
      inFire = true
    end
  end
  if inFire and not player.dead and not player.inWater then
    fireTimer = fireTimer - dt
    if fireTimer <= 0 then
      fireTimer = TICK
      player:hurtOverTime(FIRE_DAMAGE, { 1, 0.6, 0.2 }, "fire")
    end
  else
    fireTimer = math.min(TICK, fireTimer + dt)
  end

  local wasIn = player.inWater
  player.inWater = water[midK] == true
  player.submerged = water[headK] == true

  -- Breath: with his head under, the bubbles above him pop one a second; with
  -- none left he drowns, a tick of damage every half second. Out of the water
  -- they come back in about a second.
  breathPlayer = player
  if not player.dead then
    local breath = player.breath or BREATH_BUBBLES
    local before = math.ceil(breath - 0.0001)
    if player.submerged then
      breath = math.max(0, breath - dt)
      if breath <= 0 then
        drownTimer = drownTimer - dt
        if drownTimer <= 0 then
          drownTimer = TICK
          player:hurtOverTime(DROWN_DAMAGE, { 0.5, 0.8, 1 }, "water")
          audio.play("hurt", 0.35)
        end
      else
        drownTimer = TICK
      end
    else
      breath = math.min(BREATH_BUBBLES, breath + dt * BREATH_BUBBLES)
      drownTimer = TICK
    end
    -- A bubble pops each time the breath drops past a whole one
    local after = math.ceil(breath - 0.0001)
    if after < before and player.submerged then
      local bx = player.body.x + player.body.w / 2 - 12 + (before - 1) * 8
      local by = player.body.y - 14
      for _ = 1, 7 do
        effects.particle(bx + 3, by + 3, (love.math.random() - 0.5) * 60, -love.math.random() * 50, 0.4, { 0.75, 0.92, 1 }, 200, true)
      end
      audio.play("plop", 0.8, 1.4)
    end
    player.breath = breath
  end
  if player.inWater ~= (wasIn or false) then
    audio.play(player.inWater and "splash_in" or "splash_out")
    for _ = 1, 10 do
      effects.particle(px + (love.math.random() - 0.5) * 8, py - 4, (love.math.random() - 0.5) * 70, -40 - love.math.random() * 50, 0.5, { 0.55, 0.8, 0.95 }, 400, true)
    end
  end

  -- Monsters: fire sets them alight, water puts them out
  if enemies then
    for _, e in ipairs(enemies.all()) do
      local eb = e.body
      if math.abs(eb.x - px) < RANGE_X and math.abs(eb.y - py) < RANGE_Y then
        local ek = cellOf(eb.x + eb.w / 2, eb.y + eb.h / 2)
        if fire[ek] and not e.def.fireproof and not e.dead then
          enemies.ignite(e, 3, 2.5)
        end
        if water[ek] and e.burn then
          e.burn = nil
        end
        if e.def.fireWeak and not e.dead then
          -- A boss that burns badly: any flame over its body hurts it, twice a second
          local hw, hh = eb.w / 3, eb.h / 3
          local cx, cy = eb.x + eb.w / 2, eb.y + eb.h / 2
          local lit = fire[ek] or fire[cellOf(cx - hw, cy)] or fire[cellOf(cx + hw, cy)] or fire[cellOf(cx, cy - hh)] or fire[cellOf(cx, cy + hh)]
          if lit and clock - (e.lastFireHit or -9) > 0.5 then
            e.lastFireHit = clock
            enemies.damage(e, e.def.fireWeak)
          end
        end
      end
    end
  end
end

-- Drawing ----------------------------------------------------------------------------

local function visibleRange(view)
  return floor(view.x / C) - 1, floor(view.y / C) - 1, floor((view.x + view.w) / C) + 1, floor((view.y + view.h) / C) + 1
end

-- Vents on pool floors: a crusted crack (drawn behind the hunter, lit)
function fluids.drawDecor(view)
  for _, v in ipairs(vents) do
    if v.x > view.x - 8 and v.x < view.x + view.w + 8 and v.y > view.y - 8 and v.y < view.y + view.h + 8 then
      local x, y = floor(v.x), floor(v.y)
      love.graphics.setColor(0.70, 0.64, 0.24)
      love.graphics.rectangle("fill", x - 4, y - 1, 9, 1)
      love.graphics.setColor(0.82, 0.76, 0.30)
      love.graphics.rectangle("fill", x - 3, y - 2, 2, 1)
      love.graphics.rectangle("fill", x + 2, y - 2, 2, 1)
      love.graphics.setColor(0.10, 0.10, 0.04)
      love.graphics.rectangle("fill", x - 1, y - 1, 3, 1)
    end
  end
end

-- Pieces of a cell are drawn only where the terrain is not, so edges follow
-- the rock rather than the grid. A piece also counts as filled when it lies
-- in a cell the simulation had to treat as rock (its centre is solid) but a
-- neighbouring cell is filled, so there are no gaps hugging slopes.
local function pieceFilled(tbl, gx, gy, px, py, world)
  -- (cheap table lookups first: most pixels have nothing in or next to them)
  local k = gy * K + gx
  local v = tbl[k]
  if v then
    if world:isSolid(px, py) then
      return nil
    end
    return v
  end
  local n = tbl[k - 1] or tbl[k + 1] or tbl[k - K] or tbl[k + K]
  if n and solidAt(k) and not world:isSolid(px, py) then
    return n
  end
  return nil
end

-- Gas and flames glow, so they are drawn after the lighting
-- The hunter's breath: three bubbles over his head while he is under (and as
-- they come back); they flash red once he is drowning
local function drawBreath(t)
  local p = breathPlayer
  if not p or p.dead then
    return
  end
  local breath = p.breath or BREATH_BUBBLES
  if breath >= BREATH_BUBBLES - 0.001 and not p.submerged then
    return
  end
  local cx = math.floor(p.body.x + p.body.w / 2)
  local top = math.floor(p.body.y) - 14
  local drowning = breath <= 0
  for i = 1, BREATH_BUBBLES do
    local x = cx - 12 + (i - 1) * 8
    local y = top + math.floor(math.sin(t * 3 + i * 1.7) * 1.2 + 0.5)
    local full = breath > i - 1
    if full then
      -- A ring with a pale glint; the one about to pop shakes
      local shake = (breath <= i and breath > i - 1 and p.submerged) and (math.floor(t * 30) % 2) or 0
      love.graphics.setColor(0.35, 0.60, 0.85, 0.55)
      love.graphics.rectangle("fill", x + 1 + shake, y + 1, 5, 5)
      love.graphics.setColor(0.78, 0.93, 1, 0.95)
      love.graphics.rectangle("fill", x + 2 + shake, y, 3, 1)
      love.graphics.rectangle("fill", x + 2 + shake, y + 6, 3, 1)
      love.graphics.rectangle("fill", x + shake, y + 2, 1, 3)
      love.graphics.rectangle("fill", x + 6 + shake, y + 2, 1, 3)
      love.graphics.setColor(1, 1, 1)
      love.graphics.rectangle("fill", x + 2 + shake, y + 2, 1, 1)
    elseif drowning and math.floor(t * 5) % 2 == 0 then
      -- No air left: empty rings flashing red
      love.graphics.setColor(1, 0.25, 0.25, 0.9)
      love.graphics.rectangle("fill", x + 2, y, 3, 1)
      love.graphics.rectangle("fill", x + 2, y + 6, 3, 1)
      love.graphics.rectangle("fill", x, y + 2, 1, 3)
      love.graphics.rectangle("fill", x + 6, y + 2, 1, 3)
    end
  end
end

local GAS_LEVELS = 8
local GAS_MAX = 0.58 -- the strongest a gas cell is drawn
local gasPoints = {}
for i = 1, GAS_LEVELS do
  gasPoints[i] = {}
end

function fluids.drawEmissive(view)
  local gx0, gy0, gx1, gy1 = visibleRange(view)
  local t = love.timer.getTime()
  drawBreath(t)
  -- Gas: each cell a 2-px square whose strength shimmers slowly, sorted into
  -- a few brightness levels so the whole cloud is a handful of draw calls
  local counts = {}
  for i = 1, GAS_LEVELS do
    counts[i] = 0
  end
  local sin = math.sin
  for gy = gy0, gy1 do
    if (gasRows[gy] or 0) > 0 then
      local row = gy * K
      local py = gy * C
      local wob = sin(py * 0.05 - t * 0.3) * 1.7
      for gx = gx0, gx1 do
        local c = gas[row + gx]
        if c and c > 0.03 then
          local px = gx * C
          local n = 0.5 + 0.5 * sin(px * 0.07 + t * 0.5 + wob)
          local a = math.min(0.4, c * 0.3) * (0.55 + n * 0.9)
          local level = math.min(GAS_LEVELS, floor(a / GAS_MAX * GAS_LEVELS) + 1)
          local list = gasPoints[level]
          local nn = counts[level]
          list[nn + 1] = px + HALF
          list[nn + 2] = py + HALF
          counts[level] = nn + 2
        end
      end
    end
  end
  love.graphics.setPointSize(C)
  for i = 1, GAS_LEVELS do
    local list, nn = gasPoints[i], counts[i]
    for j = #list, nn + 1, -1 do
      list[j] = nil
    end
    if nn > 0 then
      love.graphics.setColor(GAS_COLOR[1], GAS_COLOR[2], GAS_COLOR[3], (i - 0.5) / GAS_LEVELS * GAS_MAX)
      love.graphics.points(list)
    end
  end
  love.graphics.setPointSize(1)
  -- Columns still warming up: a flickering pale beam where gas is about to pour
  for _, c in ipairs(columns) do
    if c.age < c.warn and c.x1 > view.x and c.x0 < view.x + view.w then
      local pulse = 0.5 + 0.5 * math.sin(t * 14)
      love.graphics.setColor(0.9, 0.95, 0.4, (0.05 + 0.10 * pulse) * (0.4 + c.age / c.warn))
      love.graphics.rectangle("fill", c.x0, c.top, c.x1 - c.x0, c.bottom - c.top)
      love.graphics.setColor(1, 0.95, 0.5, 0.45 + 0.4 * pulse)
      love.graphics.rectangle("fill", c.x0, c.bottom - 3, c.x1 - c.x0, 3)
      love.graphics.rectangle("fill", c.x0, c.top, c.x1 - c.x0, 3)
    end
  end
  -- Flames: each cell flickers, hottest (yellow-white) when young
  local frame = floor(t * 14)
  for k, life in pairs(fire) do
    local gx, gy = coords(k)
    if gx >= gx0 and gx <= gx1 and gy >= gy0 and gy <= gy1 then
      -- Tongues that flicker up past the cell top
      local h = 1 + (k * 7 + frame) % 3
      local hot = math.min(1, life * 2)
      love.graphics.setColor(1, 0.35 + 0.35 * hot, 0.1 + 0.15 * hot)
      love.graphics.rectangle("fill", gx * C, gy * C + C - h, C, h)
      if h > 1 then
        love.graphics.setColor(1, 0.85, 0.45, 0.8)
        love.graphics.rectangle("fill", gx * C + (k % 2), gy * C + C - h + 1, 1, h - 1)
      end
    end
  end
  -- Breathing it in tints the whole view a sickly green
  if fluids.exposure > 0.01 then
    love.graphics.setColor(0.55, 0.75, 0.15, 0.13 * fluids.exposure)
    love.graphics.rectangle("fill", view.x, view.y, view.w, view.h)
  end
end

local buildWaterEdge, drawWaterRun -- (defined below)

-- The water's colours: deep in the middle, lighter toward the edges, in fine
-- steps so it reads as a smooth gradient
local WATER_DEEP = { 0.13, 0.31, 0.42 }
local WATER_EDGE = { 0.27, 0.54, 0.56 }
local WATER_BANDS = {} -- { width from each edge in px, colour }, widest first
for k, width in ipairs({ 16, 13, 10, 8, 6, 5, 4, 3, 2, 1 }) do
  local t = k / 10
  WATER_BANDS[k] = {
    width,
    {
      WATER_DEEP[1] + (WATER_EDGE[1] - WATER_DEEP[1]) * t,
      WATER_DEEP[2] + (WATER_EDGE[2] - WATER_DEEP[2]) * t,
      WATER_DEEP[3] + (WATER_EDGE[3] - WATER_DEEP[3]) * t,
    },
  }
end

-- The water's sides: a gradient strip (deep to light, toward the edge) drawn
-- at each end of a run, as one image instead of stacked rectangles
local WATER_ALPHA = 0.74
local edgeImage
local edgeQuads = {}
local EDGE_W = 16
buildWaterEdge = function()
  if edgeImage then
    return
  end
  local data = love.image.newImageData(EDGE_W, 1)
  for x = 0, EDGE_W - 1 do
    -- x px from the edge: the bands' colour at that depth
    local col = WATER_DEEP
    for i = #WATER_BANDS, 1, -1 do
      if x < WATER_BANDS[i][1] then
        col = WATER_BANDS[i][2]
        break
      end
    end
    data:setPixel(x, 0, col[1], col[2], col[3], 1)
  end
  edgeImage = love.graphics.newImage(data)
  edgeImage:setFilter("nearest", "nearest")
  for w = 1, EDGE_W do
    edgeQuads[w] = love.graphics.newQuad(0, 0, w, 1, EDGE_W, 1)
  end
end

-- One pixel row's segment of water, from x0 to x1 (inclusive)
local function drawWaterSegment(x0, x1, py, surfaceRow, t)
  local w = x1 - x0 + 1
  -- (see-through enough that the hunter and fish in it can be made out)
  love.graphics.setColor(WATER_DEEP[1], WATER_DEEP[2], WATER_DEEP[3], WATER_ALPHA)
  love.graphics.rectangle("fill", x0, py, w, 1)
  local bw = math.min(EDGE_W, floor(w / 2))
  if bw > 0 then
    love.graphics.setColor(1, 1, 1, WATER_ALPHA)
    love.graphics.draw(edgeImage, edgeQuads[bw], x0, py)
    love.graphics.draw(edgeImage, edgeQuads[bw], x1 + 1, py, 0, -1, 1)
  end
  if not surfaceRow then
    return
  end
  -- The top row of a cell: a pale rippling line where there is open air above,
  -- a faint grain and now and then a glint in the body
  local aboveRow = floor((py - 1) / C) * K
  local x = x0
  while x <= x1 do
    local cx = floor(x / C)
    local cellEnd = math.min(x1, cx * C + C - 1)
    if water[aboveRow + cx] then
      -- Water above: the body. A faint grain, now and then a glint (per cell)
      local h = (cx * 73856093 + py * 19349663) % 1000
      if h < 70 then
        love.graphics.setColor(0.32, 0.56, 0.58, 0.22)
        love.graphics.rectangle("fill", x, py, cellEnd - x + 1, C)
      elseif h > 985 then
        love.graphics.setColor(0.05, 0.14, 0.2, 0.2)
        love.graphics.rectangle("fill", x, py, cellEnd - x + 1, C)
      end
      if (cx * 73856093 + py * 19349663 + floor(t * 2) * 83492791) % 1000 < 4 then
        love.graphics.setColor(0.80, 0.92, 0.95, 0.8)
        love.graphics.rectangle("fill", x, py, 1, 1)
      end
    else
      -- Open air (or rock) above: the surface, a pale rippling line
      for sx = x, cellEnd do
        if not world:isSolid(sx, py - 1) then
          local off = math.sin(sx * 0.35 + t * 2.2) > 0.5 and 1 or 0
          love.graphics.setColor(0.74, 0.84, 0.76, 0.95)
          love.graphics.rectangle("fill", sx, py + off, 1, 1)
        end
      end
    end
    x = cellEnd + 1
  end
end

local runEdges = {}

-- A run of water cells a..b in grid row gy, drawn a pixel row at a time
drawWaterRun = function(gy, a, b, t)
  local row = gy * K
  -- Which cells of the run touch something other than water (once per run)
  local edges = runEdges
  for gx = a, b do
    local k = row + gx
    edges[gx - a + 1] = not (water[k - K] and water[k + K] and water[k - 1] and water[k + 1])
  end
  for sy = 0, C - 1 do
    local py = gy * C + sy
    local segStart
    -- A rock-centred cell just left of the run lends its open pixels
    local lx = a * C
    if not water[row + a - 1] and solidAt(row + a - 1) then
      while lx > (a - 1) * C and not world:isSolid(lx - 1, py) do
        lx = lx - 1
      end
    end
    local rx = b * C + C - 1
    if not water[row + b + 1] and solidAt(row + b + 1) then
      while rx < (b + 1) * C + C - 1 and not world:isSolid(rx + 1, py) do
        rx = rx + 1
      end
    end
    if lx < a * C then
      segStart = lx
    end
    for gx = a, b do
      local k = row + gx
      if edges[gx - a + 1] then
        for ox = 0, C - 1 do
          local x = gx * C + ox
          local on = not world:isSolid(x, py)
          if on and not segStart then
            segStart = x
          elseif not on and segStart then
            drawWaterSegment(segStart, x - 1, py, sy == 0, t)
            segStart = nil
          end
        end
      elseif not segStart then
        segStart = gx * C -- inside the water: open, no need to look
      end
    end
    if segStart then
      drawWaterSegment(segStart, rx, py, sy == 0, t)
    elseif rx > b * C + C - 1 then
      drawWaterSegment(b * C + C, rx, py, sy == 0, t)
    end
  end
end

-- Water and smoke are drawn in front of the hunter, but lit
function fluids.drawFront(view)
  local gx0, gy0, gx1, gy1 = visibleRange(view)
  local t = love.timer.getTime()
  -- Water, one pixel row at a time: rows of cells are split into runs of
  -- water cells; only cells on the edge of the water (a neighbour without
  -- water) look at the terrain pixel by pixel, so the edges follow the rock
  -- while the body costs next to nothing. Cells the simulation treats as rock
  -- (a solid centre) at the end of a run lend their open pixels to it.
  buildWaterEdge()
  for gy = gy0, gy1 do
    if (waterRows[gy] or 0) > 0 then
      local row = gy * K
      local gx = gx0
      -- (a single-cell dip in the surface, water either side and below,
      -- is drawn filled, so the surface reads as a line rather than notches)
      local function wetCell(c)
        local k = row + c
        return water[k] or (water[k - 1] and water[k + 1] and water[k + K] and not solidAt(k))
      end
      while gx <= gx1 do
        if water[row + gx] then
          local a = gx
          while gx <= gx1 and wetCell(gx) do
            gx = gx + 1
          end
          drawWaterRun(gy, a, gx - 1, t)
        else
          gx = gx + 1
        end
      end
    end
  end
  -- Smoke: single pixels, dithered by density and re-rolled a few times a
  -- second, so it reads as fine drifting grit instead of blocks
  local points = {}
  local frame = floor(t * 6)
  for k, sm in pairs(smoke) do
    local gx = k % K
    local gy = (k - gx) / K
    if gx >= gx0 and gx <= gx1 and gy >= gy0 and gy <= gy1 then
      do
        local density = math.min(0.9, sm)
        for oy = 0, C - 1 do
          for ox = 0, C - 1 do
            local px, py = gx * C + ox, gy * C + oy
            local h = (px * 73856093 + py * 19349663 + frame * 83492791) % 1000 / 1000
            if h < density and not world:isSolid(px, py) then
              local g = 0.26 + h * 0.18
              points[#points + 1] = { px + 0.5, py + 0.5, g, g * 0.97, g * 1.03, 0.45 + 0.3 * (1 - h) }
            end
          end
        end
      end
    end
  end
  if #points > 0 then
    love.graphics.points(points)
  end
end

-- Gas glows faintly, flames light the dark, vents shine
function fluids.addLights(lighting, view)
  local gx0, gy0, gx1, gy1 = visibleRange(view)
  local lights = 0
  for gy = gy0 - 12, gy1 + 12, 12 do
    for gx = gx0 - 12, gx1 + 12, 12 do
      local c = gas[key(gx, gy)]
      if c and c > 0.3 and lights < 16 then
        lights = lights + 1
        lighting.add(gx * C, gy * C, 34, 0.70, 0.90, 0.30, 0.3)
      end
    end
  end
  for _, v in ipairs(vents) do
    if v.x > view.x - 40 and v.x < view.x + view.w + 40 and v.y > view.y - 40 and v.y < view.y + view.h + 40 then
      lighting.add(v.x, v.y - 4, 26, 0.85, 0.95, 0.35, 0.45)
    end
  end
  local n = 0
  for k, life in pairs(fire) do
    local gx, gy = coords(k)
    if gx >= gx0 and gx <= gx1 and gy >= gy0 and gy <= gy1 and (k % 7 == 0 or life > 0.6) and n < 30 then
      n = n + 1
      lighting.add(gx * C + HALF, gy * C, 30, 1, 0.6, 0.25, 0.55)
    end
  end
end

return fluids
