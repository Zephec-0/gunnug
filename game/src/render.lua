-- Draws the game to a low-res canvas and scales it to fill the window.
--
-- When the window isn't a whole multiple of the canvas (e.g. 400x225 into
-- 1920x1080 = 4.8x), plain nearest-neighbour scaling makes some pixels wider
-- than others. Instead the canvas is first blown up by a whole number with
-- nearest-neighbour (crisp), then smoothly scaled down the small remaining
-- amount — "sharp bilinear" scaling, which keeps every pixel the same size.
--
-- The finished frame also gets a post-process pass: bloom (the bright parts,
-- flames, eyes, sparks and the sun, blurred at two sizes and added back), sun
-- shafts, chromatic fringing, a little contrast, tints in the shadows and the
-- lights, saturation and a vignette. Each area sets its own mood (render.setMood), and the hunter's
-- health and hits bend it further.
local config = require("src.config")

local render = { scale = 1, offsetX = 0, offsetY = 0, post = true, bloom = 0.6 } -- bloom: how strong the glow is -- post: bloom and grading (a setting)

local W, H = config.VIRTUAL_W, config.VIRTUAL_H
local BACKGROUND = { 0.08, 0.06, 0.13 }

-- The look of the frame: area palettes blend between these (see render.mixFx).
-- Everything is a number or an rgb triple so two moods can be interpolated.
local DEFAULT_FX = {
  shadow = { 0.93, 0.97, 1.08 }, -- tint of the shadows
  light = { 1.07, 1.0, 0.92 }, -- tint of the lights
  sat = 1.0,
  contrast = 0.3,
  vig = 0.38,
  aberr = 0.6,
  shaft = 0, -- sun shafts
  sunX = 0.69, sunY = 0.54, -- where the sun is on screen (0..1)
}
render.defaultFx = DEFAULT_FX
local mood = { hurt = 0, lowhp = 0, dead = 0 }
local lamps = {} -- the strongest small lights in view (see lighting.lamps)
local lampPosT, lampColT, lampStrT = {}, {}, {}
local fx = {}
for k, v in pairs(DEFAULT_FX) do
  fx[k] = type(v) == "table" and { v[1], v[2], v[3] } or v
end

local canvas
local upscaled -- intermediate canvas at a whole-number multiple
local postCanvas -- the finished frame at game resolution (the post shader runs here, not at window size)
local upscale = 0
local bloomA, bloomB, bloomC, bloomD -- half and quarter size, ping-ponged
local brightShader, blurShader, finalShader, addShader

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

-- The bloom is added last, at window size: it is a soft glow, and sampled
-- smoothly it has no blocky steps (the rest of the post pass is whole-pixel
-- work and runs on the small frame)
local ADD = [[
uniform Image bloomNear;
uniform Image bloomFar;
uniform vec2 res;        // the small frame's size
uniform float aberr;     // colour fringing toward the edges
uniform float hurt;      // 1 -> 0 after a hit: a burst of fringing
uniform float bloom;     // how much glow is added
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec2 q = uv - 0.5;
  float r = length(q * vec2(1.0, res.y / res.x));
  // Chromatic aberration: none in the middle, fringing at the edges. Done
  // here, at window size, so the fringe is a fine sliver rather than whole
  // game pixels
  vec2 o = q * (aberr * (0.0009 + r * 0.0030) + hurt * 0.006);
  vec3 c = vec3(Texel(tex, uv + o).r, Texel(tex, uv).g, Texel(tex, uv - o).b);
  c += (Texel(bloomNear, uv).rgb * 0.7 + Texel(bloomFar, uv).rgb * 0.6) * bloom;
  return vec4(c, 1.0) * color;
}
]]

local FINAL = [[
uniform Image bloomNear;
uniform float time;
uniform float vig;       // vignette strength
uniform float sat;       // saturation
uniform float contrast;  // S-curve strength
uniform float shaft;     // sun shafts
uniform float lowhp;     // 0..1 how close to death: drained, pulsing red edges
uniform float dead;      // 0..1 fade to grey
uniform vec3 shadowTint;
uniform vec3 lightTint;
uniform vec2 sunPos;     // uv
uniform vec2 lampPos[4];  // uv of the strongest lamps in view
uniform vec3 lampCol[4];
uniform float lampStr[4];

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec2 q = uv - 0.5;
  vec3 c = Texel(tex, uv).rgb;

  // Sun shafts: the bright parts smeared toward the sun
  if (shaft > 0.0) {
    vec3 acc = vec3(0.0);
    float w = 1.0;
    for (int i = 1; i <= 14; i++) {
      vec2 s = mix(uv, sunPos, float(i) / 22.0);
      acc += Texel(bloomNear, s).rgb * w;
      w *= 0.9;
    }
    c += acc * 0.075 * shaft * vec3(1.0, 0.72, 0.46) * (1.0 - smoothstep(0.1, 0.9, length(uv - sunPos)) * 0.6);
  }

  // Lamp shafts: the same smear, toward the cave's own strongest lights
  for (int i = 0; i < 4; i++) {
    if (lampStr[i] > 0.0) {
      vec3 acc = vec3(0.0);
      float w = 1.0;
      for (int j = 1; j <= 8; j++) {
        vec2 s = mix(uv, lampPos[i], float(j) / 13.0);
        acc += Texel(bloomNear, s).rgb * w;
        w *= 0.86;
      }
      float near = 1.0 - smoothstep(0.04, 0.4, length((uv - lampPos[i]) * vec2(1.0, 0.56)));
      c += acc * 0.045 * lampStr[i] * lampCol[i] * near;
    }
  }

  // A gentle S-curve for contrast, cool shadows, warm lights
  vec3 s = c * c * (3.0 - 2.0 * clamp(c, 0.0, 1.0));
  c = mix(c, s, contrast);
  float l = dot(c, vec3(0.3, 0.59, 0.11));
  c *= mix(shadowTint, lightTint, smoothstep(0.1, 0.7, l));
  float g = dot(c, vec3(0.3, 0.59, 0.11));
  c = mix(vec3(g), c, sat * (1.0 - lowhp * 0.45) * (1.0 - dead));

  // Vignette (deeper and pulsing red when badly hurt)
  float pulse = 0.65 + 0.35 * sin(time * 5.0);
  float edge = smoothstep(0.3, 0.95, length(q * vec2(1.0, 1.1)));
  c *= 1.0 - edge * (vig + lowhp * 0.35 * pulse);
  c.r += edge * lowhp * 0.12 * pulse;
  return vec4(c, 1.0) * color;
}
]]

