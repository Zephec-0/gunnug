-- The Cartographer's survey map (design doc §11a-iv): records where the
-- hunter has been this run (in coarse cells, as a small image of open ground
-- and rock) and draws it as a page of the menu (M). The second tier of the
-- Survey Map upgrade also marks the shops, chests, hatches and bounty
-- quarries that lie in explored ground.
local surveymap = {}

local CELL = 16
local REVEAL = 6 -- cells around the hunter that are charted, as a radius

local world, data, image
local bx0, by0, bx1, by1 -- the charted cells' bounding box
-- The view: automatic (fitted to the charted ground) until the hunter zooms or
-- pans, then fixed at { s = screen px per cell, x0, y0 = the cell at the box's corner }
local view = { auto = true }
local geom = { x = 0, y = 0, w = 1, h = 1, s = 1, cx0 = 0, cy0 = 0 } -- where the last draw put things
local markers = {} -- the hunter's own points of interest: { x, y } in world pixels
local gw, gh = 0, 0
local dirty = false
local timer = 0

local OPEN = { 0.10, 0.16, 0.20 }
local ROCK = { 0.42, 0.34, 0.28 }
local SKY = { 0.20, 0.14, 0.26 }

-- Starts a fresh chart for a world (a new run)
function surveymap.reset(w)
  world = w
  gw = math.ceil((w.right - w.left) / CELL)
  gh = math.ceil((w.bottom - w.top) / CELL)
  data = love.image.newImageData(gw, gh)
  image = nil
  bx0, by0, bx1, by1 = nil, nil, nil, nil
  view = { auto = true }
  markers = {}
  dirty = true
  timer = 0
end

local function cellOf(x, y)
  return math.floor((x - world.left) / CELL), math.floor((y - world.top) / CELL)
end

-- Charts the ground around the hunter (a few times a second)
function surveymap.update(dt, px, py)
  if not world then
    return
  end
  timer = timer - dt
  if timer > 0 then
    return
  end
  timer = 0.25
  local cx, cy = cellOf(px, py)
  for dy = -REVEAL, REVEAL do
    for dx = -REVEAL, REVEAL do
      local x, y = cx + dx, cy + dy
      if dx * dx + dy * dy <= REVEAL * REVEAL and x >= 0 and y >= 0 and x < gw and y < gh then
        local _, _, _, a = data:getPixel(x, y)
        if a == 0 then
          local wx, wy = world.left + x * CELL + CELL / 2, world.top + y * CELL + CELL / 2
          local c = world:isSolid(math.floor(wx), math.floor(wy)) and ROCK or OPEN
          data:setPixel(x, y, c[1], c[2], c[3], 1)
          dirty = true
          bx0, by0 = math.min(bx0 or x, x), math.min(by0 or y, y)
          bx1, by1 = math.max(bx1 or x, x), math.max(by1 or y, y)
        end
      end
    end
  end
end

local function explored(wx, wy)
  if not world then
    return false
  end
  local x, y = cellOf(wx, wy)
  if x < 0 or y < 0 or x >= gw or y >= gh then
    return false
  end
  local _, _, _, a = data:getPixel(x, y)
  return a > 0
end

-- Draws the chart into the box (x, y, w, h); u is one UI unit. tier 2 adds
-- the marks. `player` is the hunter, `marks` a list of { x, y, kind } to show.
function surveymap.draw(x, y, w, h, u, player, tier, marks)
  if not data then
    return
  end
  if dirty or not image then
    if image then
      image:replacePixels(data)
    else
      image = love.graphics.newImage(data)
      image:setFilter("nearest", "nearest")
    end
    dirty = false
  end
  -- Only the charted part is shown (with a margin, and never smaller than a
  -- screenful of cells), centred in the box
  local mx0, my0, mx1, my1 = bx0 or 0, by0 or 0, bx1 or 0, by1 or 0
  local cw, ch = math.max(70, mx1 - mx0 + 12), math.max(40, my1 - my0 + 12)
  local aspect = w / h
  if cw / ch < aspect then
    cw = ch * aspect
  else
    ch = cw / aspect
  end
  local cx0 = (mx0 + mx1) / 2 - cw / 2 + 0.5
  local cy0 = (my0 + my1) / 2 - ch / 2 + 0.5
  local s = w / cw
  local ox, oy = x, y
  if not view.auto then
    s, cx0, cy0 = view.s, view.x0, view.y0
  end
  geom = { x = x, y = y, w = w, h = h, s = s, cx0 = cx0, cy0 = cy0 }
  love.graphics.setColor(0.03, 0.025, 0.05, 0.95)
  love.graphics.rectangle("fill", ox, oy, w, h)
  love.graphics.setScissor(ox, oy, w, h)
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(image, ox - cx0 * s, oy - cy0 * s, 0, s, s)
  local function at(wx, wy)
    return ox + ((wx - world.left) / CELL - cx0) * s, oy + ((wy - world.top) / CELL - cy0) * s
  end
  local dot = math.max(2, math.floor(u * 1.4))
  if tier >= 2 then
    for _, m in ipairs(marks or {}) do
      if explored(m.x, m.y) or m.always then
        local sx, sy = at(m.x, m.y)
        local c = m.color or { 1, 1, 1 }
        love.graphics.setColor(0, 0, 0, 0.8)
        love.graphics.rectangle("fill", sx - dot, sy - dot, dot * 2, dot * 2)
        love.graphics.setColor(c[1], c[2], c[3])
        love.graphics.rectangle("fill", sx - dot + 1, sy - dot + 1, dot * 2 - 2, dot * 2 - 2)
      end
    end
  end
  if player then
    local px, py = player:center()
    local sx, sy = at(px, py)
    local pulse = 0.6 + 0.4 * math.sin(love.timer.getTime() * 6)
    love.graphics.setColor(1, 0.95, 0.5, pulse)
    love.graphics.circle("line", sx, sy, dot * 2.4)
    love.graphics.setColor(1, 0.95, 0.5)
    love.graphics.circle("fill", sx, sy, dot)
  end
  -- the hunter's own marks: a teal X, with the way there from where he stands
  if #markers > 0 then
    love.graphics.setLineWidth(math.max(2, math.floor(u * 0.8)))
    local px, py = 0, 0
    if player then
      px, py = player:center()
    end
    for _, m in ipairs(markers) do
      local sx, sy = at(m.x, m.y)
      local r = math.max(3, math.floor(u * 2.2))
      love.graphics.setColor(0, 0, 0, 0.8)
      love.graphics.line(sx - r - 1, sy - r - 1, sx + r + 1, sy + r + 1)
      love.graphics.line(sx - r - 1, sy + r + 1, sx + r + 1, sy - r - 1)
      love.graphics.setColor(0.25, 0.92, 0.85)
      love.graphics.line(sx - r, sy - r, sx + r, sy + r)
      love.graphics.line(sx - r, sy + r, sx + r, sy - r)
      if player then
        local d = math.floor(math.sqrt((m.x - px) ^ 2 + (m.y - py) ^ 2) / 8 + 0.5)
        local f = love.graphics.getFont()
        local text = d .. " m"
        love.graphics.setColor(0, 0, 0, 0.75)
        love.graphics.print(text, math.floor(sx + r + 3 + 1), math.floor(sy - f:getHeight() / 2 + 1))
        love.graphics.setColor(0.45, 1, 0.95)
        love.graphics.print(text, math.floor(sx + r + 3), math.floor(sy - f:getHeight() / 2))
      end
    end
    love.graphics.setLineWidth(1)
  end
  love.graphics.setScissor()
  love.graphics.setColor(0.55, 0.48, 0.42, 0.8)
  love.graphics.rectangle("line", ox, oy, w, h)
end

-- Zoom and pan --------------------------------------------------------------------------

local MIN_S, MAX_S = 0.5, 30

-- Fixes the view where it is now (so it can be changed from there)
local function manual()
  if view.auto then
    view = { auto = false, s = geom.s, x0 = geom.cx0, y0 = geom.cy0 }
  end
end

-- Zooms by a factor about a point of the box (sx, sy in screen pixels; the
-- box's middle if nil)
function surveymap.zoom(factor, sx, sy)
  manual()
  sx = sx or (geom.x + geom.w / 2)
  sy = sy or (geom.y + geom.h / 2)
  local cellX = view.x0 + (sx - geom.x) / view.s
  local cellY = view.y0 + (sy - geom.y) / view.s
  view.s = math.max(MIN_S, math.min(MAX_S, view.s * factor))
  view.x0 = cellX - (sx - geom.x) / view.s
  view.y0 = cellY - (sy - geom.y) / view.s
end

-- Moves the view by pixels on the screen
function surveymap.pan(dx, dy)
  manual()
  view.x0 = view.x0 - dx / view.s
  view.y0 = view.y0 - dy / view.s
end

-- Back to the fitted view
function surveymap.fit()
  view = { auto = true }
end

function surveymap.inBox(sx, sy)
  return sx >= geom.x and sy >= geom.y and sx < geom.x + geom.w and sy < geom.y + geom.h
end

-- The world point under a screen point of the map
local function toWorld(sx, sy)
  local cellX = geom.cx0 + (sx - geom.x) / geom.s
  local cellY = geom.cy0 + (sy - geom.y) / geom.s
  return world.left + cellX * CELL, world.top + cellY * CELL
end

-- A point of interest where the mouse clicked
function surveymap.addMarker(sx, sy)
  if not world or not surveymap.inBox(sx, sy) then
    return false
  end
  local wx, wy = toWorld(sx, sy)
  markers[#markers + 1] = { x = wx, y = wy }
  return true
end

-- Takes down the mark under a screen point (within a few pixels). Returns true if there was one.
function surveymap.removeMarkerAt(sx, sy, reach)
  reach = reach or 12
  for i = #markers, 1, -1 do
    local m = markers[i]
    local mx = geom.x + ((m.x - world.left) / CELL - geom.cx0) * geom.s
    local my = geom.y + ((m.y - world.top) / CELL - geom.cy0) * geom.s
    if math.abs(mx - sx) <= reach and math.abs(my - sy) <= reach then
      table.remove(markers, i)
      return true
    end
  end
  return false
end

function surveymap.markerCount()
  return #markers
end

return surveymap
