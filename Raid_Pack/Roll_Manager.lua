-- Roll_Manager.lua
local addonName, addonTable = ...

local rollFrame = CreateFrame("Frame")
local RT_RefreshRollUI = nil
local RT_RefreshRollButtons = nil

local isRecordingRolls = false
local canAcceptRolls = false

local currentRollType = nil
local currentItemLink = nil
local currentItemName = nil
local currentItemTexture = nil

local isCountdownActive = false
local countdownDuration = 20
local countdownStartTime = 0
local countdownLastAnnounced = nil

local countdownBgRef = nil
local countdownTextRef = nil

local rollEntries = {}
local currentWinnerNames = {}
local currentWinnerCount = 1
local currentSessionAnnounced = false

local itemEditBoxRef = nil
local winnerHistoryTextRef = nil
local rollHistoryViewIndex = 0

local originalChatEdit_InsertLink = ChatEdit_InsertLink
local isInsertLinkHookInstalled = false

local rollContentFrameRef = nil

local msChangesEditBoxRef = nil
local msChangesToggleButtonRef = nil
local msChangesAnnounceButtonRef = nil
local isEditingMSChanges = false

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

local defaultSettings = {
    countdownDuration = 20,
    useRaidWarning = true,
    winnerHistory = {},
    rollHistory = {},
    msChangesText = ""
}

function RT_IsRollManagerEnabled()
    return true
end

local function EnsureSavedVariables()
    if type(RTRollManagerSave) ~= "table" then
        RTRollManagerSave = CopyTable(defaultSettings)
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

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, arg1)
    if arg1 ~= addonName then
        return
    end

    EnsureSavedVariables()
    countdownDuration = tonumber(RTRollManagerSave.countdownDuration) or 20

    if RefreshStatusOverlay then
        RefreshStatusOverlay()
    end

    self:UnregisterEvent("ADDON_LOADED")
end)

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

local function Announce(message)
    if not message or message == "" then
        return
    end

    SendChatMessage(message, GetAnnouncementChannel())
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
    while index <= #currentWinnerNames and index <= #RAID_MARK_ORDER do
        local winnerName = currentWinnerNames[index]
        local unit = GetUnitByName(winnerName)

        if unit then
            SetRaidTarget(unit, RAID_MARK_ORDER[index])
        end

        index = index + 1
    end
end

local function ResetRollEntries()
    wipe(rollEntries)
    wipe(currentWinnerNames)
    currentSessionAnnounced = false
end

local function GetWinnerRollValueByName(nameValue)
    local index = 1
    while index <= #rollEntries do
        if rollEntries[index].name == nameValue then
            return rollEntries[index].roll
        end
        index = index + 1
    end

    return 0
end

local function RebuildCurrentWinners()
    wipe(currentWinnerNames)

    local index = 1
    while index <= #rollEntries and index <= currentWinnerCount do
        currentWinnerNames[#currentWinnerNames + 1] = rollEntries[index].name
        index = index + 1
    end
end

local function SortRollEntries()
    table.sort(rollEntries, function(leftEntry, rightEntry)
        if leftEntry.roll == rightEntry.roll then
            return leftEntry.name < rightEntry.name
        end

        return leftEntry.roll > rightEntry.roll
    end)

    RebuildCurrentWinners()
end

local function DidPlayerAlreadyRoll(playerName)
    local index = 1
    while index <= #rollEntries do
        if rollEntries[index].name == playerName then
            return true
        end
        index = index + 1
    end

    return false
end

local function GetCountdownRemaining()
    if not isCountdownActive then
        return 0
    end

    local remainingValue = math.ceil(countdownDuration - (GetTime() - countdownStartTime))
    if remainingValue < 0 then
        remainingValue = 0
    end

    return remainingValue
end

local function NormalizeRollHistoryViewIndex()
    EnsureSavedVariables()

    local historyCount = #RTRollManagerSave.rollHistory

    if historyCount <= 0 then
        rollHistoryViewIndex = 0
        return
    end

    if rollHistoryViewIndex == nil or rollHistoryViewIndex < 0 then
        rollHistoryViewIndex = 0
        return
    end

    if rollHistoryViewIndex > historyCount then
        rollHistoryViewIndex = historyCount
    end
end

local function IsViewingCurrentRollPage()
    NormalizeRollHistoryViewIndex()
    return rollHistoryViewIndex == 0
end

local function RefreshRollUI()
    NormalizeRollHistoryViewIndex()

    if RT_RefreshRollUI then
        RT_RefreshRollUI()
    end

    if RT_RefreshRollButtons then
        RT_RefreshRollButtons()
    end
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

    currentWinnerCount = numericValue
    RebuildCurrentWinners()
    RefreshRollUI()
end

local function SetSelectedItem(itemLink)
    if not itemLink or itemLink == "" then
        return
    end

    local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemLink)

    currentItemLink = itemLink
    currentItemName = itemName or itemLink
    currentItemTexture = itemTexture
    currentWinnerCount = 1
    currentSessionAnnounced = false

    if itemEditBoxRef then
        itemEditBoxRef:SetText(itemLink)
        itemEditBoxRef:ClearFocus()
    end

    RefreshRollUI()
