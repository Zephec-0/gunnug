# Refreshes the scratch copy's src from the game and adds the test hooks
import io, os, shutil, sys
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = "E:/gametest/game/src"
DST = os.path.join(HERE, "h", "src")
shutil.copytree(SRC, DST, dirs_exist_ok=True)

def patch(name, marker, add):
    p = os.path.join(DST, name)
    with io.open(p, newline="") as f:
        s = f.read()
    i = s.rindex(marker)
    s = s[:i] + add.replace("\n", "\r\n") + s[i:]
    with io.open(p, "w", newline="") as f:
        f.write(s)

patch("devpanel.lua", "return panel", "panel._unlock = unlockEverything\n")
patch("menu.lua", "return menu", """menu._settings = function(tab)
  settingsTab = tab
  if top() ~= "settings" then push("settings") end
end
menu._push = push
""")
patch("settings.lua", "return settings", """settings._resize = function(w, h)
  keepingCanvases(function()
    local _, _, flags = love.window.getMode()
    flags.fullscreen, flags.borderless, flags.x, flags.y = false, false, nil, nil
    love.window.updateMode(w, h, flags)
  end)
end
""")
shutil.copyfile(os.path.join(HERE, sys.argv[1]), os.path.join(HERE, "h", "main.lua"))
print("ok")
