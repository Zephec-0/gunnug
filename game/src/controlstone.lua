-- The controls, carved into a standing stone by the hunter's camp (the way Noita teaches its keys in stone).
-- Lettered with the same tiny 3x5 pixel font as the signs (src.story). The keys are read from src.input, so a
-- rebound key changes the carving the next time it is drawn. Pure scenery: nothing here is solid.
local input = require("src.input")
local story = require("src.story")

local controlstone = {}

local FONT = story.FONT
local ROW = 7 -- pixels per line of lettering (5 tall and 2 between)
local PAD_X, PAD_TOP, PLINTH = 5, 7, 5

-- What the stone says: a label, then either the actions whose keys follow or a fixed text (the mouse isn't rebindable)
local LINES = {
  { "MOVE", { "left", "right" } },
  { "JUMP", { "jump" } },
  { "ROLL", { "roll" } },
  { "KICK", { "kick" } },
  { "USE", { "interact" } },
  { "FIRE", "LMB" },
  { "RELOAD", "RMB" },
}
local LABEL_CHARS = 7 -- (label column: the longest label, RELOAD, and a gap)

local SHORT = {
  ["L Shift"] = "SHIFT", ["R Shift"] = "SHIFT", ["L Ctrl"] = "CTRL", ["R Ctrl"] = "CTRL",
  ["Space"] = "SPACE", ["Left"] = "LEFT", ["Right"] = "RIGHT", ["Up"] = "UP", ["Down"] = "DOWN",
  ["Enter"] = "ENTER", ["Num Enter"] = "ENTER", ["Caps Lock"] = "CAPS", ["Backspace"] = "BKSP",
  ["L Alt"] = "ALT", ["R Alt"] = "ALT",
}

local function keyText(id)
  local keys = input.keys(id)
  local name = input.keyName(keys[1] or keys[2])
  return SHORT[name] or name:upper()
end

-- The text of each line, from the keys as they are bound now
local function texts()
  local out = {}
  for i, line in ipairs(LINES) do
    local right
    if type(line[2]) == "string" then
      right = line[2]
    else
      local parts = {}
      for _, id in ipairs(line[2]) do
        parts[#parts + 1] = keyText(id)
      end
      right = table.concat(parts, " ")
    end
    out[i] = line[1] .. string.rep(" ", LABEL_CHARS - #line[1]) .. right
  end
  return out
end

local function hash(x, k)
  local n = math.sin(x * 12.9898 + k * 78.233) * 43758.5453
  return n - math.floor(n)
end

-- The stone: a slab with a chipped top and a lettered face, the letters cut in (dark) with a lit lip below
local STONE = { 0.58, 0.51, 0.42 }
local STONE_D = { 0.36, 0.31, 0.26 }
local CUT = { 0.20, 0.16, 0.13 }
local LIP = { 0.74, 0.67, 0.55 }

local function build(lines)
  local chars = 0
  for _, t in ipairs(lines) do
    chars = math.max(chars, #t)
  end
  local w = chars * 4 - 1 + PAD_X * 2
  local h = PAD_TOP + #lines * ROW + PLINTH
  local data = love.image.newImageData(w, h)
  -- The outline: the top is chipped and its corners are knocked off
  local top = {}
  for x = 0, w - 1 do
    local t = 1 + math.floor(hash(x, 3) * 3)
    t = t + math.max(0, 3 - x) + math.max(0, x - (w - 4))
    if x > w * 0.62 and x < w * 0.82 then
      t = t + 2 -- (a bite out of the top)
    end
    top[x] = t
  end
  local cut = {}
  for i, text in ipairs(lines) do
    for c = 1, #text do
      local g = FONT[text:sub(c, c)]
      if g then
        for k = 0, 14 do
          if g:sub(k + 1, k + 1) == "1" then
            cut[(PAD_TOP + (i - 1) * ROW + math.floor(k / 3)) * w + PAD_X + (c - 1) * 4 + k % 3] = true
          end
        end
      end
    end
  end
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      if y >= top[x] then
        local edge = (x == 0 or x == w - 1 or y == top[x] or y == h - 1)
        local shade = (hash(x, y) - 0.5) * 0.07 - (x / w) * 0.09
        if y > top[x] + 1 and hash(x * 0.3, y * 0.3 + 9) < 0.12 then
          shade = shade - 0.06 -- (weathering)
        end
        local r, g, b = STONE[1] + shade, STONE[2] + shade, STONE[3] + shade
        if edge then
          r, g, b = STONE_D[1], STONE_D[2], STONE_D[3]
        elseif cut[y * w + x] then
          r, g, b = CUT[1], CUT[2], CUT[3]
        elseif cut[(y - 1) * w + x - 1] then
          r, g, b = LIP[1] + shade, LIP[2] + shade, LIP[3] + shade -- (the lit lip under and beside each cut)
        end
        data:setPixel(x, y, r, g, b, 1)
      else
        data:setPixel(x, y, 0, 0, 0, 0)
      end
    end
  end
  local img = love.graphics.newImage(data)
  img:setFilter("nearest", "nearest")
  return img, w, h
end

local cache = { key = nil }

-- Draws the stone standing on the ground at (x, ground), its middle over x
function controlstone.draw(x, ground)
  local lines = texts()
  local key = table.concat(lines, "|")
  if cache.key ~= key then
    cache.img, cache.w, cache.h = build(lines)
    cache.key = key
  end
  local w, h = cache.w, cache.h
  local x0, y0 = math.floor(x - w / 2), ground - h + 2 -- (sunk two pixels into the sand)
  -- A drift of sand banked against the foot
  love.graphics.setColor(0.70, 0.60, 0.42)
  love.graphics.rectangle("fill", x0 - 3, ground - 2, w + 6, 2)
  love.graphics.setColor(0.78, 0.68, 0.48)
  love.graphics.rectangle("fill", x0 - 1, ground - 3, w + 2, 1)
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(cache.img, x0, y0)
  return x0, x0 + w
end

-- How wide the stone is now (for culling)
function controlstone.halfWidth()
  return (cache.w or 64) / 2 + 4
end

return controlstone
