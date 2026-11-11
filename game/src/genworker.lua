-- Builds the dungeon's areas on worker threads (src.genthread) and puts the results into the real world.
--
-- An area's build (cavegen.generate) is a second or two of Lua that used to run on the main thread in slices of
-- the frame. Here it runs on another core instead, in a world of its own, and the main thread only
--   * sends the job: the area's spec and seed, and the cells of the part of the world the build works in (its
--     rectangle, the gaps beside it and a strip above: it reads what is there, and cuts the shaft down from the
--     area above into it),
--   * and, when the result comes back, merges it: the cells of the area's rectangle (and that strip) are copied
--     into the real world, the lazy-painting operations are replayed, the tints and the decoration materials
--     added, and the layout (plain data) handed on.
-- The merge is cut into slices of a millisecond or two a frame. The terrain and layout that come out are the
-- same as the main thread's own build would have made (checked cell for cell, see docs/threads.md).
--
-- Anything that goes wrong (no threads, a worker error, a build that wrote outside its rectangle) hands the area
-- back to the main thread's own build, which is still there.
local materials = require("src.materials")

local genworker = {}

genworker.enabled = true -- (the dev panel can turn it off)
local POOL = 2 -- worker threads
local STRIP = 64 -- rows above an area that are sent in and taken back (its build writes 58 of them)
-- Areas whose build writes beyond their rectangle (and beyond the gaps between side-by-side areas, which are
-- always included): px to the left and right. A build that writes outside what it was given is refused (the
-- worker says so, and the main thread builds that area itself), so a missing entry costs only the speed-up.
local EXTRA = {
  ["The Cloud Reaches"] = { left = 480 },
  ["The Quarry"] = { right = 64 },
  ["The Mesosphere"] = { left = 64, right = 64 },
}
local MERGE_ROWS = 16 -- rows of the rectangle copied per step of a merge (the clock is looked at after each step)

local ffiOk = pcall(require, "ffi")
local workers = {}
local failedForGood = false
local nextId = 0
local merges = {} -- results being merged, in the order they arrived: { res, stage, row, trans }
local epoch = 0 -- bumped for every new world: a result from an earlier one is dropped

-- Is it on? (and possible: threads, and the FFI the cells are copied with)
function genworker.available()
  return genworker.enabled and not failedForGood and ffiOk and love.thread ~= nil
end

local function spawn()
  local k = #workers + 1
  local w = { inName = "gen_in_" .. k, outName = "gen_out_" .. k }
  w.inCh, w.outCh = love.thread.getChannel(w.inName), love.thread.getChannel(w.outName)
  w.inCh:clear()
  w.outCh:clear()
  w.thread = love.thread.newThread("src/genthread.lua")
  w.thread:start(w.inName, w.outName)
  workers[k] = w
  return w
end

-- How many workers could take a job now
function genworker.free()
  local free = 0
  for _, w in ipairs(workers) do
    if not w.job then
      free = free + 1
    end
  end
  return free + (POOL - #workers)
end

function genworker.busy()
  for _, w in ipairs(workers) do
    if w.job and w.job.epoch == epoch then
      return true
    end
  end
  return #merges > 0
end

-- The part of the world an area's build works in: its rectangle, the gaps beside it (to a neighbour built side by
-- side with it), and a strip above (its shaft is cut down into the floor of the area over it)
local function regionOf(area, world)
  local ex = EXTRA[area.name]
  local gl, gr = math.max(area.gapLeft or 0, ex and ex.left or 0), math.max(area.gapRight or 0, ex and ex.right or 0)
  local x0, x1 = math.max(world.left, area.x0 - gl), math.min(world.right - 1, area.x1 + gr)
  local top = math.max(world.top, math.min(area.y0 - STRIP, (area.shaftTop or math.huge) - 24))
  return { x0, top, x1, math.min(world.bottom - 1, area.y1) }
end

local function overlaps(a, b)
  return not (a[3] < b[1] or b[3] < a[1] or a[4] < b[2] or b[4] < a[2])
end

