# X64UI

x64dbg-inspired UI library for Roblox exploit scripts. Built entirely with native GUI instances (no external dependencies, no Drawing API, no external assets).

Desktop only. I made this for myself and figured other people might find it useful.

## Loadstring

```lua
local X64UI = loadstring(game:HttpGet("https://raw.githubusercontent.com/territorialism/x64ui/main/loader.luau"))()
