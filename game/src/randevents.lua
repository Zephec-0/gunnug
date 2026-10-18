-- Random events: encounters that turn up in the dungeon on a timer, one at a
-- time, near the hunter (src.events calls into this):
--   carnival   a carny's shooting gallery: pick a speed, shoot the moving targets
--   gambler    a gambler's den: a slot machine and a game of high-low
--   tinker     a travelling tinker who re-rolls the bonuses on a weapon
--   shrine     a shrine of the fallen: pay for a blessing, or gamble on one
--   cavein     a miner buried under a cave-in: dig him out before time runs out
--   hunt       a marked beast: kill it before the clock runs out
-- Conversation and games happen in src.menu's generic dialog page.
local audio = require("src.audio")
local effects = require("src.effects")
local enemies = require("src.enemies")
local fluids = require("src.fluids")
local gunInfo = require("src.gunInfo")
local guns = require("src.guns")
local input = require("src.input")
local items = require("src.items")
local materials = require("src.materials")
local meta = require("src.meta")
local perks = require("src.perks")
local pickups = require("src.pickups")
local targets = require("src.targets")

local randevents = {}

local active -- the one event on now: { kind, x, y (ground), age, life, ... }
local timer = 60
local lastKind
local world

local KINDS = { "carnival", "gambler", "tinker", "shrine", "cavein", "hunt" }

function randevents.clear()
  active = nil
  world = nil
  timer = 45 + love.math.random() * 70
  lastKind = nil
end

-- Helpers ---------------------------------------------------------------------

local function R(c, x, y, w, h, a)
  love.graphics.setColor(c[1], c[2], c[3], (c[4] or 1) * (a or 1))
  love.graphics.rectangle("fill", x, y, w, h)
end

local function dist(o, px, py, dy)
  local dx, ddy = o.x - px, o.y + (dy or -10) - py
  return math.sqrt(dx * dx + ddy * ddy)
end

local function gold(player)
  return player.inventory.gold
end

local function say(o, text)
  o.say = { text = text, age = 0 }
end

