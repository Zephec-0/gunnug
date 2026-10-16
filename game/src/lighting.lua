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
local lightShader, maskShader, terrainShader, softShader
local fogGather, fogBlur, fogApply -- fog shaders (nil if unavailable)
local fogA, fogB -- quarter-size fog canvases, ping-ponged by the blur
local FOG_DIV = 4
local lights = {}
local ambient = { 1, 1, 1 }

local LIGHT_GAIN = 1.125 -- every light a little brighter than its colour says
local HAZE = 0.2 -- strength of the haze pass relative to the light itself
local HAZE_MAX_RADIUS = 200 -- bigger lights (the sun) make no haze
local FOG = 0.45 -- strength of the fog lit by the lights around it
local FOG_CEILING = 0.12 -- the most the fog can add anywhere (soft limit)
local MIST = 0.017 -- peak strength of the mist hanging in open cave air

-- Every light of a pass is one quad of a single mesh, its position, radius
-- and colour carried by the vertices (a draw and seven uniforms per light
-- added up to most of a millisecond with a gunfight's hundred-odd lights)
local LIGHT_SOURCE = [[
varying vec3 vLight; // the light's x, y and radius, in canvas pixels
varying vec3 vTint;
varying vec2 vPos;

#ifdef VERTEX
attribute vec4 LightA;
attribute vec4 LightB;
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  vLight = LightA.xyz;
  vTint = LightB.rgb;
  vPos = vertex_position.xy;
  return transform_projection * vertex_position;
}
#endif

#ifdef PIXEL
uniform Image mask;
uniform vec2 canvasSize;
uniform float power;
uniform float leak;
uniform float gain;

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec2 p = vPos;
  vec2 lightPos = vLight.xy;
  float radius = vLight.z;
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
    vis = mix(leak, 1.0, exp(-occ * 0.55));
  }
  return vec4(vTint * gain * a * vis, 1.0);
}
#endif
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
uniform float drift;

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
  float n = vnoise(w * 0.018 + vec2(time * 0.04 - drift * 0.012, time * 0.015)) * 0.65
    + vnoise(w * 0.047 - vec2(time * 0.035 + drift * 0.02, 0.0)) * 0.35;
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

-- Softens the light map and haze as they are laid over the scene: five taps
-- a little under a pixel apart. The shadow rays start at a random offset per
-- pixel (so edges come out as fine grain, not bands); this takes the sparkle
-- out of that grain and keeps the edges.
local SOFT_SOURCE = [[
uniform vec2 texel;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec2 o = texel * 0.8;
  vec4 c = Texel(tex, uv) * 0.36;
  c += (Texel(tex, uv + vec2(o.x, o.y)) + Texel(tex, uv + vec2(-o.x, o.y)) + Texel(tex, uv + vec2(o.x, -o.y)) + Texel(tex, uv + vec2(-o.x, -o.y))) * 0.16;
  return c;
}
]]

local MASK_SOURCE = [[
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  float a = Texel(tex, uv).a * color.a;
  return vec4(a, a, a, 1.0);
}
]]

