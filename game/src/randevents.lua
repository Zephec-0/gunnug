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
local config = require("src.config")
local effects = require("src.effects")
local eventart = require("src.eventart")
local eventui = require("src.eventui")
local enemies = require("src.enemies")
local fluids = require("src.fluids")
local gunInfo = require("src.gunInfo")
local guns = require("src.guns")
local input = require("src.input")
local items = require("src.items")
local materials = require("src.materials")
local meta = require("src.meta")
local people = require("src.people")
local perks = require("src.perks")
local pickups = require("src.pickups")
local targets = require("src.targets")

local randevents = {}

local active -- the one event on now: { kind, x, y (ground), age, life, ... }
local showcase = {} -- the test room's permanent stands: { kind, x, y (ground), o (the event now standing), wait }
local timer = 120
local lastKind
local world

local KINDS = { "carnival", "gambler", "tinker", "shrine", "cavein", "hunt" }

function randevents.clear()
  active = nil
  showcase = {}
  world = nil
  timer = 90 + love.math.random() * 140
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

-- (x: where the speaker stands, if not the event's middle)
local function say(o, text, x)
  o.say = { text = text, age = 0, x = x }
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

-- (the gold and the item come out a little apart, so neither lands on the other)
local function dropReward(x, y, goldAmount, item)
  if goldAmount and goldAmount > 0 then
    pickups.dropGold(x - (item and 9 or 0), y - 10, goldAmount)
  end
  if item then
    pickups.dropItem(x + (goldAmount and goldAmount > 0 and 9 or 0), y - 14, item, 38 * (love.math.random() < 0.5 and -1 or 1), -70)
  end
end

-- Open, flat ground with air above, near the hunter but not on top of him
-- (and always off-screen: past the edge of the view, which leads toward the aim, so the hunter has to find it)
local function findSpot(px, py, flatHalf, minD, maxD)
  minD = math.max(minD, config.VIRTUAL_W / 2 + 90)
  maxD = math.max(maxD, minD + 160)
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
    local x = math.floor(px + (love.math.random() < 0.5 and -1 or 1) * (minD + love.math.random() * (maxD - minD)))
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

-- Easy: the targets slide from side to side. Medium: they bounce about the whole stall, on the
-- diagonal. Hard: they blink in, anywhere, for a quarter of a second.
-- What a round pays: Easy a bullet or an attachment, Medium a gun, Hard a perk, each better the more of the
-- goal was hit. Under 60% of it pays nothing; above that the bands of the goal get narrower as they get better.
local DIFFICULTIES = {
  { name = "Easy", cost = 10, speed = 34, goal = 30, mode = "sweep", color = { 0.62, 0.95, 0.62 }, icon = "ammo",
    text = "Chance of an attachment or ammo. The more targets you hit, the rarer it is." },
  { name = "Medium", cost = 25, speed = 72, goal = 25, mode = "bounce", color = { 1.0, 0.95, 0.55 }, icon = "gun",
    text = "Chance of a weapon. The more targets you hit, the better a roll it has." },
  { name = "Hard", cost = 50, speed = 0, goal = 20, mode = "blink", color = { 1.0, 0.60, 0.55 }, icon = "perk",
    text = "Chance of a perk. The more targets you hit, the rarer it is." },
}
local TIER_FROM = { 0.60, 0.76, 0.89, 0.97 } -- the share of the goal where each of the four prize tiers starts
local CARNIVAL_TIME = 17
local COUNT_TIME = 3 -- the count before the targets come out
local BLINK_TIME = 1.0 -- how long a blinking target stays
local CARNY_DX = 92 -- where the carny stands: off to the side of the stall, and all of it is done through him
-- (the top-left corners a target may take, from the stall's ground point)
local AREA_X0, AREA_X1, AREA_Y0, AREA_Y1 = -62, 51, -66, -16

local function drawCarnivalTarget(t)
  if t.hidden then
    return
  end
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(eventart.target(t.flash > 0), math.floor(t.x), math.floor(t.y))
end

local function startCarnival(o, diff, player)
  o.state = "playing"
  o.diff = diff
  o.hits = 0
  o.timeLeft = CARNIVAL_TIME
  o.targets = {}
  local gx, gy = o.x, o.y
  local function roam(t)
    t.x = gx + AREA_X0 + love.math.random() * (AREA_X1 - AREA_X0)
    t.y = gy + AREA_Y0 + love.math.random() * (AREA_Y1 - AREA_Y0)
  end
  for i = 1, 3 do
    local t = { x = 0, y = 0, w = 11, h = 11, hiddenT = 0, lane = i, dir = i % 2 == 0 and -1 or 1 }
    if diff.mode == "sweep" then
      t.x, t.y = gx - 50 + (i - 1) * 40, gy - ({ 27, 43, 59 })[i]
    elseif diff.mode == "bounce" then
      roam(t)
      local a = (0.45 + love.math.random() * 0.6) -- (always well off the horizontal and the vertical)
      local sx = love.math.random() < 0.5 and 1 or -1
      local sy = love.math.random() < 0.5 and 1 or -1
      t.vx, t.vy = math.cos(a) * diff.speed * sx, math.sin(a) * diff.speed * sy
    else
      t.hidden, t.hiddenT = true, 0.2 + (i - 1) * 0.3
    end
    t.update = function(self, dt)
      if diff.mode == "blink" then
        if self.hidden then
          self.hiddenT = self.hiddenT - dt
          if self.hiddenT <= 0 then
            roam(self)
            self.hidden, self.life = false, BLINK_TIME
            for _ = 1, 5 do
              effects.particle(self.x + 5, self.y + 5, (love.math.random() - 0.5) * 50, (love.math.random() - 0.5) * 50, 0.25, { 1, 0.9, 0.5 }, 0, true)
            end
            audio.play("tick", 0.5, 1.4)
          end
        else
          self.life = self.life - dt
          if self.life <= 0 then
            self.hidden, self.hiddenT = true, 0.3 + love.math.random() * 0.5
          end
        end
        return
      end
      if self.hiddenT > 0 then
        self.hiddenT = self.hiddenT - dt
        if self.hiddenT <= 0 then
          self.hidden = false
          if diff.mode == "bounce" then
            roam(self)
          end
        end
        return
      end
      if diff.mode == "sweep" then
        self.x = self.x + self.dir * diff.speed * dt * (1 + (self.lane - 2) * 0.15)
        if self.x < gx + AREA_X0 then
          self.x, self.dir = gx + AREA_X0, 1
        elseif self.x > gx + AREA_X1 then
          self.x, self.dir = gx + AREA_X1, -1
        end
      else
        self.x, self.y = self.x + self.vx * dt, self.y + self.vy * dt
        if self.x < gx + AREA_X0 then
          self.x, self.vx = gx + AREA_X0, math.abs(self.vx)
        elseif self.x > gx + AREA_X1 then
          self.x, self.vx = gx + AREA_X1, -math.abs(self.vx)
        end
        if self.y < gy + AREA_Y0 then
          self.y, self.vy = gy + AREA_Y0, math.abs(self.vy)
        elseif self.y > gy + AREA_Y1 then
          self.y, self.vy = gy + AREA_Y1, -math.abs(self.vy)
        end
      end
    end
    t.draw = drawCarnivalTarget
    t.onHit = function(self, amount)
      if o.state ~= "playing" or self.hidden then
        return
      end
      self.flash = 0.1
      self.hidden = true
      self.hiddenT = diff.mode == "blink" and (0.5 + love.math.random() * 0.5) or 0.8
      o.hits = o.hits + 1
      audio.play("target_hit")
      popup(self.x + 5, self.y - 4, "+1", { 1, 0.85, 0.3 })
    end
    o.targets[#o.targets + 1] = targets.addCustom(t)
  end
  say(o, "Shoot!", o.x + CARNY_DX)
end

-- An item of a rarity, a common one levelled up (+1..+4) if asked
local function itemOf(rarity, level)
  local item = randomItem({ [rarity] = true })
  if level and level > 0 and items.levelable(item.id) then
    item = items.new(item.id, level)
  end
  return item
end

local function pickPerkOf(rarities)
  for _, r in ipairs(rarities) do
    local pool = {}
    for _, id in ipairs(perks.order) do
      if not perks.has(id) and perks.defs[id].rarity == r then
        pool[#pool + 1] = id
      end
    end
    if #pool > 0 then
      return pool[love.math.random(#pool)]
    end
  end
end

-- A gun, the better the higher the tier: the worst of three, a plain one, the best of three, the best of ten
local function prizeGun(tier)
  local count = ({ 3, 1, 3, 10 })[tier]
  local pick, pickScore
  for _ = 1, count do
    local g = guns.generate(nil, nil, 0.3)
    for _ = 1, 40 do
      -- (never better than an S: an SS is rerolled)
      if gunInfo.gradeIndex(g) <= 6 then
        break
      end
      g = guns.generate(nil, nil, 0.3)
    end
    local sc = gunInfo.score(g)
    if not pick or (tier == 1 and sc < pickScore) or (tier ~= 1 and sc > pickScore) then
      pick, pickScore = g, sc
    end
  end
  return pick
end

local function finishCarnival(o, player)
  for _, t in ipairs(o.targets or {}) do
    targets.remove(t)
  end
  o.targets = nil
  o.state = "done"
  o.life = 12
  local diff = o.diff
  local hits = o.hits
  local share = hits / diff.goal
  local tier = 0
  for i, from in ipairs(TIER_FROM) do
    if share >= from then
      tier = i
    end
  end
  local cx, cg = o.x + CARNY_DX, o.cy or o.y
  popup(o.x, o.y - 80, hits .. " / " .. diff.goal, { 1, 0.9, 0.5 })
  if tier == 0 then
    say(o, "Not enough, friend. Come back when you can shoot.", cx)
    return
  end
  local what
  if diff.mode == "sweep" then
    local item
    if tier == 1 then
      item = itemOf("common", 0)
    elseif tier == 2 then
      item = itemOf("common", 1)
    elseif tier == 3 then
      item = itemOf("rare")
    else
      item = itemOf("rare")
    end
    pickups.dropItem(cx - 6, cg - 14, item, -38, -70)
    what = "a prize"
  elseif diff.mode == "bounce" then
    pickups.dropWeapon(cx - 6, cg - 14, prizeGun(tier), -36, -80)
    what = "a gun"
  else
    local boon = pickPerkOf(({ { "common" }, { "rare", "common" }, { "rare", "common" }, { "epic", "rare", "common" } })[tier])
    if boon then
      pickups.dropPerk(cx - 6, cg - 14, boon, -36, -80)
    else
      pickups.dropGold(cx - 6, cg - 14, 100)
    end
    what = "a boon"
  end
  say(o, ({ "Fair shooting. Take " .. what .. ".", "Fine shooting! Have " .. what .. ".", "Sharp! Here is " .. what .. ".", "Perfect! The very best " .. (what:gsub("^an? ", "")) .. " I have!" })[tier], cx)
  audio.play("buy")
  sparkle(cx, cg)
end

-- Three cards, one a difficulty each (light green, yellow and red), saying what they may pay
local function carnivalDialog(o, player)
  local offers = {}
  for _, d in ipairs(DIFFICULTIES) do
    offers[#offers + 1] = {
      title = d.name,
      text = d.text .. "\n\nHit " .. math.ceil(TIER_FROM[1] * d.goal) .. " of " .. d.goal .. " targets or more to win anything.",
      cost = d.cost .. " gold",
      icon = d.icon,
      color = d.color,
      disabled = gold(player) < d.cost and "Not enough gold" or nil,
      fn = function()
        player.inventory.gold = player.inventory.gold - d.cost
        audio.play("buy")
        o.diff = d
        o.state, o.countT, o.beepN = "count", COUNT_TIME, COUNT_TIME + 1
        say(o, "Ready your gun...", o.x + CARNY_DX)
      end,
    }
  end
  eventui.shrine(o, player, offers, {
    title = "The Shooting Gallery",
    subtitle = "Hit the moving targets in " .. CARNIVAL_TIME .. " seconds. A count of " .. COUNT_TIME .. ", and they come out.",
    subtitleColor = { 0.95, 0.75, 0.45 },
    cardH = 160,
  })
end

-- Gambler's den ----------------------------------------------------------------

local SYMBOLS = {
  { name = "Cherry", w = 30, pay = 5 },
  { name = "Lemon", w = 25, pay = 8 },
  { name = "Bell", w = 20, pay = 12 },
  { name = "Star", w = 15, pay = 20 },
  { name = "Seven", w = 7, pay = 50 },
  { name = "Diamond", w = 3, pay = 100 },
}
local PAIR_PAY = 2.5
local SLOT_COST = 10
local TABLE_DX, SLOT_DX = -28, 40 -- the card table and the slot machine, either side of the den's middle

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

-- Pulling the slot machine's lever: it takes the coins, or says it needs them
local function playSlot(o, player)
  local now = love.timer.getTime()
  local sl = o.slot
  if sl and now < sl.endT then
    return
  end
  local sx = o.x + SLOT_DX
  if gold(player) < SLOT_COST then
    o.slot = sl or { reels = { 1, 2, 3 }, endT = 0, paid = true, win = 0, hitT = -9, leverT = -9 }
    o.slot.noT = now
    say(o, "Not enough gold. It takes " .. SLOT_COST .. ".", sx)
    audio.play("deny")
    return
  end
  player.inventory.gold = player.inventory.gold - SLOT_COST
  local r = { rollSymbol(), rollSymbol(), rollSymbol() }
  o.slot = {
    reels = r, from = sl and sl.reels or { 1, 2, 3 }, t0 = now, stops = { now + 1.1, now + 1.6, now + 2.1 },
    stopped = {}, endT = now + 2.45, leverT = now, paid = false, tick = 0, win = 0, hitT = -9, noT = -9,
  }
  o.say = nil
  audio.play("slot_coin")
  audio.play("slot_lever")
end

-- The reels turning, locking one by one, and the pay-out when the last has stopped
local function stepSlot(o, dt)
  local sl = o.slot
  if not sl or sl.paid then
    return
  end
  local now = love.timer.getTime()
  sl.tick = sl.tick - dt
  if sl.tick <= 0 and now < sl.stops[3] then
    sl.tick = 0.085
    audio.play("slot_tick", 0.6, 0.9 + love.math.random() * 0.3)
  end
  for i = 1, 3 do
    if not sl.stopped[i] and now >= sl.stops[i] then
      sl.stopped[i] = true
      audio.play("slot_stop", 0.7, 0.85 + i * 0.1)
    end
  end
  if now >= sl.stops[3] + 0.12 then
    sl.paid, sl.hitT = true, now
    local r = sl.reels
    local sx, g = o.x + SLOT_DX, o.y
    local win = 0
    if r[1] == r[2] and r[2] == r[3] then
      win = SYMBOLS[r[1]].pay * SLOT_COST
      say(o, "JACKPOT! Three " .. SYMBOLS[r[1]].name .. "s: " .. win .. " gold!", sx)
      audio.play("slot_jackpot")
    elseif r[1] == r[2] or r[2] == r[3] or r[1] == r[3] then
      win = math.floor(PAIR_PAY * SLOT_COST)
      say(o, "A pair! " .. win .. " gold.", sx)
      audio.play("slot_win")
    else
      say(o, "Nothing.", sx)
      audio.play("slot_lose")
    end
    sl.win = win
    if win > 0 then
      -- (the coins pour out of the tray, a pile of them for you to pick up)
      pickups.dropGold(sx, g - 10, win)
      sparkle(sx, g - 8, { 1, 0.85, 0.3 })
      popup(sx, g - 58, "+" .. win, { 1, 0.9, 0.3 })
    end
  end
end

-- Pays the stand's own prices, the cards' own rules (src.eventui)
local function gamblerTable(o, player)
  eventui.highlow(o, player, { sparkle = sparkle, dropCoins = function(x, y) sparkle(x, y, { 1, 0.85, 0.3 }) end })
end

-- Tinker -----------------------------------------------------------------------

local function tinkerDialog(o, player)
  eventui.tinker(o, player, { sparkle = sparkle, popup = popup })
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
  local offers = {
    {
      title = "Be Made Whole",
      text = "Lay gold on the stone and your wounds close: full health.",
      cost = "35 gold",
      icon = "heal",
      color = { 0.62, 0.55, 1.0 },
      cta = "Offer 35 gold",
      disabled = gold(player) < 35 and "Not enough gold" or nil,
      fn = function()
        player.inventory.gold = player.inventory.gold - 35
        player.hp = player.maxHp
        o.used = true
        audio.play("shrine_chime")
        sparkle(o.x, o.y - 14, { 0.7, 0.6, 1 })
        popup(o.x, o.y - 30, "Restored", { 0.7, 0.9, 1 })
      end,
    },
    {
      title = "Offer Blood",
      text = "Give up 20 health. The shrine answers with a rare boon for the rest of the run.",
      cost = "20 health",
      icon = "blood",
      color = { 0.95, 0.3, 0.38 },
      cta = "Offer your blood",
      disabled = player.hp <= 22 and "Too weak" or nil,
      fn = function()
        player:loseHealth(20)
        local boon = pickPerk("rare")
        o.used = true
        if boon then
          perks.add(boon)
          player:refreshMaxHp()
          popup(o.x, o.y - 30, perks.defs[boon].name, { 0.85, 0.6, 1 })
        end
        audio.play("shrine_chime")
        sparkle(o.x, o.y - 14, { 0.85, 0.5, 1 })
      end,
    },
    {
      title = "Pray",
      text = "Pay nothing. A coin toss: a rare item, or a curse of 15 health.",
      cost = "Free",
      icon = "prayer",
      color = { 0.95, 0.85, 0.5 },
      cta = "Pray",
      fn = function()
        o.used = true
        if love.math.random() < 0.5 then
          dropReward(o.x, o.y, 0, randomItem({ rare = true }))
          popup(o.x, o.y - 30, "The shrine provides", { 0.7, 1, 0.8 })
          audio.play("shrine_chime")
        else
          player.hp = math.max(1, player.hp - 15)
          popup(o.x, o.y - 30, "It wanted more", { 1, 0.5, 0.5 })
          audio.play("deny")
        end
      end,
    },
  }
  eventui.shrine(o, player, offers)
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

-- All the events standing now: the one on the timer, then the test room's
local function each(fn)
  if active then
    fn(active)
  end
  for _, s in ipairs(showcase) do
    if s.o then
      fn(s.o)
    end
  end
end

-- Hunt -------------------------------------------------------------------------

local HUNT_KINDS = { "ghoul", "miner", "roller" }
local HUNT_TIME = 120

local function startHunt(o, px, py, fx, fy)
  local kind = HUNT_KINDS[love.math.random(#HUNT_KINDS)]
  local x, gy = fx, fy
  if not x then
    x, gy = findSpot(px, py, 6, 150, 330)
  end
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

-- (fx, fy: a set spot on the ground, for the test room's stands)
local function spawn(kind, player, areaIndex, fx, fy)
  local px, py = player:center()
  local o = { kind = kind, age = 0, life = 170 }
  if fx then
    o.fixed, o.life = true, math.huge
  end
  if kind == "hunt" then
    o.life = fx and math.huge or HUNT_TIME + 40
    if not startHunt(o, px, py, fx, fy) then
      return nil
    end
    return o
  end
  local x, gy = fx, fy
  if not x then
    x, gy = findSpot(px, py, kind == "gambler" and 40 or (kind == "carnival" and 20 or 12), 70, 260)
  end
  if not x then
    return nil
  end
  o.x, o.y = x, gy
  if kind == "carnival" then
    o.state = "idle"
    o.title = "A carnival stall"
    -- (the carny's booth stands on whatever ground is out there, to the side)
    local cg = world:findGround(x + CARNY_DX, gy - 24)
    o.cy = (cg and math.abs(cg - gy) <= 10) and cg or gy
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
  if not fx then
    popup(x, gy - 40, names[kind], { 1, 0.9, 0.6 })
  end
  return o
end

-- One event's turn; true once it is over
local function step(o, dt, player)
  o.age = o.age + dt
  if o.say then
    o.say.age = o.say.age + dt
  end
  if o.kind == "gambler" then
    stepSlot(o, dt)
    o.life = o.life - dt
    if o.slot and love.timer.getTime() < o.slot.endT then
      o.life = math.max(o.life, 5) -- (never closes the den on a spinning reel)
    end
  elseif o.kind == "carnival" then
    if o.state == "count" then
      o.countT = o.countT - dt
      local n = math.ceil(o.countT)
      if n ~= o.beepN and n > 0 then
        o.beepN = n
        audio.play("count_beep")
      end
      if o.countT <= 0 then
        audio.play("count_go")
        startCarnival(o, o.diff, player)
        o.goT = 0.8
      end
    elseif o.state == "playing" then
      o.goT = o.goT and o.goT - dt or nil
      o.timeLeft = o.timeLeft - dt
      if o.timeLeft <= 0 then
        finishCarnival(o, player)
      end
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
      return true
    elseif o.fixed then
      o.timeLeft = HUNT_TIME -- (the test room's beast never runs out its clock)
    elseif o.timeLeft <= -30 then
      return true
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
    if o.fixed and o.used then
      -- (a spent shrine is lit again after a while)
      o.usedT = (o.usedT or 0) + dt
      if o.usedT > 6 then
        o.life = 0
      end
    end
  end
  if o.life and o.life <= 0 and (o.kind ~= "carnival" or (o.state ~= "playing" and o.state ~= "count")) then
    if o.kind == "carnival" and o.targets then
      for _, t in ipairs(o.targets) do
        targets.remove(t)
      end
    end
    return true
  end
  return false
end

function randevents.update(dt, player, areaIndex, w)
  world = w or world
  if not world then
    return
  end
  for _, s in ipairs(showcase) do
    if s.o then
      if step(s.o, dt, player) then
        s.o, s.wait = nil, 3
      end
    else
      s.wait = s.wait - dt
      if s.wait <= 0 then
        s.o = spawn(s.kind, player, 1, s.x, s.y)
        s.wait = 3
      end
    end
  end
  if not active then
    if areaIndex and meta.profileActive() and not player.dead then
      timer = timer - dt
      if timer <= 0 then
        timer = 240 + love.math.random() * 240
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
  if step(active, dt, player) then
    active = nil
  end
end

-- The test room: a permanent stand of the given kind on the ground at (x, ground)
-- that comes back a moment after it is spent (events go on while the hunter is there)
function randevents.addStand(kind, x, ground, w)
  world = w or world
  showcase[#showcase + 1] = { kind = kind, x = x, y = ground, wait = 0 }
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

-- Where an event can be spoken to: the carny, the card table or the slot machine, the tinker, the shrine
local function spots(o)
  if o.kind == "carnival" then
    return { { id = "carny", x = o.x + CARNY_DX, y = o.cy or o.y } }
  elseif o.kind == "gambler" then
    return { { id = "table", x = o.x + TABLE_DX, y = o.y }, { id = "slot", x = o.x + SLOT_DX, y = o.y } }
  elseif o.kind == "tinker" then
    return { { id = "tinker", x = o.x + 12, y = o.y } }
  elseif o.kind == "shrine" then
    return { { id = "shrine", x = o.x, y = o.y } }
  end
  return {}
end

-- The nearest place within reach, if any
local function near(o, px, py)
  if not o or o.kind == "hunt" then
    return nil
  end
  local best, bd = nil, 30
  for _, sp in ipairs(spots(o)) do
    local d = dist(sp, px, py)
    if d < bd then
      best, bd = sp, d
    end
  end
  return best
end

function randevents.interact(player)
  if player.dead then
    return false
  end
  local px, py = player:center()
  local o, sp
  each(function(c)
    if not o then
      sp = near(c, px, py)
      if sp then
        o = c
      end
    end
  end)
  if not o then
    return false
  end
  if sp.id == "carny" then
    if o.state == "idle" or o.state == "done" then
      carnivalDialog(o, player)
    elseif o.state == "count" then
      say(o, "Steady...", sp.x)
    else
      say(o, "Eyes on the targets!", sp.x)
    end
  elseif sp.id == "table" then
    gamblerTable(o, player)
  elseif sp.id == "slot" then
    playSlot(o, player)
    return true
  elseif sp.id == "tinker" then
    tinkerDialog(o, player)
  elseif sp.id == "shrine" then
    if o.used then
      say(o, "The flame has gone quiet.")
    else
      shrineDialog(o, player)
    end
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
  local RED, CREAM = { 0.85, 0.15, 0.18 }, { 0.92, 0.90, 0.82 }
  -- the rail posts and the awning
  R(WOOD_D, x - 66, g - 62, 3, 62)
  R(WOOD, x - 66, g - 62, 1, 62)
  R(WOOD_D, x + 63, g - 62, 3, 62)
  R(WOOD, x + 63, g - 62, 1, 62)
  R(WOOD, x - 67, g - 65, 134, 3)
  R(WOOD_L, x - 67, g - 65, 134, 1)
  for i = 0, 10 do
    R(i % 2 == 0 and RED or CREAM, x - 66 + i * 12, g - 71, 12, 6)
    R(i % 2 == 0 and { 0.62, 0.10, 0.13 } or { 0.74, 0.72, 0.64 }, x - 66 + i * 12, g - 66, 12, 1)
  end
  -- the back wall: boards the targets pass in front of
  for yy = g - 61, g - 15, 5 do
    R({ 0.20, 0.13, 0.10, 0.55 }, x - 62, yy, 126, 1)
  end
  -- the counter in front
  R(WOOD, x - 30, g - 12, 60, 12)
  R(WOOD_L, x - 30, g - 12, 60, 2)
  R(WOOD_D, x - 28, g - 8, 56, 1)
  R(WOOD_D, x - 30, g - 1, 60, 1)
  -- pennants
  for i = 0, 5 do
    local sway = math.floor(math.sin(t * 2 + i) * 1)
    R(i % 2 == 0 and { 0.95, 0.75, 0.2 } or { 0.3, 0.6, 0.9 }, x - 62 + i * 24, g - 59 + sway, 5, 6)
    R({ 0.2, 0.15, 0.1 }, x - 62 + i * 24, g - 59 + sway + 6, 1, 1)
  end
  -- the carny's booth, off to the right of the stall, and the carny himself
  local cx, cg = x + CARNY_DX, o.cy or g
  R(WOOD_D, cx - 22, cg - 40, 2, 40)
  R(WOOD_D, cx + 18, cg - 40, 2, 40)
  R(WOOD, cx - 24, cg - 42, 46, 3)
  for i = 0, 7 do
    R(i % 2 == 0 and RED or CREAM, cx - 24 + i * 6, cg - 46, 6, 4)
  end
  people.draw("carny", cx + 6, cg, -1, o.state == "playing" and "stand" or "work", (t * 0.5) % 1)
  R(WOOD, cx - 22, cg - 11, 22, 11)
  R(WOOD_L, cx - 22, cg - 11, 22, 2)
  R(WOOD_D, cx - 20, cg - 7, 18, 1)
  -- a bell on the counter, and the prizes on a shelf
  R({ 0.9, 0.7, 0.25 }, cx - 18, cg - 14, 4, 3)
  R({ 0.6, 0.45, 0.15 }, cx - 18, cg - 12, 4, 1)
  R(WOOD, cx - 22, cg - 32, 18, 1)
  for i = 0, 2 do
    local c = ({ { 0.85, 0.3, 0.4 }, { 0.35, 0.6, 0.9 }, { 0.9, 0.8, 0.3 } })[i + 1]
    R(c, cx - 21 + i * 6, cg - 37, 4, 5)
    R({ c[1] * 0.6, c[2] * 0.6, c[3] * 0.6 }, cx - 21 + i * 6, cg - 33, 4, 1)
    R({ 0.1, 0.08, 0.08 }, cx - 20 + i * 6, cg - 36, 1, 1)
  end
  -- the count, painted on the back wall of the stall itself
  if o.state == "count" then
    eventart.bigText(tostring(math.max(1, math.ceil(o.countT))), x, g - 36, 4, { 1, 0.9, 0.4 })
  elseif o.goT and o.goT > 0 then
    eventart.bigText("GO!", x, g - 36, 4, { 0.5, 1, 0.5 })
  end
  if o.state == "playing" then
    local bar = math.max(0, o.timeLeft / CARNIVAL_TIME)
    R({ 0.1, 0.1, 0.12 }, x - 30, g - 82, 60, 4)
    R({ 0.95, 0.75, 0.2 }, x - 30, g - 82, math.floor(60 * bar), 4)
  end
end

-- The slot machine's reels, scrolled a number of pixels down the strip (it wraps round)
local reelQuad
local function drawReel(strip, off, rx, ry)
  local h = eventart.SYMBOL_STEP * #SYMBOLS
  off = math.floor(off) % h
  local sw = eventart.SYMBOL_W
  reelQuad = reelQuad or love.graphics.newQuad(0, 0, 1, 1, 1, 1)
  local first = math.min(7, h - off)
  love.graphics.setColor(1, 1, 1)
  reelQuad:setViewport(0, off, sw, first, sw, h)
  love.graphics.draw(strip, reelQuad, rx, ry)
  if first < 7 then
    reelQuad:setViewport(0, 0, sw, 7 - first, sw, h)
    love.graphics.draw(strip, reelQuad, rx, ry + first)
  end
end

local function drawSlotMachine(o, t)
  local sl = o.slot
  local now = love.timer.getTime()
  local x, g = o.x + SLOT_DX, o.y
  local spinning = sl and now < sl.endT and not sl.paid
  local won = sl and sl.paid and sl.win > 0 and now - sl.hitT < 3
  local denied = sl and now - (sl.noT or -9) < 1.2
  local RED, REDL, REDD = { 0.58, 0.09, 0.12 }, { 0.80, 0.20, 0.20 }, { 0.34, 0.05, 0.08 }
  local GOLD, GOLDD, GOLDL = { 0.92, 0.72, 0.24 }, { 0.62, 0.45, 0.12 }, { 1.0, 0.92, 0.55 }
  -- the cabinet
  R(REDD, x - 14, g - 4, 28, 4)
  R(GOLDD, x - 14, g - 4, 28, 1)
  R(RED, x - 13, g - 38, 26, 34)
  R(REDL, x - 13, g - 38, 2, 34)
  R(REDD, x + 11, g - 38, 2, 34)
  R(GOLDD, x - 13, g - 38, 26, 1)
  R(RED, x - 12, g - 46, 24, 8)
  R(GOLD, x - 12, g - 46, 24, 1)
  R(REDD, x - 12, g - 39, 24, 1)
  -- the marquee: bulbs that chase while it spins, flash when it pays, blink red when it wants coin
  for i = 0, 4 do
    local on, c
    if denied then
      on, c = math.floor(now * 8) % 2 == 0, { 1, 0.25, 0.2 }
    elseif won then
      on, c = math.floor(now * 12 + i) % 2 == 0, { 1, 0.95, 0.5 }
    elseif spinning then
      on, c = (math.floor(now * 12) + i) % 3 == 0, { 1, 0.85, 0.3 }
    else
      on, c = math.floor(now * 1.5 + i * 1.7) % 4 == 0, { 0.95, 0.75, 0.25 }
    end
    R(on and c or { 0.30, 0.20, 0.08 }, x - 9 + i * 5, g - 43, 3, 3)
  end
  -- the window: dark behind the reels, three reels, and a line across the middle
  R(GOLDD, x - 12, g - 37, 25, 11)
  R({ 0.04, 0.035, 0.06 }, x - 11, g - 36, 23, 9)
  local strip = eventart.reelStrip()
  local step = eventart.SYMBOL_STEP
  for i = 1, 3 do
    local rx = x - 11 + (i - 1) * 8
    local fin = sl and sl.reels[i] or i
    local target = (fin - 1) * step
    local off = target
    if sl and not sl.paid and sl.stops and now < sl.stops[i] then
      local rem = sl.stops[i] - now
      off = target - 230 * rem * math.min(1, 0.3 + rem * 1.3)
    end
    drawReel(strip, off, rx, g - 35)
    R({ 0, 0, 0, 0.35 }, rx, g - 35, 7, 1)
    R({ 0, 0, 0, 0.35 }, rx, g - 29, 7, 1)
  end
  R({ 0.9, 0.15, 0.15, 0.4 }, x - 11, g - 32, 23, 1)
  -- the price plate and the coin slot
  R(REDD, x - 11, g - 24, 22, 9)
  R(GOLD, x - 9, g - 22, 4, 4)
  R(GOLDL, x - 9, g - 22, 2, 2)
  eventart.tinyText(SLOT_COST, x - 3, g - 22, { 1, 0.95, 0.75 })
  R({ 0.04, 0.03, 0.05 }, x + 5, g - 22, 5, 1)
  R(GOLDD, x + 4, g - 23, 7, 1)
  R(GOLDD, x + 4, g - 21, 7, 1)
  -- the tray: coins glint in it after a win
  R(GOLDD, x - 9, g - 12, 18, 6)
  R({ 0.05, 0.04, 0.06 }, x - 8, g - 11, 16, 4)
  if won then
    for i = 0, 4 do
      R(math.floor(now * 6 + i) % 2 == 0 and GOLDL or GOLD, x - 7 + i * 3, g - 9, 2, 2)
    end
  end
  -- the lever, on the right: pulled down and let back
  R({ 0.40, 0.40, 0.46 }, x + 14, g - 34, 2, 14)
  R({ 0.62, 0.62, 0.68 }, x + 14, g - 34, 1, 14)
  local pull = 0
  if sl then
    local k = (now - sl.leverT) / 0.4
    pull = k < 0 and 0 or (k < 0.5 and k * 2 or (k < 1 and 1 - (k - 0.5) * 2 or 0))
  end
  local by = g - 40 + math.floor(pull * 12)
  R({ 0.7, 0.1, 0.12 }, x + 13, by, 4, 4)
  R({ 1, 0.5, 0.5 }, x + 13, by, 2, 2)
end

local function drawGambler(o, t)
  local x, g = o.x, o.y
  local tx = x + TABLE_DX
  -- the dealer stands behind the table
  people.draw("dealer", tx + 6, g, -1, "work", (t * 0.4) % 1)
  -- the table: green baize, with cards and a stack of chips
  R(WOOD_D, tx - 17, g - 12, 3, 12)
  R(WOOD_D, tx + 14, g - 12, 3, 12)
  R({ 0.34, 0.22, 0.12 }, tx - 20, g - 15, 40, 3)
  R({ 0.58, 0.40, 0.22 }, tx - 20, g - 15, 40, 1)
  R({ 0.10, 0.36, 0.22 }, tx - 19, g - 17, 38, 2)
  R({ 0.16, 0.50, 0.30 }, tx - 19, g - 17, 38, 1)
  for i = 0, 2 do
    R({ 0.96, 0.94, 0.86 }, tx - 12 + i * 2, g - 21 - i, 6, 4)
    R({ 0.62, 0.10, 0.16 }, tx - 11 + i * 2, g - 20 - i, 4, 2)
  end
  R({ 0.96, 0.94, 0.86 }, tx + 2, g - 20, 6, 3)
  R({ 0.8, 0.12, 0.14 }, tx + 4, g - 19, 2, 1)
  for i = 0, 2 do
    R(({ { 0.9, 0.2, 0.2 }, { 0.2, 0.4, 0.9 }, { 0.95, 0.8, 0.25 } })[i + 1], tx + 11, g - 19 - i * 2, 5, 2)
    R({ 1, 1, 1, 0.5 }, tx + 11, g - 19 - i * 2, 5, 1)
  end
  drawSlotMachine(o, t)
end

local function drawTinker(o, t)
  local x, g = o.x, o.y
  -- a handcart on a big wheel, pots and pans hanging off it
  R(WOOD_D, x - 20, g - 19, 32, 3)
  R(WOOD, x - 20, g - 24, 32, 6)
  R(WOOD_L, x - 20, g - 24, 32, 1)
  R(WOOD_D, x - 20, g - 24, 1, 6)
  R({ 0.50, 0.50, 0.55 }, x - 16, g - 30, 6, 6)
  R({ 0.78, 0.78, 0.82 }, x - 16, g - 30, 6, 1)
  R({ 0.72, 0.46, 0.20 }, x - 6, g - 32, 5, 8)
  R({ 0.90, 0.66, 0.34 }, x - 6, g - 32, 1, 8)
  R({ 0.35, 0.55, 0.40 }, x + 2, g - 29, 6, 5)
  R(WOOD_D, x - 22, g - 26, 2, 8) -- (the handles)
  R(WOOD_D, x - 24, g - 26, 2, 1)
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(eventart.wheel(math.floor(t * 3)), x - 15, g - 15)
  R(WOOD_D, x + 10, g - 19, 12, 2)
  -- the tinker, bent under a pack, and a swinging lantern
  people.draw("tinker", x + 22, g, -1, "work", (t * 0.6) % 1)
  R({ 0.55, 0.42, 0.25 }, x + 24, g - 17, 5, 9)
  R({ 0.38, 0.28, 0.16 }, x + 24, g - 17, 5, 1)
  local sway = math.floor(math.sin(t * 3) * 1.4 + 0.5)
  R({ 0.55, 0.56, 0.6 }, x + 30, g - 27, 1, 4)
  R({ 0.95, 0.75, 0.30 }, x + 29 + sway, g - 23, 3, 4)
  R({ 1, 0.95, 0.7 }, x + 30 + sway, g - 22, 1, 2)
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

local function drawOne(o, view)
  if not o.x or o.x < view.x - 100 or o.x > view.x + view.w + 100 then
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

function randevents.draw(view)
  each(function(o)
    drawOne(o, view)
  end)
end

local function lightOne(lighting, o)
  if not o.x or o.kind == "hunt" then
    return
  end
  if o.kind == "shrine" and not o.used then
    lighting.add(o.x, o.y - 20, 60, 0.55, 0.5, 1, 0.8)
  elseif o.kind == "carnival" then
    lighting.add(o.x, o.y - 40, 90, 1, 0.8, 0.45, 0.8)
    lighting.add(o.x + CARNY_DX, (o.cy or o.y) - 30, 40, 1, 0.75, 0.4, 0.7)
  elseif o.kind == "gambler" then
    lighting.add(o.x + TABLE_DX, o.y - 30, 60, 0.6, 1, 0.65, 0.65)
    -- (the slot machine's glow shows what it is doing)
    local sl, now = o.slot, love.timer.getTime()
    if sl and now - (sl.noT or -9) < 1.2 then
      lighting.add(o.x + SLOT_DX, o.y - 26, 36, 1, 0.25, 0.2, 0.45)
    elseif sl and sl.paid and sl.win > 0 and now - sl.hitT < 3 then
      lighting.add(o.x + SLOT_DX, o.y - 26, 48, 1, 0.9, 0.4, 0.4 + 0.2 * math.sin(now * 14))
    elseif sl and now < sl.endT then
      lighting.add(o.x + SLOT_DX, o.y - 26, 38, 1, 0.8, 0.4, 0.35)
    else
      lighting.add(o.x + SLOT_DX, o.y - 26, 30, 1, 0.75, 0.35, 0.2)
    end
  elseif o.kind == "tinker" then
    lighting.add(o.x + 26, o.y - 22, 55, 1, 0.8, 0.4, 0.7)
  end
end

function randevents.addLights(lighting, view)
  each(function(o)
    lightOne(lighting, o)
  end)
end

-- (a prompt set beside something rather than over it: its text starts at the point)
local function promptSide(font, toScreen, wx, wy, text)
  local sx, sy = toScreen(wx, wy)
  love.graphics.setFont(font)
  local x, y = math.floor(sx), math.floor(sy - font:getHeight() / 2)
  love.graphics.setColor(0, 0, 0, 0.85)
  love.graphics.print(text, x + 2, y + 2)
  love.graphics.setColor(1, 0.88, 0.6)
  love.graphics.print(text, x, y)
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

local function screenOne(o, toScreen, font, player)
  if o.say and o.x then
    -- (the speech sits well above the prompt, which hangs at the speaker's chest)
    local bx = o.say.x or o.x
    local sx, sy = toScreen(bx, o.y - 46)
    require("src.npcs").bubble(font, o.say.text, sx, sy, o.say.age)
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
    prompt(font, toScreen, o.x, o.y - 84, string.format("Hits: %d / %d   Time: %d", o.hits, o.diff.goal, math.ceil(o.timeLeft)))
  elseif o.kind == "cavein" and o.state == nil then
    local text = string.format("Dig him out!  %d s", math.max(0, math.ceil(o.timeLeft)))
    prompt(font, toScreen, o.x, o.y - MOUND_H - 14, text)
  else
    local sp = near(o, px, py)
    if sp then
      local sl = o.slot
      local text = ({
        carny = (o.state == "playing" or o.state == "count") and nil or "Try the shooting gallery",
        table = "Sit at the table",
        slot = (sl and love.timer.getTime() < sl.endT) and nil or "Play!",
        tinker = "Trade with the tinker",
        shrine = o.used and nil or "Kneel at the shrine",
      })[sp.id]
      if text and sp.id == "slot" then
        promptSide(font, toScreen, sp.x + 20, sp.y - 24, key .. text)
      elseif text then
        prompt(font, toScreen, sp.x, sp.y - 26, key .. text)
      end
    end
  end
end

function randevents.drawScreen(toScreen, font, player)
  if require("src.menu").isOpen() then
    return
  end
  each(function(o)
    screenOne(o, toScreen, font, player)
  end)
end

return randevents
