-- local pattern_time = require("pattern")
--
-- grid step-entry gestures (see key_press below):
--   tap a step: toggle a single-step attack on/off
--   tap a step twice in a row: second tap ties it to the previous step
--     (sustains the same pitch through) -- via Sequence:toggle_cell
--   hold one step, tap a second: sustain the note across the whole span
--     from the first tap through the second, instead of a separate attack
--     at every step in between -- via Sequence:sustain_pos
--   bottom row (keyboard row): press = attack at the current step; hold =
--     sustains through every step visited while still held, release = ends
--     it -- via Sequence:note_on_live/note_off_live
local GGrid = {}

function GGrid:new(args)
  local m = setmetatable({}, {__index=GGrid})
  local args = args == nil and {} or args

  m.grid_on = args.grid_on == nil and true or args.grid_on

  -- initiate the grid
  local midigrid = util.file_exists(_path.code .. "midigrid")
  local grid = midigrid and include "midigrid/lib/mg_128" or grid
  m.g = grid.connect()
  m.g.key = function(x, y, z)
    if m.grid_on then m:grid_key(x, y, z) end
  end
  print("grid columns: " .. m.g.cols)

  m.width = m.g.cols
  m.height = m.g.rows
  if m.width == nil or m.width == 0 then m.width = 16 end
  if m.height == nil or m.height == 0 then m.height = 8 end
  m.scroll_y = 0

  -- setup visual
  m.beat = 0
  m.visual = {}
  m.grid_width = m.width
  for i = 1, m.height do
    m.visual[i] = {}
    for j = 1, m.width do m.visual[i][j] = 0 end
  end

  -- keep track of pressed buttons
  m.pressed_buttons = {}

  -- grid refreshing
  m.grid_refresh = metro.init()
  m.grid_refresh.time = midigrid and 0.12 or 0.03
  m.grid_refresh.event = function()
    m:grid_redraw()
  end
  m.grid_refresh:start()

  return m
end

function GGrid:grid_key(x, y, z)
  self:key_press(y, x, z == 1)
  self:grid_redraw()
end

function GGrid:key_press(row, col, on)
  local flipped_row = self.height - row
  local ct = clock.get_beats() * clock.get_beat_sec()
  local time_on = 0
  if on then
    self.pressed_buttons[row .. "," .. col] = ct
  else
    time_on = ct - self.pressed_buttons[row .. "," .. col]
    self.pressed_buttons[row .. "," .. col] = nil
  end
  if self.sequencer.state == 1 then
    -- sequence sequencers
    if on and row < self.height then
      self.sequencer.matrix_sequence_m[col] = self.sequencer.matrix_sequence_m[col] == row and 0 or row
    elseif on and row == self.height and col < self.width then
      self.sequencer:set_param("sequence", col)
    elseif not on and row == self.height and col == self.width then
      self.sequencer.state = 1 - self.sequencer.state
    end
  else
    if on and row == self.height and col < self.width - 1 then
      -- play the keyboard row like a MIDI controller: press writes an
      -- attack at the current step, and holding it down sustains through
      -- every step the sequencer advances to while still held (see
      -- note_on_live / the hold-tracking check in Sequence:update)
      self.sequencer:note_on_live(col)
    elseif not on and row == self.height and col < self.width - 1 then
      self.sequencer:note_off_live(col)
    elseif on and row < self.height then
      -- check if other buttons are pressed
      local row_other = nil
      local col_other = nil
      for k, _ in pairs(self.pressed_buttons) do
        local r, c = k:match("(%d+),(%d+)")
        r, c = tonumber(r), tonumber(c)
        if not (r == row and c == col) and r < self.height then
          row_other = r
          col_other = c
          break
        end
      end
      if row_other ~= nil and col_other ~= nil then
        -- two steps held at once: sustain the note from the first-pressed
        -- step through the second (one attack, tied through to the last
        -- step), at the pitch of whichever key is being pressed now --
        -- rather than the old behavior of toggling on every individual
        -- step in between, which just stacked separate attacks
        local step_a = col_other + math.floor((self.sequencer.step - 1) / 16) * 16
        local step_b = col + math.floor((self.sequencer.step - 1) / 16) * 16
        local step_lo, step_hi = math.min(step_a, step_b), math.max(step_a, step_b)
        self.sequencer:sustain_pos(step_lo, step_hi, flipped_row)
      else
        -- toggle specific position
        print(flipped_row, col)
        local step_index = (col) + math.floor((self.sequencer.step - 1) / 16) * 16
        self.sequencer:toggle_pos(step_index, flipped_row) -- Use flipped_row
      end
    elseif not on and row == self.height and col == self.width and time_on < 0.25 then
      self.sequencer.state = 1 - self.sequencer.state
      --   self.sequencer.note_offset = math.floor((self.sequencer.note_offset + 7) / 7) * 7
    end
  end
