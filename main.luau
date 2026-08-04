--[[
  X64UI Advanced Desktop Rework
  - Desktop only, no mobile/touch support
  - Maid cleanup, Signal bus, observable state, undo/redo history
  - Command palette with Ctrl+P
  - Validated configuration
  - Window focus management
  - Responsive viewport clamping
  - Fast CanvasGroup fade-in diffusion intro
  - Fixed: vararg closure error in X64UI:ExecuteCommand
]]

local X64UI = {
  Version = "4.0.1-desktop",
  MenuKeybind = Enum.KeyCode.RightShift,
  CurrentWindow = nil,
  NotifyGui = nil,
  Toggles = {},
  Options = {},
  Commands = {},
  CommandOrder = {},
  FocusCounter = 0,
  Theme = {
    Font = Enum.Font.Code,
    TextSize = 13,

    Background = Color3.fromRGB(19, 19, 21),
    TitleBar = Color3.fromRGB(31, 31, 34),
    Menu = Color3.fromRGB(26, 26, 29),
    Panel = Color3.fromRGB(29, 29, 32),
    PanelAlt = Color3.fromRGB(38, 38, 42),
    Border = Color3.fromRGB(62, 62, 70),

    Text = Color3.fromRGB(222, 222, 227),
    Dim = Color3.fromRGB(128, 128, 136),
    Accent = Color3.fromRGB(0, 122, 204),
    AccentText = Color3.fromRGB(88, 158, 216),
    Warning = Color3.fromRGB(220, 220, 170),
    Bad = Color3.fromRGB(244, 71, 71),
    Selection = Color3.fromRGB(51, 153, 255),

    Button = Color3.fromRGB(44, 44, 48),
    ButtonHover = Color3.fromRGB(61, 61, 66),
    Scroll = Color3.fromRGB(74, 74, 80),
  },
}

local Services = setmetatable({}, {
  __index = function(self, key)
    local service = game:GetService(key)
    self[key] = service
    return service
  end,
})

local UserInputService = Services.UserInputService
local RunService = Services.RunService
local TweenService = Services.TweenService
local Players = Services.Players
local GuiService = Services.GuiService
local HttpService = Services.HttpService
local Workspace = Services.Workspace

-- Desktop only.
if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
  warn("[X64UI] Mobile is not supported. This build is desktop-only.")
  return
end

if not table.clone then
  function table.clone(t)
    local copy = {}
    for k, v in pairs(t) do
      copy[k] = v
    end
    return copy
  end
end

if not table.pack then
  function table.pack(...)
    return { n = select("#", ...), ... }
  end
end

local Theme = X64UI.Theme

local traceback = (debug and debug.traceback) and debug.traceback or function(err)
  return tostring(err)
end

-- ==================== SIGNAL ====================

local Signal = {}
Signal.__index = Signal

function Signal.new()
  return setmetatable({
    Bindings = {},
    Destroyed = false,
  }, Signal)
end

function Signal:Connect(callback)
  assert(type(callback) == "function", "Signal callback must be a function")

  if self.Destroyed then
    return {
      Connected = false,
      Disconnect = function() end,
    }
  end

  local binding = {
    Connected = true,
    Callback = callback,
  }

  table.insert(self.Bindings, binding)

  local connection = {
    Connected = true,
    Disconnect = function()
      binding.Connected = false
      connection.Connected = false

      for i, current in ipairs(self.Bindings) do
        if current == binding then
          table.remove(self.Bindings, i)
          break
        end
      end
    end,
  }

  return connection
end

function Signal:Fire(...)
  if self.Destroyed then
    return
  end

  local arguments = table.pack(...)
  local bindings = table.clone(self.Bindings)

  for _, binding in ipairs(bindings) do
    if binding.Connected then
      task.spawn(function()
        local ok, err = xpcall(function()
          binding.Callback(table.unpack(arguments, 1, arguments.n))
        end, traceback)

        if not ok then
          warn("[X64UI] Signal callback failed:\n" .. tostring(err))
        end
      end)
    end
  end
end

function Signal:Destroy()
  self.Destroyed = true
  table.clear(self.Bindings)
end

-- ==================== MAID ====================

local Maid = {}
Maid.__index = Maid

function Maid.new()
  return setmetatable({
    Tasks = {},
    Destroyed = false,
  }, Maid)
end

function Maid:Give(taskObject)
  if self.Destroyed then
    self:CleanupTask(taskObject)
    return taskObject
  end

  table.insert(self.Tasks, taskObject)
  return taskObject
end

function Maid:CleanupTask(taskObject)
  local taskType = typeof(taskObject)

  if taskType == "RBXScriptConnection" then
    pcall(function()
      taskObject:Disconnect()
    end)
  elseif taskType == "Instance" then
    pcall(function()
      taskObject:Destroy()
    end)
  elseif type(taskObject) == "function" then
    pcall(taskObject)
  elseif type(taskObject) == "table" then
    if type(taskObject.Destroy) == "function" then
      pcall(function()
        taskObject:Destroy()
      end)
    elseif type(taskObject.Disconnect) == "function" then
      pcall(function()
        taskObject:Disconnect()
      end)
    end
  end
end

function Maid:Cleanup()
  for i = #self.Tasks, 1, -1 do
    self:CleanupTask(self.Tasks[i])
    self.Tasks[i] = nil
  end
end

function Maid:Destroy()
  if self.Destroyed then
    return
  end

  self.Destroyed = true
  self:Cleanup()
end

-- ==================== STATE ====================

local State = {}
State.__index = State

function State.new(defaultValue)
  return setmetatable({
    Value = defaultValue,
    Changed = Signal.new(),
  }, State)
end

function State:Get()
  return self.Value
end

function State:Set(value, silent)
  if self.Value == value then
    return false
  end

  local previous = self.Value
  self.Value = value

  if not silent then
    self.Changed:Fire(value, previous)
  end

  return true
end

function State:Destroy()
  self.Changed:Destroy()
end

-- ==================== HISTORY ====================

local History = {}
History.__index = History

function History.new(limit)
  return setmetatable({
    UndoStack = {},
    RedoStack = {},
    Limit = limit or 100,
    Applying = false,
  }, History)
end

function History:Push(label, undo, redo)
  if self.Applying then
    return
  end

  table.insert(self.UndoStack, {
    Label = label,
    Undo = undo,
    Redo = redo,
  })

  table.clear(self.RedoStack)

  while #self.UndoStack > self.Limit do
    table.remove(self.UndoStack, 1)
  end
end

function History:UndoLast()
  local entry = table.remove(self.UndoStack)

  if not entry then
    return false
  end

  self.Applying = true
  local ok, err = xpcall(entry.Undo, traceback)
  self.Applying = false

  if not ok then
    warn("[X64UI] Undo failed:\n" .. tostring(err))
    table.insert(self.UndoStack, entry)
    return false
  end

  table.insert(self.RedoStack, entry)
  return true
end

function History:RedoLast()
  local entry = table.remove(self.RedoStack)

  if not entry then
    return false
  end

  self.Applying = true
  local ok, err = xpcall(entry.Redo, traceback)
  self.Applying = false

  if not ok then
    warn("[X64UI] Redo failed:\n" .. tostring(err))
    table.insert(self.RedoStack, entry)
    return false
  end

  table.insert(self.UndoStack, entry)
  return true
end

function History:Clear()
  table.clear(self.UndoStack)
  table.clear(self.RedoStack)
end

-- ==================== HELPERS ====================

local function create(className, props, children)
  local inst = Instance.new(className)

  for k, v in pairs(props or {}) do
    if k ~= "Parent" then
      pcall(function()
        inst[k] = v
      end)
    end
  end

  for _, child in ipairs(children or {}) do
    child.Parent = inst
  end

  if props and props.Parent then
    inst.Parent = props.Parent
  end

  return inst
end

local function getParent()
  if gethui then
    local ok, h = pcall(gethui)
    if ok and h then return h end
  end

  local ok, core = pcall(function()
    return game:GetService("CoreGui")
  end)

  if ok and core then
    return core
  end

  return Players.LocalPlayer:WaitForChild("PlayerGui")
end

local function getViewportSize()
  local cam = Workspace.CurrentCamera
  if cam then return cam.ViewportSize end
  return Vector2.new(1280, 720)
end

local function pointInGui(gui, point)
  if not gui or not gui.Parent then return false end

  local pos = gui.AbsolutePosition
  local size = gui.AbsoluteSize

  return point.X >= pos.X
    and point.X <= pos.X + size.X
    and point.Y >= pos.Y
    and point.Y <= pos.Y + size.Y
end

local function mouseOverGui(gui)
  local ok, mouse = pcall(function()
    return UserInputService:GetMouseLocation()
  end)

  if not ok or not mouse then return false end

  local inset = GuiService:GetGuiInset()
  return pointInGui(gui, mouse) or pointInGui(gui, mouse - inset)
end

local function mousePosition2D(input)
  return Vector2.new(input.Position.X, input.Position.Y)
end

local function bindCanvas(window, scroll, layout)
  local function update()
    if scroll and scroll.Parent then
      scroll.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 12)
    end
  end

  window:Track(layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(update))
  update()
end

local function isControlValueValid(control, value)
  if not control or not control.Type then
    return false
  end

  if control.Type == "Toggle" then
    return typeof(value) == "boolean"
  end

  if control.Type == "Slider" then
    return typeof(value) == "number"
  end

  if control.Type == "Dropdown" then
    if typeof(value) ~= "string" and typeof(value) ~= "number" then
      return false
    end

    if control.Values then
      return table.find(control.Values, value) ~= nil
    end

    return true
  end

  if control.Type == "Input" or control.Type == "KeyPicker" then
    return typeof(value) == "string"
  end

  return false
end

-- ==================== CLASSES ====================

