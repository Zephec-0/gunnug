-- Composes one frame of the document onto a canvas of the document's size.
-- Canvases hold premultiplied colour: draw them with the "premultiplied" blend mode.
local doc = require("src.doc")
local rig = require("src.rig")

local R = {}
local tr = love.math.newTransform()

function R.newCanvas(w, h)
  local c = love.graphics.newCanvas(w, h)
  c:setFilter("nearest", "nearest")
  return c
end

-- o: rest (ignore pose keys), skipRef (leave reference layers out), float (a floating selection
-- {layerId, frame, img, x, y} drawn just above its layer), only (set of layer ids to draw)
function R.compose(D, f, canvas, o)
  o = o or {}
  local P = rig.pose(D, f, o.rest)
  local lg = love.graphics
  lg.push("all")
  lg.setCanvas(canvas)
  lg.origin()
  lg.setScissor()
  lg.clear(0, 0, 0, 0)
  lg.setBlendMode("alpha", "alphamultiply")
  for _, L in ipairs(D.layers) do
    if L.visible and not (o.skipRef and L.kind == "ref") and (not o.only or o.only[L.id]) then
      local pb = L.bone and P[L.bone]
      if pb then
        local m = pb.m
        tr:setMatrix("row", m[1], m[2], 0, m[5], m[3], m[4], 0, m[6], 0, 0, 1, 0, 0, 0, 0, 1)
      end
      local function draw(img, x, y)
        if pb then
          lg.push()
          lg.applyTransform(tr)
          lg.draw(img, x, y)
          lg.pop()
        else
          lg.draw(img, x, y)
        end
      end
      lg.setColor(1, 1, 1, L.opacity)
      local cel = doc.cel(D, L, f)
      if cel then
        if L.kind == "ref" then draw(doc.image(cel), L.ox or 0, L.oy or 0) else draw(doc.image(cel), 0, 0) end
      end
      local F = o.float
      if F and F.layerId == L.id and F.frame == f then draw(F.img, F.x, F.y) end
    end
  end
  lg.pop()
  return P
end

-- Pixel data of a composed frame with the premultiplication undone (for export and picking)
function R.frameData(D, f, canvas, o)
  R.compose(D, f, canvas, o)
  local d = canvas:newImageData()
  d:mapPixel(function(_, _, r, g, b, a)
    if a > 0 and a < 1 then return r / a, g / a, b / a, a end
    return r, g, b, a
  end)
  return d
end

return R
