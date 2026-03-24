-- Roll_Manager.lua

local addonName, addonTable = ...

local _G = _G
local unpack = unpack
local pcall = pcall

local rollFrame = CreateFrame("Frame")
local loader = CreateFrame("Frame")

local RefreshRollUI = nil
local RefreshActionButtons = nil
local HasActiveUnannouncedWinners = nil
local ResetCurrentRollSession = nil
local pendingItemLinkToSet = nil

local originalChatEdit_InsertLink = nil
local isInsertLinkHookInstalled = false

local RAID_MARK_ORDER = {
    1, -- Star
    2, -- Circle
    3, -- Diamond
    4, -- Triangle
    5, -- Moon
    6, -- Square
    7, -- Cross
    8  -- Skull
}

local UI_CONSTANTS = {
    LEFT_MARGIN = 20,
    RIGHT_MARGIN = -20,
    TOP_MARGIN = -20,
    BUTTON_HEIGHT = 28,
    SMALL_BUTTON_WIDTH = 32,
    STANDARD_BUTTON_WIDTH = 120,
    LARGE_BUTTON_WIDTH = 140,
    CLOSE_BUTTON_WIDTH = 100,
    CLEAR_WINNERS_BUTTON_WIDTH = 170,
    CLEAR_ROLLS_BUTTON_WIDTH = 150,
    PANEL_PADDING = 8,
    INPUT_HEIGHT = 28,
    ITEM_ICON_SIZE = 36,
    ITEM_INPUT_WIDTH = 300,
    COUNTDOWN_INPUT_WIDTH = 70,
    WINNER_LABEL_WIDTH = 300,
    ROLL_HEADER_WIDTH = 210,
    MS_CHANGES_HEIGHT = 105,
    HISTORY_NAV_BUTTON_SIZE = 28,
    TOP_SECTION_Y = -48,
    ACTIONS_Y = -96,
    COUNTDOWN_Y = -138,
    WINNERS_Y = -170,
    LIST_LABEL_Y = -204,
    CONTENT_TOP_Y = -230,
    FOOTER_Y = 12,

    OUTER_LEFT = 20,
    OUTER_RIGHT = 20,
    SPLIT_GAP = 4,
    PANEL_BOTTOM_Y = 58,
    HEADER_RIGHT_OFFSET = 20
}

local defaultSettings = {
    countdownDuration = 20,
    useRaidWarning = true,
    winnerHistory = {},
    rollHistory = {},
    msChangesText = ""
}

local rollState = {
    isRecordingRolls = false,
    canAcceptRolls = false,
    currentRollType = nil,
    currentItemLink = nil,
    currentItemName = nil,
    currentItemTexture = nil,
    isCountdownActive = false,
    countdownDuration = 20,
    countdownStartTime = 0,
    countdownLastAnnounced = nil,
    currentWinnerCount = 1,
    currentSessionAnnounced = false,
    rollHistoryViewIndex = 0,
    isEditingMSChanges = false,
    rollEntries = {},
    currentWinnerNames = {},
    historyStruckIndices = {}
}

local uiRefs = {
    rollContentFrame = nil,

    itemButton = nil,
    itemIcon = nil,
    itemEditBox = nil,
    itemBg = nil,

    winnerCountButton = nil,
    winnerCountEditBox = nil,
    winnerCountBg = nil,

    msButton = nil,
    osButton = nil,
    finishEarlyButton = nil,
    announceWinnersButton = nil,

    countdownBg = nil,
    countdownEditBox = nil,
    countdownText = nil,

    winnerLabel = nil,
    logLabel = nil,
    rollHeaderLinkButton = nil,
    rollHeaderLinkText = nil,

    msChangesBg = nil,
    msChangesEditBox = nil,
    msChangesToggleButton = nil,
    msChangesAnnounceButton = nil,
    msChangesScrollFrame = nil,
    msChangesScrollChild = nil,

    logBg = nil,
    historyBg = nil,

    leftHistoryButton = nil,
    rightHistoryButton = nil,

    rollScrollFrame = nil,
    rollScrollChild = nil,
    rollText = nil,

    rollRowButtons = {},
    rollRowTexts = {},
    rollRowStrikeLines = {},

    historyScrollFrame = nil,
    historyScrollChild = nil,
    historyText = nil,

    closeButton = nil,
    clearWinnersSavedButton = nil,
    clearRollsSavedButton = nil,

    historyRowButtons = {},
    historyRowTexts = {},
    historyRowStrikeLines = {}
}

local function TryGetElvUISkinModule()
    if not _G.ElvUI then
        return nil, nil
    end

    local okElvUI, e = pcall(unpack, _G.ElvUI)
    if not okElvUI or not e or not e.GetModule then
        return nil, nil
    end

    local okSkin, skinModule = pcall(e.GetModule, e, "Skins")
    if not okSkin then
        return e, nil
    end

    return e, skinModule
end

local function HandleButtonSkin(skinModule, button)
    if skinModule and button and skinModule.HandleButton then
        skinModule:HandleButton(button)
    end
end

local function CopyDefaultSettings()
    return CopyTable(defaultSettings)
end

function RT_IsRollManagerEnabled()
    return true
end

local function EnsureSavedVariables()
    if type(RTRollManagerSave) ~= "table" then
        RTRollManagerSave = CopyDefaultSettings()
    end

    if RTRollManagerSave.countdownDuration == nil then
        RTRollManagerSave.countdownDuration = defaultSettings.countdownDuration
    end

    if RTRollManagerSave.useRaidWarning == nil then
        RTRollManagerSave.useRaidWarning = defaultSettings.useRaidWarning
    end

    if type(RTRollManagerSave.winnerHistory) ~= "table" then
        RTRollManagerSave.winnerHistory = {}
    end

    if type(RTRollManagerSave.rollHistory) ~= "table" then
        RTRollManagerSave.rollHistory = {}
    end

    if type(RTRollManagerSave.msChangesText) ~= "string" then
        RTRollManagerSave.msChangesText = ""
    end
end

local function GetSafeStringHeight(fontString, fallbackValue)
    local resolvedFallbackValue = fallbackValue or 20

    if not fontString or not fontString.GetStringHeight then
        return resolvedFallbackValue
    end

    local heightValue = fontString:GetStringHeight()
    if not heightValue or heightValue <= 0 then
        return resolvedFallbackValue
    end

    return heightValue
end

local function GetSafeEditBoxTextHeight(editBox, fallbackValue)
    local resolvedFallbackValue = fallbackValue or 20

    if not editBox or not editBox.GetTextHeight then
        return resolvedFallbackValue
    end

    local heightValue = editBox:GetTextHeight()
    if not heightValue or heightValue <= 0 then
        return resolvedFallbackValue
    end

    return heightValue
end

local function GetAnnouncementChannel()
    EnsureSavedVariables()

    if RTRollManagerSave.useRaidWarning and GetRaidChatType then
        return GetRaidChatType()
    end

    if IsInRaid() then
        return "RAID"
    end

    if IsInGroup() then
        return "PARTY"
    end

    return "SAY"
end

local function HasAnyCurrentWinner()
    return #rollState.currentWinnerNames > 0
end

local function Announce(message)
    if not message or message == "" then
        return
    end

    SendChatMessage(message, GetAnnouncementChannel())
end

local function GetSelectedItemDisplayText()
    if rollState.currentItemLink and rollState.currentItemLink ~= "" then
        return rollState.currentItemLink
    end

    return "selected item"
end

local function ApplyPanelStyle(frame)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)
    frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
end

local function ApplyPixelStyle(frame, width, height)
    frame:SetSize(width, height)
    ApplyPanelStyle(frame)
end

local function CreatePixelInput(parent, width, height)
    local bg = CreateFrame("Frame", nil, parent)
    ApplyPixelStyle(bg, width, height)

    local editBox = CreateFrame("EditBox", nil, bg)
    editBox:SetPoint("TOPLEFT", 4, 0)
    editBox:SetPoint("BOTTOMRIGHT", -4, 0)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetAutoFocus(false)
    editBox:SetTextInsets(0, 0, 0, 0)
    editBox:SetBackdrop(nil)

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

local function SetButtonEnabled(button, isEnabled)
    if not button then
        return
    end

    if isEnabled then
        button:Enable()
    else
        button:Disable()
    end
end

local function GetUnitByName(nameValue)
    if not nameValue or nameValue == "" then
        return nil
    end

    if UnitName("player") == nameValue then
        return "player"
    end

    if IsInRaid() then
        local raidSize = GetNumRaidMembers()
        local index = 1

        while index <= raidSize do
            local unit = "raid" .. index
            if UnitName(unit) == nameValue then
                return unit
            end
            index = index + 1
        end
    elseif IsInGroup() then
        local partySize = GetNumPartyMembers()
        local index = 1

        while index <= partySize do
            local unit = "party" .. index
            if UnitName(unit) == nameValue then
                return unit
            end
            index = index + 1
        end
    end

    return nil
end

local function ClearAllWinnerMarks()
    if IsInRaid() then
        local raidSize = GetNumRaidMembers()
        local index = 1

        while index <= raidSize do
            SetRaidTarget("raid" .. index, 0)
            index = index + 1
        end
    elseif IsInGroup() then
        local partySize = GetNumPartyMembers()
        local index = 1

        while index <= partySize do
            SetRaidTarget("party" .. index, 0)
            index = index + 1
        end

        SetRaidTarget("player", 0)
    else
        SetRaidTarget("player", 0)
    end
end

local function ApplyWinnerMarks()
    ClearAllWinnerMarks()

    local index = 1
    while index <= #rollState.currentWinnerNames and index <= #RAID_MARK_ORDER do
        local winnerName = rollState.currentWinnerNames[index]
        local unit = GetUnitByName(winnerName)

        if unit then
            SetRaidTarget(unit, RAID_MARK_ORDER[index])
        end

        index = index + 1
    end
end

