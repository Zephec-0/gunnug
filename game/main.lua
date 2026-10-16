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
  if game.keypressed(key) then
    return
  end
  if key == "escape" and love.system.getOS() ~= "Web" then
    love.event.quit()
  else
    overlayStats.handleKeyboard(key) -- Should always be called last
  end
end

function love.quit()
  game.quit()
end

function love.focus(focused)
  game.focus(focused)
end

function love.textinput(text)
  game.textinput(text)
end

function love.mousepressed(x, y, button)
  game.mousepressed(x, y, button)
end

function love.mousereleased(x, y, button)
  game.mousereleased(x, y, button)
end

function love.wheelmoved(x, y)
  game.wheelmoved(x, y)
end

function love.touchpressed(id, x, y, dx, dy, pressure)
  overlayStats.handleTouch(id, x, y, dx, dy, pressure) -- Should always be called last
end
