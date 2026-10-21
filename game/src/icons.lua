-- Pixel icons (8x8) for every ammo type, attachment and perk. Each is a grid
-- of palette letters; "c", "d" and "l" are the item's own colour, its shadow
-- and its highlight, so an icon always matches its item. Built once into
-- images with nearest-neighbour filtering.
--
--   . clear    c main colour  d dark  l light
--   w white    k black        s steel S dark steel
--   r red      o orange       y yellow g gold    b brown
--   n green    u blue         p purple m pink
local icons = {}

local FIXED = {
  w = { 0.95, 0.95, 0.97 },
  k = { 0.08, 0.07, 0.10 },
  s = { 0.72, 0.74, 0.80 },
  S = { 0.36, 0.37, 0.44 },
  r = { 0.86, 0.20, 0.22 },
  o = { 1.00, 0.55, 0.15 },
  y = { 1.00, 0.92, 0.40 },
  g = { 0.95, 0.74, 0.22 },
  b = { 0.52, 0.32, 0.16 },
  n = { 0.40, 0.85, 0.35 },
  u = { 0.45, 0.72, 1.00 },
  p = { 0.60, 0.35, 0.85 },
  m = { 0.95, 0.50, 0.72 },
}

local ITEMS = {
  -- Ammo -------------------------------------------------------------------
  slug = { "..cccc..", ".cllccd.", ".cllccd.", ".cccccd.", ".cccccd.", ".cccccd.", ".gggggg.", ".gddddg." },
  piercing = { "...cc...", "...cc...", "..clcd..", "..clcd..", "..gggg..", "..gggg..", "..gddg..", "..dddd.." },
  ricochet = { ".......c", "......cc", ".c...c..", "..c.c...", "...c....", "..c.c...", ".c...c..", "c.....cc" },
  explosive = { "o..o..o.", ".o.yy.o.", "..oyyo..", "ooyyyyoo", "..oyyo..", ".o.yy.o.", "o..o..o.", "........" },
  incendiary = { "...o....", "..oo....", "..ooo.o.", ".ooyoo..", ".oyyyoo.", ".oyyyoo.", "..oyyo..", "...oo..." },
  scatter = { ".c...c..", "........", "..c..c.c", "c.......", "...c.c..", ".c....c.", "....c...", "c..c...c" },
  frost = { "...u....", ".u.u.u..", "..uwu...", "uuwwwuu.", "..uwu...", ".u.u.u..", "...u....", "........" },
  shock = { "....yy..", "...yy...", "..yy....", ".yyyyy..", "...yy...", "..yy....", ".yy.....", ".y......" },
  poison = { "...n....", "...n....", "..nnn...", ".nnlnn..", ".nlnnn..", ".nnnnn..", "..nnn...", "........" },
  vampiric = { ".w....w.", ".ww..ww.", ".ww..ww.", "..wwww..", "...rr...", "..rrrr..", "..rrrr..", "...rr..." },
  gilded = { "..gggg..", ".gyyygg.", "gyygggdg", "gygyygdg", "gygggydg", "gyggggdg", ".gddddg.", "..gggg.." },
  sticky = { ".....y..", "....o...", "..SSSS..", ".SmSSSS.", "SmmSSSSS", "SSSSSSSS", ".SSSSSS.", "..SSSS.." },
  seeker = { "...cc...", ".cc..cc.", ".c.ww.c.", "cc.ww.cc", "cc.ww.cc", ".c.ww.c.", ".cc..cc.", "...cc..." },
  singularity = { "..pppp..", ".pkkkkp.", "pkkpppkp", "pkpkkkkp", "pkpkkpkp", "pkkkkkkp", ".pkkkkp.", "..pppp.." },
  auger = { "...cc...", "..cdc...", "..dcc...", "...cdc..", "..cdc...", "..dcc...", "...cd...", "...dd..." },
  splitting = { "...cc...", "...cc...", "...cc...", "..cddc..", ".cc..cc.", ".c....c.", "c......c", "c......c" },
  boomerang = { "cc....cc", "ccc..ccc", ".ccc.cc.", "..cccc..", "..cccc..", "...cc...", "........", "........" },
  acid = { "..SSSS..", "...SS...", "..SSSS..", ".SnnnnS.", ".SnlnnS.", ".SnnnnS.", ".SSnnSS.", "..SSSS.." },
  concussive = { "w..c..w.", ".w.c.w..", "..wcw...", "cccwccc.", "..wcw...", ".w.c.w..", "w..c..w.", "........" },
  spectral = { "..wwww..", ".wwwwww.", ".wkwwkw.", ".wwwwww.", ".wwwwww.", ".wwwwww.", ".ww.ww.w", ".w..w..w" },
  executioner = { ".wwwwww.", "wwwwwwww", "wkkwwkkw", "wkkwwkkw", "wwwkkwww", ".wwwwww.", ".wkwkwk.", "..wwww.." },
  glowing = { "..yyyy..", ".yyllyy.", ".yylyyy.", ".yyyyyy.", "..yyyy..", "..ssss..", "..SSSS..", "...ss..." },
  cluster = { "..S.....", ".SSS..S.", "..S..SSS", ".....S..", ".S......", "SSS..S..", ".S..SSS.", ".....S.." },
  feather = { "......cc", ".....ccc", "....ccc.", "...ccc..", "..ccc...", ".cccd...", "cdd.....", "d......." },
  blood = { "...r....", "...r....", "..rrr...", ".rrlrr..", ".rrlrr..", ".rrrrr..", "..rrr...", "..kkk..." },
  unstable = { "..y.....", "...o....", ".rrrrrr.", "rrlrrrrr", "rrrrrrrr", "rrrkkrrr", ".rrkkrr.", "..rrrr.." },

  -- Attachments --------------------------------------------------------------
  longbarrel = { "........", "........", ".SSSSSSS", "sssssssS", ".SSSSSSS", "........", "........", "........" },
  extmag = { ".SSSS...", ".SggS...", ".SggS...", ".SggS...", ".SggS...", ".SggS...", ".SggS...", ".SSSS..." },
  compensator = { "........", ".SSSSSS.", ".SkSkSS.", ".sSsSsS.", ".SkSkSS.", ".SSSSSS.", "........", "........" },
  speedloader = { "..gggg..", ".g.gg.g.", "g.g..g.g", "gg....gg", "g.g..g.g", ".g.gg.g.", "..gggg..", "........" },
  hairtrigger = { ".SSSS...", "S....S..", "S....S..", ".SSSS...", "...SrS..", "...Sr...", "....r...", "........" },
  choke = { "ssssssss", ".ssssss.", "..ssss..", "...ss...", "...ss...", "...ss...", "........", "........" },
  charge = { ".bbbbbb.", "bddbbddb", ".bbbbbb.", "bddbbddb", ".bbbbbb.", "bddbbddb", ".bbbbbb.", "...o...." },
  burst = { "........", ".g.g.g..", ".g.g.g..", ".g.g.g..", ".g.g.g..", ".d.d.d..", ".d.d.d..", "........" },
  backblast = { "........", "...c....", "..cc....", ".ccccccc", ".ccccccc", "..cc....", "...c....", "........" },
  primer = { ".cccc...", "c....c..", ".cccc...", "c....c..", ".cccc...", "c....c..", ".cccc...", "........" },
  suppressor = { "........", "........", ".SSSSSSS", "SkSkSkSs", "SSSSSSSs", ".SSSSSSS", "........", "........" },
  laser = { "........", "S.......", "SSrrrrrr", "S.......", "........", "........", "........", "........" },
  bayonet = { "......ss", ".....ss.", "....ss..", "...ss...", ".bbs....", "bbb.....", "b.......", "........" },
  overclock = { "..oooo..", ".o....o.", "o..r...o", "o...r..o", "o....r.o", ".o....o.", "..oooo..", "...kk..." },
  magnet = { "rr....ww", "rr....ww", "rr....ww", "rr....ww", ".rr..ww.", "..rrww..", "...rw...", "........" },
  lantern = { "...ss...", "..ssss..", ".syyyys.", ".syyyys.", ".syyyys.", ".syyyys.", "..ssss..", "...ss..." },
  jets = { "...cc...", "..cccc..", "..cwwc..", "..cccc..", ".ccddcc.", ".c.oo.c.", "...oo...", "...yy..." },
  mortar = { "...ss...", "..ssss..", "..sSsS..", "..ssss..", "..oooo..", "..oooo..", "..dddd..", "........" },
  scavenger = { "..ccc...", ".c...c>.", "c.....c.", "c.....c.", "c.....c.", ".c...c..", "<.ccc...", "........" },
  quickdraw = { ".bbbbbb.", ".bddddb.", ".bdssdb.", ".bdssdb.", ".bddddb.", "..bddb..", "..bbbb..", "........" },
  glassbarrel = { ".wwwwww.", "w.u..u.w", "wu.uu.uw", "wuuuuuuw", "wu.uu.uw", "w.u..u.w", ".wwwwww.", "........" },
  scope = { ".SSSSSS.", "S..c...S", "S..c...S", "SccccccS", "S..c...S", "S..c...S", ".SSSSSS.", "........" },
  stock = { "........", "bbbbbb..", "bddddbb.", "bddddddb", "bddddddb", "bbbbbbb.", "........", "........" },
  penetrator = { ".s..s..s", ".s..s..s", "cccccccc", ".s..s..s", ".s..s..s", "........", "........", "........" },
  stabilizer = { "...ss...", "...ss...", "..s..s..", "..s..s..", ".s....s.", ".s....s.", "ss....ss", "........" },
  holsterloader = { ".bbbbbb.", ".bsssbb.", ".bs.sbb.", ".bsssbb.", ".bbbbbb.", "..c.c...", ".ccccc..", "..c.c..." },
  deadmans = { "..cccc..", ".cddddc.", "cddwwddc", "cdddwddc", "cddwwddc", ".cddddc.", "..cddc..", "...cc..." },
  reckless = { "...rr...", "...rr...", "...rr...", "...rr...", "...rr...", "........", "...rr...", "...rr..." },
  -- Fused (made in the fuser) ------------------------------------------------
  thermal = { "...o.u..", "..oo.uu.", ".ooy.uwu", "oyyo.wwu", "oyyo.wwu", ".ooy.uwu", "..oo.uu.", "...o.u.." },
  hellfume = { "...o....", "..oyo...", "..oyo.n.", ".ooyo.n.", "..o..nnn", "....nnln", "....nnnn", ".....nn." },
  blight = { "..nnnn..", ".nlnnnn.", "nnkknkkn", "nnkknkkn", "nnnnnnnn", ".nnkknn.", "..n..n..", ".n.nn.n." },
  sledge = { ".cccccc.", "clllcccd", "clccccdd", ".cccccd.", "...cd...", "...cd...", "..gggg..", "..gddg.." },
  shrapnel = { "c..c...c", ".c.cc.c.", "..clcc..", "cclllcc.", "..cclc..", ".c.cc.c.", "c...c..c", "...c...." },
  birdshot = { "......cc", ".c...ccc", "....ccc.", "..cccc..", ".clcd.c.", "cdd..c..", "d..c...c", "........" },
  sungold = { "y..y..y.", ".yggggy.", "yggyygg.", ".gyywgy.", "ygyyygy.", ".gggggy.", "y.ggg..y", "...y...." },
  corkscrew = { "...cc...", "..cddc..", ".cd..dc.", "...cdc..", "..cd....", ".cdddc..", "...cd...", "....d..." },
  marksman = { "..SSS...", ".SuuS...", "SSSSSSSS", "sssssssS", "SSSSSSSS", ".bb.....", ".bbb....", "........" },
  drumloader = { "..SSSS..", ".SggggS.", "SggSSggS", "SgS..SgS", "SgS..SgS", "SggSSggS", ".SggggS.", "..SSSS.." },
  braced = { "........", "SSSSSS..", "SbbbbS..", "bbddbbbb", "bddddddb", "bbbbbbbb", "...S..S.", "...S..S." },
  ripper = { "r.r.r...", "r.r.r...", "o.o.o...", ".SSSS...", "S....S..", "S....S..", ".SSSSrr.", "....rr.." },
  prospectlamp = { "...ss...", "..ssss..", ".syyyys.", ".syyyys.", "..ssss..", "g..ss..g", ".g....g.", "gyg..gyg" },
  deadeye = { "...rr...", "..r..r..", ".r....r.", "rr.rr.rr", "rr.rr.rr", ".r....r.", "..r..r..", "...rr..." },
  duelist = { "ss....ss", ".ss..ss.", "..ssss..", "...bb...", "..ssss..", ".ss..ss.", "bb....bb", "bb....bb" },
  assassin = { "......ss", ".....ss.", "....ss..", "kkkss...", "kwkwk...", "kkkkk...", ".bkk....", "b......." },
  twinblast = { "o......o", "oo....oo", "ooooyooo", "oyyyyyyo", "oyyyyyyo", "ooooyooo", "oo....oo", "o......o" },
  -- Batch 2 ammo ----------------------------------------------------------------
  hollowpoint = { "..cccc..", "..ckkc..", ".cclcdc.", ".cclccd.", ".cclccd.", ".gggggg.", ".gggggg.", ".gddddg." },
  tracer = { "...yy...", "..yccy..", "..clcd..", "..clcd..", "..cccd..", "...yy...", "...oo...", "....o..." },
  flechette = { "...ss...", "...ss...", "...cd...", "...cd...", "...cd...", ".c.cd.d.", "cc.cd.dd", "...cd..." },
  barbed = { "...cc...", "..clcd..", "c.clcd.d", "cc.cd.dd", "..clcd..", "c.cccc.d", "cc.cd.dd", "..gggg.." },
  rubber = { "..cccc..", ".cllccc.", "cllcccdc", "clccccdc", "cccccddc", "cccccdd.", ".cdddd..", "..dd...." },
  dumdum = { ".cccccc.", ".clllcc.", ".clccdc.", ".cccccd.", ".cccccd.", ".gggggg.", ".gggggg.", ".gddddg." },
  lucky = { "..cc.cc.", ".cllcccc", ".cllcccc", "..cccdd.", ".cccdddc", ".cccdddc", "..cc.cd.", "...cd..." },
  brass = { "...gg...", "..gggg..", ".cclccd.", ".cclccd.", ".cclccd.", ".cccccd.", ".cccccd.", ".cddddd." },
  lightload = { "........", "...cc...", "..clcd..", "..clcd..", "..cccd..", "..cccd..", "..gggg..", "........" },
  leechround = { ".cc.....", "cllc.r..", "ccccrr..", ".cccrrr.", "..ccrrr.", "...crr..", "....rr..", "........" },
  -- Batch 2 attachments ---------------------------------------------------------
  foregrip = { "..SSSS..", "..cccc..", "..clcd..", "..clcd..", "..clcd..", "..clcd..", "..cddd..", "..dddd.." },
  sights = { "........", "...SS...", "...SS...", "S..SS..S", "S..cc..S", "SSSSSSSS", ".SSSSSS.", "........" },
  brake = { "........", ".sssss..", "SSSSSSS.", "SkSkSkSS", "SSSSSSS.", ".SSSSS..", "........", "........" },
  heavybarrel = { "........", "SSSSSSSS", "ssssssss", "sscccdss", "SScccdSS", "SSSSSSSS", "........", "........" },
  lightframe = { "cccccccc", "c......c", "c.cccc.c", "c.c..c.c", "c.cccc.c", "c......c", "cccccccc", "........" },
  clips = { ".c.c.c.c", "cgcgcgcg", "cgcgcgcg", "cgcgcgcg", "SSSSSSSS", "SSSSSSSS", "........", "........" },
  pouch = { "..cccc..", ".cddddc.", "cccccccc", "ccggcccc", "ccggcccc", "cccccccc", ".cddddc.", "........" },
  rangefinder = { "..S..S..", ".SSSSSS.", "SuuSSuuS", "SuwSSwuS", "SuuSSuuS", ".SSSSSS.", "........", "........" },
  sawnstock = { "........", "........", "bbbbbbrr", "bdddddbb", "bddddddb", "bbbbbbbb", "....bb..", "........" },
  pick = { "..sssss.", ".s...ssS", "s.....sS", "....b..S", ".....b..", "....b...", "...b....", "..b....." },
  -- Batch 2 rares ---------------------------------------------------------------
  stormround = { "...cc...", "..cc....", ".clccc..", "...cc...", "..cc....", ".cc.....", "........", "........" },
  marked = { "...c....", "...c....", ".cc.cc..", "cc.rr.cc", "cc.rr.cc", ".cc.cc..", "...c....", "...c...." },
  siphon = { "...r....", "..rr....", ".rrrr...", ".rlrr...", ".rrrr.cc", "..rr.cc.", "....cc..", "...cc..." },
  quicksilver = { "...cc...", "..cllc..", ".clcccc.", "clcccccd", "cccccddd", ".cccddd.", "..cddd..", "........" },
  napalm = { "...o.o..", "..ooyo..", "..oyyo..", ".SSSSSS.", ".SoooSS.", ".SoyoSS.", ".SSSSSS.", "........" },
  hemorrhage = { "...r....", "..rrr...", "..rlr...", ".rrrrr..", ".rrrrr..", "..rrr..r", "rr...rrr", "rrr..rr." },
  grapeshot = { ".cc..cc.", "cllc.cdd", "cccc.ddd", ".cc.cc..", "..cllc..", ".cccccd.", "cc.cdd.c", "cc..cc.." },
  rebound = { "......cc", ".c...c.c", "c.c.c...", "..c.....", "...c....", "..c.c...", ".c...c..", "cc.ww..." },
  longrifle = { "...ss...", "..scds..", "..cccd..", "..cccd..", "..cccd..", "..cccd..", "..cccd..", "..gddg.." },
  gambler = { "cccccccd", "cwcccwcd", "cccccccd", "cccwcccd", "cccccccd", "cwcccwcd", "cccccccd", "dddddddd" },
  reaper = { ".cccccc.", "c.....cc", "......cc", ".....b..", "....b...", "...b....", "..b.....", ".b......" },
  rampant = { "......cc", ".....ccc", "....cccc", "...ccccc", "..cccccc", ".ccccccc", "cccccccc", "dddddddd" },
  quadburst = { "o.o.o.o.", "c.c.c.c.", "c.c.c.c.", "c.c.c.c.", "d.d.d.d.", "d.d.d.d.", "........", "........" },
  demosleeve = { ".SSSSSS.", "SooooooS", "SoyyyyoS", "SoyyyyoS", "SooooooS", ".SSSSSS.", "..o..o..", "........" },
  phasebarrel = { "........", "c.c.c.c.", "c......c", "c.cccc.c", "c......c", "c.c.c.c.", "........", "........" },
  fang = { ".wwwwww.", ".wwwwww.", "..wwww..", "..wwwd..", "..wwd...", "...wd...", "...rd...", "....r..." },
  reloadengine = { ".c.cc.c.", "cccccccc", ".cd..dc.", "ccd..dcc", "ccd..dcc", ".cd..dc.", "cccccccc", ".c.cc.c." },
  treasurebarrel = { "........", "SSSSSSS.", "sssssssS", "SSSSggSS", "....gyyg", "....gggg", "........", "........" },
  huntersscope = { "..SSSS..", ".S.cc.S.", "S..cc..S", "SccwwccS", "S..cc..S", ".S.cc.S.", "..SSSS..", "........" },
  killswitch = { "...rr...", "...rr...", "...rr...", "..SSSS..", ".SSkkSS.", "SSSkkSSS", "SSSSSSSS", "........" },
  -- Batch 2 epics ---------------------------------------------------------------
  tempest = { ".cccc...", "cllccc..", "cccccccc", ".cccccc.", "..yy....", "...yy...", "..yy....", ".y......" },
  phoenix = { "oo....oo", "ooo..ooo", ".ooyyoo.", ".ooyyoo.", "..oyyo..", "...yy...", "..y..y..", ".y....y." },
  voidround = { ".pp..pp.", "p..kk..p", ".kkkkkk.", "kkkwwkkk", "kkkwwkkk", ".kkkkkk.", "p..kk..p", ".pp..pp." },
  omen = { "c..c..c.", ".c.cc.c.", "..cwwc..", "cwkkkkwc", "cwkkkkwc", "..cwwc..", ".c.cc.c.", "c..c..c." },
  warlord = { "c..c..c.", "cc.cc.cc", "cccccccc", "clccccld", "cccccccc", "cddddddd", "cccccccc", "........" },
  -- Fused -------------------------------------------------------------------------
  mushroom = { "..cccc..", ".cclccd.", "cclcccdd", "cccccddd", "dddddddd", "...ww...", "...ww...", "...ww..." },
  beacon = { "...yy...", "..yyyy..", ".yywwyy.", "..yyyy..", "...ss...", "...SS...", "..SSSS..", "........" },
  rotround = { "...nn...", "..nnnn..", ".nrnnnn.", ".nnnnrn.", "..nrnn..", "..nnnn..", "...rr...", "...r...." },
  pinball = { ".c...c..", "c.c.c.c.", "..c.c..c", "...c....", "..cccc..", ".cllccd.", ".cccccd.", "..cddd.." },
  fortune = { "...y....", ".c.y.c..", "..cyc...", "yyyyyyy.", "..cyc...", ".c.y.c..", "...y....", "........" },
  harness = { "SS....SS", "bSbbbbSb", "bbSbbSbb", "bbbSSbbb", "bbbSSbbb", "bbSbbSbb", "bSbbbbSb", "SS....SS" },
  sniperkit = { "........", "SSSSSSSS", "SuuccuuS", "SSSSSSSS", "........", "..ggggg.", "..gddd.s", "........" },
  breacher = { "bbbbbbbb", "bddddddb", "bdooooob", "bdoyyyob", "bdoyyyob", "bdooooob", "bddddddb", "bbbbbbbb" },
  quickrig = { "b.......", "bgb.....", ".bgb....", "..bgb...", "...bgb..", "....bgb.", ".....bgb", "......bb" },
  stormseeker = { "...yy...", ".cyy..c.", "c.yy...c", "c.yyyy.c", "c...yy.c", "c..yy..c", ".c.y..c.", "...cc..." },
  crimsontithe = { "r.....r.", "rrrrrrrr", "rkrrrrkr", ".rrrrrr.", "..rrrr..", "...rr...", "...ww...", ".wwwwww." },
  billiard = { "..cccc..", ".cllccc.", "clcwwccd", "ccwkkwcd", "ccwkkwcd", "cccwwcdd", ".cdddddd", "..cddd.." },
  deathcycle = { ".wwwwww.", "wwwwwwww", "wkkwwkkw", "wwwkkwww", ".wwwwww.", "..wkwk..", "c.wwww.c", ".cc..cc." },
  executorseye = { "...r....", ".cccccc.", "cwwrrwwc", "cwrkkrwc", "cwwrrwwc", ".cccccc.", "...r....", "........" },
}