local Window = {}
Window.__index = Window

local Tab = {}
Tab.__index = Tab

local Groupbox = {}
Groupbox.__index = Groupbox

-- ==================== WINDOW CORE ====================

function Window:Track(taskObject)
  if self.Destroyed then
    if self.Maid then
      self.Maid:CleanupTask(taskObject)
    end

    return taskObject
  end

  if self.Maid then
    self.Maid:Give(taskObject)
  end

  return taskObject
end

function Window:DisconnectAll()
  if self.Maid then
    self.Maid:Cleanup()
  end

  if self.Events then
    for _, event in pairs(self.Events) do
      if type(event) == "table" and type(event.Destroy) == "function" then
        pcall(function()
          event:Destroy()
        end)
      end
    end
  end
end

function Window:Focus()
  if self.Destroyed then return end

  X64UI.FocusCounter = (X64UI.FocusCounter + 1) % 1000000

  if self.Gui then
    self.Gui.DisplayOrder = 10000 + X64UI.FocusCounter
  end

  if self.Events and self.Events.Focused then
    self.Events.Focused:Fire(self)
  end
end

function Window:SetStatus(text)
  if self.StatusLabel then
    self.StatusLabel.Text = tostring(text)
  end
end

function Window:Log(message)
  if not self.LogLabel or not self.LogLabel.Parent then return end

  self.Lines[#self.Lines + 1] = string.format("[%s] %s", os.date("%X"), tostring(message))

  if #self.Lines > 500 then
    table.remove(self.Lines, 1)
  end

  self.LogLabel.Text = table.concat(self.Lines, "\n")

  task.defer(function()
    if self.Destroyed then return end

    if self.LogScroll and self.LogLabel and self.LogLabel.Parent then
      local y = self.LogLabel.TextBounds.Y + 10
      self.LogScroll.CanvasSize = UDim2.fromOffset(0, y)
      self.LogScroll.CanvasPosition = Vector2.new(0, math.max(0, y - self.LogScroll.AbsoluteWindowSize.Y))
    end
  end)
end

function Window:ClearLog()
  table.clear(self.Lines)

  if self.LogLabel then
    self.LogLabel.Text = ""
  end

  if self.LogScroll then
    self.LogScroll.CanvasSize = UDim2.new()
  end
end

function Window:CloseDropdowns()
  for _, dropdown in ipairs(self.Dropdowns) do
    if dropdown and dropdown.Close then
      dropdown:Close()
    end
  end
end

function Window:UpdateLayout()
  if self.Destroyed or self.Minimized then return end

  local consoleHeight = self.ConsoleVisible and 160 or 0
  local statusHeight = self.StatusVisible and 22 or 0

  self.Console.Visible = self.ConsoleVisible
  self.StatusBar.Visible = self.StatusVisible

  self.Pages.Position = UDim2.fromOffset(4, self.TopOffset)
  self.Pages.Size = UDim2.new(1, -8, 1, -(self.TopOffset + consoleHeight + statusHeight + 8))

  self.Console.Position = UDim2.new(0, 4, 1, -(consoleHeight + statusHeight + 4))
  self.Console.Size = UDim2.new(1, -8, 0, consoleHeight)

  self.StatusBar.Position = UDim2.new(0, 0, 1, -statusHeight)
  self.StatusBar.Size = UDim2.new(1, 0, 0, statusHeight)
end

function Window:ClampToViewport()
  if self.Destroyed or self.Maximized then return end
  if not self.Main or not self.Main.Parent then return end

  local viewport = getViewportSize()
  local size = self.Main.AbsoluteSize
  local position = self.Main.AbsolutePosition

  local margin = 8
  local maxX = math.max(margin, viewport.X - size.X - margin)
  local maxY = math.max(margin, viewport.Y - size.Y - margin)

  self.Main.Position = UDim2.fromOffset(
    math.clamp(position.X, margin, maxX),
    math.clamp(position.Y, margin, maxY)
  )
end

function Window:ToggleConsole()
  self.ConsoleVisible = not self.ConsoleVisible
  self:UpdateLayout()

  if self.Events and self.Events.Changed then
    self.Events.Changed:Fire("ConsoleVisible", self.ConsoleVisible)
  end
end

function Window:ToggleStatusBar()
  self.StatusVisible = not self.StatusVisible
  self:UpdateLayout()

  if self.Events and self.Events.Changed then
    self.Events.Changed:Fire("StatusVisible", self.StatusVisible)
  end
end

function Window:SetMinimized(value)
  if self.Destroyed then return end

  value = value and true or false
  if value == self.Minimized then return end

  self.Minimized = value
  self.State.Minimized:Set(value)

  if value then
    self.LastSize = self.Main.Size
    self.Main.Size = UDim2.fromOffset(self.Main.AbsoluteSize.X, 24)

    self.TabBar.Visible = false
    self.Pages.Visible = false
    self.Console.Visible = false
    self.StatusBar.Visible = false
    self.Grip.Visible = false
  else
    self.Main.Size = self.LastSize or UDim2.fromOffset(1000, 640)

    self.TabBar.Visible = true
    self.Pages.Visible = true
    self.Console.Visible = self.ConsoleVisible
    self.StatusBar.Visible = self.StatusVisible
    self.Grip.Visible = true

    self:UpdateLayout()
    self:ClampToViewport()
  end

  if self.Events and self.Events.Changed then
    self.Events.Changed:Fire("Minimized", value)
  end
end

function Window:SetMaximized(value)
  if self.Destroyed or self.Minimized then return end

  value = value and true or false
  if value == self.Maximized then return end

  self.Maximized = value
  self.State.Maximized:Set(value)

  if value then
    self.PreMaxSize = self.Main.Size
    self.PreMaxPosition = self.Main.Position

    local viewport = getViewportSize()
    self.Main.Position = UDim2.fromOffset(0, 0)
    self.Main.Size = UDim2.fromOffset(viewport.X, viewport.Y)
  else
    self.Main.Size = self.PreMaxSize or UDim2.fromOffset(1000, 640)
    self.Main.Position = self.PreMaxPosition or UDim2.fromOffset(100, 100)
    self:ClampToViewport()
  end

  self:UpdateLayout()

  if self.Events and self.Events.Changed then
    self.Events.Changed:Fire("Maximized", value)
  end
end

function Window:Show()
  if self.Destroyed then return end

  if not self.Main.Visible then
    self.Main.Visible = true
    self.State.Visible:Set(true)

    if self.Events and self.Events.VisibilityChanged then
      self.Events.VisibilityChanged:Fire(true)
    end

    if self.IntroPlayed then
      pcall(function()
        self.Main.GroupTransparency = 1

        TweenService:Create(
          self.Main,
          TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
          { GroupTransparency = 0 }
        ):Play()
      end)
    end
  end
end

function Window:Hide()
  if self.Destroyed then return end

  if self.Main.Visible then
    self:CloseDropdowns()

    if self.CommandPalette then
      self.CommandPalette.Visible = false
    end

    self.Main.Visible = false
    self.State.Visible:Set(false)

    if self.Events and self.Events.VisibilityChanged then
      self.Events.VisibilityChanged:Fire(false)
    end
  end
end

function Window:Toggle()
  if self.Main.Visible then
    self:Hide()
  else
    self:Show()
  end
end

function Window:Destroy()
  if self.Destroyed then
    return
  end

  self.Destroyed = true

  if self.Events and self.Events.Destroying then
    self.Events.Destroying:Fire(self)
  end

  if self.CommandPalette then
    self.CommandPalette.Visible = false
  end

  self:CloseDropdowns()

  if self.Maid then
    self.Maid:Destroy()
  else
    self:DisconnectAll()
  end

  if self.Gui then
    self.Gui:Destroy()
    self.Gui = nil
  end

  if X64UI.CurrentWindow == self then
    X64UI.CurrentWindow = nil
  end
end

function Window:PlayIntro()
  if self.IntroPlayed or self.Destroyed then return end
  self.IntroPlayed = true

  pcall(function()
    self.Main.GroupTransparency = 1

    local wash = create("CanvasGroup", {
      Parent = self.Gui,
      Size = UDim2.fromScale(1, 1),
      BackgroundColor3 = Color3.fromRGB(7, 7, 9),
      BackgroundTransparency = 0,
      GroupTransparency = 0,
      BorderSizePixel = 0,
      ZIndex = 999999,
    })

    if self.Maid then
      self.Maid:Give(wash)
    end

    local gradient = create("UIGradient", {
      Parent = wash,
      Rotation = 90,
      Offset = Vector2.new(0, -0.2),
      Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.35, 0.22),
        NumberSequenceKeypoint.new(0.65, 0.55),
        NumberSequenceKeypoint.new(1, 1),
      }),
    })

    TweenService:Create(
      self.Main,
      TweenInfo.new(0.36, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
      { GroupTransparency = 0 }
    ):Play()

    TweenService:Create(
      gradient,
      TweenInfo.new(0.56, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
      { Offset = Vector2.new(0, 0.28) }
    ):Play()

    local washTween = TweenService:Create(
      wash,
      TweenInfo.new(0.56, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
      { GroupTransparency = 1 }
    )

    washTween:Play()

    washTween.Completed:Connect(function()
      wash:Destroy()
    end)
  end)
end

-- ==================== DRAG / RESIZE ====================

function Window:MakeDraggable(frame, handle)
  local dragging = false
  local startMouse = Vector2.zero
  local startPos = UDim2.new()

  local function canDrag()
    if self.Destroyed or not frame.Parent or not handle.Parent then return false end
    if not self.Main.Visible then return false end
    if self.Maximized then return false end
    if UserInputService:GetFocusedTextBox() then return false end
    if self.MinButton and mouseOverGui(self.MinButton) then return false end
    if self.CloseButton and mouseOverGui(self.CloseButton) then return false end
    return true
  end

  local function beginDrag(input)
    if not canDrag() then return end

    dragging = true
    startMouse = mousePosition2D(input)
    startPos = frame.Position
    self:Focus()
  end

  self:Track(handle.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
      beginDrag(input)
    end
  end))

  self:Track(UserInputService.InputBegan:Connect(function(input)
    if dragging then return end

    if input.UserInputType == Enum.UserInputType.MouseButton1 then
      if mouseOverGui(handle) then
        beginDrag(input)
      end
    end
  end))

  self:Track(UserInputService.InputChanged:Connect(function(input)
    if not dragging then return end

    if input.UserInputType == Enum.UserInputType.MouseMovement then
      local current = mousePosition2D(input)
      local delta = current - startMouse

      frame.Position = UDim2.new(
        startPos.X.Scale,
        startPos.X.Offset + delta.X,
        startPos.Y.Scale,
        startPos.Y.Offset + delta.Y
      )

      self:ClampToViewport()
    end
  end))

  self:Track(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 and dragging then
      dragging = false
      self:ClampToViewport()
    end
  end))
