-- Draws the game to a low-res canvas and scales it to fill the window.
--
-- When the window isn't a whole multiple of the canvas (e.g. 400x225 into
-- 1920x1080 = 4.8x), plain nearest-neighbour scaling makes some pixels wider
-- than others. Instead the canvas is first blown up by a whole number with
-- nearest-neighbour (crisp), then smoothly scaled down the small remaining
-- amount — "sharp bilinear" scaling, which keeps every pixel the same size.
--
-- The finished frame also gets a post-process pass: bloom (the bright parts,
-- flames, eyes, sparks and the sun, blurred at two sizes and added back), a
-- little contrast, a cool tint in the shadows and a warm one in the lights,
-- and a soft vignette.
local config = require("src.config")

local render = { scale = 1, offsetX = 0, offsetY = 0, post = true } -- post: bloom and grading (a setting)

local W, H = config.VIRTUAL_W, config.VIRTUAL_H
local BACKGROUND = { 0.08, 0.06, 0.13 }

local canvas
local upscaled -- intermediate canvas at a whole-number multiple
local upscale = 0
local bloomA, bloomB, bloomC, bloomD -- half and quarter size, ping-ponged
local brightShader, blurShader, finalShader

local BRIGHT = [[
uniform float threshold;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec3 c = Texel(tex, uv).rgb;
  float m = max(c.r, max(c.g, c.b));
  float k = smoothstep(threshold, threshold + 0.3, m);
  return vec4(c * k, 1.0);
}
]]

local BLUR = [[
uniform vec2 dir;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec3 sum = Texel(tex, uv).rgb * 0.2270270270;
  sum += Texel(tex, uv + dir * 1.3846153846).rgb * 0.3162162162;
  sum += Texel(tex, uv - dir * 1.3846153846).rgb * 0.3162162162;
  sum += Texel(tex, uv + dir * 3.2307692308).rgb * 0.0702702703;
  sum += Texel(tex, uv - dir * 3.2307692308).rgb * 0.0702702703;
  return vec4(sum, 1.0);
}
]]

local FINAL = [[
uniform Image bloomNear;
uniform Image bloomFar;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec3 c = Texel(tex, uv).rgb;
  c += Texel(bloomNear, uv).rgb * 0.7 + Texel(bloomFar, uv).rgb * 0.6;
  // A gentle S-curve for contrast, cool shadows, warm lights
  vec3 s = c * c * (3.0 - 2.0 * clamp(c, 0.0, 1.0));
  c = mix(c, s, 0.3);
  float l = dot(c, vec3(0.3, 0.59, 0.11));
  c *= mix(vec3(0.93, 0.97, 1.08), vec3(1.07, 1.0, 0.92), smoothstep(0.1, 0.7, l));
  // Vignette
  vec2 q = (uv - 0.5) * vec2(1.0, 1.1);
  c *= 1.0 - smoothstep(0.3, 0.95, length(q)) * 0.38;
  return vec4(c, 1.0) * color;
}
]]

function render.load()
  love.graphics.setDefaultFilter("nearest", "nearest")
  love.graphics.setLineStyle("rough") -- crisp, un-antialiased pixel lines
  canvas = love.graphics.newCanvas(W, H)
  local function small(div)
    local c = love.graphics.newCanvas(math.floor(W / div), math.floor(H / div))
    c:setFilter("linear", "linear")
    c:setWrap("clamp", "clamp")
    return c
  end
  bloomA, bloomB, bloomC, bloomD = small(2), small(2), small(4), small(4)
  local ok1, a = pcall(love.graphics.newShader, BRIGHT)
  local ok2, b = pcall(love.graphics.newShader, BLUR)
  local ok3, c = pcall(love.graphics.newShader, FINAL)
  if ok1 and ok2 and ok3 then
    brightShader, blurShader, finalShader = a, b, c
  else
    print("render: post-process shaders unavailable", a, b, c)
  end
  render.layout()
end

