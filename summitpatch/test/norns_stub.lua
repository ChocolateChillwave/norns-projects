-- a minimal stand-in for the norns runtime, enough to load and drive a
-- patch-editor script off-device: params, clock coroutines we can step by
-- hand, a screen recorder, and a MIDI device that records every message
-- and asserts on anything out of range.
--
-- adapted from segue/test/norns_stub.lua (see CLAUDE.md). identical copies
-- live in rytmpatch/test/ and summitpatch/test/ -- nothing in here names
-- either script, so the two copies stay byte-identical.
local S = {}

local HERE = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
S.DIR = HERE .. "/../"

---------------------------------------------------------------- util
util = {
  clamp = function(x, lo, hi)
    if x < lo then return lo elseif x > hi then return hi end
    return x
  end,
  round = function(x, q)
    q = q or 1
    return math.floor(x / q + 0.5) * q
  end,
  linlin = function(a, b, c, d, x)
    if x <= a then return c end
    if x >= b then return d end
    return (x - a) / (b - a) * (d - c) + c
  end,
  time = function() return S.now end,
  trim_string_to_width = function(s) return s end,
  file_exists = function(p) return S.files[p] ~= nil end,
}

-- util.time drives morph progress; tests step it explicitly instead of
-- waiting on a wall clock
S.now = 0
function S.advance_time(secs) S.now = S.now + secs end

S.files = {}
_path = {code = "/home/we/dust/code/", data = "/home/we/dust/data/"}
norns = {state = {data = "/home/we/dust/data/patchtest/"}}