end

function Window:MakeResizable(frame, grip)
  local resizing = false
  local startMouse = Vector2.zero
  local startSize = Vector2.zero

  local function canResize()
    if self.Destroyed or not frame.Parent or not grip.Parent or not grip.Visible then
      return false
    end

    if not self.Main.Visible then return false end
    if self.Minimized or self.Maximized then return false end
    if UserInputService:GetFocusedTextBox() then return false end
    return true
  end

  local function beginResize(input)
    if not canResize() then return end

    resizing = true
    startMouse = mousePosition2D(input)
    startSize = frame.AbsoluteSize
    self:Focus()
  end

  self:Track(grip.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
      beginResize(input)
    end
  end))

  self:Track(UserInputService.InputBegan:Connect(function(input)
    if resizing then return end

    if input.UserInputType == Enum.UserInputType.MouseButton1 then
      if mouseOverGui(grip) then
        beginResize(input)
      end
    end
  end))

  self:Track(UserInputService.InputChanged:Connect(function(input)
    if not resizing then return end

    if input.UserInputType == Enum.UserInputType.MouseMovement then
      local current = mousePosition2D(input)
      local dx = current.X - startMouse.X
      local dy = current.Y - startMouse.Y

      frame.Size = UDim2.fromOffset(
        math.clamp(startSize.X + dx, 760, 1900),
        math.clamp(startSize.Y + dy, 420, 1300)
      )

      self:UpdateLayout()
      self:ClampToViewport()
    end
  end))

  self:Track(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 and resizing then
      resizing = false
      self:ClampToViewport()
    end
  end))
end

-- ==================== TABS ====================

function Window:SelectTab(name)
  local tab = self.Tabs[name]
  if not tab then return end

  self:CloseDropdowns()

  if self.CommandPalette then
    self.CommandPalette.Visible = false
  end

  for _, other in pairs(self.Tabs) do
    other.Page.Visible = false
    other.Underline.Visible = false
    other.Button.TextColor3 = Theme.Dim
  end

  tab.Page.Visible = true
  tab.Underline.Visible = true
  tab.Button.TextColor3 = Theme.Text

  self:SetStatus("Tab: " .. tostring(name))
  self.State.ActiveTab:Set(name)

  if self.Events and self.Events.Changed then
    self.Events.Changed:Fire("ActiveTab", name)
  end
end

function Window:AddTab(name)
  if self.Tabs[name] then
    return self.Tabs[name]
  end

  local tab = setmetatable({
    Window = self,
    Name = name,
    NextLeftOrder = 0,
    NextRightOrder = 0,
  }, Tab)

  local order = #self.TabOrder + 1
  table.insert(self.TabOrder, name)

  tab.Button = create("TextButton", {
    Parent = self.TabBar,
    Size = UDim2.fromOffset(0, 26),
    AutomaticSize = Enum.AutomaticSize.X,
    BackgroundTransparency = 1,
    Text = "  " .. tostring(name) .. "  ",
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Dim,
    LayoutOrder = order,
  })

  tab.Underline = create("Frame", {
    Parent = tab.Button,
    Size = UDim2.new(1, 0, 0, 2),
    Position = UDim2.new(0, 0, 1, -2),
    BackgroundColor3 = Theme.Accent,
    BorderSizePixel = 0,
    Visible = false,
  })

  self:Track(tab.Button.MouseEnter:Connect(function()
    if not tab.Underline.Visible then
      tab.Button.TextColor3 = Theme.Text
    end
  end))

  self:Track(tab.Button.MouseLeave:Connect(function()
    if not tab.Underline.Visible then
      tab.Button.TextColor3 = Theme.Dim
    end
  end))

  self:Track(tab.Button.MouseButton1Click:Connect(function()
    self:SelectTab(name)
  end))

  tab.Page = create("Frame", {
    Parent = self.Pages,
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Visible = false,
  })

  tab.LeftPane = create("ScrollingFrame", {
    Parent = tab.Page,
    Size = UDim2.new(0.5, -3, 1, 0),
    Position = UDim2.new(0, 0, 0, 0),
    BackgroundColor3 = Theme.Background,
    BorderColor3 = Theme.Border,
    BorderSizePixel = 1,
    ScrollBarThickness = 8,
    ScrollBarImageColor3 = Theme.Scroll,
    CanvasSize = UDim2.new(),
  })

  tab.RightPane = create("ScrollingFrame", {
    Parent = tab.Page,
    Size = UDim2.new(0.5, -3, 1, 0),
    Position = UDim2.new(0.5, 3, 0, 0),
    BackgroundColor3 = Theme.Background,
    BorderColor3 = Theme.Border,
    BorderSizePixel = 1,
    ScrollBarThickness = 8,
    ScrollBarImageColor3 = Theme.Scroll,
    CanvasSize = UDim2.new(),
  })

  local leftList = create("UIListLayout", {
    Parent = tab.LeftPane,
    Padding = UDim.new(0, 4),
    SortOrder = Enum.SortOrder.LayoutOrder,
  })

  local rightList = create("UIListLayout", {
    Parent = tab.RightPane,
    Padding = UDim.new(0, 4),
    SortOrder = Enum.SortOrder.LayoutOrder,
  })

  create("UIPadding", {
    Parent = tab.LeftPane,
    PaddingTop = UDim.new(0, 4),
    PaddingLeft = UDim.new(0, 4),
    PaddingRight = UDim.new(0, 4),
    PaddingBottom = UDim.new(0, 4),
  })

  create("UIPadding", {
    Parent = tab.RightPane,
    PaddingTop = UDim.new(0, 4),
    PaddingLeft = UDim.new(0, 4),
    PaddingRight = UDim.new(0, 4),
    PaddingBottom = UDim.new(0, 4),
  })

  bindCanvas(self, tab.LeftPane, leftList)
  bindCanvas(self, tab.RightPane, rightList)

  self.Tabs[name] = tab

  if #self.TabOrder == 1 then
    self:SelectTab(name)
  end

  return tab
end

-- ==================== CONFIG ====================

function Window:SaveConfig(path)
  path = path or "x64ui_config.json"

  if not writefile then
    self:Log("writefile is not supported by this executor.")
    return false
  end

  local data = {
    Version = 1,
    Toggles = {},
    Options = {},
  }

  for name, toggle in pairs(self.Toggles) do
    if typeof(toggle.Value) == "boolean" then
      data.Toggles[name] = toggle.Value
    end
  end

  for name, option in pairs(self.Options) do
    local valueType = typeof(option.Value)

    if valueType == "number" or valueType == "string" or valueType == "boolean" then
      data.Options[name] = option.Value
    end
  end

  local ok, json = pcall(function()
    return HttpService:JSONEncode(data)
  end)

  if ok then
    writefile(path, json)
    self:Log("Config saved: " .. path)
  else
    self:Log("Config encode failed.")
  end

  return ok
end

function Window:LoadConfig(path)
  path = path or "x64ui_config.json"

  if not readfile or not isfile or not isfile(path) then
    self:Log("Config file not found.")
    return false
  end

  local ok, json = pcall(readfile, path)
  if not ok then
    self:Log("Config read failed.")
    return false
  end

  local okDecode, data = pcall(function()
    return HttpService:JSONDecode(json)
  end)

  if not okDecode or typeof(data) ~= "table" then
    self:Log("Config decode failed.")
    return false
  end

  if typeof(data.Toggles) ~= "table" then
    data.Toggles = {}
  end

  if typeof(data.Options) ~= "table" then
    data.Options = {}
  end

  local applied = 0

  for name, value in pairs(data.Toggles) do
    local toggle = self.Toggles[name]

    if toggle and toggle.SetValue and isControlValueValid(toggle, value) then
      toggle:SetValue(value, true)
      applied += 1
    end
  end

  for name, value in pairs(data.Options) do
    local option = self.Options[name]

    if option and option.SetValue then
      if option.Type == "Slider" and typeof(value) == "number" then
        value = math.clamp(value, option.Min or value, option.Max or value)
      end

      if isControlValueValid(option, value) then
        option:SetValue(value, true)
        applied += 1
      end
    end
  end

  self:Log(("Config loaded: %s (%d values applied)"):format(path, applied))
  return true
end

-- ==================== COMMAND PALETTE ====================