local function GetWinnerRollValueByName(nameValue)
    local index = 1

    while index <= #rollState.rollEntries do
        if rollState.rollEntries[index].name == nameValue then
            return rollState.rollEntries[index].roll
        end
        index = index + 1
    end

    return 0
end

local function GetEnabledRollEntries()
    local enabledEntries = {}
    local index = 1

    while index <= #rollState.rollEntries do
        local entry = rollState.rollEntries[index]
        if not entry.disabled then
            enabledEntries[#enabledEntries + 1] = entry
        end
        index = index + 1
    end

    return enabledEntries
end

local function RebuildCurrentWinners()
    wipe(rollState.currentWinnerNames)

    local enabledEntries = GetEnabledRollEntries()
    local index = 1

    while index <= #enabledEntries and index <= rollState.currentWinnerCount do
        rollState.currentWinnerNames[#rollState.currentWinnerNames + 1] = enabledEntries[index].name
        index = index + 1
    end
end

local function SortRollEntries()
    table.sort(rollState.rollEntries, function(leftEntry, rightEntry)
        if leftEntry.roll == rightEntry.roll then
            return leftEntry.name < rightEntry.name
        end

        return leftEntry.roll > rightEntry.roll
    end)

    RebuildCurrentWinners()
end

local function DidPlayerAlreadyRoll(playerName)
    local index = 1

    while index <= #rollState.rollEntries do
        if rollState.rollEntries[index].name == playerName then
            return true
        end
        index = index + 1
    end

    return false
end

local function GetCountdownRemaining()
    if not rollState.isCountdownActive then
        return 0
    end

    local remainingValue = math.ceil(rollState.countdownDuration - (GetTime() - rollState.countdownStartTime))
    if remainingValue < 0 then
        remainingValue = 0
    end

    return remainingValue
end

local function NormalizeRollHistoryViewIndex()
    EnsureSavedVariables()

    local historyCount = #RTRollManagerSave.rollHistory

    if historyCount <= 0 then
        rollState.rollHistoryViewIndex = 0
        return
    end

    if rollState.rollHistoryViewIndex == nil or rollState.rollHistoryViewIndex < 0 then
        rollState.rollHistoryViewIndex = 0
        return
    end

    if rollState.rollHistoryViewIndex > historyCount then
        rollState.rollHistoryViewIndex = historyCount
    end
end

local function IsViewingCurrentRollPage()
    NormalizeRollHistoryViewIndex()
    return rollState.rollHistoryViewIndex == 0
end

local function ResetCurrentRollResults()
    wipe(rollState.rollEntries)
    wipe(rollState.currentWinnerNames)
    rollState.currentSessionAnnounced = false
end

function HasActiveUnannouncedWinners()
    if not IsViewingCurrentRollPage() then
        return false
    end

    if rollState.isCountdownActive then
        return false
    end

    if rollState.currentSessionAnnounced then
        return false
    end

    if not rollState.currentItemLink or rollState.currentItemLink == "" then
        return false
    end

    if #rollState.rollEntries == 0 then
        return false
    end

    if #rollState.currentWinnerNames == 0 then
        return false
    end

    return true
end

local function ClearSelectedItem()
    if HasActiveUnannouncedWinners() then
        StaticPopup_Show("RTROLLMANAGER_ACTIVE_WINNER_ITEM_WARNING")
        return
    end

    rollState.currentItemLink = nil
    rollState.currentItemName = nil
    rollState.currentItemTexture = nil
    rollState.currentWinnerCount = 1

    if uiRefs.itemEditBox then
        uiRefs.itemEditBox:SetText("")
        uiRefs.itemEditBox:ClearFocus()
    end

    if uiRefs.itemIcon then
        uiRefs.itemIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end

    if uiRefs.winnerCountButton then
        uiRefs.winnerCountButton:SetText("1")
    end
end

local function SetSelectedItemInternal(itemLink)
    if not itemLink or itemLink == "" then
        return
    end

    local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemLink)

    rollState.currentItemLink = itemLink
    rollState.currentItemName = itemName or itemLink
    rollState.currentItemTexture = itemTexture
    rollState.currentWinnerCount = 1
    rollState.currentSessionAnnounced = false

    if uiRefs.itemEditBox then
        uiRefs.itemEditBox:SetText(itemLink)
        uiRefs.itemEditBox:ClearFocus()
    end

    if uiRefs.itemIcon then
        uiRefs.itemIcon:SetTexture(itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
    end

    if uiRefs.winnerCountButton then
        uiRefs.winnerCountButton:SetText(tostring(rollState.currentWinnerCount))
    end

    if uiRefs.winnerCountEditBox then
        uiRefs.winnerCountEditBox:SetText(tostring(rollState.currentWinnerCount))
    end

    RefreshRollUI()
end

ResetCurrentRollSession = function(clearSelectedItemToo)
    wipe(rollState.rollEntries)
    wipe(rollState.currentWinnerNames)

    rollState.isRecordingRolls = false
    rollState.canAcceptRolls = false
    rollState.isCountdownActive = false
    rollState.countdownStartTime = 0
    rollState.countdownLastAnnounced = nil
    rollState.currentRollType = nil
    rollState.currentWinnerCount = 1
    rollState.currentSessionAnnounced = false
    rollState.rollHistoryViewIndex = 0

    if clearSelectedItemToo then
        rollState.currentItemLink = nil
        rollState.currentItemName = nil
        rollState.currentItemTexture = nil

        if uiRefs.itemEditBox then
            uiRefs.itemEditBox:SetText("")
            uiRefs.itemEditBox:ClearFocus()
        end

        if uiRefs.itemIcon then
            uiRefs.itemIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end
    end

    if uiRefs.winnerCountButton then
        uiRefs.winnerCountButton:SetText("1")
    end

    if uiRefs.winnerCountEditBox then
        uiRefs.winnerCountEditBox:SetText("1")
        uiRefs.winnerCountEditBox:ClearFocus()
    end
end

local function SetSelectedItem(itemLink)
    if not itemLink or itemLink == "" then
        return
    end

    if HasActiveUnannouncedWinners() and itemLink ~= rollState.currentItemLink then
        pendingItemLinkToSet = itemLink
        StaticPopup_Show("RTROLLMANAGER_ACTIVE_WINNER_ITEM_WARNING")
        return
    end

    SetSelectedItemInternal(itemLink)
end

local function BuildRollSnapshot()
    local snapshot = {
        timestamp = time(),
        rollType = rollState.currentRollType or "-",
        itemLink = rollState.currentItemLink or "-",
        winnerCount = rollState.currentWinnerCount or 1,
        winners = {},
        rolls = {}
    }

    local rollIndex = 1
    while rollIndex <= #rollState.rollEntries do
        snapshot.rolls[#snapshot.rolls + 1] = {
            name = rollState.rollEntries[rollIndex].name,
            roll = rollState.rollEntries[rollIndex].roll,
            disabled = rollState.rollEntries[rollIndex].disabled and true or false
        }
        rollIndex = rollIndex + 1
    end

    local winnerIndex = 1
    while winnerIndex <= #rollState.currentWinnerNames do
        local winnerName = rollState.currentWinnerNames[winnerIndex]
        snapshot.winners[#snapshot.winners + 1] = {
            name = winnerName,
            roll = GetWinnerRollValueByName(winnerName)
        }
        winnerIndex = winnerIndex + 1
    end

    return snapshot
end

local function SaveRollSnapshot()
    EnsureSavedVariables()

    if not rollState.currentItemLink or #rollState.rollEntries == 0 then
        return
    end

    local rollHistory = RTRollManagerSave.rollHistory
    local snapshot = BuildRollSnapshot()

    table.insert(rollHistory, 1, snapshot)

    while #rollHistory > 50 do
        table.remove(rollHistory, #rollHistory)
    end

    rollState.rollHistoryViewIndex = 0
end

local function AddWinnersToHistory()
    EnsureSavedVariables()

    local winnerHistory = RTRollManagerSave.winnerHistory
    local winnerIndex = 1

    while winnerIndex <= #rollState.currentWinnerNames do
        local winnerName = rollState.currentWinnerNames[winnerIndex]

        table.insert(winnerHistory, 1, {
            rollType = rollState.currentRollType or "-",
            itemLink = rollState.currentItemLink or "-",
            winnerName = winnerName or "-",
            rollValue = GetWinnerRollValueByName(winnerName)
        })

        winnerIndex = winnerIndex + 1
    end

    while #winnerHistory > 25 do
        table.remove(winnerHistory, #winnerHistory)
    end
end

local function ClearWinnerHistory()
    EnsureSavedVariables()
    wipe(RTRollManagerSave.winnerHistory)
end

local function ClearRollHistory()
    EnsureSavedVariables()
    wipe(RTRollManagerSave.rollHistory)
    rollState.rollHistoryViewIndex = 0
end

local function BuildRollStartedMessage()
    local rollText = (rollState.currentRollType or "Roll") .. " roll started for " .. GetSelectedItemDisplayText() .. "."

    if rollState.currentWinnerCount and rollState.currentWinnerCount > 1 then
        rollText = rollText .. " Top " .. rollState.currentWinnerCount .. " highest rolls will win."
    end

    rollText = rollText .. " You have " .. rollState.countdownDuration .. " seconds to roll."

    return rollText
end

local function CompleteRollSession()
    if not rollState.isRecordingRolls and not rollState.isCountdownActive then
        return
    end

    rollState.isCountdownActive = false
    rollState.isRecordingRolls = false
    rollState.canAcceptRolls = false
    rollState.countdownStartTime = 0
    rollState.countdownLastAnnounced = nil

    Announce("Rolling ended for " .. GetSelectedItemDisplayText() .. ".")

    if not HasAnyCurrentWinner() then
        Announce("No winner for " .. GetSelectedItemDisplayText() .. ".")
    end

    RefreshRollUI()
end

local function FinishEarly()
    if not rollState.isCountdownActive then
        return
    end

    CompleteRollSession()
end

local function AnnounceWinners()
    if #rollState.currentWinnerNames == 0 then
        return
    end

    if not rollState.currentItemLink then
        return
    end

    local parts = {}
    local index = 1

    while index <= #rollState.currentWinnerNames do
        local winnerName = rollState.currentWinnerNames[index]
        parts[#parts + 1] = winnerName .. " (" .. GetWinnerRollValueByName(winnerName) .. ")"
        index = index + 1
    end

    Announce("Winners for " .. rollState.currentItemLink .. ": " .. table.concat(parts, ", "))
    rollState.currentSessionAnnounced = true

    AddWinnersToHistory()
    SaveRollSnapshot()
    ApplyWinnerMarks()

    ResetCurrentRollSession(true)
end

local function SetCurrentWinnerCount(value)
    local numericValue = tonumber(value)
    if not numericValue then
        return
    end

    if numericValue < 1 then
        numericValue = 1
    end

    if numericValue > 8 then
        numericValue = 8
    end

    rollState.currentWinnerCount = numericValue
    RebuildCurrentWinners()
end

local function ToggleRollDisabledByIndex(indexValue)
    if not IsViewingCurrentRollPage() then
        return
    end

    local entry = rollState.rollEntries[indexValue]
    if not entry then
        return
    end

    entry.disabled = not entry.disabled
    RebuildCurrentWinners()
end

local function AddRoll(playerName, rollValue)
    if not rollState.isRecordingRolls then
        return false
    end

    if not rollState.canAcceptRolls then
        return false
    end

    if not playerName or not rollValue then
        return false
    end

    if DidPlayerAlreadyRoll(playerName) then
        return false
    end

    rollState.rollHistoryViewIndex = 0

    rollState.rollEntries[#rollState.rollEntries + 1] = {
        name = playerName,
        roll = tonumber(rollValue) or 0,
        disabled = false
    }

    SortRollEntries()

    return true
end

local function BuildCountdownAnnounceMap(durationValue)
    local announceMap = {}

    local halfValue = math.floor(durationValue / 2)
    local quarterValue = math.floor(durationValue / 4)
    local sixthValue = math.floor(durationValue / 6)

    if sixthValue > 3 then
        announceMap[sixthValue] = true
    end

    if quarterValue > 3 then
        announceMap[quarterValue] = true
    end

    if halfValue > 3 then
        announceMap[halfValue] = true
    end

    announceMap[3] = true
    announceMap[2] = true
    announceMap[1] = true

    return announceMap
end

local function UpdateCountdown()
    if not rollState.isCountdownActive then
        return
    end

    local remainingValue = GetCountdownRemaining()

    if rollState.countdownLastAnnounced == nil then
        rollState.countdownLastAnnounced = rollState.countdownDuration
    end

    if remainingValue ~= rollState.countdownLastAnnounced then
        local announceMap = BuildCountdownAnnounceMap(rollState.countdownDuration)

        if remainingValue > 0 and announceMap[remainingValue] then
            Announce("Rolling ends in " .. remainingValue .. ".")
        end

        rollState.countdownLastAnnounced = remainingValue
    end

    if remainingValue <= 0 then
        CompleteRollSession()
    end
end

local function StartRollSessionInternal(rollType)
    EnsureSavedVariables()

    if not rollState.currentItemLink then
        return
    end

    if rollState.isCountdownActive then
        return
    end

    rollState.rollHistoryViewIndex = 0
    ResetCurrentRollResults()
    ClearAllWinnerMarks()

    rollState.currentRollType = rollType
    rollState.isRecordingRolls = true
    rollState.canAcceptRolls = true
    rollState.countdownDuration = tonumber(RTRollManagerSave.countdownDuration) or 20
    rollState.isCountdownActive = true
    rollState.countdownStartTime = GetTime()
    rollState.countdownLastAnnounced = nil

    Announce(BuildRollStartedMessage())
end

local function StartRollSession(rollType)
    EnsureSavedVariables()

    if not rollState.currentItemLink then
        return
    end

    if rollState.isCountdownActive then
        return
    end

    if HasActiveUnannouncedWinners() then
        StaticPopup_Show("RTROLLMANAGER_ACTIVE_WINNER_WARNING", nil, nil, rollType)
        return
    end

    StartRollSessionInternal(rollType)
end

local function ParseRollMessage(msg)
    if not msg or msg == "" then
        return nil, nil, nil, nil
    end

    local playerName, rollValue, lowValue, highValue = string.match(msg, "(.+) rolls (%d+) %((%d+)%-(%d+)%)")
    if playerName and rollValue and lowValue and highValue then
        return playerName, tonumber(rollValue), tonumber(lowValue), tonumber(highValue)
    end

    return nil, nil, nil, nil
end

local function OnSystemMessage(msg)
    local playerName, rollValue, lowValue, highValue = ParseRollMessage(msg)

    if not playerName or not rollValue then
        return
    end

    if lowValue ~= 1 or highValue ~= 100 then
        return
    end

    AddRoll(playerName, rollValue)
end

local function IsFrameHierarchyVisible(frame)
    local currentFrame = frame

    while currentFrame do
        if not currentFrame:IsVisible() then
            return false
        end

        currentFrame = currentFrame:GetParent()
    end

    return true
end

local function CanChangeSelectedItem()
    if rollState.isCountdownActive then
        return false
    end

    return true
end

local function IsLinkInsertEligible(linkValue)
    if not uiRefs.itemEditBox then
        return false
    end

    if not uiRefs.rollContentFrame or not IsFrameHierarchyVisible(uiRefs.rollContentFrame) then
        return false
    end

    if not CanChangeSelectedItem() then
        return false
    end

    if type(linkValue) ~= "string" then
        return false
    end

    if not string.find(linkValue, "|Hitem:") then
        return false
    end

    return true
end

local function TryHandleRollManagerInsertLink(linkValue)
    if not IsLinkInsertEligible(linkValue) then
        return false
    end

    SetSelectedItem(linkValue)

    if uiRefs.itemEditBox then
        uiRefs.itemEditBox:ClearFocus()
    end

    RefreshRollUI()
    return true
end

local function CallOriginalInsertLink(linkValue)
    if type(originalChatEdit_InsertLink) == "function" then
        return originalChatEdit_InsertLink(linkValue)
    end

    return false
end

local function InstallInsertLinkHook()
    if isInsertLinkHookInstalled then
        return
    end

    originalChatEdit_InsertLink = ChatEdit_InsertLink
    isInsertLinkHookInstalled = true

    ChatEdit_InsertLink = function(linkValue)
        if TryHandleRollManagerInsertLink(linkValue) then
            return true
        end

        return CallOriginalInsertLink(linkValue)
    end
end

local function GetViewedRollSnapshot()
    EnsureSavedVariables()
    NormalizeRollHistoryViewIndex()

    if not IsViewingCurrentRollPage() then
        return RTRollManagerSave.rollHistory[rollState.rollHistoryViewIndex]
    end

    return nil
end

local function GetDisplayedRollData()
    NormalizeRollHistoryViewIndex()

    local viewedSnapshot = GetViewedRollSnapshot()

    if viewedSnapshot then
        local displayedWinnerNames = {}
        local winnerIndex = 1

        while winnerIndex <= #(viewedSnapshot.winners or {}) do
            displayedWinnerNames[#displayedWinnerNames + 1] = viewedSnapshot.winners[winnerIndex].name
            winnerIndex = winnerIndex + 1
        end

        return {
            isHistory = true,
            itemLink = viewedSnapshot.itemLink or nil,
            rollType = viewedSnapshot.rollType or nil,
            rolls = viewedSnapshot.rolls or {},
            winnerNames = displayedWinnerNames,
            snapshot = viewedSnapshot
        }
    end

    return {
        isHistory = false,
        itemLink = rollState.currentItemLink,
        rollType = rollState.currentRollType,
        rolls = rollState.rollEntries,
        winnerNames = rollState.currentWinnerNames,
        snapshot = nil
    }
end

local function BuildDisplayedWinnerText(displayData)
    if not displayData or not displayData.winnerNames or #displayData.winnerNames == 0 then
        return ""
    end

    local parts = {}
    local winnerIndex = 1

    while winnerIndex <= #displayData.winnerNames do
        local winnerName = displayData.winnerNames[winnerIndex]
        local winnerRollValue = 0

        if displayData.isHistory and displayData.snapshot and displayData.snapshot.winners then
            local historyWinnerIndex = 1

            while historyWinnerIndex <= #displayData.snapshot.winners do
                local historyWinner = displayData.snapshot.winners[historyWinnerIndex]
                if historyWinner.name == winnerName then
                    winnerRollValue = historyWinner.roll or 0
                    break
                end
                historyWinnerIndex = historyWinnerIndex + 1
            end
        else
            winnerRollValue = GetWinnerRollValueByName(winnerName)
        end

        parts[#parts + 1] = winnerName .. " (" .. winnerRollValue .. ")"
        winnerIndex = winnerIndex + 1
    end

    return table.concat(parts, ", ")
end

local function GetMSChangesText()
    EnsureSavedVariables()
    return RTRollManagerSave.msChangesText or ""
end

local function SaveMSChangesText(textValue)
    EnsureSavedVariables()
    RTRollManagerSave.msChangesText = textValue or ""
end

local function SetMSChangesEditMode(isEditing)
    rollState.isEditingMSChanges = isEditing and true or false

    if not uiRefs.msChangesEditBox or not uiRefs.msChangesToggleButton then
        return
    end

    if rollState.isEditingMSChanges then
        uiRefs.msChangesToggleButton:SetText("Save")
        uiRefs.msChangesEditBox:EnableMouse(true)
        uiRefs.msChangesEditBox:EnableKeyboard(true)
        uiRefs.msChangesEditBox:SetTextColor(0, 1, 0)
        uiRefs.msChangesEditBox:SetFocus()
    else
        uiRefs.msChangesToggleButton:SetText("Edit")
        uiRefs.msChangesEditBox:ClearFocus()
        uiRefs.msChangesEditBox:EnableMouse(false)
        uiRefs.msChangesEditBox:EnableKeyboard(false)
        uiRefs.msChangesEditBox:SetTextColor(1, 1, 1)

        local savedText = GetMSChangesText()
        if uiRefs.msChangesEditBox:GetText() ~= savedText then
            uiRefs.msChangesEditBox:SetText(savedText)
        end
    end
end

local function AnnounceMSChanges()
    local textValue = ""

    if uiRefs.msChangesEditBox then
        textValue = uiRefs.msChangesEditBox:GetText() or ""
    else
        textValue = GetMSChangesText()
    end

    textValue = string.gsub(textValue, "\r\n", "\n")
    textValue = string.gsub(textValue, "\r", "\n")

    if textValue == "" then
        return
    end

    local hasAtLeastOneLine = false

    for line in string.gmatch(textValue, "[^\n]+") do
        local trimmedLine = string.gsub(line, "^%s+", "")
        trimmedLine = string.gsub(trimmedLine, "%s+$", "")

        if trimmedLine ~= "" then
            hasAtLeastOneLine = true
            Announce(trimmedLine)
        end
    end

    if not hasAtLeastOneLine then
        Announce(textValue)
    end
end

local function EnsureRollRowButton(indexValue)
    if uiRefs.rollRowButtons[indexValue] then
        return uiRefs.rollRowButtons[indexValue], uiRefs.rollRowTexts[indexValue], uiRefs.rollRowStrikeLines[indexValue]
    end

    local rowButton = CreateFrame("Button", nil, uiRefs.rollScrollChild)
    rowButton:SetHeight(18)
    rowButton:RegisterForClicks("RightButtonUp")
    rowButton:SetNormalTexture(nil)
    rowButton:SetHighlightTexture(nil)
    rowButton:SetPushedTexture(nil)
    rowButton:SetDisabledTexture(nil)

    if indexValue == 1 then
        rowButton:SetPoint("TOPLEFT", 0, 0)
        rowButton:SetPoint("TOPRIGHT", 0, 0)
    else
        rowButton:SetPoint("TOPLEFT", uiRefs.rollRowButtons[indexValue - 1], "BOTTOMLEFT", 0, -2)
        rowButton:SetPoint("TOPRIGHT", uiRefs.rollRowButtons[indexValue - 1], "BOTTOMRIGHT", 0, -2)
    end

    local rowText = rowButton:CreateFontString(nil, "OVERLAY", "ChatFontSmall")
    rowText:SetPoint("TOPLEFT", 0, 0)
    rowText:SetPoint("BOTTOMRIGHT", 0, 0)
    rowText:SetJustifyH("LEFT")
    rowText:SetJustifyV("MIDDLE")

    local strikeLine = rowButton:CreateTexture(nil, "ARTWORK")
    strikeLine:SetTexture("Interface\\Buttons\\WHITE8X8")
    strikeLine:SetHeight(1)
    strikeLine:SetVertexColor(0.7, 0.7, 0.7, 0.95)
    strikeLine:Hide()

    rowButton.text = rowText
    rowButton.strikeLine = strikeLine

    rowButton:SetScript("OnClick", function(_, button)
        if button ~= "RightButton" then
            return
        end

        if not IsViewingCurrentRollPage() then
            return
        end

        ToggleRollDisabledByIndex(indexValue)
        RefreshRollUI()
    end)

    uiRefs.rollRowButtons[indexValue] = rowButton
    uiRefs.rollRowTexts[indexValue] = rowText
    uiRefs.rollRowStrikeLines[indexValue] = strikeLine

    return rowButton, rowText, strikeLine
end

local function TrimHistoryRowTextToWidth(fontString, fullText, maxWidth)
    if not fontString then
        return fullText or ""
    end

    local textValue = fullText or ""
    fontString:SetText(textValue)

    if (fontString:GetStringWidth() or 0) <= maxWidth then
        return textValue
    end

    local ellipsisText = "..."
    local leftIndex = 1
    local rightIndex = string.len(textValue)
    local bestText = ellipsisText

    while leftIndex <= rightIndex do
        local middleIndex = math.floor((leftIndex + rightIndex) / 2)
        local candidateText = string.sub(textValue, 1, middleIndex) .. ellipsisText

        fontString:SetText(candidateText)

        if (fontString:GetStringWidth() or 0) <= maxWidth then
            bestText = candidateText
            leftIndex = middleIndex + 1
        else
            rightIndex = middleIndex - 1
        end
    end

    fontString:SetText(bestText)
    return bestText
end

local function ToggleWinnerHistoryStrikeByIndex(indexValue)
    if not rollState.historyStruckIndices then
        rollState.historyStruckIndices = {}
    end

    rollState.historyStruckIndices[indexValue] = not rollState.historyStruckIndices[indexValue]
end

local function EnsureHistoryRowButton(indexValue)
    if uiRefs.historyRowButtons[indexValue] then
        return
            uiRefs.historyRowButtons[indexValue],
            uiRefs.historyRowTexts[indexValue],
            uiRefs.historyRowStrikeLines[indexValue]
    end

    local rowButton = CreateFrame("Button", nil, uiRefs.historyScrollChild, "UIPanelButtonTemplate")
    rowButton:SetHeight(20)
    rowButton:RegisterForClicks("LeftButtonUp")
    rowButton:SetNormalTexture(nil)
    rowButton:SetHighlightTexture(nil)
    rowButton:SetPushedTexture(nil)
    rowButton:SetDisabledTexture(nil)

    if indexValue == 1 then
        rowButton:SetPoint("TOPLEFT", 0, 0)
        rowButton:SetPoint("TOPRIGHT", 0, 0)
    else
        rowButton:SetPoint("TOPLEFT", uiRefs.historyRowButtons[indexValue - 1], "BOTTOMLEFT", 0, -2)
        rowButton:SetPoint("TOPRIGHT", uiRefs.historyRowButtons[indexValue - 1], "BOTTOMRIGHT", 0, -2)
    end

    local rowText = rowButton:CreateFontString(nil, "OVERLAY", "ChatFontSmall")
    rowText:SetPoint("LEFT", 6, 0)
    rowText:SetPoint("RIGHT", -6, 0)
    rowText:SetJustifyH("LEFT")
    rowText:SetJustifyV("MIDDLE")

    local strikeLine = rowButton:CreateTexture(nil, "ARTWORK")
    strikeLine:SetTexture("Interface\\Buttons\\WHITE8X8")
    strikeLine:SetHeight(1)
    strikeLine:SetVertexColor(0.8, 0.8, 0.8, 0.95)
    strikeLine:Hide()

    rowButton.text = rowText
    rowButton.strikeLine = strikeLine

    rowButton:SetScript("OnClick", function()
        ToggleWinnerHistoryStrikeByIndex(indexValue)
        RefreshRollUI()
    end)

    uiRefs.historyRowButtons[indexValue] = rowButton
    uiRefs.historyRowTexts[indexValue] = rowText
    uiRefs.historyRowStrikeLines[indexValue] = strikeLine

    return rowButton, rowText, strikeLine
end

local function RefreshRollListUI()
    if not uiRefs.logLabel or not uiRefs.rollScrollChild or not uiRefs.logBg then
        return
    end

    EnsureSavedVariables()
    NormalizeRollHistoryViewIndex()

    local displayData = GetDisplayedRollData()
    local displayedRolls = displayData.rolls or {}
    local displayedWinners = displayData.winnerNames or {}

    local historyCount = #RTRollManagerSave.rollHistory
    local totalPages = historyCount
    local pageNumber = totalPages + 1

    if not IsViewingCurrentRollPage() then
        pageNumber = (totalPages - rollState.rollHistoryViewIndex) + 1
    end

    uiRefs.logLabel:SetText("#" .. pageNumber .. " Roll List:")

    local availableWidth = uiRefs.logBg:GetWidth() - 40
    if availableWidth < 50 then
        availableWidth = 50
    end

    if #displayedRolls == 0 then
        local rowButton, rowText, strikeLine = EnsureRollRowButton(1)
        rowButton:SetWidth(availableWidth)
        rowButton:Show()
        rowButton:EnableMouse(false)
        rowText:SetText("No rolls yet.")
        rowText:SetTextColor(1, 1, 1)
        strikeLine:Hide()

        local emptyTextWidth = rowText:GetStringWidth() or availableWidth
        if emptyTextWidth < 1 then
            emptyTextWidth = availableWidth
        end

        strikeLine:ClearAllPoints()
        strikeLine:SetPoint("LEFT", rowText, "LEFT", 0, 0)
        strikeLine:SetPoint("RIGHT", rowText, "LEFT", emptyTextWidth, 0)
        strikeLine:SetPoint("CENTER", rowText, "CENTER", 0, 0)

        local hideIndex = 2
        while uiRefs.rollRowButtons[hideIndex] do
            uiRefs.rollRowButtons[hideIndex]:Hide()
            hideIndex = hideIndex + 1
        end

        uiRefs.rollScrollChild:SetWidth(availableWidth)
        uiRefs.rollScrollChild:SetHeight(22)
        uiRefs.rollScrollFrame:UpdateScrollChildRect()
        return
    end

    local index = 1
    while index <= #displayedRolls do
        local rowButton, rowText, strikeLine = EnsureRollRowButton(index)
        local entry = displayedRolls[index]

        rowButton:SetWidth(availableWidth)
        rowButton:Show()
        rowButton:EnableMouse(displayData.isHistory ~= true)

        local isWinner = false
        local winnerIndex = 1

        while winnerIndex <= #displayedWinners do
            if displayedWinners[winnerIndex] == entry.name then
                isWinner = true
                break
            end
            winnerIndex = winnerIndex + 1
        end

        local prefix = "  "
        if isWinner and not entry.disabled then
            prefix = "* "
        end

        rowText:SetText(string.format("%s%s - %d", prefix, entry.name, entry.roll))

        if entry.disabled then
            rowText:SetTextColor(0.65, 0.65, 0.65)
            strikeLine:Show()
        elseif isWinner then
            rowText:SetTextColor(0.2, 1, 0.2)
            strikeLine:Hide()
        else
            rowText:SetTextColor(1, 1, 1)
            strikeLine:Hide()
        end

        local textWidth = rowText:GetStringWidth() or availableWidth
        if textWidth < 1 then
            textWidth = availableWidth
        end

        strikeLine:ClearAllPoints()
        strikeLine:SetPoint("LEFT", rowText, "LEFT", 0, 0)
        strikeLine:SetPoint("RIGHT", rowText, "LEFT", textWidth, 0)
        strikeLine:SetPoint("CENTER", rowText, "CENTER", 0, 0)

        index = index + 1
    end

    local hideIndex = index
    while uiRefs.rollRowButtons[hideIndex] do
        uiRefs.rollRowButtons[hideIndex]:Hide()
        hideIndex = hideIndex + 1
    end

    local contentHeight = (#displayedRolls * 20) + 4
    uiRefs.rollScrollChild:SetWidth(availableWidth)
    uiRefs.rollScrollChild:SetHeight(contentHeight)
    uiRefs.rollScrollFrame:UpdateScrollChildRect()
end

local function RefreshWinnerHistoryUI()
    if not uiRefs.historyScrollChild or not uiRefs.historyBg then
        return
    end

    EnsureSavedVariables()

    if not rollState.historyStruckIndices then
        rollState.historyStruckIndices = {}
    end

    local winnerHistory = RTRollManagerSave.winnerHistory or {}
    local availableWidth = uiRefs.historyBg:GetWidth() - 40

    if availableWidth < 80 then
        availableWidth = 80
    end

    if #winnerHistory == 0 then
        local rowButton, rowText, strikeLine = EnsureHistoryRowButton(1)
        rowButton:SetWidth(availableWidth)
        rowButton:Show()
        rowText:SetText("No winners yet.")
        rowText:SetTextColor(1, 1, 1)
        strikeLine:Hide()

        local emptyTextWidth = rowText:GetStringWidth() or availableWidth
        if emptyTextWidth < 1 then
            emptyTextWidth = availableWidth
        end

        strikeLine:ClearAllPoints()
        strikeLine:SetPoint("LEFT", rowText, "LEFT", 0, 0)
        strikeLine:SetPoint("RIGHT", rowText, "LEFT", emptyTextWidth, 0)
        strikeLine:SetPoint("CENTER", rowText, "CENTER", 0, 0)

        local hideIndex = 2
        while uiRefs.historyRowButtons[hideIndex] do
            uiRefs.historyRowButtons[hideIndex]:Hide()
            hideIndex = hideIndex + 1
        end

        uiRefs.historyScrollChild:SetWidth(availableWidth)
        uiRefs.historyScrollChild:SetHeight(24)
        uiRefs.historyScrollFrame:UpdateScrollChildRect()
        return
    end

    local index = 1
    while index <= #winnerHistory do
        local rowButton, rowText, strikeLine = EnsureHistoryRowButton(index)
        local entry = winnerHistory[index]

        rowButton:SetWidth(availableWidth)
        rowButton:Show()

        local fullText = string.format(
            "%s - %s - %s(%d)",
            entry.itemLink or "-",
            entry.winnerName or "-",
            entry.rollType or "-",
            entry.rollValue or 0
        )

        rowText:SetText(fullText)
        rowText:SetFont(STANDARD_TEXT_FONT, 12, "")

        if rollState.historyStruckIndices[index] then
            rowText:SetTextColor(0.65, 0.65, 0.65)
            strikeLine:Show()
        else
            rowText:SetTextColor(1, 1, 1)
            strikeLine:Hide()
        end

        local textWidth = rowText:GetStringWidth() or (availableWidth - 12)
        if textWidth < 1 then
            textWidth = availableWidth - 12
        end

        strikeLine:ClearAllPoints()
        strikeLine:SetPoint("LEFT", rowText, "LEFT", 0, 0)
        strikeLine:SetPoint("RIGHT", rowText, "LEFT", textWidth, 0)
        strikeLine:SetPoint("CENTER", rowText, "CENTER", 0, 0)

        index = index + 1
    end

    local hideIndex = index
    while uiRefs.historyRowButtons[hideIndex] do
        uiRefs.historyRowButtons[hideIndex]:Hide()
        hideIndex = hideIndex + 1
    end

    local contentHeight = (#winnerHistory * 22) + 4
    uiRefs.historyScrollChild:SetWidth(availableWidth)
    uiRefs.historyScrollChild:SetHeight(contentHeight)
    uiRefs.historyScrollFrame:UpdateScrollChildRect()
end

local function RefreshMSChangesUI()
    if not uiRefs.msChangesEditBox or not uiRefs.msChangesBg then
        return
    end

    if not rollState.isEditingMSChanges then
        local savedText = GetMSChangesText()
        if uiRefs.msChangesEditBox:GetText() ~= savedText then
            uiRefs.msChangesEditBox:SetText(savedText)
        end
    end

    local availableWidth = uiRefs.msChangesBg:GetWidth() - 40
    if availableWidth < 50 then
        availableWidth = 50
    end

    uiRefs.msChangesEditBox:SetWidth(availableWidth)

    local textHeight = GetSafeEditBoxTextHeight(uiRefs.msChangesEditBox, 20)
    if textHeight < 20 then
        textHeight = 20
    end

    uiRefs.msChangesEditBox:SetHeight(textHeight + 8)
    uiRefs.msChangesScrollChild:SetWidth(availableWidth)
    uiRefs.msChangesScrollChild:SetHeight(textHeight + 20)
    uiRefs.msChangesScrollFrame:UpdateScrollChildRect()
end

local function RefreshItemSectionUI()
    if not uiRefs.itemEditBox or not uiRefs.itemIcon or not uiRefs.winnerCountButton then
        return
    end

    if rollState.currentItemLink then
        uiRefs.itemEditBox:SetText(rollState.currentItemLink)
    else
        uiRefs.itemEditBox:SetText("")
    end

    uiRefs.winnerCountButton:SetText(tostring(rollState.currentWinnerCount))

    if rollState.currentItemTexture then
        uiRefs.itemIcon:SetTexture(rollState.currentItemTexture)
    else
        uiRefs.itemIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end

    if rollState.isCountdownActive then
        uiRefs.itemButton:Disable()
        uiRefs.itemEditBox:ClearFocus()
    else
        uiRefs.itemButton:Enable()
    end
end

local function RefreshWinnerLabelUI()
    if not uiRefs.winnerLabel then
        return
    end

    local displayData = GetDisplayedRollData()
    uiRefs.winnerLabel:SetText(BuildDisplayedWinnerText(displayData) or "")
end

local function RefreshRollHeaderLinkUI()
    if not uiRefs.rollHeaderLinkText then
        return
    end

    local displayData = GetDisplayedRollData()
    local displayedItemLink = displayData.itemLink

    if displayedItemLink and displayedItemLink ~= "-" then
        uiRefs.rollHeaderLinkText:SetText(displayedItemLink)
    else
        uiRefs.rollHeaderLinkText:SetText("")
    end
end

local function RefreshCountdownUI()
    if not uiRefs.countdownEditBox or not uiRefs.countdownBg or not uiRefs.countdownText then
        return
    end

    if rollState.isCountdownActive then
        if uiRefs.countdownEditBox:HasFocus() then
            uiRefs.countdownEditBox:ClearFocus()
        end

        uiRefs.countdownBg:Hide()
        uiRefs.countdownText:SetText(tostring(GetCountdownRemaining()))
        uiRefs.countdownText:Show()
    else
        uiRefs.countdownBg:Show()
        uiRefs.countdownText:Hide()

        if not uiRefs.countdownEditBox:HasFocus() then
            uiRefs.countdownEditBox:SetText(tostring(RTRollManagerSave.countdownDuration or 20))
        end

        uiRefs.countdownEditBox:SetTextColor(1, 1, 1)
    end
end

local function RefreshNavigationButtons()
    if not uiRefs.leftHistoryButton or not uiRefs.rightHistoryButton then
        return
    end

    EnsureSavedVariables()

    local hasRollHistory = #RTRollManagerSave.rollHistory > 0
    local canGoToOlder = false
    local canGoToNewer = false

    if hasRollHistory then
        if IsViewingCurrentRollPage() then
            canGoToOlder = true
            canGoToNewer = false
        else
            canGoToNewer = true
            canGoToOlder = rollState.rollHistoryViewIndex < #RTRollManagerSave.rollHistory
        end
    end

    SetButtonEnabled(uiRefs.leftHistoryButton, canGoToOlder)
    SetButtonEnabled(uiRefs.rightHistoryButton, canGoToNewer)
end

local function GetRollActionState()
    local hasSelectedItem = rollState.currentItemLink ~= nil and rollState.currentItemLink ~= ""
    local isViewingCurrentPage = IsViewingCurrentRollPage()
    local hasCurrentRolls = #rollState.rollEntries > 0
    local hasCurrentWinners = #rollState.currentWinnerNames > 0

    return {
        hasSelectedItem = hasSelectedItem,
        canFinishEarly = rollState.isCountdownActive,
        canAnnounceWinners = (not rollState.isCountdownActive)
            and isViewingCurrentPage
            and hasCurrentRolls
            and hasCurrentWinners
            and (not rollState.currentSessionAnnounced),
        isViewingCurrentPage = isViewingCurrentPage
    }
end

RefreshActionButtons = function()
    local actionState = GetRollActionState()

    SetButtonEnabled(uiRefs.msButton, actionState.hasSelectedItem and not rollState.isCountdownActive)
    SetButtonEnabled(uiRefs.osButton, actionState.hasSelectedItem and not rollState.isCountdownActive)
    SetButtonEnabled(uiRefs.finishEarlyButton, actionState.canFinishEarly)
    SetButtonEnabled(uiRefs.announceWinnersButton, actionState.canAnnounceWinners)
    SetButtonEnabled(uiRefs.msChangesToggleButton, true)
    SetButtonEnabled(uiRefs.msChangesAnnounceButton, GetMSChangesText() ~= "")

    if actionState.isViewingCurrentPage then
        uiRefs.announceWinnersButton:SetText("Announce Winners")
    else
        uiRefs.announceWinnersButton:SetText("History View")
    end
end

RefreshRollUI = function()
    if not uiRefs.rollContentFrame or not uiRefs.rollContentFrame:IsVisible() then
        return
    end

    EnsureSavedVariables()
    NormalizeRollHistoryViewIndex()

    RefreshRollListUI()
    RefreshWinnerHistoryUI()
    RefreshMSChangesUI()
    RefreshItemSectionUI()
    RefreshWinnerLabelUI()
    RefreshRollHeaderLinkUI()
    RefreshCountdownUI()
    RefreshNavigationButtons()
    RefreshActionButtons()
end

local function ShowWinnerCountButton()
    if not uiRefs.winnerCountEditBox or not uiRefs.winnerCountBg or not uiRefs.winnerCountButton then
        return
    end

    uiRefs.winnerCountEditBox:ClearFocus()
    uiRefs.winnerCountBg:Hide()
    uiRefs.winnerCountButton:Show()
    uiRefs.winnerCountButton:SetText(tostring(rollState.currentWinnerCount))
end

local function ShowWinnerCountEditBox()
    if not uiRefs.winnerCountEditBox or not uiRefs.winnerCountBg or not uiRefs.winnerCountButton then
        return
    end

    if rollState.isCountdownActive then
        return
    end

    uiRefs.winnerCountButton:Hide()
    uiRefs.winnerCountBg:Show()
    uiRefs.winnerCountEditBox:SetText(tostring(rollState.currentWinnerCount))
    uiRefs.winnerCountEditBox:SetFocus()
    uiRefs.winnerCountEditBox:HighlightText()
end

local function CreateItemSelectorSection(parent, skinModule)
    local selectLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    selectLabel:SetPoint("TOPLEFT", UI_CONSTANTS.LEFT_MARGIN, UI_CONSTANTS.TOP_MARGIN)
    selectLabel:SetText("Select Item:")

    local itemButton = CreateFrame("Button", nil, parent)
    itemButton:SetSize(UI_CONSTANTS.ITEM_ICON_SIZE, UI_CONSTANTS.ITEM_ICON_SIZE)
    itemButton:SetPoint("TOPLEFT", UI_CONSTANTS.LEFT_MARGIN, UI_CONSTANTS.TOP_SECTION_Y)
    itemButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    itemButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local itemIcon = itemButton:CreateTexture(nil, "ARTWORK")
    itemIcon:SetAllPoints()
    itemIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

    local itemBg, itemEditBox = CreatePixelInput(parent, UI_CONSTANTS.ITEM_INPUT_WIDTH, UI_CONSTANTS.INPUT_HEIGHT)
    itemBg:SetPoint("LEFT", itemButton, "RIGHT", 8, 0)

    local winnerCountButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    winnerCountButton:SetSize(UI_CONSTANTS.SMALL_BUTTON_WIDTH, UI_CONSTANTS.INPUT_HEIGHT)
    winnerCountButton:SetPoint("LEFT", itemBg, "RIGHT", 6, 0)
    winnerCountButton:SetText("1")
    HandleButtonSkin(skinModule, winnerCountButton)

    local winnerCountBg, winnerCountEditBox = CreatePixelInput(parent, UI_CONSTANTS.SMALL_BUTTON_WIDTH, UI_CONSTANTS.INPUT_HEIGHT)
    winnerCountBg:SetPoint("LEFT", itemBg, "RIGHT", 6, 0)
    winnerCountBg:Hide()

    winnerCountEditBox:SetNumeric(true)
    winnerCountEditBox:SetMaxLetters(1)

    uiRefs.itemButton = itemButton
    uiRefs.itemIcon = itemIcon
    uiRefs.itemBg = itemBg
    uiRefs.itemEditBox = itemEditBox
    uiRefs.winnerCountButton = winnerCountButton
    uiRefs.winnerCountBg = winnerCountBg
    uiRefs.winnerCountEditBox = winnerCountEditBox

    winnerCountEditBox:SetScript("OnEscapePressed", function()
        ShowWinnerCountButton()
    end)

    winnerCountEditBox:SetScript("OnEnterPressed", function(self)
        local numericValue = tonumber(self:GetText())

        if numericValue and numericValue >= 1 and numericValue <= 8 then
            SetCurrentWinnerCount(numericValue)
        end

        ShowWinnerCountButton()
        RefreshRollUI()
    end)

    winnerCountEditBox:SetScript("OnEditFocusLost", function(self)
        local numericValue = tonumber(self:GetText())

        if numericValue and numericValue >= 1 and numericValue <= 8 then
            SetCurrentWinnerCount(numericValue)
        end

        ShowWinnerCountButton()
        RefreshRollUI()
    end)

    winnerCountEditBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then
            return
        end

        local textValue = self:GetText()
        if textValue == "" then
            return
        end

        local numericValue = tonumber(textValue)
        if not numericValue or numericValue < 1 or numericValue > 8 then
            self:SetText(tostring(rollState.currentWinnerCount))
            self:HighlightText()
        end
    end)

    winnerCountButton:SetScript("OnClick", function()
        ShowWinnerCountEditBox()
    end)

    itemEditBox:EnableKeyboard(true)
    itemEditBox:SetAutoFocus(false)
    itemEditBox:SetText("")

    itemEditBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    itemEditBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)

    itemEditBox:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)

    itemEditBox:SetScript("OnEditFocusLost", function(self)
        self:SetText(rollState.currentItemLink or "")
    end)

    itemEditBox:SetScript("OnChar", function(self)
        self:SetText(rollState.currentItemLink or "")
        self:HighlightText(0, 0)
    end)

    itemEditBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then
            return
        end

        if not CanChangeSelectedItem() then
            self:SetText(rollState.currentItemLink or "")
            self:HighlightText(0, 0)
            return
        end

        local textValue = self:GetText()
        if textValue and textValue ~= "" and string.find(textValue, "|Hitem:") then
            SetSelectedItem(textValue)
            self:HighlightText(0, 0)
            RefreshRollUI()
            return
        end

        self:SetText(rollState.currentItemLink or "")
        self:HighlightText(0, 0)
    end)

    itemButton:SetScript("OnEnter", function(self)
        if rollState.currentItemLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(rollState.currentItemLink)
            GameTooltip:Show()
        end
    end)

    itemButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    itemButton:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            if not CanChangeSelectedItem() then
                return
            end

            if HasActiveUnannouncedWinners() then
                pendingItemLinkToSet = ""
                StaticPopup_Show("RTROLLMANAGER_ACTIVE_WINNER_ITEM_WARNING")
                return
            end

            ClearSelectedItem()
            RefreshRollUI()
            return
        end

        if not CanChangeSelectedItem() then
            return
        end

        if CursorHasItem() then
            local cursorType, itemID, itemLink = GetCursorInfo()

            if cursorType == "item" and itemLink then
                SetSelectedItem(itemLink)
            end

            ClearCursor()
            RefreshRollUI()
            return
        end

        itemEditBox:SetFocus()
        itemEditBox:HighlightText()
    end)
end

local function CreateActionButtonsSection(parent, skinModule)
    local msButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    msButton:SetSize(UI_CONSTANTS.STANDARD_BUTTON_WIDTH, UI_CONSTANTS.BUTTON_HEIGHT)
    msButton:SetPoint("TOPLEFT", UI_CONSTANTS.LEFT_MARGIN, UI_CONSTANTS.ACTIONS_Y)
    msButton:SetText("Start MS")
    HandleButtonSkin(skinModule, msButton)

    local osButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    osButton:SetSize(UI_CONSTANTS.STANDARD_BUTTON_WIDTH, UI_CONSTANTS.BUTTON_HEIGHT)
    osButton:SetPoint("LEFT", msButton, "RIGHT", 10, 0)
    osButton:SetText("Start OS")
    HandleButtonSkin(skinModule, osButton)

    local finishEarlyButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    finishEarlyButton:SetSize(UI_CONSTANTS.STANDARD_BUTTON_WIDTH, UI_CONSTANTS.BUTTON_HEIGHT)
    finishEarlyButton:SetPoint("LEFT", osButton, "RIGHT", 10, 0)
    finishEarlyButton:SetText("Finish Early")
    HandleButtonSkin(skinModule, finishEarlyButton)

    uiRefs.msButton = msButton
    uiRefs.osButton = osButton
    uiRefs.finishEarlyButton = finishEarlyButton

    msButton:SetScript("OnClick", function()
        StartRollSession("MS")
        RefreshRollUI()
    end)

    osButton:SetScript("OnClick", function()
        StartRollSession("OS")
        RefreshRollUI()
    end)

    finishEarlyButton:SetScript("OnClick", function()
        FinishEarly()
        RefreshRollUI()
    end)
end

local function CreateCountdownSection(parent)
    local timerLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    timerLabel:SetPoint("TOPLEFT", UI_CONSTANTS.LEFT_MARGIN, UI_CONSTANTS.COUNTDOWN_Y)
    timerLabel:SetText("Countdown:")

    local countdownBg, countdownEditBox = CreatePixelInput(parent, UI_CONSTANTS.COUNTDOWN_INPUT_WIDTH, UI_CONSTANTS.INPUT_HEIGHT)
    countdownBg:SetPoint("LEFT", timerLabel, "RIGHT", 8, 0)

    local countdownText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    countdownText:SetPoint("LEFT", timerLabel, "RIGHT", 8, 0)
    countdownText:SetWidth(UI_CONSTANTS.COUNTDOWN_INPUT_WIDTH)
    countdownText:SetJustifyH("LEFT")
    countdownText:SetText("")
    countdownText:Hide()

    uiRefs.countdownBg = countdownBg
    uiRefs.countdownEditBox = countdownEditBox
    uiRefs.countdownText = countdownText

    countdownEditBox:SetNumeric(true)
    countdownEditBox:SetMaxLetters(2)
    countdownEditBox:SetText(tostring(RTRollManagerSave and RTRollManagerSave.countdownDuration or 20))

    countdownEditBox:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(RTRollManagerSave.countdownDuration or 20))
        self:ClearFocus()
    end)

    countdownEditBox:SetScript("OnEnterPressed", function(self)
        local value = tonumber(self:GetText())

        if value and value > 0 then
            EnsureSavedVariables()
            RTRollManagerSave.countdownDuration = value
            rollState.countdownDuration = value
            self:SetText(tostring(value))
        else
            self:SetText(tostring(RTRollManagerSave.countdownDuration or 20))
        end

        self:ClearFocus()
    end)

    countdownEditBox:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)

    countdownEditBox:SetScript("OnEditFocusLost", function(self)
        local value = tonumber(self:GetText())

        if value and value > 0 then
            EnsureSavedVariables()
            RTRollManagerSave.countdownDuration = value
            rollState.countdownDuration = value
            self:SetText(tostring(value))
        else
            self:SetText(tostring(RTRollManagerSave.countdownDuration or 20))
        end
    end)

    countdownEditBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then
            return
        end

        if rollState.isCountdownActive then
            return
        end

        local textValue = self:GetText()

        if textValue == "" then
            return
        end

        local value = tonumber(textValue)
        if value and value > 0 then
            EnsureSavedVariables()
            RTRollManagerSave.countdownDuration = value
            rollState.countdownDuration = value
        end
    end)
