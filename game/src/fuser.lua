-- The fuser (design doc §5.7c): two slots beside the item bar where two
-- common items can be fused into a stronger "fused" one (items.fusions).
-- Put two items in and lock them (the toggle, or the Fuse key): from then
-- on every monster the hunter kills gives up its ether, little teal sparks
-- that stream to him and charge the fuser. At fuser.NEED ether the two
-- become one fused item. Toggling again unlocks the slots early: the ether
-- gathered so far is lost, spilling out over the ground as sparks that fade.
--
-- The fuser's state lives in the run's inventory (inv.fuse), so it carries
-- across areas. Ether in flight is cosmetic until it arrives.
local audio = require("src.audio")
local effects = require("src.effects")
local items = require("src.items")

local fuser = {}

fuser.NEED = 12 -- ether for one fusion
local KILL_ETHER = 1 -- a monster's ether...
local BOSS_ETHER = 10 -- ...and a boss's (a miniboss counts as ten kills)
local SPARKS_PER_ETHER = 5
local MAX_MOTES = 700
local REST_TIME = 5 -- dispersed sparks glow on the ground this long

local motes = {}

local TEAL = { 0.15, 1.0, 0.8 }
local CORE = { 0.75, 1.0, 0.95 }

-- A fresh fuser, for a new inventory
function fuser.new()
  return { slots = {}, locked = false, ether = 0 }
end

-- What the two items in the fuser would fuse into: its id and level, or nil
-- plus why not ("max" when two of a kind would go past +4). Two of the same
-- common item level up; two different plain commons may have a recipe.
function fuser.result(f)
  return fuser.combine(f.slots[1], f.slots[2])
end

-- What two items would fuse into (id, level), or nil (plus "max")
function fuser.combine(a, b)
  if not (a and b) then
    return nil
  end
  if a.id == b.id and items.levelable(a.id) then
    local level = (a.level or 0) + (b.level or 0) + 1
    if level > items.MAX_LEVEL then
      return nil, "max"
    end
    return a.id, level
  end
  if (a.level or 0) == 0 and (b.level or 0) == 0 then
    local id = items.fuse(a.id, b.id)
    if id then
      return id, 0
    end
  end
  return nil
end

function fuser.progress(f)
  return math.min(1, f.ether / fuser.NEED)
end

function fuser.clear()
  motes = {}
end

