-- strum.lua
-- one strummer for everything that's held. every held chord (grid cell or
-- MIDI note) adds its notes to a shared pool, and each pass strums the
-- whole pool as one gesture -- hold two chords and you hear one strum over
-- both, arpeggiator-style, not two strums stacked on top of each other.
--
-- why one engine rather than one per chord: separate strummers ran on
-- separate timing, so held chords fell out of step with each other, and a
-- pitch shared by two chords on the same MIDI channel could be cut off by
-- the other chord's note-off. here a pitch is owned once, in one map, and
-- there's a single rhythm everything joins.
--
-- chord changes are soft: a released chord's notes aren't cut, they ring for
-- `release_sec` and are then stopped -- unless a still-held chord owns that
-- pitch too, or it gets struck again first, in which case it just carries on.
--
-- caller supplies to Strum.new:
--   opts       function() -> settings, re-read at the start of every pass
--   cycler     a Patterns.cycler(), picks the pattern slots for each pass
--   on_strike  optional function(note, velocity), for display
local Strum = {}

-- humanize's per-pass and per-note depths at 100%. the knob is curved
-- (amount^1.5) so the low end is subtle: at 25% these land around an eighth
-- of their full size. variation is split between the whole strum (a little
-- faster or slower, softer or harder, a touch late) and each note (much
-- smaller), since a player varies the gesture more than individual strings --
-- the previous version jittered every gap independently by the full amount,
-- which read as sloppy rather than human by about 25%.
local TEMPO_PASS = 0.25
local GAP_NOTE = 0.15
local VEL_PASS = 0.15
local VEL_NOTE = 0.08
local LATE_MAX = 0.015  -- seconds a whole strum may land behind the beat
local FLAM_MAX = 0.006  -- seconds of spread between notes meant to coincide

-- drift is humanize's slow cousin: a random walk that wanders over tens of
-- seconds rather than re-rolling each pass, like a player gradually pushing
-- and relaxing. INERTIA is how much of the previous value carries over
-- (higher = slower wander); the depths are at 100%.
local DRIFT_INERTIA = 0.92
local DRIFT_STEP = 0.12
local DRIFT_TEMPO = 0.2
local DRIFT_VEL = 0.2

-- triangular distribution on -1..1: mostly small, occasionally large
local function tri() return math.random() + math.random() - 1 end

