---@meta _
---@diagnostic disable

local envy = rom.mods['LuaENVY-ENVY']
local _G = _globals or envy.globals or _G
envy.auto()
_globals = _globals or _G

local public = public or getfenv(1)

local function pack(...)
	return { n = select('#', ...), ... }
end

local load = loadstring

local raw_pairs = pairs
local pairs = function(t)
    local metatable = getmetatable(t)
    if metatable and metatable.__pairs then
        return metatable.__pairs(t)
    end
    return raw_pairs(t)
end

local raw_ipairs = ipairs
local ipairs = function(t)
    local metatable = getmetatable(t)
    if metatable and metatable.__ipairs then
        return metatable.__ipairs(t)
    end
    return raw_ipairs(t)
end

function public.perform_lookup(t,s,f)
	for k,v in pairs(t) do
		if f ~= nil then v = f(v) end
		if v == s then return k end
	end
	return nil
end

function public.perform_index(t,s,f)
	for k,v in ipairs(t) do
		if f ~= nil then v = f(v) end
		if v == s then return k end
	end
	return nil
end

function public.build_lookup(t,f)
	local l = {}
	for k,v in pairs(t) do
		if f ~= nil then v = f(v) end
		if v ~= nil then l[v] = k end
	end
	return l
end

function public.build_index(t,f)
	local l = {}
	for k,v in ipairs(t) do
		if f ~= nil then v = f(v) end
		if v ~= nil then l[v] = k end
	end
	return l
end

function public.clear(...)
	for _,t in public.vararg(...) do
		for k in pairs(t) do
			t[k] = nil
		end
	end
end

function public.iclear(...)
	local n = 0
	for _,t in public.vararg(...) do
		local l = #t
		if l > n then n = l end
	end
	if n == 0 then return end
	for _,t in public.vararg(...) do
		for i = 1, n do
			t[i] = nil
		end
	end
end

function public.merge(m,...)
	for _,t in public.vararg(...) do
		for k,v in pairs(t) do
			m[k] = v
		end
	end
	return m
end

--http://lua-users.org/wiki/VarargTheSecondClassCitizen
do
	function public.vararg(...)
		local i, t, l = 0, {}, nil
		local function iter()
			i = i + 1
			if i > l then return end
			return i, t[i]
		end

		--i = 0
		l = select("#", ...)
		for n = 1, l do
			t[n] = select(n, ...)
		end
		--[[
		for n = l+1, #t do
			t[n] = nil
		end
		--]]
		return iter
	end
end

local _type = type
local _getmeta = debug.getmetatable

function public.type(v)
	local t = _type(v)
	local m = _getmeta(v)
	if m then
		return t, m.__name
	end
	return t
end

local function endow_with_pairs_and_next(meta)
	--[[
	context behind this approach:
		sol objects are userdata or tables that have sol classes as metatables
		sol object attributes are functions in their sol class as the same field
		sol class __index function fallsback to itself so objects inherit class members
		sol __index generates a new 'new' function whenever it is requested
		sol classes have stub __pairs that just errors when called
		sol overrides next to error when that is used on a sol class
	--]]
	if not meta then return end
	local status, _next
	--if rawget(meta,'__pairs') or rawget(meta,'__next') then
	--	status, _next = false--pcall(pairs,object)
	--end
	if not status then
		local _index = rawget(meta,'__index')
		if not _index then return end
		if type(_index) ~= 'function' then
			function _next(s,k)
				return next(_index,k)
			end
		else
			function _next(s,k)
				local v,u,w
				while v == nil do
					k,u = next(meta,k)
					if k == nil then return nil end
					-- ignore 'new' and metatable fields
					if k ~= 'new' and k:sub(1,2) ~= '__' then
						w = s[k]
						-- if the object reports a value different to the class
						if u ~= w then
							-- assume it's actually that object's attribute
							v = w
						end
					end
				end
				return k,v
			end
		end
		rawset(meta,'__pairs',function(s,k)
			return _next,s,k
		end)
	end
	-- __next is implemented by a custom implementation of next
	local status = false--pcall(next,object)
	if not status and _next ~= nil and rawget(meta,'__next') == nil then
		rawset(meta,'__next',_next)
	end
end

---@type function?
local imgui_next_delayed_load = function()

	local imgui_style = rom.ImGui.GetStyle() -- sol.h2m.ImGuiStyle*
	local imgui_vector = imgui_style["WindowPadding"] -- sol.ImVec2*
	endow_with_pairs_and_next(getmetatable(imgui_style))
	endow_with_pairs_and_next(getmetatable(imgui_vector))
	endow_with_pairs_and_next(getmetatable(rom.ImGuiKey))
	endow_with_pairs_and_next(getmetatable(rom.ImGuiKeyMod))
	
	local imgui_vector_meta = getmetatable(imgui_vector)
	local imgui_stylevar_lookup = public.build_lookup(rom.ImGuiStyleVar)
	imgui_stylevar_lookup[rom.ImGuiStyleVar.COUNT] = nil

	function public.GetStyleVar(var)
		if type(var) == "number" then
			var = imgui_stylevar_lookup[var]
		end
		local s = rom.ImGui.GetStyle()[var]
		if getmetatable(s) ~= imgui_vector_meta then return s end
		return s['x'],s['y']
	end
end

local pushLoad = function()
	if imgui_next_delayed_load and imgui_next_delayed_load() ~= true then
		imgui_next_delayed_load = nil
	end
end

rom.gui.add_always_draw_imgui( pushLoad )

local function reverse_color(color)
	color[1], color[4] = color[4], color[1]
	color[2], color[3] = color[3], color[2]
	return color
end

local color_FF = 1 -- 0xFF
local color_20 = 32/255 -- 0x20
local color_EE = 238/255 -- 0xEE
local color_CC = 204/255 -- 0xCC

local ob = {}
public.browser = ob

local colors = {
	tree = reverse_color{color_FF,color_FF,color_20,color_FF},
	leaf = reverse_color{color_FF,color_FF,color_FF,color_20},
	info = reverse_color{color_FF,color_20,color_FF,color_FF},
	fake = reverse_color{color_EE,color_CC,color_CC,color_CC},
	null = reverse_color{color_FF,color_20,color_20,color_FF},
}

ob.root = {
	mods = rom.mods,
	lua = _globals,
	game = rom.game or _globals,
	colors = colors,
	helpers = {getmetatable = debug.getmetatable},
}

local filter_modes_browser = {
	"tree",
	"info"
}

local filter_modes_details = {
	"leaf",
	"info"
}

local function filter_match(text,filter)
	return text:match(filter)
end

local browsers = {}
local details = {}
local unfolded = {}
local last_pos = {0,0}
local last_size = {0,0}

local function create_browser(entry,x,y,w,h)
	local id = #browsers + 1
	unfolded[id..'|root'] = true
	browsers[id] = public.merge({
		index = id,
		filter_text = '',
		filter = '',
		texts = {},
		tooltips = {},
		init_pos = pack(x,y),
		init_size = pack(w,h),
		mode = 1
	},entry)
end

local function create_details(entry,x,y,w,h)
	local id = #details + 1
	details[id] = public.merge({
		index = id,
		filter_text = '',
		filter = '',
		texts = {},
		tooltips = {},
		init_pos = pack(x,y),
		init_size = pack(w,h),
		mode = 1
	},entry)
end

local function root_entries()
	return { data = ob.root, iter = pairs, chain = {}, funcs = {},
		path = 'root', name = 'root', show = 'root', text = 'root'}
end

function ob.root.helpers.to_hex(i)
	if type(i) ~= 'number' then
		i = 255*255*255*255*i[1] + 255*255*255*i[2] + 255*255*i[3] + 255*i[4]
	end
	return '0x' .. string.format("%x", i):upper()
end

local excludedFieldNames = public.build_lookup{ 
	"and", "break", "do", "else", "elseif", "end",
	"false", "for", "function", "if", "in", "local",
	"nil", "not", "or", "repeat", "return", "then",
	"true", "until", "while", "goto", "repeat", "until"
}

