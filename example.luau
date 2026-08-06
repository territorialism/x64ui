--[[
  x64ui example script
  loads the library via the official loader, then demos the full chrome + controls
]]

local X64UI = loadstring(game:HttpGet("https://raw.githubusercontent.com/territorialism/x64ui/main/loader.luau"))()

if not X64UI then
  warn("[example] failed to load x64ui")
  return
end

if X64UI._IntegrityError then
  warn("[example] library integrity error: " .. tostring(X64UI._IntegrityError))
  return
end

local window = X64UI:CreateWindow({
  Title = "x64ui example",
  Width = 1020,
  Height = 660,
  SingleInstance = true,
})

if not window then
  warn("[example] CreateWindow failed — chrome integrity check did not pass")
  return
end

-- ==================== tabs ====================

local main = window:AddTab("Main")
local combat = main:AddLeftGroupbox("Combat")
local visuals = main:AddRightGroupbox("Visuals")

local settings = window:AddTab("Settings")
local configBox = settings:AddLeftGroupbox("Config")
local miscBox = settings:AddRightGroupbox("Misc")

-- ==================== combat ====================

combat:AddToggle("Aimbot", {
  Text = "Enable Aimbot",
  Default = false,
  Callback = function(newValue, oldValue)
    window:Log("Aimbot: " .. tostring(oldValue) .. " -> " .. tostring(newValue))
  end,
})

combat:AddSlider("FOV", {
  Text = "Aim FOV",
  Min = 10,
  Max = 500,
  Default = 150,
  Rounding = 0,
  Callback = function(newValue, oldValue)
    window:Log("FOV: " .. tostring(newValue))
  end,
})

combat:AddDropdown("TargetPart", {
  Text = "Target Part",
  Values = { "Head", "Torso", "HumanoidRootPart" },
  Default = "Head",
  Callback = function(newValue, oldValue)
    window:Log("Target: " .. tostring(newValue))
  end,
})

combat:AddDropdown("Weapons", {
  Text = "Weapons (multi + searchable)",
  Values = { "Rifle", "SMG", "Pistol", "Shotgun", "Sniper", "Melee", "Grenade" },
  Multi = true,
  Searchable = true,
  Default = {},
  Callback = function(newValue, oldValue)
    window:Log("Weapons selected: " .. tostring(#newValue))
  end,
})

combat:AddKeyPicker("AimKey", {
  Text = "Aim Key",
  Default = "E",
  Callback = function(newValue, oldValue)
    window:Log("Aim key: " .. tostring(newValue))
  end,
})

-- ==================== visuals ====================

visuals:AddToggle("ESP", {
  Text = "Enable ESP",
  Default = false,
  Callback = function(newValue, oldValue)
    window:Log("ESP: " .. tostring(newValue))
  end,
})

if visuals.AddColorPicker then
  visuals:AddColorPicker("ESPColor", {
    Text = "ESP Color",
    Default = Color3.fromRGB(0, 122, 204),
    Callback = function(newColor, oldColor)
      window:Log("ESP color changed")
    end,
  })
end

if visuals.AddNumericInput then
  visuals:AddNumericInput("MaxDistance", {
    Text = "Max Distance",
    Min = 0,
    Max = 2000,
    Default = 500,
    Callback = function(newValue, oldValue)
      window:Log("MaxDistance: " .. tostring(newValue))
    end,
  })
end

visuals:AddSlider("Opacity", {
  Text = "ESP Opacity",
  Min = 0,
  Max = 1,
  Default = 0.75,
  Rounding = 2,
  Callback = function(newValue, oldValue)
    window:Log("Opacity: " .. tostring(newValue))
  end,
})

visuals:AddInput("Tag", {
  Text = "Custom Tag",
  Placeholder = "optional tag text...",
  Default = "",
  Callback = function(newValue, oldValue)
    window:Log("Tag: " .. tostring(newValue))
  end,
})

-- ==================== settings / config ====================

configBox:AddKeyPicker("MenuKey", {
  Text = "Menu Toggle Key",
  Default = "RightShift",
  Callback = function(newValue, oldValue)
    local ok, keyCode = pcall(function()
      return Enum.KeyCode[newValue]
    end)
    if ok and keyCode then
      X64UI.MenuKeybind = keyCode
      window:Log("Menu keybind set to " .. tostring(newValue))
    end
  end,
})

configBox:AddButton({
  Text = "Save Config",
  Callback = function()
    if window.SaveConfig then
      window:SaveConfig("x64ui_example_config.json")
      window:Log("Config saved")
    end
  end,
})

configBox:AddButton({
  Text = "Load Config",
  Callback = function()
    if window.LoadConfig then
      window:LoadConfig("x64ui_example_config.json", {
        Silent = false,
        FireCallbacks = false,
        RecordHistory = false,
        ApplyLayout = true,
      })
      window:Log("Config loaded")
    end
  end,
})

configBox:AddButton({
  Text = "Notify Demo",
  Callback = function()
    X64UI:Notify({
      Title = "x64ui",
      Description = "Notifications work like this.",
      Time = 3,
    })
  end,
})

-- ==================== misc ====================

miscBox:AddLabel("Full chrome is always on:")
miscBox:AddLabel("menu bar · toolbar · tabs · log · status", true)

miscBox:AddButton({
  Text = "Toggle Console",
  Callback = function()
    if window.ToggleConsole then
      window:ToggleConsole()
    end
  end,
})

miscBox:AddButton({
  Text = "Undo Last",
  Callback = function()
    if window.History then
      window.History:UndoLast()
      window:Log("Undo")
    end
  end,
})

miscBox:AddButton({
  Text = "Redo Last",
  Callback = function()
    if window.History then
      window.History:RedoLast()
      window:Log("Redo")
    end
  end,
})

miscBox:AddButton({
  Text = "Unload",
  Callback = function()
    window:Destroy()
  end,
})

if miscBox.AddListBox then
  miscBox:AddListBox("Priority", {
    Text = "Priority List",
    Values = { "Closest", "Lowest HP", "Highest Threat" },
    Multi = false,
    Height = 80,
    Callback = function(newValue, oldValue)
      window:Log("Priority: " .. tostring(newValue))
    end,
  })
end

-- ==================== commands ====================

X64UI:RegisterCommand("Hello", {
  Description = "Print a hello message to the log",
  Keywords = { "hello", "test", "demo" },
  Callback = function()
    window:Log("Hello from the command palette (Ctrl+P)")
    X64UI:Notify({
      Title = "Command",
      Description = "Hello executed",
      Time = 2,
    })
  end,
})

X64UI:RegisterCommand("Clear Log", {
  Description = "Clear the log panel",
  Keywords = { "clear", "log" },
  Callback = function()
    if window.ClearLog then
      window:ClearLog()
    end
  end,
})

-- ==================== ready ====================

window:Log("x64ui example loaded · v" .. tostring(X64UI.Version or "?"))
window:SetStatus("Ready")

X64UI:Notify({
  Title = "x64ui example",
  Description = "Full chrome active. Press Ctrl+P for commands.",
  Time = 4,
})
