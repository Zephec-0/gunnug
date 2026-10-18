-- Undo/redo as whole-document snapshots. Pixel data is kept as Lua strings, which are interned, so
-- cels that did not change between snapshots share the same memory.
local doc = require("src.doc")

local H = { undo = {}, redo = {}, cur = nil, version = 0, LIMIT = 200 }

function H.reset(D)
  H.undo, H.redo = {}, {}
  H.cur = doc.toTable(D, false)
  H.version = H.version + 1
end

-- Records the document's current state as a new step
function H.commit(D)
  H.undo[#H.undo + 1] = H.cur
  if #H.undo > H.LIMIT then table.remove(H.undo, 1) end
  H.cur = doc.toTable(D, false)
  H.redo = {}
  H.version = H.version + 1
end

-- Returns the restored document, or nil when there is nothing to undo
function H.stepBack()
  if #H.undo == 0 then return nil end
  H.redo[#H.redo + 1] = H.cur
  H.cur = table.remove(H.undo)
  H.version = H.version + 1
  return doc.fromTable(H.cur, false)
end

function H.stepForward()
  if #H.redo == 0 then return nil end
  H.undo[#H.undo + 1] = H.cur
  H.cur = table.remove(H.redo)
  H.version = H.version + 1
  return doc.fromTable(H.cur, false)
end

-- The last committed state (throws away uncommitted edits, like a lifted selection)
function H.revert()
  return doc.fromTable(H.cur, false)
end

return H
