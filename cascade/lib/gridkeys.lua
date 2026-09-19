-- gridkeys.lua
-- press/hold/release over a rectangular region of the grid. this module
-- knows about cells and nothing else -- what a cell means (which note,
-- which voicing) is the caller's business, supplied back through on_press/
-- on_release and level_fn.
--
-- the active region is the LEFT 8x8 of the grid; on a 16-wide grid the
-- right half is left dark and untouched, reserved for a sequencer page
-- later. redraw is metro-polled rather than event-driven, same as
-- polyphasic's ggrid.lua, so held-cell brightness stays correct without
-- every caller having to remember to refresh.
local GridKeys = {}

function GridKeys:new(args)
  local m = setmetatable({}, {__index = GridKeys})
  args = args or {}
  m.on_press = args.on_press     -- function(x, y)
  m.on_release = args.on_release -- function(x, y)
  m.level_fn = args.level_fn     -- function(x, y) -> 0-15 resting brightness

  local midigrid = util.file_exists(_path.code .. "midigrid")
  local grid = midigrid and include "midigrid/lib/mg_128" or grid
  m.g = grid.connect()
  m.g.key = function(x, y, z) m:key(x, y, z) end

  local cols = m.g.cols
  local rows = m.g.rows
  if cols == nil or cols == 0 then cols = 16 end
  if rows == nil or rows == 0 then rows = 8 end
  m.cols = math.min(args.cols or 8, cols)
  m.rows = math.min(args.rows or 8, rows)

  m.held = {}

  -- two buffers of levels, reused every frame rather than reallocated (see
  -- CLAUDE.md's CPU note): one being drawn, one holding what's already on
  -- the grid, so an unchanged frame can be skipped entirely
  m.levels, m.shown = {}, {}
  for x = 1, m.cols do
    m.levels[x], m.shown[x] = {}, {}
    for y = 1, m.rows do m.levels[x][y], m.shown[x][y] = 0, -1 end
  end

  m.grid_refresh = metro.init()
  m.grid_refresh.time = midigrid and 0.12 or 0.03
  m.grid_refresh.event = function() m:grid_redraw() end
  m.grid_refresh:start()

  return m
end

function GridKeys:in_region(x, y)
  return x >= 1 and x <= self.cols and y >= 1 and y <= self.rows
end

function GridKeys:key(x, y, z)
  if not self:in_region(x, y) then return end
  local key = x .. "," .. y
  if z == 1 then
    self.held[key] = true
    if self.on_press then self.on_press(x, y) end
  else
    self.held[key] = nil
    if self.on_release then self.on_release(x, y) end
  end
end

-- the level buffer is rebuilt every frame so the grid follows anything that
-- changes it -- a key going down, a latched chord, the key or scale being
-- changed from the PARAMS menu -- but it's only pushed to the hardware when
-- it actually differs from what's already there. the common case, a grid
-- sitting still, costs a comparison instead of 64 led writes and a refresh.
function GridKeys:grid_redraw()
  if self.g == nil or not self.g.device then return end

  local changed = false
  for x = 1, self.cols do
    for y = 1, self.rows do
      local level
      if self.held[x .. "," .. y] then
        level = 15
      elseif self.level_fn then
        level = self.level_fn(x, y) or 0
      else
        level = 0
      end
      self.levels[x][y] = level
      if self.shown[x][y] ~= level then changed = true end
    end
  end
  if not changed then return end

  self.g:all(0)
  for x = 1, self.cols do
    for y = 1, self.rows do
      local level = self.levels[x][y]
      self.shown[x][y] = level
      if level > 0 then self.g:led(x, y, level) end
    end
  end
  self.g:refresh()
end

return GridKeys
