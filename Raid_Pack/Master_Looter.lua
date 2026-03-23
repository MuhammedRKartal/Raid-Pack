local addonName, addonTable = ...

------------------------------------------------------------
-- STATE / REFS / CONSTANTS
------------------------------------------------------------

local STATE = {
    isEnabled = false,
}

local UI = {
    root = nil,

    logContainer = nil,

    logLeftBackground = nil,
    logLeftScroll = nil,
    logLeftContent = nil,
    logLeftText = nil,
    logLeftLabel = nil,
    logLeftCounter = nil,
    logLeftClearButton = nil,

    logRightBackground = nil,
    logRightScroll = nil,
    logRightContent = nil,
    logRightText = nil,
    logRightLabel = nil,
    logRightCounter = nil,
    logRightClearButton = nil,

    statsText = nil,
    statusText = nil,

    whisperCheckBox = nil,
    qualityButton = nil,
    toggleButton = nil,

    collectorInputs = {},
}

local REFRESH = {
    log = nil,
    stats = nil,
}

local TOOLTIP = CreateFrame("GameTooltip", "RTMasterLooterScanTooltip", nil, "GameTooltipTemplate")
TOOLTIP:SetOwner(UIParent, "ANCHOR_NONE")

local EVENT_FRAME = CreateFrame("Frame")
local LOADER_FRAME = CreateFrame("Frame")

local CONST = {
    MAX_LOG_ENTRIES = 1000,
    LOG_LEFT = 20,
    LOG_RIGHT = 20,
    LOG_TOP = -32,
    LOG_HEIGHT = 180,
    LOG_PADDING = 8,
    LOG_SCROLLBAR_SPACE = 24,
    LOG_SPLIT_GAP = 8,

    QUALITY_NAMES = {
        [0] = "Poor",
        [1] = "Common",
        [2] = "Uncommon",
        [3] = "Rare",
        [4] = "Epic",
        [5] = "Legendary",
    },

    QUALITY_COLORS = {
        [0] = "|cff9d9d9dPoor|r",
        [1] = "|cffffffffCommon|r",
        [2] = "|cff1eff00Uncommon|r",
        [3] = "|cff0070ddRare|r",
        [4] = "|cffa335eeEpic|r",
        [5] = "|cffff8000Legendary|r",
    },
}

------------------------------------------------------------
-- DEFAULT DATA
------------------------------------------------------------

local function CreateEmptyStats()
    return {
        epic = 0,
        rare = 0,
        uncommon = 0,
        common = 0,
        shards = 0,
        boe = 0,
    }
end

local function BuildDefaultSettings()
    return {
        lootCollector = UnitName("player"),
        shardsCollector = UnitName("player"),
        boeCollector = UnitName("player"),
        enabled = false,
        minQuality = 1,
        lootLog = {},
        whisperEnabled = true,
        stats = CreateEmptyStats(),
    }
end

------------------------------------------------------------
-- PUBLIC STATUS HELPERS
------------------------------------------------------------

function RT_IsMasterLooterEnabled()
    return STATE.isEnabled
end

------------------------------------------------------------
-- SAVED VARIABLE HELPERS
------------------------------------------------------------

local function EnsureSavedVariables()
    local defaultSettings = BuildDefaultSettings()

    if type(RTMasterLooterSave) ~= "table" then
        RTMasterLooterSave = CopyTable(defaultSettings)
    end

    if type(RTMasterLooterSave.lootLog) ~= "table" then
        RTMasterLooterSave.lootLog = {}
    end

    if type(RTMasterLooterSave.stats) ~= "table" then
        RTMasterLooterSave.stats = CreateEmptyStats()
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

    if RTMasterLooterSave.lootCollector == nil or RTMasterLooterSave.lootCollector == "" then
        RTMasterLooterSave.lootCollector = UnitName("player")
    end

    if RTMasterLooterSave.shardsCollector == nil or RTMasterLooterSave.shardsCollector == "" then
        RTMasterLooterSave.shardsCollector = UnitName("player")
    end

    if RTMasterLooterSave.boeCollector == nil or RTMasterLooterSave.boeCollector == "" then
        RTMasterLooterSave.boeCollector = UnitName("player")
    end

    if RTMasterLooterSave.enabled == nil then
        RTMasterLooterSave.enabled = false
    end

    if RTMasterLooterSave.whisperEnabled == nil then
        RTMasterLooterSave.whisperEnabled = true
    end
