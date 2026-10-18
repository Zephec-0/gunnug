-- Set dressing for the Barrens (the overworld desert): rock structures cut
-- into the terrain (arches, hoodoos, ruined walls), skeletons half buried in
-- the sand (see the fossils), and one small mirage oasis that turns out to be a
-- dry bed with a coin pouch when the hunter walks up to it.
local barrens = {}

local list = {} -- { kind, x, v }: the buried bones
local mirage -- { x, revealed, t }

local BONE, BONE_DARK = { 0.78, 0.72, 0.60 }, { 0.54, 0.49, 0.40 }

local function rect(x, y, w, h)
  love.graphics.rectangle("fill", x, y, w, h)
end

local paintFossils -- (defined below)

-- Rock structures ------------------------------------------------------------

local function column(world, surface, x0, x1, top, mat)
  for x = x0, x1 do
    local jag = math.floor(love.math.noise(x * 0.31, top) * 4)
    world:fillRect(x, top + jag, x, surface(x) + 3, mat)
  end
end

local function arch(world, surface, cx, mat, rng)
  local h = 62 + rng:random(0, 16)
  local g = surface(cx)
  local gap = 17 + rng:random(0, 4)
  column(world, surface, cx - gap - 13, cx - gap, g - h, mat)
  column(world, surface, cx + gap, cx + gap + 13, g - h, mat)
  for x = cx - gap - 14, cx + gap + 14 do
    local sag = math.floor(((x - cx) / (gap + 14)) ^ 2 * 6)
    local top = g - h - 6 + sag
    world:fillRect(x, top - math.floor(love.math.noise(x * 0.2, 9) * 3), x, g - h + 9 + sag, mat)
  end
end

local function hoodoo(world, surface, cx, mat, rng)
  local h = 46 + rng:random(0, 44)
  local g = surface(cx)
  local stem = 3 + rng:random(0, 2)
  for y = g - h, g + 3 do
    local t = (y - (g - h)) / h
    local half = stem + math.floor((1 - t) ^ 3 * 3) + math.floor(t ^ 4 * 5)
    half = half + math.floor(love.math.noise(y * 0.25, cx) * 2)
    world:fillRect(cx - half, y, cx + half, y, mat)
  end
  -- the balanced cap
  local cap = 9 + rng:random(0, 4)
  for dy = 0, 6 do
    local half = cap - math.floor(dy * 0.9)
    world:fillRect(cx - half, g - h - dy, cx + half, g - h - dy, mat)
  end
end

local function ruin(world, surface, cx, mat, rng)
  local x = cx
  for i = 1, rng:random(4, 6) do
    local w = rng:random(5, 8)
    local h = rng:random(10, 30)
    column(world, surface, x, x + w, surface(x) - h, mat)
    x = x + w + rng:random(10, 20)
  end
  -- one doorway with a lintel still across it
  local dx = x + 4
  column(world, surface, dx, dx + 6, surface(dx) - 36, mat)
  column(world, surface, dx + 26, dx + 32, surface(dx + 26) - 36, mat)
  world:fillRect(dx, surface(dx) - 40, dx + 32, surface(dx) - 33, mat)
end

