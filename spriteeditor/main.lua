local app = require("src.app")

local callbacks = {
  "load", "update", "draw", "mousepressed", "mousereleased", "mousemoved", "wheelmoved",
  "keypressed", "textinput", "filedropped", "resize", "quit",
}

for _, name in ipairs(callbacks) do
  love[name] = function(...)
    return app[name](...)
  end
end
