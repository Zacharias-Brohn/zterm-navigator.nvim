-- zterm-navigator: Seamless navigation between Neovim windows and ZTerm panes
--
-- When you press the navigation key (e.g., Alt+Arrow):
-- - If there's a Neovim window in that direction, navigate to it
-- - If not, send an OSC sequence to ZTerm to navigate to the next pane
--
-- Also provides vim-tpipeline-like statusline integration:
-- - Sends neovim's statusline to ZTerm's terminal statusline
-- - Updates on mode change, buffer change, cursor move, etc.

local M = {}

-- Track if statusline integration is active
M._statusline_enabled = false
M._statusline_augroup = nil

-- Default configuration
M.config = {
  -- Key mappings for navigation
  -- Set to false to disable a direction
  left = "<A-Left>",
  right = "<A-Right>",
  up = "<A-Up>",
  down = "<A-Down>",

  -- Statusline integration (vim-tpipeline style)
  statusline = {
    -- Enable statusline integration (auto-detected if nil)
    enabled = nil,
    -- Use neovim's statusline setting, or provide a custom one
    -- If nil, uses vim.o.statusline
    statusline = nil,
    -- Disable neovim's builtin statusline when sending to ZTerm
    hide_nvim_statusline = true,
  },
}

-- Send raw escape sequence to the terminal.
-- For navigation, io.write works fine. For statusline, we need a different approach
-- to avoid corruption when the content contains escape sequences.
local function send_to_tty(str)
  io.write(str)
  io.flush()
end

-- Send OSC 51 command to ZTerm for pane navigation
local function zterm_navigate(direction)
  -- OSC 51;navigate;<direction> ST
  -- Using BEL (\007) as string terminator for better compatibility
  local osc = string.format("\027]51;navigate;%s\007", direction)
  send_to_tty(osc)
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

-- ============================================================================
-- Statusline Integration (vim-tpipeline style)
-- ============================================================================

-- Check if we're running inside ZTerm
local function is_zterm()
  local term = vim.env.TERM or ""
  local term_program = vim.env.TERM_PROGRAM or ""
  local zterm_env = vim.env.ZTERM or ""
  -- ZTerm sets TERM to "zterm" or similar
  return term:match("zterm") ~= nil
    or term_program:match("[Zz]term") ~= nil
    or zterm_env ~= ""
end

-- Base64 encoding table
local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

