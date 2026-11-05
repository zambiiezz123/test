--[[
    Crescent SaveManager
    Same functions and the same config files as LinoriaLib's SaveManager
    (<folder>/settings/<name>.json + autoload.txt), so configs saved with Linoria
    load here and the other way round.
]]

local httpService = game:GetService('HttpService')
local genv = (type(getgenv) == 'function' and getgenv()) or _G

local SaveManager = {} do
    SaveManager.Folder = 'LinoriaLibSettings'
    SaveManager.Ignore = {}

    local function lib() return SaveManager.Library or genv.Library end
    local function toggles() local L = lib(); return (L and L.Toggles) or genv.Toggles or {} end
    local function options() local L = lib(); return (L and L.Options) or genv.Options or {} end

    local function fs(name) local f = genv[name]; if type(f) == 'function' then return f end; return nil end
    local function isfolder_(p) local f = fs('isfolder') or isfolder; return f and f(p) end
    local function isfile_(p) local f = fs('isfile') or isfile; return f and f(p) end

    SaveManager.Parser = {
        Toggle = {
            Save = function(idx, object)
                return { type = 'Toggle', idx = idx, value = object.Value }
            end,
            Load = function(idx, data)
                local t = toggles()[idx]
                if t then t:SetValue(data.value) end
            end,
        },
        Slider = {
            Save = function(idx, object)
                return { type = 'Slider', idx = idx, value = tostring(object.Value) }
            end,
            Load = function(idx, data)
                local o = options()[idx]
                if o then o:SetValue(data.value) end
            end,
        },
        Dropdown = {
            Save = function(idx, object)
                return { type = 'Dropdown', idx = idx, value = object.Value, mutli = object.Multi }
            end,
            Load = function(idx, data)
                local o = options()[idx]
                if o then o:SetValue(data.value) end
            end,
        },
        ColorPicker = {
            Save = function(idx, object)
                return { type = 'ColorPicker', idx = idx, value = object.Value:ToHex(), transparency = object.Transparency }
            end,
            Load = function(idx, data)
                local o = options()[idx]
                if o then o:SetValueRGB(Color3.fromHex(data.value), data.transparency) end
            end,
        },
        KeyPicker = {
            Save = function(idx, object)
                return { type = 'KeyPicker', idx = idx, mode = object.Mode, key = object.Value }
            end,
            Load = function(idx, data)
                local o = options()[idx]
                if o then o:SetValue({ data.key, data.mode }) end
            end,
        },
        Input = {
            Save = function(idx, object)
                return { type = 'Input', idx = idx, text = object.Value }
            end,
            Load = function(idx, data)
                local o = options()[idx]
                if o and type(data.text) == 'string' then o:SetValue(data.text) end
            end,
        },
    }

    function SaveManager:SetIgnoreIndexes(list)
        for _, key in next, list do self.Ignore[key] = true end
    end

    function SaveManager:SetFolder(folder)
        self.Folder = folder
        self:BuildFolderTree()
    end

    function SaveManager:Save(name)
        if not name then return false, 'no config file is selected' end
        local fullPath = self.Folder .. '/settings/' .. name .. '.json'
        local data = { objects = {} }
        for idx, toggle in next, toggles() do
            if not self.Ignore[idx] and self.Parser[toggle.Type] then
                table.insert(data.objects, self.Parser[toggle.Type].Save(idx, toggle))
            end
        end
        for idx, option in next, options() do
            if self.Parser[option.Type] and not self.Ignore[idx] then
                table.insert(data.objects, self.Parser[option.Type].Save(idx, option))
            end
        end
        local success, encoded = pcall(httpService.JSONEncode, httpService, data)
        if not success then return false, 'failed to encode data' end
        self:BuildFolderTree()
        local ok, err = pcall(writefile, fullPath, encoded)
        if not ok then return false, 'could not write the file: ' .. tostring(err) end
        return true
    end

    function SaveManager:Load(name)
        if not name then return false, 'no config file is selected' end
        local file = self.Folder .. '/settings/' .. name .. '.json'
        local okFile, exists = pcall(isfile_, file)
        if not okFile or not exists then return false, 'invalid file' end
        local success, decoded = pcall(function() return httpService:JSONDecode(readfile(file)) end)
        if not success or type(decoded) ~= 'table' or type(decoded.objects) ~= 'table' then return false, 'decode error' end
        for _, option in next, decoded.objects do
            if type(option) == 'table' and self.Parser[option.type] then
                -- each on its own thread so one slow or broken option can't stop the rest
                task.spawn(function() self.Parser[option.type].Load(option.idx, option) end)
            end
        end
        return true
    end

    function SaveManager:Delete(name)
        if not name then return false, 'no config file is selected' end
        local file = self.Folder .. '/settings/' .. name .. '.json'
        if not isfile_(file) then return false, 'invalid file' end
        local del = fs('delfile') or delfile
        if not del then return false, 'this executor cannot delete files' end
        local ok, err = pcall(del, file)
        if not ok then return false, tostring(err) end
        return true
    end

    function SaveManager:IgnoreThemeSettings()
        self:SetIgnoreIndexes({
            'BackgroundColor', 'MainColor', 'AccentColor', 'OutlineColor', 'FontColor',
            'ThemeManager_ThemeList', 'ThemeManager_CustomThemeList', 'ThemeManager_CustomThemeName',
            'ThemeManager_Accent', 'ThemeManager_Preset', 'ThemeManager_Font', 'ThemeManager_Scale',
            'ThemeManager_Lowercase', 'ThemeManager_Animations', 'ThemeManager_Moon', 'ThemeManager_Stars',
            'ThemeManager_Cursor', 'ThemeManager_Keybinds',
        })
    end

    function SaveManager:BuildFolderTree()
        local paths = { self.Folder, self.Folder .. '/themes', self.Folder .. '/settings' }
        for i = 1, #paths do
            local str = paths[i]
            pcall(function()
                if not isfolder_(str) then makefolder(str) end
            end)
        end
    end

    function SaveManager:RefreshConfigList()
        local ok, list = pcall(listfiles, self.Folder .. '/settings')
        if not ok or type(list) ~= 'table' then return {} end
        local out = {}
        for i = 1, #list do
            local file = list[i]
            if file:sub(-5) == '.json' then
                local pos = file:find('.json', 1, true)
                local start = pos
                local char = file:sub(pos, pos)
                while char ~= '/' and char ~= '\\' and char ~= '' do
                    pos = pos - 1
                    char = file:sub(pos, pos)
                end
                if char == '/' or char == '\\' then
                    table.insert(out, file:sub(pos + 1, start - 1))
                end
            end
        end
        return out
    end

    function SaveManager:SetLibrary(library)
        self.Library = library
    end

    function SaveManager:LoadAutoloadConfig()
        local path = self.Folder .. '/settings/autoload.txt'
        local okFile, exists = pcall(isfile_, path)
        if okFile and exists then
            local name = readfile(path)
            local success, err = self:Load(name)
            if not success then
                return self.Library:Notify('Failed to load autoload config: ' .. err)
            end
            self.Library:Notify(string.format('Auto loaded config %q', name))
        end
    end

    function SaveManager:BuildConfigSection(tab)
        assert(self.Library, 'Must set SaveManager.Library')
        local Opts = options()

        local section = tab:AddRightGroupbox('Configuration')

        section:AddInput('SaveManager_ConfigName', { Text = 'Config name' })
        section:AddDropdown('SaveManager_ConfigList', { Text = 'Config list', Values = self:RefreshConfigList(), AllowNull = true })

        section:AddDivider()

        section:AddButton('Create config', function()
            local name = Opts.SaveManager_ConfigName.Value
            if name:gsub(' ', '') == '' then
                return self.Library:Notify('Invalid config name (empty)', 2)
            end
            local success, err = self:Save(name)
            if not success then
                return self.Library:Notify('Failed to save config: ' .. err)
            end
            self.Library:Notify(string.format('Created config %q', name))
            Opts.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
            Opts.SaveManager_ConfigList:SetValue(nil)
        end):AddButton('Load config', function()
            local name = Opts.SaveManager_ConfigList.Value
            local success, err = self:Load(name)
            if not success then
                return self.Library:Notify('Failed to load config: ' .. err)
            end
            self.Library:Notify(string.format('Loaded config %q', name))
        end)

        section:AddButton('Overwrite config', function()
            local name = Opts.SaveManager_ConfigList.Value
            local success, err = self:Save(name)
            if not success then
                return self.Library:Notify('Failed to overwrite config: ' .. err)
            end
            self.Library:Notify(string.format('Overwrote config %q', name))
        end):AddButton('Delete config', function()
            local name = Opts.SaveManager_ConfigList.Value
            local success, err = self:Delete(name)
            if not success then
                return self.Library:Notify('Failed to delete config: ' .. err)
            end
            self.Library:Notify(string.format('Deleted config %q', name))
            Opts.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
            Opts.SaveManager_ConfigList:SetValue(nil)
        end)

        section:AddButton('Refresh list', function()
            Opts.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
            Opts.SaveManager_ConfigList:SetValue(nil)
        end):AddButton('Set as autoload', function()
            local name = Opts.SaveManager_ConfigList.Value
            if not name then
                return self.Library:Notify('Pick a config first', 2)
            end
            writefile(self.Folder .. '/settings/autoload.txt', name)
            SaveManager.AutoloadLabel:SetText('Current autoload config: ' .. name)
            self.Library:Notify(string.format('Set %q to auto load', name))
        end)

        SaveManager.AutoloadLabel = section:AddLabel('Current autoload config: none', true)

        local okFile, exists = pcall(isfile_, self.Folder .. '/settings/autoload.txt')
        if okFile and exists then
            local name = readfile(self.Folder .. '/settings/autoload.txt')
            SaveManager.AutoloadLabel:SetText('Current autoload config: ' .. name)
        end

        SaveManager:SetIgnoreIndexes({ 'SaveManager_ConfigList', 'SaveManager_ConfigName' })
    end
end

return SaveManager
