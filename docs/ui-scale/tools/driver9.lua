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

local ctrl, shift, fire = false, false, false
local realMouseDown = love.mouse.isDown
love.mouse.isDown = function(b, ...) if fire and b == 1 then return true end return realMouseDown(b, ...) end
local realDown = love.keyboard.isDown
love.keyboard.isDown = function(k, ...)
  if ctrl and (k == "lctrl" or k == "rctrl") then return true end
  if shift and (k == "lshift" or k == "rshift") then return true end
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
-- The gas line in area 1
step(10, function()
  local cat = require("src.scenes.catacombs")
  cat.finish(1)
  local info = cat.info(1)
  GL = info and info.gaslines and info.gaslines[1]
  print("gasline", GL and GL.x, GL and GL.y, GL and GL.dir)
  require("src.dev").noDamage = true
end)
step(30, function() if GL then put(GL.slit.x + GL.dir * 30, GL.y - 22) end end)
step(60, function() if GL then shot("gasline.png") end end)
step(4, function()
  if GL then
    local r = GL.room
    print("lit", require("src.fluids").ignite((r.x0 + r.x1) / 2, (r.y0 + r.y1) / 2, 1))
  end
end)
step(150, function()
  if GL then
    shot("gasline-open.png")
    local w, p = player().world, GL.plug
    local clear = true
    for y = p.y0 + 1, p.y1 - 2 do
      for x = math.min(p.x0, GL.slit.x + GL.dir * 46), math.max(p.x1, GL.slit.x + GL.dir * 46) do
        if w:isSolid(x, y) then clear = false end
      end
    end
    print("doorway clear", clear)
  end
end)
-- Test room: goo, shift-equip, shooting oil
step(6, function() game.enter("testroom") end)
step(40, function()
  local inv = game.inventory()
  local items = require("src.items")
  for _, id in ipairs({ "rimebolt", "lance", "reddot" }) do inv:addItem(items.new(id)) end
  require("src.status").apply(player(), "oiled")
end)
step(40, function() shot("goo-1.png") end)
step(25, function() shot("goo-2.png") end)
step(2, function()
  player().status = {}
  require("src.itembar").toggle()
  love.mouse.setPosition(330, 60)
  shift = true
end)
step(10, function() shot("bar-shift.png") end)
step(2, function()
  local inv = game.inventory()
  local before = inv:get({ kind = "item", index = 1 })
  require("src.itembar").mousepressed(inv, 330, 60, 1)
  local gun = inv:selectedGun()
  print("shift-click fitted:", before and before.name, gun.slots[1] and gun.slots[1].name, inv:get({ kind = "item", index = 1 }) == nil)
  love.mouse.setPosition(60, 60)
  print("on a weapon:", require("src.itembar").equipTarget(inv, love.mouse.getPosition()))
  shift = false
  require("src.itembar").toggle()
  -- oil on the ground to the right, then shoot it
  local p = player()
  local cx, cy = p:center()
  OX, OY = cx + 50, p.body.y + p.body.h - 2
  print("oil cells", require("src.fluids").addOil(OX, OY - 6, 40))
end)
step(90, function()
  local f = require("src.fluids")
  local p = player()
  local cx, cy = p:center()
  local found
  for dx = 20, 200, 2 do
    for dy = -40, 60, 2 do
      if not found and f.oilAt(cx + dx, cy + dy) then found = { cx + dx, cy + dy } end
    end
  end
  print("oil found", found and found[1] - cx, found and found[2] - cy)
  if found then
    OX, OY = found[1], found[2]
    local cam = require("src.camera")
    local sx, sy = require("src.render").toScreen(OX - cam.x, OY - cam.y)
    love.mouse.setPosition(sx, sy)
    fire = true
  end
end)
step(40, function()
  fire = false
  local f = require("src.fluids")
  local burning, oilLeft = false, false
  for dx = -40, 40, 2 do
    for dy = -8, 8, 2 do
      if f.fireAt(OX + dx, OY + dy) then burning = true end
      if f.oilAt(OX + dx, OY + dy) then oilLeft = true end
    end
  end
  print("after shots: fire", burning, "oil left", oilLeft)
  shot("oil-shot.png")
end)
step(20, function() love.event.quit(0) end)

function love.update(dt)
  frame = frame + 1
  if script[frame] then script[frame]() end
  game.update(1 / 60)
end

function love.draw()
  game.draw()
end
