-- lane.lua
-- one lane = one column of the launch grid: a bank of 8 patterns, a set of
-- Rytm voices it drives, its own playhead, and its own follow action. eight
-- of these run against each other, which is where the generative behaviour
-- comes from -- a hat lane can hand itself a new pattern every half bar
-- while the kick lane holds the same one for four.
--
-- TIMING. everything is integer ticks at 24 PPQN, driven by a single master
-- clock coroutine in segue.lua rather than one coroutine per lane. 24 ticks
-- to the beat is the smallest resolution where every division we want is a
-- whole number of ticks -- 1/4 is 24, 1/8 is 12, 1/16 is 6, 1/32 is 3, and
-- the triplets are 16 / 8 / 4 / 2 -- so quantize boundaries, follow times
-- and beat-repeat buckets are all exact integer comparisons with no
-- floating-point fuzz to guard against. every division also divides a bar
-- (96 ticks) evenly, so a lane always has a step landing exactly on any
-- launch-quantize boundary, whatever division it is running at.
--
-- THE SWITCH. this is the point of the script, so it is worth being precise
-- about where it happens. the follow check runs at the TOP of a tick, after
-- the playhead has advanced off the step it just played -- so "follow at
-- 1/4" means: play four steps, advance to step 5, change pattern, and then
-- play step 5 OF THE NEW PATTERN. under `legato` the playhead is left
-- exactly where it was, which is what makes a mid-pattern switch sound like
-- the beat carried on rather than restarted; under `cut` it snaps to step 1
-- the way an ordinary clip launch would. `xfade` and `handover` go further
-- than Ableton does and blend the two patterns over a window (see _read).
--
-- pure Lua, no norns APIs -- testable off-device. the pattern module is
-- passed in rather than included, following the convention in this repo
-- that libs don't include each other.
local Lane = {}

Lane.PPQN = 24
Lane.TICKS_PER_BAR = Lane.PPQN * 4
Lane.TICKS_PER_16TH = Lane.PPQN / 4
Lane.PATTERN_COUNT = 8

Lane.DIV_NAMES = {"1/4", "1/4T", "1/8", "1/8T", "1/16", "1/16T", "1/32", "1/32T"}
Lane.DIV_TICKS = {24, 16, 12, 8, 6, 4, 3, 2}
Lane.DIV_16TH = 5 -- index of "1/16", the default

-- launch quantize, in ticks. QUANT_PATTERN waits for the lane's own loop
-- rather than a fixed musical grid, which is the familiar clip-launch feel
-- on a lane whose pattern is not a whole number of bars long.
Lane.QUANT_PATTERN = -1
Lane.QUANT_TICKS = {0, 3, 6, 12, 24, 48, 96, 192, Lane.QUANT_PATTERN}
Lane.QUANT_NAMES = {"instant", "1/32", "1/16", "1/8", "1/4", "1/2",
                    "1 bar", "2 bar", "pattern"}

Lane.TRANS_CUT = 1
Lane.TRANS_LEGATO = 2
Lane.TRANS_XFADE = 3
Lane.TRANS_HANDOVER = 4
Lane.TRANS_NAMES = {"cut", "legato", "xfade", "handover"}

