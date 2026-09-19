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
-- MIDI clock out: enable per-port under PARAMETERS > CLOCK > "midi out" --
-- that's a norns system feature (streams continuous clock ticks on its
-- own), not something this script sets up. This script's own play/stop
-- additionally sends MIDI start/stop to those same ports, so an external
-- arpeggiator's transport follows along, not just its tempo.
--
-- display: "Halide" -- glowing per-track orbs over a faint dot-matrix
-- field (see lib/display.lua and NOTES.md for the other concepts tried,
-- including "Vanishing" -- a streetlamp-per-track scene -- which shipped
-- briefly and was reverted for feeling convoluted next to this one).
-- track number (top-left), bpm (top-right), and cpu% (top-right) are each
-- independently hideable via PARAMETERS > DISPLAY; the bottom line shows
-- the arc's footer when one's connected, or falls back to
-- play/direction/division when it isn't.
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
-- arc (optional): a paged 4-ring editor for whichever track is currently
-- selected (E1). press the arc's own pushbutton to cycle pages: PLAY
-- (division/direction/limit/probability), MIX (mute/poly/velocity range),
-- RANGE (note lo/hi, scale, root), PERFORMANCE (track select, clear,
-- randomize, evolve). K1+turn a ring applies that change to all 4 tracks
-- at once instead of just the selected one (footer shows "[ALL]" while
-- held). arc sensitivity/brightness/position live in PARAMETERS > ARC.
-- MIDI device/channel routing isn't on the arc -- set it up once in
-- PARAMETERS or via a pset.
--
GridLib = include("polyphasic/lib/ggrid")
Sequence = include("polyphasic/lib/sequence")
Display = include("polyphasic/lib/display")
lattice = require("lattice")

sequencers = {}
last_cpu = 0

-- shared with enc()/key() below (K1 = shift) and with the arc (K1 held
-- while turning a ring broadcasts it to all 4 tracks -- see all_track_fields)
local is_shift = false

