-- Rebindable keys (design doc §9b). Gameplay code asks for actions, not
-- keys: input.down("jump") while held, input.is("jump", key) in keypressed.
-- Each action has up to two keys (a main and a spare); the settings save
-- the bindings (src.settings) and the Controls page edits them.
--
-- Adding an action: add it to ACTIONS (in the order the Controls page lists
-- it) with its default keys.
local input = {}

input.ACTIONS = {
  { id = "left", name = "Move left", keys = { "a", "left" } },
  { id = "right", name = "Move right", keys = { "d", "right" } },
  { id = "jump", name = "Jump", keys = { "w", "space" } },
  { id = "down", name = "Drop through ledge", keys = { "s", "down" } },
  { id = "crouch", name = "Crouch / slide", keys = { "lctrl", "rctrl" } },
  { id = "roll", name = "Dodge roll", keys = { "lshift", "rshift" } },
  { id = "kick", name = "Kick", keys = { "f" } },
  { id = "interact", name = "Interact / pick up", keys = { "e" } },
  { id = "inventory", name = "Weapon panel", keys = { "tab" } },
  { id = "fuse", name = "Lock / release fuser", keys = { "g" } },
  { id = "throw", name = "Throw dynamite", keys = { "q" } },
  { id = "heal", name = "Drink flask", keys = { "h" } },
  { id = "map", name = "Survey map", keys = { "m" } },
  { id = "weapon1", name = "Weapon 1", keys = { "1" } },
  { id = "weapon2", name = "Weapon 2", keys = { "2" } },
  { id = "weapon3", name = "Weapon 3", keys = { "3" } },
  { id = "restart", name = "Restart run (hold)", keys = { "r" } },
}

-- The mouse isn't rebindable; the Controls page lists it for reference
input.FIXED = {
  { "Fire", "Left mouse" },
  { "Reload", "Right mouse" },
  { "Switch weapon", "Mouse wheel" },
  { "Pause", "Escape" },
}

-- Keys that can't be bound (they belong to the menus and debug tools)
local RESERVED = { escape = true, f1 = true, f2 = true, f3 = true, f5 = true, f6 = true, f8 = true, f9 = true, f10 = true, f11 = true }

local byId = {}
for _, a in ipairs(input.ACTIONS) do
  byId[a.id] = a
end

local bindings = {} -- action id -> { key1, key2 }

function input.defaults()
  local t = {}
  for _, a in ipairs(input.ACTIONS) do
    t[a.id] = { a.keys[1] or false, a.keys[2] or false }
  end
  return t
end

-- Adopts saved bindings (missing or unknown actions fall back to defaults)
function input.load(saved)
  bindings = input.defaults()
  if type(saved) == "table" then
    for id, keys in pairs(saved) do
      if byId[id] and type(keys) == "table" then
        bindings[id] = { keys[1] or false, keys[2] or false }
      end
    end
  end
end

function input.bindings()
  return bindings
end

function input.keys(id)
  return bindings[id] or { false, false }
end

function input.isReserved(key)
  return RESERVED[key] == true
end

-- Binds key to slot (1 or 2) of an action; the key is taken off any other
-- action that used it. key false clears the slot.
function input.bind(id, slot, key)
  if not bindings[id] then
    return
  end
  if key then
    for _, keys in pairs(bindings) do
      for s = 1, 2 do
        if keys[s] == key then
          keys[s] = false
        end
      end
    end
  end
  bindings[id][slot] = key or false
end

-- Drunk: the movement keys stumble. In a stumble the move and jump keys read as dropped (the hunter
-- falters) or move/left swapped (he lurches the wrong way); how often and how long grows with `drunk` (0..1)
local stumble = { left = 0, mode = "drop", wait = 0 }
local OPPOSITE = { left = "right", right = "left" }

function input.tick(dt, drunk)
  if (drunk or 0) <= 0 then
    stumble.left, stumble.wait = 0, 0
    return
  end
  if stumble.left > 0 then
    stumble.left = stumble.left - dt
    return
  end
  stumble.wait = stumble.wait - dt
  if stumble.wait <= 0 then
    stumble.mode = love.math.random() < 0.55 and "drop" or "swap"
    stumble.left = 0.2 + 0.5 * drunk * love.math.random()
    stumble.wait = (1.1 - 0.8 * drunk) * (0.4 + love.math.random())
  end
end

-- True while any key bound to the action is held
function input.down(id)
  if stumble.left > 0 then
    if stumble.mode == "drop" and (id == "left" or id == "right" or id == "jump") then
      return false
    elseif stumble.mode == "swap" and OPPOSITE[id] then
      id = OPPOSITE[id]
    end
  end
  local keys = bindings[id]
  if not keys then
    return false
  end
  for s = 1, 2 do
    if keys[s] and love.keyboard.isDown(keys[s]) then
      return true
    end
  end
  return false
end

-- True if key is bound to the action
function input.is(id, key)
  local keys = bindings[id]
  return keys ~= nil and key ~= nil and (keys[1] == key or keys[2] == key)
end

-- The key an action is bound to, for prompts ("[E] Open chest"); the spare
-- if the main one is cleared
function input.label(id)
  local keys = bindings[id] or {}
  return input.keyName(keys[1] or keys[2])
end

local NAMES = {
  space = "Space", lshift = "L Shift", rshift = "R Shift", lctrl = "L Ctrl", rctrl = "R Ctrl",
  lalt = "L Alt", ralt = "R Alt", tab = "Tab", ["return"] = "Enter", backspace = "Backspace",
  up = "Up", down = "Down", left = "Left", right = "Right", capslock = "Caps Lock",
  kpenter = "Num Enter", lgui = "L Win", rgui = "R Win", delete = "Delete", insert = "Insert",
  home = "Home", ["end"] = "End", pageup = "Page Up", pagedown = "Page Down",
}

-- A key's name as shown on the Controls page
function input.keyName(key)
  if not key then
    return "-"
  end
  if NAMES[key] then
    return NAMES[key]
  end
  if key:match("^kp") then
    return "Num " .. key:sub(3):upper()
  end
  return key:upper()
end

input.load(nil)

return input