-- Sends the build of an area. area: its spec (plain data), seed, world: the real one (what lies round the area is
-- read from it now), marker: the hunter's death marker for the area, if any.
-- Returns true if it is on its way; false if not now (no worker is free, or another build is working where this one
-- would), false, "unsendable" if this area can never go to a worker.
function genworker.submit(i, area, seed, world, marker)
  local region = regionOf(area, world)
  -- (two builds that work on the same cells run one after the other, as they would on the main thread: the later one
  -- starts from what the earlier left)
  for _, w in ipairs(workers) do
    if w.job and overlaps(region, w.job.region) then
      return false
    end
  end
  for _, m in ipairs(merges) do
    if overlaps(region, m.res.region) then
      return false
    end
  end
  local w
  for _, c in ipairs(workers) do
    if not c.job then
      w = c
      break
    end
  end
  if not w and #workers < POOL then
    local ok, made = pcall(spawn)
    if not ok then
      failedForGood = true
      print("genworker: no worker thread (" .. tostring(made) .. "), areas are built on the main thread")
      return false
    end
    w = made
  end
  if not w then
    return false
  end
  -- the cells of the whole region as they are now: the build reads what is there before it writes (the overworld's own
  -- terrain lies in some areas' rectangles, and the shaft is cut down into the floor of the area above), so it is given
  -- exactly what the main thread's build would have found
  local seeds = { { region[1], region[2], region[3], region[4], world:exportRegion(region[1], region[2], region[3], region[4]) } }
  nextId = nextId + 1
  local job = {
    id = nextId,
    i = i,
    area = area,
    seed = seed,
    w = world.width,
    h = world.height,
    left = world.left,
    top = world.top,
    region = region,
    seeds = seeds,
    marker = marker or false,
  }
  local pushed, why = pcall(w.inCh.push, w.inCh, job)
  if not pushed then
    print("genworker: area " .. tostring(i) .. " cannot be sent to a worker (" .. tostring(why) .. "), it is built on the main thread")
    return false, "unsendable"
  end
  w.job = { id = job.id, i = i, sent = love.timer.getTime(), region = region, epoch = epoch }
  return true
end

-- A new world has begun (a new run): what was sent for the old one is dropped when it comes back
function genworker.reset()
  epoch = epoch + 1
  merges = {}
end

function genworker.inFlight(i)
  for _, w in ipairs(workers) do
    if w.job and w.job.i == i then
      return true
    end
  end
  for _, m in ipairs(merges) do
    if m.res.i == i then
      return true
    end
  end
  return false
end

-- The areas' own copies of a table that was shared inside the result (a channel copies it once for every place
-- it is found): joined again
local function relink(info, links)
  for _, l in ipairs(links) do
    local src = info
    for _, k in ipairs(l.from) do
      src = src[k]
    end
    local dst = info
    for n = 1, #l.to - 1 do
      dst = dst[l.to[n]]
    end
    dst[l.to[#l.to]] = src
  end
end

local function identity()
  local t = {}
  for k = 0, 255 do
    t[k] = k
  end
  return t
end

-- One step of a merge, until `deadline` (love.timer.getTime). Returns true when it is finished.
local function mergeStep(m, deadline, world)
  local res = m.res
  local r = res.region
  if m.stage == 1 then
    relink(res.info, res.links)
    -- the decoration materials the worker made have ids of its own: the cells get the main thread's
    for _, k in ipairs(res.kits) do
      local mine = materials.decorKit(k.name, k.support, k.colors)
      for n = 1, 3 do
        if mine[n] ~= k.ids[n] then
          m.trans = m.trans or identity()
          m.trans[k.ids[n]] = mine[n]
        end
      end
    end
    world.tints = world.tints or {}
    for _, t in ipairs(res.tints) do
      if m.trans then
        local ids = {}
        for id in pairs(t.ids) do
          ids[m.trans[id] or id] = true
        end
        t.ids = ids
      end
      world.tints[#world.tints + 1] = t
    end
    for _, op in ipairs(res.lazy) do
      if op[1] == "claim" then
        world:claim(op[2], op[3], op[4], op[5])
      end
    end
    m.stage, m.row = 2, 0
  end
  if m.stage == 2 then
    local rows = r[4] - r[2] + 1
    while m.row < rows do
      world:importRegion(r[1], r[2], r[3], r[4], res.bytes, m.row, m.row + MERGE_ROWS - 1, m.trans)
      m.row = m.row + MERGE_ROWS
      if love.timer.getTime() > deadline then
        return false
      end
    end
    -- the cells are in: the lazy painting is set up as the build did (and tiles already painted are repainted)
    for _, op in ipairs(res.lazy) do
      if op[1] == "mark" then
        world:markLazy(op[2], op[3], op[4], op[5])
      elseif op[1] == "deferred" then
        world:repaintDeferred(op[2], op[3], op[4], op[5])
      end
    end
    m.stage = 3
  end
  return true
end

-- Collects what the workers have finished and works on the merges for up to `budget` seconds. For each area that is
-- complete handler(i, info, res) is called; for one that could not be built, handler(i, nil, res) (res.err says why).
-- wait: keep going (sleeping a little) until something has been handled or `budget` has run out.
function genworker.pump(world, budget, handler, wait)
  local deadline = love.timer.getTime() + budget
  local handled = false
  repeat
    for _, w in ipairs(workers) do
      if w.job then
        local res = w.outCh:pop()
        if res then
          local job = w.job
          w.job = nil
          if job.epoch ~= epoch then
            -- (built for a world that is gone)
          elseif res.ok then
            res.region = job.region
            merges[#merges + 1] = { res = res, stage = 1 }
          else
            print("genworker: area " .. tostring(res.i) .. " failed on the worker (" .. tostring(res.err) .. ")")
            handler(res.i, nil, res)
            handled = true
          end
        else
          local err = w.thread:getError()
          if err then
            print("genworker: a worker thread died: " .. tostring(err))
            failedForGood = true
            local i = w.job.i
            w.job = nil
            handler(i, nil, { err = err })
            handled = true
          end
        end
      end
    end
    local m = merges[1]
    if m then
      if mergeStep(m, math.max(deadline, love.timer.getTime() + 0.0005), world) then
        table.remove(merges, 1)
        handler(m.res.i, m.res.info, m.res)
        handled = true
      end
    end
    if wait and not handled and love.timer.getTime() < deadline then
      love.timer.sleep(0.001)
    end
  until not wait or handled or love.timer.getTime() >= deadline
  return handled
end

-- Stops the workers (they finish the build they are on first)
function genworker.shutdown()
  for _, w in ipairs(workers) do
    w.inCh:push("quit")
  end
end

return genworker
