-- a minimal stand-in for the norns runtime, enough to load and drive a
-- script off-device: params (with controlspecs, formatters and actions),
-- clock coroutines we can step by hand, screen/grid/arc/midi recorders.
local S = {}

S.SEGUE_DIR = (arg[0]:match("^(.*)[/\\][^/\\]*$") or ".") .. "/../"

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
  -- a wall clock the test drives, not the real one. anything that fades,
  -- holds or rate-limits reads this, so those behaviours are testable
  -- instead of being whatever os.clock() happened to say.
  time = function() return S.now end,
  acronym = function(s)
    local out = ""
    for w in s:gmatch("%S+") do out = out .. w:sub(1, 1):upper() end
    return out
  end,
  file_exists = function(p) return S.files[p] ~= nil end,
}

S.now = 0        -- the virtual wall clock; tests move it forward
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
-- a norns Control keeps `raw` (0-1) as the real state and derives `value`
-- from it by mapping and quantizing to the step grid. that separation is
-- load-bearing: delta accumulates in raw, so repeated small nudges do
-- eventually cross a step boundary even though the quantized value sits
-- still in between. a stub that recomputed raw from the quantized value
-- would never move at all.
local function cs_map(cs, raw)
  local v = cs.minval + util.clamp(raw, 0, 1) * (cs.maxval - cs.minval)
  if cs.step and cs.step > 0 then
    v = util.round((v - cs.minval) / cs.step) * cs.step + cs.minval
  end
  return util.clamp(v, cs.minval, cs.maxval)
end

local function cs_unmap(cs, v)
  return util.clamp((v - cs.minval) / (cs.maxval - cs.minval), 0, 1)
end

function Param:get() return self.value end
function Param:set(v) self.value = v end
function Param:get_raw() return self.raw or 0 end
function Param:set_raw(r)
  local cs = self.controlspec
  if not cs then return end
  self.raw = util.clamp(r, 0, 1)
  self.value = cs_map(cs, self.raw)
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
function params:add_group(id, name, n)
  self.groups[#self.groups + 1] = {id = id, name = name, n = n, added = 0}
  self.open_group = self.groups[#self.groups]
end
function params:add_control(id, name, cs, formatter)
  local p = {id = id, name = name, controlspec = cs, value = cs.default,
             formatter = formatter, kind = "control"}
  p.raw = cs_unmap(cs, cs.default)
  add_param(p)
  count_into_group()
end
function params:add_trigger(id, name)
  add_param{id = id, name = name, value = 0, kind = "trigger"}
  count_into_group()
end
function params:add(t)
  local p = {id = t.id, name = t.name, kind = t.type, options = t.options,
             min = t.min, max = t.max, action = t.action}
  if t.type == "option" then
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
  if cs then
    -- go through raw, so a later delta carries on from where set left off
    p:set_raw(cs_unmap(cs, util.clamp(v, cs.minval, cs.maxval)))
    v = p.value
  else
    if p.min then v = util.clamp(v, p.min, p.max) end
    if p.options then v = util.clamp(v, 1, #p.options) end
    p.value = v
  end
  if p.action and not silent then p.action(p.value) end
end
-- norns' ParamSet:delta hands off to the param object, and Control:delta is
-- `set_raw(raw + d/100)` -- it moves 1/100 of the RANGE and ignores the
-- param's step entirely. that means a control with only a few steps needs
-- many clicks to move one of them (a 4-option control takes 33), which is
-- a real and very noticeable UI problem. an earlier version of this stub
-- moved by one step instead, which was kinder than the hardware and hid
-- the bug from every test in the suite -- so it models the quirk now.
--
-- a script can override the behaviour per param by assigning p.delta, the
-- same way it can on norns, and that path is honoured here too.
function params:delta(id, d)
  local p = self:lookup_param(id)
  if p.delta then
    p.delta(p, d)
    return
  end
  local cs = p.controlspec
  if cs then
    local before = p.value
    p:set_raw(p.raw + d / 100)
    if p.action and p.value ~= before then p.action(p.value) end
  else
    self:set(id, p.value + d)
  end
end
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
    if not ok then error("clock coroutine failed on start: " .. tostring(err)) end
    return #S.coros
  end,
  -- a virtual beat clock. clock.sync(d) waits for the next multiple of d
  -- beats, so from a boundary it advances exactly d -- which is what a
  -- script driving itself at a fixed subdivision sees. get_beats() reads
  -- it back, so code that derives its position from the shared timeline
  -- (rather than counting its own ticks) can be tested at all.
  sync = function(d)
    S.beats = S.beats + (d or 1)
    coroutine.yield()
  end,
  sleep = function() coroutine.yield() end, -- sleeping does not move beats
  cancel = function(id) if S.coros[id] then S.coros[id] = false end end,
  get_tempo = function() return 120 end,
  get_beats = function() return S.beats end,
  get_beat_sec = function() return 0.5 end,
  transport = {},
}
S.beats = 0

-- resume a clock coroutine n times, surfacing any error with its traceback
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
screen.move = function(x, y)
  assert(type(x) == "number" and type(y) == "number", "screen.move needs numbers")
  assert(x >= -1 and x <= 129, "screen.move x off screen: " .. x)
  assert(y >= -1 and y <= 65, "screen.move y off screen: " .. y)
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
    S.midi_sent[#S.midi_sent + 1] = {t = "on", note = n, vel = v, ch = ch}
  end
  function d:note_off(n, v, ch)
    S.midi_sent[#S.midi_sent + 1] = {t = "off", note = n, vel = v, ch = ch}
  end
  function d:send(msg)
    S.midi_sent[#S.midi_sent + 1] = {t = msg.type or "raw"}
  end
  function d:cc() end
  return d
end
midi = {connect = function(n) return make_midi_dev(n or 1) end, vports = {}}
for i = 1, 16 do
  midi.vports[i] = make_midi_dev(i)
  midi.vports[i].name = (i == 1) and "Elektron Analog Rytm MKII" or "none"
end

---------------------------------------------------------------- include
function include(path)
  local rel = path:gsub("^segue/", "")
  return dofile(S.SEGUE_DIR .. rel .. ".lua")
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
  -- norns' own clock params; the script reads clock_source to decide
  -- whether its pattern grid should lock to a shared timeline
  add_param{id = "clock_source", name = "clock source", value = 1,
            kind = "option", options = {"internal", "midi", "link", "crow"}}
  add_param{id = "clock_tempo", name = "tempo", value = 120, kind = "number"}
  for i = 1, 16 do
    add_param{id = "clock_midi_out_" .. i, name = "midi out " .. i,
              value = (i == 1) and 1 or 0, kind = "option"}
  end
end

return S
