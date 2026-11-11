if not os.getenv("NOJITTUNE") then require("src.jittune") end
local JO = os.getenv("JITOPT")
if JO then
  local args = {}
  for a in JO:gmatch("[^,]+") do args[#args + 1] = a end
  require("jit.opt").start(unpack(args))
end
-- Benchmark driver. SCEN=combat (default) | travel. BENCH_AREAS=1,3,5. OUT=name of the result file.
local game = require("src.game")
local catacombs = require("src.scenes.catacombs")
local dev = require("src.dev")
local perf = require("src.perf")
local enemies = require("src.enemies")
local items = require("src.items")
local guns = require("src.guns")
local camera = require("src.camera")
local render = require("src.render")
local bullets = require("src.bullets")

io.stdout:setvbuf("no")
local SCEN = os.getenv("SCEN") or "combat"
local OUTNAME = os.getenv("OUT") or ("perf-" .. SCEN .. ".txt")
local NEN = tonumber(os.getenv("NEN") or "14")
local MEASURE = tonumber(os.getenv("FRAMES") or "600")
local getTime = love.timer.getTime

local OUT = {}
local function log(s)
  print(s)
  OUT[#OUT + 1] = s
end
local function flushLog()
  love.filesystem.write(OUTNAME, table.concat(OUT, "\n"))
end

function love.errorhandler(msg)
  local tb = debug.traceback(tostring(msg), 2)
  print(tb)
  OUT[#OUT + 1] = tb
  flushLog()
  return function()
    return 1
  end
end

-- raw per-frame laps
local frameLaps, group, base = {}, "", 0
perf.show = false
perf.start = function(g)
  group = g
  base = getTime()
end
perf.lap = function(name)
  local now = getTime()
  local k = group .. ": " .. name
  frameLaps[k] = (frameLaps[k] or 0) + (now - base) * 1000
  base = now
end
perf.draw = function() end

local function timed(tbl, key, label)
  local f = tbl[key]
  tbl[key] = function(a, b, c, d, e, g, h, i2, j2, k2)
    local t0 = getTime()
    local r1, r2, r3 = f(a, b, c, d, e, g, h, i2, j2, k2)
    local k = "x: " .. label
    frameLaps[k] = (frameLaps[k] or 0) + (getTime() - t0) * 1000
    return r1, r2, r3
  end
end
if os.getenv("XT") then
  local World = require("src.world")
  local gw = require("src.genworker")
  timed(World, "repaintDeferred", "World:repaintDeferred")
  timed(World, "importRegion", "World:importRegion")
  timed(World, "exportRegion", "World:exportRegion")
  timed(World, "prewarm", "World:prewarm")
  timed(World, "draw", "World:draw")
  timed(World, "flushRepaints", "World:flushRepaints")
  timed(World, "refresh", "World:refresh")
  timed(gw, "submit", "genworker.submit")
  timed(gw, "pump", "genworker.pump")
  timed(catacombs, "spawnProps", "catacombs.spawnProps")
  timed(catacombs, "ensure", "catacombs.ensure")
  timed(catacombs, "update", "catacombs.update")
  timed(require("src.physics"), "update", "physics.update")
  timed(require("src.fluids"), "update", "fluids.update")
  timed(require("src.fluids"), "runJobs", "fluids.runJobs")
  timed(require("src.fog"), "update", "fog.update")
  timed(require("src.fog"), "draw", "fog.draw")
  timed(require("src.audio"), "update", "audio.update")
  timed(require("src.save"), "update", "save.update")
end
local player, world
local fire, aimSX, aimSY = false, 900, 400
local keys = {}

local function loadout()
  local inv = game.inventory()
  local id = os.getenv("GUN") or "automatic"
  local g = guns.new(id, 8)
  local list = os.getenv("AMMO") or "scatter,incendiary,ricochet,splitting,shock,poison,glowing,seeker"
  local n = 0
  for name in list:gmatch("[^,]+") do
    n = n + 1
    g.slots[n] = items.new(name, 0)
  end
  inv.weapons[1] = g
  inv.selected = 1
  return g
end

local gun
local kinds = {}

local function free(x, y, w, h)
  for yy = y, y + h, 4 do
    for xx = x, x + w, 4 do
      if world:isSolid(math.floor(xx), math.floor(yy)) then
        return false
      end
    end
  end
  return true
end

local function topUp()
  local px, py = player:center()
  local n = 0
  for _, e in ipairs(enemies.nearby()) do
    local b = e.body
    if not e.dead and math.abs(b.x - px) < 300 and math.abs(b.y - py) < 170 then
      n = n + 1
    end
  end
  local tries = 0
  while n < NEN and tries < 200 do
    tries = tries + 1
    local kind = kinds[love.math.random(1, #kinds)]
    local def = enemies.defs[kind]
    local x = px + (love.math.random() - 0.5) * 520
    local y = py + (love.math.random() - 0.5) * 240
    if math.abs(x - px) > 50 and free(x - def.w / 2, y - def.h, def.w, def.h) then
      local sy
      if def.ground then
        sy = world:findGround(math.floor(x), math.floor(y))
        if sy and sy - y > 120 then
          sy = nil
        end
      else
        sy = y
        while sy > y - 200 and not world:isSolid(math.floor(x), math.floor(sy)) do
          sy = sy - 1
        end
        sy = sy + 1
      end
      if sy then
        enemies.spawn(kind, x, sy, 1, 1)
        n = n + 1
      end
    end
  end
end

local function areaKinds(i)
  kinds = {}
  local seen = {}
  local x0, y0, x1, y1 = catacombs.bounds(i)
  for _, e in ipairs(enemies.every()) do
    local b = e.body
    if b.x >= x0 and b.x <= x1 and b.y >= y0 and b.y <= y1 and not e.def.boss and not e.def.dummy and not seen[e.kind] and not e.segs and e.kind ~= "queen" then
      seen[e.kind] = true
      kinds[#kinds + 1] = e.kind
    end
  end
  if #kinds == 0 then
    kinds = { "ghoul", "bat", "spitter" }
  end
  table.sort(kinds)
end

local function aimNearest()
  local px, py = player:center()
  local best, bd
  for _, e in ipairs(enemies.nearby()) do
    if not e.dead then
      local b = e.body
      local d = (b.x - px) ^ 2 + (b.y - py) ^ 2
      if not bd or d < bd then
        best, bd = e, d
      end
    end
  end
  local camX, camY = camera.baseOffset()
  if best then
    aimSX, aimSY = render.toScreen(best.body.x + best.body.w / 2 - camX, best.body.y + best.body.h / 2 - camY)
  else
    aimSX, aimSY = render.toScreen(px + 100 - camX, py - camY)
  end
end

-- sampling profiler (GC must be stopped while it samples; starting it flushes every compiled trace, so one long window)
local PROF = os.getenv("PROF")
local profL, profF, profV, profOn, profTotal = {}, {}, {}, false, 0
local profile = PROF and require("jit.profile")
local function profStart()
  if not PROF or profOn then return end
  collectgarbage("collect")
  collectgarbage("stop")
  profOn = true
  profile.start("li1", function(th, samples, vmstate)
    local k = profile.dumpstack(th, "pl", 1)
    profL[k] = (profL[k] or 0) + samples
    k = profile.dumpstack(th, "pF", 1)
    profF[k] = (profF[k] or 0) + samples
    profV[vmstate] = (profV[vmstate] or 0) + samples
    profTotal = profTotal + samples
  end)
end
local function profStop()
  if not profOn then return end
  profile.stop()
  profOn = false
  collectgarbage("restart")
  collectgarbage("collect")
end
local function top(tbl, n, title)
  local list = {}
  for k, v in pairs(tbl) do list[#list + 1] = { k, v } end
  table.sort(list, function(a, b) return a[2] > b[2] end)
  OUT[#OUT + 1] = "-- " .. title
  for i = 1, math.min(#list, n) do OUT[#OUT + 1] = string.format("  %5.1f%%  %s", list[i][2] / profTotal * 100, list[i][1]) end
end
local function profReport()
  if not PROF then return end
  OUT[#OUT + 1] = "samples " .. profTotal
  top(profV, 10, "vm state (N compiled, I interpreted, C C code, J compiler, G collector)")
  local byFile = {}
  for k, v in pairs(profL) do
    local f = k:match("([%w_]+%.lua)") or k
    byFile[f] = (byFile[f] or 0) + v
  end
  top(byFile, 40, "by file")
  top(profF, tonumber(os.getenv("PROFN") or "90"), "by function")
  top(profL, tonumber(os.getenv("PROFN") or "90"), "by line")
  profL, profF, profV, profTotal = {}, {}, {}, 0
end

-- trace compiler events (JITSTAT=1)
local jitStat = { start = 0, stop = 0, abort = 0, flush = 0 }
if os.getenv("JITSTAT") then
  jit.attach(function(what) jitStat[what] = (jitStat[what] or 0) + 1 end, "trace")
end

-- inclusive timers round every function of the listed modules (WRAP=1)
local wrapStats = {}
local function wrapModule(name, t)
  for k, f in pairs(t) do
    if type(f) == "function" then
      local st = { name = name .. "." .. k, t = 0, n = 0 }
      wrapStats[#wrapStats + 1] = st
      local function fin(t0, ...)
        st.t = st.t + (getTime() - t0)
        st.n = st.n + 1
        return ...
      end
      t[k] = function(...)
        return fin(getTime(), f(...))
      end
    end
  end
end
local function wrapReport(n)
  table.sort(wrapStats, function(a, b) return a.t > b.t end)
  OUT[#OUT + 1] = "-- inclusive time per frame, by function"
  for i = 1, math.min(#wrapStats, tonumber(os.getenv("PROFN") or "60")) do
    local s = wrapStats[i]
    if s.n > 0 then
      OUT[#OUT + 1] = string.format("  %7.3f ms  %8.1f calls/f  %s", s.t * 1000 / n, s.n / n, s.name)
    end
  end
  for _, s in ipairs(wrapStats) do s.t, s.n = 0, 0 end
end

-- stages
local steps = {}
local stage, frame = 0, 0
local rec
local fakeT = 0
local route, routeT -- travel

local function pct(t, p)
  table.sort(t)
  return t[math.max(1, math.min(#t, math.ceil(#t * p)))]
end

local function begin(step)
  frame = 0
  rec = nil
  if step.kind == "travel" then
    return
  end
  game.devTeleport(step)
  player = game.player()
  world = player.world
  if step.kind == "area" then
    areaKinds(step.i)
  end
end

local function report(name)
  local n = rec.n
  local sum = 0
  for _, v in ipairs(rec.ft) do
    sum = sum + v
  end
  local avg = sum / n
  local over8, over16, over33 = 0, 0, 0
  for _, v in ipairs(rec.ft) do
    if v > 8.34 then over8 = over8 + 1 end
    if v > 16.7 then over16 = over16 + 1 end
    if v > 33.4 then over33 = over33 + 1 end
  end
  local mem = rec.mem / n
  log(string.format("== %-26s fps %6.1f | frame avg %5.2f p50 %5.2f p95 %5.2f p99 %5.2f max %6.2f | >8.3ms %d >16.7 %d >33 %d of %d | upd %5.2f draw %5.2f | calls %4d | %6.1f KB/f | bullets %.0f enemies %.0f",
    name, 1000 / avg, avg, pct(rec.ft, 0.5), pct(rec.ft, 0.95), pct(rec.ft, 0.99), rec.ft[#rec.ft], over8, over16, over33, n,
    rec.upd / n, rec.drw / n, rec.calls / n, mem, rec.bul / n, rec.en / n))
  log(string.format("     loop: pump %.2f present %.2f sleep %.2f ms avg", (rec.pump or 0) / n, (rec.present or 0) / n, (rec.sleep or 0) / n))
  local list = {}
  for k, v in pairs(rec.laps) do
    list[#list + 1] = { k, v / n, rec.lapMax[k] }
  end
  table.sort(list, function(a, b) return a[2] > b[2] end)
  for i = 1, math.min(#list, tonumber(os.getenv("TOP") or "16")) do
    log(string.format("     %6.3f ms (max %6.2f)  %s", list[i][2], list[i][3], list[i][1]))
  end
  if rec.spikes then
    table.sort(rec.spikes, function(a, b) return a.ft > b.ft end)
    for i = 1, math.min(#rec.spikes, 25) do
      local s = rec.spikes[i]
      log(string.format("   spike %6.1f ms at frame %d (%.0f, %.0f) area %s: %s", s.ft, s.frame, s.x, s.y, tostring(s.area), s.what))
    end
  end
  flushLog()
end

function love.load()
  love.math.setRandomSeed(12345)
  game.load()
  require("src.menu").close()
  game.menuAction("play", 1)
  dev.noDamage = true
  love.mouse.isDown = function(b)
    return b == 1 and fire
  end
  love.mouse.getPosition = function()
    return aimSX, aimSY
  end
  love.keyboard.isDown = function(...)
    for i = 1, select("#", ...) do
      if keys[select(i, ...)] then
        return true
      end
    end
    return false
  end
  love.window.setVSync(0)
  if os.getenv("WRAP") then
    for _, m in ipairs({ "effects", "bullets", "enemies", "fluids", "physics", "pickups", "fog", "hud", "itembar", "lighting", "props", "gore", "status", "audio", "juice", "quads", "softglow", "fuser", "critters", "ambience", "toasts", "body" }) do
      local ok, mod = pcall(require, "src." .. m)
      if ok and type(mod) == "table" then wrapModule(m, mod) end
    end
    wrapModule("World", getmetatable(game.player().world).__index)
  end
  local _, _, mode = love.window.getMode()
  log("display refresh " .. tostring(mode.refreshrate) .. " vsync " .. tostring(love.window.getVSync()) .. " window " .. love.graphics.getWidth() .. "x" .. love.graphics.getHeight() .. " renderer " .. table.concat({ love.graphics.getRendererInfo() }, " "))
  if SCEN == "paint" then
    local world = game.player().world
    for a in (os.getenv("BENCH_AREAS") or "1,2,3,4,5"):gmatch("[^,]+") do
      local i = tonumber(a)
      catacombs.generate(i)
      local x0, y0, x1, y1 = catacombs.bounds(i)
      local cx, cy = math.floor((x0 + x1) / 2), math.floor((y0 + y1) / 2)
      for n, spot in ipairs({ { cx - 256, cy - 256 }, { cx - 256, y1 - 600 }, { x0 + 100, y0 + 200 } }) do
        local rx0, ry0 = spot[1], spot[2]
        local rx1, ry1 = rx0 + 511, ry0 + 511
        local nop = function() end
        world:repaintRect(rx0, ry0, rx1, ry1, nop)
        world:repaintRect(rx0, ry0, rx1, ry1, nop)
        local best = math.huge
        if PROF then profStart() end
        for _ = 1, (PROF and 12 or 4) do
          local t0 = getTime()
          world:repaintRect(rx0, ry0, rx1, ry1)
          best = math.min(best, getTime() - t0)
        end
        if PROF then profStop() end
        local h = 0
        for y = ry0, ry1 do
          for x = rx0, rx1 do
            local r, g, b, al = world:pixelColor(x, y)
            h = (h * 31 + math.floor(r * 255 + 0.5) + math.floor(g * 255 + 0.5) * 3 + math.floor(b * 255 + 0.5) * 7 + math.floor((al or 0) * 255 + 0.5) * 11) % 2147483647
          end
        end
        log(string.format("paint area %2d %-22s spot %d: %6.1f ms for 512x512 = %.3f us/px  hash %d", i, tostring(catacombs.areaName(i)), n, best * 1000, best * 1e6 / (512 * 512), h))
      end
    end
    profReport()
    flushLog()
    love.event.quit()
    steps[1] = { kind = "travel", name = "none" }
    return
  end
  if SCEN == "combat" then
    local only = os.getenv("BENCH_AREAS") or "1,3,5"
    for a in only:gmatch("[^,]+") do
      local i = tonumber(a)
      steps[#steps + 1] = { kind = "area", i = i, name = "area " .. i .. " " .. tostring(catacombs.areaName(i)) }
    end
  else
    steps[1] = { kind = "travel", name = "travel" }
  end
end

function love.quit()
  game.quit()
  print("quit ok")
end

local started = false
local lastUpd = 0
local loopT = { pump = 0, present = 0, sleep = 0, gc = 0 }
local NOSLEEP = not os.getenv("SLEEP")
function love.run()
  love.load(love.arg.parseGameArguments(arg), arg)
  love.timer.step()
  local dt = 0
  return function()
    local t0 = getTime()
    love.event.pump()
    for name, a, b, c, d, e, f in love.event.poll() do
      if name == "quit" then
        if not love.quit or not love.quit() then
          return a or 0
        end
      end
      love.handlers[name](a, b, c, d, e, f)
    end
    loopT.pump = (getTime() - t0) * 1000
    dt = love.timer.step()
    love.update(dt)
    love.graphics.origin()
    love.graphics.clear(love.graphics.getBackgroundColor())
    love.draw()
    t0 = getTime()
    love.graphics.present()
    local t1 = getTime()
    loopT.present = (t1 - t0) * 1000
    if not NOSLEEP then love.timer.sleep(0.001) end
    loopT.sleep = (getTime() - t1) * 1000
  end
end

local function travelPos(t)
  -- camp -> shaft along the surface, then down through areas 1..3 with a horizontal weave
  local b = player.body
  if not route then
    local x0, y0, x1, y1 = catacombs.bounds(1)
    local _, _, _, yEnd = catacombs.bounds(tonumber(os.getenv("TRAVEL_TO") or "3"))
    route = { sx = b.x, sy = b.y, cx = (x0 + x1) / 2, top = y0, bottom = yEnd - 200 }
    log(string.format("route: start %.0f,%.0f shaft x %.0f top %.0f bottom %.0f", route.sx, route.sy, route.cx, route.top, route.bottom))
  end
  local r = route
  local walk = math.abs(r.cx - r.sx) / 220
  if t < walk then
    return r.sx + (r.cx - r.sx) * (t / walk), r.sy - 40
  end
  local td = t - walk
  local y = r.sy + td * 300
  if y > r.bottom then
    return nil
  end
  local x = r.cx + math.sin(td * 0.9) * 260
  return x, y
end

function love.update(dt)
  fakeT = fakeT + dt
  if not started then
    started = true
    player = game.player()
    world = player.world
    gun = loadout()
    stage = 1
    begin(steps[1])
  end
  local step = steps[stage]
  if step.kind == "area" then
    if frame % 20 == 0 then
      topUp()
    end
    gun = game.inventory().weapons[1]
    gun.chambers = gun:maxChambers()
    gun.reloadTimer = 0
    fire = frame > 30
    aimNearest()
  elseif step.kind == "travel" then
    dev.noclip = true
    fire = false
    if frame >= 60 then
      routeT = (routeT or 0) + math.min(dt, 1 / 30)
      local x, y = travelPos(routeT)
      if not x then
        step.done = true
      else
        local b = player.body
        b.x, b.y = x, y
      end
    end
  end
  for k in pairs(frameLaps) do
    frameLaps[k] = nil
  end
  local t0 = getTime()
  game.update(dt)
  lastUpd = (getTime() - t0) * 1000
end

function love.draw()
  local t0 = getTime()
  game.draw()
  love.graphics.setColor(1, 1, 1)
  local drw = (getTime() - t0) * 1000
  frame = frame + 1
  local step = steps[stage]
  if os.getenv("SHOTS") and frame % tonumber(os.getenv("SHOTS")) == 0 then
    love.graphics.captureScreenshot(string.format("shot-%s-%05d.png", SCEN, frame))
    print(string.format("shot %d: stale pieces %d", frame, #player.world.stale))
  end
  local warm = step.kind == "travel" and 60 or 150
  if frame == warm then
    collectgarbage("collect")
    rec = { ft = {}, laps = {}, lapMax = {}, upd = 0, drw = 0, calls = 0, n = 0, mem = 0, bul = 0, en = 0, lastMem = collectgarbage("count") }
    if step.kind == "travel" then
      rec.spikes = {}
    end
  elseif rec then
    local ft = love.timer.getDelta() * 1000
    rec.ft[#rec.ft + 1] = ft
    rec.n = rec.n + 1
    rec.upd = rec.upd + lastUpd
    rec.pump = (rec.pump or 0) + loopT.pump
    rec.present = (rec.present or 0) + loopT.present
    rec.sleep = (rec.sleep or 0) + loopT.sleep
    rec.lastPresent, rec.lastSleep = loopT.present, loopT.sleep
    rec.drw = rec.drw + drw
    rec.calls = rec.calls + love.graphics.getStats().drawcalls
    local m = collectgarbage("count")
    if m > rec.lastMem then
      rec.mem = rec.mem + (m - rec.lastMem)
    end
    rec.lastMem = m
    local nb = 0
    bullets.each(function()
      nb = nb + 1
    end)
    rec.bul = rec.bul + nb
    rec.en = rec.en + #enemies.nearby()
    for k, v in pairs(frameLaps) do
      rec.laps[k] = (rec.laps[k] or 0) + v
      if v > (rec.lapMax[k] or 0) then
        rec.lapMax[k] = v
      end
    end
    if rec.spikes then
      -- (the delta just measured is the frame BEFORE this one: its laps were kept in rec.prev)
      local pv = rec.prev
      if pv and ft > 12 then
        local list = {}
        for k, v in pairs(pv.laps) do
          list[#list + 1] = { k, v }
        end
        table.sort(list, function(a, b) return a[2] > b[2] end)
        local parts = {}
        for i = 1, math.min(4, #list) do
          parts[i] = string.format("%.1f %s", list[i][2], list[i][1])
        end
        rec.spikes[#rec.spikes + 1] = { ft = ft, frame = rec.n - 1, x = pv.x, y = pv.y, area = pv.area, what = string.format("upd %.1f drw %.1f present %.1f sleep %.1f | ", pv.upd, pv.drw, loopT.present, loopT.sleep) .. table.concat(parts, "; ") }
      end
      local px, py = player:center()
      pv = pv or { laps = {} }
      for k in pairs(pv.laps) do pv.laps[k] = nil end
      for k, v in pairs(frameLaps) do pv.laps[k] = v end
      pv.upd, pv.drw, pv.x, pv.y, pv.area = lastUpd, drw, px, py, catacombs.levelAt(py, px)
      rec.prev = pv
    end
    if PROF and rec.n == 1 then profStart() end
    local finished = (step.kind == "travel" and step.done) or (step.kind ~= "travel" and rec.n >= MEASURE)
    if finished then
      profStop()
      report(step.name)
      log("stale pieces left: " .. #player.world.stale)
      profReport()
      if os.getenv("JITSTAT") then
        log(string.format("   traces: %d started, %d compiled, %d aborted, %d flushes (whole game so far)", jitStat.start, jitStat.stop, jitStat.abort, jitStat.flush))
      end
      if os.getenv("WRAP") then wrapReport(rec.n) end
      flushLog()
      stage = stage + 1
      if stage > #steps then
        log("DONE")
        flushLog()
        love.event.quit()
        return
      end
      begin(steps[stage])
    end
  end
end
