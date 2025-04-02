---@diagnostic disable: lowercase-global

local envy = rom.mods['LuaENVY-ENVY']
local rawpairs = pairs

envy.auto()

key_bindings = {

}

tests_run = {}
tests_enable = {}
tests_disable = {}

--- begin tests



--- end tests

tests_active = tests_active or {}

local function run_test(name)
	local test = tests_run[name]
	print('test run:',name)
	return test()
end

local function enable_test(name)
	local test = tests_enable[name]
	tests_active[name] = true
	print('test enable:',name)
	return test()
end

local function disable_test(name)
	local test = tests_disable[name]
	tests_active[name] = false
	test()
	print('test disable:',name)
end

local function toggle_test(name)
	if tests_active[name] then
		return disable_test(name)
	else
		return enable_test(name)
	end
end

rom.gui.add_always_draw_imgui(function()
	for k,v in pairs(key_bindings) do
		if rom.ImGui.IsKeyPressed(v) then
			local w = tests_run[k]
			if w == nil then
				toggle_test(k)
			else
				run_test(k)
			end
		end
	end
end)

rom.gui.add_to_menu_bar(function()
	for k in pairs(tests_enable) do
		local _, clicked = rom.ImGui.Checkbox(k, tests_active[k] or false)
		if clicked then
			toggle_test(k)
		end
	end
	for k in pairs(tests_run) do
		if rom.ImGui.Button(k) then
			run_test(k)
		end
	end
end)

local tests = {}
for k in pairs(tests_run) do
	tests[k] = 'action'
end
for k in pairs(tests_enable) do
	tests[k] = 'switch'
end

public.tests = tests
public.run_test = run_test
public.enable_test = enable_test
public.disable_test = disable_test
public.toggle_test = toggle_test