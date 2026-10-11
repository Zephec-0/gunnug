-- Top-level game state: owns the current scene, world, player and systems,
-- and wires them into LÖVE's callbacks (called from main.lua).
--
-- A scene module provides:
--   title, subtitle               banner shown on entry
--   build(opts) -> world, spawnX, spawnY
--   populate(world)               place targets/props (after physics exists)
-- and optionally:
--   update(dt, player, game, effects)  triggers, ambient effects, background work
--   ambient                       light level colour (default: fully lit)
--   addLights(lighting, camX, camY) light sources (lanterns, candles, moon)
--   drawEmissive(camX, camY)      world-space glows drawn after the lighting
--   drawBackground(camX, camY)    on the low-res canvas, behind everything
--   drawDecor(camX, camY)         world-space decorations behind the player
--   drawScreen(toScreen, font)    full-resolution text such as signs
local bullets = require("src.bullets")
local camera = require("src.camera")
local config = require("src.config")
local effects = require("src.effects")
local enemies = require("src.enemies")
local guns = require("src.guns")
local hud = require("src.hud")
local inventory = require("src.inventory")
local itembar = require("src.itembar")
local lighting = require("src.lighting")
local menu = require("src.menu")
local physics = require("src.physics")
local pickups = require("src.pickups")
local Player = require("src.player")
local props = require("src.props")
local render = require("src.render")
local targets = require("src.targets")

-- The overworld scene is the whole world (surface and catacombs); the test
-- room is a separate tuning ground
local scenes = {
  overworld = require("src.scenes.overworld"),
  testroom = require("src.scenes.testroom"),
}

local game = {}

local scene, world, player
local inv -- the run's inventory; survives area changes, reset on restart
local pending -- { name, opts } of a scene to load on the next update
local fade = 0 -- black overlay alpha, fades out after entering a scene
local mouseVX, mouseVY = 0, 0
local showPhysics = false

-- Queues a scene change (a new run, or the test room). Loading happens next
-- update, after one blank frame.
function game.enter(name, opts)
  pending = { name = name, opts = opts }
end

local function load(name, opts)
  scene = assert(scenes[name], "unknown scene: " .. tostring(name))
  bullets.clear()
  effects.clear()
  enemies.clear()
  pickups.clear()
  local spawnX, spawnY
  world, spawnX, spawnY = scene.build(opts)
  physics.init(world)
  scene.populate(world)
  player = Player.new(spawnX, spawnY, world, inv)
  camera.snap(player:center())
  hud.showBanner(scene.title, scene.subtitle)
  fade = 1
end

-- Starts a fresh run in the overworld
local function newRun()
  inv = inventory.new()
  if itembar.isOpen() then
    itembar.toggle()
  end
  game.enter("overworld")
end

function game.load()
  render.load()
  lighting.load()
  love.mouse.setVisible(false)
  inv = inventory.new()
  -- Items dragged out of the inventory land on the ground by the hunter's feet
  itembar.onDrop = function(item)
    local px, py = player:center()
    pickups.dropItem(px + player.facing * 6, py, item, player.facing * 70, -50)
  end
  load("overworld")
  menu.open("title") -- the world waits, dimmed, behind the title screen
end

-- Carries out the action a menu button chose
local function menuAction(action)
  if action == "play" then
    menu.close()
    hud.showBanner(scene.title, scene.subtitle)
  elseif action == "resume" then
    menu.close()
  elseif action == "restart" then
    newRun()
    menu.close()
  elseif action == "title" then
    newRun()
    menu.open("title")
  elseif action == "quit" then
    love.event.quit()
  end
end

function game.update(dt)
  dt = math.min(dt, 1 / 30) -- avoid huge steps after hitches

  if pending then
    if pending.drawn then
      local p = pending
      pending = nil
      load(p.name, p.opts)
    end
    return
  end

  render.layout()
  -- The weapon panel and the menus pause the game, like Noita's inventory
  love.mouse.setVisible(itembar.isOpen() or menu.isOpen())
  menu.update()
  if itembar.isOpen() or menu.isOpen() then
    return
  end

  fade = math.max(0, fade - dt * 2)
  mouseVX, mouseVY = render.toVirtual(love.mouse.getPosition())
  local camX, camY = camera.offset()
  local aimX, aimY = mouseVX + camX, mouseVY + camY

  -- A dead hunter stays where he fell until the run is restarted (R)
  if not player.dead then
    player:update(dt, aimX, aimY)
  end
  player:updateHurt(dt)
  player:syncPhysics(dt)
  enemies.syncPhysics(dt)
  props.snapshotVelocities()
  physics.update(dt)
  if not player.dead then
    player:ride(dt)
  end

  targets.update(dt)
  props.update(dt)
  bullets.update(dt, world)
  enemies.update(dt, world, player)
  pickups.update(dt, world, player)
  effects.update(dt, world)
  world:refresh()
  hud.update(dt)

  if scene.update then
    scene.update(dt, player, game, effects)
  end

  local px, py = player:center()
  camera.update(dt, px, py, aimX, aimY)
end

local function drawLoading()
  love.graphics.clear(0, 0, 0)
  pending.drawn = true
end

