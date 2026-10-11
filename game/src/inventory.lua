-- The player's carried gear (design doc §5.6): 3 weapon slots, the selected
-- weapon, and 7 loose slots for ammo types and attachments not yet fitted to
-- a gun. Owned by the run, so it carries over between areas.
--
-- An item is a table { kind = "ammo" | "attachment", name, short, color }.
-- No items exist in the game yet; the slots are ready for them.
local guns = require("src.guns")

local inventory = {}

inventory.WEAPON_SLOTS = 3
inventory.ITEM_SLOTS = 7

local Inventory = {}
Inventory.__index = Inventory

function inventory.new()
  local self = setmetatable({ weapons = {}, items = {}, selected = 1, gold = 0 }, Inventory)
  -- No weapon pickups yet, so a run starts with one of each archetype
  self.weapons[1] = guns.new("revolver")
  self.weapons[2] = guns.new("shotgun")
  self.weapons[3] = guns.new("automatic")
  return self
end

function Inventory:selectedGun()
  return self.weapons[self.selected]
end

-- Selects a weapon slot if it holds a weapon
function Inventory:select(index)
  if self.weapons[index] then
    self.selected = index
  end
end

-- Steps to the next/previous filled weapon slot (mouse wheel)
function Inventory:cycle(dir)
  for step = 1, inventory.WEAPON_SLOTS do
    local i = (self.selected - 1 + dir * step) % inventory.WEAPON_SLOTS + 1
    if self.weapons[i] then
      self.selected = i
      return
    end
  end
end

-- Every carried gun keeps reloading, held or not
function Inventory:update(dt)
  for i = 1, inventory.WEAPON_SLOTS do
    if self.weapons[i] then
      self.weapons[i]:update(dt)
    end
  end
end

-- Slot references let the UI move things around generically:
--   { kind = "weapon", index }            one of the 3 weapon slots
--   { kind = "item", index }              one of the 7 loose item slots
--   { kind = "gunSlot", gun, index }      a slot on a specific gun
function Inventory:get(ref)
  if ref.kind == "weapon" then
    return self.weapons[ref.index]
  elseif ref.kind == "item" then
    return self.items[ref.index]
  end
  return ref.gun.slots[ref.index]
end

function Inventory:set(ref, value)
  if ref.kind == "weapon" then
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
  if not self.weapons[self.selected] then
    self:cycle(1)
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
