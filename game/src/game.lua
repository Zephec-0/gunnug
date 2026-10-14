-- Top-level game state: owns the current scene, world, player and systems,
-- and wires them into LÖVE's callbacks (called from main.lua).
--
-- A scene module provides:
--   title, subtitle               banner shown on entry
--   build(opts) -> world, spawnX, spawnY
--   populate(world)               place targets/props (after physics exists)
-- and optionally:
--   update(dt, player, game, effects)  triggers, ambient effects
--   background()                  work that keeps going even while paused
--                                 (menus, the weapon panel), such as generation
--   ambient                       light level colour (default: fully lit)
--   addLights(lighting, camX, camY) light sources (lanterns, candles, moon)
--   drawFront(camX, camY)         world-space layer in front of the player (lit)
--   drawEmissive(camX, camY)      world-space glows drawn after the lighting
--   drawBackground(camX, camY)    on the low-res canvas, behind everything
--   drawDecor(camX, camY)         world-space decorations behind the player
--   drawScreen(toScreen, font)    full-resolution text such as signs
local audio = require("src.audio")
local bullets = require("src.bullets")
local camera = require("src.camera")
local chests = require("src.chests")
local compare = require("src.compare")
local config = require("src.config")
local effects = require("src.effects")
local deaths = require("src.deaths")
local enemies = require("src.enemies")
local fuser = require("src.fuser")
local guns = require("src.guns")
local hud = require("src.hud")
local input = require("src.input")
local inventory = require("src.inventory")
local items = require("src.items")
local itembar = require("src.itembar")
local lighting = require("src.lighting")
local menu = require("src.menu")
local menubg = require("src.menubg")
local perks = require("src.perks")
local physics = require("src.physics")
local pickups = require("src.pickups")
local Player = require("src.player")
local props = require("src.props")
local render = require("src.render")
local save = require("src.save")
local settings = require("src.settings")
local shop = require("src.shop")
local targets = require("src.targets")
local toasts = require("src.toasts")

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