end

------------------------------------------------------------
-- GENERAL HELPERS
------------------------------------------------------------

local function GetPlayerName()
    return UnitName("player")
end

local function IsInRaidGroup()
    return IsInRaid() == true
end

local function IsPlayerMasterLooter()
    if not IsInRaidGroup() then
        return false
    end

    local lootMethod, masterLooterPartyID, masterLooterRaidID = GetLootMethod()
    return lootMethod == "master" and (masterLooterPartyID == 0 or masterLooterRaidID == 0)
end

local function IsPlayerLeaderOrAssistant()
    return IsPlayerLeaderOrAssist() == true
end

local function IsPlayerRaidLeader()
    return UnitIsGroupLeader("player") == true
end

local function BuildMasterLootCandidateMap()
    local candidateMap = {}

    for index = 1, 40 do
        local candidateName = GetMasterLootCandidate(index)
        if candidateName and candidateName ~= "" then
            candidateMap[candidateName] = index
        end
    end

    return candidateMap
end

------------------------------------------------------------
-- ITEM HELPERS
------------------------------------------------------------

local function IsItemBOE(itemLink)
    if not itemLink or itemLink == "" then
        return false
    end

    TOOLTIP:ClearLines()
    TOOLTIP:SetOwner(UIParent, "ANCHOR_NONE")
    TOOLTIP:SetHyperlink(itemLink)

    local isBOE = false

    for index = 2, 12 do
        local leftText = _G["RTMasterLooterScanTooltipTextLeft" .. index]
        if leftText then
            local textValue = leftText:GetText()

            if textValue then
                if textValue:find("Binds when equipped") then
                    isBOE = true
                    break
                end

                if textValue:find("Binds when picked up") then
                    isBOE = false
                    break
                end
            end
        end
    end

    TOOLTIP:Hide()
    return isBOE
end

local function GetCollectorNameForItem(itemLink, quality)
    if IsItemBOE(itemLink) then
        return RTMasterLooterSave.boeCollector
    end

    if quality == 5 then
        return RTMasterLooterSave.shardsCollector
    end

    return RTMasterLooterSave.lootCollector
end

local function GetItemQuality(itemLink)
    local _, _, quality = GetItemInfo(itemLink)
    return quality
end

------------------------------------------------------------
-- LOG / STATS HELPERS
------------------------------------------------------------

local function RebuildStatsFromLootLog()
    local stats = CreateEmptyStats()
    local lootLog = RTMasterLooterSave.lootLog or {}

    for index = 1, #lootLog do
        local entry = lootLog[index]
        local itemLink = entry.item
        local quality = GetItemQuality(itemLink)

        if quality then
            if IsItemBOE(itemLink) then
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

    RTMasterLooterSave.stats = stats
end

local function AddLootLogEntry(itemLink, playerName)
    local lootLog = RTMasterLooterSave.lootLog

    lootLog[#lootLog + 1] = {
        item = itemLink,
        to = playerName,
        time = date("%H:%M:%S"),
    }

    if #lootLog > CONST.MAX_LOG_ENTRIES then
        table.remove(lootLog, 1)
    end

    RebuildStatsFromLootLog()
end

local function ClearAllLootHistory()
    RTMasterLooterSave.lootLog = {}
    RTMasterLooterSave.stats = CreateEmptyStats()

    if REFRESH.log then
        REFRESH.log()
    end

    if REFRESH.stats then
        REFRESH.stats()
    end
end

