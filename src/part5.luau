      return failIntegrity(item.label)
    end
    if typeof(value) == "Instance" and not value.Parent then
      return failIntegrity(item.label .. " (instance has no parent)")
    end
  end

  -- menu buttons must exist
  local menuNames = { File = false, View = false, Options = false, Help = false }
  for _, child in ipairs(win.MenuBar:GetChildren()) do
    if child:IsA("TextButton") then
      local t = (child.Text or ""):gsub("%s+", "")
      for name in pairs(menuNames) do
        if t:find(name) then menuNames[name] = true end
      end
    end
  end
  for name, ok in pairs(menuNames) do
    if not ok then
      return failIntegrity("menu bar incomplete — missing '" .. name .. "'")
    end
  end

  -- toolbar must have at least a few tool buttons
  local toolCount = 0
  for _, child in ipairs(win.Toolbar:GetChildren()) do
    if child:IsA("TextButton") then toolCount += 1 end
  end
  if toolCount < 4 then
    return failIntegrity("toolbar incomplete — expected tool buttons, found " .. tostring(toolCount))
  end

  -- layout offsets must match full chrome (title+menu+toolbar+tabs)
  if (win.TopOffset or 0) < 90 then
    return failIntegrity("TopOffset too small (" .. tostring(win.TopOffset) .. ") — full chrome requires menu+toolbar")
  end

  table.insert(self.Windows, win)
  self.ActiveWindow = win
  return win
end

-- ==================== NOTIFICATIONS ====================

function X64UI:Notify(opts)
  opts = opts or {}

  local parent

  if self.ActiveWindow and not self.ActiveWindow.Destroyed and self.ActiveWindow.Gui and self.ActiveWindow.Gui.Parent then
    parent = self.ActiveWindow.Gui
  else
    if not self.NotifyGui or not self.NotifyGui.Parent then
      self.NotifyGui = Create.create("ScreenGui", {
        Name = "X64Notify",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 32767,
        Parent = getParent(),
      })
    end

    parent = self.NotifyGui
  end

  local container = parent:FindFirstChild("X64Notifications")

  if not container then
    container = Create.create("Frame", {
      Parent = parent,
      Name = "X64Notifications",
      AnchorPoint = Vector2.new(1, 1),
      Position = UDim2.new(1, -12, 1, -12),
      Size = UDim2.fromOffset(280, 0),
      AutomaticSize = Enum.AutomaticSize.Y,
      BackgroundTransparency = 1,
      ZIndex = 10000,
    })

    Create.create("UIListLayout", {
      Parent = container,
      Padding = UDim.new(0, 8),
      SortOrder = Enum.SortOrder.LayoutOrder,
      VerticalAlignment = Enum.VerticalAlignment.Bottom,
    })
  end

  while #container:GetChildren() > 6 do
    local child = container:GetChildren()[2]
    if child then child:Destroy() end
  end

  local toastMaid = Maid.new()
  local toast = Create.create("CanvasGroup", {
    Parent = container,
    Size = UDim2.new(1, 0, 0, 58),
    BackgroundColor3 = Theme.Panel,
    BorderColor3 = Theme.Border,
    GroupTransparency = 1,
    LayoutOrder = math.floor(os.clock() * 1000),
    ZIndex = 10001,
  })

  toastMaid:Give(toast)

  Create.create("TextLabel", {
    Parent = toast,
    Position = UDim2.fromOffset(8, 4),
    Size = UDim2.new(1, -16, 0, 18),
    BackgroundTransparency = 1,
    Text = opts.Title or "Notification",
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.AccentText,
    ZIndex = 10002,
  })

  Create.create("TextLabel", {
    Parent = toast,
    Position = UDim2.fromOffset(8, 24),
    Size = UDim2.new(1, -16, 0, 28),
    BackgroundTransparency = 1,
    Text = opts.Description or "",
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
    ZIndex = 10002,
  })

  TweenService:Create(
    toast,
    TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
    { GroupTransparency = 0 }
  ):Play()

  local hideThread = task.delay(opts.Time or 3, function()
    if toast and toast.Parent then
      local tween = TweenService:Create(
        toast,
        TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { GroupTransparency = 1 }
      )

      tween:Play()

      tween.Completed:Connect(function()
        toastMaid:Destroy()
      end)
    end
  end)
  
  toastMaid:Give(hideThread)
end

-- library surface integrity (api surface must be complete)
do
  local requiredApi = {
    "CreateWindow",
    "Notify",
    "RegisterCommand",
    "Theme",
    "Version",
  }
  local missing = {}
  for _, name in ipairs(requiredApi) do
    if X64UI[name] == nil then
      table.insert(missing, name)
    end
  end
  if #missing > 0 then
    local msg = "x64ui api incomplete — missing: " .. table.concat(missing, ", ")
    warn("[X64UI] " .. msg)
    -- cannot Notify yet (may not have full ui), but mark flag
    X64UI._IntegrityError = msg
  end
end

-- Global export for other scripts to pick up.
if getgenv then
  getgenv().X64UI = X64UI
elseif shared then
  shared.X64UI = X64UI
end

return X64UI
