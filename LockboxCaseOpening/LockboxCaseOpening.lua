local ADDON = "LockboxCaseOpening"

-- Lockbox names (English client).
local BOXES = {
    ["Ornate Bronze Lockbox"] = true, ["Heavy Bronze Lockbox"] = true,
    ["Iron Lockbox"] = true, ["Strong Iron Lockbox"] = true,
    ["Steel Lockbox"] = true, ["Reinforced Steel Lockbox"] = true,
    ["Mithril Lockbox"] = true, ["Thorium Lockbox"] = true,
    ["Eternium Lockbox"] = true,
}

-- Filler icons by quality (1 white, 2 green, 3 blue).
local FILLER = {
    [1] = { "INV_Misc_Note_01", "INV_Misc_Bandage_01", "INV_Misc_Food_19", "INV_Misc_Orb_01", "INV_Misc_Gear_01" },
    [2] = { "INV_Misc_Gem_Amethyst_01", "INV_Misc_Gem_Ruby_01", "INV_Jewelry_Ring_03", "INV_Sword_04", "INV_Shield_06" },
    [3] = { "INV_Sword_27", "INV_Axe_09", "INV_Helmet_02", "INV_Jewelry_Necklace_05", "INV_Misc_Gem_Diamond_01" },
}
local COIN_ICON = "Interface\\Icons\\INV_Misc_Coin_01"

local TILE, GAP, COUNT, WIN_INDEX = 64, 8, 60, 52
local STEP = TILE + GAP
local VIEW_W = 640
local DURATION, HOLD = 6.5, 2.5

local pendingUntil = 0
local playing = false

local function Quality(q) return GetItemQualityColor(q or 1) end

local function RandomFiller()
    local roll = math.random(100)
    local q = roll <= 60 and 1 or (roll <= 90 and 2 or 3)
    local set = FILLER[q]
    return "Interface\\Icons\\" .. set[math.random(#set)], q
end

-- UI ---------------------------------------------------------------
local overlay, view, strip, tiles, nameText
local function Build()
    overlay = CreateFrame("Frame", nil, UIParent)
    overlay:SetAllPoints(UIParent)
    overlay:SetFrameStrata("FULLSCREEN_DIALOG")
    overlay:EnableMouse(true)
    overlay:Hide()
    local dim = overlay:CreateTexture(nil, "BACKGROUND")
    dim:SetAllPoints()
    dim:SetColorTexture(0, 0, 0, 0.6)

    view = CreateFrame("Frame", nil, overlay)
    view:SetSize(VIEW_W, TILE + 24)
    view:SetPoint("CENTER", 0, 60)
    view:SetClipsChildren(true)
    local bg = view:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.07, 0.95)

    strip = CreateFrame("Frame", nil, view)
    strip:SetSize(COUNT * STEP, TILE + 24)

    tiles = {}
    for i = 1, COUNT do
        local t = CreateFrame("Frame", nil, strip)
        t:SetSize(TILE, TILE)
        t:SetPoint("LEFT", strip, "LEFT", (i - 1) * STEP + GAP / 2, 0)
        t.border = t:CreateTexture(nil, "BACKGROUND")
        t.border:SetPoint("TOPLEFT", -3, 3)
        t.border:SetPoint("BOTTOMRIGHT", 3, -3)
        t.icon = t:CreateTexture(nil, "ARTWORK")
        t.icon:SetAllPoints()
        tiles[i] = t
    end

    local marker = CreateFrame("Frame", nil, view)
    marker:SetAllPoints()
    marker:SetFrameLevel(view:GetFrameLevel() + 10)
    local line = marker:CreateTexture(nil, "OVERLAY")
    line:SetSize(3, TILE + 24)
    line:SetPoint("CENTER")
    line:SetColorTexture(1, 0.82, 0, 1)

    nameText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    nameText:SetPoint("TOP", view, "BOTTOM", 0, -20)

    local hint = overlay:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOP", nameText, "BOTTOM", 0, -8)
    hint:SetText("Click to skip")
end

local function Finish()
    playing = false
    overlay:SetScript("OnUpdate", nil)
    overlay:Hide()
    if LootFrame then LootFrame:SetAlpha(1) end
end

local function Play(icon, quality, label)
    if playing or not LockboxCaseOpeningDB.enabled then return end
    if not overlay then Build() end
    playing = true
    nameText:SetText("")

    for i = 1, COUNT do
        local t = tiles[i]
        local tex, q
        if i == WIN_INDEX then tex, q = icon, quality else tex, q = RandomFiller() end
        t.icon:SetTexture(tex)
        t.border:SetColorTexture(Quality(q))
    end

    local jitter = math.random(-(TILE / 2 - 6), TILE / 2 - 6)
    local target = (WIN_INDEX - 1) * STEP + STEP / 2 + jitter - VIEW_W / 2
    local elapsed, lastIdx, done = 0, 0, false

    if LootFrame then LootFrame:SetAlpha(0) end
    overlay:Show()
    overlay:SetScript("OnMouseDown", Finish)
    overlay:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        local p = math.min(elapsed / DURATION, 1)
        local eased = 1 - (1 - p) ^ 4
        local off = target * eased
        strip:ClearAllPoints()
        strip:SetPoint("LEFT", view, "LEFT", -off, 0)
        local idx = math.floor((off + VIEW_W / 2) / STEP)
        if idx ~= lastIdx and not done then
            lastIdx = idx
            PlaySound(856) -- generic UI tick
        end
        if p >= 1 and not done then
            done = true
            local r, g, b = Quality(quality)
            nameText:SetText(label)
            nameText:SetTextColor(r, g, b)
            PlaySound(quality >= 3 and 8959 or 888)
        end
        if elapsed >= DURATION + HOLD then Finish() end
    end)
