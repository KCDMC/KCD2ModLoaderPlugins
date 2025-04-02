---@diagnostic disable: lowercase-global

local envy = rom.mods['LuaENVY-ENVY']
local rawpairs = pairs

envy.auto()

key_bindings = {
	trace_metatables_graph = rom.ImGuiKey.F4;
	trace_calls_rate = rom.ImGuiKey.F3;
}

trace_enable = {}
trace_disable = {}

--- common bindings (avoid globals to avoid self-introspection)

---@diagnostic disable-next-line: undefined-global
local rom = rom
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
local gsub = string.gsub
local find = string.find
local sub = string.sub
local pack = function (...)
    return { n = select('#', ...), ... }
end

local nop = function() end

local function tolookup(t)
    local lookup = {}
    for k,v in pairs(t) do
        lookup[v] = k
    end
    return lookup
end

local printer = print

local scriptbind_classes = {}
local scriptbind_instance_hook = nop
local function scriptbind_class_name(name)
	return name
end
local function scriptbind_instance(class_name, instance, class)
	name = scriptbind_class_name(class_name)
	scriptbind_classes[name] = class
	scriptbind_instance_hook(name, instance, class)
end
rom.cryengine.on_lua_userdata_bind(scriptbind_instance)

do -- trace_calls_rate
	local tracer_name = 'trace_calls_rate'

	local reset_period = 1

    local hook_set = false
    local global_lookup

	local lookup_depth = 2
    local lookup_exclude = tolookup{
		_G, env, rom, rom.game;
		string, tostring, select, pairs, pcall, type, getmetatable, gsub, find, sub;
		'_G','__index','__newindex';
	}
	
	local called
	local waiting
	
	local metatables
	local metatables_window
	
	local names
	local global_names
	
	local unknown_meta_prefix = "Unknown Metatable "
	
	local data_path = _PLUGIN.plugins_data_mod_folder_path
	rom.path.create_directory(data_path)
	
	local dump_calls = rom.path.combine(data_path,_PLUGIN.guid .. '.' .. tracer_name .. '.txt')
	
	local file
	
	local function name_or_address(ref)
		local name = names[ref]
		if name ~= nil then return name end
		
		name = global_names[ref]
		if name ~= nil then
			--name = 'global_' .. name
			names[ref] = name
			return name
		end
		
		for k,v in pairs(scriptbind_classes) do
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

		local count = (called[path] or 0) + 1
		called[path] = count
		
		local now = os.time()
		
		local since = waiting[path] or now
		waiting[path] = since
		
		if now - since >= reset_period then
			printer(tracer_name, path, count)
			file:write(path .. '\t' .. count .. '\n')
			file:flush()
			called[path] = 0
			waiting[path] = now
		end

        return func(...)
    end


    --- managing global lookup

    local function cleanup_lookup()
		if file ~= nil then
			file:close()
			file = nil
		end
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
			if t ~= 'userdata' then
				for k,v in rawpairs(value) do
					if type(k) == 'string' and (value ~= rom.game or k:upper() == k) then -- ignore builtins and leaked globals
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

    local function generate_lookup()
		if global_lookup ~= nil then
            cleanup_lookup()
        end
        global_lookup = {}
		
		called = {}
		waiting = {}
		
		metatables = {}
		metatables_window = {}
		
		names = {}
		global_names = {}
		
		for k,v in pairs(rom.game) do
			global_names[v] = k
		end
		
		inner_generate_lookup(lookup_depth,0,nil,nil,nil,rom.game)
		
		file = io.open(dump_calls,'w')
    end
	
	--- update hook

	local function update_hook()
		if not hook_set then return end
		
		hook_set = false
		
		for k,v in pairs(scriptbind_classes) do
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
		
		cleanup_lookup()
    end

    trace_enable[tracer_name] = function()
        return enable_tracing()
    end

    trace_disable[tracer_name] = function()
        return disable_tracing()
    end
end

