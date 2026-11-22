local ADDON = "LockboxCaseOpening"

-- Lockbox names (English client).
local BOXES = {
    ["Ornate Bronze Lockbox"]    = { 1.00, 0.68, 0.40 },
    ["Heavy Bronze Lockbox"]     = { 0.88, 0.56, 0.32 },
    ["Iron Lockbox"]             = { 0.66, 0.68, 0.74 },
    ["Strong Iron Lockbox"]      = { 0.62, 0.68, 0.82 },
    ["Steel Lockbox"]            = { 0.84, 0.88, 0.95 },
    ["Reinforced Steel Lockbox"] = { 0.74, 0.84, 1.00 },
    ["Mithril Lockbox"]          = { 0.55, 0.82, 1.00 },
    ["Thorium Lockbox"]          = { 0.55, 0.95, 0.60 },
    ["Eternium Lockbox"]         = { 0.80, 0.55, 1.00 },
}
local DEFAULT_TINT = { 0.6, 0.65, 0.75 }

-- Filler icons by quality: whites and greens only, so a blue or better drop feels special.
local FILLER = {
    [1] = { "INV_Misc_Note_01", "INV_Misc_Bandage_01", "INV_Misc_Food_19", "INV_Misc_Orb_01", "INV_Misc_Gear_01" },
    [2] = { "INV_Misc_Gem_Amethyst_01", "INV_Misc_Gem_Ruby_01", "INV_Jewelry_Ring_03", "INV_Sword_04", "INV_Shield_06" },
}
local COIN_ICON = "Interface\\Icons\\INV_Misc_Coin_01"

local TILE_W, TILE_H, ICON, GAP = 230, 200, 128, 12
local COUNT, WIN_INDEX = 60, 52
local STEP = TILE_W + GAP
local DISC, STRIP_Y = 760, 20
local VIEW_W = 1920 -- updated from the real screen width on each play
local DURATION, HOLD = 6.5, 2.5

-- Case intro: the chest drops in, holds, then fades as the spinner appears.
local CASE_SIZE = 460
local CASE_DROP, CASE_HOLD_END, CASE_T = 0.9, 1.9, 2.3
local CASE_START_Y = 800

local pendingUntil, pendingBox = 0, nil
local playing = false

-- Numeric ids for sounds whose SOUNDKIT name might be missing on some clients.
local SOUND_FALLBACK = {
    IG_QUEST_LIST_COMPLETE = 878, IG_MAINMENU_OPTION_CHECKBOX_ON = 856,
}
-- Case landing sound, and the reveal sound (which has a wind-up, so it starts REVEAL_LEAD seconds early).
local DROP_SOUND, DROP_LEAD = "RAID_BOSS_EMOTE_WARNING", 0
local REVEAL_SOUND, REVEAL_LEAD = "IG_QUEST_LIST_COMPLETE", 1.6

-- Play a sound by SOUNDKIT name (or a numeric id). Returns false if it isn't available here.
local function Snd(key, fallbackId)
    if key == "NONE" then return true end
    local id = tonumber(key) or (SOUNDKIT and SOUNDKIT[key]) or SOUND_FALLBACK[key] or fallbackId
    if not id then return false end
    PlaySound(id)
    return true
end

local function Bounce(x)
    if x < 1 / 2.75 then return 7.5625 * x * x end
    if x < 2 / 2.75 then x = x - 1.5 / 2.75; return 7.5625 * x * x + 0.75 end
    if x < 2.5 / 2.75 then x = x - 2.25 / 2.75; return 7.5625 * x * x + 0.9375 end
    x = x - 2.625 / 2.75
    return 7.5625 * x * x + 0.984375
end

-- This client only exposes the C_Item versions of some item APIs.
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo

local function Quality(q)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 1]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function RandomFiller()
    local q = math.random(100) <= 65 and 1 or 2 -- mostly white, some green
    local set = FILLER[q]
    return "Interface\\Icons\\" .. set[math.random(#set)], q
end

-- UI ---------------------------------------------------------------
local overlay, view, strip, tiles, nameText, Layout -- all file-local
local caseFrame, caseBody, caseTrim, caseShadow, caseGlow, marker
local SHADE = 0.5
local function Gradient(tex, orientation, r1, g1, b1, a1, r2, g2, b2, a2)
    tex:SetColorTexture(1, 1, 1, 1)
    tex:SetGradient(orientation, CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
end

local function Build()
    overlay = CreateFrame("Frame", nil, UIParent)
    overlay:SetAllPoints(UIParent)
    overlay:SetFrameStrata("FULLSCREEN_DIALOG")
    overlay:EnableMouse(true)
    overlay:Hide()

    view = CreateFrame("Frame", nil, overlay)
    view:SetHeight(TILE_H + 40)
    view:SetPoint("LEFT", overlay, "LEFT", 0, STRIP_Y)
    view:SetPoint("RIGHT", overlay, "RIGHT", 0, STRIP_Y)
    view:SetClipsChildren(true)

    strip = CreateFrame("Frame", nil, view)
    strip:SetSize(COUNT * STEP, TILE_H + 40)

    tiles = {}
    for i = 1, COUNT do
        local t = CreateFrame("Frame", nil, strip)
        t:SetSize(TILE_W, TILE_H)
        t:SetPoint("LEFT", strip, "LEFT", (i - 1) * STEP + GAP / 2, 0)
        t.bg = t:CreateTexture(nil, "BACKGROUND")
        t.bg:SetAllPoints()
        Gradient(t.bg, "VERTICAL", 0.13, 0.15, 0.2, 0.95, 0.28, 0.31, 0.38, 0.95)
        t.glow = t:CreateTexture(nil, "BACKGROUND", nil, 1)
        t.glow:SetPoint("BOTTOMLEFT")
        t.glow:SetPoint("BOTTOMRIGHT")
        t.glow:SetHeight(TILE_H * 0.55)
        t.icon = t:CreateTexture(nil, "ARTWORK")
        t.icon:SetSize(ICON, ICON)
        t.icon:SetPoint("CENTER", 0, 8)
        t.bar = t:CreateTexture(nil, "OVERLAY")
        t.bar:SetPoint("BOTTOMLEFT")
        t.bar:SetPoint("BOTTOMRIGHT")
        t.bar:SetHeight(8)
        tiles[i] = t
    end

    -- Shade: dark over everything (tiles included) except a circular window in the middle.
    local shade = CreateFrame("Frame", nil, overlay)
    shade:SetAllPoints()
    shade:SetFrameLevel(view:GetFrameLevel() + 6)
    local hole = shade:CreateTexture(nil, "BACKGROUND")
    hole:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\circle_hole.tga")
    hole:SetSize(DISC, DISC)
    hole:SetPoint("CENTER", overlay, "CENTER", 0, STRIP_Y)
    hole:SetVertexColor(0, 0, 0, SHADE)
    local rT, rB, rL, rR = {}, {}, {}, {}
    local rects = {}
    for i = 1, 4 do
        rects[i] = shade:CreateTexture(nil, "BACKGROUND")
        rects[i]:SetColorTexture(0, 0, 0, SHADE)
    end
    rT, rB, rL, rR = rects[1], rects[2], rects[3], rects[4]
    rT:SetPoint("TOPLEFT", shade, "TOPLEFT")
    rT:SetPoint("TOPRIGHT", shade, "TOPRIGHT")
    rB:SetPoint("BOTTOMLEFT", shade, "BOTTOMLEFT")
    rB:SetPoint("BOTTOMRIGHT", shade, "BOTTOMRIGHT")
    Layout = function()
        local W, H = UIParent:GetWidth(), UIParent:GetHeight()
        local top = math.max(0, H / 2 - STRIP_Y - DISC / 2)
        local bot = math.max(0, H / 2 + STRIP_Y - DISC / 2)
        local side = math.max(0, W / 2 - DISC / 2)
        rT:SetHeight(top)
        rB:SetHeight(bot)
        rL:ClearAllPoints()
        rL:SetPoint("TOPLEFT", shade, "TOPLEFT", 0, -top)
        rL:SetPoint("BOTTOMLEFT", shade, "BOTTOMLEFT", 0, bot)
        rL:SetWidth(side)
        rR:ClearAllPoints()
        rR:SetPoint("TOPRIGHT", shade, "TOPRIGHT", 0, -top)
        rR:SetPoint("BOTTOMRIGHT", shade, "BOTTOMRIGHT", 0, bot)
        rR:SetWidth(side)
    end

    marker = CreateFrame("Frame", nil, overlay)
    marker:SetAllPoints(view)
    marker:SetFrameLevel(view:GetFrameLevel() + 10)
    local line = marker:CreateTexture(nil, "OVERLAY")
    line:SetSize(4, TILE_H + 40)
    line:SetPoint("CENTER")
    line:SetColorTexture(1, 0.85, 0.1, 1)

    -- Case art: drawn chest (greyscale body tinted per box, plus gold trim), above the shade.
    local art = "Interface\\AddOns\\" .. ADDON .. "\\"
    caseFrame = CreateFrame("Frame", nil, overlay)
    caseFrame:SetAllPoints()
    caseFrame:SetFrameLevel(view:GetFrameLevel() + 15)
    caseGlow = caseFrame:CreateTexture(nil, "BACKGROUND")
    caseGlow:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    caseGlow:SetBlendMode("ADD")
    caseGlow:SetSize(CASE_SIZE * 1.3, CASE_SIZE * 1.3)
    caseShadow = caseFrame:CreateTexture(nil, "BORDER")
    caseShadow:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    caseShadow:SetVertexColor(0, 0, 0, 0.5)
    caseShadow:SetSize(CASE_SIZE * 0.85, CASE_SIZE * 0.13)
    caseBody = caseFrame:CreateTexture(nil, "ARTWORK")
    caseBody:SetTexture(art .. "case_wood.tga")
    caseBody:SetSize(CASE_SIZE, CASE_SIZE)
    caseTrim = caseFrame:CreateTexture(nil, "OVERLAY")
    caseTrim:SetTexture(art .. "case_metal.tga")
    caseTrim:SetSize(CASE_SIZE, CASE_SIZE)
    caseFrame:Hide()

    -- Text sits above the shade so it stays bright.
    local text = CreateFrame("Frame", nil, overlay)
    text:SetAllPoints()
    text:SetFrameLevel(view:GetFrameLevel() + 20)

    local title = text:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("CENTER", overlay, "CENTER", 0, (STRIP_Y + DISC / 2 + 60) / 2) -- offset halved: title is scaled x2
    title:SetTextColor(1, 1, 1)
    title:SetText("Unlock Container")
    title:SetScale(2)

    local sub = text:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    sub:SetPoint("TOP", title, "BOTTOM", 0, -10)
    sub:SetTextColor(0.8, 0.82, 0.88)
    sub:SetText("This container can only be opened once")

    nameText = text:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    nameText:SetPoint("TOP", view, "BOTTOM", 0, -25) -- offset scaled for 1.6x
    nameText:SetScale(1.6)

    local hint = text:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
    hint:SetPoint("BOTTOM", overlay, "BOTTOM", 0, 60)
    hint:SetText("Click to skip")
end

-- Tell the guild about a blue-or-better find. Test runs have no link, so they stay quiet.
local function Announce(quality, link)
    if link and quality >= 3 and LockboxCaseOpeningDB.announce and IsInGuild() then
        local text = ("%s just found %s in a lock box!"):format(UnitName("player"), link)
        local ok, err = pcall(C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage, text, "GUILD")
        if not ok then print("|cffff4040LockboxCaseOpening:|r guild message failed: " .. tostring(err)) end
    end
end

-- Held until the reveal so the message doesn't spoil the spin; sent on skip too.
local announcePending

local function SendPendingAnnounce()
    local a = announcePending
    announcePending = nil
    if a then Announce(a[1], a[2]) end
end

local function Finish()
    playing = false
    SendPendingAnnounce()
    overlay:SetScript("OnUpdate", nil)
    overlay:Hide()
    if LootFrame then LootFrame:SetAlpha(1) end
end

local function Play(icon, quality, label, boxName, skipIntro, link, force)
    if playing or not (force or LockboxCaseOpeningDB.enabled) then
        Announce(quality, link) -- nothing to wait for, so announce straight away
        return
    end
    if not overlay then Build() end
    nameText:SetText("")

    local tint = BOXES[boxName or ""] or DEFAULT_TINT
    caseTrim:SetVertexColor(tint[1], tint[2], tint[3]) -- metal takes the box colour; wood stays natural
    caseGlow:SetVertexColor(tint[1], tint[2], tint[3], 1)

    for i = 1, COUNT do
        local t = tiles[i]
        local tex, q
        if i == WIN_INDEX then tex, q = icon, quality else tex, q = RandomFiller() end
        t.icon:SetTexture(tex)
        local r, g, b = Quality(q)
        t.bar:SetColorTexture(r, g, b, 1)
        Gradient(t.glow, "VERTICAL", r, g, b, 0.55, r, g, b, 0)
    end

    VIEW_W = UIParent:GetWidth()
    Layout()
    strip:ClearAllPoints()
    strip:SetPoint("LEFT", view, "LEFT", 0, 0)
    local jitter = math.random(-(TILE_W / 2 - 10), TILE_W / 2 - 10)
    local target = (WIN_INDEX - 1) * STEP + STEP / 2 + jitter - VIEW_W / 2
    local elapsed, lastIdx, done, spinning, landed, revealPlayed =
        0, math.floor((VIEW_W / 2) / STEP), false, false, false, false

    -- The spinner stays hidden (Hide, not alpha) while the case plays.
    if skipIntro then
        elapsed = CASE_T
        marker:Show()
        caseFrame:Hide()
    else
        view:Hide()
        marker:Hide()
        caseFrame:Show()
    end

    local function Step(dt)
        elapsed = elapsed + dt

        -- Phase 1: case drop-in, hold, exit.
        if elapsed < CASE_T then
            local q = math.min(elapsed / CASE_DROP, 1)
            if not landed and elapsed >= math.max(0, CASE_DROP / 2.75 - DROP_LEAD) then -- first ground impact, minus lead
                landed = true
                Snd(DROP_SOUND)
            end
            local y = STRIP_Y + 20 + CASE_START_Y * (1 - Bounce(q))
            local tilt = 0.28 * (1 - q) * math.cos(q * 9)
            local alpha, scale = math.min(elapsed / 0.15, 1), 1
            local glowA = 0.28 * q * (0.8 + 0.2 * math.sin(elapsed * 4))
            if elapsed > CASE_HOLD_END then
                local x = (elapsed - CASE_HOLD_END) / (CASE_T - CASE_HOLD_END)
                alpha, scale = 1 - x, 1 + 0.15 * x
                view:Show()
                view:SetAlpha(x)
            end
            caseBody:ClearAllPoints()
            caseBody:SetPoint("CENTER", overlay, "CENTER", 0, y)
            caseBody:SetSize(CASE_SIZE * scale, CASE_SIZE * scale)
            caseBody:SetRotation(tilt)
            caseTrim:ClearAllPoints()
            caseTrim:SetPoint("CENTER", overlay, "CENTER", 0, y)
            caseTrim:SetSize(CASE_SIZE * scale, CASE_SIZE * scale)
            caseTrim:SetRotation(tilt)
            caseBody:SetAlpha(alpha)
            caseTrim:SetAlpha(alpha)
            caseShadow:ClearAllPoints()
            caseShadow:SetPoint("CENTER", overlay, "CENTER", 0, STRIP_Y + 20 - CASE_SIZE * 0.27)
            caseShadow:SetAlpha(alpha * q)
            caseGlow:ClearAllPoints()
            caseGlow:SetPoint("CENTER", overlay, "CENTER", 0, STRIP_Y + 10)
            caseGlow:SetAlpha(glowA * alpha)
            return
        end

        -- Phase 2: spin.
        if not spinning then
            spinning = true
            caseFrame:Hide()
            view:Show()
            view:SetAlpha(1)
            marker:Show()
        end
        local spin = elapsed - CASE_T
        local p = math.min(spin / DURATION, 1)
        local eased = 1 - (1 - p) ^ 4
        local off = target * eased
        strip:ClearAllPoints()
        strip:SetPoint("LEFT", view, "LEFT", -off, 0)
        local idx = math.floor((off + VIEW_W / 2) / STEP)
        if idx ~= lastIdx and not done then
            lastIdx = idx
            Snd("IG_MAINMENU_OPTION_CHECKBOX_ON", 856) -- tick
        end
        if not revealPlayed and spin >= DURATION - REVEAL_LEAD then
            revealPlayed = true
            Snd(REVEAL_SOUND) -- starts early to cover its wind-up
        end
        if p >= 1 and not done then
            done = true
            local r, g, b = Quality(quality)
            nameText:SetText(label)
            nameText:SetTextColor(r, g, b)
            SendPendingAnnounce()
        end
        if spin >= DURATION + HOLD then Finish() end
    end

    -- Everything above can error; only now is the animation committed.
    playing = true
    announcePending = { quality, link }
    if LootFrame then LootFrame:SetAlpha(0) end
    overlay:Show()
    overlay:SetScript("OnMouseDown", Finish)
    overlay:SetScript("OnUpdate", function(_, dt)
        local ok, err = pcall(Step, dt)
        if not ok then
            print("|cffff4040LockboxCaseOpening error:|r " .. tostring(err))
            Finish()
        end
    end)
end

-- Detection ------------------------------------------------------------
local function OnUse(bag, slot)
    local getLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
    if not getLink then return end
    local link = getLink(bag, slot)
    local name = link and link:match("%[(.-)%]")
    if name and BOXES[name] then
        pendingUntil = GetTime() + 3
        pendingBox = name
    end
end
if C_Container and C_Container.UseContainerItem then hooksecurefunc(C_Container, "UseContainerItem", OnUse) end
if UseContainerItem then hooksecurefunc("UseContainerItem", OnUse) end

local function BestLoot()
    local best, bestScore
    local n = GetNumLootItems() or 0
    for i = 1, n do
        if LootSlotHasItem(i) then
            local link = GetLootSlotLink(i)
            local tex = GetLootSlotInfo(i)
            local _, _, q, _, _, _, _, _, _, itex, price = GetItemInfo(link or "")
            -- item data may not be cached yet; fall back to the quality code embedded in the link
            q = q or tonumber(link and link:match("|cnIQ(%d)")) or 1
            local score = q * 1e9 + (price or 0)
            if not bestScore or score > bestScore then
                bestScore = score
                best = { icon = itex or tex, quality = q, link = link, label = link and link:match("%[(.-)%]") or "Loot" }
            end
        end
    end
    if best then return best end
    if n > 0 then return { icon = COIN_ICON, quality = 1, label = "Coin" } end
end

-- LOOT_READY fires before auto-loot empties the window, so try it first; LOOT_OPENED is the fallback.
local function TryPlay(event)
    if GetTime() >= pendingUntil then return end
    -- A locked/cancelled box can leave the window armed; ignore loot that clearly comes from something else.
    local src = GetLootSourceInfo and GetLootSourceInfo(1)
    if type(src) == "string" and (src:find("^Creature") or src:find("^Vehicle") or src:find("^GameObject")) then return end
    local best = BestLoot()
    if best then
        pendingUntil = 0
        Play(best.icon, best.quality, best.label, pendingBox, nil, best.link)
    elseif event == "LOOT_OPENED" then
        pendingUntil = 0
        print("|cffff8000LockboxCaseOpening:|r opened a lockbox but found no loot to show.")
    end
end

-- Options panel -------------------------------------------------------
local PANEL_NAME = "LockboxCaseOpening"
local optionsCategory
local optionsRefresh = function() end

local function CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = PANEL_NAME

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(PANEL_NAME)

    local enable = CreateFrame("CheckButton", "LockboxCaseOpeningEnableCheck", panel, "UICheckButtonTemplate")
    enable:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -48)
    _G[enable:GetName() .. "Text"]:SetText("Play the case opening animation")
    enable:SetScript("OnClick", function(self) LockboxCaseOpeningDB.enabled = self:GetChecked() and true or false end)

    local announce = CreateFrame("CheckButton", "LockboxCaseOpeningAnnounceCheck", panel, "UICheckButtonTemplate")
    announce:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -80)
    _G[announce:GetName() .. "Text"]:SetText("Tell guild chat when a lockbox gives a blue or better item")
    announce:SetScript("OnClick", function(self) LockboxCaseOpeningDB.announce = self:GetChecked() and true or false end)

    local test = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    test:SetSize(160, 24)
    test:SetText("Play full animation")
    test:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -120)
    test:SetScript("OnClick", function() SlashCmdList.LOCKBOXCASE("test") end)

    function optionsRefresh()
        enable:SetChecked(LockboxCaseOpeningDB.enabled)
        announce:SetChecked(LockboxCaseOpeningDB.announce)
    end
    panel:SetScript("OnShow", optionsRefresh)

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        optionsCategory = Settings.RegisterCanvasLayoutCategory(panel, PANEL_NAME)
        Settings.RegisterAddOnCategory(optionsCategory)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
        optionsCategory = panel
    end
