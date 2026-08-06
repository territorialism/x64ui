--[[
made by iris
d = desktop
5.1.0d
]]

local X64UI = {
  Version = "5.1.0d",
  MenuKeybind = Enum.KeyCode.RightShift,
  Windows = {},
  ActiveWindow = nil,
  NotifyGui = nil,
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

local unpack = unpack or table.unpack

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

-- ==================== PHASE 1: STRUCTURAL FIXES ====================

-- core/log.lua
local Log = {}
function Log.info(m) print("[X64UI] " .. tostring(m)) end
function Log.warn(m) warn("[X64UI] " .. tostring(m)) end
function Log.error(m) warn("[X64UI ERROR] " .. tostring(m)) end

-- core/platform.lua
local Platform = {}
function Platform.readFile(p) return isfile and isfile(p) and readfile and readfile(p) or nil end
function Platform.writeFile(p, d) if writefile then writefile(p, d) return true end return false end
function Platform.fileExists(p) return isfile and isfile(p) or false end
function Platform.deleteFile(p) if delfile then delfile(p) end end

-- ui/glyphs.lua (Replaces corrupted Unicode strings)
local Glyphs = {
  Check = "\226\156\147",       -- ✓
  Cross = "\226\156\149",       -- ✕
  ArrowDown = "\226\150\188",   -- ▼
  ArrowRight = "\226\150\182",  -- ▶
  Grip = "\226\151\162",        -- ◢
  Minimize = "\226\128\148",    -- —
  Close = "X",
  Search = "\240\159\148\141"   -- 🔍
}

-- services/registry.lua
local Registry = {}
Registry.__index = Registry
function Registry.new()
  return setmetatable({ Controls = {}, Toggles = {}, Options = {} }, Registry)
end
function Registry:Register(name, control, controlType)
  if not name then return end
  self.Controls[name] = control
  if controlType == "Toggle" then
    self.Toggles[name] = control
  else
    self.Options[name] = control
  end
end
function Registry:Unregister(name)
  self.Controls[name] = nil
  self.Toggles[name] = nil
  self.Options[name] = nil
end
function Registry:Get(name) return self.Controls[name] end
function Registry:Clear()
  for _, c in pairs(self.Controls) do
    if c.Destroy then pcall(c.Destroy, c) end
  end
  table.clear(self.Controls)
  table.clear(self.Toggles)
  table.clear(self.Options)
end

-- core/create.lua (Strict replacement for create())
local Create = {}
function Create.create(className, props, children)
  assert(type(className) == "string", "Create.create: className must be a string")
  assert(props == nil or type(props) == "table", "Create.create: props must be a table or nil")
  assert(children == nil or type(children) == "table", "Create.create: children must be a table or nil")
  
  local inst = Instance.new(className)
  for k, v in pairs(props or {}) do
    if k ~= "Parent" then
      pcall(function() inst[k] = v end)
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
          binding.Callback(unpack(arguments, 1, arguments.n))
        end, traceback)

        if not ok then
          Log.warn("Signal callback failed:\n" .. tostring(err))
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

-- ==================== HISTORY (Phase 4: Transaction-Aware) ====================

local History = {}
History.__index = History

function History.new(limit)
  return setmetatable({
    UndoStack = {},
    RedoStack = {},
    Limit = limit or 100,
    Applying = false,
    Transaction = nil,
  }, History)
end

function History:BeginTransaction(label)
  self.Transaction = { Label = label, Undos = {}, Redos = {} }
end

function History:EndTransaction()
  if not self.Transaction then return end
  local t = self.Transaction
  self.Transaction = nil
  if #t.Undos > 0 then
    self:Push(t.Label, 
      function() for i = #t.Undos, 1, -1 do t.Undos[i]() end end, 
      function() for i = 1, #t.Redos do t.Redos[i]() end end
    )
  end
end

function History:Push(label, undo, redo)
  if self.Applying then
    return
  end

  if self.Transaction then
    table.insert(self.Transaction.Undos, undo)
    table.insert(self.Transaction.Redos, redo)
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
    Log.warn("Undo failed:\n" .. tostring(err))
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
    Log.warn("Redo failed:\n" .. tostring(err))
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

-- ==================== PHASE 3: LIFECYCLE HARDENING (InputManager) ====================

local InputManager = { Capturing = false, Callback = nil }
function InputManager:Capture(cb) self.Capturing = true self.Callback = cb end
function InputManager:Cancel() self.Capturing = false self.Callback = nil end

-- ==================== PHASE 5: UX (Tooltips & Modals) ====================

local TooltipGui, TooltipLabel
local function InitTooltip()
  if TooltipGui then return end
  TooltipGui = Create.create("ScreenGui", {
    Name = "X64Tooltip", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 99999, Parent = getParent()
  })
  TooltipLabel = Create.create("TextLabel", {
    Parent = TooltipGui, Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY,
    BackgroundColor3 = Theme.PanelAlt, BorderColor3 = Theme.Border, Text = "",
    Font = Theme.Font, TextSize = Theme.TextSize, TextColor3 = Theme.Text, Visible = false, ZIndex = 99999
  })
end

local function ShowTooltip(text, pos)
  InitTooltip()
  TooltipLabel.Text = text
  TooltipLabel.Position = UDim2.fromOffset(pos.X + 10, pos.Y + 10)
  TooltipLabel.Visible = true
end

local function HideTooltip() if TooltipLabel then TooltipLabel.Visible = false end end

function X64UI:Dialog(opts)
  opts = opts or {}
  local gui = Create.create("ScreenGui", {
    Name = "X64Dialog", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 99998, Parent = getParent()
  })
  local bg = Create.create("Frame", {
    Parent = gui, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0,0,0), BackgroundTransparency = 0.5, ZIndex = 99990
  })
  local frame = Create.create("Frame", {
    Parent = gui, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(400, 200), BackgroundColor3 = Theme.Panel, BorderColor3 = Theme.Border, ZIndex = 99991
  })
  local closeBtn = Create.create("TextButton", {
    Parent = frame, Size = UDim2.fromOffset(80, 30), Position = UDim2.new(0.5, -40, 1, -40),
    BackgroundColor3 = Theme.Button, Text = "Close", Font = Theme.Font, TextSize = Theme.TextSize, TextColor3 = Theme.Text, ZIndex = 99992
  })
  closeBtn.MouseButton1Click:Connect(function() gui:Destroy() end)
end

-- ==================== HELPERS ====================

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

  local player = Players.LocalPlayer
  if not player then
    repeat task.wait() player = Players.LocalPlayer until player
  end
  return player:WaitForChild("PlayerGui")
end

local function getViewportSize()
  local cam = Workspace.CurrentCamera
  local viewport = cam and cam.ViewportSize or Vector2.new(1280, 720)

  local ok, inset = pcall(function()
    return GuiService:GetGuiInset()
  end)

  if ok and inset then
    return viewport + inset
  end

  return viewport
