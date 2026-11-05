-- The hunter's journal: torn pages left where the people who went down lived and worked, one or two at each of the
-- four ways down (the Old Mine, the lake, the Quarry, the Needle). Walk up and press E to read one. Each page read is
-- kept in the profile (the compendium's "Journal" tab, src.compendium) and can be read again from the world.
-- Add a page here and it appears in the world and the compendium.
--
-- Joins the secrets (src.secrets): the same hooks as the Buried Vault's door.
local input = require("src.input")

local journal = {}

-- x: where it lies. The y is the ground there (src.entrances.standY). where: its place in the compendium.
journal.PAGES = {
  {
    id = "mine_notice", title = "Notice of Closure", where = "The Old Mine", x = 1452,
    text = "By order of the Gunnug Mining Co.: the lower workings are CLOSED until further notice. Any man found below the third level will be struck from the roll.\n\n- The Superintendent\n\nUnderneath, in pencil: \"The roll is already short.\"",
  },
  {
    id = "mine_graves", title = "Names at the Head of the Row", where = "The Old Mine", x = 1442,
    text = "Five crosses and a sixth mound. Someone cut the names into the boards: Alder. Quill. The Pruitt boys. Old Tam.\n\nThe sixth board is blank. The lantern set at its head is still burning, and no one in the camp admits to filling it.",
  },
  {
    id = "lake_ledger", title = "A Ledger, Swollen with Water", where = "The Sunken Hollows", x = -566,
    text = "Pumps ran day and night in the second shaft. March: the water rose a foot. April: a yard. May: the foreman says the lake is feeding the mine, not the mine the lake.\n\nNobody asked him how a lake gets under a mine.",
  },
  {
    id = "lake_sketch", title = "Surveyor's Sketch", where = "The Sunken Hollows", x = -1258,
    text = "The ground here was dry when we mapped it: three pegs, a cairn and a spring. I have drawn it as we found it, and written WATER across the middle in a hand I do not trust.\n\nIt was not there when I began the page.",
  },
  {
    id = "quarry_order", title = "Foreman's Order", where = "The Quarry", x = 4172,
    text = "Cut to the line. Do not cut past the line.\n\nThe stone below the sixth bench rings wrong, and the men say it answers back. Cut to the line.",
  },
  {
    id = "quarry_count", title = "The Cut Count", where = "The Quarry", x = 4214,
    text = "Blocks cut: 4,112.\nBlocks hauled: 3,980.\nBlocks unaccounted for: 132, and one hall.\n\nWe counted twice. The hall is still there. It is not on the plan.",
  },
  {
    id = "needle_scrawl", title = "Pilgrim's Scrawl", where = "The Needle", x = 5582,
    text = "Scratched into the stone with something that was not a knife:\n\nUP. THE WAY IS UP. I have seen the stair from here. The flank climbs and climbs and the light at the top does not move.\n\nTell them I went willingly.",
  },
  {
    id = "needle_banner", title = "The Last Banner", where = "The Needle", x = 5812,
    text = "Red cloth tied to a dead man's staff, left where the stones begin. Whoever raised it did not mean it as a warning.\n\nIt reads like a welcome.",
  },
}

-- Pages inside the dungeons: each lies on a floor spot of its area (src.cavegen's pageSpots), placed when the area is
-- spawned (setupArea). area: the level's index (src.scenes.catacombs LAYOUT).
local AREA_PAGES = {
  { id = "cave_mine", area = 1, title = "A Shift Sheet, Unsigned", where = "The Old Mine",
    text = "Third level, night shift. Nine went down and the lamps were all lit. Count at the change: eight lamps, nine men, and a tenth set of boots by the ladder.\n\nNo one has claimed them." },
  { id = "cave_fen", area = 2, title = "Botanist's Field Notes", where = "The Sunken Hollows",
    text = "The spore pods answer light. Hold a lantern to one and every pod in the fen turns the same way, like heads in a church.\n\nI have stopped bringing the lantern. They still turn." },
  { id = "cave_vents", area = 3, title = "Apothecary's Receipt", where = "The Sulfur Vents",
    text = "Sold: one gross of breathing-cloths, for a mine that was already empty.\n\nThe buyer paid in coin I did not know, warm to the touch, and left the receipt unsigned. The ink is the colour of the vents." },
  { id = "cave_quarry", area = 6, title = "Mason's Tally", where = "The Quarry",
    text = "I cut. He hauls. She counts. The count is wrong and we all know it, and none of us will say whose count is wrong.\n\nThe wall behind the sixth bench is warm. Warm stone is alive stone." },
  { id = "cave_flooded", area = 8, title = "Drowned Man's Letter", where = "The Flooded Caverns",
    text = "Dearest, the water is not rising. It is that we are sinking, a little each day, and the lake has stayed where it was.\n\nWhen you read this, look up from the bottom of the world and tell me the sky is still there." },
}
for _, p in ipairs(AREA_PAGES) do
  journal.PAGES[#journal.PAGES + 1] = p
end

local byId = {}
for _, p in ipairs(journal.PAGES) do
  byId[p.id] = p
end

local REACH_X, REACH_Y = 34, 40 -- (a little more forgiving to stand at)
local reading -- the page open on screen
local clock = 0

local function ground(p)
  if p.area then
    return p.y -- (a dungeon page: the floor spot it was placed on, or nil until its area is spawned)
  end
  return require("src.entrances").standY(p.x)
end

local function isRead(id)
  local ok, n = pcall(function()
    return require("src.save").count("journal", id)
  end)
  return ok and n and n > 0
end

function journal.clear()
  reading = nil
  for _, p in ipairs(journal.PAGES) do
    if p.area then
      p.x, p.y = nil, nil -- (placed again as each area is spawned)
    end
  end
end

-- A dungeon area has been spawned: its page lies on the first of the spots cavegen found
function journal.setupArea(index, spots)
  for _, p in ipairs(journal.PAGES) do
    if p.area == index then
      local s = spots and spots[1]
      if s then
        p.x, p.y = s[1], s[2]
      end
    end
  end
end

function journal.update(dt, player)
  clock = clock + dt
  if reading then
    local px = player:center()
    if math.abs(px - reading.x) > 90 or player.dead then
      reading = nil
    end
  end
end

-- The page the hunter stands next to, if any
local function nearest(player)
  if player.dead then
    return nil
  end
  local px, py = player:center()
  local best, bestD
  for _, p in ipairs(journal.PAGES) do
    local g = p.x and ground(p)
    if g and math.abs(px - p.x) < REACH_X and math.abs(py - (g - 6)) < REACH_Y then
      local d = math.abs(px - p.x)
      if not bestD or d < bestD then
        best, bestD = p, d
      end
    end
  end
  return best
end

function journal.interact(player)
  if reading then
    reading = nil
    return true
  end
  local p = nearest(player)
  if not p then
    return false
  end
  reading = p
  pcall(function()
    require("src.save").record("journal", p.id)
  end)
  pcall(function()
    require("src.audio").play("buy", 0.4, 1.6)
  end)
  return true
end

local function R(c, a, x, y, w, h)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
  love.graphics.rectangle("fill", math.floor(x), math.floor(y), w, h)
end

local function inView(view, p)
  return p.x ~= nil and p.x > view.x - 20 and p.x < view.x + view.w + 20 and (not p.area or (p.y > view.y - 40 and p.y < view.y + view.h + 40))
end

-- A torn page lying on the ground, lifting a little in the wind
function journal.draw(view)
  for _, p in ipairs(journal.PAGES) do
    if inView(view, p) then
      local g = ground(p)
      if g then
        local read = isRead(p.id)
        local bob = math.floor(math.sin(clock * 1.6 + p.x * 0.05) * 1 + 0.5)
        local x, y = p.x - 3, g - 10 + bob
        local paper = read and { 0.66, 0.60, 0.48 } or { 0.92, 0.86, 0.68 }
        R({ 0.15, 0.12, 0.10 }, 0.5, x, g - 1, 8, 1) -- (a shadow on the ground)
        R(paper, 1, x - 1, y - 2, 9, 11)
        R({ 0.50, 0.42, 0.30 }, 1, x - 1, y - 2, 9, 1)
        R({ 0.36, 0.30, 0.22 }, 1, x, y, 7, 1)
        R({ 0.36, 0.30, 0.22 }, 1, x, y + 2, 5, 1)
        R({ 0.36, 0.30, 0.22 }, 1, x, y + 4, 7, 1)
        R({ 0.36, 0.30, 0.22 }, 1, x, y + 6, 4, 1)
        R({ 0.20, 0.16, 0.12 }, 1, x + 5, y + 8, 2, 1) -- (a torn corner)
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- Unread pages glow faintly
function journal.drawEmissive(view)
  for _, p in ipairs(journal.PAGES) do
    if inView(view, p) and not isRead(p.id) then
      local g = ground(p)
      if g then
        local pulse = 0.5 + 0.5 * math.sin(clock * 2.2 + p.x)
        R({ 1.0, 0.86, 0.5 }, 0.07 + 0.05 * pulse, p.x - 12, g - 24, 24, 26)
        R({ 1.0, 0.9, 0.6 }, 0.12 + 0.08 * pulse, p.x - 4, g - 13, 8, 9)
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function journal.addLights() end

local function prompt(font, toScreen, wx, wy, text)
  local sx, sy = toScreen(wx, wy)
  love.graphics.setFont(font)
  local x, y = math.floor(sx - font:getWidth(text) / 2), math.floor(sy - font:getHeight())
  love.graphics.setColor(0, 0, 0, 0.85)
  love.graphics.print(text, x + 2, y + 2)
  love.graphics.setColor(1, 0.88, 0.6)
  love.graphics.print(text, x, y)
end

function journal.drawScreen(toScreen, font, player)
  if reading then
    -- The page, open: a scrap of old paper found in a dungeon. The same cream card as the playing cards (dark edge,
    -- lit upper left) gone to ruin: yellowed and stained, torn edges, a missing corner, creases and fold marks, a
    -- ragged unequal margin, and thin faded ink. Lower on the screen than the area banner, sized to its text.
    local sw, sh = love.graphics.getDimensions()
    local fonts = require("src.fonts")
    local u = math.max(2, math.floor(sh / 200))
    local body = fonts.plain(math.max(10, math.floor(sh / 47)), "italic") -- (the game's italic face, without its drop shadow: dark ink on paper)
    local head = fonts.plain(math.max(11, math.floor(sh / 40)), "italic")
    local small = fonts.plain(math.max(8, math.floor(sh / 66)), "italic")
    local w = math.floor(math.min(sw * 0.28, sh * 0.58))
    local pad = 10 * u
    local _, lines = body:getWrap(reading.text, w - pad * 2)
    local _, tlines = head:getWrap(reading.title, w - pad * 2)
    local textH = #lines * body:getHeight() * body:getLineHeight()
    local titleH = #tlines * head:getHeight() * head:getLineHeight()
    local h = math.max(math.floor(w * 0.8), pad * 2 + titleH + 6 * u + textH + small:getHeight() * 2.4)
    local x, y = math.floor((sw - w) / 2), math.floor(sh * 0.34)
    -- every page is torn the same way each time it is opened (seeded by its id)
    local seed = 0
    for ch in reading.id:gmatch(".") do
      seed = (seed * 31 + ch:byte()) % 100003
    end
    local function rnd(i)
      local v = math.sin(seed * 12.9898 + i * 78.233) * 43758.5453
      return v - math.floor(v)
    end
    -- the outline: a rectangle walked clockwise with a ragged edge, a bite out of the top right, a torn corner at the
    -- bottom left, and a long diagonal tear at the bottom right
    local pts, n = {}, 0
    local function add(px, py)
      pts[#pts + 1] = px
      pts[#pts + 1] = py
    end
    local step = 5 * u
    for px = 0, w, step do -- top edge
      n = n + 1
      local bite = (px > w * 0.62 and px < w * 0.82) and (math.sin((px - w * 0.62) / (w * 0.20) * math.pi) * 9 * u) or 0
      add(px, rnd(n) * 2.4 * u + bite)
    end
    for py = step, h, step do -- right edge
      n = n + 1
      local tear = py > h * 0.78 and (py - h * 0.78) / (h * 0.22) * 8 * u or 0
      add(w - rnd(n) * 2.4 * u - tear, py)
    end
    for px = w - 11 * u, 9 * u, -step do -- bottom edge (between the two torn corners)
      n = n + 1
      add(px, h - rnd(n) * 3 * u - (px / w) * 0 )
    end
    for py = h - step, 0, -step do -- left edge, the bottom-left corner torn off
      n = n + 1
      local corner = py > h - 14 * u and (py - (h - 14 * u)) / (14 * u) * 7 * u or 0
      add(rnd(n) * 2.6 * u + corner, py)
    end
    local okTri, tris = pcall(love.math.triangulate, pts)
    if not okTri then
      tris = { { 0, 0, w, 0, w, h }, { 0, 0, w, h, 0, h } } -- (a plain rectangle if the tear ever crosses itself)
    end
    local function fillPoly(ox, oy)
      for _, t in ipairs(tris) do
        love.graphics.polygon("fill", x + ox + t[1], y + oy + t[2], x + ox + t[3], y + oy + t[4], x + ox + t[5], y + oy + t[6])
      end
    end
    -- shadow, dark rim, then the paper itself
    love.graphics.setColor(0, 0, 0, 0.35)
    fillPoly(2 * u, 3 * u)
    love.graphics.setColor(0.50, 0.40, 0.27, 1)
    fillPoly(-u * 0.7, -u * 0.7)
    fillPoly(u * 0.7, u * 0.7)
    fillPoly(-u * 0.7, u * 0.7)
    fillPoly(u * 0.7, -u * 0.7)
    love.graphics.setColor(0.84, 0.77, 0.60, 1) -- (the card's cream, yellowed with age)
    fillPoly(0, 0)
    -- everything else on the paper is clipped to it
    love.graphics.stencil(function()
      fillPoly(0, 0)
    end, "replace", 1)
    love.graphics.setStencilTest("greater", 0)
    -- lit upper left, darker lower right
    love.graphics.setColor(0.96, 0.91, 0.74, 0.55)
    love.graphics.rectangle("fill", x, y, w * 0.55, u * 3)
    love.graphics.rectangle("fill", x, y, u * 3, h * 0.55)
    love.graphics.setColor(0.55, 0.43, 0.28, 0.40)
    love.graphics.rectangle("fill", x, y + h - u * 5, w, u * 5)
    love.graphics.rectangle("fill", x + w - u * 5, y, u * 5, h)
    -- stains: soft brown blotches, a water ring, a rust smear
    for i = 1, 6 do
      local bx, by = x + rnd(40 + i) * w, y + rnd(60 + i) * h
      local br = (5 + rnd(80 + i) * 11) * u
      for k = 4, 1, -1 do -- (a blotch is a few rings, darkest in the middle, so it has no hard edge)
        love.graphics.setColor(0.52, 0.38, 0.22, 0.035 + 0.02 * rnd(100 + i))
        love.graphics.circle("fill", bx + (rnd(i * 7 + k) - 0.5) * u * 3, by + (rnd(i * 5 + k) - 0.5) * u * 3, br * (0.5 + k * 0.17))
      end
    end
    local rx, ry = x + w * (0.15 + 0.5 * rnd(7)), y + h * 0.7
    love.graphics.setColor(0.46, 0.22, 0.12, 0.22)
    love.graphics.rectangle("fill", rx, ry, 18 * u, 2 * u)
    love.graphics.rectangle("fill", rx + 4 * u, ry + 2 * u, 9 * u, 3 * u)
    -- creases: a fold across the middle and one down, a lighter edge beside a dark line
    local fy = y + math.floor(h * (0.46 + 0.1 * rnd(11)))
    love.graphics.setColor(0.38, 0.28, 0.18, 0.40)
    love.graphics.rectangle("fill", x, fy, w, math.max(1, math.floor(u * 0.6)))
    love.graphics.setColor(1, 0.97, 0.85, 0.30)
    love.graphics.rectangle("fill", x, fy + math.max(1, math.floor(u * 0.6)), w, math.max(1, math.floor(u * 0.6)))
    local fx = x + math.floor(w * (0.40 + 0.2 * rnd(13)))
    love.graphics.setColor(0.38, 0.28, 0.18, 0.28)
    love.graphics.rectangle("fill", fx, y, math.max(1, math.floor(u * 0.6)), h)
    love.graphics.setColor(1, 0.97, 0.85, 0.22)
    love.graphics.rectangle("fill", fx + math.max(1, math.floor(u * 0.6)), y, math.max(1, math.floor(u * 0.6)), h)
    -- the ink: thin and faded, a warm grey-brown
    local ink, faint = { 0.30, 0.25, 0.20 }, { 0.46, 0.38, 0.28 }
    love.graphics.setFont(head)
    love.graphics.setColor(ink[1] + 0.05, ink[2] + 0.05, ink[3] + 0.02, 0.88)
    love.graphics.printf(reading.title, x + pad, y + pad, w - pad * 2, "center")
    local ty = y + pad + titleH + 2 * u
    love.graphics.setColor(0.52, 0.42, 0.30, 0.6)
    love.graphics.rectangle("fill", x + pad + 8 * u, ty, w - pad * 2 - 16 * u, math.max(1, math.floor(u * 0.5)))
    love.graphics.setFont(body)
    love.graphics.setColor(ink[1] + 0.08, ink[2] + 0.08, ink[3] + 0.04, 0.86)
    love.graphics.printf(reading.text, x + pad, ty + 4 * u, w - pad * 2, "left")
    -- ink blots where the writing has run
    love.graphics.setColor(0.28, 0.22, 0.18, 0.35)
    love.graphics.circle("fill", x + pad + rnd(3) * (w - pad * 2), ty + 8 * u + rnd(5) * textH * 0.7, u * 1.2)
    love.graphics.setFont(small)
    love.graphics.setColor(faint[1], faint[2], faint[3], 0.9)
    love.graphics.printf("[" .. input.label("interact") .. "] Close", x + pad, y + h - pad - small:getHeight() + u, w - pad * 2, "center")
    love.graphics.setStencilTest()
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  local p = nearest(player)
  if p then
    local g = ground(p)
    prompt(font, toScreen, p.x, g - 16, "[" .. input.label("interact") .. "] Read")
  end
end

return journal
