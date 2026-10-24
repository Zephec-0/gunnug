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
--   oil    lamp oil: flows like water but floats on it (it can't enter a water
--          cell), and burns: any flame, spark or blast that reaches it lights
--          it, and the fire runs through the whole slick, each cell burning
--          for a second or two. Spilled by lanterns that are shot.
-- Terrain is read from the world; nothing here changes it.
local audio = require("src.audio")
local effects = require("src.effects")
local materials = require("src.materials")
local perks = require("src.perks")

local fluids = {}

local C = 2 -- cell size in pixels
local HALF = C / 2
local POOL_CELL = 4 -- cavegen's pools come on a coarser grid: each of its cells fills several of ours
local WATER_STEP = 0.025 -- water moves a cell per step: 80 px/s falling
local SPREAD = 12 -- water slides sideways toward a drop up to this many cells away
local SWEEP = 1.5 -- every so often all water near the hunter is woken (terrain may have changed)
local K = 16384 -- key stride: key = gy * K + KOFF + gx (gx may be negative; KOFF keeps the sum clear of the row below)
local KOFF = 8192
local RANGE_X, RANGE_Y = 400, 270 -- the simulated region around the hunter

local GAS_COLOR = { 0.72, 0.86, 0.26 }
local TICK = 0.5 -- seconds between damage ticks while in gas or fire
local GAS_DAMAGE = 3
local FIRE_DAMAGE = 5
local DROWN_DAMAGE = 4 -- per tick (every half second) once the breath has run out
local BREATH_BUBBLES = 3 -- bubbles over his head; one pops each second he is under

local world
local gas, water, fire, smoke = {}, {}, {}, {}
local addJobs = {} -- areas' pools still being added (see fluids.add)
local oil, oilActive, oilRows = {}, {}, {} -- lamp oil: cells (true), the ones that may move, and counts per row
-- Lava (the `lava` set below) flows like water, a fifth as fast. Its state is
-- one table: fluids.update already has as many upvalues as Lua allows.
local lavaFlow = {
  active = {}, -- the cells that may move
  rows = {}, -- counts per row
  every = 5, -- one lava step per this many water steps
  tick = 0,
  moved = false,
}
local dry = {} -- cells water may not enter (shop rooms in a flooded area)
-- Flooded areas (and lakes) are not filled all at once: their water is kept
-- as runs per grid row and becomes real water cells only near the hunter
-- (fluids.update fills the rows around him, a few thousand cells a frame).
-- Filling every flooded area made a table of 1.4 million cells, tripled the
-- Lua heap and made every garbage collection a long pause.
local floodRows = {} -- grid row -> list of { gx0, gx1, top } runs not yet filled
local FLOOD_BUDGET = 6000 -- cells filled per frame at most
local lava, acid = {}, {} -- pools that stay where they are (cells keyed like the rest), and their surface spots
local acidRows = {} -- grid row -> how many acid cells it holds (see setAcid)
local lavaTop, acidTop = {}, {} -- { x, y } of cells with open air above, every few px: lights and bubbles
local LAVA_DAMAGE, ACID_DAMAGE = 10, 6
local liquidTimer = 0
local addStatic -- (defined with the setup functions below)
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

-- (declared here, above fluids.clear, so that clear really resets them: they were once declared lower down,
-- where clear's assignments only made globals, and the water cached from the last run was drawn on into the
-- next one: pools floating in thin air where the new world has none)
local blockVer = {}
local runCache, runCacheCount = {}, 0

function fluids.clear()
  gas, water, fire, smoke, vents, braziers, columns = {}, {}, {}, {}, {}, {}, {}
  fluids.gasDwell = 0
  oil, oilActive, oilRows = {}, {}, {}
  lavaFlow.active, lavaFlow.rows, lavaFlow.tick, lavaFlow.moved = {}, {}, 0, false
  addJobs = {}
  lava, acid, lavaTop, acidTop = {}, {}, {}, {}
  acidRows = {}
  dry, floodRows = {}, {}
  blockVer = {}
  runCache, runCacheCount = {}, 0
  active, waterRows, gasRows = {}, {}, {}
  gasTimer, fireTimer, drownTimer = TICK, TICK, TICK
  breathPlayer = nil
  fluids.exposure = 0
  world = nil
end

local floor = math.floor

local function key(gx, gy)
  return gy * K + KOFF + gx
end

local function cellOf(x, y)
  return key(floor(x / C), floor(y / C))
end

local function coords(k)
  local gx = k % K
  return gx - KOFF, (k - gx) / K
end

local function solidAt(k)
  local gx, gy = coords(k)
  return world:isSolid(gx * C + HALF, gy * C + HALF)
end

local function rowOf(k)
  return (k - k % K) / K
end

-- Every change to water or gas goes through these, to keep the row counts
-- Per stretch of WATER_BLOCK cells of a row: bumped whenever its water changes (the drawing caches its
-- runs by it). Per stretch rather than per row, so water pouring through a gap only has its own part of
-- each row worked out again, not the whole width of the view.
local WATER_BLOCK = 64 -- (K and KOFF are multiples of it, so floor(k / WATER_BLOCK) names the stretch)
-- (blockVer: see the top of the file)

local function setWater(k, v)
  local bk = floor(k / WATER_BLOCK)
  blockVer[bk] = (blockVer[bk] or 0) + 1
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

local function setOil(k, v)
  local had = oil[k] ~= nil
  if v and not had then
    local r = rowOf(k)
    oilRows[r] = (oilRows[r] or 0) + 1
  elseif not v and had then
    local r = rowOf(k)
    oilRows[r] = oilRows[r] - 1
  end
  oil[k] = v or nil
end

local function setLava(k, v)
  local had = lava[k] ~= nil
  if v and not had then
    local r = rowOf(k)
    lavaFlow.rows[r] = (lavaFlow.rows[r] or 0) + 1
  elseif not v and had then
    local r = rowOf(k)
    lavaFlow.rows[r] = lavaFlow.rows[r] - 1
  end
  lava[k] = v or nil
end

-- (acid never drains away: its cells are only ever added)
local function setAcid(k)
  if not acid[k] then
    local r = rowOf(k)
    acidRows[r] = (acidRows[r] or 0) + 1
    acid[k] = true
  end
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
  return not water[k] and not lava[k] and not acid[k] and not solidAt(k)
end

-- Setup ----------------------------------------------------------------------

-- Adds an area's pools: info.gas and info.water from cavegen (lists of pools,
-- each { cells = { x, y, ... } top-left pixel corners of C-px cells, vent })
-- Adding an area's pools is spread over frames (src.fluids.update runs the
-- queued jobs for ~1.5 ms a frame): done at once it was a 20-30 ms hitch
-- whenever an area finished generating.
local ADD_BUDGET = 0.0015
local addDeadline = 0
local function pause()
  if os.clock() > addDeadline then
    coroutine.yield()
  end
end

local addNow
function fluids.add(w, info)
  world = w
  addJobs[#addJobs + 1] = coroutine.create(function()
    addNow(info)
  end)
end

-- Runs the queued pool jobs for up to `budget` seconds (all of them if budget is nil)
function fluids.runJobs(budget)
  addDeadline = budget and (os.clock() + budget) or math.huge
  while addJobs[1] do
    local ok, err = coroutine.resume(addJobs[1])
    if not ok then
      error(debug.traceback(addJobs[1], err))
    end
    if coroutine.status(addJobs[1]) == "dead" then
      table.remove(addJobs, 1)
    else
      return
    end
  end
end

