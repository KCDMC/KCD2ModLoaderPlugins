---@diagnostic disable: lowercase-global

local envy = rom.mods['LuaENVY-ENVY']
envy.auto()

local perk_fields = { "perk_id", "perk_name", "perk_ui_name"}

local function load_perks()
	if rom.game == nil then return end
	-- load perk database
	local databaseName = "perk"
	rom.game.Database.LoadTable(databaseName)
	local n = rom.game.Database.GetTableInfo(databaseName).LineCount
	local database = {}
	for row = 1, n do
		local entry = rom.game.Database.GetTableLine(databaseName, row - 1)
		--print(row, entry)
		--for field,value in pairs(entry) do
		--	print('',field,value)
		--end
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
		private.enable_fields = enable_fields
	end
	
	local search_texts = rawget(private, 'search_texts')
	if search_texts == nil then
		search_texts = {}
		private.search_texts = search_texts
	end
	
	local player = rom.game.player
	if player then
		local soul = player.soul
		rom.ImGui.Text("Search by: (lua string pattern)")
		for _, field in ipairs(perk_fields) do
		
			local active = enable_fields[field]
			if active == nil then active = true end
			active = rom.ImGui.Checkbox(field, active)
			enable_fields[field] = active
			rom.ImGui.SameLine()
			local text = search_texts[field] or ""
			text = rom.ImGui.InputText("##" .. field, text, 128)
			search_texts[field] = text
		end
		rom.ImGui.Text("Most perks can't be detected as active, hold SHIFT to force remove.")
		for row, perk in ipairs(perks) do
			local pass = false
			for _, field in ipairs(perk_fields) do
				if enable_fields[field] then
					local data = perk[field]
					if data ~= "" and data ~= nil then
						pass = true
						local text = search_texts[field] or ""
						if #text > 0 then
							if not string.find(tostring(perk[field] or ""), text) then
								pass = false
								break
							end
						end
					end
				end
			end

			if pass then
				local perk_id = perk.perk_id
				local active = soul:HasPerk(perk_id, false)
				local _, clicked = rom.ImGui.Checkbox("##" .. tostring(row), active)
				for _, field in ipairs(perk_fields) do
					if enable_fields[field] then
						rom.ImGui.SameLine()
						rom.ImGui.Text(perk[field])
					end
				end
				if clicked then
					if active or rom.ImGui.IsKeyDown(rom.ImGuiKeyMod.Shift) then
						soul:RemovePerk(perk_id)
					else
						soul:AddPerk(perk_id)
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