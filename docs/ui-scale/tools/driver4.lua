-- UI scaling driver: the same screens at several window sizes
require("src.jittune")
https = nil
io.stdout:setvbuf("no")
local game = require("src.game")

function love.errorhandler(msg)
  print("ERROR: " .. tostring(msg))
  print(debug.traceback())
  love.event.quit(1)
end

local OUT = "E:/gametest/docs/ui-scale/" .. (os.getenv("ART_PREFIX") or "")
local function shot(name)
  love.graphics.captureScreenshot(function(data)
    local f = assert(io.open(OUT .. name, "wb"))
    f:write(data:encode("png"):getString())
    f:close()
    print("shot " .. name)
  end)
end

local SIZES = {}
for w, h in (os.getenv("ART_SIZES") or "960x540 1280x720 1366x768 1600x900 1280x960 1920x1080"):gmatch("(%d+)x(%d+)") do
  SIZES[#SIZES + 1] = { tonumber(w), tonumber(h) }
end
local WHAT = os.getenv("ART_WHAT") or "settings pages comp bar bright"
local function want(k) return WHAT:find(k, 1, true) ~= nil end

local frame, cursor = 0, 0
local script = {}
local function step(gap, fn)
  cursor = cursor + gap
  script[cursor] = fn
end

local settings = require("src.settings")
local menu = require("src.menu")
local function resize(s)
  if s[1] == 1920 then
    settings.set("fullscreen", true)
  else
    if settings.get("fullscreen") then settings.set("fullscreen", false) end
    settings._resize(s[1], s[2])
  end
  print("size", love.graphics.getDimensions())
end

function love.load()
  game.load()
end

step(5, function() settings.set("fullscreen", false) game.menuAction("play", 1) end)
step(15, function()
  print(require("src.devpanel")._unlock())
  require("src.dev").noDamage = true
  game.enter("overworld", { atCave = false })
end)
cursor = cursor + 100
local people = { "gunsmith", "prospector", "apothecary", "bartender", "tinker", "cartographer", "sawbone", "taxidermist" }
for _, s in ipairs(SIZES) do
  local tag = s[1] .. "x" .. s[2] .. "-"
  step(4, function() resize(s) end)
  cursor = cursor + 6
  if want("settings") then
    for tab = 1, 4 do
      step(2, function() menu.open("pause") menu._settings(tab) end)
      step(6, function() shot(tag .. "settings" .. tab .. ".png") end)
    end
    step(2, function() menu.close() end)
    step(2, function() menu.open("pause") end)
    step(6, function() shot(tag .. "pause.png") end)
    step(2, function() menu.close() end)
  end
  if want("comp") then
    step(2, function() menu.open("pause") menu._push("compendium") end)
    step(8, function() shot(tag .. "compendium.png") end)
    step(2, function() menu.close() end)
  end
  if want("pages") then
    for _, id in ipairs(people) do
      step(2, function() print("talk", id, pcall(require("src.npcs").onTalk, id)) end)
      step(8, function() if menu.isOpen() then shot(tag .. "page-" .. id .. ".png") end end)
      step(2, function() menu.close() end)
    end
    step(2, function() pcall(require("src.npcs").onTalk, "board") end)
    step(8, function() shot(tag .. "page-board.png") end)
    step(2, function() menu.close() pcall(require("src.npcs").onTalk, "hats") end)
    step(8, function() shot(tag .. "page-hats.png") end)
    step(2, function() menu.close() end)
  end
end
if want("bar") then
  step(4, function() game.enter("testroom") end)
  step(40, function()
    local inv = game.inventory()
    local items = require("src.items")
    for _, id in ipairs({ "acid", "scope", "drumloader", "slug", "frost", "lantern" }) do
      pcall(function() inv:addItem(items.new(id)) end)
    end
  end)
  for _, s in ipairs(SIZES) do
    local tag = s[1] .. "x" .. s[2] .. "-"
    step(4, function() resize(s) end)
    step(10, function() shot(tag .. "hud.png") end)
    step(2, function() require("src.itembar").toggle() end)
    step(10, function() shot(tag .. "itembar.png") end)
    step(2, function() require("src.itembar").toggle() end)
  end
end
if want("bright") then
  for _, b in ipairs({ 0.6, 1.4, 1 }) do
    step(4, function() settings.set("brightness", b) end)
    step(6, function() shot("bright-" .. b .. "-hud.png") end)
    step(2, function() menu.open("pause") menu._settings(2) end)
    step(6, function() shot("bright-" .. b .. "-settings.png") end)
    step(2, function() menu.close() end)
  end
  step(2, function() settings.set("fullscreen", false) settings._resize(1280, 720) end)
  step(6, function() settings.set("brightness", 1.4) end)
  step(6, function() shot("bright-1.4-1280.png") end)
  step(2, function() settings.set("brightness", 1) end)
end
step(6, function() love.event.quit(0) end)

function love.update(dt)
  frame = frame + 1
  if script[frame] then script[frame]() end
  game.update(1 / 60)
end

function love.draw()
  game.draw()
end
