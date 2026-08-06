--[[
  X64UI main bootstrap
  temporarily loads the full 5.2.0 build (menu bar + toolbar always on)
  until the library file is restored on this branch
]]
local URL = "https://termbin.com/2dhc1"

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
  warn("[X64UI] failed to fetch library source")
  return nil
end

local fn, err = loadstring(source)
if not fn then
  warn("[X64UI] compile failed: " .. tostring(err))
  return nil
end

local ok, lib = pcall(fn)
if not ok then
  warn("[X64UI] runtime error: " .. tostring(lib))
  return nil
end

return lib
