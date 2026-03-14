local addonName, addonTable = ...

local isMLActive = false
local mlFrame = CreateFrame("Frame")
local RT_RefreshLogUI = nil
local RT_RefreshStatsUI = nil

local function CreateEmptyStats()
    return {
        epic = 0,
        rare = 0,
        uncommon = 0,
        common = 0,
        shards = 0
    }
end

local defaultSettings = {
    lootCollector = UnitName("player"),
    shardsCollector = UnitName("player"),
    boeCollector = UnitName("player"),
    enabled = false,
    minQuality = 1,
    lootLog = {},
    whisperEnabled = true,
    stats = CreateEmptyStats()
}

local function EnsureSavedVariables()
    if not RTMasterLooterSave then
        RTMasterLooterSave = CopyTable(defaultSettings)
    end

    if not RTMasterLooterSave.stats then
        RTMasterLooterSave.stats = CreateEmptyStats()
    end

    if RTMasterLooterSave.stats.shards == nil then
        RTMasterLooterSave.stats.shards = 0
    end

    if RTMasterLooterSave.lootCollector == nil or RTMasterLooterSave.lootCollector == "" then
        RTMasterLooterSave.lootCollector = UnitName("player")
    end

    if RTMasterLooterSave.shardsCollector == nil or RTMasterLooterSave.shardsCollector == "" then
        RTMasterLooterSave.shardsCollector = UnitName("player")
    end

    if RTMasterLooterSave.boeCollector == nil or RTMasterLooterSave.boeCollector == "" then
        RTMasterLooterSave.boeCollector = UnitName("player")
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, arg1)
    if arg1 ~= addonName then
        return
    end

    EnsureSavedVariables()
    isMLActive = RTMasterLooterSave.enabled

    self:UnregisterEvent("ADDON_LOADED")
end)

local function IsPlayerMasterLooter()
    if not IsInRaid() then
        return false
    end

    local method, mlPartyID, mlRaidID = GetLootMethod()
    return (method == "master") and (mlPartyID == 0 or mlRaidID == 0)
end

local function BuildMasterLootCandidateMap()
    local candidates = {}

    for index = 1, 40 do
        local candidateName = GetMasterLootCandidate(index)
        if candidateName then
            candidates[candidateName] = index
        end
    end

    return candidates
end

local function GetTargetCollectorName(itemLink, quality)
    local targetName = RTMasterLooterSave.lootCollector
    local _, _, _, _, _, _, _, _, _, _, _, _, _, bindType = GetItemInfo(itemLink)

    if bindType == 2 then
        targetName = RTMasterLooterSave.boeCollector
    elseif quality == 5 then
        targetName = RTMasterLooterSave.shardsCollector
    end

    return targetName
end

local function DistributeLoot()
    if not isMLActive then
        return
    end

    if not IsInRaid() then
        return
    end

    if not IsPlayerMasterLooter() then
        return
    end

    local candidates = BuildMasterLootCandidateMap()
    local numItems = GetNumLootItems()

    for slot = 1, numItems do
        local _, _, _, quality = GetLootSlotInfo(slot)
        local itemLink = GetLootSlotLink(slot)

        if itemLink and quality and quality >= RTMasterLooterSave.minQuality then
            local targetName = GetTargetCollectorName(itemLink, quality)
            local targetIndex = candidates[targetName]

            if targetIndex then
                GiveMasterLoot(slot, targetIndex)
            end
        end
    end
end

local function AddLootStatByQuality(quality)
    local stats = RTMasterLooterSave.stats

    if quality == 5 then
        stats.shards = stats.shards + 1
    elseif quality == 4 then
        stats.epic = stats.epic + 1
    elseif quality == 3 then
        stats.rare = stats.rare + 1
    elseif quality == 2 then
        stats.uncommon = stats.uncommon + 1
    elseif quality <= 1 then
        stats.common = stats.common + 1
    end
end

local function AddLootLogEntry(itemLink, playerName)
    local lootLog = RTMasterLooterSave.lootLog

    lootLog[#lootLog + 1] = {
        item = itemLink,
        to = playerName,
        time = date("%H:%M:%S")
    }

    if #lootLog > 1000 then
        table.remove(lootLog, 1)
    end
