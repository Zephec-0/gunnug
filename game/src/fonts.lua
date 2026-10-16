-- The game's lettering: a hand-drawn pixel face in the 32-bit style, stubby
-- and refined. The letters are drawn on a wide 6x7 grid (cap height 7, x-height
-- 5, descenders two rows below the baseline), so they come out short and
-- broad, then:
--   * enlarged 2x with a pixel-art smoothing pass (EPX / Scale2x), which
--     rounds the corners and straightens the diagonals while keeping every
--     pixel hard-edged: strokes end up two pixels thick on a 14-row cap
--     height, finer than the chunky 16-bit face this replaced;
--   * shaded mostly white: bright along every upper edge and through the body,
--     easing to a pale steel blue only at the foot, with a slightly darker
--     rim on lower edges;
--   * given a two-step drop shadow, down and to the right: a deep navy pixel
--     against the letter and a fainter black one beyond it.
-- Small sizes skip the enlargement and use the 6x7 grid as it is. The glyphs
-- carry their own colours, so print them in white: tinting with another colour
-- shifts the whole face toward it (reds and greens still read, which suits
-- warnings and prices). fonts.get(px) matches the size of a vector font of that
-- pixel height, so it can replace love.graphics.newFont. fonts.rule draws the
-- ornamental divider used under titles.
local fonts = {}

local CAP = 7 -- cap height in grid rows
local SHADOW = 2 -- the drop shadow's reach, right and down, in output pixels
local MAX_ROWS = 9 -- the tallest glyph: lower case with a descender

-- Colours of the face (also used for ornaments)
fonts.WHITE = { 0.97, 0.98, 1.0 }
fonts.ICE = { 0.92, 0.95, 1.0 }
fonts.STEEL = { 0.46, 0.62, 0.90 }

