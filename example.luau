--[[
  X64UI Example Script
  Run the loader first, then this.
]]

-- The loader already fetched and stored X64UI globally.
local X64UI = getgenv and getgenv().X64UI or shared.X64UI

if not X64UI then
  warn("[X64UI] Library not loaded. Run the loader first.")
  return
end

-- ==================== CREATE WINDOW ====================

local window = X64UI:CreateWindow({
  Title = "My Game Hub",
  Width = 1020,
  Height = 660,
})

local main = window:AddTab("Main")
local left = main:AddLeftGroupbox("Combat")
local right = main:AddRightGroupbox("Settings")

-- ==================== CONTROLS ====================

left:AddToggle("Aimbot", {
  Text = "Enable Aimbot",
  Default = false,
  Callback = function(value)
    print("Aimbot:", value)
  end,
})

left:AddSlider("FOV", {
  Text = "Aim FOV",
  Min = 10,
  Max = 500,
  Default = 150,
  Rounding = 0,
  Callback = function(value)
    print("FOV:", value)
  end,
})

left:AddDropdown("TargetPart", {
  Text = "Target Part",
  Values = { "Head", "Torso", "HumanoidRootPart" },
  Default = "Head",
  Callback = function(value)
    print("Target Part:", value)
  end,
})

right:AddInput("ConfigName", {
  Text = "Config Name",
  Placeholder = "default",
  Callback = function(value)
    print("Config Name:", value)
  end,
})

right:AddKeyPicker("MenuKey", {
  Text = "Menu Toggle Key",
  Default = "RightShift",
  Callback = function(value)
    local ok, keyCode = pcall(function()
      return Enum.KeyCode[value]
    end)

    if ok then
      X64UI.MenuKeybind = keyCode
    end
  end,
})

right:AddButton({
  Text = "Save Config",
  Callback = function()
    window:SaveConfig("mygame_config.json")
  end,
})

right:AddButton({
  Text = "Load Config",
  Callback = function()
    window:LoadConfig("mygame_config.json")
  end,
})

right:AddButton({
  Text = "Unload",
  Callback = function()
    window:Destroy()
  end,
})

-- ==================== CUSTOM COMMANDS ====================

X64UI:RegisterCommand("Kill All", {
  Description = "Eliminate all targets",
  Keywords = { "kill", "eliminate", "combat" },
  Callback = function()
    print("Kill All executed")
  end,
})

window:Log("My Game Hub loaded.")
window:SetStatus("Ready")
