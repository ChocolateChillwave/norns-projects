-- patchcore: shared randomize / lock / morph / undo / wander engine for
-- MIDI CC patch-editor scripts (rytmpatch, summitpatch). generic: knows
-- nothing about any particular synth. identical copies live in each
-- script's lib/ so every script folder stays standalone on the device.
--
-- vocabulary:
--   desc  -- a parameter description from a device map:
--            {name, min, max, rmin?, rmax?, bias?, centered?, discrete?,
--             lock?, labels?, default?}
--            rmin/rmax = the TAME window: the part of the range that stays
--            musical, which is what randomize uses by default. min/max
--            stay the full range the encoder can reach, so nothing is
--            unreachable by hand -- taming only ever constrains the dice.
--            bias = "low"/"high"/"center": shape of the draw inside the
--            window (an envelope attack wants to land short far more often
--            than long, even within a tame window). lock = starts locked.
--            hard = "min"/"max"/"both": the one kind of cap the outlier
--            draw may not cross (see tail_room).
--
--   mode  -- per param, cycled by the script's lock key:
--            "tame"   randomize inside rmin..rmax, with bias (default)
--            "wide"   randomize across the param's full min..max
--            "locked" never randomized, never wandered
--            a global `spread` (0..1) widens every tame window toward the
--            full range at once; "wide" is that one param pinned at 1.
--   slot  -- one addressable instance of a desc: {key=unique string,
--            desc=desc, ...anything the owning script needs to send it
--            (track, channel, cc...)}. pages are arrays of slots, with
--            `false` for empty positions.
--
-- the owning script supplies send(slot, value) -- core never talks MIDI
-- itself except through the static helpers at the bottom.

local Core = {}
Core.__index = Core

function Core.new(opts)
  local self = setmetatable({}, Core)
  self.values = {}      -- key -> integer value (what we believe the device holds)
  self.modes = {}       -- key -> 1 tame / 2 wide / 3 locked (nil = desc default)
  self.undo = {}        -- scope -> list of {slot, value}
  self.morphs = {}      -- scope -> clock id
  self.send = opts.send
  self.on_change = opts.on_change or function() end
  return self
end

------------------------------------------------------------------ values

function Core:default(desc)
  if desc.default then return desc.default end
  if desc.centered then return math.floor((desc.min + desc.max + 1) / 2) end
  return desc.min
end

function Core:get(slot)
  local v = self.values[slot.key]
  if v == nil then return self:default(slot.desc) end
  return v
end

-- store + transmit. force=true resends even when unchanged ("send all").
function Core:set(slot, v, force)
  local d = slot.desc
  v = util.clamp(math.floor(v + 0.5), d.min, d.max)
  if force or self.values[slot.key] ~= v then
    self.values[slot.key] = v
    self.send(slot, v)
    self.on_change()
  end
end

-- value arrived from the device itself (knob turned on the hardware):
-- remember it, don't echo it back
function Core:receive(slot, v)
  self.values[slot.key] = util.clamp(v, slot.desc.min, slot.desc.max)
  self.on_change()
end

function Core:delta(slot, d)
  local desc = slot.desc
  -- wide continuous params get acceleration-free 1:1 steps; that's what
  -- MDPatch does too and it keeps fine edits predictable
  self:set(slot, util.clamp(self:get(slot) + d, desc.min, desc.max))
end

Core.MODES = {"tame", "wide", "locked"}

function Core:mode(slot)
  local m = self.modes[slot.key]
  if m == nil then return slot.desc.lock and "locked" or "tame" end
  return Core.MODES[m]
end

function Core:is_locked(slot) return self:mode(slot) == "locked" end

-- tame -> wide -> locked -> tame. one key opens a param up for the dice or
-- takes it out of play entirely, without burying either in a menu.
function Core:cycle_mode(slot)
  local m = self.modes[slot.key] or (slot.desc.lock and 3 or 1)
  self.modes[slot.key] = (m % 3) + 1
  self.on_change()
  return self:mode(slot)
end

function Core:set_mode(slot, name)
  for i, n in ipairs(Core.MODES) do
    if n == name then self.modes[slot.key] = i end
  end
  self.on_change()
end

------------------------------------------------------------------ randomize

-- the window randomize (and wander) may move a param inside. `spread` 0..1
-- opens the tame window out toward the param's full range; a "wide" param
-- is always fully open. an override (a recipe) replaces the map's window
-- but is widened by spread just the same.
function Core:window(slot, spread, override)
  local d = slot.desc
  local lo, hi
  if override then lo, hi = override[1], override[2]
  else lo, hi = d.rmin or d.min, d.rmax or d.max end
  spread = self:mode(slot) == "wide" and 1 or (spread or 0)
  if spread > 0 then
    lo = lo + (d.min - lo) * spread
    hi = hi + (d.max - hi) * spread
  end
  if lo > hi then lo, hi = hi, lo end
  return lo, hi
