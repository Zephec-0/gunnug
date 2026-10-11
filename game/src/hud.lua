-- Screen-space HUD: health bar and gun status (chambers + reload), Noita-style
-- in the top-right corner.
local hud = {}

local fonts = {}

local function font(size)
  if not fonts[size] then
    fonts[size] = love.graphics.newFont(size)
  end
  return fonts[size]
end

function hud.font(scale)
  return font(math.max(10, math.floor(scale * 4)))
end

local function shadowText(text, x, y, f)
  love.graphics.setFont(f)
  local r, g, b, a = love.graphics.getColor()
  love.graphics.setColor(0, 0, 0, a)
  love.graphics.print(text, x + 2, y + 2)
  love.graphics.setColor(r, g, b, a)
  love.graphics.print(text, x, y)
end

function hud.draw(player, scale)
  local ww = love.graphics.getWidth()
  local u = scale -- one game pixel at the current scale
  local f = hud.font(scale)
  local margin = 6 * u

  -- Health bar
  local barW, barH = 40 * u, 4 * u
  local x, y = ww - margin - barW, margin
  love.graphics.setColor(0.1, 0.05, 0.08, 0.8)
  love.graphics.rectangle("fill", x - u, y - u, barW + 2 * u, barH + 2 * u)
  love.graphics.setColor(0.86, 0.16, 0.24)
  love.graphics.rectangle("fill", x, y, barW * player.hp / player.maxHp, barH)
  love.graphics.setColor(1, 1, 1)
  local hpText = tostring(math.floor(player.hp))
  shadowText(hpText, x - f:getWidth(hpText) - 4 * u, y + barH / 2 - f:getHeight() / 2, f)

  if player.gun then
    hud.drawGunStatus(player.gun, ww, margin, y + barH, u, f)
  end

  -- Controls hint
  love.graphics.setColor(1, 1, 1, 0.6)
  local small = font(math.max(10, math.floor(scale * 3)))
  shadowText(
    "A/D move   W/Space jump   Ctrl crouch/slide   LMB shoot (aim down mid-air to recoil jump)   RMB reload   F kick   Tab weapons   1-3 switch   "
      .. "R restart   F9 test room   F10 new cave   F2 physics   F3 stats",
    margin,
    love.graphics.getHeight() - margin - small:getHeight(),
    small
  )

  hud.drawBanner(scale)
end

-- Chambers (filled = loaded, hollow = spent), name and reload bar of the held
-- gun, right-aligned below the health bar
function hud.drawGunStatus(gun, ww, margin, top, u, f)
  local r = 2 * u
  local gap = 2 * u
  local count = gun.def.chambers
  local cy = top + 8 * u
  local rowW
  if count <= 12 then
    rowW = count * 2 * r + (count - 1) * gap
    local cx0 = ww - margin - rowW + r
    for i = 1, count do
      local cx = cx0 + (i - 1) * (2 * r + gap)
      if i <= gun.chambers then
        love.graphics.setColor(1, 0.8, 0.3)
        love.graphics.circle("fill", cx, cy, r)
      else
        love.graphics.setColor(0.5, 0.45, 0.4)
        love.graphics.setLineWidth(math.max(1, u / 2))
        love.graphics.circle("line", cx, cy, r - u / 4)
      end
    end
  else
    -- Big magazines: a row of thin cartridge ticks instead of chambers
    local tickW, tickGap = u, u
    rowW = count * tickW + (count - 1) * tickGap
    local x0 = ww - margin - rowW
    for i = 1, count do
      if i <= gun.chambers then
        love.graphics.setColor(1, 0.8, 0.3)
      else
        love.graphics.setColor(0.5, 0.45, 0.4, 0.6)
      end
      love.graphics.rectangle("fill", x0 + (i - 1) * (tickW + tickGap), cy - r, tickW, 2 * r)
    end
  end
  love.graphics.setColor(1, 1, 1)
  shadowText(gun.def.name, ww - margin - rowW - f:getWidth(gun.def.name) - 4 * u, cy - f:getHeight() / 2, f)

  -- Reload bar
  if gun:isReloading() then
    local ry = cy + r + 3 * u
    love.graphics.setColor(0.1, 0.05, 0.08, 0.8)
    love.graphics.rectangle("fill", ww - margin - rowW, ry, rowW, u * 1.5)
    love.graphics.setColor(0.4, 0.85, 1)
    love.graphics.rectangle("fill", ww - margin - rowW, ry, rowW * gun:reloadProgress(), u * 1.5)
  end
end

-- Area title card, e.g. when entering a new area
local banner = { time = 0 }
local BANNER_TIME = 3.5

function hud.showBanner(title, subtitle)
  banner = { title = title, subtitle = subtitle, time = BANNER_TIME }
end

function hud.update(dt)
  banner.time = math.max(0, banner.time - dt)
end

function hud.drawBanner(scale)
  if banner.time <= 0 then
    return
  end
  local elapsed = BANNER_TIME - banner.time
  local alpha = math.min(1, elapsed / 0.4, banner.time / 0.8)
  local ww, wh = love.graphics.getDimensions()
  local big = font(math.max(16, math.floor(scale * 9)))
  local f = font(math.max(10, math.floor(scale * 4)))
  local y = math.floor(wh * 0.22)
  love.graphics.setColor(1, 0.86, 0.45, alpha)
  shadowText(banner.title, math.floor((ww - big:getWidth(banner.title)) / 2), y, big)
  if banner.subtitle then
    love.graphics.setColor(1, 1, 1, alpha * 0.85)
    shadowText(banner.subtitle, math.floor((ww - f:getWidth(banner.subtitle)) / 2), y + big:getHeight() + 2 * scale, f)
  end
end

function hud.drawCrosshair(vx, vy)
  local x, y = math.floor(vx), math.floor(vy)
  love.graphics.setColor(0, 0, 0, 0.5)
  love.graphics.rectangle("fill", x - 5, y + 1, 3, 1)
  love.graphics.rectangle("fill", x + 3, y + 1, 3, 1)
  love.graphics.rectangle("fill", x + 1, y - 5, 1, 3)
  love.graphics.rectangle("fill", x + 1, y + 3, 1, 3)
  love.graphics.setColor(1, 1, 1, 0.9)
  love.graphics.rectangle("fill", x - 5, y, 3, 1)
  love.graphics.rectangle("fill", x + 3, y, 3, 1)
  love.graphics.rectangle("fill", x, y - 5, 1, 3)
  love.graphics.rectangle("fill", x, y + 3, 1, 3)
end

return hud
