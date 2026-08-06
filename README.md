# X64UI

x64dbg-inspired ui library for scripts built entirely with native gui instances

desktop only. i made this for myself and figured other people might find it useful

## Loadstring

```lua
local X64UI = loadstring(game:HttpGet("https://raw.githubusercontent.com/territorialism/x64ui/main/loader.luau"))()
```

The loader handles executor-specific HTTP wrappers automatically (`syn.request`, `http.request`, `http_request`, `request`, Fluxus) and falls back to `game:HttpGet`. After a successful load it exports the library to `getgenv().X64UI` (or `shared.X64UI`) so other scripts in the same executor can access it.

## Quick Start

```lua
local X64UI = loadstring(game:HttpGet("https://raw.githubusercontent.com/territorialism/x64ui/main/loader.luau"))()

local window = X64UI:CreateWindow({
  Title = "My Script",
  Width = 1020,
  Height = 660,
  SingleInstance = true, -- default true; set false to allow multiple windows
})

local tab = window:AddTab("Main")
local left = tab:AddLeftGroupbox("Features")

left:AddToggle("Aimbot", {
  Text = "Enable Aimbot",
  Default = false,
  Callback = function(newValue, oldValue)
    print(oldValue, "->", newValue)
  end,
})

left:AddSlider("FOV", {
  Text = "FOV Radius",
  Min = 10,
  Max = 500,
  Default = 150,
  Rounding = 0,
  Callback = function(newValue, oldValue)
    print(oldValue, "->", newValue)
  end,
})

left:AddDropdown("Part", {
  Text = "Target Part",
  Values = { "Head", "Torso", "HumanoidRootPart" },
  Default = "Head",
  Callback = function(newValue, oldValue)
    print(oldValue, "->", newValue)
  end,
})
```

## Controls

Every tab splits into a left and right column. Add groupboxes to either side, then fill them with controls.

Callbacks for value controls receive `(newValue, oldValue)`. Buttons receive no args.

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
  Callback = function(newValue, oldValue) print(oldValue, "->", newValue) end,
})

toggle:SetValue(true)
toggle:GetValue()
toggle:SetVisible(true)
toggle:SetDisabled(false)
toggle:SetReadOnly(false)
```

### Sliders

```lua
local slider = group:AddSlider("MySlider", {
  Text = "Speed",
  Min = 0,
  Max = 100,
  Default = 50,
  Rounding = 0,
  Callback = function(newValue, oldValue) print(oldValue, "->", newValue) end,
})

slider:SetValue(75)
slider:GetValue()
```

### Dropdowns

Supports single-select, multi-select, and searchable lists.

```lua
local dropdown = group:AddDropdown("MyDropdown", {
  Text = "Mode",
  Values = { "Easy", "Normal", "Hard" },
  Default = "Normal",
  Searchable = false,
  Multi = false,
  Callback = function(newValue, oldValue) print(oldValue, "->", newValue) end,
})

