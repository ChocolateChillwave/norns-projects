-- a minimal stand-in for the norns runtime, enough to load and drive a
-- script off-device: params (with controlspecs, formatters and actions),
-- clock coroutines, screen/grid/arc/midi recorders.
--
-- copied from segue/test/norns_stub.lua (see CLAUDE.md) and extended for
-- cascade, which needs timing rather than step counts: the clock here runs
-- on virtual seconds, so gate lengths, release tails and strum spacing can
-- be asserted to the millisecond without waiting for any of it.
local S = {}

S.SCRIPT_DIR = (arg[0]:match("^(.*)[/\\][^/\\]*$") or ".") .. "/../"
S.SEGUE_DIR = S.SCRIPT_DIR -- name kept so the shared stub's include still works

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
  -- virtual, not wall clock: note-off deadlines are compared against this
  time = function() return S.now end,
  file_exists = function(p) return S.files[p] ~= nil end,
}

S.files = {}
_path = {code = "/home/we/dust/code/", data = "/home/we/dust/data/"}
norns = {state = {data = "/home/we/dust/data/segue/"}}

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

---------------------------------------------------------------- controlspec
controlspec = {}
function controlspec.new(minval, maxval, warp, step, default, units)
  local cs = {minval = minval, maxval = maxval, warp = warp or "lin",
              step = step or 0, default = default or minval,
              units = units or ""}
  cs.quantum = (step and step > 0) and (step / (maxval - minval)) or 0.01
  return cs
end

---------------------------------------------------------------- params
local Param = {}
Param.__index = Param
function Param:get() return self.value end
function Param:set(v) self.value = v end
function Param:get_raw()
  local cs = self.controlspec
  if not cs then return 0 end
  return (self.value - cs.minval) / (cs.maxval - cs.minval)
end
function Param:string()
  if self.formatter then return tostring(self.formatter(self)) end
  if self.options then return tostring(self.options[self.value]) end
  return tostring(self.value)
end

