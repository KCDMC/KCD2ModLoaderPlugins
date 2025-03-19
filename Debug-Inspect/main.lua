---@meta _
---@diagnostic disable

local envy = rom.mods['LuaENVY-ENVY']
envy.auto()

local inspect = import "inspect.lua"
public.inspect = inspect

local modutil = rom.mods['Testing-ModUtil']

modutil.on_event.once.game(function()
	rom.game.inspect = inspect
end)