local function ClearBOPHistory()
    local oldLog = RTMasterLooterSave.lootLog or {}
    local newLog = {}

    for index = 1, #oldLog do
        local entry = oldLog[index]
        if IsItemBOE(entry.item) then
            newLog[#newLog + 1] = entry
        end
    end

    RTMasterLooterSave.lootLog = newLog
    RebuildStatsFromLootLog()

    if REFRESH.log then
        REFRESH.log()
    end

    if REFRESH.stats then
        REFRESH.stats()
    end
end

local function ClearBOEHistory()
    local oldLog = RTMasterLooterSave.lootLog or {}
    local newLog = {}

    for index = 1, #oldLog do
        local entry = oldLog[index]
        if not IsItemBOE(entry.item) then
            newLog[#newLog + 1] = entry
        end
    end

    RTMasterLooterSave.lootLog = newLog
    RebuildStatsFromLootLog()

    if REFRESH.log then
        REFRESH.log()
    end

    if REFRESH.stats then
        REFRESH.stats()
    end
end

------------------------------------------------------------
-- WHISPER HELPERS
------------------------------------------------------------

local function IsCollectorPlayer(playerName)
    if not playerName or playerName == "" then
        return false
    end

    return playerName == RTMasterLooterSave.lootCollector
        or playerName == RTMasterLooterSave.shardsCollector
        or playerName == RTMasterLooterSave.boeCollector
end

local function TryWhisperCollector(playerName, itemLink)
    if RTMasterLooterSave.whisperEnabled ~= true then
        return
    end

    if not IsPlayerMasterLooter() then
        return
    end

    if playerName == GetPlayerName() then
        return
    end

    if not IsCollectorPlayer(playerName) then
        return
    end

    SendChatMessage(
        "RaidTools: I've sent you " .. itemLink .. ". Please check your bags.",
        "WHISPER",
        nil,
        playerName
    )
end

------------------------------------------------------------
-- LOOT MESSAGE HELPERS
------------------------------------------------------------

local function ParseLootMessage(messageText)
    local playerName, itemLink = messageText:match("([^%s]+) receives loot: (.+)%.")

    if playerName and itemLink then
        return playerName, itemLink
    end

    local receivedItemLink = messageText:match("You receive loot: (.+)%.")

    if receivedItemLink then
        return GetPlayerName(), receivedItemLink
    end

    return nil, nil
end

------------------------------------------------------------
-- CORE LOGIC
------------------------------------------------------------

local function DistributeLoot()
    if not STATE.isEnabled then
        return
    end

    if not IsInRaidGroup() then
        return
    end

    if not IsPlayerMasterLooter() then
        return
    end

    local candidateMap = BuildMasterLootCandidateMap()
    local lootItemCount = GetNumLootItems()

    for slotIndex = 1, lootItemCount do
        local _, _, _, quality = GetLootSlotInfo(slotIndex)
        local itemLink = GetLootSlotLink(slotIndex)

        if itemLink and quality then
            local collectorName = GetCollectorNameForItem(itemLink, quality)
            local candidateIndex = candidateMap[collectorName]

            if candidateIndex then
                GiveMasterLoot(slotIndex, candidateIndex)
            end
        end
    end
end

local function HandleLootMessage(messageText)
    if not IsInRaidGroup() then
        return
    end

    local playerName, itemLink = ParseLootMessage(messageText)

    if not playerName or not itemLink then
        return
    end

    if itemLink:find("money:") then
        return
    end

    local quality = GetItemQuality(itemLink)
    if not quality then
        return
    end

    AddLootLogEntry(itemLink, playerName)

    if REFRESH.log then
        REFRESH.log()
    end

    if REFRESH.stats then
        REFRESH.stats()
    end

    TryWhisperCollector(playerName, itemLink)
end

------------------------------------------------------------
-- TEST COMMAND
------------------------------------------------------------

SLASH_RTMLTEST1 = "/rtmltest"
SlashCmdList["RTMLTEST"] = function(messageText)
    EnsureSavedVariables()

    local inputText = messageText and strtrim(messageText) or ""

    if inputText == "" then
        print("Usage: /rtmltest [itemLink]")
        return
    end

    local _, itemLink, quality = GetItemInfo(inputText)
    local minQuality = tonumber(RTMasterLooterSave.minQuality) or 0

    if not quality then
        print("Item:", inputText)
        print("Quality: nil")
        print("Bind: unknown")
        print("Threshold:", CONST.QUALITY_NAMES[minQuality] or tostring(minQuality))
        print("Target: unknown")
        return
    end

    local resolvedItemLink = itemLink or inputText
    local isBOE = IsItemBOE(resolvedItemLink)
    local bindType = isBOE and "BOE" or "BOP"
    local targetName = GetCollectorNameForItem(resolvedItemLink, quality)

    print("Item:", resolvedItemLink)
    print("Quality:", CONST.QUALITY_NAMES[quality] or tostring(quality))
    print("Bind:", bindType)
    print("Target:", targetName)
end

------------------------------------------------------------
-- UI HELPERS
------------------------------------------------------------

local function ApplyPixelStyle(frame, width, height)
    frame:SetSize(width, height)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)
    frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
end

local function CreatePixelInput(parent, width, height)
    local background = CreateFrame("Frame", nil, parent)
    ApplyPixelStyle(background, width, height)

    local editBox = CreateFrame("EditBox", nil, background)
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

    return background, editBox
end

local function SetCollectorValue(editBox, saveKey, value)
    if not value or value == "" then
        return
    end

    editBox:SetText(value)
    RTMasterLooterSave[saveKey] = value
end


local function GetSkinModule()
    if TryGetElvUISkinModule then
        local engine, skin = TryGetElvUISkinModule()
        return engine, skin
    end

    return nil, nil
end

local function UpdateToggleButtonText()
    if not UI.toggleButton then
        return
    end

    if STATE.isEnabled then
        UI.toggleButton:SetText("|cff00ff00Enabled|r")
    else
        UI.toggleButton:SetText("Start Master Looter")
    end
end

local function UpdateWhisperCheckBox()
    if not UI.whisperCheckBox then
        return
    end

    UI.whisperCheckBox:SetChecked(RTMasterLooterSave.whisperEnabled == true)
end

local function UpdateCollectorInputValues()
    for saveKey, editBox in pairs(UI.collectorInputs) do
        if editBox then
            editBox:SetText(RTMasterLooterSave[saveKey] or GetPlayerName())
        end
    end
end

local function UpdateStatusArea()
    if not UI.statusText then
        return
    end

    local isInRaid = IsInRaidGroup()
    local isMasterLooter = IsPlayerMasterLooter()
    local isRaidLeaderOrAssistant = IsPlayerLeaderOrAssistant()

    if not isInRaid then
        UI.statusText:SetText("|cffffff00Status: Not In Raid|r")
        return
    end

    if isMasterLooter then
        UI.statusText:SetText("|cff00ff00Status: Master Looter Active|r")
        return
    end

    if isRaidLeaderOrAssistant then
        UI.statusText:SetText("|cffff0000WARNING: Not Master Looter|r")
        return
    end

    UI.statusText:SetText("|cffff0000WARNING: Not Master Looter|r\n|cffffaa00Not Raid Leader|r")
end

------------------------------------------------------------
-- UI REFRESH HELPERS
------------------------------------------------------------

REFRESH.log = function()
    if not UI.root or not UI.root:IsVisible() then
        return
    end

    if not UI.logLeftScroll or not UI.logRightScroll then
        return
    end

    UI.logLeftScroll:Clear()
    UI.logRightScroll:Clear()

    local lootLog = RTMasterLooterSave.lootLog or {}
    local hasBOP = false
    local hasBOE = false

    for index = #lootLog, 1, -1 do
        local entry = lootLog[index]
        local line = string.format("[%s] %s -> %s", entry.time or "00:00:00", entry.item or "?", entry.to or "?")

        if IsItemBOE(entry.item) then
            hasBOE = true
            UI.logRightScroll:AddMessage(line)
        else
            hasBOP = true
            UI.logLeftScroll:AddMessage(line)
        end
    end

    if not hasBOP then
        UI.logLeftScroll:AddMessage("No BOP logs.")
    end

    if not hasBOE then
        UI.logRightScroll:AddMessage("No BOE logs.")
    end

    if UI.logLeftCounter then
        UI.logLeftCounter:SetText("Shard: " .. tostring((RTMasterLooterSave.stats and RTMasterLooterSave.stats.shards) or 0))
    end

    if UI.logRightCounter then
        UI.logRightCounter:SetText("BOE: " .. tostring((RTMasterLooterSave.stats and RTMasterLooterSave.stats.boe) or 0))
    end

    UI.logLeftScroll:ScrollToTop()
    UI.logRightScroll:ScrollToTop()
end

REFRESH.stats = function()
    if not UI.statsText then
        return
    end

    UI.statsText:SetText("")
end

local function RefreshUI()
    UpdateToggleButtonText()
    UpdateWhisperCheckBox()
    UpdateCollectorInputValues()
    UpdateStatusArea()

    if REFRESH.log then
        REFRESH.log()
    end

    if REFRESH.stats then
        REFRESH.stats()
    end
end

------------------------------------------------------------
-- UI BUILDERS
------------------------------------------------------------

local function CreateLogSection(parentFrame, skinModule)
    UI.logContainer = CreateFrame("Frame", nil, parentFrame)
    UI.logContainer:SetPoint("TOPLEFT", CONST.LOG_LEFT, CONST.LOG_TOP)
    UI.logContainer:SetPoint("TOPRIGHT", -CONST.LOG_RIGHT, CONST.LOG_TOP)
    UI.logContainer:SetHeight(CONST.LOG_HEIGHT)

    UI.logLeftBackground = CreateFrame("Frame", nil, UI.logContainer)
    UI.logLeftBackground:SetPoint("TOPLEFT", 0, 0)
    UI.logLeftBackground:SetPoint("BOTTOMLEFT", 0, 0)
    UI.logLeftBackground:SetPoint("RIGHT", UI.logContainer, "CENTER", -(CONST.LOG_SPLIT_GAP / 2), 0)
    ApplyPixelStyle(UI.logLeftBackground, 1, 1)

    UI.logRightBackground = CreateFrame("Frame", nil, UI.logContainer)
    UI.logRightBackground:SetPoint("TOPRIGHT", 0, 0)
    UI.logRightBackground:SetPoint("BOTTOMRIGHT", 0, 0)
    UI.logRightBackground:SetPoint("LEFT", UI.logContainer, "CENTER", (CONST.LOG_SPLIT_GAP / 2), 0)
    ApplyPixelStyle(UI.logRightBackground, 1, 1)

    UI.logLeftLabel = parentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    UI.logLeftLabel:SetPoint("BOTTOMLEFT", UI.logLeftBackground, "TOPLEFT", 0, 4)
    UI.logLeftLabel:SetText("Recent BOP Loot")

    UI.logRightLabel = parentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    UI.logRightLabel:SetPoint("BOTTOMLEFT", UI.logRightBackground, "TOPLEFT", 0, 4)
    UI.logRightLabel:SetText("Recent BOE Loot")

    UI.logLeftCounter = parentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    UI.logLeftCounter:SetPoint("BOTTOMRIGHT", UI.logLeftBackground, "TOPRIGHT", -56, 4)
    UI.logLeftCounter:SetText("Shard: 0")

    UI.logRightCounter = parentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    UI.logRightCounter:SetPoint("BOTTOMRIGHT", UI.logRightBackground, "TOPRIGHT", -56, 4)
    UI.logRightCounter:SetText("BOE: 0")

    UI.logLeftClearButton = CreateFrame("Button", nil, parentFrame, "UIPanelButtonTemplate")
    UI.logLeftClearButton:SetSize(50, 18)
    UI.logLeftClearButton:SetText("Clear")
    UI.logLeftClearButton:SetPoint("BOTTOMRIGHT", UI.logLeftBackground, "TOPRIGHT", 0, 2)

    UI.logRightClearButton = CreateFrame("Button", nil, parentFrame, "UIPanelButtonTemplate")
    UI.logRightClearButton:SetSize(50, 18)
    UI.logRightClearButton:SetText("Clear")
    UI.logRightClearButton:SetPoint("BOTTOMRIGHT", UI.logRightBackground, "TOPRIGHT", 0, 2)

    if skinModule then
        skinModule:HandleButton(UI.logLeftClearButton)
        skinModule:HandleButton(UI.logRightClearButton)
    end

    UI.logLeftClearButton:SetScript("OnClick", function()
        ClearBOPHistory()
    end)

    UI.logRightClearButton:SetScript("OnClick", function()
        ClearBOEHistory()
    end)

    UI.logLeftScroll = CreateFrame("ScrollingMessageFrame", "RTMasterLooterBOPScrollFrame", UI.logLeftBackground)
    UI.logLeftScroll:SetPoint("TOPLEFT", CONST.LOG_PADDING, -CONST.LOG_PADDING)
    UI.logLeftScroll:SetPoint("BOTTOMRIGHT", -CONST.LOG_PADDING, CONST.LOG_PADDING)
    UI.logLeftScroll:SetFontObject(ChatFontSmall)
    UI.logLeftScroll:SetJustifyH("LEFT")
    UI.logLeftScroll:SetFading(false)
    UI.logLeftScroll:SetMaxLines(CONST.MAX_LOG_ENTRIES)
    UI.logLeftScroll:SetInsertMode("BOTTOM")
    UI.logLeftScroll:SetIndentedWordWrap(false)
    UI.logLeftScroll:EnableMouse(true)
    UI.logLeftScroll:EnableMouseWheel(true)
    UI.logLeftScroll:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            self:ScrollUp()
        else
            self:ScrollDown()
        end
    end)

    UI.logRightScroll = CreateFrame("ScrollingMessageFrame", "RTMasterLooterBOEScrollFrame", UI.logRightBackground)
    UI.logRightScroll:SetPoint("TOPLEFT", CONST.LOG_PADDING, -CONST.LOG_PADDING)
    UI.logRightScroll:SetPoint("BOTTOMRIGHT", -CONST.LOG_PADDING, CONST.LOG_PADDING)
    UI.logRightScroll:SetFontObject(ChatFontSmall)
    UI.logRightScroll:SetJustifyH("LEFT")
    UI.logRightScroll:SetFading(false)
    UI.logRightScroll:SetMaxLines(CONST.MAX_LOG_ENTRIES)
    UI.logRightScroll:SetInsertMode("BOTTOM")
    UI.logRightScroll:SetIndentedWordWrap(false)
    UI.logRightScroll:EnableMouse(true)
    UI.logRightScroll:EnableMouseWheel(true)
    UI.logRightScroll:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            self:ScrollUp()
        else
            self:ScrollDown()
        end
    end)

    UI.logContainer:SetScript("OnSizeChanged", function()
        if REFRESH.log then
            REFRESH.log()
        end
    end)
