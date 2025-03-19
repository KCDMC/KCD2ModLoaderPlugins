---@meta _
---@diagnostic disable

local ob = {}
public.browser = ob

local colors = {
	tree = 0xFFFF20FF,
	leaf = 0xFFFFFF20,
	info = 0xFF20FFFF,
	fake = 0xEECCCCCC,
	null = 0xFF2020FF
}

ob.root = {
	lua = ...,
	game = rom.game,
	colors = colors,
	helpers = {},
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
		init_pos = table.pack(x,y),
		init_size = table.pack(w,h),
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
		init_pos = table.pack(x,y),
		init_size = table.pack(w,h),
		mode = 1
	},entry)
end

local function root_entries()
	return { data = ob.root, iter = pairs, chain = {}, funcs = {},
		path = 'root', name = 'root', show = 'root', text = 'root'}
end

function ob.root.helpers.int_to_hex(i)
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
		return n, my, sx, table.unpack(calculate_text_sizes_x_buffer, 1, n)
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
	if ed.name then
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
	local keys_hex = {{'root','helpers','int_to_hex'}}
	
	local extra = {}
	
	function entrify(name,data,base)
		public.clear(extra)
		local data_type, sol_type = public.type(data)
		local type_name = sol_type or data_type
		local iter = nil
		local keys = nil
		local info = nil
		local func = nil
		if base ~= nil and base.type and (data_type == "number" or data_type == "nil") then
			if base.base and base.name == "colors" and base.base.name == "root" then
				table.insert(extra,{
					func = ob.root.helpers.int_to_hex,
					base = base,
					name = name,
					show = "hex",
					keys = keys_hex,
				})
			end
		elseif data_type == "table" then
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
			sd.fake = true
			if not sd.base then sd.base = ed end
		end
		return ed, table.unpack(extra)
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
	-- PATH = FUNC(PATH) | PATH[KEY] | PATH.FIELD | root
	-- FUNC = FUNC[KEY] | FUNC.FIELD | root
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
		local ret = table.pack(pcall(func))
		if ret.n <= 1 then return end
		if not ret[1] then return end
		return table.unpack(ret,2,ret.n)
	end

	local function try_tooltip(dd,sd,value_part) 
		if rom.ImGui.IsItemHovered() then
			local message
			if value_part then
				-- interpret the value here
			end
			if message ~= nil then
				rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, colors.fake)
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
							rom.ImGui.PushStyleColor(rom.ImGuiCol.HeaderHovered,0)
							rom.ImGui.PushStyleColor(rom.ImGuiCol.HeaderActive,0)
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
								rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, colors.fake)
								rom.ImGui.SameLine()
								rom.ImGui.Text(sd.name)
								rom.ImGui.PopStyleColor()
							end
							rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, colors.tree)
							rom.ImGui.SameLine()
							rom.ImGui.Text(sd.show)
							rom.ImGui.PopStyleColor()
							try_tooltip(dd,sd,false)
							rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, colors.info)
							rom.ImGui.SameLine()
							rom.ImGui.Text(sd.info)
							rom.ImGui.PopStyleColor()
							try_tooltip(dd,sd,true)
						end
					else
						-- not iterable
						rom.ImGui.Text("")
						if sd.fake then
							rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, colors.fake)
							rom.ImGui.SameLine()
							rom.ImGui.Text(sd.name)
							rom.ImGui.PopStyleColor()
						end
						rom.ImGui.SameLine()
						rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, colors.leaf)
						rom.ImGui.Text(sd.show)
						rom.ImGui.PopStyleColor()
						try_tooltip(dd,sd,false)
						if sd.type ~= "function" and sd.type ~= "thread" then
							rom.ImGui.SameLine()
							rom.ImGui.PushStyleVar(rom.ImGuiStyleVar.FramePadding, 0, 0)
							rom.ImGui.PushStyleColor(rom.ImGuiCol.FrameBg, 0)
							rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, colors.info)
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
							rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, colors.null)
							rom.ImGui.SameLine()
							rom.ImGui.Text(tostring(sd.data))
							rom.ImGui.PopStyleColor()
							if sd.type == "function" then
								rom.ImGui.SameLine()
								rom.ImGui.PushStyleVar(rom.ImGuiStyleVar.FramePadding, 0, 0)
								rom.ImGui.PushStyleColor(rom.ImGuiCol.FrameBg, 0)
								rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, colors.info)
								rom.ImGui.Text("(")
								rom.ImGui.SameLine()
								rom.ImGui.PushItemWidth(rom.ImGui.GetContentRegionAvail() - rom.ImGui.CalcTextSize('(|)'))
								local text, enter_pressed = rom.ImGui.InputText("##Text" .. id, dd.texts[id] or '', 65535, rom.ImGuiInputTextFlags.EnterReturnsTrue)
								local tooltip = dd.tooltips[id]
								if tooltip and rom.ImGui.IsItemHovered() then
									rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, tooltip.color)
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
									local result = table.pack(pcall(sd.data, peval(text)))
									if result.n > 1 then
										local color, message
										if result[1] then
											color = colors.leaf
											message = tostring_vararg(table.unpack(result, 2, result.n))
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
										rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, colors.fake)
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
				rom.ImGui.PushStyleColor(rom.ImGuiCol.HeaderHovered,0)
				rom.ImGui.PushStyleColor(rom.ImGuiCol.HeaderActive,0)
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
					rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, colors.fake)
					rom.ImGui.SameLine()
					rom.ImGui.Text(ed.name)
					rom.ImGui.PopStyleColor()
				end
				rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, colors.tree)
				rom.ImGui.SameLine()
				rom.ImGui.Text(ed.show)
				rom.ImGui.PopStyleColor()
				if ed.info ~= nil then
					rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, colors.info)
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
					rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, colors.fake)
					rom.ImGui.SameLine()
					rom.ImGui.Text(ed.name)
					rom.ImGui.PopStyleColor()
				end
				rom.ImGui.SameLine()
				rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, colors.leaf)
				rom.ImGui.Text(ed.show)
				rom.ImGui.PopStyleColor()
				if ed.type ~= "function" and ed.type ~= "thread" then
					rom.ImGui.SameLine()
					rom.ImGui.PushStyleVar(rom.ImGuiStyleVar.FramePadding, 0, 0)
					rom.ImGui.PushStyleColor(rom.ImGuiCol.FrameBg, 0)
					rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, colors.info)
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
					rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, colors.null)
					rom.ImGui.SameLine()
					rom.ImGui.Text(tostring(ed.data))
					rom.ImGui.PopStyleColor()
					if ed.type == "function" then
						rom.ImGui.SameLine()
						rom.ImGui.PushStyleVar(rom.ImGuiStyleVar.FramePadding, 0, 0)
						rom.ImGui.PushStyleColor(rom.ImGuiCol.FrameBg, 0)
						rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, colors.info)
						rom.ImGui.Text("(")
						rom.ImGui.SameLine()
						rom.ImGui.PushItemWidth(rom.ImGui.GetContentRegionAvail() - rom.ImGui.CalcTextSize('(|)'))
						local text, enter_pressed = rom.ImGui.InputText("##Text" .. ids, bd.texts[ids] or '', 65535, rom.ImGuiInputTextFlags.EnterReturnsTrue)
						local tooltip = bd.tooltips[ids]
						if tooltip and rom.ImGui.IsItemHovered() then
							rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, tooltip.color)
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
							local result = table.pack(pcall(ed.data, peval(text)))
							if result.n > 1 then
								local color, message
								if result[1] then
									color = colors.leaf
									message = tostring_vararg(table.unpack(result, 2, result.n))
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
								rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, colors.fake)
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
			local x,y = table.unpack(bd.init_pos)
			local w,h = table.unpack(bd.init_size)
			rom.ImGui.SetNextWindowPos(x,y,rom.ImGuiCond.Once)
			rom.ImGui.SetNextWindowSize(w,h,rom.ImGuiCond.Once)
		end
		if rom.ImGui.Begin(bid == rid and "Object Browser" or "Object Browser##" .. bid, table.unpack(closable)) then
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
			rom.ImGui.PushStyleColor(rom.ImGuiCol.FrameBg, 0)
			local enter_pressed
			bd.filter_text, enter_pressed = rom.ImGui.InputText("##Text" .. bid, bd.filter_text, 65535, rom.ImGuiInputTextFlags.EnterReturnsTrue)
			rom.ImGui.PopStyleColor()
			rom.ImGui.PopStyleVar()
			rom.ImGui.PopItemWidth()
			rom.ImGui.PushStyleColor(rom.ImGuiCol.Button, colors[filter_modes_browser[bd.mode]])
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
				rom.ImGui.PushStyleColor(rom.ImGuiCol.FrameBg, 0)
				rom.ImGui.PushItemWidth(x_input)
				rom.ImGui.InputText("##Path" .. bid, path, #path, rom.ImGuiInputTextFlags.ReadOnly)
				rom.ImGui.PopItemWidth()
				rom.ImGui.PopStyleColor()
				rom.ImGui.PopStyleVar()
			end
			rom.ImGui.PushStyleColor(rom.ImGuiCol.FrameBg, 0)
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
		local x,y = table.unpack(dd.init_pos)
		local w,h = table.unpack(dd.init_size)
		rom.ImGui.SetNextWindowPos(x,y,rom.ImGuiCond.Once)
		rom.ImGui.SetNextWindowSize(w,h,rom.ImGuiCond.Once)
		if rom.ImGui.Begin("Object Details##" .. did, table.unpack(closable_true)) then
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
			rom.ImGui.PushStyleColor(rom.ImGuiCol.FrameBg, 0)
			local enter_pressed
			dd.filter_text, enter_pressed = rom.ImGui.InputText("##Text" .. did, dd.filter_text, 65535, rom.ImGuiInputTextFlags.EnterReturnsTrue)
			rom.ImGui.PopStyleColor()
			rom.ImGui.PopStyleVar()
			rom.ImGui.PopItemWidth()
			rom.ImGui.PushStyleColor(rom.ImGuiCol.Button, colors[filter_modes_details[dd.mode]])
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
				rom.ImGui.PushStyleColor(rom.ImGuiCol.FrameBg, 0)
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
			rom.ImGui.PushStyleColor(rom.ImGuiCol.FrameBg, 0)
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