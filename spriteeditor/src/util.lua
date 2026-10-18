-- Small helpers shared by the editor modules.
local U = {}

function U.clamp(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi end
  return v
end

function U.round(v)
  return math.floor(v + 0.5)
end

function U.lerp(a, b, t)
  return a + (b - a) * t
end

-- Deep copy of plain data (no metatables, no userdata)
function U.copy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = U.copy(v) end
  return out
end

function U.inRect(x, y, rx, ry, rw, rh)
  return x >= rx and y >= ry and x < rx + rw and y < ry + rh
end

-- Wrap an angle into -pi..pi
function U.wrapAngle(a)
  while a > math.pi do a = a - 2 * math.pi end
  while a < -math.pi do a = a + 2 * math.pi end
  return a
end

-- Colours ------------------------------------------------------------------------------------------

function U.hsv2rgb(h, s, v)
  h = (h % 1) * 6
  local i = math.floor(h)
  local f = h - i
  local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
  if i == 0 then return v, t, p
  elseif i == 1 then return q, v, p
  elseif i == 2 then return p, v, t
  elseif i == 3 then return p, q, v
  elseif i == 4 then return t, p, v
  end
  return v, p, q
end

function U.rgb2hsv(r, g, b)
  local mx, mn = math.max(r, g, b), math.min(r, g, b)
  local d = mx - mn
  local h = 0
  if d > 0 then
    if mx == r then h = ((g - b) / d) % 6
    elseif mx == g then h = (b - r) / d + 2
    else h = (r - g) / d + 4 end
    h = h / 6
  end
  local s = mx > 0 and d / mx or 0
  return h, s, mx
end

function U.hex(c)
  return string.format("%02x%02x%02x", U.round(c[1] * 255), U.round(c[2] * 255), U.round(c[3] * 255))
end

function U.parseHex(s)
  s = (s or ""):gsub("^#", "")
  if not s:match("^%x%x%x%x%x%x$") then return nil end
  return tonumber(s:sub(1, 2), 16) / 255, tonumber(s:sub(3, 4), 16) / 255, tonumber(s:sub(5, 6), 16) / 255
end

-- Colours read back from 8-bit image data are compared with a little slack
function U.sameColor(a, b)
  local e = 0.5 / 255
  return math.abs(a[1] - b[1]) < e and math.abs(a[2] - b[2]) < e and math.abs(a[3] - b[3]) < e and math.abs(a[4] - b[4]) < e
end

function U.luma(r, g, b)
  return 0.299 * r + 0.587 * g + 0.114 * b
end

-- Lines --------------------------------------------------------------------------------------------

-- Bresenham: calls fn(x, y) for every pixel from (x0, y0) to (x1, y1)
function U.line(x0, y0, x1, y1, fn)
  local dx, dy = math.abs(x1 - x0), -math.abs(y1 - y0)
  local sx, sy = x0 < x1 and 1 or -1, y0 < y1 and 1 or -1
  local err = dx + dy
  while true do
    fn(x0, y0)
    if x0 == x1 and y0 == y1 then break end
    local e2 = 2 * err
    if e2 >= dy then err = err + dy; x0 = x0 + sx end
    if e2 <= dx then err = err + dx; y0 = y0 + sy end
  end
end

-- Serialisation ------------------------------------------------------------------------------------

local function ser(v, out)
  local tv = type(v)
  if tv == "number" then
    if v == math.floor(v) and math.abs(v) < 2 ^ 52 then
      out[#out + 1] = string.format("%d", v)
    else
      out[#out + 1] = string.format("%.9g", v)
    end
  elseif tv == "string" then
    out[#out + 1] = string.format("%q", v)
  elseif tv == "boolean" then
    out[#out + 1] = tostring(v)
  elseif tv == "table" then
    out[#out + 1] = "{"
    local n = #v
    for i = 1, n do
      ser(v[i], out)
      out[#out + 1] = ","
    end
    local keys = {}
    for k in pairs(v) do
      if not (type(k) == "number" and k >= 1 and k <= n and k % 1 == 0) then keys[#keys + 1] = k end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
      if type(k) == "string" and k:match("^[%a_][%w_]*$") then
        out[#out + 1] = k .. "="
      else
        out[#out + 1] = "["
        ser(k, out)
        out[#out + 1] = "]="
      end
      ser(v[k], out)
      out[#out + 1] = ",\n"
    end
    out[#out + 1] = "}"
  else
    out[#out + 1] = "nil"
  end
end

function U.serialize(v)
  local out = {}
  ser(v, out)
  return table.concat(out)
end

-- Loads a serialised table without giving it access to anything
function U.deserialize(s)
  local fn, err = loadstring("return " .. s)
  if not fn then return nil, err end
  setfenv(fn, {})
  local ok, res = pcall(fn)
  if not ok then return nil, res end
  return res
end

return U