local PERKS = {
  thick_skin = { ".cccccc.", ".cllccc.", ".cllccd.", ".cccccd.", "..cccd..", "..cccd..", "...cd...", "........" },
  iron_will = { "ssssssss", "sSSsSSss", "sSssssSs", "sSssssSs", ".sSssSs.", "..sSSs..", "...ss...", "........" },
  second_wind = { ".cccc...", "c....c..", ".....c..", ".ccccc..", "c.......", "c....c..", ".cccc...", "........" },
  scar_tissue = { "..wwww..", "..wrrw..", "wwwrrwww", "wrrrrrrw", "wrrrrrrw", "wwwrrwww", "..wrrw..", "..wwww.." },
  last_stand = { ".rr..rr.", "rrrrrrrr", "rrrkrrrr", "rrrrkrrr", ".rrkrrr.", "..rrkr..", "...rr...", "........" },
  regeneration = { ".nn..nn.", "nnnnnnnn", "nnnwwnnn", "nnnwwnnn", ".nnnnnn.", "..nnnn..", "...nn...", "........" },
  bloodthirst = { "...r....", "..rrr...", ".rrrrr..", ".rrwrr..", ".rrrrr..", "..rrr...", "..w.w...", "........" },
  adrenaline = { ".......s", "......s.", ".....wr.", "....wrr.", "...wrr..", "..sss...", ".s......", "s......." },
  springheel = { "...c....", "..ccc...", ".c.c.c..", "...c....", "bbbb....", "bbbbb...", "bbbbbb..", "dddddd.." },
  fleet_foot = { "w.......", "ww.bbb..", "www.bb..", "ww.bbbb.", "w..bbbb.", "...bbbbb", "...ddddd", "........" },
  slick_soles = { ".bbb....", ".bbb....", ".bbb....", "bbbbbb..", "dddddd..", "ssssssss", ".s....s.", "........" },
  double_jump = { "...uu...", "..uuuu..", ".uu..uu.", "........", "...uu...", "..uuuu..", ".uu..uu.", "........" },
  prospector = { ".sssss..", "s...s...", "....b...", "....b...", "....b...", "....b...", "....b...", "........" },
  haggler = { "..bb....", "...bb...", "..bbbb..", ".bbggbb.", ".bgyybb.", ".bbggbb.", ".bbbbbb.", "..bbbb.." },
  lucky_find = { ".nn.nn..", "nnnnnnn.", "nnnnnnn.", ".nnnnn..", "nnnnnnn.", "nnnnnnn.", ".nn.nn..", "...b...." },
  magnetic_pockets = { "r....w..", "r....w..", "rr..ww..", ".rrww...", ".....gg.", "....gyyg", "....gggg", "........" },
  sharp_eyes = { "........", "..cccc..", ".cwwwwc.", "cwwkkwwc", "cwwkkwwc", ".cwwwwc.", "..cccc..", "........" },
  heavy_hitter = { ".ssssss.", ".ssSSss.", ".ssssss.", "...bb...", "...bb...", "...bb...", "...bb...", "........" },
  quick_hands = { "wwwwwwww", ".wyyyyw.", "..wyyw..", "...ww...", "...ww...", "..w..w..", ".wyyyyw.", "wwwwwwww" },
  momentum = { "oo..oo..", ".oo..oo.", "..oo..oo", "...oo..o", "...oo..o", "..oo..oo", ".oo..oo.", "oo..oo.." },
  pyromaniac = { "..o.o...", "..ooo.o.", ".ooyoo..", ".oyyyo..", "oyykkyo.", "oyyyyyo.", ".oyyyo..", "..ooo..." },
  ricochet_master = { "c.....c.", "cc...cc.", ".cc.cc..", "..ccc...", "...c....", "..c.c...", ".c...c..", "c.....c." },
  akimbo = { "........", "ssssss..", "SSSSScc.", ".....cc.", "........", "..ssssss", ".ccSSSSS", ".cc.....", },
  diving_helm = { "..gggg..", ".gggggg.", "gccccccg", "gcuwuucg", "gcuuuucg", "gccccccg", ".gddddgg", ".......g", },
  needle_sight = { "......ss", ".....ss.", "....ss..", "...ss...", "..ss....", ".ss.....", "sw......", "w......." },
  death_burst = { "o.w..w.o", ".wwwwww.", "wwkwwkww", "wwwwwwww", ".wkwkw..", "o.wwww.o", "........", "........" },
  juggler = { "..c.....", ".ccc..c.", "..c..ccc", ".....c..", ".c......", "ccc..c..", ".c..ccc.", ".....c.." },
  kicker = { "...bb..o", "...bb.o.", "...bb...", "..bbbbb.", ".bbbbbbb", ".bbbbbbb", ".dddddd.", "........" },
  glass_cannon = { "..uuuu..", ".uuwuuu.", "uuuwuuuu", "uuwuuwuu", "uuuuwuuu", ".uuuuuu.", "..uuuu..", "........" },
  devils_bargain = { "r......r", "rr....rr", ".rrrrrr.", ".rkrrkr.", ".rrrrrr.", ".rrwwrr.", "..rrrr..", "........" },
  greedy_hands = { "..gggg..", ".gyyyyg.", ".gyyyyg.", "..gggg..", "ww.ww.ww", "wwwwwwww", ".wwwwww.", "........" },
  berserker = { "..sss...", ".ssSss..", ".ssSsb..", "..sbb...", "...b....", "...b....", "...b....", "........" },
  pact_of_pain = { "wwwwww..", "wddddw..", "wdrrdw..", "wdrrdw..", "wddddw..", "wwwwww..", ".rrr....", "........" },
}

