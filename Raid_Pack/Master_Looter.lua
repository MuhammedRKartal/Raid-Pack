local addonName, addonTable = ...

local STATE = {
    isEnabled = false,
    statusElapsed = 0,
}

local UI = {
    root = nil,
    logSection = nil,
    bopPanel = nil,
    boePanel = nil,
    bopTitle = nil,
    boeTitle = nil,
    bopCounter = nil,
    boeCounter = nil,
    bopClearButton = nil,
    boeClearButton = nil,
    bopScroll = nil,
    boeScroll = nil,
    statusPanel = nil,
    statusText = nil,
    raidLeaderText = nil,
    makeMLButton = nil,
    collectorPanel = nil,
    collectorInputs = {},
    whisperCheckBox = nil,
    whisperLabel = nil,
    toggleButton = nil,
    closeButton = nil,
}

local CONST = {
    MAX_LOG_ENTRIES = 1000,
    OUTER_LEFT = 20,
    OUTER_RIGHT = 20,
    TOP_OFFSET = -34,
    LOG_SECTION_HEIGHT = 210,
    LOG_GAP = 10,
    SECTION_GAP = 40,
    STATUS_HEIGHT = 110,
    STATUS_INNER_TOP_PADDING = 20,
    COLLECTOR_HEIGHT = 110,
    COLLECTOR_TITLE_GAP = 10,
    LABEL_WIDTH = 90,
    INPUT_WIDTH = 150,
    TARGET_WIDTH = 58,
    SELF_WIDTH = 48,
    QUALITY_NAMES = {
        [0] = "Poor",
        [1] = "Common",
        [2] = "Uncommon",
        [3] = "Rare",
        [4] = "Epic",
        [5] = "Legendary",
    },
}

local scanTooltip = CreateFrame("GameTooltip", "RTMasterLooterScanTooltip", nil, "GameTooltipTemplate")
scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")

local eventFrame = CreateFrame("Frame")
local loaderFrame = CreateFrame("Frame")

local function createEmptyStats()
    return {
        epic = 0,
        rare = 0,
        uncommon = 0,
        common = 0,
        shards = 0,
        boe = 0,
    }
end

local function buildDefaultSettings()
    return {
        lootCollector = UnitName("player"),
        shardsCollector = UnitName("player"),
        boeCollector = UnitName("player"),
        enabled = false,
        minQuality = 1,
        lootLog = {},
        whisperEnabled = true,
        stats = createEmptyStats(),
    }
end

local function ensureSavedVariables()
    local defaultSettings = buildDefaultSettings()

    if type(RTMasterLooterSave) ~= "table" then
        RTMasterLooterSave = CopyTable(defaultSettings)
    end

    if type(RTMasterLooterSave.lootLog) ~= "table" then
        RTMasterLooterSave.lootLog = {}
    end

    if type(RTMasterLooterSave.stats) ~= "table" then
        RTMasterLooterSave.stats = createEmptyStats()
    end

    if RTMasterLooterSave.stats.shards == nil then
        RTMasterLooterSave.stats.shards = 0
    end

    if RTMasterLooterSave.stats.boe == nil then
        RTMasterLooterSave.stats.boe = 0
    end

    if RTMasterLooterSave.stats.epic == nil then
        RTMasterLooterSave.stats.epic = 0
    end

    if RTMasterLooterSave.stats.rare == nil then
        RTMasterLooterSave.stats.rare = 0
    end

    if RTMasterLooterSave.stats.uncommon == nil then
        RTMasterLooterSave.stats.uncommon = 0
    end

    if RTMasterLooterSave.stats.common == nil then
        RTMasterLooterSave.stats.common = 0
    end

    if not RTMasterLooterSave.lootCollector or RTMasterLooterSave.lootCollector == "" then
        RTMasterLooterSave.lootCollector = UnitName("player")
    end

    if not RTMasterLooterSave.shardsCollector or RTMasterLooterSave.shardsCollector == "" then
        RTMasterLooterSave.shardsCollector = UnitName("player")
    end

    if not RTMasterLooterSave.boeCollector or RTMasterLooterSave.boeCollector == "" then
        RTMasterLooterSave.boeCollector = UnitName("player")
    end

    if RTMasterLooterSave.enabled == nil then
        RTMasterLooterSave.enabled = false
    end

    if RTMasterLooterSave.whisperEnabled == nil then
        RTMasterLooterSave.whisperEnabled = true
    end
