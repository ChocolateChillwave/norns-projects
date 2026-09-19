-- chords.lua
-- chord voicing banks, built by stacking SCALE DEGREES rather than fixed
-- semitone intervals. a degree stack is diatonic by construction -- there's
-- no "is this chord in key" test to run and no clamping to a nearest legal
-- chord type, because every note is pulled straight out of the scale.
--
-- degree offsets are relative to the chord's own root: 0 = root, 2 = third,
-- 4 = fifth, 6 = seventh, 8 = ninth, 10 = eleventh, 12 = thirteenth (odd
-- offsets land on the steps between, which is what makes quartal/spread
-- voicings possible). in a 7-note scale, offset 7 is the octave.
--
-- a bank is a "flavor": 4 voicings sharing a harmonic character, one per
-- grid row within an octave group, ordered most compact (row 1) to widest
-- (row 4). tweaking these tables is the intended way to change how the
-- instrument sounds -- nothing else depends on their contents.
local Chords = {}

-- used only when the scale is chromatic: degree-stacking over 12 equal
-- semitones gives clusters, so a chromatic root gets a major-shaped stack
-- built on it instead. keeps chromatic usable as the "any root" escape
-- hatch without it turning into a tone cluster machine.
local MAJOR_STEPS = {0, 2, 4, 5, 7, 9, 11}

-- ordered roughly from plain to colorful, so turning the bank ring moves
-- through related sounds rather than jumping around
Chords.BANKS = {
  {
    -- the only bank with plain three-note voicings. every other bank is 4-6
    -- notes so a strum always has something to spread across; triads are
    -- here because sometimes you just want the chord and nothing else.
    name = "triads",
    voicings = {
      {name = "close",   deg = {0, 2, 4}},
      {name = "open",    deg = {0, 4, 9}},
      {name = "octave",  deg = {0, 2, 4, 7}},
      {name = "wide",    deg = {0, 4, 9, 11}},
    },
  },
  {
    name = "add nine",
    voicings = {
      {name = "close",   deg = {0, 2, 4, 8}},
      {name = "open",    deg = {0, 4, 8, 9}},
      {name = "five",    deg = {0, 2, 4, 7, 8}},
      {name = "wide",    deg = {0, 4, 7, 8, 9, 11}},
    },
  },
  {
    name = "sixths",
    voicings = {
      {name = "close",   deg = {0, 2, 4, 5}},
      {name = "six-nine", deg = {0, 2, 5, 8}},
      {name = "open",    deg = {0, 4, 7, 9, 12}},
      {name = "wide",    deg = {0, 4, 8, 9, 12}},
    },
  },
  {
    name = "sevenths",
    voicings = {
      {name = "close",   deg = {0, 2, 4, 6}},
      {name = "open",    deg = {0, 4, 6, 9}},
      {name = "shell",   deg = {0, 2, 6, 9}},
      {name = "wide",    deg = {0, 4, 6, 9, 11}},
    },
  },
  {
    name = "ninths",
    voicings = {
      {name = "close",   deg = {0, 2, 4, 6, 8}},
      {name = "open",    deg = {0, 4, 6, 8, 11}},
      {name = "upper",   deg = {0, 6, 8, 11}},
      {name = "wide",    deg = {0, 4, 8, 10, 12}},
    },
  },
  {
    name = "elevenths",
    voicings = {
      {name = "close",   deg = {0, 2, 4, 6, 8, 10}},
      {name = "open",    deg = {0, 4, 6, 8, 10}},
      {name = "upper",   deg = {0, 6, 8, 10, 11}},
      {name = "wide",    deg = {0, 4, 8, 10, 13}},
    },
  },
  {
    name = "thirteenths",
    voicings = {
      {name = "close",   deg = {0, 2, 4, 6, 8, 12}},
      {name = "open",    deg = {0, 4, 6, 9, 12}},
      {name = "upper",   deg = {0, 6, 8, 12}},
      {name = "wide",    deg = {0, 4, 6, 8, 12, 14}},
    },
  },
  {
    name = "sus",
    voicings = {
      {name = "sus2",    deg = {0, 1, 4, 7}},
      {name = "sus4",    deg = {0, 3, 4, 7}},
      {name = "nine sus", deg = {0, 3, 4, 6, 8}},
      {name = "wide",    deg = {0, 4, 7, 8, 10}},
    },
  },
  {
    name = "quartal",
    voicings = {
      {name = "four",    deg = {0, 3, 6, 9}},
      {name = "five",    deg = {0, 3, 6, 9, 12}},
      {name = "octave",  deg = {0, 3, 7, 10}},
      {name = "wide",    deg = {0, 3, 6, 10, 12}},
    },
  },
  {
    name = "fifths",
    voicings = {
      {name = "power",   deg = {0, 4, 7, 11}},
      {name = "stacked", deg = {0, 4, 8, 12}},
      {name = "hollow",  deg = {0, 7, 11, 14}},
      {name = "wide",    deg = {0, 4, 7, 11, 14}},
    },
  },
  {
    name = "spread",
    voicings = {
      {name = "four",    deg = {0, 4, 7, 9}},
      {name = "five",    deg = {0, 4, 7, 9, 11}},
      {name = "upper",   deg = {0, 7, 9, 11, 12}},
      {name = "full",    deg = {0, 4, 6, 7, 9, 11}},
    },
  },
  {
    name = "octave bass",
    voicings = {
      {name = "four",    deg = {0, 7, 9, 11}},
      {name = "five",    deg = {0, 7, 9, 11, 13}},
      {name = "lift",    deg = {0, 7, 10, 12, 14}},
      {name = "full",    deg = {0, 4, 7, 9, 11, 13}},
    },
  },
  {
    name = "clusters",
    voicings = {
      {name = "seconds", deg = {0, 1, 2, 4}},
      {name = "spread",  deg = {0, 1, 4, 8}},
      {name = "shimmer", deg = {0, 4, 8, 9, 10}},
      {name = "wide",    deg = {0, 7, 8, 9, 11}},
    },
  },
}

