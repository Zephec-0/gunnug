-- Grass, stamped into the terrain while an area is generated: tufts of one-pixel blades, two to five pixels tall,
-- along the top of the earth and the mossy clays (the materials with `grassIds` in src.materials), so it costs
-- nothing while the game runs. The blades are decoration pixels of their own (not solid), painted with the rest
-- of the terrain and gone again if the ground under them is dug away (World:colorAt).
--
-- Only the first three areas have it (their themes say `grass = true`), and none grows in water or lava or acid:
-- not in a flooded part, not in a pool.
local materials = require("src.materials")

local grass = {}

local floor = math.floor
local COVER = 0.72 -- the share of columns that carry a tuft

local function hash(x, k)
  local n = math.sin(x * 12.9898 + k * 78.233) * 43758.5453
  return n - floor(n)
end

-- One blade standing on (x, y), the first open pixel over the ground, h tall; ids = the three greens
local function blade(world, x, y, h, lean, ids)
  local lower = floor(h / 2)
  world:stampPixel(x, y, ids[1]) -- the root
  for k = 1, h - 1 do
    local up = k >= lower and lean or 0 -- (the upper half leans)
    world:stampPixel(x + up, y - k, k == h - 1 and ids[3] or ids[2])
  end
end

-- x0..x1, y0..y1: the area. pools = lists of pools ({ cells = { x, y, ... } } squares of cellSize) to keep clear
-- of; flood = { top } or nil; tick() gives the frame back
function grass.bake(world, x0, y0, x1, y1, pools, cellSize, flood, tick)
  local wet = {}
  for _, list in ipairs(pools) do
    for _, pool in ipairs(list) do
      local cells = pool.cells
      for i = 1, #cells, 2 do
        wet[floor(cells[i + 1] / cellSize) * 100000 + floor(cells[i] / cellSize)] = true
      end
    end
  end
  local function inWater(x, y)
    if flood and y >= flood.top - 6 then
      return true
    end
    return wet[floor(y / cellSize) * 100000 + floor(x / cellSize)] or wet[floor((y - 5) / cellSize) * 100000 + floor(x / cellSize)] or false
  end
  local defs = materials.defs
  local count = 0
  for x = x0, x1 do
    if hash(x, 1) < COVER then
      local aboveSolid = world:isSolid(x, y0)
      for y = y0 + 1, y1 do
        local isSolid = world:isSolid(x, y)
        if isSolid and not aboveSolid then
          local def = defs[world:get(x, y)]
          local ids = def and def.grassIds
          if ids and not inWater(x, y - 1) then
            -- The blade is only as tall as the open air above the ground
            local h = 2 + floor(hash(x, 2) * 4)
            for k = 1, h do
              if world:isSolid(x, y - 1 - k) then
                h = k
                break
              end
            end
            if h >= 2 then
              local lean = h >= 4 and (hash(x, 5) < 0.5 and -1 or 1) or 0
              blade(world, x, y - 1, h, lean, ids)
              count = count + 1
              -- every third tuft has a shorter blade beside it
              if hash(x, 4) < 0.33 and not world:isSolid(x + 1, y - 1) and world:isSolid(x + 1, y) then
                blade(world, x + 1, y - 1, math.max(2, h - 2), 0, ids)
              end
            end
          end
        end
        aboveSolid = isSolid
      end
    end
    if x % 6 == 0 then
      tick()
    end
  end
  return count
end

return grass
