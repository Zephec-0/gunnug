-- The gold readout: a pile of coins that grows with the run's gold, one coin for every GOLD_PER_COIN gold.
-- The coins make up to MAX_COLUMNS stacks, shared out evenly (the second stack starts once the first is
-- COLUMN_COINS high). A coin added falls onto the top of its stack; spent ones are simply gone. Any gold short
-- of a whole coin is one coin lying at the foot of the pile. Everything is laid out on a grid of cells, c
-- screen pixels each.
local coinstack = {}

local GOLD_PER_COIN = 20
local COLUMN_COINS = 10
local MAX_COLUMNS = 3
local COIN_W, PITCH = 6, 2 -- a coin's width and the height of each in the stack, in cells
local COLUMN_STEP = 4 -- (the stacks overlap, each one set back and up a little from the last) -- how far across the next stack starts, in cells
local FALL_TIME, ADD_EVERY = 0.2, 0.05

local GOLD, GOLD_L, GOLD_D = { 0.95, 0.74, 0.22 }, { 1.0, 0.94, 0.62 }, { 0.62, 0.40, 0.09 }
local GOLD2 = { 0.88, 0.64, 0.16 }

local shown, lastAdd = 0, 0
local fallStart, fallIndex

-- A thin coin, 2 cells tall: a bright top edge over the body (the dark underside of the one below shows
-- between them), with a darker end on its right
local function coin(x, y, c, k, alpha)
  local body = k % 2 == 0 and GOLD or GOLD2
  alpha = alpha or 1
  love.graphics.setColor(GOLD_L[1], GOLD_L[2], GOLD_L[3], alpha)
  love.graphics.rectangle("fill", x + c, y, (COIN_W - 2) * c, c)
  love.graphics.setColor(body[1], body[2], body[3], alpha)
  love.graphics.rectangle("fill", x, y + c, (COIN_W - 1) * c, c)
  love.graphics.setColor(GOLD_D[1], GOLD_D[2], GOLD_D[3], alpha)
  love.graphics.rectangle("fill", x + (COIN_W - 1) * c, y + c, c, c)
end

local function capacity()
  return COLUMN_COINS * MAX_COLUMNS
end

-- Draws the pile with its bottom-right corner at (rightX, y), c pixels to a cell. Returns the pile's width
-- and height in pixels.
function coinstack.draw(gold, rightX, y, c)
  local now = love.timer.getTime()
  local target = math.min(capacity(), math.floor(gold / GOLD_PER_COIN))
  if target < shown then
    shown = target
    fallIndex = nil
  elseif target > shown and now - lastAdd >= ADD_EVERY then
    shown = shown + 1
    lastAdd = now
    fallStart = now
    fallIndex = shown
  end

  -- The stacks and their heights: shown coins shared out as evenly as they go
  local cols = math.max(1, math.min(MAX_COLUMNS, math.ceil(shown / COLUMN_COINS)))
  local odd = gold % GOLD_PER_COIN > 0 and gold < GOLD_PER_COIN * capacity()
  local width = ((cols - 1) * COLUMN_STEP + COIN_W + 1 + (odd and COIN_W or 0)) * c
  local x = rightX - width
  local height = (COLUMN_COINS * PITCH + 3 + (cols - 1) * 2) * c
  -- The most recent coin lands on the stack that took it
  local fallCol = fallIndex and (fallIndex - 1) % cols or nil
  for col = cols - 1, 0, -1 do
    local h = math.floor(shown / cols) + (col < shown % cols and 1 or 0)
    for row = 0, h - 1 do
      local cx = x + (col * COLUMN_STEP + 1) * c
      local cy = y - ((row + 1) * PITCH + 1 + col * 2) * c
      local k = row * cols + col + 1
      if fallCol == col and row == h - 1 then
        local t = (now - fallStart) / FALL_TIME
        if t >= 1 then
          fallIndex = nil
        else
          cy = cy - (1 - t * t) * 12 * c
          coin(math.floor(cx), math.floor(cy), c, k, math.min(1, t * 3))
          cx = nil
        end
      end
      if cx then
        coin(math.floor(cx), math.floor(cy), c, k)
      end
    end
  end
  -- The odd gold under a whole coin: one lying at the pile's foot
  if odd then
    local part = (gold % GOLD_PER_COIN) / GOLD_PER_COIN
    coin(math.floor(rightX - COIN_W * c), math.floor(y - 2 * c), c, 1, 0.45 + 0.55 * part)
  end
  love.graphics.setColor(1, 1, 1)
  return width, height
end

return coinstack
