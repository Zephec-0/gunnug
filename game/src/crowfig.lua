-- The great crow the Crow Rider flies, drawn on the 1:1 pixel grid.
--
-- A black bird with a violet sheen: a feathered body, a hackled head with a heavy beak and a glowing
-- eye, a fan of tail feathers, and two wings of long feathers that fold, sweep and flex as they beat.
-- Every frame is rasterised pixel by pixel (the geometry is turned by the pitch before it is sampled,
-- never the picture), rim-lit, and kept as an image: the wingbeat is 16 frames, tilted five ways, and
-- the crow can be mid-dive (wings swept back, talons out) or rearing up to shriek (wings flung wide).
-- Facing is the picture mirrored.
--
--   crowfig.draw(x, y, f, flap, alpha, pose, pitch)   x, y: the middle of its body; f: facing (1 or -1);
--       flap: the wingbeat clock in radians; pose: nil (flying), "dive" or "wind"; pitch: tilt in radians
--       (positive: nose down)
--   crowfig.eye(x, y, f)    where the eye is, for its glow
local crowfig = {}

local floor, sin, cos, sqrt, abs, max, min = math.floor, math.sin, math.cos, math.sqrt, math.abs, math.max, math.min

local W, H = 100, 112 -- the picture's size and where the body's middle is in it
local OX, OY = 50, 62
crowfig.W, crowfig.H, crowfig.OX, crowfig.OY = W, H, OX, OY

local C = {
  ink = { 0.018, 0.012, 0.032 },
  d1 = { 0.040, 0.027, 0.066 },
  d2 = { 0.075, 0.050, 0.115 },
  d3 = { 0.125, 0.082, 0.195 },
  d4 = { 0.20, 0.13, 0.31 },
  sheen = { 0.38, 0.23, 0.58 },
  hi = { 0.60, 0.40, 0.84 },
  beak = { 0.17, 0.155, 0.20 },
  beakLo = { 0.095, 0.085, 0.12 },
  beakHi = { 0.36, 0.33, 0.42 },
  claw = { 0.30, 0.27, 0.34 },
  eye = { 0.95, 0.35, 1.0 },
  eyeHi = { 1.0, 0.85, 1.0 },
}
crowfig.colors = C

local function lerp(a, b, t)
  return a + (b - a) * t
end

-- Is (x, y) within the capsule from (ax, ay) to (bx, by), radius r0 at a and r1 at b? Returns the
-- position along it (0..1) and the side (-1..1 across it), or nil
local function capsule(x, y, ax, ay, bx, by, r0, r1)
  local dx, dy = bx - ax, by - ay
  local l2 = dx * dx + dy * dy
  local t = l2 > 0 and ((x - ax) * dx + (y - ay) * dy) / l2 or 0
  t = t < 0 and 0 or (t > 1 and 1 or t)
  local px, py = ax + dx * t, ay + dy * t
  local r = lerp(r0, r1, t)
  local ex, ey = x - px, y - py
  local d2 = ex * ex + ey * ey
  if d2 > r * r then
    return nil
  end
  local side = (ex * -dy + ey * dx) / (math.sqrt(l2) * r + 1e-6)
  return t, side
end

