-- The sealed floor under the Deep (docs/undercroft-design.md): in the small room under the Deep's shop
-- (the one with the teleport pad), an iron plate is let into the floor with a keyhole in it. Pressing E on it
-- with the Sunken Key (src.buriedvault's Relic) turns the key: the Key is spent, the plate gives, a shaft opens
-- below, and the Undercroft stays open for good on that save (src.meta). On a save that has already opened it,
-- the way is open from the start and no key is needed.
local audio = require("src.audio")
local effects = require("src.effects")
local input = require("src.input")
local inventory = require("src.inventory")
local materials = require("src.materials")
local meta = require("src.meta")

local deepseal = {}

local SHOP = 1 -- the Deep's one shop
local PLATE_W, PLATE_H, SHAFT_DEPTH = 26, 6, 60
local REACH = 30

local world
local plate -- { x0, y0, x1, y1 }: the iron plate; its shaft runs on below it
local opened

function deepseal.clear()
  world, plate, opened = nil, nil, false
end

local function carve()
  for y = plate.y0, plate.y1 + SHAFT_DEPTH do
    for x = plate.x0, plate.x1 do
      world:setRaw(x, y, materials.AIR)
    end
  end
  world:repaintRegion(plate.x0 - 3, plate.y0 - 3, plate.x1 + 3, plate.y1 + SHAFT_DEPTH + 3)
  require("src.physics").rebuildRegion(plate.x0 - 3, plate.y0 - 3, plate.x1 + 3, plate.y1 + SHAFT_DEPTH + 3)
end

-- Where the way down ends for now (the first Undercroft zone is built here)
function deepseal.shaft()
  return plate and { x0 = plate.x0, x1 = plate.x1, top = plate.y0, bottom = plate.y1 + SHAFT_DEPTH } or nil
end

function deepseal.which()
  return SHOP
end

-- back: the room under the shop (src.cavegen's room.back)
function deepseal.geometry(back)
  return { x0 = back.cx + 14, y0 = back.floorY, x1 = back.cx + 14 + PLATE_W - 1, y1 = back.floorY + PLATE_H - 1 }
end

function deepseal.setup(w, back)
  world, opened = w, false
  plate = deepseal.geometry(back)
  if meta.undercroftOpen() then
    opened = true
    carve()
    return
  end
  world:fillRect(plate.x0, plate.y0, plate.x1, plate.y1, materials.IRON)
  world:repaintRegion(plate.x0 - 1, plate.y0 - 1, plate.x1 + 1, plate.y1 + 1)
end

local function near(player)
  if not world or not plate or opened or player.dead then
    return false
  end
  local px, py = player:center()
  return math.abs(px - (plate.x0 + plate.x1) / 2) < REACH and py < plate.y0 and py > plate.y0 - 40
end

local function carried(inv)
  for i = 1, inventory.ITEM_SLOTS do
    if inv.items[i] and inv.items[i].id == "sunkenkey" then
      return i
    end
  end
end

function deepseal.interact(player)
  if not near(player) then
    return false
  end
  local slot = carried(player.inventory)
  if not slot then
    return false -- (nothing to say: it is only a locked floor)
  end
  player.inventory.items[slot] = nil
  opened = true
  meta.openUndercroft()
  carve()
  audio.play("hatch")
  local cx = (plate.x0 + plate.x1) / 2
  effects.ring(cx, plate.y0, 40, { 0.85, 0.7, 0.35 })
  for _ = 1, 40 do
    effects.particle(plate.x0 + (plate.x1 - plate.x0) * love.math.random(), plate.y0 + 2, (love.math.random() - 0.5) * 50, 10 + love.math.random() * 60, 1.1, { 0.45, 0.46, 0.54 }, 520)
  end
  effects.popup(cx, plate.y0 - 18, "The way down is open", { 0.9, 0.78, 0.45 })
  return true
end

function deepseal.update() end

local function R(c, a, x, y, w, h)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
  love.graphics.rectangle("fill", math.floor(x), math.floor(y), w, h)
end

local function inView(view, m)
  return plate and view.x + view.w >= plate.x0 - m and view.x <= plate.x1 + m and view.y + view.h >= plate.y0 - m and view.y <= plate.y1 + m
end

-- The keyhole: a dark socket in the middle of the plate
function deepseal.draw(view)
  if not world or not plate or opened or not inView(view, 30) then
    return
  end
  local cx = math.floor((plate.x0 + plate.x1) / 2)
  R({ 0.05, 0.05, 0.08 }, 1, cx - 2, plate.y0, 5, 5)
  R({ 0.05, 0.05, 0.08 }, 1, cx - 1, plate.y0 + 5, 3, 1)
  R({ 0.56, 0.58, 0.68 }, 1, cx - 3, plate.y0, 1, 5)
  R({ 0.56, 0.58, 0.68 }, 1, cx + 3, plate.y0, 1, 5)
end

function deepseal.drawEmissive(view)
  if not world or not plate or opened or not inView(view, 30) then
    return
  end
  local t = love.timer.getTime()
  local cx = math.floor((plate.x0 + plate.x1) / 2)
  R({ 0.95, 0.78, 0.4 }, 0.25 + 0.25 * math.sin(t * 2), cx, plate.y0 + 1, 1, 2)
end

function deepseal.addLights(lighting, view)
  if not world or not plate or opened or not inView(view, 100) then
    return
  end
  lighting.add((plate.x0 + plate.x1) / 2, plate.y0 - 3, 22, 0.95, 0.75, 0.35, 0.25)
end

function deepseal.drawScreen(toScreen, font, player)
  if not near(player) or not carried(player.inventory) then
    return
  end
  local text = "[" .. input.label("interact") .. "]"
  local sx, sy = toScreen((plate.x0 + plate.x1) / 2, plate.y0 - 14)
  love.graphics.setFont(font)
  local x, y = math.floor(sx - font:getWidth(text) / 2), math.floor(sy - font:getHeight())
  love.graphics.setColor(0, 0, 0, 0.85)
  love.graphics.print(text, x + 2, y + 2)
  love.graphics.setColor(1, 0.88, 0.6)
  love.graphics.print(text, x, y)
end

return deepseal
