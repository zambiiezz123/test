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
-- 2. Theme
-- ===========================================================================
local T = {
    bg        = Color3.fromRGB(22, 22, 30),
    panel     = Color3.fromRGB(28, 28, 40),
    panelAlt  = Color3.fromRGB(33, 34, 48),
    row       = Color3.fromRGB(31, 32, 46),
    rowHover  = Color3.fromRGB(40, 42, 60),
    rowSelect = Color3.fromRGB(48, 52, 78),
    stroke    = Color3.fromRGB(48, 50, 70),
    text      = Color3.fromRGB(192, 202, 245),
    textDim   = Color3.fromRGB(120, 126, 160),
    accent    = Color3.fromRGB(122, 162, 247),   -- blue  (FireServer)
    accent2   = Color3.fromRGB(158, 206, 106),   -- green (InvokeServer)
    danger    = Color3.fromRGB(247, 118, 142),
}

-- Tiny helpers to keep instance creation terse -----------------------------
local function make(class, props, children)
    local o = Instance.new(class)
    for k, v in pairs(props or {}) do o[k] = v end
    for _, c in ipairs(children or {}) do c.Parent = o end
    return o
end
local function corner(r) return make('UICorner', { CornerRadius = UDim.new(0, r or 6) }) end
local function stroke(c, th) return make('UIStroke', { Color = c or T.stroke, Thickness = th or 1 }) end
local function pad(px) return make('UIPadding', {
    PaddingLeft = UDim.new(0, px), PaddingRight = UDim.new(0, px),
    PaddingTop = UDim.new(0, px), PaddingBottom = UDim.new(0, px),
}) end

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
local gui = make('ScreenGui', {
    Name = 'RemoteSpy_' .. tostring(math.random(1000, 9999)),
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 9999,
})
pcall(function() gui.Parent = hiddenUI or LocalPlayer:WaitForChild('PlayerGui') end)
pcall(protectGui, gui)
if not gui.Parent then gui.Parent = LocalPlayer:WaitForChild('PlayerGui') end

local root = make('Frame', {
    Name = 'Root',
    Parent = gui,
    Size = UDim2.fromOffset(720, 460),
    Position = UDim2.fromScale(0.5, 0.5),
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundColor3 = T.bg,
    BorderSizePixel = 0,
}, { corner(10), stroke(T.stroke, 1) })

-- Drop shadow-ish outline glow
make('UIStroke', { Parent = root, Color = T.accent, Thickness = 1, Transparency = 0.75 })

-- --- Title bar ------------------------------------------------------------
local titleBar = make('Frame', {
    Name = 'TitleBar', Parent = root,
    Size = UDim2.new(1, 0, 0, 40),
    BackgroundColor3 = T.panel, BorderSizePixel = 0,
}, { corner(10) })
make('Frame', { Parent = titleBar, Size = UDim2.new(1, 0, 0, 12),
    Position = UDim2.new(0, 0, 1, -12), BackgroundColor3 = T.panel, BorderSizePixel = 0 })

make('Frame', { Parent = titleBar, Name = 'AccentDot',
    Size = UDim2.fromOffset(10, 10), Position = UDim2.fromOffset(16, 15),
    BackgroundColor3 = T.accent, BorderSizePixel = 0 }, { corner(5) })

local titleLabel = make('TextLabel', {
    Parent = titleBar, BackgroundTransparency = 1,
    Position = UDim2.fromOffset(36, 0), Size = UDim2.new(1, -160, 1, 0),
    Font = Enum.Font.GothamBold, Text = 'Remote Spy', TextSize = 15,
    TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left,
})

local countLabel = make('TextLabel', {
    Parent = titleBar, BackgroundTransparency = 1,
    Position = UDim2.new(0, 120, 0, 0), Size = UDim2.new(1, -250, 1, 0),
    Font = Enum.Font.Gotham, Text = '0 calls', TextSize = 12,
    TextColor3 = T.textDim, TextXAlignment = Enum.TextXAlignment.Left,
})

local function titleButton(xOff, colorHover)
    local b = make('TextButton', {
        Parent = titleBar, AutoButtonColor = false, Text = '',
        Size = UDim2.fromOffset(28, 28), Position = UDim2.new(1, xOff, 0, 6),
        BackgroundColor3 = T.panelAlt,
    }, { corner(6) })
    b.MouseEnter:Connect(function() b.BackgroundColor3 = colorHover or T.rowHover end)
    b.MouseLeave:Connect(function() b.BackgroundColor3 = T.panelAlt end)
    return b