function render.layout()
  local ww, wh = love.graphics.getDimensions()
  render.scale = math.min(ww / W, wh / H)
  render.offsetX = math.floor((ww - W * render.scale) / 2)
  render.offsetY = math.floor((wh - H * render.scale) / 2)

  local whole = math.max(1, math.ceil(render.scale - 1e-6))
  if whole ~= upscale then
    upscale = whole
    upscaled = love.graphics.newCanvas(W * whole, H * whole)
    upscaled:setFilter("linear", "linear")
  end
end

function render.beginWorld()
  love.graphics.setCanvas(canvas)
  -- World lines (tracers, the guns in the hunter's hands) are one game pixel;
  -- never inherit a thicker width left over from the full-resolution UI
  love.graphics.setLineWidth(1)
  love.graphics.clear(BACKGROUND)
end

-- Blurs the bright parts of the frame into bloomA (near, half size) and
-- bloomC (far, quarter size)
local function makeBloom()
  love.graphics.setColor(1, 1, 1)
  love.graphics.setShader(brightShader)
  brightShader:send("threshold", 0.8)
  love.graphics.setCanvas(bloomA)
  love.graphics.clear(0, 0, 0, 1)
  love.graphics.draw(canvas, 0, 0, 0, bloomA:getWidth() / W, bloomA:getHeight() / H)
  love.graphics.setShader(blurShader)
  local function blur(from, to)
    love.graphics.setCanvas(to)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.draw(from, 0, 0)
  end
  blurShader:send("dir", { 1 / bloomA:getWidth(), 0 })
  blur(bloomA, bloomB)
  blurShader:send("dir", { 0, 1 / bloomA:getHeight() })
  blur(bloomB, bloomA)
  -- Down to a quarter for the wide glow
  love.graphics.setShader()
  love.graphics.setCanvas(bloomC)
  love.graphics.clear(0, 0, 0, 1)
  love.graphics.draw(bloomA, 0, 0, 0, bloomC:getWidth() / bloomA:getWidth(), bloomC:getHeight() / bloomA:getHeight())
  love.graphics.setShader(blurShader)
  blurShader:send("dir", { 1 / bloomC:getWidth(), 0 })
  blur(bloomC, bloomD)
  blurShader:send("dir", { 0, 1 / bloomC:getHeight() })
  blur(bloomD, bloomC)
  love.graphics.setShader()
  love.graphics.setCanvas()
end

function render.endWorld()
  love.graphics.setColor(1, 1, 1)
  local post = finalShader ~= nil and render.post
  local shader = post and finalShader or nil
  if post then
    makeBloom()
    finalShader:send("bloomNear", bloomA)
    finalShader:send("bloomFar", bloomC)
  end
  if math.abs(render.scale - upscale) < 1e-6 then
    love.graphics.setCanvas()
    love.graphics.clear(0, 0, 0)
    love.graphics.setShader(shader)
    love.graphics.draw(canvas, render.offsetX, render.offsetY, 0, render.scale, render.scale)
    love.graphics.setShader()
    return
  end
  love.graphics.setCanvas(upscaled)
  love.graphics.clear(0, 0, 0)
  love.graphics.setShader(shader)
  love.graphics.draw(canvas, 0, 0, 0, upscale, upscale)
  love.graphics.setShader()
  love.graphics.setCanvas()
  love.graphics.clear(0, 0, 0)
  local s = render.scale / upscale
  love.graphics.draw(upscaled, render.offsetX, render.offsetY, 0, s, s)
end

-- Size of one UI unit in window pixels, independent of the world pixel density
function render.uiScale()
  return render.scale * config.UI_SCALE
end

-- Window pixels -> canvas pixels
function render.toVirtual(sx, sy)
  return (sx - render.offsetX) / render.scale, (sy - render.offsetY) / render.scale
end

-- Canvas pixels -> window pixels
function render.toScreen(vx, vy)
  return vx * render.scale + render.offsetX, vy * render.scale + render.offsetY
end

return render
