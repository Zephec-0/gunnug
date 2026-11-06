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

-- Convex polygons (the far scenery's crystals and mounds): each a fan of triangles, written the same way into a
-- second buffer, so a polygon is a few stores instead of a setColor and a draw call. Only one of the two
-- buffers ever holds anything: adding to one first draws the other, so the order of drawing holds.
local TRI_MAX = 1024 -- triangles per draw
local tmesh, tdata, tfpos, tbcol
local nt = 0
local function flushTris()
  tmesh:setVertices(tdata, 1, nt * 3)
  tmesh:setDrawRange(1, nt * 3)
  local r, g, b, a = love.graphics.getColor()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(tmesh)
  love.graphics.setColor(r, g, b, a)
  nt = 0
end

local flushRects
function quads.flush()
  if nt > 0 then
    flushTris()
  end
  flushRects()
end

function flushRects()
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
    if nt > 0 then
      -- (while polygons are being gathered a rectangle joins them, as two triangles: switching back and forth
      -- would draw the batch each time)
      if nt + 2 > TRI_MAX then
        flushTris()
      end
      local cr, cg, cb, ca = byte(r), byte(g), byte(b), byte(a or 1)
      local x1, y1 = x + w, y + h
      local f = nt * 9
      tfpos[f], tfpos[f + 1] = x, y
      tfpos[f + 3], tfpos[f + 4] = x1, y
      tfpos[f + 6], tfpos[f + 7] = x1, y1
      tfpos[f + 9], tfpos[f + 10] = x, y
      tfpos[f + 12], tfpos[f + 13] = x1, y1
      tfpos[f + 15], tfpos[f + 16] = x, y1
      local c = nt * 36 + 8
      for i = 0, 60, 12 do
        tbcol[c + i], tbcol[c + i + 1], tbcol[c + i + 2], tbcol[c + i + 3] = cr, cg, cb, ca
      end
      nt = nt + 2
      return
    end
    if n >= MAX then
      flushRects()
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
  -- A convex polygon: pts = { x1, y1, x2, y2, ... } (count points), drawn in the colour given
  function quads.poly(r, g, b, a, pts, count)
    if not tmesh then
      local format = { { "VertexPosition", "float", 2 }, { "VertexColor", "byte", 4 } }
      tmesh = love.graphics.newMesh(format, TRI_MAX * 3, "triangles", "stream")
      tdata = love.data.newByteData(TRI_MAX * 3 * 12)
      tfpos = ffi.cast("float*", tdata:getFFIPointer())
      tbcol = ffi.cast("uint8_t*", tdata:getFFIPointer())
    end
    if n > 0 then
      flushRects()
    end
    local cr, cg, cb, ca = byte(r), byte(g), byte(b), byte(a or 1)
    local x1, y1 = pts[1], pts[2]
    for k = 2, count - 1 do
      if nt >= TRI_MAX then
        flushTris()
      end
      local f = nt * 9 -- 3 vertices x 3 floats
      tfpos[f], tfpos[f + 1] = x1, y1
      tfpos[f + 3], tfpos[f + 4] = pts[2 * k - 1], pts[2 * k]
      tfpos[f + 6], tfpos[f + 7] = pts[2 * k + 1], pts[2 * k + 2]
      local c = nt * 36 + 8
      for i = 0, 24, 12 do
        tbcol[c + i], tbcol[c + i + 1], tbcol[c + i + 2], tbcol[c + i + 3] = cr, cg, cb, ca
      end
      nt = nt + 1
    end
  end
else
  function quads.rect(r, g, b, a, x, y, w, h)
    love.graphics.setColor(r, g, b, a or 1)
    love.graphics.rectangle("fill", x, y, w, h)
  end
  function quads.poly(r, g, b, a, pts, count)
    love.graphics.setColor(r, g, b, a or 1)
    local t = {}
    for i = 1, count * 2 do
      t[i] = pts[i]
    end
    love.graphics.polygon("fill", t)
  end
end

quads.floor = floor
return quads
