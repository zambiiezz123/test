--[[
    Remote Spy  —  sleek client-side RemoteEvent / RemoteFunction inspector
    ------------------------------------------------------------------------
    • Hooks __namecall to capture every FireServer / InvokeServer call.
    • Live feed on the left, full details on the right.
    • Copy the exact call as a ready-to-run Lua snippet, or copy just the path.
    • Shows where each remote lives in the game tree (GetFullName + a safe
      indexed accessor you can paste straight back into an executor).
    • Draggable window, Pause / Clear, live search filter, per-remote ignore.
    • Toggle key: Right Shift (change TOGGLE_KEY below). Close button unloads.
    • Looks like the Crescent menu and follows its saved UI settings (accent,
      font, lowercase). No image assets: every icon is frames or text.

    Requires an executor with hookmetamethod + getnamecallmethod (Synapse,
    Script-Ware, Wave, Delta, Solara, etc.). setclipboard is used for copy.
]]

-- ===========================================================================
-- 0. Clean up any previous instance
-- ===========================================================================
if getgenv().RemoteSpy_Unload then
    pcall(getgenv().RemoteSpy_Unload)
    task.wait(0.05)
end

-- ===========================================================================
-- 1. Config / services
-- ===========================================================================
local TOGGLE_KEY   = Enum.KeyCode.RightShift   -- show / hide the window
local MAX_ROWS     = 300                        -- feed cap before oldest trims
local SAVE_FILE    = 'RemoteSpy_dump.txt'       -- deduped live dump of UNIQUE calls

local Players    = game:GetService('Players')
local UIS        = game:GetService('UserInputService')
local RunService = game:GetService('RunService')

local LocalPlayer = Players.LocalPlayer

-- Executor feature probes (degrade gracefully) -----------------------------
local clipboard   = (setclipboard or (syn and syn.write_clipboard) or toclipboard or function() end)
local protectGui  = (syn and syn.protect_gui) or (getgenv().protect_gui) or function() end
local hiddenUI    = (gethui and gethui()) or (get_hidden_gui and get_hidden_gui())
local getNCMethod = getnamecallmethod
local hookMeta    = hookmetamethod
local checkCaller = checkcaller or function() return false end

-- Persist the open/close key across executions via the executor file API.
local KEY_FILE = 'RemoteSpy_togglekey.txt'
local function saveToggleKey()
    pcall(function() if writefile then writefile(KEY_FILE, TOGGLE_KEY.Name) end end)
end
do  -- load a previously-saved key, if any
    local ok, name = pcall(function()
        return (isfile and isfile(KEY_FILE)) and readfile(KEY_FILE) or nil
    end)
    if ok and type(name) == 'string' and name ~= '' then
        local ok2, keyEnum = pcall(function() return Enum.KeyCode[name] end)
        if ok2 and typeof(keyEnum) == 'EnumItem' then TOGGLE_KEY = keyEnum end
    end
end

if not (hookMeta and getNCMethod) then
    warn('[RemoteSpy] This executor lacks hookmetamethod / getnamecallmethod. Aborting.')
    return
end

-- ===========================================================================
-- 2. Theme  (the Crescent look: black, white accent, square corners)
-- ===========================================================================
-- Colours and UI settings follow the user's Crescent menu: the live library
-- (getgenv().Library, when it is Crescent) or else Crescent/settings.json.
-- Everything falls back to Crescent's defaults.
local TweenService = game:GetService('TweenService')
local HttpService  = game:GetService('HttpService')

local rgb = Color3.fromRGB
local Theme = {
    Window       = rgb(12, 12, 14),
    Panel        = rgb(8, 8, 9),
    Groupbox     = rgb(15, 15, 17),
    Element      = rgb(22, 22, 25),
    ElementHover = rgb(31, 31, 35),
    Border       = rgb(34, 34, 39),
    BorderLight  = rgb(62, 62, 70),
    Outline      = rgb(0, 0, 0),
    Text         = rgb(230, 230, 234),
    TextDim      = rgb(148, 148, 156),
    TextMuted    = rgb(88, 88, 96),
    Accent       = rgb(242, 242, 246),
    Moon         = rgb(31, 31, 36),
    Risk         = rgb(255, 96, 96),
}
local Prefs = { font = 'Gotham', lowercase = true, animations = true, moon = true }

do
    local fromLibrary = false
    pcall(function()
        local L = getgenv().Library
        if type(L) == 'table' and L.Version ~= nil and type(L.Theme) == 'table' then
            for k in pairs(Theme) do
                if typeof(L.Theme[k]) == 'Color3' then Theme[k] = L.Theme[k] end
            end
            if type(L.Prefs) == 'table' then
                for k, v in pairs(Prefs) do
                    if type(L.Prefs[k]) == type(v) then Prefs[k] = L.Prefs[k] end
                end
            end
            fromLibrary = true
        end
    end)
    if not fromLibrary then
        pcall(function()
            local file = 'Crescent/settings.json'
            if not (isfile and readfile and isfile(file)) then return end
            local data = HttpService:JSONDecode(readfile(file))
            if type(data) ~= 'table' then return end
            for k, v in pairs(Prefs) do
                if type(data[k]) == type(v) then Prefs[k] = data[k] end
            end
            if type(data.accent) == 'string' then
                local ok, c = pcall(Color3.fromHex, data.accent)
                if ok and typeof(c) == 'Color3' then Theme.Accent = c end
            end
        end)
    end
end
Theme.AccentDim = Theme.Accent:Lerp(Theme.Element, 0.55)

