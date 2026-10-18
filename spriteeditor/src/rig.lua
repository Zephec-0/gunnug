-- Puppet rig: a small bone hierarchy. Each bone has a rest pose (head position, angle and length
-- in canvas pixels) and per-frame keys {r, x, y}: a rotation added to the rest angle and a
-- translation of the head. Frames without a key are interpolated between the keys around them
-- (eased if the earlier key says so) and hold the nearest key at the ends.
--
-- Layers bound to a bone are drawn (and painted) in rest-pose space and moved rigidly with it, so a
-- character can be cut into parts and animated like a puppet.
local U = require("src.util")
local doc = require("src.doc")

local rig = {}

function rig.bone(D, id)
  for i, B in ipairs(D.bones) do
    if B.id == id then return B, i end
  end
end

-- Bones are always stored parents-first: a new bone is appended after its parent
function rig.add(D, parentId, x1, y1, x2, y2, name)
  local dx, dy = x2 - x1, y2 - y1
  local B = {
    id = doc.id(D), name = name or ("bone " .. (#D.bones + 1)), parent = parentId,
    x = x1, y = y1, angle = math.atan2(dy, dx), len = math.max(1, math.sqrt(dx * dx + dy * dy)), keys = {},
  }
  for f = 1, #D.frames do B.keys[f] = false end
  D.bones[#D.bones + 1] = B
  return B
end

function rig.remove(D, id)
  local B, i = rig.bone(D, id)
  if not B then return end
  for _, C in ipairs(D.bones) do
    if C.parent == id then C.parent = B.parent end
  end
  for _, L in ipairs(D.layers) do
    if L.bone == id then L.bone = nil end
  end
  table.remove(D.bones, i)
end

function rig.depth(D, B)
  local d = 0
  while B.parent do
    B = rig.bone(D, B.parent)
    if not B then break end
    d = d + 1
  end
  return d
end

-- The (interpolated) key of a bone at frame f: r, x, y, isKeyed
function rig.key(B, f)
  local keys = B.keys
  local k = keys[f]
  if k then return k.r, k.x, k.y, true end
  local p, n
  for i = f - 1, 1, -1 do
    if keys[i] then p = i; break end
  end
  for i = f + 1, #keys do
    if keys[i] then n = i; break end
  end
  if not p and not n then return 0, 0, 0, false end
  if not n then local q = keys[p]; return q.r, q.x, q.y, false end
  if not p then local q = keys[n]; return q.r, q.x, q.y, false end
  local a, b = keys[p], keys[n]
  local t = (f - p) / (n - p)
  if a.ease then t = t * t * (3 - 2 * t) end
  return U.lerp(a.r, b.r, t), U.lerp(a.x, b.x, t), U.lerp(a.y, b.y, t), false
end

function rig.setKey(B, f, r, x, y)
  local k = B.keys[f]
  if not k then
    k = { r = 0, x = 0, y = 0 }
    B.keys[f] = k
  end
  k.r, k.x, k.y = r, x, y
  return k
end

-- World pose of every bone on frame f (rest = true ignores the keys). Returns a table by bone id:
--   hx, hy, a     head and angle      tx, ty   tail
--   m             the skin transform {a, b, c, d, tx, ty} from rest space to posed space
function rig.pose(D, f, rest)
  local P = {}
  for _, B in ipairs(D.bones) do
    local r, x, y = 0, 0, 0
    if not rest then r, x, y = rig.key(B, f) end
    local hx, hy, a
    local par = B.parent and P[B.parent]
    if par then
      local pb = par.bone
      local ox, oy = B.x - pb.x, B.y - pb.y
      local c, s = math.cos(-pb.angle), math.sin(-pb.angle)
      local lx, ly = ox * c - oy * s, ox * s + oy * c
      local c2, s2 = math.cos(par.a), math.sin(par.a)
      hx = par.hx + lx * c2 - ly * s2 + x
      hy = par.hy + lx * s2 + ly * c2 + y
      a = par.a + (B.angle - pb.angle) + r
    else
      hx, hy, a = B.x + x, B.y + y, B.angle + r
    end
    local th = a - B.angle
    local c, s = math.cos(th), math.sin(th)
    if math.abs(th) < 1e-6 then c, s = 1, 0 end
    -- Translation snapped to whole pixels so parts don't shimmer between frames
    local m = { c, -s, s, c, U.round(hx - (c * B.x - s * B.y)), U.round(hy - (s * B.x + c * B.y)) }
    P[B.id] = {
      bone = B, hx = hx, hy = hy, a = a, m = m,
      tx = hx + math.cos(a) * B.len, ty = hy + math.sin(a) * B.len,
    }
  end
  return P
end

function rig.isIdentity(m)
  return m[1] == 1 and m[3] == 0 and m[5] == 0 and m[6] == 0
end

-- Maps a canvas pixel back to the rest-space pixel that is drawn there
function rig.inverse(m)
  local c, s, tx, ty = m[1], m[3], m[5], m[6]
  return function(X, Y)
    local dx, dy = X + 0.5 - tx, Y + 0.5 - ty
    return math.floor(c * dx + s * dy), math.floor(-s * dx + c * dy)
  end
end

-- Cyclic coordinate descent: turns `B` and up to chain-1 of its parents so B's tail reaches (tx, ty)
function rig.ik(D, f, B, tx, ty, chain)
  local list, cur = {}, B
  for _ = 1, chain do
    list[#list + 1] = cur
    if not cur.parent then break end
    cur = rig.bone(D, cur.parent)
    if not cur then break end
  end
  for _ = 1, 12 do
    for _, J in ipairs(list) do
      local P = rig.pose(D, f)
      local pj, pe = P[J.id], P[B.id]
      local a1 = math.atan2(pe.ty - pj.hy, pe.tx - pj.hx)
      local a2 = math.atan2(ty - pj.hy, tx - pj.hx)
      local d = U.wrapAngle(a2 - a1)
      local r, x, y = rig.key(J, f)
      rig.setKey(J, f, r + d, x, y)
    end
  end
end

-- Distance from a point to a bone segment
function rig.distance(p, x, y)
  local dx, dy = p.tx - p.hx, p.ty - p.hy
  local l2 = dx * dx + dy * dy
  local t = l2 > 0 and U.clamp(((x - p.hx) * dx + (y - p.hy) * dy) / l2, 0, 1) or 0
  local px, py = p.hx + dx * t, p.hy + dy * t
  return math.sqrt((x - px) ^ 2 + (y - py) ^ 2), t
end

return rig
