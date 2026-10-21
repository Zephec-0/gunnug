-- Drawing that never changes, drawn once into a canvas and then put on screen as one image: a slab of rock
-- that was a row of rectangles every frame, the mine's timbers and rails, the shapes of the item bar's slots.
-- Each use has a switch (bake.enabled), also in the dev panel (F2), so any of them can be turned off to get the
-- plain drawing back; a switched-off one never touches a canvas.
local bake = {}

bake.enabled = {
  slabs = true, -- the platforms' rock slabs (src.scenes.catacombs)
  minedecor = true, -- the old mine's rails, supports, skeletons and pickaxes (src.minedecor)
  itembar = true, -- the rounded boxes of the item bar's slots (src.itembar)
}

local function render(w, h, x0, y0, fn)
  local cv = love.graphics.newCanvas(w, h)
  cv:setFilter("nearest", "nearest")
  love.graphics.push("all")
  love.graphics.setCanvas(cv)
  love.graphics.setScissor()
  love.graphics.setShader()
  love.graphics.origin()
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.translate(-x0, -y0)
  fn()
  love.graphics.pop()
  return cv
end

-- Puts a baked canvas on screen at (x, y). (Baked with ordinary alpha blending, so it is drawn premultiplied.)
function bake.blit(cv, x, y)
  local mode, alphamode = love.graphics.getBlendMode()
  local r, g, b, a = love.graphics.getColor()
  love.graphics.setBlendMode("alpha", "premultiplied")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(cv, x, y)
  love.graphics.setBlendMode(mode, alphamode)
  love.graphics.setColor(r, g, b, a)
end

-- A piece of the scenery that does not change while `ver` stays the same: owner is the thing it belongs to (a
-- table), idx which piece of it, (x0, y0, w, h) the box it fills in world pixels, fn() draws it in world
-- coordinates. Drawn from its canvas, made the first time it is wanted.
local pieces = setmetatable({}, { __mode = "k" })
function bake.piece(owner, idx, ver, x0, y0, w, h, fn)
  local list = pieces[owner]
  if not list then
    list = {}
    pieces[owner] = list
  end
  local e = list[idx]
  if not e or e.ver ~= ver or e.w ~= w or e.h ~= h then
    e = { ver = ver, w = w, h = h, canvas = render(w, h, x0, y0, fn) }
    list[idx] = e
  end
  bake.blit(e.canvas, x0, y0)
end

-- A shape looked up by a key (the same shape is wanted again and again, at different places): the canvas, made
-- by drawing fn() with its top left at (0, 0). Once too many are held they are all let go.
local shapes, nShapes = {}, 0
function bake.shape(key, w, h, fn)
  local cv = shapes[key]
  if not cv then
    if nShapes >= 400 then
      shapes, nShapes = {}, 0
    end
    cv = render(w, h, 0, 0, fn)
    shapes[key] = cv
    nShapes = nShapes + 1
  end
  return cv
end

function bake.clear()
  pieces = setmetatable({}, { __mode = "k" })
  shapes, nShapes = {}, 0
end

return bake