-- Fills dst with the mood a blended with the mood b (t = 0 is a, 1 is b);
-- fields a mood leaves out come from the defaults
function render.mixFx(dst, a, b, t)
  a, b = a or {}, b or a or {}
  for k, def in pairs(DEFAULT_FX) do
    local x, y = a[k] == nil and def or a[k], b[k] == nil and def or b[k]
    if type(def) == "table" then
      dst[k] = dst[k] or { 0, 0, 0 }
      for i = 1, 3 do
        dst[k][i] = x[i] + (y[i] - x[i]) * t
      end
    else
      dst[k] = x + (y - x) * t
    end
  end
  return dst
end

-- Sets this frame's look: the area's mood (a table like DEFAULT_FX, may be
-- nil) and the hunter's state (hurt flash 0..1, low health 0..1, dead 0..1)
function render.setMood(area, hurt, lowhp, dead)
  render.mixFx(fx, area, area, 0)
  mood.hurt, mood.lowhp, mood.dead = hurt or 0, lowhp or 0, dead or 0
end

-- The lights light shafts stream from this frame
function render.setLamps(list)
  lamps = list or {}
end

function render.load()
  love.graphics.setDefaultFilter("nearest", "nearest")
  love.graphics.setLineStyle("rough") -- crisp, un-antialiased pixel lines
  canvas = love.graphics.newCanvas(W, H)
  postCanvas = love.graphics.newCanvas(W, H)
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
  local ok4, d = pcall(love.graphics.newShader, ADD)
  if ok1 and ok2 and ok3 and ok4 then
    brightShader, blurShader, finalShader, addShader = a, b, c, d
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
  local source = canvas
  if post then
    makeBloom()
    local f = finalShader
    f:send("bloomNear", bloomA)
    f:send("time", love.timer.getTime())
    f:send("vig", fx.vig)
    f:send("sat", fx.sat)
    f:send("contrast", fx.contrast)
    f:send("shaft", fx.shaft)
    f:send("sunPos", { fx.sunX, fx.sunY })
    for i = 1, 4 do
      local l = lamps[i]
      lampPosT[i] = l and { l.x, l.y } or { 0, 0 }
      lampColT[i] = l and { l.r, l.g, l.b } or { 0, 0, 0 }
      lampStrT[i] = l and l.s or 0
    end
    f:send("lampPos", lampPosT[1], lampPosT[2], lampPosT[3], lampPosT[4])
    f:send("lampCol", lampColT[1], lampColT[2], lampColT[3], lampColT[4])
    f:send("lampStr", lampStrT[1], lampStrT[2], lampStrT[3], lampStrT[4])
    f:send("lowhp", mood.lowhp)
    f:send("dead", mood.dead)
    f:send("shadowTint", fx.shadow)
    f:send("lightTint", fx.light)
    -- The whole post pass runs on the 640x360 frame (it is all whole-pixel
    -- effects anyway), then the result is scaled up: far cheaper than shading
    -- every pixel of a 1080p window
    love.graphics.setCanvas(postCanvas)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setShader(finalShader)
    love.graphics.draw(canvas, 0, 0)
    love.graphics.setShader()
    love.graphics.setCanvas()
    source = postCanvas
    addShader:send("bloomNear", bloomA)
    addShader:send("bloomFar", bloomC)
    addShader:send("res", { W, H })
    addShader:send("aberr", fx.aberr)
    addShader:send("hurt", mood.hurt)
    addShader:send("bloom", render.bloom)
  end
  if math.abs(render.scale - upscale) < 1e-6 then
    love.graphics.setCanvas()
    love.graphics.clear(0, 0, 0)
    love.graphics.setShader(post and addShader or nil)
    love.graphics.draw(source, render.offsetX, render.offsetY, 0, render.scale, render.scale)
    love.graphics.setShader()
    return
  end
  love.graphics.setCanvas(upscaled)
  love.graphics.clear(0, 0, 0)
  love.graphics.setShader(post and addShader or nil)
  love.graphics.draw(source, 0, 0, 0, upscale, upscale)
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
