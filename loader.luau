local function fetch(url)
  local clients = {
    type(syn) == "table" and syn.request,
    type(http) == "table" and http.request,
    type(http_request) == "function" and http_request,
    type(request) == "function" and request,
  }

  for _, client in ipairs(clients) do
    if type(client) == "function" then
      local ok, res = pcall(client, { Url = url, Method = "GET" })
      if ok and type(res) == "table" and type(res.Body) == "string" and #res.Body > 0 then
        return res.Body
      end
    end
  end

  local ok, res = pcall(function()
    return game:HttpGet(url)
  end)
  if ok and type(res) == "string" and #res > 0 then
    return res
  end
end

local function patchSource(source)
  local function replace(old, new)
    if not string.find(source, old, 1, true) then
      return false
    end
    source = source:gsub(string.gsub(old, "([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"), function()
      return new
    end, 1)
    return true
  end

  replace([[  local existing = (getgenv and getgenv().X64UI) or (shared and shared.X64UI)
  if type(existing) == "table" and type(existing.Unload) == "function" then
    pcall(function() existing:Unload() end)
  end]], [[  local existing
  pcall(function()
    if type(getgenv) == "function" then
      local env = getgenv()
      if type(env) == "table" then existing = env.X64UI end
    end
  end)
  if not existing and type(shared) == "table" then
    existing = shared.X64UI
  end
  if type(existing) == "table" and type(existing.Unload) == "function" then
    pcall(function() existing:Unload() end)
  end]])

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
  self._Queue[#self._Queue + 1] = args
  if self._Firing then return end

  self._Firing = true
  while #self._Queue > 0 and not self.Destroyed do
    local current = table.remove(self._Queue, 1)
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
  self._Firing = false]])

  replace([[  local ok, err = xpcall(fn, traceback)
  self:EndTransaction()
  if not ok then
    Log.warn("Transaction failed:\\n" .. tostring(err))
  end
  return ok]], [[  local ok, err = xpcall(fn, traceback)
  if not ok then
    self.Transaction = nil
    self._TxDepth = 0
    Log.warn("Transaction failed:\\n" .. tostring(err))
    return false
  end
  self:EndTransaction()
  return true]])

  replace([[  for _, listener in ipairs(self[phase]) do
    local ok, err = xpcall(listener, traceback, input, gameProcessed)
    if not ok then Log.warn("InputRouter listener failed:\\n" .. tostring(err)) end
  end]], [[  local listeners = table.clone(self[phase])
  for _, listener in ipairs(listeners) do
    if table.find(self[phase], listener) then
      local ok, err = xpcall(listener, traceback, input, gameProcessed)
      if not ok then Log.warn("InputRouter listener failed:\\n" .. tostring(err)) end
    end
  end]])

  return source
end

local url = "https://raw.githubusercontent.com/territorialism/x64ui/main/main.luau"
local source = fetch(url)
if not source then
  warn("x64ui: failed to fetch main.luau")
  return
end

source = patchSource(source)

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