end

local function ClearSelectedItem()
    currentItemLink = nil
    currentItemName = nil
    currentItemTexture = nil
    currentWinnerCount = 1

    if itemEditBoxRef then
        itemEditBoxRef:SetText("")
        itemEditBoxRef:ClearFocus()
    end

    RefreshRollUI()
end

local function ResetCurrentRollSession(clearSelectedItemToo)
    wipe(rollEntries)
    wipe(currentWinnerNames)

    isRecordingRolls = false
    canAcceptRolls = false
    isCountdownActive = false
    countdownStartTime = 0
    countdownLastAnnounced = nil

    currentRollType = nil
    currentWinnerCount = 1
    currentSessionAnnounced = false
    rollHistoryViewIndex = 0

    if clearSelectedItemToo then
        currentItemLink = nil
        currentItemName = nil
        currentItemTexture = nil

        if itemEditBoxRef then
            itemEditBoxRef:SetText("")
            itemEditBoxRef:ClearFocus()
        end
    end
end

local function AddRoll(playerName, rollValue)
    if not isRecordingRolls then
        return false
    end

    if not canAcceptRolls then
        return false
    end

    if not playerName or not rollValue then
        return false
    end

    if DidPlayerAlreadyRoll(playerName) then
        return false
    end

    rollHistoryViewIndex = 0

    rollEntries[#rollEntries + 1] = {
        name = playerName,
        roll = tonumber(rollValue) or 0
    }

    SortRollEntries()
    RefreshRollUI()

    return true
end