-- Glyphs: one string per row ('#' set). Capitals and digits are 7 rows; lower
-- case is 7 rows (two blank rows over the x-height) or 9 with a descender.
local G = {
  A = { "..##..", ".#..#.", "#....#", "######", "#....#", "#....#", "#....#" },
  B = { "#####.", "#....#", "#....#", "#####.", "#....#", "#....#", "#####." },
  C = { ".####.", "#....#", "#.....", "#.....", "#.....", "#....#", ".####." },
  D = { "#####.", "#....#", "#....#", "#....#", "#....#", "#....#", "#####." },
  E = { "######", "#.....", "#.....", "####..", "#.....", "#.....", "######" },
  F = { "######", "#.....", "#.....", "####..", "#.....", "#.....", "#....." },
  G = { ".####.", "#....#", "#.....", "#..###", "#....#", "#....#", ".####." },
  H = { "#....#", "#....#", "#....#", "######", "#....#", "#....#", "#....#" },
  I = { "#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####" },
  J = { "...###", "....#.", "....#.", "....#.", "#...#.", "#...#.", ".###.." },
  K = { "#...#.", "#..#..", "#.#...", "##....", "#.#...", "#..#..", "#...#." },
  L = { "#.....", "#.....", "#.....", "#.....", "#.....", "#.....", "######" },
  M = { "#....#", "##..##", "#.##.#", "#.##.#", "#....#", "#....#", "#....#" },
  N = { "#....#", "##...#", "#.#..#", "#..#.#", "#...##", "#....#", "#....#" },
  O = { ".####.", "#....#", "#....#", "#....#", "#....#", "#....#", ".####." },
  P = { "#####.", "#....#", "#....#", "#####.", "#.....", "#.....", "#....." },
  Q = { ".####.", "#....#", "#....#", "#....#", "#..#.#", "#...#.", ".###.#" },
  R = { "#####.", "#....#", "#....#", "#####.", "#.#...", "#..#..", "#...##" },
  S = { ".#####", "#.....", "#.....", ".####.", ".....#", ".....#", "#####." },
  T = { "######", "..##..", "..##..", "..##..", "..##..", "..##..", "..##.." },
  U = { "#....#", "#....#", "#....#", "#....#", "#....#", "#....#", ".####." },
  V = { "#....#", "#....#", "#....#", "#....#", ".#..#.", ".#..#.", "..##.." },
  W = { "#....#", "#....#", "#....#", "#.##.#", "#.##.#", "##..##", "#....#" },
  X = { "#....#", ".#..#.", "..##..", "..##..", "..##..", ".#..#.", "#....#" },
  Y = { "#....#", ".#..#.", "..##..", "..##..", "..##..", "..##..", "..##.." },
  Z = { "######", ".....#", "....#.", "...#..", "..#...", "#.....", "######" },
  ["0"] = { ".####.", "#....#", "#...##", "#.##.#", "##...#", "#....#", ".####." },
  ["1"] = { "..##..", ".###..", "..##..", "..##..", "..##..", "..##..", ".####." },
  ["2"] = { ".####.", "#....#", ".....#", "...##.", "..#...", ".#....", "######" },
  ["3"] = { "#####.", ".....#", ".....#", "..###.", ".....#", ".....#", "#####." },
  ["4"] = { "...##.", "..#.#.", ".#..#.", "#...#.", "######", "....#.", "....#." },
  ["5"] = { "######", "#.....", "#####.", ".....#", ".....#", "#....#", ".####." },
  ["6"] = { ".####.", "#.....", "#.....", "#####.", "#....#", "#....#", ".####." },
  ["7"] = { "######", ".....#", "....#.", "...#..", "..#...", "..#...", "..#..." },
  ["8"] = { ".####.", "#....#", "#....#", ".####.", "#....#", "#....#", ".####." },
  ["9"] = { ".####.", "#....#", "#....#", ".#####", ".....#", ".....#", ".####." },
  [" "] = { "..", "..", "..", "..", "..", "..", ".." },
  ["."] = { ".", ".", ".", ".", ".", "#", "#" },
  [","] = { "..", "..", "..", "..", ".#", ".#", "#." },
  [":"] = { ".", "#", "#", ".", ".", "#", "#" },
  [";"] = { "..", ".#", ".#", "..", "..", ".#", "#." },
  ["!"] = { "#", "#", "#", "#", "#", ".", "#" },
  ["?"] = { ".####.", "#....#", ".....#", "...##.", "..#...", "......", "..#..." },
  ["'"] = { "#", "#", "#", ".", ".", ".", "." },
  ['"'] = { "#.#", "#.#", "#.#", "...", "...", "...", "..." },
  ["-"] = { "......", "......", "......", "######", "......", "......", "......" },
  ["+"] = { "......", "..##..", "..##..", "######", "..##..", "..##..", "......" },
  ["/"] = { ".....#", "....#.", "....#.", "...#..", "..#...", "..#...", "#....." },
  ["%"] = { "##...#", "##..#.", "...#..", "..#...", ".#..##", "#...##", "......" },
  ["("] = { "..#", ".#.", "#..", "#..", "#..", ".#.", "..#" },
  [")"] = { "#..", ".#.", "..#", "..#", "..#", ".#.", "#.." },
  ["["] = { "###", "#..", "#..", "#..", "#..", "#..", "###" },
  ["]"] = { "###", "..#", "..#", "..#", "..#", "..#", "###" },
  ["<"] = { "...#", "..#.", ".#..", "#...", ".#..", "..#.", "...#" },
  [">"] = { "#...", ".#..", "..#.", "...#", "..#.", ".#..", "#..." },
  ["="] = { "......", "......", "######", "......", "######", "......", "......" },
  ["*"] = { "......", "#.##.#", ".####.", "######", ".####.", "#.##.#", "......" },
  ["#"] = { ".#..#.", ".#..#.", "######", ".#..#.", "######", ".#..#.", ".#..#." },
  ["&"] = { ".###..", "#...#.", "#..#..", ".##...", "#..#.#", "#...#.", ".###.#" },
  ["_"] = { "......", "......", "......", "......", "......", "......", "######" },
  ["|"] = { "#", "#", "#", "#", "#", "#", "#" },
  ["~"] = { "......", "......", ".##..#", "#..##.", "......", "......", "......" },
  ["@"] = { ".####.", "#....#", "#.####", "#.#..#", "#.####", "#.....", ".####." },
  ["^"] = { "..##..", ".#..#.", "#....#", "......", "......", "......", "......" },
  -- Lower case
  a = { ".....", ".....", ".###.", "....#", ".####", "#...#", ".####" },
  b = { "#....", "#....", "####.", "#...#", "#...#", "#...#", "####." },
  c = { ".....", ".....", ".###.", "#...#", "#....", "#...#", ".###." },
  d = { "....#", "....#", ".####", "#...#", "#...#", "#...#", ".####" },
  e = { ".....", ".....", ".###.", "#...#", "#####", "#....", ".###." },
  f = { "..##.", ".#...", "####.", ".#...", ".#...", ".#...", ".#..." },
  g = { ".....", ".....", ".####", "#...#", "#...#", "#...#", ".####", "....#", ".###." },
  h = { "#....", "#....", "####.", "#...#", "#...#", "#...#", "#...#" },
  i = { ".", "#", ".", "#", "#", "#", "#" },
  j = { "..", ".#", "..", ".#", ".#", ".#", ".#", ".#", "#." },
  k = { "#....", "#....", "#..#.", "#.#..", "##...", "#.#..", "#..#." },
  l = { "##.", ".#.", ".#.", ".#.", ".#.", ".#.", ".##" },
  m = { ".....", ".....", "##.#.", "#.#.#", "#.#.#", "#...#", "#...#" },
  n = { ".....", ".....", "####.", "#...#", "#...#", "#...#", "#...#" },
  o = { ".....", ".....", ".###.", "#...#", "#...#", "#...#", ".###." },
  p = { ".....", ".....", "####.", "#...#", "#...#", "#...#", "####.", "#....", "#...." },
  q = { ".....", ".....", ".####", "#...#", "#...#", "#...#", ".####", "....#", "....#" },
  r = { ".....", ".....", "#.##.", "##..#", "#....", "#....", "#...." },
  s = { ".....", ".....", ".####", "#....", ".###.", "....#", "####." },
  t = { ".#...", ".#...", "####.", ".#...", ".#...", ".#..#", "..##." },
  u = { ".....", ".....", "#...#", "#...#", "#...#", "#..##", ".##.#" },
  v = { ".....", ".....", "#...#", "#...#", "#...#", ".#.#.", "..#.." },
  w = { ".....", ".....", "#...#", "#...#", "#.#.#", "#.#.#", ".#.#." },
  x = { ".....", ".....", "#...#", ".#.#.", "..#..", ".#.#.", "#...#" },
  y = { ".....", ".....", "#...#", "#...#", "#...#", ".####", "....#", "....#", ".###." },
  z = { ".....", ".....", "#####", "...#.", "..#..", ".#...", "#####" },
}