end

-- Icons drawn from Frames so they never depend on emoji font support.
local function iconBar(parent, w, h, offx, offy, rot)
    return make('Frame', {
        Parent = parent, AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, offx or 0, 0.5, offy or 0),
        Size = UDim2.fromOffset(w, h), Rotation = rot or 0,
        BackgroundColor3 = T.text, BorderSizePixel = 0,
    }, { corner(1) })
end

local settingsBtn = titleButton(-104)                      -- three-line menu
iconBar(settingsBtn, 14, 2, 0, -5)
iconBar(settingsBtn, 14, 2, 0, 0)
iconBar(settingsBtn, 14, 2, 0, 5)

local minBtn = titleButton(-70)                            -- single line
iconBar(minBtn, 12, 2, 0, 5)

local closeBtn = titleButton(-36, T.danger)                -- X
iconBar(closeBtn, 14, 2, 0, 0, 45)
iconBar(closeBtn, 14, 2, 0, 0, -45)

-- --- Body split -----------------------------------------------------------
local body = make('Frame', {
    Name = 'Body', Parent = root,
    Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40),
    BackgroundTransparency = 1,
}, { pad(10) })
make('UIListLayout', { Parent = body, FillDirection = Enum.FillDirection.Horizontal,
    Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder })

-- LEFT column: search + toolbar + feed --------------------------------------
local left = make('Frame', {
    Name = 'Left', Parent = body, LayoutOrder = 1,
    Size = UDim2.new(0.42, 0, 1, 0), BackgroundTransparency = 1,
})
make('UIListLayout', { Parent = left, Padding = UDim.new(0, 8),
    SortOrder = Enum.SortOrder.LayoutOrder })

local searchBox = make('TextBox', {
    Parent = left, LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 30),
    BackgroundColor3 = T.panel, BorderSizePixel = 0,
    Font = Enum.Font.Gotham, PlaceholderText = 'filter by name...',
    Text = '', TextSize = 13, TextColor3 = T.text,
    PlaceholderColor3 = T.textDim, ClearTextOnFocus = false,
    TextXAlignment = Enum.TextXAlignment.Left,
}, { corner(6), stroke(), pad(8) })

local toolbar = make('Frame', {
    Parent = left, LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 28),
    BackgroundTransparency = 1,
})
make('UIListLayout', { Parent = toolbar, FillDirection = Enum.FillDirection.Horizontal,
    Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder })

local function toolButton(text, order)
    local b = make('TextButton', {
        Parent = toolbar, LayoutOrder = order, AutoButtonColor = false,
        Size = UDim2.new(1/3, -4, 1, 0), BackgroundColor3 = T.panel,
        Font = Enum.Font.GothamMedium, Text = text, TextSize = 12, TextColor3 = T.text,
    }, { corner(6), stroke() })
    b.MouseEnter:Connect(function() b.BackgroundColor3 = T.rowHover end)
    b.MouseLeave:Connect(function() b.BackgroundColor3 = T.panel end)
    return b
end
local pauseBtn   = toolButton('Pause', 1)
local clearBtn   = toolButton('Clear', 2)
local copyAllBtn = toolButton('Copy All', 3) -- copy the deduped dump (also on disk)

local feed = make('ScrollingFrame', {
    Name = 'Feed', Parent = left, LayoutOrder = 3,
    Size = UDim2.new(1, 0, 1, -74), BackgroundColor3 = T.panel, BorderSizePixel = 0,
    ScrollBarThickness = 4, ScrollBarImageColor3 = T.accent,
    CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ScrollingDirection = Enum.ScrollingDirection.Y,
}, { corner(8), stroke(), pad(6) })
make('UIListLayout', { Parent = feed, Padding = UDim.new(0, 4),
    SortOrder = Enum.SortOrder.LayoutOrder })

-- RIGHT column: detail view -------------------------------------------------
local right = make('Frame', {
    Name = 'Right', Parent = body, LayoutOrder = 2,
    Size = UDim2.new(0.58, -10, 1, 0), BackgroundColor3 = T.panel, BorderSizePixel = 0,
}, { corner(8), stroke(), pad(12) })
make('UIListLayout', { Parent = right, Padding = UDim.new(0, 8),
    SortOrder = Enum.SortOrder.LayoutOrder })

local detailName = make('TextLabel', {
    Parent = right, LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 22),
    BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
    Text = 'Select a call', TextSize = 15, TextColor3 = T.text,
    TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
})
local detailPath = make('TextLabel', {
    Parent = right, LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 16),
    BackgroundTransparency = 1, Font = Enum.Font.Gotham,
    Text = '', TextSize = 12, TextColor3 = T.textDim,
    TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
})

