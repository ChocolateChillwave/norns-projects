-- pattern.lua
-- one pattern = one "clip": a fixed-length step grid for a single lane,
-- plus the follow settings that decide what happens after it has played.
--
-- trigs are indexed by SLOT, not by Rytm voice -- slot 1 is whatever the
-- owning lane has as its first voice. that keeps a pattern portable: the
-- same two-row hat pattern works whether the lane is driving CH+OH or two
-- toms, and the step editor can just draw the lane's slots as rows.
--
-- a cell is a velocity (1-127) or nil for no trig. no separate on/off flag
-- and no accent flag -- an accent is just a higher velocity, which is also
-- exactly what the Rytm wants to receive.
--
-- pure Lua, no norns APIs -- testable off-device.
local Pattern = {}

-- velocity levels the built-in library is written in terms of
Pattern.ACCENT = 112
Pattern.NORMAL = 90
Pattern.GHOST = 52

-- follow actions, mirroring Ableton's set. resolved in lane.lua -- this
-- table is only the vocabulary and the order the params menu shows them in.
Pattern.ACTIONS = {
  "none",   -- stay on this pattern (the timer still re-arms, so a later
            -- edit to the action takes effect without a relaunch)
  "next",   -- the next pattern in the bank, wrapping
  "prev",
  "first",
  "last",
  "any",    -- any pattern in the bank, this one included
  "other",  -- any pattern except this one
  "rand2",  -- either neighbour (prev or next)
}
Pattern.ACTION_NONE = 1
Pattern.ACTION_NEXT = 2

-- follow-action times, in 16th-note steps. 0 is the "off" sentinel and -1
-- means "when the pattern loops", i.e. Ableton's default end-of-clip
-- behaviour -- expressed separately from a step count because a pattern's
-- length is editable and the follow time should track it.
Pattern.FOLLOW_END = -1
Pattern.FOLLOW_TIMES = {0, 1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 64, Pattern.FOLLOW_END}
Pattern.FOLLOW_NAMES = {"off", "1/16", "1/8", "1/8.", "1/4", "1/4.", "1/2",
                        "1/2.", "1 bar", "1.5 bar", "2 bar", "4 bar", "end"}

function Pattern.new(slots, length, name)
  local p = {
    name = name or "--",
    length = length or 16,
    slots = slots or 1,
    trigs = {},
    -- follow defaults to Ableton's out-of-the-box behaviour: nothing
    -- happens until you give the pattern somewhere to go.
    follow = {time = Pattern.FOLLOW_END, a = 1, b = 1, chance = 100},
  }
  for s = 1, p.slots do p.trigs[s] = {} end
  return p
end

function Pattern.get(p, slot, step)
  local row = p.trigs[slot]
  if row == nil then return nil end
  return row[((step - 1) % p.length) + 1]
end

function Pattern.set(p, slot, step, vel)
  if p.trigs[slot] == nil then p.trigs[slot] = {} end
  p.trigs[slot][step] = (vel and vel > 0) and vel or nil
end

-- cycle a cell off -> normal -> accent -> ghost -> off. one grid key can
-- then reach every velocity level the library itself uses, without a
-- separate "velocity mode" -- press repeatedly to land on the one you want.
function Pattern.cycle(p, slot, step)
  local v = Pattern.get(p, slot, step)
  local nxt
  if v == nil then nxt = Pattern.NORMAL
  elseif v >= Pattern.ACCENT then nxt = Pattern.GHOST
  elseif v >= Pattern.NORMAL then nxt = Pattern.ACCENT
  else nxt = nil end
  Pattern.set(p, slot, step, nxt)
  return nxt
end

function Pattern.clear(p)
  for s = 1, p.slots do p.trigs[s] = {} end
end

function Pattern.is_empty(p)
  for s = 1, p.slots do
    for _ in pairs(p.trigs[s]) do return false end
  end
  return true
end

function Pattern.copy(p)
  local q = Pattern.new(p.slots, p.length, p.name)
  for s = 1, p.slots do
    local row = {}
    for step, vel in pairs(p.trigs[s]) do row[step] = vel end
    q.trigs[s] = row
  end
  q.follow = {time = p.follow.time, a = p.follow.a, b = p.follow.b,
              chance = p.follow.chance}
  return q
end

-- how many steps until this pattern's follow action should fire, given its
-- current length. FOLLOW_END is resolved here rather than at edit time so
-- that changing a pattern's length moves its end-of-pattern follow with it.
function Pattern.follow_steps(p)
  local t = p.follow.time
  if t == 0 then return nil end
  if t == Pattern.FOLLOW_END then return p.length end
  return t
end

-- build from the compact string form the library is written in:
-- one character per step, "-" = rest. see library.lua for the key.
local CHARS = {
  ["x"] = Pattern.NORMAL, ["X"] = Pattern.ACCENT, ["o"] = Pattern.GHOST,
}
function Pattern.from_rows(rows, name, length)
  local len = length or #rows[1]
  local p = Pattern.new(#rows, len, name)
  for s = 1, #rows do
    local row = rows[s]
    for step = 1, math.min(#row, len) do
      local vel = CHARS[row:sub(step, step)]
      if vel then p.trigs[s][step] = vel end
    end
  end
  return p
end

return Pattern
