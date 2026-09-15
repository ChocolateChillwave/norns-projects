-- display.lua
-- "Halide": glowing orbs over a faint dot-matrix field -- the physical
-- pixel grid made just barely visible, closest of the concepts we tried to
-- what the OLED looks like up close (see NOTES.md for the others).
--
-- lane (x) = track, height (y) = the scale row it just played,
-- brightness/bloom = how recently + how hard it fired.
-- velocity shapes both peak brightness and fade time (harder hit = brighter + longer).

local Display = {}

Display.lane_x = {34, 58, 82, 106}
Display.rows = 7
Display.top_y = 12
Display.bottom_y = 54

local ATTACK = 0.045       -- seconds, fixed
local DECAY_MIN = 0.22     -- seconds, at velocity 0
local DECAY_MAX = 0.9      -- seconds, at velocity 1
local REST_LEVEL = 2       -- screen.level of the resting/last-position dot

-- the field redraws every frame, so spacing is chosen to stay cheap (a few
-- dozen screen.pixel calls, not hundreds) rather than to match the denser
-- browser mockup 1:1
local FIELD_SPACING = 12
local LANE_DOT_SPACING = 8
local FIELD_TOP, FIELD_BOTTOM = 6, 58
local FIELD_LEFT, FIELD_RIGHT = 4, 124

local lamps = {}

local function clamp(n, lo, hi)
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

-- NOTE: util.time() is assumed to return a monotonic float in seconds, which is
-- how several community scripts drive animation. If your norns build doesn't
-- have it, swap elapsed-time tracking here for a frame counter driven by the
-- 1/15s redraw metro instead.
local function now() return util.time() end

function Display.row_y(i)
  return Display.top_y + (Display.bottom_y - Display.top_y) * (i / (Display.rows - 1))
end

function Display.init(num_tracks)
  lamps = {}
  for i = 1, num_tracks do
    lamps[i] = {
      y = Display.row_y(3),
      fired_at = nil,
      vel = 0,
      decay = DECAY_MIN
    }
  end
end

-- track: 1-indexed track number
-- row: 0-indexed row (0..Display.rows-1) the note that just fired sits on
-- velocity: 1-127, MIDI-style
function Display.trigger(track, row, velocity)
  local l = lamps[track]
  if l == nil then return end
  l.y = Display.row_y(row)
  l.fired_at = now()
  l.vel = clamp(velocity, 1, 127) / 127
  l.decay = DECAY_MIN + l.vel * (DECAY_MAX - DECAY_MIN)
end

local function envelope(track, t_now)
  local l = lamps[track]
  if l == nil or l.fired_at == nil then return 0 end
  local t = t_now - l.fired_at
  if t < ATTACK then return t / ATTACK end
  local d = t - ATTACK
  if d > l.decay then return 0 end
  return (1 - d / l.decay) ^ 2 -- eased decay
end

local function draw_orb(x, y, lit, vel)
  local peak = REST_LEVEL + lit * vel * (15 - REST_LEVEL)
  local spread = 0.75 + 0.35 * vel -- harder hits bloom a little wider

  if lit > 0.02 then
    screen.level(clamp(math.floor(peak * 0.3), 0, 15))
    screen.circle(x, y, 5 * spread)
    screen.fill()

    screen.level(clamp(math.floor(peak * 0.65), 0, 15))
    screen.circle(x, y, 3 * spread)
    screen.fill()
  end

  screen.level(clamp(math.floor(math.max(REST_LEVEL, peak)), 0, 15))
  screen.circle(x, y, 1.4)
  screen.fill()
end

-- the pixel grid made faintly visible everywhere, plus a slightly brighter
-- column of dots marking each track's lane -- replaces the old solid lane
-- lines + single home-row reference line
local function draw_field()
  screen.level(1)
  local x = FIELD_LEFT
  while x < FIELD_RIGHT do
    local y = FIELD_TOP
    while y < FIELD_BOTTOM do
      screen.pixel(x, y)
      y = y + FIELD_SPACING
    end
    x = x + FIELD_SPACING
  end
  screen.fill()

  screen.level(2)
  for _, lx in ipairs(Display.lane_x) do
    local y = FIELD_TOP
    while y < FIELD_BOTTOM do
      screen.pixel(lx, y)
      y = y + LANE_DOT_SPACING
    end
  end
  screen.fill()
end

-- call from redraw(); does NOT call screen.update() so the caller can layer
-- other elements (track number, cpu meter, arc footer, etc.) before
-- flipping the frame -- the track indicator lives in polyphasic.lua now,
-- as plain text matching the bpm/cpu/arc-footer style, not a badge here.
function Display.draw(num_tracks)
  screen.aa(1)
  screen.line_width(1)

  draw_field()

  local t_now = now()
  for i = 1, num_tracks do
    local x = Display.lane_x[i]
    local l = lamps[i]
    if l then
      draw_orb(x, l.y, envelope(i, t_now), l.vel)
    end
  end
end

return Display
