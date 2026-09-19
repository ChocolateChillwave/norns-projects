-- summitpatch v0.1.0
--
-- patch randomizer + AFX-style per-key
-- overlays for Novation Summit / Peak
--
-- MIDI out only: no engine.
--
-- RANDOMIZER: 11 pages of CCs
-- (osc, pitch mod, mix, filter,
-- envs, lfos, fx) + an NRPN
-- STRUCT page (waves/filter
-- shape, unverified, locked by
-- default). recipes bias the
-- random windows toward bass /
-- pad / lead / pluck / perc /
-- drone, or "chaos" = full range.
--
-- AFX (last page): play notes
-- into norns (keyboard or a
-- sequencer on "input port").
-- each key gets its own set of
-- offsets on 8 target params,
-- sent right before the note
-- is passed on to the Summit --
-- like Novation's AFX mode, one
-- patch per key.
--
--    ▼ instructions below ▼
--
-- E1: page
-- E2: select param
-- E3: change value
-- K2: randomize page
-- K3: lock/unlock param
-- K1+E1: recipe
-- K1+E2: random amount
-- K1+E3: morph time
-- K1+K2: undo / redo
-- K1+K3: randomize whole patch
--
-- on the AFX page:
-- E3: offset for this key
-- K2: randomize this key
-- K3: AFX on/off
-- K1+E2: select key
-- K1+E3: change target param
-- K1+K3: randomize every key
--
-- tip: if the Summit's own keys
-- feed norns, set Summit LOCAL
-- CONTROL off so notes only
-- sound after the overlay lands.

local Core = include("summitpatch/lib/patchcore")
local View = include("summitpatch/lib/pageview")
local Map = include("summitpatch/lib/summit_map")
local musicutil = require("musicutil")

local NUM_EDIT_PAGES = #Map.pages
local AFX_PAGE = NUM_EDIT_PAGES + 1
local NUM_PAGES = AFX_PAGE
local AFX_TARGETS = 8
local AFX_MAX_KEYS = 24

local MORPH_BEATS = {0, 1/4, 1/2, 1, 2, 4, 8, 16}
local MORPH_NAMES = {"off", "1/4", "1/2", "1", "2", "4", "8", "16"}
local WANDER_BEATS = {1/4, 1/2, 1, 2, 4, 8}
local WANDER_NAMES = {"1/4", "1/2", "1", "2", "4", "8"}
local AFX_KEYS = {12, 24}

local core
local out_dev, in_dev
local shift = false
local dirty = true
local page = 1
local sel = 1
local clocks = {}

local page_slots = {}   -- page -> array of 8 slots (false = empty)
local all_slots = {}    -- flattened, for randomize-whole-patch
local slot_by_id = {}

-- AFX state
local afx = {
  offsets = {},   -- [key 1..24][target 1..8] = -127..127
  key = 1,        -- key slot shown on the AFX page (follows last note)
  sent = {},      -- desc id -> value last sent to the Summit (base or overlaid)
  held = {},      -- note -> true
  undo = nil,
}

---------------------------------------------------------------- slots

