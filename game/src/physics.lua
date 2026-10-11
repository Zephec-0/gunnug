-- Box2D world (love.physics) plus collision outlines traced from the pixel
-- terrain. Outlines are built per chunk so destroying terrain only needs the
-- touched chunks rebuilt (physics.rebuildRegion). The world is large, so
-- chunks are only traced when a moving object comes near them
-- (physics.update); untouched terrain never needs outlines.
local config = require("src.config")

local physics = {}

local CHUNK = config.physics.chunkSize

local terrain -- src.world instance the outlines are traced from
local chunks = {} -- chunk key -> static body with that chunk's outlines, or false if traced and empty

-- Marching squares. Corners: a = top-left, b = top-right, c = bottom-right,
-- d = bottom-left; case = a*8 + b*4 + c*2 + d. Edges: 1 top, 2 right,
-- 3 bottom, 4 left. Each entry lists the segments (edge pairs) for that case.
local CASES = {
  [1] = { { 4, 3 } },
  [2] = { { 3, 2 } },
  [3] = { { 4, 2 } },
  [4] = { { 1, 2 } },
  [5] = { { 1, 2 }, { 4, 3 } },
  [6] = { { 1, 3 } },
  [7] = { { 1, 4 } },
  [8] = { { 1, 4 } },
  [9] = { { 1, 3 } },
  [10] = { { 1, 4 }, { 3, 2 } },
  [11] = { { 1, 2 } },
  [12] = { { 4, 2 } },
  [13] = { { 3, 2 } },
  [14] = { { 4, 3 } },
}

-- Edge midpoints in half-pixel units (so they stay integers), for the square
-- whose top-left sample is pixel (x, y). Samples sit at pixel centres.
local function edgePoint(x, y, edge)
  if edge == 1 then
    return 2 * x + 2, 2 * y + 1
  elseif edge == 2 then
    return 2 * x + 3, 2 * y + 2
  elseif edge == 3 then
    return 2 * x + 2, 2 * y + 3
  end
  return 2 * x + 1, 2 * y + 2
end

local function pointKey(hx, hy)
  return hx * 1048576 + hy
end