-- Fonts: the Crescent font family, Regular for body text, Medium for titles.
local Fonts = {}
do
    local FONT_ENUMS = {
        ['Gotham'] = 'Gotham', ['Builder Sans'] = 'BuilderSans', ['Roboto'] = 'Roboto',
        ['Source Sans'] = 'SourceSans', ['Ubuntu'] = 'Ubuntu', ['Code'] = 'Code',
    }
    local family
    pcall(function() family = Font.fromEnum(Enum.Font[FONT_ENUMS[Prefs.font] or 'Gotham']).Family end)
    family = family or 'rbxasset://fonts/families/GothamSSm.json'
    local function face(weight)
        local ok, f = pcall(Font.new, family, weight, Enum.FontStyle.Normal)
        if ok and f then return f end
        return Font.fromEnum(Enum.Font.Gotham)
    end
    Fonts.body = face(Enum.FontWeight.Regular)
    Fonts.bold = face(Enum.FontWeight.Medium)
    local ok, mono = pcall(function() return Font.fromEnum(Enum.Font.RobotoMono) end)
    Fonts.mono = (ok and mono) or Font.fromEnum(Enum.Font.Code)
end

-- UI labels follow Crescent's lowercase setting. Remote names, paths and
-- captured code never go through this.
local function shown(s)
    s = tostring(s == nil and '' or s)
    if Prefs.lowercase then return s:lower() end
    return s
end

local function tween(inst, t, props)
    if not Prefs.animations or t <= 0 then
        for k, v in pairs(props) do inst[k] = v end
        return
    end
    local ok, tw = pcall(TweenService.Create, TweenService, inst,
        TweenInfo.new(t, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), props)
    if ok and tw then
        tw:Play()
    else
        for k, v in pairs(props) do inst[k] = v end
    end
end

-- One helper creates every instance with Crescent's defaults: no border, body
-- font at 13, Text colour, see-through text backgrounds, 1px miter strokes.
local GUI_CLASS  = { Frame = true, ScrollingFrame = true, TextLabel = true, TextButton = true, TextBox = true }
local TEXT_CLASS = { TextLabel = true, TextButton = true, TextBox = true }
local function New(class, props)
    local o = Instance.new(class)
    if GUI_CLASS[class] then
        o.BorderSizePixel = 0
        if TEXT_CLASS[class] then
            o.BackgroundTransparency = 1
            o.FontFace = Fonts.body
            o.TextSize = 13
            o.TextColor3 = Theme.Text
            o.Text = ''
            if class == 'TextBox' then o.ClearTextOnFocus = false end
        end
        if class == 'TextButton' then o.AutoButtonColor = false end
    elseif class == 'UIStroke' then
        o.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        o.Thickness = 1
        o.LineJoinMode = Enum.LineJoinMode.Miter
    end
    local parent
    for k, v in pairs(props or {}) do
        if k == 'Parent' then
            parent = v
        elseif k == 'Bold' then
            if v then o.FontFace = Fonts.bold end
        else
            o[k] = v
        end
    end
    if parent then o.Parent = parent end
    return o
end
local function stroke(parent, color)
    return New('UIStroke', { Color = color or Theme.Border, Parent = parent })
end
local function line(parent, pos, size)
    return New('Frame', { Position = pos, Size = size, BackgroundColor3 = Theme.Border, Parent = parent })
end

-- ===========================================================================
-- 3. Value -> code serialisation (the "copy" magic)
-- ===========================================================================

-- Safe indexed path back to an instance: game:GetService("X")["A"]["B"]
local function instancePath(obj)
    local parts, cur = {}, obj
    for _ = 1, 50 do
        if not cur or cur == game then break end
        if cur.Parent == game then
            table.insert(parts, 1, string.format('game:GetService(%q)', cur.ClassName))
            break
        end
        table.insert(parts, 1, string.format('[%q]', cur.Name))
        cur = cur.Parent
    end
    if #parts == 0 then return 'nil --[[ unreachable ]]' end
    return table.concat(parts)
end