end

local function getMousePos()
  return UserInputService:GetMouseLocation()
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
  local ok, mouse = pcall(getMousePos)
  if not ok or not mouse then return false end

  local inset = GuiService:GetGuiInset()
  return pointInGui(gui, mouse) or pointInGui(gui, mouse - inset)
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
    if typeof(value) ~= "string" and typeof(value) ~= "number" and typeof(value) ~= "table" then
      return false
    end

    if control.Values and typeof(value) ~= "table" then
      return table.find(control.Values, value) ~= nil
    end

    return true
  end

  if control.Type == "Input" or control.Type == "KeyPicker" then
    return typeof(value) == "string"
  end

  return false
end

local function getWindowResizeLimits()
  local viewport = getViewportSize()
  local margin = 8

  local maxW = math.max(1, viewport.X - margin * 2)
  local maxH = math.max(1, viewport.Y - margin * 2)

  local minW = math.min(760, maxW)
  local minH = math.min(420, maxH)

  return viewport, margin, Vector2.new(minW, minH), Vector2.new(maxW, maxH)
end

-- ==================== CLASSES ====================

local Window = {}
Window.__index = Window

local Tab = {}
Tab.__index = Tab

local Groupbox = {}
Groupbox.__index = Groupbox

-- ==================== PHASE 2: CONTROL API STANDARDIZATION (BaseControl) ====================

local BaseControl = {}
BaseControl.__index = BaseControl
function BaseControl.new(type, frame, window, name)
  return setmetatable({ Type = type, Frame = frame, Window = window, Name = name, Visible = true, Disabled = false, ReadOnly = false }, BaseControl)
end
function BaseControl:SetVisible(v) self.Visible = v if self.Frame then self.Frame.Visible = v end end
function BaseControl:SetDisabled(v) self.Disabled = v end
function BaseControl:SetReadOnly(v) self.ReadOnly = v end
function BaseControl:Destroy()
  if self.Frame then pcall(function() self.Frame:Destroy() end) end
  if self.Window and self.Window.Registry and self.Name then self.Window.Registry:Unregister(self.Name) end
