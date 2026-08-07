-- loader.luau
local function fetch(url)
    if request then
        local ok, res = pcall(request, { Url = url, Method = "GET" })
        if ok and res and res.Body then return res.Body end
    end
    local ok, res = pcall(game.HttpGet, game, url)
    if ok and res then return res end
    return nil
end

local url = "https://raw.githubusercontent.com/territorialism/x64ui/main/main.luau"
local source = fetch(url)
if not source then
    warn("x64ui: failed to fetch main.luau")
    return
end

local fn, err = loadstring(source, "x64ui")
if not fn then
    warn("x64ui: compile error: " .. tostring(err))
    return
end

local ok, lib = pcall(fn)
if not ok then
    warn("x64ui: runtime error: " .. tostring(lib))
    return
end

if getgenv then getgenv().X64UI = lib end
if shared then shared.X64UI = lib end
return lib