end

local function CreateWinnersSection(parent, skinModule)
    local announceWinnersButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    announceWinnersButton:SetSize(UI_CONSTANTS.LARGE_BUTTON_WIDTH, 24)
    announceWinnersButton:SetPoint("TOPLEFT", parent, "TOPLEFT", UI_CONSTANTS.OUTER_LEFT, UI_CONSTANTS.WINNERS_Y)
    announceWinnersButton:SetText("Announce Winners")
    HandleButtonSkin(skinModule, announceWinnersButton)

    local winnerLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    winnerLabel:SetPoint("LEFT", announceWinnersButton, "RIGHT", 10, 0)
    winnerLabel:SetPoint("RIGHT", parent, "CENTER", -UI_CONSTANTS.SPLIT_GAP - 6, 0)
    winnerLabel:SetJustifyH("LEFT")
    winnerLabel:SetJustifyV("MIDDLE")
    winnerLabel:SetText("")

    uiRefs.announceWinnersButton = announceWinnersButton
    uiRefs.winnerLabel = winnerLabel

    announceWinnersButton:SetScript("OnClick", function()
        if rollState.isCountdownActive then
            return
        end

        if not IsViewingCurrentRollPage() then
            return
        end

        if #rollState.currentWinnerNames == 0 then
            return
        end

        if rollState.currentSessionAnnounced then
            return
        end

        AnnounceWinners()
        RefreshRollUI()
    end)
