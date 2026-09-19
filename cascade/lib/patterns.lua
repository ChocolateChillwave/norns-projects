-- patterns.lua
-- a strum pattern is a SLOT per note: when that note lands, in units of the
-- strum gap. notes arrive sorted low to high, so slot i belongs to the i-th
-- lowest note. equal slots strike together (pinch, block, pairs), and slots
-- needn't be whole numbers (accelerate/decelerate shape the timing itself).
--
-- slots rather than a plain note order because two slot lists can be
-- blended: halfway between "up" and "down" is a real, playable in-between
-- timing, not a coin flip between the two orders. that blend is what lets
-- the pattern cycler change patterns gradually instead of jumping.
--
-- pure Lua, no norns APIs -- testable off-device.
local Patterns = {}

-- listed roughly by similarity, so "advance" steps between neighbours
Patterns.NAMES = {
  "up", "skip up", "pairs", "accelerate", "decelerate", "thumb", "pinch",
  "block", "outside-in", "inside-out", "skip down", "down", "random",
}

local SHAPES = {}

SHAPES["up"] = function(n, i) return i - 1 end
SHAPES["down"] = function(n, i) return n - i end

SHAPES["outside-in"] = function(n, i)
  local from_low, from_high = i - 1, n - i
  if from_low <= from_high then return 2 * from_low end
  return 2 * from_high + 1
end

-- odd-numbered notes first, then the evens: a broken, rolling feel
SHAPES["skip up"] = function(n, i)
  if i % 2 == 1 then return (i - 1) / 2 end
  return math.ceil(n / 2) + (i / 2 - 1)
end

SHAPES["pairs"] = function(n, i) return math.floor((i - 1) / 2) end

-- lowest and highest struck together, then the inner notes rise
SHAPES["pinch"] = function(n, i)
  if i == 1 or i == n then return 0 end
  return i - 1
end

-- bass note alone, a beat of space, then the rest strummed up
SHAPES["thumb"] = function(n, i)
  if i == 1 then return 0 end
  return i
end

SHAPES["block"] = function(n, i) return 0 end

-- same total length as "up", but the gaps shrink (accelerate) or grow
-- (decelerate) through the strum
SHAPES["accelerate"] = function(n, i)
  if n < 2 then return 0 end
  return (n - 1) * math.sqrt((i - 1) / (n - 1))
end
SHAPES["decelerate"] = function(n, i)
  if n < 2 then return 0 end
  return (n - 1) * ((i - 1) / (n - 1)) ^ 2
end

local function raw_slots(name, n)
  local out = {}
  if name == "random" then
    local order = {}
    for i = 1, n do order[i] = i end
    for i = n, 2, -1 do
      local j = math.random(i)
      order[i], order[j] = order[j], order[i]
    end
    for pos, i in ipairs(order) do out[i] = pos - 1 end
  elseif name == "inside-out" then
    for i = 1, n do out[i] = SHAPES["outside-in"](n, i) end
    Patterns.mirror(out)
  elseif name == "skip down" then
    for i = 1, n do out[i] = SHAPES["skip up"](n, i) end
    Patterns.mirror(out)
  else
    local shape = SHAPES[name] or SHAPES["up"]
    for i = 1, n do out[i] = shape(n, i) end
  end
  return out
end

-- reverses timing in place: the last note to land becomes the first
function Patterns.mirror(slots)
  local top = 0
  for _, s in ipairs(slots) do if s > top then top = s end end
  for i, s in ipairs(slots) do slots[i] = top - s end
  return slots
end

function Patterns.slots(idx, n, mirrored)
  local out = raw_slots(Patterns.NAMES[idx] or "up", n)
  if mirrored then Patterns.mirror(out) end
  return out
end

-- ============================================================
-- cycler: decides which pattern plays on each pass
-- ============================================================

-- modes: 1 hold, 2 advance, 3 alternate (mirror), 4 random
Patterns.CYCLE_NAMES = {"hold", "advance", "alternate", "random"}

local Cycler = {}

function Patterns.cycler()
  return setmetatable({pass = 0, changed = 0, seen = nil}, {__index = Cycler})
end

local function same(a, b) return a.idx == b.idx and a.mirrored == b.mirrored end

-- o: {pattern = idx, mode = 1-4, every = passes between changes (>= 1),
--     morph = passes spent blending into a new pattern (0 = instant)}
-- returns this pass's slots for n notes.
function Cycler:step(o, n)
  local pass = self.pass
  self.pass = pass + 1
  local count = #Patterns.NAMES

  local target
  if self.seen == nil then
    -- first pass: start on the chosen pattern with nothing to blend from,
    -- and count "every" from here, not from some time before playing
    self.cur = {idx = o.pattern, mirrored = false}
    self.prev = self.cur
    self.seen = o.pattern
    self.changed = pass
  elseif self.seen ~= o.pattern then
    -- the pattern knob was turned: head there, whatever the mode
    target = {idx = o.pattern, mirrored = false}
    self.seen = o.pattern
  elseif o.mode ~= 1 and pass - self.changed >= o.every then
    if o.mode == 2 then
      target = {idx = self.cur.idx % count + 1, mirrored = false}
    elseif o.mode == 3 then
      target = {idx = self.cur.idx, mirrored = not self.cur.mirrored}
    else
      local r = math.random(count - 1)
      if r >= self.cur.idx then r = r + 1 end
      target = {idx = r, mirrored = false}
    end
  end

  if target and not same(target, self.cur) then
    self.prev = self.cur
    self.cur = target
    self.changed = pass
  end

  -- a morph longer than the gap between automatic changes would never
  -- finish, so it's capped to fit. morph counts in-between passes: with
  -- morph 1 the change pass is half-way and the next pass is fully there.
  local morph = o.morph
  if o.mode ~= 1 then morph = math.min(morph, o.every - 1) end
  local progress = 1
  if morph > 0 then
    progress = math.min(1, (pass - self.changed + 1) / (morph + 1))
  end

  local to = Patterns.slots(self.cur.idx, n, self.cur.mirrored)
  if progress >= 1 or same(self.prev, self.cur) then return to end
  local from = Patterns.slots(self.prev.idx, n, self.prev.mirrored)
  for i = 1, n do to[i] = from[i] * (1 - progress) + to[i] * progress end
  return to
end

return Patterns
