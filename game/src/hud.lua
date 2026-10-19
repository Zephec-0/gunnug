-- Screen-space HUD: the health flask and gun status (chambers + reload), Noita-style
-- in the top-right corner.
local input = require("src.input")
local fontFace = require("src.fonts")
local coinstack = require("src.coinstack")

local hud = {}

local function font(size)
  return fontFace.get(size)
end

-- Gradients -------------------------------------------------------------------
-- Health bars are drawn at the window's full resolution, with the colour
-- changing smoothly down every pixel row (vertex-coloured quads).

-- A rectangle shaded from top colour to bottom colour
function hud.gradRect(x, y, w, h, top, bottom, alpha)
  alpha = alpha or 1
  local mesh = love.graphics.newMesh({
    { x, y, 0, 0, top[1], top[2], top[3], alpha },
    { x + w, y, 1, 0, top[1], top[2], top[3], alpha },
    { x + w, y + h, 1, 1, bottom[1], bottom[2], bottom[3], alpha },
    { x, y + h, 0, 1, bottom[1], bottom[2], bottom[3], alpha },
  }, "fan", "static")
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(mesh)
end

-- Blood: a dark crimson, glossier at the surface
local LIQUID_TOP = { 0.70, 0.07, 0.11 }
local LIQUID_MID = { 0.45, 0.03, 0.07 }
local LIQUID_BOTTOM = { 0.17, 0.01, 0.035 }

-- The player's health: a round glass flask of dark blood. The surface ripples in
-- hard pixel steps; bubbles rise now and then as arcade-style pixel sprites (a
-- little ring with a glint) and pop at the top. When health is low (under 30%)
-- the blood boils: the surface churns, bubbles are big and constant, spray
-- flies, the flask shakes and glows.
local bubbles, drops = {}, {}
local lastBarTime

-- The liquid's vertices and mesh are kept and refilled every frame (a new
-- mesh and ~800 little tables a frame was the biggest source of garbage in
-- the game, and so of the collector's pauses)
local barVerts, barMesh = {}, nil
local function barVert(k, vx, vy, r, g, b)
  local v = barVerts[k]
  if not v then
    v = { 0, 0, 0, 0, 0, 0, 0, 1 }
    barVerts[k] = v
  end
  v[1], v[2], v[5], v[6], v[7] = vx, vy, r, g, b
end
local RING, FILL, GLINT = { 0.80, 0.16, 0.19 }, { 0.30, 0.02, 0.05 }, { 1.0, 0.62, 0.62 }

-- The health bottle: a glass bottle lying at 45 degrees, its neck up and to the left, open at the top. It is
-- drawn on the screen's own pixel grid (cells of CELL pixels, the same as the coins and ammo), so every edge is
-- a stepped pixel line: each cell is tested against the bottle's outline in its own leaning frame, and the ones
-- on the edge become the glass. The blood stays level across the screen however the bottle leans, pooling in
-- the low corner; its surface ripples in whole-cell steps and tilts and bobs against the hunter's
-- accelerations. Bubbles are kept relative to the bottle's centre and only drawn inside the glass.
local GLASS_LIT, GLASS, GLASS_DARK = { 0.86, 0.84, 0.94 }, { 0.66, 0.62, 0.76 }, { 0.50, 0.46, 0.60 }
local slosh, bob = { a = 0, v = 0 }, { a = 0, v = 0 } -- the surface's tilt, and its bob (springs)
local lastPvx, lastPvy
local K = math.sqrt(0.5)

-- Profiles, in units: L x T the body, NL x NT the neck, corner = the chamfer on the far corners and
-- shoulder = how far the shoulders slope in to the neck (45 degrees in the bottle's frame, which is
-- straight horizontal and vertical steps on the screen)
local VARIANTS = {
  { L = 30, T = 19, NL = 7, NT = 9, corner = 5, shoulder = 5 }, -- classic flask
  { L = 38, T = 14, NL = 6, NT = 7, corner = 3, shoulder = 4 }, -- slim vial
  { L = 24, T = 22, NL = 5, NT = 12, corner = 7, shoulder = 5 }, -- squat jar
  { L = 30, T = 19, NL = 9, NT = 7, corner = 7, shoulder = 6, ring = true }, -- apothecary, ringed lip
}
hud.bottleVariant = 4

-- The bottle's half-width at a (units along it from the body's centre), or nil beyond its ends
local function halfWidth(v, a)
  local hl, ht, nt = v.L / 2, v.T / 2, v.NT / 2
  if a > hl or a < -hl - v.NL then
    return nil
  end
  if a >= -hl then
    local w = ht
    local fromEnd = hl - a
    if fromEnd < v.corner then
      -- a rounded corner: a quarter circle of radius corner
      local d = v.corner - fromEnd
      w = ht - (v.corner - math.sqrt(math.max(0, v.corner * v.corner - d * d)))
    end
    local fromNeck = a + hl
    if fromNeck < v.shoulder then
      -- a rounded shoulder, bulging out from the neck
      local t = fromNeck / v.shoulder
      w = math.min(w, nt + (ht - nt) * (1 - (1 - t) * (1 - t)))
    end
    return w
  end
  if v.ring and (a < -hl - v.NL + 1.2 or (a > -hl - v.NL + 2.4 and a < -hl - v.NL + 3.6)) then
    return nt + 1.2
  end
  return nt
end

-- The screen-space extent of the bottle from its centre, in pixels: left, top, right, bottom
-- One pixel of the HUD's art: a world pixel at the usual zoom, so it matches the game's own grain
function hud.cell(u)
  return math.max(1, math.floor(u / require("src.config").UI_SCALE + 0.5))
end

