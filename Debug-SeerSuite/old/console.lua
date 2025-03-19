---@meta _
---@diagnostic disable

local sc = {}
public.console = sc

local base_globals = ...
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
		color = 0xFF2020EE,
	},
	info = {
		prefix = {
			debug = "",
			shown = ""
		},
		logger = rom.log.info,
		color = 0xFFEEEEEE,
	},
	warning = {
		prefix = {
			debug = "",
			shown = ""
		},
		logger = rom.log.warning,
		color = 0xFF20EEEE,
	},
	history = {
		prefix = {
			debug = "",
			shown = "] "
		},
		logger = false,
		color = 0xEECCCCCC,
	},
	echo = {
		prefix = {
			debug = "[Echo]:",
			shown = ""
		},
		logger = rom.log.info,
		color = 0xFFEEEEEE,
	},
	print = {
		prefix = {
			debug = "[Print]:",
			shown = ""
		},
		logger = rom.log.info,
		color = 0xFFEEEEEE,
	},
	returns = {
		prefix = {
			debug = "[Returns]:",
			shown = ""
		},
		logger = rom.log.info,
		color = 0xFFFFFF20,
	},
	perror = {
		prefix = {
			debug = "[Error]",
			shown = ""
		},
		logger = rom.log.warn,
		color = 0xFF2020EE,
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
		return true, table.unpack(parse_buffer)
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
		return true, table.unpack(parse_buffer)
	end
end

local run_console_multicommand
local function run_console_command(md, text)
		local parse_result = table.pack(parse_command_text(text))
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
		local ret = table.pack(pcall(command,md,table.unpack(parse_result, 3, parse_result.n)))
		if ret.n <= 1 then return end
		if ret[1] == false then
			return sc.log.perror(md, true, ret[2])
		end
		return sc.log.info(md, false, table.unpack(ret, 2, ret.n))
end
function run_console_multicommand(md, text)
		local parse_result = table.pack(parse_multicommand_text(text))
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
			sc.log.echo(md, true, table.unpack(h))
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
		local ret = table.pack(repl_execute_lua(md, true, text))
		if ret.n <= 1 then return end
		if ret[1] == false then
			return sc.log.perror(md, true, ret[2])
		end
		return sc.log.returns(md, false, table.unpack( ret, 2, ret.n ))
	end,
	--https://stackoverflow.com/a/10387949
	luae = function(md,path,...)
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
		local ret = table.pack(repl_execute_lua(md, true, data, ...))
		if ret.n <= 1 then return end
		if ret[1] == false then
			return sc.log.perror(md, true, ret[2])
		end
		return sc.log.returns(md, false, table.unpack( ret, 2, ret.n ))
	end,
	exec = function(md,path)
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
			local ret = table.pack(repl_execute_lua(md, true, text))
			if ret.n <= 1 then return end
			if ret[1] == false then
				return sc.log.perror(md, true, ret[2])
			end
			globals._ = ret[2]
			return sc.log.returns(md, false, table.unpack(ret, 2, ret.n))
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
		return n, my, sx, table.unpack(calculate_text_sizes_x_buffer, 1, n)
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
						else
							local status, file = pcall(io.open,tpath,'w')
							if status then file.close() end
						end
					end
					rom.ImGui.PushStyleColor(rom.ImGuiCol.FrameBg, 0)
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
							if color ~= nil then rom.ImGui.PushStyleColor(rom.ImGuiCol.Text, color) end
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