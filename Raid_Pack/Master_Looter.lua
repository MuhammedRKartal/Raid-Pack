local addonName, addonTable = ...

local TML = {}

------------------------------------------------------------
-- MODULE TABLES
------------------------------------------------------------

TML.DB = {}
TML.HELPER = {}
TML.ITEM = {}
TML.LOG = {}
TML.WHISPER = {}
TML.LOGIC = {}
TML.STYLE = {}
TML.BUILDER = {}
TML.EVENTS = {}
TML.API = {}

------------------------------------------------------------
-- TML.STATE / TML.UI REFS / CONSTANTS
------------------------------------------------------------

TML.STATE = {
    isEnabled = false,
    statusElapsed = 0,
}

TML.UI = {
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

TML.REFRESH = {
    log = nil,
    status = nil,
    controls = nil,
}

TML.TOOLTIP = CreateFrame("GameTooltip", "TMLMasterLooterScanTooltip", nil, "GameTooltipTemplate")
TML.TOOLTIP:SetOwner(UIParent, "ANCHOR_NONE")

TML.EVENT_FRAME = CreateFrame("Frame")
TML.LOADER_FRAME = CreateFrame("Frame")

TML.CONST = {
    MAX_LOG_ENTRIES = 1000,

    OUTER_LEFT = 20,
    OUTER_RIGHT = 20,
    TOP_OFFSET = -34,

    LOG_SECTION_HEIGHT = 210,
    LOG_GAP = 10,
    PANEL_INSET = 8,

    SECTION_GAP = 40,

    STATUS_HEIGHT = 110,
    STATUS_INNER_TOP_PADDING = 20,

    COLLECTOR_HEIGHT = 110,
    COLLECTOR_TITLE_GAP = 10,

    ROW_HEIGHT = 30,
    LABEL_WIDTH = 90,
    INPUT_WIDTH = 150,
    TARGET_WIDTH = 58,
    SELF_WIDTH = 48,

    FOOTER_HEIGHT = 40,

    QUALITY_NAMES = {
        [0] = "Poor",
        [1] = "Common",
        [2] = "Uncommon",
        [3] = "Rare",
        [4] = "Epic",
        [5] = "Legendary",
    },
}

------------------------------------------------------------
-- DEFAULT DATA
------------------------------------------------------------

function TML.DB.CreateEmptyStats()
    return {
        epic = 0,
        rare = 0,
        uncommon = 0,
        common = 0,
        shards = 0,
        boe = 0,
    }
end

function TML.DB.BuildDefaultSettings()
    return {
        lootCollector = UnitName("player"),
        shardsCollector = UnitName("player"),
        boeCollector = UnitName("player"),
        enabled = false,
        minQuality = 1,
        lootLog = {},
        whisperEnabled = true,
        stats = TML.DB.CreateEmptyStats(),
    }
end

------------------------------------------------------------
-- PUBLIC STATUS HELPERS
------------------------------------------------------------

function TML_IsMasterLooterEnabled()
    return TML.STATE.isEnabled
end

------------------------------------------------------------
-- SAVED VARIABLE HELPERS
------------------------------------------------------------

function TML.DB.EnsureSavedVariables()
    local defaultSettings = TML.DB.BuildDefaultSettings()

    if type(RTMasterLooterSave) ~= "table" then
        RTMasterLooterSave = CopyTable(defaultSettings)
    end

    if type(RTMasterLooterSave.lootLog) ~= "table" then
        RTMasterLooterSave.lootLog = {}
    end

    if type(RTMasterLooterSave.stats) ~= "table" then
        RTMasterLooterSave.stats = TML.DB.CreateEmptyStats()
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

------------------------------------------------------------
-- GENERAL HELPERS
------------------------------------------------------------

function TML.HELPER.GetPlayerName()
    return UnitName("player")
end

function TML.HELPER.IsInRaidGroup()
    return IsInRaid() == true
end

function TML.HELPER.IsPlayerRaidLeader()
    if not IsInRaid() then
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

function TML.HELPER.IsPlayerLeaderOrAssistant()
    if not IsInRaid() then
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

function TML.HELPER.IsPlayerMasterLooter()
    if not TML.HELPER.IsInRaidGroup() then
        return false
    end

    local lootMethod, masterLooterPartyID, masterLooterRaidID = GetLootMethod()

    if lootMethod ~= "master" then
        return false
    end

    return masterLooterPartyID == 0 or masterLooterRaidID == 0
end

function TML.HELPER.BuildMasterLootCandidateMap()
    local candidateMap = {}

    for index = 1, 40 do
        local candidateName = GetMasterLootCandidate(index)
        if candidateName and candidateName ~= "" then
            candidateMap[candidateName] = index
        end
    end

    return candidateMap
end

function TML.HELPER.GetSkinModule()
    if TryGetElvUISkinModule then
        local engine, skin = TryGetElvUISkinModule()
        return engine, skin
    end

    return nil, nil
end

------------------------------------------------------------
-- ITEM HELPERS
------------------------------------------------------------

function TML.ITEM.IsItemBOE(itemLink)
    if not itemLink or itemLink == "" then
        return false
    end

    TML.TOOLTIP:ClearLines()
    TML.TOOLTIP:SetOwner(UIParent, "ANCHOR_NONE")
    TML.TOOLTIP:SetHyperlink(itemLink)

    local isBOE = false

    for index = 2, 12 do
        local leftText = _G["TMLMasterLooterScanTooltipTextLeft" .. index]
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

    TML.TOOLTIP:Hide()

    return isBOE
end

function TML.ITEM.GetItemQuality(itemLink)
    local _, _, quality = GetItemInfo(itemLink)
    return quality
end

function TML.ITEM.IsIgnoredLootItem(itemLink)
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

function TML.ITEM.GetCollectorNameForItem(itemLink, quality)
    if TML.ITEM.IsItemBOE(itemLink) then
        return RTMasterLooterSave.boeCollector
    end

    if quality == 5 then
        return RTMasterLooterSave.shardsCollector
    end

    return RTMasterLooterSave.lootCollector
end

------------------------------------------------------------
-- LOG / STATS HELPERS
------------------------------------------------------------

function TML.LOG.RebuildStatsFromLootLog()
    local stats = TML.DB.CreateEmptyStats()
    local lootLog = RTMasterLooterSave.lootLog or {}

    for index = 1, #lootLog do
        local entry = lootLog[index]
        local itemLink = entry.item

        if not TML.ITEM.IsIgnoredLootItem(itemLink) then
            local quality = TML.ITEM.GetItemQuality(itemLink)

            if quality then
                if TML.ITEM.IsItemBOE(itemLink) then
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

function TML.LOG.AddLootLogEntry(itemLink, playerName)
    local lootLog = RTMasterLooterSave.lootLog

    lootLog[#lootLog + 1] = {
        item = itemLink,
        to = playerName,
        time = date("%H:%M"),
    }

    if #lootLog > TML.CONST.MAX_LOG_ENTRIES then
        table.remove(lootLog, 1)
    end

    TML.LOG.RebuildStatsFromLootLog()
end

function TML.LOG.ClearBOPHistory()
    local oldLog = RTMasterLooterSave.lootLog or {}
    local newLog = {}

    for index = 1, #oldLog do
        local entry = oldLog[index]

        if TML.ITEM.IsItemBOE(entry.item) then
            newLog[#newLog + 1] = entry
        end
    end

    RTMasterLooterSave.lootLog = newLog
    TML.LOG.RebuildStatsFromLootLog()

    if TML.REFRESH.log then
        TML.REFRESH.log()
    end
end

function TML.LOG.ClearBOEHistory()
    local oldLog = RTMasterLooterSave.lootLog or {}
    local newLog = {}

    for index = 1, #oldLog do
        local entry = oldLog[index]

        if not TML.ITEM.IsItemBOE(entry.item) then
            newLog[#newLog + 1] = entry
        end
    end

    RTMasterLooterSave.lootLog = newLog
    TML.LOG.RebuildStatsFromLootLog()

    if TML.REFRESH.log then
        TML.REFRESH.log()
    end
end

------------------------------------------------------------
-- WHISPER HELPERS
------------------------------------------------------------

function TML.WHISPER.IsCollectorPlayer(playerName)
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

function TML.WHISPER.TryWhisperCollector(playerName, itemLink)
    if RTMasterLooterSave.whisperEnabled ~= true then
        return
    end

    if not TML.HELPER.IsPlayerMasterLooter() then
        return
    end

    if playerName == TML.HELPER.GetPlayerName() then
        return
    end

    if not TML.WHISPER.IsCollectorPlayer(playerName) then
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

function TML.LOGIC.ParseLootMessage(messageText)
    local playerName, itemLink = messageText:match("([^%s]+) receives loot: (.+)%.")
    if playerName and itemLink then
        return playerName, itemLink
    end

    local receivedItemLink = messageText:match("You receive loot: (.+)%.")
    if receivedItemLink then
        return TML.HELPER.GetPlayerName(), receivedItemLink
    end

    return nil, nil
end

function TML.LOG.FormatLogLine(entry)
    local timeText = entry.time or "00:00:00"
    local itemText = entry.item or "?"
    local targetText = entry.to or "?"
    return string.format("[%s] %s -> %s", timeText, itemText, targetText)
end

------------------------------------------------------------
-- CORE LOGIC
------------------------------------------------------------

function TML.LOGIC.DistributeLoot()
    if not TML.STATE.isEnabled then
        return
    end

    if not TML.HELPER.IsInRaidGroup() then
        return
    end

    if not TML.HELPER.IsPlayerMasterLooter() then
        return
    end

    local candidateMap = TML.HELPER.BuildMasterLootCandidateMap()
    local lootItemCount = GetNumLootItems()
    local playerName = TML.HELPER.GetPlayerName()
    local selfCandidateIndex = candidateMap[playerName]

    for slotIndex = 1, lootItemCount do
        local _, _, _, quality = GetLootSlotInfo(slotIndex)
        local itemLink = GetLootSlotLink(slotIndex)

        if itemLink and quality then
            local collectorName = TML.ITEM.GetCollectorNameForItem(itemLink, quality)
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

function TML.LOGIC.HandleLootMessage(messageText)
    if not TML.HELPER.IsInRaidGroup() then
        return
    end

    local playerName, itemLink = TML.LOGIC.ParseLootMessage(messageText)

    if not playerName or not itemLink then
        return
    end

    if itemLink:find("money:") then
        return
    end

    local quality = TML.ITEM.GetItemQuality(itemLink)
    if not quality then
        return
    end

    if TML.ITEM.IsIgnoredLootItem(itemLink) then
        return
    end

    TML.LOG.AddLootLogEntry(itemLink, playerName)

    if TML.REFRESH.log then
        TML.REFRESH.log()
    end

    TML.WHISPER.TryWhisperCollector(playerName, itemLink)
end

------------------------------------------------------------
-- TEST COMMAND
------------------------------------------------------------

SLASH_RTMLTEST1 = "/rtmltest"
SlashCmdList["RTMLTEST"] = function(messageText)
    TML.DB.EnsureSavedVariables()

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
    local bindType = TML.ITEM.IsItemBOE(resolvedItemLink) and "BOE" or "BOP"
    local targetName = TML.ITEM.GetCollectorNameForItem(resolvedItemLink, quality)

    print("Item:", resolvedItemLink)
    print("Quality:", TML.CONST.QUALITY_NAMES[quality] or tostring(quality))
    print("Bind:", bindType)
    print("Target:", targetName)
end

------------------------------------------------------------
-- TML.UI STYLE HELPERS
------------------------------------------------------------

function TML.STYLE.ApplyBackdrop(frame, bgR, bgG, bgB, bgA, borderR, borderG, borderB, borderA)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })

    frame:SetBackdropColor(bgR, bgG, bgB, bgA)
    frame:SetBackdropBorderColor(borderR, borderG, borderB, borderA)
end

function TML.STYLE.ApplyPanelStyle(frame)
    TML.STYLE.ApplyBackdrop(frame, 0.0, 0.0, 0.0, 0.9, 0.3, 0.3, 0.3, 1)
end

function TML.STYLE.ApplyInputStyle(frame)
    TML.STYLE.ApplyBackdrop(frame, 0.0, 0.0, 0.0, 1.0, 0.4, 0.4, 0.4, 1)
end

function TML.BUILDER.CreateSectionPanel(parent, width, height)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, height)
    TML.STYLE.ApplyPanelStyle(frame)
    return frame