do -- trace_calls_count
	local tracer_name = 'trace_calls_count'

    local hook_set = false
    local global_lookup

	local lookup_depth = 2
    local lookup_exclude = tolookup{
		_G, env, rom, rom.game;
		string, tostring, select, pairs, pcall, type, getmetatable, gsub, find, sub;
		'_G','__index','__newindex';
	}
	
	local called
	
	local metatables
	local metatables_window
	
	local names
	local global_names
	
	local unknown_meta_prefix = "Unknown Metatable "
	
	local data_path = _PLUGIN.plugins_data_mod_folder_path
	rom.path.create_directory(data_path)
	
	local dump_calls = rom.path.combine(data_path,_PLUGIN.guid .. '.' .. tracer_name .. '.txt')
	
	local file
	
	local function name_or_address(ref)
		local name = names[ref]
		if name ~= nil then return name end
		
		name = global_names[ref]
		if name ~= nil then
			--name = 'global_' .. name
			names[ref] = name
			return name
		end
		
		for k,v in pairs(scriptbind_classes) do
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

		called[path] = (called[path] or 0) + 1

        return func(...)
    end


    --- managing global lookup

    local function cleanup_lookup()
		if file ~= nil then
			file:close()
			file = nil
		end
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
			if t ~= 'userdata' then
				for k,v in rawpairs(value) do
					if type(k) == 'string' and (value ~= rom.game or k:upper() == k) then -- ignore builtins and leaked globals
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

    local function generate_lookup()
		if global_lookup ~= nil then
            cleanup_lookup()
        end
        global_lookup = {}
		
		called = {}
		
		metatables = {}
		metatables_window = {}
		
		names = {}
		global_names = {}
		
		for k,v in pairs(rom.game) do
			global_names[v] = k
		end
		
		inner_generate_lookup(lookup_depth,0,nil,nil,nil,rom.game)
		
		file = io.open(dump_calls,'w')
    end
	
	--- update hook

	local function update_hook()
		if not hook_set then return end
		
		hook_set = false
		
		for k,v in pairs(scriptbind_classes) do
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
		
		for path, count in pairs(called) do
			printer(tracer_name, path, count)
			file:write(path .. '\t' .. count .. '\n')
			file:flush()
		end
		
		cleanup_lookup()
    end

    trace_enable[tracer_name] = function()
        return enable_tracing()
    end

    trace_disable[tracer_name] = function()
        return disable_tracing()
    end
end

do -- trace_calls_once
	local tracer_name = 'trace_calls_once'

    local hook_set = false
    local global_lookup

	local lookup_depth = 2
    local lookup_exclude = tolookup{
		_G, env, rom, rom.game;
		string, tostring, select, pairs, pcall, type, getmetatable, gsub, find, sub;
		'_G','__index','__newindex';
	}
	
	local called
	
	local metatables
	local metatables_window
	
	local names
	local global_names
	
	local unknown_meta_prefix = "Unknown Metatable "
	
	local data_path = _PLUGIN.plugins_data_mod_folder_path
	rom.path.create_directory(data_path)
	
	local dump_calls = rom.path.combine(data_path,_PLUGIN.guid .. '.' .. tracer_name .. '.txt')
	
	local file
	
	local function name_or_address(ref)
		local name = names[ref]
		if name ~= nil then return name end
		
		name = global_names[ref]
		if name ~= nil then
			--name = 'global_' .. name
			names[ref] = name
			return name
		end
		
		for k,v in pairs(scriptbind_classes) do
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

		if not called[path] then
			called[path] = true
			printer(tracer_name, path)
			file:write(path .. '\n')
			file:flush()
		end

        return func(...)
    end


    --- managing global lookup

    local function cleanup_lookup()
		if file ~= nil then
			file:close()
			file = nil
		end
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
			if t ~= 'userdata' then
				for k,v in rawpairs(value) do
					if type(k) == 'string' and (value ~= rom.game or k:upper() == k) then -- ignore builtins and leaked globals
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

    local function generate_lookup()
		if global_lookup ~= nil then
            cleanup_lookup()
        end
        global_lookup = {}
		
		called = {}
		
		metatables = {}
		metatables_window = {}
		
		names = {}
		global_names = {}
		
		for k,v in pairs(rom.game) do
			global_names[v] = k
		end
		
		inner_generate_lookup(lookup_depth,0,nil,nil,nil,rom.game)
		
		file = io.open(dump_calls,'w')
    end
	
	--- update hook

	local function update_hook()
		if not hook_set then return end
		
		hook_set = false
		
		for k,v in pairs(scriptbind_classes) do
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
		
		cleanup_lookup()
    end

    trace_enable[tracer_name] = function()
        return enable_tracing()
    end

    trace_disable[tracer_name] = function()
        return disable_tracing()
    end
