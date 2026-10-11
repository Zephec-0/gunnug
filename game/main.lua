https = nil
local overlayStats = require("lib.overlayStats")
local runtimeLoader = require("runtime.loader")
local game = require("src.game")

function love.load()
  https = runtimeLoader.loadHTTPS()
  game.load()
  overlayStats.load() -- Should always be called last
end

function love.draw()
  game.draw()
  overlayStats.draw() -- Should always be called last
end

function love.update(dt)
  game.update(dt)
  overlayStats.update(dt) -- Should always be called last
end

function love.keypressed(key)
  if key == "escape" and love.system.getOS() ~= "Web" then
    love.event.quit()
  else
    game.keypressed(key)
    overlayStats.handleKeyboard(key) -- Should always be called last
  end
end

function love.touchpressed(id, x, y, dx, dy, pressure)
  overlayStats.handleTouch(id, x, y, dx, dy, pressure) -- Should always be called last
end