-- thins a pool by dropping from the middle, always keeping the lowest and
-- highest note so the chord keeps its shape and its bass
local function thin(pool, density)
  local n = #pool
  if density >= 1 or n <= 2 then return pool end
  local keep = math.max(2, util.round(n * density))
  if keep >= n then return pool end
  local out, seen = {}, {}
  for i = 1, keep do
    local idx = util.round(1 + (i - 1) * (n - 1) / (keep - 1))
    if not seen[idx] then
      seen[idx] = true
      out[#out + 1] = pool[idx]
    end
  end
  return out
end

function Strum.new(args)
  local m = setmetatable({}, {__index = Strum})
  m.opts = args.opts
  m.cycler = args.cycler
  m.on_strike = args.on_strike
  m.held = {}        -- key -> {notes_fn, set = {note = true}}
  m.sounding = {}    -- note -> {device, channel, tail}
  m.last_pool = {}
  m.drift_tempo = 0
  m.drift_vel = 0
  m.running = false
  m.state = "idle"   -- idle / strumming / waiting
  m.kick = false
  return m
end

function Strum:count()
  local n = 0
  for _ in pairs(self.held) do n = n + 1 end
  return n
end

function Strum:add(key, notes_fn)
  if self.held[key] then self:remove(key) end
  local h = {notes_fn = notes_fn, set = {}}
  for _, note in ipairs(notes_fn() or {}) do h.set[note] = true end
  self.held[key] = h

  -- a pitch this chord owns that was ringing out from a released chord is
  -- wanted again, so it shouldn't be stopped by that old release. clearing
  -- `off_at` alongside the token matters: it's the deadline _tail compares
  -- against, and leaving a stale one behind made the next release think a
  -- stop was already scheduled when that timer had long since been dropped,
  -- so the note was never stopped at all.
  for note in pairs(h.set) do
    local s = self.sounding[note]
    if s then
      s.tail = nil
      s.off_at = nil
    end
  end

  local o = self.opts()
  if not self.running then
    self:_start()
  elseif not o.cycle or o.retrigger_now then
    -- a one-shot has to strum again or the new chord would never sound;
    -- in cycle mode this is the "strum now" setting. between passes the
    -- wait is cancelled outright; mid-pass, the pass finishes and the next
    -- one starts straight away instead of waiting its turn.
    if self.state == "waiting" then
      self:_stop()
      self:_start()
    else
      self.kick = true
    end
  end
end

function Strum:remove(key)
  local h = self.held[key]
  if h == nil then return end
  self.held[key] = nil

  local release = self.opts().release_sec
  for note in pairs(h.set) do
    if not self:_owned(note) then self:_tail(note, release) end
  end

  if next(self.held) == nil then self:_stop() end
end

function Strum:panic(device)
  self.held = {}
  self:_stop()
  for note in pairs(self.sounding) do self:_off(note) end
  -- CC 123 is "all notes off": 16 messages rather than 2048
  if device then
    for ch = 1, 16 do device:cc(123, 0, ch) end
  end
end

-- ============================================================
-- internals
-- ============================================================

function Strum:_owned(note)
  for _, h in pairs(self.held) do
    if h.set[note] then return true end
  end
  return false
end

-- notes are tracked by their pool pitch, but sent as `out` -- the bass split
-- can transpose the lowest note, and the note-off has to match what actually
-- went out
function Strum:_off(note)
  local s = self.sounding[note]
  if s == nil then return end
  if s.device then s.device:note_off(s.out or note, 0, s.channel) end
  self.sounding[note] = nil
end

function Strum:sounding_notes()
  local out = {}
  for note in pairs(self.sounding) do out[#out + 1] = note end
  table.sort(out)
  return out
end

-- stops a note after `sec`, unless something re-claims it first: a re-strike
-- replaces the sounding entry (dropping this token), and a re-press clears
-- the tail. these timers are never cancelled, only made obsolete, so they
-- don't need the clock-id care the main coroutine does.
--
-- an earlier stop already scheduled wins: letting go of a key shouldn't
-- extend a note past the note-length gate it was struck with.
function Strum:_tail(note, sec)
  local s = self.sounding[note]
  if s == nil then return end
  if sec <= 0 then
    self:_off(note)
    return
  end
  -- defer to an existing stop only if that timer is still live: `off_at`
  -- without a token is a leftover from one that was dropped
  local deadline = util.time() + sec
  if s.tail and s.off_at and s.off_at <= deadline then return end

  local token = {}
  s.tail = token
  s.off_at = deadline
  clock.run(function()
    clock.sleep(sec)
    local cur = self.sounding[note]
    if cur and cur.tail == token then self:_off(note) end
  end)
end

-- stopping a pitch before re-striking it keeps it from ever being on twice
-- with only one note-off to clear it
function Strum:_strike(note, velocity, o, is_bass)
  if self.sounding[note] then self:_off(note) end

  local channel, out = o.channel, note
  if is_bass and o.bass_channel then
    channel = o.bass_channel
    out = util.clamp(note + (o.bass_shift or 0), 0, 127)
  end

  o.device:note_on(out, velocity, channel)
  self.sounding[note] = {device = o.device, channel = channel, out = out}
  if self.on_strike then self.on_strike(note, velocity) end
end

-- NOTHING here calls clock.cancel, deliberately.
--
-- norns' clock.cancel nils the thread but a wake already queued for it still
-- arrives, and the scheduler then resumes a nil thread: "bad argument #1 to
-- 'resume' (thread expected)". Cancelling a coroutine sitting in clock.sync
-- or clock.sleep -- which is exactly what stopping a strum meant -- hit that
-- race, crashed the clock, and took any note-off timer waiting behind it with
-- it, so notes hung.
--
-- instead a run carries a token. stopping clears it, and the run checks it
-- at every wake and before every strike, so a superseded run makes no sound
-- and retires itself the next time it wakes. worst case it lingers, silent,
-- until its next wake was due.
--
-- (an earlier version guarded against norns reusing clock ids. it doesn't --
-- the id counter only ever increments -- so that guard was unnecessary.)
function Strum:_stop()
  self.running = false
  self.state = "idle"
  self.kick = false
  self.token = nil
end

-- `running` is set before clock.run because the coroutine starts executing
-- immediately and can finish inside that first resume
function Strum:_start()
  local token = {}
  self.token = token
  self.running = true
  self.state = "strumming"
  clock.run(function()
    self:_run(token)
    if self.token == token then
      self.running = false
      self.state = "idle"
    end
  end)
end

function Strum:_run(token)
  while true do
    if self.token ~= token then return end

    local o = self.opts()
    if o.device == nil then return end

    self.state = "strumming"
    self.kick = false
    self:_pass(o, token)

    if self.token ~= token or next(self.held) == nil then return end
    if not o.cycle and not self.kick then return end

    if not self.kick then
      self.state = "waiting"
      if o.cycle_sync then
        clock.sync(o.cycle_beats)
      else
        clock.sleep(o.cycle_sec)
      end
    end
  end
end

function Strum:_pool()
  local union = {}
  for _, h in pairs(self.held) do
    h.set = {}
    for _, note in ipairs(h.notes_fn() or {}) do
      h.set[note] = true
      union[note] = true
    end
  end
  local pool = {}
  for note in pairs(union) do pool[#pool + 1] = note end
  table.sort(pool)
  return pool
end

function Strum:_pass(o, token)
  -- density thins the pool structurally, the same way every pass, unlike
  -- probability which re-rolls per note per pass
  local pool = thin(self:_pool(), o.density)
  self.last_pool = pool

  local playing = {}
  for _, note in ipairs(pool) do playing[note] = true end

  -- anything still sounding that this pass isn't playing gets the soft
  -- release: a chord that was let go, or a note dropped because density
  -- fell or the chord re-voiced itself mid-hold (bank/invert/transpose are
  -- re-read every pass)
  for note, s in pairs(self.sounding) do
    if not s.tail and not playing[note] then self:_tail(note, o.release_sec) end
  end

  local n = #pool
  if n == 0 then return end

  local slots = self.cycler:step(o.pattern, n)
  local top = 0
  for i = 1, n do if slots[i] > top then top = slots[i] end end

  -- which way the hand is moving, read off the pattern itself rather than
  -- being told: if the lowest note lands before the highest it's a
  -- downstroke. works for any pattern, mirrored or mid-morph.
  local upstroke = (n > 1) and (slots[1] > slots[n])

  -- an upstroke catches fewer strings, from the top down
  local skip_below = 0
  if upstroke and o.upstroke_keep < 1 then
    skip_below = n - math.max(1, util.round(n * o.upstroke_keep))
  end

  -- fit: scale the gap so the strum spans a set fraction of the repeat,
  -- however many notes are in the pool
  local gap = o.gap
  if o.fit and top > 0 then gap = (o.span * o.repeat_sec) / top end

  local k = (o.humanize > 0) and (o.humanize ^ 1.5) or 0
  if o.drift > 0 then
    self.drift_tempo = util.clamp(self.drift_tempo * DRIFT_INERTIA + tri() * DRIFT_STEP, -1, 1)
    self.drift_vel = util.clamp(self.drift_vel * DRIFT_INERTIA + tri() * DRIFT_STEP, -1, 1)
  end
  local tempo = 1 + tri() * TEMPO_PASS * k + self.drift_tempo * DRIFT_TEMPO * o.drift
  local vel_pass = 1 + tri() * VEL_PASS * k + self.drift_vel * DRIFT_VEL * o.drift

  local events = {}
  for i = 1, n do
    local t = slots[i] * gap * tempo
    if k > 0 then
      t = t + tri() * GAP_NOTE * k * gap + math.random() * FLAM_MAX * k
    end
    -- tilt follows when a note lands, not its pitch; a strum with nothing
    -- to spread over (block) sits in the middle of the curve, untilted
    local frac = (top > 0) and (slots[i] / top) or 0.5
    events[i] = {t = math.max(0, t), note = pool[i], frac = frac, rank = i}
  end
  table.sort(events, function(a, b) return a.t < b.t end)

  if k > 0 then clock.sleep(math.random() * LATE_MAX * k) end
  if self.token ~= token then return end

  local elapsed = 0
  for _, e in ipairs(events) do
    local wait = e.t - elapsed
    if wait > 0 then
      clock.sleep(wait)
      elapsed = e.t
    end
    if self.token ~= token then return end

    -- `playing` is this pass's plan, made before the first note sounded, so
    -- it can name a chord that has since been let go. striking such a note
    -- would replace its sounding entry and drop the release timer set when
    -- the key came up, leaving it ringing forever -- so ownership is checked
    -- again here, at the moment of the strike.
    --
    -- notes an upstroke skips are left ringing rather than released: the
    -- string is still there, the pick just didn't catch it.
    if e.rank > skip_below and playing[e.note] and self:_owned(e.note)
       and math.random() <= o.probability then
      local vel = o.velocity * (1 + o.tilt * (2 * e.frac - 1)) * vel_pass
      if k > 0 then vel = vel * (1 + tri() * VEL_NOTE * k) end
      if upstroke then vel = vel * o.upstroke_level end
      -- the lowest note of the whole pool is the bass, whichever chord it
      -- came from -- held chords merge into one voicing, so they get one bass
      self:_strike(e.note, util.clamp(util.round(vel), 1, 127), o, e.note == pool[1])
      if o.gate_sec > 0 then self:_tail(e.note, o.gate_sec) end
    end
  end
end

return Strum