end

do -- trace_calls
	local tracer_name = 'trace_calls'

    local hook_set = false
    local global_lookup

	local lookup_depth = 2
    local lookup_exclude = tolookup{
		_G, env, rom, rom.game;
		string, tostring, select, pairs, pcall, type, getmetatable, gsub, find, sub;
		'_G','__index','__newindex';
	}
	
	local metatables
	local metatables_window
	
	local names
	local global_names
	
	local unknown_meta_prefix = "Unknown Metatable "
	
	local data_path = _PLUGIN.plugins_data_mod_folder_path
	rom.path.create_directory(data_path)
	
	local dump_calls = rom.path.combine(data_path,_PLUGIN.guid .. '.' .. tracer_name .. '.txt')
	
	local file
	
	local function name_or_address(ref)
		local name = names[ref]
		if name ~= nil then return name end
		
		name = global_names[ref]
		if name ~= nil then
			--name = 'global_' .. name
			names[ref] = name
			return name
		end
		
		for k,v in pairs(scriptbind_classes) do
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

		printer(tracer_name, path)
		file:write(path .. '\n')
		file:flush()

        return func(...)
    end


    --- managing global lookup

    local function cleanup_lookup()
		if file ~= nil then
			file:close()
			file = nil
		end
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
			if t ~= 'userdata' then
				for k,v in rawpairs(value) do
					if type(k) == 'string' and (value ~= rom.game or k:upper() == k) then -- ignore builtins and leaked globals
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

    local function generate_lookup()
		if global_lookup ~= nil then
            cleanup_lookup()
        end
        global_lookup = {}
		
		metatables = {}
		metatables_window = {}
		
		names = {}
		global_names = {}
		
		for k,v in pairs(rom.game) do
			global_names[v] = k
		end
		
		inner_generate_lookup(lookup_depth,0,nil,nil,nil,rom.game)
		
		file = io.open(dump_calls,'w')
    end
	
	--- update hook

	local function update_hook()
		if not hook_set then return end
		
		hook_set = false
		
		for k,v in pairs(scriptbind_classes) do
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
		
		cleanup_lookup()
    end

    trace_enable[tracer_name] = function()
        return enable_tracing()
    end

    trace_disable[tracer_name] = function()
        return disable_tracing()
    end
end

