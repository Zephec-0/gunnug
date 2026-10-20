-- A batch of plain coloured rectangles, written straight into a vertex buffer
-- (LuaJIT's FFI) and drawn with one mesh draw. The pictures made of hundreds
-- or thousands of little rectangles a frame (the far scenery's seaweed and
-- swell, the fluids' cells) spent most of their time in the calls themselves:
-- a setColor and a rectangle each. Here a rectangle is a few stores.
--
-- quads.rect(r, g, b, a, x, y, w, h) adds one (in the current coordinates,
-- the transform applies when the batch is drawn); quads.flush() draws what
-- has been added. Anything else drawn in between must be preceded by a flush
-- so the order stays right. Colours are kept as bytes, as LÖVE keeps them for
-- its own rectangles. Without the FFI it falls back to plain rectangles.
local quads = {}

local ok, ffi = pcall(require, "ffi")
-- Rectangles per draw (4 vertices each). Kept small: Mesh:setVertices copies the whole buffer it is
-- given, however few vertices are asked for, so a big one cost a third of a millisecond every flush.
local MAX = 1024

local mesh, data, fpos, bcol -- (the vertex buffer seen as floats and as bytes: 12 bytes a vertex, x y then r g b a)
local n = 0

local function init()
  local format = { { "VertexPosition", "float", 2 }, { "VertexColor", "byte", 4 } }
  mesh = love.graphics.newMesh(format, MAX * 4, "triangles", "stream")
  local map = love.data.newByteData(MAX * 6 * 2)
  local idx = ffi.cast("uint16_t*", map:getFFIPointer())
  for q = 0, MAX - 1 do
    local v, k = q * 4, q * 6
    idx[k], idx[k + 1], idx[k + 2] = v + 1, v + 2, v + 3
    idx[k + 3], idx[k + 4], idx[k + 5] = v + 1, v + 3, v + 4
  end
  -- (the vertex map is 1-based in the table form; in the Data form it is 0-based)
  for i = 0, MAX * 6 - 1 do
    idx[i] = idx[i] - 1
  end
  mesh:setVertexMap(map, "uint16")
  data = love.data.newByteData(MAX * 4 * 12)
  fpos = ffi.cast("float*", data:getFFIPointer())
  bcol = ffi.cast("uint8_t*", data:getFFIPointer())
end

local floor = math.floor
local function byte(v)
  v = v * 255 + 0.5
  if v < 0 then
    return 0
  elseif v > 255 then
    return 255
  end
  return v - v % 1
end

function quads.flush()
  if n == 0 then
    return
  end
  mesh:setVertices(data, 1, n * 4)
  mesh:setDrawRange(1, n * 6)
  local r, g, b, a = love.graphics.getColor()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(mesh)
  love.graphics.setColor(r, g, b, a)
  n = 0
end

if ok then
  function quads.rect(r, g, b, a, x, y, w, h)
    if not mesh then
      init()
    end
    if n >= MAX then
      quads.flush()
    end
    local cr, cg, cb, ca = byte(r), byte(g), byte(b), byte(a or 1)
    -- (plain number indices into the float and byte views: no cdata made, even when not compiled)
    local f = n * 12 -- 4 vertices x 3 floats
    local x1, y1 = x + w, y + h
    fpos[f], fpos[f + 1] = x, y
    fpos[f + 3], fpos[f + 4] = x1, y
    fpos[f + 6], fpos[f + 7] = x1, y1
    fpos[f + 9], fpos[f + 10] = x, y1
    local c = n * 48 + 8
    for i = 0, 36, 12 do
      bcol[c + i], bcol[c + i + 1], bcol[c + i + 2], bcol[c + i + 3] = cr, cg, cb, ca
    end
    n = n + 1
  end
else
  function quads.rect(r, g, b, a, x, y, w, h)
    love.graphics.setColor(r, g, b, a or 1)
    love.graphics.rectangle("fill", x, y, w, h)
  end
end

quads.floor = floor
return quads