-- Normal-mapped terrain. The rock's own shading is read as a height map; the
-- direction the light map brightens toward is the direction of the light. Faces
-- tilted toward it brighten, faces tilted away darken, and the shiny crests
-- pick up a glint. The light map itself is multiplied over afterwards, so this
-- only adds relief: it does nothing where the light is flat or dim.
local TERRAIN_SOURCE = [[
uniform Image light;
uniform vec2 canvasSize;
uniform vec2 texel;
uniform vec3 ambient;
uniform float strength;

float lum(vec3 c) {
  return dot(c, vec3(0.3, 0.59, 0.11));
}

// The rock's brightness smoothed over a few pixels (3 taps), so the relief
// follows its broad shading and ridges instead of every pixel's speckle
float height(Image t, vec2 uv, vec2 along, float own) {
  vec4 a = Texel(t, uv);
  vec4 b = Texel(t, uv + along);
  vec4 c = Texel(t, uv - along);
  float h = (a.a > 0.5 ? lum(a.rgb) : own) + (b.a > 0.5 ? lum(b.rgb) : own) + (c.a > 0.5 ? lum(c.rgb) : own);
  return h / 3.0;
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec4 c = Texel(tex, uv);
  if (c.a < 0.5) {
    return c * color;
  }
  float own = lum(c.rgb);
  vec2 ox = vec2(texel.x * 3.0, 0.0);
  vec2 oy = vec2(0.0, texel.y * 3.0);
  float hl = height(tex, uv - ox, oy, own);
  float hr = height(tex, uv + ox, oy, own);
  float hu = height(tex, uv - oy, ox, own);
  float hd = height(tex, uv + oy, ox, own);
  vec3 n = normalize(vec3((hl - hr) * 2.2, (hu - hd) * 2.2, 1.0));

  vec2 p = sc / canvasSize;
  vec2 d = vec2(5.0) / canvasSize;
  vec2 j = vec2(0.0, 1.5) / canvasSize;
  vec2 i = vec2(1.5, 0.0) / canvasSize;
  float ll = lum(Texel(light, p - vec2(d.x, 0.0)).rgb) + lum(Texel(light, p - vec2(d.x, 0.0) + j).rgb) + lum(Texel(light, p - vec2(d.x, 0.0) - j).rgb);
  float lr = lum(Texel(light, p + vec2(d.x, 0.0)).rgb) + lum(Texel(light, p + vec2(d.x, 0.0) + j).rgb) + lum(Texel(light, p + vec2(d.x, 0.0) - j).rgb);
  float lu = lum(Texel(light, p - vec2(0.0, d.y)).rgb) + lum(Texel(light, p - vec2(0.0, d.y) + i).rgb) + lum(Texel(light, p - vec2(0.0, d.y) - i).rgb);
  float ld = lum(Texel(light, p + vec2(0.0, d.y)).rgb) + lum(Texel(light, p + vec2(0.0, d.y) + i).rgb) + lum(Texel(light, p + vec2(0.0, d.y) - i).rgb);
  vec2 g = vec2(lr - ll, ld - lu) / 3.0;
  float lv = max(lum(Texel(light, p).rgb) - lum(ambient), 0.0);
  float reach = smoothstep(0.0, 0.06, length(g)) * smoothstep(0.03, 0.4, lv);
  vec3 L = normalize(vec3(g * 4.0, 0.5));
  float lit = dot(n, L) - L.z;
  float glint = pow(max(dot(n, normalize(L + vec3(0.0, 0.0, 1.0))), 0.0), 36.0) * smoothstep(0.4, 0.85, own);
  vec3 rgb = c.rgb * (1.0 + clamp(lit, -0.5, 0.5) * 1.1 * strength * reach) + vec3(1.0, 0.93, 0.8) * glint * 0.2 * strength * reach;
  return vec4(rgb, 1.0) * color;
}
]]

-- The view got bigger or smaller (the boss fights pull the camera out, see
-- render.setZoom): the light canvases are made again at the new size
function lighting.resize(w, h)
  if w == W and h == H then
    return
  end
  W, H = w, h
  if not canvas then
    return
  end
  local linear = canvas:getFilter() == "linear"
  canvas = love.graphics.newCanvas(W, H)
  hazeCanvas = love.graphics.newCanvas(W, H)
  maskCanvas = love.graphics.newCanvas(W, H)
  maskCanvas:setFilter("nearest", "nearest")
  if linear then
    canvas:setFilter("linear", "linear")
    hazeCanvas:setFilter("linear", "linear")
  end
  if fogA then
    local function small()
      local c = love.graphics.newCanvas(math.floor(W / FOG_DIV), math.floor(H / FOG_DIV))
      c:setFilter("linear", "linear")
      c:setWrap("clamp", "clamp")
      return c
    end
    fogA, fogB = small(), small()
  end
end

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
    local okS, sf = pcall(love.graphics.newShader, SOFT_SOURCE)
    if okS then
      softShader = sf
      canvas:setFilter("linear", "linear")
      hazeCanvas:setFilter("linear", "linear")
    end
    local okT, t = pcall(love.graphics.newShader, TERRAIN_SOURCE)
    if okT then
      terrainShader = t
    else
      print("lighting: terrain shader unavailable", t)
    end
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