-- An item of one of the given rarities (a set like { rare = true }) that the
-- profile may find
local function randomItem(set)
  local pool = {}
  for _, id in ipairs(items.order) do
    local d = items.defs[id]
    if set[d.rarity] and (not items.isAvailable or items.isAvailable(id)) then
      pool[#pool + 1] = id
    end
  end
  if #pool == 0 then
    return items.random()
  end
  return items.new(pool[love.math.random(#pool)])
end

local function dropReward(x, y, goldAmount, item)
  if goldAmount and goldAmount > 0 then
    pickups.dropGold(x, y - 10, goldAmount)
  end
  if item then
    pickups.dropItem(x, y - 14, item, (love.math.random() - 0.5) * 40, -70)
  end
end

-- Open, flat ground with air above, near the hunter but not on top of him
local function findSpot(px, py, flatHalf, minD, maxD)
  for _ = 1, 80 do
    local x = math.floor(px + (love.math.random() < 0.5 and -1 or 1) * (minD + love.math.random() * (maxD - minD)))
    local gy = world:findGround(x, math.floor(py - 40))
    if gy and math.abs(gy - py) < 70 and not world:isSolid(x, gy - 4) then
      local ok = not fluids.waterAt(x, gy - 4)
      for dx = -flatHalf, flatHalf, 4 do
        local g2 = world:findGround(x + dx, gy - 10)
        if not g2 or math.abs(g2 - gy) > 4 then
          ok = false
          break
        end
        for k = 6, 30, 6 do
          if world:isSolid(x + dx, gy - k) then
            ok = false
          end
        end
      end
      if ok then
        return x, gy
      end
    end
  end
  -- Cramped caves rarely have a flat room: cut a nook into ordinary rock beside
  -- the hunter (never into anything unbreakable), a flat floor and head-room
  for _ = 1, 60 do
    local x = math.floor(px + (love.math.random() < 0.5 and -1 or 1) * (minD * 0.6 + love.math.random() * (maxD - minD)))
    local gy = world:findGround(x, math.floor(py - 40))
    if gy and math.abs(gy - py) < 60 and not fluids.waterAt(x, gy - 4) then
      local hw = flatHalf + 6
      local ok = true
      for yy = gy - 40, gy + 4, 4 do
        for xx = x - hw, x + hw, 4 do
          local id = world:get(xx, yy)
          if materials.defs[id] and materials.defs[id].hardness == math.huge and materials.defs[id].solid then
            ok = false
          end
        end
      end
      if ok then
        world:fillRect(x - hw, gy - 40, x + hw, gy - 1, materials.AIR)
        world:fillRect(x - hw, gy, x + hw, gy + 3, materials.DIRT)
        world:repaintRegion(x - hw - 3, gy - 43, x + hw + 3, gy + 7)
        require("src.physics").rebuildRegion(x - hw - 3, gy - 43, x + hw + 3, gy + 7)
        return x, gy
      end
    end
  end
  return nil
end

-- The dialog's buttons -------------------------------------------------------

local function openDialog(dlg)
  require("src.menu").openDialog(dlg)
end

local function popup(x, y, text, color)
  effects.popup(x, y, text, color or { 1, 0.9, 0.5 })
end

local function sparkle(x, y, color)
  for _ = 1, 18 do
    effects.particle(x + (love.math.random() - 0.5) * 12, y - 8, (love.math.random() - 0.5) * 80, -30 - love.math.random() * 60, 0.7, color or { 1, 0.85, 0.4 }, -20, true)
  end
end

-- Carnival -------------------------------------------------------------------

local DIFFICULTIES = {
  { name = "Easy", cost = 10, speed = 34, mult = 1 },
  { name = "Medium", cost = 25, speed = 68, mult = 1.8 },
  { name = "Hard", cost = 50, speed = 112, mult = 3 },
}
local CARNIVAL_TIME = 25

local function drawCarnivalTarget(t)
  if t.hidden then
    return
  end
  local cx, cy = t.x + 5, t.y + 5
  local white = t.flash > 0
  local function ring(r, c)
    love.graphics.setColor(white and 1 or c[1], white and 1 or c[2], white and 1 or c[3])
    love.graphics.circle("fill", cx, cy, r)
  end
  ring(6, { 0.20, 0.05, 0.07 })
  ring(5.2, { 0.85, 0.65, 0.15 })
  ring(3.8, { 0.80, 0.12, 0.14 })
  ring(2.4, { 0.92, 0.88, 0.75 })
  ring(1.1, { 0.80, 0.12, 0.14 })
end

local function startCarnival(o, diff, player)
  o.state = "playing"
  o.diff = diff
  o.hits = 0
  o.timeLeft = CARNIVAL_TIME
  o.targets = {}
  local lanes = { 22, 38, 54 }
  for i, h in ipairs(lanes) do
    local t = {
      x = o.x - 50 + (i - 1) * 40,
      y = o.y - h,
      w = 10,
      h = 10,
      dir = i % 2 == 0 and -1 or 1,
      hiddenT = 0,
      lane = i,
    }
    t.update = function(self, dt)
      if self.hiddenT > 0 then
        self.hiddenT = self.hiddenT - dt
        if self.hiddenT <= 0 then
          self.hidden = false
        end
        return
      end
      self.x = self.x + self.dir * diff.speed * dt * (1 + (self.lane - 2) * 0.15)
      if self.x < o.x - 62 then
        self.x, self.dir = o.x - 62, 1
      elseif self.x > o.x + 52 then
        self.x, self.dir = o.x + 52, -1
      end
    end
    t.draw = drawCarnivalTarget
    t.onHit = function(self, amount)
      if o.state ~= "playing" or self.hidden then
        return
      end
      self.flash = 0.1
      self.hidden = true
      self.hiddenT = 0.8
      o.hits = o.hits + 1
      audio.play("select")
      popup(self.x + 5, self.y - 4, "+1", { 1, 0.85, 0.3 })
    end
    o.targets[#o.targets + 1] = targets.addCustom(t)
  end
  say(o, "Ready... shoot!")
end

local function finishCarnival(o, player)
  for _, t in ipairs(o.targets or {}) do
    targets.remove(t)
  end
  o.targets = nil
  o.state = "done"
  o.life = 12
  local m = o.diff.mult
  local hits = o.hits
  local g, item
  if hits >= 15 then
    g = math.floor(60 * m)
    item = randomItem(o.diff.mult >= 3 and { rare = true, epic = true } or { rare = true })
    say(o, "Marksman! Take the grand prize!")
  elseif hits >= 10 then
    g = math.floor(30 * m)
    item = randomItem(o.diff.mult >= 1.8 and { rare = true } or { common = true })
    say(o, "Fine shooting! Have a prize.")
  elseif hits >= 5 then
    g = math.floor(15 * m)
    say(o, "Not bad. A little something.")
  else
    say(o, "Better luck next time, friend.")
  end
  popup(o.x, o.y - 40, hits .. " hits", { 1, 0.9, 0.5 })
  if g then
    dropReward(o.x, o.y, g, item)
    audio.play("buy")
    sparkle(o.x, o.y - 10)
  end
end

local function carnivalDialog(o, player)
  local dlg = { title = "The Shooting Gallery", subtitle = "Hit the moving targets in " .. CARNIVAL_TIME .. " seconds. Pick how fast they move.", subtitleColor = { 0.95, 0.75, 0.45 } }
  dlg.lines = {
    "Five hits wins a little something, ten a prize, fifteen the grand prize. Faster targets pay out more.",
  }
  dlg.buttons = {}
  for _, d in ipairs(DIFFICULTIES) do
    dlg.buttons[#dlg.buttons + 1] = {
      label = d.name .. " (" .. d.cost .. " gold)",
      sub = "Targets move at " .. d.speed .. " px/s, rewards x" .. d.mult,
      disabled = gold(player) < d.cost,
      fn = function()
        player.inventory.gold = player.inventory.gold - d.cost
        audio.play("buy")
        startCarnival(o, d, player)
      end,
    }
  end
  dlg.buttons[#dlg.buttons + 1] = { label = "Walk away" }
  openDialog(dlg)
end

-- Gambler's den ----------------------------------------------------------------

local SYMBOLS = {
  { name = "Cherry", w = 30, pay = 5, color = { 0.9, 0.15, 0.2 } },
  { name = "Lemon", w = 25, pay = 8, color = { 0.95, 0.9, 0.25 } },
  { name = "Bell", w = 20, pay = 12, color = { 0.95, 0.75, 0.25 } },
  { name = "Star", w = 15, pay = 20, color = { 0.55, 0.8, 1 } },
  { name = "Seven", w = 7, pay = 50, color = { 1, 0.4, 0.2 } },
  { name = "Diamond", w = 3, pay = 100, color = { 0.6, 1, 0.95 } },
}
local PAIR_PAY = 2.5

local function rollSymbol()
  local r = love.math.random() * 100
  for i, s in ipairs(SYMBOLS) do
    r = r - s.w
    if r <= 0 then
      return i
    end
  end
  return 1
end

local function drawSymbol(i, x, y, w, h)
  local s = SYMBOLS[i]
  local cx, cy = x + w / 2, y + h / 2
  local r = math.min(w, h) * 0.32
  love.graphics.setColor(s.color)
  if s.name == "Cherry" then
    love.graphics.circle("fill", cx - r * 0.55, cy + r * 0.4, r * 0.55)
    love.graphics.circle("fill", cx + r * 0.55, cy + r * 0.4, r * 0.55)
    love.graphics.setColor(0.3, 0.7, 0.3)
    love.graphics.line(cx - r * 0.5, cy - r * 0.1, cx, cy - r, cx + r * 0.5, cy - r * 0.1)
  elseif s.name == "Lemon" then
    love.graphics.ellipse("fill", cx, cy, r * 1.2, r * 0.8)
  elseif s.name == "Bell" then
    love.graphics.polygon("fill", cx - r, cy + r * 0.7, cx - r * 0.6, cy - r * 0.6, cx, cy - r, cx + r * 0.6, cy - r * 0.6, cx + r, cy + r * 0.7)
    love.graphics.circle("fill", cx, cy + r * 0.9, r * 0.25)
  elseif s.name == "Star" then
    for k = 0, 9 do
      local r1 = k % 2 == 0 and r * 1.1 or r * 0.45
      local r2 = (k + 1) % 2 == 0 and r * 1.1 or r * 0.45
      local a1, a2 = -math.pi / 2 + k * math.pi / 5, -math.pi / 2 + (k + 1) * math.pi / 5
      love.graphics.polygon("fill", cx, cy, cx + math.cos(a1) * r1, cy + math.sin(a1) * r1, cx + math.cos(a2) * r2, cy + math.sin(a2) * r2)
    end
  elseif s.name == "Seven" then
    love.graphics.rectangle("fill", cx - r, cy - r, r * 2, r * 0.45)
    love.graphics.setLineWidth(math.max(2, r * 0.45))
    love.graphics.line(cx + r * 0.75, cy - r * 0.6, cx - r * 0.2, cy + r)
    love.graphics.setLineWidth(1)
  else
    love.graphics.polygon("fill", cx, cy - r * 1.1, cx + r, cy, cx, cy + r * 1.1, cx - r, cy)
    love.graphics.setColor(1, 1, 1, 0.6)
    love.graphics.polygon("fill", cx, cy - r * 1.1, cx + r * 0.3, cy - r * 0.2, cx - r * 0.3, cy - r * 0.2)
  end
end

local BETS = { 10, 25, 50 }

local function gamblerMenu(o, player)
  local dlg = { title = "The Gambler's Den", subtitle = "A dim table, a rattling machine, and a man who never loses.", subtitleColor = { 0.5, 0.9, 0.55 } }
  dlg.edge = { 0.3, 0.6, 0.35, 0.8 }
  dlg.lines = { "Gold or nothing. The house is honest, the odds are not." }
  dlg.buttons = {
    { label = "Slot machine", sub = "Three reels, from " .. BETS[1] .. " gold a pull", fn = function(d) randevents.slots(o, player, d) return true end },
    { label = "High-Low", sub = "Guess the next card. Push your luck or cash out", fn = function(d) randevents.highlow(o, player, d) return true end },
    { label = "Leave the table" },
  }
  openDialog(dlg)
end

function randevents.slots(o, player, dlg)
  dlg.title = "Slot Machine"
  dlg.subtitle = "Three alike pays big, a pair pays " .. PAIR_PAY .. "x. Cherry 5x  Lemon 8x  Bell 12x  Star 20x  Seven 50x  Diamond 100x"
  dlg.drawH = 66
  o.slot = o.slot or { reels = { 1, 2, 3 }, bet = BETS[1], spinUntil = 0, last = "Pull the lever." }
  local sl = o.slot
  dlg.draw = function(x, y, w, h, u, H)
    local rw, rh = math.floor(46 * u), math.floor(40 * u)
    local gap = math.floor(6 * u)
    local total = rw * 3 + gap * 2
    local sx = x + (w - total) / 2
    local now = love.timer.getTime()
    for i = 1, 3 do
      local rx = sx + (i - 1) * (rw + gap)
      love.graphics.setColor(0.08, 0.07, 0.1)
      love.graphics.rectangle("fill", rx, y + 6 * u, rw, rh, u, u)
      love.graphics.setColor(0.7, 0.55, 0.2)
      love.graphics.rectangle("line", rx, y + 6 * u, rw, rh, u, u)
      local stopAt = sl.spinUntil - (3 - i) * 0.4
      local sym = sl.reels[i]
      if now < stopAt then
        sym = (math.floor(now * 14 + i * 3) % #SYMBOLS) + 1
      end
      drawSymbol(sym, rx, y + 6 * u, rw, rh)
    end
    H.printCentered(sl.last, x + w / 2, y + h - 13 * u, H.F.small, { 0.9, 0.9, 0.7 })
  end
  local function build()
    local spinning = love.timer.getTime() < sl.spinUntil
    dlg.lines = { "You have " .. gold(player) .. " gold." }
    dlg.buttons = {
      {
        label = "Pull (bet " .. sl.bet .. ")",
        disabled = gold(player) < sl.bet or spinning,
        fn = function(d)
          player.inventory.gold = player.inventory.gold - sl.bet
          local r = { rollSymbol(), rollSymbol(), rollSymbol() }
          sl.reels = r
          sl.spinUntil = love.timer.getTime() + 1.3
          local win = 0
          if r[1] == r[2] and r[2] == r[3] then
            win = SYMBOLS[r[1]].pay * sl.bet
            sl.last = "JACKPOT: three " .. SYMBOLS[r[1]].name .. "s! +" .. win
          elseif r[1] == r[2] or r[2] == r[3] or r[1] == r[3] then
            win = math.floor(PAIR_PAY * sl.bet)
            sl.last = "A pair. +" .. win
          else
            sl.last = "Nothing."
          end
          audio.play("select")
          -- paid out when the reels stop (the dialog's draw does not run logic, so pay now)
          if win > 0 then
            player.inventory.gold = player.inventory.gold + win
          end
          build()
          return true
        end,
      },
      {
        label = "Change bet (" .. sl.bet .. ")",
        fn = function(d)
          local idx = 1
          for i, b in ipairs(BETS) do
            if b == sl.bet then
              idx = i
            end
          end
          sl.bet = BETS[idx % #BETS + 1]
          build()
          return true
        end,
      },
      { label = "Back", fn = function(d) gamblerMenu(o, player) return false end },
    }
  end
  build()
  -- the buttons refresh as the reels settle
  dlg.refresh = build
end

function randevents.highlow(o, player, dlg)
  dlg.title = "High-Low"
  dlg.subtitle = "A card is dealt. Guess whether the next is higher or lower; a tie loses. Each right guess multiplies the pot."
  dlg.drawH = 66
  o.hl = o.hl or { bet = BETS[1], card = nil, pot = 0, streak = 0, msg = "Place a bet and deal." }
  local hl = o.hl
  local RANKS = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K" }
  dlg.draw = function(x, y, w, h, u, H)
    local cw, ch = math.floor(32 * u), math.floor(44 * u)
    local cx = x + w / 2 - cw / 2
    love.graphics.setColor(0.93, 0.92, 0.85)
    love.graphics.rectangle("fill", cx, y + 6 * u, cw, ch, u, u)
    love.graphics.setColor(0.2, 0.2, 0.25)
    love.graphics.rectangle("line", cx, y + 6 * u, cw, ch, u, u)
    if hl.card then
      local red = (hl.card + (hl.suit or 0)) % 2 == 0
      love.graphics.setColor(red and 0.8 or 0.1, red and 0.1 or 0.1, red and 0.12 or 0.14)
      H.printCentered(RANKS[hl.card], cx + cw / 2, y + 6 * u + ch / 2 - H.F.head:getHeight() / 2, H.F.head, red and { 0.8, 0.1, 0.12 } or { 0.1, 0.1, 0.14 })
    else
      love.graphics.setColor(0.5, 0.15, 0.2)
      love.graphics.rectangle("fill", cx + 3 * u, y + 9 * u, cw - 6 * u, ch - 6 * u)
    end
    H.printCentered(hl.msg, x + w / 2, y + h - 13 * u, H.F.small, { 0.9, 0.9, 0.7 })
    if hl.pot > 0 then
      H.shadowPrint("Pot: " .. hl.pot, x + 6 * u, y + 6 * u, H.F.body, { 1, 0.85, 0.3 })
    end
  end
  local function chance(higher)
    local c = hl.card
    local p = higher and (13 - c) / 13 or (c - 1) / 13
    return p
  end
  local function guess(higher)
    local nextCard = love.math.random(1, 13)
    local old = hl.card
    local won = (higher and nextCard > old) or (not higher and nextCard < old)
    if won then
      local p = chance(higher)
      hl.pot = math.floor(hl.pot * math.min(6, 0.94 / math.max(0.05, p)) + 0.5)
      hl.streak = hl.streak + 1
      hl.msg = RANKS[old] .. " then " .. RANKS[nextCard] .. ": right!"
      hl.card, hl.suit = nextCard, love.math.random(0, 1)
      if hl.streak >= 6 then
        hl.msg = "Six in a row! The house pays up."
        player.inventory.gold = player.inventory.gold + hl.pot
        hl.pot, hl.card, hl.streak = 0, nil, 0
      end
    else
      hl.msg = RANKS[old] .. " then " .. RANKS[nextCard] .. ": the house wins."
      hl.pot, hl.card, hl.streak = 0, nil, 0
    end
  end
  local function build()
    dlg.lines = { "You have " .. gold(player) .. " gold." }
    dlg.buttons = {}
    if not hl.card then
      dlg.buttons[#dlg.buttons + 1] = {
        label = "Deal (bet " .. hl.bet .. ")",
        disabled = gold(player) < hl.bet,
        fn = function()
          player.inventory.gold = player.inventory.gold - hl.bet
          hl.pot, hl.streak = hl.bet, 0
          hl.card, hl.suit = love.math.random(1, 13), love.math.random(0, 1)
          hl.msg = "Higher or lower?"
          audio.play("select")
          build()
          return true
        end,
      }
      dlg.buttons[#dlg.buttons + 1] = {
        label = "Change bet (" .. hl.bet .. ")",
        fn = function()
          local idx = 1
          for i, b in ipairs(BETS) do
            if b == hl.bet then
              idx = i
            end
          end
          hl.bet = BETS[idx % #BETS + 1]
          build()
          return true
        end,
      }
    else
      local ph, pl = chance(true), chance(false)
      dlg.buttons[#dlg.buttons + 1] = {
        label = "Higher",
        sub = ph > 0 and string.format("%d%% chance, pot x%.1f", ph * 100 + 0.5, math.min(6, 0.94 / ph)) or "Impossible",
        disabled = ph <= 0,
        fn = function() guess(true) build() return true end,
      }
      dlg.buttons[#dlg.buttons + 1] = {
        label = "Lower",
        sub = pl > 0 and string.format("%d%% chance, pot x%.1f", pl * 100 + 0.5, math.min(6, 0.94 / pl)) or "Impossible",
        disabled = pl <= 0,
        fn = function() guess(false) build() return true end,
      }
      dlg.buttons[#dlg.buttons + 1] = {
        label = "Cash out (" .. hl.pot .. ")",
        disabled = hl.streak < 1,
        fn = function()
          player.inventory.gold = player.inventory.gold + hl.pot
          hl.msg = "You walk away with " .. hl.pot .. "."
          hl.pot, hl.card, hl.streak = 0, nil, 0
          audio.play("buy")
          build()
          return true
        end,
      }
    end
    dlg.buttons[#dlg.buttons + 1] = {
      label = "Back",
      disabled = hl.card ~= nil,
      fn = function() gamblerMenu(o, player) return false end,
    }
  end
  build()
  dlg.refresh = build
end

-- Tinker -----------------------------------------------------------------------

local function tinkerDialog(o, player)
  local inv = player.inventory
  local gun = inv:selectedGun()
  local dlg = { title = "The Travelling Tinker", subtitle = "\"Every gun has a better self in it. Let me shake it loose.\"", subtitleColor = { 0.95, 0.75, 0.45 } }
  o.rerolls = o.rerolls or 0
  local function price()
    return 35 + 30 * o.rerolls
  end
  local function build()
    gun = inv:selectedGun()
    if not gun or not gun.rolls then
      dlg.lines = { "You are not holding a weapon he can work on." }
      dlg.buttons = { { label = "Leave" } }
      return
    end
    local g = gunInfo.grade(gun)
    local _, sustained = gunInfo.dps(gun)
    dlg.lines = {
      { text = gun.name .. "   grade " .. g.letter .. "   " .. math.floor(sustained + 0.5) .. " DPS", color = g.color },
      "Re-rolls the bonuses on the weapon you hold (it keeps its slots and what is fitted). The price climbs with every try. You can undo the last one for free.",
      "You have " .. gold(player) .. " gold.",
    }
    dlg.buttons = {
      {
        label = "Re-roll (" .. price() .. " gold)",
        disabled = gold(player) < price(),
        fn = function()
          inv.gold = inv.gold - price()
          o.rerolls = o.rerolls + 1
          local fresh = guns.generate(gun.id, nil, 0)
          o.undo = { gun = gun, rolls = gun.rolls, name = gun.name }
          gun.rolls, gun.name = fresh.rolls, fresh.name
          gun.statsSignature = nil
          audio.play("buy")
          sparkle(o.x, o.y - 10, { 1, 0.8, 0.4 })
          build()
          return true
        end,
      },
      {
        label = "Undo the last re-roll",
        disabled = not (o.undo and o.undo.gun == gun),
        fn = function()
          gun.rolls, gun.name = o.undo.rolls, o.undo.name
          gun.statsSignature = nil
          o.undo = nil
          audio.play("select")
          build()
          return true
        end,
      },
      { label = "Done" },
    }
  end
  build()
  dlg.refresh = build
  openDialog(dlg)
end

-- Shrine -----------------------------------------------------------------------

local function pickPerk(rarity)
  local pool = {}
  for _, id in ipairs(perks.order) do
    if not perks.has(id) and perks.defs[id].rarity == rarity then
      pool[#pool + 1] = id
    end
  end
  return pool[#pool > 0 and love.math.random(#pool) or 1]
end

local function shrineDialog(o, player)
  local dlg = { title = "Shrine of the Fallen", subtitle = "Names scratched into the stone, and a pale flame that never gutters.", subtitleColor = { 0.7, 0.6, 1 } }
  dlg.edge = { 0.5, 0.4, 0.8, 0.8 }
  local function build()
    if o.used then
      dlg.lines = { "The flame has gone quiet." }
      dlg.buttons = { { label = "Leave" } }
      return
    end
    dlg.lines = { "The shrine takes one thing and gives another. Choose what you will give. You have " .. gold(player) .. " gold and " .. player.hp .. " health." }
    dlg.buttons = {
      {
        label = "Offer 35 gold",
        sub = "Be made whole: full health",
        disabled = gold(player) < 35,
        fn = function()
          player.inventory.gold = player.inventory.gold - 35
          player.hp = player.maxHp
          o.used = true
          audio.play("buy")
          sparkle(o.x, o.y - 14, { 0.7, 0.6, 1 })
          popup(o.x, o.y - 30, "Restored", { 0.7, 0.9, 1 })
        end,
      },
      {
        label = "Offer your blood (20 health)",
        sub = "A rare boon for the rest of the run",
        disabled = player.hp <= 22,
        fn = function()
          player:loseHealth(20)
          local boon = pickPerk("rare")
          o.used = true
          if boon then
            perks.add(boon)
            player:refreshMaxHp()
            popup(o.x, o.y - 30, perks.defs[boon].name, { 0.85, 0.6, 1 })
          end
          audio.play("buy")
          sparkle(o.x, o.y - 14, { 0.85, 0.5, 1 })
        end,
      },
      {
        label = "Pray, and pay nothing",
        sub = "A coin toss: a rare item, or a curse of 15 health",
        fn = function()
          o.used = true
          if love.math.random() < 0.5 then
            dropReward(o.x, o.y, 0, randomItem({ rare = true }))
            popup(o.x, o.y - 30, "The shrine provides", { 0.7, 1, 0.8 })
            audio.play("buy")
          else
            player.hp = math.max(1, player.hp - 15)
            popup(o.x, o.y - 30, "It wanted more", { 1, 0.5, 0.5 })
            audio.play("deny")
          end
        end,
      },
      { label = "Walk away" },
    }
  end
  build()
  dlg.refresh = build
  openDialog(dlg)
end

-- Cave-in ----------------------------------------------------------------------

local MOUND_W, MOUND_H = 13, 18

local function buryMiner(o)
  local x, g = o.x, o.y
  world:fillRect(x - MOUND_W, g - MOUND_H, x + MOUND_W, g - 1, materials.DIRT)
  world:repaintRegion(x - MOUND_W - 3, g - MOUND_H - 3, x + MOUND_W + 3, g + 3)
  require("src.physics").rebuildRegion(x - MOUND_W - 3, g - MOUND_H - 3, x + MOUND_W + 3, g + 3)
end

local function moundSolid(o)
  local n = 0
  for yy = o.y - MOUND_H, o.y - 1, 2 do
    for xx = o.x - 4, o.x + 4 do
      if world:isSolid(xx, yy) then
        n = n + 1
      end
    end
  end
  return n
end

-- Hunt -------------------------------------------------------------------------

local HUNT_KINDS = { "ghoul", "miner", "roller" }
local HUNT_TIME = 120

local function startHunt(o, px, py)
  local kind = HUNT_KINDS[love.math.random(#HUNT_KINDS)]
  local x, gy = findSpot(px, py, 6, 150, 330)
  if not x then
    return false
  end
  local e = enemies.spawn(kind, x, gy, 2.2, 1)
  local affixes = {}
  local pool = {}
  for _, a in ipairs(enemies.AFFIX_ORDER) do
    pool[#pool + 1] = a
  end
  for _ = 1, 2 do
    if #pool > 0 then
      affixes[#affixes + 1] = table.remove(pool, love.math.random(#pool))
    end
  end
  enemies.makeElite(e, affixes)
  e.bountyName = "Marked " .. (e.def.name or kind)
  e.state = "chase"
  o.beast, o.x, o.y, o.timeLeft, o.kind = e, x, gy, HUNT_TIME, "hunt"
  popup(px, py - 30, "A marked beast prowls these halls", { 1, 0.5, 0.4 })
  audio.play("explosion", 0.4, 0.6)
  return true
end

-- Spawning ---------------------------------------------------------------------

local function spawn(kind, player, areaIndex)
  local px, py = player:center()
  local o = { kind = kind, age = 0, life = 170 }
  if kind == "hunt" then
    o.life = HUNT_TIME + 40
    if not startHunt(o, px, py) then
      return nil
    end
    return o
  end
  local x, gy = findSpot(px, py, kind == "gambler" and 22 or (kind == "carnival" and 14 or 12), 70, 260)
  if not x then
    return nil
  end
  o.x, o.y = x, gy
  if kind == "carnival" then
    o.state = "idle"
    o.title = "A carnival stall"
  elseif kind == "cavein" then
    o.timeLeft = 75
    buryMiner(o)
  end
  local names = {
    carnival = "A carnival stall, out of nowhere...",
    gambler = "A gambler's den...",
    tinker = "A travelling tinker",
    shrine = "A shrine of the fallen",
    cavein = "Someone is buried here!",
  }
  popup(x, gy - 40, names[kind], { 1, 0.9, 0.6 })
  return o
end

function randevents.update(dt, player, areaIndex, w)
  world = w or world
  if not world then
    return
  end
  if not active then
    if areaIndex and meta.profileActive() and not player.dead then
      timer = timer - dt
      if timer <= 0 then
        timer = 120 + love.math.random() * 120
        local kind
        for _ = 1, 6 do
          kind = KINDS[love.math.random(#KINDS)]
          if kind ~= lastKind then
            break
          end
        end
        active = spawn(kind, player, areaIndex)
        lastKind = active and kind or lastKind
        if not active then
          timer = 20
        end
      end
    end
    return
  end
  local o = active
  o.age = o.age + dt
  if o.say then
    o.say.age = o.say.age + dt
  end
  local px, py = player:center()
  if o.kind == "carnival" then
    if o.state == "playing" then
      o.timeLeft = o.timeLeft - dt
      if o.timeLeft <= 0 then
        finishCarnival(o, player)
      end
    elseif o.state == "idle" then
      o.life = o.life - dt
    else
      o.life = o.life - dt
    end
  elseif o.kind == "hunt" then
    o.timeLeft = o.timeLeft - dt
    local e = o.beast
    if e and e.dead then
      local b = e.body
      dropReward(b.x + b.w / 2, b.y + b.h, 80, randomItem({ rare = true }))
      popup(b.x + b.w / 2, b.y - 20, "Bounty claimed", { 1, 0.85, 0.4 })
      audio.play("buy")
      active = nil
      return
    elseif o.timeLeft <= -30 then
      active = nil
    end
  elseif o.kind == "cavein" then
    if o.state ~= "done" then
      o.timeLeft = o.timeLeft - dt
      if o.state == nil then
        o.digT = (o.digT or 0) - dt
        if o.digT <= 0 then
          o.digT = 0.25
          if moundSolid(o) <= 12 then
            o.state = "done"
            o.life = 10
            say(o, "Thank the stars! Take this.")
            dropReward(o.x, o.y, 55, randomItem({ common = true, rare = true }))
            audio.play("buy")
            sparkle(o.x, o.y - 10)
          end
        end
      end
      if o.state == nil and o.timeLeft <= 0 then
        o.state = "lost"
        o.life = 12
        popup(o.x, o.y - 30, "Too late...", { 0.8, 0.7, 0.7 })
      end
    else
      o.life = o.life - dt
    end
    if o.state == "lost" then
      o.life = o.life - dt
    end
  else
    o.life = o.life - dt
  end
  if o.life and o.life <= 0 and (o.kind ~= "carnival" or o.state ~= "playing") then
    if o.kind == "carnival" and o.targets then
      for _, t in ipairs(o.targets) do
        targets.remove(t)
      end
    end
    active = nil
  end
end

-- For tests: an event of the given kind beside the hunter at once
function randevents.force(kind, player, w)
  world = w or world
  active = spawn(kind, player, 1)
  return active
end

function randevents.current()
  return active
end

-- Interaction ------------------------------------------------------------------

local function near(o, px, py)
  return o and o.kind ~= "hunt" and dist(o, px, py) < 30
end

function randevents.interact(player)
  local o = active
  if not o or player.dead then
    return false
  end
  local px, py = player:center()
  if not near(o, px, py) then
    return false
  end
  if o.kind == "carnival" then
    if o.state == "idle" or o.state == "done" then
      carnivalDialog(o, player)
    else
      say(o, "Eyes on the targets!")
    end
  elseif o.kind == "gambler" then
    gamblerMenu(o, player)
  elseif o.kind == "tinker" then
    tinkerDialog(o, player)
  elseif o.kind == "shrine" then
    shrineDialog(o, player)
  elseif o.kind == "cavein" then
    say(o, o.state == nil and "Dig! Please dig!" or "...")
  end
  audio.play("select")
  return true
end

-- Drawing ----------------------------------------------------------------------

local WOOD, WOOD_D, WOOD_L = { 0.45, 0.30, 0.17 }, { 0.30, 0.20, 0.11 }, { 0.62, 0.44, 0.25 }
local SKIN = { 0.80, 0.60, 0.46 }

local function drawFigure(x, g, hat, coat, facing)
  R({ 0.2, 0.17, 0.16 }, x - 2, g - 5, 2, 5)
  R({ 0.2, 0.17, 0.16 }, x + 1, g - 5, 2, 5)
  R(coat, x - 3, g - 12, 7, 8)
  R(SKIN, x - 2, g - 17, 5, 5)
  R(hat, x - 3, g - 19, 7, 2)
  R(hat, x - 2, g - 21, 5, 2)
  R({ 0.1, 0.08, 0.08 }, x + (facing or 1), g - 15, 1, 1)
end

local function drawCarnival(o, t)
  local x, g = o.x, o.y
  -- the rail posts and the counter
  R(WOOD_D, x - 66, g - 62, 2, 62)
  R(WOOD_D, x + 64, g - 62, 2, 62)
  R(WOOD, x - 66, g - 64, 132, 3)
  for i = 0, 10 do
    R(i % 2 == 0 and { 0.85, 0.15, 0.18 } or { 0.92, 0.9, 0.82 }, x - 66 + i * 12, g - 70, 12, 6)
  end
  R(WOOD, x - 30, g - 12, 60, 12)
  R(WOOD_L, x - 30, g - 12, 60, 2)
  R(WOOD_D, x - 28, g - 8, 56, 1)
  drawFigure(x + 40, g, { 0.7, 0.1, 0.12 }, { 0.82, 0.78, 0.7 }, -1)
  -- pennants
  for i = 0, 5 do
    R(i % 2 == 0 and { 0.95, 0.75, 0.2 } or { 0.3, 0.6, 0.9 }, x - 62 + i * 24, g - 58 + math.floor(math.sin(t * 2 + i) * 1), 5, 6)
  end
  if o.state == "playing" then
    local bar = math.max(0, o.timeLeft / CARNIVAL_TIME)
    R({ 0.1, 0.1, 0.12 }, x - 30, g - 80, 60, 4)
    R({ 0.95, 0.75, 0.2 }, x - 30, g - 80, 60 * bar, 4)
  end
end

local function drawGambler(o, t)
  local x, g = o.x, o.y
  -- table with green baize and cards
  R(WOOD_D, x - 24, g - 14, 3, 14)
  R(WOOD_D, x + 8, g - 14, 3, 14)
  R({ 0.10, 0.34, 0.20 }, x - 28, g - 17, 42, 4)
  R({ 0.06, 0.22, 0.13 }, x - 28, g - 14, 42, 1)
  R({ 0.93, 0.92, 0.85 }, x - 20, g - 20, 5, 3)
  R({ 0.93, 0.92, 0.85 }, x - 12, g - 20, 5, 3)
  R({ 0.8, 0.12, 0.14 }, x - 11, g - 19, 1, 1)
  -- the slot machine
  R({ 0.55, 0.10, 0.12 }, x + 18, g - 34, 14, 34)
  R({ 0.85, 0.65, 0.2 }, x + 18, g - 34, 14, 3)
  R({ 0.08, 0.07, 0.1 }, x + 20, g - 28, 10, 8)
  local spin = math.floor(t * 8)
  for i = 0, 2 do
    R(SYMBOLS[((spin + i * 2) % #SYMBOLS) + 1].color, x + 21 + i * 3, g - 26, 2, 4)
  end
  R({ 0.85, 0.65, 0.2 }, x + 32, g - 28, 1, 8)
  R({ 0.8, 0.12, 0.14 }, x + 31, g - 30, 3, 3)
  drawFigure(x - 4, g, { 0.15, 0.15, 0.2 }, { 0.2, 0.2, 0.28 }, 1)
end

local function drawTinker(o, t)
  local x, g = o.x, o.y
  -- a handcart with a big wheel, pots and pans hanging off it
  R(WOOD_D, x - 18, g - 18, 30, 3)
  R(WOOD, x - 18, g - 22, 30, 5)
  R(WOOD_L, x - 18, g - 22, 30, 1)
  R({ 0.5, 0.5, 0.55 }, x - 14, g - 28, 6, 6)
  R({ 0.7, 0.45, 0.2 }, x - 4, g - 30, 5, 8)
  R({ 0.35, 0.55, 0.4 }, x + 4, g - 27, 6, 5)
  love.graphics.setColor(WOOD_D)
  love.graphics.circle("line", x - 8, g - 7, 7)
  love.graphics.circle("fill", x - 8, g - 7, 1.5)
  for k = 0, 3 do
    local a = k * math.pi / 4 + t * 0.2
    love.graphics.line(x - 8 + math.cos(a) * 7, g - 7 + math.sin(a) * 7, x - 8 - math.cos(a) * 7, g - 7 - math.sin(a) * 7)
  end
  R(WOOD_D, x + 10, g - 18, 10, 2)
  -- the tinker, bent under a pack
  drawFigure(x + 22, g, { 0.4, 0.3, 0.15 }, { 0.45, 0.32, 0.2 }, -1)
  R({ 0.55, 0.42, 0.25 }, x + 24, g - 16, 5, 8)
  R({ 0.9, 0.7, 0.3 }, x + 25, g - 24 + math.floor(math.sin(t * 3) * 1), 2, 3) -- a swinging lantern
end

local function drawShrine(o, t)
  local x, g = o.x, o.y
  local STONE, STONE_L, STONE_D = { 0.40, 0.40, 0.46 }, { 0.58, 0.58, 0.64 }, { 0.24, 0.24, 0.30 }
  R(STONE_D, x - 14, g - 4, 28, 4)
  R(STONE, x - 12, g - 8, 24, 4)
  R(STONE, x - 10, g - 30, 4, 22)
  R(STONE, x + 6, g - 30, 4, 22)
  R(STONE_L, x - 10, g - 30, 1, 22)
  R(STONE_L, x + 6, g - 30, 1, 22)
  R(STONE_D, x - 12, g - 33, 24, 4)
  R(STONE_L, x - 12, g - 33, 24, 1)
  R({ 0.2, 0.2, 0.26 }, x - 4, g - 16, 8, 6)
  if not o.used then
    local f = 0.7 + math.sin(t * 6) * 0.15
    R({ 0.5, 0.45, 1 }, x - 2, g - 22 - math.floor(f * 3), 4, 6 + math.floor(f * 3))
    R({ 0.85, 0.8, 1 }, x - 1, g - 20 - math.floor(f * 3), 2, 4)
  else
    R({ 0.2, 0.18, 0.28 }, x - 1, g - 18, 2, 2)
  end
  for i = -1, 1, 2 do
    R({ 0.75, 0.7, 0.55 }, x + i * 8 - 1, g - 10, 3, 2)
  end
end

local function drawCavein(o, t)
  local x, g = o.x, o.y
  if o.state == "lost" then
    R({ 0.75, 0.7, 0.58 }, x - 1, g - MOUND_H - 4, 2, 4)
    R({ 0.75, 0.7, 0.58 }, x - 3, g - MOUND_H - 2, 6, 1)
  elseif o.state == nil then
    -- a hand reaching up out of the rubble, waving
    local w = math.floor(math.sin(t * 5) * 1.5)
    R(SKIN, x - 1 + w, g - MOUND_H - 6, 2, 6)
    R(SKIN, x - 2 + w, g - MOUND_H - 8, 4, 2)
    R(SKIN, x - 3 + w, g - MOUND_H - 9, 1, 2)
    R(SKIN, x + 2 + w, g - MOUND_H - 9, 1, 2)
  elseif o.state == "done" then
    drawFigure(x, g, { 0.4, 0.3, 0.15 }, { 0.5, 0.42, 0.3 }, 1)
  end
end

function randevents.draw(view)
  local o = active
  if not o or not o.x or o.x < view.x - 100 or o.x > view.x + view.w + 100 then
    return
  end
  local t = love.timer.getTime()
  if o.kind == "carnival" then
    drawCarnival(o, t)
  elseif o.kind == "gambler" then
    drawGambler(o, t)
  elseif o.kind == "tinker" then
    drawTinker(o, t)
  elseif o.kind == "shrine" then
    drawShrine(o, t)
  elseif o.kind == "cavein" then
    drawCavein(o, t)
  end
end

function randevents.addLights(lighting, view)
  local o = active
  if not o or not o.x or o.kind == "hunt" then
    return
  end
  if o.kind == "shrine" and not o.used then
    lighting.add(o.x, o.y - 20, 60, 0.55, 0.5, 1, 0.8)
  elseif o.kind == "carnival" then
    lighting.add(o.x, o.y - 40, 90, 1, 0.8, 0.45, 0.8)
  elseif o.kind == "gambler" then
    lighting.add(o.x, o.y - 24, 70, 0.5, 1, 0.6, 0.6)
  elseif o.kind == "tinker" then
    lighting.add(o.x + 26, o.y - 22, 55, 1, 0.8, 0.4, 0.7)
  end
end

local function prompt(font, toScreen, wx, wy, text)
  local sx, sy = toScreen(wx, wy)
  love.graphics.setFont(font)
  local x, y = math.floor(sx - font:getWidth(text) / 2), math.floor(sy - font:getHeight())
  love.graphics.setColor(0, 0, 0, 0.85)
  love.graphics.print(text, x + 2, y + 2)
  love.graphics.setColor(1, 0.88, 0.6)
  love.graphics.print(text, x, y)
end

function randevents.drawScreen(toScreen, font, player)
  local o = active
  if not o or require("src.menu").isOpen() then
    return
  end
  if o.say and o.x then
    require("src.npcs").bubble(font, o.say.text, toScreen(o.x, o.y - 26), select(2, toScreen(o.x, o.y - 26)), o.say.age)
  end
  if player.dead then
    return
  end
  local px, py = player:center()
  local key = "[" .. input.label("interact") .. "] "
  if o.kind == "hunt" then
    local e = o.beast
    if e and not e.dead then
      local t = math.max(0, math.floor(o.timeLeft))
      local text = string.format("%s  %d:%02d", enemies.eliteName(e), math.floor(t / 60), t % 60)
      love.graphics.setFont(font)
      local ww = love.graphics.getWidth()
      love.graphics.setColor(0, 0, 0, 0.8)
      love.graphics.print(text, math.floor(ww / 2 - font:getWidth(text) / 2) + 2, math.floor(font:getHeight() * 5) + 2)
      love.graphics.setColor(1, o.timeLeft > 0 and 0.55 or 0.4, 0.4)
      love.graphics.print(text, math.floor(ww / 2 - font:getWidth(text) / 2), math.floor(font:getHeight() * 5))
    end
    return
  end
  if o.kind == "carnival" and o.state == "playing" then
    prompt(font, toScreen, o.x, o.y - 84, string.format("Hits: %d   Time: %d", o.hits, math.ceil(o.timeLeft)))
  elseif o.kind == "cavein" and o.state == nil then
    local text = string.format("Dig him out!  %d s", math.max(0, math.ceil(o.timeLeft)))
    prompt(font, toScreen, o.x, o.y - MOUND_H - 14, text)
  elseif near(o, px, py) then
    local text = ({
      carnival = (o.state == "playing") and nil or "Try the shooting gallery",
      gambler = "Sit at the table",
      tinker = "Trade with the tinker",
      shrine = o.used and nil or "Kneel at the shrine",
    })[o.kind]
    if text then
      prompt(font, toScreen, o.x, o.y - 30, key .. text)
    end
  end
end

return randevents
