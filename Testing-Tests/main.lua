---@diagnostic disable: lowercase-global

local envy = rom.mods['LuaENVY-ENVY']
envy.auto()

key_bindings = {
	save = rom.ImGuiKey.F5;
	meta_graph2 = rom.ImGuiKey.F4;
}

tests_run = {}
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
local print = print -- you could replace this with some io or socket stuff
local error = error
local unpack = unpack
local gsub = string.gsub
local find = string.find
local sub = string.sub
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

tests_run.save = function() rom.game.Game.SaveGameViaResting() end

do -- meta_graph2: trace function calls live - metatables only

    local hook_set = false
    local global_lookup

	local lookup_depth = 2
    local lookup_exclude = tolookup{
		_G, env, rom, rom.game;
		string, tostring, select, pairs, pcall, type, getmetatable, gsub, find, sub;
	}
	
	local graph
	local stack
	local called = {}
	
	local metatables
	local metatables_window
	
	local names
	local global_names
	
	local unknown_meta_prefix = "Unknown Metatable "
	
	local function inspect() return rom.game.inspect or function() end end

	local function connect(a,b)
		if a == b then return false end
		local da = graph[a] or {}
		graph[a] = da
		if da[b] then return false end
		da[b] = true
		return true
	end
	
	local function name_or_address(ref)
		local name = names[ref]
		if name ~= nil then return name end
		
		name = global_names[ref]
		if name ~= nil then
			--name = 'global_' .. name
			names[ref] = name
			return name 
		end
		
		for k,v in pairs(rom.game.__cryengine__metatables) do
			if v == ref then
				name = gsub(gsub(gsub(k,unknown_meta_prefix,'unknown_'),' ','_'),'::','__')
				break
			end
		end
		
		if name == nil then
			local refstr = tostring(ref)
			local i = find(refstr,':')
			name = sub(refstr,1,i-1) .. '_' .. sub(refstr,i+7)
		end
		
		names[ref] = name
		return name
	end
	
	local function connect_list(node,list)
		local n = #list
		for i = 1, n, 1 do
			local v = list[i]
			local m = getmetatable(v)
			if type(v) ~= 'string' and m then
				connect(node,m)
			end
		end
	end

	local inspect_filter_nokeys = { process = function(v, p)
		if p[#p] == inspect().KEY then
			return name_or_address(v)
		else
			return v
		end
	end }

    --- tracing calls

    local function call_tracing(func,...)
        if not hook_set then
            return func(...)
        end
        local p = global_lookup[func]
        if p == nil then
            return func(...)
        end

		if not called[p.path] then
			called[p.path] = true
			print('call', p.path)
		end

		local q = stack[#stack]
		
		if q then
			connect(q.parent,p.parent)
		end
		
		table.insert(stack,p)

		local args = pack(...)

		connect_list(p.parent,args)

        local rets = pack(func(...))

		connect_list(p.parent,rets)

		table.remove(stack)

        return unpack(rets)
    end


    --- managing global lookup

    local function cleanup_lookup()
        for f,p in pairs(global_lookup) do
			if type(f) == 'function' then
				p.parent[p.key] = f
			end
        end
        global_lookup = nil
    end

    local function inner_generate_lookup(max_depth,depth,path,parent,key,value)
        if depth > max_depth then return end
        if depth > 0 and lookup_exclude[value] or lookup_exclude[key] then return end
        if global_lookup[value] ~= nil then return end
        local t = type(value)
        if t == 'function' then
            global_lookup[value] = {path = path, parent = parent, key = key}
            parent[key] = function(...) return call_tracing(value,...) end
        elseif t == 'table' or t == 'userdata' then
			if depth == 1 then
				key = name_or_address(value)
				path = key
			end
			local meta = getmetatable(value)
			if meta then
				connect(value, meta, 'meta')
			end
			if t ~= 'userdata' then
				for k,v in pairs(value) do
					local path = path
					if path ~= nil then
						path = path .. '.' .. k
					else
						path = k
					end
					inner_generate_lookup(max_depth,depth+1,path,value,k,v)
				end
			end
        end
    end

    local function generate_lookup()
		if global_lookup ~= nil then
            cleanup_lookup()
        end
        global_lookup = {}
		
		graph = {}
		stack = {}
		called = {}
		
		metatables = {}
		metatables_window = {}
		
		names = {}
		global_names = {}
		
		for k,v in pairs(rom.game) do
			global_names[v] = k
		end
    end
	
	--- update hook

	local function update_hook()
		if not hook_set then return end
		
		hook_set = false
		
		for k,v in pairs(rom.game.__cryengine__metatables) do
			if names[v] == nil then
				metatables_window[name_or_address(v)] = v
			end
		end
		
		inner_generate_lookup(lookup_depth,0,nil,nil,nil,metatables_window)
		
		for k in pairs(metatables_window) do
			metatables[k] = v
		end
		
		for k in pairs(metatables) do
			metatables_window[k] = nil
		end
		
		hook_set = true
		
	end
	
	rom.gui.add_always_draw_imgui(update_hook)
	
    --- toggle tracing

    local function enable_tracing()
        if hook_set then
            error('hook active, cannot begin')
            return
        end
        
        generate_lookup()

        hook_set = true
		
		update_hook()
    end

    local function disable_tracing()
        if not hook_set then
            error('hook not active, cannot end')
            return
        end

        hook_set = false
		
		local inspect = inspect()
		if inspect then
			local content = inspect(graph,inspect_filter_nokeys)
			local data_path = _PLUGIN.plugins_data_mod_folder_path
			rom.path.create_directory(data_path)
			local file_path = rom.path.combine(data_path,'Testing-Tests.meta_graph2.txt')
			local file = io.open(file_path,'w')
			file:write(content)
			file:close()
			print("DUMP:", #content)
		end
		
		cleanup_lookup()
    end

    function tests_enable.meta_graph2()
        return enable_tracing()
    end

    function tests_disable.meta_graph2()
        return disable_tracing()
    end
end


do -- meta_graph: trace function calls live - metatables only

    local hook_set = false
    local global_lookup

	local lookup_depth = 2
    local lookup_exclude = tolookup{
		_G, env, rom, rom.game, string, tostring, select, pairs, pcall, type, getmetatable;
	}
	
	local graph 
	local stack
	local called
	local names = setmetatable({},{__mode='k'})
	
	local function inspect() return rom.game.inspect or function() end end

	local function connect(a,b)
		if a == b then return false end
		local da = graph[a] or {}
		graph[a] = da
		if da[b] then return false end
		da[b] = true
		return true
		--local db = graph[b] or {}
		--graph[b] = db
		--db[a] = true
	end
	
	local function name_or_address(ref)
		local refstr = tostring(ref)
		local i = refstr:find(':')
		return refstr:sub(1,1):upper() .. '_' .. refstr:sub(i+2)
	end
	
	local function connect_list(node,list,func)
		local n = #list
		for i = 1, n, 1 do
			local v = list[i]
			local m = (func or getmetatable)(v)
			if type(v) ~= 'string' and m then
				if connect(node,m) then
					print("DATA:",name_or_address(node),name_or_address(m))
				end
			end
		end
	end

	local inspect_filter_nokeys = { process = function(v, p)
		if p[#p] == inspect().KEY then
			return names[v] or name_or_address(v)
		else
			return v
		end
	end }

	local function get_metatables()
		local metatables_list = rom.game.__cryengine__metatables
		local metatables = {}
		
		for k,v in pairs(rom.game) do
			if names[v] == nil then
				names[v] = k
			end
		end
		
		for _,v in ipairs(metatables_list) do
			metatables[name_or_address(v)] = v
		end
		
		return metatables
	end

    --- tracing calls

    local function call_tracing(func,...)
        if not hook_set then
            return func(...)
        end
        local p = global_lookup[func]
        if p == nil then
            return func(...)
        end

		local q = stack[#stack]

		if not called[func] then
			called[func] = true
			print('CALLED:', p.path, q and q.path or '')
		end
		
		if q then
			connect_list(q.parent,p.parent)
		end
		
		table.insert(stack,p)

		local args = pack(...)

		connect_list(p.parent,args)

        local rets = pack(func(...))

		connect_list(p.parent,rets)

		table.remove(stack)

        return unpack(rets)
    end


    --- managing global lookup

    local function cleanup_lookup()
        for f,p in pairs(global_lookup) do
			if type(f) == 'function' then
				p.parent[p.key] = f
			end
        end
        global_lookup = nil
    end

    local function inner_generate_lookup(max_depth,depth,path,parent,key,value)
        if depth > max_depth then return end
        if depth > 0 and lookup_exclude[value] or lookup_exclude[key] then return end
        if global_lookup[value] ~= nil then return end
        local t = type(value)
        if t == 'function' then
            global_lookup[value] = {path = path, parent = parent, key = key}
            parent[key] = function(...) return call_tracing(value,...) end
        elseif t == 'table' or t == 'userdata' then
			--[[
			if parent ~= nil then
				if connect(parent,value) then
					print('CHILD:', name_or_address(parent), name_or_address(value))
				end
			end
			--]]
			local meta = getmetatable(value)
			if meta and connect(value, meta) then
				local name = names[meta]
				if name == nil then
					name = 'M' .. name_or_address(meta)
					names[meta] = name
				end
				print('META:', name_or_address(value), name_or_address(meta))
			end
			if t ~= 'userdata' then
				for k,v in pairs(value) do
					local path = path
					if path ~= nil then
						path = path .. '.' .. k
					else
						path = k
					end
					inner_generate_lookup(max_depth,depth+1,path,value,k,v)
				end
			end
        end
    end

    local function generate_lookup(depth)
        -- associates references with a global path
        -- uses DFS (depth-first search) currently, but BFS (breadth-first search) would be ideal
        if global_lookup ~= nil then
            cleanup_lookup()
        end
        global_lookup = {}
		graph = {}
		stack = {}
		called = {}
        inner_generate_lookup(depth,0,nil,nil,nil,get_metatables())
    end
    --- toggle tracing

    local function enable_tracing()
        if hook_set then
            error('hook active, cannot begin')
            return
        end
        
        generate_lookup(lookup_depth)

        hook_set = true
    end

    local function disable_tracing()
        if not hook_set then
            error('hook not active, cannot end')
            return
        end

        hook_set = false
		
		local inspect = inspect()
		if inspect then
			local content = inspect(graph,inspect_filter_nokeys)
			local data_path = _PLUGIN.plugins_data_mod_folder_path
			rom.path.create_directory(data_path)
			local file_path = rom.path.combine(data_path,'Testing-Tests.meta_graph2.txt')
			local file = io.open(file_path,'w')
			file:write(content)
			file:close()
			print("DUMP:", #content)
		end
		
		cleanup_lookup()
    end

    function tests_enable.meta_graph()
        return enable_tracing()
    end

    function tests_disable.meta_graph()
        return disable_tracing()
    end
end

do -- tracing3: trace function calls live - metatables only

    local hook_set = false
    local global_lookup

	local lookup_depth = 2
    local lookup_exclude = tolookup{
		_G, env, rom, rom.game, string, tostring, select, pairs, pcall, type, getmetatable;
		
		-- ignoring things that get spammed in the prologue constantly
		"SetPhysicParams", "SetAudioRtpcValue", "OnEnablePhysics", "GetAnimationTime", "IsAnimationRunning", "GetDefaultAuxAudioProxyID", "UpdateFadeValue", "_UpdateRtpc","SetInteractiveCollisionType","IsUsable";
		-- regular but spammy
		"FreeSlot","Activate","ActivateOutput","LoadLight","LoadLightToSlot","ActivateLight","OnReset","CacheResources","SetFlags";
		-- regular but not spammy
		"OnHit","CacheResource","IsEditor","SetLightColorParams","UpdateLightTOD","GetLightDesc","InitTodActiveTable";
		-- intermittent but spammy
		"IsUsableMsgChanged","GetEntity","Action","_IHint","_IAction","_IType","_IClass","_IInteraction","_IActionMap";
		-- intermittent but not spammy
		"ConvertTimesStringToNumArray","GetWorldHourOfDay","SetColorParams","_IFunc","AddInteractorAction","GetCanTalkHintType";
		-- with torch out, spammy
		"SetSlotPosAndDir","GetHelperDir","GetSlotHelperPos","LoadParticleEffect","DeleteParticleEmitter","SetFlagsExtended";
		-- putting torch away, spammy
		"SetUpdatePolicy","OnIdle","Cleanup","OnActivate";
		-- spammy with extra metatables
		"OnAction","GetActions","CanInteractWith","ForceUsable","IsInTenseCircumstance","HasScriptContext","CanFollow";
		-- spammy with extra metatables 2
		"IsOpen","ReportUnlocked","Unlock","DoPlayAnimation","BeforePlayAnimation","BuildObjectAnimationName","StopAnimation","StartAnimation","SetAnimationSpeed","SetAnimationTime","GetSuspiciousVolume","UpdateBeforeAnimation","ReportManipulationStart","GetAnimationLength";
		-- spammy with extra metatables 3
		"IsDialogRestricted","IsInCombatDanger","GetChatActions","IsCombatChatTarget","HasAcceptedChat","CanChat","HasChatRequest";
	}

	local function name_or_address(ref)
		local refstr = tostring(ref)
		local i = refstr:find(':')
		return refstr:sub(i+2)
	end

	local function get_metatables()
		local metatables_list = rom.game.__cryengine__metatables
		local metatables = {}
		
		local global = {} 
		for k,v in pairs(rom.game) do
			global[v] = k
		end
		
		for _,v in ipairs(metatables_list) do
			local k = global[v]
			if k == nil then
				k = '_' .. name_or_address(v)
			end
			metatables[k] = v
		end
		
		return metatables
	end

    --- tracing calls

    local function call_tracing(func,...)
        if not hook_set then
            return func(...)
        end
        local p = global_lookup[func]
        if p == nil then
            return func(...)
        end

        local path = p.path

        print('TRACE ARGS:', path, ...)

        local rets = pack(func(...))

        print('TRACE RETS:', path, unpack(rets))
		
        return unpack(rets)
    end


    --- managing global lookup

    local function cleanup_lookup()
        for f,p in pairs(global_lookup) do
			if type(f) == 'function' then
				p.parent[p.key] = f
			end
        end
        global_lookup = nil
    end

    local function inner_generate_lookup(max_depth,depth,path,parent,key,value)
        if depth > max_depth then return end
        if depth > 0 and lookup_exclude[value] or lookup_exclude[key] then return end
        if global_lookup[value] ~= nil then return end
        local t = type(value)
        if t == 'function' then
            global_lookup[value] = {path = path, parent = parent, key = key}
            parent[key] = function(...) return call_tracing(value,...) end
        elseif t == 'table' then
            for k,v in pairs(value) do
				local path = path
				if path ~= nil then
					path = path .. '.' .. k
				else
					path = k
				end
				inner_generate_lookup(max_depth,depth+1,path,value,k,v)
            end
        end
    end

    local function generate_lookup(depth)
        -- associates references with a global path
        -- uses DFS (depth-first search) currently, but BFS (breadth-first search) would be ideal
        if global_lookup ~= nil then
            cleanup_lookup()
        end
        global_lookup = {}
        inner_generate_lookup(depth,0,nil,nil,nil,get_metatables())
    end
    --- toggle tracing

    local function enable_tracing()
        if hook_set then
            error('tracing active, cannot begin')
            return
        end
        
        print("begin - tracing")

        -- max depth of 2 to avoid DFS tunneling into super/__index obscuring the root class
        generate_lookup(lookup_depth)

        hook_set = true
    end

    local function disable_tracing()
        if not hook_set then
            error('tracing not active, cannot end')
            return
        end

        hook_set = false
		
        cleanup_lookup()

        print("end - tracing")
    end

    function tests_enable.tracing3()
        return enable_tracing()
    end

    function tests_disable.tracing3()
        return disable_tracing()
    end
end


do -- tracing2: trace function calls live

    local hook_set = false
    local global_lookup

	local lookup_depth = 3
    local lookup_exclude = tolookup{
		_G, env, rom, rom.game, tostring, select, pairs, pcall, type, getmetatable;
		
		-- ignoring things that get spammed in the prologue constantly
		"SetPhysicParams", "SetAudioRtpcValue", "OnEnablePhysics", "GetAnimationTime", "IsAnimationRunning", "GetDefaultAuxAudioProxyID", "UpdateFadeValue", "_UpdateRtpc","SetInteractiveCollisionType","IsUsable";
		-- regular but spammy
		"FreeSlot","Activate","ActivateOutput","LoadLight","LoadLightToSlot","ActivateLight","OnReset","CacheResources","SetFlags";
		-- regular but not spammy
		"OnHit","CacheResource","IsEditor","SetLightColorParams","UpdateLightTOD","GetLightDesc","InitTodActiveTable";
		-- intermittent but spammy
		"IsUsableMsgChanged","GetEntity","Action","_IHint","_IAction","_IType","_IClass","_IInteraction","_IActionMap";
		-- intermittent but not spammy
		"ConvertTimesStringToNumArray","GetWorldHourOfDay","SetColorParams","_IFunc","AddInteractorAction","GetCanTalkHintType";
		-- with torch out, spammy
		"SetSlotPosAndDir","GetHelperDir","GetSlotHelperPos","LoadParticleEffect","DeleteParticleEmitter","SetFlagsExtended";
		-- putting torch away, spammy
		"SetUpdatePolicy","OnIdle","Cleanup","OnActivate";
		}

	local globalise_depth = 3
	local globalise_exclude = tolookup{'_G'}


    --- tracing calls

    local function call_tracing(func,...)
        if not hook_set then
            return func(...)
        end
        local p = global_lookup[func]
        if p == nil then
            return func(...)
        end

        local path = p.path

        print('TRACE ARGS:', path, ...)

        local rets = pack(func(...))

        print('TRACE RETS:', path, unpack(rets))
		
        return unpack(rets)
    end


    --- managing global lookup

    local function cleanup_lookup()
        for f,p in pairs(global_lookup) do
			if type(f) == 'function' then
				p.parent[p.key] = f
			end
        end
        global_lookup = nil
    end

    local function inner_generate_lookup(max_depth,depth,path,parent,key,value)
        if depth > max_depth then return end
        if depth > 0 and lookup_exclude[value] or lookup_exclude[key] then return end
        if global_lookup[value] ~= nil then return end
        local t = type(value)
        if t == 'function' then
            global_lookup[value] = {path = path, parent = parent, key = key}
            parent[key] = function(...) return call_tracing(value,...) end
        elseif t == 'table' then
            for k,v in pairs(value) do
                if type(k) == 'string' then
					local c = k:sub(1,1)
					if c ~= '_' and c == c:upper() then -- ignore lowercase paths
						local path = path
						if path ~= nil then
							path = path .. '.' .. k
						else
							path = k
						end
						inner_generate_lookup(max_depth,depth+1,path,value,k,v)
					end
                end
            end
        end
    end

    local function generate_lookup(depth)
        -- associates references with a global path
        -- uses DFS (depth-first search) currently, but BFS (breadth-first search) would be ideal
        if global_lookup ~= nil then
            cleanup_lookup()
        end
        global_lookup = {}
        inner_generate_lookup(depth,0,nil,nil,nil,rom.game)
    end

    local function inner_globalise_metatables(max_depth,depth,path,parent,key,value)
        if depth > max_depth then return end
		if depth > 0 and globalise_exclude[value] or globalise_exclude[key] then return end
        local t = type(value)
		if t == 'userdata' then
			local meta = getmetatable(value)
			if meta then
				rom.game.METATABLES[path] = meta
			end
		end
        if t == 'table' then
			local meta = getmetatable(value)
			if meta then
				rom.game.METATABLES[path] = meta
			end
		
            for k,v in pairs(value) do
                if type(k) == 'string' then
					local path = path
					if path ~= nil then
						path = path .. '.' .. k
					else
						path = k
					end
					inner_globalise_metatables(max_depth,depth+1,path,value,k,v)
                end
            end
        end
    end

    local function globalise_metatables(depth)
        -- associates references with a global path
        -- uses DFS (depth-first search) currently, but BFS (breadth-first search) would be ideal
		rom.game.METATABLES = rom.game.METATABLES or {}
        inner_globalise_metatables(depth,0,nil,nil,nil,rom.game)
    end

    --- toggle tracing

    local function enable_tracing()
        if hook_set then
            error('tracing active, cannot begin')
            return
        end
        
        print("begin - tracing")

        -- max depth of 2 to avoid DFS tunneling into super/__index obscuring the root class
		globalise_metatables(globalise_depth)
        generate_lookup(lookup_depth)

        hook_set = true
    end

    local function disable_tracing()
        if not hook_set then
            error('tracing not active, cannot end')
            return
        end

        hook_set = false
		
        cleanup_lookup()

        print("end - tracing")
    end

    function tests_enable.tracing2()
        return enable_tracing()
    end

    function tests_disable.tracing2()
        return disable_tracing()
    end
end

do -- trace_UIAction
	
	local listener = { listen = function(self, ...)
		print('TRACE UIACTION:', ...)
	end }
	
	function tests_enable.trace_UIAction()
		--rom.game.UIAction.RegisterElementListener( listener, "", -1, "", "listen" )
		--rom.game.UIAction.RegisterActionListener( listener, "", "", "listen" )
		rom.game.UIAction.RegisterEventSystemListener( listener, "", "", "listen" )
	end
	
	function tests_disable.trace_UIAction()
		--rom.game.UIAction.UnregisterElementListener( listener, "listen" )
		--rom.game.UIAction.UnregisterActionListener( listener, "listen" )
		rom.game.UIAction.UnregisterEventSystemListener( listener, "listen" )
	end
	
end

do -- trace_setter

	local __G
	local meta

	function tests_enable.trace_setter()
		__G = {}
	
		meta = getmetatable( rom.game )
		
		setmetatable( rom.game )
	
		for k,v in pairs(rom.game) do
			__G[k] = v
			rom.game[k] = nil
		end
		
		for k in pairs(__G) do
			rom.game[k] = nil
		end

		setmetatable( rom.game, { __index = __G, __newindex = function(_,k,v)
			__G[k] = v
			print('TRACE SET:', k,v)
		end } )
	end
	
	function tests_disable.trace_setter()
		if meta ~= nil then
			setmetatable(rom.game,meta)
		else
			setmetatable(rom.game)
		end

		for k,v in pairs(__G) do
			rom.game[k] = v
		end
		
		__G = nil
	end
	
end

do -- tracing: trace function calls live

    local hook_set = false
    local global_lookup

    local lookup_exclude = tolookup{_G, env, rom, rom.game, tostring, select, pairs, pcall, type, getmetatable}


    --- tracing calls

    local function call_tracing(func,...)
        if not hook_set then
            return func(...)
        end
        local p = global_lookup[func]
        if p == nil then
            return func(...)
        end

        local path = p.path

        print('TRACE ARGS:', path, ...)

        local rets = pack(func(...))

        print('TRACE RETS:', path, unpack(rets))
		
        return unpack(rets)
    end


    --- managing global lookup

    local function cleanup_lookup()
        for f,p in pairs(global_lookup) do
			if type(f) == 'function' then
				p.parent[p.key] = f
			end
        end
        global_lookup = nil
    end

    local function inner_generate_lookup(max_depth,depth,path,parent,key,value)
        if depth > max_depth then return end
        if depth > 0 and lookup_exclude[value] then return end
        if global_lookup[value] ~= nil then return end
        local t = type(value)
        if t == 'function' then
            global_lookup[value] = {path = path, parent = parent, key = key}
            parent[key] = function(...) return call_tracing(value,...) end
        elseif t == 'table' then
            for k,v in pairs(value) do
                if type(k) == 'string' then
					local c = k:sub(1,1)
					if c ~= '_' and c == c:upper() then -- ignore lowercase paths
						local path = path
						if path ~= nil then
							path = path .. '.' .. k
						else
							path = k
						end
						inner_generate_lookup(max_depth,depth+1,path,value,k,v)
					end
                end
            end
        end
    end

    local function generate_lookup(depth)
        -- associates references with a global path
        -- uses DFS (depth-first search) currently, but BFS (breadth-first search) would be ideal
        if global_lookup ~= nil then
            cleanup_lookup()
        end
        global_lookup = {}
        inner_generate_lookup(depth,0,nil,nil,nil,rom.game)
    end


    --- toggle tracing

    local function enable_tracing()
        if hook_set then
            error('tracing active, cannot begin')
            return
        end
        
        print("begin - tracing")

        -- max depth of 2 to avoid DFS tunneling into super/__index obscuring the root class
        generate_lookup(2)

        hook_set = true
    end

    local function disable_tracing()
        if not hook_set then
            error('tracing not active, cannot end')
            return
        end

        hook_set = false
		
        cleanup_lookup()

        print("end - tracing")
    end

    function tests_enable.tracing()
        return enable_tracing()
    end

    function tests_disable.tracing()
        return disable_tracing()
    end
end

do -- aft: aggregate function types (stable)

    local tracemode = "c" -- c, r, l are valid elements
    local hook_set = false
    local within_hook = false
    local within_call = false
    local aggregate
    local global_lookup

    local lookup_exclude = tolookup{_G, env, rom, rom.game, sethook, tostring, select, pairs, pcall, type, getmetatable}
    local type_order = {'boolean', 'integer', 'number', 'string', 'function', 'thread', 'table', 'userdata'}

    
    --- collecting types from data

    local function get_type(object)
        local t = type(object)
        if t ~= 'table' and t ~= 'userdata' then
            return t
        end
        --assume documentation namespace
        local meta = getmetatable(object)
        if meta == nil or meta.type == nil then
            return t
        end
        local namespace = 'kcd2def*'
        t = meta.type
        if rom.game[t] == meta then
            return namespace .. t
        end
        return namespace .. 'unknown-' .. t
    end

    local function join_type_set(data,kind,value,name)
        local names, types
        local t = get_type(value)
        if kind == nil then
            -- skip this layer
            names = data
        else
            names = data[kind]
            if names == nil then
                names = {}
                data[kind] = names
            end
        end
        if name == nil then
            -- skip this layer
            types = names
        else
            types = names[name]
            if types == nil then
                types = {}
                names[name] = types
            end
        end
        types[t] = true
    end

    local function join_types(types)
        -- mutates the data provided

        --local opt = types['nil']
        --types['nil'] = nil
        local expr = ''
        local sep = '|'
        for _,t in ipairs(type_order) do
            if types[t] then
                types[t] = nil
                expr = expr .. sep .. t
            end
        end
        local rest = {}
        local n = 0
        for k in pairs(types) do
            n = n + 1
            rest[n] = k
        end
        table.sort(rest)
        for _,t in ipairs(rest) do
            expr = expr .. sep .. t
        end
        --if opt then
        --    expr = expr .. '?'
        --end
        expr = expr:sub(2)
        
        if #expr == 0 then return 'unknown' end
        
        return expr
    end
    

    --- tracing calls and collecting data

    local function get_function_data(path)
        local data = aggregate[path]
        if data == nil then
            data = {}
            aggregate[path] = data
        end
        return data
    end

    local function calltracer(event)
        if not hook_set then return end
        if not within_call then return end
        if event == 'tail return' then return end
        
        within_hook = true
        
        local info = getinfo(2,"f")
        local p = global_lookup[info.func]
        
        if p ~= nil then
            local path = p.path
            --print(event .. ': ' .. path)
            local data = get_function_data(path)
            local i = 1
            local n = 0
            if event == 'call' then
                info = getinfo(info.func,"u")
                ---@diagnostic disable-next-line: undefined-field
                data.isvararg = info.isvararg
                while true do
                    local name, value = getlocal(2, i)
                    if name ~= nil then
                        if name ~= '(*temporary)' then
                            local order = data.order
                            if order == nil then
                               order = {}
                               data.order = order
                            end
                            n = n + 1
                            order[n] = name
                            join_type_set(data,'param',value,name)
                        --else
                            --join_type_set(data,'vararg',value)
                        end
                        i = i + 1
                    else
                        break
                    end
                end
            --[[
            else -- return or line work here, line is more consistent but expensive
                -- in theory, this may allow for documenting the names of return values
                while true do
                    local name, value = getlocal(2, i)
                    if name ~= nil then
                        if name ~= '(*temporary)' then
                            join_type_set(data,name,value,'local',i)
                        end
                        i = i + 1
                    else
                        break
                    end
                end
            --]]
            end

        end
        
        within_hook = false
    end

    local function trace_call(func,...)
        if within_hook or not hook_set then
            return func(...)
        end
        local p = global_lookup[func]
        if p == nil then
            return func(...)
        end

        local path = p.path

        --print('wcall: ' .. path)

        local args = pack(...)

        local data = get_function_data(path)
        if data ~= nil then
            for i = 1, args.n, 1 do
                join_type_set(data,'arg',args[i],i)
            end
        end

        local outer_layer = not within_call

        if outer_layer then
            sethook(calltracer,tracemode)
            within_call = true
        end

        local rets = pack(func(...))

        if outer_layer then
            within_call = false
            sethook()
        end

        data = get_function_data(path)
        if data ~= nil then
            for i = 1, rets.n, 1 do
                join_type_set(data,'return',rets[i],i)
            end
        end

        --print('wreturn: ' .. path)
        return unpack(rets)
    end


    --- managing global lookup

    local function cleanup_lookup()
        for f,p in pairs(global_lookup) do
            p.parent[p.key] = f
        end
        global_lookup = nil
    end

    local function inner_generate_lookup(max_depth,depth,path,parent,key,value)
        if depth > max_depth then return end
        if depth > 0 and lookup_exclude[value] then return end
        if global_lookup[value] ~= nil then return end
        local t = type(value)
        if t == 'function' then
            global_lookup[value] = {path = path, parent = parent, key = key}
            parent[key] = function(...) return trace_call(value,...) end
        elseif t == 'table' then
            for k,v in pairs(value) do
                if type(k) == 'string' then
					local c = k:sub(1,1)
					if c ~= '_' and c == c:upper() then -- ignore lowercase paths
						local path = path
						if path ~= nil then
							path = path .. '.' .. k
						else
							path = k
						end
						inner_generate_lookup(max_depth,depth+1,path,value,k,v)
					end
                end
            end
        end
    end

    local function generate_lookup(depth)
        -- associates function references with a global path
        -- uses DFS (depth-first search) currently, but BFS (breadth-first search) would be ideal
        if global_lookup ~= nil then
            cleanup_lookup()
        end
        global_lookup = {}
        inner_generate_lookup(depth,0,nil,nil,nil,rom.game)
    end


    --- post-processing collected results

    local function process_result(result)
        -- mutates the data provided

        for _,res in pairs(result) do
            local vars = res['vararg']
            if vars ~= nil then
                res['vararg'] = join_types(vars)
            end
            local args = res['arg']
            if args ~= nil then
                for i,u in ipairs(args) do
                    args[i] = join_types(u)
                end
            end
            local rets = res['return']
            if rets ~= nil then
                for i,u in ipairs(rets) do
                    rets[i] = join_types(u)
                end
            end
            local pars = res['param']
            if pars ~= nil then
                for k,u in pairs(pars) do
                    pars[k] = join_types(u)
                end
            end
        end

        return result
    end

    local function dump_result(result,logger)
        -- produces hopefully valid type annotations

        local paths = {}
        do
            local n = 0
            for path in pairs(result) do
                n = n + 1
                paths[n] = path
            end
        end

        table.sort(paths)

        local prefix = ' fun('
        local infix = '): '
        logger = logger or print

        local lastpath = nil
        for _,path in ipairs(paths) do
            local res = result[path]
            local pars = res['param']
            if pars ~= nil then
                local pord = res['order']
                for i,n in ipairs(pord) do
                    pars[i] = n .. ': ' .. pars[n]
                end
                pars = table.concat(pars,', ')
            else
                local args = res['arg']
                if args == nil then
                    pars = ''
                else
                    pars = {}
                    local n = 0
                    for i,a in ipairs(args) do
                        n = n + 1
                        pars[n] = 'unk_' .. tostring(i) .. ': ' .. a
                    end
                    pars = table.concat(pars,', ')
                end
            end
            if res['isvararg'] then
                if #pars > 0 then
                    pars = pars .. ', '
                end
                pars = pars .. '...'
            end
            local rets = res['return']
            if rets == nil then
                rets = 'nil'
            else
                rets = table.concat(rets,', ')
            end
            
            local sig = prefix .. pars .. infix .. rets

            --- private or deprecated by default so they can be manually adjusted later
			local key = path
			local i = path:match'^.*()%.'
			if i ~= nil then
				key = path:sub(i+1)
				path = path:sub(1,i-1)
			else
				path = ''
			end

            if #path > 0 then
                if path ~= lastpath then
                    logger('')
                    logger('---@class kcd2def*' .. path)
                end
                lastpath = path
                logger('---@field private ' .. key .. sig)
            else
                logger('')
                logger('---@deprecated')
                logger('---@type' .. sig)
                logger(key .. ' = ...')
            end
            
        end
    end


    --- toggle tracing

    local function enable_aggregate_function_types()
        if hook_set then
            error('aggregate_function_types active, cannot begin')
            return
        end
        
        print("begin - aggregate_function_types")

        -- max depth of 2 to avoid DFS tunneling into super/__index obscuring the root class
        generate_lookup(2)
        aggregate = {}
        hook_set = true
    end

    local function disable_aggregate_function_types()
        if not hook_set then
            error('aggregate_function_types not active, cannot end')
            return
        end

        hook_set = false
        cleanup_lookup()

        process_result(aggregate)
        dump_result(aggregate)

        print("end - aggregate_function_types")
        
        return aggregate
    end

    function tests_enable.aft()
        return enable_aggregate_function_types()
    end

    function tests_disable.aft()
        return disable_aggregate_function_types()
    end
end

do -- meta_aft: aggregate function types (unstable)

    local tracemode = "c" -- c, r, l are valid elements
    local hook_set = false
    local within_hook = false
    local within_call = false
    local aggregate
    local global_lookup
    local path_lookup

    local lookup_exclude = tolookup{_G, env, rom, rom.game, sethook, tostring, select, pairs, pcall, type, getmetatable}
    local type_order = {'boolean', 'integer', 'number', 'string', 'function', 'thread', 'table', 'userdata'}

    
    --- collecting types from data

    local function get_metatype(meta,t)
        if meta == nil then
            return t
        end
        local mt
        local p = global_lookup ~= nil and global_lookup[meta]
        if p then
            mt = p.path
        else
            mt = meta.type
        end
        if mt == nil then
            return t
        end
        --assume documentation namespace
        local namespace = 'kcd2def*'
        if p or rom.game[mt] == meta then
            return namespace .. mt
        end
        return namespace .. 'unknown-' .. mt
    end

    local function get_type(object,func)
        local t = type(object)
        if t ~= 'table' and t ~= 'userdata' then
            return t
        end
        local p = global_lookup ~= nil and global_lookup[func]
        return get_metatype(p and p.parent) or get_metatype(object.__super) or get_metatype(getmetatable(object), t)
    end

    local function join_type_set(data,kind,value,name)
        local names, types
        local t = get_type(value,data.func)
        if kind == nil then
            -- skip this layer
            names = data
        else
            names = data[kind]
            if names == nil then
                names = {}
                data[kind] = names
            end
        end
        if name == nil then
            -- skip this layer
            types = names
        else
            types = names[name]
            if types == nil then
                types = {}
                names[name] = types
            end
        end
        types[t] = true
    end

    local function join_types(types)
        -- mutates the data provided

        --local opt = types['nil']
        --types['nil'] = nil
        local expr = ''
        local sep = '|'
        for _,t in ipairs(type_order) do
            if types[t] then
                types[t] = nil
                expr = expr .. sep .. t
            end
        end
        local rest = {}
        local n = 0
        for k in pairs(types) do
            n = n + 1
            rest[n] = k
        end
        table.sort(rest)
        for _,t in ipairs(rest) do
            expr = expr .. sep .. t
        end
        --if opt then
        --    expr = expr .. '?'
        --end
        expr = expr:sub(2)
        
        if #expr == 0 then return 'unknown' end
        
        return expr
    end
    

    --- tracing calls and collecting data

    local function get_function_data(path)
        local data = aggregate[path]
        if data == nil then
            data = {}
            aggregate[path] = data
        end
        return data
    end

    local function calltracer(event)
        if not hook_set then return end
        if not within_call then return end
        if event == 'tail return' then return end
        
        within_hook = true
        
        local info = getinfo(2,"f")
        local p = global_lookup[info.func]
        
        if p ~= nil then
            local path = p.path
            --print(event .. ': ' .. path)
            local data = get_function_data(path)
            local i = 1
            local n = 0
            if event == 'call' then
                info = getinfo(info.func,"u")
                ---@diagnostic disable-next-line: undefined-field
                data.isvararg = info.isvararg
                while true do
                    local name, value = getlocal(2, i)
                    if name ~= nil then
                        if name ~= '(*temporary)' then
                            local order = data.order
                            if order == nil then
                               order = {}
                               data.order = order
                            end
                            n = n + 1
                            order[n] = name
                            join_type_set(data,'param',value,name)
                        --else
                            --join_type_set(data,'vararg',value)
                        end
                        i = i + 1
                    else
                        break
                    end
                end
            --[[
            else -- return or line work here, line is more consistent but expensive
                -- in theory, this may allow for documenting the names of return values
                while true do
                    local name, value = getlocal(2, i)
                    if name ~= nil then
                        if name ~= '(*temporary)' then
                            join_type_set(data,name,value,'local',i)
                        end
                        i = i + 1
                    else
                        break
                    end
                end
            --]]
            end

        end
        
        within_hook = false
    end

    local function trace_call(func,...)
        if within_hook or not hook_set then
            return func(...)
        end
        local p = global_lookup[func]
        if p == nil then
            return func(...)
        end

        local path = p.path

        --print('wcall: ' .. path)

        local data = get_function_data(path)

        data.func = func

        local args = pack(...)
        for i = 1, args.n, 1 do
            join_type_set(data,'arg',args[i],i)
        end

        local outer_layer = not within_call

        if outer_layer then
            sethook(calltracer,tracemode)
            within_call = true
        end

        local rets = pack(func(...))

        if outer_layer then
            within_call = false
            sethook()
        end

        for i = 1, rets.n, 1 do
            join_type_set(data,'return',rets[i],i)
        end

        --print('wreturn: ' .. path)
        return unpack(rets)
    end


    --- managing global lookup

    local function cleanup_lookup()
        for f,p in pairs(global_lookup) do
            if type(f) == 'function' then
                p.parent[p.key] = f
            end
        end
    end

    local function inner_generate_lookup(max_depth,depth,path,parent,key,value)
        if depth > max_depth then return end
        if depth > 0 and lookup_exclude[value] then return end
        if global_lookup[value] ~= nil then return end
        local t = type(value)
        if t == 'function' then
            local p = {path = path, parent = parent, key = key, value = value}
            global_lookup[value] = p
            if path ~= nil then path_lookup[path] = p end
            parent[key] = function(...) return trace_call(value,...) end
        elseif t == 'table' then
            local p = {path = path, parent = parent, key = key, value = value}
            global_lookup[value] = p
            if path ~= nil then path_lookup[path] = p end
            for k,v in pairs(value) do
                if type(k) == 'string' then
					local c = k:sub(1,1)
					if c ~= '_' and c == c:upper() then -- ignore lowercase paths
						local path = path
						if path ~= nil then
							path = path .. '.' .. k
						else
							path = k
						end
						inner_generate_lookup(max_depth,depth+1,path,value,k,v)
					end
                end
            end
        end
    end

    local function generate_lookup(depth)
        -- associates function references with a global path
        -- uses DFS (depth-first search) currently, but BFS (breadth-first search) would be ideal
        if global_lookup ~= nil then
            cleanup_lookup()
        end
        global_lookup = {}
        path_lookup = {}
        inner_generate_lookup(depth,0,nil,nil,nil,rom.game)
    end


    --- post-processing collected results

    local function process_result(result)
        -- mutates the data provided

        for _,res in pairs(result) do
            local vars = res['vararg']
            if vars ~= nil then
                res['vararg'] = join_types(vars)
            end
            local args = res['arg']
            if args ~= nil then
                for i,u in ipairs(args) do
                    args[i] = join_types(u)
                end
            end
            local rets = res['return']
            if rets ~= nil then
                for i,u in ipairs(rets) do
                    rets[i] = join_types(u)
                end
            end
            local pars = res['param']
            if pars ~= nil then
                for k,u in pairs(pars) do
                    pars[k] = join_types(u)
                end
            end
        end

        return result
    end

    local function dump_result(result,logger)
        -- produces hopefully valid type annotations

        local paths = {}
        do
            local n = 0
            for path in pairs(result) do
                n = n + 1
                paths[n] = path
            end
        end

        table.sort(paths)

        local prefix = ' fun('
        local infix = '): '
        logger = logger or print

        local lastpath = nil
        for _,path in ipairs(paths) do
            local res = result[path]
            local pars = res['param']

            if pars ~= nil then
                local pord = res['order']
                for i,n in ipairs(pord) do
                    pars[i] = n .. ': ' .. pars[n]
                end
                pars = table.concat(pars,', ')
            else
                local args = res['arg']
                if args == nil then
                    pars = ''
                else
                    pars = {}
                    local n = 0
                    for i,a in ipairs(args) do
                        n = n + 1
                        pars[n] = 'unk_' .. tostring(i) .. ': ' .. a
                    end
                    pars = table.concat(pars,', ')
                end
            end
            if res['isvararg'] then
                if #pars > 0 then
                    pars = pars .. ', '
                end
                pars = pars .. '...'
            end
            local rets = res['return']
            if rets == nil then
                rets = 'nil'
            else
                rets = table.concat(rets,', ')
            end
            
            local sig = prefix .. pars .. infix .. rets

            local p = path_lookup[path]
            local class
            if p ~= nil then
                class = p.parent
            end

			local key = path
			local i = path:match'^.*()%.'
			if i ~= nil then
				key = path:sub(i+1)
				path = path:sub(1,i-1)
			else
				path = ''
			end
            
            if class == nil then class = rom.game[path] end

            local meta = getmetatable(class)
            local metatype = get_metatype(meta)

            --- private or deprecated by default so they can be manually adjusted later
            if #path > 0 then
                if path ~= lastpath then
                    logger('')
                    logger('---@class kcd2def*' .. path .. (metatype ~= nil and ': ' .. metatype or ''))
                end
                lastpath = path
                logger('---@field private ' .. key .. sig)
            else
                logger('')
                logger('---@deprecated')
                logger('---@type' .. sig)
                logger(key .. ' = ...')
            end
            
        end
    end


    --- toggle tracing

    local function enable_aggregate_function_types()
        if hook_set then
            error('aggregate_function_types active, cannot begin')
            return
        end
        
        print("begin - aggregate_function_types")

        -- max depth of 2 to avoid DFS tunneling into super/__index obscuring the root class
        generate_lookup(2)
        aggregate = {}
        hook_set = true
    end

    local function disable_aggregate_function_types()
        if not hook_set then
            error('aggregate_function_types not active, cannot end')
            return
        end

        hook_set = false
        cleanup_lookup()

        process_result(aggregate)
        dump_result(aggregate)

        print("end - aggregate_function_types")
        
        return aggregate
    end

    function tests_enable.meta_aft()
        return enable_aggregate_function_types()
    end

    function tests_disable.meta_aft()
        return disable_aggregate_function_types()
    end
end

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

public.run_test = run_test
public.enable_test = enable_test
public.disable_test = disable_test
public.toggle_test = toggle_test