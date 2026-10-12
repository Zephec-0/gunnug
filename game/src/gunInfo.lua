-- What to tell the player about a weapon: its grade (how good its rolls are),
-- its stats against its archetype's base, a damage-per-second estimate, and
-- the short summary used by pick-up and purchase pop-ups. Pure functions of
-- a gun (src.guns), so any screen can use them.
local gunInfo = {}

-- Grades from worst to best, with the colours they are drawn in
gunInfo.GRADES = {
  { letter = "D", color = { 0.62, 0.64, 0.70 } },
  { letter = "C", color = { 0.60, 0.88, 0.62 } },
  { letter = "B", color = { 0.50, 0.72, 1.00 } },
  { letter = "A", color = { 0.78, 0.58, 1.00 } },
  { letter = "S", color = { 1.00, 0.55, 0.28 } },
}

-- Cut-offs on the roll score (see score): below the first is a D, and so on
local CUTS = { 0.10, 0.19, 0.27, 0.35 }

-- Which way is better for each rolled stat (+1 higher, -1 lower)
local ROLLED = { damage = 1, bulletSpeed = 1, impactForce = 1, chambers = 1, fireDelay = -1, reloadTime = -1, spread = -1 }

-- How good a generated weapon's bonuses are: the sum of how much better (or
-- worse) each rolled stat came out, plus a little for each slot above the
-- archetype's usual count. Typical weapons score 0.1-0.3.
function gunInfo.score(gun)
  local s = 0
  if gun.rolls then
    for stat, dir in pairs(ROLLED) do
      local m = gun.rolls[stat] or 1
      s = s + (dir > 0 and (m - 1) or (1 - m) / 0.8)
    end
  end
  s = s + (gun.slotCount - gun.def.slots - (gun.def.slotBias or 0)) * 0.03
  return s
end

-- 1 (D) to 5 (S)
function gunInfo.gradeIndex(gun)
  local s = gunInfo.score(gun)
  for i, cut in ipairs(CUTS) do
    if s < cut then
      return i
    end
  end
  return #CUTS + 1
end

function gunInfo.grade(gun)
  return gunInfo.GRADES[gunInfo.gradeIndex(gun)]
end

-- Burst and sustained damage per second (counting the reload)
function gunInfo.dps(gun)
  local st = gun:stats()
  local volley = math.max(1, st.damage) * math.max(1, st.pellets)
  local cycle = st.chambers * st.fireDelay + st.reloadTime
  return volley / st.fireDelay, volley * st.chambers / cycle
end

local function pct(better, base)
  if not base or base == 0 then
    return nil
  end
  local d = better / base - 1
  if math.abs(d) < 0.01 then
    return nil
  end
  return d
end

-- The stat table of a weapon card: { label, value text, delta } where delta is
-- the fractional change against the archetype's base (positive = better)
function gunInfo.rows(gun)
  local st, def = gun:stats(), gun.def
  local dmg = math.max(1, math.floor(st.damage + 0.5))
  local _, sustained = gunInfo.dps(gun)
  local rows = {
    { "Damage", st.pellets > 1 and string.format("%dx%d", dmg, st.pellets) or tostring(dmg), pct(st.damage, def.damage) },
    { "Rate", string.format("%.1f/s", 1 / st.fireDelay), pct(def.fireDelay, st.fireDelay) },
    { "Reload", string.format("%.2fs", st.reloadTime), pct(def.reloadTime, st.reloadTime) },
    { "Magazine", tostring(st.chambers), pct(st.chambers, def.chambers) },
    { "Spread", string.format("%.1f", st.spread), pct(def.spread + 0.001, st.spread + 0.001) },
    { "Impact", tostring(math.floor(st.impactForce + 0.5)), pct(st.impactForce, def.impactForce) },
    { "Recoil", tostring(math.floor(st.recoil + 0.5)), nil },
    { "DPS", tostring(math.floor(sustained + 0.5)), nil },
    { "Crit", string.format("%d%%", math.floor(st.critChance * 100 + 0.5)), nil },
  }
  return rows
end

-- A short summary for pop-ups: title, grade, and two stat lines
function gunInfo.summary(gun)
  local st = gun:stats()
  local burst, sustained = gunInfo.dps(gun)
  local dmg = math.max(1, math.floor(st.damage + 0.5))
  return {
    title = gun.name,
    grade = gunInfo.grade(gun),
    lines = {
      string.format("%s   %s", gun.def.name, st.pellets > 1 and string.format("%dx%d dmg", dmg, st.pellets) or (dmg .. " dmg")),
      string.format("%.1f shots/s   %d DPS", 1 / st.fireDelay, math.floor(sustained + 0.5)),
      string.format("%d %s   %d %s", st.chambers, st.chambers == 1 and "chamber" or "chambers", gun.slotCount, gun.slotCount == 1 and "slot" or "slots"),
    },
  }
end

return gunInfo