end

local function CreateRollLogSection(parent, skinModule)
    local logLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    logLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", UI_CONSTANTS.OUTER_LEFT, UI_CONSTANTS.LIST_LABEL_Y)
    logLabel:SetText("Roll List:")

    local rollHeaderLinkButton = CreateFrame("Button", nil, parent)
    rollHeaderLinkButton:SetPoint("LEFT", logLabel, "RIGHT", 6, 0)
    rollHeaderLinkButton:SetPoint("RIGHT", parent, "CENTER", -UI_CONSTANTS.SPLIT_GAP - 120, 0)
    rollHeaderLinkButton:SetHeight(20)
    rollHeaderLinkButton:RegisterForClicks("LeftButtonUp")

    local rollHeaderLinkText = rollHeaderLinkButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rollHeaderLinkText:SetAllPoints()
    rollHeaderLinkText:SetJustifyH("LEFT")
    rollHeaderLinkButton.text = rollHeaderLinkText

    local logBg = CreateFrame("Frame", nil, parent)
    logBg:SetPoint("TOPLEFT", parent, "TOPLEFT", UI_CONSTANTS.OUTER_LEFT, UI_CONSTANTS.CONTENT_TOP_Y)
    logBg:SetPoint("BOTTOMRIGHT", parent, "BOTTOM", -UI_CONSTANTS.SPLIT_GAP, UI_CONSTANTS.PANEL_BOTTOM_Y)
    ApplyPanelStyle(logBg)

    local rightHistoryButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    rightHistoryButton:SetSize(UI_CONSTANTS.HISTORY_NAV_BUTTON_SIZE, 24)
    rightHistoryButton:SetPoint("TOPRIGHT", logBg, "TOPRIGHT", -2, 28)
    rightHistoryButton:SetText(">")
    HandleButtonSkin(skinModule, rightHistoryButton)

    local leftHistoryButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    leftHistoryButton:SetSize(UI_CONSTANTS.HISTORY_NAV_BUTTON_SIZE, 24)
    leftHistoryButton:SetPoint("RIGHT", rightHistoryButton, "LEFT", -4, 0)
    leftHistoryButton:SetText("<")
    HandleButtonSkin(skinModule, leftHistoryButton)

    local scrollFrame = CreateFrame("ScrollFrame", "RTRollManagerScrollFrame", logBg, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 8, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 8)

    local scrollChild = CreateFrame("Frame", "RTRollManagerScrollChild", scrollFrame)
    scrollChild:SetSize(1, 1)
    scrollFrame:SetScrollChild(scrollChild)

    uiRefs.logLabel = logLabel
    uiRefs.rollHeaderLinkButton = rollHeaderLinkButton
    uiRefs.rollHeaderLinkText = rollHeaderLinkText
    uiRefs.logBg = logBg
    uiRefs.leftHistoryButton = leftHistoryButton
    uiRefs.rightHistoryButton = rightHistoryButton
    uiRefs.rollScrollFrame = scrollFrame
    uiRefs.rollScrollChild = scrollChild

    rollHeaderLinkButton:SetScript("OnEnter", function(self)
        local displayData = GetDisplayedRollData()
        local linkValue = displayData and displayData.itemLink or nil

        if linkValue and linkValue ~= "-" then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(linkValue)
            GameTooltip:Show()
        end
    end)

    rollHeaderLinkButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    rollHeaderLinkButton:SetScript("OnClick", function()
        local displayData = GetDisplayedRollData()
        local linkValue = displayData and displayData.itemLink or nil

        if linkValue and linkValue ~= "-" and HandleModifiedItemClick then
            HandleModifiedItemClick(linkValue)
        end
    end)

    leftHistoryButton:SetScript("OnClick", function()
        EnsureSavedVariables()
        NormalizeRollHistoryViewIndex()

        if #RTRollManagerSave.rollHistory == 0 then
            return
        end

        if IsViewingCurrentRollPage() then
            rollState.rollHistoryViewIndex = 1
        elseif rollState.rollHistoryViewIndex < #RTRollManagerSave.rollHistory then
            rollState.rollHistoryViewIndex = rollState.rollHistoryViewIndex + 1
        end

        RefreshRollUI()
    end)

    rightHistoryButton:SetScript("OnClick", function()
        EnsureSavedVariables()
        NormalizeRollHistoryViewIndex()

        if #RTRollManagerSave.rollHistory == 0 then
            return
        end

        if rollState.rollHistoryViewIndex > 1 then
            rollState.rollHistoryViewIndex = rollState.rollHistoryViewIndex - 1
        else
            rollState.rollHistoryViewIndex = 0
        end

        RefreshRollUI()
    end)