-- What is printed: capitals, digits and punctuation, then lower case
local ORDER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,:;!?'\"-+/%()[]<>=*#&_|~@^"
local LOWER = "abcdefghijklmnopqrstuvwxyz"

local cache = {}

-- The face's colours: t = 0 at the top of a letter, 1 at its foot
local function bodyColor(t)
  if t < 0.6 then
    local k = t / 0.6
    return 1.0 + (0.94 - 1.0) * k, 1.0 + (0.97 - 1.0) * k, 1.0
  end
  local k = (t - 0.6) / 0.4
  return 0.94 + (0.66 - 0.94) * k, 0.97 + (0.78 - 0.97) * k, 1.0 + (0.95 - 1.0) * k
end

-- A glyph's strings as a boolean grid grid[y][x] (1-based)
local function parse(rows)
  local grid = {}
  for y, line in ipairs(rows) do
    grid[y] = {}
    for x = 1, #line do
      grid[y][x] = line:sub(x, x) == "#"
    end
  end
  return grid, #rows[1], #rows
end

-- Scale2x (EPX): each pixel becomes four, and a pixel at a diagonal corner
-- takes its neighbour's colour, so corners round off and diagonals smooth
-- while every pixel stays hard-edged
local function epx(grid, w, h)
  local function at(x, y)
    return grid[y] and grid[y][x] or false
  end
  local out = {}
  for y = 1, h * 2 do
    out[y] = {}
  end
  for y = 1, h do
    for x = 1, w do
      local p, a, b, c, d = at(x, y), at(x, y - 1), at(x + 1, y), at(x - 1, y), at(x, y + 1)
      local p1, p2, p3, p4 = p, p, p, p
      if c == a and c ~= d and a ~= b then
        p1 = a
      end
      if a == b and a ~= c and b ~= d then
        p2 = b
      end
      if d == c and d ~= b and c ~= a then
        p3 = c
      end
      if b == d and b ~= a and d ~= c then
        p4 = d
      end
      out[2 * y - 1][2 * x - 1], out[2 * y - 1][2 * x] = p1, p2
      out[2 * y][2 * x - 1], out[2 * y][2 * x] = p3, p4
    end
  end
  return out, w * 2, h * 2