-- Ramer–Douglas–Peucker line simplification on a flat {x1, y1, x2, y2, ...} list
local function simplify(pts, epsilon)
  local n = #pts / 2
  if n < 3 then
    return pts
  end
  local keep = { [1] = true, [n] = true }
  local function recurse(i, j)
    local x1, y1 = pts[2 * i - 1], pts[2 * i]
    local x2, y2 = pts[2 * j - 1], pts[2 * j]
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    local best, bestDist = nil, epsilon
    for k = i + 1, j - 1 do
      local px, py = pts[2 * k - 1], pts[2 * k]
      local dist
      if len == 0 then
        dist = math.sqrt((px - x1) ^ 2 + (py - y1) ^ 2)
      else
        dist = math.abs(dy * px - dx * py + x2 * y1 - y2 * x1) / len
      end
      if dist > bestDist then
        best, bestDist = k, dist
      end
    end
    if best then
      keep[best] = true
      recurse(i, best)
      recurse(best, j)
    end
  end
  recurse(1, n)
  local out = {}
  for k = 1, n do
    if keep[k] then
      out[#out + 1] = pts[2 * k - 1]
      out[#out + 1] = pts[2 * k]
    end
  end
  return out
end

-- Traces the terrain inside one chunk into polylines (in pixel coordinates).
local function traceChunk(cx, cy)
  local x0, y0 = cx * CHUNK, cy * CHUNK
  local x1 = math.min(x0 + CHUNK, terrain.width) - 1
  local y1 = math.min(y0 + CHUNK, terrain.height) - 1

  local points = {} -- key -> { hx, hy }
  local links = {} -- key -> list of linked keys
  local function link(k1, k2)
    links[k1] = links[k1] or {}
    links[k2] = links[k2] or {}
    table.insert(links[k1], k2)
    table.insert(links[k2], k1)
  end

  for y = y0, y1 do
    for x = x0, x1 do
      local case = (terrain:isSolid(x, y) and 8 or 0)
        + (terrain:isSolid(x + 1, y) and 4 or 0)
        + (terrain:isSolid(x + 1, y + 1) and 2 or 0)
        + (terrain:isSolid(x, y + 1) and 1 or 0)
      local segs = CASES[case]
      if segs then
        for _, seg in ipairs(segs) do
          local ax, ay = edgePoint(x, y, seg[1])
          local bx, by = edgePoint(x, y, seg[2])
          local ka, kb = pointKey(ax, ay), pointKey(bx, by)
          points[ka] = points[ka] or { ax, ay }
          points[kb] = points[kb] or { bx, by }
          link(ka, kb)
        end
      end
    end
  end

  -- Walk the links into polylines: open chains first (they start at a point
  -- with a single link, on the chunk border), then closed loops.
  local visited = {}
  local polylines = {}
  local function walk(start)
    local coords, loop = {}, false
    local prev, cur = nil, start
    while cur do
      visited[cur] = true
      local p = points[cur]
      coords[#coords + 1] = p[1] / 2
      coords[#coords + 1] = p[2] / 2
      local nextKey
      for _, k in ipairs(links[cur]) do
        if k ~= prev and not visited[k] then
          nextKey = k
          break
        end
      end
      if not nextKey then
        for _, k in ipairs(links[cur]) do
          if k == start and prev ~= nil and #coords > 4 then
            loop = true
          end
        end
      end
      prev, cur = cur, nextKey
    end
    polylines[#polylines + 1] = { coords = coords, loop = loop }
  end
  for key, l in pairs(links) do
    if #l == 1 and not visited[key] then
      walk(key)
    end
  end
  for key in pairs(links) do
    if not visited[key] then
      walk(key)
    end
  end
  return polylines
end

-- Margin around an object: its size plus more than it moves in a step
local REACH = CHUNK * 1.5

local function chunkKey(cx, cy)
  return cy * 65536 + cx
end

local function rebuildChunk(cx, cy)
  local key = chunkKey(cx, cy)
  if chunks[key] then
    chunks[key]:destroy()
    chunks[key] = nil
  end

  local polylines = traceChunk(cx, cy)
  if #polylines == 0 then
    chunks[key] = false
    return
  end
  local body = love.physics.newBody(physics.world, 0, 0, "static")
  for _, poly in ipairs(polylines) do
    local coords = poly.coords
    if poly.loop then
      -- Close the loop for simplification, then drop the duplicate end point
      coords[#coords + 1] = coords[1]
      coords[#coords + 1] = coords[2]
      coords = simplify(coords, config.physics.simplify)
      coords[#coords] = nil
      coords[#coords] = nil
    else
      coords = simplify(coords, config.physics.simplify)
    end
    local count = #coords / 2
    if (poly.loop and count >= 3) or (not poly.loop and count >= 2) then
      local fixture = love.physics.newFixture(body, love.physics.newChainShape(poly.loop, coords))
      fixture:setFriction(0.8)
    end
  end
  chunks[key] = body
end

-- Creates a fresh physics world for the given terrain. Chunks are traced on
-- demand (see ensureChunks).
function physics.init(world)
  if physics.world then
    physics.world:destroy()
  end
  love.physics.setMeter(config.physics.meter)
  physics.world = love.physics.newWorld(0, config.gravity, true)
  terrain = world
  chunks = {}
end

-- Traces any not-yet-traced chunks overlapping the pixel rectangle
local function ensureChunks(x0, y0, x1, y1)
  local maxX = math.ceil(terrain.width / CHUNK) - 1
  local maxY = math.ceil(terrain.height / CHUNK) - 1
  for cy = math.max(0, math.floor(y0 / CHUNK)), math.min(maxY, math.floor(y1 / CHUNK)) do
    for cx = math.max(0, math.floor(x0 / CHUNK)), math.min(maxX, math.floor(x1 / CHUNK)) do
      if chunks[chunkKey(cx, cy)] == nil then
        rebuildChunk(cx, cy)
      end
    end
  end
end

-- Re-traces the already-traced chunks touching the pixel rectangle (for
-- destructible terrain); untraced ones pick up the change when first traced.
function physics.rebuildRegion(x0, y0, x1, y1)
  -- Squares reach one pixel left/up into neighbouring chunks
  for cy = math.floor((y0 - 1) / CHUNK), math.floor(y1 / CHUNK) do
    for cx = math.floor((x0 - 1) / CHUNK), math.floor(x1 / CHUNK) do
      if cx >= 0 and cy >= 0 and chunks[chunkKey(cx, cy)] ~= nil then
        rebuildChunk(cx, cy)
      end
    end
  end
  -- Wake nearby sleeping objects so they notice terrain vanishing beneath them
  local m = REACH
  for _, body in ipairs(physics.world:getBodies()) do
    if body:getType() == "dynamic" and not body:isAwake() then
      local x, y = body:getPosition()
      if x > x0 - m and x < x1 + m and y > y0 - m and y < y1 + m then
        body:setAwake(true)
      end
    end
  end
end

-- Every moving object gets outlines traced around it before stepping
function physics.update(dt)
  for _, body in ipairs(physics.world:getBodies()) do
    if body:getType() == "dynamic" and body:isAwake() then
      local x, y = body:getPosition()
      ensureChunks(x - REACH, y - REACH, x + REACH, y + REACH)
    end
  end
  physics.world:update(dt)
end

-- Collision outlines, for the F2 debug view
function physics.drawDebug()
  love.graphics.setLineWidth(1)
  for _, body in ipairs(physics.world:getBodies()) do
    local kind = body:getType()
    if kind == "static" then
      love.graphics.setColor(0.2, 1, 0.4, 0.9)
    elseif kind == "kinematic" then
      love.graphics.setColor(0.3, 0.7, 1, 0.9)
    else
      love.graphics.setColor(1, 0.3, 0.8, body:isAwake() and 0.9 or 0.4)
    end
    for _, fixture in ipairs(body:getFixtures()) do
      local shape = fixture:getShape()
      local shapeType = shape:getType()
      if shapeType == "chain" then
        love.graphics.line(body:getWorldPoints(shape:getPoints()))
      elseif shapeType == "polygon" then
        love.graphics.polygon("line", body:getWorldPoints(shape:getPoints()))
      end
    end
  end
end

return physics
