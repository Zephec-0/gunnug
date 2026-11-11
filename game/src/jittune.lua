-- LuaJIT's limits on compiled code, raised. Require this first, in every Lua state (main.lua, src/genthread.lua).
--
-- LuaJIT keeps at most 1000 compiled traces and 512 KB of machine code by default, and when either runs out it
-- throws ALL of its compiled code away and starts again. This game is far bigger than that: measured in a fight
-- (2026-11-10) it filled the limits and flushed about every 9 frames, 160,000 traces recompiled in 12 seconds, so
-- most of each frame went to the compiler and to code running interpreted in the meantime. With room for all of
-- it nothing is flushed: the same fight went from about 60 fps to about 120, and the garbage per frame fell by
-- more than half (interpreted code boxes more numbers).
--
-- maxtrace: traces kept (65535 is LuaJIT's ceiling). maxmcode: machine code in KB, in all. sizemcode: KB per
-- block of it. The memory is only taken as traces are made (about 20,000 after a long session).
local ok, opt = pcall(require, "jit.opt")
if ok and opt and jit and jit.status and jit.status() then
  pcall(opt.start, "maxtrace=60000", "maxmcode=262144", "sizemcode=256")
end
return true
