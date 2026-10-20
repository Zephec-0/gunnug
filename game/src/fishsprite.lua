-- The fish boss's bodies, baked pixel by pixel at their real size (one art pixel = one game
-- pixel), so the bigger fish carry more detail rather than the small fish's pixels blown up.
-- The fish faces right. A region map is made first (what part each pixel is), then coloured,
-- then outlined.

local fishsprite = {}

local cache = {}

local R = {
  NONE = 0, BODY = 1, FIN = 2, PEC = 3, CAVITY = 4, TOOTH = 5, EYE = 6, IRIS = 7, GLINT = 8, GILL = 9, RAY = 10,
}

-- the body's outline from the tail to the snout: u, top v, bottom v (as fractions of the box)
local PROFILE = {
  { 0.10, 0.44, 0.58 },
  { 0.20, 0.38, 0.62 },
  { 0.30, 0.28, 0.72 },
  { 0.42, 0.19, 0.80 },
  { 0.55, 0.16, 0.83 },
  { 0.68, 0.18, 0.83 },
  { 0.80, 0.25, 0.79 },
  { 0.90, 0.34, 0.70 },
  { 0.985, 0.45, 0.62 },
}

local function profile(u)
  if u < PROFILE[1][1] or u > PROFILE[#PROFILE][1] then
    return nil
  end
  for i = 1, #PROFILE - 1 do
    local a, b = PROFILE[i], PROFILE[i + 1]
    if u <= b[1] then
      local f = (u - a[1]) / (b[1] - a[1])
      return a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f
    end
  end
end

local function mul(c, k)
  return { c[1] * k, c[2] * k, c[3] * k }
end

local function mix(a, b, f)
  return { a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f }
end

-- Which part of the fish is at this pixel (and how far down the body it is)
local function regionAt(px, py, w, h, stage, beat, open)
  local u, v = (px + 0.5) / w, (py + 0.5) / h
  local top, bot = profile(u)
  local fine = stage >= 2 -- fin rays, spines and scales come with size
  local drop = open and 0.27 or 0
  local mouthV = 0.56
  local inHead = u > 0.70

  -- tail: a fork that beats up and down
  local tailEnd = 0.19
  if u < tailEnd then
    local f = (tailEnd - u) / tailEnd -- 1 at the tip, 0 at the root
    local cy = 0.5 + (beat == 1 and 0.05 or -0.05) * f
    local half = 0.07 + 0.36 * f
    local notch = 0.17 * math.max(0, f - 0.45) / 0.55 -- the fork's V
    local d = math.abs(v - cy)
    if d < half and d >= notch then
      if fine and f > 0.3 and (math.floor(((v - cy) / (0.2 - u + 0.04)) * 3.2) % 2 == 0) then
        return R.RAY
      end
      return R.FIN
    end
    if u < PROFILE[1][1] then
      return R.NONE
    end
  end

  -- fins above and below the body
  do
    local btop, bbot = profile(math.min(math.max(u, PROFILE[1][1]), PROFILE[#PROFILE][1]))
    -- dorsal: steep at the front, sloping away behind
    if u >= 0.33 and u <= 0.72 then
      local peak = 0.46
      local fh
      if u < peak then
        fh = (u - 0.33) / (peak - 0.33)
      else
        fh = 1 - (u - peak) / (0.72 - peak)
      end
      local edge = btop - (btop - 0.0) * fh * (stage >= 3 and 1 or 0.95)
      if fine then
        -- spines: the edge between rays falls back a little
        local spine = math.floor(u * w / 3.0)
        local ph = (u * w) % 3.0
        if ph > 1.4 then
          edge = edge + (btop - edge) * 0.22
        end
        if stage >= 3 and spine % 4 == 2 then
          edge = edge + (btop - edge) * 0.35 -- a torn gap in the fin
        end
      end
      if v >= edge and v < btop + 0.02 then
        if fine and ((u * w) % 3.0) < 0.9 and v < btop - 0.03 then
          return R.RAY
        end
        return R.FIN
      end
    end
    -- belly fin (pelvic), pointing back
    if u >= 0.46 and u <= 0.60 then
      local f = 1 - math.abs(u - 0.50) / 0.10
      local tipv = bbot + (0.99 - bbot) * math.max(0, f)
      if v >= bbot - 0.02 and v <= tipv and f > 0 then
        return R.FIN
      end
    end
    -- anal fin
    if fine and u >= 0.22 and u <= 0.32 then
      local f = 1 - math.abs(u - 0.26) / 0.06
      local tipv = bbot + (0.93 - bbot) * math.max(0, f)
      if v >= bbot - 0.02 and v <= tipv and f > 0 then
        return R.FIN
      end
    end
  end

  if not top then
    return R.NONE
  end

  -- the body, with the lower jaw hanging when the mouth is open
  local jawBot = bot + (inHead and drop * math.min(1, (u - 0.70) / 0.28) or 0)
  if v < top or v > jawBot then
    -- (the pectoral fin may still be here)
    return R.NONE
  end

  if inHead then
    local mouthLow = mouthV + (open and drop * math.min(1, (u - 0.70) / 0.28) or 0)
    if u > 0.74 and v >= mouthV and v < mouthLow then
      return R.CAVITY
    end
    -- the closed mouth is a dark line from the snout back to under the eye
    if u > 0.74 and not open and v >= mouthV and v < mouthV + 1.1 / h then
      return R.CAVITY
    end
  end

  -- eye
  local ex, ey = 0.795 * w, 0.37 * h
  local er = math.max(1.0, h * 0.075)
  local dx, dy = px + 0.5 - ex, py + 0.5 - ey
  local ed = math.sqrt(dx * dx + dy * dy)
  if stage >= 2 then
    if ed <= er then
      if ed <= er * 0.6 then
        if stage >= 3 and dx < 0 and dy < 0 and ed > er * 0.15 then
          return R.GLINT
        end
        return R.IRIS
      end
      return R.EYE
    end
  end

  -- gills: a curved slit behind the eye
  do
    local gv = (v - 0.5) / 0.30
    local gu = 0.655 + 0.05 * gv * gv
    if v > top + 0.12 and v < bot - 0.10 and math.abs(u - gu) * w < 0.55 then
      return R.GILL
    end
    if stage >= 3 and v > top + 0.15 and v < bot - 0.14 and math.abs(u - gu - 0.04) * w < 0.5 then
      return R.GILL
    end
  end

  -- pectoral fin, laid along the flank
  if u >= 0.50 and u <= 0.64 and v >= 0.52 and v <= 0.74 then
    local f = (0.64 - u) / 0.14 -- 1 at the root...
    local edge = 0.52 + (0.74 - 0.52) * (1 - f) * 0.9
    if v >= 0.50 + (0.66 - 0.5) * (1 - f) and v <= edge + 0.12 * f then
      return R.PEC
    end
  end

  return R.BODY, (v - top) / (bot - top)
end

local function shade(region, depth, px, py, w, h, stage, S, flash)
  if flash then
    return 1, 1, 1
  end
  local c
  if region == R.FIN then
    c = S.fin
  elseif region == R.RAY then
    c = mul(S.fin, 0.62)
  elseif region == R.PEC then
    c = mix(S.fin, S.light, 0.35)
  elseif region == R.CAVITY then
    c = { 0.30, 0.04, 0.06 }
  elseif region == R.TOOTH then
    c = { 0.94, 0.92, 0.84 }
  elseif region == R.EYE then
    c = { 0.08, 0.04, 0.05 }
  elseif region == R.IRIS then
    c = stage >= 2 and { 1, 0.25, 0.2 } or { 1, 0.8, 0.5 }
  elseif region == R.GLINT then
    c = { 1, 0.85, 0.7 }
  elseif region == R.GILL then
    c = mul(S.back, 0.8)
  else
    local t = depth or 0.5
    if t < 0.20 then
      c = S.back
    elseif t < 0.36 then
      c = mix(S.back, S.body, 0.7)
    elseif t < 0.52 then
      c = S.body
    elseif t < 0.66 then
      c = S.light
    elseif t < 0.80 then
      c = S.body
    else
      c = S.belly
    end
    if stage >= 2 then
      -- scales: staggered rows of short marks
      local sx = math.max(3, math.floor(w / 14))
      local sy = math.max(3, math.floor(h / 8))
      local row = math.floor(py / sy)
      if t > 0.18 and t < 0.84 and (px + (row % 2) * math.floor(sx / 2)) % sx == 0 and py % sy ~= 0 then
        c = mul(c, 0.86)
      end
    end
    if stage >= 3 then
      -- scars across the flank
      local u, v = (px + 0.5) / w, (py + 0.5) / h
      local s1 = math.abs((v - 0.50) - (u - 0.30) * 0.55)
      local s2 = math.abs((v - 0.58) - (u - 0.40) * 0.45)
      if (s1 * h < 0.7 and u > 0.30 and u < 0.46) or (s2 * h < 0.7 and u > 0.40 and u < 0.52) then
        c = mix(c, S.light, 0.6)
      end
    end
  end
  return c[1], c[2], c[3]
end

local function bake(S, stage, w, h, beat, open, flash)
  local map, depth = {}, {}
  for py = 0, h - 1 do
    map[py], depth[py] = {}, {}
    for px = 0, w - 1 do
      local r, d = regionAt(px, py, w, h, stage, beat, open)
      map[py][px], depth[py][px] = r, d
    end
  end

  -- teeth along the mouth line, upper and lower
  local snout = math.floor(w * 0.985) - 1
  local per = math.max(2, math.floor(w / 11 + 0.5))
  local th = ({ 2, 3, 6 })[math.min(3, stage)] or 3
  if stage >= 3 then
    th = math.floor(h * 0.12)
  elseif stage == 2 then
    th = math.max(2, math.floor(h * 0.1))
  end
  local mouthY = math.floor(0.56 * h)
  local drop = open and math.floor(0.27 * h + 0.5) or 0
  local x = snout - 1
  local n = 0
  while x > w * 0.74 and n < 6 do
    local hw = math.max(1, math.floor(per / 2))
    for dx = -hw, hw do
      local px = x + dx
      local hgt = th * (1 - math.abs(dx) / (hw + 1))
      for k = 0, math.floor(hgt + 0.5) - 1 do
        local uy = mouthY + 1 + k
        if map[uy] and map[uy][px] ~= nil and map[uy][px] ~= R.NONE then
          map[uy][px] = R.TOOTH
        end
        -- the lower teeth sit between the upper ones
        local lx = px - math.floor(per / 2) - 1
        local ly = mouthY + math.min(drop, math.floor(drop * math.min(1, (lx / w - 0.70) / 0.28))) + 1 - k
        if map[ly] and map[ly][lx] ~= nil and map[ly][lx] ~= R.NONE and lx > w * 0.76 then
          map[ly][lx] = R.TOOTH
        end
      end
    end
    x = x - per - 1
    n = n + 1
  end

  local data = love.image.newImageData(w, h)
  local outline = mul(S.back, 0.35)
  for py = 0, h - 1 do
    for px = 0, w - 1 do
      local r = map[py][px]
      if r ~= R.NONE then
        local edge = false
        for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
          local q = map[py + d[2]] and map[py + d[2]][px + d[1]]
          if q == nil or q == R.NONE then
            edge = true
          end
        end
        local rr, gg, bb
        if edge and r ~= R.TOOTH then
          if flash then
            rr, gg, bb = 1, 1, 1
          else
            rr, gg, bb = outline[1], outline[2], outline[3]
          end
        else
          rr, gg, bb = shade(r, depth[py][px], px, py, w, h, stage, S, flash)
        end
        data:setPixel(px, py, rr, gg, bb, 1)
      end
    end
  end
  local img = love.graphics.newImage(data)
  img:setFilter("nearest", "nearest")
  return img
end

function fishsprite.get(S, stage, w, h, beat, open, flash)
  local key = stage .. ":" .. w .. "x" .. h .. ":" .. (beat or 0) .. (open and "o" or "c") .. (flash and "f" or "n")
  local img = cache[key]
  if not img then
    img = bake(S, stage, w, h, beat or 0, open, flash)
    cache[key] = img
  end
  return img
end

-- The Even Bigger Fish: an eel. A long green body with a ridge of fin along its back and belly,
-- baked at its real size. Two pictures: the body, and a layer of purple streaks that the boss
-- draws on top, pulsing along it. The boss also draws both in 1 px strips, riding a wave, so the
-- body swims like an eel.

local EEL_HH = {
  { 0.00, 0.02 }, { 0.12, 0.09 }, { 0.30, 0.19 }, { 0.55, 0.23 }, { 0.78, 0.26 }, { 0.87, 0.29 }, { 0.97, 0.20 }, { 1.0, 0.14 },
}

local function eelHalf(u)
  if u < 0 or u > 1 then
    return nil
  end
  for i = 1, #EEL_HH - 1 do
    local a, b = EEL_HH[i], EEL_HH[i + 1]
    if u <= b[1] then
      return a[2] + (b[2] - a[2]) * (u - a[1]) / (b[1] - a[1])
    end
  end
end

local EEL = {
  back = { 0.08, 0.24, 0.12 },
  body = { 0.16, 0.44, 0.20 },
  light = { 0.36, 0.68, 0.32 },
  belly = { 0.66, 0.76, 0.40 },
  fin = { 0.24, 0.14, 0.38 },
  finray = { 0.14, 0.08, 0.26 },
  outline = { 0.03, 0.10, 0.05 },
}

local function eelRegion(px, py, w, h, open)
  local u, v = (px + 0.5) / w, (py + 0.5) / h
  local hh = eelHalf(u)
  local cy = 0.5
  local top, bot
  if hh then
    top, bot = cy - hh, cy + hh
  end
  local drop = open and 0.16 or 0
  local inHead = u > 0.80
  local mouthV = 0.53

  -- fins: a ridge along the back, a lower one along the belly, a small one behind the head
  if top then
    if u >= 0.10 and u <= 0.80 then
      local fh = 0.09 + 0.05 * math.sin(u * 9)
      local ray = math.floor(u * w / 3)
      if v < top and v >= top - fh and (px % 3 ~= 0 or v > top - fh * 0.5) then
        return (px % 3 == 0) and 2 or 1
      end
      if v < top and v >= top - fh then
        return 2
      end
    end
    if u >= 0.14 and u <= 0.62 then
      local fh = 0.07
      if v > bot and v <= bot + fh then
        return (px % 3 == 0) and 2 or 1
      end
    end
    -- pectoral
    if u >= 0.70 and u <= 0.80 and v > cy + 0.05 and v < cy + 0.05 + (0.80 - u) * 1.4 + 0.07 then
      if v > bot - 0.05 then
        return 1
      end
    end
  elseif u < 0.0 then
    return 0
  end
  if not top then
    return 0
  end

  local jawBot = bot + (inHead and drop * math.min(1, (u - 0.78) / 0.2) or 0)
  if v < top or v > jawBot then
    return 0
  end
  if inHead and u > 0.84 then
    local lowLip = mouthV + drop * math.min(1, (u - 0.78) / 0.2)
    if v >= mouthV and v < lowLip then
      return 7 -- the open mouth
    end
    if not open and v >= mouthV and v < mouthV + 1.1 / h then
      return 7
    end
  end
  -- the eye
  local ex, ey = 0.875 * w, 0.40 * h
  local er = math.max(1.6, h * 0.07)
  local dx, dy = px + 0.5 - ex, py + 0.5 - ey
  local ed = math.sqrt(dx * dx + dy * dy)
  if ed <= er then
    if ed <= er * 0.55 then
      return 8
    end
    return 9
  end
  -- gills
  local gv = (v - cy) / 0.2
  local gu = 0.74 + 0.03 * gv * gv
  if v > top + 0.08 and v < bot - 0.06 and math.abs(u - gu) * w < 0.6 then
    return 10
  end
  return 3, (v - top) / math.max(0.001, bot - top)
end

local function eelColour(id, t, px, py, w, h, flash)
  if flash then
    return 1, 1, 1
  end
  local c
  if id == 1 then
    c = EEL.fin
  elseif id == 2 then
    c = EEL.finray
  elseif id == 7 then
    c = { 0.28, 0.03, 0.08 }
  elseif id == 8 then
    c = { 1, 0.45, 0.9 }
  elseif id == 9 then
    c = { 0.12, 0.04, 0.12 }
  elseif id == 10 then
    c = EEL.back
  elseif id == 11 then
    c = { 0.95, 0.93, 0.82 }
  else
    t = t or 0.5
    if t < 0.2 then
      c = EEL.back
    elseif t < 0.4 then
      c = EEL.body
    elseif t < 0.6 then
      c = EEL.light
    elseif t < 0.78 then
      c = EEL.body
    else
      c = EEL.belly
    end
    -- faint scale marks
    if (px + (math.floor(py / 3) % 2) * 2) % 5 == 0 and py % 3 ~= 0 and t > 0.15 and t < 0.8 then
      c = { c[1] * 0.88, c[2] * 0.9, c[3] * 0.88 }
    end
  end
  return c[1], c[2], c[3]
end

local eelCache = {}

function fishsprite.eel(w, h, open, flash)
  local key = w .. "x" .. h .. (open and "o" or "c") .. (flash and "f" or "n")
  local hit = eelCache[key]
  if hit then
    return hit[1], hit[2]
  end
  local map, depth = {}, {}
  for py = 0, h - 1 do
    map[py], depth[py] = {}, {}
    for px = 0, w - 1 do
      map[py][px], depth[py][px] = eelRegion(px, py, w, h, open)
    end
  end
  -- teeth along the mouth: upper and lower rows
  local th = math.max(3, math.floor(h * 0.16))
  local per = 5
  local mouthY = math.floor(0.53 * h)
  local dropPx = open and math.floor(0.16 * h + 0.5) or 0
  local x = w - 2
  local n = 0
  while x > w * 0.84 and n < 4 do
    for dx = -2, 2 do
      local px = x + dx
      local hgt = th * (1 - math.abs(dx) / 3)
      for k = 0, math.floor(hgt + 0.5) - 1 do
        local uy = mouthY + 1 + k
        if map[uy] and map[uy][px] and map[uy][px] ~= 0 then
          map[uy][px] = 11
        end
        local lx = px - 3
        local ly = mouthY + math.floor(dropPx * math.min(1, (lx / w - 0.78) / 0.2)) + 1 - k
        if map[ly] and map[ly][lx] and map[ly][lx] ~= 0 and lx > w * 0.85 then
          map[ly][lx] = 11
        end
      end
    end
    x = x - per - 2
    n = n + 1
  end

  local data = love.image.newImageData(w, h)
  local streak = love.image.newImageData(w, h)
  local NB = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
  for py = 0, h - 1 do
    for px = 0, w - 1 do
      local id = map[py][px]
      if id ~= 0 then
        local edge = false
        for _, d in ipairs(NB) do
          local q = map[py + d[2]] and map[py + d[2]][px + d[1]]
          if q == nil or q == 0 then
            edge = true
          end
        end
        local r, g, b
        if edge and id ~= 11 then
          r, g, b = EEL.outline[1], EEL.outline[2], EEL.outline[3]
          if flash then
            r, g, b = 1, 1, 1
          end
        else
          r, g, b = eelColour(id, depth[py][px], px, py, w, h, flash)
        end
        data:setPixel(px, py, r, g, b, 1)
        -- the streaks: slanted purple strokes along the flank and dots along the fin rays
        if not flash and not edge then
          local u = (px + 0.5) / w
          local t = depth[py][px]
          if id == 3 and t and t > 0.16 and t < 0.84 and u < 0.80 then
            local s = (px + py * 1.6) % 15
            if s < 1 then
              streak:setPixel(px, py, 0.95, 0.75, 1, 1)
            elseif s < 3.4 then
              streak:setPixel(px, py, 0.62, 0.28, 0.95, 1)
            end
          elseif id == 2 and py % 2 == 0 then
            streak:setPixel(px, py, 0.8, 0.45, 1, 1)
          end
        end
      end
    end
  end
  local a, b = love.graphics.newImage(data), love.graphics.newImage(streak)
  a:setFilter("nearest", "nearest")
  b:setFilter("nearest", "nearest")
  eelCache[key] = { a, b }
  return a, b
end

return fishsprite
