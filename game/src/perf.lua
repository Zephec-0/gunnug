-- Frame-time readout and test switches for the dev panel (F2). Dev builds only: a released build never
-- shows the readout or turns anything off (everything below is gated on perf.show / perf.off, both empty there).
--
--   perf.start(group)  begin timing a group of sections ("update" or "draw")
--   perf.lap(name)     the time since the last lap (or start) goes to `name` in that group
--   perf.off[key]      true: the part of the game called `key` is skipped (see perf.SWITCHES for the list)
--
-- Laps are CPU time. The GPU runs a frame or so behind, so a cheap-looking lap can hide an expensive shader:
-- "Wait for the GPU at each lap" (perf.sync) reads one pixel back after every lap, which makes each lap include
-- the GPU work queued before it (the frame gets slower while it is on). The surest test stays the frame time
-- shown on the top line when a part is switched off.
local perf = { show = false, sync = false, off = {} }

local groups = {} -- name -> { order = {...}, ms = { lap = ms } }
local current
local base
local syncCanvas
local frame = { dt = 1 / 60 }

-- { key, label } in the order the dev panel lists them. A part is on unless perf.off[key] is set.
perf.SWITCHES = {
  { "head", "Lighting passes" },
  { "lights", "Light sources (all lights)" },
  { "rays", "Shadow rays (rock and sprite shadows)" },
  { "haze", "Haze pass around lights" },
  { "fog", "Cave fog and mist" },
  { "relief", "Terrain relief shading" },
  { "motes", "Dust motes" },
  { "apply", "Light map over the scene (all lighting)" },
  { "head", "Scene layers" },
  { "baked", "Baked cave backdrop layers (off: redrawn every frame)" },
  { "background", "Background / parallax" },
  { "decor", "Area decor (backdrops, scenery, vents)" },
  { "terrain", "Terrain" },
  { "objects", "Props, chests, shops, NPCs, events" },
  { "enemies", "Enemies (drawing)" },
  { "front", "Front layer (water, reflections, smoke, oil)" },
  { "effects", "Effects, critters, hunter's particles" },
  { "emissive", "Glows / emissive pass" },
  { "fogdraw", "Fog of war overlay" },
  { "weather", "Weather overlay" },
  { "head", "Simulation" },
  { "fluids", "Water and gas simulation" },
  { "enemyAI", "Enemies thinking and moving" },
  { "bullets", "Bullets" },
  { "ambient", "Critters, ambience, weather" },
}

function perf.on(key)
  return not perf.off[key]
end

local function flush()
  if not syncCanvas then
    syncCanvas = love.graphics.newCanvas(1, 1)
  end
  love.graphics.push("all")
  love.graphics.setCanvas(syncCanvas)
  love.graphics.clear(0, 0, 0, 1)
  love.graphics.pop()
  syncCanvas:newImageData() -- (a read back waits for everything queued before it)
end

function perf.start(group)
  if not perf.show then
    return
  end
  current = groups[group]
  if not current then
    current = { order = {}, ms = {} }
    groups[group] = current
  end
  if perf.sync then
    flush()
  end
  base = love.timer.getTime()
end

function perf.lap(name)
  if not perf.show or not current then
    return
  end
  if perf.sync then
    flush()
  end
  local now = love.timer.getTime()
  local ms = (now - base) * 1000
  base = now
  local old = current.ms[name]
  if old then
    current.ms[name] = old + (ms - old) * 0.06
  else
    current.ms[name] = ms
    current.order[#current.order + 1] = name
  end
end

-- Switches that are off (the readout shows them, so a forgotten one is noticed)
local function offList()
  local out = {}
  for _, s in ipairs(perf.SWITCHES) do
    if s[1] ~= "head" and perf.off[s[1]] then
      out[#out + 1] = s[1]
    end
  end
  return out
end

-- The laps as { group = { { name, ms }, ... } } (for tests)
function perf.snapshot()
  local out = {}
  for g, grp in pairs(groups) do
    out[g] = {}
    for _, name in ipairs(grp.order) do
      out[g][#out[g] + 1] = { name, grp.ms[name] }
    end
  end
  return out
end

function perf.reset()
  for k in pairs(perf.off) do
    perf.off[k] = nil
  end
  groups = {}
end

function perf.draw(u)
  if not perf.show then
    return
  end
  local itembar = require("src.itembar")
  local font = itembar.font(3.2 * u)
  local dt = love.timer.getDelta()
  frame.dt = frame.dt + (dt - frame.dt) * 0.06
  local x, y = 3 * u, 12 * u
  local lh = 3.9 * u
  local function line(text, color)
    itembar.shadowPrint(text, x, y, font, color)
    y = y + lh
  end
  local stats = love.graphics.getStats()
  line(string.format("%.0f fps   %.1f ms/frame   %d draw calls   %d canvas switches%s", 1 / frame.dt, frame.dt * 1000, stats.drawcalls, stats.canvasswitches, perf.sync and "   [GPU sync]" or ""), { 1, 1, 0.6 })
  local n = #require("src.lighting").list()
  line(string.format("%d lights this frame", n), { 0.8, 0.8, 0.85 })
  local off = offList()
  if #off > 0 then
    line("OFF: " .. table.concat(off, ", "), { 1, 0.5, 0.5 })
  end
  for _, g in ipairs({ "update", "draw" }) do
    local grp = groups[g]
    if grp then
      local total = 0
      for _, name in ipairs(grp.order) do
        total = total + grp.ms[name]
      end
      line(string.format("%s  %.2f ms", g, total), { 0.75, 0.6, 0.95 })
      for _, name in ipairs(grp.order) do
        local ms = grp.ms[name]
        local c = ms > 2 and { 1, 0.45, 0.4 } or ms > 0.7 and { 1, 0.85, 0.45 } or { 0.82, 0.82, 0.88 }
        line(string.format("%6.2f  %s", ms, name), c)
      end
    end
  end
end

return perf
