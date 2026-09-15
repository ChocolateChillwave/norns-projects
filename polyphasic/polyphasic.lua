-- polyphasic v0.1.0
--
-- a 4-track polymetric MIDI sequencer, adapted from pitter-patter (schollz)
-- https://llllllll.co/t/pitter-patter
--
-- MIDI out only: no engine.name, no SuperCollider synthesis, no nb voice
-- routing. each track addresses its own MIDI device + channel directly
-- (see the TRACK N params), and every grid-triggered note draws its
-- velocity from one shared lo/hi range under the "polyphasic" params group.
--
--    ▼ instructions below ▼
--
-- E1: change track
-- E2: change direction
-- E3: change note pool
-- K1+E1: change midi out device
-- K1+E2: change clock division
-- K1+E3: change length
-- K1: shift
-- K2: mute
-- K3: play/stop
-- K1+K2: clear current view
-- K1+K3: clear all
--
GridLib = include("polyphasic/lib/ggrid")
Sequence = include("polyphasic/lib/sequence")
Display = include("polyphasic/lib/display")
lattice = require("lattice")
if not string.find(package.cpath, "/home/we/dust/code/polyphasic/lib/") then
  package.cpath = package.cpath .. ";/home/we/dust/code/polyphasic/lib/?.so"
end
json = require("cjson") -- NOTE: needs cjson's .so present in polyphasic/lib/
                         -- (pitter-patter ships it via a git submodule) or
                         -- pattern save/load below will fail to require it.

sequencers = {}
last_cpu = 0

-- ppqn=96 divides evenly by 2 and 3, so the triplet-family divisions below
-- are clock-accurate with no jitter. quintuplet/septuplet divisions would
-- need a higher ppqn (more clock overhead) and aren't included here.
local divisions = {4, 2, 1, 2/3, 1/2, 1/3, 1/4, 1/6, 1/8, 1/12, 1/16, 1/24, 1/32}
local divisions_strings = {
  "4 beats", "2 beats", "1 beat", "2/3 (triplet)", "1/2", "1/3 (triplet)",
  "1/4", "1/6 (triplet)", "1/8", "1/12 (triplet)", "1/16", "1/24 (triplet)", "1/32"
}

local function add_control(id, name, min, max, default, unit)
  unit = unit or ""
  params:add{
    type = "control",
    id = id,
    name = name,
    controlspec = controlspec.new(min, max, "lin", 1, default, unit, 1 / (max - min))
  }
end

-- shared by all four tracks: every grid-triggered note draws a random
-- velocity from this range. external MIDI input notes carry their own
-- real velocity and never call this.
local function random_velocity()
  return math.random(params:get("vel_lo"), params:get("vel_hi"))
end

local function make_on_note(track_id)
  return function(note_index, velocity)
    local row = (note_index - 1) % Display.rows
    Display.trigger(track_id, row, velocity)
  end
end

function init()
  for i = 1, 4 do
    sequencers[i] = Sequence:new{
      id = i,
      divisions = divisions,
      divisions_strings = divisions_strings,
      get_velocity = random_velocity,
      on_note = make_on_note(i)
    }
  end

  params_main()

  params:add_group("polyphasic", 2)
  add_control("vel_lo", "velocity lo", 1, 127, 40)
  add_control("vel_hi", "velocity hi", 1, 127, 110)
  params:set_action("vel_lo", function(v) if v > params:get("vel_hi") then params:set("vel_hi", v) end end)
  params:set_action("vel_hi", function(v) if v < params:get("vel_lo") then params:set("vel_lo", v) end end)

  grid_ = GridLib:new()
  Display.init(4)

  params:bang()

  local seq_clock = lattice:new{ppqn = 96}
  for _, division in ipairs(divisions) do
    local beat = 1
    seq_clock:new_sprocket({
      action = function(t)
        if params:get("main_play") == 1 then
          for i = 1, 4 do sequencers[i]:update(division, beat) end
          beat = beat + 1
        end
      end,
      division = division
    })
  end

  cpu_tracker = poll.set("cpu_avg")
  cpu_tracker.callback = function(x)
    if x > 0 then last_cpu = x end
  end
  cpu_tracker:start()

  clock.run(function()
    clock.sleep(0.1)
    seq_clock:hard_restart()
  end)
  clock.run(function()
    while true do
      clock.sleep(1 / 15)
      redraw()
    end
  end)
end

local is_shift = false

function enc(k, d)
  if k == 1 then
    if is_shift then
      sequencers[params:get("main_sequence")]:delta_param("midi_out_device", d)
    else
      params:delta("main_sequence", d)
    end
  elseif k == 2 then
    if is_shift then
      sequencers[params:get("main_sequence")]:delta_param("division", d)
    elseif d == 1 or d == -1 then
      if params:get("main_play") == 1 then
        sequencers[params:get("main_sequence")]:delta_param("direction", d)
      else
        sequencers[params:get("main_sequence")]:set_param("direction", d < 0 and 1 or 4)
        sequencers[params:get("main_sequence")]:update(divisions[sequencers[params:get("main_sequence")]:get_param("division")])
      end
    end
  elseif k == 3 then
    if is_shift then
      sequencers[params:get("main_sequence")]:delta_param("limit", d)
    else
      sequencers[params:get("main_sequence")].note_offset = sequencers[params:get("main_sequence")].note_offset + d
    end
  end
