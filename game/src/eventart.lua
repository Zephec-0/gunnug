-- Pixel art for the random events, drawn on the game's own pixel grid (never scaled by anything but a
-- whole number of game pixels, and baked once into images):
--   the slot machine's reel strip (seven by seven symbols), the playing cards (faces, backs and the
--   four face cards: the Jack a golemling, the Queen the Sulfur Queen, the King the Biggest Fish and
--   the Ace the Crow Rider), the card table's felt, and the little icons the shrine's cards carry.
local eventart = {}

local floor, sin, cos, sqrt, abs, min, max = math.floor, math.sin, math.cos, math.sqrt, math.abs, math.min, math.max

-- A painter ------------------------------------------------------------------------------------

local Painter = {}
Painter.__index = Painter

local function newPainter(w, h)
  return setmetatable({ w = w, h = h, px = {} }, Painter)
end

function Painter:put(x, y, c)
  x, y = floor(x), floor(y)
  if x >= 0 and y >= 0 and x < self.w and y < self.h then
    self.px[y * self.w + x] = c
  end
end

function Painter:get(x, y)
  return self.px[floor(y) * self.w + floor(x)]
end

function Painter:rect(x, y, w, h, c)
  for yy = y, y + h - 1 do
    for xx = x, x + w - 1 do
      self:put(xx, yy, c)
    end
  end
end

-- A filled disc / ellipse whose pixel centres lie inside it; colour may be a function(x, y) -> colour
function Painter:disc(cx, cy, rx, ry, c)
  ry = ry or rx
  for y = floor(cy - ry), math.ceil(cy + ry) do
    for x = floor(cx - rx), math.ceil(cx + rx) do
      local dx, dy = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
      if dx * dx + dy * dy <= 1 then
        self:put(x, y, type(c) == "function" and c(x, y, dx, dy) or c)
      end
    end
  end
end

function Painter:line(x0, y0, x1, y1, c)
  x0, y0, x1, y1 = floor(x0), floor(y0), floor(x1), floor(y1)
  local dx, dy = abs(x1 - x0), -abs(y1 - y0)
  local sx, sy = x0 < x1 and 1 or -1, y0 < y1 and 1 or -1
  local err = dx + dy
  while true do
    self:put(x0, y0, c)
    if x0 == x1 and y0 == y1 then
      break
    end
    local e2 = 2 * err
    if e2 >= dy then
      err = err + dy
      x0 = x0 + sx
    end
    if e2 <= dx then
      err = err + dx
      y0 = y0 + sy
    end
  end
end

-- A convex polygon, filled
function Painter:poly(pts, c)
  local y0, y1 = math.huge, -math.huge
  for i = 1, #pts, 2 do
    y0, y1 = min(y0, pts[i + 1]), max(y1, pts[i + 1])
  end
  for y = floor(y0), math.ceil(y1) do
    local yy = y + 0.5
    local xa, xb = math.huge, -math.huge
    local n = #pts / 2
    for i = 1, n do
      local ax, ay = pts[i * 2 - 1], pts[i * 2]
      local j = i % n + 1
      local bx, by = pts[j * 2 - 1], pts[j * 2]
      if (ay <= yy and by > yy) or (by <= yy and ay > yy) then
        local x = ax + (yy - ay) / (by - ay) * (bx - ax)
        xa, xb = min(xa, x), max(xb, x)
      end
    end
    if xa <= xb then
      for x = floor(xa + 0.5), floor(xb - 0.5) do
        self:put(x, y, type(c) == "function" and c(x, y) or c)
      end
    end
  end
end

-- Rows of characters through a palette (' ' and '.' are empty), placed at (x, y)
function Painter:rows(x, y, rows, pal)
  for j, row in ipairs(rows) do
    for i = 1, #row do
      local ch = row:sub(i, i)
      local c = pal[ch]
      if c then
        self:put(x + i - 1, y + j - 1, c)
      end
    end
  end
end

