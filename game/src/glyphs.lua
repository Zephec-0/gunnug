-- Glyphs: the proof of a slain boss. Each of the run's bosses leaves one behind
-- (a theme's `glyph`), and the hunter who carries them all can light the pedestals
-- on the mountain's top (src.summit) and be carried up to the sky. They belong to the run (inv.glyphs), so they must be won again after
-- a death; unlike perks they have no effect of their own. Each is drawn glowing on the
-- health bottle (src.hud), only once it has been taken.
local glyphs = {}

glyphs.order = { "sulfur", "stone", "deep", "hunter" }

-- Each rune is cut in straight strokes, like the old futhark letters
glyphs.defs = {
  sulfur = {
    name = "Glyph of Sulfur",
    color = { 0.95, 0.82, 0.28 },
    desc = "Taken from the Sulfur Queen.",
    rune = { "#..#..#", "#..#..#", ".#.#.#.", "..###..", "...#...", "...#...", "...#..." },
  },
  stone = {
    name = "Glyph of Stone",
    color = { 0.92, 0.66, 0.40 },
    desc = "Taken from the marble Colossus.",
    rune = { "#.....#", "##...##", "#.#.#.#", "#..#..#", "#.#.#.#", "##...##", "#.....#" },
  },
  deep = {
    name = "Glyph of the Deep",
    color = { 0.38, 0.66, 1.0 },
    desc = "Taken from the Biggest Fish.",
    rune = { "#.###..", "#.#..#.", "#.#..#.", "#.###..", "#.#..#.", "#.#..#.", "#.###.." },
  },
  hunter = {
    name = "Glyph of the Hunt",
    color = { 0.80, 0.45, 1.0 },
    desc = "Taken from the Dark Hunter.",
    rune = { "#......", "#.##...", "#..##..", "#.###..", "#..##..", "#.##...", "#......" },
  },
}

-- The run's glyphs live in its inventory (inv.glyphs = { id = true }); this
-- module reads whichever inventory was bound last (see inventory.new)
local owned = {}

function glyphs.bind(inv)
  owned = inv.glyphs
end

function glyphs.has(id)
  return owned[id] == true
end

function glyphs.add(id)
  owned[id] = true
end

function glyphs.count()
  local n = 0
  for _, id in ipairs(glyphs.order) do
    if owned[id] then
      n = n + 1
    end
  end
  return n
end

function glyphs.total()
  return #glyphs.order
end

-- A glyph shaped like a pickup, for the pickup code (name, colour, rarity)
function glyphs.new(id)
  local def = assert(glyphs.defs[id], "unknown glyph: " .. tostring(id))
  return { id = id, isGlyph = true, name = def.name, color = def.color, rarity = "epic", desc = def.desc }
end

-- The rune alone (7x7 cells) at (x, y), `s` screen pixels to a cell, glowing in the glyph's colour: a soft
-- additive halo under the cells, no frame or backing
function glyphs.draw(id, x, y, s, alpha)
  local def = glyphs.defs[id]
  local c = def.color
  alpha = alpha or 1
  local pulse = 0.85 + 0.15 * math.sin(love.timer.getTime() * 2.2 + #id)
  love.graphics.setBlendMode("add")
  love.graphics.setColor(c[1], c[2], c[3], 0.22 * pulse * alpha)
  for row, line in ipairs(def.rune) do
    for col = 1, 7 do
      if line:sub(col, col) == "#" then
        love.graphics.rectangle("fill", x + (col - 1) * s - s * 0.5, y + (row - 1) * s - s * 0.5, s * 2, s * 2)
      end
    end
  end
  love.graphics.setBlendMode("alpha")
  love.graphics.setColor(math.min(1, c[1] + 0.2), math.min(1, c[2] + 0.2), math.min(1, c[3] + 0.2), alpha)
  for row, line in ipairs(def.rune) do
    for col = 1, 7 do
      if line:sub(col, col) == "#" then
        love.graphics.rectangle("fill", x + (col - 1) * s, y + (row - 1) * s, s, s)
      end
    end
  end
end

return glyphs
