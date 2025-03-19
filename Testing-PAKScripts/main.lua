---@meta _
---@diagnostic disable

local envy = rom.mods['LuaENVY-ENVY']
envy.auto()

local modutil = rom.mods['Testing-ModUtil']

local scripts_path = _PLUGIN.plugins_data_mod_folder_path

local default_script_bind = rom.ImGuiKey.F7
local default_script_name = 'autorun.lua'
local default_script_code = "System.LogAlways('PAKScripts AUTORUN EXECUTED!')"
local default_script_path = rom.path.combine(scripts_path, default_script_name)

rom.path.create_directory(scripts_path)

do
	--local found = pcall(function()
	--	local file = io.open(default_script_path)
	--	file:close()
	--end)
	local found = false
	for _ in pairs(rom.path.get_files(scripts_path)) do
		found = true
		break
	end
	if not found then
		local file = io.open(default_script_path,'w')
		file:write(default_script_code)
		file:close()
	end
end

local env = {}

local function reload_scripts()
	--envy.import(env,default_script_path,rom.game)
	for _,file_path in pairs(rom.path.get_files(scripts_path)) do
		envy.import(env,file_path,rom.game)
	end
end

modutil.on_event.once.game(reload_scripts)

rom.gui.add_always_draw_imgui(function()
	if rom.ImGui.IsKeyPressed(default_script_bind) then
		reload_scripts()
	end
end)


rom.gui.add_to_menu_bar(function()
	if rom.ImGui.Button("Reload Scripts") then
		reload_scripts()
	end
end)