end

local function getPlayerName()
    return UnitName("player")
end

local function isInRaidGroup()
    if IsInRaid then
        return IsInRaid()
    end

    return UnitInRaid("player") ~= nil
end

local function isPlayerRaidLeader()
    if not isInRaidGroup() then
        return false
    end

    local playerName = UnitName("player")

    for index = 1, GetNumRaidMembers() do
        local name, rank = GetRaidRosterInfo(index)

        if name == playerName then
            return rank == 2
        end
    end

    return false
end

local function isPlayerLeaderOrAssistant()
    if not isInRaidGroup() then
        return false
    end

    local playerName = UnitName("player")

    for index = 1, GetNumRaidMembers() do
        local name, rank = GetRaidRosterInfo(index)

        if name == playerName then
            return rank == 2 or rank == 1
        end
    end

    return false
end

local function isPlayerMasterLooter()
    if not isInRaidGroup() then
        return false
    end

    local lootMethod, masterLooterPartyID, masterLooterRaidID = GetLootMethod()

    if lootMethod ~= "master" then
        return false
    end

    return masterLooterPartyID == 0 or masterLooterRaidID == 0
end

local function buildMasterLootCandidateMap()
    local candidateMap = {}

    for index = 1, 40 do
        local candidateName = GetMasterLootCandidate(index)
        if candidateName and candidateName ~= "" then
            candidateMap[candidateName] = index
        end
    end

    return candidateMap
end

local function getSkinModule()
    if TryGetElvUISkinModule then
        local _, skinModule = TryGetElvUISkinModule()
        return skinModule
    end

    return nil
end

local function isItemBOE(itemLink)
    if not itemLink or itemLink == "" then
        return false
    end

    scanTooltip:ClearLines()
    scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTooltip:SetHyperlink(itemLink)

    local isBOEValue = false

    for index = 2, 12 do
        local leftText = _G["RTMasterLooterScanTooltipTextLeft" .. index]
        if leftText then
            local textValue = leftText:GetText()

            if textValue then
                if textValue:find("Binds when equipped") then
                    isBOEValue = true
                    break
                end

                if textValue:find("Binds when picked up") then
                    isBOEValue = false
                    break
                end
            end
        end
    end

    scanTooltip:Hide()

    return isBOEValue
end

local function getItemQuality(itemLink)
    local _, _, quality = GetItemInfo(itemLink)
    return quality
end

local function isIgnoredLootItem(itemLink)
    if not itemLink or itemLink == "" then
        return false
    end

    local itemName = GetItemInfo(itemLink)

    if not itemName or itemName == "" then
        local itemText = tostring(itemLink)

        if itemText:find("Emblem of Triumph") then
            return true
        end

        if itemText:find("Emblem of Heroism") then
            return true
        end

        if itemText:find("Emblem of Conquest") then
            return true
        end

        if itemText:find("Emblem of Frost") then
            return true
        end

        return false
    end

    if itemName == "Emblem of Triumph" then
        return true
    end

    if itemName == "Emblem of Heroism" then
        return true
    end

    if itemName == "Emblem of Conquest" then
        return true
    end

    if itemName == "Emblem of Frost" then
        return true
    end

    return false
end

local function getCollectorNameForItem(itemLink, quality)
    if isItemBOE(itemLink) then
        return RTMasterLooterSave.boeCollector
    end

    if quality == 5 then
        return RTMasterLooterSave.shardsCollector
    end

    return RTMasterLooterSave.lootCollector
end

