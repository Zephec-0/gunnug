-- Starting points taken from Gunnug itself: canvas sizes around each character's in-game hitbox
-- (src/enemies.lua, src/needlemobs.lua, src/darkhunter.lua, config.player), palettes from the
-- game's colours, and puppet rigs with the hunter's limb proportions (src/playeranim.lua).
local doc = require("src.doc")
local rig = require("src.rig")
local U = require("src.util")

local presets = {}

local function hex(s)
  local r, g, b = U.parseHex(s)
  return { r, g, b, 1 }
end

local function rgb(r, g, b)
  return { r, g, b, 1 }
end

presets.palettes = {
  {
    name = "Gunnug",
    colors = {
      -- the hunter (playeranim COLORS), dark to light
      rgb(0.03, 0.02, 0.04), rgb(0.06, 0.05, 0.06), rgb(0.09, 0.08, 0.11), rgb(0.11, 0.09, 0.11),
      rgb(0.15, 0.13, 0.17), rgb(0.20, 0.19, 0.24), rgb(0.22, 0.19, 0.23), rgb(0.27, 0.23, 0.30),
      rgb(0.17, 0.17, 0.21), rgb(0.36, 0.36, 0.42), rgb(0.44, 0.43, 0.45), rgb(0.64, 0.63, 0.62),
      rgb(0.78, 0.77, 0.75), rgb(0.70, 0.72, 0.78), rgb(0.80, 0.82, 0.88),
      rgb(0.30, 0.17, 0.11), rgb(0.30, 0.24, 0.18), rgb(1.0, 0.86, 0.48), rgb(0.20, 0.80, 0.66),
      -- creature skins and blood
      rgb(0.26, 0.42, 0.32), rgb(0.56, 0.62, 0.62), rgb(0.62, 0.64, 0.66), rgb(0.74, 0.52, 0.48),
      rgb(0.8, 0.78, 0.84), hex("5a1414"), hex("8f1e1e"), hex("c03a2b"),
      -- desert dusk and fire
      hex("3b2a28"), hex("6b4a3a"), hex("a0714f"), hex("d4a373"), hex("efd0a0"),
      rgb(1.0, 0.5, 0.18), hex("ffd25a"), rgb(0.55, 1.0, 0.5), rgb(0.62, 0.74, 1.0),
    },
  },
  {
    name = "DB32",
    colors = {
      hex("000000"), hex("222034"), hex("45283c"), hex("663931"), hex("8f563b"), hex("df7126"),
      hex("d9a066"), hex("eec39a"), hex("fbf236"), hex("99e550"), hex("6abe30"), hex("37946e"),
      hex("4b692f"), hex("524b24"), hex("323c39"), hex("3f3f74"), hex("306082"), hex("5b6ee1"),
      hex("639bff"), hex("5fcde4"), hex("cbdbfc"), hex("ffffff"), hex("9badb7"), hex("847e87"),
      hex("696a6a"), hex("595652"), hex("76428a"), hex("ac3232"), hex("d95763"), hex("d77bba"),
      hex("8f974a"), hex("8a6f30"),
    },
  },
  {
    name = "Grays",
    colors = (function()
      local t = {}
      for i = 0, 15 do t[#t + 1] = rgb(i / 15, i / 15, i / 15) end
      return t
    end)(),
  },
}

-- Characters: canvas w/h, hitbox `hit` = {w, h}; ground ones stand on the bottom of the hitbox
presets.list = {
  { key = "custom", name = "Custom size", w = 32, h = 32 },
  { group = "Player" },
  { key = "hunter", name = "The Hunter", w = 32, h = 32, hit = { 8, 19 }, ground = true, rig = "humanoid" },
  { group = "Catacombs" },
  { key = "ghoul", name = "Ghoul", w = 32, h = 32, hit = { 12, 19 }, ground = true, rig = "humanoid" },
  { key = "miner", name = "Skeleton Miner", w = 32, h = 32, hit = { 10, 19 }, ground = true, rig = "humanoid" },
  { key = "bat", name = "Cave Bat", w = 24, h = 16, hit = { 10, 7 }, rig = "winged" },
  { key = "swarmbat", name = "Swarm Bat", w = 16, h = 16, hit = { 10, 7 }, rig = "winged" },
  { key = "spitter", name = "Spitter", w = 16, h = 16, hit = { 10, 8 } },
  { key = "hopper", name = "Mire Hopper", w = 24, h = 16, hit = { 12, 9 }, ground = true, rig = "quadruped" },
  { key = "bloater", name = "Bloater", w = 24, h = 24, hit = { 14, 14 } },
  { key = "wisp", name = "Cinder Wisp", w = 16, h = 16, hit = { 8, 8 } },
  { key = "worm", name = "Tunnel Worm", w = 16, h = 16, hit = { 4, 4 }, rig = "chain" },
  { key = "roller", name = "Cave Roller", w = 24, h = 16, hit = { 12, 10 }, ground = true },
  { key = "piranha", name = "Piranha", w = 16, h = 12, hit = { 8, 5 }, rig = "chain" },
  { key = "minigolem", name = "Marble Golem", w = 24, h = 32, hit = { 14, 20 }, ground = true, rig = "humanoid" },
  { group = "The Needle" },
  { key = "crow", name = "Needle Crow", w = 16, h = 16, hit = { 10, 8 }, rig = "winged" },
  { key = "cragram", name = "Crag Ram", w = 32, h = 24, hit = { 22, 15 }, ground = true, rig = "quadruped" },
  { key = "dustdevil", name = "Dust Devil", w = 24, h = 32, hit = { 14, 22 } },
  { key = "gargoyle", name = "Gargoyle", w = 24, h = 24, hit = { 14, 16 }, rig = "winged" },
  { group = "Bosses" },
  { key = "darkhunter", name = "The Dark Hunter", w = 32, h = 32, hit = { 8, 19 }, ground = true, rig = "humanoid" },
  { key = "warden", name = "The Ashen Warden", w = 48, h = 48, hit = { 24, 38 }, ground = true, rig = "humanoid" },
  { key = "matron", name = "The Mire Matron", w = 40, h = 32, hit = { 24, 18 }, ground = true, rig = "quadruped" },
  { key = "behemoth", name = "The Gas Behemoth", w = 40, h = 40, hit = { 28, 28 } },
  { key = "dreadbat", name = "The Dread Bat", w = 56, h = 40, hit = { 30, 21 }, rig = "winged" },
  { key = "golem", name = "The Marble Colossus", w = 112, h = 128, hit = { 74, 112 }, ground = true, rig = "humanoid" },
  { key = "queen", name = "The Sulfur Queen", w = 112, h = 112, hit = { 84, 84 } },
  { group = "Other" },
  { key = "icon", name = "Item / gun icon", w = 16, h = 16 },
  { key = "tile", name = "Tile", w = 16, h = 16 },
  { key = "prop", name = "Prop", w = 32, h = 32, ground = true },
}

presets.rigs = { "none", "humanoid", "quadruped", "winged", "chain" }

function presets.byKey(key)
  for _, p in ipairs(presets.list) do
    if p.key == key then return p end
  end
end

-- Hitbox guide in canvas pixels: fx = centre column, fy = the row below the feet (or bottom edge)
function presets.guide(p, w, h)
  local hw, hh = p.hit and p.hit[1] or 0, p.hit and p.hit[2] or 0
  local g = { w = hw, h = hh, ground = p.ground or false, fx = math.floor(w / 2) }
  if p.ground then
    g.fy = h - 2
  else
    g.fy = math.floor((h + hh) / 2)
  end
  return g
end

-- Rig templates --------------------------------------------------------------------------------------

-- Draws a placeholder stick along a bone into its part layer, so the rig is visible right away
local function stick(L, x1, y1, x2, y2, c, thick)
  local d = L.part.data
  local w, h = d:getDimensions()
  local o = -math.floor((thick - 1) / 2)
  U.line(math.floor(x1), math.floor(y1), math.floor(x2), math.floor(y2), function(x, y)
    for oy = 0, thick - 1 do
      for ox = 0, thick - 1 do
        local px, py = x + o + ox, y + o + oy
        if px >= 0 and py >= 0 and px < w and py < h then d:setPixel(px, py, c[1], c[2], c[3], 1) end
      end
    end
  end)
  doc.touch(L.part)
end

local DARK, MID, LIGHT, HEAD = rgb(0.27, 0.23, 0.30), rgb(0.44, 0.43, 0.45), rgb(0.64, 0.63, 0.62), rgb(0.78, 0.77, 0.75)

-- Adds a bone plus a part layer bound to it, with a stick drawn along it
local function part(D, layers, parent, name, x1, y1, x2, y2, color, thick, noLayer)
  local B = rig.add(D, parent and parent.id, x1, y1, x2, y2, name)
  if not noLayer then
    local L = doc.addLayer(D, name, "part")
    L.bone = B.id
    stick(L, x1, y1, x2, y2, color, thick)
    layers[name] = L
  end
  return B
end

-- Reorders the template's layers bottom to top
local function order(D, layers, names)
  local rest = {}
  for _, L in ipairs(D.layers) do
    local used = false
    for _, n in ipairs(names) do
      if layers[n] == L then used = true end
    end
    if not used then rest[#rest + 1] = L end
  end
  D.layers = rest
  for _, n in ipairs(names) do
    if layers[n] then D.layers[#D.layers + 1] = layers[n] end
  end
end

local templates = {}

-- A two-bone limb from (x, y): first bone at angle a1, second at a2 (radians, 0 = right, down = pi/2)
local function limb(D, Ls, parent, n1, n2, x, y, a1, l1, a2, l2, color, t)
  local kx, ky = x + math.cos(a1) * l1, y + math.sin(a1) * l1
  local B = part(D, Ls, parent, n1, x, y, kx, ky, color, t)
  part(D, Ls, B, n2, kx, ky, kx + math.cos(a2) * l2, ky + math.sin(a2) * l2, color, t)
  return B
end

-- The hunter's skeleton (playeranim.lua: thigh/shin 5.3, torso 6.4, arms 3.8 + 3.8 at 19px tall),
-- standing in a slight A-pose facing right so every bone can be grabbed
function templates.humanoid(D, g)
  local s = math.max(0.5, (g.h > 0 and g.h or D.h * 0.6) / 19)
  local cx, fy = g.fx + 0.5, g.fy
  local thigh, shin, torso, arm, head = 5.3 * s, 5.3 * s, 6.4 * s, 3.8 * s, 3.5 * s
  local hipY = fy - 0.5 - (thigh + shin) * math.cos(0.2)
  local neckY = hipY - torso
  local shY = neckY + s
  local t = math.max(1, U.round(s))
  local down = math.pi / 2
  local Ls = {}
  local pelvis = part(D, Ls, nil, "pelvis", cx, hipY, cx, hipY + 1.5 * s, MID, t, true)
  local torsoB = part(D, Ls, pelvis, "torso", cx, hipY, cx, neckY, LIGHT, t + 2)
  part(D, Ls, torsoB, "head", cx, neckY, cx, neckY - head, HEAD, t + 2)
  limb(D, Ls, torsoB, "arm back", "forearm back", cx, shY, down + 0.45, arm, down + 0.25, arm, DARK, t)
  limb(D, Ls, pelvis, "thigh back", "shin back", cx, hipY, down + 0.2, thigh, down + 0.2, shin, DARK, t)
  limb(D, Ls, pelvis, "thigh front", "shin front", cx, hipY, down - 0.2, thigh, down - 0.2, shin, MID, t)
  limb(D, Ls, torsoB, "arm front", "forearm front", cx, shY, down - 0.45, arm, down - 0.9, arm, MID, t)
  order(D, Ls, { "arm back", "forearm back", "thigh back", "shin back", "torso", "head",
    "thigh front", "shin front", "arm front", "forearm front" })
end

-- Four legs, a body facing right, head and tail
function templates.quadruped(D, g)
  local hw, hh = g.w > 0 and g.w or D.w * 0.6, g.h > 0 and g.h or D.h * 0.5
  local cx, fy = g.fx + 0.5, g.fy
  local leg = math.max(2, hh * 0.45)
  local by = fy - leg
  local half = math.max(2, hw * 0.35)
  local t = math.max(1, U.round(hh / 12))
  local Ls = {}
  local body = part(D, Ls, nil, "body", cx - half, by, cx + half, by, LIGHT, t + 2)
  part(D, Ls, body, "head", cx + half, by, cx + half + hw * 0.2, by - hh * 0.3, HEAD, t + 1)
  part(D, Ls, body, "tail", cx - half, by, cx - half - hw * 0.2, by - hh * 0.15, MID, t)
  local down = math.pi / 2
  local function legs(x, side, lean, col)
    limb(D, Ls, body, "leg " .. side, "foot " .. side, x, by, down + lean, leg / 2, down - lean, leg / 2, col, t)
  end
  legs(cx + half - 1, "front far", -0.35, DARK)
  legs(cx - half + 1, "back far", 0.35, DARK)
  legs(cx + half - 1, "front near", 0.25, MID)
  legs(cx - half + 1, "back near", -0.25, MID)
  order(D, Ls, { "leg front far", "foot front far", "leg back far", "foot back far", "tail", "body", "head",
    "leg front near", "foot front near", "leg back near", "foot back near" })
end

-- A body with two jointed wings (bats, crows, gargoyles)
function templates.winged(D, g)
  local hw, hh = g.w > 0 and g.w or D.w * 0.5, g.h > 0 and g.h or D.h * 0.5
  local cx = g.fx + 0.5
  local cy = g.ground and (g.fy - hh / 2) or (g.fy - hh / 2)
  local t = math.max(1, U.round(hh / 10))
  local span = math.min(D.w / 2 - 1, hw * 0.9)
  local Ls = {}
  local body = part(D, Ls, nil, "body", cx, cy - hh * 0.25, cx, cy + hh * 0.35, LIGHT, t + 1)
  part(D, Ls, body, "head", cx, cy - hh * 0.25, cx, cy - hh * 0.55, HEAD, t + 1)
  local wy = cy - hh * 0.15
  local lf = part(D, Ls, body, "wing far", cx, wy, cx - span * 0.5, wy - hh * 0.2, DARK, t)
  part(D, Ls, lf, "wingtip far", cx - span * 0.5, wy - hh * 0.2, cx - span, wy + hh * 0.1, DARK, t)
  local rn = part(D, Ls, body, "wing near", cx, wy, cx + span * 0.5, wy - hh * 0.2, MID, t)
  part(D, Ls, rn, "wingtip near", cx + span * 0.5, wy - hh * 0.2, cx + span, wy + hh * 0.1, MID, t)
  order(D, Ls, { "wing far", "wingtip far", "body", "head", "wing near", "wingtip near" })
end

-- A chain of segments for worms, fish and tails
function templates.chain(D, g)
  local hw = g.w > 0 and math.max(g.w, D.w * 0.6) or D.w * 0.7
  local hh = g.h > 0 and g.h or D.h * 0.3
  local cy = g.fy - hh / 2
  local n = 4
  local x0 = g.fx + 0.5 - hw / 2
  local seg = hw / n
  local t = math.max(1, U.round(hh * 0.6))
  local Ls, prev, names = {}, nil, {}
  for i = 1, n do
    local name = "segment " .. i
    prev = part(D, Ls, prev, name, x0 + (i - 1) * seg, cy, x0 + i * seg, cy, i == n and HEAD or LIGHT, t)
    names[#names + 1] = name
  end
  order(D, Ls, names)
end

function presets.applyRig(D, kind)
  local f = templates[kind]
  if not f then return false end
  local g = D.guide or { w = 0, h = 0, fx = math.floor(D.w / 2), fy = D.h - 2, ground = true }
  f(D, g)
  return true
end

-- A new document from a preset (and optional rig template)
function presets.newDoc(p, w, h, rigKind, palette)
  local D = doc.new(w, h, { name = p.key ~= "custom" and p.key or "sprite", palette = palette, preset = p.key, noLayer = true })
  if p.hit then D.guide = presets.guide(p, w, h) end
  if rigKind and rigKind ~= "none" then
    presets.applyRig(D, rigKind)
  else
    doc.addLayer(D, "Layer 1")
  end
  -- The in-game look, captured from Gunnug, as a faded reference underneath
  local ref = "refs/" .. p.key .. ".png"
  if p.key ~= "custom" and love.filesystem.getInfo(ref) then
    local ok, data = pcall(love.image.newImageData, ref)
    if ok then
      local L = doc.addLayer(D, "in-game reference", "ref", 1)
      doc.setData(L.part, data)
      local iw, ih = data:getDimensions()
      L.ox, L.oy = math.floor((w - iw) / 2), h - ih
    end
  end
  return D
end

return presets