function Window:CreateCommandPalette()
  local palette = create("Frame", {
    Parent = self.Gui,
    AnchorPoint = Vector2.new(0.5, 0),
    Position = UDim2.new(0.5, 0, 0, 90),
    Size = UDim2.fromOffset(520, 320),
    BackgroundColor3 = Theme.Panel,
    BorderColor3 = Theme.Border,
    Visible = false,
    ZIndex = 5000,
  })

  local input = create("TextBox", {
    Parent = palette,
    Position = UDim2.fromOffset(8, 8),
    Size = UDim2.new(1, -16, 0, 30),
    BackgroundColor3 = Theme.PanelAlt,
    BorderColor3 = Theme.Border,
    PlaceholderText = "Search commands...  Ctrl+P to toggle",
    ClearTextOnFocus = false,
    Text = "",
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
    ZIndex = 5001,
  })

  local results = create("ScrollingFrame", {
    Parent = palette,
    Position = UDim2.fromOffset(8, 46),
    Size = UDim2.new(1, -16, 1, -54),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 6,
    ScrollBarImageColor3 = Theme.Scroll,
    CanvasSize = UDim2.new(),
    ZIndex = 5001,
  })

  local layout = create("UIListLayout", {
    Parent = results,
    Padding = UDim.new(0, 3),
    SortOrder = Enum.SortOrder.LayoutOrder,
  })

  local itemMaid = Maid.new()
  self.Maid:Give(itemMaid)

  local selectedIndex = 1
  local visibleCommands = {}
  local resultButtons = {}

  local function updateSelection()
    if #resultButtons == 0 then
      return
    end

    selectedIndex = math.clamp(selectedIndex, 1, #resultButtons)

    for i, button in ipairs(resultButtons) do
      button.BackgroundColor3 = (i == selectedIndex) and Theme.Selection or Theme.Button
    end

    local selectedButton = resultButtons[selectedIndex]

    if selectedButton and results.Parent then
      local itemTop = selectedButton.AbsolutePosition.Y - results.AbsolutePosition.Y + results.CanvasPosition.Y
      local itemBottom = itemTop + selectedButton.AbsoluteSize.Y
      local viewTop = results.CanvasPosition.Y
      local viewBottom = viewTop + results.AbsoluteWindowSize.Y

      if itemTop < viewTop then
        results.CanvasPosition = Vector2.new(0, math.max(0, itemTop))
      elseif itemBottom > viewBottom then
        results.CanvasPosition = Vector2.new(0, math.max(0, itemBottom - results.AbsoluteWindowSize.Y))
      end
    end
  end

  local function clearResults()
    itemMaid:Cleanup()

    for _, child in ipairs(results:GetChildren()) do
      if child:IsA("TextButton") then
        child:Destroy()
      end
    end

    table.clear(visibleCommands)
    table.clear(resultButtons)
  end

  local function rebuild()
    clearResults()

    local query = string.lower(input.Text or "")
    local order = 1

    for _, commandName in ipairs(X64UI.CommandOrder) do
      local command = X64UI.Commands[commandName]

      if command then
        local searchable = string.lower(
          command.Name .. " " ..
          command.Description .. " " ..
          table.concat(command.Keywords, " ")
        )

        if query == "" or string.find(searchable, query, 1, true) then
          table.insert(visibleCommands, command)

          local text = command.Name
          if command.Description ~= "" then
            text = text .. "  —  " .. command.Description
          end

          local item = create("TextButton", {
            Parent = results,
            Size = UDim2.new(1, 0, 0, 38),
            BackgroundColor3 = Theme.Button,
            BorderColor3 = Theme.Border,
            Text = "  " .. text,
            TextXAlignment = Enum.TextXAlignment.Left,
            Font = Theme.Font,
            TextSize = Theme.TextSize,
            TextColor3 = Theme.Text,
            AutoButtonColor = false,
            LayoutOrder = order,
            ZIndex = 5002,
          })

          itemMaid:Give(item)

          local index = #visibleCommands

          itemMaid:Give(item.MouseEnter:Connect(function()
            selectedIndex = index
            updateSelection()
          end))

          itemMaid:Give(item.MouseLeave:Connect(function()
            updateSelection()
          end))

          itemMaid:Give(item.MouseButton1Click:Connect(function()
            X64UI:ExecuteCommand(command.Name)
            self:CloseCommandPalette()
          end))

          table.insert(resultButtons, item)
          order += 1
        end
      end
    end

    results.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 8)
    selectedIndex = math.clamp(selectedIndex, 1, math.max(1, #resultButtons))
    updateSelection()
  end

  local function moveSelection(delta)
    if #resultButtons == 0 then return end

    selectedIndex += delta
    selectedIndex = math.clamp(selectedIndex, 1, #resultButtons)
    updateSelection()
  end

  local function executeSelected()
    local command = visibleCommands[selectedIndex]

    if command then
      X64UI:ExecuteCommand(command.Name)
      self:CloseCommandPalette()
    end
  end

  self:Track(input:GetPropertyChangedSignal("Text"):Connect(rebuild))

  self:Track(UserInputService.InputBegan:Connect(function(inputObject)
    if not palette.Visible then return end
    if inputObject.UserInputType ~= Enum.UserInputType.Keyboard then return end

    if inputObject.KeyCode == Enum.KeyCode.Escape then
      self:CloseCommandPalette()
    elseif inputObject.KeyCode == Enum.KeyCode.Up then
      moveSelection(-1)
    elseif inputObject.KeyCode == Enum.KeyCode.Down then
      moveSelection(1)
    elseif inputObject.KeyCode == Enum.KeyCode.Return then
      executeSelected()
    end
  end))

  self.CommandPalette = palette
  self.CommandInput = input
  self.CommandResults = results

  function self:OpenCommandPalette()
    palette.Visible = true
    input.Text = ""
    selectedIndex = 1
    rebuild()
    input:CaptureFocus()
    self:Focus()
  end

  function self:CloseCommandPalette()
    palette.Visible = false
    input:ReleaseFocus()
  end

  function self:ToggleCommandPalette()
    if palette.Visible then
      self:CloseCommandPalette()
    else
      self:OpenCommandPalette()
    end
  end

  return palette
end

-- ==================== CONTROLS ====================

function Tab:AddGroupbox(side, title)
  local isLeft = side == "Left"
  local parent = isLeft and self.LeftPane or self.RightPane

  local order
  if isLeft then
    self.NextLeftOrder += 1
    order = self.NextLeftOrder
  else
    self.NextRightOrder += 1
    order = self.NextRightOrder
  end

  local group = setmetatable({
    Window = self.Window,
    Tab = self,
    NextOrder = 0,
  }, Groupbox)

  group.Frame = create("Frame", {
    Parent = parent,
    Size = UDim2.new(1, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundColor3 = Theme.Panel,
    BorderColor3 = Theme.Border,
    LayoutOrder = order,
  })

  create("UIListLayout", {
    Parent = group.Frame,
    SortOrder = Enum.SortOrder.LayoutOrder,
  })

  create("TextLabel", {
    Parent = group.Frame,
    LayoutOrder = 0,
    Size = UDim2.new(1, 0, 0, 20),
    BackgroundColor3 = Theme.PanelAlt,
    BorderSizePixel = 0,
    Text = " " .. tostring(title or "Group"),
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Warning,
  })

  group.Content = create("Frame", {
    Parent = group.Frame,
    LayoutOrder = 1,
    Size = UDim2.new(1, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1,
  })

  group.Layout = create("UIListLayout", {
    Parent = group.Content,
    Padding = UDim.new(0, 4),
    SortOrder = Enum.SortOrder.LayoutOrder,
  })

  create("UIPadding", {
    Parent = group.Content,
    PaddingTop = UDim.new(0, 4),
    PaddingLeft = UDim.new(0, 4),
    PaddingRight = UDim.new(0, 4),
    PaddingBottom = UDim.new(0, 4),
  })

  return group
end

function Tab:AddLeftGroupbox(title)
  return self:AddGroupbox("Left", title)
end

function Tab:AddRightGroupbox(title)
  return self:AddGroupbox("Right", title)
end

function Tab:GetDefaultGroupbox()
  if not self.DefaultGroupbox then
    self.DefaultGroupbox = self:AddLeftGroupbox("General")
  end

  return self.DefaultGroupbox
end

local function createControlFrame(group, height, automatic, horizontal)
  local row = create("Frame", {
    Parent = group.Content,
    Size = UDim2.new(1, 0, 0, height or 24),
    BackgroundTransparency = 1,
    LayoutOrder = group.NextOrder,
  })

  group.NextOrder += 1

  if automatic then
    row.AutomaticSize = Enum.AutomaticSize.Y
  end

  local layout = create("UIListLayout", {
    Parent = row,
    Padding = UDim.new(0, 3),
    SortOrder = Enum.SortOrder.LayoutOrder,
  })

  if horizontal then
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
  else
    layout.FillDirection = Enum.FillDirection.Vertical
  end

  return row, layout
end

function Groupbox:AddLabel(text, wrap)
  local row = createControlFrame(self, nil, true, false)

  local label = create("TextLabel", {
    Parent = row,
    Size = UDim2.new(1, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1,
    Text = text or "",
    TextWrapped = wrap and true or false,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
  })

  local obj = {
    Type = "Label",
    Label = label,
    Frame = row,
  }

  function obj:SetText(newText)
    label.Text = tostring(newText)
  end

  return obj
end

function Groupbox:AddButton(opts)
  opts = opts or {}

  local row = createControlFrame(self, 26, false, false)

  local button = create("TextButton", {
    Parent = row,
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundColor3 = Theme.Button,
    BorderColor3 = Theme.Border,
    Text = opts.Text or "Button",
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
  })

  self.Window:Track(button.MouseEnter:Connect(function()
    button.BackgroundColor3 = Theme.ButtonHover
  end))

  self.Window:Track(button.MouseLeave:Connect(function()
    button.BackgroundColor3 = Theme.Button
  end))

  self.Window:Track(button.MouseButton1Click:Connect(function()
    if opts.Callback then
      local ok, err = xpcall(opts.Callback, traceback)
      if not ok then
        warn("[X64UI] Button callback failed:\n" .. tostring(err))
      end
    elseif opts.Func then
      local ok, err = xpcall(opts.Func, traceback)
      if not ok then
        warn("[X64UI] Button callback failed:\n" .. tostring(err))
      end
    end

    self.Window:Log("Button: " .. tostring(opts.Text or "Button"))
  end))

  return button
end

function Groupbox:AddToggle(name, opts)
  opts = opts or {}

  local row = createControlFrame(self, 22, false, true)
  local state = State.new(opts.Default == true)

  local check = create("TextButton", {
    Parent = row,
    Size = UDim2.fromOffset(18, 18),
    BackgroundColor3 = Theme.PanelAlt,
    BorderColor3 = Theme.Border,
    Text = "",
    Font = Theme.Font,
    TextSize = 13,
    TextColor3 = Theme.AccentText,
    AutoButtonColor = false,
  })

  local label = create("TextButton", {
    Parent = row,
    Size = UDim2.new(1, -24, 1, 0),
    BackgroundTransparency = 1,
    Text = opts.Text or name or "Toggle",
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
    AutoButtonColor = false,
  })

  local obj = {
    Type = "Toggle",
    Value = state:Get(),
    Button = check,
    Changed = Signal.new(),
  }

  local internalChange = false

  local function render(value)
    obj.Value = value
    check.Text = value and "✓" or ""
    check.BackgroundColor3 = value and Theme.Accent or Theme.PanelAlt
  end

  local function set(value, silent, withHistory)
    value = value == true

    local previous = state:Get()
    if previous == value then
      return
    end

    state:Set(value, true)
    render(value)

    if not silent then
      obj.Changed:Fire(value, previous)

      if self.Window.Events and self.Window.Events.Changed then
        self.Window.Events.Changed:Fire(name or "Toggle", value)
      end

      if opts.Callback then
        local ok, err = xpcall(function()
          opts.Callback(value)
        end, traceback)

        if not ok then
          warn("[X64UI] Toggle callback failed:\n" .. tostring(err))
        end
      end
    end

    if withHistory and not internalChange then
      self.Window.History:Push(
        "Toggle " .. tostring(opts.Text or name),
        function()
          internalChange = true
          set(previous, false, false)
          internalChange = false
        end,
        function()
          internalChange = true
          set(value, false, false)
          internalChange = false
        end
      )
    end
  end

  local function toggle()
    set(not state:Get(), false, true)
  end

  self.Window:Track(check.MouseButton1Click:Connect(toggle))
  self.Window:Track(label.MouseButton1Click:Connect(toggle))

  function obj:SetValue(value, silent)
    set(value, silent == true, false)
  end

  function obj:GetValue()
    return state:Get()
  end

  function obj:Destroy()
    state:Destroy()
    obj.Changed:Destroy()
  end

  self.Window.Maid:Give(obj)
  render(state:Get())

  if name then
    self.Window.Toggles[name] = obj
    X64UI.Toggles[name] = obj
  end

  return obj
end

function Groupbox:AddSlider(name, opts)
  opts = opts or {}

  local min = tonumber(opts.Min) or 0
  local max = tonumber(opts.Max) or 100
  local value = tonumber(opts.Default) or min
  local digits = tonumber(opts.Rounding) or 0
  local step = 1 / (10 ^ math.clamp(digits, 0, 6))

  local row = createControlFrame(self, nil, true, false)

  local header = create("Frame", {
    Parent = row,
    Size = UDim2.new(1, 0, 0, 16),
    BackgroundTransparency = 1,
  })

  create("UIListLayout", {
    Parent = header,
    FillDirection = Enum.FillDirection.Horizontal,
    VerticalAlignment = Enum.VerticalAlignment.Center,
  })

  create("TextLabel", {
    Parent = header,
    Size = UDim2.new(1, -70, 1, 0),
    BackgroundTransparency = 1,
    Text = opts.Text or name or "Slider",
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
  })

  local valueLabel = create("TextLabel", {
    Parent = header,
    Size = UDim2.fromOffset(70, 16),
    BackgroundTransparency = 1,
    Text = "",
    TextXAlignment = Enum.TextXAlignment.Right,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.AccentText,
  })

  local bar = create("TextButton", {
    Parent = row,
    Size = UDim2.new(1, 0, 0, 14),
    BackgroundColor3 = Theme.PanelAlt,
    BorderColor3 = Theme.Border,
    Text = "",
    AutoButtonColor = false,
  })

  local fill = create("Frame", {
    Parent = bar,
    Size = UDim2.fromScale(0, 1),
    BackgroundColor3 = Theme.Accent,
    BorderSizePixel = 0,
  })

  local obj = {
    Type = "Slider",
    Value = value,
    Min = min,
    Max = max,
    Changed = Signal.new(),
  }

  local function format(v)
    if step < 1 then
      return string.format("%." .. digits .. "f", v)
    end

    return tostring(math.floor(v + 0.5))
  end

  local function round(v)
    return math.floor((v / step) + 0.5) * step
  end

  local function set(v, silent)
    v = math.clamp(round(v), min, max)

    local previous = obj.Value
    value = v
    obj.Value = v
    valueLabel.Text = format(v)

    local scale = 0
    if max ~= min then
      scale = (v - min) / (max - min)
    end

    fill.Size = UDim2.fromScale(scale, 1)

    if not silent and previous ~= v then
      obj.Changed:Fire(v, previous)

      if self.Window.Events and self.Window.Events.Changed then
        self.Window.Events.Changed:Fire(name or "Slider", v)
      end

      if opts.Callback then
        local ok, err = xpcall(function()
          opts.Callback(v)
        end, traceback)

        if not ok then
          warn("[X64UI] Slider callback failed:\n" .. tostring(err))
        end
      end
    end
  end

  local dragging = false
  local dragStartValue = value

  local function updateFromX(x)
    if not bar.Parent then return end

    local rel = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
    set(min + ((max - min) * rel), false)
  end

  self.Window:Track(bar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
      dragging = true
      dragStartValue = obj.Value
      updateFromX(input.Position.X)
    end
  end))

  self.Window:Track(UserInputService.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
      updateFromX(input.Position.X)
    end
  end))

  self.Window:Track(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 and dragging then
      dragging = false

      local newValue = obj.Value
      if newValue ~= dragStartValue then
        local oldValue = dragStartValue

        self.Window.History:Push(
          "Slider " .. tostring(opts.Text or name),
          function()
            set(oldValue, false)
          end,
          function()
            set(newValue, false)
          end
        )
      end
    end
  end))

  function obj:SetValue(v, silent)
    set(v, silent == true)
  end

  function obj:GetValue()
    return obj.Value
  end

  function obj:Destroy()
    obj.Changed:Destroy()
  end

  self.Window.Maid:Give(obj)
  set(value, true)

  if name then
    self.Window.Options[name] = obj
    X64UI.Options[name] = obj
  end

  return obj
end

function Groupbox:AddDropdown(name, opts)
  opts = opts or {}

  local values = opts.Values or {}
  local selected = opts.Default or values[1]

  if typeof(selected) == "number" then
    selected = values[selected]
  end

  if not table.find(values, selected) then
    selected = values[1]
  end

  local row = createControlFrame(self, nil, true, false)

  create("TextLabel", {
    Parent = row,
    Size = UDim2.new(1, 0, 0, 16),
    BackgroundTransparency = 1,
    Text = opts.Text or name or "Dropdown",
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
  })

  local button = create("TextButton", {
    Parent = row,
    Size = UDim2.new(1, 0, 0, 20),
    BackgroundColor3 = Theme.PanelAlt,
    BorderColor3 = Theme.Border,
    Text = "▼ " .. tostring(selected),
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
  })

  local list = create("ScrollingFrame", {
    Parent = self.Window.Gui,
    Visible = false,
    BackgroundColor3 = Theme.Panel,
    BorderColor3 = Theme.Border,
    BorderSizePixel = 1,
    ScrollBarThickness = 6,
    ScrollBarImageColor3 = Theme.Scroll,
    CanvasSize = UDim2.new(),
    ZIndex = 2000,
  })

  local listLayout = create("UIListLayout", {
    Parent = list,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 1),
  })

  local obj = {
    Type = "Dropdown",
    Value = selected,
    Values = values,
    Button = button,
    List = list,
    OpenedAt = 0,
    Changed = Signal.new(),
  }

  local internalChange = false

  local function getListHeight()
    return math.min((#values * 19) + 2, 220)
  end

  function obj:RefreshPosition()
    if not button.Parent then return end

    local pos = button.AbsolutePosition
    local size = button.AbsoluteSize

    list.Position = UDim2.fromOffset(pos.X, pos.Y + size.Y + 2)
    list.Size = UDim2.fromOffset(size.X, getListHeight())
    list.CanvasSize = UDim2.fromOffset(0, listLayout.AbsoluteContentSize.Y + 2)
  end

  function obj:Open()
    obj:RefreshPosition()
    list.Visible = true
    obj.OpenedAt = os.clock()
  end

  function obj:Close()
    list.Visible = false
  end

  function obj:Toggle()
    if list.Visible then
      obj:Close()
    else
      obj:Open()
    end
  end

  local function set(value, silent, withHistory)
    if not table.find(values, value) then return end

    local previous = obj.Value
    if previous == value then return end

    obj.Value = value
    button.Text = "▼ " .. tostring(value)

    if not silent then
      obj.Changed:Fire(value, previous)

      if self.Window.Events and self.Window.Events.Changed then
        self.Window.Events.Changed:Fire(name or "Dropdown", value)
      end

      if opts.Callback then
        local ok, err = xpcall(function()
          opts.Callback(value)
        end, traceback)

        if not ok then
          warn("[X64UI] Dropdown callback failed:\n" .. tostring(err))
        end
      end
    end

    if withHistory and not internalChange then
      self.Window.History:Push(
        "Dropdown " .. tostring(opts.Text or name),
        function()
          internalChange = true
          set(previous, false, false)
          internalChange = false
        end,
        function()
          internalChange = true
          set(value, false, false)
          internalChange = false
        end
      )
    end
  end

  self.Window:Track(button.MouseButton1Click:Connect(function()
    obj:Toggle()
  end))

  for i, value in ipairs(values) do
    local item = create("TextButton", {
      Parent = list,
      LayoutOrder = i,
      Size = UDim2.new(1, 0, 0, 18),
      BackgroundTransparency = 1,
      Text = "  " .. tostring(value),
      TextXAlignment = Enum.TextXAlignment.Left,
      Font = Theme.Font,
      TextSize = Theme.TextSize,
      TextColor3 = Theme.Text,
      ZIndex = 2001,
    })

    self.Window:Track(item.MouseEnter:Connect(function()
      item.BackgroundColor3 = Theme.Selection
      item.BackgroundTransparency = 0
    end))

    self.Window:Track(item.MouseLeave:Connect(function()
      item.BackgroundTransparency = 1
    end))

    self.Window:Track(item.MouseButton1Click:Connect(function()
      set(value, false, true)
      obj:Close()
    end))
  end

  function obj:SetValue(value, silent)
    set(value, silent == true, false)
  end

  function obj:GetValue()
    return obj.Value
  end

  function obj:Destroy()
    obj.Changed:Destroy()
  end

  self.Window.Maid:Give(obj)
  set(selected, true)
  table.insert(self.Window.Dropdowns, obj)

  if name then
    self.Window.Options[name] = obj
    X64UI.Options[name] = obj
  end

  return obj
end

function Groupbox:AddInput(name, opts)
  opts = opts or {}

  local row = createControlFrame(self, nil, true, false)

  create("TextLabel", {
    Parent = row,
    Size = UDim2.new(1, 0, 0, 16),
    BackgroundTransparency = 1,
    Text = opts.Text or name or "Input",
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
  })

  local box = create("TextBox", {
    Parent = row,
    Size = UDim2.new(1, 0, 0, 20),
    BackgroundColor3 = Theme.PanelAlt,
    BorderColor3 = Theme.Border,
    PlaceholderText = opts.Placeholder or "",
    Text = opts.Default or "",
    ClearTextOnFocus = false,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
    TextXAlignment = Enum.TextXAlignment.Left,
  })

  local obj = {
    Type = "Input",
    Value = tostring(opts.Default or ""),
    TextBox = box,
    Changed = Signal.new(),
  }

  local internalChange = false
  local focusedValue = obj.Value

  local function set(value, silent, withHistory)
    value = tostring(value)

    local previous = obj.Value
    if previous == value then return end

    obj.Value = value
    box.Text = value

    if not box:IsFocused() then
      focusedValue = value
    end

    if not silent then
      obj.Changed:Fire(value, previous)

      if self.Window.Events and self.Window.Events.Changed then
        self.Window.Events.Changed:Fire(name or "Input", value)
      end

      if opts.Callback then
        local ok, err = xpcall(function()
          opts.Callback(value)
        end, traceback)

        if not ok then
          warn("[X64UI] Input callback failed:\n" .. tostring(err))
        end
      end
    end

    if withHistory and not internalChange then
      self.Window.History:Push(
        "Input " .. tostring(opts.Text or name),
        function()
          internalChange = true
          set(previous, false, false)
          internalChange = false
        end,
        function()
          internalChange = true
          set(value, false, false)
          internalChange = false
        end
      )
    end
  end

  self.Window:Track(box.Focused:Connect(function()
    focusedValue = box.Text
  end))

  self.Window:Track(box.FocusLost:Connect(function(_)
    local newText = box.Text

    if newText ~= focusedValue then
      set(newText, false, true)
      focusedValue = newText
    else
      set(newText, true, false)
    end
  end))

  function obj:SetValue(value, silent)
    set(value, silent == true, false)
    focusedValue = obj.Value
  end

  function obj:GetValue()
    return obj.Value
  end

  function obj:Destroy()
    obj.Changed:Destroy()
  end

  self.Window.Maid:Give(obj)

  if name then
    self.Window.Options[name] = obj
    X64UI.Options[name] = obj
  end

  return obj
end

function Groupbox:AddKeyPicker(name, opts)
  opts = opts or {}

  local row = createControlFrame(self, 22, false, true)

  create("TextLabel", {
    Parent = row,
    Size = UDim2.new(1, -90, 1, 0),
    BackgroundTransparency = 1,
    Text = opts.Text or name or "Keybind",
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
  })

  local button = create("TextButton", {
    Parent = row,
    Size = UDim2.fromOffset(90, 18),
    BackgroundColor3 = Theme.PanelAlt,
    BorderColor3 = Theme.Border,
    Text = tostring(opts.Default or "None"),
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
  })

  local waiting = false

  local obj = {
    Type = "KeyPicker",
    Value = tostring(opts.Default or "None"),
    Button = button,
    Changed = Signal.new(),
  }

  local internalChange = false

  local function set(value, silent, withHistory)
    value = tostring(value)

    local previous = obj.Value
    if previous == value then return end

    obj.Value = value
    button.Text = value

    if not silent then
      obj.Changed:Fire(value, previous)

      if self.Window.Events and self.Window.Events.Changed then
        self.Window.Events.Changed:Fire(name or "KeyPicker", value)
      end

      if opts.Callback then
        local ok, err = xpcall(function()
          opts.Callback(value)
        end, traceback)

        if not ok then
          warn("[X64UI] KeyPicker callback failed:\n" .. tostring(err))
        end
      end
    end

    if withHistory and not internalChange then
      self.Window.History:Push(
        "Keybind " .. tostring(opts.Text or name),
        function()
          internalChange = true
          set(previous, false, false)
          internalChange = false
        end,
        function()
          internalChange = true
          set(value, false, false)
          internalChange = false
        end
      )
    end
  end

  self.Window:Track(button.MouseButton1Click:Connect(function()
    waiting = true
    self.Window.PickingKey = true
    button.Text = "Press key..."
  end))

  self.Window:Track(UserInputService.InputBegan:Connect(function(input)
    if not waiting then return end
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

    waiting = false
    self.Window.PickingKey = false

    if input.KeyCode == Enum.KeyCode.Escape then
      set("None", false, true)
    else
      set(input.KeyCode.Name, false, true)
    end
  end))

  function obj:SetValue(value, silent)
    set(value, silent == true, false)
  end

  function obj:GetValue()
    return obj.Value
  end

  function obj:Destroy()
    obj.Changed:Destroy()
  end

  self.Window.Maid:Give(obj)
  set(obj.Value, true)

  if name then
    self.Window.Options[name] = obj
    X64UI.Options[name] = obj
  end

  return obj
end

function Groupbox:AddDivider()
  local row = createControlFrame(self, 8, false, false)

  return create("Frame", {
    Parent = row,
    Size = UDim2.new(1, 0, 0, 1),
    Position = UDim2.new(0, 0, 0.5, 0),
    BackgroundColor3 = Theme.Border,
    BorderSizePixel = 0,
  })
end

function Tab:AddLabel(...)
  return self:GetDefaultGroupbox():AddLabel(...)
end

function Tab:AddButton(...)
  return self:GetDefaultGroupbox():AddButton(...)
end

function Tab:AddToggle(...)
  return self:GetDefaultGroupbox():AddToggle(...)
end

function Tab:AddSlider(...)
  return self:GetDefaultGroupbox():AddSlider(...)
end

function Tab:AddDropdown(...)
  return self:GetDefaultGroupbox():AddDropdown(...)
end

function Tab:AddInput(...)
  return self:GetDefaultGroupbox():AddInput(...)
end

function Tab:AddKeyPicker(...)
  return self:GetDefaultGroupbox():AddKeyPicker(...)
end

function Tab:AddDivider(...)
  return self:GetDefaultGroupbox():AddDivider(...)
end

-- ==================== COMMAND REGISTRY ====================

function X64UI:RegisterCommand(name, options)
  assert(type(name) == "string", "Command name must be a string")
  assert(type(options) == "table", "Command options must be a table")
  assert(type(options.Callback) == "function", "Command callback is required")

  local command = {
    Name = name,
    Description = options.Description or "",
    Keywords = options.Keywords or {},
    Callback = options.Callback,
  }

  self.Commands[name] = command

  if not table.find(self.CommandOrder, name) then
    table.insert(self.CommandOrder, name)
  end

  return command
end

function X64UI:UnregisterCommand(name)
  self.Commands[name] = nil

  local index = table.find(self.CommandOrder, name)
  if index then
    table.remove(self.CommandOrder, index)
  end
end

function X64UI:ExecuteCommand(name, ...)
  local command = self.Commands[name]

  if not command then
    return false, "Unknown command: " .. tostring(name)
  end

  local args = table.pack(...)

  local ok, result = xpcall(function()
    return command.Callback(table.unpack(args, 1, args.n))
  end, traceback)

  if not ok then
    warn("[X64UI] Command failed:\n" .. tostring(result))
    return false, result
  end

  return true, result
end

function X64UI:RegisterDefaultCommands()
  self:RegisterCommand("Toggle Window", {
    Description = "Show or hide the interface",
    Keywords = { "menu", "visibility", "window" },
    Callback = function()
      if X64UI.CurrentWindow then
        X64UI.CurrentWindow:Toggle()
      end
    end,
  })

  self:RegisterCommand("Maximize Window", {
    Description = "Toggle maximized mode",
    Keywords = { "fullscreen", "resize" },
    Callback = function()
      local window = X64UI.CurrentWindow
      if window then
        window:SetMaximized(not window.Maximized)
      end
    end,
  })

  self:RegisterCommand("Minimize Window", {
    Description = "Toggle minimized mode",
    Keywords = { "collapse", "titlebar" },
    Callback = function()
      local window = X64UI.CurrentWindow
      if window then
        window:SetMinimized(not window.Minimized)
      end
    end,
  })

  self:RegisterCommand("Undo Last Change", {
    Description = "Undo the previous control change",
    Keywords = { "history", "reverse" },
    Callback = function()
      local window = X64UI.CurrentWindow
      if window then
        window.History:UndoLast()
      end
    end,
  })

  self:RegisterCommand("Redo Last Change", {
    Description = "Redo the last undone change",
    Keywords = { "history", "repeat" },
    Callback = function()
      local window = X64UI.CurrentWindow
      if window then
        window.History:RedoLast()
      end
    end,
  })

  self:RegisterCommand("Toggle Console", {
    Description = "Show or hide the log console",
    Keywords = { "log", "output" },
    Callback = function()
      local window = X64UI.CurrentWindow
      if window then
        window:ToggleConsole()
      end
    end,
  })

  self:RegisterCommand("Toggle Status Bar", {
    Description = "Show or hide the status bar",
    Keywords = { "footer", "fps" },
    Callback = function()
      local window = X64UI.CurrentWindow
      if window then
        window:ToggleStatusBar()
      end
    end,
  })

  self:RegisterCommand("Clear Log", {
    Description = "Clear all console messages",
    Keywords = { "console", "log", "clear" },
    Callback = function()
      local window = X64UI.CurrentWindow
      if window then
        window:ClearLog()
      end
    end,
  })

  self:RegisterCommand("Save Config", {
    Description = "Save current control values",
    Keywords = { "config", "save", "writefile" },
    Callback = function()
      local window = X64UI.CurrentWindow
      if window then
        window:SaveConfig()
      end
    end,
  })

  self:RegisterCommand("Load Config", {
    Description = "Load saved control values",
    Keywords = { "config", "load", "readfile" },
    Callback = function()
      local window = X64UI.CurrentWindow
      if window then
        window:LoadConfig()
      end
    end,
  })

  self:RegisterCommand("Command Palette", {
    Description = "Open or close the command palette",
    Keywords = { "search", "commands", "ctrl p" },
    Callback = function()
      local window = X64UI.CurrentWindow
      if window then
        window:ToggleCommandPalette()
      end
    end,
  })
end

X64UI:RegisterDefaultCommands()

-- ==================== WINDOW CREATION ====================

function X64UI:CreateWindow(options)
  options = options or {}

  if self.CurrentWindow and not self.CurrentWindow.Destroyed then
    self.CurrentWindow:Destroy()
  end

  local win = setmetatable({}, Window)

  win.Maid = Maid.new()

  win.Events = {
    Changed = Signal.new(),
    Focused = Signal.new(),
    VisibilityChanged = Signal.new(),
    Destroying = Signal.new(),
  }

  win.Maid:Give(win.Events.Changed)
  win.Maid:Give(win.Events.Focused)
  win.Maid:Give(win.Events.VisibilityChanged)
  win.Maid:Give(win.Events.Destroying)

  win.History = History.new(150)

  win.State = {
    Visible = State.new(true),
    Minimized = State.new(false),
    Maximized = State.new(false),
    ActiveTab = State.new(nil),
  }

  win.Maid:Give(win.State.Visible)
  win.Maid:Give(win.State.Minimized)
  win.Maid:Give(win.State.Maximized)
  win.Maid:Give(win.State.ActiveTab)

  win.Tabs = {}
  win.TabOrder = {}
  win.Dropdowns = {}
  win.Options = {}
  win.Toggles = {}
  win.Lines = {}

  win.Title = options.Title or "x64dbg UI"
  win.ConsoleVisible = options.Console ~= false
  win.StatusVisible = options.Status ~= false
  win.TopOffset = 54
  win.Minimized = false
  win.Maximized = false
  win.Destroyed = false
  win.PickingKey = false
  win.IntroPlayed = false
  win.CommandModifierDown = false

  local viewport = getViewportSize()
  local width = options.Width or 1020
  local height = options.Height or 660

  win.Gui = create("ScreenGui", {
    Name = options.Name or "X64UI",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = options.DisplayOrder or 10000,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    Parent = getParent(),
  })

  win.Main = create("CanvasGroup", {
    Parent = win.Gui,
    Name = "MainWindow",
    AnchorPoint = Vector2.zero,
    Size = UDim2.fromOffset(width, height),
    Position = UDim2.fromOffset(
      math.clamp((viewport.X / 2) - (width / 2), 8, viewport.X - 8),
      math.clamp((viewport.Y / 2) - (height / 2), 8, viewport.Y - 8)
    ),
    BackgroundColor3 = Theme.Background,
    BorderColor3 = Theme.Border,
    BorderSizePixel = 1,
    GroupTransparency = 1,
  })

  win.TitleBar = create("Frame", {
    Parent = win.Main,
    Size = UDim2.new(1, 0, 0, 24),
    BackgroundColor3 = Theme.TitleBar,
    BorderSizePixel = 0,
  })

  create("TextLabel", {
    Parent = win.TitleBar,
    Position = UDim2.fromOffset(8, 0),
    Size = UDim2.new(1, -100, 1, 0),
    BackgroundTransparency = 1,
    Text = win.Title,
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
  })

  win.MinButton = create("TextButton", {
    Parent = win.TitleBar,
    Position = UDim2.new(1, -60, 0, 2),
    Size = UDim2.fromOffset(28, 20),
    BackgroundColor3 = Theme.TitleBar,
    BorderSizePixel = 0,
    Text = "—",
    Font = Theme.Font,
    TextSize = 13,
    TextColor3 = Theme.Text,
  })

  win.CloseButton = create("TextButton", {
    Parent = win.TitleBar,
    Position = UDim2.new(1, -30, 0, 2),
    Size = UDim2.fromOffset(28, 20),
    BackgroundColor3 = Theme.TitleBar,
    BorderSizePixel = 0,
    Text = "X",
    Font = Theme.Font,
    TextSize = 13,
    TextColor3 = Theme.Text,
  })

  win:Track(win.MinButton.MouseEnter:Connect(function()
    win.MinButton.BackgroundColor3 = Theme.PanelAlt
  end))

  win:Track(win.MinButton.MouseLeave:Connect(function()
    win.MinButton.BackgroundColor3 = Theme.TitleBar
  end))

  win:Track(win.CloseButton.MouseEnter:Connect(function()
    win.CloseButton.BackgroundColor3 = Theme.Bad
  end))

  win:Track(win.CloseButton.MouseLeave:Connect(function()
    win.CloseButton.BackgroundColor3 = Theme.TitleBar
  end))

  win:Track(win.MinButton.MouseButton1Click:Connect(function()
    win:SetMinimized(not win.Minimized)
  end))

  win:Track(win.CloseButton.MouseButton1Click:Connect(function()
    win:Destroy()
  end))

  local lastTitleClick = 0

  win:Track(win.TitleBar.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

    local now = os.clock()

    if now - lastTitleClick <= 0.24 then
      win:SetMaximized(not win.Maximized)
      lastTitleClick = 0
    else
      lastTitleClick = now
    end
  end))

  win.TabBar = create("ScrollingFrame", {
    Parent = win.Main,
    Position = UDim2.fromOffset(0, 24),
    Size = UDim2.new(1, 0, 0, 26),
    BackgroundColor3 = Theme.Menu,
    BorderSizePixel = 0,
    ScrollBarThickness = 0,
    ScrollingDirection = Enum.ScrollingDirection.X,
    CanvasSize = UDim2.new(),
  })

  local tabLayout = create("UIListLayout", {
    Parent = win.TabBar,
    FillDirection = Enum.FillDirection.Horizontal,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 1),
  })

  win:Track(tabLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    win.TabBar.CanvasSize = UDim2.fromOffset(tabLayout.AbsoluteContentSize.X + 8, 0)
  end))

  win.Pages = create("Frame", {
    Parent = win.Main,
    Position = UDim2.fromOffset(4, win.TopOffset),
    Size = UDim2.new(1, -8, 1, -(win.TopOffset + 160 + 22 + 8)),
    BackgroundColor3 = Theme.Background,
    BorderColor3 = Theme.Border,
    BorderSizePixel = 1,
  })

  win.Console = create("Frame", {
    Parent = win.Main,
    Visible = win.ConsoleVisible,
    BackgroundColor3 = Theme.Panel,
    BorderColor3 = Theme.Border,
  })

  local consoleHeader = create("Frame", {
    Parent = win.Console,
    Size = UDim2.new(1, 0, 0, 20),
    BackgroundColor3 = Theme.PanelAlt,
    BorderSizePixel = 0,
  })

  create("TextLabel", {
    Parent = consoleHeader,
    Position = UDim2.fromOffset(6, 0),
    Size = UDim2.new(1, -110, 1, 0),
    BackgroundTransparency = 1,
    Text = "Log",
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Warning,
  })

  local clearButton = create("TextButton", {
    Parent = consoleHeader,
    Position = UDim2.new(1, -56, 0, 0),
    Size = UDim2.fromOffset(56, 20),
    BackgroundColor3 = Theme.PanelAlt,
    BorderSizePixel = 0,
    Text = "Clear",
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
  })

  win:Track(clearButton.MouseButton1Click:Connect(function()
    win:ClearLog()
  end))

  win.LogScroll = create("ScrollingFrame", {
    Parent = win.Console,
    Position = UDim2.fromOffset(0, 20),
    Size = UDim2.new(1, 0, 1, -20),
    BackgroundColor3 = Theme.Background,
    BorderSizePixel = 0,
    ScrollBarThickness = 8,
    ScrollBarImageColor3 = Theme.Scroll,
    CanvasSize = UDim2.new(),
  })

  win.LogLabel = create("TextLabel", {
    Parent = win.LogScroll,
    Size = UDim2.new(1, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1,
    Text = "",
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
    TextWrapped = true,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
  })

  create("UIPadding", {
    Parent = win.LogScroll,
    PaddingTop = UDim.new(0, 4),
    PaddingLeft = UDim.new(0, 4),
    PaddingRight = UDim.new(0, 4),
    PaddingBottom = UDim.new(0, 4),
  })

  win.StatusBar = create("Frame", {
    Parent = win.Main,
    Position = UDim2.new(0, 0, 1, -22),
    Size = UDim2.new(1, 0, 0, 22),
    BackgroundColor3 = Theme.TitleBar,
    BorderSizePixel = 0,
  })

  win.StatusLabel = create("TextLabel", {
    Parent = win.StatusBar,
    Position = UDim2.fromOffset(8, 0),
    Size = UDim2.new(0.6, -16, 1, 0),
    BackgroundTransparency = 1,
    Text = "Ready",
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
  })

  win.StatusRight = create("TextLabel", {
    Parent = win.StatusBar,
    Position = UDim2.new(0.6, 0, 0, 0),
    Size = UDim2.new(0.4, -8, 1, 0),
    BackgroundTransparency = 1,
    Text = "FPS: --",
    TextXAlignment = Enum.TextXAlignment.Right,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Dim,
  })

  win.Grip = create("TextButton", {
    Parent = win.Main,
    Position = UDim2.new(1, -14, 1, -14),
    Size = UDim2.fromOffset(14, 14),
    BackgroundTransparency = 1,
    Text = "◢",
    Font = Theme.Font,
    TextSize = 12,
    TextColor3 = Theme.Dim,
  })

  win:MakeDraggable(win.Main, win.TitleBar)
  win:MakeResizable(win.Main, win.Grip)
  win:CreateCommandPalette()

  win:Track(win.Main.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
      win:Focus()
    end
  end))

  win:Track(UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

    if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
      win.CommandModifierDown = true
    end

    if win.CommandModifierDown and input.KeyCode == Enum.KeyCode.P then
      win:ToggleCommandPalette()
      return
    end

    if win.PickingKey then return end
    if gameProcessed then return end
    if UserInputService:GetFocusedTextBox() then return end

    local key = X64UI.MenuKeybind

    if typeof(key) == "string" then
      local ok, enumKey = pcall(function()
        return Enum.KeyCode[key]
      end)

      if ok then
        key = enumKey
      else
        return
      end
    end

    if input.KeyCode == key then
      win:Toggle()
    end
  end))

  win:Track(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Keyboard then
      if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
        win.CommandModifierDown = false
      end
    end
  end))

  win:Track(UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

    task.defer(function()
      if win.Destroyed then return end

      if win.CommandPalette and win.CommandPalette.Visible then
        if not mouseOverGui(win.CommandPalette) then
          win:CloseCommandPalette()
        end
      end

      for _, dropdown in ipairs(win.Dropdowns) do
        if dropdown.List and dropdown.List.Visible then
          local tooSoon = os.clock() - dropdown.OpenedAt < 0.05

          if not tooSoon and not mouseOverGui(dropdown.Button) and not mouseOverGui(dropdown.List) then
            dropdown:Close()
          end
        end
      end
    end)
  end))

  win:Track(RunService.RenderStepped:Connect(function()
    if win.Destroyed then return end

    for _, dropdown in ipairs(win.Dropdowns) do
      if dropdown.List and dropdown.List.Visible then
        if not win.Main.Visible or win.Minimized then
          dropdown:Close()
        else
          dropdown:RefreshPosition()
        end
      end
    end
  end))

  local frames = 0
  local last = os.clock()

  win:Track(RunService.RenderStepped:Connect(function()
    frames += 1

    if os.clock() - last >= 1 then
      if win.StatusRight and win.StatusRight.Parent then
        win.StatusRight.Text = string.format("FPS: %d | %s", frames, os.date("%X"))
      end

      frames = 0
      last = os.clock()
    end
  end))

  win:Track(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    task.defer(function()
      if win.Destroyed then return end

      if win.Maximized then
        local newViewport = getViewportSize()
        win.Main.Position = UDim2.fromOffset(0, 0)
        win.Main.Size = UDim2.fromOffset(newViewport.X, newViewport.Y)
        win:UpdateLayout()
      else
        win:ClampToViewport()
      end
    end)
  end))

  win:UpdateLayout()
  win:PlayIntro()

  X64UI.CurrentWindow = win
  return win