local codeBox = make('ScrollingFrame', {
    Parent = right, LayoutOrder = 3, Size = UDim2.new(1, 0, 1, -84),
    BackgroundColor3 = T.bg, BorderSizePixel = 0,
    ScrollBarThickness = 4, ScrollBarImageColor3 = T.accent,
    CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, { corner(6), stroke(), pad(10) })
local codeLabel = make('TextLabel', {
    Parent = codeBox, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y, Font = Enum.Font.Code,
    Text = '-- captured call source will appear here', TextSize = 13,
    TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true,
})

local detailBtns = make('Frame', {
    Parent = right, LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 30),
    BackgroundTransparency = 1,
})
make('UIListLayout', { Parent = detailBtns, FillDirection = Enum.FillDirection.Horizontal,
    Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder })

local function detailButton(text, order, w, color)
    local b = make('TextButton', {
        Parent = detailBtns, LayoutOrder = order, AutoButtonColor = false,
        Size = UDim2.new(w, order == 1 and -0 or -4, 1, 0),
        BackgroundColor3 = color or T.panelAlt,
        Font = Enum.Font.GothamMedium, Text = text, TextSize = 12,
        TextColor3 = order == 1 and Color3.new(1, 1, 1) or T.text,
    }, { corner(6) })
    b.MouseEnter:Connect(function() b.BackgroundTransparency = 0.15 end)
    b.MouseLeave:Connect(function() b.BackgroundTransparency = 0 end)
    return b
end
local copyCodeBtn = detailButton('Copy Script', 1, 0.4, T.accent)
local copyPathBtn = detailButton('Copy Path', 2, 0.3)
local ignoreBtn   = detailButton('Ignore Remote', 3, 0.3)

-- ---- Settings overlay (top-right gear opens this) ------------------------
local settingsPanel = make('Frame', {
    Name = 'Settings', Parent = root, Visible = false,
    Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40),
    BackgroundColor3 = T.bg, BorderSizePixel = 0,
}, { corner(10) })

local sCard = make('Frame', {
    Parent = settingsPanel, AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(380, 200),
    BackgroundColor3 = T.panel, BorderSizePixel = 0,
}, { corner(12), stroke(), pad(18) })
make('UIListLayout', { Parent = sCard, Padding = UDim.new(0, 12),
    SortOrder = Enum.SortOrder.LayoutOrder })

make('TextLabel', { Parent = sCard, LayoutOrder = 1, BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 0, 22), Font = Enum.Font.GothamBold, Text = 'Settings',
    TextSize = 16, TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left })
make('TextLabel', { Parent = sCard, LayoutOrder = 2, BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 0, 16), Font = Enum.Font.Gotham, Text = 'Open / close key',
    TextSize = 13, TextColor3 = T.textDim, TextXAlignment = Enum.TextXAlignment.Left })

local keyRow = make('Frame', { Parent = sCard, LayoutOrder = 3,
    Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = T.bg, BorderSizePixel = 0,
}, { corner(8), stroke() })
local keyValueLabel = make('TextLabel', { Parent = keyRow, BackgroundTransparency = 1,
    Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -120, 1, 0),
    Font = Enum.Font.GothamMedium, Text = TOGGLE_KEY.Name, TextSize = 14,
    TextColor3 = T.accent, TextXAlignment = Enum.TextXAlignment.Left })
local rebindBtn = make('TextButton', { Parent = keyRow, AutoButtonColor = false,
    AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0),
    Size = UDim2.fromOffset(96, 26), BackgroundColor3 = T.accent,
    Font = Enum.Font.GothamMedium, Text = 'Rebind', TextSize = 13,
    TextColor3 = Color3.new(1, 1, 1) }, { corner(6) })

local doneBtn = make('TextButton', { Parent = sCard, LayoutOrder = 4,
    Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = T.panelAlt, AutoButtonColor = false,
    Font = Enum.Font.GothamMedium, Text = 'Done', TextSize = 13, TextColor3 = T.text,
}, { corner(8) })
doneBtn.MouseEnter:Connect(function() doneBtn.BackgroundColor3 = T.rowHover end)
doneBtn.MouseLeave:Connect(function() doneBtn.BackgroundColor3 = T.panelAlt end)

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
    btn.Text = okText
    task.delay(0.8, function() if btn and btn.Parent then btn.Text = prev end end)
end

