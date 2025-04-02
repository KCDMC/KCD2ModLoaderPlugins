local key_binding = rom.ImGuiKey.F5;

local save = function()
	rom.game.Game.SaveGameViaResting()
end

rom.gui.add_always_draw_imgui(function()
	if rom.ImGui.IsKeyPressed(key_binding) then
		save()
	end
end)

rom.gui.add_to_menu_bar(function()
	if rom.ImGui.Button('Quicksave') then
		save()
	end
end)