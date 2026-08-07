# x64ui

a desktop-only luau ui library

## usage

```luau
loadstring(game:HttpGet("https://raw.githubusercontent.com/territorialism/x64ui/main/loader.luau"))()
```

or directly:

```luau
loadstring(game:HttpGet("https://raw.githubusercontent.com/territorialism/x64ui/main/main.luau"))()
```

the loader exports the library to `getgenv().X64UI` and `shared.X64UI`.

## requirements

- desktop environment (keyboard and mouse required)
- sunc compatible executor (supports `request` with pascalcase `Url` and `Method`)
- fallback to `game:HttpGet` if `request` is unavailable

## api

### x64ui:CreateWindow(options)
creates a new window.

```luau
local Window = X64UI:CreateWindow({
    Name = "my window",
    Title = "my title",
    Width = 1100,
    Height = 680,
})
```

### window:AddTab(name)
adds a tab to the window.

```luau
local Tab = Window:AddTab("main")
```

### tab:AddLeftGroupbox(title) / tab:AddRightGroupbox(title)
adds a groupbox to the left or right pane.

```luau
local Groupbox = Tab:AddLeftGroupbox("settings")
```

### controls

all controls support standard callbacks `(newValue, oldValue)`.

#### toggle
```luau
local Toggle = Groupbox:AddToggle("MyToggle", {
    Text = "my toggle",
    Default = false,
    Callback = function(New, Old)
        print(New, Old)
    end,
})
```

#### slider
```luau
local Slider = Groupbox:AddSlider("MySlider", {
    Text = "my slider",
    Min = 0,
    Max = 100,
    Default = 50,
    Rounding = 1,
    Suffix = "ms",
    Callback = function(New, Old)
        print(New, Old)
    end,
})
```

#### dropdown (single + multi, searchable)
```luau
local Dropdown = Groupbox:AddDropdown("MyDropdown", {
    Text = "my dropdown",
    Values = {"a", "b", "c"},
    Default = 1,
    Multi = false,
    Searchable = false,
    Callback = function(New, Old)
        print(New, Old)
    end,
})
```

#### colorpicker
```luau
local ColorPicker = Groupbox:AddColorPicker("MyColor", {
    Text = "my color",
    Default = Color3.fromRGB(255, 0, 0),
    Callback = function(New, Old)
        print(New, Old)
    end,
})
```

#### keypicker
supports modes: `Toggle`, `Hold`, `Press`, `Always`.

```luau
local KeyPicker = Groupbox:AddKeyPicker("MyKey", {
    Text = "my key",
    Default = "None",
    Mode = "Hold",
    Callback = function(New, Old)
        print(New, Old)
    end,
})
```

## config

save and load configurations. `NoSave = true` on a control excludes it.

```luau
X64UI:SaveConfig()
X64UI:LoadConfig({
    Silent = false,
    FireCallbacks = true,
    RecordHistory = true,
    ApplyLayout = true,
})
```

## theming

```luau
X64UI:SetThemeKey("Accent", Color3.fromRGB(0, 122, 204))
X64UI:ApplyTheme({ ... })
```

## lifecycle

```luau
X64UI:Unload() -- destroys all windows, clears globals
```