params = {list = {}, by_id = {}, groups = {}, seps = {}}
S.param_order = params.list

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
-- norns takes either add_group(name, n) or add_group(id, name, n)
function params:add_group(id, name, n)
  if n == nil and type(name) == "number" then id, name, n = name, id, name end
  self.groups[#self.groups + 1] = {id = id, name = name, n = n, added = 0}
  self.open_group = self.groups[#self.groups]
end
function params:add_control(id, name, cs, formatter)
  add_param{id = id, name = name, controlspec = cs, value = cs.default,
            formatter = formatter, kind = "control"}
  count_into_group()
end
function params:add_trigger(id, name)
  add_param{id = id, name = name, value = 0, kind = "trigger"}
  count_into_group()
end
function params:add_option(id, name, options, default)
  add_param{id = id, name = name, options = options, value = default or 1,
            kind = "option"}
  count_into_group()
end
function params:add_number(id, name, min, max, default, formatter)
  add_param{id = id, name = name, min = min, max = max, value = default or min,
            formatter = formatter, kind = "number"}
  count_into_group()
end
function params:add_binary(id, name, behaviour, default)
  add_param{id = id, name = name, min = 0, max = 1, value = default or 0,
            kind = "binary"}
  count_into_group()
end
function params:add(t)
  local p = {id = t.id, name = t.name, kind = t.type, options = t.options,
             min = t.min, max = t.max, action = t.action,
             controlspec = t.controlspec, formatter = t.formatter}
  if t.type == "control" then
    -- a control param's default lives in its controlspec, not in `default`
    assert(t.controlspec, "control param " .. tostring(t.id) .. " has no controlspec")
    p.value = t.default or t.controlspec.default
  elseif t.type == "option" then
    p.value = t.default or 1
  elseif t.type == "number" then
    p.value = t.default or t.min
  else
    p.value = t.default or 0
  end
  add_param(p)
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
  local cs = p.controlspec
  if cs then v = util.clamp(v, cs.minval, cs.maxval) end
  if p.min then v = util.clamp(v, p.min, p.max) end
  if p.options then v = util.clamp(v, 1, #p.options) end
  p.value = v
  if p.action and not silent then p.action(v) end
end
function params:delta(id, d)
  local p = self:lookup_param(id)
  local step = (p.controlspec and p.controlspec.step) or 1
  if step == 0 then step = 0.01 end
  self:set(id, p.value + d * step)
end
function params:set_action(id, fn) self:lookup_param(id).action = fn end
function params:bang()
  for _, p in ipairs(self.list) do
    if p.action and p.kind ~= "trigger" then p.action(p.value) end
  end
end

---------------------------------------------------------------- musicutil
-- a stand-in for norns' lib/musicutil: enough scales to exercise the script,
-- with the behaviour that actually matters here -- generation stops at MIDI
-- 127, so a pool can come back shorter than asked for, which is the thing
-- scripts have to nil-guard against.
local SCALE_DEFS = {
  {name = "Major", intervals = {0, 2, 4, 5, 7, 9, 11}},
  {name = "Natural Minor", intervals = {0, 2, 3, 5, 7, 8, 10}},
  {name = "Harmonic Minor", intervals = {0, 2, 3, 5, 7, 8, 11}},
  {name = "Dorian", intervals = {0, 2, 3, 5, 7, 9, 10}},
  {name = "Phrygian", intervals = {0, 1, 3, 5, 7, 8, 10}},
  {name = "Lydian", intervals = {0, 2, 4, 6, 7, 9, 11}},
  {name = "Mixolydian", intervals = {0, 2, 4, 5, 7, 9, 10}},
  {name = "Locrian", intervals = {0, 1, 3, 5, 6, 8, 10}},
  {name = "Major Pentatonic", intervals = {0, 2, 4, 7, 9}},
  {name = "Minor Pentatonic", intervals = {0, 3, 5, 7, 10}},
  {name = "Blues", intervals = {0, 3, 5, 6, 7, 10}},
  {name = "Whole Tone", intervals = {0, 2, 4, 6, 8, 10}},
  {name = "Chromatic", intervals = {0,1,2,3,4,5,6,7,8,9,10,11}},
}

local MusicUtil = {SCALES = SCALE_DEFS}
S.MusicUtil = MusicUtil

local function resolve_scale(scale)
  if type(scale) == "number" then return SCALE_DEFS[scale] or SCALE_DEFS[1] end
  for _, s in ipairs(SCALE_DEFS) do
    if s.name:lower() == tostring(scale):lower() then return s end
  end
  return SCALE_DEFS[1]
end

function MusicUtil.generate_scale_of_length(root, scale, length)
  local def = resolve_scale(scale)
  local out = {}
  local i = 0
  while #out < length do
    local note = root + math.floor(i / #def.intervals) * 12
                      + def.intervals[(i % #def.intervals) + 1]
    if note > 127 then break end
    out[#out + 1] = note
    i = i + 1
  end
  return out
end

function MusicUtil.generate_scale(root, scale, octaves)
  local def = resolve_scale(scale)
  return MusicUtil.generate_scale_of_length(root, scale, #def.intervals * (octaves or 1) + 1)
end

local NAMES = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}
function MusicUtil.note_num_to_name(n, with_octave)
  local name = NAMES[(n % 12) + 1]
  if with_octave then name = name .. (math.floor(n / 12) - 1) end
  return name
end

package.preload["musicutil"] = function() return MusicUtil end

---------------------------------------------------------------- clock
-- virtual time, modelled on norns' core/clock.lua:
--   * ids come from a counter that only ever increments -- norns never
--     reuses them, so neither does this
--   * clock.cancel nils the thread but leaves any wake already queued for
--     it, and resuming that nil thread raises the same error the device
--     does ("bad argument #1 to 'resume' (thread expected)"). that race is
--     a real crash cascade hit on hardware, so the stub reproduces it
--     rather than hiding it
S.now = 0
S.coros = {}          -- id -> coroutine (nil once finished or cancelled)
S.wakes = {}          -- id -> virtual time it should next resume
S.cancels = 0
S.tempo = 120
local next_clock_id = 1

clock = {
  run = function(f, ...)
    local id = next_clock_id
    next_clock_id = next_clock_id + 1
    local co = coroutine.create(f)
    S.coros[id] = co
    local ok, dur = coroutine.resume(co, ...)
    if not ok then error("clock coroutine failed on start: " .. tostring(dur)) end
    if coroutine.status(co) == "dead" then S.coros[id] = nil
    else S.wakes[id] = S.now + (dur or 0) end
    return id
  end,
  sleep = function(t) coroutine.yield(t or 0) end,
  sync = function(beats)
    -- wait to the next multiple of `beats`, like the real transport grid
    local period = (beats or 1) * (60 / S.tempo)
    local nxt = (math.floor(S.now / period + 1e-9) + 1) * period
    coroutine.yield(nxt - S.now)
  end,
  cancel = function(id)
    S.cancels = S.cancels + 1
    S.coros[id] = nil
  end,
  get_tempo = function() return S.tempo end,
  get_beats = function() return S.now / (60 / S.tempo) end,
  get_beat_sec = function() return 60 / S.tempo end,
  transport = {},
}

-- run every clock forward to virtual time `to`
function S.run_until(to)
  while true do
    local soonest, id = math.huge, nil
    for i, w in pairs(S.wakes) do
      if w < soonest then soonest, id = w, i end
    end
    if id == nil or soonest > to + 1e-9 then S.now = to return end

    S.now = math.max(S.now, soonest)
    S.wakes[id] = nil
    local co = S.coros[id]
    if co == nil then
      error("bad argument #1 to 'resume' (thread expected) -- clock " .. id ..
            " was cancelled with a wake still queued")
    end
    local ok, dur = coroutine.resume(co)
    if not ok then error("clock coroutine " .. id .. " failed: " .. tostring(dur)) end
    if coroutine.status(co) == "dead" then S.coros[id] = nil
    else S.wakes[id] = S.now + (dur or 0) end
  end
end

function S.run_for(seconds) S.run_until(S.now + seconds) end

-- resume a clock coroutine n times, ignoring virtual time (kept for the
-- shared stub's step-counting style)
function S.advance(id, n)
  for i = 1, n do
    local co = S.coros[id]
    if not co or coroutine.status(co) == "dead" then
      error("clock coroutine " .. id .. " is not running (iteration " .. i .. ")")
    end
    local ok, err = coroutine.resume(co)
    if not ok then
      error("clock coroutine " .. id .. " failed on iteration " .. i ..
            ": " .. tostring(err))
    end
  end
end

---------------------------------------------------------------- metro
S.metros = {}
metro = {
  init = function()
    local m = {time = 1, event = nil}
    function m:start() self.running = true end
    function m:stop() self.running = false end
    S.metros[#S.metros + 1] = m
    return m
  end,
}

---------------------------------------------------------------- screen
S.draws = 0
screen = {}
for _, name in ipairs({"clear", "update", "fill", "stroke", "aa", "level",
                       "line_width", "close", "circle", "arc", "curve",
                       "font_face", "font_size", "pixel", "display_image",
                       "blend_mode"}) do
  screen[name] = function() end
end
S.moves = {}
screen.move = function(x, y)
  assert(type(x) == "number" and type(y) == "number", "screen.move needs numbers")
  assert(x == x and y == y, "screen.move got a NaN")
  assert(x >= -1 and x <= 129, "screen.move x off screen: " .. x)
  assert(y >= -1 and y <= 65, "screen.move y off screen: " .. y)
  S.moves[#S.moves + 1] = {x = x, y = y}
end
screen.rect = function(x, y, w, h)
  assert(type(x) == "number" and type(y) == "number", "screen.rect needs numbers")
  assert(w >= 0 and h >= 0, "screen.rect negative size: " .. w .. "x" .. h)
  assert(x >= -1 and x + w <= 129, "screen.rect runs off the right edge: x=" ..
         x .. " w=" .. w)
  assert(y >= -1 and y + h <= 65, "screen.rect runs off the bottom: y=" ..
         y .. " h=" .. h)
end
screen.text = function(s)
  S.draws = S.draws + 1
  assert(s ~= nil, "screen.text(nil)")
  assert(not tostring(s):find("nil"), "screen.text drew a nil: " .. tostring(s))
end
screen.text_right = screen.text
screen.text_center = screen.text
screen.line = function(x, y)
  assert(type(x) == "number" and type(y) == "number", "screen.line needs numbers")
  assert(x == x and y == y, "screen.line got a NaN")
  assert(x >= -1 and x <= 129, "screen.line x off screen: " .. x)
  assert(y >= -1 and y <= 65, "screen.line y off screen: " .. y)
  S.lines = (S.lines or 0) + 1
end
screen.load_png = function() return nil end

---------------------------------------------------------------- grid / arc
S.grid_leds = {}
local function make_grid(cols, rows)
  local g = {cols = cols, rows = rows, device = (cols > 0) and {} or nil}
  function g:all(v) end
  function g:led(x, y, v)
    assert(x >= 1 and x <= self.cols, "grid led x out of range: " .. x ..
           " (cols " .. self.cols .. ")")
    assert(y >= 1 and y <= self.rows, "grid led y out of range: " .. y)
    assert(v >= 0 and v <= 15, "grid led level out of range: " .. tostring(v))
    S.grid_leds[#S.grid_leds + 1] = {x, y, v}
  end
  function g:refresh() end
  return g
end
S.make_grid = make_grid
S.grid_cols = {16, 0} -- port 1 is a 128, port 2 unplugged, by default
S.grids = {}
grid = {connect = function(n)
  n = n or 1
  local cols = S.grid_cols[n] or 0
  local g = make_grid(cols, cols > 0 and 8 or 0)
  S.grids[n] = g
  return g
end}

-- fire a physical grid press at the handler the script installed
function S.grid_key(port, x, y, z)
  local g = S.grids[port]
  assert(g, "no grid connected on port " .. port)
  assert(g.key, "nothing is listening for keys on port " .. port)
  g.key(x, y, z)
end

S.arc_leds = {}
S.arc_connected = true
arc = {connect = function()
  local a = {device = S.arc_connected and {} or nil}
  function a:all(v) end
  function a:led(ring, led, level)
    assert(ring >= 1 and ring <= 4, "arc ring out of range: " .. ring)
    assert(led >= 1 and led <= 64, "arc led out of range: " .. led)
    assert(level >= 0 and level <= 15, "arc level out of range: " .. level)
    S.arc_leds[#S.arc_leds + 1] = {ring, led, level}
  end
  function a:segment() end
  function a:refresh() end
  S.arc_obj = a
  return a
end}

---------------------------------------------------------------- midi
S.midi_sent = {}
local function make_midi_dev(port)
  local d = {port = port}
  function d:note_on(n, v, ch)
    assert(n >= 0 and n <= 127, "note out of range: " .. n)
    assert(v >= 1 and v <= 127, "velocity out of range: " .. v)
    assert(ch >= 1 and ch <= 16, "channel out of range: " .. ch)
    S.midi_sent[#S.midi_sent + 1] = {t = "on", note = n, vel = v, ch = ch, time = S.now}
  end
  function d:note_off(n, v, ch)
    S.midi_sent[#S.midi_sent + 1] = {t = "off", note = n, vel = v, ch = ch, time = S.now}
  end
  function d:send(msg)
    S.midi_sent[#S.midi_sent + 1] = {t = msg.type or "raw"}
  end
  function d:cc(c, v, ch)
    S.midi_sent[#S.midi_sent + 1] = {t = "cc", cc = c, val = v, ch = ch, time = S.now}
  end
  return d
end
midi = {connect = function(n) return make_midi_dev(n or 1) end, vports = {}}
for i = 1, 16 do midi.vports[i] = make_midi_dev(i) end

function midi.to_msg(d)
  local status = d[1] or 0
  local kind = "other"
  if status >= 0x90 and status < 0xA0 then kind = "note_on"
  elseif status >= 0x80 and status < 0x90 then kind = "note_off" end
  return {type = kind, note = d[2], vel = d[3], ch = (status % 16) + 1}
end

-- fire an incoming MIDI note at whatever handler the script installed
function S.midi_in(dev, kind, note, vel)
  assert(dev and dev.event, "nothing is listening for MIDI in")
  dev.event({(kind == "note_on") and 0x90 or 0x80, note, vel or 100})
end

---------------------------------------------------------------- crow
-- crow is reached over USB and Just Friends over crow's ii bus; both just
-- record what was sent. S.crow_present = false stands in for crow being
-- unplugged, which scripts have to survive.
S.crow_sent = {}
S.crow_present = true

local function crow_record(fn)
  return function(...)
    if not S.crow_present then return end
    S.crow_sent[#S.crow_sent + 1] = {fn = fn, args = {...}, time = S.now}
  end
end

crow = {ii = {jf = {}}, output = {}}
for _, fn in ipairs({"mode", "play_voice", "play_note", "trigger", "run_mode",
                     "run", "transpose", "vtrigger", "tick", "god_mode",
                     "retune", "quantize"}) do
  crow.ii.jf[fn] = crow_record("jf." .. fn)
end
for i = 1, 4 do
  crow.output[i] = setmetatable({}, {
    __newindex = function(t, k, v) crow_record("output." .. i .. "." .. k)(v) end,
    __call = function() crow_record("output." .. i .. "()")() end,
  })
end

-- every crow call of one kind, as a list of argument tables
function S.crow_calls(fn)
  local out = {}
  for _, c in ipairs(S.crow_sent) do
    if c.fn == fn then out[#out + 1] = c.args end
  end
  return out
end

---------------------------------------------------------------- include
-- scripts include their own libs by full dust path ("cascade/lib/chords"),
-- so drop the leading script-folder segment and resolve from this script's
-- own directory
function include(path)
  local rel = path:gsub("^[^/]+/", "")
  return dofile(S.SCRIPT_DIR .. rel .. ".lua")
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
-- state the script never exposes (the lanes table, mainly)
function S.upvalue(f, name)
  local i = 1
  while true do
    local n, v = debug.getupvalue(f, i)
    if n == nil then return nil end
    if n == name then return v end
    i = i + 1
  end
end

function S.get_lanes() return S.upvalue(redraw, "lanes") end

-- norns provides clock_midi_out_N system params; the script reads them to
-- decide who to send transport to
function S.add_system_params()
  for i = 1, 16 do
    add_param{id = "clock_midi_out_" .. i, name = "midi out " .. i,
              value = (i == 1) and 1 or 0, kind = "option"}
  end
end

return S
