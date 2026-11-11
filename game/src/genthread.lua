-- The worker thread that builds an area (src.genworker starts it, one or two of these run). It takes a job from its
-- channel: the area's spec and seed, the size of the world, and the strip of the world above the area (what the
-- area's own build will cut into). It builds the area into a world of its own (cavegen.generate, the same code
-- the main thread would have run, so the same terrain and the same layout come out), then sends back what the
-- main thread needs to put it in the real world: the cells of the rectangle, the lazy-painting operations, the
-- tints, the decoration materials it had to make, and the area's layout (plain data).
-- Everything here is plain data or a ByteData: nothing of the main thread's (no graphics, no save file) is touched.
local inName, outName = ...
require("love.timer")
require("love.math")
require("love.image")
require("love.data")
require("love.filesystem")
require("src.jittune") -- (this thread has a Lua state, and so a JIT, of its own)
local ffi = require("ffi")

local inCh, outCh = love.thread.getChannel(inName), love.thread.getChannel(outName)

-- The hunter's death marker is the one piece of the save file the layout reads (src.story): the main thread sends it
-- along with the job, and this stands in for src.meta
local marker
package.preload["src.meta"] = function()
  return {
    markerFor = function()
      return marker or nil
    end,
    clearMarker = function() end,
  }
end

-- The tables of `v` that appear more than once, as paths of keys: { { from = { keys }, to = { keys } }, ... }
-- (a channel copies a table once for every place it is found; the main thread joins them again)
local function sharedLinks(root)
  local seen, links = {}, {}
  local path = {}
  local function walk(v)
    if type(v) ~= "table" then
      return
    end
    if seen[v] then
      local to = {}
      for i = 1, #path do
        to[i] = path[i]
      end
      links[#links + 1] = { from = seen[v], to = to }
      return
    end
    local here = {}
    for i = 1, #path do
      here[i] = path[i]
    end
    seen[v] = here
    for k, x in pairs(v) do
      if type(x) == "table" then
        path[#path + 1] = k
        walk(x)
        path[#path] = nil
      end
    end
  end
  walk(root)
  return links
end

-- Anything the build wrote outside the rectangle it was given back would be lost: this looks for cells that are
-- not air outside it (the world started out all air, apart from the strip that was sent in)
local function leaked(world, x0, y0, x1, y1)
  local count = 0
  local bx0, by0, bx1, by1 = math.huge, math.huge, -math.huge, -math.huge
  local function mark(x, y)
    count = count + 1
    if x < bx0 then bx0 = x end
    if x > bx1 then bx1 = x end
    if y < by0 then by0 = y end
    if y > by1 then by1 = y end
  end
  for _, t in ipairs(world.tiles) do
    local c = t.cells
    if c then
      for y = t.y, t.y1 - 1 do
        local rowIn = y >= y0 and y <= y1
        local base = (y - t.y) * t.w + 1
        if rowIn then
          for x = t.x, math.min(t.x1 - 1, x0 - 1) do
            if c[base + x - t.x] ~= 0 then
              mark(x, y)
            end
          end
          for x = math.max(t.x, x1 + 1), t.x1 - 1 do
            if c[base + x - t.x] ~= 0 then
              mark(x, y)
            end
          end
        else
          for k = base, base + t.w - 1 do
            if c[k] ~= 0 then
              mark(t.x + k - base, y)
            end
          end
        end
      end
    elseif t.uniform ~= 0 and (t.x1 - 1 < x0 or t.x > x1 or t.y1 - 1 < y0 or t.y > y1) then
      mark(t.x, t.y)
    end
  end
  return count, bx0, by0, bx1, by1
end

while true do
  local job = inCh:demand()
  if job == "quit" then
    break
  end
  local ok, err = pcall(function()
    local t0 = love.timer.getTime()
    local World = require("src.world")
    local cavegen = require("src.cavegen")
    local materials = require("src.materials")
    local world = World.new(job.w, job.h, job.left, job.top)
    local r = job.region
    marker = job.marker or nil
    -- the strip of the real world the build reads and cuts into
    for _, st in ipairs(job.seeds) do
      world:importRegion(st[1], st[2], st[3], st[4], st[5], 0, st[4] - st[2])
    end
    if job.area.profileData then
      job.area.profile = require("src.profiles").make(job.area.profileData)
    end
    world.lazyLog = {}
    local info = cavegen.generate(world, job.area, job.seed)
    local built = love.timer.getTime()
    -- (the layout holds the area's own spec, which may hold a function: the main thread puts its own spec back)
    local hadArea = info.area ~= nil
    info.area = nil
    local bad, bx0, by0, bx1, by1 = leaked(world, r[1], r[2], r[3], r[4])
    if bad > 0 then
      error(string.format("the build wrote %d cells outside the region it was given back (x %d..%d, y %d..%d)", bad, bx0, bx1, by0, by1))
    end
    local bytes = world:exportRegion(r[1], r[2], r[3], r[4])
    outCh:push({
      ok = true,
      id = job.id,
      i = job.i,
      info = info,
      hadArea = hadArea,
      links = sharedLinks(info),
      bytes = bytes,
      lazy = world.lazyLog,
      tints = world.tints or {},
      kits = materials.kitExport(),
      built = built - t0,
      total = love.timer.getTime() - t0,
    })
  end)
  if not ok then
    outCh:push({ ok = false, id = job.id, i = job.i, err = tostring(err) })
  end
end
