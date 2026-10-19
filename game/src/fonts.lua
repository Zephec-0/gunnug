local fonts = {}

-- The game's lettering: Scientifica, a 5-pixel-wide bitmap face (cap height 7, x-height 5, descenders two rows below
-- the baseline; src/scientificadata.lua is generated from assets/fonts/scientifica-11.bdf). It is drawn white
-- with a one-pixel dark navy drop shadow, down and to the right, so it reads on any background. The glyphs
-- carry their own colours, so print them in white: tinting with another colour shifts the whole face toward it
-- (reds and greens still read, which suits warnings and prices). fonts.get(px) matches the size of a vector font
-- of that pixel height, using a whole-number enlargement of the bitmap, so it can replace love.graphics.newFont.
-- fonts.rule draws the ornamental divider used under titles.
local utf8 = require("utf8") -- (the LOVE framework's own)

-- The three weights of the face, loaded the first time they are wanted
local FACES = { regular = "src.scientificadata", bold = "src.scientificabold", italic = "src.scientificaitalic" }
local DATA = {}

local CAP = 7 -- cap height in rows; the text box starts at the top of the capitals
local ROWS = 9 -- cap top to the lowest descender
local SHADOW = 1 -- the drop shadow's reach, right and down, in glyph pixels

-- Colours of the face (also used for ornaments)
fonts.WHITE = { 0.97, 0.98, 1.0 }
fonts.ICE = { 0.92, 0.95, 1.0 }
fonts.STEEL = { 0.46, 0.62, 0.90 }

local cache = {}
local info = setmetatable({}, { __mode = "k" }) -- font -> { k, style, plain }

-- Builds the image font with every pixel k times as big. plain = no drop shadow (for dark text on a light
-- ground, where the shadow only thickens the strokes until the letters run together).
local function build(style, k, plain)
  DATA[style] = DATA[style] or require(FACES[style])
  local data = DATA[style]
  local shadow = plain and 0 or SHADOW
  local lift = style == "italic" and 1 or 0 -- (the slanted capitals stand a row above the cap line)
  local codes = {}
  for code in pairs(data) do
    codes[#codes + 1] = code
  end
  table.sort(codes)
  local cellRows = ROWS + lift + shadow
  local cellH = cellRows * k
  -- A glyph that leans out to the left of its cell (a negative offset) is moved right to sit inside it
  local function span(g)
    return math.max(g[1], math.max(0, -g[4]) + g[4] + g[2])
  end
  local total = 1
  for _, code in ipairs(codes) do
    total = total + (span(data[code]) + shadow) * k + 1
  end
  local img = love.image.newImageData(total, cellH)
  for y = 0, cellH - 1 do
    img:setPixel(0, y, 1, 0, 1, 1) -- separator
  end
  local chars = {}
  local x0 = 1
  for _, code in ipairs(codes) do
    local g = data[code]
    local adv, w, h, xo, yo, bits = g[1], g[2], g[3], g[4], g[5], g[6]
    local cols = span(g) + shadow
    local cellW = cols * k
    chars[#chars + 1] = utf8.char(code)
    for y = 0, cellH - 1 do
      img:setPixel(x0 + cellW, y, 1, 0, 1, 1)
    end
    -- the glyph's pixels (gx, gy in glyph pixels, from the cell's top-left)
    local top = CAP - (yo + h) + lift
    local left = xo + math.max(0, -xo)
    local on = {}
    for r = 1, h do
      local byte = bits[r]
      for c = 0, w - 1 do
        if math.floor(byte / 2 ^ (7 - c)) % 2 == 1 then
          on[(top + r - 1) * 64 + (left + c)] = true
        end
      end
    end
    local function at(gx, gy)
      return on[gy * 64 + gx]
    end
    local function put(gx, gy, r, g2, b, a)
      if gx < 0 or gy < 0 or gx >= cols or gy >= cellRows then
        return
      end
      for dy = 0, k - 1 do
        for dx = 0, k - 1 do
          img:setPixel(x0 + gx * k + dx, gy * k + dy, r, g2, b, a)
        end
      end
    end
    for gy = 0, cellRows - 1 do
      for gx = 0, cols - 1 do
        if at(gx, gy) then
          put(gx, gy, 1, 1, 1, 1)
        elseif not plain and (at(gx - 1, gy - 1) or at(gx - 1, gy) or at(gx, gy - 1)) then
          put(gx, gy, 0.04, 0.06, 0.18, 1) -- the shadow against the letter
        end
      end
    end
    x0 = x0 + cellW + 1
  end
  local font = love.graphics.newImageFont(img, table.concat(chars))
  font:setFilter("nearest", "nearest")
  font:setLineHeight(plain and 1.35 or 1.2) -- room between wrapped lines
  info[font] = { k = k, style = style, plain = plain }
  return font
end

local function variant(style, k, plain)
  local key = (style or "regular") .. k .. (plain and "p" or "")
  if not cache[key] then
    cache[key] = build(style or "regular", k, plain)
  end
  return cache[key]
end

-- A font about as tall as a vector font of px pixels (capitals about 0.72 of it, a whole number of bitmap
-- pixels each). style: nil (regular), "bold" or "italic"
function fonts.get(px, style)
  return variant(style, math.max(1, math.floor(px * 0.72 / CAP + 0.5)))
end

-- The same, without the drop shadow
function fonts.plain(px, style)
  return variant(style, math.max(1, math.floor(px * 0.72 / CAP + 0.5)), true)
end

-- Where the ink of one character sits in a font this module made: x, y offset of its top-left from the
-- point it is printed at, and its width and height (all in screen pixels, the drop shadow not counted), so a
-- letter can be centred on what you see rather than on its cell
function fonts.ink(font, ch)
  local i = info[font]
  local g = i and DATA[i.style] and DATA[i.style][utf8.codepoint(ch)]
  if not g then
    return 0, 0, font:getWidth(ch), font:getHeight()
  end
  local lift = i.style == "italic" and 1 or 0
  return (g[4] + math.max(0, -g[4])) * i.k, (CAP - (g[5] + g[3]) + lift) * i.k, g[2] * i.k, g[3] * i.k
end

-- Another weight of a font this module made, at the same size (and with or without the shadow)
function fonts.like(font, style, plain)
  local i = info[font]
  if not i then
    return font
  end
  return variant(style or i.style, i.k, plain)
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