end

local function CreateStatsSection(parentFrame)
    UI.statsText = parentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    UI.statsText:SetPoint("TOPLEFT", 25, -215)
    UI.statsText:SetText("")
end

local function CreateStatusSection(parentFrame, skinModule)
    local statusAnchor = CreateFrame("Frame", nil, parentFrame)
    statusAnchor:SetSize(320, 60)
    statusAnchor:SetPoint("TOPLEFT", 20, -285)

    local makeMasterLooterButton = CreateFrame("Button", nil, parentFrame, "UIPanelButtonTemplate")
    makeMasterLooterButton:SetSize(130, 26)
    makeMasterLooterButton:SetPoint("BOTTOMLEFT", statusAnchor, "TOPLEFT", 0, 10)
    makeMasterLooterButton:SetText("Make Me ML")

    if skinModule then
        skinModule:HandleButton(makeMasterLooterButton)
    end

    UI.statusText = parentFrame:CreateFontString(nil, "OVERLAY")
    UI.statusText:SetPoint("TOPLEFT", statusAnchor, "TOPLEFT", 0, 0)
    UI.statusText:SetJustifyH("LEFT")
    UI.statusText:SetJustifyV("TOP")
    UI.statusText:SetWidth(320)
    UI.statusText:SetFont(STANDARD_TEXT_FONT, 15, "OUTLINE")

    makeMasterLooterButton:SetScript("OnClick", function()
        SetLootMethod("master", GetPlayerName())
    end)

    parentFrame:SetScript("OnUpdate", function()
        UpdateStatusArea()

        if IsPlayerLeaderOrAssistant() and not IsPlayerMasterLooter() then
            makeMasterLooterButton:Show()
        else
            makeMasterLooterButton:Hide()
        end
    end)
