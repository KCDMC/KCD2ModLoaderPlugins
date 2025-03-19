---@diagnostic disable: lowercase-global

key_bindings = {

}

tests = {}
tests_enable = {}
tests_disable = {}

--- common bindings (avoid globals to avoid self-introspection)

---@diagnostic disable-next-line: undefined-global
local rom = rom
local memory = rom.memory or memory
local env = getfenv(1)
local _G = _G
local pairs = pairs
local type = type
local tostring = tostring
local pcall = pcall
local xpcall = xpcall
local select = select
local getmetatable = getmetatable
local sethook = debug.sethook
local getinfo = debug.getinfo
local getlocal = debug.getlocal
local traceback = debug.traceback
local print = print
local error = error
local unpack = unpack
local pack = function (...)
    return { n = select('#', ...), ... }
end
local function tolookup(t)
    local lookup = {}
    for k,v in pairs(t) do
        lookup[v] = k
    end
    return lookup
end

--- begin tests

if false then --do
	local xml = rom.mods['Testing-XML']
	
	local file_path = "libs/tables/item/inventorypreset__poi.xml"

	xml.hook(file_path, function(data)
		for i,preset in pairs(data.database.InventoryPresets.InventoryPreset) do
			if preset._attr.Name == 'inventory_poi_zarostlaZemnice_chest' then
				print('one way A:', i, preset, xml.encode{InventoryPreset = preset})
				for j,item in pairs(preset.PresetItem) do
					if item._attr.Name == 'money' then
						print('one way B:', j, item, xml.encode{PresetItem = item})
						item._attr.Amount = '4000'
						print('one way C:', xml.encode{PresetItem = item})
					end
				end
			end
		end
	end)
	
	local gs, gm, fs, fm = xml.helpers()
	
	local data_path1 = xml.path.database.InventoryPresets.InventoryPreset.Name.inventory_poi_zarostlaZemnice_chest
	local node_path1 = gs^gs^gm^fs
	
	local data_path2 = xml.path.PresetItem.Name.money
	local node_path2 = gm^fs
	
	xml.hook(file_path, function(data)
		local preset = node_path1(data,data_path1())
		print('another way A:', preset, xml.encode{InventoryPreset = preset})
		local item = node_path2(preset,data_path2())
		print('another way B:', item, xml.encode{PresetItem = item})
		item._attr.Amount = '8000'
		print('another way C:', xml.encode{PresetItem = item})
	end)
end

--- end tests

tests_active = tests_active or {}

rom.gui.add_always_draw_imgui(function()
	for k,v in pairs(key_bindings) do
		if rom.ImGui.IsKeyPressed(v) then
			local w = tests[k]
			if w == nil then
				w = tests_enable[k]
				if w ~= nil then
					if tests_active[k] then
						w = tests_disable[k]
						if w ~= nil then
							tests_active[k] = false
							print('test disable:',k)
							w()
						else
							rom.log.error('could not find test' .. k)
						end
					else
						tests_active[k] = true
						print('test enable:',k)
						w()
					end
				else
					rom.log.error('could not find test' .. k)
				end
			else
				print('test run:',k)
				w()
			end
		end
	end
end)

rom.gui.add_to_menu_bar(function()
	for k,v in pairs(tests_enable) do
		local active, clicked = rom.ImGui.Checkbox(k, tests_active[k] or false)
		if clicked then
			tests_active[k] = active
			if active then
				print('test enable:',k)
				v()
			else
				print('test disable:',k)
				tests_disable[k]()
			end
		end
	end
	for k,v in pairs(tests) do
		local clicked = rom.ImGui.Button(k)
		if clicked then
			print('test run:',k)
			v()
		end
	end
end)