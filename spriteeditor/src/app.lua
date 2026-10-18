-- The editor: state, canvas view, tool handling and commands. Panels, the timeline and dialogs
-- live in their own modules and call back into this one.
local U = require("src.util")
local doc = require("src.doc")
local rig = require("src.rig")
local paint = require("src.paint")
local fx = require("src.fx")
local render = require("src.render")
local history = require("src.history")
local fileio = require("src.fileio")
local presets = require("src.presets")
local ui = require("src.ui")

local A = {}
local S = {}
A.S = S
A.cmd = {}
local cmd = A.cmd
local lg = love.graphics
local T = ui.theme

A.TOOLS = {
  { id = "pencil", label = "Pen", key = "b", tip = "Pencil (B). Right click paints the 2nd colour" },
  { id = "eraser", label = "Erase", key = "e", tip = "Eraser (E)" },
  { id = "fill", label = "Fill", key = "g", tip = "Bucket fill (G)" },
  { id = "picker", label = "Pick", key = "i", tip = "Colour picker (I, or hold Alt with any tool)" },
  { id = "line", label = "Line", key = "l", tip = "Line (L). Shift snaps to 45 degrees" },
  { id = "rect", label = "Rect", key = "u", tip = "Rectangle (U). Shift makes a square" },
  { id = "ellipse", label = "Oval", key = "o", tip = "Ellipse (O). Shift makes a circle" },
  { id = "select", label = "Select", key = "m", tip = "Rectangle select (M). Ctrl+C / X / V, Delete" },
  { id = "move", label = "Move", key = "v", tip = "Move (V): drags the selection, or the whole cel. Arrows nudge" },
  { id = "bone", label = "Bone", key = "k", tip = "Bone (K): drag to add a bone (from a tip: chained). Click selects, Alt+drag moves a joint" },
  { id = "pose", label = "Pose", key = "p", tip = "Pose (P): drag a bone to turn it, Shift+drag moves it, drag near its tip for IK" },
}
local PAINT = { pencil = true, eraser = true, fill = true, line = true, rect = true, ellipse = true }
A.MODES = {
  { id = "normal", label = "Normal", tip = "Paint the colour" },
  { id = "shadeUp", label = "Light", tip = "Shade: steps each pixel to the nearest lighter palette colour" },
  { id = "shadeDown", label = "Dark", tip = "Shade: steps each pixel to the nearest darker palette colour" },
  { id = "dither", label = "Dither", tip = "Checkerboard of both colours (a clear 2nd colour leaves gaps)" },
}

local function ctrlDown() return love.keyboard.isDown("lctrl", "rctrl") end
local function shiftDown() return love.keyboard.isDown("lshift", "rshift") end
local function altDown() return love.keyboard.isDown("lalt", "ralt") end

function A.msg(s, warn)
  S.msg, S.msgT, S.msgWarn = s, 4, warn
end

-- Document lifecycle -------------------------------------------------------------------------------

function A.ensureCanvases()
  local D = S.D
  if S.compW == D.w and S.compH == D.h then return end
  for _, c in ipairs({ S.comp, S.work, S.pvC }) do c:release() end
  for _, c in ipairs(S.onionC or {}) do c:release() end
  S.comp, S.work, S.pvC = render.newCanvas(D.w, D.h), render.newCanvas(D.w, D.h), render.newCanvas(D.w, D.h)
  S.onionC = {}
  for i = 1, 6 do S.onionC[i] = render.newCanvas(D.w, D.h) end
  S.compW, S.compH = D.w, D.h
end

function A.setDoc(D, path)
  S.D, S.path = D, path
  S.frame, S.layer, S.bone = 1, #D.layers, nil
  S.sel, S.float, S.drag, S.tag, S.rangeA, S.rangeB = nil, nil, nil, nil, nil, nil
  S.playing, S.pvFrame, S.pvT = false, 1, 0
  S.tlScroll, S.layerScroll = 0, 0
  history.reset(D)
  S.savedVersion = history.version
  A.ensureCanvases()
  A.fit()
  A.updateTitle()
end

