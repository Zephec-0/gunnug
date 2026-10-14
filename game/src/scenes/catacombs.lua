-- The generated areas under the Barrens (design doc §3, §7): the Catacombs,
-- the Sunken Hollows below them, then the Sulfur Vents, each ending at a shop
-- room whose hatch drops into the next. The Vents end differently: a huge
-- boss arena (the Sulfur Queen's) fills their last quarter, and below it, once
-- the Queen is dead, are two shops, left and right, each leading to its own
-- area (the Cinder Warrens on the left, the Drowned Halls on the right).
-- Entering one shop collapses the shaft to the other. Not scenes of their own:
-- the overworld scene owns the whole world and hands this module the region
-- below the surface.
--
-- Generation takes a few seconds per area, so each area runs as a coroutine a
-- few milliseconds per frame, in order, in the background while the hunter is
-- still above it (no loading screen). catacombs.ensure(y) completes any area
-- the hunter is getting close to, if it isn't done yet.
local cavegen = require("src.cavegen")
local chests = require("src.chests")
local audio = require("src.audio")
local effects = require("src.effects")
local enemies = require("src.enemies")
local fluids = require("src.fluids")
local hud = require("src.hud")
local materials = require("src.materials")
local minedecor = require("src.minedecor")
local physics = require("src.physics")
local props = require("src.props")
local shop = require("src.shop")

local catacombs = {}

-- How each area looks: palette, light, the glowing mushrooms (or crystals)
-- that light the way, the backdrop behind the rock and the far rock pillars
-- (dark face, rim light, cracks). glowCount is per 1920x3680 of area.
local THEMES = {
  {
    name = "The Catacombs",
    subtitle = "Area 1",
    ambient = { 0.36, 0.32, 0.44 },
    palette = nil, -- the default rock and dirt
    glow = { 0.35, 0.95, 0.85 }, -- teal fungus
    glowCount = 150,
    glowRadius = 34,
    stalk = { 0.55, 0.62, 0.55 },
    backTop = { 0.10, 0.08, 0.14 },
    backDeep = { 0.06, 0.05, 0.09 },
    pillars = { { 0.03, 0.025, 0.05 }, { 0.16, 0.13, 0.22 }, { 0.10, 0.08, 0.15 } },
    monsters = { ghoul = 38, bat = 28, spitter = 14, hopper = 6, miner = 28, roller = 10, worm = 12 }, -- per 1920x3680; an old mine: skeletal miners, rollers and worms in the rock
    boss = { "warden", "dreadbat" }, -- one of the two, chosen per run
    waterPools = 30,
    swarms = { swarmbat = 4 }, -- colonies of bats under the ceilings
    -- Breakables beside the crates { prop, count per 1920x3680 }: pots and pouches of coin, candle-lit skulls and lanterns
    breakables = { { "urn", 14 }, { "pouch", 12 }, { "lantern", 8 }, { "skullCandle", 8 }, { "sporePod", 6 }, { "tntBarrel", 22 }, { "tntBarrel", 8 }, { "crate", 12 } },
    mine = true, -- an old mine: rails and carts, shoring, oil lamps, skeletons, pickaxes, TNT
    stalactites = 150,
  },
  {
    name = "The Sunken Hollows",
    subtitle = "Area 2",
    ambient = { 0.17, 0.21, 0.31 }, -- darker and colder
    palette = { rock = materials.SLATE, dirt = materials.BLUECLAY },
    glow = { 0.35, 1.0, 0.45 }, -- green mushrooms, lots of them
    glowCount = 480,
    glowRadius = 40,
    stalk = { 0.45, 0.62, 0.50 },
    backTop = { 0.045, 0.06, 0.105 },
    backDeep = { 0.03, 0.04, 0.075 },
    pillars = { { 0.02, 0.03, 0.05 }, { 0.10, 0.14, 0.22 }, { 0.06, 0.08, 0.14 } },
    monsters = { ghoul = 20, bat = 14, spitter = 20, hopper = 44, bloater = 10, worm = 12, roller = 14, miner = 5 }, -- a fen: hoppers everywhere
    boss = "matron",
    waterPools = 60,
    swarms = { swarmbat = 2 },
    breakables = { { "sporePod", 36 }, { "urn", 10 }, { "pouch", 14 }, { "lantern", 8 } }, -- glowing spore pods in the fen
    stalactites = 70,
  },
  {
    name = "The Sulfur Vents",
    subtitle = "Area 3",
    ambient = { 0.40, 0.40, 0.24 }, -- a murky yellow-green
    palette = { rock = materials.SULFUR, dirt = materials.BILECLAY },
    glow = { 1.0, 0.92, 0.35 }, -- sulfur crystals
    glowLight = 0.4, -- (yellow reads far brighter than the other areas' tints, so they give less light)
    glowCount = 220,
    glowRadius = 36,
    crystals = true,
    stalk = { 0.80, 0.72, 0.30 },
    backTop = { 0.085, 0.09, 0.04 },
    backDeep = { 0.05, 0.055, 0.025 },
    pillars = { { 0.035, 0.035, 0.012 }, { 0.20, 0.20, 0.08 }, { 0.11, 0.11, 0.05 } },
    monsters = { ghoul = 14, bat = 10, spitter = 12, hopper = 8, bloater = 46, wisp = 40, worm = 12, roller = 8, miner = 8 }, -- gas bags and fire wisps
    boss = "queen", -- the Sulfur Queen, in the arena that fills the last quarter
    arena = true,
    gasPools = 34, -- pools of poison gas in low spots (src.fluids)
    waterPools = 22,
    swarms = { swarmbat = 2, wisp = 3 }, -- and flocks of wisps
    breakables = { { "geode", 30 }, { "urn", 10 }, { "pouch", 12 }, { "lantern", 10 } }, -- sulfur geodes that glow (no open flames: the gas)
    stalactites = 40,
  },
  {
    -- Left of the Queen's arena (area 4a): scorched basalt and ash, ember light
    name = "The Cinder Warrens",
    subtitle = "Area 4 - left path",
    ambient = { 0.40, 0.27, 0.24 },
    palette = { rock = materials.BASALT, dirt = materials.ASH },
    glow = { 1.0, 0.55, 0.25 }, -- embers in the cracks
    glowCount = 260,
    glowRadius = 38,
    stalk = { 0.62, 0.34, 0.22 },
    backTop = { 0.10, 0.05, 0.045 },
    backDeep = { 0.06, 0.03, 0.03 },
    pillars = { { 0.04, 0.02, 0.02 }, { 0.26, 0.12, 0.08 }, { 0.14, 0.06, 0.05 } },
    monsters = { ghoul = 30, bat = 16, spitter = 18, hopper = 4, wisp = 36, worm = 14, roller = 14, miner = 14 },
    swarms = { swarmbat = 3, wisp = 3 },
    waterPools = 14,
    breakables = { { "emberPot", 30 }, { "urn", 16 }, { "pouch", 14 }, { "skullCandle", 14 }, { "lantern", 8 } },
    stalactites = 80,
  },
  {
    -- Right of the Queen's arena (area 4b): a flooded slate maze
    name = "The Drowned Halls",
    subtitle = "Area 4 - right path",
    ambient = { 0.14, 0.24, 0.30 },
    palette = { rock = materials.SLATE, dirt = materials.BLUECLAY },
    glow = { 0.35, 0.85, 1.0 }, -- cyan glowcaps
    glowCount = 420,
    glowRadius = 40,
    stalk = { 0.40, 0.58, 0.62 },
    backTop = { 0.035, 0.07, 0.09 },
    backDeep = { 0.02, 0.045, 0.06 },
    pillars = { { 0.015, 0.035, 0.05 }, { 0.08, 0.17, 0.24 }, { 0.05, 0.10, 0.15 } },
    monsters = { ghoul = 10, bat = 10, spitter = 16, hopper = 52, bloater = 18, worm = 12, roller = 10, miner = 4 },
    swarms = { swarmbat = 3 },
    waterPools = 100,
    breakables = { { "sporePod", 30 }, { "geode", 12 }, { "urn", 16 }, { "pouch", 14 }, { "lantern", 12 } },
    stalactites = 90,
  },
}

-- How the areas are laid out: three in a column (rows 1-3), then the two
-- Queen's-shop areas side by side in row 4, each under half the world's width
local LAYOUT = {
  { row = 1 },
  { row = 2 },
  { row = 3 },
  { row = 4, side = "left", parent = 3, half = 1 },
  { row = 4, side = "right", parent = 3, half = 2 },
}

local levels = {} -- levels[i] = { theme, area, job, info, propsSpawned, shopReached }
local world
local firstArea, baseSeed
local levelHeight = 0
local deadline = 0 -- os.clock() time the current slice of work must stop at
local announced = {} -- the areas whose banner has been shown

function catacombs.count()
  return #levels
end

function catacombs.theme(i)
  return THEMES[i] or THEMES[#THEMES]
end

-- Starts the areas under the surface. first: the first area's rectangle and
-- entrance (see cavegen.generate); rows: how many rows of areas lie below the
-- surface (4 is the whole layout, 3 stops after the Sulfur Vents).
function catacombs.start(w, first, seed, rows)
  world, firstArea, baseSeed = w, first, seed
  levelHeight = first.y1 - first.y0 + 1
  levels = {}
  announced = {}
  fluids.clear()
  local mid = math.floor((first.x0 + first.x1 + 1) / 2)
  for i, l in ipairs(LAYOUT) do
    if l.row <= (rows or 1) then
      local x0, x1 = first.x0, first.x1
      if l.half == 1 then
        x1 = mid - 1
      elseif l.half == 2 then
        x0 = mid
      end
      levels[i] = {
        theme = THEMES[i],
        index = i,
        row = l.row,
        parent = l.parent,
        side = l.side,
        x0 = x0,
        x1 = x1,
        y0 = first.y0 + (l.row - 1) * levelHeight,
      }
    end
  end
  -- The boss's death opens the arena's gates
  enemies.onBossKilled = function(e)
    for _, lv in ipairs(levels) do
      if lv.info and lv.info.arena and e.areaIndex == lv.index then
        catacombs.openGates(lv)
      end
    end
  end
end

-- The area (index) that the shop j (1 = left, 2 = right) of area i leads to
local function childOf(i, j)
  for k, l in ipairs(levels) do
    if k > 1 and (l.parent or k - 1) == i and (not l.side or (l.side == "left") == (j == 1)) then
      return k
    end
  end
  return nil
end

-- The area spec for level i, built from the area above once that is generated
local function areaFor(i)
  local lv = levels[i]
  local base = {}
  if i == 1 then
    for k, v in pairs(firstArea) do
      base[k] = v
    end
  else
    local parent = levels[lv.parent or (i - 1)]
    local hatch = parent.info.shops[lv.side == "right" and 2 or 1].hatch
    base = {
      x0 = lv.x0,
      x1 = lv.x1,
      y0 = lv.y0,
      y1 = lv.y0 + levelHeight - 1,
      entranceX = hatch.cx,
      entranceY = lv.y0 + 96,
      shaftX0 = hatch.x0,
      shaftX1 = hatch.x1,
      shaftTop = hatch.y1 + 1,
    }
  end
  base.level = lv.row
  base.palette = lv.theme.palette
  base.arena = lv.theme.arena
  base.glowCount = lv.theme.glowCount
  base.breakables = lv.theme.breakables
  base.mine = lv.theme.mine
  base.stalactites = lv.theme.stalactites
  base.gasPools = lv.theme.gasPools
  base.waterPools = lv.theme.waterPools
  base.monsters = lv.theme.monsters
  base.boss = lv.theme.boss
  base.swarms = lv.theme.swarms
  base.hasNext = childOf(i, 1) ~= nil
  return base
end

local function tick()
  if os.clock() > deadline then
    coroutine.yield()
  end
end

-- Runs the coroutine of level i for up to `budget` seconds (creating it first)
local function resume(i, budget)
  local lv = levels[i]
  if not lv.job then
    local area = areaFor(i)
    lv.area = area
    lv.job = coroutine.create(function()
      return cavegen.generate(world, area, baseSeed + (i - 1) * 7919, tick)
    end)
  end
  deadline = os.clock() + budget
  local ok, result = coroutine.resume(lv.job)
  if not ok then
    error(debug.traceback(lv.job, result))
  end
  if coroutine.status(lv.job) == "dead" then
    lv.job, lv.info = nil, result
    if result.arena and result.arena.platforms then
      world.platforms = world.platforms or {}
      for _, p in ipairs(result.arena.platforms) do
        world.platforms[#world.platforms + 1] = p
      end
    end
  end
end

local function nextUnfinished()
  for i, lv in ipairs(levels) do
    if not lv.info then
      return i
    end
  end
  return nil
end

-- Spends up to budget seconds on generation; call once per frame
function catacombs.step(budget)
  local i = nextUnfinished()
  if i then
    resume(i, budget)
  end
end

-- Completes generation of every area up to and including level `upTo` (default: all)
function catacombs.finish(upTo)
  for i = 1, math.min(upTo or #levels, #levels) do
    while not levels[i].info do
      resume(i, math.huge)
    end
  end
end

-- Makes sure the area the hunter is heading into exists: any area whose top
-- is within 900 px below him is completed now if it isn't already
function catacombs.ensure(py)
  for i, lv in ipairs(levels) do
    -- (the first area is completed by the scene when the hunter goes underground)
    if i > 1 and not lv.info and py > lv.y0 - 900 then
      catacombs.finish(i)
    end
  end
end

function catacombs.ready()
  return levels[1] ~= nil and levels[1].info ~= nil
end

-- An area's layout (default the first: where the F10 shortcut spawns), or
-- nil until it is generated
function catacombs.info(i)
  return levels[i or 1] and levels[i or 1].info
end

-- The area (1-based index) a world position lies in, or nil above them all.
-- x only matters in row 4, where two areas sit side by side.
function catacombs.levelAt(y, x)
  if not firstArea or y < firstArea.y0 then
    return nil
  end
  local row = math.floor((y - firstArea.y0) / levelHeight) + 1
  local fallback
  for i, lv in ipairs(levels) do
    if lv.row == row then
      fallback = fallback or i
      if x and x >= lv.x0 and x <= lv.x1 then
        return i
      end
    end
  end
  return fallback or #levels
end

-- Backdrop colour behind the rock at depth y (inside the areas); x picks the
-- side in row 4
function catacombs.backdrop(y, x)
  local i = catacombs.levelAt(y, x) or 1
  local t = THEMES[i] or THEMES[#THEMES]
  local d = math.min(1, (y - levels[i].y0) / (levelHeight * 0.8))
  return t.backTop[1] + (t.backDeep[1] - t.backTop[1]) * d,
    t.backTop[2] + (t.backDeep[2] - t.backTop[2]) * d,
    t.backTop[3] + (t.backDeep[3] - t.backTop[3]) * d
end

-- Scatters crates, chests, monsters and the shop stock through every area
-- that exists. Needs the physics world, so the scene calls it after setting
-- that up (and the area update calls it every frame after).
function catacombs.spawnProps()
  for i, lv in ipairs(levels) do
    local info = lv.info
    if info and not lv.propsSpawned then
      lv.propsSpawned = true
      -- Resting objects start asleep: their terrain outlines are only traced
      -- once something wakes them, instead of all in the same frame
      for _, s in ipairs(info.crates) do
        props.spawn("crate", s[1], s[2] - 7).body:setAwake(false)
      end
      for _, s in ipairs(info.ironCrates) do
        props.spawn("ironCrate", s[1], s[2] - 8.5).body:setAwake(false)
      end
      for _, group in ipairs(info.breakables or {}) do
        local def = props.defs[group.name]
        for _, s in ipairs(group.spots) do
          props.spawn(group.name, s[1], s[2] - def.height / 2 - 0.5, 0, lv.theme.glow).body:setAwake(false)
        end
      end
      for _, cart in ipairs(info.mine and info.mine.carts or {}) do
        props.spawn("minecart", cart.x, cart.y - 7).body:setAwake(false)
      end
      for j, room in ipairs(info.shops) do
        shop.populate(room, world, lv.row, childOf(i, j))
        enemies.spawn("dummy", shop.dummySpot(room))
      end
      fluids.add(world, info)
      -- Piranhas: a small school in every pool big enough (one per ~80 cells
      -- of 4 px, up to six), placed in cells with water above them too
      for _, pool in ipairs(info.water or {}) do
        local n = #pool.cells / 2
        local count = math.min(6, math.floor(n / 80))
        if count > 0 then
          local deep = {}
          local inPool = {}
          for c = 1, #pool.cells, 2 do
            inPool[pool.cells[c] .. "," .. pool.cells[c + 1]] = true
          end
          for c = 1, #pool.cells, 2 do
            local x, y = pool.cells[c], pool.cells[c + 1]
            if inPool[x .. "," .. (y - 4)] and inPool[(x - 4) .. "," .. y] and inPool[(x + 4) .. "," .. y] then
              deep[#deep + 1] = { x, y }
            end
          end
          for _ = 1, math.min(count, #deep) do
            local spot = table.remove(deep, love.math.random(#deep))
            enemies.spawn("piranha", spot[1] + 2, spot[2], 1 + (lv.row - 1) * 0.6, lv.row)
          end
        end
      end
      if info.arena then
        for _, br in ipairs(info.arena.braziers) do
          fluids.addBrazier(br.x, br.y)
        end
      end
      local a = info.area
      for _, c in ipairs(info.chests) do
        local depth = math.min(1, (c[2] - a.y0) / (a.y1 - a.y0) + (lv.row - 1) * 0.35)
        chests.spawn(c[1], c[2], depth)
      end
      local swarms = {}
      for _, m in ipairs(info.enemies) do
        local swarm
        if m.swarm then
          swarms[m.swarm] = swarms[m.swarm] or {}
          swarm = swarms[m.swarm]
        end
        local e = enemies.spawn(m.kind, m.x, m.y, m.toughness, lv.row, swarm)
        if m.boss then
          e.areaIndex = i
          if m.arena then
            e.arena = info.arena -- the boss stays inside it, and wakes when the hunter enters
          end
        end
      end
    end
  end
end

-- Banners as the hunter reaches each area, the shop-reached message, and gas
function catacombs.update(player, dt)
  catacombs.spawnProps()
  fluids.update(dt, player, enemies)
  local px, py = player:center()
  local at = catacombs.levelAt(py, px)
  if at and not announced[at] and py > levels[at].y0 then
    announced[at] = true
    hud.showBanner(levels[at].theme.name, levels[at].theme.subtitle .. "  -  seed " .. baseSeed)
  end
  local b = player.body
  for i, lv in ipairs(levels) do
    local info = lv.info
    if info then
      local a = info.arena
      if a and not lv.arenaEntered and px > a.x0 and px < a.x1 and py > a.top and py < a.floorY then
        lv.arenaEntered = true
        hud.showBanner("The Queen's Lair", "Kill the Sulfur Queen. She is immune to fire, and nothing stops her flying; her gas is not so safe")
      end
      for j, s in ipairs(info.shops) do
        if b.x >= s.x and b.x + b.w <= s.x + s.w and b.y >= s.y and b.y + b.h <= s.y + s.h then
          if not lv.shopReached then
            lv.shopReached = true
            if lv.area.hasNext then
              hud.showBanner("The Shop", "Heal, buy, test guns on the dummy, then shoot the chain to open the hatch. Leaving closes the shop")
            else
              hud.showBanner("The Shop", "This path ends here for now. More depths are coming soon. Try your guns on the dummy")
            end
          end
          -- Choosing one of two shops seals the way to the other
          if #info.shops > 1 and not lv.chosen then
            lv.chosen = j
            for k, other in ipairs(info.shops) do
              if k ~= j then
                catacombs.seal(lv, other)
              end
            end
            hud.showBanner("The Way Behind You Collapses", "The other shop is out of reach unless you dig")
          end
        end
      end
    end
  end
end

-- Fills a shop's access shaft with rubble (breakable rock, so it can be dug out)
function catacombs.seal(lv, room)
  if room.sealed then
    return
  end
  room.sealed = true
  local sh = room.shaft
  local id = lv.theme.palette and lv.theme.palette.rock or materials.ROCK
  for y = sh.y0, sh.y1 do
    for x = sh.x0, sh.x1 do
      world:setRaw(x, y, id)
    end
  end
  world:repaintRegion(sh.x0, sh.y0, sh.x1, sh.y1)
  physics.rebuildRegion(sh.x0, sh.y0, sh.x1, sh.y1)
  audio.play("explosion", 0.8, 0.5)
  for _ = 1, 40 do
    effects.particle(sh.x0 + love.math.random() * (sh.x1 - sh.x0), sh.y0 + love.math.random() * 30, (love.math.random() - 0.5) * 60, 20 + love.math.random() * 60, 1.0, { 0.45, 0.42, 0.30 }, 300)
  end
end

-- The Queen is dead: the iron gates over both shafts open
function catacombs.openGates(lv)
  local a = lv.info.arena
  if a.open then
    return
  end
  a.open = true
  audio.play("hatch")
  for _, g in ipairs(a.gates) do
    for y = g.y0, g.y1 do
      for x = g.x0, g.x1 do
        world:setRaw(x, y, materials.AIR)
      end
    end
    world:repaintRegion(g.x0, g.y0, g.x1, g.y1)
    physics.rebuildRegion(g.x0, g.y0, g.x1, g.y1)
    for _ = 1, 30 do
      effects.particle(g.x0 + love.math.random() * (g.x1 - g.x0), g.y0 + 2, (love.math.random() - 0.5) * 40, 10 + love.math.random() * 50, 1.0, { 0.40, 0.41, 0.48 }, 520)
    end
  end
  hud.showBanner("The Queen Has Fallen", "The gates are open. Two shops lie below, left and right: choose one")
end

-- Is the point inside a shop room?
function catacombs.inShop(x, y)
  for _, lv in ipairs(levels) do
    for _, s in ipairs(lv.info and lv.info.shops or {}) do
      if x >= s.x and x <= s.x + s.w and y >= s.y and y <= s.y + s.h then
        return true
      end
    end
  end
  return false
end

function catacombs.shopReached()
  return levels[1] ~= nil and levels[1].shopReached == true
end

local function flicker(seed)
  local t = love.timer.getTime()
  return math.sin(t * 9 + seed) * 0.5 + math.sin(t * 23 + seed * 2) * 0.5
end

-- Two iron sconces with candles on each shop's back wall
local function candles(info)
  local list = {}
  for _, s in ipairs(info.shops) do
    list[#list + 1] = { s.x + 48, s.y + 30, 4 }
    list[#list + 1] = { s.x + math.floor(s.w * 0.33), s.y + 30, 4 }
    list[#list + 1] = { s.x + math.floor(s.w * 0.62), s.y + 30, 4 }
    list[#list + 1] = { s.x + s.w - 48, s.y + 30, 4 }
  end
  return list
end

-- view: { x, y, w, h } in world pixels; things outside it (plus margin) are skipped
local function visible(view, x, y, margin)
  return x > view.x - margin and x < view.x + view.w + margin and y > view.y - margin and y < view.y + view.h + margin
end

function catacombs.addLights(lighting, view)
  fluids.addLights(lighting, view)
  local t = love.timer.getTime()
  for _, lv in ipairs(levels) do
    local info = lv.info
    if info then
      for i, c in ipairs(candles(info)) do
        if visible(view, c[1], c[2], 120) then
          lighting.add(c[1], c[2] - c[3] - 2, 120, 1, 0.68, 0.36, 1.0 + flicker(i) * 0.07)
        end
      end
      if info.mine then
        minedecor.addLights(lighting, info.mine, view)
      end
      local g, r = lv.theme.glow, lv.theme.glowRadius
      local strong = (lv.index > 1 and 0.75 or 0.6) * (lv.theme.glowLight or 1)
      for i, spot in ipairs(info.glows) do
        if visible(view, spot[1], spot[2], r) then
          lighting.add(spot[1], spot[2] - 3, r, g[1], g[2], g[3], strong + math.sin(t * 1.5 + i) * 0.08)
        end
      end
    end
  end
end

-- A cluster of sulfur crystals: little pale spikes (their tips glow, see drawEmissive)
local function drawCrystals(x, y, seed, stalk)
  for i = 0, 2 do
    local dx = (i - 1) * 2 + (seed + i) % 2
    local h = 3 + (seed + i * 5) % 5
    love.graphics.setColor(stalk[1] * (0.8 + 0.1 * i), stalk[2] * (0.8 + 0.1 * i), stalk[3])
    love.graphics.rectangle("fill", x + dx, y - h, 1, h)
  end
  love.graphics.setColor(stalk[1] * 0.6, stalk[2] * 0.6, stalk[3] * 0.6)
  love.graphics.rectangle("fill", x - 3, y - 1, 7, 1)
end

local function drawFungus(x, y, seed, stalk)
  -- A cluster of tiny caps on stalks
  for i = 0, 2 do
    local dx = (i - 1) * 2 + (seed + i) % 2
    local h = 2 + (seed + i * 3) % 3
    love.graphics.setColor(stalk)
    love.graphics.rectangle("fill", x + dx, y - h, 1, h)
  end
end

function catacombs.drawDecor(view)
  fluids.drawDecor(view)
  for _, lv in ipairs(levels) do
    local info = lv.info
    if info then
      local drawGlow = lv.theme.crystals and drawCrystals or drawFungus
      for i, g in ipairs(info.glows) do
        if visible(view, g[1], g[2], 8) then
          drawGlow(g[1], g[2], i, lv.theme.stalk)
        end
      end
      if info.mine then
        minedecor.draw(info.mine, view)
      end
      for _, s in ipairs(info.shops) do
        if visible(view, s.x + s.w / 2, s.y + s.h / 2, 400) then
          -- Empty shelves on the back wall, each with a darker underside
          for i = 0, 2 do
            local y = s.y + 32 + i * 16
            love.graphics.setColor(0.36, 0.25, 0.17)
            love.graphics.rectangle("fill", s.x + s.w - 112, y, 70, 2)
            love.graphics.setColor(0.20, 0.14, 0.10)
            love.graphics.rectangle("fill", s.x + s.w - 112, y + 2, 70, 1)
          end
        end
      end
      if visible(view, view.x + view.w / 2, view.y + view.h / 2, 3000) then
        -- Sconce brackets and candle sticks
        for _, c in ipairs(candles(info)) do
          if visible(view, c[1], c[2], 8) then
            love.graphics.setColor(0.14, 0.12, 0.14)
            love.graphics.rectangle("fill", c[1] - 2, c[2] + 1, 5, 1)
            love.graphics.rectangle("fill", c[1], c[2] + 2, 1, 4)
            love.graphics.setColor(0.82, 0.78, 0.66)
            love.graphics.rectangle("fill", c[1], c[2] - c[3], 1, c[3] + 1)
          end
        end
      end
      -- The arena's one-way platforms: slabs of the area's rock
      if info.arena and info.arena.platforms then
        local def = materials.defs[lv.theme.palette and lv.theme.palette.rock or materials.ROCK]
        for _, p in ipairs(info.arena.platforms) do
          if visible(view, (p.x0 + p.x1) / 2, p.y, 60) then
            for x = p.x0, p.x1 do
              local thick = 5 + math.floor(love.math.noise(x * 0.2, p.y) * 3)
              love.graphics.setColor(def.topColor[1], def.topColor[2], def.topColor[3])
              love.graphics.rectangle("fill", x, p.y, 1, 1)
              love.graphics.setColor(def.color[1] * 0.85, def.color[2] * 0.85, def.color[3] * 0.85)
              love.graphics.rectangle("fill", x, p.y + 1, 1, thick - 1)
            end
          end
        end
      end
      -- The arena's braziers: a stone bowl on a short pedestal (the fire is
      -- real fire, see src.fluids)
      if info.arena then
        for _, br in ipairs(info.arena.braziers) do
          if visible(view, br.x, br.y, 12) then
            love.graphics.setColor(0.28, 0.27, 0.32)
            love.graphics.rectangle("fill", br.x - 2, br.y - 9, 5, 9)
            love.graphics.rectangle("fill", br.x - 6, br.y - 1, 13, 1)
            love.graphics.setColor(0.40, 0.39, 0.46)
            love.graphics.rectangle("fill", br.x - 6, br.y - 12, 13, 4)
            love.graphics.rectangle("fill", br.x - 4, br.y - 9, 9, 1)
            love.graphics.setColor(0.18, 0.17, 0.21)
            love.graphics.rectangle("fill", br.x - 5, br.y - 12, 11, 1)
          end
        end
      end
    end
  end
end

function catacombs.drawEmissive(view)
  fluids.drawEmissive(view)
  for _, lv in ipairs(levels) do
    local info = lv.info
    if info then
      local g = lv.theme.glow
      if info.mine then
        minedecor.drawEmissive(info.mine, view)
      end
      for i, spot in ipairs(info.glows) do
        if visible(view, spot[1], spot[2], 8) then
          for j = 0, 2 do
            local dx = (j - 1) * 2 + (i + j) % 2
            love.graphics.setColor(math.min(1, g[1] + 0.1), math.min(1, g[2] + 0.05), math.min(1, g[3] + 0.05))
            if lv.theme.crystals then
              -- A bright tip on each crystal
              local h = 3 + (i + j * 5) % 5
              love.graphics.rectangle("fill", spot[1] + dx, spot[2] - h, 1, 1)
            else
              -- Glowing caps on the fungus stalks
              local h = 2 + (i + j * 3) % 3
              love.graphics.rectangle("fill", spot[1] + dx - (j == 1 and 1 or 0), spot[2] - h - 1, j == 1 and 3 or 2, 1)
            end
          end
        end
      end
      for i, c in ipairs(candles(info)) do
        local top = c[2] - c[3]
        love.graphics.setColor(1, 0.72, 0.28)
        love.graphics.rectangle("fill", c[1], top - 2 - (flicker(i) > 0.3 and 1 or 0), 1, 2)
        love.graphics.setColor(1, 0.95, 0.7)
        love.graphics.rectangle("fill", c[1], top - 1, 1, 1)
      end
    end
  end
end

-- Water and smoke, in front of the hunter
function catacombs.drawFront(view)
  fluids.drawFront(view)
end

function catacombs.drawScreen(toScreen, font)
  for _, lv in ipairs(levels) do
    if lv.info then
      for _, s in ipairs(lv.info.shops) do
        local sx, sy = toScreen(s.x + s.w / 2, s.y + 19)
        local sw, sh = love.graphics.getDimensions()
        if sx > -100 and sx < sw + 100 and sy > -50 and sy < sh + 50 then
          local text = "SHOP"
          love.graphics.setFont(font)
          love.graphics.setColor(0, 0, 0, 0.8)
          love.graphics.print(text, math.floor(sx - font:getWidth(text) / 2) + 2, math.floor(sy) + 2)
          love.graphics.setColor(0.97, 0.98, 1)
          love.graphics.print(text, math.floor(sx - font:getWidth(text) / 2), math.floor(sy))
        end
      end
    end
  end
end

-- An area's name (for the save files' "deepest reached")
function catacombs.areaName(i)
  return THEMES[i] and THEMES[i].name or nil
end

return catacombs
