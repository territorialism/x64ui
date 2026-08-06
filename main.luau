--[[
  X64UI main entry
  assembles in-repo source parts (no external paste hosts)
]]
local BASE = "https://raw.githubusercontent.com/territorialism/x64ui/main/"
local PARTS = {
  "src/part1.luau",
  "src/part2.luau",
  "src/part3.luau",
  "src/part4.luau",
  "src/part5.luau"
}

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

local source = table.create(#PARTS)
for i, path in ipairs(PARTS) do
  local body = httpGet(BASE .. path)
  if not body then
    warn("[X64UI] failed to fetch " .. path)
    return {
      CreateWindow = function()
        warn("[X64UI] incomplete source — missing " .. path)
        return nil
      end,
      Notify = function() end,
      Version = "assemble-failed",
      _IntegrityError = "missing source part: " .. path,
    }
  end
  source[i] = body
end

local code = table.concat(source)
local fn, err = loadstring(code)
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
