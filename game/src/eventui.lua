-- The random events' own pages (src.randevents opens them through src.menu's dialog, which hands the
-- page over: dialog.custom(H, dialog) draws all of it and places its buttons through H.button):
--   highlow   the gambler's card table: green felt under a lamp, cards flying in and stacking up
--   tinker    the travelling tinker's bench: the weapon cards on show, a re-roll button, a shaken card
--   shrine    the shrine of the fallen: three cards, each an offering
-- Everything pictured is pixel art at the size it has in the world (one game pixel is H.gp on screen).
local audio = require("src.audio")
local eventart = require("src.eventart")
local gunInfo = require("src.gunInfo")
local guns = require("src.guns")
local inventory = require("src.inventory")
local itembar = require("src.itembar")
local pickups = require("src.pickups")

local eventui = {}

local gfx = love.graphics
local floor, min, max, sin, cos, sqrt, abs = math.floor, math.min, math.max, math.sin, math.cos, math.sqrt, math.abs

local function open(dlg)
  require("src.menu").openDialog(dlg)
end

local function clickEdge(dlg)
  local down = love.mouse.isDown(1)
  local edge = down and not dlg.wasDown
  dlg.wasDown = down
  return edge
end

local function inside(mx, my, x, y, w, h)
  return mx >= x and mx < x + w and my >= y and my < y + h
end

local function easeOut(k)
  k = max(0, min(1, k))
  return 1 - (1 - k) ^ 3
end

-- High-Low -----------------------------------------------------------------------------------------

local BET = 10
local MARGIN, CAP = 1.12, 8 -- what a right guess multiplies the pot by: MARGIN / chance, up to CAP
local FLY = 0.55 -- seconds a dealt card takes to come down
local WIN_STREAK = 6

local function mult(p)
  return min(CAP, MARGIN / max(0.05, p))
end

local function chance(card, higher)
  return higher and (13 - card) / 13 or (card - 1) / 13
end

-- (the table is a panel of 520 x 300 game pixels, its lamp hanging over the middle)
local FELT_W, FELT_H = 520, 300
local LAMP = { 218, 138 }
local PILE = { 196, 150 } -- where the cards land (the middle of the top card)

