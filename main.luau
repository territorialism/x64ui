--[[
  x64ui 0.0.2-d entry
  assembles in-repo source under src/release/ (no paste hosts)
]]
local BASE = "https://raw.githubusercontent.com/territorialism/x64ui/main/"
local PARTS = {
  "src/release/c01.luau",
  "src/release/c02.luau",
  "src/release/c03.luau",
  "src/release/c04.luau",
  "src/release/c05.luau",
  "src/release/c06.luau",
  "src/release/c07.luau",
  "src/release/c08.luau",
  "src/release/c09.luau",
  "src/release/c10.luau",
  "src/release/c11.luau",
  "src/release/c12.luau",
  "src/release/c13.luau",
  "src/release/c14.luau",
  "src/release/c15.luau",
  "src/release/c16.luau"
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
      Version = "0.0.2-d-incomplete",
      _IntegrityError = "missing source part: " .. path,
    }
  end
  source[i] = body
end

local code = table.concat(source)
local fn, err = loadstring(code)
if not fn then
  warn("[X64UI] compile failed: " .. tostring(err))
  return { Version = "0.0.2-d-compile-failed", _IntegrityError = tostring(err) }
end
local ok, lib = pcall(fn)
if not ok then
  warn("[X64UI] runtime error: " .. tostring(lib))
  return { Version = "0.0.2-d-runtime-failed", _IntegrityError = tostring(lib) }
end
return lib