end

function GGrid:get_visual()
  -- clear visual
  for row = 1, self.height do for col = 1, self.width do self.visual[row][col] = 0 end end

  -- illuminate currently pressed button
  for k, v in pairs(self.pressed_buttons) do
    local row, col = k:match("(%d+),(%d+)")
    row = tonumber(row)
    col = tonumber(col)
    if row == self.height and col == self.width and v ~= 1234 and self.sequencer ~= nil and self.sequencer.state == 0 then
      local ct = clock.get_beats() * clock.get_beat_sec()
      if ct - v > 0.75 then
        print("time on: ", ct - v)
        self.pressed_buttons[k] = ct - 0.25
        self.sequencer.note_offset = math.floor((self.sequencer.note_offset + 7) / 7) * 7
      end
    end
    self.visual[tonumber(row)][tonumber(col)] = 15
  end

  -- illuminate sequence
  if self.sequencer ~= nil then
    -- show sequencer 
    if self.sequencer.state == 0 then
      -- figure out which of the 'width' steps to show based on 
      -- self.sequencer.step and self.width 
      local step_offset = math.floor((self.sequencer.step - 1) / self.width) * self.width
      for i = 1, self.width do
        for j = 1, self.height - 1 do
          local note_index = self.sequencer:get_note_index(self.height - j)
          local note_value = self.sequencer.matrix[i + step_offset][note_index]
          if note_value > 0 then
            local level = 12 - (self.sequencer.scale_full[note_index] % 12) + 2
            self.visual[j][i] = note_value == 2 and math.max(2, util.round(level / 3)) or level
          end
        end
      end

      -- show current step
      for i = 1, self.height - 1 do
        local v = self.visual[i][(self.sequencer.step - 1) % self.width + 1]
        local note_index = self.sequencer:get_note_index(1)
        v = v + util.round(util.linlin(0, self.sequencer.note_max, 2, 15, note_index))
        if v > 15 then v = 15 end
        self.visual[i][(self.sequencer.step - 1) % self.width + 1] = v
      end

      -- show keyboard
      for col = 1, self.width - 1 do
        local note_index = self.sequencer:get_note_index(col)
        self.visual[self.height][col] = 12 - (self.sequencer.scale_full[note_index] % 12) + 2
      end

    else
      -- show all the steps
      for i = 1, self.width do
        local v = self.sequencer.matrix_sequence_m[i]
        if v > 0 and v < self.height then self.visual[v][i] = self.sequencer.matrix_sequence_cur == i and 10 or 5 end
      end
      for i = 1, self.height - 1 do
        local v = self.visual[i][self.sequencer.matrix_sequence_ind]
        v = v + 2
        if v > 15 then v = 15 end
        self.visual[i][self.sequencer.matrix_sequence_ind] = v

      end
      -- sohw the current sequencer
      self.visual[self.height][self.sequencer:get_param("sequence")] = 15
    end
  end
  return self.visual
end

function GGrid:grid_redraw()
  local gd = self:get_visual()
  if not self.grid_on then return end
  self.g:all(0)
  local s = 1
  local e = self.grid_width
  local adj = 0
  for row = 1, self.height do
    for col = s, e do if gd[row][col] ~= 0 then self.g:led(col + adj, row, gd[row][col]) end end
  end
  self.g:refresh()
end

return GGrid