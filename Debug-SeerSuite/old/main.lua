---@meta _
---@diagnostic disable

---@module 'LuaENVY-ENVY'
local envy = rom.mods["LuaENVY-ENVY"]
---@module 'LuaENVY-ENVY-auto'
envy.auto()

private.envy = envy

import('core.lua')
import('browser.lua',nil,envy.globals)
import('console.lua',nil,rom.game or envy.globals)