function Lane:new(args)
  local m = setmetatable({}, {__index = Lane})
  args = args or {}
  m.P = args.pattern_lib           -- the pattern module (injected)
  m.id = args.id or 1
  m.name = args.name or ("lane " .. m.id)
  m.voices = args.voices or {1}    -- Rytm voice numbers, one per slot
  m.slots = #m.voices

  m.bank = {}
  for i = 1, Lane.PATTERN_COUNT do
    m.bank[i] = m.P.new(m.slots, 16, "--")
  end

  m.active = 1
  m.queued = nil                   -- pattern index waiting on a boundary
  m.queued_trans = nil
  m.pos = 1                        -- step about to play
  m.started = false
  m.step_count = 0                 -- steps played since the last commit

  m.div = Lane.DIV_16TH
  m.swing = 0                      -- ticks to delay every second step
  m.mute = false
  m.level = 1.0                    -- velocity scale
  m.prob = 1.0                     -- per-trig probability
  m.follow_on = true
  m.skip_empty = true              -- never let a follow action land on an
                                   -- empty pattern (silence is rarely what
                                   -- was meant, and a part-filled bank is
                                   -- the normal case)
  m.transition = Lane.TRANS_LEGATO
  m.morph_steps = 8

  -- morph state
  m.morph_from = nil
  m.morph_left = 0
  m.morph_total = 0
  m.morph_mode = nil

  -- preallocated hit buffer -- tick() runs up to 48 times a second across
  -- 8 lanes, so it must not allocate (CLAUDE.md's CPU budget rule)
  m.hits = {}
  for i = 1, m.slots do m.hits[i] = {voice = 0, vel = 0} end
  m.hit_count = 0

  m.switched = false               -- set on a tick where a commit happened
  return m
end

function Lane:pattern() return self.bank[self.active] end

-- `boost` is the momentary roll/fill from the FX grid: it halves the lane's
-- step length while held, so the same pattern plays at double time. changing
-- the step length mid-flight shifts where the lane's steps land, which can
-- clip or double a step at the moment it engages -- that is a performance
-- effect being turned on by hand, so the glitch is acceptable (and mostly
-- the point) rather than something to smooth over.
function Lane:div_ticks()
  local dt = Lane.DIV_TICKS[self.div]
  if self.boost then dt = math.floor(dt / 2) end
  if dt < 1 then dt = 1 end
  return dt
end

---------------------------------------------------------------- follow actions

-- indices a follow action is allowed to land on. with skip_empty set this
-- is only the patterns that would actually make a sound.
function Lane:_candidates(out)
  local n = 0
  for i = 1, Lane.PATTERN_COUNT do
    if (not self.skip_empty) or (not self.P.is_empty(self.bank[i])) then
      n = n + 1
      out[n] = i
    end
  end
  return n
end

local _cand = {}

function Lane:_resolve(action)
  local n = self:_candidates(_cand)
  if n == 0 then return nil end
  local cur = self.active
  local name = self.P.ACTIONS[action]

  -- position of the active pattern within the candidate list, so "next"
  -- means the next *usable* pattern rather than the next slot
  local at = nil
  for i = 1, n do
    if _cand[i] == cur then at = i end
  end

  if name == "none" then
    return nil
  elseif name == "next" then
    if at == nil then return _cand[1] end
    return _cand[(at % n) + 1]
  elseif name == "prev" then
    if at == nil then return _cand[n] end
    return _cand[((at - 2) % n) + 1]
  elseif name == "first" then
    return _cand[1]
  elseif name == "last" then
    return _cand[n]
  elseif name == "any" then
    return _cand[math.random(n)]
  elseif name == "other" then
    if n < 2 then return nil end
    local pick = math.random(n - 1)
    if at and pick >= at then pick = pick + 1 end
    return _cand[pick]
  elseif name == "rand2" then
    if at == nil then return _cand[1] end
    local step = (math.random(2) == 1) and 1 or -1
    return _cand[((at - 1 + step) % n) + 1]
  end
  return nil
end

-- the follow time in steps OF THIS LANE. the stored value is in 16ths so
-- that a pattern keeps the same musical follow time when its lane's
-- division changes; "end" resolves against the pattern's current length.
function Lane:follow_steps()
  local p = self:pattern()
  local t = p.follow.time
  if t == 0 then return nil end
  if t == self.P.FOLLOW_END then return p.length end
  local steps = (t * Lane.TICKS_PER_16TH) / self:div_ticks()
  steps = math.floor(steps + 0.5)
  if steps < 1 then steps = 1 end
  return steps
end

---------------------------------------------------------------- switching

-- change pattern now. `pos` is left alone for legato/morph (that is the
-- whole trick -- the playhead carries on where it was, so the switch lands
-- mid-phrase without restarting it) and snapped to 1 for a cut. wrapping by
-- the new pattern's length matters when the two are different sizes.
function Lane:commit(idx, trans)
  if idx == nil or idx < 1 or idx > Lane.PATTERN_COUNT then return end
  trans = trans or self.transition
  local from = self:pattern()
  self.active = idx
  local len = self:pattern().length

  if trans == Lane.TRANS_CUT then
    self.pos = 1
    self.morph_left = 0
    self.morph_from = nil
  else
    self.pos = ((self.pos - 1) % len) + 1
    if trans == Lane.TRANS_XFADE or trans == Lane.TRANS_HANDOVER then
      self.morph_from = from
      self.morph_total = math.max(1, self.morph_steps)
      self.morph_left = self.morph_total
      self.morph_mode = trans
    else
      self.morph_left = 0
      self.morph_from = nil
    end
  end

  self.step_count = 0
  self.queued = nil
  self.queued_trans = nil
  self.switched = true
end

-- queue a manual launch. pressing the pattern that is already queued
-- cancels it; pressing the one already playing relaunches it (which under
-- `cut` restarts the loop and under `legato` is deliberately a no-op).
function Lane:launch(idx, trans)
  if self.queued == idx then
    self.queued = nil
    self.queued_trans = nil
    return
  end
  self.queued = idx
  self.queued_trans = trans or self.transition
end

function Lane:_boundary(grid_tick, quant)
  if quant == nil or quant == 0 then return true end
  if quant == Lane.QUANT_PATTERN then return self.pos == 1 end
  return grid_tick % quant == 0
end

---------------------------------------------------------------- reading steps

function Lane:_read()
  local p = self:pattern()
  local n = 0
  local mix = 1
  if self.morph_left > 0 and self.morph_from then
    mix = 1 - (self.morph_left / self.morph_total)
  end

  for s = 1, self.slots do
    local src = p
    if mix < 1 then
      local use_b
      if self.morph_mode == Lane.TRANS_HANDOVER and self.slots > 1 then
        -- voices hand over one at a time, highest slot first, so the
        -- lane's anchor (slot 1 -- the kick, the downbeat tom) is the last
        -- thing to change. on a single-slot lane there is nothing to
        -- stagger, so it falls back to the probabilistic blend.
        use_b = mix > (self.slots - s) / self.slots
      else
        use_b = math.random() < mix
      end
      if not use_b then src = self.morph_from end
    end
    local vel = self.P.get(src, s, self.pos)
    if vel and (self.prob >= 1 or math.random() < self.prob) then
      local v = vel * self.level
      if v > 127 then v = 127 end
      if v >= 1 then
        n = n + 1
        local h = self.hits[n]
        h.voice = self.voices[s]
        h.vel = v
      end
    end
  end
  self.hit_count = n
  return n
end

---------------------------------------------------------------- the tick

-- called once per master tick. returns the number of hits to play, with the
-- hits themselves in self.hits[1..n] (a reused buffer -- read it before the
-- next tick). returns 0 when this tick is not one of the lane's steps.
function Lane:tick(t, quant)
  local dt = self:div_ticks()
  local k = math.floor(t / dt)
  local r = t - k * dt

  -- swing delays every second step by a whole number of ticks. at 24 PPQN
  -- a 16th is 6 ticks, so the reachable amounts are 0 / 17% / 33% / 50% --
  -- coarse, but those are the musically useful ones and it keeps the whole
  -- timeline on exact integers.
  local fire
  if r == 0 then
    fire = (self.swing == 0) or (k % 2 == 0)
  else
    fire = (self.swing > 0) and (r == self.swing) and (k % 2 == 1)
  end
  if not fire then return 0 end

  self.switched = false

  if self.started then
    self.pos = self.pos + 1
    if self.pos > self:pattern().length then self.pos = 1 end
  else
    self.started = true
  end

  -- follow first: it belongs to the pattern that just finished playing, and
  -- it deliberately ignores launch quantize (an Ableton follow action fires
  -- on its own clock, not the global grid -- that is what lets it land in
  -- the middle of a bar).
  if self.follow_on then
    local need = self:follow_steps()
    if need and self.step_count >= need then
      local f = self:pattern().follow
      local action = f.a
      if f.chance < 100 and math.random(100) > f.chance then action = f.b end
      local target = self:_resolve(action)
      if target then
        self:commit(target, self.transition)
      else
        self.step_count = 0 -- re-arm, so editing the action later takes hold
      end
    end
  end

  -- then any manual launch whose quantize boundary has arrived
  if self.queued and self:_boundary(k * dt, quant) then
    self:commit(self.queued, self.queued_trans)
  end

  if self.morph_left > 0 then self.morph_left = self.morph_left - 1 end
  self.step_count = self.step_count + 1

  if self.mute then
    self.hit_count = 0
    return 0
  end
  return self:_read()
end

function Lane:reset()
  self.pos = 1
  self.started = false
  self.step_count = 0
  self.morph_left = 0
  self.morph_from = nil
  self.queued = nil
  self.queued_trans = nil
end

---------------------------------------------------------------- persistence

function Lane:serialize()
  local t = {active = self.active, div = self.div, swing = self.swing,
             mute = self.mute, level = self.level, prob = self.prob,
             follow_on = self.follow_on, skip_empty = self.skip_empty,
             transition = self.transition, morph_steps = self.morph_steps,
             voices = {}, bank = {}}
  for i = 1, #self.voices do t.voices[i] = self.voices[i] end
  for i = 1, Lane.PATTERN_COUNT do
    local p = self.bank[i]
    local rows = {}
    for s = 1, p.slots do
      local row = {}
      for step, vel in pairs(p.trigs[s]) do row[tostring(step)] = vel end
      rows[s] = row
    end
    t.bank[i] = {name = p.name, length = p.length, slots = p.slots,
                 trigs = rows,
                 follow = {time = p.follow.time, a = p.follow.a,
                           b = p.follow.b, chance = p.follow.chance}}
  end
  return t
end

function Lane:deserialize(t)
  if type(t) ~= "table" then return end
  self.active = t.active or 1
  self.div = t.div or Lane.DIV_16TH
  self.swing = t.swing or 0
  self.mute = t.mute or false
  self.level = t.level or 1.0
  self.prob = t.prob or 1.0
  if t.follow_on ~= nil then self.follow_on = t.follow_on end
  if t.skip_empty ~= nil then self.skip_empty = t.skip_empty end
  self.transition = t.transition or Lane.TRANS_LEGATO
  self.morph_steps = t.morph_steps or 8
  if t.voices then
    self.voices = {}
    for i = 1, #t.voices do self.voices[i] = t.voices[i] end
    self.slots = #self.voices
    self.hits = {}
    for i = 1, self.slots do self.hits[i] = {voice = 0, vel = 0} end
  end
  if t.bank then
    for i = 1, Lane.PATTERN_COUNT do
      local src = t.bank[i]
      if src then
        local p = self.P.new(src.slots or self.slots, src.length or 16,
                             src.name or "--")
        for s = 1, p.slots do
          local row = src.trigs and src.trigs[s]
          if row then
            for step, vel in pairs(row) do
              p.trigs[s][tonumber(step)] = vel
            end
          end
        end
        if src.follow then
          p.follow.time = src.follow.time
          p.follow.a = src.follow.a
          p.follow.b = src.follow.b
          p.follow.chance = src.follow.chance
        end
        self.bank[i] = p
      end
    end
  end
  self:reset()
end

return Lane
