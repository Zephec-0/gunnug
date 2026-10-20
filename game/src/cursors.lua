-- The game's mouse pointer (menus, the weapon panel and the other overlays; in a
-- run the crosshair takes over, see src.hud): a small flat gold triangle, turned a
-- little about its tip, with no outline, a slightly deeper shade along its
-- underside and a faint drop shadow. While the button is held it tilts in a touch more and shrinks a touch.
-- Drawn as a pixel grid and scaled up 2x into real (hardware) cursors, so it never
-- lags the mouse. The click lands on the tip.
local cursors = {}

local SCALE = 2
local W, H = 13, 14 -- the grid, with room for the rim and for the tilted shape
local TIP = { 1, 1 } -- the tip's cell: the hotspot

local PALETTE = {
  g = { 0.91, 0.71, 0.31 },
  d = { 0.80, 0.60, 0.25 },
  s = { 0.02, 0.01, 0.04, 0.34 }, -- the drop shadow: one cell down and to the right, soft
}

-- The triangle's corners, in grid cells, tip first
local SHAPE = { { 1.0, 1.0 }, { 1.0, 11.5 }, { 8.0, 8.5 } }

local function inside(poly, px, py)
  local sign
  for i = 1, 3 do
    local a, b = poly[i], poly[i % 3 + 1]
    local cross = (b[1] - a[1]) * (py - a[2]) - (b[2] - a[2]) * (px - a[1])
    if math.abs(cross) > 0.9 then
      local s = cross > 0
      if sign ~= nil and sign ~= s then
        return false
      end
      sign = s
    end
  end
  return true
end

-- The grid for the shape turned by `angle` (radians, clockwise on screen) and scaled
-- by `k`, both about the tip: rows of palette letters
local function rows(angle, k)
  local poly = {}
  local c, s = math.cos(angle), math.sin(angle)
  for i, p in ipairs(SHAPE) do
    local x, y = (p[1] - TIP[1]) * k, (p[2] - TIP[2]) * k
    poly[i] = { TIP[1] + x * c - y * s, TIP[2] + x * s + y * c }
  end
  local grid = {}
  for y = 1, H do
    grid[y] = {}
    for x = 1, W do
      grid[y][x] = inside(poly, x - 0.5, y - 0.5) and "g" or "."
    end
  end
  local function at(x, y)
    return grid[y] and grid[y][x] or "."
  end
  local out = {}
  for y = 1, H do
    local row = {}
    for x = 1, W do
      local ch = at(x, y)
      if ch == "g" and (at(x + 1, y) == "." or at(x, y + 1) == ".") then
        ch = "d" -- the underside, a shade deeper
      elseif ch == "." and at(x - 1, y - 1) ~= "." then
        ch = "s"
      end
      row[x] = ch
    end
    out[y] = table.concat(row)
  end
  return out
end

cursors.rest = rows(math.rad(-20), 0.88)
cursors.pressed = rows(math.rad(-25), 0.82) -- (a small change: a touch more turned, a touch smaller)
cursors.hot = TIP

local function build(grid, scale)
  local data = love.image.newImageData(W * scale, H * scale)
  for y = 1, H do
    for x = 1, W do
      local c = PALETTE[grid[y]:sub(x, x)]
      if c then
        for dy = 0, scale - 1 do
          for dx = 0, scale - 1 do
            data:setPixel((x - 1) * scale + dx, (y - 1) * scale + dy, c[1], c[2], c[3], c[4] or 1)
          end
        end
      end
    end
  end
  return data
end

local made, held

local function make()
  local ok, rest, pressed = pcall(function()
    return love.mouse.newCursor(build(cursors.rest, SCALE), TIP[1] * SCALE, TIP[2] * SCALE),
      love.mouse.newCursor(build(cursors.pressed, SCALE), TIP[1] * SCALE, TIP[2] * SCALE)
  end)
  made = ok and { rest = rest, pressed = pressed } or false
end

-- Makes this the system pointer (if it cannot be made, the default one stays), and
-- tilts it while the left button is down: call every frame
function cursors.update()
  if made == nil then
    make()
  end
  if not made then
    return
  end
  local down = love.mouse.isDown(1)
  if down ~= held then
    held = down
    love.mouse.setCursor(down and made.pressed or made.rest)
  end
end

-- (the same, once, at start-up)
cursors.apply = cursors.update

return cursors
