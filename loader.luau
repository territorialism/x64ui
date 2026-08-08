local function fetch(url)
  local clients = {
    type(syn) == "table" and syn.request,
    type(http) == "table" and http.request,
    type(http_request) == "function" and http_request,
    type(request) == "function" and request,
  }

  for _, client in ipairs(clients) do
    if type(client) == "function" then
      local ok, res = pcall(client, {
        Url = url,
        Method = "GET",
        Headers = {
          ["Cache-Control"] = "no-cache",
        },
      })
      if ok and type(res) == "table" then
        local status = tonumber(res.StatusCode)
        local body = res.Body
        if (not status or status >= 200 and status < 300) and type(body) == "string" and #body > 0 then
          return body
        end
      end
    end
  end

  if type(game) == "userdata" or type(game) == "table" then
    local ok, res = pcall(function()
      return game:HttpGet(url)
    end)
    if ok and type(res) == "string" and #res > 0 then
      return res
    end
  end
end

local function patchSource(source)
  local patched = 0
  local required = 0

  local function replace(old, new, requiredPatch)
    if requiredPatch then
      required += 1
    end

    if string.find(source, new, 1, true) then
      return true
    end

    local start = string.find(source, old, 1, true)
    if not start then
      return false
    end

    local pattern = string.gsub(old, "([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    local changed = false
    source = string.gsub(source, pattern, function()
      changed = true
      patched += 1
      return new
    end, 1)
    return changed
  end

  replace([[  local existing = (getgenv and getgenv().X64UI) or (shared and shared.X64UI)
  if type(existing) == "table" and type(existing.Unload) == "function" then
    pcall(function() existing:Unload() end)
  end]], [[  local existing
  pcall(function()
    if type(getgenv) == "function" then
      local env = getgenv()
      if type(env) == "table" then
        existing = env.X64UI
      end
    end
  end)
  if not existing and type(shared) == "table" then
    existing = shared.X64UI
  end
  if type(existing) == "table" and type(existing.Unload) == "function" then
    pcall(function() existing:Unload() end)
  end]], true)

  replace([[  if self._Firing then
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
        Log.warn("Signal callback failed:\\n" .. tostring(err))
      end
    end
  end
  self._Firing = false]], [[  local args = table.pack(...)
  self._Queue = self._Queue or {}
  self._QueueTail = (self._QueueTail or 0) + 1
  self._Queue[self._QueueTail] = args
  if self._Firing then return end

  self._Firing = true
  local head = 1
  while head <= self._QueueTail and not self.Destroyed do
    local current = self._Queue[head]
    self._Queue[head] = nil
    head += 1
    for i = #self.Bindings, 1, -1 do
      local binding = self.Bindings[i]
      if binding and binding.Connected then
        local ok, err = xpcall(binding.Callback, traceback, unpack(current, 1, current.n))
        if not ok then
          Log.warn("Signal callback failed:\\n" .. tostring(err))
        end
      end
    end
  end
  table.clear(self._Queue)
  self._QueueTail = 0
  self._Firing = false]], true)

  replace([[  local ok, err = xpcall(fn, traceback)
  self:EndTransaction()
  if not ok then
    Log.warn("Transaction failed:\\n" .. tostring(err))
  end
  return ok]], [[  local ok, err = xpcall(fn, traceback)
  if not ok then
    local transaction = self.Transaction
    self.Transaction = nil
    self._TxDepth = 0
    if transaction and #transaction.Undos > 0 then
      self.Applying = true
      for i = #transaction.Undos, 1, -1 do
        pcall(transaction.Undos[i])
      end
      self.Applying = false
    end
    Log.warn("Transaction failed:\\n" .. tostring(err))
    return false
  end
  self:EndTransaction()
  return true]], true)

  replace([[  for _, listener in ipairs(self[phase]) do
    local ok, err = xpcall(listener, traceback, input, gameProcessed)
    if not ok then Log.warn("InputRouter listener failed:\\n" .. tostring(err)) end
  end]], [[  local listeners = table.clone(self[phase])
  for _, listener in ipairs(listeners) do
    if table.find(self[phase], listener) then
      local ok, err = xpcall(listener, traceback, input, gameProcessed)
      if not ok then Log.warn("InputRouter listener failed:\\n" .. tostring(err)) end
    end
  end]], true)

  replace([[  self._began, self._changed, self._ended = nil, nil, nil
  self.Connected = false]], [[  self._began, self._changed, self._ended = nil, nil, nil
  table.clear(self.Began)
  table.clear(self.Changed)
  table.clear(self.Ended)
  table.clear(self.CaptureStack)
  self.Connected = false]], true)

  replace([[  ThemeBindings[#ThemeBindings + 1] = { instance, property, key }]], [[  local binding = setmetatable({ instance, property, key }, { __mode = "v" })
  ThemeBindings[#ThemeBindings + 1] = binding]], true)

  local valid = string.find(source, "local X64UI =", 1, true)
    and string.find(source, "local Signal =", 1, true)
    and string.find(source, "local InputRouter", 1, true)
    and string.find(source, "local History =", 1, true)

  if not valid then
    return nil, "downloaded source is not a recognized x64ui build"
  end

  if patched < required then
    return nil, string.format("expected %d runtime patches, applied %d", required, patched)
  end

  return source
end

local url = "https://raw.githubusercontent.com/territorialism/x64ui/main/main.luau"
local source = fetch(url)
if not source then
  warn("x64ui: failed to fetch main.luau")
  return
end

local patched, patchErr = patchSource(source)
if not patched then
  warn("x64ui: patch validation failed: " .. tostring(patchErr))
  return
end
source = patched

local compiler = loadstring or load
if type(compiler) ~= "function" then
  warn("x64ui: no supported compiler is available")
  return
end

local ok, fn, err = pcall(compiler, source, "x64ui")
if not ok or type(fn) ~= "function" then
  warn("x64ui: compile error: " .. tostring(ok and err or fn))
  return
end

local ran, lib = pcall(fn)
if not ran then
  warn("x64ui: runtime error: " .. tostring(lib))
  return
end

local function publish(env)
  if type(env) ~= "table" then return end
  pcall(function()
    env.X64UI = lib
  end)
end

local okEnv, env = pcall(function()
  return type(getgenv) == "function" and getgenv() or nil
end)
if okEnv then
  publish(env)
end

if type(shared) == "table" then
  publish(shared)
end

return lib