local function rebuildStatsFromLootLog()
    local stats = createEmptyStats()
    local lootLog = RTMasterLooterSave.lootLog or {}

    for index = 1, #lootLog do
        local entry = lootLog[index]
        local itemLink = entry.item

        if not isIgnoredLootItem(itemLink) then
            local quality = getItemQuality(itemLink)

            if quality then
                if isItemBOE(itemLink) then
                    stats.boe = stats.boe + 1
                elseif quality == 5 then
                    stats.shards = stats.shards + 1
                elseif quality == 4 then
                    stats.epic = stats.epic + 1
                elseif quality == 3 then
                    stats.rare = stats.rare + 1
                elseif quality == 2 then
                    stats.uncommon = stats.uncommon + 1
                else
                    stats.common = stats.common + 1
                end
            end
        end
    end

    RTMasterLooterSave.stats = stats
end

local function formatLogLine(entry)
    local timeText = entry.time or "00:00:00"
    local itemText = entry.item or "?"
    local targetText = entry.to or "?"
    return string.format("[%s] %s -> %s", timeText, itemText, targetText)
end

local function refreshLog()
    if not UI.root or not UI.root:IsVisible() then
        return
    end

    if not UI.bopScroll or not UI.boeScroll then
        return
    end

    UI.bopScroll:Clear()
    UI.boeScroll:Clear()

    local lootLog = RTMasterLooterSave.lootLog or {}
    local hasBOP = false
    local hasBOE = false

    for index = 1, #lootLog do
        local entry = lootLog[index]

        if not isIgnoredLootItem(entry.item) then
            local line = formatLogLine(entry)

            if isItemBOE(entry.item) then
                hasBOE = true
                UI.boeScroll:AddMessage(line)
            else
                hasBOP = true
                UI.bopScroll:AddMessage(line)
            end
        end
    end

    if not hasBOP then
        UI.bopScroll:AddMessage("No BOP logs.")
    end

    if not hasBOE then
        UI.boeScroll:AddMessage("No BOE logs.")
    end

    if UI.bopCounter then
        UI.bopCounter:SetText("Shard: " .. tostring((RTMasterLooterSave.stats and RTMasterLooterSave.stats.shards) or 0))
    end

    if UI.boeCounter then
        UI.boeCounter:SetText("BOE: " .. tostring((RTMasterLooterSave.stats and RTMasterLooterSave.stats.boe) or 0))
        UI.boeCounter:SetTextColor(0, 1, 0, 1)
    end

    UI.bopScroll:ScrollToBottom()
    UI.boeScroll:ScrollToBottom()
end

local function addLootLogEntry(itemLink, playerName)
    local lootLog = RTMasterLooterSave.lootLog

    lootLog[#lootLog + 1] = {
        item = itemLink,
        to = playerName,
        time = date("%H:%M"),
    }

    if #lootLog > CONST.MAX_LOG_ENTRIES then
        table.remove(lootLog, 1)
    end

    rebuildStatsFromLootLog()
end

