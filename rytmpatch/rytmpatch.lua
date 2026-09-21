-- rytmpatch v0.1.0
--
-- MIDI CC patch randomizer/editor for the Elektron Analog Rytm MKII,
-- after MDPatch (hanjo-synth) for the Machinedrum.
--
-- MIDI out only: no engine.
-- 12 tracks x 5 track pages (SYNTH SAMPLE FILTER AMP LFO) + 4 FX pages
-- (DELAY REVERB DIST COMP). SYNTH relabels itself for the track's
-- machine -- set machines under PARAMETERS > MACHINES (the script can't
-- read them from the Rytm).
--
--    ▼ instructions below ▼
--
-- E1: page
-- E2: select param
-- E3: change value
-- K2: randomize page
-- K3: tame / wide / locked
-- K1+E1: track
-- K1+E2: random amount
-- K1+E3: morph time
-- K1+K2: undo / redo
-- K1+K3: randomize whole track
--        (on an FX page: all FX)
--
-- randomize keeps each param
-- inside a musical window (the
-- ticks on its bar), not its
-- whole CC range. K3 cycles a
-- param: tame -> wide (hollow
-- block, full range) -> locked
-- (solid block, never touched).
-- PARAMETERS > RANDOMIZE >
-- "widen range" opens every
-- window at once, and
-- "outliers" (10%) is how often
-- a param ignores its window
-- and lands outside it -- the
-- extremes stay reachable, just
-- rare.
--
-- Rytm setup: MIDI CONFIG >
-- CHANNELS: tracks on 1-12
-- (or set "track 1 channel"),
-- FX control channel to match
-- "fx channel". enable PARAM
-- receive; enable PARAM send
-- too if you want knob moves
-- mirrored on screen.

local Core = include("rytmpatch/lib/patchcore")
local View = include("rytmpatch/lib/pageview")
local Map = include("rytmpatch/lib/rytm_map")
local musicutil = require("musicutil")

local NUM_TRACKS = 12
local NUM_TRACK_PAGES = #Map.track_pages
local NUM_PAGES = NUM_TRACK_PAGES + #Map.fx_pages

local MORPH_BEATS = {0, 1/4, 1/2, 1, 2, 4, 8, 16}
local MORPH_NAMES = {"off", "1/4", "1/2", "1", "2", "4", "8", "16"}
local WANDER_BEATS = {1/4, 1/2, 1, 2, 4, 8}
local WANDER_NAMES = {"1/4", "1/2", "1", "2", "4", "8"}

local core
local out_dev
local shift = false
local dirty = true
local track = 1
local page = 1
local sel = 1
local clocks = {}

-- slots[t][p] for track pages, fx_slots[p] for FX pages: built once (and
-- the SYNTH page again on machine change), never per frame
local slots = {}
local fx_slots = {}
-- incoming CC -> slot lookup for mirroring the Rytm's own knob moves
local track_cc = {}
local fx_cc = {}

---------------------------------------------------------------- slot tables

local function build_track_page(t, p)
  local descs
  if p == 1 then
    descs = Map.machine_pages[params:get("machine_" .. t)]
  else
    descs = Map.track_pages[p].slots
  end
  local list = {}
  for i = 1, 8 do
    local desc = descs[i]
    list[i] = desc and {key = "t" .. t .. ".cc" .. desc.cc, desc = desc, track = t} or false
  end
  slots[t][p] = list
  for i = 1, 8 do
    if list[i] then track_cc[t][list[i].desc.cc] = list[i] end
  end
end

local function build_slots()
  for t = 1, NUM_TRACKS do
    slots[t] = {}
    track_cc[t] = {}
    for p = 1, NUM_TRACK_PAGES do build_track_page(t, p) end
  end
  for p, pg in ipairs(Map.fx_pages) do
    local list = {}
    for i = 1, 8 do
      local desc = pg.slots[i]
      list[i] = desc and {key = "fx.cc" .. desc.cc, desc = desc, fx = true} or false
      if desc then fx_cc[desc.cc] = list[i] end
    end
    fx_slots[p] = list
  end
end

local function is_fx_page(p) return p > NUM_TRACK_PAGES end

local function page_slots(p)
  if is_fx_page(p) then return fx_slots[p - NUM_TRACK_PAGES] end
  return slots[track][p]
end

local function page_name(p)
  if is_fx_page(p) then return Map.fx_pages[p - NUM_TRACK_PAGES].name end
  return Map.track_pages[p].name
end

local function scope_for(p)
  return is_fx_page(p) and "fx" or ("t" .. track)
end