end

-- Builds the image font: s = 1 uses the grid as it is, s = 2 enlarges it with
-- EPX; k scales every pixel up by a whole number
local function build(s, k)
  local list = {}
  for i = 1, #ORDER do
    list[#list + 1] = ORDER:sub(i, i)
  end
  for i = 1, #LOWER do
    list[#list + 1] = LOWER:sub(i, i)
  end
  local capRows = CAP * s
  local cellRows = MAX_ROWS * s + SHADOW
  local glyphs, total = {}, 1
  for i, ch in ipairs(list) do
    local grid, w, h = parse(G[ch])
    if s == 2 then
      grid, w, h = epx(grid, w, h)
    end
    glyphs[i] = { grid = grid, w = w, h = h, cell = (ch == " " and 4 * s or w + SHADOW) * k }
    total = total + glyphs[i].cell + 1
  end
  local img = love.image.newImageData(total, cellRows * k)
  for y = 0, cellRows * k - 1 do
    img:setPixel(0, y, 1, 0, 1, 1) -- separator
  end
  local x0 = 1
  for i = 1, #list do
    local g = glyphs[i]
    for y = 0, cellRows * k - 1 do
      img:setPixel(x0 + g.cell, y, 1, 0, 1, 1)
    end
    local function on(gx, gy)
      return gx >= 1 and gy >= 1 and gx <= g.w and gy <= g.h and g.grid[gy][gx]
    end
    for gy = 1, cellRows do
      for gx = 1, g.w + SHADOW do
        local r, gr, b, a
        if on(gx, gy) then
          r, gr, b = bodyColor(math.min(1, (gy - 1) / (capRows - 1)))
          if not on(gx, gy - 1) then
            r, gr, b = 1, 1, 1 -- lit top edge
          end
          if not on(gx, gy + 1) or not on(gx + 1, gy) then
            r, gr, b = r * 0.78, gr * 0.84, b * 0.94 -- a slightly darker rim below and to the right
          end
          a = 1
        elseif on(gx - 1, gy - 1) or on(gx - 1, gy) or on(gx, gy - 1) then
          r, gr, b, a = 0.04, 0.06, 0.18, 1 -- the shadow against the letter
        elseif on(gx - 2, gy - 2) or on(gx - 2, gy - 1) or on(gx - 1, gy - 2) then
          r, gr, b, a = 0, 0, 0, 0.5 -- and the fainter one beyond it
        end
        if a then
          for dy = 0, k - 1 do
            for dx = 0, k - 1 do
              img:setPixel(x0 + (gx - 1) * k + dx, (gy - 1) * k + dy, r, gr, b, a)
            end
          end
        end
      end
    end
    x0 = x0 + g.cell + 1
  end
  local font = love.graphics.newImageFont(img, table.concat(list))
  font:setFilter("nearest", "nearest")
  font:setLineHeight(1.25) -- room between wrapped lines for the shadow
  return font
end

-- Which build suits a vector font of px pixels: small sizes use the 6x7 grid
-- as it is, larger ones the smoothed 2x grid, each at a whole-number scale
local function sizeFor(px)
  local cap = px * 0.72
  if cap < 11 then
    return 1, math.max(1, math.floor(cap / CAP + 0.5))
  end
  return 2, math.max(1, math.floor(cap / (CAP * 2) + 0.5))
end

-- A font about as tall as a vector font of px pixels
function fonts.get(px)
  local s, k = sizeFor(px)
  local key = s * 100 + k
  if not cache[key] then
    cache[key] = build(s, k)
  end
  return cache[key]
end

-- Prints name in `color`, then " [X]" with the weapon grade's letter in the
-- grade's own colour. Returns the total width. (shadow: the offset of an extra
-- black drop shadow, if wanted.)
function fonts.printGraded(font, name, grade, x, y, color, shadow)
  love.graphics.setFont(font)
  local tail = " ["
  local wName = font:getWidth(name)
  local wTail = font:getWidth(tail)
  local wLetter = font:getWidth(grade.letter)
  local wEnd = font:getWidth("]")
  x, y = math.floor(x), math.floor(y)
  if shadow then
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.print(name .. tail .. grade.letter .. "]", x + shadow, y + shadow)
  end
  love.graphics.setColor(color or { 1, 1, 1 })
  love.graphics.print(name .. tail, x, y)
  love.graphics.setColor(grade.color)
  love.graphics.print(grade.letter, x + wName + wTail, y)
  love.graphics.setColor(color or { 1, 1, 1 })
  love.graphics.print("]", x + wName + wTail + wLetter, y)
  return wName + wTail + wLetter + wEnd
end

-- Width of the text printGraded prints
function fonts.gradedWidth(font, name, grade)
  return font:getWidth(name .. " [" .. grade.letter .. "]")
end

-- An ornamental rule centred on cx: a thin line fading out to both sides
-- with a diamond and two small beads in the middle, like the rune-cut
-- dividers on a stone. unit = one UI pixel; r, g, b the colour (default
-- the face's steel blue).
function fonts.rule(cx, y, width, unit, r, g, b, alpha)
  r, g, b = r or fonts.STEEL[1], g or fonts.STEEL[2], b or fonts.STEEL[3]
  alpha = alpha or 1
  local half = width / 2
  local steps = 24
  for i = 0, steps - 1 do
    local t = i / steps
    local fade = (1 - t) ^ 1.2
    local seg = half / steps
    love.graphics.setColor(r, g, b, alpha * fade)
    love.graphics.rectangle("fill", cx + 6 * unit + t * (half - 6 * unit), y, seg + 1, unit)
    love.graphics.rectangle("fill", cx - 6 * unit - t * (half - 6 * unit) - seg, y, seg + 1, unit)
  end
  love.graphics.setColor(0, 0, 0, alpha * 0.8)
  love.graphics.polygon("fill", cx, y - 2 * unit, cx + 4 * unit, y + unit / 2, cx, y + 3 * unit, cx - 4 * unit, y + unit / 2)
  love.graphics.setColor(r, g, b, alpha)
  love.graphics.polygon("fill", cx, y - 3 * unit, cx + 3 * unit, y + unit / 2, cx, y + 4 * unit, cx - 3 * unit, y + unit / 2)
  love.graphics.setColor(fonts.WHITE[1], fonts.WHITE[2], fonts.WHITE[3], alpha)
  love.graphics.rectangle("fill", cx - unit / 2, y - unit, unit, unit * 2.5)
  love.graphics.setColor(r, g, b, alpha)
  love.graphics.rectangle("fill", cx - 5.5 * unit, y - unit / 2, unit * 1.5, unit * 2)
  love.graphics.rectangle("fill", cx + 4 * unit, y - unit / 2, unit * 1.5, unit * 2)
end

return fonts
