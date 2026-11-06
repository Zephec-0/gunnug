-- Environmental storytelling outside the four ways down from the Barrens (docs/todo.md, 2026-11-04): what the
-- people who went in left behind. The terrain work and the ground colouring are done at build time (world tints
-- and carved terraces); the standing dressing (graves, a pier, a crane, banners) is drawn every frame with the rest
-- of the ground-level scenery (src.scenes.overworld).
--   The Old Mine   : a rope across the way down, a spilled cart
--   Sunken Hollows : a pier into the lake, a swamped rowboat, the roof of a drowned cabin, nets drying on the beach
--   The Quarry     : a stepped pit round the crevice, cut blocks, a derrick and a sled, the ground paling to the
--                    quarry's own stone and rust
--   The Needle     : the ground darkening toward the mountain, standing stones and tattered banners up the ramp
local materials = require("src.materials")

local entrances = {}

local STONEBRICK, STONE, AIR, SAND, SANDSTONE = materials.STONEBRICK, materials.ROCK, materials.AIR, materials.SAND, materials.SANDSTONE
local HOSTS = { SAND } -- (only the surface sand takes the colour, not the rock under it)

local QUARRY_X, QUARRY_HALF = 4300, 19
local MINE = { rope0 = 1590, rope1 = 1722 }
local NEEDLE_X0, NEEDLE_X1 = 5000, 5860
local MOUTH_X = 5916 -- the face of the mountain where the doorway is cut (src.cavegen carveWalkIn)

local theWorld
local lake -- { x0, x1, top, e = the entry } once built
local surfaceAt

local function R(c, x, y, w, h, a)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
  love.graphics.rectangle("fill", math.floor(x), math.floor(y), w, h)
end

local function tint(world, x0, x1, layers, hosts, y0, y1)
  world:addTint(x0, y0 or 150, x1, y1 or 720, layers, hosts or HOSTS)
end

-- The stepped pit round the quarry's crevice: terraces going down toward it on both sides, a block or two left on
-- each, the cut faces in worked stone. `terraces` remembers each tread so the dressing stands on it.
local STEPS, TREAD, RISE = 7, 36, 9
local SHAFT_LEN = 320 -- how far down the crevice the light and the wall gradient run
local terraces = {}

local function floorAt(x, fallback)
  for _, t in ipairs(terraces) do
    if x >= t.x0 and x <= t.x1 then
      return t.y
    end
  end
  return fallback
end

-- Where things stand at x: the terrace tread there, else the ground (the lamp posts at the crevice use it)
-- How much of the near scenery (the mesas and ruined towers on the horizon) to show with the camera at x: none over
-- the lake, where they read as slabs hanging in the air over the water (there is no plain behind it, just the bowl),
-- easing back in over 220 px past either bank
function entrances.sceneryFade(x)
  if not lake then
    return 1
  end
  local d = math.max(lake.x0 - x, x - lake.x1, 0)
  return math.min(1, d / 220)
end

function entrances.groundAt(x, fallback)
  return floorAt(x, fallback)
end

