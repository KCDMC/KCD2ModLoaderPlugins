---@diagnostic disable: lowercase-global

-- bindings
-- e.g. name = rom.ImGuiKey[key];

key_bindings = {
	
}

key_bindings_hold = {

}

-- write to these

patches = {}

-- read from these

patches_ready = patches_ready or {}
patches_active = patches_active or {}

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

--- begin patches

do -- durable: no durability loss (for player)
	-- https://fearlessrevolution.com/viewtopic.php?p=393239&sid=0007567b3eb2f3f6f798ee2c48b560e4#p393239
	
	function patches.durable()
		-- target: movss   dword ptr [rbx+34], xmm3
		-- address xmm3: new durability
		-- address rbx: item pointer
		-- address [rbx+54]: actor ID
		-- address [rbx+34]: old durability
		local ptr = memory.scan_pattern("F3 0F 11 5B 34 48 8B 01") -- unique in IDA and Cheat Engine
		memory.dynamic_hook_mid("durable", {"xmm3", "[rbx+54]", "[rbx+34]"}, {"float", "int", "float"}, 0, ptr, function(args)
			if patches_active.durable and args[2]:get() == 0 then -- is player
				args[1]:set(args[3]:get()) -- new durability is old durability
			end
		end)
	end

end

do -- durable_set_1: always max durability (assumed 1) (for player)
	-- https://fearlessrevolution.com/viewtopic.php?p=393239&sid=0007567b3eb2f3f6f798ee2c48b560e4#p393239
	
	function patches.durable_set_1()
		-- target: movss   dword ptr [rbx+34], xmm3
		-- address xmm3: new durability
		-- address rbx: item pointer
		-- address [rbx+54]: actor ID
		-- address [rbx+34]: old durability
		local ptr = memory.scan_pattern("F3 0F 11 5B 34 48 8B 01") -- unique in IDA and Cheat Engine
		memory.dynamic_hook_mid("durable_set_1", {"xmm3", "[rbx+54]"}, {"float", "int"}, 0, ptr, function(args)
			if patches_active.durable_set_1 and args[2]:get() == 0 then -- is player
				args[1]:set(1) -- new durability is 1
			end
		end)
	end

end

do -- durable_set_1: always max durability (assumed 100) (for player)
	-- https://fearlessrevolution.com/viewtopic.php?p=393239&sid=0007567b3eb2f3f6f798ee2c48b560e4#p393239
	
	function patches.durable_set_100()
		-- target: movss   dword ptr [rbx+34], xmm3
		-- address xmm3: new durability
		-- address rbx: item pointer
		-- address [rbx+54]: actor ID
		-- address [rbx+34]: old durability
		local ptr = memory.scan_pattern("F3 0F 11 5B 34 48 8B 01") -- unique in IDA and Cheat Engine
		memory.dynamic_hook_mid("durable_set_100", {"xmm3", "[rbx+54]"}, {"float", "int"}, 0, ptr, function(args)
			if patches_active.durable_set_100 and args[2]:get() == 0 then -- is player
				args[1]:set(100) -- new durability is 100
			end
		end)
	end

end

do -- durable_max_test: always max durability (for player) ???
	-- https://fearlessrevolution.com/viewtopic.php?p=393239&sid=0007567b3eb2f3f6f798ee2c48b560e4#p393239
	
	function patches.durable_max_test()
		-- target: movss   dword ptr [rbx+34], xmm3
		-- address xmm0: max durability ???
		-- address xmm3: new durability
		-- address rbx: item pointer
		-- address [rbx+54]: actor ID
		-- address [rbx+34]: old durability
		local ptr = memory.scan_pattern("F3 0F 11 5B 34 48 8B 01") -- unique in IDA and Cheat Engine
		memory.dynamic_hook_mid("durable_max_test", {"xmm3", "[rbx+54]", "xmm0"}, {"float", "int", "float"}, 0, ptr, function(args)
			if patches_active.durable_max_test and args[2]:get() == 0 then -- is player
				args[1]:set(args[3]:get()) -- new durability is other min arg
			end
		end)
	end

end

--- end patches

local function patch_enable(name)
	if not patches_ready[name] then
		patches[name]()
		patches_ready[name] = true
	end
	patches_active[name] = true
end

local function patch_disable(name)
	patches_active[name] = false
end


rom.gui.add_always_draw_imgui(function()
	for k,v in pairs(key_bindings) do
		if rom.ImGui.IsKeyPressed(v) then
			if patches_active[k] then
				patch_disable(k)
			else
				patch_enable(k)
			end
		end
	end
	for k,v in pairs(key_bindings_hold) do
		if rom.ImGui.IsKeyDown(v) then
			if not patches_active[k] then
				patch_enable(k)
			end
		else
			if patches_active[k] then
				patch_disable(k)
			end
		end
	end
end)

rom.gui.add_to_menu_bar(function()
	for k in pairs(patches) do
		local active, clicked = rom.ImGui.Checkbox(k, patches_active[k] or false)
		if clicked then
			if active then
				patch_enable(k)
			else
				patch_disable(k)
			end
		end
	end
end)