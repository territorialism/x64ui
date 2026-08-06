--[[
  X64UI Example Script (v5.1 API)

  Load via loader.luau first, or paste loader + main above this block.
]]

local X64UI = (getgenv and getgenv().X64UI)
  or (shared and shared.X64UI)

if not X64UI then
  warn("[X64UI] Library not loaded. Run loader.luau first.")
  return
end

local window = X64UI:CreateWindow({
  Title = "My Game Hub",
  Width = 1020,
  Height = 660,
  SingleInstance = true,
})

local main = window:AddTab("Main")
local left = main:AddLeftGroupbox("Combat")
local right = main:AddRightGroupbox("Settings")

-- ==================== BASIC CONTROLS ====================

left:AddToggle("Aimbot", {
  Text = "Enable Aimbot",
  Default = false,
  Callback = function(newValue, oldValue)
    print("Aimbot:", oldValue, "->", newValue)
  end,
})

left:AddSlider("FOV", {
  Text = "Aim FOV",
  Min = 10,
  Max = 500,
  Default = 150,
  Rounding = 0,
  Callback = function(newValue, oldValue)
    print("FOV:", oldValue, "->", newValue)
  end,
})

left:AddDropdown("TargetPart", {
  Text = "Target Part",
  Values = { "Head", "Torso", "HumanoidRootPart" },
  Default = "Head",
  Callback = function(newValue, oldValue)
    print("Target Part:", oldValue, "->", newValue)
  end,
})

left:AddDropdown("Weapons", {
  Text = "Weapons (multi + searchable)",
  Values = { "Rifle", "SMG", "Pistol", "Shotgun", "Sniper", "Melee", "Grenade" },
  Multi = true,
  Searchable = true,
  Default = {},
  Callback = function(newValue, oldValue)
    print("Weapons selected:", #newValue)
  end,
})

left:AddInput("Note", {
  Text = "Note",
  Placeholder = "Write something here...",
  Callback = function(newValue, oldValue)
    print("Note:", oldValue, "->", newValue)
  end,
})

-- ==================== PHASE 5 CONTROLS ====================

right:AddColorPicker("ESPColor", {
  Text = "ESP Color",
  Default = Color3.fromRGB(0, 122, 204),
  Callback = function(newColor, oldColor)
    print("ESP Color changed")
  end,
})

right:AddNumericInput("MaxDistance", {
  Text = "Max Distance",
  Min = 0,
  Max = 2000,
  Default = 500,
  Callback = function(newValue, oldValue)
    print("MaxDistance:", oldValue, "->", newValue)
  end,
})

right:AddListBox("Priority", {
  Text = "Priority List",
  Values = { "Closest", "Lowest HP", "Highest Threat" },
  Multi = false,
  Height = 80,
  Callback = function(newValue, oldValue)
    print("Priority:", newValue)
  end,
})

right:AddKeyPicker("MenuKey", {
  Text = "Menu Toggle Key",
  Default = "RightShift",
  Callback = function(newValue, oldValue)
    local ok, keyCode = pcall(function()
      return Enum.KeyCode[newValue]
    end)
    if ok then
      X64UI.MenuKeybind = keyCode
    end
  end,
})

right:AddDivider()

right:AddButton({
  Text = "Save Config",
  Callback = function()
    window:SaveConfig("mygame_config.json")
  end,
})

right:AddButton({
  Text = "Load Config",
  Callback = function()
    window:LoadConfig("mygame_config.json", {
      Silent = false,
      FireCallbacks = false,
      RecordHistory = false,
      ApplyLayout = true,
    })
  end,
})

right:AddButton({
  Text = "Show Dialog",
  Callback = function()
    if X64UI.Dialog then
      X64UI:Dialog({
        Title = "Confirm",
        Message = "This is a modal dialog example.",
      })
    elseif window.ShowModal then
      window:ShowModal({
        Title = "Confirm",
        Message = "This is a modal dialog example.",
        Callback = function(ok)
          print("Dialog result:", ok)
        end,
      })
    end
  end,
})

right:AddButton({
  Text = "Notify",
  Callback = function()
    X64UI:Notify({
      Title = "X64UI",
      Description = "Notifications work like this.",
      Time = 3,
    })
  end,
})

right:AddButton({
  Text = "Unload",
  Callback = function()
    window:Destroy()
  end,
})

-- ==================== COMMANDS ====================

X64UI:RegisterCommand("Kill All", {
  Description = "Eliminate all targets",
  Keywords = { "kill", "eliminate", "combat" },
  Callback = function()
    print("Kill All executed")
    window:Log("Kill All ran")
  end,
})

window:Log("My Game Hub loaded.")
window:SetStatus("Ready")
