--[[
    Crescent UI - v1.0.0

    A menu library with LinoriaLib's function names. A script written for Linoria
    (CreateWindow, AddTab, AddLeftGroupbox, AddRightGroupbox, AddToggle, AddSlider,
    AddDropdown, AddInput, AddButton, AddLabel, AddDivider, AddKeyPicker,
    AddColorPicker, Toggles / Options, Notify, OnUnload, Unload, plus the
    SaveManager / ThemeManager add-ons) runs on it unchanged.

    Look: black with a white accent, a crescent moon behind the content, smooth
    animations. The UI settings (accent, font, lowercase, moon, stars, cursor,
    keybind list, scale, window size) live in Crescent/settings.json and are shared
    by every script that uses Crescent.
]]

local VERSION = '1.0.0'

local function svc(name)
    local s = game:GetService(name)
    if type(cloneref) == 'function' then
        local ok, r = pcall(cloneref, s)
        if ok and r ~= nil then return r end
    end
    return s
end

local Players          = svc('Players')
local RunService       = svc('RunService')
local UserInputService = svc('UserInputService')
local TweenService     = svc('TweenService')
local TextService      = svc('TextService')
local HttpService      = svc('HttpService')
local GuiService       = svc('GuiService')
local CoreGui          = svc('CoreGui')

local LocalPlayer = Players.LocalPlayer
local clock = os.clock
local genv = (type(getgenv) == 'function' and getgenv()) or _G

local rgb = Color3.fromRGB
local UDim2new, fromOffset, fromScale = UDim2.new, UDim2.fromOffset, UDim2.fromScale
local V2 = Vector2.new
local floor, clamp, max, min, abs, exp = math.floor, math.clamp, math.max, math.min, math.abs, math.exp
local lower = string.lower

local GUTTER = 15                 -- left/right inset of everything that isn't a checkbox
local MIN_W, MIN_H = 470, 380
local HEADER_H, TABS_H = 28, 22
local PANEL_TOP = HEADER_H + TABS_H + 6

local Toggles, Options = {}, {}
genv.Toggles = Toggles
genv.Options = Options

-- ============================================================================
-- Theme
-- ============================================================================
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
    Star         = rgb(96, 96, 108),
    Risk         = rgb(255, 96, 96),
}
local DEFAULT_ACCENT = Theme.Accent

local PRESETS = {
    { 'Crescent', rgb(242, 242, 246) },
    { 'Silver',   rgb(178, 180, 190) },
    { 'Gold',     rgb(226, 196, 104) },
    { 'Frost',    rgb(160, 200, 255) },
    { 'Rose',     rgb(255, 160, 190) },
    { 'Mint',     rgb(150, 235, 190) },
}

-- Linoria's colour names, mapped onto the theme.
local LEGACY = {
    FontColor = 'Text', MainColor = 'Element', BackgroundColor = 'Panel',
    AccentColor = 'Accent', OutlineColor = 'Border', RiskColor = 'Risk',
}

local function C(key)
    local v = Theme[key]
    if v then return v end
    if key == 'AccentDim' or key == 'AccentColorDark' then return Theme.Accent:Lerp(Theme.Element, 0.55) end
    if key == 'Black' then return Theme.Outline end
    local l = LEGACY[key]
    if l then return Theme[l] end
    return nil
end

-- ============================================================================
-- Library table
-- ============================================================================
local Library = {
    Version = VERSION,
    Toggles = Toggles,
    Options = Options,
    Signals = {},
    OpenedFrames = {},
    DependencyBoxes = {},
    Registry = {},
    RegistryMap = {},
    HudRegistry = {},
    NotifyOnError = false,
    Toggled = false,
    Unloaded = false,
    Font = Enum.Font.Gotham,
    Theme = Theme,
    Presets = PRESETS,
    Black = Color3.new(0, 0, 0),
}
local Registry = Library.RegistryMap

local lastLegacy = {}
local function pushLegacy()
    for name, key in pairs(LEGACY) do
        Library[name] = Theme[key]
        lastLegacy[name] = Theme[key]
    end
    Library.AccentColorDark = C('AccentDim')
end
-- A script that sets Library.AccentColor (Linoria style) and calls
-- UpdateColorsUsingRegistry gets that colour adopted into the theme.
local function pullLegacy()
    for name, key in pairs(LEGACY) do
        local v = rawget(Library, name)
        if typeof(v) == 'Color3' and v ~= lastLegacy[name] then Theme[key] = v end
    end
end

-- ============================================================================
-- Saved UI settings (shared by every Crescent script)
-- ============================================================================
local PREFS_DIR, PREFS_FILE = 'Crescent', 'Crescent/settings.json'
local Prefs = {
    preset = 'Crescent', font = 'Gotham', lowercase = true, moon = true, stars = true,
    animations = true, cursor = true, keybinds = false, scale = 100,
}
local PREF_TYPES = {
    accent = 'string', preset = 'string', font = 'string', lowercase = 'boolean', moon = 'boolean',
    stars = 'boolean', animations = 'boolean', cursor = 'boolean', keybinds = 'boolean',
    scale = 'number', width = 'number', height = 'number',
}
Library.Prefs = Prefs

do
    local ok, data = pcall(function()
        if type(isfile) == 'function' and type(readfile) == 'function' and isfile(PREFS_FILE) then
            return HttpService:JSONDecode(readfile(PREFS_FILE))
        end
        return nil
    end)
    if ok and type(data) == 'table' then
        for k, t in pairs(PREF_TYPES) do
            if type(data[k]) == t then Prefs[k] = data[k] end
        end
    end
    if type(Prefs.accent) == 'string' then
        local ok2, c = pcall(Color3.fromHex, Prefs.accent)
        if ok2 and typeof(c) == 'Color3' then Theme.Accent = c end
    end
    Prefs.scale = clamp(tonumber(Prefs.scale) or 100, 60, 150)
end
pushLegacy()

local savePending = false
local function savePrefs()
    if savePending then return end
    savePending = true
    task.delay(0.4, function()
        savePending = false
        if type(writefile) ~= 'function' then return end
        pcall(function()
            if type(isfolder) == 'function' and type(makefolder) == 'function' and not isfolder(PREFS_DIR) then
                makefolder(PREFS_DIR)
            end
            writefile(PREFS_FILE, HttpService:JSONEncode(Prefs))
        end)
    end)
end

-- ============================================================================
-- Fonts
-- ============================================================================
local FONT_ENUMS = {
    ['Gotham'] = 'Gotham', ['Builder Sans'] = 'BuilderSans', ['Roboto'] = 'Roboto',
    ['Source Sans'] = 'SourceSans', ['Ubuntu'] = 'Ubuntu', ['Code'] = 'Code',
}
Library.FontNames = { 'Gotham', 'Builder Sans', 'Roboto', 'Source Sans', 'Ubuntu', 'Code' }
local Fonts = {}
local function loadFonts(name)
    local family
    pcall(function() family = Font.fromEnum(Enum.Font[FONT_ENUMS[name] or 'Gotham']).Family end)
    family = family or 'rbxasset://fonts/families/GothamSSm.json'
    local function make(weight)
        local ok, f = pcall(Font.new, family, weight, Enum.FontStyle.Normal)
        if ok and f then return f end
        return Font.fromEnum(Enum.Font.Gotham)
    end
    Fonts.body = make(Enum.FontWeight.Regular)
    Fonts.bold = make(Enum.FontWeight.Medium)
    Library.FontFace = Fonts.body
end
if not FONT_ENUMS[Prefs.font] then Prefs.font = 'Gotham' end
loadFonts(Prefs.font)

-- ============================================================================
-- Instances: one helper creates everything so theme, font, text case and the
-- fade animation can find what they need later.
-- ============================================================================
local TextRaw, FontOf, Rest, Kind = {}, {}, {}, {}
local Restylers = {}

local GUI_CLASS = {
    Frame = true, ScrollingFrame = true, TextLabel = true, TextButton = true,
    TextBox = true, ImageLabel = true, ImageButton = true,
}
local TEXT_CLASS = { TextLabel = true, TextButton = true, TextBox = true }
local FADE = {
    Frame = { 'BackgroundTransparency' },
    ScrollingFrame = { 'BackgroundTransparency', 'ScrollBarImageTransparency' },
    TextLabel = { 'BackgroundTransparency', 'TextTransparency' },
    TextButton = { 'BackgroundTransparency', 'TextTransparency' },
    TextBox = { 'BackgroundTransparency', 'TextTransparency' },
    ImageLabel = { 'BackgroundTransparency', 'ImageTransparency' },
    ImageButton = { 'BackgroundTransparency', 'ImageTransparency' },
    UIStroke = { 'Transparency' },
}

local function resolve(key)
    if type(key) == 'function' then return key() end
    return C(key)
end

function Library:AddToRegistry(Instance, Properties)
    Registry[Instance] = { Instance = Instance, Properties = Properties }
    for prop, key in pairs(Properties) do
        local v = resolve(key)
        if v ~= nil then Instance[prop] = v end
    end
end

function Library:RemoveFromRegistry(Instance)
    Registry[Instance] = nil
end

local function New(class, props, themed)
    local inst = Instance.new(class)
    if GUI_CLASS[class] then
        inst.BorderSizePixel = 0
        if TEXT_CLASS[class] then
            inst.BackgroundTransparency = 1
            inst.FontFace = Fonts.body
            FontOf[inst] = 'body'
            inst.TextSize = 13
            inst.TextColor3 = Theme.Text
            inst.Text = ''
            if class == 'TextBox' then inst.ClearTextOnFocus = false end
        end
        if class == 'TextButton' or class == 'ImageButton' then inst.AutoButtonColor = false end
    elseif class == 'UIStroke' then
        inst.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        inst.Thickness = 1
        inst.LineJoinMode = Enum.LineJoinMode.Miter
    end
    local parent
    if props then
        for k, v in pairs(props) do
            if k == 'Parent' then
                parent = v
            elseif k == 'Bold' then
                if v then inst.FontFace = Fonts.bold; FontOf[inst] = 'bold' end
            else
                inst[k] = v
            end
        end
    end
    if themed then Library:AddToRegistry(inst, themed) end
    -- text elements start see-through; one given a background colour is a box
    if TEXT_CLASS[class] and themed and themed.BackgroundColor3 and not (props and props.BackgroundTransparency ~= nil) then
        inst.BackgroundTransparency = 0
    end
    local fp = FADE[class]
    if fp then
        local r
        for _, p in ipairs(fp) do
            local v = inst[p]
            if v < 1 then r = r or {}; r[p] = v end
        end
        Rest[inst] = r
    end
    Kind[inst] = GUI_CLASS[class] and 1 or 2
    if parent then inst.Parent = parent end
    return inst
end

local function shown(raw)
    raw = tostring(raw == nil and '' or raw)
    if Prefs.lowercase then return lower(raw) end
    return raw
end

local function setText(inst, raw)
    raw = tostring(raw == nil and '' or raw)
    TextRaw[inst] = raw
    inst.Text = shown(raw)
end

local function forget(inst)
    Registry[inst] = nil
    Rest[inst] = nil
    Kind[inst] = nil
    FontOf[inst] = nil
    TextRaw[inst] = nil
end

local function restyle()
    for inst, entry in pairs(Registry) do
        for prop, key in pairs(entry.Properties) do
            local v = resolve(key)
            if v ~= nil then pcall(function() inst[prop] = v end) end
        end
    end
    for _, f in ipairs(Restylers) do pcall(f) end
end

function Library:UpdateColorsUsingRegistry()
    pullLegacy()
    pushLegacy()
    restyle()
end

-- ============================================================================
-- Animation: easing, a tiny value animator (stepped every frame), TweenService
-- for colours/positions, and a fade that walks the visible tree.
-- ============================================================================
local function linear(t) return t end
local function easeOutCubic(t) return 1 - (1 - t) ^ 3 end
local function easeOutQuint(t) return 1 - (1 - t) ^ 5 end

local Anims = {}
local function animate(id, dur, from, to, step, done, ease)
    if not Prefs.animations then dur = 0 end
    if dur <= 0 then
        Anims[id] = nil
        step(to)
        if done then done() end
        return
    end
    Anims[id] = { t0 = clock(), dur = dur, from = from, to = to, step = step, done = done, ease = ease or easeOutCubic }
    step(from)
end