local cache = {}

local function shade(c, k)
  return { c[1] * k, c[2] * k, c[3] * k }
end

local function light(c)
  return { c[1] + (1 - c[1]) * 0.55, c[2] + (1 - c[2]) * 0.55, c[3] + (1 - c[3]) * 0.55 }
end

-- The grid for a thing ({ id, isPerk? }), or nil if it has no icon yet
function icons.rows(thing)
  return (thing.isPerk and PERKS or ITEMS)[thing.id]
end

-- An 8x8 image for an ammo type, attachment or perk (nil if none)
function icons.get(thing)
  local key = (thing.isPerk and "p:" or "i:") .. tostring(thing.id)
  if cache[key] == nil then
    local rows = icons.rows(thing)
    if not rows then
      cache[key] = false
    else
      local base = thing.color or { 0.7, 0.7, 0.7 }
      local palette = { c = base, d = shade(base, 0.55), l = light(base) }
      local data = love.image.newImageData(8, 8)
      for y, row in ipairs(rows) do
        for x = 1, 8 do
          local ch = row:sub(x, x)
          local c = palette[ch] or FIXED[ch]
          if c then
            data:setPixel(x - 1, y - 1, c[1], c[2], c[3], 1)
          end
        end
      end
      local img = love.graphics.newImage(data)
      img:setFilter("nearest", "nearest")
      cache[key] = img
    end
  end
  return cache[key] or nil