end

-- shape a uniform draw inside the window. strength fades to 0 as the
-- window opens up, so "wide"/"full" really is uniform across the range.
local function shape(u, bias, strength)
  if not bias or strength <= 0 then return u end
  local b
  if bias == "low" then b = u * u
  elseif bias == "high" then b = 1 - (1 - u) * (1 - u)
  else b = (u + math.random()) / 2 end -- center: triangular
  return u + (b - u) * strength
end

-- how much room there is outside the window on each side, honouring a
-- desc's `hard` cap ("min"/"max"/"both") -- the few places where an
-- accidental extreme is a hazard rather than a surprise (runaway delay
-- feedback, a compressor's makeup gain). `hard` only stops the dice:
-- "wide" mode and widen range are deliberate, and still open the param.
local function tail_room(d, lo, hi)
  local below = (d.hard == "min" or d.hard == "both") and 0 or math.max(0, math.ceil(lo) - d.min)
  local above = (d.hard == "max" or d.hard == "both") and 0 or math.max(0, d.max - math.floor(hi))
  return below, above
end

-- one value: usually from inside the window (shaped by bias), but with
-- probability `tails` from outside it instead. the extremes are musical
-- sometimes -- sustain 0 for a pluck, a slow pad attack, a filter slammed
-- shut -- they just shouldn't be as likely as the sane middle. outside
-- draws are uniform, so a genuine 0 is as reachable as a near miss.
function Core:draw(slot, lo, hi, opts)
  local d = slot.desc
  local wide = self:mode(slot) == "wide"
  local tails = wide and 0 or (opts.tails or 0)
  if tails > 0 and math.random() < tails then
    local below, above = tail_room(d, lo, hi)
    if below + above > 0 then
      if math.random() * (below + above) < below then
        return math.random(d.min, math.ceil(lo) - 1)
      end
      return math.random(math.floor(hi) + 1, d.max)
    end
  end
  if d.discrete then return math.random(util.round(lo), util.round(hi)) end
  local u = (opts.lo or 0) + math.random() * ((opts.hi or 1) - (opts.lo or 0))
  u = shape(u, d.bias, 1 - (wide and 1 or (opts.spread or 0)))
  return lo + u * (hi - lo)
end

-- amount 0..1: 1 = fresh random value, 0.25 = drift a quarter of the way
-- from the current value toward a random one. for discrete params
-- (waveforms, filter types) amount is the probability of re-rolling,
-- since "a quarter of the way from SAW to SQUARE" isn't meaningful.
-- opts.lo/hi 0..1 narrow the window further (MDPatch's CC min/max).
function Core:roll(slot, opts, range_override)
  local d = slot.desc
  local lo, hi = self:window(slot, opts.spread, range_override)
  local cur = self:get(slot)
  local target = self:draw(slot, lo, hi, opts)
  if d.discrete then
    if math.random() > opts.amount then return cur end
    return util.clamp(util.round(target), d.min, d.max)
  end
  return util.round(util.clamp(cur + (target - cur) * opts.amount, d.min, d.max))
end

-- slots: array (may contain false holes), n = its length.
-- opts: {amount, lo, hi, spread, tails, beats, scope,
--        ranges=fn(slot)->{lo,hi}|nil, keep_undo}
function Core:randomize(slots, n, opts)
  local changes = {}
  for i = 1, n do
    local s = slots[i]
    if s and not self:is_locked(s) then
      local ov = opts.ranges and opts.ranges(s) or nil
      changes[#changes + 1] = {slot = s, to = self:roll(s, opts, ov)}
    end
  end
  if not opts.keep_undo then self:snapshot(opts.scope, slots, n) end
  self:apply(changes, opts.beats, opts.scope)
  return #changes
end

------------------------------------------------------------------ undo

function Core:snapshot(scope, slots, n)
  local snap = {}
  for i = 1, n do
    local s = slots[i]
    if s then snap[#snap + 1] = {slot = s, value = self:get(s)} end
  end
  self.undo[scope] = snap
end

-- swaps the stored snapshot with the current values, so pressing undo a
-- second time is redo
function Core:swap_undo(scope, beats)
  local snap = self.undo[scope]
  if not snap then return false end
  local redo, changes = {}, {}
  for i, e in ipairs(snap) do
    redo[i] = {slot = e.slot, value = self:get(e.slot)}
    changes[i] = {slot = e.slot, to = e.value}
  end
  self.undo[scope] = redo
  self:apply(changes, beats, scope)
  return true
end

------------------------------------------------------------------ morph

-- changes: list of {slot, to}. beats <= 0 jumps immediately. discrete
-- params always jump at the start. each scope has at most one running
-- morph; starting a new one in the same scope cancels the old one where
-- it stands. a param touched by anything else mid-morph (encoder, wander,
-- a different scope's morph, incoming MIDI) drops out of this morph
-- rather than fighting it.
function Core:apply(changes, beats, scope)
  scope = scope or "_"
  if self.morphs[scope] then
    clock.cancel(self.morphs[scope])
    self.morphs[scope] = nil
  end
  local secs = (beats or 0) * clock.get_beat_sec()
  if secs <= 0 then
    for _, c in ipairs(changes) do self:set(c.slot, c.to) end
    return
  end
  local live = {}
  for _, c in ipairs(changes) do
    if c.slot.desc.discrete then
      self:set(c.slot, c.to)
    else
      local from = self:get(c.slot)
      -- never-touched param: adopt its default as the start point quietly
      -- instead of transmitting a pointless first step equal to it
      if self.values[c.slot.key] == nil then self.values[c.slot.key] = from end
      if from ~= c.to then
        live[#live + 1] = {slot = c.slot, from = from, to = c.to, last = from}
      end
    end
  end
  if #live == 0 then return end
  self.morphs[scope] = clock.run(function()
    local t0 = util.time()
    while true do
      local p = math.min(1, (util.time() - t0) / secs)
      local any = false
      for _, m in ipairs(live) do
        if m.last ~= nil then
          if self:get(m.slot) ~= m.last then
            m.last = nil -- someone else moved it; let go
          else
            local v = util.round(m.from + (m.to - m.from) * p)
            self:set(m.slot, v)
            m.last = self:get(m.slot)
            any = true
          end
        end
      end
      if p >= 1 or not any then break end
      clock.sleep(1 / 30)
    end
    self.morphs[scope] = nil
    self.on_change()
  end)
end

function Core:morphing()
  return next(self.morphs) ~= nil
end

function Core:stop_all()
  for scope, id in pairs(self.morphs) do clock.cancel(id) end
  self.morphs = {}
end

------------------------------------------------------------------ wander

-- nudge one random unlocked continuous param in `slots` by up to
-- depth (0..1) of its window, gliding over `beats`. wander stays inside
-- the same tame window randomize uses, so leaving it running doesn't
-- slowly walk the sound somewhere extreme.
function Core:wander_step(slots, n, depth, beats, spread)
  local pool = {}
  for i = 1, n do
    local s = slots[i]
    if s and not s.desc.discrete and not self:is_locked(s) then pool[#pool + 1] = s end
  end
  if #pool == 0 then return end
  local s = pool[math.random(#pool)]
  local lo, hi = self:window(s, spread)
  local to = util.round(util.clamp(self:get(s) + (math.random() * 2 - 1) * (hi - lo) * depth, lo, hi))
  self:apply({{slot = s, to = to}}, beats, "wander:" .. s.key)
end

------------------------------------------------------------------ persistence

-- modes are saved as 1/2/3 numbers so they round-trip through tab.save
-- unambiguously. `extra` lets a script stash its own data (e.g.
-- summitpatch's AFX offsets) in the same file.
function Core:save(path, extra)
  tab.save({values = self.values, modes = self.modes, extra = extra}, path)
end

function Core:load(path)
  if not util.file_exists(path) then return nil end
  local t = tab.load(path)
  if not t then return nil end
  self.values = t.values or {}
  self.modes = t.modes or {}
  -- files written before tame/wide/locked existed carry locks = 1/0
  if t.locks then
    for k, v in pairs(t.locks) do self.modes[k] = (v == 1) and 3 or 1 end
  end
  self.undo = {}
  self.on_change()
  return t.extra
end

------------------------------------------------------------------ midi helpers

-- NRPN with a 7-bit value on data entry MSB (CC6), LSB (CC38) zeroed
function Core.nrpn(dev, ch, msb, lsb, value)
  dev:cc(99, msb, ch)
  dev:cc(98, lsb, ch)
  dev:cc(6, value, ch)
  dev:cc(38, 0, ch)
end

function Core.port_names()
  local names = {}
  for i = 1, #midi.vports do
    names[i] = i .. ": " .. util.trim_string_to_width(midi.vports[i].name, 70)
  end
  return names
end

return Core
