-- 2D lighting (Dead Cells-style mood). Each frame:
--   1. a terrain mask is drawn (solid = white);
--   2. a light map is built on a low-res canvas, cleared to the scene's ambient
--      colour, with every light added on top by a shader that marches a ray
--      from each pixel to the light through the mask, so rock casts shadows
--      (a little light leaks through, and rock faces right at the edge of
--      open air stay lit);
--   3. a second, softer pass of the same lights goes into a haze canvas: a
--      tight glow around each light;
--   3b. in caves, fog: the finished light map is shrunk to a quarter-size
--      canvas (open air only), blurred wide, and added to the haze through
--      drifting noise, so light spills out into the air around it and the
--      shadows rock casts carry on into the fog. It is held back where the
--      light is already bright, so lamps keep their shape instead of blowing
--      out, and a faint mist tinted by the ambient light hangs in open air far
--      from any light. All of it costs a few small full-screen passes, however
--      many lights there are;
--   4. the light map is multiplied over the finished scene and the haze is
--      added on top, so the air around a lantern or a flame glows: the
--      volumetric part. Walls block the haze too. Dust motes drift through
--      the lit air of caves (lighting.drawMotes, drawn before the multiply).
-- Things that should glow regardless (eyes, flames, sparks, bullets) are
-- drawn after all this as "emissive"; src.render then blooms them.
-- If shaders are unavailable the old unshadowed radial sprites are used.
local config = require("src.config")

local lighting = {}

local W, H = config.VIRTUAL_W, config.VIRTUAL_H
local canvas, hazeCanvas, maskCanvas
local glow -- radial falloff sprite (fallback path)
local white -- 1x1 sprite the shader quads are drawn with
local lightShader, maskShader
local fogGather, fogBlur, fogApply -- fog shaders (nil if unavailable)
local fogA, fogB -- quarter-size fog canvases, ping-ponged by the blur
local FOG_DIV = 4
local lights = {}
local ambient = { 1, 1, 1 }

local HAZE = 0.2 -- strength of the haze pass relative to the light itself
local HAZE_MAX_RADIUS = 200 -- bigger lights (the sun) make no haze
local FOG = 0.45 -- strength of the fog lit by the lights around it
local FOG_CEILING = 0.12 -- the most the fog can add anywhere (soft limit)
local MIST = 0.017 -- peak strength of the mist hanging in open cave air

local LIGHT_SOURCE = [[
uniform Image mask;
uniform vec2 origin;
uniform vec2 span;
uniform vec2 lightPos;
uniform vec2 canvasSize;
uniform float radius;
uniform float power;
uniform float leak;
uniform vec3 tint;

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec2 p = origin + uv * span;
  float dist = length(p - lightPos);
  if (dist >= radius) {
    return vec4(0.0, 0.0, 0.0, 0.0);
  }
  float f = 1.0 - dist / radius;
  float a = pow(f, power) + 0.25 * pow(f, 6.0);
  float vis = 1.0;
  if (dist > 6.0) {
    float occ = 0.0;
    // Each pixel starts its ray at a different offset, so the shadow edges
    // come out as fine grain instead of wide bands
    float jitter = fract(sin(dot(floor(p), vec2(12.9898, 78.233))) * 43758.5453);
    for (int i = 0; i < 24; i++) {
      float t = (float(i) + jitter) / 24.0;
      float along = t * dist;
      if (along > 3.0 && along < dist - 3.0) {
        vec2 q = (p + (lightPos - p) * t) / canvasSize;
        occ += Texel(mask, q).r;
      }
    }
    occ = occ * dist / 24.0;
    vis = mix(leak, 1.0, exp(-occ * 0.35));
  }
  return vec4(tint * a * vis, 1.0);
}
]]