-- ppqn=96 divides evenly by 2 and 3, so the triplet-family divisions below
-- are clock-accurate with no jitter. quintuplet/septuplet divisions would
-- need a higher ppqn (more clock overhead) and aren't included here.
local divisions = {4, 2, 1, 2/3, 1/2, 1/3, 1/4, 1/6, 1/8, 1/12, 1/16, 1/24, 1/32}
local divisions_strings = {
  "4 beats", "2 beats", "1 beat", "2/3", "1/2", "1/3",
  "1/4", "1/6", "1/8", "1/12", "1/16", "1/24", "1/32"
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

-- shared by all four tracks: every grid-triggered note draws its velocity
-- from this range, shaped by the global vel_curve. external MIDI input
-- notes carry their own real velocity and never call this.
--
-- curve position is per-track: it reads the calling sequence's own current
-- step and limit, so each track ramps/cycles across its own loop length
-- rather than sharing one global phase -- "random" (the original behavior)
-- ignores step/limit entirely, same as before this existed.
local function curve_velocity(seq)
  local lo, hi = params:get("vel_lo"), params:get("vel_hi")
  local curve = params:get("vel_curve")
  if curve == 1 then return math.random(lo, hi) end -- random

  local limit = seq:get_param("limit")
  local phase = limit > 1 and (seq.step_last - 1) / (limit - 1) or 0
  local t
  if curve == 2 then t = phase                              -- ramp up
  elseif curve == 3 then t = 1 - phase                       -- ramp down
  elseif curve == 4 then t = 1 - math.abs(2 * phase - 1)     -- triangle
  elseif curve == 5 then t = math.sin(phase * math.pi)       -- sine (smoothed triangle)
  else t = 0.5 end
  return util.round(lo + t * (hi - lo))
end

local function make_on_note(track_id)
  return function(note_index, velocity)
    local row = (note_index - 1) % Display.rows
    Display.trigger(track_id, row, velocity)
  end
end

-- arc: a paged 4-ring editor for the currently selected track's params
-- (main_sequence -- the same "current track" E1/E2/E3 already use). the
-- generic paging/rendering/sensitivity machinery lives in lib/garc.lua
-- (reusable across future scripts); this table is just polyphasic's page
-- layout, with a per-track ring's `id` as a resolver function so it always
-- points at whichever track is currently selected.
GArc = include("polyphasic/lib/garc")

local function track_field(field)
  return function() return "sequence" .. params:get("main_sequence") .. "_" .. field end
end

-- hold K1 while turning an arc ring to apply the change to all 4 tracks at
-- once instead of just the selected one (see is_shift below) -- lets e.g.
-- scale get set the same on every track in one turn instead of 4
local function all_track_fields(field)
  return function()
    local ids = {}
    for i = 1, 4 do table.insert(ids, "sequence" .. i .. "_" .. field) end
    return ids
  end
end

local ARC_PAGES = {
  {
    name = "PLAY",
    rings = {
      {label = "division", id = track_field("division"), all_ids = all_track_fields("division")},
      {label = "direction", id = track_field("direction"), all_ids = all_track_fields("direction")},
      {label = "limit", id = track_field("limit"), all_ids = all_track_fields("limit")},
      {label = "prob", id = track_field("probability"), all_ids = all_track_fields("probability")}
    }
  }, {
    name = "MIX",
    rings = {
      {label = "mute", id = track_field("mute"), all_ids = all_track_fields("mute")},
      {label = "poly", id = track_field("poly"), all_ids = all_track_fields("poly")},
      {label = "vel lo", id = "vel_lo"},
      {label = "vel hi", id = "vel_hi"}
    }
  }, {
    name = "RANGE",
    rings = {
      {label = "note lo", id = track_field("note_lo"), all_ids = all_track_fields("note_lo")},
      {label = "note hi", id = track_field("note_hi"), all_ids = all_track_fields("note_hi")},
      {label = "scale", id = track_field("scale"), all_ids = all_track_fields("scale")},
      {label = "root", id = track_field("root_note"), all_ids = all_track_fields("root_note")}
    }
  }, {
    name = "PERF", -- "PERFORMANCE" ate too much of the arc footer's character budget
    rings = {
      {label = "track", id = "main_sequence"}, -- global: changes which track every other page's rings act on
      {label = "clear", id = track_field("clear"), all_ids = all_track_fields("clear")},
      {label = "randomize", id = track_field("randomize"), all_ids = all_track_fields("randomize")},
      {label = "evolve", id = track_field("evolve"), all_ids = all_track_fields("evolve")}
    }
  }
  -- MIDI device/channel routing intentionally left off the arc -- that's a
  -- per-setup thing to configure once (or via a pset), not something worth
  -- live arc access.
}

function init()
  for i = 1, 4 do
    sequencers[i] = Sequence:new{
      id = i,
      divisions = divisions,
      divisions_strings = divisions_strings,
      get_velocity = curve_velocity,
      on_note = make_on_note(i)
    }
  end

  params_main()

  params:add_group("DISPLAY", 3)
  for _, p in ipairs({
    {id = "show_track", name = "show track number"},
    {id = "show_bpm", name = "show bpm"},
    {id = "show_cpu", name = "show cpu%"}
  }) do
    params:add{
      type = "control", id = p.id, name = p.name,
      controlspec = controlspec.new(0, 1, "lin", 1, 1, "", 1),
      formatter = function(param) return param:get() == 1 and "on" or "off" end
    }
  end

  params:add_group("polyphasic", 3)
  add_control("vel_lo", "velocity lo", 1, 127, 40)
  add_control("vel_hi", "velocity hi", 1, 127, 110)
  params:set_action("vel_lo", function(v) if v > params:get("vel_hi") then params:set("vel_hi", v) end end)
  params:set_action("vel_hi", function(v) if v < params:get("vel_lo") then params:set("vel_lo", v) end end)
  params:add{
    type = "control", id = "vel_curve", name = "velocity curve",
    controlspec = controlspec.new(1, 5, "lin", 1, 1, "", 1 / 4),
    formatter = function(param)
      local curves = {"random", "ramp up", "ramp down", "triangle", "sine"}
      return curves[param:get()]
    end
  }

  params:add_group("ARC", 4)
  add_control("arc_threshold", "arc sensitivity", 1, 64, 24)
  add_control("arc_brightness", "arc brightness", 1, 15, 10)
  add_control("arc_dim", "arc dim brightness", 0, 15, 2)
  params:add{
    type = "control", id = "arc_position", name = "arc position",
    controlspec = controlspec.new(1, 4, "lin", 1, 1, "", 1 / 3),
    formatter = function(param)
      local positions = {"up", "right", "down", "left"}
      return positions[param:get()]
    end
  }

  grid_ = GridLib:new()
  Display.init(4)
  garc_ = GArc:new{
    pages = ARC_PAGES,
    threshold_id = "arc_threshold",
    bright_id = "arc_brightness",
    dim_id = "arc_dim",
    position_id = "arc_position",
    shift_fn = function() return is_shift end
  }

  params:bang()
  garc_:redraw() -- otherwise the arc stays dark until the first touch

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
      -- keeps the rings showing the real values when something else moves
      -- them (PARAMS menu, pset load, an encoder); only redraws on a change
      if garc_ then garc_:poll() end
    end
  end)