end

-- ==================== NOTIFICATIONS ====================

function X64UI:Notify(opts)
  opts = opts or {}

  local parent

  if self.CurrentWindow and not self.CurrentWindow.Destroyed and self.CurrentWindow.Gui and self.CurrentWindow.Gui.Parent then
    parent = self.CurrentWindow.Gui
  else
    if not self.NotifyGui or not self.NotifyGui.Parent then
      self.NotifyGui = create("ScreenGui", {
        Name = "X64Notify",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 999999,
        Parent = getParent(),
      })
    end

    parent = self.NotifyGui
  end

  local container = parent:FindFirstChild("X64Notifications")

  if not container then
    container = create("Frame", {
      Parent = parent,
      Name = "X64Notifications",
      AnchorPoint = Vector2.new(1, 1),
      Position = UDim2.new(1, -12, 1, -12),
      Size = UDim2.fromOffset(280, 0),
      AutomaticSize = Enum.AutomaticSize.Y,
      BackgroundTransparency = 1,
      ZIndex = 10000,
    })

    create("UIListLayout", {
      Parent = container,
      Padding = UDim.new(0, 8),
      SortOrder = Enum.SortOrder.LayoutOrder,
      HorizontalAlignment = Enum.HorizontalAlignment.Right,
      VerticalAlignment = Enum.VerticalAlignment.Bottom,
    })
  end

  local toast = create("CanvasGroup", {
    Parent = container,
    Size = UDim2.new(1, 0, 0, 58),
    BackgroundColor3 = Theme.Panel,
    BorderColor3 = Theme.Border,
    GroupTransparency = 1,
    LayoutOrder = math.floor(os.clock() * 1000),
    ZIndex = 10001,
  })

  create("TextLabel", {
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

  create("TextLabel", {
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

  task.delay(opts.Time or 3, function()
    if toast and toast.Parent then
      local tween = TweenService:Create(
        toast,
        TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        { GroupTransparency = 1 }
      )

      tween:Play()

      tween.Completed:Connect(function()
        toast:Destroy()
      end)
    end
  end)
end

-- ==================== DEMO ====================

do
  local window = X64UI:CreateWindow({
    Title = "Advanced X64UI",
    Width = 1020,
    Height = 660,
  })

  local main = window:AddTab("Main")
  local left = main:AddLeftGroupbox("Controls")
  local right = main:AddRightGroupbox("System")

  left:AddLabel("Desktop-only build.", true)
  left:AddLabel("Ctrl+P opens the command palette.", true)
  left:AddLabel("Toggle, slider, dropdown, input, and keybind changes support undo/redo.", true)

  local enabled = left:AddToggle("Enabled", {
    Text = "Enable system",
    Default = true,
    Callback = function(value)
      window:Log("Enabled -> " .. tostring(value))
    end,
  })

  left:AddSlider("Speed", {
    Text = "Speed",
    Min = 0,
    Max = 100,
    Default = 50,
    Rounding = 0,
    Callback = function(value)
      window:SetStatus("Speed: " .. tostring(value))
    end,
  })

  left:AddDropdown("Mode", {
    Text = "Mode",
    Values = { "Safe", "Balanced", "Aggressive", "Custom" },
    Default = "Balanced",
    Callback = function(value)
      window:Log("Mode -> " .. tostring(value))
    end,
  })

  left:AddInput("Note", {
    Text = "Note",
    Placeholder = "Type something",
    Callback = function(value)
      window:Log("Note -> " .. tostring(value))
    end,
  })

  left:AddKeyPicker("Hotkey", {
    Text = "Example Hotkey",
    Default = "None",
    Callback = function(value)
      window:Log("Hotkey -> " .. tostring(value))
    end,
  })

  right:AddButton({
    Text = "Notify",
    Callback = function()
      X64UI:Notify({
        Title = "X64UI",
        Description = "Advanced architecture loaded.",
        Time = 3,
      })
    end,
  })

  right:AddButton({
    Text = "Save Config",
    Callback = function()
      window:SaveConfig()
    end,
  })

  right:AddButton({
    Text = "Load Config",
    Callback = function()
      window:LoadConfig()
    end,
  })

  right:AddButton({
    Text = "Undo",
    Callback = function()
      window.History:UndoLast()
    end,
  })

  right:AddButton({
    Text = "Redo",
    Callback = function()
      window.History:RedoLast()
    end,
  })

  right:AddButton({
    Text = "Unload",
    Callback = function()
      window:Destroy()
    end,
  })

  X64UI:RegisterCommand("Reset Controls", {
    Description = "Restore demo controls to defaults",
    Keywords = { "reset", "defaults", "configuration" },
    Callback = function()
      enabled:SetValue(true)
      window.Options.Speed:SetValue(50)
      window.Options.Mode:SetValue("Balanced")
      window.Options.Note:SetValue("")
      window.Options.Hotkey:SetValue("None")
      window.History:Clear()
      window:SetStatus("Controls reset")
    end,
  })

  window:Log("X64UI advanced desktop build loaded.")
  window:SetStatus("Ready")
end

-- Optional global export for loadstring/loaders.
if getgenv then
  getgenv().X64UI = X64UI
elseif shared then
  shared.X64UI = X64UI
end

return X64UI