-- The wing: a list of feathers (capsules), furthest from the viewer's eye first
-- ψ is how far above (positive) the wing is held, sw how far it is swept back
local function wing(rx, ry, psi1, psi2, sw1, sw2, flex, scale)
  local L1, L2 = 17 * scale, 27 * scale
  local wx, wy = rx - L1 * cos(psi1) * sw1, ry - L1 * sin(psi1)
  local tx, ty = wx - L2 * cos(psi2) * sw2, wy - L2 * sin(psi2)
  local fs = {}
  local sx, sy = tx - rx, ty - ry
  local sl = sqrt(sx * sx + sy * sy) + 1e-6
  sx, sy = sx / sl, sy / sl
  local function feather(bx, by, len, k, tone)
    -- a feather streams backward, sweeping out toward the wingtip, bent by the beat
    local cxd, cyd = -1, 0.18 - flex
    local dx, dy = cxd + sx * 0.55 * k, cyd + sy * 0.55 * k
    local dl = sqrt(dx * dx + dy * dy)
    dx, dy = dx / dl, dy / dl
    fs[#fs + 1] = { bx, by, bx + dx * len, by + dy * len, 2.9 * scale, 0.7, tone }
  end
  -- (the long ones first, so the short coverts overlap their roots)
  for i = 0, 5 do
    local t = i / 5
    local len = (21 - 8 * t * t) * scale
    feather(lerp(wx, tx, t), lerp(wy, ty, t), len, 0.6 + t * 0.7, i % 2)
  end
  feather(tx, ty, 11 * scale, 1.6, 0)
  for i = 0, 4 do
    local t = i / 4
    feather(lerp(rx, wx, t), lerp(ry, wy, t), (14 - 3 * t) * scale, 0.3 + t * 0.3, (i + 1) % 2)
  end
  -- the leading edge, a rounded arm of covert feathers
  fs[#fs + 1] = { rx, ry, wx, wy, 5.2 * scale, 3.4 * scale, 2, arm = true }
  fs[#fs + 1] = { wx, wy, tx, ty, 3.6 * scale, 1.2, 2, arm = true }
  return fs
end

local function wingTone(fe, t, side, dark)
  local k = dark and 0.62 or 1
  local c
  if fe.arm then
    c = side < -0.15 and C.d4 or C.d3
    if side < -0.62 then
      c = C.sheen
    end
  else
    c = fe[7] == 0 and C.d2 or C.d3
    if t > 0.82 then
      c = C.d1
    end
    if side < -0.55 and t < 0.8 then
      c = C.d4
    end
  end
  return c, k
end

local function sampleWing(fs, x, y, dark)
  for i = #fs, 1, -1 do
    local fe = fs[i]
    local t, side = capsule(x, y, fe[1], fe[2], fe[3], fe[4], fe[5], fe[6])
    if t then
      return wingTone(fe, t, side, dark)
    end
  end
end

-- One frame ---------------------------------------------------------------------------------------

local function render(phase, pose, pitch)
  local beat1, beat2, sw, scale, talons, open
  local flex
  if pose == "dive" then
    beat1, beat2, sw, scale, talons, open, flex = 0.45, 0.2 + 0.35 * sin(phase * 2 + 1), 0.92, 0.95, true, true, 0.18
  elseif pose == "wind" then
    beat1, beat2, sw, scale, talons, open, flex = 1.25, 1.3, 0.3, 1.1, false, true, -0.1
  else
    local s1, s2 = sin(phase), sin(phase - 0.75)
    beat1, beat2 = 0.12 + 1.0 * s1, 0.12 + 1.05 * s2
    sw, scale, talons, open = 0.34, 1, false, false
    flex = cos(phase - 0.4) * 0.45
  end
  local sw2 = sw * (pose == "dive" and 1 or 1.15)
  local nearW = wing(4, -7, beat1, beat2, sw, sw2, flex, scale)
  local farW = wing(1, -8, beat1 * 0.92 + 0.1, beat2 * 0.92 + 0.1, sw, sw2, flex * 0.9, scale * 0.9)
  -- the tail's feathers
  local tail = {}
  for i = 0, 4 do
    local a = lerp(-0.28, 0.5, i / 4) + (pose == "dive" and -0.15 or 0)
    tail[#tail + 1] = { -15, 1.5, -15 - cos(a) * 22, 1.5 + sin(a) * 22 * 0.7, 3.2, 0.9, i % 2 }
  end

  local ca, sa = cos(pitch), sin(pitch)
  local grid = {}
  for py = 0, H - 1 do
    for px = 0, W - 1 do
      -- (back into the crow's own frame, untilted)
      local sx, sy = px - OX + 0.5, py - OY + 0.5
      local x, y = sx * ca + sy * sa, -sx * sa + sy * ca
      local c, k = nil, 1
      -- the eye
      if x >= 20 and x < 22.5 and y >= -12 and y < -9.5 then
        c = (x < 21 and y < -11) and C.eyeHi or C.eye
      end
      -- the near wing
      if not c then
        c, k = sampleWing(nearW, x, y, false)
      end
      if not c then
        k = 1
        -- the beak: an upper and a lower half
        local lowDrop = open and 5 or 0
        if x >= 22 and x < 35.5 then
          local u = (x - 22) / 13.5
          local top = lerp(-13.5, -6.5, u * u * 0.4 + u * 0.6)
          local bot = lerp(-5, -6, u)
          if y >= top and y < bot then
            c = (y < top + 1.2 and C.beakHi) or C.beak
            if u > 0.82 and y > bot - 2 then
              c = C.beakLo
            end
          end
          local top2 = lerp(-4.8, -5 + lowDrop * 0.55, u)
          local bot2 = lerp(-1.2, -2 + lowDrop, u * 0.9)
          if not c and y >= top2 + (open and u * 3 or 0) and y < bot2 + (open and u * 4 or 0) and u < 0.85 then
            c = C.beakLo
          end
        end
      end
      if not c then
        -- the head (hackles at its throat and nape) and the neck
        local hx, hy = x - 19, y + 9
        local inHead = hx * hx + hy * hy <= 6.8 * 6.8
        local t = capsule(x, y, 12, -3, 19, -9, 6.2, 5.4)
        if inHead or t then
          local nl = -(y + 9) / 6.8
          c = nl > 0.55 and C.d4 or (nl > -0.1 and C.d3 or (nl > -0.6 and C.d2 or C.d1))
          if inHead and nl > 0.78 and x < 21 then
            c = C.sheen
          end
        elseif x >= 9 and x <= 20 and y >= -3 and y <= 3 + (x - 9) * 0.18 and ((floor(x + y) % 3) == 0) then
          c = C.d2 -- (the throat's ruffle)
        elseif x >= 11 and x <= 15 and y >= -17 and y <= -12 and (x - 11) + (y + 17) * 0.5 < 5 - ((floor(x) % 2) * 2) then
          c = C.d2 -- (a tuft on the nape)
        end
      end
      if not c then
        -- the torso: a broad chest tapering to the tail
        local rear = x < 0
        local ry = 9.8 * (rear and (1 + 0.40 * x / 20) or 1)
        local rx = 20
        local cy0 = rear and 0.5 + (-x * 0.05) or 0.5
        local ex, ey = x / rx, (y - cy0) / ry
        local d = ex * ex + ey * ey
        local chest = (x - 12) * (x - 12) + (y + 0.5) * (y + 0.5) <= 9.5 * 9.5
        if d <= 1 or chest then
          local nl = -((y - cy0) / ry)
          local tone
          if nl > 0.74 then
            tone = C.sheen
          elseif nl > 0.30 then
            tone = C.d4
          elseif nl > -0.25 then
            tone = C.d3
          elseif nl > -0.65 then
            tone = C.d2
          else
            tone = C.d1
          end
          -- the plumage: rows of feathers, each edge a shade down
          local row = floor((y + 20) / 3)
          local col = floor((x + 40 + (row % 2) * 2) / 4)
          if (floor(y + 20) % 3 == 2) and ((x + 40 + (row % 2) * 2) % 4 < 2.2) and nl < 0.7 then
            tone = (tone == C.d4 and C.d3) or (tone == C.d3 and C.d2) or C.d1
          end
          c = tone
        end
      end
      if not c then
        -- the legs: tucked up under it, or reaching out forward with the talons spread
        local legs = talons and { { 4, 8, 12, 15, 5 }, { -1, 8, 8, 16, 5 } } or { { 3, 8, 4, 13, 1 }, { -2, 8, -2, 13, 1 } }
        for _, lg in ipairs(legs) do
          if capsule(x, y, lg[1], lg[2], lg[3], lg[4], 1.5, 1.1) then
            c = C.beak
          end
          if talons then
            for s = -1, 1 do
              if capsule(x, y, lg[3], lg[4], lg[3] + 5 + s, lg[4] + 2.2 * s + 1.5, 1, 0.5) then
                c = C.claw
              end
            end
          elseif capsule(x, y, lg[3], lg[4], lg[3] + 3, lg[4] + 1.5, 1, 0.5) then
            c = C.claw
          end
        end
      end
      if not c then
        for i = #tail, 1, -1 do
          local fe = tail[i]
          local t, side = capsule(x, y, fe[1], fe[2], fe[3], fe[4], fe[5], fe[6])
          if t then
            c = (fe[7] == 0 and C.d2 or C.d3)
            if t > 0.8 then
              c = C.d1
            elseif side < -0.5 then
              c = C.d4
            end
            break
          end
        end
      end
      if not c then
        c, k = sampleWing(farW, x, y, true)
      end
      if c then
        grid[py * W + px] = { c[1] * k, c[2] * k, c[3] * k }
      end
    end
  end

  -- A violet rim along every upper edge (no outline: the crow stands on its own colours)
  local data = love.image.newImageData(W, H)
    for py = 0, H - 1 do
    for px = 0, W - 1 do
      local g = grid[py * W + px]
      if g then
        local above = py > 0 and grid[(py - 1) * W + px]
        if not above and g[3] > 0.1 then
          g = { lerp(g[1], C.hi[1], 0.55), lerp(g[2], C.hi[2], 0.55), lerp(g[3], C.hi[3], 0.55) }
        end
        data:setPixel(px, py, g[1], g[2], g[3], 1)
      end
    end
  end
  local img = love.graphics.newImage(data)
  img:setFilter("nearest", "nearest")
  return img
end

-- Drawing -------------------------------------------------------------------------------------------

local PHASES, PITCHES = 16, 5
local cache = {}

local function frame(phase, pose, pitch)
  local pi2 = math.pi * 2
  local pb = pose and 0 or floor((phase % pi2) / pi2 * PHASES + 0.5) % PHASES
  local tb = max(-2, min(2, floor(pitch / 0.2 + (pitch >= 0 and 0.5 or -0.5))))
  if pose == "dive" then
    tb = max(-1, min(4, floor(pitch / 0.22 + 0.5)))
  end
  local key = (pose or "fly") .. ":" .. pb .. ":" .. tb
  local img = cache[key]
  if not img then
    img = render(pb / PHASES * pi2, pose, tb * (pose == "dive" and 0.22 or 0.2))
    cache[key] = img
  end
  return img
end

function crowfig.draw(x, y, f, flap, alpha, pose, pitch)
  local img = frame(flap or 0, pose, pitch or 0)
  love.graphics.setColor(1, 1, 1, alpha or 1)
  love.graphics.draw(img, floor(x), floor(y), 0, f < 0 and -1 or 1, 1, OX, OY)
end

function crowfig.eye(x, y, f)
  return x + (f < 0 and -1 or 1) * 21, y - 10.5
end

return crowfig