-- Fog, step 1: the light map (less the ambient) in open air, shrunk to the
-- fog canvas. Four linear taps cover each 4x4 block.
local FOG_GATHER = [[
uniform Image mask;
uniform vec3 ambient;
uniform vec2 texel;

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec3 l = vec3(0.0);
  float solid = 0.0;
  vec2 o[4];
  o[0] = vec2(-1.0, -1.0);
  o[1] = vec2(1.0, -1.0);
  o[2] = vec2(-1.0, 1.0);
  o[3] = vec2(1.0, 1.0);
  for (int i = 0; i < 4; i++) {
    l += Texel(tex, uv + o[i] * texel).rgb;
    solid += Texel(mask, uv + o[i] * texel).r;
  }
  l = max(l * 0.25 - ambient, 0.0);
  return vec4(l * (1.0 - solid * 0.25), 1.0);
}
]]

-- Fog, step 2: a wide separable blur on the fog canvas
local FOG_BLUR = [[
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

-- Fog, step 3 (full size, into the haze): the blurred light through drifting
-- noise, held back where the light is already bright, softly capped, plus
-- the mist; only over open air
local FOG_APPLY = [[
uniform Image fog;
uniform Image mask;
uniform Image light;
uniform vec3 ambient;
uniform vec2 cam;
uniform vec2 canvasSize;
uniform float time;
uniform float strength;
uniform float ceiling;
uniform vec3 mistTint;
uniform float mist;

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  float air = 1.0 - Texel(mask, uv).r;
  if (air <= 0.0) {
    return vec4(0.0, 0.0, 0.0, 1.0);
  }
  vec2 w = uv * canvasSize + cam;
  float n = vnoise(w * 0.018 + vec2(time * 0.04, time * 0.015)) * 0.65
    + vnoise(w * 0.047 - vec2(time * 0.035, 0.0)) * 0.35;
  float drift = 0.3 + 1.2 * smoothstep(0.2, 0.85, n);
  vec3 here = max(Texel(light, uv).rgb - ambient, 0.0);
  float lum = dot(here, vec3(0.3, 0.59, 0.11));
  float keep = 1.0 - 0.8 * smoothstep(0.08, 0.55, lum);
  vec3 f = Texel(fog, uv).rgb * strength * drift * keep;
  f = f * ceiling / (ceiling + f); // never more than the ceiling, however many lights overlap
  f += mistTint * smoothstep(0.45, 0.9, n) * mist;
  return vec4(f * air, 1.0);
}
]]

local MASK_SOURCE = [[
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  float a = Texel(tex, uv).a;
  return vec4(a, a, a, 1.0);
}
]]

function lighting.load()
  canvas = love.graphics.newCanvas(W, H)
  hazeCanvas = love.graphics.newCanvas(W, H)
  maskCanvas = love.graphics.newCanvas(W, H)
  maskCanvas:setFilter("nearest", "nearest")
  local one = love.image.newImageData(1, 1)
  one:setPixel(0, 0, 1, 1, 1, 1)
  white = love.graphics.newImage(one)
  local ok, a = pcall(love.graphics.newShader, LIGHT_SOURCE)
  local ok2, b = pcall(love.graphics.newShader, MASK_SOURCE)
  if ok and ok2 then
    lightShader, maskShader = a, b
    local okG, g = pcall(love.graphics.newShader, FOG_GATHER)
    local okB, bl = pcall(love.graphics.newShader, FOG_BLUR)
    local okA, ap = pcall(love.graphics.newShader, FOG_APPLY)
    if okG and okB and okA then
      fogGather, fogBlur, fogApply = g, bl, ap
      local function small()
        local c = love.graphics.newCanvas(math.floor(W / FOG_DIV), math.floor(H / FOG_DIV))
        c:setFilter("linear", "linear")
        c:setWrap("clamp", "clamp")
        return c
      end
      fogA, fogB = small(), small()
      canvas:setFilter("linear", "linear") -- (sampled between pixels by the gather)
    else
      print("lighting: fog shaders unavailable", g, bl, ap)
    end
  else
    print("lighting: shaders unavailable, using plain lights", a, b)
  end
  local size = 128
  local data = love.image.newImageData(size, size)
  for y = 0, size - 1 do
    for x = 0, size - 1 do
      local dx, dy = (x + 0.5) / size * 2 - 1, (y + 0.5) / size * 2 - 1
      local d = math.min(1, math.sqrt(dx * dx + dy * dy))
      local v = (1 - d) * (1 - d) -- soft quadratic falloff
      data:setPixel(x, y, v, v, v, 1)
    end
  end
  glow = love.graphics.newImage(data)
  glow:setFilter("linear", "linear")