end

function TML.BUILDER.CreatePixelInput(parent, width, height)
    local background = CreateFrame("Frame", nil, parent)
    background:SetSize(width, height)
    TML.STYLE.ApplyInputStyle(background)

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

function TML.STYLE.SkinButton(button, skinModule)
    if skinModule and skinModule.HandleButton then
        skinModule:HandleButton(button)
        return
    end
end

function TML.STYLE.SkinCheckBox(checkBox, skinModule)
    if skinModule and skinModule.HandleCheckBox then
        skinModule:HandleCheckBox(checkBox)
        return
    end
end

function TML.BUILDER.SetCollectorValue(editBox, saveKey, value)
    if not value or value == "" then
        return
    end

    editBox:SetText(value)
    RTMasterLooterSave[saveKey] = value
end

------------------------------------------------------------
-- TML.UI STATUS HELPERS
------------------------------------------------------------

function TML.REFRESH.UpdateToggleButtonText()
    if not TML.UI.toggleButton then
        return
    end

    if TML.STATE.isEnabled then
        TML.UI.toggleButton:SetText("|cff00ff00Enabled|r")
    else
        TML.UI.toggleButton:SetText("Start Master Looter")
    end
end

function TML.REFRESH.UpdateWhisperCheckBox()
    if not TML.UI.whisperCheckBox then
        return
    end

    TML.UI.whisperCheckBox:SetChecked(RTMasterLooterSave.whisperEnabled == true)