local function serialize(v, seen, depth)
    seen  = seen or {}
    depth = depth or 0
    local t = typeof(v)

    if t == 'string' then
        return string.format('%q', v)
    elseif t == 'number' or t == 'boolean' then
        return tostring(v)
    elseif t == 'nil' then
        return 'nil'
    elseif t == 'Instance' then
        return instancePath(v)
    elseif t == 'Vector3' then
        return string.format('Vector3.new(%s, %s, %s)', v.X, v.Y, v.Z)
    elseif t == 'Vector2' then
        return string.format('Vector2.new(%s, %s)', v.X, v.Y)
    elseif t == 'CFrame' then
        return string.format('CFrame.new(%s)', table.concat({ v:GetComponents() }, ', '))
    elseif t == 'Color3' then
        return string.format('Color3.fromRGB(%d, %d, %d)',
            math.floor(v.R * 255 + 0.5), math.floor(v.G * 255 + 0.5), math.floor(v.B * 255 + 0.5))
    elseif t == 'UDim2' then
        return string.format('UDim2.new(%s, %s, %s, %s)',
            v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset)
    elseif t == 'EnumItem' then
        return tostring(v)
    elseif t == 'table' then
        if seen[v] then return '"<cyclic table>"' end
        if depth > 4 then return '"<...>"' end
        seen[v] = true
        local isArray = true
        local n = 0
        for k in pairs(v) do
            n = n + 1
            if type(k) ~= 'number' then isArray = false end
        end
        if n == 0 then return '{}' end
        local indent    = string.rep('    ', depth + 1)
        local endIndent = string.rep('    ', depth)
        local out = {}
        if isArray then
            for _, item in ipairs(v) do
                out[#out + 1] = indent .. serialize(item, seen, depth + 1)
            end
        else
            for k, item in pairs(v) do
                local key = (type(k) == 'string' and k:match('^%a[%w_]*$'))
                    and k .. ' = '
                    or string.format('[%s] = ', serialize(k, seen, depth + 1))
                out[#out + 1] = indent .. key .. serialize(item, seen, depth + 1)
            end
        end
        return '{\n' .. table.concat(out, ',\n') .. '\n' .. endIndent .. '}'
    else
        return string.format('%q --[[ %s ]]', tostring(v), t)
    end
end

-- Full reproduction snippet for one captured call
local function buildSnippet(entry)
    local argParts = {}
    for i = 1, entry.argc do
        argParts[i] = serialize(entry.args[i])
    end
    local argStr = table.concat(argParts, ', ')
    local remoteExpr = instancePath(entry.remote)
    return string.format(
        '-- %s  (%s)\nlocal remote = %s\nremote:%s(%s)',
        entry.name, entry.className, remoteExpr, entry.method, argStr
    )
end

-- ---- Deduped live dump (every UNIQUE remote call, auto-saved to a file) ------
-- Keys each capture by method + remote name + a coarse ARG SHAPE (Instance ->
-- ClassName, string/number/bool/enum -> value, table -> "table"), so a remote
-- that re-fires the same call collapses to ONE entry, but genuine variants (e.g.
-- different move names) each stay. New uniques append to SAVE_FILE live + feed a
-- "Copy All" buffer. Incoming (OnClientEvent) records are commented, outgoing are
-- paste-ready.
local dumpSigs  = {}   -- signature -> true
local dumpParts = {}   -- ordered unique records
local function entrySig(entry)
    local p = { entry.method, tostring(entry.name), tostring(entry.argc) }
    for i = 1, entry.argc do
        local v = entry.args[i]
        local t = typeof(v)
        if t == 'Instance' then p[#p + 1] = v.ClassName
        elseif t == 'string' or t == 'number' or t == 'boolean' or t == 'EnumItem' then p[#p + 1] = tostring(v)
        elseif t == 'table' then p[#p + 1] = 'table'
        else p[#p + 1] = t end
    end
    return table.concat(p, '|')
end
local function buildRecord(entry)
    local argParts = {}
    for i = 1, entry.argc do argParts[i] = serialize(entry.args[i]) end
    local argStr = table.concat(argParts, ', ')
    local path = instancePath(entry.remote)
    if entry.method == 'OnClientEvent' then -- incoming (server -> client)
        return string.format('-- IN   %s  (%s)\n-- %s\n-- args: %s', entry.name, entry.className, path, argStr)
    end
    return string.format('-- OUT  %s  (%s)\nlocal remote = %s\nremote:%s(%s)', entry.name, entry.className, path, entry.method, argStr)
end
local function recordUnique(entry)
    if dumpSigs[entrySig(entry)] then return false end
    dumpSigs[entrySig(entry)] = true
    dumpParts[#dumpParts + 1] = buildRecord(entry)
    pcall(function() if writefile then writefile(SAVE_FILE, table.concat(dumpParts, '\n\n')) end end)
    return true
end

-- ===========================================================================
-- 4. UI
-- ===========================================================================
local W, H     = 720, 460       -- window size
local HEADER_H = 28             -- Crescent's header height
local ROW_H    = 32             -- one call in the feed

local gui = Instance.new('ScreenGui')
gui.Name = 'RemoteSpy_' .. tostring(math.random(1000, 9999))
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 9999
pcall(function() gui.Parent = hiddenUI or LocalPlayer:WaitForChild('PlayerGui') end)
pcall(protectGui, gui)
if not gui.Parent then gui.Parent = LocalPlayer:WaitForChild('PlayerGui') end

-- Window: an outer frame filled with the border colour, the window 1px inside
-- it, and a black 1px outline around the lot.
local root = New('Frame', {
    Name = 'Root', Parent = gui,
    Size = UDim2.fromOffset(W, H),
    Position = UDim2.fromScale(0.5, 0.5),
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundColor3 = Theme.Border,
})
stroke(root, Theme.Outline)
local winScale = New('UIScale', { Parent = root })   -- for the scale-in on open
local main = New('Frame', {
    Name = 'Main', Parent = root,
    Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 1, -2),
    BackgroundColor3 = Theme.Window, ClipsDescendants = true,
})

local function popIn()
    if not Prefs.animations then return end
    winScale.Scale = 0.96
    tween(winScale, 0.2, { Scale = 1 })
end

-- Crescent moon: a circle with a background-coloured circle over its upper
-- right. Frames only, no image asset.
local function crescent(parent, moonColor, cutColor)
    local moon = New('Frame', { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = moonColor, Parent = parent })
    New('UICorner', { CornerRadius = UDim.new(1, 0), Parent = moon })
    local cut = New('Frame', {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5 + 0.28, 0.5 - 0.29),
        Size = UDim2.fromScale(1.03, 1.03), BackgroundColor3 = cutColor, Parent = moon,
    })
    New('UICorner', { CornerRadius = UDim.new(1, 0), Parent = cut })
    return moon
end

-- The big dim moon Crescent draws behind its content (off with its "moon"
-- setting). `parent` must clip and be Panel-coloured.
local function moonBehind(parent)
    if not Prefs.moon then return end
    local moonBox = New('Frame', {
        Parent = parent, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.6, 0.6),
    })
    New('UIAspectRatioConstraint', { Parent = moonBox, AspectRatio = 1 })
    local moon = crescent(moonBox, Theme.Moon, Theme.Panel)
    moon.Size = UDim2.fromScale(1, 1)
    moon.Position = UDim2.fromScale(0.5825, 0.4125)
    New('UIGradient', { Parent = moon, Rotation = 35, Color = ColorSequence.new(Color3.new(1, 1, 1), rgb(130, 130, 140)) })
end

-- Groupbox: see-through box with 1px borders; the title breaks the top line.
-- Returns the box and the padded content frame inside it.
local function groupbox(parent, title, props)
    props.Parent = parent
    props.BackgroundColor3 = Theme.Groupbox
    props.BackgroundTransparency = 0.3
    local box = New('Frame', props)
    line(box, UDim2.new(), UDim2.new(0, 1, 1, 0))                       -- left
    line(box, UDim2.new(1, -1, 0, 0), UDim2.new(0, 1, 1, 0))            -- right
    line(box, UDim2.new(0, 0, 1, -1), UDim2.new(1, 0, 0, 1))            -- bottom
    line(box, UDim2.new(), UDim2.fromOffset(6, 1))                      -- top, before the title
    local topRight = line(box, UDim2.new(), UDim2.new(1, 0, 0, 1))      -- top, after the title
    local label = New('TextLabel', {
        Parent = box, Position = UDim2.fromOffset(9, -7), Size = UDim2.fromOffset(0, 14),
        AutomaticSize = Enum.AutomaticSize.X, Bold = true, Text = shown(title),
    })
    local function fit()
        local w = label.AbsoluteSize.X / math.max(winScale.Scale, 0.01)
        local x = math.floor(9 + w + 5 + 0.5)
        topRight.Position = UDim2.fromOffset(x, 0)
        topRight.Size = UDim2.new(1, -x, 0, 1)
    end
    label:GetPropertyChangedSignal('AbsoluteSize'):Connect(fit)
    fit()
    local content = New('Frame', {
        Parent = box, BackgroundTransparency = 1,
        Position = UDim2.fromOffset(8, 14), Size = UDim2.new(1, -16, 1, -22),
    })
    return box, content
end

-- Button: Element box, Border stroke; hover lightens both, a click flashes the
-- stroke to the accent. An "active" button (pause while paused) keeps an
-- accent stroke.
local Buttons = {}
local function button(parent, text, order, size)
    local b = New('TextButton', {
        Parent = parent, LayoutOrder = order, Size = size,
        BackgroundTransparency = 0, BackgroundColor3 = Theme.Element,
        Text = shown(text), TextTruncate = Enum.TextTruncate.AtEnd,
    })
    local st = stroke(b)
    New('UIPadding', { Parent = b, PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5) })
    local s = { hover = false, active = false }
    local function rest()
        return s.active and Theme.AccentDim or (s.hover and Theme.BorderLight or Theme.Border)
    end
    function s.paint(t)
        tween(b, t or 0.15, {
            BackgroundColor3 = s.hover and Theme.ElementHover or Theme.Element,
            TextColor3 = s.active and Theme.Accent or Theme.Text,
        })
        tween(st, t or 0.2, { Color = rest() })
    end
    b.MouseEnter:Connect(function() s.hover = true; s.paint() end)
    b.MouseLeave:Connect(function() s.hover = false; s.paint() end)
    b.MouseButton1Click:Connect(function()
        st.Color = Theme.Accent
        tween(st, 0.4, { Color = rest() })
    end)
    Buttons[b] = s
    return b
end
local function setButtonActive(b, on)
    local s = Buttons[b]
    if s then s.active = on; s.paint() end
end

-- Text input: Element box, muted placeholder, accent stroke while typing.
local function input(parent, order, placeholder)
    local frame = New('Frame', {
        Parent = parent, LayoutOrder = order, Size = UDim2.new(1, 0, 0, 20),
        BackgroundColor3 = Theme.Element, ClipsDescendants = true,
    })
    local st = stroke(frame)
    local box = New('TextBox', {
        Parent = frame, Position = UDim2.fromOffset(7, 0), Size = UDim2.new(1, -14, 1, 0),
        PlaceholderText = placeholder, PlaceholderColor3 = Theme.TextMuted,
        TextXAlignment = Enum.TextXAlignment.Left,
    })
    local hover, focused = false, false
    local function paint()
        tween(st, 0.15, { Color = focused and Theme.AccentDim or (hover and Theme.BorderLight or Theme.Border) })
    end
    frame.MouseEnter:Connect(function() hover = true; paint() end)
    frame.MouseLeave:Connect(function() hover = false; paint() end)
    box.Focused:Connect(function() focused = true; paint() end)
    box.FocusLost:Connect(function() focused = false; paint() end)
    return box
end

local function hlist(parent, gap)
    return New('UIListLayout', {
        Parent = parent, FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, gap), SortOrder = Enum.SortOrder.LayoutOrder,
    })
end
local function vlist(parent, gap)
    return New('UIListLayout', { Parent = parent, Padding = UDim.new(0, gap), SortOrder = Enum.SortOrder.LayoutOrder })
end

-- --- Header ---------------------------------------------------------------
local titleBar = New('Frame', {      -- opaque (same colour as the window) like the old bar: it is the drag handle
    Name = 'TitleBar', Parent = main,
    Size = UDim2.new(1, 0, 0, HEADER_H), BackgroundColor3 = Theme.Window,
})

local logo = crescent(titleBar, Theme.Accent, Theme.Window)
logo.Position = UDim2.fromOffset(17, 15)
logo.Size = UDim2.fromOffset(11, 11)

local titleRow = New('Frame', {
    Parent = titleBar, BackgroundTransparency = 1,
    Position = UDim2.fromOffset(30, 1), Size = UDim2.new(1, -110, 1, 0),
})
New('UIListLayout', {
    Parent = titleRow, FillDirection = Enum.FillDirection.Horizontal,
    VerticalAlignment = Enum.VerticalAlignment.Center,
    Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
})
local titleLabel = New('TextLabel', {
    Parent = titleRow, LayoutOrder = 1, Size = UDim2.new(0, 0, 1, 0),
    AutomaticSize = Enum.AutomaticSize.X, Bold = true,
    Text = shown('Remote Spy'), TextColor3 = Theme.TextDim,
})
local countLabel = New('TextLabel', {
    Parent = titleRow, LayoutOrder = 2, Size = UDim2.new(0, 0, 1, 0),
    AutomaticSize = Enum.AutomaticSize.X, TextSize = 12,
    Text = '0 calls', TextColor3 = Theme.TextMuted,
})

-- Header controls: small Element boxes, right to left. Icons are 1px frames or
-- an ASCII glyph (never images); they brighten on hover.
local function headerButton(slot, hoverInk)
    local b = New('TextButton', {
        Parent = titleBar, AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10 - (slot - 1) * 22, 0.5, 1), Size = UDim2.fromOffset(18, 18),
        BackgroundTransparency = 0, BackgroundColor3 = Theme.Element,
    })
    local st = stroke(b)
    local ink = {}   -- { instance, colour property }
    local hover = false
    local function paint()
        tween(b, 0.15, { BackgroundColor3 = hover and Theme.ElementHover or Theme.Element })
        tween(st, 0.2, { Color = hover and Theme.BorderLight or Theme.Border })
        for _, i in ipairs(ink) do
            tween(i[1], 0.15, { [i[2]] = hover and (hoverInk or Theme.Text) or Theme.TextDim })
        end
    end
    b.MouseEnter:Connect(function() hover = true; paint() end)
    b.MouseLeave:Connect(function() hover = false; paint() end)
    b.MouseButton1Click:Connect(function()
        st.Color = Theme.Accent
        tween(st, 0.4, { Color = hover and Theme.BorderLight or Theme.Border })
    end)
    local icon = {}
    function icon.bar(w, y)      -- a 1px line, centred, y px off the middle
        local f = New('Frame', {
            Parent = b, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, y),
            Size = UDim2.fromOffset(w, 1), BackgroundColor3 = Theme.TextDim,
        })
        ink[#ink + 1] = { f, 'BackgroundColor3' }
    end
    function icon.glyph(text)
        local l = New('TextLabel', {
            Parent = b, Position = UDim2.fromOffset(0, -1), Size = UDim2.fromScale(1, 1),
            Text = text, TextColor3 = Theme.TextDim,
        })
        ink[#ink + 1] = { l, 'TextColor3' }
    end
    return b, icon
end

local closeBtn, closeIcon = headerButton(1, Theme.Risk)        -- x
closeIcon.glyph('x')
local minBtn, minIcon = headerButton(2)                        -- single line
minIcon.bar(8, 0)
local settingsBtn, menuIcon = headerButton(3)                  -- three lines
menuIcon.bar(8, -3)
menuIcon.bar(8, 0)
menuIcon.bar(8, 3)

-- --- Body: the dark panel, with the moon behind the two boxes ----------------
local body = New('Frame', {
    Name = 'Body', Parent = main,
    Position = UDim2.fromOffset(10, HEADER_H), Size = UDim2.new(1, -20, 1, -(HEADER_H + 10)),
    BackgroundColor3 = Theme.Panel, ClipsDescendants = true,
})
stroke(body)
moonBehind(body)

-- LEFT box: filter + toolbar + feed ------------------------------------------
local _, left = groupbox(body, 'Calls', {
    Position = UDim2.fromOffset(8, 12), Size = UDim2.new(0.42, -12, 1, -20),
})
vlist(left, 6)

local searchBox = input(left, 1, shown('Filter by name'))

local toolbar = New('Frame', {
    Parent = left, LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1,
})
hlist(toolbar, 6)
local pauseBtn   = button(toolbar, 'Pause', 1, UDim2.new(1/3, -4, 1, 0))
local clearBtn   = button(toolbar, 'Clear', 2, UDim2.new(1/3, -4, 1, 0))
local copyAllBtn = button(toolbar, 'Copy all', 3, UDim2.new(1/3, -4, 1, 0)) -- copy the deduped dump (also on disk)

local feed = New('ScrollingFrame', {
    Name = 'Feed', Parent = left, LayoutOrder = 3,
    Size = UDim2.new(1, 0, 1, -52), BackgroundColor3 = Theme.Panel, BackgroundTransparency = 0.5,
    ScrollBarThickness = 2, ScrollBarImageColor3 = Theme.TextMuted,
    CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ScrollingDirection = Enum.ScrollingDirection.Y,
})
stroke(feed)
vlist(feed, 1)

-- RIGHT box: detail view -------------------------------------------------------
local _, right = groupbox(body, 'Details', {
    Position = UDim2.new(0.42, 4, 0, 12), Size = UDim2.new(0.58, -12, 1, -20),
})
vlist(right, 6)

local detailName = New('TextLabel', {
    Parent = right, LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 18), Bold = true,
    Text = shown('Select a call'), TextColor3 = Theme.TextDim,
    TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
})
local detailPath = New('TextLabel', {
    Parent = right, LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 14),
    Text = '', TextSize = 12, TextColor3 = Theme.TextDim,
    TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
})