local function stepAnims()
    if next(Anims) == nil then return end
    local now = clock()
    local ids = {}
    for id in pairs(Anims) do ids[#ids + 1] = id end
    local finished
    for _, id in ipairs(ids) do
        local a = Anims[id]
        if a then
            local k = (now - a.t0) / a.dur
            if k >= 1 then
                Anims[id] = nil
                local ok, err = pcall(a.step, a.to)
                if not ok then warn('[Crescent] animation error: ' .. tostring(err)) end
                finished = finished or {}
                finished[#finished + 1] = a
            else
                local ok, err = pcall(a.step, a.from + (a.to - a.from) * a.ease(k))
                if not ok then
                    Anims[id] = nil
                    warn('[Crescent] animation error: ' .. tostring(err))
                end
            end
        end
    end
    if finished then
        for _, a in ipairs(finished) do
            if a.done then
                local ok, err = pcall(a.done)
                if not ok then warn('[Crescent] animation error: ' .. tostring(err)) end
            end
        end
    end
end

local function tween(inst, t, props, style, dir)
    if not Prefs.animations or t <= 0 then
        for k, v in pairs(props) do inst[k] = v end
        return
    end
    local ok, tw = pcall(TweenService.Create, TweenService, inst,
        TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), props)
    if ok and tw then
        tw:Play()
    else
        for k, v in pairs(props) do inst[k] = v end
    end
end

-- Fade: every transparency property is scaled toward 1 by (1 - a). Rest holds
-- each instance's resting values; `dirty` remembers what was touched so it can be
-- put back exactly when the fade ends. Hidden subtrees are skipped.
local PageAlpha = {}
local function fadeTree(inst, a, dirty)
    local r = Rest[inst]
    if r then
        for p, b in pairs(r) do inst[p] = b + (1 - b) * (1 - a) end
        dirty[inst] = true
    end
    for _, ch in ipairs(inst:GetChildren()) do
        if Kind[ch] ~= 1 or ch.Visible then
            local pa = PageAlpha[ch]
            fadeTree(ch, pa and a * pa or a, dirty)
        end
    end
end

local function restoreDirty(dirty)
    for inst in pairs(dirty) do
        local r = Rest[inst]
        if r then
            for p, b in pairs(r) do inst[p] = b end
        end
        dirty[inst] = nil
    end
end

-- ============================================================================
-- Screen GUI, overlay layer (popups, tooltip, notifications, cursor), modal
-- ============================================================================
local ScreenGui = Instance.new('ScreenGui')
pcall(function() ScreenGui.Name = HttpService:GenerateGUID(false):gsub('-', ''):sub(1, 16) end)
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = false
ScreenGui.DisplayOrder = 999999
do
    local protect = (type(protectgui) == 'function' and protectgui)
        or (type(syn) == 'table' and type(syn.protect_gui) == 'function' and syn.protect_gui)
    if protect then pcall(protect, ScreenGui) end
    local placed = false
    if type(gethui) == 'function' then
        placed = pcall(function() ScreenGui.Parent = gethui() end) and ScreenGui.Parent ~= nil
    end
    if not placed then
        placed = pcall(function() ScreenGui.Parent = CoreGui end) and ScreenGui.Parent ~= nil
    end
    if not placed and LocalPlayer then
        ScreenGui.Parent = LocalPlayer:WaitForChild('PlayerGui')
    end
end
Library.ScreenGui = ScreenGui

local Overlay = New('Frame', { Name = 'Overlay', BackgroundTransparency = 1, Size = fromOffset(0, 0), ZIndex = 2, Parent = ScreenGui })
local ModalButton = New('TextButton', { BackgroundTransparency = 1, Size = fromOffset(0, 0), Text = '', Modal = false, Parent = ScreenGui })

local Inset = V2(0, 0)
local function refreshInset()
    local ok, a = pcall(function() return GuiService:GetGuiInset() end)
    if ok and typeof(a) == 'Vector2' then Inset = a end
end
refreshInset()

-- Mouse in the same space as AbsolutePosition (below the top bar inset).
local function mouse()
    return UserInputService:GetMouseLocation() - Inset
end

local function screen()
    local s = ScreenGui.AbsoluteSize
    if s.X < 2 then
        local cam = workspace.CurrentCamera
        if cam then s = cam.ViewportSize - Inset end
    end
    return s
end

local function isOver(obj, pad)
    if typeof(obj) ~= 'Instance' or not obj.Parent then return false end
    local m = mouse()
    local p, s = obj.AbsolutePosition, obj.AbsoluteSize
    pad = pad or 0
    return m.X >= p.X - pad and m.X <= p.X + s.X + pad and m.Y >= p.Y - pad and m.Y <= p.Y + s.Y + pad
end

local WinScaleObj
local function curScale()
    return WinScaleObj and WinScaleObj.Scale or 1
end

-- ============================================================================
-- Callbacks
-- ============================================================================
local function safeCall(f, ...)
    if type(f) ~= 'function' then return end
    local ok, err = xpcall(f, debug.traceback, ...)
    if not ok then
        warn('[Crescent] callback error: ' .. tostring(err))
        if Library.NotifyOnError then
            Library:Notify(tostring(err):match('^[^\n]*'), 3)
        end
    end
end

function Library:SafeCallback(f, ...)
    return safeCall(f, ...)
end

function Library:AttemptSave()
    if Library.SaveManager then pcall(function() Library.SaveManager:Save() end) end
end

function Library:GiveSignal(Signal)
    table.insert(Library.Signals, Signal)
    return Signal
end

function Library:Create(Class, Properties)
    if type(Class) ~= 'string' then
        for k, v in pairs(Properties or {}) do Class[k] = v end
        return Class
    end
    return New(Class, Properties)
end

function Library:CreateLabel(Properties)
    local l = New('TextLabel', Properties)
    return l
end

function Library:MapValue(Value, MinA, MaxA, MinB, MaxB)
    return (1 - ((Value - MinA) / (MaxA - MinA))) * MinB + ((Value - MinA) / (MaxA - MinA)) * MaxB
end

function Library:GetDarkerColor(Color)
    local H, S, V = Color3.toHSV(Color)
    return Color3.fromHSV(H, S, V / 1.5)
end

function Library:GetTextBounds(Text, Font, Size, Resolution)
    local ok, b = pcall(function()
        return TextService:GetTextSize(Text, Size, typeof(Font) == 'EnumItem' and Font or Enum.Font.Gotham, Resolution or V2(1920, 1080))
    end)
    if ok and b then return b.X, b.Y end
    return #tostring(Text) * Size * 0.5, Size
end

function Library:IsMouseOverFrame(Frame)
    return isOver(Frame)
end

-- ============================================================================
-- Drag routing: one active drag at a time, fed by the global input handlers.
-- ============================================================================
local Drag = nil

function Library:MakeDraggable(Instance, Cutoff)
    Instance.Active = true
    Instance.InputBegan:Connect(function(Input)
        if Input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        local m0 = mouse()
        if m0.Y - Instance.AbsolutePosition.Y > (Cutoff or 40) then return end
        local p0 = Instance.Position
        Drag = {
            move = function(m)
                local d = m - m0
                Instance.Position = UDim2new(p0.X.Scale, p0.X.Offset + d.X, p0.Y.Scale, p0.Y.Offset + d.Y)
            end,
        }
    end)
end

-- ============================================================================
-- Smooth scrolling. The ScrollingFrame keeps its native wheel handling (so the
-- wheel never also zooms the camera); each native jump is turned into a target
-- and the canvas glides there.
-- ============================================================================
local Scrollers = {}
local function smoothScroll(sf, onUpdate)
    local st = { sf = sf, cur = sf.CanvasPosition.Y, target = sf.CanvasPosition.Y, guard = false, onUpdate = onUpdate }
    function st.maxY()
        local s = curScale()
        if s <= 0 then s = 1 end
        return max(0, (sf.AbsoluteCanvasSize.Y - sf.AbsoluteWindowSize.Y) / s)
    end
    function st.set(y)
        st.guard = true
        sf.CanvasPosition = V2(0, y)
        st.guard = false
    end
    sf:GetPropertyChangedSignal('CanvasPosition'):Connect(function()
        if st.guard then return end
        local y = sf.CanvasPosition.Y
        local d = y - st.cur
        if abs(d) < 0.01 then return end
        if not Prefs.animations then
            st.cur, st.target = y, y
            if onUpdate then onUpdate() end
            return
        end
        st.target = clamp(st.target + d, 0, st.maxY())
        st.set(st.cur)
        Scrollers[st] = true
    end)
    return st
end

local function stepScrollers(dt)
    if next(Scrollers) == nil then return end
    local k = 1 - exp(-dt * 16)
    for st in pairs(Scrollers) do
        if not st.sf.Parent then
            Scrollers[st] = nil
        else
            st.target = clamp(st.target, 0, st.maxY())
            st.cur = st.cur + (st.target - st.cur) * k
            if abs(st.target - st.cur) < 0.5 then
                st.cur = st.target
                Scrollers[st] = nil
            end
            st.set(st.cur)
            if st.onUpdate then pcall(st.onUpdate) end
        end
    end
end

-- ============================================================================
-- Popups (dropdown lists, colour pickers, keybind mode menus). One at a time,
-- anchored to the control that opened it and kept attached while you scroll.
-- ============================================================================
local Current = nil

local function closePopup(instant)
    local p = Current
    if not p then return end
    Current = nil
    Library.OpenedFrames[p.root] = nil
    if p.onClose then safeCall(p.onClose) end
    if instant or not Prefs.animations then
        Anims[p] = nil
        p.root:Destroy()
        return
    end
    local h0 = p.height
    animate(p, 0.12, 1, 0, function(v)
        p.root.Size = fromOffset(p.width, max(1, floor(h0 * (0.85 + 0.15 * v) + 0.5)))
        fadeTree(p.root, v, p.dirty)
    end, function()
        p.root:Destroy()
    end, easeOutCubic)
end

local function placePopup(p)
    local a = p.anchor
    if typeof(a) ~= 'Instance' or not a.Parent or not a.Visible then return false end
    local ap, as = a.AbsolutePosition, a.AbsoluteSize
    if as.X <= 0 then return false end
    if p.clip and p.clip.Parent then
        local cp, cs = p.clip.AbsolutePosition, p.clip.AbsoluteSize
        local ay = ap.Y + as.Y / 2
        if ay < cp.Y or ay > cp.Y + cs.Y then return false end
    end
    local s = Prefs.scale / 100
    local w, h = p.width * s, p.height * s
    local x = (p.align == 'right') and (ap.X + as.X - w) or ap.X
    local y = ap.Y + as.Y + 4
    local sc = screen()
    if y + h > sc.Y - 6 and ap.Y - h - 4 > 6 then y = ap.Y - h - 4 end
    x = clamp(x, 6, max(6, sc.X - w - 6))
    p.root.Position = fromOffset(floor(x + 0.5), floor(y + 0.5))
    return true
end

local function openPopup(spec)
    closePopup(true)
    local root = New('Frame', {
        Size = fromOffset(spec.width, 0), ClipsDescendants = true, Active = true, ZIndex = 6, Parent = Overlay,
    }, { BackgroundColor3 = spec.bg or 'Element' })
    New('UIStroke', { Parent = root }, { Color = 'BorderLight' })
    New('UIScale', { Scale = Prefs.scale / 100, Parent = root })
    local p = {
        root = root, anchor = spec.anchor, clip = spec.clip, owner = spec.owner, width = spec.width,
        align = spec.align, dirty = {}, onClose = spec.onClose, height = 0,
    }
    local ok, h = pcall(spec.build, root, p)
    if not ok then
        warn('[Crescent] popup error: ' .. tostring(h))
        root:Destroy()
        return nil
    end
    p.height = h or 0
    Current = p
    Library.OpenedFrames[root] = true
    if not placePopup(p) then
        closePopup(true)
        return nil
    end
    function p.resize(nh)
        p.height = nh
        if not Anims[p] then root.Size = fromOffset(p.width, nh) end
    end
    animate(p, 0.22, 0, 1, function(v)
        root.Size = fromOffset(p.width, max(1, floor(p.height * (0.55 + 0.45 * v) + 0.5)))
        fadeTree(root, v, p.dirty)
    end, function()
        root.Size = fromOffset(p.width, p.height)
        restoreDirty(p.dirty)
    end, easeOutQuint)
    return p
end

function Library:MouseIsOverOpenedFrame()
    return Current ~= nil and isOver(Current.root)
end

-- A row in a popup list: hover tint, click callback.
local function popupRow(parent, order, height, onClick)
    local r = New('TextButton', { Size = UDim2new(1, 0, 0, height), LayoutOrder = order, Text = '', Parent = parent }, { BackgroundColor3 = 'Element' })
    r.MouseEnter:Connect(function() tween(r, 0.12, { BackgroundColor3 = C('ElementHover') }) end)
    r.MouseLeave:Connect(function() tween(r, 0.18, { BackgroundColor3 = C('Element') }) end)
    r.MouseButton1Down:Connect(onClick)
    return r
end

-- ============================================================================
-- Tooltip
-- ============================================================================
local Tip = { dirty = {}, alpha = 0 }
Tip.frame = New('Frame', { Size = fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, Visible = false, ZIndex = 9, Parent = Overlay }, { BackgroundColor3 = 'Window' })
New('UIStroke', { Parent = Tip.frame }, { Color = 'BorderLight' })
New('UIPadding', {
    PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 6), Parent = Tip.frame,
})
Tip.label = New('TextLabel', {
    Size = fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, TextWrapped = true, TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left, Parent = Tip.frame,
}, { TextColor3 = 'TextDim' })
New('UISizeConstraint', { MaxSize = V2(300, 2000), Parent = Tip.label })

local function hideTip()
    Tip.owner = nil
    Tip.shown = false
    if Tip.frame.Visible then
        animate(Tip, 0.1, Tip.alpha, 0, function(v)
            Tip.alpha = v
            fadeTree(Tip.frame, v, Tip.dirty)
        end, function()
            Tip.frame.Visible = false
        end)
    end
end

function Library:AddToolTip(InfoStr, HoverInstance)
    if type(InfoStr) ~= 'string' or InfoStr == '' or typeof(HoverInstance) ~= 'Instance' then return end
    HoverInstance.MouseEnter:Connect(function()
        if Library.Unloaded then return end
        Tip.owner, Tip.text, Tip.at, Tip.shown = HoverInstance, InfoStr, clock() + 0.4, false
    end)
    HoverInstance.MouseLeave:Connect(function()
        if Tip.owner == HoverInstance then hideTip() end
    end)
end

local function stepTip()
    local o = Tip.owner
    if not o then return end
    if not o.Parent or not Library.Toggled or not isOver(o) or (Current and isOver(Current.root)) then
        hideTip()
        return
    end
    if not Tip.shown and clock() >= Tip.at then
        Tip.shown = true
        Tip.label.Text = Tip.text
        Tip.frame.Visible = true
        animate(Tip, 0.14, Tip.alpha, 1, function(v)
            Tip.alpha = v
            fadeTree(Tip.frame, v, Tip.dirty)
        end, function()
            restoreDirty(Tip.dirty)
        end)
    end
    if Tip.shown then
        local m, sz, sc = mouse(), Tip.frame.AbsoluteSize, screen()
        local x, y = m.X + 14, m.Y + 12
        if x + sz.X > sc.X - 4 then x = m.X - sz.X - 10 end
        if y + sz.Y > sc.Y - 4 then y = m.Y - sz.Y - 8 end
        Tip.frame.Position = fromOffset(floor(x), floor(y))
    end
end

-- Linoria's hover helper: switch registry colours while the mouse is over.
function Library:OnHighlight(HighlightInstance, Instance, Properties, PropertiesDefault)
    HighlightInstance.MouseEnter:Connect(function()
        local reg = Registry[Instance]
        for prop, key in pairs(Properties) do
            Instance[prop] = resolve(key) or key
            if reg and reg.Properties[prop] then reg.Properties[prop] = key end
        end
    end)
    HighlightInstance.MouseLeave:Connect(function()
        local reg = Registry[Instance]
        for prop, key in pairs(PropertiesDefault) do
            Instance[prop] = resolve(key) or key
            if reg and reg.Properties[prop] then reg.Properties[prop] = key end
        end
    end)
end

-- ============================================================================
-- Notifications
-- ============================================================================
local Notes = {}
local NOTE_X = 12

local function restackNotes()
    local y = 12
    for _, n in ipairs(Notes) do
        n.ty = y
        y = y + n.h + 6
    end
end

local function removeNote(n, fast)
    if n.gone then return end
    n.gone = true
    Anims[n.prog] = nil
    animate(n, fast and 0.12 or 0.26, n.alpha, 0, function(v)
        n.alpha = v
        n.x = NOTE_X - (1 - v) * 28
        fadeTree(n.frame, v, n.dirty)
    end, function()
        for i, m in ipairs(Notes) do
            if m == n then table.remove(Notes, i) break end
        end
        n.frame:Destroy()
        restackNotes()
    end, easeOutCubic)
end

function Library:Notify(Text, Time)
    if Library.Unloaded then return end
    Text = tostring(Text == nil and '' or Text)
    Time = tonumber(Time) or 5
    local n = { x = -24, y = 12, ty = 12, h = 30, alpha = 0, dirty = {}, prog = {} }
    local frame = New('Frame', { Size = fromOffset(220, 30), Position = fromOffset(-24, 12), ZIndex = 5, Parent = Overlay }, { BackgroundColor3 = 'Window' })
    New('UIStroke', { Parent = frame }, { Color = 'Border' })
    New('Frame', { Size = UDim2new(0, 2, 1, 0), Parent = frame }, { BackgroundColor3 = 'Accent' })
    local content = New('Frame', { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.XY, Size = fromOffset(0, 0), Parent = frame })
    New('UIPadding', {
        PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 7), PaddingBottom = UDim.new(0, 8), Parent = content,
    })
    local label = New('TextLabel', {
        AutomaticSize = Enum.AutomaticSize.XY, Size = fromOffset(0, 0), TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left, Text = Text, Parent = content,
    }, { TextColor3 = 'Text' })
    New('UISizeConstraint', { MaxSize = V2(340, 2000), Parent = label })
    local bar = New('Frame', { Position = UDim2new(0, 0, 1, -1), Size = UDim2new(1, 0, 0, 1), BackgroundTransparency = 0.4, Parent = frame }, { BackgroundColor3 = 'Accent' })
    n.frame = frame
    local function fit()
        local s = content.AbsoluteSize
        if s.X < 1 or n.gone then return end
        frame.Size = fromOffset(s.X, s.Y)
        n.h = s.Y
        restackNotes()
    end
    content:GetPropertyChangedSignal('AbsoluteSize'):Connect(fit)
    table.insert(Notes, n)
    local live = {}
    for _, m in ipairs(Notes) do
        if not m.gone then live[#live + 1] = m end
    end
    for i = 1, #live - 8 do removeNote(live[i], true) end
    restackNotes()
    n.y = n.ty
    fit()
    animate(n, 0.34, 0, 1, function(v)
        n.alpha = v
        n.x = -24 + (NOTE_X + 24) * v
        fadeTree(frame, v, n.dirty)
    end, function()
        restoreDirty(n.dirty)
    end, easeOutQuint)
    animate(n.prog, Time, 1, 0, function(v)
        bar.Size = UDim2new(v, 0, 0, 1)
    end, function()
        removeNote(n)
    end, linear)
    if not Prefs.animations then
        task.delay(Time, function() removeNote(n) end)
    end
end

local function stepNotes(dt)
    if #Notes == 0 then return end
    local k = 1 - exp(-dt * 14)
    for _, n in ipairs(Notes) do
        n.y = n.y + (n.ty - n.y) * k
        n.frame.Position = fromOffset(floor(n.x + 0.5), floor(n.y + 0.5))
    end
end

-- ============================================================================
-- Watermark
-- ============================================================================
local WM = {}
WM.frame = New('Frame', { Size = fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, Visible = false, ZIndex = 4, Parent = Overlay }, { BackgroundColor3 = 'Window' })
New('UIStroke', { Parent = WM.frame }, { Color = 'Border' })
New('UIPadding', { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 6), Parent = WM.frame })
WM.label = New('TextLabel', { Size = fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, TextSize = 12, Parent = WM.frame }, { TextColor3 = 'Text' })
New('Frame', { Position = UDim2new(0, -10, 0, -5), Size = UDim2new(1, 20, 0, 1), Parent = WM.frame }, { BackgroundColor3 = 'Accent' })
Library.Watermark = WM.frame
Library.WatermarkText = WM.label

