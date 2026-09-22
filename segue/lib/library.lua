-- library.lua
-- the built-in beats, grouped into banks, and the lane layout they assume.
--
-- BANKS. eight of them, each holding eight kits:
--   generic  house  techno  electro  breakbeats  variety  variety 2  user
-- a kit is one beat written across the lanes; bank slot N is the same kit
-- on every lane, so the launch grid's rows are kits.
--
-- THE RULE THAT SHAPES EVERY BANK: its kits have to work together. follow
-- actions drift individual lanes between the kits of whatever bank is
-- loaded, so a hat lane landing in kit 5 while the kick is still on kit 2
-- has to sound like a choice, not an accident. that is why house is eight
-- variations on four-to-the-floor rather than house next to electro next
-- to a breakbeat: the first version of this library mixed genres in one
-- bank and the drift produced clashes. inside a genre bank the kick
-- patterns stay broadly compatible, and the variety banks are picked for
-- the same reason -- `variety` leans four-to-the-floor, `variety 2` leans
-- broken -- so each still hangs together as a set.
--
-- characters, one per step:  X accent   x normal   o ghost   - rest
-- one string per voice, in the order the lane lists its voices (so CLAP's
-- first string is CP and its second is RS). a kit that names no part for a
-- lane leaves it empty on purpose -- that voice sits the kit out.
--
-- ACCURACY. the named breaks (amen, think, apache, impeach) are written
-- from memory of how they are usually notated, at 16th resolution. they
-- are meant to be recognisable and to feel right, not to be transcriptions
-- of a recording; the amen's micro-timing in particular will not fit a
-- 16th grid at all. edit them by ear.
--
-- pure Lua, no norns APIs -- testable off-device.
local Library = {}

-- lane -> Rytm voices, and each lane's own FOLLOW OVERRIDES. these are the
-- lane level of the inheritance chain (see lane.lua), used as the defaults
-- for the lane follow params. everything not listed inherits the global,
-- which ships as "at the end of the pattern, stay put" -- so the kick,
-- snare and friends hold, and only the lanes where movement is musical
-- override it. that is the shipped behaviour expressed as three overrides
-- instead of 64 copied settings.
--
-- follow_time is an index into Pattern.FOLLOW_TIMES (9 = 1 bar, 11 = 2
-- bar); follow_a is an index into Pattern.ACTIONS (2 = next, 7 = other).
Library.LANES = {
  {name = "KICK",  voices = {1}},
  {name = "SNARE", voices = {2}},
  {name = "CLAP",  voices = {4, 3}},                    -- CP, RS
  {name = "TOMS",  voices = {5, 6, 7, 8},               -- BT LT MT HT
   follow = {follow_a = 2}},                             -- step to the next fill
  {name = "CHH",   voices = {9},
   follow = {follow_time = 9, follow_a = 7, follow_chance = 40}},
  {name = "OHH",   voices = {10},
   follow = {follow_time = 11, follow_a = 7, follow_chance = 50}},
  {name = "CYM",   voices = {11}},
  {name = "COW",   voices = {12}},
}

local function bars(a, b) return a .. b end
local function K(name, length, parts) return {name = name, length = length, parts = parts} end

-- the four toms, low to high. most kits only want one or two of them.
local function toms(bt, lt, mt, ht)
  local e = "----------------"
  return {bt or e, lt or e, mt or e, ht or e}
end

