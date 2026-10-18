-- The sprite document: a canvas size, a list of frames, layers holding one cel (pixel image) per
-- frame, a skeleton of bones with per-frame pose keys, and named frame ranges (tags).
--
-- Layer kinds:
--   frames  one cel per frame (classic frame-by-frame pixel animation); a frame may have no cel
--   part    a single cel shared by every frame: a puppet piece, usually bound to a bone
--   ref     a reference image (e.g. the in-game character) drawn faded; never exported
--
-- Cel and key arrays are dense: index f is the frame, `false` means "nothing here".
local U = require("src.util")

local doc = {}

function doc.newCel(w, h, data)
  return { data = data or love.image.newImageData(w, h), dirty = true }
end

-- Call after changing a cel's pixels
function doc.touch(cel)
  cel.dirty = true
  cel.str = nil
end

-- Swap in new image data (for example a different size)
function doc.setData(cel, data)
  cel.data = data
  if cel.img then cel.img:release() end
  cel.img = nil
  doc.touch(cel)
end

-- GPU image of a cel, refreshed lazily after edits
function doc.image(cel)
  if not cel.img then
    cel.img = love.graphics.newImage(cel.data)
    cel.img:setFilter("nearest", "nearest")
    cel.dirty = false
  elseif cel.dirty then
    cel.img:replacePixels(cel.data)
    cel.dirty = false
  end
  return cel.img
end

-- The raw pixel string, cached so unchanged cels share memory across undo snapshots
function doc.str(cel)
  if not cel.str then cel.str = cel.data:getString() end
  return cel.str
end

function doc.copyCel(c)
  return doc.newCel(nil, nil, c.data:clone())
end

function doc.isEmpty(cel)
  local d = cel.data
  local w, h = d:getDimensions()
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local _, _, _, a = d:getPixel(x, y)
      if a > 0 then return false end
    end
  end
  return true
end

function doc.id(D)
  local i = D.nextId
  D.nextId = i + 1
  return i
end

function doc.new(w, h, opts)
  opts = opts or {}
  local D = {
    w = w, h = h,
    name = opts.name or "untitled",
    frames = { { dur = 100 } },
    layers = {}, bones = {}, tags = {},
    palette = U.copy(opts.palette or {}),
    guide = opts.guide and U.copy(opts.guide),
    preset = opts.preset,
    nextId = 1,
  }
  if not opts.noLayer then doc.addLayer(D, "Layer 1") end
  return D
end

