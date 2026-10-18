-- Modal dialogs: new sprite (with the game's characters), open, save as, export, canvas size,
-- rename, import of a dropped image, confirmation and the shortcut list
local U = require("src.util")
local fileio = require("src.fileio")
local presets = require("src.presets")
local ui = require("src.ui")

local M = {}
local lg = love.graphics
local T = ui.theme

local function enterPressed()
  for _, k in ipairs(ui.keys) do
    if k == "return" or k == "kpenter" then return true end
  end
  return false
end

local function box(w, h, title)
  local W, H = lg.getDimensions()
  lg.setColor(0, 0, 0, 0.55)
  lg.rectangle("fill", 0, 0, W, H)
  local x, y = math.floor((W - w) / 2), math.floor((H - h) / 2)
  ui.rect(T.panel, x, y, w, h)
  ui.rect(T.line, x, y, w, h, "line")
  ui.rect(T.panel2, x, y, w, 30)
  ui.text(title, x + 12, y + 7, T.text, ui.big)
  return x, y
end

function M.open(A, kind, args)
  local S = A.S
  local m = { kind = kind, args = args or {} }
  if kind == "new" then
    m.sel = 2
    for i, p in ipairs(presets.list) do
      if p.key == (S.D.preset or "hunter") then m.sel = i end
    end
    local p = presets.list[m.sel]
    m.w, m.h = tostring(p.w), tostring(p.h)
    m.rig = 1
    m.pal = 1
    m.scroll = 0
  elseif kind == "open" then
    m.files = fileio.listProjects()
    m.scroll = 0
  elseif kind == "saveas" then
    m.name = S.path or fileio.safeName(S.D.name)
    ui.setFocus("dlg_name", m.name)
  elseif kind == "export" then
    m.name = fileio.safeName(S.path or S.D.name)
    m.layout, m.cols, m.scale, m.scope, m.meta = "strip", "8", 1, "all", true
  elseif kind == "canvas" then
    m.w, m.h, m.ax, m.ay = tostring(S.D.w), tostring(S.D.h), 0.5, 1
  elseif kind == "rename" then
    m.name = m.args.target.name
    ui.setFocus("dlg_name", m.name)
  end
  return m
end

local function close(A)
  A.closeModal()
end

-- New ----------------------------------------------------------------------------------------------

local function drawNew(A, m)
  local S = A.S
  local x, y = box(640, 470, "New sprite")
  local lx, ly, lw, lh = x + 12, y + 42, 330, 416
  ui.rect(T.bg, lx, ly, lw, lh)
  local rh = 20
  local list = presets.list
  local vis = math.floor(lh / rh)
  m.scroll = U.clamp(m.scroll - ui.scroll(lx, ly, lw, lh), 0, math.max(0, #list - vis))
  lg.setScissor(lx, ly, lw, lh)
  for row = 0, vis - 1 do
    local i = row + 1 + m.scroll
    local p = list[i]
    if not p then break end
    local ry = ly + row * rh
    if p.group then
      ui.text(p.group, lx + 6, ry + 5, T.accent, ui.small)
    else
      if i == m.sel then ui.rect(T.btnActive, lx, ry, lw, rh - 1) elseif ui.hit(lx, ry, lw, rh) then ui.rect(T.btnHover, lx, ry, lw, rh - 1) end
      ui.text(p.name, lx + 14, ry + 3)
      local info = p.w .. "x" .. p.h .. (p.hit and ("   hit " .. p.hit[1] .. "x" .. p.hit[2]) or "")
      ui.text(info, lx + lw - ui.small:getWidth(info) - 8, ry + 4, T.dim, ui.small)
      if ui.clicked(lx, ry, lw, rh) then
        local now = love.timer.getTime()
        local again = m.sel == i and now - (m.clickT or 0) < 0.35
        m.sel, m.clickT = i, now
        m.w, m.h = tostring(p.w), tostring(p.h)
        m.rig = 1
        if p.rig then
          for k, r in ipairs(presets.rigs) do if r == p.rig then m.rig = k end end
        end
        if again then m.go = true end
      end
    end
  end
  lg.setScissor()
  -- options
  local p = list[m.sel]
  local ox, oy, ow = x + 356, y + 42, 272
  ui.text(p.name, ox, oy, T.text, ui.big)
  oy = oy + 24
  if p.hit then
    ui.text("In-game hitbox " .. p.hit[1] .. " x " .. p.hit[2] .. (p.ground and ", stands on the ground" or ", flies"), ox, oy, T.dim, ui.small)
    oy = oy + 14
    ui.text("The canvas leaves room around it for limbs,", ox, oy, T.dim, ui.small)
    ui.text("weapons and motion.", ox, oy + 12, T.dim, ui.small)
    oy = oy + 28
  end
  if love.filesystem.getInfo("refs/" .. (p.key or "") .. ".png") then
    ui.text("Includes the in-game look as a reference layer", ox, oy, T.accent, ui.small)
    oy = oy + 16
  end
  oy = oy + 6
  m.w = ui.textbox("dlg_w", ox, oy, 100, 22, m.w, { label = "W", maxLen = 3 })
  m.h = ui.textbox("dlg_h", ox + 110, oy, 100, 22, m.h, { label = "H", maxLen = 3 })
  oy = oy + 30
  local rigs = presets.rigs
  if ui.button("Puppet rig: " .. rigs[m.rig], ox, oy, ow, 22, { tip = "Start with bones and a part layer per bone (the hunter's proportions)" }) then
    m.rig = m.rig % #rigs + 1
  end
  oy = oy + 26
  local pals = presets.palettes
  if ui.button("Palette: " .. pals[m.pal].name, ox, oy, ow, 22) then m.pal = m.pal % #pals + 1 end
  oy = oy + 34
  ui.text("Pixel art stays small: up to 256 x 256.", ox, oy, T.dim, ui.small)
  local w, h = tonumber(m.w), tonumber(m.h)
  local ok = w and h and w >= 1 and h >= 1 and w <= 256 and h <= 256
  if (ui.button("Create", x + 640 - 192, y + 470 - 38, 86, 26, { disabled = not ok, active = ok }) or (ok and (m.go or enterPressed()))) then
    m.go = false
    local D = presets.newDoc(p, math.floor(w), math.floor(h), rigs[m.rig], pals[m.pal].colors)
    close(A)
    A.setDoc(D, nil)
    S.paletteIdx = m.pal
    if rigs[m.rig] ~= "none" then
      S.tab = "rig"
      S.tool = "pose"
      A.msg("Each bone has its own part layer with a placeholder stick: draw over them, then pose with P")
    end
  end
  if ui.button("Cancel", x + 640 - 98, y + 470 - 38, 86, 26) then close(A) end
end

-- Open ---------------------------------------------------------------------------------------------

local function drawOpen(A, m)
  local x, y = box(460, 420, "Open project")
  local lx, ly, lw, lh = x + 12, y + 42, 436, 330
  ui.rect(T.bg, lx, ly, lw, lh)
  ui.text("spriteeditor/projects  (you can also drop a .gspr or .png onto the window)", lx, y + 386, T.dim, ui.small)
  local rh = 22
  local vis = math.floor(lh / rh)
  m.scroll = U.clamp(m.scroll - ui.scroll(lx, ly, lw, lh), 0, math.max(0, #m.files - vis))
  if #m.files == 0 then ui.text("No saved projects yet.", lx + 10, ly + 10, T.dim) end
  lg.setScissor(lx, ly, lw, lh)
  for row = 0, vis - 1 do
    local f = m.files[row + 1 + m.scroll]
    if not f then break end
    local ry = ly + row * rh
    if ui.hit(lx, ry, lw, rh) then ui.rect(T.btnHover, lx, ry, lw, rh - 1) end
    ui.text(f.name == "_autosave" and "_autosave (recovery)" or f.name, lx + 10, ry + 4, f.name == "_autosave" and T.warn or T.text)
    local t = os.date("%Y-%m-%d %H:%M", f.time)
    ui.text(t, lx + lw - ui.small:getWidth(t) - 10, ry + 6, T.dim, ui.small)
    if ui.clicked(lx, ry, lw, rh) then
      close(A)
      A.cmd.open(f.name)
    end
  end
  lg.setScissor()
  if ui.button("Cancel", x + 460 - 98, y + 420 - 34, 86, 24) then close(A) end
end

-- Save as / rename -----------------------------------------------------------------------------------

local function drawName(A, m, title, label, action)
  local x, y = box(400, 130, title)
  local v, sub = ui.textbox("dlg_name", x + 12, y + 46, 376, 24, m.name, { label = label, maxLen = 40 })
  m.name = v
  if ui.button("OK", x + 400 - 192, y + 130 - 36, 86, 26, { active = true }) or sub then
    if m.name and m.name:match("%S") then
      close(A)
      action(m.name)
    end
  end
  if ui.button("Cancel", x + 400 - 98, y + 130 - 36, 86, 26) then close(A) end
end

-- Export -------------------------------------------------------------------------------------------

local function drawExport(A, m)
  local S, D = A.S, A.S.D
  local x, y = box(460, 300, "Export")
  local ox, oy = x + 14, y + 44
  m.name = ui.textbox("dlg_ename", ox, oy, 432, 24, m.name, { label = "Name", maxLen = 40 })
  oy = oy + 34
  local layouts = { { "strip", "Strip" }, { "grid", "Grid" }, { "files", "One PNG per frame" } }
  ui.text("Layout", ox, oy + 4, T.dim)
  for i, l in ipairs(layouts) do
    if ui.button(l[2], ox + 70 + (i - 1) * 122, oy, 118, 22, { active = m.layout == l[1] }) then m.layout = l[1] end
  end
  oy = oy + 28
  if m.layout == "grid" then
    m.cols = ui.textbox("dlg_cols", ox + 70, oy, 120, 22, m.cols, { label = "Columns", maxLen = 3 })
    oy = oy + 28
  end
  ui.text("Scale", ox, oy + 4, T.dim)
  for i = 1, 4 do
    if ui.button(i .. "x", ox + 70 + (i - 1) * 60, oy, 56, 22, { active = m.scale == i, tip = i == 3 and "The game shows its world at 3x on a 1080p screen" or nil }) then m.scale = i end
  end
  oy = oy + 28
  ui.text("Frames", ox, oy + 4, T.dim)
  if ui.button("All in one", ox + 70, oy, 118, 22, { active = m.scope == "all" }) then m.scope = "all" end
  if ui.button("A file per tag", ox + 192, oy, 118, 22, { active = m.scope == "tags", disabled = #D.tags == 0 }) then m.scope = "tags" end
  oy = oy + 28
  m.meta = ui.toggle("Lua metadata (frame rects, durations, tags, anchor, hitbox)", ox, oy, 432, 22, m.meta)
  oy = oy + 32
  ui.text("Writes to spriteeditor/export/ (the reference layer is left out)", ox, oy, T.dim, ui.small)
  if ui.button("Export", x + 460 - 192, y + 300 - 36, 86, 26, { active = true }) or enterPressed() then
    close(A)
    A.cmd.export({ name = fileio.safeName(m.name), layout = m.layout, cols = tonumber(m.cols) or 8, scale = m.scale, scope = m.scope, meta = m.meta })
  end
  if ui.button("Cancel", x + 460 - 98, y + 300 - 36, 86, 26) then close(A) end
end

-- Canvas size --------------------------------------------------------------------------------------

local function drawCanvas(A, m)
  local x, y = box(360, 250, "Canvas size")
  local ox, oy = x + 14, y + 44
  m.w = ui.textbox("dlg_cw", ox, oy, 100, 22, m.w, { label = "W", maxLen = 3 })
  m.h = ui.textbox("dlg_ch", ox + 110, oy, 100, 22, m.h, { label = "H", maxLen = 3 })
  oy = oy + 34
  ui.text("Anchor (where the art stays)", ox, oy, T.dim, ui.small)
  oy = oy + 16
  for j = 0, 2 do
    for i = 0, 2 do
      local ax, ay = i / 2, j / 2
      if ui.button("", ox + i * 30, oy + j * 30, 26, 26, { active = m.ax == ax and m.ay == ay }) then m.ax, m.ay = ax, ay end
    end
  end
  ui.text("Bottom centre keeps the\nfeet on the ground line.", ox + 110, oy + 20, T.dim, ui.small)
  local w, h = tonumber(m.w), tonumber(m.h)
  local ok = w and h and w >= 1 and h >= 1 and w <= 256 and h <= 256
  if ui.button("Apply", x + 360 - 192, y + 250 - 36, 86, 26, { disabled = not ok, active = ok }) or (ok and enterPressed()) then
    close(A)
    A.cmd.resize(math.floor(w), math.floor(h), m.ax, m.ay)
  end
  if ui.button("Cancel", x + 360 - 98, y + 250 - 36, 86, 26) then close(A) end
end

-- Import -------------------------------------------------------------------------------------------

local function drawImport(A, m)
  local S = A.S
  local data = m.args.data
  local iw, ih = data:getDimensions()
  local x, y = box(420, 250, "Import " .. (m.args.name or "image"))
  local ox, oy = x + 14, y + 42
  ui.text(string.format("%d x %d image, the sprite is %d x %d", iw, ih, S.D.w, S.D.h), ox, oy, T.dim)
  oy = oy + 24
  local opts = {
    { "layer", "As a new layer on this frame" },
    { "ref", "As a reference layer (faded, not exported)" },
    { "frames", string.format("Split into frames (%d of them)", math.floor(iw / S.D.w) * math.floor(ih / S.D.h)) },
    { "doc", "As a new sprite of its size" },
  }
  for _, o in ipairs(opts) do
    if ui.button(o[2], ox, oy, 392, 24) then
      close(A)
      if o[1] == "doc" then
        A.confirmDiscard(function() A.cmd.import("doc", data) end)
      else
        A.cmd.import(o[1], data)
      end
    end
    oy = oy + 28
  end
  if ui.button("Cancel", x + 420 - 98, y + 250 - 34, 86, 24) then close(A) end
end

-- Confirm / help -----------------------------------------------------------------------------------

local function drawConfirm(A, m)
  local x, y = box(380, 120, "Are you sure?")
  ui.text(m.args.text, x + 14, y + 44)
  if ui.button(m.args.yes or "Yes", x + 380 - 192, y + 120 - 36, 86, 26, { active = true }) then
    close(A)
    m.args.fn()
  end
  if ui.button("Cancel", x + 380 - 98, y + 120 - 36, 86, 26) then close(A) end
end

local HELP = {
  { "Tools", "B pencil  E eraser  G fill  I picker (or Alt)  L line  U rect  O ellipse  M select  V move  K bone  P pose" },
  { "Brush", "[ ] size   X swap colours   right mouse paints the 2nd colour (clear = erase)" },
  { "View", "wheel zoom   middle drag or Space+drag pan   Ctrl+0 fit   ' grid   H hitbox   N onion   R rest pose" },
  { "Frames", ", . previous / next   Home End   F new frame   Shift+F duplicate   Enter play / stop" },
  { "Edit", "Ctrl+Z undo   Ctrl+Y redo   Ctrl+A / D select all / none   Ctrl+C X V   Del clear   arrows nudge" },
  { "Files", "Ctrl+N new   Ctrl+O open   Ctrl+S save   Ctrl+E export   drop a PNG to import it" },
  { "Rig", "Bone tool: drag to add a bone; from a bone's tip it chains on, elsewhere it's a child of the" },
  { "", "selected bone (Ctrl: new root). Click selects, Alt+drag moves a joint. Pose tool: drag a bone to turn" },
  { "", "it (Ctrl snaps 15 deg), Shift+drag moves it, drag near the tip to bend the chain (IK)." },
  { "", "Each posed frame gets a key; frames between keys are interpolated. Bake flattens the" },
  { "", "puppet into frame-by-frame pixels for cleanup." },
  { "Layers", "Frame layers have a cel per frame. Parts are one image on every frame, moved by a bone." },
}

local function drawHelp(A)
  local x, y = box(760, 330, "Shortcuts")
  local oy = y + 42
  for _, h in ipairs(HELP) do
    ui.text(h[1], x + 14, oy, T.accent)
    ui.text(h[2], x + 80, oy, T.text)
    oy = oy + 20
  end
  if ui.button("Close", x + 760 - 98, y + 330 - 36, 86, 26) or enterPressed() then close(A) end
end

function M.draw(A, m)
  if m.kind == "new" then drawNew(A, m)
  elseif m.kind == "open" then drawOpen(A, m)
  elseif m.kind == "saveas" then drawName(A, m, "Save as", "Name", function(n) A.cmd.save(fileio.safeName(n)) end)
  elseif m.kind == "rename" then
    drawName(A, m, "Rename " .. m.args.what, "Name", function(n)
      m.args.target.name = n
      A.commit()
    end)
  elseif m.kind == "export" then drawExport(A, m)
  elseif m.kind == "canvas" then drawCanvas(A, m)
  elseif m.kind == "import" then drawImport(A, m)
  elseif m.kind == "confirm" then drawConfirm(A, m)
  elseif m.kind == "help" then drawHelp(A)
  end
end

return M
