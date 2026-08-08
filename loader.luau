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

local url = "https://raw.githubusercontent.com/territorialism/x64ui/main/main.luau"
local source = fetch(url)
if not source then
  warn("x64ui: failed to fetch main.luau")
  return
end

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