function hud.bottleExtent(u)
  local v = VARIANTS[hud.bottleVariant]
  local hl, ht = v.L / 2, v.T / 2
  local l, t, r, b = math.huge, math.huge, -math.huge, -math.huge
  for _, ab in ipairs({ { -hl, -ht }, { -hl, ht }, { hl, -ht }, { hl, ht }, { -hl - v.NL, -v.NT / 2 - 1.2 }, { -hl - v.NL, v.NT / 2 + 1.2 } }) do
    local x, y = (ab[1] - ab[2]) * K * u, (ab[1] + ab[2]) * K * u
    l, t, r, b = math.min(l, x), math.min(t, y), math.max(r, x), math.max(b, y)
  end
  return l, t, r, b
end

-- Draws the bottle centred at (cx, cy); u screen pixels to a unit
function hud.drawHealthBar(player, u, cx, cy)
  local now = love.timer.getTime()
  local dt = math.min(0.1, lastBarTime and now - lastBarTime or 0)
  lastBarTime = now
  local v = VARIANTS[hud.bottleVariant]
  local frac = math.max(0, math.min(1, player.hp / player.maxHp))
  local low = frac < 0.3 and (1 - frac / 0.3) or 0 -- 0 = fine, 1 = nearly dead

  -- Below about 18% it shakes a little and pulses red (alarm: 0 = fine, rising quickly to a gentle 0.6)
  local alarm = frac < 0.18 and math.min(1, (0.18 - frac) / 0.08) * (0.45 + 0.15 * (1 - frac / 0.18)) or 0
  if alarm > 0 then
    cx = cx + (love.math.random() - 0.5) * alarm * 0.8 * u
    cy = cy + (love.math.random() - 0.5) * alarm * 0.8 * u
  end
  -- The damage the bottle has taken: 0 whole, 1 dinged and scratched (under 2/3 health), 2 cracked, broken
  -- and shot through (under 1/3)
  local stage = frac > 2 / 3 and 0 or (frac > 1 / 3 and 1 or 2)
  local c = hud.cell(u) -- one pixel of HUD art
  local hl, ht = v.L / 2, v.T / 2
  local xL, yTop, xR, yBot = hud.bottleExtent(u)
  xL, yTop, xR, yBot = cx + xL, cy + yTop, cx + xR, cy + yBot
  -- The body's own vertical span (for the level), without the neck
  local bTop, bBot = cy - (hl + ht) * K * u, cy + (hl + ht) * K * u

  local PULSE_R = 9 -- how far (units) a pulse spreads from the glass before it fades
  local pulsePhase = (now * (0.9 + alarm)) % 1
  local pulseR = pulsePhase * PULSE_R
  local margin = alarm > 0 and (PULSE_R + 2) * u or 0
  local chips, scratches, cracks, hole = {}, {}, {}, nil
  if stage >= 1 then
    -- Dings: small bites out of the glass's edge; and scratches
    chips = { { hl, -2, 0.9 }, { 4, ht, 0.8 } }
    scratches = { { -8, -2, -3, -4 }, { 2, 5, 8, 3 }, { -1, 1, 3, 0.5 } }
  end
  if stage >= 2 then
    -- Broken: a corner gone, the lip chipped, cracks spreading from a bullet hole clean through
    chips = { { hl, -2, 1.1 }, { 4, ht, 1.0 }, { -6, -ht, 0.9 }, { hl - 3, ht - 0.5, 0.9 } } -- (small dents, not bites)
    scratches = { { -8, -2, -3, -4 }, { 2, 5, 8, 3 }, { -1, 1, 3, 0.5 }, { 6, -6, 10, -3 }, { -12, 3, -9, 5 } }
    hole = { -2, -3, 1.3 } -- (in the upper half, toward the neck)
    local hx, hy = hole[1], hole[2]
    local function crack(...)
      local p = { ... }
      cracks[#cracks + 1] = { hx + p[1], hy + p[2], hx + p[3], hy + p[4] }
    end
    crack(0, 0, -4, -3) crack(-4, -3, -7, -6) crack(0, 0, -3, 3) crack(-3, 3, -6, 4.5)
    crack(0, 0, 1, -4) crack(1, -4, 2, -7) crack(0, 0, 4, 3) crack(4, 3, 8, 4) crack(4, 3, 6, 6.5)
    crack(0, 0, 5, -1) crack(5, -1, 9, -3) crack(-4, -3, -6, -2.5) crack(1, -4, -1.5, -6) crack(8, 4, 10, 6) crack(-6, 4.5, -9, 5.5)
  end
  local holeR = hole and hole[3] or -1
  local function distSeg(a, b, s)
    local ax, ay, bx, by = s[1], s[2], s[3], s[4]
    local dx, dy = bx - ax, by - ay
    local t = math.max(0, math.min(1, ((a - ax) * dx + (b - ay) * dy) / (dx * dx + dy * dy)))
    return math.sqrt((a - ax - dx * t) ^ 2 + (b - ay - dy * t) ^ 2)
  end

  -- Sloshing: the surface tilts and bobs against the hunter's accelerations, springing back
  local pb = player.body
  if pb then
    if lastPvx then
      slosh.v = slosh.v - (pb.vx - lastPvx) * 0.0035
      bob.v = bob.v + (pb.vy - lastPvy) * 0.03
    end
    lastPvx, lastPvy = pb.vx, pb.vy
  end
  local steps = math.max(1, math.floor(dt * 120))
  for _ = 1, steps do
    local h = dt / steps
    slosh.v = slosh.v + (-90 * slosh.a - 4.5 * slosh.v) * h
    slosh.a = math.max(-0.45, math.min(0.45, slosh.a + slosh.v * h))
    bob.v = bob.v + (-110 * bob.a - 5 * bob.v) * h
    bob.a = math.max(-2.5, math.min(2.5, bob.a + bob.v * h))
  end
  -- (never brimful: even at full health the level stays below the neck)
  local range = (bBot - bTop) * 0.74
  local surface = bBot - frac * range + bob.a * u
  local amp = (0.55 + 2.0 * low) * u * 0.5
  local speed = 2 + 9 * low
  local function ripple(x)
    local raw = amp * (0.5 + 0.5 * math.sin(x * 0.045 / u * 4.8 + now * speed) + 0.4 * math.sin(x * 0.11 + now * speed * 1.7))
    return math.floor(raw / c + 0.5) * c
  end
  local function surfaceAt(x)
    return surface + math.floor(slosh.a * (x - cx) / c + 0.5) * c + ripple(x)
  end
  local flare = low * (0.5 + 0.5 * math.sin(now * 10)) * 0.25

  -- What a point is: 0 outside, 1 the bottle, 2 just past the open lip (so the lip has no edge). Also a, b
  local function probe(px, py)
    local dx, dy = (px - cx) / u, (py - cy) / u
    local a, b = (dx + dy) * K, (dy - dx) * K
    local w = halfWidth(v, a)
    if w and math.abs(b) <= w then
      for _, ch in ipairs(chips) do
        if (a - ch[1]) ^ 2 + (b - ch[2]) ^ 2 < ch[3] * ch[3] then
          return 0, a, b
        end
      end
      return 1, a, b
    end
    if a < -hl - v.NL and a > -hl - v.NL - 2 and math.abs(b) <= v.NT / 2 then
      return 2, a, b
    end
    return 0, a, b
  end

  for gx = math.floor((xL - margin) / c), math.ceil((xR + margin) / c) do
    for gy = math.floor((yTop - margin) / c), math.ceil((yBot + margin) / c) do
      local px, py = gx * c + c / 2, gy * c + c / 2
      local state, a, b = probe(px, py)
      local dHole = hole and math.sqrt((a - hole[1]) ^ 2 + (b - hole[2]) ^ 2) or 99
      if state == 0 and alarm > 0 then
        -- The pulse: a red ring spreading out from the glass, thinning as it goes
        local aa = math.max(-hl - v.NL, math.min(hl, a))
        local w = halfWidth(v, aa) or 0
        local d = math.sqrt(math.max(0, math.abs(b) - w) ^ 2 + (a - aa) ^ 2)
        if d > 0 and d > pulseR - 1.1 and d <= pulseR + 0.4 then
          love.graphics.setColor(1, 0.12, 0.12, (1 - pulsePhase) ^ 1.5 * 0.5 * alarm / 0.6)
          love.graphics.rectangle("fill", gx * c, gy * c, c, c)
        end
      end
      if state == 1 and dHole < holeR then
        -- (shot clean through: nothing here at all)
      elseif state == 1 then
        local edge = probe(px - c, py) == 0 or probe(px + c, py) == 0 or probe(px, py - c) == 0 or probe(px, py + c) == 0
        if edge then
          local col = b < -ht * 0.4 and GLASS_LIT or (b > ht * 0.4 and GLASS_DARK or GLASS)
          love.graphics.setColor(col[1], col[2], col[3], 0.95)
        elseif frac > 0 and py >= surfaceAt(px) then
          -- The blood: blended down from the bright top through the red to the deep base
          local k = math.min(1, (py - surface) / range)
          local c1, c2, kk
          if k < 0.35 then
            c1, c2, kk = LIQUID_TOP, LIQUID_MID, k / 0.35
          else
            c1, c2, kk = LIQUID_MID, LIQUID_BOTTOM, (k - 0.35) / 0.65
          end
          love.graphics.setColor(
            math.min(1, c1[1] + (c2[1] - c1[1]) * kk + flare * (1 - k)),
            c1[2] + (c2[2] - c1[2]) * kk + flare * 0.6 * (1 - k),
            c1[3] + (c2[3] - c1[3]) * kk + flare * 0.6 * (1 - k)
          )
        else
          -- The empty glass: see-through, with the back wall showing as a lighter band just inside the
          -- lit edge, a darker one inside the shaded edge, and a faint reflection streak
          local near = probe(px - 2 * c, py) == 0 or probe(px + 2 * c, py) == 0 or probe(px, py - 2 * c) == 0 or probe(px, py + 2 * c) == 0
          if near and b < 0 then
            love.graphics.setColor(0.62, 0.58, 0.78, 0.34)
          elseif near then
            love.graphics.setColor(0.10, 0.07, 0.16, 0.5)
          elseif b < -ht * 0.62 and b > -ht * 0.5 - 1.2 and a > -hl + 4 and a < hl - 8 then
            love.graphics.setColor(1, 1, 1, 0.16)
          else
            love.graphics.setColor(0.24, 0.20, 0.34, 0.32)
          end
        end
        love.graphics.rectangle("fill", gx * c, gy * c, c, c)
        -- The scorched ring round the bullet hole
        if not edge and dHole < holeR + 1.1 then
          love.graphics.setColor(0.04, 0.02, 0.05, 0.85)
          love.graphics.rectangle("fill", gx * c, gy * c, c, c)
        end
        -- A bright line along the surface, and a glint on the lit side's glass
        if not edge and frac > 0 and py >= surfaceAt(px) and py < surfaceAt(px) + c then
          love.graphics.setColor(0.95, 0.30, 0.32, 0.55)
          love.graphics.rectangle("fill", gx * c, gy * c, c, c)
        elseif edge and b < -ht * 0.4 and a > -hl + 3 and a < hl - 9 then
          love.graphics.setColor(1, 1, 1, 0.35)
          love.graphics.rectangle("fill", gx * c, gy * c, c, c)
        end
      end
    end
  end

  -- Scratches and cracks: jagged lines plotted on the glass's own cell grid, so they match its pixel density
  if #scratches > 0 or #cracks > 0 then
    local f = c
    local function isEdge(x, y)
      return probe(x - c, y) == 0 or probe(x + c, y) == 0 or probe(x, y - c) == 0 or probe(x, y + c) == 0
    end
    local function dot(a, b, col, ox)
      local x, y = cx + (a - b) * K * u, cy + (a + b) * K * u
      x, y = math.floor(x / f) * f, math.floor(y / f) * f
      if probe(x + f / 2, y + f / 2) == 1 and not isEdge(x + f / 2, y + f / 2) and not (hole and (a - hole[1]) ^ 2 + (b - hole[2]) ^ 2 < (holeR + 0.6) ^ 2) then
        love.graphics.setColor(col[1], col[2], col[3], col[4])
        love.graphics.rectangle("fill", x + (ox or 0), y + (ox or 0), f, f)
      end
    end
    local function jag(a, b)
      local n = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
      return (n - math.floor(n)) - 0.5
    end
    local function line(seg, col, shadow, jagged)
      local ax, ay, bx, by = seg[1], seg[2], seg[3], seg[4]
      local len = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
      local pieces = jagged and math.max(1, math.floor(len / 1.6)) or 1
      local px, py = ax, ay
      for i = 1, pieces do
        local t = i / pieces
        local qx, qy = ax + (bx - ax) * t, ay + (by - ay) * t
        if jagged and i < pieces then
          local nx, ny = -(by - ay) / len, (bx - ax) / len
          local j = jag(qx, qy) * 0.9
          qx, qy = qx + nx * j, qy + ny * j
        end
        local steps = math.max(1, math.ceil(math.sqrt((qx - px) ^ 2 + (qy - py) ^ 2) * u / f * 1.5))
        for k = 0, steps do
          local m = k / steps
          local a, b = px + (qx - px) * m, py + (qy - py) * m
          if shadow then
            dot(a + 0.25, b + 0.25, { 0.03, 0.02, 0.06, 0.5 }, 0)
          end
          dot(a, b, col)
        end
        px, py = qx, qy
      end
    end
    for _, sg in ipairs(scratches) do
      line(sg, { 1, 1, 1, 0.38 }, false, false)
    end
    for _, sg in ipairs(cracks) do
      line(sg, { 0.97, 0.95, 1, 0.75 }, false, true)
    end
    if hole then
      -- the web: arcs round the hole
      for i = 0, 140 do
        local th = i / 140 * math.pi * 2
        if math.sin(th * 3 + 1) > 0.15 then
          local rr = 3.3 + jag(th, 1) * 0.5
          dot(hole[1] + math.cos(th) * rr, hole[2] + math.sin(th) * rr, { 0.97, 0.95, 1, 0.65 })
        end
      end
    end
  end

  -- Bubbles: a trickle when healthy, a roiling boil when low. Tiny pixel sprites on the cell grid, rising in
  -- whole-pixel steps and popping into spray at the surface.
  local function inside(bx, by)
    return probe(cx + bx, cy + by) == 1 and probe(cx + bx + 2 * c, cy + by + 2 * c) == 1 and probe(cx + bx - 2 * c, cy + by - 2 * c) == 1
  end
  if frac > 0.08 then
    local rate = 0.8 + low * 14
    if love.math.random() < rate * dt then
      local kind = love.math.random() < (0.35 + low * 0.35) and 3 or (love.math.random() < 0.5 and 2 or 1)
      local a, b = (love.math.random() - 0.5) * (v.L - 4) * u, (love.math.random() - 0.5) * (v.T - 4) * u
      local bx, by = (a - b) * K, (a + b) * K
      if cy + by > surface + 3 * c then
        bubbles[#bubbles + 1] = {
          px = bx,
          py = by,
          size = kind,
          vy = (3 + love.math.random() * 5) * u * (1 + low * 2.5),
          sway = love.math.random() * 6.3,
          swayRate = 2 + love.math.random() * 3 + low * 4,
        }
      end
    end
  end
  local function pix(bx, by, col, al)
    love.graphics.setColor(col[1], col[2], col[3], al or 1)
    love.graphics.rectangle("fill", math.floor((cx + bx) / c) * c, math.floor((cy + by) / c) * c, c, c)
  end
  for i = #bubbles, 1, -1 do
    local b = bubbles[i]
    b.py = b.py - b.vy * dt
    b.px = b.px + math.sin(now * b.swayRate + b.sway) * u * (0.5 + low) * dt * 6
    local bx, by = b.px, b.py
    if cy + by <= surfaceAt(cx + bx) + c * 0.5 or not inside(bx, by) then
      -- Pops at the surface; a boiling one throws off spray
      if low > 0.1 and inside(bx, by) then
        for _ = 1, 2 + math.floor(low * 3) do
          drops[#drops + 1] = { x = cx + bx, y = cy + by, vx = (love.math.random() - 0.5) * 30 * u, vy = -(10 + love.math.random() * 24 * (0.5 + low)) * u, life = 0.35 }
        end
      end
      table.remove(bubbles, i)
    else
      if b.size == 1 then
        pix(bx, by, RING)
      elseif b.size == 2 then
        pix(bx, by, RING) pix(bx + c, by, RING) pix(bx, by + c, RING) pix(bx + c, by + c, FILL)
        pix(bx, by, GLINT, 0.9)
      else
        for ox = 0, 2 do
          for oy = 0, 2 do
            if not (ox == 1 and oy == 1) then
              pix(bx + ox * c, by + oy * c, RING)
            end
          end
        end
        pix(bx + c, by + c, FILL)
        pix(bx, by, GLINT)
      end
    end
  end
  -- Blood weeping from the bullet hole while it is under the surface
  if hole then
    local hx, hy = cx + (hole[1] - hole[2]) * K * u, cy + (hole[1] + hole[2]) * K * u
    if hy > surfaceAt(hx) and love.math.random() < 2.5 * dt then
      drops[#drops + 1] = { x = hx + (love.math.random() - 0.5) * u, y = hy + 2 * u, vx = (love.math.random() - 0.5) * 6 * u, vy = 4 * u, life = 0.6 }
    end
  end
  for i = #drops, 1, -1 do
    local d = drops[i]
    d.life = d.life - dt
    d.vy = d.vy + 90 * u * dt
    d.x, d.y = d.x + d.vx * dt, d.y + d.vy * dt
    if d.life <= 0 then
      table.remove(drops, i)
    else
      love.graphics.setColor(0.72, 0.10, 0.14, math.min(1, d.life * 4))
      love.graphics.rectangle("fill", math.floor(d.x / c) * c, math.floor(d.y / c) * c, c, c)
    end
  end
  return xL, yTop, xR, yBot
end

function hud.font(scale)
  return font(math.max(10, math.floor(scale * 4)))
end

local function shadowText(text, x, y, f)
  love.graphics.setFont(f)
  local r, g, b, a = love.graphics.getColor()
  love.graphics.setColor(0, 0, 0, a)
  love.graphics.print(text, x + 2, y + 2)
  love.graphics.setColor(r, g, b, a)
  love.graphics.print(text, x, y)
end

function hud.draw(player, scale)
  local ww = love.graphics.getWidth()
  local u = scale -- one game pixel at the current scale
  local f = hud.font(scale)
  local margin = 6 * u

  -- Health: the bottle, top right, lying at 45 degrees with its number inside. The marks sit at its upper
  -- right (the sigil over its count) and the gold's coin stack at its lower left.
  local el, et, er = hud.bottleExtent(u)
  local bcx, bcy = ww - margin - er, margin - et
  local bl, _, _, bb = hud.drawHealthBar(player, u, bcx, bcy)
  love.graphics.setColor(1, 1, 1)
  local hpText = tostring(math.floor(player.hp))
  local hf = hud.font(scale * (player.hp < 20 and 2.1 or 1.4)) -- (bigger still when nearly gone)
  local tx, ty = math.floor(bcx - hf:getWidth(hpText) / 2), math.floor(bcy - hf:getHeight() / 2)
  -- The blood's red with a light grey outline
  love.graphics.setFont(hf)
  local o = math.max(1, math.floor(scale * 0.35))
  love.graphics.setColor(0.80, 0.82, 0.88)
  for dx = -o, o, o do
    for dy = -o, o, o do
      if dx ~= 0 or dy ~= 0 then
        love.graphics.print(hpText, tx + dx, ty + dy)
      end
    end
  end
  love.graphics.setColor(0.78, 0.10, 0.15)
  love.graphics.print(hpText, tx, ty)
  local belowFlask = bb + 2 * u
  local meta = require("src.meta")
  local fh = f:getHeight()

  local profile = require("src.save").profile()
  if profile and (profile.marks > 0 or (profile.stats.marksEarned or 0) > 0) then
    local s = math.max(1, math.floor(u * 0.75 + 0.5))
    local markText = tostring(profile.marks)
    local mx = math.floor(ww - margin - math.max(7 * s, f:getWidth(markText)) / 2)
    local c = meta.SIGIL_COLOR
    meta.drawSigil(mx - math.floor(3.5 * s), math.floor(margin - 1 * s), s)
    love.graphics.setColor(c[1], c[2], c[3])
    shadowText(markText, math.floor(mx - f:getWidth(markText) / 2), math.floor(margin + 7 * s), f)
  end

  local goldText = tostring(player.inventory.gold)
  local cp = hud.cell(u)
  local stackRight = bcx + el - u
  coinstack.draw(player.inventory.gold, stackRight, bb, cp)
  love.graphics.setColor(1.0, 0.88, 0.5)
  shadowText(goldText, math.floor(stackRight + 2 * u), math.floor(bb - fh), f)

  if player.gun2 then
    -- Akimbo: the other hand's magazine sits behind the first's, faded to a purple-grey
    hud.drawGunStatus(player.gun2, ww, margin, belowFlask, u, f, { behind = true })
  end
  if player.gun then
    hud.drawGunStatus(player.gun, ww, margin, belowFlask, u, f)
  end

  -- Under the bottle, one column: a row for each thing carried (an icon and "x count"): dynamite, flasks,
  -- vault keys, silver bells. Every row is centred in the column and spaced out so none touches another.
  do
    local inv = player.inventory
    local s = hud.cell(u)
    local f = hud.font(scale * 0.9)
    local fh = f:getHeight()
    local cx = math.floor(ww - margin - 7 * u)
    local y = math.floor(belowFlask + 20 * u)
    local nb = 0
    for _ in pairs(inv.relics or {}) do
      nb = nb + 1
    end
    local rows = {
      { inv.dynamite or 0, function(ix, iy)
        love.graphics.setColor(0.75, 0.16, 0.12)
        love.graphics.rectangle("fill", ix + s, iy + 3 * s, 3 * s, 7 * s)
        love.graphics.setColor(0.95, 0.85, 0.65)
        love.graphics.rectangle("fill", ix + s, iy + 5 * s, 3 * s, s)
        love.graphics.setColor(0.6, 0.5, 0.35)
        love.graphics.rectangle("fill", ix + 2 * s, iy + s, s, 2 * s)
        love.graphics.setColor(1, 0.75, 0.35)
        love.graphics.rectangle("fill", ix + 2 * s, iy, s, s)
      end },
      { inv.flasks or 0, function(ix, iy)
        love.graphics.setColor(0.45, 0.85, 0.55)
        love.graphics.rectangle("fill", ix + s, iy + 4 * s, 3 * s, 6 * s)
        love.graphics.setColor(0.8, 0.95, 0.85)
        love.graphics.rectangle("fill", ix + 2 * s, iy + s, s, 3 * s)
        love.graphics.setColor(0.6, 0.45, 0.3)
        love.graphics.rectangle("fill", ix + 2 * s, iy, s, s)
      end },
      { inv.keys or 0, function(ix, iy)
        love.graphics.setColor(0.86, 0.68, 0.30)
        love.graphics.rectangle("fill", ix + s, iy, 3 * s, 3 * s)
        love.graphics.rectangle("fill", ix + 2 * s, iy + 3 * s, s, 6 * s)
        love.graphics.rectangle("fill", ix + 3 * s, iy + 7 * s, 2 * s, s)
      end },
      { nb, function(ix, iy)
        love.graphics.setColor(0.78, 0.82, 0.92)
        love.graphics.rectangle("fill", ix + s, iy + s, 4 * s, 5 * s)
        love.graphics.rectangle("fill", ix, iy + 5 * s, 6 * s, 2 * s)
        love.graphics.rectangle("fill", ix + 2 * s, iy + 7 * s, s, s)
      end },
    }
    for _, row in ipairs(rows) do
      if row[1] > 0 then
        local text = "x" .. row[1]
        local gap = math.floor(3 * u)
        local width = 6 * s + gap + f:getWidth(text)
        local ix = cx - math.floor(width / 2)
        row[2](ix, y)
        love.graphics.setColor(0.97, 0.98, 1)
        shadowText(text, ix + 6 * s + gap, math.floor(y + 5 * s - fh / 2), f)
        y = math.floor(y + math.max(10 * s, fh) + 3 * u)
      end
    end
  end
  love.graphics.setColor(1, 1, 1)

  hud.drawBanner(scale)
end

-- Ammo pips -----------------------------------------------------------------
-- Each chamber of the held gun is a little cartridge: the double-barrel's are
-- the fat red-and-brass base of a shotgun shell, everything else's bullets
-- (copper tip, brass case). A fired one goes dull (the revolver keeps its
-- empty brass until it reloads) and gives a tiny poof: a flash, three wisps of
-- smoke and a casing flicked up. Reloading pops the full set back in, left to
-- right.
local PIP = {
  revolver = { w = 3, pitch = 5 },
  pistol = { w = 2, pitch = 4 },
  mg = { w = 2, pitch = 3 },
  shell = { w = 5, pitch = 7 },
}
local TIP, TIP_L = { 0.84, 0.52, 0.28 }, { 1.0, 0.80, 0.55 }
local BRASS, BRASS_L, BRASS_D, RIM = { 0.95, 0.74, 0.26 }, { 1.0, 0.92, 0.55 }, { 0.68, 0.47, 0.15 }, { 0.50, 0.34, 0.10 }
local HULL, HULL_L, HULL_D = { 0.80, 0.16, 0.13 }, { 0.98, 0.42, 0.34 }, { 0.50, 0.08, 0.08 }
local ammoState = setmetatable({}, { __mode = "k" }) -- gun -> { last, puffs, fillAt, fillFrom }
local POOF = 0.38
local PIP_ROW = 50
local POP = 0.2

local function pipKind(gun, count)
  local model = gun.def.model
  local kind = model == "shotgun" and "shell" or (model == "revolver" and "revolver" or ((model == "automatic" or model == "gatling") and "mg" or "pistol"))
  if count > 24 and kind ~= "mg" and kind ~= "shell" then
    kind = "mg"
  end
  return kind
end

-- One pip with its left edge at x and bottom at yb; q = one pip pixel
local function drawPip(kind, x, yb, q, filled, lift)
  local function cell(cx, cy, cw, ch, c, a)
    love.graphics.setColor(c[1], c[2], c[3], a or 1)
    love.graphics.rectangle("fill", x + cx * q, yb - lift - (8 - cy) * q, cw * q, ch * q)
  end
  if kind == "shell" then
    -- The base of a shotgun shell: red hull cut off above, a brass band, a rim
    if filled then
      cell(0, 2, 5, 4, HULL)
      cell(0, 2, 1, 4, HULL_L)
      cell(4, 2, 1, 4, HULL_D)
      cell(0, 2, 5, 1, HULL_D)
      cell(0, 6, 5, 1, BRASS)
      cell(0, 6, 1, 1, BRASS_L)
      cell(4, 6, 1, 1, BRASS_D)
      cell(0, 7, 5, 1, BRASS)
      cell(0, 7, 5, 1, BRASS_D, 0.5)
      cell(0, 7, 1, 1, BRASS_L)
      cell(2, 4, 1, 1, { 1, 1, 1 }, 0.25) -- a glint on the hull
    else
      -- Spent: a scorched, dull hull and a dark brass base
      cell(0, 3, 5, 3, { 0.30, 0.10, 0.10 }, 0.55)
      cell(0, 6, 5, 2, { 0.34, 0.27, 0.15 }, 0.55)
      cell(1, 3, 3, 1, { 0.08, 0.06, 0.06 }, 0.6)
    end
    return
  end
  local w = PIP[kind].w
  if filled then
    if w == 3 then
      cell(1, 0, 1, 1, TIP_L)
      cell(0, 1, 3, 1, TIP)
      cell(0, 1, 1, 1, TIP_L)
      cell(0, 2, 1, 5, BRASS_L)
      cell(1, 2, 1, 5, BRASS)
      cell(2, 2, 1, 5, BRASS_D)
      cell(0, 4, 3, 1, BRASS_D, 0.5) -- the groove round the case
    else
      cell(0, 0, 2, 1, TIP_L)
      cell(0, 1, 2, 1, TIP)
      cell(0, 2, 1, 5, BRASS_L)
      cell(1, 2, 1, 5, BRASS)
    end
    cell(0, 7, w, 1, RIM)
  elseif kind == "revolver" then
    -- The empty case stays in the cylinder
    cell(0, 2, w, 5, { 0.42, 0.32, 0.14 }, 0.8)
    cell(0, 2, w, 1, { 0.10, 0.07, 0.05 })
    cell(0, 7, w, 1, { 0.30, 0.2, 0.08 }, 0.8)
  else
    cell(0, 2, w, 6, { 0.45, 0.40, 0.35 }, 0.22)
  end
end

local function drawPoof(kind, cx, cy, q, age, seed)
  local k = age / POOF
  if age < 0.07 then
    local s = (kind == "shell" and 7 or 5) * q
    love.graphics.setColor(1, 0.92, 0.55, 1 - age / 0.07)
    love.graphics.rectangle("fill", math.floor(cx - s / 2), math.floor(cy - s / 2), s, s)
  end
  for i = 1, 3 do
    local ang = seed * 6.28 + i * 2.1
    local d = (4 + 7 * k) * q
    love.graphics.setColor(0.78, 0.78, 0.8, (1 - k) * 0.65)
    local sz = math.max(1, math.floor(q * (1.2 - 0.4 * k) + 0.5))
    love.graphics.rectangle("fill", math.floor(cx + math.cos(ang) * d), math.floor(cy + math.sin(ang) * d * 0.7 - 6 * q * k), sz, sz)
  end
  if kind ~= "revolver" then
    -- The casing flicked up and out
    local fx, fy = cx - (3 + seed * 5) * q * k, cy - (14 * k - 22 * k * k) * q
    love.graphics.setColor(BRASS[1], BRASS[2], BRASS[3], 1 - k)
    love.graphics.rectangle("fill", math.floor(fx), math.floor(fy), q, 2 * q)
  end
end

-- A faded purple-grey wash over whatever is drawn while it is set (the off-hand gun's magazine)
local BEHIND = [[
vec4 effect(vec4 c, Image t, vec2 uv, vec2 sc) {
  vec4 p = Texel(t, uv) * c;
  float g = dot(p.rgb, vec3(0.4, 0.4, 0.2));
  vec3 col = mix(vec3(g), vec3(0.50, 0.42, 0.72) * (0.55 + g * 0.8), 0.65);
  return vec4(col, p.a * 0.5);
}
]]
local behindShader

-- Pips, name and reload bar of the held gun, right-aligned below the health bar.
-- opts.behind: the off-hand gun of Akimbo, drawn behind and to the lower left, faded, with no name
function hud.drawGunStatus(gun, ww, margin, top, u, f, opts)
  local behind = opts and opts.behind
  if behind then
    if behindShader == nil then
      local ok, sh = pcall(love.graphics.newShader, BEHIND)
      behindShader = ok and sh or false
    end
    if behindShader then
      love.graphics.setShader(behindShader)
    end
    ww, top = ww - 5 * u, top + 4 * u
  end
  local count = gun:maxChambers()
  local kind = pipKind(gun, count)
  local q = math.max(1, math.floor(u * 0.5 + 0.5))
  local spec = PIP[kind]
  local pitch, pw = spec.pitch * q, spec.w * q
  -- A big belt (the Gatling) wraps into rows of at most PIP_ROW
  local perRow = math.min(count, PIP_ROW)
  local rows = math.ceil(count / perRow)
  local rowH = 9 * q
  local rowW = (perRow - 1) * pitch + pw
  local cy = top + 8 * u
  local yb = math.floor(cy + 4 * q)
  local x0 = ww - margin - rowW
  local now = love.timer.getTime()

  -- What changed since last frame: rounds fired (each gets a poof), or refilled
  local st = ammoState[gun]
  if not st then
    st = { last = gun.chambers, puffs = {} }
    ammoState[gun] = st
  end
  if gun.chambers < st.last then
    for i = gun.chambers + 1, math.min(st.last, gun.chambers + 8) do
      st.puffs[#st.puffs + 1] = { i = i, born = now, seed = love.math.random() }
    end
  elseif gun.chambers > st.last then
    st.fillAt, st.fillFrom = now, st.last
  end
  st.last = gun.chambers

  for i = 1, count do
    local lift = 0
    if st.fillAt and i > st.fillFrom then
      local age = now - st.fillAt - (i - st.fillFrom) / math.max(1, count - st.fillFrom) * 0.2
      if age > 0 and age < POP then
        lift = math.sin(age / POP * math.pi) * 3 * q
      elseif age <= 0 and gun.chambers >= i then
        lift = 0
      end
    end
    drawPip(kind, x0 + ((i - 1) % perRow) * pitch, yb + math.floor((i - 1) / perRow) * rowH, q, i <= gun.chambers, math.floor(lift))
  end

  for n = #st.puffs, 1, -1 do
    local pf = st.puffs[n]
    local age = now - pf.born
    if age >= POOF or n > 24 then
      table.remove(st.puffs, n)
    else
      drawPoof(kind, x0 + ((pf.i - 1) % perRow) * pitch + pw / 2, yb - 4 * q + math.floor((pf.i - 1) / perRow) * rowH, q, age, pf.seed)
    end
  end

  love.graphics.setColor(1, 1, 1)
  if behind then
    love.graphics.setShader()
    return
  end
  shadowText(gun.name, x0 - f:getWidth(gun.name) - 4 * u, cy - f:getHeight() / 2, f)

  -- Reloading: the word waves, filling from red to gold as the reload goes
  if gun:isReloading() then
    local word = "RELOADING"
    local progress = gun:reloadProgress()
    local ry = yb + 3 * u + (rows - 1) * rowH
    local right = ww - margin
    local left = right - f:getWidth(word)
    local lx = left
    for i = 1, #word do
      local ch = word:sub(i, i)
      local wave = math.floor(math.sin(now * 11 - i * 0.7) * 1.2 * u * 0.5 + 0.5)
      if (i - 0.5) / #word < progress then
        love.graphics.setColor(1.0, 0.82, 0.25)
      else
        love.graphics.setColor(0.85, 0.16, 0.14)
      end
      shadowText(ch, math.floor(lx), ry + wave, f)
      lx = lx + f:getWidth(ch)
    end
  end
end

-- Area title card, e.g. when entering a new area
local banner = { time = 0 }
local BANNER_TIME = 3.5

function hud.showBanner(title, subtitle)
  banner = { title = title, subtitle = subtitle, time = BANNER_TIME }
end

function hud.update(dt)
  banner.time = math.max(0, banner.time - dt)
end

function hud.drawBanner(scale)
  if banner.time <= 0 or hud.hideBanner then
    return
  end
  local elapsed = BANNER_TIME - banner.time
  local alpha = math.min(1, elapsed / 0.4, banner.time / 0.8)
  local ww, wh = love.graphics.getDimensions()
  local big = font(math.max(16, math.floor(scale * 9)))
  local f = font(math.max(10, math.floor(scale * 4)))
  local y = math.floor(wh * 0.22)
  love.graphics.setColor(0.96, 0.98, 1, alpha)
  shadowText(banner.title, math.floor((ww - big:getWidth(banner.title)) / 2), y, big)
  fontFace.rule(ww / 2, y + big:getHeight() + 2 * scale, math.max(big:getWidth(banner.title) * 1.3, 80 * scale), math.max(1, math.floor(scale * 0.5)), 0.46, 0.62, 0.9, alpha * 0.9)
  if banner.subtitle then
    love.graphics.setColor(1, 1, 1, alpha * 0.85)
    shadowText(banner.subtitle, math.floor((ww - f:getWidth(banner.subtitle)) / 2), y + big:getHeight() + 6 * scale, f)
  end
end

-- Shown over a dimmed screen once the hunter has died
function hud.drawDeath(scale)
  local ww, wh = love.graphics.getDimensions()
  love.graphics.setColor(0, 0, 0, 0.45)
  love.graphics.rectangle("fill", 0, 0, ww, wh)
  local big = font(math.max(16, math.floor(scale * 11)))
  local f = font(math.max(10, math.floor(scale * 4)))
  local y = math.floor(wh * 0.38)
  local title, sub = "You Died", ""
  love.graphics.setColor(0.86, 0.16, 0.2)
  shadowText(title, math.floor((ww - big:getWidth(title)) / 2), y, big)
  fontFace.rule(ww / 2, y + big:getHeight() + 2 * scale, math.max(big:getWidth(title) * 1.2, 80 * scale), math.max(1, math.floor(scale * 0.5)), 0.7, 0.14, 0.18)
  love.graphics.setColor(1, 1, 1, 0.85)
  shadowText(sub, math.floor((ww - f:getWidth(sub)) / 2), y + big:getHeight() + 6 * scale, f)
end

-- The crosshair, set in Settings > Crosshair: style (a plus, a ring, a dot or
-- an X), colour, opacity, line thickness, arm length and the gap round the
-- centre, with or without a dark outline. Drawn at (vx, vy) in game pixels.
hud.CROSSHAIR_COLORS = {
  { 1, 1, 1 },
  { 0.3, 1, 0.35 },
  { 1, 0.95, 0.3 },
  { 0.3, 0.95, 1 },
  { 1, 0.35, 0.35 },
  { 1, 0.45, 0.95 },
  { 1, 0.62, 0.2 },
}
hud.CROSSHAIR_STYLES = { "plus", "circle", "dot", "x" }

-- Calls rect(x, y, w, h) for every bar of the shape (not the ring)
local function crosshairBars(style, x, y, t, len, gap, rect)
  local half = math.floor(t / 2)
  if style == "dot" then
    local d = t + 1
    rect(x - math.floor(d / 2), y - math.floor(d / 2), d, d)
  elseif style == "x" then
    for i = gap, gap + len - 1 do
      for _, sx in ipairs({ -1, 1 }) do
        for _, sy in ipairs({ -1, 1 }) do
          rect(x + sx * i - half, y + sy * i - half, t, t)
        end
      end
    end
  else
    rect(x - gap - len, y - half, len, t)
    rect(x + gap + 1, y - half, len, t)
    rect(x - half, y - gap - len, t, len)
    rect(x - half, y + gap + 1, t, len)
  end
end

function hud.drawCrosshair(vx, vy)
  local settings = require("src.settings")
  local style = settings.get("crosshairStyle") or "plus"
  local c = hud.CROSSHAIR_COLORS[settings.get("crosshairColor")] or hud.CROSSHAIR_COLORS[1]
  local a = settings.get("crosshairOpacity") or 0.9
  local t = math.max(1, math.floor(settings.get("crosshairThickness") or 1))
  local len = math.max(1, math.floor(settings.get("crosshairLength") or 3))
  local gap = math.max(0, math.floor(settings.get("crosshairGap") or 2))
  local outline = settings.get("crosshairOutline")
  local x, y = math.floor(vx), math.floor(vy)
  local function rectFill(rx, ry, w, h)
    love.graphics.rectangle("fill", rx, ry, w, h)
  end
  local function rectEdge(rx, ry, w, h)
    love.graphics.rectangle("fill", rx - 1, ry - 1, w + 2, h + 2)
  end
  love.graphics.push("all")
  love.graphics.setLineStyle("rough")
  local r = gap + len + 1
  if outline then
    love.graphics.setColor(0, 0, 0, 0.6 * a)
    if style == "circle" then
      love.graphics.setLineWidth(t + 2)
      love.graphics.circle("line", x + 0.5, y + 0.5, r, 28)
    else
      crosshairBars(style, x, y, t, len, gap, rectEdge)
    end
  end
  love.graphics.setColor(c[1], c[2], c[3], a)
  if style == "circle" then
    love.graphics.setLineWidth(t)
    love.graphics.circle("line", x + 0.5, y + 0.5, r, 28)
  else
    crosshairBars(style, x, y, t, len, gap, rectFill)
  end
  love.graphics.pop()
end

return hud