local function clearBOPHistory()
    local oldLog = RTMasterLooterSave.lootLog or {}
    local newLog = {}

    for index = 1, #oldLog do
        local entry = oldLog[index]

        if isItemBOE(entry.item) then
            newLog[#newLog + 1] = entry
        end
    end

    RTMasterLooterSave.lootLog = newLog
    rebuildStatsFromLootLog()
    refreshLog()
end

local function clearBOEHistory()
    local oldLog = RTMasterLooterSave.lootLog or {}
    local newLog = {}

    for index = 1, #oldLog do
        local entry = oldLog[index]

        if not isItemBOE(entry.item) then
            newLog[#newLog + 1] = entry
        end
    end

    RTMasterLooterSave.lootLog = newLog
    rebuildStatsFromLootLog()
    refreshLog()
end

local function isCollectorPlayer(playerName)
    if not playerName or playerName == "" then
        return false
    end

    if playerName == RTMasterLooterSave.lootCollector then
        return true
    end

    if playerName == RTMasterLooterSave.shardsCollector then
        return true
    end

    if playerName == RTMasterLooterSave.boeCollector then
        return true
    end

    return false
end

local function tryWhisperCollector(playerName, itemLink)
    if RTMasterLooterSave.whisperEnabled ~= true then
        return
    end

    if not isPlayerMasterLooter() then
        return
    end

    if playerName == getPlayerName() then
        return
    end

    if not isCollectorPlayer(playerName) then
        return
    end

    SendChatMessage(
        "RaidTools: I've sent you " .. itemLink .. ". Please check your bags.",
        "WHISPER",
        nil,
        playerName
    )
end

local function parseLootMessage(messageText)
    local playerName, itemLink = messageText:match("([^%s]+) receives loot: (.+)%.")
    if playerName and itemLink then
        return playerName, itemLink
    end

    local receivedItemLink = messageText:match("You receive loot: (.+)%.")
    if receivedItemLink then
        return getPlayerName(), receivedItemLink
    end

    return nil, nil
end

local function distributeLoot()
    if not STATE.isEnabled then
        return
    end

    if not isInRaidGroup() then
        return
    end

    if not isPlayerMasterLooter() then
        return
    end

    local candidateMap = buildMasterLootCandidateMap()
    local lootItemCount = GetNumLootItems()
    local playerName = getPlayerName()
    local selfCandidateIndex = candidateMap[playerName]

    for slotIndex = 1, lootItemCount do
        local _, _, _, quality = GetLootSlotInfo(slotIndex)
        local itemLink = GetLootSlotLink(slotIndex)

        if itemLink and quality then
            local collectorName = getCollectorNameForItem(itemLink, quality)
            local candidateIndex = candidateMap[collectorName]

            if not candidateIndex then
                candidateIndex = selfCandidateIndex
            end

            if candidateIndex then
                GiveMasterLoot(slotIndex, candidateIndex)
            end
        end
    end
end

local function handleLootMessage(messageText)
    if not isInRaidGroup() then
        return
    end

    local playerName, itemLink = parseLootMessage(messageText)

    if not playerName or not itemLink then
        return
    end

    if itemLink:find("money:") then
        return
    end

    local quality = getItemQuality(itemLink)
    if not quality then
        return
    end

    if isIgnoredLootItem(itemLink) then
        return
    end

    addLootLogEntry(itemLink, playerName)
    refreshLog()
    tryWhisperCollector(playerName, itemLink)
end

local function applyBackdrop(frame, bgR, bgG, bgB, bgA, borderR, borderG, borderB, borderA)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })

    frame:SetBackdropColor(bgR, bgG, bgB, bgA)
    frame:SetBackdropBorderColor(borderR, borderG, borderB, borderA)
end

local function applyPanelStyle(frame)
    applyBackdrop(frame, 0.0, 0.0, 0.0, 0.9, 0.3, 0.3, 0.3, 1)
end

local function applyInputStyle(frame)
    applyBackdrop(frame, 0.0, 0.0, 0.0, 1.0, 0.4, 0.4, 0.4, 1)
end

local function skinButton(button, skinModule)
    if skinModule and skinModule.HandleButton then
        skinModule:HandleButton(button)
    end
end

local function skinCheckBox(checkBox, skinModule)
    if skinModule and skinModule.HandleCheckBox then
        skinModule:HandleCheckBox(checkBox)
    end
end

local function updateToggleButtonText()
    if not UI.toggleButton then
        return
    end

    if STATE.isEnabled then
        UI.toggleButton:SetText("|cff00ff00Enabled|r")
    else
        UI.toggleButton:SetText("Start Master Looter")
    end
end

local function updateWhisperCheckBox()
    if not UI.whisperCheckBox then
        return
    end

    UI.whisperCheckBox:SetChecked(RTMasterLooterSave.whisperEnabled == true)
end

local function updateCollectorInputValues()
    for saveKey, editBox in pairs(UI.collectorInputs) do
        if editBox then
            editBox:SetText(RTMasterLooterSave[saveKey] or getPlayerName())
        end
    end
end

