-- The Buried Vault (docs/undercroft-design.md): a sealed block of vault rock under the Needle, in the plain's
-- solid rock just below the mountain's floor. Nothing points to it: the way in is to dig down a little from the
-- Needle's lowest caves, and only a bullet with the vaultDig effect gets through the rock. Inside, an
-- chamber shaped like a goblet, with three locks and the Relic (see `info` below).
-- (the locks take three fused items, all made by the hunter: nothing in the vault supplies one)
local materials = require("src.materials")

local buriedvault = {}

local VAULT, AIR, BRICK, BEDROCK = materials.VAULTROCK, materials.AIR, materials.STONEBRICK, materials.BEDROCK

-- The block of vault rock: it starts just under the Needle's box (which ends at y 1099)
local BLOCK = { x0 = 6780, y0 = 1100, x1 = 7220, y1 = 1440 }

-- What is hollowed out of it: one chamber shaped like a goblet (or an hourglass). The upper bulb is plain vault
-- rock (a hunter digs into it from anywhere and lands on the shelf across it, where three locks stand). Under the
-- shelf the bulb holds a pool of water that funnels down to a narrow neck, stopped by a plug. Below the plug is a
-- sphere with the Cork on a tall column; when the third lock is set the plug gives and the water pours down into
-- the basin round the column's foot (src.relicdoor). Only the neck and the sphere are bedrock, so nothing digs to
-- the Cork or round the plug; ledges up the sphere and the neck are the way back out.
local CX = 7000
local BULB = { cy = 1190, rx = 60, ry = 42, flat = 1213 } -- (the ellipse down to `flat`, then a funnel)
local FUNNEL_END, NECK_HW = 1236, 7
local SPHERE = { cy = 1330, r = 60 }
local TOP, BOTTOM = BULB.cy - BULB.ry, SPHERE.cy + SPHERE.r
local SHELL_FROM = 1230 -- (the bedrock starts a little above the neck)

buriedvault.info = {
  block = BLOCK,
  shelf = { x0 = 6936, y0 = 1186, x1 = 7045, y1 = 1189 }, -- (brick, wall to nearly wall: the pool is under it)
  locks = { 6982, 7000, 7018 }, -- (x centres of the three locks, standing on the shelf)
  waterLevel = 1195, -- (the pool's surface, just under the shelf)
  plug = { x0 = CX - NECK_HW, y0 = 1240, x1 = CX + NECK_HW, y1 = 1245 },
  bulb = { x0 = CX - BULB.rx, x1 = CX + BULB.rx },
  bounds = { x0 = CX - BULB.rx - 6, y0 = TOP - 6, x1 = CX + BULB.rx + 6, y1 = BOTTOM + 6 },
  -- the Cork rests on a column rising from the sphere's floor, so the water that pours in lies round its foot
  pedestal = { x0 = CX - 5, y0 = 1332, x1 = CX + 5, y1 = BOTTOM + 2 },
  -- the way out of the sphere: ledges (x0, x1, y) up its wall and the neck, a jump apart
  ledges = {
    { 7012, 7020, 1320 }, { 6980, 6988, 1308 }, { 7012, 7020, 1296 }, { 6982, 6990, 1284 },
    { 7007, 7014, 1274 }, { 6993, 7000, 1262 }, { 7001, 7007, 1252 },
  },
  pocket = { x0 = 7190, y0 = 1125, x1 = 7205, y1 = 1135 }, -- (far from the Relic: the north-east corner of the block)
}
buriedvault.SHELL = 5
-- Over the vault, in the Needle's lowest rock, the gold runs richer: a hint that something lies below
buriedvault.goldHint = { x0 = 6880, y0 = 1010, x1 = 7060, y1 = 1096, count = 26 }

-- Half the width of the chamber at row y (nil outside it)
local function halfWidth(y)
  local hw
  if y >= TOP and y <= BULB.flat then
    local d = (y - BULB.cy) / BULB.ry
    hw = BULB.rx * math.sqrt(math.max(0, 1 - d * d))
  elseif y > BULB.flat and y <= FUNNEL_END then
    local d = (BULB.flat - BULB.cy) / BULB.ry
    local top = BULB.rx * math.sqrt(1 - d * d)
    hw = top + (NECK_HW - top) * (y - BULB.flat) / (FUNNEL_END - BULB.flat)
  end
  if y > FUNNEL_END and y < SPHERE.cy - SPHERE.r + 4 then
    hw = NECK_HW
  end
  if y >= SPHERE.cy - SPHERE.r and y <= BOTTOM then
    local d = (y - SPHERE.cy) / SPHERE.r
    local sh = SPHERE.r * math.sqrt(math.max(0, 1 - d * d))
    hw = math.max(hw or 0, sh)
  end
  return hw
end

local function carve(world, r)
  world:fillRect(r.x0, r.y0, r.x1, r.y1, AIR)
end

function buriedvault.build(world)
  local b, i = BLOCK, buriedvault.info
  world:fillFast(b.x0, b.y0, b.x1, b.y1, VAULT)
  local sh = buriedvault.SHELL
  -- the bedrock shell round the neck and the sphere
  for y = SHELL_FROM, BOTTOM + sh do
    -- (the widest the hollow gets within `sh` rows either way, so the shell is as thick on the slopes as at the sides)
    local widest
    for yy = math.max(SHELL_FROM, y - sh), y + sh do
      local hw = halfWidth(yy)
      if hw and (not widest or hw > widest) then
        widest = hw
      end
    end
    if widest then
      world:fillRect(CX - math.floor(widest) - sh, y, CX + math.floor(widest) + sh, y, BEDROCK)
    end
  end
  for y = TOP, BOTTOM do
    local hw = halfWidth(y)
    if hw and hw >= 1 then
      world:fillRect(CX - math.floor(hw), y, CX + math.floor(hw), y, AIR)
    end
  end
  world:fillRect(i.shelf.x0, i.shelf.y0, i.shelf.x1, i.shelf.y1, BRICK)
  world:fillRect(i.plug.x0, i.plug.y0, i.plug.x1, i.plug.y1, BEDROCK)
  world:fillRect(i.pedestal.x0, i.pedestal.y0, i.pedestal.x1, i.pedestal.y1, BRICK)
  for _, l in ipairs(i.ledges) do
    world:fillRect(l[1], l[3], l[2], l[3] + 1, BRICK)
  end
  require("src.relicdoor").setup(world)
end

return buriedvault
