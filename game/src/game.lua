-- Top-level game state: owns the current scene, world, player and systems,
-- and wires them into LÖVE's callbacks (called from main.lua).
--
-- A scene module provides:
--   title, subtitle               banner shown on entry
--   build(opts) -> world, spawnX, spawnY
--   populate(world)               place targets/props (after physics exists)
-- and optionally:
--   update(dt, player, game)      triggers, e.g. game.enter("mine")
--   drawBackground(camX, camY)    on the low-res canvas, behind everything
--   drawDecor()                   world-space decorations behind the player
--   drawScreen(toScreen, font)    full-resolution text such as signs
local bullets = require("src.bullets")
local camera = require("src.camera")
local effects = require("src.effects")
local hud = require("src.hud")
local physics = require("src.physics")
local Player = require("src.player")
local props = require("src.props")
local render = require("src.render")
local targets = require("src.targets")

local scenes = {
  overworld = require("src.scenes.overworld"),
  mine = require("src.scenes.mine"),
  testroom = require("src.scenes.testroom"),
}

local game = {}

local scene, world, player
local pending -- { name, opts } of a scene to load on the next update
local fade = 0 -- black overlay alpha, fades out after entering a scene
local mouseVX, mouseVY = 0, 0
local showPhysics = false

-- Queues a scene change. Loading happens next update so a "loading" frame
-- can be drawn first (generation takes a moment).
function game.enter(name, opts)
  pending = { name = name, opts = opts }
end

local function load(name, opts)
  scene = assert(scenes[name], "unknown scene: " .. tostring(name))
  bullets.clear()
  effects.clear()
  local spawnX, spawnY
  world, spawnX, spawnY = scene.build(opts)
  physics.init(world)
  scene.populate(world)
  player = Player.new(spawnX, spawnY, world)
  camera.snap(world, player:center())
  hud.showBanner(scene.title, scene.subtitle)
  fade = 1
end

function game.load()
  render.load()
  love.mouse.setVisible(false)
  load("overworld")
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

  fade = math.max(0, fade - dt * 2)
  render.layout()
  mouseVX, mouseVY = render.toVirtual(love.mouse.getPosition())
  local camX, camY = camera.offset()
  local aimX, aimY = mouseVX + camX, mouseVY + camY

  player:update(dt, aimX, aimY)
  player:syncPhysics(dt)
  physics.update(dt)
  player:ride(dt)

  targets.update(dt)
  props.update(dt)
  bullets.update(dt, world)
  effects.update(dt, world)
  world:refresh()
  hud.update(dt)

  if scene.update then
    scene.update(dt, player, game)
  end

  local px, py = player:center()
  camera.update(dt, world, px, py, aimX, aimY)
end

local function drawLoading()
  love.graphics.clear(0, 0, 0)
  local f = hud.font(render.scale)
  local text = "Descending..."
  love.graphics.setFont(f)
  love.graphics.setColor(1, 0.86, 0.45)
  local ww, wh = love.graphics.getDimensions()
  love.graphics.print(text, math.floor((ww - f:getWidth(text)) / 2), math.floor(wh / 2))
  pending.drawn = true
end

function game.draw()
  if pending then
    drawLoading()
    return
  end
  local camX, camY = camera.offset()

  render.beginWorld()
  if scene.drawBackground then
    scene.drawBackground(camX, camY)
  end
  love.graphics.push()
  love.graphics.translate(-camX, -camY)
  if scene.drawDecor then
    scene.drawDecor()
  end
  world:draw()
  targets.draw()
  props.draw()
  player:draw()
  bullets.draw()
  effects.drawWorld()
  if showPhysics then
    physics.drawDebug()
  end
  love.graphics.pop()
  hud.drawCrosshair(mouseVX, mouseVY)
  if fade > 0 then
    love.graphics.setColor(0, 0, 0, fade)
    love.graphics.rectangle("fill", 0, 0, 480, 270)
  end
  render.endWorld()

  -- Full-resolution overlays
  local function toScreen(x, y)
    return render.toScreen(x - camX, y - camY)
  end
  local font = hud.font(render.scale)
  if scene.drawScreen then
    scene.drawScreen(toScreen, font)
  end
  effects.drawScreen(toScreen, font)
  hud.draw(player, render.scale)
  love.graphics.setColor(1, 1, 1)
end

function game.keypressed(key)
  if pending then
    return
  end
  if key == "w" or key == "space" then
    player:pressJump()
  elseif key == "f" then
    player:kick()
  elseif key == "r" then
    game.enter("overworld")
  elseif key == "f9" then
    game.enter("testroom")
  elseif key == "f10" then
    game.enter("mine")
  elseif key == "f2" then
    showPhysics = not showPhysics
  end
end

return game