do -- trace_metamethod_calls_once
	local tracer_name = 'trace_metamethod_calls_once'

    local hook_set = false
    local global_lookup

	local lookup_depth = 2
    local lookup_exclude = tolookup{
		_G, env, rom, rom.game;
		string, tostring, select, pairs, pcall, type, getmetatable, gsub, find, sub;
	}
	
	local called
	
	local metatables
	local metatables_window
	
	local names
	local global_names
	
	local unknown_meta_prefix = "Unknown Metatable "
	
	local data_path = _PLUGIN.plugins_data_mod_folder_path
	rom.path.create_directory(data_path)
	
	local dump_calls = rom.path.combine(data_path,_PLUGIN.guid .. '.' .. tracer_name .. '.txt')
	
	local file
	
	local function name_or_address(ref)
		local name = names[ref]
		if name ~= nil then return name end
		
		name = global_names[ref]
		if name ~= nil then
			--name = 'global_' .. name
			names[ref] = name
			return name
		end
		
		for k,v in pairs(scriptbind_classes) do
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

		if not called[path] then
			called[path] = true
			printer(tracer_name, path)
			file:write(path .. '\n')
			file:flush()
		end

        return func(...)
    end


    --- managing global lookup

    local function cleanup_lookup()
		if file ~= nil then
			file:close()
			file = nil
		end
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
			if t ~= 'userdata' then
				for k,v in rawpairs(value) do
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
		
		called = {}
		
		metatables = {}
		metatables_window = {}
		
		names = {}
		global_names = {}
		
		for k,v in pairs(rom.game) do
			global_names[v] = k
		end
		
		file = io.open(dump_calls,'w')
    end
	
	--- update hook

	local function update_hook()
		if not hook_set then return end
		
		hook_set = false
		
		for k,v in pairs(scriptbind_classes) do
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
		
		cleanup_lookup()
    end

    trace_enable[tracer_name] = function()
        return enable_tracing()
    end

    trace_disable[tracer_name] = function()
        return disable_tracing()
    end
end

do -- trace_metamethod_calls
	local tracer_name = 'trace_metamethod_calls'

    local hook_set = false
    local global_lookup

	local lookup_depth = 2
    local lookup_exclude = tolookup{
		_G, env, rom, rom.game;
		string, tostring, select, pairs, pcall, type, getmetatable, gsub, find, sub;
	}
	
	
	local metatables
	local metatables_window
	
	local names
	local global_names
	
	local unknown_meta_prefix = "Unknown Metatable "
	
	local data_path = _PLUGIN.plugins_data_mod_folder_path
	rom.path.create_directory(data_path)
	
	local dump_calls = rom.path.combine(data_path,_PLUGIN.guid .. '.' .. tracer_name .. '.txt')
	
	local file
	
	local function name_or_address(ref)
		local name = names[ref]
		if name ~= nil then return name end
		
		name = global_names[ref]
		if name ~= nil then
			--name = 'global_' .. name
			names[ref] = name
			return name
		end
		
		for k,v in pairs(scriptbind_classes) do
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

		printer(tracer_name, path)
		file:write(path .. '\n')
		file:flush()

        return func(...)
    end


    --- managing global lookup

    local function cleanup_lookup()
		if file ~= nil then
			file:close()
			file = nil
		end
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
			if t ~= 'userdata' then
				for k,v in rawpairs(value) do
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
		
		metatables = {}
		metatables_window = {}
		
		names = {}
		global_names = {}
		
		for k,v in pairs(rom.game) do
			global_names[v] = k
		end
		
		file = io.open(dump_calls,'w')
    end
	
	--- update hook

	local function update_hook()
		if not hook_set then return end
		
		hook_set = false
		
		for k,v in pairs(scriptbind_classes) do
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
		
		cleanup_lookup()
    end

    trace_enable[tracer_name] = function()
        return enable_tracing()
    end

    trace_disable[tracer_name] = function()
        return disable_tracing()
    end
end