---------------------------------------------------------------- tab
local function ser(v, out)
  local t = type(v)
  if t == "number" or t == "boolean" then
    out[#out + 1] = tostring(v)
  elseif t == "string" then
    out[#out + 1] = string.format("%q", v)
  elseif t == "table" then
    out[#out + 1] = "{"
    for k, val in pairs(v) do
      if type(k) == "number" then
        out[#out + 1] = "[" .. k .. "]="
      else
        out[#out + 1] = "[" .. string.format("%q", tostring(k)) .. "]="
      end
      ser(val, out)
      out[#out + 1] = ","
    end
    out[#out + 1] = "}"
  else
    error("tab.save cannot serialize a " .. t)
  end
end

tab = {
  save = function(data, path)
    local out = {}
    ser(data, out)
    S.files[path] = table.concat(out)
  end,
  load = function(path)
    local src = S.files[path]
    if src == nil then return nil end
    return load("return " .. src)()
  end,
  count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end,
}

---------------------------------------------------------------- params
local Param = {}
Param.__index = Param
function Param:get() return self.value end
function Param:string()
  if self.formatter then return tostring(self.formatter(self)) end
  if self.options then return tostring(self.options[self.value]) end
  return tostring(self.value)
end

params = {list = {}, by_id = {}, groups = {}, seps = {}}

local function add_param(p)
  setmetatable(p, Param)
  params.list[#params.list + 1] = p
  params.by_id[p.id] = p
end

-- norns' add_group(id, name, n) swallows exactly the next n params; once
-- it is full, later params are top-level again. the stub has to close the
-- group the same way or it silently over-counts.
local function count_into_group()
  local g = params.open_group
  if g == nil then return end
  g.added = g.added + 1
  if g.added >= g.n then params.open_group = nil end
end

function params:add_separator(id, name)
  self.seps[#self.seps + 1] = {id = id, name = name}
end
function params:add_group(id, name, n)
  self.groups[#self.groups + 1] = {id = id, name = name, n = n, added = 0}
  self.open_group = self.groups[#self.groups]
end
function params:add_number(id, name, min, max, default, formatter)
  add_param{id = id, name = name, min = min, max = max,
            value = default or min, formatter = formatter, kind = "number"}
  count_into_group()
end
function params:add_option(id, name, options, default)
  add_param{id = id, name = name, options = options, min = 1, max = #options,
            value = default or 1, kind = "option"}
  count_into_group()
end
function params:add_trigger(id, name)
  add_param{id = id, name = name, value = 0, kind = "trigger"}
  count_into_group()
end
function params:lookup_param(id)
  local p = self.by_id[id]
  if p == nil then error("no such param: " .. tostring(id)) end
  return p
end
function params:get(id) return self:lookup_param(id).value end
function params:string(id) return self:lookup_param(id):string() end
function params:set(id, v, silent)
  local p = self:lookup_param(id)
  if p.min then v = util.clamp(v, p.min, p.max) end
  p.value = v
  if p.action and not silent then p.action(v) end
end
function params:delta(id, d) self:set(id, self:lookup_param(id).value + d) end
function params:set_action(id, fn) self:lookup_param(id).action = fn end
function params:bang()
  for _, p in ipairs(self.list) do
    if p.action and p.kind ~= "trigger" then p.action(p.value) end
  end
end

---------------------------------------------------------------- clock
S.coros = {}
clock = {
  run = function(f, ...)
    local co = coroutine.create(f)
    S.coros[#S.coros + 1] = co
    local ok, err = coroutine.resume(co, ...)
    if not ok then error(err) end
    return #S.coros
  end,
  sync = function() coroutine.yield() end,
  sleep = function() coroutine.yield() end,
  cancel = function(id) if S.coros[id] then S.coros[id] = false end end,
  get_tempo = function() return 120 end,
  get_beats = function() return 0 end,
  get_beat_sec = function() return 0.5 end,
}

-- step one coroutine n times (clock.sleep/sync yield back to us)
function S.advance(id, n)
  local co = S.coros[id]
  if not co then return end
  for _ = 1, n or 1 do
    if coroutine.status(co) == "dead" then return end
    local ok, err = coroutine.resume(co)
    if not ok then error(err) end
  end
end

-- step every live coroutine
function S.advance_all(n)
  for i = 1, #S.coros do S.advance(i, n) end
end

---------------------------------------------------------------- screen
S.draws = 0
screen = setmetatable({}, {__index = function(_, k)
  if k == "text_extents" then return function(s) return #tostring(s) * 5 end end
  if k == "update" then return function() S.draws = S.draws + 1 end end
  return function() end
end})

---------------------------------------------------------------- midi
S.midi_sent = {}
S.midi_devs = {}
local function make_midi_dev(port)
  local d = {port = port, name = (port == 1) and "Elektron Analog Rytm MKII" or ("port " .. port)}
  function d:cc(c, v, ch)
    assert(c >= 0 and c <= 127, "cc number out of range: " .. tostring(c))
    assert(v >= 0 and v <= 127, "cc value out of range: " .. tostring(v))
    assert(v == math.floor(v), "cc value not an integer: " .. tostring(v))
    assert(ch >= 1 and ch <= 16, "channel out of range: " .. tostring(ch))
    S.midi_sent[#S.midi_sent + 1] = {t = "cc", cc = c, val = v, ch = ch, port = self.port}
  end
  function d:note_on(n, v, ch)
    assert(n >= 0 and n <= 127, "note out of range: " .. tostring(n))
    assert(v >= 1 and v <= 127, "velocity out of range: " .. tostring(v))
    assert(ch >= 1 and ch <= 16, "channel out of range: " .. tostring(ch))
    S.midi_sent[#S.midi_sent + 1] = {t = "on", note = n, vel = v, ch = ch, port = self.port}
  end
  function d:note_off(n, v, ch)
    S.midi_sent[#S.midi_sent + 1] = {t = "off", note = n, vel = v, ch = ch, port = self.port}
  end
  function d:pitchbend(v, ch)
    S.midi_sent[#S.midi_sent + 1] = {t = "pitchbend", val = v, ch = ch, port = self.port}
  end
  function d:channel_pressure(v, ch)
    S.midi_sent[#S.midi_sent + 1] = {t = "channel_pressure", val = v, ch = ch, port = self.port}
  end
  function d:key_pressure(n, v, ch)
    S.midi_sent[#S.midi_sent + 1] = {t = "key_pressure", note = n, val = v, ch = ch, port = self.port}
  end
  function d:send(msg)
    S.midi_sent[#S.midi_sent + 1] = {t = msg.type or "raw", port = self.port}
  end
  return d
end

midi = {
  connect = function(n) return S.midi_devs[n or 1] end,
  vports = {},
  -- the script receives whatever it passed to midi.to_msg; the stub hands
  -- messages straight through as tables
  to_msg = function(data) return data end,
}
for i = 1, 16 do
  S.midi_devs[i] = make_midi_dev(i)
  midi.vports[i] = S.midi_devs[i]
end

-- deliver an incoming message to whatever handler the script installed
function S.midi_in(port, msg)
  local dev = S.midi_devs[port]
  if dev.event then dev.event(msg) end
end

function S.sent_cc(cc, ch)
  local out = {}
  for _, m in ipairs(S.midi_sent) do
    if m.t == "cc" and m.cc == cc and (ch == nil or m.ch == ch) then out[#out + 1] = m.val end
  end
  return out
end

---------------------------------------------------------------- musicutil
local musicutil = {
  note_num_to_name = function(n, oct)
    local names = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
    local name = names[(n % 12) + 1]
    return oct and (name .. (math.floor(n / 12) - 2)) or name
  end,
}
local real_require = require
require = function(name)
  if name == "musicutil" then return musicutil end
  return real_require(name)
end

---------------------------------------------------------------- include
-- scripts include("<script>/lib/x"); drop that first segment and resolve
-- against this script folder, so both copies of the stub are identical
function include(path)
  return dofile(S.DIR .. path:gsub("^[^/]+/", "") .. ".lua")
end

---------------------------------------------------------------- misc
S.prints = {}
local real_print = print
function print(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
  S.prints[#S.prints + 1] = table.concat(parts, " ")
end
S.real_print = real_print

-- reach a local the script keeps in a closure, so a test can assert on
-- state the script never exposes
function S.upvalue(f, name)
  local i = 1
  while true do
    local n, v = debug.getupvalue(f, i)
    if n == nil then return nil end
    if n == name then return v end
    i = i + 1
  end
end

return S