-- Recording into the save slot (src.save): every weapon, ammo type and
-- attachment that reaches the inventory is counted once (the same object
-- picked up again isn't counted twice), and so is every perk taken in a run
local counted = setmetatable({}, { __mode = "k" })
local runPerks = {}
local lastGold = 0
local deathCounted
local playing = false -- a run is under way (not on the title screen)
local discoveries = {} -- this run's first-time compendium entries: { category, id }
local deadTime = 0 -- seconds the hunter has been dead (the recap follows the death animation)
local deathPhoto -- the killer, photographed the moment he died (false: nothing to photograph)
local RECAP_DELAY = 1.5
local DEATH_FADE_START = 0.3 -- the fade to the recap starts this long after the fall

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
  fuser.clear()
  pickups.clear()
  chests.clear()
  shop.clear()
  compare.close()
  local spawnX, spawnY
  world, spawnX, spawnY = scene.build(opts)
  physics.init(world)
  scene.populate(world)
  player = Player.new(spawnX, spawnY, world, inv)
  bullets.player = player
  camera.snap(player:center())
  hud.showBanner(scene.title, scene.subtitle)
  fade = 1
end

-- Starts a fresh run in the overworld
local function newRun()
  inv = inventory.new()
  runPerks, lastGold = {}, 0
  discoveries, deadTime, deathPhoto = {}, 0, nil
  audio.setRecap(false)
  if itembar.isOpen() then
    itembar.toggle()
  end
  game.enter("overworld")
  if playing then
    save.stat("runs")
  end
end

local function note(thing, category, id)
  if thing and not counted[thing] then
    counted[thing] = true
    save.record(category, id)
  end
end

-- Logs what the run has collected into the profile (cheap: a few slots a frame)
local function track(area)
  if not save.profile() or not inv then
    return
  end
  for i = 1, inventory.WEAPON_SLOTS do
    local gun = inv.weapons[i]
    if gun then
      note(gun, "weapon", gun.id)
      for s = 1, gun.slotCount do
        local item = gun.slots[s]
        if item then
          note(item, item.kind, items.key(item.id, item.level))
        end
      end
    end
  end
  for i = 1, inventory.ITEM_SLOTS do
    local item = inv.items[i]
    if item then
      note(item, item.kind, items.key(item.id, item.level))
    end
  end
  for i = 1, 2 do
    local item = inv.fuse.slots[i]
    if item then
      note(item, item.kind, items.key(item.id, item.level))
    end
  end
  for _, id in ipairs(inv.perks) do
    if not runPerks[id] then
      runPerks[id] = true
      save.record("perk", id)
    end
  end
  if inv.gold > lastGold then
    save.stat("gold", inv.gold - lastGold)
  end
  lastGold = inv.gold
  if area then
    save.statMax("deepest", area)
  end
  if player.dead and deathCounted ~= player then
    deathCounted = player
    save.stat("deaths")
    save.flush()
  end
end

function game.load()
  audio.load()
  render.load()
  lighting.load()
  settings.load()
  -- A first discovery pops up a note at the side of the screen
  save.onDiscover = function(category, id)
    if playing then
      toasts.discover(category, id)
      discoveries[#discoveries + 1] = { category, id }
    end
  end
  menu.onAction = function(action, arg)
    game.menuAction(action, arg)
  end
  love.mouse.setVisible(false)
  inv = inventory.new()
  -- A replaced weapon drops at the hunter's feet
  compare.onChoose = function(index, newGun, pickup)
    local old = inv.weapons[index]
    inv.weapons[index] = newGun
    if pickup.shop then
      shop.take(pickup, inv) -- bought: pay now that a weapon to replace was chosen
    else
      pickups.remove(pickup)
    end
    local px, py = player:center()
    pickups.dropWeapon(px + player.facing * 6, py, old, player.facing * 70, -50)
    effects.weaponCard(px, py - 22, newGun)
  end
  -- The fuser's tooltip names a result only once the save file has found it
  itembar.isKnown = function(category, id)
    return save.count(category, id) > 0
  end
  -- The fuser's lock, from its button on the item bar
  itembar.onFuseToggle = function()
    if player and not player.dead then
      fuser.toggle(inv, player)
    end
  end
  -- With all weapon slots full, picking up a weapon asks which to replace
  pickups.onWeaponFull = function(p)
    compare.open(p.gun, p)
  end
  -- So do weapons dragged off the bar
  itembar.onDropWeapon = function(gun)
    local px, py = player:center()
    pickups.dropWeapon(px + player.facing * 6, py, gun, player.facing * 70, -50)
  end
  -- Items dragged out of the inventory land on the ground by the hunter's feet
  itembar.onDrop = function(item)
    local px, py = player:center()
    pickups.dropItem(px + player.facing * 6, py, item, player.facing * 70, -50)
  end
  -- Kills: heal, momentum and refills for the hunter, and Death Burst
  enemies.onKill = function(e, fx)
    if player then
      player:onKill(e, fx)
    end
    -- Its ether charges a locked fuser
    if inv then
      local b = e.body
      fuser.onKill(inv, b.x + b.w / 2, b.y + b.h / 2, e.def.boss and not (e.group and e.group.alive > 1))
    end
    -- Into the bestiary (a split Queen counts once, when the last of her falls)
    if not (e.group and e.group.alive > 1) then
      save.record("enemy", e.kind)
      save.stat("kills")
      if e.def.boss then
        save.stat("bosses")
      end
    else
      save.stat("kills")
    end
    if perks.has("death_burst") then
      local b = e.body
      local x, y = b.x + b.w / 2, b.y + b.h / 2
      effects.explosion(x, y, 22)
      audio.play("explosion", 0.6)
      enemies.damageArea(x, y, 22, 12, 180)
    end
  end
  load("overworld") -- the first world is built behind the title screen
  menu.open("title")
  audio.setMenu(true)
end

-- Carries out what a menu chose (src.menu calls this)
function game.menuAction(action, arg)
  if action == "play" then
    -- Into a run with the chosen save slot (the world behind the title is fresh)
    save.use(arg)
    settings.set("lastSlot", arg)
    playing = true
    save.stat("runs")
    runPerks, lastGold, deathCounted = {}, inv and inv.gold or 0, nil
    discoveries, deadTime, deathPhoto = {}, 0, nil
    menu.close()
    audio.setMenu(false)
    toasts.clear()
    hud.showBanner(scene.title, scene.subtitle)
  elseif action == "resume" then
    menu.close()
  elseif action == "restart" then
    newRun()
    menu.close()
  elseif action == "title" then
    save.flush()
    playing = false
    newRun()
    menu.open("title")
    audio.setMenu(true)
  elseif action == "quit" then
    save.flush()
    love.event.quit()
  end
end

-- Typed text, for the name entry (main.lua passes love.textinput on)
function game.textinput(text)
  menu.textinput(text)
end

-- Saves on the way out (main.lua calls this from love.quit)
function game.quit()
  save.flush()
end

-- The window lost focus: pause, if the setting says so
function game.focus(focused)
  if not focused and playing and not menu.isOpen() and settings.get("pauseOnFocusLoss") then
    menu.open("pause")
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
  local underground, area, inShop = 0, nil, false
  if scene.undergroundFactor and not menu.isOpen() then
    underground = scene.undergroundFactor(player:center())
    if scene.audioInfo then
      area, inShop = scene.audioInfo(player:center())
    end
  end
  -- (with the weapon panel open the area's sound plays on, but muffled)
  audio.update(dt, underground, menu.isOpen(), area, inShop, itembar.isOpen())
  -- The weapon panel and the menus pause the game, like Noita's inventory
  love.mouse.setVisible(itembar.isOpen() or menu.isOpen() or compare.isOpen())
  menu.update(dt)
  if menu.isFrontEnd() then
    menubg.update(dt)
  end
  save.update(dt, playing and not (itembar.isOpen() or menu.isOpen() or compare.isOpen()))
  toasts.update(dt)
  compare.update()
  if scene.background then
    scene.background()
  end
  if playing then
    track(area)
    -- A death: once the hunter has finished falling, the recap
    if player.dead and not menu.isOpen() then
      if deathPhoto == nil then
        -- The picture for the wanted poster, taken as he falls
        local source = player.lastSource
        deathPhoto = enemies.defs[source] and enemies.photo(player.lastEnemy, source) or false
      end
      deadTime = deadTime + dt
      if deadTime >= RECAP_DELAY then
        local profile = save.profile()
        local recap = deaths.recap(profile and profile.name, player.lastSource)
        recap.discoveries = discoveries
        recap.photo = deathPhoto or nil
        recap.slot = save.activeSlot()
        toasts.clear()
        menu.open("recap", recap)
        audio.setRecap(true)
      end
    elseif not player.dead then
      deadTime, deathPhoto = 0, nil
    end
  end
  if itembar.isOpen() or menu.isOpen() or compare.isOpen() then
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
  chests.update(dt)
  shop.update(dt, player)
  bullets.update(dt, world)
  enemies.update(dt, world, player)
  pickups.update(dt, world, player)
  fuser.update(dt, world, player, inv)
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

-- The title screen: the black hole, with the menu over it
local function drawFrontEnd()
  menubg.prepare()
  render.beginWorld()
  menubg.draw()
  menu.drawWorldLayer()
  render.endWorld()
  menu.draw(render.uiScale())
  love.graphics.setColor(1, 1, 1)
end

function game.draw()
  if menu.isFrontEnd() then
    -- (a world being built behind the title doesn't blank the screen)
    if pending then
      pending.drawn = true
    end
    drawFrontEnd()
    return
  end
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
  props.addLights(lighting, view)
  chests.addLights(lighting, view)
  shop.addLights(lighting, view)
  bullets.addLights(lighting)
  effects.addLights(lighting)
  fuser.addLights(lighting)
  if scene.addLights then
    scene.addLights(lighting, camX, camY)
  end
  lighting.render(camX, camY, function()
    world:draw(camX, camY, config.VIRTUAL_W, config.VIRTUAL_H)
  end)

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
  props.draw(view)
  chests.draw(view)
  shop.draw(view)
  enemies.draw(view)
  player:draw()
  effects.drawWorld()
  if scene.drawFront then
    scene.drawFront(camX, camY)
  end
  love.graphics.pop()

  lighting.drawMotes(camX, camY)
  lighting.apply()

  -- Emissive pass: glows that ignore the darkness
  love.graphics.push()
  love.graphics.translate(-camX, -camY)
  if scene.drawEmissive then
    scene.drawEmissive(camX, camY)
  end
  player:drawEmissive()
  enemies.drawEmissive(view)
  props.drawEmissive(view)
  pickups.drawEmissive(view)
  chests.drawEmissive(view)
  shop.drawEmissive(view)
  bullets.draw()
  effects.drawEmissive()
  fuser.drawEmissive()
  if showPhysics then
    physics.drawDebug()
  end
  love.graphics.pop()
  -- A red flash when the hunter is hurt
  if player.hurtFlash > 0 then
    love.graphics.setColor(0.7, 0.05, 0.05, 0.28 * player.hurtFlash)
    love.graphics.rectangle("fill", 0, 0, config.VIRTUAL_W, config.VIRTUAL_H)
  end
  if not itembar.isOpen() and not menu.isOpen() and not compare.isOpen() and not player.dead then
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
  enemies.drawScreen(toScreen, font)
  pickups.drawScreen(toScreen, font, player)
  chests.drawScreen(toScreen, font, player)
  shop.drawScreen(toScreen, font, player)
  -- Hovering the mouse over a weapon lying about, or on a shop pedestal, shows
  -- what it is before you take it
  if not (itembar.isOpen() or menu.isOpen() or compare.isOpen()) then
    local wx, wy = mouseVX + camX, mouseVY + camY
    local gun, gx, gy = pickups.weaponAt(wx, wy)
    if not gun then
      gun, gx, gy = shop.weaponAt(wx, wy)
    end
    if gun then
      local sx, sy = toScreen(gx, gy)
      effects.drawWeaponCard(sx, sy, gun, font)
    end
  end
  -- The title screen stands alone; a pause menu keeps the HUD but hides the
  -- area banner, which would show through it
  if menu.state() ~= "title" and menu.state() ~= "recap" then
    hud.hideBanner = menu.isOpen() or compare.isOpen()
    hud.draw(player, render.uiScale())
    itembar.draw(inv, render.uiScale())
  end
  -- Dying: once he has fallen, the world fades darker toward the recap (which
  -- picks up with the same darkness, the world still showing behind it)
  if playing and player.dead and not menu.isOpen() and deadTime > DEATH_FADE_START then
    local ww, wh = love.graphics.getDimensions()
    local k = math.min(1, (deadTime - DEATH_FADE_START) / (RECAP_DELAY - DEATH_FADE_START))
    love.graphics.setColor(0.05, 0.01, 0.02, 0.8 * k)
    love.graphics.rectangle("fill", 0, 0, ww, wh)
  end
  compare.draw(inv, render.uiScale())
  toasts.draw(render.uiScale())
  menu.draw(render.uiScale())
  love.graphics.setColor(1, 1, 1)
end

-- Returns true if the key was handled (main.lua uses this so Escape closes
-- the weapon panel or opens the pause menu instead of quitting)
function game.keypressed(key)
  if key == "f11" then
    settings.set("fullscreen", not settings.get("fullscreen"))
    return true
  end
  if menu.isOpen() then
    menu.keypressed(key)
    return true -- a menu swallows every key
  end
  if pending then
    return false
  end
  if compare.isOpen() then
    compare.keypressed(key)
    return true -- and so does the compare prompt
  end
  if input.is("fuse", key) and not player.dead then
    fuser.toggle(inv, player)
    return true
  end
  if input.is("inventory", key) or (key == "escape" and itembar.isOpen()) then
    itembar.toggle()
    return true
  elseif key == "escape" then
    menu.open("pause")
    return true
  elseif input.is("weapon1", key) or input.is("weapon2", key) or input.is("weapon3", key) then
    inv:select(input.is("weapon1", key) and 1 or (input.is("weapon2", key) and 2 or 3))
    return true
  end
  if itembar.isOpen() then
    return false -- everything else waits until the panel is closed
  end
  if input.is("jump", key) and not player.dead then
    player:pressJump()
  elseif input.is("kick", key) and not player.dead then
    player:kick()
  elseif input.is("roll", key) and not player.dead then
    player:pressRoll()
  elseif input.is("interact", key) and not player.dead then
    if not chests.interact(player) and not shop.interact(player) then
      pickups.interact(player)
    end
  elseif key == "f6" and not player.dead then
    -- Debug: swaps the held weapon for a randomly generated one
    local gun = guns.generate()
    inv.weapons[inv.selected] = gun
    local px, py = player:center()
    effects.weaponCard(px, py - 22, gun)
  elseif input.is("restart", key) then
    newRun()
  elseif key == "f9" then
    game.enter("testroom")
  elseif key == "f10" then
    game.enter("overworld", { atCave = true }) -- a fresh world, starting at the catacombs' entrance
  elseif key == "f8" and scene.toArena and not player.dead then
    -- Testing: straight to the Sulfur Queen's arena
    scene.toArena(player)
    camera.snap(player:center())
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
  if compare.isOpen() then
    return
  end
  if itembar.mousepressed(inv, x, y, button) or pending or itembar.isOpen() then
    return
  end
  if button == 2 and inv:selectedGun() then
    if inv:selectedGun():reload() then
      audio.play("reload")
    end
  end
end

function game.mousereleased(x, y, button)
  if menu.isOpen() then
    menu.mousereleased(x, y, button)
    return
  end
  if compare.isOpen() then
    compare.mousereleased(x, y, button)
    return
  end
  itembar.mousereleased(inv, x, y, button)
end

function game.wheelmoved(dx, dy)
  if menu.isOpen() then
    menu.wheelmoved(dx, dy)
    return
  end
  if dy ~= 0 and not itembar.isOpen() and not menu.isOpen() and not compare.isOpen() then
    inv:cycle(dy > 0 and -1 or 1)
  end
end

-- For tests and future pickups
function game.inventory()
  return inv
end

function game.player()
  return player
end

return game
