-- library.lua
-- the built-in beats, and the default lane layout they assume.
--
-- patterns are written as one character per step:
--   X  accent   x  normal   o  ghost   -  rest
-- one string per slot, and a lane's slots are its voices in order (so the
-- CLAP lane's first string is CP and its second is RS). every string here
-- is 16 characters; the length check in the test harness will catch it if
-- one drifts.
--
-- FOLLOW DEFAULTS are part of the curation, not an afterthought. the
-- rhythm-section lanes (kick, snare, clap, cymbal, cowbell) ship with
-- "end / none", i.e. Ableton's default of staying put until you launch
-- something -- they are the anchor, and a kick that wanders on its own is
-- just noise. the movement is given to the lanes where it is musical: toms
-- step to the next fill every time round, and the two hat lanes take an
-- "other" jump some of the time and otherwise hold. so the script does
-- something generative the moment it starts without the floor moving under
-- you, and every bit of that is editable per pattern.
--
-- a bank slot left empty is deliberate: with a lane's skip_empty set (the
-- default) follow actions step straight over it, so it is a free slot to
-- write your own pattern into without having to first disarm anything.
--
-- pure Lua, no norns APIs -- testable off-device.
local Library = {}

-- shorthand for the follow spec: {time in 16ths (or -1 for "end"),
-- action A, action B, chance of A}. action numbers index Pattern.ACTIONS:
-- 1 none, 2 next, 3 prev, 4 first, 5 last, 6 any, 7 other, 8 rand2.
local HOLD = {-1, 1, 1, 100}       -- at the end of the pattern, stay
local CYCLE = {-1, 2, 1, 100}      -- at the end, step to the next
local DRIFT_1BAR = {16, 7, 1, 40}  -- every bar, 40% chance of jumping
local DRIFT_2BAR = {32, 7, 1, 50}  -- every two bars, 50% chance