end

function TML.REFRESH.UpdateCollectorInputValues()
    for saveKey, editBox in pairs(TML.UI.collectorInputs) do
        if editBox then
            editBox:SetText(RTMasterLooterSave[saveKey] or TML.HELPER.GetPlayerName())
        end
    end
end

TML.REFRESH.status = function()
    if not TML.UI.statusText or not TML.UI.raidLeaderText or not TML.UI.makeMLButton then
        return
    end

    local isInRaid = TML.HELPER.IsInRaidGroup()
    local isMasterLooter = TML.HELPER.IsPlayerMasterLooter()
    local isLeaderOrAssist = TML.HELPER.IsPlayerLeaderOrAssistant()
    local isRaidLeader = TML.HELPER.IsPlayerRaidLeader()

    if not isInRaid then
        TML.UI.statusText:SetText("|cffffff00Not In Raid|r")
        TML.UI.raidLeaderText:SetText("")
        TML.UI.makeMLButton:Hide()
        return
    end

    if isMasterLooter then
        TML.UI.statusText:SetText("|cff00ff00Master Looter|r")
    else
        TML.UI.statusText:SetText("|cffff2020WARNING: Not Master Looter|r")
    end

    if isRaidLeader then
        TML.UI.raidLeaderText:SetText("|cff00ff00Raid Leader|r")
    elseif isLeaderOrAssist then
        TML.UI.raidLeaderText:SetText("|cffffcc00Assist / Can't Set ML|r")
    else
        TML.UI.raidLeaderText:SetText("|cffffaa00Not Raid Leader|r")
    end

    if isLeaderOrAssist and not isMasterLooter then
        TML.UI.makeMLButton:Show()
    else
        TML.UI.makeMLButton:Hide()
    end
