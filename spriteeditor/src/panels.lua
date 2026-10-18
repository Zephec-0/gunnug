-- Top bar, tool column and the right-hand panel (colour, palette, layers / effects / rig tabs)
local U = require("src.util")
local doc = require("src.doc")
local rig = require("src.rig")
local presets = require("src.presets")
local render = require("src.render")
local ui = require("src.ui")

local P = {}
local lg = love.graphics
local T = ui.theme

local function panelBg(R)
  ui.rect(T.panel, R.x, R.y, R.w, R.h)
end

local function header(s, x, y, w)
  ui.text(s, x, y, T.dim, ui.small)
  ui.rect(T.line, x + ui.small:getWidth(s) + 6, y + 6, w - ui.small:getWidth(s) - 6, 1)
end

-- Top bar ------------------------------------------------------------------------------------------

function P.drawTop(A, R)
  local S, cmd = A.S, A.cmd
  ui.rect(T.panel2, R.x, R.y, R.w, R.h)
  ui.rect(T.line, R.x, R.y + R.h - 1, R.w, 1)
  local x, y, h = 6, 4, 22
  local function b(label, w, tip, o)
    o = o or {}
    o.tip = tip
    local r = ui.button(label, x, y, w, h, o)
    x = x + w + 3
    return r
  end
  local function gap() x = x + 10 end
  if b("New", 44, "New sprite (Ctrl+N)") then A.confirmDiscard(function() A.openModal("new") end) end
  if b("Open", 46, "Open a project (Ctrl+O)") then A.confirmDiscard(function() A.openModal("open") end) end
  if b("Save", 44, "Save (Ctrl+S)") then if S.path then cmd.save() else A.openModal("saveas") end end
  if b("Save as", 58, "Save under a new name (Ctrl+Shift+S)") then A.openModal("saveas") end
  if b("Export", 54, "Export a PNG sprite sheet + Lua metadata (Ctrl+E)") then A.openModal("export") end
  if b("Canvas", 56, "Resize the canvas") then A.openModal("canvas") end
  gap()
  if b("Undo", 44, "Ctrl+Z") then cmd.undo() end
  if b("Redo", 44, "Ctrl+Y") then cmd.redo() end
  gap()
  if b("Grid", 40, "Pixel grid (')", { active = S.showGrid }) then S.showGrid = not S.showGrid end
  if b("Hitbox", 52, "The character's in-game hitbox and ground line (H)", { active = S.showGuide }) then S.showGuide = not S.showGuide end
  if b("Preview", 58, "Live preview at game scale", { active = S.preview }) then S.preview = not S.preview end
  gap()
  if b("-", 22, "Zoom out (-, wheel)") then A.zoomStep(-1) end
  if b("+", 22, "Zoom in (=, wheel)") then A.zoomStep(1) end
  if b("Fit", 34, "Fit the sprite in view (Ctrl+0)") then A.fit() end
  gap()
  if b("Keys", 42, "Keyboard shortcuts") then A.openModal("help") end
  local name = (S.path or S.D.name) .. (A.isDirty() and " *" or "")
  local nw = ui.font:getWidth(name)
  if x + nw + 12 < R.w then ui.text(name, R.w - nw - 10, y + 4, A.isDirty() and T.warn or T.dim) end
end

-- Tool column --------------------------------------------------------------------------------------