end

-- The same icon for the interface (the compendium, the item bar, the shop and camp
-- pages), in a flatter 16-bit style: the 8x8 art doubled to 16x16 (each pixel a 2x2 block:
-- flat colours, hard edges, no blending), one flat
-- step lighter along the top and one darker along the bottom of any part two pixels
-- thick, and a very soft drop shadow baked in around it. The image is the 16x16 art
-- with HD_PAD pixels of room on every side for the shadow, nearest filtered. (The
-- world still uses the plain 8x8 from icons.get: it is drawn at the game's own scale.)
icons.HD_SIZE = 16
icons.HD_PAD = 2
local hdCache = {}
local hdShadow = setmetatable({}, { __mode = "k" }) -- art image -> its soft shadow image
local hdBox = setmetatable({}, { __mode = "k" }) -- art image -> { x0, y0, x1, y1 }: where the art is drawn within it

local function mix(c, to, k)
  return { c[1] + (to[1] - c[1]) * k, c[2] + (to[2] - c[2]) * k, c[3] + (to[3] - c[3]) * k }
end

local WHITE, SHADOW = { 1, 1, 1 }, { 0.04, 0.03, 0.08 }
local DROP = { 0.02, 0.01, 0.04 }
local DROP_ALPHA = 0.4

function icons.getHD(thing)
  local key = (thing.isPerk and "p:" or "i:") .. tostring(thing.id)
  local hit = hdCache[key]
  if hit ~= nil then
    return hit or nil
  end
  local rows = icons.rows(thing)
  if not rows then
    hdCache[key] = false
    return nil
  end
  local base = thing.color or { 0.7, 0.7, 0.7 }
  local palette = { c = base, d = shade(base, 0.55), l = light(base) }
  local N, PAD = icons.HD_SIZE, icons.HD_PAD
  local function src(x, y) -- the source pixel's palette letter ("." for clear)
    local ch = rows[y]:sub(x, x)
    return (palette[ch] or FIXED[ch]) and ch or "."
  end
  -- Every source pixel becomes a 2 x 2 block (8 -> 16): the art exactly as drawn, with square pixels. (The
  -- earlier 1.5x resample made every other pixel a different width, which squashed circles and blurred the
  -- shapes; smoothing the corners instead (Scale2x) turned thin rings into diamonds.)
  local big = {}
  for dy = 1, N do
    big[dy] = {}
    for dx = 1, N do
      local ch = src(math.ceil(dx / 2), math.ceil(dy / 2))
      big[dy][dx] = ch ~= "." and (palette[ch] or FIXED[ch]) or false
    end
  end
  local function at(x, y)
    return big[y] and big[y][x] or false
  end
  local size = N + 2 * PAD
  -- The shadow: the shape one pixel down and right, blurred over 3 x 3, faint
  local shadow = love.image.newImageData(size, size)
  local data = love.image.newImageData(size, size)
  for y = 0, size - 1 do
    for x = 0, size - 1 do
      local sum = 0
      for oy = -1, 1 do
        for ox = -1, 1 do
          if at(x - PAD + ox, y - PAD + oy) then
            sum = sum + 1
          end
        end
      end
      if sum > 0 then
        shadow:setPixel(x, y, DROP[1], DROP[2], DROP[3], DROP_ALPHA * sum / 9)
      end
    end
  end
  local bx0, by0, bx1, by1 = N, N, 1, 1
  for y = 1, N do
    for x = 1, N do
      local c = big[y][x]
      if c then
        bx0, by0, bx1, by1 = math.min(bx0, x), math.min(by0, y), math.max(bx1, x), math.max(by1, y)
        if not at(x, y - 1) and at(x, y + 1) then c = mix(c, WHITE, 0.22) end
        if not at(x, y + 1) and at(x, y - 1) then c = mix(c, SHADOW, 0.28) end
        data:setPixel(x - 1 + PAD, y - 1 + PAD, c[1], c[2], c[3], 1)
      end
    end
  end
  local img = love.graphics.newImage(data)
  img:setFilter("nearest", "nearest")
  -- (the shadow is scaled smoothly, so it falls off softly however large the icon is drawn)
  local sh = love.graphics.newImage(shadow)
  sh:setFilter("linear", "linear")
  hdShadow[img] = sh
  -- (in image pixels: the art's left, top, right and bottom edges)
  hdBox[img] = { PAD + bx0 - 1, PAD + by0 - 1, PAD + bx1, PAD + by1 }
  hdCache[key] = img
  return img
end

-- Draws an image from getHD (art and shadow) with its top left at (x, y), scaled s;
-- other images are drawn plain
function icons.drawHD(img, x, y, s, alpha)
  local sh = hdShadow[img]
  if sh then
    love.graphics.setColor(1, 1, 1, alpha or 1)
    love.graphics.draw(sh, x, y, 0, s, s)
  end
  love.graphics.setColor(1, 1, 1, alpha or 1)
  love.graphics.draw(img, x, y, 0, s, s)
end

-- The same, with the middle of what is drawn (not of the 16 x 16 square it is drawn in)
-- on (cx, cy), at whole pixels; tint (optional) = { r, g, b } multiplies the art
function icons.drawHDAt(img, cx, cy, s, alpha, tint)
  local box = hdBox[img]
  local ax, ay = (img:getWidth()) / 2, (img:getHeight()) / 2
  if box then
    ax, ay = (box[1] + box[3]) / 2, (box[2] + box[4]) / 2
  end
  local x, y = math.floor(cx - ax * s + 0.5), math.floor(cy - ay * s + 0.5)
  local sh = hdShadow[img]
  if sh then
    love.graphics.setColor(1, 1, 1, alpha or 1)
    love.graphics.draw(sh, x, y, 0, s, s)
  end
  local t = tint or { 1, 1, 1 }
  love.graphics.setColor(t[1], t[2], t[3], alpha or 1)
  love.graphics.draw(img, x, y, 0, s, s)
end

-- A levelled item's tier as a roman numeral (src.items), in light teal along the
-- bottom of a box of `size` at (x, y), centred. (The small square pip in the top
-- corner is something else: it means the item could be fused.)
local NUMERAL = {
  I = { "###", ".#.", ".#.", ".#.", "###" },
  V = { "#.#", "#.#", "#.#", "#.#", ".#." },
  X = { "#.#", "#.#", ".#.", "#.#", "#.#" },
}
local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }
function icons.drawLevel(level, x, y, size, alpha)
  alpha = alpha or 1
  local text = ROMAN[level]
  if not text then
    return
  end
  local c = math.max(1, math.floor(size / 20)) -- one numeral pixel
  local w = (#text * 3 + (#text - 1)) * c
  local shadow = math.max(1, math.floor(c / 2))
  local x0 = math.floor(x + (size - w) / 2)
  local y0 = math.floor(y + size - 5 * c - c * 2.5)
  for pass = 1, 2 do
    if pass == 1 then
      love.graphics.setColor(0.02, 0.06, 0.06, 0.9 * alpha)
    else
      love.graphics.setColor(0.62, 1.0, 0.92, alpha)
    end
    for i = 1, #text do
      local px = x0 + (i - 1) * 4 * c
      local rows = NUMERAL[text:sub(i, i)]
      for ry = 1, 5 do
        local row = rows[ry]
        for rx = 1, 3 do
          if row:sub(rx, rx) == "#" then
            local o = pass == 1 and shadow or 0
            love.graphics.rectangle("fill", px + (rx - 1) * c + o, y0 + (ry - 1) * c + o, c, c)
          end
        end
      end
    end
  end
  love.graphics.setColor(1, 1, 1, alpha)
end

-- For tests: every id that has an icon grid
function icons.ids()
  return ITEMS, PERKS
end

return icons
