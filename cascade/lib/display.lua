-- display.lua
-- the strum drawn as vibrating strings.
--
-- the look is the one phones give guitar strings: a camera with a rolling
-- shutter exposes the image one column at a time, so each column catches the
-- string at a different point in its cycle and a plain vibration comes out as
-- a travelling wave. that's faked here directly -- a string is drawn as a
-- sine along x whose phase advances with time, so it ripples rather than
-- flickering. it isn't how a string really moves, which is exactly the point.
--
-- pitch drives both the number of waves across the screen and how fast the
-- ripple travels, so high notes shimmer tightly and low notes roll slowly.
-- velocity sets how hard it's displaced, and it settles back to a flat line.
--
-- keep an eye on cost: a rippling string is one move plus SAMPLES-1 lines,
-- and a resting one is a single line. that's the reason for MAX_STRINGS and
-- for resting strings being cheap -- see CLAUDE.md's CPU budget note.
local Display = {}

local WIDTH = 128
local TOP, BOTTOM = 30, 56     -- the band strings live in, under the chord name
local MAX_STRINGS = 6
local SAMPLES = 16             -- points per rippling string

local DECAY = 0.9              -- seconds for a struck string to settle
local AMP_MAX = 2.4            -- pixels of displacement at full velocity
local LEVEL_REST = 2
local LEVEL_MAX = 15

local struck = {}              -- note -> {at = time, vel = 0-1}
local points = {}              -- reused each frame, never reallocated

function Display.init()
  struck = {}
end

function Display.strike(note, velocity)
  struck[note] = {at = util.time(), vel = util.clamp((velocity or 100) / 127, 0, 1)}
end

-- how many waves fit across the screen, and how fast they travel: both rise
-- with pitch, which is what makes a high string read as tighter and quicker
local function wave_for(note)
  local cycles = util.clamp(1.5 + (note - 36) / 9, 1.5, 9)
  local speed = 4 + util.clamp((note - 36) * 0.25, 0, 14)
  return cycles, speed
end

-- 0 when a string is at rest, 1 the instant it's struck
local function energy(note, now)
  local s = struck[note]
  if s == nil then return 0 end
  local elapsed = (now - s.at) / DECAY
  if elapsed >= 1 or elapsed < 0 then return 0 end
  return (1 - elapsed) * s.vel
end

-- notes are drawn lowest at the bottom, like strings on a chart. more notes
-- than lines available are sampled evenly so the outer ones are always shown.
local function choose(pool)
  local n = #pool
  if n <= MAX_STRINGS then return pool, n end
  local out = {}
  for i = 1, MAX_STRINGS do
    out[i] = pool[util.round(1 + (i - 1) * (n - 1) / (MAX_STRINGS - 1))]
  end
  return out, MAX_STRINGS
end

function Display.draw(pool, now)
  if pool == nil or #pool == 0 then return end
  local notes, count = choose(pool)
  local spacing = (count > 1) and ((BOTTOM - TOP) / (count - 1)) or 0

  for i = 1, count do
    local note = notes[i]
    local y = BOTTOM - (i - 1) * spacing   -- lowest note at the bottom
    local e = energy(note, now)

    if e <= 0.01 then
      screen.level(LEVEL_REST)
      screen.move(0, y)
      screen.line(WIDTH, y)
      screen.stroke()
    else
      local cycles, speed = wave_for(note)
      local amp = AMP_MAX * e
      local phase = now * speed
      screen.level(util.round(util.linlin(0, 1, LEVEL_REST + 1, LEVEL_MAX, e)))
      for p = 1, SAMPLES do
        local x = (p - 1) * WIDTH / (SAMPLES - 1)
        points[p] = y + amp * math.sin(2 * math.pi * cycles * (x / WIDTH) + phase)
      end
      screen.move(0, points[1])
      for p = 2, SAMPLES do
        screen.line((p - 1) * WIDTH / (SAMPLES - 1), points[p])
      end
      screen.stroke()
    end
  end
end

-- the older, cheaper visual: one dot per note, brightening as it's struck
function Display.draw_dots(pool, now)
  if pool == nil or #pool == 0 then return end
  local count = #pool
  local spacing = math.min(14, 110 / math.max(count - 1, 1))
  local x0 = 64 - (count - 1) * spacing / 2

  screen.aa(1)
  for i, note in ipairs(pool) do
    local e = energy(note, now)
    screen.level(util.round(util.linlin(0, 1, LEVEL_REST, LEVEL_MAX, e)))
    screen.circle(x0 + (i - 1) * spacing, 46, util.linlin(0, 1, 1.5, 3.5, e))
    screen.fill()
  end
  screen.aa(0)
end

return Display
