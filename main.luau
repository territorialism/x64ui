--[[
made by iris
d = desktop
5.1.0d
]]

local X64UI = {
  Version = "5.5.1-desktop",
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
    Toolbar = Color3.fromRGB(33, 33, 33),
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

-- Reinjection guard: unload previous instance
do
  local existing = (getgenv and getgenv().X64UI) or (shared and shared.X64UI)
  if type(existing) == "table" and type(existing.Unload) == "function" then
    pcall(function() existing:Unload() end)
  end
end

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

local Layer = {
  Base = 1,
  Panel = 10,
  Popup = 2000,
  ColorPicker = 2500,
  Menu = 3000,
  Modal = 5000,
  Toast = 10000,
  Tooltip = 32767,
}

-- Live theming (Phase 5)
local ThemeBindings = {}

local function themed(instance, property, key)
  if not instance or not key or Theme[key] == nil then return instance end
  ThemeBindings[#ThemeBindings + 1] = { instance, property, key }
  instance[property] = Theme[key]
  return instance
end

function X64UI:SetThemeKey(key, value)
  if Theme[key] == nil and value == nil then return end
  Theme[key] = value
  X64UI.Theme[key] = value
  for i = #ThemeBindings, 1, -1 do
    local b = ThemeBindings[i]
    if not b[1] or not b[1].Parent then
      table.remove(ThemeBindings, i)
    elseif b[3] == key then
      pcall(function() b[1][b[2]] = value end)
    end
  end
end

function X64UI:ApplyTheme(patch)
  if type(patch) ~= "table" then return end
  for k, v in pairs(patch) do
    self:SetThemeKey(k, v)
  end
end




-- Forward declarations (B01): InitTooltip / Dialog call these before the
-- local function bodies appear later in the file.
local getParent, getViewportSize, getMousePos, mouseOverGui, pointInGui, toGuiSpace


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
local Platform = {
  CanWrite = type(writefile) == "function",
  CanRead = type(readfile) == "function" and type(isfile) == "function",
  CanDelete = type(delfile) == "function",
}

function Platform.readFile(path)
  if not Platform.CanRead or not isfile(path) then return nil end
  local ok, data = pcall(readfile, path)
  return ok and data or nil
end

function Platform.writeFile(path, content)
  if not Platform.CanWrite then return false end
  local ok = pcall(writefile, path, content)
  return ok == true
end

function Platform.fileExists(path)
  if not Platform.CanRead then return false end
  local ok, exists = pcall(isfile, path)
  return ok and exists == true
end

function Platform.deleteFile(path)
  if not Platform.CanDelete then return end
  pcall(delfile, path)
end

-- ui/glyphs.lua (Replaces corrupted Unicode strings)
local Glyphs = {
  Check = "\226\156\147",       -- ✓
  Cross = "\226\156\149",       -- ✕
  ArrowDown = "\226\150\188",   -- ▼
  ArrowRight = "\226\150\182",  -- ▶
  Grip = "\226\151\162",        -- ◢
  Minimize = "\226\128\148",    -- —
  Close = "X",
  Search = "\240\159\148\141"   -- 
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
  -- snapshot first: Destroy mutates Controls via Unregister
  local snapshot = {}
  for _, c in pairs(self.Controls) do
    snapshot[#snapshot + 1] = c
  end
  for _, c in ipairs(snapshot) do
    if c and c.Destroy then pcall(c.Destroy, c) end
  end
  table.clear(self.Controls)
  table.clear(self.Toggles)
  table.clear(self.Options)
end

-- core/create.lua (Strict replacement for create())
local Create = {}
local function setProperty(inst, key, value)
  inst[key] = value
end

function Create.create(className, props, children)
  assert(type(className) == "string", "Create.create: className must be a string")
  assert(props == nil or type(props) == "table", "Create.create: props must be a table or nil")
  assert(children == nil or type(children) == "table", "Create.create: children must be a table or nil")

  local inst = Instance.new(className)
  for k, v in pairs(props or {}) do
    if k ~= "Parent" then
      local ok, err = pcall(setProperty, inst, k, v)
      if not ok and X64UI and X64UI._DebugCreate then
        Log.warn("Create.create failed to set " .. tostring(k) .. ": " .. tostring(err))
      end
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

  if self._Firing then
    -- re-entrant: queue unbounded recursion
    return
  end

  self._Firing = true
  local n = select("#", ...)
  -- iterate backwards so Disconnect during fire is safe without clone
  for i = #self.Bindings, 1, -1 do
    local binding = self.Bindings[i]
    if binding and binding.Connected then
      local ok, err = xpcall(binding.Callback, traceback, ...)
      if not ok then
        Log.warn("Signal callback failed:\n" .. tostring(err))
      end
    end
  end
  self._Firing = false
end

function Signal:ConnectDeferred(callback)
  return self:Connect(function(...)
    local args = table.pack(...)
    task.defer(function()
      callback(unpack(args, 1, args.n))
    end)
  end)
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
  elseif taskType == "thread" then
    pcall(task.cancel, taskObject)
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
  self._TxDepth = (self._TxDepth or 0) + 1
  if self._TxDepth == 1 then
    self.Transaction = { Label = label or "Transaction", Undos = {}, Redos = {} }
  end
end

function History:EndTransaction()
  self._TxDepth = math.max(0, (self._TxDepth or 0) - 1)
  if self._TxDepth > 0 then return end
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

function History:WithTransaction(label, fn)
  self:BeginTransaction(label)
  local ok, err = xpcall(fn, traceback)
  self:EndTransaction()
  if not ok then
    Log.warn("Transaction failed:\n" .. tostring(err))
  end
  return ok
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

-- InputRouter: one library-wide input owner (Phase 1)
local InputRouter = {
  Began = {},
  Changed = {},
  Ended = {},
  CaptureStack = {},
  Connected = false,
}

function InputRouter:On(phase, listener)
  table.insert(self[phase], listener)
  return function()
    local index = table.find(self[phase], listener)
    if index then table.remove(self[phase], index) end
  end
end

function InputRouter:PushCapture(handlers)
  table.insert(self.CaptureStack, handlers)
  return function()
    local index = table.find(self.CaptureStack, handlers)
    if index then table.remove(self.CaptureStack, index) end
  end
end

function InputRouter:Dispatch(phase, input, gameProcessed)
  local top = self.CaptureStack[#self.CaptureStack]
  if top then
    local handler = top[phase]
    if handler then
      local ok, err = xpcall(handler, traceback, input, gameProcessed)
      if not ok then Log.warn("InputRouter capture failed:\n" .. tostring(err)) end
    end
    return
  end
  for _, listener in ipairs(self[phase]) do
    local ok, err = xpcall(listener, traceback, input, gameProcessed)
    if not ok then Log.warn("InputRouter listener failed:\n" .. tostring(err)) end
  end
end

function InputRouter:Connect()
  if self.Connected then return end
  self.Connected = true
  self._began = UserInputService.InputBegan:Connect(function(input, gp)
    self:Dispatch("Began", input, gp)
  end)
  self._changed = UserInputService.InputChanged:Connect(function(input, gp)
    self:Dispatch("Changed", input, gp)
  end)
  self._ended = UserInputService.InputEnded:Connect(function(input, gp)
    self:Dispatch("Ended", input, gp)
  end)
end

function InputRouter:Disconnect()
  if self._began then self._began:Disconnect() end
  if self._changed then self._changed:Disconnect() end
  if self._ended then self._ended:Disconnect() end
  self._began, self._changed, self._ended = nil, nil, nil
  self.Connected = false
  table.clear(self.Began)
  table.clear(self.Changed)
  table.clear(self.Ended)
  table.clear(self.CaptureStack)
end

-- Back-compat shim used by existing KeyPicker code
local InputManager = {
  Capturing = false,
  Callback = nil,
  _release = nil,
}
function InputManager:Capture(cb)
  self.Capturing = true
  self.Callback = cb
  if self._release then self._release() end
  self._release = InputRouter:PushCapture({
    Began = function(input, gameProcessed)
      if self.Callback then
        self.Callback(input, gameProcessed)
      end
    end,
  })
end
function InputManager:Cancel()
  self.Capturing = false
  self.Callback = nil
  if self._release then
    self._release()
    self._release = nil
  end
end

-- Bind names: KeyCode.Name (RightShift, LeftControl, ...) or MouseButton1/2/3
local function InputToBindName(input)
  if not input then return nil end
  local uit = input.UserInputType
  if uit == Enum.UserInputType.Keyboard then
    local kc = input.KeyCode
    if not kc or kc == Enum.KeyCode.Unknown then
      return nil
    end
    return kc.Name
  end
  if uit == Enum.UserInputType.MouseButton1 then return "MouseButton1" end
  if uit == Enum.UserInputType.MouseButton2 then return "MouseButton2" end
  if uit == Enum.UserInputType.MouseButton3 then return "MouseButton3" end
  return nil
end

local function InputMatchesBind(input, bindName)
  if not bindName or bindName == "" or bindName == "None" then
    return false
  end
  local name = InputToBindName(input)
  if not name then
    return false
  end
  if name == bindName then
    return true
  end
  -- aliases: Shift / Control / Alt match either side
  if bindName == "Shift" and (name == "LeftShift" or name == "RightShift") then
    return true
  end
  if bindName == "Control" and (name == "LeftControl" or name == "RightControl") then
    return true
  end
  if bindName == "Alt" and (name == "LeftAlt" or name == "RightAlt") then
    return true
  end
  if bindName == "MB1" and name == "MouseButton1" then return true end
  if bindName == "MB2" and name == "MouseButton2" then return true end
  if bindName == "MB3" and name == "MouseButton3" then return true end
  return false
end

InputRouter:Connect()

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

function getParent()
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

function getViewportSize(gui)
  -- Prefer measured ScreenGui size (correct with IgnoreGuiInset).
  -- Never add GuiInset on top of Camera.ViewportSize (double-counts topbar).
  if gui and gui.Parent and gui.AbsoluteSize.X > 0 then
    return gui.AbsoluteSize
  end
  local cam = Workspace.CurrentCamera
  if cam and cam.ViewportSize then
    return cam.ViewportSize
  end
  return Vector2.new(1280, 720)
end

local function getSafeViewportRect()
  local viewport = getViewportSize()
  local margin = 8
  -- keep a hard edge inset so corners never sit past the screen
  local left = margin
  local top = margin
  local right = viewport.X - margin
  local bottom = viewport.Y - margin
  return left, top, right, bottom, viewport
end

function getMousePos()
  -- Always use GetMouseLocation (top-left of screen). InputObject.Position from
  -- InputBegan is NOT updated for MouseButton1/2 (Roblox API).
  return UserInputService:GetMouseLocation()
end

function toGuiSpace(point, gui)
  -- ScreenGui with IgnoreGuiInset draws over the topbar; mouse coords do not.
  if gui and gui:IsA("ScreenGui") and gui.IgnoreGuiInset then
    return point + GuiService:GetGuiInset()
  end
  return point
end

function pointInGui(gui, point)
  if not gui or not gui.Parent then return false end

  local pos = gui.AbsolutePosition
  local size = gui.AbsoluteSize

  return point.X >= pos.X
    and point.X <= pos.X + size.X
    and point.Y >= pos.Y
    and point.Y <= pos.Y + size.Y
end

function mouseOverGui(gui)
  local ok, mouse = pcall(getMousePos)
  if not ok or not mouse then return false end

  -- Try both raw mouse and inset-reconciled point so hit tests work for
  -- IgnoreGuiInset and non-IgnoreGuiInset roots.
  if pointInGui(gui, mouse) then return true end
  local inset = GuiService:GetGuiInset()
  return pointInGui(gui, mouse - inset) or pointInGui(gui, mouse + inset)
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

  local t = control.Type
  if t == "Toggle" then
    return typeof(value) == "boolean"
  end
  if t == "Slider" or t == "NumericInput" then
    return typeof(value) == "number"
  end
  if t == "Dropdown" then
    if typeof(value) == "table" then return true end -- multi
    return typeof(value) == "string" or typeof(value) == "number"
  end
  if t == "ColorPicker" then
    return typeof(value) == "Color3" or (type(value) == "table" and value.r ~= nil)
  end
  if t == "KeyPicker" then
    return typeof(value) == "string"
  end
  if t == "ListBox" or t == "Tree" or t == "Table" then
    return typeof(value) == "table" or typeof(value) == "string" or typeof(value) == "number" or value == nil
  end
  if t == "Input" or t == "TextBox" then
    return typeof(value) == "string" or typeof(value) == "number"
  end
  return true -- unknown types: don't block save
end

local function getWindowResizeLimits()
  local left, top, right, bottom, viewport = getSafeViewportRect()
  local margin = 8

  local maxW = math.max(1, right - left)
  local maxH = math.max(1, bottom - top)

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
function BaseControl:SetVisible(v)
  self.Visible = v and true or false
  if self.Frame then self.Frame.Visible = self.Visible end
end

function BaseControl:SetDisabled(v)
  self.Disabled = v and true or false
  if self.Frame then
    self.Frame.Active = not self.Disabled
  end
  if self.Label then
    self.Label.TextColor3 = self.Disabled and Theme.Dim or Theme.Text
  end
end

function BaseControl:SetReadOnly(v)
  self.ReadOnly = v and true or false
end

function BaseControl:CanInteract()
  return (not self.Disabled) and (not self.ReadOnly) and self.Visible and (not self.Destroyed)
end

function BaseControl:Destroy()
  if self.Destroyed then return end
  self.Destroyed = true
  if self.Frame then pcall(function() self.Frame:Destroy() end) end
  if self.Window and self.Window.Registry and self.Name then self.Window.Registry:Unregister(self.Name) end
end

-- Chaining helpers (Linoria-style): label:AddKeyPicker, toggle:AddColorPicker
function BaseControl:AddKeyPicker(name, opts)
  if not self.Window or not self.Frame then return nil end
  -- find parent groupbox via Frame parent chain is hard; use Window active tab default
  local group = self._Groupbox
  if not group then return nil end
  opts = opts or {}
  opts.Text = opts.Text or ""
  return group:AddKeyPicker(name, opts)
end

function BaseControl:AddColorPicker(name, opts)
  local group = self._Groupbox
  if not group then return nil end
  return group:AddColorPicker(name, opts)
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

function Window:Log(message, severity)
  if not self.LogLabel or not self.LogLabel.Parent then return end

  if not self.Lines then self.Lines = {} end

  local text = tostring(message)
  local sev = severity
  if not sev then
    local lower = string.lower(text)
    if lower:find("error", 1, true) or lower:find("fail", 1, true) then
      sev = "error"
    elseif lower:find("warn", 1, true) then
      sev = "warn"
    elseif lower:find("success", 1, true) or lower:find("loaded", 1, true) then
      sev = "good"
    else
      sev = "info"
    end
  end

  local color = "#DCDCE3"
  if sev == "error" or sev == "bad" then
    color = "#F44747"
  elseif sev == "warn" or sev == "warning" then
    color = "#DCDCAA"
  elseif sev == "good" or sev == "success" then
    color = "#4EC9B0"
  elseif sev == "accent" then
    color = "#589ED8"
  end

  -- escape richtext special chars in message body
  local safe = text:gsub("[<>&]", { ["<"] = "&lt;", [">"] = "&gt;", ["&"] = "&amp;" })
  local line = string.format(
    '<font color="#888888">[%s]</font> <font color="%s">%s</font>',
    os.date("%X"),
    color,
    safe
  )
  self.Lines[#self.Lines + 1] = line

  while #self.Lines > 200 do
    table.remove(self.Lines, 1)
  end

  self._LogDirty = true
  if self._LogFlushScheduled then return end
  self._LogFlushScheduled = true

  task.defer(function()
    self._LogFlushScheduled = false
    if self.Destroyed or not self._LogDirty then return end
    self._LogDirty = false

    if not self.LogLabel or not self.LogLabel.Parent then return end

    local joined = table.concat(self.Lines, "\n")
    if #joined > 12000 then
      joined = joined:sub(#joined - 12000)
    end
    self.LogLabel.Text = joined

    if self.LogScroll and self.LogLabel.Parent then
      local y = self.LogLabel.TextBounds.Y + 10
      self.LogScroll.CanvasSize = UDim2.fromOffset(0, y)
      self.LogScroll.CanvasPosition = Vector2.new(0, math.max(0, y - self.LogScroll.AbsoluteSize.Y))
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
  -- never rewrite position mid-drag (that is what caused the snap)
  if self._Dragging then return end

  local left, top, right, bottom, viewport = getSafeViewportRect()
  local _, margin, minSize, maxSize = getWindowResizeLimits()

  local currentSize = Vector2.new(self.Main.AbsoluteSize.X, self.Main.AbsoluteSize.Y)
  local size = Vector2.new(
    math.clamp(currentSize.X, minSize.X, maxSize.X),
    math.clamp(currentSize.Y, minSize.Y, maxSize.Y)
  )

  if size.X ~= currentSize.X or size.Y ~= currentSize.Y then
    self.Main.Size = UDim2.fromOffset(size.X, size.Y)
    self:UpdateLayout()
  end

  -- stay in Position.Offset space (ScreenGui IgnoreGuiInset). AbsolutePosition
  -- can differ by inset and causes a visible jump when written back.
  local posX = self.Main.Position.X.Offset
  local posY = self.Main.Position.Y.Offset

  local maxX = math.max(left, right - size.X)
  local maxY = math.max(top, bottom - size.Y)

  posX = math.clamp(posX, left, maxX)
  posY = math.clamp(posY, top, maxY)

  if posX + size.X > right then
    posX = math.max(left, right - size.X)
  end
  if posY + size.Y > bottom then
    posY = math.max(top, bottom - size.Y)
  end

  self.Main.Position = UDim2.fromOffset(posX, posY)
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
  if value then self:CloseAllPopups() end
  if self.Destroyed then return end

  value = value and true or false
  if value == self.Minimized then return end

  self.Minimized = value
  self.State.Minimized:Set(value)

  if value then
    self.LastSize = self.Main.Size
    self.Main.Size = UDim2.fromOffset(self.Main.AbsoluteSize.X, 24)

    if self.MenuBar then self.MenuBar.Visible = false end
    if self.Toolbar then self.Toolbar.Visible = false end
    if self.MenuDropdown then self.MenuDropdown.Visible = false end
    self.TabBar.Visible = false
    self.Pages.Visible = false
    self.Console.Visible = false
    self.StatusBar.Visible = false
    self.Grip.Visible = false
  else
    self.Main.Size = self.LastSize or UDim2.fromOffset(1000, 640)

    if self.MenuBar then self.MenuBar.Visible = true end
    if self.Toolbar then self.Toolbar.Visible = true end
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
  self:CloseAllPopups()
  if self.Destroyed then return end

  if self.Main.Visible then
    self:CloseDropdowns()

    if self.CloseMenu then
      self.CloseMenu()
    end

    if self.CommandPalette then
      self.CommandPalette.Visible = false
    end

    if self.MenuDropdown then
      self.MenuDropdown.Visible = false
    end

    self.Main.Visible = false
    self.State.Visible:Set(false)

    if self.Events and self.Events.VisibilityChanged then
      self.Events.VisibilityChanged:Fire(false)
    end
  end
end

function Window:Toggle()
  self:CloseAllPopups()
  if self.Main.Visible then
    self:Hide()
  else
    self:Show()
  end
end


function Window:RegisterPopup(popup)
  if not self.Popups then self.Popups = {} end
  table.insert(self.Popups, popup)
  return popup
end

function Window:CloseAllPopups()
  if not self.Popups then return end
  for _, popup in ipairs(self.Popups) do
    pcall(function()
      if type(popup.Close) == "function" then
        popup:Close()
      elseif type(popup) == "function" then
        popup()
      end
    end)
  end
  table.clear(self.Popups)
end

function Window:Destroy()
  self:CloseAllPopups()
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
  local startPos = Vector2.zero

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
    -- use offset-space only (IgnoreGuiInset ScreenGui). mixing AbsolutePosition
    -- with Position.Offset causes a one-frame snap on every move.
    startMouse = getMousePos()
    startPos = Vector2.new(frame.Position.X.Offset, frame.Position.Y.Offset)
    self._Dragging = true
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
      local nextPos = startPos + delta

      -- soft edge limits while dragging (no AbsolutePosition rewrite)
      local left, top, right, bottom = getSafeViewportRect()
      local size = Vector2.new(frame.AbsoluteSize.X, frame.AbsoluteSize.Y)
      nextPos = Vector2.new(
        math.clamp(nextPos.X, left, math.max(left, right - size.X)),
        math.clamp(nextPos.Y, top, math.max(top, bottom - size.Y))
      )

      frame.Position = UDim2.fromOffset(nextPos.X, nextPos.Y)
    end
  end))

  self:Track(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 and dragging then
      dragging = false
      self._Dragging = false
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


function Window:SaveProfile(name)
  name = tostring(name or "default"):gsub("[^%w%-%_]", "")
  if name == "" then name = "default" end
  return self:SaveConfig("x64ui_profile_" .. name .. ".json")
end

function Window:LoadProfile(name, loadOpts)
  name = tostring(name or "default"):gsub("[^%w%-%_]", "")
  if name == "" then name = "default" end
  return self:LoadConfig("x64ui_profile_" .. name .. ".json", loadOpts)
end

function Window:SaveConfig(path)
  path = path or "x64ui_config.json"

  if not Platform.CanWrite then
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
    if toggle.NoSave then continue end
    if typeof(toggle.Value) == "boolean" then
      data.Toggles[name] = toggle.Value
    end
  end

  for name, option in pairs(self.Registry.Options) do
    if option.NoSave then continue end
    local encoded = X64UI.SerializeValue(option)
    if encoded ~= nil then
      data.Options[name] = encoded
    end
  end

  data.Layout = {
    Size = { self.Main.Size.X.Offset, self.Main.Size.Y.Offset },
    Pos = { self.Main.Position.X.Offset, self.Main.Position.Y.Offset },
    Minimized = self.Minimized == true,
    Maximized = self.Maximized == true,
    Scale = self.Scale or 1,
  }
  data.Version = 3
  data.MenuKeybind = (typeof(X64UI.MenuKeybind) == "EnumItem") and X64UI.MenuKeybind.Name or tostring(X64UI.MenuKeybind)

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
        value = X64UI.DeserializeValue(option, value)

        if option.Type == "Slider" and typeof(value) == "number" then
          value = math.clamp(value, option.Min or value, option.Max or value)
        end

        if isControlValueValid(option, value) then
          option:SetValue(value, not fireCallbacks)
        else
          Log.warn("Config rejected key '" .. tostring(name) .. "' (invalid value for " .. tostring(option.Type) .. ")")
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

function Groupbox:AddDependencyBox()
  local holder = Create.create("Frame", {
    Parent = self.Content,
    Size = UDim2.new(1, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1,
    LayoutOrder = self.NextOrder,
    Visible = true,
  })
  self.NextOrder += 1

  Create.create("UIListLayout", {
    Parent = holder,
    Padding = UDim.new(0, 4),
    SortOrder = Enum.SortOrder.LayoutOrder,
  })

  local proxy = {
    Content = holder,
    NextOrder = 1,
    Window = self.Window,
    Title = self.Title,
  }
  setmetatable(proxy, { __index = Groupbox })

  local box = {
    Type = "DependencyBox",
    Group = self,
    Window = self.Window,
    Visible = true,
    Holder = holder,
  }

  function box:SetupDependencies(deps)
    local function evaluate()
      local show = true
      if type(deps) == "table" then
        for control, required in pairs(deps) do
          if type(control) == "table" and control.GetValue then
            if control:GetValue() ~= required then
              show = false
              break
            end
          end
        end
      end
      holder.Visible = show
      box.Visible = show
    end
    if type(deps) == "table" then
      for control, _ in pairs(deps) do
        if type(control) == "table" and control.Changed and control.Changed.Connect then
          self.Window:Track(control.Changed:Connect(evaluate))
        end
      end
    end
    evaluate()
  end

  for _, method in ipairs({
    "AddToggle", "AddSlider", "AddDropdown", "AddLabel", "AddButton",
    "AddInput", "AddKeyPicker", "AddColorPicker", "AddNumericInput",
    "AddListBox", "AddTree", "AddTable", "AddDivider",
  }) do
    box[method] = function(_, ...)
      return proxy[method](proxy, ...)
    end
  end

  return box
end


function Tab:GetDefaultGroupbox()
  if not self.DefaultGroupbox then
    self.DefaultGroupbox = self:AddLeftGroupbox("General")
  end

  return self.DefaultGroupbox
end


function Groupbox:Clear()
  for _, child in ipairs(self.Content:GetChildren()) do
    if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
      child:Destroy()
    end
  end
  self.NextOrder = 1
end

function Tab:Destroy()
  if self.Destroyed then return end
  self.Destroyed = true
  if self.Frame then pcall(function() self.Frame:Destroy() end) end
  if self.Button then pcall(function() self.Button:Destroy() end) end
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
  obj._Groupbox = self
  function obj:SetText(newText) label.Text = tostring(newText) end
  function obj:AddKeyPicker(n, o)
    return self._Groupbox:AddKeyPicker(n, o)
  end
  function obj:AddColorPicker(n, o)
    return self._Groupbox:AddColorPicker(n, o)
  end
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

  obj._Groupbox = self
  function obj:AddColorPicker(n, o)
    return self._Groupbox:AddColorPicker(n, o)
  end
  function obj:AddKeyPicker(n, o)
    return self._Groupbox:AddKeyPicker(n, o)
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

  -- Label left, value right (no UIListLayout — scale-1 + list overlaps value into text)
  Create.create("TextLabel", {
    Parent = header,
    Size = UDim2.new(1, -56, 1, 0),
    Position = UDim2.fromOffset(0, 0),
    BackgroundTransparency = 1,
    Text = opts.Text or name or "Slider",
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Center,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
    TextTruncate = Enum.TextTruncate.AtEnd,
  })

  local valueLabel = Create.create("TextBox", {
    Parent = header,
    Size = UDim2.fromOffset(52, 16),
    Position = UDim2.new(1, -52, 0, 0),
    BackgroundTransparency = 1,
    Text = "",
    TextXAlignment = Enum.TextXAlignment.Right,
    TextYAlignment = Enum.TextYAlignment.Center,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.AccentText,
    ClearTextOnFocus = false,
    PlaceholderText = "",
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

  local suffix = opts.Suffix or ""
  local function format(v)
    local s
    if step < 1 then
      s = string.format("%." .. digits .. "f", v)
    else
      s = tostring(math.floor(v + 0.5))
    end
    return s .. suffix
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
      if not obj:CanInteract() then return end
      dragging = true
      dragStartValue = obj.Value
      updateFromX(getMousePos().X)
    end
  end))

  self.Window:Track(UserInputService.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
      updateFromX(getMousePos().X)
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

  
  self.Window:Track(valueLabel.FocusLost:Connect(function(enter)
    local typed = tonumber(valueLabel.Text:match("[%d%.%-]+"))
    if typed then
      set(typed, false, true)
    else
      valueLabel.Text = format(obj.Value)
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

  local function formatDropdownLabel(val)
    if opts.Multi then
      local n = (type(val) == "table" and #val) or 0
      return Glyphs.ArrowDown .. " " .. tostring(n) .. " selected"
    end
    return Glyphs.ArrowDown .. " " .. tostring(val)
  end

  local button = Create.create("TextButton", {
    Parent = row,
    Size = UDim2.new(1, 0, 0, 20),
    BackgroundColor3 = Theme.PanelAlt,
    BorderColor3 = Theme.Border,
    Text = formatDropdownLabel(opts.Multi and (type(selected) == "table" and selected or {}) or selected),
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
    PlaceholderText = "Search",
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
  if opts.Multi then
    if type(opts.Default) == "table" then
      obj.Value = table.clone(opts.Default)
    else
      obj.Value = {}
    end
  else
    obj.Value = selected
  end
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
    local height = getListHeight()
    local viewport = getViewportSize(self.Window and self.Window.Gui)
    local spaceBelow = viewport.Y - (pos.Y + size.Y)
    local openUp = spaceBelow < height + 8 and pos.Y > height + 8

    if openUp then
      list.Position = UDim2.fromOffset(pos.X, pos.Y - height - 2)
    else
      list.Position = UDim2.fromOffset(pos.X, pos.Y + size.Y + 2)
    end
    list.Size = UDim2.fromOffset(size.X, height)
    list.CanvasSize = UDim2.fromOffset(0, listLayout.AbsoluteContentSize.Y + 2)
  end

  function obj:Open()
    obj:RefreshPosition()
    list.Visible = true
    obj.OpenedAt = os.clock()
    self.Window:RegisterPopup({
      Close = function()
        obj:Close()
      end,
    })
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
    button.Text = formatDropdownLabel(value)

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
    if not obj:CanInteract() then return end
    obj:Toggle()
  end))

  local itemMaid = Maid.new()
  self.Window.Maid:Give(itemMaid)

  local function buildItems()
    itemMaid:Cleanup()
    for _, child in ipairs(list:GetChildren()) do
      if child:IsA("TextButton") and child ~= searchBox then child:Destroy() end
    end

    local query = string.lower(searchBox.Text or "")
    local order = 1

    -- windowed render for large lists (virtualization)
    local filtered = {}
    for i, value in ipairs(values) do
      if query == "" or string.find(string.lower(tostring(value)), query, 1, true) then
        filtered[#filtered + 1] = value
      end
    end

    local maxVisible = 60
    local startIndex = 1
    local endIndex = #filtered
    if #filtered > maxVisible then
      -- show first maxVisible matches (search already narrows; full scroll virtualization is heavier)
      endIndex = maxVisible
      if not list:FindFirstChild("X64VirtHint") then
        local hint = Create.create("TextLabel", {
          Parent = list,
          Name = "X64VirtHint",
          LayoutOrder = 99999,
          Size = UDim2.new(1, 0, 0, 16),
          BackgroundTransparency = 1,
          Text = string.format("  showing %d of %d — type to filter", maxVisible, #filtered),
          Font = Theme.Font,
          TextSize = Theme.TextSize - 1,
          TextColor3 = Theme.Dim,
          TextXAlignment = Enum.TextXAlignment.Left,
          ZIndex = 2001,
        })
        itemMaid:Give(hint)
      end
    end

    for i = startIndex, endIndex do
      local value = filtered[i]
      if value ~= nil then
        local isSelected = false
        if opts.Multi then
          isSelected = type(obj.Value) == "table" and table.find(obj.Value, value) ~= nil
        else
          isSelected = obj.Value == value
        end

        local item = Create.create("TextButton", {
          Parent = list,
          LayoutOrder = i,
          Size = UDim2.new(1, 0, 0, 18),
          BackgroundColor3 = Theme.Selection,
          BackgroundTransparency = isSelected and 0 or 1,
          Text = (isSelected and "> " or "  ") .. tostring(value),
          TextXAlignment = Enum.TextXAlignment.Left,
          Font = Theme.Font,
          TextSize = Theme.TextSize,
          TextColor3 = Theme.Text,
          ZIndex = 2001,
        })

        itemMaid:Give(item.MouseEnter:Connect(function()
          item.BackgroundColor3 = Theme.Selection
          item.BackgroundTransparency = 0
        end))

        itemMaid:Give(item.MouseLeave:Connect(function()
          local still = false
          if opts.Multi then
            still = type(obj.Value) == "table" and table.find(obj.Value, value) ~= nil
          else
            still = obj.Value == value
          end
          item.BackgroundTransparency = still and 0 or 1
          item.BackgroundColor3 = Theme.Selection
        end))

        itemMaid:Give(item.MouseButton1Click:Connect(function()
          if opts.Multi then
            local current = table.clone(obj.Value)
            local idx = table.find(current, value)
            if idx then table.remove(current, idx) else table.insert(current, value) end
            set(current, false, true)
            buildItems()
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

  function obj:SetValues(newValues)
    values = newValues or {}
    buildItems()
  end

  function obj:Refresh()
    buildItems()
  end

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
  local mode = opts.Mode or "Toggle" -- Toggle | Hold | Press | Always
  local noUI = opts.NoUI == true

  local row
  local button
  if not noUI then
    row = createControlFrame(self, 22, false, true)

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

    button = Create.create("TextButton", {
      Parent = row,
      Size = UDim2.fromOffset(90, 18),
      BackgroundColor3 = Theme.PanelAlt,
      BorderColor3 = Theme.Border,
      Text = tostring(opts.Default or "None"),
      Font = Theme.Font,
      TextSize = Theme.TextSize,
      TextColor3 = Theme.Text,
    })
  end

  local obj = BaseControl.new("KeyPicker", row, self.Window, name)
  obj.Value = tostring(opts.Default or "None")
  obj.Mode = mode
  obj.Button = button
  obj.Changed = Signal.new()
  obj.Clicked = Signal.new()
  obj._State = false
  obj._Holding = false

  local internalChange = false

  local function set(value, silent, withHistory)
    value = tostring(value)

    local previous = obj.Value
    if previous == value then return end

    obj.Value = value
    if button then button.Text = value end

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

  local function fireClick()
    obj.Clicked:Fire(obj._State)
    if opts.OnClick then
      local ok, err = xpcall(function()
        opts.OnClick(obj._State)
      end, traceback)
      if not ok then Log.warn("KeyPicker OnClick failed:\n" .. tostring(err)) end
    end
  end

  local function onKeyBegan(input, gameProcessed)
    if obj.Disabled or obj.Destroyed then return end
    if gameProcessed and mode ~= "Always" then return end
    if UserInputService:GetFocusedTextBox() then return end
    if self.Window.PickingKey then return end
    if obj.Value == "None" or obj.Value == "" then return end
    if not InputMatchesBind(input, obj.Value) then return end

    if mode == "Toggle" then
      obj._State = not obj._State
      fireClick()
    elseif mode == "Hold" then
      obj._Holding = true
      obj._State = true
      fireClick()
    elseif mode == "Press" then
      obj._State = true
      fireClick()
      obj._State = false
    elseif mode == "Always" then
      obj._State = true
    end
  end

  local function onKeyEnded(input)
    if mode ~= "Hold" then return end
    if not obj._Holding then return end
    if not InputMatchesBind(input, obj.Value) then return end
    obj._Holding = false
    obj._State = false
    fireClick()
  end

  if InputRouter then
    InputRouter:On("Began", onKeyBegan)
    InputRouter:On("Ended", onKeyEnded)
  else
    self.Window:Track(UserInputService.InputBegan:Connect(onKeyBegan))
    self.Window:Track(UserInputService.InputEnded:Connect(onKeyEnded))
  end

  if button then
    self.Window:Track(button.MouseButton1Click:Connect(function()
      if not obj:CanInteract() then return end
      button.Text = "..."
      self.Window.PickingKey = true

      -- defer so the MouseButton1 that opened the picker is not captured as the bind
      task.defer(function()
        if obj.Destroyed or not self.Window.PickingKey then return end

        InputManager:Capture(function(input)
          local name = InputToBindName(input)
          if not name then
            return -- ignore movement / unknown
          end

          if name == "Escape" then
            set("None", false, true)
          else
            set(name, false, true)
          end

          InputManager:Cancel()
          self.Window.PickingKey = false
          if button then
            button.Text = obj.Value
          end
        end)
      end)
    end))
  end

  function obj:SetValue(value, silent)
    set(value, silent == true, false)
  end

  function obj:GetValue()
    return obj.Value
  end

  function obj:GetState()
    if mode == "Always" then return true end
    return obj._State == true
  end

  function obj:SetMode(newMode)
    mode = newMode or mode
    obj.Mode = mode
    obj._State = false
    obj._Holding = false
  end

  function obj:OnClick(fn)
    return obj.Clicked:Connect(fn)
  end

  self.Window.Maid:Give(obj)
  set(obj.Value, true)

  if name then
    self.Window.Registry:Register(name, obj, "Option")
  end

  -- chaining: allow :AddColorPicker on same row later via group helpers
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
  local hue, sat, vib = default:ToHSV()

  local row = createControlFrame(self, 22, false, true)
  Create.create("TextLabel", {
    Parent = row,
    Size = UDim2.new(1, -50, 1, 0),
    BackgroundTransparency = 1,
    Text = opts.Text or name or "Color",
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
  })

  local preview = Create.create("TextButton", {
    Parent = row,
    Size = UDim2.fromOffset(40, 18),
    BackgroundColor3 = default,
    BorderColor3 = Theme.Border,
    Text = "",
    AutoButtonColor = false,
  })

  -- Obsidian-style picker panel
  local picker = Create.create("Frame", {
    Parent = self.Window.Gui,
    Visible = false,
    Size = UDim2.fromOffset(230, 230),
    BackgroundColor3 = Theme.Panel,
    BorderColor3 = Theme.Border,
    ZIndex = 2500,
  })

  local satMap = Create.create("ImageButton", {
    Parent = picker,
    Position = UDim2.fromOffset(8, 8),
    Size = UDim2.fromOffset(180, 180),
    BackgroundColor3 = Color3.fromHSV(hue, 1, 1),
    Image = "rbxassetid://4155801252", -- Obsidian SaturationMap
    BorderSizePixel = 0,
    AutoButtonColor = false,
    ZIndex = 2501,
  })

  local satCursor = Create.create("Frame", {
    Parent = satMap,
    AnchorPoint = Vector2.new(0.5, 0.5),
    Size = UDim2.fromOffset(6, 6),
    Position = UDim2.fromScale(sat, 1 - vib),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0,
    ZIndex = 2503,
  })
  Create.create("UICorner", { Parent = satCursor, CornerRadius = UDim.new(1, 0) })
  Create.create("UIStroke", { Parent = satCursor, Color = Color3.new(0, 0, 0), Thickness = 1 })

  local hueSeq = {}
  for i = 0, 10 do
    local t = i / 10
    table.insert(hueSeq, ColorSequenceKeypoint.new(t, Color3.fromHSV(t, 1, 1)))
  end

  local hueBar = Create.create("TextButton", {
    Parent = picker,
    Position = UDim2.fromOffset(196, 8),
    Size = UDim2.fromOffset(26, 180),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0,
    Text = "",
    AutoButtonColor = false,
    ZIndex = 2501,
  })
  Create.create("UIGradient", {
    Parent = hueBar,
    Rotation = 90,
    Color = ColorSequence.new(hueSeq),
  })

  local hueCursor = Create.create("Frame", {
    Parent = hueBar,
    AnchorPoint = Vector2.new(0.5, 0.5),
    Size = UDim2.new(1, 2, 0, 2),
    Position = UDim2.fromScale(0.5, hue),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0,
    ZIndex = 2503,
  })
  Create.create("UIStroke", { Parent = hueCursor, Color = Color3.new(0, 0, 0), Thickness = 1 })

  local hexBox = Create.create("TextBox", {
    Parent = picker,
    Position = UDim2.fromOffset(8, 196),
    Size = UDim2.fromOffset(214, 22),
    BackgroundColor3 = Theme.PanelAlt,
    BorderColor3 = Theme.Border,
    Text = "#" .. default:ToHex(),
    Font = Theme.Font,
    TextSize = Theme.TextSize,
    TextColor3 = Theme.Text,
    ClearTextOnFocus = false,
    ZIndex = 2501,
  })

  local obj = BaseControl.new("ColorPicker", row, self.Window, name)
  obj.Value = default
  obj.Hue, obj.Sat, obj.Vib = hue, sat, vib
  obj.Changed = Signal.new()

  local function display(silent)
    obj.Value = Color3.fromHSV(obj.Hue, obj.Sat, obj.Vib)
    preview.BackgroundColor3 = obj.Value
    satMap.BackgroundColor3 = Color3.fromHSV(obj.Hue, 1, 1)
    satCursor.Position = UDim2.fromScale(obj.Sat, 1 - obj.Vib)
    hueCursor.Position = UDim2.fromScale(0.5, obj.Hue)
    hexBox.Text = "#" .. obj.Value:ToHex()
    if not silent then
      local prev = obj.Value
      obj.Changed:Fire(obj.Value, prev)
      if opts.Callback then
        pcall(opts.Callback, obj.Value, prev)
      end
    end
  end

  local function openPicker()
    if obj.Disabled or obj.ReadOnly then return end
    local pos = preview.AbsolutePosition
    picker.Position = UDim2.fromOffset(pos.X, pos.Y + 22)
    picker.Visible = true
  end

  local function closePicker()
    picker.Visible = false
  end

  self.Window:Track(preview.MouseButton1Click:Connect(function()
    if picker.Visible then closePicker() else openPicker() end
  end))

  local function bindDrag(gui, updateFn)
    self.Window:Track(gui.InputBegan:Connect(function(input)
      if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
      updateFn(getMousePos())
      local conn, endConn
      conn = UserInputService.InputChanged:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseMovement then
          updateFn(inp.Position)
        end
      end)
      endConn = UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
          conn:Disconnect()
          endConn:Disconnect()
        end
      end)
    end))
  end

  bindDrag(satMap, function(pos)
    local rel = satMap.AbsolutePosition
    local size = satMap.AbsoluteSize
    obj.Sat = math.clamp((pos.X - rel.X) / math.max(size.X, 1), 0, 1)
    obj.Vib = 1 - math.clamp((pos.Y - rel.Y) / math.max(size.Y, 1), 0, 1)
    display(false)
  end)

  bindDrag(hueBar, function(pos)
    local rel = hueBar.AbsolutePosition
    local size = hueBar.AbsoluteSize
    obj.Hue = math.clamp((pos.Y - rel.Y) / math.max(size.Y, 1), 0, 1)
    display(false)
  end)

  self.Window:Track(hexBox.FocusLost:Connect(function()
    local text = hexBox.Text:gsub("#", "")
    local ok, color = pcall(function()
      return Color3.fromHex(text)
    end)
    if ok and typeof(color) == "Color3" then
      obj.Hue, obj.Sat, obj.Vib = color:ToHSV()
      display(false)
    else
      hexBox.Text = "#" .. obj.Value:ToHex()
    end
  end))

  self.Window:Track(UserInputService.InputBegan:Connect(function(input)
    if not picker.Visible then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
      if not mouseOverGui(picker) and not mouseOverGui(preview) then
        closePicker()
      end
    end
  end))

  function obj:SetValue(c, silent)
    if typeof(c) ~= "Color3" then return end
    obj.Hue, obj.Sat, obj.Vib = c:ToHSV()
    display(silent)
  end

  function obj:GetValue()
    return obj.Value
  end

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
  display(true)
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

  if self._IntegrityError then
    warn("[X64UI] " .. tostring(self._IntegrityError))
    pcall(function()
      self:Notify({
        Title = "X64UI integrity",
        Description = tostring(self._IntegrityError),
        Time = 8,
      })
    end)
    return nil
  end

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
  win.TopOffset = 102
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

  local defaultScale = 1
  if viewport.Y >= 1440 then
    defaultScale = 1.15
  elseif viewport.Y < 900 then
    defaultScale = 0.9
  end
  win.Scale = tonumber(options.Scale) or defaultScale
  win.UIScale = Create.create("UIScale", {
    Parent = win.Main,
    Scale = win.Scale,
  })
  function win:SetScale(scale)
    scale = math.clamp(tonumber(scale) or 1, 0.5, 2)
    self.Scale = scale
    if self.UIScale then self.UIScale.Scale = scale end
  end

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


  -- menu bar (always present)
  win.MenuBar = Create.create("Frame", {
    Parent = win.Main,
    Position = UDim2.fromOffset(0, 24),
    Size = UDim2.new(1, 0, 0, 22),
    BackgroundColor3 = Theme.Menu,
    BorderSizePixel = 0,
    ZIndex = 20,
  })
  Create.create("UIListLayout", {
    Parent = win.MenuBar,
    FillDirection = Enum.FillDirection.Horizontal,
    Padding = UDim.new(0, 2),
    VerticalAlignment = Enum.VerticalAlignment.Center,
    SortOrder = Enum.SortOrder.LayoutOrder,
  })

  -- parent to ScreenGui so it renders above page content
  win.MenuDropdown = Create.create("Frame", {
    Parent = win.Gui,
    Visible = false,
    BackgroundColor3 = Theme.Panel,
    BorderColor3 = Theme.Border,
    BorderSizePixel = 1,
    ZIndex = 3000,
    AutomaticSize = Enum.AutomaticSize.None,
  })
  Create.create("UIListLayout", {
    Parent = win.MenuDropdown,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 1),
  })
  Create.create("UIPadding", {
    Parent = win.MenuDropdown,
    PaddingTop = UDim.new(0, 2),
    PaddingBottom = UDim.new(0, 2),
  })

  local openMenuName = nil
  local menus = {
    File = {
      { Text = "Unload", Callback = function() win:Destroy() end },
      { Text = "Exit", Callback = function() win:Destroy() end },
    },
    View = {
      { Text = "Toggle Console", Callback = function()
        if win.ToggleConsole then win:ToggleConsole() end
      end },
      { Text = "Toggle Status Bar", Callback = function()
        if win.ToggleStatusBar then
          win:ToggleStatusBar()
        else
          win.StatusVisible = not win.StatusVisible
          win:UpdateLayout()
        end
      end },
      { Text = "Command Palette", Callback = function()
        if win.OpenCommandPalette then
          win:OpenCommandPalette()
        elseif win.ToggleCommandPalette then
          win:ToggleCommandPalette()
        end
      end },
    },
    Options = {
      { Text = "Save Config", Callback = function()
        if win.SaveConfig then win:SaveConfig("x64ui_config.json") end
      end },
      { Text = "Load Config", Callback = function()
        if win.LoadConfig then win:LoadConfig("x64ui_config.json") end
      end },
    },
    Help = {
      { Text = "About", Callback = function()
        X64UI:Notify({
          Title = "X64UI",
          Description = "x64dbg-inspired ui · v" .. tostring(X64UI.Version or "?"),
          Time = 4,
        })
      end },
    },
  }

  local function clearMenuItems()
    for _, child in ipairs(win.MenuDropdown:GetChildren()) do
      if child:IsA("TextButton") then
        child:Destroy()
      end
    end
  end

  local function closeMenu()
    openMenuName = nil
    win.MenuDropdown.Visible = false
    for _, child in ipairs(win.MenuBar:GetChildren()) do
      if child:IsA("TextButton") then
        child.BackgroundTransparency = 1
        child.BackgroundColor3 = Theme.Menu
      end
    end
  end

  win.CloseMenu = closeMenu

  local function openMenu(name, sourceButton)
    if openMenuName == name and win.MenuDropdown.Visible then
      closeMenu()
      return
    end

    openMenuName = name
    clearMenuItems()

    local items = menus[name] or {}
    for i, item in ipairs(items) do
      local itemBtn = Create.create("TextButton", {
        Parent = win.MenuDropdown,
        LayoutOrder = i,
        Size = UDim2.new(1, 0, 0, 22),
        BackgroundTransparency = 1,
        BackgroundColor3 = Theme.Selection,
        Text = "  " .. item.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Theme.Font,
        TextSize = Theme.TextSize,
        TextColor3 = Theme.Text,
        AutoButtonColor = false,
        ZIndex = 3001,
      })
      win:Track(itemBtn.MouseEnter:Connect(function()
        itemBtn.BackgroundTransparency = 0
      end))
      win:Track(itemBtn.MouseLeave:Connect(function()
        itemBtn.BackgroundTransparency = 1
      end))
      win:Track(itemBtn.MouseButton1Click:Connect(function()
        closeMenu()
        if item.Callback then
          pcall(item.Callback)
        end
      end))
    end

    -- position in screen space (parent is ScreenGui)
    local btnPos = sourceButton.AbsolutePosition
    local btnSize = sourceButton.AbsoluteSize
    local width = math.max(btnSize.X, 180)
    local height = (#items * 22) + 6

    win.MenuDropdown.Size = UDim2.fromOffset(width, height)
    win.MenuDropdown.Position = UDim2.fromOffset(btnPos.X, btnPos.Y + btnSize.Y)
    win.MenuDropdown.Visible = true

    for _, child in ipairs(win.MenuBar:GetChildren()) do
      if child:IsA("TextButton") then
        if child == sourceButton then
          child.BackgroundColor3 = Theme.PanelAlt
          child.BackgroundTransparency = 0
        else
          child.BackgroundTransparency = 1
        end
      end
    end
  end

  local function addMenuButton(name, order)
    local b = Create.create("TextButton", {
      Parent = win.MenuBar,
      LayoutOrder = order or 0,
      Size = UDim2.fromOffset(0, 20),
      AutomaticSize = Enum.AutomaticSize.X,
      BackgroundTransparency = 1,
      BackgroundColor3 = Theme.PanelAlt,
      Text = "  " .. name .. "  ",
      Font = Theme.Font,
      TextSize = Theme.TextSize,
      TextColor3 = Theme.Text,
      AutoButtonColor = false,
      ZIndex = 21,
    })
    win:Track(b.MouseButton1Click:Connect(function()
      openMenu(name, b)
    end))
    win:Track(b.MouseEnter:Connect(function()
      if openMenuName then
        -- windows-style: hover switches open menu
        if openMenuName ~= name then
          openMenu(name, b)
        end
      else
        b.BackgroundColor3 = Theme.PanelAlt
        b.BackgroundTransparency = 0
      end
    end))
    win:Track(b.MouseLeave:Connect(function()
      if openMenuName ~= name then
        b.BackgroundTransparency = 1
      end
    end))
    return b
  end

  addMenuButton("File", 1)
  addMenuButton("View", 2)
  addMenuButton("Options", 3)
  addMenuButton("Help", 4)

  -- close menu on outside click
  win:Track(UserInputService.InputBegan:Connect(function(input)
    if not win.MenuDropdown.Visible then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    task.defer(function()
      if not win.MenuDropdown or not win.MenuDropdown.Visible then return end
      local overMenu = mouseOverGui(win.MenuDropdown)
      local overBar = mouseOverGui(win.MenuBar)
      if not overMenu and not overBar then
        closeMenu()
      end
    end)
  end))

  -- toolbar (always present)
  win.Toolbar = Create.create("Frame", {
    Parent = win.Main,
    Position = UDim2.fromOffset(0, 46),
    Size = UDim2.new(1, 0, 0, 28),
    BackgroundColor3 = Theme.Toolbar or Theme.Menu,
    BorderSizePixel = 0,
  })
  Create.create("UIListLayout", {
    Parent = win.Toolbar,
    FillDirection = Enum.FillDirection.Horizontal,
    Padding = UDim.new(0, 2),
    VerticalAlignment = Enum.VerticalAlignment.Center,
  })
  Create.create("UIPadding", {
    Parent = win.Toolbar,
    PaddingLeft = UDim.new(0, 4),
  })

  local function addToolButton(text, callback)
    local b = Create.create("TextButton", {
      Parent = win.Toolbar,
      Size = UDim2.fromOffset(60, 22),
      BackgroundColor3 = Theme.Toolbar or Theme.Menu,
      BorderColor3 = Theme.Border,
      Text = text,
      Font = Theme.Font,
      TextSize = Theme.TextSize,
      TextColor3 = Theme.Text,
    })
    win:Track(b.MouseEnter:Connect(function()
      b.BackgroundColor3 = Theme.PanelAlt
    end))
    win:Track(b.MouseLeave:Connect(function()
      b.BackgroundColor3 = Theme.Toolbar or Theme.Menu
    end))
    win:Track(b.MouseButton1Click:Connect(function()
      if callback then pcall(callback) end
    end))
    return b
  end

  local function addToolSeparator()
    Create.create("Frame", {
      Parent = win.Toolbar,
      Size = UDim2.fromOffset(1, 18),
      BackgroundColor3 = Theme.Border,
      BorderSizePixel = 0,
    })
  end

  addToolButton("Run", function() win:Log("Toolbar: Run") end)
  addToolButton("Pause", function() win:Log("Toolbar: Pause") end)
  addToolButton("Step", function() win:Log("Toolbar: Step") end)
  addToolButton("Over", function() win:Log("Toolbar: Step Over") end)
  addToolSeparator()
  addToolButton("Clear", function() win:ClearLog() end)
  addToolButton("Undo", function()
    if win.History then win.History:UndoLast() end
  end)
  addToolButton("Redo", function()
    if win.History then win.History:RedoLast() end
  end)

  win.TabBar = Create.create("ScrollingFrame", {
    Parent = win.Main,
    Position = UDim2.fromOffset(0, 74),
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
    RichText = true,
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
    if input.UserInputType == Enum.UserInputType.Keyboard then
      if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
        win.CommandModifierDown = true
      end

      if (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl))
        and input.KeyCode == Enum.KeyCode.P then
        win:ToggleCommandPalette()
        return
      end
    end

    if win.PickingKey then return end
    if InputManager and InputManager.Capturing then return end
    if InputRouter and #InputRouter.CaptureStack > 0 then return end
    if gameProcessed then return end
    if UserInputService:GetFocusedTextBox() then return end

    local key = X64UI.MenuKeybind
    local matched = false

    if typeof(key) == "EnumItem" then
      if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == key then
        matched = true
      end
    elseif typeof(key) == "string" then
      matched = InputMatchesBind(input, key)
    end

    if matched then
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

  -- Clear sticky modifiers on focus loss (alt-tab while holding Ctrl)
  win:Track(UserInputService.WindowFocusReleased:Connect(function()
    win.CommandModifierDown = false
    win.PickingKey = false
  end))

  win:Track(win.Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
    if not win.Destroyed and not win.Maximized and not win.Minimized then
      win:ClampToViewport()
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

  -- integrity: full chrome is mandatory (not optional / handpicked)
  local function failIntegrity(issue)
    local detail = "[X64UI] window integrity failed: " .. tostring(issue)
    warn(detail)
    pcall(function()
      X64UI:Notify({
        Title = "X64UI integrity",
        Description = tostring(issue),
        Time = 8,
      })
    end)
    pcall(function()
      if win and not win.Destroyed then
        win:Destroy()
      end
    end)
    return nil
  end

  local required = {
    { key = "Gui", label = "ScreenGui root missing" },
    { key = "Main", label = "main window frame missing" },
    { key = "TitleBar", label = "title bar missing" },
    { key = "MenuBar", label = "menu bar missing (File/View/Options/Help required)" },
    { key = "Toolbar", label = "toolbar missing (Run/Pause/Step chrome required)" },
    { key = "TabBar", label = "tab bar missing" },
    { key = "Pages", label = "pages container missing" },
    { key = "Console", label = "log console missing" },
    { key = "StatusBar", label = "status bar missing" },
    { key = "Registry", label = "control registry missing" },
    { key = "History", label = "history stack missing" },
    { key = "Maid", label = "maid cleanup missing" },
  }

  for _, item in ipairs(required) do
    local value = win[item.key]
    if value == nil then
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



function X64UI.SerializeValue(control)
  if not control then return nil end
  local t = control.Type
  local v = control.Value
  if t == "ColorPicker" and typeof(v) == "Color3" then
    return { t = "Color3", r = v.R, g = v.G, b = v.B }
  end
  if t == "Dropdown" and type(v) == "table" then
    return { t = "Multi", v = v }
  end
  if t == "Toggle" or t == "Slider" or t == "NumericInput" or t == "KeyPicker" or t == "Input" then
    return v
  end
  if type(v) == "string" or type(v) == "number" or type(v) == "boolean" then
    return v
  end
  return nil -- skip non-json-safe
end

function X64UI.DeserializeValue(control, raw)
  if not control or raw == nil then return nil end
  if type(raw) == "table" and raw.t == "Color3" then
    return Color3.new(raw.r or 0, raw.g or 0, raw.b or 0)
  end
  if type(raw) == "table" and raw.t == "Multi" then
    return raw.v
  end
  return raw
end


function X64UI:SetWatermark(text)
  if not self._WatermarkGui or not self._WatermarkGui.Parent then
    self._WatermarkGui = Create.create("ScreenGui", {
      Name = "X64Watermark",
      ResetOnSpawn = false,
      IgnoreGuiInset = true,
      DisplayOrder = 100,
      Parent = getParent(),
    })
    self._WatermarkLabel = Create.create("TextLabel", {
      Parent = self._WatermarkGui,
      Position = UDim2.fromOffset(12, 12),
      Size = UDim2.fromOffset(0, 0),
      AutomaticSize = Enum.AutomaticSize.XY,
      BackgroundColor3 = Theme.Panel,
      BorderColor3 = Theme.Border,
      Text = "",
      Font = Theme.Font,
      TextSize = Theme.TextSize,
      TextColor3 = Theme.Text,
      TextXAlignment = Enum.TextXAlignment.Left,
    })
    Create.create("UIPadding", {
      Parent = self._WatermarkLabel,
      PaddingLeft = UDim.new(0, 6),
      PaddingRight = UDim.new(0, 6),
      PaddingTop = UDim.new(0, 3),
      PaddingBottom = UDim.new(0, 3),
    })
  end
  if text == nil or text == false or text == "" then
    self._WatermarkGui.Enabled = false
  else
    self._WatermarkGui.Enabled = true
    self._WatermarkLabel.Text = tostring(text)
  end
end


function X64UI:SetKeybindList(enabled)
  if enabled == false then
    if self._KeybindListGui then
      self._KeybindListGui.Enabled = false
    end
    return
  end

  if not self._KeybindListGui or not self._KeybindListGui.Parent then
    self._KeybindListGui = Create.create("ScreenGui", {
      Name = "X64KeybindList",
      ResetOnSpawn = false,
      IgnoreGuiInset = true,
      DisplayOrder = 150,
      Parent = getParent(),
    })
    self._KeybindListFrame = Create.create("Frame", {
      Parent = self._KeybindListGui,
      AnchorPoint = Vector2.new(1, 0),
      Position = UDim2.new(1, -12, 0, 12),
      Size = UDim2.fromOffset(200, 0),
      AutomaticSize = Enum.AutomaticSize.Y,
      BackgroundColor3 = Theme.Panel,
      BorderColor3 = Theme.Border,
    })
    Create.create("UIListLayout", {
      Parent = self._KeybindListFrame,
      Padding = UDim.new(0, 2),
      SortOrder = Enum.SortOrder.LayoutOrder,
    })
    Create.create("TextLabel", {
      Parent = self._KeybindListFrame,
      Size = UDim2.new(1, 0, 0, 18),
      BackgroundColor3 = Theme.TitleBar,
      BorderSizePixel = 0,
      Text = " keybinds ",
      Font = Theme.Font,
      TextSize = Theme.TextSize,
      TextColor3 = Theme.AccentText,
      TextXAlignment = Enum.TextXAlignment.Left,
    })
  end

  self._KeybindListGui.Enabled = true

  -- refresh rows from registered keypickers across windows
  for _, child in ipairs(self._KeybindListFrame:GetChildren()) do
    if child:IsA("TextLabel") and child.LayoutOrder > 0 then
      child:Destroy()
    end
  end

  local order = 1
  for _, win in ipairs(self.Windows or {}) do
    if win.Registry and win.Registry.Options then
      for name, opt in pairs(win.Registry.Options) do
        if opt.Type == "KeyPicker" and opt.Value and opt.Value ~= "None" then
          local state = ""
          if opt.GetState then
            state = opt:GetState() and " [ON]" or ""
          end
          Create.create("TextLabel", {
            Parent = self._KeybindListFrame,
            LayoutOrder = order,
            Size = UDim2.new(1, -8, 0, 16),
            BackgroundTransparency = 1,
            Text = string.format(" %s: %s%s", name, tostring(opt.Value), state),
            Font = Theme.Font,
            TextSize = Theme.TextSize - 1,
            TextColor3 = Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
          })
          order += 1
        end
      end
    end
  end
end


function X64UI:GetCapabilities()
  return {
    writefile = Platform.CanWrite == true,
    readfile = Platform.CanRead == true,
    delfile = Platform.CanDelete == true,
    gethui = type(gethui) == "function",
    request = type(request) == "function",
    getgenv = type(getgenv) == "function",
    hookfunction = type(hookfunction) == "function",
    Drawing = type(Drawing) == "table",
  }
end

function X64UI:ReportCapabilities(window)
  local c = self:GetCapabilities()
  local parts = {}
  for k, v in pairs(c) do
    parts[#parts + 1] = k .. "=" .. (v and "yes" or "no")
  end
  table.sort(parts)
  local msg = "caps: " .. table.concat(parts, " ")
  if window and window.Log then
    window:Log(msg, "accent")
  else
    Log.info(msg)
  end
  return c
end

function X64UI:Unload()
  if self.Unloaded then return end
  self.Unloaded = true

  if InputRouter and InputRouter.Disconnect then
    pcall(function() InputRouter:Disconnect() end)
  end

  for i = #self.Windows, 1, -1 do
    local win = self.Windows[i]
    if win and type(win.Destroy) == "function" then
      pcall(function() win:Destroy() end)
    end
  end
  table.clear(self.Windows)
  self.ActiveWindow = nil

  if self.NotifyGui then
    pcall(function() self.NotifyGui:Destroy() end)
    self.NotifyGui = nil
  end

  if getgenv then getgenv().X64UI = nil end
  if shared then shared.X64UI = nil end
end

-- Global export for other scripts to pick up.
if getgenv then
  getgenv().X64UI = X64UI
elseif shared then
  shared.X64UI = X64UI
end

return X64UI
