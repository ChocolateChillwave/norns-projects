-- garc.lua
-- reusable paged arc controller. N pages of up to 4 rings, each ring bound
-- to a norns param (read/written by id -- a ring's id can be a plain string
-- or a function returning one, so a caller can point a ring at "whichever
-- track/step is currently selected" the way polyphasic does, without this
-- module needing to know anything about tracks/steps itself).
--
-- built for polyphasic but kept generic (no polyphasic-specific state
-- touched anywhere in this file) so it can be copied into future scripts
-- the way ggrid.lua/display.lua's patterns already are -- see CLAUDE.md's
-- "core modules" section.
--
-- caller supplies, to GArc:new{...}:
--   pages         { {name=, rings={ {label=, id=}, ... up to 4 }}, ... }
--   threshold_id  id of a norns param controlling arc sensitivity (how much
--                 raw encoder motion registers as one step)
--   bright_id     id of a norns param for the "selected/lit" LED level
--   dim_id        id of a norns param for the "unselected tick" LED level
--                 in discrete mode (optional -- falls back to bright_id)
--   position_id   id of a norns param (1-4) rotating every ring a quarter
--                 turn per step, so the arc can be read right-side up
--                 regardless of how it's physically oriented (optional)
--   shift_fn      function returning true/false -- while true, turning a
--                 ring with an `all_ids` list (see pages, above) applies
--                 the change to every id in that list instead of just the
--                 ring's own `id` (optional; a ring with no `all_ids` is
--                 unaffected either way). e.g. a caller whose rings each
--                 target "whichever track is selected" can give a ring an
--                 `all_ids` returning every track's version of that same
--                 param, so holding a modifier key broadcasts one turn to
--                 all of them instead of just the selected one.
--
-- rendering: a ring with only a handful of selectable values (auto-detected
-- from the param's own min/max/step) draws one dim tick per option, evenly
-- spaced around the full ring, with the selected one lit bright -- rather
-- than a continuous fill, which for e.g. a 2-option param would either look
-- like a half-lit ring or (at high sensitivity) flash between empty and
-- full as you turn past the single threshold between the two values. wider
-- params get a continuous fill instead, smoothed by an accumulator so the
-- ring tracks continuously between registered steps rather than jumping in
-- whole-step increments -- with a floor/ceiling fixup so the very bottom of
-- the range still shows one lit LED (not indistinguishable from "off") and
-- the very top reads as a fully lit ring.
--
-- a continuous ring can ask for a different look with `style`, which is
-- worth doing when the plain fill misrepresents the value:
--   "fill"     (default) origin to value. unchanged from before, so pages
--              that don't ask for anything look exactly as they did
--   "bipolar"  fills out from the origin in whichever direction the value
--              sits. for anything signed -- tilt, transpose, a pan -- a
--              fill reads as "80% of something" when the value means "a
--              bit negative", and this doesn't
--   "comet"    a bright head with the tail falling away behind it
--   "dot"      just the head, for a position rather than an amount
-- and `track = true` lays a dim ring underneath, so an empty or centred
-- value still reads as a dial rather than as an arc that isn't connected.
--
-- values move for reasons other than the arc -- the PARAMS menu, a pset
-- load, an encoder, a script's own automation -- so call GArc:poll() from
-- whatever loop already drives the screen and the rings will follow. it
-- compares four values and only redraws when one actually moved.
local GArc = {}

local LEDS_PER_RING = 64
local DISCRETE_MAX_OPTIONS = 16 -- above this, fall back to continuous fill
local COMET_TAIL = 8            -- leds a comet's tail fades over
-- budget for a 128px-wide norns line. raised from an initial 22 after that
-- cut scale names down to nothing useful -- this is still an estimate (no
-- exact on-device character-width measurement), so say if it's still too
-- tight for some values or has started overflowing again for others.
local FOOTER_MAX_CHARS = 30

local function clamp01(n) return util.clamp(n, 0, 1) end

function GArc:new(args)
  local m = setmetatable({}, {__index = GArc})
  m.pages = args.pages
  m.threshold_id = args.threshold_id
  m.bright_id = args.bright_id
  m.dim_id = args.dim_id or args.bright_id
  m.position_id = args.position_id
  m.shift_fn = args.shift_fn
  m.page = 1
  m.accum = {0, 0, 0, 0}
  m.last_ring = 1
  m.seen_id = {}      -- what poll() last saw on each ring, so it can tell
  m.seen_value = {}   -- when a value moved without the arc being touched

  m.a = arc.connect()
  m.a.delta = function(n, d) m:_on_delta(n, d) end
  m.a.key = function(_, z) if z == 1 then m:cycle_page() end end

  return m
end

function GArc:_ring_id(ring)
  if type(ring.id) == "function" then return ring.id() end
  return ring.id
end

function GArc:_param(ring)
  return params:lookup_param(self:_ring_id(ring))
end

function GArc:_broadcasting(ring)
  return ring.all_ids ~= nil and self.shift_fn ~= nil and self.shift_fn()
end

function GArc:_apply_delta(ring, dir)
  if self:_broadcasting(ring) then
    for _, id in ipairs(ring.all_ids()) do params:delta(id, dir) end
  else
    params:delta(self:_ring_id(ring), dir)
  end
end

-- quarter-turn rotation offset, in radians, applied to every angle this
-- ring draws -- lets the arc be read right-side up in any physical
-- orientation (position_id is 1-4)
function GArc:_rotation()
  if self.position_id == nil then return 0 end
  return (params:get(self.position_id) - 1) * (math.pi / 2)
end

-- returns the option count for a "small enough to show as discrete ticks"
-- param, or nil if it should render as a continuous fill instead
function GArc:_option_count(cs)
  local step = cs.step or 1
  if step <= 0 then return nil end
  local count = util.round((cs.maxval - cs.minval) / step) + 1
  if count >= 2 and count <= DISCRETE_MAX_OPTIONS then return count end
  return nil
end

function GArc:_led_for_angle(angle)
  local a = angle % (math.pi * 2)
  return util.round(a / (math.pi * 2) * LEDS_PER_RING) % LEDS_PER_RING + 1
end

function GArc:_draw_discrete(ring_n, p, count)
  local cs = p.controlspec
  local idx = util.round((p:get() - cs.minval) / cs.step)
  local rot = self:_rotation()
  local bright = params:get(self.bright_id)
  local dim = params:get(self.dim_id)
  for i = 0, count - 1 do
    local angle = rot + (math.pi * 2) * (i / count)
    local led = self:_led_for_angle(angle)
    self.a:led(ring_n, led, i == idx and bright or dim)
  end
end

-- lights individual LEDs directly (rather than a:segment(), whose angle
-- handling turned out not to reliably render a truly full or truly empty
-- ring at the extremes) so the LED count at floor/ceiling is exact: 1 at
-- minimum (never indistinguishable from "off"), all 64 at maximum.
function GArc:_draw_continuous(ring_n, p, ring)
  local cs = p.controlspec
  local base = p:get_raw()
  local threshold = params:get(self.threshold_id)
  local smooth = ((self.accum[ring_n] or 0) / threshold) * cs.quantum
  local frac = clamp01(base + smooth)

  local bright = params:get(self.bright_id)
  local dim = params:get(self.dim_id)
  local rot_led = util.round(self:_rotation() / (math.pi * 2) * LEDS_PER_RING)
  local function led_at(offset, level)
    self.a:led(ring_n, (offset + rot_led) % LEDS_PER_RING + 1, level)
  end

  if ring.track then
    for i = 0, LEDS_PER_RING - 1 do led_at(i, dim) end
  end

  local style = ring.style or "fill"

  if style == "bipolar" then
    -- the origin is the centre and the value runs out either side of it. a
    -- fill would show a value just below centre as most of a ring.
    local signed = frac * 2 - 1
    local reach = util.round(math.abs(signed) * (LEDS_PER_RING / 2))
    led_at(0, bright)
    for i = 1, reach do led_at((signed >= 0) and i or -i, bright) end

  elseif style == "dot" then
    led_at(util.round(frac * (LEDS_PER_RING - 1)), bright)

  elseif style == "comet" then
    local lit = math.max(1, util.round(frac * LEDS_PER_RING))
    for i = 0, lit - 1 do
      local behind = lit - 1 - i
      local level = bright
      if behind > 0 then
        level = math.max(dim, util.round(bright * (1 - behind / COMET_TAIL)))
      end
      led_at(i, level)
    end

  else
    local lit = math.max(1, util.round(frac * LEDS_PER_RING))
    for i = 0, lit - 1 do led_at(i, bright) end
  end
end

function GArc:redraw()
  if self.a == nil or not self.a.device then return end
  self.a:all(0)
  local page = self.pages[self.page]
  for n = 1, 4 do
    local ring = page.rings[n]
    if ring then
      local p = self:_param(ring)
      if p and p.controlspec then
        local count = self:_option_count(p.controlspec)
        if count then
          self:_draw_discrete(n, p, count)
        else
          self:_draw_continuous(n, p, ring)
        end
      end
    end
  end
  self.a:refresh()
  self:_snapshot()
end

-- what the rings are currently showing, so poll() can spot a value that
-- moved without the arc being touched
function GArc:_snapshot()
  local page = self.pages[self.page]
  for n = 1, 4 do
    local ring = page.rings[n]
    if ring then
      local id = self:_ring_id(ring)
      local p = params:lookup_param(id)
      self.seen_id[n], self.seen_value[n] = id, p and p:get()
    else
      self.seen_id[n], self.seen_value[n] = nil, nil
    end
  end
end

-- call from the loop that already drives the screen. reading four values
-- every frame is cheap; lighting 64 leds four times is not, so this only
-- redraws when something actually changed. that keeps the rings honest
-- when a value moves from the PARAMS menu, a pset load or an encoder --
-- without it, the arc shows whatever it last drew until you touch it.
function GArc:poll()
  if self.a == nil or not self.a.device then return end
  local page = self.pages[self.page]

  for n = 1, 4 do
    local ring = page.rings[n]
    local id, value
    if ring then
      id = self:_ring_id(ring)
      local p = params:lookup_param(id)
      value = p and p:get()
    end
    if self.seen_id[n] ~= id or self.seen_value[n] ~= value then
      self:redraw()
      return
    end
  end
end

-- raw arc motion accumulates per-ring and only advances the param once it
-- crosses `threshold` (carrying the remainder), the same technique
-- chordflow uses -- treating every event as a flat +-1 step makes tiny
-- jitter register as a full step while fast spins don't go any faster.
function GArc:_on_delta(n, d)
  local ring = self.pages[self.page].rings[n]
  if not ring then return end
  local threshold = params:get(self.threshold_id)
  self.accum[n] = (self.accum[n] or 0) + d
  self.last_ring = n
  while self.accum[n] >= threshold do
    self:_apply_delta(ring, 1)
    self.accum[n] = self.accum[n] - threshold
  end
  while self.accum[n] <= -threshold do
    self:_apply_delta(ring, -1)
    self.accum[n] = self.accum[n] + threshold
  end
  self:redraw()
end

function GArc:cycle_page()
  self.page = self.page % #self.pages + 1
  self.accum = {0, 0, 0, 0}
  self:redraw()
end

-- caller draws this wherever it fits their own screen layout -- avoiding
-- collisions with other on-screen text is layout-specific, so it stays
-- their job, not this module's. page name, ring label, and the [ALL]
-- broadcast tag (if present) all come first and are never trimmed --
-- truncation only ever eats into the formatted value at the end, since
-- that's the part most likely to be long (a param's formatter was written
-- for the roomier PARAMS menu, not this line) and least essential to keep
-- in full once it's already legible on the arc's own ring.
function GArc:footer_text()
  if self.a == nil or not self.a.device then return nil end
  local page = self.pages[self.page]
  local ring = page.rings[self.last_ring]
  if not ring then return nil end
  local tag = self:_broadcasting(ring) and "[ALL] " or ""
  local text = tag .. page.name .. " " .. ring.label .. ": " .. params:string(self:_ring_id(ring))
  if #text > FOOTER_MAX_CHARS then
    -- plain "..." rather than a single ellipsis glyph -- guaranteed to
    -- exist in any font, not dependent on the active font having U+2026
    text = text:sub(1, FOOTER_MAX_CHARS - 3) .. "..."
  end
  return text
end

return GArc