local function refreshStatus()
    if not UI.statusText or not UI.raidLeaderText or not UI.makeMLButton then
        return
    end

    local isInRaidValue = isInRaidGroup()
    local isMasterLooterValue = isPlayerMasterLooter()
    local isLeaderOrAssistValue = isPlayerLeaderOrAssistant()
    local isRaidLeaderValue = isPlayerRaidLeader()

    if not isInRaidValue then
        UI.statusText:SetText("|cffffff00Not In Raid|r")
        UI.raidLeaderText:SetText("")
        UI.makeMLButton:Hide()
        return
    end

    if isMasterLooterValue then
        UI.statusText:SetText("|cff00ff00Master Looter|r")
    else
        UI.statusText:SetText("|cffff2020WARNING: Not Master Looter|r")
    end

    if isRaidLeaderValue then
        UI.raidLeaderText:SetText("|cff00ff00Raid Leader|r")
    elseif isLeaderOrAssistValue then
        UI.raidLeaderText:SetText("|cffffcc00Assist / Can't Set ML|r")
    else
        UI.raidLeaderText:SetText("|cffffaa00Not Raid Leader|r")
    end

    if isLeaderOrAssistValue and not isMasterLooterValue then
        UI.makeMLButton:Show()
    else
        UI.makeMLButton:Hide()
    end
end

local function refreshControls()
    updateToggleButtonText()
    updateWhisperCheckBox()
    updateCollectorInputValues()
    refreshStatus()
end

local function refreshUI()
    refreshControls()
    refreshLog()
end

local function createSectionPanel(parent, width, height)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, height)
    applyPanelStyle(frame)
    return frame
end

local function createPixelInput(parent, width, height)
    local background = CreateFrame("Frame", nil, parent)
    background:SetSize(width, height)
    applyInputStyle(background)

    local editBox = CreateFrame("EditBox", nil, background)
    editBox:SetPoint("TOPLEFT", 4, 0)
    editBox:SetPoint("BOTTOMRIGHT", -4, 0)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ChatFontNormal)

    if editBox.Left then
        editBox.Left:Hide()
    end

    if editBox.Middle then
        editBox.Middle:Hide()
    end

    if editBox.Right then
        editBox.Right:Hide()
    end

    return background, editBox
end

local function setCollectorValue(editBox, saveKey, value)
    if not value or value == "" then
        return
    end

    editBox:SetText(value)
    RTMasterLooterSave[saveKey] = value
end

local function createLogScrollFrame(parent, globalName)
    local scroll = CreateFrame("ScrollingMessageFrame", globalName, parent)
    scroll:SetPoint("TOPLEFT", 8, -26)
    scroll:SetPoint("BOTTOMRIGHT", -8, 8)
    scroll:SetFontObject(ChatFontSmall)
    scroll:SetJustifyH("LEFT")
    scroll:SetFading(false)
    scroll:SetMaxLines(CONST.MAX_LOG_ENTRIES)
    scroll:SetInsertMode("BOTTOM")
    scroll:SetIndentedWordWrap(false)
    scroll:EnableMouse(true)
    scroll:EnableMouseWheel(true)

    scroll:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            self:ScrollUp()
        else
            self:ScrollDown()
        end
    end)

    return scroll
end

local function createLogPanel(parent, skinModule, side)
    local panel = createSectionPanel(parent, 1, CONST.LOG_SECTION_HEIGHT)

    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetTextColor(1, 0.82, 0, 1)

    local counter = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    counter:SetTextColor(1, 0.82, 0, 1)

    local clearButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    clearButton:SetSize(46, 18)
    clearButton:SetText("Clear")
    skinButton(clearButton, skinModule)

    local scrollName = "RTMasterLooterBOPScrollFrame"
    if side ~= "LEFT" then
        scrollName = "RTMasterLooterBOEScrollFrame"
    end

    local scroll = createLogScrollFrame(panel, scrollName)

    if side == "LEFT" then
        title:SetText("Recent BOP Loot")
        counter:SetText("Shard: 0")
        counter:SetTextColor(1, 0.5, 0, 1)
    else
        title:SetText("Recent BOE Loot")
        counter:SetText("BOE: 0")
        counter:SetTextColor(0, 1, 0, 1)
    end

    return panel, title, counter, clearButton, scroll
end