local codeBox = New('ScrollingFrame', {
    Parent = right, LayoutOrder = 3, Size = UDim2.new(1, 0, 1, -70),
    BackgroundColor3 = Theme.Panel, BackgroundTransparency = 0.5,
    ScrollBarThickness = 2, ScrollBarImageColor3 = Theme.TextMuted,
    CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ScrollingDirection = Enum.ScrollingDirection.Y,
})
stroke(codeBox)
New('UIPadding', {
    Parent = codeBox, PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
    PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
})
local codeLabel = New('TextLabel', {
    Parent = codeBox, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
    FontFace = Fonts.mono, TextSize = 12,
    Text = '-- captured call source will appear here', TextColor3 = Theme.TextMuted,
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
    TextWrapped = true,
})

local detailBtns = New('Frame', {
    Parent = right, LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1,
})
hlist(detailBtns, 6)
local copyCodeBtn = button(detailBtns, 'Copy script', 1, UDim2.new(0.4, -4, 1, 0))
local copyPathBtn = button(detailBtns, 'Copy path', 2, UDim2.new(0.3, -4, 1, 0))
local ignoreBtn   = button(detailBtns, 'Ignore remote', 3, UDim2.new(0.3, -4, 1, 0))

-- ---- Settings overlay (the menu button opens this) --------------------------
local settingsPanel = New('Frame', {
    Name = 'Settings', Parent = main, Visible = false, ZIndex = 2,
    Position = body.Position, Size = body.Size, BackgroundColor3 = Theme.Panel,
    ClipsDescendants = true,
})
stroke(settingsPanel)
moonBehind(settingsPanel)

