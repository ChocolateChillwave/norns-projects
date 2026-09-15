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
local GArc = {}

local LEDS_PER_RING = 64
local DISCRETE_MAX_OPTIONS = 16 -- above this, fall back to continuous fill

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
function GArc:_draw_continuous(ring_n, p, n)
  local cs = p.controlspec
  local base = p:get_raw()
  local threshold = params:get(self.threshold_id)
  local smooth = ((self.accum[n] or 0) / threshold) * cs.quantum
  local frac = clamp01(base + smooth)
  local lit = math.max(1, util.round(frac * LEDS_PER_RING))
  local rot_led = util.round(self:_rotation() / (math.pi * 2) * LEDS_PER_RING)
  local bright = params:get(self.bright_id)
  for i = 0, lit - 1 do
    local led = (i + rot_led) % LEDS_PER_RING + 1
    self.a:led(ring_n, led, bright)
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
          self:_draw_continuous(n, p, n)
        end
      end
    end
  end
  self.a:refresh()
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
-- their job, not this module's
function GArc:footer_text()
  if self.a == nil or not self.a.device then return nil end
  local page = self.pages[self.page]
  local ring = page.rings[self.last_ring]
  if not ring then return nil end
  local tag = self:_broadcasting(ring) and "[ALL] " or ""
  return tag .. page.name .. " " .. ring.label .. ": " .. params:string(self:_ring_id(ring))
end

return GArc
