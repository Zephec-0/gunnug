-- Renders the app icon's PNGs (the title screen's cylinder) into the LÖVE save folder:
--   love tools/icon        then   python tools/make-icon.py
package.path = "game/?.lua;" .. package.path
function love.load()
  love.filesystem.setIdentity("gunnug-icon")
  local logo = dofile("game/src/titlelogo.lua")
  for _, size in ipairs({ 1024, 256, 128, 64, 48, 32, 24, 16 }) do
    local data = logo.iconData(size)
    data:encode("png", "icon" .. size .. ".png")
  end
  print(love.filesystem.getSaveDirectory())
  love.event.quit()
end
