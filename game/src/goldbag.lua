-- The gold readout: a brown sack, see-through except for its edges, with the
-- run's gold sitting in it as coins (one coin per two gold). The coins are
-- real little rigid bodies in a physics world of their own (nothing to do with
-- the game's), so they pile up and heap above the mouth of the sack when it
-- is overfilled. They have inertia: every change in the hunter's speed throws
-- them the other way (a jump presses them down, a landing bounces them up,
-- turning sloshes them across), his footsteps jostle them, and a hit scatters
-- them. A lid nobody sees keeps them in. All of it is for show.
--
-- Everything is laid out on a grid of cells, p screen pixels each; a coin is
-- 2x2 cells. The physics world works in units of 8 per cell, to keep the coins
-- a sensible size for Box2D.
local goldbag = {}

local S = 8 -- physics units per cell
local COIN_R = 1 -- coin radius, in cells
local GOLD_PER_COIN = 2
local MAX_COINS = 190
local HEAP_ROWS = 14 -- how far above the mouth the walls (and so the heap) reach

-- Half-width of the sack, row by row from the rim down: a narrow mouth over a
-- round belly
local HALF = {
  9, 9, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13, 13, 13, 13, 13, 13, 13, 12, 12, 12, 12, 11, 11, 10, 10, 8, 6, 4,
}
local ROWS = #HALF
local RIM_ROWS = 2

local BASE_G = 130 -- cells/s^2
local INERTIA = 0.22 -- coin speed (cells/s) per px/s change in the hunter's speed
local MAX_KICK = 95 -- the most one frame can throw a coin (cells/s)
local STEP_TIME = 0.16 -- footsteps while running, each jostling some coins
local world, floorBody
local coins = {}
local stepAcc = 0
local lastTime, lastVx, lastVy
local stepT = 0
local lastHurt = 0

local function build()
  world = love.physics.newWorld(0, BASE_G * S, true)
  floorBody = love.physics.newBody(world, 0, 0, "static")
  -- One chain: down the left wall (from the top of the heap), round the belly
  -- and up the right
  local left, right = {}, {}
  local topY = -HEAP_ROWS
  local lidY = -(HEAP_ROWS + 3)
  left[#left + 1] = -(HALF[1] - 1) * S
  left[#left + 1] = lidY * S
  left[#left + 1] = -(HALF[1] - 1) * S
  left[#left + 1] = topY * S
  for r = 1, ROWS - 1 do
    local x = -(HALF[r] - 1) * S
    left[#left + 1] = x
    left[#left + 1] = (r - 1) * S
    left[#left + 1] = x
    left[#left + 1] = r * S
  end
  local pts = {}
  for _, v in ipairs(left) do
    pts[#pts + 1] = v
  end
  -- Across the bottom row, then back up the right side
  for r = ROWS - 1, 1, -1 do
    local x = (HALF[r] - 1) * S
    pts[#pts + 1] = x
    pts[#pts + 1] = r * S
    pts[#pts + 1] = x
    pts[#pts + 1] = (r - 1) * S
  end
  pts[#pts + 1] = (HALF[1] - 1) * S
  pts[#pts + 1] = topY * S
  pts[#pts + 1] = (HALF[1] - 1) * S
  pts[#pts + 1] = lidY * S -- (and the loop closes across the top: the lid)
  -- (Box2D refuses edges of no length: drop repeated points)
  local clean = { pts[1], pts[2] }
  for i = 3, #pts, 2 do
    if pts[i] ~= clean[#clean - 1] or pts[i + 1] ~= clean[#clean] then
      clean[#clean + 1] = pts[i]
      clean[#clean + 1] = pts[i + 1]
    end
  end
  local shape = love.physics.newChainShape(true, clean)
  local fixture = love.physics.newFixture(floorBody, shape)
  fixture:setFriction(0.3)
  fixture:setRestitution(0.3)
end

local function addCoin()
  local body = love.physics.newBody(world, (love.math.random() - 0.5) * 8 * S, (-HEAP_ROWS - 1) * S, "dynamic")
  body:setLinearDamping(0.12)
  body:setAngularDamping(0.5)
  local fixture = love.physics.newFixture(body, love.physics.newCircleShape(COIN_R * S), 1)
  fixture:setFriction(0.22)
  fixture:setRestitution(0.38)
  body:setLinearVelocity(0, 40 * S * love.math.random())
  coins[#coins + 1] = { body = body, tone = love.math.random() }
end

local function removeTopmost()
  local best, bi = math.huge, nil
  for i, c in ipairs(coins) do
    local y = c.body:getY()
    if y < best then
      best, bi = y, i
    end
  end
  if bi then
    coins[bi].body:destroy()
    table.remove(coins, bi)
  end
end

local PALETTE = {
  edge = { 0.30, 0.17, 0.08 },
  edgeLight = { 0.66, 0.43, 0.21 },
  rim = { 0.58, 0.38, 0.19 },
  rimDark = { 0.40, 0.25, 0.12 },
  fill = { 0.55, 0.36, 0.18 },
  stitch = { 0.85, 0.68, 0.42 },
}

-- Adds (vx, vy) cells/s to a coin's speed, each coin a little differently
local function kick(c, vx, vy, spread)
  local j = 1 + (love.math.random() - 0.5) * spread
  local cvx, cvy = c.body:getLinearVelocity()
  c.body:setLinearVelocity(cvx + vx * j * S, cvy + vy * j * S)
  c.body:setAwake(true)
end

-- Draws the sack with its top edge at topY, right edge at rightX, p pixels per
-- cell. Returns the sack's left edge, right edge and bottom, in pixels.
function goldbag.draw(gold, player, rightX, topY, p)
  local now = love.timer.getTime()
  local dt = lastTime and math.min(0.05, now - lastTime) or 0
  lastTime = now
  if not world then
    build()
  end

  -- Inertia: the sack moves with the hunter, the coins lag behind, so each
  -- change in his speed throws them the opposite way
  local b = player and player.body
  if b and dt > 0 then
    if lastVx then
      local dvx, dvy = b.vx - lastVx, b.vy - lastVy
      local kx = math.max(-MAX_KICK, math.min(MAX_KICK, -dvx * INERTIA))
      local ky = math.max(-MAX_KICK, math.min(MAX_KICK, -dvy * INERTIA))
      if math.abs(kx) + math.abs(ky) > 1.5 then
        for _, c in ipairs(coins) do
          kick(c, kx, ky, 0.5)
        end
      end
    end
    lastVx, lastVy = b.vx, b.vy
    -- Footsteps while running jostle a few coins up
    if player.grounded and math.abs(b.vx) > 30 then
      stepT = stepT - dt
      if stepT <= 0 then
        stepT = STEP_TIME
        for _, c in ipairs(coins) do
          if love.math.random() < 0.3 then
            kick(c, (love.math.random() - 0.5) * 16, -(10 + love.math.random() * 22), 0)
          end
        end
      end
    end
    -- A hit scatters them
    local hurt = player.hurtFlash or 0
    if hurt > lastHurt + 0.5 then
      for _, c in ipairs(coins) do
        local ang = love.math.random() * math.pi * 2
        local sp = 30 + love.math.random() * 50
        kick(c, math.cos(ang) * sp, math.sin(ang) * sp - 25, 0)
      end
    end
    lastHurt = hurt
  end

  -- One coin per GOLD_PER_COIN gold: new ones drop in, spent ones go
  local target = math.min(MAX_COINS, math.floor(gold / GOLD_PER_COIN))
  if #coins < target then
    for _ = 1, math.min(3, target - #coins) do
      addCoin()
    end
  elseif #coins > target then
    for _ = 1, math.min(4, #coins - target) do
      removeTopmost()
    end
  end
  stepAcc = stepAcc + dt
  while stepAcc >= 1 / 60 do
    stepAcc = stepAcc - 1 / 60
    world:update(1 / 60, 8, 3)
  end
  for i = #coins, 1, -1 do
    local c = coins[i]
    local x, y = c.body:getPosition()
    if y > (ROWS + 4) * S or math.abs(x) > 20 * S then
      c.body:destroy() -- escaped: it will be replaced
      table.remove(coins, i)
    end
  end

  local width = (2 * 13 + 1) * p
  local cx = rightX - width / 2
  local function px(cellX, cellY, w, h)
    love.graphics.rectangle("fill", math.floor(cx + cellX * p), math.floor(topY + cellY * p), (w or 1) * p, (h or 1) * p)
  end

  -- The see-through belly
  love.graphics.setColor(PALETTE.fill[1], PALETTE.fill[2], PALETTE.fill[3], 0.26)
  for r = 1, ROWS do
    px(-HALF[r], r - 1, 2 * HALF[r] + 1, 1)
  end

  -- The coins, two-by-two pixels each in two golds, with a bright corner and a dark one
  for _, c in ipairs(coins) do
    local x, y = c.body:getPosition()
    local cellX, cellY = x / S - COIN_R, y / S - COIN_R
    local base = c.tone < 0.5 and { 0.97, 0.76, 0.22 } or { 0.90, 0.68, 0.18 }
    local sx, sy = math.floor(cx + cellX * p + 0.5), math.floor(topY + cellY * p + 0.5)
    love.graphics.setColor(base[1], base[2], base[3])
    love.graphics.rectangle("fill", sx, sy, 2 * p, 2 * p)
    love.graphics.setColor(1, 0.95, 0.6)
    love.graphics.rectangle("fill", sx, sy, p, p)
    love.graphics.setColor(0.62, 0.40, 0.09)
    love.graphics.rectangle("fill", sx + p, sy + p, p, p)
  end

  -- The edges, opaque: any cell of the sack next to the outside, and the rolled rim
  for r = 1, ROWS do
    for side = -1, 1, 2 do
      local from, to = HALF[r], HALF[r]
      local prev, nxt = HALF[r - 1] or 0, HALF[r + 1] or 0
      local inner = math.min(prev, nxt, HALF[r]) -- cells beyond this on the row are edge
      for x = inner, from do
        local ex = side * x
        local lit = side == -1 and r > RIM_ROWS
        love.graphics.setColor(lit and PALETTE.edgeLight[1] or PALETTE.edge[1], lit and PALETTE.edgeLight[2] or PALETTE.edge[2], lit and PALETTE.edgeLight[3] or PALETTE.edge[3])
        px(ex, r - 1)
      end
    end
  end
  -- The bottom rows
  love.graphics.setColor(PALETTE.edge[1], PALETTE.edge[2], PALETTE.edge[3])
  px(-HALF[ROWS], ROWS - 1, 2 * HALF[ROWS] + 1, 1)
  -- The rolled rim round the mouth, with a lighter lip and a shaded underside
  love.graphics.setColor(PALETTE.rim[1], PALETTE.rim[2], PALETTE.rim[3])
  px(-HALF[1] - 1, 0, 2 * HALF[1] + 3, RIM_ROWS)
  love.graphics.setColor(PALETTE.edgeLight[1], PALETTE.edgeLight[2], PALETTE.edgeLight[3])
  px(-HALF[1] - 1, 0, 2 * HALF[1] + 3, 1)
  love.graphics.setColor(PALETTE.rimDark[1], PALETTE.rimDark[2], PALETTE.rimDark[3])
  px(-HALF[1] - 1, RIM_ROWS, 2 * HALF[1] + 3, 1)
  -- Stitches down the side, and a patch
  love.graphics.setColor(PALETTE.stitch[1], PALETTE.stitch[2], PALETTE.stitch[3], 0.9)
  for r = 6, ROWS - 6, 3 do
    px(HALF[r] - 2, r - 1, 1, 1)
  end
  love.graphics.setColor(PALETTE.edgeLight[1], PALETTE.edgeLight[2], PALETTE.edgeLight[3], 0.9)
  px(-HALF[16] + 3, 14, 4, 4)
  love.graphics.setColor(PALETTE.edge[1], PALETTE.edge[2], PALETTE.edge[3])
  px(-HALF[16] + 3, 14, 4, 1)
  px(-HALF[16] + 3, 17, 4, 1)
  px(-HALF[16] + 3, 14, 1, 4)
  px(-HALF[16] + 6, 14, 1, 4)

  love.graphics.setColor(1, 1, 1)
  return cx - width / 2, cx + width / 2, topY + ROWS * p
end

return goldbag