local calculate_text_sizes
do
	local calculate_text_sizes_x_buffer = {}
	function calculate_text_sizes(...)
		-- don't need to clear the buffer since 
		-- we only iterate over the region we overwrite
		local frame_padding_x, frame_padding_y = public.GetStyleVar(rom.ImGuiStyleVar.FramePadding)
		local frame_padding_x_2 = 2*frame_padding_x
		local frame_padding_y_2 = 2*frame_padding_y
		local my = 0 -- maximum y value in this row
		local sx = 0 -- sum of x values in this row
		local n -- number of items in this row
		for i,t in public.vararg(...) do
			n = i
			local x,y = rom.ImGui.CalcTextSize(t)
			x = x + frame_padding_x_2
			y = y + frame_padding_y_2
			calculate_text_sizes_x_buffer[i] = x
			sx = sx + x
			if y > my then my = y end
		end
		return n, my, sx, unpack(calculate_text_sizes_x_buffer, 1, n)
	end
end

local function tostring_literal(value)
	if type(value) == "string" then
		local lined, _lined = 0, value:gmatch("\n")
		for _ in _lined do lined = lined + 1 end
		local dquoted, _dquoted = 0, value:gmatch([=["]=])
		for _ in _dquoted do dquoted = dquoted + 1 end
		local squoted, _squoted = 0, value:gmatch([=[']=])
		for _ in _squoted do squoted = squoted + 1 end
		local edquoted, _edquoted = 0, value:gmatch([=[\"]=])
		if lined > 0 or (dquoted > 0 and squoted > 0) then
			local special, _special = 0, value:gmatch([=[[=]]=])
			for _ in _special do special = special + 1 end
			local eq = "="
			for i = 1, special do
				eq = eq .. '='
			end
			return '['..eq..'[' .. value .. ']'..eq..']'
		elseif squoted > 0 then
			return '"' .. value .. '"'
		else
			return "'" .. value .. "'"
		end
	end
	return tostring(value)
end

local function tostring_vararg(...)
	local s = ""
	for _,v in public.vararg(...) do
		v = tostring_literal(v)
		s = s .. '\t' .. v
	end
	return s:sub(2,#s)
end

local function path_part_key(key)
	if type(key) == "string" then
		if excludedFieldNames[key] or not key:match("^[_%a][_%w]*$") then
			return '[' .. tostring_literal(key) .. ']' 
		end
		return '.' .. key
	end
	if type(key) == "number" then
		return '[' .. key .. ']' 
	end
end

local function path_part(ed,path)
	path = (path or '')
	if ed.name and not ed.flat then
		path = path .. path_part_key(ed.name)
	end
	if ed.keys then
		for _, key in ipairs(ed.keys) do
			if type(key) == "table" then
				-- build new path for a function to wrap over it
				local wrap = nil
				for _, k in ipairs(key) do
					if wrap then
						local part = path_part_key(k)
						if part == nil then part = "[?]" end
						wrap = wrap .. part
					else
						wrap = k
					end
				end
				path = wrap .. '(' .. path .. ')'
			else
				-- extend current path
				local part = path_part_key(key)
				if part == nil then return "<" .. ed.show or '???' .. ">" end
				path = path .. part
			end
		end
	end
	return path
end

local entrify
do
	-- to avoid making these many times
	local keys_hex = {{'root','helpers','to_hex'}}
	local keys_meta = {{'root','helpers','getmetatable'}}

	local extra = {}
	
	function entrify(name,data,base)
		public.clear(extra)
		local data_type, sol_type = public.type(data)
		local type_name = sol_type or data_type
		local iter = nil
		local keys = nil
		local info = nil
		local func = nil

		if base ~= nil and base.meta == nil then
			local meta = getmetatable(base.data)
			base.meta = meta
			if meta ~= nil then
				table.insert(extra,{
					func = ob.root.helpers.getmetatable,
					base = base.base,
					name = base.name,
					fake = ".",
					flat = true,
					show = "meta",
					keys = keys_meta,
					iter = pairs,
				})
			end
		end

		if base ~= nil and base.type and (data_type == "number" or data_type == "nil") then
			if base.base and base.name == "colors" and base.base.name == "root" then
				table.insert(extra,{
					func = ob.root.helpers.to_hex,
					base = base,
					name = name,
					show = "hex",
					keys = keys_hex,
				})
			end
		elseif data_type == "table" then
			if base.base and base.name == "colors" and base.base.name == "root" then
				table.insert(extra,{
					func = ob.root.helpers.to_hex,
					base = base,
					name = name,
					show = "hex",
					keys = keys_hex,
				})
			end
			iter = pairs
		elseif sol_type then
			if sol_type:match("Im") then
				iter = pairs
			elseif tostring(data):match('unordered_map') then
				iter = pairs
			elseif tostring(data):match('<') then -- span or container
				iter = ipairs
			end
		end

		local ed = { 
			fake = false,
			info = info,
			base = base,
			func = func,
			name = name,
			keys = keys,
			iter = iter
		}

		if func == nil then ed.data = data end
		for _,sd in ipairs(extra) do
			sd.fake = sd.fake or true
			if not sd.base then sd.base = ed end
		end
		return ed, unpack(extra)
	end
end

local function resolve(ed)
	local func = ed.func
	local base = ed.base
	if func then
		if base.iter then
			local data = base.data[ed.name]
			if data then
				ed.data = func(data)
			end
		else
			ed.data = func(base.data)
		end
	elseif base and base.iter then
		ed.data = base and base.data[ed.name]
	end
	return ed
end

local function refresh(ed)
	if ed == nil then return ed end
	if ed.entries == nil then return ed end
	--for _,ed in ipairs(ed.entries) do
	--	refresh(ed)
	--end
	ed.entries = nil
	return ed
end

--[[
local path_cache = setmetatable({},{__mode='v'})
--]]

local unfold
do
	local function type_name(o,t)
		if t == nil then return nil end
		if t:match('unordered_map') then
			return 'map'
		end
		if t:match('span') then
			return 'span'
		end
		if t:match('vector') then
			return 'vector'
		end
		if t:match('container') then
			return 'container'
		end
		return t
	end

	local function _len(t)
		return #t
	end
	
	local function len(t)
		local s,v = pcall(_len,t)
		if s then return math.floor(v) end
	end

	function unfold(ed)
		if ed.entries then return ed.entries end
		ed.path = ed.path or path_part(ed)
		--path_cache[ed.path] = ed
		ed.meta = nil
		local data = ed.data
		if ed.data == nil then data = resolve(ed).data end
		local iter = ed.iter
		local entries = {}
		if iter ~= nil and data ~= nil then
			local order = {}
			for k in iter(data) do
				table.insert(order,k)
			end
			table.sort(order, function(a,b) return tostring(a) < tostring(b) end)
			for _,k in ipairs(order) do
				local v = data[k]
				for _,sd in public.vararg(entrify(k,v,ed)) do
					if sd ~= nil then
						table.insert(entries,sd)
					end
				end
			end
		end
		for i,sd in ipairs(entries) do
			sd.index = i
			sd.path = path_part(sd,ed.path)
			--sd.chain = mod.merge({},ed.chain)
			--table.insert(sd.chain,sd.name)
			--sd.funcs = mod.merge({},ed.funcs)
			--if sd.func then
			--	sd.funcs[#sd.chain] = sd.func
			--end
			local data = sd.data
			if data == nil then data = resolve(sd).data end
			local ta,tb = public.type(data)
			sd.type = sd.type or type_name(data,tb) or ta 
			sd.info = sd.info or sd.type
			local size = len(data)
			if size then
				sd.size = size
				sd.info = sd.info .. '[' .. size .. ']'
			end
			if not sd.show then sd.show = tostring(sd.name) end
			sd.text = sd.info and sd.show .. '|' .. sd.info or sd.show
			if sd.fake then
				local base = sd.base
				local info = base.info
				sd.text = sd.text .. '|' .. (info and (base.show .. '|' .. info) or base.show)
			end
		end
		ed.entries = entries
		return entries
	end
end

local function resolve_vararg_simple(...)
	local ed = browsers[1]
	for _,k in public.vararg(...) do
		for j, sd in ipairs(unfold(ed)) do
			if sd.name == k or sd.func == k then
				ed = sd
				break
			end
		end
	end
	return ed
end

--[[

function resolve_vararg(...)
	local ed = browsers[1]
	for _,k in mod.vararg(...) do
		for j, sd in ipairs(unfold(ed)) do
			if sd.name == k then
				ed = sd
				break
			end
		end
	end
	return ed
end

function resolve_chain_funcs(chain, funcs)
	local ed = browsers[1]
	for i,k in ipairs(chain) do
		local func
		if funcs then func = funcs[i] end
		for j, sd in ipairs(unfold(ed)) do
			if sd.name == k and sd.func == func then
				ed = sd
				break
			end
		end
	end
	return ed
end

function resolve_path(path)
	local ed = path_cache[path]
	if ed ~= nil then return ed end
	-- TODO: resolve the path using grammar:
	-- PATH = FUNC(PATH), PATH[KEY], PATH.FIELD, root
	-- FUNC = FUNC[KEY], FUNC.FIELD, root
	-- KEY = .*
	-- FIELD = %w+
	-- only works for valid paths that don't use table, userdata, function or thread as keys
	-- as such, disqualify a path if it contains PATH<.+?: [A-F0-9]+>
	local ed = browsers[1]
	for _,k in path:gmatch('%.(.+?)') do
		for j, sd in ipairs(unfold(ed)) do
			if sd.name == k then
				ed = sd
				break
			end
		end
	end
	return ed
end

--]]

local render_details
local render_browser
do
	local script_prefix = "gml_Script_"
	local script_prefix_index = #script_prefix+1

	local function peval(text)
		local func = load("return " .. text)
		if not func then return nil end
		envy.setfenv(func,_G)
		local ret = pack(pcall(func))
		if ret.n <= 1 then return end
		if not ret[1] then return end
		return unpack(ret,2,ret.n)
	end

	local function try_tooltip(dd,sd,value_part) 
		if rom.ImGui.IsItemHovered() then
			local message
			if value_part then
				-- interpret the value here
			end
			if message ~= nil then 
				rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, unpack(colors.fake))
				rom.ImGui.SetTooltip(message);
				rom.ImGui.PopStyleColor()
			end
		end
	end

	function render_details(dd)
		local entries = unfold(dd)
		if entries then
			local filter = dd.filter
			local skipped = false
			for _,sd in ipairs(entries) do
				if #filter ~= 0 and not filter_match(sd.text,filter) then
					skipped = true
				else
					local id = dd.index .. '|' .. sd.path
					if sd.iter then
						if dd.mode ~= 1 then
							-- iterable
							rom.ImGui.PushStyleColor(rom.ImGuiCol.HeaderHovered,0,0,0,0)
							rom.ImGui.PushStyleColor(rom.ImGuiCol.HeaderActive,0,0,0,0)
							rom.ImGui.Selectable("##Select" .. id, false)
							rom.ImGui.PopStyleColor()
							rom.ImGui.PopStyleColor()
							if rom.ImGui.IsItemHovered() then
								if rom.ImGui.IsItemClicked(rom.ImGuiMouseButton.Middle) then
									local x,y = rom.ImGui.GetWindowPos()
									local w,h = rom.ImGui.GetWindowSize()
									create_browser(sd,x+w,y,w,h)
								end
								if rom.ImGui.IsItemClicked(rom.ImGuiMouseButton.Right) then
									local x,y = rom.ImGui.GetWindowPos()
									local w,h = rom.ImGui.GetWindowSize()
									create_details(sd,x+w,y,w,h)
								end
							end
							if sd.fake then
								rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, unpack(colors.fake))
								rom.ImGui.SameLine()
								rom.ImGui.Text(type(sd.fake) == 'string' and sd.fake or sd.name)
								rom.ImGui.PopStyleColor()
							end
							rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, unpack(colors.tree))
							rom.ImGui.SameLine()
							rom.ImGui.Text(sd.show)
							rom.ImGui.PopStyleColor()
							try_tooltip(dd,sd,false)
							rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, unpack(colors.info))
							rom.ImGui.SameLine()
							rom.ImGui.Text(sd.info)
							rom.ImGui.PopStyleColor()
							try_tooltip(dd,sd,true)
						end
					else
						-- not iterable
						rom.ImGui.Text("")
						if sd.fake then
							rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, unpack(colors.fake))
							rom.ImGui.SameLine()
							rom.ImGui.Text(type(sd.fake) == 'string' and sd.fake or sd.name)
							rom.ImGui.PopStyleColor()
						end
						rom.ImGui.SameLine()
						rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, unpack(colors.leaf))
						rom.ImGui.Text(sd.show)
						rom.ImGui.PopStyleColor()
						try_tooltip(dd,sd,false)
						if sd.type ~= "function" and sd.type ~= "thread" then
							rom.ImGui.SameLine()
							rom.ImGui.PushStyleVar(rom.ImGuiStyleVar.FramePadding, 0, 0)
							rom.ImGui.PushStyleColor(rom.ImGuiCol.FrameBg, 0,0,0,0)
							rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, unpack(colors.info))
							rom.ImGui.PushItemWidth(rom.ImGui.GetContentRegionAvail() - rom.ImGui.CalcTextSize('|'))
							local text, enter_pressed = rom.ImGui.InputText("##Text" .. id, dd.texts[id] or tostring_literal(sd.data), 65535, sd.fake and rom.ImGuiInputTextFlags.ReadOnly or rom.ImGuiInputTextFlags.EnterReturnsTrue)
							rom.ImGui.PopItemWidth()
							rom.ImGui.PopStyleColor()
							rom.ImGui.PopStyleColor()
							rom.ImGui.PopStyleVar()
							try_tooltip(dd,sd,true)
							if enter_pressed then
								dd.data[sd.name] = peval(text)
								dd.texts[id] = nil
								refresh(dd)
							elseif text == "" then 
								dd.texts[id] = nil
							else
								dd.texts[id] = text
							end
						else
							rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, unpack(colors.null))
							rom.ImGui.SameLine()
							rom.ImGui.Text(tostring(sd.data))
							rom.ImGui.PopStyleColor()
							if sd.type == "function" then
								rom.ImGui.SameLine()
								rom.ImGui.PushStyleVar(rom.ImGuiStyleVar.FramePadding, 0, 0)
								rom.ImGui.PushStyleColor(rom.ImGuiCol.FrameBg, 0,0,0,0)
								rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, unpack(colors.info))
								rom.ImGui.Text("(")
								rom.ImGui.SameLine()
								rom.ImGui.PushItemWidth(rom.ImGui.GetContentRegionAvail() - rom.ImGui.CalcTextSize('(|)'))
								local text, enter_pressed = rom.ImGui.InputText("##Text" .. id, dd.texts[id] or '', 65535, rom.ImGuiInputTextFlags.EnterReturnsTrue)
								local tooltip = dd.tooltips[id]
								if tooltip and rom.ImGui.IsItemHovered() then
									rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, unpack(tooltip.color))
									rom.ImGui.SetTooltip(tooltip.message);
									rom.ImGui.PopStyleColor()
								end
								rom.ImGui.PopItemWidth()
								rom.ImGui.SameLine()
								rom.ImGui.Text(")")
								rom.ImGui.PopStyleColor()
								rom.ImGui.PopStyleColor()
								rom.ImGui.PopStyleVar()
								if enter_pressed then
									local result = pack(pcall(sd.data, peval(text)))
									if result.n > 1 then
										local color, message
										if result[1] then
											color = colors.leaf
											message = tostring_vararg(unpack(result, 2, result.n))
										else 
											color = colors.null
											message = result[2]
										end
										dd.tooltips[id] = { message = message, color = color }
									end
									dd.texts[id] = nil
								else
									dd.texts[id] = text
								end
								if dd.data and sd.show == "call" then
									local params = dd.data.params
									if params == nil then
										local name = dd.data.name
										if name == nil then
											local script_name = dd.data.script_name
											if script_name ~= nil then
												name = script_name:sub(script_prefix_index)
											end
										end
									end
									if params ~= nil then
										rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, unpack(colors.fake))
										rom.ImGui.Text("")
										rom.ImGui.SameLine()
										rom.ImGui.Text("")
										rom.ImGui.SameLine()
										rom.ImGui.Text("params:")
										for _,p in ipairs(params) do
											rom.ImGui.SameLine()
											rom.ImGui.Text(p.name)
											if p.value and rom.ImGui.IsItemHovered() then
												rom.ImGui.SetTooltip(p.value);
											end
										end
										rom.ImGui.PopStyleColor()
									end
								end
							end
						end
					end
				end
			end
			if skipped then
				rom.ImGui.Text("")
				rom.ImGui.SameLine()
				rom.ImGui.Text("...")
			end
		end
	end

	function render_browser(bd,ed)
		local ids = bd.index .. '|' .. ed.path
		local show = ed.path ~= "root"
		local _unfolded = unfolded[ids] == true
		if show then
			if ed.iter then
				-- iterable
				rom.ImGui.PushStyleColor(rom.ImGuiCol.HeaderHovered,0,0,0,0)
				rom.ImGui.PushStyleColor(rom.ImGuiCol.HeaderActive,0,0,0,0)
				rom.ImGui.Selectable("##Select" .. ids, false)
				rom.ImGui.PopStyleColor()
				rom.ImGui.PopStyleColor()
				if rom.ImGui.IsItemHovered() then
					if rom.ImGui.IsItemHovered() and rom.ImGui.IsItemClicked(rom.ImGuiMouseButton.Left) then
						_unfolded = not _unfolded
					end
					if rom.ImGui.IsItemClicked(rom.ImGuiMouseButton.Middle) then
						local x,y = rom.ImGui.GetWindowPos()
						local w,h = rom.ImGui.GetWindowSize()
						create_browser(ed,x+w,y,w,h)
					end
					if rom.ImGui.IsItemClicked(rom.ImGuiMouseButton.Right) then
						local x,y = rom.ImGui.GetWindowPos()
						local w,h = rom.ImGui.GetWindowSize()
						create_details(ed,x+w,y,w,h)
					end
				end
				unfolded[ids] = _unfolded
				rom.ImGui.SetNextItemOpen(_unfolded)
				rom.ImGui.SameLine()
				rom.ImGui.TreeNode("##Node" .. ids)
				if ed.fake then
					rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, unpack(colors.fake))
					rom.ImGui.SameLine()
					rom.ImGui.Text(type(ed.fake) == 'string' and ed.fake or ed.name)
					rom.ImGui.PopStyleColor()
				end
				rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, unpack(colors.tree))
				rom.ImGui.SameLine()
				rom.ImGui.Text(ed.show)
				rom.ImGui.PopStyleColor()
				if ed.info ~= nil then
					rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, unpack(colors.info))
					rom.ImGui.SameLine()
					rom.ImGui.Text(ed.info)
					rom.ImGui.PopStyleColor()
				end
			else
				-- not iterable
				rom.ImGui.Text("\t")
				rom.ImGui.SameLine()
				rom.ImGui.Text("")
				if ed.fake then
					rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, unpack(colors.fake))
					rom.ImGui.SameLine()
					rom.ImGui.Text(type(ed.fake) == 'string' and ed.fake or ed.name)
					rom.ImGui.PopStyleColor()
				end
				rom.ImGui.SameLine()
				rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, unpack(colors.leaf))
				rom.ImGui.Text(ed.show)
				rom.ImGui.PopStyleColor()
				if ed.type ~= "function" and ed.type ~= "thread" then
					rom.ImGui.SameLine()
					rom.ImGui.PushStyleVar(rom.ImGuiStyleVar.FramePadding, 0, 0)
					rom.ImGui.PushStyleColor(rom.ImGuiCol.FrameBg, 0,0,0,0)
					rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, unpack(colors.info))
					rom.ImGui.PushItemWidth(rom.ImGui.GetContentRegionAvail() - rom.ImGui.CalcTextSize('|'))
					local text, enter_pressed = rom.ImGui.InputText("##Text" .. ids, bd.texts[ids] or tostring_literal(ed.data), 65535, ed.fake and rom.ImGuiInputTextFlags.ReadOnly or rom.ImGuiInputTextFlags.EnterReturnsTrue)
					rom.ImGui.PopItemWidth()
					rom.ImGui.PopStyleColor()
					rom.ImGui.PopStyleColor()
					rom.ImGui.PopStyleVar()
					try_tooltip(bd,ed,true)
					if enter_pressed then
						ed.base.data[ed.name] = peval(text)
						bd.texts[ids] = nil
						refresh(bd)
					elseif text == "" then 
						bd.texts[ids] = nil
					else
						bd.texts[ids] = text
					end
				else
					rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, unpack(colors.null))
					rom.ImGui.SameLine()
					rom.ImGui.Text(tostring(ed.data))
					rom.ImGui.PopStyleColor()
					if ed.type == "function" then
						rom.ImGui.SameLine()
						rom.ImGui.PushStyleVar(rom.ImGuiStyleVar.FramePadding, 0, 0)
						rom.ImGui.PushStyleColor(rom.ImGuiCol.FrameBg, 0,0,0,0)
						rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, unpack(colors.info))
						rom.ImGui.Text("(")
						rom.ImGui.SameLine()
						rom.ImGui.PushItemWidth(rom.ImGui.GetContentRegionAvail() - rom.ImGui.CalcTextSize('(|)'))
						local text, enter_pressed = rom.ImGui.InputText("##Text" .. ids, bd.texts[ids] or '', 65535, rom.ImGuiInputTextFlags.EnterReturnsTrue)
						local tooltip = bd.tooltips[ids]
						if tooltip and rom.ImGui.IsItemHovered() then
							rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, unpack(tooltip.color))
							rom.ImGui.SetTooltip(tooltip.message);
							rom.ImGui.PopStyleColor()
						end
						rom.ImGui.PopItemWidth()
						rom.ImGui.SameLine()
						rom.ImGui.Text(")")
						rom.ImGui.PopStyleColor()
						rom.ImGui.PopStyleColor()
						rom.ImGui.PopStyleVar()
						if enter_pressed then
							local result = pack(pcall(ed.data, peval(text)))
							if result.n > 1 then
								local color, message
								if result[1] then
									color = colors.leaf
									message = tostring_vararg(unpack(result, 2, result.n))
								else 
									color = colors.null
									message = result[2]
								end
								bd.tooltips[ids] = { message = message, color = color }
							end
							bd.texts[ids] = nil
						else
							bd.texts[ids] = text
						end
						if bd.data and ed.show == "call" then
							local params = bd.data.params
							if params == nil then
								local name = bd.data.name
								if name == nil then
									local script_name = bd.data.script_name
									if script_name ~= nil then
										name = script_name:sub(script_prefix_index)
									end
								end
							end
							if params ~= nil then
								rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, unpack(colors.fake))
								rom.ImGui.Text("")
								rom.ImGui.SameLine()
								rom.ImGui.Text("")
								rom.ImGui.SameLine()
								rom.ImGui.Text("params:")
								for _,p in ipairs(params) do
									rom.ImGui.SameLine()
									rom.ImGui.Text(p.name)
									if p.value and rom.ImGui.IsItemHovered() then
										rom.ImGui.SetTooltip(p.value);
									end
								end
								rom.ImGui.PopStyleColor()
							end
						end
					end
				end
			end
		end
		if _unfolded then
			local filter = bd.filter
			local entries = unfold(ed)
			if entries then
				local skipped = false
				for _,sd in ipairs(entries) do
					if sd.iter or bd.mode == 2 then 
						if not unfolded[bd.index .. '|' .. sd.path] and #filter ~= 0 and not filter_match(sd.text,filter) then
							skipped = true
						else
							render_browser(bd,sd)
						end
					end
				end
				if skipped then
					rom.ImGui.Text("")
					rom.ImGui.SameLine()
					rom.ImGui.Text("")
					rom.ImGui.SameLine()
					rom.ImGui.Text("...")
				end
			end
			if show then rom.ImGui.TreePop() end
		end
	end