-- Everything that is empty and beside something painted gets the outline colour
function Painter:outline(c)
  local add = {}
  for y = 0, self.h - 1 do
    for x = 0, self.w - 1 do
      if not self.px[y * self.w + x] then
        if self:get(x - 1, y) and x > 0 or self:get(x + 1, y) and x < self.w - 1 or self:get(x, y - 1) and y > 0 or self:get(x, y + 1) and y < self.h - 1 then
          add[#add + 1] = y * self.w + x
        end
      end
    end
  end
  for _, i in ipairs(add) do
    self.px[i] = c
  end
end

function Painter:image()
  local data = love.image.newImageData(self.w, self.h)
  for y = 0, self.h - 1 do
    for x = 0, self.w - 1 do
      local c = self.px[y * self.w + x]
      if c then
        data:setPixel(x, y, c[1], c[2], c[3], c[4] or 1)
      end
    end
  end
  local img = love.graphics.newImage(data)
  img:setFilter("nearest", "nearest")
  return img, data
end

local function shade(c, k)
  return { min(1, c[1] * k), min(1, c[2] * k), min(1, c[3] * k), c[4] }
end

local function hash(x, y, s)
  local n = sin(x * 127.1 + y * 311.7 + (s or 0) * 74.7) * 43758.5453
  return n - floor(n)
end

-- The slot machine's reels -----------------------------------------------------------------------

local SYM_PAL = {
  r = { 0.92, 0.16, 0.20 }, R = { 0.55, 0.06, 0.12 }, g = { 0.32, 0.72, 0.32 }, w = { 1, 1, 0.92 },
  y = { 0.96, 0.90, 0.26 }, Y = { 0.72, 0.62, 0.12 },
  o = { 0.96, 0.76, 0.26 }, O = { 0.66, 0.46, 0.10 }, k = { 0.32, 0.20, 0.10 },
  s = { 0.62, 0.84, 1.0 }, S = { 0.28, 0.48, 0.78 },
  q = { 1.0, 0.42, 0.20 }, Q = { 0.70, 0.20, 0.10 },
  d = { 0.58, 1.0, 0.96 }, D = { 0.20, 0.62, 0.62 },
}

-- The symbols, in the order of randevents' SYMBOLS: Cherry, Lemon, Bell, Star, Seven, Diamond
local SYMBOLS = {
  { "...gg..", "..g..g.", ".g....g", "rr...rr", "rwR.rwR", "rRR.rRR", ".RR..RR" },
  { ".......", "..yyy..", ".ywyyY.", "yyyyyyY", ".yyyYY.", "..YYY..", "......." },
  { "...o...", "..ooo..", ".owooO.", ".owooO.", ".ooooO.", "ooooooO", "..OkO.." },
  { "...s...", "...s...", "sssssss", ".ssws S", "..sss..", ".ss.ss.", ".s...s." },
  { "qqqqqqq", "QQQQqQQ", "....qQ.", "...qQ..", "..qQ...", "..qQ...", "..qQ..." },
  { "...d...", "..dwd..", ".dwddD.", "ddddddD", ".dddDD.", "..dDD..", "...D..." },
}
eventart.SYMBOL_W, eventart.SYMBOL_H, eventart.SYMBOL_STEP = 7, 7, 8

local strip
-- A tall picture of every symbol one above the next (a pixel of space between), for scrolling past a window
function eventart.reelStrip()
  if not strip then
    local p = newPainter(7, #SYMBOLS * 8)
    for i, rows in ipairs(SYMBOLS) do
      local fixed = {}
      for j, r in ipairs(rows) do
        fixed[j] = r:gsub(" ", ".")
      end
      p:rows(0, (i - 1) * 8, fixed, SYM_PAL)
    end
    strip = p:image()
    strip:setWrap("clamp", "repeat")
  end
  return strip
end

-- One symbol on its own (a picture of 7 x 7)
local singles = {}
function eventart.symbol(i)
  if not singles[i] then
    local p = newPainter(7, 7)
    local fixed = {}
    for j, r in ipairs(SYMBOLS[i]) do
      fixed[j] = r:gsub(" ", ".")
    end
    p:rows(0, 0, fixed, SYM_PAL)
    singles[i] = p:image()
  end
  return singles[i]
end

-- Playing cards ----------------------------------------------------------------------------------

eventart.CARD_W, eventart.CARD_H = 54, 68
local CW, CH = 54, 68

local FONT5 = {
  ["0"] = { "01110", "10001", "10011", "10101", "11001", "10001", "01110" },
  ["1"] = { "00100", "01100", "00100", "00100", "00100", "00100", "01110" },
  ["2"] = { "01110", "10001", "00001", "00010", "00100", "01000", "11111" },
  ["3"] = { "11110", "00001", "00001", "01110", "00001", "00001", "11110" },
  ["4"] = { "00010", "00110", "01010", "10010", "11111", "00010", "00010" },
  ["5"] = { "11111", "10000", "11110", "00001", "00001", "10001", "01110" },
  ["6"] = { "00110", "01000", "10000", "11110", "10001", "10001", "01110" },
  ["7"] = { "11111", "00001", "00010", "00100", "01000", "01000", "01000" },
  ["8"] = { "01110", "10001", "10001", "01110", "10001", "10001", "01110" },
  ["9"] = { "01110", "10001", "10001", "01111", "00001", "00010", "01100" },
}
local FONT3 = {
  ["0"] = { "111", "101", "101", "101", "111" }, ["1"] = { "010", "110", "010", "010", "111" },
  ["2"] = { "111", "001", "111", "100", "111" }, ["3"] = { "111", "001", "111", "001", "111" },
  ["4"] = { "101", "101", "111", "001", "001" }, ["5"] = { "111", "100", "111", "001", "111" },
  ["6"] = { "111", "100", "111", "101", "111" }, ["7"] = { "111", "001", "010", "010", "010" },
  ["8"] = { "111", "101", "111", "101", "111" }, ["9"] = { "111", "101", "111", "001", "111" },
  A = { "010", "101", "111", "101", "101" }, J = { "001", "001", "001", "101", "010" },
  Q = { "010", "101", "101", "111", "011" }, K = { "101", "101", "110", "101", "101" },
}
local PIPS = {
  [0] = { "00100", "01110", "11111", "11111", "00100" }, -- spade
  [1] = { "01010", "11111", "11111", "01110", "00100" }, -- heart
  [2] = { "01110", "01110", "10101", "11111", "00100" }, -- club
  [3] = { "00100", "01110", "11111", "01110", "00100" }, -- diamond
}
local RED, BLACK = { 0.78, 0.10, 0.14 }, { 0.12, 0.11, 0.16 }
local function suitColor(suit)
  return (suit == 1 or suit == 3) and RED or BLACK
end

eventart.RANKS = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K" }

local function bitmap(p, x, y, rows, c, scale, flipped)
  scale = scale or 1
  local h, w = #rows, #rows[1]
  for j = 1, h do
    for i = 1, w do
      if rows[j]:sub(i, i) == "1" then
        local ix, iy = i - 1, j - 1
        if flipped then
          ix, iy = w - 1 - ix, h - 1 - iy
        end
        p:rect(x + ix * scale, y + iy * scale, scale, scale, c)
      end
    end
  end
end

local function rankRows(rank, font)
  local label = eventart.RANKS[rank]
  local out = {}
  for ch in label:gmatch(".") do
    out[#out + 1] = font[ch]
  end
  local rows = {}
  for j = 1, #out[1] do
    local r = {}
    for k, glyph in ipairs(out) do
      r[#r + 1] = glyph[j]
    end
    rows[j] = table.concat(r, "0")
  end
  return rows
end

local CARD = {
  edge = { 0.10, 0.08, 0.11 }, body = { 0.94, 0.91, 0.82 }, hi = { 1.0, 0.99, 0.94 },
  lo = { 0.78, 0.73, 0.62 }, frame = { 0.72, 0.64, 0.50 },
}

-- The blank card: a cream face with well rounded corners, lit from the upper left
local CORNER = 4.5
local function insideCard(x, y)
  local r = CORNER
  local dx = x < r and r - x - 0.5 or (x > CW - 1 - r and x + 0.5 - (CW - r) or 0)
  local dy = y < r and r - y - 0.5 or (y > CH - 1 - r and y + 0.5 - (CH - r) or 0)
  return dx * dx + dy * dy <= r * r
end

local function cardBase(p)
  for y = 0, CH - 1 do
    for x = 0, CW - 1 do
      if insideCard(x, y) then
        local c = CARD.body
        if not (insideCard(x - 1, y) and insideCard(x + 1, y) and insideCard(x, y - 1) and insideCard(x, y + 1)) then
          c = CARD.edge
        elseif not (insideCard(x - 1, y) and insideCard(x, y - 1) and insideCard(x - 1, y - 1)) or not insideCard(x - 2, y) and x > 1 or not insideCard(x, y - 2) and y > 1 then
          c = CARD.hi
        elseif not (insideCard(x + 1, y) and insideCard(x, y + 1)) or not insideCard(x + 2, y) and x < CW - 2 or not insideCard(x, y + 2) and y < CH - 2 then
          c = CARD.lo
        end
        p:put(x, y, c)
      end
    end
  end
end

-- Years of use: the paper has yellowed and gone blotchy (most at the edges), speckled with foxing; the
-- corners are rubbed and chipped, the outline worn through in places, and a fold runs across it with a
-- few scuffs. Applied over everything painted, the pictures too (a little less).
local function vnoise(x, y, seed)
  local ix, iy = floor(x), floor(y)
  local fx, fy = x - ix, y - iy
  fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
  local a, b = hash(ix, iy, seed), hash(ix + 1, iy, seed)
  local c, d = hash(ix, iy + 1, seed), hash(ix + 1, iy + 1, seed)
  return (a + (b - a) * fx) + ((c + (d - c) * fx) - (a + (b - a) * fx)) * fy
end

local function weather(p, seed)
  local TAN = { 0.66, 0.52, 0.30 }
  for y = 0, CH - 1 do
    for x = 0, CW - 1 do
      local c = p:get(x, y)
      if c then
        local edge = min(x, y, CW - 1 - x, CH - 1 - y)
        local paper = (c[1] + c[2] + c[3]) / 3 > 0.72
        local blot = max(0, vnoise(x / 6, y / 6, seed) - 0.52) * 1.6
        local grime = (max(0, 1 - edge / 10) * 0.55 + blot) * (paper and 1 or 0.35)
        local k = min(0.75, grime) * 0.6
        local g = (hash(x, y, seed + 7) - 0.5) * (paper and 0.07 or 0.03)
        p:put(x, y, {
          max(0, min(1, c[1] * (1 - k * 0.22) + (TAN[1] - c[1] * 0.5) * k * 0.5 + g)),
          max(0, min(1, c[2] * (1 - k * 0.28) + (TAN[2] - c[2] * 0.5) * k * 0.5 + g)),
          max(0, min(1, c[3] * (1 - k * 0.38) + (TAN[3] - c[3] * 0.5) * k * 0.5 + g)),
        })
      end
    end
  end
  -- foxing: brown speckles
  for i = 1, 16 do
    local x, y = floor(hash(i, 1, seed) * CW), floor(hash(i, 2, seed) * CH)
    local c = p:get(x, y)
    if c and (c[1] + c[2] + c[3]) / 3 > 0.62 then
      local a = 0.35 + hash(i, 3, seed) * 0.4
      p:put(x, y, { c[1] * (1 - a) + 0.52 * a, c[2] * (1 - a) + 0.38 * a, c[3] * (1 - a) + 0.22 * a })
    end
  end
  -- a fold: a pale line with a dark one beside it, slightly slanted, broken here and there
  local fx0, slant = 10 + hash(1, 9, seed) * (CW - 20), (hash(2, 9, seed) - 0.5) * 0.35
  local vertical = hash(3, 9, seed) < 0.5
  for t = 0, (vertical and CH or CW) - 1 do
    if hash(t, 5, seed) > 0.22 then
      local x, y
      if vertical then
        x, y = floor(fx0 + t * slant), t
      else
        x, y = t, floor(10 + hash(1, 9, seed) * (CH - 20) + t * slant)
      end
      local c = p:get(x, y)
      if c then
        p:put(x, y, { min(1, c[1] * 1.10 + 0.03), min(1, c[2] * 1.10 + 0.03), min(1, c[3] * 1.08 + 0.02) })
      end
      local x2, y2 = vertical and x + 1 or x, vertical and y or y + 1
      local c2 = p:get(x2, y2)
      if c2 then
        p:put(x2, y2, { c2[1] * 0.86, c2[2] * 0.84, c2[3] * 0.80 })
      end
    end
  end
  -- scuffs: short pale scratches
  for i = 1, 4 do
    local x, y = floor(hash(i, 11, seed) * (CW - 8)) + 2, floor(hash(i, 12, seed) * (CH - 8)) + 2
    local dx, dy = hash(i, 13, seed) < 0.5 and 1 or 0, 1
    for k = 0, 2 + floor(hash(i, 14, seed) * 3) do
      local c = p:get(x + dx * k, y + dy * k)
      if c then
        p:put(x + dx * k, y + dy * k, { min(1, c[1] + 0.18), min(1, c[2] + 0.17), min(1, c[3] + 0.14) })
      end
    end
  end
  -- the outline is worn through in places, and the corners are rubbed pale or chipped away
  for y = 0, CH - 1 do
    for x = 0, CW - 1 do
      local c = p:get(x, y)
      if c and (c[1] + c[2] + c[3]) / 3 < 0.2 and min(x, y, CW - 1 - x, CH - 1 - y) == 0 and hash(x, y, seed + 3) < 0.07 then
        p:put(x, y, { 0.64, 0.56, 0.42 })
      end
    end
  end
  for _, corner in ipairs({ { 0, 0, 1, 1 }, { CW - 1, 0, -1, 1 }, { 0, CH - 1, 1, -1 }, { CW - 1, CH - 1, -1, -1 } }) do
    local rub = hash(corner[1], corner[2], seed + 5)
    for dy = 0, 4 do
      for dx = 0, 4 do
        local x, y = corner[1] + corner[3] * dx, corner[2] + corner[4] * dy
        local c = p:get(x, y)
        if c and hash(x, y, seed + 9) < 0.45 * rub * (1 - (dx + dy) / 8) then
          p:put(x, y, { 0.76, 0.68, 0.52 })
        end
      end
    end
    if rub > 0.7 then
      -- (a chip out of the corner)
      p.px[corner[2] * CW + corner[1]] = nil
      p.px[(corner[2] + corner[4]) * CW + corner[1]] = nil
    end
  end
end

-- The corner marks: rank over suit at the upper left, turned over at the lower right
local function corners(p, rank, suit)
  local c = suitColor(suit)
  local rows = rankRows(rank, FONT3)
  local rw = #rows[1]
  bitmap(p, 4, 4, rows, c)
  bitmap(p, 4 + floor((rw - 5) / 2), 11, PIPS[suit], c)
  bitmap(p, CW - 4 - rw, CH - 9, rows, c, 1, true)
  bitmap(p, CW - 9 - floor((rw - 5) / 2), CH - 16, PIPS[suit], c, 1, true)
end

-- The face cards' pictures: 36 x 44, painted at (x, y) of the card
local FACE_W, FACE_H = 34, 42

local function frameFace(p, x0, y0, bg)
  p:rect(x0 - 1, y0 - 1, FACE_W + 2, FACE_H + 2, CARD.frame)
  for y = 0, FACE_H - 1 do
    for x = 0, FACE_W - 1 do
      -- (a vignette: darker toward the corners)
      local dx, dy = (x - FACE_W / 2) / (FACE_W / 2), (y - FACE_H / 2) / (FACE_H / 2)
      local k = 1.12 - 0.45 * (dx * dx + dy * dy)
      p:put(x0 + x, y0 + y, shade(bg, k))
    end
  end
end

-- The Jack: a golemling, an orange gem on two marble legs
local function faceJack(p, x0, y0)
  frameFace(p, x0, y0, { 0.24, 0.26, 0.36 })
  local function P(x, y, c)
    p:put(x0 + x, y0 + y, c)
  end
  -- a soft glow round the gem
  p:disc(x0 + 17, y0 + 18, 13, 15, function(x, y, dx, dy)
    local base = p:get(x, y)
    local k = (1 - sqrt(dx * dx + dy * dy)) * 0.22
    return base and { min(1, base[1] + k * 1.0), min(1, base[2] + k * 0.55), min(1, base[3] + k * 0.1) } or nil
  end)
  -- legs of marble
  local M, ML, MD = { 0.84, 0.82, 0.76 }, { 0.96, 0.95, 0.9 }, { 0.55, 0.53, 0.52 }
  for s = 0, 1 do
    local lx = x0 + 9 + s * 11
    p:rect(lx, y0 + 28, 7, 10, M)
    p:rect(lx, y0 + 28, 2, 10, ML)
    p:rect(lx + 5, y0 + 28, 2, 10, MD)
    p:rect(lx - 1, y0 + 37, 9, 3, MD)
    p:rect(lx - 1, y0 + 37, 9, 1, M)
  end
  p:rect(x0 + 9, y0 + 27, 18, 2, MD)
  -- the gem body: a faceted orange diamond
  local cx, cy = x0 + 17.5, y0 + 15
  p:poly({ cx, cy - 13, cx + 10, cy - 1, cx + 7, cy + 9, cx - 7, cy + 9, cx - 10, cy - 1 }, function(x, y)
    local t = (x - (cx - 10)) / 20 + (y - (cy - 13)) / 44
    if t < 0.32 then
      return { 1.0, 0.86, 0.45 }
    elseif t < 0.55 then
      return { 1.0, 0.64, 0.20 }
    elseif t < 0.8 then
      return { 0.88, 0.42, 0.10 }
    end
    return { 0.62, 0.26, 0.08 }
  end)
  p:line(cx, cy - 13, cx, cy + 9, { 1.0, 0.78, 0.35 })
  p:line(cx - 10, cy - 1, cx + 10, cy - 1, { 0.75, 0.34, 0.08 })
  -- the slit of an eye, burning
  p:rect(floor(cx) + 2, floor(cy) - 5, 2, 7, { 0.18, 0.06, 0.04 })
  p:rect(floor(cx) + 2, floor(cy) - 4, 1, 5, { 1.0, 0.95, 0.7 })
  -- sparks
  for _, s in ipairs({ { 4, 6 }, { 29, 9 }, { 6, 22 }, { 28, 24 } }) do
    P(s[1], s[2], { 1.0, 0.78, 0.35 })
  end
end

-- The Queen: the Sulfur Queen, a crowned slime
local function faceQueen(p, x0, y0)
  frameFace(p, x0, y0, { 0.10, 0.20, 0.12 })
  local cx, cy = x0 + 17, y0 + 24
  -- drips
  for _, d in ipairs({ { -9, 12, 5 }, { -2, 14, 7 }, { 6, 13, 4 }, { 11, 11, 3 } }) do
    p:rect(cx + d[1], cy + d[2], 2, d[3], { 0.58, 0.64, 0.27 })
    p:disc(cx + d[1] + 1, cy + d[2] + d[3] + 1, 1.6, 1.6, { 0.76, 0.82, 0.40 })
  end
  -- the body, glassy at the rim and bright in the middle
  p:disc(cx, cy, 14, 13, function(x, y, dx, dy)
    local d = sqrt(dx * dx + dy * dy)
    local lit = -dx * 0.5 - dy * 0.6
    local v = 0.62 + 0.45 * (1 - d) * 0.8 + lit * 0.25
    if d > 0.88 then
      return { 0.43, 0.48, 0.20 }
    end
    return { 0.58 * v + 0.1, 0.64 * v + 0.1, 0.27 * v }
  end)
  -- the crown: three slime lobes, a circlet and a bubble
  for _, l in ipairs({ { -7, -14 }, { 0, -17 }, { 7, -14 } }) do
    p:disc(cx + l[1], cy + l[2], 3.5, 3.5, { 0.76, 0.82, 0.40 })
  end
  p:rect(cx - 10, cy - 9, 21, 2, { 0.90, 0.78, 0.30 })
  p:disc(cx, cy - 8, 2, 2, { 1.0, 0.95, 0.6 })
  -- eyes: dents holding an ember
  for s = -1, 1, 2 do
    p:disc(cx + s * 5, cy - 1, 3, 3.5, { 0.20, 0.24, 0.08 })
    p:disc(cx + s * 5, cy, 1.6, 1.8, { 1.0, 0.7, 0.2 })
    p:put(cx + s * 5, cy - 1, { 1.0, 0.95, 0.7 })
  end
  p:rect(cx - 3, cy + 7, 7, 2, { 0.16, 0.20, 0.06 })
  -- bubbles
  for _, b in ipairs({ { -9, 5, 2 }, { 8, 6, 1.5 }, { -2, 9, 1.2 }, { 10, -5, 1.2 } }) do
    p:disc(cx + b[1], cy + b[2], b[3], b[3], { 0.86, 0.92, 0.55 })
  end
end

-- The King: the Biggest Fish, a whale shark with four tusks and a lure
local function faceKing(p, x0, y0)
  frameFace(p, x0, y0, { 0.05, 0.12, 0.26 })
  local function ramp(v)
    return { 0.08 + 0.18 * v, 0.16 + 0.30 * v, 0.34 + 0.38 * v }
  end
  -- tail, body, head
  p:poly({ x0 + 2, y0 + 12, x0 + 12, y0 + 22, x0 + 12, y0 + 26, x0 + 2, y0 + 36 }, ramp(0.35))
  p:disc(x0 + 20, y0 + 25, 16, 11, function(x, y, dx, dy)
    return ramp(0.55 - dy * 0.45 - dx * 0.1)
  end)
  -- a pale belly
  p:disc(x0 + 21, y0 + 32, 12, 3.5, { 0.30, 0.42, 0.58 })
  -- the spots of a whale shark
  for i = 0, 9 do
    local sx, sy = x0 + 8 + hash(i, 1, 5) * 18, y0 + 17 + hash(i, 2, 5) * 11
    if p:get(sx, sy) then
      p:put(sx, sy, { 0.6, 0.88, 1.0 })
    end
  end
  -- the maw, open to the front, with tusks
  p:disc(x0 + 30, y0 + 25, 6, 8.5, { 0.12, 0.06, 0.20 })
  p:disc(x0 + 31, y0 + 25, 3.5, 5.5, { 0.22, 0.12, 0.34 })
  local T, TD = { 0.96, 0.92, 0.78 }, { 0.70, 0.64, 0.50 }
  for _, t in ipairs({ { 26, 17, 1 }, { 31, 16, 1 }, { 26, 33, -1 }, { 31, 34, -1 } }) do
    p:poly({ x0 + t[1], y0 + t[2], x0 + t[1] + 3, y0 + t[2], x0 + t[1] + 2, y0 + t[2] + 7 * t[3] }, T)
    p:put(x0 + t[1] + 2, y0 + t[2] + t[3] * 3, TD)
  end
  -- the eye, a fin, the lure on its stalk
  p:disc(x0 + 21, y0 + 18, 1.6, 1.6, { 0.75, 0.95, 1.0 })
  p:poly({ x0 + 14, y0 + 14, x0 + 22, y0 + 9, x0 + 20, y0 + 15 }, ramp(0.3))
  p:line(x0 + 24, y0 + 14, x0 + 27, y0 + 7, { 0.12, 0.26, 0.5 })
  p:line(x0 + 27, y0 + 7, x0 + 31, y0 + 6, { 0.12, 0.26, 0.5 })
  p:line(x0 + 31, y0 + 6, x0 + 32, y0 + 9, { 0.12, 0.26, 0.5 })
  p:disc(x0 + 32, y0 + 10, 2, 2, { 0.55, 0.9, 1.0 })
  p:put(x0 + 32, y0 + 10, { 1, 1, 1 })
  -- a few bubbles
  for _, b in ipairs({ { 5, 8 }, { 8, 5 }, { 28, 38 } }) do
    p:put(x0 + b[1], y0 + b[2], { 0.5, 0.75, 0.95 })
  end
end

-- The Ace: the Crow Rider, a hunter in black and violet on a crow with its wings thrown up
local function faceAce(p, x0, y0)
  frameFace(p, x0, y0, { 0.17, 0.10, 0.28 })
  local B, B2, SH = { 0.06, 0.04, 0.09 }, { 0.12, 0.08, 0.19 }, { 0.40, 0.24, 0.62 }
  -- the far wing, then the crow's body and tail
  p:poly({ x0 + 14, y0 + 24, x0 + 6, y0 + 8, x0 + 10, y0 + 6, x0 + 20, y0 + 22 }, B2)
  p:poly({ x0 + 3, y0 + 28, x0 + 12, y0 + 25, x0 + 14, y0 + 31, x0 + 5, y0 + 36 }, B)
  p:disc(x0 + 18, y0 + 28, 11, 6.5, function(x, y, dx, dy)
    return dy < -0.4 and B2 or B
  end)
  p:disc(x0 + 27, y0 + 24, 5, 5, B)
  p:poly({ x0 + 30, y0 + 22, x0 + 37, y0 + 25, x0 + 30, y0 + 27 }, { 0.30, 0.28, 0.34 })
  p:put(x0 + 28, y0 + 22, { 0.98, 0.4, 1.0 })
  p:put(x0 + 28, y0 + 23, { 0.98, 0.4, 1.0 })
  -- the near wing, feathers fanned up and back
  p:poly({ x0 + 18, y0 + 26, x0 + 8, y0 + 4, x0 + 22, y0 + 3, x0 + 24, y0 + 24 }, B)
  for i = 0, 4 do
    p:line(x0 + 18 + i, y0 + 25, x0 + 10 + i * 3, y0 + 4 + (i % 2), B2)
  end
  p:line(x0 + 18, y0 + 25, x0 + 21, y0 + 5, SH)
  p:line(x0 + 9, y0 + 29, x0 + 27, y0 + 28, SH)
  -- talons
  p:line(x0 + 17, y0 + 34, x0 + 17, y0 + 38, { 0.30, 0.28, 0.34 })
  p:line(x0 + 22, y0 + 34, x0 + 23, y0 + 38, { 0.30, 0.28, 0.34 })
  -- the rider: a tall hat and a long coat, a violet lining
  p:rect(x0 + 21, y0 + 12, 5, 12, { 0.08, 0.05, 0.12 })
  p:rect(x0 + 22, y0 + 15, 1, 8, { 0.72, 0.28, 1.0 })
  p:rect(x0 + 21, y0 + 10, 5, 3, { 0.80, 0.56, 0.46 })
  p:rect(x0 + 19, y0 + 9, 9, 1, { 0.06, 0.04, 0.09 })
  p:rect(x0 + 21, y0 + 4, 5, 5, { 0.06, 0.04, 0.09 })
  p:rect(x0 + 21, y0 + 8, 5, 1, { 0.58, 0.22, 0.90 })
  p:put(x0 + 24, y0 + 11, { 0.86, 0.45, 1.0 })
  -- stars behind
  for _, s in ipairs({ { 4, 4 }, { 29, 5 }, { 3, 18 }, { 31, 14 } }) do
    p:put(x0 + s[1], y0 + s[2], { 0.8, 0.6, 1.0 })
  end
end

local FACES = { [1] = faceAce, [11] = faceJack, [12] = faceQueen, [13] = faceKing }

local cards = {}
-- A card's face (rank 1..13, A low; suit 0..3) as an image of 54 x 68
function eventart.card(rank, suit)
  local key = rank * 4 + suit
  if not cards[key] then
    local p = newPainter(CW, CH)
    cardBase(p)
    local c = suitColor(suit)
    if FACES[rank] then
      FACES[rank](p, 10, 13)
      corners(p, rank, suit)
    else
      local rows = rankRows(rank, FONT5)
      local scale = 3
      local rw = #rows[1] * scale
      bitmap(p, floor((CW - rw) / 2), 18, rows, c, scale)
      bitmap(p, floor((CW - 15) / 2), 42, PIPS[suit], c, 3)
      corners(p, rank, suit)
    end
    weather(p, key * 3 + 1)
    cards[key] = p:image()
  end
  return cards[key]
end

local back
-- The back of a card: a lattice of diamonds in deep red and gold, round a medallion
function eventart.cardBack()
  if not back then
    local p = newPainter(CW, CH)
    cardBase(p)
    local x0, y0, w, h = 4, 4, CW - 8, CH - 8
    p:rect(x0, y0, w, h, { 0.50, 0.50, 0.50 })
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local a, b = (x + y) % 6, (x - y) % 6
        local c = { 0.40, 0.09, 0.16 }
        if a == 0 or b == 0 then
          c = { 0.78, 0.60, 0.22 }
        elseif a == 1 or b == 1 or a == 5 or b == 5 then
          c = { 0.30, 0.06, 0.12 }
        end
        p:put(x0 + x, y0 + y, c)
      end
    end
    -- a gold frame
    p:rect(x0, y0, w, 1, { 0.95, 0.80, 0.35 })
    p:rect(x0, y0 + h - 1, w, 1, { 0.95, 0.80, 0.35 })
    p:rect(x0, y0, 1, h, { 0.95, 0.80, 0.35 })
    p:rect(x0 + w - 1, y0, 1, h, { 0.95, 0.80, 0.35 })
    p:rect(x0 + 2, y0 + 2, w - 4, 1, { 0.20, 0.04, 0.08 })
    -- the medallion
    local cx, cy = CW / 2, CH / 2
    p:disc(cx, cy, 11, 14, { 0.95, 0.80, 0.35 })
    p:disc(cx, cy, 9, 12, { 0.25, 0.05, 0.10 })
    p:disc(cx, cy, 8, 11, { 0.50, 0.10, 0.18 })
    -- a four-pointed star
    local S = { 1.0, 0.92, 0.55 }
    p:poly({ cx, cy - 9, cx + 2, cy - 2, cx + 7, cy, cx + 2, cy + 2, cx, cy + 9, cx - 2, cy + 2, cx - 7, cy, cx - 2, cy - 2 }, S)
    p:put(cx, cy, { 1, 1, 1 })
    weather(p, 77)
    cards.back = p:image()
    back = cards.back
  end
  return back
end

-- The felt ---------------------------------------------------------------------------------------

local felt
-- A green baize table top of w x h game pixels: speckled cloth, a wooden rim, and a lamp hanging over
-- the middle (it is baked in: bright under the lamp, dark at the corners)
function eventart.felt(w, h)
  if not felt or felt.w ~= w or felt.h ~= h then
    local data = love.image.newImageData(w, h)
    local cx, cy = w * 0.42, h * 0.46
    local rim = 7
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local dx, dy = (x - cx) / (w * 0.62), (y - cy) / (h * 0.72)
        local light = max(0, 1 - sqrt(dx * dx + dy * dy))
        light = 0.28 + 0.95 * light * light
        local r, g, b
        if x < rim or y < rim or x >= w - rim or y >= h - rim then
          -- the wooden rim, with grain
          local grain = hash(floor(x / 6), y, 3) * 0.12 + (y % 5 == 0 and 0.05 or 0)
          local edge = (x == rim - 1 or y == rim - 1 or x == w - rim or y == h - rim) and 0.55 or 1
          r, g, b = (0.34 + grain) * edge, (0.20 + grain * 0.7) * edge, (0.10 + grain * 0.4) * edge
          light = 0.45 + light * 0.6
        else
          local n = hash(x, y, 1) * 0.10 + hash(floor(x / 2), floor(y / 2), 2) * 0.07
          r, g, b = 0.06 + n * 0.3, 0.30 + n, 0.17 + n * 0.5
        end
        data:setPixel(x, y, min(1, r * light), min(1, g * light), min(1, b * light), 1)
      end
    end
    local img = love.graphics.newImage(data)
    img:setFilter("nearest", "nearest")
    felt = { img = img, w = w, h = h }
  end
  return felt.img
end

-- Icons ------------------------------------------------------------------------------------------

local ICONS = {}
-- Little pictures for the shrine's cards (24 x 24): "heal" (a heart in a halo), "blood" (a drop, a
-- dagger across it), "prayer" (a flame between two open hands)
function eventart.icon(name)
  if not ICONS[name] then
    local p = newPainter(24, 24)
    if name == "heal" then
      p:disc(12, 12, 11, 11, { 0.30, 0.26, 0.55 })
      p:disc(12, 12, 9.5, 9.5, { 0.18, 0.15, 0.36 })
      local H = { "0110110", "1111111", "1111111", "0111110", "0011100", "0001000" }
      for j, row in ipairs(H) do
        for i = 1, #row do
          if row:sub(i, i) == "1" then
            local c = (i + j) % 5 == 0 and { 1.0, 0.55, 0.60 } or { 0.92, 0.22, 0.30 }
            p:rect(3 + (i - 1) * 2.4, 5 + (j - 1) * 2.4, 3, 3, c)
          end
        end
      end
      p:put(7, 8, { 1, 0.85, 0.85 })
    elseif name == "ammo" then
      -- a bullet standing in a halo, a small sight beside it
      p:disc(12, 12, 11, 11, { 0.18, 0.30, 0.20 })
      p:disc(12, 12, 9.5, 9.5, { 0.10, 0.16, 0.11 })
      p:rect(9, 10, 6, 9, { 0.85, 0.62, 0.28 })
      p:rect(9, 10, 2, 9, { 1.0, 0.85, 0.5 })
      p:rect(14, 10, 1, 9, { 0.55, 0.38, 0.16 })
      p:poly({ 9, 10, 15, 10, 14, 6, 10, 6 }, { 0.78, 0.5, 0.22 })
      p:poly({ 10, 6, 14, 6, 12, 3 }, { 0.62, 0.38, 0.14 })
      p:rect(9, 19, 6, 1, { 0.45, 0.30, 0.12 })
    elseif name == "gun" then
      -- a revolver, in a halo
      p:disc(12, 12, 11, 11, { 0.38, 0.34, 0.16 })
      p:disc(12, 12, 9.5, 9.5, { 0.17, 0.15, 0.08 })
      p:rect(3, 9, 13, 3, { 0.62, 0.64, 0.72 })
      p:rect(3, 9, 13, 1, { 0.88, 0.9, 0.96 })
      p:rect(12, 8, 6, 6, { 0.5, 0.52, 0.6 })
      p:rect(13, 9, 4, 4, { 0.30, 0.31, 0.38 })
      p:poly({ 15, 13, 19, 13, 18, 19, 14, 19 }, { 0.55, 0.34, 0.16 })
      p:rect(11, 12, 2, 3, { 0.4, 0.42, 0.5 })
      p:rect(4, 8, 1, 1, { 0.9, 0.9, 0.95 })
    elseif name == "perk" then
      -- a star in a halo
      p:disc(12, 12, 11, 11, { 0.45, 0.20, 0.20 })
      p:disc(12, 12, 9.5, 9.5, { 0.20, 0.08, 0.09 })
      local pts = {}
      for k = 0, 9 do
        local r = k % 2 == 0 and 8 or 3.4
        local a = -math.pi / 2 + k * math.pi / 5
        pts[#pts + 1] = 12 + math.cos(a) * r
        pts[#pts + 1] = 12.5 + math.sin(a) * r
      end
      p:poly(pts, function(x, y) return (x + y) % 6 < 3 and { 1.0, 0.78, 0.45 } or { 0.95, 0.6, 0.35 } end)
      p:disc(12, 12.5, 2, 2, { 1.0, 0.95, 0.75 })
    elseif name == "blood" then
      p:poly({ 12, 2, 19, 13, 17, 19, 12, 22, 7, 19, 5, 13 }, function(x, y)
        local t = (x - 5) / 14 + (y - 2) / 20
        return t < 0.7 and { 0.78, 0.08, 0.12 } or { 0.50, 0.04, 0.08 }
      end)
      p:rect(9, 9, 2, 4, { 1.0, 0.55, 0.55 })
      p:line(3, 21, 21, 3, { 0.78, 0.80, 0.86 })
      p:line(3, 22, 21, 4, { 0.45, 0.47, 0.55 })
      p:rect(1, 20, 4, 3, { 0.45, 0.28, 0.12 })
    else
      p:disc(12, 10, 6, 8, function(x, y, dx, dy)
        local d = abs(dx) * 0.8 - dy * 0.3
        return d < 0.35 and { 1.0, 0.92, 0.55 } or { 0.62, 0.50, 1.0 }
      end)
      p:poly({ 12, 0, 17, 9, 12, 14, 7, 9 }, { 0.62, 0.50, 1.0 })
      p:poly({ 12, 4, 15, 10, 12, 13, 9, 10 }, { 1.0, 0.95, 0.7 })
      -- the hands
      p:poly({ 1, 22, 3, 14, 9, 17, 10, 22 }, { 0.84, 0.66, 0.52 })
      p:poly({ 23, 22, 21, 14, 15, 17, 14, 22 }, { 0.84, 0.66, 0.52 })
      p:line(3, 15, 8, 18, { 0.62, 0.45, 0.34 })
      p:line(21, 15, 16, 18, { 0.62, 0.45, 0.34 })
    end
    ICONS[name] = p:image()
  end
  return ICONS[name]
end

-- An arrow, 11 wide: "up" or "down"
local arrows = {}
function eventart.arrow(dir)
  if not arrows[dir] then
    local p = newPainter(11, 11)
    local rows = {
      "....#....", "...###...", "..#####..", ".#######.", "#########", "...###...", "...###...", "...###...",
    }
    local pal = { ["#"] = { 1, 1, 1 } }
    if dir == "down" then
      local flipped = {}
      for i = #rows, 1, -1 do
        flipped[#flipped + 1] = rows[i]
      end
      rows = flipped
    end
    p:rows(1, 1, rows, pal)
    arrows[dir] = p:image()
  end
  return arrows[dir]
end

-- World pieces -----------------------------------------------------------------------------------

local targetImgs = {}
-- The gallery's bullseye, 11 x 11 (white for the flash of a hit)
function eventart.target(white)
  local key = white and "w" or "n"
  if not targetImgs[key] then
    local p = newPainter(11, 11)
    local function ring(r, c)
      p:disc(5.5, 5.5, r, r, white and { 1, 1, 1 } or c)
    end
    ring(5.5, { 0.20, 0.05, 0.07 })
    ring(4.8, { 0.88, 0.68, 0.18 })
    ring(3.6, { 0.82, 0.12, 0.14 })
    ring(2.5, { 0.94, 0.90, 0.78 })
    ring(1.2, { 0.82, 0.12, 0.14 })
    if not white then
      p:put(3, 2, { 1, 0.95, 0.7 })
      p:put(2, 3, { 1, 0.95, 0.7 })
    end
    targetImgs[key] = p:image()
  end
  return targetImgs[key]
end

local wheelImgs = {}
-- The tinker's cart wheel, 15 x 15, turned k eighths of a spoke apart (k 0..7)
function eventart.wheel(k)
  k = floor(k) % 8
  if not wheelImgs[k] then
    local p = newPainter(15, 15)
    local WD, WL = { 0.28, 0.19, 0.10 }, { 0.58, 0.40, 0.22 }
    p:disc(7.5, 7.5, 7.5, 7.5, WD)
    p:disc(7.5, 7.5, 5.6, 5.6, { 0, 0, 0, 0 })
    for y = 0, 14 do
      for x = 0, 14 do
        local dx, dy = x + 0.5 - 7.5, y + 0.5 - 7.5
        local d = sqrt(dx * dx + dy * dy)
        if d <= 5.6 then
          p.px[y * 15 + x] = nil
        end
      end
    end
    for s = 0, 3 do
      local a = s * math.pi / 4 + k * math.pi / 32
      p:line(7 + cos(a) * 6, 7 + sin(a) * 6, 7 - cos(a) * 6, 7 - sin(a) * 6, WL)
    end
    p:disc(7.5, 7.5, 1.6, 1.6, { 0.75, 0.62, 0.30 })
    p:put(7, 7, { 0.95, 0.85, 0.5 })
    wheelImgs[k] = p:image()
  end
  return wheelImgs[k]
end

local FONT3_TINY = {
  ["0"] = { "111", "101", "101", "101", "111" }, ["1"] = { "010", "110", "010", "010", "111" },
  ["2"] = { "111", "001", "111", "100", "111" }, ["3"] = { "111", "001", "111", "001", "111" },
  ["4"] = { "101", "101", "111", "001", "001" }, ["5"] = { "111", "100", "111", "001", "111" },
  ["6"] = { "111", "100", "111", "101", "111" }, ["7"] = { "111", "001", "010", "010", "010" },
  ["8"] = { "111", "101", "111", "101", "111" }, ["9"] = { "111", "101", "111", "001", "111" },
}
-- Digits three pixels wide, drawn straight into the world at (x, y) in the colour c
function eventart.tinyText(str, x, y, c)
  love.graphics.setColor(c[1], c[2], c[3], c[4] or 1)
  for ch in tostring(str):gmatch(".") do
    local g = FONT3_TINY[ch]
    if g then
      for j = 1, 5 do
        for i = 1, 3 do
          if g[j]:sub(i, i) == "1" then
            love.graphics.rectangle("fill", x + i - 1, y + j - 1, 1, 1)
          end
        end
      end
    end
    x = x + 4
  end
end

-- Big blocky lettering for the gallery's count: digits and "GO!" from 5 x 7 glyphs, scaled by whole pixels,
-- centred on (cx, cy), drawn straight into the world
local BIG = {
  G = { "01110", "10001", "10000", "10111", "10001", "10001", "01110" },
  O = { "01110", "10001", "10001", "10001", "10001", "10001", "01110" },
  ["!"] = { "00100", "00100", "00100", "00100", "00100", "00000", "00100" },
}
function eventart.bigText(str, cx, cy, scale, c)
  local n = #str
  local w = n * 6 * scale - scale
  local x0, y0 = floor(cx - w / 2), floor(cy - 3.5 * scale)
  for pass = 1, 2 do
    local col = pass == 1 and { 0.05, 0.03, 0.03, 0.8 } or c
    local off = pass == 1 and 1 or 0
    love.graphics.setColor(col[1], col[2], col[3], col[4] or 1)
    for k = 1, n do
      local g = FONT5[str:sub(k, k)] or BIG[str:sub(k, k)]
      if g then
        for j = 1, 7 do
          for i = 1, 5 do
            if g[j]:sub(i, i) == "1" then
              love.graphics.rectangle("fill", x0 + (k - 1) * 6 * scale + (i - 1) * scale + off, y0 + (j - 1) * scale + off, scale, scale)
            end
          end
        end
      end
    end
  end
end

local rerollImg
-- The re-roll icon: a circling arrow, 11 x 11, in white (tinted as it is drawn)
function eventart.reroll()
  if not rerollImg then
    local p = newPainter(11, 11)
    local W = { 1, 1, 1 }
    for y = 0, 10 do
      for x = 0, 10 do
        local dx, dy = x + 0.5 - 5.5, y + 0.5 - 5.5
        local d = sqrt(dx * dx + dy * dy)
        local a = math.atan2(dy, dx)
        if d >= 3.3 and d <= 4.9 and not (a > -1.35 and a < -0.35) then
          p:put(x, y, W)
        end
      end
    end
    p:poly({ 6.5, 0.2, 10.8, 1.4, 8.6, 5 }, W)
    rerollImg = p:image()
  end
  return rerollImg
end

eventart.Painter = newPainter
eventart.shade = shade
return eventart
