# zterm-navigator

Seamless navigation between Neovim windows and ZTerm terminal panes.

## Features

- Navigate between Neovim splits using `Alt+Arrow` keys
- When there's no Neovim window in that direction, automatically navigate to the next ZTerm pane
- Works bidirectionally - you can navigate from shell to Neovim and back

## Requirements

- [ZTerm](https://github.com/yourusername/zterm) terminal emulator
- Neovim 0.7+

## Installation

### Using lazy.nvim

```lua
{
  "yourusername/zterm-navigator",
  config = function()
    require("zterm-navigator").setup()
  end,
}
```

### Using packer.nvim

```lua
use {
  "yourusername/zterm-navigator",
  config = function()
    require("zterm-navigator").setup()
  end,
}
```

## Configuration

```lua
require("zterm-navigator").setup({
  -- Default keybindings (set to false to disable)
  left = "<A-Left>",
  right = "<A-Right>",
  up = "<A-Up>",
  down = "<A-Down>",
})
```

## ZTerm Configuration

Make sure your ZTerm config (`~/.config/zterm/config.json`) has matching keybindings:

```json
{
  "keybindings": {
    "focus_pane_up": "alt+up",
    "focus_pane_down": "alt+down",
    "focus_pane_left": "alt+left",
    "focus_pane_right": "alt+right"
  },
  "pass_keys_to_programs": ["nvim", "vim"]
}
```

## How It Works

1. When you press `Alt+Arrow` in Neovim:
   - The plugin checks if there's a Neovim window in that direction
   - If yes, it navigates to that window using `wincmd`
   - If no, it sends an OSC 51 escape sequence to ZTerm

2. ZTerm receives the OSC sequence and navigates to the neighboring pane

3. When you press `Alt+Arrow` in a shell (non-Neovim):
   - ZTerm checks `pass_keys_to_programs` - since it's not Neovim, ZTerm handles navigation directly

## Protocol

The plugin communicates with ZTerm using OSC (Operating System Command) sequences:

```
OSC 51 ; navigate ; <direction> BEL
```

Where `<direction>` is one of: `up`, `down`, `left`, `right`.

## License

MIT