---------------------------------------------------------------- generic
-- genre-neutral building blocks: straight 4/4, the vocabulary every other
-- bank is a dialect of. the easiest bank to drift within.
local GENERIC = {
  K("basic", 16, {
    KICK  = {"X-------X-------"},
    SNARE = {"----X-------X---"},
    CHH   = {"x-x-x-x-x-x-x-x-"},
  }),
  K("backbeat", 16, {
    KICK  = {"X-------X-x-----"},
    SNARE = {"----X-------X---"},
    CHH   = {"x-x-x-x-x-x-x-x-"},
    OHH   = {"--------------x-"},
  }),
  K("drive", 16, {
    KICK  = {"X-----x-X-------"},
    SNARE = {"----X-------X---"},
    CHH   = {"X-x-X-x-X-x-X-x-"},
    OHH   = {"------x-------x-"},
  }),
  K("half", 16, {
    KICK  = {"X---------x-----"},
    SNARE = {"--------X-------"},
    CHH   = {"x-x-x-x-x-x-x-x-"},
  }),
  K("threes", 16, {
    KICK  = {"X-----x-X-----x-"},
    SNARE = {"----X-------X---"},
    CHH   = {"x--x--x--x--x--x"},
  }),
  K("sparse", 16, {
    KICK  = {"X---------------"},
    SNARE = {"------------X---"},
    CHH   = {"x---x---x---x---"},
  }),
  K("busy", 16, {
    KICK  = {"X--x--x-X--x----"},
    SNARE = {"----X--o----X-o-"},
    CHH   = {"xoxoxoxoxoxoxoxo"},
    OHH   = {"--------------x-"},
  }),
  K("fill", 16, {
    KICK  = {"X-------X-------"},
    SNARE = {"----X-------oxox"},
    TOMS  = toms("--------------xX", "------------xx--",
                 "----------xx----", "--------xx------"),
    CHH   = {"x-x-x-x---------"},
    CYM   = {"X---------------"},
  }),
}

---------------------------------------------------------------- house
-- eight takes on four-to-the-floor. the kick barely changes across the
-- bank (garage is the one skippy exception), so any lane from any kit sits
-- over any other.
local HOUSE = {
  K("classic", 16, {
    KICK = {"X---X---X---X---"},
    CLAP = {"----X-------X---", "----------------"},
    CHH  = {"o-o-o-o-o-o-o-o-"},
    OHH  = {"--x---x---x---x-"},
  }),
  K("deep", 16, {
    KICK = {"X---X---X---X---"},
    CLAP = {"----------------", "----x-------x---"},
    CHH  = {"--x---x---x---x-"},
    OHH  = {"------------x---"},
  }),
  K("garage", 16, {
    KICK = {"X-----x---X-----"},
    CLAP = {"----X-------X---", "--o-----o-o-----"},
    CHH  = {"x-xx-xx-x-xx-xx-"},
  }),
  K("disco", 16, {
    KICK  = {"X---X---X---X---"},
    SNARE = {"----X-------X---"},
    CHH   = {"xoxoxoxoxoxoxoxo"},
    OHH   = {"--X---X---X---X-"},
  }),
  K("tribal", 16, {
    KICK = {"X---X---X---X---"},
    CLAP = {"----X-------X---", "x--x--x---x--x--"},
    TOMS = toms(nil, "--x-------x-----", "------x-------x-", nil),
    CHH  = {"--x---x---x---x-"},
  }),
  K("jackin", 16, {
    KICK = {"X---X---X-x-X---"},
    CLAP = {"----X-------X---", "----------------"},
    CHH  = {"xxoxxxoxxxoxxxox"},
    OHH  = {"--x---x---x---x-"},
  }),
  K("minimal", 16, {
    KICK = {"X---X---X---X---"},
    CLAP = {"----------------", "----------x-----"},
    CHH  = {"----x-------x---"},
  }),
  K("chicago", 16, {
    KICK  = {"X---X---X---X---"},
    SNARE = {"----X-------X---"},
    CLAP  = {"----X-------X---", "----------------"},
    CHH   = {"--x---x---x---x-"},
    COW   = {"x-----x-----x---"},
  }),
}

