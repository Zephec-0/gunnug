-- General frame-rate benchmark driver: camp, each area, arenas.
local game = require("src.game")
local catacombs = require("src.scenes.catacombs")
local dev = require("src.dev")

local OUT = {}
local function log(s) print(s); OUT[#OUT + 1] = s; love.filesystem.write("perf.txt", table.concat(OUT, "\n")) end

function love.errorhandler(msg)
  print(debug.traceback(msg, 2)); love.filesystem.write("perf-error.txt", debug.traceback(msg, 2)); return function() return 1 end
end

local WARM, MEASURE = 90, 300
local steps = {{ kind = "camp", name = "camp" }}
local stage, frame, started = 0, 0, false
local rec
local fakeX, fakeT = 0, 0

function love.load()
  game.load()
local only = os.getenv("BENCH_AREAS")
local n = catacombs.count()
for i = 1, n do
  if not only or ("," .. only .. ","):find("," .. i .. ",", 1, true) then
    steps[#steps + 1] = { kind = "area", i = i, name = "area " .. i .. " " .. tostring(catacombs.areaName(i)) }
  end
end
for _, i in ipairs(catacombs.arenaAreas()) do
  if not only or ("," .. only .. ","):find("," .. i .. ",", 1, true) then
    steps[#steps + 1] = { kind = "arena", i = i, name = "arena " .. i }
  end
end


  require("src.menu").close()
  game.menuAction("play", 1)
  dev.noDamage = true
  -- shoot and walk so projectiles / effects / enemy AI are exercised
  local realDown = love.mouse.isDown
  love.mouse.isDown = function(b) return b == 1 end
  love.mouse.getPosition = function() return 900 + math.sin(fakeT) * 300, 300 end
  love.keyboard.isDown = function(k)
    if k == "d" or k == "right" then return math.sin(fakeT * 0.5) > 0.2 end
    if k == "a" or k == "left" then return math.sin(fakeT * 0.5) < -0.2 end
    return false
  end
  game.devTeleport(steps[1])
end

local function pct(t, p) table.sort(t); return t[math.max(1, math.floor(#t * p))] end

function love.update(dt)
  fakeT = fakeT + dt
  local t0 = os.clock()
  game.update(dt)
  if rec then rec.upd[#rec.upd + 1] = (os.clock() - t0) * 1000 end
end

function love.draw()
  local t0 = os.clock()
  game.draw()
  love.graphics.setColor(1, 1, 1)
  frame = frame + 1
  if frame == WARM then
    rec = { upd = {}, drw = {}, ft = {}, calls = 0, n = 0 }
    collectgarbage("collect"); collectgarbage("stop"); rec.mem0 = collectgarbage("count")
  elseif rec then
    rec.drw[#rec.drw + 1] = (os.clock() - t0) * 1000
    rec.ft[#rec.ft + 1] = love.timer.getDelta() * 1000
    rec.calls = rec.calls + love.graphics.getStats().drawcalls
    rec.n = rec.n + 1
    if rec.n >= MEASURE then
      local mem = (collectgarbage("count") - rec.mem0) / rec.n
      collectgarbage("restart")
      local sum = 0 for _, v in ipairs(rec.ft) do sum = sum + v end
      local avg = sum / #rec.ft
      local us, ds = 0, 0
      for _, v in ipairs(rec.upd) do us = us + v end
      for _, v in ipairs(rec.drw) do ds = ds + v end
      log(string.format("%-28s fps %6.1f  frame avg %5.2f p95 %5.2f p99 %5.2f max %6.2f | upd %5.2f draw %5.2f ms | calls %4d | %5.1f KB/frame",
        steps[stage + 1].name, 1000 / avg, avg, pct(rec.ft, 0.95), pct(rec.ft, 0.99), rec.ft[#rec.ft], us / #rec.upd, ds / #rec.drw, rec.calls / rec.n, mem))
      rec = nil
      stage = stage + 1
      if stage >= #steps then log("DONE"); love.event.quit(); return end
      frame = 0
      local t = os.clock()
      game.devTeleport(steps[stage + 1])
    end
  end
end
