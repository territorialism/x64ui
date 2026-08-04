--[[
  X64UI Loader
]]

local LIBRARY_URL = "https://raw.githubusercontent.com/territorialism/x64ui/main/main.luau"

local success, source = pcall(function()
  return game:HttpGet(LIBRARY_URL)
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

fn()