---------------------------------------------------------------- techno
-- four-to-the-floor again, but harder and more hypnotic: the top end
-- carries the movement, the kick is a pulse to hang it off.
local TECHNO = {
  K("four four", 16, {
    KICK = {"X---X---X---X---"},
    CLAP = {"----X-------X---", "----------------"},
    CHH  = {"x-x-x-x-x-x-x-x-"},
    OHH  = {"--x---x---x---x-"},
  }),
  K("rolling", 16, {
    KICK = {"X---X---X---X---"},
    CLAP = {"----X-------X---", "----------------"},
    CHH  = {"xxoxxoxxoxxoxxox"},
    OHH  = {"--x---x---x---X-"},
    CYM  = {"x-------x-------"},
  }),
  K("hypnotic", 16, {
    KICK = {"X---X---X---X---"},
    CLAP = {"----------------", "--x---x---x---x-"},
    TOMS = toms("------------x---", nil, nil, nil),
    CHH  = {"--x---x---x---x-"},
    COW  = {"------x---------"},
  }),
  K("driving", 16, {
    KICK = {"X---X---X---X---"},
    CLAP = {"----------------", "-x-x-x-x-x-x-x-x"},
    CHH  = {"x-x-x-x-x-x-x-x-"},
    OHH  = {"--x---x---x---x-"},
  }),
  K("industrial", 16, {
    KICK  = {"X---X---X--XX---"},
    SNARE = {"----X-------X---"},
    CHH   = {"x-x-x-x-x-x-x-x-"},
    CYM   = {"X-------x-------"},
  }),
  K("peak", 16, {
    KICK = {"X---X---X---X---"},
    CLAP = {"----X-------X---", "----------------"},
    CHH  = {"XxxxXxxxXxxxXxxx"},
    OHH  = {"--x---x---x---x-"},
    CYM  = {"X---------------"},
  }),
  K("broken", 16, {
    KICK = {"X--x--x---X-x---"},
    CLAP = {"----X-------X---", "----------------"},
    CHH  = {"--x-x---x-x---x-"},
    OHH  = {"------x-------x-"},
  }),
  K("dub", 16, {
    KICK = {"X-------X-------"},
    CLAP = {"----------------", "----x-------x---"},
    CHH  = {"--x-------x-----"},
    OHH  = {"------x-------x-"},
  }),
}

---------------------------------------------------------------- electro
-- 808 syncopation: the kick carries the groove rather than marking time,
-- and the cowbell and toms do real work. every kick here is off the grid,
-- so they interlock with each other rather than with house.
local ELECTRO = {
  K("electro", 16, {
    KICK  = {"X--X--x---X--x--"},
    SNARE = {"----X-------X---"},
    CLAP  = {"------------X---", "--x---x---x---x-"},
    TOMS  = toms("--------x-------", "-------------x--", nil, nil),
    CHH   = {"xoxoxoxoxoxoxoxo"},
    COW   = {"x-----x-----x---"},
  }),
  K("planet", 16, {
    KICK = {"X--X--X---X-----"},
    CLAP = {"----X-------X---", "----------------"},
    CHH  = {"x-x-x-x-x-x-x-x-"},
    COW  = {"x-x---x-x-x---x-"},
  }),
  K("808", 16, {
    KICK = {"X-------X-x-----"},
    CLAP = {"----X-------X---", "----------------"},
    TOMS = toms("--------x-------", "----------x-----",
                "------------x---", "--------------x-"),
    CHH  = {"x---x---x---x---"},
  }),
  K("miami", 16, {
    KICK  = {"X--X----X--X----"},
    SNARE = {"----X-------X---"},
    CHH   = {"xoxoxoxoxoxoxoxo"},
    OHH   = {"--------------x-"},
  }),
  K("breakdance", 16, {
    KICK = {"X--X--x-X--X--x-"},
    CLAP = {"----X--x----X---", "--x-------x-----"},
    CHH  = {"xoxxxoxxxoxxxoxx"},
    COW  = {"------x-------x-"},
  }),
  K("cowbell", 16, {
    KICK = {"X--X--x---X--x--"},
    CLAP = {"----X-------X---", "----------------"},
    CHH  = {"--x---x---x---x-"},
    COW  = {"x-xx-x-xx-xx-x-x"},
  }),
  K("detroit", 16, {
    KICK = {"X---X---X---X---"},
    CLAP = {"----X-------X---", "--x---x---x---x-"},
    CHH  = {"xoxoxoxoxoxoxoxo"},
    TOMS = toms("--------------x-", nil, nil, nil),
  }),
  K("sparse", 16, {
    KICK = {"X-----x---------"},
    CLAP = {"------------X---", "----------------"},
    CHH  = {"----x-------x---"},
    COW  = {"--------x-------"},
  }),
}

