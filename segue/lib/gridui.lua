-- gridui.lua
-- routes two 8x8 surfaces -- LAUNCH (pattern slots) and FX (performance) --
-- onto whatever grid hardware is actually plugged in, and owns the refresh
-- metro for both.
--
-- three layouts, picked automatically at init:
--   "dual"   two grids on vports 1 and 2. port 1 is LAUNCH, port 2 is FX.
--   "split"  one 16-wide grid. left 8x8 is LAUNCH, right 8x8 is FX -- the
--            same left/right convention cascade already uses, so a 128
--            behaves the way the other scripts in this repo do.
--   "single" one 8x8. LAUNCH normally, FX while the alt modifier is held,
--            so nothing is unreachable on the smaller box.
-- the caller never sees any of this: it gets on_launch(lane, slot, z) and
-- on_fx(col, row, z) and draws through level_launch/level_fx.
--
-- redraw is metro-polled rather than event-driven, matching gridkeys.lua
-- and ggrid.lua elsewhere in this repo -- the playhead moves on its own, so
-- the surface has to refresh whether or not anything was pressed.
local GridUI = {}

GridUI.LAUNCH = 1
GridUI.FX = 2

function GridUI:new(args)
  local m = setmetatable({}, {__index = GridUI})
  args = args or {}
  m.on_launch = args.on_launch      -- function(lane, slot, z)
  m.on_fx = args.on_fx              -- function(col, row, z)
  m.level_launch = args.level_launch -- function(lane, slot) -> 0-15
  m.level_fx = args.level_fx        -- function(col, row) -> 0-15
  m.alt = false                     -- single-grid layout: show FX instead

  local midigrid = util.file_exists(_path.code .. "midigrid")
  local gridlib = midigrid and include "midigrid/lib/mg_128" or grid
  m.midigrid = midigrid

  m.g1 = gridlib.connect(1)
  -- midigrid emulates a single grid over a MIDI controller and has no
  -- second vport to ask for, so only the real grid lib gets probed for one
  if not midigrid then
    m.g2 = gridlib.connect(2)
  end
  m.g1.key = function(x, y, z) m:_key(1, x, y, z) end
  if m.g2 then m.g2.key = function(x, y, z) m:_key(2, x, y, z) end end

  m:detect()

  m.refresh = metro.init()
  m.refresh.time = midigrid and 0.12 or 0.04
  m.refresh.event = function() m:redraw() end
  m.refresh:start()

  return m
end

local function cols_of(g)
  if g == nil or g.device == nil then return 0 end
  local c = g.cols
  if c == nil or c == 0 then return 16 end -- connected but not reporting
  return c
end

function GridUI:detect()
  local c1, c2 = cols_of(self.g1), cols_of(self.g2)
  if c2 >= 8 then
    self.layout = "dual"
  elseif c1 >= 16 then
    self.layout = "split"
  else
    self.layout = "single"
  end
  self.c1, self.c2 = c1, c2
  print("segue: grid layout = " .. self.layout ..
        " (port1 " .. c1 .. " cols, port2 " .. c2 .. " cols)")
  return self.layout
end

-- which surface, and at what local coordinates, a physical press lands on
function GridUI:_resolve(port, x, y)
  if y < 1 or y > 8 then return nil end
  if self.layout == "dual" then
    if port == 1 and x >= 1 and x <= 8 then return GridUI.LAUNCH, x, y end
    if port == 2 and x >= 1 and x <= 8 then return GridUI.FX, x, y end
  elseif self.layout == "split" then
    if port ~= 1 then return nil end
    if x >= 1 and x <= 8 then return GridUI.LAUNCH, x, y end
    if x >= 9 and x <= 16 then return GridUI.FX, x - 8, y end
  else
    if port ~= 1 then return nil end
    if x >= 1 and x <= 8 then
      return (self.alt and GridUI.FX or GridUI.LAUNCH), x, y
    end
  end
  return nil
end

function GridUI:_key(port, x, y, z)
  local surface, cx, cy = self:_resolve(port, x, y)
  if surface == nil then return end
  if surface == GridUI.LAUNCH then
    if self.on_launch then self.on_launch(cx, cy, z) end
  else
    if self.on_fx then self.on_fx(cx, cy, z) end
  end
end

-- set alt (single-grid layout only). returns true if the display changed,
-- so the caller can skip a pointless refresh on the other layouts.
function GridUI:set_alt(v)
  v = v and true or false
  if self.alt == v then return false end
  self.alt = v
  return self.layout == "single"
end

function GridUI:_paint(g, ox, surface)
  for x = 1, 8 do
    for y = 1, 8 do
      local lv
      if surface == GridUI.LAUNCH then
        lv = self.level_launch and self.level_launch(x, y) or 0
      else
        lv = self.level_fx and self.level_fx(x, y) or 0
      end
      if lv and lv > 0 then g:led(x + ox, y, lv > 15 and 15 or lv) end
    end
  end
end

function GridUI:redraw()
  if self.g1 == nil or self.g1.device == nil then return end
  self.g1:all(0)
  if self.layout == "dual" then
    self:_paint(self.g1, 0, GridUI.LAUNCH)
    if self.g2 and self.g2.device then
      self.g2:all(0)
      self:_paint(self.g2, 0, GridUI.FX)
      self.g2:refresh()
    end
  elseif self.layout == "split" then
    self:_paint(self.g1, 0, GridUI.LAUNCH)
    self:_paint(self.g1, 8, GridUI.FX)
  else
    self:_paint(self.g1, 0, self.alt and GridUI.FX or GridUI.LAUNCH)
  end
  self.g1:refresh()
end

function GridUI:cleanup()
  if self.refresh then self.refresh:stop() end
  if self.g1 and self.g1.device then self.g1:all(0) self.g1:refresh() end
  if self.g2 and self.g2.device then self.g2:all(0) self.g2:refresh() end
end

return GridUI