end

local frame_period = 60
local frame_counter = 60

local closable_true, closable_false

local function imgui_on_render()
	if ob.root.style == nil then
		ob.root.style = rom.ImGui.GetStyle()
	end
	if closable_true == nil then
		closable_true = {true,rom.ImGuiWindowFlags.NoSavedSettings}
		closable_false = {}
	end

	local should_refresh = false
	if frame_counter >= frame_period then
		frame_counter = 0
		should_refresh = true
	end
	frame_counter = frame_counter + 1
	local rid = 1
	local first = false
	for bid,bd in pairs(browsers) do
		local closable = closable_false
		if bid ~= rid then 
			closable = closable_true
			local x,y = unpack(bd.init_pos)
			local w,h = unpack(bd.init_size)
			rom.ImGui.SetNextWindowPos(x,y,rom.ImGuiCond.Once)
			rom.ImGui.SetNextWindowSize(w,h,rom.ImGuiCond.Once)
		end
		if rom.ImGui.Begin(bid == rid and "Object Browser" or "Object Browser##" .. bid, unpack(closable)) then
			if first or bid == rid then
				last_pos[1], last_pos[2] = rom.ImGui.GetWindowPos()
				last_size[1], last_size[2] = rom.ImGui.GetWindowSize()
				first = false
			end
			bd.index = bid
			local item_spacing_x, item_spacing_y = public.GetStyleVar(rom.ImGuiStyleVar.ItemSpacing)
			local frame_padding_x, frame_padding_y = public.GetStyleVar(rom.ImGuiStyleVar.FramePadding)
			local num, y_max, x_total, x_swap, x_filter = calculate_text_sizes('...','Filter: ')
			local x,y = rom.ImGui.GetContentRegionAvail()
			-- height of InputText == font_size + frame_padding.y
			-- and we're going to change frame_padding.y temporarily later on
			-- such that InputText's height == max y
			local x_input = x - x_total - item_spacing_x*num
			local y_box = y - y_max - item_spacing_y
			local x_box = x
			rom.ImGui.Text("Filter: ")
			rom.ImGui.SameLine()
			rom.ImGui.PushItemWidth(x_input)
			rom.ImGui.PushStyleVar(rom.ImGuiStyleVar.FramePadding, 0, 0)
			rom.ImGui.PushStyleColor(rom.ImGuiCol.FrameBg, 0,0,0,0)
			local enter_pressed
			bd.filter_text, enter_pressed = rom.ImGui.InputText("##Text" .. bid, bd.filter_text, 65535, rom.ImGuiInputTextFlags.EnterReturnsTrue)
			rom.ImGui.PopStyleColor()
			rom.ImGui.PopStyleVar()
			rom.ImGui.PopItemWidth()
			rom.ImGui.PushStyleColor(rom.ImGuiCol.Button, unpack(colors[filter_modes_browser[bd.mode]]))
			rom.ImGui.SameLine()
			if rom.ImGui.Button("    ##Swap" .. bid) then
				bd.mode = bd.mode%#filter_modes_browser + 1
			end
			rom.ImGui.PopStyleColor()
			if enter_pressed then
				bd.filter = bd.filter_text
			end
			if should_refresh then
				refresh(bd)
			end
			if bid ~= rid then
				local path = bd.path or "???"
				y_box = y_box - y_max - item_spacing_y
				rom.ImGui.Text("Path: ")
				rom.ImGui.SameLine()
				rom.ImGui.PushStyleVar(rom.ImGuiStyleVar.FramePadding, 0, 0)
				rom.ImGui.PushStyleColor(rom.ImGuiCol.FrameBg, 0,0,0,0)
				rom.ImGui.PushItemWidth(x_input)
				rom.ImGui.InputText("##Path" .. bid, path, #path, rom.ImGuiInputTextFlags.ReadOnly)
				rom.ImGui.PopItemWidth()
				rom.ImGui.PopStyleColor()
				rom.ImGui.PopStyleVar()
			end
			rom.ImGui.PushStyleColor(rom.ImGuiCol.FrameBg, 0,0,0,0)
			if rom.ImGui.BeginListBox("##Box" .. bid,x_box,y_box) then
				rom.ImGui.PopStyleColor()
				render_browser(bd,bd)
				rom.ImGui.EndListBox()
			else
				rom.ImGui.PopStyleColor()
			end
			rom.ImGui.End()
		elseif bid ~= rid then
			browsers[bid] = nil
			rom.ImGui.End()
		end
	end
	for did,dd in pairs(details) do
		local x,y = unpack(dd.init_pos)
		local w,h = unpack(dd.init_size)
		rom.ImGui.SetNextWindowPos(x,y,rom.ImGuiCond.Once)
		rom.ImGui.SetNextWindowSize(w,h,rom.ImGuiCond.Once)
		if rom.ImGui.Begin("Object Details##" .. did, unpack(closable_true)) then
			if first then
				last_pos[1], last_pos[2] = rom.ImGui.GetWindowPos()
				last_size[1], last_size[2] = rom.ImGui.GetWindowSize()
				first = false
			end
			dd.index = did
			local item_spacing_x, item_spacing_y = public.GetStyleVar(rom.ImGuiStyleVar.ItemSpacing)
			local frame_padding_x, frame_padding_y = public.GetStyleVar(rom.ImGuiStyleVar.FramePadding)
			local num, y_max, x_total, x_swap, x_filter = calculate_text_sizes('...','Filter: ')
			local x,y = rom.ImGui.GetContentRegionAvail()
			-- height of InputText == font_size + frame_padding.y
			-- and we're going to change frame_padding.y temporarily later on
			-- such that InputText's height == max y
			local y_input = y_max - rom.ImGui.GetFontSize() - frame_padding_y 
			local x_input = x - x_total - item_spacing_x*num
			local y_box = y - y_max - item_spacing_y
			local x_box = x
			rom.ImGui.Text("Filter: ")
			rom.ImGui.SameLine()
			rom.ImGui.PushItemWidth(x_input)
			rom.ImGui.PushStyleVar(rom.ImGuiStyleVar.FramePadding, 0, 0)
			rom.ImGui.PushStyleColor(rom.ImGuiCol.FrameBg, 0,0,0,0)
			local enter_pressed
			dd.filter_text, enter_pressed = rom.ImGui.InputText("##Text" .. did, dd.filter_text, 65535, rom.ImGuiInputTextFlags.EnterReturnsTrue)
			rom.ImGui.PopStyleColor()
			rom.ImGui.PopStyleVar()
			rom.ImGui.PopItemWidth()
			rom.ImGui.PushStyleColor(rom.ImGuiCol.Button, unpack(colors[filter_modes_details[dd.mode]]))
			rom.ImGui.SameLine()
			if rom.ImGui.Button("    ##Swap" .. did) then
				dd.mode = dd.mode%#filter_modes_details + 1
			end
			rom.ImGui.PopStyleColor()
			do
				local path = dd.path or "???"
				y_box = y_box - y_max - item_spacing_y
				rom.ImGui.Text("Path:  ")
				rom.ImGui.SameLine()
				rom.ImGui.PushStyleVar(rom.ImGuiStyleVar.FramePadding, 0, 0)
				rom.ImGui.PushStyleColor(rom.ImGuiCol.FrameBg, 0,0,0,0)
				rom.ImGui.PushItemWidth(x)
				rom.ImGui.InputText("##Path" .. did, path, #path, rom.ImGuiInputTextFlags.ReadOnly)
				rom.ImGui.PopItemWidth()
				rom.ImGui.PopStyleColor()
				rom.ImGui.PopStyleVar()
			end
			if enter_pressed then
				dd.filter = dd.filter_text
			end
			if should_refresh then
				refresh(dd)
			end
			rom.ImGui.PushStyleColor(rom.ImGuiCol.FrameBg, 0,0,0,0)
			if rom.ImGui.BeginListBox("##Box" .. did,x_box,y_box) then
				rom.ImGui.PopStyleColor()
				render_details(dd)
				rom.ImGui.EndListBox()
			else
				rom.ImGui.PopStyleColor()
			end
			rom.ImGui.End()
		else
			details[did] = nil
			rom.ImGui.End()
		end
	end
end

create_browser(root_entries())
rom.gui.add_imgui(imgui_on_render)

local sc = {}
public.console = sc

local base_globals = rom.game or _globals
local globals = {}

local ob = public.browser
globals.root = ob and ob.root

local repl_environment = setmetatable({},{
	__index = function(_,k)
		local v = globals[k]
		if v ~= nil then return v end
		return base_globals[k]
	end,
	__newindex = globals
})

---@type string?
local autoexec = "autoexec"
local datafolder = _PLUGIN.plugins_data_mod_folder_path

local function check_data_folder()
	rom.path.create_directory(datafolder)
	return datafolder
end

local function tostring_literal(value)
	-- TODO: expand tables python-style?
	if type(value) == "string" then
		local lined, _lined = 0, value:gmatch("\n")
		for _ in _lined do lined = lined + 1 end
		local dquoted, _dquoted = 0, value:gmatch([=["]=])
		for _ in _dquoted do dquoted = dquoted + 1 end
		local squoted, _squoted = 0, value:gmatch([=[']=])
		for _ in _squoted do squoted = squoted + 1 end
		if lined > 0 or (dquoted > 0 and squoted > 0) then
			local special, _special = 0, value:gmatch([=[[=]]=])
			for _ in _special do special = special + 1 end
			local eq = "="
			for _ = 1, special do
				eq = eq .. '='
			end
			return '['..eq..'[' .. value .. ']'..eq..']'
		elseif squoted > 0 then
			return '"' .. value .. '"'
		else
			return "'" .. value .. "'"
		end
	end
	return tostring(value)
end

local function tostring_vararg(raw, ...)
	local s = ""
	for _,v in public.vararg(...) do
		v = raw and tostring(v) or tostring_literal(v)
		s = s .. '\t' .. v
	end
	return s:sub(2,#s)
end

sc.log = {
	error = {
		prefix = {
			debug = "",
			shown = ""
		},
		logger = rom.log.error,
		color = reverse_color{color_FF,color_20,color_20,color_EE},
	},
	info = {
		prefix = {
			debug = "",
			shown = ""
		},
		logger = rom.log.info,
		color = reverse_color{color_FF,color_EE,color_EE,color_EE},
	},
	warning = {
		prefix = {
			debug = "",
			shown = ""
		},
		logger = rom.log.warning,
		color = reverse_color{color_FF,color_20,color_EE,color_EE},
	},
	history = {
		prefix = {
			debug = "",
			shown = "] "
		},
		logger = false,
		color = reverse_color{color_EE,color_CC,color_CC,color_CC},
	},
	echo = {
		prefix = {
			debug = "[Echo]:",
			shown = ""
		},
		logger = rom.log.info,
		color = reverse_color{color_FF,color_EE,color_EE,color_EE},
	},
	print = {
		prefix = {
			debug = "[Print]:",
			shown = ""
		},
		logger = rom.log.info,
		color = reverse_color{color_FF,color_EE,color_EE,color_EE},
	},
	returns = {
		prefix = {
			debug = "[Returns]:",
			shown = ""
		},
		logger = rom.log.info,
		color = reverse_color{color_FF,color_FF,color_FF,color_20},
	},
	perror = {
		prefix = {
			debug = "[Error]",
			shown = ""
		},
		logger = rom.log.warn,
		color = reverse_color{color_FF,color_20,color_20,color_EE},
	},
}

local console_log_meta = { __call = function(lg,...) return lg.log(...) end }

for _,lg in pairs(sc.log) do
	lg.log = function(md, raw, ...)
		local text = tostring_vararg(raw, ...)
		table.insert(md.raw, text)
		table.insert(md.shown, lg.prefix.shown .. text)
		md.colors[#md.raw] = lg.color
		if lg.logger then
			return lg.logger( md.prefix .. lg.prefix.debug .. text )
		end
	end
	setmetatable(lg,console_log_meta)
end

local function repl_execute_lua(md, env, text, ...)
	public.merge(globals,md.definitions)
	---@type string|function?, string?
	local func, err = text, ''
	
	if type(text) == "string" then
		env = env == true and repl_environment or env
		func, err = load( "return " .. text, nil, "t", env)
		if not func then
			func, err = load( text, nil, "t", env )
			if not func then
				return false, err
			end
		end
	end
	---@cast func function
	return pcall( func, ... )
end

--https://stackoverflow.com/a/28664691
local parse_command_text
local parse_multicommand_text
do 
	-- TODO: This needs to be improved regarding properly handling embedded and mixed quotes!
	local parse_buffer = {}
	function parse_command_text(text)
		public.iclear(parse_buffer)
		local spat, epat, buf, quoted = [=[^(['"])]=], [=[(['"])$]=], nil, nil
		for str in text:gmatch("%S+") do
			local squoted = str:match(spat)
			local equoted = str:match(epat)
			local escaped = str:match([=[(\*)['"]$]=])
			if squoted and not quoted and not equoted then
				buf, quoted = str, squoted
			elseif buf and equoted == quoted and #escaped % 2 == 0 then
				str, buf, quoted = buf .. ' ' .. str, nil, nil
			elseif buf then
				buf = buf .. ' ' .. str
			end
			if not buf then
				local token = str:gsub(spat,""):gsub(epat,"")
				table.insert(parse_buffer,token)
			end
		end
		if buf then return false, "Missing matching quote for "..buf end
		return true, unpack(parse_buffer)
	end
	function parse_multicommand_text(text)
		public.iclear(parse_buffer)
		for mstr in text:gmatch("[^\r\n]+") do
			local pquoted, buf = 0, nil
			for str in mstr:gmatch("[^;]+") do
				str = str:gsub("^%s\\*", "")
				local quoted, _quoted = 0, str:gmatch([=[['"]]=])
				for _ in _quoted do quoted = quoted + 1 end
				local escaped, _escaped = 0, str:gmatch([=[\['"]]=])
				for _ in _escaped do escaped = escaped + 1 end
				pquoted = (pquoted+quoted-escaped) % 2
				if not buf and pquoted == 1 then
					buf = str
				elseif buf and pquoted == 0 then
					str, buf = buf .. ';' .. str, nil
				elseif buf and pquoted == 1 then
					buf = buf .. ';' .. str
					str, buf, quoted = buf .. ';' .. str, nil, 0
				end
				if not buf then
					local token = str
					table.insert(parse_buffer,token)
				end
			end
			if buf then return false, "Missing matching quote for "..buf end
		end
		return true, unpack(parse_buffer)
	end
end

local run_console_multicommand
local function run_console_command(md, text)
		local parse_result = pack(parse_command_text(text))
		local status, command_name = parse_result[1], parse_result[2]
		if not status then
			return sc.log.perror(md, true, command_name)
		end
		local alias = sc.aliases[command_name]
		if alias ~= nil then
			return run_console_multicommand(md, alias)
		end
		local command = sc.commands[command_name]
		if command == nil then
			return sc.log.perror(md, true, 'no command by the name of "' .. command_name .. '" found')
		end
		local ret = pack(pcall(command,md,unpack(parse_result, 3, parse_result.n)))
		if ret.n <= 1 then return end
		if ret[1] == false then
			return sc.log.perror(md, true, ret[2])
		end
		return sc.log.info(md, false, unpack(ret, 2, ret.n))
end
function run_console_multicommand(md, text)
		local parse_result = pack(parse_multicommand_text(text))
		local status, err = parse_result[1], parse_result[2]
		if not status then
			sc.log.perror(md, true, err)
		end
		for i = 2, parse_result.n do
			run_console_command(md, parse_result[i])
		end
end


sc.aliases = {}
sc.binds = {}
sc.ibinds = {}

sc.command_help = {
	{"help","[0..1]","lists the available commands"},
	{"echo","[0..]","prints a message to the console"},
	{"lua","[1..]","executes lua code and shows the result"},
	{"luae","[1]","executes lua file with args and shows the result"},
	{"exec","[1]","executes a file containing a list of console commands"},
	{"alias","[0..2]","defines a command that represents multiple commands"},
	{"bind","[0..2]","binds a key combination to run commands during gameplay"},
	{"ibind","[0..2]","binds a key combination to run commands on the mod gui"}
}

local _MouseButton
local _KeyMod
local _Key

local function check_bind(md,k)
	local bind = ''
	for key in k:upper():gmatch("(%w+)") do
		if _Key == nil then
			_MouseButton = {}
			for k in pairs(rom.ImGuiMouseButton) do
				_MouseButton[k:upper() .. "MOUSE"] = k .. "Mouse"
			end
			_KeyMod = {}
			for k in pairs(rom.ImGuiKeyMod) do
				_KeyMod[k:upper()] = k
			end
			_Key = {}
			for k in pairs(rom.ImGuiKey) do
				_Key[k:upper()] = k
			end
		end
		key = _MouseButton[key] or _KeyMod[key] or _Key[key]
		if not key then 
			return sc.log.perror(md, true, 'invalid key combo: "' .. k .. '"')
		end
		bind = bind .. '+' .. key
	end
	return bind:sub(2)
end

sc.commands = {
	help = function(md,stub)
		if stub then
			local msg = sc.command_help[stub]
			if not msg then 
				return sc.log.perror(md, true, 'no command by the name of "' .. stub .. '" found')
			end
			return sc.log.echo(md, true, msg)
		end
		for _,h in ipairs(sc.command_help) do
			sc.log.echo(md, true, unpack(h))
		end
	end,
	echo = function(md,...)
		local text = ""
		for _, arg in public.vararg(...) do
			text = text .. ' ' .. arg
		end
		text = text:sub(2,#text)
		return sc.log.echo(md,true,text)
	end,
	lua = function(md,...)
		local text = ""
		for _, arg in public.vararg(...) do
			text = text .. ' ' .. arg
		end
		text = text:sub(2,#text)
		if #text == 0 then
			return sc.log.perror(md, true, "cannot execute empty lua code.")
		end
		local ret = pack(repl_execute_lua(md, true, text))
		if ret.n <= 1 then return end
		if ret[1] == false then
			return sc.log.perror(md, true, ret[2])
		end
		return sc.log.returns(md, false, unpack( ret, 2, ret.n ))
	end,
	--https://stackoverflow.com/a/10387949
	luae = function(md,path,...)
		if io then
			local qualpath = check_data_folder() .. '/' .. path
			local file = io.open(qualpath,"rb")
			if not file or type(file) == "string" or type(file) == "number" then
				file = io.open(qualpath .. ".lua","rb")
				if not file or type(file) == "string" or type(file) == "number" then
					return sc.log.warning(md, true, 'attempted to read the lua file "' .. path .. '", but failed.')
				end
			end
			local data = file:read("*a")
			file:close()
			local ret = pack(repl_execute_lua(md, true, data, ...))
			if ret.n <= 1 then return end
			if ret[1] == false then
				return sc.log.perror(md, true, ret[2])
			end
			return sc.log.returns(md, false, unpack( ret, 2, ret.n ))
		end
	end,
	exec = function(md,path)
		if io then
			local qualpath = check_data_folder() .. '/' .. path
			local file = io.open(qualpath,"rb")
			if not file or type(file) == "string" or type(file) == "number" then
				file = io.open(qualpath .. ".txt","rb")
				if not file or type(file) == "string" or type(file) == "number" then
					return sc.log.warning(md, true, 'attempted to read the batch file "' .. path .. '", but failed.')
				end
			end
			local data = file:read("*a")
			file:close()
			return run_console_multicommand(md,data)
		end
	end,
	alias = function(md,name,...)
		if name == nil then
			for k,v in pairs(sc.aliases) do
				sc.log.echo(md, true, k,v)
			end
			return
		end
		local text = ""
		for _, arg in public.vararg(...) do
			text = text .. ' ' .. arg
		end
		text = text:sub(2,#text)
		if #text == 0 then
			local msg = sc.aliases[name]
			if not msg then 
				return sc.log.perror(md, true, 'no alias by the name of "' .. name .. '" exists')
			end
			return sc.log.echo(md, true, msg)
		end
		sc.aliases[name] = text
	end,
	bind = function(md,name,...)
		if name == nil then
			for k,v in pairs(sc.binds) do
				sc.log.echo(md, true, k,v)
			end
			return
		end
		name = check_bind(md,name)
		if name == nil then return end
		local text = ""
		for _, arg in public.vararg(...) do
			text = text .. ' ' .. arg
		end
		text = text:sub(2,#text)
		if #text == 0 then
			local msg = sc.binds[name]
			if not msg then 
				return sc.log.perror(md, true, 'no bind for the key combo "' .. name .. '" exists')
			end
			return sc.log.echo(md, true, msg)
		end
		sc.binds[name] = text
	end,
	ibind = function(md,name,...)
		if name == nil then
			for k,v in pairs(sc.ibinds) do
				sc.log.echo(md, true, k,v)
			end
			return
		end
		name = check_bind(md,name)
		if name == nil then return end
		local text = ""
		for _, arg in public.vararg(...) do
			text = text .. ' ' .. arg
		end
		text = text:sub(2,#text)
		if #text == 0 then
			local msg = sc.ibinds[name]
			if not msg then 
				return sc.log.perror(md, true, 'no UI bind for the key combo "' .. name .. '" exists')
			end
			return sc.log.echo(md, true, msg)
		end
		sc.ibinds[name] = text
	end
}

sc.modes = {
	{
		name = "Notepad",
		prefix = "[Notes]:",
		on_enter = function(md) return function(text)
			table.insert(md.history,text)
			return sc.log.info(md, true, text)
		end end
	},
	{
		name = "Console",
		prefix = "[Console]:",
		on_enter = function(md) return function(text)
			table.insert(md.history,text)
			sc.log.history(md, true, text)
			return run_console_multicommand(md, text)
		end end
	},
	{
		name = "Lua REPL",
		prefix = "[LuaREPL]:",
		on_enter = function(md) return function(text)
			table.insert(md.history,text)
			sc.log.history(md, true, text)
			local ret = pack(repl_execute_lua(md, true, text))
			if ret.n <= 1 then return end
			if ret[1] == false then
				return sc.log.perror(md, true, ret[2])
			end
			globals._ = ret[2]
			return sc.log.returns(md, false, unpack(ret, 2, ret.n))
		end end
	}
}

local function console_mode_definitions(get_md)
	return {
		help = function()
			local h = {}
			for k in pairs(globals) do
				if type(k) == "string" and k:sub(1,1) ~= '_' then
					table.insert(h,k)
				end
			end
			sc.log.print(get_md(),true,table.concat(h,', '))
		end,
		print = function(...)
			return sc.log.print(get_md(),true,...)
		end,
		tprint = function(...)
			for _,o in public.vararg(...) do
				sc.log.print(get_md(),false,o)
				local t = type(o)
				if t == "table" or t == "userdata" then
					---@cast o table
					for k,v in pairs(o) do
						sc.log.print(get_md(),false,k,v)
					end
				end
			end
		end,
		itprint = function(...)
			for _,o in public.vararg(...) do
				sc.log.print(get_md(),false,o)
				local t = type(o)
				if t == "table" or t == "userdata" then
					---@cast o table
					for k,v in ipairs(o) do
						sc.log.print(get_md(),false,k,v)
					end
				end
			end
		end,
		mprint = function(m,...)
			for _,o in public.vararg(...) do
				sc.log.print(get_md(),false,o)
				local t = type(o)
				if t == "table" or t == "userdata" then
					---@cast o table
					for k,v in pairs(o) do
						sc.log.print(get_md(),false,k,m(v))
					end
				end
			end
		end,
		imprint = function(m,...)
			for _,o in public.vararg(...) do
				sc.log.print(get_md(),false,o)
				local t = type(o)
				if t == "table" or t == "userdata" then
					---@cast o table
					for k,v in ipairs(o) do
						sc.log.print(get_md(),false,k,m(v))
					end
				end
			end
		end,
		eval = function(...)
			return repl_execute_lua(get_md(), ...)
		end
	}
end

for mi,md in ipairs(sc.modes) do
	public.merge(md,{
		current_text = "",
		enter_pressed = false,
		history_offset = 0,
		history = {},
		shown = {},
		raw = {},
		selected = {},
		selected_last = nil,
		colors = {},
		index = mi,
		on_enter = md.on_enter(md),
		definitions = console_mode_definitions(function() return md end)
	})
end

sc.mode = sc.modes[1]
public.merge(globals,console_mode_definitions(function() return sc.mode end))

local calculate_text_sizes
do
	local calculate_text_sizes_x_buffer = {}
	function calculate_text_sizes(...)
		-- don't need to clear the buffer since 
		-- we only iterate over the region we overwrite
		local frame_padding_x, frame_padding_y = public.GetStyleVar(rom.ImGuiStyleVar.FramePadding)
		local frame_padding_x_2 = 2*frame_padding_x
		local frame_padding_y_2 = 2*frame_padding_y
		local my = 0 -- maximum y value in this row
		local sx = 0 -- sum of x values in this row
		local n -- number of items in this row
		for i,t in public.vararg(...) do
			n = i
			local x,y = rom.ImGui.CalcTextSize(t)
			x = x + frame_padding_x_2
			y = y + frame_padding_y_2
			calculate_text_sizes_x_buffer[i] = x
			sx = sx + x
			if y > my then my = y end
		end
		return n, my, sx, unpack(calculate_text_sizes_x_buffer, 1, n)
	end
end

local function run_bind(m,k,v)
	local pass = true
	for key in k:gmatch("(%w+)") do
		if k:match("Mouse$") and rom.ImGuiMouseButton[key:sub(1,#key-5)] then
			pass = pass and rom.ImGui.IsMouseClicked(rom.ImGuiMouseButton[key:sub(1,#key-5)])
		elseif rom.ImGuiKeyMod[key] then
			pass = pass and rom.ImGui.IsKeyDown(rom.ImGuiKeyMod[key])
		elseif rom.ImGuiKey[key] then
			pass = pass and rom.ImGui.IsKeyPressed(rom.ImGuiKey[key])
		else
			pass = false
		end
		if not pass then break end
	end
	if pass then
		run_console_multicommand(m,v)
	end
end

local tab_selected = false

local function imgui_off_render()
	local m = sc.mode
	for k,v in pairs(sc.binds) do
		pcall(run_bind,m,k,v)
	end
end

local function file_exists(name)
	if io == nil then return false end
	local f=io.open(name,"r")
	if f~=nil then
		io.close(f)
		return true
	else
		return false
	end
end

local function imgui_on_render()
	local m = sc.mode
	for k,v in pairs(sc.ibinds) do
		pcall(run_bind,m,k,v)
	end
	if rom.ImGui.Begin("Script Console", rom.ImGuiWindowFlags.NoTitleBar) then
		if rom.ImGui.BeginTabBar("Mode") then
			local item_spacing_x, item_spacing_y = public.GetStyleVar(rom.ImGuiStyleVar.ItemSpacing)
			local frame_padding_x, frame_padding_y = public.GetStyleVar(rom.ImGuiStyleVar.FramePadding)
			local bot_num, bot_y_max, bot_x_total, x_focus = calculate_text_sizes("|")
			local x,y = rom.ImGui.GetContentRegionAvail()
			local x_input = x - bot_x_total - item_spacing_x*bot_num
			-- height of InputText == font_size + frame_padding.y
			-- and we're going to change frame_padding.y temporarily later on
			-- such that InputText's height == max y
			local y_input = bot_y_max - rom.ImGui.GetFontSize() - frame_padding_y 
			local box_y = y - bot_y_max - item_spacing_y*2
			for mi,md in ipairs(sc.modes) do
				local ds = md.name
				local ms = tostring(mi)
				if (tab_selected and sc.mode == md) and rom.ImGui.BeginTabItem(ds, rom.ImGuiTabItemFlags.SetSelected) or rom.ImGui.BeginTabItem(ds) then
					if not tab_selected then sc.mode = md end
					if sc.mode == md then tab_selected = false end
					rom.ImGui.EndTabItem()
					if autoexec then
						local name = autoexec
						autoexec = nil
						local path = check_data_folder() .. '/' .. name
						local tpath = path .. '.txt'
						if file_exists(path) or file_exists(tpath) then
							run_console_command(md,"exec " .. name)
						elseif io ~= nil then
							local status, file = pcall(io.open,tpath,'w')
							if status then file:close() end
						end
					end
					rom.ImGui.PushStyleColor(rom.ImGuiCol.FrameBg, 0,0,0,0)
					if rom.ImGui.BeginListBox("##Box" .. ms,x,box_y) then
						rom.ImGui.PopStyleColor()
						local selected = not rom.ImGui.IsMouseClicked(rom.ImGuiMouseButton.Left)
						for li,ls in ipairs(md.shown) do
							local tall = select(2,rom.ImGui.CalcTextSize(ls, false, x-frame_padding_x*2-item_spacing_x))
							rom.ImGui.Selectable("##Select" .. ms .. tostring(li), md.selected[li] or false, rom.ImGuiSelectableFlags.AllowDoubleClick, 0, tall)
							if rom.ImGui.IsItemClicked(rom.ImGuiMouseButton.Left) then
								selected = true
								if rom.ImGui.IsKeyDown(rom.ImGuiKeyMod.Shift) then
									local ll = md.selected_last
									if ll then
										for i in ipairs(md.shown) do
											md.selected[i] = false
										end
										local step = ll<li and -1 or 1
										for i = li, ll, step do
											md.selected[i] = true
										end
									else
										md.selected_last = li
									end
								elseif rom.ImGui.IsKeyDown(rom.ImGuiKeyMod.Ctrl) then
									md.selected_last = li
									md.selected[li] = not md.selected[li]
								else
									md.selected_last = li
									for i in ipairs(md.shown) do
										md.selected[i] = false
									end
									md.selected[li] = true
								end
							end
							rom.ImGui.SameLine()
							local color = md.colors[li]
							if color ~= nil then rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, unpack(color)) end
							rom.ImGui.TextWrapped(ls)
							if color ~= nil then rom.ImGui.PopStyleColor() end
						end
						if not selected then
							for i in ipairs(md.shown) do
								md.selected[i] = false
							end
						end
						rom.ImGui.EndListBox()
					else
						rom.ImGui.PopStyleColor()
					end
					rom.ImGui.PushItemWidth(x_input)
					rom.ImGui.PushStyleVar(rom.ImGuiStyleVar.FramePadding, frame_padding_x, y_input)
					md.current_text, md.enter_pressed = rom.ImGui.InputText("##Text" .. ms, md.current_text, 65535, rom.ImGuiInputTextFlags.EnterReturnsTrue)
					rom.ImGui.PopStyleVar()
					rom.ImGui.PopItemWidth()
					if rom.ImGui.IsWindowFocused(rom.ImGuiFocusedFlags.RootAndChildWindows) then
						if not rom.ImGui.IsItemFocused() and not rom.ImGui.IsItemActive() then
							if rom.ImGui.IsKeyDown(rom.ImGuiKeyMod.Ctrl) and rom.ImGui.IsKeyPressed(rom.ImGuiKey.C) then
								local text
								for hi,b in ipairs(md.selected) do
									if b then 
										local line = md.raw[hi] or md.shown[hi]
										if text == nil then
											text = line
										else
											text = text .. '\n' .. line
										end
									end
								end
								rom.ImGui.SetClipboardText(text)
							end
							if rom.ImGui.IsKeyDown(rom.ImGuiKeyMod.Ctrl) and rom.ImGui.IsKeyPressed(rom.ImGuiKey.A) then
								for i in ipairs(md.shown) do
									md.selected[i] = true
								end
							end
							if rom.ImGui.IsKeyDown(rom.ImGuiKeyMod.Ctrl) and rom.ImGui.IsKeyPressed(rom.ImGuiKey.D) then
								for i in ipairs(md.shown) do
									md.selected[i] = false
								end
							end
							if rom.ImGui.IsKeyDown(rom.ImGuiKeyMod.Ctrl) and rom.ImGui.IsKeyPressed(rom.ImGuiKey.Z) then
								public.iclear(md.shown,md.raw,md.selected,md.colors)
							end
							if rom.ImGui.IsKeyPressed(rom.ImGuiKey.Tab) then
								tab_selected = true
								local n = #sc.modes
								sc.mode = sc.modes[mi % n + 1]
							end
						end
						local changed_offset
						if rom.ImGui.IsKeyPressed(rom.ImGuiKey.UpArrow) then
							md.history_offset = md.history_offset + 1
							if md.history_offset > #md.history then
								md.history_offset = #md.history
							end
							changed_offset = true
						end
						if rom.ImGui.IsKeyPressed(rom.ImGuiKey.DownArrow) then
							md.history_offset = md.history_offset - 1
							if md.history_offset < 0 then
								md.history_offset = 0
							end
							changed_offset = true
						end
						if changed_offset then
							if md.history_offset == 0 then
								md.current_text = ""
							else
								md.current_text = md.history[#md.history-md.history_offset+1]
							end
						end
					end
				end
			end
			rom.ImGui.EndTabBar()
		end
		rom.ImGui.End()
	end
	-- handling entering input separate from constructing the UI
	-- so actions that use h2m.ImGui will be separate from the sc's UI
	for mi,md in ipairs(sc.modes) do
		if md.enter_pressed then
			md.enter_pressed = false
			md.history_offset = 0
			local text = md.current_text
			md.current_text = ""
			md.on_enter(text)
		end
	end
end

rom.gui.add_imgui(imgui_on_render)
rom.gui.add_always_draw_imgui(function() if not rom.gui.is_open() then return imgui_off_render() end end)

function sc.rcon(text)
	return run_console_multicommand(sc.mode,text)
end

function sc.rlua(text, ...)
	return select(2,repl_execute_lua(sc.mode,true,text,...))
end