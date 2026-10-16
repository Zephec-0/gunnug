-- Box2D world (love.physics) plus collision outlines traced from the pixel
-- terrain. Outlines are built per chunk so destroying terrain only needs the
-- touched chunks rebuilt (physics.rebuildRegion). The world is large, so
-- chunks are only traced when a moving object comes near them
-- (physics.update); untouched terrain never needs outlines.
local config = require("src.config")

local physics = {}

local CHUNK = config.physics.chunkSize

local terrain -- src.world instance the outlines are traced from
local bodies, cullTimer = {}, 0 -- (see physics.update)
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
-- Tracing is done often (every blast re-traces the chunks it touched), so
-- it works in tables kept from one trace to the next, and reads each pixel
-- once (two rows of samples) rather than four times. Every outline point has
-- at most two links (one per square it is shared by), kept as linkA/linkB.
local ptX, ptY, linkA, linkB, visited = {}, {}, {}, {}, {}
local rowTop, rowBottom = {}, {}

local function addLink(k, other)
  if linkA[k] == nil then
    linkA[k] = other
  else
    linkB[k] = other
  end
end

local function traceChunk(cx, cy)
  local x0, y0 = math.max(cx * CHUNK, terrain.left), math.max(cy * CHUNK, terrain.top)
  local x1 = math.min(cx * CHUNK + CHUNK, terrain.right) - 1
  local y1 = math.min(cy * CHUNK + CHUNK, terrain.bottom) - 1

  for k in pairs(ptX) do
    ptX[k], ptY[k], linkA[k], linkB[k], visited[k] = nil, nil, nil, nil, nil
  end
  local isSolid = terrain.isSolid
  local top, bottom = rowTop, rowBottom
  for x = x0, x1 + 1 do
    top[x - x0] = isSolid(terrain, x, y0)
  end
  for y = y0, y1 do
    for x = x0, x1 + 1 do
      bottom[x - x0] = isSolid(terrain, x, y + 1)
    end
    for x = x0, x1 do
      local i = x - x0
      local case = (top[i] and 8 or 0) + (top[i + 1] and 4 or 0) + (bottom[i + 1] and 2 or 0) + (bottom[i] and 1 or 0)
      local segs = CASES[case]
      if segs then
        for _, seg in ipairs(segs) do
          local ax, ay = edgePoint(x, y, seg[1])
          local bx, by = edgePoint(x, y, seg[2])
          local ka, kb = pointKey(ax, ay), pointKey(bx, by)
          ptX[ka], ptY[ka] = ax, ay
          ptX[kb], ptY[kb] = bx, by
          addLink(ka, kb)
          addLink(kb, ka)
        end
      end
    end
    top, bottom = bottom, top
  end

  -- Walk the links into polylines: open chains first (they start at a point
  -- with a single link, on the chunk border), then closed loops.
  local polylines = {}
  local function walk(start)
    local coords, loop = {}, false
    local prev, cur = nil, start
    while cur do
      visited[cur] = true
      coords[#coords + 1] = ptX[cur] / 2
      coords[#coords + 1] = ptY[cur] / 2
      local a, b = linkA[cur], linkB[cur]
      local nextKey
      if a and a ~= prev and not visited[a] then
        nextKey = a
      elseif b and b ~= prev and not visited[b] then
        nextKey = b
      end
      if not nextKey and (a == start or b == start) and prev ~= nil and #coords > 4 then
        loop = true
      end
      prev, cur = cur, nextKey
    end
    polylines[#polylines + 1] = { coords = coords, loop = loop }
  end
  for key in pairs(linkA) do
    if linkB[key] == nil and not visited[key] then
      walk(key)
    end
  end
  for key in pairs(linkA) do
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
  pendingChunks, pendingWake = {}, {}
  bodies, cullTimer = {}, 0
end

-- Traces any not-yet-traced chunks overlapping the pixel rectangle
local function ensureChunks(x0, y0, x1, y1)
  local minX, minY = math.floor(terrain.left / CHUNK), math.floor(terrain.top / CHUNK)
  local maxX, maxY = math.floor((terrain.right - 1) / CHUNK), math.floor((terrain.bottom - 1) / CHUNK)
  for cy = math.max(minY, math.floor(y0 / CHUNK)), math.min(maxY, math.floor(y1 / CHUNK)) do
    for cx = math.max(minX, math.floor(x0 / CHUNK)), math.min(maxX, math.floor(x1 / CHUNK)) do
      if chunks[chunkKey(cx, cy)] == nil then
        rebuildChunk(cx, cy)
      end
    end
  end
end

-- Re-traces the already-traced chunks touching the pixel rectangle (for
-- destructible terrain); untraced ones pick up the change when first traced.
-- The work is queued and done once per frame, just before the physics step
-- (physics.flush): a volley of explosive rounds digs the same chunks many
-- times over in one frame, and tracing a chunk is the dearest part of a blast.
local pendingChunks = {} -- chunk key -> { cx, cy }
local pendingWake = {} -- { x0, y0, x1, y1 } boxes whose sleeping objects must wake

function physics.rebuildRegion(x0, y0, x1, y1)
  -- Squares reach one pixel left/up into neighbouring chunks
  for cy = math.floor((y0 - 1) / CHUNK), math.floor(y1 / CHUNK) do
    for cx = math.floor((x0 - 1) / CHUNK), math.floor(x1 / CHUNK) do
      local key = chunkKey(cx, cy)
      if chunks[key] ~= nil and not pendingChunks[key] then
        pendingChunks[key] = { cx, cy }
      end
    end
  end
  pendingWake[#pendingWake + 1] = { x0, y0, x1, y1 }
end

-- Does the queued rebuilds and wakes the sleeping objects near them
function physics.flush()
  if #pendingWake == 0 then
    return
  end
  for key, c in pairs(pendingChunks) do
    if chunks[key] ~= nil then
      rebuildChunk(c[1], c[2])
    end
  end
  pendingChunks = {}
  -- Wake nearby sleeping objects so they notice terrain vanishing beneath them
  -- (from the list physics.update keeps: one new from Box2D for every blast
  -- was a big table of every body each time; anything newer is awake anyway)
  local m = REACH
  for _, body in ipairs(bodies) do
    if not body:isDestroyed() and body:getType() == "dynamic" and not body:isAwake() then
      local x, y = body:getPosition()
      for _, r in ipairs(pendingWake) do
        if x > r[1] - m and x < r[3] + m and y > r[2] - m and y < r[4] + m then
          body:setAwake(true)
          break
        end
      end
    end
  end
  pendingWake = {}
end

-- Every moving object gets outlines traced around it before stepping
-- Objects far from the hunter are taken out of the simulation (setActive
-- false) and put back as he comes near: a crate knocked loose in an area he
-- left kept being simulated, and the terrain outlines around it kept being
-- traced, all over the world (30-50 ms frames). Only objects near him get
-- outlines traced. The list of bodies is refreshed a few times a second
-- (asking Box2D for it every frame made a new table each time).
local FAR_X, FAR_Y = 900, 700

function physics.update(dt, px, py)
  physics.flush()
  cullTimer = cullTimer - dt
  if cullTimer <= 0 or not px then
    cullTimer = 0.2
    bodies = physics.world:getBodies()
    if px then
      for _, body in ipairs(bodies) do
        if body:getType() == "dynamic" then
          local x, y = body:getPosition()
          local near = math.abs(x - px) < FAR_X and math.abs(y - py) < FAR_Y
          if near ~= body:isActive() then
            body:setActive(near)
          end
        end
      end
    end
  end
  for _, body in ipairs(bodies) do
    if not body:isDestroyed() and body:getType() == "dynamic" and body:isActive() and body:isAwake() then
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