function Library:SetWatermarkVisibility(Bool)
    WM.frame.Visible = not not Bool
end

function Library:SetWatermark(Text)
    WM.label.Text = tostring(Text)
end

-- ============================================================================
-- Keybind list
-- ============================================================================
local Pickers = {}
local PickingNow = nil

local KB = { dirty = true }
KB.frame = New('Frame', { Position = fromOffset(12, 300), Size = fromOffset(190, 46), Visible = Prefs.keybinds, Active = true, ZIndex = 4, Parent = Overlay }, { BackgroundColor3 = 'Window' })
New('UIStroke', { Parent = KB.frame }, { Color = 'Border' })
New('Frame', { Size = UDim2new(1, 0, 0, 1), Parent = KB.frame }, { BackgroundColor3 = 'Accent' })
do
    local title = New('TextLabel', { Position = fromOffset(10, 1), Size = UDim2new(1, -20, 0, 22), TextSize = 12, Bold = true, TextXAlignment = Enum.TextXAlignment.Left, Parent = KB.frame }, { TextColor3 = 'TextDim' })
    setText(title, 'Keybinds')
end
KB.list = New('Frame', { BackgroundTransparency = 1, Position = fromOffset(10, 24), Size = UDim2new(1, -20, 1, -28), Parent = KB.frame })
New('UIListLayout', { SortOrder = Enum.SortOrder.LayoutOrder, Parent = KB.list })
Library.KeybindFrame = KB.frame
Library.KeybindContainer = KB.list
Library:MakeDraggable(KB.frame, 24)

local KEY_SHORT = {
    LeftShift = 'lshift', RightShift = 'rshift', LeftControl = 'lctrl', RightControl = 'rctrl',
    LeftAlt = 'lalt', RightAlt = 'ralt', Return = 'enter', Backspace = 'bksp', Escape = 'esc',
    CapsLock = 'caps', PageUp = 'pgup', PageDown = 'pgdn', Insert = 'ins', Delete = 'del',
    One = '1', Two = '2', Three = '3', Four = '4', Five = '5', Six = '6', Seven = '7', Eight = '8',
    Nine = '9', Zero = '0', MB1 = 'mb1', MB2 = 'mb2', None = 'none', Unknown = 'none',
}
local function keyName(k)
    if k == nil then return 'none' end
    k = tostring(k)
    return KEY_SHORT[k] or lower(k)
end

local function refreshKeybinds()
    KB.dirty = false
    for _, ch in ipairs(KB.list:GetChildren()) do
        if ch:IsA('TextLabel') then ch:Destroy() end
    end
    local n = 0
    for _, kp in ipairs(Pickers) do
        local ok, on = pcall(kp.GetState, kp)
        if not kp._noUI and ok and on and kp.Value ~= 'None' then
            n = n + 1
            New('TextLabel', {
                Size = UDim2new(1, 0, 0, 16), TextSize = 12, LayoutOrder = n, TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd, Text = '[' .. keyName(kp.Value) .. ']  ' .. shown(kp._text), Parent = KB.list,
            }, { TextColor3 = 'Text' })
        end
    end
    if n == 0 then
        New('TextLabel', { Size = UDim2new(1, 0, 0, 16), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, Text = 'none', Parent = KB.list }, { TextColor3 = 'TextMuted' })
    end
    KB.frame.Size = fromOffset(190, 24 + max(n, 1) * 16 + 8)
end

-- ============================================================================
-- Crosshair cursor (shown while the menu is open)
-- ============================================================================
local Cursor = { on = false }
do
    local function line(w, h, z, key)
        return New('Frame', { AnchorPoint = V2(0.5, 0.5), Size = fromOffset(w, h), Visible = false, ZIndex = z, Parent = Overlay }, { BackgroundColor3 = key })
    end
    Cursor.parts = { line(13, 3, 20, 'Outline'), line(3, 13, 20, 'Outline'), line(11, 1, 21, 'Accent'), line(1, 11, 21, 'Accent') }
end

local function cursorOn()
    if Cursor.on then return end
    Cursor.on = true
    Cursor.saved = UserInputService.MouseIconEnabled
end

local function cursorOff()
    if not Cursor.on then return end
    Cursor.on = false
    for _, p in ipairs(Cursor.parts) do p.Visible = false end
    pcall(function() UserInputService.MouseIconEnabled = Cursor.saved ~= false end)
end

local function stepCursor()
    if not Cursor.on then return end
    if not Prefs.cursor then
        if Cursor.parts[1].Visible then
            for _, p in ipairs(Cursor.parts) do p.Visible = false end
            pcall(function() UserInputService.MouseIconEnabled = Cursor.saved ~= false end)
        end
        return
    end
    local m = mouse()
    for _, p in ipairs(Cursor.parts) do
        p.Visible = true
        p.Position = fromOffset(floor(m.X + 0.5), floor(m.Y + 0.5))
    end
    UserInputService.MouseIconEnabled = false
end

-- ============================================================================
-- Search registry (filled by the controls, used by the window's search box)
-- ============================================================================
local Searchables = {}
local function registerSearch(row, text, container)
    local e = { row = row, text = lower(tostring(text or '')), group = container._group, tab = container._tab }
    Searchables[#Searchables + 1] = e
    return e
end

-- ============================================================================
-- Add-ons that sit on the right of a toggle or label: KeyPicker, ColorPicker
-- ============================================================================
local AddonFuncs = {}
local AddonMeta = { __index = AddonFuncs }

local function addonHolder(row, hit, label, labelInset)
    local holder = New('Frame', {
        AnchorPoint = V2(1, 0.5), Position = UDim2new(1, 0, 0.5, 0), Size = fromOffset(0, 16),
        AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, ZIndex = 3, Parent = row,
    })
    New('UIListLayout', {
        FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4), Parent = holder,
    })
    local function fit()
        local w = holder.AbsoluteSize.X / curScale()
        if w > 0 then w = w + 6 end
        if hit then hit.Size = UDim2new(1, -w, 1, 0) end
        if label then label.Size = UDim2new(1, -((labelInset or 0) + w), 1, 0) end
    end
    holder:GetPropertyChangedSignal('AbsoluteSize'):Connect(fit)
    return holder
end

function AddonFuncs:AddKeyPicker(Idx, Info)
    local ParentObj = self
    assert(Info.Default, 'AddKeyPicker: Missing default value.')

    local KeyPicker = {
        Value = Info.Default,
        Toggled = false,
        Mode = Info.Mode or 'Toggle', -- Always, Toggle, Hold
        Type = 'KeyPicker',
        Callback = Info.Callback or function(Value) end,
        ChangedCallback = Info.ChangedCallback or function(New) end,
        SyncToggleState = Info.SyncToggleState or false,
    }
    if KeyPicker.SyncToggleState then
        Info.Modes = { 'Toggle' }
        Info.Mode = 'Toggle'
    end
    local Modes = Info.Modes or { 'Always', 'Toggle', 'Hold' }
    KeyPicker._noUI = Info.NoUI
    KeyPicker._text = Info.Text or ''

    local holder = ParentObj._holder
    ParentObj._addonCount = (ParentObj._addonCount or 0) + 1
    local box = New('TextButton', {
        Size = fromOffset(0, 15), AutomaticSize = Enum.AutomaticSize.X, TextSize = 12,
        LayoutOrder = ParentObj._addonCount, Parent = holder,
    }, { BackgroundColor3 = 'Element' })
    local stroke = New('UIStroke', { Parent = box })
    New('UIPadding', { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = box })
    New('UISizeConstraint', { MinSize = V2(26, 0), Parent = box })
    KeyPicker._box = box

    local hover = false
    local lastLook, lastState
    local function paint(instant)
        local on = KeyPicker:GetState()
        local picking = PickingNow == KeyPicker
        local look = (picking and 'p' or '') .. (on and 'o' or '') .. (hover and 'h' or '') .. (KeyPicker.Value == 'None' and 'n' or '')
        if look == lastLook and not instant then return end
        lastLook = look
        local tc = (picking or on) and C('Accent') or (KeyPicker.Value == 'None' and C('TextMuted') or C('TextDim'))
        local sc = (picking or on) and C('AccentDim') or (hover and C('BorderLight') or C('Border'))
        tween(box, instant and 0 or 0.12, { TextColor3 = tc })
        tween(stroke, instant and 0 or 0.12, { Color = sc })
    end
    local function showKey()
        if PickingNow ~= KeyPicker then box.Text = keyName(KeyPicker.Value) end
    end

    function KeyPicker:GetState()
        if KeyPicker.Mode == 'Always' then
            return true
        elseif KeyPicker.Mode == 'Hold' then
            local Key = KeyPicker.Value
            if Key == 'None' then return false end
            if Key == 'MB1' then return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) end
            if Key == 'MB2' then return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) end
            local ok, code = pcall(function() return Enum.KeyCode[Key] end)
            if not ok or code == nil then return false end
            return UserInputService:IsKeyDown(code)
        else
            return KeyPicker.Toggled
        end
    end

    function KeyPicker:Update()
        local on = KeyPicker:GetState()
        if on ~= lastState then
            lastState = on
            KB.dirty = true
        end
        showKey()
        paint()
    end

    function KeyPicker:SetValue(Data)
        local Key, Mode = Data[1], Data[2]
        KeyPicker.Value = Key
        if Mode ~= nil then
            for _, m in ipairs(Modes) do
                if m == Mode then KeyPicker.Mode = Mode end
            end
        end
        KB.dirty = true
        KeyPicker:Update()
    end

    function KeyPicker:OnClick(Callback)
        KeyPicker.Clicked = Callback
    end

    function KeyPicker:OnChanged(Callback)
        KeyPicker.Changed = Callback
        safeCall(Callback, KeyPicker.Value)
    end

    if ParentObj.Addons then table.insert(ParentObj.Addons, KeyPicker) end

    function KeyPicker:DoClick()
        if ParentObj.Type == 'Toggle' and KeyPicker.SyncToggleState then
            ParentObj:SetValue(not ParentObj.Value)
        end
        safeCall(KeyPicker.Callback, KeyPicker.Toggled)
        safeCall(KeyPicker.Clicked, KeyPicker.Toggled)
    end

    function KeyPicker:_cancelPick()
        if PickingNow == KeyPicker then PickingNow = nil end
        showKey()
        paint()
    end

    function KeyPicker:_finishPick(Key, Input)
        PickingNow = nil
        KeyPicker._pickedAt = clock()
        KeyPicker.Value = Key
        KB.dirty = true
        showKey()
        paint()
        safeCall(KeyPicker.ChangedCallback, Input.KeyCode or Input.UserInputType)
        safeCall(KeyPicker.Changed, Input.KeyCode or Input.UserInputType)
        Library:AttemptSave()
    end

    box.MouseEnter:Connect(function() hover = true; paint() end)
    box.MouseLeave:Connect(function() hover = false; paint() end)
    box.MouseButton1Down:Connect(function()
        if Library:MouseIsOverOpenedFrame() then return end
        if PickingNow and PickingNow ~= KeyPicker then PickingNow:_cancelPick() end
        closePopup()
        PickingNow = KeyPicker
        KeyPicker._armAt = clock() + 0.12
        box.Text = '...'
        paint()
    end)
    box.MouseButton2Down:Connect(function()
        if Library:MouseIsOverOpenedFrame() or PickingNow then return end
        if KeyPicker._pickedAt and clock() - KeyPicker._pickedAt < 0.25 then return end
        if #Modes <= 1 then return end
        if Current and Current.owner == KeyPicker then closePopup() return end
        openPopup({
            owner = KeyPicker, anchor = box, clip = ParentObj._clip, width = 92, align = 'right',
            build = function(root)
                New('UIListLayout', { SortOrder = Enum.SortOrder.LayoutOrder, Parent = root })
                New('UIPadding', { PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2), Parent = root })
                for i, mode in ipairs(Modes) do
                    local r = popupRow(root, i, 18, function()
                        KeyPicker.Mode = mode
                        KB.dirty = true
                        KeyPicker:Update()
                        Library:AttemptSave()
                        closePopup()
                    end)
                    local t = New('TextLabel', { Position = fromOffset(10, 0), Size = UDim2new(1, -16, 1, 0), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, Parent = r })
                    setText(t, mode)
                    t.TextColor3 = (KeyPicker.Mode == mode) and C('Text') or C('TextDim')
                    if KeyPicker.Mode == mode then
                        New('Frame', { Position = fromOffset(0, 4), Size = fromOffset(2, 10), Parent = r }, { BackgroundColor3 = 'Accent' })
                    end
                end
                return #Modes * 18 + 4
            end,
        })
    end)

    table.insert(Restylers, function() lastLook = nil; paint(true) end)
    table.insert(Pickers, KeyPicker)
    showKey()
    paint(true)
    KeyPicker:Update()

    Options[Idx] = KeyPicker
    return self
end

