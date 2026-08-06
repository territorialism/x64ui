--[[
  X64UI main entry
  Loads the full library from this same repository only.
  No paste hosts. No missing part files.
]]

-- Full library blob committed in this repo (historical single-file main).
-- Replace this entry with the latest single-file main.luau when you push it.
local URL = "https://raw.githubusercontent.com/territorialism/x64ui/de759a5dba77c81fdb11e6cb5749e5acdb4a3ab0/main.luau"

local function httpGet(url)
  if type(request) == "function" then
    local ok, res = pcall(request, { Url = url, Method = "GET" })
    if ok and type(res) == "table" then
      local body = res.Body or res.body
      if type(body) == "string" and #body > 0 then return body end
    elseif ok and type(res) == "string" and #res > 0 then
      return res
    end
  end
  local ok, body = pcall(game.HttpGet, game, url)
  if ok and type(body) == "string" and #body > 0 then return body end
  return nil
end

local source = httpGet(URL)
if not source then
  warn("[X64UI] failed to fetch library from repository")
  return {
    CreateWindow = function()
      warn("[X64UI] library source missing")
      return nil
    end,
    Notify = function() end,
    Version = "fetch-failed",
    _IntegrityError = "library source fetch failed",
  }
end

local fn, err = loadstring(source)
if not fn then
  warn("[X64UI] compile failed: " .. tostring(err))
  return {
    CreateWindow = function()
      warn("[X64UI] compile failed: " .. tostring(err))
      return nil
    end,
    Notify = function() end,
    Version = "compile-failed",
    _IntegrityError = "compile failed: " .. tostring(err),
  }
end

local ok, lib = pcall(fn)
if not ok then
  warn("[X64UI] runtime error: " .. tostring(lib))
  return {
    CreateWindow = function()
      warn("[X64UI] runtime error: " .. tostring(lib))
      return nil
    end,
    Notify = function() end,
    Version = "runtime-failed",
    _IntegrityError = "runtime error: " .. tostring(lib),
  }
end

if type(lib) ~= "table" then
  warn("[X64UI] library did not return a table")
  return nil
end

return lib
