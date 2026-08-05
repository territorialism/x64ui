# X64UI

x64dbg-inspired ui library for scripts built entirely with native gui instances

desktop only. i made this for myself and figured other people might find it useful

## Loadstring

```lua
local X64UI = loadstring(game:HttpGet("https://raw.githubusercontent.com/territorialism/x64ui/main/loader.luau"))()
```

The loader handles executor-specific HTTP wrappers automatically (Synapse, Fluxus, Krnl, Wave, etc.) and falls back to `game:HttpGet`. It also exports the library to `getgenv().X64UI` so other scripts in the same executor can access it.

## Quick Start

```lua
local X64UI = loadstring(game:HttpGet("https://raw.githubusercontent.com/territorialism/x64ui/main/loader.luau"))()

local window = X64UI:CreateWindow({
  Title = "My Script",
  Width = 1020,
  Height = 660,
})

local tab = window:AddTab("Main")
local left = tab:AddLeftGroupbox("Features")

left:AddToggle("Aimbot", {
  Text = "Enable Aimbot",
  Default = false,
  Callback = function(v) print(v) end,
})

left:AddSlider("FOV", {
  Text = "FOV Radius",
  Min = 10,
  Max = 500,
  Default = 150,
  Rounding = 0,
  Callback = function(v) print(v) end,
})

left:AddDropdown("Part", {
  Text = "Target Part",
  Values = { "Head", "Torso", "HumanoidRootPart" },
  Default = "Head",
  Callback = function(v) print(v) end,
})
```

## Controls

Every tab splits into a left and right column. Add groupboxes to either side, then fill them with controls.

### Labels

```lua
group:AddLabel("Some descriptive text")
group:AddLabel("Wrapped text that can span multiple lines.", true)
```

### Buttons

```lua
group:AddButton({
  Text = "Click Me",
  Callback = function()
    print("Clicked!")
  end,
})
```

### Toggles

```lua
local toggle = group:AddToggle("MyToggle", {
  Text = "Enable Feature",
  Default = false,
  Callback = function(v) print(v) end,
})

toggle:SetValue(true)   -- set programmatically
toggle:GetValue()        -- read current value
```

### Sliders

```lua
local slider = group:AddSlider("MySlider", {
  Text = "Speed",
  Min = 0,
  Max = 100,
  Default = 50,
  Rounding = 0,          -- decimal places (0 = integers)
  Callback = function(v) print(v) end,
})

slider:SetValue(75)
slider:GetValue()
```

### Dropdowns

```lua
local dropdown = group:AddDropdown("MyDropdown", {
  Text = "Mode",
  Values = { "Easy", "Normal", "Hard" },
  Default = "Normal",
  Callback = function(v) print(v) end,
})

dropdown:SetValue("Hard")
dropdown:GetValue()
```

### Text Inputs

```lua
local input = group:AddInput("MyInput", {
  Text = "Username",
  Placeholder = "Type here...",
  Default = "",
  Callback = function(v) print(v) end,
})

input:SetValue("admin")
input:GetValue()
```

### Key Pickers

```lua
local keybind = group:AddKeyPicker("MyKey", {
  Text = "Toggle Key",
  Default = "Q",
  Callback = function(v) print("Key set to:", v) end,
})

keybind:SetValue("E")
keybind:GetValue()
```

### Dividers

```lua
group:AddDivider()
```

## Window Methods

```lua
window:Log("Message to console")        -- write to the log panel
window:ClearLog()                        -- clear the log panel
window:SetStatus("Ready")                -- update the status bar
window:SaveConfig("config.json")         -- save all toggle/slider/input values
window:LoadConfig("config.json")         -- load saved values
window:Destroy()                         -- close and clean up everything
```

## Command Palette

Press `Ctrl+P` to open the command palette. Type to fuzzy-search registered commands, use arrow keys to navigate, press Enter to execute.

Register your own commands:

```lua
X64UI:RegisterCommand("Teleport", {
  Description = "Teleport to nearest player",
  Keywords = { "tp", "teleport", "move" },
  Callback = function()
    -- your code here
  end,
})
```

Built-in commands: toggle window, maximize, minimize, undo/redo, toggle console, toggle status bar, clear log, save/load config.

## Notifications

```lua
X64UI:Notify({
  Title = "Alert",
  Description = "Something happened.",
  Time = 5,  -- seconds (default: 3)
})
```

## Hotkeys

| Key | Action |
|-----|--------|
| `RightShift` | Toggle window visibility (change with `X64UI.MenuKeybind`) |
| `Ctrl+P` | Open/close command palette |
| Double-click title bar | Maximize / restore |

## Config System

`window:SaveConfig()` writes all named toggles, sliders, dropdowns, inputs, and keybinds to a JSON file using the executor's `writefile`. `window:LoadConfig()` reads them back and applies the values silently (no callbacks fire, no history entries created).

Config files are stored in your executor's workspace folder.

## Undo / Redo

Every toggle, slider, dropdown, input, and keybind change is tracked in an undo stack (up to 150 entries). Access it through `window.History:UndoLast()` and `window.History:RedoLast()`. The command palette has these built in, or you can bind them to buttons.

## Theme

All colors are defined in `X64UI.Theme`. Override them before calling `CreateWindow` if you want a different look:

```lua
X64UI.Theme.Background = Color3.fromRGB(10, 10, 10)
X64UI.Theme.Accent = Color3.fromRGB(255, 0, 128)
```

## Architecture

- **Signal bus** — custom event system, no RBXScriptSignal dependency
- **Maid cleanup** — all connections, instances, and tasks tracked and destroyed together
- **Observable state** — controls backed by State objects with change signals
- **History stack** — undo/redo for all user interactions
- **Viewport clamping** — window stays on screen, resize grip respects screen bounds
- **No CanvasGroup on main window** — avoids the engine's 1024x1024 texture blur bug when maximized

## Executor Compatibility

Works on anything with a Luau runtime and basic `game:HttpGet`. Tested on Synapse X, ScriptWare, Fluxus, Krnl, and Wave. The loader auto-detects executor-specific HTTP wrappers.

If your executor doesn't support `writefile`/`readfile`, the config system will log a message and skip silently.

## Known Limitations

- Desktop only. No touch/mobile support and I have no plans to add it.
- `CanvasGroup` is used for notifications (they're small so the texture limit doesn't matter). The main window uses a plain `Frame` to avoid blur.
- Dropdown lists are children of the root ScreenGui so they can render above other elements. If you create multiple windows, dropdowns from all of them share the same parent.
- The command palette only supports single-keyword fuzzy matching, not multi-word queries.

## License

MIT. Do whatever you want with it.
```

---

**Commit message for the full overhaul:**

```
fix(all): fix 8 bugs, remove demo from library, rewrite docs

- loader: add executor HTTP wrapper chain, add loadstring error capture
- loader: export to getgenv/shared after loading
- main: add unpack polyfill for older executors
- main: fix getParent() crash when LocalPlayer not loaded
- main: fix viewport clamping (add GuiInset offset)
- main: fix drag snapping (use GetMouseLocation consistently)
- main: fix CanvasGroup blur when maximized (use Frame instead)
- main: fix corner resize exceeding viewport (dynamic limits)
- main: cap ZIndex at 32767 (was 999999)
- main: remove built-in demo from library file
- example: add nil safety checks, add notification demo
- readme: complete rewrite with full API docs
```