function eventui.highlow(o, player, env)
  local hl = o.hl
  if not hl then
    hl = { card = nil, suit = 0, pot = 0, streak = 0, msg = "Deal a card.", pile = {}, anim = nil }
    o.hl = hl
  end
  local inv = player.inventory
  local dlg = { title = "High-Low", music = "table" }

  local function land()
    local a = hl.anim
    hl.anim = nil
    hl.pile[#hl.pile + 1] = { card = a.card, suit = a.suit, dx = a.dx, dy = a.dy, rot = a.rot }
    if #hl.pile > 7 then
      table.remove(hl.pile, 1)
    end
    audio.play("card_slap")
    if a.kind == "deal" then
      hl.card, hl.suit = a.card, a.suit
      hl.msg = "Higher or lower?"
      return
    end
    local old = hl.card
    local R = eventart.RANKS
    if a.won then
      hl.pot = floor(hl.pot * mult(chance(old, a.higher)) + 0.5)
      hl.streak = hl.streak + 1
      hl.msg = R[old] .. " then " .. R[a.card] .. ": right!"
      hl.card, hl.suit = a.card, a.suit
      audio.play("coin")
      if hl.streak >= WIN_STREAK then
        hl.msg = "Six in a row! The house pays up."
        inv.gold = inv.gold + hl.pot
        env.dropCoins(o.x, o.y - 30, 0)
        audio.play("slot_jackpot")
        hl.pot, hl.card, hl.streak = 0, nil, 0
      end
    else
      hl.msg = R[old] .. " then " .. R[a.card] .. ": the house wins."
      hl.pot, hl.card, hl.streak = 0, nil, 0
      audio.play("slot_lose")
    end
  end

  -- A card comes down from the top of the screen onto the pile
  local function fly(card, suit, extra)
    -- (each card lands a little off: shifted and turned, never square on the one below)
    local turn = (0.05 + love.math.random() * 0.2) * (love.math.random() < 0.5 and -1 or 1)
    local a = { card = card, suit = suit, t0 = love.timer.getTime(), dx = floor((love.math.random() - 0.5) * 14), dy = floor((love.math.random() - 0.5) * 10), rot = turn }
    for k, v in pairs(extra or {}) do
      a[k] = v
    end
    hl.anim = a
    audio.play("card_deal")
  end

  local function deal()
    inv.gold = inv.gold - BET
    hl.pot, hl.streak = BET, 0
    audio.play("slot_coin")
    fly(love.math.random(1, 13), love.math.random(0, 3), { kind = "deal" })
  end

  local function guess(higher)
    local old = hl.card
    local nxt, suit = love.math.random(1, 13), love.math.random(0, 3)
    local won = (higher and nxt > old) or (not higher and nxt < old)
    hl.msg = "..."
    fly(nxt, suit, { kind = "guess", higher = higher, won = won })
  end

  dlg.custom = function(H)
    local ww, wh = gfx.getDimensions()
    local S = H.gp
    local ox, oy = floor((ww - FELT_W * S) / 2), floor((wh - FELT_H * S) / 2)
    local function sx(x) return ox + floor(x * S) end
    local function sy(y) return oy + floor(y * S) end
    local now = love.timer.getTime()
    if hl.anim and now - hl.anim.t0 >= FLY then
      land()
    end
    -- the table pops out of the dimmed page, with a shadow under it
    gfx.setColor(0, 0, 0, 0.5)
    gfx.rectangle("fill", ox + 4 * S, oy + 5 * S, FELT_W * S, FELT_H * S)
    gfx.setColor(1, 1, 1)
    gfx.draw(eventart.felt(FELT_W, FELT_H), ox, oy, 0, S, S)
    H.pageTitle("High-Low", sx(36), sy(26))
    local small, body = H.F.small, H.F.body
    -- the rules, and the purse
    H.wrapped("A card is dealt. Guess whether the next is higher or lower; a tie loses, an ace is low and a king high. Every right guess multiplies the pot.", sx(36), sy(48), floor(116 * S), small, { 0.82, 0.92, 0.82 })
    H.shadowPrint("Gold: " .. inv.gold, sx(36), sy(158), body, { 1, 0.85, 0.3 })
    if hl.pot > 0 then
      H.shadowPrint("Pot: " .. hl.pot, sx(36), sy(158) + body:getHeight() * 1.3, body, { 1, 0.92, 0.5 })
      H.shadowPrint("In a row: " .. hl.streak .. " / " .. WIN_STREAK, sx(36), sy(158) + body:getHeight() * 2.6, small, { 0.85, 0.95, 0.85 })
    end

    -- the cards: shadows fall away from the lamp, and the older ones sit darker beneath
    local function shadowOf(gx, gy, lift)
      local dx = (gx - LAMP[1]) * 0.05 + 2
      local dy = (gy - LAMP[2]) * 0.05 + 3
      return dx * (1 + lift * 5), dy * (1 + lift * 5)
    end
    local function drawCard(img, gx, gy, lift, dim, scale, rot)
      local cw, ch = eventart.CARD_W, eventart.CARD_H
      scale, rot = scale or 1, rot or 0
      local shx, shy = shadowOf(gx, gy, lift)
      gfx.push()
      gfx.translate(sx(gx + shx), sy(gy + shy))
      gfx.rotate(rot)
      gfx.setColor(0, 0, 0, 0.40 - 0.18 * lift)
      gfx.rectangle("fill", -floor(cw * scale * S / 2), -floor(ch * scale * S / 2), floor(cw * scale * S), floor(ch * scale * S))
      gfx.pop()
      gfx.setColor(dim, dim, dim * 0.97, 1)
      gfx.draw(img, sx(gx), sy(gy), rot, S * scale, S * scale, cw / 2, ch / 2)
    end
    if #hl.pile == 0 and not hl.anim then
      drawCard(eventart.cardBack(), PILE[1], PILE[2], 0, 1)
    end
    for i, c in ipairs(hl.pile) do
      local depth = #hl.pile - i
      drawCard(eventart.card(c.card, c.suit), PILE[1] + c.dx, PILE[2] + c.dy, 0, max(0.55, 1 - depth * 0.1), 1, c.rot)
    end
    if hl.anim then
      local a = hl.anim
      local k = (now - a.t0) / FLY
      local e = easeOut(k)
      local lx, ly = PILE[1] + a.dx, PILE[2] + a.dy
      local gx = lx + (1 - e) * 60
      local top = -oy / S - 50 -- (above the top of the screen)
      local gy = top + (ly - top) * e
      local lift = 1 - e
      -- (coming from above it is face up, looks bigger and spins as it comes)
      drawCard(eventart.card(a.card, a.suit), gx, gy, lift, 1, 1 + 0.18 * lift, a.rot + (1 - e) * 1.2)
    end
    -- the message under the pile
    H.printCentered(hl.msg, sx(PILE[1]), sy(PILE[2] + 46), body, { 1, 1, 0.85 })

    -- the choices, to the right of the cards
    local bx, bw = sx(284), floor(190 * S)
    local busy = hl.anim ~= nil
    local by = sy(78)
    local function place(h, gap)
      local y = by
      by = by + floor((h + gap) * S)
      return y, floor(h * S)
    end
    if not hl.card then
      local y, h = place(36, 8)
      H.button("dlg:hl:deal", "Deal a card", bx, y, bw, h, function() deal() return true end,
        { disabled = busy or inv.gold < BET, sub = inv.gold < BET and "Not enough gold" or ("Bet " .. BET .. " gold") })
    else
      local ph, pl = chance(hl.card, true), chance(hl.card, false)
      for _, d in ipairs({ { true, ph, "Higher", "up" }, { false, pl, "Lower", "down" } }) do
        local higher, p = d[1], d[2]
        local y, h = place(36, 8)
        H.button("dlg:hl:" .. d[3], d[3], bx, y, bw, h, function() guess(higher) return true end, {
          disabled = busy or p <= 0,
          sub = p > 0 and string.format("%d%% chance, the pot x%.1f", p * 100 + 0.5, mult(p)) or "Impossible",
        })
        -- (the arrow, in the button's left end)
        gfx.setColor(higher and { 0.55, 1, 0.65 } or { 1, 0.6, 0.55 })
        gfx.draw(eventart.arrow(d[4]), bx + floor(8 * S), y + floor((h - 11 * S) / 2), 0, S, S)
      end
      local y, h = place(24, 8)
      H.button("dlg:hl:cash", "Cash out (" .. hl.pot .. ")", bx, y, bw, h, function()
        inv.gold = inv.gold + hl.pot
        hl.msg = "You walk away with " .. hl.pot .. "."
        env.dropCoins(o.x, o.y - 30, 0)
        audio.play("slot_win")
        hl.pot, hl.card, hl.streak = 0, nil, 0
        return true
      end, { disabled = busy or hl.streak < 1, sub = hl.streak < 1 and "Win a guess first" or nil })
    end
    local y, h = place(24, 0)
    H.button("dlg:hl:leave", "Leave table", bx, y, bw, h, function() return false end, { disabled = busy or hl.card ~= nil, sub = hl.card and "Cash out first" or nil })
  end
  open(dlg)
end

-- The tinker -----------------------------------------------------------------------------------------

local FLIP = 0.45

-- The weapon becomes another of its kind: new bonuses and a new number of slots. Whatever is fitted stays
-- in its slot, but a gun that comes out with fewer slots drops what no longer fits, on the ground.
local function reforge(gun, player, env)
  local fresh = guns.generate(gun.id, nil, 0)
  gun.rolls, gun.name = fresh.rolls, fresh.name
  gun.statsSignature = nil
  local old = gun.slotCount
  gun.slotCount = fresh.slotCount
  local px, py = player:center()
  local dropped = 0
  for i = gun.slotCount + 1, old do
    local item = gun.slots[i]
    if item then
      gun.slots[i] = nil
      dropped = dropped + 1
      pickups.dropItem(px + (dropped - 1.5) * 8, py - 10, item, (dropped % 2 == 0 and 1 or -1) * (30 + dropped * 12), -90)
    end
  end
  gun.chambers = gun:maxChambers()
  if dropped > 0 then
    env.popup(px, py - 26, "Popped loose: " .. dropped .. (dropped == 1 and " item" or " items"), { 1, 0.7, 0.4 })
  end
end

function eventui.tinker(o, player, env)
  local inv = player.inventory
  local dlg = { title = "The Travelling Tinker" }
  local tk = { flip = nil, flash = 0 }
  -- (the price climbs with each gun's own re-rolls, not with the tinker's)
  local function price(gun)
    return 35 + 30 * ((gun and gun.tinkerRolls) or 0)
  end

  dlg.custom = function(H)
    local ww, wh = gfx.getDimensions()
    local u, S = H.u, H.gp
    local now = love.timer.getTime()
    H.pageTitle("The Travelling Tinker", H.X(14), H.Y(9))
    H.shadowPrint("\"Every gun has a better self in it. Let me shake it loose.\"", H.X(14), H.Y(26), H.F.small, { 0.95, 0.75, 0.45 })

    -- the carried weapons, as cards, scaled down so they all sit on the screen together
    local carried = {}
    for i = 1, inventory.weaponSlots() do
      if inv.weapons[i] then
        carried[#carried + 1] = i
      end
    end
    local C = itembar.CARD
    local cu = min(u * 0.78, (wh * 0.6) / C.h, (ww * 0.92) / (max(1, #carried) * (C.w + C.gap * 3)))
    local cw, ch, gap = C.w * cu, C.h * cu, C.gap * 3 * cu
    local total = #carried * cw + max(0, #carried - 1) * gap
    local x0 = floor((ww - total) / 2)
    local y0 = floor(H.Y(40) + 2 * u)
    -- (the flip turns the card edge-on, and the new weapon is what turns back)
    if tk.flip and not tk.flip.swapped and now - tk.flip.t0 >= FLIP / 2 then
      local gun = inv.weapons[tk.flip.idx]
      if gun then
        reforge(gun, player, env)
        env.sparkle(o.x, o.y - 10, { 1, 0.8, 0.4 })
        audio.play("buy")
      end
      tk.flip.swapped = true
    end
    if tk.flip and now - tk.flip.t0 >= FLIP then
      tk.flash, tk.flashIdx, tk.flip = now, tk.flip.idx, nil
    end
    for n, i in ipairs(carried) do
      local gun = inv.weapons[i]
      local cost = price(gun)
      local cx = x0 + (n - 1) * (cw + gap)
      local flipping = tk.flip and tk.flip.idx == i
      local sxs, lift = 1, 0
      if flipping then
        local k = (now - tk.flip.t0) / FLIP
        sxs = max(0.02, abs(cos(k * math.pi)))
        lift = -sin(k * math.pi) * 6 * cu
      end
      gfx.push()
      gfx.translate(cx + cw / 2, y0 + ch / 2 + lift)
      gfx.scale(sxs, 1)
      gfx.translate(-cw / 2, -ch / 2)
      itembar.drawGunCard(inv, gun, 0, 0, cu, { index = i, selected = true, static = true, border = { 0.9, 0.75, 0.4 } })
      if tk.flash > 0 and tk.flashIdx == i and now - tk.flash < 0.5 then
        gfx.setColor(1, 0.9, 0.5, 0.45 * (1 - (now - tk.flash) / 0.5))
        gfx.rectangle("fill", 0, 0, cw, ch)
      end
      gfx.pop()
      -- under each card: its own re-roll button, an icon and the price beside it
      local bh = floor(14 * u)
      local by = y0 + ch + 5 * u
      local can = gun.rolls and inv.gold >= cost and not tk.flip
      H.button("dlg:tk:roll" .. i, "", floor(cx), floor(by), floor(cw), bh, function()
        inv.gold = inv.gold - cost
        gun.tinkerRolls = (gun.tinkerRolls or 0) + 1
        tk.flip = { t0 = love.timer.getTime(), idx = i }
        audio.play("tinker_shake")
        return true
      end, { disabled = not can })
      local label = tostring(cost)
      local fw = H.F.body:getWidth(label)
      local iw = 15 * S
      local sx0 = cx + (cw - (iw + 3 * S + fw)) / 2
      gfx.setColor(can and { 1, 0.9, 0.55 } or { 0.5, 0.48, 0.5 })
      gfx.draw(eventart.reroll(), floor(sx0), floor(by + (bh - iw) / 2), 0, S, S)
      H.shadowPrint(label, floor(sx0 + iw + 3 * S), floor(by + (bh - H.F.body:getHeight()) / 2), H.F.body, can and { 1, 0.95, 0.7 } or { 0.55, 0.5, 0.5 })
    end
    local bw = floor(80 * u)
    H.button("dlg:tk:done", "Done", floor((ww - bw) / 2), floor(y0 + ch + 5 * u + 14 * u + 4 * u), bw, floor(13 * u), function() return false end, { disabled = tk.flip ~= nil })
  end
  open(dlg)
end

-- The shrine -----------------------------------------------------------------------------------------

-- offers: a list of { title, text, cost (a line), icon, color, disabled (a reason or nil), fn }
-- Click a card (or press its number) to take the offer; Esc walks away.
function eventui.shrine(o, player, offers, opts)
  opts = opts or {}
  local dlg = { title = opts.title or "Shrine of the Fallen" }
  dlg.custom = function(H)
    local ww, wh = gfx.getDimensions()
    local S, u = H.gp, H.u
    local now = love.timer.getTime()
    H.pageTitle(opts.title or "Shrine of the Fallen", H.X(14), H.Y(9))
    H.shadowPrint(opts.subtitle or "Names scratched into the stone, and a pale flame that never gutters. The shrine takes one thing and gives another.", H.X(14), H.Y(26), H.F.small, opts.subtitleColor or { 0.7, 0.6, 1 })
    local cw, ch = floor(84 * S), floor((opts.cardH or 120) * S)
    local gap = floor(14 * S)
    local n = #offers
    local x0 = floor((ww - (n * cw + (n - 1) * gap)) / 2)
    local y0 = floor((wh - ch) / 2) - floor(4 * u) -- (in the middle of the screen)
    local edge = clickEdge(dlg)
    local mx, my = love.mouse.getPosition()
    local chosen
    local rr = floor(3 * S) -- the corners are rounded
    for i, of in ipairs(offers) do
      local x = x0 + (i - 1) * (cw + gap)
      local hover = inside(mx, my, x, y0, cw, ch) and not of.disabled
      local lift = hover and -floor(3 * S) or 0
      local c = of.color
      -- the card: a dark face with a coloured rim, lit from above
      gfx.setColor(0, 0, 0, 0.45)
      gfx.rectangle("fill", x + floor(3 * S), y0 + lift + floor(4 * S), cw, ch, rr, rr)
      gfx.setColor(c[1] * 0.35, c[2] * 0.35, c[3] * 0.35, 1)
      gfx.rectangle("fill", x, y0 + lift, cw, ch, rr, rr)
      gfx.setColor(0.07, 0.06, 0.11, 1)
      gfx.rectangle("fill", x + S, y0 + lift + S, cw - 2 * S, ch - 2 * S, max(1, rr - S), max(1, rr - S))
      local k = of.disabled and 0.35 or (hover and 1 or 0.8)
      gfx.setColor(c[1] * k, c[2] * k, c[3] * k, 1)
      gfx.rectangle("fill", x + 6 * S, y0 + lift + 3 * S, cw - 12 * S, S)
      -- the picture, in a halo
      gfx.setColor(1, 1, 1, of.disabled and 0.35 or 1)
      local img = eventart.icon(of.icon)
      local bob = of.disabled and 0 or floor(sin(now * 2 + i) * 0.9 + 0.5)
      gfx.draw(img, x + floor((cw - 24 * S) / 2), y0 + lift + floor((10 + bob) * S), 0, S, S)
      -- its words
      H.printCentered(of.title, x + cw / 2, y0 + lift + floor(40 * S), H.F.body, of.disabled and { 0.5, 0.5, 0.55 } or { 1, 0.97, 0.9 })
      H.wrapped(of.text, x + floor(6 * S), y0 + lift + floor(40 * S) + H.F.body:getHeight() * 1.5, cw - floor(12 * S), H.F.small, of.disabled and { 0.4, 0.4, 0.44 } or { 0.82, 0.8, 0.86 })
      -- the cost, a block set into the foot of the card
      local bh = floor(15 * S)
      local by = y0 + lift + ch - bh - floor(4 * S)
      if of.disabled then
        gfx.setColor(0.35, 0.1, 0.1, 1)
      else
        local m = hover and 0.8 or 0.55
        gfx.setColor(c[1] * m, c[2] * m, c[3] * m, 1)
      end
      gfx.rectangle("fill", x + floor(4 * S), by, cw - floor(8 * S), bh, rr, rr)
      H.printCentered(of.disabled or of.cost, x + cw / 2, by + (bh - H.F.body:getHeight()) / 2, H.F.body, of.disabled and { 1, 0.6, 0.6 } or { 1, 1, 1 })
      if (edge and hover) or (not of.disabled and love.keyboard.isDown(tostring(i)) and not dlg.keyHeld) then
        chosen = of
      end
    end
    dlg.keyHeld = love.keyboard.isDown("1") or love.keyboard.isDown("2") or love.keyboard.isDown("3")
    H.printCentered("Click a card to take it     Esc: walk away", ww / 2, y0 + ch + 10 * u, H.F.small, { 0.65, 0.6, 0.8 })
    if chosen then
      chosen.fn()
      H.close()
    end
  end
  open(dlg)
end

return eventui