do -- trace_metatables_graph
	local tracer_name = 'trace_metatables_graph'

    local hook_set = false
    local global_lookup

	local lookup_depth = 2
    local lookup_exclude = tolookup{
		_G, env, rom, rom.game;
		string, tostring, select, pairs, pcall, type, getmetatable, gsub, find, sub;
	}
	
	local graph
	local stack
	
	local metatables
	local metatables_window
	
	local names
	local global_names
	
	local unknown_meta_prefix = "Unknown Metatable "
	
	local data_path = _PLUGIN.plugins_data_mod_folder_path
	rom.path.create_directory(data_path)
	
	local dump_graph = rom.path.combine(data_path,_PLUGIN.guid .. '.' .. tracer_name .. '.txt')
	
	local function inspect() return rom.game.inspect or function() end end
	
	local function name_or_address(ref)
		local name = names[ref]
		if name ~= nil then return name end
		
		name = global_names[ref]
		if name ~= nil then
			--name = 'global_' .. name
			names[ref] = name
			return name
		end
		
		for k,v in pairs(scriptbind_classes) do
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
	
	local function connect(a,b,r)
		if a == b then return false end
		if global_names[b] then return false end
		local da = graph[a] or {}
		graph[a] = da
		if da[b] then return false end
		da[b] = r or true
		return true
	end
	
	local function connect_list(node,list,reason)
		local n = #list
		for i = 1, n, 1 do
			local v = list[i]
			local m = getmetatable(v)
			if type(v) ~= 'string' and m then
				connect(node,m,reason)
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

		local path = p.path
		local parent = p.parent
		local key = p.key

		local q = stack[#stack]
		
		if q then
			connect(q.parent,parent,q.key .. ' > ' .. key)
		end
		
		table.insert(stack,p)

		local args = pack(...)

		connect_list(parent,args,key)

        local rets = pack(func(...))

		connect_list(parent,rets,'= ' .. key)

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
				connect(value, meta, '^')
			end
			if t ~= 'userdata' then
				for k,v in rawpairs(value) do
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
		
		for k,v in pairs(scriptbind_classes) do
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
			local file = io.open(dump_graph,'w')
			file:write(content)
			file:close()
		end
		
		cleanup_lookup()
    end

    trace_enable[tracer_name] = function()
        return enable_tracing()
    end

    trace_disable[tracer_name] = function()
        return disable_tracing()
    end
end

do -- trace_UIAction
	local tracer_name = 'trace_UIAction'
	
	local listener = { listen = function(self, ...)
		printer(tracer_name, ...)
	end }
	
	trace_enable[tracer_name] = function()
		--rom.game.UIAction.RegisterElementListener( listener, "", -1, "", "listen" )
		--rom.game.UIAction.RegisterActionListener( listener, "", "", "listen" )
		rom.game.UIAction.RegisterEventSystemListener( listener, "", "", "listen" )
	end
	
	trace_disable[tracer_name] = function()
		--rom.game.UIAction.UnregisterElementListener( listener, "listen" )
		--rom.game.UIAction.UnregisterActionListener( listener, "listen" )
		rom.game.UIAction.UnregisterEventSystemListener( listener, "listen" )
	end
	
end

do -- trace_setter
	local tracer_name = 'trace_setter'

	local __G
	local meta

	trace_enable[tracer_name] = function()
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
			printer(tracer_name, k,v)
		end } )
	end
	
	trace_disable[tracer_name] = function()
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

--- end tracers

trace_active = trace_active or {}

local function enable_tracing(name)
	local tracer = trace_enable[name]
	trace_active[name] = true
	printer('trace enable:',name)
	return tracer()
end

local function disable_tracing(name)
	local tracer = trace_disable[name]
	trace_active[name] = false
	tracer()
	printer('trace disable:',name)
end

local function toggle_tracing(name)
	if trace_active[name] then
		return disable_tracing(name)
	else
		return enable_tracing(name)
	end
end

rom.gui.add_always_draw_imgui(function()
	for k,v in pairs(key_bindings) do
		if rom.ImGui.IsKeyPressed(v) then
			toggle_tracing(k)
		end
	end
end)

rom.gui.add_to_menu_bar(function()
	for k in pairs(trace_enable) do
		local _, clicked = rom.ImGui.Checkbox(k, trace_active[k] or false)
		if clicked then
			toggle_tracing(k)
		end
	end
end)

local tracers = {}
for k in pairs(trace_enable) do
	tracers[k] = 'switch'
end

public.tracers = tracers
public.enable_tracing = enable_tracing
public.disable_tracing = disable_tracing
public.toggle_tracing = toggle_tracing