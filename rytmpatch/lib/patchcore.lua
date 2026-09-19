-- patchcore: shared randomize / lock / morph / undo / wander engine for
-- MIDI CC patch-editor scripts (rytmpatch, summitpatch). generic: knows
-- nothing about any particular synth. identical copies live in each
-- script's lib/ so every script folder stays standalone on the device.
--
-- vocabulary:
--   desc  -- a parameter description from a device map:
--            {name, min, max, rmin?, rmax?, centered?, discrete?, lock?,
--             labels?, default?}
--            rmin/rmax = the "sane" randomization window (defaults to
--            min/max). lock = locked by default until the user toggles it.
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
  self.locks = {}       -- key -> 1/0 (explicit user choice; nil = use desc.lock)
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

function Core:is_locked(slot)
  local l = self.locks[slot.key]
  if l == nil then return slot.desc.lock == true end
  return l == 1
end

function Core:toggle_lock(slot)
  self.locks[slot.key] = self:is_locked(slot) and 0 or 1
  self.on_change()
end

------------------------------------------------------------------ randomize

-- amount 0..1: 1 = fresh random value, 0.25 = drift a quarter of the way
-- from the current value toward a random one. for discrete params
-- (waveforms, filter types) amount is the probability of re-rolling,
-- since "a quarter of the way from SAW to SQUARE" isn't meaningful.
-- lo/hi 0..1 narrow the window further (MDPatch's CC min/max).
function Core:roll(slot, amount, lo, hi, range_override)
  local d = slot.desc
  local rmin, rmax = d.rmin or d.min, d.rmax or d.max
  if range_override then rmin, rmax = range_override[1], range_override[2] end
  local cur = self:get(slot)
  if d.discrete then
    if math.random() > amount then return cur end
    return math.random(rmin, rmax)
  end
  local r = rmin + (lo + math.random() * (hi - lo)) * (rmax - rmin)
  return util.round(util.clamp(cur + (r - cur) * amount, d.min, d.max))
end

-- slots: array (may contain false holes), n = its length.
-- opts: {amount, lo, hi, beats, scope, ranges=fn(slot)->{lo,hi}|nil, keep_undo}
function Core:randomize(slots, n, opts)
  local changes = {}
  for i = 1, n do
    local s = slots[i]
    if s and not self:is_locked(s) then
      local ov = opts.ranges and opts.ranges(s) or nil
      changes[#changes + 1] = {slot = s, to = self:roll(s, opts.amount, opts.lo, opts.hi, ov)}
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
-- depth (0..1) of its full range, gliding over `beats`
function Core:wander_step(slots, n, depth, beats)
  local pool = {}
  for i = 1, n do
    local s = slots[i]
    if s and not s.desc.discrete and not self:is_locked(s) then pool[#pool + 1] = s end
  end
  if #pool == 0 then return end
  local s = pool[math.random(#pool)]
  local d = s.desc
  local span = (d.max - d.min) * depth
  local to = util.round(util.clamp(self:get(s) + (math.random() * 2 - 1) * span, d.min, d.max))
  self:apply({{slot = s, to = to}}, beats, "wander:" .. s.key)
end

------------------------------------------------------------------ persistence

-- locks are saved as 1/0 numbers (not booleans) so they round-trip
-- through tab.save unambiguously. `extra` lets a script stash its own
-- data (e.g. summitpatch's AFX offsets) in the same file.
function Core:save(path, extra)
  tab.save({values = self.values, locks = self.locks, extra = extra}, path)
end

function Core:load(path)
  if not util.file_exists(path) then return nil end
  local t = tab.load(path)
  if not t then return nil end
  self.values = t.values or {}
  self.locks = t.locks or {}
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
