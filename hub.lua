--[[
    Game test menu — built on LinoriaLib
    Run this single script while loaded into your game.

    Movement : WalkSpeed, Fly, Noclip, Infinite Jump, Jump Power
    World    : No Fall Damage, No Fog
    Each movement feature has a checkbox + (most) a keybind synced to it.
]]

-- 0. Unload any previous instance FIRST ---------------------------------------
-- Re-injecting without this leaves the old script's loops running against a
-- stale Toggles/Options table -> "attempt to index nil with 'Value'" spam.
if getgenv().GameTestMenu_Unload then
    pcall(getgenv().GameTestMenu_Unload)
    task.wait(0.1)
end 

-- 0.5 Auto-execute safety: wait for the LocalPlayer before loading the UI lib --
-- Library.lua calls LocalPlayer:GetMouse() as it loads, so injecting BEFORE the
-- player exists throws "attempt to index nil with 'GetMouse'" (line 21 below).
-- Waiting for LocalPlayer + PlayerGui makes the script safe to auto-execute on
-- join / after a server hop (it just holds until the join finishes).
repeat task.wait() until game:GetService('Players').LocalPlayer
    and game:GetService('Players').LocalPlayer:FindFirstChildOfClass('PlayerGui')

-- 1. Load the library + addons -------------------------------------------------
local repo = 'https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/'

local Library      = loadstring(game:HttpGet(repo .. 'Library.lua'))()
local ThemeManager = loadstring(game:HttpGet(repo .. 'addons/ThemeManager.lua'))()
local SaveManager  = loadstring(game:HttpGet(repo .. 'addons/SaveManager.lua'))()

-- Expose an unload hook so the NEXT injection can clean us up.
getgenv().GameTestMenu_Unload = function() Library:Unload() end

-- ============================================================================
-- 1.5 GAME HUB: detect the current experience, route to that game's module
-- ============================================================================
-- This one script is a HUB - it only builds the features for the game you are
-- actually in. Matching is by the current place's PlaceId OR its GameId (the
-- UNIVERSE / "game" id). Putting a UNIVERSE id in a game's list therefore matches
-- EVERY experience/place under that game automatically (that is what Forgotten
-- Stories uses). To add a game: add a row here + a branch below.
--   * roguecopy (Rogue Lineage) = the big module below (runs ONLY in that game).
--   * forgottenstories          = its own module (placeholder for now).
--   * anything else             = a small "unsupported" page with copy-id buttons.
local HUB_CURRENT = 'unknown'
do
    local HUB_GAMES = {
        { key = 'roguecopy',        ids = { 133317834779462 } },
        -- Forgotten Stories: GameId 9246027831 is the UNIVERSE (matches EVERY
        -- experience under it via game.GameId); 90667623337283 is the main place.
        { key = 'forgottenstories', ids = { 9246027831, 90667623337283, 91220286841086 } },
        -- Slayers: place ids from ReplicatedStorage.CAM.Worlds (Ouwland main world,
        -- Main Menu, Minigames). Add its GameId (universe) here once known.
        { key = 'slayers',          ids = { 136406881576517, 16205713724, 75556147183481 } },
    }
    local pid, uid = game.PlaceId, game.GameId
    for _, g in ipairs(HUB_GAMES) do
        for _, id in ipairs(g.ids) do
            if pid == id or uid == id then HUB_CURRENT = g.key; break end
        end
        if HUB_CURRENT ~= 'unknown' then break end
    end
    print(('[Hub] PlaceId=%d GameId(universe)=%d -> module: %s'):format(pid, uid, HUB_CURRENT))
end

-- Non-roguecopy games build their OWN self-contained menu here and RETURN, so
-- none of the Rogue Lineage code further down runs for them. As Forgotten Stories
-- scripts get written they go in its branch.
if HUB_CURRENT ~= 'roguecopy' then
    local RunService = game:GetService('RunService')
    local RepStorage = game:GetService('ReplicatedStorage')
    local UIS        = game:GetService('UserInputService')
    local hubConns   = {} -- tracked connections, disconnected on unload
    local function htrack(c) hubConns[#hubConns + 1] = c; return c end

    local Window = Library:CreateWindow({
        Title = (HUB_CURRENT == 'forgottenstories') and 'Game Hub - Forgotten Stories'
            or (HUB_CURRENT == 'slayers') and 'Game Hub - Slayers'
            or 'Game Hub - Universal',
        Center = true, AutoShow = true, TabPadding = 8, MenuFadeTime = 0.2,
    })

    if HUB_CURRENT == 'forgottenstories' then
        local Players     = game:GetService('Players')
        local LocalPlayer = Players.LocalPlayer
        local VIM         = game:GetService('VirtualInputManager')
        local Tab = Window:AddTab('Combat')
        local fireQte, defend, refreshMoves, stackFire, stackRelease -- forward-declared for the buttons

        -- ===== UI: Auto QTE (offensive attack minigame - QteResult) =======
        local QteBox = Tab:AddLeftGroupbox('Auto QTE (attack)')
        QteBox:AddLabel('Auto-aces YOUR attack QTE. From the decompiled source:\nthe QTE minigame runs on YOUR client and reports its own\ngrade via QteResult - it even fires "Miss" by itself when\nyou ignore it. Rewrite mode hooks that outgoing report and\nflips the grade, so the server sees ONE authentic,\nperfectly-timed report. Grades: Miss / Hit / Critical.', true)
        local QteStatus = QteBox:AddLabel('Idle')
        QteBox:AddToggle('AutoQTE', {
            Text = 'Auto QTE', Default = false,
            Tooltip = 'Auto-pass every attack QTE with the grade below.',
        }):AddKeyPicker('AutoQTEKey', { Default = 'None', SyncToggleState = true, Mode = 'Toggle', Text = 'Auto QTE' })
        QteBox:AddDropdown('QTEMethod', {
            Values = { 'Rewrite grade (recommended)', 'Instant fire on attack' },
            Default = 1, Multi = false, Text = 'Method',
            Tooltip = 'Rewrite = intercept the game\'s OWN QteResult send and upgrade the grade in-flight (one report, authentic timing, works no matter what opened the QTE). Instant fire = the old behavior: fire our own QteResult when your attack starts - the game still sends its own grade later, so the server gets TWO reports; fallback only.',
        })
        QteBox:AddInput('QTEResult', { Text = 'Grade', Default = 'Critical', Finished = true, Placeholder = 'Critical',
            Tooltip = 'Confirmed grades: Miss / Hit / Critical (Critical = best). Rewrite only touches those three - special QTEs with their own words (Soulkiller\'s Alive/Death) pass through untouched so they can\'t be corrupted.' })
        QteBox:AddSlider('QTEFireDelay', { Text = 'Fire delay (Instant mode)', Default = 0, Min = 0, Max = 0.5, Rounding = 2, Suffix = ' s',
            Tooltip = 'Instant-fire mode only: delay between your attack starting and firing the grade.' })
        QteBox:AddToggle('QTEContinuous', { Text = 'Also continuous (Instant mode)', Default = false,
            Tooltip = 'Instant-fire mode only: also fire the grade on the interval below. Spammy (the server sees stray results). Rewrite mode never needs this.' })
        QteBox:AddSlider('QTEInterval', { Text = 'Continuous interval', Default = 0.25, Min = 0.05, Max = 1, Rounding = 2, Suffix = ' s' })
        QteBox:AddButton({ Text = 'Fire QteResult once (test)', Func = function()
            if fireQte and fireQte() then Library:Notify('Fired QteResult', 2) else Library:Notify('QteResult remote not found', 5) end
        end })

        -- ===== UI: Auto Parry / Dodge (defensive - ActionClient/HitResult) =
        local ParryBox = Tab:AddRightGroupbox('Auto Parry / Dodge')
        ParryBox:AddLabel('Auto-defends attacks on YOU. From the decompiled combat\nmodule: your OWN client judges the 0.18s parry / 0.30s\ndodge windows and always reports the verdict - on a miss\nit fires HitResult "Hit" at the attack animation\'s Hit\nkeyframe. Rewrite mode flips that exact packet into\n"Parry"/"Dodge": one report, authentic marker timing,\nauthentic args. No extra remotes, no timing race.', true)
        local ParryStatus = ParryBox:AddLabel('Idle')
        ParryBox:AddToggle('FSAutoParry', {
            Text = 'Auto parry/dodge', Default = false,
            Tooltip = 'Turn every failed defense into a success (Rewrite), or fire/simulate the defense yourself (fallback methods).',
        }):AddKeyPicker('FSAutoParryKey', { Default = 'None', SyncToggleState = true, Mode = 'Toggle', Text = 'Auto parry/dodge' })
        ParryBox:AddDropdown('FSParryMethod', {
            Values = { 'Rewrite fail -> success (recommended)', 'Fire HitResult directly', 'Simulate F / WASD keys' },
            Default = 1, Multi = false, Text = 'Method',
            Tooltip = 'Rewrite = intercept the game\'s own failure report ("Hit"/"Blocked") as it leaves and change it to Parry/Dodge - the server sees a single perfectly-timed report; USE THIS. Fire directly = send our own HitResult at attack start (the game still sends its own "Hit" later = two conflicting reports - this is why the old version did nothing; kept as fallback). Simulate keys = press F/WASD via VirtualInputManager (real 0.18s/0.30s windows apply).',
        })
        ParryBox:AddDropdown('FSDefault', {
            Values = { 'Parry', 'Dodge', 'Both (parry + dodge)' },
            Default = 1, Multi = false, Text = 'Default action',
            Tooltip = 'Action for moves NOT in the dodge list. Rewrite mode flips one packet so "Both" acts as Parry there; "Both" only truly fires both in Fire-directly mode.',
        })
        ParryBox:AddInput('FSDodgeMoves', { Text = 'Dodge these moves', Default = 'BarkStomp, TectonicCall, Bandit: Assassinate, The Twisted: Death Grip, Dust: Spike, Harlod: Severe, Woodpeck, Carnage: Mutilate, ???: Strikeback, ???: Light Divide, Abigail: Jagged Jaw, Dust: Rib Breaker, Dust: Stone Punches', Finished = true,
            Placeholder = 'comma-separated move names',
            Tooltip = 'Moves whose success is a DODGE - seeded from the decompiled source (side-dodge, AoE and restrain-dodge moves) + the live dump. Everything else uses the Default action; restrain-PARRY moves (Gamma Drill, CorrosiveBite, Pressure Ball) correctly stay Parry. Add moves as you meet them.' })
        ParryBox:AddToggle('FSRewriteBlocked', { Text = 'Upgrade Blocked too', Default = true,
            Tooltip = 'Rewrite mode: while holding F you block (chip damage) and the client reports "Blocked" - upgrade that to a full Parry/Dodge as well.' })
        ParryBox:AddToggle('FSFakeAnims', { Text = 'Play defense FX/anims', Default = true,
            Tooltip = 'When a fail is rewritten to a success, also fire the game\'s own cosmetic remotes so it LOOKS real to everyone: parry = the ParryTry + Parry clang/particles + a brief block stance (ServerEffects2, broadcast to all clients); dodge = the real dodge animation via PlayAnimationServer. Same calls/args as a legit defense - the one difference is ordering: these fire a frame AFTER the verdict (a real ParryTry comes at the F-press). Cosmetically indistinguishable; turn OFF for zero extra traffic.' })
        ParryBox:AddSlider('FSParryDelay', { Text = 'Fire delay (direct mode)', Default = 0, Min = 0, Max = 0.6, Rounding = 2, Suffix = ' s',
            Tooltip = 'Fire-directly mode only.' })
        ParryBox:AddToggle('FSAttackEnd', { Text = 'Send AttackEnd (direct mode)', Default = true,
            Tooltip = 'Fire-directly mode only: send the end-of-attack handshake after our HitResult. Rewrite mode never needs it - the game does its own AttackEnd at the AttackEnd animation marker (the optional defense FX above are the only extra traffic Rewrite ever sends).' })
        ParryBox:AddToggle('FSLogCombat', { Text = 'Log combat (console)', Default = false,
            Tooltip = 'Prints every ActionClient attack, every in-flight rewrite, StartMinigame QTEs and all other incoming Remotes events to console.' })
        ParryBox:AddButton({ Text = 'Test parry (press F)', Func = function()
            pcall(function() VIM:SendKeyEvent(true, Enum.KeyCode.F, false, game); VIM:SendKeyEvent(false, Enum.KeyCode.F, false, game) end)
            Library:Notify('Pressed F (test)', 2)
        end })

        -- ===== UI: Auto Attack (your turn - ActionServer) =================
        local AttackBox = Tab:AddRightGroupbox('Auto Attack')
        AttackBox:AddLabel('Attacks for you on YOUR turn. From the dump: an attack\nis just ActionServer:FireServer(enemy, move), and your\nturn arrives as BattleMusic("Side", "PartyMembers").\nMoves load from YOUR equipped skills via the game\'s own\nGetEquippedSkills query. Pair with Auto QTE so the swing\nit triggers auto-aces its minigame.', true)
        local AttackStatus = AttackBox:AddLabel('Idle')
        AttackBox:AddToggle('FSAutoAttack', {
            Text = 'Auto attack', Default = false,
            Tooltip = 'On your turn, fire a ticked move at the first living enemy. Rotates through the ticked moves so it varies.',
        }):AddKeyPicker('FSAutoAttackKey', { Default = 'None', SyncToggleState = true, Mode = 'Toggle', Text = 'Auto attack' })
        AttackBox:AddDropdown('FSAttackMoves', {
            Values = { 'Slash', 'Punch', 'Stab', 'Cleave', 'Bash', 'Poke', 'Puncture', 'Slice', 'Smash', 'Maul', 'Scratch', 'ExecutionBlow', 'SerratedSlice' },
            Default = {}, Multi = true, AllowNull = true, Text = 'Use moves',
            Tooltip = 'Tick the moves to rotate through - NOTHING ticked = rotate through all listed. "Refresh moves" fills this with YOUR equipped skills straight from the game\'s own GetEquippedSkills query (CastSpell excluded for now); until refreshed it shows the known basic moves.',
        })
        AttackBox:AddButton({ Text = 'Refresh moves (your skills)', Func = function() if refreshMoves then refreshMoves(false) end end })
        AttackBox:AddInput('FSAttackExtra', { Text = 'Extra moves', Default = 'Punch', Finished = true,
            Placeholder = 'Punch, Slash',
            Tooltip = 'Comma-separated moves ADDED to the dropdown on refresh. Basic attacks like Punch come from your WEAPON (BruiserBands = fist), not from GetEquippedSkills, and the weapon-type mapping is partly guesswork - so anything the queries miss goes here. Seeded with Punch.' })
        AttackBox:AddSlider('FSAttackDelay', { Text = 'Turn delay', Default = 1, Min = 0, Max = 5, Rounding = 1, Suffix = ' s',
            Tooltip = 'Wait this long after your turn starts before attacking. 0 = instant (reads robotic).' })
        AttackBox:AddSlider('FSAttackRetry', { Text = 'Retry interval', Default = 2, Min = 0.5, Max = 5, Rounding = 1, Suffix = ' s',
            Tooltip = 'If the attack did not register (move on cooldown, target died), try the NEXT move in the rotation after this long - as long as it is still your turn.' })
        AttackBox:AddToggle('FSAttackSkipBL', { Text = 'Skip blacklisted moves', Default = true,
            Tooltip = 'Ask the game\'s own CombatCheckClient("Get","ActionBlacklist") before attacking (exactly what the real client does at battle start) and skip any move it lists.' })
        AttackBox:AddToggle('FSAttackStamina', { Text = 'Skip moves you can\'t afford', Default = true,
            Tooltip = 'Stamina is checked AND deducted on the server (Realize: "NotEnoughStamina" -> the attack is dropped, turn wasted). This reads your Stats.Stamina and the move\'s StaminaUsage from the game\'s own SkillSmallDescriptions module and skips moves you cannot pay for. Punch costs 0.' })

        -- ===== UI: Stack & Release (multi-hit burst) ======================
        local StackBox = Tab:AddRightGroupbox('Stack & Release')
        StackBox:AddLabel('From the decompiled server module (Realize): EVERY\nActionServer call parks its own listener waiting for ONE\nQteResult, then deals damage. Fire the move N times, hold\nthe game\'s own QTE reports, then send ONE grade - all N\nlisteners resolve at once = N hits in the same instant.\nStamina is paid per copy (server-side). Punch is free.', true)
        local StackStatus = StackBox:AddLabel('Idle')
        StackBox:AddToggle('FSStackAuto', {
            Text = 'Auto stack on my turn', Default = false,
            Tooltip = 'On your turn: stack the move below instead of a normal auto-attack, then release after "Hold" (or on the keybind if Manual release is on).',
        }):AddKeyPicker('FSStackAutoKey', { Default = 'None', SyncToggleState = true, Mode = 'Toggle', Text = 'Auto stack' })
        StackBox:AddDropdown('FSStackMove', {
            Values = { 'Punch', 'Slash', 'Stab', 'Cleave', 'Bash', 'Poke', 'Puncture', 'Slice', 'Smash', 'Maul', 'Scratch', 'ExecutionBlow', 'SerratedSlice' },
            Default = 1, Multi = false, Text = 'Move to stack',
            Tooltip = 'Single-QTE basic attacks stack cleanly (Punch/Slash/Stab/Cleave/Bash/Poke/Puncture/Slice/Smash/Maul/Scratch/ExecutionBlow/SerratedSlice). Multi-hit skills (DoubleStrike, NeedleFlurry...) wait for SEVERAL reports each - unpredictable. "Refresh moves" fills this list too.',
        })
        StackBox:AddDropdown('FSStackTarget', {
            Values = { 'Lowest-HP enemy', 'All enemies (full stack each)', 'All enemies (split the stack)' },
            Default = 1, Multi = false, Text = 'Targets',
            Tooltip = 'Lowest-HP = the whole stack on one mob. Full stack each = Stack size copies on EVERY living enemy (3 mobs x 5 = 15 copies, one release lands all of them). Split = Stack size copies total, dealt round-robin across the mobs. Every copy is its own server listener, so ONE release resolves all of them. Stamina is paid per copy.',
        })
        StackBox:AddSlider('FSStackCount', { Text = 'Stack size', Default = 5, Min = 2, Max = 20, Rounding = 0, Suffix = 'x',
            Tooltip = 'How many copies of the move to fire before releasing (per enemy in "full stack each" mode). Capped by stamina when "Cap by stamina" is on.' })
        StackBox:AddSlider('FSStackGap', { Text = 'Gap between copies', Default = 0.05, Min = 0, Max = 0.5, Rounding = 2, Suffix = ' s' })
        StackBox:AddSlider('FSStackHold', { Text = 'Hold before release', Default = 1.5, Min = 0, Max = 8, Rounding = 1, Suffix = ' s',
            Tooltip = 'Auto-release this long after the last copy. The server turns the WHOLE stack into a Miss at its own timeout (Punch/Stab/Scratch 12s, Slash/Slice 14s, others 20s, counted from the FIRST copy) - a safety release always fires 2s before that.' })
        StackBox:AddToggle('FSStackManual', { Text = 'Manual release (keybind)', Default = false,
            Tooltip = 'Do not auto-release after Hold - wait for the Release key / button (the safety release before the server timeout still applies).' })
        StackBox:AddToggle('FSStackStamina', { Text = 'Cap by stamina', Default = true,
            Tooltip = 'Fire only as many copies as your Stats.Stamina can pay for (cost from the game\'s SkillSmallDescriptions). The server rejects unpaid copies anyway - this just keeps the count honest. Punch costs 0 = unlimited.' })
        StackBox:AddButton({ Text = 'Stack now', Func = function() if stackFire then stackFire('button') end end })
        StackBox:AddButton({ Text = 'Release now', Func = function() if stackRelease then stackRelease('button') end end })
        StackBox:AddLabel('Stack key'):AddKeyPicker('FSStackKey', { Default = 'None', Mode = 'Toggle', Text = 'Stack now' })
        StackBox:AddLabel('Release key'):AddKeyPicker('FSStackReleaseKey', { Default = 'None', Mode = 'Toggle', Text = 'Release stack' })

        -- ===== UI: Auto Scavenge (Mining minigame) ========================
        local MineBox = Tab:AddLeftGroupbox('Auto Scavenge (Mining)')
        MineBox:AddLabel('Auto-completes the mining-node minigame. From the\ndecompiled Mining module: the stones, the ore rolls and\nthe final loot are ALL decided on YOUR client - it fires\nQteResult(<table of ore counts>) at the end and the\nserver credits whatever table arrives (your manual run\nproved it). So this just sends the loot you set below.', true)
        local MineStatus = MineBox:AddLabel('Idle')
        MineBox:AddToggle('FSAutoMine', {
            Text = 'Auto scavenge', Default = false,
            Tooltip = 'When the Mining minigame opens (StartMinigame "Mining"), auto-complete it with the loot below.',
        }):AddKeyPicker('FSAutoMineKey', { Default = 'None', SyncToggleState = true, Mode = 'Toggle', Text = 'Auto scavenge' })
        MineBox:AddDropdown('FSMineMethod', {
            Values = { 'Auto-click stones (real loot)', 'Instant result (after delay)', 'Rewrite the real result' },
            Default = 1, Multi = false, Text = 'Method',
            Tooltip = 'Auto-click = actually plays the minigame: sweeps every stone with real clicks (1-click break below makes each pop instantly), the game rolls the ores itself and sends ITS OWN result - fully authentic traffic, loot = the max the RNG gives. Instant = skip playing, fire the configured loot table after the delay below and swallow the minigame\'s own late result - fastest. Rewrite = AFK through the ~10s timer, then fill the game\'s own outgoing table with the configured loot.',
        })
        MineBox:AddInput('FSMineLoot', {
            Text = 'Loot', Default = 'Iron=3, Copper=2, Silver=1, Gold=1', Finished = true,
            Placeholder = 'Iron=3, Copper=2',
            Tooltip = 'Ore=count pairs. Valid ores: Copper, Ruby, Silver, Iron, Wishbone, Emerald, Fossil, Gold. HONEST: the server trusts the table, but keep counts PLAUSIBLE for a 10s minigame (stones take 2 hits, some roll empty) - a great legit run is maybe 5-8 ores total. Absurd values are the one thing a server-side sanity check could ever flag.',
        })
        MineBox:AddToggle('FSMineJitter', { Text = 'Randomize counts (+/-1)', Default = true,
            Tooltip = 'Nudge each configured count by -1/0/+1 every run so nodes don\'t all yield the exact same table.' })
        MineBox:AddSlider('FSMineDelay', { Text = 'Instant-mode delay', Default = 5, Min = 0, Max = 10, Rounding = 1, Suffix = ' s',
            Tooltip = 'Instant mode: how long to "mine" before the result fires. The real minigame is a ~3s countdown + 10s timer, so a few seconds reads as a fast legit run. 0 = truly instant.' })
        MineBox:AddToggle('FSMineOneClick', { Text = '1-click break', Default = true,
            Tooltip = 'Stones normally take 2 hits (from the source: Hits attribute 1 = cracked, 2 = break). This pre-sets every stone\'s Hits to 1 the moment the grid spawns, so YOUR first click (or the auto-clicker\'s) breaks it instantly. Pure client-side GUI state - the server never sees hit counts, only the final loot table. Works for manual mining too.' })
        MineBox:AddSlider('FSMineClickDelay', { Text = 'Auto-click interval', Default = 0.05, Min = 0, Max = 0.3, Rounding = 2, Suffix = ' s',
            Tooltip = 'Auto-click mode: pause between stone clicks. The click handler has no cooldown, so 0.05s clears a full grid in about a second once the countdown ends.' })

        -- ===== UI: Forgotten Stories info ================================
        local InfoBox = Tab:AddLeftGroupbox('Forgotten Stories')
        InfoBox:AddLabel('More FS scripts on request (farms, teleports, ESP...).', true)
        InfoBox:AddButton({ Text = 'Copy PlaceId', Func = function()
            if setclipboard then pcall(setclipboard, tostring(game.PlaceId)) end
            Library:Notify('Copied PlaceId: ' .. tostring(game.PlaceId), 4)
        end }):AddButton({ Text = 'Copy GameId (universe)', Func = function()
            if setclipboard then pcall(setclipboard, tostring(game.GameId)) end
            Library:Notify('Copied GameId: ' .. tostring(game.GameId), 4)
        end })

        -- ===== LOGIC =====================================================
        -- Built from the DECOMPILED client combat module (ReplicatedStorage.
        -- Modules.PlayAnimations / ProcessAttack / QuickTimeEvents) + a live
        -- RemoteSpy dump. The facts that drive the design:
        --  * YOUR client judges the defense itself (0.18s parry / 0.30s dodge
        --    input windows) and ALWAYS files a verdict at the enemy attack
        --    animation's keyframe markers: success -> HitResult "Parry"/"Dodge"
        --    at the Parry/Left/Right/Down/Jump marker; failure -> the "Hit"
        --    marker fires HitResult(...,"Hit") (or "Blocked" while holding F)
        --    0.07s after the swing lands. QTE modules likewise fire
        --    QteResult("Miss") BY THEMSELVES when ignored (timeout).
        --  * Therefore ADDING our own remote fire = TWO reports per attack;
        --    the game's authentic marker-timed one wins/conflicts server-side.
        --    That is exactly why direct firing "did nothing".
        --  * Every combat send in the whole dump is namecall style
        --    (remote:FireServer(...)); zero cached direct calls. So one
        --    __namecall hook (documented + supported on Volt, and proven live
        --    by RemoteSpy on this machine) can REWRITE the verdict in-flight:
        --    single report, authentic timing, authentic args.
        local remoteCache = {}
        local function findRemote(n) -- RemoteEvents only (never a same-named Folder/Module)
            local c = remoteCache[n]
            if c and c.Parent then return c end
            local rf = RepStorage:FindFirstChild('Remotes')
            local r = rf and rf:FindFirstChild(n)
            if not (r and r:IsA('RemoteEvent')) then
                r = nil
                for _, d in ipairs(RepStorage:GetDescendants()) do
                    if d.Name == n and d:IsA('RemoteEvent') then r = d; break end
                end
            end
            remoteCache[n] = r
            return r
        end
        -- YOUR fighter model under workspace.PartyMembers. May be named by
        -- username (currently 'roblox_user_<UserId>' - that IS the account's
        -- real name after the Roblox rename) - match every form.
        local ANON = 'roblox_user_' .. LocalPlayer.UserId
        local function myFighter()
            local pm = workspace:FindFirstChild('PartyMembers')
            if pm then
                local m = pm:FindFirstChild(LocalPlayer.Name) or pm:FindFirstChild(ANON)
                if m then return m end
                for _, c in ipairs(pm:GetChildren()) do
                    if Players:GetPlayerFromCharacter(c) == LocalPlayer then return c end
                end
            end
            return LocalPlayer.Character -- may be nil in party combat; callers guard
        end
        local function tapKey(kc)
            pcall(function() VIM:SendKeyEvent(true, kc, false, game); VIM:SendKeyEvent(false, kc, false, game) end)
        end
        local function isMe(inst)
            if typeof(inst) ~= 'Instance' then return false end
            if inst == myFighter() or (LocalPlayer.Character and inst == LocalPlayer.Character) then return true end
            if Players:GetPlayerFromCharacter(inst) == LocalPlayer then return true end
            return inst.Name == LocalPlayer.Name or inst.Name == ANON
        end
        -- Does an ActionClient(attacker, defender, ...) target ME?
        --   direct hit -> defender is my fighter model
        --   AoE        -> defender is the STRING "AoE"; the game's own client
        --                 substitutes YOUR model on each client (ProcessAttack
        --                 does `if a2 == "AoE" then a2 = LocalPlayer.PlayerCharacter.Value`),
        --                 so any non-mine AoE is aimed at me too.
        local function targetsMe(attacker, defender)
            if isMe(defender) then return true end
            if typeof(defender) == 'string' then return not isMe(attacker) end
            return false
        end
        -- Status/UI updates queued from hook threads (which must NOT touch GUI -
        -- wrong thread identity) and drained on our own Heartbeat thread.
        local uiQueue = {}
        local function pushStatus(which, text) uiQueue[#uiQueue + 1] = { which, text } end
        -- Cosmetic-FX requests ({action, defenderModel, Side}) queued from the
        -- hook thread the same way; the drain fires them on our own thread.
        local fxQueue = {}
        -- Dodge-move set parsed from the input (lowercased).
        local function dodgeSet()
            local set = {}
            for m in tostring((Options.FSDodgeMoves and Options.FSDodgeMoves.Value) or ''):gmatch('[^,]+') do
                m = m:gsub('^%s+', ''):gsub('%s+$', ''); if m ~= '' then set[m:lower()] = true end
            end
            return set
        end
        -- The action a success report should carry for this move. From the source:
        -- defense validity is baked into each move's animation MARKERS, not data -
        -- so this is the dodge-list (side-dodge + restrain-dodge moves) with
        -- everything else defaulting to Parry (restrain-parry moves incl. Gamma
        -- Drill / CorrosiveBite / Pressure Ball resolve as Parry, correctly).
        -- Moves arrive as bare ids (BarkStomp) OR "Character: Move" display names
        -- ("Bandit: Assassinate") - BOTH exist on the wire (dump + source). Match
        -- the full string AND the tail after ':' so one list covers both forms.
        local function isDodgeMove(move)
            if not move then return false end
            local s = dodgeSet()
            local m = tostring(move):lower()
            if s[m] then return true end
            local tail = m:match(':%s*(.+)$')
            return (tail ~= nil and s[tail]) == true
        end
        local function requiredAction(move)
            if isDodgeMove(move) then return 'Dodge' end
            local dflt = (Options.FSDefault and Options.FSDefault.Value) or 'Parry'
            return (dflt == 'Dodge') and 'Dodge' or 'Parry' -- 'Both' = Parry here (one packet, one action)
        end
        -- Which method is active?
        local function qteRewriteOn()
            return Toggles.AutoQTE and Toggles.AutoQTE.Value
                and tostring((Options.QTEMethod and Options.QTEMethod.Value) or 'Rewrite'):find('Rewrite') ~= nil
        end
        local function parryRewriteOn()
            return Toggles.FSAutoParry and Toggles.FSAutoParry.Value
                and tostring((Options.FSParryMethod and Options.FSParryMethod.Value) or 'Rewrite'):find('Rewrite') ~= nil
        end
        -- ==== Auto Scavenge (Mining) helpers ==============================
        -- From the decompiled Mining QTE module: stones break CLIENT-side (2
        -- clicks each - hitStone: 1st click cracks, 2nd calls breakStone; a
        -- Stonewhisperers-Guide roll can insta-break), some stones roll empty,
        -- rollOre() picks the ore CLIENT-side, and the finished loot goes up as
        -- QteResult:FireServer(<table of ore counts>). The server credits the
        -- table as-is. Clicks/hits never reach the server - only this table.
        local MINE_ORES = { 'Copper', 'Ruby', 'Silver', 'Iron', 'Wishbone', 'Emerald', 'Fossil', 'Gold' }
        local mineFiredAt = -1e9 -- when WE last fired a loot table (duplicate guard)
        local function buildMineLoot()
            local t = {}
            for _, o in ipairs(MINE_ORES) do t[o] = 0 end -- real client sends ALL keys, zeros included
            for k, v in tostring((Options.FSMineLoot and Options.FSMineLoot.Value) or ''):gmatch('(%a+)%s*=%s*(%d+)') do
                for _, o in ipairs(MINE_ORES) do
                    if o:lower() == k:lower() then t[o] = tonumber(v) or 0 end
                end
            end
            if Toggles.FSMineJitter and Toggles.FSMineJitter.Value then
                for k, v in pairs(t) do
                    if v > 0 then t[k] = math.max(0, v + math.random(-1, 1)) end
                end
            end
            return t
        end
        local function lootString(t)
            local parts = {}
            for _, o in ipairs(MINE_ORES) do
                if (t[o] or 0) > 0 then parts[#parts + 1] = o .. ' x' .. t[o] end
            end
            return (#parts > 0) and table.concat(parts, ', ') or 'nothing'
        end
        local function mineInstantOn()
            return Toggles.FSAutoMine and Toggles.FSAutoMine.Value
                and tostring((Options.FSMineMethod and Options.FSMineMethod.Value) or ''):find('Instant') ~= nil
        end
        local function mineRewriteOn()
            return Toggles.FSAutoMine and Toggles.FSAutoMine.Value
                and tostring((Options.FSMineMethod and Options.FSMineMethod.Value) or ''):find('Rewrite') ~= nil
        end
        local function mineAutoClickOn()
            return Toggles.FSAutoMine and Toggles.FSAutoMine.Value
                and tostring((Options.FSMineMethod and Options.FSMineMethod.Value) or 'Auto'):find('click') ~= nil
        end
        -- The live Mining grid's stones: ImageLabels carrying the module's OWN
        -- setupStone attributes (Hits / Broken / IsEmpty) - a selector that can't
        -- confuse them with any other GUI, whatever the ScreenGui is named.
        local function findMineStones(timeout)
            local t0 = os.clock()
            repeat
                local roots = { LocalPlayer:FindFirstChild('PlayerGui') }
                pcall(function() roots[#roots + 1] = (gethui and gethui()) or game:GetService('CoreGui') end)
                for _, root in ipairs(roots) do
                    if root then
                        local stones = {}
                        for _, d in ipairs(root:GetDescendants()) do
                            if d:IsA('ImageLabel') and d:GetAttribute('Broken') ~= nil and d:GetAttribute('Hits') ~= nil then
                                stones[#stones + 1] = d
                            end
                        end
                        if #stones > 0 then return stones end
                    end
                end
                task.wait(0.1)
            until os.clock() - t0 > (timeout or 8)
            return nil
        end
        -- Auto-mine: pre-crack every stone to Hits=1 (next hit = break, from the
        -- decompiled hitStone: v36 >= 2 -> breakStone), then sweep the grid with
        -- real VIM clicks. Clicks during the 3s countdown no-op (the module's
        -- input flag isn't set yet), so the loop just keeps sweeping until every
        -- stone reports Broken - each break runs the game's own rollOre(), and
        -- the game sends ITS OWN loot table at the end. Zero fabricated traffic.
        local mineClicking = false
        local function autoMineRun()
            if mineClicking then return end
            mineClicking = true
            local ok, err = pcall(function()
                local stones = findMineStones(8)
                if not stones then pushStatus('mine', 'Mining grid not found'); return end
                local oneClick = Toggles.FSMineOneClick and Toggles.FSMineOneClick.Value
                if oneClick then
                    for _, s in ipairs(stones) do
                        pcall(function()
                            if s:GetAttribute('Broken') == false and (s:GetAttribute('Hits') or 0) < 1 then
                                s:SetAttribute('Hits', 1) -- next hit breaks it
                            end
                        end)
                    end
                end
                if not mineAutoClickOn() then
                    if oneClick then pushStatus('mine', '1-click armed on ' .. #stones .. ' stones') end
                    return -- 1-click only; the player clicks manually
                end
                pushStatus('mine', 'Auto-mining ' .. #stones .. ' stones...')
                local inset = game:GetService('GuiService'):GetGuiInset()
                local deadline = os.clock() + 18 -- countdown (~3s) + 10s timer + slack
                while os.clock() < deadline do
                    if not (Toggles.FSAutoMine and Toggles.FSAutoMine.Value) then break end
                    local remaining = 0
                    for _, s in ipairs(stones) do
                        if s.Parent and s:GetAttribute('Broken') == false then
                            remaining = remaining + 1
                            local c = s.AbsolutePosition + s.AbsoluteSize / 2
                            local x, y = math.floor(c.X + inset.X), math.floor(c.Y + inset.Y)
                            pcall(function() VIM:SendMouseMoveEvent(x, y, game) end)
                            RunService.Heartbeat:Wait() -- let the hit test see the new cursor spot
                            pcall(function() VIM:SendMouseButtonEvent(x, y, 0, true, game, 0) end)
                            pcall(function() VIM:SendMouseButtonEvent(x, y, 0, false, game, 0) end)
                            local dly = (Options.FSMineClickDelay and Options.FSMineClickDelay.Value) or 0.05
                            if dly > 0 then task.wait(dly) end
                        end
                    end
                    if remaining == 0 then pushStatus('mine', 'All stones broken'); break end
                    if not stones[1].Parent then break end -- grid closed (result already sent)
                    RunService.Heartbeat:Wait()
                end
            end)
            mineClicking = false
            if not ok then pushStatus('mine', 'Auto-mine error: ' .. tostring(err):sub(1, 60)) end
        end

        -- QTE: fire the configured grade ourselves (Instant mode / test button).
        -- Returns true only if the remote was found AND the fire didn't error -
        -- no more UI claiming success while a pcall swallowed a failure.
        fireQte = function()
            local r = findRemote('QteResult'); if not r then return false end
            local g = tostring((Options.QTEResult and Options.QTEResult.Value) or '')
            if g == '' then g = 'Critical' end -- an emptied Grade box must never fire ""
            return (pcall(function() r:FireServer(g) end))
        end

        local SIDE_KEY = { left = Enum.KeyCode.A, right = Enum.KeyCode.D, down = Enum.KeyCode.S, back = Enum.KeyCode.S }

        -- Direct-mode defense (fallback methods only - Rewrite never calls this).
        -- Fires our own HitResult mirroring the ActionClient args, or taps keys.
        -- Returns true only when something was actually sent.
        defend = function(attacker, defender, move, options)
            local forced = isDodgeMove(move) -- in the dodge list (either name form)
            local dflt   = (Options.FSDefault and Options.FSDefault.Value) or 'Parry'
            local actions
            if forced then actions = { 'Dodge' }
            elseif dflt == 'Dodge' then actions = { 'Dodge' }
            elseif dflt == 'Both (parry + dodge)' then actions = { 'Parry', 'Dodge' } -- fire both, server takes the right one
            else actions = { 'Parry' } end
            local side   = (options and options.Side) or 'None'
            local stream = (options and options.Streampath) or false
            local method = tostring((Options.FSParryMethod and Options.FSParryMethod.Value) or '')
            if method:find('Simulate') then
                task.spawn(function()
                    local key = (actions[1] == 'Dodge') and (SIDE_KEY[tostring(side):lower()] or Enum.KeyCode.W) or Enum.KeyCode.F
                    local t0 = os.clock()
                    repeat tapKey(key); task.wait(0.05) until os.clock() - t0 > 0.6
                end)
                return true
            end
            local hr = findRemote('HitResult')
            if not hr then Library:Notify('FS: HitResult remote not found', 4); return false end
            -- The server expects the EXACT PartyMembers model as the defender. For a
            -- direct hit that's the instance it sent; for an AoE (defender = "AoE"
            -- string) substitute my own fighter model. NEVER the string, NEVER nil.
            local me = (typeof(defender) == 'Instance' and isMe(defender)) and defender or myFighter()
            if not me then Library:Notify('FS: could not resolve YOUR fighter under workspace.PartyMembers', 5); return false end
            local sent = false
            for _, action in ipairs(actions) do
                sent = pcall(function()
                    hr:FireServer(attacker or workspace, me, move or 'Chop', action, { Side = side, Streampath = stream })
                end) or sent
            end
            if sent and Toggles.FSAttackEnd and Toggles.FSAttackEnd.Value then
                local ae = findRemote('AttackEnd'); if ae then pcall(function() ae:FireServer() end) end
            end
            if sent and Toggles.FSFakeAnims and Toggles.FSFakeAnims.Value then
                fxQueue[#fxQueue + 1] = { actions[1], me, side } -- look the part in direct mode too
            end
            return sent
        end

        -- Cosmetic defense FX so a rewritten parry/dodge LOOKS real to everyone.
        -- These are the EXACT cosmetic sends the legit client makes on a real
        -- defense (from the decompiled PlayAnimations module + the live dump):
        --   parry -> ServerEffects2(me,"ParryTry",false); (me,nil,"Parry",false)
        --            [clang + Parry1-5 particles, rebroadcast to ALL clients via
        --            ClientEffects] + a brief BlockStart/BlockEnd stance;
        --   dodge -> PlayAnimationServer(me, Animations.Humanoid.<side>Dodge,
        --            false) [server rebroadcasts PlayAnimationClient -> every
        --            player sees the dodge animation on your model].
        -- The server just relays these (pure cosmetics), so they're safe extras.
        local fxFlip = false
        local function playDefenseFx(kind, me, side)
            me = (typeof(me) == 'Instance') and me or myFighter()
            if not me then return end
            if kind == 'Dodge' then
                local pas = findRemote('PlayAnimationServer')
                local anims = RepStorage:FindFirstChild('Animations')
                local hum = anims and anims:FindFirstChild('Humanoid')
                if not (pas and hum) then return end
                -- Sided attacks are dodged to the OPPOSITE side (from the source's
                -- RandomSideDodge handler); no side -> alternate so it varies.
                side = tostring(side or ''):lower()
                local animName
                if side == 'left' then animName = 'RightDodge'
                elseif side == 'right' then animName = 'LeftDodge'
                else fxFlip = not fxFlip; animName = fxFlip and 'LeftDodge' or 'RightDodge' end
                local anim = hum:FindFirstChild(animName) or hum:FindFirstChild('LeftDodge')
                if anim then pcall(function() pas:FireServer(me, anim, false) end) end
            else -- Parry
                local se = findRemote('ServerEffects2'); if not se then return end
                pcall(function() se:FireServer(me, 'ParryTry', false) end)       -- the F-press try sound
                pcall(function() se:FireServer(me, nil, 'Parry', false) end)     -- clang + parry particles
                pcall(function() se:FireServer(me, nil, 'BlockStart', true) end) -- brief block stance...
                task.delay(0.45, function()
                    pcall(function() se:FireServer(me, nil, 'BlockEnd', true) end) -- ...then drop it
                end)
            end
        end

        -- ==== THE REWRITE HOOK (the actual fix) ============================
        -- Intercept the game's OWN outgoing combat reports and flip the verdict:
        --   HitResult(atk, me, move, "Hit"/"Blocked", opts) -> "Parry"/"Dodge"
        --   QteResult("Miss"/"Hit" [,name])                 -> configured grade
        -- The game keeps its exact timing (animation markers), arg shapes,
        -- once-flags and AttackEnd handshake - the server sees ONE authentic
        -- report per attack. Our own direct fires pass checkcaller() and are
        -- never rewritten. Any error in the decision falls through to the
        -- original call so combat can never break because of us.
        -- Stack & Release state (read by the hook thread, written by our thread):
        -- while a stack is armed the game's OWN QteResult grade reports are
        -- swallowed (stackSwallow counts down, bounded by stackMuteUntil) so
        -- nothing resolves the server-side listeners before our single release.
        local stackSwallow, stackMuteUntil, stackPending, stackMove = 0, 0, 0, nil
        local nmOld -- original __namecall; restored on unload
        do
            local hookMeta = hookmetamethod
            local getNC    = getnamecallmethod
            local canCall  = checkcaller or function() return false end
            local STD_GRADE = { Miss = true, Hit = true, Critical = true }
            local BLOCK = {} -- sentinel: decide says "swallow this call entirely"
            -- Runs on the GAME's calling thread: no Instance creation / GUI writes
            -- here (that thread lacks the capability) - status goes through uiQueue.
            local function decide(self, ...)
                local nme = self.Name
                if nme == 'QteResult' then
                    local a = table.pack(...)
                    -- MINING: this QteResult carries a TABLE of ore counts, not a
                    -- grade string (Mining module fires it at its 10s timeout).
                    if type(a[1]) == 'table' then
                        if not (Toggles.FSAutoMine and Toggles.FSAutoMine.Value) then return nil end
                        if mineInstantOn() then
                            -- Instant mode already fired OUR loot; swallow the
                            -- module's late (mostly empty) duplicate.
                            if os.clock() - mineFiredAt < 30 then return BLOCK end
                            return nil
                        end
                        if not mineRewriteOn() then
                            -- Auto-click mode: this table is the REAL loot from the
                            -- stones we broke - pass it through untouched.
                            pushStatus('mine', 'Mined: ' .. lootString(a[1]))
                            return nil
                        end
                        -- Rewrite mode: fill the game's OWN table IN PLACE (tables
                        -- pass by reference, so the original call - at its authentic
                        -- timeout moment - sends our counts). No repack needed.
                        for k, v in pairs(buildMineLoot()) do a[1][k] = v end
                        pushStatus('mine', 'Loot rewritten: ' .. lootString(a[1]))
                        return nil
                    end
                    -- STACK armed: hold the game's own grade report so the N parked
                    -- server listeners stay pending until OUR single release.
                    if stackSwallow > 0 and os.clock() < stackMuteUntil then
                        stackSwallow = stackSwallow - 1
                        pushStatus('stack', ('Held game QTE "%s" (%d pending, %d more to hold)'):format(tostring(a[1]), stackPending, stackSwallow))
                        return BLOCK
                    end
                    if not qteRewriteOn() then return nil end
                    -- only standard grades: special QTEs (Soulkiller "Alive"/"Death")
                    -- use their own words - forcing "Critical" there could hurt you.
                    if not STD_GRADE[tostring(a[1])] then return nil end
                    local want = tostring((Options.QTEResult and Options.QTEResult.Value) or '')
                    if not STD_GRADE[want] then want = 'Critical' end -- empty/typo'd Grade box can NOT reach the wire
                    if tostring(a[1]) == want then
                        pushStatus('qte', 'QTE already ' .. want)
                        return nil
                    end
                    pushStatus('qte', ('QTE %s -> %s'):format(tostring(a[1]), want))
                    a[1] = want
                    return a
                elseif nme == 'HitResult' then
                    if not parryRewriteOn() then return nil end
                    local a = table.pack(...)
                    local act = a[4]
                    if act == 'Hit' or (act == 'Blocked' and Toggles.FSRewriteBlocked and Toggles.FSRewriteBlocked.Value) then
                        local newAct = requiredAction(a[3])
                        pushStatus('parry', ('%s: %s -> %s'):format(tostring(a[3]), tostring(act), newAct))
                        if Toggles.FSFakeAnims and Toggles.FSFakeAnims.Value then
                            -- queue the matching cosmetic FX (fired from OUR thread
                            -- next frame; a[2] = my fighter model, a[5] = options)
                            fxQueue[#fxQueue + 1] = { newAct, a[2], type(a[5]) == 'table' and a[5].Side or nil }
                        end
                        a[4] = newAct
                        return a
                    elseif act == 'Parry' or act == 'Dodge' then
                        pushStatus('parry', ('%s: real %s (kept)'):format(tostring(a[3]), act))
                    end
                end
                return nil
            end
            if hookMeta and getNC then
                local okHook, hookErr = pcall(function()
                    nmOld = hookMeta(game, '__namecall', function(self, ...)
                        if nmOld and getNC() == 'FireServer' and typeof(self) == 'Instance' and not canCall() then
                            local okD, repl = pcall(decide, self, ...)
                            if okD and repl == BLOCK then return end -- swallowed (duplicate mining result / held stack report)
                            if okD and repl then return nmOld(self, table.unpack(repl, 1, repl.n)) end
                        end
                        if nmOld then return nmOld(self, ...) end
                        -- Original lost (a broken hookmetamethod returned nil):
                        -- raw indexed dispatch keeps the game working, un-rewritten.
                        return self[getNC()](self, ...)
                    end)
                end)
                if okHook and nmOld then
                    -- restore on unload via the hubConns sweep (pseudo-connection)
                    htrack({ Disconnect = function() pcall(function() hookMeta(game, '__namecall', nmOld) end) end })
                else
                    Library:Notify('FS: __namecall hook FAILED (' .. tostring(hookErr) .. ') - Rewrite method dead, switch Method to direct fire.', 8)
                end
            else
                Library:Notify('FS: executor lacks hookmetamethod/getnamecallmethod - Rewrite method unavailable, switch Method to direct fire.', 8)
            end
        end

        -- Drain queued status text + cosmetic FX on OUR thread (executor
        -- identity - GUI-safe, and our fires pass checkcaller so the hook
        -- never rewrites them).
        htrack(RunService.Heartbeat:Connect(function()
            if #fxQueue > 0 then
                local fb = fxQueue; fxQueue = {}
                for _, f in ipairs(fb) do pcall(playDefenseFx, f[1], f[2], f[3]) end
            end
            if #uiQueue == 0 then return end
            local batch = uiQueue; uiQueue = {}
            for _, m in ipairs(batch) do
                pcall(function()
                    if m[1] == 'qte' and QteStatus then QteStatus:SetText(m[2])
                    elseif m[1] == 'parry' and ParryStatus then ParryStatus:SetText(m[2])
                    elseif m[1] == 'mine' and MineStatus then MineStatus:SetText(m[2])
                    elseif m[1] == 'attack' and AttackStatus then AttackStatus:SetText(m[2])
                    elseif m[1] == 'stack' and StackStatus then StackStatus:SetText(m[2]) end
                    if Toggles.FSLogCombat and Toggles.FSLogCombat.Value then print('[FS] ' .. m[2]) end
                end)
            end
        end))

        -- ==== Auto Attack =================================================
        -- From the dump: an attack is ONE call - ActionServer:FireServer(
        -- <enemy model>, '<move>'). Turn signals: BattleMusic('Side', <side>)
        -- flips whose turn it is ('PartyMembers' = yours); battle 'Start'
        -- carries the opening side as its 4th arg; 'Stop' / EndBattle clear it.
        -- Moves come from the game's OWN InventoryQueryClient(
        -- 'GetEquippedSkills') query - the exact call the real client makes.
        local atkSide, atkTurnAt, atkLastTry = nil, 0, -1e9
        local atkActed, atkBusy, atkFlip = false, false, 0
        local ATK_FALLBACK = { 'Slash', 'Punch', 'Stab', 'Cleave', 'Bash', 'Poke', 'Puncture', 'Slice', 'Smash', 'Maul', 'Scratch', 'ExecutionBlow', 'SerratedSlice' }
        -- Flatten whatever shape GetEquippedSkills returns (array of strings,
        -- dict of name=true, array of tables with .Name) into a name list.
        local function skillNames(v, out, depth)
            out = out or {}; depth = depth or 0
            if depth > 3 then return out end
            if type(v) == 'string' then out[#out + 1] = v
            elseif type(v) == 'table' then
                for k, item in pairs(v) do
                    if type(item) == 'string' then out[#out + 1] = item
                    elseif type(item) == 'table' then
                        if type(item.Name) == 'string' then out[#out + 1] = item.Name
                        else skillNames(item, out, depth + 1) end
                    elseif type(k) == 'string' and item then out[#out + 1] = k end -- dict: ANY truthy value counts (true / slot number / level), not just `true`
                end
            end
            return out
        end
        refreshMoves = function(silent)
            task.spawn(function()
                local rem = RepStorage:FindFirstChild('Remotes')
                local iq = rem and rem:FindFirstChild('InventoryQueryClient')
                local names = {}
                local function dumpShape(tag, v) -- console print so the real return shape can be pinned
                    pcall(function()
                        print('[FS skills] ' .. tag .. ' -> ' .. game:GetService('HttpService'):JSONEncode(v))
                    end)
                end
                if iq and iq:IsA('RemoteFunction') then
                    -- 1) equipped SKILLS (Ragequake etc.). NOTE: basics like Punch are
                    -- NOT in here - they come from the equipped WEAPON.
                    local ok, res = pcall(function() return iq:InvokeServer('GetEquippedSkills') end)
                    if ok then dumpShape('GetEquippedSkills', res); names = skillNames(res) end
                    -- 2) equipped WEAPON TYPES -> their basic attack (BruiserBands =
                    -- fist -> Punch). Map is best-effort; unknown types stay raw so
                    -- they are at least visible in the dropdown/console.
                    local ok2, res2 = pcall(function() return iq:InvokeServer('GetEquippedWeaponTypes') end)
                    if ok2 then
                        dumpShape('GetEquippedWeaponTypes', res2)
                        local WEAPON_MOVE = {
                            fist = 'Punch', fists = 'Punch', unarmed = 'Punch', bruiser = 'Punch',
                            sword = 'Slash', axe = 'Cleave', hammer = 'Smash', mace = 'Bash',
                            spear = 'Poke', dagger = 'Stab', knife = 'Stab', claw = 'Scratch', claws = 'Scratch',
                        }
                        for _, w in ipairs(skillNames(res2)) do
                            names[#names + 1] = WEAPON_MOVE[tostring(w):lower()] or w
                        end
                    end
                end
                -- 3) user-typed extras: the guaranteed path for anything the queries miss
                for m in tostring((Options.FSAttackExtra and Options.FSAttackExtra.Value) or ''):gmatch('[^,]+') do
                    m = m:gsub('^%s+', ''):gsub('%s+$', '')
                    if m ~= '' then names[#names + 1] = m end
                end
                local seen, list = {}, {}
                for _, n in ipairs(names) do
                    local key = tostring(n)
                    -- per request: leave spell-casting out for now
                    if not seen[key] and not key:lower():gsub('%s', ''):find('castspell') then
                        seen[key] = true; list[#list + 1] = key
                    end
                end
                table.sort(list)
                if #list == 0 then list = ATK_FALLBACK end
                if Options.FSAttackMoves then pcall(function() Options.FSAttackMoves:SetValues(list) end) end
                if Options.FSStackMove then pcall(function() Options.FSStackMove:SetValues(list) end) end
                pushStatus('attack', #list .. ' move(s) loaded')
                if not silent then Library:Notify(('Auto attack: %d move(s) loaded from your skills'):format(#list), 3) end
            end)
        end
        local function selectedMoves()
            local dd = Options.FSAttackMoves
            local all = (dd and dd.Values) or ATK_FALLBACK
            local sel = dd and dd.Value
            local list = {}
            if type(sel) == 'table' and next(sel) ~= nil then
                for _, n in ipairs(all) do if sel[n] then list[#list + 1] = n end end
            end
            if #list == 0 then -- nothing ticked = rotate through everything listed
                for _, n in ipairs(all) do list[#list + 1] = n end
            end
            return list
        end
        local function actionBlacklist() -- the same pre-check the real client runs
            if not (Toggles.FSAttackSkipBL and Toggles.FSAttackSkipBL.Value) then return nil end
            local rem = RepStorage:FindFirstChild('Remotes')
            local cc = rem and rem:FindFirstChild('CombatCheckClient')
            if not (cc and cc:IsA('RemoteFunction')) then return nil end
            local ok, res = pcall(function() return cc:InvokeServer('Get', 'ActionBlacklist') end)
            if not ok or type(res) ~= 'table' then return nil end
            local set = {}
            for k, v in pairs(res) do
                if type(v) == 'string' then set[v] = true
                elseif type(k) == 'string' then set[k] = true end
            end
            return set
        end
        -- Target the LOWEST-HP living enemy (finish kills first). HP read from
        -- the Humanoid, a Health/HP attribute, or a Health/HP Value child -
        -- whichever this game exposes; enemies with no readable HP sort last.
        local function enemyHealth(m)
            local hum = m:FindFirstChildOfClass('Humanoid')
            if hum then
                if hum.Health <= 0 then return nil end -- dead
                if hum.Health < hum.MaxHealth or hum.MaxHealth ~= 100 then return hum.Health end
            end
            local a = tonumber(m:GetAttribute('Health')) or tonumber(m:GetAttribute('HP'))
            if a then return (a > 0) and a or nil end
            local v = m:FindFirstChild('Health') or m:FindFirstChild('HP')
            if v and v:IsA('ValueBase') then
                local n = tonumber(v.Value)
                if n then return (n > 0) and n or nil end
            end
            if hum then return hum.Health end -- untouched default Humanoid: still alive
            return math.huge -- no readable HP: valid target, lowest priority
        end
        local function pickEnemy()
            local en = workspace:FindFirstChild('Enemies')
            if not en then return nil end
            local best, bestHp
            for _, m in ipairs(en:GetChildren()) do
                local hp = enemyHealth(m)
                if hp and (not bestHp or hp < bestHp) then best, bestHp = m, hp end
            end
            return best
        end
        -- Every living enemy, lowest HP first (so a split stack finishes kills first).
        local function livingEnemies()
            local en = workspace:FindFirstChild('Enemies')
            local list = {}
            if not en then return list end
            for _, m in ipairs(en:GetChildren()) do
                local hp = enemyHealth(m)
                if hp then list[#list + 1] = { m = m, hp = hp } end
            end
            table.sort(list, function(a, b) return a.hp < b.hp end)
            local out = {}
            for i, e in ipairs(list) do out[i] = e.m end
            return out
        end
        -- Stamina: checked AND deducted server-side in Realize (Stats.Stamina >=
        -- StaminaUsage, else "NotEnoughStamina" and the attack is dropped). It
        -- can't be bypassed from the client - but we can read both numbers the
        -- server reads and never waste a turn on a move we can't pay for.
        local skillDesc -- the game's own SkillSmallDescriptions.DNAData (costs, cooldowns)
        local function moveCost(mv)
            if skillDesc == nil then
                local ok, mod = pcall(function()
                    local m = RepStorage:FindFirstChild('Modules'); m = m and m:FindFirstChild('SkillSmallDescriptions')
                    return m and require(m)
                end)
                skillDesc = (ok and type(mod) == 'table' and type(mod.DNAData) == 'table') and mod.DNAData or false
            end
            local d = skillDesc and skillDesc[mv]
            if type(d) ~= 'table' then return nil end -- unknown move: no opinion
            return math.max(tonumber(d.StaminaUsage) or 0, 0), math.max(tonumber(d.ManaUsage) or 0, 0)
        end
        local function myStamina()
            local me = myFighter()
            local ci = me and me:FindFirstChild('CharacterInfo')
            local st = ci and ci:FindFirstChild('Stats')
            local s = st and st:FindFirstChild('Stamina')
            local m = st and st:FindFirstChild('Mana')
            return s and tonumber(s.Value) or nil, m and tonumber(m.Value) or nil
        end
        local function canAfford(mv)
            if not (Toggles.FSAttackStamina and Toggles.FSAttackStamina.Value) then return true end
            local sc, mc = moveCost(mv); if not sc then return true end
            local s, m = myStamina(); if not s then return true end
            if s < sc then return false, ('%s needs %s stamina, you have %s'):format(mv, sc, s) end
            if m and mc and m < mc then return false, ('%s needs %s mana, you have %s'):format(mv, mc, m) end
            return true
        end
        local function tryAttack()
            local enemy = pickEnemy()
            if not enemy then pushStatus('attack', 'No enemy to hit'); return end
            local moves = selectedMoves(); if #moves == 0 then return end
            local blk = actionBlacklist() -- yields; we're on our own thread
            local lastWhy
            for _ = 1, #moves do
                atkFlip = (atkFlip % #moves) + 1
                local mv = moves[atkFlip]
                local okCost, why = canAfford(mv)
                if not okCost then lastWhy = why
                elseif not (blk and blk[mv]) then
                    local as = findRemote('ActionServer'); if not as then return end
                    if pcall(function() as:FireServer(enemy, mv) end) then
                        pushStatus('attack', ('%s -> %s'):format(mv, enemy.Name))
                    end
                    return
                end
            end
            pushStatus('attack', lastWhy and ('Skipped: ' .. lastWhy) or 'All selected moves blacklisted (cooldown?)')
        end

        -- ==== Stack & Release ============================================
        -- Server (Realize, decompiled): per ActionServer call -> stamina paid ->
        -- ActionClient broadcast -> Casting=true -> a QteResult listener with a
        -- once-flag + per-move Timeout -> TakeDamage(grade). The listeners are
        -- independent, so N calls parked before any QteResult all resolve on the
        -- SAME single report. Hold the game's own reports (hook swallow), then
        -- send one grade = N simultaneous hits.
        local STACK_TIMEOUT = { Slash = 14, Cleave = 23, Bash = 20, Poke = 20, Puncture = 20, Slice = 14, Smash = 20,
            Maul = 20, Stab = 12, Scratch = 12, ExecutionBlow = 20, SerratedSlice = 20, Punch = 12, CorromushThrow = 12 }
        local stackBusy, stackFiredAt, stackGen = false, 0, 0
        -- true while a stack is being fired or is waiting for release: the
        -- Instant-QTE fallback paths must NOT fire a grade (it would release early).
        local function stackHolding() return stackBusy or stackPending > 0 end
        local function stackGrade()
            local g = tostring((Options.QTEResult and Options.QTEResult.Value) or '')
            if g ~= 'Miss' and g ~= 'Hit' and g ~= 'Critical' then g = 'Critical' end
            return g
        end
        stackRelease = function(reason)
            if stackPending <= 0 then pushStatus('stack', 'Nothing stacked to release'); return false end
            local r = findRemote('QteResult'); if not r then pushStatus('stack', 'QteResult remote missing'); return false end
            local g = stackGrade()
            local n, mv = stackPending, stackMove
            stackPending = 0
            local ok = pcall(function() r:FireServer(g) end) -- passes checkcaller: never swallowed
            pushStatus('stack', ok and ('RELEASED %d x %s as %s (%s) - all targets'):format(n, tostring(mv), g, tostring(reason))
                                or 'Release fire failed')
            return ok
        end
        stackFire = function(reason)
            if stackBusy then pushStatus('stack', 'Already stacking'); return false end
            -- Targets: one mob, or every living mob. Copies are dealt round-robin
            -- (lowest HP first) so a stamina-capped stack still spreads out.
            local mode = tostring((Options.FSStackTarget and Options.FSStackTarget.Value) or 'Lowest')
            local targets
            if mode:find('All') then targets = livingEnemies()
            else local e = pickEnemy(); targets = e and { e } or {} end
            if #targets == 0 then pushStatus('stack', 'No enemy to hit'); return false end
            local mv = tostring((Options.FSStackMove and Options.FSStackMove.Value) or 'Punch')
            if mv == '' or mv == 'nil' then mv = 'Punch' end
            local n = math.floor(tonumber(Options.FSStackCount and Options.FSStackCount.Value) or 5)
            if mode:find('full') then n = n * #targets end -- Stack size copies PER enemy
            if Toggles.FSStackStamina and Toggles.FSStackStamina.Value then
                local sc = moveCost(mv)
                local s = myStamina()
                if sc and sc > 0 and s then
                    local afford = math.floor(s / sc)
                    if afford < 1 then pushStatus('stack', ('Not enough stamina: %s costs %s, you have %s'):format(mv, sc, s)); return false end
                    if afford < n then n = afford end
                end
            end
            if n < 1 then return false end
            local as = findRemote('ActionServer'); if not as then pushStatus('stack', 'ActionServer remote missing'); return false end
            stackBusy = true
            stackGen = stackGen + 1
            local gen = stackGen
            task.spawn(function()
                atkActed = true -- keep the normal auto-attack quiet this turn
                local timeout = STACK_TIMEOUT[mv] or 12
                stackMove, stackPending = mv, 0
                stackSwallow, stackMuteUntil = n, os.clock() + timeout
                stackFiredAt = os.clock()
                local gap = tonumber(Options.FSStackGap and Options.FSStackGap.Value) or 0.05
                for i = 1, n do
                    local enemy = targets[((i - 1) % #targets) + 1] -- round-robin across the targets
                    if pcall(function() as:FireServer(enemy, mv) end) then stackPending = stackPending + 1 end
                    pushStatus('stack', ('Stacking %s %d/%d on %s%s%s'):format(mv, i, n, enemy.Name,
                        #targets > 1 and (' (+' .. (#targets - 1) .. ' more)') or '',
                        atkSide ~= 'PartyMembers' and ' (not your turn?)' or ''))
                    if gap > 0 then task.wait(gap) end
                end
                stackBusy = false
                if stackPending <= 0 then pushStatus('stack', 'No copy went out'); return end
                local manual = Toggles.FSStackManual and Toggles.FSStackManual.Value
                local hold = tonumber(Options.FSStackHold and Options.FSStackHold.Value) or 1.5
                -- safety: release before the server's timeout turns the whole stack into a Miss
                local safetyAt = stackFiredAt + timeout - 2
                if not manual then
                    task.wait(math.max(0, math.min(hold, safetyAt - os.clock())))
                    if stackGen == gen and stackPending > 0 then stackRelease('auto') end
                else
                    pushStatus('stack', ('%d x %s stacked - press Release (safety in %ds)'):format(stackPending, mv, math.floor(safetyAt - os.clock())))
                    task.delay(math.max(0, safetyAt - os.clock()), function()
                        if stackGen == gen and stackPending > 0 then stackRelease('safety timeout') end
                    end)
                end
            end)
            return true
        end
        htrack(RunService.Heartbeat:Connect(function()
            local autoOn  = Toggles.FSAutoAttack and Toggles.FSAutoAttack.Value
            local stackOn = Toggles.FSStackAuto and Toggles.FSStackAuto.Value
            if not (autoOn or stackOn) then return end
            if atkSide ~= 'PartyMembers' or atkActed or atkBusy or stackBusy then return end
            if os.clock() - atkTurnAt < ((Options.FSAttackDelay and Options.FSAttackDelay.Value) or 1) then return end
            if os.clock() - atkLastTry < ((Options.FSAttackRetry and Options.FSAttackRetry.Value) or 2) then return end
            atkLastTry = os.clock()
            atkBusy = true
            task.spawn(function()
                if stackOn then pcall(stackFire, 'auto') else pcall(tryAttack) end
                atkBusy = false
            end)
        end))
        if Options.FSStackKey then Options.FSStackKey:OnClick(function() if stackFire then stackFire('key') end end) end
        if Options.FSStackReleaseKey then Options.FSStackReleaseKey:OnClick(function() if stackRelease then stackRelease('key') end end) end
        -- Turn signals (BattleMusic / EndBattle), resolved race-proof like the rest.
        task.spawn(function()
            local rem = RepStorage:FindFirstChild('Remotes') or RepStorage:WaitForChild('Remotes', 60)
            if not rem then return end
            local bm = rem:FindFirstChild('BattleMusic') or rem:WaitForChild('BattleMusic', 60)
            if bm and bm:IsA('RemoteEvent') then
                htrack(bm.OnClientEvent:Connect(function(cmd, a2, a3, a4)
                    if cmd == 'Side' then
                        atkSide = a2; atkTurnAt = os.clock(); atkLastTry = -1e9; atkActed = false
                        stackSwallow = 0 -- a new turn: never hold a real QTE report from the last stack
                        if a2 == 'PartyMembers' and ((Toggles.FSAutoAttack and Toggles.FSAutoAttack.Value)
                           or (Toggles.FSStackAuto and Toggles.FSStackAuto.Value)) then
                            local s = myStamina()
                            pushStatus('attack', 'Your turn...' .. (s and (' (stamina ' .. s .. ')') or ''))
                        end
                    elseif cmd == 'Start' then
                        atkSide = a4; atkTurnAt = os.clock(); atkLastTry = -1e9; atkActed = false
                        stackSwallow = 0
                    elseif cmd == 'Stop' then
                        atkSide = nil
                        stackSwallow, stackPending = 0, 0
                    end
                end))
            end
            local eb = rem:FindFirstChild('EndBattle')
            if eb and eb:IsA('RemoteEvent') then
                htrack(eb.OnClientEvent:Connect(function()
                    atkSide = nil
                    stackSwallow, stackPending = 0, 0
                    if Toggles.FSAutoAttack and Toggles.FSAutoAttack.Value then pushStatus('attack', 'Battle over') end
                end))
            end
        end)
        task.delay(3, function() pcall(refreshMoves, true) end) -- seed the dropdown from your skills

        -- ==== ActionClient consumer (log + the non-Rewrite fallback modes) ==
        -- ActionClient(attacker, defender, move, options): defender is YOUR
        -- fighter model for direct hits, or the STRING "AoE" for area moves.
        -- Resolved with WaitForChild so injecting before ReplicatedStorage
        -- finishes replicating (auto-execute) can't leave the module dead.
        task.spawn(function()
            local rem = RepStorage:FindFirstChild('Remotes') or RepStorage:WaitForChild('Remotes', 60)
            local ac = rem and (rem:FindFirstChild('ActionClient') or rem:WaitForChild('ActionClient', 60))
            if not ac then
                Library:Notify('FS: Remotes.ActionClient never appeared (60s) - injected in the wrong place? Rewrite still works.', 8)
                return
            end
            htrack(ac.OnClientEvent:Connect(function(attacker, defender, move, options)
                local mine = isMe(attacker)
                if Toggles.FSLogCombat and Toggles.FSLogCombat.Value then
                    print(('[FS action] attacker=%s defender=%s move=%s side=%s%s'):format(
                        typeof(attacker) == 'Instance' and attacker.Name or tostring(attacker),
                        typeof(defender) == 'Instance' and defender.Name or tostring(defender),
                        tostring(move), tostring(options and options.Side),
                        mine and '  <MINE>' or (targetsMe(attacker, defender) and '  <ON ME>' or '')))
                end
                if mine then
                    atkActed = true -- my action registered: don't auto-attack again this turn
                    -- MY attack. Instant-fire QTE mode only; Rewrite mode does its
                    -- work when the QTE module's own send passes the hook. (defender
                    -- may be an enemy, the "AoE" string, or nil for Rest - any
                    -- non-nil target means a real attack.)
                    if defender ~= nil and Toggles.AutoQTE and Toggles.AutoQTE.Value and not qteRewriteOn() and not stackHolding() then
                        local qd = (Options.QTEFireDelay and Options.QTEFireDelay.Value) or 0
                        local fq = function()
                            if Toggles.AutoQTE and Toggles.AutoQTE.Value and fireQte() then
                                pushStatus('qte', 'QTE fired for ' .. tostring(move))
                            end
                        end
                        if qd > 0 then task.delay(qd, fq) else fq() end
                    end
                    return
                end
                -- Enemy attack aimed at me: direct/simulate fallback modes only.
                if not (Toggles.FSAutoParry and Toggles.FSAutoParry.Value) then return end
                if parryRewriteOn() then return end -- Rewrite handles it at send time
                if not targetsMe(attacker, defender) then return end
                local d = (Options.FSParryDelay and Options.FSParryDelay.Value) or 0
                local go = function()
                    if Toggles.FSAutoParry and Toggles.FSAutoParry.Value
                       and defend(attacker, defender, move, options) then
                        pushStatus('parry', 'Sent ' .. requiredAction(move) .. ' for ' .. tostring(move))
                    end
                end
                if d > 0 then task.delay(d, go) else go() end
            end))
        end)

        -- StartMinigame (server -> client QTE opener). In Rewrite mode nothing to
        -- do - whatever opens the QTE, the module's own QteResult send is what we
        -- rewrite. In Instant mode, fire the grade when a QTE opens.
        task.spawn(function()
            -- findRemote is class-checked: a same-named ModuleScript/Folder deeper
            -- in ReplicatedStorage can't shadow the real Remotes.StartMinigame.
            local sm = findRemote('StartMinigame')
            if not sm then
                local rem = RepStorage:FindFirstChild('Remotes') or RepStorage:WaitForChild('Remotes', 60)
                sm = rem and rem:WaitForChild('StartMinigame', 60)
            end
            if not (sm and sm:IsA('RemoteEvent')) then return end
            htrack(sm.OnClientEvent:Connect(function(qteName)
                if Toggles.FSLogCombat and Toggles.FSLogCombat.Value then print('[FS qte] StartMinigame <- ' .. tostring(qteName)) end
                if tostring(qteName) == 'Mining' then
                    -- 1-click break arms on ANY mining open (manual play included);
                    -- Auto-click mode additionally sweeps the grid with real clicks.
                    if (Toggles.FSMineOneClick and Toggles.FSMineOneClick.Value) or mineAutoClickOn() then
                        task.spawn(autoMineRun)
                    end
                    -- Auto Scavenge, Instant mode: fire the loot table ourselves
                    -- after the "pretend to mine" delay. (Rewrite mode does nothing
                    -- here - the hook fills the module's own table at its timeout.)
                    if mineInstantOn() then
                        local d = (Options.FSMineDelay and Options.FSMineDelay.Value) or 5
                        pushStatus('mine', ('Mining node - loot fires in %.1fs'):format(d))
                        task.delay(d, function()
                            if not mineInstantOn() then return end
                            local r = findRemote('QteResult'); if not r then return end
                            local loot = buildMineLoot()
                            mineFiredAt = os.clock()
                            if pcall(function() r:FireServer(loot) end) then
                                pushStatus('mine', 'Scavenged: ' .. lootString(loot))
                            end
                        end)
                    end
                    return -- NEVER send a grade string to a table minigame
                end
                if Toggles.AutoQTE and Toggles.AutoQTE.Value and not qteRewriteOn() and not stackHolding() then
                    if fireQte() then pushStatus('qte', 'QTE fired: ' .. tostring(qteName)) end
                end
            end))
        end)

        -- Optional continuous QTE spam (Instant mode only - Rewrite never needs it).
        local qteAccum = 0
        htrack(RunService.Heartbeat:Connect(function(dt)
            if qteRewriteOn() or stackHolding()
               or not (Toggles.AutoQTE and Toggles.AutoQTE.Value and Toggles.QTEContinuous and Toggles.QTEContinuous.Value) then
                qteAccum = 0; return
            end
            qteAccum = qteAccum + dt
            if qteAccum < ((Options.QTEInterval and Options.QTEInterval.Value) or 0.25) then return end
            qteAccum = 0; fireQte()
        end))

        -- Diagnostic: log every OTHER incoming Remotes client event (recursive +
        -- remotes that stream in later, so it works even when combat loads late).
        task.spawn(function()
            local rem = RepStorage:FindFirstChild('Remotes') or RepStorage:WaitForChild('Remotes', 60)
            if not rem then return end
            local skip = { ActionClient = true, StartMinigame = true } -- logged by their own handlers
            local function watch(r)
                if not (r:IsA('RemoteEvent') and not skip[r.Name]) then return end
                htrack(r.OnClientEvent:Connect(function(...)
                    if not (Toggles.FSLogCombat and Toggles.FSLogCombat.Value) then return end
                    local parts = {}
                    for i = 1, select('#', ...) do
                        local v = select(i, ...)
                        parts[i] = (typeof(v) == 'Instance') and (v.ClassName .. ':' .. v.Name) or tostring(v)
                    end
                    print(('[FS in] %s <- %s'):format(r.Name, table.concat(parts, ', ')))
                end))
            end
            for _, r in ipairs(rem:GetDescendants()) do watch(r) end
            htrack(rem.DescendantAdded:Connect(watch))
        end)

        if Toggles.AutoQTE then Toggles.AutoQTE:OnChanged(function()
            if QteStatus then QteStatus:SetText(Toggles.AutoQTE.Value and 'Auto QTE ON' or 'Idle') end
        end) end
        if Toggles.FSAutoParry then Toggles.FSAutoParry:OnChanged(function()
            if ParryStatus then ParryStatus:SetText(Toggles.FSAutoParry.Value and 'Auto parry/dodge ON' or 'Idle') end
        end) end
        if Toggles.FSAutoAttack then Toggles.FSAutoAttack:OnChanged(function()
            if AttackStatus then AttackStatus:SetText(Toggles.FSAutoAttack.Value and 'Auto attack ON' or 'Idle') end
            if Toggles.FSAutoAttack.Value and refreshMoves then refreshMoves(true) end -- re-pull your skills on enable
        end) end
    elseif HUB_CURRENT == 'slayers' then
        -- ===== SLAYERS (Demon-Slayer-style) ================================
        -- Built from the decompiled Slayers source (roguecopy/SlayersSRC). The
        -- facts that shape it:
        --  * Networking = ReplicatedStorage.RemotePlus. Client sends are CACHED
        --    direct calls: Signals.SignalEvent.Event:FireServer("<Name>", ...),
        --    so a FireServer hookfunction (not __namecall) sees game traffic.
        --  * No client anti-cheat. Server tripwire: casting a skill your loadout
        --    doesn't have = BanActions.Tier1 (Skills_Module.SourceCheck). So this
        --    module NEVER sends skill names; M1 / block / dash all go through
        --    the game's own input paths (InputHandler / keys / Dash_Handler).
        --  * Mobs are server-owned (isnetworkowner = false) -> no freeze-style
        --    AI breaker. The mob farm instead sits ABOVE the mob: the server M1
        --    hitbox (Combat_presets.Get_Players_For_Combat) is a 6.25-stud-tall
        --    box centred 1 stud under the attacker's root, so the mob's swing
        --    can't reach up while yours reaches ~4 studs down onto its head.
        -- Every feature is its own IIFE so no single function nears Luau's
        -- 200-local register cap.
        (function()
            local Players     = game:GetService('Players')
            local LP          = Players.LocalPlayer
            local CS          = game:GetService('CollectionService')
            local VIM         = game:GetService('VirtualInputManager')
            local HttpService = game:GetService('HttpService')
            local S = { noclipWhy = {}, dropRules = {}, farmLocked = false, dead = false }
            htrack({ Disconnect = function() S.dead = true end }) -- stops our while-loops on unload

            -- ---- shared helpers ---------------------------------------------
            function S.root() local c = LP.Character; return c and c:FindFirstChild('HumanoidRootPart') end
            function S.hum() local c = LP.Character; return c and c:FindFirstChildOfClass('Humanoid') end
            -- 'A.B.C' under ReplicatedStorage (names may contain spaces).
            function S.find(path)
                local node = RepStorage
                for part in path:gmatch('[^%.]+') do node = node and node:FindFirstChild(part) end
                return node
            end
            local modCache = {}
            function S.req(path) -- require a game module (cached only on success)
                if modCache[path] then return modCache[path] end
                local inst = S.find(path)
                if not (inst and inst:IsA('ModuleScript')) then return nil end
                local ok, m = pcall(require, inst)
                if ok and m ~= nil then modCache[path] = m; return m end
                return nil
            end
            local remCache = {}
            function S.remote(path, child)
                local key = path .. '/' .. child
                local r = remCache[key]
                if r and r.Parent then return r end
                local p = S.find(path)
                r = p and p:FindFirstChild(child)
                remCache[key] = r
                return r
            end
            local SIG_EVENT = 'Communication.ServerAndClient.Signals.SignalEvent'
            local SIG_FUNC  = 'Communication.ServerAndClient.Signals.SignalFunction'
            local PORTAL    = 'CAM.Global.ServerClientPortal'
            local EFFECTS   = 'Communication.ServerAndClient.Effects.EffectsEvent'
            S.PORTAL, S.EFFECTS = PORTAL, EFFECTS
            -- Same wire format as the game's SignalEvent.ToServer(name, ...).
            function S.fire(name, ...)
                local r = S.remote(SIG_EVENT, 'Event'); if not r then return false end
                return (pcall(r.FireServer, r, name, ...))
            end
            function S.invoke(name, ...)
                local r = S.remote(SIG_FUNC, 'Function'); if not r then return false, 'SignalFunction missing' end
                return pcall(r.InvokeServer, r, name, ...)
            end
            function S.portal(name, ...)
                local r = S.remote(PORTAL, 'Event'); if not r then return false end
                return (pcall(r.FireServer, r, name, ...))
            end
            function S.values() -- ReplicatedStorage.Player_Service.Values.<me> (live stun/stamina/training)
                local ps = RepStorage:FindFirstChild('Player_Service'); local v = ps and ps:FindFirstChild('Values')
                return v and v:FindFirstChild(LP.Name)
            end
            function S.data() -- current save slot folder, account root (Utility.GetData)
                local ps = RepStorage:FindFirstChild('Player_Service'); local d = ps and ps:FindFirstChild('Data')
                local root = d and d:FindFirstChild(LP.Name)
                local se = root and root:FindFirstChild('slotEquipped')
                local slots = root and root:FindFirstChild('slots')
                return (se and slots and slots:FindFirstChild('Slot' .. tostring(se.Value))) or nil, root
            end
            function S.val(parent, ...) -- nil-safe nested FindFirstChild -> .Value
                local node = parent
                for _, n in ipairs({ ... }) do node = node and node:FindFirstChild(n) end
                if node and node:IsA('ValueBase') then return node.Value end
                return nil
            end
            function S.fmt(sec)
                sec = math.max(0, math.floor(sec + 0.5))
                if sec >= 3600 then return ('%dh%02dm'):format(math.floor(sec / 3600), math.floor((sec % 3600) / 60)) end
                return ('%d:%02d'):format(math.floor(sec / 60), sec % 60)
            end
            -- UI writes from our worker threads: Volt can resume a thread without the
            -- capability to touch the protected hub GUI ("lacking capability Plugin"),
            -- which used to kill Auto Quest mid-accept. Re-raise identity first and
            -- never let a UI write throw.
            local setIdentity = setthreadidentity or set_thread_identity or (syn and syn.set_thread_identity)
            function S.ui() if setIdentity then pcall(setIdentity, 8) end end
            function S.setText(lbl, t) S.ui(); pcall(lbl.SetText, lbl, t) end
            -- Animation classifier. Replicated tracks are all named "Animation", so
            -- match by AnimationId against the game's own folders (built once):
            --   ReplicatedStorage.Skills.<style>.<skill>...  -> 'skill' (+ skill name)
            --   ReplicatedStorage.Assets.Animations.*_Combat_Anims.Swing_N / Run_Hit -> 'swing'
            --   anything else under Assets.Animations (react/block/dash/jump/...) -> 'basic'
            --   not found anywhere -> 'unknown' (boss-only moves, new content)
            local animMap
            local function buildAnimMap()
                animMap = {}
                local function idOf(a) return tostring(a.AnimationId):match('%d+') end
                local sk = RepStorage:FindFirstChild('Skills')
                if sk then
                    for _, style in ipairs(sk:GetChildren()) do
                        for _, skill in ipairs(style:GetChildren()) do
                            for _, a in ipairs(skill:GetDescendants()) do
                                if a:IsA('Animation') then
                                    local id = idOf(a)
                                    if id then animMap[id] = { kind = 'skill', skill = skill.Name, phase = a.Name } end
                                end
                            end
                        end
                    end
                end
                local assets = RepStorage:FindFirstChild('Assets')
                local anims = assets and assets:FindFirstChild('Animations')
                if anims then
                    for _, a in ipairs(anims:GetDescendants()) do
                        if a:IsA('Animation') then
                            local id = idOf(a)
                            if id and not animMap[id] then
                                local swing = (a.Name:match('^Swing_%d') or a.Name == 'Run_Hit')
                                    and a.Parent and a.Parent.Name:find('Combat_Anims') ~= nil
                                animMap[id] = { kind = swing and 'swing' or 'basic', phase = a.Name,
                                    skill = a.Parent and a.Parent.Name or '?' }
                            end
                        end
                    end
                end
            end
            function S.animInfo(track)
                if not animMap then buildAnimMap() end
                local a = track and track.Animation
                local id = a and tostring(a.AnimationId):match('%d+')
                return (id and animMap[id]) or { kind = 'unknown', phase = a and a.Name or '?', skill = '?' }, id
            end
            -- Per-model connection lifetime: everything bound to a model is dropped the
            -- moment it leaves the game (mob died / streamed out), so long farm sessions
            -- don't pile up dead connections. Whatever is still bound goes on unload.
            local lifeConns = {}
            function S.bindLife(model, conn)
                local list = lifeConns[model]
                if not list then
                    list = {}
                    lifeConns[model] = list
                    list[1] = model.AncestryChanged:Connect(function()
                        if model:IsDescendantOf(game) then return end
                        for _, c in ipairs(lifeConns[model] or {}) do pcall(function() c:Disconnect() end) end
                        lifeConns[model] = nil
                    end)
                end
                list[#list + 1] = conn
                return conn
            end
            htrack({ Disconnect = function()
                for _, list in pairs(lifeConns) do for _, c in ipairs(list) do pcall(function() c:Disconnect() end) end end
                lifeConns = {}
            end })
            -- ---- M1 data straight from CAM.Global.Combat_presets (+ MorePresets) -----
            local function presetIdx(t, i) return type(t) == 'table' and (t[i] or t.Default) or nil end
            -- Preset for a swing: the anim folder names the weapon ("Axe and Mace_Combat_Anims"
            -- -> Presets["Axe and Mace"]); falls back to the attacker's equipped tool.
            function S.swingPreset(model, info)
                local CPm = S.req('CAM.Global.Combat_presets')
                local P = CPm and type(CPm.Presets) == 'table' and CPm.Presets
                if not P then return nil end
                local weapon = info and tostring(info.skill or ''):match('^(.-)_Combat_Anims$')
                if weapon and P[weapon] then return P[weapon], weapon end
                -- No anim-folder hint: the attacker's own normalised preset (S.m1Preset:
                -- NpcMimicFolder.Equipped_Tool for mobs - CIP.Get_equipped_tool returns nil for
                -- every NPC - so "Cutlass" -> Regular Katana and "Blood Sickles" -> Sickles
                -- instead of silently falling back to Combat).
                if S.m1Preset then
                    local p, n = S.m1Preset(model)
                    if p then return p, n end
                end
                return P.Combat, 'Combat'
            end
            -- Seconds from swing-anim start to the server hit check. Same maths as the
            -- game's Main_Combat_Script_Client: the _Swings cue fires at before_swing, the
            -- server hit lands (before_hit - run_remove) after the anim starts.
            function S.swingTiming(preset, combo, run)
                local CPm = S.req('CAM.Global.Combat_presets')
                if run and preset and preset.CombatRunHit and CPm then preset = CPm.Presets.Combat end
                if not preset then return 0.2, 0.15 end
                local bs = (type(preset.delay_before_swing) == 'table' and preset.delay_before_swing[combo])
                    or preset.default_before_swing or (CPm and CPm.Default_Swing_Wait) or 0.15
                local bh = (type(preset.delay_before_hit) == 'table' and preset.delay_before_hit[combo])
                    or preset.default_before_hit or bs
                local rr = (run and combo == 1 and preset.run_swing_remove_on_first) or 0
                return math.max(bs, bh - rr), bs
            end
            -- The server's M1 box (Get_Players_For_Combat) -> CFrame, Size. npc = the /1.2 shrink.
            function S.m1Box(root, preset, idx, npc)
                preset = preset or {}
                local u1 = preset.MinHitboxSize or 0
                local r = presetIdx(preset.Reaches, idx); if r then u1 = u1 + r end
                local vel = root.AssemblyLinearVelocity
                local m = math.clamp(vel.Magnitude / 5, 0, 13)
                m = (m <= 5) and m / 2 or m
                local v = (vel.Magnitude > 0.01) and (vel.Unit * m) or Vector3.zero
                v = Vector3.new(v.X, 0, v.Z) * 1.25
                if v.Magnitude <= 1 or v.Magnitude > 100 then v = root.CFrame.LookVector end
                local dir = Vector3.new(v.X, 0, v.Z)
                dir = dir.Magnitude > 0.01 and dir.Unit or Vector3.new(0, 0, -1)
                local ext = math.min(v.Magnitude, 7)
                if u1 < 0 then ext = math.max(ext + u1, 1) else ext = math.max(u1, ext) end
                local base = root.CFrame * CFrame.new(0, -1, 0)
                local yo = presetIdx(preset.YOffsets, idx); if yo then base = base * CFrame.new(0, yo, 0) end
                local addW, addD = 0, 0
                if idx == 7 then addW, addD = 4, 7 end
                local w = presetIdx(preset.Widths, idx) or 0
                local dp = presetIdx(preset.Depths, idx) or 0
                local scale = npc and (1 / 1.2) or 1
                local size = Vector3.new(addW + 6 + w, w + 6.25, math.max(addD + 9 + dp, 1)) * scale + Vector3.new(0, 0, ext)
                local p = base.Position
                local cf = CFrame.lookAt(p, p + dir) * CFrame.new(0, 0, -ext * 0.75)
                local zo = presetIdx(preset.ZOffsets, idx); if zo then cf = cf * CFrame.new(0, 0, -zo) end
                return cf, size
            end
            -- ---- M1 preset + vertical box maths (farm head height, Auto Parry reach, viewer) ----
            -- Preset name -> preset, normalised like the game's own M1 punch() (CU/Combat.lua:91-138):
            -- Presets[v]; else an item with a CombatPreset / HasCombat / Breathing swings
            -- Presets[CombatPreset or 'Regular Katana']; anything else (plain item, unknown
            -- name, no value) = bare Combat.
            function S.m1PresetNamed(v)
                local CPm = S.req('CAM.Global.Combat_presets')
                local P = CPm and type(CPm.Presets) == 'table' and CPm.Presets
                if not P then return nil, nil end
                if type(v) ~= 'string' or v == '' then return P.Combat, 'Combat' end
                if P[v] then return P[v], v end
                local Items = S.req('CAM.Global.Collectibles.Items')
                local ok, it = pcall(function() return Items and Items[v] end)
                if ok and type(it) == 'table' and (it.CombatPreset ~= nil or it.HasCombat or it.Breathing ~= nil) then
                    local n = (type(it.CombatPreset) == 'string' and it.CombatPreset) or 'Regular Katana'
                    if P[n] then return P[n], n end
                end
                return P.Combat, 'Combat'
            end
            -- The preset an attacker's server M1 box is built from. Mobs: the model's
            -- AiPrerequistes.NpcMimicFolder.Equipped_Tool ("Bear", "Cutlass", "Blood Sickles",
            -- "Obi Manipulation"...), read straight off the model: CIP.Get_equipped_tool always
            -- returns nil for NPCs (it hands AiMimic:Get a nil model; Character_info_provider.lua
            -- 22-27, AiMimic.lua 9-11). Every AiPrerequistes child is scanned defensively.
            -- Us: get_equipped_Combat (CU/Combat.lua:9-42) - the Toolbar item when it has its own
            -- CombatPreset, else the first Skills_Provider.CurPower style that has an
            -- Assets.Animations["<style>_Combat_Anims"] folder, else the item / bare Combat.
            -- Other players: their equipped item (their CurPower is not replicated to us).
            function S.m1Preset(who)
                if typeof(who) ~= 'Instance' then return S.m1PresetNamed(nil) end
                local plr = (who:IsA('Player') and who) or Players:GetPlayerFromCharacter(who)
                if not plr then
                    for _, ch in ipairs(who:GetChildren()) do
                        if ch.Name == 'AiPrerequistes' then
                            local f = ch:FindFirstChild('NpcMimicFolder')
                            local e = f and f:FindFirstChild('Equipped_Tool')
                            if e and e:IsA('ValueBase') and e.Value ~= nil and tostring(e.Value) ~= '' then
                                return S.m1PresetNamed(tostring(e.Value))
                            end
                        end
                    end
                    return S.m1PresetNamed(nil)
                end
                local nm
                local CIP = S.req('CAM.Global.Character_info_provider')
                if CIP and CIP.Get_equipped_tool then
                    local ok, n = pcall(function()
                        local t = CIP.Get_equipped_tool(plr)
                        return t and t.Name
                    end)
                    if ok and type(n) == 'string' and n ~= '' then nm = n end
                end
                if plr == LP then
                    local Items = S.req('CAM.Global.Collectibles.Items')
                    local ok, it = pcall(function() return nm and Items and Items[nm] end)
                    local cp = ok and type(it) == 'table' and it.CombatPreset or nil
                    if cp == nil or cp == 'Combat' then
                        -- the game's own test (Combat.lua:24-29): a style swings only if its anim
                        -- folder exists. Presets alone can't tell - Combat_presets.lua:163-167 adds
                        -- EVERY FightingStyles key to Presets (aliased to Combat).
                        local cur = S.find('CAM.Client.Controllers.Skills_Provider.CurPower')
                        local anims = S.find('Assets.Animations')
                        if cur and cur:IsA('StringValue') and anims then
                            for p in cur.Value:gmatch('[^,]+') do
                                if anims:FindFirstChild(p .. '_Combat_Anims') then return S.m1PresetNamed(p) end
                            end
                        end
                    end
                end
                return S.m1PresetNamed(nm)
            end
            -- Vertical span of an M1 box over EVERY combo hit 1..Max (Get_Players_For_Combat:
            -- centre root -1 (+YOffsets[i]), height 6.25 + Widths[i]; Combat_presets.lua:403-427),
            -- relative to the attacker's root. which = 'top': the highest top (a mob's worst reach
            -- UP); 'bottom': the highest bottom (OUR shallowest reach down, so every hit lands).
            function S.m1BoxSpan(preset, which)
                local best
                for i = 1, math.max(1, (preset and tonumber(preset.Max)) or 7) do
                    local c = -1 + ((preset and presetIdx(preset.YOffsets, i)) or 0)
                    local h = (6.25 + ((preset and presetIdx(preset.Widths, i)) or 0)) / 2
                    local v = (which == 'bottom') and (c - h) or (c + h)
                    if not best or v > best then best = v end
                end
                return best or ((which == 'bottom') and -4.125 or 2.125)
            end
            function S.mobBoxTop(model) return S.m1BoxSpan((S.m1Preset(model)), 'top') end
            -- Our root centre -> feet (R15: HipHeight + half the root; R6: legs hang 2 studs
            -- under the torso). ONE number for the farm's head height AND Auto Parry's reach test.
            function S.m1Legs()
                local hum, root = S.hum(), S.root()
                local half = root and root.Size.Y / 2 or 1
                if hum and hum.RigType == Enum.HumanoidRigType.R6 then return half + 2 end
                return (hum and hum.HipHeight or 2) + half
            end
            -- Highest point of a model's DIRECT-CHILD BaseParts above its root. That is all the
            -- server's box query sees (Utility.GetModelInRegion keeps a part only when its Parent
            -- is the Humanoid model: hats, weapon models, hair folders never count), unlike
            -- GetBoundingBox. CanQuery=false parts are invisible to GetPartBoundsInBox as well.
            function S.bodyTop(model, root)
                root = root or model:FindFirstChild('HumanoidRootPart')
                if not root then return nil end
                local top
                for _, p in ipairs(model:GetChildren()) do
                    if p:IsA('BasePart') and p.CanQuery then
                        local cf, sz = p.CFrame, p.Size
                        local t = cf.Position.Y + (math.abs(cf.RightVector.Y) * sz.X + math.abs(cf.UpVector.Y) * sz.Y
                            + math.abs(cf.LookVector.Y) * sz.Z) / 2
                        if not top or t > top then top = t end
                    end
                end
                return top and (top - root.Position.Y) or nil
            end
            S.FARM_CLEAR = 0.15 -- the farm parks our feet this far above a mob's worst box top (+ Height tweak)
            function S.pingSec()
                local ok, ms = pcall(function() return game:GetService('Stats').Network.ServerStatsItem['Data Ping']:GetValue() end)
                if not (ok and ms) then ok, ms = pcall(function() return LP:GetNetworkPing() * 2000 end) end
                return (ok and tonumber(ms) or 0) / 1000
            end
            function S.posOf(inst) -- world position of a part / attachment / model
                if not inst then return nil end
                if inst:IsA('BasePart') then return inst.Position end
                if inst:IsA('Attachment') then return inst.WorldPosition end
                if inst:IsA('Model') then
                    local r = inst:FindFirstChild('HumanoidRootPart') or inst.PrimaryPart
                    if r then return r.Position end
                    local ok, cf = pcall(inst.GetPivot, inst); if ok then return cf.Position end
                end
                return nil
            end
            -- Hostile mobs = Models tagged IsMob inside workspace.Humanoids.Regions.
            -- <Region>.ActiveNpcs.<slot folder>; a slot with a BossInfo config = boss.
            function S.mobs()
                local out = {}
                local hs = workspace:FindFirstChild('Humanoids')
                local regs = hs and hs:FindFirstChild('Regions')
                if not regs then return out end
                for _, region in ipairs(regs:GetChildren()) do
                    local act = region:FindFirstChild('ActiveNpcs')
                    if act then
                        for _, slot in ipairs(act:GetChildren()) do
                            local boss = slot:FindFirstChild('BossInfo') ~= nil
                            for _, m in ipairs(slot:GetChildren()) do
                                if m:IsA('Model') and m:GetAttribute('IsMob') then
                                    local hum = m:FindFirstChildOfClass('Humanoid')
                                    local root = m:FindFirstChild('HumanoidRootPart')
                                    if hum and root and hum.Health > 0 then
                                        out[#out + 1] = {
                                            model = m, slot = slot, hum = hum, root = root, name = slot.Name, boss = boss,
                                            civ = slot.Name:find('Civilian') ~= nil or m:GetAttribute('CivilianState') ~= nil,
                                        }
                                    end
                                end
                            end
                        end
                    end
                end
                return out
            end
            -- Noclip while any feature asks for it (Stepped so CanCollide sticks).
            function S.noclip(why, on) S.noclipWhy[why] = on or nil end
            local noclipped = setmetatable({}, { __mode = 'k' })
            htrack(RunService.Stepped:Connect(function()
                if next(S.noclipWhy) == nil then
                    if next(noclipped) ~= nil then
                        for p in pairs(noclipped) do
                            if p.Parent then pcall(function() p.CanCollide = true end) end
                            noclipped[p] = nil
                        end
                    end
                    return
                end
                local c = LP.Character; if not c then return end
                for _, p in ipairs(c:GetDescendants()) do
                    if p:IsA('BasePart') and p.CanCollide then p.CanCollide = false; noclipped[p] = true end
                end
            end))
            -- Bounded-speed glide (continuous movement like the game's own client
            -- PivotTo teleports; far safer than one huge jump). New glide cancels old.
            local glideGen = 0
            function S.stopGlide() glideGen = glideGen + 1; S.noclip('glide', false) end
            function S.glideTo(pos, speed, label)
                if not S.root() then Library:Notify('No character', 2); return end
                glideGen = glideGen + 1
                local gen = glideGen
                S.noclip('glide', true)
                task.spawn(function() pcall(function() LP:RequestStreamAroundAsync(pos, 5) end) end)
                task.spawn(function()
                    local t0 = os.clock()
                    local yielded = false
                    while glideGen == gen and os.clock() - t0 < 240 do
                        local dt = RunService.Heartbeat:Wait()
                        if glideGen ~= gen then break end
                        -- The Mob farm pins the root on RenderStepped once it has a target; a glide
                        -- still running on Heartbeat (quest camp trip, farm return, a Travel click)
                        -- wrote LAST every frame and dragged us off the mob's head. The farm wins:
                        -- this glide ends the moment it has a target (a paused farm has none).
                        if S.farmHasTarget and not S.farmPaused then yielded = true; break end
                        local r = S.root()
                        if r then
                            local delta = pos - r.Position
                            local d = delta.Magnitude
                            local rot = r.CFrame - r.Position
                            if d <= 2 then r.CFrame = CFrame.new(pos) * rot; r.AssemblyLinearVelocity = Vector3.zero; break end
                            local step = math.min(d, (speed or (Options.SLTPSpeed and Options.SLTPSpeed.Value) or 120) * dt)
                            r.CFrame = CFrame.new(r.Position + delta.Unit * step) * rot
                            r.AssemblyLinearVelocity = Vector3.zero
                        end
                    end
                    if glideGen == gen then
                        S.noclip('glide', false)
                        if label then
                            S.ui() -- worker thread: re-raise identity before touching the hub GUI
                            if yielded then pcall(Library.Notify, Library, 'Glide to ' .. label .. ' stopped - Mob farm has a target', 3)
                            else pcall(Library.Notify, Library, 'Arrived: ' .. label, 2) end
                        end
                    end
                end)
            end
            -- One FireServer hook (the game's sends are cached direct calls, so
            -- __namecall never sees them). Features push drop-rules into
            -- S.dropRules; our own sends pass checkcaller and are never touched.
            do
                local hookfn  = hookfunction or replaceclosure
                local canCall = checkcaller or function() return false end
                local wrap    = newcclosure or function(f) return f end
                if hookfn then
                    local fireRef = Instance.new('RemoteEvent').FireServer
                    local old
                    local ok = pcall(function()
                        old = hookfn(fireRef, wrap(function(self, ...)
                            if old and #S.dropRules > 0 and not canCall() and typeof(self) == 'Instance' and self.Name == 'Event' then
                                local a1, a2, a3 = ...
                                for _, rule in ipairs(S.dropRules) do
                                    local okR, drop = pcall(rule, a1, a2, a3)
                                    if okR and drop then return end
                                end
                            end
                            return old(self, ...)
                        end))
                    end)
                    if ok and old then
                        htrack({ Disconnect = function() pcall(hookfn, fireRef, old) end })
                    else
                        Library:Notify('Slayers: FireServer hook failed - No drown / auto-train report filtering disabled', 6)
                    end
                end
            end
            local IH = S.req('CAM.Client.Components.Client.InputHandler') -- the game's input API
            -- ---- Kill-aura target counting (shared by every kill-aura feature) --
            -- count, players, mobs, bosses, civs, perfect = S.kaTargetsInBox(cf, size, kind)
            -- Same query every server hitbox runs: Utility.GetModelInRegion
            -- (RS/CAM/Global/Utility.lua:1216) = workspace:GetPartBoundsInBox over
            -- workspace.Humanoids (RaycastHelper.lua:34-44: Include, MaxParts 350);
            -- a part counts for its PARENT Model, which must have a PrimaryPart.
            -- Player characters live in workspace.Humanoids too and check_victim only
            -- spares them in a Safezone / Lair / minigame / party (Checker.lua:856-891),
            -- so every skill box CAN hit players - callers must keep them out.
            --   count   = #mobs: live IsMob models touched that the hit is not wasted
            --             on (civilians left out; BossInfo trainees DO count)
            --   players = OTHER players touched: root inside the box grown by a body's
            --             half size (works whether or not characters live under
            --             workspace.Humanoids) + other players' clones (Clone_Owner)
            --   mobs    = array of the counted mob Models; bosses = how many of them
            --             sit in a slot with BossInfo (weight them yourself)
            --   civs    = civilians touched (never in count)
            --   perfect = touched mobs holding Blocking.Perfect: a Perfect hit makes the
            --             skill's hitDetected return true (e.g. Flame TigerServer.lua:84-86)
            --             and Utility.ProcessHitboxTargets stops its target loop on a true
            --             return (Utility.lua:832-884), so the rest of the box is wasted
            --   kind    = nil (alive only) | 'm1' | 'skill' -> S.kaHittable filter
            -- S.kaHittable(model, kind) -> false when Checker.check_victim would waste
            --   the hit (Checker.lua:816-1123; a mob's values folder = the mob Model):
            --   iframe (StatsFetch.GetIFrame / iframe child / SHCS iframe skill),
            --   NpcCounter attr (1 = counters M1, 3 = counters skills, 2 = both) and
            --   StatsFetch.GetCounter (armed Counter StringValue or live skill counter,
            --   same 1/2/3 types) - two SEPARATE checks on the server (:938-966 then
            --   :974-1003), so either one can waste the hit; Dodge IntValue (M1 always;
            --   skills unless Mode == 'Combat', :1010-1019); Blocking.Perfect.
            --   Results are cached per model for 0.1s (callers query many boxes a tick).
            -- S.kaPlayersInBox(cf, size) -> other players whose root is inside (no query).
            -- S.kaPlayersNear(pos, radius) -> n, nearest: other players' roots + their
            --   Clone_Owner models among workspace.Humanoids' children within radius.
            ;(function()
                local params = OverlapParams.new()
                params.FilterType = Enum.RaycastFilterType.Include
                params.MaxParts = 350 -- the server's own cap (RaycastHelper.Humanoids)
                local SF
                local function sf()
                    SF = SF or S.req('CAM.Global.Subsets.Gameplay.StatsFetch')
                    return SF
                end
                local function playersIn(cf, size, set)
                    local hx, hy, hz = size.X / 2 + 2.5, size.Y / 2 + 3.5, size.Z / 2 + 2.5
                    for _, p in ipairs(Players:GetPlayers()) do
                        local c = p ~= LP and p.Character
                        local r = c and (c:FindFirstChild('HumanoidRootPart') or c.PrimaryPart)
                        if r then
                            local lp = cf:PointToObjectSpace(r.Position)
                            if math.abs(lp.X) <= hx and math.abs(lp.Y) <= hy and math.abs(lp.Z) <= hz then set[p] = true end
                        end
                    end
                end
                function S.kaPlayersInBox(cf, size)
                    local set, n = {}, 0
                    playersIn(cf, size, set)
                    for _ in pairs(set) do n = n + 1 end
                    return n
                end
                local function cloneOwner(m) -- another player's summon / clone: hitting it is PvP
                    local own = m:FindFirstChild('Clone_Owner')
                    if own and own:IsA('StringValue') and own.Value ~= '' and own.Value ~= LP.Name then
                        return Players:FindFirstChild(own.Value)
                    end
                    return nil
                end
                function S.kaPlayersNear(pos, radius)
                    local n, nearest = 0, math.huge
                    local function consider(r)
                        local d = (r.Position - pos).Magnitude
                        if d <= radius then n = n + 1 end
                        if d < nearest then nearest = d end
                    end
                    for _, p in ipairs(Players:GetPlayers()) do
                        local c = p ~= LP and p.Character
                        local r = c and (c:FindFirstChild('HumanoidRootPart') or c.PrimaryPart)
                        if r then consider(r) end
                    end
                    local hs = workspace:FindFirstChild('Humanoids')
                    if hs then
                        for _, m in ipairs(hs:GetChildren()) do
                            if m:IsA('Model') and m ~= LP.Character and cloneOwner(m) then
                                local r = m:FindFirstChild('HumanoidRootPart') or m.PrimaryPart
                                if r then consider(r) end
                            end
                        end
                    end
                    return n, nearest
                end
                local function counters(ct, kind) -- Menum.CounterType {Combat=1, All=2, AllExceptCombat=3}
                    ct = tonumber(ct)
                    return ct == 2 or (kind == 'skill' and ct == 3) or (kind == 'm1' and ct == 1)
                end
                local function iframed(m)
                    local f = sf()
                    if f and f.GetIFrame then
                        local ok, fr = pcall(f.GetIFrame, m, LP.Character)
                        if ok and fr ~= nil then return true end
                    elseif m:FindFirstChild('iframe') or m:FindFirstChild('escapeiframe') then
                        return true
                    end
                    -- GetIFrame reads SHC on the client; a mob's live skill sits in SHCS
                    local sh = m:FindFirstChild('SHCS')
                    local st = f and f.SkillStats
                    if sh and sh:IsA('StringValue') and sh.Value ~= '' and st and st.Get then
                        local ok, s = pcall(st.Get, sh.Value)
                        if ok and type(s) == 'table' and s.iframe then return true end
                    end
                    return false
                end
                local hitCache = setmetatable({}, { __mode = 'k' }) -- [model] = { t = clock, [kind] = bool }
                local function hittable(m, kind)
                    local hum = m and m:FindFirstChildOfClass('Humanoid')
                    if not (hum and hum.Health > 0) then return false end
                    if not kind then return true end
                    local blk = m:FindFirstChild('Blocking')
                    if blk and blk:FindFirstChild('Perfect') and not m:FindFirstChild('PierceBlock') then return false end
                    if counters(m:GetAttribute('NpcCounter'), kind) then return false end -- server check 1
                    local f = sf()
                    if f and f.GetCounter then -- server check 2 (independent of the attribute)
                        local ok, t = pcall(f.GetCounter, m, m)
                        if ok and counters(t, kind) then return false end
                    end
                    local dg = m:FindFirstChild('Dodge')
                    if dg and dg:IsA('IntValue') and dg.Value > 0 and (kind == 'm1' or dg:GetAttribute('Mode') ~= 'Combat') then return false end
                    if iframed(m) then return false end
                    return true
                end
                function S.kaHittable(m, kind)
                    if not m then return false end
                    local key, now = kind or 'alive', os.clock()
                    local c = hitCache[m]
                    if c and now - c.t < 0.1 and c[key] ~= nil then return c[key] end
                    local r = hittable(m, kind)
                    if not c or now - c.t >= 0.1 then c = { t = now }; hitCache[m] = c end
                    c[key] = r
                    return r
                end
                function S.kaTargetsInBox(cf, size, kind)
                    local pset = {}
                    playersIn(cf, size, pset)
                    local mobs, bosses, civs, perfect = {}, 0, 0, 0
                    local hs = workspace:FindFirstChild('Humanoids')
                    local parts
                    if hs then
                        params.FilterDescendantsInstances = { hs }
                        local ok, res = pcall(workspace.GetPartBoundsInBox, workspace, cf, size, params)
                        parts = ok and res or nil
                    end
                    local seen, me = {}, LP.Character
                    for _, part in ipairs(parts or {}) do
                        local m = part.Parent
                        if m and not seen[m] and m ~= me and m:IsA('Model') and m.PrimaryPart ~= nil then
                            seen[m] = true
                            local owner = cloneOwner(m)
                            local plr = Players:GetPlayerFromCharacter(m)
                            if plr then
                                if plr ~= LP then pset[plr] = true end
                            elseif owner then
                                pset[owner] = true
                            elseif m:GetAttribute('IsMob') and S.kaHittable(m, nil) then
                                local blk = m:FindFirstChild('Blocking')
                                if blk and blk:FindFirstChild('Perfect') and not m:FindFirstChild('PierceBlock') then perfect = perfect + 1 end
                                local slot = m.Parent
                                local boss = slot ~= nil and slot:FindFirstChild('BossInfo') ~= nil
                                if (slot and slot.Name:find('Civilian')) or (m:GetAttribute('CivilianState') ~= nil and not boss) then
                                    civs = civs + 1
                                elseif S.kaHittable(m, kind) then
                                    mobs[#mobs + 1] = m
                                    if boss then bosses = bosses + 1 end
                                end
                            end
                        end
                    end
                    local players = 0
                    for _ in pairs(pset) do players = players + 1 end
                    return #mobs, players, mobs, bosses, civs, perfect
                end
            end)()

            local Tabs = {
                Farm    = Window:AddTab('Farm'),
                Combat  = Window:AddTab('Combat'),
                Visuals = Window:AddTab('Visuals'),
                Travel  = Window:AddTab('Travel'),
                Misc    = Window:AddTab('Misc'),
            }

            -- ================================================================
            -- MOB FARM: sit on the target's head + hold M1
            -- ================================================================
            ;(function()
                local box = Tabs.Farm:AddLeftGroupbox('Mob Farm')
                box:AddLabel('Sits on the target\'s head and holds M1. The mob\'s\nM1 hitbox only reaches ~2 studs above its root; yours\nreaches ~4 studs below you, so you hit and it whiffs.\nMob SKILLS can still land (mostly bosses).', true)
                local status = box:AddLabel('Idle')
                box:AddToggle('SLMobFarm', { Text = 'Mob farm', Default = false })
                    :AddKeyPicker('SLMobFarmKey', { Default = 'None', SyncToggleState = true, Mode = 'Toggle', Text = 'Mob farm' })
                box:AddDropdown('SLFarmTargets', { Values = {}, Default = {}, Multi = true, AllowNull = true, Text = 'Only these mobs',
                    Tooltip = 'Nothing ticked = any mob. "Refresh" lists the mob types loaded around you (the world streams, so far camps are not listed until you go near).' })
                box:AddButton({ Text = 'Refresh mob list', Func = function()
                    local seen, list = {}, {}
                    for _, m in ipairs(S.mobs()) do
                        if not seen[m.name] then seen[m.name] = true; list[#list + 1] = m.name end
                    end
                    table.sort(list)
                    Options.SLFarmTargets:SetValues(list)
                    Library:Notify(('%d mob type(s) loaded nearby'):format(#list), 2)
                end })
                box:AddDropdown('SLFarmPriority', { Values = { 'Nearest', 'Lowest HP' }, Default = 1, Multi = false, Text = 'Target priority' })
                box:AddSlider('SLFarmRange', { Text = 'Search range', Default = 200, Min = 30, Max = 600, Rounding = 0, Suffix = ' studs' })
                box:AddDropdown('SLFarmHeightMode', { Values = { 'Auto (hitbox math)', 'Model size', 'Manual' }, Default = 1, Multi = false, Text = 'Height mode',
                    Tooltip = 'Auto = per mob: just above the top of that mob M1 box (its weapon preset, highest combo), but low enough that YOUR box (your weapon, least-reaching combo) still reaches the top of its body. The body top counts its direct parts only (the server hit check ignores hats / accessories), so on accessory-heavy mobs Auto sits lower than it used to and may show [no safe gap]: it then sits low enough to keep hitting and the mob can reach you - keep Block when a mob attacks on. Model size = old mode (mob top + your legs). Manual = fixed height below.' })
                box:AddSlider('SLFarmTweak', { Text = 'Height tweak', Default = 0.3, Min = -5, Max = 3, Rounding = 1, Suffix = ' studs',
                    Tooltip = 'Added on top of the computed height. Raise if the mob still hits you; lower if YOUR hits stop landing. (Under the mob is worse: the M1 box sits 1 stud BELOW the attacker\'s root, so from below the mob out-reaches you.)' })
                box:AddSlider('SLFarmHeight', { Text = 'Manual height', Default = 5.8, Min = 0, Max = 12, Rounding = 1, Suffix = ' studs',
                    Tooltip = 'Height mode = Manual: your root sits this far above the mob\'s root, plus Height tweak (~5.8 for human-sized mobs).' })
                box:AddSlider('SLFarmSpeed', { Text = 'Travel speed', Default = 90, Min = 30, Max = 250, Rounding = 0, Suffix = ' studs/s' })
                box:AddToggle('SLFarmM1', { Text = 'Hold M1', Default = true, Tooltip = 'Holds the game\'s own "Combat" input (normal combo timing - the server gates M1 speed anyway).' })
                box:AddToggle('SLFarmSkipCiv', { Text = 'Skip civilians', Default = true })
                box:AddToggle('SLFarmBosses', { Text = 'Include bosses', Default = true })
                box:AddToggle('SLFarmGroup', { Text = 'Group mobs (pull 2 at once)', Default = true,
                    Tooltip = 'Hit a mob once so it chases you, then go tag a second one; both walk under you and your M1 box hits them together. Server rules (Following.lua): mobs only aggro when HIT and at most 2 can chase one player (NpcsPerPlayer = 2), so 2 is the cap. Skipped for bosses.' })
                box:AddSlider('SLFarmGroupRange', { Text = 'Group pull range', Default = 60, Min = 15, Max = 110, Rounding = 0, Suffix = ' studs',
                    Tooltip = 'Only pull a second mob this close to the first (they stop chasing past ~75-120 studs).' })
                box:AddToggle('SLFarmReturn', { Text = 'Return to farm spot after death', Default = true,
                    Tooltip = 'If you die (or get flung) far from the mob you were farming, it streams out and nothing is in range. This glides you back to where you last farmed so the farm picks it (or its respawn) up again.' })
                box:AddToggle('SLFarmBlock', { Text = 'Block when a mob attacks', Default = true,
                    Tooltip = 'Uses the Combat tab > Auto Parry settings (exact timing, hitbox check, fallback). M1 keeps going until the moment the block must land, and only if the swing can actually reach you on its head; then block, then resume M1. If a block can\'t work (pierced / guard broken / no perfect possible) the farm hops out instead.' })
                box:AddToggle('SLFarmDodge', { Text = 'Dodge mob skills', Default = true,
                    Tooltip = 'When the mob (or a mob near you) starts a real SKILL (matched by animation id against the game\'s Skills folder - normal swings, reacts, blocks and dashes never trigger it), keep hitting through the wind-up, jump out just before the skill\'s first hit and snap back right after its last one.' })
                box:AddDropdown('SLDodgeWhere', { Values = { 'Up', 'Away', 'Up + away' }, Default = 3, Multi = false, Text = 'Dodge to' })
                box:AddSlider('SLDodgeDist', { Text = 'Dodge distance', Default = 30, Min = 10, Max = 80, Rounding = 0, Suffix = ' studs' })
                box:AddSlider('SLDodgeTime', { Text = 'Fallback dodge time', Default = 1.2, Min = 0.3, Max = 4, Rounding = 1, Suffix = ' s',
                    Tooltip = 'Known skills (Upper Smash, Volcanic Conquest, Whirl Pool, Dead Calm, Thunder Clap, Predator Claws...) use their exact hit windows from the game\'s skill configs. This time is only for skills without timing data, unknown boss moves and persistent (never-ending) telegraphs. Normal telegraphs (cast by your target / a mob chasing you, or drawn within 40 studs of you) keep you out for as long as they are drawn.' })
                box:AddSlider('SLDodgeLead', { Text = 'Dodge early / late by', Default = 0.15, Min = 0, Max = 0.6, Rounding = 2, Suffix = ' s',
                    Tooltip = 'Leave this much before the first hit and come back this much after the last one. Raise it with high ping or if skills still clip you.' })
                box:AddToggle('SLDodgeUnknown', { Text = 'Dodge unknown moves too', Default = true,
                    Tooltip = 'Animations that are in neither the Skills folder nor the basic move folders (boss-only moves) dodge on the fallback time if they last 0.6s+. Turn off if a boss makes you dodge constantly.' })
                box:AddToggle('SLDodgeLog', { Text = 'Log mob animations', Default = false,
                    Tooltip = 'Prints every non-looping animation the target plays + whether it counted as a skill, AND saves each new one to SlayersHub/mob_animations.txt in your executor workspace (one line per mob + animation, no duplicates - kept across sessions).' })

                local target, holding, lastPress, lastStatus, lastPick = nil, false, 0, 0, 0
                local lastReturn, returning = -1e9, false
                local function releaseM1()
                    if holding then holding = false; if IH then pcall(IH.VirtualRelease, 'Combat') end end
                end
                S.releaseM1 = releaseM1 -- Auto Parry's farm-block drops M1 before pressing block
                S.farmGetTarget = function() return target end -- Mob Magnet: the farm's live target (no frame lag)
                local function valid(m)
                    if not (m and m.Parent) then return false end
                    local hum = m:FindFirstChildOfClass('Humanoid')
                    return hum ~= nil and hum.Health > 0 and m:FindFirstChild('HumanoidRootPart') ~= nil
                end
                -- Mobs currently chasing US: the server parents an ObjectValue per
                -- follower into <character>.NpcsFollowing (max 2 per player).
                local function followers()
                    local set, n = {}, 0
                    local c = LP.Character
                    local f = c and c:FindFirstChild('NpcsFollowing')
                    if f then
                        for _, v in ipairs(f:GetChildren()) do
                            if v:IsA('ObjectValue') and v.Value and valid(v.Value) then set[v.Value] = true; n = n + 1 end
                        end
                    end
                    return set, n
                end
                -- pick(exclude, near, radius): exclude = model to skip; near/radius =
                -- only mobs within radius of that point; noAggro = only mobs not
                -- already chasing us. Grouping on: mobs chasing us win ties.
                local function pick(exclude, near, radius, noAggro)
                    local root = S.root(); if not root then return nil end
                    local grp = Toggles.SLFarmGroup.Value
                    local chasing = grp and followers() or {}
                    local filter = Options.SLFarmTargets.Value
                    local fOn = type(filter) == 'table' and next(filter) ~= nil
                    -- Auto Quest overrides the list (loose name match: "Mother Bear" vs "MotherBear").
                    -- A claimed Boss Hunt's boss (S.huntMob - set by Boss Hunts > "Farm prefers the
                    -- hunted boss" only while it is alive and loaded) overrides both, at any loaded range.
                    local qn = S.huntMob or S.questMob
                    local qm = qn and (qn:lower():gsub('[^%w]', ''))
                    local reach = S.huntMob and math.max(Options.SLFarmRange.Value, 600) or Options.SLFarmRange.Value
                    local byHp = Options.SLFarmPriority.Value == 'Lowest HP'
                    local best, bestScore
                    for _, m in ipairs(S.mobs()) do
                        local ok
                        if qm then
                            ok = (m.name:lower():gsub('[^%w]', '')) == qm
                        elseif fOn then
                            -- explicitly picked in "Only these mobs": ignore the civilian /
                            -- boss filters (trainees carry CivilianState + a BossInfo)
                            ok = filter[m.name] == true
                        else
                            ok = not (Toggles.SLFarmSkipCiv.Value and m.civ) and not (m.boss and not Toggles.SLFarmBosses.Value)
                                and not (fOn and not filter[m.name])
                        end
                        if ok and (m.model == exclude or (noAggro and (chasing[m.model] or m.boss))
                            or (near and (m.root.Position - near).Magnitude > radius)
                            or (S.kaAvoid and (S.kaAvoid[m.model] or 0) > os.clock())) then ok = false end -- Kill Aura: a player keeps standing by it
                        if ok then
                            local d = (m.root.Position - root.Position).Magnitude
                            if d <= reach then
                                local score = byHp and (m.hum.Health + d * 0.001) or d
                                if chasing[m.model] then score = score - 1e6 end -- already grouped under us
                                if not bestScore or score < bestScore then best, bestScore = m.model, score end
                            end
                        end
                    end
                    return best
                end
                -- Vertical extent of an M1 box (Combat_presets.Get_Players_For_Combat):
                -- centre = root -1 (+YOffsets), height = 6.25 + Widths. The NPC /1.2
                -- shrink is deliberately NOT applied to mob boxes (worst case = safe).
                local CPm = S.req('CAM.Global.Combat_presets')
                local CIP = S.req('CAM.Global.Character_info_provider')
                local function presetOf(who)
                    -- Shared S.m1Preset (NpcMimicFolder.Equipped_Tool + CombatPreset normalised).
                    -- The CIP path below is only a fallback: CIP.Get_equipped_tool returns nil for
                    -- every NPC, so every mob here used to be sized as Combat.
                    if S.m1Preset then return (S.m1Preset(who)) end
                    if not (CPm and type(CPm.Presets) == 'table') then return nil end
                    local tool
                    if CIP and CIP.Get_equipped_tool then
                        local ok, t = pcall(CIP.Get_equipped_tool, who)
                        if ok then tool = t end
                    end
                    return (tool and tool.Name and CPm.Presets[tool.Name]) or CPm.Presets.Combat
                end
                -- Per-model cache: the body top + preset lookups used to run every frame
                -- (CIP.Get_equipped_tool(LP) walks the whole inventory on each call).
                local hCache = setmetatable({}, { __mode = 'k' }) -- [model] = { at, bb, top, mTop }
                local myBot, myBotAt = -4.125, -1e9
                -- Quest-mob check memo for RenderStepped: redone only when S.questMob, S.huntMob
                -- or the target changes (no string building every frame).
                local qmSeen, qmNorm, offQT, offQV, hmSeen, hmNorm = false, nil, nil, false, false, nil
                local heightNote = ''
                local function heightFor(model, mroot)
                    local mode = Options.SLFarmHeightMode.Value
                    if mode == 'Manual' then return math.clamp(Options.SLFarmHeight.Value + Options.SLFarmTweak.Value, -8, 16) end -- tweak applies in every mode
                    local now = os.clock()
                    local hc = hCache[model]
                    if not hc or now - hc.at > 0.5 then
                        local okB, bcf, bsz = pcall(model.GetBoundingBox, model)
                        hc = {
                            at = now,
                            -- 'Model size' (old mode, unchanged): whole model incl. hats / weapon / hair
                            bb = okB and (bcf.Position.Y + bsz.Y / 2 - mroot.Position.Y) or 2.5,
                            -- Auto: DIRECT-CHILD parts only (what the server's box query sees)
                            top = S.bodyTop(model, mroot) or 2.5,
                            -- mob box top = the highest over ALL its combo hits (its real preset)
                            mTop = S.m1BoxSpan(presetOf(model), 'top'),
                        }
                        hCache[model] = hc
                    end
                    local legs = S.m1Legs() -- the same number Auto Parry's reach test uses
                    if mode == 'Model size' then return math.clamp(hc.bb + legs + Options.SLFarmTweak.Value, 1, 16) end
                    local top = hc.top
                    -- Auto: feet just above the mob's box top, but our box bottom still
                    -- inside its body. No gap (tall mob box / short body) -> favour hitting.
                    if now - myBotAt > 0.5 then myBotAt, myBot = now, S.m1BoxSpan(presetOf(LP), 'bottom') end
                    local lo = hc.mTop + legs + S.FARM_CLEAR    -- feet clear the mob's box (worst combo)
                    local hi = top - 0.3 - myBot                -- our box (shallowest combo) still reaches its top
                    local want = lo + Options.SLFarmTweak.Value
                    heightNote = (lo > hi) and '  [no safe gap]' or ''
                    return math.clamp(math.min(want, hi), 1, 20)
                end
                -- ---- skill dodge: cue on mob skill anims / SHCS / telegraphs --------
                local dodgeFrom, dodgeUntil, dodgeWhy, lastDodgeEnd = 0, 0, '', -1e9
                local holdOutFrom, holdOutUntil, holdOutWho = 0, 0, nil -- open-ended charge dodge (Stone Wall grab)
                -- Danger window per skill, seconds after its animation starts: {leave, return}.
                -- From each skill's Config.lua hit timings (first hit .. last hit + recovery):
                --   Upper Smash      THROW 0.165 + EXPLODE 0.36 / LAUNCH 0.8
                --   Volcanic Conq.   slices 0.345 / 0.8 / spin 1.33 / 1.7
                --   Arcs of Justice  hold ticks every 0.35 from 0.2 (hold length varies)
                --   Whirl Pool       tap: 10 hits over 0.7s; Basin: slams from 0.255, dash 1.35s
                --   Dead Calm        catch box 50x10x50 at 0.7 (Startup); cutscene 4.7 / 6.2
                --   Thunder C&F      1.1s startup then 75-stud dash (width 18) + final hit
                --   Predator Claws   slashes 0.17 / 0.5, dash at ~0.9 for 0.5s
                -- Windows are in ANIMATION time (track.TimePosition), not wall time: hold
                -- skills freeze their anim while charging, so wall time drifts. Upper Smash
                -- (Gyorei's slam): anim freezes at 0.2 (HOLD_FREEZE_AT) until release, then
                -- explode at release+0.525, launch at release+1.325 -> anim 0.725 / 1.525.
                local SKILL_WIN = {
                    ['Upper Smash'] = { 0.6, 1.7 },
                    ['Volcanic Conquest'] = { 0.2, 2.1 },
                    ['Arcs of Justice'] = { 0, 3.0 },
                    ['Whirl Pool/Activate'] = { 0.1, 1.2 }, ['Whirl Pool/Basin'] = { 0.1, 1.9 }, ['Whirl Pool'] = { 0, 1.5 },
                    ['Dead Calm/Startup'] = { 0.3, 1.2 }, ['Dead Calm/User'] = { 4.4, 7.0 }, ['Dead Calm'] = { 0.3, 1.2 },
                    ['Thunder Clap and Flash/Dash'] = { 0.6, 1.8 }, ['Thunder Clap and Flash/Player'] = { 0, 1.8 },
                    ['Thunder Clap and Flash'] = { 0.6, 1.8 }, ['Eightfold'] = { 0, 1.8 },
                    ['Predator Claws'] = { 0.1, 1.6 },
                    -- Stone Wall tap: wall 0.21 / shatter 0.82 after release (hold <0.3s).
                    -- Its GRAB (hold >=0.3s) is handled by the open-ended VFX hold-out below.
                    ['Stone Wall/Activate'] = { 0, 1.5 }, ['Stone Wall/StoneGrabAttempt'] = { 0, 0.9 },
                    ['Stone Wall/StoneGrabUser'] = { 0, 1.4 },
                }
                -- Wall-clock windows for skills whose anim is swapped / frozen mid-cast.
                local NO_TRACK = { ['Stone Wall'] = true }
                -- Buffs / utility "skills" that never hit: don't dodge them.
                local NO_DODGE = { ['Enhanced Hearing'] = true }
                local function skillWindow(skill, phase)
                    if NO_DODGE[skill] then return nil end
                    local w = SKILL_WIN[skill .. '/' .. tostring(phase)] or SKILL_WIN[skill]
                    if w then return w[1], w[2], true end
                    return 0, Options.SLDodgeTime.Value, false -- skill we have no timings for
                end
                -- Leave at +from, come back at +to (seconds from now), padded by the lead.
                -- A skill whose window is followed by its track's TimePosition each frame
                -- (so a held / frozen wind-up keeps pushing the hit window back).
                local dTrack, dTrackFrom, dTrackTo, dTrackSpeed = nil, 0, 0, 1
                local function followTrack()
                    if not dTrack then return end
                    local now, lead = os.clock(), Options.SLDodgeLead.Value
                    if dTrack.IsPlaying then
                        local tp = dTrack.TimePosition
                        dTrackSpeed = dTrack.Speed
                        if tp > dTrackTo + lead then dTrack = nil; return end
                        local sp = math.max(dTrackSpeed, 0.05)
                        if dTrackSpeed < 0.05 then sp = 1 end -- frozen (charging): assume release now
                        dodgeFrom = now + math.max(0, (dTrackFrom - tp) / sp - lead)
                        dodgeUntil = now + (dTrackTo - tp) / sp + lead
                    else
                        -- stopped while still frozen = the skill was cancelled, never released
                        if dTrackSpeed < 0.05 and now < dodgeFrom then dodgeFrom, dodgeUntil = 0, 0 end
                        dTrack = nil -- otherwise the last wall-clock window finishes on its own
                    end
                end
                local function triggerDodge(model, why, from, to, track)
                    if not (Toggles.SLFarmDodge.Value and target) then return end
                    local r, mr = S.root(), model and model:FindFirstChild('HumanoidRootPart')
                    if model ~= target and not (r and mr and (mr.Position - r.Position).Magnitude < 30) then return end
                    if track then -- anim-time window: followTrack() drives dodgeFrom/Until
                        dTrack, dTrackFrom, dTrackTo, dTrackSpeed = track, from or 0, to or Options.SLDodgeTime.Value, 1
                        dodgeWhy = why
                        followTrack()
                        return
                    end
                    local lead, now = Options.SLDodgeLead.Value, os.clock()
                    local s, e = now + math.max(0, (from or 0) - lead), now + (to or Options.SLDodgeTime.Value) + lead
                    if now < dodgeUntil then -- overlapping skills: widen the current window
                        dodgeFrom, dodgeUntil = math.min(dodgeFrom, s), math.max(dodgeUntil, e)
                    else
                        dodgeFrom, dodgeUntil = s, e
                    end
                    dodgeWhy = why
                end
                S.farmDodge = triggerDodge -- Auto Parry hops out through the farm when a block can't work
                -- Animation log file: workspace/SlayersHub/mob_animations.txt, one line
                -- per unique (mob, animation id). Existing lines seed the dedupe set,
                -- so re-injecting / new sessions never write a duplicate.
                local ANIM_DIR, ANIM_FILE = 'SlayersHub', 'SlayersHub/mob_animations.txt'
                local animSeen
                local function logAnimToFile(mob, name, id, len, skill)
                    if not writefile then return end
                    if not animSeen then
                        animSeen = {}
                        pcall(function()
                            if isfile and isfile(ANIM_FILE) then
                                for line in readfile(ANIM_FILE):gmatch('[^\r\n]+') do
                                    local m, i = line:match('^(.-) | .- | (%S+) |')
                                    if m and i then animSeen[m .. '|' .. i] = true end
                                end
                            end
                        end)
                    end
                    local key = mob .. '|' .. id
                    if animSeen[key] then return end
                    animSeen[key] = true
                    local line = ('%s | %s | %s | %.2fs | %s\n'):format(mob, name, id, len, skill and 'SKILL' or 'not skill')
                    pcall(function()
                        if makefolder and isfolder and not isfolder(ANIM_DIR) then makefolder(ANIM_DIR) end
                        if appendfile and isfile and isfile(ANIM_FILE) then appendfile(ANIM_FILE, line)
                        else writefile(ANIM_FILE, ((isfile and isfile(ANIM_FILE)) and readfile(ANIM_FILE) or '') .. line) end
                    end)
                end
                local hookedMob = setmetatable({}, { __mode = 'k' })
                local function hookMob(model)
                    if hookedMob[model] then return end
                    hookedMob[model] = true
                    local hum = model:FindFirstChildOfClass('Humanoid')
                    local an = hum and hum:FindFirstChildOfClass('Animator')
                    if an then
                        S.bindLife(model, an.AnimationPlayed:Connect(function(track)
                            if track.Looped then return end
                            local info, id = S.animInfo(track)
                            -- only real skills dodge; swings / reacts / blocks / dashes never do.
                            -- Unknown ids (boss-only moves) dodge on the fallback time if long enough.
                            local skill = info.kind == 'skill'
                                or (info.kind == 'unknown' and Toggles.SLDodgeUnknown.Value and track.Length >= 0.6)
                            local label = info.kind == 'skill' and (info.skill .. '/' .. info.phase)
                                or (info.kind .. ' ' .. tostring(info.skill) .. '/' .. tostring(info.phase))
                            if Toggles.SLDodgeLog.Value and model == target then
                                print(('[Farm anim] %s: %s (%.2fs) %s'):format(model.Name, label, track.Length, skill and '-> DODGE' or ''))
                                local mob = (model.Parent and model.Parent.Name ~= '' and model.Parent.Name) or model.Name
                                logAnimToFile(mob, label, 'rbxassetid://' .. tostring(id or '?'), track.Length, skill)
                            end
                            if skill then
                                local from, to, known = skillWindow(info.skill or '?', info.phase)
                                if from then
                                    local useTrack = known and not NO_TRACK[info.skill] and track or nil
                                    triggerDodge(model, info.kind == 'skill' and info.skill or 'unknown move', from, to, useTrack)
                                end
                            end
                        end))
                    end
                    local function watchShcs(v)
                        if not v:IsA('StringValue') then return end
                        S.bindLife(model, v.Changed:Connect(function(val)
                            if val ~= '' then
                                local from, to = skillWindow(tostring(val), nil)
                                if from then triggerDodge(model, tostring(val), from, to) end
                            end
                        end))
                    end
                    local sh = model:FindFirstChild('SHCS') or model:FindFirstChild('SHC')
                    if sh then watchShcs(sh) end
                    S.bindLife(model, model.ChildAdded:Connect(function(c) if c.Name == 'SHCS' or c.Name == 'SHC' then watchShcs(c) end end))
                end
                S.farmHookMob = hookMob -- Mob Magnet: parked mobs feed the farm's skill dodge
                -- Boss telegraphs (Effects/Core/Telegraph.lua): the client draws each one as
                -- workspace.Debree["<id>-Telegraph"] - created EMPTY on "Start" (plus a Highlight
                -- adorned to the caster when it flashes); the shape plates come with a later
                -- phase call and are placed on the next Heartbeat; Cancel renames it "--" +
                -- sets Cancelled; the plates are removed a Fade after the telegraph's Duration,
                -- except on a Persist telegraph (attribute set on the folder), whose plates stay.
                -- Before: ANY telegraph on the map hopped us off for a fixed time (and a 2s
                -- telegraph landed after the 1.2s hop). Now: only one cast by our target / a mob
                -- chasing us, or whose plate comes within TELE_NEAR studs, and we stay off for
                -- as long as it is drawn (+ lead); a Persist one for the fallback dodge time.
                local TELE_NEAR, teleUntil = 40, 0
                local function teleMine(f, r)
                    local chasing = followers()
                    for _, d in ipairs(f:GetDescendants()) do
                        if d:IsA('Highlight') then
                            local a = d.Adornee
                            if a and (a == target or chasing[a]) then return true end
                        elseif d:IsA('BasePart') and d.Position.Magnitude > 1 then -- plates sit at the origin until placed
                            local flat = (d.Position - r.Position) * Vector3.new(1, 0, 1)
                            if flat.Magnitude - math.max(d.Size.X, d.Size.Y, d.Size.Z) / 2 <= TELE_NEAR then return true end
                        end
                    end
                    return false
                end
                local function watchTelegraph(f)
                    local persist = f:GetAttribute('Persist') == true
                    local t0, mineAt, seen = os.clock(), nil, false
                    while not S.dead and f.Parent and not f:GetAttribute('Cancelled') and os.clock() - t0 < 8 do
                        local drawn = f:FindFirstChildWhichIsA('BasePart', true) ~= nil or f:FindFirstChildWhichIsA('Highlight', true) ~= nil
                        if drawn then seen = true elseif seen then break end -- plates / highlight gone = it has landed
                        if not mineAt then
                            local r = S.root()
                            if r and target and teleMine(f, r) then mineAt = os.clock(); dodgeWhy = 'telegraph' end
                            if not mineAt and os.clock() - t0 > 3 then return end -- never came near us
                        end
                        -- a Persist telegraph never removes its plates: out for the fallback time only
                        if mineAt and persist and os.clock() - mineAt > Options.SLDodgeTime.Value then break end
                        if mineAt and Toggles.SLFarmDodge.Value then teleUntil = math.max(teleUntil, os.clock() + Options.SLDodgeLead.Value + 0.05) end
                        RunService.Heartbeat:Wait()
                    end
                end
                task.spawn(function()
                    local debree = workspace:FindFirstChild('Debree') or workspace:WaitForChild('Debree', 60)
                    if not debree then return end
                    htrack(debree.ChildAdded:Connect(function(f)
                        if f.Name:match('%-Telegraph$') and target and Toggles.SLFarmDodge.Value then task.spawn(watchTelegraph, f) end
                    end))
                end)
                -- Release cues from the skill's own server VFX broadcast (EffectsEvent
                -- (name, caster, phase)). Exact server timing, independent of the anim:
                -- Upper Smash "Throw" = explode in 0.36s, launch 0.8s after that.
                local VFX_WIN = {
                    ['Upper SmashVFX/Throw'] = { 0.36, 1.16 },
                    ['Upper SmashVFX/Explode'] = { 0, 0.8 },
                    ['Stone WallVFX/Wall'] = { 0, 0.8 }, ['Stone WallVFX/Break'] = { 0, 0.3 },
                }
                -- Open-ended hold-outs: a charge whose release time only the server AI
                -- knows. Stone Wall's grab: "Start" at 0.3s into the hold, then the grab
                -- box (22x25x22, instant on release) resolves as Miss / Hit / Cancel.
                -- Stay out from Start until one of those arrives (capped for safety).
                local VFX_OPEN = { ['Stone GrabVfx/Start'] = 6 }
                local VFX_CLOSE = { ['Stone GrabVfx/Miss'] = 0.3, ['Stone GrabVfx/Hit'] = 0.4, ['Stone GrabVfx/Cancel'] = 0.2 }
                task.spawn(function()
                    local holder = S.find(S.EFFECTS)
                    local ev = holder and holder:WaitForChild('Event', 60)
                    if not ev then return end
                    htrack(ev.OnClientEvent:Connect(function(name, who, phase)
                        if type(name) ~= 'string' or typeof(who) ~= 'Instance' then return end
                        local key = name .. '/' .. tostring(phase)
                        if VFX_OPEN[key] and target and Toggles.SLFarmDodge.Value then
                            local r, mr = S.root(), who:FindFirstChild('HumanoidRootPart')
                            if who == target or (r and mr and (mr.Position - r.Position).Magnitude < 30) then
                                holdOutFrom, holdOutUntil, holdOutWho = os.clock(), os.clock() + VFX_OPEN[key], who
                                dodgeWhy = (name:gsub('[Vv][Ff][Xx]$', '')) .. ' (charging)'
                            end
                            return
                        end
                        if VFX_CLOSE[key] and who == holdOutWho then
                            holdOutUntil = math.min(holdOutUntil, os.clock() + VFX_CLOSE[key])
                            return
                        end
                        local w = VFX_WIN[key]
                        if not (w and target and typeof(who) == 'Instance') then return end
                        -- Only a caster the dodge would accept may replace the anim estimate: a far
                        -- player's Upper Smash used to wipe the window we were following for our target.
                        local r, mr = S.root(), who:FindFirstChild('HumanoidRootPart')
                        if not (who == target or (r and mr and (mr.Position - r.Position).Magnitude < 30)) then return end
                        dTrack = nil -- the real release time beats the anim estimate
                        triggerDodge(who, (name:gsub('VFX$', '')), w[1], w[2])
                    end))
                end)
                local function setStatus(t)
                    if os.clock() - lastStatus > 0.3 then lastStatus = os.clock(); S.setText(status, t) end
                end
                htrack(RunService.RenderStepped:Connect(function(dt)
                    S.farmHasTarget = target ~= nil
                    -- Auto Quest Farm drives this loop on its own (no need to also tick Mob farm)
                    local on = Toggles.SLMobFarm.Value or (Toggles.SLAutoQuest and Toggles.SLAutoQuest.Value)
                    if not on or S.farmPaused then -- paused = Auto Quest is walking to an NPC
                        if target or holding or S.farmLocked then
                            target = nil; S.farmLocked = false; releaseM1(); S.noclip('farm', false); S.setText(status, 'Idle')
                        end
                        if not on then S.farmLastPos = nil end -- farm off: forget the spot
                        return
                    end
                    local root = S.root()
                    if not root then releaseM1(); S.farmLocked = false; return end
                    if target and target == S.huntDrop then target = nil end -- Boss Hunts gave up on this boss
                    -- Auto Quest switched mobs (or is handing in: its no-match questMob sentinel): a target
                    -- picked for the old quest stayed "valid", so the farm finished it (and its
                    -- group) first. Same loose name match as pick(); memoised (qmSeen / offQT), so no
                    -- strings are built per frame. A claimed hunt's boss (S.huntMob) is never off-quest.
                    if S.questMob ~= qmSeen or S.huntMob ~= hmSeen then
                        qmSeen, hmSeen = S.questMob, S.huntMob
                        qmNorm = type(qmSeen) == 'string' and (qmSeen:lower():gsub('[^%w]', '')) or nil
                        hmNorm = type(hmSeen) == 'string' and (hmSeen:lower():gsub('[^%w]', '')) or nil
                        offQT = nil
                    end
                    if target ~= offQT then
                        offQT = target
                        local tn = qmNorm and target and target.Parent and (target.Parent.Name:lower():gsub('[^%w]', ''))
                        offQV = (tn and tn ~= qmNorm and tn ~= hmNorm) or false
                    end
                    if not valid(target) or offQV or (S.kaAvoid and (S.kaAvoid[target] or 0) > os.clock()) then
                        -- Target died (finisher), left, is off-quest, or Kill Aura skips it (a player keeps
                        -- standing by it, S.kaAvoid): re-pick on that SAME frame instead of idling up to
                        -- 0.25s for the next scan slot (the throttle only paces repeat scans while nothing
                        -- is in range). M1 stays held when the next mob is already under us (a grouped
                        -- follower wins the pick); the travel / dodge branches release it anyway.
                        local lost = target ~= nil
                        target = nil; S.farmLocked = false
                        if lost or os.clock() - lastPick > 0.25 then lastPick = os.clock(); target = pick(S.huntDrop) end -- scan 4x/s, not every frame
                        if not target then releaseM1() end
                    elseif S.huntMob and hmNorm and os.clock() - lastPick > 0.5 and target.Parent
                        and (target.Parent.Name:lower():gsub('[^%w]', '')) ~= hmNorm then
                        -- a claimed hunt's boss came into reach: leave the current mob for it
                        lastPick = os.clock()
                        local b = pick()
                        if b and b ~= target then target = b; releaseM1(); S.farmLocked = false end
                    elseif Toggles.SLFarmGroup.Value and S.farmLocked and os.clock() - lastPick > 0.25
                        and os.clock() >= (S.kaAimUntil or 0) then -- never retarget in a Kill Aura cast window
                        -- Grouping: once our target is chasing us and we have room for
                        -- another follower, go tag the nearest un-aggroed mob. The first
                        -- one follows us over; both end up under our M1 box.
                        lastPick = os.clock()
                        local chasing, n = followers()
                        local tslot = target.Parent
                        if chasing[target] and n < 2 and not (tslot and tslot:FindFirstChild('BossInfo')) then
                            local nxt = pick(target, target.HumanoidRootPart.Position, Options.SLFarmGroupRange.Value, true)
                            if nxt then target = nxt; releaseM1(); S.farmLocked = false end
                        end
                    end
                    if not target then
                        -- Died / got flung far away: the mob streamed out, so nothing is in
                        -- range. Glide back to where we were last farming and look again.
                        if S.farmLastMob ~= S.questMob then S.farmLastPos = nil end -- quest switched mobs: old spot is stale
                        local back = S.farmLastPos
                        if back and Toggles.SLFarmReturn.Value and (root.Position - back).Magnitude > 40 then
                            if os.clock() - lastReturn > 6 then
                                lastReturn, returning = os.clock(), true
                                S.glideTo(back + Vector3.new(0, 6, 0), math.max(Options.SLFarmSpeed.Value, 120))
                            end
                            setStatus(('Returning to farm spot (%.0f studs)'):format((root.Position - back).Magnitude))
                            return
                        end
                        S.noclip('farm', false)
                        setStatus((S.kaAvoidUntil or 0) > os.clock() and 'Skipping a mob a player stands next to (Kill Aura, 20s) - no other mob in range'
                            or 'No mob in range (go near a camp)')
                        return
                    end
                    if returning then returning = false; S.stopGlide() end -- found one: the farm moves us now
                    S.noclip('farm', true)
                    hookMob(target)
                    local mroot = target.HumanoidRootPart
                    -- The farm spot is where regular mobs are farmed. A detour to a claimed hunt's
                    -- boss (S.huntMob) keeps it, so the return-glide brings us back afterwards
                    -- (unless that boss is also Auto Quest's own quest mob).
                    local onHunt = false
                    if hmNorm and target.Parent then -- (hmNorm / qmNorm: the memoised names above)
                        local tn = (target.Parent.Name:lower():gsub('[^%w]', ''))
                        onHunt = tn == hmNorm and tn ~= qmNorm
                    end
                    if not onHunt then
                        S.farmLastPos, S.farmLastMob = mroot.Position, S.questMob
                    elseif not S.farmLastPos then
                        S.farmLastPos, S.farmLastMob = root.Position, S.questMob -- no spot yet: where the detour began
                    end
                    local goal = mroot.Position + Vector3.new(0, heightFor(target, mroot), 0)
                    local flat = mroot.CFrame.LookVector * Vector3.new(1, 0, 1)
                    if flat.Magnitude < 0.1 then flat = Vector3.new(0, 0, -1) end
                    local mobFlat = flat -- the mob's own facing (skill dodge Away = behind IT, not behind our box)
                    -- Kill Aura (M1 box packing): may swap in a spot + facing whose M1 box
                    -- covers more mobs, and says when M1 must wait (target countering /
                    -- perfect-blocking, a punishing mob or a player inside our box).
                    local kaN, kaHold, kaSnap = 0, nil, false
                    if S.kaPose then
                        local okK, g2, f2, n2, h2, s2 = pcall(S.kaPose, target, mroot, goal, flat)
                        if okK and typeof(g2) == 'Vector3' and typeof(f2) == 'Vector3' and f2.Magnitude > 0.1 then
                            goal, flat, kaN, kaHold, kaSnap = g2, f2, tonumber(n2) or 0, h2, s2 == true
                        end
                    end
                    -- skill dodge: hop out of range for the skill's active time, then snap back
                    followTrack()
                    local nowD = os.clock()
                    -- Kill Aura reads these so it never starts (or keeps holding) a skill into a dodge
                    S.farmDodgeFrom, S.farmDodgeUntil = dodgeFrom, dodgeUntil
                    S.farmHoldOutFrom, S.farmHoldOutUntil = holdOutFrom, holdOutUntil
                    if holdOutWho and not (holdOutWho.Parent and valid(holdOutWho)) then holdOutUntil = 0; holdOutWho = nil end
                    -- open-ended: a charge (Stone Grab) or a live telegraph. The telegraph hold-out only
                    -- counts near the mob: travelling to a far target past someone else's plate must not
                    -- jump us to goal + offset in one frame (the dodge branch writes the root directly).
                    local charging = (nowD >= holdOutFrom and nowD < holdOutUntil)
                        or (nowD < teleUntil and (goal - root.Position).Magnitude <= Options.SLDodgeDist.Value + 8)
                    if charging or (nowD >= dodgeFrom and nowD < dodgeUntil) then -- inside the skill's hit window
                        local where, dist = Options.SLDodgeWhere.Value, Options.SLDodgeDist.Value
                        local away = -mobFlat.Unit -- behind the mob, off its facing
                        local off = (where == 'Up' and Vector3.new(0, dist, 0))
                            or (where == 'Away' and away * dist)
                            or (away * dist * 0.7 + Vector3.new(0, dist * 0.7, 0))
                        local p = goal + off
                        root.CFrame = CFrame.lookAt(p, p + flat.Unit)
                        root.AssemblyLinearVelocity = Vector3.zero
                        S.farmLocked = false
                        releaseM1()
                        lastDodgeEnd = os.clock()
                        setStatus(charging and ('Dodging %s'):format(dodgeWhy)
                            or ('Dodging %s (%.1fs)'):format(dodgeWhy, dodgeUntil - os.clock()))
                        return
                    end
                    local delta = goal - root.Position
                    if kaSnap and S.farmLocked and delta.Magnitude > 6 and delta.Magnitude <= 20 then
                        root.CFrame = CFrame.lookAt(goal, goal + flat.Unit) -- Kill Aura just changed the spot: short hop, keep swinging
                        delta = Vector3.zero
                    end
                    if delta.Magnitude > 6 and os.clock() - lastDodgeEnd < 0.3 then
                        root.CFrame = CFrame.lookAt(goal, goal + flat.Unit) -- snap straight back after a dodge
                        delta = Vector3.zero
                    end
                    if delta.Magnitude > 6 then -- travelling: bounded glide, no swings
                        S.farmLocked = false
                        releaseM1()
                        local step = math.min(delta.Magnitude, Options.SLFarmSpeed.Value * dt)
                        local p = root.Position + delta.Unit * step
                        root.CFrame = CFrame.lookAt(p, p + flat.Unit)
                        setStatus(('-> %s (%.0f studs)'):format(target.Parent and target.Parent.Name or target.Name, delta.Magnitude))
                    else -- locked on its head
                        S.farmLocked = true
                        -- Kill Aura cast window (until S.kaAimUntil): face the point it scored
                        -- (skill boxes are root.CFrame * offset, so facing = where they land) and
                        -- sink by S.kaDrop ONLY inside S.kaDropWins (around each server hit), so
                        -- between hits we sit on the usual safe perch. Outside it: the head lock.
                        if S.kaAim and os.clock() < (S.kaAimUntil or 0) then
                            local nowK, sink = os.clock(), 0
                            if (S.kaDrop or 0) > 0 and type(S.kaDropWins) == 'table' then
                                for _, w in ipairs(S.kaDropWins) do
                                    if nowK >= w[1] and nowK <= w[2] then sink = S.kaDrop; break end
                                end
                            end
                            local castAt = goal - Vector3.new(0, sink, 0)
                            local face = (S.kaAim - castAt) * Vector3.new(1, 0, 1)
                            root.CFrame = CFrame.lookAt(castAt, castAt + ((face.Magnitude > 0.5) and face.Unit or flat.Unit))
                        else
                            root.CFrame = CFrame.lookAt(goal, goal + flat.Unit)
                        end
                        if Toggles.SLFarmM1.Value and IH and not kaHold and os.clock() >= (S.farmBlockUntil or 0) then -- paused while block is held / Kill Aura says wait
                            -- Re-press every 0.35s: the game's hold-chain stops if a
                            -- punch is refused (e.g. we got stunned), a fresh press restarts it.
                            local now = os.clock()
                            if not holding or now - lastPress > 0.35 then
                                lastPress = now
                                if holding then pcall(IH.VirtualRelease, 'Combat') end
                                holding = pcall(IH.VirtualPress, 'Combat')
                            end
                        else
                            releaseM1()
                        end
                        local hum = target:FindFirstChildOfClass('Humanoid')
                        local chasingSet, nChasing = followers()
                        -- the grouped mob under us: its skills / charges dodge too (was: only the target was hooked)
                        for m in pairs(chasingSet) do hookMob(m) end
                        setStatus(('Farming %s  %d/%d HP  h=%.1f%s%s%s%s'):format(target.Parent and target.Parent.Name or target.Name,
                            math.floor(hum.Health + 0.5), math.floor(hum.MaxHealth + 0.5), goal.Y - mroot.Position.Y, heightNote,
                            nChasing > 0 and ('  [%d grouped]'):format(nChasing) or '',
                            kaN >= 2 and ('  [%d in box]'):format(kaN) or '',
                            kaHold and ('  [M1 wait: %s]'):format(tostring(kaHold)) or (S.kaStat or '')))
                    end
                    root.AssemblyLinearVelocity = Vector3.zero
                end))
                if not IH then box:AddLabel('InputHandler not loaded - Hold M1 unavailable here.', true) end
                htrack({ Disconnect = function() releaseM1() end })
            end)()
            -- ================================================================
            -- KILL AURA: M1 box packing - one swing hits every mob in the box
            -- ================================================================
            -- Combat_presets.Get_Players_For_Combat (CAM/Global/Combat_presets.lua:314-442)
            -- builds ONE box from our server-side root at hit time and returns every
            -- Humanoid model with a direct-child part inside it (Utility.GetModelInRegion,
            -- Utility.lua:1216-1242, over workspace.Humanoids, MaxParts 350): no cap, no
            -- distance / LOS check, the client sends no target. M1 speed is server-gated
            -- (Check_can_do_combat_server), so the only multiplier is how many mobs share
            -- that box. Idle camp mobs rarely stand that close, so in practice this packs
            -- the (max 2) mobs Group mobs pulls under us. ~5x/s it tries spots above the
            -- target / the pack centre / each mob-pair midpoint, facing each mob, and
            -- picks the box that holds the most mobs while our feet stay above every
            -- nearby mob's own box (same clearance maths as heightFor, S.kaClearance).
            -- It also guards M1: never into a player, and waits out counters / perfect
            -- blocks (capped, so a stuck state can never freeze the farm).
            ;(function()
                local box = Tabs.Farm:AddRightGroupbox('Kill Aura')
                S.kaBox = box -- the Skill aura adds its part below (one Kill Aura groupbox)
                box:AddLabel('The server M1 box hits EVERY mob inside it (no cap). Camp mobs rarely stand that close, so the real gain is the 2 mobs Group mobs pulls under you: up to ~2 mobs/hit. The hit check below measures it.', true)
                box:AddToggle('SLKAMulti', { Text = 'Multi-target M1', Default = false,
                    Tooltip = 'Off by default: it changes where the farm sits. About 5x/s it tries spots above the target, above the pack centre and above each mob-pair midpoint, facing each mob, and moves only when that box holds 2+ mobs and beats sitting on the target head (min 1s per spot, never chases a walking target). Turn it on after Reset hit check shows more than 1.0 mobs/hit at your camp.' })
                box:AddSlider('SLKARadius', { Text = 'Pack radius', Default = 12, Min = 6, Max = 20, Rounding = 0, Suffix = ' studs',
                    Tooltip = 'Mobs this close (flat distance) to the target are packed into the box.' })
                box:AddSlider('SLKAMargin', { Text = 'M1 box safety margin', Default = 0.5, Min = 0, Max = 2, Rounding = 1, Suffix = ' studs',
                    Tooltip = 'A mob only counts if it is inside your box shrunk by this much front / back / sides (ping, mob drift; height is exact). Raise it if the hit check below shows fewer mobs/hit than the box predicts.' })
                box:AddToggle('SLKAOnlyWanted', { Text = 'Only pack farm targets', Default = true,
                    Tooltip = 'Only mobs the farm itself would pick (quest mob / Only-these-mobs list / civilian + boss toggles) count; other mobs never pull the spot. (Either way a Kill Aura spot never clips a civilian while Skip civilians is on, or a boss while Include bosses is off.)' })
                box:AddToggle('SLKADefense', { Text = 'Respect counters / perfect blocks', Default = true,
                    Tooltip = 'Server check_victim: a mob in counter stance (NpcCounter 1/2, a Counter value, a counter skill) or holding a PERFECT block punishes the swing. M1 waits while the target (or a mob inside your box) is in that state - max 2s each time, then one swing takes the counter (Auto Parry / skill dodge cover the riposte). Dodge charges / i-frames cost nothing (M1 keeps going and burns them); such mobs just never count toward packing.' })
                box:AddToggle('SLKANoPvP', { Text = 'Never swing into players', Default = true,
                    Tooltip = 'Player characters live in workspace.Humanoids too, so the M1 box hits them. M1 waits while a player (or a player clone) is inside the reach of any of your combo hits. If one stays by the target for 5s the farm skips that mob for 20s and takes another.' })
                local statLbl = box:AddLabel('Hit check: waiting for farm swings', true)

                local V3 = Vector3.new
                local CPm
                local function presets()
                    CPm = CPm or S.req('CAM.Global.Combat_presets')
                    return CPm and type(CPm.Presets) == 'table' and CPm.Presets or nil
                end
                local function pidx(t, i) return type(t) == 'table' and (t[i] or t.Default) or nil end
                local function flat2(v) return V3(v.X, 0, v.Z) end
                -- S.req, but a failed require is only retried every 30s (not every frame).
                local modMemo = {}
                local function reqMemo(path)
                    local e = modMemo[path]
                    if e and (e.m or os.clock() - e.t < 30) then return e.m or nil end
                    local m = S.req(path)
                    modMemo[path] = { m = m or false, t = os.clock() }
                    return m
                end
                -- The server's last_magasd IntValue under a root (Combat_presets.lua:331-367):
                -- created on the first swing, raised by the swing's own speed, 0 again 0.75s
                -- after its last change. Server-created, so it replicates.
                local function lmOf(part)
                    local v = part and part:FindFirstChild('last_magasd')
                    return (v and v:IsA('ValueBase') and tonumber(v.Value)) or 0
                end
                -- Reach bonus u1 (:368-389): max(preset MinHitboxSize, tool floor) + Reaches[combo].
                local function reachU1(preset, idx, floor)
                    local u1 = math.max(preset.MinHitboxSize or 0, tonumber(floor) or 0)
                    local r = pidx(preset.Reaches, idx); if r then u1 = u1 + r end
                    return u1
                end

                -- The server M1 box for a HYPOTHETICAL root CFrame with zero velocity:
                -- Get_Players_For_Combat with |vel| <= 1 -> dir = LookVector (:325-330);
                -- ext = max(u1, min(last_magasd, 7)) (:396-401, u1 < 0: max(lm + u1, 1));
                -- floor = the equipped TOOL preset's MinHitboxSize / AccessoryHitBoxAdditions
                -- (:369-386); minExt = the last_magasd to assume (default 1). own = true
                -- drops Widths: the decompiled server never applies them to the size
                -- (:419-421), so OUR box is modelled without them (smaller = safe count),
                -- mob boxes keep them (bigger = safe clearance). Returns CFrame, Size.
                function S.m1BoxAt(cf, preset, idx, npc, minExt, floor, own)
                    preset = preset or {}
                    idx = idx or 1
                    local u1 = reachU1(preset, idx, floor)
                    local lv = cf.LookVector
                    local dir = V3(lv.X, 0, lv.Z)
                    dir = dir.Magnitude > 0.01 and dir.Unit or V3(0, 0, -1)
                    local ext = minExt or 1
                    if u1 < 0 then ext = math.max(ext + u1, 1) else ext = math.max(u1, ext) end
                    local base = cf * CFrame.new(0, -1, 0)
                    local yo = pidx(preset.YOffsets, idx); if yo then base = base * CFrame.new(0, yo, 0) end
                    local addW, addD = 0, 0
                    if idx == 7 then addW, addD = 4, 7 end
                    local w = own and 0 or (pidx(preset.Widths, idx) or 0)
                    local dp = pidx(preset.Depths, idx) or 0
                    local scale = npc and (1 / 1.2) or 1
                    local size = V3(addW + 6 + w, w + 6.25, math.max(addD + 9 + dp, 1)) * scale + V3(0, 0, ext)
                    local p = base.Position
                    local out = CFrame.lookAt(p, p + dir) * CFrame.new(0, 0, -ext * 0.75)
                    local zo = pidx(preset.ZOffsets, idx); if zo then out = out * CFrame.new(0, 0, -zo) end
                    return out, size
                end

                -- Our preset, exactly like CU/Combat.lua get_equipped_Combat + punch():
                -- the tool's Items[].CombatPreset, else a fighting style from CurPower with a
                -- <name>_Combat_Anims folder, else the tool name; unknown weapon items fall
                -- back to Items[name].CombatPreset or 'Regular Katana'. Cached 1s.
                -- 3rd return = reach floor from the TOOL's own preset (server :369-386).
                local myCache
                local function myPreset()
                    local P = presets(); if not P then return nil, '?', 0 end
                    local now = os.clock()
                    if myCache and now - myCache.t < 1 then return myCache.p, myCache.n, myCache.f end
                    local Items = S.req('CAM.Global.Collectibles.Items')
                    local CIP = S.req('CAM.Global.Character_info_provider')
                    local tool
                    if CIP and CIP.Get_equipped_tool then
                        local ok, t = pcall(CIP.Get_equipped_tool, LP)
                        if ok then tool = t end
                    end
                    local tname = tool and tool.Name
                    local item = (tname and type(Items) == 'table') and Items[tname] or nil
                    local name
                    if type(item) ~= 'table' or item.CombatPreset == nil or item.CombatPreset == 'Combat' then
                        local cp = S.find('CAM.Client.Controllers.Skills_Provider.CurPower')
                        local anims = S.find('Assets.Animations')
                        if cp and anims then
                            for _, v in ipairs(string.split(tostring(cp.Value), ',')) do
                                if v ~= '' and anims:FindFirstChild(v .. '_Combat_Anims') then name = v; break end
                            end
                        end
                        name = name or tname
                    else
                        name = tname
                    end
                    local p = name and P[name] or nil
                    if not p and name and type(Items) == 'table' and type(Items[name]) == 'table' then
                        name = Items[name].CombatPreset or 'Regular Katana'
                        p = P[name]
                    end
                    if not p then p, name = P.Combat, 'Combat' end
                    local floor = 0
                    local tp = tname and P[tname] or nil
                    if type(tp) == 'table' then
                        floor = tonumber(tp.MinHitboxSize) or 0
                        local add = tp.AccessoryHitBoxAdditions
                        local acc = type(add) == 'table' and LP.Character and LP.Character:FindFirstChild('Accessories')
                        if acc then
                            for k, v in pairs(add) do
                                if type(v) == 'number' and acc:FindFirstChild(tostring(k)) then floor = math.max(floor, v) end
                            end
                        end
                    end
                    myCache = { p = p, n = name, f = floor, t = now }
                    return p, name, floor
                end
                -- The combo we just threw + when: CU/Combat.lua:107-118 / :152-163 writes it to
                -- Player_Service.Values.<me>.ComboTrackerClient (.Value = hit, .Time = os.clock())
                -- on every punch - an instance, so no reliance on sharing the game's require
                -- cache. Fallback: the Combat_presets.Last_Combo / Last_Punched fields.
                local function comboTracker()
                    local vals = S.values()
                    local ct = vals and vals:FindFirstChild('ComboTrackerClient')
                    local tv = ct and ct:FindFirstChild('Time')
                    if ct and tv then return tonumber(ct.Value), tonumber(tv.Value) end
                    if presets() then return tonumber(CPm.Last_Combo), tonumber(CPm.Last_Punched) end
                    return nil, nil
                end
                -- Next combo hit (CU/Combat.lua:164-169: wraps after Max or 7; ComboValue resets
                -- to 1 combo_duration after the last punch, :48-68).
                local function nextCombo(preset)
                    local mx = math.clamp(tonumber(preset and preset.Max) or 5, 1, 7)
                    local last, at = comboTracker()
                    local dur = (CPm and tonumber(CPm.combo_duration)) or 1.35
                    if not (last and at) or last < 1 or os.clock() - at > dur then return 1 end
                    if last >= mx or last == 7 then return 1 end
                    return last + 1
                end
                -- In the air the Max hit is thrown as hit 7 (Main_Combat_Script_Client.lua:50-58,
                -- :115-117); hovering over a mob is always in the air.
                local function airborne()
                    local h = S.hum()
                    if not h then return true end
                    local fm = h.FloorMaterial
                    return fm == nil or fm == Enum.Material.Air
                end
                -- Which last_magasd the server will use for OUR hit. With the swing flag set it
                -- is raised to >= 1 (our |dir| when still) BEFORE ext is computed (:361-367);
                -- once we have seen it >= 1 while swinging, that is proven, so ext is in
                -- [1, current]. Until then also model 0 (a zero-length aim vector: :396-402).
                local lmProven = false
                local function extSet(root)
                    local lm = math.min(lmOf(root), 7)
                    if lm >= 1 then lmProven = true end
                    if not lmProven then return { 0, 1 } end
                    if lm > 1 then return { 1, lm } end
                    return { 1 }
                end
                -- Mob preset: AiPrerequistes.NpcMimicFolder.Equipped_Tool (read directly -
                -- AiMimic:GetFolder would CREATE the folder), normalised like punch():
                -- Presets[v] or Presets[Items[v].CombatPreset or 'Regular Katana']; none = Combat.
                local mobCache = setmetatable({}, { __mode = 'k' })
                local function mobPreset(model)
                    local P = presets(); if not P then return nil end
                    local c = mobCache[model]
                    if c and os.clock() - c.t < 5 then return c.p end
                    local v = S.val(model, 'AiPrerequistes', 'NpcMimicFolder', 'Equipped_Tool')
                    local p
                    if v == nil or tostring(v) == '' then
                        p = P.Combat
                    else
                        v = tostring(v)
                        p = P[v]
                        if not p then
                            local Items = S.req('CAM.Global.Collectibles.Items')
                            local it = type(Items) == 'table' and Items[v] or nil
                            p = P[(type(it) == 'table' and it.CombatPreset) or 'Regular Katana'] or P.Combat
                        end
                    end
                    mobCache[model] = { p = p, t = os.clock() }
                    return p
                end
                -- A MOB box top over EVERY combo (centre root -1 +YOffsets, height 6.25 + Widths);
                -- Widths kept and the NPC /1.2 shrink left off on purpose (worst case = safe).
                local topCache, botCache = setmetatable({}, { __mode = 'k' }), setmetatable({}, { __mode = 'k' })
                local function topRel(preset)
                    if not preset then return 2.125 end
                    local t = topCache[preset]; if t then return t end
                    t = -math.huge
                    for c = 1, math.max(tonumber(preset.Max) or 5, 7) do
                        t = math.max(t, -1 + (pidx(preset.YOffsets, c) or 0) + (6.25 + (pidx(preset.Widths, c) or 0)) / 2)
                    end
                    topCache[preset] = t
                    return t
                end
                -- OUR box's HIGHEST bottom over our combos (the hit that reaches least far down),
                -- without Widths (the smaller reading of the server box).
                local function bottomRel(preset)
                    if not preset then return -4.125 end
                    local b = botCache[preset]; if b then return b end
                    b = -math.huge
                    local mx = math.clamp(tonumber(preset.Max) or 5, 1, 7)
                    for c = 1, 7 do
                        if c <= mx or c == 7 then
                            b = math.max(b, -1 + (pidx(preset.YOffsets, c) or 0) - 6.25 / 2)
                        end
                    end
                    botCache[preset] = b
                    return b
                end
                -- How far (flat) a mob's box can reach from its root, any facing: it turns to
                -- face you, walking stretches ext (:325-327) and the server keeps the larger
                -- ext in the replicated last_magasd for 0.75s after it stops (:331-367).
                local function reachOf(preset, mroot)
                    preset = preset or {}
                    local vel = mroot.AssemblyLinearVelocity
                    local m = math.clamp(vel.Magnitude / 5, 0, 13)
                    m = (m <= 5) and m / 2 or m
                    local e0 = m * 1.25
                    e0 = (e0 <= 1) and 1 or math.min(e0, 7)
                    e0 = math.max(e0, math.min(lmOf(mroot), 7))
                    local best = 0
                    for _, c in ipairs({ 1, 2, 3, 4, 5, 7 }) do
                        local u1 = (preset.MinHitboxSize or 0) + (pidx(preset.Reaches, c) or 0)
                        local e = (u1 < 0) and math.max(e0 + u1, 1) or math.max(u1, e0)
                        local addW, addD = 0, 0
                        if c == 7 then addW, addD = 4, 7 end
                        local depth = math.max(addD + 9 + (pidx(preset.Depths, c) or 0), 1) + e
                        local cz = 0.75 * e + (pidx(preset.ZOffsets, c) or 0)
                        local hw = (addW + 6 + (pidx(preset.Widths, c) or 0)) / 2
                        local fz = math.max(cz + depth / 2, depth / 2 - cz)
                        best = math.max(best, math.sqrt(fz * fz + hw * hw))
                    end
                    return best + 1.5
                end
                -- Top of the mob's DIRECT-CHILD, queryable parts (all the server region
                -- query can see: GetModelInRegion takes part.Parent), relative to its root.
                local function bodyTop(model, mroot)
                    local top
                    for _, p in ipairs(model:GetChildren()) do
                        if p:IsA('BasePart') and p.CanQuery then
                            local cf, s = p.CFrame, p.Size
                            local hy = 0.5 * (math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z)
                            local t = p.Position.Y + hy
                            if not top or t > top then top = t end
                        end
                    end
                    return top and (top - mroot.Position.Y) or 2.5
                end
                -- heightFor (Auto) + the pose solver share this: lo = root height where our
                -- feet clear the mob's highest box (any combo); hi = highest root where our
                -- least-reaching combo still touches the top of its direct-child parts.
                function S.kaClearance(model, mroot, legs)
                    if not presets() then return nil end
                    local lo = topRel(mobPreset(model)) + legs + 0.15
                    local hi = bodyTop(model, mroot) - 0.3 - bottomRel((myPreset()))
                    return lo, hi
                end

                -- ---- defence state (Checker.check_victim :816-1123, read-only) ----------
                -- Values folder = Player_Service.Values[<model name>] or the model itself
                -- (Utility.getvaluesfolder :1186-1214).
                local function valuesOf(model)
                    local ps = RepStorage:FindFirstChild('Player_Service')
                    local vals = ps and ps:FindFirstChild('Values')
                    return (vals and vals:FindFirstChild(model.Name)) or model
                end
                -- SkillStats.Get(skill)[key] (lowercase keys, SkillStats.lua:136-144).
                local function statOf(skill, key)
                    local SS = reqMemo('CAM.Global.Subsets.Gameplay.StatsFetch.Modules.SkillStats')
                    if not (SS and type(SS.Get) == 'function') then return nil end
                    local ok, st = pcall(SS.Get, skill)
                    if ok and type(st) == 'table' then return st[key] end
                    return nil
                end
                -- 'absorb' = the mob eats the hit (i-frames, Dodge charges); 'punish' = the
                -- swing gets countered / perfect-parried. Same order as check_victim.
                local function defenseOf(model)
                    local vf = valuesOf(model)
                    -- hold i-frame, server side (VisibilityHelpers.lua:18-37 on the server reads
                    -- SHCS): a skill with the iframe stat + last_performed + a Max_Hold_Time
                    local shs = model:FindFirstChild('SHCS')
                    if shs and shs:IsA('StringValue') and shs.Value ~= '' and shs:GetAttribute('last_performed') ~= nil
                        and statOf(shs.Value, 'iframe') then
                        local PP = reqMemo('CAM.Global.PlayerProfile')
                        local si = PP and type(PP.skill_info) == 'table' and PP.skill_info[shs.Value]
                        if type(si) == 'table' and si.Max_Hold_Time then return 'absorb', 'i-frames' end
                    end
                    -- iframe / escapeiframe children, unless one names us (GetIFrame.lua:14-53)
                    local anyI, oursI = false, false
                    for _, c in ipairs(vf:GetChildren()) do
                        if c.Name == 'iframe' or c.Name == 'escapeiframe' then
                            anyI = true
                            if c:IsA('ValueBase') and tostring(c.Value) == LP.Name then oursI = true end
                        end
                    end
                    if anyI and not oursI then return 'absorb', 'i-frames' end
                    -- NpcCounter 1 = M1s, 2 = everything (Checker.lua:935-972)
                    local nc = model:GetAttribute('NpcCounter')
                    if nc == 1 or nc == 2 then return 'punish', 'counter stance' end
                    -- GetCounter.lua:10-19: a Counter StringValue (Type attr; Record ones never
                    -- fire on M1, Checker.lua:989-1003), else the FIRST of SHC / SHCS
                    local ctr, ct = vf:FindFirstChild('Counter'), nil
                    if ctr and ctr:IsA('StringValue') and ctr.Value ~= '' then
                        ct = ctr:GetAttribute('Type')
                        if ctr:GetAttribute('Record') == true then ct = nil end
                    else
                        local sh = model:FindFirstChild('SHC') or model:FindFirstChild('SHCS')
                        if sh and sh:IsA('StringValue') and sh.Value ~= '' then ct = statOf(sh.Value, 'counter') end
                    end
                    if ct == 1 or ct == 2 then return 'punish', 'counter' end
                    local dg = vf:FindFirstChild('Dodge')
                    if dg and dg:IsA('IntValue') and dg.Value > 0 then return 'absorb', 'dodge' end
                    local blk = vf:FindFirstChild('Blocking')
                    if blk and not vf:FindFirstChild('PierceBlock') and blk:FindFirstChild('Perfect') then return 'punish', 'perfect block' end
                    return nil, nil
                end
                -- Same filter as the farm's pick(): quest mob / Only-these-mobs list / civ + boss toggles.
                local function kindOf(model)
                    local slot = model.Parent
                    local name = slot and slot.Name or model.Name
                    local civ = name:find('Civilian') ~= nil or model:GetAttribute('CivilianState') ~= nil
                    local boss = slot ~= nil and slot:FindFirstChild('BossInfo') ~= nil
                    return name, civ, boss
                end
                local function wantedModel(model)
                    local name, civ, boss = kindOf(model)
                    if S.questMob then
                        return (name:lower():gsub('[^%w]', '')) == (tostring(S.questMob):lower():gsub('[^%w]', ''))
                    end
                    local filter = Options.SLFarmTargets and Options.SLFarmTargets.Value
                    if type(filter) == 'table' and next(filter) ~= nil then return filter[name] == true end
                    return not (Toggles.SLFarmSkipCiv and Toggles.SLFarmSkipCiv.Value and civ)
                        and not (boss and Toggles.SLFarmBosses and not Toggles.SLFarmBosses.Value)
                end
                -- A mob a Kill Aura spot must not clip: an unwanted civilian (Skip civilians on)
                -- or boss (Include bosses off). The farm's own spot is left as it always was.
                local function offLimits(model)
                    if wantedModel(model) then return false end
                    local _, civ, boss = kindOf(model)
                    return (civ and Toggles.SLFarmSkipCiv and Toggles.SLFarmSkipCiv.Value)
                        or (boss and Toggles.SLFarmBosses and not Toggles.SLFarmBosses.Value) or false
                end

                -- ---- region queries: the server's own filter ------------------------------
                local HS
                local OPH = OverlapParams.new()
                OPH.FilterType = Enum.RaycastFilterType.Include
                OPH.MaxParts = 350
                local OPT = OverlapParams.new()
                OPT.FilterType = Enum.RaycastFilterType.Include
                OPT.MaxParts = 64
                local function humFolder()
                    if HS and HS.Parent then return HS end
                    HS = workspace:FindFirstChild('Humanoids')
                    if HS then OPH.FilterDescendantsInstances = { HS } end
                    return HS
                end
                -- Models GetModelInRegion would return: the part's direct parent is a Model
                -- with a PrimaryPart (Utility.lua:1234-1241) and a child named Humanoid (:434).
                local function modelsIn(cf, size, params)
                    local out, seen = {}, {}
                    local ok, parts = pcall(workspace.GetPartBoundsInBox, workspace, cf, size, params)
                    if not ok or type(parts) ~= 'table' then return out end
                    for _, p in ipairs(parts) do
                        local m = p.Parent
                        if m and not seen[m] and m:IsA('Model') and m.PrimaryPart ~= nil and m:FindFirstChild('Humanoid') then
                            seen[m] = true
                            out[#out + 1] = m
                        end
                    end
                    return out
                end
                local function isPlayerish(m)
                    if Players:GetPlayerFromCharacter(m) then return true end
                    local co = m:FindFirstChild('Clone_Owner') -- a player's clone (check_victim :844-850)
                    return co ~= nil and co:IsA('StringValue') and co.Value ~= LP.Name and Players:FindFirstChild(co.Value) ~= nil
                end
                local function vmin(a, b) return V3(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z)) end
                local function vmax(a, b) return V3(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z)) end
                -- Boxes built for one pose share its yaw frame: intersect (cover = false) or
                -- cover their extents in the first box's frame, then shrink / pad each face
                -- by the Vector3 pad.
                local function merge(list, cover, pad)
                    local f0 = list[1][1]
                    local lo, hi
                    for _, b in ipairs(list) do
                        local c, h = f0:PointToObjectSpace(b[1].Position), b[2] / 2
                        if not lo then
                            lo, hi = c - h, c + h
                        elseif cover then
                            lo, hi = vmin(lo, c - h), vmax(hi, c + h)
                        else
                            lo, hi = vmax(lo, c - h), vmin(hi, c + h)
                        end
                    end
                    if cover then lo, hi = lo - pad, hi + pad else lo, hi = lo + pad, hi - pad end
                    local size = hi - lo
                    if size.X < 0.2 or size.Y < 0.2 or size.Z < 0.2 then return nil, nil end
                    return f0 * CFrame.new((lo + hi) / 2), size
                end
                -- One of OUR boxes in the identity pose (upright at the origin, facing -Z).
                -- ext 0 with no reach bonus = the server aims along a zero vector (:396-402),
                -- so its facing is undefined: it becomes a facing-free square (inside every
                -- rotation of it when intersecting, around every rotation when covering).
                local function poseBox(pp, c, e, floor, own, cover)
                    local cf, size = S.m1BoxAt(CFrame.new(), pp, c, false, e, floor, own)
                    if not (e <= 0 and reachU1(pp or {}, c, floor) == 0) then return { cf, size } end
                    local zo = math.abs(pidx(pp and pp.ZOffsets, c) or 0)
                    local hw, hd = size.X / 2, size.Z / 2
                    local half
                    if cover then
                        half = math.sqrt(hw * hw + hd * hd) + zo
                    else
                        half = math.max(0.1, (math.min(hw, hd) - zo) / math.sqrt(2))
                    end
                    return { CFrame.new(0, -1 + (pidx(pp and pp.YOffsets, c) or 0), 0), V3(half * 2, size.Y, half * 2) }
                end
                -- Pose-relative templates, for every last_magasd the server may use (exts):
                --  N = the hit we throw next (+ hit 7 if it is the air finisher), no Widths,
                --      shrunk by margin (flat)                        -> the count
                --  G = inside EVERY combo's box (a spot is held for many swings)  -> target must be in it
                --  U = anything ANY combo (and hit 7) can touch, Widths kept, padded -> player / punisher veto
                local function templates(pp, nextC, margin, floor, exts, air)
                    local mx = math.clamp(tonumber(pp and pp.Max) or 5, 1, 7)
                    local nC, gC, uC = { nextC }, {}, {}
                    if air and nextC == mx then nC[2] = 7 end
                    for c = 1, mx do gC[#gC + 1] = c; uC[#uC + 1] = c end
                    if air then gC[#gC + 1] = 7 end
                    uC[#uC + 1] = 7
                    local nList, gList, uList = {}, {}, {}
                    for _, e in ipairs(exts) do
                        for _, c in ipairs(nC) do nList[#nList + 1] = poseBox(pp, c, e, floor, true, false) end
                        for _, c in ipairs(gC) do gList[#gList + 1] = poseBox(pp, c, e, floor, true, false) end
                        for _, c in ipairs(uC) do uList[#uList + 1] = poseBox(pp, c, e, floor, false, true) end
                    end
                    local shrink = V3(margin, 0.1, margin) -- mobs drift sideways; our height is exact
                    local nL, nS = merge(nList, false, shrink)
                    local gL, gS = merge(gList, false, shrink)
                    local uL, uS = merge(uList, true, V3(0.75, 0.75, 0.75))
                    return nL, nS, gL, gS, uL, uS
                end
                -- Score one pose: mobs its box hits (target included), or nil + why.
                -- fatal = don't swing from here at all (player / punishing mob in reach).
                -- alt = a Kill Aura spot (not the farm's own): also refuses off-limits mobs.
                local function evalPose(ctx, pos, dir, needTarget, alt)
                    local cf = CFrame.lookAt(pos, pos + dir)
                    local veto
                    for _, m in ipairs(modelsIn(cf * ctx.uL, ctx.uS, OPH)) do
                        if m ~= ctx.me and m ~= ctx.target then
                            if isPlayerish(m) then
                                if Toggles.SLKANoPvP.Value then return nil, 'player in box', true end
                            elseif m:GetAttribute('IsMob') then
                                if Toggles.SLKADefense.Value then
                                    local k, why = ctx.def(m)
                                    if k == 'punish' then return nil, 'mob ' .. tostring(why), true end
                                end
                                if alt and not veto and offLimits(m) then veto = 'off-limits mob in reach' end
                            end
                        end
                    end
                    if veto then return nil, veto, false end
                    if needTarget and #modelsIn(cf * ctx.gL, ctx.gS, OPT) == 0 then return nil, 'target out of reach', false end
                    local n = 0
                    if ctx.nL then
                        for _, m in ipairs(modelsIn(cf * ctx.nL, ctx.nS, OPH)) do
                            if m == ctx.target then
                                n = n + 1
                            elseif m ~= ctx.me and m:GetAttribute('IsMob') and ctx.countable(m) then
                                n = n + 1
                            end
                        end
                    end
                    if needTarget then n = math.max(n, 1) end
                    return n, nil, false
                end

                -- cur = the pose in use for the current target: pos/dir = a WORLD-anchored Kill
                -- Aura spot (nil = the farm's own spot on the target's head), since = when it
                -- was adopted (1s minimum), switchedAt = last change (the farm snaps there).
                local cur, lastSolve, lastErr = {}, 0, -1e9
                local punishSince, mobPunishSince, playerSince
                S.kaAvoid = setmetatable({}, { __mode = 'k' }) -- target -> os.clock() until which the farm skips it
                S.kaAvoidUntil = 0
                local function solve(target, mroot, baseGoal, baseFlat)
                    local root, me = S.root(), LP.Character
                    if not (root and me and humFolder() and presets()) then return nil end
                    local pp, _, floor = myPreset()
                    local ctx = { me = me, target = target }
                    ctx.nL, ctx.nS, ctx.gL, ctx.gS, ctx.uL, ctx.uS = templates(pp, nextCombo(pp), Options.SLKAMargin.Value, floor, extSet(root), airborne())
                    if not ctx.uL then return nil end
                    OPT.FilterDescendantsInstances = { target }
                    local defC = {}
                    ctx.def = function(m)
                        local d = defC[m]
                        if not d then
                            local k, why = defenseOf(m)
                            d = { k or false, why }
                            defC[m] = d
                        end
                        return d[1] or nil, d[2]
                    end
                    ctx.countable = function(m)
                        local h = m:FindFirstChildOfClass('Humanoid')
                        if not (h and h.Health > 0) then return false end
                        if Toggles.SLKAOnlyWanted.Value and not wantedModel(m) then return false end
                        return ctx.def(m) == nil -- absorbers / punishers never count
                    end
                    local now = os.clock()
                    local baseN, baseWhy, baseFatal = evalPose(ctx, baseGoal, baseFlat, false, false)
                    local res = { n = baseN or 0, hold = baseFatal and baseWhy or nil }
                    local function adopt(pos, dir, n) -- pos nil = the farm's own spot
                        local changed
                        if pos then
                            changed = not (cur.pos and cur.dir) or (flat2(pos) - flat2(cur.pos)).Magnitude > 2
                                or (cur.dir.X * dir.X + cur.dir.Z * dir.Z) < 0.9
                        else
                            changed = cur.pos ~= nil
                        end
                        if changed then cur.since, cur.switchedAt = now, now end
                        cur.pos, cur.dir = pos, pos and dir or nil
                        if pos then
                            res.alt, res.pos, res.ty, res.dir, res.n, res.hold = true, pos, mroot.Position.Y, dir, n, nil
                        end
                        return res
                    end
                    if not (Toggles.SLKAMulti.Value and ctx.nL and ctx.gL) then return adopt(nil) end
                    -- the pack (mobs worth hitting) + every mob box that could reach a spot near it
                    local tpos = mroot.Position
                    local tf = flat2(tpos)
                    local hum = S.hum()
                    local legs = (hum and hum.HipHeight or 2) + root.Size.Y / 2
                    local tweak = Options.SLFarmTweak and Options.SLFarmTweak.Value or 0
                    local radius = Options.SLKARadius.Value
                    local baseDy = baseGoal.Y - tpos.Y -- never sit lower over the pack than the farm sits on the target (Manual / Model size modes)
                    local danger = { { pos = tpos, lo = topRel(mobPreset(target)) + legs + 0.15, r2 = math.huge } }
                    local pack = {}
                    for _, m in ipairs(S.mobs()) do
                        if m.model ~= target then
                            local d = (flat2(m.root.Position) - tf).Magnitude
                            if d <= radius + 40 then
                                local mp = mobPreset(m.model)
                                local r = reachOf(mp, m.root)
                                if d <= radius + r then
                                    danger[#danger + 1] = { pos = m.root.Position, lo = topRel(mp) + legs + 0.15, r2 = r * r }
                                end
                                if d <= radius and ctx.countable(m.model) then pack[#pack + 1] = { p = flat2(m.root.Position), d = d } end
                            end
                        end
                    end
                    table.sort(pack, function(a, b) return a.d < b.d end)
                    while #pack > 4 do table.remove(pack) end
                    -- root height at a spot: feet above every mob box that can reach it (+ tweak),
                    -- and at least the farm's own height over the target
                    local function heightAt(p)
                        local y = -math.huge
                        for _, d in ipairs(danger) do
                            local dx, dz = d.pos.X - p.X, d.pos.Z - p.Z
                            if dx * dx + dz * dz <= d.r2 then y = math.max(y, d.pos.Y + d.lo) end
                        end
                        return math.max(y + tweak, tpos.Y + baseDy)
                    end
                    -- the spot in use, re-checked where it is (world-anchored, not target-relative)
                    local curPos, curN
                    if cur.pos and cur.dir then
                        local p = flat2(cur.pos)
                        curPos = V3(p.X, heightAt(p), p.Z)
                        curN = evalPose(ctx, curPos, cur.dir, true, true)
                    end
                    -- hysteresis: a pose is kept >= 1s unless it turned fatal / lost the target
                    if now - (cur.since or -1e9) < 1 then
                        if curPos and curN then return adopt(curPos, cur.dir, curN) end
                        if not cur.pos and not baseFatal then return adopt(nil) end
                    end
                    -- a walking target (chasing / leashing home): no NEW spot, it would drag us
                    -- along; keep the current one only while it still holds the target
                    if flat2(mroot.AssemblyLinearVelocity).Magnitude > 3 then
                        if curPos and curN and (curN >= 2 or baseFatal) then return adopt(curPos, cur.dir, curN) end
                        return adopt(nil)
                    end
                    -- candidate spots: above the target, the pack centre, target-mob and mob-mob midpoints
                    local pts, aims = { tf }, { tf }
                    if #pack > 0 then
                        local sum = tf
                        for _, e in ipairs(pack) do sum = sum + e.p; aims[#aims + 1] = e.p end
                        local cen = sum / (#pack + 1)
                        pts[#pts + 1] = cen
                        aims[#aims + 1] = cen
                        for i = 1, #pack do
                            pts[#pts + 1] = (tf + pack[i].p) / 2
                            for j = i + 1, #pack do pts[#pts + 1] = (pack[i].p + pack[j].p) / 2 end
                        end
                    end
                    -- cheap pre-score (mob roots vs the N footprint), then real queries on the best 8
                    local half = ctx.nS / 2
                    local bf = flat2(baseFlat)
                    bf = bf.Magnitude > 0.05 and bf.Unit or V3(0, 0, -1)
                    local function inXZ(bcf, p)
                        local q = bcf:PointToObjectSpace(p)
                        return math.abs(q.X) <= half.X + 1 and math.abs(q.Z) <= half.Z + 1
                    end
                    local pre = {}
                    for _, p in ipairs(pts) do
                        local pos = V3(p.X, heightAt(p), p.Z)
                        local move = (pos - root.Position).Magnitude
                        local dirs = { bf }
                        for _, a in ipairs(aims) do
                            local v = a - p
                            if v.Magnitude > 1 then dirs[#dirs + 1] = v.Unit end
                        end
                        for _, dir in ipairs(dirs) do
                            local bcf = CFrame.lookAt(pos, pos + dir) * ctx.nL
                            if inXZ(bcf, tf) then
                                local c = 1
                                for _, e in ipairs(pack) do if inXZ(bcf, e.p) then c = c + 1 end end
                                if c >= 2 or baseFatal then pre[#pre + 1] = { pos = pos, dir = dir, c = c, move = move } end
                            end
                        end
                    end
                    table.sort(pre, function(a, b)
                        if a.c ~= b.c then return a.c > b.c end
                        return a.move < b.move
                    end)
                    local best
                    for i = 1, math.min(#pre, 8) do
                        local c = pre[i]
                        local n = evalPose(ctx, c.pos, c.dir, true, true)
                        if n and (not best or n > best.n or (n == best.n and c.move < best.move)) then
                            best = { pos = c.pos, dir = c.dir, n = n, move = c.move }
                        end
                    end
                    -- sticky: keep the current spot unless something strictly beats it
                    if curPos and curN and (not best or curN >= best.n) then
                        best = { pos = curPos, dir = cur.dir, n = curN, move = 0, cur = true }
                    end
                    local bn = baseN or 0
                    if best and ((best.n >= 2 and (best.n > bn or (best.cur and best.n >= bn))) or (baseFatal and best.n >= 1)) then
                        return adopt(best.pos, best.dir, best.n)
                    end
                    return adopt(nil)
                end
                -- Called by the Mob Farm every frame with its own goal/facing (head of the
                -- target). Solves at most 5x/s; returns goal, flat, mobs in box, hold-M1
                -- reason (or nil), snap (true for 0.3s after the solver changed the spot).
                function S.kaPose(target, mroot, goal, flat)
                    if not (Toggles.SLKAMulti.Value or Toggles.SLKADefense.Value or Toggles.SLKANoPvP.Value) then
                        cur = {}
                        return goal, flat, 0, nil, false
                    end
                    local now = os.clock()
                    if cur.target ~= target then
                        cur = { target = target }
                        lastSolve, punishSince, mobPunishSince, playerSince = 0, nil, nil, nil
                    end
                    local root = S.root()
                    if root and (root.Position - goal).Magnitude < 45 then
                        if now - lastSolve >= 0.2 then
                            lastSolve = now
                            local ok, res = pcall(solve, target, mroot, goal, flat)
                            cur.res = (ok and type(res) == 'table') and res or nil
                            if not ok and now - lastErr > 5 then lastErr = now; S.setText(statLbl, 'Kill Aura error: ' .. tostring(res)) end
                        end
                    else
                        cur.res, cur.pos, cur.dir, cur.since = nil, nil, nil, nil
                    end
                    local res = cur.res
                    local g, f, n, hold = goal, flat, 0, nil
                    if res then
                        n, hold = res.n or 0, res.hold
                        if res.alt and res.pos and res.dir then
                            -- world-anchored spot; only its height follows the target
                            g, f = V3(res.pos.X, mroot.Position.Y + (res.pos.Y - res.ty), res.pos.Z), res.dir
                        end
                    end
                    -- Caps, so a state nothing clears (NpcCounter only goes when a hit triggers
                    -- it, Checker.lua:935-972) can never freeze the farm: a punishing neighbour
                    -- gets 2s, then one swing takes its counter (Auto Parry / skill dodge cover the
                    -- riposte). Players are never swung into; after 5s the farm skips this target
                    -- for 20s (pick() and the farm loop read S.kaAvoid).
                    if hold ~= nil and tostring(hold):sub(1, 4) == 'mob ' then
                        mobPunishSince = mobPunishSince or now
                        if now - mobPunishSince >= 2 then hold = nil end
                    else
                        mobPunishSince = nil
                    end
                    if hold == 'player in box' then
                        playerSince = playerSince or now
                        if now - playerSince >= 5 then
                            S.kaAvoid[target] = now + 20
                            S.kaAvoidUntil = now + 20
                        end
                    else
                        playerSince = nil
                    end
                    if Toggles.SLKADefense.Value then
                        local k, why = defenseOf(target)
                        if k == 'punish' then
                            punishSince = punishSince or now
                            if now - punishSince < 2 then hold = hold or ('target ' .. tostring(why)) end
                        else
                            punishSince = nil -- i-frames / Dodge charges: keep swinging (costs nothing, burns the charges)
                        end
                    else
                        punishSince = nil
                    end
                    return g, f, n, hold, now - (cur.switchedAt or -1e9) < 0.3
                end

                -- ---- hit check: did one swing really damage several mobs? ----------------
                -- Ledger = <mob>.DMG.<our name>.Value, a running damage total created on the
                -- first hit; fallback: DMG attrs LastAttacker == us and LastAttacked moved.
                -- Looked up fresh every time (DMG can be created / re-created).
                local hist, hIdx, lastKey = {}, 0, nil
                local function ledger(model)
                    local d = valuesOf(model):FindFirstChild('DMG')
                    if not d then return 0, 0, nil end
                    local e = d:FindFirstChild(LP.Name)
                    local v = (e and e:IsA('ValueBase')) and tonumber(e.Value) or 0
                    return v or 0, tonumber(d:GetAttribute('LastAttacked')) or 0, d:GetAttribute('LastAttacker')
                end
                local function record(pred, hit)
                    hIdx = hIdx % 40 + 1
                    hist[hIdx] = { pred, hit }
                    local sw, landed, mobs, boxed = 0, 0, 0, 0
                    for _, h in pairs(hist) do
                        sw = sw + 1
                        boxed = boxed + h[1]
                        if h[2] > 0 then landed = landed + 1; mobs = mobs + h[2] end
                    end
                    local avg = landed > 0 and mobs / landed or 0
                    S.kaAvg = avg
                    S.kaStat = landed > 0 and ('  %.2f mobs/hit'):format(avg) or ''
                    S.setText(statLbl, ('Last %d swings: %d landed, avg %.2f mobs/hit (box predicted %.2f; checked on the DMG ledger)'):format(sw, landed, avg, boxed / math.max(sw, 1)))
                end
                box:AddButton({ Text = 'Reset hit check', Func = function()
                    hist, hIdx, S.kaStat, S.kaAvg = {}, 0, '', nil
                    S.setText(statLbl, 'Hit check: waiting for farm swings')
                end })
                -- A new punch = ComboTrackerClient.Time changes (CU/Combat.lua:152-163; fallback
                -- Combat_presets.Last_Punched). Watch every mob the swing could touch across a
                -- one-swing-wide window centred on when its damage should replicate (hit time
                -- + round trip), so back-to-back swings (~0.26s apart) are not double counted.
                htrack(RunService.Heartbeat:Connect(function()
                    local root = S.root()
                    if S.farmLocked and root and lmOf(root) >= 1 then lmProven = true end
                    local last, at = comboTracker()
                    if at == nil or at == lastKey then return end
                    local first = lastKey == nil
                    lastKey = at
                    if first or not S.farmLocked then return end
                    if not (root and humFolder() and presets()) then return end
                    local pp, _, floor = myPreset()
                    local combo = math.max(1, tonumber(last) or 1)
                    local mx = math.clamp(tonumber(pp and pp.Max) or 5, 1, 7)
                    if combo == mx and airborne() then combo = 7 end -- the air finisher (Main_Combat_Script_Client.lua:115-117)
                    local e = math.max(1, math.min(lmOf(root), 7))
                    local ok, cf, size = pcall(S.m1BoxAt, root.CFrame, pp, combo, false, e, floor, true)
                    local ok7, cf7, size7 = pcall(S.m1BoxAt, root.CFrame, pp, 7, false, math.max(e, 3), floor)
                    if not (ok and ok7) then return end
                    local pred = 0
                    for _, m in ipairs(modelsIn(cf, size, OPH)) do
                        if m ~= LP.Character and m:GetAttribute('IsMob') then pred = pred + 1 end
                    end
                    local watch = {}
                    for _, m in ipairs(modelsIn(cf7, size7 + V3(4, 4, 4), OPH)) do
                        if m ~= LP.Character and m:GetAttribute('IsMob') then watch[#watch + 1] = m end
                    end
                    if #watch == 0 then return end
                    local lead = math.max(0, S.swingTiming(pp, combo, false) + S.pingSec() - 0.13)
                    task.delay(lead, function()
                        local before = {}
                        for i, m in ipairs(watch) do
                            if m.Parent then
                                local v, la = ledger(m)
                                before[i] = { v, la }
                            end
                        end
                        task.wait(0.26)
                        local hit = 0
                        for i, m in ipairs(watch) do
                            local b = before[i]
                            if b and m.Parent then
                                local v, la, who = ledger(m)
                                if v > b[1] + 1e-3 or (who == LP.Name and la > b[2]) then hit = hit + 1 end
                            end
                        end
                        record(pred, hit)
                    end)
                end))
            end)()

            -- ================================================================
            -- AUTO QUEST FARM: best kill quest for your level -> farm -> repeat
            -- ================================================================
            -- Kill quests (Category "Combat") from Ouwland/Content/*/Quests. Accept =
            -- SignalEvent "AddQuest"(<answer text>) - the exact call the dialogue
            -- makes. Server rules (Quests.lua): 1 Combat quest at a time, 30s
            -- between accepts, Requirements.Level (= Data.Exp.Goal / expPerLevel).
            -- Abandon = SignalEvent "RemoveQuest"(<quest folder name>) (the quest
            -- card's X button). Kills are credited server-side; completion removes
            -- the quest from Data.slots.SlotN.Quests.Holder.
            ;(function()
                local V = Vector3.new
                -- Kept in level order: Auto walks it top-down. boss = its alt (mob
                -- quest from the same NPC) is farmed while the boss is respawning.
                local QUESTS = {
                    { l = 'Krue - 3 Bandits',                       key = 'Ill take 3 bandits',                    npc = 'Krue',                 at = V(-425.5, 1243.5, -952.5),   mob = 'Bandit',               camp = V(-296.7, 1224.2, -1022.2) },
                    { l = 'Krue - Bandit boss Zuko (Lv 7)',         key = 'Ill take the bandit boss(Lv 7)',        npc = 'Krue',                 at = V(-425.5, 1243.5, -952.5),   mob = 'Zuko',                 camp = V(-296.7, 1224.2, -1022.2), boss = 'Ill take 3 bandits' },
                    { l = 'Tom - 4 Bear Cubs (Lv 10)',              key = 'Ill drive the bears back(Lv 10)',       npc = 'Tom',                  at = V(507.2, 1121.4, -970.2),    mob = 'Bear Cub',             camp = V(540.5, 1121, -1023.5) },
                    { l = 'Tom - Mother Bear (Lv 18)',              key = 'Ill fell the Mother Bear(Lv 18)',       npc = 'Tom',                  at = V(507.2, 1121.4, -970.2),    mob = 'Mother Bear',          camp = V(540.5, 1121, -1023.5),   boss = 'Ill drive the bears back(Lv 10)' },
                    { l = 'Chaka - 4 Kaiden Subordinates (Lv 26)',  key = 'Ill clear out his subordinates(Lv 26)', npc = 'Chaka',                at = V(471, 1146, -1260),         mob = 'Kaiden Subordinate',   camp = V(585.7, 1146.5, -1314.9) },
                    { l = 'Chaka - Kaiden (Lv 34)',                 key = 'Ill deal with Kaiden(Lv 34)',           npc = 'Chaka',                at = V(471, 1146, -1260),         mob = 'Kaiden',               camp = V(585.7, 1146.5, -1314.9), boss = 'Ill clear out his subordinates(Lv 26)' },
                    { l = 'Wagwan - 4 Hoyuzo Guards (Lv 40)',       key = 'I will clear out his guards(Lv 40)',    npc = 'Wagwan',               at = V(723.8, 1019.2, -802),      mob = 'Hoyuzo Subordinate',   camp = V(651, 1001, -1023.3) },
                    { l = 'Rin - Beast Born Demons (Lv 47, night)', key = 'Ill drive them off(Lv 47)',             npc = 'Rin',                  at = V(432.2, 1018, 73.1),        mob = 'Beast Born Demon',     camp = V(170.7, 888.7, 603.5),    night = true },
                    { l = 'Wagwan - Hoyuzo (Lv 50)',                key = 'I will take care of Hoyuzo(Lv 50)',     npc = 'Wagwan',               at = V(723.8, 1019.2, -802),      mob = 'Hoyuzo',               camp = V(746.9, 1001, -1413),     boss = 'I will clear out his guards(Lv 40)' },
                    { l = 'Jugg - 7 Blood Hounded (Lv 62)',         key = 'Ill clear the cave(Lv 62)',             npc = 'Jugg',                 at = V(487.7, 874.1, 1007.8),     mob = 'Blood Hounded Demon',  camp = V(789.3, 830, 927.5) },
                    { l = 'Goro - 6 Lesser Demons (Lv 75)',         key = 'Ill thin them out(Lv 75)',              npc = 'Demon Slayer Goro',    at = V(-872, 234.8, 318.5),       mob = 'Lesser Demon',         camp = V(-675.7, 230.5, 397.1) },
                    { l = 'Mokuro - 6 Mizunoe Slayers (Lv 75)',     key = 'Ill break their watch(Lv 75)',          npc = 'Demon Mokuro',         at = V(-1948.4, 28.4, 374.3),     mob = 'Mizunoe Demon Slayer', camp = V(-1834.1, 31, 487.6) },
                    { l = 'Goro - 7 Greater Demons (Lv 83)',        key = 'Ill go up after the greater ones(Lv 83)', npc = 'Demon Slayer Goro',  at = V(-872, 234.8, 318.5),       mob = 'Greater Demon',        camp = V(-499, 284.8, 528.8) },
                    { l = 'Delroy - 8 Kanoe Slayers (Lv 90)',       key = 'Theyre not welcome here(Lv 90)',        npc = 'Demon Delroy',         at = V(139.6, 1254.2, -1911.3),   mob = 'Kanoe Demon Slayer',   camp = V(283.9, 1302, -2041.2) },
                    { l = 'Tomoi - 8 High Demons (Lv 90)',          key = 'Ill help you defeat them(Lv 90)',       npc = 'Wounded Slayer Tomoi', at = V(485.3, 1222.6, -1813),     mob = 'High Demon',           camp = V(388, 1253.9, -1927.2) },
                    { l = 'Mitsu - 9 Ice Profound (Lv 105)',        key = 'Ill drive back the frost(Lv 105)',      npc = 'Demon Slayer Mitsu',   at = V(-824.3, 1381.5, -2537.8),  mob = 'Ice Profound Demon',   camp = V(-919, 1381.7, -2447.5) },
                    { l = 'Mitsu - 8 Fire Profound (Lv 115)',       key = 'Ill put out the blaze(Lv 115)',         npc = 'Demon Slayer Mitsu',   at = V(-824.3, 1381.5, -2537.8),  mob = 'Fire Profound Demon',  camp = V(-915.7, 1374.2, -2430.4) },
                }
                local AUTO = 'Auto - best for my level'
                local byLabel, byKey, labels = {}, {}, { AUTO }
                for _, q in ipairs(QUESTS) do
                    q.lv = tonumber(q.key:match('%(Lv (%d+)%)')) or 0
                    byLabel[q.l] = q; byKey[q.key] = q; labels[#labels + 1] = q.l
                end
                for _, q in ipairs(QUESTS) do if q.boss then q.alt = byKey[q.boss] end end

                local box = Tabs.Farm:AddLeftGroupbox('Auto Quest Farm')
                box:AddLabel('One switch: picks the best kill quest for your\nlevel, grabs it, farms it (Mob Farm settings), and\nrepeats until a higher one unlocks. Boss quests are\ndone when the boss is up; while it respawns the\nmob quest before it is farmed instead.', true)
                local status = box:AddLabel('Idle')
                local lvLabel = box:AddLabel('Level: ?')
                box:AddToggle('SLAutoQuest', { Text = 'Auto quest farm', Default = false })
                    :AddKeyPicker('SLAutoQuestKey', { Default = 'None', SyncToggleState = true, Mode = 'Toggle', Text = 'Auto quest farm' })
                box:AddDropdown('SLQuest', { Values = labels, Default = 1, Multi = false, AllowNull = false, Text = 'Quest',
                    Tooltip = 'Auto = highest quest your level allows. Pick one to lock it (a boss pick still falls back to its mob quest while the boss is down).' })
                box:AddToggle('SLQuestBoss', { Text = 'Do boss quests when the boss is up', Default = true })
                box:AddDropdown('SLQRank', { Values = { 'Highest level', 'Best EXP/min' }, Default = 1, Multi = false, Text = 'Auto picks by',
                    Tooltip = 'Highest level = the top quest you can take. Best EXP/min = your top 2 quests compete on MEASURED EXP per minute: quest reward + the kills\' own EXP, over how long that quest really took you (accept -> done + the walk back, saved in SlayersHub/quest_times.json). Each is run once to time it before anything is compared; the lower one must win by 10%.' })
                box:AddToggle('SLQCdFarm', { Text = 'Farm through the accept cooldown', Default = true,
                    Tooltip = 'The 30s accept cooldown counts from your last quest accept (and hunt claims share it). When it is still running as a quest finishes (a quick quest, or a hunt claimed mid-quest), keep farming the quest you just finished instead of standing at the NPC, and leave so you arrive as it ends (distance / travel speed + 1s). Quests over 30s long finish with no cooldown left, so it rarely kicks in otherwise.' })
                box:AddToggle('SLQSpawnWait', { Text = 'Wait at the next respawn', Default = true,
                    Tooltip = 'At the camp with every quest mob dead: shows the respawn countdown (slot DespawnedAt + SpawnTime) and waits over the slot that comes back first, never more than 100 studs from the camp. Needs "Travel to the camp" to move you.' })
                box:AddToggle('SLQuestAbandon', { Text = 'Drop a boss quest if the boss dies', Default = true,
                    Tooltip = 'Someone else killed "your" boss: abandon the quest (X on the quest card) and farm the mob quest instead of idling through the respawn.' })
                box:AddToggle('SLQuestTravel', { Text = 'Travel to the camp', Default = true,
                    Tooltip = 'Glide to the quest mob\'s camp when none are loaded around you.' })
                box:AddSlider('SLQuestSpeed', { Text = 'Quest travel speed', Default = 180, Min = 60, Max = 400, Rounding = 0, Suffix = ' studs/s',
                    Tooltip = 'Glide speed for the trips to the NPC / camp. Higher = faster re-grab; lower if you get pulled back.' })
                box:AddSlider('SLQuestStall', { Text = 'Re-grab if stuck for', Default = 150, Min = 0, Max = 600, Rounding = 0, Suffix = ' s',
                    Tooltip = 'If the quest\'s kill counter has not moved for this long, drop it (X on the quest card) and grab it fresh. Also: a quest whose counters are all full but never cleared gets walked back to its NPC. 0 = off.' })

                local function QM() return S.req('CAM.Global.Subsets.Gameplay.Quests') end
                local function questEntry(key) -- the live quest folder in Quests.Holder, if active
                    local slot = S.data()
                    local holder = slot and slot:FindFirstChild('Quests') and slot.Quests:FindFirstChild('Holder')
                    if not holder then return nil end
                    for _, q in ipairs(holder:GetChildren()) do
                        local qs = q:FindFirstChild('QuestString')
                        if (qs and qs.Value == key) or q.Name == key then return q end
                    end
                    return nil
                end
                local function activeQuest()
                    for _, q in ipairs(QUESTS) do
                        local e = questEntry(q.key)
                        if e then return q, e end
                    end
                    return nil
                end
                local function progress(q)
                    local tf = q:FindFirstChild('Tasks') or q
                    local parts = {}
                    for _, t in ipairs(tf:GetChildren()) do
                        local v, mx = S.val(t, 'Value'), S.val(t, 'Max')
                        if v and mx then parts[#parts + 1] = ('%d/%d'):format(v, mx) end
                    end
                    return table.concat(parts, ', ')
                end
                local function npcPrompt(name)
                    local regs = workspace:FindFirstChild('Debree') and workspace.Debree:FindFirstChild('Regions')
                    if not regs then return nil end
                    for _, r in ipairs(regs:GetChildren()) do
                        local st = r:FindFirstChild('StationaryNpcs')
                        local m = st and st:FindFirstChild(name)
                        if m then
                            for _, d in ipairs(m:GetDescendants()) do if d:IsA('ProximityPrompt') then return d end end
                        end
                    end
                    return nil
                end
                local function near(pos, r)
                    local root = S.root()
                    return root ~= nil and (root.Position - pos).Magnitude <= r
                end
                -- Same maths as ItemRequirements: level = Exp.Goal / expPerLevel.
                local function myLevel()
                    local gs = S.req('CAM.Global.gameSettings')
                    local goal = S.val(S.data(), 'Exp', 'Goal')
                    local per = gs and tonumber(gs.expPerLevel)
                    if goal and per and per > 0 then return math.floor(goal / per) end
                    return nil
                end
                -- Quests.CanAddQuest(LP, key, skipCD) decoded (Quests.lua:226-286):
                --   true            -> can accept now
                --   nil             -> requirements fail (Level / Race / Items: ItemRequirements.Passes)
                --   false, 2        -> one-time quest already done
                --   false, 1        -> already holding it
                --   false, false, q -> the category's single slot is taken by quest q
                --   false, true, q  -> 30s accept cooldown (only checked when skipCD ~= true)
                -- Only trusted when the key is registered in Quests.Holder (an unknown key
                -- "passes" as a Combat quest). Returns nil when it can't be checked here.
                local function canAdd(key, skipCD)
                    local m = QM()
                    if not (m and type(m.CanAddQuest) == 'function' and type(m.Holder) == 'table' and m.Holder[key] ~= nil) then
                        return nil, 'quest not registered on this client', 'unknown'
                    end
                    local ok, r, why, held = pcall(m.CanAddQuest, LP, key, skipCD == true)
                    if not ok then return nil, 'CanAddQuest failed', 'unknown' end
                    if r == true then return true, nil, 'ok' end
                    if r == nil then return false, 'requirements not met (level / race / items)', 'req' end
                    if why == 2 then return false, 'one-time quest already done', 'done' end
                    if why == 1 then return false, 'already holding it', 'held' end
                    if why == false then
                        local okC, cat = pcall(m.GetQuestCategory, key)
                        return false, ('another %s quest is active: %s'):format(okC and tostring(cat) or 'Combat', tostring(held)), 'full'
                    end
                    return false, 'accept cooldown', 'cd'
                end
                -- ---- EXP/min ranking (Auto, "Best EXP/min") -------------------------
                -- EXP = Quests.Holder[key].Rewards.Exp + the kills' own EXP (each task's Max
                -- x LiveConfig NpcDataTable[<task Code>].Rewards.Exp; Code = the NPC code
                -- Quests.QuestTask stores). Time = that quest's MEASURED accept -> completion
                -- time (rolling average, kept in SlayersHub/quest_times.json) + the camp ->
                -- NPC walk back, never under Quests.QuestCD. No guessed times: an unmeasured
                -- quest has no rate and choose() runs it once before comparing.
                local TIMES_FILE = 'SlayersHub/quest_times.json'
                local learned, startedAt = {}, {}
                pcall(function()
                    if isfile and readfile and isfile(TIMES_FILE) then
                        local t = HttpService:JSONDecode(readfile(TIMES_FILE))
                        if type(t) == 'table' then
                            for k, v in pairs(t) do if type(k) == 'string' and type(v) == 'number' and v > 0 then learned[k] = v end end
                        end
                    end
                end)
                local function learnDuration(q)
                    local t0 = startedAt[q.key]
                    if not t0 then return end
                    local d = os.clock() - t0
                    if d < 5 or d > 3600 then return end
                    learned[q.key] = learned[q.key] and (learned[q.key] * 0.6 + d * 0.4) or d
                    if writefile then
                        pcall(function()
                            if makefolder and isfolder and not isfolder('SlayersHub') then makefolder('SlayersHub') end
                            writefile(TIMES_FILE, HttpService:JSONEncode(learned))
                        end)
                    end
                end
                local npcTbl, npcAt = nil, -1e9
                local function npcExp(code) -- EXP one kill of this NPC code pays (LiveConfig, re-read every 60s)
                    if os.clock() - npcAt > 60 then
                        npcAt = os.clock()
                        local LC = S.req('CAM.Global.LiveConfig')
                        local ok, t = false, nil
                        if LC and type(LC.get) == 'function' then ok, t = pcall(LC.get, 'NpcDataTable') end
                        npcTbl = (ok and type(t) == 'table') and t or nil
                    end
                    local d = npcTbl and code and npcTbl[code]
                    return (type(d) == 'table' and type(d.Rewards) == 'table' and tonumber(d.Rewards.Exp)) or 0
                end
                local function questExp(q) -- quest reward + the kill EXP of its tasks
                    local m = QM()
                    local def = m and type(m.Holder) == 'table' and m.Holder[q.key]
                    if type(def) ~= 'table' then return math.max(q.lv, 1) * 18 end
                    local xp = type(def.Rewards) == 'table' and tonumber(def.Rewards.Exp) or 0
                    local qi = def.QuestInstance
                    local tasks = typeof(qi) == 'Instance' and qi:FindFirstChild('Tasks')
                    for _, t in ipairs(tasks and tasks:GetChildren() or {}) do
                        xp = xp + (tonumber(S.val(t, 'Max')) or 0) * npcExp(S.val(t, 'Code'))
                    end
                    return xp
                end
                local function questRate(q) -- measured EXP per minute; nil until the quest has been timed
                    local secs = learned[q.key]
                    if not secs then return nil end
                    local m = QM()
                    local back = (q.camp - q.at).Magnitude / math.max(Options.SLQuestSpeed.Value, 1)
                    return questExp(q) / math.max(secs + back, (m and tonumber(m.QuestCD)) or 30) * 60
                end
                local function eligible(q)
                    -- The game's own gate: Quests.CanAddQuest(LP, key, skipCD = true). nil = level /
                    -- Race / item requirements fail (Jugg, Goro, Tomoi want Slayer|Hybrid; Mokuro,
                    -- Delroy Demon|Hybrid), false,2 = one-time quest done. The cooldown is skipped
                    -- here because it only delays an accept (the Book of Guidance filters with the
                    -- cooldown-inclusive call, RecommendedQuest.lua:97). Already holding it / the
                    -- Combat slot being taken still count (tick() reports those).
                    local can, _, kind = canAdd(q.key, true)
                    if can == nil then -- not verifiable on this client: the old level-only check
                        local lv = myLevel()
                        if lv == nil then return q.lv == 0 end
                        return lv >= q.lv
                    end
                    return can == true or kind == 'held' or kind == 'full'
                end
                local function isNight()
                    local DN = S.req('CAM.Global.DayAndNightHandler')
                    if DN and type(DN.IsNight) == 'function' then
                        local ok, r = pcall(DN.IsNight); if ok then return r end
                    end
                    return nil
                end
                local function norm(s) return (tostring(s):lower():gsub('[^%w]', '')) end
                -- 'alive' | 'up' (spawned, not streamed in) | 'night' | seconds to respawn | nil (no BossInfo seen)
                local function bossState(q)
                    local want = norm(q.mob)
                    for _, cfg in ipairs(CS:GetTagged('BossTag')) do
                        local folder = cfg.Parent
                        if folder and norm(folder.Name) == want then
                            for _, c in ipairs(folder:GetChildren()) do
                                if c:IsA('Model') then
                                    local h = c:FindFirstChildOfClass('Humanoid')
                                    if h and h.Health > 0 then return 'alive', cfg end
                                end
                            end
                            local desp = folder:GetAttribute('DespawnedAt')
                            local left = desp and ((cfg:GetAttribute('SpawnTime') or 0) - (workspace:GetServerTimeNow() - desp)) or 0
                            if left > 0 then return left, cfg end
                            if cfg:GetAttribute('OnlyAtNight') and isNight() == false then return 'night', cfg end
                            return 'up', cfg
                        end
                    end
                    return nil
                end
                local function bossReady(q)
                    local st = bossState(q)
                    return st == nil or st == 'alive' or st == 'up' or (type(st) == 'number' and st <= 15)
                end
                -- Which quest to grab next (+ a note for the status line).
                local function resolve(q)
                    if q.boss and not (Toggles.SLQuestBoss.Value and bossReady(q)) and q.alt then
                        local st = bossState(q)
                        local why = type(st) == 'number' and (q.mob .. ' respawns in ' .. S.fmt(st)) or (q.mob .. ' is down')
                        return q.alt, why
                    end
                    return q
                end
                local function choose()
                    local sel = Options.SLQuest.Value
                    if sel and sel ~= AUTO and byLabel[sel] then return resolve(byLabel[sel]) end
                    local night = isNight()
                    if Options.SLQRank.Value ~= 'Best EXP/min' then
                        for i = #QUESTS, 1, -1 do -- highest level first
                            local q = QUESTS[i]
                            if eligible(q) and not (q.night and night == false) then return resolve(q) end
                        end
                        return nil
                    end
                    -- Best EXP/min: the top 2 eligible quests (by level) compete. Each is run and
                    -- timed once before any comparison (never a guess), then the lower one
                    -- must beat the higher one by 10% to be picked.
                    local cands = {}
                    for i = #QUESTS, 1, -1 do
                        local q = QUESTS[i]
                        if eligible(q) and not (q.night and night == false) then
                            local r, why = resolve(q)
                            if not (cands[1] and cands[1].q == r) then cands[#cands + 1] = { q = r, why = why } end
                            if #cands == 2 then break end
                        end
                    end
                    for _, c in ipairs(cands) do
                        if not learned[c.q.key] then return c.q, c.why end -- time it once first
                    end
                    local best = cands[1]
                    local r1, r2 = best and questRate(best.q), cands[2] and questRate(cands[2].q)
                    if r1 and r2 and r2 > r1 * 1.1 then best = cands[2] end
                    if best then return best.q, best.why end
                    return nil
                end
                -- Seconds until the server's 30s accept cooldown clears. Same maths
                -- as Quests.CanAddQuest: QuestCD < Utility.Tick() - Quests.LastTime.
                local function cooldownLeft()
                    local lt = S.val(S.data(), 'Quests', 'LastTime')
                    local U, m = S.req('CAM.Global.Utility'), QM()
                    if not (lt and U and type(U.Tick) == 'function') then return 0 end
                    local ok, now = pcall(U.Tick)
                    if not ok or type(now) ~= 'number' then return 0 end
                    local cd = (m and tonumber(m.QuestCD)) or 30
                    return math.max(0, cd - (now - lt) + 0.25) -- +0.25s slack for the server's clock
                end
                local function running() return Toggles.SLAutoQuest.Value and not S.dead end
                -- ---- spawn-aware waiting ---------------------------------------------
                -- Quest-mob slots = workspace.Humanoids.Regions.<region>.ActiveNpcs.<def.Name>
                -- folders (Regions.lua PrepareRegion; Quantity = that many folders). A dead
                -- slot carries DespawnedAt (GetServerTimeNow epoch, not cleared on respawn)
                -- and returns SpawnTime later: the BossInfo attribute for bosses (the boss
                -- bar's own countdown, BossUI.lua), else the region def's
                -- SendOver.Spawning.SpawnTime (require(ReplicatedStorage.Regions).Regions).
                local afterQ -- the quest we just finished (farmed through the accept cooldown)
                local ourGlide, hoverAt, hoverT = false, nil, 0
                local lastSeen = setmetatable({}, { __mode = 'k' }) -- slot folder -> where its mob last stood
                local spawnDefs = {}
                local function spawningOf(slot) -- that slot's SendOver.Spawning table (cached)
                    local region = slot.Parent and slot.Parent.Parent
                    if not region then return nil end
                    local key = region.Name .. '/' .. slot.Name
                    if spawnDefs[key] == nil then
                        local R = S.req('Regions')
                        if not R then return nil end -- not loaded yet: try again next time
                        spawnDefs[key] = false
                        local reg = type(R.Regions) == 'table' and R.Regions[region.Name]
                        if type(reg) == 'table' and type(reg.Npcs) == 'table' then
                            for _, def in ipairs(reg.Npcs) do
                                if type(def) == 'table' and def.Name == slot.Name and type(def.SendOver) == 'table'
                                    and type(def.SendOver.Spawning) == 'table' then
                                    spawnDefs[key] = def.SendOver.Spawning
                                    break
                                end
                            end
                        end
                    end
                    return spawnDefs[key] or nil
                end
                local function asPos(v)
                    if typeof(v) == 'Vector3' then return v end
                    if typeof(v) == 'CFrame' then return v.Position end
                    return nil
                end
                -- Seconds until a dead slot respawns (<= 0 = due) + where it will stand.
                local function slotEta(slot, now)
                    local bi = slot:FindFirstChild('BossInfo') -- the BossTag config (BossUI.lua reads it the same way)
                    if not bi then for _, c in ipairs(slot:GetChildren()) do if CS:HasTag(c, 'BossTag') then bi = c; break end end end
                    local sp = spawningOf(slot)
                    local st = (bi and tonumber(bi:GetAttribute('SpawnTime'))) or (sp and tonumber(sp.SpawnTime))
                    local desp = tonumber(slot:GetAttribute('DespawnedAt'))
                    if not (st and desp) then return nil end
                    local pos = lastSeen[slot] or (bi and asPos(bi:GetAttribute('Center')))
                    if not pos and sp then
                        local locs = type(sp.Locations) == 'table' and sp.Locations or {}
                        pos = (#locs == 1 and asPos(locs[1])) or asPos(sp.Center) or asPos(locs[1])
                    end
                    return desp + st - now, pos
                end
                local function inCamp(p, camp) -- stay within 100 studs (flat) of the camp
                    local d = Vector3.new(p.X - camp.X, 0, p.Z - camp.Z)
                    if d.Magnitude <= 100 then return p end
                    local c = camp + d.Unit * 100
                    return Vector3.new(c.X, p.Y, c.Z)
                end
                -- Nothing to hit at the camp: wait over the quest-mob slot that comes back
                -- first (or walk toward a loaded one the farm's search range misses).
                -- Returns a status note ('next spawn in 12s', ...) or nil.
                local function spawnWait(q, camp, move)
                    local hs = workspace:FindFirstChild('Humanoids')
                    local regs = hs and hs:FindFirstChild('Regions')
                    if not (regs and camp) then return nil end
                    local want, now, root = norm(q.mob), workspace:GetServerTimeNow(), S.root()
                    local livePos, liveD, eta, etaPos, dead, total = nil, math.huge, math.huge, nil, 0, 0
                    for _, region in ipairs(regs:GetChildren()) do
                        local act = region:FindFirstChild('ActiveNpcs')
                        for _, slot in ipairs(act and act:GetChildren() or {}) do
                            if norm(slot.Name) == want then
                                total = total + 1
                                local live
                                for _, m in ipairs(slot:GetChildren()) do
                                    local h = m:IsA('Model') and m:FindFirstChildOfClass('Humanoid')
                                    local r = h and m:FindFirstChild('HumanoidRootPart')
                                    if r and h.Health > 0 then live = r.Position end
                                end
                                if live then
                                    lastSeen[slot] = live
                                    local d = root and (live - root.Position).Magnitude or 0
                                    if d < liveD then livePos, liveD = live, d end
                                else
                                    dead = dead + 1
                                    local e, p = slotEta(slot, now)
                                    -- long past due with no model = it's up but not loaded / walked
                                    -- off (DespawnedAt is never cleared): nothing to wait for
                                    if e and e > -5 and e < eta then eta, etaPos = (e > 0 and e or 0), p end
                                end
                            end
                        end
                    end
                    if total == 0 then return nil end
                    local goal, note
                    if livePos then
                        -- only walk over if it is really past the farm's search range
                        goal = liveD > Options.SLFarmRange.Value * 0.9 and livePos or nil
                        note = ('%s loaded %.0f studs away'):format(q.mob, liveD)
                    elseif eta < math.huge then
                        goal = etaPos
                        note = eta > 0.5 and ('next spawn in %ds'):format(math.ceil(eta)) or 'spawn due'
                    else
                        return ('%d/%d dead, respawn time unknown'):format(dead, total)
                    end
                    if move and goal and root then
                        goal = inCamp(goal, camp)
                        local hover = goal + Vector3.new(0, 6, 0)
                        -- the farm's own "return to farm spot" now agrees with where we wait
                        S.farmLastPos, S.farmLastMob = goal, S.questMob
                        if (root.Position - hover).Magnitude > 10
                            and (not hoverAt or (hoverAt - hover).Magnitude > 8 or os.clock() - hoverT > 5) then
                            hoverAt, hoverT, ourGlide = hover, os.clock(), true
                            S.glideTo(hover, Options.SLQuestSpeed.Value)
                        end
                    end
                    return note
                end
                local function accept(q, why)
                    S.farmPaused = true
                    S.setText(status, 'Going to ' .. q.npc .. (why and ('  (' .. why .. ')') or ''))
                    S.glideTo(q.at + Vector3.new(0, 3, 0), Options.SLQuestSpeed.Value)
                    local t0 = os.clock()
                    while not near(q.at, 8) and os.clock() - t0 < 90 and running() do task.wait(0.1) end
                    if not near(q.at, 8) then return false, 'could not reach ' .. q.npc end
                    -- Walk there DURING the cooldown, then accept the instant it clears.
                    local left = cooldownLeft()
                    while left > 0 and running() do
                        S.setText(status, ('At %s - accept cooldown %.1fs'):format(q.npc, left))
                        task.wait(math.min(left, 0.25))
                        left = cooldownLeft()
                    end
                    if not running() then return false, 'stopped' end
                    -- The game's own accept gate, cooldown included (what the NPC dialogue
                    -- checks): anything but true = the server refuses, so don't send AddQuest.
                    local can, cwhy, kind = canAdd(q.key, false)
                    local tc = os.clock()
                    while can == false and kind == 'cd' and os.clock() - tc < 3 and running() do
                        task.wait(0.2); can, cwhy, kind = canAdd(q.key, false) -- cooldown clock-edge slack
                    end
                    if can == false then return false, cwhy end
                    -- open the NPC's dialogue prompt first (the legit path), then accept
                    local pp
                    local t1 = os.clock()
                    repeat pp = npcPrompt(q.npc); if not pp then task.wait(0.1) end until pp or os.clock() - t1 > 5
                    if pp and fireproximityprompt then pcall(fireproximityprompt, pp); S.ui(); task.wait(0.3) end
                    S.fire('AddQuest', q.key)
                    local t2 = os.clock()
                    while not questEntry(q.key) and os.clock() - t2 < 3 do task.wait(0.1) end
                    if questEntry(q.key) then return true end
                    return false, 'not accepted'
                end

                local nextTry, lastTravel, lastDrop, done = 0, 0, 0, 0
                local lastActive, dropped = nil, false
                local lastProg, lastProgQ, progAt, lastTurnIn = nil, nil, os.clock(), 0
                local function allDone(q) -- every task Value >= Max (quest finished but still held)
                    local tf = q:FindFirstChild('Tasks'); if not tf then return false end
                    local any = false
                    for _, t in ipairs(tf:GetChildren()) do
                        local v, mx = S.val(t, 'Value'), S.val(t, 'Max')
                        if v and mx then any = true; if v < mx then return false end end
                    end
                    return any
                end
                local function tick()
                    S.ui()
                    local lv = myLevel()
                    S.setText(lvLabel, 'Level: ' .. (lv and tostring(lv) or '?') .. ('   |   quests done: %d'):format(done))
                    if not Toggles.SLAutoQuest.Value then return end
                    local cur, entry = activeQuest()
                    if cur then
                        lastActive, S.questAcceptPending = cur, false
                        S.questMob = cur.mob
                        local camp, note = cur.camp, ''
                        if cur.boss then
                            local st, cfg = bossState(cur)
                            local c = cfg and cfg:GetAttribute('Center')
                            if typeof(c) == 'Vector3' then camp = c end
                            if type(st) == 'number' then
                                note = '  - respawns in ' .. S.fmt(st)
                                if st > 45 and Toggles.SLQuestAbandon.Value and os.clock() - lastDrop > 10 then
                                    lastDrop = os.clock(); dropped = true
                                    S.fire('RemoveQuest', entry.Name)
                                    note = '  - boss died, dropping quest'
                                end
                            end
                        end
                        local prog = progress(entry)
                        if prog ~= lastProg or cur ~= lastProgQ then lastProg, lastProgQ, progAt = prog, cur, os.clock() end
                        if allDone(entry) then
                            -- counters full but the server hasn't cleared it: stop farming
                            -- and talk to the quest NPC (the legit hand-in path)
                            S.questMob = '\0none' -- matches no mob, so the farm idles
                            if os.clock() - lastTurnIn > 15 then
                                lastTurnIn = os.clock()
                                S.farmPaused = true
                                S.setText(status, 'Quest complete - handing in to ' .. cur.npc)
                                S.glideTo(cur.at + Vector3.new(0, 3, 0), Options.SLQuestSpeed.Value)
                                local t0 = os.clock()
                                while not near(cur.at, 8) and os.clock() - t0 < 60 and running() do task.wait(0.1) end
                                local pp = npcPrompt(cur.npc)
                                if pp and fireproximityprompt then pcall(fireproximityprompt, pp); S.ui() end
                                task.wait(1)
                                S.farmPaused = false
                            end
                            return
                        end
                        if S.huntMob then progAt = os.clock() end -- fighting a claimed hunt's boss: not stuck
                        local stall = Options.SLQuestStall.Value
                        if stall > 0 and os.clock() - progAt > stall and os.clock() - lastDrop > 10 then
                            lastDrop = os.clock(); dropped = true; progAt = os.clock()
                            S.fire('RemoveQuest', entry.Name)
                            S.setText(status, ('No progress for %ds - dropping %s to re-grab'):format(stall, cur.mob))
                            return
                        end
                        if ourGlide and S.farmHasTarget then ourGlide, hoverAt = false, nil; S.stopGlide() end -- the farm drives now
                        local sw
                        if not S.farmHasTarget and Toggles.SLQSpawnWait.Value and near(camp, 150) then
                            -- at the camp with nothing to hit: respawn countdown + wait over the next slot
                            sw = spawnWait(cur, camp, Toggles.SLQuestTravel.Value)
                        elseif Toggles.SLQuestTravel.Value and not S.farmHasTarget and not near(camp, 120) and os.clock() - lastTravel > 10 then
                            -- no quest mob loaded near us: head to its camp (every 10s at most)
                            lastTravel, ourGlide = os.clock(), true
                            S.glideTo(camp + Vector3.new(0, 5, 0), Options.SLQuestSpeed.Value)
                        end
                        S.setText(status, ('Active: %s  %s%s  (idle %ds)%s'):format(cur.mob, prog, note,
                            math.floor(os.clock() - progAt), sw and ('  - ' .. sw) or ''))
                        return
                    end
                    if lastActive then -- it vanished = completed (unless we dropped it)
                        if not dropped then
                            done = done + 1
                            learnDuration(lastActive)
                            -- farm this camp through a still-running accept cooldown (a finished
                            -- boss quest's boss is dead: its camp's mob quest instead)
                            afterQ = (lastActive.boss and lastActive.alt) or lastActive
                        end
                        startedAt[lastActive.key] = nil
                        lastActive, dropped = nil, false
                    end
                    local q, why = choose()
                    if not q then S.questMob, S.questAcceptPending = nil, false; S.setText(status, 'No quest available for your level'); return end
                    if ourGlide and S.farmHasTarget then ourGlide, hoverAt = false, nil; S.stopGlide() end
                    -- No NPC trip can fix these: the Combat slot is held by a quest this list
                    -- doesn't know, or the picked quest fails its requirements (race / level /
                    -- items) or is a one-time quest already done. Keep farming meanwhile.
                    local _, blockWhy, kind = canAdd(q.key, true)
                    if kind == 'full' or kind == 'req' or kind == 'done' then
                        S.questMob, S.questAcceptPending = (afterQ or q).mob, false
                        S.setText(status, kind == 'full' and (blockWhy .. ' - finish or abandon it') or (q.l .. ': ' .. blockWhy))
                        return
                    end
                    S.questAcceptPending = true -- an AddQuest is coming: Boss Hunts holds its auto-claim
                    -- The 30s accept cooldown (Quests.QuestCD, shared by every category) counts
                    -- from the last accept. If it still runs as a quest finishes (a quick quest,
                    -- a hunt claimed mid-quest), keep farming the quest we just finished and
                    -- leave for the NPC only when the cooldown ends about as we arrive.
                    local left, r0 = cooldownLeft(), S.root()
                    local trip = r0 and (r0.Position - q.at).Magnitude / math.max(Options.SLQuestSpeed.Value, 1) or 0
                    if Toggles.SLQCdFarm.Value and left > trip + 1 and (afterQ or S.farmHasTarget) then
                        local fq = afterQ or q
                        S.questMob = fq.mob
                        local sw
                        if not S.farmHasTarget and Toggles.SLQSpawnWait.Value and near(fq.camp, 150) then
                            sw = spawnWait(fq, fq.camp, Toggles.SLQuestTravel.Value)
                        elseif Toggles.SLQuestTravel.Value and not S.farmHasTarget and not near(fq.camp, 120) and os.clock() - lastTravel > 10 then
                            -- e.g. a finished boss quest: its mob camp can be ~400 studs from the boss
                            lastTravel, ourGlide = os.clock(), true
                            S.glideTo(fq.camp + Vector3.new(0, 5, 0), Options.SLQuestSpeed.Value)
                        end
                        S.setText(status, ('Cooldown %.0fs - farming %s%s, then %s'):format(left, fq.mob,
                            sw and ('  (' .. sw .. ')') or '', q.l))
                        return
                    end
                    S.questMob = q.mob
                    if os.clock() < nextTry then return end
                    local ok, res, err = pcall(accept, q, why)
                    S.farmPaused = false
                    if ok and res then
                        startedAt[q.key], afterQ = os.clock(), nil
                        local rate = questRate(q)
                        S.setText(status, 'Accepted: ' .. q.l .. (rate and ('  (~%.0f EXP/min measured)'):format(rate) or '  (timing this run)'))
                        nextTry = os.clock() + 2
                    else
                        S.setText(status, ('Not accepted (%s) - retrying in 5s'):format(tostring(ok and err or res)))
                        nextTry = os.clock() + 5
                    end
                end
                task.spawn(function()
                    while not S.dead do
                        task.wait(0.25) -- notice completion fast
                        local ok = pcall(tick)
                        if not ok then S.farmPaused = false end -- never leave the farm frozen
                    end
                end)
                Toggles.SLAutoQuest:OnChanged(function()
                    if not Toggles.SLAutoQuest.Value then
                        S.questMob = nil; S.farmPaused = false; S.stopGlide(); S.setText(status, 'Idle')
                        afterQ, hoverAt, ourGlide, S.questAcceptPending = nil, nil, false, nil
                        table.clear(startedAt) -- time spent with Auto off is not quest time
                    end
                end)
            end)()

            -- ================================================================
            -- EXP METER: EXP/hour + levels/hour over a rolling 5-minute window
            -- ================================================================
            -- Data.slots.SlotN.Exp: Current = progress inside the level, Goal = that
            -- level's cost = level x gameSettings.expPerLevel (ItemRequirements reads
            -- level = Goal / expPerLevel; the admin "Give Level" command costs level k
            -- at k x expPerLevel). So lifetime EXP = per*L*(L-1)/2 + Current and level-ups
            -- never break the maths. Rates are RAW EXP - the numbers quest rewards and
            -- hunt cards use. The HUD prints EXP divided by Multipliers.LevelCostFactor
            -- (HudBottomLeft/EXP.lua; 3 below Lv45, 2.2 at Lv55-125): shown in brackets.
            ;(function()
                local box = Tabs.Farm:AddLeftGroupbox('EXP Meter')
                local lbl = box:AddLabel('Measuring...', true)
                local WINDOW = 300
                local samples, slotRef, sess = {}, nil, nil
                box:AddButton({ Text = 'Reset meter', Func = function()
                    samples, sess = {}, nil
                    S.setText(lbl, 'Measuring...')
                end })
                local function snap()
                    local slot = S.data()
                    local cur, goal = tonumber(S.val(slot, 'Exp', 'Current')), tonumber(S.val(slot, 'Exp', 'Goal'))
                    local gs = S.req('CAM.Global.gameSettings')
                    local per = gs and tonumber(gs.expPerLevel)
                    if not (slot and cur and goal and goal > 0 and per and per > 0) then return nil end
                    local lv = math.floor(goal / per + 1e-6)
                    return { t = os.clock(), slot = slot, lv = lv, cur = cur, goal = goal,
                        total = per * lv * (lv - 1) / 2 + cur, frac = lv + cur / goal }
                end
                local function hudDiv(lv) -- the HUD's EXP divisor at this level
                    local M = S.req('CAM.Global.Multipliers')
                    if M and type(M.LevelCostFactor) == 'function' then
                        local ok, f = pcall(M.LevelCostFactor, lv)
                        if ok and type(f) == 'number' and f > 0 then return f end
                    end
                    return 1
                end
                local function num(n)
                    local a = math.abs(n)
                    if a >= 1e6 then return ('%.2fM'):format(n / 1e6) end
                    if a >= 1e4 then return ('%.1fk'):format(n / 1e3) end
                    return ('%d'):format(math.floor(n + 0.5))
                end
                local function update()
                    local s = snap()
                    if not s then return end
                    local last = samples[#samples]
                    if s.slot ~= slotRef or (last and s.total < last.total) then -- slot swap / data reset: start over
                        samples, sess, slotRef = {}, nil, s.slot
                    end
                    samples[#samples + 1] = s
                    sess = sess or s
                    while #samples > 2 and s.t - samples[1].t > WINDOW do table.remove(samples, 1) end
                    local a = samples[1]
                    local dt = s.t - a.t
                    if dt < 20 then S.setText(lbl, ('Measuring... %ds'):format(math.floor(dt))); return end
                    local f = hudDiv(s.lv)
                    local rawH = (s.total - a.total) / dt * 3600
                    local lvH = (s.frac - a.frac) / dt * 3600
                    local toNext = rawH > 0 and (s.goal - s.cur) / rawH * 3600 or nil
                    local gained = s.total - sess.total
                    S.setText(lbl, ('EXP/h: %s  (HUD %s)   Levels/h: %.2f\nNext level in %s  (last %s)\nSession: +%s EXP (HUD %s), +%.2f lv in %s'):format(
                        num(rawH), num(rawH / f), lvH, toNext and S.fmt(toNext) or '-', S.fmt(dt),
                        num(gained), num(gained / f), s.frac - sess.frac, S.fmt(s.t - sess.t)))
                end
                task.spawn(function()
                    while not S.dead do
                        task.wait(1)
                        pcall(update)
                    end
                end)
            end)()

            -- ================================================================
            -- AUTO TRAINING (quest credit; minigames are client-judged)
            -- ================================================================
            ;(function()
                local box = Tabs.Farm:AddRightGroupbox('Auto Training')
                box:AddLabel('Training here only gives QUEST credit (no stats).\nEvery minigame is judged on your client; only\n"passed: true/false" is sent. Start a station (or use\nthe button); this waits a believable time, drops the\ngame\'s own "failed" report and sends a pass.', true)
                local status = box:AddLabel('Idle')
                box:AddToggle('SLAutoTrain', { Text = 'Auto-complete training', Default = false,
                    Tooltip = 'Pushups, Squat, Meditation, Target Shooting, Cup Game, Boulder Split: pass after a legit-looking time. Boulder Push: walks the boulder to its goal (the server checks the boulder touching the goal).' })
                box:AddSlider('SLTrainScale', { Text = 'Time scale', Default = 1, Min = 0.6, Max = 2, Rounding = 2, Suffix = 'x',
                    Tooltip = '1x = a fast legit run. Lower = faster but less believable.' })
                local TIME = { Pushups = 12, Squat = 10, Meditation = 22, ['Target Shooting'] = 25, ['Cup Game'] = 55, ['Boulder Split'] = 31.5 }
                local active -- the live Training folder we're passing
                table.insert(S.dropRules, function(a1, a2, a3)
                    return a1 == 'training_signaler' and a2 == 'Stop' and a3 ~= true
                        and Toggles.SLAutoTrain.Value and active ~= nil and active.Parent ~= nil
                end)
                local function onTraining(f)
                    if f.Name ~= 'Training' or not Toggles.SLAutoTrain.Value then return end
                    local t0 = os.clock()
                    while f.Parent and f:GetAttribute('Type') == nil and os.clock() - t0 < 2 do task.wait(0.1) end
                    local kind = f:GetAttribute('Type')
                    if TIME[kind] then
                        active = f
                        local wait = TIME[kind] * Options.SLTrainScale.Value + math.random() * 2
                        status:SetText(('%s: passing in %.0fs'):format(kind, wait))
                        task.delay(wait, function()
                            if f.Parent and Toggles.SLAutoTrain.Value then
                                S.fire('training_signaler', 'Stop', true)
                                status:SetText(kind .. ': sent PASS')
                            end
                            if active == f then active = nil end
                        end)
                    elseif kind == 'Boulder Push' then
                        local goal = f:GetAttribute('GoalPosition')
                        if typeof(goal) == 'Vector3' then
                            status:SetText('Boulder Push: walking the boulder to the goal')
                            S.glideTo(goal, 15, 'boulder goal')
                        else
                            status:SetText('Boulder Push: no GoalPosition attribute - push it yourself')
                        end
                    else
                        status:SetText(tostring(kind) .. ': not automated')
                    end
                end
                box:AddButton({ Text = 'Start nearest station', Func = function()
                    local root, tr = S.root(), workspace:FindFirstChild('Training')
                    if not (root and tr) then Library:Notify('No Training stations loaded here', 3); return end
                    local best, bestD
                    for _, pp in ipairs(tr:GetDescendants()) do
                        if pp:IsA('ProximityPrompt') and pp.Enabled then
                            local pos = S.posOf(pp.Parent)
                            if pos then
                                local d = (pos - root.Position).Magnitude
                                if not bestD or d < bestD then best, bestD = pp, d end
                            end
                        end
                    end
                    if not best then Library:Notify('No training prompt found', 3); return end
                    if bestD > best.MaxActivationDistance + 2 then
                        Library:Notify(('Nearest station is %.0f studs away - get within %.0f'):format(bestD, best.MaxActivationDistance), 3); return
                    end
                    if fireproximityprompt then pcall(fireproximityprompt, best) else Library:Notify('Executor lacks fireproximityprompt', 3) end
                end })
                task.spawn(function()
                    local ps = RepStorage:WaitForChild('Player_Service', 60)
                    local vals = ps and ps:WaitForChild('Values', 60)
                    local v = vals and vals:WaitForChild(LP.Name, 60)
                    if not v then return end
                    htrack(v.ChildAdded:Connect(function(c) task.spawn(onTraining, c) end))
                    htrack(v.ChildRemoved:Connect(function(c)
                        if c.Name == 'Training' then
                            if active == c then active = nil end
                            status:SetText('Idle')
                        end
                    end))
                end)
            end)()

            -- ================================================================
            -- AUTO FISH (the bite verdict is client-reported)
            -- ================================================================
            ;(function()
                local box = Tabs.Farm:AddRightGroupbox('Auto Fish')
                box:AddLabel('Rare Fishing RodServer trusts your client\'s reel\nresult (BiteVerdict = your true/false). Equip a rod\nand stand on dry ground next to water. The final\ncatch roll (CatchChance / loot) stays server-side.', true)
                local status = box:AddLabel('Idle')
                box:AddToggle('SLAutoFish', { Text = 'Auto-win bites', Default = false,
                    Tooltip = 'On each bite, report a successful reel after the reaction delay below (the game\'s own reel bar fails after ~3s of no input).' })
                box:AddToggle('SLAutoCast', { Text = 'Auto cast / recast', Default = true,
                    Tooltip = 'Casts at the nearest water in front of you (within ~32 studs) whenever the rod is idle.' })
                box:AddSlider('SLFishMin', { Text = 'Reel reaction min', Default = 1.1, Min = 0.4, Max = 2.8, Rounding = 1, Suffix = ' s' })
                box:AddSlider('SLFishMax', { Text = 'Reel reaction max', Default = 2.0, Min = 0.5, Max = 2.9, Rounding = 1, Suffix = ' s' })
                local state, stateAt, caught = 'idle', 0, 0
                local function rodEquipped()
                    local c = LP.Character; local t = c and c:FindFirstChildOfClass('Tool')
                    return t ~= nil and t.Name:find('Fishing Rod') ~= nil
                end
                -- Water = parts tagged SwimParts (same filter the rod uses).
                local function waterPos()
                    local root = S.root(); if not root then return nil end
                    local parts = {}
                    for _, v in ipairs(CS:GetTagged('SwimParts')) do parts[#parts + 1] = v.Parent or v end
                    if #parts == 0 then return nil end
                    local rp = RaycastParams.new()
                    rp.FilterType = Enum.RaycastFilterType.Include
                    rp.FilterDescendantsInstances = parts
                    local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
                    if look.Magnitude < 0.1 then look = Vector3.new(0, 0, -1) end
                    look = look.Unit
                    for r = 8, 32, 4 do
                        for a = 0, 330, 30 do
                            local dir = CFrame.Angles(0, math.rad(a), 0) * look
                            local p = root.Position + dir * r
                            local hit = workspace:Raycast(p + Vector3.new(0, 50, 0), Vector3.new(0, -120, 0), rp)
                            if hit then return hit.Position end
                        end
                    end
                    return nil
                end
                local function click(pos)
                    S.fire('Tool_Mouse', 'Down', pos)
                    task.wait(0.12)
                    S.fire('Tool_Mouse', 'Up', pos)
                end
                task.spawn(function()
                    local holder = S.find(PORTAL)
                    local pe = holder and holder:WaitForChild('Event', 60)
                    if not pe then return end
                    htrack(pe.OnClientEvent:Connect(function(name, msg, token)
                        if name ~= 'FishingRod' or not Toggles.SLAutoFish.Value then return end
                        if msg == 'Bite' then
                            state, stateAt = 'bite', os.clock()
                            local lo = math.min(Options.SLFishMin.Value, Options.SLFishMax.Value)
                            local hi = math.max(Options.SLFishMin.Value, Options.SLFishMax.Value)
                            local wait = lo + math.random() * (hi - lo)
                            status:SetText(('Bite! reeling in %.1fs'):format(wait))
                            task.delay(wait, function()
                                if not Toggles.SLAutoFish.Value then return end
                                S.portal('FishingRod', token, true) -- the exact report the reel minigame sends
                                caught = caught + 1
                                state, stateAt = 'reel', os.clock()
                                status:SetText(('Reeled - %d this session'):format(caught))
                            end)
                        elseif msg == 'BiteMissed' then
                            status:SetText('Fish slipped (server catch roll)')
                        elseif msg == 'BiteCancel' then
                            state, stateAt = 'idle', os.clock()
                        end
                    end))
                end)
                local acc = 0
                htrack(RunService.Heartbeat:Connect(function(dt)
                    acc = acc + dt; if acc < 0.5 then return end; acc = 0
                    if not (Toggles.SLAutoFish.Value and Toggles.SLAutoCast.Value) then state = 'idle'; return end
                    if not rodEquipped() then return end
                    local now = os.clock()
                    if state == 'reel' and now - stateAt > 4.5 then state, stateAt = 'idle', now end
                    if state == 'bite' and now - stateAt > 8 then state, stateAt = 'idle', now end
                    if state == 'waiting' and now - stateAt > 30 then
                        -- no bite in 30s: a click while cast = reel in; recast after
                        state, stateAt = 'idle', now
                        local r = S.root()
                        if r then task.spawn(click, r.Position) end
                        return
                    end
                    if state == 'idle' and now - stateAt > 1.5 then
                        local hum = S.hum()
                        if hum and hum.FloorMaterial ~= Enum.Material.Air then
                            state, stateAt = 'casting', now
                            task.spawn(function()
                                local pos = waterPos()
                                if not pos then
                                    status:SetText('No water within 32 studs - move to the shore')
                                    state, stateAt = 'idle', os.clock() + 3
                                    return
                                end
                                click(pos)
                                state, stateAt = 'waiting', os.clock()
                                status:SetText('Cast - waiting for a bite')
                            end)
                        end
                    end
                end))
            end)()
            -- ================================================================
            -- KILL AURA - SKILL AURA: auto-cast YOUR equipped skills at packs
            -- ================================================================
            -- Skills are the AoE lever: a skill tick is Utility.CreateHitbox
            -- (RS/CAM/Global/Utility.lua:920) at our server-side root.CFrame *
            -- Config.<X>_HITBOX_OFFSET, size Config.<X>_HITBOX_SIZE (e.g. Flame
            -- TigerServer.lua:115) and hits EVERY model in that box - mobs AND players
            -- (check_victim only spares Safezone / Lair / minigame / party, Checker.lua
            -- :856-891) - while M1 is server-gated to ~1.86 hits/s.
            -- Casts go ONLY through the HUD's own slot keys: InputHandler 'Skills_1st'..
            -- 'Skills_10th' -> HUD Skills.lua:270-360 tryHold(slot) -> Skill_Controller
            -- .Attempt_Hold(<the HUD's cached slot name>) -> Can_Skill + Checker.check ->
            -- 'server_skill_controller_signaler'. We never send a skill name: one outside
            -- the loadout = Skills_Module.SourceCheck -> BanActions.Tier1 (Skills_Module
            -- .lua:291-294), and the client Can_Skill does NOT stop it (v29 is reassigned
            -- at :303), so before every press the fresh Skills_Provider.get_current_keys()
            -- must equal the list the HUD last received (Keys_Changed; deferred while SHC
            -- is busy, Skills_Provider.lua:74-112). Slot 1 is Blocking on every weapon /
            -- power (Breathings/*.lua Skills[1]) - never cast.
            -- What a press FIRES depends on how long the key is held for some skills
            -- (HOLD_DURATION / TAP_THRESHOLD / MIN_HOLD_DUR ...): those are cast only when
            -- listed in MODE below (verified branch, hold time, boxes, hit times); every
            -- other branching skill is listed as NOT CAST.
            -- PvP: no cast while another player / player clone is within reach of ANY
            -- box the skill has (all branches, grabs, far boxes) + the pad; dash /
            -- projectile skills (and skills without box data) need 175 studs clear.
            -- The farm reads S.kaAim (face) and S.kaDrop inside S.kaDropWins (sink, only
            -- around hit instants, only for cancel_bypass skills) until S.kaAimUntil; the
            -- Skill Aim Assist mousepos hook returns S.kaAim for that window; S.kaCasting
            -- = our slot key is held (Auto Parry stays off it).
            ;(function()
                local SP    = S.req('CAM.Client.Controllers.Skills_Provider')
                local CK    = S.req('CAM.Global.Checker')
                local PP    = S.req('CAM.Global.PlayerProfile')
                local CPm   = S.req('CAM.Global.Combat_presets')
                local PSR   = S.req('CAM.Global.PlayerStatResolver')
                local STATS = S.req('CAM.Global.SkillService.Stats')
                local SSA   = S.req('CAM.Global.Subsets.Gameplay.Skill_Switch_Adder')
                local SFM   = S.req('CAM.Global.Subsets.Gameplay.StatsFetch')
                local MCD   = S.req('CAM.Global.Subsets.Gameplay.manage_cd')
                local SLOT_KEYS = { 'Skills_1st', 'Skills_2nd', 'Skills_3rd', 'Skills_4th', 'Skills_5th',
                    'Skills_6th', 'Skills_7th', 'Skills_8th', 'Skills_9th', 'Skills_10th' } -- HUD Skills.lua:23-32
                local NEVER = { Blocking = true }
                local BOSS_W, MOVER_GUARD = 3, 175
                -- Verified hold-time branches (server scripts under RS/Skills/<style>/<skill>):
                --  Flame Tiger: held past HOLD_DURATION 0.3 the slash chain runs off the
                --   server root while the key stays down (Flame TigerServer.lua:33-194; each
                --   step re-checks Id, which the controller renews on UnHold, cf. client
                --   Skill_Controller.lua:352): SLASH 20x12x20 at 0.38 / 1.58 / 1.925 / 2.585,
                --   IMPACT 35x20x35 at 3.755. Released under 0.3 = TAP branch instead (:195-
                --   515): dash + TigerHead projectile that grabs any humanoid within 162 studs,
                --   BITE/DIVE boxes 63.5/80 studs out. So: hold 4.05s, never release < 0.45s.
                --   UnHold adds pause_gameplay + NR for RELEASE_LOCK_DURATION 2 (Flame Tiger.lua:146-147).
                --  Whirl Pool: released < 0.3 = one TAP box 22x25x22 at root*(0,7.5,0) on
                --   UnHold (Whirl PoolServer.lua:97-160); held = Basin dash 65 studs/s.
                --  Stone Wall: released < 0.3 = WALL at release+0.21 (root*(0,0,-10)), BREAK
                --   at +0.82 in the WALL frame (v6 * BREAK_HITBOX_OFFSET, Stone WallServer.lua
                --   :199-299); held = single-target GRAB (:432).
                --  Arrow Eruption: released < MIN_HOLD_DUR 0.35 = cancelled; else HITBOX_ONE
                --   at release, HITBOX_TWO +1.5 (Arrow EruptionServer.lua:47-130). The HUD
                --   auto-releases at Max_Hold 0.4 (Arrow.lua:6, Skill_Controller.lua:583).
                --  Not modelled (listed NOT CAST): Water Wheel (tap = 60 studs/s dash with a
                --   catch part), Flashing Willow (boxes sit at the aim point and it pulls you
                --   there), Upper Smash, Quick Draw, Storm Rush, Obi Barrage / Charge, Tamari,
                --   Barren Hanging Garden - anything with a hold-time branch key.
                local MODE = {
                    ['Flame Tiger'] = { hold = 4.05, keep = 0.45, lock = 2, rel = 'press',
                        keys = { SLASH_HITBOX_SIZE = true, IMPACT_HITBOX_SIZE = true },
                        hits = { 0.38, 1.58, 1.925, 2.585, 3.755 } },
                    ['Whirl Pool'] = { hold = 0.08, tap = true, lock = 2, rel = 'release',
                        keys = { TAP_HITBOX_SIZE = true }, hits = { 0 } },
                    ['Stone Wall'] = { hold = 0.08, tap = true, lock = 2, rel = 'release',
                        keys = { WALL_HITBOX_SIZE = true, BREAK_HITBOX_SIZE = true },
                        offs = { BREAK_HITBOX_SIZE = { 'WALL_HITBOX_OFFSET', 'BREAK_HITBOX_OFFSET' } },
                        hits = { 0.21, 0.82 } },
                    ['Arrow Eruption'] = { hold = 0.5, lock = 2.64, rel = 'release',
                        keys = { HITBOX_ONE_SIZE = true, HITBOX_TWO_SIZE = true }, hits = { 0, 1.5 } },
                }
                -- Config keys that mean: the hold time picks a different attack
                local BRANCH = { HOLD_DURATION = true, TAP_THRESHOLD = true, HOLD_THRESHOLD = true,
                    MIN_HOLD_DUR = true, BARRAGE_MIN_HOLD = true, CLOSE_HOLD_DURATION = true }
                -- Config keys of dashes / projectiles / summons / teleports: effects that
                -- travel away from our root, so the PvP guard needs MOVER_GUARD studs clear
                local MOVER_KEYS = { 'DASH', 'PROJECTILE', 'TRAVEL', 'TELEPORT', 'TORNADO', 'BEAM', 'ORB_', 'PETAL',
                    'BEAD', 'GLIDE', 'FLIGHT', 'LEASH', 'SUMMON', 'METEOR', 'GUST', 'CATCH', 'DISTANCE', 'AIM_RANGE',
                    'DEPLOY_RANGE', 'TARGET_RANGE', 'MAX_RANGE', 'ROCKUP', 'SHORT_RANGE', 'HEAD_SPEED', 'THROW_SPEED',
                    'RISE_SPEED', 'SLAM_SPEED', 'BURST_SPEED', 'DRIVE_SPEED', 'RELEASE_SPEED', 'DRAG_SPEED', 'SPAWN_OFFSET' }

                local box = S.kaBox or Tabs.Farm:AddRightGroupbox('Kill Aura')
                if S.kaBox then box:AddDivider() end -- under the multi-hit M1 part
                S.kaBox = box -- other kill-aura parts can add to the same groupbox
                box:AddLabel('Skill aura: casts YOUR equipped skills through\nthe game HUD slot keys when the real hit box of\na skill (its Config HITBOX_SIZE / OFFSET) covers\nenough mobs - skills hit every mob in the box.\nNever casts Blocking, never with a player near,\nnever sends a skill name itself.', true)
                local status = box:AddLabel('Off', true)
                local loadLbl = box:AddLabel('Loadout: -', true)
                local refreshLoadout -- assigned below (button + signals)
                box:AddToggle('SLKASkillAura', { Text = 'Skill aura', Default = false,
                    Tooltip = 'Auto-casts the ticked skills when their hit box would hit Min targets mobs. With Mob / Quest farm on it only casts while the farm sits on a mob, and (while M1 is held) only in the gap after your finisher.' })
                    :AddKeyPicker('SLKASkillAuraKey', { Default = 'None', SyncToggleState = true, Mode = 'Toggle', Text = 'Skill aura' })
                box:AddDropdown('SLKASSkills', { Values = {}, Default = {}, Multi = true, AllowNull = true, Text = 'Skills it may cast',
                    Tooltip = 'Your current HUD loadout (Blocking and skills whose hold / tap branches are not modelled are never listed). New skills start ticked when they have a real area box at your root (10+ studs, not a grab / counter / dash / projectile) and lock you for 3.5s or less.' })
                box:AddButton({ Text = 'Refresh loadout', Func = function() if refreshLoadout then task.spawn(refreshLoadout, true) end end })
                box:AddSlider('SLKASMin', { Text = 'Min targets', Default = 2, Min = 1, Max = 8, Rounding = 0,
                    Tooltip = 'Cast only when the box of the skill would hit at least this many mobs. A boss counts as 3.' })
                box:AddToggle('SLKASAnyTime', { Text = 'Cast outside finisher gap', Default = false,
                    Tooltip = 'Off: while the farm holds M1, cast only in the free gap after your 5th hit (the next M1 waits 1.65s; skills are client-locked for 0.5s after any M1). On: cast whenever ready - M1 is paused ~0.6s so the 0.5s lock clears.' })
                box:AddSlider('SLKASGapEnd', { Text = 'Finisher gap end margin', Default = 0.35, Min = 0, Max = 1, Rounding = 2, Suffix = ' s',
                    Tooltip = 'Stop starting casts this long before the next M1 is due (gap = 0.5s .. final 1.65s after the finisher).' })
                box:AddToggle('SLKASHold', { Text = 'Hold skills to max', Default = false,
                    Tooltip = 'Hold the key for the Max_Hold of the skill (minus 0.25s) instead of tapping - for hold-loop skills. Capped by Max hold time. Skills with a verified hold / tap branch always use their own hold time.' })
                box:AddSlider('SLKASHoldCap', { Text = 'Max hold time', Default = 5, Min = 0.3, Max = 6, Rounding = 1, Suffix = ' s' })
                box:AddSlider('SLKASDrop', { Text = 'Max cast drop', Default = 0, Min = 0, Max = 5, Rounding = 1, Suffix = ' studs',
                    Tooltip = 'Farm only, cancel-bypass skills only (a stun cannot cancel them): many skill boxes start 3 studs under your root and miss from the head of the mob. Sinks you by the smallest amount (0.5 steps) that reaches Min targets, and only for ~0.35s around each hit - the rest of the cast you stay on the perch. 0 = never.' })
                box:AddSlider('SLKASFallback', { Text = 'Fallback radius', Default = 10, Min = 4, Max = 30, Rounding = 0, Suffix = ' studs',
                    Tooltip = 'Area used for a skill whose Config has no HITBOX_SIZE fields (a cube this far out from your root).' })
                box:AddSlider('SLKASMargin', { Text = 'Skill box safety margin', Default = 1, Min = 0, Max = 4, Rounding = 1, Suffix = ' studs',
                    Tooltip = 'Mobs only count if they are this far inside the box sideways (ping / mob movement). Height is not shrunk.' })
                box:AddSlider('SLKASPlayerPad', { Text = 'Player safety pad', Default = 10, Min = 0, Max = 30, Rounding = 0, Suffix = ' studs',
                    Tooltip = 'No cast while another player (or their clone) is within reach of ANY box of the skill plus this. Dash / projectile skills need 175 studs clear.' })
                box:AddToggle('SLKASFace', { Text = 'Turn to the pack when not farming', Default = true,
                    Tooltip = 'Off: only casts along the way you already face.' })
                box:AddToggle('SLKASLog', { Text = 'Log casts', Default = false, Tooltip = 'Console: skill, predicted targets, drop, then how many actually took damage.' })

                local slots, choice, infoCache = {}, {}, {}
                local loadSig, lastLoad = nil, -1e9
                local hudSig, stableSig, stableAt = nil, nil, 0 -- what the HUD holds / fresh-read stability
                local busyUntil, retryAt = 0, {}
                local castLog, lastTxt, lastStatus = {}, 'none', 0
                local pressed, pressAt, pressKeep, faceHold = nil, 0, 0, false

                -- ---- per-skill data from its Config + skill_info ------------------
                local function skillFolder(name)
                    local sk = RepStorage:FindFirstChild('Skills')
                    if not sk then return nil end
                    for _, style in ipairs(sk:GetChildren()) do -- Skills/<style>/<skill>/Config
                        local f = style:FindFirstChild(name)
                        if f and f:FindFirstChild('Config') then return f end
                    end
                    for _, d in ipairs(sk:GetDescendants()) do
                        if d.Name == name and d:FindFirstChild('Config') then return d end
                    end
                    return nil
                end
                local function readConfig(name)
                    local f = skillFolder(name)
                    local c = f and f:FindFirstChild('Config')
                    if not (c and c:IsA('ModuleScript')) then return nil end
                    local ok, cfg = pcall(require, c)
                    return (ok and type(cfg) == 'table') and cfg or nil
                end
                local function cfOf(v)
                    if typeof(v) == 'CFrame' then return v end
                    if typeof(v) == 'Vector3' then return CFrame.new(v) end
                    return nil
                end
                -- <X>_HITBOX_SIZE pairs with <X>_HITBOX_OFFSET, then <X minus trailing
                -- digits>_HITBOX_OFFSET (UPSLASH1_ -> UPSLASH_), then HITBOX_OFFSET; none
                -- = root.CFrame itself (Unknowing FireServer.lua:145).
                local function offsetFor(cfg, key)
                    local cands = { (key:gsub('SIZE', 'OFFSET', 1)) }
                    local base = key:match('^(.-)_?HITBOX_SIZE$')
                    if base and base ~= '' then cands[#cands + 1] = (base:gsub('%d+$', '')) .. '_HITBOX_OFFSET' end
                    cands[#cands + 1] = 'HITBOX_OFFSET'
                    for _, k in ipairs(cands) do
                        local cf = cfOf(cfg[k])
                        if cf then return cf end
                    end
                    return CFrame.new()
                end
                local function chainOff(cfg, list) -- offsets applied one after another (Stone Wall BREAK)
                    local cf = CFrame.new()
                    for _, k in ipairs(list) do cf = cf * (cfOf(cfg[k]) or CFrame.new()) end
                    return cf
                end
                local function statsOf(name, entry) -- entry.SkillStats, else StatsFetch.SkillStats.Get
                    local st = type(entry) == 'table' and entry.SkillStats or nil
                    if type(st) == 'table' then return st end
                    if SFM and SFM.SkillStats and SFM.SkillStats.Get then
                        local ok, r = pcall(SFM.SkillStats.Get, name)
                        if ok and type(r) == 'table' then return r end
                    end
                    return {}
                end
                local function deriveInfo(name, entry)
                    local cfg = readConfig(name)
                    local mode = MODE[name]
                    local all, hitAts, maxAt = {}, {}, nil
                    local branch, mover, lockS = false, cfg == nil, 0
                    if cfg then
                        for k, v in pairs(cfg) do
                            if type(k) == 'string' then
                                if BRANCH[k] or k:sub(1, 4) == 'TAP_' then branch = true end
                                for _, pat in ipairs(MOVER_KEYS) do
                                    if k:find(pat, 1, true) then mover = true; break end
                                end
                                -- (RANGE_CHECK_HITBOX_SIZE etc. only test range, they deal no damage)
                                if typeof(v) == 'Vector3' and k:find('HITBOX', 1, true) and k:find('SIZE', 1, true) and not k:find('CHECK', 1, true) then
                                    local off = (mode and mode.offs and mode.offs[k]) and chainOff(cfg, mode.offs[k]) or offsetFor(cfg, k)
                                    local far = off.Position.Magnitude > 40 -- set relative to a projectile / aim point
                                    if far then mover = true end
                                    all[#all + 1] = { key = k, size = v, off = off, far = far,
                                        single = (k:find('GRAB', 1, true) or k:find('CATCH', 1, true) or k:find('SCAN', 1, true)) ~= nil }
                                elseif type(v) == 'number' then
                                    if k:match('_AT$') and v > 0 and v < 8 then -- hit times (SLASH1_AT, HEAD_AT ...)
                                        hitAts[#hitAts + 1] = v
                                        maxAt = math.max(maxAt or 0, v)
                                    end
                                    if ((k:find('LOCK', 1, true) and not k:find('HOLD_LOCK', 1, true) and k:sub(1, 4) ~= 'TAP_')
                                        or k == 'RELEASE_DUR') and v > 0 and v < 10 then
                                        lockS = math.max(lockS, v) -- pause_gameplay / NR after the cast
                                    end
                                end
                            end
                        end
                    end
                    if #all == 0 then mover = true end -- no box data: unknown geometry
                    table.sort(all, function(a, b) return a.key < b.key end)
                    local use = {}
                    if mode then
                        for _, b in ipairs(all) do if mode.keys[b.key] then use[#use + 1] = b end end
                    else
                        for _, b in ipairs(all) do if not b.far and not b.single then use[#use + 1] = b end end
                        if #use == 0 then for _, b in ipairs(all) do if not b.far then use[#use + 1] = b end end end
                    end
                    local reach, fwd, aoe, guard = 0, 0, false, 0
                    for _, b in ipairs(use) do
                        local p = b.off.Position
                        reach = math.max(reach, Vector3.new(p.X, 0, p.Z).Magnitude + math.max(b.size.X, b.size.Z) / 2)
                        fwd = math.max(fwd, -p.Z)
                        if not b.single and math.max(b.size.X, b.size.Z) >= 10 then aoe = true end
                    end
                    for _, b in ipairs(all) do guard = math.max(guard, b.off.Position.Magnitude + b.size.Magnitude / 2) end
                    if mover then guard = math.max(guard, MOVER_GUARD) end
                    local pinfo = PP and type(PP.skill_info) == 'table' and PP.skill_info[name] or nil -- Items.lua:42
                    local stats = statsOf(name, entry)
                    local counter = stats.counter ~= nil
                    local unsupported = (branch and not mode) and 'hold/tap branches not modelled' or nil
                    local hits = mode and mode.hits or { 0 }
                    if not mode then for _, a in ipairs(hitAts) do hits[#hits + 1] = a end end
                    local lastHit = 0
                    for _, a in ipairs(hits) do lastHit = math.max(lastHit, a) end
                    local hold = mode and mode.hold or 0.1
                    local lock = hold + ((mode and mode.lock) or lockS)
                    local cdName = (pinfo and pinfo.CoolDownName) or name
                    if MCD and MCD.filter_cd_name then
                        local ok, n = pcall(MCD.filter_cd_name, LP, name)
                        if ok and type(n) == 'string' and n ~= '' then cdName = n end
                    end
                    return {
                        name = name, boxes = use, all = all, cfg = cfg ~= nil, reach = reach, fwd = fwd,
                        aoe = aoe and (mode ~= nil or not counter) and not unsupported,
                        mover = mover, guard = guard, unsupported = unsupported, mode = mode,
                        rootAim = #use > 0 and (mode ~= nil or not mover), -- boxes sit at our root: aim at root height
                        tap = mode and mode.tap or false, hold = hold, keep = mode and mode.keep or 0,
                        rel = mode and mode.rel or 'any', hits = hits, lastHit = lastHit,
                        after = mode and (lastHit + 0.4) or math.clamp((maxAt or 0.8) + 0.4, 0.6, 4),
                        lock = lock,
                        cancelBypass = stats.cancel_bypass ~= nil, -- stun can't cancel it (ManuelCancel.lua, HUD Skills.lua:244-253)
                        maxHold = tonumber(type(entry) == 'table' and entry.Max_Hold) or (pinfo and tonumber(pinfo.Max_Hold_Time)) or 0,
                        stamina = (pinfo and tonumber(pinfo.Stamina)) or tonumber(type(entry) == 'table' and entry.Stamina) or 0,
                        cd = tonumber(type(entry) == 'table' and entry.CoolDown) or (pinfo and tonumber(pinfo.Cooldown)) or 0,
                        cdName = cdName, -- manage_cd.filter_cd_name (manage_cd.lua:124-132)
                        category = pinfo and pinfo.Category or nil,
                        requiresAura = pinfo and pinfo.RequiresAura or nil,
                        requiresModeBar = pinfo and pinfo.RequiresModeBar == true or false,
                        autoTick = false,
                    }
                end

                -- ---- readiness (same checks as Skills_Module.Can_Skill, read-only) --
                local function cdLeft(info)
                    local c = LP.Character
                    if not c then return 99 end
                    local shc = c:FindFirstChild('SHC') -- client stamp (HUD Skills.lua:503)
                    local v = shc and shc:FindFirstChild(info.cdName)
                    if v then
                        local st = v:GetAttribute('Started')
                        local left = (st and type(v.Value) == 'number') and (v.Value - (os.clock() - st)) or 1
                        return math.max(left, 0.05)
                    end
                    local shcs = c:FindFirstChild('SHCS') -- server stamp, removed 0.25s early (manage_cd.lua:120)
                    if shcs and shcs:FindFirstChild(info.cdName) then return 0.25 end
                    return 0
                end
                local function staminaOk(info) -- Skills_Module.lua:304-310
                    if (info.stamina or 0) <= 0 then return true end
                    local v = S.values()
                    local st = v and v:FindFirstChild('Stamina')
                    if not (st and type(st.Value) == 'number') then return true end
                    local f = 0
                    if PSR and PSR.GetStat then
                        local ok, a = pcall(PSR.GetStat, LP, 'Stamina Cost Factor')
                        if ok and type(a) == 'number' then f = f + a end
                        if info.category then
                            local ok2, b = pcall(PSR.GetStat, LP, tostring(info.category) .. ' Stamina Cost Factor')
                            if ok2 and type(b) == 'number' then f = f + b end
                        end
                    end
                    return st.Value >= math.max(0, info.stamina * (1 + f))
                end
                local function skillsOff(name) -- Values.skillsdisabled (Skills_Module.lua:253-260)
                    local v = S.values()
                    local sd = v and v:FindFirstChild('skillsdisabled')
                    if not sd then return false end
                    local s = tostring(sd.Value)
                    if s:find('all', 1, true) then return s:find('except' .. name, 1, true) == nil end
                    return s:find(name, 1, true) ~= nil
                end
                local function isLocked(name) -- HUD lock icon (Skills.lua:208-209)
                    if not (STATS and STATS.GetRequirements) then return false end
                    local ok, _, unlocked = pcall(STATS.GetRequirements, LP, name)
                    return ok and unlocked ~= true
                end
                -- nil = castable now, else why not. Mirrors the Can_Skill / Attempt_Hold
                -- outcomes that would otherwise be a wasted press: RequiresAura (Skills_Module
                -- .lua:296-301), RequiresModeBar (:327-340, Skills_Provider.ModeBarFull), and a
                -- pending Skill_Switch follow-up (Attempt_Hold sends 'Switch' instead of the
                -- cast, Skill_Controller.lua:106-128).
                local function notReady(s, now)
                    local info = s.info
                    if s.locked then return 'locked' end
                    if info.unsupported then return info.unsupported end
                    if now < (retryAt[s.name] or 0) then return 'retry' end
                    if cdLeft(info) > 0 then return 'cooldown' end
                    if not staminaOk(info) then return 'stamina' end
                    if skillsOff(s.name) then return 'disabled' end
                    local pi = PP and type(PP.skill_info) == 'table' and PP.skill_info[s.name] or nil
                    local aura = (pi and pi.RequiresAura) or info.requiresAura
                    if aura then
                        local v = S.values()
                        if not (v and v:FindFirstChild(aura)) then return tostring(aura) .. ' not active' end
                    end
                    if (pi and pi.RequiresModeBar == true) or info.requiresModeBar then
                        local full = false
                        if SP and SP.ModeBarFull then
                            local ok, r = pcall(SP.ModeBarFull)
                            full = ok and r == true
                        end
                        if not full then return 'mode bar not full' end
                    end
                    local sw = LP:FindFirstChild(s.name .. ((SSA and SSA.extension) or 'Skill_Switch'))
                    if sw and not sw:FindFirstChild('Disabled') then return 'switch follow-up pending' end
                    return nil
                end

                -- ---- loadout ------------------------------------------------------
                local function sigOf(list) -- slot names 1..10, the part of the list the HUD casts from
                    local t = {}
                    for i = 1, #SLOT_KEYS do
                        local e = type(list) == 'table' and list[i] or nil
                        t[i] = (type(e) == 'table' and type(e.Name) == 'string') and e.Name or ''
                    end
                    return table.concat(t, '|')
                end
                local function updateLoadLabel()
                    if #slots == 0 then S.setText(loadLbl, 'Loadout: none (equip your weapon / power)'); return end
                    local L = {}
                    for _, s in ipairs(slots) do
                        local i = s.info
                        local how
                        if i.unsupported then
                            how = 'NOT CAST (' .. i.unsupported .. ')'
                        else
                            how = ((i.mode and not i.tap) and ('hold %.2fs, '):format(i.hold) or 'tap, ')
                                .. ((#i.boxes > 0) and ('%d box, reach %.0f, fwd %.0f%s'):format(#i.boxes, i.reach, i.fwd, i.aoe and ', AoE' or '')
                                    or 'no box data (fallback radius)')
                                .. ('  lock %.1fs  clear %.0f%s'):format(i.lock, i.guard, i.mover and ' (dash/proj)' or '')
                        end
                        L[#L + 1] = ('%d %s%s: %s  cd %ss  st %s'):format(s.idx, s.name, s.locked and ' [locked]' or '',
                            how, tostring(i.cd), tostring(i.stamina))
                    end
                    S.setText(loadLbl, 'Loadout:\n' .. table.concat(L, '\n'))
                end
                local function applyKeys(list)
                    lastLoad = os.clock()
                    if type(list) ~= 'table' then return end
                    local sigAll = sigOf(list)
                    if sigAll ~= stableSig then stableSig, stableAt = sigAll, os.clock() end
                    local newSlots, names = {}, {}
                    for i, key in ipairs(SLOT_KEYS) do
                        local e = list[i]
                        local nm = type(e) == 'table' and e.Name or nil
                        if type(nm) == 'string' and nm ~= '' and not NEVER[nm] then
                            local info = infoCache[nm]
                            if not info then
                                info = deriveInfo(nm, e)
                                info.autoTick = info.aoe and (info.mode ~= nil or not info.mover) and info.lock <= 3.5
                                infoCache[nm] = info
                            end
                            newSlots[#newSlots + 1] = { idx = i, key = key, name = nm, info = info, locked = isLocked(nm) }
                            if not info.unsupported then names[#names + 1] = nm end
                        end
                    end
                    slots = newSlots
                    if sigAll ~= loadSig then
                        loadSig = sigAll
                        local nv = {}
                        for _, sl in ipairs(newSlots) do
                            if not sl.info.unsupported then
                                local want = choice[sl.name]
                                if want == nil then want = sl.info.autoTick end -- first time seen
                                if want then nv[sl.name] = true end
                            end
                        end
                        S.ui()
                        pcall(function() Options.SLKASSkills:SetValues(names); Options.SLKASSkills:SetValue(nv) end)
                    end
                    updateLoadLabel()
                end
                Options.SLKASSkills:OnChanged(function()
                    local v = Options.SLKASSkills.Value
                    v = type(v) == 'table' and v or {}
                    for _, s in ipairs(slots) do
                        if not s.info.unsupported then choice[s.name] = v[s.name] == true end
                    end
                end)
                refreshLoadout = function(force)
                    if not (SP and type(SP.get_current_keys) == 'function') then
                        lastLoad = os.clock()
                        S.setText(loadLbl, 'Skills_Provider not loaded - skill aura unavailable')
                        return
                    end
                    if force then loadSig = nil; infoCache = {} end
                    local ok, list = pcall(SP.get_current_keys)
                    if ok then applyKeys(list) else lastLoad = os.clock() end
                end
                if SP and type(SP.Keys_Changed) == 'table' and SP.Keys_Changed.Connect then
                    local ok, conn = pcall(function()
                        return SP.Keys_Changed:Connect(function(list)
                            hudSig = sigOf(list) -- the HUD's updateSkills got this same list (Skills.lua:224-225)
                            task.defer(applyKeys, list)
                        end)
                    end)
                    if ok and conn then htrack(conn) end
                end
                htrack(LP.CharacterAdded:Connect(function()
                    hudSig, stableSig = nil, nil -- the HUD remounts and re-reads get_current_keys()
                    task.delay(2.5, function() if not S.dead then refreshLoadout(false) end end)
                end))

                -- ---- M1 timing (Combat_presets fields the client combat writes) ----
                local function myPreset() -- same pick as CU/Combat.lua: tool preset or its CombatPreset
                    if not (CPm and type(CPm.Presets) == 'table') then return nil end
                    local CIP = S.req('CAM.Global.Character_info_provider')
                    local tool
                    if CIP and CIP.Get_equipped_tool then
                        local ok, t = pcall(CIP.Get_equipped_tool, LP)
                        if ok then tool = t end
                    end
                    local n = tool and tool.Name
                    if n and CPm.Presets[n] then return CPm.Presets[n] end
                    local IT = S.req('CAM.Global.Collectibles.Items')
                    local it = n and IT and IT[n]
                    if type(it) == 'table' then return CPm.Presets[it.CombatPreset or 'Regular Katana'] or CPm.Presets.Combat end
                    return CPm.Presets.Combat
                end
                -- 'lock' = <0.5s since an M1 (Checker.lua:109 refuses skills), 'gap' =
                -- after the finisher before the next M1 is due, 'idle' = M1 not landing,
                -- 'combo' = mid-chain.
                local function gapState()
                    if not CPm then return 'idle', 99 end
                    local since = os.clock() - (tonumber(CPm.Last_Punched) or 0)
                    if since < (tonumber(CPm.slow_walk_duration) or 0.5) then return 'lock', since end
                    local pre = myPreset()
                    local final = (pre and tonumber(pre.final)) or 1.65
                    if since > final + 0.35 then return 'idle', since end
                    local mx = (pre and tonumber(pre.Max)) or 5
                    local lc = CPm.Last_Combo
                    if (lc == mx or lc == 7) and since <= final - Options.SLKASGapEnd.Value then return 'gap', since end
                    return 'combo', since
                end

                -- ---- area evaluation ---------------------------------------------
                local function weightOf(m) return (m.Parent and m.Parent:FindFirstChild('BossInfo')) and BOSS_W or 1 end
                -- Weighted centroid of hittable, non-civilian mobs within reach of pos.
                local function packAim(mobs, pos, reach)
                    local sum, w = Vector3.zero, 0
                    for _, m in ipairs(mobs) do
                        if not (m.civ and not m.boss) and (m.root.Position - pos).Magnitude <= reach + 6 and S.kaHittable(m.model, 'skill') then
                            local k = m.boss and BOSS_W or 1
                            sum = sum + m.root.Position * k
                            w = w + k
                        end
                    end
                    if w == 0 then return nil, 0 end
                    return sum / w, w
                end
                -- Union of mobs over the skill's scoring boxes cast from frame cf0, or nil +
                -- why: 'player' (any of ALL its boxes, grown by the pad, touches another
                -- player / clone), 'perfect' (a Perfect-blocking mob in a scoring box),
                -- 'civilian' (Skip civilians on and one is in a scoring box).
                local function scoreBoxes(info, cf0, checkPlayers)
                    local margin = Options.SLKASMargin.Value
                    local pad = Options.SLKASPlayerPad.Value * 2
                    local use, all = info.boxes, info.all
                    if #use == 0 then
                        local d = Options.SLKASFallback.Value * 2
                        use = { { size = Vector3.new(d, d, d), off = CFrame.new() } }
                        if #all == 0 then all = use end
                    end
                    if checkPlayers then
                        for _, b in ipairs(all) do
                            local cf, sz = cf0 * b.off, b.size + Vector3.new(pad, pad, pad)
                            if S.kaPlayersInBox(cf, sz) > 0 then return nil, 'player' end
                            local _, pl = S.kaTargetsInBox(cf, sz, nil)
                            if pl > 0 then return nil, 'player' end
                        end
                    end
                    local skipCiv = Toggles.SLFarmSkipCiv and Toggles.SLFarmSkipCiv.Value
                    local seen, score, n, list = {}, 0, 0, {}
                    for _, b in ipairs(use) do
                        local cf = cf0 * b.off
                        local _, _, _, _, civs, perfect = S.kaTargetsInBox(cf, b.size + Vector3.new(margin, margin, margin) * 2, nil)
                        if perfect > 0 then return nil, 'perfect' end
                        if civs > 0 and skipCiv then return nil, 'civilian' end
                        local sz = b.size - Vector3.new(margin, 0, margin) * 2 -- sideways only: height is exact
                        local _, _, mobs = S.kaTargetsInBox(cf, Vector3.new(math.max(sz.X, 1), sz.Y, math.max(sz.Z, 1)), 'skill')
                        for _, m in ipairs(mobs) do
                            if not seen[m] then
                                seen[m] = true
                                n = n + 1
                                list[#list + 1] = m
                                score = score + weightOf(m)
                            end
                        end
                    end
                    return score, n, list
                end
                -- Candidate frames: facing the centroid (only if we can hold that facing)
                -- and our current facing, at drop 0 then 0.5-stud steps up to dropMax;
                -- the smallest drop that reaches Min targets wins. Any 'player' = hold.
                local function evalSkill(info, root, centroid, dropMax, canTurn)
                    local p = root.Position
                    local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
                    look = (look.Magnitude > 0.1) and look.Unit or Vector3.new(0, 0, -1)
                    local flat = (centroid - p) * Vector3.new(1, 0, 1)
                    local dirs = (canTurn and flat.Magnitude > 1.5) and { flat.Unit, look } or { look }
                    local drops = { 0 }
                    if dropMax > 0 then
                        local d = 0.5
                        while d <= dropMax + 1e-6 do drops[#drops + 1] = d; d = d + 0.5 end
                    end
                    local minT = Options.SLKASMin.Value
                    local best, why
                    for _, d in ipairs(drops) do
                        local at = p - Vector3.new(0, d, 0)
                        for _, dir in ipairs(dirs) do
                            local sc, n, list = scoreBoxes(info, CFrame.lookAt(at, at + dir), d == 0)
                            if not sc then
                                if n == 'player' then return nil, 'player' end
                                why = n
                            elseif not best or sc > best.score then
                                -- root-box skills aim level with our root (skills that align the
                                -- root to mousepos would otherwise pitch every box); projectile /
                                -- no-box skills aim at the pack itself.
                                local aimY = info.rootAim and at.Y or centroid.Y
                                best = { score = sc, n = n, mobs = list, drop = d, dir = dir,
                                    aim = Vector3.new(at.X, aimY, at.Z) + dir * math.max(6, flat.Magnitude) }
                            end
                        end
                        if best and best.score >= minT then break end
                    end
                    return best, why
                end

                local function cpm()
                    local now, keep = os.clock(), {}
                    for _, t in ipairs(castLog) do if now - t <= 60 then keep[#keep + 1] = t end end
                    castLog = keep
                    return #keep
                end
                local function setStatus(t, force)
                    if not force and os.clock() - lastStatus < 0.25 then return end
                    lastStatus = os.clock()
                    S.setText(status, t .. ('\nLast: %s  |  %d casts/min'):format(lastTxt, cpm()))
                end
                local function dmgOf(m) -- mob.DMG.<attacker Name> = running damage total
                    local d = m:FindFirstChild('DMG')
                    local v = d and d:FindFirstChild(LP.Name)
                    return (v and tonumber(v.Value)) or 0
                end
                local function guardRadius(info) return info.guard + Options.SLKASPlayerPad.Value * 1.8 + 5 end

                -- ---- one cast through the HUD slot key -----------------------------
                local function fired(s, tPress) -- the HUD's Attempt_Hold went through
                    local c = LP.Character
                    local shc = c and c:FindFirstChild('SHC')
                    if shc and (shc.Value == s.name or shc:FindFirstChild(s.info.cdName) ~= nil) then return true end
                    local pi = PP and type(PP.skill_info) == 'table' and PP.skill_info[s.name] or nil
                    return type(pi) == 'table' and type(pi.lastUsed) == 'number' and pi.lastUsed >= tPress - 0.02 -- Skill_Controller.lua:178
                end
                local function releasePressed() -- never before the skill's keep time (tap-branch flip)
                    local k = pressed
                    if not k then return end
                    local wait = pressKeep - (os.clock() - pressAt)
                    pressed = nil
                    S.kaCasting = false
                    if wait > 0 then task.delay(wait, function() pcall(IH.VirtualRelease, k) end) else pcall(IH.VirtualRelease, k) end
                end
                local function holdAbort(info, now)
                    if not Toggles.SLKASkillAura.Value or S.dead then return 'aura off' end
                    if (S.farmDodgeFrom or 0) <= now + 0.1 and (S.farmDodgeUntil or 0) > now then return 'farm dodge' end
                    if now >= (S.farmHoldOutFrom or 0) and now < (S.farmHoldOutUntil or 0) then return 'farm dodge' end
                    local r = S.root()
                    if r and S.kaPlayersNear(r.Position, guardRadius(info)) > 0 then return 'player came near' end
                    return nil
                end
                local function cast(s, e)
                    local info = s.info
                    local hold = info.hold
                    if not info.mode and Toggles.SLKASHold.Value and (info.maxHold or 0) > 0 then
                        hold = math.clamp(info.maxHold - 0.25, 0.1, Options.SLKASHoldCap.Value)
                    end
                    local span = (info.rel == 'press') and (math.max(hold, info.lastHit) + 0.4) or (hold + info.after)
                    local farm = S.farmLocked
                    local t0 = os.clock()
                    -- 1) face / aim first; the settle wait below lets it replicate
                    S.kaSkill, S.kaAim, S.kaDropWins = s.name, e.aim, nil
                    S.kaDrop = (farm and info.cancelBypass) and e.drop or 0
                    S.kaAimUntil = t0 + 1 + span
                    faceHold = (not farm) and Toggles.SLKASFace.Value
                    -- 2) the HUD slot must hold THIS skill, and the HUD's cached list must be
                    --    the fresh one (it casts ITS name, Skills.lua:279-287)
                    local okK, list = pcall(SP.get_current_keys)
                    if not (okK and type(list) == 'table') then return false, 'loadout unreadable' end
                    local cur = list[s.idx]
                    if not (type(cur) == 'table' and cur.Name == s.name) then applyKeys(list); return false, 'loadout changed' end
                    local fresh = sigOf(list)
                    if hudSig ~= nil then
                        if fresh ~= hudSig then return false, 'loadout changing (HUD not updated yet)' end
                    elseif not (stableSig == fresh and os.clock() - stableAt >= 0.5) then
                        if stableSig ~= fresh then stableSig, stableAt = fresh, os.clock() end
                        return false, 'confirming loadout'
                    end
                    local c = LP.Character
                    local shc = c and c:FindFirstChild('SHC')
                    if shc and (shc.Value ~= '' or shc:GetAttribute('en') == true) then return false, 'busy' end
                    if CK and CK.check then -- the exact gate Attempt_Hold runs (Skill_Controller.lua:132)
                        local okC, can = pcall(CK.check, LP, s.name)
                        if okC and not can then return false, 'game refused it right now' end
                    end
                    if IH.IsAvailable and not IH.IsAvailable() then return false, 'busy' end
                    -- 3) rest M1 for the cast, then settle: frames + half a ping so the new
                    --    facing / drop is on the server before the Hold remote lands
                    if farm then
                        S.farmBlockUntil = math.max(S.farmBlockUntil or 0, os.clock() + 0.3 + hold)
                        if S.releaseM1 then S.releaseM1() end
                    end
                    local tPlan = os.clock() + 0.06 + math.clamp(S.pingSec() * 0.5, 0.03, 0.15)
                    if S.kaDrop > 0 then -- sink only around each hit (client time ~ press + at)
                        local wins = {}
                        for _, at in ipairs(info.hits) do
                            if info.rel == 'press' then
                                wins[#wins + 1] = { tPlan + at - 0.18, tPlan + at + 0.18 }
                            elseif info.rel == 'release' then
                                wins[#wins + 1] = { tPlan + hold + at - 0.18, tPlan + hold + at + 0.18 }
                            else -- unknown base: cover press- and release-relative
                                wins[#wins + 1] = { tPlan + at - 0.18, tPlan + hold + at + 0.18 }
                            end
                        end
                        S.kaDropWins = wins
                    end
                    S.kaAimUntil = tPlan + span
                    busyUntil = S.kaAimUntil + 0.3
                    for _ = 1, 3 do RunService.RenderStepped:Wait() end
                    if os.clock() < tPlan then task.wait(tPlan - os.clock()) end
                    local r0 = S.root()
                    if not r0 or S.kaPlayersNear(r0.Position, guardRadius(info)) > 0 then return false, 'player came near' end
                    if S.farmLocked ~= farm then return false, 'farm moved' end
                    if farm then S.farmBlockUntil = math.max(S.farmBlockUntil or 0, os.clock() + hold + 0.15) end
                    local snap, hp0 = {}, {}
                    for _, m in ipairs(e.mobs) do
                        snap[m] = dmgOf(m)
                        local h = m:FindFirstChildOfClass('Humanoid')
                        hp0[m] = h and h.Health or 0
                    end
                    -- 4) press the HUD slot key; hold with abort checks (never release
                    --    before info.keep: Flame Tiger under 0.3s = its projectile branch)
                    local tPress = os.clock()
                    pressed, pressAt, pressKeep = s.key, tPress, info.keep
                    S.kaCasting = true
                    pcall(IH.VirtualPress, s.key)
                    local started, abortWhy = false, nil
                    while true do
                        local now = os.clock()
                        if not started then started = fired(s, tPress) end
                        if now - tPress >= hold then break end
                        if now - tPress >= pressKeep then
                            if not started and now - tPress > 0.35 then break end -- never went out
                            abortWhy = holdAbort(info, now)
                            if abortWhy then break end
                        end
                        RunService.Heartbeat:Wait()
                    end
                    releasePressed()
                    if not started then
                        local t1 = os.clock()
                        repeat
                            task.wait(0.05)
                            started = fired(s, tPress)
                        until started or os.clock() - t1 > 0.4
                    end
                    if not started then retryAt[s.name] = os.clock() + 2; return false, s.name .. ' did not fire' end
                    if abortWhy then
                        S.kaAimUntil, S.kaDropWins = 0, nil
                        busyUntil = os.clock() + 0.5
                    end
                    castLog[#castLog + 1] = os.clock()
                    lastTxt = ('%s -> %d target(s)%s%s'):format(s.name, e.n, e.drop > 0 and (' [-%.1f]'):format(e.drop) or '',
                        abortWhy and (' (released early: ' .. abortWhy .. ')') or '')
                    if Toggles.SLKASLog.Value then
                        print(('[Skill aura] %s  targets %d (score %d)  drop %.1f  hold %.2fs%s'):format(s.name, e.n, e.score, e.drop, hold,
                            abortWhy and ('  released early: ' .. abortWhy) or ''))
                    end
                    task.delay(math.max(0.2, tPress + span - os.clock()) + 0.4, function()
                        local hit = 0
                        for m, d0 in pairs(snap) do
                            local h = m:FindFirstChildOfClass('Humanoid')
                            if not m.Parent or not h or h.Health <= 0 or dmgOf(m) > d0 or h.Health < (hp0[m] or 0) - 0.01 then hit = hit + 1 end
                        end
                        lastTxt = ('%s -> %d target(s), ~%d hit'):format(s.name, e.n, hit)
                        if Toggles.SLKASLog.Value then print(('[Skill aura] %s  ~%d / %d took damage'):format(s.name, hit, e.n)) end
                    end)
                    return true
                end

                local function tick()
                    if not Toggles.SLKASkillAura.Value then return end
                    local now = os.clock()
                    if loadSig == nil or now - lastLoad > 5 then refreshLoadout(false) end
                    if now < busyUntil then return end -- a cast is in flight
                    local root, hum = S.root(), S.hum()
                    if not (root and hum and hum.Health > 0) then setStatus('Waiting for character'); return end
                    if not IH then setStatus('InputHandler not loaded - cannot cast'); return end
                    if not SP then setStatus('Skills_Provider not loaded - cannot cast'); return end
                    local farmOn = Toggles.SLMobFarm.Value or (Toggles.SLAutoQuest and Toggles.SLAutoQuest.Value)
                    if farmOn and (S.farmPaused or not S.farmLocked) then setStatus('Waiting for the farm to lock on a mob'); return end
                    if farmOn and ((now >= (S.farmHoldOutFrom or 0) and now < (S.farmHoldOutUntil or 0))
                        or ((S.farmDodgeUntil or 0) > now - 0.15 and (S.farmDodgeFrom or 0) < now + 1)) then
                        setStatus('Holding casts: dodge window'); return
                    end
                    local c = LP.Character
                    local shc = c and c:FindFirstChild('SHC')
                    if (shc and (shc.Value ~= '' or shc:GetAttribute('en') == true)) or (IH.IsAvailable and not IH.IsAvailable()) then
                        setStatus('Busy (stun / skill / block)'); return
                    end
                    -- M1 timing first: nothing below is worth computing while we can't cast
                    local farmAttacking = farmOn and S.farmLocked and Toggles.SLFarmM1 and Toggles.SLFarmM1.Value
                    local anyTime = Toggles.SLKASAnyTime.Value
                    local g, since = gapState()
                    if g == 'lock' and not (farmAttacking and anyTime) then setStatus('M1 lock (skills refused for 0.5s after an M1)'); return end
                    if farmAttacking and not anyTime and g == 'combo' then setStatus('Waiting for the finisher gap'); return end
                    local sel = Options.SLKASSkills.Value
                    sel = type(sel) == 'table' and sel or {}
                    local minT = Options.SLKASMin.Value
                    local canTurn = S.farmLocked or Toggles.SLKASFace.Value -- a facing we can hold through the cast
                    local mobs = S.mobs()
                    local best, bestSlot, bestRank, note, anySel = nil, nil, nil, nil, false
                    for _, s in ipairs(slots) do
                        local info = s.info
                        if sel[s.name] and not info.unsupported then
                            anySel = true
                            local nr = notReady(s, now)
                            if nr and nr ~= 'cooldown' and nr ~= 'retry' and nr ~= 'stamina' then
                                note = note or (s.name .. ': ' .. nr)
                            elseif not nr then
                                local R = guardRadius(info)
                                local np, nearest = S.kaPlayersNear(root.Position, R)
                                if np > 0 then
                                    note = ('Player %.0f studs away - %s needs %.0f clear'):format(nearest, s.name, R)
                                else
                                    local reach = (#info.boxes > 0) and info.reach or Options.SLKASFallback.Value
                                    local centroid, w = packAim(mobs, root.Position, reach)
                                    if centroid and w >= minT then
                                        local dropMax = (farmOn and S.farmLocked and info.cancelBypass) and Options.SLKASDrop.Value or 0
                                        local e, bad = evalSkill(info, root, centroid, dropMax, canTurn)
                                        if e and e.score >= minT then
                                            -- lock time costs M1 hits (~1.86/s) the cast has to make up for
                                            local rank = e.score - info.lock * 1.86 / math.max(e.score, 1)
                                            if not bestRank or rank > bestRank or (rank == bestRank and info.cd > bestSlot.info.cd) then
                                                best, bestSlot, bestRank = e, s, rank
                                            end
                                        elseif bad == 'player' then note = 'Player / clone near a ' .. s.name .. ' box - holding'
                                        elseif bad == 'perfect' then note = 'A mob in range is perfect-blocking'
                                        elseif bad == 'civilian' then note = 'Civilian in a ' .. s.name .. ' box (Skip civilians is on)'
                                        end
                                    end
                                end
                            end
                        end
                    end
                    if not best then
                        setStatus(not anySel and 'No skill ticked (or loadout empty)' or note or 'Waiting: no ready skill covers a pack')
                        return
                    end
                    if g == 'lock' then -- farm M1 + 'Cast outside finisher gap': rest M1 so the 0.5s lock clears
                        S.farmBlockUntil = math.max(S.farmBlockUntil or 0, now + 0.85 - since)
                        setStatus(('%s ready (%d targets) - resting M1 for the skill lock'):format(bestSlot.name, best.n)); return
                    end
                    busyUntil = now + 8 -- cast() sets the real window
                    setStatus(('Casting %s at %d target(s)%s'):format(bestSlot.name, best.n, best.drop > 0 and (' (drop %.1f)'):format(best.drop) or ''), true)
                    task.spawn(function()
                        local ok, res, why = pcall(cast, bestSlot, best)
                        if not (ok and res) then
                            releasePressed()
                            S.kaAimUntil, S.kaDropWins = 0, nil
                            busyUntil = os.clock() + 0.3
                            setStatus('Cast skipped: ' .. tostring(ok and why or res), true)
                        end
                    end)
                end
                task.spawn(function()
                    task.wait(1)
                    refreshLoadout(false)
                    while not S.dead do
                        local ok, err = pcall(tick)
                        if not ok then setStatus('Skill aura error: ' .. tostring(err), true) end
                        task.wait(0.12)
                    end
                end)
                -- not farming + Turn to the pack: hold the scored facing through the cast
                -- (the farm does this itself while locked)
                htrack(RunService.RenderStepped:Connect(function()
                    if not faceHold or S.farmLocked then return end
                    if not S.kaAim or os.clock() >= (S.kaAimUntil or 0) then faceHold = false; return end
                    local r = S.root()
                    if not r then return end
                    local fl = (S.kaAim - r.Position) * Vector3.new(1, 0, 1)
                    if fl.Magnitude > 0.5 then r.CFrame = CFrame.lookAt(r.Position, r.Position + fl.Unit) end
                end))
                Toggles.SLKASkillAura:OnChanged(function()
                    if Toggles.SLKASkillAura.Value then
                        task.spawn(refreshLoadout, true)
                    else
                        releasePressed() -- (a hold loop in flight also sees the toggle and stops)
                        S.kaAimUntil, S.kaDropWins = 0, nil
                        busyUntil = 0
                        setStatus('Off', true)
                    end
                end)
                if not SP then box:AddLabel('Skills_Provider not loaded - skill aura unavailable.', true) end
                htrack({ Disconnect = function()
                    S.kaAimUntil, S.kaDropWins = 0, nil
                    if IH then releasePressed() end
                end })
            end)()

            -- ================================================================
            -- LOOT / CHEST / QUEST-PICKUP HELPERS + BOSS HUNTS
            -- ================================================================
            ;(function()
                local box = Tabs.Farm:AddLeftGroupbox('Loot & Quest Helpers')
                box:AddLabel('Fires the game\'s OWN prompts when you\'re in range.\nThe server still checks ownership and distance.', true)
                box:AddToggle('SLAutoLoot', { Text = 'Auto-pick loot drops', Default = false, Tooltip = 'Parts tagged LootDrop (workspace.LootDrops) that are yours to claim.' })
                box:AddToggle('SLAutoChest', { Text = 'Auto-open chests', Default = false, Tooltip = 'Models tagged Chest that are not Locked (sealed caches need their guards dead first).' })
                box:AddToggle('SLAutoPickup', { Text = 'Auto-pick quest items', Default = false, Tooltip = 'The "Pick Up" props your pickup quests spawn (server checks you are within ~25 studs of the spot).' })
                local firedAt = setmetatable({}, { __mode = 'k' })
                local SKIP = { Map = true, Humanoids = true, Debree = true, Terrain = true, Training = true, Chests = true, LootDrops = true, Camera = true }
                local function tryPrompt(pp, root)
                    if not (pp.Enabled and fireproximityprompt) then return end
                    if firedAt[pp] and os.clock() - firedAt[pp] < 2 then return end
                    local pos = S.posOf(pp.Parent)
                    if pos and (pos - root.Position).Magnitude <= pp.MaxActivationDistance - 0.5 then
                        firedAt[pp] = os.clock()
                        pcall(fireproximityprompt, pp)
                    end
                end
                local acc = 0
                htrack(RunService.Heartbeat:Connect(function(dt)
                    acc = acc + dt; if acc < 0.4 then return end; acc = 0
                    local loot, chest, pick = Toggles.SLAutoLoot.Value, Toggles.SLAutoChest.Value, Toggles.SLAutoPickup.Value
                    if not (loot or chest or pick) then return end
                    local root = S.root(); if not root then return end
                    if loot then
                        for _, d in ipairs(CS:GetTagged('LootDrop')) do
                            if d:GetAttribute('DropClaimedBy') == nil then
                                for _, pp in ipairs(d:GetDescendants()) do if pp:IsA('ProximityPrompt') then tryPrompt(pp, root) end end
                            end
                        end
                    end
                    if chest then
                        for _, c in ipairs(CS:GetTagged('Chest')) do
                            if c:GetAttribute('ChestState') ~= 'Locked' and not c:GetAttribute('IsOpen') then
                                for _, pp in ipairs(c:GetDescendants()) do if pp:IsA('ProximityPrompt') then tryPrompt(pp, root) end end
                            end
                        end
                    end
                    if pick then -- PickupState parents its props to workspace root
                        for _, ch in ipairs(workspace:GetChildren()) do
                            if not SKIP[ch.Name] and (ch:IsA('BasePart') or ch:IsA('Model')) then
                                local pp = ch:FindFirstChildWhichIsA('ProximityPrompt', true)
                                if pp and pp.ActionText == 'Pick Up' then tryPrompt(pp, root) end
                            end
                        end
                    end
                end))
                if not fireproximityprompt then box:AddLabel('Executor lacks fireproximityprompt - helpers disabled.', true) end

                -- ---- Boss hunts (ReplicatedStorage.BossHunts board) ----------
                -- Board entries (DialogueComponent/Components/Quests.lua readHunt): attributes
                -- Quest (= its Quests.Holder key, "Eliminate <Npc>"), Boss, Side ('Muzan' |
                -- 'Crow'), Tier (a STRING: Mythic > Legendary > Epic > Rare > UnCommon >
                -- Common), ExpiresAt. BossHunts.Sides: Muzan = Demon/Hybrid, Crow =
                -- Slayer/Hybrid (Humans get none). Worth = Rewards(Entry(Boss)).Exp x
                -- Factor(entry) (0.5 solo / private .. 1 with 3+ eligible players) - what
                -- the hunt card shows. Claim = BossHuntsRequest{action="Claim", id}, sent
                -- only when Quests.CanAddQuest(LP, Quest) is true (the card's own gate).
                -- Hunts are quest Category "BossHunt": one at a time, next to a Combat quest.
                local hb = Tabs.Farm:AddLeftGroupbox('Boss Hunts')
                hb:AddLabel('Crow board hunts (ReplicatedStorage.BossHunts),\nmost EXP first. Claims only go out when the\ngame\'s own CanAddQuest check passes. A hunt is\nits own quest slot: it runs next to your quest.', true)
                local hStatus = hb:AddLabel('')
                hb:AddDropdown('SLHunt', { Values = {}, Default = nil, Multi = false, AllowNull = true, Text = 'Hunt' })
                local byLabel = {}
                local TIER_RANK = { Mythic = 6, Legendary = 5, Epic = 4, Rare = 3, UnCommon = 2, Common = 1 }
                local pendingId, pendingAt, pendingBoss = nil, 0, nil -- last claim sent, until a hunt quest shows up
                local failedIds = {} -- board ids whose claim produced no hunt quest (skipped while listed)
                local function BHm() return S.req('CAM.Global.Subsets.Gameplay.Quests.BossHunts') end
                local function QMh() return S.req('CAM.Global.Subsets.Gameplay.Quests') end
                local function norm(s) return (tostring(s):lower():gsub('[^%w]', '')) end
                local function fmtNum(n)
                    n = tonumber(n) or 0
                    if n >= 1e6 then return ('%.1fM'):format(n / 1e6) end
                    if n >= 1e4 then return ('%.1fk'):format(n / 1e3) end
                    return tostring(math.floor(n + 0.5))
                end
                local function sideOk(side) -- my race is listed in BossHunts.Sides[side].Race
                    local BH = BHm()
                    local def = BH and type(BH.Sides) == 'table' and side ~= nil and BH.Sides[side]
                    local race = S.val(S.data(), 'Race')
                    return type(def) == 'table' and type(def.Race) == 'table' and race ~= nil and table.find(def.Race, race) ~= nil
                end
                local function huntExp(h) -- EXP the claim pays (the board card's maths) + its BossHunts entry
                    local BH, Q = BHm(), QMh()
                    local entry, rew, factor = nil, nil, 1
                    if BH and type(BH.Entry) == 'function' then
                        local ok, e = pcall(BH.Entry, h.boss); if ok then entry = e end
                    end
                    if Q and type(Q.GetQuestInfo) == 'function' and h.quest then
                        local ok, info = pcall(Q.GetQuestInfo, h.quest)
                        if ok and type(info) == 'table' then rew = info.Rewards end
                    end
                    if type(rew) ~= 'table' and entry and type(BH.Rewards) == 'function' then
                        local ok, r = pcall(BH.Rewards, entry); if ok then rew = r end
                    end
                    if entry and type(BH.Factor) == 'function' then
                        local ok, f = pcall(BH.Factor, entry); if ok and type(f) == 'number' then factor = f end
                    end
                    return math.floor((type(rew) == 'table' and tonumber(rew.Exp) or 0) * factor + 0.5), entry
                end
                -- Quests.CanAddQuest(LP, Quest) (no cooldown skip), decoded like the Crow's
                -- CrowTasks_Denied lines: true = claimable, anything else + the reason.
                local function canClaim(h)
                    local Q = QMh()
                    if not h.quest then return nil, 'board entry has no Quest' end
                    if not (Q and type(Q.CanAddQuest) == 'function' and type(Q.Holder) == 'table' and Q.Holder[h.quest] ~= nil) then
                        return nil, 'hunt quest not registered on this client'
                    end
                    local ok, r, why, held = pcall(Q.CanAddQuest, LP, h.quest)
                    if not ok then return nil, 'CanAddQuest failed' end
                    if r == true then return true end
                    if r == nil then return false, 'not your side / level band' end
                    if why == 1 then return false, 'already holding it' end
                    if why == 2 then return false, 'already done' end
                    if why == false then return false, 'one hunt at a time - finish ' .. tostring(held or 'yours') .. ' first' end
                    return false, 'quest cooldown (30s, shared with every quest)'
                end
                htrack({ Disconnect = function() S.huntMob, S.huntDrop = nil, nil end })
                local function hunts()
                    local out = {}
                    local f = RepStorage:FindFirstChild('BossHunts')
                    if not f then return out end
                    local now = workspace:GetServerTimeNow()
                    for _, h in ipairs(f:GetChildren()) do
                        local exp = h:GetAttribute('ExpiresAt')
                        if not exp or exp > now then
                            local boss, tier = tostring(h:GetAttribute('Boss') or h.Name), tostring(h:GetAttribute('Tier') or '?')
                            local e = { id = h.Name, inst = h, boss = boss, tier = tier, side = h:GetAttribute('Side'),
                                quest = h:GetAttribute('Quest'), left = exp and (exp - now) or nil, rank = TIER_RANK[tier] or 0 }
                            e.xp, e.entry = huntExp(e)
                            e.mine = sideOk(e.side)
                            out[#out + 1] = e
                        end
                    end
                    -- your side first, then most EXP (tier breaks ties / covers a missing entry)
                    table.sort(out, function(a, b)
                        if a.mine ~= b.mine then return a.mine end
                        if a.xp ~= b.xp then return a.xp > b.xp end
                        return a.rank > b.rank
                    end)
                    return out
                end
                local function refresh()
                    byLabel = {}
                    local labels = {}
                    for _, h in ipairs(hunts()) do
                        local l = ('%s  %s  %s exp  [%s%s]%s  #%s'):format(h.boss, h.tier, fmtNum(h.xp), tostring(h.side or '?'),
                            h.mine and '' or ', not your side', h.left and ('  ' .. S.fmt(h.left)) or '', tostring(h.id))
                        byLabel[l] = h; labels[#labels + 1] = l
                    end
                    Options.SLHunt:SetValues(labels)
                    hStatus:SetText(('%d hunt(s) on the board'):format(#labels))
                end
                local function claim(h)
                    if not h then return false end
                    local ok, why = canClaim(h)
                    if ok ~= true then S.setText(hStatus, ('Not claimed - %s: %s'):format(h.boss, tostring(why))); return false end
                    S.fire('BossHuntsRequest', { action = 'Claim', id = h.id })
                    pendingId, pendingAt, pendingBoss = h.id, os.clock(), h.boss
                    S.setText(hStatus, ('Claim sent: %s  %s  %s exp'):format(h.boss, h.tier, fmtNum(h.xp)))
                    return true
                end
                hb:AddButton({ Text = 'Refresh', Func = refresh })
                    :AddButton({ Text = 'Claim selected', Func = function()
                        local h = byLabel[Options.SLHunt.Value or '']
                        if not h then Library:Notify('Pick a hunt (Refresh first)', 2); return end
                        claim(h)
                    end })
                hb:AddToggle('SLAutoHunt', { Text = 'Auto-claim best hunt', Default = false,
                    Tooltip = 'When you hold no hunt: claims your side\'s hunt worth the most EXP (reward x group factor, Muzan = Demon/Hybrid, Crow = Slayer/Hybrid), only when the game\'s own Quests.CanAddQuest passes (level band, race, the shared 30s quest cooldown, one hunt at a time) and never while Auto quest is about to accept. A claim that gets no hunt quest within 8s is not retried for that hunt, and the next try backs off (1 min, doubling to 10 min).' })
                hb:AddToggle('SLHuntPrefer', { Text = 'Farm prefers the hunted boss', Default = false,
                    Tooltip = 'While you hold a hunt and its boss is alive and loaded (within ~600 studs), Mob farm / Auto quest farm go for it, then glide back to your farm spot. Gives up on that boss for 10 min if you die on it or it loses under 5% HP in 60s (e.g. a Lv 200 Mythic you can\'t kill).' })
                local hHeld = hb:AddLabel('No hunt held', true)
                local function hasHuntQuest(list)
                    -- the BossHunt-category quest you hold (a claimed hunt needn't stay on the
                    -- board): its Holder key, boss Npc name, BossHunts entry and quest folder
                    local slot = S.data()
                    local holder = slot and slot:FindFirstChild('Quests') and slot.Quests:FindFirstChild('Holder')
                    if not holder then return nil end
                    local Q, BH = QMh(), BHm()
                    for _, f in ipairs(holder:GetChildren()) do
                        local qs = f:FindFirstChild('QuestString')
                        local key = (qs and qs.Value ~= '' and qs.Value) or f.Name
                        local cat
                        if Q and type(Q.GetQuestCategory) == 'function' then
                            local ok, c = pcall(Q.GetQuestCategory, key); if ok then cat = c end
                        end
                        -- unknown keys report 'Combat', so the key shape is the fallback
                        if cat == 'BossHunt' or key:match('^Eliminate ') ~= nil then
                            local boss, entry = key:match('^Eliminate (.+)$'), nil
                            if boss and BH and type(BH.Entry) == 'function' then
                                local ok, e = pcall(BH.Entry, boss); if ok then entry = e end
                            end
                            return key, boss, entry, f
                        end
                    end
                    return nil
                end
                -- Every second: (1) point the farm at the hunted boss while it is alive and
                -- loaded (S.huntMob; Mob Farm's pick() prefers it), with a give-up guard,
                -- (2) show the held hunt, (3) check the last claim took, (4) auto-claim.
                local lastClaim, lastHeld, claimGap = 0, nil, 5
                local skipUntil, skipWhy, chase = {}, {}, nil
                local function huntTick()
                    local now = os.clock()
                    local key, boss, _, f = hasHuntQuest()
                    local nb = boss and norm(boss)
                    -- give-up guard 1: we died (or respawned) while the farm was on the boss
                    local myHum = S.hum()
                    if chase and (chase.nb ~= nb or LP.Character ~= chase.char or not (myHum and myHum.Health > 0)) then
                        if chase.nb == nb then skipUntil[nb], skipWhy[nb] = now + 600, 'you died on it' end
                        chase = nil
                    end
                    local want, seen
                    if nb then
                        local r = S.root()
                        local farming = Toggles.SLMobFarm.Value or (Toggles.SLAutoQuest and Toggles.SLAutoQuest.Value)
                        for _, m in ipairs(S.mobs()) do
                            if norm(m.name) == nb then
                                seen = m
                                if Toggles.SLHuntPrefer.Value and farming and r and now >= (skipUntil[nb] or 0)
                                    and (m.root.Position - r.Position).Magnitude <= 600 then want = m end
                                break
                            end
                        end
                    end
                    -- give-up guard 2: under 5% of its HP gone in 60s of the farm being on it
                    if want then
                        local frac = want.hum.Health / math.max(want.hum.MaxHealth, 1)
                        if not chase or chase.model ~= want.model or now - chase.last > 5 then
                            chase = { nb = nb, model = want.model, char = LP.Character, hp = frac, at = now, last = now }
                        else
                            chase.last = now
                            if frac > chase.hp or chase.hp - frac >= 0.05 then chase.hp, chase.at = frac, now end
                            if now - chase.at > 60 then
                                skipUntil[nb], skipWhy[nb] = now + 600, 'under 5% damage in 60s'
                                want, chase = nil, nil
                            end
                        end
                    end
                    S.huntMob = want and want.name or nil
                    -- a boss we gave up on: the farm drops it and won't re-pick it (unless
                    -- Auto Quest's own quest is that boss - its stall timer handles that)
                    local questOnIt = S.questMob ~= nil and norm(S.questMob) == nb
                    S.huntDrop = (seen and now < (skipUntil[nb] or 0) and not questOnIt) and seen.model or nil
                    local txt = 'No hunt held'
                    if key then
                        local prog, tl = {}, ''
                        local tf = f and f:FindFirstChild('Tasks')
                        for _, t in ipairs(tf and tf:GetChildren() or {}) do
                            local v, mx = S.val(t, 'Value'), S.val(t, 'Max')
                            if v and mx then prog[#prog + 1] = ('%d/%d'):format(v, mx) end
                        end
                        local tm = f and f:FindFirstChild('Timer')
                        local st, tg = tonumber(S.val(tm, 'Started')), tonumber(S.val(tm, 'Target'))
                        if st and tg and st > 0 then tl = '  ' .. S.fmt(st + tg - os.time()) .. ' left' end
                        local state = want and 'farm is on it' or (seen and 'loaded' or 'not loaded')
                        if nb and now < (skipUntil[nb] or 0) then
                            state = ('farm skips it %s (%s)'):format(S.fmt(skipUntil[nb] - now), tostring(skipWhy[nb]))
                        end
                        txt = ('Hunting %s  %s%s  - %s'):format(tostring(boss or key), table.concat(prog, ', '), tl, state)
                    end
                    if txt ~= lastHeld then lastHeld = txt; S.setText(hHeld, txt) end
                    -- a claim that produced no hunt quest in 8s was ignored: don't repeat it
                    if key then
                        claimGap, pendingId = 5, nil
                    elseif pendingId and now - pendingAt > 8 then
                        failedIds[pendingId] = true
                        claimGap = math.min(math.max(claimGap, 30) * 2, 600)
                        S.setText(hStatus, ('Claim for %s got no hunt quest (the server may want your Crow board open - summon the Crow once). Next auto-claim in %s'):format(
                            tostring(pendingBoss), S.fmt(claimGap)))
                        pendingId = nil
                    end
                    if key or pendingId or not Toggles.SLAutoHunt.Value or now - lastClaim < claimGap then return end
                    -- never race Auto Quest's accept (both reset the shared 30s quest cooldown):
                    -- claim only while it holds its quest, not while it heads to / waits at an NPC
                    if S.farmPaused or S.questAcceptPending then return end
                    for _, h in ipairs(hunts()) do
                        if h.mine and not failedIds[h.id] and canClaim(h) == true then
                            lastClaim = now
                            claim(h)
                            return
                        end
                    end
                end
                task.spawn(function()
                    while not S.dead do
                        task.wait(1)
                        if not S.dead then
                            if not pcall(huntTick) then S.huntMob, S.huntDrop = nil, nil end
                        end
                    end
                end)
            end)()

            -- ================================================================
            -- COMBAT: auto parry/block vs mobs, telegraph dodge, anti-knockback
            -- ================================================================
            ;(function()
                local box = Tabs.Combat:AddLeftGroupbox('Auto Parry / Block')
                box:AddLabel('Blocking is the skill on F. A PERFECT parry = block\nlanding <=0.25s (vs mobs; 0.1s vs players) before the\nserver\'s hit check. Times each swing from the game\'s\nown Combat_presets (per weapon / mob / combo hit),\nminus your ping, re-checks right before pressing, and\ndashes when a block can\'t work.', true)
                box:AddToggle('SLAutoParry', { Text = 'Auto parry/block', Default = false })
                    :AddKeyPicker('SLAutoParryKey', { Default = 'None', SyncToggleState = true, Mode = 'Toggle', Text = 'Auto parry' })
                box:AddToggle('SLParryPlayers', { Text = 'Also vs players', Default = false, Tooltip = 'The player parry window is only 0.1s - unreliable above ~150ms ping.' })
                box:AddDropdown('SLParryTiming', { Values = { 'Exact (game data)', 'Fixed delay' }, Default = 1, Multi = false, Text = 'Timing',
                    Tooltip = 'Exact = the hit time for that weapon / mob / combo hit from Combat_presets (bears 0.40s, Gyorei\'s axe 0.35s...), minus ping. Fixed = press a set time after the swing starts (old behaviour).' })
                box:AddSlider('SLParryLead', { Text = 'Block lands before hit by', Default = 0.1, Min = 0, Max = 0.25, Rounding = 2, Suffix = ' s',
                    Tooltip = 'Exact mode. The perfect window vs mobs is the 0.25s before the hit; 0.1 aims inside it. Raise if you block too late, lower if you get plain blocks.' })
                box:AddSlider('SLParryPing', { Text = 'Ping compensation', Default = 100, Min = 0, Max = 150, Rounding = 0, Suffix = ' %',
                    Tooltip = 'Exact mode. Press this much of your round-trip ping earlier (the swing reaches you half a ping late, your block reaches the server half a ping late).' })
                box:AddSlider('SLParryDelay', { Text = 'Fixed press delay', Default = 0.1, Min = 0, Max = 0.6, Rounding = 2, Suffix = ' s',
                    Tooltip = 'Fixed mode only: wait after the swing starts before pressing block.' })
                box:AddSlider('SLParryMargin', { Text = 'Hitbox margin', Default = 2, Min = 0, Max = 8, Rounding = 1, Suffix = ' studs',
                    Tooltip = 'Only block when you are inside the attacker\'s real M1 box (its weapon preset, facing, run stretch) plus this margin. Raise if swings clip you from the edge.' })
                box:AddSlider('SLParryHold', { Text = 'Hold block for', Default = 0.55, Min = 0.15, Max = 2, Rounding = 2, Suffix = ' s',
                    Tooltip = 'Released this long after the LAST swing, so a whole combo is blocked.' })
                box:AddDropdown('SLParryFallback', { Values = { 'Dash if block useless or no perfect', 'Dash only if block useless', 'Never dash' },
                    Default = 1, Multi = false, Text = 'When a block won\'t work',
                    Tooltip = 'Read from your server values: PierceBlock (pierced) or a broken guard = the block does nothing. Hit in the last 1s / stunned = no PERFECT is possible (server rule). Dash out instead. While farming, the farm hops out instead of dashing.' })
                box:AddToggle('SLParryLog', { Text = 'Log parry timing', Default = false,
                    Tooltip = 'Console: predicted hit time per swing and what happened (blocked / HIT). Use it to tune Lead and Ping.' })
                box:AddDropdown('SLBlockKey', { Values = { 'F', 'Q', 'E', 'R', 'T', 'G', 'H', 'V' }, Default = 1, Multi = false, Text = 'Block key',
                    Tooltip = 'Your in-game Block keybind (default F).' })
                local holdUntil, keyDown, keyCode = 0, false, Enum.KeyCode.F
                local pending = setmetatable({}, { __mode = 'k' }) -- [model] = clock of the last scheduled swing
                local lastDash = 0
                local function blockPulse()
                    holdUntil = math.max(holdUntil, os.clock() + Options.SLParryHold.Value)
                    if not keyDown then
                        keyCode = Enum.KeyCode[Options.SLBlockKey.Value or 'F'] or Enum.KeyCode.F
                        keyDown = true
                        pcall(function() VIM:SendKeyEvent(true, keyCode, false, game) end)
                    end
                end
                htrack(RunService.Heartbeat:Connect(function()
                    if keyDown and os.clock() > holdUntil then
                        keyDown = false
                        pcall(function() VIM:SendKeyEvent(false, keyCode, false, game) end)
                    end
                end))
                htrack({ Disconnect = function() if keyDown then pcall(function() VIM:SendKeyEvent(false, keyCode, false, game) end) end end })
                -- Mob Farm "Block when a mob attacks": active while the farm sits on a mob.
                local function farmBlocking()
                    return S.farmLocked and Toggles.SLFarmBlock and Toggles.SLFarmBlock.Value
                end
                -- Block state from Player_Service.Values.<me> (BlockingServer / Checker rules).
                local function blockState()
                    local v = S.values()
                    if not v then return false, false end
                    local useless = v:FindFirstChild('PierceBlock') ~= nil
                    local blk = v:FindFirstChild('Blocking') or LP:FindFirstChild('Blocking')
                    if blk and blk:IsA('ValueBase') and (blk:GetAttribute('BreakAt') ~= nil or (tonumber(blk.Value) or 1) <= 0) then useless = true end
                    local noPerfect = v:FindFirstChild('Stun') ~= nil or v:FindFirstChild('CombatStun') ~= nil
                    local dmg = v:FindFirstChild('DMG')
                    local la = dmg and dmg:GetAttribute('LastAttacked')
                    local U = S.req('CAM.Global.Utility')
                    if la and U and type(U.Tick) == 'function' then
                        local ok, now = pcall(U.Tick)
                        if ok and type(now) == 'number' and now - la < 1 then noPerfect = true end
                    end
                    return useless, noPerfect
                end
                -- Is our root inside the attacker's M1 box (+margin)?
                local function inReach(model, preset, combo)
                    local wr, root = model:FindFirstChild('HumanoidRootPart'), S.root()
                    if not (wr and root) then return false end
                    local ok, cf, size = pcall(S.m1Box, wr, preset, combo, false)
                    if not ok then return (root.Position - wr.Position).Magnitude < 14 end
                    local m = Options.SLParryMargin.Value
                    local lp = cf:PointToObjectSpace(root.Position)
                    -- Vertical: our feet (S.m1Legs(), the SAME number the farm's heightFor uses) vs
                    -- the box top. For a mob that top is the higher of this swing's box and its real
                    -- preset's worst combo (S.mobBoxTop). While the farm pins us on a mob there is no
                    -- extra margin: the farm parks our feet S.FARM_CLEAR above exactly that top, so a
                    -- swing that can't reach never stops M1 / holds block (the old +0.5 margin was
                    -- bigger than the farm's 0.15 + 0.3 tweak clearance). Otherwise a small margin.
                    local legs = S.m1Legs()
                    local top = size.Y / 2
                    local isMob = model:GetAttribute('IsMob') and true or false
                    if isMob and S.mobBoxTop then
                        top = math.max(top, S.mobBoxTop(model) - (cf.Position.Y - wr.Position.Y))
                    end
                    local tol = (isMob and S.farmLocked) and 0 or math.min(m, 0.5)
                    return math.abs(lp.X) <= size.X / 2 + m and math.abs(lp.Z) <= size.Z / 2 + m
                        and lp.Y - legs <= top + tol and lp.Y + 2 >= -size.Y / 2 - m
                end
                local function dashOut()
                    if os.clock() - lastDash < 1 then return end
                    lastDash = os.clock()
                    local DH = S.req('CAM.Client.Modules.GamePlay.Dash_Handler')
                    if DH then pcall(DH.Perform, 'S') end
                end
                -- The moment the block has to go out: re-validate, then block / dash.
                local function fire(model, track, preset, combo, why)
                    -- Kill Aura is holding a skill key: a block press (F = Skills_1st) goes through
                    -- Attempt_Hold('Blocking'), which StopHolds a held skill it can't play over
                    -- (Skill_Controller.lua:141-150) - wasting it, or (Flame Tiger under 0.3s)
                    -- flipping it to its projectile branch. A dash would drag the skill's boxes.
                    if S.kaCasting then return end
                    local farm = farmBlocking()
                    if not (Toggles.SLAutoParry.Value or farm) then return end
                    if S.farmLocked and not farm then return end
                    if track and not track.IsPlaying then return end -- feinted / cancelled / stunned
                    local hum = model:FindFirstChildOfClass('Humanoid')
                    if not (model.Parent and hum and hum.Health > 0) then return end
                    if not inReach(model, preset, combo) then return end -- walked off / swing can't reach us
                    local useless, noPerfect = blockState()
                    local fb = Options.SLParryFallback.Value
                    local dash = (useless and fb ~= 'Never dash') or (noPerfect and fb == 'Dash if block useless or no perfect')
                    local myHum = S.hum()
                    local hp = myHum and myHum.Health
                    -- On the farm the hop-out goes through S.farmDodge (= the farm's triggerDodge),
                    -- which returns early while "Dodge mob skills" is off - that left the swing
                    -- with neither a hop NOR a block. Then: no perfect possible -> block anyway (a
                    -- chip block still beats a clean hit; the farm pins the root, so a real dash
                    -- would do nothing); block useless (pierced / guard broken) -> leave it and keep
                    -- M1 going, since blocking would only pause M1 for nothing (old behaviour).
                    if dash and S.farmLocked and not (S.farmDodge and Toggles.SLFarmDodge and Toggles.SLFarmDodge.Value) then
                        if useless then
                            if Toggles.SLParryLog.Value then
                                print(('[Parry] %s %s -> SKIP [block useless, farm dodge off] (M1 continues)'):format(model.Name, tostring(why)))
                            end
                            return
                        end
                        dash = false
                    end
                    if dash then
                        if S.farmLocked and S.farmDodge then S.farmDodge(model, 'unblockable swing', 0, 0.45)
                        else dashOut() end
                    else
                        if farm then
                            S.farmBlockUntil = math.max(S.farmBlockUntil or 0, os.clock() + Options.SLParryHold.Value + 0.05)
                            if S.releaseM1 then S.releaseM1() end
                        end
                        blockPulse()
                    end
                    if Toggles.SLParryLog.Value then
                        task.delay(0.45, function()
                            local h2 = S.hum() and S.hum().Health
                            local res = (hp and h2 and h2 < hp - 0.5) and ('HIT -%d'):format(math.floor(hp - h2 + 0.5)) or 'no damage'
                            print(('[Parry] %s %s -> %s%s (%s)'):format(model.Name, why, dash and 'DASH' or 'BLOCK',
                                useless and ' [block useless]' or (noPerfect and ' [no perfect]' or ''), res))
                        end)
                    end
                end
                -- Schedule a swing. From the anim cue, TimePosition = time already gone;
                -- from the _Swings effect cue, before_swing has already gone.
                local function schedule(model, track, info, combo, run, fromCue)
                    local farm = farmBlocking()
                    if not (Toggles.SLAutoParry.Value or farm) then return end
                    if S.farmLocked and not farm then return end -- farm without block: don't interrupt our M1s
                    if typeof(model) ~= 'Instance' or model == LP.Character then return end
                    local isPlayer = Players:GetPlayerFromCharacter(model) ~= nil
                    if isPlayer and not Toggles.SLParryPlayers.Value then return end
                    if not isPlayer and not model:GetAttribute('IsMob') then return end
                    local wr, root = model:FindFirstChild('HumanoidRootPart'), S.root()
                    if not (wr and root) or (root.Position - wr.Position).Magnitude > 60 then return end
                    if fromCue then
                        if pending[model] and os.clock() - pending[model] < 0.8 then return end -- the anim cue already has it
                    elseif pending[model] and os.clock() - pending[model] < 0.12 then return end
                    pending[model] = os.clock()
                    local preset, pname = S.swingPreset(model, info)
                    local hitAt, swingAt = S.swingTiming(preset, combo, run)
                    local d
                    if Options.SLParryTiming.Value == 'Fixed delay' then
                        d = Options.SLParryDelay.Value - (fromCue and swingAt or 0)
                    else
                        local elapsed = fromCue and swingAt or (track and track.TimePosition / math.max(track.Speed, 0.05) or 0)
                        d = hitAt - elapsed - S.pingSec() * Options.SLParryPing.Value / 100 - Options.SLParryLead.Value
                    end
                    local why = ('%s hit %d%s @%.2fs'):format(pname or '?', combo, run and ' (run)' or '', hitAt)
                    if d > 0 then task.delay(d, fire, model, track, preset, combo, why) else fire(model, track, preset, combo, why) end
                end
                -- cue 1 (fallback): "<Weapon>_Swings"(attacker, combo, run) effect, sent at before_swing
                task.spawn(function()
                    local holder = S.find(EFFECTS)
                    local ev = holder and holder:WaitForChild('Event', 60)
                    if not ev then return end
                    htrack(ev.OnClientEvent:Connect(function(name, who, combo, run)
                        if type(name) == 'string' and name:sub(-7) == '_Swings' and typeof(who) == 'Instance' then
                            local info = { skill = name:sub(1, -8) .. '_Combat_Anims' }
                            schedule(who, nil, info, tonumber(combo) or 1, run == true, true)
                        end
                    end))
                end)
                -- cue 2 (primary): replicated Swing_N / Run_Hit animation, hooked the moment
                -- an Animator appears (mobs + player characters), dropped when the model goes.
                local hooked = setmetatable({}, { __mode = 'k' })
                local function hookAnimator(an)
                    if hooked[an] or not an:IsA('Animator') then return end
                    local model = an:FindFirstAncestorOfClass('Model')
                    if not model or model == LP.Character then return end
                    hooked[an] = true
                    S.bindLife(model, an.AnimationPlayed:Connect(function(track)
                        -- replicated tracks are all named "Animation": match the id instead
                        local info = S.animInfo(track)
                        if info.kind ~= 'swing' then return end
                        local run = info.phase == 'Run_Hit'
                        local combo = run and 1 or (tonumber(tostring(info.phase):match('Swing_(%d+)')) or 1)
                        schedule(model, track, info, combo, run, false)
                    end))
                end
                task.spawn(function()
                    local hs = workspace:FindFirstChild('Humanoids') or workspace:WaitForChild('Humanoids', 60)
                    if not hs then return end
                    for _, d in ipairs(hs:GetDescendants()) do if d:IsA('Animator') then hookAnimator(d) end end
                    htrack(hs.DescendantAdded:Connect(function(d) if d:IsA('Animator') then task.defer(hookAnimator, d) end end))
                end)
                local function hookChar(c)
                    if not c then return end
                    for _, d in ipairs(c:GetDescendants()) do if d:IsA('Animator') then hookAnimator(d) end end
                    S.bindLife(c, c.DescendantAdded:Connect(function(d) if d:IsA('Animator') then task.defer(hookAnimator, d) end end))
                end
                local function hookPlayer(p)
                    if p == LP then return end
                    hookChar(p.Character)
                    htrack(p.CharacterAdded:Connect(hookChar))
                end
                for _, p in ipairs(Players:GetPlayers()) do hookPlayer(p) end
                htrack(Players.PlayerAdded:Connect(hookPlayer))

                -- ---- Telegraph auto-dodge (world-boss ground AoEs) ------------
                local tb = Tabs.Combat:AddLeftGroupbox('Telegraph Dodge')
                tb:AddLabel('Bosses with CastTelegraph (Datai, Gyutai, Reaper,\nSaneri...) draw their AoE as workspace.Debree\n"<id>-Telegraph". If you\'re standing in it, dash out\n(plain dash = no i-frames, it just moves you ~12 studs).', true)
                tb:AddToggle('SLTeleDodge', { Text = 'Auto-dodge telegraphs', Default = false })
                tb:AddDropdown('SLDodgeDir', { Values = { 'Back', 'Left', 'Right', 'Alternate L/R' }, Default = 4, Multi = false, Text = 'Dash direction' })
                tb:AddSlider('SLDodgeDelay', { Text = 'Dodge delay', Default = 0.2, Min = 0, Max = 1.5, Rounding = 2, Suffix = ' s',
                    Tooltip = 'Wait after the telegraph appears (lets its shape build) before checking + dashing.' })
                local flip = false
                local function dash()
                    local DH = S.req('CAM.Client.Modules.GamePlay.Dash_Handler')
                    if not DH then return end
                    local m = Options.SLDodgeDir.Value
                    local letter = (m == 'Back' and 'S') or (m == 'Left' and 'A') or (m == 'Right' and 'D') or nil
                    if not letter then flip = not flip; letter = flip and 'A' or 'D' end
                    pcall(DH.Perform, letter)
                end
                local function inside(folder, pos)
                    for _, p in ipairs(folder:GetDescendants()) do
                        if p:IsA('BasePart') then
                            local lp = p.CFrame:PointToObjectSpace(pos)
                            if p:IsA('Part') and p.Shape == Enum.PartType.Cylinder then
                                local r = math.max(p.Size.Y, p.Size.Z) / 2 + 3
                                if math.sqrt(lp.Y * lp.Y + lp.Z * lp.Z) <= r then return true end
                            elseif math.abs(lp.X) <= p.Size.X / 2 + 3 and math.abs(lp.Z) <= p.Size.Z / 2 + 3 then
                                return true
                            end
                        end
                    end
                    return false
                end
                task.spawn(function()
                    local debree = workspace:FindFirstChild('Debree') or workspace:WaitForChild('Debree', 60)
                    if not debree then return end
                    htrack(debree.ChildAdded:Connect(function(f)
                        if not (Toggles.SLTeleDodge.Value and f.Name:match('%-Telegraph$')) then return end
                        task.delay(Options.SLDodgeDelay.Value, function()
                            -- The shape plates come with a LATER phase call than the empty "Start"
                            -- folder (Effects/Core/Telegraph.lua), so one look at +delay often saw no
                            -- plate at all: keep looking for up to 1s. While the Mob farm has a target
                            -- it hops out of telegraphs itself and re-pins the root every frame, so a
                            -- dash here would only burn the dash.
                            local t0 = os.clock()
                            while not S.dead and f.Parent and not f:GetAttribute('Cancelled') and os.clock() - t0 < 1 do
                                if S.farmHasTarget and Toggles.SLFarmDodge and Toggles.SLFarmDodge.Value then return end
                                local root = S.root()
                                if root and inside(f, root.Position) then dash(); return end
                                RunService.Heartbeat:Wait()
                            end
                        end)
                    end))
                end)

                -- ---- Anti-knockback -------------------------------------------
                local kb = Tabs.Combat:AddRightGroupbox('Anti-Knockback')
                kb:AddLabel('Knockback / air-juggle movers are inserted on YOUR\nroot (combat_knockback, regular_bv, air_combo_bp) and\nyou own your physics, so deleting them works - the\ngame\'s own Dash does the same. Stun still applies.', true)
                kb:AddToggle('SLAntiKB', { Text = 'Anti-knockback', Default = false })
                local KB = { combat_knockback = true, regular_bv = true, air_combo_bp = true }
                local function hookRoot(root)
                    htrack(root.ChildAdded:Connect(function(c)
                        if Toggles.SLAntiKB.Value and KB[c.Name] then task.defer(function() pcall(c.Destroy, c) end) end
                    end))
                end
                local function onChar(c)
                    local r = c:WaitForChild('HumanoidRootPart', 15)
                    if r then hookRoot(r) end
                end
                if LP.Character then task.spawn(onChar, LP.Character) end
                htrack(LP.CharacterAdded:Connect(onChar))

                -- ---- Skill aim assist (silent aim) ----------------------------
                local ab = Tabs.Combat:AddRightGroupbox('Skill Aim Assist')
                ab:AddLabel('Every skill/tool reads its aim from Platform_Handler.\nmousepos. This returns the target\'s position instead.\nThe server clamps aim to each skill\'s range, so it\nfixes accuracy, not reach.', true)
                ab:AddToggle('SLAim', { Text = 'Aim skills at target', Default = false })
                    :AddKeyPicker('SLAimKey', { Default = 'None', SyncToggleState = true, Mode = 'Toggle', Text = 'Skill aim' })
                ab:AddToggle('SLAimPlayers', { Text = 'Include players', Default = false })
                ab:AddSlider('SLAimFov', { Text = 'Cursor radius', Default = 220, Min = 40, Max = 800, Rounding = 0, Suffix = ' px',
                    Tooltip = 'Only targets whose screen position is within this many pixels of your cursor.' })
                local aimLabel = ab:AddLabel('Target: none')
                local aimTarget -- a HumanoidRootPart
                local PH = S.req('CAM.Client.Controllers.Platform_Handler')
                if PH and type(PH.mousepos) == 'function' then
                    local orig = PH.mousepos
                    PH.mousepos = function(a1, a2, a3)
                        -- Kill Aura skill casts own the aim for their cast window: the point it
                        -- scored (S.kaAim), with the same radius clamp as below.
                        if S.kaAim and os.clock() < (S.kaAimUntil or 0) then
                            local kaPos, r = S.kaAim, S.root()
                            if a1 ~= nil and r and (kaPos - r.Position).Magnitude > a1 then
                                kaPos = r.Position + (kaPos - r.Position).Unit * a1
                            end
                            return kaPos
                        end
                        if Toggles.SLAim and Toggles.SLAim.Value and aimTarget and aimTarget.Parent then
                            local pos = aimTarget.Position
                            local r = S.root()
                            if a1 ~= nil and r and (pos - r.Position).Magnitude > a1 then -- mirror the original's radius clamp
                                pos = r.Position + (pos - r.Position).Unit * a1
                            end
                            return pos
                        end
                        return orig(a1, a2, a3)
                    end
                    htrack({ Disconnect = function() PH.mousepos = orig end })
                else
                    ab:AddLabel('Platform_Handler not loaded - aim assist unavailable.', true)
                end
                local acc2, lastName = 0, nil
                htrack(RunService.Heartbeat:Connect(function(dt)
                    acc2 = acc2 + dt; if acc2 < 0.1 then return end; acc2 = 0
                    if not Toggles.SLAim.Value then aimTarget = nil; return end
                    local cam = workspace.CurrentCamera; if not cam then return end
                    local mouse = UIS:GetMouseLocation()
                    local best, bestD
                    local function consider(root)
                        local sp, on = cam:WorldToViewportPoint(root.Position)
                        if on then
                            local d = (Vector2.new(sp.X, sp.Y) - mouse).Magnitude
                            if d <= Options.SLAimFov.Value and (not bestD or d < bestD) then best, bestD = root, d end
                        end
                    end
                    for _, m in ipairs(S.mobs()) do consider(m.root) end
                    if Toggles.SLAimPlayers.Value then
                        for _, p in ipairs(Players:GetPlayers()) do
                            local c = p ~= LP and p.Character
                            local r = c and c:FindFirstChild('HumanoidRootPart')
                            local h = c and c:FindFirstChildOfClass('Humanoid')
                            if r and h and h.Health > 0 then consider(r) end
                        end
                    end
                    aimTarget = best
                    local nm = best and best.Parent and best.Parent.Name or 'none'
                    if nm ~= lastName then lastName = nm; aimLabel:SetText('Target: ' .. nm) end
                end))
            end)()

            -- ================================================================
            -- HITBOX VIEWER: draw the server's M1 box (Combat_presets.Get_Players_For_Combat)
            -- ================================================================
            -- Box = 6 wide x 6.25 tall x 9 deep, centred on root*(0,-1,0) (+YOffsets),
            -- aimed along your move direction (look vector when still), stretched
            -- forward by max(MinHitboxSize + Reaches, run speed) and pushed 0.75x that
            -- ahead (+ZOffsets). Hit 7 adds 4 width / 7 depth; NPC boxes are /1.2.
            -- Widths/Depths come from the weapon's preset. Local-only adornments.
            ;(function()
                local box = Tabs.Combat:AddRightGroupbox('Hitbox Viewer')
                box:AddLabel('Draws the exact box the SERVER uses for M1 hits\n(from Combat_presets). It stretches forward while\nyou run - that is real, running M1s reach further.', true)
                box:AddToggle('SLShowHitbox', { Text = 'Show my M1 hitbox', Default = false })
                    :AddKeyPicker('SLShowHitboxKey', { Default = 'None', SyncToggleState = true, Mode = 'Toggle', Text = 'Show hitbox' })
                local CPm = S.req('CAM.Global.Combat_presets')
                local names = { 'Current weapon' }
                if CPm and type(CPm.Presets) == 'table' then
                    local list = {}
                    for n in pairs(CPm.Presets) do list[#list + 1] = tostring(n) end
                    table.sort(list)
                    for _, n in ipairs(list) do names[#names + 1] = n end
                end
                box:AddDropdown('SLHitboxWeapon', { Values = names, Default = 1, Multi = false, Text = 'Weapon',
                    Tooltip = 'Preview any weapon\'s range, or follow what you have equipped.' })
                box:AddSlider('SLHitboxHit', { Text = 'Combo hit', Default = 1, Min = 1, Max = 7, Rounding = 0,
                    Tooltip = 'Some weapons change reach per hit; hit 7 (the finisher) is 4 wider and 7 deeper.' })
                box:AddToggle('SLHitboxMobs', { Text = 'Also show nearby mob hitboxes', Default = false,
                    Tooltip = 'Red boxes for mobs within 60 studs (their equipped weapon preset, NPC size).' })
                local info = box:AddLabel('')
                if not CPm then box:AddLabel('Combat_presets not loaded - viewer unavailable.', true); return end
                local CIP = S.req('CAM.Global.Character_info_provider')

                local function presetFor(who)
                    local sel = Options.SLHitboxWeapon.Value
                    if who == LP and sel and sel ~= 'Current weapon' and CPm.Presets[sel] then return CPm.Presets[sel], sel end
                    local tool
                    -- Shared S.m1Preset: mobs = NpcMimicFolder.Equipped_Tool, normalised (Cutlass ->
                    -- Regular Katana...); CIP.Get_equipped_tool returns nil for every NPC.
                    if S.m1Preset then
                        local p, n = S.m1Preset(who)
                        if p then return p, n end
                    end
                    if CIP and CIP.Get_equipped_tool then
                        local ok, t = pcall(CIP.Get_equipped_tool, who)
                        if ok then tool = t end
                    end
                    local nm = tool and tool.Name
                    return (nm and CPm.Presets[nm]) or CPm.Presets.Combat, nm or 'Combat'
                end
                -- Mirror of Get_Players_For_Combat's geometry -> (CFrame, Size)
                local boxFor = S.m1Box

                local pool = {}
                local function adorn(i, color)
                    local a = pool[i]
                    if not (a and a.Parent) then
                        a = Instance.new('BoxHandleAdornment')
                        a.Adornee = workspace.Terrain -- Terrain sits at the origin, so CFrame = world space
                        a.AlwaysOnTop = true
                        a.ZIndex = 5
                        a.Transparency = 0.75
                        a.Parent = workspace.CurrentCamera
                        pool[i] = a
                    end
                    a.Color3 = color
                    return a
                end
                local function hideFrom(n) for i = n, #pool do if pool[i] then pool[i].Visible = false end end end
                local lastInfo = 0
                htrack(RunService.RenderStepped:Connect(function()
                    if not Toggles.SLShowHitbox.Value then hideFrom(1); return end
                    local idx = Options.SLHitboxHit.Value
                    local n = 0
                    local root = S.root()
                    if root then
                        local preset, wname = presetFor(LP)
                        local ok, cf, size = pcall(boxFor, root, preset, idx, false)
                        if ok then
                            n = n + 1
                            local a = adorn(n, Color3.fromRGB(80, 255, 120))
                            a.CFrame, a.Size, a.Visible = cf, size, true
                            if os.clock() - lastInfo > 0.3 then
                                lastInfo = os.clock()
                                S.setText(info, ('%s  hit %d:  %.1f wide x %.1f tall x %.1f deep'):format(wname, idx, size.X, size.Y, size.Z))
                            end
                        end
                        if Toggles.SLHitboxMobs.Value then
                            for _, m in ipairs(S.mobs()) do
                                if n >= 12 then break end
                                if (m.root.Position - root.Position).Magnitude < 60 then
                                    local mp = presetFor(m.model)
                                    local ok2, mcf, msize = pcall(boxFor, m.root, mp, 1, true)
                                    if ok2 then
                                        n = n + 1
                                        local a = adorn(n, Color3.fromRGB(255, 70, 70))
                                        a.CFrame, a.Size, a.Visible = mcf, msize, true
                                    end
                                end
                            end
                        end
                    end
                    hideFrom(n + 1)
                end))
                htrack({ Disconnect = function() for _, a in pairs(pool) do pcall(a.Destroy, a) end end })
            end)()

            -- ================================================================
            -- MOB MAGNET (experimental): park mobs WE network-own inside our M1 box
            -- ================================================================
            -- Hostile mobs are server-owned. In the decompiled server skill code only
            -- four skills hand the CASTER network ownership of a mob's root, and none
            -- of them ever takes it back:
            --   Scyther Vortex (Sickles)         captureVictim -> root:SetNetworkOwner(caster)
            --   War Gale Wind (War Fans)         captureVictim -> same
            --   Rising Dust Storm (Wind, V1+V2)  captureVictim -> same
            --   Obi Charge (Obi Manipulation)    carry grab    -> same
            -- The only visible resets are the mob's own NpcConfig.Signals.TouchedWater
            -- (SetNetworkOwner(nil) + MoveTo its spawn) and death (a fresh model).
            -- Release runs Combat_Util.RagDoll / Knockback, which live in ServerStorage
            -- (not in the dump) and MAY take ownership back - hence "Probe only".
            -- The server M1 box takes every model with a DIRECT child part inside it
            -- (Get_Players_For_Combat -> Utility.GetModelInRegion), so an owned mob can
            -- be parked in our box: under our feet, at a depth where our box still
            -- reaches its top but ITS box (worst combo) stays below our feet. A mob
            -- with no such depth is left alone. No remotes are fired, but the CFrames
            -- we write replicate to the server (that is the point) and to every player.
            -- isnetworkowner is re-checked every frame; a mob we stop owning is never
            -- touched again. Heartbeat is only connected while the toggle is on.
            ;(function()
                local box = Tabs.Farm:AddRightGroupbox('Mob Magnet')
                box:AddLabel('Only moves mobs YOUR client network-owns. That\nhappens after you catch them with Scyther Vortex,\nWar Gale Wind, Rising Dust Storm or Obi Charge -\nwithout one of those it stays at 0 and does nothing.', true)
                local status = box:AddLabel('owned mobs: -', true)
                box:AddToggle('SLMagnet', { Text = 'Mob magnet (experimental)', Default = false,
                    Tooltip = 'EXPERIMENTAL. Owned mobs near you (isnetworkowner) are parked just under your feet inside your M1 box, at a depth where your box still reaches them but theirs (worst combo) cannot reach you; a mob with no such spot is left alone. One M1 then hits all of them. Only Scyther Vortex, War Gale Wind, Rising Dust Storm and Obi Charge ever give you a mob - otherwise nothing happens. No remotes are fired, but the positions you set replicate to the server (and every player) through network ownership: anyone watching sees mobs glued under you.' })
                box:AddToggle('SLMagProbe', { Text = 'Probe only (move nothing)', Default = true,
                    Tooltip = 'Counts owned mobs and shows what the magnet WOULD do, without moving anything. Check this first: catch mobs with your capture skill and watch "owned" after they are released and after your first M1 lands. The release ragdoll / knockback code is server-only and may take ownership back - if the count drops to 0, the magnet can never do anything for you. Untick to let it move mobs.' })
                box:AddToggle('SLMagFarmOnly', { Text = 'Only while Mob Farm is locked on', Default = true,
                    Tooltip = 'Only works while Mob Farm / Auto Quest sits on its target (that is what keeps you above the mobs). Off = also while you play normally, which drags owned mobs along with you - the most visible use, with no farm benefit.' })
                box:AddSlider('SLMagRadius', { Text = 'Magnet radius', Default = 30, Min = 8, Max = 80, Rounding = 0, Suffix = ' studs',
                    Tooltip = 'Owned mobs within this distance of you get pulled in. A mob is never dragged more than 100 studs from where it was first pulled.' })
                box:AddSlider('SLMagMax', { Text = 'Max mobs stacked', Default = 4, Min = 1, Max = 8, Rounding = 0,
                    Tooltip = 'Slots in your M1 box (small offsets so they don\'t sit inside each other).' })
                box:AddSlider('SLMagSpeed', { Text = 'Pull speed', Default = 60, Min = 20, Max = 300, Rounding = 0, Suffix = ' studs/s',
                    Tooltip = 'Owned mobs glide to their slot at this speed. Mobs run at 25 studs/s (NpcConfig Spawning RunSpeed), so much more than that reads as a snap to anyone watching.' })
                box:AddSlider('SLMagPlayers', { Text = 'Pause if a player is within', Default = 100, Min = 0, Max = 300, Rounding = 0, Suffix = ' studs',
                    Tooltip = 'Moves nothing while another player is this close (they would see it). 0 = never pause. Mobs another player is fighting (their NpcsFollowing) are never moved.' })
                box:AddToggle('SLMagBosses', { Text = 'Also move bosses', Default = false,
                    Tooltip = 'A boss glued under you is the most visible thing this can do. Off = bosses are never moved.' })
                box:AddLabel('Waits while a mob is in the vortex, carried, knocked\nback or ragdolled; holds counter-armed / perfect-\nblocking mobs just outside your box; pauses while\nthe farm travels or dodges. Parked mobs feed the\nfarm\'s skill dodge. Never parks a mob on water.', true)
                local isOwner = isnetworkowner or is_network_owner
                if not isOwner then box:AddLabel('Executor lacks isnetworkowner - magnet disabled.', true) end
                local function owns(part)
                    local ok, r = pcall(isOwner, part)
                    return ok and r == true and not part.Anchored
                end

                local CPm = S.req('CAM.Global.Combat_presets')
                local P = CPm and type(CPm.Presets) == 'table' and CPm.Presets or nil
                local Items -- CAM.Global.Collectibles.Items (false = failed to load)
                local SF    -- CAM.Global.Subsets.Gameplay.StatsFetch (loaded on first enable; false = failed)
                -- A mob's M1 preset: AiPrerequistes.NpcMimicFolder.Equipped_Tool (AiMimic),
                -- else that item's CombatPreset, else Regular Katana / Combat.
                local function mobPreset(model)
                    if not P then return nil end
                    local v = S.val(model, 'AiPrerequistes', 'NpcMimicFolder', 'Equipped_Tool')
                    if type(v) ~= 'string' or v == '' then return P.Combat end
                    if P[v] then return P[v] end
                    if Items == nil then Items = S.req('CAM.Global.Collectibles.Items') or false end
                    local it = type(Items) == 'table' and Items[v]
                    local cp = type(it) == 'table' and it.CombatPreset
                    return (cp and P[cp]) or P['Regular Katana'] or P.Combat
                end
                -- Largest value a per-combo preset table can give (HandDemon Widths
                -- {Default=10,[3]=12}). A combo with no entry and no Default uses 0.
                local function tmax(t)
                    if type(t) ~= 'table' then return 0 end
                    local m = (t.Default == nil) and 0 or nil
                    for _, v in pairs(t) do
                        if type(v) == 'number' and (m == nil or v > m) then m = v end
                    end
                    return m or 0
                end
                -- Extent of a model's DIRECT child parts in its root's frame (GetModelInRegion
                -- keeps a part only when its Parent is the Model - accessory handles never
                -- count): top = highest point, feet = lowest point below the root,
                -- rad = horizontal half-diagonal of its footprint.
                local function measure(model, r)
                    local top, feet, ax, az
                    local rcf = r.CFrame
                    for _, p in ipairs(model:GetChildren()) do
                        if p:IsA('BasePart') then
                            local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = rcf:ToObjectSpace(p.CFrame):GetComponents()
                            local sz = p.Size
                            local hx = (math.abs(r00) * sz.X + math.abs(r01) * sz.Y + math.abs(r02) * sz.Z) / 2
                            local hy = (math.abs(r10) * sz.X + math.abs(r11) * sz.Y + math.abs(r12) * sz.Z) / 2
                            local hz = (math.abs(r20) * sz.X + math.abs(r21) * sz.Y + math.abs(r22) * sz.Z) / 2
                            top = math.max(top or -1e9, y + hy)
                            feet = math.max(feet or -1e9, hy - y)
                            ax = math.max(ax or 0, math.abs(x) + hx)
                            az = math.max(az or 0, math.abs(z) + hz)
                        end
                    end
                    return top, feet, ax and math.sqrt(ax * ax + az * az)
                end
                -- Ragdolled = RagdollHandler's state (Humanoid Physics) or any ragdoll
                -- RigidJoint with Part1 cleared (RagdollHandler.setRagdollEnabled). Scyther
                -- Vortex ragdolls every victim for BURST_STUN 1.3s as it lets go.
                local PHYSICS = Enum.HumanoidStateType.Physics
                local function ragdolled(model, hum)
                    if hum.PlatformStand or hum:GetState() == PHYSICS then return true end
                    local rc = model:FindFirstChild('RagdollConstraints')
                    if rc then
                        for _, c in ipairs(rc:GetChildren()) do
                            local j = c:FindFirstChild('RigidJoint')
                            local jv = j and j:IsA('ObjectValue') and j.Value
                            if jv and jv:IsA('JointInstance') and jv.Part1 == nil then return true end
                        end
                    end
                    return false
                end
                -- Per-model shape, measured once the rig is intact (callers check ragdolled
                -- first) and cached for the model's life. reach = top of ITS M1 box vs its
                -- root: centre -1 + YOffsets, height 6.25 + Widths, max over every combo,
                -- no NPC shrink (worst case, same rule as the farm's Auto height).
                local shapes = setmetatable({}, { __mode = 'k' })
                local function shapeOf(model, r)
                    local s = shapes[model]
                    if s then return s end
                    local top, feet, rad = measure(model, r)
                    if not top then return nil end
                    local preset = mobPreset(model)
                    s = {
                        top = math.clamp(top, 0.5, 30), feet = math.clamp(feet, 0.5, 30), rad = math.clamp(rad, 1, 20),
                        reach = -1 + tmax(preset and preset.YOffsets) + (6.25 + tmax(preset and preset.Widths)) / 2,
                    }
                    shapes[model] = s
                    return s
                end

                local cands, seen, slotOf, slotUsed, holding, others = {}, {}, {}, {}, {}, {}
                local origin = setmetatable({}, { __mode = 'k' }) -- where we first moved each mob from (leash)
                -- Camps reset mobs past Spawning.DespawnDistance (150 default, 250+ on the
                -- live camps) from their Center: 100 stays inside both.
                local LEASH = 100
                -- Slots {sideways, forward} studs from our root, clamped into the part of
                -- the box that EVERY combo covers, and >= 2 studs off the column under
                -- us, where the Mob Farm's own target stands.
                local SLOTS = { { 0, 2.4 }, { 1.9, 1.7 }, { -1.9, 1.7 }, { 0.9, 3.4 }, { -0.9, 3.4 }, { 2, -0.8 }, { -2, -0.8 }, { 0, -2 } }
                local DOWN = Vector3.new(0, -80, 0)
                local floorRp = RaycastParams.new()
                floorRp.FilterType = Enum.RaycastFilterType.Exclude
                floorRp.IgnoreWater = false -- a Terrain water surface counts as water, not floor
                local waterRp = RaycastParams.new()
                waterRp.FilterType = Enum.RaycastFilterType.Include
                pcall(function() waterRp.BruteForceAllSlow = true end) -- same query the fishing rod uses for SwimParts
                local F = { carried = {} } -- per-frame geometry shared by the helpers below
                local ourPreset, ownedAll, myFeet, hasWater, nearPlayer = nil, 0, 3, false, nil
                local lastScan, lastLbl, lastText, lastErr = 0, 0, '', nil
                local function scan(root, hum)
                    table.clear(cands)
                    local rootPos = root.Position
                    -- Other players: never touch a mob they are fighting (the server's
                    -- NpcsFollowing ObjectValues, Following.Set), and pause while one is close.
                    table.clear(others)
                    local near, lim = nil, Options.SLMagPlayers.Value
                    local ex, water = {}, {}
                    if LP.Character then ex[1] = LP.Character end
                    for _, p in ipairs(Players:GetPlayers()) do
                        local ch = p ~= LP and p.Character
                        if ch then
                            ex[#ex + 1] = ch
                            local f = ch:FindFirstChild('NpcsFollowing')
                            if f then
                                for _, v in ipairs(f:GetChildren()) do
                                    if v:IsA('ObjectValue') and v.Value then others[v.Value] = true end
                                end
                            end
                            local pr = ch:FindFirstChild('HumanoidRootPart')
                            local d = pr and (pr.Position - rootPos).Magnitude
                            if d and lim > 0 and d <= lim and (not near or d < near) then near = d end
                        end
                    end
                    nearPlayer = near and math.floor(near + 0.5) or nil
                    local rad = Options.SLMagRadius.Value
                    local skipCiv = Toggles.SLFarmSkipCiv and Toggles.SLFarmSkipCiv.Value
                    local n = 0
                    for _, m in ipairs(S.mobs()) do
                        if m.model ~= LP.Character and Players:GetPlayerFromCharacter(m.model) == nil then
                            if owns(m.root) then
                                n = n + 1
                                if (m.root.Position - rootPos).Magnitude <= rad and not others[m.model]
                                    and not (m.boss and not Toggles.SLMagBosses.Value) and not (m.civ and skipCiv) then
                                    cands[#cands + 1] = m
                                end
                            else
                                origin[m.model] = nil -- not ours (any more): the next grab starts a fresh leash
                            end
                        end
                    end
                    ownedAll = n
                    ourPreset = S.swingPreset(LP, nil)
                    -- our lowest direct-child part vs our root (what a mob's box must stay under)
                    local _, f = measure(LP.Character, root)
                    myFeet = math.max(f or 3, hum.HipHeight + root.Size.Y / 2)
                    -- Water = the SwimParts TouchParts + their sibling Texture (Swimming.lua
                    -- getTexture). Floor rays pass through them; water rays hit only them.
                    for _, nm in ipairs({ 'Humanoids', 'Debree' }) do
                        local fo = workspace:FindFirstChild(nm); if fo then ex[#ex + 1] = fo end
                    end
                    for _, v in ipairs(CS:GetTagged('SwimParts')) do
                        water[#water + 1] = v; ex[#ex + 1] = v
                        local tex = v.Parent and v.Parent:FindFirstChild('Texture')
                        if tex then water[#water + 1] = tex; ex[#ex + 1] = tex end
                    end
                    floorRp.FilterDescendantsInstances = ex
                    waterRp.FilterDescendantsInstances = water
                    hasWater = #water > 0
                end
                -- Our box for every combo 1..7 (S.m1Box = Get_Players_For_Combat), in combo
                -- 1's box space (all share one orientation): the INTERSECTION is where a
                -- parked mob is hit whatever combo we are on; the UNION is what a held-out
                -- mob must stay clear of; bottom = highest box bottom vs our root (least reach).
                local function frameGeometry(root)
                    local ok1, cf1 = pcall(S.m1Box, root, ourPreset, 1, false)
                    if not ok1 then return false end
                    local rootY = root.Position.Y
                    local ix0, ix1, iz0, iz1 = -1e9, 1e9, -1e9, 1e9
                    local ux, uz0, uz1, bottom = 0, 1e9, -1e9, -1e9
                    for i = 1, 7 do
                        local ok, cf, size = pcall(S.m1Box, root, ourPreset, i, false)
                        if ok then
                            local c = cf1:PointToObjectSpace(cf.Position)
                            local hx, hz = size.X / 2, size.Z / 2
                            ix0, ix1 = math.max(ix0, c.X - hx), math.min(ix1, c.X + hx)
                            iz0, iz1 = math.max(iz0, c.Z - hz), math.min(iz1, c.Z + hz)
                            ux = math.max(ux, math.abs(c.X) + hx)
                            uz0, uz1 = math.min(uz0, c.Z - hz), math.max(uz1, c.Z + hz)
                            bottom = math.max(bottom, cf.Position.Y - size.Y / 2 - rootY)
                        end
                    end
                    F.boxCf, F.rootLocal = cf1, cf1:PointToObjectSpace(root.Position)
                    F.ix0, F.ix1, F.iz0, F.iz1 = ix0, ix1, iz0, iz1
                    F.ux, F.uz0, F.uz1, F.bottom = ux, uz0, uz1, bottom
                    -- Carried mobs: Utility.CreateOuwWeld is an ObjectValue(victim root) on the
                    -- CARRIER's root, tagged OuwWeld a frame later (task.defer) - Obi Charge,
                    -- Execution Scyther, Storm Piercer... by us or by anyone else.
                    local carried = F.carried
                    table.clear(carried)
                    for _, c in ipairs(root:GetChildren()) do
                        if c:IsA('ObjectValue') and c.Value then carried[c.Value] = true end
                    end
                    for _, c in ipairs(CS:GetTagged('OuwWeld')) do
                        if c:IsA('ObjectValue') and c.Value then carried[c.Value] = true end
                    end
                    return true
                end
                local function clampS(v, a, b) -- math.clamp that tolerates an empty range
                    if a > b then return (a + b) / 2 end
                    return math.clamp(v, a, b)
                end
                -- Height for a mob's root at (x, z): never into the floor; nil = water there
                -- (touching water fires the mob's TouchedWater: ownership reset + walk home).
                local function settle(x, z, y, feet)
                    local from = Vector3.new(x, math.max(F.rootPos.Y, y) + 2, z)
                    local fl = workspace:Raycast(from, DOWN, floorRp)
                    if fl and fl.Material == Enum.Material.Water then return nil end -- Terrain water
                    if hasWater then -- a SwimParts surface above the ground here (not under a bridge)
                        local w = workspace:Raycast(from, DOWN, waterRp)
                        if w and (not fl or w.Position.Y >= fl.Position.Y - 0.5) then return nil end
                    end
                    if fl then y = math.max(y, fl.Position.Y + feet) end
                    return y
                end
                local function freeSlot(model)
                    local i = slotOf[model]
                    if i then slotUsed[i] = nil; slotOf[model] = nil end
                end
                local function takeSlot(model, maxN)
                    local i = slotOf[model]
                    if i and i <= maxN then return i end
                    freeSlot(model)
                    for k = 1, math.min(maxN, #SLOTS) do
                        if not slotUsed[k] then slotUsed[k] = model; slotOf[model] = k; return k end
                    end
                    return nil
                end
                -- The game is moving it: carried, in the vortex, welded, knocked back or
                -- ragdolled. Hands off until that ends.
                local function handsOff(model, mr, hum)
                    if F.carried[mr] or mr:FindFirstChild('ALP') then return true end
                    local ar = mr.AssemblyRootPart
                    if ar and ar ~= mr and not ar:IsDescendantOf(model) then return true end
                    for _, c in ipairs(mr:GetChildren()) do
                        if c:IsA('BodyMover') or c:IsA('LinearVelocity') or c:IsA('AlignPosition') or c:IsA('VectorForce') then return true end
                    end
                    return ragdolled(model, hum)
                end
                -- Hitting it would backfire (Checker.check_victim, M1 from a player):
                -- NpcCounter 1/2, a Counter / SHC(S) counter of type 1/2 (StatsFetch.
                -- GetCounter; Record = M1s pass), or a Perfect block without PierceBlock.
                local function risky(model)
                    local nc = model:GetAttribute('NpcCounter')
                    if nc == 1 or nc == 2 then return true end
                    local ok, ty, _, obj = false, nil, nil, nil
                    if SF and SF.GetCounter then ok, ty, _, obj = pcall(SF.GetCounter, model, model) end
                    if not ok then -- no StatsFetch: its Counter StringValue branch by hand
                        local cv = model:FindFirstChild('Counter')
                        ty, obj = nil, nil
                        if cv and cv:IsA('StringValue') and cv.Value ~= '' then ty, obj = cv:GetAttribute('Type'), cv end
                    end
                    if (ty == 1 or ty == 2) and not (typeof(obj) == 'Instance' and obj:GetAttribute('Record') == true) then return true end
                    local b = model:FindFirstChild('Blocking')
                    return b ~= nil and b:FindFirstChild('Perfect') ~= nil and model:FindFirstChild('PierceBlock') == nil
                end
                -- Glide toward `want` (leash from the first pull; the in-between spot is
                -- floor-clamped and never on water). Returns 'ok' | 'leash' | 'water'.
                local function moveTo(model, mr, want, feet, away)
                    local o = origin[model]
                    if not o then o = mr.Position; origin[model] = o end
                    if (want - o).Magnitude > LEASH then return 'leash' end
                    if F.dry then return 'ok' end
                    if S.farmHookMob then pcall(S.farmHookMob, model) end -- the farm's skill dodge watches it too
                    local mpos = mr.Position
                    local delta = want - mpos
                    local stepMax = Options.SLMagSpeed.Value * F.dt
                    local pos = want
                    if delta.Magnitude > stepMax then
                        pos = mpos + delta.Unit * stepMax
                        local y = settle(pos.X, pos.Z, pos.Y, feet)
                        if not y then return 'water' end
                        pos = Vector3.new(pos.X, y, pos.Z)
                    end
                    local flat = Vector3.new(pos.X - F.rootPos.X, 0, pos.Z - F.rootPos.Z)
                    if flat.Magnitude < 0.2 then flat = F.boxCf.LookVector end
                    flat = flat.Unit
                    mr.CFrame = CFrame.lookAt(pos, away and (pos + flat) or (pos - flat)) -- faces us (held out: away)
                    mr.AssemblyLinearVelocity = Vector3.zero
                    mr.AssemblyAngularVelocity = Vector3.zero
                    return 'ok'
                end
                -- One owned, in-range mob that is not the farm's target.
                -- Returns 'slot' | 'hold' | 'wait' | 'unsafe' | nil (all slots taken).
                local function handle(model, mr, hum, maxN)
                    if handsOff(model, mr, hum) then return 'wait' end
                    local sh = shapeOf(model, mr)
                    if not sh then return 'wait' end
                    local lo = sh.reach + myFeet + 0.15 -- depth where ITS box top clears our feet
                    local hi = sh.top - 0.3 - F.bottom  -- depth where OUR box bottom still reaches its top
                    if risky(model) then
                        -- Hold it just outside every combo's box, at the safe depth, facing
                        -- away, until the counter / perfect block clears.
                        freeSlot(model)
                        local ml = F.boxCf:PointToObjectSpace(mr.Position)
                        local near = holding[model] or (math.abs(ml.X) < F.ux + sh.rad + 1
                            and ml.Z > F.uz0 - sh.rad - 1 and ml.Z < F.uz1 + sh.rad + 1)
                        if not near then return 'wait' end -- already well outside our box
                        local side = (ml.X >= 0) and 1 or -1
                        local p = F.boxCf * Vector3.new(side * (F.ux + sh.rad + 1.5), 0, clampS(ml.Z, F.uz0, F.uz1))
                        local y = settle(p.X, p.Z, F.rootPos.Y - (lo + 0.3), sh.feet)
                        if not y then return 'unsafe' end
                        local r = moveTo(model, mr, Vector3.new(p.X, y, p.Z), sh.feet, true)
                        if r == 'water' then return 'unsafe' elseif r ~= 'ok' then return 'wait' end
                        holding[model] = true
                        seen[model] = 'hold'
                        return 'hold'
                    end
                    holding[model] = nil
                    if lo > hi then return 'unsafe' end -- no depth where we reach it and it can't reach us
                    local k = takeSlot(model, maxN)
                    if not k then return nil end
                    local sl = SLOTS[k]
                    local p = F.boxCf * Vector3.new(clampS(sl[1], F.ix0 + 0.5, F.ix1 - 0.5), 0,
                        clampS(F.rootLocal.Z - sl[2], F.iz0 + 0.5, F.iz1 - 0.5))
                    local y = settle(p.X, p.Z, F.rootPos.Y - math.min(lo + 0.3, hi), sh.feet)
                    -- the floor lifted it back into reach (standing on the ground, a taller
                    -- mob than the target, a crate under the slot...): leave it alone
                    if not y or F.rootPos.Y - y < sh.reach + myFeet + 0.05 then freeSlot(model); return 'unsafe' end
                    local r = moveTo(model, mr, Vector3.new(p.X, y, p.Z), sh.feet, false)
                    if r ~= 'ok' then freeSlot(model); return (r == 'water') and 'unsafe' or 'wait' end
                    seen[model] = 'slot'
                    return 'slot'
                end
                local function step(dt)
                    if S.dead then return end
                    local root, hum = S.root(), S.hum()
                    if not (root and hum and hum.Health > 0) then return end
                    local now = os.clock()
                    if now - lastScan > 0.25 then lastScan = now; scan(root, hum) end
                    -- Mob Farm / Auto Quest travelling, dodging or paused: leave the mobs be
                    -- (dragging a mob into our dodge spot drags its skill hitbox with it).
                    local farmOn = (Toggles.SLMobFarm and Toggles.SLMobFarm.Value) or (Toggles.SLAutoQuest and Toggles.SLAutoQuest.Value)
                    local why
                    if Toggles.SLMagFarmOnly.Value and not farmOn then why = 'farm off'
                    elseif farmOn and (S.farmPaused or not S.farmLocked) then why = 'farm not locked on'
                    elseif nearPlayer then why = ('player %d studs away'):format(nearPlayer) end
                    F.dry, F.dt, F.rootPos = Toggles.SLMagProbe.Value, dt, root.Position
                    local rootPos = F.rootPos
                    table.clear(seen)
                    local parked, held, waiting, unsafe = 0, 0, 0, 0
                    local rad, maxN = Options.SLMagRadius.Value + 4, Options.SLMagMax.Value
                    -- the farm's live target (Heartbeat runs after its RenderStepped): the farm
                    -- sits on it, so moving it too = the two chase each other. No getter =
                    -- the mob right under us while locked.
                    local tgt = S.farmGetTarget and S.farmGetTarget()
                    local geo = false
                    for _, m in ipairs(cands) do
                        local model, mr = m.model, m.root
                        if model.Parent and mr.Parent and m.hum.Health > 0 and (mr.Position - rootPos).Magnitude <= rad then
                            if not owns(mr) then
                                origin[model] = nil -- ownership lost: never touched again until re-grabbed
                            elseif why then
                                if slotOf[model] then seen[model] = 'slot' end
                                if holding[model] then seen[model] = 'hold' end
                            else
                                local mpos = mr.Position
                                local flatD = Vector3.new(mpos.X - rootPos.X, 0, mpos.Z - rootPos.Z).Magnitude
                                local isTarget = (tgt ~= nil and model == tgt)
                                    or (S.farmGetTarget == nil and S.farmLocked and flatD < 1.2 and mpos.Y < rootPos.Y)
                                if not isTarget then
                                    if not geo then -- geometry once per frame, only when something is ours
                                        geo = frameGeometry(root)
                                        if not geo then break end
                                    end
                                    local r = handle(model, mr, m.hum, maxN)
                                    if r == 'slot' then parked = parked + 1
                                    elseif r == 'hold' then held = held + 1
                                    elseif r == 'wait' then waiting = waiting + 1
                                    elseif r == 'unsafe' then unsafe = unsafe + 1 end
                                end
                            end
                        end
                    end
                    for model in pairs(slotOf) do
                        if seen[model] ~= 'slot' then freeSlot(model) end -- lost / busy / risky / died / out of range
                    end
                    for model in pairs(holding) do
                        if seen[model] ~= 'hold' then holding[model] = nil end
                    end
                    if now - lastLbl > 0.3 then
                        lastLbl = now
                        local t = ('owned mobs: %d'):format(ownedAll)
                        if parked > 0 then t = t .. (F.dry and '  |  would park: %d' or '  |  in box: %d'):format(parked) end
                        if held > 0 then t = t .. (F.dry and '  |  would hold out: %d' or '  |  held out: %d'):format(held) end
                        if waiting > 0 then t = t .. ('  |  waiting: %d'):format(waiting) end
                        if unsafe > 0 then t = t .. ('  |  no safe spot: %d'):format(unsafe) end
                        if why and ownedAll > 0 then t = t .. ('  (paused: %s)'):format(why) end
                        if F.dry then t = t .. '  [probe: nothing moved]' end
                        if t ~= lastText then lastText = t; S.setText(status, t) end
                    end
                end
                local conn
                local function stop()
                    if conn then conn:Disconnect(); conn = nil end
                    table.clear(cands); table.clear(seen); table.clear(slotOf); table.clear(slotUsed)
                    table.clear(holding); table.clear(others); table.clear(origin); table.clear(F.carried)
                    ownedAll, nearPlayer, lastText, lastErr = 0, nil, '', nil
                    S.setText(status, 'owned mobs: -')
                end
                Toggles.SLMagnet:OnChanged(function()
                    if not Toggles.SLMagnet.Value or S.dead then stop(); return end
                    if not isOwner then Library:Notify('Mob magnet: this executor has no isnetworkowner - nothing to do', 4); return end
                    if conn then return end
                    if SF == nil then SF = S.req('CAM.Global.Subsets.Gameplay.StatsFetch') or false end
                    lastScan = 0
                    conn = RunService.Heartbeat:Connect(function(dt)
                        local ok, err = pcall(step, dt)
                        if not ok and err ~= lastErr then
                            lastErr, lastText = err, ''
                            S.setText(status, 'magnet error: ' .. tostring(err))
                        end
                    end)
                end)
                htrack({ Disconnect = stop })
            end)()

            -- ================================================================
            -- MOVEMENT: speed, infinite breath, infinite climb
            -- ================================================================
            ;(function()
                local box = Tabs.Travel:AddLeftGroupbox('Movement')
                box:AddLabel('Breath + climb stamina are local tables in the\nSwimming / Climbing character scripts (found via\ngetgc). Drown damage is CLIENT-reported ("Swim",\n"DrownDamage") and is dropped. Speed: test first -\nthe server may validate movement.', true)
                box:AddToggle('SLSpeed', { Text = 'WalkSpeed override', Default = false })
                    :AddKeyPicker('SLSpeedKey', { Default = 'None', SyncToggleState = true, Mode = 'Toggle', Text = 'WalkSpeed' })
                box:AddSlider('SLSpeedValue', { Text = 'WalkSpeed', Default = 32, Min = 16, Max = 250, Rounding = 0 })
                box:AddToggle('SLFly', { Text = 'Fly', Default = false,
                    Tooltip = 'WASD = move (camera direction), Space = up, Ctrl = down. Pauses while Mob / Quest farm is moving you.' })
                    :AddKeyPicker('SLFlyKey', { Default = 'None', SyncToggleState = true, Mode = 'Toggle', Text = 'Fly' })
                box:AddSlider('SLFlySpeed', { Text = 'Fly speed', Default = 60, Min = 10, Max = 300, Rounding = 0, Suffix = ' studs/s' })
                box:AddToggle('SLNoclip', { Text = 'Noclip', Default = false })
                    :AddKeyPicker('SLNoclipKey', { Default = 'None', SyncToggleState = true, Mode = 'Toggle', Text = 'Noclip' })
                Toggles.SLNoclip:OnChanged(function() S.noclip('user', Toggles.SLNoclip.Value) end)
                ;(function() -- fly: bounded CFrame steps + zero velocity (same style as the glide)
                    local UIS = game:GetService('UserInputService')
                    local K = Enum.KeyCode
                    local flying = false
                    htrack(RunService.RenderStepped:Connect(function(dt)
                        local want = Toggles.SLFly.Value and not S.farmHasTarget and not S.farmPaused
                        local root, hum = S.root(), S.hum()
                        if not (want and root and hum) then
                            if flying then flying = false; S.noclip('fly', false); if hum then hum.PlatformStand = false end end
                            return
                        end
                        flying = true
                        hum.PlatformStand = true -- no falling / walking anims fighting us
                        local cam = workspace.CurrentCamera
                        local dir = Vector3.zero
                        if not UIS:GetFocusedTextBox() then
                            local look, right = cam.CFrame.LookVector, cam.CFrame.RightVector
                            if UIS:IsKeyDown(K.W) then dir = dir + look end
                            if UIS:IsKeyDown(K.S) then dir = dir - look end
                            if UIS:IsKeyDown(K.D) then dir = dir + right end
                            if UIS:IsKeyDown(K.A) then dir = dir - right end
                            if UIS:IsKeyDown(K.Space) then dir = dir + Vector3.yAxis end
                            if UIS:IsKeyDown(K.LeftControl) then dir = dir - Vector3.yAxis end
                        end
                        local pos = root.Position
                        if dir.Magnitude > 0 then pos = pos + dir.Unit * Options.SLFlySpeed.Value * dt end
                        local flat = cam.CFrame.LookVector * Vector3.new(1, 0, 1)
                        root.CFrame = flat.Magnitude > 0.1 and CFrame.lookAt(pos, pos + flat.Unit) or (root.CFrame - root.Position + pos)
                        root.AssemblyLinearVelocity = Vector3.zero
                    end))
                    htrack({ Disconnect = function()
                        local hum = S.hum(); if flying and hum then hum.PlatformStand = false end
                    end })
                end)()
                box:AddToggle('SLInfBreath', { Text = 'Infinite breath / no drown', Default = false })
                box:AddToggle('SLInfClimb', { Text = 'Infinite climb stamina', Default = false })
                local gcLabel = box:AddLabel('')
                table.insert(S.dropRules, function(a1, a2)
                    return a1 == 'Swim' and a2 == 'DrownDamage' and Toggles.SLInfBreath.Value
                end)
                local climbT, breathT, lastScan = {}, {}, -1e9
                local function scan()
                    lastScan = os.clock()
                    if not getgc then gcLabel:SetText('Executor lacks getgc'); return end
                    local c, b = {}, {}
                    for _, v in ipairs(getgc(true)) do
                        if type(v) == 'table' then
                            if rawget(v, 'MaxClimbTime') ~= nil and rawget(v, 'CurrentStamina') ~= nil then c[#c + 1] = v
                            elseif rawget(v, 'Breath') ~= nil and rawget(v, 'Drowning') ~= nil then b[#b + 1] = v end
                        end
                    end
                    climbT, breathT = c, b
                    gcLabel:SetText(('Found %d climb / %d breath table(s)'):format(#c, #b))
                end
                htrack(LP.CharacterAdded:Connect(function()
                    climbT, breathT = {}, {}
                    task.delay(3, function()
                        if Toggles.SLInfBreath.Value or Toggles.SLInfClimb.Value then scan() end
                    end)
                end))
                local function onToggle()
                    if Toggles.SLInfBreath.Value or Toggles.SLInfClimb.Value then task.spawn(scan) end
                end
                Toggles.SLInfBreath:OnChanged(onToggle)
                Toggles.SLInfClimb:OnChanged(onToggle)
                htrack(RunService.Heartbeat:Connect(function()
                    if Toggles.SLSpeed.Value then
                        local hum = S.hum()
                        if hum and hum.WalkSpeed ~= Options.SLSpeedValue.Value then hum.WalkSpeed = Options.SLSpeedValue.Value end
                    end
                    local wantB, wantC = Toggles.SLInfBreath.Value, Toggles.SLInfClimb.Value
                    if not (wantB or wantC) then return end
                    if ((wantB and #breathT == 0) or (wantC and #climbT == 0)) and os.clock() - lastScan > 6 then task.spawn(scan) end
                    if wantB then
                        for _, t in ipairs(breathT) do pcall(function() t.Breath = 1; t.Drowning = false end) end
                    end
                    if wantC then
                        for _, t in ipairs(climbT) do pcall(function() t.CurrentStamina = t.MaxClimbTime end) end
                    end
                end))
            end)()

            -- ================================================================
            -- TRAVEL: teleport lists, shrines, server tools
            -- ================================================================
            ;(function()
                local V = Vector3.new
                local NPCS = {
                    ['Betty'] = V(714, 1121, -808), ['Chaka'] = V(471, 1146, -1260), ['Kuro (night shop)'] = V(667.3, 1121.2, -1100.8),
                    ['Tom'] = V(507.2, 1121.4, -970.2), ['Wagwan'] = V(723.8, 1019.2, -802), ['Liv'] = V(657.4, 1018.7, 139.7),
                    ['Ren'] = V(-1795, 311.8, -85), ['Shiori'] = V(-1814.3, 311.8, -101.1), ['Demon Slayer Goro'] = V(-872, 234.8, 318.5),
                    ['Ubu Sisters'] = V(-2625.6, 284, -203), ['Demon Mokuro'] = V(-1948.4, 28.4, 374.3),
                    ['Baitmonger Nori'] = V(1643.2, 669.9, -190.1), ['Blacksmith Togane'] = V(1732.1, 694, -764.6),
                    ['Refiner Hagane'] = V(1865.3, 694, -434.3), ['Stonemason Tobei'] = V(1876, 659, -206), ['Yagane'] = V(1814, 659, -516),
                    ['Demon Delroy'] = V(139.6, 1254.2, -1911.3), ['Demon Slayer Mitsu'] = V(-824.3, 1381.5, -2537.8),
                    ['Old Trapper Retsu'] = V(440, 1177, -1504), ['Wounded Slayer Tomoi'] = V(485.3, 1222.6, -1813),
                    ['Iceveil Guard Shiro'] = V(-106.8, 1349, -2498.6), ['Shrine Messenger Akio'] = V(-207.1, 1349.6, -2423),
                    ['Winter Store Rep Lynx'] = V(-91.7, 1353.4, -2705.6), ['Duelist Hibiki'] = V(-1233.8, 1427.4, -4592.8),
                    ['Harvester of Souls Zurinyz'] = V(-1212.6, 1387.5, -2371.6), ['Lamplighter Isamu'] = V(1082.2, 1425.7, -749),
                    ['Soryu Expert Kazuma'] = V(-769.5, 909.4, 303.3), ['Tai Chi Expert Renjiro'] = V(1883.1, 686.6, -761),
                    ['Tailor Omi'] = V(1827.2, 1616.2, 119.7), ['Weaver Hatsu'] = V(2281.2, 812.7, 14.7),
                    ['Trainer: Water Urokodaki'] = V(667.2, 1022.7, -228.2), ['Trainer: Flame Rengu'] = V(-967.6, 1028.7, 1188.2),
                    ['Trainer: Insect Shinora'] = V(-1798.9, 347.9, -189.3), ['Trainer: Serpent Obari'] = V(37, 1311.2, -1179.5),
                    ['Trainer: Sound Tengai'] = V(464.9, 1491.1, -3272.8), ['Trainer: Stone Gyorei'] = V(2578.6, 1095.8, -828.4),
                    ['Trainer: Thunder Zentaro'] = V(1970.2, 1660, -609.8), ['Trainer: Wind Saneri'] = V(-275.6, 1187.5, -3436.7),
                    ['Angler Runo'] = V(-561.1, 796.2, 683.7), ['Elara (rotating shop)'] = V(427.8, 941, 507.4),
                    ['Fisherman Jeso'] = V(-192, 806.9, 602.7), ['Ginzo'] = V(273.8, 941.5, 528.2),
                    ['Legendary Fisherman Isao (night)'] = V(-214.6, 797, 61.1), ['Alchemist Meku'] = V(-138.1, 801.2, 518.7),
                    ['Rin'] = V(432.2, 1018, 73.1), ['Dock Master Sofen'] = V(-160.8, 796.2, 703.3), ['Jugg'] = V(487.7, 874.1, 1007.8),
                    ['Shady Individual Rooyi'] = V(-772.9, 965.1, -8.6), ['Kazu'] = V(-626, 1242.5, -1138), ['Kona'] = V(-791.6, 1260.1, -1130.9),
                    ['Krue'] = V(-425.5, 1243.5, -952.5), ['Lucy'] = V(-615.5, 1258.5, -1177.5), ['MoldySugar'] = V(-701.8, 1243.3, -982.7),
                    ['Noote'] = V(-515.5, 1243.2, -1251.2), ['Raze (katanas)'] = V(-594, 1242.5, -1095), ['Rika (potions)'] = V(-496.5, 1248.9, -1177.2),
                    ['Wagasa Maker Genzo'] = V(-1058.8, 1226, -955.7),
                }
                local PLACES = {
                    ['Crystal: Windy Peak'] = V(-447.9, 1241.4, -919.1), ['Crystal: Bamboo Grove'] = V(367.7, 1129.5, -941.1),
                    ['Crystal: Bamboo Sanctuary'] = V(627.1, 1020, -194.5), ['Crystal: Butterfly Estate'] = V(-1772.6, 314.6, -120.3),
                    ['Crystal: Final Selection'] = V(-2547.6, 278, 31.7), ['Crystal: Hidden Mist Village'] = V(1640, 606.3, -125),
                    ['Crystal: Iceveil Settlement'] = V(-208.8, 1352.7, -2596.5), ['Crystal: Mistfall Harbor'] = V(136.5, 873.9, 733.4),
                    ['Shrine: Bamboo Grove'] = V(-409.4, 1250.2, -1312), ['Shrine: Butterfly Estate'] = V(-1728.8, 315.2, 126.6),
                    ['Shrine: Mistfall Harbor'] = V(17, 967.7, 372.3), ['Shrine: Hidden Mist Village'] = V(1266.2, 980.9, -482.3),
                    ['Shrine: Frost Veil'] = V(142.1, 1385.1, -2783.2),
                    ['Training: Pushups'] = V(-1891.6, 312.3, 78.8), ['Training: Meditation'] = V(-1635.9, 312.8, -202.9),
                    ['Training: Squat Rack'] = V(-1861.6, 316, -77.2), ['Training: Cup Game'] = V(-1899, 315.3, -6.7),
                    ['Training: Target Shooting'] = V(-1475.5, 314.5, -97.3), ['Training: Boulder Split'] = V(-1046.8, 1130.5, -628.8),
                    ['Training: Boulder Push'] = V(-311.6, 1071.6, -579.6), ['Training: Parkour Dungeon'] = V(116.3, 1066.1, -1290.9),
                    ['Ouwigahara portal'] = V(-1607.1, 1015.5, 1142.4),
                    ['Statue: Fighting'] = V(2082.5, 1543.8, -216), ['Statue: Power'] = V(-697.4, 1386.5, -1914.3),
                    ['Statue: Weapons'] = V(-1381.7, 1010.3, 1109.4),
                    ['Camp: Bandits'] = V(-296.7, 1224.2, -1022.2), ['Camp: Bear Cubs'] = V(540.5, 1121, -1023.5),
                    ['Camp: Hoyuzo Subordinates'] = V(533, 1001, -1357), ['Camp: Kaiden Subordinates'] = V(585.7, 1146.5, -1314.9),
                    ['Camp: Greater Demons'] = V(-499, 284.8, 528.8), ['Camp: Lesser Demons'] = V(-675.7, 230.5, 397.1),
                    ['Camp: Mizunoe Slayers'] = V(-1834.1, 31, 487.6), ['Camp: Fire Profound'] = V(-915.7, 1374.2, -2430.4),
                    ['Camp: High Demons'] = V(388, 1253.9, -1927.2), ['Camp: Ice Profound'] = V(-919, 1381.7, -2447.5),
                    ['Camp: Kanoe Slayers'] = V(283.9, 1302, -2041.2), ['Camp: Beast Born'] = V(170.7, 888.7, 603.5),
                    ['Camp: Blood Hounded'] = V(789.3, 830, 927.5), ['Camp: Mizunoto'] = V(-833.9, 964, -75.1),
                }
                -- Fallback boss centres (live BossInfo.Center is preferred when loaded).
                local BOSSES = {
                    Zuko = V(-296.7, 1224.2, -1022.2), MotherBear = V(540.5, 1121, -1023.5), Kaiden = V(585.7, 1146.6, -1314.9),
                    Hoyuzo = V(746.9, 1001, -1413), Fujiko = V(-2459.5, 37.9, 1119), Akazo = V(-1132, 1380.9, -1746.6),
                    Datai = V(-165.5, 1043, -1137.5), Domae = V(-296.5, 1350.5, -3451.3), Enru = V(821.8, 800, 543.9),
                    Giyen = V(388.9, 1018, -85.1), Gyorei = V(2574.6, 1089, -742.4), Gyutai = V(-266.1, 1043.2, -1139.7),
                    Nezura = V(-1459.5, 276, 935.5), Obari = V(770.5, 1121, -1047), Reaper = V(98.5, 1043, -573.9),
                    Rengu = V(-712.9, 965, 883.8), Saneri = V(-379.1, 1093.5, -422.4), Shinora = V(-452.6, 964.5, 2.1),
                    Sumari = V(396.4, 1018, -620.4), Tengai = V(-133.5, 1349, -2631.3), Yahari = V(825.7, 1019.2, -641.3),
                    Zentaro = V(1332.1, 821.5, -1017.6), FlameTrainee = V(-1128.9, 1029, 994.4), InsectTrainee = V(-1395.6, 261.5, 69.2),
                    ReaperTrainee = V(-1219.3, 1373.6, -3034.4), SerpentTrainee = V(-271.4, 1292, -1535.7), SoryuTrainee = V(-427, 288.8, 543.3),
                    SoundTrainee = V(192.5, 1349, -2581.3), StoneTrainee = V(2685.2, 1073.6, -568.8), TaiChiTrainee = V(2360.5, 602, -642.3),
                    ThunderTrainee = V(2425.5, 1073.6, -556.8), WaterTrainee = V(815.3, 1018.9, 101.6), WindTrainee = V(-941.6, 1381, -2635.6),
                }
                S.BOSSES = BOSSES
                local function sortedKeys(t) local k = {}; for n in pairs(t) do k[#k + 1] = n end; table.sort(k); return k end

                local box = Tabs.Travel:AddRightGroupbox('Teleport')
                box:AddLabel('Bounded-speed glide (the game itself moves players\nclient-side). The server MAY validate movement -\ntry a short hop first. Shrine travel below is the\nguaranteed-safe way to cross the map.', true)
                box:AddSlider('SLTPSpeed', { Text = 'Glide speed', Default = 120, Min = 30, Max = 400, Rounding = 0, Suffix = ' studs/s' })
                box:AddDropdown('SLTPNpc', { Values = sortedKeys(NPCS), Default = nil, Multi = false, AllowNull = true, Text = 'NPC / trainer / shop' })
                box:AddButton({ Text = 'Go to NPC', Func = function()
                    local n = Options.SLTPNpc.Value; local p = n and NPCS[n]
                    if not p then Library:Notify('Pick an NPC', 2); return end
                    S.glideTo(p + Vector3.new(0, 3, 0), nil, n)
                end })
                box:AddDropdown('SLTPPlace', { Values = sortedKeys(PLACES), Default = nil, Multi = false, AllowNull = true, Text = 'Place / camp / training' })
                box:AddButton({ Text = 'Go to place', Func = function()
                    local n = Options.SLTPPlace.Value; local p = n and PLACES[n]
                    if not p then Library:Notify('Pick a place', 2); return end
                    S.glideTo(p + Vector3.new(0, 4, 0), nil, n)
                end })
                box:AddDropdown('SLTPBoss', { Values = sortedKeys(BOSSES), Default = nil, Multi = false, AllowNull = true, Text = 'Boss arena' })
                box:AddButton({ Text = 'Go to boss', Func = function()
                    local n = Options.SLTPBoss.Value
                    if not n then Library:Notify('Pick a boss', 2); return end
                    local p = BOSSES[n]
                    for _, cfg in ipairs(CS:GetTagged('BossTag')) do
                        if cfg.Parent and cfg.Parent.Name == n and typeof(cfg:GetAttribute('Center')) == 'Vector3' then p = cfg:GetAttribute('Center') end
                    end
                    if not p then Library:Notify('Unknown boss position', 2); return end
                    S.glideTo(p + Vector3.new(0, 5, 0), nil, n)
                end })
                box:AddButton({ Text = 'Stop glide', Func = function() S.stopGlide(); Library:Notify('Glide stopped', 1.5) end })
                box:AddLabel('Stop key'):AddKeyPicker('SLStopGlideKey', { Default = 'None', Mode = 'Toggle', Text = 'Stop glide' })
                Options.SLStopGlideKey:OnClick(function() S.stopGlide() end)

                -- ---- Shrines (the game's own fast travel) ---------------------
                local sb = Tabs.Travel:AddLeftGroupbox('Shrine Travel')
                sb:AddLabel('The map pin does exactly this from anywhere:\nTravelShrine(name). Must be unlocked (Wen) and\nout of combat; not inside Muzan\'s Lair.', true)
                local SHRINES = { 'Bamboo Grove Shrine', 'Butterfly Estate Shrine', 'Mistfall Harbor Shrine', 'Hidden Mist Village Shrine', 'Frost Veil Shrine' }
                local PRICE = { ['Bamboo Grove Shrine'] = 10000, ['Butterfly Estate Shrine'] = 15000, ['Mistfall Harbor Shrine'] = 25000,
                    ['Hidden Mist Village Shrine'] = 35000, ['Frost Veil Shrine'] = 45000 }
                sb:AddDropdown('SLShrine', { Values = SHRINES, Default = nil, Multi = false, AllowNull = true, Text = 'Shrine' })
                local function unlocked(name)
                    local _, root = S.data()
                    local list = tostring(S.val(root, 'Archives', 'Shrines') or '')
                    for s in list:gmatch('[^,]+') do if s:gsub('^%s+', ''):gsub('%s+$', '') == name then return true end end
                    return false
                end
                sb:AddButton({ Text = 'Travel', Func = function()
                    local n = Options.SLShrine.Value
                    if not n then Library:Notify('Pick a shrine', 2); return end
                    if not unlocked(n) then Library:Notify(('%s is locked - Unlock costs %d Wen'):format(n, PRICE[n] or 0), 4); return end
                    S.fire('TravelShrine', n)
                    Library:Notify('Travelling to ' .. n, 2)
                end }):AddButton({ Text = 'Unlock (Wen)', Func = function()
                    local n = Options.SLShrine.Value
                    if not n then Library:Notify('Pick a shrine', 2); return end
                    task.spawn(function()
                        local ok, res = S.invoke('UnlockShrine', n)
                        Library:Notify((ok and res == true) and ('Unlocked ' .. n) or ('Unlock refused: ' .. tostring(res)), 4)
                    end)
                end })

                -- ---- Server tools (the game's own server browser) -------------
                local srv = Tabs.Travel:AddRightGroupbox('Servers')
                srv:AddLabel('Uses the in-game server browser (ServerBrowser-\nController.Browse -> Join / TeleportServer).', true)
                local srvStatus = srv:AddLabel('Idle')
                srv:AddDropdown('SLRegion', { Values = { 'ALL', 'NA-WEST', 'NA-CENTRAL', 'NA-EAST', 'SA', 'EU', 'AF', 'AS', 'OCE' }, Default = 1, Multi = false, Text = 'Region' })
                srv:AddDropdown('SLServer', { Values = {}, Default = nil, Multi = false, AllowNull = true, Text = 'Server (lowest pop first)' })
                local byLabel = {}
                local function browse(thenJoin)
                    local SB = S.req('CAM.Client.Controllers.ServerBrowserController')
                    if not SB then Library:Notify('ServerBrowserController not loaded', 3); return end
                    srvStatus:SetText('Browsing...')
                    local done, conn = false, nil
                    conn = SB.Updated:Connect(function(state)
                        if done then return end
                        done = true
                        pcall(function() conn:Disconnect() end)
                        local list = {}
                        for _, s in ipairs((type(state) == 'table' and state.Servers) or {}) do
                            local cur = false
                            pcall(function() cur = SB.IsCurrentServer(s) end)
                            if not cur and (s.Players or 0) < (s.MaxPlayers or 99) then list[#list + 1] = s end
                        end
                        table.sort(list, function(a, b) return (a.Players or 0) < (b.Players or 0) end)
                        byLabel = {}
                        local labels = {}
                        for _, s in ipairs(list) do
                            local l = ('%s  %d/%d  %s'):format(tostring(s.Name), s.Players or 0, s.MaxPlayers or 0, tostring(s.Region or ''))
                            byLabel[l] = s; labels[#labels + 1] = l
                        end
                        Options.SLServer:SetValues(labels)
                        srvStatus:SetText(('%d joinable server(s)'):format(#labels))
                        if thenJoin and list[1] then
                            srvStatus:SetText('Joining ' .. tostring(list[1].Name))
                            task.spawn(function()
                                local ok, a, b = pcall(SB.Join, list[1])
                                if not ok or a == false then Library:Notify('Join failed: ' .. tostring(ok and b or a), 5) end
                            end)
                        end
                    end)
                    local ok, err = pcall(SB.Browse, nil, Options.SLRegion.Value or 'ALL')
                    if not ok then srvStatus:SetText('Browse failed: ' .. tostring(err)); done = true; pcall(function() conn:Disconnect() end) end
                    task.delay(10, function() if not done then done = true; pcall(function() conn:Disconnect() end); srvStatus:SetText('No reply (rate limited?)') end end)
                end
                srv:AddButton({ Text = 'Find servers', Func = function() browse(false) end })
                    :AddButton({ Text = 'Hop to lowest', Func = function() browse(true) end })
                srv:AddButton({ Text = 'Join selected', Func = function()
                    local s = byLabel[Options.SLServer.Value or '']
                    if not s then Library:Notify('Find servers first', 2); return end
                    local SB = S.req('CAM.Client.Controllers.ServerBrowserController')
                    task.spawn(function()
                        local ok, a, b = pcall(SB.Join, s)
                        if not ok or a == false then Library:Notify('Join failed: ' .. tostring(ok and b or a), 5) end
                    end)
                end })
                srv:AddInput('SLJobId', { Text = 'Join by JobId', Default = '', Finished = true, Placeholder = 'server JobId' })
                srv:AddButton({ Text = 'Join JobId', Func = function()
                    local id = tostring(Options.SLJobId.Value or ''):gsub('%s', '')
                    if id == '' then Library:Notify('Paste a JobId', 2); return end
                    local T = S.req('CAM.Client.Modules.Teleporter')
                    if not T then Library:Notify('Teleporter module not loaded', 3); return end
                    task.spawn(function()
                        local ok, a, b = pcall(T.Request, { placeId = game.PlaceId, jobId = id, allowFallback = false }, { Title = 'Joining Server', SubTitle = id })
                        if not ok or a == false then Library:Notify('Join failed: ' .. tostring(ok and b or a), 5) end
                    end)
                end }):AddButton({ Text = 'Copy my JobId', Func = function()
                    if setclipboard then pcall(setclipboard, game.JobId) end
                    Library:Notify('JobId: ' .. game.JobId, 4)
                end })
            end)()

            -- ================================================================
            -- VISUALS: ESP, boss tracker, Black Marketer predictor
            -- ================================================================
            ;(function()
                local box = Tabs.Visuals:AddLeftGroupbox('ESP')
                box:AddToggle('SLEspMobs', { Text = 'Mobs', Default = false })
                box:AddToggle('SLEspBosses', { Text = 'Bosses', Default = false })
                box:AddToggle('SLEspNpcs', { Text = 'NPCs', Default = false })
                box:AddToggle('SLEspChests', { Text = 'Chests', Default = false })
                box:AddToggle('SLEspLoot', { Text = 'Loot drops', Default = false })
                box:AddToggle('SLEspFlags', { Text = 'Show state flags', Default = true, Tooltip = '[AGGRO] targeting someone, [BLOCK] blocking, [PERFECT] parry window live, [STUN] stunned, [COUNTER] counter armed (don\'t hit).' })
                box:AddSlider('SLEspDist', { Text = 'Max distance', Default = 800, Min = 50, Max = 3000, Rounding = 0, Suffix = ' studs' })
                box:AddLabel('The world streams in ~625 studs around you, so far\nmobs aren\'t on your client (use the boss tracker).', true)
                if not Drawing then box:AddLabel('Executor lacks the Drawing API - ESP unavailable.', true); return end
                local COLORS = {
                    mob = Color3.fromRGB(255, 90, 90), boss = Color3.fromRGB(255, 60, 220), npc = Color3.fromRGB(90, 200, 255),
                    chest = Color3.fromRGB(255, 210, 80), loot = Color3.fromRGB(120, 255, 120),
                }
                local pool = {} -- [instance] = { name = Text, info = Text }
                local function mk()
                    local a, b = Drawing.new('Text'), Drawing.new('Text')
                    for _, t in ipairs({ a, b }) do t.Visible = false; t.Center = true; t.Outline = true end
                    a.Size, b.Size = 14, 12
                    return { name = a, info = b }
                end
                local function hide(o) o.name.Visible = false; o.info.Visible = false end
                local function free(o) pcall(function() o.name:Remove() end); pcall(function() o.info:Remove() end) end
                local ents, acc = {}, 1
                local function gather()
                    local out = {}
                    if Toggles.SLEspMobs.Value or Toggles.SLEspBosses.Value then
                        for _, m in ipairs(S.mobs()) do
                            if (m.boss and Toggles.SLEspBosses.Value) or (not m.boss and Toggles.SLEspMobs.Value) then
                                out[#out + 1] = { inst = m.model, kind = m.boss and 'boss' or 'mob', title = m.name, hum = m.hum, root = m.root }
                            end
                        end
                    end
                    if Toggles.SLEspNpcs.Value then
                        local regs = workspace:FindFirstChild('Debree') and workspace.Debree:FindFirstChild('Regions')
                        if regs then
                            for _, r in ipairs(regs:GetChildren()) do
                                local st = r:FindFirstChild('StationaryNpcs')
                                if st then for _, n in ipairs(st:GetChildren()) do out[#out + 1] = { inst = n, kind = 'npc', title = n.Name } end end
                            end
                        end
                    end
                    if Toggles.SLEspChests.Value then
                        for _, c in ipairs(CS:GetTagged('Chest')) do
                            if not c:GetAttribute('IsOpen') then out[#out + 1] = { inst = c, kind = 'chest', title = tostring(c:GetAttribute('ChestId') or 'Chest') } end
                        end
                    end
                    if Toggles.SLEspLoot.Value then
                        for _, d in ipairs(CS:GetTagged('LootDrop')) do
                            if d:GetAttribute('DropClaimedBy') == nil then out[#out + 1] = { inst = d, kind = 'loot', title = tostring(d:GetAttribute('DropItemId') or 'Loot') } end
                        end
                    end
                    return out
                end
                local function flags(m)
                    local t = {}
                    if m:GetAttribute('Aggroed') then t[#t + 1] = 'AGGRO' end
                    local b = m:FindFirstChild('Blocking')
                    if b then t[#t + 1] = b:FindFirstChild('Perfect') and 'PERFECT' or 'BLOCK' end
                    if m:FindFirstChild('Stun') or m:FindFirstChild('CombatStun') or m:FindFirstChild('Strict_Stun') then t[#t + 1] = 'STUN' end
                    if m:GetAttribute('NpcCounter') then t[#t + 1] = 'COUNTER' end
                    return (#t > 0) and (' [' .. table.concat(t, '][') .. ']') or ''
                end
                htrack(RunService.RenderStepped:Connect(function(dt)
                    acc = acc + dt
                    if acc >= 0.5 then acc = 0; ents = gather() end
                    local cam = workspace.CurrentCamera
                    local me = S.root()
                    local seen = {}
                    if cam then
                        local maxD = Options.SLEspDist.Value
                        for _, e in ipairs(ents) do
                            local inst = e.inst
                            local pos = inst.Parent and (e.root and e.root.Position or S.posOf(inst))
                            if pos then
                                local dist = me and (pos - me.Position).Magnitude or 0
                                local o = pool[inst]
                                if not o then o = mk(); pool[inst] = o end
                                seen[inst] = true
                                local sp, on = cam:WorldToViewportPoint(pos + Vector3.new(0, 3, 0))
                                if not on or dist > maxD then hide(o) else
                                    local col = COLORS[e.kind]
                                    o.name.Text, o.name.Color, o.name.Position, o.name.Visible = e.title, col, Vector2.new(sp.X, sp.Y - 16), true
                                    local info = ('%.0fm'):format(dist)
                                    if e.hum then
                                        info = ('%d/%d HP  '):format(math.floor(e.hum.Health + 0.5), math.floor(e.hum.MaxHealth + 0.5)) .. info
                                        if Toggles.SLEspFlags.Value then info = info .. flags(inst) end
                                    elseif e.kind == 'chest' then
                                        info = info .. '  ' .. tostring(inst:GetAttribute('ChestState') or '')
                                    end
                                    o.info.Text, o.info.Color, o.info.Position, o.info.Visible = info, Color3.new(1, 1, 1), Vector2.new(sp.X, sp.Y - 2), true
                                end
                            end
                        end
                    end
                    for inst, o in pairs(pool) do
                        if not seen[inst] then free(o); pool[inst] = nil end
                    end
                end))
                htrack({ Disconnect = function() for i, o in pairs(pool) do free(o); pool[i] = nil end end })
            end)()

            ;(function()
                -- ---- Boss tracker (BossInfo configs are not streamed: map-wide)
                local box = Tabs.Visuals:AddRightGroupbox('Boss Tracker')
                box:AddToggle('SLBossNotify', { Text = 'Notify when a boss is up', Default = false })
                box:AddDropdown('SLBossWatch', { Values = {}, Default = {}, Multi = true, AllowNull = true, Text = 'Only notify for',
                    Tooltip = 'Nothing ticked = all bosses. Filled automatically.' })
                local list = box:AddLabel('Loading...', true)
                local prevUp, known = {}, {}
                local function isNight()
                    local DN = S.req('CAM.Global.DayAndNightHandler')
                    if DN and type(DN.IsNight) == 'function' then
                        local ok, r = pcall(DN.IsNight); if ok then return r end
                    end
                    return nil
                end
                task.spawn(function()
                    while not S.dead do
                        local now = workspace:GetServerTimeNow()
                        local night = isNight()
                        local rows, names, newNames = {}, {}, false
                        for _, cfg in ipairs(CS:GetTagged('BossTag')) do
                            local folder = cfg.Parent
                            if folder then
                                local name = folder.Name
                                names[#names + 1] = name
                                if not known[name] then known[name] = true; newNames = true end
                                local model
                                for _, c in ipairs(folder:GetChildren()) do if c:IsA('Model') then model = c; break end end
                                local hum = model and model:FindFirstChildOfClass('Humanoid')
                                local desp = folder:GetAttribute('DespawnedAt')
                                local left = desp and ((cfg:GetAttribute('SpawnTime') or 0) - (now - desp)) or 0
                                local nightOnly = cfg:GetAttribute('OnlyAtNight')
                                local txt, order, up
                                if hum and hum.Health > 0 then
                                    txt = ('ALIVE %d%%'):format(math.floor(hum.Health / math.max(hum.MaxHealth, 1) * 100)); order = 0; up = true
                                elseif left > 0 then
                                    txt = 'in ' .. S.fmt(left); order = 2 + left / 1e4; up = false
                                elseif nightOnly and night == false then
                                    txt = 'night only'; order = 3; up = false
                                else
                                    txt = 'UP (not loaded)'; order = 1; up = true
                                end
                                rows[#rows + 1] = { order = order, line = ('%s - %s'):format(name, txt) }
                                if up and prevUp[name] == false and Toggles.SLBossNotify.Value then
                                    local w = Options.SLBossWatch.Value
                                    if type(w) ~= 'table' or next(w) == nil or w[name] then Library:Notify(name .. ' is up!', 8) end
                                end
                                prevUp[name] = up
                            end
                        end
                        table.sort(rows, function(a, b) return a.order < b.order end)
                        local lines = {}
                        for _, r in ipairs(rows) do lines[#lines + 1] = r.line end
                        pcall(function() list:SetText(#lines > 0 and table.concat(lines, '\n') or 'No BossTag configs found (not in the main world?)') end)
                        if newNames then table.sort(names); pcall(function() Options.SLBossWatch:SetValues(names) end) end
                        task.wait(1)
                    end
                end)
            end)()

            ;(function()
                -- ---- Black Marketer predictor (seeded schedule, client-computable)
                local box = Tabs.Visuals:AddRightGroupbox('Black Marketer')
                local lbl = box:AddLabel('Loading...', true)
                local spot
                local function update()
                    local TV = S.req('CAM.Global.Subsets.Gameplay.TimedVendor')
                    local BM = S.req('Ouwland.Content.Misc.Npcs.Black Marketer')
                    if not (TV and BM and BM.TimedVendor and BM.Spawns) then lbl:SetText('Vendor modules not loaded here'); return end
                    local cfg = BM.TimedVendor
                    local ok, st = pcall(TV.GetState, cfg)
                    if not ok or type(st) ~= 'table' then lbl:SetText('GetState failed'); return end
                    local okI, idx = pcall(TV.GetSpotIndex, cfg, st.Cycle, #BM.Spawns)
                    local cf = okI and BM.Spawns[idx]
                    spot = cf and cf.Position or nil
                    local okS, stock = pcall(TV.GetStock, cfg, st.Cycle)
                    local names = {}
                    if okS and type(stock) == 'table' then
                        for _, it in ipairs(stock) do names[#names + 1] = type(it) == 'table' and tostring(it.Name) or tostring(it) end
                    end
                    lbl:SetText(('%s  (%s %s)\nSpot #%s: %s\nStock: %s'):format(
                        st.Active and 'ACTIVE' or 'Away', st.Active and 'leaves in' or 'arrives in', S.fmt(st.NextEdgeIn or 0),
                        tostring(idx), spot and ('%.0f, %.0f, %.0f'):format(spot.X, spot.Y, spot.Z) or '?',
                        #names > 0 and table.concat(names, ', ') or '?'))
                end
                box:AddButton({ Text = 'Go to Black Marketer', Func = function()
                    if not spot then Library:Notify('Location unknown', 2); return end
                    S.glideTo(spot + Vector3.new(0, 3, 0), nil, 'Black Marketer')
                end })
                box:AddLabel('Spot = TimedVendor.GetSpotIndex(cycle) - check it\nonce against the real vendor position.', true)
                task.spawn(function()
                    while not S.dead do pcall(update); task.wait(5) end
                end)
            end)()

            ;(function()
                -- ---- No Fog: Lighting fog + Atmosphere + Terrain clouds -------
                -- Re-asserted every frame (the day/night cycle re-tweens Lighting),
                -- originals saved per object and restored on toggle-off / unload.
                local Lighting = game:GetService('Lighting')
                local box = Tabs.Visuals:AddLeftGroupbox('World')
                box:AddToggle('SLNoFog', { Text = 'No fog', Default = false,
                    Tooltip = 'Pushes fog past the horizon, zeroes Atmosphere density/haze/glare and hides Terrain clouds. Local only.' })
                    :AddKeyPicker('SLNoFogKey', { Default = 'None', SyncToggleState = true, Mode = 'Toggle', Text = 'No fog' })
                local saved = { fog = nil, atmo = {}, clouds = {} }
                local function apply()
                    if not saved.fog then saved.fog = { Lighting.FogStart, Lighting.FogEnd } end
                    Lighting.FogStart, Lighting.FogEnd = 1e6, 1e6
                    for _, v in ipairs(Lighting:GetChildren()) do
                        if v:IsA('Atmosphere') then
                            if not saved.atmo[v] then saved.atmo[v] = { v.Density, v.Haze, v.Glare } end
                            v.Density, v.Haze, v.Glare = 0, 0, 0
                        end
                    end
                    local c = workspace.Terrain:FindFirstChildOfClass('Clouds')
                    if c then
                        if not saved.clouds[c] then saved.clouds[c] = c.Enabled end
                        c.Enabled = false
                    end
                end
                local function restore()
                    if saved.fog then Lighting.FogStart, Lighting.FogEnd = saved.fog[1], saved.fog[2]; saved.fog = nil end
                    for a, o in pairs(saved.atmo) do
                        if a.Parent then pcall(function() a.Density, a.Haze, a.Glare = o[1], o[2], o[3] end) end
                    end
                    for c, en in pairs(saved.clouds) do if c.Parent then pcall(function() c.Enabled = en end) end end
                    saved.atmo, saved.clouds = {}, {}
                end
                Toggles.SLNoFog:OnChanged(function() if not Toggles.SLNoFog.Value then restore() end end)
                htrack(RunService.RenderStepped:Connect(function()
                    if Toggles.SLNoFog.Value then pcall(apply) end
                end))
                htrack({ Disconnect = function() pcall(restore) end })
            end)()

            -- ================================================================
            -- MISC: stats panel, instant spins, staff detector
            -- ================================================================
            ;(function()
                local box = Tabs.Misc:AddLeftGroupbox('Stats')
                local lbl = box:AddLabel('Loading...', true)
                local function build()
                    local slot, root = S.data()
                    if not slot then return 'Player data not replicated yet' end
                    local L = {}
                    local goal, cur = S.val(slot, 'Exp', 'Goal'), S.val(slot, 'Exp', 'Current')
                    if goal then
                        L[#L + 1] = ('Level %d   XP %d / %d (%.0f%%)'):format(math.floor(goal / 60), cur or 0, goal, (cur or 0) / math.max(goal, 1) * 100)
                    end
                    L[#L + 1] = ('Wen %s   Skill points %s   Rep %s'):format(tostring(S.val(slot, 'Wen') or '?'), tostring(S.val(slot, 'SkillPoints') or '?'), tostring(S.val(slot, 'Reputation') or '?'))
                    L[#L + 1] = ('Race %s   Clan %s'):format(tostring(S.val(slot, 'Race') or '?'), tostring(S.val(slot, 'Clan') or '?'))
                    local rank = S.val(slot, 'SlayerRank') or S.val(slot, 'DemonRank')
                    if rank then L[#L + 1] = 'Rank ' .. tostring(rank) end
                    local powers = slot:FindFirstChild('Powers')
                    if powers then
                        local p = {}
                        for _, v in ipairs(powers:GetChildren()) do
                            if v:IsA('ValueBase') and tostring(v.Value) ~= '' then p[#p + 1] = v.Name .. ': ' .. tostring(v.Value) end
                        end
                        if #p > 0 then L[#L + 1] = table.concat(p, '   ') end
                    end
                    L[#L + 1] = ('Spins %s  (free clan %s / other %s, account %s)'):format(tostring(S.val(slot, 'Spinning', 'Spins') or 0),
                        tostring(S.val(slot, 'Spinning', 'FreeClanSpins') or 0), tostring(S.val(slot, 'Spinning', 'FreeOtherSpins') or 0),
                        tostring(S.val(root, 'AccountSpins') or 0))
                    local st = S.values() and S.values():FindFirstChild('Stamina')
                    if st then L[#L + 1] = ('Stamina %d / %d'):format(st.Value, st.MaxValue or 0) end
                    local mult = slot:FindFirstChild('Multipliers')
                    if mult then
                        local now = workspace:GetServerTimeNow()
                        for _, m in ipairs(mult:GetChildren()) do
                            local s, d = S.val(m, 'Started'), S.val(m, 'Duration')
                            if s and d and s + d > now then L[#L + 1] = ('Boost %s: %s left'):format(m.Name, S.fmt(s + d - now)) end
                        end
                    end
                    local holder = slot:FindFirstChild('Quests') and slot.Quests:FindFirstChild('Holder')
                    if holder then
                        for _, q in ipairs(holder:GetChildren()) do
                            local tasks = {}
                            local tf = q:FindFirstChild('Tasks')
                            if tf then
                                for _, t in ipairs(tf:GetChildren()) do
                                    local v, mx = S.val(t, 'Value') or (t:IsA('ValueBase') and t.Value), S.val(t, 'Max')
                                    tasks[#tasks + 1] = ('%s %s/%s'):format(t.Name, tostring(v or 0), tostring(mx or '?'))
                                end
                            end
                            L[#L + 1] = ('Quest: %s  %s'):format(q.Name, table.concat(tasks, ', '))
                        end
                    end
                    if LP:GetAttribute('SaveDisabled') or LP:GetAttribute('SaveDisabledSlot') then L[#L + 1] = '!! DATA SAVING IS DISABLED THIS SESSION !!' end
                    return table.concat(L, '\n')
                end
                task.spawn(function()
                    while not S.dead do
                        local ok, txt = pcall(build)
                        pcall(function() lbl:SetText(ok and txt or ('Stats error: ' .. tostring(txt))) end)
                        task.wait(2)
                    end
                end)

                -- ---- Spins -----------------------------------------------------
                local sp = Tabs.Misc:AddRightGroupbox('Spins')
                sp:AddLabel('Rolls are decided on the SERVER (RemoteFunction) -\nodds can\'t be changed. This just skips the wheel:\nsends the roll, shows the result, closes the spin.\nClan odds: Common 60 / Uncommon 23 / Rare 12 /\nLegendary 4 / Mythic 0.9 / Supreme 0.1 (%).\nEvil Art: 3 spins, 30% nothing, else ~7.8% each.', true)
                local last = sp:AddLabel('Last result: -')
                local armed = {}
                local function spin(kind)
                    if not armed[kind] or os.clock() - armed[kind] > 3 then
                        armed[kind] = os.clock()
                        Library:Notify('Click again within 3s to spend spins', 3)
                        return
                    end
                    armed[kind] = nil
                    task.spawn(function()
                        local fn = (kind == 'clan') and 'ClanSpin' or 'EvilArtSpin'
                        local ok, res = S.invoke(fn)
                        if not ok then Library:Notify('Spin failed: ' .. tostring(res), 5); return end
                        S.fire((kind == 'clan') and 'ClanSpinComplete' or 'EvilArtSpinComplete')
                        local txt = (type(res) == 'table') and (pcall(HttpService.JSONEncode, HttpService, res) and HttpService:JSONEncode(res) or 'table') or tostring(res)
                        last:SetText('Last result: ' .. txt)
                        Library:Notify(fn .. ' -> ' .. txt, 8)
                    end)
                end
                sp:AddButton({ Text = 'Evil Art spin (instant)', Func = function() spin('ea') end })
                sp:AddButton({ Text = 'Clan spin (instant, menu place)', Func = function() spin('clan') end })
                sp:AddLabel('Clan spins only work in the Main Menu place; the\nEvil Art spin may require being at its NPC.', true)

                -- ---- Staff detector -------------------------------------------
                local sf = Tabs.Misc:AddRightGroupbox('Staff Detector')
                sf:AddLabel('Staff = rank >= 5 in group 12851171 (the OCI admin\nclearance: Ban/Kick/Bring/Goto).', true)
                sf:AddToggle('SLStaff', { Text = 'Warn when staff is here', Default = true })
                local sLbl = sf:AddLabel('Staff in server: none')
                local staff = {}
                local function redraw()
                    local n = {}
                    for p, r in pairs(staff) do if p.Parent then n[#n + 1] = ('%s (rank %d)'):format(p.Name, r) end end
                    sLbl:SetText('Staff in server: ' .. (#n > 0 and table.concat(n, ', ') or 'none'))
                end
                local function check(p)
                    if p == LP then return end
                    task.spawn(function()
                        local ok, rank = pcall(p.GetRankInGroup, p, 12851171)
                        if ok and type(rank) == 'number' and rank >= 5 then
                            staff[p] = rank
                            redraw()
                            if Toggles.SLStaff.Value then
                                Library:Notify(('STAFF in server: %s (rank %d)'):format(p.Name, rank), 15)
                                pcall(function()
                                    local s = Instance.new('Sound')
                                    s.SoundId = 'rbxasset://sounds/electronicpingshort.wav'
                                    s.Volume = 1
                                    game:GetService('SoundService'):PlayLocalSound(s)
                                end)
                            end
                        end
                    end)
                end
                for _, p in ipairs(Players:GetPlayers()) do check(p) end
                htrack(Players.PlayerAdded:Connect(check))
                htrack(Players.PlayerRemoving:Connect(function(p) if staff[p] then staff[p] = nil; redraw() end end))
            end)()
        end)()
    else
        -- ===== UNIVERSAL HUB: any experience NOT registered above ========
        -- Game-agnostic basics that work on plain Roblox physics: Fly (with
        -- speed), Noclip, Player ESP and a bounded-speed tween onto any ESP'd
        -- player. No remotes, no game-specific paths.
        local Players     = game:GetService('Players')
        local LocalPlayer = Players.LocalPlayer
        local CS          = game:GetService('CollectionService')
        local function getChar() return LocalPlayer.Character end
        local function getHum()  local c = getChar(); return c and c:FindFirstChildOfClass('Humanoid') end
        local function getRoot() local c = getChar(); return c and c:FindFirstChild('HumanoidRootPart') end

        local Tab = Window:AddTab('Universal')
        local MoveBox = Tab:AddLeftGroupbox('Movement')
        MoveBox:AddLabel(('Universal module (experience not registered).\nPlaceId %d | GameId %d'):format(game.PlaceId, game.GameId), true)
        MoveBox:AddToggle('UFly', { Text = 'Fly', Default = false, Tooltip = 'WASD to move, Space / Ctrl for up / down (camera-relative).' })
            :AddKeyPicker('UFlyKey', { Default = 'None', SyncToggleState = true, Mode = 'Toggle', Text = 'Fly' })
        MoveBox:AddSlider('UFlySpeed', { Text = 'Fly speed', Default = 60, Min = 10, Max = 500, Rounding = 0, Suffix = ' studs/s' })
        MoveBox:AddToggle('UNoclip', { Text = 'Noclip', Default = false, Tooltip = 'Walk through parts (CanCollide off on your character each physics step).' })
            :AddKeyPicker('UNoclipKey', { Default = 'None', SyncToggleState = true, Mode = 'Toggle', Text = 'Noclip' })
        MoveBox:AddButton({ Text = 'Copy PlaceId', Func = function()
            if setclipboard then pcall(setclipboard, tostring(game.PlaceId)) end
            Library:Notify('Copied PlaceId: ' .. tostring(game.PlaceId), 4)
        end }):AddButton({ Text = 'Copy GameId', Func = function()
            if setclipboard then pcall(setclipboard, tostring(game.GameId)) end
            Library:Notify('Copied GameId: ' .. tostring(game.GameId), 4)
        end })

        local EspBox = Tab:AddRightGroupbox('Player ESP')
        EspBox:AddToggle('UEsp', { Text = 'Player ESP', Default = false })
            :AddKeyPicker('UEspKey', { Default = 'None', SyncToggleState = true, Mode = 'Toggle', Text = 'Player ESP' })
        EspBox:AddToggle('UEspBoxes',    { Text = 'Boxes',    Default = true })
        EspBox:AddToggle('UEspNames',    { Text = 'Names',    Default = true })
        EspBox:AddToggle('UEspDistance', { Text = 'Distance', Default = true })
        EspBox:AddToggle('UEspHealth',   { Text = 'Health',   Default = true })
        EspBox:AddToggle('UEspTracers',  { Text = 'Tracers',  Default = false })
        EspBox:AddSlider('UEspMaxDist', { Text = 'Max distance', Default = 2000, Min = 50, Max = 10000, Rounding = 0, Suffix = ' studs' })
        EspBox:AddLabel('Color'):AddColorPicker('UEspColor', { Default = Color3.fromRGB(255, 255, 0), Title = 'ESP color' })

        local TweenBox = Tab:AddRightGroupbox('Tween to player')
        TweenBox:AddLabel('Glides you to the chosen player at a bounded speed\n(continuous movement, not a snap - far less likely to\ntrip a teleport check). Re-targets each frame, so a\nmoving player is followed until you arrive.', true)
        local TweenStatus = TweenBox:AddLabel('Idle')
        TweenBox:AddDropdown('UTweenTarget', { SpecialType = 'Player', Values = {}, AllowNull = true, Text = 'Player' })
        TweenBox:AddSlider('UTweenSpeed', { Text = 'Tween speed', Default = 150, Min = 20, Max = 2000, Rounding = 0, Suffix = ' studs/s' })
        TweenBox:AddSlider('UTweenOffset', { Text = 'Stand-off', Default = 4, Min = 0, Max = 20, Rounding = 1, Suffix = ' studs',
            Tooltip = 'Stop this far behind the target instead of inside them.' })
        TweenBox:AddToggle('UTweenNoclip', { Text = 'Noclip while tweening', Default = true })
        local tweenTo, tweenStop
        TweenBox:AddButton({ Text = 'Tween to player', Func = function() if tweenTo then tweenTo() end end })
            :AddButton({ Text = 'Stop', Func = function() if tweenStop then tweenStop() end end })
        TweenBox:AddLabel('Tween key'):AddKeyPicker('UTweenKey', { Default = 'None', Mode = 'Toggle', Text = 'Tween to player' })
        TweenBox:AddLabel('Stop key'):AddKeyPicker('UTweenStopKey', { Default = 'None', Mode = 'Toggle', Text = 'Stop tween' })

        -- ---- Fly ------------------------------------------------------------
        local flyVel, flyGyro
        local function stopFly()
            if flyVel then flyVel:Destroy(); flyVel = nil end
            if flyGyro then flyGyro:Destroy(); flyGyro = nil end
        end
        local function startFly()
            local root = getRoot(); if not root then return end
            stopFly()
            flyVel = Instance.new('BodyVelocity')
            flyVel.MaxForce = Vector3.new(9e9, 9e9, 9e9); flyVel.Velocity = Vector3.zero
            pcall(function() CS:AddTag(flyVel, 'AllowedBM') end)
            flyVel.Parent = root
            flyGyro = Instance.new('BodyGyro')
            flyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9); flyGyro.P = 5e4; flyGyro.CFrame = root.CFrame
            pcall(function() CS:AddTag(flyGyro, 'AllowedBM') end)
            flyGyro.Parent = root
        end
        if Toggles.UFly then Toggles.UFly:OnChanged(function() if Toggles.UFly.Value then startFly() else stopFly() end end) end
        htrack(LocalPlayer.CharacterAdded:Connect(function()
            if Toggles.UFly and Toggles.UFly.Value then task.wait(0.3); startFly() end
        end))
        htrack(RunService.RenderStepped:Connect(function()
            if not (Toggles.UFly and Toggles.UFly.Value and flyVel and flyGyro) then return end
            local cam = workspace.CurrentCamera; if not cam then return end
            local cf, dir = cam.CFrame, Vector3.zero
            if UIS:IsKeyDown(Enum.KeyCode.W) then dir += cf.LookVector end
            if UIS:IsKeyDown(Enum.KeyCode.S) then dir -= cf.LookVector end
            if UIS:IsKeyDown(Enum.KeyCode.A) then dir -= cf.RightVector end
            if UIS:IsKeyDown(Enum.KeyCode.D) then dir += cf.RightVector end
            if UIS:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis end
            if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.yAxis end
            flyGyro.CFrame = cf
            flyVel.Velocity = (dir.Magnitude > 0 and dir.Unit or Vector3.zero) * ((Options.UFlySpeed and Options.UFlySpeed.Value) or 60)
            local hum = getHum()
            if hum and hum:GetState() == Enum.HumanoidStateType.Freefall then pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end) end
        end))
        htrack({ Disconnect = stopFly })

        -- ---- Noclip (Stepped so CanCollide sticks) + tween/fly noclip ------
        local tweening = false
        htrack(RunService.Stepped:Connect(function()
            local on = (Toggles.UNoclip and Toggles.UNoclip.Value)
                or (tweening and Toggles.UTweenNoclip and Toggles.UTweenNoclip.Value)
                or (Toggles.UFly and Toggles.UFly.Value)
            if not on then return end
            local char = getChar(); if not char then return end
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA('BasePart') and p.CanCollide then p.CanCollide = false end
            end
        end))

        -- ---- Tween to player (bounded glide, re-targets each frame) -------
        local tweenGen = 0
        local function targetPlayer()
            local name = Options.UTweenTarget and Options.UTweenTarget.Value
            if not name or name == '' then return nil end
            local p = Players:FindFirstChild(name)
            if not p then for _, pl in ipairs(Players:GetPlayers()) do if pl.DisplayName == name then p = pl; break end end end
            return p
        end
        tweenStop = function()
            tweenGen = tweenGen + 1; tweening = false
            if TweenStatus then TweenStatus:SetText('Idle') end
        end
        tweenTo = function()
            local p = targetPlayer()
            if not p then Library:Notify('Pick a player first', 2); return end
            if not getRoot() then Library:Notify('No character', 2); return end
            tweenGen = tweenGen + 1
            local gen = tweenGen
            tweening = true
            if TweenStatus then TweenStatus:SetText('-> ' .. p.Name) end
            task.spawn(function()
                local t0 = os.clock()
                while tweenGen == gen and os.clock() - t0 < 120 do
                    local dt = RunService.RenderStepped:Wait()
                    if tweenGen ~= gen then break end
                    local root = getRoot()
                    local tr = p.Parent and p.Character and p.Character:FindFirstChild('HumanoidRootPart')
                    if not tr then if TweenStatus then TweenStatus:SetText(p.Name .. ' not spawned') end; break end
                    if root then
                        local off = (Options.UTweenOffset and Options.UTweenOffset.Value) or 4
                        local goal = (tr.CFrame * CFrame.new(0, 0, off)).Position
                        local delta = goal - root.Position
                        local dist = delta.Magnitude
                        if dist <= 2 then
                            root.CFrame = CFrame.lookAt(goal, tr.Position)
                            if TweenStatus then TweenStatus:SetText('Arrived at ' .. p.Name) end
                            break
                        end
                        local step = math.min(dist, ((Options.UTweenSpeed and Options.UTweenSpeed.Value) or 150) * dt)
                        root.CFrame = CFrame.lookAt(root.Position + delta.Unit * step, tr.Position)
                        root.AssemblyLinearVelocity = Vector3.zero
                        local hum = getHum()
                        if hum and hum:GetState() == Enum.HumanoidStateType.Freefall then pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end) end
                    end
                end
                if tweenGen == gen then tweening = false end
            end)
        end
        if Options.UTweenKey then Options.UTweenKey:OnClick(function() tweenTo() end) end
        if Options.UTweenStopKey then Options.UTweenStopKey:OnClick(function() tweenStop() end) end
        htrack({ Disconnect = function() tweenGen = tweenGen + 1; tweening = false end })

        -- ---- Player ESP (Drawing API) ---------------------------------------
        if Drawing then
            local esp = {} -- [player] = drawings
            local function mk(class) local d = Drawing.new(class); d.Visible = false; return d end
            local function newEsp() return { box = mk('Square'), name = mk('Text'), dist = mk('Text'), hp = mk('Text'), tracer = mk('Line') } end
            local function hide(o) for _, d in pairs(o) do d.Visible = false end end
            local function remove(o) for _, d in pairs(o) do pcall(function() d:Remove() end) end end
            htrack(RunService.RenderStepped:Connect(function()
                local on = Toggles.UEsp and Toggles.UEsp.Value
                if not on then for _, o in pairs(esp) do hide(o) end; return end
                local cam = workspace.CurrentCamera; if not cam then return end
                local vp = cam.ViewportSize
                local myRoot = getRoot()
                local maxD = (Options.UEspMaxDist and Options.UEspMaxDist.Value) or 2000
                local color = (Options.UEspColor and Options.UEspColor.Value) or Color3.new(1, 1, 0)
                local seen = {}
                for _, p in ipairs(Players:GetPlayers()) do
                    local char = p ~= LocalPlayer and p.Character
                    local hum = char and char:FindFirstChildOfClass('Humanoid')
                    local root = char and char:FindFirstChild('HumanoidRootPart')
                    if hum and root and hum.Health > 0 then
                        seen[p] = true
                        local o = esp[p]; if not o then o = newEsp(); esp[p] = o end
                        local dist = myRoot and (myRoot.Position - root.Position).Magnitude or (cam.CFrame.Position - root.Position).Magnitude
                        local sp = cam:WorldToViewportPoint(root.Position)
                        if dist > maxD or sp.Z <= 0 then hide(o) else
                            local cf, size = char:GetBoundingBox()
                            local top = cam:WorldToViewportPoint((cf * CFrame.new(0, size.Y / 2, 0)).Position)
                            local bot = cam:WorldToViewportPoint((cf * CFrame.new(0, -size.Y / 2, 0)).Position)
                            local h = math.abs(bot.Y - top.Y); local w = h * 0.55
                            local x, y = sp.X - w / 2, math.min(top.Y, bot.Y)
                            o.box.Visible = Toggles.UEspBoxes and Toggles.UEspBoxes.Value or false
                            o.box.Color, o.box.Thickness, o.box.Filled = color, 1, false
                            o.box.Position, o.box.Size = Vector2.new(x, y), Vector2.new(w, h)
                            o.name.Visible = Toggles.UEspNames and Toggles.UEspNames.Value or false
                            o.name.Text = p.DisplayName ~= p.Name and (p.DisplayName .. ' (@' .. p.Name .. ')') or p.Name
                            o.name.Color, o.name.Size, o.name.Center, o.name.Outline = color, 13, true, true
                            o.name.Position = Vector2.new(sp.X, y - 16)
                            o.dist.Visible = Toggles.UEspDistance and Toggles.UEspDistance.Value or false
                            o.dist.Text = ('%.0f studs'):format(dist)
                            o.dist.Color, o.dist.Size, o.dist.Center, o.dist.Outline = Color3.new(1, 1, 1), 12, true, true
                            o.dist.Position = Vector2.new(sp.X, y + h + 2)
                            o.hp.Visible = Toggles.UEspHealth and Toggles.UEspHealth.Value or false
                            local frac = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                            o.hp.Text = ('%d / %d'):format(math.floor(hum.Health + 0.5), math.floor(hum.MaxHealth + 0.5))
                            o.hp.Color = Color3.fromRGB(0, 255, 0):Lerp(Color3.fromRGB(255, 0, 0), 1 - frac)
                            o.hp.Size, o.hp.Center, o.hp.Outline = 12, true, true
                            o.hp.Position = Vector2.new(sp.X, y + h + 16)
                            o.tracer.Visible = Toggles.UEspTracers and Toggles.UEspTracers.Value or false
                            o.tracer.Color, o.tracer.Thickness = color, 1
                            o.tracer.From, o.tracer.To = Vector2.new(vp.X / 2, vp.Y), Vector2.new(sp.X, y + h)
                        end
                    end
                end
                for p, o in pairs(esp) do
                    if not seen[p] then remove(o); esp[p] = nil end
                end
            end))
            htrack({ Disconnect = function() for p, o in pairs(esp) do remove(o); esp[p] = nil end end })
        else
            EspBox:AddLabel('Executor lacks the Drawing API - ESP unavailable.', true)
        end
    end

    -- UI Settings + config persistence for the non-roguecopy menu (its OWN folder
    -- so each game's saved config stays separate).
    local UITab = Window:AddTab('UI Settings')
    local MenuGroup = UITab:AddLeftGroupbox('Menu')
    MenuGroup:AddButton('Unload', function() Library:Unload() end)
    MenuGroup:AddLabel('Menu bind'):AddKeyPicker('MenuKeybind', { Default = 'End', NoUI = true, Text = 'Menu keybind' })
    Library.ToggleKeybind = Options.MenuKeybind

    Library:OnUnload(function()
        for _, c in ipairs(hubConns) do pcall(function() c:Disconnect() end) end
        getgenv().GameTestMenu_Unload = nil
        print('Game hub unloaded')
    end)

    ThemeManager:SetLibrary(Library)
    SaveManager:SetLibrary(Library)
    SaveManager:IgnoreThemeSettings()
    SaveManager:SetIgnoreIndexes({ 'MenuKeybind' })
    ThemeManager:SetFolder('GameHub_' .. HUB_CURRENT)
    SaveManager:SetFolder('GameHub_' .. HUB_CURRENT)
    SaveManager:BuildConfigSection(UITab)
    ThemeManager:ApplyToTab(UITab)

    -- Keybinds start blank + Backspace clears (same as the Rogue Lineage module).
    for name, obj in pairs(Options) do
        if name ~= 'MenuKeybind' and type(obj) == 'table' and obj.Mode ~= nil
           and type(obj.SetValue) == 'function' then
            pcall(function() if obj.Value ~= 'None' then obj:SetValue({ 'None', obj.Mode or 'Toggle' }) end end)
            if type(obj.OnChanged) == 'function' then
                obj:OnChanged(function()
                    if obj.Value == 'Backspace' then
                        pcall(function() obj:SetValue({ 'None', obj.Mode or 'Toggle' }) end)
                        Library:Notify('Keybind cleared (press a key to rebind)', 1.5)
                    end
                end)
            end
        end
    end

    SaveManager:LoadAutoloadConfig()
    return
end

-- ============================================================================
-- ROGUECOPY (Rogue Lineage) MODULE - only runs when HUB_CURRENT == 'roguecopy'.
-- Everything from here down is the original menu, unchanged.
-- ============================================================================

-- 2. Services / locals ---------------------------------------------------------
local Players    = game:GetService('Players')
local RunService = game:GetService('RunService')
local UIS        = game:GetService('UserInputService')
local Lighting   = game:GetService('Lighting')
local RepStorage = game:GetService('ReplicatedStorage')
local Teleport   = game:GetService('TeleportService')
local HttpServ   = game:GetService('HttpService')

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

-- Track everything we connect so we can cleanly disconnect on unload.
local Connections = {}
local function track(conn) table.insert(Connections, conn); return conn end

-- Fresh character accessors (survive respawns) --------------------------------
local function getChar() return LocalPlayer.Character end
local function getHumanoid()
    local c = getChar()
    return c and c:FindFirstChildOfClass('Humanoid')
end
local function getRoot()
    local c = getChar()
    return c and c:FindFirstChild('HumanoidRootPart')
end

-- 3. Window / tabs -------------------------------------------------------------
local Window = Library:CreateWindow({
    Title = 'Game Hub - Rogue Lineage',
    Center = true,
    AutoShow = true,
    TabPadding = 8,
    MenuFadeTime = 0.2,
})

local Tabs = {
    Main = Window:AddTab('Main'),
    Combat = Window:AddTab('Combat'),
    Teleport = Window:AddTab('Teleport'),
    Visuals = Window:AddTab('Visuals'),
    Experimental = Window:AddTab('Experimental'),
    QOL = Window:AddTab('QOL'),
    ['UI Settings'] = Window:AddTab('UI Settings'),
}

local MoveBox  = Tabs.Main:AddLeftGroupbox('Movement')
local WorldBox = Tabs.Main:AddRightGroupbox('World')

-- ============================================================================
-- 4. UI ELEMENTS (built first, logic wired later)
-- ============================================================================

-- WalkSpeed: keybind chained onto the toggle so SyncToggleState works.
MoveBox:AddToggle('WalkSpeedEnabled', {
    Text = 'WalkSpeed',
    Default = false,
    Tooltip = 'Override WalkSpeed with the slider value',
}):AddKeyPicker('WalkSpeedKey', {
    Default = 'F', SyncToggleState = true, Mode = 'Toggle', Text = 'WalkSpeed',
})
MoveBox:AddSlider('WalkSpeedValue', {
    Text = 'WalkSpeed', Default = 50, Min = 16, Max = 200, Rounding = 0, Suffix = ' studs/s',
})

-- Fly
MoveBox:AddToggle('FlyEnabled', {
    Text = 'Fly',
    Default = false,
    Tooltip = 'WASD to move, Space/Ctrl for up/down',
}):AddKeyPicker('FlyKey', {
    Default = 'G', SyncToggleState = true, Mode = 'Toggle', Text = 'Fly',
})
MoveBox:AddSlider('FlySpeed', {
    Text = 'Fly speed', Default = 60, Min = 10, Max = 200, Rounding = 0, Suffix = ' studs/s',
})

-- Noclip
MoveBox:AddToggle('NoclipEnabled', {
    Text = 'Noclip',
    Default = false,
    Tooltip = 'Walk through parts',
}):AddKeyPicker('NoclipKey', {
    Default = 'N', SyncToggleState = true, Mode = 'Toggle', Text = 'Noclip',
})

-- Infinite Jump
MoveBox:AddToggle('InfJumpEnabled', {
    Text = 'Infinite Jump',
    Default = false,
}):AddKeyPicker('InfJumpKey', {
    Default = 'J', SyncToggleState = true, Mode = 'Toggle', Text = 'Infinite Jump',
})

-- Jump Power
MoveBox:AddToggle('JumpPowerEnabled', {
    Text = 'Jump Power',
    Default = false,
})
MoveBox:AddSlider('JumpPowerValue', {
    Text = 'Jump power', Default = 50, Min = 50, Max = 500, Rounding = 0,
})

-- Attach to back: teleport behind the nearest target each frame
MoveBox:AddToggle('AttachBack', {
    Text = 'Attach to back',
    Default = false,
    Tooltip = 'Teleport behind the nearest target each frame (faces them)',
})
MoveBox:AddSlider('AttachDistance', {
    Text = 'Attach distance', Default = 5, Min = 0, Max = 30, Rounding = 1, Suffix = ' studs',
})
MoveBox:AddSlider('AttachY', {
    Text = 'Attach Y level', Default = 0, Min = -10, Max = 10, Rounding = 1, Suffix = ' studs',
})
MoveBox:AddSlider('AttachRange', {
    Text = 'Attach max range', Default = 50, Min = 5, Max = 300, Rounding = 0, Suffix = ' studs',
    Tooltip = 'Only attach to targets within this range (prevents TPing across the map)',
})
MoveBox:AddSlider('AttachSpeed', {
    Text = 'Attach smoothness', Default = 0.35, Min = 0.03, Max = 1, Rounding = 2,
    Tooltip = 'Glide speed to the target. Lower = smoother tween, less likely to be kicked. 1 = instant snap.',
})
MoveBox:AddToggle('AttachDodge', {
    Text = 'Auto-dodge target attacks',
    Default = false,
    Tooltip = 'When the attach target swings, back off briefly then re-attach',
})
MoveBox:AddSlider('DodgeDistance', {
    Text = 'Dodge back', Default = 12, Min = 2, Max = 40, Rounding = 0, Suffix = ' studs',
})
MoveBox:AddSlider('DodgeTime', {
    Text = 'Dodge time', Default = 0.35, Min = 0.1, Max = 1, Rounding = 2, Suffix = ' s',
    Tooltip = 'How long to stay backed off after the target starts an attack',
})

-- World features
WorldBox:AddToggle('NoFallDamage', {
    Text = 'No Fall Damage',
    Default = false,
    Tooltip = 'Drops the client-sided fall-damage remote. Catches BOTH namecall (Bleach TakeDamage) and direct FireServer (Rogue Lineage ApplyFallDamage), so it works across games.',
})
WorldBox:AddToggle('NoFog', {
    Text = 'No Fog',
    Default = false,
    Tooltip = 'Clears the teal murk: pushes Lighting fog past the horizon, zeroes Atmosphere density/haze/glare, and disables Terrain clouds. Re-asserted every frame so the weather cycle cannot bring it back.',
})
WorldBox:AddToggle('NoKillBricks', {
    Text = 'No Kill Bricks',
    Default = false,
    Tooltip = 'Neutralizes named instakill parts on YOUR client (PITBASE void floor, ArdorianKillbrick, Lava, Traps) by killing their Touch, and drops the client-reported SunBurn (vampire sunlight) hazard. NOTE: the void pit is also enforced server-side on touch - use Fly to cross it, a toggle cannot cancel a server-side kill.',
})
WorldBox:AddToggle('Invisible', {
    Text = 'Invisible (LOCAL view only)',
    Default = false,
    Tooltip = 'Turns YOUR character transparent. HONEST LIMIT: under RL server-authority a client transparency write does NOT replicate - OTHER players still see you (same reason melee-resize does not work). So this only hides you on YOUR screen. Real hide-from-others in RL exists ONLY as OWNED abilities (Stealth / Shadestep / Rift Dive - the SERVER fades you and replicates it); there is NO safe client-side way to trigger that, so this toggle is local-only. Re-asserted each frame; restored when off.',
}):AddKeyPicker('InvisibleKey', {
    Default = 'B', SyncToggleState = true, Mode = 'Toggle', Text = 'Invisible',
})

-- Instantly knock yourself (drop HP to 0) via a massive self fall-damage report.
local selfKnock -- forward-declared for the button/keybind
WorldBox:AddButton({
    Text = 'Knock self (HP -> 0)',
    Func = function() if selfKnock then selfKnock() end end,
    Tooltip = 'Instantly knock yourself. Fires your own ApplyFallDamage with overkill damage (Rogue Lineage) - works even with No Fall Damage on.',
})
WorldBox:AddLabel('Knock key'):AddKeyPicker('KnockKey', {
    Default = 'K', Mode = 'Toggle', Text = 'Knock self',
})

-- AA gun = server-side anti-cheat that kills you for staying airborne too long.
-- No remote fires, so it can't be blocked. This just times how long you've been
-- airborne and learns the lethal threshold from when it actually kills you.
local AABox = Tabs.Main:AddRightGroupbox('Anti-Cheat (AA Gun)')
AABox:AddLabel('Server kills you for prolonged flight.\nCannot be blocked - this only warns you.', true)
local AATimerLabel = AABox:AddLabel('Airborne: idle')
AABox:AddSlider('AAThreshold', {
    Text = 'Est. AA time', Default = 12, Min = 3, Max = 60, Rounding = 1, Suffix = ' s',
    Tooltip = 'Your guess at the lethal airborne time. Calibrate it from death notifications.',
})
AABox:AddToggle('AAAutoDisableFly', {
    Text = 'Auto-disable fly before AA',
    Default = true,
    Tooltip = 'Cuts fly ~1s before the estimated AA time so you drop and reset the timer',
})

-- Server hop ------------------------------------------------------------------
local serverHop, rejoinServer, clearVisited -- forward-declared for the buttons

local ServerBox = Tabs.Main:AddRightGroupbox('Server')
local ServerLabel = ServerBox:AddLabel('Visited: 0 servers')
ServerBox:AddButton({
    Text = 'Server Hop (lowest pop)',
    Func = function() if serverHop then serverHop() end end,
    Tooltip = 'Find the least-populated joinable server (skips ones you already hopped to)',
})
ServerBox:AddButton({
    Text = 'Rejoin',
    Func = function() if rejoinServer then rejoinServer() end end,
})
ServerBox:AddButton({
    Text = 'Clear visited list',
    Func = function() if clearVisited then clearVisited() end end,
    Tooltip = 'Forget the blocklist of servers you have already joined',
})

-- Combat tab ------------------------------------------------------------------
local doParry, saveAttackDB, clearAttackDB, clearTimings, timedBlock, dumpTimings, doDodge -- forward-declared
local runCombo -- combo-macro runner (Combat Extras)
local returnToWeapon -- weapon-slot swap-back (Weapon Swap)
local voidGrabbed, flingGrabbed -- grab-void / grab-fling (Experimental)
local runGateCombo -- pick target -> TP -> grab -> gate -> lava (Experimental)

local ParryBox = Tabs.Combat:AddLeftGroupbox('Auto Parry')
ParryBox:AddToggle('AutoParry', {
    Text = 'Auto Parry',
    Default = false,
    Tooltip = 'Fires the parry remote when a logged attack animation plays nearby',
})
ParryBox:AddToggle('AutoEquip', {
    Text = 'Auto-equip on enable',
    Default = false,
    Tooltip = 'Fires ToggleWeapon when Auto Parry turns on. Leave OFF if your weapon is already out (it would unequip you).',
})
ParryBox:AddToggle('ParryIgnorePlayers', {
    Text = 'Ignore player anims',
    Default = false,
    Tooltip = 'Only auto-parry mob attacks, never other players (PvE only)',
})
ParryBox:AddSlider('ParryDistance', {
    Text = 'Parry range', Default = 30, Min = 5, Max = 120, Rounding = 0, Suffix = ' studs',
})
ParryBox:AddSlider('ParryReactionDelay', {
    Text = 'React delay', Default = 0, Min = 0, Max = 0.6, Rounding = 2, Suffix = ' s',
    Tooltip = 'Wait this long after an attack anim before parrying (tune to game timing)',
})
ParryBox:AddSlider('ParryCooldown', {
    Text = 'Cooldown', Default = 0.4, Min = 0, Max = 3, Rounding = 2, Suffix = ' s',
})
ParryBox:AddDropdown('ParryMode', {
    Values = { 'Smart (no setup)', 'Database (IDs)', 'Both' },
    Default = 2, Multi = false, Text = 'Detect mode',
    Tooltip = 'Database = parry ONLY real attacks from VV game data (no false parries on walk/strafe/block). Smart = any non-looping facing attack. Both = either.',
})
ParryBox:AddDropdown('ParryTiming', {
    Values = { 'Learned (trained)', 'On hit marker', 'On start', 'Fixed delay' },
    Default = 1, Multi = false, Text = 'Timing',
    Tooltip = 'Learned = hand-measured DB first, then timings you trained, then a fallback %. This is the Aztup-style path - use it.',
})
ParryBox:AddSlider('ParryFacing', {
    Text = 'Facing', Default = 0.3, Min = -1, Max = 1, Rounding = 2,
    Tooltip = 'How much the enemy must face you (-1 = ignore, ~0.3 = front arc)',
})
ParryBox:AddSlider('ParryMinLen', {
    Text = 'Min anim len', Default = 0.3, Min = 0, Max = 2, Rounding = 2, Suffix = ' s',
    Tooltip = 'Smart mode ignores animations shorter than this (filters tiny effect stubs)',
})
ParryBox:AddSlider('ParryFallback', {
    Text = 'Untrained hit %', Default = 0.5, Min = 0.1, Max = 1, Rounding = 2,
    Tooltip = 'For attacks you have not trained, parry at this fraction of the animation length (so they are not missed)',
})
ParryBox:AddSlider('ParryPingComp', {
    Text = 'Ping compensation', Default = 50, Min = 0, Max = 100, Rounding = 0, Suffix = ' %',
    Tooltip = 'Block this % of your ping EARLIER so the parry lands on time despite latency (Aztup-style). 0 = off.',
})
ParryBox:AddToggle('AutoLearn', {
    Text = 'Auto-learn attacks', Default = true,
    Tooltip = 'When an attack hit-marker fires, save its anim ID to the database automatically',
})
ParryBox:AddToggle('AutoTrain', {
    Text = 'Learn timings while fighting', Default = true,
    Tooltip = 'When an auto-parry lands (the attack gets interrupted), record its exact timing - the DB self-trains as you fight',
})
ParryBox:AddToggle('ReadFeints', {
    Text = 'Read feints', Default = true,
    Tooltip = 'Do not parry if the attack cancels before its hit (the mob feinted to bait your parry)',
})
ParryBox:AddDropdown('ParryMethod', {
    Values = { 'Right-click (real parry)', 'Mouse2 (block/parry)', 'RedCounter (blade catch)', 'Block (Combat tap)' },
    Default = 1,
    Multi = false,
    Text = 'Parry method',
    Tooltip = 'Right-click = simulate a real RMB so 1s own parry window runs (recommended)',
})
ParryBox:AddButton({
    Text = 'Test Parry',
    Func = function() if doParry then doParry() end end,
    Tooltip = 'Fire the parry remote once to confirm it works',
})
ParryBox:AddButton({
    Text = 'Toggle Weapon',
    Func = function()
        local c = RepStorage:FindFirstChild('Requests')
        local r = c and c:FindFirstChild('Combat')
        if r then r:FireServer('ToggleWeapon') end
    end,
    Tooltip = 'Manually equip/unequip your weapon',
}):AddButton({
    Text = 'Save DB',
    Func = function() if saveAttackDB then saveAttackDB() end end,
    Tooltip = 'Write learned attack IDs to file',
})
ParryBox:AddButton({
    Text = 'Clear learned DB',
    Func = function() if clearAttackDB then clearAttackDB() end end,
    Tooltip = 'Forget auto-learned attack IDs (keeps the built-in seed list)',
})
-- Parry timing controls (moved here from the removed Parry Trainer box - Auto
-- Parry and Learn-timings still depend on them).
ParryBox:AddSlider('ParryLead', {
    Text = 'Parry lead', Default = 0.06, Min = 0, Max = 0.3, Rounding = 2, Suffix = ' s',
    Tooltip = 'Raise block this long before the learned hit time',
})
ParryBox:AddSlider('BlockHold', {
    Text = 'Block hold', Default = 0.25, Min = 0.05, Max = 1, Rounding = 2, Suffix = ' s',
    Tooltip = 'How long to hold block when parrying',
})
local TrainerLabel = ParryBox:AddLabel('Learned timings: 0')
local SourceLabel  = ParryBox:AddLabel('Source DB: building...')

local DodgeBox = Tabs.Combat:AddLeftGroupbox('Auto Dodge')
DodgeBox:AddLabel('Dodges UNPARRYABLE (red) attacks using\nVV\'s own ParryIndicator. No guessing.', true)
DodgeBox:AddToggle('AutoDodge', {
    Text = 'Auto-dodge red attacks', Default = false,
    Tooltip = 'Listens to VV\'s ParryIndicator event and fires the Dash remote on red (unparryable) attacks. Parryable attacks are left to Auto Parry.',
})
DodgeBox:AddDropdown('DodgeDir', {
    Values = { 'Alternate L/R', 'Left (A)', 'Right (D)', 'Back (S)' },
    Default = 1, Multi = false, Text = 'Dodge direction',
    Tooltip = 'Which way to dash. Alternate flips left/right each dodge so you do not drift one way.',
})
DodgeBox:AddDropdown('DodgeOn', {
    Values = { 'Rushdown', 'NeutralParry', 'NormalParry', 'Riposte' },
    Default = {}, Multi = true, Text = 'Also dodge (besides Red)',
    Tooltip = 'Red (unparryable) is always dodged. Tick extra indicator types here to dodge instead of parrying them.',
})
DodgeBox:AddSlider('DodgeCooldown', {
    Text = 'Dodge cooldown', Default = 0.5, Min = 0, Max = 3, Rounding = 2, Suffix = ' s',
})
DodgeBox:AddToggle('DodgeNotify', { Text = 'Notify on dodge', Default = true })
DodgeBox:AddButton({
    Text = 'Test dodge (left)',
    Func = function() if doDodge then doDodge('A') end end,
    Tooltip = 'Fire one left dash to confirm the Dash remote works',
})

local ExpBox = Tabs.Combat:AddRightGroupbox('Experimental')
ExpBox:AddToggle('NoStun', {
    Text = 'No stun (cancel stun anims)', Default = false,
    Tooltip = 'Stops stun animations on your character so you can act through hits (uses the built-in STUN_ANIMS id list).',
})
ExpBox:AddToggle('AIBreaker', {
    Text = 'AI breaker', Default = false,
    Tooltip = 'Disable nearby mob AI so they cannot attack/parry. Only works if VV lets the client own the mob (network ownership). Experimental.',
})
ExpBox:AddDropdown('AIBreakMethod', {
    Values = { 'Stop combat anims', 'Freeze + slow', 'Ragdoll (physics)', 'All' },
    Default = 4, Multi = false, Text = 'AI break method',
})
ExpBox:AddSlider('AIBreakRange', {
    Text = 'AI break range', Default = 60, Min = 10, Max = 300, Rounding = 0, Suffix = ' studs',
})
ExpBox:AddToggle('AIBreakTargetOnly', {
    Text = 'AI break: target only', Default = false,
    Tooltip = 'Only break the locked attach target, not every nearby mob',
})

-- Combat Extras: anti-grab, auto-M1, movestack ------------------------------
local ExtraBox = Tabs.Combat:AddRightGroupbox('Combat Extras')
ExtraBox:AddToggle('AntiGrab', {
    Text = 'Anti-grab / auto-getup', Default = false,
    Tooltip = 'The instant you are Grabbed / Knocked / Unconscious, auto-mash the game\'s OWN escape inputs (F to get up, movement + jump to struggle a grab) so you break free as soon as the server allows. No reaction delay.',
})
ExtraBox:AddDivider()
ExtraBox:AddLabel('M1 speed is server-gated - these are the\nlegit client levers (rate + local anim + cancel).', true)
ExtraBox:AddToggle('AutoM1', {
    Text = 'Auto M1', Default = false,
    Tooltip = 'Spam LightAttack at the interval below. Hold the key (or tick the box). Server rejects extras that come too fast, so raise the interval if swings drop.',
}):AddKeyPicker('AutoM1Key', {
    Default = 'E', SyncToggleState = true, Mode = 'Hold', Text = 'Auto M1',
})
ExtraBox:AddSlider('M1Rate', {
    Text = 'M1 interval', Default = 0.28, Min = 0.1, Max = 1, Rounding = 2, Suffix = ' s',
})
ExtraBox:AddSlider('M1AnimSpeed', {
    Text = 'M1 anim speed (local)', Default = 1, Min = 1, Max = 3, Rounding = 2, Suffix = 'x',
    Tooltip = 'Speeds up YOUR swing animation locally so you can input the next M1 sooner. Experimental - the server still gates the real combo timing, so this is mostly feel/queue help.',
})
ExtraBox:AddToggle('MoveStack', {
    Text = 'Attack-cancel (movestack)', Default = false,
    Tooltip = 'After each auto M1, fire a quick cancel input to cut the recovery, then continue - chains combos faster IF the server accepts the cancel (RL-style dash/block cancel). Experimental.',
})
ExtraBox:AddDropdown('MoveStackWith', {
    Values = { 'Dash', 'Block tap', 'Sheath/unsheath' },
    Default = 1, Multi = false, Text = 'Cancel with',
})

local ComboBox = Tabs.Combat:AddRightGroupbox('Combo Macro')
ComboBox:AddLabel('Build a combo from tokens, run it on a key:\nm1 heavy block parry dash dashl dashr\ndashf dashb sheath wait', true)
ComboBox:AddInput('ComboSeq', {
    Text = 'Combo', Default = 'm1,m1,m1,heavy', Finished = true, Placeholder = 'm1,m1,m1,dash,heavy',
    Tooltip = 'Comma/space separated tokens. "wait" just inserts one step delay.',
})
ComboBox:AddSlider('ComboStep', {
    Text = 'Step delay', Default = 0.16, Min = 0.03, Max = 1, Rounding = 2, Suffix = ' s',
    Tooltip = 'Delay between combo steps. Lower = faster (server may reject too-fast).',
})
ComboBox:AddButton({ Text = 'Run combo', Func = function() if runCombo then runCombo() end end })
ComboBox:AddLabel('Combo key'):AddKeyPicker('ComboKey', {
    Default = 'C', Mode = 'Toggle', Text = 'Run combo',
})

local SwapBox = Tabs.Combat:AddRightGroupbox('Weapon Swap')
SwapBox:AddLabel('Casting a hotbar move leaves you holding it.\nThis snaps you back to your weapon slot after\nyou cast (arms on a move-slot key, returns on\nthe click). Also a manual key.', true)
SwapBox:AddToggle('AutoReturnWeapon', {
    Text = 'Auto return to weapon', Default = false,
    Tooltip = 'After you switch to a move slot and cast (click), auto-press your weapon-slot key so you are not stuck holding the move. Never fires while you are on the weapon, so it can\'t interrupt M1s.',
})
SwapBox:AddSlider('WeaponSlot', {
    Text = 'Weapon slot', Default = 1, Min = 1, Max = 10, Rounding = 0,
    Tooltip = 'Which hotbar slot your weapon is in (you keep it in slot 1).',
})
SwapBox:AddSlider('ReturnDelay', {
    Text = 'Return delay', Default = 0.3, Min = 0, Max = 1.5, Rounding = 2, Suffix = ' s',
    Tooltip = 'Wait this long after the cast before swapping back, so the move goes off. Raise it if moves get cut short; 0 = instant.',
})
SwapBox:AddButton({ Text = 'Return to weapon now', Func = function() if returnToWeapon then returnToWeapon() end end })
SwapBox:AddLabel('Return key'):AddKeyPicker('ReturnKey', {
    Default = 'V', Mode = 'Toggle', Text = 'Return to weapon',
})

-- Melee Reach -----------------------------------------------------------------
local ReachBox = Tabs.Combat:AddLeftGroupbox('Melee Reach')
ReachBox:AddLabel('RL melee is a SERVER-side range check around\nYOU, so resizing parts does nothing (the server\nnever sees it). This glides you into range of\nwhatever you AIM at - no resizing, no screen mess.', true)
ReachBox:AddToggle('Reach', {
    Text = 'Melee reach',
    Default = false,
    Tooltip = 'Glide to melee range of the enemy you aim at so your normal M1s land from far away. Only pulls you when you are actually aiming at a valid target.',
})
ReachBox:AddSlider('ReachRange', {
    Text = 'Search range', Default = 80, Min = 10, Max = 400, Rounding = 0, Suffix = ' studs',
    Tooltip = 'How far away a target can be for reach to lock onto it.',
})
ReachBox:AddSlider('ReachMelee', {
    Text = 'Stand-off', Default = 6, Min = 2, Max = 15, Rounding = 1, Suffix = ' studs',
    Tooltip = 'How close to sit to the target. Keep it under your weapon length so M1s connect (most RL weapons ~7-10).',
})
ReachBox:AddSlider('ReachAim', {
    Text = 'Aim tightness', Default = 0.4, Min = 0, Max = 1, Rounding = 2,
    Tooltip = 'How near your crosshair the target must be. 0 = ignore aim (just the nearest), 1 = must be dead-centre.',
})
ReachBox:AddToggle('ReachAbove', {
    Text = 'Float above target', Default = false,
    Tooltip = 'Sit directly above the target (out of its swing arc) instead of behind it.',
})
ReachBox:AddToggle('ReachPlayersOnly', {
    Text = 'Players only', Default = false,
    Tooltip = 'Only reach toward other players, never mobs/NPCs.',
})

-- Visuals tab: Mob ESP --------------------------------------------------------
local EspBox = Tabs.Visuals:AddLeftGroupbox('Mob ESP')
EspBox:AddToggle('MobESP', {
    Text = 'Mob ESP',
    Default = false,
    Tooltip = 'Draw ESP on hollows/mobs (hostile non-player Humanoids, no interact prompt)',
})
EspBox:AddToggle('NPCESP', {
    Text = 'NPC ESP',
    Default = false,
    Tooltip = 'Draw ESP on interactable NPCs (quest givers / vendors - they have a ProximityPrompt)',
})
EspBox:AddToggle('PlayerESP', {
    Text = 'Player ESP',
    Default = false,
    Tooltip = 'Draw ESP on other players',
})
EspBox:AddToggle('ESPBoxes',    { Text = 'Boxes',     Default = true })
EspBox:AddToggle('ESPNames',    { Text = 'Names',     Default = true })
EspBox:AddToggle('ESPHealth',   { Text = 'Health bar', Default = true })
EspBox:AddToggle('ESPHP',       { Text = 'HP number',  Default = true })
EspBox:AddToggle('ESPDistance', { Text = 'Distance',  Default = true })
EspBox:AddSlider('ESPMaxDistance', {
    Text = 'Max distance', Default = 500, Min = 50, Max = 2000, Rounding = 0, Suffix = ' studs',
    Tooltip = 'Max distance for NPC + Player ESP. Mobs have their own slider below.',
})
EspBox:AddSlider('MobMaxDistance', {
    Text = 'Mob max distance', Default = 1000, Min = 50, Max = 5000, Rounding = 0, Suffix = ' studs',
    Tooltip = 'Max distance for MOB ESP only (mobs in workspace.Alive). NPC/Player use the general Max distance above.',
})
EspBox:AddLabel('Mob color'):AddColorPicker('ESPColor', {
    Default = Color3.fromRGB(255, 80, 80), Title = 'Mob color',
})
EspBox:AddLabel('NPC color'):AddColorPicker('NPCColor', {
    Default = Color3.fromRGB(90, 200, 255), Title = 'NPC color',
})
EspBox:AddLabel('Player color'):AddColorPicker('PlayerColor', {
    Default = Color3.fromRGB(255, 255, 0), Title = 'Player color',
})
EspBox:AddToggle('ESPNameDebug', {
    Text = 'Debug names (console)', Default = false,
    Tooltip = 'Print where un-named entities might store their name (to fix "Mob")',
})

local ProxBox = Tabs.Visuals:AddRightGroupbox('Proximity')
ProxBox:AddLabel('Ding + on-screen list of who is near.', true)
ProxBox:AddToggle('ProxAlert', {
    Text = 'Alert ding', Default = false,
    Tooltip = 'Play a sound when someone enters range',
})
ProxBox:AddToggle('ProxList', {
    Text = 'On-screen list', Default = false,
    Tooltip = 'Show nearby names + distance on screen',
})
ProxBox:AddSlider('ProxRange', {
    Text = 'Range', Default = 100, Min = 20, Max = 1000, Rounding = 0, Suffix = ' studs',
})
ProxBox:AddToggle('ProxIncludeMobs', {
    Text = 'Include mobs/NPCs', Default = false,
    Tooltip = 'Also alert/list nearby mobs and NPCs, not just players',
})

-- Trinket ESP: find lootable trinkets, identified by the TrinketTypeLib -------
local ArtBox = Tabs.Visuals:AddRightGroupbox('Trinket ESP')
ArtBox:AddLabel('Finds lootable trinkets in the workspace\n"Dinkets" folder. They are NOT named, so each is\nidentified by mesh/colour and coloured by type.\nThrough-wall + off-screen edge labels.', true)
ArtBox:AddToggle('TrinketESP', {
    Text = 'Trinket ESP', Default = false,
    Tooltip = 'Mark every lootable trinket across the whole map, named + colour-coded by type.',
})
ArtBox:AddToggle('TrinketHighlight', {
    Text = 'Highlight (through walls)', Default = true,
    Tooltip = 'AlwaysOnTop outline on the trinket so you see it through terrain.',
})
ArtBox:AddToggle('TrinketNames',    { Text = 'Names', Default = true })
ArtBox:AddToggle('TrinketDistance', { Text = 'Distance', Default = true })
ArtBox:AddToggle('TrinketTracer',   { Text = 'Tracers', Default = false,
    Tooltip = 'Draw a line from the bottom of your screen toward each trinket.' })
ArtBox:AddToggle('TrinketHideUnknown', {
    Text = 'Hide unidentified', Default = false,
    Tooltip = 'Hide trinkets the type library cannot identify (otherwise shown white as "Unknown").',
})
-- Shared trinket name list (used by BOTH the ESP "Show only" and the Farm "Farm
-- only" dropdowns so they never drift out of sync).
local TRINKET_NAMES = {
    '???', 'Amulet', 'Amulet of the White King', 'Candy', 'Diamond', 'Emerald',
    'Fairfrozen', 'Goblet', 'Howler Friend', 'Ice Essence', 'Idol of the Forgotten',
    [[Lannis's Amulet]], 'Mysterious Artifact', 'Night Stone', 'Old Amulet', 'Old Ring',
    'Opal', 'Phoenix Down', [[Philosopher's Stone]], 'Rift Gem', 'Ring', 'Ruby',
    'Sapphire', 'Scroll', 'Scroom Key', 'Spider Cloak', 'Unknown',
}
ArtBox:AddDropdown('TrinketFilter', {
    Values = TRINKET_NAMES,
    Default = {}, Multi = true, AllowNull = true, Text = 'Show only',
    Tooltip = 'Tick the trinkets you want to see. Leave EVERYTHING unticked to show all trinkets.',
})
ArtBox:AddSlider('TrinketMaxDist', {
    Text = 'Max distance', Default = 100000, Min = 100, Max = 100000, Rounding = 0, Suffix = ' studs',
    Tooltip = 'Map-wide by default. Lower it to only show trinkets within range.',
})

-- Trinket Farm: auto-TP to trinkets and collect them ------------------------
local FarmBox = Tabs.Visuals:AddRightGroupbox('Trinket Farm')
FarmBox:AddLabel('Auto-travel to trinkets and collect them. Tick which\nones in "Farm only" below (leave it empty = grab\neverything). Glide is the snapback-proof travel with\nno cooldown - best for bulk. Keep No Fall Damage on.', true)
local FarmStatus = FarmBox:AddLabel('Idle')
FarmBox:AddDropdown('FarmFilter', {
    Values = TRINKET_NAMES,
    Default = {}, Multi = true, AllowNull = true, Text = 'Farm only',
    Tooltip = 'Tick the trinkets to FARM - independent of the Trinket ESP "Show only" filter. Leave EVERYTHING unticked to farm every trinket.',
})
FarmBox:AddToggle('TrinketFarm', {
    Text = 'Auto-farm trinkets', Default = false,
    Tooltip = 'Repeatedly travel to the nearest trinket that matches "Farm only" and fire its collect (fireclickdetector on the trinket). Stops when none are left. The key below toggles it on/off.',
}):AddKeyPicker('TrinketFarmKey', {
    Default = 'I', SyncToggleState = true, Mode = 'Toggle', Text = 'Auto-farm trinkets',
})
FarmBox:AddDropdown('FarmTPMethod', {
    Values = { 'Glide (no cooldown)', 'Gate bypass (5s each)', 'Instant (grab before snapback)' },
    Default = 1, Multi = false, Text = 'Travel method',
    Tooltip = 'Glide (DEFAULT - use this) = continuous bounded move, no snapback, no cooldown, no Gate needed. The right method for farming. Gate bypass = PATCHED for farming: single gate TPs (Teleport tab / NPC TP) still work, but the server now snaps back / blocks RAPID repeated gate teleports, so it fails when spammed one-per-trinket - do NOT farm with it. Instant = fastest but a cold TPSafe usually snaps back before the collect registers (misses some).',
})
FarmBox:AddSlider('FarmReach', {
    Text = 'Collect radius', Default = 10, Min = 4, Max = 40, Rounding = 0, Suffix = ' studs',
    Tooltip = 'How close to get before firing the collect / counting as arrived.',
})
FarmBox:AddSlider('FarmDelay', {
    Text = 'Per-trinket delay', Default = 0.35, Min = 0.1, Max = 2, Rounding = 2, Suffix = ' s',
    Tooltip = 'Pause after each trinket so the pickup registers before moving on.',
})

-- Auto server-hop farm: cast Trinket Shift on arrival, farm, hop when dry ------
FarmBox:AddDivider()
FarmBox:AddToggle('AutoHopFarm', {
    Text = 'Auto server-hop farm', Default = false,
    Tooltip = 'On join: cast Trinket Shift (the slot below), then run the Trinket Farm. When the farm runs dry it server-hops to a fresh low-pop server and repeats. PERSISTS across hops via a flag file - REQUIRES the menu to auto-run on each new server (put this script in your executor\'s auto-execute folder). Toggle off to stop + clear the flag.',
})
FarmBox:AddSlider('ShiftSlot', {
    Text = 'Trinket Shift slot', Default = 4, Min = 1, Max = 10, Rounding = 0,
    Tooltip = 'Which hotbar slot your Trinket Shift move is in (you said 4).',
})
FarmBox:AddDropdown('ShiftActivate', {
    Values = { 'Left click (M1)', 'Right click (M2)', 'Equip only' },
    Default = 1, Multi = false, Text = 'Shift activation',
    Tooltip = 'How the move casts after equipping the slot. Left = tool Activate + M1 (most moves). Right = the RightClick remote + M2 (gate-style). Equip only = just hold it. If it doesn\'t cast, flip this.',
})
FarmBox:AddSlider('ShiftRecast', {
    Text = 'Re-cast shift every', Default = 12, Min = 0, Max = 60, Rounding = 0, Suffix = ' s',
    Tooltip = 'Re-cast Trinket Shift on this interval so the disguise does not lapse mid-farm (its own cooldown still applies - an early re-cast just no-ops). 0 = only cast once on arrival.',
})
FarmBox:AddSlider('HopWhenDry', {
    Text = 'Hop after dry for', Default = 5, Min = 1, Max = 30, Rounding = 0, Suffix = ' s',
    Tooltip = 'Wait this long with no farmable trinkets left before server-hopping (avoids hopping on a brief empty while trinkets stream in).',
})
-- Menu bypass: after a hop RL drops you at the save-slot Data List -> main menu,
-- so before farming we auto-pick your slot and click PLAY to actually spawn.
-- (funcs assigned in the auto-hop logic block far below).
local autoMenuNow, dumpMenuButtons
FarmBox:AddSlider('SaveSlot', {
    Text = 'Save slot (row)', Default = 2, Min = 1, Max = 6, Rounding = 0,
    Tooltip = 'Which save-slot ROW to load on a fresh server (top = 1). Your Spy is whichever row it shows in the Data List. Overridden by "Slot match" if that is filled.',
})
FarmBox:AddInput('SlotMatch', {
    Text = 'Slot match', Default = '', Finished = true, Placeholder = 'your name or Spy',
    Tooltip = 'MORE RELIABLE than the row number: click the slot row whose text contains this (your character NAME or CLASS, e.g. Spy). Leave blank to use the row number instead.',
})
FarmBox:AddButton({ Text = 'Pick slot + PLAY (test)', Func = function() if autoMenuNow then autoMenuNow() end end })
    :AddButton({ Text = 'Dump menu buttons', Func = function() if dumpMenuButtons then dumpMenuButtons() end end })
FarmBox:AddSlider('LoadSettle', {
    Text = 'Load settle', Default = 5, Min = 0, Max = 20, Rounding = 0, Suffix = ' s',
    Tooltip = 'After you spawn on a new server, WAIT this long for the join lag-spike to pass BEFORE casting shift / starting the farm. Farming (teleporting) during the spike gets you kicked, so keep this at a few seconds.',
})

-- Visuals: hide overhead nameplates (VV NameTagUI) --------------------------
EspBox:AddDivider()
EspBox:AddToggle('HideNames', {
    Text = 'Hide overhead names', Default = false,
    Tooltip = 'Hide VV player nameplates (NameTagUI). LOCAL VIEW ONLY - hiding yours does not hide it from other players, only on your screen.',
})
EspBox:AddDropdown('HideNameScope', {
    Values = { 'Mine', 'Others', 'All' },
    Default = 1, Multi = false, Text = 'Hide whose name',
    Tooltip = 'Mine = just your nameplate (your screen). Others = everyone else (declutter). All = everyone.',
})

-- Spectate: click a leaderboard name to view their POV ------------------------
local stopSpectate, specSelected, specCycle -- forward-declared for the buttons
local SpecBox = Tabs.Visuals:AddLeftGroupbox('Spectate')
SpecBox:AddLabel('Click a name in the in-game leaderboard\n(top-right) to view their POV, or pick below.', true)
local SpectateLabel = SpecBox:AddLabel('Spectating: nobody')
SpecBox:AddToggle('ClickSpectate', {
    Text = 'Click leaderboard to spectate', Default = true,
    Tooltip = 'Click a player row in the in-game leaderboard to snap your camera onto them.',
})
SpecBox:AddDropdown('SpectateTarget', {
    SpecialType = 'Player', Values = {}, AllowNull = true, Text = 'Player',
    Tooltip = 'Reliable fallback: pick a player, then hit Spectate.',
})
SpecBox:AddButton({ Text = 'Spectate selected', Func = function() if specSelected then specSelected() end end })
    :AddButton({ Text = 'Stop', Func = function() if stopSpectate then stopSpectate() end end })
SpecBox:AddButton({ Text = '< Prev', Func = function() if specCycle then specCycle(-1) end end })
    :AddButton({ Text = 'Next >', Func = function() if specCycle then specCycle(1) end end })

-- Experimental tab ------------------------------------------------------------
local GrabBox = Tabs.Experimental:AddLeftGroupbox('Grab: Void / Fling')
GrabBox:AddLabel('Grab someone with the game\'s OWN grab first -\nwhile you hold them the server gives YOU network\nownership of them, so we can shove them into the\nvoid or fling them and it replicates. Release is\nautomatic (they drop where you left them).', true)
local GrabStatus = GrabBox:AddLabel('Grabbing: nobody')
GrabBox:AddButton({ Text = 'Void grabbed (drop to void)', Func = function() if voidGrabbed then voidGrabbed() end end })
GrabBox:AddLabel('Void key'):AddKeyPicker('VoidGrabKey', {
    Default = 'Z', Mode = 'Toggle', Text = 'Void grabbed',
})
GrabBox:AddButton({ Text = 'Fling grabbed (yeet)', Func = function() if flingGrabbed then flingGrabbed() end end })
GrabBox:AddLabel('Fling key'):AddKeyPicker('FlingGrabKey', {
    Default = 'Y', Mode = 'Toggle', Text = 'Fling grabbed',
})
GrabBox:AddToggle('AutoVoidGrab', {
    Text = 'Auto-void on grab', Default = false,
    Tooltip = 'The instant you grab someone, void them automatically (no key press).',
})
GrabBox:AddSlider('VoidDepth', {
    Text = 'Void depth', Default = 1000, Min = 200, Max = 5000, Rounding = 0, Suffix = ' studs',
    Tooltip = 'How far below the map to shove them. Deeper = surer death, but bigger jump the server might reject.',
})
GrabBox:AddSlider('FlingPower', {
    Text = 'Fling power', Default = 600, Min = 100, Max = 5000, Rounding = 0,
    Tooltip = 'Velocity magnitude of the yeet.',
})

local SelfFlingBox = Tabs.Experimental:AddRightGroupbox('Self Fling (spin)')
SelfFlingBox:AddLabel('Spins YOUR character fast (noclipped) to launch\nyourself / knock nearby players on contact.\nEXPERIMENTAL - RL anti-cheat may knock or kick\nYOU. Use in short bursts, No Fall Damage on.', true)
SelfFlingBox:AddToggle('SelfFling', {
    Text = 'Self fling (spin)', Default = false,
    Tooltip = 'Hold the key (or tick) to spin. Touching others while spinning can knock them around. Can also fling YOU into the void - be ready.',
}):AddKeyPicker('SelfFlingKey', {
    Default = 'P', SyncToggleState = true, Mode = 'Hold', Text = 'Self fling',
})
SelfFlingBox:AddSlider('SpinPower', {
    Text = 'Spin power', Default = 200, Min = 20, Max = 1000, Rounding = 0,
})

-- Auto Gate -> Kill combo -----------------------------------------------------
local ComboGateBox = Tabs.Experimental:AddLeftGroupbox('Auto Gate -> Kill')
ComboGateBox:AddLabel('Pick a target: TP onto them, try to grab them,\ncharge gate mana, cast the gate, and deliver them\nonto the lava kill brick.\n\nHONEST: a gate only CARRIES someone you are\nGRABBING (verified in the dump) - proximity is\nnot enough. So it fires the game\'s grab (Carry),\nwhich only takes if they are KNOCKED, and as a\nbackstop shoves the grabbed victim straight onto\nthe lava (the reliable kill - the gate is just the\nvehicle). Needs the Gate spell in your hotbar.', true)
local ComboStatus = ComboGateBox:AddLabel('Idle')
ComboGateBox:AddDropdown('GateTarget', {
    Values = {}, Default = nil, Multi = false, AllowNull = true, Text = 'Target',
    Tooltip = 'Who to send to the lava. Filled from the players in the server (updates as they join/leave; the Teleport tab\'s "Refresh list" also refreshes it).',
})
ComboGateBox:AddToggle('GateComboShove', {
    Text = 'Send grabbed victim to lava (TPSafe)', Default = true,
    Tooltip = 'The kill: once you have them grabbed, stamp the game\'s TPSafe whitelist on the VICTIM and teleport their HumanoidRootPart onto the lava. You stay put - only they get delivered. Uses grab network-ownership + TPSafe so it is instant and not snapped back.',
})
ComboGateBox:AddToggle('GateComboCastGate', {
    Text = 'Also cast the gate (theatrics)', Default = false,
    Tooltip = 'Optional: also charge mana and cast the real gate mid-combo. OFF by default - the TPSafe victim-drag already does the kill, so the gate cast is not needed.',
})
ComboGateBox:AddSlider('GateManaCost', {
    Text = 'Gate mana cost', Default = 1, Min = 0, Max = 100, Rounding = 0,
    Tooltip = 'Only used if "Also cast the gate" is on. Charge mana up to this before casting (gate costs 1 in the dump).',
})
ComboGateBox:AddButton({ Text = 'Run gate combo', Func = function() if runGateCombo then runGateCombo() end end })
ComboGateBox:AddLabel('Combo key'):AddKeyPicker('GateComboKey', {
    Default = 'O', Mode = 'Toggle', Text = 'Gate combo',
})

-- ============================================================================
-- 5. LOGIC
-- ============================================================================

-- ---- No Fall Damage: drop the client-sided fall-damage remote ---------------
-- Two games, two call styles, so we cover both:
--   * Bleach/VV fires a RemoteEvent named 'TakeDamage' via remote:FireServer()
--     -> caught by the __namecall hook.
--   * Rogue Lineage fires CharacterHandler.Remotes.ApplyFallDamage through a
--     CACHED FireServer (FireServer(remote, dmg)) that bypasses __namecall
--     -> caught by a hookfunction on FireServer.
-- Blocking the report is safe re: RL's "Loser!" trap: the server only places
-- the 'FallCD' cooldown AFTER it receives the damage call, so if we never send
-- it, nothing is created for the trap to catch being removed.
local MenuUnloaded = false
local restoreNamecall  -- un-stacks the __namecall hook on unload
local restoreFire      -- restores the FireServer function hook on unload
local knocking = false -- true only while we fire our OWN ApplyFallDamage (self-knock), so the No Fall Damage hook lets that one call through

local FALL_REMOTES = { TakeDamage = true, ApplyFallDamage = true }
local function isFallBlock(self, method)
    return not knocking
        and method == 'FireServer'
        and Toggles.NoFallDamage and Toggles.NoFallDamage.Value
        and typeof(self) == 'Instance'
        and self.ClassName == 'RemoteEvent'
        and FALL_REMOTES[self.Name] == true
end

-- Client-reported environmental hazards this game trusts the client to report
-- (same family as fall damage - see CharacterHandler/Input.lua). SunBurn(true) =
-- "I stepped into sunlight as a vampire, start burning me"; dropping that start
-- report means the server never applies the burn. We let SunBurn(false) through
-- so an already-running burn can still be cleared. Gated on No Kill Bricks.
local HAZARD_REMOTES = { SunBurn = true }
local function isHazardBlock(self, method, firstArg)
    return method == 'FireServer'
        and Toggles.NoKillBricks and Toggles.NoKillBricks.Value
        and firstArg ~= false          -- drop the "start"; pass the "stop" (false)
        and typeof(self) == 'Instance'
        and self.ClassName == 'RemoteEvent'
        and HAZARD_REMOTES[self.Name] == true
end
do
    local hookmetamethod   = hookmetamethod
    local getnamecallmethod = getnamecallmethod
    local newcclosure      = newcclosure or function(f) return f end
    local checkcaller      = checkcaller or function() return false end

    if hookmetamethod and getnamecallmethod then
        local oldNamecall
        oldNamecall = hookmetamethod(game, '__namecall', newcclosure(function(self, ...)
            if not MenuUnloaded and not checkcaller() and typeof(self) == 'Instance' then
                local method = getnamecallmethod()
                local class = self.ClassName

                -- No Fall Damage (namecall path): drop the self-damage report.
                if isFallBlock(self, method) then return end

                -- No Kill Bricks (namecall path): drop the SunBurn hazard report.
                if isHazardBlock(self, method, (...)) then return end

                -- Attaching to a flying target can briefly drop you, making VV
                -- fire a FallFX packet whose animation interrupts your M1.
                -- Swallow it while Attach to back is on.
                if method == 'FireServer' and class == 'RemoteEvent'
                   and Toggles.AttachBack and Toggles.AttachBack.Value then
                    local a1 = ...
                    if type(a1) == 'table' and a1.Type == 'FallFX' then
                        return
                    end
                end
            end
            return oldNamecall(self, ...)
        end))
        -- Let unload remove our hook layer. Without this, every re-injection
        -- stacks another __namecall wrapper onto the game - they pile up, slow
        -- every namecall, and make Library:Unload()'s UI teardown freeze.
        restoreNamecall = function()
            pcall(function() hookmetamethod(game, '__namecall', oldNamecall) end)
        end
    else
        Library:Notify('Executor lacks hookmetamethod - No Fall Damage may not fully work', 6)
    end

    -- FireServer function hook: catches the cached FireServer(remote, ...)
    -- direct-call style Rogue Lineage uses for ApplyFallDamage, which never goes
    -- through __namecall. Guarded - only installs if the executor exposes it.
    local hookfunction = hookfunction or replaceclosure
    if hookfunction then
        local newcclosure = newcclosure or function(f) return f end
        local fireRef = Instance.new('RemoteEvent').FireServer
        local oldFire
        local ok = pcall(function()
            oldFire = hookfunction(fireRef, newcclosure(function(self, ...)
                if not MenuUnloaded and isFallBlock(self, 'FireServer') then
                    return
                end
                if not MenuUnloaded and isHazardBlock(self, 'FireServer', (...)) then
                    return
                end
                return oldFire(self, ...)
            end))
        end)
        if ok and oldFire then
            restoreFire = function()
                pcall(function() hookfunction(fireRef, oldFire) end)
            end
        end
    end
end

-- ---- No Kill Bricks: neutralize touch-kill map parts locally ----------------
-- The map has instakill surfaces (PITBASE = the void floor, ArdorianKillbrick,
-- plus generic Lava/Trap bricks). We set CanTouch=false on them on OUR client so
-- any client-detected contact can't register, and remember the originals so we
-- can restore them. The SunBurn hazard report is dropped by the hooks above.
-- HONEST LIMIT: a purely server-side Touched kill (the void pit is enforced
-- server-side) can't be cancelled from the client - use Fly to cross a pit.
local restoreKillBricks -- exposed for OnUnload
do
    local KILLBRICK_NAMES = {
        PITBASE = true, ArdorianKillbrick = true, Killbrick = true, KillBrick = true,
        KillPart = true, KillBlock = true, DamageBrick = true, Lava = true,
        Trap = true, Spike = true, Spikes = true,
    }
    local neutralized = setmetatable({}, { __mode = 'k' }) -- [part] = original CanTouch
    local function neutralize(inst)
        if neutralized[inst] == nil and inst:IsA('BasePart') and KILLBRICK_NAMES[inst.Name] then
            neutralized[inst] = inst.CanTouch
            pcall(function() inst.CanTouch = false end)
        end
    end
    local function scanBricks()
        local root = workspace:FindFirstChild('Map') or workspace
        for _, d in ipairs(root:GetDescendants()) do neutralize(d) end
    end
    restoreKillBricks = function()
        for part, orig in pairs(neutralized) do
            if part.Parent then pcall(function() part.CanTouch = orig end) end
            neutralized[part] = nil
        end
    end

    -- Catch kill bricks that stream in while the toggle is on.
    track(workspace.DescendantAdded:Connect(function(d)
        if Toggles.NoKillBricks and Toggles.NoKillBricks.Value then neutralize(d) end
    end))
    if Toggles.NoKillBricks then
        Toggles.NoKillBricks:OnChanged(function()
            if Toggles.NoKillBricks.Value then scanBricks() else restoreKillBricks() end
        end)
    end
end

-- ---- Invisible (LOCAL view only) --------------------------------------------
-- HONEST: under RL's server-authority (FilteringEnabled) a CLIENT setting part
-- Transparency on its own character does NOT replicate to the server / other
-- players - the SAME reason Melee Reach can't resize parts server-side. So this
-- only makes YOU invisible on YOUR screen; others still see you normally. There
-- is no client property write that hides you from them. RL DOES have real
-- (server-replicated) invisibility, but ONLY as OWNED abilities (Stealth /
-- Shadestep / Rift Dive / Reformation): the SERVER fades the character via a
-- ServerScriptService TransparencyModule + a "Transparency" NumberValue in
-- Character.Boosts, which a client CANNOT forge (client-made instances under the
-- server-owned character don't replicate up), so there is no safe client-side
-- shortcut - only legit ability activation. Transparency + LocalTransparency-
-- Modifier are re-asserted each frame (the game re-renders your character), and
-- the originals are restored on toggle-off / unload.
local restoreInvis
do
    local saved = setmetatable({}, { __mode = 'k' }) -- [inst] = original Transparency
    local function hideOne(d)
        if d:IsA('BasePart') or d:IsA('Decal') or d:IsA('Texture') then
            if saved[d] == nil then saved[d] = d.Transparency end
            if d.Transparency ~= 1 then pcall(function() d.Transparency = 1 end) end
            if d:IsA('BasePart') then pcall(function() d.LocalTransparencyModifier = 1 end) end
        end
    end
    local function applyInvis()
        local char = getChar(); if not char then return end
        for _, d in ipairs(char:GetDescendants()) do hideOne(d) end
    end
    restoreInvis = function()
        for inst, orig in pairs(saved) do
            if inst.Parent then
                pcall(function() inst.Transparency = orig end)
                if inst:IsA('BasePart') then pcall(function() inst.LocalTransparencyModifier = 0 end) end
            end
            saved[inst] = nil
        end
    end
    track(RunService.RenderStepped:Connect(function()
        if not (Toggles.Invisible and Toggles.Invisible.Value) then return end
        applyInvis() -- re-assert every frame (new/respawned parts get hidden too)
    end))
    if Toggles.Invisible then
        Toggles.Invisible:OnChanged(function()
            if not Toggles.Invisible.Value then restoreInvis() end
        end)
    end
end

-- ---- Self-knock: report massive fall damage to drop ourselves to 0 HP -------
-- RL fall damage is client-reported (FireServer(CharacterHandler.Remotes.
-- ApplyFallDamage, dmg)), so firing it with overkill instantly knocks us. The
-- `knocking` flag above makes our own No Fall Damage hook pass THIS call through.
selfKnock = function()
    local char = getChar()
    local ch = char and char:FindFirstChild('CharacterHandler')
    local remotes = ch and ch:FindFirstChild('Remotes')
    local remote = remotes and remotes:FindFirstChild('ApplyFallDamage')
    if not remote then
        Library:Notify('ApplyFallDamage remote not found (Rogue Lineage only)', 4)
        return
    end
    local hum = getHumanoid()
    local dmg = (hum and hum.MaxHealth or 1000) * 2 + 500 -- overkill so HP hits 0 -> knocked
    knocking = true
    pcall(function() remote:FireServer(dmg) end)
    knocking = false
    Library:Notify('Knocking self...', 2)
end
if Options.KnockKey then Options.KnockKey:OnClick(function() selfKnock() end) end

-- ---- Server hop -------------------------------------------------------------
-- Scans all public VV servers, joins the lowest-population joinable one, and
-- remembers servers already joined (persisted to file) so it never loops back.
do
    local placeId    = game.PlaceId
    local currentJob = game.JobId
    local FOLDER     = 'GameTestMenu'
    local VISITED    = FOLDER .. '/visited_servers.json'

    local visited = {}
    pcall(function()
        if isfile and isfile(VISITED) then
            visited = HttpServ:JSONDecode(readfile(VISITED)) or {}
        end
    end)
    visited[currentJob] = true -- never pick the server we're already in

    local function saveVisited()
        pcall(function()
            if makefolder and isfolder and not isfolder(FOLDER) then makefolder(FOLDER) end
            if writefile then writefile(VISITED, HttpServ:JSONEncode(visited)) end
        end)
    end

    local function visitedCount()
        local n = 0
        for _ in pairs(visited) do n += 1 end
        return n
    end
    ServerLabel:SetText(('Visited: %d servers'):format(visitedCount() - 1))

    local function httpGet(url)
        local ok, res = pcall(function() return game:HttpGetAsync(url) end)
        if ok and res then return res end
        local req = (syn and syn.request) or http_request or request
        if req then
            local ok2, resp = pcall(req, { Url = url, Method = 'GET' })
            if ok2 and resp and resp.Body then return resp.Body end
        end
        return nil
    end

    serverHop = function()
        Library:Notify('Searching for lowest-population server...', 3)
        local best, bestPlayers, cursor, pages = nil, nil, nil, 0
        repeat
            pages += 1
            local url = ('https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100'):format(placeId)
            if cursor then url = url .. '&cursor=' .. cursor end
            local body = httpGet(url)
            if not body then Library:Notify('Server hop: HTTP request failed', 5); return end
            local ok, data = pcall(function() return HttpServ:JSONDecode(body) end)
            if not ok or not data then Library:Notify('Server hop: bad response', 5); return end
            for _, s in ipairs(data.data or {}) do
                if s.id ~= currentJob and not visited[s.id]
                   and s.playing and s.maxPlayers and s.playing < s.maxPlayers then
                    if not bestPlayers or s.playing < bestPlayers then
                        best, bestPlayers = s.id, s.playing
                    end
                end
            end
            cursor = data.nextPageCursor
        until not cursor or pages >= 12

        if not best then
            Library:Notify('No new joinable server found. Try Clear visited list.', 6)
            return
        end
        visited[best] = true
        saveVisited()
        Library:Notify(('Hopping to a %d-player server...'):format(bestPlayers), 4)
        local ok, err = pcall(function()
            Teleport:TeleportToPlaceInstance(placeId, best, LocalPlayer)
        end)
        if not ok then Library:Notify('Teleport failed: ' .. tostring(err), 6) end
    end

    rejoinServer = function()
        Library:Notify('Rejoining...', 3)
        pcall(function() Teleport:TeleportToPlaceInstance(placeId, currentJob, LocalPlayer) end)
    end

    clearVisited = function()
        visited = { [currentJob] = true }
        saveVisited()
        ServerLabel:SetText('Visited: 0 servers')
        Library:Notify('Cleared visited server list', 3)
    end
end

-- ---- Fly bodymovers ---------------------------------------------------------
local flyVel, flyGyro
local function stopFly()
    if flyVel then flyVel:Destroy(); flyVel = nil end
    if flyGyro then flyGyro:Destroy(); flyGyro = nil end
end
local function startFly()
    local root = getRoot()
    if not root then return end
    stopFly()
    -- Rogue Lineage's CharacterHandler strips BodyMovers not tagged "AllowedBM",
    -- and SEPARATELY destroys any BodyGyro whose P == 90000 while you're alive.
    -- That's exactly why fly died the instant you toggled it mid-life but worked
    -- on respawn (it re-applied before the new character's guard had connected).
    -- Tagging both movers + using a P that isn't 90000 survives the guard head-on.
    -- The tag is harmless in games that don't look for it.
    local CS = game:GetService('CollectionService')

    flyVel = Instance.new('BodyVelocity')
    flyVel.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    flyVel.Velocity = Vector3.zero
    CS:AddTag(flyVel, 'AllowedBM')
    flyVel.Parent = root

    flyGyro = Instance.new('BodyGyro')
    flyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    flyGyro.P = 5e4          -- was 9e4 (== 90000), which RL destroys on sight
    flyGyro.CFrame = root.CFrame
    CS:AddTag(flyGyro, 'AllowedBM')
    flyGyro.Parent = root
end

Toggles.FlyEnabled:OnChanged(function()
    if Toggles.FlyEnabled.Value then startFly() else stopFly() end
end)

-- ---- No Fog -----------------------------------------------------------------
-- VV's LightingManager / WeatherClient re-applies fog on a cycle, so a one-shot
-- set gets overwritten after ~20s. We re-force it on a throttled loop while on,
-- and remember originals (per Atmosphere) so we can restore on disable/unload.
local fogOriginals = {}            -- { saved=bool, FogEnd, FogStart }
local atmoOriginals = {}           -- [Atmosphere] = { Density, Haze, Glare }
local cloudOriginals = {}          -- [Clouds]     = { Enabled, Cover, Density }

local function applyNoFog()
    -- 1) Legacy fog: push the wall past the horizon.
    Lighting.FogEnd = 1e6
    Lighting.FogStart = 1e6
    -- 2) Atmosphere is what gives this game the teal wash - kill the scattering
    --    entirely (Density), plus Haze + Glare so no tint/bloom is left.
    for _, v in ipairs(Lighting:GetDescendants()) do
        if v:IsA('Atmosphere') then
            if atmoOriginals[v] == nil then
                atmoOriginals[v] = { Density = v.Density, Haze = v.Haze, Glare = v.Glare }
            end
            v.Density = 0
            v.Haze = 0
            pcall(function() v.Glare = 0 end)
        end
    end
    -- 3) Volumetric clouds (the dark blob overhead) live under Terrain.
    local terrain = workspace:FindFirstChildOfClass('Terrain')
    local clouds = terrain and terrain:FindFirstChildOfClass('Clouds')
    if clouds then
        if cloudOriginals[clouds] == nil then
            cloudOriginals[clouds] = { Enabled = clouds.Enabled, Cover = clouds.Cover, Density = clouds.Density }
        end
        pcall(function() clouds.Enabled = false; clouds.Cover = 0; clouds.Density = 0 end)
    end
end

local function restoreFog()
    if fogOriginals.saved then
        Lighting.FogEnd = fogOriginals.FogEnd
        Lighting.FogStart = fogOriginals.FogStart
        fogOriginals.saved = false
    end
    for atmo, data in pairs(atmoOriginals) do
        if atmo.Parent then
            atmo.Density = data.Density
            atmo.Haze = data.Haze
            pcall(function() atmo.Glare = data.Glare end)
        end
    end
    table.clear(atmoOriginals)
    for clouds, data in pairs(cloudOriginals) do
        if clouds.Parent then
            pcall(function() clouds.Enabled = data.Enabled; clouds.Cover = data.Cover; clouds.Density = data.Density end)
        end
    end
    table.clear(cloudOriginals)
end

Toggles.NoFog:OnChanged(function()
    if Toggles.NoFog.Value then
        if not fogOriginals.saved then
            fogOriginals.FogEnd = Lighting.FogEnd
            fogOriginals.FogStart = Lighting.FogStart
            fogOriginals.saved = true
        end
        applyNoFog()
    else
        restoreFog()
    end
end)

-- Maintenance loop: re-assert No Fog EVERY frame (RunStepped runs after the
-- game's weather update) so a tween can't creep the haze back even for a frame.
-- It's a handful of property writes over Lighting's few children - cheap.
track(RunService.RenderStepped:Connect(function()
    if not Toggles.NoFog.Value then return end
    applyNoFog()
end))

-- ---- AA gun (anti-cheat) airborne timer -------------------------------------
local airborneTime = 0
local lastAADeath = nil

local function bindDeath(char)
    local hum = char:FindFirstChildOfClass('Humanoid')
    if not hum then return end
    track(hum.Died:Connect(function()
        -- Died after being airborne a while = almost certainly the AA gun.
        if airborneTime > 1 then
            lastAADeath = airborneTime
            Library:Notify(('AA killed you after %.1fs airborne - set Est. AA time below this'):format(airborneTime), 8)
        end
    end))
end

if getChar() then bindDeath(getChar()) end
track(LocalPlayer.CharacterAdded:Connect(function(char)
    airborneTime = 0
    task.wait(0.2)
    bindDeath(char)
end))

local aaLabelAccum = 0
track(RunService.Heartbeat:Connect(function(dt)
    local hum = getHumanoid()
    local airborne = hum and hum.FloorMaterial == Enum.Material.Air
    airborneTime = airborne and (airborneTime + dt) or 0

    local threshold = Options.AAThreshold.Value

    -- Auto-disable fly ~1s early so you drop and the timer resets (checked every frame).
    if Toggles.AAAutoDisableFly.Value and Toggles.FlyEnabled.Value
       and airborneTime >= (threshold - 1) then
        Toggles.FlyEnabled:SetValue(false)
        Library:Notify('Auto-disabled fly to dodge AA gun', 3)
    end

    -- Throttle the label update (SetText triggers a groupbox resize).
    aaLabelAccum += dt
    if aaLabelAccum >= 0.1 then
        aaLabelAccum = 0
        local lastTxt = lastAADeath and (' | last AA @ %.1fs'):format(lastAADeath) or ''
        if airborne then
            local remaining = math.max(0, threshold - airborneTime)
            AATimerLabel:SetText(('Airborne %.1fs | AA in ~%.1fs%s'):format(airborneTime, remaining, lastTxt))
        else
            AATimerLabel:SetText('Grounded' .. lastTxt)
        end
    end
end))

-- ---- Mob ESP (Drawing API) --------------------------------------------------
local espCleanup -- declared here so OnUnload can clear the drawings
local trinketCleanup -- Trinket ESP teardown (highlights + drawings)
do
    if not Drawing then
        Library:Notify('Executor lacks Drawing API - Mob ESP disabled', 6)
    else
        -- Actual mobs spawn in workspace.Alive (a.k.a. Live); interactable NPCs
        -- (Merchant / Doctor / vendors) live in workspace.NPCs; OTHER PLAYERS
        -- also share the Alive folder, so we exclude them here and draw them via
        -- the Players loop instead. We classify by FOLDER (reliable) rather than
        -- guessing from a ProximityPrompt - that guess was tagging the whole NPCs
        -- folder as "mobs" and never scanning the real Alive folder.
        local MOB_FOLDERS = { 'Alive', 'Live', 'Living', 'Mobs', 'Enemies', 'Monsters', 'Entities' }
        local NPC_FOLDERS = { 'NPCs', 'NPC' }

        local function gatherFolderEntities()
            local list = {}
            local function scan(cont, kind)
                for _, m in ipairs(cont:GetChildren()) do
                    if m:IsA('Model') and m ~= getChar() and not Players:GetPlayerFromCharacter(m)
                       and m:FindFirstChildOfClass('Humanoid') then
                        list[#list + 1] = { model = m, kind = kind }
                    end
                end
            end
            local foundAny = false
            for _, name in ipairs(NPC_FOLDERS) do
                local f = workspace:FindFirstChild(name)
                if f then scan(f, 'npc'); foundAny = true end
            end
            for _, name in ipairs(MOB_FOLDERS) do
                local f = workspace:FindFirstChild(name)
                if f then scan(f, 'mob'); foundAny = true end
            end
            -- Fallback (unknown map layout): scan workspace root, guess by prompt.
            if not foundAny then
                for _, m in ipairs(workspace:GetChildren()) do
                    if m:IsA('Model') and m ~= getChar() and not Players:GetPlayerFromCharacter(m)
                       and m:FindFirstChildOfClass('Humanoid') then
                        local kind = m:FindFirstChildWhichIsA('ProximityPrompt', true) and 'npc' or 'mob'
                        list[#list + 1] = { model = m, kind = kind }
                    end
                end
            end
            return list
        end

        local esp = {} -- [model] = { box, name, dist, hpbg, hpfg }
        local nameCache  = setmetatable({}, { __mode = 'k' }) -- model -> resolved name

        local function looksLikeName(s)
            return type(s) == 'string' and s ~= '' and #s <= 40
                and s:match('%a') ~= nil and s:match('^%d+$') == nil and s:find('%%') == nil
        end
        -- Real name from: DisplayName -> model name -> attributes -> StringValues
        -- -> overhead nameplate text. Caches once resolved.
        local debugged = setmetatable({}, { __mode = 'k' })
        local function entityName(model, hum)
            local cached = nameCache[model]
            if cached then return cached end
            local nm
            if hum and looksLikeName(hum.DisplayName) then nm = hum.DisplayName end
            if not nm and looksLikeName(model.Name) then nm = model.Name end
            if not nm then
                for _, key in ipairs({ 'Name', 'DisplayName', 'MobName', 'EnemyName', 'Title' }) do
                    if looksLikeName(model:GetAttribute(key)) then nm = model:GetAttribute(key); break end
                end
            end
            if not nm then
                for _, d in ipairs(model:GetDescendants()) do
                    if d:IsA('StringValue') and looksLikeName(d.Value) then nm = d.Value; break end
                    if (d:IsA('TextLabel') or d:IsA('TextButton')) and looksLikeName(d.Text) then nm = d.Text; break end
                end
            end
            if nm then nameCache[model] = nm; return nm end
            -- Still unknown: optional one-time dump so we can find where the name lives.
            if Toggles.ESPNameDebug and Toggles.ESPNameDebug.Value and not debugged[model] then
                debugged[model] = true
                local labels = {}
                for _, d in ipairs(model:GetDescendants()) do
                    if d:IsA('TextLabel') or d:IsA('TextButton') then labels[#labels + 1] = ('%q'):format(d.Text) end
                end
                print(('[ESP name?] %s | model.Name=%q | display=%q | labels: %s')
                    :format(model:GetFullName(), model.Name, hum and hum.DisplayName or '', table.concat(labels, ', ')))
            end
            return (model.Name ~= '' and model.Name) or 'Mob'
        end

        local function newEsp()
            local function mk(class)
                local d = Drawing.new(class)
                d.Visible = false
                return d
            end
            return {
                box  = mk('Square'),
                name = mk('Text'),
                dist = mk('Text'),
                hp   = mk('Text'),
                hpbg = mk('Square'),
                hpfg = mk('Square'),
            }
        end

        local function hide(o)
            o.box.Visible, o.name.Visible, o.dist.Visible = false, false, false
            o.hp.Visible, o.hpbg.Visible, o.hpfg.Visible = false, false, false
        end

        local function removeEsp(o)
            for _, d in pairs(o) do pcall(function() d:Remove() end) end
        end

        local function update(o, model, cam, maxD, color, name)
            local hum = model:FindFirstChildOfClass('Humanoid')
            local root = model:FindFirstChild('HumanoidRootPart') or model.PrimaryPart
            if not (hum and root and hum.Health > 0) then hide(o); return end

            local dist = (cam.CFrame.Position - root.Position).Magnitude
            if dist > maxD then hide(o); return end

            -- 2D box from the model's 3D bounding box
            local cf, size = model:GetBoundingBox()
            local s = size / 2
            local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
            local inFront = false
            for _, off in ipairs({
                Vector3.new(-s.X, -s.Y, -s.Z), Vector3.new(-s.X, -s.Y, s.Z),
                Vector3.new(-s.X,  s.Y, -s.Z), Vector3.new(-s.X,  s.Y, s.Z),
                Vector3.new( s.X, -s.Y, -s.Z), Vector3.new( s.X, -s.Y, s.Z),
                Vector3.new( s.X,  s.Y, -s.Z), Vector3.new( s.X,  s.Y, s.Z),
            }) do
                local v = cam:WorldToViewportPoint((cf * CFrame.new(off)).Position)
                if v.Z > 0 then inFront = true end
                minX, minY = math.min(minX, v.X), math.min(minY, v.Y)
                maxX, maxY = math.max(maxX, v.X), math.max(maxY, v.Y)
            end
            if not inFront then hide(o); return end

            local w, h = maxX - minX, maxY - minY

            -- Box
            o.box.Visible = Toggles.ESPBoxes.Value
            o.box.Color, o.box.Thickness, o.box.Filled = color, 1, false
            o.box.Position, o.box.Size = Vector2.new(minX, minY), Vector2.new(w, h)

            -- Name
            o.name.Visible = Toggles.ESPNames.Value
            o.name.Text = ((name or entityName(model, hum)):gsub('^%.+', '')) -- strip leading '.' (mob names)
            o.name.Color, o.name.Size, o.name.Center, o.name.Outline = color, 13, true, true
            o.name.Position = Vector2.new(minX + w / 2, minY - 16)

            -- Distance
            o.dist.Visible = Toggles.ESPDistance.Value
            o.dist.Text = ('%.0f studs'):format(dist)
            o.dist.Color, o.dist.Size, o.dist.Center, o.dist.Outline =
                Color3.new(1, 1, 1), 12, true, true
            o.dist.Position = Vector2.new(minX + w / 2, maxY + 2)

            -- Health bar (left of box)
            local frac = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
            o.hpbg.Visible = Toggles.ESPHealth.Value
            o.hpbg.Color, o.hpbg.Filled = Color3.new(0, 0, 0), true
            o.hpbg.Position, o.hpbg.Size = Vector2.new(minX - 5, minY), Vector2.new(2, h)
            o.hpfg.Visible = Toggles.ESPHealth.Value
            o.hpfg.Color = Color3.fromRGB(0, 255, 0):Lerp(Color3.fromRGB(255, 0, 0), 1 - frac)
            o.hpfg.Filled = true
            o.hpfg.Position = Vector2.new(minX - 5, minY + h * (1 - frac))
            o.hpfg.Size = Vector2.new(2, h * frac)

            -- HP number (the thing you actually want to read), coloured by fraction
            o.hp.Visible = Toggles.ESPHP and Toggles.ESPHP.Value or false
            o.hp.Text = ('%d / %d'):format(math.floor(hum.Health + 0.5), math.floor(hum.MaxHealth + 0.5))
            o.hp.Color = Color3.fromRGB(0, 255, 0):Lerp(Color3.fromRGB(255, 0, 0), 1 - frac)
            o.hp.Size, o.hp.Center, o.hp.Outline = 13, true, true
            o.hp.Position = Vector2.new(minX + w / 2, maxY + 16)
        end

        -- Mobs/NPCs (by folder) + other players. Players carry their real name.
        local function getEntities()
            local list = gatherFolderEntities()
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and p.Character then
                    list[#list + 1] = { model = p.Character, kind = 'player', name = p.DisplayName }
                end
            end
            return list
        end

        -- Proximity: ding on entry + on-screen nearby list -------------------
        local SoundService = game:GetService('SoundService')
        local proxInRange = {}
        local proxTexts = {}
        for i = 1, 12 do
            local t = Drawing.new('Text')
            t.Visible, t.Size, t.Outline, t.Center = false, 14, true, false
            t.Color = Color3.new(1, 1, 1)
            proxTexts[i] = t
        end
        local function clearProxList() for _, t in ipairs(proxTexts) do t.Visible = false end end
        local function playDing()
            local s = Instance.new('Sound')
            s.SoundId = 'rbxasset://sounds/electronicpingshort.wav'
            s.Volume = 1
            pcall(function() SoundService:PlayLocalSound(s) end)
        end
        local function handleProximity(nearby)
            local nowIn = {}
            for _, n in ipairs(nearby) do nowIn[n.key] = true end
            if Toggles.ProxAlert.Value then
                for _, n in ipairs(nearby) do
                    if not proxInRange[n.key] then playDing() end -- ding only on new entry
                end
            end
            proxInRange = nowIn
            if Toggles.ProxList.Value then
                table.sort(nearby, function(a, b) return a.dist < b.dist end)
                for i = 1, #proxTexts do
                    local t, n = proxTexts[i], nearby[i]
                    if n then
                        t.Visible = true
                        t.Text = ('%s  -  %.0f studs'):format(n.name, n.dist)
                        t.Position = Vector2.new(14, 160 + (i - 1) * 16)
                    else
                        t.Visible = false
                    end
                end
            else
                clearProxList()
            end
        end

        track(RunService.RenderStepped:Connect(function()
            local showMob = Toggles.MobESP.Value
            local showNpc = Toggles.NPCESP.Value
            local showPlr = Toggles.PlayerESP.Value
            local proxOn  = Toggles.ProxAlert.Value or Toggles.ProxList.Value
            if not (showMob or showNpc or showPlr or proxOn) then
                for _, o in pairs(esp) do hide(o) end
                clearProxList()
                return
            end
            local cam = workspace.CurrentCamera
            local maxD = Options.ESPMaxDistance.Value
            local maxMobD = Options.MobMaxDistance and Options.MobMaxDistance.Value or maxD
            local colorOf = { mob = Options.ESPColor.Value, npc = Options.NPCColor.Value, player = Options.PlayerColor.Value }
            local myRoot = getRoot()
            local proxRange, includeMobs = Options.ProxRange.Value, Toggles.ProxIncludeMobs.Value

            local seen, nearby = {}, {}
            for _, e in ipairs(getEntities()) do
                local model, kind = e.model, e.kind
                local hum = model:FindFirstChildOfClass('Humanoid')
                local root = model:FindFirstChild('HumanoidRootPart') or model.PrimaryPart
                local nm = e.name or entityName(model, hum)
                -- Mob model names look like ".Zombie Scroom2288" - drop the leading
                -- dot AND the trailing spawn number so the label reads clean.
                if kind == 'mob' then nm = (nm:gsub('^%.+', ''):gsub('%s*%d+$', '')) end

                if (kind == 'mob' and showMob) or (kind == 'npc' and showNpc) or (kind == 'player' and showPlr) then
                    seen[model] = true
                    local o = esp[model]
                    if not o then o = newEsp(); esp[model] = o end
                    update(o, model, cam, (kind == 'mob') and maxMobD or maxD, colorOf[kind], nm)
                end

                if proxOn and root and myRoot and (kind == 'player' or includeMobs) then
                    local d = (myRoot.Position - root.Position).Magnitude
                    if d <= proxRange then nearby[#nearby + 1] = { name = nm, dist = d, key = model } end
                end
            end
            for model, o in pairs(esp) do
                if not seen[model] or not model.Parent then
                    removeEsp(o); esp[model] = nil
                end
            end
            handleProximity(nearby)
        end))

        espCleanup = function()
            for model, o in pairs(esp) do removeEsp(o); esp[model] = nil end
            for _, t in ipairs(proxTexts) do pcall(function() t:Remove() end) end
        end
    end
end

-- ---- Trinket ESP ------------------------------------------------------------
-- This game stores lootable trinkets in the workspace.Trinkets FOLDER (each a
-- BasePart with a ClickPart + SpecialMesh/Particle; no 'ID' child). They are NOT
-- named, so we identify each by its mesh / colour / particle via trinketType().
-- A through-walls Highlight shows them behind terrain; a Drawing label (name +
-- distance) pins to the screen edge when off-screen. Coloured per trinket type.
-- To update identification, edit trinketType() - it mirrors your TrinketTypeLib.
local function trinketType(Object)
    local UNKNOWN = { Color = Color3.fromRGB(255, 255, 255), Name = 'Unknown' }
    if not Object:IsA('BasePart') then return UNKNOWN end
    local Light    = Object:FindFirstChildOfClass('PointLight')
    local Mesh     = Object:FindFirstChildOfClass('SpecialMesh')
    local Particle = Object:FindFirstChildOfClass('ParticleEmitter')
    -- mesh id from a MeshPart directly, OR from a SpecialMesh child (this game
    -- uses Part + SpecialMesh instead of MeshPart).
    local meshId   = (Object:IsA('MeshPart') and Object.MeshId) or (Mesh and Mesh.MeshId) or nil
    local color    = Object.Color
    local GOLD, BLUE, PINK = Color3.fromRGB(255, 213, 128), Color3.fromRGB(137, 207, 240), Color3.fromRGB(255, 0, 255)

    -- Mesh-ID trinkets
    local MESHES = {
        ['rbxassetid://5196551436'] = { GOLD, 'Amulet' },
        ['rbxassetid://923469333']  = { GOLD, 'Candy' },
        ['rbxassetid://5204003946'] = { GOLD, 'Goblet' },
        ['rbxassetid://2520762076'] = { BLUE, 'Howler Friend' },
        ['rbxassetid://5196577540'] = { GOLD, 'Old Amulet' },
        ['rbxassetid://5196782997'] = { GOLD, 'Old Ring' },
        ['rbxassetid://5196776695'] = { GOLD, 'Ring' },
        ['rbxassetid://5204453430'] = { BLUE, 'Scroll' },
    }
    if meshId and MESHES[meshId] then
        return { Color = MESHES[meshId][1], Name = MESHES[meshId][2] }
    end

    -- Union-specific (PointLight colour / UsePartColor)
    if Object:IsA('UnionOperation') then
        if Light and Light.Color == Color3.fromRGB(255, 255, 255) then return { Color = PINK, Name = 'Amulet of the White King' } end
        if color == Color3.fromRGB(111, 113, 125) then return { Color = GOLD, Name = 'Idol of the Forgotten' } end
        if color == Color3.fromRGB(248, 248, 248) and not Object.UsePartColor then return { Color = PINK, Name = [[Lannis's Amulet]] } end
        if color == Color3.fromRGB(29, 46, 58) then return { Color = PINK, Name = 'Night Stone' } end
        if color == Color3.fromRGB(255, 89, 89) then return { Color = PINK, Name = [[Philosopher's Stone]] } end
        if color == Color3.fromRGB(248, 217, 109) then return { Color = PINK, Name = 'Scroom Key' } end
    end

    -- Colour + particle (original TrinketTypeLib Part-branch order, now applied
    -- to any BasePart so it works regardless of Part/MeshPart class).
    local pk = Particle and Particle.Color.Keypoints[1].Value or nil
    if color == Color3.fromRGB(89, 34, 89) then return { Color = BLUE, Name = '???' }
    elseif color == Color3.fromRGB(164, 187, 190) then return { Color = BLUE, Name = 'Diamond' }
    elseif color == Color3.fromRGB(0, 184, 49) then return { Color = BLUE, Name = 'Emerald' }
    elseif color == Color3.fromRGB(128, 187, 219) then return { Color = PINK, Name = 'Fairfrozen' }
    elseif Particle and Particle.Color == Color3.fromRGB(25, 185, 155) then return { Color = BLUE, Name = 'Ice Essence' }
    elseif pk == Color3.new(0.45098, 1, 0) then return { Color = GOLD, Name = 'Mysterious Artifact' }
    elseif color == Color3.fromRGB(248, 248, 248) and Mesh then return { Color = GOLD, Name = 'Opal' }
    elseif pk == Color3.new(1, 0.8, 0) then return { Color = BLUE, Name = 'Phoenix Down' }
    elseif color == Color3.fromRGB(255, 0, 191) then return { Color = PINK, Name = 'Rift Gem' }
    elseif color == Color3.fromRGB(255, 0, 0) then return { Color = BLUE, Name = 'Ruby' }
    elseif color == Color3.fromRGB(16, 42, 220) then return { Color = BLUE, Name = 'Sapphire' }
    elseif color == Color3.fromRGB(255, 255, 0) then return { Color = PINK, Name = 'Spider Cloak' }
    end

    return UNKNOWN
end

do
    -- This game keeps trinkets in workspace.Trinkets - each is a BasePart with a
    -- ClickPart + SpecialMesh/Particle, NOT a direct workspace child and with no
    -- 'ID' child. So every part in that folder IS a trinket.
    -- The folder holding trinkets is named "Dinkets" in this game (not
    -- "Trinkets"), and it may be nested, so we search recursively and accept
    -- either name. A plain workspace:FindFirstChild('Trinkets') only checks
    -- direct children AND the wrong name - which is why nothing showed.
    local TRINKET_FOLDER_NAMES = { Dinkets = true, Trinkets = true }
    local cachedFolder
    local function trinketsFolder()
        if cachedFolder and cachedFolder.Parent then return cachedFolder end
        cachedFolder = nil
        for _, d in ipairs(workspace:GetDescendants()) do
            if (d:IsA('Folder') or d:IsA('Model')) and TRINKET_FOLDER_NAMES[d.Name] then cachedFolder = d; return d end
        end
        return nil
    end
    local function inTrinketFolder(d)
        local f = d.Parent
        return f ~= nil and TRINKET_FOLDER_NAMES[f.Name] == true
    end
    local function anchorOf(obj)
        if obj:IsA('BasePart') then return obj end
        return obj.PrimaryPart or obj:FindFirstChildWhichIsA('BasePart')
    end

    local tracked = {} -- [obj] = { name, color, hl, label, tracer }
    local function makeVisual(obj)
        local ok, info = pcall(trinketType, anchorOf(obj) or obj)
        if not (ok and type(info) == 'table') then info = { Name = 'Unknown', Color = Color3.new(1, 1, 1) } end
        local v = { name = info.Name or 'Unknown', color = info.Color or Color3.new(1, 1, 1) }
        pcall(function()
            local hl = Instance.new('Highlight')
            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            hl.FillTransparency = 0.5
            hl.OutlineTransparency = 0
            hl.FillColor, hl.OutlineColor = v.color, v.color
            hl.Enabled = false
            hl.Adornee = obj:IsA('Model') and obj or anchorOf(obj)
            hl.Parent = obj
            v.hl = hl
        end)
        if Drawing then
            v.label = Drawing.new('Text')
            v.label.Center, v.label.Outline, v.label.Size, v.label.Visible = true, true, 14, false
            v.tracer = Drawing.new('Line')
            v.tracer.Thickness, v.tracer.Visible = 1, false
        end
        tracked[obj] = v
    end
    local function removeVisual(obj)
        local v = tracked[obj]; if not v then return end
        if v.hl then pcall(function() v.hl:Destroy() end) end
        if v.label then pcall(function() v.label:Remove() end) end
        if v.tracer then pcall(function() v.tracer:Remove() end) end
        tracked[obj] = nil
    end
    local function scanAll()
        local folder = trinketsFolder()
        if not folder then return nil end
        for _, d in ipairs(folder:GetChildren()) do
            if not tracked[d] and anchorOf(d) then makeVisual(d) end
        end
        return folder
    end

    -- Catch trinkets that spawn / stream into the Trinkets folder while on.
    -- Deferred so the mesh/particle/colour have a frame to replicate first.
    track(workspace.DescendantAdded:Connect(function(d)
        if not (Toggles.TrinketESP and Toggles.TrinketESP.Value) then return end
        if inTrinketFolder(d) and not tracked[d] then
            task.defer(function()
                if d.Parent and inTrinketFolder(d) and not tracked[d] and anchorOf(d) then makeVisual(d) end
            end)
        end
    end))

    if Toggles.TrinketESP then
        Toggles.TrinketESP:OnChanged(function()
            if Toggles.TrinketESP.Value then
                local folder = scanAll()
                local n = 0; for _ in pairs(tracked) do n += 1 end
                if not folder then
                    Library:Notify('Trinket ESP: no Dinkets/Trinkets folder found in workspace', 4)
                else
                    Library:Notify(('Trinket ESP: tracking %d trinket(s) in "%s"'):format(n, folder.Name), 3)
                end
            else
                for obj in pairs(tracked) do removeVisual(obj) end
            end
        end)
    end

    local rescanAccum = 0
    track(RunService.RenderStepped:Connect(function(dt)
        if not (Toggles.TrinketESP and Toggles.TrinketESP.Value) then return end
        rescanAccum += dt
        if rescanAccum >= 4 then rescanAccum = 0; scanAll() end -- safety re-sweep

        local cam = workspace.CurrentCamera
        local vp = cam.ViewportSize
        local myRoot = getRoot()
        local maxD = Options.TrinketMaxDist.Value
        local showHL = Toggles.TrinketHighlight.Value
        local showName, showDist = Toggles.TrinketNames.Value, Toggles.TrinketDistance.Value
        local showTracer = Toggles.TrinketTracer.Value
        local hideUnknown = Toggles.TrinketHideUnknown.Value
        local filter = Options.TrinketFilter and Options.TrinketFilter.Value
        local filterActive = filter and next(filter) ~= nil -- nothing ticked = show all

        for obj, v in pairs(tracked) do
            local part = obj.Parent and anchorOf(obj)
            if not part or (hideUnknown and v.name == 'Unknown')
               or (filterActive and not filter[v.name]) then
                if v.hl then v.hl.Enabled = false end
                if v.label then v.label.Visible = false end
                if v.tracer then v.tracer.Visible = false end
                if not part then removeVisual(obj) end
            else
                local pos = part.Position
                local dist = myRoot and (myRoot.Position - pos).Magnitude or 0
                if dist > maxD then
                    if v.hl then v.hl.Enabled = false end
                    if v.label then v.label.Visible = false end
                    if v.tracer then v.tracer.Visible = false end
                else
                    if v.hl then v.hl.Enabled = showHL end
                    local sp = cam:WorldToViewportPoint(pos)
                    local inFront = sp.Z > 0
                    if v.label and (showName or showDist) then
                        local x, y = sp.X, sp.Y
                        if not inFront then x = vp.X - x; y = vp.Y - y end -- behind cam -> mirror to edge
                        x = math.clamp(x, 28, vp.X - 28)
                        y = math.clamp(y, 40, vp.Y - 40)
                        local txt = showName and v.name or ''
                        if showDist then txt = (txt ~= '' and txt .. '  ' or '') .. ('[%.0f]'):format(dist) end
                        v.label.Text, v.label.Color, v.label.Position, v.label.Visible = txt, v.color, Vector2.new(x, y), true
                    elseif v.label then v.label.Visible = false end
                    if v.tracer then
                        if showTracer and inFront then
                            v.tracer.Color = v.color
                            v.tracer.From = Vector2.new(vp.X / 2, vp.Y)
                            v.tracer.To = Vector2.new(sp.X, sp.Y)
                            v.tracer.Visible = true
                        else v.tracer.Visible = false end
                    end
                end
            end
        end
    end))

    trinketCleanup = function()
        for obj in pairs(tracked) do removeVisual(obj) end
    end
end

-- ---- Spectate ---------------------------------------------------------------
-- Click a player row in the in-game leaderboard (or pick from the dropdown) to
-- snap your camera onto them. Pure camera work (Camera.CameraSubject) - no
-- remotes, no GUI tampering: we only READ the leaderboard's row labels and map
-- each back to its player via their leaderstatsfake first/last name, so the
-- "banned" tamper trap (which only fires if the leaderboard is deleted) is safe.
do
    local spectating = nil -- Player we're viewing
    local function setLabel()
        if SpectateLabel then
            SpectateLabel:SetText('Spectating: ' .. (spectating and spectating.Name or 'nobody'))
        end
    end
    stopSpectate = function()
        spectating = nil
        local h = getHumanoid()
        if h then
            workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
            workspace.CurrentCamera.CameraSubject = h
        end
        setLabel()
    end
    local function spectate(p)
        if not p or p == LocalPlayer then stopSpectate(); return end
        local char = p.Character
        local hum = char and char:FindFirstChildOfClass('Humanoid')
        if not hum then Library:Notify(p.Name .. ' is not spawned', 2); return end
        spectating = p
        workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
        workspace.CurrentCamera.CameraSubject = hum
        setLabel()
        Library:Notify('Spectating ' .. p.Name, 2)
    end
    specSelected = function()
        local name = Options.SpectateTarget.Value
        if not name or name == '' then Library:Notify('Pick a player first', 2); return end
        local p = Players:FindFirstChild(name)
        if not p then
            for _, pl in ipairs(Players:GetPlayers()) do if pl.DisplayName == name then p = pl; break end end
        end
        if p then spectate(p) else Library:Notify('Player not found', 2) end
    end
    specCycle = function(dir)
        local list = {}
        for _, p in ipairs(Players:GetPlayers()) do if p ~= LocalPlayer then list[#list + 1] = p end end
        if #list == 0 then return end
        table.sort(list, function(a, b) return a.Name < b.Name end)
        local idx = 0
        for i, p in ipairs(list) do if p == spectating then idx = i; break end end
        idx = idx + (dir >= 0 and 1 or -1)
        if idx < 1 then idx = #list elseif idx > #list then idx = 1 end
        spectate(list[idx])
    end

    -- Keep the camera on the target through respawns; drop it if they leave.
    track(RunService.Heartbeat:Connect(function()
        if not spectating then return end
        if not spectating.Parent then stopSpectate(); return end
        local char = spectating.Character
        local hum = char and char:FindFirstChildOfClass('Humanoid')
        if hum and workspace.CurrentCamera.CameraSubject ~= hum then
            workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
            workspace.CurrentCamera.CameraSubject = hum
        end
    end))
    -- On OUR respawn, restore our own camera unless we're actively spectating.
    track(LocalPlayer.CharacterAdded:Connect(function()
        if not spectating then
            task.wait(0.3)
            local h = getHumanoid()
            if h then workspace.CurrentCamera.CameraSubject = h end
        end
    end))

    -- Map a leaderboard row's text back to a player via their leaderstatsfake name.
    local function playerFromText(text)
        -- On MouseEnter the game swaps the row text from the RP name to the raw
        -- USERNAME with a zero-width ‎ mark injected after the 2nd char (see
        -- LeaderboardClient) - and you're always hovering when you click. Strip
        -- that mark + padding and match the username first, RP name as fallback.
        local clean = tostring(text):gsub('\226\128\142', ''):gsub('%s+', ' ')
        clean = clean:match('^%s*(.-)%s*$') or clean
        local low = clean:lower()
        if low == '' then return nil end
        -- 1) username / display name (what the row shows while hovered)
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and (low == p.Name:lower() or low == p.DisplayName:lower()) then
                return p
            end
        end
        -- 2) leaderstatsfake first/last name (row's un-hovered RP text)
        for _, p in ipairs(Players:GetPlayers()) do
            local ls = p:FindFirstChild('leaderstatsfake')
            if ls then
                local fnv, lnv = ls:FindFirstChild('FirstName'), ls:FindFirstChild('LastName')
                local fn = fnv and tostring(fnv.Value):lower() or ''
                local ln = lnv and tostring(lnv.Value):lower() or ''
                if fn ~= '' and low:find(fn, 1, true) and (ln == '' or low:find(ln, 1, true)) then
                    return p
                end
            end
        end
        return nil
    end
    -- Connect click detection to each leaderboard row label (read-only).
    local hooked = setmetatable({}, { __mode = 'k' })
    local function hookLeaderboard()
        local pg = LocalPlayer:FindFirstChild('PlayerGui')
        local lb = pg and pg:FindFirstChild('LeaderboardGui')
        if not lb then return end
        for _, d in ipairs(lb:GetDescendants()) do
            if (d:IsA('TextLabel') or d:IsA('TextButton')) and not hooked[d] then
                hooked[d] = true
                track(d.InputBegan:Connect(function(input)
                    if not (Toggles.ClickSpectate and Toggles.ClickSpectate.Value) then return end
                    if input.UserInputType ~= Enum.UserInputType.MouseButton1
                       and input.UserInputType ~= Enum.UserInputType.Touch then return end
                    local p = playerFromText(d.Text)
                    if p then
                        -- Click the name you're already watching = stop spectating.
                        if p == spectating then stopSpectate() else spectate(p) end
                    end
                end))
            end
        end
    end
    hookLeaderboard()
    local rehookAccum = 0
    track(RunService.Heartbeat:Connect(function(dt)
        rehookAccum += dt
        if rehookAccum >= 1 then rehookAccum = 0; hookLeaderboard() end
    end))

    setLabel()
end

-- ---- Hide overhead nameplates (VV NameTagUI) --------------------------------
-- VV's OverheadManager skips players; their overhead name is TitleManager's
-- custom NameTagUI (CollectionService tag "NameTagUI"). We hide those on our
-- client. NOTE: this only affects OUR screen - other players still render your
-- name from replicated data; there is no client-controllable "hidden" flag.
do
    local CollectionService = game:GetService('CollectionService')
    local hiddenTags = setmetatable({}, { __mode = 'k' }) -- gui we hid

    -- Returns (isMine, isPlayerNametag) by climbing to the owning character.
    local function tagOwner(gui)
        local node = gui.Parent
        while node and node ~= game do
            if node:IsA('Model') then
                local p = Players:GetPlayerFromCharacter(node)
                if p then return p == LocalPlayer, true end
            end
            node = node.Parent
        end
        return false, false
    end
    local function setShown(gui, shown)
        pcall(function()
            if gui:IsA('LayerCollector') then gui.Enabled = shown      -- BillboardGui / etc.
            elseif gui:IsA('GuiObject') then gui.Visible = shown end
        end)
    end
    local function refreshNames()
        local on = Toggles.HideNames and Toggles.HideNames.Value
        local scope = (Options.HideNameScope and Options.HideNameScope.Value) or 'Mine'
        for _, gui in ipairs(CollectionService:GetTagged('NameTagUI')) do
            local mine, isPlayer = tagOwner(gui)
            local hide = on and isPlayer and (scope == 'All'
                or (scope == 'Mine' and mine)
                or (scope == 'Others' and not mine))
            if hide then
                hiddenTags[gui] = true
                setShown(gui, false)
            elseif hiddenTags[gui] then
                hiddenTags[gui] = nil
                setShown(gui, true)
            end
        end
    end
    if Toggles.HideNames then Toggles.HideNames:OnChanged(refreshNames) end
    if Options.HideNameScope then Options.HideNameScope:OnChanged(refreshNames) end
    -- Re-apply ~3x/sec so new/respawned nametags get hidden too.
    local nameAccum = 0
    track(RunService.Heartbeat:Connect(function(dt)
        nameAccum += dt
        if nameAccum < 0.3 then return end
        nameAccum = 0
        if (Toggles.HideNames and Toggles.HideNames.Value) or next(hiddenTags) then refreshNames() end
    end))
end

-- ---- Combat: parry action ---------------------------------------------------
-- Attack animation IDs that should trigger a parry. Fill these in from the
-- Animation Logger output (copy the rbxassetid:// string for each enemy attack).
-- Curated from RemoteSpy anim logs. These are the SHORT, non-looping swing
-- candidates. The 5.00s / 8.53s looping IDs were excluded (idle/walk loops),
-- as were the sub-0.3s effect stubs. Prune anything that false-triggers.
local ATTACK_ANIMS = {
    -- Scorpion Hollow attacks
    ['rbxassetid://17188146433'] = true,  -- 1.60s (fires often = likely M1)
    ['rbxassetid://17188382622'] = true,  -- 1.83s
    ['rbxassetid://17188386684'] = true,  -- 1.95s
    ['rbxassetid://17188670401'] = true,  -- 2.07s
    ['rbxassetid://17188289743'] = true,  -- 2.97s
    ['rbxassetid://18989204838'] = true,  -- 3.00s
    ['rbxassetid://17188155225'] = true,  -- 3.13s

    -- Player (WOLF_ELECTRO) attacks
    ['rbxassetid://18998838518'] = true,  -- 1.75s
    ['rbxassetid://18958401014'] = true,  -- 1.65s
    ['rbxassetid://18958341833'] = true,  -- 2.47s
    ['rbxassetid://18958397073'] = true,  -- 1.65s
    ['rbxassetid://16417788544'] = true,  -- 0.78s (M1 combo swings)
    ['rbxassetid://16417792446'] = true,  -- 0.93s
    ['rbxassetid://16417798771'] = true,  -- 0.92s
    ['rbxassetid://16417803802'] = true,  -- 0.93s
}

-- ===== HAND-MEASURED PARRY TIMINGS (Aztup-style database) ===================
-- The reliable path. Parry an attack manually, read the time the Parry Trainer
-- prints, and hardcode it here keyed by the NUMERIC anim id (no rbxassetid://):
--   [id] = seconds        -> single parry, that many seconds into the anim
--   [id] = { 0.3, 0.7 }   -> multi-hit combo: one parry per listed time
-- These OVERRIDE runtime-learned timings when Timing = 'Learned (trained)', and
-- are seeded into ATTACK_ANIMS below so 'Database (IDs)' mode treats them as
-- known attacks. Fill this from the 'Dump timings (DB)' button output.
local MANUAL_TIMINGS = {
    -- ['17188146433'] = 0.46,
    -- ['18958341833'] = { 0.30, 0.70 },
}

-- Numeric id from a full AnimationId ('rbxassetid://123' -> '123').
local function animNum(animId)
    return type(animId) == 'string' and animId:match('%d+') or nil
end

-- Seed the known-attack set so measured attacks count as 'known' in DB mode.
for num in pairs(MANUAL_TIMINGS) do
    ATTACK_ANIMS['rbxassetid://' .. num] = true
end

-- ===== PARRY + FEINT SOUND IDS ===============================================
-- Numeric SoundId(s) the game plays on a SUCCESSFUL parry, and the ones a mob
-- plays when it FEINTS (cancels a windup to bait your parry). Found with the
-- Sound Logger (Combat tab); numeric, no rbxassetid://. Parry sounds confirm
-- parries + self-train timings; feint sounds cancel the pending parry.
local PARRY_SOUNDS = {
    -- "MetalDeflect3" - the clang of a SUCCESSFUL deflect/parry. Reliable success
    -- marker (it fired together with ParryAttempt on a real parry).
    ['139820161644863'] = true,
    -- ['90455183009158'] = true, -- "ParryAttempt": plays when you TRY a parry;
    --   likely fires on MISTIMED attempts too, so it false-confirms. Enable only
    --   if MetalDeflect proves unreliable.
    -- ['108027087532477'] = true, -- earlier guess; never observed firing
}
local FEINT_SOUNDS = {
    ['4840035902'] = true,      -- mob feint (bait) - skip the parry
}

-- ===== SOURCE-ACCURATE ATTACK DB (built live from VV's own game data) ========
-- Instead of guessing/training, read VV's real combat data at load: walk
-- SharedAssets.Animations.WeaponAnimations, classify each anim by its name
-- (<Weapon>Light#, <Weapon>Heavy#, <Mob>Attack_#), and pull the EXACT hit
-- timestamp from SharedAssets.Info.WeaponStats (LightAttackTimestamp /
-- HeavyTimestamp). Frame-accurate, and self-updates if VV patches.
--   SOURCE_DB[animId] = { kind = 'Light'/'Heavy'/'Mob', weapon, t = seconds|nil }
-- This also fixes false parries: walk/idle/strafe/block/deflect anims simply
-- aren't in here, so they can never be treated as attacks.
local SOURCE_DB = {}
local sourceDBCount, sourceTimedCount = 0, 0
local function buildSourceDB()
    table.clear(SOURCE_DB)
    local n, timed = 0, 0
    local sa = RepStorage:FindFirstChild('SharedAssets')
    local animsFolder = sa and sa:FindFirstChild('Animations')
    local info = sa and sa:FindFirstChild('Info')
    local statsFolder = info and info:FindFirstChild('WeaponStats')
    if not animsFolder then return 0, 0 end

    local statCache = {}
    local function weaponInfo(weapon)
        local c = statCache[weapon]
        if c ~= nil then return c or nil end
        local m = statsFolder and statsFolder:FindFirstChild(weapon)
        if not m and weapon:find('Hollow') then -- hollows share HollowCombat stats
            m = statsFolder and statsFolder:FindFirstChild('HollowCombat')
        end
        local wi = false
        if m then
            local ok, mod = pcall(require, m)
            if ok and type(mod) == 'table' and type(mod.weaponInfo) == 'table' then wi = mod.weaponInfo end
        end
        statCache[weapon] = wi
        return wi or nil
    end

    local function classify(name)
        local w = name:match('^(%a+)Light%d+%a*$'); if w then return w, 'Light' end
        w = name:match('^(%a+)Heavy%d+%a*$'); if w then return w, 'Heavy' end
        w = name:match('^(%a+)Attack_?%d+$'); if w then return w, 'Mob' end
        return nil
    end

    for _, d in ipairs(animsFolder:GetDescendants()) do
        if d:IsA('Animation') then
            local weapon, kind = classify(d.Name)
            local id = weapon and d.AnimationId
            if weapon and id and id ~= '' and not SOURCE_DB[id] then
                local t
                if kind ~= 'Mob' then
                    local wi = weaponInfo(weapon)
                    if wi then t = (kind == 'Heavy') and wi.HeavyTimestamp or wi.LightAttackTimestamp end
                end
                SOURCE_DB[id] = { kind = kind, weapon = weapon, t = t }
                n += 1
                if t then timed += 1 end
            end
        end
    end
    return n, timed
end
pcall(function() sourceDBCount, sourceTimedCount = buildSourceDB() end)
if SourceLabel then
    SourceLabel:SetText(('Source DB: %d attacks (%d timed)'):format(sourceDBCount, sourceTimedCount))
end
print(('[AutoParry] Source DB: %d attack anims, %d with exact game-data timings')
    :format(sourceDBCount, sourceTimedCount))

-- Stun animations on YOUR character. With No Stun on, these get cancelled so
-- you can act through hits. Find IDs with the Animation Logger's "Log MY anims".
local STUN_ANIMS = {
    -- ['rbxassetid://0000000000'] = true,
}

-- Attach auto-dodge state (set by the attack detector, read by the attach loop).
local attachTargetModel = nil
local attachDodgeUntil = 0

-- Keyframe/marker names that mean "the attack is connecting now". VV's exact
-- names may differ - use the Animation Logger's "Log markers" to find them and
-- add any extras here. Matching is case-insensitive (see markerIsHit).
local HIT_MARKERS = {
    hit = true, cast = true, swing = true, damage = true, attack = true,
    active = true, hitbox = true, m1 = true, slash = true, contact = true,
}
local function markerIsHit(name)
    return type(name) == 'string' and HIT_MARKERS[name:lower()] == true
end

-- Auto-learned attack DB (persisted). Seeds from the table above + saved file.
local DB_FILE = 'GameTestMenu/attack_anims.json'
local learned = {}
pcall(function()
    if isfile and isfile(DB_FILE) then
        for id in pairs(HttpServ:JSONDecode(readfile(DB_FILE)) or {}) do
            ATTACK_ANIMS[id] = true; learned[id] = true
        end
    end
end)
saveAttackDB = function()
    pcall(function()
        if makefolder and isfolder and not isfolder('GameTestMenu') then makefolder('GameTestMenu') end
        if writefile then writefile(DB_FILE, HttpServ:JSONEncode(learned)) end
    end)
    Library:Notify('Saved attack DB', 3)
end
clearAttackDB = function()
    for id in pairs(learned) do learned[id] = nil end
    saveAttackDB()
    Library:Notify('Cleared learned attack DB', 3)
end
local function learnAnim(id)
    if id and id ~= '?' and not learned[id] then
        ATTACK_ANIMS[id] = true
        learned[id] = true
        pcall(saveAttackDB)
        print('[AutoParry] learned attack anim: ' .. id)
    end
end

-- Is `char` facing roughly toward us? (dot of their look vs direction to us)
local function facingMe(char)
    local hrp = char:FindFirstChild('HumanoidRootPart') or char.PrimaryPart
    local myRoot = getRoot()
    if not (hrp and myRoot) then return true end
    local toMe = myRoot.Position - hrp.Position
    if toMe.Magnitude < 1 then return true end
    return hrp.CFrame.LookVector:Dot(toMe.Unit) >= Options.ParryFacing.Value
end

local Requests = RepStorage:FindFirstChild('Requests')

local function fireRequest(name, ...)
    if not Requests then return end
    local r = Requests:FindFirstChild(name)
    if r then r:FireServer(...) end
end

-- Shared M1 (LightAttack) driver for Auto-M1 / combos / movestack. VV routes M1
-- through NetworkManager (a module, not a Requests remote): hold=true then
-- release=false. m1Once() = one full swing.
local NetMgr
pcall(function()
    local sm = RepStorage:FindFirstChild('SharedModules')
    local nmMod = sm and sm:FindFirstChild('NetworkManager')
    if nmMod then NetMgr = require(nmMod) end
end)
local function fireM1(down)
    if not NetMgr then return end
    pcall(function()
        if type(NetMgr.FireServer) == 'function' then
            if down then NetMgr:FireServer('LightAttack', true, false) else NetMgr:FireServer('LightAttack', false) end
        else
            local ev = NetMgr:GetEvent('LightAttack')
            if ev and ev.FireServer then
                if down then ev:FireServer(true, false) else ev:FireServer(false) end
            end
        end
    end)
end
local function m1Once()
    fireM1(true)
    task.delay(0.03, function() fireM1(false) end)
end

-- Confirmed via RemoteSpy:
--   Mouse2     = block/parry press (no args)
--   RedCounter = blade-catch / alt parry (no args)
doParry = function()
    local m = Options.ParryMethod.Value
    if m == 'Right-click (real parry)' then
        if timedBlock then timedBlock() end
    elseif m == 'RedCounter (blade catch)' then
        fireRequest('RedCounter')
    elseif m == 'Block (Combat tap)' then
        -- Quick block press+release = a parry if timed on the attack's active frame
        fireRequest('Combat', 'Block', true)
        task.delay(0.15, function() fireRequest('Combat', 'Block', false) end)
    else
        fireRequest('Mouse2')
    end
end

-- Equip once when Auto Parry is enabled (assumes you start unequipped).
Toggles.AutoParry:OnChanged(function()
    if Toggles.AutoParry.Value and Toggles.AutoEquip.Value and Requests then
        local c = Requests:FindFirstChild('Combat')
        if c then c:FireServer('ToggleWeapon') end
    end
end)

-- ---- Parry Trainer: learn the exact parry timing per attack -----------------
-- VV has no parry remote - a parry is a block raised on the hit frame. So we
-- learn, per attack animation, how far in the parry landed, then replay a
-- timed block at that exact point. Persisted to file so it accumulates.
local TIMINGS_FILE = 'GameTestMenu/parry_timings.json'
local learnedTiming = {}   -- [animId] = { t = avgSeconds, n = sampleCount }
local recentAttack         -- most recent in-range enemy attack (for manual mark)

pcall(function()
    if isfile and isfile(TIMINGS_FILE) then
        learnedTiming = HttpServ:JSONDecode(readfile(TIMINGS_FILE)) or {}
    end
end)

local function timingCount()
    local n = 0
    for _ in pairs(learnedTiming) do n += 1 end
    return n
end
local function updateTrainerLabel()
    if TrainerLabel then TrainerLabel:SetText(('Learned timings: %d'):format(timingCount())) end
end
updateTrainerLabel()

local function saveTimings()
    pcall(function()
        if makefolder and isfolder and not isfolder('GameTestMenu') then makefolder('GameTestMenu') end
        if writefile then writefile(TIMINGS_FILE, HttpServ:JSONEncode(learnedTiming)) end
    end)
end
local function recordTiming(animId, t)
    if not animId or animId == '?' or not t or t <= 0 then return end
    local e = learnedTiming[animId]
    if e then
        e.t = (e.t * e.n + t) / (e.n + 1)
        e.n += 1
    else
        learnedTiming[animId] = { t = t, n = 1 }
    end
    ATTACK_ANIMS[animId] = true -- a parried anim is definitely an attack
    saveTimings()
    updateTrainerLabel()
    local num = (type(animId) == 'string' and animId:match('%d+')) or animId
    print(('[Trainer] %s -> %.3fs (n=%d)'):format(animId, learnedTiming[animId].t, learnedTiming[animId].n))
    print(("    DB: ['%s'] = %.2f,"):format(tostring(num), learnedTiming[animId].t)) -- paste-ready
    Library:Notify(('Learned parry @ %.2fs'):format(t), 2)
end
clearTimings = function()
    learnedTiming = {}
    saveTimings()
    updateTrainerLabel()
    Library:Notify('Cleared learned parry timings', 3)
end
-- Dump everything learned/measured as a paste-ready MANUAL_TIMINGS block so you
-- can hand the numbers off to bake into the hardcoded database.
dumpTimings = function()
    local keys = {}
    for animId in pairs(learnedTiming) do keys[#keys + 1] = animId end
    table.sort(keys, function(a, b) return learnedTiming[a].t < learnedTiming[b].t end)
    local lines = { 'local MANUAL_TIMINGS = {' }
    for _, animId in ipairs(keys) do
        local num = (type(animId) == 'string' and animId:match('%d+')) or animId
        local e = learnedTiming[animId]
        lines[#lines + 1] = ("    ['%s'] = %.2f,  -- n=%d"):format(tostring(num), e.t, e.n)
    end
    lines[#lines + 1] = '}'
    local blob = table.concat(lines, '\n')
    print('\n===== MEASURED PARRY TIMINGS (paste-ready) =====\n' .. blob ..
          '\n================================================')
    if setclipboard then pcall(setclipboard, blob) end
    Library:Notify(('Dumped %d timings to console%s'):format(#keys, setclipboard and ' + clipboard' or ''), 4)
end

-- ---- Latency / FPS helpers (Aztup-style) ------------------------------------
-- playerFPS feeds the block-spam loop; ping feeds parry-lead compensation.
local Stats = game:GetService('Stats')
local playerFPS = 60
do
    local frames, accum = 0, 0
    track(RunService.RenderStepped:Connect(function(dt)
        frames += 1; accum += dt
        if accum >= 1 then playerFPS = frames; frames, accum = 0, 0 end
    end))
end
local function pingSeconds()
    local ok, ms = pcall(function() return Stats.PerformanceStats.Ping:GetValue() end)
    return (ok and ms and ms > 0) and (ms / 1000) or 0
end
-- Subtract a fraction of your ping so the block fires early enough to land.
local function calculatePingWait(n)
    local pct = Options.ParryPingComp and Options.ParryPingComp.Value or 0
    if pct <= 0 then return n end
    return math.max(0, n - pingSeconds() * (pct / 100))
end

-- Block state (right-click). A successful parry = block raised on the hit frame.
local blocking = false
local lastBlockTime = 0
track(UIS.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton2 then blocking = true end
end))
track(UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton2 then blocking = false; lastBlockTime = os.clock() end
end))

-- A parry in VV = the real Block remote raised on the hit frame, then released:
--   press   = Requests.Combat:FireServer('Block', true)
--   release = Requests.Combat:FireServer('Block', false)
-- Aztup trick: SPAM the press across the first ~0.1s of frames so a dropped
-- packet or ping spike can't make the block miss the active hit window, then
-- hold for BlockHold and release. We also fire the hardware RMB if the executor
-- exposes it, so VV's own client parry runs too.
local VIM = game:GetService('VirtualInputManager')
local hasSim = type(mouse2press) == 'function' and type(mouse2release) == 'function'
local function rmb(down)
    if down and mouse2press then pcall(mouse2press); return end
    if (not down) and mouse2release then pcall(mouse2release); return end
    pcall(function()
        local mp = UIS:GetMouseLocation()
        VIM:SendMouseButtonEvent(mp.X, mp.Y, 1, down, game, 0)
    end)
end
timedBlock = function()
    rmb(true)
    local startC = os.clock()
    -- Spam ~12 block presses spread over the first ~0.1s (scaled to FPS) so the
    -- server registers the block even if a frame/packet drops. Re-sending the
    -- held 'Block, true' is idempotent, so this can't double-parry.
    local fps = math.clamp(playerFPS, 1, 240)
    local loops = math.clamp(math.floor(fps * 0.1) + 1, 1, 12)
    local perFrame = math.ceil(12 / loops)
    local spamWindow = math.min(0.1, Options.BlockHold.Value)
    repeat
        for _ = 1, perFrame do fireRequest('Combat', 'Block', true) end
        task.wait()
    until os.clock() - startC >= spamWindow
    -- Hold the block for the remainder of BlockHold, then release.
    local rest = Options.BlockHold.Value - (os.clock() - startC)
    if rest > 0 then task.wait(rest) end
    fireRequest('Combat', 'Block', false) -- release => the parry resolves
    rmb(false)
end

Library:Notify('Parry: Combat Block remote (spam+hold)' .. (hasSim and ' + input sim' or ''), 6)


-- ---- Combat: animation logger + autoparry detection -------------------------
local lastParry = 0
local function fireParryNow(srcName, animName, animId, why)
    if os.clock() - lastParry < Options.ParryCooldown.Value then return end
    lastParry = os.clock()
    local msg = ('PARRIED %s | "%s" | %s | %s'):format(srcName or '?', animName or '?', animId or '?', why or '')
    print('[AutoParry] ' .. msg)
    Library:Notify(('PARRIED %s (%s)'):format(srcName or '?', why or ''), 2)
    if doParry then doParry() end
end

-- ---- Feint tracking (kept for Auto Parry's "Read feints" option) ------------
-- The Sound Logger / parry-SFX confirmation that used to populate this was
-- removed. The table stays empty, so "Read feints" is a harmless no-op unless a
-- new feint source is wired in later.
local feintGen = setmetatable({}, { __mode = 'k' })

local function onAnimPlayed(char, animTrack)
    local anim = animTrack.Animation
    local animId = anim and anim.AnimationId or '?'
    local animName = (anim and anim.Name ~= '' and anim.Name) or animTrack.Name or '?'
    local oroot = char:FindFirstChild('HumanoidRootPart') or char.PrimaryPart
    local myRoot = getRoot()
    local dist = (myRoot and oroot) and (myRoot.Position - oroot.Position).Magnitude or math.huge
    local isPlayer = Players:GetPlayerFromCharacter(char) ~= nil
    local looped = animTrack.Looped

    -- AI BREAKER (stop combat anims): cancel the mob's attack/parry animation
    -- so it can't act. Only bites if VV lets us control the mob.
    if Toggles.AIBreaker.Value and not isPlayer and not looped
       and (Options.AIBreakMethod.Value == 'Stop combat anims' or Options.AIBreakMethod.Value == 'All')
       and dist <= Options.AIBreakRange.Value
       and (not Toggles.AIBreakTargetOnly.Value or char == attachTargetModel) then
        pcall(function() animTrack:Stop(0) end)
    end

    -- TRAINING: learn parry timing from your manual blocks -------------------
    if not looped and dist <= Options.ParryDistance.Value + 5
       and not (Toggles.ParryIgnorePlayers.Value and isPlayer) then
        recentAttack = { animId = animId, track = animTrack, startC = os.clock() }
    end

    -- ATTACH AUTO-DODGE: if the attach target swings, back off briefly --------
    if Toggles.AttachBack.Value and Toggles.AttachDodge.Value
       and attachTargetModel and char == attachTargetModel and not looped
       and (ATTACK_ANIMS[animId] or animTrack.Length >= 0.3) then
        attachDodgeUntil = os.clock() + Options.DodgeTime.Value
    end

    -- AUTO PARRY -------------------------------------------------------------
    if not Toggles.AutoParry.Value then return end
    if looped then return end                                  -- never parry idle loops
    if dist > Options.ParryDistance.Value then return end
    if Toggles.ParryIgnorePlayers.Value and isPlayer then return end

    local mode = Options.ParryMode.Value
    local srcEntry = SOURCE_DB[animId] -- VV game-data attack entry (nil = not an attack)
    local known = (srcEntry ~= nil) or (ATTACK_ANIMS[animId] == true)
    local smartOk = facingMe(char) and animTrack.Length >= Options.ParryMinLen.Value

    local consider
    if mode == 'Database (IDs)' then consider = known
    elseif mode == 'Smart (no setup)' then consider = smartOk
    else consider = known or smartOk end                       -- Both
    if not consider then return end

    local timing = Options.ParryTiming.Value

    -- Learned: parry at the per-attack time you taught it. For UNtrained attacks
    -- fall back to a fraction of the animation length so we never just miss them.
    if timing == 'Learned (trained)' then
        local num = animNum(animId)
        local manual = num and MANUAL_TIMINGS[num] or nil

        -- Multi-hit combo from the hand-measured DB: one parry per listed time,
        -- ping-compensated, with drift correction so later hits stay aligned.
        if type(manual) == 'table' then
            local feintGenAt = feintGen[char] or 0
            task.spawn(function()
                local startC = os.clock()
                for _, raw in ipairs(manual) do
                    local target = calculatePingWait(math.max(0, raw - Options.ParryLead.Value))
                    local wait = target - (os.clock() - startC)
                    if wait > 0 then task.wait(wait) end
                    if not animTrack.IsPlaying then return end -- feinted/cancelled
                    if Toggles.ReadFeints.Value and (feintGen[char] or 0) ~= feintGenAt then return end
                    if os.clock() - lastParry >= Options.ParryCooldown.Value then
                        lastParry = os.clock()
                        print(('[AutoParry] combo block %s hit @ %.2fs'):format(animId, raw))
                        timedBlock()
                    end
                end
            end)
            return
        end

        -- Single parry point. Priority: SOURCE game-data timestamp > hand-measured
        -- DB > runtime-trained > fallback %. The source time is the exact frame the
        -- attack connects (from VV's WeaponStats), so no training needed.
        local e = learnedTiming[animId]
        local srcT = srcEntry and srcEntry.t -- exact hit timestamp from VV's WeaponStats
        local base = srcT
            or (type(manual) == 'number' and manual)
            or (e and e.t)
            or (animTrack.Length * Options.ParryFallback.Value)
        local src = (srcT and 'source')
            or (type(manual) == 'number' and 'manual')
            or (e and 'trained')
            or 'fallback'
        local when = calculatePingWait(math.max(0, base - Options.ParryLead.Value))
        local feintGenAt = feintGen[char] or 0 -- detect a feint sound during this windup

        local feinted, parryFiredAt = false, nil
        local sc
        sc = animTrack.Stopped:Connect(function()
            local stoppedAt = animTrack.TimePosition
            -- Stopped BEFORE we parried = a feint/cancel -> don't parry it.
            if not parryFiredAt and Toggles.ReadFeints.Value then feinted = true end
            -- AUTO-TRAIN: only learn when OUR parry just landed (the swing was cut
            -- short soon after we blocked) - never from feints/early cancels. Skip
            -- when hand-measured so runtime noise can't drift a tuned DB entry.
            if Toggles.AutoTrain.Value and not manual and parryFiredAt
               and not (Toggles.ConfirmTrainOnly and Toggles.ConfirmTrainOnly.Value)
               and (os.clock() - parryFiredAt) < 0.35
               and stoppedAt < (animTrack.Length - 0.10)
               and stoppedAt >= animTrack.Length * 0.3 then
                recordTiming(animId, stoppedAt)
            end
            if sc then sc:Disconnect() end
        end)
        task.delay(animTrack.Length + 1, function() if sc then sc:Disconnect() end end)

        task.delay(when, function()
            if feinted then return end -- attack was feinted (anim cancelled) -> skip
            if Toggles.ReadFeints.Value and (feintGen[char] or 0) ~= feintGenAt then
                return -- feint SOUND fired during this windup -> it was bait, skip
            end
            if os.clock() - lastParry < Options.ParryCooldown.Value then return end
            lastParry = os.clock()
            parryFiredAt = os.clock()
            print(('[AutoParry] %s block %s @ %.2fs'):format(src, animId, when))
            timedBlock()
        end)

        -- If VV ever fires a hit marker, learn the ID so it becomes a known attack.
        if Toggles.AutoLearn.Value then
            local mc
            mc = animTrack.KeyframeReached:Connect(function(kf)
                if markerIsHit(kf) then learnAnim(animId); if mc then mc:Disconnect() end end
            end)
            task.delay(animTrack.Length + 0.3, function() if mc then mc:Disconnect() end end)
        end
        return
    end

    -- On hit marker: parry exactly when a hit keyframe fires (frame-perfect),
    -- and learn the ID. Falls back to a start-parry if no marker shows up.
    if timing == 'On hit marker' then
        local done = false
        local mc
        mc = animTrack.KeyframeReached:Connect(function(kf)
            if done or not markerIsHit(kf) then return end
            done = true
            if Toggles.AutoLearn.Value then learnAnim(animId) end
            fireParryNow(char.Name, animName, animId, 'marker:' .. tostring(kf))
            if mc then mc:Disconnect() end
        end)
        task.delay(animTrack.Length + 0.3, function() if mc then mc:Disconnect() end end)
        -- Fallback: if this anim is a known attack but fired no hit marker,
        -- parry near the end of its windup so we don't miss it entirely.
        if known then
            task.delay(math.max(0, animTrack.Length * 0.5), function()
                if not done then done = true; fireParryNow(char.Name, animName, animId, 'known-fallback') end
            end)
        end
        return
    end

    -- On start: parry immediately. Fixed delay: wait the react slider first.
    local lead = (timing == 'Fixed delay') and Options.ParryReactionDelay.Value or 0
    task.delay(lead, function() fireParryNow(char.Name, animName, animId, timing) end)
end

-- No Stun: cancel stun animations on YOUR character so you can act through hits.
local function onMyAnim(animTrack)
    local anim = animTrack.Animation
    local id = anim and anim.AnimationId or '?'
    if Toggles.NoStun and Toggles.NoStun.Value and STUN_ANIMS[id] then
        pcall(function() animTrack:Stop(0) end)
        print('[NoStun] cancelled ' .. id)
    end
    -- Local M1 anim speed-up (experimental): only speeds YOUR weapon Light/Heavy
    -- swings (must be a known attack anim), so walk/idle stay normal.
    local sp = Options.M1AnimSpeed and Options.M1AnimSpeed.Value or 1
    if sp > 1.01 and (SOURCE_DB[id] or ATTACK_ANIMS[id]) then
        pcall(function() animTrack:AdjustSpeed(sp) end)
    end
end

local animHooked = {}
local function hookAnimator(animator)
    if animHooked[animator] then return end
    local conn = animator.AnimationPlayed:Connect(function(animTrack)
        local hum = animator.Parent
        local char = hum and hum.Parent
        if not char then return end
        if char == getChar() then
            pcall(onMyAnim, animTrack)                       -- local: no-stun + logging
        elseif char:FindFirstChildOfClass('Humanoid') then
            pcall(onAnimPlayed, char, animTrack)             -- enemies: parry/dodge
        end
    end)
    animHooked[animator] = conn
    track(conn)
end

for _, d in workspace:GetDescendants() do
    if d:IsA('Animator') then hookAnimator(d) end
end
track(workspace.DescendantAdded:Connect(function(d)
    if d:IsA('Animator') then hookAnimator(d) end
end))

-- ---- Auto Dodge: react to VV's ParryIndicator and dodge unparryable attacks --
-- VV sends a ParryIndicator(kind, ...) event to the client for incoming attacks:
--   NormalParry / NeutralParry = parryable ; Red = UNPARRYABLE (must dodge) ;
--   Riposte / Rushdown = special. We listen to that exact event and fire VV's
--   own Dash remote (Requests.Dash:InvokeServer(vector, speed*velocity)) to dodge.
do
    local DashRemote = Requests and Requests:FindFirstChild('Dash')

    -- Direction map + velocity, pulled live from DashInfo (with a fallback).
    local DASH_DIRS = {
        A = { vector = 'RightVector', speed = -1 }, -- left
        D = { vector = 'RightVector', speed =  1 }, -- right
        W = { vector = 'LookVector',  speed =  1 }, -- forward
        S = { vector = 'LookVector',  speed = -1 }, -- back
    }
    local dashVelocity = 73
    pcall(function()
        local sa = RepStorage:FindFirstChild('SharedAssets')
        local info = sa and sa:FindFirstChild('Info')
        local di = info and info:FindFirstChild('DashInfo')
        if di then
            local d = require(di)
            if type(d) == 'table' then
                dashVelocity = tonumber(d.DashVelocity) or dashVelocity
                if type(d.DirectionalInfo) == 'table' then
                    for k, v in pairs(d.DirectionalInfo) do
                        if type(v) == 'table' and v.Vector then
                            DASH_DIRS[k] = { vector = v.Vector, speed = v.Speed or 1 }
                        end
                    end
                end
            end
        end
    end)

    doDodge = function(dirKey)
        if not DashRemote then return end
        local d = DASH_DIRS[dirKey] or DASH_DIRS.A
        task.spawn(function() -- InvokeServer yields; don't block the caller/event
            pcall(function() DashRemote:InvokeServer(d.vector, d.speed * dashVelocity) end)
        end)
    end

    local dodgeFlip = false
    local function pickDir()
        local m = Options.DodgeDir.Value
        if m == 'Left (A)' then return 'A'
        elseif m == 'Right (D)' then return 'D'
        elseif m == 'Back (S)' then return 'S'
        else dodgeFlip = not dodgeFlip; return dodgeFlip and 'A' or 'D' end -- Alternate
    end

    local lastDodge = 0
    pcall(function()
        local sm = RepStorage:FindFirstChild('SharedModules')
        local nmMod = sm and sm:FindFirstChild('NetworkManager')
        if not nmMod then print('[AutoDodge] NetworkManager not found - dodge disabled'); return end
        local nm = require(nmMod)
        local ev = nm:GetEvent('ParryIndicator')
        local sig = ev and ev.OnClientEvent
        if not sig then print('[AutoDodge] ParryIndicator event not found - dodge disabled'); return end
        track(sig:Connect(function(kind)
            if MenuUnloaded or not (Toggles.AutoDodge and Toggles.AutoDodge.Value) then return end
            if type(kind) ~= 'string' then return end
            local extra = Options.DodgeOn and Options.DodgeOn.Value
            local dodge = (kind == 'Red') or (extra and extra[kind])
            if not dodge then return end
            if os.clock() - lastDodge < Options.DodgeCooldown.Value then return end
            lastDodge = os.clock()
            local dir = pickDir()
            print(('[AutoDodge] %s -> dodge %s'):format(kind, dir))
            doDodge(dir)
            if Toggles.DodgeNotify and Toggles.DodgeNotify.Value then
                Library:Notify(('Dodged %s'):format(kind), 1)
            end
        end))
        print('[AutoDodge] hooked ParryIndicator (auto-dodge ready, dodges Red)')
    end)
end

-- ---- Combat Extras: anti-grab, auto-M1 + movestack, combo macro -------------
do
    local CollectionService = game:GetService('CollectionService')
    local vim = game:GetService('VirtualInputManager')
    local CombatRemote = Requests and Requests:FindFirstChild('Combat')

    local function tapKey(kc)
        pcall(function()
            vim:SendKeyEvent(true, kc, false, game)
            vim:SendKeyEvent(false, kc, false, game)
        end)
    end

    -- Anti-grab / auto-getup: drive the game's OWN escape inputs the instant we're
    -- tagged, so we break free as soon as the server permits (no reaction delay).
    -- There's no dedicated escape remote - F gets you up from Knocked, and a grab
    -- locks other inputs, so we mash movement + jump to feed the struggle.
    local grabAcc = 0
    track(RunService.Heartbeat:Connect(function(dt)
        if not (Toggles.AntiGrab and Toggles.AntiGrab.Value) then return end
        local char = getChar(); if not char then return end
        grabAcc += dt
        if grabAcc < 0.12 then return end -- ~8 mashes/sec
        grabAcc = 0
        local knocked = char:FindFirstChild('Knocked') or char:FindFirstChild('Unconscious')
            or CollectionService:HasTag(char, 'Knocked') or CollectionService:HasTag(char, 'Unconscious')
        local grabbed = char:FindFirstChild('Grabbed') or CollectionService:HasTag(char, 'Grabbed')
        if knocked then tapKey(Enum.KeyCode.F) end -- getup
        if grabbed then
            tapKey(Enum.KeyCode.Space)
            tapKey(Enum.KeyCode.W); tapKey(Enum.KeyCode.A)
            tapKey(Enum.KeyCode.S); tapKey(Enum.KeyCode.D)
        end
    end))

    -- Auto M1 (+ movestack cancel). Server gates the real combo cadence, so the
    -- interval slider is the true speed knob; too-fast extras just get dropped.
    local function cancelInput()
        local m = Options.MoveStackWith and Options.MoveStackWith.Value or 'Dash'
        if m == 'Dash' then
            if doDodge then doDodge('S') end
        elseif m == 'Block tap' then
            fireRequest('Combat', 'Block', true)
            task.delay(0.05, function() fireRequest('Combat', 'Block', false) end)
        else -- Sheath/unsheath: toggle out then back so the swing recovery is cut
            if CombatRemote then
                pcall(function() CombatRemote:FireServer('ToggleWeapon') end)
                task.delay(0.05, function() pcall(function() CombatRemote:FireServer('ToggleWeapon') end) end)
            end
        end
    end
    local m1Acc = 0
    track(RunService.Heartbeat:Connect(function(dt)
        if not (Toggles.AutoM1 and Toggles.AutoM1.Value) then return end
        m1Acc += dt
        if m1Acc < (Options.M1Rate and Options.M1Rate.Value or 0.28) then return end
        m1Acc = 0
        m1Once()
        if Toggles.MoveStack and Toggles.MoveStack.Value then task.delay(0.04, cancelInput) end
    end))

    -- Combo macro: parse the token string and fire the real remotes in sequence.
    runCombo = function()
        local seq = tostring(Options.ComboSeq and Options.ComboSeq.Value or '')
        local steps = {}
        for tok in seq:gmatch('[%a%d]+') do steps[#steps + 1] = tok:lower() end
        if #steps == 0 then Library:Notify('Enter a combo first', 2); return end
        task.spawn(function()
            for _, tok in ipairs(steps) do
                if tok == 'm1' or tok == 'light' then m1Once()
                elseif tok == 'heavy' then if CombatRemote then pcall(function() CombatRemote:FireServer('HeavyAttack', true) end) end
                elseif tok == 'block' or tok == 'parry' then if doParry then doParry() end
                elseif tok == 'dash' or tok == 'dashb' then if doDodge then doDodge('S') end
                elseif tok == 'dashl' then if doDodge then doDodge('A') end
                elseif tok == 'dashr' then if doDodge then doDodge('D') end
                elseif tok == 'dashf' then if doDodge then doDodge('W') end
                elseif tok == 'sheath' or tok == 'toggle' then if CombatRemote then pcall(function() CombatRemote:FireServer('ToggleWeapon') end) end
                -- 'wait' (and unknown tokens) just consume the step delay
                end
                task.wait(Options.ComboStep and Options.ComboStep.Value or 0.16)
            end
        end)
        Library:Notify(('Combo: %d steps'):format(#steps), 1.5)
    end
    if Options.ComboKey then Options.ComboKey:OnClick(function() if runCombo then runCombo() end end) end
end

-- ---- Weapon Swap: auto-return to your weapon slot after casting a move -------
-- This game's hotbar (BackpackClient) maps number keys One..Zero -> slots 1..10
-- and equips via the game's own handler, so "switch to the weapon" = press its
-- slot's number key. We DON'T need to know the weapon's name: pressing a NON-
-- weapon slot key arms it (you switched to a move), and the next cast-click
-- returns you. That means it can never fire while you're on the weapon, so it
-- won't interrupt M1 spam.
do
    local vim = game:GetService('VirtualInputManager')
    local KEY_TO_SLOT = {
        [Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3, [Enum.KeyCode.Four] = 4,
        [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6, [Enum.KeyCode.Seven] = 7, [Enum.KeyCode.Eight] = 8,
        [Enum.KeyCode.Nine] = 9, [Enum.KeyCode.Zero] = 10,
    }
    local SLOT_TO_KEY = {}
    for k, v in pairs(KEY_TO_SLOT) do SLOT_TO_KEY[v] = k end

    local function tapKey(kc)
        pcall(function()
            vim:SendKeyEvent(true, kc, false, game)
            vim:SendKeyEvent(false, kc, false, game)
        end)
    end
    returnToWeapon = function()
        local slot = math.floor((Options.WeaponSlot and Options.WeaponSlot.Value) or 1)
        tapKey(SLOT_TO_KEY[slot] or Enum.KeyCode.One)
    end

    local armed = false -- true once you switch to a non-weapon (move) slot
    track(UIS.InputBegan:Connect(function(input, gpe)
        if gpe then return end -- typing in a box / clicking the menu
        if not (Toggles.AutoReturnWeapon and Toggles.AutoReturnWeapon.Value) then return end
        local wslot = math.floor((Options.WeaponSlot and Options.WeaponSlot.Value) or 1)
        if input.UserInputType == Enum.UserInputType.Keyboard then
            local s = KEY_TO_SLOT[input.KeyCode]
            if s then armed = (s ~= wslot) end -- move slot -> arm ; weapon slot -> disarm
        elseif input.UserInputType == Enum.UserInputType.MouseButton1 and armed then
            armed = false
            task.delay((Options.ReturnDelay and Options.ReturnDelay.Value) or 0.3, function()
                if Toggles.AutoReturnWeapon and Toggles.AutoReturnWeapon.Value then returnToWeapon() end
            end)
        end
    end))
    if Options.ReturnKey then Options.ReturnKey:OnClick(function() returnToWeapon() end) end
end

-- ---- Experimental: grab-void / grab-fling + self-fling ----------------------
-- While YOU are grabbing someone, this game hands your client network ownership
-- of the victim (it writes their Humanoid.PlatformStand each frame - see
-- CharacterHandler/Input.lua). Character.Grabbing.Value is the victim, so we can
-- shove their HumanoidRootPart into the void / fling it and it replicates. When
-- the grab ends they're dropped wherever we left them.
do
    local function strip(s) return (tostring(s):gsub('^%.+', '')) end
    local function getGrabbed()
        local char = getChar()
        local g = char and char:FindFirstChild('Grabbing')
        local victim = g and g.Value
        if typeof(victim) == 'Instance' and victim:FindFirstChild('HumanoidRootPart') then return victim end
        return nil
    end

    voidGrabbed = function()
        local victim = getGrabbed()
        if not victim then Library:Notify('You are not grabbing anyone', 2); return end
        local vhrp = victim:FindFirstChild('HumanoidRootPart'); if not vhrp then return end
        local depth = Options.VoidDepth and Options.VoidDepth.Value or 1000
        Library:Notify('Voiding ' .. strip(victim.Name) .. '...', 2)
        task.spawn(function()
            local t0 = os.clock()
            -- Spam for a few frames so a single server reposition can't save them.
            while os.clock() - t0 < 0.6 and getGrabbed() == victim do
                pcall(function()
                    local p = vhrp.Position
                    vhrp.CFrame = CFrame.new(p.X, -depth, p.Z)
                    vhrp.AssemblyLinearVelocity = Vector3.new(0, -600, 0)
                end)
                RunService.Heartbeat:Wait()
            end
        end)
    end

    flingGrabbed = function()
        local victim = getGrabbed()
        if not victim then Library:Notify('You are not grabbing anyone', 2); return end
        local vhrp = victim:FindFirstChild('HumanoidRootPart'); if not vhrp then return end
        local power = Options.FlingPower and Options.FlingPower.Value or 600
        Library:Notify('Flinging ' .. strip(victim.Name) .. '...', 2)
        task.spawn(function()
            local t0 = os.clock()
            while os.clock() - t0 < 0.3 and getGrabbed() == victim do
                pcall(function()
                    vhrp.AssemblyLinearVelocity = Vector3.new((math.random() * 2 - 1) * power, power, (math.random() * 2 - 1) * power)
                    vhrp.AssemblyAngularVelocity = Vector3.new(power, power, power)
                end)
                RunService.Heartbeat:Wait()
            end
        end)
    end

    if Options.VoidGrabKey then Options.VoidGrabKey:OnClick(function() if voidGrabbed then voidGrabbed() end end) end
    if Options.FlingGrabKey then Options.FlingGrabKey:OnClick(function() if flingGrabbed then flingGrabbed() end end) end

    -- Status label + auto-void trigger (throttled so SetText doesn't thrash).
    local statusAcc, lastGrabbed = 0, nil
    track(RunService.Heartbeat:Connect(function(dt)
        local victim = getGrabbed()
        if victim ~= lastGrabbed then
            if victim and Toggles.AutoVoidGrab and Toggles.AutoVoidGrab.Value and voidGrabbed then
                task.delay(0.15, voidGrabbed)
            end
            lastGrabbed = victim
        end
        statusAcc += dt
        if statusAcc >= 0.2 then
            statusAcc = 0
            if GrabStatus then GrabStatus:SetText('Grabbing: ' .. (victim and strip(victim.Name) or 'nobody')) end
        end
    end))

    -- Self-fling: spin our own HRP (noclipped) each frame while enabled.
    track(RunService.RenderStepped:Connect(function()
        if not (Toggles.SelfFling and Toggles.SelfFling.Value) then return end
        local char = getChar(); local hrp = getRoot(); if not (char and hrp) then return end
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA('BasePart') and p.CanCollide then p.CanCollide = false end
        end
        local pw = Options.SpinPower and Options.SpinPower.Value or 200
        hrp.AssemblyAngularVelocity = Vector3.new(pw, pw, pw)
        hrp.AssemblyLinearVelocity = Vector3.new(0, 20, 0)
    end))
    if Toggles.SelfFling then
        Toggles.SelfFling:OnChanged(function()
            if not Toggles.SelfFling.Value then
                local hrp = getRoot()
                if hrp then hrp.AssemblyAngularVelocity = Vector3.zero; hrp.AssemblyLinearVelocity = Vector3.zero end
            end
        end)
    end
end

-- ---- Infinite Jump ----------------------------------------------------------
track(UIS.JumpRequest:Connect(function()
    if Toggles.InfJumpEnabled.Value then
        local hum = getHumanoid()
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end))

-- ---- Per-frame loop: WalkSpeed / JumpPower / Fly / NoFallDamage -------------
track(RunService.RenderStepped:Connect(function()
    local hum = getHumanoid()

    if hum then
        if Toggles.WalkSpeedEnabled.Value then
            hum.WalkSpeed = Options.WalkSpeedValue.Value
        end
        if Toggles.JumpPowerEnabled.Value then
            hum.UseJumpPower = true
            hum.JumpPower = Options.JumpPowerValue.Value
        end
        -- No Stun: keep us out of forced-stun physics states (PlatformStand /
        -- ragdoll) so a hit can't lock our movement/attacks.
        if Toggles.NoStun.Value then
            if hum.PlatformStand then hum.PlatformStand = false end
            local st = hum:GetState()
            if st == Enum.HumanoidStateType.Ragdoll or st == Enum.HumanoidStateType.FallingDown then
                pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
            end
        end
    end

    -- Fly movement (camera-relative)
    if Toggles.FlyEnabled.Value and flyVel and flyGyro then
        local speed = Options.FlySpeed.Value
        local dir = Vector3.zero
        local cf = Camera.CFrame
        if UIS:IsKeyDown(Enum.KeyCode.W) then dir += cf.LookVector end
        if UIS:IsKeyDown(Enum.KeyCode.S) then dir -= cf.LookVector end
        if UIS:IsKeyDown(Enum.KeyCode.A) then dir -= cf.RightVector end
        if UIS:IsKeyDown(Enum.KeyCode.D) then dir += cf.RightVector end
        if UIS:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.new(0, 1, 0) end
        if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.new(0, 1, 0) end

        flyGyro.CFrame = cf
        flyVel.Velocity = (dir.Magnitude > 0 and dir.Unit or Vector3.zero) * speed
    end
end))

-- ---- Attach to back ---------------------------------------------------------
-- Teleport behind the nearest target (mob / npc / player), facing them.
-- Distance & Y level are configurable.
local ATTACH_FOLDERS = { 'Alive', 'Live', 'Living', 'Mobs', 'Enemies', 'NPCs', 'Entities', 'Monsters' }
-- Shared NPC test (also used by AI Breaker): a model carrying a
-- ProximityPrompt is an interactable NPC (vendor / guard / quest-giver).
local attachNpcCache = setmetatable({}, { __mode = 'k' })
local function isNpcModel(m)
    local v = attachNpcCache[m]
    if v == nil then v = m:FindFirstChildWhichIsA('ProximityPrompt', true) ~= nil; attachNpcCache[m] = v end
    return v
end
local lockedTarget -- model we stay attached to until it dies / leaves range

-- All valid attach candidates as { model, root, hum }.
local function attachCandidates()
    local list = {}
    local function add(m)
        if m == getChar() then return end
        local hum = m:FindFirstChildOfClass('Humanoid')
        local root = m:FindFirstChild('HumanoidRootPart') or m.PrimaryPart
        if hum and hum.Health > 0 and root then
            list[#list + 1] = { model = m, root = root, hum = hum }
        end
    end
    local function scan(cont)
        for _, m in ipairs(cont:GetChildren()) do
            if m:IsA('Model') and not Players:GetPlayerFromCharacter(m) then
                add(m)
            end
        end
    end
    local any = false
    for _, n in ipairs(ATTACH_FOLDERS) do
        local f = workspace:FindFirstChild(n)
        if f then scan(f); any = true end
    end
    if not any then scan(workspace) end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then add(p.Character) end
    end
    return list
end

local function findAttachTarget()
    local myRoot = getRoot()
    if not myRoot then return nil end
    local range = Options.AttachRange.Value

    -- 1) Keep the locked target while it's still alive AND in range. This stops
    --    it switching to whatever hollow wanders closest.
    if lockedTarget and lockedTarget.Parent then
        local hum = lockedTarget:FindFirstChildOfClass('Humanoid')
        local root = lockedTarget:FindFirstChild('HumanoidRootPart') or lockedTarget.PrimaryPart
        if hum and hum.Health > 0 and root
           and (myRoot.Position - root.Position).Magnitude <= range then
            return root
        end
        lockedTarget = nil -- dead or out of range -> release, pick the next
    end

    -- 2) Pick a new target: the LOWEST-HEALTH hollow in range (finish it, then
    --    move to the next), tie-broken by nearest.
    local best, bestRoot, bestHp, bestD
    for _, c in ipairs(attachCandidates()) do
        local d = (myRoot.Position - c.root.Position).Magnitude
        if d <= range then
            local hp = c.hum.Health
            if not bestHp or hp < bestHp or (hp == bestHp and d < bestD) then
                best, bestRoot, bestHp, bestD = c.model, c.root, hp, d
            end
        end
    end
    lockedTarget = best
    return bestRoot
end

track(RunService.RenderStepped:Connect(function()
    if not Toggles.AttachBack.Value then return end
    local myRoot = getRoot()
    local target = findAttachTarget() -- already range-gated; nil if none in range
    if myRoot and target then
        attachTargetModel = target.Parent -- so the dodge detector knows our target
        -- Auto-dodge: while the target's attack is active, sit further back.
        local dist = Options.AttachDistance.Value
        if Toggles.AttachDodge.Value and os.clock() < attachDodgeUntil then
            dist = dist + Options.DodgeDistance.Value
        end
        -- behind the target = +Z in its local space (LookVector points -Z),
        -- then face the target so back attacks land.
        local pos = (target.CFrame * CFrame.new(0, Options.AttachY.Value, dist)).Position
        local goal = CFrame.new(pos, target.Position)
        -- Tween (lerp) toward the goal instead of snapping -> smoother, far less
        -- likely to trip the teleport anti-cheat that was kicking you.
        myRoot.CFrame = myRoot.CFrame:Lerp(goal, math.clamp(Options.AttachSpeed.Value, 0, 1))
        -- Stop us entering freefall (which plays the fall anim / fires FallFX and
        -- interrupts your M1): kill downward momentum + force a grounded state.
        myRoot.AssemblyLinearVelocity = Vector3.zero
        local hum = getHumanoid()
        if hum and hum:GetState() == Enum.HumanoidStateType.Freefall then
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
        end
    end
end))

-- ---- AI breaker: freeze / ragdoll nearby mobs -------------------------------
-- Works only on mobs the server lets the client own (network ownership).
track(RunService.Heartbeat:Connect(function()
    if not Toggles.AIBreaker.Value then return end
    local method = Options.AIBreakMethod.Value
    local doFreeze  = method == 'Freeze + slow' or method == 'All'
    local doRagdoll = method == 'Ragdoll (physics)' or method == 'All'
    if not (doFreeze or doRagdoll) then return end
    local myRoot = getRoot(); if not myRoot then return end
    local range = Options.AIBreakRange.Value
    local targetOnly = Toggles.AIBreakTargetOnly.Value

    local function affect(m)
        if m == getChar() or Players:GetPlayerFromCharacter(m) or isNpcModel(m) then return end
        if targetOnly and m ~= attachTargetModel then return end
        local hum = m:FindFirstChildOfClass('Humanoid')
        local root = m:FindFirstChild('HumanoidRootPart') or m.PrimaryPart
        if not (hum and root and hum.Health > 0) then return end
        if (myRoot.Position - root.Position).Magnitude > range then return end
        if doFreeze then
            root.AssemblyLinearVelocity = Vector3.zero
            pcall(function() hum.WalkSpeed = 0; hum.JumpPower = 0 end)
        end
        if doRagdoll then
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.Physics) end)
        end
    end
    local function scan(cont)
        for _, m in ipairs(cont:GetChildren()) do if m:IsA('Model') then affect(m) end end
    end
    local any = false
    for _, n in ipairs(ATTACH_FOLDERS) do
        local f = workspace:FindFirstChild(n); if f then scan(f); any = true end
    end
    if not any then scan(workspace) end
end))

-- ---- Noclip (Stepped so CanCollide sticks) ----------------------------------
track(RunService.Stepped:Connect(function()
    if not Toggles.NoclipEnabled.Value then return end
    local char = getChar()
    if not char then return end
    for _, part in char:GetDescendants() do
        if part:IsA('BasePart') and part.CanCollide then
            part.CanCollide = false
        end
    end
end))

-- ---- Restore defaults when a feature is turned OFF --------------------------
Toggles.WalkSpeedEnabled:OnChanged(function()
    if not Toggles.WalkSpeedEnabled.Value then
        local hum = getHumanoid(); if hum then hum.WalkSpeed = 16 end
    end
end)
Toggles.JumpPowerEnabled:OnChanged(function()
    if not Toggles.JumpPowerEnabled.Value then
        local hum = getHumanoid(); if hum then hum.JumpPower = 50 end
    end
end)

-- ---- Re-apply fly after respawn while it's enabled --------------------------
track(LocalPlayer.CharacterAdded:Connect(function()
    if Toggles.FlyEnabled and Toggles.FlyEnabled.Value then
        task.wait(0.3)
        startFly()
    end
end))

-- ---- Melee Reach ------------------------------------------------------------
-- RL melee hit detection is a SERVER-side magnitude check around your Humanoid-
-- RootPart (reading the weapon's Length stat), so client-side part resizing is
-- useless: the server never sees the resized parts. The way to actually "hit
-- far" is to close the distance - glide to just inside your weapon length of the
-- target you're aiming at so your ordinary M1s connect. Movement is capped to a
-- bounded speed (like Fly) so the server never rubber-bands it, and it only
-- pulls you while you're aiming at a valid target (nil target = you stay put).
local REACH_FOLDERS = { 'Alive', 'Live', 'Living', 'Mobs', 'Enemies', 'NPCs', 'Entities', 'Monsters' }
local function reachCandidates()
    local list, seen = {}, {}
    local function add(m)
        if m == getChar() or seen[m] then return end
        local root = m:FindFirstChild('HumanoidRootPart') or m.PrimaryPart
        local hum = m:FindFirstChildOfClass('Humanoid')
        if root and hum and hum.Health > 0 then seen[m] = true; list[#list + 1] = { root = root } end
    end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then add(p.Character) end
    end
    if not Toggles.ReachPlayersOnly.Value then
        for _, n in ipairs(REACH_FOLDERS) do
            local f = workspace:FindFirstChild(n)
            if f then
                for _, m in ipairs(f:GetChildren()) do
                    if m:IsA('Model') and not Players:GetPlayerFromCharacter(m) then add(m) end
                end
            end
        end
    end
    return list
end

-- The target nearest to your crosshair (within range + the aim cone).
local function pickReachTarget()
    local myRoot = getRoot(); if not myRoot then return nil end
    local cam = workspace.CurrentCamera
    local range = Options.ReachRange.Value
    local minDot = 0.2 + Options.ReachAim.Value * 0.75 -- aim tightness -> crosshair cone
    local best, bestScore
    for _, c in ipairs(reachCandidates()) do
        if (myRoot.Position - c.root.Position).Magnitude <= range then
            local dir = c.root.Position - cam.CFrame.Position
            if dir.Magnitude > 0.1 then
                local dot = cam.CFrame.LookVector:Dot(dir.Unit) -- 1 = dead-centre
                if dot >= minDot then
                    local score = (1 - dot) * 1000 + dir.Magnitude -- crosshair first, then nearest
                    if not bestScore or score < bestScore then best, bestScore = c.root, score end
                end
            end
        end
    end
    return best
end

track(RunService.RenderStepped:Connect(function(dt)
    if not Toggles.Reach.Value then return end
    local myRoot = getRoot(); if not myRoot then return end
    local target = pickReachTarget()
    if not target then return end -- not aiming at anything valid -> don't move
    local off = Options.ReachMelee.Value
    local goalPos = Toggles.ReachAbove.Value
        and (target.Position + Vector3.new(0, off, 0))
        or (target.CFrame * CFrame.new(0, 0, off)).Position
    local toGoal = goalPos - myRoot.Position
    local maxStep = 250 * dt -- bounded speed the server accepts (like Fly) -> no rubber-band
    local newPos = (toGoal.Magnitude > maxStep) and (myRoot.Position + toGoal.Unit * maxStep) or goalPos
    myRoot.CFrame = CFrame.lookAt(newPos, target.Position)
    myRoot.AssemblyLinearVelocity = Vector3.zero
    local hum = getHumanoid()
    if hum and hum:GetState() == Enum.HumanoidStateType.Freefall then
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
    end
end))

-- ============================================================================
-- 6. UI Settings tab + addons
-- ============================================================================
local MenuGroup = Tabs['UI Settings']:AddLeftGroupbox('Menu')

MenuGroup:AddButton('Unload', function() Library:Unload() end)
MenuGroup:AddLabel('Menu bind'):AddKeyPicker('MenuKeybind', {
    Default = 'End', NoUI = true, Text = 'Menu keybind',
})
Library.ToggleKeybind = Options.MenuKeybind

-- ============================================================================
-- TELEPORT  (to-player dropdown + Rogue Lineage area warp)
-- ============================================================================
-- RL's server rubber-bands INSTANT teleports (snaps you back ~1s later), so we
-- GLIDE to the destination at a bounded speed instead - continuous movement the
-- server accepts, exactly like Fly. Tune "Glide speed": lower it if you still
-- snap back, raise it for near-instant short hops. No Fall Damage recommended.
local tpToPlayer, refreshTPPlayers, refreshTPAreas, warpToArea -- forward-declared for the buttons
local coordTeleport, copyMyPos, joinByUsername, cancelTP, manaChargeTest, runGateKill

local TPPlayerBox = Tabs.Teleport:AddLeftGroupbox('Teleport to Player')
TPPlayerBox:AddDropdown('TPTarget', {
    Values = {}, Default = nil, Multi = false, AllowNull = true,
    Text = 'Player', Tooltip = 'Who to teleport to (Refresh to rescan)',
})
TPPlayerBox:AddToggle('TPBehind', {
    Text = 'Arrive behind them', Default = true,
    Tooltip = 'Face the target and stand behind them instead of on top',
})
TPPlayerBox:AddSlider('TPOffset', {
    Text = 'Stand-off', Default = 4, Min = 0, Max = 20, Rounding = 1, Suffix = ' studs',
})
TPPlayerBox:AddToggle('InstantTP', {
    Text = 'Instant TP (TPSafe)', Default = true,
    Tooltip = 'Teleport INSTANTLY using the game\'s own TPSafe whitelist (the flag Gate/Celeritas stamp so the server does not snap them back) instead of the slow glide. Applies to player TP, area warp, coords, gate-kill AND the gate combo. Turn OFF to fall back to the bounded glide. Keep No Fall Damage on.',
})
TPPlayerBox:AddSlider('TPGlideSpeed', {
    Text = 'Glide speed', Default = 250, Min = 50, Max = 3000, Rounding = 0, Suffix = ' studs/s',
    Tooltip = 'Only used when Instant TP is OFF. How fast to glide to the destination - lower it if you still rubber-band with the glide, raise it for faster travel.',
})
TPPlayerBox:AddToggle('GateAssistTP', {
    Text = 'Gate-assist TP (bypass snapback)', Default = true,
    Tooltip = 'A cold TP gets snapped back, but a TP right after a REAL gate is accepted. So this casts a throwaway gate to the cover area below, waits for it to land, then instantly TPs you onto the selected player. Costs 1 mana + the gate cooldown (~5s) and needs the Gate spell in your hotbar. Only affects Teleport-to-Player. Do NOT run it together with Gate-kill.',
})
TPPlayerBox:AddInput('GateCoverArea', {
    Text = 'Cover area', Default = 'arena', Finished = true, Placeholder = 'arena',
    Tooltip = 'Which area the throwaway gate goes to before the real TP. Any gate-able area works (arena, desert, tundra, forest, deepforest, ...). Change it if you cannot gate to arena.',
})
TPPlayerBox:AddButton({ Text = 'Charge mana (test)', Func = function() if manaChargeTest then manaChargeTest() end end })
TPPlayerBox:AddButton({ Text = 'Teleport to player', Func = function() tpToPlayer() end })
    :AddButton({ Text = 'Refresh list', Func = function() refreshTPPlayers() end })
TPPlayerBox:AddLabel('Teleport key'):AddKeyPicker('TPKey', {
    Default = 'T', Mode = 'Toggle', Text = 'Teleport to player',
})
TPPlayerBox:AddButton({ Text = 'Stop teleport (cancel glide)', Func = function() if cancelTP then cancelTP() end end })
TPPlayerBox:AddLabel('Stop TP key'):AddKeyPicker('StopTPKey', {
    Default = 'X', Mode = 'Toggle', Text = 'Stop teleport',
    Tooltip = 'Instantly cancel any in-flight teleport/area/coord glide and stay put.',
})

local TPAreaBox = Tabs.Teleport:AddRightGroupbox('Area Warp')
TPAreaBox:AddLabel('Rogue Lineage: reads workspace.AreaMarkers\nand drops you into the chosen area.', true)
TPAreaBox:AddDropdown('WarpArea', {
    Values = {}, Default = nil, Multi = false, AllowNull = true,
    Text = 'Area', Tooltip = 'Areas found in workspace.AreaMarkers',
})
TPAreaBox:AddToggle('GateAssistWarp', {
    Text = 'Gate-assist warp (bypass snapback)', Default = true,
    Tooltip = 'Cast a throwaway gate to the cover area (set in the Teleport-to-Player box) first, then instant-TP into the chosen area so the server does not snap you back. Costs 1 mana + the ~5s gate cooldown + needs the Gate spell. Turn OFF to use the plain Instant/Glide teleport instead.',
})
TPAreaBox:AddButton({ Text = 'Warp to area', Func = function() warpToArea() end })
    :AddButton({ Text = 'Refresh areas', Func = function() refreshTPAreas() end })

local TPCoordBox = Tabs.Teleport:AddLeftGroupbox('Coordinates')
TPCoordBox:AddLabel('Paste an X Y Z position (spaces or commas)\nand glide there - handy for trinket spots.', true)
TPCoordBox:AddInput('TPCoords', {
    Text = 'X Y Z', Default = '', Finished = true, Placeholder = '5743.4 328.584 647.925',
    Tooltip = 'Three numbers separated by spaces or commas.',
})
TPCoordBox:AddButton({ Text = 'Teleport to coords', Func = function() if coordTeleport then coordTeleport() end end })
    :AddButton({ Text = 'Copy my position', Func = function() if copyMyPos then copyMyPos() end end })

local GateBox = Tabs.Teleport:AddLeftGroupbox('Gate Redirect')
GateBox:AddLabel('Pick a person -> gate onto them (SKIPPED if you\nare already within ~18 studs -> then it is ONE gate,\nno 5s wait) -> stay glued -> cast a gate that DRAGS\nthem: the game warps any conscious player within 20\nstuds that touches your gate (confirmed in the dump).\n\nThey land at the COVER AREA (the gate destination, set\nin Teleport-to-Player), not the exact kill brick - YOU\npeel off to the kill brick. For an exact-lava kill use\nAuto Gate -> Kill (grab). Keep No Kill Bricks on.', true)
local GateKillStatus = GateBox:AddLabel('Idle')
GateBox:AddDropdown('GateRedirectTarget', {
    Values = {}, Default = nil, Multi = false, AllowNull = true, Text = 'Target',
    Tooltip = 'Who to gate onto first. Filled from the players in the server; the Teleport-to-Player "Refresh list" also refreshes it.',
})
GateBox:AddDropdown('GateKillName', {
    Values = { 'Nearest (any)', 'Lava', 'Abyss Void', 'PITBASE', 'ArdorianKillbrick', 'Killbrick', 'KillPart', 'Trap' },
    Default = 1, Multi = false, Text = 'Kill brick',
    Tooltip = '"Nearest (any)" picks the closest known instakill part; or force a specific one. Lava is baked to its known coord (it is unnamed terrain, so a name scan misses it).',
})
GateBox:AddButton({ Text = 'Run gate-kill', Func = function() if runGateKill then runGateKill() end end })
GateBox:AddLabel('Gate-kill key'):AddKeyPicker('GateKillKey', {
    Default = 'H', Mode = 'Toggle', Text = 'Gate kill',
})

local TPJoinBox = Tabs.Teleport:AddRightGroupbox('Join by Username')
TPJoinBox:AddLabel('Follow a player into THEIR server by username.\nOnly works if their join privacy lets you in\n(friends, or everyone) - a private join can\'t be\nresolved. A UserId works too.', true)
TPJoinBox:AddInput('JoinUsername', {
    Text = 'Username', Default = '', Finished = true, Placeholder = 'their username or UserId',
    Tooltip = 'Exact username (or a numeric UserId), then press the button.',
})
local JoinStatus = TPJoinBox:AddLabel('Idle')
TPJoinBox:AddButton({ Text = 'Join their server', Func = function() if joinByUsername then joinByUsername() end end })

-- ---- Find Player Server: PlaceId + Username -> find their job instance -------
-- Two ways to locate which running server a user is in, best-first:
--   1) PRESENCE (reliable): POST presence.roblox.com/v1/presence/users. The
--      executor's request() attaches your Roblox cookie, so the response's
--      `gameId` IS the jobId - IF the target's join privacy lets you see it
--      (Everyone, or Friends when you're friends). Then TeleportToPlaceInstance.
--   2) THUMBNAIL SCAN (best-effort fallback for private joins): if presence
--      returns no gameId, walk the Place ID's PUBLIC server list
--      (games.roblox.com/.../servers/Public) and match the target's avatar
--      headshot to a server's playerToken via thumbnails.roblox.com/v1/batch
--      (imageUrl is identical whether queried by userId or by that user's token).
--      HONEST LIMITS (dump/API-verified): Roblox CAPS playerTokens at ~5 per
--      server and empties the players[] list, so if the target isn't one of the
--      ~5 exposed tokens in their server we simply can't see them; and a truly
--      private/friends-only server never appears in the Public list at all. So
--      this fallback finds people in PUBLIC servers only, and even then can miss.
-- Whole feature is ONE IIFE => zero persistent top-level locals (200-cap safe).
;(function()
    local req = (syn and syn.request) or (http and http.request) or http_request or request
    local TeleportService = Teleport
    local PRESENCE_URL = 'https://presence.roblox.com/v1/presence/users'
    local THUMB_URL    = 'https://thumbnails.roblox.com/v1/batch'
    local SIZE, FMT    = '150x150', 'Png'      -- MUST match between userId + token queries

    local FindBox = Tabs.Teleport:AddRightGroupbox('Find Player Server')
    FindBox:AddLabel('Find which server a user is in (Place ID + username),\nthen join it. Presence finds the EXACT server if their\njoin privacy allows; otherwise it scans the PUBLIC server\nlist and matches their avatar thumbnail. Honest limit:\nRoblox now hides most players from the server list, so the\nthumbnail scan only finds people in PUBLIC servers and can\nstill miss - presence is the reliable path.', true)
    FindBox:AddInput('FindSrvPlace', {
        Text = 'Place ID', Default = tostring(game.PlaceId), Finished = true,
        Placeholder = 'place id (blank = this game)',
        Tooltip = 'The game\'s Place ID (the number in the game page URL). Drives the public-server scan + the join. Blank = the game you are in now.',
    })
    FindBox:AddButton({ Text = 'Copy this Place ID', Func = function()
        local pid = tostring(game.PlaceId)
        if setclipboard then pcall(setclipboard, pid) end
        if Options.FindSrvPlace then Options.FindSrvPlace:SetValue(pid) end -- also drop it into the box
        Library:Notify('Copied Place ID: ' .. pid, 4)
    end })
    FindBox:AddInput('FindSrvUser', {
        Text = 'Username', Default = '', Finished = true, Placeholder = 'username or UserId',
        Tooltip = 'Target\'s exact username, or their numeric UserId.',
    })
    FindBox:AddToggle('FindSrvThumb', {
        Text = 'Thumbnail scan (private joins)', Default = true,
        Tooltip = 'If presence will not hand over the server (private/friends-only join), scan the Place ID\'s PUBLIC servers and match the target\'s avatar thumbnail. Slower, rate-limited, and only finds players sitting in PUBLIC servers.',
    })
    FindBox:AddSlider('FindSrvPages', {
        Text = 'Scan pages', Default = 8, Min = 1, Max = 40, Rounding = 0,
        Tooltip = 'Thumbnail scan only: how many pages (x100 servers) of the public list to sweep before giving up. Higher = more thorough but more likely to hit Roblox rate limits (429).',
    })
    local FindStatus = FindBox:AddLabel('Idle')

    local foundPlace, foundJob = nil, nil   -- captured for Join + Copy buttons
    local scanning = false
    local csrf = nil
    local function setStatus(s) if FindStatus then FindStatus:SetText(s) end end

    -- Authed JSON request with one-shot 403/X-CSRF-TOKEN refresh + 429 backoff.
    -- Returns decoded JSON on 2xx, else nil + a short error tag.
    local function httpReq(method, url, bodyTbl)
        if not req then return nil, 'nohttp' end
        local body = bodyTbl and HttpServ:JSONEncode(bodyTbl) or nil
        for attempt = 1, 4 do
            local headers = { ['Content-Type'] = 'application/json' }
            if csrf then headers['X-CSRF-TOKEN'] = csrf end
            local ok, res = pcall(req, { Url = url, Method = method, Body = body, Headers = headers })
            if not ok or not res then return nil, 'reqfail' end
            local status = res.StatusCode or res.Status or res.status_code or 0
            if status == 403 then
                local h = res.Headers or res.headers or {}
                local tok = h['x-csrf-token'] or h['X-CSRF-Token'] or h['X-CSRF-TOKEN']
                if tok and tok ~= csrf then csrf = tok -- refresh + retry once more
                else return nil, 'forbidden' end
            elseif status == 429 then
                task.wait(1.5 * attempt)               -- throttled -> back off + retry
            elseif status >= 200 and status < 300 then
                local okD, data = pcall(function() return HttpServ:JSONDecode(res.Body) end)
                if okD then return data end
                return nil, 'baddata'
            else
                return nil, 'http' .. tostring(status)
            end
        end
        return nil, 'retries'
    end

    local function resolveUser(raw)
        raw = tostring(raw or ''):gsub('^%s+', ''):gsub('%s+$', '')
        if raw == '' then return nil end
        local id = tonumber(raw)
        if id then return id, raw end
        local ok, uid = pcall(function() return Players:GetUserIdFromNameAsync(raw) end)
        if ok and uid then return uid, raw end
        return nil
    end

    local function presenceOf(userId)
        local data = httpReq('POST', PRESENCE_URL, { userIds = { userId } })
        return data and data.userPresences and data.userPresences[1] or nil
    end

    -- Reference headshot for the target (by userId). Retried once for a Pending render.
    local function refHeadshot(userId)
        for _ = 1, 2 do
            local data = httpReq('POST', THUMB_URL, {
                { requestId = 'ref', type = 'AvatarHeadShot', targetId = userId, size = SIZE, format = FMT, isCircular = false },
            })
            local item = data and data.data and data.data[1]
            if item and item.state == 'Completed' and item.imageUrl then return item.imageUrl end
            task.wait(0.5)
        end
        return nil
    end

    -- Resolve a token list -> { token = imageUrl } (Completed only), 100/batch.
    local function resolveTokens(tokens)
        local out, i = {}, 1
        while i <= #tokens do
            local batch, map = {}, {}
            for j = i, math.min(i + 99, #tokens) do
                local rid = tostring(j)
                batch[#batch + 1] = { requestId = rid, token = tokens[j], type = 'AvatarHeadShot', size = SIZE, format = FMT, isCircular = false }
                map[rid] = tokens[j]
            end
            local data = httpReq('POST', THUMB_URL, batch)
            if data and data.data then
                for _, item in ipairs(data.data) do
                    if item.state == 'Completed' and item.imageUrl and item.requestId then
                        local tk = map[item.requestId]
                        if tk then out[tk] = item.imageUrl end
                    end
                end
            end
            i = i + 100
            task.wait(0.1)
        end
        return out
    end

    -- Walk the place's PUBLIC servers, match the target headshot -> return jobId.
    local function thumbScan(userId, placeId)
        local refUrl = refHeadshot(userId)
        if not refUrl then setStatus('Could not load target thumbnail'); return nil end
        local maxPages = math.floor((Options.FindSrvPages and Options.FindSrvPages.Value) or 8)
        local cursor, page, servers = nil, 0, 0
        while page < maxPages do
            page = page + 1
            local url = ('https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&excludeFullGames=false&limit=100'):format(tostring(placeId))
            if cursor then url = url .. '&cursor=' .. cursor end
            local data = httpReq('GET', url)
            if not data or not data.data then
                setStatus(('Scan stopped at page %d (no data / rate limited)'):format(page)); return nil
            end
            local tokens, tokJob = {}, {}
            for _, s in ipairs(data.data) do
                servers = servers + 1
                if type(s.playerTokens) == 'table' then
                    for _, tk in ipairs(s.playerTokens) do
                        if tokJob[tk] == nil then tokens[#tokens + 1] = tk; tokJob[tk] = s.id end
                    end
                end
            end
            setStatus(('Scanning: page %d, %d servers, %d visible avatars...'):format(page, servers, #tokens))
            local urls = resolveTokens(tokens)
            for tk, u in pairs(urls) do
                if u == refUrl then return tokJob[tk] end   -- match -> that server's jobId
            end
            cursor = data.nextPageCursor
            if not cursor then
                setStatus(('Swept all %d public servers - target not among visible players'):format(servers)); return nil
            end
            task.wait(0.15)
        end
        setStatus(('Swept %d servers (page cap) - not found. Raise Scan pages, or they are in a private server'):format(servers))
        return nil
    end

    -- Find the target's server. Returns true if foundJob/foundPlace are set.
    local function doFind()
        foundPlace, foundJob = nil, nil
        local userId, uname = resolveUser(Options.FindSrvUser and Options.FindSrvUser.Value)
        if not userId then setStatus('Enter a username / UserId'); Library:Notify('Find: enter a username or UserId', 3); return false end
        if not req then setStatus('No HTTP function'); Library:Notify('Executor has no request() - cannot look up servers', 6); return false end

        setStatus('Looking up ' .. uname .. ' presence...')
        local pres = presenceOf(userId)
        if not pres then setStatus('Presence lookup failed (rate limited / no cookie?)'); Library:Notify('Presence lookup failed', 5); return false end
        if pres.userPresenceType ~= 2 then
            setStatus(uname .. ' is not in a game')
            Library:Notify(uname .. ' is not currently in a game', 4); return false
        end
        -- In-game. gameId present = presence handed us the exact server.
        if pres.gameId then
            foundPlace, foundJob = pres.placeId or game.PlaceId, pres.gameId
            setStatus('Found (presence): ' .. tostring(pres.gameId))
            Library:Notify('Found ' .. uname .. "'s server (presence). Copy/Join ready.", 5)
            return true
        end
        -- Private join: no gameId. Thumbnail scan fallback (if enabled).
        if not (Toggles.FindSrvThumb and Toggles.FindSrvThumb.Value) then
            setStatus(uname .. "'s join is private (no jobId) - enable Thumbnail scan")
            Library:Notify(uname .. "'s join is private - enable Thumbnail scan to try public servers", 6); return false
        end
        local typedPlace = tonumber(tostring(Options.FindSrvPlace and Options.FindSrvPlace.Value or ''):match('%d+'))
        local scanPlace = typedPlace or pres.placeId or game.PlaceId
        setStatus(uname .. "'s join is private - scanning public servers of place " .. tostring(scanPlace) .. '...')
        local job = thumbScan(userId, scanPlace)
        if job then
            foundPlace, foundJob = scanPlace, job
            setStatus('Found (thumbnail): ' .. tostring(job))
            Library:Notify('Found ' .. uname .. "'s server by thumbnail match. Copy/Join ready.", 5)
            return true
        end
        return false
    end

    local function doJoin()
        if not foundJob then Library:Notify('Find a server first', 3); return end
        local place = foundPlace or tonumber(tostring(Options.FindSrvPlace and Options.FindSrvPlace.Value or ''):match('%d+')) or game.PlaceId
        setStatus('Joining ' .. tostring(foundJob) .. '...')
        Library:Notify('Joining server ' .. tostring(foundJob), 4)
        local ok, err = pcall(function()
            TeleportService:TeleportToPlaceInstance(place, foundJob, LocalPlayer)
        end)
        if not ok then setStatus('Teleport failed'); Library:Notify('Teleport failed: ' .. tostring(err), 6) end
    end

    FindBox:AddButton({ Text = 'Find instance', Func = function()
        if scanning then Library:Notify('Already searching...', 2); return end
        scanning = true
        task.spawn(function() pcall(doFind); scanning = false end)
    end }):AddButton({ Text = 'Join found server', Func = function() task.spawn(doJoin) end })
    FindBox:AddButton({ Text = 'Copy instance id', Func = function()
        if not foundJob then Library:Notify('No instance id yet - Find first', 3); return end
        if setclipboard then pcall(setclipboard, tostring(foundJob)) end
        Library:Notify('Copied jobId: ' .. tostring(foundJob), 4)
    end })
    FindBox:AddLabel('Find + join key'):AddKeyPicker('FindSrvKey', {
        Default = 'None', Mode = 'Toggle', Text = 'Find + join server',
    })
    if Options.FindSrvKey then
        Options.FindSrvKey:OnClick(function()
            if scanning then return end
            scanning = true
            task.spawn(function()
                local pcallOk, found = pcall(doFind)
                scanning = false
                if pcallOk and found then doJoin() end
            end)
        end)
    end
end)() -- end Find Player Server IIFE

-- ---- logic ----
-- Glide the root to a goal CFrame at a bounded speed instead of snapping there.
-- Small per-frame CFrame steps + noclip = continuous movement the server does
-- NOT rubber-band (an instant jump gets reconciled back ~1s later). A generation
-- counter makes a new teleport cancel any glide already in flight.
local tpGen = 0
local lastSelfTP = 0 -- timestamp of our last SELF-initiated teleport, so the gate
                     -- redirect's jump-detector ignores OUR jumps (only a real gate warp fires it)
local function tpGlide(goalCF)
    if not getRoot() then Library:Notify('No character to teleport', 2); return end
    tpGen = tpGen + 1
    lastSelfTP = os.clock()
    local myGen = tpGen
    task.spawn(function()
        local goalPos, rot = goalCF.Position, goalCF.Rotation
        local nocliped = setmetatable({}, { __mode = 'k' }) -- weak: dead-char parts GC out
        local t0 = os.clock()
        local bestDist, lastProgress = math.huge, os.clock()
        -- Re-fetch the character EVERY frame. Crossing an area boundary can
        -- swap/reload your character OR the game yanks you (TPtoNonCliff snaps you
        -- to safe ground). Capturing root ONCE made the loop abort the instant
        -- that happened - hence "it doesn't continue". Now we resume from wherever
        -- we land, wait through any frame the character is briefly gone, and give
        -- up cleanly only if we genuinely stop making progress for a few seconds.
        while tpGen == myGen and (os.clock() - t0) <= 60 do
            local dt = RunService.RenderStepped:Wait()
            if tpGen ~= myGen then break end
            local root = getRoot()
            if not (root and root.Parent) then
                lastProgress = os.clock() -- character loading in - don't count as stuck
            else
                local pos = root.Position
                local delta = goalPos - pos
                local dist = delta.Magnitude
                if dist <= 2 then break end -- arrived
                if dist < bestDist - 1 then bestDist = dist; lastProgress = os.clock() end
                if os.clock() - lastProgress > 4 then break end -- stuck being yanked -> stop
                local char = getChar()
                if char then
                    for _, p in ipairs(char:GetDescendants()) do
                        if p:IsA('BasePart') and p.CanCollide then p.CanCollide = false; nocliped[p] = true end
                    end
                end
                local step = math.min(dist, math.max(1, Options.TPGlideSpeed.Value) * dt)
                root.CFrame = rot + (pos + delta.Unit * step) -- keep goal facing, step the position
                root.AssemblyLinearVelocity = Vector3.zero
                local hum = getHumanoid()
                if hum and hum:GetState() == Enum.HumanoidStateType.Freefall then
                    pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
                end
            end
        end
        local root = getRoot()
        if tpGen == myGen and root and root.Parent then
            root.CFrame = goalCF
            root.AssemblyLinearVelocity = Vector3.zero
        end
        for p in pairs(nocliped) do if p.Parent then pcall(function() p.CanCollide = true end) end end
    end)
end
-- Cancel any in-flight glide: bumping the generation makes the running glide
-- loop's `tpGen == myGen` guard fail, so it exits and restores collisions.
cancelTP = function()
    tpGen = tpGen + 1
    Library:Notify('Teleport cancelled', 1.5)
end

-- ---- Instant teleport via the game's OWN "TPSafe" whitelist -----------------
-- Every long teleport the game itself does (Gate / Celeritas / Wrathful Leap)
-- drops a Vector3Value named "TPSafe" (Value = destination position) on the
-- Character right BEFORE it sets HumanoidRootPart.CFrame. That value is the token
-- the SERVER anti-cheat (Nemesis) reads to say "this jump is legit, don't snap it
-- back". We create the identical value on our own character, so a single instant
-- CFrame set to ANY point sticks - no gliding. Verified in the dump:
--   Gate/Activator.lua:497-515  (TPSafe.Value = dest, then HRP.CFrame = dest)
--   Wrathful Leap/Activator.lua:110-114 (same idiom)
-- We also own our own HRP (no SetNetworkOwner on characters, no position remote),
-- so the client CFrame write is authoritative; TPSafe just stops the snapback.
local function tpSafeMark(char, pos)
    if not char then return end
    local v = Instance.new('Vector3Value')
    v.Name = 'TPSafe'
    v.Value = pos
    v.Parent = char
    game:GetService('Debris'):AddItem(v, 4) -- same ~4s lifetime the game uses
    return v
end
-- Reject NaN / absurd coords - huge or NaN CFrames are what actually get you kicked.
local function finiteCF(cf)
    local p = cf.Position
    if p ~= p then return false end -- NaN
    return math.abs(p.X) < 1e6 and math.abs(p.Y) < 1e6 and math.abs(p.Z) < 1e6
end
-- Instant teleport: whitelist with TPSafe, then set CFrame in the SAME frame.
local function tpInstant(goalCF)
    local char, root = getChar(), getRoot()
    if not (char and root) then Library:Notify('No character to teleport', 2); return end
    if not finiteCF(goalCF) then Library:Notify('Teleport target invalid (out of range)', 3); return end
    tpGen = tpGen + 1              -- cancel any in-flight glide
    lastSelfTP = os.clock()
    tpSafeMark(char, goalCF.Position)
    local hum = getHumanoid()
    if not (hum and (hum.SeatPart or hum.Sit)) then -- same guard the Gate uses
        root.CFrame = goalCF
        root.AssemblyLinearVelocity = Vector3.zero
    end
end
-- Dispatcher honoured by every teleport below: Instant TP toggle on = TPSafe
-- instant (default), off = the old bounded glide.
local function tpMove(goalCF)
    if Toggles.InstantTP and Toggles.InstantTP.Value then tpInstant(goalCF) else tpGlide(goalCF) end
end

-- ---- Gate-assist teleport: bypass the cold-TP snapback ----------------------
-- A cold TP (just setting CFrame, even with a client-made TPSafe) gets snapped
-- back by the server AC. But a TP RIGHT AFTER a real gate is accepted - the gate
-- opens the AC's grace window. So we cast a real throwaway gate to a cover area,
-- wait for it to land (it drops a "NoFall" folder), then instant-TP to the real
-- target inside that window. Costs 1 mana + the gate cooldown, needs the Gate spell.
-- Charge mana via the game's OWN "SetManaChargeState" remote - this is the "hold
-- G to charge" mechanic. The game fires it through a CACHED FireServer (direct
-- call), which is exactly why it never shows up in RemoteSpy (RemoteSpy only sees
-- __namecall). Firing true starts the charge, false stops it; the server builds
-- Character.Mana (0-100) while it's true. Returns the final Mana.Value.
--   Remote:  Character.CharacterHandler.Remotes.SetManaChargeState  (Input.lua:1724)
--   Mana:    Character.Mana (NumberValue, 0-100 - Input.lua:118, /100 at :949)
-- Resolve the character that actually holds CharacterHandler/Remotes/Mana. RL
-- parents the real character at workspace.Live.<username> - that's exactly where
-- RemoteSpy found the charge remote (workspace.Live.<name>.CharacterHandler.
-- Remotes.SetManaChargeState). LocalPlayer.Character did NOT resolve to it here,
-- which is why the earlier fire hit the wrong object and nothing charged.
local function manaChar()
    local live = workspace:FindFirstChild('Live') or workspace:FindFirstChild('Alive')
    local byName = live and live:FindFirstChild(LocalPlayer.Name)
    if byName and byName:FindFirstChild('CharacterHandler') then return byName end
    local c = getChar()
    if c and c:FindFirstChild('CharacterHandler') then return c end
    return byName or c
end
local function chargeMana(target, timeout)
    local char = manaChar()
    if not char then Library:Notify('Gate-assist: character not found', 4); return 0 end
    local ch = char:FindFirstChild('CharacterHandler')
    local rem = ch and ch:FindFirstChild('Remotes')
    local setCharge = rem and rem:FindFirstChild('SetManaChargeState')
    local mana = char:FindFirstChild('Mana')
    if not setCharge then Library:Notify('Gate-assist: SetManaChargeState remote not found', 5); return mana and mana.Value or 0 end
    if not mana then Library:Notify('Gate-assist: no Mana object on character', 4); return 0 end
    if mana.Value >= target then return mana.Value end
    -- Fire the EXACT call RemoteSpy captured from holding G: SetManaChargeState
    -- :FireServer(true) to charge, (false) to stop. Fire true ONCE and HOLD (never
    -- early-cancel) while the server builds Character.Mana, then release.
    local before = mana.Value
    pcall(function() print('[GateAssist] charge remote = ' .. setCharge:GetFullName()) end)
    pcall(function() setCharge:FireServer(true) end)
    local t0 = os.clock()
    repeat RunService.Heartbeat:Wait() until mana.Value >= target or (os.clock() - t0 > (timeout or 6))
    pcall(function() setCharge:FireServer(false) end)
    print(('[GateAssist] mana %.1f -> %.1f (target %d, %.1fs)'):format(before, mana.Value, target, os.clock() - t0))
    return mana.Value
end
-- Standalone test: charge for ~3s and report the mana delta, so you can verify
-- charging works on its own (separate from the whole gate-assist flow).
manaChargeTest = function()
    task.spawn(function()
        local m0 = manaChar()
        local mv = m0 and m0:FindFirstChild('Mana')
        local before = mv and mv.Value or 0
        Library:Notify(('Charging mana 3s (from %.0f)...'):format(before), 2)
        local m = chargeMana(999, 3) -- target unreachable -> charges the full 3s
        Library:Notify(('Mana now %.0f (was %.0f) - check console'):format(m, before), 5)
    end)
end

local function castGate(area, manaTarget)
    local char = manaChar()
    local hum = char and char:FindFirstChildOfClass('Humanoid')
    if not (char and hum) then return false end
    -- Cooldown gate: the server rejects a cast while you hold the "SnapCool" tag
    -- (added for 5s after each gate - Gate/Activator.lua:72,113-118).
    if game:GetService('CollectionService'):HasTag(char, 'SnapCool') then
        Library:Notify('Gate on cooldown (~5s) - try again in a moment', 3); return false
    end
    local gate = char:FindFirstChild('Gate')
        or (LocalPlayer:FindFirstChild('Backpack') and LocalPlayer.Backpack:FindFirstChild('Gate'))
    if not gate then Library:Notify('Gate-assist: no "Gate" spell in your hotbar', 4); return false end
    -- CHARGE MANA FIRST. The gate needs Mana.Value >= its cost (1 - Gate/
    -- Activator.lua:12,109). manaTarget is a small buffer over the cost; callers
    -- that want SPEED pass a low value (gate-kill uses ~10 so the cast fires in
    -- ~0.4s instead of ~1.7s). Defaults to a safe 40 for the gate-assist TP.
    local finalMana = chargeMana(manaTarget or 40, 6)
    if finalMana < 1 then
        Library:Notify('Gate-assist: could not charge mana (sheath your weapon?)', 4)
        -- fall through and try anyway; the server makes the final call
    end
    -- Equip, then RIGHT-CLICK to open the "type a gate location" box. gate:Activate()
    -- does NOT open the gate in RL - the real activation is the RightClick remote
    -- (Character.CharacterHandler.Remotes.RightClick:FireServer(true), captured via
    -- RemoteSpy). We keep it held (true) until the destination is submitted.
    pcall(function() hum:EquipTool(gate) end)
    task.wait(0.15)
    local rem = char:FindFirstChild('CharacterHandler') and char.CharacterHandler:FindFirstChild('Remotes')
    local rc = rem and rem:FindFirstChild('RightClick')
    if not rc then Library:Notify('Gate-assist: RightClick remote not found', 4); return false end
    pcall(function() rc:FireServer(true) end)

    -- SUBMIT THE DESTINATION (dump-accurate). From Gate/Activator.lua: the server
    -- clones "GateGUI" into our PlayerGui and creates a RemoteEvent named
    -- "GateRemote" inside it, then does GateRemote.OnServerEvent:Once expecting a
    -- STRING (the destination). So the ONE thing that submits a gate is:
    --     GateRemote:FireServer(area)
    -- The TextBox and the "type in chat" path are just two client-side ways to
    -- fire that SAME remote - we need neither. (OLD BUG: the poll broke on `box or
    -- timeout`, IGNORING the remote, so it waited 2.5s for a TextBox that might
    -- never resolve, timed out, spammed "type-box did not open", and left the gate
    -- GUI hanging -> the loop/mess. It still landed because you typed in chat.)
    local pg = LocalPlayer:FindFirstChild('PlayerGui')
    local g0, gateRemote = os.clock(), nil
    repeat
        task.wait()
        if pg then
            local gui = pg:FindFirstChild('GateGUI') or pg:FindFirstChild('Gate')
            if gui then gateRemote = gui:FindFirstChild('GateRemote', true) end
            if not gateRemote then
                -- Definitive signal regardless of the GUI's name: the RemoteEvent
                -- literally named "GateRemote" sitting in our PlayerGui.
                for _, d in ipairs(pg:GetDescendants()) do
                    if d:IsA('RemoteEvent') and d.Name == 'GateRemote' then gateRemote = d; break end
                end
            end
        end
    until gateRemote or (os.clock() - g0 > 4)
    if not gateRemote then
        pcall(function() rc:FireServer(false) end)
        Library:Notify('Gate-assist: gate did not open (RightClick didn\'t register / on cooldown / no Gate spell?)', 4)
        return false
    end
    -- Fire the destination string. The server's Once-handler reads it, closes the
    -- GUI itself (clone:Destroy), and resolves the warp - so we don't touch the
    -- TextBox at all (that avoids stealing focus / the on-screen keyboard).
    pcall(function() gateRemote:FireServer(area) end)
    task.wait(0.05)
    pcall(function() rc:FireServer(false) end) -- release right-click
    return true
end
-- Cast a cover gate, wait for it to land, then TP to the target. `goalOrFn` is a
-- CFrame OR a function returning the fresh target CFrame (so a moving player is
-- re-resolved AFTER the gate detour, not at button-press time).
local function gateThenTP(goalOrFn)
    task.spawn(function()
        local char = getChar()
        local landed = false
        local conn = char and char.ChildAdded:Connect(function(c)
            if c.Name == 'NoFall' then landed = true end
        end)
        local area = tostring((Options.GateCoverArea and Options.GateCoverArea.Value) or 'arena')
        if area:gsub('%s', '') == '' then area = 'arena' end
        Library:Notify('Gate-assist: casting cover gate...', 2)
        local fired = castGate(area)
        -- Wait for the gate to actually land (NoFall drop), up to 4s. Keep
        -- lastSelfTP fresh so the gate-redirect detector ignores this cover gate.
        local t0 = os.clock()
        repeat
            RunService.Heartbeat:Wait()
            lastSelfTP = os.clock()
        until landed or (os.clock() - t0 > 4)
        if conn then conn:Disconnect() end
        if not landed then
            -- The gate never fired/landed (no mana, on cooldown, or no Gate spell).
            -- Do NOT teleport - without the gate's grace window a cold TP just
            -- snaps straight back, so it's pointless. Bail and tell you why.
            Library:Notify(fired and 'Gate did not land (on cooldown?) - NOT teleporting'
                or 'Gate did not fire (mana / no Gate spell?) - NOT teleporting', 5)
            return
        end
        task.wait(0.6) -- the same grace window the working gate-redirect uses
        local goalCF = (type(goalOrFn) == 'function') and goalOrFn() or goalOrFn
        if goalCF and finiteCF(goalCF) then
            tpInstant(goalCF)
            Library:Notify('Gate-assist -> teleported', 2)
        else
            Library:Notify('Gate-assist: target no longer available', 3)
        end
    end)
end

-- Raycast down so area warps land ON the map, not inside a ceiling marker.
local function tpGround(pos)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { getChar() }
    local hit = workspace:Raycast(pos + Vector3.new(0, 50, 0), Vector3.new(0, -5000, 0), params)
    return (hit and hit.Position or pos) + Vector3.new(0, 4, 0)
end

refreshTPPlayers = function()
    local names = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then names[#names + 1] = p.Name end
    end
    table.sort(names)
    Options.TPTarget:SetValues(names)
    if Options.GateTarget then Options.GateTarget:SetValues(names) end -- combo target dropdown
    if Options.GateRedirectTarget then Options.GateRedirectTarget:SetValues(names) end -- gate-kill target
end
tpToPlayer = function()
    local name = Options.TPTarget.Value
    if not name or name == '' then Library:Notify('Pick a player first', 2); return end
    local p = Players:FindFirstChild(name)
    if not (p and p.Character and p.Character:FindFirstChild('HumanoidRootPart')) then
        Library:Notify(name .. ' is not spawned', 2); return
    end
    local off = Options.TPOffset.Value
    -- Resolve the destination LAZILY so gate-assist re-reads the (possibly moved)
    -- target after the gate detour, not at button-press time.
    local function goal()
        local r = p.Character and p.Character:FindFirstChild('HumanoidRootPart')
        if not r then return nil end
        if Toggles.TPBehind.Value then
            local behind = (r.CFrame * CFrame.new(0, 0, off)).Position
            return CFrame.lookAt(behind, r.Position)
        end
        return r.CFrame * CFrame.new(0, 0, off)
    end
    if Toggles.GateAssistTP and Toggles.GateAssistTP.Value then
        gateThenTP(goal)
    else
        local g = goal(); if g then tpMove(g) end
    end
end

refreshTPAreas = function(silent)
    local folder = workspace:FindFirstChild('AreaMarkers')
    local names, seen = {}, {}
    if folder then
        for _, m in ipairs(folder:GetChildren()) do
            if not seen[m.Name] then seen[m.Name] = true; names[#names + 1] = m.Name end
        end
    end
    table.sort(names)
    Options.WarpArea:SetValues(names)
    if #names == 0 and not silent then Library:Notify('No workspace.AreaMarkers here (Rogue Lineage only)', 3) end
end
warpToArea = function()
    local name = Options.WarpArea.Value
    if not name or name == '' then Library:Notify('Pick an area first', 2); return end
    local folder = workspace:FindFirstChild('AreaMarkers')
    local marker = folder and folder:FindFirstChild(name)
    if not marker then Library:Notify('Area marker gone - Refresh areas', 2); return end
    local pos
    if marker:IsA('BasePart') then pos = marker.Position
    elseif marker:IsA('Model') then pos = marker:GetPivot().Position end
    if not pos then Library:Notify('Could not resolve area position', 2); return end
    local goalCF = CFrame.new(tpGround(pos))
    if Toggles.GateAssistWarp and Toggles.GateAssistWarp.Value then
        gateThenTP(goalCF) -- cover gate -> land -> instant-TP into the area (no snapback)
    else
        tpMove(goalCF)
    end
    Library:Notify('Warping to ' .. name .. '...', 2)
end

coordTeleport = function()
    local nums = {}
    for n in tostring(Options.TPCoords.Value):gmatch('%-?%d*%.?%d+') do
        nums[#nums + 1] = tonumber(n)
    end
    if #nums < 3 then Library:Notify('Enter 3 numbers: X Y Z', 3); return end
    local x, y, z = nums[1], nums[2], nums[3]
    tpMove(CFrame.new(x, y, z))
    Library:Notify(('Teleporting to %.1f, %.1f, %.1f'):format(x, y, z), 2)
end
copyMyPos = function()
    local root = getRoot()
    if not root then Library:Notify('No character', 2); return end
    local p = root.Position
    local s = ('%.3f %.3f %.3f'):format(p.X, p.Y, p.Z)
    if Options.TPCoords then Options.TPCoords:SetValue(s) end -- drop it into the input
    if setclipboard then pcall(setclipboard, s) end
    Library:Notify('Position: ' .. s, 4)
end

-- Join a player's server by username (presence "follow"). Resolves username ->
-- UserId, then reads Roblox presence via the executor's AUTHENTICATED HTTP
-- (request/syn.request auto-attaches your Roblox cookies for *.roblox.com). The
-- server's jobId only comes back if the target's join privacy allows you in
-- (friends / everyone); a private join returns no jobId and we say so.
joinByUsername = function()
    local raw = tostring(Options.JoinUsername.Value or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if raw == '' then Library:Notify('Enter a username first', 3); return end
    local function setStatus(s) if JoinStatus then JoinStatus:SetText(s) end end
    local req = (syn and syn.request) or (http and http.request) or http_request or request
    if not req then
        setStatus('No HTTP function')
        Library:Notify('Executor has no request() - cannot look up presence', 6); return
    end
    task.spawn(function()
        -- 1) username -> UserId (a numeric input is used directly)
        local userId = tonumber(raw)
        if not userId then
            setStatus('Looking up ' .. raw .. '...')
            local ok, id = pcall(function() return Players:GetUserIdFromNameAsync(raw) end)
            if not ok or not id then
                setStatus('User not found')
                Library:Notify('No such username: ' .. raw, 4); return
            end
            userId = id
        end

        -- 2) presence lookup (POST, retried once with an X-CSRF token if asked)
        setStatus('Finding their server...')
        local url  = 'https://presence.roblox.com/v1/presence/users'
        local body = HttpServ:JSONEncode({ userIds = { userId } })
        local function doReq(token)
            local headers = { ['Content-Type'] = 'application/json' }
            if token then headers['X-CSRF-TOKEN'] = token end
            local ok, res = pcall(req, { Url = url, Method = 'POST', Body = body, Headers = headers })
            return ok and res or nil
        end
        local res = doReq()
        local status = res and (res.StatusCode or res.Status or res.status_code)
        if res and status == 403 then -- CSRF challenge -> grab token from headers, retry
            local h = res.Headers or res.headers or {}
            local token = h['x-csrf-token'] or h['X-CSRF-Token'] or h['X-CSRF-TOKEN']
            if token then res = doReq(token) end
        end
        if not res or not res.Body then
            setStatus('Presence request failed')
            Library:Notify('Presence request failed (executor HTTP blocked?)', 6); return
        end

        local ok, data = pcall(function() return HttpServ:JSONDecode(res.Body) end)
        local pres = ok and data and data.userPresences and data.userPresences[1]
        if not pres then
            setStatus('No presence data')
            Library:Notify('Could not read presence for ' .. raw, 5); return
        end
        -- userPresenceType: 0 offline, 1 online (site/app), 2 in-game, 3 studio
        if pres.userPresenceType ~= 2 or not pres.placeId then
            setStatus(raw .. ' is not in a game')
            Library:Notify(raw .. ' is not currently in a game', 5); return
        end
        if not pres.gameId then
            setStatus('Their join is private')
            Library:Notify(raw .. "'s join is private - must be friends or joins-on", 6); return
        end

        setStatus('Joining ' .. raw .. '...')
        Library:Notify('Joining ' .. raw .. "'s server...", 4)
        local tok, err = pcall(function()
            Teleport:TeleportToPlaceInstance(pres.placeId, pres.gameId, LocalPlayer)
        end)
        if not tok then
            setStatus('Teleport failed')
            Library:Notify('Teleport failed: ' .. tostring(err), 6)
        end
    end)
end

if Options.TPKey then Options.TPKey:OnClick(function() tpToPlayer() end) end
if Options.StopTPKey then Options.StopTPKey:OnClick(function() cancelTP() end) end

-- ---- Gate Kill: gate onto a chosen player, then gate to a chosen kill brick --
-- (Replaces the old passive gate-redirect.) Two gate-assist hops, each the SAME
-- working instant-TP-via-cover-gate method the Teleport tab uses:
--   1) gate-assist INSTANT-TP onto the selected player,
--   2) stay glued onto them (bounded follow) while the gate cooldown (SnapCool,
--      ~5s from hop 1) clears and mana recharges, then gate-assist INSTANT-TP to
--      the chosen kill brick.
-- HONEST: with no grab, a gate carries only YOU - from the dump a gate drags only
-- a GRABBED victim (Character.Grabbing.Value); proximity / standing on them does
-- not. So you land on the kill brick yourself (keep No Kill Bricks on / have a way
-- out). If the target does not come along, the Auto Gate -> Kill combo
-- (Experimental) with the Carry grab is the verified victim delivery.
do
    local CS = game:GetService('CollectionService')
    local gateKillBusy = false -- single-run guard: re-pressing while a run is in
                               -- flight is ignored (no stacked / "retrying" runs)
    -- Baked-in kill-brick spots (lava is terrain/unnamed, so a name scan misses
    -- it - hardcode known coords). Add more as you find them.
    local KNOWN_KILLBRICKS = {
        Lava = Vector3.new(5578.76, 332.685, 640.572), -- user-provided lava kill brick
        ['Abyss Void'] = Vector3.new(5041.62, 628.018, 956.8), -- user-provided abyss void
    }
    local KILLBRICK_NAMES = {
        PITBASE = true, ArdorianKillbrick = true, Killbrick = true, KillBrick = true,
        KillPart = true, KillBlock = true, DamageBrick = true, Lava = true,
        Trap = true, Spike = true, Spikes = true,
    }
    -- Position of the chosen kill brick: a baked coord wins (reliable), else scan
    -- the map for a named instakill part, else fall back to the nearest baked coord.
    local function findKillPos()
        local pick = (Options.GateKillName and Options.GateKillName.Value) or 'Nearest (any)'
        local root = getRoot(); local origin = root and root.Position or Vector3.zero
        if pick ~= 'Nearest (any)' and KNOWN_KILLBRICKS[pick] then return KNOWN_KILLBRICKS[pick] end
        local best, bestD
        local scanRoot = workspace:FindFirstChild('Map') or workspace
        for _, d in ipairs(scanRoot:GetDescendants()) do
            if d:IsA('BasePart') then
                local isKill = (pick == 'Nearest (any)') and KILLBRICK_NAMES[d.Name] or (d.Name == pick)
                if isKill then
                    local dd = (d.Position - origin).Magnitude
                    if not bestD or dd < bestD then best, bestD = d.Position, dd end
                end
            end
        end
        if best then return best end
        for _, pos in pairs(KNOWN_KILLBRICKS) do -- nothing named found -> nearest baked spot
            local dd = (pos - origin).Magnitude
            if not bestD or dd < bestD then best, bestD = pos, dd end
        end
        return best
    end

    local function setStatus(s) if GateKillStatus then GateKillStatus:SetText(s) end end

    -- One blocking gate-assist hop: cast a cover gate to the cover area, wait for
    -- it to LAND (drops a "NoFall" folder), grace, then TPSafe instant-TP to
    -- goalOrFn() (re-resolved after the detour). Returns true on success. Reuses
    -- the same castGate + NoFall-wait the Teleport-to-Player gate-assist uses.
    local function gateHop(goalOrFn, label, onLanded, manaTarget)
        local char = getChar()
        local landed = false
        -- onLanded fires the INSTANT the gate warps us (NoFall drops) - used to
        -- release the follow-glue exactly at the warp, not before, so we stay on
        -- the target through the whole cast.
        local conn = char and char.ChildAdded:Connect(function(c)
            if c.Name == 'NoFall' then landed = true; if onLanded then pcall(onLanded) end end
        end)
        local area = tostring((Options.GateCoverArea and Options.GateCoverArea.Value) or 'arena')
        if area:gsub('%s', '') == '' then area = 'arena' end
        if label then Library:Notify(label, 2) end
        local fired = castGate(area, manaTarget)
        local t0 = os.clock()
        repeat RunService.Heartbeat:Wait(); lastSelfTP = os.clock() until landed or (os.clock() - t0 > 4)
        if conn then conn:Disconnect() end
        if not landed then
            Library:Notify(fired and 'Gate did not land (on cooldown?)'
                or 'Gate did not fire (mana / no Gate spell?)', 5)
            return false
        end
        task.wait(0.6) -- the grace window the working gate-assist uses
        local goalCF = (type(goalOrFn) == 'function') and goalOrFn() or goalOrFn
        if goalCF and finiteCF(goalCF) then tpInstant(goalCF); return true end
        return false
    end

    runGateKill = function()
        if gateKillBusy then Library:Notify('Gate-kill: already running (let it finish)', 2); return end
        local name = Options.GateRedirectTarget and Options.GateRedirectTarget.Value
        if not name or name == '' then setStatus('Pick a person'); Library:Notify('Gate-kill: pick a person first', 3); return end
        local p = Players:FindFirstChild(name)
        if not p then for _, pl in ipairs(Players:GetPlayers()) do if pl.DisplayName == name then p = pl; break end end end
        if not (p and p.Character and p.Character:FindFirstChild('HumanoidRootPart')) then
            setStatus(tostring(name) .. ' not spawned'); Library:Notify(tostring(name) .. ' is not spawned', 3); return
        end
        local killPos = findKillPos()
        if not killPos then
            setStatus('No kill brick')
            Library:Notify('Gate-kill: no kill brick found for "' .. tostring(Options.GateKillName and Options.GateKillName.Value) .. '"', 4)
            return
        end
        local killCF = CFrame.new(killPos + Vector3.new(0, 3, 0)) -- land ON it

        gateKillBusy = true
        task.spawn(function()
            -- ONE follow loop glues us EXACTLY onto the target AND noclips our
            -- character so our collision can't push us off them. We sit perfectly
            -- aligned INSIDE them, so the gate (which spawns at US) spawns ON them
            -- and they touch it -> dragged. Without noclip, collision holds us a few
            -- studs away and the gate misses them. Bounded glide = server-accepted
            -- (no snapback). Runs from arrival through hop 2's whole cast; releases
            -- the instant the gate warps us. Collision restored at the end.
            local following = false
            local noclipped = setmetatable({}, { __mode = 'k' }) -- parts we set CanCollide=false
            local function glueOn()
                if following then return end
                following = true
                task.spawn(function()
                    while following do
                        local dt = RunService.RenderStepped:Wait()
                        if not following then break end
                        local myChar = getChar()
                        if myChar then -- noclip so we can overlap them exactly
                            for _, pt in ipairs(myChar:GetDescendants()) do
                                if pt:IsA('BasePart') and pt.CanCollide then pt.CanCollide = false; noclipped[pt] = true end
                            end
                        end
                        local r = p.Character and p.Character:FindFirstChild('HumanoidRootPart')
                        local myR = getRoot()
                        if r and myR then
                            -- glide to EXACTLY their position (noclip lets us sit inside them)
                            local toGoal = r.Position - myR.Position
                            local maxStep = 500 * dt
                            local newPos = (toGoal.Magnitude > maxStep) and (myR.Position + toGoal.Unit * maxStep) or r.Position
                            myR.CFrame = CFrame.new(newPos)
                            myR.AssemblyLinearVelocity = Vector3.zero
                        end
                    end
                end)
            end

            -- Wrapped so `following` + the busy-guard ALWAYS release, even if a frame
            -- where the character is briefly nil throws mid-flow (that bug used to
            -- leak the follow loop -> glued forever, hop 2 never firing).
            local ok, err = pcall(function()
                local function targetRoot() return p.Character and p.Character:FindFirstChild('HumanoidRootPart') end
                local myR0, tr0 = getRoot(), targetRoot()
                local near = myR0 and tr0 and (myR0.Position - tr0.Position).Magnitude <= 18

                if not near then
                    -- HOP 1: gate-assist onto the player (only when far). THIS is the
                    -- gate that costs the 5s SnapCool cooldown before the drag gate.
                    setStatus('Gate onto ' .. p.Name .. '...')
                    local ok1 = gateHop(function() local r = targetRoot(); return r and r.CFrame or nil end,
                        'Gate-kill: gating onto ' .. p.Name .. '...', nil, 10)
                    if not ok1 then setStatus('Failed to reach ' .. p.Name); return end
                    -- Glue on and wait out the 5s SnapCool (HARD server floor between
                    -- two gates - Gate/Activator.lua:113-118), locked on them throughout.
                    glueOn()
                    setStatus('Locked on ' .. p.Name .. ' (5s gate cooldown)...')
                    local cw = os.clock()
                    local mc = manaChar() or getChar()
                    while mc and CS:HasTag(mc, 'SnapCool') and (os.clock() - cw < 7) do
                        RunService.Heartbeat:Wait()
                        mc = manaChar() or getChar() -- re-resolve; never pass nil to HasTag
                    end
                else
                    -- Already within touch range (<=18 studs): SKIP hop 1 entirely ->
                    -- ONE gate, NO 5s wait. Fastest + least time for them to clock you.
                    -- Fly/walk within ~18 studs of them first to hit this path.
                    glueOn()
                end

                -- HOP 2: the DRAG gate. Cast while glued within ~20 studs so the gate's
                -- own touch + proximity warp yanks the player along too (confirmed in
                -- the dump: Gate/Activator.lua:376-481 warps any conscious humanoid
                -- within 20 studs that touches the gate). Keep gluing through the whole
                -- cast; release only when the gate warps us (onLanded).
                setStatus('Gate-drag ' .. p.Name .. '...')
                local ok2 = gateHop(killCF, 'Gate-kill: dragging ' .. p.Name .. '...', function() following = false end, 10)
                if ok2 then setStatus('Dragged ' .. p.Name .. ' via gate')
                else setStatus('Drag gate failed') end
            end)
            following = false
            gateKillBusy = false
            for pt in pairs(noclipped) do if pt.Parent then pcall(function() pt.CanCollide = true end) end end
            if not ok then Library:Notify('Gate-kill stopped: ' .. tostring(err):sub(1, 90), 4) end
        end)
    end
    if Options.GateKillKey then Options.GateKillKey:OnClick(function() if runGateKill then runGateKill() end end) end
end

-- ---- Auto Gate -> Kill combo ------------------------------------------------
-- Pick a target, TP onto them, try to grab (Carry - only takes if they are
-- knocked), charge gate mana, cast the gate, then - as the reliable backstop -
-- shove the grabbed victim's HRP onto the lava kill brick. The gate only carries
-- a GRABBED victim (see Gate/Activator.lua), which is why the grab + direct shove
-- matter more than the gate itself.
do
    local LAVA = Vector3.new(5578.76, 332.685, 640.572) -- user-provided lava coord
    local function setStatus(s) if ComboStatus then ComboStatus:SetText(s) end end
    local function charRemotes()
        local ch = getChar() and getChar():FindFirstChild('CharacterHandler')
        return ch and ch:FindFirstChild('Remotes')
    end
    local function grabbedVictim()
        local ch = getChar()
        local g = ch and ch:FindFirstChild('Grabbing')
        local v = g and g.Value
        if typeof(v) == 'Instance' and v:FindFirstChild('HumanoidRootPart') then return v end
        return nil
    end

    runGateCombo = function()
        local name = Options.GateTarget and Options.GateTarget.Value
        if not name or name == '' then setStatus('Pick a target'); Library:Notify('Pick a target first', 3); return end
        local p = Players:FindFirstChild(name)
        if not p then for _, pl in ipairs(Players:GetPlayers()) do if pl.DisplayName == name then p = pl; break end end end
        local troot = p and p.Character and p.Character:FindFirstChild('HumanoidRootPart')
        if not troot then setStatus((name) .. ' not spawned'); Library:Notify(name .. ' is not spawned', 3); return end
        local lavaCF = CFrame.new(LAVA + Vector3.new(0, 3, 0)) -- land ON the lava

        task.spawn(function()
            -- 1) TP onto the target (instant if Instant TP is on)
            setStatus('TP to ' .. p.Name .. '...')
            Library:Notify('Gate combo -> ' .. p.Name, 2)
            tpMove(troot.CFrame)
            local t0 = os.clock()
            repeat
                task.wait()
                local r = getRoot()
                troot = p.Character and p.Character:FindFirstChild('HumanoidRootPart') or troot
                if r and troot and (r.Position - troot.Position).Magnitude < 8 then break end
            until os.clock() - t0 > 5

            -- 2) grab (Carry) - only takes if they are knocked/grabbable
            setStatus('Grabbing...')
            local rem = charRemotes()
            local carry = rem and rem:FindFirstChild('Carry')
            if carry then pcall(function() carry:FireServer() end) end
            task.wait(0.25)

            -- 3) OPTIONAL theatrics: charge mana + cast the real gate
            if Toggles.GateComboCastGate and Toggles.GateComboCastGate.Value then
                local cost = Options.GateManaCost and Options.GateManaCost.Value or 1
                local mana = getChar() and getChar():FindFirstChild('Mana')
                local setCharge = rem and rem:FindFirstChild('SetManaChargeState')
                if mana and setCharge and mana.Value < cost then
                    setStatus('Charging mana...')
                    pcall(function() setCharge:FireServer(true) end)
                    local m0 = os.clock()
                    repeat task.wait(0.1) until (mana.Value >= cost) or (os.clock() - m0 > 5)
                    pcall(function() setCharge:FireServer(false) end)
                end
                setStatus('Casting gate...')
                local char = getChar(); local hum = getHumanoid()
                local gate = char and (char:FindFirstChild('Gate')
                    or (LocalPlayer:FindFirstChild('Backpack') and LocalPlayer.Backpack:FindFirstChild('Gate')))
                if gate and hum then
                    pcall(function() hum:EquipTool(gate) end)
                    task.wait(0.1)
                    pcall(function() gate:Activate() end)
                    -- Activating spawns a "GateGUI" clone (ImageLabel.TextBox for the
                    -- exit) with a "GateRemote" RemoteEvent; the server reads the typed
                    -- text (WarpData.alias[...]), so set the TextBox AND fire the remote.
                    local exit = 'arena'
                    local pg = LocalPlayer:FindFirstChild('PlayerGui')
                    local g0, gui, remote = os.clock(), nil, nil
                    repeat
                        task.wait()
                        gui = pg and (pg:FindFirstChild('GateGUI') or pg:FindFirstChild('Gate'))
                        remote = gui and gui:FindFirstChild('GateRemote', true)
                        if gui and not remote then remote = gui:FindFirstChildWhichIsA('RemoteEvent', true) end
                    until remote or (os.clock() - g0 > 2)
                    if gui then
                        local box = gui:FindFirstChild('TextBox', true)
                        if box then pcall(function() box.Text = exit end) end
                    end
                    if remote then pcall(function() remote:FireServer(exit) end) end
                else
                    Library:Notify('Gate combo: no "Gate" spell in your hotbar (skipping cast)', 4)
                end
            end

            -- 4) THE KILL: TPSafe the grabbed victim onto the lava. While you grab
            -- them the game hands you network ownership of the victim, and TPSafe
            -- (the same whitelist the real Gate stamps on a grabbed victim - see
            -- Gate/Activator.lua:504-511) makes the server accept the teleport - so
            -- we drop ONLY them on the lava and stay safe ourselves.
            if Toggles.GateComboShove == nil or (Toggles.GateComboShove and Toggles.GateComboShove.Value) then
                setStatus('Delivering to lava...')
                local victim = grabbedVictim()
                if not victim then
                    setStatus('Not grabbing anyone')
                    Library:Notify('Gate combo: no grabbed victim (they must be knocked to grab)', 4)
                else
                    tpSafeMark(victim, lavaCF.Position) -- whitelist the victim's jump (~4s)
                    local s0 = os.clock()
                    while os.clock() - s0 < 0.9 do
                        victim = grabbedVictim() or victim
                        local vhrp = victim and victim:FindFirstChild('HumanoidRootPart')
                        if vhrp then
                            pcall(function()
                                vhrp.CFrame = lavaCF
                                vhrp.AssemblyLinearVelocity = Vector3.new(0, -60, 0)
                            end)
                        end
                        RunService.Heartbeat:Wait()
                    end
                end
            end
            setStatus('Done')
            Library:Notify('Gate combo done', 2)
        end)
    end
    if Options.GateComboKey then Options.GateComboKey:OnClick(function() if runGateCombo then runGateCombo() end end) end
end

-- Shared signal the Auto server-hop farm watches: true when the Trinket Farm has
-- no farmable trinket left (so the hopper knows this server is picked clean).
local trinketFarmDry = false

-- ---- Trinket Farm: auto-travel to trinkets and collect them -----------------
-- Reuses the Trinket ESP detection (workspace Dinkets/Trinkets folder + the
-- trinketType() classifier) and the Trinket ESP "Show only" filter to choose
-- which trinkets to grab. Travels to each with a snapback-proof method (Glide by
-- default - continuous, no gate cooldown, since the gate bypass's 5s cooldown
-- makes bulk farming slow), then fires the trinket's collect: any ClickDetector
-- (the ClickPart) + any ProximityPrompt, and we stand on it so a Touched pickup
-- fires too. Collected trinkets leave the folder so they drop out of the list;
-- ones that resist 3 attempts get skipped. [The exact collect call is being
-- confirmed by the rl-trinket-collect workflow - this fires every plausible one.]
;(function() -- IIFE (not a bare do-block): keeps this feature's ~15 locals in
             -- its OWN register budget so the main chunk stays under Luau's
             -- 200-local cap. Costs zero persistent locals.
    local CS = game:GetService('CollectionService')
    local TRINKET_FOLDER_NAMES = { Dinkets = true, Trinkets = true }
    local function trinketsFolder()
        for _, d in ipairs(workspace:GetDescendants()) do
            if (d:IsA('Folder') or d:IsA('Model')) and TRINKET_FOLDER_NAMES[d.Name] then return d end
        end
        return nil
    end
    local function anchorOf(obj)
        if obj:IsA('BasePart') then return obj end
        return obj.PrimaryPart or obj:FindFirstChildWhichIsA('BasePart')
    end
    local function farmName(obj, part)
        local ok, info = pcall(trinketType, part or obj)
        return (ok and type(info) == 'table' and info.Name) or 'Trinket'
    end
    local function setStatus(s) if FarmStatus then FarmStatus:SetText(s) end end
    -- Rounded-position key so a re-created trinket at the same spot (a NEW Instance)
    -- still counts as already-handled this run (mirrors the ingredient farm).
    local function posKey(part)
        local p = part.Position
        return ('%d,%d,%d'):format(math.floor(p.X + 0.5), math.floor(p.Y + 0.5), math.floor(p.Z + 0.5))
    end

    -- Trinket pickup = the trinket's own ClickDetector.MouseClick (Roblox engine-
    -- level, routed straight to a server Script ON the trinket in workspace.Dinkets)
    -- - NOT the combat LeftClick remote (that just swings your weapon). Confirmed by
    -- the rl-trinket-collect workflow: the game marks lootables via FindFirstChild(
    -- 'ClickDetector') and DISABLES pickup by zeroing that ClickDetector's
    -- MaxActivationDistance (EffectsHandler/LocalScript.lua:5332). So the clean
    -- collect is fireclickdetector, which triggers MouseClick directly - no aiming.
    -- We still TP onto the trinket (~0 studs) to satisfy any server-side distance
    -- re-check in the trinket's Script (that Script is server-only, not in the dump).
    local function collectTrinket(obj, part)
        local cd = obj:FindFirstChildWhichIsA('ClickDetector', true)
        if cd and fireclickdetector then
            pcall(function() cd.MaxActivationDistance = math.huge end) -- un-zero if hidden/looted
            pcall(fireclickdetector, cd, 1)
            pcall(fireclickdetector, cd) -- some executors ignore the distance arg
            return
        end
        -- Fallback (executor lacks fireclickdetector): physically click it - aim the
        -- cursor at the trinket, then simulate a real left press+release so the
        -- engine fires MouseClick (needs the cursor actually over the ClickDetector).
        if part then
            local cam = workspace.CurrentCamera
            local sp = cam:WorldToViewportPoint(part.Position)
            if sp.Z > 0 then
                local x, y = math.floor(sp.X), math.floor(sp.Y)
                pcall(function() VIM:SendMouseMoveEvent(x, y, game) end)
                pcall(function() VIM:SendMouseButtonEvent(x, y, 0, true, game, 0) end)
                pcall(function() VIM:SendMouseButtonEvent(x, y, 0, false, game, 0) end)
            end
        end
        -- Rare alternative: a ProximityPrompt pickup.
        for _, d in ipairs(obj:GetDescendants()) do
            if d:IsA('ProximityPrompt') and fireproximityprompt then pcall(fireproximityprompt, d) end
        end
    end

    local attemptedAt = setmetatable({}, { __mode = 'k' })
    local failCount   = setmetatable({}, { __mode = 'k' })
    -- STRONG (not weak) visited sets, same fix as the ingredient farm: never churn
    -- back to a trinket we already handled this run. visited = by Instance,
    -- visitedPos = by rounded spot (a re-created trinket at the same place is
    -- still skipped). Both cleared on each fresh run.
    local visited    = {}
    local visitedPos = {}
    local farmActive  = false
    local function on() return not MenuUnloaded and Toggles.TrinketFarm and Toggles.TrinketFarm.Value end

    -- Nearest matching, not-recently-tried, not-blacklisted trinket.
    local function pickNext()
        local folder = trinketsFolder(); if not folder then return nil end
        local myR = getRoot(); local origin = myR and myR.Position or Vector3.zero
        local filter = Options.FarmFilter and Options.FarmFilter.Value
        local filterActive = filter and next(filter) ~= nil -- nothing ticked = grab all
        local best, bestPart, bestD
        for _, obj in ipairs(folder:GetChildren()) do
            local part = anchorOf(obj)
            if part and not visited[obj] and not visitedPos[posKey(part)] -- handled this run -> skip
               and (failCount[obj] or 0) < 3
               and (os.clock() - (attemptedAt[obj] or -1e9)) > 5 then
                local nm = farmName(obj, part)
                if (not filterActive) or filter[nm] then
                    local d = (part.Position - origin).Magnitude
                    if not bestD or d < bestD then best, bestPart, bestD = obj, part, d end
                end
            end
        end
        return best, bestPart
    end

    local function nearPos(pos, reach)
        local myR = getRoot()
        return myR ~= nil and (myR.Position - pos).Magnitude <= reach
    end

    local function farmTravel(pos, method, reach)
        local goalCF = CFrame.new(pos + Vector3.new(0, 3, 0))
        if method == 'Gate bypass (5s each)' then
            gateThenTP(goalCF)
            local t0 = os.clock()
            repeat RunService.Heartbeat:Wait() until nearPos(pos, reach) or (os.clock() - t0 > 12) or not on()
            local mc = manaChar() or getChar(); local cw = os.clock()
            while mc and CS:HasTag(mc, 'SnapCool') and (os.clock() - cw < 7) and on() do
                RunService.Heartbeat:Wait(); mc = manaChar() or getChar()
            end
        elseif method == 'Instant (grab before snapback)' then
            tpInstant(goalCF)
            RunService.Heartbeat:Wait()
        else -- Glide (default) - continuous, server-accepted, no snapback, no cooldown
            tpGlide(goalCF)
            local t0 = os.clock()
            repeat RunService.Heartbeat:Wait() until nearPos(pos, reach) or (os.clock() - t0 > 15) or not on()
        end
    end

    -- Travel WITH snapback retry. Trinkets are MAP-WIDE, so a glide often crosses
    -- an RL area boundary and the AC yanks you back ("glides to it then snaps
    -- back") - the LOCAL ingredient farm never hit this. So if we did not actually
    -- arrive, re-glide (resuming from wherever we got yanked to) up to 3 times; if
    -- it keeps snapping we give up on THIS trinket (caller marks it visited + moves
    -- to the next) instead of churning on one unreachable node forever.
    local function farmGoTo(pos, method, reach)
        for _ = 1, 3 do
            if not on() then return false end
            farmTravel(pos, method, reach)
            if nearPos(pos, reach) then return true end
            task.wait(0.2) -- settle after a snapback, then retry from the new position
        end
        return nearPos(pos, reach)
    end

    local function runFarm()
        if farmActive then return end
        farmActive = true
        trinketFarmDry = false
        task.spawn(function()
            table.clear(visited); table.clear(visitedPos) -- fresh sweep on each run start
            while on() do
                local obj, part = pickNext()
                if not (obj and part) then
                    trinketFarmDry = true -- nothing left here -> the auto-hopper may hop
                    setStatus('No matching trinkets left'); task.wait(1.5)
                else
                    trinketFarmDry = false
                    local pos    = part.Position
                    local reach  = (Options.FarmReach and Options.FarmReach.Value) or 10
                    local method = (Options.FarmTPMethod and Options.FarmTPMethod.Value) or 'Glide (no cooldown)'
                    local delay  = (Options.FarmDelay and Options.FarmDelay.Value) or 0.35
                    setStatus('-> ' .. farmName(obj, part))
                    attemptedAt[obj] = os.clock()
                    local arrived = farmGoTo(pos, method, reach)
                    if arrived then
                        -- Fire collect, then WAIT for the trinket to actually leave the
                        -- folder (real pickup confirmation) before advancing - the same
                        -- robust step the ingredient farm uses, so we never move on
                        -- before the server registered the pickup.
                        for _ = 1, 6 do
                            if not obj.Parent then break end
                            collectTrinket(obj, part)
                            RunService.Heartbeat:Wait()
                        end
                        local t0 = os.clock()
                        repeat RunService.Heartbeat:Wait() until (not obj.Parent) or (os.clock() - t0 > delay)
                    else
                        setStatus(farmName(obj, part) .. ' kept snapping back - skipped')
                    end
                    if obj.Parent then failCount[obj] = (failCount[obj] or 0) + 1 end -- still here = not collected
                    -- Mark handled (Instance + spot) so we never churn back to it this run.
                    visited[obj] = true
                    visitedPos[posKey(part)] = true
                end
            end
            farmActive = false
            trinketFarmDry = false
            setStatus('Idle')
        end)
    end
    if Toggles.TrinketFarm then
        Toggles.TrinketFarm:OnChanged(function()
            if Toggles.TrinketFarm.Value then runFarm() else setStatus('Stopping...') end
        end)
    end
end)() -- end Trinket Farm IIFE

-- ---- Auto server-hop trinket farm -------------------------------------------
-- Chains it all together: on a fresh server, cast Trinket Shift (disguise), run
-- the Trinket Farm, and when the farm is DRY (no farmable trinkets left) for a
-- moment, server-hop (serverHop already skips servers you've visited) and repeat.
-- Persistence across the teleport is a flag file: on each menu load, if the flag
-- is set we auto-resume. That means the menu MUST re-run on the new server -> put
-- this script in your executor's auto-execute folder (queue_on_teleport is also
-- fired as a best-effort re-inject when the executor exposes it).
;(function() -- IIFE (see Trinket Farm note): keeps this block's locals off the
             -- main chunk's 200-local budget. Assigns the top-level upvalues
             -- autoMenuNow / dumpMenuButtons, which still work as upvalues.
    local FLAG = 'GameTestMenu/trinket_autohop.json'
    local NUM_KEYS = {
        [1] = Enum.KeyCode.One, [2] = Enum.KeyCode.Two, [3] = Enum.KeyCode.Three, [4] = Enum.KeyCode.Four,
        [5] = Enum.KeyCode.Five, [6] = Enum.KeyCode.Six, [7] = Enum.KeyCode.Seven, [8] = Enum.KeyCode.Eight,
        [9] = Enum.KeyCode.Nine, [10] = Enum.KeyCode.Zero,
    }

    local function setFlag(active)
        pcall(function()
            if makefolder and isfolder and not isfolder('GameTestMenu') then makefolder('GameTestMenu') end
            if writefile then writefile(FLAG, HttpServ:JSONEncode({ active = active == true })) end
        end)
    end
    local function flagSet()
        local ok, res = pcall(function() return isfile and isfile(FLAG) and HttpServ:JSONDecode(readfile(FLAG)) end)
        return ok and type(res) == 'table' and res.active == true
    end

    -- Equip the shift slot, then cast per the chosen method.
    local function useShift()
        local slot = math.floor((Options.ShiftSlot and Options.ShiftSlot.Value) or 4)
        local key = NUM_KEYS[slot] or Enum.KeyCode.Four
        pcall(function() VIM:SendKeyEvent(true, key, false, game) end)
        task.wait(0.05)
        pcall(function() VIM:SendKeyEvent(false, key, false, game) end)
        task.wait(0.35) -- let the move equip
        local method = (Options.ShiftActivate and Options.ShiftActivate.Value) or 'Left click (M1)'
        if method == 'Equip only' then return end
        local char = getChar()
        local mp = UIS:GetMouseLocation()
        if method == 'Right click (M2)' then
            -- gate-style: fire the RightClick remote, plus a VIM M2 as backup
            local rem = char and char:FindFirstChild('CharacterHandler') and char.CharacterHandler:FindFirstChild('Remotes')
            local rc = rem and rem:FindFirstChild('RightClick')
            if rc then pcall(function() rc:FireServer(true) end); task.wait(0.06); pcall(function() rc:FireServer(false) end) end
            pcall(function() VIM:SendMouseButtonEvent(mp.X, mp.Y, 1, true, game, 0) end)
            task.wait(0.06)
            pcall(function() VIM:SendMouseButtonEvent(mp.X, mp.Y, 1, false, game, 0) end)
        else -- Left click (M1): tool Activate (position-independent) + a VIM M1 backup
            local tool = char and char:FindFirstChildOfClass('Tool')
            if tool then pcall(function() tool:Activate() end) end
            pcall(function() VIM:SendMouseButtonEvent(mp.X, mp.Y, 0, true, game, 0) end)
            task.wait(0.06)
            pcall(function() VIM:SendMouseButtonEvent(mp.X, mp.Y, 0, false, game, 0) end)
        end
    end

    -- ---- Menu bypass: auto-pick the save slot + click PLAY on a fresh server --
    -- After a hop RL drops you at the Data List (slot select) -> main menu; the
    -- character only spawns once you load a slot AND click PLAY. LocalPlayer.Ingame
    -- (MenuReturnClient reads it) is the "actually spawned" signal. The menu's own
    -- scripts aren't in the dump, so we drive its BUTTONS like a human would.
    local function ingame() return LocalPlayer:FindFirstChild('Ingame') ~= nil end
    -- STRONGER "actually in the world" signal than Ingame/getChar (both can be
    -- truthy at the Data List menu, which made it skip the menu-bypass and gate
    -- with no real character). The REAL character lives at workspace.Live.<name>
    -- with an HRP - that does NOT exist at the slot-select menu, only after you
    -- load a slot + PLAY. Nothing (shift / farm / gate) may run until this is true.
    local function reallySpawned()
        local live = workspace:FindFirstChild('Live') or workspace:FindFirstChild('Alive')
        local c = live and live:FindFirstChild(LocalPlayer.Name)
        return (c and c:FindFirstChild('HumanoidRootPart') ~= nil) or false
    end

    local function guiRoots()
        local list = {}
        local pg = LocalPlayer:FindFirstChild('PlayerGui'); if pg then list[#list + 1] = pg end
        local ok, cg = pcall(function() return (gethui and gethui()) or game:GetService('CoreGui') end)
        if ok and cg then list[#list + 1] = cg end
        return list
    end
    local function onScreen(d) -- every GuiObject ancestor Visible + top LayerCollector Enabled
        local node = d
        while node and node:IsA('GuiObject') do
            if not node.Visible then return false end
            node = node.Parent
        end
        if node and node:IsA('LayerCollector') and not node.Enabled then return false end
        return true
    end
    -- Press a GUI element: fire its own click handlers directly (no positioning),
    -- falling back to a real VIM click at its on-screen centre.
    local function pressButton(btn)
        if not btn then return false end
        if btn:IsA('GuiButton') then
            if getconnections then
                local ok = pcall(function()
                    for _, c in ipairs(getconnections(btn.MouseButton1Click)) do
                        if c.Fire then c:Fire() elseif type(c.Function) == 'function' then c.Function() end
                    end
                end)
                if ok then return true end
            end
            if firesignal then
                if pcall(function() firesignal(btn.MouseButton1Click) end) then return true end
            end
        end
        local ap, as = btn.AbsolutePosition, btn.AbsoluteSize
        local x, y = math.floor(ap.X + as.X / 2), math.floor(ap.Y + as.Y / 2)
        pcall(function() VIM:SendMouseMoveEvent(x, y, game) end)
        pcall(function() VIM:SendMouseButtonEvent(x, y, 0, true, game, 0) end)
        task.wait(0.05)
        pcall(function() VIM:SendMouseButtonEvent(x, y, 0, false, game, 0) end)
        return true
    end

    -- Click the save-slot row: by "Slot match" text if set, else the Nth big row.
    local function pressChosenSlot()
        local match = tostring((Options.SlotMatch and Options.SlotMatch.Value) or ''):gsub('^%s+', ''):gsub('%s+$', '')
        if match ~= '' then
            local low = match:lower()
            for _, root in ipairs(guiRoots()) do
                for _, d in ipairs(root:GetDescendants()) do
                    if (d:IsA('TextLabel') or d:IsA('TextButton')) and onScreen(d)
                       and tostring(d.Text):lower():find(low, 1, true) then
                        local node = d
                        while node and node.Parent do -- climb to a clickable row
                            if node:IsA('GuiButton') then return pressButton(node) end
                            node = node.Parent
                        end
                        return pressButton(d) -- no button ancestor: VIM-click the label's spot
                    end
                end
            end
            return false
        end
        -- No match text: click the Nth slot-like button (big rows, top-to-bottom).
        local slot = math.floor((Options.SaveSlot and Options.SaveSlot.Value) or 1)
        local rows = {}
        for _, root in ipairs(guiRoots()) do
            for _, d in ipairs(root:GetDescendants()) do
                if d:IsA('GuiButton') and onScreen(d) and d.AbsoluteSize.X > 200 and d.AbsoluteSize.Y > 35 then
                    rows[#rows + 1] = d
                end
            end
        end
        table.sort(rows, function(a, b) return a.AbsolutePosition.Y < b.AbsolutePosition.Y end)
        if rows[slot] then return pressButton(rows[slot]) end
        return false
    end

    -- Click a PLAY button (text/name == 'play').
    local function pressPlay()
        for _, root in ipairs(guiRoots()) do
            for _, d in ipairs(root:GetDescendants()) do
                if d:IsA('GuiButton') and onScreen(d) then
                    if tostring(d.Text):lower():gsub('%s+', '') == 'play' or d.Name:lower() == 'play' then
                        return pressButton(d)
                    end
                end
            end
        end
        return false
    end

    dumpMenuButtons = function()
        local n = 0
        for _, root in ipairs(guiRoots()) do
            for _, d in ipairs(root:GetDescendants()) do
                if (d:IsA('GuiButton') or d:IsA('TextLabel')) and onScreen(d) then
                    n += 1
                    print(('[Menu] %s | text=%q | name=%q | pos=%d,%d size=%d,%d'):format(
                        d.ClassName, tostring(d.Text), d.Name,
                        math.floor(d.AbsolutePosition.X), math.floor(d.AbsolutePosition.Y),
                        math.floor(d.AbsoluteSize.X), math.floor(d.AbsoluteSize.Y)))
                end
            end
        end
        Library:Notify(('Dumped %d visible menu buttons/labels to console'):format(n), 4)
    end

    -- Keep clicking slot + PLAY until the REAL character exists (reallySpawned).
    local function autoMenu()
        local t0 = os.clock()
        while not reallySpawned() and (os.clock() - t0 < 90) do
            pcall(pressChosenSlot)
            task.wait(0.4)
            pcall(pressPlay)
            task.wait(0.9)
        end
        return reallySpawned()
    end
    autoMenuNow = function() task.spawn(autoMenu) end

    local seqActive = false
    local function startSequence()
        if seqActive then return end
        seqActive = true
        task.spawn(function()
            -- Fresh server -> at the Data List / main menu until we load a slot +
            -- PLAY. Run the bypass FIRST; nothing else fires until reallySpawned().
            if not reallySpawned() then
                Library:Notify('Auto-hop: at menu -> picking slot + PLAY...', 3)
                autoMenu()
            end
            -- If we STILL are not in the world, the menu bypass failed - do NOT
            -- farm/gate (that is exactly what caused the "gate did not fire" at the
            -- menu). Bail and tell you how to fix the slot targeting.
            if not reallySpawned() then
                Library:Notify('Auto-hop: could not get past the menu - set "Slot match" to your name/class or use "Dump menu buttons". Not farming.', 7)
                seqActive = false
                return
            end
            -- CRITICAL: let the join lag-spike pass BEFORE we start moving. Farming
            -- (teleport/glide) during the spike trips the AC and kicks you.
            local settle = (Options.LoadSettle and Options.LoadSettle.Value) or 5
            if settle > 0 and Toggles.AutoHopFarm and Toggles.AutoHopFarm.Value then
                Library:Notify(('Auto-hop: spawned - settling %ds before farming...'):format(math.floor(settle)), 3)
                local s0 = os.clock()
                repeat task.wait(0.2) until (os.clock() - s0 > settle) or not (Toggles.AutoHopFarm and Toggles.AutoHopFarm.Value)
            end
            if reallySpawned() and Toggles.AutoHopFarm and Toggles.AutoHopFarm.Value then
                Library:Notify('Auto-hop: casting Trinket Shift...', 2)
                pcall(useShift)
                if Toggles.TrinketFarm then Toggles.TrinketFarm:SetValue(true) end -- start the farm
            end
            seqActive = false
        end)
    end

    local dryAt, lastShift, hopping = nil, 0, false
    track(RunService.Heartbeat:Connect(function()
        if MenuUnloaded then return end
        if not (Toggles.AutoHopFarm and Toggles.AutoHopFarm.Value) then dryAt = nil; return end

        -- keep the disguise up (its own cooldown makes an early re-cast a no-op);
        -- only while REALLY in the world, never at the menu / mid-load.
        local recast = (Options.ShiftRecast and Options.ShiftRecast.Value) or 0
        if recast > 0 and reallySpawned() and (os.clock() - lastShift) > recast then
            lastShift = os.clock()
            task.spawn(function() pcall(useShift) end)
        end

        -- hop once the farm has been dry for the configured delay
        if trinketFarmDry then
            dryAt = dryAt or os.clock()
            local wait = (Options.HopWhenDry and Options.HopWhenDry.Value) or 5
            if not hopping and (os.clock() - dryAt) > wait then
                hopping = true
                Library:Notify('Auto-hop: server picked clean -> hopping...', 3)
                if serverHop then pcall(serverHop) end
                -- if the teleport didn't fire (no new server found), allow a retry
                task.delay(15, function() hopping = false end)
            end
        else
            dryAt = nil
        end
    end))

    if Toggles.AutoHopFarm then
        Toggles.AutoHopFarm:OnChanged(function()
            if Toggles.AutoHopFarm.Value then
                setFlag(true)
                lastShift = 0
                -- best-effort re-inject on the next teleport (needs an executor that
                -- exposes queue_on_teleport; auto-execute is the reliable path).
                local qot = queue_on_teleport or (syn and syn.queue_on_teleport)
                if qot then pcall(qot, 'if getgenv then getgenv().GameTestMenu_ResumeHop = true end') end
                startSequence()
            else
                setFlag(false)
                dryAt = nil; hopping = false
                if Toggles.TrinketFarm then Toggles.TrinketFarm:SetValue(false) end -- stop the farm too
                Library:Notify('Auto-hop trinket farm OFF (flag cleared)', 3)
            end
        end)
    end

    -- Auto-resume on a fresh server if the flag is set (menu re-ran on join).
    if flagSet() and Toggles.AutoHopFarm then
        task.defer(function()
            Library:Notify('Auto-hop trinket farm resuming (toggle off in Visuals to stop)', 4)
            Toggles.AutoHopFarm:SetValue(true) -- fires OnChanged -> shift + farm + arm hop
        end)
    end
end)() -- end Auto server-hop IIFE

-- ============================================================================
-- QOL  (NPC / merchant teleport)
-- ============================================================================
do
    -- Baked NPC / vendor spots (name -> coord). Add more as you find them.
    local KNOWN_NPCS = {
        Merchant = Vector3.new(-1236.8, 143.643, 264.9), -- user-provided merchant
    }
    local NPC_FOLDERS = { 'NPCs', 'NPC' }

    local NpcBox = Tabs.QOL:AddLeftGroupbox('NPC / Merchant TP')
    NpcBox:AddLabel('Teleport to an NPC or vendor. The list = baked\nspots (Merchant) + any live NPCs found in\nworkspace.NPCs. Gate-assist keeps the server from\nsnapping you back; turn it off to glide instead.', true)
    NpcBox:AddDropdown('NpcTarget', {
        Values = {}, Default = nil, Multi = false, AllowNull = true, Text = 'NPC',
        Tooltip = 'Known baked spots + live NPCs from workspace.NPCs. Hit Refresh to rescan.',
    })
    NpcBox:AddToggle('GateAssistNPC', {
        Text = 'Gate-assist (bypass snapback)', Default = true,
        Tooltip = 'Cast a cover gate then instant-TP so the server does not snap you back (needs the Gate spell + the ~5s gate cooldown). OFF = bounded glide (no Gate needed, still no snapback, just slower travel).',
    })
    local NpcStatus = NpcBox:AddLabel('Idle')

    -- Live position of a scanned NPC model by name.
    local function livePos(name)
        for _, fn in ipairs(NPC_FOLDERS) do
            local f = workspace:FindFirstChild(fn)
            local m = f and f:FindFirstChild(name)
            if m then
                local part = m:FindFirstChild('HumanoidRootPart') or m.PrimaryPart
                    or m:FindFirstChildWhichIsA('BasePart') or (m:IsA('BasePart') and m)
                if part then return part.Position end
                if m:IsA('Model') then return m:GetPivot().Position end
            end
        end
        return nil
    end
    local function npcPos(name) return KNOWN_NPCS[name] or livePos(name) end

    local function refreshNpcs(silent)
        local names, seen = {}, {}
        for nm in pairs(KNOWN_NPCS) do if not seen[nm] then names[#names + 1] = nm; seen[nm] = true end end
        for _, fn in ipairs(NPC_FOLDERS) do
            local f = workspace:FindFirstChild(fn)
            if f then
                for _, m in ipairs(f:GetChildren()) do
                    if m:IsA('Model') and m.Name ~= '' and not seen[m.Name] then
                        names[#names + 1] = m.Name; seen[m.Name] = true
                    end
                end
            end
        end
        table.sort(names)
        Options.NpcTarget:SetValues(names)
        if not silent then Library:Notify(('NPC TP: %d destination(s)'):format(#names), 2) end
    end

    local function tpToNpc()
        local name = Options.NpcTarget and Options.NpcTarget.Value
        if not name or name == '' then Library:Notify('Pick an NPC first', 2); return end
        local pos = npcPos(name)
        if not pos then NpcStatus:SetText(name .. ' not found'); Library:Notify('NPC not found: ' .. name .. ' (try Refresh)', 3); return end
        local goalCF = CFrame.new(pos + Vector3.new(0, 3, 0)) -- land at their spot (no ceiling raycast)
        NpcStatus:SetText('-> ' .. name)
        if Toggles.GateAssistNPC and Toggles.GateAssistNPC.Value then
            gateThenTP(goalCF) -- cover gate -> land -> instant-TP (no snapback)
        else
            tpGlide(goalCF) -- bounded glide, also no snapback, no Gate needed
        end
        Library:Notify('Teleporting to ' .. name .. '...', 2)
    end

    NpcBox:AddButton({ Text = 'Teleport to NPC', Func = tpToNpc })
        :AddButton({ Text = 'Refresh NPCs', Func = function() refreshNpcs() end })
    NpcBox:AddLabel('NPC TP key'):AddKeyPicker('NpcTPKey', {
        Default = 'L', Mode = 'Toggle', Text = 'NPC teleport',
    })
    if Options.NpcTPKey then Options.NpcTPKey:OnClick(tpToNpc) end

    refreshNpcs(true) -- silent pre-populate
end

-- QOL: Teleport to coords (separate X / Y / Z boxes + gate bypass) -----------
do
    local QCoordBox = Tabs.QOL:AddRightGroupbox('Teleport to Coords')
    QCoordBox:AddLabel('Separate X / Y / Z boxes -> gate-assist bypass so\nthe server does not snap you back. "Copy my\nposition" fills the three boxes with where you are.', true)
    -- No Numeric filter: it can strip the leading minus, and coords go negative.
    QCoordBox:AddInput('QCoordX', { Text = 'X', Default = '', Finished = true, Placeholder = '-1236.8' })
    QCoordBox:AddInput('QCoordY', { Text = 'Y', Default = '', Finished = true, Placeholder = '143.643' })
    QCoordBox:AddInput('QCoordZ', { Text = 'Z', Default = '', Finished = true, Placeholder = '264.9' })
    QCoordBox:AddToggle('GateAssistCoord', {
        Text = 'Gate-assist (bypass snapback)', Default = true,
        Tooltip = 'Cover gate -> instant-TP to the coords so the server does not snap you back (needs the Gate spell + the ~5s gate cooldown). OFF = bounded glide (no Gate needed, still no snapback).',
    })
    local QCoordStatus = QCoordBox:AddLabel('Idle')

    local function coordTp()
        local x = tonumber(Options.QCoordX and Options.QCoordX.Value)
        local y = tonumber(Options.QCoordY and Options.QCoordY.Value)
        local z = tonumber(Options.QCoordZ and Options.QCoordZ.Value)
        if not (x and y and z) then
            QCoordStatus:SetText('Enter X, Y and Z')
            Library:Notify('Enter a number in all three of X / Y / Z', 3); return
        end
        local goalCF = CFrame.new(x, y, z)
        if not finiteCF(goalCF) then Library:Notify('Coords out of range', 3); return end
        QCoordStatus:SetText(('-> %.0f, %.0f, %.0f'):format(x, y, z))
        if Toggles.GateAssistCoord and Toggles.GateAssistCoord.Value then
            gateThenTP(goalCF) -- cover gate -> land -> instant-TP (no snapback)
        else
            tpGlide(goalCF) -- bounded glide, also no snapback, no Gate needed
        end
        Library:Notify(('Teleporting to %.1f, %.1f, %.1f'):format(x, y, z), 2)
    end
    local function copyPos()
        local root = getRoot()
        if not root then Library:Notify('No character', 2); return end
        local p = root.Position
        if Options.QCoordX then Options.QCoordX:SetValue(('%.3f'):format(p.X)) end
        if Options.QCoordY then Options.QCoordY:SetValue(('%.3f'):format(p.Y)) end
        if Options.QCoordZ then Options.QCoordZ:SetValue(('%.3f'):format(p.Z)) end
        Library:Notify(('Filled X/Y/Z: %.1f, %.1f, %.1f'):format(p.X, p.Y, p.Z), 3)
    end

    QCoordBox:AddButton({ Text = 'Teleport to coords', Func = coordTp })
        :AddButton({ Text = 'Copy my position', Func = copyPos })
    QCoordBox:AddLabel('Coord TP key'):AddKeyPicker('QCoordKey', {
        Default = 'M', Mode = 'Toggle', Text = 'Coord teleport',
    })
    if Options.QCoordKey then Options.QCoordKey:OnClick(coordTp) end
end

-- QOL: Ingredient Farm (workspace.Ingredients) ------------------------------
-- Same auto-travel-and-collect shape as the Trinket Farm, but for the named
-- pickups in workspace.Ingredients. Matches by model Name (cleaned of a leading
-- '.' and a trailing spawn number). Seeded with the 3 known ones; leave the
-- filter empty to farm everything in the folder. COLLECT (dump-confirmed by the
-- rl-ingredient-collect workflow) = the ingredient part's OWN
-- ClickDetector.MouseClick, fired via fireclickdetector - byte-for-byte the
-- trinket system. There is NO ProximityPrompt anywhere in the game, no pickup
-- remote, no Touched. Each ingredient is a BasePart with an "isIngredient" marker
-- + a direct-child "ClickDetector" (the hide/looted path zeroes that CD's
-- MaxActivationDistance, so we un-zero it before firing).
;(function() -- IIFE (see Trinket Farm note): this block is what overflowed the
             -- main chunk's 200-local cap ("travel"); running it as its own
             -- function keeps its ~20 locals out of the main register budget.
    local CS = game:GetService('CollectionService')
    local FOLDER_NAMES = { Ingredients = true }
    local KNOWN_INGREDIENTS = { 'Lava Flower', 'Moss Plant', 'Scroom' } -- user-provided seed

    local IngBox = Tabs.QOL:AddLeftGroupbox('Ingredient Farm')
    IngBox:AddLabel('Auto-travel to ingredients in workspace.Ingredients\nand collect them. Tick which in "Farm only" (leave\nempty = grab everything). Glide is snapback-proof;\nkeep No Fall Damage on.', true)
    local IngStatus = IngBox:AddLabel('Idle')
    IngBox:AddDropdown('IngredientFilter', {
        Values = KNOWN_INGREDIENTS, Default = {}, Multi = true, AllowNull = true, Text = 'Farm only',
        Tooltip = 'Tick the ingredients to farm. Leave EVERYTHING unticked to farm every ingredient in the folder.',
    })
    IngBox:AddToggle('IngredientFarm', {
        Text = 'Auto-farm ingredients', Default = false,
        Tooltip = 'Repeatedly travel to the nearest matching ingredient in workspace.Ingredients and pick it up. Stops when none are left. The key below toggles it on/off.',
    }):AddKeyPicker('IngredientFarmKey', {
        Default = 'U', SyncToggleState = true, Mode = 'Toggle', Text = 'Auto-farm ingredients',
    })
    IngBox:AddDropdown('IngTPMethod', {
        Values = { 'Glide (no cooldown)', 'Gate bypass (5s each)', 'Instant (grab before snapback)' },
        Default = 1, Multi = false, Text = 'Travel method',
        Tooltip = 'Glide (DEFAULT - use this) = continuous, no snapback, no cooldown, no Gate needed. The right method for farming. Gate bypass = PATCHED for farming: single gate TPs (Teleport tab / NPC TP) still work, but the server now snaps back / blocks RAPID repeated gate teleports, so it fails when spammed one-per-item - do NOT farm with it. Instant = fastest, may snap back before collect (misses some).',
    })
    IngBox:AddSlider('IngReach', {
        Text = 'Collect radius', Default = 8, Min = 4, Max = 40, Rounding = 0, Suffix = ' studs',
    })
    IngBox:AddSlider('IngDelay', {
        Text = 'Per-item delay', Default = 0.35, Min = 0.1, Max = 2, Rounding = 2, Suffix = ' s',
    })

    local function ingFolder()
        local f = workspace:FindFirstChild('Ingredients')
        if f then return f end
        for _, d in ipairs(workspace:GetDescendants()) do
            if (d:IsA('Folder') or d:IsA('Model')) and FOLDER_NAMES[d.Name] then return d end
        end
        return nil
    end
    local function anchorOf(obj)
        if obj:IsA('BasePart') then return obj end
        return obj.PrimaryPart or obj:FindFirstChildWhichIsA('BasePart')
    end
    local function ingName(obj)
        return (tostring(obj.Name):gsub('^%.+', ''):gsub('%s*%d+$', ''))
    end
    local function setStatus(s) if IngStatus then IngStatus:SetText(s) end end
    -- Stable spot key (rounded position) so a respawned/re-created part at the same
    -- spot (a NEW Instance) still counts as already-visited this run.
    local function posKey(part)
        local p = part.Position
        return ('%d,%d,%d'):format(math.floor(p.X + 0.5), math.floor(p.Y + 0.5), math.floor(p.Z + 0.5))
    end

    -- Collect = the ingredient part's OWN ClickDetector.MouseClick. Resolve the CD
    -- (it's a direct child of the part; handle a Model wrapper too), force it
    -- clickable in case a hide/looted state zeroed MaxActivationDistance, then fire
    -- it. No aiming/ProximityPrompt - we've already TP'd on, which satisfies the
    -- server distance re-check.
    local function collect(obj, part)
        local cd = (part and part:FindFirstChildWhichIsA('ClickDetector'))
            or obj:FindFirstChildWhichIsA('ClickDetector', true)
        if not cd then return end
        pcall(function() cd.MaxActivationDistance = math.huge end) -- un-zero if hidden/looted
        if fireclickdetector then
            pcall(fireclickdetector, cd, 1)
            pcall(fireclickdetector, cd) -- some executors ignore the distance arg
        elseif part then
            -- No fireclickdetector: physically click it (aim + press/release).
            local sp = workspace.CurrentCamera:WorldToViewportPoint(part.Position)
            if sp.Z > 0 then
                local x, y = math.floor(sp.X), math.floor(sp.Y)
                pcall(function() VIM:SendMouseMoveEvent(x, y, game) end)
                pcall(function() VIM:SendMouseButtonEvent(x, y, 0, true, game, 0) end)
                pcall(function() VIM:SendMouseButtonEvent(x, y, 0, false, game, 0) end)
            end
        end
    end

    local attemptedAt = setmetatable({}, { __mode = 'k' })
    local failCount   = setmetatable({}, { __mode = 'k' })
    -- STRONG tables (NOT weak): a weak Instance-keyed table can drop entries when
    -- the object's Lua proxy is GC'd even though the ingredient still exists, which
    -- made pickNext "forget" it had already gone there and revisit it. Strong keys
    -- never drop. `visited` = by Instance, `visitedPos` = by rounded spot (so a
    -- re-created part at the same place is still skipped). Both cleared per run.
    local visited    = {} -- [obj]      = true
    local visitedPos = {} -- ['x,y,z']  = true
    local active = false
    local function on() return not MenuUnloaded and Toggles.IngredientFarm and Toggles.IngredientFarm.Value end

    local function pickNext()
        local f = ingFolder(); if not f then return nil end
        local myR = getRoot(); local origin = myR and myR.Position or Vector3.zero
        local filter = Options.IngredientFilter and Options.IngredientFilter.Value
        local filterActive = filter and next(filter) ~= nil -- nothing ticked = grab all
        local best, bestPart, bestD
        for _, obj in ipairs(f:GetChildren()) do
            local part = anchorOf(obj)
            if part and not visited[obj] and not visitedPos[posKey(part)] -- been here this run -> never pick it again
               and (failCount[obj] or 0) < 3
               and (os.clock() - (attemptedAt[obj] or -1e9)) > 5 then
                if (not filterActive) or filter[ingName(obj)] or filter[obj.Name] then
                    local d = (part.Position - origin).Magnitude
                    if not bestD or d < bestD then best, bestPart, bestD = obj, part, d end
                end
            end
        end
        return best, bestPart
    end

    local function nearPos(pos, reach)
        local myR = getRoot()
        return myR ~= nil and (myR.Position - pos).Magnitude <= reach
    end

    local function travel(pos, method, reach)
        local goalCF = CFrame.new(pos + Vector3.new(0, 3, 0))
        if method == 'Gate bypass (5s each)' then
            gateThenTP(goalCF)
            local t0 = os.clock()
            repeat RunService.Heartbeat:Wait() until nearPos(pos, reach) or (os.clock() - t0 > 12) or not on()
            local mc = manaChar() or getChar(); local cw = os.clock()
            while mc and CS:HasTag(mc, 'SnapCool') and (os.clock() - cw < 7) and on() do
                RunService.Heartbeat:Wait(); mc = manaChar() or getChar()
            end
        elseif method == 'Instant (grab before snapback)' then
            tpInstant(goalCF); RunService.Heartbeat:Wait()
        else -- Glide (default)
            tpGlide(goalCF)
            local t0 = os.clock()
            repeat RunService.Heartbeat:Wait() until nearPos(pos, reach) or (os.clock() - t0 > 15) or not on()
        end
    end

    local function run()
        if active then return end
        active = true
        task.spawn(function()
            table.clear(visited); table.clear(visitedPos) -- fresh sweep on each start; within a run we never revisit
            while on() do
                local obj, part = pickNext()
                if not (obj and part) then
                    setStatus('No matching ingredients left'); task.wait(1.5)
                else
                    local pos    = part.Position
                    local reach  = (Options.IngReach and Options.IngReach.Value) or 8
                    local method = (Options.IngTPMethod and Options.IngTPMethod.Value) or 'Glide (no cooldown)'
                    local delay  = (Options.IngDelay and Options.IngDelay.Value) or 0.35
                    setStatus('-> ' .. ingName(obj))
                    attemptedAt[obj] = os.clock()
                    travel(pos, method, reach)
                    -- Fire the collect a few frames, then WAIT for the server to
                    -- actually remove the part from the folder (real confirmation)
                    -- before deciding. Only a part that survives the whole window
                    -- counts as a fail -> that's what stops it re-targeting the same
                    -- still-present Lava Flower forever.
                    for _ = 1, 6 do
                        if not obj.Parent then break end
                        collect(obj, part)
                        RunService.Heartbeat:Wait()
                    end
                    local t0 = os.clock()
                    repeat RunService.Heartbeat:Wait() until (not obj.Parent) or (os.clock() - t0 > delay)
                    if obj.Parent then failCount[obj] = (failCount[obj] or 0) + 1 end
                    -- mark visited (by Instance AND spot) whether or not the collect
                    -- landed -> never come back to it this run.
                    visited[obj] = true
                    visitedPos[posKey(part)] = true
                end
            end
            active = false
            setStatus('Idle')
        end)
    end
    if Toggles.IngredientFarm then
        Toggles.IngredientFarm:OnChanged(function()
            if Toggles.IngredientFarm.Value then run() else setStatus('Stopping...') end
        end)
    end
end)() -- end Ingredient Farm IIFE

refreshTPPlayers()
refreshTPAreas(true) -- silent pre-populate; the button below notifies if empty
track(Players.PlayerAdded:Connect(function() refreshTPPlayers() end))
track(Players.PlayerRemoving:Connect(function() refreshTPPlayers() end))

Library:OnUnload(function()
    MenuUnloaded = true -- makes the namecall hook pass everything through again
    -- Remove our __namecall hook FIRST, so the heavy UI teardown below (and all
    -- future namecalls) no longer run through it. This is what stops the freeze.
    if restoreNamecall then pcall(restoreNamecall) end
    if restoreFire then pcall(restoreFire) end
    for _, conn in pairs(Connections) do
        pcall(function() conn:Disconnect() end)
    end
    pcall(stopFly)
    pcall(restoreFog) -- put fog/atmosphere back if it was on
    if restoreKillBricks then pcall(restoreKillBricks) end -- un-neutralize kill bricks
    if restoreInvis then pcall(restoreInvis) end -- un-hide our character
    if espCleanup then pcall(espCleanup) end -- remove ESP drawings from screen
    if trinketCleanup then pcall(trinketCleanup) end -- remove trinket highlights + drawings
    if stopSpectate then pcall(stopSpectate) end -- put the camera back on us
    getgenv().GameTestMenu_Unload = nil
    print('Game test menu unloaded')
end)

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
-- Ignore AutoHopFarm in the config: its persistence is its OWN flag file (set on
-- toggle-on, cleared on toggle-off), so the config can't surprise-start the
-- server-hop farm on a normal load.
SaveManager:SetIgnoreIndexes({ 'MenuKeybind', 'AutoHopFarm' })
ThemeManager:SetFolder('GameTestMenu')
SaveManager:SetFolder('GameTestMenu')
SaveManager:BuildConfigSection(Tabs['UI Settings'])
ThemeManager:ApplyToTab(Tabs['UI Settings'])

-- ---- Keybinds: start BLANK + Backspace clears a bind ------------------------
-- Every keybind starts UNBOUND ('None') so nothing fires until YOU bind it. This
-- runs after all keypickers are built and BEFORE LoadAutoloadConfig, so a config
-- YOU saved still re-applies your own binds (only a fresh/unconfigured load is
-- blank). And since LinoriaLib captures whatever key you press while rebinding
-- (so Backspace would otherwise bind literally as 'Backspace'), each keypicker's
-- OnChanged catches that and resets it to 'None' -> Backspace = "clear this bind".
-- The menu open/close key (MenuKeybind) is left bound so you can't lock yourself
-- out of the menu.
for name, obj in pairs(Options) do
    if name ~= 'MenuKeybind' and type(obj) == 'table' and obj.Mode ~= nil
       and type(obj.SetValue) == 'function' then
        pcall(function()
            if obj.Value ~= 'None' then obj:SetValue({ 'None', obj.Mode or 'Toggle' }) end
        end)
        if type(obj.OnChanged) == 'function' then
            obj:OnChanged(function()
                if obj.Value == 'Backspace' then
                    pcall(function() obj:SetValue({ 'None', obj.Mode or 'Toggle' }) end)
                    Library:Notify('Keybind cleared (press a key to rebind)', 1.5)
                end
            end)
        end
    end
end

SaveManager:LoadAutoloadConfig()
