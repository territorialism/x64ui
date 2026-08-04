# X64UI

x64dbg ui library

## Loadstring

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/territorialism/x64ui/main/loader.lua"))()
```

## Example

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/territorialism/x64ui/main/loader.lua"))()

local X64UI = getgenv and getgenv().X64UI or shared.X64UI

local window = X64UI:CreateWindow({ Title = "My Hub" })
local tab = window:AddTab("Main")
local group = tab:AddLeftGroupbox("Controls")

group:AddToggle("MyToggle", {
  Text = "Enable Feature",
  Default = false,
  Callback = function(value)
    print("Toggle:", value)
  end,
})
```

## Hotkeys

| Key | Action |
|-----|--------|
| `RightShift` | Toggle UI visibility |
| `Ctrl+P` | Open command palette |
| Double-click titlebar | Maximize / Restore |