end

TML.REFRESH.controls = function()
    TML.REFRESH.UpdateToggleButtonText()
    TML.REFRESH.UpdateWhisperCheckBox()
    TML.REFRESH.UpdateCollectorInputValues()

    if TML.REFRESH.status then
        TML.REFRESH.status()
    end
end

------------------------------------------------------------
-- TML.UI LOG TML.REFRESH
------------------------------------------------------------

TML.REFRESH.log = function()
    if not TML.UI.root or not TML.UI.root:IsVisible() then
        return
    end

    if not TML.UI.bopScroll or not TML.UI.boeScroll then
        return
    end

    TML.UI.bopScroll:Clear()
    TML.UI.boeScroll:Clear()

    local lootLog = RTMasterLooterSave.lootLog or {}
    local hasBOP = false
    local hasBOE = false

    for index = 1, #lootLog do
        local entry = lootLog[index]

        if not TML.ITEM.IsIgnoredLootItem(entry.item) then
            local line = TML.LOG.FormatLogLine(entry)

            if TML.ITEM.IsItemBOE(entry.item) then
                hasBOE = true
                TML.UI.boeScroll:AddMessage(line)
            else
                hasBOP = true
                TML.UI.bopScroll:AddMessage(line)
            end
        end
    end

    if not hasBOP then
        TML.UI.bopScroll:AddMessage("No BOP logs.")
    end

    if not hasBOE then
        TML.UI.boeScroll:AddMessage("No BOE logs.")
    end

    if TML.UI.bopCounter then
        TML.UI.bopCounter:SetText("Shard: " .. tostring((RTMasterLooterSave.stats and RTMasterLooterSave.stats.shards) or 0))
    end

    if TML.UI.boeCounter then
        TML.UI.boeCounter:SetText("BOE: " .. tostring((RTMasterLooterSave.stats and RTMasterLooterSave.stats.boe) or 0))
        TML.UI.boeCounter:SetTextColor(0, 1, 0, 1)
    end

    TML.UI.bopScroll:ScrollToBottom()
    TML.UI.boeScroll:ScrollToBottom()