local function addMote(m)
  if #motes >= MAX_MOTES then
    table.remove(motes, 1)
  end
  motes[#motes + 1] = m
end

-- Spills sparks out over the ground around (x, y)
local function disperse(x, y, count)
  for _ = 1, count do
    local a = -math.pi * (0.1 + love.math.random() * 0.8)
    local sp = 40 + love.math.random() * 110
    addMote({
      state = "fall",
      x = x + (love.math.random() - 0.5) * 6,
      y = y + (love.math.random() - 0.5) * 6,
      vx = math.cos(a) * sp,
      vy = math.sin(a) * sp,
      life = REST_TIME * (0.6 + love.math.random() * 0.6),
      size = love.math.random() < 0.35 and 2 or 1,
      seed = love.math.random() * 10,
    })
  end
end

-- Locks the two items in (if they fuse), or unlocks them and loses the ether
function fuser.toggle(inv, player)
  local f = inv.fuse
  local px, py = player:center()
  if f.locked then
    f.locked = false
    -- The ether gathered (and any still on its way) spills out
    local count = math.floor(f.ether * SPARKS_PER_ETHER)
    for _, m in ipairs(motes) do
      if m.state == "seek" then
        m.state, m.life = "fall", REST_TIME * 0.6
      end
    end
    f.ether = 0
    disperse(px, py, math.max(6, count))
    audio.play("fuse_release")
    effects.popup(px, py - 18, "Fuser released", { 0.55, 0.9, 0.85 })
    return
  end
  if not (f.slots[1] and f.slots[2]) then
    audio.play("deny")
    effects.popup(px, py - 18, "Put two items in the fuser", { 1, 0.6, 0.5 })
    return
  end
  local id, why = fuser.result(f)
  if not id then
    audio.play("deny")
    effects.popup(px, py - 18, why == "max" and "That would go past +" .. items.MAX_LEVEL or "These two won't fuse", { 1, 0.6, 0.5 })
    return
  end
  f.locked = true
  f.ether = 0
  audio.play("fuse_lock")
  effects.popup(px, py - 18, "Fuser locked: slay monsters", { 0.4, 1, 0.85 })
end

-- A monster died at (x, y): while the fuser is locked its ether streams out
-- to the hunter
function fuser.onKill(inv, x, y, boss)
  if not inv.fuse.locked then
    return
  end
  local ether = boss and BOSS_ETHER or KILL_ETHER
  local count = ether * SPARKS_PER_ETHER
  for _ = 1, count do
    local a = love.math.random() * math.pi * 2
    local sp = 30 + love.math.random() * 70
    addMote({
      state = "seek",
      x = x + (love.math.random() - 0.5) * 8,
      y = y + (love.math.random() - 0.5) * 8,
      vx = math.cos(a) * sp,
      vy = math.sin(a) * sp - 30,
      age = -love.math.random() * 0.15,
      value = ether / count,
      size = love.math.random() < 0.4 and 2 or 1,
      seed = love.math.random() * 10,
    })
  end
end

-- The fusion is done: the two items become one, left in the first slot
local function complete(inv, player)
  local f = inv.fuse
  local id, level = fuser.result(f)
  f.locked, f.ether = false, 0
  if not id then
    return
  end
  local item = items.new(id, level)
  f.slots[1], f.slots[2] = item, nil
  local px, py = player:center()
  for _ = 1, 40 do
    local a = love.math.random() * math.pi * 2
    local sp = 60 + love.math.random() * 120
    addMote({
      state = "burst",
      x = px,
      y = py,
      vx = math.cos(a) * sp,
      vy = math.sin(a) * sp,
      life = 0.4 + love.math.random() * 0.4,
      size = love.math.random() < 0.5 and 2 or 1,
      seed = love.math.random() * 10,
    })
  end
  audio.play("fuse_done")
  effects.popup(px, py - 22, "Fused: " .. item.name, { 0.4, 1, 0.85 })
  if fuser.onFused then
    fuser.onFused(item)
  end
end

-- Set by src.game: called with the new item when a fusion completes
fuser.onFused = nil

function fuser.update(dt, world, player, inv)
  local px, py = player:center()
  local f = inv.fuse
  for i = #motes, 1, -1 do
    local m = motes[i]
    local dead = false
    if m.state == "seek" then
      m.age = m.age + dt
      if m.age < 0.3 then
        -- Burst out of the body, slowing...
        local drag = math.exp(-dt * 5)
        m.vx, m.vy = m.vx * drag, m.vy * drag
      else
        -- ...then drawn to the hunter, faster and faster
        local dx, dy = px - m.x, py - m.y
        local d = math.sqrt(dx * dx + dy * dy)
        if d < 5 then
          dead = true
          if f.locked then
            f.ether = f.ether + m.value
            audio.play("ether", 0.5, 0.9 + f.ether / fuser.NEED * 0.5)
          end
        else
          local speed = math.min(320, 60 + (m.age - 0.3) * 420)
          local k = math.min(1, dt * 8)
          m.vx = m.vx + (dx / d * speed - m.vx) * k
          m.vy = m.vy + (dy / d * speed - m.vy) * k
        end
      end
      if m.age > 6 then
        dead = true -- (lost on the way: never hangs about)
      end
    elseif m.state == "fall" then
      m.vy = m.vy + 300 * dt
      m.vx = m.vx * math.exp(-dt * 1.5)
      if world:isSolid(math.floor(m.x + m.vx * dt), math.floor(m.y + m.vy * dt + 1)) then
        m.state, m.vx, m.vy = "rest", 0, 0
      end
      m.life = m.life - dt
      dead = m.life <= 0
    elseif m.state == "rest" then
      m.life = m.life - dt
      dead = m.life <= 0
    else -- burst
      m.vx, m.vy = m.vx * math.exp(-dt * 4), m.vy * math.exp(-dt * 4)
      m.life = m.life - dt
      dead = m.life <= 0
    end
    if dead then
      table.remove(motes, i)
    elseif m.state ~= "rest" then
      m.x, m.y = m.x + m.vx * dt, m.y + m.vy * dt
    end
  end
  if f.locked and f.ether >= fuser.NEED - 1e-6 then
    complete(inv, player)
  end
end

-- After the lighting (they glow): tiny neon sparks, 1 or 2 pixels
function fuser.drawEmissive()
  local t = love.timer.getTime()
  for _, m in ipairs(motes) do
    local a = 1
    if m.life and (m.state == "rest" or m.state == "fall") then
      a = math.min(1, m.life / 1.5)
      if m.state == "rest" then
        a = a * (0.6 + 0.4 * math.sin(t * 4 + m.seed * 3))
      end
    elseif m.state == "burst" then
      a = math.min(1, m.life / 0.3)
    end
    local x, y = math.floor(m.x), math.floor(m.y)
    if m.size == 2 then
      love.graphics.setColor(TEAL[1], TEAL[2], TEAL[3], a * 0.85)
      love.graphics.rectangle("fill", x, y, 2, 2)
      love.graphics.setColor(CORE[1], CORE[2], CORE[3], a)
      love.graphics.rectangle("fill", x, y, 1, 1)
    else
      local flick = 0.75 + 0.25 * math.sin(t * 20 + m.seed * 7)
      love.graphics.setColor(TEAL[1] + 0.3, TEAL[2], TEAL[3], a * flick)
      love.graphics.rectangle("fill", x, y, 1, 1)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

-- A faint teal light round streams of ether
function fuser.addLights(lighting)
  local n = 0
  for _, m in ipairs(motes) do
    if m.size == 2 and m.state ~= "rest" then
      n = n + 1
      if n % 6 == 0 and lighting.add then
        lighting.add(m.x, m.y, 18, TEAL[1] * 0.5, TEAL[2] * 0.5, TEAL[3] * 0.5)
      end
    end
  end
end

return fuser
