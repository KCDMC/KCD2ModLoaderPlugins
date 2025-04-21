---@diagnostic disable: lowercase-global

local envy = rom.mods['LuaENVY-ENVY']
envy.auto()

local default_enabled_fields = { "perk_id", "perk_name", "perk_ui_name", "visibility", "exclude_in_game_mode" }

local perk_fields = { "row", "perk_id", "perk_name", "perk_ui_name", "visibility", "exclude_in_game_mode", "autolearnable", "level", "skill_selector", "ui_priority", "perk_ui_lore_desc", "icon_id", "parent_id", "metaperk_id" }

local function has_perk(soul, perk)
	return soul:HasPerk(perk_id, false)
end

local function load_perks(perk_fields)
	if rom.game == nil then return end
	-- load perk database
	local databaseName = "perk"
	rom.game.Database.LoadTable(databaseName)
	local n = rom.game.Database.GetTableInfo(databaseName).LineCount
	local database = {}
	for row = 1, n do
		local entry = rom.game.Database.GetTableLine(databaseName, row - 1)
		--print(row, entry)
		for field,value in pairs(entry) do
			--print('',field,value)
			entry[field] = tostring(value)
		end
		entry.row = tostring(row)
		database[row] = entry
	end
	return database
end

local function draw_menu()
	local perks = rawget(private, 'perks')
	if perks == nil then
		perks = load_perks()
		if perks == nil then return end
		private.perks = perks
	end
	
	local enable_fields = rawget(private, 'enable_fields')
	if enable_fields == nil then
		enable_fields = {}
		for _,field in ipairs(default_enabled_fields) do
			enable_fields[field] = true
		end
		private.enable_fields = enable_fields
	end
	
	local search_texts = rawget(private, 'search_texts')
	if search_texts == nil then
		search_texts = {}
		private.search_texts = search_texts
	end
	
	rom.ImGui.Text("Search by: (lua string pattern)")
	for _, field in ipairs(perk_fields) do
		local active = enable_fields[field]
		if active == nil then active = false end
		active = rom.ImGui.Checkbox(field, active)
		enable_fields[field] = active
		rom.ImGui.SameLine()
		local text = search_texts[field] or ""
		rom.ImGui.PushStyleColor(rom.ImGuiCol.FrameBg,0,0,0,0)
		text = rom.ImGui.InputText("##" .. field, text, 128)
		rom.ImGui.PopStyleColor()
		search_texts[field] = text
	end
	
	rom.ImGui.Separator()
	
	local player = rom.game.player
	if player then
		local soul = player.soul
		
		local force_remove = rom.ImGui.IsKeyDown(rom.ImGuiKeyMod.Shift)
		if force_remove then
			rom.ImGui.TextColored(1, 1, 0, 1, "SHIFT is held, perks will be force removed.")
		else
			rom.ImGui.Text("Most perks can't be detected as active, hold SHIFT to force remove.")
		end
		
		rom.ImGui.Text("Found Perks:")
		
		for row, perk in ipairs(perks) do
			local pass = true
			for _, field in ipairs(perk_fields) do
				local text = search_texts[field]
				if #text > 0 then
					local status, result = pcall(string.find, perk[field], text)
					if not status or not result then
						pass = false
						break
					end
				end
			end
			
			if pass then
				local active = has_perk(soul, perk)
				local _, clicked = rom.ImGui.Checkbox("##" .. tostring(row), active or force_remove)
				for _, field in ipairs(perk_fields) do
					if enable_fields[field] then
						rom.ImGui.SameLine()
						local pf = perk[field] or ""
						local x = rom.ImGui.CalcTextSize(pf)
						if rom.ImGui.Selectable(pf .. "##" .. field .. '#' .. tostring(row), false, 0, x, 0) then
							rom.ImGui.SetClipboardText(pf)
						end
					end
				end
				if clicked then
					if active or force_remove then
						soul:RemovePerk(perk.perk_id)
					else
						soul:AddPerk(perk.perk_id)
					end
				end
			end
		end
	else
		rom.ImGui.TextColored(1, 0, 0, 1, "Player has not yet loaded.")
	end
end

rom.gui.add_to_menu_bar( function()
	local show_menu = rawget(private, 'show_menu')
	if show_menu == nil then show_menu = false end
	show_menu = rom.ImGui.Checkbox("Show Menu", show_menu)
	private.show_menu = show_menu
	if show_menu then draw_menu() end
end )

rom.gui.add_imgui( function()
	if rom.ImGui.Begin("Perk Menu") then
		draw_menu()
		rom.ImGui.End()
	end
end )