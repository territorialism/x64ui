--[[
  X64UI Loader
  Updated to support modern HTTP wrappers and properly return the library.
]]

local LIBRARY_URL = "https://raw.githubusercontent.com/territorialism/x64ui/main/main.luau"

local success, source = pcall(function()
  local http = (syn and syn.request) or http_request or request or (fluxus and fluxus.request)
  if http then
    return http({Url = LIBRARY_URL, Method = "GET"}).Body
  else
    return game:HttpGet(LIBRARY_URL)
  end
end)

if not success then
  warn("[X64UI] Failed to fetch library: " .. tostring(source))
  return
end

local fn = loadstring(source)
if not fn then
  warn("[X64UI] Failed to compile library.")
  return
end

return fn()