end

local function CreateWhisperSection(parentFrame, skinModule)
    UI.whisperCheckBox = CreateFrame("CheckButton", nil, parentFrame, "ChatConfigCheckButtonTemplate")
    UI.whisperCheckBox:SetSize(32, 32)
    UI.whisperCheckBox:SetPoint("BOTTOMLEFT", 15, 12)

    if skinModule then
        skinModule:HandleCheckBox(UI.whisperCheckBox)
    end

    UI.whisperCheckBox:SetScript("OnClick", function(self)
        RTMasterLooterSave.whisperEnabled = self:GetChecked() and true or false
    end)

    local label = parentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", UI.whisperCheckBox, "RIGHT", 2, 0)
    label:SetText("Whisper Winner")
end

local function CreateCollectorInputRow(parentFrame, labelText, yOffset, saveKey, skinModule)
    local label = parentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", 20, yOffset)
    label:SetText(labelText)
    label:SetWidth(140)
    label:SetJustifyH("LEFT")

    local background, editBox = CreatePixelInput(parentFrame, 180, 24)
    background:SetPoint("TOPLEFT", 160, yOffset + 4)

    editBox:SetText(RTMasterLooterSave[saveKey] or GetPlayerName())
    editBox:SetScript("OnTextChanged", function(self)
        RTMasterLooterSave[saveKey] = self:GetText()
    end)

    local targetButton = CreateFrame("Button", nil, parentFrame, "UIPanelButtonTemplate")
    targetButton:SetSize(60, 24)
    targetButton:SetPoint("LEFT", background, "RIGHT", 8, 0)
    targetButton:SetText("Target")

    if skinModule then
        skinModule:HandleButton(targetButton)
    end

    targetButton:SetScript("OnClick", function()
        local targetName = UnitName("target")
        if not targetName then
            return
        end

        editBox:SetText(targetName)
        RTMasterLooterSave[saveKey] = targetName
    end)

    local selfButton = CreateFrame("Button", nil, parentFrame, "UIPanelButtonTemplate")
    selfButton:SetSize(50, 24)
    selfButton:SetPoint("LEFT", targetButton, "RIGHT", 4, 0)
    selfButton:SetText("Self")

    if skinModule then
        skinModule:HandleButton(selfButton)
    end

    selfButton:SetScript("OnClick", function()
        local playerName = GetPlayerName()
        editBox:SetText(playerName)
        RTMasterLooterSave[saveKey] = playerName
    end)

    UI.collectorInputs[saveKey] = editBox
