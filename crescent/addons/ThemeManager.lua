--[[
    Crescent ThemeManager
    Same entry points as LinoriaLib's ThemeManager (SetLibrary, SetFolder,
    ApplyToTab, ApplyToGroupbox). Builds a "Theme" box: accent colour, presets,
    font, scale, lowercase text, animations, moon, stars, crosshair cursor and the
    keybind list. Changes apply live and are saved to Crescent/settings.json, so
    every game in the hub shares one look.
]]

local ThemeManager = {} do
    ThemeManager.Folder = 'LinoriaLibSettings'
    ThemeManager.Library = nil

    function ThemeManager:SetLibrary(library)
        self.Library = library
    end

    function ThemeManager:SetFolder(folder)
        self.Folder = folder
        self:BuildFolderTree()
    end

    function ThemeManager:BuildFolderTree()
        for _, p in ipairs({ self.Folder, self.Folder .. '/themes' }) do
            pcall(function()
                if not isfolder(p) then makefolder(p) end
            end)
        end
    end

    function ThemeManager:ApplyToTab(tab)
        assert(self.Library, 'Must set ThemeManager.Library first!')
        local groupbox = tab:AddLeftGroupbox('Theme')
        self:ApplyToGroupbox(groupbox)
    end

    function ThemeManager:ApplyToGroupbox(groupbox)
        assert(self.Library, 'Must set ThemeManager.Library first!')
        local L = self.Library
        if type(L.SetPref) ~= 'function' then
            groupbox:AddLabel('Theme settings need the Crescent library.', true)
            return
        end

        local P = L.Prefs
        local Opts = L.Options
        local ready = false

        local presetNames, presetColor = {}, {}
        for _, p in ipairs(L.Presets) do
            presetNames[#presetNames + 1] = p[1]
            presetColor[p[1]] = p[2]
        end

        groupbox:AddLabel('Accent'):AddColorPicker('ThemeManager_Accent', { Default = L.Theme.Accent, Title = 'Accent' })
        groupbox:AddDropdown('ThemeManager_Preset', {
            Text = 'Preset', Values = presetNames, Default = presetColor[P.preset] and P.preset or nil, AllowNull = true,
            Tooltip = 'Accent colour presets. Pick your own colour with the swatch above.',
        })
        groupbox:AddDropdown('ThemeManager_Font', { Text = 'Font', Values = L.FontNames, Default = P.font })
        groupbox:AddSlider('ThemeManager_Scale', { Text = 'Menu scale', Default = P.scale, Min = 70, Max = 140, Rounding = 0, Suffix = '%' })
        groupbox:AddToggle('ThemeManager_Lowercase', { Text = 'Lowercase text', Default = P.lowercase })
        groupbox:AddToggle('ThemeManager_Animations', { Text = 'Animations', Default = P.animations })
        groupbox:AddToggle('ThemeManager_Moon', { Text = 'Moon', Default = P.moon })
        groupbox:AddToggle('ThemeManager_Stars', { Text = 'Stars', Default = P.stars })
        groupbox:AddToggle('ThemeManager_Cursor', { Text = 'Crosshair cursor', Default = P.cursor, Tooltip = 'Draws a crosshair at the mouse while the menu is open.' })
        groupbox:AddToggle('ThemeManager_Keybinds', { Text = 'Keybind list', Default = P.keybinds, Tooltip = 'A small list of the keybinds that are on. Drag it by its title.' })
        groupbox:AddButton('Reset theme', function()
            Opts.ThemeManager_Preset:SetValue('Crescent')
            Opts.ThemeManager_Font:SetValue('Gotham')
            Opts.ThemeManager_Scale:SetValue(100)
            for id, v in pairs({
                ThemeManager_Lowercase = true, ThemeManager_Animations = true, ThemeManager_Moon = true,
                ThemeManager_Stars = true, ThemeManager_Cursor = true, ThemeManager_Keybinds = false,
            }) do
                local t = L.Toggles[id]
                if t then t:SetValue(v) end
            end
            L:ResetPrefs()
            L:Notify('Theme reset', 2)
        end)

        local applyingPreset = false
        Opts.ThemeManager_Accent:OnChanged(function(c)
            if not ready then return end
            L:SetPref('accent', c)
            if not applyingPreset then
                local cur = Opts.ThemeManager_Preset.Value
                if cur and presetColor[cur] and presetColor[cur]:ToHex() ~= c:ToHex() then
                    Opts.ThemeManager_Preset:SetValue(nil)
                end
            end
        end)
        Opts.ThemeManager_Preset:OnChanged(function(name)
            if not ready then return end
            L:SetPref('preset', name)
            local c = name and presetColor[name]
            if c then
                applyingPreset = true
                Opts.ThemeManager_Accent:SetValueRGB(c)
                applyingPreset = false
            end
        end)
        Opts.ThemeManager_Font:OnChanged(function(v) if ready and v then L:SetPref('font', v) end end)
        Opts.ThemeManager_Scale:OnChanged(function(v) if ready then L:SetPref('scale', v) end end)
        for id, key in pairs({
            ThemeManager_Lowercase = 'lowercase', ThemeManager_Animations = 'animations', ThemeManager_Moon = 'moon',
            ThemeManager_Stars = 'stars', ThemeManager_Cursor = 'cursor', ThemeManager_Keybinds = 'keybinds',
        }) do
            L.Toggles[id]:OnChanged(function(v) if ready then L:SetPref(key, v) end end)
        end
        ready = true
    end

    -- Linoria names some scripts call; kept so they don't error.
    function ThemeManager:CreateThemeManager(groupbox) return self:ApplyToGroupbox(groupbox) end
    function ThemeManager:LoadDefault() end
    function ThemeManager:SaveDefault() end
    function ThemeManager:ThemeUpdate()
        if self.Library and self.Library.UpdateColorsUsingRegistry then self.Library:UpdateColorsUsingRegistry() end
    end
    function ThemeManager:ApplyTheme(name)
        local L = self.Library
        if not L or not L.Presets then return end
        for _, p in ipairs(L.Presets) do
            if p[1] == name and L.SetPref then L:SetPref('accent', p[2]) end
        end
    end
end

return ThemeManager