end

local function TryWhisperCollector(playerName, itemLink)
    if not RTMasterLooterSave.whisperEnabled then
        return
    end

    if not IsPlayerMasterLooter() then
        return
    end

    if playerName == UnitName("player") then
        return
    end

    local isCollector =
        playerName == RTMasterLooterSave.lootCollector or
        playerName == RTMasterLooterSave.shardsCollector or
        playerName == RTMasterLooterSave.boeCollector

    if not isCollector then
        return
    end

    SendChatMessage(
        "RaidTools: I've sent you " .. itemLink .. ". Please check your bags.",
        "WHISPER",
        nil,
        playerName
    )
end

local function ParseLootMessage(msg)
    local playerName, itemLink = msg:match("([^%s]+) receives loot: (.+)%.")

    if playerName and itemLink then
        return playerName, itemLink
    end

    local receivedItemLink = msg:match("You receive loot: (.+)%.")

    if receivedItemLink then
        return UnitName("player"), receivedItemLink
    end

    return nil, nil
end

local function OnLootMsg(msg)
    if not IsInRaid() then
        return
    end

    local playerName, itemLink = ParseLootMessage(msg)

    if not playerName or not itemLink then
        return
    end

    if itemLink:find("money:") then
        return
    end

    local _, _, quality = GetItemInfo(itemLink)
    if not quality then
        return
    end

    if quality < RTMasterLooterSave.minQuality then
        return
    end

    AddLootLogEntry(itemLink, playerName)
    AddLootStatByQuality(quality)

    if RT_RefreshLogUI then
        RT_RefreshLogUI()
    end

    if RT_RefreshStatsUI then
        RT_RefreshStatsUI()
    end

    TryWhisperCollector(playerName, itemLink)
end

mlFrame:RegisterEvent("LOOT_OPENED")
mlFrame:RegisterEvent("CHAT_MSG_LOOT")
mlFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "LOOT_OPENED" then
        DistributeLoot()
        return
    end

    if event == "CHAT_MSG_LOOT" then
        OnLootMsg(...)
    end
end)

local function ApplyPixelStyle(frame, width, height)
    frame:SetSize(width, height)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)
    frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
end

local function CreatePixelInput(parent, width, height)
    local bg = CreateFrame("Frame", nil, parent)
    ApplyPixelStyle(bg, width, height)

    local editBox = CreateFrame("EditBox", nil, bg)
    editBox:SetPoint("TOPLEFT", 4, 0)
    editBox:SetPoint("BOTTOMRIGHT", -4, 0)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetAutoFocus(false)

    if editBox.Left then
        editBox.Left:Hide()
    end

    if editBox.Middle then
        editBox.Middle:Hide()
    end

    if editBox.Right then
        editBox.Right:Hide()
    end

    return bg, editBox
end