-- highest degree offset any voicing uses -- how many scale steps of room a
-- chord needs above its root to come out complete
function Chords.max_degree()
  local top = 0
  for _, bank in ipairs(Chords.BANKS) do
    for _, v in ipairs(bank.voicings) do
      for _, d in ipairs(v.deg) do if d > top then top = d end end
    end
  end
  return top
end

function Chords.bank_names()
  local names = {}
  for _, b in ipairs(Chords.BANKS) do table.insert(names, b.name) end
  return names
end

function Chords.voicing(bank_idx, voicing_idx)
  local bank = Chords.BANKS[bank_idx] or Chords.BANKS[1]
  return bank.voicings[voicing_idx] or bank.voicings[1], bank
end

-- scale: flat ascending array of MIDI notes. root_index: 1-based index into
-- it for this chord's root. a degree that runs off the end of the pool (or
-- past MIDI's range) is dropped rather than erroring -- the chord just comes
-- out with fewer notes, same defensive approach the rest of this repo takes
-- with scale pools.
function Chords.build(scale, root_index, degrees, chromatic)
  local root = scale[root_index]
  if root == nil then return {} end

  local notes = {}
  for _, d in ipairs(degrees) do
    local n
    if chromatic then
      n = root + math.floor(d / 7) * 12 + MAJOR_STEPS[(d % 7) + 1]
    else
      n = scale[root_index + d]
    end
    if n ~= nil and n >= 0 and n <= 127 then table.insert(notes, n) end
  end
  return notes
end

