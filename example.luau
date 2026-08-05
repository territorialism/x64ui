--[[
  X64UI Example Script

  Load the library first using loader.luau, then run this.
  If you're combining everything into one script, just paste the
  loader and library above this block.
]]

local X64UI = (getgenv and getgenv().X64UI)
  or (shared and shared.X64UI)

if not X64UI then
  warn("[X64UI] Library not loaded. Run loader.luau first.")
  return
end

-- ==================== WINDOW ====================

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

left:AddInput("Note", {
  Text = "Note",
  Placeholder = "Write something here...",
  Callback = function(value)
    print("Note:", value)
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
