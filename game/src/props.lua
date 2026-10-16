-- Physics objects (Box2D rigid bodies): crates, falling terrain debris, and
-- later barrels and physics-based projectiles. Each type sets its own mass and
-- how strongly world gravity affects it (gravityScale) — together, its "weight".
local config = require("src.config")
local effects = require("src.effects")
local physics = require("src.physics")
local pickups = require("src.pickups")

local props = {}

local list = {}

local MAX_DEBRIS = 60 -- oldest terrain debris is removed beyond this

-- Spatial index: every prop sits in the grid cell of its centre, rebuilt once
-- a frame after the physics step (props.update). Queries look only at the
-- cells near what they ask about, widened by the biggest prop's reach plus a
-- frame of fast movement, then check exactly against the live shapes. There
-- are hundreds of props in a run (crates, pots, lamps, debris) and enemies,
-- the hunter and every bullet ask about them each frame.
local CELL = 64
local grid = {} -- cell key -> list of props
local reach = 16 -- the biggest prop's bounding radius, plus slack for movement

local function cellKey(cx, cy)
  return cy * 65536 + cx
end

-- The index is kept up to date as props move rather than rebuilt every
-- frame (hundreds of props, most of them at rest, made a new grid and its
-- buckets each frame: a steady stream of garbage)
local function unindex(p)
  local bucket = p.cellK and grid[p.cellK]
  if bucket then
    for i = #bucket, 1, -1 do
      if bucket[i] == p then
        table.remove(bucket, i)
        break
      end
    end
  end
  p.cellK = nil
end