-- positive inverts up (lowest note moves an octave up, repeated), negative
-- inverts down (highest note moves an octave down)
function Chords.invert(notes, amount)
  local result = {}
  for i, n in ipairs(notes) do result[i] = n end
  for _ = 1, amount do
    if #result > 1 then
      local lowest = table.remove(result, 1)
      table.insert(result, lowest + 12)
    end
  end
  for _ = 1, -amount do
    if #result > 1 then
      local highest = table.remove(result, #result)
      table.insert(result, 1, highest - 12)
    end
  end
  return result
end

-- picks how to place `notes` so they move as little as possible from what's
-- already sounding: returns an inversion count and an octave shift for the
-- caller to apply. this is voice leading -- without it, moving from one grid
-- cell to another jumps the whole chord to wherever that root sits.
--
-- returns 0, 0 when there's nothing to lead from, so the chord keeps the
-- placement it was built with.
function Chords.lead(notes, reference)
  if #notes == 0 or reference == nil or #reference == 0 then return 0, 0 end

  local best_cost, best_inv, best_oct = math.huge, 0, 0
  for inv = -(#notes - 1), (#notes - 1) do
    local candidate = Chords.invert(notes, inv)
    for oct = -1, 1 do
      local cost = 0
      for _, n in ipairs(candidate) do
        local nearest = math.huge
        for _, r in ipairs(reference) do
          nearest = math.min(nearest, math.abs((n + oct * 12) - r))
        end
        cost = cost + nearest
      end
      -- tiny penalties so that, all else equal, the plainest placement wins
      -- rather than an arbitrary one
      cost = cost + math.abs(inv) * 0.01 + math.abs(oct) * 0.05
      if cost < best_cost then
        best_cost, best_inv, best_oct = cost, inv, oct
      end
    end
  end
  return best_inv, best_oct
end

-- best-effort chord symbol for the screen, read off the actual pitch
-- classes present rather than the voicing that produced them.
--
-- `root` must be the chord's real root, not notes[1] -- an inverted or
-- spread voicing puts some other tone in the bass, and naming from the
-- bass turns an inverted Cmaj7 into "Em". a bass note that isn't the root
-- is reported as a slash instead.
function Chords.name(root, notes, note_names)
  if #notes == 0 then return "--" end

  local pc = {}
  local lowest = notes[1]
  for _, n in ipairs(notes) do
    pc[(n - root) % 12] = true
    if n < lowest then lowest = n end
  end

  local quality
  if pc[3] then quality = "m"
  elseif pc[4] then quality = ""
  elseif pc[5] then quality = "sus4"
  elseif pc[2] then quality = "sus2"
  else quality = "5" end

  if pc[3] and pc[6] and not pc[7] then quality = "dim" end
  if pc[4] and pc[8] and not pc[7] then quality = "aug" end

  -- highest tertian extension present wins, so a 7-9-11 stack reads as 11
  local ext = ""
  if pc[10] or pc[11] then
    local major_seventh = pc[11]
    if pc[9] then ext = major_seventh and "maj13" or "13"
    -- an 11th needs the 9th (or a third) under it; root-4-5-b7 alone
    -- is a 7sus4, not an 11
    elseif pc[5] and (pc[2] or pc[3] or pc[4]) then ext = major_seventh and "maj11" or "11"
    elseif pc[2] then ext = major_seventh and "maj9" or "9"
    else ext = major_seventh and "maj7" or "7" end
  elseif pc[9] then
    ext = pc[2] and "6/9" or "6"
  elseif pc[2] and (pc[3] or pc[4]) then
    ext = "add9"
  end

  -- a tone already named in the extension isn't also a suspension: the 2 of
  -- a sus2 is the 9 ("Cmaj9", not "Cmaj9sus2"), and an 11 chord customarily
  -- leaves the third out, so its 4 is the 11 ("Cmaj11", not "Cmaj11sus4")
  if quality == "sus2" and (ext:find("9") or ext:find("11") or ext:find("13")) then
    quality = ""
  end
  if quality == "sus4" and ext:find("11") then quality = "" end

  local name = note_names[(root % 12) + 1]
  if quality:sub(1, 3) == "sus" then
    name = name .. ext .. quality       -- "C7sus4", not "Csus47"
  else
    name = name .. quality .. ext
  end

  if lowest % 12 ~= root % 12 then
    name = name .. "/" .. note_names[(lowest % 12) + 1]
  end
  return name
end

return Chords