function CreateMasterLooterTabContent(parent, onClose)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints()
    f:Hide()

    local E, S = TryGetElvUISkinModule()

    local LOG_LEFT = 20
    local LOG_RIGHT = 20
    local LOG_TOP = -32
    local LOG_HEIGHT = 120
    local LOG_PADDING = 8
    local LOG_SCROLLBAR_SPACE = 24

    local logLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    logLbl:SetPoint("TOPLEFT", LOG_LEFT, -15)
    logLbl:SetText("Recent Loot Log (Filtered):")

    local logBg = CreateFrame("Frame", nil, f)
    logBg:SetPoint("TOPLEFT", LOG_LEFT, LOG_TOP)
    logBg:SetPoint("TOPRIGHT", -LOG_RIGHT, LOG_TOP)
    logBg:SetHeight(LOG_HEIGHT)
    logBg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1
    })
    logBg:SetBackdropColor(0, 0, 0, 0.9)
    logBg:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    local clearLog = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearLog:SetSize(50, 18)
    clearLog:SetPoint("BOTTOMRIGHT", logBg, "TOPRIGHT", 0, 2)
    clearLog:SetText("Clear")
    if S then
        S:HandleButton(clearLog)
    end

    local logScroll = CreateFrame("ScrollFrame", "RTMasterLooterScroll", logBg, "UIPanelScrollFrameTemplate")
    logScroll:SetPoint("TOPLEFT", LOG_PADDING, -LOG_PADDING)
    logScroll:SetPoint("BOTTOMRIGHT", -LOG_SCROLLBAR_SPACE, LOG_PADDING)

    local logContent = CreateFrame("Frame", nil, logScroll)
    logContent:SetSize(1, 1)
    logScroll:SetScrollChild(logContent)

    local logText = logContent:CreateFontString(nil, "OVERLAY", "ChatFontSmall")
    logText:SetPoint("TOPLEFT", 0, 0)
    logText:SetJustifyH("LEFT")
    logText:SetJustifyV("TOP")

    local function UpdateLogWidth()
        local availableWidth = logBg:GetWidth() - (LOG_PADDING * 2) - LOG_SCROLLBAR_SPACE
        if availableWidth < 50 then
            availableWidth = 50
        end

        logContent:SetWidth(availableWidth)
        logText:SetWidth(availableWidth)
    end

    logBg:SetScript("OnSizeChanged", function()
        UpdateLogWidth()

        if RT_RefreshLogUI then
            RT_RefreshLogUI()
        end
    end)

    RT_RefreshLogUI = function()
        if not f:IsVisible() then
            return
        end

        UpdateLogWidth()

        local logs = RTMasterLooterSave.lootLog or {}
        local lines = {}

        for index = #logs, 1, -1 do
            local entry = logs[index]
            lines[#lines + 1] = string.format("[%s] %s -> %s", entry.time, entry.item, entry.to)
        end

        if #lines == 0 then
            logText:SetText("No logs yet.")
        else
            logText:SetText(table.concat(lines, "\n"))
        end

        logContent:SetHeight(logText:GetStringHeight() + 20)
        logScroll:UpdateScrollChildRect()
    end

    clearLog:SetScript("OnClick", function()
        RTMasterLooterSave.lootLog = {}
        RTMasterLooterSave.stats = CreateEmptyStats()

        RT_RefreshLogUI()
        RT_RefreshStatsUI()
    end)

    local statsText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statsText:SetPoint("TOPLEFT", 25, -155)

    RT_RefreshStatsUI = function()
        local stats = RTMasterLooterSave.stats
        statsText:SetText(string.format(
            "|cffff8000Shard: %d|r  |cffa335eeEpic: %d|r  |cff0070ddRare: %d|r  |cff1eff00Uncommon: %d|r",
            stats.shards,
            stats.epic,
            stats.rare,
            stats.uncommon
        ))
    end

    local statusText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusText:SetPoint("TOPLEFT", 20, -205)

    local makeMLBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    makeMLBtn:SetSize(130, 26)
    makeMLBtn:SetPoint("LEFT", statusText, "RIGHT", 15, 0)
    makeMLBtn:SetText("Make Me ML")
    if S then
        S:HandleButton(makeMLBtn)
    end

    makeMLBtn:SetScript("OnClick", function()
        SetLootMethod("master", UnitName("player"))
    end)

    f:SetScript("OnUpdate", function()
        local isPlayerML = IsPlayerMasterLooter()

        if isPlayerML then
            statusText:SetText("|cff00ff00Status: Master Looter|r")
        else
            statusText:SetText("|cffff0000Status: Not Master Looter|r")
        end

        if IsPlayerLeaderOrAssist() and not isPlayerML then
            makeMLBtn:Show()
        else
            makeMLBtn:Hide()
        end
    end)

    local whisperCB = CreateFrame("CheckButton", nil, f, "ChatConfigCheckButtonTemplate")
    whisperCB:SetSize(32, 32)
    whisperCB:SetPoint("BOTTOMLEFT", 15, 12)
    if S then
        S:HandleCheckBox(whisperCB)
    end

    whisperCB:SetChecked(RTMasterLooterSave.whisperEnabled)
    whisperCB:SetScript("OnClick", function(self)
        RTMasterLooterSave.whisperEnabled = self:GetChecked()
    end)

    local whisperCBLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    whisperCBLbl:SetPoint("LEFT", whisperCB, "RIGHT", 2, 0)
    whisperCBLbl:SetText("Whisper Winner")

    local qLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    qLbl:SetPoint("TOPLEFT", 20, -235)
    qLbl:SetText("Quality Threshold:")

    local qBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    qBtn:SetSize(140, 26)
    qBtn:SetPoint("TOPLEFT", 160, -232)
    if S then
        S:HandleButton(qBtn)
    end

    local qualities = {
        [0] = "|cff9d9d9dPoor|r",
        [1] = "|cffffffffCommon|r",
        [2] = "|cff1eff00Uncommon|r",
        [3] = "|cff0070ddRare|r",
        [4] = "|cffa335eeEpic|r"
    }

    local function UpdateQText()
        qBtn:SetText(qualities[RTMasterLooterSave.minQuality] or "Common")
    end

    qBtn:SetScript("OnClick", function()
        local nextQuality = RTMasterLooterSave.minQuality + 1

        if nextQuality > 4 then
            nextQuality = 0
        end

        RTMasterLooterSave.minQuality = nextQuality
        UpdateQText()
    end)

    local function CreateInputWithTarget(label, yOffset, saveKey)
        local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", 20, yOffset)
        lbl:SetText(label)
        lbl:SetWidth(140)
        lbl:SetJustifyH("LEFT")

        local bg, eb = CreatePixelInput(f, 180, 24)
        bg:SetPoint("TOPLEFT", 160, yOffset + 4)

        eb:SetText(RTMasterLooterSave[saveKey] or UnitName("player"))
        eb:SetScript("OnTextChanged", function(self)
            RTMasterLooterSave[saveKey] = self:GetText()
        end)

        local btnTarget = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btnTarget:SetSize(60, 24)
        btnTarget:SetPoint("LEFT", bg, "RIGHT", 8, 0)
        btnTarget:SetText("Target")
        if S then
            S:HandleButton(btnTarget)
        end

        btnTarget:SetScript("OnClick", function()
            local targetName = UnitName("target")
            if not targetName then
                return
            end

            eb:SetText(targetName)
            RTMasterLooterSave[saveKey] = targetName
        end)

        local btnSelf = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btnSelf:SetSize(50, 24)
        btnSelf:SetPoint("LEFT", btnTarget, "RIGHT", 4, 0)
        btnSelf:SetText("Self")
        if S then
            S:HandleButton(btnSelf)
        end

        btnSelf:SetScript("OnClick", function()
            local playerName = UnitName("player")
            eb:SetText(playerName)
            RTMasterLooterSave[saveKey] = playerName
        end)
    end

    CreateInputWithTarget("Main Loot:", -275, "lootCollector")
    CreateInputWithTarget("Shard/Legendary:", -305, "shardsCollector")
    CreateInputWithTarget("BoE Collector:", -335, "boeCollector")

    local toggleBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    toggleBtn:SetSize(170, 28)
    toggleBtn:SetPoint("BOTTOMRIGHT", -18, 12)
    if S then
        S:HandleButton(toggleBtn)
    end

    toggleBtn:SetScript("OnClick", function()
        isMLActive = not isMLActive
        RTMasterLooterSave.enabled = isMLActive

        if isMLActive then
            toggleBtn:SetText("|cff00ff00Enabled|r")
        else
            toggleBtn:SetText("Start Master Looter")
        end
    end)

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    closeBtn:SetSize(100, 28)
    closeBtn:SetPoint("RIGHT", toggleBtn, "LEFT", -10, 0)
    closeBtn:SetText("Close")
    if S then
        S:HandleButton(closeBtn)
    end

    closeBtn:SetScript("OnClick", onClose)

    f:SetScript("OnShow", function()
        UpdateQText()
        RT_RefreshLogUI()
        RT_RefreshStatsUI()
        whisperCB:SetChecked(RTMasterLooterSave.whisperEnabled)

        if isMLActive then
            toggleBtn:SetText("|cff00ff00Enabled|r")
        else
            toggleBtn:SetText("Start Master Looter")
        end
    end)

    return f
end