# x64ui

x64dbg-inspired ui library for scripts built entirely with native gui instances

desktop only. i made this for myself and figured other people might find it useful

## loadstring

```lua
local X64UI = loadstring(game:HttpGet("https://raw.githubusercontent.com/territorialism/x64ui/main/loader.luau"))()
```

the loader uses the sunc-standard `request` global when available, otherwise falls back to `game:HttpGet`. after a successful load it exports the library to `getgenv().X64UI` (or `shared.X64UI`) so other scripts in the same session can access it.

## quick start

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

## controls

every tab splits into a left and right column. add groupboxes to either side, then fill them with controls.

callbacks for value controls receive `(newValue, oldValue)`. buttons receive no args.

### labels

```lua
group:AddLabel("Some descriptive text")
group:AddLabel("Wrapped text that can span multiple lines.", true)
```

### buttons

```lua
group:AddButton({
  Text = "Click Me",
  Callback = function()
    print("Clicked!")
  end,
})
```

### toggles

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

### sliders

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

### dropdowns

supports single-select, multi-select, and searchable lists.

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

### text inputs

```lua
local input = group:AddInput("MyInput", {
  Text = "Username",
  Placeholder = "Type here...",
  Default = "",
  Callback = function(newValue, oldValue) print(oldValue, "->", newValue) end,
})
```

### key pickers

```lua
local keybind = group:AddKeyPicker("MyKey", {
  Text = "Toggle Key",
  Default = "Q",
  Callback = function(newValue, oldValue) print("Key set to:", newValue) end,
})
```

### color picker

```lua
group:AddColorPicker("ESPColor", {
  Text = "ESP Color",
  Default = Color3.fromRGB(0, 122, 204),
  Callback = function(newColor, oldColor) end,
})
```

### numeric input

```lua
group:AddNumericInput("MaxDist", {
  Text = "Max Distance",
  Min = 0,
  Max = 2000,
  Default = 500,
  Callback = function(newValue, oldValue) end,
})
```

### list box

```lua
group:AddListBox("Priority", {
  Text = "Priority",
  Values = { "Closest", "Lowest HP", "Highest Threat" },
  Multi = false,
  Height = 100,
  Callback = function(newValue, oldValue) end,
})
```

### table / tree

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

### dividers

```lua
group:AddDivider()
```

## window methods

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

## command palette

press `Ctrl+P` to open the command palette. type to search, arrow keys to navigate, enter to execute.

```lua
X64UI:RegisterCommand("Teleport", {
  Description = "Teleport to nearest player",
  Keywords = { "tp", "teleport", "move" },
  Callback = function()
    -- your code here
  end,
})
```

## notifications

```lua
X64UI:Notify({
  Title = "Alert",
  Description = "Something happened.",
  Time = 5,
})
```

visible notifications are capped; older ones are removed first.

## dialogs

```lua
X64UI:Dialog({
  Title = "Confirm",
  Message = "Are you sure?",
})
-- or window:ShowModal({ Title, Message, ConfirmText, CancelText, Callback })
```

## hotkeys

| key | action |
|-----|--------|
| `RightShift` | toggle window visibility (change with `X64UI.MenuKeybind`) |
| `Ctrl+P` | open/close command palette |
| double-click title bar | maximize / restore |
| esc | close open dropdown / command palette / cancel key capture |

## config system

`window:SaveConfig(path)` writes named toggles/options (and layout) via the filesystem (`Platform` wrappers).

`window:LoadConfig(path, opts)` supports:

- `Silent` — suppress log message
- `FireCallbacks` — whether control callbacks fire (default true unless you set false)
- `RecordHistory` — wrap apply in a history transaction
- `ApplyLayout` — restore size/position

## undo / redo

tracked via `window.History:UndoLast()` / `RedoLast()`. transactions (`BeginTransaction` / `EndTransaction`) group multiple changes.

## theme

override before `CreateWindow`:

```lua
X64UI.Theme.Background = Color3.fromRGB(10, 10, 10)
X64UI.Theme.Accent = Color3.fromRGB(255, 0, 128)
```

## architecture

- **registry** — per-window control registry (no global options/toggles pollution)
- **signal bus** — custom event system
- **maid cleanup** — connections, instances, tasks destroyed together
- **observable state** — state objects with change signals
- **history stack** — undo/redo with optional transactions
- **platform** — file ops go through platform wrappers
- **glyphs** — safe unicode for check/arrow/grip
- **viewport clamping** — window stays on screen
- **no canvasgroup on main window** — avoids 1024×1024 texture blur when maximized

## compatibility

requires a luau environment with either the sunc-standard `request` global or `game:HttpGet`. file apis (`writefile` / `readfile`) are optional; config save/load logs and skips if they are missing.

## known limitations

- desktop only. no touch/mobile support.
- canvasgroup used for notifications only (small, so texture limit is fine).
- dropdown lists parented to root screenGui so they render above content.
- command palette is simple substring search, not full multi-word fuzzy ranking.

## license

mit. do whatever you want with it.