-- every slot of the current track (or all FX), flattened
local function scope_slots(p)
  local list = {}
  if is_fx_page(p) then
    for _, pg in ipairs(fx_slots) do
      for i = 1, 8 do list[#list + 1] = pg[i] end
    end
  else
    for q = 1, NUM_TRACK_PAGES do
      for i = 1, 8 do list[#list + 1] = slots[track][q][i] end
    end
  end
  return list
end

---------------------------------------------------------------- midi

local function track_channel(t)
  return ((params:get("track_ch") + t - 2) % 16) + 1
end

local function send(slot, v)
  if not out_dev then return end
  local ch = slot.fx and params:get("fx_ch") or track_channel(slot.track)
  out_dev:cc(slot.desc.cc, v, ch)
  -- diagnostic: with a DAW or a plugin in the chain it's worth seeing
  -- exactly what left norns, since anything in between can re-channelize
  -- or swallow CCs
  if params:get("log") == 2 then
    print(string.format("rytmpatch -> ch %2d  cc %3d = %3d  (%s)", ch, slot.desc.cc, v, slot.desc.name))
  end
end

local function audition(t)
  if params:get("audition") == 1 or not out_dev then return end
  local ch, note = track_channel(t), params:get("audition_note")
  out_dev:note_on(note, 100, ch)
  clock.run(function()
    clock.sleep(0.15)
    out_dev:note_off(note, 0, ch)
  end)
end

local function midi_event(data)
  if params:get("sync_in") == 1 then return end
  local msg = midi.to_msg(data)
  if msg.type ~= "cc" then return end
  local slot
  if msg.ch == params:get("fx_ch") then
    slot = fx_cc[msg.cc]
  else
    local t = ((msg.ch - params:get("track_ch")) % 16) + 1
    if t <= NUM_TRACKS then slot = track_cc[t][msg.cc] end
  end
  if slot then core:receive(slot, msg.val) end
end

local function connect_midi()
  if out_dev then out_dev.event = nil end
  out_dev = midi.connect(params:get("midi_port"))
  out_dev.event = midi_event
end

local function send_all()
  for t = 1, NUM_TRACKS do
    for p = 1, NUM_TRACK_PAGES do
      for i = 1, 8 do
        local s = slots[t][p][i]
        -- only resend what we actually hold a value for: blasting
        -- defaults over params never touched would flatten the kit
        if s and core.values[s.key] ~= nil then core:set(s, core.values[s.key], true) end
      end
    end
  end
  for _, pg in ipairs(fx_slots) do
    for i = 1, 8 do
      local s = pg[i]
      if s and core.values[s.key] ~= nil then core:set(s, core.values[s.key], true) end
    end
  end
end

---------------------------------------------------------------- actions

local function spread() return params:get("rnd_spread") / 100 end

local function rand_opts(scope)
  return {
    amount = params:get("rnd_amount") / 100,
    lo = params:get("rnd_lo") / 100,
    hi = math.max(params:get("rnd_lo"), params:get("rnd_hi")) / 100,
    spread = spread(),
    tails = params:get("rnd_tails") / 100,
    beats = MORPH_BEATS[params:get("morph")],
    scope = scope,
  }
end

local function randomize_page()
  local n = core:randomize(page_slots(page), 8, rand_opts(scope_for(page)))
  View.flash(n > 0 and ("RANDOM " .. page_name(page)) or "ALL LOCKED")
  if not is_fx_page(page) then audition(track) end
end

local function randomize_scope()
  local list = scope_slots(page)
  local n = core:randomize(list, #list, rand_opts(scope_for(page)))
  View.flash(n > 0 and (is_fx_page(page) and "RANDOM ALL FX" or ("RANDOM TRACK " .. track)) or "ALL LOCKED")
  if not is_fx_page(page) then audition(track) end
end

local function undo()
  if core:swap_undo(scope_for(page), MORPH_BEATS[params:get("morph")]) then
    View.flash("UNDO / REDO")
    if not is_fx_page(page) then audition(track) end
  else
    View.flash("NOTHING TO UNDO")
  end
end

---------------------------------------------------------------- persistence

local function data_path(n)
  return norns.state.data .. "rytmpatch-" .. string.format("%02d", n) .. ".data"
end

local function setup_pset_hooks()
  params.action_write = function(filename, name, number)
    core:save(data_path(number))
  end
  params.action_read = function(filename, silent, number)
    core:load(data_path(number))
    if params:get("send_on_load") == 2 then send_all() end
  end
  params.action_delete = function(filename, name, number)
    if util.file_exists(data_path(number)) then os.remove(data_path(number)) end
  end
end

---------------------------------------------------------------- params

local function add_params()
  params:add_separator("rytmpatch_sep", "RYTMPATCH")

  params:add_group("rytmpatch_midi", "MIDI", 7)
  params:add_option("midi_port", "rytm port", Core.port_names(), 1)
  params:set_action("midi_port", function() connect_midi() end)
  params:add_number("track_ch", "track 1 channel", 1, 16, 1)
  params:add_number("fx_ch", "fx channel", 1, 16, 13)
  params:add_option("sync_in", "mirror rytm knobs", {"off", "on"}, 2)
  params:add_option("log", "log sends to maiden", {"off", "on"}, 1)
  params:add_option("send_on_load", "send on pset load", {"off", "on"}, 2)
  params:add_trigger("send_all", "send all to rytm")
  params:set_action("send_all", function() send_all(); View.flash("SENT ALL") end)

  params:add_group("rytmpatch_random", "RANDOMIZE", 11)
  params:add_number("rnd_amount", "random amount", 0, 100, 100, function(p) return p:get() .. "%" end)
  -- 0% = each param's tame window (see lib/rytm_map.lua), 100% = its full
  -- CC range, i.e. the old free-for-all
  params:add_number("rnd_spread", "widen range", 0, 100, 0, function(p) return p:get() .. "%" end)
  -- chance per param of ignoring the window and landing outside it, so
  -- the extremes stay reachable by the dice without becoming the norm
  params:add_number("rnd_tails", "outliers", 0, 100, 10, function(p) return p:get() .. "%" end)
  params:add_number("rnd_lo", "range low", 0, 100, 0, function(p) return p:get() .. "%" end)
  params:add_number("rnd_hi", "range high", 0, 100, 100, function(p) return p:get() .. "%" end)
  params:add_option("morph", "morph time (beats)", MORPH_NAMES, 1)
  params:add_option("wander", "wander", {"off", "page", "track"}, 1)
  params:add_option("wander_div", "wander every (beats)", WANDER_NAMES, 3)
  params:add_number("wander_depth", "wander depth", 1, 50, 8, function(p) return p:get() .. "%" end)
  params:add_option("audition", "audition on random", {"off", "on"}, 1)
  params:add_number("audition_note", "audition note", 0, 127, 60,
    function(p) return musicutil.note_num_to_name(p:get(), true) end)

  params:add_group("rytmpatch_machines", "MACHINES", NUM_TRACKS)
  for t = 1, NUM_TRACKS do
    params:add_option("machine_" .. t, "track " .. t, Map.machine_names,
      Map.machine_index(Map.default_machines[t]))
    params:set_action("machine_" .. t, function()
      if slots[t] then
        build_track_page(t, 1)
        dirty = true
      end
    end)
  end
end

---------------------------------------------------------------- norns

function init()
  core = Core.new({
    send = send,
    on_change = function() dirty = true end,
  })
  add_params()
  build_slots()
  setup_pset_hooks()
  params:bang()
  connect_midi()
  -- restore the last session's picture of the Rytm (no send: the Rytm may
  -- have moved on since; use "send all" to push it)
  core:load(norns.state.data .. "rytmpatch-last.data")

  clocks.redraw = clock.run(function()
    while true do
      clock.sleep(1 / 15)
      if dirty or View.flashing() or core:morphing() then
        dirty = false
        redraw()
      end
    end
  end)

  clocks.wander = clock.run(function()
    while true do
      local beats = WANDER_BEATS[params:get("wander_div")]
      clock.sync(beats)
      local mode = params:get("wander")
      if mode > 1 then
        local list = mode == 2 and page_slots(page) or scope_slots(page)
        core:wander_step(list, #list, params:get("wander_depth") / 100, beats, spread())
      end
    end
  end)
end

function enc(n, d)
  if shift then
    if n == 1 then
      track = util.clamp(track + d, 1, NUM_TRACKS)
    elseif n == 2 then
      params:delta("rnd_amount", d)
      View.flash("RANDOM AMOUNT " .. params:get("rnd_amount") .. "%")
    elseif n == 3 then
      params:delta("morph", d)
      View.flash("MORPH " .. params:string("morph"))
    end
  else
    if n == 1 then
      page = util.clamp(page + d, 1, NUM_PAGES)
    elseif n == 2 then
      sel = util.clamp(sel + d, 1, 8)
    elseif n == 3 then
      local s = page_slots(page)[sel]
      if s then core:delta(s, d) end
    end
  end
  dirty = true
end

function key(n, z)
  if n == 1 then
    shift = z == 1
  elseif z == 1 then
    if n == 2 then
      if shift then undo() else randomize_page() end
    elseif n == 3 then
      if shift then
        randomize_scope()
      else
        local s = page_slots(page)[sel]
        if s then
          View.flash(string.upper(core:cycle_mode(s)) .. " " .. s.desc.name)
        end
      end
    end
  end
  dirty = true
end

function redraw()
  screen.clear()
  screen.aa(0)
  screen.font_face(1)
  screen.font_size(8)

  local left
  if is_fx_page(page) then
    left = "FX"
  else
    left = string.format("T%02d ", track) .. Map.machine_names[params:get("machine_" .. track)]
  end
  View.header(left, page_name(page) .. " " .. page .. "/" .. NUM_PAGES)

  local list = page_slots(page)
  for i = 1, 8 do View.slot(i, core, list[i], i == sel, spread()) end

  local foot
  if core:morphing() then
    foot = "morphing..."
  elseif shift then
    foot = "K2 undo  K3 rnd " .. (is_fx_page(page) and "all fx" or "track")
  else
    foot = "rnd " .. params:get("rnd_amount") .. "%  morph " .. params:string("morph")
    if params:get("rnd_spread") > 0 then foot = foot .. "  wide " .. params:get("rnd_spread") .. "%" end
    if params:get("wander") > 1 then foot = foot .. "  ~" end
  end
  View.footer(foot)
  screen.update()
end

function cleanup()
  for _, id in pairs(clocks) do clock.cancel(id) end
  if core then
    core:stop_all()
    core:save(norns.state.data .. "rytmpatch-last.data")
  end
  if out_dev then out_dev.event = nil end
end
