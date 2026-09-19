-- voices.lua
-- the Analog Rytm's 12 voices, and how a trig actually reaches one.
--
-- ADDRESSING. a voice is a (channel, note) pair and nothing else. those 24
-- numbers are the single source of truth -- they live in params, and this
-- module just reads them. the named layouts below are *presets* that fill
-- those params in, not a mode that gets consulted at send time.
--
-- that split is deliberate and was learned the hard way: the first version
-- had a "scheme" consulted on every trig plus a set of optional per-voice
-- overrides, and because every override was a param with a default,
-- params:bang() set all of them at startup and they permanently shadowed
-- the scheme. the scheme control and the channel control both did nothing,
-- silently. with presets writing into one set of values there is no second
-- place for the answer to come from, so that class of bug cannot recur.
--
-- note-offs are queued rather than sent from a per-trig coroutine: at 16ths
-- across 8 lanes that would be up to ~60 short-lived coroutines a second on
-- a Pi for no benefit, since the Rytm's own envelopes decide a hit's length
-- regardless of how long the note is held. the master tick flushes them
-- (see Voices:flush), so a trig's gate is one master tick long.
--
-- pure Lua, no norns APIs -- testable off-device.
local Voices = {}

Voices.COUNT = 12
Voices.NAMES = {"BD", "SD", "RS", "CP", "BT", "LT", "MT", "HT",
                "CH", "OH", "CY", "CB"}
Voices.LONG = {"bass drum", "snare", "rimshot", "clap", "bass tom",
               "low tom", "mid tom", "high tom", "closed hat", "open hat",
               "cymbal", "cowbell"}

-- layouts. SEQ is the default because it is what the Rytm this was written
-- for is actually set to: everything on one channel, notes counting up from
-- zero in track order.
Voices.LAYOUT_SEQ = 1
Voices.LAYOUT_FACTORY = 2
Voices.LAYOUT_TRACK = 3
Voices.LAYOUT_NAMES = {"one ch, notes 0-11",
                       "one ch, factory notes",
                       "track channels 1-12"}

-- the Rytm's factory per-track trig notes
Voices.FACTORY_NOTES = {36, 38, 40, 41, 43, 45, 47, 48, 50, 52, 53, 55}

-- C4 -- the sound's natural pitch when a track is played on its own channel
Voices.TRACK_NOTE = 60

-- where a layout puts voice v. `base` is the shared channel, which the
-- track-channel layout ignores because each track supplies its own.
function Voices.layout_address(layout, v, base)
  base = base or 1
  if layout == Voices.LAYOUT_TRACK then
    return v, Voices.TRACK_NOTE
  elseif layout == Voices.LAYOUT_FACTORY then
    return base, Voices.FACTORY_NOTES[v]
  end
  return base, v - 1
end

function Voices:new(args)
  local m = setmetatable({}, {__index = Voices})
  args = args or {}
  m.dev = args.dev              -- a midi device (or a stub in tests)
  m.pending = {}                -- note-offs waiting for the next flush
  m.sounding = {}               -- key -> {note, ch} for panic
  m.on_trig = args.on_trig      -- optional function(voice, vel) for display

  m.chan = {}
  m.note = {}
  local layout = args.layout or Voices.LAYOUT_SEQ
  local base = args.base_channel or 1
  for v = 1, Voices.COUNT do
    m.chan[v], m.note[v] = Voices.layout_address(layout, v, base)
  end
  return m
end

function Voices:set_address(v, ch, note)
  if v < 1 or v > Voices.COUNT then return end
  if ch then self.chan[v] = ch end
  if note then self.note[v] = note end
end

function Voices:address(v) return self.chan[v], self.note[v] end

function Voices:trig(v, vel)
  if v == nil or vel == nil or vel <= 0 then return end
  local ch, note = self:address(v)
  if ch == nil or note == nil then return end
  vel = math.floor(vel)
  if vel < 1 then vel = 1 elseif vel > 127 then vel = 127 end

  -- a voice retriggered before its own note-off has flushed would otherwise
  -- strand that note on: close the old one first.
  local key = ch * 1000 + note
  if self.sounding[key] then self:_off(key) end

  if self.dev then self.dev:note_on(note, vel, ch) end
  self.sounding[key] = {note = note, ch = ch}
  self.pending[#self.pending + 1] = key
  if self.on_trig then self.on_trig(v, vel) end
end

function Voices:_off(key)
  local n = self.sounding[key]
  if n == nil then return end
  if self.dev then self.dev:note_off(n.note, 0, n.ch) end
  self.sounding[key] = nil
end

-- called once per master tick: everything trigged before now gets released.
function Voices:flush()
  if #self.pending == 0 then return end
  for i = 1, #self.pending do self:_off(self.pending[i]) end
  -- reuse the table rather than allocating a fresh one every tick
  for i = #self.pending, 1, -1 do self.pending[i] = nil end
end

-- cut a voice that is still sounding, without waiting for the next flush.
-- used by the hat choke: the Rytm has no cross-track choke group of its
-- own, so a closed hat cutting an open one has to happen on this side.
function Voices:release_voice(v)
  local ch, note = self:address(v)
  if ch == nil or note == nil then return end
  self:_off(ch * 1000 + note)
end

function Voices:panic()
  for key in pairs(self.sounding) do self:_off(key) end
  for i = #self.pending, 1, -1 do self.pending[i] = nil end
  self.sounding = {}
end

return Voices
