

local envy = rom.mods['LuaENVY-ENVY']

envy.auto()

local pack = function (...)
    return { n = select('#', ...), ... }
end

local xml = import 'xml2lua.lua'

local handler = function() return import 'tree.lua' end

local load_callbacks = {}

local nil_path = {}

local function handle_xml_data(path,data)
	local callbacks = load_callbacks[path]
	if not callbacks then return data end
	for _,callback in ipairs(callbacks) do
		local newdata = callback(data, path)
		if newdata ~= nil then
			data = newdata
		end
	end
	return data
end

local function handle_xml_content(path,content)
	local data = decode(content)
	data = handle_xml_data(path,data)
	return encode(data)
end

local function normalise(path)
	path = path:lower():gsub('\\','/'):gsub('//','/')
	if path:sub(1,5) == 'data/' then return path:sub(6) end
	return path
end

local function prepare_callbacks(path)
	local callbacks = load_callbacks[path]
	if callbacks then return callbacks end
	
	rom.game_data.on_xml_parse(function(given_path,content)
		given_path = normalise(given_path)
		if path ~= nil_path and given_path ~= path then return content end
		return handle_xml_content(path,content)
	end)
	
	callbacks = {}
	load_callbacks[path] = callbacks
	return callbacks
end

public.decode = function(str)
	local h = handler()
	local p = xml.parser(h)
	p:parse(str)
	return h.root
end
public.encode = function(tbl) return xml.toXml(tbl) end

function public.decode_file(path)
	local file, msg = io.open(path)
	if file == nil then error(msg) end
	local content = file:read('*all')
	file:close()
	return decode(content)
end

function public.encode_file(path,data)
	local content = encode(data)
	rom.path.create_directory(rom.path.get_parent(path))
	local file, msg = io.open(path,'w')
	if file == nil then error(msg) end
	file:write(content)
	file:close()
end

public.hook = function(path,callback)	
	if type(callback) ~= 'function' then
		path, callback = callback, path
	end
	if path == nil then path = nil_path end
	local callbacks = prepare_callbacks(path)
	table.insert(callbacks,callback)
end

local function is_singular(xml_data)
	if xml_data == nil then return true end
	if xml_data[1] == nil then return true end
	return false
end

local function is_multiple(xml_data)
	if xml_data == nil then return true end
	if xml_data[1] ~= nil then return true end
	return false
end

function public.get_entry(xml_data)
	if is_singular(xml_data) then return xml_data end
	local k, entry = next(xml_data)
	return entry, k
end


function public.get_entries(xml_data)
	if is_multiple(xml_data) then return xml_data end
	return { xml_data }
end

function public.get_entry_by_tag(xml_data, tag_name)
	if xml_data == nil then return end
	return get_entry(get_entry(xml_data)[tag_name])
end

function public.get_entries_by_tag(xml_data, tag_name)
	if xml_data == nil then return end
	local entries = get_entries(xml_data)
	local tagged = {}
	for _,entry in pairs(entries) do
		for _,e in pairs(get_entries(entry[tag_name])) do
			table.insert(tagged,e)
		end
	end
	return tagged
end

function public.find_entry_by_attr(xml_data, attr_filter, attr_match)
	if xml_data == nil then return end
	local entries = get_entries(xml_data)
	local filter_type = type(attr_filter)
	for i,entry in pairs(entries) do
		local attr = entry._attr
		if attr then
			if attr_match == nil and filter_type == 'string' then
				if attr[attr_filter] then
					return entry, i
				end
			elseif filter_type == 'string' then
				if attr[attr_filter] == attr_match then
					return entry, i
				end
			else
				if attr_filter(entry._attr) then
					return entry, i
				end
			end
		end
	end
end

function public.find_entries_by_attr(xml_data, attr_filter, attr_match)
	if xml_data == nil then return nil end
	local entries = get_entries(xml_data)
	local found_entries = {}
	local found_indices = {}
	local filter_type = type(attr_filter)
	for i,entry in pairs(entries) do
		local attr = entry._attr
		if attr then
			if attr_match == nil and filter_type == 'string' then
				if attr[attr_filter] then
					table.insert(found_entries, entry)
					table.insert(found_indices, i)
				end
			elseif filter_type == 'string' then
				if attr[attr_filter] == attr_match then
					table.insert(found_entries, entry)
					table.insert(found_indices, i)
				end
			else
				if attr_filter(attr) then
					table.insert(found_entries, entry)
					table.insert(found_indices, i)
				end
			end
		end
	end
	return found_entries, found_indices
end

local helper_meta

local function helper(call, args)
	return setmetatable({_call = call, _args = args}, helper_meta)
end

helper_meta = {
	__call = function(self, ...)
		return self._call(...)
	end;
	__mul = function(self, other)
		return helper(function(data, ...)
			local args = pack(...)
			local take = pack(unpack(args,1,self._args-1))
			local skip = pack(unpack(args,self._args,args.n))
			return self(other(data,unpack(take)),unpack(skip))
		end,self._args)
	end;
	__pow = function(self, other)
		return helper(function(data, ...)
			local args = pack(...)
			local take = pack(unpack(args,1,self._args-1))
			local skip = pack(unpack(args,self._args,args.n))
			return other(self(data,unpack(take)),unpack(skip))
		end,self._args)
	end;
}

function public.helpers()
	return helper(get_entry_by_tag,2), helper(get_entries_by_tag,2), helper(find_entry_by_attr,3), helper(find_entries_by_attr,3)
end

local path_meta

path_meta = {
	__index = function(self,key)
		local path = rawget(self,'_path')
		if path == nil then
			return setmetatable({_path = {key}},path_meta)
		end
		local newpath = {}
		local n = 0
		for i,key in ipairs(path) do
			newpath[i] = key
			n = i
		end
		newpath[n+1] = key
		return setmetatable({_path = newpath},path_meta)
	end;
	__call = function(self)
		return unpack(self._path or {})
	end;
}


public.path = setmetatable({},path_meta)