end

local function CreateCollectorRow(parentFrame, skinModule, options)
    local rowFrame = CreateFrame("Frame", nil, parentFrame)
    rowFrame:SetSize(options.rowWidth or 410, options.rowHeight or 24)
    rowFrame:SetPoint("TOPLEFT", options.left or 0, options.top or 0)

    local label = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", 0, 0)
    label:SetWidth(options.labelWidth or 100)
    label:SetJustifyH("LEFT")
    label:SetText(options.labelText or "")

    local background, editBox = CreatePixelInput(rowFrame, options.inputWidth or 190, 24)
    background:SetPoint("LEFT", label, "RIGHT", options.inputOffset or 10, 0)

    editBox:SetText(RTMasterLooterSave[options.saveKey] or GetPlayerName())
    editBox:SetScript("OnTextChanged", function(self)
        RTMasterLooterSave[options.saveKey] = self:GetText()
    end)

    local targetButton = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
    targetButton:SetSize(58, 24)
    targetButton:SetPoint("LEFT", background, "RIGHT", 6, 0)
    targetButton:SetText("Target")

    if skinModule then
        skinModule:HandleButton(targetButton)
    end

    targetButton:SetScript("OnClick", function()
        SetCollectorValue(editBox, options.saveKey, UnitName("target"))
    end)

    local selfButton = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
    selfButton:SetSize(48, 24)
    selfButton:SetPoint("LEFT", targetButton, "RIGHT", 4, 0)
    selfButton:SetText("Self")

    if skinModule then
        skinModule:HandleButton(selfButton)
    end

    selfButton:SetScript("OnClick", function()
        SetCollectorValue(editBox, options.saveKey, GetPlayerName())
    end)

    UI.collectorInputs[options.saveKey] = editBox

    return rowFrame, editBox