local function createLogSection(parentFrame, skinModule)
    local section = CreateFrame("Frame", nil, parentFrame)
    section:SetPoint("TOPLEFT", CONST.OUTER_LEFT, CONST.TOP_OFFSET)
    section:SetPoint("TOPRIGHT", -CONST.OUTER_RIGHT, CONST.TOP_OFFSET)
    section:SetHeight(CONST.LOG_SECTION_HEIGHT)

    local halfWidth = (section:GetWidth() - CONST.LOG_GAP) / 2
    if not halfWidth or halfWidth <= 0 then
        halfWidth = 400
    end

    UI.logSection = section

    local bopPanel, bopTitle, bopCounter, bopClearButton, bopScroll = createLogPanel(section, skinModule, "LEFT")
    bopPanel:SetPoint("TOPLEFT", 0, 0)
    bopPanel:SetWidth(halfWidth)

    local boePanel, boeTitle, boeCounter, boeClearButton, boeScroll = createLogPanel(section, skinModule, "RIGHT")
    boePanel:SetPoint("TOPRIGHT", 0, 0)
    boePanel:SetWidth(halfWidth)

    bopTitle:SetPoint("BOTTOMLEFT", bopPanel, "TOPLEFT", 0, 4)
    bopCounter:SetPoint("BOTTOMRIGHT", bopPanel, "TOPRIGHT", -54, 4)
    bopClearButton:SetPoint("BOTTOMRIGHT", bopPanel, "TOPRIGHT", 0, 2)

    boeTitle:SetPoint("BOTTOMLEFT", boePanel, "TOPLEFT", 0, 4)
    boeCounter:SetPoint("BOTTOMRIGHT", boePanel, "TOPRIGHT", -54, 4)
    boeClearButton:SetPoint("BOTTOMRIGHT", boePanel, "TOPRIGHT", 0, 2)

    UI.bopPanel = bopPanel
    UI.boePanel = boePanel
    UI.bopTitle = bopTitle
    UI.boeTitle = boeTitle
    UI.bopCounter = bopCounter
    UI.boeCounter = boeCounter
    UI.bopClearButton = bopClearButton
    UI.boeClearButton = boeClearButton
    UI.bopScroll = bopScroll
    UI.boeScroll = boeScroll

    UI.bopClearButton:SetScript("OnClick", function()
        clearBOPHistory()
    end)

    UI.boeClearButton:SetScript("OnClick", function()
        clearBOEHistory()
    end)

    section:SetScript("OnSizeChanged", function(self)
        local width = self:GetWidth()
        local panelWidth = math.floor((width - CONST.LOG_GAP) / 2)

        if panelWidth < 120 then
            panelWidth = 120
        end

        UI.bopPanel:SetWidth(panelWidth)
        UI.boePanel:SetWidth(panelWidth)
    end)
end

local function createStatusSection(parentFrame, skinModule)
    local panel = createSectionPanel(parentFrame, 1, CONST.STATUS_HEIGHT)

    local statusText = panel:CreateFontString(nil, "OVERLAY")
    statusText:SetFont(STANDARD_TEXT_FONT, 16, "OUTLINE")
    statusText:SetJustifyH("LEFT")
    statusText:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -CONST.STATUS_INNER_TOP_PADDING)
    statusText:SetPoint("RIGHT", panel, "RIGHT", -12, 0)

    local raidLeaderText = panel:CreateFontString(nil, "OVERLAY")
    raidLeaderText:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    raidLeaderText:SetJustifyH("LEFT")
    raidLeaderText:SetPoint("TOPLEFT", statusText, "BOTTOMLEFT", 0, -8)
    raidLeaderText:SetPoint("RIGHT", panel, "RIGHT", -12, 0)

    local makeMLButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    makeMLButton:SetSize(140, 24)
    makeMLButton:SetText("Make Me ML")
    makeMLButton:SetPoint("TOPLEFT", raidLeaderText, "BOTTOMLEFT", 0, -10)
    skinButton(makeMLButton, skinModule)

    makeMLButton:SetScript("OnClick", function()
        SetLootMethod("master", getPlayerName())
        refreshStatus()
    end)

    UI.statusPanel = panel
    UI.statusText = statusText
    UI.raidLeaderText = raidLeaderText
    UI.makeMLButton = makeMLButton
end

