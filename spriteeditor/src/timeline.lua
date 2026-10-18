-- The timeline: playback and frame controls, tags, bone keys and a layer x frame grid of cels
local U = require("src.util")
local rig = require("src.rig")
local ui = require("src.ui")

local TL = {}
local lg = love.graphics
local T = ui.theme

local LW, CW, RH = 190, 20, 18

function TL.draw(A, R)
  local S, D, cmd = A.S, A.S.D, A.cmd
  ui.rect(T.panel, R.x, R.y, R.w, R.h)
  ui.rect(T.line, R.x, R.y, R.w, 1)
  local nf = #D.frames
  -- controls ---------------------------------------------------------------------------------------
  local x, y, h = R.x + 6, R.y + 5, 22
  local function b(label, w, tip, o)
    o = o or {}
    o.tip = tip
    local r = ui.button(label, x, y, w, h, o)
    x = x + w + 3
    return r
  end
  local function gap() x = x + 10 end
  if b(S.playing and "Stop" or "Play", 48, "Play / stop (Enter)", { active = S.playing }) then cmd.togglePlay() end
  if b("|<", 24, "First frame (Home)") then A.setFrame(1) end
  if b("<", 24, "Previous frame (,)") then A.setFrame(S.frame - 1) end
  if b(">", 24, "Next frame (.)") then A.setFrame(S.frame + 1) end
  if b(">|", 24, "Last frame (End)") then A.setFrame(nf) end
  gap()
  if b("+ Frame", 58, "New empty frame after this one (F)") then cmd.addFrame(false) end
  if b("Dup", 38, "Duplicate this frame (Shift+F)") then cmd.addFrame(true) end
  if b("Del", 38, "Delete this frame (or the shift-selected range)") then cmd.deleteFrame() end
  if b("< Move", 52, "Move this frame earlier") then cmd.moveFrame(-1) end
  if b("Move >", 52, "Move this frame later") then cmd.moveFrame(1) end
  gap()
  local dur = D.frames[S.frame].dur
  local nv, ch, rel = ui.slider("dur", x, y, 150, h, dur, 20, 500, "", { step = 10, tip = "How long this frame (or the selected range) shows" })
  ui.textc(string.format("%d ms  (%.1f fps)", dur, 1000 / dur), x, y, 150, h, T.text, ui.small)
  if ch then cmd.setDuration(nv, false) end
  if rel then A.commit() end
  x = x + 153
  if b("-", 18, "10ms shorter") then cmd.setDuration(dur - 10, false) A.commit() end
  if b("+", 18, "10ms longer") then cmd.setDuration(dur + 10, false) A.commit() end
  if b("All", 34, "Give every frame this duration") then cmd.setDuration(dur, true) A.commit() end
  gap()
  if b("Onion", 48, "Onion skin: earlier frames red, later frames blue (N)", { active = S.onion }) then S.onion = not S.onion end
  if b("-", 18, "Fewer onion frames") then S.onionN = math.max(1, S.onionN - 1) end
  ui.textc(tostring(S.onionN), x, y, 14, h, T.dim)
  x = x + 17
  if b("+", 18, "More onion frames") then S.onionN = math.min(3, S.onionN + 1) end
  if b("Loop", 42, "Loop playback", { active = S.loop }) then S.loop = not S.loop end
  gap()
  if b("+ Tag", 48, "Name the selected frame range (an animation such as idle or walk)") then cmd.addTag() end
  if b("- Tag", 48, "Delete the selected tag") then cmd.deleteTag() end
  if b("Rename", 54, "Rename the selected tag", { disabled = not (S.tag and D.tags[S.tag]) }) then
    A.openModal("rename", { what = "tag", target = D.tags[S.tag] })
  end
  -- grid -------------------------------------------------------------------------------------------
  local gy = R.y + 32
  local gx = R.x + LW
  local gw = R.w - LW - 8
  local nvis = math.max(1, math.floor(gw / CW))
  if S.tlLastFrame ~= S.frame then
    if S.frame <= S.tlScroll then S.tlScroll = S.frame - 1
    elseif S.frame > S.tlScroll + nvis then S.tlScroll = S.frame - nvis end
    S.tlLastFrame = S.frame
  end
  local tagY, numY, rigY, layY = gy, gy + 16, gy + 33, gy + 53
  local bottom = R.y + R.h - 4
  local nrows = math.max(1, math.floor((bottom - layY) / RH))
  local nl = #D.layers
  S.tlLayerScroll = U.clamp(S.tlLayerScroll or 0, 0, math.max(0, nl - nrows))
  local wheelGrid = ui.scroll(gx, gy, gw, bottom - gy)
  if wheelGrid ~= 0 then S.tlScroll = S.tlScroll - wheelGrid * 2 end
  local wheelLabels = ui.scroll(R.x, layY, LW, bottom - layY)
  if wheelLabels ~= 0 then S.tlLayerScroll = U.clamp(S.tlLayerScroll - wheelLabels, 0, math.max(0, nl - nrows)) end
  S.tlScroll = U.clamp(S.tlScroll, 0, math.max(0, nf - nvis))
  local function colX(f) return gx + (f - 1 - S.tlScroll) * CW end
  local function colAt(mx) return math.floor((mx - gx) / CW) + 1 + S.tlScroll end
  local ra, rb = S.rangeA, S.rangeB
  if ra and rb then ra, rb = math.min(ra, rb), math.max(ra, rb) end
  lg.setScissor(gx, gy, gw, bottom - gy)
  -- column backgrounds
  for f = S.tlScroll + 1, math.min(nf, S.tlScroll + nvis) do
    local cx = colX(f)
    if ra and f >= ra and f <= rb then ui.rect({ 0.25, 0.32, 0.45 }, cx, numY, CW - 1, bottom - numY) end
    if f == S.frame then ui.rect({ 0.24, 0.40, 0.36 }, cx, numY, CW - 1, bottom - numY) end
    if S.playing and f == S.frame then ui.rect(T.accent, cx, numY, CW - 1, 2) end
    ui.textc(tostring(f), cx, numY, CW - 1, 15, f == S.frame and T.text or T.dim, ui.small)
  end
  -- tags
  for i, Tg in ipairs(D.tags) do
    local x1, x2 = colX(Tg.from), colX(Tg.to) + CW - 1
    local hue = (i * 0.17) % 1
    local r, g, bb = U.hsv2rgb(hue, 0.55, i == S.tag and 0.85 or 0.55)
    ui.rect({ r, g, bb }, x1, tagY, x2 - x1, 14)
    ui.text(ui.fit(Tg.name, x2 - x1 - 4, ui.small), x1 + 3, tagY + 1, { 0, 0, 0 }, ui.small)
  end
  -- rig keys
  if #D.bones > 0 then
    for f = S.tlScroll + 1, math.min(nf, S.tlScroll + nvis) do
      local cx = colX(f) + CW / 2
      local sel, any = false, false
      for _, B in ipairs(D.bones) do
        if B.keys[f] then
          any = true
          if B.id == S.bone then sel = true end
        end
      end
      if sel then
        lg.setColor(1, 0.6, 0.35)
        lg.polygon("fill", cx, rigY + 3, cx + 5, rigY + 8, cx, rigY + 13, cx - 5, rigY + 8)
      elseif any then
        lg.setColor(0.75, 0.55, 0.45)
        lg.polygon("line", cx, rigY + 4, cx + 4, rigY + 8, cx, rigY + 12, cx - 4, rigY + 8)
      end
    end
  end
  -- cels
  for row = 0, nrows - 1 do
    local i = nl - (row + S.tlLayerScroll)
    local L = D.layers[i]
    if not L then break end
    local ry = layY + row * RH
    if i == S.layer then ui.rect({ 1, 1, 1, 0.05 }, gx, ry, gw, RH - 1) end
    if L.kind == "part" or L.kind == "ref" then
      local x1, x2 = colX(1), colX(nf) + CW - 1
      ui.rect(L.kind == "ref" and { 0.45, 0.35, 0.25, 0.6 } or { 0.30, 0.45, 0.60, 0.7 }, x1 + 2, ry + 5, x2 - x1 - 4, RH - 10)
    else
      for f = S.tlScroll + 1, math.min(nf, S.tlScroll + nvis) do
        local cx = colX(f)
        if L.cels[f] then
          lg.setColor(f == S.frame and i == S.layer and T.sel or (L.visible and T.text or T.dim))
          lg.rectangle("fill", cx + 5, ry + 4, CW - 11, RH - 9)
        else
          lg.setColor(T.line)
          lg.circle("line", cx + CW / 2, ry + RH / 2, 2)
        end
      end
    end
  end
  lg.setScissor()
  -- grid input
  local shift = love.keyboard.isDown("lshift", "rshift")
  local function pickFrame(f, isShift)
    f = U.clamp(f, 1, nf)
    if isShift then
      S.rangeA = S.rangeA or S.frame
      S.rangeB = f
    else
      S.rangeA, S.rangeB = nil, nil
    end
    A.setFrame(f)
  end
  if ui.clicked(gx, numY, gw, bottom - numY) then
    local f = colAt(ui.mx)
    if f >= 1 and f <= nf then
      pickFrame(f, shift)
      if ui.my >= layY then
        local row = math.floor((ui.my - layY) / RH)
        local i = nl - (row + S.tlLayerScroll)
        if D.layers[i] then A.setLayer(i) end
      end
      S.tlScrub = ui.my < rigY
    end
  end
  if S.tlScrub then
    if love.mouse.isDown(1) then
      local f = U.clamp(colAt(ui.mx), 1, nf)
      if f ~= S.frame then A.setFrame(f) end
    else
      S.tlScrub = false
    end
  end
  if ui.clicked(gx, tagY, gw, 15) then
    local f = colAt(ui.mx)
    local hit
    for i, Tg in ipairs(D.tags) do
      if f >= Tg.from and f <= Tg.to then hit = i end
    end
    if hit then
      local now = love.timer.getTime()
      if S.tag == hit and now - (S.tagClickT or 0) < 0.35 then
        A.openModal("rename", { what = "tag", target = D.tags[hit] })
      end
      S.tagClickT = now
      S.tag = hit
      S.rangeA, S.rangeB = D.tags[hit].from, D.tags[hit].to
      A.setFrame(D.tags[hit].from)
    else
      S.tag = nil
    end
  end
  if ui.hit(gx, gy, gw, bottom - gy) then ui.tip = "Click a cel to select it, Shift+click for a range, drag the numbers to scrub, wheel scrolls" end
  -- labels -----------------------------------------------------------------------------------------
  ui.text("Tags", R.x + 8, tagY + 1, T.dim, ui.small)
  ui.text("Frame", R.x + 8, numY + 1, T.dim, ui.small)
  local B = S.bone and rig.bone(D, S.bone)
  ui.text("Bone keys" .. (B and (": " .. B.name) or ""), R.x + 8, rigY + 2, T.dim, ui.small)
  for row = 0, nrows - 1 do
    local i = nl - (row + S.tlLayerScroll)
    local L = D.layers[i]
    if not L then break end
    local ry = layY + row * RH
    ui.rect(i == S.layer and T.btnActive or (row % 2 == 0 and T.panel2 or T.panel), R.x + 4, ry, LW - 8, RH - 1)
    lg.setColor(L.visible and T.text or T.dim)
    if L.visible then lg.circle("fill", R.x + 13, ry + RH / 2, 3.5) else lg.circle("line", R.x + 13, ry + RH / 2, 3.5) end
    if ui.clicked(R.x + 4, ry, 18, RH) then L.visible = not L.visible end
    local tag = L.kind == "part" and " [part]" or (L.kind == "ref" and " [ref]" or "")
    ui.text(ui.fit(L.name .. tag, LW - 36), R.x + 24, ry + 2, L.visible and T.text or T.dim)
    if ui.clicked(R.x + 22, ry, LW - 26, RH) then A.setLayer(i) end
  end
  if nl > nrows then
    ui.text(string.format("%d-%d of %d layers (wheel)", S.tlLayerScroll + 1, S.tlLayerScroll + nrows, nl), R.x + 8, bottom - 12, T.dim, ui.small)
  end
end

return TL
