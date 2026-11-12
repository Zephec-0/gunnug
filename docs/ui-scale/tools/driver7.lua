-- Batch 2026-11-12 checks
require("src.jittune")
https = nil
io.stdout:setvbuf("no")
local game = require("src.game")

function love.errorhandler(msg)
  print("ERROR: " .. tostring(msg))
  print(debug.traceback())
  love.event.quit(1)
end

local OUT = "E:/gametest/docs/batch-1112/"
local function shot(name)
  love.graphics.captureScreenshot(function(data)
    local f = assert(io.open(OUT .. name, "wb"))
    f:write(data:encode("png"):getString())
    f:close()
    print("shot " .. name)
  end)
end

local frame, cursor = 0, 0
local script = {}
local function step(gap, fn)
  cursor = cursor + gap
  script[cursor] = fn
end
local function player() return game.player() end
local function put(x, y)
  local p = player()
  local b = p.body
  b.x, b.y, b.vx, b.vy = x, y, 0, 0
  if p.physBody then p.physBody:setPosition(b.x + b.w / 2, b.y + b.h / 2) end
  require("src.camera").snap(p:center())
end
local function ground(x)
  local p = player()
  return p.world:findGroundUnder(x, p.body.w, 160) - p.body.h
end

local ctrl = false
local realDown = love.keyboard.isDown
love.keyboard.isDown = function(k, ...)
  if ctrl and (k == "lctrl" or k == "rctrl") then return true end
  return realDown(k, ...)
end

function love.load()
  game.load()
end

step(5, function() require("src.settings").set("fullscreen", true) game.menuAction("play", 1) end)
step(15, function()
  print(require("src.devpanel")._unlock())
  require("src.dev").noDamage = false
  game.enter("overworld", { atCave = false })
end)
step(90, function() print("spawn at", player().body.x) shot("camp.png") end)
step(4, function() put(1300, ground(1300)) end)
step(40, function() shot("sign-town-pond.png") end)
step(4, function() put(1440, ground(1440)) end)
step(40, function() shot("sign-ramp.png") end)
step(4, function() put(1622, ground(1622)) end)
step(40, function() shot("sign-pit.png") end)
step(4, function() put(1655, 700) end)
step(25, function() shot("shaft-chevrons.png") end)
-- Poison and fire stop at 1
step(4, function()
  put(956, ground(956))
  local p = player()
  p.hp = 3
  p:hurtOverTime(10, nil, "fire")
  print("after fire", p.hp, p.dead)
  p:hurtOverTime(10, nil, "poison")
  print("after poison", p.hp, p.dead)
  p.hp = p.maxHp
  -- fused items
  local items = require("src.items")
  local n = 0
  for _, f in ipairs(items.fusions) do
    local it = items.new(f[3])
    assert(it and it.name, f[3])
    assert(require("src.icons").get(it), "no icon " .. f[3])
    assert(items.defs[f[1]] and items.defs[f[2]], f[3])
    n = n + 1
  end
  print("fusions ok", n)
  local a, lvl = require("src.fuser").combine(items.new("frost"), items.new("shock"))
  print("frost+shock ->", a, lvl)
end)
-- The sluice in area 2
step(10, function()
  local cat = require("src.scenes.catacombs")
  cat.finish(2)
  for i = 1, 3 do
    local info = cat.info(i)
    print("area", i, info and #(info.sluices or {}), info and info.sluices and info.sluices[1] and info.sluices[1].reservoir ~= nil)
    if info and info.sluices and info.sluices[1] and not SL then
      SL = info.sluices[1]
    end
  end
end)
step(30, function()
  if SL then
    print("sluice", SL.x, SL.y, SL.dir, SL.gate.y0, SL.gate.y1)
    require("src.dev").noDamage = true
    put(SL.x + SL.dir * 60, SL.y - 22)
  end
end)
step(60, function() if SL then shot("sluice.png") end end)
step(4, function()
  if SL and SL.reservoir then
    -- let the reservoir out
    local g = SL.reservoir.plug
    local w = player().world
    w:fillRect(g.x0, g.y0, g.x1, g.y1, 0)
    w:repaintRegion(g.x0 - 3, g.y0 - 3, g.x1 + 3, g.y1 + 3)
  end
end)
step(420, function()
  if SL then
    shot("sluice-open.png")
    local w = player().world
    local g = SL.gate
    print("gate solid after", w:isSolid((g.x0 + g.x1) / 2, (g.y0 + g.y1) / 2))
  end
end)
-- Notes: one vanishes when read, and the world waits
step(4, function()
  local journal = require("src.journal")
  local pg
  for _, p in ipairs(journal.PAGES) do if p.x and p.y then pg = pg or p end end
  if pg then
    put(pg.x - 4, pg.y - 20)
    PG = pg
  end
  print("page", pg and pg.id, pg and pg.x)
  -- (the dev unlock marks every page read: forget that until one is read here)
  local save = require("src.save")
  local realCount, realRecord = save.count, save.record
  local readNow = {}
  save.count = function(cat, id) if cat == "journal" then return readNow[id] and 1 or 0 end return realCount(cat, id) end
  save.record = function(cat, id, ...) if cat == "journal" then readNow[id] = true return end return realRecord(cat, id, ...) end
end)
step(20, function() shot("note-before.png") print("interact", require("src.journal").interact(player()), require("src.journal").isReading()) end)
step(20, function() shot("note-open.png") print("keypress swallowed", game.keypressed("x"), require("src.journal").isReading()) end)
step(20, function() shot("note-after.png") print("again", require("src.journal").interact(player())) require("src.journal").close() end)
-- Test room: bottle, bar, drop mark, reload
step(6, function() game.enter("testroom") end)
step(40, function()
  local inv = game.inventory()
  local items = require("src.items")
  for _, id in ipairs({ "rimebolt", "lance", "motherlode", "reddot", "bandolier", "rocketeer", "limpet", "deadshot", "claimjumper", "icebreaker", "whisper" }) do
    pcall(function() inv:addItem(items.new(id)) end)
  end
  require("src.status").apply(player(), "oiled")
end)
step(90, function() shot("bottle-oiled.png") end)
step(2, function() require("src.status").apply(player(), "soaked") end)
step(60, function() shot("bottle-oiled-soaked.png") end)
step(2, function()
  player().status = {}
  require("src.itembar").toggle()
  love.mouse.setPosition(330, 60)
  ctrl = true
end)
step(10, function() shot("bar-ctrl-x.png") end)
step(2, function()
  local inv = game.inventory()
  local before = inv:get({ kind = "item", index = 1 })
  require("src.itembar").mousepressed(inv, 330, 60, 1)
  print("ctrl-click dropped:", before and before.name, inv:get({ kind = "item", index = 1 }) == nil)
  ctrl = false
  require("src.itembar").toggle()
  local gun = inv:selectedGun()
  gun.chambers = 0
  print("reload started", gun:reload())
end)
step(18, function() shot("bar-reload-1.png") end)
step(14, function() shot("bar-reload-2.png") end)
step(60, function() love.event.quit(0) end)

function love.update(dt)
  frame = frame + 1
  if script[frame] then script[frame]() end
  game.update(1 / 60)
end

function love.draw()
  game.draw()
end
