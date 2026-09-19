-- pageview: draws an 8-slot parameter page (2 columns x 4 rows) on the
-- norns screen. shared by rytmpatch and summitpatch (identical copies).
--
-- layout (128x64):
--   y 7        header: left text / right text
--   y 17..52   4 rows x 2 columns; each cell = name, value, thin bar
--   y 62       footer (status / flash message)

local View = {}

local COL_X = {0, 66}
local ROW_Y = {17, 28, 39, 50}
local CELL_W = 62

-- the flash message replaces the footer briefly after an action
local flash_text, flash_until = nil, 0

function View.flash(text, secs)
  flash_text = text
  flash_until = util.time() + (secs or 0.9)
end

function View.flashing()
  return flash_text ~= nil and util.time() < flash_until
end

function View.header(left, right)
  screen.level(15)
  screen.move(0, 7)
  screen.text(left)
  screen.level(6)
  screen.move(127, 7)
  screen.text_right(right)
  screen.level(1)
  screen.move(0, 10)
  screen.line(128, 10)
  screen.stroke()
end

function View.footer(text)
  if View.flashing() then
    screen.level(15)
    screen.move(64, 62)
    screen.text_center(flash_text)
  else
    screen.level(4)
    screen.move(0, 62)
    screen.text(text)
  end
end

-- cell i (1..8). fields:
--   name, text (value string), frac (0..1 bar fill), centered (bar grows
--   from the middle), selected, locked, empty
function View.cell(i, name, text, frac, centered, selected, locked, empty)
  local x = COL_X[((i - 1) % 2) + 1]
  local y = ROW_Y[math.floor((i - 1) / 2) + 1]
  if empty then
    screen.level(1)
    screen.move(x + 4, y)
    screen.text("-")
    return
  end
  -- lock marker: small solid block left of the name
  if locked then
    screen.level(selected and 10 or 5)
    screen.rect(x, y - 4, 2, 4)
    screen.fill()
  end
  screen.level(selected and 15 or 5)
  screen.move(x + 4, y)
  screen.text(name)
  screen.level(selected and 15 or 8)
  screen.move(x + CELL_W, y)
  screen.text_right(text)
  -- bar
  local bx, bw, by = x + 4, CELL_W - 4, y + 2
  screen.level(1)
  screen.rect(bx, by, bw, 1)
  screen.fill()
  screen.level(selected and 12 or 4)
  if centered then
    local mid = bx + bw / 2
    local w = (frac - 0.5) * bw
    if w >= 0 then screen.rect(mid, by, math.max(1, w), 1)
    else screen.rect(mid + w, by, -w, 1) end
  else
    screen.rect(bx, by, math.max(1, frac * bw), 1)
  end
  screen.fill()
end

-- convenience: draw a patchcore slot
function View.slot(i, core, slot, selected)
  if not slot then
    View.cell(i, nil, nil, 0, false, false, false, true)
    return
  end
  local d = slot.desc
  local v = core:get(slot)
  local text
  if d.labels then
    text = d.labels[v - d.min + 1] or tostring(v)
  elseif d.centered then
    local c = math.floor((d.min + d.max + 1) / 2)
    local off = v - c
    text = (off > 0 and "+" or "") .. off
  else
    text = tostring(v)
  end
  local frac = (d.max > d.min) and (v - d.min) / (d.max - d.min) or 0
  View.cell(i, d.name, text, frac, d.centered, selected, core:is_locked(slot), false)
end

return View