Library.LANES = {

  {name = "KICK", voices = {1}, follow = HOLD, patterns = {
    {"pulse",   {"X-------X-------"}},
    {"four",    {"X---x---X---x---"}},
    {"four+e",  {"X---x---X---x--x"}},
    {"house",   {"X---X---X---X---"}},
    {"electro", {"X-----x-X---x---"}},
    {"broken",  {"X--x---X--x-X---"}},
    {"jungle",  {"X-----X---X-----"}},
    {"double",  {"X--X----X--X--x-"}},
  }},

  {name = "SNARE", voices = {2}, follow = HOLD, patterns = {
    {"backbeat", {"----X-------X---"}},
    {"ghosted",  {"----X--o----X--o"}},
    {"push",     {"----X-------X-x-"}},
    {"halftime", {"------------X---"}},
    {"breaks",   {"----X--o--X-X---"}},
    {"rolling",  {"----X-o-o---X-o-"}},
    {"3-3-2",    {"------X-----X---"}},
    {"fill",     {"----X-o-X-o-XoXo"}},
  }},

  -- slot 1 = CP (clap), slot 2 = RS (rimshot)
  {name = "CLAP", voices = {4, 3}, follow = HOLD, patterns = {
    {"clap",     {"----X-------X---",
                  "----------------"}},
    {"clap+rim", {"----X-------X---",
                  "--x---x---x---x-"}},
    {"rim 16",   {"----------------",
                  "--x-x-x-x-x-x-x-"}},
    {"off rim",  {"------------X---",
                  "---x---x---x---x"}},
    {"sparse",   {"------------X---",
                  "-------x--------"}},
    {"latin",    {"-----x------x---",
                  "x--x--x---x--x--"}},
    {"clave",    {"----------------",
                  "x--x--x---x-x---"}},
    {"busy",     {"----X---X---X---",
                  "-x-x-x-x-x-x-x-x"}},
  }},

  -- slot 1 = BT, 2 = LT, 3 = MT, 4 = HT. the fill lane -- it cycles.
  {name = "TOMS", voices = {5, 6, 7, 8}, follow = CYCLE, patterns = {
    {"tap",     {"----------------",
                 "----------------",
                 "----------------",
                 "-------------x--"}},
    {"descend", {"---------------X",
                 "--------------x-",
                 "-------------x--",
                 "------------x---"}},
    {"ascend",  {"------------X---",
                 "-------------x--",
                 "--------------x-",
                 "---------------x"}},
    {"tribal",  {"X-------X-------",
                 "----x-------x---",
                 "--x---x---x---x-",
                 "----------------"}},
    {"offbeat", {"----------------",
                 "---x---x---x---x",
                 "----------------",
                 "----------------"}},
    {"march",   {"X---X---X---X---",
                 "--x---x---x---x-",
                 "----------------",
                 "----------------"}},
    {"fill 8",  {"--------X-------",
                 "---------x-x----",
                 "----------x-x-x-",
                 "-------------x-x"}},
    {"sparse",  {"----------------",
                 "----------------",
                 "-------x--------",
                 "----------------"}},
  }},

  {name = "CHH", voices = {9}, follow = DRIFT_1BAR, patterns = {
    {"8ths",    {"x-x-x-x-x-x-x-x-"}},
    {"16ths",   {"xoxoxoxoxoxoxoxo"}},
    {"offbeat", {"--x---x---x---x-"}},
    {"3-group", {"x--x--x--x--x--x"}},
    {"sparse",  {"x---x---x---x---"}},
    {"accents", {"XoxoXoxoXoxoXoxo"}},
    {"broken",  {"x-xox-x-xoxox-x-"}},
    {"rolling", {"xxoxxoxxoxxoxxox"}},
  }},

  {name = "OHH", voices = {10}, follow = DRIFT_2BAR, patterns = {
    {"offbeat", {"--x---x---x---x-"}},
    {"and 2",   {"--------x-------"}},
    {"last",    {"--------------x-"}},
    {"halves",  {"----x-------x---"}},
    {"pumping", {"--x---x---x---X-"}},
    {"pair",    {"--x-x-------x---"}},
    {"long",    {"------------X---"}},
    {"driving", {"--X---x---X---x-"}},
  }},

  {name = "CYM", voices = {11}, follow = HOLD, patterns = {
    {"crash",    {"X---------------"}},
    {"ride 8",   {"x-x-x-x-x-x-x-x-"}},
    {"ride off", {"--x---x---x---x-"}},
    {"accent",   {"X-------x-------"}},
    {"swell",    {"o-o-o-o-x-x-X-X-"}},
    {"late",     {"------------X---"}},
    {"ride 16",  {"xoxoxoxoxoxoxoxo"}},
    -- slot 8 intentionally empty: a silent slot to launch when you want the
    -- cymbal out, and one that follow actions skip over on their own
  }},

  {name = "COW", voices = {12}, follow = HOLD, patterns = {
    {"clave",  {"x--x--x---x-x---"}},
    {"4ths",   {"x---x---x---x---"}},
    {"offs",   {"--x---x---x---x-"}},
    {"3-3-2",  {"x-----x-----x---"}},
    {"busy",   {"x-x---x-x-x---x-"}},
    {"accent", {"X-------X-------"}},
    {"roll",   {"xoxoxo----------"}},
    -- slot 8 intentionally empty, as above
  }},
}

-- fill a lane's bank from its library entry. patterns the library does not
-- define are left as the empty ones the lane was constructed with.
function Library.populate(lane, spec, Pattern)
  local f = spec.follow or HOLD
  for i = 1, #spec.patterns do
    local entry = spec.patterns[i]
    local p = Pattern.from_rows(entry[2], entry[1], 16)
    p.follow.time = f[1]
    p.follow.a = f[2]
    p.follow.b = f[3]
    p.follow.chance = f[4]
    lane.bank[i] = p
  end
  -- empty slots still need the lane's slot count, so the step editor has
  -- rows to draw and a later edit writes into the right place
  for i = #spec.patterns + 1, #lane.bank do
    local p = Pattern.new(lane.slots, 16, "--")
    p.follow.time = f[1]
    p.follow.a = f[2]
    p.follow.b = f[3]
    p.follow.chance = f[4]
    lane.bank[i] = p
  end
end

return Library