-- Encode a string to base64
local function base64_encode(data)
  return ((data:gsub('.', function(x)
    local r, b = '', x:byte()
    for i = 8, 1, -1 do r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and '1' or '0') end
    return r
  end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
    if #x < 6 then return '' end
    local c = 0
    for i = 1, 6 do c = c + (x:sub(i, i) == '1' and 2 ^ (6 - i) or 0) end
    return b64chars:sub(c + 1, c + 1)
  end) .. ({ '', '==', '=' })[#data % 3 + 1])
end

-- Send statusline content to ZTerm via OSC 51
-- Content is base64-encoded to avoid escape sequence interpretation issues
local function send_statusline(content)
  if content and content ~= "" then
    -- Base64 encode to avoid neovim interpreting escape sequences
    local encoded = base64_encode(content)
    local osc = string.format("\027]51;statusline;b64:%s\007", encoded)
    send_to_tty(osc)
  else
    -- Empty statusline to clear
    local osc = "\027]51;statusline;\007"
    send_to_tty(osc)
  end
end

-- Get the rendered statusline with ANSI escape codes
local function get_rendered_statusline()
  -- Get the statusline string to evaluate
  local stl = M.config.statusline.statusline or vim.o.statusline

  -- If empty, try to get a sensible default
  if not stl or stl == "" then
    -- Build a simple default statusline
    stl = " %f %m%r%h%w %= %y [%l,%c] %P "
  end

  -- Use nvim_eval_statusline to get the rendered content with highlights
  local ok, result = pcall(vim.api.nvim_eval_statusline, stl, {
    winid = vim.api.nvim_get_current_win(),
    highlights = true,
    fillchar = " ",
  })

  if not ok then
    return nil
  end

  -- Convert highlights to ANSI escape codes
  local output = {}
  local str = result.str
  local highlights = result.highlights or {}

  -- Sort highlights by start position
  table.sort(highlights, function(a, b) return a.start < b.start end)

  local pos = 1
  for i, hl in ipairs(highlights) do
    -- Add any text before this highlight
    if hl.start > pos then
      -- No highlight for this segment, use reset
      table.insert(output, "\027[0m")
      table.insert(output, str:sub(pos, hl.start))
    end

    -- Determine the end of this highlight
    local hl_end
    if i < #highlights then
      hl_end = highlights[i + 1].start
    else
      hl_end = #str
    end

    -- Get the highlight colors
    local hl_info = vim.api.nvim_get_hl(0, { name = hl.group, link = false })
    local ansi = {}

    -- Foreground color
    if hl_info.fg then
      local r = bit.rshift(bit.band(hl_info.fg, 0xFF0000), 16)
      local g = bit.rshift(bit.band(hl_info.fg, 0x00FF00), 8)
      local b = bit.band(hl_info.fg, 0x0000FF)
      table.insert(ansi, string.format("38;2;%d;%d;%d", r, g, b))
    end

    -- Background color
    if hl_info.bg then
      local r = bit.rshift(bit.band(hl_info.bg, 0xFF0000), 16)
      local g = bit.rshift(bit.band(hl_info.bg, 0x00FF00), 8)
      local b = bit.band(hl_info.bg, 0x0000FF)
      table.insert(ansi, string.format("48;2;%d;%d;%d", r, g, b))
    end

    -- Bold
    if hl_info.bold then
      table.insert(ansi, "1")
    end

    -- Italic
    if hl_info.italic then
      table.insert(ansi, "3")
    end

    -- Underline
    if hl_info.underline then
      table.insert(ansi, "4")
    end

    -- Build the ANSI sequence
    if #ansi > 0 then
      table.insert(output, "\027[" .. table.concat(ansi, ";") .. "m")
    else
      table.insert(output, "\027[0m")
    end

    -- Add the highlighted text
    table.insert(output, str:sub(hl.start + 1, hl_end))
    pos = hl_end + 1
  end

  -- Add any remaining text
  if pos <= #str then
    table.insert(output, "\027[0m")
    table.insert(output, str:sub(pos))
  end

  -- Reset at the end
  table.insert(output, "\027[0m")

  return table.concat(output)
end

-- Update the ZTerm statusline
local function update_statusline()
  if not M._statusline_enabled then
    return
  end

  local content = get_rendered_statusline()
  if content then
    send_statusline(content)
  end
end

-- Saved laststatus value to restore on disable
M._saved_laststatus = nil

-- Enable statusline integration
function M.enable_statusline()
  if M._statusline_enabled then
    return
  end

  M._statusline_enabled = true

  -- Hide neovim's statusline if configured
  if M.config.statusline.hide_nvim_statusline then
    M._saved_laststatus = vim.o.laststatus
    vim.o.laststatus = 0
  end

  -- Create autocommands for statusline updates
  M._statusline_augroup = vim.api.nvim_create_augroup("ZTermStatusline", { clear = true })

  -- Events that should trigger a statusline update
  local events = {
    "ModeChanged",      -- Mode changes (normal, insert, visual, etc.)
    "BufEnter",         -- Entering a buffer
    "BufWritePost",     -- After writing a file
    "FileChangedShellPost",
    "WinEnter",         -- Entering a window
    "CursorMoved",      -- Cursor moved (for position info)
    "CursorMovedI",     -- Cursor moved in insert mode
    "DiagnosticChanged", -- LSP diagnostics changed
  }

  vim.api.nvim_create_autocmd(events, {
    group = M._statusline_augroup,
    callback = function()
      -- Defer slightly to batch rapid updates
      vim.defer_fn(update_statusline, 10)
    end,
  })

  -- Initial update
  update_statusline()
end

-- Disable statusline integration
function M.disable_statusline()
  if not M._statusline_enabled then
    return
  end

  M._statusline_enabled = false

  -- Remove autocommands
  if M._statusline_augroup then
    vim.api.nvim_del_augroup_by_id(M._statusline_augroup)
    M._statusline_augroup = nil
  end

  -- Restore neovim's statusline
  if M._saved_laststatus then
    vim.o.laststatus = M._saved_laststatus
    M._saved_laststatus = nil
  end
  -- Note: ZTerm automatically clears the custom statusline when neovim exits
end

-- Toggle statusline integration
function M.toggle_statusline()
  if M._statusline_enabled then
    M.disable_statusline()
  else
    M.enable_statusline()
  end
end

-- ============================================================================
-- Setup
-- ============================================================================

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

  -- Set up statusline integration
  local statusline_enabled = M.config.statusline.enabled
  if statusline_enabled == nil then
    -- Auto-detect: enable if running in ZTerm
    statusline_enabled = is_zterm()
  end

  if statusline_enabled then
    -- Defer to ensure neovim is fully loaded
    vim.defer_fn(function()
      M.enable_statusline()
    end, 100)
  end
end

return M