-- The light records are kept and reused frame to frame (hundreds a frame in
-- a gunfight were a steady stream of garbage)
local lightPool = {}

-- Starts a new frame of lights with the given ambient colour
function lighting.begin(ambientColor)
  for i = #lights, 1, -1 do
    lights[i] = nil
  end
  ambient = ambientColor or { 1, 1, 1 }
end

-- Adds a light in world coordinates. intensity scales the colour.
function lighting.add(x, y, radius, r, g, b, intensity)
  intensity = intensity or 1
  local n = #lights + 1
  local l = lightPool[n]
  if not l then
    l = {}
    lightPool[n] = l
  end
  l.x, l.y, l.radius = x, y, radius
  l.r, l.g, l.b = r * intensity, g * intensity, b * intensity
  lights[n] = l
end

local LIGHT_FORMAT = { { "VertexPosition", "float", 2 }, { "LightA", "float", 4 }, { "LightB", "float", 4 } }
local lightVerts = { {}, {} } -- (per pass: kept and refilled, like the light records)
local lightMeshes = {}

local function lightVert(verts, k, x, y, lx, ly, radius, l)
  local v = verts[k]
  if not v then
    v = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
    verts[k] = v
  end
  v[1], v[2], v[3], v[4], v[5] = x, y, lx, ly, radius
  v[7], v[8], v[9] = l.r, l.g, l.b
end

-- Draws a pass of lights (the shader set, its power, leak and gain sent) onto
-- the current canvas: all of them at once, each a quad over its reach.
-- hazeOnly: just the small lights (the sun makes no haze).
local function drawLights(pass, camX, camY, radiusMul, hazeOnly)
  local verts = lightVerts[pass]
  local n = 0
  for _, l in ipairs(lights) do
    if not hazeOnly or l.radius <= HAZE_MAX_RADIUS then
      local radius = l.radius * radiusMul
      local lx, ly = l.x - camX, l.y - camY
      local x0, y0 = math.max(0, math.floor(lx - radius)), math.max(0, math.floor(ly - radius))
      local x1, y1 = math.min(W, math.ceil(lx + radius)), math.min(H, math.ceil(ly + radius))
      if x1 > x0 and y1 > y0 then
        lightVert(verts, n + 1, x0, y0, lx, ly, radius, l)
        lightVert(verts, n + 2, x1, y0, lx, ly, radius, l)
        lightVert(verts, n + 3, x1, y1, lx, ly, radius, l)
        lightVert(verts, n + 4, x0, y0, lx, ly, radius, l)
        lightVert(verts, n + 5, x1, y1, lx, ly, radius, l)
        lightVert(verts, n + 6, x0, y1, lx, ly, radius, l)
        n = n + 6
      end
    end
  end
  if n == 0 then
    return
  end
  local mesh = lightMeshes[pass]
  if not mesh or mesh:getVertexCount() < n then
    mesh = love.graphics.newMesh(LIGHT_FORMAT, math.max(n, 1200), "triangles", "dynamic")
    lightMeshes[pass] = mesh
  end
  mesh:setVertices(verts, 1, n)
  mesh:setDrawRange(1, n)
  love.graphics.draw(mesh)
end

