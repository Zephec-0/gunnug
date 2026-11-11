-- Save files (design doc §9c): three profile slots. A profile keeps what the
-- hunter has learned across runs: the compendium (every weapon, ammo type,
-- attachment and perk ever collected, and every monster slain, with counts)
-- and lifetime stats. Runs themselves are roguelike: the only mid-run save is
-- "Save and quit" (see the saved runs below), which is used up when resumed.
-- A profile is chosen on the title screen and every run played after that
-- adds to it.
--
-- A profile is written to the LÖVE save directory as slotN.sav: a plain Lua
-- table literal, loaded back in an empty environment (it can't run code).
-- The previous good copy is kept as slotN.bak in case a write is cut short.
--
-- Recording is keyed by category and id, so new weapons, items, perks and
-- monsters need no changes here:
--   save.record("weapon" | "ammo" | "attachment" | "perk" | "enemy", id, n)
local save = {}

save.SLOTS = 3
save.VERSION = 2 -- 2: marks, the camp's people, upgrades and unlocks (src.meta)

local FLUSH_INTERVAL = 5 -- seconds between writes while something changed

local slots = {} -- index -> profile table, false if empty (loaded lazily)
local active -- index of the slot in use, or nil
local dirty = false
local flushTimer = 0
local lastText = {} -- slot -> the text known to be in its file: read and found good, or written, this session (see the writer thread)

-- Called as onDiscover(category, id) the first time a profile records something
save.onDiscover = nil

local function path(i, ext)
  return "slot" .. i .. "." .. (ext or "sav")
end

-- Serialising -----------------------------------------------------------------------

local function isIdent(k)
  return type(k) == "string" and k:match("^[%a_][%w_]*$") ~= nil
end

local function serialize(v, indent, out)
  local t = type(v)
  if t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then
      out[#out + 1] = "0"
    elseif v == math.floor(v) then
      out[#out + 1] = string.format("%d", v)
    else
      out[#out + 1] = string.format("%.17g", v)
    end
  elseif t == "string" then
    out[#out + 1] = string.format("%q", v)
  elseif t == "boolean" then
    out[#out + 1] = tostring(v)
  elseif t == "table" then
    -- Keys sorted, so the files diff cleanly
    local keys = {}
    for k in pairs(v) do
      if type(k) == "string" or type(k) == "number" then
        keys[#keys + 1] = k
      end
    end
    table.sort(keys, function(a, b)
      if type(a) == type(b) then
        return a < b
      end
      return type(a) == "number"
    end)
    out[#out + 1] = "{\n"
    local inner = indent .. "  "
    for _, k in ipairs(keys) do
      local kind = type(v[k])
      if kind == "number" or kind == "string" or kind == "boolean" or kind == "table" then
        out[#out + 1] = inner
        out[#out + 1] = isIdent(k) and k or ("[" .. (type(k) == "string" and string.format("%q", k) or tostring(k)) .. "]")
        out[#out + 1] = " = "
        serialize(v[k], inner, out)
        out[#out + 1] = ",\n"
      end
    end
    out[#out + 1] = indent .. "}"
  else
    out[#out + 1] = "nil"
  end
end

function save.encode(tbl)
  local out = { "return " }
  serialize(tbl, "", out)
  out[#out + 1] = "\n"
  return table.concat(out)
end

-- Reads a table literal written by save.encode (nil if missing or broken)
function save.decode(text)
  if type(text) ~= "string" then
    return nil
  end
  local chunk = loadstring(text, "save")
  if not chunk then
    return nil
  end
  setfenv(chunk, {})
  local ok, result = pcall(chunk)
  if ok and type(result) == "table" then
    return result
  end
  return nil
end

-- Profiles --------------------------------------------------------------------------

-- Every category a profile counts; listed here only so a fresh profile has
-- them all (record() makes new ones on demand)
save.CATEGORIES = { "weapon", "ammo", "attachment", "perk", "enemy", "condition", "journal" }

local function fresh()
  local p = {
    version = save.VERSION,
    created = os.time(),
    lastPlayed = os.time(),
    playtime = 0, -- seconds in a run (menus and pauses don't count)
    stats = { runs = 0, deaths = 0, gold = 0, kills = 0, bosses = 0, deepest = 0, marksEarned = 0, skyBeaten = 0 },
    found = {},
    -- What carries over between runs (design doc §11a-iv, -v; src.meta):
    marks = 0, -- the permanent currency, spent at camp
    camp = {}, -- id -> true for each person living at camp (freed below)
    upgrades = {}, -- upgrade id -> tier bought
    unlocked = {}, -- category -> { id = true }: taught beyond the starting pool
    seen = {}, -- category -> { id = true }: met, but not necessarily collected
    trophies = {}, -- monster kind -> elites of it slain
    bank = 0, -- gold in the Prospector's strongbox
    bankedPerk = "", -- id of the perk on his shelf (kept between runs; "" for none)
    rules = {}, -- the Bartender's house rules switched on: id -> true
    limbs = {}, -- what the Sawbone has taken (and paid for in bonuses): id -> true
    mounted = {}, -- monster kind -> level the Taxidermist has mounted its trophy to (0 or absent: not yet)
    board = false, -- the bounty board has gone up (an elite slain, then a death)
    hat = "plain", -- the hat worn into the next run (src.meta HATS): some set a rule for the whole run
    -- The Undercroft (docs/undercroft-design.md): the way below the Deep, opened once for good
    undercroft = { open = false, beaten = false },
    secrets = {}, -- secret id -> true, found for good (the Ace of Spades, the full bar tab, ...)
    hatWins = {}, -- hat id -> true: a boss beaten wearing it
  }
  for _, c in ipairs(save.CATEGORIES) do
    p.found[c] = {}
    p.unlocked[c] = {}
    p.seen[c] = {}
  end
  return p
end

-- Fills in anything an older or hand-edited file is missing
local function repair(p)
  local old = tonumber(p.version) or 1
  local base = fresh()
  for k, v in pairs(base) do
    if type(p[k]) ~= type(v) then
      p[k] = v
    end
  end
  for k, v in pairs(base.stats) do
    if type(p.stats[k]) ~= "number" then
      p.stats[k] = v
    end
  end
  for k, v in pairs(base.undercroft) do
    if type(p.undercroft[k]) ~= type(v) then
      p.undercroft[k] = v
    end
  end
  for _, c in ipairs(save.CATEGORIES) do
    for _, key in ipairs({ "found", "unlocked", "seen" }) do
      if type(p[key][c]) ~= "table" then
        p[key][c] = {}
      end
    end
  end
  -- A file from before the unlocks keeps everything it had already found
  if old < 2 then
    for _, c in ipairs(save.CATEGORIES) do
      for id, n in pairs(p.found[c]) do
        if type(n) == "number" and n > 0 then
          p.unlocked[c][id] = true
        end
      end
    end
  end
  p.version = save.VERSION
  return p
end

local function readFile(name)
  if not love.filesystem.getInfo(name) then
    return nil
  end
  local ok, text = pcall(love.filesystem.read, name)
  return ok and save.decode(text) or nil
end

local function load(i)
  if slots[i] == nil then
    local p
    if love.filesystem.getInfo(path(i)) then
      local ok, text = pcall(love.filesystem.read, path(i))
      p = ok and save.decode(text) or nil
      lastText[i] = p and text or nil -- (a good file: its text is the backup for the next write)
    end
    p = p or readFile(path(i, "bak"))
    slots[i] = p and repair(p) or false
  end
  return slots[i] or nil
end

-- The writer thread ---------------------------------------------------------------
--
-- The profile is written every few seconds while it changes (save.update), and the write (the old file read back
-- and checked, the backup written, the file written) took about 7 ms of a frame each time: a dropped frame every
-- five seconds of a fight. Those periodic writes go to a small thread instead. The main thread still makes the
-- text; the thread only puts it on disk, backup first, in the order it was sent.
--
-- What keeps it safe:
--   * the backup it writes is the text this session knows to be in the file (lastText: what it read and found
--     good when the profile was loaded, or what it last wrote), so it is always a good copy and nothing has to
--     be read back;
--   * a write when that text is not known, and every write that is asked for outright (save.flush on quitting, dying or
--     leaving for the title, a new profile, a new name), is done on the main thread as before, after waiting for
--     the thread to finish what it has (drain), so the file is on disk when the call returns and nothing is ever
--     written out of order;
--   * erasing a profile waits for the thread too;
--   * no threads, or the thread failing: everything is written on the main thread, as before.
local writer -- { thread, inCh, outCh, pending }, false if there is none to be had
local WRITER_CODE = [[
require("love.filesystem")
local inCh, outCh = love.thread.getChannel("save_writer_in"), love.thread.getChannel("save_writer_out")
while true do
  local job = inCh:demand()
  if job == "quit" then
    break
  end
  if job.bak then
    love.filesystem.write(job.bakName, job.bak)
  end
  local ok, err = love.filesystem.write(job.name, job.text)
  outCh:push(ok and "ok" or ("could not write " .. job.name .. ": " .. tostring(err)))
end
]]

local function startWriter()
  if writer == nil then
    writer = false
    if love.thread then
      local ok, w = pcall(function()
        local t = { inCh = love.thread.getChannel("save_writer_in"), outCh = love.thread.getChannel("save_writer_out"), pending = 0 }
        t.inCh:clear()
        t.outCh:clear()
        t.thread = love.thread.newThread(WRITER_CODE)
        t.thread:start()
        return t
      end)
      if ok then
        writer = w
      end
    end
  end
  return writer
end

-- Takes in the thread's answers; with wait, until everything it was sent is on disk
local function drain(wait)
  local w = writer
  if not w then
    return
  end
  while w.pending > 0 do
    local res
    if wait then
      res = w.outCh:demand(0.25)
    else
      res = w.outCh:pop()
    end
    if res then
      w.pending = w.pending - 1
      if res ~= "ok" then
        print("save: " .. res)
        lastText = {} -- (what is on disk is not known any more: the next write checks it again)
      end
    elseif not w.thread:isRunning() then
      -- (the thread has died: back to writing on the main thread, and the profile is written again in full)
      print("save: the writer thread stopped (" .. tostring(w.thread:getError()) .. ")")
      writer, lastText, dirty = false, {}, true
      return
    elseif not wait then
      return
    end
  end
end

local function write(i)
  local p = slots[i]
  if not p then
    return
  end
  drain(true) -- (anything the thread still has goes to disk first)
  local text = save.encode(p)
  -- Keep the last good copy before overwriting it
  if love.filesystem.getInfo(path(i)) then
    local ok, old = pcall(love.filesystem.read, path(i))
    if ok and save.decode(old) then
      love.filesystem.write(path(i, "bak"), old)
    end
  end
  local ok, err = love.filesystem.write(path(i), text)
  if not ok then
    print("save: could not write " .. path(i) .. ": " .. tostring(err))
  end
  lastText[i] = ok and text or nil
end

-- The periodic write: handed to the thread when this session knows what is in the file (see above)
local function writeLater(i)
  local p = slots[i]
  if not p then
    return
  end
  local w = lastText[i] and startWriter()
  if not w then
    return write(i)
  end
  drain(false)
  if not writer or not lastText[i] then
    return write(i)
  end
  local text = save.encode(p)
  w.inCh:push({ name = path(i), text = text, bakName = path(i, "bak"), bak = lastText[i] })
  w.pending = w.pending + 1
  lastText[i] = text
end

-- The profile in slot i, or nil if it is empty
function save.peek(i)
  return load(i)
end

-- Makes slot i active, creating a fresh profile if it was empty
function save.use(i)
  if active and active ~= i then
    save.flush()
  end
  if not load(i) then
    slots[i] = fresh()
    write(i)
  end
  active = i
  slots[i].lastPlayed = os.time()
  dirty = true
end

-- Names the hunter of slot i (creating the profile if the slot was empty)
function save.setName(i, name)
  if not load(i) then
    slots[i] = fresh()
  end
  slots[i].name = name
  write(i)
end

-- Deletes the profile in slot i (and its backup and any saved run)
function save.erase(i)
  drain(true)
  lastText[i] = nil
  love.filesystem.remove(path(i))
  love.filesystem.remove(path(i, "bak"))
  save.clearRun(i)
  slots[i] = false
  if active == i then
    active = nil
  end
end

function save.activeSlot()
  return active
end

function save.profile()
  return active and slots[active] or nil
end

-- Writes the active profile now if anything changed
function save.flush()
  if active and dirty then
    write(active)
  end
  drain(true) -- (whatever the writer thread was given is on disk when this returns)
  dirty = false
  flushTimer = 0
end

-- The game is closing: everything on disk, and the writer thread told to stop (writes after this, if any, are
-- made on the main thread)
function save.close()
  save.flush()
  if writer then
    writer.inCh:push("quit")
  end
  writer = false
end

-- Counts time played and writes the profile every few seconds while it changes
function save.update(dt, playing)
  local p = save.profile()
  if not p then
    return
  end
  if playing then
    p.playtime = p.playtime + dt
  end
  flushTimer = flushTimer + dt
  if dirty and flushTimer >= FLUSH_INTERVAL then
    -- (the periodic write: on the writer thread, so it costs the frame only the making of the text)
    if active then
      writeLater(active)
    end
    dirty = false
    flushTimer = 0
  end
end

-- Saved runs -------------------------------------------------------------------------

-- "Save and quit" writes the run in progress to runN.sav, beside the profile of
-- the slot it belongs to: the same kind of table literal, with its own version.
-- It holds what the world can't rebuild by itself (the hunter, his kit, the
-- seed the areas grow from, see src.game); a file that is missing, broken or
-- from another version reads as "no saved run". Resuming deletes it, and so
-- does a death, a restart or leaving the run.
save.RUN_VERSION = 1

local runs = {} -- slot -> saved run, false if none (read lazily)

local function runPath(i)
  return "run" .. i .. ".sav"
end

local function validRun(r)
  return type(r) == "table"
    and r.version == save.RUN_VERSION
    and type(r.seed) == "number"
    and type(r.x) == "number"
    and type(r.y) == "number"
    and type(r.hp) == "number"
    and type(r.inv) == "table"
    and type(r.inv.weapons) == "table"
    and type(r.inv.items) == "table"
end

-- The saved run of slot i, or nil
function save.peekRun(i)
  if runs[i] == nil then
    local r = readFile(runPath(i))
    runs[i] = validRun(r) and r or false
  end
  return runs[i] or nil
end

-- Writes run as slot i's saved run; false if the file could not be written
function save.writeRun(i, run)
  run.version = save.RUN_VERSION
  runs[i] = nil
  local ok, err = love.filesystem.write(runPath(i), save.encode(run))
  if not ok then
    print("save: could not write " .. runPath(i) .. ": " .. tostring(err))
  end
  return ok and true or false
end

function save.clearRun(i)
  if i then
    love.filesystem.remove(runPath(i))
    runs[i] = false
  end
end

-- Recording ------------------------------------------------------------------------

-- Adds n (default 1) to the count of something collected or slain. Returns
-- true the first time this profile records it.
function save.record(category, id, n)
  local p = save.profile()
  if not p or id == nil then
    return false
  end
  local list = p.found[category]
  if not list then
    list = {}
    p.found[category] = list
  end
  local first = (list[id] or 0) <= 0
  list[id] = (list[id] or 0) + (n or 1)
  dirty = true
  if first and save.onDiscover then
    save.onDiscover(category, id)
  end
  return first
end

-- How many of something the profile has recorded (0 if none)
function save.count(category, id, profile)
  profile = profile or save.profile()
  local list = profile and profile.found[category]
  return list and list[id] or 0
end

-- Adds to a lifetime stat
function save.stat(key, n)
  local p = save.profile()
  if p then
    p.stats[key] = (p.stats[key] or 0) + (n or 1)
    dirty = true
  end
end

-- Raises a lifetime stat to v if it is higher (deepest area reached)
function save.statMax(key, v)
  local p = save.profile()
  if p and v > (p.stats[key] or 0) then
    p.stats[key] = v
    dirty = true
  end
end

-- Marks the active profile as changed (for src.meta, which edits it directly)
function save.touch()
  dirty = true
end

-- "3h 05m" / "12m" for a number of seconds
function save.formatTime(seconds)
  local m = math.floor(seconds / 60)
  if m < 60 then
    return m .. "m"
  end
  return string.format("%dh %02dm", math.floor(m / 60), m % 60)
end

-- For tests: forget what's cached so files are read again
function save.reset()
  drain(true)
  lastText = {}
  slots, runs, active, dirty = {}, {}, nil, false
end

return save
