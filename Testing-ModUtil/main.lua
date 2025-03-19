---@meta _
---@diagnostic disable

---@module 'LuaENVY-ENVY'
local envy = rom.mods['LuaENVY-ENVY']
---@module 'LuaENVY-ENVY-auto'
envy.auto();

public.private = private

local listeners_each = {}
local listeners_once = {}

private.exhausted_events = {}
private.trigger_event = {}
public.on_event = {}
on_event.each = {}
on_event.once = {}
on_event.next = {}

local function call_event(callback,...)
	local s,m = pcall(callback,...)
	if not s then return rom.log.error(m) end
end

function private.define_event(name)
	exhausted_events[name] = false
	listeners_each[name] = {}
	listeners_once[name] = {}
	trigger_event[name] = function()
		local skip_once = exhausted_events[name]
		exhausted_events[name] = true
		
		if not skip_once then
			--print('on_event.once:', name)
		
			for _,callback in ipairs(listeners_once[name]) do
				call_event(callback)
			end
			for k in pairs(listeners_once[name]) do
				listeners_once[name][k] = nil
			end
		end
		
		--print('on_event.each:', name)
		
		for _,callback in ipairs(listeners_each[name]) do
			call_event(callback)
		end
	end
	on_event.each[name] = function(callback)
		table.insert(listeners_each[name],callback)
	end 
	on_event.once[name] = function(callback)
		if exhausted_events[name] then return call_event(callback) end
		table.insert(listeners_once[name],callback)
	end
	on_event.next[name] = function(callback)
		table.insert(listeners_once[name],callback)
	end
end

define_event('mod')
define_event('game')

define_event('reload')
define_event('pause')
define_event('resume')

define_event('player')
define_event('system')
define_event('level')
define_event('ready')

local remap_UIAction_System = {
	system = 'OnSystemStarted';
	reload = 'OnQuickLoadingStart';
	level = 'OnLoadingComplete';
	ready = 'OnGameplayStarted';
	resume = 'OnGameResume';
	pause = 'OnGamePause';
}

local reloadable = {}

reloadable.reload = true
reloadable.level = true
reloadable.player = true
reloadable.ready = true

on_event.each.reload(function()
	for _,k in ipairs(reloadable) do
		exhausted_events[k] = false
	end
end)

on_event.each.resume(function()
	exhausted_events.pause = false
end)

on_event.each.pause(function()
	exhausted_events.resume = false
end)

on_event.each.ready(function()
	trigger_event.resume()
end)

on_event.each.game( function()
	local register = rom.game.UIAction.RegisterEventSystemListener
	for name, event in pairs(remap_UIAction_System) do
		register({f=trigger_event[name]}, 'System', event, 'f')
	end
	trigger_event.pause()
end )

local last_player
local loaded_game

local function check_load()
	if rom.game then
		if not loaded_game then
			loaded_game = true
			trigger_event.game()
		end
		if rom.game.player ~= last_player then
			last_player = rom.game.player
			trigger_event.player()
		end
	end
end

rom.gui.add_always_draw_imgui(check_load)

on_event.once.game(function()
	-- nearly fixed...
	--import("mod.lua", rom.game, public)
end)