end

function enc(k, d)
  if k == 1 then
    if is_shift then
      sequencers[params:get("main_sequence")]:delta_param("midi_out_device", d)
    else
      params:delta("main_sequence", d)
      -- every arc ring targets "whichever track is selected" -- refresh so
      -- switching tracks doesn't leave the rings showing the old one's
      -- values until the next arc turn
      if garc_ then garc_:redraw() end
    end
  elseif k == 2 then
    if is_shift then
      sequencers[params:get("main_sequence")]:delta_param("division", d)
    elseif d == 1 or d == -1 then
      if params:get("main_play") == 1 then
        sequencers[params:get("main_sequence")]:delta_param("direction", d)
      else
        sequencers[params:get("main_sequence")]:set_param("direction", d < 0 and 2 or 1) -- backward : forward
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

-- norns' standard transport hooks: fire on Link start/stop as well as MIDI
-- clock start/stop when CLOCK source is set accordingly. the raw per-device
-- MIDI start/stop handling in params_main() is separate and stays as-is
-- (it works regardless of the global CLOCK source setting).
function clock.transport.start()
  params:set("main_play", 1)
end

function clock.transport.stop()
  params:set("main_play", 0)
end

function redraw()
  screen.clear()

  local current = sequencers[params:get("main_sequence")]
  Display.draw(4)

  if params:get("show_track") == 1 then
    screen.level(4)
    screen.move(0, 7)
    screen.text(tostring(params:get("main_sequence")))
  end

  local show_bpm = params:get("show_bpm") == 1
  local show_cpu = params:get("show_cpu") == 1
  if show_bpm or show_cpu then
    local right_text = ""
    if show_bpm then right_text = string.format("%.0f", params:get("clock_tempo")) .. "bpm" end
    if show_cpu then
      if show_bpm then right_text = right_text .. " " end
      right_text = right_text .. string.format("%2.0f", last_cpu) .. "%"
    end
    screen.level(4)
    screen.move(128, 7)
    screen.text_right(right_text)
  end

  -- arc footer takes this line when there's one to show (it already covers
  -- play/direction/division-equivalent info for whichever ring you're on);
  -- otherwise fall back to the plain play/direction/division line so that
  -- info doesn't disappear when no arc is connected
  local footer = garc_ and garc_:footer_text()
  screen.level(footer and 3 or 2)
  screen.move(0, 64 - 2)
  screen.text(footer or (params:string("main_play") .. current:get_param_str("direction") .. " " ..
    current:get_param_str("division")))

  screen.update()
end

function rerun()
  norns.script.load(norns.state.script)
end

function cleanup()
  for i = 1, 4 do sequencers[i]:panic() end
end

function table.reverse(t)
  local len = #t
  for i = len - 1, 1, -1 do t[len] = table.remove(t, i) end
end

-- forwards start/stop/continue to every port enabled under PARAMETERS >
-- CLOCK > "midi out" (clock_midi_out_1..16 -- norns' own clock params,
-- registered before this script's init() runs). that system-level setting
-- already streams continuous MIDI clock ticks to those ports on its own;
-- this just adds the transport message on top of it, so an arpeggiator
-- synced to norns' clock also starts/stops with the sequencer's own
-- play/stop instead of just free-running.
local function send_transport(msg_type)
  for i = 1, 16 do
    if params:get("clock_midi_out_" .. i) == 1 then
      local port = midi.vports[i]
      if port then port[msg_type](port) end
    end
  end
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
      action=function(v)
        if v == 0 then
          for i = 1, 4 do sequencers[i]:reset_timer() end
          send_transport("stop")
        else
          send_transport("start")
        end
      end
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
    tab.save(data, filename .. ".data")
  end

  params.action_read = function(filename, silent)
    filename = filename .. ".data"
    if not util.file_exists(filename) then do return end end
    local data = tab.load(filename)
    if data == nil then do return end end
    for i = 1, 4 do sequencers[i]:unmarshal(data["sequence_" .. i]) end
  end
end