end

function TML.REFRESH.RefreshUI()
    if TML.REFRESH.controls then
        TML.REFRESH.controls()
    end

    if TML.REFRESH.log then
        TML.REFRESH.log()
    end
end

------------------------------------------------------------
-- TML.UI BUILDERS
------------------------------------------------------------

function TML.BUILDER.CreateLogScrollFrame(parent, globalName)
    local scroll = CreateFrame("ScrollingMessageFrame", globalName, parent)
    scroll:SetPoint("TOPLEFT", 8, -26)
    scroll:SetPoint("BOTTOMRIGHT", -8, 8)
    scroll:SetFontObject(ChatFontSmall)
    scroll:SetJustifyH("LEFT")
    scroll:SetFading(false)
    scroll:SetMaxLines(TML.CONST.MAX_LOG_ENTRIES)
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

function TML.BUILDER.CreateLogPanel(parent, skinModule, side)
    local panel = TML.BUILDER.CreateSectionPanel(parent, 1, TML.CONST.LOG_SECTION_HEIGHT)

    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetTextColor(1, 0.82, 0, 1)

    local counter = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    counter:SetTextColor(1, 0.82, 0, 1)

    local clearButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    clearButton:SetSize(46, 18)
    clearButton:SetText("Clear")
    TML.STYLE.SkinButton(clearButton, skinModule)

    local scrollName
    if side == "LEFT" then
        scrollName = "TMLMasterLooterBOPScrollFrame"
    else
        scrollName = "TMLMasterLooterBOEScrollFrame"
    end

    local scroll = TML.BUILDER.CreateLogScrollFrame(panel, scrollName)

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