local function build_slots()
  for p, pg in ipairs(Map.pages) do
    local list = {}
    for i = 1, 8 do
      local desc = pg.slots[i]
      if desc then
        local s = {key = "s." .. desc.id, desc = desc}
        list[i] = s
        slot_by_id[desc.id] = s
        all_slots[#all_slots + 1] = s
      else
        list[i] = false
      end
    end
    page_slots[p] = list
  end
end

local function clear_afx()
  for k = 1, AFX_MAX_KEYS do
    afx.offsets[k] = {}
    for t = 1, AFX_TARGETS do afx.offsets[k][t] = 0 end
  end
end

local function afx_target(t)
  return slot_by_id[Map.cc_ids[params:get("afx_t" .. t)]]
end

---------------------------------------------------------------- midi out

local function out_ch() return params:get("out_ch") end

local function send(slot, v)
  afx.sent[slot.desc.id] = v
  if not out_dev then return end
  local d = slot.desc
  if d.cc then
    out_dev:cc(d.cc, v, out_ch())
  else
    Core.nrpn(out_dev, out_ch(), d.nrpn[1], d.nrpn[2], v)
  end
end

local function send_raw_cc(slot, v)
  if afx.sent[slot.desc.id] == v then return end
  afx.sent[slot.desc.id] = v
  if out_dev then out_dev:cc(slot.desc.cc, v, out_ch()) end
end

-- overlay = base patch value + this key's offset (x depth), per target
local function apply_overlay(k)
  local depth = params:get("afx_depth") / 100
  local offs = afx.offsets[k]
  for t = 1, AFX_TARGETS do
    local s = afx_target(t)
    local d = s.desc
    local v = util.clamp(util.round(core:get(s) + offs[t] * depth), d.min, d.max)
    send_raw_cc(s, v)
  end
end

local function restore_base()
  for t = 1, AFX_TARGETS do
    local s = afx_target(t)
    send_raw_cc(s, core:get(s))
  end
end

local function key_for_note(note)
  local n = AFX_KEYS[params:get("afx_keys")]
  return ((note - params:get("afx_root")) % n) + 1
end

local function send_all()
  for _, s in ipairs(all_slots) do
    if core.values[s.key] ~= nil then core:set(s, core.values[s.key], true) end
  end
end

---------------------------------------------------------------- midi in

local function sync_cc(msg)
  if params:get("sync_in") == 1 or msg.ch ~= out_ch() then return end
  local d = Map.by_cc[msg.cc]
  if d then
    core:receive(slot_by_id[d.id], msg.val)
    afx.sent[d.id] = msg.val
  end
end

local function handle_in(data, same_port)
  local msg = midi.to_msg(data)
  local in_ch = params:get("in_ch")
  if msg.ch and in_ch > 0 and msg.ch ~= in_ch and not (same_port and msg.type == "cc") then return end
  -- "auto" passes notes on only when they come from a different port than
  -- the Summit's: echoing the Summit's own keys straight back at it would
  -- double every note while its local control is on
  local mode = params:get("thru")
  local thru = out_dev and (mode == 2 or (mode == 3 and not same_port))

  if msg.type == "note_on" and msg.vel > 0 then
    afx.held[msg.note] = true
    if params:get("afx_on") == 2 then
      local k = key_for_note(msg.note)
      apply_overlay(k)
      if afx.key ~= k then afx.key = k; dirty = true end
    end
    if thru then out_dev:note_on(msg.note, msg.vel, out_ch()) end
  elseif msg.type == "note_off" or (msg.type == "note_on" and msg.vel == 0) then
    afx.held[msg.note] = nil
    if thru then out_dev:note_off(msg.note, 0, out_ch()) end
    if params:get("afx_on") == 2 and params:get("afx_release") == 2 and next(afx.held) == nil then
      restore_base()
    end
  elseif msg.type == "cc" then
    if same_port then
      -- CCs coming back from the Summit itself: mirror, never echo
      sync_cc(msg)
    elseif thru then
      out_dev:cc(msg.cc, msg.val, out_ch())
    end
  elseif thru then
    if msg.type == "pitchbend" then out_dev:pitchbend(msg.val, out_ch())
    elseif msg.type == "channel_pressure" then out_dev:channel_pressure(msg.val, out_ch())
    elseif msg.type == "key_pressure" then out_dev:key_pressure(msg.note, msg.val, out_ch())
    end
  end
end

local function connect_midi()
  if out_dev then out_dev.event = nil end
  if in_dev then in_dev.event = nil end
  local op, ip = params:get("out_port"), params:get("in_port")
  out_dev = midi.connect(op)
  in_dev = midi.connect(ip)
  if op == ip then
    out_dev.event = function(data) handle_in(data, true) end
  else
    out_dev.event = function(data)
      local msg = midi.to_msg(data)
      if msg.type == "cc" then sync_cc(msg) end
    end
    in_dev.event = function(data) handle_in(data, false) end
  end
end

---------------------------------------------------------------- actions

local function recipe_ranges()
  local name = Map.recipe_names[params:get("recipe")]
  if name == "any" then return nil end
  if name == "chaos" then
    return function(s) return {s.desc.min, s.desc.max} end
  end
  local r = Map.recipes[name]
  return function(s) return r[s.desc.id] end
end

local function rand_opts()
  return {
    amount = params:get("rnd_amount") / 100,
    lo = params:get("rnd_lo") / 100,
    hi = math.max(params:get("rnd_lo"), params:get("rnd_hi")) / 100,
    beats = MORPH_BEATS[params:get("morph")],
    scope = "patch",
    ranges = recipe_ranges(),
  }
end

local function afx_snapshot()
  afx.undo = {}
  for k = 1, AFX_MAX_KEYS do
    afx.undo[k] = {table.unpack(afx.offsets[k])}
  end
end

local function afx_randomize_key(k)
  local amount = params:get("rnd_amount") / 100
  local spread = params:get("afx_spread")
  local offs = afx.offsets[k]
  for t = 1, AFX_TARGETS do
    local r = math.random(-spread, spread)
    offs[t] = util.round(offs[t] + (r - offs[t]) * amount)
  end
end

local function randomize_page()
  if page == AFX_PAGE then
    afx_snapshot()
    afx_randomize_key(afx.key)
    View.flash("RANDOM KEY " .. afx.key)
  else
    local n = core:randomize(page_slots[page], 8, rand_opts())
    View.flash(n > 0 and ("RANDOM " .. Map.pages[page].name) or "ALL LOCKED")
  end
end

local function randomize_all()
  if page == AFX_PAGE then
    afx_snapshot()
    for k = 1, AFX_KEYS[params:get("afx_keys")] do afx_randomize_key(k) end
    View.flash("RANDOM ALL KEYS")
  else
    local n = core:randomize(all_slots, #all_slots, rand_opts())
    View.flash(n > 0 and ("RANDOM PATCH (" .. params:string("recipe") .. ")") or "ALL LOCKED")
  end
end

local function undo()
  if page == AFX_PAGE then
    if not afx.undo then View.flash("NOTHING TO UNDO"); return end
    local redo = {}
    for k = 1, AFX_MAX_KEYS do redo[k] = afx.offsets[k] end
    afx.offsets, afx.undo = afx.undo, redo
    View.flash("UNDO / REDO KEYS")
  elseif core:swap_undo("patch", MORPH_BEATS[params:get("morph")]) then
    View.flash("UNDO / REDO")
  else
    View.flash("NOTHING TO UNDO")
  end
end

---------------------------------------------------------------- persistence

local function data_path(n)
  return norns.state.data .. "summitpatch-" .. string.format("%02d", n) .. ".data"
end

local function load_file(path)
  local extra = core:load(path)
  clear_afx()
  if extra and extra.afx then
    for k = 1, AFX_MAX_KEYS do
      for t = 1, AFX_TARGETS do
        local v = extra.afx[k] and extra.afx[k][t]
        if v then afx.offsets[k][t] = v end
      end
    end
  end
  afx.undo = nil
  afx.sent = {}
end

local function save_file(path)
  core:save(path, {afx = afx.offsets})
end

local function setup_pset_hooks()
  params.action_write = function(filename, name, number) save_file(data_path(number)) end
  params.action_read = function(filename, silent, number)
    load_file(data_path(number))
    if params:get("send_on_load") == 2 then send_all() end
  end
  params.action_delete = function(filename, name, number)
    if util.file_exists(data_path(number)) then os.remove(data_path(number)) end
  end
end

---------------------------------------------------------------- params

local function pct(p) return p:get() .. "%" end

local function add_params()
  local ports = Core.port_names()
  params:add_separator("summitpatch_sep", "SUMMITPATCH")

  params:add_group("summitpatch_midi", "MIDI", 8)
  params:add_option("out_port", "summit port", ports, 1)
  params:set_action("out_port", function() connect_midi() end)
  params:add_number("out_ch", "summit channel", 1, 16, 1)
  params:add_option("in_port", "input port (notes)", ports, 1)
  params:set_action("in_port", function() connect_midi() end)
  params:add_number("in_ch", "input channel", 0, 16, 0,
    function(p) return p:get() == 0 and "omni" or p:get() end)
  params:add_option("thru", "note thru", {"off", "on", "auto"}, 3)
  params:add_option("sync_in", "mirror summit knobs", {"off", "on"}, 2)
  params:add_option("send_on_load", "send on pset load", {"off", "on"}, 2)
  params:add_trigger("send_all", "send all to summit")
  params:set_action("send_all", function() if core then send_all(); View.flash("SENT ALL") end end)

  params:add_group("summitpatch_random", "RANDOMIZE", 8)
  params:add_option("recipe", "recipe", Map.recipe_names, 1)
  params:add_number("rnd_amount", "random amount", 0, 100, 100, pct)
  params:add_number("rnd_lo", "range low", 0, 100, 0, pct)
  params:add_number("rnd_hi", "range high", 0, 100, 100, pct)
  params:add_option("morph", "morph time (beats)", MORPH_NAMES, 1)
  params:add_option("wander", "wander", {"off", "page", "patch"}, 1)
  params:add_option("wander_div", "wander every (beats)", WANDER_NAMES, 3)
  params:add_number("wander_depth", "wander depth", 1, 50, 8, pct)

  params:add_group("summitpatch_afx", "AFX", 7 + AFX_TARGETS)
  params:add_option("afx_on", "afx overlays", {"off", "on"}, 2)
  params:add_option("afx_keys", "keys", {"12 (per note name)", "24 (two octaves)"}, 1)
  params:add_number("afx_root", "first key", 0, 127, 48,
    function(p) return musicutil.note_num_to_name(p:get(), true) end)
  params:add_number("afx_depth", "overlay depth", 0, 200, 100, pct)
  params:add_number("afx_spread", "random spread", 1, 127, 40)
  params:add_option("afx_release", "on release", {"hold", "return"}, 1)
  params:add_trigger("afx_clear", "clear all offsets")
  params:set_action("afx_clear", function()
    if core then afx_snapshot(); clear_afx(); View.flash("OFFSETS CLEARED") end
  end)
  local target_names = {}
  for i, id in ipairs(Map.cc_ids) do target_names[i] = Map.by_id[id].name .. " (" .. id .. ")" end
  for t = 1, AFX_TARGETS do
    local default = 1
    for i, id in ipairs(Map.cc_ids) do
      if id == Map.afx_defaults[t] then default = i end
    end
    params:add_option("afx_t" .. t, "target " .. t, target_names, default)
    params:set_action("afx_t" .. t, function() dirty = true end)
  end
end

---------------------------------------------------------------- norns

function init()
  core = Core.new({
    send = send,
    on_change = function() dirty = true end,
  })
  build_slots()
  clear_afx()
  add_params()
  setup_pset_hooks()
  params:bang()
  connect_midi()
  load_file(norns.state.data .. "summitpatch-last.data")

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
        local list, n
        if mode == 2 and page ~= AFX_PAGE then list, n = page_slots[page], 8
        else list, n = all_slots, #all_slots end
        core:wander_step(list, n, params:get("wander_depth") / 100, beats)
      end
    end
  end)
end

function enc(n, d)
  if page == AFX_PAGE and shift and n ~= 1 then
    if n == 2 then
      afx.key = util.clamp(afx.key + d, 1, AFX_KEYS[params:get("afx_keys")])
    elseif n == 3 then
      params:delta("afx_t" .. sel, d)
    end
  elseif page == AFX_PAGE and not shift and n == 3 then
    local offs = afx.offsets[afx.key]
    offs[sel] = util.clamp(offs[sel] + d, -127, 127)
  elseif shift then
    if n == 1 then
      params:delta("recipe", d)
      View.flash("RECIPE " .. params:string("recipe"))
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
      local s = page_slots[page][sel]
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
        randomize_all()
      elseif page == AFX_PAGE then
        params:set("afx_on", params:get("afx_on") == 2 and 1 or 2)
        if params:get("afx_on") == 1 then restore_base() end
        View.flash("AFX " .. params:string("afx_on"))
      else
        local s = page_slots[page][sel]
        if s then
          core:toggle_lock(s)
          View.flash((core:is_locked(s) and "LOCKED " or "UNLOCKED ") .. s.desc.name)
        end
      end
    end
  end
  dirty = true
end

local function draw_afx()
  local keys = AFX_KEYS[params:get("afx_keys")]
  local note = params:get("afx_root") + afx.key - 1
  local name = musicutil.note_num_to_name(note, keys == 24)
  View.header("AFX KEY " .. name, afx.key .. "/" .. keys .. "  " .. NUM_PAGES .. "/" .. NUM_PAGES)
  local offs = afx.offsets[afx.key]
  for t = 1, AFX_TARGETS do
    local s = afx_target(t)
    local o = offs[t]
    View.cell(t, s.desc.name, (o > 0 and "+" or "") .. o, (o + 127) / 254, true, t == sel, false, false)
  end
  if shift then
    View.footer("E2 key  E3 target  K3 rnd all")
  else
    View.footer("afx " .. params:string("afx_on") .. "  depth " .. params:get("afx_depth") .. "%  "
      .. params:string("afx_release"))
  end
end

function redraw()
  screen.clear()
  screen.aa(0)
  screen.font_face(1)
  screen.font_size(8)

  if page == AFX_PAGE then
    draw_afx()
  else
    View.header(Map.pages[page].name, params:string("recipe") .. "  " .. page .. "/" .. NUM_PAGES)
    local list = page_slots[page]
    for i = 1, 8 do View.slot(i, core, list[i], i == sel) end
    local foot
    if core:morphing() then
      foot = "morphing..."
    elseif shift then
      foot = "E1 recipe  K2 undo  K3 rnd all"
    else
      foot = "rnd " .. params:get("rnd_amount") .. "%  morph " .. params:string("morph")
      if params:get("wander") > 1 then foot = foot .. "  ~" end
    end
    View.footer(foot)
  end
  screen.update()
end

function cleanup()
  for _, id in pairs(clocks) do clock.cancel(id) end
  if core then
    core:stop_all()
    save_file(norns.state.data .. "summitpatch-last.data")
  end
  if out_dev then out_dev.event = nil end
  if in_dev then in_dev.event = nil end
end
