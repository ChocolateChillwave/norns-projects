-- library.lua
-- the built-in beats, and the default lane layout they assume.
--
-- ORGANISED AS KITS. pattern slot N means the same beat on every lane:
-- row 1 is the amen break across all eight lanes, row 2 is a straight
-- four-four, and so on. that matters because the thing a drum pattern
-- actually is -- an amen break, an electro groove -- lives *across* voices,
-- not in one of them. eight independent per-voice banks can only produce
-- divisions of the bar, which is exactly how the first version sounded.
--
-- three ways to play it follow from that, all from the same data:
--   launch a whole row (a scene)  -> the real, interlocking beat
--   launch one cell               -> borrow that lane's part from another
--                                    kit, over whatever else is playing
--   let follow actions run        -> individual lanes drift between kits,
--                                    which is the generative behaviour, but
--                                    now every destination is a musically
--                                    coherent part rather than a bar count
--
-- patterns are written as one character per step:
--   X  accent   x  normal   o  ghost   -  rest
-- one string per voice, in the order that lane lists its voices (so CLAP's
-- first string is CP and its second RS). a kit that doesn't name a lane
-- leaves it empty and silent -- that is deliberate, not an omission: the
-- amen has no cowbell.
--
-- ACCURACY. the break transcriptions here are written from memory of how
-- these patterns are usually notated, at 16th resolution. they are meant to
-- be recognisable and to feel right, not to be exact transfers of a
-- recording -- the amen in particular is a 4-bar loop with a lot of
-- micro-timing that a 16th grid cannot hold at all. treat them as a
-- starting point to edit by ear on the device.
--
-- pure Lua, no norns APIs -- testable off-device.
local Library = {}

-- follow spec: {time in 16ths (or -1 for "end"), action A, action B,
-- chance of A}. action numbers index Pattern.ACTIONS:
-- 1 none, 2 next, 3 prev, 4 first, 5 last, 6 any, 7 other, 8 rand2.
local HOLD = {-1, 1, 1, 100}       -- at the end of the pattern, stay
local CYCLE = {-1, 2, 1, 100}      -- at the end, step to the next
local DRIFT_1BAR = {16, 7, 1, 40}  -- every bar, 40% chance of jumping kit
local DRIFT_2BAR = {32, 7, 1, 50}  -- every two bars, 50% chance

-- lane -> Rytm voices. left as it was 2026-09-20 rather than resplit; the
-- four toms share lane 4, so they get one pattern bank and one follow
-- action between them. they are still four separate voices on the wire
-- (notes 4/5/6/7) -- see NOTES.md, "lane layout".
Library.LANES = {
  {name = "KICK",  voices = {1},           follow = HOLD},
  {name = "SNARE", voices = {2},           follow = HOLD},
  {name = "CLAP",  voices = {4, 3},        follow = HOLD},       -- CP, RS
  {name = "TOMS",  voices = {5, 6, 7, 8},  follow = CYCLE},      -- BT LT MT HT
  {name = "CHH",   voices = {9},           follow = DRIFT_1BAR},
  {name = "OHH",   voices = {10},          follow = DRIFT_2BAR},
  {name = "CYM",   voices = {11},          follow = HOLD},
  {name = "COW",   voices = {12},          follow = HOLD},
}

-- two-bar kits are written as two 16-character halves joined, so the bar
-- line stays visible in the source
local function bars(a, b) return a .. b end

