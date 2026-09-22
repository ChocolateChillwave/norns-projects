-- lane.lua
-- one lane = one column of the launch grid: a bank of 8 patterns, a set of
-- Rytm voices it drives, its own playhead, and its own follow action. eight
-- of these run against each other, which is where the generative behaviour
-- comes from -- a hat lane can hand itself a new pattern every half bar
-- while the kick lane holds the same one for four.
--
-- TIMING. everything is integer ticks at 96 PPQN, driven by a single master
-- clock coroutine in segue.lua rather than one coroutine per lane. every
-- division we want is a whole number of ticks -- 1/4 is 96, 1/8 is 48, 1/16
-- is 24, 1/32 is 12, and the triplets are 64 / 32 / 16 / 8 -- so quantize
-- boundaries, follow times and beat-repeat buckets are all exact integer
-- comparisons with no floating-point fuzz to guard against. every division
-- also divides a bar (384 ticks) evenly, so a lane always has a step landing
-- exactly on any launch-quantize boundary, whatever division it runs at.
-- see the PPQN constant below for why it is 96 and not 24.
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

-- 96 ticks to the beat, raised from 24 on 2026-09-20. 24 was the smallest
-- resolution at which every division and every bar boundary is a whole
-- number of ticks, and it is still the reason all the timing maths here is
-- integer -- but it put a floor under swing. a 16th was 6 ticks, so the
-- only reachable swing amounts were 0 / 17 / 33 / 50%, and the breaks this
-- library is built around live in between those. at 96 a 16th is 24 ticks,
-- which is roughly 4% resolution.
--
-- the cost is four times as many clock wakeups: 192/sec at 120bpm rather
-- than 48. polyphasic runs a 96 PPQN lattice on this hardware and has been
-- played, so there is direct precedent that a Pi copes -- but this script
-- ticks eight lanes per wakeup, so Lane:tick opens with the cheapest
-- possible rejection (one modulo, two compares) for the common case of
-- "not this lane's step".
Lane.PPQN = 96
Lane.TICKS_PER_BAR = Lane.PPQN * 4
Lane.TICKS_PER_16TH = Lane.PPQN / 4
Lane.PATTERN_COUNT = 8

Lane.DIV_NAMES = {"1/4", "1/4T", "1/8", "1/8T", "1/16", "1/16T", "1/32", "1/32T"}
Lane.DIV_TICKS = {96, 64, 48, 32, 24, 16, 12, 8}
Lane.DIV_16TH = 5 -- index of "1/16", the default

-- swing is a percentage of the lane's own step, not a tick count, so it
-- means the same thing whatever division the lane runs at. 75% is the cap:
-- past that the swung step is closer to the following downbeat than its
-- own, which stops reading as swing.
Lane.SWING_MAX = 75

-- launch quantize, in ticks. QUANT_PATTERN waits for the lane's own loop
-- rather than a fixed musical grid, which is the familiar clip-launch feel
-- on a lane whose pattern is not a whole number of bars long.
Lane.QUANT_PATTERN = -1
Lane.QUANT_TICKS = {0, 12, 24, 48, 96, 192, 384, 768, Lane.QUANT_PATTERN}
Lane.QUANT_NAMES = {"instant", "1/32", "1/16", "1/8", "1/4", "1/2",
                    "1 bar", "2 bar", "pattern"}

Lane.TRANS_CUT = 1
Lane.TRANS_LEGATO = 2
Lane.TRANS_XFADE = 3
Lane.TRANS_HANDOVER = 4
Lane.TRANS_NAMES = {"cut", "legato", "xfade", "handover"}

-- INHERITANCE. a pattern-level setting resolves in three steps:
--
--   the pattern's own override  (pattern.ov[key], nil if it has none)
--   then the lane's             (via self.parent, injected by the caller)
--   then the global value       (also via self.parent)
--
-- the lane and global levels live in norns params, which this module must
-- not touch (CONVENTIONS §4), so the caller hands in `parent(key)` that
-- does both. left out, it falls back to these defaults -- which is what
-- the desktop tests run against, and which are also the shipped globals.
--
-- only settings that are read when something CHANGES live here: follow
-- time and actions, chance, transition, quantize. division, swing and
-- morph are read every tick, so the caller resolves those into plain
-- fields (self.div, self.swing, self.morph_steps) whenever they change,
-- and the 96 PPQN hot path never pays for a lookup.
Lane.DEFAULTS = {
  follow_time = 13,               -- index of "end" in Pattern.FOLLOW_TIMES
  follow_a = 1,                   -- "none"
  follow_b = 1,
  follow_chance = 100,
  trans = Lane.TRANS_LEGATO,
  quant = 7,                      -- index of "1 bar" in QUANT_TICKS
}

