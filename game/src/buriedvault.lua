-- The Buried Vault (docs/undercroft-design.md): a sealed block of vault rock under the Needle, in the plain's
-- solid rock just below the mountain's floor. Nothing points to it: the way in is to dig down a little from the
-- Needle's lowest caves, and only a bullet with the vaultDig effect gets through the rock. Inside, an
-- antechamber with a door in its far wall (the fused-item door, built later) and a room behind it for the Relic.
-- (the door takes three fused items, all made by the hunter: nothing in the vault supplies one)
local materials = require("src.materials")

local buriedvault = {}

local VAULT, AIR, BRICK, BEDROCK = materials.VAULTROCK, materials.AIR, materials.STONEBRICK, materials.BEDROCK

-- The block of vault rock: it starts just under the Needle's box (which ends at y 1099)
local BLOCK = { x0 = 6780, y0 = 1100, x1 = 7220, y1 = 1380 }

-- What is hollowed out of it, and where the later steps put things
buriedvault.info = {
  block = BLOCK,
  antechamber = { x0 = 6900, y0 = 1270, x1 = 6960, y1 = 1320 },
  door = { x0 = 6961, y0 = 1290, x1 = 6966, y1 = 1320 }, -- (a brick divider for now; the fused-item door goes here)
  relicRoom = { x0 = 6967, y0 = 1270, x1 = 7040, y1 = 1320 },
  pedestal = { x0 = 7000, y0 = 1312, x1 = 7008, y1 = 1320 }, -- (the Sunken Key rests on it)
  pocket = { x0 = 7190, y0 = 1125, x1 = 7205, y1 = 1135 }, -- (far from the Relic: the north-east corner of the block)
}
-- The Relic's room is boxed in bedrock, which nothing digs: the only way in is through the door
buriedvault.SHELL = 5
-- Over the vault, in the Needle's lowest rock, the gold runs richer: a hint that something lies below
buriedvault.goldHint = { x0 = 6880, y0 = 1010, x1 = 7060, y1 = 1096, count = 26 }

local function carve(world, r)
  world:fillRect(r.x0, r.y0, r.x1, r.y1, AIR)
end

function buriedvault.build(world)
  local b, i = BLOCK, buriedvault.info
  world:fillFast(b.x0, b.y0, b.x1, b.y1, VAULT)
  local r, sh = i.relicRoom, buriedvault.SHELL
  world:fillRect(i.door.x0, r.y0 - sh, r.x1 + sh, r.y1 + sh, BEDROCK)
  carve(world, i.antechamber)
  carve(world, i.relicRoom)
  world:fillRect(i.pedestal.x0, i.pedestal.y0, i.pedestal.x1, i.pedestal.y1, BRICK)
  -- The wall between the two rooms, until the door is built
  world:fillRect(i.door.x0, i.antechamber.y0, i.door.x1, i.antechamber.y1, BEDROCK)
  require("src.relicdoor").setup(world)
end

return buriedvault