end

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

  X64UI.ActiveWindow = self

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
      pcall(function() dropdown:Close() end)
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
  if self.Destroyed or self.Maximized or self.Minimized then return end
  if not self.Main or not self.Main.Parent then return end

  local viewport, margin, minSize, maxSize = getWindowResizeLimits()

  local currentSize = Vector2.new(self.Main.AbsoluteSize.X, self.Main.AbsoluteSize.Y)
  local size = Vector2.new(
    math.clamp(currentSize.X, minSize.X, maxSize.X),
    math.clamp(currentSize.Y, minSize.Y, maxSize.Y)
  )

  if size.X ~= currentSize.X or size.Y ~= currentSize.Y then
    self.Main.Size = UDim2.fromOffset(size.X, size.Y)
    self:UpdateLayout()
  end

  local posX = self.Main.Position.X.Offset
  local posY = self.Main.Position.Y.Offset

  local maxX = math.max(margin, viewport.X - size.X - margin)
  local maxY = math.max(margin, viewport.Y - size.Y - margin)

  self.Main.Position = UDim2.fromOffset(
    math.clamp(posX, margin, maxX),
    math.clamp(posY, margin, maxY)
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

  if self.Registry then
    self.Registry:Clear()
  end

  if self.Gui then
    self.Gui:Destroy()
    self.Gui = nil
  end

  for i, win in ipairs(X64UI.Windows) do
    if win == self then
      table.remove(X64UI.Windows, i)
      break
    end
  end

  if X64UI.ActiveWindow == self then
    X64UI.ActiveWindow = X64UI.Windows[#X64UI.Windows] or nil
  end
end

function Window:PlayIntro()
  if self.IntroPlayed or self.Destroyed then return end
  self.IntroPlayed = true

  pcall(function()
    local wash = Create.create("CanvasGroup", {
      Parent = self.Gui,
      Size = UDim2.fromScale(1, 1),
      BackgroundColor3 = Color3.fromRGB(7, 7, 9),
      BackgroundTransparency = 0,
      GroupTransparency = 0,
      BorderSizePixel = 0,
      ZIndex = 32767,
    })

    if self.Maid then
      self.Maid:Give(wash)
    end

    local gradient = Create.create("UIGradient", {
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
    startMouse = getMousePos()
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
      local current = getMousePos()
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

  local function normalizeSize()
    local _, _, minSize, maxSize = getWindowResizeLimits()

    local current = Vector2.new(frame.AbsoluteSize.X, frame.AbsoluteSize.Y)
    local fixed = Vector2.new(
      math.clamp(current.X, minSize.X, maxSize.X),
      math.clamp(current.Y, minSize.Y, maxSize.Y)
    )

    if fixed.X ~= current.X or fixed.Y ~= current.Y then
      frame.Size = UDim2.fromOffset(fixed.X, fixed.Y)
      self:UpdateLayout()
    end

    return fixed
  end

  local function beginResize(input)
    if not canResize() then return end

    resizing = true
    startMouse = getMousePos()
    startSize = normalizeSize()
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
      local _, _, minSize, maxSize = getWindowResizeLimits()
      local current = getMousePos()

      local nextSize = Vector2.new(
        math.clamp(startSize.X + (current.X - startMouse.X), minSize.X, maxSize.X),
        math.clamp(startSize.Y + (current.Y - startMouse.Y), minSize.Y, maxSize.Y)
      )

      frame.Size = UDim2.fromOffset(nextSize.X, nextSize.Y)

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

  tab.Button = Create.create("TextButton", {
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

  tab.Underline = Create.create("Frame", {
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

  tab.Page = Create.create("Frame", {
    Parent = self.Pages,
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Visible = false,
  })

  tab.LeftPane = Create.create("ScrollingFrame", {
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

  tab.RightPane = Create.create("ScrollingFrame", {
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

  local leftList = Create.create("UIListLayout", {
    Parent = tab.LeftPane,
    Padding = UDim.new(0, 4),
    SortOrder = Enum.SortOrder.LayoutOrder,
  })

  local rightList = Create.create("UIListLayout", {
    Parent = tab.RightPane,
    Padding = UDim.new(0, 4),
    SortOrder = Enum.SortOrder.LayoutOrder,
  })

  Create.create("UIPadding", {
    Parent = tab.LeftPane,
    PaddingTop = UDim.new(0, 4),
    PaddingLeft = UDim.new(0, 4),
    PaddingRight = UDim.new(0, 4),
    PaddingBottom = UDim.new(0, 4),
  })

  Create.create("UIPadding", {
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

-- ==================== CONFIG (Phase 4: State and Config) ====================

function Window:SaveConfig(path)
  path = path or "x64ui_config.json"

  if not Platform.writeFile then
    self:Log("writefile is not supported by this executor.")
    return false
  end

  local data = {
    Version = 2,
    Toggles = {},
    Options = {},
    Layout = {},
  }

  for name, toggle in pairs(self.Registry.Toggles) do
    if typeof(toggle.Value) == "boolean" then
      data.Toggles[name] = toggle.Value
    end
  end

  for name, option in pairs(self.Registry.Options) do
    local valueType = typeof(option.Value)

    if valueType == "number" or valueType == "string" or valueType == "boolean" or valueType == "table" then
      data.Options[name] = option.Value
    end
  end

  data.Layout = {
    Size = { self.Main.Size.X.Offset, self.Main.Size.Y.Offset },
    Pos = { self.Main.Position.X.Offset, self.Main.Position.Y.Offset },
  }

  local ok, json = pcall(function()
    return HttpService:JSONEncode(data)
  end)

  if ok then
    Platform.writeFile(path, json)
    self:Log("Config saved: " .. path)
  else
    self:Log("Config encode failed.")
  end

  return ok
end

function Window:LoadConfig(path, loadOpts)
  path = path or "x64ui_config.json"
  loadOpts = loadOpts or {}

  local silent = loadOpts.Silent
  local fireCallbacks = loadOpts.FireCallbacks ~= false
  local recordHistory = loadOpts.RecordHistory ~= false
  local applyLayout = loadOpts.ApplyLayout ~= false

  if not Platform.fileExists(path) then
    self:Log("Config file not found.")
    return false
  end

  local json = Platform.readFile(path)
  if not json then
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

  -- Config migrations (Phase 4)
  if not data.Version or data.Version < 2 then
    data.Layout = data.Layout or {}
    data.Version = 2
  end

  if recordHistory then self.History:BeginTransaction("Load Config") end

  if typeof(data.Toggles) == "table" then
    for name, value in pairs(data.Toggles) do
      local toggle = self.Registry:Get(name)
      if toggle and toggle.SetValue and isControlValueValid(toggle, value) then
        toggle:SetValue(value, not fireCallbacks)
      end
    end
  end

  if typeof(data.Options) == "table" then
    for name, value in pairs(data.Options) do
      local option = self.Registry:Get(name)

      if option and option.SetValue then
        if option.Type == "Slider" and typeof(value) == "number" then
          value = math.clamp(value, option.Min or value, option.Max or value)
        end

        if isControlValueValid(option, value) then
          option:SetValue(value, not fireCallbacks)
        end
      end
    end
  end

  if applyLayout and typeof(data.Layout) == "table" then
    if data.Layout.Size then self.Main.Size = UDim2.fromOffset(data.Layout.Size[1], data.Layout.Size[2]) end
    if data.Layout.Pos then self.Main.Position = UDim2.fromOffset(data.Layout.Pos[1], data.Layout.Pos[2]) end
    self:ClampToViewport()
    self:UpdateLayout()
  end

  if recordHistory then self.History:EndTransaction() end
  if not silent then self:Log(("Config loaded: %s"):format(path)) end
  return true
end

-- ==================== COMMAND PALETTE ====================

function Window:CreateCommandPalette()
  local palette = Create.create("Frame", {
    Parent = self.Gui,
    AnchorPoint = Vector2.new(0.5, 0),
    Position = UDim2.new(0.5, 0, 0, 90),
    Size = UDim2.fromOffset(520, 320),
    BackgroundColor3 = Theme.Panel,
    BorderColor3 = Theme.Border,
    Visible = false,
    ZIndex = 5000,
  })

  local input = Create.create("TextBox", {
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

  local results = Create.create("ScrollingFrame", {
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

  local layout = Create.create("UIListLayout", {
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
            text = text .. " — " .. command.Description
          end

          local item = Create.create("TextButton", {
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

  group.Frame = Create.create("Frame", {
    Parent = parent,
    Size = UDim2.new(1, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundColor3 = Theme.Panel,
    BorderColor3 = Theme.Border,
    LayoutOrder = order,
  })

  Create.create("UIListLayout", {
    Parent = group.Frame,
    SortOrder = Enum.SortOrder.LayoutOrder,
  })

  Create.create("TextLabel", {
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

  group.Content = Create.create("Frame", {
    Parent = group.Frame,
    LayoutOrder = 1,
    Size = UDim2.new(1, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1,
  })

  group.Layout = Create.create("UIListLayout", {
    Parent = group.Content,
    Padding = UDim.new(0, 4),
    SortOrder = Enum.SortOrder.LayoutOrder,
  })

  Create.create("UIPadding", {
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
  local row = Create.create("Frame", {
    Parent = group.Content,
    Size = UDim2.new(1, 0, 0, height or 24),
    BackgroundTransparency = 1,
    LayoutOrder = group.NextOrder,
  })

  group.NextOrder += 1

  if automatic then
    row.AutomaticSize = Enum.AutomaticSize.Y
  end

  local layout = Create.create("UIListLayout", {
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

  local label = Create.create("TextLabel", {
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

  local obj = BaseControl.new("Label", row, self.Window, nil)
  obj.Label = label
  function obj:SetText(newText) label.Text = tostring(newText) end
  return obj
end

function Groupbox:AddButton(opts)
  opts = opts or {}

  local row = createControlFrame(self, 26, false, false)

  local button = Create.create("TextButton", {
    Parent = row,
    Size = UDim2.new(1, 0, 1, 0),
    BackgroundColor3 = Theme.Button,
    BorderColor3 = Theme.Border,
    Text = opts.Text or "Button",
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
  })

  local obj = BaseControl.new("Button", row, self.Window, nil)
  obj.Button = button

  function obj:SetText(newText) button.Text = tostring(newText) end

  self.Window:Track(button.MouseEnter:Connect(function()
    button.BackgroundColor3 = Theme.ButtonHover
  end))

  self.Window:Track(button.MouseLeave:Connect(function()
    button.BackgroundColor3 = Theme.Button
  end))

  self.Window:Track(button.MouseButton1Click:Connect(function()
    if not obj.Disabled and opts.Callback then
      local ok, err = xpcall(opts.Callback, traceback)
      if not ok then
        Log.warn("Button callback failed:\n" .. tostring(err))
      end
    end

    self.Window:Log("Button: " .. tostring(opts.Text or "Button"))
  end))

  return obj
end

function Groupbox:AddToggle(name, opts)
  opts = opts or {}

  local row = createControlFrame(self, 22, false, true)
  local state = State.new(opts.Default == true)

  local check = Create.create("TextButton", {
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

  local label = Create.create("TextButton", {
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

  local obj = BaseControl.new("Toggle", row, self.Window, name)
  obj.Value = state:Get()
  obj.Button = check
  obj.Changed = Signal.new()

  local internalChange = false

  local function render(value)
    obj.Value = value
    check.Text = value and Glyphs.Check or ""
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
          opts.Callback(value, previous)
        end, traceback)

        if not ok then
          Log.warn("Toggle callback failed:\n" .. tostring(err))
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

  self.Window.Maid:Give(obj)
  render(state:Get())

  if name then
    self.Window.Registry:Register(name, obj, "Toggle")
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

  local header = Create.create("Frame", {
    Parent = row,
    Size = UDim2.new(1, 0, 0, 16),
    BackgroundTransparency = 1,
  })

  Create.create("UIListLayout", {
    Parent = header,
    FillDirection = Enum.FillDirection.Horizontal,
    VerticalAlignment = Enum.VerticalAlignment.Center,
  })

  Create.create("TextLabel", {
    Parent = header,
    Size = UDim2.new(1, -70, 1, 0),
    BackgroundTransparency = 1,
    Text = opts.Text or name or "Slider",
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
  })

  local valueLabel = Create.create("TextLabel", {
    Parent = header,
    Size = UDim2.fromOffset(70, 16),
    BackgroundTransparency = 1,
    Text = "",
    TextXAlignment = Enum.TextXAlignment.Right,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.AccentText,
  })

  local bar = Create.create("TextButton", {
    Parent = row,
    Size = UDim2.new(1, 0, 0, 14),
    BackgroundColor3 = Theme.PanelAlt,
    BorderColor3 = Theme.Border,
    Text = "",
    AutoButtonColor = false,
  })

  local fill = Create.create("Frame", {
    Parent = bar,
    Size = UDim2.fromScale(0, 1),
    BackgroundColor3 = Theme.Accent,
    BorderSizePixel = 0,
  })

  local obj = BaseControl.new("Slider", row, self.Window, name)
  obj.Value = value
  obj.Min = min
  obj.Max = max
  obj.Changed = Signal.new()

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
          opts.Callback(v, previous)
        end, traceback)

        if not ok then
          Log.warn("Slider callback failed:\n" .. tostring(err))
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

  self.Window.Maid:Give(obj)
  set(value, true)

  if name then
    self.Window.Registry:Register(name, obj, "Option")
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

  if not table.find(values, selected) and not opts.Multi then
    selected = values[1]
  end

  local row = createControlFrame(self, nil, true, false)

  Create.create("TextLabel", {
    Parent = row,
    Size = UDim2.new(1, 0, 0, 16),
    BackgroundTransparency = 1,
    Text = opts.Text or name or "Dropdown",
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
  })

  local button = Create.create("TextButton", {
    Parent = row,
    Size = UDim2.new(1, 0, 0, 20),
    BackgroundColor3 = Theme.PanelAlt,
    BorderColor3 = Theme.Border,
    Text = Glyphs.ArrowDown .. " " .. tostring(selected),
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
  })

  local list = Create.create("ScrollingFrame", {
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

  local searchBox = Create.create("TextBox", {
    Parent = list,
    Size = UDim2.new(1, 0, 0, 20),
    BackgroundColor3 = Theme.PanelAlt,
    BorderColor3 = Theme.Border,
    PlaceholderText = Glyphs.Search .. " Search",
    Text = "",
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
    ZIndex = 2001,
  })

  local listLayout = Create.create("UIListLayout", {
    Parent = list,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 1),
  })

  local obj = BaseControl.new("Dropdown", row, self.Window, name)
  obj.Value = opts.Multi and {} or selected
  obj.Values = values
  obj.Button = button
  obj.List = list
  obj.OpenedAt = 0
  obj.Changed = Signal.new()

  local internalChange = false

  local function getListHeight()
    return math.min((#values * 19) + 22, 220)
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
    local previous = obj.Value
    if not opts.Multi and not table.find(values, value) then return end
    
    obj.Value = value
    if opts.Multi then
      button.Text = Glyphs.ArrowDown .. " " .. tostring(#value) .. " selected"
    else
      button.Text = Glyphs.ArrowDown .. " " .. tostring(value)
    end

    if not silent then
      obj.Changed:Fire(value, previous)

      if self.Window.Events and self.Window.Events.Changed then
        self.Window.Events.Changed:Fire(name or "Dropdown", value)
      end

      if opts.Callback then
        local ok, err = xpcall(function()
          opts.Callback(value, previous)
        end, traceback)

        if not ok then
          Log.warn("Dropdown callback failed:\n" .. tostring(err))
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

  local function buildItems()
    for _, child in ipairs(list:GetChildren()) do
      if child:IsA("TextButton") and child ~= searchBox then child:Destroy() end
    end

    local query = string.lower(searchBox.Text or "")
    local order = 1

    for i, value in ipairs(values) do
      if query == "" or string.find(string.lower(tostring(value)), query, 1, true) then
        local item = Create.create("TextButton", {
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
          if opts.Multi then
            local current = table.clone(obj.Value)
            local idx = table.find(current, value)
            if idx then table.remove(current, idx) else table.insert(current, value) end
            set(current, false, true)
          else
            set(value, false, true)
            obj:Close()
          end
        end))
        order += 1
      end
    end
    list.CanvasSize = UDim2.fromOffset(0, listLayout.AbsoluteContentSize.Y + 2)
  end

  self.Window:Track(searchBox:GetPropertyChangedSignal("Text"):Connect(buildItems))
  buildItems()

  function obj:SetValue(value, silent)
    set(value, silent == true, false)
  end

  function obj:GetValue()
    return obj.Value
  end

  function obj:Destroy()
    obj.Changed:Destroy()
    if self.List then pcall(function() self.List:Destroy() end) end
    BaseControl.Destroy(self)
  end

  self.Window.Maid:Give(obj)
  if not opts.Multi then set(selected, true) end
  table.insert(self.Window.Dropdowns, obj)

  if name then
    self.Window.Registry:Register(name, obj, "Option")
  end

  return obj
end

function Groupbox:AddInput(name, opts)
  opts = opts or {}

  local row = createControlFrame(self, nil, true, false)

  Create.create("TextLabel", {
    Parent = row,
    Size = UDim2.new(1, 0, 0, 16),
    BackgroundTransparency = 1,
    Text = opts.Text or name or "Input",
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
  })

  local box = Create.create("TextBox", {
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

  local obj = BaseControl.new("Input", row, self.Window, name)
  obj.Value = tostring(opts.Default or "")
  obj.TextBox = box
  obj.Changed = Signal.new()

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
          opts.Callback(value, previous)
        end, traceback)

        if not ok then
          Log.warn("Input callback failed:\n" .. tostring(err))
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

  self.Window.Maid:Give(obj)

  if name then
    self.Window.Registry:Register(name, obj, "Option")
  end

  return obj
end

function Groupbox:AddKeyPicker(name, opts)
  opts = opts or {}

  local row = createControlFrame(self, 22, false, true)

  Create.create("TextLabel", {
    Parent = row,
    Size = UDim2.new(1, -90, 1, 0),
    BackgroundTransparency = 1,
    Text = opts.Text or name or "Keybind",
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
  })

  local button = Create.create("TextButton", {
    Parent = row,
    Size = UDim2.fromOffset(90, 18),
    BackgroundColor3 = Theme.PanelAlt,
    BorderColor3 = Theme.Border,
    Text = tostring(opts.Default or "None"),
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
  })

  local obj = BaseControl.new("KeyPicker", row, self.Window, name)
  obj.Value = tostring(opts.Default or "None")
  obj.Button = button
  obj.Changed = Signal.new()

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
          opts.Callback(value, previous)
        end, traceback)

        if not ok then
          Log.warn("KeyPicker callback failed:\n" .. tostring(err))
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
    if obj.ReadOnly or obj.Disabled then return end
    button.Text = "Press key..."
    InputManager:Capture(function(input)
      if input.KeyCode == Enum.KeyCode.Escape then
        set("None", false, true)
      else
        set(input.KeyCode.Name, false, true)
      end
      InputManager:Cancel()
    end)
  end))

  self.Window:Track(UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not InputManager.Capturing or not InputManager.Callback then return end
    
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
      InputManager:Cancel()
      button.Text = obj.Value
      return
    end
    
    if gameProcessed then return end
    if UserInputService:GetFocusedTextBox() then return end
    
    if input.UserInputType == Enum.UserInputType.Keyboard then
      InputManager.Callback(input)
    end
  end))

  function obj:SetValue(value, silent)
    set(value, silent == true, false)
  end

  function obj:GetValue()
    return obj.Value
  end

  self.Window.Maid:Give(obj)
  set(obj.Value, true)

  if name then
    self.Window.Registry:Register(name, obj, "Option")
  end

  return obj
end

function Groupbox:AddDivider()
  local row = createControlFrame(self, 8, false, false)
  local div = Create.create("Frame", {
    Parent = row,
    Size = UDim2.new(1, 0, 0, 1),
    Position = UDim2.new(0, 0, 0.5, 0),
    BackgroundColor3 = Theme.Border,
    BorderSizePixel = 0,
  })
  local obj = BaseControl.new("Divider", row, self.Window, nil)
  return obj
end

function Groupbox:AddColorPicker(name, opts)
  opts = opts or {}
  local default = opts.Default or Color3.fromRGB(255, 255, 255)
  local h, s, v = default:ToHSV()
  local row = createControlFrame(self, 22, false, true)
  Create.create("TextLabel", {
    Parent = row, Size = UDim2.new(1, -50, 1, 0), BackgroundTransparency = 1,
    Text = opts.Text or name or "Color", TextXAlignment = Enum.TextXAlignment.Left,
    Font = Theme.Font, TextSize = Theme.TextSize, TextColor3 = Theme.Text,
  })
  local preview = Create.create("TextButton", {
    Parent = row, Size = UDim2.fromOffset(40, 18), BackgroundColor3 = default,
    BorderColor3 = Theme.Border, Text = "", AutoButtonColor = false,
  })
  local picker = Create.create("Frame", {
    Parent = self.Window.Gui, Visible = false, Size = UDim2.fromOffset(200, 180),
    BackgroundColor3 = Theme.Panel, BorderColor3 = Theme.Border, ZIndex = 2500,
  })
  local satVal = Create.create("ImageButton", {
    Parent = picker, Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(150, 120),
    BackgroundColor3 = Color3.fromHSV(h, 1, 1), BorderSizePixel = 0, AutoButtonColor = false, ZIndex = 2501,
  })
  local blackOverlay = Create.create("Frame", {
    Parent = satVal, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
    BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 2502,
  })
  Create.create("UIGradient", {
    Parent = blackOverlay,
    Transparency = NumberSequence.new({
      NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0),
    }),
    Rotation = 90,
  })
  local whiteOverlay = Create.create("Frame", {
    Parent = satVal, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1),
    BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 2501,
  })
  Create.create("UIGradient", {
    Parent = whiteOverlay,
    Transparency = NumberSequence.new({
      NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1),
    }),
    Rotation = 0,
  })
  local hueBar = Create.create("TextButton", {
    Parent = picker, Position = UDim2.fromOffset(166, 8), Size = UDim2.fromOffset(26, 120),
    BackgroundColor3 = Color3.new(1, 0, 0), BorderSizePixel = 0, Text = "", AutoButtonColor = false, ZIndex = 2501,
  })
  Create.create("UIGradient", {
    Parent = hueBar, Rotation = 90,
    Color = ColorSequence.new({
      ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
      ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
      ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
      ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 255, 255)),
      ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
      ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
      ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
    }),
  })
  local obj = BaseControl.new("ColorPicker", row, self.Window, name)
  obj.Value = default
  obj.Hue, obj.Sat, obj.Val = h, s, v
  obj.Changed = Signal.new()
  local function applyColor(silent)
    local c = Color3.fromHSV(obj.Hue, obj.Sat, obj.Val)
    local prev = obj.Value
    obj.Value = c
    preview.BackgroundColor3 = c
    satVal.BackgroundColor3 = Color3.fromHSV(obj.Hue, 1, 1)
    if not silent then
      obj.Changed:Fire(c, prev)
      if opts.Callback then pcall(opts.Callback, c, prev) end
    end
  end
  local function openPicker()
    if obj.Disabled or obj.ReadOnly then return end
    local pos = preview.AbsolutePosition
    picker.Position = UDim2.fromOffset(pos.X, pos.Y + 22)
    picker.Visible = true
  end
  local function closePicker() picker.Visible = false end
  self.Window:Track(preview.MouseButton1Click:Connect(function()
    if picker.Visible then closePicker() else openPicker() end
  end))
  self.Window:Track(satVal.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    local function update(pos)
      local rel = satVal.AbsolutePosition
      local size = satVal.AbsoluteSize
      obj.Sat = math.clamp((pos.X - rel.X) / math.max(size.X, 1), 0, 1)
      obj.Val = 1 - math.clamp((pos.Y - rel.Y) / math.max(size.Y, 1), 0, 1)
      applyColor(false)
    end
    update(input.Position)
    local conn, endConn
    conn = UserInputService.InputChanged:Connect(function(inp)
      if inp.UserInputType == Enum.UserInputType.MouseMovement then update(inp.Position) end
    end)
    endConn = UserInputService.InputEnded:Connect(function(inp)
      if inp.UserInputType == Enum.UserInputType.MouseButton1 then
        conn:Disconnect()
        endConn:Disconnect()
      end
    end)
  end))
  self.Window:Track(hueBar.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    local function update(pos)
      local rel = hueBar.AbsolutePosition
      local size = hueBar.AbsoluteSize
      obj.Hue = math.clamp((pos.Y - rel.Y) / math.max(size.Y, 1), 0, 1)
      applyColor(false)
    end
    update(input.Position)
    local conn, endConn
    conn = UserInputService.InputChanged:Connect(function(inp)
      if inp.UserInputType == Enum.UserInputType.MouseMovement then update(inp.Position) end
    end)
    endConn = UserInputService.InputEnded:Connect(function(inp)
      if inp.UserInputType == Enum.UserInputType.MouseButton1 then
        conn:Disconnect()
        endConn:Disconnect()
      end
    end)
  end))
  self.Window:Track(UserInputService.InputBegan:Connect(function(input)
    if not picker.Visible then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
      if not mouseOverGui(picker) and not mouseOverGui(preview) then closePicker() end
    end
  end))
  function obj:SetValue(c, silent)
    if typeof(c) ~= "Color3" then return end
    obj.Hue, obj.Sat, obj.Val = c:ToHSV()
    applyColor(silent)
  end
  function obj:GetValue() return obj.Value end
  function obj:Destroy()
    if picker and picker.Parent then pcall(function() picker:Destroy() end) end
    BaseControl.Destroy(self)
  end
  if opts.Tooltip then
    self.Window:Track(preview.MouseEnter:Connect(function() ShowTooltip(opts.Tooltip, getMousePos()) end))
    self.Window:Track(preview.MouseLeave:Connect(HideTooltip))
  end
  self.Window.Maid:Give(obj)
  if name then self.Window.Registry:Register(name, obj, "Option") end
  applyColor(true)
  return obj
end

function Groupbox:AddNumericInput(name, opts)
  opts = opts or {}
  local minV = tonumber(opts.Min)
  local maxV = tonumber(opts.Max)
  local default = tonumber(opts.Default) or 0
  local row = createControlFrame(self, nil, true, false)
  Create.create("TextLabel", {
    Parent = row, Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1,
    Text = opts.Text or name or "Number", TextXAlignment = Enum.TextXAlignment.Left,
    Font = Theme.Font, TextSize = Theme.TextSize, TextColor3 = Theme.Text,
  })
  local box = Create.create("TextBox", {
    Parent = row, Size = UDim2.new(1, 0, 0, 20), BackgroundColor3 = Theme.PanelAlt,
    BorderColor3 = Theme.Border, Text = tostring(default), ClearTextOnFocus = false,
    Font = Theme.Font, TextSize = Theme.TextSize, TextColor3 = Theme.Text,
    TextXAlignment = Enum.TextXAlignment.Left,
  })
  local obj = BaseControl.new("NumericInput", row, self.Window, name)
  obj.Value = default
  obj.Changed = Signal.new()
  local function set(v, silent)
    v = tonumber(v)
    if not v then box.Text = tostring(obj.Value) return end
    if minV then v = math.max(minV, v) end
    if maxV then v = math.min(maxV, v) end
    local prev = obj.Value
    if prev == v then box.Text = tostring(v) return end
    obj.Value = v
    box.Text = tostring(v)
    if not silent then
      obj.Changed:Fire(v, prev)
      if opts.Callback then pcall(opts.Callback, v, prev) end
    end
  end
  self.Window:Track(box.FocusLost:Connect(function() set(box.Text, false) end))
  function obj:SetValue(v, silent) set(v, silent) end
  function obj:GetValue() return obj.Value end
  function obj:SetDisabled(v)
    BaseControl.SetDisabled(self, v)
    box.TextEditable = not v
  end
  function obj:SetReadOnly(v)
    BaseControl.SetReadOnly(self, v)
    box.TextEditable = not v
  end
  if opts.Tooltip then
    self.Window:Track(box.MouseEnter:Connect(function() ShowTooltip(opts.Tooltip, getMousePos()) end))
    self.Window:Track(box.MouseLeave:Connect(HideTooltip))
  end
  self.Window.Maid:Give(obj)
  if name then self.Window.Registry:Register(name, obj, "Option") end
  return obj
end

function Groupbox:AddListBox(name, opts)
  opts = opts or {}
  local values = opts.Values or {}
  local multi = opts.Multi == true
  local height = opts.Height or 100
  local row = createControlFrame(self, nil, true, false)
  Create.create("TextLabel", {
    Parent = row, Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1,
    Text = opts.Text or name or "List", TextXAlignment = Enum.TextXAlignment.Left,
    Font = Theme.Font, TextSize = Theme.TextSize, TextColor3 = Theme.Text,
  })
  local scroll = Create.create("ScrollingFrame", {
    Parent = row, Size = UDim2.new(1, 0, 0, height), BackgroundColor3 = Theme.PanelAlt,
    BorderColor3 = Theme.Border, ScrollBarThickness = 6, ScrollBarImageColor3 = Theme.Scroll,
    CanvasSize = UDim2.new(),
  })
  local layout = Create.create("UIListLayout", { Parent = scroll, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 1) })
  local obj = BaseControl.new("ListBox", row, self.Window, name)
  obj.Value = multi and (type(opts.Default) == "table" and opts.Default or {}) or opts.Default
  obj.Values = values
  obj.Multi = multi
  obj.Changed = Signal.new()
  local function rebuild()
    for _, c in ipairs(scroll:GetChildren()) do
      if c:IsA("TextButton") then c:Destroy() end
    end
    for i, val in ipairs(values) do
      local selected = multi and table.find(obj.Value, val) or (obj.Value == val)
      local item = Create.create("TextButton", {
        Parent = scroll, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = i,
        BackgroundTransparency = selected and 0 or 1, BackgroundColor3 = Theme.Selection,
        Text = (selected and Glyphs.Check .. " " or "  ") .. tostring(val),
        TextXAlignment = Enum.TextXAlignment.Left, Font = Theme.Font, TextSize = Theme.TextSize,
        TextColor3 = Theme.Text, AutoButtonColor = false,
      })
      self.Window:Track(item.MouseButton1Click:Connect(function()
        if obj.Disabled or obj.ReadOnly then return end
        if multi then
          local prev = table.clone(obj.Value)
          local idx = table.find(obj.Value, val)
          if idx then table.remove(obj.Value, idx) else table.insert(obj.Value, val) end
          obj.Changed:Fire(obj.Value, prev)
          if opts.Callback then pcall(opts.Callback, obj.Value, prev) end
        else
          local prev = obj.Value
          obj.Value = val
          obj.Changed:Fire(val, prev)
          if opts.Callback then pcall(opts.Callback, val, prev) end
        end
        rebuild()
      end))
    end
    scroll.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 4)
  end
  rebuild()
  function obj:SetValues(newVals)
    values = newVals or {}
    obj.Values = values
    rebuild()
  end
  function obj:SetValue(v, silent)
    obj.Value = v
    rebuild()
    if not silent then obj.Changed:Fire(v) end
  end
  function obj:GetValue() return obj.Value end
  function obj:Destroy() BaseControl.Destroy(self) end
  self.Window.Maid:Give(obj)
  if name then self.Window.Registry:Register(name, obj, "Option") end
  return obj
end

function Groupbox:AddTree(name, opts)
  opts = opts or {}
  local nodes = opts.Nodes or {}
  local height = opts.Height or 140
  local row = createControlFrame(self, nil, true, false)
  Create.create("TextLabel", {
    Parent = row, Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1,
    Text = opts.Text or name or "Tree", TextXAlignment = Enum.TextXAlignment.Left,
    Font = Theme.Font, TextSize = Theme.TextSize, TextColor3 = Theme.Text,
  })
  local scroll = Create.create("ScrollingFrame", {
    Parent = row, Size = UDim2.new(1, 0, 0, height), BackgroundColor3 = Theme.PanelAlt,
    BorderColor3 = Theme.Border, ScrollBarThickness = 6, ScrollBarImageColor3 = Theme.Scroll,
    CanvasSize = UDim2.new(),
  })
  local layout = Create.create("UIListLayout", { Parent = scroll, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 1) })
  local obj = BaseControl.new("Tree", row, self.Window, name)
  obj.Nodes = nodes
  obj.Value = nil
  obj.Changed = Signal.new()
  local expanded = {}
  local function rebuild(list, depth, order)
    depth = depth or 0
    order = order or { n = 0 }
    for _, node in ipairs(list or {}) do
      order.n += 1
      local hasChildren = type(node.Children) == "table" and #node.Children > 0
      local isExp = expanded[node] == true
      local prefix = string.rep("  ", depth) .. (hasChildren and (isExp and Glyphs.ArrowDown or Glyphs.ArrowRight) or " ")
      local item = Create.create("TextButton", {
        Parent = scroll, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = order.n,
        BackgroundTransparency = (obj.Value == node) and 0 or 1, BackgroundColor3 = Theme.Selection,
        Text = prefix .. " " .. tostring(node.Text or node.Name or "?"),
        TextXAlignment = Enum.TextXAlignment.Left, Font = Theme.Font, TextSize = Theme.TextSize,
        TextColor3 = Theme.Text, AutoButtonColor = false,
      })
      self.Window:Track(item.MouseButton1Click:Connect(function()
        if hasChildren then
          expanded[node] = not isExp
          for _, c in ipairs(scroll:GetChildren()) do
            if c:IsA("TextButton") then c:Destroy() end
          end
          rebuild(nodes, 0, { n = 0 })
          scroll.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 4)
        else
          local prev = obj.Value
          obj.Value = node
          obj.Changed:Fire(node, prev)
          if opts.Callback then pcall(opts.Callback, node, prev) end
          for _, c in ipairs(scroll:GetChildren()) do
            if c:IsA("TextButton") then c:Destroy() end
          end
          rebuild(nodes, 0, { n = 0 })
          scroll.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 4)
        end
      end))
      if hasChildren and isExp then
        rebuild(node.Children, depth + 1, order)
      end
    end
  end
  rebuild(nodes)
  scroll.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 4)
  function obj:SetNodes(newNodes)
    nodes = newNodes or {}
    obj.Nodes = nodes
    for _, c in ipairs(scroll:GetChildren()) do
      if c:IsA("TextButton") then c:Destroy() end
    end
    rebuild(nodes)
    scroll.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 4)
  end
  function obj:AddNode(text, parentNode)
    local node = { Text = text, Children = {} }
    if parentNode and parentNode.Children then
      table.insert(parentNode.Children, node)
    else
      table.insert(nodes, node)
    end
    obj:SetNodes(nodes)
    return node
  end
  function obj:GetValue() return obj.Value end
  function obj:Destroy() BaseControl.Destroy(self) end
  self.Window.Maid:Give(obj)
  if name then self.Window.Registry:Register(name, obj, "Option") end
  return obj
end

function Groupbox:AddTable(name, opts)
  opts = opts or {}
  local columns = opts.Columns or { "Col1", "Col2" }
  local rows = opts.Rows or {}
  local height = opts.Height or 120
  local rowFrame = createControlFrame(self, nil, true, false)
  Create.create("TextLabel", {
    Parent = rowFrame, Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1,
    Text = opts.Text or name or "Table", TextXAlignment = Enum.TextXAlignment.Left,
    Font = Theme.Font, TextSize = Theme.TextSize, TextColor3 = Theme.Text,
  })
  local header = Create.create("Frame", {
    Parent = rowFrame, Size = UDim2.new(1, 0, 0, 18), BackgroundColor3 = Theme.PanelAlt, BorderSizePixel = 0,
  })
  local colW = 1 / math.max(#columns, 1)
  for i, col in ipairs(columns) do
    Create.create("TextLabel", {
      Parent = header, Size = UDim2.new(colW, 0, 1, 0), Position = UDim2.new(colW * (i - 1), 0, 0, 0),
      BackgroundTransparency = 1, Text = " " .. tostring(col), TextXAlignment = Enum.TextXAlignment.Left,
      Font = Theme.Font, TextSize = 12, TextColor3 = Theme.Warning,
    })
  end
  local scroll = Create.create("ScrollingFrame", {
    Parent = rowFrame, Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, height),
    BackgroundColor3 = Theme.Background, BorderColor3 = Theme.Border, ScrollBarThickness = 6,
    ScrollBarImageColor3 = Theme.Scroll, CanvasSize = UDim2.new(),
  })
  local layout = Create.create("UIListLayout", { Parent = scroll, SortOrder = Enum.SortOrder.LayoutOrder })
  local obj = BaseControl.new("Table", rowFrame, self.Window, name)
  obj.Columns = columns
  obj.Rows = rows
  obj.Changed = Signal.new()
  local function rebuild()
    for _, c in ipairs(scroll:GetChildren()) do
      if c:IsA("Frame") then c:Destroy() end
    end
    for ri, rowData in ipairs(rows) do
      local r = Create.create("Frame", {
        Parent = scroll, Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, LayoutOrder = ri,
      })
      for ci, col in ipairs(columns) do
        local cell = rowData[col] or rowData[ci] or ""
        Create.create("TextLabel", {
          Parent = r, Size = UDim2.new(colW, 0, 1, 0), Position = UDim2.new(colW * (ci - 1), 0, 0, 0),
          BackgroundTransparency = 1, Text = " " .. tostring(cell), TextXAlignment = Enum.TextXAlignment.Left,
          Font = Theme.Font, TextSize = 12, TextColor3 = Theme.Text,
        })
      end
    end
    scroll.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 4)
  end
  rebuild()
  function obj:SetRows(newRows)
    rows = newRows or {}
    obj.Rows = rows
    rebuild()
  end
  function obj:GetRows() return obj.Rows end
  function obj:Destroy() BaseControl.Destroy(self) end
  self.Window.Maid:Give(obj)
  if name then self.Window.Registry:Register(name, obj, "Option") end
  return obj
end

function Tab:AddLabel(...) return self:GetDefaultGroupbox():AddLabel(...) end
function Tab:AddButton(...) return self:GetDefaultGroupbox():AddButton(...) end
function Tab:AddToggle(...) return self:GetDefaultGroupbox():AddToggle(...) end
function Tab:AddSlider(...) return self:GetDefaultGroupbox():AddSlider(...) end
function Tab:AddDropdown(...) return self:GetDefaultGroupbox():AddDropdown(...) end
function Tab:AddInput(...) return self:GetDefaultGroupbox():AddInput(...) end
function Tab:AddKeyPicker(...) return self:GetDefaultGroupbox():AddKeyPicker(...) end
function Tab:AddDivider(...) return self:GetDefaultGroupbox():AddDivider(...) end
function Tab:AddColorPicker(...) return self:GetDefaultGroupbox():AddColorPicker(...) end
function Tab:AddNumericInput(...) return self:GetDefaultGroupbox():AddNumericInput(...) end
function Tab:AddListBox(...) return self:GetDefaultGroupbox():AddListBox(...) end
function Tab:AddTree(...) return self:GetDefaultGroupbox():AddTree(...) end
function Tab:AddTable(...) return self:GetDefaultGroupbox():AddTable(...) end

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
    return command.Callback(unpack(args, 1, args.n))
  end, traceback)

  if not ok then
    Log.warn("Command failed:\n" .. tostring(result))
    return false, result
  end

  return true, result
end

-- ==================== WINDOW CREATION ====================

function X64UI:CreateWindow(options)
  options = options or {}

  if options.SingleInstance ~= false and self.ActiveWindow and not self.ActiveWindow.Destroyed then
    self.ActiveWindow:Destroy()
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
  win.Registry = Registry.new()

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

  win.Gui = Create.create("ScreenGui", {
    Name = options.Name or "X64UI",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = options.DisplayOrder or 10000,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    Parent = getParent(),
  })

  win.Main = Create.create("Frame", {
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
  })

  win.TitleBar = Create.create("Frame", {
    Parent = win.Main,
    Size = UDim2.new(1, 0, 0, 24),
    BackgroundColor3 = Theme.TitleBar,
    BorderSizePixel = 0,
  })

  Create.create("TextLabel", {
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

  win.MinButton = Create.create("TextButton", {
    Parent = win.TitleBar,
    Position = UDim2.new(1, -60, 0, 2),
    Size = UDim2.fromOffset(28, 20),
    BackgroundColor3 = Theme.TitleBar,
    BorderSizePixel = 0,
    Text = Glyphs.Minimize,
    Font = Theme.Font,
    TextSize = 13,
    TextColor3 = Theme.Text,
  })

  win.CloseButton = Create.create("TextButton", {
    Parent = win.TitleBar,
    Position = UDim2.new(1, -30, 0, 2),
    Size = UDim2.fromOffset(28, 20),
    BackgroundColor3 = Theme.TitleBar,
    BorderSizePixel = 0,
    Text = Glyphs.Close,
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

  win.TabBar = Create.create("ScrollingFrame", {
    Parent = win.Main,
    Position = UDim2.fromOffset(0, 24),
    Size = UDim2.new(1, 0, 0, 26),
    BackgroundColor3 = Theme.Menu,
    BorderSizePixel = 0,
    ScrollBarThickness = 0,
    ScrollingDirection = Enum.ScrollingDirection.X,
    CanvasSize = UDim2.new(),
  })

  local tabLayout = Create.create("UIListLayout", {
    Parent = win.TabBar,
    FillDirection = Enum.FillDirection.Horizontal,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 1),
  })

  win:Track(tabLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    win.TabBar.CanvasSize = UDim2.fromOffset(tabLayout.AbsoluteContentSize.X + 8, 0)
  end))

  win.Pages = Create.create("Frame", {
    Parent = win.Main,
    Position = UDim2.fromOffset(4, win.TopOffset),
    Size = UDim2.new(1, -8, 1, -(win.TopOffset + 160 + 22 + 8)),
    BackgroundColor3 = Theme.Background,
    BorderColor3 = Theme.Border,
    BorderSizePixel = 1,
  })

  win.Console = Create.create("Frame", {
    Parent = win.Main,
    Visible = win.ConsoleVisible,
    BackgroundColor3 = Theme.Panel,
    BorderColor3 = Theme.Border,
  })

  local consoleHeader = Create.create("Frame", {
    Parent = win.Console,
    Size = UDim2.new(1, 0, 0, 20),
    BackgroundColor3 = Theme.PanelAlt,
    BorderSizePixel = 0,
  })

  Create.create("TextLabel", {
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

  local clearButton = Create.create("TextButton", {
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

  win.LogScroll = Create.create("ScrollingFrame", {
    Parent = win.Console,
    Position = UDim2.fromOffset(0, 20),
    Size = UDim2.new(1, 0, 1, -20),
    BackgroundColor3 = Theme.Background,
    BorderSizePixel = 0,
    ScrollBarThickness = 8,
    ScrollBarImageColor3 = Theme.Scroll,
    CanvasSize = UDim2.new(),
  })

  win.LogLabel = Create.create("TextLabel", {
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

  Create.create("UIPadding", {
    Parent = win.LogScroll,
    PaddingTop = UDim.new(0, 4),
    PaddingLeft = UDim.new(0, 4),
    PaddingRight = UDim.new(0, 4),
    PaddingBottom = UDim.new(0, 4),
  })

  win.StatusBar = Create.create("Frame", {
    Parent = win.Main,
    Position = UDim2.new(0, 0, 1, -22),
    Size = UDim2.new(1, 0, 0, 22),
    BackgroundColor3 = Theme.TitleBar,
    BorderSizePixel = 0,
  })

  win.StatusLabel = Create.create("TextLabel", {
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

  win.StatusRight = Create.create("TextLabel", {
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

  win.Grip = Create.create("TextButton", {
    Parent = win.Main,
    Position = UDim2.new(1, -14, 1, -14),
    Size = UDim2.fromOffset(14, 14),
    BackgroundTransparency = 1,
    Text = Glyphs.Grip,
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
      HorizontalAlignment = Enum.HorizontalAlignment.Right,
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

-- Global export for other scripts to pick up.
if getgenv then
  getgenv().X64UI = X64UI
elseif shared then
  shared.X64UI = X64UI
end

return X64UI