function game.draw()
  if pending then
    drawLoading()
    return
  end
  local camX, camY = camera.offset()

  -- Light map for this frame (scene ambient + every light source)
  local view = { x = camX, y = camY, w = config.VIRTUAL_W, h = config.VIRTUAL_H }
  lighting.begin(scene.ambient)
  player:addLights(lighting)
  enemies.addLights(lighting, view)
  pickups.addLights(lighting, view)
  bullets.addLights(lighting)
  effects.addLights(lighting)
  if scene.addLights then
    scene.addLights(lighting, camX, camY)
  end
  lighting.render(camX, camY)

  render.beginWorld()
  if scene.drawBackground then
    scene.drawBackground(camX, camY)
  end
  love.graphics.push()
  love.graphics.translate(-camX, -camY)
  if scene.drawDecor then
    scene.drawDecor(camX, camY)
  end
  world:draw(camX, camY, config.VIRTUAL_W, config.VIRTUAL_H)
  targets.draw()
  props.draw()
  enemies.draw(view)
  player:draw()
  effects.drawWorld()
  love.graphics.pop()

  lighting.apply()

  -- Emissive pass: glows that ignore the darkness
  love.graphics.push()
  love.graphics.translate(-camX, -camY)
  if scene.drawEmissive then
    scene.drawEmissive(camX, camY)
  end
  player:drawEmissive()
  enemies.drawEmissive(view)
  pickups.drawEmissive(view)
  bullets.draw()
  effects.drawEmissive()
  if showPhysics then
    physics.drawDebug()
  end
  love.graphics.pop()
  -- A red flash when the hunter is hurt
  if player.hurtFlash > 0 then
    love.graphics.setColor(0.7, 0.05, 0.05, 0.28 * player.hurtFlash)
    love.graphics.rectangle("fill", 0, 0, config.VIRTUAL_W, config.VIRTUAL_H)
  end
  if not itembar.isOpen() and not menu.isOpen() and not player.dead then
    hud.drawCrosshair(mouseVX, mouseVY)
  end
  if fade > 0 then
    love.graphics.setColor(0, 0, 0, fade)
    love.graphics.rectangle("fill", 0, 0, config.VIRTUAL_W, config.VIRTUAL_H)
  end
  render.endWorld()

  -- Full-resolution overlays
  local function toScreen(x, y)
    return render.toScreen(x - camX, y - camY)
  end
  local font = hud.font(render.uiScale())
  if scene.drawScreen then
    scene.drawScreen(toScreen, font)
  end
  effects.drawScreen(toScreen, font)
  pickups.drawScreen(toScreen, font, player)
  -- The title screen stands alone; a pause menu keeps the HUD but hides the
  -- area banner, which would show through it
  if menu.state() ~= "title" then
    hud.hideBanner = menu.isOpen()
    hud.draw(player, render.uiScale())
    if player.dead then
      hud.drawDeath(render.uiScale())
    end
    itembar.draw(inv, render.uiScale())
  end
  menu.draw(render.uiScale())
  love.graphics.setColor(1, 1, 1)
end

-- Returns true if the key was handled (main.lua uses this so Escape closes
-- the weapon panel or opens the pause menu instead of quitting)
function game.keypressed(key)
  if pending then
    return false
  end
  if menu.isOpen() then
    menuAction(menu.keypressed(key))
    return true -- a menu swallows every key
  end
  if key == "tab" or (key == "escape" and itembar.isOpen()) then
    itembar.toggle()
    return true
  elseif key == "escape" then
    menu.open("pause")
    return true
  elseif key == "1" or key == "2" or key == "3" then
    inv:select(tonumber(key))
    return true
  end
  if itembar.isOpen() then
    return false -- everything else waits until the panel is closed
  end
  if (key == "w" or key == "space") and not player.dead then
    player:pressJump()
  elseif key == "f" and not player.dead then
    player:kick()
  elseif key == "e" and not player.dead then
    pickups.interact(player)
  elseif key == "f6" and not player.dead then
    -- Debug: swaps the held weapon for a randomly generated one
    local gun = guns.generate()
    inv.weapons[inv.selected] = gun
    local px, py = player:center()
    effects.popup(px, py - 14, gun.name, { 1, 0.9, 0.6 })
  elseif key == "r" then
    newRun()
  elseif key == "f9" then
    game.enter("testroom")
  elseif key == "f10" then
    game.enter("overworld", { atCave = true }) -- a fresh world, starting at the catacombs' entrance
  elseif key == "f2" then
    showPhysics = not showPhysics
  else
    return false
  end
  return true
end

function game.mousepressed(x, y, button)
  if menu.isOpen() then
    menu.mousepressed(x, y, button)
    return
  end
  if itembar.mousepressed(inv, x, y, button) or pending or itembar.isOpen() then
    return
  end
  if button == 2 and inv:selectedGun() then
    inv:selectedGun():reload()
  end
end

function game.mousereleased(x, y, button)
  if menu.isOpen() then
    menuAction(menu.mousereleased(x, y, button))
    return
  end
  itembar.mousereleased(inv, x, y, button)
end

function game.wheelmoved(_, dy)
  if dy ~= 0 and not itembar.isOpen() and not menu.isOpen() then
    inv:cycle(dy > 0 and -1 or 1)
  end
end

-- For tests and future pickups
function game.inventory()
  return inv
end

return game
