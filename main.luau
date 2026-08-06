--[[
  X64UI main bootstrap
  loads full 5.2.4 source (drag snap fix)
]]
local URL = "https://termbin.com/ktocy"

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
  warn("[X64UI] failed to fetch library source from " .. tostring(URL))
  return {
    CreateWindow = function()
      warn("[X64UI] library source missing — cannot create window")
      return nil
    end,
    Notify = function()
      warn("[X64UI] library source missing — notify unavailable")
    end,
    Version = "bootstrap-failed",
    _IntegrityError = "library source fetch failed",
  }
end

local fn, err = loadstring(source)
if not fn then
  warn("[X64UI] compile failed: " .. tostring(err))
  return {
    CreateWindow = function()
      warn("[X64UI] compile failed — cannot create window: " .. tostring(err))
      return nil
    end,
    Notify = function() end,
    Version = "bootstrap-compile-failed",
    _IntegrityError = "compile failed: " .. tostring(err),
  }
end

local ok, lib = pcall(fn)
if not ok then
  warn("[X64UI] runtime error: " .. tostring(lib))
  return {
    CreateWindow = function()
      warn("[X64UI] runtime error — cannot create window: " .. tostring(lib))
      return nil
    end,
    Notify = function() end,
    Version = "bootstrap-runtime-failed",
    _IntegrityError = "runtime error: " .. tostring(lib),
  }
end

if type(lib) ~= "table" then
  warn("[X64UI] library did not return a table")
  return nil
end

return lib