end

local function CreateMSChangesSection(parent, skinModule)
    local msChangesLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    msChangesLabel:SetPoint("TOPLEFT", parent, "TOP", UI_CONSTANTS.SPLIT_GAP, UI_CONSTANTS.TOP_MARGIN)
    msChangesLabel:SetText("MS Changes:")

    local msChangesToggleButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    msChangesToggleButton:SetSize(70, 24)
    msChangesToggleButton:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -UI_CONSTANTS.OUTER_RIGHT, -14)
    msChangesToggleButton:SetText("Edit")
    HandleButtonSkin(skinModule, msChangesToggleButton)

    local msChangesAnnounceButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    msChangesAnnounceButton:SetSize(90, 24)
    msChangesAnnounceButton:SetPoint("RIGHT", msChangesToggleButton, "LEFT", -8, 0)
    msChangesAnnounceButton:SetText("Announce")
    HandleButtonSkin(skinModule, msChangesAnnounceButton)

    local msChangesBg = CreateFrame("Frame", nil, parent)
    msChangesBg:SetPoint("TOPLEFT", parent, "TOP", UI_CONSTANTS.SPLIT_GAP, UI_CONSTANTS.TOP_SECTION_Y)
    msChangesBg:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -UI_CONSTANTS.OUTER_RIGHT, UI_CONSTANTS.TOP_SECTION_Y)
    msChangesBg:SetHeight(UI_CONSTANTS.MS_CHANGES_HEIGHT)
    ApplyPanelStyle(msChangesBg)

    local msChangesScrollFrame = CreateFrame("ScrollFrame", "RTRollManagerMSChangesScrollFrame", msChangesBg, "UIPanelScrollFrameTemplate")
    msChangesScrollFrame:SetPoint("TOPLEFT", 8, -8)
    msChangesScrollFrame:SetPoint("BOTTOMRIGHT", -28, 8)

    local msChangesScrollChild = CreateFrame("Frame", "RTRollManagerMSChangesScrollChild", msChangesScrollFrame)
    msChangesScrollChild:SetSize(1, 1)
    msChangesScrollFrame:SetScrollChild(msChangesScrollChild)

    local msChangesEditBox = CreateFrame("EditBox", nil, msChangesScrollChild)
    msChangesEditBox:SetPoint("TOPLEFT", 0, 0)
    msChangesEditBox:SetMultiLine(true)
    msChangesEditBox:SetAutoFocus(false)
    msChangesEditBox:SetFontObject(ChatFontSmall)
    msChangesEditBox:SetTextInsets(0, 0, 0, 0)
    msChangesEditBox:SetJustifyH("LEFT")
    msChangesEditBox:SetText(GetMSChangesText())
    msChangesEditBox:EnableMouse(false)
    msChangesEditBox:EnableKeyboard(false)
    msChangesEditBox:SetTextColor(1, 1, 1)

    uiRefs.msChangesBg = msChangesBg
    uiRefs.msChangesEditBox = msChangesEditBox
    uiRefs.msChangesToggleButton = msChangesToggleButton
    uiRefs.msChangesAnnounceButton = msChangesAnnounceButton
    uiRefs.msChangesScrollFrame = msChangesScrollFrame
    uiRefs.msChangesScrollChild = msChangesScrollChild

    msChangesEditBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        self:SetText(GetMSChangesText())
        SetMSChangesEditMode(false)
        RefreshRollUI()
    end)

    msChangesEditBox:SetScript("OnEnterPressed", function(self)
        if IsShiftKeyDown() then
            self:Insert("\n")
            return
        end

        SaveMSChangesText(self:GetText() or "")
        SetMSChangesEditMode(false)
        RefreshRollUI()
    end)

    msChangesEditBox:SetScript("OnTextChanged", function()
        RefreshMSChangesUI()
    end)

    msChangesToggleButton:SetScript("OnClick", function()
        if not rollState.isEditingMSChanges then
            SetMSChangesEditMode(true)
            RefreshRollUI()
            return
        end

        SaveMSChangesText(msChangesEditBox:GetText() or "")
        SetMSChangesEditMode(false)
        RefreshRollUI()
    end)

    msChangesAnnounceButton:SetScript("OnClick", function()
        if rollState.isEditingMSChanges then
            SaveMSChangesText(msChangesEditBox:GetText() or "")
            SetMSChangesEditMode(false)
        end

        AnnounceMSChanges()
        RefreshRollUI()
    end)