function TML.BUILDER.CreateLogSection(parentFrame, skinModule)
    local section = CreateFrame("Frame", nil, parentFrame)
    section:SetPoint("TOPLEFT", TML.CONST.OUTER_LEFT, TML.CONST.TOP_OFFSET)
    section:SetPoint("TOPRIGHT", -TML.CONST.OUTER_RIGHT, TML.CONST.TOP_OFFSET)
    section:SetHeight(TML.CONST.LOG_SECTION_HEIGHT)

    local halfWidth = (section:GetWidth() - TML.CONST.LOG_GAP) / 2
    if not halfWidth or halfWidth <= 0 then
        halfWidth = 400
    end

    TML.UI.logSection = section

    local bopPanel, bopTitle, bopCounter, bopClearButton, bopScroll = TML.BUILDER.CreateLogPanel(section, skinModule, "LEFT")
    bopPanel:SetPoint("TOPLEFT", 0, 0)
    bopPanel:SetWidth(halfWidth)

    local boePanel, boeTitle, boeCounter, boeClearButton, boeScroll = TML.BUILDER.CreateLogPanel(section, skinModule, "RIGHT")
    boePanel:SetPoint("TOPRIGHT", 0, 0)
    boePanel:SetWidth(halfWidth)

    bopTitle:SetPoint("BOTTOMLEFT", bopPanel, "TOPLEFT", 0, 4)
    bopCounter:SetPoint("BOTTOMRIGHT", bopPanel, "TOPRIGHT", -54, 4)
    bopClearButton:SetPoint("BOTTOMRIGHT", bopPanel, "TOPRIGHT", 0, 2)

    boeTitle:SetPoint("BOTTOMLEFT", boePanel, "TOPLEFT", 0, 4)
    boeCounter:SetPoint("BOTTOMRIGHT", boePanel, "TOPRIGHT", -54, 4)
    boeClearButton:SetPoint("BOTTOMRIGHT", boePanel, "TOPRIGHT", 0, 2)

    TML.UI.bopPanel = bopPanel
    TML.UI.boePanel = boePanel
    TML.UI.bopTitle = bopTitle
    TML.UI.boeTitle = boeTitle
    TML.UI.bopCounter = bopCounter
    TML.UI.boeCounter = boeCounter
    TML.UI.bopClearButton = bopClearButton
    TML.UI.boeClearButton = boeClearButton
    TML.UI.bopScroll = bopScroll
    TML.UI.boeScroll = boeScroll

    TML.UI.bopClearButton:SetScript("OnClick", function()
        TML.LOG.ClearBOPHistory()
    end)

    TML.UI.boeClearButton:SetScript("OnClick", function()
        TML.LOG.ClearBOEHistory()
    end)

    section:SetScript("OnSizeChanged", function(self)
        local width = self:GetWidth()
        local panelWidth = math.floor((width - TML.CONST.LOG_GAP) / 2)

        if panelWidth < 120 then
            panelWidth = 120
        end

        TML.UI.bopPanel:SetWidth(panelWidth)
        TML.UI.boePanel:SetWidth(panelWidth)
    end)
end

function TML.BUILDER.CreateStatusSection(parentFrame, skinModule)
    local panel = TML.BUILDER.CreateSectionPanel(parentFrame, 1, TML.CONST.STATUS_HEIGHT)

    local statusText = panel:CreateFontString(nil, "OVERLAY")
    statusText:SetFont(STANDARD_TEXT_FONT, 16, "OUTLINE")
    statusText:SetJustifyH("LEFT")
    statusText:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -TML.CONST.STATUS_INNER_TOP_PADDING)
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
    TML.STYLE.SkinButton(makeMLButton, skinModule)

    makeMLButton:SetScript("OnClick", function()
        SetLootMethod("master", TML.HELPER.GetPlayerName())
        if TML.REFRESH.status then
            TML.REFRESH.status()
        end
    end)

    TML.UI.statusPanel = panel
    TML.UI.statusText = statusText
    TML.UI.raidLeaderText = raidLeaderText
    TML.UI.makeMLButton = makeMLButton
end

function TML.BUILDER.CreateCollectorRow(parentFrame, skinModule, labelText, saveKey, yOffset)
    local row = CreateFrame("Frame", nil, parentFrame)
    row:SetPoint("TOPLEFT", 8, yOffset)
    row:SetPoint("TOPRIGHT", -8, yOffset)
    row:SetHeight(24)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", 0, 0)
    label:SetWidth(TML.CONST.LABEL_WIDTH)
    label:SetJustifyH("LEFT")
    label:SetText(labelText)

    local selfButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    selfButton:SetSize(TML.CONST.SELF_WIDTH, 24)
    selfButton:SetPoint("RIGHT", 0, 0)
    selfButton:SetText("Self")
    TML.STYLE.SkinButton(selfButton, skinModule)

    local targetButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    targetButton:SetSize(TML.CONST.TARGET_WIDTH, 24)
    targetButton:SetPoint("RIGHT", selfButton, "LEFT", -4, 0)
    targetButton:SetText("Target")
    TML.STYLE.SkinButton(targetButton, skinModule)

    local inputBackground, editBox = TML.BUILDER.CreatePixelInput(row, TML.CONST.INPUT_WIDTH, 24)
    inputBackground:SetPoint("LEFT", label, "RIGHT", 8, 0)
    inputBackground:SetPoint("RIGHT", targetButton, "LEFT", -6, 0)

    editBox:SetText(RTMasterLooterSave[saveKey] or TML.HELPER.GetPlayerName())
    editBox:SetScript("OnTextChanged", function(self)
        RTMasterLooterSave[saveKey] = self:GetText()
    end)

    targetButton:SetScript("OnClick", function()
        TML.BUILDER.SetCollectorValue(editBox, saveKey, UnitName("target"))
    end)

    selfButton:SetScript("OnClick", function()
        TML.BUILDER.SetCollectorValue(editBox, saveKey, TML.HELPER.GetPlayerName())
    end)

    TML.UI.collectorInputs[saveKey] = editBox