end

-- Starts a new frame of lights with the given ambient colour
function lighting.begin(ambientColor)
  lights = {}
  ambient = ambientColor or { 1, 1, 1 }
end

-- Adds a light in world coordinates. intensity scales the colour.
function lighting.add(x, y, radius, r, g, b, intensity)
  intensity = intensity or 1
  lights[#lights + 1] = { x = x, y = y, radius = radius, r = r * intensity, g = g * intensity, b = b * intensity }
end

-- One light drawn by the shader onto the current canvas
local function drawLight(l, camX, camY, radius, power, leak, scale)
  local lx, ly = l.x - camX, l.y - camY
  local x0, y0 = math.max(0, math.floor(lx - radius)), math.max(0, math.floor(ly - radius))
  local x1, y1 = math.min(W, math.ceil(lx + radius)), math.min(H, math.ceil(ly + radius))
  if x1 <= x0 or y1 <= y0 then
    return
  end
  lightShader:send("origin", { x0, y0 })
  lightShader:send("span", { x1 - x0, y1 - y0 })
  lightShader:send("lightPos", { lx, ly })
  lightShader:send("radius", radius)
  lightShader:send("power", power)
  lightShader:send("leak", leak)
  lightShader:send("tint", { l.r * scale, l.g * scale, l.b * scale })
  love.graphics.draw(white, x0, y0, 0, x1 - x0, y1 - y0)
end

-- Renders the light map (and haze) for the current camera. Call before
-- drawing the scene (it switches canvases). drawTerrain: a function that
-- draws the terrain in world coordinates (it is drawn into the mask).
function lighting.render(camX, camY, drawTerrain)
  love.graphics.push("all")
  love.graphics.origin()
  if lightShader and drawTerrain then
    love.graphics.setCanvas(maskCanvas)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.push()
    love.graphics.translate(-camX, -camY)
    love.graphics.setShader(maskShader)
    drawTerrain()
    love.graphics.pop()
    love.graphics.setShader()

    lightShader:send("mask", maskCanvas)
    lightShader:send("canvasSize", { W, H })
    love.graphics.setBlendMode("add")
    love.graphics.setColor(1, 1, 1)
    love.graphics.setShader(lightShader)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(ambient[1], ambient[2], ambient[3], 1)
    for _, l in ipairs(lights) do
      drawLight(l, camX, camY, l.radius, 1.7, 0.3, 1)
    end
    love.graphics.setCanvas(hazeCanvas)
    love.graphics.clear(0, 0, 0, 1)
    for _, l in ipairs(lights) do
      if l.radius <= HAZE_MAX_RADIUS then
        drawLight(l, camX, camY, l.radius * 1.3, 2.4, 0.04, HAZE)
      end
    end
    -- Fog and mist belong to the caves: none on the surface, fading in as the
    -- ambient light darkens on the way down
    local dark = math.max(0, 1 - (ambient[1] + ambient[2] + ambient[3]) / 3 / 0.6)
    if fogApply and dark > 0 then
      love.graphics.setBlendMode("replace", "premultiplied")
      love.graphics.setShader(fogGather)
      fogGather:send("mask", maskCanvas)
      fogGather:send("ambient", ambient)
      fogGather:send("texel", { 1 / W, 1 / H })
      love.graphics.setCanvas(fogA)
      love.graphics.draw(canvas, 0, 0, 0, 1 / FOG_DIV, 1 / FOG_DIV)
      love.graphics.setShader(fogBlur)
      local fw, fh = fogA:getDimensions()
      for pass = 1, 2 do
        local spread = pass * 1.5
        fogBlur:send("dir", { spread / fw, 0 })
        love.graphics.setCanvas(fogB)
        love.graphics.draw(fogA, 0, 0)
        fogBlur:send("dir", { 0, spread / fh })
        love.graphics.setCanvas(fogA)
        love.graphics.draw(fogB, 0, 0)
      end
      love.graphics.setBlendMode("add")
      love.graphics.setCanvas(hazeCanvas)
      love.graphics.setShader(fogApply)
      local peak = math.max(ambient[1], ambient[2], ambient[3], 0.01)
      fogApply:send("fog", fogA)
      fogApply:send("mask", maskCanvas)
      fogApply:send("light", canvas)
      fogApply:send("ambient", ambient)
      fogApply:send("cam", { camX, camY })
      fogApply:send("canvasSize", { W, H })
      fogApply:send("time", love.timer.getTime())
      fogApply:send("strength", FOG * math.min(1, dark * 2))
      fogApply:send("ceiling", FOG_CEILING)
      fogApply:send("mistTint", { ambient[1] / peak, ambient[2] / peak, ambient[3] / peak })
      fogApply:send("mist", MIST * dark)
      love.graphics.draw(white, 0, 0, 0, W, H)
    end
    love.graphics.setShader()
  else
    lightShader = nil
    love.graphics.setCanvas(canvas)
    love.graphics.clear(ambient[1], ambient[2], ambient[3], 1)
    love.graphics.setBlendMode("add")
    local gw = glow:getWidth()
    for _, l in ipairs(lights) do
      local s = l.radius * 2 / gw
      love.graphics.setColor(l.r, l.g, l.b)
      love.graphics.draw(glow, l.x - camX - l.radius, l.y - camY - l.radius, 0, s, s)
    end
  end
  love.graphics.pop()
end

-- Dust motes drifting through the air of caves. Drawn in screen space just
-- before lighting.apply, so the light map dims the ones in the dark and the
-- ones in a lantern glow catch it.
local MOTES = 90
function lighting.drawMotes(camX, camY)
  local dark = 1 - (ambient[1] + ambient[2] + ambient[3]) / 3 / 0.6
  if dark <= 0 then
    return
  end
  local t = love.timer.getTime()
  love.graphics.push("all")
  love.graphics.origin()
  for i = 1, MOTES do
    local seed = i * 12.9898
    local depth = 0.55 + (i * 0.6180339) % 1 * 0.45 -- parallax: nearer motes follow the camera more
    local bx = (seed * 7.13 + t * (1.5 + i % 5 * 0.8)) - camX * depth
    local by = (seed * 3.71 + math.sin(t * 0.3 + i) * 10) - camY * depth - t * (0.8 + i % 3 * 0.5)
    local x = math.floor(bx % (W + 20) - 10)
    local y = math.floor(by % (H + 20) - 10)
    local twinkle = 0.55 + 0.45 * math.sin(t * (0.9 + i % 4 * 0.5) + i)
    love.graphics.setColor(1, 0.97, 0.88, 0.55 * twinkle * math.min(1, dark * 1.4))
    love.graphics.rectangle("fill", x, y, 1, 1)
  end
  love.graphics.pop()
end

-- Multiplies the light map over everything drawn so far on the current
-- canvas, then adds the haze
function lighting.apply()
  love.graphics.push("all")
  love.graphics.origin()
  love.graphics.setBlendMode("multiply", "premultiplied")
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(canvas, 0, 0)
  if lightShader then
    love.graphics.setBlendMode("add", "premultiplied")
    love.graphics.draw(hazeCanvas, 0, 0)
  end
  love.graphics.pop()
end

return lighting