local _, sCard = groupbox(settingsPanel, 'Settings', {
    AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(300, 90),
})
vlist(sCard, 6)

New('TextLabel', {
    Parent = sCard, LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 16),
    Text = shown('Open / close key'), TextColor3 = Theme.TextDim,
    TextXAlignment = Enum.TextXAlignment.Left,
})

local keyRow = New('Frame', {
    Parent = sCard, LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1,
})
local keyBox = New('Frame', {
    Parent = keyRow, Size = UDim2.new(1, -86, 1, 0), BackgroundColor3 = Theme.Element,
})
local keyStroke = stroke(keyBox)
local keyValueLabel = New('TextLabel', {
    Parent = keyBox, Position = UDim2.fromOffset(7, 0), Size = UDim2.new(1, -14, 1, 0),
    Text = shown(TOGGLE_KEY.Name), TextColor3 = Theme.TextDim,
    TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
})
local rebindBtn = button(keyRow, 'Rebind', 1, UDim2.fromOffset(80, 20))
rebindBtn.AnchorPoint = Vector2.new(1, 0)
rebindBtn.Position = UDim2.new(1, 0, 0, 0)

local doneBtn = button(sCard, 'Done', 3, UDim2.new(1, 0, 0, 20))

-- Key box look: dim while idle, accent while waiting for a key (Crescent's
-- key picker does the same).
local function paintKey(waiting)
    tween(keyValueLabel, 0.12, { TextColor3 = waiting and Theme.Accent or Theme.TextDim })
    tween(keyStroke, 0.12, { Color = waiting and Theme.AccentDim or Theme.Border })