end

function TML.BUILDER.CreateCollectorSection(parentFrame, skinModule)
    local panel = TML.BUILDER.CreateSectionPanel(parentFrame, 1, TML.CONST.COLLECTOR_HEIGHT)

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 0, TML.CONST.COLLECTOR_TITLE_GAP)
    title:SetTextColor(1, 0.82, 0, 1)
    title:SetText("Collectors")

    TML.BUILDER.CreateCollectorRow(panel, skinModule, "Main Loot:", "lootCollector", -12)
    TML.BUILDER.CreateCollectorRow(panel, skinModule, "Shard:", "shardsCollector", -42)
    TML.BUILDER.CreateCollectorRow(panel, skinModule, "BoE Collector:", "boeCollector", -72)

    TML.UI.collectorPanel = panel
end

function TML.BUILDER.CreateWhisperSection(parentFrame, skinModule)
    local checkBox = CreateFrame("CheckButton", nil, parentFrame, "ChatConfigCheckButtonTemplate")
    checkBox:SetSize(32, 32)
    checkBox:SetPoint("BOTTOMLEFT", 16, 10)
    TML.STYLE.SkinCheckBox(checkBox, skinModule)

    checkBox:SetScript("OnClick", function(self)
        RTMasterLooterSave.whisperEnabled = self:GetChecked() and true or false
    end)

    local label = parentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", checkBox, "RIGHT", 2, 0)
    label:SetText("Whisper Winner")

    TML.UI.whisperCheckBox = checkBox
    TML.UI.whisperLabel = label
end

function TML.BUILDER.CreateBottomButtons(parentFrame, onClose, skinModule)
    local toggleButton = CreateFrame("Button", nil, parentFrame, "UIPanelButtonTemplate")
    toggleButton:SetSize(170, 28)
    toggleButton:SetPoint("BOTTOMRIGHT", -18, 12)
    TML.STYLE.SkinButton(toggleButton, skinModule)

    toggleButton:SetScript("OnClick", function()
        TML.STATE.isEnabled = not TML.STATE.isEnabled
        RTMasterLooterSave.enabled = TML.STATE.isEnabled

        if RefreshStatusOverlay then
            RefreshStatusOverlay()
        end

        if TML.REFRESH.controls then
            TML.REFRESH.controls()
        end
    end)

    local closeButton = CreateFrame("Button", nil, parentFrame, "UIPanelButtonTemplate")
    closeButton:SetSize(100, 28)
    closeButton:SetPoint("RIGHT", toggleButton, "LEFT", -10, 0)
    closeButton:SetText("Close")
    TML.STYLE.SkinButton(closeButton, skinModule)

    closeButton:SetScript("OnClick", onClose)

    TML.UI.toggleButton = toggleButton
    TML.UI.closeButton = closeButton
end

------------------------------------------------------------
-- PUBLIC TML.UI ENTRY
------------------------------------------------------------