-- After undo/redo: same view, indices kept in range
function A.replaceDoc(D)
  S.D = D
  S.float, S.drag = nil, nil
  S.frame = U.clamp(S.frame, 1, #D.frames)
  S.pvFrame = U.clamp(S.pvFrame, 1, #D.frames)
  S.layer = U.clamp(S.layer, 1, math.max(1, #D.layers))
  if S.bone and not rig.bone(D, S.bone) then S.bone = nil end
  if S.tag and not D.tags[S.tag] then S.tag = nil end
  A.ensureCanvases()
end

function A.isDirty()
  return history.version ~= S.savedVersion
end

function A.updateTitle()
  local name = S.path or (S.D.name .. " (unsaved)")
  love.window.setTitle("Gunnug Sprite Editor - " .. name .. (A.isDirty() and " *" or ""))
end

function A.commit()
  history.commit(S.D)
  A.updateTitle()
end

function A.layerObj()
  return S.D.layers[S.layer]
end

-- The current layer if it can be painted, otherwise nil with a message
function A.editableLayer(quiet)
  local L = A.layerObj()
  local why
  if not L then why = "No layer"
  elseif L.locked then why = "Layer \"" .. L.name .. "\" is locked"
  elseif not L.visible then why = "Layer \"" .. L.name .. "\" is hidden"
  end
  if why then
    if not quiet then A.msg(why, true) end
    return nil
  end
  return L
end

function A.isRest()
  return S.restPose or S.tool == "bone"
end

-- Inverse skin mapping for painting into a layer that rides a posed bone
function A.layerInv(L)
  if not L.bone or A.isRest() then return nil end
  local pb = rig.pose(S.D, S.frame)[L.bone]
  if not pb or rig.isIdentity(pb.m) then return nil end
  return rig.inverse(pb.m)
end

function A.setFrame(f)
  A.dropFloat()
  S.frame = U.clamp(f, 1, #S.D.frames)
end

function A.setLayer(i)
  A.dropFloat()
  S.layer = U.clamp(i, 1, math.max(1, #S.D.layers))
  local L = A.layerObj()
  if L and L.bone then S.bone = L.bone end
end

function A.selectBone(id)
  S.bone = id
  if not id then return end
  for i, L in ipairs(S.D.layers) do
    if L.bone == id then
      if S.layer ~= i then A.setLayer(i) end
      return
    end
  end
end

function A.setTool(t)
  if t ~= "move" then A.dropFloat() end
  S.tool = t
end

-- The frame range playback loops over: the selected tag, else the tag holding the frame, else all
function A.playRange(f)
  local D = S.D
  if S.tag and D.tags[S.tag] then
    local T_ = D.tags[S.tag]
    if f >= T_.from and f <= T_.to then return T_.from, T_.to end
  end
  for _, T_ in ipairs(D.tags) do
    if f >= T_.from and f <= T_.to then return T_.from, T_.to end
  end
  return 1, #D.frames
end

local function nextFrame(f)
  local a, b = A.playRange(f)
  if f >= b or f < a then return a end
  return f + 1
end

-- View ---------------------------------------------------------------------------------------------

function A.layout()
  local W, H = lg.getDimensions()
  local L = {}
  L.top = { x = 0, y = 0, w = W, h = 30 }
  L.status = { x = 0, y = H - 22, w = W, h = 22 }
  L.tl = { x = 0, y = H - 22 - 210, w = W, h = 210 }
  L.left = { x = 0, y = 30, w = 84, h = L.tl.y - 30 }
  L.right = { x = W - 296, y = 30, w = 296, h = L.tl.y - 30 }
  L.canvas = { x = 84, y = 30, w = W - 84 - 296, h = L.tl.y - 30 }
  S.L = L
end

function A.fit()
  A.layout()
  local C, D = S.L.canvas, S.D
  S.zoom = math.max(1, math.floor(math.min(C.w * 0.75 / D.w, C.h * 0.8 / D.h)))
  S.panX = math.floor(C.x + (C.w - D.w * S.zoom) / 2)
  S.panY = math.floor(C.y + (C.h - D.h * S.zoom) / 2)
end

function A.zoomAt(mx, my, z)
  z = U.clamp(z, 1, 64)
  if z == S.zoom then return end
  S.panX = U.round(mx - (mx - S.panX) * z / S.zoom)
  S.panY = U.round(my - (my - S.panY) * z / S.zoom)
  S.zoom = z
end

function A.zoomStep(dir)
  local C = S.L.canvas
  local steps = { 1, 2, 3, 4, 5, 6, 8, 10, 12, 16, 20, 24, 32, 40, 48, 64 }
  local z = S.zoom
  if dir > 0 then
    for _, s in ipairs(steps) do if s > S.zoom then z = s break end end
  else
    for i = #steps, 1, -1 do if steps[i] < S.zoom then z = steps[i] break end end
  end
  local mx, my = love.mouse.getPosition()
  if not U.inRect(mx, my, C.x, C.y, C.w, C.h) then mx, my = C.x + C.w / 2, C.y + C.h / 2 end
  A.zoomAt(mx, my, z)
end

function A.toPixel(mx, my)
  return (mx - S.panX) / S.zoom, (my - S.panY) / S.zoom
end

function A.inCanvas(x, y)
  local C = S.L.canvas
  return U.inRect(x, y, C.x, C.y, C.w, C.h)
end

function A.previewRect()
  local C, D = S.L.canvas, S.D
  local s = 3 -- the game draws its 640x360 world at 3x on a 1080p screen
  while s > 1 and (D.w * s > C.w * 0.3 or D.h * s > C.h * 0.45) do s = s - 1 end
  local w, h = D.w * s, D.h * s
  return C.x + C.w - w - 14, C.y + 26, w, h, s
end

-- The preview's frame, wide enough for its label
function A.previewBox()
  local _, py, pw, ph = A.previewRect()
  local bw = math.max(pw + 8, 112)
  local C = S.L.canvas
  return C.x + C.w - bw - 10, py - 18, bw, ph + 22
end

function A.overPreview(x, y)
  if not S.preview then return false end
  local bx, by, bw, bh = A.previewBox()
  return U.inRect(x, y, bx, by, bw, bh)
end

-- Floating selection -------------------------------------------------------------------------------

local function clipRect(r, w, h)
  local x0, y0 = math.max(0, r.x), math.max(0, r.y)
  local x1, y1 = math.min(w, r.x + r.w), math.min(h, r.y + r.h)
  return { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
end

local function newFloat(L, data, x, y, changed)
  local img = lg.newImage(data)
  img:setFilter("nearest", "nearest")
  local w, h = data:getDimensions()
  S.float = { layerId = L.id, frame = S.frame, data = data, img = img, x = x, y = y, w = w, h = h, changed = changed }
end

-- Lifts the selection (or the whole cel) off the current layer so it can be moved
function A.lift()
  local L = A.editableLayer()
  if not L or L.kind == "ref" then return false end
  local cel = doc.cel(S.D, L, S.frame)
  if not cel then
    A.msg("Nothing on this frame to move", true)
    return false
  end
  local cw, ch = cel.data:getDimensions()
  local r = S.sel and clipRect(S.sel, cw, ch) or { x = 0, y = 0, w = cw, h = ch }
  if r.w <= 0 or r.h <= 0 then return false end
  local data = love.image.newImageData(r.w, r.h)
  data:paste(cel.data, 0, 0, r.x, r.y, r.w, r.h)
  fx.clear(cel.data, r)
  doc.touch(cel)
  newFloat(L, data, r.x, r.y, false)
  return true
end

function A.dropFloat()
  local F = S.float
  if not F then return end
  S.float = nil
  local L = doc.layerById(S.D, F.layerId)
  if L then
    local cel = doc.cel(S.D, L, F.frame, true)
    local d = cel.data
    local cw, ch = d:getDimensions()
    for y = 0, F.h - 1 do
      for x = 0, F.w - 1 do
        local r, g, b, a = F.data:getPixel(x, y)
        local tx, ty = F.x + x, F.y + y
        if a > 0 and tx >= 0 and ty >= 0 and tx < cw and ty < ch then d:setPixel(tx, ty, r, g, b, a) end
      end
    end
    doc.touch(cel)
  end
  F.img:release()
  if F.changed then A.commit() end
end

-- Throws away uncommitted changes (a lifted selection) by going back to the last snapshot
function A.cancelFloat()
  if not S.float then return end
  S.float.img:release()
  A.replaceDoc(history.revert())
end

-- Colour -------------------------------------------------------------------------------------------

function A.setPrimary(c)
  S.primary = { c[1], c[2], c[3], c[4] }
  local h, s, v = U.rgb2hsv(c[1], c[2], c[3])
  if s == 0 or v == 0 then h = S.hsv and S.hsv[1] or 0 end
  if v == 0 then s = S.hsv and S.hsv[2] or 0 end
  S.hsv = { h, s, v }
end

function A.pick(ix, iy, b)
  local D = S.D
  if ix < 0 or iy < 0 or ix >= D.w or iy >= D.h then return end
  local c
  local L = A.layerObj()
  if L and L.kind ~= "ref" and L.visible then
    local cel = doc.cel(D, L, S.frame)
    if cel then
      local cx, cy = ix, iy
      local inv = A.layerInv(L)
      if inv then cx, cy = inv(ix, iy) end
      local w, h = cel.data:getDimensions()
      if cx >= 0 and cy >= 0 and cx < w and cy < h then
        local r, g, bb, a = cel.data:getPixel(cx, cy)
        if a > 0 then c = { r, g, bb, a } end
      end
    end
  end
  if not c then
    local d = render.frameData(D, S.frame, S.work, { skipRef = true, rest = A.isRest() })
    local r, g, bb, a = d:getPixel(ix, iy)
    d:release()
    if a > 0 then c = { r, g, bb, a } end
  end
  if not c then
    for i = #D.layers, 1, -1 do
      local R = D.layers[i]
      if R.kind == "ref" and R.visible then
        local d = R.part.data
        local x, y = ix - (R.ox or 0), iy - (R.oy or 0)
        local w, h = d:getDimensions()
        if x >= 0 and y >= 0 and x < w and y < h then
          local r, g, bb, a = d:getPixel(x, y)
          if a > 0 then c = { r, g, bb, 1 } break end
        end
      end
    end
  end
  c = c or { 0, 0, 0, 0 }
  if b == 2 then S.secondary = c else A.setPrimary(c) end
end

-- Canvas interaction -------------------------------------------------------------------------------

local function makeCtx(L, b)
  local cel = doc.cel(S.D, L, S.frame, true)
  local c1, c2 = S.primary, S.secondary
  if b == 2 then c1, c2 = c2, c1 end
  return paint.begin({
    cel = cel, inv = A.layerInv(L), color = c1, color2 = c2, erase = S.tool == "eraser",
    mode = S.mode, lockAlpha = S.lockAlpha, size = S.size, mirrorX = S.mirrorX, mirrorY = S.mirrorY,
    sel = S.sel, pp = S.pixelPerfect and S.tool == "pencil", palette = S.D.palette, W = S.D.w, H = S.D.h,
  })
end

local function finishPaint(ctx)
  if ctx.touched then
    doc.touch(ctx.cel)
    A.commit()
  end
end

local function boneTol()
  return math.max(0.7, 7 / S.zoom)
end

local function nearestBone(P, x, y, tol)
  local best, bd, bt
  local bones = S.D.bones
  for i = #bones, 1, -1 do -- later bones (drawn in front) win ties
    local B = bones[i]
    local d, t = rig.distance(P[B.id], x, y)
    if d < tol and (not bd or d < bd) then best, bd, bt = B, d, t end
  end
  return best, bt
end

local function dist(x1, y1, x2, y2)
  return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2)
end

local function snapHalf(v)
  return U.round(v * 2) / 2
end

-- Bone tool (always in rest pose). Drag adds a bone: from a bone's tip it chains a child of that
-- bone, from anywhere else it is a child of the selected bone (Ctrl: a new root). A click selects.
-- Alt+drag moves a joint: the tip (children attached there follow) or the head.
local function bonePress(px, py)
  local D = S.D
  local P = rig.pose(D, S.frame, true)
  local tol = boneTol()
  if altDown() then
    for i = #D.bones, 1, -1 do
      local B = D.bones[i]
      local p = P[B.id]
      if dist(p.tx, p.ty, px, py) < tol then
        local kids = {}
        for _, C in ipairs(D.bones) do
          if C.parent == B.id and dist(C.x, C.y, p.tx, p.ty) < 0.01 then kids[#kids + 1] = C end
        end
        A.selectBone(B.id)
        S.drag = { kind = "boneTail", bone = B, kids = kids }
        return
      end
    end
    for i = #D.bones, 1, -1 do
      local B = D.bones[i]
      if dist(B.x, B.y, px, py) < tol then
        local p = P[B.id]
        A.selectBone(B.id)
        S.drag = { kind = "boneHead", bone = B, tx = p.tx, ty = p.ty }
        return
      end
    end
    return
  end
  local parent = not ctrlDown() and S.bone or nil
  local hx, hy = snapHalf(px), snapHalf(py)
  for i = #D.bones, 1, -1 do
    local p = P[D.bones[i].id]
    if dist(p.tx, p.ty, px, py) < tol then
      parent, hx, hy = D.bones[i].id, p.tx, p.ty
      break
    end
  end
  S.drag = { kind = "newBone", parent = parent, x0 = hx, y0 = hy, x1 = hx, y1 = hy, clickBone = nearestBone(P, px, py, tol) }
end

local function posePress(px, py)
  local D, f = S.D, S.frame
  local P = rig.pose(D, f)
  local B, t = nearestBone(P, px, py, boneTol())
  if not B then
    S.bone = nil
    return
  end
  A.selectBone(B.id)
  local p = P[B.id]
  local r0, x0, y0 = rig.key(B, f)
  if shiftDown() then
    S.drag = { kind = "poseMove", bone = B, sx = px, sy = py, r0 = r0, x0 = x0, y0 = y0 }
  elseif S.ik and t > 0.6 and B.parent then
    S.drag = { kind = "poseIK", bone = B }
  else
    S.drag = { kind = "poseRot", bone = B, g0 = math.atan2(py - p.hy, px - p.hx), r0 = r0, x0 = x0, y0 = y0 }
  end
end

function A.canvasPress(x, y, b)
  if b == 3 or (b == 1 and love.keyboard.isDown("space")) then
    S.drag = { kind = "pan", button = b, sx = x, sy = y, px = S.panX, py = S.panY }
    return
  end
  if b ~= 1 and b ~= 2 then return end
  S.playing = false
  local px, py = A.toPixel(x, y)
  local ix, iy = math.floor(px), math.floor(py)
  local tool = S.tool
  if altDown() and PAINT[tool] then tool = "picker" end
  if tool == "picker" then
    A.pick(ix, iy, b)
    S.drag = { kind = "picker", button = b }
    return
  end
  if tool == "bone" then
    if b == 1 then bonePress(px, py) end
    if S.drag then S.drag.button = b end
    return
  end
  if tool == "pose" then
    if b == 1 then posePress(px, py) end
    if S.drag then S.drag.button = b end
    return
  end
  if tool == "select" then
    A.dropFloat()
    S.sel = nil
    S.drag = { kind = "select", button = b, x0 = ix, y0 = iy, x1 = ix, y1 = iy }
    return
  end
  if tool == "move" then
    local L = A.editableLayer()
    if not L then return end
    if L.kind == "ref" then
      S.drag = { kind = "moveRef", button = b, layer = L, sx = ix, sy = iy, ox = L.ox or 0, oy = L.oy or 0 }
      return
    end
    if not S.float and not A.lift() then return end
    S.drag = { kind = "move", button = b, sx = ix, sy = iy, fx = S.float.x, fy = S.float.y }
    return
  end
  local L = A.editableLayer()
  if not L then return end
  if L.kind == "ref" then
    A.msg("That's a reference layer: pick a drawing layer", true)
    return
  end
  A.dropFloat()
  local ctx = makeCtx(L, b)
  if tool == "fill" then
    paint.fill(ctx, ix, iy, S.fillGlobal)
    finishPaint(ctx)
    return
  end
  if tool == "pencil" or tool == "eraser" then
    paint.strokeTo(ctx, ix, iy)
    doc.touch(ctx.cel)
    S.drag = { kind = "stroke", button = b, ctx = ctx }
    return
  end
  S.drag = { kind = "shape", button = b, ctx = ctx, tool = tool, x0 = ix, y0 = iy, x1 = ix, y1 = iy }
end

-- The pixels a shape drag covers (shift constrains it)
function A.shapePoints(d)
  local x0, y0, x1, y1 = d.x0, d.y0, d.x1, d.y1
  local dx, dy = x1 - x0, y1 - y0
  if shiftDown() then
    if d.tool == "line" then
      local ax, ay = math.abs(dx), math.abs(dy)
      if ax > 2 * ay then dy = 0
      elseif ay > 2 * ax then dx = 0
      else
        local m = math.max(ax, ay)
        dx, dy = (dx < 0 and -m or m), (dy < 0 and -m or m)
      end
    else
      local m = math.max(math.abs(dx), math.abs(dy))
      dx, dy = (dx < 0 and -m or m), (dy < 0 and -m or m)
    end
    x1, y1 = x0 + dx, y0 + dy
  end
  if d.tool == "line" then return paint.linePoints(x0, y0, x1, y1) end
  if d.tool == "rect" then return paint.rectPoints(x0, y0, x1, y1, S.fillShapes) end
  return paint.ellipsePoints(x0, y0, x1, y1, S.fillShapes)
end

function A.canvasMove(x, y)
  local d = S.drag
  local px, py = A.toPixel(x, y)
  local ix, iy = math.floor(px), math.floor(py)
  S.hoverX, S.hoverY = ix, iy
  if not d then return end
  local D, f = S.D, S.frame
  if d.kind == "pan" then
    S.panX, S.panY = d.px + (x - d.sx), d.py + (y - d.sy)
  elseif d.kind == "picker" then
    A.pick(ix, iy, d.button)
  elseif d.kind == "stroke" then
    paint.strokeTo(d.ctx, ix, iy)
    doc.touch(d.ctx.cel)
  elseif d.kind == "shape" then
    d.x1, d.y1 = ix, iy
  elseif d.kind == "select" then
    d.x1, d.y1 = ix, iy
    d.moved = d.moved or ix ~= d.x0 or iy ~= d.y0
    local x0, x1 = math.min(d.x0, ix), math.max(d.x0, ix)
    local y0, y1 = math.min(d.y0, iy), math.max(d.y0, iy)
    local r = clipRect({ x = x0, y = y0, w = x1 - x0 + 1, h = y1 - y0 + 1 }, D.w, D.h)
    S.sel = (d.moved and r.w > 0 and r.h > 0) and r or nil
  elseif d.kind == "move" and S.float then
    S.float.x, S.float.y = d.fx + ix - d.sx, d.fy + iy - d.sy
    S.float.changed = S.float.changed or ix ~= d.sx or iy ~= d.sy
    if S.sel then S.sel.x, S.sel.y = S.float.x, S.float.y end
  elseif d.kind == "moveRef" then
    d.layer.ox, d.layer.oy = d.ox + ix - d.sx, d.oy + iy - d.sy
    d.moved = true
  elseif d.kind == "newBone" then
    d.x1, d.y1 = snapHalf(px), snapHalf(py)
  elseif d.kind == "boneTail" then
    local B = d.bone
    local tx, ty = snapHalf(px), snapHalf(py)
    B.angle = math.atan2(ty - B.y, tx - B.x)
    B.len = math.max(1, dist(B.x, B.y, tx, ty))
    local ex, ey = B.x + math.cos(B.angle) * B.len, B.y + math.sin(B.angle) * B.len
    for _, C in ipairs(d.kids) do
      local cx, cy = C.x + math.cos(C.angle) * C.len, C.y + math.sin(C.angle) * C.len
      C.x, C.y = ex, ey
      C.angle = math.atan2(cy - ey, cx - ex)
      C.len = math.max(1, dist(ex, ey, cx, cy))
    end
    d.moved = true
  elseif d.kind == "boneHead" then
    local B = d.bone
    B.x, B.y = snapHalf(px), snapHalf(py)
    B.angle = math.atan2(d.ty - B.y, d.tx - B.x)
    B.len = math.max(1, dist(B.x, B.y, d.tx, d.ty))
    d.moved = true
  elseif d.kind == "poseRot" then
    local p = rig.pose(D, f)[d.bone.id]
    local a = math.atan2(py - p.hy, px - p.hx)
    local r = d.r0 + U.wrapAngle(a - d.g0)
    if ctrlDown() then
      local step = math.pi / 12
      r = U.round(r / step) * step
    end
    rig.setKey(d.bone, f, r, d.x0, d.y0)
    d.moved = true
  elseif d.kind == "poseMove" then
    rig.setKey(d.bone, f, d.r0, d.x0 + U.round(px - d.sx), d.y0 + U.round(py - d.sy))
    d.moved = true
  elseif d.kind == "poseIK" then
    rig.ik(D, f, d.bone, px, py, 2)
    d.moved = true
  end
end

function A.canvasRelease(x, y, b)
  local d = S.drag
  if not d or d.button ~= b then return end
  S.drag = nil
  if d.kind == "stroke" then
    finishPaint(d.ctx)
  elseif d.kind == "shape" then
    paint.commitPoints(d.ctx, A.shapePoints(d))
    finishPaint(d.ctx)
  elseif d.kind == "newBone" then
    local len = dist(d.x0, d.y0, d.x1, d.y1)
    if len < 1 then
      A.selectBone(d.clickBone and d.clickBone.id or nil)
    else
      local D = S.D
      local B = rig.add(D, d.parent, d.x0, d.y0, d.x1, d.y1)
      if S.autoPart then
        local L = doc.addLayer(D, B.name, "part", math.min(S.layer + 1, #D.layers + 1))
        L.bone = B.id
        S.layer = U.clamp(S.layer + 1, 1, #D.layers)
      end
      S.bone = B.id
      A.commit()
    end
  elseif (d.kind == "boneTail" or d.kind == "boneHead" or d.kind == "moveRef" or d.kind:match("^pose")) and d.moved then
    A.commit()
  end
end

-- Commands -----------------------------------------------------------------------------------------

function cmd.undo()
  if S.drag then return end
  if S.float then
    A.cancelFloat()
    return
  end
  local D = history.stepBack()
  if D then A.replaceDoc(D) A.msg("Undo") else A.msg("Nothing to undo") end
  A.updateTitle()
end

function cmd.redo()
  if S.drag then return end
  A.dropFloat()
  local D = history.stepForward()
  if D then A.replaceDoc(D) A.msg("Redo") else A.msg("Nothing to redo") end
  A.updateTitle()
end

function cmd.togglePlay()
  A.dropFloat()
  S.playing = not S.playing
  S.playT = 0
end

-- Frames
function cmd.addFrame(dup)
  A.dropFloat()
  doc.insertFrame(S.D, S.frame + 1, dup)
  S.frame = S.frame + 1
  A.commit()
end

function cmd.deleteFrame()
  A.dropFloat()
  local a, b = S.frame, S.frame
  if S.rangeA and S.rangeB then a, b = math.min(S.rangeA, S.rangeB), math.max(S.rangeA, S.rangeB) end
  local n = 0
  for f = b, a, -1 do
    if doc.deleteFrame(S.D, f) then n = n + 1 end
  end
  if n == 0 then A.msg("A sprite needs at least one frame", true) return end
  S.rangeA, S.rangeB = nil, nil
  S.frame = U.clamp(a, 1, #S.D.frames)
  A.commit()
end

function cmd.moveFrame(dir)
  A.dropFloat()
  if doc.swapFrames(S.D, S.frame, S.frame + dir) then
    S.frame = S.frame + dir
    A.commit()
  end
end

function cmd.setDuration(ms, all)
  local D = S.D
  ms = U.clamp(math.floor(ms + 0.5), 10, 5000)
  if all then
    for _, F in ipairs(D.frames) do F.dur = ms end
  elseif S.rangeA and S.rangeB then
    for f = math.min(S.rangeA, S.rangeB), math.max(S.rangeA, S.rangeB) do D.frames[f].dur = ms end
  else
    D.frames[S.frame].dur = ms
  end
end

-- Tags
function cmd.addTag()
  local D = S.D
  local a, b = S.frame, S.frame
  if S.rangeA and S.rangeB then a, b = math.min(S.rangeA, S.rangeB), math.max(S.rangeA, S.rangeB) end
  local names = { "idle", "walk", "run", "attack", "hurt", "death", "jump", "fall" }
  local name = names[#D.tags + 1] or ("tag " .. (#D.tags + 1))
  D.tags[#D.tags + 1] = { name = name, from = a, to = b }
  S.tag = #D.tags
  A.commit()
  A.openModal("rename", { what = "tag", target = D.tags[#D.tags] })
end

function cmd.deleteTag()
  if not S.tag or not S.D.tags[S.tag] then A.msg("Select a tag first (click its bar)", true) return end
  table.remove(S.D.tags, S.tag)
  S.tag = nil
  A.commit()
end

-- Layers
function cmd.addLayer(kind)
  A.dropFloat()
  local D = S.D
  local L = doc.addLayer(D, nil, kind, S.layer + 1)
  if kind == "part" then
    L.name = "Part " .. L.id
    if S.bone then L.bone = S.bone; L.name = rig.bone(D, S.bone).name end
  end
  S.layer = S.layer + 1
  A.commit()
end

function cmd.dupLayer()
  A.dropFloat()
  local D, L = S.D, A.layerObj()
  if not L then return end
  local N = doc.addLayer(D, L.name .. " copy", L.kind, S.layer + 1)
  N.opacity, N.bone, N.ox, N.oy = L.opacity, L.bone, L.ox, L.oy
  for f = 1, #D.frames do N.cels[f] = L.cels[f] and doc.copyCel(L.cels[f]) or false end
  if L.part then N.part = doc.copyCel(L.part) end
  S.layer = S.layer + 1
  A.commit()
end

function cmd.deleteLayer()
  A.dropFloat()
  local D = S.D
  if #D.layers <= 1 then A.msg("Keep at least one layer", true) return end
  table.remove(D.layers, S.layer)
  S.layer = U.clamp(S.layer, 1, #D.layers)
  A.commit()
end

function cmd.moveLayer(dir)
  A.dropFloat()
  local D, i = S.D, S.layer
  local j = i + dir
  if j < 1 or j > #D.layers then return end
  D.layers[i], D.layers[j] = D.layers[j], D.layers[i]
  S.layer = j
  A.commit()
end

-- Merges the current layer into the one below it, frame by frame (as they look now)
function cmd.mergeDown()
  A.dropFloat()
  local D, i = S.D, S.layer
  local top, below = D.layers[i], D.layers[i - 1]
  if not below then A.msg("No layer below to merge into", true) return end
  if top.kind == "ref" or below.kind == "ref" then A.msg("Reference layers can't be merged", true) return end
  if below.bone then A.msg("The layer below is bound to a bone: bake the rig instead", true) return end
  local only = { [top.id] = true, [below.id] = true }
  local cels = {}
  local tv, bv = top.visible, below.visible
  top.visible, below.visible = true, true
  for f = 1, #D.frames do
    cels[f] = doc.newCel(nil, nil, render.frameData(D, f, S.work, { only = only, rest = false }))
  end
  below.kind, below.part, below.cels = "frames", nil, cels
  below.visible = bv or tv
  table.remove(D.layers, i)
  S.layer = i - 1
  A.commit()
end

-- Frame layer <-> puppet part
function cmd.toggleKind()
  A.dropFloat()
  local D, L = S.D, A.layerObj()
  if not L or L.kind == "ref" then return end
  if L.kind == "frames" then
    local c = L.cels[S.frame]
    L.part = c and doc.copyCel(c) or doc.newCel(D.w, D.h)
    for f = 1, #D.frames do L.cels[f] = false end
    L.kind = "part"
    A.msg("Now a part: the same image on every frame (from frame " .. S.frame .. ")")
  else
    for f = 1, #D.frames do L.cels[f] = doc.copyCel(L.part) end
    L.part = nil
    L.kind = "frames"
    A.msg("Now a frame layer: the part was copied into every frame")
  end
  A.commit()
end

function cmd.bindBone()
  local L = A.layerObj()
  if not L or L.kind == "ref" then return end
  if not S.bone then A.msg("Select a bone first (Rig tab or the Pose tool)", true) return end
  L.bone = S.bone
  A.commit()
end

function cmd.unbind()
  local L = A.layerObj()
  if not L or not L.bone then return end
  L.bone = nil
  A.commit()
end

-- Selection and clipboard
function cmd.selectAll()
  A.dropFloat()
  S.sel = { x = 0, y = 0, w = S.D.w, h = S.D.h }
end

function cmd.deselect()
  A.dropFloat()
  S.sel = nil
end

function cmd.copy(cut)
  local F = S.float
  if F then
    S.clip = { data = F.data:clone(), x = F.x, y = F.y }
    if cut then
      F.img:release()
      S.float = nil
      A.commit()
    end
    return
  end
  local L = A.layerObj()
  local cel = L and L.kind ~= "ref" and doc.cel(S.D, L, S.frame)
  if not cel then A.msg("Nothing to copy here", true) return end
  local cw, ch = cel.data:getDimensions()
  local r = S.sel and clipRect(S.sel, cw, ch) or { x = 0, y = 0, w = cw, h = ch }
  if r.w <= 0 or r.h <= 0 then return end
  local data = love.image.newImageData(r.w, r.h)
  data:paste(cel.data, 0, 0, r.x, r.y, r.w, r.h)
  S.clip = { data = data, x = r.x, y = r.y }
  if cut then
    if L.locked then A.msg("Layer is locked", true) return end
    fx.clear(cel.data, r)
    doc.touch(cel)
    A.commit()
  end
  A.msg(cut and "Cut" or "Copied")
end

function cmd.paste()
  if not S.clip then A.msg("Clipboard is empty", true) return end
  A.dropFloat()
  local L = A.editableLayer()
  if not L or L.kind == "ref" then return end
  local C = S.clip
  newFloat(L, C.data:clone(), C.x, C.y, true)
  S.sel = { x = C.x, y = C.y, w = S.float.w, h = S.float.h }
  S.tool = "move"
  A.msg("Pasted: drag it with the Move tool, Enter to place")
end

function cmd.delete()
  if S.float then
    S.float.img:release()
    S.float = nil
    A.commit()
    return
  end
  local L = A.editableLayer()
  if not L or L.kind == "ref" then return end
  local cel = doc.cel(S.D, L, S.frame)
  if not cel then return end
  fx.clear(cel.data, S.sel)
  doc.touch(cel)
  A.commit()
end

function cmd.nudge(dx, dy)
  if not S.float and not A.lift() then return end
  S.float.x, S.float.y = S.float.x + dx, S.float.y + dy
  S.float.changed = true
  if S.sel then S.sel.x, S.sel.y = S.float.x, S.float.y end
end

-- Effects
local FX = {
  flipH = function(d, r) fx.flipH(d, r) end,
  flipV = function(d, r) fx.flipV(d, r) end,
  rotCW = function(d, r) fx.rotate(d, r, 1) end,
  rotCCW = function(d, r) fx.rotate(d, r, -1) end,
  outline = function(d, r) fx.outline(d, r, S.primary, false) end,
  outline8 = function(d, r) fx.outline(d, r, S.primary, true) end,
  inline = function(d, r) fx.inline(d, r, S.primary) end,
  shadow = function(d, r) fx.shadow(d, r, S.primary, 1, 1) end,
  lighter = function(d, r) fx.hsv(d, r, 0, 0, 0.06) end,
  darker = function(d, r) fx.hsv(d, r, 0, 0, -0.06) end,
  hueUp = function(d, r) fx.hsv(d, r, 1 / 24, 0, 0) end,
  hueDown = function(d, r) fx.hsv(d, r, -1 / 24, 0, 0) end,
  satUp = function(d, r) fx.hsv(d, r, 0, 0.1, 0) end,
  satDown = function(d, r) fx.hsv(d, r, 0, -0.1, 0) end,
  invert = function(d, r) fx.invert(d, r) end,
  gray = function(d, r) fx.gray(d, r) end,
  snap = function(d, r) fx.snap(d, r, S.D.palette) end,
  replace = function(d, r) fx.replace(d, r, S.primary, S.secondary) end,
  shiftL = function(d, r) fx.shift(d, r, -1, 0) end,
  shiftR = function(d, r) fx.shift(d, r, 1, 0) end,
  shiftU = function(d, r) fx.shift(d, r, 0, -1) end,
  shiftD = function(d, r) fx.shift(d, r, 0, 1) end,
  despeckle = function(d, r) fx.despeckle(d, r) end,
  clear = function(d, r) fx.clear(d, r) end,
}

local function fxTargets()
  local D, L = S.D, A.layerObj()
  local out = {}
  if S.fxScope == "frame" then
    for _, M in ipairs(D.layers) do
      if M.kind ~= "ref" and not M.locked and M.visible then
        local c = doc.cel(D, M, S.frame)
        if c then out[#out + 1] = c end
      end
    end
    return out
  end
  if not L or L.kind == "ref" then return out end
  if L.locked then A.msg("Layer is locked", true) return out end
  if S.fxScope == "layer" then
    if L.kind == "part" then
      out[1] = L.part
    else
      for f = 1, #D.frames do
        if L.cels[f] then out[#out + 1] = L.cels[f] end
      end
    end
  else
    local c = doc.cel(D, L, S.frame)
    if c then out[1] = c end
  end
  return out
end

function cmd.fx(id)
  A.dropFloat()
  local list = fxTargets()
  if #list == 0 then A.msg("Nothing to apply that to on this frame", true) return end
  for _, c in ipairs(list) do
    FX[id](c.data, S.sel)
    doc.touch(c)
  end
  A.commit()
end

-- Rig
function cmd.deleteBone()
  if not S.bone then return end
  rig.remove(S.D, S.bone)
  S.bone = nil
  A.commit()
end

function cmd.keyAll()
  local D, f = S.D, S.frame
  for _, B in ipairs(D.bones) do
    local r, x, y = rig.key(B, f)
    rig.setKey(B, f, r, x, y)
  end
  A.commit()
end

function cmd.clearKey(all)
  local D, f = S.D, S.frame
  for _, B in ipairs(D.bones) do
    if all or B.id == S.bone then B.keys[f] = false end
  end
  A.commit()
end

function cmd.toggleEase()
  local B = S.bone and rig.bone(S.D, S.bone)
  local k = B and B.keys[S.frame]
  if not k then A.msg("The selected bone has no key on this frame", true) return end
  k.ease = not k.ease or nil
  A.commit()
end

function cmd.copyPose()
  S.poseClip = {}
  for _, B in ipairs(S.D.bones) do
    local r, x, y = rig.key(B, S.frame)
    S.poseClip[B.id] = { r, x, y }
  end
  A.msg("Pose copied")
end

function cmd.pastePose(mirror)
  if not S.poseClip then A.msg("Copy a pose first", true) return end
  for _, B in ipairs(S.D.bones) do
    local k = S.poseClip[B.id]
    if k then rig.setKey(B, S.frame, k[1], k[2], k[3]) end
  end
  A.commit()
end

function cmd.resetPose()
  for _, B in ipairs(S.D.bones) do
    if not S.bone or B.id == S.bone then rig.setKey(B, S.frame, 0, 0, 0) end
  end
  A.commit()
end

-- Flattens everything visible into a new frame layer so the animation can be cleaned up by hand
function cmd.bake()
  A.dropFloat()
  local D = S.D
  local only, n = {}, 0
  for _, L in ipairs(D.layers) do
    if L.visible and L.kind ~= "ref" then only[L.id] = true n = n + 1 end
  end
  if n == 0 then return end
  local N = doc.addLayer(D, "baked", "frames")
  for f = 1, #D.frames do
    N.cels[f] = doc.newCel(nil, nil, render.frameData(D, f, S.work, { only = only }))
  end
  for _, L in ipairs(D.layers) do
    if only[L.id] then L.visible = false end
  end
  S.layer = #D.layers
  A.commit()
  A.msg("Baked " .. #D.frames .. " frames into \"baked\" (the puppet layers are hidden, not gone)")
end

function cmd.template(kind)
  A.dropFloat()
  if presets.applyRig(S.D, kind) then
    S.layer = #S.D.layers
    A.commit()
    A.msg("Added a " .. kind .. " rig: draw each part on its layer, then pose it")
  end
end

-- Canvas size
function cmd.resize(w, h, ax, ay)
  A.dropFloat()
  doc.resize(S.D, w, h, ax, ay)
  S.sel = nil
  A.ensureCanvases()
  A.fit()
  A.commit()
end

-- Files
function cmd.save(name)
  A.dropFloat()
  name = name or S.path
  if not name then A.openModal("saveas") return end
  local ok, res = fileio.save(S.D, name)
  if ok then
    S.path = name
    S.D.name = name
    S.savedVersion = history.version
    A.msg("Saved " .. res)
  else
    A.msg("Save failed: " .. tostring(res), true)
  end
  A.updateTitle()
end

function cmd.open(name)
  local D, err = fileio.load(name)
  if not D then A.msg("Couldn't open " .. name .. ": " .. tostring(err), true) return end
  A.setDoc(D, name ~= "_autosave" and name or nil)
  A.msg("Opened projects/" .. name .. ".gspr")
end

function cmd.export(o)
  A.dropFloat()
  local files, err = fileio.export(S.D, o)
  if not files then A.msg("Export failed: " .. tostring(err), true) return end
  A.msg("Exported " .. table.concat(files, ", "))
  S.lastExport = files
end

-- Imports a dropped PNG in one of several ways
function cmd.import(how, data)
  local D = S.D
  local iw, ih = data:getDimensions()
  if how == "doc" then
    local N = doc.new(iw, ih, { name = "imported", palette = D.palette })
    N.layers[1].cels[1] = doc.newCel(nil, nil, data)
    A.setDoc(N, nil)
    return
  end
  A.dropFloat()
  if how == "ref" then
    local L = doc.addLayer(D, "reference", "ref", 1)
    doc.setData(L.part, data)
    L.ox, L.oy = math.floor((D.w - iw) / 2), D.h - ih
    S.layer = 1
  elseif how == "layer" then
    local L = doc.addLayer(D, "imported", "frames", S.layer + 1)
    local c = doc.newCel(D.w, D.h)
    c.data:paste(data, 0, 0, 0, 0, iw, ih)
    L.cels[S.frame] = c
    S.layer = S.layer + 1
  elseif how == "frames" then
    local cols, rows = math.floor(iw / D.w), math.floor(ih / D.h)
    if cols * rows == 0 then A.msg("The image is smaller than one frame", true) return end
    local L = doc.addLayer(D, "imported", "frames", S.layer + 1)
    local n = 0
    for r = 0, rows - 1 do
      for c = 0, cols - 1 do
        n = n + 1
        if n > #D.frames then doc.insertFrame(D, #D.frames + 1, false) end
        local cel = doc.newCel(D.w, D.h)
        cel.data:paste(data, 0, 0, c * D.w, r * D.h, D.w, D.h)
        L.cels[n] = cel
      end
    end
    S.layer = S.layer + 1
    A.msg("Imported " .. n .. " frames")
  end
  A.commit()
end

-- Callbacks ------------------------------------------------------------------------------------------

local panels, timeline, dialogs

function A.load()
  panels = require("src.panels")
  timeline = require("src.timeline")
  dialogs = require("src.dialogs")
  A.dialogs = dialogs
  love.keyboard.setKeyRepeat(true)
  ui.init()
  local checker = love.image.newImageData(2, 2)
  checker:mapPixel(function(x, y)
    local v = (x + y) % 2 == 0 and 0.30 or 0.24
    return v, v, v, 1
  end)
  S.checker = lg.newImage(checker)
  S.checker:setFilter("nearest", "nearest")
  S.checker:setWrap("repeat", "repeat")
  S.palettes = presets.palettes
  A.setPrimary({ 0.64, 0.63, 0.62, 1 })
  S.secondary = { 0, 0, 0, 0 }
  S.tool, S.size, S.mode = "pencil", 1, "normal"
  S.lockAlpha, S.pixelPerfect, S.mirrorX, S.mirrorY = false, true, false, false
  S.fillShapes, S.fillGlobal = false, false
  S.showGrid, S.showGuide, S.onion, S.onionN = true, true, false, 1
  S.showBones, S.restPose, S.ik, S.autoPart = true, false, true, true
  S.preview, S.loop = true, true
  S.tab, S.fxScope = "layers", "cel"
  S.msg, S.msgT = "", 0
  S.autosaveT, S.autosavedVersion = 0, -1
  A.layout()
  A.setDoc(presets.newDoc(presets.byKey("hunter"), 32, 32, "none", presets.palettes[1].colors), nil)
  A.openModal("new")
end

function A.openModal(kind, args)
  A.dropFloat()
  S.drag = nil
  S.modal = dialogs.open(A, kind, args)
end

function A.closeModal()
  S.modal = nil
  ui.focus = nil
end

-- Asks before throwing away unsaved work
function A.confirmDiscard(fn)
  if not A.isDirty() then fn() return end
  A.openModal("confirm", { text = "Discard the unsaved changes to this sprite?", yes = "Discard", fn = fn })
end

function A.update(dt)
  A.layout()
  local D = S.D
  if S.msgT > 0 then S.msgT = S.msgT - dt end
  if S.playing then
    S.playT = S.playT + dt * 1000
    local guard = 0
    while S.playT >= D.frames[S.frame].dur and guard < 100 do
      S.playT = S.playT - D.frames[S.frame].dur
      local n = nextFrame(S.frame)
      if n < S.frame and not S.loop then
        S.playing = false
        break
      end
      S.frame = n
      guard = guard + 1
    end
  end
  -- The preview loops on its own over the range around the current frame
  S.pvFrame = U.clamp(S.pvFrame or 1, 1, #D.frames)
  local a, b = A.playRange(S.frame)
  if S.pvFrame < a or S.pvFrame > b then S.pvFrame, S.pvT = a, 0 end
  S.pvT = S.pvT + dt * 1000
  local guard = 0
  while S.pvT >= D.frames[S.pvFrame].dur and guard < 100 do
    S.pvT = S.pvT - D.frames[S.pvFrame].dur
    S.pvFrame = S.pvFrame >= b and a or S.pvFrame + 1
    guard = guard + 1
  end
  -- Autosave once a minute while there are unsaved changes
  S.autosaveT = S.autosaveT + dt
  if S.autosaveT > 60 then
    S.autosaveT = 0
    if A.isDirty() and S.autosavedVersion ~= history.version and not S.float then
      if fileio.save(D, "_autosave") then S.autosavedVersion = history.version end
    end
  end
end

-- Drawing --------------------------------------------------------------------------------------------

local function dashedRect(x, y, w, h)
  lg.setLineWidth(1)
  lg.setColor(0, 0, 0, 0.9)
  lg.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1)
  lg.setColor(1, 1, 1, 0.95)
  local seg, off = 4, (love.timer.getTime() * 12) % 8
  local function edge(x1, y1, x2, y2)
    local len = math.max(math.abs(x2 - x1), math.abs(y2 - y1))
    local dx, dy = (x2 - x1) / math.max(1, len), (y2 - y1) / math.max(1, len)
    local t = -off
    while t < len do
      local a, b = math.max(0, t), math.min(len, t + seg)
      if b > a then lg.line(x1 + dx * a, y1 + dy * a, x1 + dx * b, y1 + dy * b) end
      t = t + seg * 2
    end
  end
  local x2, y2 = x + w - 0.5, y + h - 0.5
  edge(x + 0.5, y + 0.5, x2, y + 0.5)
  edge(x2, y + 0.5, x2, y2)
  edge(x2, y2, x + 0.5, y2)
  edge(x + 0.5, y2, x + 0.5, y + 0.5)
end

local function drawComp(canvas, x, y, z, r, g, b, a)
  lg.setBlendMode("alpha", "premultiplied")
  a = a or 1
  lg.setColor((r or 1) * a, (g or 1) * a, (b or 1) * a, a)
  lg.draw(canvas, x, y, 0, z, z)
  lg.setBlendMode("alpha", "alphamultiply")
end

local function drawBones(P, x0, y0, z)
  local D = S.D
  local active = S.tool == "bone" or S.tool == "pose"
  if not active and not S.showBones then return end
  local alpha = active and 1 or 0.45
  lg.setLineWidth(1)
  for _, B in ipairs(D.bones) do
    local p = P[B.id]
    local hx, hy, tx, ty = x0 + p.hx * z, y0 + p.hy * z, x0 + p.tx * z, y0 + p.ty * z
    local dx, dy = tx - hx, ty - hy
    local len = math.max(1, math.sqrt(dx * dx + dy * dy))
    local nx, ny = -dy / len, dx / len
    local wdt = math.min(len * 0.18, math.max(3, z * 0.6))
    local mx, my = hx + dx * 0.2, hy + dy * 0.2
    local sel = B.id == S.bone
    local keyed = B.keys[S.frame] and not A.isRest()
    local c = sel and T.sel or (keyed and { 1.0, 0.55, 0.35 } or { 0.55, 0.85, 1.0 })
    local poly = { hx, hy, mx + nx * wdt, my + ny * wdt, tx, ty, mx - nx * wdt, my - ny * wdt }
    lg.setColor(c[1], c[2], c[3], 0.28 * alpha)
    lg.polygon("fill", poly)
    lg.setColor(0, 0, 0, 0.6 * alpha)
    lg.setLineWidth(3)
    lg.polygon("line", poly)
    lg.setLineWidth(1)
    lg.setColor(c[1], c[2], c[3], alpha)
    lg.polygon("line", poly)
    lg.circle("fill", hx, hy, math.max(2, math.min(5, z * 0.35)))
    lg.circle("line", tx, ty, math.max(2, math.min(4, z * 0.3)))
    if B.parent and P[B.parent] then
      local pp = P[B.parent]
      local px_, py_ = x0 + pp.tx * z, y0 + pp.ty * z
      if math.abs(px_ - hx) + math.abs(py_ - hy) > 1 then
        lg.setColor(c[1], c[2], c[3], 0.35 * alpha)
        lg.line(px_, py_, hx, hy)
      end
    end
  end
  if S.bone then
    for _, B in ipairs(D.bones) do
      if B.id == S.bone then
        local p = P[B.id]
        ui.text(B.name, x0 + p.tx * z + 6, y0 + p.ty * z - 6, T.sel, ui.small)
      end
    end
  end
end

function A.drawCanvas()
  local C, D = S.L.canvas, S.D
  local z, x0, y0 = S.zoom, S.panX, S.panY
  local w, h = D.w * z, D.h * z
  ui.rect(T.bg, C.x, C.y, C.w, C.h)
  lg.setScissor(C.x, C.y, C.w, C.h)
  -- checkerboard
  local cs = 8
  lg.setColor(1, 1, 1)
  local q = lg.newQuad(0, 0, w / cs, h / cs, 2, 2)
  lg.draw(S.checker, q, x0, y0, 0, cs, cs)
  q:release()
  -- onion skin: earlier frames red, later frames blue
  if S.onion and not S.playing then
    for k = S.onionN, 1, -1 do
      local fade = 0.38 / k
      if S.frame - k >= 1 then drawComp(S.onionC[2 * k - 1], x0, y0, z, 1, 0.35, 0.35, fade) end
      if S.frame + k <= #D.frames then drawComp(S.onionC[2 * k], x0, y0, z, 0.35, 0.6, 1, fade) end
    end
  end
  drawComp(S.comp, x0, y0, z)
  -- grid
  if S.showGrid and z >= 6 then
    lg.setLineWidth(1)
    for i = 0, D.w do
      lg.setColor(1, 1, 1, i % 8 == 0 and 0.16 or 0.06)
      lg.line(x0 + i * z + 0.5, y0, x0 + i * z + 0.5, y0 + h)
    end
    for j = 0, D.h do
      lg.setColor(1, 1, 1, j % 8 == 0 and 0.16 or 0.06)
      lg.line(x0, y0 + j * z + 0.5, x0 + w, y0 + j * z + 0.5)
    end
  end
  lg.setColor(T.line)
  lg.rectangle("line", x0 - 0.5, y0 - 0.5, w + 1, h + 1)
  -- hitbox guide from the game
  local g = D.guide
  if S.showGuide and g then
    if g.w > 0 then
      local gx, gy = g.fx - math.floor(g.w / 2), g.fy - g.h
      lg.setColor(0.3, 0.9, 1.0, 0.7)
      lg.rectangle("line", x0 + gx * z + 0.5, y0 + gy * z + 0.5, g.w * z - 1, g.h * z - 1)
    end
    if g.ground then
      lg.setColor(1, 0.6, 0.25, 0.7)
      lg.line(x0, y0 + g.fy * z + 0.5, x0 + w, y0 + g.fy * z + 0.5)
    end
    lg.setColor(0.3, 0.9, 1.0, 0.35)
    lg.line(x0 + (g.fx + 0.5) * z, y0 + g.fy * z - 3, x0 + (g.fx + 0.5) * z, y0 + g.fy * z + 3)
  end
  if S.mirrorX then
    lg.setColor(1, 0.4, 0.8, 0.5)
    lg.line(x0 + w / 2, y0, x0 + w / 2, y0 + h)
  end
  if S.mirrorY then
    lg.setColor(1, 0.4, 0.8, 0.5)
    lg.line(x0, y0 + h / 2, x0 + w, y0 + h / 2)
  end
  -- selection
  if S.sel then
    dashedRect(x0 + S.sel.x * z, y0 + S.sel.y * z, S.sel.w * z, S.sel.h * z)
  elseif S.float then
    local F = S.float
    dashedRect(x0 + F.x * z, y0 + F.y * z, F.w * z, F.h * z)
  end
  -- bones
  if #D.bones > 0 then drawBones(S.pose, x0, y0, z) end
  local d = S.drag
  if d and d.kind == "newBone" then
    lg.setColor(T.sel)
    lg.setLineWidth(2)
    lg.line(x0 + d.x0 * z, y0 + d.y0 * z, x0 + d.x1 * z, y0 + d.y1 * z)
    lg.setLineWidth(1)
    lg.circle("fill", x0 + d.x0 * z, y0 + d.y0 * z, 3)
  end
  -- shape preview
  if d and d.kind == "shape" then
    local c = d.button == 2 and S.secondary or S.primary
    lg.setColor(c[1], c[2], c[3], math.max(0.35, c[4]))
    local o = -math.floor((S.size - 1) / 2)
    for _, p in ipairs(A.shapePoints(d)) do
      lg.rectangle("fill", x0 + (p[1] + o) * z, y0 + (p[2] + o) * z, S.size * z, S.size * z)
    end
  end
  -- brush cursor
  local mx, my = love.mouse.getPosition()
  if not S.modal and A.inCanvas(mx, my) and (PAINT[S.tool] and S.tool ~= "fill") and S.hoverX then
    local o = -math.floor((S.size - 1) / 2)
    local bx, by = x0 + (S.hoverX + o) * z, y0 + (S.hoverY + o) * z
    lg.setColor(0, 0, 0, 0.7)
    lg.rectangle("line", bx - 0.5, by - 0.5, S.size * z + 1, S.size * z + 1)
    lg.setColor(1, 1, 1, 0.8)
    lg.rectangle("line", bx + 0.5, by + 0.5, S.size * z - 1, S.size * z - 1)
  end
  -- labels
  ui.text(string.format("%dx%d  zoom %dx", D.w, D.h, z), C.x + 8, C.y + 6, T.dim, ui.small)
  if A.isRest() and #D.bones > 0 then ui.text("REST POSE", C.x + 8, C.y + 20, T.sel, ui.small) end
  if S.playing then ui.text("PLAYING", C.x + 8, C.y + 34, T.accent, ui.small) end
  lg.setScissor()
  -- live preview at game scale
  if S.preview then
    local px, py, pw, ph, s = A.previewRect()
    local bx, by, bw, bh = A.previewBox()
    ui.rect({ 0.05, 0.05, 0.06 }, bx, by, bw, bh)
    ui.rect({ 0.23, 0.19, 0.20 }, px, py, pw, ph)
    drawComp(S.pvC, px, py, s)
    ui.text("preview " .. s .. "x   frame " .. S.pvFrame, bx + 4, by + 3, T.dim, ui.small)
  end
end

function A.drawStatus()
  local R, D = S.L.status, S.D
  ui.rect(T.panel, R.x, R.y, R.w, R.h)
  ui.rect(T.line, R.x, R.y, R.w, 1)
  local parts = {}
  if S.hoverX and S.hoverX >= 0 and S.hoverY >= 0 and S.hoverX < D.w and S.hoverY < D.h then
    parts[#parts + 1] = string.format("x %d  y %d", S.hoverX, S.hoverY)
  end
  parts[#parts + 1] = string.format("frame %d/%d  %dms", S.frame, #D.frames, D.frames[S.frame].dur)
  local L = A.layerObj()
  if L then parts[#parts + 1] = "layer: " .. L.name end
  if S.bone then
    local B = rig.bone(D, S.bone)
    if B then parts[#parts + 1] = "bone: " .. B.name end
  end
  ui.text(table.concat(parts, "     "), R.x + 8, R.y + 4, T.dim)
  if S.msgT > 0 then
    local w = ui.font:getWidth(S.msg)
    ui.text(S.msg, R.x + R.w - w - 10, R.y + 4, S.msgWarn and T.warn or T.accent)
  end
end

function A.draw()
  ui.begin()
  A.layout()
  local D = S.D
  -- compose everything shown this frame before any scissoring
  local rest = A.isRest()
  S.pose = render.compose(D, S.frame, S.comp, { rest = rest, float = S.float })
  if S.onion and not S.playing then
    for k = 1, S.onionN do
      if S.frame - k >= 1 then render.compose(D, S.frame - k, S.onionC[2 * k - 1], { rest = rest, skipRef = true }) end
      if S.frame + k <= #D.frames then render.compose(D, S.frame + k, S.onionC[2 * k], { rest = rest, skipRef = true }) end
    end
  end
  if S.preview then render.compose(D, S.pvFrame, S.pvC, { skipRef = true }) end
  lg.clear(T.bg)
  A.drawCanvas()
  ui.blocked = S.modal ~= nil
  -- a click on the preview plays/stops
  if S.preview then
    local px, py, pw, ph = A.previewRect()
    if ui.clicked(A.previewBox()) then cmd.togglePlay() end
    if ui.hit(px, py, pw, ph) then ui.tip = "Live preview at game scale. Click to play / stop the canvas" end
  end
  panels.drawLeft(A, S.L.left)
  panels.drawRight(A, S.L.right)
  timeline.draw(A, S.L.tl)
  panels.drawTop(A, S.L.top)
  A.drawStatus()
  ui.blocked = false
  if S.modal then dialogs.draw(A, S.modal) end
  ui.drawTip()
  ui.finish()
end

-- Input ----------------------------------------------------------------------------------------------

function A.mousepressed(x, y, b)
  if S.modal then ui.press(b) return end
  if A.inCanvas(x, y) and not A.overPreview(x, y) then
    ui.focus = nil
    A.canvasPress(x, y, b)
  else
    ui.press(b)
  end
end

function A.mousereleased(x, y, b)
  A.canvasRelease(x, y, b)
end

function A.mousemoved(x, y)
  A.canvasMove(x, y)
end

function A.wheelmoved(dx, dy)
  local mx, my = love.mouse.getPosition()
  if not S.modal and A.inCanvas(mx, my) and not A.overPreview(mx, my) then
    if dy ~= 0 then A.zoomStep(dy > 0 and 1 or -1) end
  else
    ui.wheel = ui.wheel + dy
  end
end

function A.textinput(t)
  if ui.focus then ui.textinput(t) end
end

local TOOL_KEYS = {}
for _, t in ipairs(A.TOOLS) do TOOL_KEYS[t.key] = t.id end

function A.keypressed(k)
  if ui.focus then ui.key(k) return end
  if S.modal then
    ui.key(k)
    if k == "escape" then A.closeModal() end
    return
  end
  if S.drag and k ~= "escape" then return end
  local ctrl, shift = ctrlDown(), shiftDown()
  if ctrl then
    if k == "z" then if shift then cmd.redo() else cmd.undo() end
    elseif k == "y" then cmd.redo()
    elseif k == "s" then if shift or not S.path then A.openModal("saveas") else cmd.save() end
    elseif k == "o" then A.confirmDiscard(function() A.openModal("open") end)
    elseif k == "n" then A.confirmDiscard(function() A.openModal("new") end)
    elseif k == "e" then A.openModal("export")
    elseif k == "c" then cmd.copy(false)
    elseif k == "x" then cmd.copy(true)
    elseif k == "v" then cmd.paste()
    elseif k == "a" then cmd.selectAll()
    elseif k == "d" then cmd.deselect()
    elseif k == "0" then A.fit()
    end
    return
  end
  if TOOL_KEYS[k] then A.setTool(TOOL_KEYS[k]) return end
  if k == "x" then
    local p = S.primary
    A.setPrimary(S.secondary)
    S.secondary = p
  elseif k == "[" then S.size = math.max(1, S.size - 1)
  elseif k == "]" then S.size = math.min(8, S.size + 1)
  elseif k == "return" or k == "kpenter" then
    if S.float then A.dropFloat() else cmd.togglePlay() end
  elseif k == "," then A.setFrame(S.frame - 1)
  elseif k == "." then A.setFrame(S.frame + 1)
  elseif k == "home" then A.setFrame(1)
  elseif k == "end" then A.setFrame(#S.D.frames)
  elseif k == "left" or k == "right" or k == "up" or k == "down" then
    local dx = (k == "left" and -1) or (k == "right" and 1) or 0
    local dy = (k == "up" and -1) or (k == "down" and 1) or 0
    if S.tool == "move" or S.sel or S.float then
      cmd.nudge(dx * (shift and 4 or 1), dy * (shift and 4 or 1))
    elseif dx ~= 0 then
      A.setFrame(S.frame + dx)
    else
      A.setLayer(S.layer - dy)
    end
  elseif k == "delete" or k == "backspace" then cmd.delete()
  elseif k == "escape" then
    if S.drag then
      S.drag = nil
      A.replaceDoc(history.revert())
    elseif S.float then A.cancelFloat()
    else S.sel = nil end
  elseif k == "f" then cmd.addFrame(shift)
  elseif k == "n" then S.onion = not S.onion
  elseif k == "h" then S.showGuide = not S.showGuide
  elseif k == "'" then S.showGrid = not S.showGrid
  elseif k == "r" then S.restPose = not S.restPose
  elseif k == "=" or k == "kp+" then A.zoomStep(1)
  elseif k == "-" or k == "kp-" then A.zoomStep(-1)
  end
end

function A.filedropped(file)
  local name = file:getFilename()
  local ok, res = pcall(function()
    file:open("r")
    local s = file:read()
    file:close()
    return s
  end)
  if not ok or not res then A.msg("Couldn't read " .. name, true) return end
  if name:lower():match("%.gspr$") then
    local t = U.deserialize(res)
    local ok2, D = pcall(doc.fromTable, t, true)
    if t and ok2 then
      A.confirmDiscard(function() A.setDoc(D, nil) end)
    else
      A.msg("Not a sprite project", true)
    end
    return
  end
  local ok3, data = pcall(love.image.newImageData, love.filesystem.newFileData(res, name))
  if not ok3 then A.msg("Only PNG images and .gspr projects can be dropped", true) return end
  A.openModal("import", { data = data, name = name:match("([^/\\]+)$") })
end

function A.resize()
  A.layout()
end

function A.quit()
  if A.isDirty() and not S.quitting then
    A.openModal("confirm", {
      text = "Quit without saving?", yes = "Quit",
      fn = function() S.quitting = true love.event.quit() end,
    })
    return true
  end
  return false
end

return A
