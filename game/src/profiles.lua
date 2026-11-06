-- Mountain silhouettes as data, so the same function can be made on the main thread (the area's theme) and on a
-- worker thread that builds the area (a function cannot be sent to it, its description can: see src.genworker).
-- A profile is function(y) -> the x range of the rock at height y (xa, xb), or nil above the summit.
local profiles = {}

-- A flank rising from xGround at the ground line to xTop at the summit, `rise` px up (run px across), the rock
-- reaching `right` on the other side; the plain's rock below the ground line
function profiles.flank(d)
  local slope = d.run / d.rise
  return function(y)
    if y < d.summit then
      return nil
    end
    if y >= d.ground then
      return d.xGround, d.right
    end
    return math.floor(d.xTop + (d.ground - y) * slope), d.right
  end
end

function profiles.make(d)
  return profiles[d.kind](d)
end

return profiles