function TML.API.CreateMasterLooterTabContent(parent, onClose)
    TML.DB.EnsureSavedVariables()
    TML.LOG.RebuildStatsFromLootLog()

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints()
    frame:Hide()

    TML.UI.root = frame
    TML.UI.collectorInputs = {}

    local _, skinModule = TML.HELPER.GetSkinModule()

    TML.BUILDER.CreateLogSection(frame, skinModule)
    TML.BUILDER.CreateStatusSection(frame, skinModule)
    TML.BUILDER.CreateCollectorSection(frame, skinModule)
    TML.BUILDER.CreateWhisperSection(frame, skinModule)
    TML.BUILDER.CreateBottomButtons(frame, onClose, skinModule)

    function TML.BUILDER.UpdateBottomSections()
        if not TML.UI.logSection then
            return
        end

        local width = TML.UI.logSection:GetWidth()
        local half = math.floor((width - TML.CONST.LOG_GAP) / 2)

        if half < 150 then
            half = 150
        end

        if TML.UI.collectorPanel then
            TML.UI.collectorPanel:ClearAllPoints()
            TML.UI.collectorPanel:SetWidth(half)
            TML.UI.collectorPanel:SetPoint("TOPLEFT", TML.UI.logSection, "BOTTOMLEFT", 0, -TML.CONST.SECTION_GAP)
        end

        if TML.UI.statusPanel then
            TML.UI.statusPanel:ClearAllPoints()
            TML.UI.statusPanel:SetWidth(half)
            TML.UI.statusPanel:SetHeight(TML.CONST.STATUS_HEIGHT)
            TML.UI.statusPanel:SetPoint("TOPRIGHT", TML.UI.logSection, "BOTTOMRIGHT", 0, -TML.CONST.SECTION_GAP)
        end
    end

    if TML.UI.logSection then
        TML.UI.logSection:HookScript("OnSizeChanged", function()
            TML.BUILDER.UpdateBottomSections()
        end)
    end

    frame:SetScript("OnShow", function()
        TML.DB.EnsureSavedVariables()
        TML.LOG.RebuildStatsFromLootLog()
        TML.STATE.isEnabled = RTMasterLooterSave.enabled == true
        TML.BUILDER.UpdateBottomSections()
        TML.REFRESH.RefreshUI()
    end)

    frame:SetScript("OnUpdate", function(self, elapsed)
        TML.STATE.statusElapsed = TML.STATE.statusElapsed + elapsed

        if TML.STATE.statusElapsed < 0.2 then
            return
        end

        TML.STATE.statusElapsed = 0

        if TML.REFRESH.status then
            TML.REFRESH.status()
        end
    end)

    return frame
end



function CreateMasterLooterTabContent(parent, onClose)
    return TML.API.CreateMasterLooterTabContent(parent, onClose)
end

------------------------------------------------------------
-- EVENT HANDLERS
------------------------------------------------------------

function TML.EVENTS.HandleAddonLoaded(loadedAddonName)
    if loadedAddonName ~= addonName then
        return
    end

    TML.DB.EnsureSavedVariables()
    TML.LOG.RebuildStatsFromLootLog()
    TML.STATE.isEnabled = RTMasterLooterSave.enabled == true

    if RefreshStatusOverlay then
        RefreshStatusOverlay()
    end

    TML.LOADER_FRAME:UnregisterEvent("ADDON_LOADED")
end

function TML.EVENTS.HandleMainEvent(event, ...)
    if event == "LOOT_OPENED" then
        TML.LOGIC.DistributeLoot()
        return
    end

    if event == "CHAT_MSG_LOOT" then
        TML.LOGIC.HandleLootMessage(...)
        return
    end

    if event == "PARTY_LOOT_METHOD_CHANGED" then
        if TML.REFRESH.status then
            TML.REFRESH.status()
        end
        return
    end

    if event == "GROUP_ROSTER_UPDATE" then
        if TML.REFRESH.status then
            TML.REFRESH.status()
        end
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        if TML.REFRESH.status then
            TML.REFRESH.status()
        end
    end
end

------------------------------------------------------------
-- EVENT REGISTRATION
------------------------------------------------------------

TML.LOADER_FRAME:RegisterEvent("ADDON_LOADED")
TML.LOADER_FRAME:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        TML.EVENTS.HandleAddonLoaded(...)
    end
end)

TML.EVENT_FRAME:RegisterEvent("LOOT_OPENED")
TML.EVENT_FRAME:RegisterEvent("CHAT_MSG_LOOT")
TML.EVENT_FRAME:RegisterEvent("PARTY_LOOT_METHOD_CHANGED")
TML.EVENT_FRAME:RegisterEvent("GROUP_ROSTER_UPDATE")
TML.EVENT_FRAME:RegisterEvent("PLAYER_ENTERING_WORLD")
TML.EVENT_FRAME:SetScript("OnEvent", function(self, event, ...)
    TML.EVENTS.HandleMainEvent(event, ...)
end)