Library.KITS = {

  -- 1 ------------------------------------------------------------ amen
  -- the break. two bars, because the whole character is that bar two does
  -- not repeat bar one -- the snare shifts off the backbeat and the kick
  -- moves late. on a single bar it is just a funk beat.
  {name = "amen", length = 32, parts = {
    KICK  = {bars("X---------x-----", "X-----------x---")},
    SNARE = {bars("----X--o----X---", "----X-----X--X--")},
    CLAP  = {bars("----------------", "----------------"),      -- CP
             bars("--o-------o-----", "--o---o---------")},     -- RS ticks
    TOMS  = {bars("----------------", "----------------"),      -- BT
             bars("----------------", "----------------"),      -- LT
             bars("----------------", "---------x------"),      -- MT
             bars("----------------", "----------------")},     -- HT
    CHH   = {bars("x-x-x-x-x-x-x-x-", "x-x-x-x-x-x-x-x-")},
    OHH   = {bars("--------------x-", "------x---------")},
    CYM   = {bars("X---------------", "----------------")},
  }},

  -- 2 ------------------------------------------------------- four four
  -- straight techno. no snare at all -- the backbeat is the clap, which is
  -- what makes it read as techno rather than as rock.
  {name = "four four", length = 16, parts = {
    KICK = {"X---X---X---X---"},
    CLAP = {"----X-------X---",
            "----------------"},
    CHH  = {"x-x-x-x-x-x-x-x-"},
    OHH  = {"--x---x---x---x-"},
  }},

  -- 3 ----------------------------------------------------------- think
  -- the other break everyone samples. busier kick than the amen, ghost
  -- snares on the back half of each beat.
  {name = "think", length = 16, parts = {
    KICK  = {"X-----x---x-----"},
    SNARE = {"----X--o----X--o"},
    CLAP  = {"----------------",
             "--o---o---o---o-"},
    CHH   = {"x-x-x-x-x-x-x-x-"},
    OHH   = {"------------x---"},
    CYM   = {"x-------x-------"},
  }},

  -- 4 --------------------------------------------------------- electro
  -- 808 syncopation: the kick carries the groove rather than marking time,
  -- and the cowbell is doing real work.
  {name = "electro", length = 16, parts = {
    KICK  = {"X--X--x---X--x--"},
    SNARE = {"----X-------X---"},
    CLAP  = {"------------X---",
             "--x---x---x---x-"},
    TOMS  = {"--------x-------",
             "-------------x--",
             "----------------",
             "----------------"},
    CHH   = {"xoxoxoxoxoxoxoxo"},
    COW   = {"x-----x-----x---"},
  }},

  -- 5 --------------------------------------------------------- rolling
  -- driving techno. the hat does the work: 16ths with every third one
  -- ghosted so it pushes instead of sitting flat.
  {name = "rolling", length = 16, parts = {
    KICK = {"X---X---X---X---"},
    CLAP = {"----X-------X---",
            "----------------"},
    CHH  = {"xxoxxoxxoxxoxxox"},
    OHH  = {"--x---x---x---X-"},
    CYM  = {"x-------x-------"},
  }},

  -- 6 ----------------------------------------------------------- funky
  -- ghost notes are the entire point of this one. play it with the snare's
  -- level up and you can hear how much of the groove is below the accents.
  {name = "funky", length = 16, parts = {
    KICK  = {"X--x-----X-x----"},
    SNARE = {"----Xo-o-o-oX-o-"},
    CLAP  = {"----------------",
             "o---o---o---o---"},
    CHH   = {"x-x-x-x-x-x-x-x-"},
    OHH   = {"--------x-------"},
    CYM   = {"x---x---x---x---"},
  }},

  -- 7 -------------------------------------------------------- halftime
  -- two bars of space, with the toms doing a descending fill at the end of
  -- the second. the one kit here that leans on the TOMS lane.
  {name = "halftime", length = 32, parts = {
    KICK  = {bars("X---------------", "------X---------")},
    SNARE = {bars("------------X---", "------------X---")},
    TOMS  = {bars("----------------", "----------------"),   -- BT
             bars("----------------", "--------------x-"),   -- LT
             bars("----------------", "-------------x--"),   -- MT
             bars("----------------", "------------x---")},  -- HT
    CHH   = {bars("x---x---x---x---", "x---x---x---x---")},
    OHH   = {bars("----------------", "--------------x-")},
    CYM   = {bars("X---------------", "----------------")},
  }},

  -- 8 -------------------------------------------------------- hypnotic
  -- minimal. almost nothing in it, which makes it the useful one to drift
  -- *into* -- a lane landing here drops out of the way.
  {name = "hypnotic", length = 16, parts = {
    KICK = {"X---X---X---X---"},
    CLAP = {"----------------",
            "--x---x---x---x-"},
    TOMS = {"------------x---",
            "----------------",
            "----------------",
            "----------------"},
    CHH  = {"--x---x---x---x-"},
    COW  = {"------x---------"},
  }},
}

-- fill a lane's bank: one pattern per kit, in kit order, so bank slot N is
-- kit N on every lane.
function Library.populate(lane, spec, Pattern)
  local f = spec.follow or HOLD
  for k = 1, #Library.KITS do
    local kit = Library.KITS[k]
    local rows = kit.parts[spec.name]

    -- a kit may name fewer rows than the lane has voices (halftime writes
    -- all four toms, but a kit that only wanted one would not) -- pad, so
    -- from_rows still produces a pattern with a row per voice for the step
    -- editor to draw
    local full = {}
    for s = 1, lane.slots do
      full[s] = (rows and rows[s]) or ""
    end

    local p = Pattern.from_rows(full, kit.name, kit.length)

    if Pattern.is_empty(p) then
      -- an empty slot means "this voice sits this kit out". it has to stay
      -- put: with skip_empty on, a relative follow action from a pattern
      -- that isn't in its own candidate list would jump the lane straight
      -- back in, and the silence you asked for would last one bar.
      p.follow.time = -1
      p.follow.a = 1
      p.follow.b = 1
      p.follow.chance = 100
    else
      p.follow.time = f[1]
      p.follow.a = f[2]
      p.follow.b = f[3]
      p.follow.chance = f[4]
    end

    lane.bank[k] = p
  end
end

-- kit names, for the scene row and the screen
function Library.kit_names()
  local out = {}
  for i = 1, #Library.KITS do out[i] = Library.KITS[i].name end
  return out
end

return Library
