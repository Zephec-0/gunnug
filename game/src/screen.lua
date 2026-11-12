-- The picture's size. The interface is laid out for 1920x1080 (three window pixels to the game pixel) and the
-- whole sizes above it (2560x1440...): its lettering and pixel art only come in whole sizes, so at any other size
-- the text and the boxes it sits in stop fitting each other. So at any other size the whole frame (world and
-- interface) is drawn for the next of those sizes up into a canvas, and that is scaled down to the window: every
-- window shows the same layout.
-- The rest of the game never knows: love.graphics.getDimensions and love.mouse.getPosition answer in the canvas's
-- pixels, and love.graphics.setCanvas() goes back to the canvas. At a whole size nothing is changed at all.
local config = require("src.config")

local screen = {}

local BASE_W, BASE_H = config.VIRTUAL_W, config.VIRTUAL_H
local realDimensions = love.graphics.getDimensions
local realSetCanvas = love.graphics.setCanvas
local realGetCanvas = love.graphics.getCanvas
local realMouse = love.mouse.getPosition

local vw, vh -- the picture's size while it is scaled (nil: it is the window)
local kx, ky = 1, 1 -- picture pixels per window pixel
local frame -- the canvas the picture is drawn into
local target -- (with a stencil: the menus cut shapes out with one)
local drawing = false

screen.force = nil -- (tests) a whole size to lay out for, whatever the window
screen.brightness = 1 -- the player's brightness setting (src.settings): 1 leaves the picture as drawn

-- Brightness is a curve put over the finished frame (world and interface): above 1 it lifts the dark and middle
-- tones, below 1 it sinks them, and black and white stay where they are, so nothing burns out or goes grey
local BRIGHTEN = [[
uniform float amount;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec3 c = Texel(tex, uv).rgb;
  return vec4(pow(max(c, vec3(0.0)), vec3(1.0 / amount)), 1.0);
}
]]
local brightShader, brightTried
local grab -- the canvas the frame goes into when only the brightness needs one (it is the window's size)

local function brightening()
  if math.abs((screen.brightness or 1) - 1) < 0.005 then
    return false
  end
  if not brightTried then
    brightTried = true
    local ok, sh = pcall(love.graphics.newShader, BRIGHTEN)
    brightShader = ok and sh or nil
  end
  return brightShader ~= nil
end

-- Works out the size to draw at; called before every layout (render.layout)
function screen.layout()
  local ww, wh = realDimensions()
  local base = math.min(ww / BASE_W, wh / BASE_H)
  local whole = math.floor(base + 0.5)
  if math.abs(base - whole) > 0.03 then
    whole = math.ceil(base)
  end
  whole = screen.force or math.max(3, whole)
  local k = whole / base
  if math.abs(k - 1) <= 0.03 then
    vw, vh, kx, ky = nil, nil, 1, 1
    if frame and frame ~= grab then
      frame:release()
    end
    frame, target = nil, nil
    return
  end
  local nw, nh = math.floor(ww * k + 0.5), math.floor(wh * k + 0.5)
  if nw ~= vw or nh ~= vh or not frame or frame == grab then
    vw, vh = nw, nh
    if frame and frame ~= grab then
      frame:release()
    end
    frame = love.graphics.newCanvas(vw, vh)
    frame:setFilter("linear", "linear")
    target = { frame, stencil = true }
  end
  kx, ky = vw / ww, vh / wh
end

function screen.scaled()
  return vw ~= nil
end

-- Window pixels -> picture pixels (mouse events)
function screen.fromWindow(x, y)
  return x * kx, y * ky
end

function love.graphics.getDimensions()
  if vw then
    return vw, vh
  end
  return realDimensions()
end

function love.graphics.getWidth()
  return (love.graphics.getDimensions())
end

function love.graphics.getHeight()
  local _, h = love.graphics.getDimensions()
  return h
end

function love.mouse.getPosition()
  local x, y = realMouse()
  return x * kx, y * ky
end

function love.mouse.getX()
  return (love.mouse.getPosition())
end

function love.mouse.getY()
  local _, y = love.mouse.getPosition()
  return y
end

function love.graphics.setCanvas(a, ...)
  if drawing and a == nil then
    return realSetCanvas(target)
  end
  return realSetCanvas(a, ...)
end

-- (code that asks "am I drawing to the window?" must hear yes while the picture's canvas is the target)
function love.graphics.getCanvas()
  local c = realGetCanvas()
  if drawing and c == frame then
    return nil
  end
  return c
end

-- Around the drawing of one frame
function screen.begin()
  if not vw and brightening() then
    -- (the curve reads the finished picture, so the frame goes into a canvas the window's size)
    local ww, wh = realDimensions()
    if not grab or grab:getWidth() ~= ww or grab:getHeight() ~= wh then
      if grab then
        grab:release()
      end
      grab = love.graphics.newCanvas(ww, wh)
    end
    frame, target = grab, { grab, stencil = true }
  end
  if frame then
    drawing = true
    realSetCanvas(target)
    love.graphics.clear(0, 0, 0, 1)
  end
end

function screen.finish()
  if not drawing then
    return
  end
  drawing = false
  realSetCanvas()
  local ww, wh = realDimensions()
  love.graphics.push("all")
  love.graphics.origin()
  love.graphics.setShader()
  love.graphics.setScissor()
  love.graphics.setBlendMode("replace")
  love.graphics.setColor(1, 1, 1, 1)
  if brightening() then
    brightShader:send("amount", screen.brightness)
    love.graphics.setShader(brightShader)
  end
  love.graphics.draw(frame, 0, 0, 0, ww / frame:getWidth(), wh / frame:getHeight())
  love.graphics.pop()
  if frame == grab then
    frame, target = nil, nil
  end
end

return screen