end

local function CreateWinnerHistorySection(parent)
    local historyLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    historyLabel:SetPoint("TOPLEFT", parent, "TOP", UI_CONSTANTS.SPLIT_GAP, UI_CONSTANTS.LIST_LABEL_Y)
    historyLabel:SetText("Latest Winners:")

    local historyBg = CreateFrame("Frame", nil, parent)
    historyBg:SetPoint("TOPLEFT", parent, "TOP", UI_CONSTANTS.SPLIT_GAP, UI_CONSTANTS.CONTENT_TOP_Y)
    historyBg:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -UI_CONSTANTS.OUTER_RIGHT, UI_CONSTANTS.PANEL_BOTTOM_Y)
    ApplyPanelStyle(historyBg)

    local historyScrollFrame = CreateFrame("ScrollFrame", "RTRollManagerHistoryScrollFrame", historyBg, "UIPanelScrollFrameTemplate")
    historyScrollFrame:SetPoint("TOPLEFT", 8, -8)
    historyScrollFrame:SetPoint("BOTTOMRIGHT", -28, 8)

    local historyScrollChild = CreateFrame("Frame", "RTRollManagerHistoryScrollChild", historyScrollFrame)
    historyScrollChild:SetSize(1, 1)
    historyScrollFrame:SetScrollChild(historyScrollChild)

    uiRefs.historyBg = historyBg
    uiRefs.historyScrollFrame = historyScrollFrame
    uiRefs.historyScrollChild = historyScrollChild