end

function key(k, z)
  if k == 1 then
    is_shift = z == 1
  elseif z == 1 and k == 2 then
    if not is_shift then
      sequencers[params:get("main_sequence")]:set_param("mute",
        sequencers[params:get("main_sequence")]:get_param("mute") == 0 and 1 or 0)
    else
      sequencers[params:get("main_sequence")]:clear_visible()
    end
  elseif z == 1 and k == 3 then
    if is_shift then
      sequencers[params:get("main_sequence")]:clear()
    else
      params:set("main_play", params:get("main_play") == 0 and 1 or 0)
    end
  end
end

function redraw()
  screen.clear()
  Display.draw(4)

  local current = sequencers[params:get("main_sequence")]

  screen.level(4)
  screen.move(0, 7)
  screen.text("track " .. params:get("main_sequence") .. (current:get_param("mute") == 1 and " * muted" or ""))

  screen.level(4)
  screen.move(128, 7)
  screen.text_right(string.format("%2.0f", last_cpu) .. "%")

  screen.level(2)
  screen.move(0, 64 - 2)
  screen.text(params:string("main_play") .. current:get_param_str("direction") .. " " .. current:get_param_str("division"))

  screen.update()
end

function rerun()
  norns.script.load(norns.state.script)
end

function cleanup()
end

function table.reverse(t)
  local len = #t
  for i = len - 1, 1, -1 do t[len] = table.remove(t, i) end
end

function params_main()
  midi_connections = {}
  local midi_devices = {"any", "none"}
  local midi_channels = {"all"}
  for i = 1, 16 do table.insert(midi_channels, i) end
  for j, dev in pairs(midi.devices) do
    if dev.port ~= nil then table.insert(midi_devices, dev.name) end
  end

  local params_menu = {
    {
      id="sequence", name="track select", min=1, max=4, exp=false, div=1, default=1,
      formatter=function(param) return string.format("%d", param:get()) end,
      action=function(v) grid_.sequencer = sequencers[v] end
    }, {
      id="play", name="play", min=0, max=1, exp=false, div=1, default=1,
      formatter=function(param) return param:get() == 0 and "" or "play " end,
      action=function(v) if v == 0 then for i = 1, 4 do sequencers[i]:reset_timer() end end end
    }, {
      id="midi_input", name="midi input device", min=1, max=#midi_devices, exp=false, div=1, default=1,
      formatter=function(param) return midi_devices[param:get()] end
    }, {
      id="midi_channel", name="midi channel", min=1, max=17, exp=false, div=1, default=1,
      formatter=function(param) return midi_channels[param:get()] end
    }
  }
  for _, pram in ipairs(params_menu) do
    params:add{
      type="control", id="main_" .. pram.id, name=pram.name,
      controlspec=controlspec.new(pram.min, pram.max, pram.exp and "exp" or "lin", pram.div, pram.default,
                                  pram.unit or "", pram.div / (pram.max - pram.min)),
      formatter=pram.formatter
    }
    if pram.hide then params:hide(pram.id) end
    if pram.action then params:set_action("main_" .. pram.id, pram.action) end
  end
  for j, dev in pairs(midi.devices) do
    if dev.port ~= nil then
      local conn = midi.connect(dev.port)
      conn.event = function(data)
        local d = midi.to_msg(data)
        if d.type == "clock" then return end
        if params:get("main_midi_input") == 2 then do return end end
        if dev.name ~= midi_devices[params:get("main_midi_input")] and params:get("main_midi_input") > 2 then
          do return end
        end
        if d.ch ~= nil and d.ch ~= midi_channels[params:get("main_midi_channel")] and params:get("main_midi_channel") >
            2 then do return end end
        if d.type == 'start' or d.type == 'continue' then
          params:set("main_play", 1)
        elseif d.type == "stop" then
          params:set("main_play", 0)
        end
        if d.type == "note_on" then
          sequencers[params:get("main_sequence")]:toggle_from_note(d.note)
        end
      end
    end
  end

  params.action_write = function(filename, name)
    local data = {}
    for i = 1, 4 do data["sequence_" .. i] = sequencers[i]:marshal() end
    filename = filename .. ".json"
    local file = io.open(filename, "w+")
    io.output(file)
    io.write(json.encode(data))
    io.close(file)
  end

  params.action_read = function(filename, silent)
    filename = filename .. ".json"
    if not util.file_exists(filename) then do return end end
    local f = io.open(filename, "rb")
    local content = f:read("*all")
    f:close()
    if content == nil then do return end end
    local data = json.decode(content)
    if data == nil then do return end end
    for i = 1, 4 do sequencers[i]:unmarshal(data["sequence_" .. i]) end
  end
end