local function createCollectorRow(parentFrame, skinModule, labelText, saveKey, yOffset)
    local row = CreateFrame("Frame", nil, parentFrame)
    row:SetPoint("TOPLEFT", 8, yOffset)
    row:SetPoint("TOPRIGHT", -8, yOffset)
    row:SetHeight(24)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", 0, 0)
    label:SetWidth(CONST.LABEL_WIDTH)
    label:SetJustifyH("LEFT")
    label:SetText(labelText)

    local selfButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    selfButton:SetSize(CONST.SELF_WIDTH, 24)
    selfButton:SetPoint("RIGHT", 0, 0)
    selfButton:SetText("Self")
    skinButton(selfButton, skinModule)

    local targetButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    targetButton:SetSize(CONST.TARGET_WIDTH, 24)
    targetButton:SetPoint("RIGHT", selfButton, "LEFT", -4, 0)
    targetButton:SetText("Target")
    skinButton(targetButton, skinModule)

    local inputBackground, editBox = createPixelInput(row, CONST.INPUT_WIDTH, 24)
    inputBackground:SetPoint("LEFT", label, "RIGHT", 8, 0)
    inputBackground:SetPoint("RIGHT", targetButton, "LEFT", -6, 0)

    editBox:SetText(RTMasterLooterSave[saveKey] or getPlayerName())
    editBox:SetScript("OnTextChanged", function(self)
        RTMasterLooterSave[saveKey] = self:GetText()
    end)

    targetButton:SetScript("OnClick", function()
        setCollectorValue(editBox, saveKey, UnitName("target"))
    end)

    selfButton:SetScript("OnClick", function()
        setCollectorValue(editBox, saveKey, getPlayerName())
    end)

    UI.collectorInputs[saveKey] = editBox
end

local function createCollectorSection(parentFrame, skinModule)
    local panel = createSectionPanel(parentFrame, 1, CONST.COLLECTOR_HEIGHT)

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 0, CONST.COLLECTOR_TITLE_GAP)
    title:SetTextColor(1, 0.82, 0, 1)
    title:SetText("Collectors")

    createCollectorRow(panel, skinModule, "Main Loot:", "lootCollector", -12)
    createCollectorRow(panel, skinModule, "Shard:", "shardsCollector", -42)
    createCollectorRow(panel, skinModule, "BoE Collector:", "boeCollector", -72)

    UI.collectorPanel = panel
end

local function createWhisperSection(parentFrame, skinModule)
    local checkBox = CreateFrame("CheckButton", nil, parentFrame, "ChatConfigCheckButtonTemplate")
    checkBox:SetSize(24, 24)
    checkBox:SetPoint("BOTTOMLEFT", 16, 10)
    skinCheckBox(checkBox, skinModule)

    checkBox:SetScript("OnClick", function(self)
        RTMasterLooterSave.whisperEnabled = self:GetChecked() and true or false
    end)

    local label = parentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", checkBox, "RIGHT", 2, 0)
    label:SetText("Whisper Winner")

    UI.whisperCheckBox = checkBox
    UI.whisperLabel = label
end

local function createBottomButtons(parentFrame, onClose, skinModule)
    local toggleButton = CreateFrame("Button", nil, parentFrame, "UIPanelButtonTemplate")
    toggleButton:SetSize(170, 28)
    toggleButton:SetPoint("BOTTOMRIGHT", -18, 12)
    skinButton(toggleButton, skinModule)

    toggleButton:SetScript("OnClick", function()
        STATE.isEnabled = not STATE.isEnabled
        RTMasterLooterSave.enabled = STATE.isEnabled

        if RefreshStatusOverlay then
            RefreshStatusOverlay()
        end

        refreshControls()
    end)

    local closeButton = CreateFrame("Button", nil, parentFrame, "UIPanelButtonTemplate")
    closeButton:SetSize(100, 28)
    closeButton:SetPoint("RIGHT", toggleButton, "LEFT", -10, 0)
    closeButton:SetText("Close")
    skinButton(closeButton, skinModule)

    closeButton:SetScript("OnClick", onClose)

    UI.toggleButton = toggleButton
    UI.closeButton = closeButton
end

