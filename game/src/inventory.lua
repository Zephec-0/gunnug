-- The player's carried gear (design doc §5.6): 3 weapon slots, the selected
-- weapon, and 7 loose slots for ammo types and attachments not yet fitted to
-- a gun. Owned by the run, so it carries over between areas.
--
-- An item is a table { kind = "ammo" | "attachment", name, short, color }.
-- No items exist in the game yet; the slots are ready for them.
local fuser = require("src.fuser")
local guns = require("src.guns")
local items = require("src.items")
local perks = require("src.perks")

local inventory = {}

inventory.WEAPON_SLOTS = 3
inventory.ITEM_SLOTS = 11
local START_ITEM_CHANCE = 0.5

local Inventory = {}
Inventory.__index = Inventory

-- How many weapon slots the hunter has now: Akimbo (an Epic perk) takes the
-- third away, and the guns in the first two are held and fired together
function inventory.weaponSlots()
  return perks.has("akimbo") and 2 or inventory.WEAPON_SLOTS
end

function inventory.akimbo()
  return perks.has("akimbo")
end

function inventory.reloadsHolstered(gun)
  return perks.sum("bgReload") > 0 or gun:stats().bgReload > 0
end

-- Set by src.meta: function(base chance) -> the chance the starting revolver
-- comes with an item fitted (the Gunsmith's Loaded Holster makes it certain)
inventory.startItemChance = nil

-- Every run starts with a revolver that has rolled its own stat variation
-- and, half the time, one ammo type or attachment already fitted (never a
-- cursed one)
function inventory.starterGun()
  local gun = guns.generate("revolver", nil, 0)
  local chance = inventory.startItemChance and inventory.startItemChance(START_ITEM_CHANCE) or START_ITEM_CHANCE
  if love.math.random() < chance then
    local item
    for _ = 1, 50 do
      item = items.random()
      if item.rarity ~= "cursed" then
        break
      end
    end
    if item and item.rarity ~= "cursed" then
      gun.slots[love.math.random(1, gun.slotCount)] = item
    end
  end
  return gun
end

function inventory.new()
  local self = setmetatable({ weapons = {}, items = {}, perks = {}, selected = 1, gold = 0, fuse = fuser.new() }, Inventory)
  perks.bind(self)
  self.weapons[1] = inventory.starterGun()
  self.dynamite = inventory.startDynamite and inventory.startDynamite() or 0
  self.flasks = inventory.startFlasks and inventory.startFlasks() or 0
  return self
end

-- Set by src.meta: sticks of dynamite a run starts with
inventory.startDynamite = nil
inventory.startFlasks = nil

function Inventory:selectedGun()
  if inventory.akimbo() then
    return self.weapons[1] or self.weapons[2] -- (both are held: the first fires as the main gun)
  end
  return self.weapons[self.selected]
end

-- Akimbo: the gun in the other hand (nil without the perk or a second gun)
function Inventory:offhandGun()
  if inventory.akimbo() and self.weapons[1] then
    return self.weapons[2]
  end
  return nil
end

-- Akimbo taken: the third slot is gone. Its gun moves to an empty slot if
-- there is one; otherwise it is returned, for the caller to drop.
function Inventory:foldThirdSlot()
  local gun = self.weapons[3]
  self.weapons[3] = nil
  if self.selected > 2 then
    self.selected = 1
  end
  if gun then
    for i = 1, 2 do
      if not self.weapons[i] then
        self.weapons[i] = gun
        return nil
      end
    end
  end
  return gun
end

-- Selects a weapon slot, empty or not: an empty slot means bare hands
function Inventory:select(index)
  if index >= 1 and index <= inventory.weaponSlots() then
    self.selected = index
  end
end

-- Steps to the next/previous weapon slot (mouse wheel), empty ones included
function Inventory:cycle(dir)
  local n = inventory.weaponSlots()
  self.selected = (math.min(self.selected, n) - 1 + dir) % n + 1
end

-- Where a picked-up weapon goes: the selected slot if it is empty, else the
-- first empty one (nil if all are full)
function Inventory:freeWeaponSlot()
  if not self.weapons[self.selected] then
    return self.selected
  end
  for i = 1, inventory.weaponSlots() do
    if not self.weapons[i] then
      return i
    end
  end
  return nil
end

-- Only the held gun reloads. Switching away mid-reload cancels it (it starts
-- over when you switch back), unless the gun can reload holstered (the Holster
-- Loader attachment) or you have the Juggler perk.
function Inventory:update(dt)
  local held = self:selectedGun()
  local held2 = self:offhandGun()
  if self.lastHeld and self.lastHeld ~= held then
    if not inventory.reloadsHolstered(self.lastHeld) then
      self.lastHeld:cancelReload()
    end
  end
  self.lastHeld = held
  for i = 1, inventory.WEAPON_SLOTS do
    local gun = self.weapons[i]
    if gun then
      if gun == held or gun == held2 or inventory.reloadsHolstered(gun) then
        gun:update(dt)
      else
        gun:updateHolstered(dt)
      end
    end
  end
end

-- Slot references let the UI move things around generically:
--   { kind = "weapon", index }            one of the 3 weapon slots
--   { kind = "item", index }              one of the 7 loose item slots
--   { kind = "gunSlot", gun, index }      a slot on a specific gun
--   { kind = "fuse", index }              one of the fuser's 2 slots (src.fuser)
function Inventory:get(ref)
  if ref.kind == "fuse" then
    return self.fuse.slots[ref.index]
  elseif ref.kind == "perk" then
    return ref.perk -- shown in the panel for its tooltip only
  elseif ref.kind == "weapon" then
    return self.weapons[ref.index]
  elseif ref.kind == "item" then
    return self.items[ref.index]
  end
  return ref.gun.slots[ref.index]
end

function Inventory:set(ref, value)
  if ref.kind == "fuse" then
    self.fuse.slots[ref.index] = value
  elseif ref.kind == "weapon" then
    self.weapons[ref.index] = value
  elseif ref.kind == "item" then
    self.items[ref.index] = value
  else
    ref.gun.slots[ref.index] = value
  end
end

-- Weapons only go in weapon slots; ammo and attachments go anywhere else
local function accepts(ref, thing)
  if thing == nil then
    return true
  end
  local isWeapon = getmetatable(thing) ~= nil and thing.def ~= nil
  return (ref.kind == "weapon") == isWeapon
end

-- Moves the contents of one slot to another, swapping if the target is full.
-- Returns true if anything moved.
function Inventory:move(from, to)
  if from.kind == "perk" or to.kind == "perk" or from.kind == "fuseToggle" or to.kind == "fuseToggle" then
    return false
  end
  -- A locked fuser holds on to its two items
  if self.fuse.locked and (from.kind == "fuse" or to.kind == "fuse") then
    return false
  end
  local a, b = self:get(from), self:get(to)
  if a == nil or not accepts(to, a) or not accepts(from, b) then
    return false
  end
  self:set(to, a)
  self:set(from, b)
  -- Keep the same weapon selected if it was the one moved
  if from.kind == "weapon" and to.kind == "weapon" then
    if self.selected == from.index then
      self.selected = to.index
    elseif self.selected == to.index then
      self.selected = from.index
    end
  end
  return true
end

function Inventory:hasRoom()
  for i = 1, inventory.ITEM_SLOTS do
    if not self.items[i] then
      return true
    end
  end
  return false
end

-- Puts an item in the first free loose slot. Returns false if full.
function Inventory:addItem(item)
  for i = 1, inventory.ITEM_SLOTS do
    if not self.items[i] then
      self.items[i] = item
      return true
    end
  end
  return false
end

return inventory