-- Where something at x stands: on the lake's beach or bowl floor (the real ground there), on a quarry terrace, else
-- on the ground line (the journal's pages use it)
local groundTopFn
function entrances.standY(x)
  if lake and theWorld and x >= lake.x0 - 120 and x <= lake.x1 + 120 and groundTopFn then
    return groundTopFn(x)
  end
  return floorAt(x, surfaceAt and surfaceAt(x) or nil)
end

local function buildQuarry(world, surface)
  terraces = {}
  for side = -1, 1, 2 do
    for k = 1, STEPS do
      local a = QUARRY_X + side * (QUARRY_HALF + 1 + (k - 1) * TREAD)
      local b = QUARRY_X + side * (QUARRY_HALF + k * TREAD)
      local x0, x1 = math.min(a, b), math.max(a, b)
      local depth = (STEPS - k + 1) * RISE -- (the nearest terrace is the lowest)
      local floorY = surface(a) + depth
      terraces[#terraces + 1] = { x0 = x0, x1 = x1, y = floorY, k = k }
      for x = x0, x1 do
        world:fillRect(x, surface(x) - 12, x, floorY - 1, AIR) -- (cut down from the ground line)
      end
      world:fillRect(x0, floorY, x1, floorY + 1, STONEBRICK) -- (the worked tread, in cut blocks)
      if k % 2 == 1 then -- a dressed block left standing, and a half-cut one beside it
        local bx = x0 + 6 + (k * 7) % 11
        world:fillRect(bx, floorY - 9, bx + 12, floorY - 1, STONEBRICK)
        world:fillRect(bx + 15, floorY - 4, bx + 20, floorY - 1, STONEBRICK)
      end
      if k == 1 then -- the lips of the crevice, back at the foot of the steps where the way down is
        local lip = side == -1 and x1 - 3 or x0
        world:fillRect(lip, floorY - 13, lip + 3, floorY - 1, STONEBRICK)
      end
      -- the squared riser up to the next tread out, three blocks thick
      local o0, o1 = side == -1 and x0 - 3 or x1 + 1, side == -1 and x0 - 1 or x1 + 3
      world:fillRect(o0, floorY - RISE - 1, o1, floorY + 1, STONEBRICK)
    end
  end
  -- The ground takes on the Quarry's own pale cut stone and grey spoil toward the pit, in the surface sand, the
  -- sandstone under it for a hundred px or so, and the cut blocks: full strength at the crevice, so the way down
  -- is the same colours as the first area below
  local rockTop, spoil = { 0.80, 0.68, 0.52 }, { 0.56, 0.50, 0.42 }
  local hosts = { SAND, SANDSTONE, STONEBRICK }
  for side = -1, 1, 2 do
    local x0, x1 = QUARRY_X + (side == -1 and -400 or 1), QUARRY_X + (side == -1 and -1 or 400)
    tint(world, x0, x1, {
      { kind = "wash", color = rockTop, amount = 0.7, xa = QUARRY_X + side * 400, xb = QUARRY_X + side * 40, seed = 3, y0 = 330, y1 = 660 },
      { kind = "wash", color = spoil, amount = 0.3, xa = QUARRY_X + side * 220, xb = QUARRY_X + side * 20, seed = 6, y0 = 330, y1 = 660 },
    }, hosts, 330, 660)
  end
end

-- The far wall of the cut: one stepped face of cut blocks across the whole pit, up to the old ground line, so
-- nothing of the hills behind shows through the notch. Behind each tread a flat-topped face level with the ground
-- there; the face over the crevice stands at the nearest tread's height. Drawn in world coordinates in the decor pass, over the earth backdrop and under the terrain.
function entrances.drawBackdrop(camX, camY, offX, offY)
  offX, offY = offX or camX, offY or camY
  if not surfaceAt or #terraces == 0 then
    return
  end
  local inner
  for _, t in ipairs(terraces) do
    if t.k == 1 and (not inner or t.y > inner.y) then
      inner = t
    end
  end
  local list = {}
  for _, t in ipairs(terraces) do
    list[#list + 1] = t
  end
  -- (over the crevice itself)
  list[#list + 1] = { x0 = QUARRY_X - QUARRY_HALF, x1 = QUARRY_X + QUARRY_HALF, y = inner.y, k = 1 }
  for _, t in ipairs(list) do
    if t.x1 > camX - 4 and t.x0 < camX + 700 then
      local top = math.min(surfaceAt(t.x0), surfaceAt(t.x1)) - 2
      local x0, w = math.floor(t.x0 - offX), t.x1 - t.x0 + 1
      local y0, h = math.floor(top - offY), t.y - top
      love.graphics.setColor(0.62, 0.49, 0.38, 1)
      love.graphics.rectangle("fill", x0, y0, w, h)
      love.graphics.setColor(0.54, 0.42, 0.33, 1)
      love.graphics.rectangle("fill", x0, y0 + math.floor(h * 0.55), w, h - math.floor(h * 0.55)) -- (a shade deeper lower down)
      love.graphics.setColor(0.74, 0.61, 0.47, 1)
      love.graphics.rectangle("fill", x0, y0, w, 2) -- (the lit top edge)
      love.graphics.setColor(0.43, 0.33, 0.26, 1)
      local row = 0
      for y = 8, h - 1, 8 do
        love.graphics.rectangle("fill", x0, y0 + y, w, 1) -- the course
        row = row + 1
        for x = (row % 2) * 9, w - 1, 18 do
          love.graphics.rectangle("fill", x0 + x, y0 + y - 8, 1, 8) -- the joints, staggered
        end
      end
      love.graphics.setColor(0.32, 0.24, 0.19, 0.45)
      love.graphics.rectangle("fill", x0, y0 + h - 5, w, 5) -- (shadow where it meets the tread)
    end
  end
  -- Down the crevice: the wall carries on in the cut stone's own tone, then darkens into the cave's earth with depth,
  -- so the opening of the hole and the cut around it are one piece. (The same warm gradient the mine's shaft has.)
  local sx0, sx1 = QUARRY_X - QUARRY_HALF, QUARRY_X + QUARRY_HALF
  local top = inner.y
  local len = math.max(80, 760 - top) -- (dark by where the cave's own backdrop takes over)
  for y = top, top + len, 4 do
    local f = math.min(1, (y - top) / len)
    local e = f ^ 0.7
    love.graphics.setColor(0.54 + (0.10 - 0.54) * e, 0.42 + (0.07 - 0.42) * e, 0.33 + (0.07 - 0.33) * e, 1)
    love.graphics.rectangle("fill", sx0 - offX, y - offY, sx1 - sx0 + 1, 4)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- The last of the evening sun falling down the crevice, like the mine's shaft: a warm column of light that thins with
-- depth and breathes slowly, spreading a little at the mouth (drawn with the glows, over the lit scene)
function entrances.drawEmissive(camX, camY, sunlight)
  if not surfaceAt or #terraces == 0 or sunlight <= 0.02 then
    return
  end
  local top = terraces[1].y
  for _, t in ipairs(terraces) do
    if t.k == 1 then
      top = t.y
    end
  end
  if camY > top + SHAFT_LEN + 60 or camY + 400 < top - 40 or camX > QUARRY_X + 200 or camX + 700 < QUARRY_X - 200 then
    return
  end
  local t = love.timer.getTime()
  local x0, x1 = QUARRY_X - QUARRY_HALF, QUARRY_X + QUARRY_HALF
  local bottom = top + SHAFT_LEN + 60
  for y = top, bottom, 6 do
    local k = (y - top) / (bottom - top)
    local a = 0.19 * math.min(1, k * 12) * (1 - k) ^ 1.5 * (0.85 + 0.15 * math.sin(t * 0.8 + k * 5)) * sunlight
    love.graphics.setColor(1, 0.78, 0.45, a)
    love.graphics.rectangle("fill", x0, y, x1 - x0 + 1, 6)
  end
  -- (a soft widening at the mouth, where the light comes over the bench)
  for i = 0, 7 do
    local spread = 3 + i * 2
    love.graphics.setColor(1, 0.8, 0.5, 0.03 * sunlight * (1 - i / 8))
    love.graphics.rectangle("fill", x0 - spread, top - 14 + i * 4, x1 - x0 + 1 + spread * 2, 4)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

local moteTimer = 0
-- Dust turning slowly in the light of the crevice (px, py: the hunter)
function entrances.update(dt, px, py)
  if not surfaceAt or #terraces == 0 then
    return
  end
  moteTimer = moteTimer - dt
  if moteTimer <= 0 and math.abs(px - QUARRY_X) < 500 and py < 1000 then
    moteTimer = 0.1
    local top = terraces[1].y
    for _, t in ipairs(terraces) do
      if t.k == 1 then
        top = t.y
      end
    end
    local x0, x1 = QUARRY_X - QUARRY_HALF, QUARRY_X + QUARRY_HALF
    require("src.effects").particle(x0 + 2 + love.math.random() * (x1 - x0 - 4), top + love.math.random() * 300, (love.math.random() - 0.5) * 6, 3 + love.math.random() * 5, 3, { 1, 0.85, 0.55 }, 0, true)
  end
end

-- The Needle: the ground goes from sand to near black slate with rust seams on the ramp up to the mountain
local function buildNeedle(world)
  -- (a change of ground, not of the rock: only the surface sand, taking on the mountain's own sandstone and a little
  -- shade as it nears the face, so the ground and the cave mouth belong together)
  tint(world, NEEDLE_X0, NEEDLE_X1 + 140, {
    { kind = "wash", color = { 0.54, 0.32, 0.25 }, amount = 0.75, xa = NEEDLE_X0 + 100, xb = NEEDLE_X1 - 100, seed = 11 },
    { kind = "wash", color = { 0.30, 0.20, 0.20 }, amount = 0.30, xa = NEEDLE_X0 + 500, xb = NEEDLE_X1, seed = 4 },
  })
end

-- The lake's ground, all in one continuous tint (no seams, no material swaps): going toward the water the sand slowly
-- darkens to a brown dirt. That brown holds on the bowl's edges and upper part, and with depth it gives way to the
-- Flooded Caverns' own colours (the blue clay and slate of its palette, and algae in the deep of the bowl).
local REACH = 360 -- how far from the water the browning starts

local function buildLake(world, e, waterTop)
  local x0, x1 = e.x - e.half, e.x + e.half
  local brown, slate, algae = { 0.44, 0.31, 0.21 }, { 0.26, 0.34, 0.47 }, { 0.16, 0.40, 0.32 }
  local hosts = { SAND, SANDSTONE }
  -- (each layer is a band in height as well: the brown is strongest at the ground and over the upper bowl and
  -- fades out with depth; the dungeon's colours fade in below it)
  -- (one tint box per bank: a wash holds its full strength on the far side of its range, so a west bank's layers inside a
  -- box that also took in the east bank would have painted the whole east side brown up to the box's hard edge)
  local mid = e.x
  tint(world, x0 - REACH - 60, mid, {
    { kind = "wash", color = brown, amount = 0.7, xa = x0 - REACH, xb = x0 + 80, seed = 9, y0 = 420, y1 = 660 },
    { kind = "wash", color = slate, amount = 0.55, xa = x0 + 20, xb = x0 + 240, seed = 5, y0 = 560, y1 = 860 },
    { kind = "wash", color = algae, amount = 0.3, xa = x0 + 100, xb = x0 + 320, seed = 3, y0 = 620, y1 = 900 },
  }, hosts, 420, 900)
  tint(world, mid + 1, x1 + REACH + 60, {
    { kind = "wash", color = brown, amount = 0.7, xa = x1 + REACH, xb = x1 - 80, seed = 9, y0 = 420, y1 = 660 },
    { kind = "wash", color = slate, amount = 0.55, xa = x1 - 20, xb = x1 - 240, seed = 5, y0 = 560, y1 = 860 },
    { kind = "wash", color = algae, amount = 0.3, xa = x1 - 100, xb = x1 - 320, seed = 3, y0 = 620, y1 = 900 },
  }, hosts, 420, 900)
end

function entrances.build(world, surface, lakes, entries)
  surfaceAt = surface
  theWorld = world
  lake = nil
  for _, e in ipairs(entries) do
    if e.lake then
      lake = { e = e, x0 = e.x - e.half, x1 = e.x + e.half, top = lakes[1] and lakes[1].top or surface(e.x) + 36 }
      buildLake(world, e, lake.top)
    end
  end
  buildQuarry(world, surface)
  buildNeedle(world)
end

------------------------------------------------------------------------------------------------------------------------
-- Drawing
------------------------------------------------------------------------------------------------------------------------
local WOOD, WOOD_D, WOOD_L = { 0.36, 0.25, 0.15 }, { 0.22, 0.15, 0.10 }, { 0.52, 0.38, 0.22 }
local IRON = { 0.30, 0.30, 0.34 }
local CLOTH = { 0.55, 0.22, 0.18 }

local function drawMine(vx0, vx1)
  if vx1 < MINE.rope0 - 40 or vx0 > MINE.rope1 + 40 then
    return
  end
  local s = surfaceAt
  -- a rope across the way down at the pit's two rims, sagging between posts
  for _, px in ipairs({ MINE.rope0, MINE.rope1 }) do
    local pg = s(px)
    R(WOOD_D, px, pg - 12, 2, 12)
    R(CLOTH, px - 1, pg - 13, 4, 2)
  end
  -- (the cord drawn only as a short sag off each post: the shaft itself is open)
  for k = 0, 8 do
    local x = MINE.rope0 + 2 + k
    R({ 0.72, 0.62, 0.42 }, x, s(MINE.rope0) - 11 + math.floor(math.sin(k / 8 * math.pi) * 3), 1, 1)
  end
end

-- the beach's ground line at column x (the first solid cell going down), remembered
local groundCache = {}
local function groundTop(x)
  local g = groundCache[x]
  if not g then
    local y = surfaceAt(x) - 40
    while y < surfaceAt(x) + 300 and not theWorld:isSolid(x, y) do
      y = y + 1
    end
    g = y
    groundCache[x] = g
  end
  return g
end

-- Plants: a cheap hash per column, so each stays the same from frame to frame
groundTopFn = groundTop

local function hash(x, k)
  local h = math.sin(x * 12.9898 + k * 78.233) * 43758.5453
  return h - math.floor(h)
end

-- where the beach meets the water on each side (the ground comes up to the waterline), found once
local function findShores()
  local top = lake.top
  local x = lake.x1 - 220
  while x < lake.x1 and groundTop(x) > top do
    x = x + 1
  end
  lake.shore = x
  x = lake.x0 + 220
  while x > lake.x0 - 200 and groundTop(x) > top do
    x = x - 1
  end
  lake.shoreW = x
end

-- Grass and earth: the closer the ground is to the water, the more of it grows (thick at the shoreline, thinning
-- to bare sand some 260 px out). Blades and a few flowers drawn along the ground line.
local function drawShoreGrowth(vx0, vx1)
  local top = lake.top
  local WARM = { { 0.18, 0.28, 0.16 }, { 0.30, 0.44, 0.22 }, { 0.50, 0.64, 0.30 } } -- (earth's own blades)
  local COLD = { { 0.12, 0.30, 0.30 }, { 0.22, 0.46, 0.42 }, { 0.42, 0.68, 0.58 } } -- (the blue clay's, the dungeon's)
  for x = math.floor(vx0), math.ceil(vx1) do
    local dist
    if x >= lake.shore then
      dist = x - lake.shore
    elseif x <= lake.shoreW then
      dist = lake.shoreW - x
    end
    if dist and dist < 260 then
      local g = groundTop(x)
      if g <= top + 1 then
        local density = (1 - dist / 260) ^ 1.3
        local r = hash(x, 1)
        if r < density * 0.95 then
          local h = 2 + math.floor(hash(x, 2) * (2 + density * 5))
          local c = WARM[1 + math.floor(hash(x, 3) * 3)]
          local lean = math.floor(math.sin(love.timer.getTime() * 1.3 + x * 0.21) * 1.2 + 0.5)
          R(c, x, g - h, 1, h)
          R(c, x + lean, g - h - 1, 1, 1)
          if r < density * 0.05 then -- a pale flower here and there
            R({ 0.86, 0.80, 0.50 }, x, g - h - 2, 1, 1)
          end
        end
      end
    end
  end
end

-- Under the water: kelp and weed on the slopes and the floor of the bowl, a little coral and a few shells. They sway
-- slowly; drawn before the water, so it tints them into the dark.
local function drawUnderwater(vx0, vx1)
  local top = lake.top
  local t = love.timer.getTime()
  local KELP = { { 0.09, 0.28, 0.14 }, { 0.17, 0.44, 0.22 }, { 0.36, 0.70, 0.36 } }
  local x0 = math.max(math.floor(vx0 / 3) * 3, lake.x0 + 6)
  for x = x0, math.min(vx1, lake.x1 - 4), 3 do
    local g = groundTop(x)
    local depth = g - top
    if depth > 2 and depth < 400 then
      local r = hash(x, 5)
      -- thicker on the shallows and the slopes, thinner in the deep dark
      local cover = 0.55 * (1 - math.min(1, depth / 300))
      if r < cover then
        local kind = hash(x, 6)
        local ph = hash(x, 7) * 6.28
        if kind < 0.55 then
          -- kelp: a tapering strand of segments swaying
          local h = 8 + math.floor(hash(x, 8) * 22)
          local c = KELP[1 + math.floor(hash(x, 9) * 3)]
          for k = 0, h - 1, 2 do
            local sway = math.floor(math.sin(t * 0.9 + ph + k * 0.22) * (k / h) * 3 + 0.5)
            R(c, x + sway, g - 1 - k, 2 - ((k > h * 0.6) and 1 or 0), 2)
          end
        elseif kind < 0.75 then
          -- weed: a short bunch of fine blades
          local h = 4 + math.floor(hash(x, 10) * 8)
          for b = -1, 1 do
            for k = 0, h - 1 do
              local sway = math.floor(math.sin(t * 1.2 + ph + k * 0.3 + b) * (k / h) * 2 + 0.5)
              R({ 0.15, 0.40, 0.37 }, x + b + sway, g - 1 - k, 1, 1)
            end
          end
        elseif kind < 0.88 then
          -- coral: a squat branching head
          local c = hash(x, 11) < 0.5 and { 0.85, 0.38, 0.44 } or { 0.85, 0.60, 0.22 }
          R(c, x, g - 4, 1, 4)
          R(c, x - 1, g - 6, 1, 3)
          R(c, x + 1, g - 5, 1, 3)
          R({ 1.0, 0.72, 0.66 }, x, g - 5, 1, 1)
        else
          -- a handful of shells
          R({ 0.64, 0.70, 0.72 }, x, g - 2, 3, 2)
          R({ 0.44, 0.49, 0.54 }, x, g - 1, 3, 1)
        end
      end
    end
  end
end

local function drawLake(vx0, vx1)
  if not lake or not theWorld or vx1 < lake.x0 - 240 or vx0 > lake.x1 + 280 then
    return
  end
  if not lake.shore then
    findShores()
  end
  local top = lake.top
  local shore = lake.shore
  drawShoreGrowth(vx0, vx1)
  drawUnderwater(vx0, vx1)
  -- what is left of the old works: the mine's rails run on down the beach and into the water, an ore cart left part
  -- way down
  for x = shore + 10, shore - 120, -1 do
    local y = groundTop(x) - 1
    R(IRON, x, y - 1, 1, 1)
    if x % 6 == 0 then
      R(WOOD_D, x, y, 1, 2)
    end
  end
  local cx = shore - 66
  local cy = groundTop(cx + 8) - 1
  R({ 0.30, 0.20, 0.15 }, cx, cy - 9, 16, 8)
  R({ 0.20, 0.14, 0.11 }, cx, cy - 9, 16, 2)
  R({ 0.40, 0.28, 0.20 }, cx + 1, cy - 6, 14, 1)
  R(IRON, cx + 2, cy - 2, 3, 3)
  R(IRON, cx + 11, cy - 2, 3, 3)
end

local function drawQuarry(vx0, vx1)
  if vx1 < QUARRY_X - 200 or vx0 > QUARRY_X + 200 then
    return
  end
  local function G(x)
    return floorAt(x, surfaceAt(x))
  end
  -- a timber derrick on a right-hand terrace: a mast, a boom leaning out over the pit, a rope and a hook
  local mx = QUARRY_X + 140
  local g = G(mx)
  R(WOOD_D, mx, g - 52, 3, 52)
  R(WOOD_D, mx - 10, g - 3, 23, 3) -- the base
  R(WOOD_L, mx + 1, g - 52, 1, 52)
  for k = 0, 40 do
    R(WOOD, mx - k, g - 52 + math.floor(k * 0.28), 1, 3)
  end
  R({ 0.72, 0.62, 0.42 }, mx - 41, g - 40, 1, 24) -- the rope
  R(IRON, mx - 43, g - 16, 5, 3)
  R(IRON, mx - 41, g - 13, 1, 3)
  -- a sled with a block on it left on a far left terrace, and its rope
  local sx = QUARRY_X - 150
  local sg = G(sx)
  R(WOOD_D, sx - 2, sg - 3, 36, 3)
  R({ 0.60, 0.54, 0.46 }, sx + 4, sg - 14, 22, 11)
  R({ 0.74, 0.68, 0.58 }, sx + 4, sg - 14, 22, 2)
  R({ 0.46, 0.40, 0.34 }, sx + 4, sg - 5, 22, 2)
  R({ 0.72, 0.62, 0.42 }, sx + 34, sg - 3, 14, 1)
  -- a stack of dressed blocks and a barrel of chisels on a nearer terrace (the stack on the level, not across a riser)
  local kx = QUARRY_X - 100
  local kg = G(kx + 20)
  for r = 0, 2 do
    for c = 0, 2 - r do
      R({ 0.62 - r * 0.03, 0.56 - r * 0.03, 0.47 }, kx + c * 10 + r * 5, kg - (r + 1) * 8, 9, 8)
      R({ 0.40, 0.35, 0.30 }, kx + c * 10 + r * 5, kg - r * 8 - 1, 9, 1)
    end
  end
  local bx = QUARRY_X + 75
  local bg = G(bx + 3)
  R(WOOD, bx, bg - 8, 7, 8)
  R(IRON, bx, bg - 6, 7, 1)
  R(IRON, bx + 2, bg - 12, 1, 5)
  R(IRON, bx + 5, bg - 11, 1, 4)
end

-- Banners on poles, tattered, and standing stones (dark slabs with a pale glint along one edge), thickening up the ramp
local STONES = { 5120, 5260, 5360, 5440, 5510, 5580, 5650, 5710, 5760, 5805 }

local function drawNeedle(vx0, vx1)
  if vx1 < NEEDLE_X0 or vx0 > NEEDLE_X1 + 40 then
    return
  end
  local s = surfaceAt
  local t = love.timer.getTime()
  for i, x in ipairs(STONES) do
    if x > vx0 - 30 and x < vx1 + 30 then
      local g = s(x + 3)
      local f = i / #STONES
      local h = 18 + f * 34 + (i * 7) % 11
      local w = 8 + (i % 3) * 3
      local d = 0.27 - f * 0.12
      R({ d, d * 0.85, d * 1.1 }, x, g - h, w, h + 2) -- the slab
      R({ d * 0.6, d * 0.5, d * 0.7 }, x + w - 2, g - h, 2, h + 2) -- its shadowed side
      R({ 0.55, 0.45, 0.60 }, x, g - h, 1, h * 0.6, 0.35 + 0.25 * f) -- a pale edge catching the last of the light
      R({ d, d * 0.85, d * 1.1 }, x + 1, g - h - 2, w - 2, 2) -- worn crown
      if i % 3 == 0 then
        -- a banner on a pole beside it, torn and stirring in the wind
        local bx = x + w + 4
        R(WOOD_D, bx, g - 40, 2, 40)
        for k = 0, 9 do
          local wave = math.floor(math.sin(t * 2.2 + k * 0.6 + i) * 1.5)
          local len = 14 - (k % 3) * 3
          R({ 0.34, 0.12, 0.16 }, bx + 2, g - 39 + k * 2 + wave, len, 2)
        end
        R({ 0.62, 0.50, 0.30 }, bx - 1, g - 41, 4, 2)
      end
    end
  end
end

-- The doorway into the Needle was a bare black slot in a cliff. Dressed so it belongs to the ground leading up to it:
-- the sand drifts into the opening, rock teeth hang from the real roof, fallen stones lie at the jambs, and the dark
-- comes on gradually inside instead of at the cut. Everything follows the cut as it is in the world, so nothing hangs
-- in open air.
local function roofAt(x, g)
  -- the underside of the roof at column x: scanning down from high up, the first air cell below solid rock
  local solid = false
  for y = g - 70, g do
    if theWorld:isSolid(x, y) then
      solid = true
    elseif solid then
      return y
    end
  end
  return nil
end

local function drawMouth(vx0, vx1)
  if not theWorld or vx1 < MOUTH_X - 40 or vx0 > MOUTH_X + 140 then
    return
  end
  local g = surfaceAt(MOUTH_X - 8)
  for x = MOUTH_X - 12, MOUTH_X + 70 do
    local roof = roofAt(x, g)
    if roof then
      local i = x - (MOUTH_X - 12)
      -- the dark settles in with depth (only the air of the opening)
      local floorY = roof
      while floorY < g + 4 and not theWorld:isSolid(x, floorY) do
        floorY = floorY + 1
      end
      local a = math.min(0.75, 0.75 * ((x - MOUTH_X + 12) / 62) ^ 0.8)
      R({ 0.03, 0.02, 0.03 }, x, roof, 1, floorY - roof, a)
      -- a tooth of rock hanging from the roof here and there
      if i % 3 == 0 then
        local len = 2 + math.floor((math.sin(i * 1.7) + 1) * 2.2) + (i % 9 == 0 and 3 or 0)
        local d = 0.42 - len * 0.03
        R({ d * 1.25, d * 0.75, d * 0.6 }, x, roof, 2, math.min(len, floorY - roof - 6))
      end
    end
  end
  -- the sand on the floor drifts in, thinning out
  for i = 0, 36 do
    local h = math.floor(5 * (1 - i / 36) ^ 1.5 + 0.5 + math.sin(i * 0.9) * 0.4)
    if h > 0 then
      R({ 0.60, 0.40, 0.29 }, MOUTH_X - 14 + i, g - h + 1, 1, h)
      R({ 0.70, 0.50, 0.37 }, MOUTH_X - 14 + i, g - h + 1, 1, 1)
    end
  end
  -- a fallen slab at the jamb
  R({ 0.34, 0.22, 0.18 }, MOUTH_X - 24, g - 7, 11, 7)
  R({ 0.46, 0.31, 0.24 }, MOUTH_X - 24, g - 7, 11, 1)
  R({ 0.34, 0.22, 0.18 }, MOUTH_X - 13, g - 4, 6, 4)
end

function entrances.draw(vx0, vx1)
  if not surfaceAt then
    return
  end
  drawMine(vx0, vx1)
  drawLake(vx0, vx1)
  drawQuarry(vx0, vx1)
  drawNeedle(vx0, vx1)
  drawMouth(vx0, vx1)
  love.graphics.setColor(1, 1, 1, 1)
end

return entrances