end

local function OpenOptions()
    if Settings and Settings.OpenToCategory and optionsCategory and optionsCategory.GetID then
        Settings.OpenToCategory(optionsCategory:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory and optionsCategory then
        InterfaceOptionsFrame_OpenToCategory(optionsCategory)
        InterfaceOptionsFrame_OpenToCategory(optionsCategory) -- first call can miss
    else
        print("open Esc > Options > AddOns > " .. PANEL_NAME)
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("LOOT_READY")
f:RegisterEvent("LOOT_OPENED")
f:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" and arg == ADDON then
        LockboxCaseOpeningDB = LockboxCaseOpeningDB or {}
        if LockboxCaseOpeningDB.enabled == nil then LockboxCaseOpeningDB.enabled = true end
        if LockboxCaseOpeningDB.announce == nil then LockboxCaseOpeningDB.announce = true end
        CreateOptionsPanel()
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
        TryPlay(event)
    end
end)

SLASH_LOCKBOXCASE1 = "/lockcase"
SlashCmdList.LOCKBOXCASE = function(msg)
    msg = (msg or ""):lower()
    if msg == "test" then
        Play("Interface\\Icons\\INV_Sword_27", 3, "Test Item", "Strong Iron Lockbox", nil, nil, true)
    elseif msg == "spin" then
        Play("Interface\\Icons\\INV_Sword_27", 3, "Test Item", "Strong Iron Lockbox", true, nil, true)
    elseif msg == "options" or msg == "config" then
        OpenOptions()
    elseif msg:match("^findsound") then
        local pat = msg:match("^findsound%s+(.+)")
        if not pat then print("/lockcase findsound <text> - search the game's SOUNDKIT names") return end
        if not SOUNDKIT then print("no SOUNDKIT table on this client") return end
        local names = {}
        for k, v in pairs(SOUNDKIT) do
            if tostring(k):lower():find(pat, 1, true) then names[#names + 1] = tostring(k) .. "=" .. tostring(v) end
        end
        table.sort(names)
        print(("%d match(es) for '%s'"):format(#names, pat))
        for i = 1, math.min(#names, 25) do print("  " .. names[i]) end
    elseif msg:match("^sound") then
        local key = msg:match("^sound%s+(%S+)")
        if not key then print("/lockcase sound <NAME or id> - audition a sound") return end
        Snd(tonumber(key) or key:upper())
    elseif msg == "debug" then
        if not overlay then print("not built yet - run /lockcase test first") return end
        local t1, tw = tiles[1], tiles[WIN_INDEX]
        print(("overlay shown=%s view shown=%s visible=%s effAlpha=%.2f size=%.0fx%.0f"):format(tostring(overlay:IsShown()), tostring(view:IsShown()), tostring(view:IsVisible()), view:GetEffectiveAlpha(), view:GetWidth(), view:GetHeight()))
        print(("strip left=%s width=%s tile1 left=%s visible=%s tile1 icon=%s"):format(tostring(strip:GetLeft()), tostring(strip:GetWidth()), tostring(t1:GetLeft()), tostring(t1:IsVisible()), tostring(t1.icon:GetTexture())))
        print(("winner tile left=%s icon=%s UIParent=%.0fx%.0f"):format(tostring(tw:GetLeft()), tostring(tw.icon:GetTexture()), UIParent:GetWidth(), UIParent:GetHeight()))
    elseif msg == "on" or msg == "off" then
        LockboxCaseOpeningDB.enabled = (msg == "on")
        print("|cff00ff00LockboxCaseOpening|r " .. msg)
    else
        print("/lockcase options | test | spin | debug | findsound <text> | sound <name> | on | off")
    end
end