end

-- ===========================================================================
-- 5. State + row rendering
-- ===========================================================================
local calls    = {}        -- ordered list of captured entries
local rowByEntry = {}      -- entry -> row frame
local selected = nil
local paused   = false
local filter   = ''
local ignored  = {}        -- [remote] = true
local totalCalls = 0
local queue    = {}        -- captures waiting to be turned into rows

local function flashButton(btn, okText)
    local prev = btn.Text
    btn.Text = shown(okText)
    task.delay(0.8, function() if btn and btn.Parent then btn.Text = prev end end)
end

local function renderDetail(entry)
    selected = entry
    if not entry then
        detailName.Text = shown('Select a call')
        detailName.TextColor3 = Theme.TextDim
        detailPath.Text = ''
        codeLabel.Text  = '-- captured call source will appear here'
        codeLabel.TextColor3 = Theme.TextMuted
        return
    end
    detailName.Text = string.format('%s  ·  %s', entry.name, entry.method)
    detailName.TextColor3 = Theme.Text
    local ok, full = pcall(function() return entry.remote:GetFullName() end)
    detailPath.Text = ok and full or '<remote destroyed>'
    codeLabel.Text  = buildSnippet(entry)
    codeLabel.TextColor3 = Theme.Text
end

local function passesFilter(entry)
    if filter == '' then return true end
    return entry.name:lower():find(filter, 1, true) ~= nil
end

-- One call in the feed, styled like a Crescent dropdown row: Element background,
-- lighter on hover; the selected row gets the accent bar and full-white name.
local function makeRow(entry)
    local row = New('TextButton', {
        Parent = feed, Size = UDim2.new(1, 0, 0, ROW_H),
        BackgroundTransparency = 0, BackgroundColor3 = Theme.Element,
        LayoutOrder = entry.id,
    })

    local bar = New('Frame', { Parent = row, Visible = false,
        Position = UDim2.fromOffset(0, 4), Size = UDim2.fromOffset(2, ROW_H - 8),
        BackgroundColor3 = Theme.Accent })

    local nameLabel = New('TextLabel', { Parent = row,
        Position = UDim2.fromOffset(10, 3), Size = UDim2.new(1, -58, 0, 15),
        Text = entry.name, TextColor3 = Theme.TextDim,
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })

    New('TextLabel', { Parent = row,
        Position = UDim2.fromOffset(10, 17), Size = UDim2.new(1, -58, 0, 12),
        Text = string.format('%s · %d arg%s', entry.method, entry.argc,
            entry.argc == 1 and '' or 's'),
        TextSize = 12, TextColor3 = Theme.TextMuted,
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })

    New('TextLabel', { Parent = row,
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 0), Size = UDim2.fromOffset(44, ROW_H),
        Text = '#' .. entry.id, TextSize = 12,
        TextColor3 = Theme.TextMuted, TextXAlignment = Enum.TextXAlignment.Right })

    local function refreshColor()
        local on = selected == entry
        bar.Visible = on
        tween(nameLabel, 0.15, { TextColor3 = on and Theme.Text or Theme.TextDim })
    end
    refreshColor()
    row.MouseEnter:Connect(function() tween(row, 0.12, { BackgroundColor3 = Theme.ElementHover }) end)
    row.MouseLeave:Connect(function() tween(row, 0.18, { BackgroundColor3 = Theme.Element }) end)
    row.MouseButton1Click:Connect(function()
        renderDetail(entry)
        for e in pairs(rowByEntry) do
            if e._refreshColor then e._refreshColor() end
        end
    end)

    rowByEntry[entry] = row
    entry._refreshColor = refreshColor
    return row