end

local function CreateCollectorSection(parentFrame, skinModule)
    local collectorSection = CreateFrame("Frame", nil, parentFrame)
    collectorSection:SetSize(430, 112)
    collectorSection:SetPoint("TOPLEFT", 20, -365)

    local rowHeight = 30
    local startTop = -10

    CreateCollectorRow(collectorSection, skinModule, {
        labelText = "Main Loot:",
        saveKey = "lootCollector",
        left = 8,
        top = startTop,
        labelWidth = 100,
        inputWidth = 190,
        rowWidth = 410,
        rowHeight = 24,
    })

    CreateCollectorRow(collectorSection, skinModule, {
        labelText = "Shard:",
        saveKey = "shardsCollector",
        left = 8,
        top = startTop - rowHeight,
        labelWidth = 100,
        inputWidth = 190,
        rowWidth = 410,
        rowHeight = 24,
    })

    CreateCollectorRow(collectorSection, skinModule, {
        labelText = "BoE Collector:",
        saveKey = "boeCollector",
        left = 8,
        top = startTop - (rowHeight * 2),
        labelWidth = 100,
        inputWidth = 190,
        rowWidth = 410,
        rowHeight = 24,
    })

    return collectorSection
end

local function CreateBottomButtons(parentFrame, onClose, skinModule)
    UI.toggleButton = CreateFrame("Button", nil, parentFrame, "UIPanelButtonTemplate")
    UI.toggleButton:SetSize(170, 28)
    UI.toggleButton:SetPoint("BOTTOMRIGHT", -18, 12)

    if skinModule then
        skinModule:HandleButton(UI.toggleButton)
    end

    UI.toggleButton:SetScript("OnClick", function()
        STATE.isEnabled = not STATE.isEnabled
        RTMasterLooterSave.enabled = STATE.isEnabled

        if RefreshStatusOverlay then
            RefreshStatusOverlay()
        end

        UpdateToggleButtonText()
    end)

    local closeButton = CreateFrame("Button", nil, parentFrame, "UIPanelButtonTemplate")
    closeButton:SetSize(100, 28)
    closeButton:SetPoint("RIGHT", UI.toggleButton, "LEFT", -10, 0)
    closeButton:SetText("Close")

    if skinModule then
        skinModule:HandleButton(closeButton)
    end

    closeButton:SetScript("OnClick", onClose)