local function default_parent(key) return Lane.DEFAULTS[key] end

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

  m.parent = args.parent or default_parent -- lane/global resolution

  m.active = 1
  m.queued = nil                   -- pattern index waiting on a boundary
  m.queued_trans = nil
  m.queued_quant = nil             -- the quantize that launch resolved to
  m.pending_bank = nil             -- a bank column waiting on a boundary
  m.pending_bank_quant = nil
  m.pos = 1                        -- step about to play
  m.started = false
  m.step_count = 0                 -- steps played since the last commit

  m.div = Lane.DIV_16TH
  m.swing = 0                      -- percent of a step, 0-75
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

  -- preallocated hit buffer -- tick() runs 192 times a second across 8
  -- lanes, so it must not allocate (CLAUDE.md's CPU budget rule)
  m.hits = {}
  for i = 1, m.slots do m.hits[i] = {voice = 0, vel = 0} end
  m.hit_count = 0

  m.switched = false               -- set on a tick where a commit happened
  return m
end

function Lane:pattern() return self.bank[self.active] end

-- a setting as it actually applies to pattern `p` (the active one if left
-- out): its own override, else whatever the lane/global chain says.
function Lane:setting(key, p)
  p = p or self:pattern()
  if p and p.ov then
    local v = p.ov[key]
    if v ~= nil then return v end
  end
  return self.parent(key)
end

-- where that value came from -- "pattern" when p overrides it, otherwise
-- whatever the parent chain reports. used by the screen to show inherited
-- values as inherited rather than as if they had been set here.
function Lane:setting_source(key, p)
  p = p or self:pattern()
  if p and p.ov and p.ov[key] ~= nil then return "pattern" end
  return "parent"
end

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

-- swing as a tick offset for this lane's current step length. stored as a
-- percentage (0-75) so it survives a division change meaning the same
-- thing; the achievable resolution is one tick, which at a 1/16 division
-- (24 ticks) is about 4%.
function Lane:swing_ticks(dt)
  if self.swing <= 0 then return 0 end
  dt = dt or self:div_ticks()
  local ticks = math.floor(self.swing / 100 * dt + 0.5)
  if ticks >= dt then ticks = dt - 1 end
  if ticks < 0 then ticks = 0 end
  return ticks
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
  local t = self.P.FOLLOW_TIMES[self:setting("follow_time", p)]
  if t == nil or t == 0 then return nil end
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
-- `from` is the pattern the blend starts from. it is normally whatever was
-- playing, but a bank switch replaces the whole bank before committing, so
-- by the time it gets here the "current" pattern is already the new one --
-- it has to pass the old pattern in explicitly or xfade/handover would
-- blend the new pattern with itself.
function Lane:commit(idx, trans, from)
  if idx == nil or idx < 1 or idx > Lane.PATTERN_COUNT then return end
  trans = trans or self:setting("trans", self.bank[idx])
  from = from or self:pattern()
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
  self.queued_quant = nil
  self.switched = true
end

-- queue a manual launch. pressing the pattern that is already queued
-- cancels it; pressing the one already playing relaunches it (which under
-- `cut` restarts the loop and under `legato` is deliberately a no-op).
--
-- transition and quantize both come from the pattern being LAUNCHED, not
-- the one being left -- the way an Ableton clip carries its own launch
-- settings. so a fill with its own "cut" override always cuts in, whatever
-- the lane or the global transition says.
function Lane:launch(idx, trans)
  if self.queued == idx then
    self.queued = nil
    self.queued_trans = nil
    self.queued_quant = nil
    return
  end
  local target = self.bank[idx]
  self.queued = idx
  self.queued_trans = trans or self:setting("trans", target)
  self.queued_quant = Lane.QUANT_TICKS[self:setting("quant", target)]
end

-- queue a whole new bank column to swap in at the next quantize boundary.
-- the lane stays on the same slot number and hands off with its own
-- transition, so a bank change is just another smooth switch: under legato
-- the playhead carries across into the equivalent kit of the new bank.
function Lane:queue_bank(column, quant_idx)
  self.pending_bank = column
  self.pending_bank_quant = Lane.QUANT_TICKS[quant_idx or self.parent("quant")]
end

function Lane:_swap_bank()
  local from = self:pattern()
  local queued = self.queued
  local queued_quant = self.queued_quant
  self.bank = self.pending_bank
  self.pending_bank = nil
  self.pending_bank_quant = nil
  -- same slot, new bank. the transition is the new pattern's own (it may
  -- override); the blend starts from the pattern that was actually playing.
  self:commit(self.active, self:setting("trans", self.bank[self.active]), from)
  -- commit() clears any queued launch, which is right for an ordinary switch
  -- and wrong here: a kit pressed while the bank change was pending would
  -- otherwise be silently dropped. put it back, aimed at the NEW bank, and
  -- re-read its transition from the pattern that will actually arrive --
  -- the same "arriving pattern decides" rule as every other switch.
  if queued then
    self.queued = queued
    self.queued_quant = queued_quant
    self.queued_trans = self:setting("trans", self.bank[queued])
  end