-- Builds the dressing. `blocked(x)` says where nothing may be put (camp, mine,
-- entrances, the mountain's ramp); lo and hi are the stretch to dress.
function barrens.build(world, surface, seed, lo, hi, blocked, mat, fossilId)
  list = {}
  mirage = nil
  local rng = love.math.newRandomGenerator((seed or 1) * 7 + 13)
  if fossilId then
    paintFossils(world, surface, love.math.newRandomGenerator((seed or 1) * 11 + 5), lo, hi, blocked, fossilId)
  end
  local x = lo
  local arches, oasisPlaced = 0, false
  while x < hi do
    x = x + 110 + rng:random(0, 90)
    if not blocked(x) and not blocked(x - 60) and not blocked(x + 60) then
      local slope = math.abs(surface(x + 30) - surface(x - 30))
      local roll = rng:random()
      if not oasisPlaced and x > 2300 and roll < 0.35 then
        oasisPlaced = true
        mirage = { x = x, revealed = false, t = 0 }
      elseif slope < 18 then
        if roll < 0.12 and arches < 3 then
          arches = arches + 1
          arch(world, surface, x, mat, rng)
          x = x + 60
        elseif roll < 0.28 then
          hoodoo(world, surface, x, mat, rng)
          if rng:random() < 0.5 then
            hoodoo(world, surface, x + 26, mat, rng)
          end
        elseif roll < 0.36 then
          ruin(world, surface, x, mat, rng)
          x = x + 120
        end
      end
    end
  end
end

-- Fossils: skeletons buried in the sand and sandstone, drawn into the terrain
-- itself (bone pixels) so they show in the cut of the ground wherever the view
-- takes in the underground. Each shape is a function that puts bone pixels.

local function skullShape(put, x, y, dir)
  for yy = 0, 4 do
    for xx = 0, 6 do
      local eye = (xx == 2 or xx == 3) and (yy == 1 or yy == 2)
      if not eye then
        put(x + xx * dir, y + yy)
      end
    end
  end
  for xx = 1, 5, 2 do
    put(x + xx * dir, y + 5) -- teeth
  end
  put(x + 7 * dir, y + 3)
end

local function ribsShape(put, x, y, count, h, dir)
  for i = 0, count * 4 do
    put(x + i * dir, y) -- the spine
    put(x + i * dir, y + 1)
  end
  for k = 0, count - 1 do
    local rx = x + 3 + k * 4
    local hh = h - math.abs(k - (count - 1) / 2) * 0.9
    for j = 1, math.floor(hh) do
      local cx = rx + math.floor((j / hh) ^ 2 * 2) * dir
      put(cx, y + j)
      put(cx + 1, y + j)
    end
  end
end

local function legShape(put, x, y, dir, len)
  for i = 0, len do
    put(x + i * dir, y + math.floor(i * 0.25))
    put(x + i * dir, y + math.floor(i * 0.25) + 1)
  end
  put(x - dir, y - 1)
  put(x - dir, y + 1)
  put(x + len * dir + dir, y + math.floor(len * 0.25) + 1)
  put(x + len * dir + dir, y + math.floor(len * 0.25) - 1)
end

local function armShape(put, x, y)
  for j = 0, 8 do
    put(x, y - j)
    put(x + 1, y - j)
  end
  for _, dx in ipairs({ -2, -1, 0, 1, 2 }) do
    for j = 1, 2 + (dx == 0 and 1 or 0) do
      put(x + dx, y - 8 - j)
    end
  end
end

local FOSSILS = {
  -- a whole one, lying on its side: skull, spine, ribs, a thigh bone
  function(put, x, y, dir)
    skullShape(put, x, y, dir)
    ribsShape(put, x + 9 * dir, y + 2, 5, 8, dir)
    legShape(put, x + 31 * dir, y + 3, dir, 9)
    legShape(put, x + 30 * dir, y + 6, dir, 8)
  end,
  -- the great ribcage of some beast, arching up out of the stone, and its horned skull
  function(put, x, y, dir)
    for k = 0, 6 do
      local rx = x + k * 6
      local h = 20 - math.abs(k - 3) * 3
      for j = 0, h do
        put(rx + math.floor((j / h) ^ 2 * 4) * dir, y - j)
        put(rx + math.floor((j / h) ^ 2 * 4) * dir + 1, y - j)
      end
    end
    for i = 0, 40 do
      put(x + i, y)
      put(x + i, y + 1)
    end
    skullShape(put, x - 12 * dir, y - 6, dir)
    for k = 0, 6 do
      put(x - 12 * dir + (8 + math.floor(k * 0.6)) * dir, y - 6 - k)
    end
  end,
  -- two skulls and a scatter of long bones
  function(put, x, y, dir)
    skullShape(put, x, y, dir)
    skullShape(put, x + 14 * dir, y + 4, -dir)
    legShape(put, x + 3, y + 10, 1, 10)
    legShape(put, x + 18, y + 12, -1, 8)
  end,
  -- a whale: a skull the size of a hut, a spine ninety pixels long, eleven great
  -- ribs and the fork of the tail
  function(put, x, y, dir)
    for i = 0, 90 do
      put(x + i * dir, y)
      put(x + i * dir, y + 1)
      put(x + i * dir, y + 2)
      if i % 6 == 3 then
        put(x + i * dir, y - 1) -- the knobs of the vertebrae
      end
    end
    for k = 0, 10 do
      local rx = x + 14 + k * 7
      local h = 36 - math.abs(k - 5) * 4
      for j = 1, h do
        local cx = rx + math.floor((j / h) ^ 2 * 5) * dir
        put(cx, y + 2 + j)
        put(cx + 1, y + 2 + j)
      end
    end
    -- the skull: a long, tall dome with a hollow eye and a lower jaw
    for yy = 0, 12 do
      local width = 22 - math.floor(math.abs(yy - 5) * 1.4)
      for xx = 0, width do
        local eye = (xx >= 14 and xx <= 16) and (yy >= 3 and yy <= 5)
        if not eye then
          put(x - (xx + 4) * dir, y - 5 + yy)
        end
      end
    end
    for xx = 2, 24, 2 do
      put(x - xx * dir, y + 9) -- the teeth along the jaw
      put(x - xx * dir, y + 10)
    end
    for j = 0, 9 do
      put(x + (90 + j) * dir, y - j)
      put(x + (90 + j) * dir, y + 2 + j)
    end
  end,
  -- an arm, reaching for the surface
  function(put, x, y, dir)
    armShape(put, x, y)
    ribsShape(put, x - 6, y + 2, 3, 5, 1)
  end,
}

barrens.fossils = FOSSILS -- (for tests)

paintFossils = function(world, surface, rng, lo, hi, blocked, id)
  local x = lo
  while x < hi do
    x = x + 90 + rng:random(0, 120)
    if not blocked(x) and not blocked(x + 40) and not blocked(x - 40) then
      local dir = rng:random() < 0.5 and -1 or 1
      local pick = rng:random(1, #FOSSILS)
      if pick == 4 and rng:random() < 0.55 then
        pick = 1 -- (whales are rarer)
      end
      local depth = 26 + rng:random(0, 52)
      if pick == 4 then
        depth = 52 + rng:random(0, 40) -- (the whale lies deepest)
        x = x + 60 -- and takes up room
      end
      local y = surface(x) + depth
      local fn = FOSSILS[pick]
      local function put(px, py)
        if rng:random() > 0.14 and world:isSolid(px, py) then -- (a few pixels weathered away)
          world:setRaw(px, py, id)
        end
      end
      fn(put, x, y, dir)
    end
  end
end

-- Drawing --------------------------------------------------------------------

local function drawArm(x, g, v)
  love.graphics.setColor(BONE_DARK)
  rect(x, g - 7, 2, 7)
  love.graphics.setColor(BONE)
  rect(x, g - 11, 2, 5)
  for i = -2, 2, 2 do
    rect(x + i, g - 14 + math.abs(i) / 2, 1, 3) -- the fingers
  end
  rect(x - 1, g - 11, 4, 1)
end

local function drawRibs(x, g, v)
  for i = 0, 4 do
    local bx = x + i * 5
    local h = 9 - math.abs(i - 2) * 2
    love.graphics.setColor(BONE)
    for k = 0, h do
      rect(bx + math.floor((k / h) ^ 2 * 2), g - 1 - k, 1, 1)
    end
  end
  love.graphics.setColor(BONE_DARK)
  rect(x, g - 2, 21, 1) -- the spine
end

local function drawSkull(x, g, v)
  love.graphics.setColor(BONE)
  rect(x, g - 6, 7, 5)
  rect(x + 1, g - 7, 5, 1)
  love.graphics.setColor(0.10, 0.08, 0.08)
  rect(x + 1, g - 5, 2, 2)
  rect(x + 4, g - 5, 2, 2)
  love.graphics.setColor(BONE_DARK)
  rect(x + 2, g - 2, 1, 2)
  rect(x + 4, g - 2, 1, 2)
  if v > 0.5 then
    -- a pickaxe beside it
    love.graphics.setColor(0.42, 0.28, 0.16)
    rect(x + 11, g - 9, 1, 9)
    love.graphics.setColor(0.60, 0.62, 0.68)
    rect(x + 8, g - 10, 7, 1)
    rect(x + 8, g - 9, 1, 1)
    rect(x + 14, g - 9, 1, 1)
  end
end

local function drawLegs(x, g, v)
  -- two legs and a boot sticking out of the sand
  love.graphics.setColor(BONE)
  rect(x, g - 8, 1, 8)
  rect(x + 4, g - 6, 1, 6)
  love.graphics.setColor(0.34, 0.24, 0.16)
  rect(x - 2, g - 11, 4, 4)
  love.graphics.setColor(BONE_DARK)
  rect(x + 3, g - 7, 3, 1)
end

local function drawSitting(x, g, v)
  -- a skeleton propped against nothing, slumped, a hat beside it
  love.graphics.setColor(BONE)
  rect(x, g - 9, 4, 4) -- skull
  love.graphics.setColor(0.10, 0.08, 0.08)
  rect(x + 1, g - 8, 1, 1)
  rect(x + 3, g - 8, 1, 1)
  love.graphics.setColor(BONE)
  rect(x + 1, g - 5, 2, 5)
  rect(x - 2, g - 3, 3, 1)
  rect(x + 3, g - 2, 5, 1)
  love.graphics.setColor(0.30, 0.22, 0.14)
  rect(x + 10, g - 2, 6, 2)
  rect(x + 11, g - 4, 4, 2)
end

local DRAW = { drawArm, drawRibs, drawSkull, drawLegs, drawSitting }

local function drawMirage(m, surface, t)
  local g = surface(m.x)
  if m.revealed then
    -- the dry bed: cracked ground and a bleached skull
    love.graphics.setColor(0.62, 0.50, 0.34)
    rect(m.x - 22, g - 1, 44, 2)
    love.graphics.setColor(0.46, 0.36, 0.25)
    for i = -18, 18, 6 do
      rect(m.x + i, g - 1, 1, 2)
      rect(m.x + i + 2, g, 3, 1)
    end
    drawSkull(m.x - 4, g, 0.1)
    return
  end
  local a = 0.55 + 0.2 * math.sin(t * 1.3)
  -- shimmering pond: bands of blue that wobble sideways
  for row = 0, 5 do
    local wob = math.floor(math.sin(t * 2 + row * 1.3) * 2)
    love.graphics.setColor(0.45 + row * 0.03, 0.72, 0.85, a * (1 - row * 0.1))
    rect(m.x - 22 + wob + row, g - 6 + row, 44 - row * 2, 1)
  end
  -- two palms, doubled and faint below as a reflection
  for _, dx in ipairs({ -15, 14 }) do
    local sway = math.floor(math.sin(t * 1.1 + dx) * 1.5)
    love.graphics.setColor(0.40, 0.30, 0.18, a)
    for k = 0, 17 do
      rect(m.x + dx + math.floor(k * 0.08) + sway * (k > 12 and 1 or 0), g - 7 - k, 1, 1)
    end
    love.graphics.setColor(0.30, 0.62, 0.30, a)
    local top = g - 25
    for i = -6, 6 do
      rect(m.x + dx + sway + i, top + math.floor(math.abs(i) * 0.7), 1, 1)
      rect(m.x + dx + sway + i, top + math.floor(math.abs(i) * 0.7) + 1, 1, 1)
    end
    love.graphics.setColor(0.30, 0.62, 0.30, a * 0.25)
    for k = 0, 6 do
      rect(m.x + dx + sway + math.floor(math.sin(t * 2 + k) * 2), g - 5 + k * 0.4, 1, 1)
    end
  end
  -- heat shimmer above it
  love.graphics.setColor(1, 0.9, 0.7, 0.10)
  for i = 0, 3 do
    rect(m.x - 26 + math.floor(math.sin(t * 3 + i) * 3), g - 30 - i * 3, 52, 1)
  end
end

function barrens.draw(vx0, vx1, surface)
  love.graphics.setColor(1, 1, 1)
  for _, b in ipairs(list) do
    if b.x > vx0 - 30 and b.x < vx1 + 30 then
      DRAW[b.kind](b.x, surface(b.x + 2) + 1, b.v)
    end
  end
  if mirage and mirage.x > vx0 - 40 and mirage.x < vx1 + 40 then
    drawMirage(mirage, surface, love.timer.getTime())
  end
  love.graphics.setColor(1, 1, 1)
end

-- Walking up to the mirage: it breaks, and what was left there is a pouch of coins
function barrens.update(dt, player, effects, pickups)
  if mirage and not mirage.revealed then
    local px, py = player:center()
    if math.abs(px - mirage.x) < 44 and math.abs(py - (player.world:findGround(mirage.x, 160) - 10)) < 40 then
      mirage.revealed = true
      for _ = 1, 24 do
        effects.particle(mirage.x + (love.math.random() - 0.5) * 44, player.world:findGround(mirage.x, 160) - 4 - love.math.random() * 10, (love.math.random() - 0.5) * 30, -10 - love.math.random() * 20, 0.8, { 0.5, 0.78, 0.9 }, -20, true)
      end
      effects.popup(mirage.x, player.world:findGround(mirage.x, 160) - 30, "Just a mirage...", { 0.7, 0.85, 0.95 })
      pickups.dropGold(mirage.x, player.world:findGround(mirage.x, 160) - 8, 40)
    end
  end
end

return barrens