end

------------------------------------------------------------
-- PUBLIC UI ENTRY
------------------------------------------------------------

function CreateMasterLooterTabContent(parent, onClose)
    EnsureSavedVariables()
    RebuildStatsFromLootLog()

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints()
    frame:Hide()

    UI.root = frame
    UI.collectorInputs = {}

    local _, skinModule = GetSkinModule()

    CreateLogSection(frame, skinModule)
    CreateStatsSection(frame)
    CreateStatusSection(frame, skinModule)
    CreateWhisperSection(frame, skinModule)
    CreateCollectorSection(frame, skinModule)
    CreateBottomButtons(frame, onClose, skinModule)

    frame:SetScript("OnShow", function()
        EnsureSavedVariables()
        RebuildStatsFromLootLog()
        STATE.isEnabled = RTMasterLooterSave.enabled == true
        RefreshUI()
    end)

    return frame
end

------------------------------------------------------------
-- EVENT HANDLERS
------------------------------------------------------------

local function HandleAddonLoaded(loadedAddonName)
    if loadedAddonName ~= addonName then
        return
    end

    EnsureSavedVariables()
    RebuildStatsFromLootLog()
    STATE.isEnabled = RTMasterLooterSave.enabled == true

    if RefreshStatusOverlay then
        RefreshStatusOverlay()
    end

    LOADER_FRAME:UnregisterEvent("ADDON_LOADED")
end

local function HandleMainEvent(event, ...)
    if event == "LOOT_OPENED" then
        DistributeLoot()
        return
    end

    if event == "CHAT_MSG_LOOT" then
        HandleLootMessage(...)
    end
end

------------------------------------------------------------
-- EVENT REGISTRATION
------------------------------------------------------------

LOADER_FRAME:RegisterEvent("ADDON_LOADED")
LOADER_FRAME:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        HandleAddonLoaded(...)
    end
end)

EVENT_FRAME:RegisterEvent("LOOT_OPENED")
EVENT_FRAME:RegisterEvent("CHAT_MSG_LOOT")
EVENT_FRAME:SetScript("OnEvent", function(self, event, ...)
    HandleMainEvent(event, ...)
end)