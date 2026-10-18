-- Soft borders between the far backgrounds of neighbouring areas: instead of the
-- scenery changing in one hard line where one area ends and the next begins, the
-- next area's backdrop and parallax are drawn over the current one with a
-- feathered edge, so each bleeds into the other (design doc §2a). Also used for
-- the shop's void (see catacombs.drawVoidRect).
local config = require("src.config")
local catacombs = require("src.scenes.catacombs")
local parallax = require("src.parallax")

local depthblend = {}

local FEATHER = 120 -- px over which one background fades into the next

local SHADER = [[
uniform vec4 box;     // the area's rectangle in world pixels: x0, y0, x1, y1
uniform vec2 origin;  // the world position of the canvas's top-left
uniform vec2 size;    // the canvas's size
uniform float feather;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec2 w = origin + uv * size;
  float inside = min(min(w.x - box.x, box.z - w.x), min(w.y - box.y, box.w - w.y));
  float a = clamp((inside + feather * 0.5) / feather, 0.0, 1.0);
  a = a * a * (3.0 - 2.0 * a);
  return Texel(tex, uv) * color * a;
}
]]

local canvas, shader

local function ensure()
  local w, h = config.VIRTUAL_W, config.VIRTUAL_H
  if not canvas or canvas:getWidth() ~= w or canvas:getHeight() ~= h then
    canvas = love.graphics.newCanvas(w, h)
    canvas:setFilter("nearest", "nearest")
  end
  if shader == nil then
    local ok, sh = pcall(love.graphics.newShader, SHADER)
    shader = ok and sh or false
  end
end

-- One area's backdrop (stripes of its colour) and parallax scenery over x0..x1, y0..y1
local function layer(i, camX, camY, x0, y0, x1, y1)
  local th = catacombs.theme(i)
  for y = math.floor(y0 / 8) * 8, y1, 8 do
    love.graphics.setColor(catacombs.backdropIn(i, y))
    love.graphics.rectangle("fill", x0, y, x1 - x0, 8)
  end
  parallax.draw(th.parallax or i, camX, camY, x0, y0, x1, y1, th.pillars)
end
depthblend.layer = layer

-- Draws the backgrounds of area `primary` over the whole view, then every other
-- (ordinary) area the view reaches over it with feathered edges.
function depthblend.draw(primary, camX, camY, vx0, vy0, vx1, vy1, top)
  vy0 = math.max(vy0, top or vy0)
  layer(primary, camX, camY, vx0, vy0, vx1, vy1)
  ensure()
  if not shader then
    return
  end
  for i = 1, catacombs.count() do
    local th = catacombs.theme(i)
    local ax0, ay0, ax1, ay1 = catacombs.bounds(i)
    if i ~= primary and ax0 and not th.profile and not th.open then
      local half = FEATHER / 2
      local x0, y0, x1, y1 = math.max(ax0 - half, vx0), math.max(ay0 - half, vy0), math.min(ax1 + half, vx1), math.min(ay1 + half, vy1)
      if x1 > x0 and y1 > y0 then
        love.graphics.push("all")
        love.graphics.setCanvas(canvas)
        love.graphics.origin()
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.translate(-camX, -camY)
        love.graphics.setScissor(math.floor(x0 - camX), math.floor(y0 - camY), math.ceil(x1 - x0), math.ceil(y1 - y0))
        layer(i, camX, camY, x0, y0, x1, y1)
        love.graphics.pop()
        love.graphics.push("all")
        love.graphics.setBlendMode("alpha", "premultiplied")
        love.graphics.setShader(shader)
        shader:send("box", { ax0, ay0, ax1, ay1 })
        shader:send("origin", { camX, camY })
        shader:send("size", { canvas:getDimensions() })
        shader:send("feather", FEATHER)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(canvas, camX, camY)
        love.graphics.pop()
      end
    end
  end
end

return depthblend
