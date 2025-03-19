---@meta _
---@diagnostic disable

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