---------------------------------------------------------------- breakbeats
-- the sampled-break family. kick and snare converse rather than keep time,
-- and the ghost notes are most of the groove. the two-bar kits (amen,
-- halftime, jungle) exist because their whole character is bar two not
-- repeating bar one -- and they are also what makes lanes phase against
-- each other, since a 32-step lane loops half as often as a 16-step one.
local BREAKBEATS = {
  K("amen", 32, {
    KICK  = {bars("X---------x-----", "X-----------x---")},
    SNARE = {bars("----X--o----X---", "----X-----X--X--")},
    CLAP  = {bars("----------------", "----------------"),
             bars("--o-------o-----", "--o---o---------")},
    TOMS  = {bars("----------------", "----------------"),
             bars("----------------", "----------------"),
             bars("----------------", "---------x------"),
             bars("----------------", "----------------")},
    CHH   = {bars("x-x-x-x-x-x-x-x-", "x-x-x-x-x-x-x-x-")},
    OHH   = {bars("--------------x-", "------x---------")},
    CYM   = {bars("X---------------", "----------------")},
  }),
  K("think", 16, {
    KICK  = {"X-----x---x-----"},
    SNARE = {"----X--o----X--o"},
    CLAP  = {"----------------", "--o---o---o---o-"},
    CHH   = {"x-x-x-x-x-x-x-x-"},
    OHH   = {"------------x---"},
    CYM   = {"x-------x-------"},
  }),
  K("funky", 16, {
    KICK  = {"X--x-----X-x----"},
    SNARE = {"----Xo-o-o-oX-o-"},
    CLAP  = {"----------------", "o---o---o---o---"},
    CHH   = {"x-x-x-x-x-x-x-x-"},
    OHH   = {"--------x-------"},
    CYM   = {"x---x---x---x---"},
  }),
  K("halftime", 32, {
    KICK  = {bars("X---------------", "------X---------")},
    SNARE = {bars("------------X---", "------------X---")},
    TOMS  = {bars("----------------", "----------------"),
             bars("----------------", "--------------x-"),
             bars("----------------", "-------------x--"),
             bars("----------------", "------------x---")},
    CHH   = {bars("x---x---x---x---", "x---x---x---x---")},
    OHH   = {bars("----------------", "--------------x-")},
    CYM   = {bars("X---------------", "----------------")},
  }),
  K("apache", 16, {
    KICK  = {"X-----x---X-----"},
    SNARE = {"----X-------X---"},
    TOMS  = toms(nil, "x-x---x-x-x---x-", "---x-------x----", nil),
    CHH   = {"x-x-x-x-x-x-x-x-"},
  }),
  K("impeach", 16, {
    KICK  = {"X-------X-X-----"},
    SNARE = {"----X-------X---"},
    CHH   = {"x-x-x-x-x-x-x-x-"},
    OHH   = {"------x---------"},
  }),
  K("jungle", 32, {
    KICK  = {bars("X---------X-----", "--X-------X-----")},
    SNARE = {bars("----X--o-X--X--o", "----X--o-X-oX---")},
    CHH   = {bars("x-x-x-x-x-x-x-x-", "x-x-x-x-x-x-x-x-")},
    OHH   = {bars("--------------x-", "----------------")},
  }),
  K("skeleton", 16, {
    KICK  = {"X---------x-----"},
    SNARE = {"----X-------X---"},
    CHH   = {"x---x---x---x---"},
  }),
}

