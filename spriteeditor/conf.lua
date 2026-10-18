-- Gunnug sprite editor: a separate LÖVE program, not part of the game. Run it with
--   love.exe spriteeditor     (or editor.bat in the repository root)
function love.conf(t)
  t.identity = "gunnug-spriteeditor"
  t.version = "11.5"
  t.console = false

  t.window.title = "Gunnug Sprite Editor"
  t.window.width = 1600
  t.window.height = 900
  t.window.minwidth = 1180
  t.window.minheight = 800
  t.window.resizable = true
  t.window.vsync = 1
  t.window.highdpi = false

  t.modules.audio = false
  t.modules.sound = false
  t.modules.physics = false
  t.modules.joystick = false
  t.modules.video = false
end