end

local function CreateFooterButtons(parent, skinModule, onClose)
    local closeButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    closeButton:SetSize(UI_CONSTANTS.CLOSE_BUTTON_WIDTH, UI_CONSTANTS.BUTTON_HEIGHT)
    closeButton:SetPoint("BOTTOMRIGHT", -18, UI_CONSTANTS.FOOTER_Y)
    closeButton:SetText("Close")
    HandleButtonSkin(skinModule, closeButton)

    local clearWinnersSavedButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    clearWinnersSavedButton:SetSize(UI_CONSTANTS.CLEAR_WINNERS_BUTTON_WIDTH, UI_CONSTANTS.BUTTON_HEIGHT)
    clearWinnersSavedButton:SetPoint("BOTTOMLEFT", 18, UI_CONSTANTS.FOOTER_Y)
    clearWinnersSavedButton:SetText("Clear Saved Winners")
    HandleButtonSkin(skinModule, clearWinnersSavedButton)

    local clearRollsSavedButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    clearRollsSavedButton:SetSize(UI_CONSTANTS.CLEAR_ROLLS_BUTTON_WIDTH, UI_CONSTANTS.BUTTON_HEIGHT)
    clearRollsSavedButton:SetPoint("LEFT", clearWinnersSavedButton, "RIGHT", 10, 0)
    clearRollsSavedButton:SetText("Clear Saved Rolls")
    HandleButtonSkin(skinModule, clearRollsSavedButton)

    uiRefs.closeButton = closeButton
    uiRefs.clearWinnersSavedButton = clearWinnersSavedButton
    uiRefs.clearRollsSavedButton = clearRollsSavedButton

    closeButton:SetScript("OnClick", onClose)

    clearRollsSavedButton:SetScript("OnClick", function()
        ClearRollHistory()
        RefreshRollUI()
    end)

    clearWinnersSavedButton:SetScript("OnClick", function()
        ClearWinnerHistory()
        RefreshRollUI()
    end)