local function renderDetail(entry)
    selected = entry
    if not entry then
        detailName.Text = 'Select a call'
        detailPath.Text = ''
        codeLabel.Text  = '-- captured call source will appear here'
        return
    end
    detailName.Text = string.format('%s  ·  %s', entry.name, entry.method)
    detailName.TextColor3 = entry.method == 'InvokeServer' and T.accent2 or T.accent
    local ok, full = pcall(function() return entry.remote:GetFullName() end)
    detailPath.Text = ok and full or '<remote destroyed>'
    codeLabel.Text  = buildSnippet(entry)
end

local function passesFilter(entry)
    if filter == '' then return true end
    return entry.name:lower():find(filter, 1, true) ~= nil
end

local function makeRow(entry)
    local isInvoke = entry.method == 'InvokeServer'
    local row = make('TextButton', {
        Parent = feed, AutoButtonColor = false, Text = '',
        Size = UDim2.new(1, 0, 0, 42), BackgroundColor3 = T.row, BorderSizePixel = 0,
        LayoutOrder = entry.id,
    }, { corner(6) })

    make('Frame', { Parent = row, Size = UDim2.fromOffset(3, 30),
        Position = UDim2.fromOffset(6, 6), BorderSizePixel = 0,
        BackgroundColor3 = isInvoke and T.accent2 or T.accent }, { corner(2) })

    make('TextLabel', { Parent = row, BackgroundTransparency = 1,
        Position = UDim2.fromOffset(16, 4), Size = UDim2.new(1, -60, 0, 18),
        Font = Enum.Font.GothamMedium, Text = entry.name, TextSize = 13,
        TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd })

    make('TextLabel', { Parent = row, BackgroundTransparency = 1,
        Position = UDim2.fromOffset(16, 22), Size = UDim2.new(1, -60, 0, 14),
        Font = Enum.Font.Gotham,
        Text = string.format('%s · %d arg%s', entry.method, entry.argc,
            entry.argc == 1 and '' or 's'),
        TextSize = 11, TextColor3 = T.textDim,
        TextXAlignment = Enum.TextXAlignment.Left })

    make('TextLabel', { Parent = row, BackgroundTransparency = 1,
        Position = UDim2.new(1, -50, 0, 0), Size = UDim2.fromOffset(44, 42),
        Font = Enum.Font.GothamBold, Text = '#' .. entry.id, TextSize = 11,
        TextColor3 = T.textDim, TextXAlignment = Enum.TextXAlignment.Right })

    local function refreshColor()
        row.BackgroundColor3 = (selected == entry) and T.rowSelect or T.row
    end
    row.MouseEnter:Connect(function() if selected ~= entry then row.BackgroundColor3 = T.rowHover end end)
    row.MouseLeave:Connect(refreshColor)
    row.MouseButton1Click:Connect(function()
        renderDetail(entry)
        for e, r in pairs(rowByEntry) do
            r.BackgroundColor3 = (e == entry) and T.rowSelect or T.row
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
    pauseBtn.Text = paused and 'Resume' or 'Pause'
    pauseBtn.TextColor3 = paused and T.accent2 or T.text
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
    root.Size = minimised and UDim2.fromOffset(720, 40) or UDim2.fromOffset(720, 460)
end)

-- Settings + open/close key rebind
local awaitingKey = false
settingsBtn.MouseButton1Click:Connect(function()
    settingsPanel.Visible = not settingsPanel.Visible
end)
doneBtn.MouseButton1Click:Connect(function()
    settingsPanel.Visible = false
    awaitingKey = false
    keyValueLabel.Text = TOGGLE_KEY.Name
    keyValueLabel.TextColor3 = T.accent
end)
rebindBtn.MouseButton1Click:Connect(function()
    awaitingKey = true
    keyValueLabel.Text = 'Press any key...'
    keyValueLabel.TextColor3 = T.accent2
end)

local function setVisible(v) root.Visible = v end
UIS.InputBegan:Connect(function(i, gpe)
    -- Capture the next key press when rebinding (ignore mouse buttons)
    if awaitingKey and i.UserInputType == Enum.UserInputType.Keyboard then
        TOGGLE_KEY = i.KeyCode
        saveToggleKey()                    -- persist across executions
        keyValueLabel.Text = TOGGLE_KEY.Name
        keyValueLabel.TextColor3 = T.accent
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
titleLabel.Text = 'Remote Spy'
warn(('[RemoteSpy] Loaded. Toggle with %s. Fire some remotes in-game to populate the feed.')
    :format(TOGGLE_KEY.Name))
