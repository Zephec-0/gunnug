require("src.jittune") -- (first: room for LuaJIT's compiled code, before anything is compiled)
https = nil
local overlayStats = require("lib.overlayStats")
local runtimeLoader = require("runtime.loader")
local game = require("src.game")

-- LÖVE's own main loop, but for its 1 ms sleep at the end of every frame. That sleep is there so a game with
-- nothing to wait for doesn't spin a whole core; with vsync on, presenting the frame already waits for the display,
-- and the sleep (1.5 ms as measured on Windows) only eats into the frame: at 120 fps it is a sixth of the 8.3 ms.
-- So it is kept only while vsync is off, or when a frame came back in under 2 ms (vsync overridden in the driver,
-- or the window minimised: nothing is holding the loop back then).
function love.run()
  if love.load then
    love.load(love.arg.parseGameArguments(arg), arg)
  end
  if love.timer then
    love.timer.step()
  end
  local dt = 0
  local getTime = love.timer.getTime
  return function()
    local frameStart = getTime()
    if love.event then
      love.event.pump()
      for name, a, b, c, d, e, f in love.event.poll() do
        if name == "quit" then
          if not love.quit or not love.quit() then
            return a or 0
          end
        end
        love.handlers[name](a, b, c, d, e, f)
      end
    end
    dt = love.timer.step()
    if love.update then
      love.update(dt)
    end
    local drew = false
    if love.graphics and love.graphics.isActive() then
      love.graphics.origin()
      love.graphics.clear(love.graphics.getBackgroundColor())
      if love.draw then
        love.draw()
      end
      love.graphics.present()
      drew = true
    end
    if not drew or love.window.getVSync() == 0 or getTime() - frameStart < 0.002 then
      love.timer.sleep(0.001)
    end
  end
end

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
    if not love.filesystem.isFused() then -- (the F-key debug tools are for source checkouts only)
      overlayStats.handleKeyboard(key) -- Should always be called last
    end
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