function AddonFuncs:AddColorPicker(Idx, Info)
    local ParentObj = self
    assert(Info.Default, 'AddColorPicker: Missing default value.')

    local ColorPicker = {
        Value = Info.Default,
        Transparency = Info.Transparency or 0,
        Type = 'ColorPicker',
        Title = type(Info.Title) == 'string' and Info.Title or 'Color picker',
        Callback = Info.Callback or function(Color) end,
    }
    local hasAlpha = Info.Transparency ~= nil

    function ColorPicker:SetHSVFromRGB(Color)
        local H, S, V = Color3.toHSV(Color)
        ColorPicker.Hue, ColorPicker.Sat, ColorPicker.Vib = H, S, V
    end
    ColorPicker:SetHSVFromRGB(ColorPicker.Value)

    ParentObj._addonCount = (ParentObj._addonCount or 0) + 1
    local swatch = New('TextButton', { Size = fromOffset(22, 11), Text = '', BackgroundTransparency = 0, LayoutOrder = ParentObj._addonCount, Parent = ParentObj._holder })
    local swStroke = New('UIStroke', { Parent = swatch }, { Color = 'Border' })
    swatch.MouseEnter:Connect(function() tween(swStroke, 0.12, { Color = C('BorderLight') }) end)
    swatch.MouseLeave:Connect(function() tween(swStroke, 0.18, { Color = C('Border') }) end)

    local ui = nil

    function ColorPicker:Display()
        ColorPicker.Value = Color3.fromHSV(ColorPicker.Hue, ColorPicker.Sat, ColorPicker.Vib)
        swatch.BackgroundColor3 = ColorPicker.Value
        if ui then pcall(ui.refresh) end
        safeCall(ColorPicker.Callback, ColorPicker.Value)
        safeCall(ColorPicker.Changed, ColorPicker.Value)
    end

    function ColorPicker:OnChanged(Func)
        ColorPicker.Changed = Func
        safeCall(Func, ColorPicker.Value)
    end

    local function build(root)
        local PAD, SV = 8, 150
        local top = 24
        local title = New('TextLabel', { Position = fromOffset(PAD, 4), Size = UDim2new(1, -PAD * 2, 0, 16), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, Parent = root }, { TextColor3 = 'TextDim' })
        setText(title, ColorPicker.Title)

        local sv = New('TextButton', { Text = '', BackgroundTransparency = 0, Position = fromOffset(PAD, top), Size = fromOffset(SV, SV), Parent = root })
        local white = New('Frame', { Size = fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), Parent = sv })
        New('UIGradient', { Transparency = NumberSequence.new(0, 1), Parent = white })
        local black = New('Frame', { Size = fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), Parent = sv })
        New('UIGradient', { Rotation = 90, Transparency = NumberSequence.new(1, 0), Parent = black })
        New('UIStroke', { Parent = sv }, { Color = 'Border' })
        local svCursor = New('Frame', { AnchorPoint = V2(0.5, 0.5), Size = fromOffset(5, 5), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 2, Parent = sv })
        New('UIStroke', { Color = Color3.new(0, 0, 0), Parent = svCursor })

        local hx = PAD + SV + 8
        local hue = New('TextButton', { Text = '', BackgroundTransparency = 0, Position = fromOffset(hx, top), Size = fromOffset(12, SV), BackgroundColor3 = Color3.new(1, 1, 1), Parent = root })
        local keys = {}
        for i = 0, 6 do keys[#keys + 1] = ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i == 6 and 0 or i / 6, 1, 1)) end
        New('UIGradient', { Rotation = 90, Color = ColorSequence.new(keys), Parent = hue })
        New('UIStroke', { Parent = hue }, { Color = 'Border' })
        local hueCursor = New('Frame', { AnchorPoint = V2(0.5, 0.5), Size = UDim2new(1, 4, 0, 2), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 2, Parent = hue })
        New('UIStroke', { Color = Color3.new(0, 0, 0), Parent = hueCursor })

        local width = hx + 12 + PAD
        local alpha, alphaCursor
        if hasAlpha then
            local ax = hx + 12 + 8
            New('Frame', { Position = fromOffset(ax, top), Size = fromOffset(12, SV), Parent = root }, { BackgroundColor3 = 'Panel' })
            alpha = New('TextButton', { Text = '', BackgroundTransparency = 0, Position = fromOffset(ax, top), Size = fromOffset(12, SV), Parent = root })
            New('UIGradient', { Rotation = 90, Transparency = NumberSequence.new(0, 1), Parent = alpha })
            New('UIStroke', { Parent = alpha }, { Color = 'Border' })
            alphaCursor = New('Frame', { AnchorPoint = V2(0.5, 0.5), Size = UDim2new(1, 4, 0, 2), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 2, Parent = alpha })
            New('UIStroke', { Color = Color3.new(0, 0, 0), Parent = alphaCursor })
            width = ax + 12 + PAD
        end

        local by = top + SV + 8
        local hex = New('TextBox', { Position = fromOffset(PAD, by), Size = fromOffset(78, 18), TextSize = 12, BackgroundTransparency = 0, Parent = root }, { BackgroundColor3 = 'Panel', TextColor3 = 'Text' })
        New('UIStroke', { Parent = hex }, { Color = 'Border' })
        local rgbText = New('TextLabel', { Position = fromOffset(PAD + 84, by), Size = UDim2new(1, -(PAD * 2 + 84), 0, 18), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, Parent = root }, { TextColor3 = 'TextMuted' })

        local function refresh()
            sv.BackgroundColor3 = Color3.fromHSV(ColorPicker.Hue, 1, 1)
            svCursor.Position = fromScale(ColorPicker.Sat, 1 - ColorPicker.Vib)
            hueCursor.Position = UDim2new(0.5, 0, ColorPicker.Hue, 0)
            if alpha then
                alpha.BackgroundColor3 = ColorPicker.Value
                alphaCursor.Position = UDim2new(0.5, 0, ColorPicker.Transparency, 0)
            end
            if not hex:IsFocused() then hex.Text = '#' .. ColorPicker.Value:ToHex() end
            local c = ColorPicker.Value
            rgbText.Text = string.format('%d, %d, %d', floor(c.R * 255 + 0.5), floor(c.G * 255 + 0.5), floor(c.B * 255 + 0.5))
        end

        local function dragOn(btn, fn)
            btn.MouseButton1Down:Connect(function()
                Drag = { move = fn }
                fn(mouse())
            end)
        end
        dragOn(sv, function(m)
            local p, s = sv.AbsolutePosition, sv.AbsoluteSize
            ColorPicker.Sat = clamp((m.X - p.X) / max(1, s.X), 0, 1)
            ColorPicker.Vib = 1 - clamp((m.Y - p.Y) / max(1, s.Y), 0, 1)
            ColorPicker:Display()
        end)
        dragOn(hue, function(m)
            local p, s = hue.AbsolutePosition, hue.AbsoluteSize
            ColorPicker.Hue = clamp((m.Y - p.Y) / max(1, s.Y), 0, 1)
            ColorPicker:Display()
        end)
        if alpha then
            dragOn(alpha, function(m)
                local p, s = alpha.AbsolutePosition, alpha.AbsoluteSize
                ColorPicker.Transparency = clamp((m.Y - p.Y) / max(1, s.Y), 0, 1)
                ColorPicker:Display()
            end)
        end
        hex.FocusLost:Connect(function()
            local s = hex.Text:gsub('#', ''):gsub('%s', '')
            local ok, c = pcall(Color3.fromHex, s)
            if ok and typeof(c) == 'Color3' then
                ColorPicker:SetValueRGB(c, ColorPicker.Transparency)
            end
            refresh()
        end)

        ui = { refresh = refresh, width = width }
        refresh()
        return by + 18 + 8, width
    end

    function ColorPicker:Show()
        if Current and Current.owner == ColorPicker then return end
        local width = 8 + 150 + 8 + 12 + 8 + (hasAlpha and 20 or 0)
        openPopup({
            owner = ColorPicker, anchor = swatch, clip = ParentObj._clip, width = width, align = 'right', bg = 'Window',
            build = function(root) local h = build(root) return h end,
            onClose = function() ui = nil end,
        })
    end

    function ColorPicker:Hide()
        if Current and Current.owner == ColorPicker then closePopup() end
    end

    function ColorPicker:SetValue(HSV, Transparency)
        local Color = Color3.fromHSV(HSV[1], HSV[2], HSV[3])
        ColorPicker.Transparency = Transparency or 0
        ColorPicker:SetHSVFromRGB(Color)
        ColorPicker:Display()
    end

    function ColorPicker:SetValueRGB(Color, Transparency)
        ColorPicker.Transparency = Transparency or 0
        ColorPicker:SetHSVFromRGB(Color)
        ColorPicker:Display()
    end

    swatch.MouseButton1Down:Connect(function()
        if Current and Current.owner == ColorPicker then closePopup() return end
        if Library:MouseIsOverOpenedFrame() then return end
        ColorPicker:Show()
    end)

    ColorPicker:Display()
    ColorPicker.DisplayFrame = swatch

    Options[Idx] = ColorPicker
    return self
end

-- ============================================================================
-- Groupbox contents
-- ============================================================================
local GroupFuncs = {}
local GroupMeta = { __index = GroupFuncs }

function GroupFuncs:_row(height, search)
    self._order = (self._order or 0) + 1
    local row = New('Frame', { BackgroundTransparency = 1, Size = UDim2new(1, 0, 0, height or 0), LayoutOrder = self._order, Parent = self.Container })
    if height == nil then row.AutomaticSize = Enum.AutomaticSize.Y end
    local entry
    if search ~= false then entry = registerSearch(row, search, self) end
    return row, entry
end

function GroupFuncs:Resize() end

function GroupFuncs:AddBlank(Size)
    self:_row(tonumber(Size) or 0, false)
end

function GroupFuncs:AddLabel(Text, DoesWrap)
    local Label = {}
    local row, lbl
    if DoesWrap then
        row = self:_row(nil, Text)
        New('UIPadding', { PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 7), Parent = row })
        lbl = New('TextLabel', {
            Position = fromOffset(GUTTER, 0), Size = UDim2new(1, -GUTTER, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
            TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
            LineHeight = 1.12, Parent = row,
        }, { TextColor3 = 'TextDim' })
    else
        local entry
        row, entry = self:_row(20, Text)
        Label._search = entry
        lbl = New('TextLabel', {
            Position = fromOffset(GUTTER, 0), Size = UDim2new(1, -GUTTER, 1, 0), TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
        }, { TextColor3 = 'Text' })
        Label._holder = addonHolder(row, nil, lbl, GUTTER)
        Label._clip = self._clip
    end
    setText(lbl, Text)

    Label.TextLabel = lbl
    Label.Container = self.Container

    function Label:SetText(NewText)
        setText(lbl, NewText)
        if Label._search then Label._search.text = lower(tostring(NewText or '')) end
    end

    if not DoesWrap then setmetatable(Label, AddonMeta) end
    return Label
end

local function processButtonParams(Obj, ...)
    local Props = select(1, ...)
    if type(Props) == 'table' then
        Obj.Text = Props.Text
        Obj.Func = Props.Func
        Obj.DoubleClick = Props.DoubleClick
        Obj.Tooltip = Props.Tooltip
    else
        Obj.Text = select(1, ...)
        Obj.Func = select(2, ...)
    end
    assert(type(Obj.Func) == 'function', 'AddButton: `Func` callback is missing.')
end

-- Button text that is wider than its box shrinks (13 down to 10), and is cut
-- with "..." only if it still doesn't fit. Re-fits when the box or text changes.
local BUTTON_TEXT_MAX, BUTTON_TEXT_MIN = 13, 10
local Measure = New('TextLabel', {
    Position = fromOffset(-5000, -5000), Size = fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X,
    TextTransparency = 1, Parent = Overlay,
})
-- width of a button's text at full size (unscaled pixels)
local function textWidth(str)
    Measure.FontFace = Fonts.body
    Measure.TextSize = BUTTON_TEXT_MAX
    Measure.Text = str
    return Measure.TextBounds.X
end

local function fitButtonText(btn)
    local function fit()
        local size = BUTTON_TEXT_MAX
        btn.TextTruncate = Enum.TextTruncate.None
        btn.TextSize = size
        while not btn.TextFits and size > BUTTON_TEXT_MIN do
            size = size - 1
            btn.TextSize = size
        end
        if not btn.TextFits then btn.TextTruncate = Enum.TextTruncate.AtEnd end
    end
    btn:GetPropertyChangedSignal('AbsoluteSize'):Connect(fit)
    btn:GetPropertyChangedSignal('Text'):Connect(fit)
    btn:GetPropertyChangedSignal('FontFace'):Connect(fit)
    fit()
    -- once more after the font has had time to load
    task.delay(1.5, function() if btn.Parent then fit() end end)
end

function GroupFuncs:AddButton(...)
    local Button = {}
    processButtonParams(Button, ...)

    local row, entry = self:_row(29, Button.Text)
    local strip = New('Frame', { BackgroundTransparency = 1, Position = fromOffset(GUTTER, 4), Size = UDim2new(1, -2 * GUTTER, 0, 20), Parent = row })
    local stripLayout = New('UIListLayout', { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6), Parent = strip })
    local members = {}

    -- Buttons share the row while every label fits (shrunk at most to the
    -- minimum size); otherwise they stack, one full-width button per line.
    local function relayout()
        local n = #members
        local width = strip.AbsoluteSize.X / curScale()
        local stack = false
        if n > 1 and width > 0 then
            local per = (width - 6 * (n - 1)) / n - 10
            for _, b in ipairs(members) do
                if textWidth(b.Outer.Text) * (BUTTON_TEXT_MIN + 0.5) / BUTTON_TEXT_MAX > per then stack = true end
            end
        end
        if stack then
            stripLayout.FillDirection = Enum.FillDirection.Vertical
            stripLayout.Padding = UDim.new(0, 4)
            for _, b in ipairs(members) do b.Outer.Size = UDim2new(1, 0, 0, 20) end
            local h = n * 20 + (n - 1) * 4
            strip.Size = UDim2new(1, -2 * GUTTER, 0, h)
            row.Size = UDim2new(1, 0, 0, h + 9)
        else
            stripLayout.FillDirection = Enum.FillDirection.Horizontal
            stripLayout.Padding = UDim.new(0, 6)
            for _, b in ipairs(members) do b.Outer.Size = UDim2new(1 / n, -6 * (n - 1) / n, 0, 20) end
            strip.Size = UDim2new(1, -2 * GUTTER, 0, 20)
            row.Size = UDim2new(1, 0, 0, 29)
        end
    end
    local lastWidth = -1
    strip:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()
        local w = strip.AbsoluteSize.X
        if math.abs(w - lastWidth) < 0.5 then return end
        lastWidth = w
        relayout()
    end)
    table.insert(Restylers, relayout)
    task.delay(1.5, function() if strip.Parent then relayout() end end)

    local function makeButton(Obj)
        local btn = New('TextButton', { Size = fromScale(1, 1), LayoutOrder = #members + 1, Parent = strip }, { BackgroundColor3 = 'Element' })
        local stroke = New('UIStroke', { Parent = btn }, { Color = 'Border' })
        New('UIPadding', { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5), Parent = btn })
        setText(btn, Obj.Text)
        Obj.Outer, Obj.Inner, Obj.Label = btn, btn, btn
        members[#members + 1] = Obj
        fitButtonText(btn)
        relayout()

        local hover = false
        local function paint(t)
            tween(btn, t or 0.15, { BackgroundColor3 = hover and C('ElementHover') or C('Element') })
            tween(stroke, t or 0.2, { Color = hover and C('BorderLight') or C('Border') })
            if not Obj._armed then tween(btn, t or 0.15, { TextColor3 = C('Text') }) end
        end
        btn.MouseEnter:Connect(function() hover = true; paint() end)
        btn.MouseLeave:Connect(function() hover = false; paint() end)
        table.insert(Restylers, function() paint(0) end)

        local function flash()
            stroke.Color = C('Accent')
            tween(stroke, 0.4, { Color = hover and C('BorderLight') or C('Border') })
        end

        btn.MouseButton1Click:Connect(function()
            if Library:MouseIsOverOpenedFrame() or Obj.Locked then return end
            flash()
            if Obj.DoubleClick then
                if Obj._armed and clock() - Obj._armed < 0.5 then
                    Obj._armed = nil
                    setText(btn, Obj.Text)
                    paint(0)
                    safeCall(Obj.Func)
                else
                    local stamp = clock()
                    Obj._armed = stamp
                    setText(btn, 'Are you sure?')
                    btn.TextColor3 = C('Accent')
                    task.delay(0.5, function()
                        if Obj._armed == stamp then
                            Obj._armed = nil
                            setText(btn, Obj.Text)
                            paint()
                        end
                    end)
                end
                return
            end
            safeCall(Obj.Func)
        end)

        function Obj:AddTooltip(tooltip)
            if type(tooltip) == 'string' then Library:AddToolTip(tooltip, btn) end
            return self
        end
        if type(Obj.Tooltip) == 'string' then Obj:AddTooltip(Obj.Tooltip) end
        paint(0)
    end

    makeButton(Button)

    function Button:AddButton(...)
        local Sub = {}
        processButtonParams(Sub, ...)
        makeButton(Sub)
        if entry then entry.text = entry.text .. ' ' .. lower(tostring(Sub.Text or '')) end
        Sub.AddButton = function(_, ...) return Button:AddButton(...) end
        return Sub
    end

    return Button
end

function GroupFuncs:AddDivider()
    local row = self:_row(13, false)
    New('Frame', { Position = fromOffset(GUTTER, 6), Size = UDim2new(1, -2 * GUTTER, 0, 1), Parent = row }, { BackgroundColor3 = 'Border' })
    return { Type = 'Divider' }
end

function GroupFuncs:AddInput(Idx, Info)
    assert(Info.Text, 'AddInput: Missing `Text` string.')

    local Textbox = {
        Value = Info.Default or '',
        Numeric = Info.Numeric or false,
        Finished = Info.Finished or false,
        Type = 'Input',
        Callback = Info.Callback or function(Value) end,
    }

    local row = self:_row(46, Info.Text)
    local label = New('TextLabel', { Position = fromOffset(GUTTER, 3), Size = UDim2new(1, -GUTTER, 0, 15), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = row }, { TextColor3 = 'Text' })
    setText(label, Info.Text)
    local frame = New('Frame', { Position = fromOffset(GUTTER, 20), Size = UDim2new(1, -2 * GUTTER, 0, 20), ClipsDescendants = true, Parent = row }, { BackgroundColor3 = 'Element' })
    local stroke = New('UIStroke', { Parent = frame }, { Color = 'Border' })
    local box = New('TextBox', {
        Position = fromOffset(7, 0), Size = UDim2new(1, -14, 1, 0), Text = tostring(Textbox.Value),
        PlaceholderText = Info.Placeholder or '', TextXAlignment = Enum.TextXAlignment.Left, Parent = frame,
    }, { TextColor3 = 'Text', PlaceholderColor3 = 'TextMuted' })

    local hover, focused = false, false
    local function paint()
        tween(stroke, 0.15, { Color = focused and C('AccentDim') or (hover and C('BorderLight') or C('Border')) })
    end
    local function fitText()
        box.TextXAlignment = (focused and not box.TextFits) and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left
    end
    frame.MouseEnter:Connect(function() hover = true; paint() end)
    frame.MouseLeave:Connect(function() hover = false; paint() end)
    box.Focused:Connect(function() focused = true; paint(); fitText() end)
    table.insert(Restylers, paint)

    if type(Info.Tooltip) == 'string' then Library:AddToolTip(Info.Tooltip, frame) end

    function Textbox:SetValue(Text)
        Text = tostring(Text == nil and '' or Text)
        if Info.MaxLength and #Text > Info.MaxLength then
            Text = Text:sub(1, Info.MaxLength)
        end
        if Textbox.Numeric then
            if (not tonumber(Text)) and Text:len() > 0 and not Text:match('^%-?%.?$') then
                Text = Textbox.Value
            end
        end
        Textbox.Value = Text
        if box.Text ~= Text then box.Text = Text end
        safeCall(Textbox.Callback, Textbox.Value)
        safeCall(Textbox.Changed, Textbox.Value)
    end

    if Textbox.Finished then
        box.FocusLost:Connect(function()
            focused = false
            paint()
            fitText()
            if box.Text ~= Textbox.Value then
                Textbox:SetValue(box.Text)
                Library:AttemptSave()
            end
        end)
    else
        box.FocusLost:Connect(function() focused = false; paint(); fitText() end)
        box:GetPropertyChangedSignal('Text'):Connect(function()
            fitText()
            if box.Text ~= Textbox.Value then
                Textbox:SetValue(box.Text)
                Library:AttemptSave()
            end
        end)
    end

    function Textbox:OnChanged(Func)
        Textbox.Changed = Func
        safeCall(Func, Textbox.Value)
    end

    Options[Idx] = Textbox
    return Textbox
end

function GroupFuncs:AddToggle(Idx, Info)
    assert(Info.Text, 'AddToggle: Missing `Text` string.')

    local Toggle = {
        Value = Info.Default or false,
        Type = 'Toggle',
        Callback = Info.Callback or function(Value) end,
        Addons = {},
        Risky = Info.Risky,
    }

    local row = self:_row(20, Info.Text)
    local check = New('Frame', { Position = fromOffset(1, 6), Size = fromOffset(8, 8), Parent = row })
    local stroke = New('UIStroke', { Parent = check })
    New('UIGradient', { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), rgb(196, 196, 202)), Parent = check })
    local pop = New('UIScale', { Parent = check })
    local label = New('TextLabel', {
        Position = fromOffset(GUTTER, 0), Size = UDim2new(1, -GUTTER, 1, 0), TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
    })
    setText(label, Info.Text)
    local hit = New('TextButton', { BackgroundTransparency = 1, Size = fromScale(1, 1), Text = '', ZIndex = 2, Parent = row })
    Toggle._holder = addonHolder(row, hit, label, GUTTER)
    Toggle._clip = self._clip

    local hover = false
    function Toggle:Display(instant)
        local on = Toggle.Value
        local t = instant and 0 or 0.16
        tween(check, t, { BackgroundColor3 = on and C('Accent') or (hover and C('ElementHover') or C('Element')) })
        tween(stroke, t, { Color = on and C('AccentDim') or (hover and C('BorderLight') or C('Border')) })
        tween(label, t, { TextColor3 = Toggle.Risky and C('Risk') or ((on or hover) and C('Text') or C('TextDim')) })
    end

    function Toggle:UpdateColors()
        Toggle:Display(true)
    end

    function Toggle:OnChanged(Func)
        Toggle.Changed = Func
        safeCall(Func, Toggle.Value)
    end

    function Toggle:SetValue(Bool)
        Bool = (not not Bool)
        local was = Toggle.Value
        Toggle.Value = Bool
        Toggle:Display()
        if Bool and not was and Prefs.animations then
            pop.Scale = 0.55
            tween(pop, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
        end
        for _, Addon in next, Toggle.Addons do
            if Addon.Type == 'KeyPicker' and Addon.SyncToggleState then
                Addon.Toggled = Bool
                Addon:Update()
            end
        end
        safeCall(Toggle.Callback, Toggle.Value)
        safeCall(Toggle.Changed, Toggle.Value)
        Library:UpdateDependencyBoxes()
    end

    hit.MouseEnter:Connect(function() hover = true; Toggle:Display() end)
    hit.MouseLeave:Connect(function() hover = false; Toggle:Display() end)
    hit.MouseButton1Down:Connect(function()
        if Library:MouseIsOverOpenedFrame() then return end
        Toggle:SetValue(not Toggle.Value)
        Library:AttemptSave()
    end)
    if type(Info.Tooltip) == 'string' then Library:AddToolTip(Info.Tooltip, hit) end

    table.insert(Restylers, function() Toggle:Display(true) end)
    Toggle:Display(true)

    Toggle.TextLabel = label
    Toggle.Container = self.Container
    setmetatable(Toggle, AddonMeta)

    Toggles[Idx] = Toggle
    Library:UpdateDependencyBoxes()
    return Toggle
end

function GroupFuncs:AddSlider(Idx, Info)
    assert(Info.Default, 'AddSlider: Missing default value.')
    assert(Info.Text, 'AddSlider: Missing slider text.')
    assert(Info.Min, 'AddSlider: Missing minimum value.')
    assert(Info.Max, 'AddSlider: Missing maximum value.')
    assert(Info.Rounding, 'AddSlider: Missing rounding value.')

    local Slider = {
        Value = Info.Default,
        Min = Info.Min,
        Max = Info.Max,
        Rounding = Info.Rounding,
        MaxSize = 232,
        Type = 'Slider',
        Callback = Info.Callback or function(Value) end,
    }

    local row = self:_row(37, Info.Text)
    local lbl = New('TextLabel', { Position = fromOffset(GUTTER, 3), Size = UDim2new(1, -GUTTER - 74, 0, 15), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = row }, { TextColor3 = 'Text' })
    setText(lbl, Info.Text)
    local val = New('TextBox', { AnchorPoint = V2(1, 0), Position = UDim2new(1, -GUTTER, 0, 3), Size = fromOffset(72, 15), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, Parent = row }, { TextColor3 = 'TextDim' })
    local track = New('Frame', { Position = fromOffset(GUTTER, 24), Size = UDim2new(1, -2 * GUTTER, 0, 5), Parent = row }, { BackgroundColor3 = 'Element' })
    local tStroke = New('UIStroke', { Parent = track }, { Color = 'Border' })
    local fill = New('Frame', { Size = fromScale(0, 1), Parent = track }, { BackgroundColor3 = 'Accent' })
    New('UIGradient', { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), rgb(200, 200, 206)), Parent = fill })
    local hit = New('TextButton', { BackgroundTransparency = 1, Text = '', Position = fromOffset(GUTTER - 3, 19), Size = UDim2new(1, -2 * GUTTER + 6, 0, 15), ZIndex = 2, Parent = row })
    local minus = New('TextButton', { BackgroundTransparency = 1, Text = '-', TextSize = 14, Position = fromOffset(0, 19), Size = fromOffset(GUTTER - 3, 15), Parent = row }, { TextColor3 = 'TextMuted' })
    local plus = New('TextButton', { BackgroundTransparency = 1, Text = '+', TextSize = 13, AnchorPoint = V2(1, 0), Position = UDim2new(1, 0, 0, 19), Size = fromOffset(GUTTER - 3, 15), Parent = row }, { TextColor3 = 'TextMuted' })

    local function Round(Value)
        if Slider.Rounding == 0 then return floor(Value) end
        return tonumber(string.format('%.' .. Slider.Rounding .. 'f', Value))
    end

    local function fmt(v)
        local r = tonumber(Slider.Rounding) or 0
        if r <= 0 then
            if v == floor(v) then return string.format('%d', v) end
            return tostring(v)
        end
        return string.format('%.' .. r .. 'f', v)
    end

    local shownFrac
    local hover, dragging = false, false
    local function frac()
        if Slider.Max == Slider.Min then return 0 end
        return clamp((Slider.Value - Slider.Min) / (Slider.Max - Slider.Min), 0, 1)
    end

    local function paint()
        tween(tStroke, 0.15, { Color = dragging and C('AccentDim') or (hover and C('BorderLight') or C('Border')) })
    end

    function Slider:Display(instant)
        if not val:IsFocused() then val.Text = fmt(Slider.Value) .. (Info.Suffix or '') end
        local target = frac()
        if instant or shownFrac == nil or not Prefs.animations then
            Anims[fill] = nil
            shownFrac = target
            fill.Size = fromScale(target, 1)
        else
            animate(fill, 0.14, shownFrac, target, function(v)
                shownFrac = v
                fill.Size = fromScale(v, 1)
            end, nil, easeOutQuint)
        end
    end

    function Slider:UpdateColors()
        paint()
    end

    function Slider:OnChanged(Func)
        Slider.Changed = Func
        safeCall(Func, Slider.Value)
    end

    function Slider:GetValueFromXOffset(X)
        return Round(Library:MapValue(X, 0, Slider.MaxSize, Slider.Min, Slider.Max))
    end

    function Slider:SetValue(Str)
        local Num = tonumber(Str)
        if not Num then return end
        Num = clamp(Num, Slider.Min, Slider.Max)
        Slider.Value = Num
        Slider:Display()
        safeCall(Slider.Callback, Slider.Value)
        safeCall(Slider.Changed, Slider.Value)
    end

    local function commit(nv)
        nv = clamp(nv, min(Slider.Min, Slider.Max), max(Slider.Min, Slider.Max))
        if nv ~= Slider.Value then
            Slider.Value = nv
            Slider:Display()
            safeCall(Slider.Callback, Slider.Value)
            safeCall(Slider.Changed, Slider.Value)
        end
    end

    local function setFromX(x)
        local ap, as = track.AbsolutePosition, track.AbsoluteSize
        local f = as.X > 0 and clamp((x - ap.X) / as.X, 0, 1) or 0
        commit(Round(Slider.Min + (Slider.Max - Slider.Min) * f))
    end

    hit.MouseEnter:Connect(function() hover = true; paint() end)
    hit.MouseLeave:Connect(function() hover = false; paint() end)
    hit.MouseButton1Down:Connect(function()
        if Library:MouseIsOverOpenedFrame() then return end
        dragging = true
        paint()
        setFromX(mouse().X)
        Drag = {
            move = function(m) setFromX(m.X) end,
            stop = function()
                dragging = false
                paint()
                Library:AttemptSave()
            end,
        }
    end)

    local holding = {}
    local function stepBy(dir)
        local r = tonumber(Slider.Rounding) or 0
        local inc = r > 0 and 10 ^ (-r) or 1
        commit(Round(Slider.Value + dir * inc + (r > 0 and 0 or 1e-9)))
    end
    local function holdButton(btn, dir)
        btn.MouseEnter:Connect(function() tween(btn, 0.12, { TextColor3 = C('Text') }) end)
        btn.MouseLeave:Connect(function()
            holding[btn] = nil
            tween(btn, 0.18, { TextColor3 = C('TextMuted') })
        end)
        btn.MouseButton1Up:Connect(function() holding[btn] = nil end)
        btn.MouseButton1Down:Connect(function()
            if Library:MouseIsOverOpenedFrame() then return end
            stepBy(dir)
            local token = {}
            holding[btn] = token
            task.delay(0.35, function()
                local n = 0
                while holding[btn] == token and not Library.Unloaded
                    and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
                    stepBy(dir)
                    n = n + 1
                    task.wait(n > 20 and 0.02 or 0.05)
                end
                if holding[btn] == token then holding[btn] = nil end
                Library:AttemptSave()
            end)
        end)
    end
    holdButton(minus, -1)
    holdButton(plus, 1)

    val.Focused:Connect(function()
        val.Text = tostring(Slider.Value)
        val.TextColor3 = C('Text')
    end)
    val.FocusLost:Connect(function()
        local n = tonumber((val.Text:gsub('[^%d%.%-eE]', '')))
        val.TextColor3 = C('TextDim')
        if n then
            n = Round(clamp(n, min(Slider.Min, Slider.Max), max(Slider.Min, Slider.Max)))
            if n ~= Slider.Value then
                Slider:SetValue(n)
                Library:AttemptSave()
            end
        end
        Slider:Display(true)
    end)

    if type(Info.Tooltip) == 'string' then Library:AddToolTip(Info.Tooltip, hit) end

    table.insert(Restylers, function() paint(); val.TextColor3 = val:IsFocused() and C('Text') or C('TextDim') end)
    Slider:Display(true)

    Options[Idx] = Slider
    return Slider
