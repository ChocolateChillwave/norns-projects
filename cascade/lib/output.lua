-- output.lua
-- where notes actually go: MIDI, Just Friends over crow's ii bus, or both.
--
-- shaped deliberately like a norns midi device -- note_on/note_off/cc with
-- the same arguments -- so the strum engine holds "a device" and never
-- learns that anything else exists. nothing in strum.lua changed to add
-- Just Friends.
--
-- Just Friends has six voices, which is a good fit for an instrument whose
-- screen draws six strings: each sounding note is handed a voice and gets it
-- back when it stops. past six, the oldest voice is taken, since a strum
-- that runs long has already moved on from its first note.
--
-- pitch is 1V/oct with middle C at 0V, the usual crow convention.
--
-- two things here are guesses that hardware will settle, both flagged in
-- NOTES.md: whether "sustain" wants level 0 as its note-off (jf.trigger
-- exists as the alternative, but it carries no pitch, and relying on JF
-- remembering the last one is the sort of assumption that's wrong), and
-- what level range sounds right.
local Output = {}

local JF_VOICES = 6
local MIDDLE_C = 60

-- crow is absent more often than it's present -- unplugged, or the script
-- running on a norns with nothing attached -- so every ii call goes through
-- here rather than assuming the module is there
local function jf_send(fn, ...)
  if crow == nil or crow.ii == nil or crow.ii.jf == nil then return end
  local f = crow.ii.jf[fn]
  if f == nil then return end
  f(...)
end

function Output.new()
  local m = setmetatable({}, {__index = Output})
  m.cfg = {midi = true, jf = false, device = nil, jf_level = 5, jf_sustain = false}
  m.voice_note = {}   -- jf voice -> the note holding it
  m.voice_age = {}    -- jf voice -> when it was taken, for stealing
  m.age = 0
  m.jf_on = false     -- whether JF has been handed over to ii
  return m
end

-- called whenever the output params change. taking JF over and giving it
-- back are edge-triggered: mode(1) latches, so repeating it every param
-- change would be noise on the bus.
function Output:configure(cfg)
  self.cfg = cfg
  if cfg.jf and not self.jf_on then
    self.jf_on = true
    jf_send("mode", 1)
  elseif not cfg.jf and self.jf_on then
    self:_jf_stop_all()
    self.jf_on = false
    jf_send("mode", 0)
  end
end

-- hand Just Friends back on the way out, or it stays in ii mode and ignores
-- its own front panel until something else claims it
function Output:shutdown()
  if self.jf_on then
    self:_jf_stop_all()
    self.jf_on = false
    jf_send("mode", 0)
  end
end

function Output:note_on(note, velocity, channel)
  local cfg = self.cfg
  if cfg.midi and cfg.device then cfg.device:note_on(note, velocity, channel) end
  if cfg.jf then self:_jf_on(note, velocity) end
end

function Output:note_off(note, velocity, channel)
  local cfg = self.cfg
  if cfg.midi and cfg.device then cfg.device:note_off(note, velocity or 0, channel) end
  if cfg.jf then self:_jf_off(note) end
end

-- the engine's panic sends CC 123 per channel; JF's equivalent is releasing
-- every voice it's holding
function Output:cc(number, value, channel)
  local cfg = self.cfg
  if cfg.midi and cfg.device then cfg.device:cc(number, value, channel) end
  if cfg.jf and number == 123 then self:_jf_stop_all() end
end

-- ============================================================
-- Just Friends
-- ============================================================

function Output:_jf_alloc(note)
  for v = 1, JF_VOICES do
    if self.voice_note[v] == note then return v end   -- re-striking the same pitch
  end
  for v = 1, JF_VOICES do
    if self.voice_note[v] == nil then return v end
  end
  local oldest, age = 1, math.huge
  for v = 1, JF_VOICES do
    if (self.voice_age[v] or 0) < age then oldest, age = v, self.voice_age[v] or 0 end
  end
  return oldest
end

function Output:_jf_on(note, velocity)
  local voice = self:_jf_alloc(note)
  self.age = self.age + 1
  self.voice_note[voice] = note
  self.voice_age[voice] = self.age

  local volts = (note - MIDDLE_C) / 12
  local level = util.clamp((velocity or 100) / 127, 0, 1) * self.cfg.jf_level
  jf_send("play_voice", voice, volts, level)
end

function Output:_jf_off(note)
  for v = 1, JF_VOICES do
    if self.voice_note[v] == note then
      -- in pluck mode JF's own envelope ends the note, so there's nothing
      -- to send; the voice just becomes free again
      if self.cfg.jf_sustain then
        jf_send("play_voice", v, (note - MIDDLE_C) / 12, 0)
      end
      self.voice_note[v] = nil
      self.voice_age[v] = nil
      return
    end
  end
end

function Output:_jf_stop_all()
  for v = 1, JF_VOICES do
    if self.voice_note[v] ~= nil then
      jf_send("play_voice", v, (self.voice_note[v] - MIDDLE_C) / 12, 0)
      self.voice_note[v] = nil
      self.voice_age[v] = nil
    end
  end
end

-- for tests and display: which voices are in use
function Output:jf_voices()
  local out = {}
  for v = 1, JF_VOICES do out[v] = self.voice_note[v] end
  return out
end

return Output