local function updateBottomSections()
    if not UI.logSection then
        return
    end

    local width = UI.logSection:GetWidth()
    local half = math.floor((width - CONST.LOG_GAP) / 2)

    if half < 150 then
        half = 150
    end

    if UI.collectorPanel then
        UI.collectorPanel:ClearAllPoints()
        UI.collectorPanel:SetWidth(half)
        UI.collectorPanel:SetPoint("TOPLEFT", UI.logSection, "BOTTOMLEFT", 0, -CONST.SECTION_GAP)
    end

    if UI.statusPanel then
        UI.statusPanel:ClearAllPoints()
        UI.statusPanel:SetWidth(half)
        UI.statusPanel:SetHeight(CONST.STATUS_HEIGHT)
        UI.statusPanel:SetPoint("TOPRIGHT", UI.logSection, "BOTTOMRIGHT", 0, -CONST.SECTION_GAP)
    end
end

local function createMasterLooterTabContent(parent, onClose)
    ensureSavedVariables()
    rebuildStatsFromLootLog()

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints()
    frame:Hide()

    UI.root = frame
    UI.collectorInputs = {}

    local skinModule = getSkinModule()

    createLogSection(frame, skinModule)
    createStatusSection(frame, skinModule)
    createCollectorSection(frame, skinModule)
    createWhisperSection(frame, skinModule)
    createBottomButtons(frame, onClose, skinModule)

    if UI.logSection then
        UI.logSection:HookScript("OnSizeChanged", function()
            updateBottomSections()
        end)
    end

    frame:SetScript("OnShow", function()
        ensureSavedVariables()
        rebuildStatsFromLootLog()
        STATE.isEnabled = RTMasterLooterSave.enabled == true
        updateBottomSections()
        refreshUI()
    end)

    frame:SetScript("OnUpdate", function(_, elapsed)
        STATE.statusElapsed = STATE.statusElapsed + elapsed

        if STATE.statusElapsed < 0.2 then
            return
        end

        STATE.statusElapsed = 0
        refreshStatus()
    end)

    return frame
end

local function handleAddonLoaded(loadedAddonName)
    if loadedAddonName ~= addonName then
        return
    end

    ensureSavedVariables()
    rebuildStatsFromLootLog()
    STATE.isEnabled = RTMasterLooterSave.enabled == true

    if RefreshStatusOverlay then
        RefreshStatusOverlay()
    end

    loaderFrame:UnregisterEvent("ADDON_LOADED")
end

local function handleMainEvent(event, ...)
    if event == "LOOT_OPENED" then
        distributeLoot()
        return
    end

    if event == "CHAT_MSG_LOOT" then
        handleLootMessage(...)
        return
    end

    if event == "PARTY_LOOT_METHOD_CHANGED" then
        refreshStatus()
        return
    end

    if event == "GROUP_ROSTER_UPDATE" then
        refreshStatus()
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        refreshStatus()
    end
end

local function isMasterLooterEnabled()
    return STATE.isEnabled
end

SLASH_RTMLTEST1 = "/rtmltest"
SlashCmdList["RTMLTEST"] = function(messageText)
    ensureSavedVariables()

    local inputText = messageText and strtrim(messageText) or ""

    if inputText == "" then
        print("Usage: /rtmltest [itemLink]")
        return
    end

    local _, itemLink, quality = GetItemInfo(inputText)

    if not quality then
        print("Item:", inputText)
        print("Quality: nil")
        print("Bind: unknown")
        print("Target: unknown")
        return
    end

    local resolvedItemLink = itemLink or inputText
    local bindType = isItemBOE(resolvedItemLink) and "BOE" or "BOP"
    local targetName = getCollectorNameForItem(resolvedItemLink, quality)

    print("Item:", resolvedItemLink)
    print("Quality:", CONST.QUALITY_NAMES[quality] or tostring(quality))
    print("Bind:", bindType)
    print("Target:", targetName)
end

loaderFrame:RegisterEvent("ADDON_LOADED")
loaderFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        handleAddonLoaded(...)
    end
end)

eventFrame:RegisterEvent("LOOT_OPENED")
eventFrame:RegisterEvent("CHAT_MSG_LOOT")
eventFrame:RegisterEvent("PARTY_LOOT_METHOD_CHANGED")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    handleMainEvent(event, ...)
end)

addonTable = addonTable or {}
addonTable.CreateMasterLooterTabContent = createMasterLooterTabContent
addonTable.IsMasterLooterEnabled = isMasterLooterEnabled