end

local function addCall(entry)
    recordUnique(entry) -- dedup + live-save this unique call to SAVE_FILE
    calls[#calls + 1] = entry
    makeRow(entry)
    if not passesFilter(entry) and rowByEntry[entry] then
        rowByEntry[entry].Visible = false
    end
    -- trim oldest
    while #calls > MAX_ROWS do
        local old = table.remove(calls, 1)
        if rowByEntry[old] then rowByEntry[old]:Destroy() rowByEntry[old] = nil end
        if selected == old then renderDetail(nil) end
    end
    countLabel.Text = totalCalls .. ' calls'
    task.defer(function() feed.CanvasPosition = Vector2.new(0, feed.AbsoluteCanvasSize.Y) end)
end

-- ===========================================================================
-- 6. Button wiring
-- ===========================================================================
searchBox:GetPropertyChangedSignal('Text'):Connect(function()
    filter = searchBox.Text:lower()
    for entry, row in pairs(rowByEntry) do
        row.Visible = passesFilter(entry)
    end
end)

pauseBtn.MouseButton1Click:Connect(function()
    paused = not paused
    pauseBtn.Text = shown(paused and 'Resume' or 'Pause')
    setButtonActive(pauseBtn, paused)
end)

clearBtn.MouseButton1Click:Connect(function()
    for _, row in pairs(rowByEntry) do row:Destroy() end
    table.clear(calls)
    table.clear(rowByEntry)
    renderDetail(nil)
    countLabel.Text = totalCalls .. ' calls'
end)

-- Copy the whole DEDUPED dump (unique calls only) to the clipboard. The same
-- text is auto-saved to SAVE_FILE on disk as calls come in.
copyAllBtn.MouseButton1Click:Connect(function()
    if #dumpParts == 0 then flashButton(copyAllBtn, 'Empty'); return end
    clipboard(('-- RemoteSpy dump: %d unique remote calls (auto-saved to %s)\n\n')
        :format(#dumpParts, SAVE_FILE) .. table.concat(dumpParts, '\n\n'))
    flashButton(copyAllBtn, ('Copied %d'):format(#dumpParts))
end)

copyCodeBtn.MouseButton1Click:Connect(function()
    if not selected then return end
    clipboard(buildSnippet(selected))
    flashButton(copyCodeBtn, 'Copied!')
end)

copyPathBtn.MouseButton1Click:Connect(function()
    if not selected then return end
    clipboard(instancePath(selected.remote))
    flashButton(copyPathBtn, 'Copied')
end)

ignoreBtn.MouseButton1Click:Connect(function()
    if not selected then return end
    ignored[selected.remote] = true
    flashButton(ignoreBtn, 'Ignored')
end)

-- ===========================================================================
-- 7. Window controls (drag / minimise / close / toggle key)
-- ===========================================================================
do  -- dragging
    local dragging, dragStart, startPos
    titleBar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging, dragStart, startPos = true, i.Position, root.Position
            i.Changed:Connect(function()
                if i.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
            local d = i.Position - dragStart
            root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
end

local minimised = false
minBtn.MouseButton1Click:Connect(function()
    minimised = not minimised
    body.Visible = not minimised
    settingsPanel.Visible = false
    tween(root, 0.2, { Size = minimised and UDim2.fromOffset(W, HEADER_H + 2) or UDim2.fromOffset(W, H) })
end)

-- Settings + open/close key rebind
local awaitingKey = false
settingsBtn.MouseButton1Click:Connect(function()
    settingsPanel.Visible = not settingsPanel.Visible
end)
doneBtn.MouseButton1Click:Connect(function()
    settingsPanel.Visible = false
    awaitingKey = false
    keyValueLabel.Text = shown(TOGGLE_KEY.Name)
    paintKey(false)
end)
rebindBtn.MouseButton1Click:Connect(function()
    awaitingKey = true
    keyValueLabel.Text = shown('Press any key...')
    paintKey(true)
end)

local function setVisible(v)
    root.Visible = v
    if v then popIn() end
end
UIS.InputBegan:Connect(function(i, gpe)
    -- Capture the next key press when rebinding (ignore mouse buttons)
    if awaitingKey and i.UserInputType == Enum.UserInputType.Keyboard then
        TOGGLE_KEY = i.KeyCode
        saveToggleKey()                    -- persist across executions
        keyValueLabel.Text = shown(TOGGLE_KEY.Name)
        paintKey(false)
        awaitingKey = false
        return
    end
    if gpe then return end
    if i.KeyCode == TOGGLE_KEY then setVisible(not root.Visible) end
end)

-- ===========================================================================
-- 8. THE HOOK
-- ===========================================================================
-- Drain the queue on OUR OWN thread. The __namecall hook runs inside the
-- game's calling thread, which lacks the capability to create Instances -->
-- building rows there fails with "cannot access 'Instance' (lacking
-- capability Plugin)". A Heartbeat connection made from the main chunk keeps
-- the executor identity, so Instance.new / GUI writes are allowed here.
local drainConn = RunService.Heartbeat:Connect(function()
    if #queue == 0 then return end
    local batch = queue
    queue = {}
    for _, entry in ipairs(batch) do
        local ok, err = pcall(addCall, entry)
        if not ok then warn('[RemoteSpy] row error: ' .. tostring(err)) end
    end
end)

-- Shared, data-only capture (NO Instance creation on this thread - the row is
-- built later by drainConn, which runs with executor identity).
local function capture(self, method, ...)
    if paused or ignored[self] or typeof(self) ~= 'Instance' then return end
    -- checkCaller() only guards OUTGOING (skip OUR OWN fires). Incoming
    -- (OnClientEvent) is fired by the game, so never skip it on checkCaller.
    if method ~= 'OnClientEvent' and checkCaller() then return end
    local okN, nm = pcall(function() return self.Name end)
    local okC, cn = pcall(function() return self.ClassName end)
    totalCalls = totalCalls + 1
    queue[#queue + 1] = {
        id        = totalCalls,
        remote    = self,
        name      = okN and nm or '???',
        className = okC and cn or 'Instance',
        method    = method,
        args      = { ... },
        argc      = select('#', ...),
    }
end

-- (a) __namecall: catches normal  remote:FireServer(...) / :InvokeServer(...).
-- `inNamecall` flags the C-dispatch below so the raw function hooks in (b) do
-- NOT also capture the same call (which would double every normal call).
local inNamecall = false
local oldNamecall
oldNamecall = hookMeta(game, '__namecall', function(self, ...)
    local method = getNCMethod()
    if not inNamecall and (method == 'FireServer' or method == 'InvokeServer') then
        capture(self, method, ...)
    end
    inNamecall = true
    local r = table.pack(pcall(oldNamecall, self, ...))
    inNamecall = false
    if not r[1] then error(r[2], 2) end
    return table.unpack(r, 2, r.n)
end)

-- (b) Raw FireServer / InvokeServer hooks: catch the CACHED direct calls the
-- game uses (`local fs = Instance.new('RemoteEvent').FireServer; fs(remote, ...)`)
-- which BYPASS __namecall completely. This is how Rogue Lineage fires the exact
-- remotes a namecall-only spy can NEVER see: SetManaChargeState (hold G / mana),
-- ApplyFallDamage, Carry, Sprint, and more. Needs hookfunction/replaceclosure.
local restoreFE, restoreIS
do
    local hookfunction = hookfunction or replaceclosure
    local newcc = newcclosure or function(fn) return fn end
    if hookfunction then
        pcall(function()
            local oldFE
            oldFE = hookfunction(Instance.new('RemoteEvent').FireServer, newcc(function(self, ...)
                if not inNamecall then capture(self, 'FireServer', ...) end
                return oldFE(self, ...)
            end))
            restoreFE = function() pcall(function() hookfunction(Instance.new('RemoteEvent').FireServer, oldFE) end) end
        end)
        pcall(function()
            local oldIS
            oldIS = hookfunction(Instance.new('RemoteFunction').InvokeServer, newcc(function(self, ...)
                if not inNamecall then capture(self, 'InvokeServer', ...) end
                return oldIS(self, ...)
            end))
            restoreIS = function() pcall(function() hookfunction(Instance.new('RemoteFunction').InvokeServer, oldIS) end) end
        end)
        warn('[RemoteSpy] Cached-call capture ' .. ((restoreFE or restoreIS) and 'ON' or 'FAILED')
            .. ' - direct FireServer(remote,...) calls now visible.')
    else
        warn('[RemoteSpy] No hookfunction - cached direct calls (SetManaChargeState etc.) will NOT show.')
    end
end

-- (c) Incoming capture: connect OnClientEvent on every RemoteEvent so SERVER ->
-- CLIENT events (combat attack signals / effects / telegraphs) are logged too,
-- not just outgoing fires. Scoped to ReplicatedStorage (where remotes live) plus
-- any that stream in later. Deduped in the dump like everything else.
local incomingConns = {}
local hookedIncoming = setmetatable({}, { __mode = 'k' })
local function hookIncoming(r)
    if hookedIncoming[r] then return end
    if not (typeof(r) == 'Instance' and r:IsA('RemoteEvent')) then return end
    hookedIncoming[r] = true
    local ok, conn = pcall(function()
        return r.OnClientEvent:Connect(function(...) capture(r, 'OnClientEvent', ...) end)
    end)
    if ok and conn then incomingConns[#incomingConns + 1] = conn end
end
do
    local RepStorage = game:GetService('ReplicatedStorage')
    for _, d in ipairs(RepStorage:GetDescendants()) do hookIncoming(d) end
    incomingConns[#incomingConns + 1] = RepStorage.DescendantAdded:Connect(hookIncoming)
end

-- ===========================================================================
-- 9. Unload
-- ===========================================================================
local function unload()
    pcall(function() hookMeta(game, '__namecall', oldNamecall) end)  -- restore
    if restoreFE then pcall(restoreFE) end   -- un-hook raw FireServer
    if restoreIS then pcall(restoreIS) end   -- un-hook raw InvokeServer
    if drainConn then drainConn:Disconnect() end
    for _, c in ipairs(incomingConns) do pcall(function() c:Disconnect() end) end -- un-hook incoming
    if gui then gui:Destroy() end
    getgenv().RemoteSpy_Unload = nil
end
closeBtn.MouseButton1Click:Connect(unload)
getgenv().RemoteSpy_Unload = unload

-- ===========================================================================
-- 10. Intro toast
-- ===========================================================================
countLabel.Text = '0 calls'
titleLabel.Text = shown('Remote Spy')
popIn()
warn(('[RemoteSpy] Loaded. Toggle with %s. Fire some remotes in-game to populate the feed.')
    :format(TOGGLE_KEY.Name))