local function BuildRollSnapshot()
    local snapshot = {
        rollType = currentRollType or "-",
        itemLink = currentItemLink or "-",
        winnerCount = currentWinnerCount or 1,
        winners = {},
        rolls = {}
    }

    local rollIndex = 1
    while rollIndex <= #rollEntries do
        snapshot.rolls[#snapshot.rolls + 1] = {
            name = rollEntries[rollIndex].name,
            roll = rollEntries[rollIndex].roll
        }
        rollIndex = rollIndex + 1
    end

    local winnerIndex = 1
    while winnerIndex <= #currentWinnerNames do
        local winnerName = currentWinnerNames[winnerIndex]
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

    if not currentItemLink or #rollEntries == 0 then
        return
    end

    local rollHistory = RTRollManagerSave.rollHistory
    local snapshot = BuildRollSnapshot()

    table.insert(rollHistory, 1, snapshot)

    while #rollHistory > 50 do
        table.remove(rollHistory, #rollHistory)
    end

    rollHistoryViewIndex = 0
end

local function AddWinnersToHistory()
    EnsureSavedVariables()

    local winnerHistory = RTRollManagerSave.winnerHistory
    local winnerIndex = 1

    while winnerIndex <= #currentWinnerNames do
        local winnerName = currentWinnerNames[winnerIndex]

        table.insert(winnerHistory, 1, {
            rollType = currentRollType or "-",
            itemLink = currentItemLink or "-",
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
    RefreshRollUI()
end

local function ClearRollHistory()
    EnsureSavedVariables()
    wipe(RTRollManagerSave.rollHistory)
    rollHistoryViewIndex = 0
    RefreshRollUI()
end

local function ClearWinnerHighlight()
    ClearAllWinnerMarks()
end

local function AnnounceWinners()
    if #currentWinnerNames == 0 then
        return
    end

    local parts = {}
    local index = 1

    while index <= #currentWinnerNames do
        local winnerName = currentWinnerNames[index]
        parts[#parts + 1] = winnerName .. " (" .. GetWinnerRollValueByName(winnerName) .. ")"
        index = index + 1
    end

    Announce("Winners for " .. (currentItemLink or "selected item") .. ": " .. table.concat(parts, ", "))
    AddWinnersToHistory()
    ApplyWinnerMarks()

    ResetCurrentRollSession(true)
    RefreshRollUI()
end

local function StartRollSession(rollType)
    EnsureSavedVariables()

    if not currentItemLink then
        return
    end

    if isCountdownActive then
        return
    end

    rollHistoryViewIndex = 0
    ResetRollEntries()
    ClearAllWinnerMarks()

    currentRollType = rollType
    isRecordingRolls = true
    canAcceptRolls = true

    countdownDuration = tonumber(RTRollManagerSave.countdownDuration) or 20
    isCountdownActive = true
    countdownStartTime = GetTime()
    countdownLastAnnounced = nil

    local rollText = currentRollType .. " roll started for " .. currentItemLink .. "."

    if currentWinnerCount and currentWinnerCount > 1 then
        rollText = rollText .. " Top " .. currentWinnerCount .. " highest rolls will win."
    end

    rollText = rollText .. " You have " .. countdownDuration .. " seconds to roll."

    Announce(rollText)

    RefreshRollUI()
end

local function CompleteRollSession()
    if not isRecordingRolls and not isCountdownActive then
        return
    end

    isCountdownActive = false
    isRecordingRolls = false
    canAcceptRolls = false
    countdownStartTime = 0
    countdownLastAnnounced = nil

    SaveRollSnapshot()
    rollHistoryViewIndex = 0

    Announce("Rolling ended for " .. (currentItemLink or "selected item") .. ".")

    RefreshRollUI()
end

local function FinishEarly()
    if not isCountdownActive then
        return
    end

    CompleteRollSession()
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
    if not isCountdownActive then
        return
    end

    local remainingValue = GetCountdownRemaining()

    if countdownLastAnnounced == nil then
        countdownLastAnnounced = countdownDuration
    end

    if remainingValue ~= countdownLastAnnounced then
        local announceMap = BuildCountdownAnnounceMap(countdownDuration)

        if remainingValue > 0 and announceMap[remainingValue] then
            if remainingValue <= 3 then
                Announce(tostring(remainingValue))
            else
                Announce("Rolling ends in " .. remainingValue .. ".")
            end
        end

        countdownLastAnnounced = remainingValue
        RefreshRollUI()
    end

    if remainingValue <= 0 then
        CompleteRollSession()
    end
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

local function TryInsertItemLink(linkValue)
    if not itemEditBoxRef then
        return false
    end

    if not rollContentFrameRef or not rollContentFrameRef:IsShown() then
        return false
    end

    if type(linkValue) ~= "string" then
        return false
    end

    if not string.find(linkValue, "|Hitem:") then
        return false
    end

    SetSelectedItem(linkValue)
    itemEditBoxRef:ClearFocus()
    return true
end

local function InstallInsertLinkHook()
    if isInsertLinkHookInstalled then
        return
    end

    isInsertLinkHookInstalled = true

    ChatEdit_InsertLink = function(linkValue)
        if TryInsertItemLink(linkValue) then
            return true
        end

        if originalChatEdit_InsertLink then
            return originalChatEdit_InsertLink(linkValue)
        end

        return false
    end
end

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

local function GetViewedRollSnapshot()
    EnsureSavedVariables()
    NormalizeRollHistoryViewIndex()

    if not IsViewingCurrentRollPage() then
        return RTRollManagerSave.rollHistory[rollHistoryViewIndex]
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
        itemLink = currentItemLink,
        rollType = currentRollType,
        rolls = rollEntries,
        winnerNames = currentWinnerNames,
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
    isEditingMSChanges = isEditing and true or false

    if not msChangesEditBoxRef or not msChangesToggleButtonRef then
        return
    end

    if isEditingMSChanges then
        msChangesToggleButtonRef:SetText("Save")
        msChangesEditBoxRef:EnableMouse(true)
        msChangesEditBoxRef:EnableKeyboard(true)
        msChangesEditBoxRef:SetTextColor(0, 1, 0)
        msChangesEditBoxRef:SetFocus()
    else
        msChangesToggleButtonRef:SetText("Edit")
        msChangesEditBoxRef:ClearFocus()
        msChangesEditBoxRef:EnableMouse(false)
        msChangesEditBoxRef:EnableKeyboard(false)
        msChangesEditBoxRef:SetTextColor(1, 1, 1)

        local savedText = GetMSChangesText()
        if msChangesEditBoxRef:GetText() ~= savedText then
            msChangesEditBoxRef:SetText(savedText)
        end
    end
end

local function AnnounceMSChanges()
    local textValue = ""

    if msChangesEditBoxRef then
        textValue = msChangesEditBoxRef:GetText() or ""
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

rollFrame:RegisterEvent("CHAT_MSG_SYSTEM")
rollFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "CHAT_MSG_SYSTEM" then
        OnSystemMessage(...)
    end
end)

rollFrame:SetScript("OnUpdate", function()
    UpdateCountdown()
end)

SLASH_RTROLLRESET1 = "/rtrollreset"
SlashCmdList["RTROLLRESET"] = function()
    ResetCurrentRollSession(true)
    RefreshRollUI()
    print("Roll Manager reset.")
end

function CreateRollManagerTabContent(parent, onClose)
    local f = CreateFrame("Frame", nil, parent)
    rollContentFrameRef = f
    f:SetAllPoints()
    f:Hide()

    InstallInsertLinkHook()

    local _, S = TryGetElvUISkinModule()

    local selectLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    selectLabel:SetPoint("TOPLEFT", 20, -20)
    selectLabel:SetText("Select Item:")

    local itemButton = CreateFrame("Button", nil, f)
    itemButton:SetSize(36, 36)
    itemButton:SetPoint("TOPLEFT", 20, -48)
    itemButton:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
    itemButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    itemButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local itemIcon = itemButton:CreateTexture(nil, "ARTWORK")
    itemIcon:SetAllPoints()
    itemIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

    local itemBg, itemEditBox = CreatePixelInput(f, 300, 28)
    itemBg:SetPoint("LEFT", itemButton, "RIGHT", 8, 0)

    local winnerCountButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    winnerCountButton:SetSize(32, 28)
    winnerCountButton:SetPoint("LEFT", itemBg, "RIGHT", 6, 0)
    winnerCountButton:SetText("1")
    if S then
        S:HandleButton(winnerCountButton)
    end

    local winnerCountBg, winnerCountEditBox = CreatePixelInput(f, 32, 28)
    winnerCountBg:SetPoint("LEFT", itemBg, "RIGHT", 6, 0)
    winnerCountBg:Hide()

    winnerCountEditBox:SetNumeric(true)
    winnerCountEditBox:SetMaxLetters(1)

    local function ShowWinnerCountButton()
        winnerCountEditBox:ClearFocus()
        winnerCountBg:Hide()
        winnerCountButton:Show()
        winnerCountButton:SetText(tostring(currentWinnerCount))
    end

    local function ShowWinnerCountEditBox()
        winnerCountButton:Hide()
        winnerCountBg:Show()
        winnerCountEditBox:SetText(tostring(currentWinnerCount))
        winnerCountEditBox:SetFocus()
        winnerCountEditBox:HighlightText()
    end

    winnerCountEditBox:SetScript("OnEscapePressed", function(self)
        ShowWinnerCountButton()
    end)

    winnerCountEditBox:SetScript("OnEnterPressed", function(self)
        local textValue = self:GetText()
        local numericValue = tonumber(textValue)

        if numericValue and numericValue >= 1 and numericValue <= 8 then
            SetCurrentWinnerCount(numericValue)
        end

        ShowWinnerCountButton()
    end)

    winnerCountEditBox:SetScript("OnEditFocusLost", function(self)
        local textValue = self:GetText()
        local numericValue = tonumber(textValue)

        if numericValue and numericValue >= 1 and numericValue <= 8 then
            SetCurrentWinnerCount(numericValue)
        end

        ShowWinnerCountButton()
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
            self:SetText(tostring(currentWinnerCount))
            self:HighlightText()
        end
    end)

    winnerCountButton:SetScript("OnClick", function()
        ShowWinnerCountEditBox()
    end)

    itemEditBoxRef = itemEditBox
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
        self:SetText(currentItemLink or "")
    end)

    itemEditBox:SetScript("OnChar", function(self)
        self:SetText(currentItemLink or "")
        self:HighlightText(0, 0)
    end)

    itemEditBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then
            return
        end

        local textValue = self:GetText()
        if textValue and textValue ~= "" and string.find(textValue, "|Hitem:") then
            SetSelectedItem(textValue)
            if currentItemTexture then
                itemIcon:SetTexture(currentItemTexture)
            end
            self:HighlightText(0, 0)
            return
        end

        self:SetText(currentItemLink or "")
        self:HighlightText(0, 0)
    end)

    local msButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    msButton:SetSize(120, 28)
    msButton:SetPoint("TOPLEFT", 20, -96)
    msButton:SetText("Start MS")
    if S then
        S:HandleButton(msButton)
    end

    local osButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    osButton:SetSize(120, 28)
    osButton:SetPoint("LEFT", msButton, "RIGHT", 10, 0)
    osButton:SetText("Start OS")
    if S then
        S:HandleButton(osButton)
    end

    local finishEarlyButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    finishEarlyButton:SetSize(120, 28)
    finishEarlyButton:SetPoint("LEFT", osButton, "RIGHT", 10, 0)
    finishEarlyButton:SetText("Finish Early")
    if S then
        S:HandleButton(finishEarlyButton)
    end

    local timerLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    timerLabel:SetPoint("TOPLEFT", 20, -138)
    timerLabel:SetText("Countdown:")

    local countdownBg, countdownEditBox = CreatePixelInput(f, 70, 28)
    countdownBg:SetPoint("LEFT", timerLabel, "RIGHT", 8, 0)

    local countdownText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    countdownText:SetPoint("LEFT", timerLabel, "RIGHT", 8, 0)
    countdownText:SetWidth(70)
    countdownText:SetJustifyH("LEFT")
    countdownText:SetText("")
    countdownText:Hide()

    countdownBgRef = countdownBg
    countdownTextRef = countdownText

    countdownEditBox:SetNumeric(true)
    countdownEditBox:SetMaxLetters(2)
    countdownEditBox:SetText(tostring(RTRollManagerSave and RTRollManagerSave.countdownDuration or 20))

    countdownEditBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    countdownEditBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)

    countdownEditBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then
            return
        end

        if isCountdownActive then
            return
        end

        local value = tonumber(self:GetText())
        if value and value > 0 then
            EnsureSavedVariables()
            RTRollManagerSave.countdownDuration = value
            countdownDuration = value
        end
    end)

    local announceWinnersButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    announceWinnersButton:SetSize(140, 24)
    announceWinnersButton:SetPoint("TOPLEFT", 20, -170)
    announceWinnersButton:SetText("Announce Winners")
    if S then
        S:HandleButton(announceWinnersButton)
    end

    local winnerLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    winnerLabel:SetPoint("LEFT", announceWinnersButton, "RIGHT", 10, 0)
    winnerLabel:SetWidth(300)
    winnerLabel:SetJustifyH("LEFT")
    winnerLabel:SetText("")

    local logLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    logLabel:SetPoint("TOPLEFT", 20, -204)
    logLabel:SetText("Roll List:")

    local rollHeaderLinkButton = CreateFrame("Button", nil, f)
    rollHeaderLinkButton:SetPoint("LEFT", logLabel, "RIGHT", 6, 0)
    rollHeaderLinkButton:SetSize(210, 20)
    rollHeaderLinkButton:RegisterForClicks("LeftButtonUp")

    local rollHeaderLinkText = rollHeaderLinkButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rollHeaderLinkText:SetAllPoints()
    rollHeaderLinkText:SetJustifyH("LEFT")
    rollHeaderLinkButton.text = rollHeaderLinkText

    local msChangesLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    msChangesLabel:SetPoint("TOPLEFT", 452, -20)
    msChangesLabel:SetText("MS Changes:")

    local msChangesToggleButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    msChangesToggleButton:SetSize(70, 24)
    msChangesToggleButton:SetPoint("TOPRIGHT", -20, -14)
    msChangesToggleButton:SetText("Edit")
    if S then
        S:HandleButton(msChangesToggleButton)
    end

    local msChangesAnnounceButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    msChangesAnnounceButton:SetSize(90, 24)
    msChangesAnnounceButton:SetPoint("RIGHT", msChangesToggleButton, "LEFT", -8, 0)
    msChangesAnnounceButton:SetText("Announce")
    if S then
        S:HandleButton(msChangesAnnounceButton)
    end

    local msChangesBg = CreateFrame("Frame", nil, f)
    msChangesBg:SetPoint("TOPLEFT", 452, -48)
    msChangesBg:SetPoint("TOPRIGHT", -20, -48)
    msChangesBg:SetHeight(105)
    msChangesBg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1
    })
    msChangesBg:SetBackdropColor(0, 0, 0, 0.9)
    msChangesBg:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

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

    msChangesEditBoxRef = msChangesEditBox
    msChangesToggleButtonRef = msChangesToggleButton
    msChangesAnnounceButtonRef = msChangesAnnounceButton

    local historyLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    historyLabel:SetPoint("TOPLEFT", 452, -204)
    historyLabel:SetText("Latest Winners:")

    local logBg = CreateFrame("Frame", nil, f)
    logBg:SetPoint("TOPLEFT", 20, -230)
    logBg:SetPoint("BOTTOMRIGHT", -452, 58)
    logBg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1
    })
    logBg:SetBackdropColor(0, 0, 0, 0.9)
    logBg:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    local historyBg = CreateFrame("Frame", nil, f)
    historyBg:SetPoint("TOPLEFT", 452, -230)
    historyBg:SetPoint("BOTTOMRIGHT", -20, 58)
    historyBg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1
    })
    historyBg:SetBackdropColor(0, 0, 0, 0.9)
    historyBg:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    local rightHistoryButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    rightHistoryButton:SetSize(28, 24)
    rightHistoryButton:SetPoint("TOPRIGHT", logBg, "TOPRIGHT", -2, 28)
    rightHistoryButton:SetText(">")
    if S then
        S:HandleButton(rightHistoryButton)
    end

    local leftHistoryButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    leftHistoryButton:SetSize(28, 24)
    leftHistoryButton:SetPoint("RIGHT", rightHistoryButton, "LEFT", -4, 0)
    leftHistoryButton:SetText("<")
    if S then
        S:HandleButton(leftHistoryButton)
    end

    local scrollFrame = CreateFrame("ScrollFrame", "RTRollManagerScrollFrame", logBg, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 8, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 8)

    local scrollChild = CreateFrame("Frame", "RTRollManagerScrollChild", scrollFrame)
    scrollChild:SetSize(1, 1)
    scrollFrame:SetScrollChild(scrollChild)

    local rollText = scrollChild:CreateFontString(nil, "OVERLAY", "ChatFontSmall")
    rollText:SetPoint("TOPLEFT", 0, 0)
    rollText:SetJustifyH("LEFT")
    rollText:SetJustifyV("TOP")

    local historyScrollFrame = CreateFrame("ScrollFrame", "RTRollManagerHistoryScrollFrame", historyBg, "UIPanelScrollFrameTemplate")
    historyScrollFrame:SetPoint("TOPLEFT", 8, -8)
    historyScrollFrame:SetPoint("BOTTOMRIGHT", -28, 8)

    local historyScrollChild = CreateFrame("Frame", "RTRollManagerHistoryScrollChild", historyScrollFrame)
    historyScrollChild:SetSize(1, 1)
    historyScrollFrame:SetScrollChild(historyScrollChild)

    local historyText = historyScrollChild:CreateFontString(nil, "OVERLAY", "ChatFontSmall")
    historyText:SetPoint("TOPLEFT", 0, 0)
    historyText:SetJustifyH("LEFT")
    historyText:SetJustifyV("TOP")
    winnerHistoryTextRef = historyText

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

    msChangesEditBox:SetScript("OnTextChanged", function(self)
        local availableWidth = msChangesBg:GetWidth() - 40
        if availableWidth < 50 then
            availableWidth = 50
        end

        self:SetWidth(availableWidth)

        local textHeight = 20
        if self.GetTextHeight then
            textHeight = self:GetTextHeight()
        end

        if textHeight < 20 then
            textHeight = 20
        end

        self:SetHeight(textHeight + 8)
        msChangesScrollChild:SetWidth(availableWidth)
        msChangesScrollChild:SetHeight(textHeight + 20)
        msChangesScrollFrame:UpdateScrollChildRect()
    end)

    msChangesToggleButton:SetScript("OnClick", function()
        if not isEditingMSChanges then
            SetMSChangesEditMode(true)
            return
        end

        SaveMSChangesText(msChangesEditBox:GetText() or "")
        SetMSChangesEditMode(false)
        RefreshRollUI()
    end)

    msChangesAnnounceButton:SetScript("OnClick", function()
        if isEditingMSChanges then
            SaveMSChangesText(msChangesEditBox:GetText() or "")
            SetMSChangesEditMode(false)
        end

        AnnounceMSChanges()
    end)

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

    itemButton:SetScript("OnEnter", function(self)
        if currentItemLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(currentItemLink)
            GameTooltip:Show()
        end
    end)

    itemButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    itemButton:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            ClearSelectedItem()
            itemIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            return
        end

        if CursorHasItem() then
            local cursorType, itemID, itemLink = GetCursorInfo()
            if cursorType == "item" and itemLink then
                SetSelectedItem(itemLink)
                if currentItemTexture then
                    itemIcon:SetTexture(currentItemTexture)
                end
            end
            ClearCursor()
        else
            itemEditBox:SetFocus()
            itemEditBox:HighlightText()
        end
    end)

    leftHistoryButton:SetScript("OnClick", function()
        EnsureSavedVariables()
        NormalizeRollHistoryViewIndex()

        if #RTRollManagerSave.rollHistory == 0 then
            return
        end

        if IsViewingCurrentRollPage() then
            rollHistoryViewIndex = 1
        elseif rollHistoryViewIndex < #RTRollManagerSave.rollHistory then
            rollHistoryViewIndex = rollHistoryViewIndex + 1
        end

        RefreshRollUI()
    end)

    rightHistoryButton:SetScript("OnClick", function()
        EnsureSavedVariables()
        NormalizeRollHistoryViewIndex()

        if #RTRollManagerSave.rollHistory == 0 then
            return
        end

        if rollHistoryViewIndex > 1 then
            rollHistoryViewIndex = rollHistoryViewIndex - 1
        else
            rollHistoryViewIndex = 0
        end

        RefreshRollUI()
    end)

    announceWinnersButton:SetScript("OnClick", function()
        if isCountdownActive then
            return
        end

        if not IsViewingCurrentRollPage() then
            return
        end

        if #currentWinnerNames == 0 then
            return
        end

        if currentSessionAnnounced then
            return
        end

        AnnounceWinners()
    end)

    RT_RefreshRollButtons = function()
        local hasSelectedItem = currentItemLink ~= nil and currentItemLink ~= ""
        local isViewingCurrentPage = IsViewingCurrentRollPage()
        local hasCurrentRolls = #rollEntries > 0
        local hasCurrentWinners = #currentWinnerNames > 0

        local canAnnounceCurrentSession = (not isCountdownActive)
            and isViewingCurrentPage
            and hasCurrentRolls
            and hasCurrentWinners
            and (not currentSessionAnnounced)

        SetButtonEnabled(msButton, hasSelectedItem)
        SetButtonEnabled(osButton, hasSelectedItem)
        SetButtonEnabled(finishEarlyButton, isCountdownActive)
        SetButtonEnabled(announceWinnersButton, canAnnounceCurrentSession)
        SetButtonEnabled(msChangesToggleButton, true)
        SetButtonEnabled(msChangesAnnounceButton, GetMSChangesText() ~= "")

        if isViewingCurrentPage then
            announceWinnersButton:SetText("Announce Winners")
        else
            announceWinnersButton:SetText("History View")
        end

    end

    RT_RefreshRollUI = function()
        if not f:IsVisible() then
            return
        end

        EnsureSavedVariables()
        NormalizeRollHistoryViewIndex()

        local displayData = GetDisplayedRollData()
        local displayedRolls = displayData.rolls or {}
        local displayedItemLink = displayData.itemLink
        local displayedWinners = displayData.winnerNames or {}

        local historyCount = RTRollManagerSave and #RTRollManagerSave.rollHistory or 0
        local totalPages = historyCount
        local pageNumber = totalPages + 1

        if not IsViewingCurrentRollPage() then
            pageNumber = (totalPages - rollHistoryViewIndex) + 1
        end

        logLabel:SetText("#" .. pageNumber .. " Roll List:")

        local lines = {}
        local index = 1
        while index <= #displayedRolls do
            local entry = displayedRolls[index]
            local prefix = "  "

            local winnerIndex = 1
            while winnerIndex <= #displayedWinners do
                if displayedWinners[winnerIndex] == entry.name then
                    prefix = "* "
                    break
                end
                winnerIndex = winnerIndex + 1
            end

            lines[#lines + 1] = string.format("%s%s - %d", prefix, entry.name, entry.roll)
            index = index + 1
        end

        if #lines == 0 then
            rollText:SetText("No rolls yet.")
        else
            rollText:SetText(table.concat(lines, "\n"))
        end

        local historyLines = {}
        local winnerHistory = RTRollManagerSave and RTRollManagerSave.winnerHistory or {}
        local historyIndex = 1

        while historyIndex <= #winnerHistory do
            local entry = winnerHistory[historyIndex]
            historyLines[#historyLines + 1] = string.format(
                "%s - %s - %s - %d",
                entry.rollType or "-",
                entry.itemLink or "-",
                entry.winnerName or "-",
                entry.rollValue or 0
            )
            historyIndex = historyIndex + 1
        end

        if #historyLines == 0 then
            historyText:SetText("No winners yet.")
        else
            historyText:SetText(table.concat(historyLines, "\n"))
        end

        local logAvailableWidth = logBg:GetWidth() - 40
        if logAvailableWidth < 50 then
            logAvailableWidth = 50
        end

        scrollChild:SetWidth(logAvailableWidth)
        rollText:SetWidth(logAvailableWidth)
        scrollChild:SetHeight(rollText:GetStringHeight() + 20)
        scrollFrame:UpdateScrollChildRect()

        local historyAvailableWidth = historyBg:GetWidth() - 40
        if historyAvailableWidth < 50 then
            historyAvailableWidth = 50
        end

        historyScrollChild:SetWidth(historyAvailableWidth)
        historyText:SetWidth(historyAvailableWidth)
        historyScrollChild:SetHeight(historyText:GetStringHeight() + 20)
        historyScrollFrame:UpdateScrollChildRect()

        if msChangesEditBoxRef then
            if not isEditingMSChanges then
                local savedMSChangesText = GetMSChangesText()
                if msChangesEditBoxRef:GetText() ~= savedMSChangesText then
                    msChangesEditBoxRef:SetText(savedMSChangesText)
                end
            end

            local msChangesAvailableWidth = msChangesBg:GetWidth() - 40
            if msChangesAvailableWidth < 50 then
                msChangesAvailableWidth = 50
            end

            msChangesEditBoxRef:SetWidth(msChangesAvailableWidth)

            local msChangesTextHeight = 20
            if msChangesEditBoxRef.GetTextHeight then
                msChangesTextHeight = msChangesEditBoxRef:GetTextHeight()
            end

            if msChangesTextHeight < 20 then
                msChangesTextHeight = 20
            end

            msChangesEditBoxRef:SetHeight(msChangesTextHeight + 8)
            msChangesScrollChild:SetWidth(msChangesAvailableWidth)
            msChangesScrollChild:SetHeight(msChangesTextHeight + 20)
            msChangesScrollFrame:UpdateScrollChildRect()
        end

        if currentItemLink then
            itemEditBox:SetText(currentItemLink)
        else
            itemEditBox:SetText("")
        end

        winnerCountButton:SetText(tostring(currentWinnerCount))

        if currentItemTexture then
            itemIcon:SetTexture(currentItemTexture)
        else
            itemIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end

        local displayedWinnerText = BuildDisplayedWinnerText(displayData)
        winnerLabel:SetText(displayedWinnerText or "")

        if displayedItemLink and displayedItemLink ~= "-" then
            rollHeaderLinkText:SetText(displayedItemLink)
        else
            rollHeaderLinkText:SetText("")
        end

        timerLabel:SetText("Countdown:")

        if isCountdownActive then
            if countdownEditBox:HasFocus() then
                countdownEditBox:ClearFocus()
            end

            if countdownBgRef then
                countdownBgRef:Hide()
            end

            if countdownTextRef then
                countdownTextRef:SetText(tostring(GetCountdownRemaining()))
                countdownTextRef:Show()
            end
        else
            if countdownBgRef then
                countdownBgRef:Show()
            end

            if countdownTextRef then
                countdownTextRef:Hide()
            end

            countdownEditBox:SetText(tostring(RTRollManagerSave.countdownDuration or 20))
            countdownEditBox:SetTextColor(1, 1, 1)
        end

        local hasRollHistory = RTRollManagerSave and #RTRollManagerSave.rollHistory > 0
        local canGoToOlder = false
        local canGoToNewer = false

        if hasRollHistory then
            if IsViewingCurrentRollPage() then
                canGoToOlder = true
                canGoToNewer = false
            else
                canGoToNewer = true
                canGoToOlder = rollHistoryViewIndex < #RTRollManagerSave.rollHistory
            end
        end

        SetButtonEnabled(leftHistoryButton, canGoToOlder)
        SetButtonEnabled(rightHistoryButton, canGoToNewer)

        if RT_RefreshRollButtons then
            RT_RefreshRollButtons()
        end
    end

    msButton:SetScript("OnClick", function()
        StartRollSession("MS")
    end)

    osButton:SetScript("OnClick", function()
        StartRollSession("OS")
    end)

    finishEarlyButton:SetScript("OnClick", function()
        FinishEarly()
    end)

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    closeBtn:SetSize(100, 28)
    closeBtn:SetPoint("BOTTOMRIGHT", -18, 12)
    closeBtn:SetText("Close")
    if S then
        S:HandleButton(closeBtn)
    end
    closeBtn:SetScript("OnClick", onClose)

    local clearWinnersSavedButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearWinnersSavedButton:SetSize(170, 28)
    clearWinnersSavedButton:SetPoint("BOTTOMLEFT", 18, 12)
    clearWinnersSavedButton:SetText("Clear Saved Winners")
    if S then
        S:HandleButton(clearWinnersSavedButton)
    end

    local clearRollsSavedButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearRollsSavedButton:SetSize(150, 28)
    clearRollsSavedButton:SetPoint("LEFT", clearWinnersSavedButton, "RIGHT", 10, 0)
    clearRollsSavedButton:SetText("Clear Saved Rolls")
    if S then
        S:HandleButton(clearRollsSavedButton)
    end

    clearRollsSavedButton:SetScript("OnClick", function()
        ClearRollHistory()
    end)

    clearWinnersSavedButton:SetScript("OnClick", function()
        ClearWinnerHistory()
    end)

    f:SetScript("OnShow", function()
        EnsureSavedVariables()
        NormalizeRollHistoryViewIndex()
        countdownEditBox:SetText(tostring(RTRollManagerSave.countdownDuration or 20))

        if msChangesEditBoxRef then
            msChangesEditBoxRef:SetText(GetMSChangesText())
        end

        SetMSChangesEditMode(false)
        RefreshRollUI()
    end)

    return f
end