end

local function RegisterStaticPopups()
    StaticPopupDialogs["RTROLLMANAGER_ACTIVE_WINNER_ITEM_WARNING"] = {
        text = "There is still an active winner for the current roll.\nChanging the selected item will clear the current roll results.\n\nDo you want to continue?",
        button1 = YES,
        button2 = NO,
        OnAccept = function()
            ResetCurrentRollSession(false)

            if pendingItemLinkToSet and pendingItemLinkToSet ~= "" then
                SetSelectedItemInternal(pendingItemLinkToSet)
            else
                rollState.currentItemLink = nil
                rollState.currentItemName = nil
                rollState.currentItemTexture = nil
                rollState.currentWinnerCount = 1

                if uiRefs.itemEditBox then
                    uiRefs.itemEditBox:SetText("")
                    uiRefs.itemEditBox:ClearFocus()
                end

                if uiRefs.itemIcon then
                    uiRefs.itemIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                end

                if uiRefs.winnerCountButton then
                    uiRefs.winnerCountButton:SetText("1")
                end

                if uiRefs.winnerCountEditBox then
                    uiRefs.winnerCountEditBox:SetText("1")
                end
            end

            pendingItemLinkToSet = nil
            RefreshRollUI()
        end,
        OnCancel = function()
            pendingItemLinkToSet = nil
            RefreshRollUI()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3
    }

    StaticPopupDialogs["RTROLLMANAGER_ACTIVE_WINNER_WARNING"] = {
        text = "There is still an active winner for the current roll.\nStarting a new roll will clear the current roll results.\n\nDo you want to continue?",
        button1 = YES,
        button2 = NO,
        OnAccept = function(self, rollType)
            StartRollSessionInternal(rollType)
            RefreshRollUI()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3
    }
end

SLASH_RTROLLRESET1 = "/rtrollreset"
SlashCmdList["RTROLLRESET"] = function()
    ResetCurrentRollSession(true)
    RefreshRollUI()
    print("Roll Manager reset.")
end

function CreateRollManagerTabContent(parent, onClose)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints()
    frame:Hide()

    uiRefs.rollContentFrame = frame

    InstallInsertLinkHook()

    local _, skinModule = TryGetElvUISkinModule()

    CreateItemSelectorSection(frame, skinModule)
    CreateActionButtonsSection(frame, skinModule)
    CreateCountdownSection(frame)
    CreateWinnersSection(frame, skinModule)
    CreateRollLogSection(frame, skinModule)
    CreateMSChangesSection(frame, skinModule)
    CreateWinnerHistorySection(frame)
    CreateFooterButtons(frame, skinModule, onClose)

    frame:SetScript("OnShow", function()
        EnsureSavedVariables()
        NormalizeRollHistoryViewIndex()

        if uiRefs.countdownEditBox then
            uiRefs.countdownEditBox:SetText(tostring(RTRollManagerSave.countdownDuration or 20))
        end

        if uiRefs.msChangesEditBox then
            uiRefs.msChangesEditBox:SetText(GetMSChangesText())
        end

        SetMSChangesEditMode(false)
        RefreshRollUI()
    end)

    return frame
end

rollFrame:RegisterEvent("CHAT_MSG_SYSTEM")
rollFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "CHAT_MSG_SYSTEM" then
        OnSystemMessage(...)
        RefreshRollUI()
    end
end)

rollFrame:SetScript("OnUpdate", function()
    UpdateCountdown()

    if uiRefs.rollContentFrame and uiRefs.rollContentFrame:IsVisible() then
        RefreshCountdownUI()
        RefreshActionButtons()
    end
end)

loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, arg1)
    if arg1 ~= addonName then
        return
    end

    EnsureSavedVariables()
    rollState.countdownDuration = tonumber(RTRollManagerSave.countdownDuration) or 20

    RegisterStaticPopups()

    if RefreshStatusOverlay then
        RefreshStatusOverlay()
    end

    self:UnregisterEvent("ADDON_LOADED")
end)