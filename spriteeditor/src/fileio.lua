-- Projects (.gspr) live in spriteeditor/projects, exports in spriteeditor/export. LÖVE can only
-- write to its save folder, so files go through io.open on the editor's own source folder; reading
-- and listing use love.filesystem, which sees that folder too.
local doc = require("src.doc")
local render = require("src.render")
local U = require("src.util")

local F = {}

F.root = love.filesystem.getSource():gsub("\\", "/"):gsub("/$", "")

function F.abs(rel)
  return F.root .. "/" .. rel
end

local function ensureDir(rel)
  if love.filesystem.getInfo(rel, "directory") then return end
  local p = F.abs(rel)
  if love.system.getOS() == "Windows" then
    os.execute('mkdir "' .. p:gsub("/", "\\") .. '" 2>nul')
  else
    os.execute('mkdir -p "' .. p .. '"')
  end
end

function F.write(rel, data)
  local dir = rel:match("^(.*)/[^/]+$")
  if dir then ensureDir(dir) end
  local f, err = io.open(F.abs(rel), "wb")
  if not f then return false, err end
  f:write(data)
  f:close()
  return true
end

function F.safeName(s)
  s = (s or ""):gsub("[^%w%-_ ]", ""):gsub("^%s+", ""):gsub("%s+$", "")
  return s ~= "" and s or "sprite"
end

-- Projects -----------------------------------------------------------------------------------------

function F.listProjects()
  local out = {}
  for _, name in ipairs(love.filesystem.getDirectoryItems("projects")) do
    if name:match("%.gspr$") then
      local info = love.filesystem.getInfo("projects/" .. name)
      out[#out + 1] = { name = name:gsub("%.gspr$", ""), time = info and info.modtime or 0 }
    end
  end
  table.sort(out, function(a, b) return a.time > b.time end)
  return out
end

function F.save(D, name)
  local ok, err = F.write("projects/" .. name .. ".gspr", U.serialize(doc.toTable(D, true)))
  return ok, ok and ("projects/" .. name .. ".gspr") or err
end

function F.load(name)
  local s = love.filesystem.read("projects/" .. name .. ".gspr")
  if not s then return nil, "can't read " .. name end
  local t, err = U.deserialize(s)
  if not t then return nil, err end
  local ok, D = pcall(doc.fromTable, t, true)
  if not ok then return nil, D end
  return D
end

-- Export -------------------------------------------------------------------------------------------

local function scaled(src, s)
  if s == 1 then return src end
  local w, h = src:getDimensions()
  local out = love.image.newImageData(w * s, h * s)
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local r, g, b, a = src:getPixel(x, y)
      if a > 0 then
        for oy = 0, s - 1 do
          for ox = 0, s - 1 do out:setPixel(x * s + ox, y * s + oy, r, g, b, a) end
        end
      end
    end
  end
  return out
end

-- o: name, layout ("strip" | "grid" | "files"), cols, scale, scope ("all" | "tags"), meta (bool)
-- Returns the written paths (relative to the editor folder) or nil, error
function F.export(D, o)
  local canvas = render.newCanvas(D.w, D.h)
  local s = o.scale or 1
  local groups = {}
  if o.scope == "tags" and #D.tags > 0 then
    for _, T in ipairs(D.tags) do
      local fr = {}
      for f = T.from, T.to do fr[#fr + 1] = f end
      groups[#groups + 1] = { suffix = "_" .. F.safeName(T.name):gsub(" ", "_"), frames = fr, tags = { { name = T.name, from = 1, to = #fr } } }
    end
  else
    local fr = {}
    for f = 1, #D.frames do fr[#fr + 1] = f end
    groups[1] = { suffix = "", frames = fr, tags = U.copy(D.tags) }
  end
  local written = {}
  for _, G in ipairs(groups) do
    local base = o.name .. G.suffix
    local meta = {
      frameW = D.w * s, frameH = D.h * s, scale = s, frames = {}, tags = G.tags,
      anchor = D.guide and { x = (D.guide.fx - math.floor(D.guide.w / 2) + D.guide.w / 2) * s, y = D.guide.fy * s } or nil,
      hitbox = D.guide and D.guide.w > 0 and { w = D.guide.w, h = D.guide.h } or nil,
    }
    local n = #G.frames
    if o.layout == "files" then
      for i, f in ipairs(G.frames) do
        local d = scaled(render.frameData(D, f, canvas, { skipRef = true }), s)
        local file = string.format("%s_%03d.png", base, i)
        local ok, err = F.write("export/" .. file, d:encode("png"):getString())
        if not ok then return nil, err end
        written[#written + 1] = "export/" .. file
        meta.frames[i] = { image = file, dur = D.frames[f].dur }
      end
    else
      local cols = o.layout == "grid" and math.max(1, math.min(n, o.cols or 8)) or n
      local rows = math.ceil(n / cols)
      local sheet = love.image.newImageData(D.w * s * cols, D.h * s * rows)
      for i, f in ipairs(G.frames) do
        local d = scaled(render.frameData(D, f, canvas, { skipRef = true }), s)
        local cx, cy = (i - 1) % cols, math.floor((i - 1) / cols)
        sheet:paste(d, cx * D.w * s, cy * D.h * s, 0, 0, D.w * s, D.h * s)
        meta.frames[i] = { x = cx * D.w * s, y = cy * D.h * s, w = D.w * s, h = D.h * s, dur = D.frames[f].dur }
      end
      meta.image = base .. ".png"
      local ok, err = F.write("export/" .. base .. ".png", sheet:encode("png"):getString())
      if not ok then return nil, err end
      written[#written + 1] = "export/" .. base .. ".png"
    end
    if o.meta then
      local ok, err = F.write("export/" .. base .. ".lua", "-- Exported by the Gunnug sprite editor\nreturn " .. U.serialize(meta) .. "\n")
      if not ok then return nil, err end
      written[#written + 1] = "export/" .. base .. ".lua"
    end
  end
  canvas:release()
  return written
end

return F