function doc.addLayer(D, name, kind, at)
  local L = {
    id = doc.id(D), name = name or ("Layer " .. (#D.layers + 1)), kind = kind or "frames",
    visible = true, opacity = 1, locked = false, cels = {},
  }
  for i = 1, #D.frames do L.cels[i] = false end
  if L.kind ~= "frames" then L.part = doc.newCel(D.w, D.h) end
  if L.kind == "ref" then L.ox, L.oy, L.opacity = 0, 0, 0.4 end
  table.insert(D.layers, at or (#D.layers + 1), L)
  return L
end

function doc.layerById(D, id)
  for i, L in ipairs(D.layers) do
    if L.id == id then return L, i end
  end
end

-- The cel a layer shows on frame f (creating an empty one if asked)
function doc.cel(D, L, f, create)
  if L.kind ~= "frames" then return L.part end
  local c = L.cels[f]
  if not c and create then
    c = doc.newCel(D.w, D.h)
    L.cels[f] = c
  end
  return c or nil
end

-- Frames -------------------------------------------------------------------------------------------

-- Inserts a frame at index `at`; `dup` copies the frame before it
function doc.insertFrame(D, at, dup)
  local src = at - 1
  local base = D.frames[src] or D.frames[at] or { dur = 100 }
  table.insert(D.frames, at, { dur = base.dur })
  for _, L in ipairs(D.layers) do
    local c = false
    if dup and L.cels[src] then c = doc.copyCel(L.cels[src]) end
    table.insert(L.cels, at, c)
  end
  for _, B in ipairs(D.bones) do
    local k = false
    if dup and B.keys[src] then k = U.copy(B.keys[src]) end
    table.insert(B.keys, at, k)
  end
  for _, T in ipairs(D.tags) do
    if T.from >= at then T.from = T.from + 1 end
    if T.to >= at or (dup and T.to == src) then T.to = T.to + 1 end
  end
end

function doc.deleteFrame(D, i)
  if #D.frames <= 1 then return false end
  table.remove(D.frames, i)
  for _, L in ipairs(D.layers) do table.remove(L.cels, i) end
  for _, B in ipairs(D.bones) do table.remove(B.keys, i) end
  for k = #D.tags, 1, -1 do
    local T = D.tags[k]
    if T.from > i then T.from = T.from - 1 end
    if T.to >= i then T.to = T.to - 1 end
    if T.to < T.from then table.remove(D.tags, k) end
  end
  return true
end

function doc.swapFrames(D, i, j)
  if not D.frames[i] or not D.frames[j] then return false end
  D.frames[i], D.frames[j] = D.frames[j], D.frames[i]
  for _, L in ipairs(D.layers) do L.cels[i], L.cels[j] = L.cels[j], L.cels[i] end
  for _, B in ipairs(D.bones) do B.keys[i], B.keys[j] = B.keys[j], B.keys[i] end
  return true
end

-- Canvas size --------------------------------------------------------------------------------------

-- Resizes the canvas; (ax, ay) is the anchor in 0..1 (0.5, 1 keeps the feet where they are)
function doc.resize(D, nw, nh, ax, ay)
  local dx, dy = U.round((nw - D.w) * ax), U.round((nh - D.h) * ay)
  local ow, oh = D.w, D.h
  local function move(c)
    local nd = love.image.newImageData(nw, nh)
    nd:paste(c.data, dx, dy, 0, 0, ow, oh)
    doc.setData(c, nd)
  end
  for _, L in ipairs(D.layers) do
    if L.kind == "ref" then
      L.ox, L.oy = (L.ox or 0) + dx, (L.oy or 0) + dy
    else
      for f = 1, #D.frames do
        if L.cels[f] then move(L.cels[f]) end
      end
      if L.part then move(L.part) end
    end
  end
  for _, B in ipairs(D.bones) do
    B.x, B.y = B.x + dx, B.y + dy
  end
  if D.guide then
    D.guide.fx, D.guide.fy = D.guide.fx + dx, D.guide.fy + dy
  end
  D.w, D.h = nw, nh
end

-- Serialisation ------------------------------------------------------------------------------------

-- `encode` compresses and base64s pixel data for files; undo snapshots keep the raw strings
local function pack(s, encode)
  if not encode then return s end
  return love.data.encode("string", "base64", love.data.compress("string", "zlib", s, 9))
end

local function unpack(s, encoded)
  if not encoded then return s end
  return love.data.decompress("string", "zlib", love.data.decode("string", "base64", s))
end

function doc.toTable(D, encode)
  local t = {
    version = 1, w = D.w, h = D.h, name = D.name, preset = D.preset, nextId = D.nextId,
    frames = U.copy(D.frames), tags = U.copy(D.tags), palette = U.copy(D.palette),
    guide = D.guide and U.copy(D.guide), bones = U.copy(D.bones), layers = {},
  }
  for i, L in ipairs(D.layers) do
    local l = {
      id = L.id, name = L.name, kind = L.kind, visible = L.visible, opacity = L.opacity,
      locked = L.locked, bone = L.bone, ox = L.ox, oy = L.oy, cels = {},
    }
    for f = 1, #D.frames do
      local c = L.cels[f]
      l.cels[f] = c and pack(doc.str(c), encode) or false
    end
    if L.part then
      l.part = pack(doc.str(L.part), encode)
      l.pw, l.ph = L.part.data:getDimensions()
    end
    t.layers[i] = l
  end
  return t
end

function doc.fromTable(t, encoded)
  local D = {
    w = t.w, h = t.h, name = t.name or "untitled", preset = t.preset, nextId = t.nextId or 1,
    frames = U.copy(t.frames), tags = U.copy(t.tags or {}), palette = U.copy(t.palette or {}),
    guide = t.guide and U.copy(t.guide), bones = U.copy(t.bones or {}), layers = {},
  }
  local nf = #D.frames
  for _, B in ipairs(D.bones) do
    B.keys = B.keys or {}
    for f = 1, nf do
      if B.keys[f] == nil then B.keys[f] = false end
    end
  end
  local function cel(s, w, h)
    local raw = unpack(s, encoded)
    local c = doc.newCel(nil, nil, love.image.newImageData(w, h, "rgba8", raw))
    c.str = raw
    return c
  end
  for i, l in ipairs(t.layers) do
    local L = {
      id = l.id, name = l.name, kind = l.kind or "frames", visible = l.visible ~= false,
      opacity = l.opacity or 1, locked = l.locked or false, bone = l.bone, ox = l.ox, oy = l.oy, cels = {},
    }
    for f = 1, nf do
      local s = l.cels and l.cels[f]
      L.cels[f] = s and cel(s, D.w, D.h) or false
    end
    if l.part then L.part = cel(l.part, l.pw or D.w, l.ph or D.h) end
    D.layers[i] = L
  end
  return D
end

return doc
