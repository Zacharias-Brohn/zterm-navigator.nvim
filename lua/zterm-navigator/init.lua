-- zterm-navigator: Seamless navigation between Neovim windows and ZTerm panes
--
-- When you press the navigation key (e.g., Alt+Arrow):
-- - If there's a Neovim window in that direction, navigate to it
-- - If not, send an OSC sequence to ZTerm to navigate to the next pane

local M = {}

-- Default configuration
M.config = {
  -- Key mappings for navigation
  -- Set to false to disable a direction
  left = "<A-Left>",
  right = "<A-Right>",
  up = "<A-Up>",
  down = "<A-Down>",
}

-- Send OSC 51 command to ZTerm for pane navigation
local function zterm_navigate(direction)
  -- OSC 51;navigate;<direction> ST
  -- Using BEL (\007) as string terminator for better compatibility
  local osc = string.format("\027]51;navigate;%s\007", direction)
  io.write(osc)
  io.flush()
end

-- Get the window number in a given direction, or 0 if none exists
local function get_window_in_direction(direction)
  local dir_char = ({
    left = "h",
    right = "l",
    up = "k",
    down = "j",
  })[direction]

  if not dir_char then
    return 0
  end

  -- Get current window number
  local current_winnr = vim.fn.winnr()
  -- Get window number in the specified direction
  local target_winnr = vim.fn.winnr(dir_char)

  -- If winnr() returns the same window, there's no window in that direction
  if target_winnr == current_winnr then
    return 0
  end

  return target_winnr
end

-- Navigate in the given direction
-- First tries to move within Neovim, falls back to ZTerm pane navigation
local function navigate(direction)
  local target_win = get_window_in_direction(direction)

  if target_win ~= 0 then
    -- There's a Neovim window in that direction, navigate to it
    vim.cmd("wincmd " .. ({
      left = "h",
      right = "l",
      up = "k",
      down = "j",
    })[direction])
  else
    -- No Neovim window, ask ZTerm to navigate
    zterm_navigate(direction)
  end
end

-- Public navigation functions
function M.navigate_left()
  navigate("left")
end

function M.navigate_right()
  navigate("right")
end

function M.navigate_up()
  navigate("up")
end

function M.navigate_down()
  navigate("down")
end

-- Setup function to configure keymaps
function M.setup(opts)
  -- Merge user options with defaults
  opts = opts or {}
  M.config = vim.tbl_deep_extend("force", M.config, opts)

  -- Set up keymaps
  local keymap_opts = { noremap = true, silent = true }

  if M.config.left then
    vim.keymap.set({"n", "t"}, M.config.left, M.navigate_left,
      vim.tbl_extend("force", keymap_opts, { desc = "Navigate left (window/pane)" }))
  end

  if M.config.right then
    vim.keymap.set({"n", "t"}, M.config.right, M.navigate_right,
      vim.tbl_extend("force", keymap_opts, { desc = "Navigate right (window/pane)" }))
  end

  if M.config.up then
    vim.keymap.set({"n", "t"}, M.config.up, M.navigate_up,
      vim.tbl_extend("force", keymap_opts, { desc = "Navigate up (window/pane)" }))
  end

  if M.config.down then
    vim.keymap.set({"n", "t"}, M.config.down, M.navigate_down,
      vim.tbl_extend("force", keymap_opts, { desc = "Navigate down (window/pane)" }))
  end
end

return M