---------------------------------------------------------------- the banks
-- the two variety banks are *picks* from the genre banks, by bank name and
-- kit number, so a kit exists once in the source and cannot drift out of
-- step with its copy. `variety` leans four-to-the-floor and `variety 2`
-- leans broken, so each is still a set that drifts coherently -- which
-- kits genuinely work together is a judgment to check by ear.
Library.BANKS = {
  {name = "generic",    short = "GEN", kits = GENERIC},
  {name = "house",      short = "HSE", kits = HOUSE},
  {name = "techno",     short = "TEC", kits = TECHNO},
  {name = "electro",    short = "ELE", kits = ELECTRO},
  {name = "breakbeats", short = "BRK", kits = BREAKBEATS},
  {name = "variety", short = "VR1", picks = {
    {"house", 1}, {"techno", 2}, {"house", 4}, {"techno", 4},
    {"house", 2}, {"techno", 3}, {"electro", 7}, {"house", 8},
  }},
  {name = "variety 2", short = "VR2", picks = {
    {"breakbeats", 1}, {"breakbeats", 2}, {"electro", 1}, {"breakbeats", 3},
    {"electro", 2}, {"breakbeats", 5}, {"generic", 7}, {"breakbeats", 8},
  }},
  -- the one bank you own. it starts empty and fills from "copy to user"
  -- or the step editor; unlike the factory banks, edits to it are kept.
  {name = "user", short = "USR", user = true},
}

Library.USER = #Library.BANKS
Library.KITS_PER_BANK = 8

function Library.bank_names()
  local out = {}
  for i, b in ipairs(Library.BANKS) do out[i] = b.name end
  return out
end

local function bank_by_name(name)
  for _, b in ipairs(Library.BANKS) do
    if b.name == name then return b end
  end
  return nil
end

-- the eight kit tables for bank `b`, with picks resolved. nil for the user
-- bank, which has no factory data -- it is built from saved state instead.
function Library.kits(b)
  local bank = Library.BANKS[b]
  if bank == nil or bank.user then return nil end
  if bank.kits then return bank.kits end
  local out = {}
  for i, pick in ipairs(bank.picks) do
    local src = bank_by_name(pick[1])
    out[i] = src and src.kits and src.kits[pick[2]]
  end
  return out
end

-- one lane's eight patterns from bank `b`: a fresh copy every call, which
-- is what keeps the factory banks read-only -- editing what a lane holds
-- can never reach back into this file's tables.
function Library.column(b, spec, slots, Pattern)
  local column = {}
  local kits = Library.kits(b)
  for k = 1, Library.KITS_PER_BANK do
    local kit = kits and kits[k]
    local p
    if kit then
      local rows = kit.parts[spec.name]
      -- a kit may name fewer rows than the lane has voices -- pad, so the
      -- step editor still gets a row per voice to draw
      local full = {}
      for s = 1, slots do full[s] = (rows and rows[s]) or "" end
      p = Pattern.from_rows(full, kit.name, kit.length)
    else
      p = Pattern.new(slots, 16, "--")
    end
    -- an empty slot means "this voice sits the kit out", and it has to
    -- stay put: with skip_empty on, the active pattern is not in its own
    -- candidate list, so an inherited "next" or "other" would resolve to
    -- the first non-empty kit and drag the lane back in after one bar.
    if Pattern.is_empty(p) then p.ov.follow_a = Pattern.ACTION_NONE end
    column[k] = p
  end
  return column
end

-- the kit names for a bank, for the screen. the user bank's names come
-- from its saved patterns, so this is only the factory half.
function Library.kit_names(b)
  local out = {}
  local kits = Library.kits(b)
  for k = 1, Library.KITS_PER_BANK do
    out[k] = (kits and kits[k] and kits[k].name) or "--"
  end
  return out
end

return Library