-- Renders the light map (and haze) for the current camera. Call before
-- drawing the scene (it switches canvases). drawTerrain: a function that
-- draws the terrain in world coordinates (it is drawn into the mask).
function lighting.render(camX, camY, drawTerrain, drawOccluders)
  love.graphics.push("all")
  love.graphics.origin()
  if lightShader and drawTerrain then
    love.graphics.setCanvas(maskCanvas)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.push()
    love.graphics.translate(-camX, -camY)
    love.graphics.setShader(maskShader)
    drawTerrain()
    if drawOccluders then
      -- Creatures cast soft shadows too: partial blockers, never darker than rock
      love.graphics.setBlendMode("lighten", "premultiplied")
      drawOccluders()
      love.graphics.setBlendMode("alpha")
    end
    love.graphics.pop()
    love.graphics.setShader()

    lightShader:send("mask", maskCanvas)
    lightShader:send("canvasSize", { W, H })
    love.graphics.setBlendMode("add")
    love.graphics.setColor(1, 1, 1)
    love.graphics.setShader(lightShader)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(ambient[1], ambient[2], ambient[3], 1)
    lightShader:send("power", 1.7)
    lightShader:send("leak", 0.08)
    lightShader:send("gain", LIGHT_GAIN)
    drawLights(1, camX, camY, 1, false)
    love.graphics.setCanvas(hazeCanvas)
    love.graphics.clear(0, 0, 0, 1)
    lightShader:send("power", 2.4)
    lightShader:send("leak", 0.03)
    lightShader:send("gain", HAZE)
    drawLights(2, camX, camY, 1.3, true)
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
      fogApply:send("drift", lighting.drift)
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

-- The terrain mask of this frame (solid = white), at the size of the frame; nil if the lighting shaders are unavailable
function lighting.mask()
  return lightShader and maskCanvas or nil
end

-- This frame's lights (read-only; for things that reflect them)
function lighting.list()
  return lights
end

-- How strong the terrain's relief is (0 turns it off)
lighting.reliefStrength = 1

-- How far the wind has blown the air (px), set by src.weather: it carries the
-- fog and the dust motes along
lighting.drift = 0

-- The terrain shader for this frame's lit pass (nil if unavailable), with the
-- light map and ambient set. Pass it to World:draw.
function lighting.terrainShader()
  if not terrainShader or not lightShader or (lighting.reliefStrength or 0) <= 0 then
    return nil
  end
  terrainShader:send("light", canvas)
  terrainShader:send("canvasSize", { W, H })
  terrainShader:send("ambient", ambient)
  terrainShader:send("strength", lighting.reliefStrength)
  return terrainShader
end

-- The n strongest small lights in view (not the sun): where light shafts
-- stream from in the cave's air. Each { x, y (0..1 of the screen), r, g, b, s (0..1) }
function lighting.lamps(camX, camY, n)
  local dark = 1 - (ambient[1] + ambient[2] + ambient[3]) / 3 / 0.6
  local out = {}
  if dark <= 0 then
    return out
  end
  -- Kept sorted, strongest first, never more than n long (only the winners
  -- get a record)
  for _, l in ipairs(lights) do
    if l.radius <= HAZE_MAX_RADIUS then
      local sx, sy = l.x - camX, l.y - camY
      if sx > -40 and sx < W + 40 and sy > -40 and sy < H + 40 then
        local strength = (l.r + l.g + l.b) / 3 * l.radius
        local m = #out
        if m < n or strength > out[m].s then
          local rec
          if m < n then
            rec = {}
            m = m + 1
          else
            rec = out[m] -- (the weakest drops out; its record is reused)
          end
          local j = m
          while j > 1 and out[j - 1].s < strength do
            out[j] = out[j - 1]
            j = j - 1
          end
          out[j] = rec
          local peak = math.max(l.r, l.g, l.b, 0.001)
          rec.x, rec.y, rec.s = sx / W, sy / H, strength
          rec.r, rec.g, rec.b = l.r / peak, l.g / peak, l.b / peak
        end
      end
    end
  end
  for _, l in ipairs(out) do
    l.s = math.min(1, l.s / 45) * math.min(1, dark * 2)
  end
  return out
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
    local bx = (seed * 7.13 + t * (1.5 + i % 5 * 0.8) + lighting.drift * 0.7 * depth) - camX * depth
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
  if softShader then
    softShader:send("texel", { 1 / W, 1 / H })
    love.graphics.setShader(softShader)
  end
  love.graphics.draw(canvas, 0, 0)
  if lightShader then
    love.graphics.setBlendMode("add", "premultiplied")
    love.graphics.draw(hazeCanvas, 0, 0)
  end
  love.graphics.setShader()
  love.graphics.pop()
end

return lighting