addNow = function(info)
  local sub = POOL_CELL / C
  for _, p in ipairs(info.gas or {}) do
    pause()
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
  -- Shop rooms stay dry in a flooded area (only there: elsewhere water never reaches them)
  if info.flood then
    for _, room in ipairs(info.shops or {}) do
      for gy = floor((room.y - 6) / C), floor((room.y + room.h + 6) / C) do
        for gx = floor((room.x - 6) / C), floor((room.x + room.w + 6) / C) do
          dry[key(gx, gy)] = true
        end
      end
    end
    local topRow = floor(info.flood.top / C)
    for i, r in ipairs(info.flood.runs) do
      local list = floodRows[r[1]] or {}
      floodRows[r[1]] = list
      list[#list + 1] = { r[2], r[3], r[1] == topRow }
      if i % 2000 == 0 then
        pause()
      end
    end
  end
  addStatic(lava, info.lava, lavaTop, setLava)
  addStatic(acid, info.acid, acidTop, setAcid)
  -- (pools start asleep: the periodic sweep wakes the water near the hunter
  -- that can move; marking every pool active made each water step walk all
  -- the water in the world)
  for _, p in ipairs(info.water or {}) do
    pause()
    for i = 1, #p.cells, 2 do
      local gx, gy = p.cells[i] / C, p.cells[i + 1] / C
      for oy = 0, sub - 1 do
        for ox = 0, sub - 1 do
          local k = key(gx + ox, gy + oy)
          if not solidAt(k) then
            setWater(k, true)
          end
        end
      end
    end
  end
end

-- Fills a static liquid's cells from cavegen's pools and notes its surface spots
addStatic = function(cells, pools, tops, setter)
  local sub = POOL_CELL / C
  local added = {} -- (only this area's new cells are looked at for surface spots)
  for _, p in ipairs(pools or {}) do
    pause()
    for i = 1, #p.cells, 2 do
      local gx, gy = p.cells[i] / C, p.cells[i + 1] / C
      for oy = 0, sub - 1 do
        for ox = 0, sub - 1 do
          local k = key(gx + ox, gy + oy)
          if not solidAt(k) then
            if setter then
              setter(k, true)
            else
              cells[k] = true
            end
            added[#added + 1] = k
          end
        end
      end
    end
  end
  for _, k in ipairs(added) do
    if not cells[k - K] and not solidAt(k - K) and k % 4 == 0 then
      local gx, gy = coords(k)
      tops[#tops + 1] = { gx * C + HALF, gy * C }
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

-- Floods every open cell in the box (x0..x1, y0..y1) a slice at a time, from
-- the world as it is now (a lake in a hollow of the ground)
function fluids.floodBox(w, x0, y0, x1, y1)
  world = world or w
  local runs = {}
  for gy = floor(y0 / C), floor(y1 / C) do
    local start
    for gx = floor(x0 / C), floor(x1 / C) do
      local open_ = not w:isSolid(gx * C + HALF, gy * C + HALF)
      if open_ and not start then
        start = gx
      elseif not open_ and start then
        runs[#runs + 1] = { gy, start, gx - 1 }
        start = nil
      end
    end
    if start then
      runs[#runs + 1] = { gy, start, floor(x1 / C) }
    end
  end
  local topRow = floor(y0 / C)
  for _, r in ipairs(runs) do
    local list = floodRows[r[1]] or {}
    floodRows[r[1]] = list
    list[#list + 1] = { r[2], r[3], r[1] == topRow }
  end
end

-- Fills the flood runs that lie in the given grid box (outward from row
-- `midRow`), up to `budget` cells; the parts of a run outside the box wait
local function fillFlood(gx0, gy0, gx1, gy1, midRow, budget)
  if next(floodRows) == nil then
    return
  end
  for step = 0, math.max(midRow - gy0, gy1 - midRow) do
    for side = -1, 1, 2 do
      local gy = midRow + step * side
      if not (step == 0 and side == 1) and gy >= gy0 and gy <= gy1 then
        local list = floodRows[gy]
        if list then
          for i = #list, 1, -1 do
            local r = list[i]
            if r[2] >= gx0 and r[1] <= gx1 then
              local a, b = math.max(r[1], gx0), math.min(r[2], gx1)
              table.remove(list, i)
              if r[1] < a then
                list[#list + 1] = { r[1], a - 1, r[3] }
              end
              if r[2] > b then
                list[#list + 1] = { b + 1, r[2], r[3] }
              end
              for gx = a, b do
                local k = gy * K + KOFF + gx
                if not dry[k] and not water[k] then
                  setWater(k, true)
                  if r[3] then
                    active[k] = true
                  end
                end
              end
              budget = budget - (b - a + 1)
              if budget <= 0 then
                return
              end
            end
          end
          if #list == 0 then
            floodRows[gy] = nil
          end
        end
      end
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

-- Oil catching: the cell's oil turns into a flame that burns a while
local function igniteOil(k)
  setOil(k, nil)
  oilActive[k] = nil
  fire[k] = 1.1 + love.math.random() * 1.1
  smoke[k - K] = math.min(1, (smoke[k - K] or 0) + 0.3)
end

-- Spills `cells` cells of oil at (x, y): each goes into the nearest free cell
-- around it, and they all start to flow
function fluids.addOil(x, y, cells)
  if not world or cells <= 0 then
    return 0
  end
  local cx, cy = floor(x / C), floor(y / C)
  local placed = 0
  for ring = 0, 6 do
    for dy = -ring, ring do
      for dx = -ring, ring do
        if placed < cells and (math.abs(dx) == ring or math.abs(dy) == ring) then
          local k = key(cx + dx, cy + dy)
          if not oil[k] and not water[k] and not lava[k] and not acid[k] and open(k) then
            if fire[k] then
              fire[k] = math.max(fire[k], 1.2) -- (spilled straight into a flame: it burns)
            else
              setOil(k, true)
              oilActive[k] = true
            end
            placed = placed + 1
          end
        end
      end
    end
    if placed >= cells then
      break
    end
  end
  return placed
end

-- A burst of flame (a lantern breaking): a ball of fire cells round (x, y)
-- that lights any oil and gas it touches
function fluids.fireBurst(x, y, radius)
  if not world then
    return
  end
  local r = floor(radius / C)
  local cx, cy = floor(x / C), floor(y / C)
  for dy = -r, r do
    for dx = -r, r do
      if dx * dx + dy * dy <= r * r then
        local k = key(cx + dx, cy + dy)
        if oil[k] then
          igniteOil(k)
        elseif gas[k] then
          igniteCell(k, gas[k])
        elseif open(k) and love.math.random() < 0.7 then
          fire[k] = math.max(fire[k] or 0, 0.3 + love.math.random() * 0.4)
        end
      end
    end
  end
  fluids.addSmoke(x, y - radius, 0.5)
end

function fluids.oilAt(x, y)
  return oil[cellOf(x, y)] == true
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
      if oil[k] then
        igniteOil(k)
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
        if oil[k] then
          igniteOil(k)
        elseif c then
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

local lastPlayer, lastEnemies -- set each frame by fluids.update (for zap)

-- Shock rounds into water: the whole connected body of it (up to a cap of
-- cells) is charged, hurting everything standing or swimming in it
local ZAP_CELLS = 2500
function fluids.zap(x, y, damage)
  local start = cellOf(x, y)
  if not water[start] then
    return
  end
  local set, queue, head, n = { [start] = true }, { start }, 1, 1
  while head <= #queue and n < ZAP_CELLS do
    local k = queue[head]
    head = head + 1
    for _, d in ipairs({ 1, -1, K, -K }) do
      local nk = k + d
      if water[nk] and not set[nk] then
        set[nk] = true
        queue[#queue + 1] = nk
        n = n + 1
      end
    end
  end
  local r = love.math.random
  -- crackling sparks over the water's cells
  for _ = 1, math.min(60, #queue) do
    local gx, gy = coords(queue[r(#queue)])
    effects.particle(gx * C + HALF, gy * C + HALF, (r() - 0.5) * 30, -10 - r() * 30, 0.35, { 0.65, 0.8, 1 }, 0, true)
  end
  effects.ring(x, y, 18, { 0.6, 0.7, 1 })
  audio.playAt("steam_hiss", x, y, 0.5)
  local dmg = math.max(6, math.floor(damage * 1.5 + 0.5))
  local function wet(body)
    return set[cellOf(body.x + body.w / 2, body.y + body.h - 2)] or set[cellOf(body.x + body.w / 2, body.y + body.h / 2)]
  end
  for _, e in ipairs(lastEnemies and lastEnemies.nearby() or {}) do
    if not e.dead and wet(e.body) then
      lastEnemies.damage(e, dmg, 0, 0, 0, false, nil)
      e.zap = 0.5
    end
  end
  local p = lastPlayer
  if p and not p.dead and wet(p.body) then
    p:hurtOverTime(math.max(2, math.floor(dmg / 3)), { 0.65, 0.8, 1 }, "shock")
  end
end

-- Frost rounds into water: the surface around the hit freezes into a skin of
-- ice the hunter can stand on (it can be dug through)
function fluids.freeze(x, y)
  local k0 = cellOf(x, y)
  if not water[k0] then
    return
  end
  local top = k0
  while water[top - K] do
    top = top - K
  end
  local frozen = false
  local ix0, iy0, ix1, iy1 = math.huge, math.huge, -math.huge, -math.huge
  for dx = -7, 7 do
    local k = top + dx
    -- the surface at that column: up or down a few cells to find it
    local found
    for off = -3, 3 do
      local kk = k + off * K
      if water[kk] and not water[kk - K] then
        found = kk
        break
      end
    end
    if found then
      for layer = 0, 1 do
        local kk = found + layer * K
        if water[kk] then
          setWater(kk, nil)
          local gx, gy = coords(kk)
          for py = gy * C, gy * C + C - 1 do
            for px = gx * C, gx * C + C - 1 do
              world:set(px, py, materials.ICE)
            end
          end
          ix0, iy0 = math.min(ix0, gx * C), math.min(iy0, gy * C)
          ix1, iy1 = math.max(ix1, gx * C + C), math.max(iy1, gy * C + C)
          frozen = true
        end
      end
    end
  end
  if frozen then
    local r = love.math.random
    for _ = 1, 14 do
      effects.particle(ix0 + r() * (ix1 - ix0), iy0, (r() - 0.5) * 24, -8 - r() * 20, 0.6, { 0.78, 0.93, 1 }, 60, true)
    end
    effects.ring(x, y, 14, { 0.75, 0.92, 1 })
    pcall(function()
      world:repaintRegion(ix0 - 2, iy0 - 2, ix1 + 2, iy1 + 2)
      require("src.physics").rebuildRegion(ix0 - 2, iy0 - 2, ix1 + 2, iy1 + 2)
    end)
  end
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
    if (waterRows[gy] or 0) + (oilRows[gy] or 0) + (lavaFlow.rows[gy] or 0) > 0 then
      for gx = gx0, gx1 do
        local k = gy * K + KOFF + gx
        if water[k] then
          active[k] = true
        end
        if oil[k] then
          oilActive[k] = true
        end
        if lava[k] then
          lavaFlow.active[k] = true
        end
      end
    end
  end
end

function fluids.lavaAt(x, y)
  return lava[cellOf(x, y)] == true
end

function fluids.acidAt(x, y)
  return acid[cellOf(x, y)] == true
end

-- A random point of `kind` ("water" or "fire") within r of (x, y), or nil
function fluids.probe(kind, x, y, r)
  local rnd = love.math.random
  if kind == "fire" then
    for _, br in ipairs(braziers) do
      local bx, by = coords(br.k)
      bx, by = bx * C, by * C
      if math.abs(bx - x) < r and math.abs(by - y) < r then
        return bx, by
      end
    end
  end
  local set = kind == "water" and water or fire
  for _ = 1, 24 do
    local px, py = x + (rnd() * 2 - 1) * r, y + (rnd() * 2 - 1) * r
    if set[cellOf(px, py)] then
      return px, py
    end
  end
  return nil
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

-- The simulated region: what the camera shows (at any zoom, wherever it leans or a boss fight pulls
-- it) plus VIEW_MARGIN px all round, so liquids are already moving before they come into view; and
-- always a box round the hunter himself. Gas is stepped over a tighter margin (GAS_MARGIN).
local VIEW_MARGIN, GAS_MARGIN = 128, 48
local camera = require("src.camera")
local config = require("src.config")
local function region(px, py)
  local x0, y0 = camera.x - VIEW_MARGIN, camera.y - VIEW_MARGIN
  local x1, y1 = camera.x + config.VIRTUAL_W + VIEW_MARGIN, camera.y + config.VIRTUAL_H + VIEW_MARGIN
  x0, y0 = math.min(x0, px - 200), math.min(y0, py - 150)
  x1, y1 = math.max(x1, px + 200), math.max(y1, py + 150)
  return floor(x0 / C), floor(y0 / C), floor(x1 / C), floor(y1 / C)
end

-- Gas diffuses toward emptier neighbours: slowly sideways, faster down, a
-- little up. Thin traces vanish. (The weights are for 2-px cells.)
local GAS_OFFSETS = { K, -1, 1, -K }
-- (a sweep of the whole cloud every 0.15 s, not 0.1: the weights and the thinning are scaled up to match, so it spreads and
-- thins at the same speed with a third less work)
local GAS_SWEEP = 0.15
local GAS_WEIGHTS = { 0.24 * 1.5, 0.14 * 1.5, 0.14 * 1.5, 0.08 * 1.5 }
-- The gas is stepped a band of rows at a time, one band a frame (a whole sweep takes 0.1 s, as it always
-- did): all of it in one go was a spike of 20+ ms ten times a second. The scratch tables are kept, not
-- rebuilt, so a big cloud makes no garbage either.
local GAS_SLICES = 6
local GS = { slice = 0, acc = 0, delta = {}, keys = {}, open = {}, okeys = {}, bounds = {} }
local function stepGas(gx0, gy0, gx1, gy1)
  GS.slice = GS.slice % GAS_SLICES + 1
  if GS.slice == 1 then
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
  end
  if GS.slice == 1 then
    -- The bands hold equal amounts of gas, not equal numbers of rows: a cloud in one band would
    -- make that frame several times dearer than the others
    local total = 0
    for gy = gy0, gy1 do
      total = total + (gasRows[gy] or 0)
    end
    local per, acc, n, bd = total / GAS_SLICES, 0, 1, GS.bounds
    bd[0] = gy0 - 1
    for gy = gy0, gy1 do
      acc = acc + (gasRows[gy] or 0)
      if n < GAS_SLICES and acc >= per * n then
        bd[n] = gy
        n = n + 1
      end
    end
    for i = n, GAS_SLICES do
      bd[i] = gy1
    end
  end
  local ra, rb = GS.bounds[GS.slice - 1] + 1, GS.bounds[GS.slice]
  local delta, keys, nk = GS.delta, GS.keys, 0
  local openCache, okeys, no = GS.open, GS.okeys, 0
  for gy = ra, rb do
    if (gasRows[gy] or 0) > 0 then
      local row = gy * K + KOFF
      local rowWater = (waterRows[gy] or 0) > 0
      for gx = gx0, gx1 do
        local k = row + gx
        local c = gas[k]
        if c then
          if rowWater and water[k] then
            setGas(k, nil)
          else
            -- (gas also slowly thins out on its own: without this, a big cloud in a closed
            -- room, the Queen's arena, levels off at a faint plateau and never goes)
            local dk = delta[k]
            if dk == nil then
              nk = nk + 1
              keys[nk] = k
              dk = 0
            end
            dk = dk - (c * 0.009 + 0.0009)
            delta[k] = dk
            for i = 1, 4 do
              local nb = k + GAS_OFFSETS[i]
              local diff = c - (gas[nb] or 0)
              if diff > 0.012 then
                local o = openCache[nb]
                if o == nil then
                  o = open(nb)
                  openCache[nb] = o
                  no = no + 1
                  okeys[no] = nb
                end
                if o then
                  local f = diff * GAS_WEIGHTS[i]
                  delta[k] = delta[k] - f
                  local dn = delta[nb]
                  if dn == nil then
                    nk = nk + 1
                    keys[nk] = nb
                    dn = 0
                  end
                  delta[nb] = dn + f
                end
              end
            end
          end
        end
      end
    end
  end
  for i = 1, nk do
    local k = keys[i]
    local v = (gas[k] or 0) + delta[k]
    setGas(k, (v >= 0.012) and math.min(1, v) or nil)
    delta[k] = nil
    keys[i] = nil
  end
  for i = 1, no do
    openCache[okeys[i]] = nil
    okeys[i] = nil
  end
end

-- Called every frame: steps as many bands as the time allows (one a frame at 60 fps)
local function stepGasFrame(dt, gx0, gy0, gx1, gy1)
  GS.acc = GS.acc + dt
  local steps = 0
  while GS.acc >= GAS_SWEEP / GAS_SLICES and steps < 3 do
    GS.acc = GS.acc - GAS_SWEEP / GAS_SLICES
    steps = steps + 1
    stepGas(gx0, gy0, gx1, gy1)
  end
  GS.acc = math.min(GS.acc, GAS_SWEEP / GAS_SLICES)
end

-- Flames: ignite neighbouring gas (reaching two cells, so a burning cloud
-- flares across quickly), die down, leave smoke, and are put out by water
local FIRE_REACH = { -1, 1, -K, K, -2, 2, -2 * K, 2 * K, -3, 3, -4, 4, -3 * K, -4 * K }
local OIL_REACH = { -1, 1, K, -K, K - 1, K + 1 }
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
        -- burning oil spreads to the oil next to it, quickly but not at once
        for _, d in ipairs(OIL_REACH) do
          if oil[k + d] and r() < 0.55 then
            igniteOil(k + d)
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
local smokeCells = {} -- (kept from step to step)
local function stepSmoke(gx0, gy0, gx1, gy1)
  local cells = smokeCells
  for i = #cells, 1, -1 do
    cells[i] = nil
  end
  for k in pairs(smoke) do
    local gx, gy = coords(k)
    if gx >= gx0 and gx <= gx1 and gy >= gy0 and gy <= gy1 then
      cells[#cells + 1] = k
    end
  end
  local r = love.math.random
  for _, k in ipairs(cells) do
    local v = smoke[k]
    if v then
      v = v * 0.965 - 0.005 -- (fades quickly: thick smoke was a lag source)
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
-- During a water step the terrain can't change, and the sideways scans ask about the same cells over
-- and over: the step remembers what it learned about each cell's rock (see stepWater)
local solidMemo, memoOn = {}, false
local function free(k)
  if water[k] or oil[k] or lava[k] or acid[k] or dry[k] then
    return false
  end
  if memoOn then
    local v = solidMemo[k]
    if v == nil then
      v = solidAt(k) and true or false
      solidMemo[k] = v
    end
    return not v
  end
  return not solidAt(k)
end

-- Oil flows the same way, but it can't push into water, so it settles on top
local function stepOil(gx0, gy0, gx1, gy1)
  local r = love.math.random
  local list = {}
  for k in pairs(oilActive) do
    local gx, gy = coords(k)
    if gx >= gx0 and gx <= gx1 and gy >= gy0 and gy <= gy1 then
      list[#list + 1] = k
    else
      oilActive[k] = nil
    end
  end
  if #list == 0 then
    return
  end
  table.sort(list, function(a, b)
    return a > b
  end)
  local moved = {}
  local function move(k, n)
    setOil(k, nil)
    setOil(n, true)
    moved[n] = true
    oilActive[k] = nil
    oilActive[n] = true
    for _, d in ipairs(NEIGHBOURS) do
      if oil[k + d] then
        oilActive[k + d] = true
      end
    end
  end
  for _, k in ipairs(list) do
    if oil[k] and not moved[k] then
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
        oilActive[k] = nil
      end
    elseif not oil[k] then
      oilActive[k] = nil
    end
  end
end

-- Lava flows the same way too (see lavaFlow.every), and likewise can't push into water
function lavaFlow.step(gx0, gy0, gx1, gy1)
  local r = love.math.random
  local list = {}
  for k in pairs(lavaFlow.active) do
    local gx, gy = coords(k)
    if gx >= gx0 and gx <= gx1 and gy >= gy0 and gy <= gy1 then
      list[#list + 1] = k
    else
      lavaFlow.active[k] = nil
    end
  end
  if #list == 0 then
    return
  end
  table.sort(list, function(a, b)
    return a > b
  end)
  local moved = {}
  local function move(k, n)
    setLava(k, nil)
    setLava(n, true)
    moved[n] = true
    lavaFlow.active[k] = nil
    lavaFlow.active[n] = true
    lavaFlow.moved = true
    if n % 4 == 0 and not lava[n - K] and not solidAt(n - K) and #lavaTop < 900 then
      local ngx, ngy = coords(n)
      lavaTop[#lavaTop + 1] = { ngx * C + HALF, ngy * C }
    end
    for _, d in ipairs(NEIGHBOURS) do
      if lava[k + d] then
        lavaFlow.active[k + d] = true
      end
    end
  end
  for _, k in ipairs(list) do
    if lava[k] and not moved[k] then
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
        lavaFlow.active[k] = nil
      end
    elseif not lava[k] then
      lavaFlow.active[k] = nil
    end
  end
end

-- Surface spots (for light and bubbles) that the lava has left are dropped
function lavaFlow.prune()
  local out = 0
  for i = 1, #lavaTop do
    local spot = lavaTop[i]
    local k = cellOf(spot[1], spot[2])
    if lava[k] and not lava[k - K] then
      out = out + 1
      lavaTop[out] = spot
    end
  end
  for i = #lavaTop, out + 1, -1 do
    lavaTop[i] = nil
  end
end

-- (its lists and the sort orders are kept from step to step: a pouring pool is thousands of cells a step,
-- and a new table or two for each was a stream of garbage)
local stepList, stepMoved = {}, {}
-- The cells a move can free up: water falls, slides diagonally down and runs along its own row, so
-- emptying a cell only helps the three cells over it and the two beside it. (The three under it used to
-- be woken too, only to look around, find nothing and go back to sleep: most of a pouring pool's cost.)
local UPWARD = { -K - 1, -K, -K + 1, -1, 1 }
local function moveWater(k, n)
  setWater(k, nil)
  setWater(n, true)
  stepMoved[n] = true
  if gas[n] then
    setGas(n, nil)
  end
  fire[n] = nil
  active[k] = nil
  active[n] = true
  for i = 1, 5 do
    local c = k + UPWARD[i]
    if water[c] then
      active[c] = true
    end
  end
end
-- A step is begun (the cells to move, in order) and then worked through a budget of cells at a time,
-- spread over the frames until the next step is due: a pool pouring through a gap is thousands of
-- cells a step, and doing them all in one frame was a stutter 40 times a second. With the budget the
-- water moves exactly as before; only a really huge flood, more than the budget can keep up with,
-- flows a little slower instead of dragging the frame rate down.
local stepPos, stepEnd, stepRight, rowStart, rowEnd, stepRow -- (where the step being worked through is)
local stepping = false
local function beginWaterStep(gx0, gy0, gx1, gy1)
  local r = love.math.random
  local list = stepList
  for i = #list, 1, -1 do
    list[i] = nil
  end
  for k in pairs(active) do
    local gx, gy = coords(k)
    if gx >= gx0 and gx <= gx1 and gy >= gy0 and gy <= gy1 then
      list[#list + 1] = k
    else
      active[k] = nil -- (out of range: the sweep wakes it again when the hunter is near)
    end
  end
  if #list == 0 then
    return
  end
  -- Bottom rows first; each row swept left or right at random. (Sorted with the plain numeric order,
  -- which is far quicker than a comparison function, then walked in the order wanted: from the end for
  -- bottom rows first and right to left, or row by row from the bottom, each row left to right.)
  stepRight = r() < 0.5
  table.sort(list)
  for k in pairs(stepMoved) do
    stepMoved[k] = nil
  end
  stepPos, stepRow = #list, nil
  stepping = true
end

-- Is there a drop within SPREAD cells along the row toward d, with open water-free cells all the way?
local function slidesToward(k, d)
  for i = 1, SPREAD do
    local c = k + d * i
    if not free(c) then
      return false
    end
    if free(c + K) then
      return true
    end
  end
  return false
end

-- Works through up to `budget` cells of the step under way; returns how many it did
local function continueWaterStep(budget)
  local r = love.math.random
  local list, moved = stepList, stepMoved
  for k in pairs(solidMemo) do
    solidMemo[k] = nil -- (the terrain may have changed since the last frame)
  end
  memoOn = true
  local done_ = 0
  while done_ < budget do
    local k
    if stepRight then
      if stepPos < 1 then
        stepping = false
        break
      end
      k = list[stepPos]
      stepPos = stepPos - 1
    else
      if not stepRow or stepRow > rowEnd then
        if stepPos < 1 then
          stepping = false
          break
        end
        local row = list[stepPos] - list[stepPos] % K
        rowEnd = stepPos
        while stepPos >= 1 and list[stepPos] - list[stepPos] % K == row do
          stepPos = stepPos - 1
        end
        rowStart = stepPos + 1
        stepRow = rowStart
      end
      k = list[stepRow]
      stepRow = stepRow + 1
    end
    done_ = done_ + 1
    -- (straight-line code: the little two-way loops this used to be made LuaJIT give up compiling
    -- the step, and run it in the interpreter, several times slower)
    if water[k] and not moved[k] then
      local below = k + K
      if free(below) then
        moveWater(k, below)
      else
        local side = r() < 0.5 and -1 or 1
        if free(below + side) and free(k + side) then
          moveWater(k, below + side)
        elseif free(below - side) and free(k - side) then
          moveWater(k, below - side)
        elseif slidesToward(k, side) then
          moveWater(k, k + side)
        elseif slidesToward(k, -side) then
          moveWater(k, k - side)
        else
          active[k] = nil
        end
      end
    elseif not water[k] then
      active[k] = nil
    end
  end
  memoOn = false
  return done_
end

-- Lava and acid ----------------------------------------------------------------------

-- The things lava and acid do, a few times a second: hurt whatever stands in
-- them, ignite gas over lava, boil away water that touches it, burn and
-- dissolve wood, and bubble
-- The liquids' steps for this frame: water a budget of cells at a time (see beginWaterStep), oil and
-- lava whenever a water step begins
local function runSteps(dt, gx0, gy0, gx1, gy1)
  accWater = accWater + dt
  local steps = 0
  -- (the budget scales with the frame's length: about 120,000 cells a second, at least 800 a frame)
  local budget = math.max(800, math.floor(120000 * dt))
  while budget > 0 do
    if stepping then
      budget = budget - continueWaterStep(budget)
    end
    if stepping or accWater < WATER_STEP or steps >= 2 then
      break
    end
    accWater = accWater - WATER_STEP
    steps = steps + 1
    beginWaterStep(gx0, gy0, gx1, gy1)
    if next(oilActive) then
      stepOil(gx0, gy0, gx1, gy1)
    end
    lavaFlow.tick = lavaFlow.tick + 1
    if lavaFlow.tick >= lavaFlow.every then
      lavaFlow.tick = 0
      if next(lavaFlow.active) then
        lavaFlow.step(gx0, gy0, gx1, gy1)
      end
    end
  end
  accWater = math.min(accWater, WATER_STEP)
end

function fluids.updateLiquids(dt, player, enemies, px, py, b, gx0, gy0, gx1, gy1)
  if next(lava) == nil and next(acid) == nil then
    return
  end
  liquidTimer = liquidTimer + dt
  if liquidTimer < 0.1 then
    return
  end
  local step = liquidTimer
  liquidTimer = 0
  local r = love.math.random
  local bodyCells = { cellOf(px, b.y + b.h - 3), cellOf(px, py), cellOf(px, b.y + 4) }
  -- The hunter
  local inLava, inAcid = false, false
  if not player.dead then
    for _, k in ipairs(bodyCells) do
      inLava = inLava or lava[k] == true
      inAcid = inAcid or acid[k] == true
    end
  end
  player.inLava = inLava
  if inLava then
    player.lavaTimer = (player.lavaTimer or 0) - step
    if player.lavaTimer <= 0 then
      player.lavaTimer = 0.3
      player:hurtOverTime(LAVA_DAMAGE, { 1, 0.5, 0.15 }, "lava")
      audio.play("hurt", 0.35)
      for _ = 1, 6 do
        effects.particle(px + (r() - 0.5) * 6, py + (r() - 0.5) * 8, (r() - 0.5) * 60, -30 - r() * 60, 0.5, { 1, 0.55 + r() * 0.3, 0.15 }, 200, true)
      end
    end
  elseif inAcid then
    player.acidTimer = (player.acidTimer or 0) - step
    if player.acidTimer <= 0 then
      player.acidTimer = 0.4
      player:hurtOverTime(ACID_DAMAGE, { 0.7, 1, 0.3 }, "acid")
      audio.play("hurt", 0.3)
      for _ = 1, 5 do
        effects.particle(px + (r() - 0.5) * 6, py + (r() - 0.5) * 8, (r() - 0.5) * 30, -20 - r() * 40, 0.5, { 0.7, 1, 0.3 }, -20, true)
      end
    end
  end
  -- Monsters (flying ones never touch it; the fireproof shrug lava off)
  if enemies then
    for _, e in ipairs(enemies.nearby()) do
      local eb = e.body
      if not e.dead and e.def.ground and math.abs(eb.x - px) < RANGE_X and math.abs(eb.y - py) < RANGE_Y then
        local ek = cellOf(eb.x + eb.w / 2, eb.y + eb.h - 3)
        if lava[ek] and not (e.def.fireproof or e.fireproof) then
          e.lavaTimer = (e.lavaTimer or 0) - step
          if e.lavaTimer <= 0 then
            e.lavaTimer = 0.4
            enemies.damage(e, 8)
            enemies.ignite(e, 4, 2)
          end
        elseif acid[ek] then
          e.acidTimer = (e.acidTimer or 0) - step
          if e.acidTimer <= 0 then
            e.acidTimer = 0.5
            enemies.damage(e, 4)
            enemies.corrode(e, 4)
          end
        end
      end
    end
  end
  -- Lava: lights gas over it, boils water at its edge, scorches wood
  local scanned = 0
  for _, spot in ipairs(lavaTop) do
    local x, y = spot[1], spot[2]
    if x > px - RANGE_X and x < px + RANGE_X and y > py - RANGE_Y and y < py + RANGE_Y then
      local k = cellOf(x, y)
      if gas[k - K] and gas[k - K] > 0.1 then
        fluids.ignite(x, y - 2, 1, true)
      end
      for _, d in ipairs({ -1, 1, -K }) do
        if water[k + d] then
          setWater(k + d, nil)
          smoke[k + d] = math.min(1, (smoke[k + d] or 0) + 0.6)
          if r() < 0.4 then
            audio.playAt("steam_hiss", x, y, 0.6)
          end
        end
      end
      if r() < 0.02 then
        local gx, gy = coords(k)
        -- scorches the wood that touches it
        local wx = (gx + (r() < 0.5 and -1 or 1)) * C + HALF
        if world:get(wx, y - 1) == materials.WOOD then
          world:set(wx, y - 1, materials.AIR)
          fire[k - K] = 0.5
          smoke[k - K - K] = 0.5
        end
      end
      scanned = scanned + 1
    end
  end
  -- Acid: eats the wood it touches
  for _, spot in ipairs(acidTop) do
    local x, y = spot[1], spot[2]
    if x > px - RANGE_X and x < px + RANGE_X and y > py - RANGE_Y and y < py + RANGE_Y and r() < 0.05 then
      for _, dx in ipairs({ -2, 2 }) do
        if world:get(x + dx, y + 1) == materials.WOOD then
          world:set(x + dx, y + 1, materials.AIR)
          effects.particle(x + dx, y, (r() - 0.5) * 20, -20, 0.5, { 0.7, 1, 0.3 }, -30, true)
        end
      end
      if world:get(x, y - 1) == materials.WOOD then
        world:set(x, y - 1, materials.AIR)
      end
    end
  end
end

-- Props that sit in lava burn, ones in acid corrode (called by the scene with the props module)
function fluids.updateProps(props)
  for _, p in ipairs(props.all()) do
    local x, y = p.body:getPosition()
    local k = cellOf(x, y)
    if lava[k] then
      props.damage(p, 3)
      fluids.ignite(x, y - 2, 0.5)
    elseif acid[k] then
      props.damage(p, 2)
    end
  end
end

-- Per frame ------------------------------------------------------------------------

-- player: the hunter; enemies: the enemies module (for fire and water on monsters)
-- Wakes the liquid in a rectangle of cells that could move (the periodic sweep, and the strips the
-- region newly covers as the view moves)
local function wakeRect(gx0, gy0, gx1, gy1)
  for gy = gy0, gy1 do
    if (waterRows[gy] or 0) > 0 then
      for gx = gx0, gx1 do
        local k = gy * K + KOFF + gx
        -- (only water that could move: open space under it or beside it. Water merely touching rock
        -- used to count too, which woke a couple of thousand cells for nothing every sweep: a stutter)
        if water[k] and (not water[k + K] or not water[k - 1] or not water[k + 1]) and (free(k + K) or free(k - 1) or free(k + 1)) then
          active[k] = true
        end
      end
    end
    if (oilRows[gy] or 0) > 0 then
      for gx = gx0, gx1 do
        local k = gy * K + KOFF + gx
        if oil[k] and (not oil[k + K] or not oil[k - 1] or not oil[k + 1]) then
          oilActive[k] = true
        end
      end
    end
    if (lavaFlow.rows[gy] or 0) > 0 then
      for gx = gx0, gx1 do
        local k = gy * K + KOFF + gx
        if lava[k] and (not lava[k + K] or not lava[k - 1] or not lava[k + 1]) then
          lavaFlow.active[k] = true
        end
      end
    end
  end
end

-- The region last frame: the strips it newly covers are woken at once, so liquid coming into range
-- (or back into it) carries on moving straight away instead of waiting for the sweep
local lastRegion = { 0, 0, -1, -1 }
local function wakeNewStrips(gx0, gy0, gx1, gy1)
  local l = lastRegion
  if gx1 < l[1] or gx0 > l[3] or gy1 < l[2] or gy0 > l[4] then
    wakeRect(gx0, gy0, gx1, gy1) -- (a jump: all of it is new)
  else
    -- (a couple of cells back inside the old edge too: what was cut off there wakes again)
    if gx0 < l[1] then
      wakeRect(gx0, gy0, l[1] + 2, gy1)
    end
    if gx1 > l[3] then
      wakeRect(l[3] - 2, gy0, gx1, gy1)
    end
    if gy0 < l[2] then
      wakeRect(gx0, gy0, gx1, l[2] + 2)
    end
    if gy1 > l[4] then
      wakeRect(gx0, l[4] - 2, gx1, gy1)
    end
  end
  l[1], l[2], l[3], l[4] = gx0, gy0, gx1, gy1
end

function fluids.update(dt, player, enemies)
  if not world then
    return
  end
  lastPlayer, lastEnemies = player, enemies
  clock = clock + dt
  fluids.runJobs(ADD_BUDGET)
  local b = player.body
  local px, py = b.x + b.w / 2, b.y + b.h / 2
  local gx0, gy0, gx1, gy1 = region(px, py)
  -- The flood around the hunter becomes real water (a margin past the
  -- simulated region, so it is there before it comes into view)
  fillFlood(gx0 - 20, gy0 - 20, gx1 + 20, gy1 + 20, floor(py / C), FLOOD_BUDGET)

  accSweep = accSweep + dt
  if accSweep >= SWEEP then
    -- Wake the water near the hunter, in case the rock under it was dug away
    accSweep = 0
    wakeRect(gx0, gy0, gx1, gy1)
  end
  wakeNewStrips(gx0, gy0, gx1, gy1)
  runSteps(dt, gx0, gy0, gx1, gy1)
  local gm = (VIEW_MARGIN - GAS_MARGIN) / C -- (the gas is stepped a little closer round the view than the water: cells further off wait)
  stepGasFrame(dt, gx0 + gm, gy0 + gm, gx1 - gm, gy1 - gm)
  accSmoke = accSmoke + dt
  if accSmoke >= 0.05 then
    accSmoke = 0
    stepSmoke(gx0, gy0, gx1, gy1)
  end
  accSlow = accSlow + dt
  if accSlow >= 0.1 then
    local step = accSlow
    accSlow = 0
    if lavaFlow.moved then
      lavaFlow.moved = false
      lavaFlow.prune()
    end
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
    -- Gas beyond three screens is let go (the vents and the Queen make more when the hunter is back)
    local fx, fy = floor(config.FAR_X / C), floor(config.FAR_Y / C)
    local cx0, cy0 = floor(px / C), floor(py / C)
    for k in pairs(gas) do
      local x, y = coords(k)
      if x < cx0 - fx or x > cx0 + fx or y < cy0 - fy or y > cy0 + fy then
        setGas(k, nil)
      end
    end
    for k in pairs(smoke) do
      local x, y = coords(k)
      if x < gx0 - 20 or x > gx1 + 20 or y < gy0 - 20 or y > gy1 + 20 then
        smoke[k] = nil
      end
    end
  end

  fluids.updateLiquids(dt, player, enemies, px, py, b, gx0, gy0, gx1, gy1)

  -- The hunter: gas, fire and water
  local headK, midK = cellOf(px, b.y + 3), cellOf(px, py)
  local inCol = fluids.inColumn(px, py)
  local inGas = not player.dead and (inCol or math.max(gas[headK] or 0, gas[midK] or 0) > 0.12)
  if inGas then
    fluids.gasDwell = math.min(8, (fluids.gasDwell or 0) + dt)
    gasTimer = gasTimer - dt
    if gasTimer <= 0 then
      gasTimer = TICK
      local c = math.max(gas[headK] or 0, gas[midK] or 0)
      local ramp = 1 + (fluids.gasDwell or 0) * 0.25
      player:hurtOverTime(math.floor((inCol and COLUMN_DAMAGE or GAS_DAMAGE * (0.6 + c)) * ramp + 0.5), GAS_COLOR, "gas")
      audio.play("hurt", 0.35)
    end
    if love.math.random() < dt * 6 then
      effects.particle(px + player.facing * 3, b.y + 5, player.facing * 14, -10, 0.6, GAS_COLOR, -20, true)
    end
  else
    fluids.gasDwell = math.max(0, (fluids.gasDwell or 0) - dt * 2)
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
    if perks.sum("diving") > 0 then
      breath = BREATH_BUBBLES -- the Diving Helm: breathes under water
      before = BREATH_BUBBLES
      drownTimer = TICK
    elseif player.submerged then
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
    for _, e in ipairs(enemies.nearby()) do
      local eb = e.body
      if math.abs(eb.x - px) < RANGE_X and math.abs(eb.y - py) < RANGE_Y then
        local ek = cellOf(eb.x + eb.w / 2, eb.y + eb.h / 2)
        if fire[ek] and not (e.def.fireproof or e.fireproof) and not e.dead then
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
  local k = gy * K + KOFF + gx
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
  if not p or p.dead or perks.sum("diving") > 0 then
    return -- (the Diving Helm breathes for him: no bubbles)
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
local LEVEL_PER = GAS_LEVELS / GAS_MAX
local gasPoints = {}
for i = 1, GAS_LEVELS do
  gasPoints[i] = {}
end

-- Lava and acid: rows of cells drawn as runs, glowing (they ignore the dark)
local function drawStatic(cells, view, gx0, gy0, gx1, gy1, t, isLava, rows)
  local floor_ = math.floor
  for gy = gy0, gy1 do
    local row = gy * K + KOFF
    local gx = gx0
    if (rows[gy] or 0) <= 0 then
      gx = gx1 + 1 -- (nothing in this row: the counts are kept by setLava and setAcid)
    end
    while gx <= gx1 do
      if cells[row + gx] then
        local a = gx
        while gx <= gx1 and cells[row + gx] do
          gx = gx + 1
        end
        local px, w, py = a * C, (gx - a) * C, gy * C
        local surface = not cells[row + a - K] -- (open above the start of the run)
        if isLava then
          -- Deep red-orange body, a bright seething top, dark crust that drifts
          local depth = 0
          local up = row - K
          while depth < 6 and cells[up + a] do
            depth = depth + 1
            up = up - K
          end
          local d = math.min(1, depth / 6)
          local pulse = 0.5 + 0.5 * math.sin(t * 1.6 + px * 0.05 + gy * 0.3)
          love.graphics.setColor(1.0 - 0.28 * d, 0.62 - 0.4 * d + 0.08 * pulse, 0.12 - 0.07 * d)
          love.graphics.rectangle("fill", px, py, w, C)
          -- Crust: dark plates sliding across the surface rows
          if depth < 1 then
            local seg = 8
            for sx = px, px + w - 1, seg do
              local h = (floor_((sx + t * 6) / seg) * 73856093 + gy * 19349663) % 100
              if h < 38 then
                love.graphics.setColor(0.5, 0.12, 0.05, 0.7)
                love.graphics.rectangle("fill", sx, py, math.min(seg - 2, px + w - sx), C)
              end
            end
          end
          if surface then
            local wob = floor_(1.5 * math.sin(px * 0.2 + t * 2.5))
            love.graphics.setColor(1, 0.92, 0.5)
            love.graphics.rectangle("fill", px, py + math.max(0, wob), w, 1)
          end
        else
          local depth = 0
          local up = row - K
          while depth < 4 and cells[up + a] do
            depth = depth + 1
            up = up - K
          end
          local d = math.min(1, depth / 4)
          love.graphics.setColor(0.52 - 0.18 * d, 0.92 - 0.35 * d, 0.2 - 0.05 * d, 0.88)
          love.graphics.rectangle("fill", px, py, w, C)
          if surface then
            love.graphics.setColor(0.85, 1, 0.5, 0.95)
            love.graphics.rectangle("fill", px, py + (floor_(t * 3 + px * 0.3) % 2), w, 1)
          end
        end
      else
        gx = gx + 1
      end
    end
  end
end

-- Bubbles popping on the lava and acid in view, with their sounds
local bubbleTimer = 0
local function bubble(view, dt)
  bubbleTimer = bubbleTimer - dt
  if bubbleTimer > 0 then
    return
  end
  bubbleTimer = 0.12
  local r = love.math.random
  for _, set in ipairs({ { lavaTop, true }, { acidTop, false } }) do
    local tops = set[1]
    if #tops > 0 then
      for _ = 1, 2 do
        local spot = tops[r(#tops)]
        local x, y = spot[1], spot[2]
        if x > view.x and x < view.x + view.w and y > view.y and y < view.y + view.h and r() < 0.5 then
          if set[2] then
            effects.particle(x, y, (r() - 0.5) * 14, -30 - r() * 40, 0.5 + r() * 0.5, { 1, 0.55 + r() * 0.3, 0.15 }, 60, true)
            if r() < 0.35 then
              audio.playAt("lava_bubble", x, y, 0.8)
            end
            if r() < 0.25 then
              effects.particle(x, y - 3, (r() - 0.5) * 8, -12, 1.4, { 0.3, 0.27, 0.27 }, -26) -- a thread of smoke
            end
          else
            effects.particle(x, y, (r() - 0.5) * 8, -16 - r() * 24, 0.6, { 0.75, 1, 0.35 }, -20, true)
            if r() < 0.3 then
              audio.playAt("acid_fizz", x, y, 0.8)
            end
          end
        end
      end
    end
  end
end

function fluids.drawEmissive(view)
  local gx0, gy0, gx1, gy1 = visibleRange(view)
  local t = love.timer.getTime()
  drawBreath(t)
  if next(lava) ~= nil then
    drawStatic(lava, view, gx0, gy0, gx1, gy1, t, true, lavaFlow.rows)
  end
  if next(acid) ~= nil then
    drawStatic(acid, view, gx0, gy0, gx1, gy1, t, false, acidRows)
  end
  bubble(view, love.timer.getDelta())
  -- Gas: each cell a 2-px square whose strength shimmers slowly, sorted into
  -- a few brightness levels so the whole cloud is a handful of draw calls
  local counts = {}
  for i = 1, GAS_LEVELS do
    counts[i] = 0
  end
  local sin, cos = math.sin, math.cos
  -- (sin(px * 0.07 + t * 0.5 + wob) = sin(a) cos(wob) + cos(a) sin(wob): a sin and a cos per column and
  -- per row, not one per cell)
  local sA, cA = GS.sA or {}, GS.cA or {}
  GS.sA, GS.cA = sA, cA
  for gx = gx0, gx1 do
    local a = gx * C * 0.07 + t * 0.5
    sA[gx - gx0] = sin(a)
    cA[gx - gx0] = cos(a)
  end
  for gy = gy0, gy1 do
    if (gasRows[gy] or 0) > 0 then
      local row = gy * K + KOFF
      local py = gy * C
      local wob = sin(py * 0.05 - t * 0.3) * 1.7
      local sB, cB = sin(wob), cos(wob)
      for gx = gx0, gx1 do
        local c = gas[row + gx]
        if c and c > 0.03 then
          local i = gx - gx0
          local n = 0.5 + 0.5 * (sA[i] * cB + cA[i] * sB)
          local a = c * 0.3
          if a > 0.4 then
            a = 0.4
          end
          local level = floor(a * (0.55 + n * 0.9) * LEVEL_PER) + 1
          if level > GAS_LEVELS then
            level = GAS_LEVELS
          end
          local list = gasPoints[level]
          local nn = counts[level]
          list[nn + 1] = gx * C + HALF
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
  local aboveRow = floor((py - 1) / C) * K + KOFF
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
  local row = gy * K + KOFF
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

-- Open water surfaces in view, found once a frame: { x0, x1, y, depth }
local surfaces = {}
local surfaceLines = {} -- every open surface run, however short (for the ripple line)
local surfacePoolA, surfacePoolB = {}, {} -- (their records, reused frame to frame)

-- What the drawing needs about the water in a stretch of a row, kept until the
-- water in that row or the one above it changes: its runs of cells, and the
-- spans of those with open air above (the surface). Blocks of 256 cells.
local BLOCK = WATER_BLOCK
-- (runCache, runCacheCount: see the top of the file)

local aboveRow = {}
local function rowBlock(gy, block)
  local bk = (gy * K + KOFF) / BLOCK + block -- (see WATER_BLOCK; also the cache's key)
  local ver = (blockVer[bk] or 0) + (blockVer[bk - K / BLOCK] or 0)
  local entry = runCache[bk]
  if not entry then
    runCacheCount = runCacheCount + 1
  end
  if not entry or entry.ver ~= ver then
    local runs, spans = entry and entry.runs or {}, entry and entry.spans or {}
    local lent = entry and entry.lent or {} -- (cells the simulation took for rock that touch this water: see below)
    for i = #runs, 1, -1 do
      runs[i] = nil
    end
    for i = #lent, 1, -1 do
      lent[i] = nil
    end
    for i = #spans, 1, -1 do
      spans[i] = nil
    end
    local row = gy * K + KOFF
    local g0, g1 = block * BLOCK, block * BLOCK + BLOCK - 1
    local gx = g0
    local above -- (the rock over the stretch, read in one go the first time it is needed: see solidAt)
    while gx <= g1 do
      if water[row + gx] then
        local a = gx
        local s0
        while gx <= g1 and water[row + gx] do
          local open = not water[row + gx - K]
          if open then
            if not above then
              above = aboveRow
              world:solidRow(g0 * C + HALF, g1 * C + HALF, (gy - 1) * C + HALF, above, 0)
            end
            open = above[(gx - g0) * C] == 0
            if not open then
              lent[#lent + 1] = gx -- (a rock cell over the water: its open pixels are water's)
              lent[#lent + 1] = gy - 1
            end
          end
          if not water[row + gx + K] and solidAt(row + gx + K) then
            lent[#lent + 1] = gx
            lent[#lent + 1] = gy + 1
          end
          if open and not s0 then
            s0 = gx
          elseif not open and s0 then
            spans[#spans + 1] = s0
            spans[#spans + 1] = gx - 1
            s0 = nil
          end
          gx = gx + 1
        end
        if s0 then
          spans[#spans + 1] = s0
          spans[#spans + 1] = gx - 1
        end
        -- (rock cells at the ends of the run lend their open pixels too)
        if not water[row + a - 1] and solidAt(row + a - 1) then
          lent[#lent + 1] = a - 1
          lent[#lent + 1] = gy
        end
        if not water[row + gx] and solidAt(row + gx) then
          lent[#lent + 1] = gx
          lent[#lent + 1] = gy
        end
        runs[#runs + 1] = a
        runs[#runs + 1] = gx - 1
      else
        gx = gx + 1
      end
    end
    entry = entry or {}
    entry.runs, entry.spans, entry.lent, entry.ver = runs, spans, lent, ver
    runCache[bk] = entry
  end
  return entry
end

local function findSurfaces(view)
  local gx0, gy0, gx1, gy1 = visibleRange(view)
  for i = #surfaces, 1, -1 do
    surfaces[i] = nil
  end
  for i = #surfaceLines, 1, -1 do
    surfaceLines[i] = nil
  end
  if runCacheCount > 20000 then
    runCache, runCacheCount = {}, 0 -- (drop it all rather than let it grow as the hunter wanders)
  end
  local b0, b1 = floor(gx0 / BLOCK), floor(gx1 / BLOCK)
  for gy = gy0, gy1 do
    if (waterRows[gy] or 0) > 0 then
      for block = b0, b1 do
        local spans = rowBlock(gy, block).spans
        for i = 1, #spans, 2 do
          local a, z = spans[i], spans[i + 1] + 1
          local n = #surfaceLines + 1
          local l = surfacePoolB[n]
          if not l then
            l = {}
            surfacePoolB[n] = l
          end
          l[1], l[2], l[3] = a * C, z * C, gy * C
          surfaceLines[n] = l
          if z - a >= 6 then
            local row = gy * K + KOFF
            local mid = floor((a + z) / 2)
            local d = 0
            while d < 14 and water[row + mid + d * K] do
              d = d + 1
            end
            local n = #surfaces + 1
            local sf = surfacePoolA[n]
            if not sf then
              sf = {}
              surfacePoolA[n] = sf
            end
            sf.x0, sf.x1, sf.y, sf.depth = a * C, z * C, gy * C, d * C
            surfaces[n] = sf
          end
        end
      end
    end
  end
end

-- Set by the game: draws the creatures (the hunter and the monsters) so they can be mirrored
fluids.reflector = nil

local smokePool, smokePoints = {}, {} -- reused point tables for drawing smoke

-- Still water mirrors what stands over it: the creatures drawn upside down
-- under each surface near the hunter, clipped to the pool. The water drawn
-- over the top softens it to a faint, tinted echo.
local function drawReflections(view)
  if not fluids.reflector or not breathPlayer or #surfaces == 0 then
    return
  end
  local pb = breathPlayer.body
  local px, py = pb.x + pb.w / 2, pb.y + pb.h / 2
  local done = 0
  for _, s in ipairs(surfaces) do
    if done < 2 and s.x1 > px - 110 and s.x0 < px + 110 and s.y > py - 90 and s.y < py + 36 then
      done = done + 1
      local sx0, sy0 = love.graphics.transformPoint(s.x0, s.y)
      local sx1, sy1 = love.graphics.transformPoint(s.x1, s.y + math.min(s.depth, 30))
      if sx1 > sx0 and sy1 > sy0 then
        love.graphics.setScissor(math.floor(sx0), math.floor(sy0), math.ceil(sx1 - sx0), math.ceil(sy1 - sy0))
        love.graphics.push()
        love.graphics.translate(0, 2 * s.y)
        love.graphics.scale(1, -1)
        fluids.reflector(view)
        love.graphics.pop()
        love.graphics.setScissor()
        -- It fades with depth: the water's own colour thickening over it
        local depth = math.min(s.depth, 30)
        for i = 0, 5 do
          love.graphics.setColor(WATER_DEEP[1], WATER_DEEP[2], WATER_DEEP[3], 0.12 + i * 0.1)
          love.graphics.rectangle("fill", s.x0, s.y + i * depth / 6, s.x1 - s.x0, math.ceil(depth / 6))
        end
      end
    end
  end
  love.graphics.setColor(1, 1, 1)
end

-- Lamps over the water leave a rippling glint streaming down from the surface
function fluids.drawGlints(lights)
  do
    return -- (off: the streaks of lamplight under the surface read as reflections)
  end
  local t = love.timer.getTime()
  for _, s in ipairs(surfaces) do
    for _, l in ipairs(lights) do
      if l.x > s.x0 + 2 and l.x < s.x1 - 2 and l.y < s.y and s.y - l.y < 150 and l.radius <= 200 then
        local peak = math.max(l.r, l.g, l.b, 0.001)
        local power = math.min(1, peak * 1.4) * math.min(1, (1 - (s.y - l.y) / 160) * 1.4)
        if power > 0.15 then
          local depth = math.min(s.depth, 34)
          for i = 0, depth / 2 do
            local yy = s.y + 2 + i * 2
            local sway = math.floor(math.sin(t * 2.6 + i * 0.9 + l.x) * (1 + i * 0.12))
            local w = math.max(1, math.floor(4 * (1 - i / (depth / 2 + 1)) + math.sin(t * 4 + i) * 1.2))
            love.graphics.setColor(l.r / peak, l.g / peak, l.b / peak, 0.6 * power * (1 - i / (depth / 2 + 1)))
            love.graphics.rectangle("fill", l.x - w / 2 + sway, yy, w, 1)
          end
        end
      end
    end
  end
  love.graphics.setColor(1, 1, 1)
end

-- The water's body, drawn as whole runs of cells with a shader that cuts the
-- rock out of it using the terrain mask (src.lighting): far cheaper than
-- working out the water's edge pixel by pixel, which matters when a whole
-- area is flooded. Lighter water along the rock, a faint grain and now and
-- then a glint, as before.
local WATER_BODY = [[
uniform Image mask;
uniform vec2 canvasSize;
uniform vec2 cam;
uniform float time;

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec2 p = sc / canvasSize;
  if (Texel(mask, p).r > 0.9) {
    discard;
  }
  vec2 d = 1.0 / canvasSize;
  float near = 0.0;
  for (int i = 0; i < 4; i++) {
    float r = 3.0 + float(i) * 3.0;
    float hit = max(max(Texel(mask, p + vec2(r, 0.0) * d).r, Texel(mask, p - vec2(r, 0.0) * d).r), max(Texel(mask, p + vec2(0.0, r) * d).r, Texel(mask, p - vec2(0.0, r) * d).r));
    near = max(near, step(0.9, hit) * (1.0 - float(i) * 0.27));
  }
  vec3 col = mix(vec3(0.13, 0.31, 0.42), vec3(0.27, 0.54, 0.56), near);
  vec2 wp = floor(sc + cam);
  // the Flooded Caverns' water (the west) is tinged purple
  if (wp.x < -380.0) {
    col = mix(col, col * vec3(1.45, 0.82, 1.6) + vec3(0.03, 0.0, 0.05), 0.65);
  }
  if (hash(floor(wp / 2.0)) < 0.07) {
    col = mix(col, vec3(0.32, 0.56, 0.58), 0.15);
  }
  if (hash(wp + floor(time * 2.0) * 7.0) > 0.9993) {
    col = vec3(0.8, 0.92, 0.95);
  }
  // (the west's water is 40% more see-through)
  return vec4(col, wp.x < -380.0 ? 0.444 : 0.74);
}
]]
local waterBody

-- The old way: pixel-exact edges, one pixel row at a time (used if the shader or the mask is unavailable)
local function drawWaterOld(gx0, gy0, gx1, gy1, t)
  buildWaterEdge()
  for gy = gy0, gy1 do
    if (waterRows[gy] or 0) > 0 then
      local row = gy * K + KOFF
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
end

local surfacePoints, surfacePool = {}, {}
local quads = require("src.quads")
local function drawWaterShaded(view, gx0, gy0, gx1, gy1, t, mask)
  if waterBody == nil then
    local ok, sh = pcall(love.graphics.newShader, WATER_BODY)
    waterBody = ok and sh or false
  end
  if not waterBody then
    return false
  end
  waterBody:send("mask", mask)
  waterBody:send("canvasSize", { mask:getDimensions() })
  waterBody:send("cam", { view.x, view.y })
  waterBody:send("time", t)
  love.graphics.setShader(waterBody)
  love.graphics.setColor(1, 1, 1)
  local b0, b1 = floor(gx0 / BLOCK), floor(gx1 / BLOCK)
  -- (the runs go into the rectangle batch, src.quads: water broken up by a drain is thousands of them)
  local qrect = quads.rect
  for gy = gy0, gy1 do
    if (waterRows[gy] or 0) > 0 then
      for block = b0, b1 do
        local entry = rowBlock(gy, block)
        local runs = entry.runs
        for i = 1, #runs, 2 do
          local a, z = runs[i], runs[i + 1] + 1
          qrect(1, 1, 1, 1, a * C, gy * C, (z - a) * C, C)
        end
        -- (the shader cuts the rock out, so only the open pixels of these show)
        local lent = entry.lent
        for i = 1, #lent, 2 do
          qrect(1, 1, 1, 1, lent[i] * C, lent[i + 1] * C, C, C)
        end
      end
    end
  end
  quads.flush()
  love.graphics.setShader()
  -- The surface: a pale rippling line where there is open air above (its points kept frame to frame)
  local points, pool, np = surfacePoints, surfacePool, 0
  for _, l in ipairs(surfaceLines) do
    for sx = l[1], l[2] - 1 do
      if not world:isSolid(sx, l[3] - 1) then
        local off = math.sin(sx * 0.35 + t * 2.2) > 0.5 and 1 or 0
        np = np + 1
        local pt = pool[np]
        if not pt then
          pt = {}
          pool[np] = pt
        end
        pt[1], pt[2] = sx + 0.5, l[3] + off + 0.5
        points[np] = pt
      end
    end
  end
  for i = #points, np + 1, -1 do
    points[i] = nil
  end
  if #points > 0 then
    love.graphics.setColor(0.74, 0.84, 0.76, 0.95)
    love.graphics.points(points)
    love.graphics.setColor(1, 1, 1)
  end
  return true
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
  findSurfaces(view)
  drawReflections(view)
  local mask = require("src.lighting").mask()
  if not (mask and drawWaterShaded(view, gx0, gy0, gx1, gy1, t, mask)) then
    drawWaterOld(gx0, gy0, gx1, gy1, t)
  end
  -- Smoke: single pixels, dithered by density and re-rolled a few times a
  -- second, so it reads as fine drifting grit instead of blocks. (The point
  -- tables are kept and reused frame to frame: smoke over a fire is thousands
  -- of them, and making them afresh each frame fed the garbage collector.)
  local points = smokePoints
  local np = 0
  local frame = floor(t * 6)
  for k, sm in pairs(smoke) do
    local gx, gy = coords(k)
    if gx >= gx0 and gx <= gx1 and gy >= gy0 and gy <= gy1 then
      do
        -- One grit pixel per cell at most (a quarter of the old cost), still
        -- dithered by density and re-rolled a few times a second
        local h = (gx * 73856093 + gy * 19349663 + frame * 83492791) % 1000 / 1000
        if h < math.min(0.9, sm * 1.5) then
          local px = gx * C + floor(h * 997) % C
          local py = gy * C + floor(h * 331) % C
          if not world:isSolid(px, py) then
            local g = 0.26 + h * 0.18
            np = np + 1
            local pt = smokePool[np]
            if not pt then
              pt = {}
              smokePool[np] = pt
            end
            pt[1], pt[2], pt[3], pt[4], pt[5], pt[6] = px + 0.5, py + 0.5, g, g * 0.97, g * 1.03, 0.45 + 0.3 * (1 - h)
            points[np] = pt
          end
        end
      end
    end
  end
  for i = #points, np + 1, -1 do
    points[i] = nil
  end
  if np > 0 then
    love.graphics.points(points)
  end
  -- Oil: a dark, brown-black slick with a dull amber sheen along its top
  for gy = gy0, gy1 do
    if (oilRows[gy] or 0) > 0 then
      for gx = gx0, gx1 do
        local k = gy * K + KOFF + gx
        if oil[k] then
          if not oil[k - K] then
            local glint = ((gx * 7 + floor(t * 2)) % 11 == 0) and 0.18 or 0
            love.graphics.setColor(0.36 + glint, 0.25 + glint, 0.10 + glint * 0.5, 0.95)
          else
            love.graphics.setColor(0.13, 0.09, 0.05, 0.95)
          end
          love.graphics.rectangle("fill", gx * C, gy * C, C, C)
        end
      end
    end
  end
end

-- Gas glows faintly, flames light the dark, vents shine
function fluids.addLights(lighting, view)
  local gx0, gy0, gx1, gy1 = visibleRange(view)
  local lights = 0
  local t = love.timer.getTime()
  local nl = 0
  for _, spot in ipairs(lavaTop) do
    if spot[1] > view.x - 60 and spot[1] < view.x + view.w + 60 and spot[2] > view.y - 60 and spot[2] < view.y + view.h + 60 and nl < 14 then
      nl = nl + 1
      lighting.add(spot[1], spot[2] - 3, 54, 1, 0.45, 0.12, 0.85 + 0.15 * math.sin(t * 3 + spot[1] * 0.1))
    end
  end
  nl = 0
  for _, spot in ipairs(acidTop) do
    if spot[1] > view.x - 40 and spot[1] < view.x + view.w + 40 and spot[2] > view.y - 40 and spot[2] < view.y + view.h + 40 and nl < 8 and spot[1] % 3 == 0 then
      nl = nl + 1
      lighting.add(spot[1], spot[2] - 2, 36, 0.45, 0.95, 0.2, 0.5)
    end
  end
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