end

-- Detection ------------------------------------------------------------
local function OnUse(bag, slot)
    local getLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
    local link = getLink(bag, slot)
    local name = link and GetItemInfo(link)
    if name and BOXES[name] then pendingUntil = GetTime() + 3 end
end
if C_Container and C_Container.UseContainerItem then hooksecurefunc(C_Container, "UseContainerItem", OnUse) end
if UseContainerItem then hooksecurefunc("UseContainerItem", OnUse) end

local function BestLoot()
    local best, bestScore
    for i = 1, GetNumLootItems() do
        if LootSlotHasItem(i) then
            local link = GetLootSlotLink(i)
            local tex = GetLootSlotInfo(i)
            local _, _, q, _, _, _, _, _, _, itex, price = GetItemInfo(link or "")
            q = q or 1
            local score = q * 1e9 + (price or 0)
            if not bestScore or score > bestScore then
                bestScore = score
                best = { icon = itex or tex, quality = q, label = link and link:match("%[(.-)%]") or "Loot" }
            end
        end
    end
    if best then return best end
    if GetNumLootItems() > 0 then return { icon = COIN_ICON, quality = 1, label = "Coin" } end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("LOOT_OPENED")
f:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" and arg == ADDON then
        LockboxCaseOpeningDB = LockboxCaseOpeningDB or {}
        if LockboxCaseOpeningDB.enabled == nil then LockboxCaseOpeningDB.enabled = true end
    elseif event == "LOOT_OPENED" and GetTime() < pendingUntil then
        pendingUntil = 0
        local best = BestLoot()
        if best then Play(best.icon, best.quality, best.label) end
    end
end)

SLASH_LOCKBOXCASE1 = "/lockcase"
SlashCmdList.LOCKBOXCASE = function(msg)
    msg = (msg or ""):lower()
    if msg == "test" then
        Play("Interface\\Icons\\INV_Sword_27", 3, "Test Item")
    elseif msg == "on" or msg == "off" then
        LockboxCaseOpeningDB.enabled = (msg == "on")
        print("|cff00ff00LockboxCaseOpening|r " .. msg)
    else
        print("/lockcase test | on | off")
    end
end
