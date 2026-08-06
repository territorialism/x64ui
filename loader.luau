--[[
  X64UI Loader
  - Executor HTTP wrapper chain (syn.request, http.request, http_request, request, fluxus)
  - Safe body extraction + loadstring error capture
  - Exports to getgenv().X64UI / shared.X64UI after load
]]

local LIBRARY_URL = "https://raw.githubusercontent.com/territorialism/x64ui/main/main.luau"

local function httpGet(url)
  local requestFn =
    (syn and syn.request)
    or (http and http.request)
    or http_request
    or request
    or (fluxus and fluxus.request)

  if requestFn then
    local ok, res = pcall(requestFn, {
      Url = url,
      Method = "GET",
    })
    if not ok then
      return nil, tostring(res)
    end
    if type(res) == "table" then
      local body = res.Body or res.body
      if type(body) == "string" and #body > 0 then
        return body
      end
      return nil, "empty response body"
    end
    if type(res) == "string" and #res > 0 then
      return res
    end
    return nil, "unexpected response type"
  end

  local ok, body = pcall(game.HttpGet, game, url)
  if not ok then
    return nil, tostring(body)
  end
  if type(body) ~= "string" or #body == 0 then
    return nil, "empty HttpGet body"
  end
  return body
end

local source, err = httpGet(LIBRARY_URL)
if not source then
  warn("[X64UI] Failed to fetch library: " .. tostring(err))
  return nil
end

local compileOk, fnOrErr = pcall(loadstring, source)
if not compileOk then
  warn("[X64UI] Failed to compile library: " .. tostring(fnOrErr))
  return nil
end
if type(fnOrErr) ~= "function" then
  warn("[X64UI] loadstring returned non-function")
  return nil
end

local runOk, libOrErr = pcall(fnOrErr)
if not runOk then
  warn("[X64UI] Library runtime error: " .. tostring(libOrErr))
  return nil
end

local X64UI = libOrErr
if type(X64UI) ~= "table" then
  warn("[X64UI] Library did not return a table")
  return nil
end

if getgenv then
  getgenv().X64UI = X64UI
elseif shared then
  shared.X64UI = X64UI
end

return X64UI