local function indexProp(p)
  local x, y = p.body:getPosition()
  p.ix, p.iy = x, y -- (also used for cheap on-screen tests)
  local k = cellKey(math.floor(x / CELL), math.floor(y / CELL))
  if k ~= p.cellK then
    unindex(p)
    local bucket = grid[k]
    if not bucket then
      bucket = {}
      grid[k] = bucket
    end
    bucket[#bucket + 1] = p
    p.cellK = k
  end
  local r = (p.width + p.height) * 0.75 + 24
  if r > reach then
    reach = r
  end
end

local function rebuildIndex()
  grid = {}
  reach = 16
end
local refreshAt = 0 -- (round robin: a few resting props are looked at again every frame too)

-- Calls fn(p) for every prop that might touch the rectangle; stops early if
-- fn returns true, and returns what it returned
local function nearby(x, y, w, h, fn)
  local cx0, cy0 = math.floor((x - reach) / CELL), math.floor((y - reach) / CELL)
  local cx1, cy1 = math.floor((x + w + reach) / CELL), math.floor((y + h + reach) / CELL)
  for cy = cy0, cy1 do
    for cx = cx0, cx1 do
      local bucket = grid[cellKey(cx, cy)]
      if bucket then
        for _, p in ipairs(bucket) do
          if not p.removed then
            local r = fn(p)
            if r then
              return r
            end
          end
        end
      end
    end
  end
  return nil
end

-- Prop art is drawn with whole-pixel rectangles from the top-left of the box
-- (x = -floor(w/2)), so every edge lands exactly on the pixel grid.
local function frame(x, y, w, h, t)
  love.graphics.rectangle("fill", x, y, w, t)
  love.graphics.rectangle("fill", x, y + h - t, w, t)
  love.graphics.rectangle("fill", x, y, t, h)
  love.graphics.rectangle("fill", x + w - t, y, t, h)
end

local function drawCrate(p)
  local w, h = p.width, p.height
  local x, y = -math.floor(w / 2), -math.floor(h / 2)
  love.graphics.setColor(0.52, 0.37, 0.24)
  love.graphics.rectangle("fill", x, y, w, h)
  -- Plank seams
  love.graphics.setColor(0.40, 0.28, 0.18)
  love.graphics.rectangle("fill", x, y + math.floor(h / 3), w, 1)
  love.graphics.rectangle("fill", x, y + math.floor(2 * h / 3), w, 1)
  -- Diagonal brace, one pixel per step
  love.graphics.setColor(0.32, 0.22, 0.14)
  for i = 2, w - 3 do
    love.graphics.rectangle("fill", x + i, y + math.floor(i * (h - 1) / (w - 1)), 1, 1)
  end
  love.graphics.setColor(0.22, 0.15, 0.10)
  frame(x, y, w, h, 1)
end

local function drawIronCrate(p)
  local w, h = p.width, p.height
  local x, y = -math.floor(w / 2), -math.floor(h / 2)
  love.graphics.setColor(0.30, 0.31, 0.36)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.setColor(0.41, 0.42, 0.48)
  love.graphics.rectangle("fill", x + 2, y + 2, w - 4, 1) -- top highlight
  -- Brass band across the middle
  love.graphics.setColor(0.56, 0.44, 0.24)
  love.graphics.rectangle("fill", x + 1, y + math.floor(h / 2) - 1, w - 2, 2)
  love.graphics.setColor(0.14, 0.14, 0.17)
  frame(x, y, w, h, 1)
  -- Corner rivets
  love.graphics.setColor(0.58, 0.60, 0.66)
  for _, c in ipairs({ { 2, 2 }, { w - 3, 2 }, { 2, h - 3 }, { w - 3, h - 3 } }) do
    love.graphics.rectangle("fill", x + c[1], y + c[2], 1, 1)
  end
end

-- Breakable pots, pouches and lamps found about the areas. Each is drawn from
-- the top-left of its box like the crates; the lamps' flames and crystals are
-- drawn again after the lighting (see props.drawEmissive) so they glow.
local function rects(x, y, list, color)
  love.graphics.setColor(color)
  for _, r in ipairs(list) do
    love.graphics.rectangle("fill", x + r[1], y + r[2], r[3], r[4])
  end
end

local function topLeft(p)
  return -math.floor(p.width / 2), -math.floor(p.height / 2)
end

local function drawUrn(p)
  local x, y = topLeft(p)
  rects(x, y, { { 2, 0, 5, 1 }, { 3, 1, 3, 2 }, { 1, 3, 7, 2 }, { 0, 5, 9, 4 }, { 1, 9, 7, 2 }, { 2, 11, 5, 1 } }, { 0.62, 0.38, 0.26 })
  rects(x, y, { { 2, 0, 5, 1 }, { 1, 4, 2, 4 }, { 3, 1, 1, 2 } }, { 0.80, 0.56, 0.40 })
  rects(x, y, { { 6, 4, 2, 6 }, { 5, 9, 2, 2 }, { 5, 1, 1, 2 } }, { 0.42, 0.25, 0.18 })
  -- A painted band with a zigzag
  rects(x, y, { { 0, 6, 9, 1 } }, { 0.30, 0.17, 0.13 })
  rects(x, y, { { 1, 7, 1, 1 }, { 3, 7, 1, 1 }, { 5, 7, 1, 1 }, { 7, 7, 1, 1 } }, { 0.88, 0.76, 0.52 })
end

local function drawPouch(p)
  local x, y = topLeft(p)
  rects(x, y, { { 3, 0, 1, 2 }, { 5, 0, 1, 2 }, { 2, 3, 5, 1 }, { 1, 4, 7, 1 }, { 0, 5, 9, 2 }, { 1, 7, 7, 1 } }, { 0.52, 0.38, 0.24 })
  rects(x, y, { { 1, 5, 2, 2 }, { 2, 4, 2, 1 } }, { 0.66, 0.50, 0.32 })
  rects(x, y, { { 6, 5, 3, 3 }, { 5, 7, 2, 1 } }, { 0.36, 0.25, 0.16 })
  rects(x, y, { { 2, 2, 5, 1 } }, { 0.22, 0.15, 0.10 }) -- the drawstring
  rects(x, y, { { 4, 4, 1, 1 } }, { 0.95, 0.76, 0.28 }) -- a coin showing
end

local function drawLantern(p)
  local x, y = topLeft(p)
  rects(x, y, { { 2, 0, 3, 1 }, { 1, 1, 1, 1 }, { 5, 1, 1, 1 }, { 1, 2, 5, 1 }, { 1, 3, 1, 6 }, { 5, 3, 1, 6 }, { 0, 9, 7, 1 }, { 1, 10, 5, 1 } }, { 0.20, 0.19, 0.22 })
  rects(x, y, { { 2, 3, 3, 6 } }, { 0.50, 0.33, 0.14 })
  rects(x, y, { { 2, 3, 1, 6 } }, { 0.66, 0.46, 0.20 })
end

local function drawSkullCandle(p)
  local x, y = topLeft(p)
  rects(x, y, { { 3, 2, 2, 2 } }, { 0.86, 0.82, 0.68 }) -- the candle
  rects(x, y, { { 2, 4, 4, 1 }, { 1, 5, 6, 3 }, { 2, 8, 4, 1 }, { 2, 9, 4, 1 } }, { 0.80, 0.78, 0.70 })
  rects(x, y, { { 5, 5, 2, 3 }, { 5, 8, 1, 2 } }, { 0.58, 0.56, 0.52 })
  rects(x, y, { { 2, 6, 1, 1 }, { 4, 6, 1, 1 }, { 3, 7, 1, 1 }, { 3, 9, 1, 1 } }, { 0.10, 0.08, 0.10 })
end

-- A lamp's glow colour: its own, or the area's mushroom/crystal colour
local function glowOf(p, default)
  return p.glow or default
end

local function drawSporePod(p)
  local x, y = topLeft(p)
  local g = glowOf(p, { 0.35, 0.95, 0.85 })
  rects(x, y, { { 4, 7, 2, 3 }, { 3, 9, 4, 1 } }, { 0.28, 0.34, 0.26 }) -- stem and foot
  rects(x, y, { { 3, 0, 4, 1 }, { 2, 1, 6, 1 }, { 1, 2, 8, 1 }, { 0, 3, 10, 4 }, { 1, 7, 8, 1 } }, { g[1] * 0.42, g[2] * 0.42, g[3] * 0.42 })
  rects(x, y, { { 6, 3, 4, 4 } }, { g[1] * 0.25, g[2] * 0.25, g[3] * 0.25 })
end

local GEODE_SPIKES = { { 2, 3 }, { 4, 1 }, { 6, 2 }, { 8, 3 } } -- x, top

local function drawGeode(p)
  local x, y = topLeft(p)
  local g = glowOf(p, { 1.0, 0.92, 0.35 })
  rects(x, y, { { 1, 5, 9, 1 }, { 0, 6, 11, 2 }, { 1, 8, 9, 1 } }, { 0.34, 0.31, 0.28 })
  rects(x, y, { { 0, 6, 3, 2 }, { 1, 5, 3, 1 } }, { 0.46, 0.42, 0.38 })
  -- Crystal spikes of the area's colour
  for _, s in ipairs(GEODE_SPIKES) do
    rects(x, y, { { s[1], s[2], 2, 6 - s[2] } }, { g[1] * 0.62, g[2] * 0.62, g[3] * 0.62 })
    rects(x, y, { { s[1], s[2], 1, 6 - s[2] } }, { math.min(1, g[1] * 0.9 + 0.1), math.min(1, g[2] * 0.9 + 0.1), math.min(1, g[3] * 0.9 + 0.1) })
  end
end

local function drawEmberPot(p)
  local x, y = topLeft(p)
  rects(x, y, { { 1, 2, 7, 1 }, { 0, 3, 9, 4 }, { 1, 7, 7, 2 }, { 2, 9, 5, 1 } }, { 0.24, 0.20, 0.20 })
  rects(x, y, { { 1, 3, 2, 4 } }, { 0.34, 0.28, 0.27 })
  rects(x, y, { { 6, 4, 3, 4 } }, { 0.15, 0.12, 0.13 })
  rects(x, y, { { 1, 2, 7, 1 } }, { 0.10, 0.08, 0.09 }) -- the dark mouth
end

-- Flames, ember cracks and crystal tips, drawn after the lighting
local function emitLantern(p, t)
  local x, y = topLeft(p)
  local f = math.sin(t * 9 + p.seed) > 0.3 and 1 or 0
  rects(x, y, { { 2, 5 - f, 3, 3 + f } }, { 1, 0.72, 0.28 })
  rects(x, y, { { 3, 6, 1, 2 } }, { 1, 0.95, 0.7 })
end

local function emitSkullCandle(p, t)
  local x, y = topLeft(p)
  local f = math.sin(t * 11 + p.seed) > 0.2 and 1 or 0
  rects(x, y, { { 3, -f, 2, 2 + f } }, { 1, 0.72, 0.28 })
  rects(x, y, { { 3, 1, 1, 1 } }, { 1, 0.95, 0.7 })
  rects(x, y, { { 2, 6, 1, 1 }, { 4, 6, 1, 1 } }, { 1, 0.8, 0.3 }) -- the eyes glow
end

local function emitSporePod(p, t)
  local x, y = topLeft(p)
  local g = glowOf(p, { 0.35, 0.95, 0.85 })
  local pulse = 0.6 + 0.3 * math.sin(t * 2 + p.seed)
  rects(x, y, { { 2, 2, 2, 2 }, { 5, 4, 3, 2 }, { 3, 5, 1, 1 } }, { g[1], g[2], g[3], pulse })
  rects(x, y, { { 2, 2, 1, 1 }, { 6, 4, 1, 1 } }, { 1, 1, 1, pulse * 0.8 })
end

local function emitGeode(p, t)
  local x, y = topLeft(p)
  local g = glowOf(p, { 1.0, 0.92, 0.35 })
  local a = 0.85 + 0.15 * math.sin(t * 3 + p.seed)
  for _, s in ipairs(GEODE_SPIKES) do
    rects(x, y, { { s[1], s[2], 1, 1 } }, { math.min(1, g[1] + 0.1), math.min(1, g[2] + 0.1), math.min(1, g[3] + 0.1), a })
  end
end

local function emitEmberPot(p, t)
  local x, y = topLeft(p)
  local f = math.sin(t * 8 + p.seed) > 0 and 1 or 0
  rects(x, y, { { 2, 1, 5, 1 }, { 3 + f, 0, 2, 1 } }, { 1, 0.5, 0.15 })
  rects(x, y, { { 4, 1, 1, 1 } }, { 1, 0.8, 0.3 })
  rects(x, y, { { 2, 5, 1, 2 }, { 5, 6, 1, 1 } }, { 1, 0.45, 0.12, 0.8 })
end


-- Old TNT: a barrel of black powder, stencilled in red; it goes off on a short
-- fuse once it takes enough damage
local TNT_GLYPHS = {
  T = { "###", ".#.", ".#.", ".#.", ".#." },
  N = { "#.#", "###", "###", "#.#", "#.#" },
}

local function drawTntBarrel(p)
  local x, y = topLeft(p)
  rects(x, y, { { 2, 0, 9, 1 }, { 1, 1, 11, 14 }, { 2, 15, 9, 1 } }, { 0.50, 0.31, 0.17 })
  rects(x, y, { { 1, 1, 2, 14 }, { 3, 0, 3, 1 } }, { 0.66, 0.42, 0.22 })
  rects(x, y, { { 10, 1, 2, 14 }, { 8, 15, 3, 1 } }, { 0.34, 0.20, 0.11 })
  -- Iron hoops
  rects(x, y, { { 0, 2, 13, 1 }, { 0, 13, 13, 1 } }, { 0.24, 0.25, 0.29 })
  rects(x, y, { { 0, 2, 13, 1 } }, { 0.36, 0.37, 0.42 })
  -- The label: red capitals on a faded cream plate
  rects(x, y, { { 1, 4, 11, 7 } }, { 0.86, 0.78, 0.60 })
  rects(x, y, { { 1, 4, 11, 1 }, { 1, 10, 11, 1 } }, { 0.70, 0.60, 0.44 })
  for i, ch in ipairs({ "T", "N", "T" }) do
    for gy, row in ipairs(TNT_GLYPHS[ch]) do
      for gx = 1, 3 do
        if row:sub(gx, gx) == "#" then
          rects(x, y, { { 1 + (i - 1) * 4 + gx - 1, 4 + gy, 1, 1 } }, { 0.72, 0.12, 0.10 })
        end
      end
    end
  end
  if p.lit then
    rects(x, y, { { 6, -2, 1, 2 } }, { 0.14, 0.10, 0.08 }) -- the fuse
  end
end

local function emitTntBarrel(p, t)
  if not p.lit then
    return
  end
  local x, y = topLeft(p)
  local f = math.floor(t * 30) % 2
  rects(x, y, { { 6, -3 - f, 1, 1 + f } }, { 1, 0.7 + f * 0.2, 0.25 })
end

-- An ore cart: a riveted iron box on two small wheels, heaped with rock and ore
local function drawMinecart(p)
  local x, y = topLeft(p)
  -- Heap of ore over the rim
  rects(x, y, { { 3, 0, 16, 2 }, { 5, -1, 6, 1 }, { 12, -1, 4, 1 } }, { 0.36, 0.34, 0.33 })
  rects(x, y, { { 4, 0, 3, 1 }, { 13, -1, 2, 1 } }, { 0.50, 0.48, 0.46 })
  rects(x, y, { { 8, 0, 1, 1 }, { 15, 0, 1, 1 }, { 6, 1, 1, 1 }, { 11, -1, 1, 1 } }, { 0.95, 0.75, 0.25 })
  -- The box: a rolled rim, rust-brown plating, bands and rivets
  rects(x, y, { { 0, 2, 22, 2 } }, { 0.40, 0.41, 0.46 })
  rects(x, y, { { 0, 2, 22, 1 } }, { 0.58, 0.59, 0.64 })
  rects(x, y, { { 1, 4, 20, 6 } }, { 0.40, 0.29, 0.22 })
  rects(x, y, { { 1, 4, 20, 1 } }, { 0.50, 0.37, 0.28 })
  rects(x, y, { { 1, 9, 20, 1 } }, { 0.28, 0.20, 0.16 })
  rects(x, y, { { 5, 4, 1, 6 }, { 11, 4, 1, 6 }, { 17, 4, 1, 6 } }, { 0.30, 0.31, 0.35 })
  rects(x, y, { { 3, 5, 1, 1 }, { 8, 5, 1, 1 }, { 14, 5, 1, 1 }, { 19, 5, 1, 1 } }, { 0.62, 0.52, 0.40 })
  -- Wheels
  for _, wx in ipairs({ 3, 15 }) do
    rects(x, y, { { wx, 10, 4, 3 }, { wx + 1, 9, 2, 1 } }, { 0.20, 0.20, 0.24 })
    rects(x, y, { { wx + 1, 11, 2, 1 } }, { 0.55, 0.56, 0.60 })
  end
end

-- Terrain debris carries an image of the pixels it was cut from
local function drawDebris(p)
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(p.image, -math.floor(p.width / 2), -math.floor(p.height / 2))
end

props.defs = {
  crate = {
    width = 13,
    height = 13,
    mass = 1,
    hp = 25, -- breaks when its damage total reaches this
    gold = { 0, 4 }, -- gold spilled when it breaks (min, max)
    itemChance = 0.12, -- chance it holds an ammo type or attachment
    gravityScale = 0.4,
    friction = 0.4,
    restitution = 0.25,
    linearDamping = 0.3,
    angularDamping = 0.4,
    showDamage = true,
    draw = drawCrate,
  },
  ironCrate = {
    width = 16,
    height = 16,
    mass = 4,
    hp = 90,
    gold = { 5, 12 },
    itemChance = 0.4,
    gravityScale = 0.6,
    friction = 0.7,
    restitution = 0.1,
    linearDamping = 0.3,
    angularDamping = 0.5,
    showDamage = true,
    draw = drawIronCrate,
  },
  -- Small breakables found about the areas (see THEMES in src.scenes.catacombs)
  urn = {
    width = 9, height = 12, mass = 0.6, hp = 12, gold = { 1, 6 }, itemChance = 0.1,
    shard = { 0.62, 0.38, 0.26 },
    gravityScale = 0.4, friction = 0.4, restitution = 0.2, linearDamping = 0.3, angularDamping = 0.4,
    showDamage = true, draw = drawUrn,
  },
  pouch = {
    width = 9, height = 8, mass = 0.35, hp = 6, gold = { 3, 9 }, itemChance = 0.04,
    shard = { 0.52, 0.38, 0.24 },
    gravityScale = 0.4, friction = 0.8, restitution = 0.05, linearDamping = 0.5, angularDamping = 0.7,
    showDamage = true, draw = drawPouch,
  },
  lantern = {
    width = 7, height = 11, mass = 0.5, hp = 10, gold = { 0, 3 }, itemChance = 0.05,
    shard = { 0.95, 0.75, 0.35 },
    light = { radius = 80, color = { 1, 0.68, 0.34 }, intensity = 0.9 },
    gravityScale = 0.4, friction = 0.5, restitution = 0.15, linearDamping = 0.3, angularDamping = 0.5,
    showDamage = true, draw = drawLantern, emit = emitLantern,
    oil = 24, -- cells of lamp oil inside: spilt as it is shot, the rest when it breaks (src.fluids)
  },
  skullCandle = {
    width = 8, height = 10, mass = 0.5, hp = 12, gold = { 1, 5 }, itemChance = 0.06,
    shard = { 0.80, 0.78, 0.70 },
    light = { radius = 62, color = { 1, 0.7, 0.36 }, intensity = 0.8 },
    gravityScale = 0.4, friction = 0.6, restitution = 0.1, linearDamping = 0.3, angularDamping = 0.6,
    showDamage = true, draw = drawSkullCandle, emit = emitSkullCandle,
  },
  sporePod = {
    width = 10, height = 10, mass = 0.4, hp = 8, gold = { 0, 3 }, itemChance = 0.08,
    glowShard = true, -- bursts into the area's glow colour
    light = { radius = 64, intensity = 0.8 }, -- (colour: the area's)
    gravityScale = 0.35, friction = 0.6, restitution = 0.1, linearDamping = 0.4, angularDamping = 0.6,
    showDamage = true, draw = drawSporePod, emit = emitSporePod,
  },
  geode = {
    width = 11, height = 9, mass = 2.5, hp = 26, gold = { 4, 11 }, itemChance = 0.15,
    glowShard = true,
    light = { radius = 58, intensity = 0.75 },
    gravityScale = 0.6, friction = 0.8, restitution = 0.05, linearDamping = 0.3, angularDamping = 0.6,
    showDamage = true, draw = drawGeode, emit = emitGeode,
  },
  emberPot = {
    width = 9, height = 10, mass = 0.9, hp = 12, gold = { 1, 5 }, itemChance = 0.08,
    shard = { 0.28, 0.23, 0.22 },
    light = { radius = 66, color = { 1, 0.5, 0.2 }, intensity = 0.85 },
    ignites = true, -- the coals spill out in flames when it breaks
    gravityScale = 0.45, friction = 0.6, restitution = 0.1, linearDamping = 0.3, angularDamping = 0.5,
    showDamage = true, draw = drawEmberPot, emit = emitEmberPot,
  },
  -- The old mine (area 1): a barrel of TNT that goes up on a short fuse, and an ore cart
  tntBarrel = {
    width = 13, height = 16, mass = 1.8, hp = 12, itemChance = 0,
    shard = { 0.50, 0.31, 0.17 },
    explosive = { count = 3, scale = 2.0, dig = 13, digPower = 3 }, -- a big blast and a real crater
    gravityScale = 0.5, friction = 0.6, restitution = 0.15, linearDamping = 0.3, angularDamping = 0.5,
    showDamage = true, draw = drawTntBarrel, emit = emitTntBarrel,
  },
  minecart = {
    width = 22, height = 13, mass = 5, hp = 80, gold = { 8, 18 }, itemChance = 0.25,
    shard = { 0.40, 0.29, 0.22 },
    gravityScale = 0.6, friction = 0.25, restitution = 0.1, linearDamping = 0.15, angularDamping = 0.4,
    showDamage = true, draw = drawMinecart,
  },
  -- Mass comes from the materials it is made of (materials.lua density)
  debris = {
    gravityScale = 0.7,
    friction = 0.7,
    restitution = 0.1,
    linearDamping = 0.2,
    angularDamping = 0.3,
    showDamage = false,
    draw = drawDebris,
  },
}

function props.clear()
  list = {} -- bodies are destroyed along with the physics world
  rebuildIndex()
end

local function newBody(def, x, y, angle)
  local body = love.physics.newBody(physics.world, x, y, "dynamic")
  body:setAngle(angle or 0)
  body:setGravityScale(def.gravityScale)
  body:setLinearDamping(def.linearDamping)
  body:setAngularDamping(def.angularDamping)
  return body
end

local function addFixture(def, body, shape, density)
  local fixture = love.physics.newFixture(body, shape, density)
  fixture:setFriction(def.friction)
  fixture:setRestitution(def.restitution)
  return fixture
end

local function register(prop)
  prop.flash = 0
  prop.total = 0
  list[#list + 1] = prop
  indexProp(prop) -- (findable straight away, before the next rebuild)
  return prop
end

-- Spawns a box-shaped prop centred at (x, y)
function props.spawn(name, x, y, angle, glow)
  local def = assert(props.defs[name], "unknown prop: " .. tostring(name))
  local body = newBody(def, x, y, angle)
  -- Density is per square metre; pick it so the body ends up with def.mass
  local m = config.physics.meter
  local density = def.mass / ((def.width / m) * (def.height / m))
  local fixture = addFixture(def, body, love.physics.newRectangleShape(def.width, def.height), density)
  return register({
    def = def,
    body = body,
    fixtures = { fixture },
    width = def.width,
    height = def.height,
    glow = glow, -- lamps: the colour of their light (default: the def's)
    seed = love.math.random() * 6.3, -- desynchronises flickers
  })
end

local function remove(p)
  p.removed = true
  unindex(p)
  for i, q in ipairs(list) do
    if q == p then
      table.remove(list, i)
      break
    end
  end
  p.body:destroy()
end

-- Spawns a falling chunk of terrain.
--   image: the chunk's pixels; x, y: centre of its bounding box
--   rects: { {x, y, w, h}, ... } in image coordinates, covering the solid pixels
--   density: Box2D density (per square metre)
--   pixels, color: how many pixels it holds and a sample colour; it breaks
--   (crumbles) once damaged for about 40% of its pixel count, at least 6
function props.spawnDebris(image, x, y, rects, density, pixels, color)
  local def = props.defs.debris
  local w, h = image:getDimensions()
  local body = newBody(def, x, y, 0)
  local fixtures = {}
  for _, r in ipairs(rects) do
    local shape = love.physics.newRectangleShape(r[1] + r[3] / 2 - w / 2, r[2] + r[4] / 2 - h / 2, r[3], r[4])
    fixtures[#fixtures + 1] = addFixture(def, body, shape, density)
  end
  local prop = register({
    def = def,
    body = body,
    fixtures = fixtures,
    width = w,
    height = h,
    image = image,
    hp = math.max(6, math.floor((pixels or 20) * 0.4)),
    color = color,
  })

  local debrisCount = 0
  for _, q in ipairs(list) do
    if q.def == def then
      debrisCount = debrisCount + 1
    end
  end
  if debrisCount > MAX_DEBRIS then
    for _, q in ipairs(list) do
      if q.def == def then
        remove(q)
        break
      end
    end
  end
  return prop
end

-- Point test against the prop's actual (rotated) shapes
function props.hitTest(x, y)
  return nearby(x, y, 0, 0, function(p)
    for _, f in ipairs(p.fixtures) do
      if f:testPoint(x, y) then
        return p
      end
    end
  end)
end

-- Breaks a crate: wood splinters and any gold inside spills out. The prop
-- itself is removed on the next props.update, so callers that are looping
-- over the list aren't disturbed.
local function breakProp(p)
  if p.def.explosive then
    -- Powder: it doesn't break, it fizzes for a moment and then goes off
    if not p.lit then
      p.lit = true
      p.fuse = 0.15 + love.math.random() * 0.15
    end
    return
  end
  p.broken = true
  local x, y = p.body:getPosition()
  local c = p.color or p.def.shard or (p.def == props.defs.ironCrate and { 0.34, 0.35, 0.40 } or { 0.5, 0.36, 0.23 })
  if p.def.glowShard then
    c = p.glow or { 0.5, 0.9, 0.8 }
  end
  for _ = 1, 12 do
    local a = love.math.random() * math.pi * 2
    local s = 30 + love.math.random() * 100
    -- (glowing lamps spill glowing bits; pots and pouches just shatter)
    effects.particle(x, y, math.cos(a) * s, math.sin(a) * s - 40, 0.6, c, 520, p.def.glowShard or false)
  end
  if p.def.light then
    effects.ring(x, y, 14, p.glow or p.def.light.color or { 1, 0.8, 0.4 })
  end
  if p.def.ignites then
    require("src.fluids").ignite(x, y, 1)
  end
  if p.def.oil then
    -- A lantern breaking: the rest of its oil, and a puff of fire that lights it
    local fluids = require("src.fluids")
    fluids.addOil(x, y + 2, p.oil or p.def.oil)
    fluids.fireBurst(x, y, 7)
    effects.explosion(x, y, 5)
    require("src.audio").play("explosion", 0.35, 1.6)
  end
  local gold = p.def.gold
  if gold then
    pickups.dropGold(x, y, love.math.random(gold[1], gold[2]))
  end
  if p.def.itemChance then
    pickups.maybeDropItem(x, y, p.def.itemChance)
  end
end

function props.damage(p, amount)
  p.flash = 0.08
  p.total = p.total + amount
  -- A lantern spills its oil a little at every hit
  if p.def.oil and not p.broken then
    p.oil = p.oil or p.def.oil
    local spill = math.min(p.oil, 3 + math.floor(amount / 3))
    if spill > 0 then
      local x, y = p.body:getPosition()
      p.oil = p.oil - require("src.fluids").addOil(x, y + 2, spill)
    end
  end
  local hp = p.hp or p.def.hp
  if hp and p.total >= hp and not p.broken then
    breakProp(p)
  end
end

-- Impulse at a world point (off-centre hits make the prop spin)
function props.impulse(p, ix, iy, x, y)
  if x then
    p.body:applyLinearImpulse(ix, iy, x, y)
  else
    p.body:applyLinearImpulse(ix, iy)
  end
end

function props.push(p, fx, fy)
  p.body:applyForce(fx, fy)
end

local EPS = 0.05

-- Separating-axis test: is the pixel rectangle overlapping a convex polygon?
-- (The polygon's points go in one table kept for the purpose: asked about
-- every prop near every creature each frame, a new table each time added up.)
local polyPts = {}
local function fillPts(...)
  local n = select("#", ...)
  for i = 1, n do
    polyPts[i] = (select(i, ...))
  end
  return n
end

local function polygonOverlapsRect(n, x, y, w, h)
  local pts = polyPts
  local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
  for i = 1, n, 2 do
    minX, maxX = math.min(minX, pts[i]), math.max(maxX, pts[i])
    minY, maxY = math.min(minY, pts[i + 1]), math.max(maxY, pts[i + 1])
  end
  if minX >= x + w - EPS or maxX <= x + EPS or minY >= y + h - EPS or maxY <= y + EPS then
    return false
  end
  for i = 1, n, 2 do
    local j = i + 2 > n and 1 or i + 2
    local nx, ny = pts[j + 1] - pts[i + 1], pts[i] - pts[j]
    local len = math.sqrt(nx * nx + ny * ny)
    nx, ny = nx / len, ny / len
    local pMin, pMax = math.huge, -math.huge
    for k = 1, n, 2 do
      local d = pts[k] * nx + pts[k + 1] * ny
      pMin, pMax = math.min(pMin, d), math.max(pMax, d)
    end
    -- the rectangle's four corners, projected
    local ax, bx, ay, by = x * nx, (x + w) * nx, y * ny, (y + h) * ny
    local rMin = math.min(ax + ay, bx + ay, ax + by, bx + by)
    local rMax = math.max(ax + ay, bx + ay, ax + by, bx + by)
    if pMin >= rMax - EPS or pMax <= rMin + EPS then
      return false
    end
  end
  return true
end

local function overlapsRect(p, x, y, w, h)
  -- Cheap reject using the prop's bounding radius
  local bx, by = p.body:getPosition()
  local radius = (p.width + p.height) * 0.75
  if bx + radius < x or bx - radius > x + w or by + radius < y or by - radius > y + h then
    return false
  end
  for _, f in ipairs(p.fixtures) do
    if polygonOverlapsRect(fillPts(p.body:getWorldPoints(f:getShape():getPoints())), x, y, w, h) then
      return true
    end
  end
  return false
end

-- First prop overlapping the rectangle, skipping any in the `ignore` set
-- (These two are asked many times a frame, by every creature and the
-- hunter, so they walk the grid themselves rather than make a closure for
-- nearby() each time: the garbage added up)
function props.overlapsRect(x, y, w, h, ignore)
  local cx0, cy0 = math.floor((x - reach) / CELL), math.floor((y - reach) / CELL)
  local cx1, cy1 = math.floor((x + w + reach) / CELL), math.floor((y + h + reach) / CELL)
  for cy = cy0, cy1 do
    for cx = cx0, cx1 do
      local bucket = grid[cellKey(cx, cy)]
      if bucket then
        for _, p in ipairs(bucket) do
          if not p.removed and not (ignore and ignore[p]) and overlapsRect(p, x, y, w, h) then
            return p
          end
        end
      end
    end
  end
  return nil
end

-- All props overlapping the rectangle, as a set. Given `into`, that table is
-- emptied and filled instead of a new one being made.
function props.overlapping(x, y, w, h, into)
  local set = into
  if set then
    for k in pairs(set) do
      set[k] = nil
    end
  else
    set = {}
  end
  local cx0, cy0 = math.floor((x - reach) / CELL), math.floor((y - reach) / CELL)
  local cx1, cy1 = math.floor((x + w + reach) / CELL), math.floor((y + h + reach) / CELL)
  for cy = cy0, cy1 do
    for cx = cx0, cx1 do
      local bucket = grid[cellKey(cx, cy)]
      if bucket then
        for _, p in ipairs(bucket) do
          if not p.removed and overlapsRect(p, x, y, w, h) then
            set[p] = true
          end
        end
      end
    end
  end
  return set
end

function props.kick(x, y, w, h, dir, force, lift, damage)
  local hit = {}
  nearby(x, y, w, h, function(p)
    if overlapsRect(p, x, y, w, h) then
      hit[#hit + 1] = p
    end
  end)
  for _, p in ipairs(hit) do
    props.damage(p, damage)
    -- Strike low on the object so it tumbles away
    props.impulse(p, dir * force, -lift, p.body:getX(), y + h * 0.75)
  end
end

function props.all()
  return list
end

-- Remembers every object's velocity from just before the physics step. A
-- collision happens inside the step and changes the velocity, so impacts
-- have to be judged by the speed the object arrived with.
function props.snapshotVelocities()
  for _, p in ipairs(list) do
    local b = p.body
    if b:isAwake() and b:isActive() then
      p.prevVx, p.prevVy = b:getLinearVelocity()
    else
      p.prevVx, p.prevVy = 0, 0 -- (at rest, or frozen far away)
    end
  end
end

-- Impact damage (design doc §6a): what a moving object does to whatever it
-- hits, from its momentum (mass x speed, in the same units as a kick's
-- impulse). A kicked crate is worth about 7, a heavy iron crate or a big
-- chunk of falling rock far more; slow or resting objects do nothing.
-- vx, vy: the object's own velocity (px/s), so a creature walking into a
-- resting object never counts as an impact.
-- Returns damage (0 when too gentle), and the momentum itself.
local MIN_MOMENTUM = 90 -- below this an object just bumps
local MOMENTUM_PER_DAMAGE = 25

function props.impactDamage(p, vx, vy)
  local momentum = p.body:getMass() * math.sqrt(vx * vx + vy * vy)
  if momentum <= MIN_MOMENTUM then
    return 0, momentum
  end
  return math.floor((momentum - MIN_MOMENTUM) / MOMENTUM_PER_DAMAGE), momentum
end

-- A lit barrel of powder goes off: the blast hurts the hunter, monsters and
-- other props (setting off any more barrels nearby) and carves a crater
local function detonate(p)
  p.broken = true
  local x, y = p.body:getPosition()
  local ex = p.def.explosive
  for _ = 1, 14 do
    local a = love.math.random() * math.pi * 2
    local s = 40 + love.math.random() * 120
    effects.particle(x, y, math.cos(a) * s, math.sin(a) * s - 50, 0.7, { 0.50, 0.31, 0.17 }, 520)
  end
  require("src.bullets").blast(x, y, ex.count, ex.scale, ex.dig, ex.digPower, "keg")
end

function props.update(dt)
  for i = #list, 1, -1 do
    local p = list[i]
    p.flash = math.max(0, p.flash - dt)
    if p.lit and not p.broken then
      p.fuse = p.fuse - dt
      if math.floor(p.fuse * 24) % 2 == 0 then
        p.flash = 0.05 -- blinks white as the fuse burns down
      end
      if p.fuse <= 0 then
        detonate(p)
      end
    end
    if p.broken then
      remove(p)
    end
  end
  -- Only what moves needs its place in the index updated (a resting or
  -- frozen body can't have moved), plus a few others in turn, in case
  -- something put one somewhere
  for _, p in ipairs(list) do
    local b = p.body
    if b:isAwake() and b:isActive() then
      indexProp(p)
    end
  end
  local n = #list
  for _ = 1, math.min(n, 16) do
    refreshAt = refreshAt % n + 1
    indexProp(list[refreshAt])
  end
end

-- Is the prop (by its indexed position) within the view, plus a margin?
local function inView(p, view, margin)
  local x, y = p.ix, p.iy
  return x > view.x - margin and x < view.x + view.w + margin and y > view.y - margin and y < view.y + view.h + margin
end

-- Lamps give light for as long as they stand
function props.addLights(lighting, view)
  local t = love.timer.getTime()
  for _, p in ipairs(list) do
    local l = p.def.light
    if l and not p.broken then
      if inView(p, view, 100) then
        local x, y = p.body:getPosition()
        local c = l.color or p.glow or { 1, 0.8, 0.4 }
        local flick = 1 + math.sin(t * 9 + p.seed) * 0.04 + math.sin(t * 23 + p.seed * 2) * 0.03
        lighting.add(x, y - 1, l.radius, c[1], c[2], c[3], l.intensity * flick)
      end
    end
  end
end

-- Flames, embers and crystal tips, after the lighting
function props.drawEmissive(view)
  local t = love.timer.getTime()
  for _, p in ipairs(list) do
    local emit = p.def.emit
    if emit and not p.broken then
      if inView(p, view, 30) then
        local bx, by = p.body:getPosition()
        love.graphics.push()
        love.graphics.translate(math.floor(bx + 0.5), math.floor(by + 0.5))
        love.graphics.rotate(p.body:getAngle())
        emit(p, t)
        love.graphics.pop()
      end
    end
  end
end

local function drawOne(p)
  love.graphics.push()
  -- Whole-pixel position: a sliding crate moves in clean pixel steps
  -- instead of resampling its pixels every frame
  love.graphics.translate(math.floor(p.body:getX() + 0.5), math.floor(p.body:getY() + 0.5))
  love.graphics.rotate(p.body:getAngle())
  if p.flash > 0 and p.def.showDamage then
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("fill", -math.floor(p.width / 2), -math.floor(p.height / 2), p.width, p.height)
  else
    p.def.draw(p)
  end
  love.graphics.pop()
end

-- view: { x, y, w, h } in world pixels; props well off it are skipped
function props.draw(view)
  for _, p in ipairs(list) do
    if not view or inView(p, view, (p.width + p.height) + 24) then
      drawOne(p)
    end
  end
end

return props