function P.drawLeft(A, R)
  local S = A.S
  panelBg(R)
  ui.rect(T.line, R.x + R.w - 1, R.y, 1, R.h)
  local x, y = R.x + 4, R.y + 6
  local bw, bh = 37, 26
  for i, t in ipairs(A.TOOLS) do
    local cx = x + ((i - 1) % 2) * (bw + 2)
    local cy = y + math.floor((i - 1) / 2) * (bh + 2)
    if ui.button(t.label, cx, cy, bw, bh, { active = S.tool == t.id, tip = t.tip, font = ui.small }) then A.setTool(t.id) end
  end
  y = y + math.ceil(#A.TOOLS / 2) * (bh + 2) + 8
  local fw = R.w - 8
  header("Brush", x, y, fw)
  y = y + 14
  if ui.button("-", x, y, 20, 20, { tip = "Smaller brush ([)" }) then S.size = math.max(1, S.size - 1) end
  ui.textc(S.size .. "px", x + 20, y, fw - 40, 20)
  if ui.button("+", x + fw - 20, y, 20, 20, { tip = "Bigger brush (])" }) then S.size = math.min(8, S.size + 1) end
  y = y + 26
  header("Mode", x, y, fw)
  y = y + 14
  for _, m in ipairs(A.MODES) do
    if ui.button(m.label, x, y, fw, 20, { active = S.mode == m.id, tip = m.tip, font = ui.small }) then S.mode = m.id end
    y = y + 22
  end
  y = y + 4
  header("Options", x, y, fw)
  y = y + 14
  local function tog(label, key, tip)
    S[key] = ui.toggle(label, x, y, fw, 20, S[key], tip)
    y = y + 22
  end
  tog("Lock alpha", "lockAlpha", "Only paint over pixels that are already there")
  tog("Pixel perf.", "pixelPerfect", "Pixel-perfect pencil: removes the doubled corners in 1px strokes")
  tog("Mirror X", "mirrorX", "Paint mirrored left/right around the canvas centre")
  tog("Mirror Y", "mirrorY", "Paint mirrored top/bottom")
  tog("Filled", "fillShapes", "Rectangles and ellipses are filled")
  tog("Fill all", "fillGlobal", "Bucket replaces that colour everywhere instead of the touching area")
end

-- Right panel --------------------------------------------------------------------------------------

local function drawSwatch(c, x, y, w, h, S)
  lg.setColor(1, 1, 1)
  local q = lg.newQuad(0, 0, w / 6, h / 6, 2, 2)
  lg.draw(S.checker, q, x, y, 0, 6, 6)
  q:release()
  lg.setColor(c[1], c[2], c[3], c[4])
  lg.rectangle("fill", x, y, w, h)
  lg.setColor(T.line)
  lg.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
end

local function drawColor(A, x, y, w)
  local S, D = A.S, A.S.D
  header("Colour", x, y, w)
  y = y + 14
  drawSwatch(S.secondary, x + 22, y + 16, 30, 30, S)
  drawSwatch(S.primary, x, y, 34, 34, S)
  if ui.clicked(x + 22, y + 16, 30, 30) or ui.clicked(x, y, 34, 34) then
    local p = S.primary
    A.setPrimary(S.secondary)
    S.secondary = p
  end
  if ui.hit(x, y, 52, 46) then ui.tip = "Left / right colours. Click (or X) to swap" end
  -- sliders
  local sx, sw = x + 62, w - 62
  local h, s, v = S.hsv[1], S.hsv[2], S.hsv[3]
  local function apply(nh, ns, nv)
    S.hsv = { nh, ns, nv }
    local r, g, b = U.hsv2rgb(nh, ns, nv)
    S.primary = { r, g, b, S.primary[4] }
  end
  local nh, ch = ui.slider("hue", sx, y, sw, 12, h, 0, 1, "H", {
    track = function(t) return U.hsv2rgb(t, 1, 1) end,
  })
  if ch then apply(nh, s, v) end
  local ns, cs = ui.slider("sat", sx, y + 14, sw, 12, s, 0, 1, "S", {
    track = function(t) return U.hsv2rgb(h, t, math.max(v, 0.2)) end,
  })
  if cs then apply(h, ns, v) end
  local nv, cv = ui.slider("val", sx, y + 28, sw, 12, v, 0, 1, "V", {
    track = function(t) return U.hsv2rgb(h, s, t) end,
  })
  if cv then apply(h, s, nv) end
  local na, ca = ui.slider("alpha", sx, y + 42, sw, 12, S.primary[4], 0, 1, "A", {
    step = 1 / 255, track = function(t) return t, t, t end,
  })
  if ca then S.primary[4] = na end
  y = y + 60
  local hv, sub, blur = ui.textbox("hex", x, y, 86, 20, ui.focus == "hex" and nil or U.hex(S.primary), { label = "#", maxLen = 6, tip = "Hex colour, Enter to apply" })
  if sub or blur then
    local r, g, b = U.parseHex(hv)
    if r then A.setPrimary({ r, g, b, 1 }) end
  end
  if ui.button("+ palette", x + 90, y, 64, 20, { tip = "Add the left colour to the palette", font = ui.small }) then
    D.palette[#D.palette + 1] = U.copy(S.primary)
    A.commit()
  end
  if ui.button("- palette", x + 157, y, 64, 20, { tip = "Remove the left colour from the palette", font = ui.small }) then
    for i = #D.palette, 1, -1 do
      if U.sameColor(D.palette[i], S.primary) then table.remove(D.palette, i) end
    end
    A.commit()
  end
  if ui.button("Extract", x + 224, y, w - 224, 20, { tip = "Add every colour used on this frame to the palette", font = ui.small }) then
    local d = render.frameData(D, S.frame, S.work, { skipRef = true })
    local W_, H_ = d:getDimensions()
    for py = 0, H_ - 1 do
      for px = 0, W_ - 1 do
        local r, g, b, a = d:getPixel(px, py)
        if a > 0 then
          local c, found = { r, g, b, 1 }, false
          for _, p in ipairs(D.palette) do
            if U.sameColor(p, c) then found = true break end
          end
          if not found then D.palette[#D.palette + 1] = c end
        end
      end
    end
    d:release()
    A.commit()
  end
  y = y + 26
  -- palette grid
  local cell = 16
  local cols = math.floor(w / cell)
  local rows = math.max(1, math.ceil(#D.palette / cols))
  rows = math.min(rows, 6)
  for i, c in ipairs(D.palette) do
    local cx, cy = (i - 1) % cols, math.floor((i - 1) / cols)
    if cy < rows then
      local px, py = x + cx * cell, y + cy * cell
      lg.setColor(c[1], c[2], c[3], c[4])
      lg.rectangle("fill", px, py, cell - 1, cell - 1)
      if U.sameColor(c, S.primary) then
        lg.setColor(1, 1, 1)
        lg.rectangle("line", px + 0.5, py + 0.5, cell - 2, cell - 2)
      end
      if ui.clicked(px, py, cell, cell, 1) then A.setPrimary(c) end
      if ui.clicked(px, py, cell, cell, 2) then S.secondary = U.copy(c) end
    end
  end
  if ui.hit(x, y, w, rows * cell) then ui.tip = "Left click: left colour. Right click: right colour" end
  y = y + rows * cell + 4
  -- palette presets
  local pals = presets.palettes
  if ui.button("Palette: " .. pals[S.paletteIdx or 1].name, x, y, w - 60, 20, { font = ui.small, tip = "Choose a palette preset" }) then
    S.paletteIdx = (S.paletteIdx or 1) % #pals + 1
  end
  if ui.button("Load", x + w - 56, y, 56, 20, { font = ui.small, tip = "Replace this sprite's palette with the preset" }) then
    D.palette = U.copy(pals[S.paletteIdx or 1].colors)
    A.commit()
  end
  return y + 26
end

-- Layers tab
local function drawLayers(A, x, y, w, h)
  local S, D, cmd = A.S, A.S.D, A.cmd
  local bw = math.floor((w - 10) / 6)
  local function row(btns)
    for i, b in ipairs(btns) do
      if ui.button(b[1], x + (i - 1) * (bw + 2), y, bw, 20, { font = ui.small, tip = b[2] }) then b[3]() end
    end
    y = y + 22
  end
  row({
    { "+Layer", "New frame-by-frame layer above", function() cmd.addLayer("frames") end },
    { "+Part", "New puppet part: one image on every frame (bound to the selected bone)", function() cmd.addLayer("part") end },
    { "Dup", "Duplicate layer", cmd.dupLayer },
    { "Del", "Delete layer", cmd.deleteLayer },
    { "Up", "Move layer up", function() cmd.moveLayer(1) end },
    { "Down", "Move layer down", function() cmd.moveLayer(-1) end },
  })
  local L = A.layerObj()
  row({
    { "Rename", "Rename layer (or double-click it)", function() if L then A.openModal("rename", { what = "layer", target = L }) end end },
    { "Merge", "Merge into the layer below", cmd.mergeDown },
    { L and L.kind == "part" and "To fr." or "To part", "Switch between frame-by-frame and puppet part", cmd.toggleKind },
    { "Bind", "Bind this layer to the selected bone", cmd.bindBone },
    { "Unbind", "Stop following the bone", cmd.unbind },
    { "Lock", "Lock / unlock", function() if L then L.locked = not L.locked end end },
  })
  if L then
    local nv, ch, rel = ui.slider("opacity", x, y, w, 16, L.opacity, 0, 1, "opacity ", { fmt = "%.2f", step = 0.05 })
    if ch then L.opacity = nv end
    if rel then A.commit() end
    y = y + 20
    local B = L.bone and rig.bone(D, L.bone)
    local info = L.kind == "frames" and "frame-by-frame" or (L.kind == "part" and "puppet part" or "reference (not exported)")
    if B then info = info .. ", on bone \"" .. B.name .. "\"" end
    ui.text(ui.fit(info, w), x, y, T.dim, ui.small)
    y = y + 16
  end
  return y
end

local function drawLayerList(A, x, y, w, h)
  local S, D = A.S, A.S.D
  local rh = 20
  local n = #D.layers
  local visible = math.max(1, math.floor(h / rh))
  local scroll = ui.scroll(x, y, w, h)
  S.layerScroll = U.clamp((S.layerScroll or 0) - scroll, 0, math.max(0, n - visible))
  lg.setScissor(x, y, w, h)
  for row = 0, visible - 1 do
    local i = n - (row + S.layerScroll)
    local L = D.layers[i]
    if not L then break end
    local ry = y + row * rh
    local cur = i == S.layer
    ui.rect(cur and T.btnActive or (row % 2 == 0 and T.panel2 or T.panel), x, ry, w, rh - 1)
    -- visibility
    lg.setColor(L.visible and T.text or T.dim)
    if L.visible then lg.circle("fill", x + 10, ry + rh / 2, 4) else lg.circle("line", x + 10, ry + rh / 2, 4) end
    if ui.clicked(x, ry, 20, rh) then L.visible = not L.visible end
    -- lock
    lg.setColor(L.locked and T.warn or T.line)
    lg.rectangle(L.locked and "fill" or "line", x + 24.5, ry + 7.5, 8, 7)
    if ui.clicked(x + 20, ry, 16, rh) then L.locked = not L.locked end
    local badge = L.kind == "part" and "part" or (L.kind == "ref" and "ref" or "")
    if L.bone then
      local B = rig.bone(D, L.bone)
      badge = (badge ~= "" and badge .. " " or "") .. "@" .. (B and B.name or "?")
    end
    local bwid = ui.small:getWidth(badge)
    ui.text(ui.fit(L.name, w - 46 - bwid), x + 40, ry + 3, cur and T.text or T.text)
    ui.text(badge, x + w - bwid - 4, ry + 4, L.kind == "ref" and T.warn or T.accent, ui.small)
    if ui.clicked(x + 36, ry, w - 36, rh) then
      local now = love.timer.getTime()
      if S.lastLayerClick == L.id and now - (S.lastLayerClickT or 0) < 0.35 then
        A.openModal("rename", { what = "layer", target = L })
      end
      S.lastLayerClick, S.lastLayerClickT = L.id, now
      A.setLayer(i)
    end
  end
  lg.setScissor()
end

-- Effects tab
local FX_BUTTONS = {
  { "flipH", "Flip H", "Mirror left/right" }, { "flipV", "Flip V", "Mirror up/down" },
  { "rotCW", "Rot CW", "Quarter turn clockwise" }, { "rotCCW", "Rot CCW", "Quarter turn anticlockwise" },
  { "outline", "Outline", "Outline in the left colour (4 sides)" }, { "outline8", "Outline 8", "Outline including corners" },
  { "inline", "Inline", "Colour the art's own edge pixels" }, { "shadow", "Shadow", "1px drop shadow down-right in the left colour" },
  { "lighter", "Lighter", "Brighten" }, { "darker", "Darker", "Darken" },
  { "hueDown", "Hue -", "Shift hue" }, { "hueUp", "Hue +", "Shift hue" },
  { "satDown", "Sat -", "Less saturated" }, { "satUp", "Sat +", "More saturated" },
  { "invert", "Invert", "Invert colours" }, { "gray", "Grayscale", "Remove colour" },
  { "snap", "To palette", "Snap every colour to the nearest palette colour" }, { "replace", "Replace L>R", "Replace the left colour with the right colour" },
  { "shiftL", "Shift <", "Scroll pixels left, wrapping around" }, { "shiftR", "Shift >", "Scroll pixels right, wrapping around" },
  { "shiftU", "Shift ^", "Scroll pixels up, wrapping around" }, { "shiftD", "Shift v", "Scroll pixels down, wrapping around" },
  { "despeckle", "Despeckle", "Remove lone stray pixels" }, { "clear", "Clear", "Erase everything" },
}

local function drawFx(A, x, y, w)
  local S = A.S
  header("Apply to", x, y, w)
  y = y + 14
  local sw = math.floor((w - 4) / 3)
  local scopes = { { "cel", "This cel", "The current layer on this frame" }, { "layer", "Whole layer", "Every frame of the current layer" }, { "frame", "This frame", "Every unlocked layer on this frame" } }
  for i, s in ipairs(scopes) do
    if ui.button(s[2], x + (i - 1) * (sw + 2), y, sw, 20, { active = S.fxScope == s[1], tip = s[3], font = ui.small }) then S.fxScope = s[1] end
  end
  y = y + 24
  ui.text(S.sel and "Only inside the selection" or "Whole image (select an area to limit it)", x, y, T.dim, ui.small)
  y = y + 16
  local cols = 2
  local bw = math.floor((w - (cols - 1) * 2) / cols)
  for i, b in ipairs(FX_BUTTONS) do
    local cx, cy = (i - 1) % cols, math.floor((i - 1) / cols)
    if ui.button(b[2], x + cx * (bw + 2), y + cy * 22, bw, 20, { tip = b[3], font = ui.small }) then A.cmd.fx(b[1]) end
  end
end

-- Rig tab
local function drawRig(A, x, y, w, h)
  local S, D, cmd = A.S, A.S.D, A.cmd
  local bw = math.floor((w - 6) / 4)
  local function tog(i, label, key, tip)
    S[key] = ui.toggle(label, x + (i - 1) * (bw + 2), y, bw, 20, S[key], tip)
  end
  tog(1, "Show", "showBones", "Show bones with every tool")
  tog(2, "Rest", "restPose", "View and paint the rest pose (R)")
  tog(3, "IK", "ik", "Dragging near a bone's tip with the Pose tool bends it and its parent (inverse kinematics)")
  tog(4, "Auto part", "autoPart", "New bones get their own part layer, bound to them")
  y = y + 24
  S.rigTemplate = S.rigTemplate or 2
  local rigs = presets.rigs
  if ui.button("Template: " .. rigs[S.rigTemplate], x, y, w - 64, 20, { font = ui.small, tip = "Rig templates use the hunter's proportions, scaled to the hitbox" }) then
    S.rigTemplate = S.rigTemplate % #rigs + 1
    if rigs[S.rigTemplate] == "none" then S.rigTemplate = S.rigTemplate % #rigs + 1 end
  end
  if ui.button("Add", x + w - 60, y, 60, 20, { font = ui.small, tip = "Add this rig with a part layer per bone" }) then cmd.template(rigs[S.rigTemplate]) end
  y = y + 24
  local function row(btns)
    for i, b in ipairs(btns) do
      if ui.button(b[1], x + (i - 1) * (bw + 2), y, bw, 20, { font = ui.small, tip = b[2] }) then b[3]() end
    end
    y = y + 22
  end
  local B = S.bone and rig.bone(D, S.bone)
  row({
    { "Key all", "Key every bone's current pose on this frame", cmd.keyAll },
    { "Del key", "Remove the selected bone's key on this frame", function() cmd.clearKey(false) end },
    { "Del all", "Remove every bone's key on this frame", function() cmd.clearKey(true) end },
    { "Ease", "Ease out of this key (smooth instead of linear)", cmd.toggleEase },
  })
  row({
    { "Copy pose", "Copy the pose on this frame", cmd.copyPose },
    { "Paste", "Paste the copied pose onto this frame", cmd.pastePose },
    { "Reset", "Back to the rest pose on this frame (selected bone, or all)", cmd.resetPose },
    { "Bake", "Flatten the animation into a new frame layer for pixel cleanup", cmd.bake },
  })
  row({
    { "Rename", "Rename the selected bone", function() if B then A.openModal("rename", { what = "bone", target = B }) end end },
    { "Delete", "Delete the selected bone (its children move up)", cmd.deleteBone },
    { "Deselect", "New bones start a new root", function() S.bone = nil end },
    { "Bind lyr", "Bind the current layer to the selected bone", cmd.bindBone },
  })
  if B then
    local r, bx, by, keyed = rig.key(B, S.frame)
    local deg = r * 180 / math.pi
    local nv, ch, rel = ui.slider("bonerot", x, y, w, 16, U.clamp(deg, -180, 180), -180, 180, "turn ", { fmt = "%.0f", step = 1, tip = "Rotation on this frame (keys it)" })
    if ch then rig.setKey(B, S.frame, nv * math.pi / 180, bx, by) end
    if rel then A.commit() end
    y = y + 20
    local k = B.keys[S.frame]
    ui.text(string.format("%s  offset %d,%d  %s", keyed and "keyed here" or "interpolated", bx, by, k and k.ease and "eased" or ""), x, y, keyed and T.accent or T.dim, ui.small)
    y = y + 16
  else
    ui.text("Pose tool: click a bone. Bone tool: drag to add.", x, y, T.dim, ui.small)
    y = y + 16
  end
  return y
end

local function drawBoneList(A, x, y, w, h)
  local S, D = A.S, A.S.D
  local rh = 18
  local n = #D.bones
  local visible = math.max(1, math.floor(h / rh))
  S.boneScroll = U.clamp((S.boneScroll or 0) - ui.scroll(x, y, w, h), 0, math.max(0, n - visible))
  if n == 0 then
    ui.text("No bones yet. Add a template above, or", x, y + 2, T.dim, ui.small)
    ui.text("use the Bone tool (K) in the canvas.", x, y + 16, T.dim, ui.small)
    return
  end
  lg.setScissor(x, y, w, h)
  for row = 0, visible - 1 do
    local B = D.bones[row + 1 + S.boneScroll]
    if not B then break end
    local ry = y + row * rh
    local cur = B.id == S.bone
    ui.rect(cur and T.btnActive or (row % 2 == 0 and T.panel2 or T.panel), x, ry, w, rh - 1)
    local depth = rig.depth(D, B)
    local keyed = B.keys[S.frame]
    ui.text(B.name, x + 6 + depth * 10, ry + 2, T.text)
    local nk = 0
    for _, k in ipairs(B.keys) do if k then nk = nk + 1 end end
    local s = (keyed and "key  " or "") .. nk .. " keys"
    ui.text(s, x + w - ui.small:getWidth(s) - 4, ry + 3, keyed and T.accent or T.dim, ui.small)
    if ui.clicked(x, ry, w, rh) then A.selectBone(B.id) end
  end
  lg.setScissor()
end

function P.drawRight(A, R)
  local S = A.S
  panelBg(R)
  ui.rect(T.line, R.x, R.y, 1, R.h)
  local x, w = R.x + 8, R.w - 16
  local y = drawColor(A, x, R.y + 6, w)
  -- tabs
  local tabs = { { "layers", "Layers" }, { "fx", "Effects" }, { "rig", "Rig" } }
  local tw = math.floor((w - 4) / 3)
  for i, t in ipairs(tabs) do
    if ui.button(t[2], x + (i - 1) * (tw + 2), y, tw, 22, { active = S.tab == t[1] }) then S.tab = t[1] end
  end
  y = y + 28
  local bottom = R.y + R.h - 6
  if S.tab == "layers" then
    y = drawLayers(A, x, y, w, bottom - y)
    drawLayerList(A, x, y, w, bottom - y)
  elseif S.tab == "fx" then
    drawFx(A, x, y, w)
  else
    y = drawRig(A, x, y, w, bottom - y)
    drawBoneList(A, x, y + 2, w, bottom - y - 2)
  end
end

return P