-- multi + searchable
group:AddDropdown("Weapons", {
  Text = "Weapons",
  Values = { "Rifle", "SMG", "Pistol", "Shotgun" },
  Multi = true,
  Searchable = true,
  Default = {},
  Callback = function(selected) print(#selected, "selected") end,
})
```

### Text Inputs

```lua
local input = group:AddInput("MyInput", {
  Text = "Username",
  Placeholder = "Type here...",
  Default = "",
  Callback = function(newValue, oldValue) print(oldValue, "->", newValue) end,
})
```

### Key Pickers

```lua
local keybind = group:AddKeyPicker("MyKey", {
  Text = "Toggle Key",
  Default = "Q",
  Callback = function(newValue, oldValue) print("Key set to:", newValue) end,
})
```

### Color Picker

```lua
group:AddColorPicker("ESPColor", {
  Text = "ESP Color",
  Default = Color3.fromRGB(0, 122, 204),
  Callback = function(newColor, oldColor) end,
})
```

### Numeric Input

```lua
group:AddNumericInput("MaxDist", {
  Text = "Max Distance",
  Min = 0,
  Max = 2000,
  Default = 500,
  Callback = function(newValue, oldValue) end,
})
```

### List Box

```lua
group:AddListBox("Priority", {
  Text = "Priority",
  Values = { "Closest", "Lowest HP", "Highest Threat" },
  Multi = false,
  Height = 100,
  Callback = function(newValue, oldValue) end,
})
```

### Table / Tree

```lua
group:AddTable("Scores", {
  Text = "Scores",
  Columns = { "Name", "Kills", "Deaths" },
  Rows = {
    { Name = "Player1", Kills = 12, Deaths = 3 },
    { Name = "Player2", Kills = 8, Deaths = 5 },
  },
  Height = 120,
})

group:AddTree("Hierarchy", {
  Text = "Folders",
  Nodes = {
    { Text = "Root", Children = {
      { Text = "Child A" },
      { Text = "Child B", Children = { { Text = "Leaf" } } },
    }},
  },
  Height = 140,
})
```

### Dividers

```lua
group:AddDivider()
```

## Window Methods

```lua
window:Log("Message to console")
window:ClearLog()
window:SetStatus("Ready")
window:SaveConfig("config.json")
window:LoadConfig("config.json", {
  Silent = false,
  FireCallbacks = false,
  RecordHistory = false,
  ApplyLayout = true,
})
window:Destroy()
window:Show()
window:Hide()
window:Toggle()
window:SetMinimized(true)
window:SetMaximized(true)
```

`X64UI.Windows` holds all live windows. `X64UI.ActiveWindow` is the focused one.

`CreateWindow({ SingleInstance = false })` allows multiple windows at once.

## Command Palette

Press `Ctrl+P` to open the command palette. Type to search, arrow keys to navigate, Enter to execute.

```lua
X64UI:RegisterCommand("Teleport", {
  Description = "Teleport to nearest player",
  Keywords = { "tp", "teleport", "move" },
  Callback = function()
    -- your code here
  end,
})
```

## Notifications

```lua
X64UI:Notify({
  Title = "Alert",
  Description = "Something happened.",
  Time = 5,
})
```

Visible notifications are capped; older ones are removed first.

## Dialogs

```lua
X64UI:Dialog({
  Title = "Confirm",
  Message = "Are you sure?",
})
-- or window:ShowModal({ Title, Message, ConfirmText, CancelText, Callback })
```

## Hotkeys

| Key | Action |
|-----|--------|
| `RightShift` | Toggle window visibility (change with `X64UI.MenuKeybind`) |
| `Ctrl+P` | Open/close command palette |
| Double-click title bar | Maximize / restore |
| Esc | Close open dropdown / command palette / cancel key capture |

## Config System

`window:SaveConfig(path)` writes named toggles/options (and layout) via the executor filesystem (`Platform` wrappers).

`window:LoadConfig(path, opts)` supports:

- `Silent` — suppress log message
- `FireCallbacks` — whether control callbacks fire (default true unless you set false)
- `RecordHistory` — wrap apply in a history transaction
- `ApplyLayout` — restore size/position

## Undo / Redo

Tracked via `window.History:UndoLast()` / `RedoLast()`. Transactions (`BeginTransaction` / `EndTransaction`) group multiple changes.

## Theme

Override before `CreateWindow`:

```lua
X64UI.Theme.Background = Color3.fromRGB(10, 10, 10)
X64UI.Theme.Accent = Color3.fromRGB(255, 0, 128)
```

## Architecture

- **Registry** — per-window control registry (no global Options/Toggles pollution)
- **Signal bus** — custom event system
- **Maid cleanup** — connections, instances, tasks destroyed together
- **Observable state** — State objects with change signals
- **History stack** — undo/redo with optional transactions
- **Platform** — file ops go through Platform wrappers
- **Glyphs** — safe unicode for check/arrow/grip
- **Viewport clamping** — window stays on screen
- **No CanvasGroup on main window** — avoids 1024×1024 texture blur when maximized

## Executor Compatibility

Works on Luau executors with basic HTTP. Loader auto-detects common request APIs and falls back to `game:HttpGet`.

If `writefile` / `readfile` are missing, config save/load logs and skips.

## Known Limitations

- Desktop only. No touch/mobile support.
- CanvasGroup used for notifications only (small, so texture limit is fine).
- Dropdown lists parented to root ScreenGui so they render above content.
- Command palette is simple substring search, not full multi-word fuzzy ranking.

## License

MIT. Do whatever you want with it.