end

-- how many of this lane's own steps until a queued launch commits, or nil
-- if nothing is waiting. walks forward rather than dividing, because the
-- commit lands on the lane's next STEP whose grid tick sits on a quantize
-- boundary -- which is not the same as the next boundary when the lane's
-- division is coarser than the quantize setting.
function Lane:steps_to_launch(t, quant)
  if self.queued == nil and self.pending_bank == nil then return nil end
  -- the launch carries its own resolved quantize; a bank change carries
  -- the one it was queued with. the argument is only the fallback.
  if self.queued then
    quant = self.queued_quant or quant
  else
    quant = self.pending_bank_quant or quant
  end
  if quant == nil or quant == 0 then return 0 end
  if quant == Lane.QUANT_PATTERN then
    return self:pattern().length - self.pos + 1
  end
  local dt = self:div_ticks()
  local k = math.floor(t / dt)
  for n = 1, 256 do
    if ((k + n) * dt) % quant == 0 then return n end
  end
  return nil
end

-- how many steps until this pattern's follow action fires, or nil if it
-- never will (follow off for the lane, or the pattern's time set to off)
function Lane:steps_to_follow()
  if not self.follow_on then return nil end
  local need = self:follow_steps()
  if need == nil then return nil end
  return math.max(0, need - self.step_count)
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
  local r = t % dt
  local sw = self:swing_ticks(dt)

  -- the cheapest possible rejection first. at 96 PPQN this runs 192 times a
  -- second per lane and almost always lands here, so it is one modulo and
  -- two compares before anything else is computed.
  if r ~= 0 and r ~= sw then return 0 end

  local k = (t - r) / dt

  -- swing delays every second step. `sw` is already in ticks, worked out
  -- from the lane's own step length, so the percentage means the same
  -- thing at any division.
  local fire
  if r == 0 then
    fire = (sw == 0) or (k % 2 == 0)
  else
    fire = (sw > 0) and (k % 2 == 1)
  end
  if not fire then return 0 end

  self.switched = false

  if self.started then
    self.pos = self.pos + 1
    if self.pos > self:pattern().length then self.pos = 1 end
  else
    -- first step after a start: take the playhead from where the shared
    -- timeline says it should be, rather than always beginning at step 1.
    -- that is what makes joining a Link session late sound right -- the
    -- pattern is already in the correct place relative to everyone else,
    -- instead of starting its phrase wherever the transport happened to
    -- begin. the caller controls this by choosing the tick origin: with an
    -- origin of "now", k is 0 here and this still lands on step 1.
    self.started = true
    self.pos = (k % self:pattern().length) + 1
  end

  -- follow first: it belongs to the pattern that just finished playing, and
  -- it deliberately ignores launch quantize (an Ableton follow action fires
  -- on its own clock, not the global grid -- that is what lets it land in
  -- the middle of a bar).
  if self.follow_on then
    local need = self:follow_steps()
    if need and self.step_count >= need then
      local p = self:pattern()
      local action = self:setting("follow_a", p)
      local chance = self:setting("follow_chance", p)
      if chance < 100 and math.random(100) > chance then
        action = self:setting("follow_b", p)
      end
      local target = self:_resolve(action)
      if target then
        -- the arriving pattern's own transition, as with a manual launch
        self:commit(target, self:setting("trans", self.bank[target]))
      else
        self.step_count = 0 -- re-arm, so editing the action later takes hold
      end
    end
  end

  -- a bank change waiting on its boundary goes first, so that a launch
  -- queued in the same breath lands inside the NEW bank rather than the old
  if self.pending_bank and self:_boundary(k * dt, self.pending_bank_quant) then
    self:_swap_bank()
  end

  -- then any manual launch whose quantize boundary has arrived. the
  -- launch's own resolved quantize wins over the one passed in, which is
  -- only the fallback for callers that queue without going through launch()
  if self.queued and self:_boundary(k * dt, self.queued_quant or quant) then
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
  self.queued_quant = nil
  self.pending_bank = nil
  self.pending_bank_quant = nil
end

---------------------------------------------------------------- columns

-- a column is one lane's eight patterns: its share of a bank. these pack
-- one into plain tables and back, for the autosave, psets and the User
-- bank alike. step keys go out as strings because tab.save writes integer
-- keys positionally and a sparse trig row would not survive that.
function Lane.pack_column(column)
  local out = {}
  for i = 1, Lane.PATTERN_COUNT do
    local p = column[i]
    local rows = {}
    for s = 1, p.slots do
      local row = {}
      for step, vel in pairs(p.trigs[s]) do row[tostring(step)] = vel end
      rows[s] = row
    end
    local ov = {}
    for k, v in pairs(p.ov) do ov[k] = v end
    out[i] = {name = p.name, length = p.length, slots = p.slots,
              trigs = rows, ov = ov}
  end
  return out
end

function Lane.unpack_column(t, P, slots)
  local column = {}
  for i = 1, Lane.PATTERN_COUNT do
    local src = t and t[i]
    local p = P.new((src and src.slots) or slots, (src and src.length) or 16,
                    (src and src.name) or "--")
    if src then
      for s = 1, p.slots do
        local row = src.trigs and src.trigs[s]
        if row then
          for step, vel in pairs(row) do p.trigs[s][tonumber(step)] = vel end
        end
      end
      if src.ov then
        for k, v in pairs(src.ov) do p.ov[k] = v end
      end
    end
    column[i] = p
  end
  return column
end

---------------------------------------------------------------- persistence

function Lane:serialize()
  local t = {active = self.active, div = self.div, swing = self.swing,
             mute = self.mute, level = self.level, prob = self.prob,
             follow_on = self.follow_on, skip_empty = self.skip_empty,
             transition = self.transition, morph_steps = self.morph_steps,
             voices = {}, bank = {}}
  for i = 1, #self.voices do t.voices[i] = self.voices[i] end
  t.bank = Lane.pack_column(self.bank)
  return t
end

-- `opts.settings` restores the values that a caller might instead be
-- holding in params (division, swing, level, mute, follow, transition,
-- morph). it defaults to OFF, which is the important half of the contract:
-- segue keeps those in norns params, so a data blob restoring them too
-- would give the same value two homes and let the blob quietly win. the
-- flag exists so the round trip can still be tested end to end.
function Lane:deserialize(t, opts)
  if type(t) ~= "table" then return end
  opts = opts or {}
  self.active = t.active or 1
  if opts.settings then
    self.div = t.div or Lane.DIV_16TH
    self.swing = t.swing or 0
    self.mute = t.mute or false
    self.level = t.level or 1.0
    self.prob = t.prob or 1.0
    if t.follow_on ~= nil then self.follow_on = t.follow_on end
    self.transition = t.transition or Lane.TRANS_LEGATO
    self.morph_steps = t.morph_steps or 8
  end
  if t.skip_empty ~= nil then self.skip_empty = t.skip_empty end
  if t.voices then
    self.voices = {}
    for i = 1, #t.voices do self.voices[i] = t.voices[i] end
    self.slots = #self.voices
    self.hits = {}
    for i = 1, self.slots do self.hits[i] = {voice = 0, vel = 0} end
  end
  if t.bank then
    self.bank = Lane.unpack_column(t.bank, self.P, self.slots)
  end
  self:reset()
end

return Lane