end

local function playerNames(except)
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= except then list[#list + 1] = p.Name end
    end
    table.sort(list, function(a, b) return a < b end)
    return list
end

local function teamNames()
    local list = {}
    pcall(function()
        for _, t in ipairs(game:GetService('Teams'):GetTeams()) do list[#list + 1] = t.Name end
    end)
    table.sort(list, function(a, b) return a < b end)
    return list
end

function GroupFuncs:AddDropdown(Idx, Info)
    if Info.SpecialType == 'Player' then
        Info.Values = playerNames()
        Info.AllowNull = true
    elseif Info.SpecialType == 'Team' then
        Info.Values = teamNames()
        Info.AllowNull = true
    end

    assert(Info.Values, 'AddDropdown: Missing dropdown value list.')
    assert(Info.AllowNull or Info.Default, 'AddDropdown: Missing default value. Pass `AllowNull` as true if this was intentional.')

    if not Info.Text then Info.Compact = true end

    local Dropdown = {
        Values = Info.Values,
        Value = Info.Multi and {},
        Multi = Info.Multi,
        Type = 'Dropdown',
        SpecialType = Info.SpecialType,
        Callback = Info.Callback or function(Value) end,
    }

    local clip = self._clip
    local labelH = Info.Compact and 0 or 17
    local row = self:_row(3 + labelH + 26, Info.Text)
    if not Info.Compact then
        local lbl = New('TextLabel', { Position = fromOffset(GUTTER, 3), Size = UDim2new(1, -GUTTER, 0, 15), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = row }, { TextColor3 = 'Text' })
        setText(lbl, Info.Text)
    end
    local box = New('TextButton', { Position = fromOffset(GUTTER, 3 + labelH), Size = UDim2new(1, -2 * GUTTER, 0, 20), Text = '', Parent = row }, { BackgroundColor3 = 'Element' })
    local stroke = New('UIStroke', { Parent = box })
    local valueText = New('TextLabel', { Position = fromOffset(7, 0), Size = UDim2new(1, -28, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = box })
    local plusIcon = New('TextLabel', { AnchorPoint = V2(0.5, 0.5), Position = UDim2new(1, -10, 0.5, 0), Size = fromOffset(12, 12), Text = '+', TextSize = 15, Parent = box }, { TextColor3 = 'TextDim' })

    local hover, isOpen = false, false
    local function paintBox(t)
        tween(stroke, t or 0.15, { Color = isOpen and C('AccentDim') or (hover and C('BorderLight') or C('Border')) })
        tween(box, t or 0.15, { BackgroundColor3 = hover and C('ElementHover') or C('Element') })
    end

    local function isSelected(v)
        if Info.Multi then return type(Dropdown.Value) == 'table' and Dropdown.Value[v] == true end
        return Dropdown.Value == v
    end

    function Dropdown:Display()
        local Str
        if Info.Multi then
            local parts = {}
            if type(Dropdown.Value) == 'table' then
                for _, Value in next, Dropdown.Values do
                    if Dropdown.Value[Value] then parts[#parts + 1] = tostring(Value) end
                end
            end
            Str = table.concat(parts, ', ')
        else
            Str = (Dropdown.Value ~= nil and Dropdown.Value ~= false) and tostring(Dropdown.Value) or ''
        end
        if Str == '' then
            valueText.Text = 'none'
            valueText.TextColor3 = C('TextMuted')
        else
            valueText.Text = Str
            valueText.TextColor3 = C('Text')
        end
    end

    function Dropdown:GetActiveValues()
        if Info.Multi then
            local T = {}
            for Value in next, Dropdown.Value do table.insert(T, Value) end
            return T
        else
            return Dropdown.Value and 1 or 0
        end
    end

    local ROW = 18
    local list -- live list state while open

    local function fire()
        safeCall(Dropdown.Callback, Dropdown.Value)
        safeCall(Dropdown.Changed, Dropdown.Value)
        Library:UpdateDependencyBoxes()
    end

    local function buildList(root, p)
        for _, ch in ipairs(root:GetChildren()) do
            if not (ch:IsA('UIStroke') or ch:IsA('UIScale')) then ch:Destroy() end
        end
        local entries = {}
        local count = 0
        for _ in next, Dropdown.Values do count = count + 1 end
        local top = 2
        local search
        if count > 10 then
            search = New('TextBox', {
                Position = fromOffset(6, 5), Size = UDim2new(1, -12, 0, 18), TextSize = 12, PlaceholderText = 'search',
                TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 0, Parent = root,
            }, { BackgroundColor3 = 'Panel', TextColor3 = 'Text', PlaceholderColor3 = 'TextMuted' })
            New('UIPadding', { PaddingLeft = UDim.new(0, 6), Parent = search })
            New('UIStroke', { Parent = search }, { Color = 'Border' })
            top = 28
        end
        local sf = New('ScrollingFrame', {
            BackgroundTransparency = 1, Position = fromOffset(0, top), Size = UDim2new(1, 0, 0, min(count, 8) * ROW),
            CanvasSize = fromOffset(0, count * ROW), ScrollBarThickness = 2, ScrollingDirection = Enum.ScrollingDirection.Y,
            ElasticBehavior = Enum.ElasticBehavior.Never, Parent = root,
        }, { ScrollBarImageColor3 = 'TextMuted' })
        New('UIListLayout', { SortOrder = Enum.SortOrder.LayoutOrder, Parent = sf })
        smoothScroll(sf)

        local function paintEntry(e)
            local on = isSelected(e.value)
            e.t.TextColor3 = on and C('Text') or C('TextDim')
            if e.mark then e.mark.Visible = on end
            if e.check then
                e.check.BackgroundColor3 = on and C('Accent') or C('Element')
            end
        end

        local i = 0
        for _, Value in next, Dropdown.Values do
            i = i + 1
            local e = { value = Value, lower = lower(tostring(Value)) }
            e.r = popupRow(sf, i, ROW, function()
                local Selected = isSelected(Value)
                local Try = not Selected
                if Dropdown:GetActiveValues() == 1 and (not Try) and (not Info.AllowNull) then
                    return
                end
                if Info.Multi then
                    if Try then Dropdown.Value[Value] = true else Dropdown.Value[Value] = nil end
                else
                    if Try then Dropdown.Value = Value else Dropdown.Value = nil end
                end
                for _, other in ipairs(entries) do paintEntry(other) end
                Dropdown:Display()
                fire()
                Library:AttemptSave()
                if not Info.Multi and Try then closePopup() end
            end)
            local tx = 10
            if Info.Multi then
                e.check = New('Frame', { Position = fromOffset(8, 6), Size = fromOffset(6, 6), Parent = e.r })
                New('UIStroke', { Parent = e.check }, { Color = 'BorderLight' })
                tx = 21
            else
                e.mark = New('Frame', { Position = fromOffset(0, 4), Size = fromOffset(2, ROW - 8), Visible = false, Parent = e.r }, { BackgroundColor3 = 'Accent' })
            end
            e.t = New('TextLabel', { Position = fromOffset(tx, 0), Size = UDim2new(1, -(tx + 6), 1, 0), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = tostring(Value), Parent = e.r })
            paintEntry(e)
            entries[#entries + 1] = e
        end

        local function sizeFor(n)
            return top + min(n, 8) * ROW + 2
        end
        if search then
            search:GetPropertyChangedSignal('Text'):Connect(function()
                local q = lower(search.Text)
                local n = 0
                for _, e in ipairs(entries) do
                    local show = q == '' or e.lower:find(q, 1, true) ~= nil
                    e.r.Visible = show
                    if show then n = n + 1 end
                end
                sf.CanvasSize = fromOffset(0, n * ROW)
                sf.Size = UDim2new(1, 0, 0, min(max(n, 1), 8) * ROW)
                if p and p.resize then p.resize(sizeFor(max(n, 1))) end
            end)
        end
        list = { entries = entries, paint = function() for _, e in ipairs(entries) do paintEntry(e) end end }
        return sizeFor(max(count, 1))
    end

    local function open()
        local s = Prefs.scale / 100
        local p = openPopup({
            owner = Dropdown, anchor = box, clip = clip, width = max(80, box.AbsoluteSize.X / s), build = buildList,
            onClose = function()
                isOpen = false
                list = nil
                tween(plusIcon, 0.2, { Rotation = 0 })
                paintBox()
            end,
        })
        if p then
            isOpen = true
            tween(plusIcon, 0.25, { Rotation = 45 })
            paintBox()
        end
    end

    function Dropdown:BuildDropdownList()
        if Current and Current.owner == Dropdown then
            local p = Current
            local h = buildList(p.root, p)
            p.resize(h)
        end
        Dropdown:Display()
    end

    function Dropdown:SetValues(NewValues)
        if NewValues then Dropdown.Values = NewValues end
        Dropdown:BuildDropdownList()
    end

    function Dropdown:OpenDropdown()
        if not (Current and Current.owner == Dropdown) then open() end
    end

    function Dropdown:CloseDropdown()
        if Current and Current.owner == Dropdown then closePopup() end
    end

    function Dropdown:OnChanged(Func)
        Dropdown.Changed = Func
        safeCall(Func, Dropdown.Value)
    end

    function Dropdown:SetValue(Val)
        if Dropdown.Multi then
            local nTable = {}
            for Value in next, (type(Val) == 'table' and Val or {}) do
                if table.find(Dropdown.Values, Value) then nTable[Value] = true end
            end
            Dropdown.Value = nTable
        else
            if not Val then
                Dropdown.Value = nil
            elseif table.find(Dropdown.Values, Val) then
                Dropdown.Value = Val
            end
        end
        if list then list.paint() end
        Dropdown:Display()
        fire()
    end

    function Dropdown:UpdateColors()
        paintBox(0)
        Dropdown:Display()
    end

    box.MouseEnter:Connect(function() hover = true; paintBox() end)
    box.MouseLeave:Connect(function() hover = false; paintBox() end)
    box.MouseButton1Down:Connect(function()
        if Current and Current.owner == Dropdown then closePopup() return end
        if Library:MouseIsOverOpenedFrame() then return end
        open()
    end)
    if type(Info.Tooltip) == 'string' then Library:AddToolTip(Info.Tooltip, box) end

    local Defaults = {}
    if type(Info.Default) == 'string' then
        local i = table.find(Dropdown.Values, Info.Default)
        if i then table.insert(Defaults, i) end
    elseif type(Info.Default) == 'table' then
        for _, Value in next, Info.Default do
            local i = table.find(Dropdown.Values, Value)
            if i then table.insert(Defaults, i) end
        end
    elseif type(Info.Default) == 'number' and Dropdown.Values[Info.Default] ~= nil then
        table.insert(Defaults, Info.Default)
    end
    if next(Defaults) then
        for i = 1, #Defaults do
            local Index = Defaults[i]
            if Info.Multi then
                Dropdown.Value[Dropdown.Values[Index]] = true
            else
                Dropdown.Value = Dropdown.Values[Index]
            end
            if not Info.Multi then break end
        end
    end

    table.insert(Restylers, function() Dropdown:UpdateColors() end)
    paintBox(0)
    Dropdown:Display()

    Options[Idx] = Dropdown
    return Dropdown
end

function GroupFuncs:AddDependencyBox()
    self._order = (self._order or 0) + 1
    local holder = New('Frame', {
        BackgroundTransparency = 1, Size = UDim2new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = self._order, Visible = false, Parent = self.Container,
    })
    New('UIListLayout', { SortOrder = Enum.SortOrder.LayoutOrder, Parent = holder })

    local Depbox = setmetatable({
        Dependencies = {}, Visible = false, Container = holder,
        _tab = self._tab, _group = self._group, _clip = self._clip, _order = 0,
    }, GroupMeta)

    function Depbox:Resize() end

    function Depbox:Update()
        for _, Dependency in next, Depbox.Dependencies do
            local Elem, Value = Dependency[1], Dependency[2]
            local ok = true
            if type(Elem) == 'table' then
                if Elem.Type == 'Toggle' then
                    ok = Elem.Value == Value
                elseif Elem.Type == 'Dropdown' then
                    if type(Elem.Value) == 'table' then ok = Elem.Value[Value] == true else ok = Elem.Value == Value end
                end
            end
            if not ok then
                holder.Visible = false
                Depbox.Visible = false
                return
            end
        end
        Depbox.Visible = true
        holder.Visible = true
    end

    function Depbox:SetupDependencies(Dependencies)
        for _, Dependency in next, Dependencies do
            assert(type(Dependency) == 'table', 'SetupDependencies: Dependency is not of type `table`.')
            assert(Dependency[1], 'SetupDependencies: Dependency is missing element argument.')
            assert(Dependency[2] ~= nil, 'SetupDependencies: Dependency is missing value argument.')
        end
        Depbox.Dependencies = Dependencies
        Depbox:Update()
    end

    table.insert(Library.DependencyBoxes, Depbox)
    return Depbox
end

function Library:UpdateDependencyBoxes()
    for _, Depbox in next, Library.DependencyBoxes do
        pcall(Depbox.Update, Depbox)
    end
end

-- ============================================================================
-- Crescent shape: a circle with a background-coloured circle laid over its
-- upper right. Drawn with frames, so it needs no image asset.
-- ============================================================================
local function crescent(parent, moonKey, cutKey)
    local moon = New('Frame', { AnchorPoint = V2(0.5, 0.5), Parent = parent }, { BackgroundColor3 = moonKey })
    New('UICorner', { CornerRadius = UDim.new(1, 0), Parent = moon })
    local cut = New('Frame', { AnchorPoint = V2(0.5, 0.5), Position = fromScale(0.5 + 0.28, 0.5 - 0.29), Size = fromScale(1.03, 1.03), Parent = moon }, { BackgroundColor3 = cutKey })
    New('UICorner', { CornerRadius = UDim.new(1, 0), Parent = cut })
    return moon, cut
end

-- ============================================================================
-- Window
-- ============================================================================
local WinDirty = {}
local WinAlpha = 0

function Library:CreateWindow(...)
    if Library.Window then return Library.Window end

    local Arguments = { ... }
    local Config = {}
    if type(Arguments[1]) == 'table' then
        Config = Arguments[1]
    else
        Config.Title = Arguments[1]
        Config.AutoShow = Arguments[2] or false
    end
    if type(Config.Title) ~= 'string' then Config.Title = 'No title' end
    local fadeTime = (type(Config.MenuFadeTime) == 'number') and Config.MenuFadeTime or 0.2

    local size = (typeof(Config.Size) == 'UDim2') and Config.Size or fromOffset(560, 620)
    local W = (size.X.Offset > 0) and size.X.Offset or 560
    local H = (size.Y.Offset > 0) and size.Y.Offset or 620
    if type(Prefs.width) == 'number' then W = Prefs.width end
    if type(Prefs.height) == 'number' then H = Prefs.height end
    local sc = screen()
    local k0 = Prefs.scale / 100
    W = clamp(W, MIN_W, max(MIN_W, sc.X / k0 - 20))
    H = clamp(H, MIN_H, max(MIN_H, sc.Y / k0 - 20))

    local center
    if Config.Center or typeof(Config.Position) ~= 'UDim2' then
        center = V2(sc.X / 2, sc.Y / 2)
    else
        local p = Config.Position
        center = V2(p.X.Offset + W / 2, p.Y.Offset + H / 2)
    end

    local Window = { Tabs = {} }
    Library.Window = Window

    local Outer = New('Frame', {
        AnchorPoint = V2(0.5, 0.5), Position = fromOffset(center.X, center.Y), Size = fromOffset(W, H),
        Visible = false, ZIndex = 1, Parent = ScreenGui,
    }, { BackgroundColor3 = 'Border' })
    New('UIStroke', { Parent = Outer }, { Color = 'Outline' })
    WinScaleObj = New('UIScale', { Scale = k0, Parent = Outer })
    local Main = New('Frame', { Position = fromOffset(1, 1), Size = UDim2new(1, -2, 1, -2), Parent = Outer }, { BackgroundColor3 = 'Window' })
    Window.Holder = Outer

    -- header: little moon, title, search
    local Header = New('Frame', { BackgroundTransparency = 1, Size = UDim2new(1, 0, 0, HEADER_H), Parent = Main })
    local logo = crescent(Header, 'Accent', 'Window')
    logo.Position = fromOffset(17, 15)
    logo.Size = fromOffset(11, 11)
    local Title = New('TextLabel', {
        Position = fromOffset(30, 1), Size = UDim2new(1, -210, 1, 0), TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd, Bold = true, Parent = Header,
    }, { TextColor3 = 'TextDim' })
    setText(Title, Config.Title)
    local DragArea = New('TextButton', { BackgroundTransparency = 1, Size = UDim2new(1, -176, 1, 0), Text = '', Parent = Header })
    local SearchFrame = New('Frame', { AnchorPoint = V2(1, 0.5), Position = UDim2new(1, -10, 0.5, 1), Size = fromOffset(156, 18), Parent = Header }, { BackgroundColor3 = 'Element' })
    local SearchStroke = New('UIStroke', { Parent = SearchFrame }, { Color = 'Border' })
    local SearchBox = New('TextBox', {
        Position = fromOffset(7, 0), Size = UDim2new(1, -14, 1, 0), TextSize = 12, PlaceholderText = 'search',
        TextXAlignment = Enum.TextXAlignment.Left, Parent = SearchFrame,
    }, { TextColor3 = 'Text', PlaceholderColor3 = 'TextMuted' })

    -- tab bar
    local TabBar = New('Frame', { BackgroundTransparency = 1, Position = fromOffset(10, HEADER_H), Size = UDim2new(1, -20, 0, TABS_H), Parent = Main })
    New('Frame', { Position = UDim2new(0, 0, 1, -1), Size = UDim2new(1, 0, 0, 1), Parent = TabBar }, { BackgroundColor3 = 'Border' })
    local Underline = New('Frame', { Position = UDim2new(0, 0, 1, -2), Size = fromOffset(0, 2), ZIndex = 2, Parent = TabBar }, { BackgroundColor3 = 'Accent' })

    -- content panel with the moon behind the pages
    local Panel = New('Frame', {
        Position = fromOffset(10, PANEL_TOP), Size = UDim2new(1, -20, 1, -(PANEL_TOP + 10)), ClipsDescendants = true, Parent = Main,
    }, { BackgroundColor3 = 'Panel' })
    New('UIStroke', { Parent = Panel }, { Color = 'Border' })
    local MoonLayer = New('Frame', { BackgroundTransparency = 1, Size = fromScale(1, 1), Parent = Panel })
    local Stars = {}
    do
        local rng = Random.new(20261105)
        for _ = 1, 26 do
            local x, y = rng:NextNumber(0.03, 0.97), rng:NextNumber(0.03, 0.97)
            if (x - 0.5) ^ 2 + (y - 0.5) ^ 2 > 0.12 then
                local s = (rng:NextNumber() < 0.25) and 2 or 1
                local f = New('Frame', { AnchorPoint = V2(0.5, 0.5), Position = fromScale(x, y), Size = fromOffset(s, s), Visible = Prefs.stars, Parent = MoonLayer }, { BackgroundColor3 = 'Star' })
                Stars[#Stars + 1] = { f = f, phase = rng:NextNumber(0, math.pi * 2), speed = rng:NextNumber(0.5, 1.4) }
            end
        end
    end
    local MoonBox = New('Frame', {
        BackgroundTransparency = 1, AnchorPoint = V2(0.5, 0.5), Position = fromScale(0.5, 0.5), Size = fromScale(0.6, 0.6),
        Visible = Prefs.moon, Parent = MoonLayer,
    })
    New('UIAspectRatioConstraint', { AspectRatio = 1, Parent = MoonBox })
    local Moon = crescent(MoonBox, 'Moon', 'Panel')
    Moon.Size = fromScale(1, 1)
    Moon.Position = fromScale(0.5825, 0.4125)
    New('UIGradient', { Rotation = 35, Color = ColorSequence.new(Color3.new(1, 1, 1), rgb(130, 130, 140)), Parent = Moon })
    local PageHolder = New('Frame', { BackgroundTransparency = 1, Size = fromScale(1, 1), Parent = Panel })

    -- resize grip
    local Grip = New('TextButton', { AnchorPoint = V2(1, 1), Position = UDim2new(1, -1, 1, -1), Size = fromOffset(10, 10), BackgroundTransparency = 1, Text = '', ZIndex = 3, Parent = Main })
    for _, d in ipairs({ { 7, 7 }, { 4, 7 }, { 7, 4 } }) do
        New('Frame', { Position = fromOffset(d[1] - 1, d[2] - 1), Size = fromOffset(2, 2), Parent = Grip }, { BackgroundColor3 = 'TextMuted' })
    end

    local WinSize = V2(W, H)
    local WinPos, WinTarget = center, center
    local function applyPos()
        Outer.Position = fromOffset(floor(WinPos.X + 0.5), floor(WinPos.Y + 0.5))
    end

    local AnimScale = 1
    local function applyScale()
        WinScaleObj.Scale = (Prefs.scale / 100) * AnimScale
    end

    -- ---------------------------------------------------------------- tabs
    local TabList = {}
    local ActiveTab = nil
    local PageAnimating = false

    local function paintTab(t, instant)
        local col
        if t == ActiveTab then col = C('Text')
        elseif t._miss then col = C('TextMuted')
        elseif t._hover then col = C('Text')
        else col = C('TextDim') end
        tween(t.Button, instant and 0 or 0.15, { TextColor3 = col })
    end

    local function moveUnderline(instant)
        local t = ActiveTab
        if not t or not t.W then return end
        local props = { Position = UDim2new(0, floor(t.X + 8 + 0.5), 1, -2), Size = fromOffset(max(0, floor(t.W - 16 + 0.5)), 2) }
        if instant then
            Underline.Position, Underline.Size = props.Position, props.Size
        else
            tween(Underline, 0.32, props)
        end
    end

    local function relayoutTabs(instant)
        local n = #TabList
        if n == 0 then return end
        table.sort(TabList, function(a, b) return a.Order < b.Order end)
        local nat, sum, mx = {}, 0, 0
        for i, t in ipairs(TabList) do
            local w = t.Button.TextBounds.X + 26
            nat[i] = w
            sum = sum + w
            mx = max(mx, w)
        end
        local avail = WinSize.X - 22
        if sum > avail then
            local k = curScale()
            local cap = screen().X / max(k, 0.01) - 20
            local need = min(sum + 22, cap)
            if need > WinSize.X then
                WinSize = V2(need, WinSize.Y)
                Outer.Size = fromOffset(WinSize.X, WinSize.Y)
                avail = WinSize.X - 22
            end
        end
        local widths = {}
        if mx * n <= avail then
            for i = 1, n do widths[i] = avail / n end
        elseif sum <= avail then
            local extra = (avail - sum) / n
            for i = 1, n do widths[i] = nat[i] + extra end
        else
            for i = 1, n do widths[i] = nat[i] * avail / sum end
        end
        local x = 0
        for i, t in ipairs(TabList) do
            t.X, t.W = x, widths[i]
            t.Button.Position = fromOffset(floor(x + 0.5), 0)
            t.Button.Size = fromOffset(floor(widths[i] + 0.5), TABS_H)
            x = x + widths[i]
        end
        moveUnderline(instant ~= false)
    end

    local function selectTab(t, instant)
        if ActiveTab == t then return end
        closePopup(true)
        local prev = ActiveTab
        ActiveTab = t
        if prev then
            prev.Page.Visible = false
            paintTab(prev)
        end
        t.Page.Visible = true
        paintTab(t)
        moveUnderline(instant)
        if instant or not Prefs.animations or WinAlpha <= 0 or not Library.Toggled then
            PageAlpha[t.Page] = nil
            t.Page.Position = fromOffset(0, 0)
            return
        end
        PageAlpha[t.Page] = 0
        t.Page.Position = fromOffset(0, 10)
        tween(t.Page, 0.4, { Position = fromOffset(0, 0) })
        PageAnimating = true
        local page = t.Page
        animate('page', 0.26, 0, 1, function(v)
            PageAlpha[page] = v
            fadeTree(page, WinAlpha * v, WinDirty)
        end, function()
            PageAlpha[page] = nil
            PageAnimating = false
            if not Anims.win and WinAlpha >= 1 then restoreDirty(WinDirty) end
        end, easeOutCubic)
    end

    local function column(page, side)
        local col = New('ScrollingFrame', {
            BackgroundTransparency = 1,
            Position = side == 1 and fromOffset(10, 0) or UDim2new(0.5, 5, 0, 0),
            Size = UDim2new(0.5, -15, 1, 0),
            CanvasSize = fromOffset(0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollBarThickness = 0,
            ScrollBarImageTransparency = 1,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            ElasticBehavior = Enum.ElasticBehavior.Never,
            Parent = page,
        })
        New('UIPadding', {
            PaddingTop = UDim.new(0, 16), PaddingBottom = UDim.new(0, 14), PaddingLeft = UDim.new(0, 1), PaddingRight = UDim.new(0, 1), Parent = col,
        })
        New('UIListLayout', { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 18), Parent = col })

        local thumbHit = New('TextButton', { BackgroundTransparency = 1, Text = '', Size = fromOffset(8, 20), Visible = false, ZIndex = 3, Parent = page })
        local thumb = New('Frame', { AnchorPoint = V2(0.5, 0), Position = UDim2new(0.5, 0, 0, 0), Size = UDim2new(0, 2, 1, 0), Parent = thumbHit }, { BackgroundColor3 = 'TextMuted' })
        local st
        local function geometry()
            local k = curScale()
            local view, canvas = col.AbsoluteWindowSize.Y, col.AbsoluteCanvasSize.Y
            local trackH = view / k - 16
            local thH = max(24, trackH * view / max(canvas, 1))
            return view, canvas, trackH, thH
        end
        local function updateThumb()
            local view, canvas, trackH, thH = geometry()
            if canvas <= view + 2 or view <= 0 then
                thumbHit.Visible = false
                return
            end
            thumbHit.Visible = true
            local m = st.maxY()
            local f = m > 0 and clamp(st.cur / m, 0, 1) or 0
            local y = 8 + (trackH - thH) * f
            thumbHit.Size = fromOffset(8, thH)
            thumbHit.Position = (side == 1) and UDim2new(0.5, -4, 0, y) or UDim2new(1, -9, 0, y)
        end
        st = smoothScroll(col, updateThumb)
        col:GetPropertyChangedSignal('AbsoluteCanvasSize'):Connect(updateThumb)
        col:GetPropertyChangedSignal('AbsoluteWindowSize'):Connect(updateThumb)
        thumbHit.MouseEnter:Connect(function() tween(thumb, 0.12, { BackgroundColor3 = C('TextDim') }) end)
        thumbHit.MouseLeave:Connect(function() tween(thumb, 0.2, { BackgroundColor3 = C('TextMuted') }) end)
        thumbHit.MouseButton1Down:Connect(function()
            local m0, cur0, k = mouse().Y, st.cur, curScale()
            Drag = {
                move = function(mp)
                    local _, _, trackH, thH = geometry()
                    local per = st.maxY() / max(1, trackH - thH)
                    st.target = clamp(cur0 + (mp.Y - m0) / k * per, 0, st.maxY())
                    Scrollers[st] = true
                end,
            }
        end)
        return col, st
    end

    -- borders for a box: left/right/bottom lines plus a top line that leaves a
    -- gap for the title (the groupbox look from the reference)
    local function boxFrame(col, order, titled)
        local box = New('Frame', { Size = UDim2new(1, 0, 0, 40), LayoutOrder = order, BackgroundTransparency = 0.3, Parent = col }, { BackgroundColor3 = 'Groupbox' })
        New('Frame', { Size = UDim2new(0, 1, 1, 0), Parent = box }, { BackgroundColor3 = 'Border' })
        New('Frame', { Position = UDim2new(1, -1, 0, 0), Size = UDim2new(0, 1, 1, 0), Parent = box }, { BackgroundColor3 = 'Border' })
        New('Frame', { Position = UDim2new(0, 0, 1, -1), Size = UDim2new(1, 0, 0, 1), Parent = box }, { BackgroundColor3 = 'Border' })
        local segs = {}
        if titled then
            segs.left = New('Frame', { Size = fromOffset(6, 1), Parent = box }, { BackgroundColor3 = 'Border' })
            segs.right = New('Frame', { Size = UDim2new(1, 0, 0, 1), Parent = box }, { BackgroundColor3 = 'Border' })
        else
            New('Frame', { Size = UDim2new(1, 0, 0, 1), Parent = box }, { BackgroundColor3 = 'Border' })
        end
        return box, segs
    end

    function Window:SetWindowTitle(NewTitle)
        setText(Title, NewTitle)
    end

    function Window:AddTab(Name)
        local Tab = { Groupboxes = {}, Tabboxes = {}, Name = Name, Order = #TabList + 1, _groups = {}, _boxOrder = 0 }

        local btn = New('TextButton', { BackgroundTransparency = 1, Size = fromOffset(60, TABS_H), Bold = true, TextSize = 13, Parent = TabBar })
        setText(btn, Name)
        btn.TextColor3 = C('TextDim')
        Tab.Button = btn

        local page = New('Frame', { BackgroundTransparency = 1, Size = fromScale(1, 1), Visible = false, Parent = PageHolder })
        Tab.Page = page
        Tab.Left, Tab.LeftScroll = column(page, 1)
        Tab.Right, Tab.RightScroll = column(page, 2)

        btn.MouseButton1Down:Connect(function() selectTab(Tab) end)
        btn.MouseEnter:Connect(function() Tab._hover = true; paintTab(Tab) end)
        btn.MouseLeave:Connect(function() Tab._hover = false; paintTab(Tab) end)
        btn:GetPropertyChangedSignal('TextBounds'):Connect(function() relayoutTabs(true) end)

        function Tab:ShowTab() selectTab(Tab) end
        function Tab:HideTab()
            if ActiveTab == Tab then
                page.Visible = false
                ActiveTab = nil
                paintTab(Tab)
            end
        end
        function Tab:SetLayoutOrder(Position)
            Tab.Order = Position
            relayoutTabs(true)
        end

        function Tab:AddGroupbox(Info)
            local col = (Info.Side == 1) and Tab.Left or Tab.Right
            Tab._boxOrder = Tab._boxOrder + 1
            local box, segs = boxFrame(col, Tab._boxOrder, true)
            local G = setmetatable({ Name = Info.Name, _tab = Tab, _order = 0, _clip = col, _box = box }, GroupMeta)
            G._group = G
            G._titleLower = lower(tostring(Info.Name or ''))

            local title = New('TextLabel', {
                Position = fromOffset(9, -7), Size = fromOffset(0, 14), AutomaticSize = Enum.AutomaticSize.X,
                TextSize = 13, Bold = true, Parent = box,
            }, { TextColor3 = 'Text' })
            setText(title, Info.Name)
            local function fixTitle()
                local w = title.AbsoluteSize.X / curScale()
                if tostring(Info.Name or '') == '' then w = -10 end
                local x = 9 + w + 5
                segs.right.Position = fromOffset(floor(x + 0.5), 0)
                segs.right.Size = UDim2new(1, -floor(x + 0.5), 0, 1)
            end
            title:GetPropertyChangedSignal('AbsoluteSize'):Connect(fixTitle)
            fixTitle()

            local content = New('Frame', { BackgroundTransparency = 1, Position = fromOffset(8, 14), Size = UDim2new(1, -16, 0, 0), Parent = box })
            local layout = New('UIListLayout', { SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })
            local function fit()
                local h = layout.AbsoluteContentSize.Y / curScale()
                content.Size = UDim2new(1, -16, 0, h)
                box.Size = UDim2new(1, 0, 0, floor(h + 14 + 9 + 0.5))
            end
            layout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(fit)
            fit()

            G.Container = content
            Tab.Groupboxes[Info.Name] = G
            table.insert(Tab._groups, G)
            return G
        end

        function Tab:AddLeftGroupbox(GName) return Tab:AddGroupbox({ Side = 1, Name = GName }) end
        function Tab:AddRightGroupbox(GName) return Tab:AddGroupbox({ Side = 2, Name = GName }) end

        function Tab:AddTabbox(Info)
            local col = (Info.Side == 1) and Tab.Left or Tab.Right
            Tab._boxOrder = Tab._boxOrder + 1
            local box = boxFrame(col, Tab._boxOrder, false)
            local Tabbox = { Tabs = {} }
            local bar = New('Frame', { BackgroundTransparency = 1, Position = fromOffset(1, 1), Size = UDim2new(1, -2, 0, 22), Parent = box })
            New('Frame', { Position = UDim2new(0, 0, 1, -1), Size = UDim2new(1, 0, 0, 1), Parent = bar }, { BackgroundColor3 = 'Border' })
            local line = New('Frame', { Position = UDim2new(0, 0, 1, -1), Size = UDim2new(0, 0, 0, 1), ZIndex = 2, Parent = bar }, { BackgroundColor3 = 'Accent' })
            local subs, active = {}, nil

            local function resize()
                if not active then return end
                local h = active._layout.AbsoluteContentSize.Y / curScale()
                active.Container.Size = UDim2new(1, -16, 0, h)
                box.Size = UDim2new(1, 0, 0, floor(22 + 8 + h + 9 + 0.5))
            end
            local function paintSubs(instant)
                local n = #subs
                for i, s in ipairs(subs) do
                    s.btn.Position = UDim2new((i - 1) / n, 0, 0, 0)
                    s.btn.Size = UDim2new(1 / n, 0, 1, 0)
                    tween(s.btn, instant and 0 or 0.15, { TextColor3 = (s == active) and C('Text') or C('TextDim') })
                end
                for i, s in ipairs(subs) do
                    if s == active then
                        local props = { Position = UDim2new((i - 1) / n, 8, 1, -1), Size = UDim2new(1 / n, -16, 0, 1) }
                        if instant then line.Position, line.Size = props.Position, props.Size else tween(line, 0.3, props) end
                    end
                end
            end

            function Tabbox:AddTab(SubName)
                local T = setmetatable({ Name = SubName, _tab = Tab, _order = 0, _clip = col, _box = box }, GroupMeta)
                T._group = T
                T._titleLower = lower(tostring(SubName or ''))
                local sbtn = New('TextButton', { BackgroundTransparency = 1, Bold = true, TextSize = 12, Parent = bar })
                setText(sbtn, SubName)
                local content = New('Frame', { BackgroundTransparency = 1, Position = fromOffset(8, 30), Size = UDim2new(1, -16, 0, 0), Visible = false, Parent = box })
                local layout = New('UIListLayout', { SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })
                T.Container, T._layout, T.btn = content, layout, sbtn
                layout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
                    if active == T then resize() end
                end)
                function T:Show()
                    if active then active.Container.Visible = false end
                    active = T
                    content.Visible = true
                    paintSubs()
                    resize()
                end
                function T:Hide() content.Visible = false end
                function T:Resize() resize() end
                sbtn.MouseButton1Down:Connect(function() T:Show() end)
                table.insert(subs, T)
                paintSubs(true)
                if #subs == 1 then T:Show() end
                Tabbox.Tabs[SubName] = T
                table.insert(Tab._groups, T)
                return T
            end

            table.insert(Restylers, function() paintSubs(true) end)
            Tab.Tabboxes[Info.Name or ''] = Tabbox
            return Tabbox
        end

        function Tab:AddLeftTabbox(TName) return Tab:AddTabbox({ Name = TName, Side = 1 }) end
        function Tab:AddRightTabbox(TName) return Tab:AddTabbox({ Name = TName, Side = 2 }) end

        table.insert(TabList, Tab)
        Window.Tabs[Name] = Tab
        relayoutTabs(true)
        if #TabList == 1 then selectTab(Tab, true) end
        paintTab(Tab, true)
        return Tab
    end

    -- ---------------------------------------------------------------- search
    local function applySearch(raw)
        local q = lower((tostring(raw or ''):gsub('^%s+', ''):gsub('%s+$', '')))
        local searching = q ~= ''
        closePopup(true)
        local tabHits, boxShow = {}, {}
        for _, e in ipairs(Searchables) do
            if e.row.Parent then
                local g = e.group
                local hit = (not searching) or (e.text:find(q, 1, true) ~= nil)
                    or (g ~= nil and g._titleLower ~= nil and g._titleLower:find(q, 1, true) ~= nil)
                e.row.Visible = hit
                if hit and searching then
                    if g and g._box then boxShow[g._box] = true end
                    if e.tab then tabHits[e.tab] = true end
                end
            end
        end
        for _, t in ipairs(TabList) do
            t._miss = searching and not tabHits[t]
            for _, g in ipairs(t._groups) do
                local b = g._box
                if b then
                    local titleHit = searching and g._titleLower and g._titleLower:find(q, 1, true) ~= nil
                    b.Visible = (not searching) or boxShow[b] == true or titleHit == true
                    if titleHit then tabHits[t] = true; t._miss = false end
                end
            end
            paintTab(t)
        end
        if searching and ActiveTab and not tabHits[ActiveTab] then
            for _, t in ipairs(TabList) do
                if tabHits[t] then selectTab(t) break end
            end
        end
    end
    SearchBox:GetPropertyChangedSignal('Text'):Connect(function() applySearch(SearchBox.Text) end)
    SearchBox.Focused:Connect(function() tween(SearchStroke, 0.15, { Color = C('AccentDim') }) end)
    SearchBox.FocusLost:Connect(function() tween(SearchStroke, 0.2, { Color = C('Border') }) end)

    -- ---------------------------------------------------------------- drag + resize
    DragArea.MouseButton1Down:Connect(function()
        local m0, p0 = mouse(), WinTarget
        Drag = {
            move = function(m)
                local sc2 = screen()
                local half = WinSize * curScale() / 2
                local t = p0 + (m - m0)
                t = V2(clamp(t.X, -half.X + 80, sc2.X + half.X - 80), clamp(t.Y, half.Y - 4, sc2.Y - 40 + half.Y))
                WinTarget = t
            end,
        }
    end)

    Grip.MouseButton1Down:Connect(function()
        local m0, s0, c0, k = mouse(), WinSize, WinTarget, curScale()
        Drag = {
            move = function(m)
                local d = (m - m0) / k
                local sc2 = screen()
                local nw = clamp(s0.X + d.X, MIN_W, max(MIN_W, sc2.X / k - 10))
                local nh = clamp(s0.Y + d.Y, MIN_H, max(MIN_H, sc2.Y / k - 10))
                WinSize = V2(nw, nh)
                Outer.Size = fromOffset(nw, nh)
                local c = c0 + V2(nw - s0.X, nh - s0.Y) * k / 2
                WinTarget, WinPos = c, c
                applyPos()
                relayoutTabs(true)
            end,
            stop = function()
                Prefs.width, Prefs.height = floor(WinSize.X), floor(WinSize.Y)
                savePrefs()
            end,
        }
    end)

    -- ---------------------------------------------------------------- open / close
    local MoonDrift = 0
    local function placeMoon()
        MoonBox.Position = UDim2new(0.5, 0, 0.5, floor(MoonDrift + 0.5))
    end

    local function setWinAlpha(a)
        WinAlpha = a
        fadeTree(Outer, a, WinDirty)
    end

    function Window._setOpen(show)
        if show then
            Outer.Visible = true
            cursorOn()
            if WinAlpha <= 0.01 then
                AnimScale = 0.955
                applyScale()
                MoonDrift = 16
                placeMoon()
            end
            animate('win', fadeTime + 0.06, WinAlpha, 1, setWinAlpha, function()
                if not PageAnimating then restoreDirty(WinDirty) end
            end, easeOutCubic)
            animate('winScale', 0.42, AnimScale, 1, function(v) AnimScale = v; applyScale() end, nil, easeOutQuint)
            animate('moon', 1.1, MoonDrift, 0, function(v) MoonDrift = v; placeMoon() end, nil, easeOutQuint)
        else
            cursorOff()
            animate('win', max(0.1, fadeTime * 0.8), WinAlpha, 0, setWinAlpha, function()
                Outer.Visible = false
            end, easeOutCubic)
            animate('winScale', 0.2, AnimScale, 0.975, function(v) AnimScale = v; applyScale() end, nil, easeOutCubic)
        end
    end

    function Window._step(dt)
        if (WinTarget - WinPos).Magnitude > 0.3 then
            WinPos = WinPos:Lerp(WinTarget, 1 - exp(-dt * 38))
            applyPos()
        elseif WinPos ~= WinTarget then
            WinPos = WinTarget
            applyPos()
        end
        if Library.Toggled and Prefs.stars and Moon.Parent then
            local t = clock()
            for _, s in ipairs(Stars) do
                local kk = 0.5 + 0.5 * math.sin(t * s.speed + s.phase)
                s.f.BackgroundColor3 = Theme.Panel:Lerp(Theme.Star, 0.25 + 0.75 * kk)
            end
        end
    end

    function Window._applyPrefs(key)
        if key == 'moon' then MoonBox.Visible = Prefs.moon end
        if key == 'stars' then for _, s in ipairs(Stars) do s.f.Visible = Prefs.stars end end
        if key == 'scale' then applyScale() end
        if key == 'font' or key == 'lowercase' then relayoutTabs(true) end
    end

    table.insert(Restylers, function()
        for _, t in ipairs(TabList) do paintTab(t, true) end
        moveUnderline(true)
    end)

    Window._relayoutTabs = relayoutTabs
    Window._applySearch = applySearch

    if Config.AutoShow then
        task.defer(function()
            if not Library.Unloaded and not Library.Toggled then Library:Toggle(true) end
        end)
    end

    return Window
end

-- Opens/closes the menu. Works as Library:Toggle(), Library.Toggle() (Linoria
-- passes it to task.spawn), or Library:Toggle(true/false) to force a state.
function Library.Toggle(a, b)
    local force
    if a == Library then force = b else force = a end
    if type(force) ~= 'boolean' then force = nil end
    local Window = Library.Window
    if not Window or Library.Unloaded then return end
    local show
    if force == nil then show = not Library.Toggled else show = force end
    if show == Library.Toggled then return end
    Library.Toggled = show
    ModalButton.Modal = show
    closePopup(true)
    hideTip()
    if PickingNow then PickingNow:_cancelPick() end
    Window._setOpen(show)
end

-- ============================================================================
-- UI preferences (used by the ThemeManager add-on)
-- ============================================================================
function Library:SetPref(key, value)
    if key == 'accent' then
        if typeof(value) ~= 'Color3' then return end
        Theme.Accent = value
        Prefs.accent = value:ToHex()
        pushLegacy()
        restyle()
    elseif key == 'font' then
        if not FONT_ENUMS[value] then return end
        Prefs.font = value
        loadFonts(value)
        for inst, kind in pairs(FontOf) do inst.FontFace = Fonts[kind] or Fonts.body end
        restyle()
    elseif key == 'lowercase' then
        Prefs.lowercase = not not value
        for inst, raw in pairs(TextRaw) do inst.Text = shown(raw) end
        restyle()
    elseif key == 'scale' then
        Prefs.scale = clamp(tonumber(value) or 100, 60, 150)
    elseif key == 'keybinds' then
        Prefs.keybinds = not not value
        KB.frame.Visible = Prefs.keybinds
        KB.dirty = true
    elseif key == 'preset' then
        Prefs.preset = value
    elseif key == 'moon' or key == 'stars' or key == 'animations' or key == 'cursor' then
        Prefs[key] = not not value
    else
        return
    end
    if Library.Window and Library.Window._applyPrefs then Library.Window._applyPrefs(key) end
    savePrefs()
end

function Library:ResetPrefs()
    Library:SetPref('accent', DEFAULT_ACCENT)
    Prefs.width, Prefs.height = nil, nil
    savePrefs()
end

-- ============================================================================
-- Unload
-- ============================================================================
local UnloadCallbacks = {}
local OnUnloadMethod

function Library:OnUnload(Callback)
    table.insert(UnloadCallbacks, Callback)
end
OnUnloadMethod = Library.OnUnload

function Library:Unload()
    if Library.Unloaded then return end
    Library.Unloaded = true
    for Idx = #Library.Signals, 1, -1 do
        local Connection = table.remove(Library.Signals, Idx)
        pcall(function() Connection:Disconnect() end)
    end
    for _, cb in ipairs(UnloadCallbacks) do safeCall(cb) end
    if rawget(Library, 'OnUnload') ~= OnUnloadMethod and type(rawget(Library, 'OnUnload')) == 'function' then
        safeCall(rawget(Library, 'OnUnload'))
    end
    closePopup(true)
    pcall(function() ModalButton.Modal = false end)
    cursorOff()
    local win = Library.Window
    if win and Library.Toggled and Prefs.animations then
        task.spawn(function()
            local t0 = clock()
            local dirty = {}
            while clock() - t0 < 0.15 do
                local a = 1 - (clock() - t0) / 0.15
                pcall(fadeTree, win.Holder, a * WinAlpha, dirty)
                RunService.RenderStepped:Wait()
            end
            ScreenGui:Destroy()
        end)
    else
        ScreenGui:Destroy()
    end
end

-- ============================================================================
-- Global input + per-frame work
-- ============================================================================
local UIT = Enum.UserInputType

local function onInputBegan(Input, Processed)
    if Library.Unloaded then return end
    local ut = Input.UserInputType

    if PickingNow then
        local kp = PickingNow
        if clock() >= (kp._armAt or 0) then
            local Key
            if ut == UIT.Keyboard then
                Key = Input.KeyCode.Name
            elseif ut == UIT.MouseButton1 then
                Key = 'MB1'
            elseif ut == UIT.MouseButton2 then
                Key = 'MB2'
            end
            if Key then kp:_finishPick(Key, Input) end
        end
        return
    end

    local typing = false
    pcall(function() typing = UserInputService:GetFocusedTextBox() ~= nil end)

    if not typing then
        local tk = Library.ToggleKeybind
        if type(tk) == 'table' and tk.Type == 'KeyPicker' then
            if ut == UIT.Keyboard and Input.KeyCode.Name == tk.Value then
                task.spawn(Library.Toggle, Library)
            end
        elseif Input.KeyCode == Enum.KeyCode.RightControl or (Input.KeyCode == Enum.KeyCode.RightShift and not Processed) then
            task.spawn(Library.Toggle, Library)
        end

        for i = 1, #Pickers do
            local kp = Pickers[i]
            if kp and kp.Mode == 'Toggle' then
                local Key = kp.Value
                local hit = (Key == 'MB1' and ut == UIT.MouseButton1)
                    or (Key == 'MB2' and ut == UIT.MouseButton2)
                    or (ut == UIT.Keyboard and Input.KeyCode.Name == Key)
                if hit then
                    kp.Toggled = not kp.Toggled
                    kp:DoClick()
                end
            end
        end
    end

    for i = 1, #Pickers do
        local kp = Pickers[i]
        if kp then pcall(kp.Update, kp) end
    end

    if Current and (ut == UIT.MouseButton1 or ut == UIT.MouseButton2 or ut == UIT.Touch) then
        if not isOver(Current.root) and not isOver(Current.anchor) then closePopup() end
    end
end

local function onInputEnded(Input)
    if Library.Unloaded then return end
    local ut = Input.UserInputType
    if ut == UIT.MouseButton1 or ut == UIT.Touch then
        local d = Drag
        Drag = nil
        if d and d.stop then safeCall(d.stop) end
    end
    if not PickingNow then
        for i = 1, #Pickers do
            local kp = Pickers[i]
            if kp then pcall(kp.Update, kp) end
        end
    end
end

local function onInputChanged(Input)
    if Library.Unloaded then return end
    if Drag and (Input.UserInputType == UIT.MouseMovement or Input.UserInputType == UIT.Touch) then
        local ok, err = pcall(Drag.move, mouse())
        if not ok then
            Drag = nil
            warn('[Crescent] drag error: ' .. tostring(err))
        end
    end
end

local DOTS = { '.', '..', '...' }
local function onRender(dt)
    if Library.Unloaded then return end
    stepAnims()
    stepScrollers(dt)
    stepNotes(dt)
    stepTip()
    stepCursor()
    local win = Library.Window
    if win and win._step then win._step(dt) end
    if Current and not placePopup(Current) then closePopup(true) end
    -- a key box waiting for a key shows moving dots
    local kp = PickingNow
    if kp and kp._box then kp._box.Text = DOTS[floor(clock() * 3) % 3 + 1] end
    if KB.dirty and KB.frame.Visible then pcall(refreshKeybinds) end
end

local function onPlayerChange(leaving)
    local list = playerNames(leaving)
    for _, Value in next, Options do
        if type(Value) == 'table' and Value.Type == 'Dropdown' and Value.SpecialType == 'Player' then
            pcall(Value.SetValues, Value, list)
        end
    end
end

Library:GiveSignal(UserInputService.InputBegan:Connect(onInputBegan))
Library:GiveSignal(UserInputService.InputEnded:Connect(onInputEnded))
Library:GiveSignal(UserInputService.InputChanged:Connect(onInputChanged))
Library:GiveSignal(RunService.RenderStepped:Connect(onRender))
Library:GiveSignal(ScreenGui.DescendantRemoving:Connect(forget))
Library:GiveSignal(Players.PlayerAdded:Connect(function() onPlayerChange(nil) end))
Library:GiveSignal(Players.PlayerRemoving:Connect(function(p) onPlayerChange(p) end))
Library:GiveSignal(ScreenGui:GetPropertyChangedSignal('AbsoluteSize'):Connect(refreshInset))

-- read-only view for debugging and tests
Library._internals = { Rest = Rest, Anims = Anims, Searchables = Searchables, Pickers = Pickers, WinDirty = WinDirty }

genv.Library = Library
return Library
