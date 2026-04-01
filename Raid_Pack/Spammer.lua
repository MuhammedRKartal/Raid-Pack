-- Spammer.lua

local addonName = ...
local addonTable = select(2, ...)

------------------------------------------------------------
-- STATE / REFS / CONSTANTS
------------------------------------------------------------

local STATE = {
    isSpamming = false,
    selectedPresetName = nil,
    saveFeedbackResetAt = 0,
    uiUpdateAccumulator = 0,
}

local UI = {
    msgEditBox = nil,
    charCountText = nil,
    startBtn = nil,
    msgLabel = nil,

    presetDropdownButton = nil,
    presetDropdownText = nil,
    renamePresetBtn = nil,
    renamePresetBG = nil,
    renamePresetEditBox = nil,
    deletePresetBtn = nil,
    savePresetBtn = nil,

    channelRows = {},
}

local CONST = {
    CREATE_NEW_PRESET_LABEL = "Create New",
    CREATE_NEW_PRESET_BASE_NAME = "New Message",
    DEFAULT_PRESET_NAME = "Weakauras Discord",
    DEFAULT_PRESET_MESSAGE = "Need a new UI or nice Weakauras to track everything? Come Join the Weakaura Center: https://discord.gg/7E6jAPsJD9",
    PRESET_NAME_MAX_LENGTH = 21,
    MAX_MESSAGE_LENGTH = 255,
    UI_UPDATE_INTERVAL = 0.1,
    DEFAULT_INTERVALS = {
        ["General"] = "31",
        ["Trade"] = "23",
        ["World"] = "61",
        ["YELL"] = "41",
    },
    DEFAULT_ENABLED_CHANNELS = {
        ["General"] = true,
        ["Trade"] = true,
        ["World"] = true,
        ["YELL"] = true,
    },
    CHANNEL_POOL = {
        { name = "General", chatType = "CHANNEL" },
        { name = "Trade", chatType = "CHANNEL" },
        { name = "World", chatType = "CHANNEL" },
        { name = "YELL", chatType = "YELL" },
    },
}

CONST.DEFAULT_PRESET_READONLY_TEXT = CONST.DEFAULT_PRESET_MESSAGE .. "\n(Default preset is read-only)"
CONST.SPAMMER_PRESET_DELETE_POPUP = addonName .. "SpammerPresetDeletePopup"

local eventFrame = CreateFrame("Frame")
local loader = CreateFrame("Frame")

local GetSelectedPresetName

------------------------------------------------------------
-- PUBLIC STATUS HELPERS
------------------------------------------------------------

function RT_IsSpammerEnabled()
    return STATE.isSpamming
end

------------------------------------------------------------
-- TEXT / TABLE HELPERS
------------------------------------------------------------

local function TrimText(text)
    local result = text or ""
    result = string.gsub(result, "^%s+", "")
    result = string.gsub(result, "%s+$", "")
    return result
end

local function LimitTextLength(text, maxLength)
    local result = text or ""

    if string.len(result) > maxLength then
        result = string.sub(result, 1, maxLength)
    end

    return result
end

local function CapitalizeWords(text)
    local result = tostring(text or "")
    result = string.lower(result)
    result = string.gsub(result, "(%a)([%w']*)", function(firstChar, restChars)
        return string.upper(firstChar) .. restChars
    end)
    return result
end

local function NormalizeChannelName(channelName)
    local result = string.lower(channelName or "")
    result = string.gsub(result, "%s+", "")
    return result
end

local function CopyIntervals(source)
    local result = {}

    for channelName, defaultValue in pairs(CONST.DEFAULT_INTERVALS) do
        local value = defaultValue

        if type(source) == "table" and source[channelName] ~= nil then
            value = tostring(source[channelName])
        end

        result[channelName] = value
    end

    return result
end

local function CopyEnabledChannels(source)
    local result = {}

    for channelName, defaultValue in pairs(CONST.DEFAULT_ENABLED_CHANNELS) do
        local value = defaultValue

        if type(source) == "table" and source[channelName] ~= nil then
            value = source[channelName] and true or false
        end

        result[channelName] = value
    end

    return result
end

local function CopyPresetData(source)
    local result = {
        message = "",
        intervals = CopyIntervals(nil),
        enabledChannels = CopyEnabledChannels(nil),
        order = nil,
        isDefault = false,
        isReadOnly = false,
    }

    if type(source) == "table" then
        result.message = tostring(source.message or "")
        result.intervals = CopyIntervals(source.intervals)
        result.enabledChannels = CopyEnabledChannels(source.enabledChannels)

        if type(source.order) == "number" then
            result.order = source.order
        end

        if source.isDefault == true then
            result.isDefault = true
        end

        if source.isReadOnly == true then
            result.isReadOnly = true
        end
    end

    return result
end

local function BuildDefaultPresetData(source)
    local result = {
        message = CONST.DEFAULT_PRESET_MESSAGE,
        intervals = CopyIntervals(nil),
        enabledChannels = CopyEnabledChannels(nil),
        order = -1,
        isDefault = true,
        isReadOnly = true,
    }

    if type(source) == "table" then
        result.intervals = CopyIntervals(source.intervals)
        result.enabledChannels = CopyEnabledChannels(source.enabledChannels)
    end

    return result
end

------------------------------------------------------------
-- SAVED VARIABLE HELPERS
------------------------------------------------------------

local function GetCharacterKey()
    local characterName = UnitName("player") or "Unknown"
    local realmName = GetRealmName() or "UnknownRealm"
    return tostring(realmName) .. " - " .. tostring(characterName)
end

local function EnsureRootSavedVariables()
    if type(RTSpammerSave) ~= "table" then
        RTSpammerSave = {}
    end

    if type(RTSpammerSave.presets) ~= "table" then
        RTSpammerSave.presets = {}
    end

    if type(RTSpammerSave.characterSettings) ~= "table" then
        RTSpammerSave.characterSettings = {}
    end

    if type(RTSpammerSave.presetOrderCounter) ~= "number" then
        RTSpammerSave.presetOrderCounter = 0
    end
end

local function EnsureCharacterSettings()
    local characterKey = GetCharacterKey()

    if type(RTSpammerSave.characterSettings[characterKey]) ~= "table" then
        RTSpammerSave.characterSettings[characterKey] = {}
    end

    if type(RTSpammerSave.characterSettings[characterKey].activePresetName) ~= "string" then
        RTSpammerSave.characterSettings[characterKey].activePresetName = nil
    end
end

local function NormalizePresets()
    local migratedPresets = {}
    local existingDefaultPreset = nil

    if type(RTSpammerSave.presets[CONST.DEFAULT_PRESET_NAME]) == "table" then
        existingDefaultPreset = RTSpammerSave.presets[CONST.DEFAULT_PRESET_NAME]
    elseif type(RTSpammerSave.current) == "table" then
        existingDefaultPreset = {
            intervals = RTSpammerSave.current.intervals,
            enabledChannels = RTSpammerSave.current.enabledChannels,
        }
    end

    for presetName, presetData in pairs(RTSpammerSave.presets) do
        if type(presetName) == "string" and presetName ~= "" and presetName ~= CONST.DEFAULT_PRESET_NAME then
            local normalizedPresetData = CopyPresetData(presetData)

            normalizedPresetData.isDefault = false
            normalizedPresetData.isReadOnly = false

            if type(normalizedPresetData.order) ~= "number" then
                RTSpammerSave.presetOrderCounter = RTSpammerSave.presetOrderCounter + 1
                normalizedPresetData.order = RTSpammerSave.presetOrderCounter
            end

            if type(presetData) == "table" and type(presetData.intervals) ~= "table" and type(RTSpammerSave.current) == "table" then
                normalizedPresetData.intervals = CopyIntervals(RTSpammerSave.current.intervals)
                normalizedPresetData.enabledChannels = CopyEnabledChannels(RTSpammerSave.current.enabledChannels)
            end

            migratedPresets[presetName] = normalizedPresetData
        end
    end

    migratedPresets[CONST.DEFAULT_PRESET_NAME] = BuildDefaultPresetData(existingDefaultPreset)
    RTSpammerSave.presets = migratedPresets
    RTSpammerSave.current = nil
end

local function EnsureDefaultActivePreset()
    local characterKey = GetCharacterKey()
    local characterData = RTSpammerSave.characterSettings[characterKey]
    local activePresetName = characterData.activePresetName

    if activePresetName == nil
        and type(RTSpammerSave.activePresetName) == "string"
        and RTSpammerSave.activePresetName ~= ""
        and RTSpammerSave.presets[RTSpammerSave.activePresetName] then
        characterData.activePresetName = RTSpammerSave.activePresetName
        activePresetName = characterData.activePresetName
    end

    if type(activePresetName) ~= "string"
        or activePresetName == ""
        or not RTSpammerSave.presets[activePresetName] then
        characterData.activePresetName = CONST.DEFAULT_PRESET_NAME
    end

    RTSpammerSave.activePresetName = nil
end

local function EnsureSavedVariables()
    EnsureRootSavedVariables()
    EnsureCharacterSettings()
    NormalizePresets()
    EnsureDefaultActivePreset()
end

local function GetPresetData(presetName)
    EnsureSavedVariables()

    if type(presetName) ~= "string" or presetName == "" then
        return nil
    end

    return RTSpammerSave.presets[presetName]
end

local function IsDefaultPreset(presetName)
    local presetData = GetPresetData(presetName)
    return presetData ~= nil and presetData.isDefault == true
end

local function IsPresetReadOnly(presetName)
    local presetData = GetPresetData(presetName)
    return presetData ~= nil and presetData.isReadOnly == true
end

local function CanRenamePreset(presetName)
    if type(presetName) ~= "string" or presetName == "" or presetName == CONST.CREATE_NEW_PRESET_LABEL then
        return false
    end

    return GetPresetData(presetName) ~= nil and not IsPresetReadOnly(presetName)
end

local function CanDeletePreset(presetName)
    if type(presetName) ~= "string" or presetName == "" or presetName == CONST.CREATE_NEW_PRESET_LABEL then
        return false
    end

    return GetPresetData(presetName) ~= nil and not IsDefaultPreset(presetName)
end

local function CanSavePreset(presetName)
    if type(presetName) ~= "string" or presetName == "" or presetName == CONST.CREATE_NEW_PRESET_LABEL then
        return false
    end

    return GetPresetData(presetName) ~= nil and not IsPresetReadOnly(presetName)
end

local function GetCharacterActivePresetName()
    EnsureSavedVariables()

    local characterKey = GetCharacterKey()
    local presetName = RTSpammerSave.characterSettings[characterKey].activePresetName

    if type(presetName) ~= "string"
        or presetName == ""
        or not RTSpammerSave.presets[presetName] then
        return CONST.DEFAULT_PRESET_NAME
    end

    return presetName
end

local function SetCharacterActivePresetName(presetName)
    EnsureSavedVariables()

    local characterKey = GetCharacterKey()

    if type(presetName) == "string" and presetName ~= "" and RTSpammerSave.presets[presetName] then
        RTSpammerSave.characterSettings[characterKey].activePresetName = presetName
    else
        RTSpammerSave.characterSettings[characterKey].activePresetName = CONST.DEFAULT_PRESET_NAME
    end
end

------------------------------------------------------------
-- SPAM STATE HELPERS
------------------------------------------------------------

local function SetCooldownText(row, text)
    if row and row.cdText then
        if row.lastCooldownText ~= text then
            row.cdText:SetText(text)
            row.lastCooldownText = text
        end
    end
end

local function StopSpamming(resetCooldowns)
    STATE.isSpamming = false

    if RefreshStatusOverlay then
        RefreshStatusOverlay()
    end

    if UI.startBtn then
        UI.startBtn:SetText("Start Spamming")
    end

    if resetCooldowns then
        for _, row in ipairs(UI.channelRows) do
            row.nextSend = 0
            SetCooldownText(row, "|cff888888Ready|r")
        end
    end
end

local function GetSavedMessageForCurrentSelection()
    local presetName = GetSelectedPresetName()
    local presetData = GetPresetData(presetName)

    if not presetData then
        return ""
    end

    if IsPresetReadOnly(presetName) then
        return CONST.DEFAULT_PRESET_READONLY_TEXT
    end

    return presetData.message or ""
end

local function GetMessageToSend()
    local presetName = GetCharacterActivePresetName()
    local presetData = GetPresetData(presetName)

    if not presetData then
        return ""
    end

    return presetData.message or ""
end

------------------------------------------------------------
-- LINK HELPERS
------------------------------------------------------------

local isLinkHookInstalled = false
local originalChatEdit_InsertLink = nil
local lastActiveLinkTarget = nil

local function ClearMessageBoxAsLinkTarget()
    if lastActiveLinkTarget == UI.msgEditBox then
        lastActiveLinkTarget = nil
    end
end

local function SetMessageBoxAsLinkTarget()
    local presetName = GetSelectedPresetName()

    if not UI.msgEditBox or IsPresetReadOnly(presetName) then
        lastActiveLinkTarget = nil
        return
    end

    lastActiveLinkTarget = UI.msgEditBox
end

local function IsMessageBoxActive()
    if not UI.msgEditBox then
        return false
    end

    if not UI.msgEditBox:IsShown() then
        return false
    end

    return lastActiveLinkTarget == UI.msgEditBox or UI.msgEditBox:HasFocus()
end

local function InsertLinkIntoMessageBox(link)
    local presetName = GetSelectedPresetName()

    if IsPresetReadOnly(presetName) or not link or link == "" then
        return false
    end

    if not UI.msgEditBox or not UI.msgEditBox:IsShown() then
        return false
    end

    if not IsMessageBoxActive() then
        return false
    end

    local currentText = UI.msgEditBox:GetText() or ""
    local currentLength = string.len(currentText)
    local linkLength = string.len(link)
    local maxLength = CONST.MAX_MESSAGE_LENGTH

    if currentLength >= maxLength then
        UI.msgEditBox:SetFocus()
        return true
    end

    if currentLength + linkLength > maxLength then
        UI.msgEditBox:SetFocus()
        return true
    end

    UI.msgEditBox:SetFocus()
    UI.msgEditBox:Insert(link)

    SetMessageBoxAsLinkTarget()
    UpdateCharacterCount()
    UpdateMessageDirtyState()

    return true
end

local function HookLinkInsertion()
    if isLinkHookInstalled then
        return
    end

    isLinkHookInstalled = true
    originalChatEdit_InsertLink = ChatEdit_InsertLink

    ChatEdit_InsertLink = function(link)
        if InsertLinkIntoMessageBox(link) then
            return true
        end

        if originalChatEdit_InsertLink then
            return originalChatEdit_InsertLink(link)
        end

        return false
    end
end

HookLinkInsertion()

------------------------------------------------------------
-- UI HELPERS
------------------------------------------------------------

local function SetSaveButtonVisual(textValue, redValue, greenValue, blueValue)
    if not UI.savePresetBtn then
        return
    end

    UI.savePresetBtn:SetText(textValue)

    local buttonText = UI.savePresetBtn:GetFontString()
    if buttonText then
        buttonText:SetTextColor(redValue, greenValue, blueValue)
    end
end

local function ShowSavedFeedback()
    SetSaveButtonVisual("Saved", 0, 1, 0)
    STATE.saveFeedbackResetAt = GetTime() + 3
end

local function SetMessageEditBoxReadOnly(isReadOnly)
    if not UI.msgEditBox then
        return
    end

    if isReadOnly then
        ClearMessageBoxAsLinkTarget()
        UI.msgEditBox:ClearFocus()
        UI.msgEditBox:EnableMouse(false)
        if UI.msgEditBox.EnableKeyboard then
            UI.msgEditBox:EnableKeyboard(false)
        end
        UI.msgEditBox:SetTextColor(0.6, 0.6, 0.6)
    else
        UI.msgEditBox:EnableMouse(true)
        if UI.msgEditBox.EnableKeyboard then
            UI.msgEditBox:EnableKeyboard(true)
        end
        UI.msgEditBox:SetTextColor(1, 1, 1)
    end
end

local function GetRawMessageLength(text)
    local safeText = tostring(text or "")
    return string.len(safeText)
end

local function UpdateCharacterCount()
    if not UI.charCountText or not UI.msgEditBox then
        return
    end

    local messageText = UI.msgEditBox:GetText() or ""
    local rawLength = GetRawMessageLength(messageText)

    UI.charCountText:SetText(string.format("Chars: %d/%d", rawLength, CONST.MAX_MESSAGE_LENGTH))
end

local function UpdateMessageDirtyState()
    if not UI.msgLabel then
        return
    end

    local presetName = GetSelectedPresetName()

    if IsPresetReadOnly(presetName) then
        UI.msgLabel:SetText("Message to Spam:")
        return
    end

    local currentMessage = ""
    local savedMessage = GetSavedMessageForCurrentSelection()

    if UI.msgEditBox then
        currentMessage = UI.msgEditBox:GetText() or ""
    end

    if currentMessage ~= savedMessage then
        UI.msgLabel:SetText("Message to Spam |cffffcc00(Not Saved)|r")
        if UI.msgEditBox then
            UI.msgEditBox:SetTextColor(0, 1, 0)
        end
    else
        UI.msgLabel:SetText("Message to Spam:")
        if UI.msgEditBox then
            UI.msgEditBox:SetTextColor(1, 1, 1)
        end
    end
end

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

------------------------------------------------------------
-- CHANNEL HELPERS
------------------------------------------------------------

local function FindJoinedChannelByMatcher(matcher)
    local index = 1

    while true do
        local channelId, channelName = GetChannelName(index)

        if not channelId or channelId <= 0 then
            break
        end

        if type(channelName) == "string" and channelName ~= "" and matcher(channelName, channelId) then
            return channelId, channelName
        end

        index = index + 1
    end

    return nil, nil
end

local function GetFixedChannelInfo(channelKey)
    local normalizedKey = string.lower(tostring(channelKey or ""))

    local function IsMatch(name)
        local normalizedName = string.lower(tostring(name or "")):gsub("%s+", "")

        if normalizedKey == "world" then
            return string.find(normalizedName, "world", 1, true) ~= nil
                or string.find(normalizedName, "global", 1, true) ~= nil
        end

        if normalizedKey == "trade" then
            return string.find(normalizedName, "trade", 1, true) ~= nil
        end

        if normalizedKey == "lfg" then
            return string.find(normalizedName, "lookingforgroup", 1, true) ~= nil
                or normalizedName == "lfg"
        end

        return string.find(normalizedName, normalizedKey, 1, true) ~= nil
    end

    local channelList = { GetChannelList() }

    for index = 1, #channelList, 2 do
        local channelId = channelList[index]
        local channelName = channelList[index + 1]

        if type(channelId) == "number" and type(channelName) == "string" and IsMatch(channelName) then
            return channelId, channelName
        end
    end

    return nil, nil
end

local function RefreshAvailableChannels()
    local visibleCount = 0

    for _, row in ipairs(UI.channelRows) do
        local isAvailable = false
        local displayName = row.config.name

        if row.config.chatType == "YELL" then
            isAvailable = true
            displayName = CapitalizeWords(row.config.name)
        else
            local channelIndex, channelName = GetFixedChannelInfo(row.config.name)

            if channelIndex and channelIndex > 0 then
                isAvailable = true
                displayName = CapitalizeWords(channelName) .. " (" .. tostring(channelIndex) .. ")"
            end
        end

        if isAvailable then
            visibleCount = visibleCount + 1
            row:SetPoint("TOPLEFT", 25, -206 - ((visibleCount - 1) * 32))
            row.text:SetText(displayName)
            row:Show()
        else
            row:Hide()
        end
    end
end

local RefreshPresetActionButtons

local function RefreshChannelsAndPreserveUI()
    if not UI.channelRows or #UI.channelRows == 0 then
        return
    end

    RefreshAvailableChannels()

    if UI.startBtn and RefreshStatusOverlay then
        RefreshStatusOverlay()
    end

    if UI.savePresetBtn then
        RefreshPresetActionButtons()
    end

    if UI.msgEditBox then
        UpdateMessageDirtyState()
    end
end

------------------------------------------------------------
-- PRESET <-> UI HELPERS
------------------------------------------------------------

GetSelectedPresetName = function()
    local presetName = STATE.selectedPresetName

    if type(presetName) == "string"
        and presetName ~= ""
        and presetName ~= CONST.CREATE_NEW_PRESET_LABEL
        and GetPresetData(presetName) then
        return presetName
    end

    return GetCharacterActivePresetName()
end

local function GetSortedPresetNames()
    EnsureSavedVariables()

    local presetNames = {}

    for presetName in pairs(RTSpammerSave.presets) do
        presetNames[#presetNames + 1] = presetName
    end

    table.sort(presetNames, function(leftValue, rightValue)
        local leftPreset = GetPresetData(leftValue)
        local rightPreset = GetPresetData(rightValue)
        local leftOrder = 0
        local rightOrder = 0

        if leftPreset and type(leftPreset.order) == "number" then
            leftOrder = leftPreset.order
        end

        if rightPreset and type(rightPreset.order) == "number" then
            rightOrder = rightPreset.order
        end

        if leftOrder ~= rightOrder then
            return leftOrder > rightOrder
        end

        return tostring(leftValue) < tostring(rightValue)
    end)

    local result = { CONST.CREATE_NEW_PRESET_LABEL }

    for _, presetName in ipairs(presetNames) do
        result[#result + 1] = presetName
    end

    return result
end

local function GetUniquePresetName(baseName)
    EnsureSavedVariables()

    local trimmedBaseName = LimitTextLength(TrimText(baseName or ""), CONST.PRESET_NAME_MAX_LENGTH)

    if trimmedBaseName == "" then
        return ""
    end

    if not RTSpammerSave.presets[trimmedBaseName] then
        return trimmedBaseName
    end

    local copySuffix = " (copy)"
    local indexedPrefix = " (copy "

    local candidateName = LimitTextLength(trimmedBaseName, CONST.PRESET_NAME_MAX_LENGTH - string.len(copySuffix)) .. copySuffix
    if not RTSpammerSave.presets[candidateName] then
        return candidateName
    end

    local copyIndex = 2
    while true do
        local suffix = indexedPrefix .. tostring(copyIndex) .. ")"
        local maxBaseLength = CONST.PRESET_NAME_MAX_LENGTH - string.len(suffix)
        local basePart = trimmedBaseName

        if maxBaseLength < 1 then
            maxBaseLength = 1
        end

        basePart = LimitTextLength(basePart, maxBaseLength)
        candidateName = basePart .. suffix

        if not RTSpammerSave.presets[candidateName] then
            return candidateName
        end

        copyIndex = copyIndex + 1
    end
end

local function GetNextNewPresetName()
    EnsureSavedVariables()

    local newIndex = 1

    while true do
        local candidateName = CONST.CREATE_NEW_PRESET_BASE_NAME .. " (" .. tostring(newIndex) .. ")"

        if string.len(candidateName) > CONST.PRESET_NAME_MAX_LENGTH then
            candidateName = LimitTextLength(candidateName, CONST.PRESET_NAME_MAX_LENGTH)
        end

        if not RTSpammerSave.presets[candidateName] then
            return candidateName
        end

        newIndex = newIndex + 1
    end
end

local function ApplyPresetToUI(presetData)
    if not presetData then
        return
    end

    for _, row in ipairs(UI.channelRows) do
        local channelName = row.config.name
        row.timer:SetText(tostring(presetData.intervals[channelName] or CONST.DEFAULT_INTERVALS[channelName] or "30"))
        row.check:SetChecked(presetData.enabledChannels[channelName] and true or false)
    end

    if UI.msgEditBox then
        if presetData.isReadOnly == true then
            UI.msgEditBox:SetText(CONST.DEFAULT_PRESET_READONLY_TEXT)
        else
            UI.msgEditBox:SetText(presetData.message or "")
        end
    end

    SetMessageEditBoxReadOnly(presetData.isReadOnly == true)
    UpdateCharacterCount()
    UpdateMessageDirtyState()
end

local function ReadPresetDataFromUI(basePresetData)
    local result = CopyPresetData(basePresetData)

    if UI.msgEditBox and not result.isReadOnly then
        result.message = UI.msgEditBox:GetText() or ""
    end

    for _, row in ipairs(UI.channelRows) do
        result.intervals[row.config.name] = row.timer:GetText() or CONST.DEFAULT_INTERVALS[row.config.name]
        result.enabledChannels[row.config.name] = row.check:GetChecked() and true or false
    end

    return result
end

local function IsPresetDirty()
    local presetName = GetSelectedPresetName()
    local presetData = GetPresetData(presetName)

    if not presetData or not CanSavePreset(presetName) then
        return false
    end

    local currentPresetData = ReadPresetDataFromUI(presetData)

    local savedMessage = tostring(presetData.message or "")
    local currentMessage = tostring(currentPresetData.message or "")

    if currentMessage ~= savedMessage then
        return true
    end

    for channelName, savedInterval in pairs(presetData.intervals or {}) do
        local currentInterval = tostring((currentPresetData.intervals or {})[channelName] or "")
        if currentInterval ~= tostring(savedInterval or "") then
            return true
        end
    end

    for channelName, currentInterval in pairs((currentPresetData.intervals or {})) do
        local savedInterval = tostring((presetData.intervals or {})[channelName] or "")
        if tostring(currentInterval or "") ~= savedInterval then
            return true
        end
    end

    for channelName, savedEnabled in pairs(presetData.enabledChannels or {}) do
        local currentEnabled = ((currentPresetData.enabledChannels or {})[channelName] == true)
        if currentEnabled ~= (savedEnabled == true) then
            return true
        end
    end

    for channelName, currentEnabled in pairs((currentPresetData.enabledChannels or {})) do
        local savedEnabled = ((presetData.enabledChannels or {})[channelName] == true)
        if (currentEnabled == true) ~= savedEnabled then
            return true
        end
    end

    return false
end

RefreshPresetActionButtons = function()
    local presetName = STATE.selectedPresetName
    local canRename = CanRenamePreset(presetName)
    local canDelete = CanDeletePreset(presetName)
    local canSave = CanSavePreset(presetName)
    local isDirty = false

    if canSave then
        isDirty = IsPresetDirty()
    end

    if UI.savePresetBtn then
        if canSave and isDirty then
            UI.savePresetBtn:Enable()
            SetSaveButtonVisual("Save", 1, 0.82, 0)
        else
            SetSaveButtonVisual("Save", 0.5, 0.5, 0.5)
            UI.savePresetBtn:Disable()
        end
    end

    if UI.renamePresetBtn then
        if canRename then
            UI.renamePresetBtn:Enable()
        else
            UI.renamePresetBtn:Disable()
        end
    end

    if UI.deletePresetBtn then
        if canDelete then
            UI.deletePresetBtn:Enable()
        else
            UI.deletePresetBtn:Disable()
        end
    end
end

local function SetSelectedPresetName(presetName)
    STATE.selectedPresetName = presetName

    if presetName and presetName ~= "" and presetName ~= CONST.CREATE_NEW_PRESET_LABEL and GetPresetData(presetName) then
        SetCharacterActivePresetName(presetName)
    end

    if UI.presetDropdownText then
        if presetName and presetName ~= "" then
            UI.presetDropdownText:SetText(presetName)
        else
            UI.presetDropdownText:SetText("Select Preset")
        end
    end

    RefreshPresetActionButtons()
    UpdateMessageDirtyState()
end

local function SaveActivePreset()
    EnsureSavedVariables()

    local presetName = GetSelectedPresetName()
    local presetData = GetPresetData(presetName)

    if not CanSavePreset(presetName) or not presetData then
        return
    end

    local updatedPresetData = ReadPresetDataFromUI(presetData)
    updatedPresetData.order = presetData.order
    updatedPresetData.isDefault = false
    updatedPresetData.isReadOnly = false

    RTSpammerSave.presets[presetName] = updatedPresetData
    SetCharacterActivePresetName(presetName)

    UpdateMessageDirtyState()
    RefreshPresetActionButtons()
end

local function SaveSelectedPresetSettingsFromUI()
    EnsureSavedVariables()

    local presetName = GetSelectedPresetName()
    local presetData = GetPresetData(presetName)

    if not presetData then
        return
    end

    if IsDefaultPreset(presetName) then
        local updatedPresetData = CopyPresetData(presetData)

        for _, row in ipairs(UI.channelRows) do
            updatedPresetData.intervals[row.config.name] = row.timer:GetText() or CONST.DEFAULT_INTERVALS[row.config.name]
            updatedPresetData.enabledChannels[row.config.name] = row.check:GetChecked() and true or false
        end

        updatedPresetData.message = CONST.DEFAULT_PRESET_MESSAGE
        updatedPresetData.order = -1
        updatedPresetData.isDefault = true
        updatedPresetData.isReadOnly = true

        RTSpammerSave.presets[presetName] = updatedPresetData
        return
    end

    if not CanSavePreset(presetName) then
        return
    end

    SaveActivePreset()
end

------------------------------------------------------------
-- RENAME FLOW
------------------------------------------------------------

local function StopRenameMode()
    if UI.presetDropdownButton then
        UI.presetDropdownButton:Show()
    end

    if UI.renamePresetBG then
        UI.renamePresetBG:Hide()
    end

    if UI.renamePresetEditBox then
        UI.renamePresetEditBox:Hide()
        UI.renamePresetEditBox:ClearFocus()
    end

    if UI.renamePresetBtn then
        UI.renamePresetBtn:SetText("Rename")
        UI.renamePresetBtn.isRenaming = false
    end
end

local function GetMostRecentPresetNameExcluding(excludedPresetName)
    EnsureSavedVariables()

    local selectedPresetName = nil
    local selectedOrder = -math.huge

    for presetName, presetData in pairs(RTSpammerSave.presets or {}) do
        if presetName ~= excludedPresetName
            and presetName ~= CONST.DEFAULT_PRESET_NAME
            and type(presetData) == "table"
            and type(presetData.order) == "number" then
            if presetData.order > selectedOrder then
                selectedOrder = presetData.order
                selectedPresetName = presetName
            end
        end
    end

    if selectedPresetName and RTSpammerSave.presets[selectedPresetName] then
        return selectedPresetName
    end

    return CONST.DEFAULT_PRESET_NAME
end

local function CreateNewPreset()
    EnsureSavedVariables()
    StopSpamming(false)

    local presetName = GetNextNewPresetName()

    RTSpammerSave.presetOrderCounter = (RTSpammerSave.presetOrderCounter or 0) + 1

    local newPresetData = {
        message = "",
        intervals = CopyIntervals(nil),
        enabledChannels = CopyEnabledChannels(nil),
        order = RTSpammerSave.presetOrderCounter,
        isDefault = false,
        isReadOnly = false,
    }

    RTSpammerSave.presets[presetName] = newPresetData

    SetCharacterActivePresetName(presetName)
    SetSelectedPresetName(presetName)
    StopRenameMode()
    ApplyPresetToUI(RTSpammerSave.presets[presetName])
    RefreshPresetActionButtons()
end

local function LoadPreset(presetName)
    if not presetName or presetName == "" then
        return
    end

    if presetName == CONST.CREATE_NEW_PRESET_LABEL then
        CreateNewPreset()
        return
    end

    EnsureSavedVariables()

    local presetData = GetPresetData(presetName)
    if not presetData then
        return
    end

    StopSpamming(false)
    SetCharacterActivePresetName(presetName)
    SetSelectedPresetName(presetName)
    StopRenameMode()
    ApplyPresetToUI(presetData)
end

local function DeletePreset(presetName)
    if not CanDeletePreset(presetName) then
        return
    end

    EnsureSavedVariables()
    StopSpamming(false)

    RTSpammerSave.presets[presetName] = nil

    local fallbackPresetName = GetMostRecentPresetNameExcluding(presetName)
    local characterKey = GetCharacterKey()

    if RTSpammerSave.characterSettings
        and RTSpammerSave.characterSettings[characterKey] then
        RTSpammerSave.characterSettings[characterKey].activePresetName = fallbackPresetName
    end

    SetCharacterActivePresetName(fallbackPresetName)
    SetSelectedPresetName(fallbackPresetName)
    StopRenameMode()
    ApplyPresetToUI(GetPresetData(fallbackPresetName))
    RefreshPresetActionButtons()
end

StaticPopupDialogs[CONST.SPAMMER_PRESET_DELETE_POPUP] = {
    text = 'Are you sure you want to delete "%s"?',
    button1 = "Yes",
    button2 = "No",
    OnAccept = function(self)
        local presetName = self.data
        DeletePreset(presetName)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function StartRenameMode()
    local presetName = GetSelectedPresetName()
    if not CanRenamePreset(presetName) then
        return
    end

    if UI.presetDropdownButton then
        UI.presetDropdownButton:Hide()
    end

    if UI.renamePresetBG then
        UI.renamePresetBG:Show()
    end

    if UI.renamePresetEditBox then
        UI.renamePresetEditBox:Show()
        UI.renamePresetEditBox:SetText(presetName)
        UI.renamePresetEditBox:SetFocus()
        UI.renamePresetEditBox:HighlightText()
    end

    if UI.renamePresetBtn then
        UI.renamePresetBtn:SetText("|cff00ff00Save|r")
        UI.renamePresetBtn.isRenaming = true
    end
end

local function RenameSelectedPreset(newName)
    EnsureSavedVariables()

    local oldName = GetSelectedPresetName()
    if not CanRenamePreset(oldName) then
        StopRenameMode()
        return
    end

    local finalName = LimitTextLength(TrimText(newName or ""), CONST.PRESET_NAME_MAX_LENGTH)
    if finalName == "" then
        return
    end

    if finalName == oldName then
        StopRenameMode()
        return
    end

    finalName = GetUniquePresetName(finalName)

    RTSpammerSave.presets[finalName] = CopyPresetData(RTSpammerSave.presets[oldName])

    if type(RTSpammerSave.presets[oldName]) == "table" and type(RTSpammerSave.presets[oldName].order) == "number" then
        RTSpammerSave.presets[finalName].order = RTSpammerSave.presets[oldName].order
    end

    RTSpammerSave.presets[finalName].isDefault = false
    RTSpammerSave.presets[finalName].isReadOnly = false

    RTSpammerSave.presets[oldName] = nil
    SetCharacterActivePresetName(finalName)
    SetSelectedPresetName(finalName)
    StopRenameMode()
end

------------------------------------------------------------
-- UI BUILDERS
------------------------------------------------------------

local function CreatePresetDropdown(parentFrame)
    local dropdownWidth = 220
    local dropdownHeight = 24

    UI.presetDropdownButton = CreateFrame("Button", nil, parentFrame, "UIPanelButtonTemplate")
    UI.presetDropdownButton:SetSize(dropdownWidth, dropdownHeight)
    UI.presetDropdownButton:SetText("")

    UI.presetDropdownText = UI.presetDropdownButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.presetDropdownText:SetPoint("LEFT", UI.presetDropdownButton, "LEFT", 10, 0)
    UI.presetDropdownText:SetJustifyH("LEFT")
    UI.presetDropdownText:SetWidth(dropdownWidth - 20)

    SetSelectedPresetName(nil)

    local menuFrame = CreateFrame("Frame", addonName .. "PresetDropdownMenu", UIParent, "UIDropDownMenuTemplate")
    local isMenuOpen = false

    UI.presetDropdownButton:SetScript("OnClick", function(self)
        if isMenuOpen and DropDownList1 and DropDownList1:IsShown() then
            CloseDropDownMenus()
            isMenuOpen = false
            return
        end

        local menuList = {}
        local presetNames = GetSortedPresetNames()

        if #presetNames == 0 then
            menuList[1] = {
                text = "No presets",
                notCheckable = true,
                isTitle = true,
            }
        else
            local menuIndex = 1

            for _, presetName in ipairs(presetNames) do
                local menuText = presetName

                if presetName == CONST.CREATE_NEW_PRESET_LABEL then
                    menuText = "|cff00ff00" .. presetName .. "|r"
                end

                menuList[menuIndex] = {
                    text = menuText,
                    checked = presetName ~= CONST.CREATE_NEW_PRESET_LABEL and GetSelectedPresetName() == presetName,
                    func = function()
                        isMenuOpen = false
                        LoadPreset(presetName)
                    end,
                }
                menuIndex = menuIndex + 1
            end
        end

        EasyMenu(menuList, menuFrame, self, 0, 0, "MENU")
        isMenuOpen = true
    end)

    UI.presetDropdownButton:HookScript("OnHide", function()
        isMenuOpen = false
    end)
end

------------------------------------------------------------
-- PUBLIC UI ENTRY
------------------------------------------------------------

function CreateSpammerTabContent(parent, onClose)
    EnsureSavedVariables()

    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints()
    f:Hide()

    local topLeftX = 25
    local topRowY = -20

    local loadPresetLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    loadPresetLabel:SetPoint("TOPLEFT", topLeftX, topRowY)
    loadPresetLabel:SetText("Load Preset:")

    CreatePresetDropdown(f)
    UI.presetDropdownButton:SetPoint("LEFT", loadPresetLabel, "RIGHT", 10, 0)

    UI.renamePresetBG = CreateFrame("Frame", nil, f)
    ApplyPixelStyle(UI.renamePresetBG, 220, 24)
    UI.renamePresetBG:SetPoint("LEFT", loadPresetLabel, "RIGHT", 10, 0)
    UI.renamePresetBG:Hide()

    UI.renamePresetEditBox = CreateFrame("EditBox", nil, UI.renamePresetBG)
    UI.renamePresetEditBox:SetAllPoints()
    UI.renamePresetEditBox:SetAutoFocus(false)
    UI.renamePresetEditBox:SetFontObject(ChatFontNormal)
    UI.renamePresetEditBox:SetJustifyH("LEFT")
    UI.renamePresetEditBox:SetMaxLetters(CONST.PRESET_NAME_MAX_LENGTH)
    UI.renamePresetEditBox:Hide()

    UI.renamePresetEditBox:SetScript("OnTextChanged", function(self)
        local currentText = self:GetText() or ""
        if string.len(currentText) > CONST.PRESET_NAME_MAX_LENGTH then
            self:SetText(string.sub(currentText, 1, CONST.PRESET_NAME_MAX_LENGTH))
            self:SetCursorPosition(CONST.PRESET_NAME_MAX_LENGTH)
        end
    end)

    UI.renamePresetEditBox:SetScript("OnEnterPressed", function(self)
        RenameSelectedPreset(self:GetText() or "")
    end)

    UI.renamePresetEditBox:SetScript("OnEscapePressed", function()
        StopRenameMode()
    end)

    UI.renamePresetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    UI.renamePresetBtn:SetSize(80, 24)
    UI.renamePresetBtn:SetPoint("LEFT", UI.presetDropdownButton, "RIGHT", 8, 0)
    UI.renamePresetBtn:SetText("Rename")
    UI.renamePresetBtn.isRenaming = false
    UI.renamePresetBtn:SetScript("OnClick", function()
        if UI.renamePresetBtn.isRenaming then
            RenameSelectedPreset(UI.renamePresetEditBox:GetText() or "")
        else
            StartRenameMode()
        end
    end)

    UI.deletePresetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    UI.deletePresetBtn:SetSize(80, 24)
    UI.deletePresetBtn:SetPoint("LEFT", UI.renamePresetBtn, "RIGHT", 8, 0)
    UI.deletePresetBtn:SetText("Delete")
    UI.deletePresetBtn:SetScript("OnClick", function()
        local presetName = GetSelectedPresetName()

        if not CanDeletePreset(presetName) then
            return
        end

        StaticPopup_Show(CONST.SPAMMER_PRESET_DELETE_POPUP, presetName, nil, presetName)
    end)

    UI.msgLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.msgLabel:SetPoint("TOPLEFT", 25, -60)
    UI.msgLabel:SetText("Message to Spam:")

    UI.savePresetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    UI.savePresetBtn:SetSize(80, 24)
    UI.savePresetBtn:SetPoint("TOPRIGHT", -25, -56)
    UI.savePresetBtn:SetText("Save")
    UI.savePresetBtn:SetScript("OnClick", function()
        SaveActivePreset()
        UpdateMessageDirtyState()
        RefreshPresetActionButtons()
        ShowSavedFeedback()
    end)

    local msgBG = CreateFrame("Frame", nil, f)
    ApplyPixelStyle(msgBG, 0, 80)
    msgBG:SetPoint("TOPLEFT", 25, -84)
    msgBG:SetPoint("TOPRIGHT", -25, -84)

    UI.msgEditBox = CreateFrame("EditBox", nil, msgBG)
    UI.msgEditBox:SetMultiLine(true)
    UI.msgEditBox:SetMaxLetters(CONST.MAX_MESSAGE_LENGTH)
    UI.msgEditBox:SetFontObject(ChatFontNormal)
    UI.msgEditBox:SetPoint("TOPLEFT", 8, -8)
    UI.msgEditBox:SetPoint("BOTTOMRIGHT", -8, 8)
    UI.msgEditBox:SetAutoFocus(false)
    UI.msgEditBox:EnableMouse(true)
    if UI.msgEditBox.SetHyperlinksEnabled then
        UI.msgEditBox:SetHyperlinksEnabled(false)
    end

    UI.msgEditBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""

        if string.len(text) > CONST.MAX_MESSAGE_LENGTH then
            self:SetText(string.sub(text, 1, CONST.MAX_MESSAGE_LENGTH))
            self:SetCursorPosition(CONST.MAX_MESSAGE_LENGTH)
        end

        SetMessageBoxAsLinkTarget()
        UpdateCharacterCount()
        UpdateMessageDirtyState()
        RefreshPresetActionButtons()
    end)

    UI.msgEditBox:SetScript("OnEscapePressed", function(self)
        ClearMessageBoxAsLinkTarget()
        self:ClearFocus()
    end)

    UI.msgEditBox:SetScript("OnMouseDown", function(self)
        local presetName = GetSelectedPresetName()

        if IsPresetReadOnly(presetName) then
            ClearMessageBoxAsLinkTarget()
            self:ClearFocus()
            return
        end

        SetMessageBoxAsLinkTarget()
        self:SetFocus()
    end)

    UI.msgEditBox:SetScript("OnEditFocusGained", function(self)
        local presetName = GetSelectedPresetName()

        if IsPresetReadOnly(presetName) then
            ClearMessageBoxAsLinkTarget()
            self:ClearFocus()
            return
        end

        SetMessageBoxAsLinkTarget()
    end)

    UI.msgEditBox:SetScript("OnEditFocusLost", function()
        ClearMessageBoxAsLinkTarget()
    end)

    UI.msgEditBox:SetScript("OnHide", function()
        ClearMessageBoxAsLinkTarget()
    end)

    UI.charCountText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.charCountText:SetPoint("TOPRIGHT", msgBG, "BOTTOMRIGHT", 0, -5)
    UI.charCountText:SetText("Characters: 0/255")

    for i, config in ipairs(CONST.CHANNEL_POOL) do
        local row = CreateFrame("Frame", nil, f)
        row:SetSize(600, 30)
        row:SetPoint("TOPLEFT", 25, -206 - ((i - 1) * 32))

        row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.check:SetPoint("LEFT", 0, 0)
        row.check:SetSize(24, 24)
        row.check:SetScript("OnClick", function()
            UpdateMessageDirtyState()
            RefreshPresetActionButtons()
            SaveSelectedPresetSettingsFromUI()
        end)

        row.text = row.check:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.text:SetPoint("LEFT", row.check, "RIGHT", 5, 0)

        local sLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sLabel:SetPoint("LEFT", 220, 0)
        sLabel:SetText("Interval:")

        local tBG = CreateFrame("Frame", nil, row)
        ApplyPixelStyle(tBG, 45, 22)
        tBG:SetPoint("LEFT", sLabel, "RIGHT", 10, 0)

        row.timer = CreateFrame("EditBox", nil, tBG)
        row.timer:SetAllPoints()
        row.timer:SetJustifyH("CENTER")
        row.timer:SetNumeric(true)
        row.timer:SetAutoFocus(false)
        row.timer:SetFontObject(ChatFontNormal)
        row.timer:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
        end)
        row.timer:SetScript("OnEditFocusLost", function()
            UpdateMessageDirtyState()
            RefreshPresetActionButtons()
            SaveSelectedPresetSettingsFromUI()
        end)

        row.cdText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.cdText:SetPoint("LEFT", tBG, "RIGHT", 15, 0)
        row.cdText:SetText("|cff888888Ready|r")
        row.lastCooldownText = nil

        row.config = config
        row.nextSend = 0
        UI.channelRows[i] = row
    end

    eventFrame:UnregisterAllEvents()
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("CHANNEL_UI_UPDATE")
    eventFrame:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
    eventFrame:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE_USER")

    eventFrame:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_ENTERING_WORLD"
            or event == "CHANNEL_UI_UPDATE"
            or event == "CHAT_MSG_CHANNEL_NOTICE"
            or event == "CHAT_MSG_CHANNEL_NOTICE_USER" then
            RefreshChannelsAndPreserveUI()
        end
    end)

    eventFrame:SetScript("OnUpdate", function(self, elapsed)
        STATE.uiUpdateAccumulator = STATE.uiUpdateAccumulator + elapsed

        if UI.savePresetBtn and STATE.saveFeedbackResetAt > 0 and GetTime() >= STATE.saveFeedbackResetAt then
            SetSaveButtonVisual("Save", 1, 0.82, 0)
            STATE.saveFeedbackResetAt = 0
        end

        if STATE.uiUpdateAccumulator < CONST.UI_UPDATE_INTERVAL then
            return
        end

        STATE.uiUpdateAccumulator = 0

        local now = GetTime()

        for _, row in ipairs(UI.channelRows) do
            local remaining = row.nextSend - now

            if remaining > 0 then
                if row:IsShown() then
                    local colorCode = "|cff888888"

                    if STATE.isSpamming and row.check:GetChecked() then
                        colorCode = "|cff00ff00"
                    end

                    SetCooldownText(row, string.format("%s%.1fs|r", colorCode, remaining))
                end
            elseif STATE.isSpamming and row.check:GetChecked() then
                if row:IsShown() then
                    SetCooldownText(row, "|cffffcc00SENDING|r")
                end

                local textValue = GetMessageToSend()
                local intervalValue = tonumber(row.timer:GetText()) or 30
                row.nextSend = now + intervalValue

                if textValue ~= "" then
                    if row.config.chatType == "CHANNEL" then
                        local channelId = nil
                        local channelName = nil

                        channelId, channelName = GetFixedChannelInfo(row.config.name)

                        if channelId and channelId > 0 then
                            SendChatMessage(textValue, "CHANNEL", nil, channelId)
                        end
                    else
                        SendChatMessage(textValue, row.config.chatType)
                    end
                end
            else
                if row:IsShown() then
                    SetCooldownText(row, "|cff888888Ready|r")
                end
            end
        end
    end)

    f:SetScript("OnShow", function()
        EnsureSavedVariables()
        RefreshAvailableChannels()

        local presetName = GetCharacterActivePresetName()

        if presetName and GetPresetData(presetName) then
            SetSelectedPresetName(presetName)
            ApplyPresetToUI(GetPresetData(presetName))
        else
            SetSelectedPresetName(CONST.DEFAULT_PRESET_NAME)
            ApplyPresetToUI(GetPresetData(CONST.DEFAULT_PRESET_NAME))
        end

        StopRenameMode()
        RefreshPresetActionButtons()
        UpdateMessageDirtyState()
    end)

    UI.startBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    UI.startBtn:SetSize(170, 28)
    UI.startBtn:SetPoint("BOTTOMRIGHT", -18, 12)
    UI.startBtn:SetText("Start Spamming")

    UI.startBtn:SetScript("OnClick", function()
        if not STATE.isSpamming then
            local textValue = GetMessageToSend()

            if textValue == "" then
                return
            end

            STATE.isSpamming = true
            if RefreshStatusOverlay then
                RefreshStatusOverlay()
            end
            UI.startBtn:SetText("|cff00ff00Enabled|r")

            local now = GetTime()

            for _, row in ipairs(UI.channelRows) do
                local intervalValue = tonumber(row.timer:GetText()) or 30

                if not row.nextSend or row.nextSend <= 0 then
                    if row.config.name == "World" then
                        row.nextSend = now
                    else
                        row.nextSend = now + intervalValue
                    end
                end
            end
        else
            StopSpamming(false)
        end
    end)

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    closeBtn:SetSize(100, 28)
    closeBtn:SetPoint("RIGHT", UI.startBtn, "LEFT", -10, 0)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", onClose)

    if TryGetElvUISkinModule then
        local eValue, sValue = TryGetElvUISkinModule()

        if eValue and sValue then
            sValue:HandleButton(UI.presetDropdownButton)
            sValue:HandleButton(UI.renamePresetBtn)
            sValue:HandleButton(UI.deletePresetBtn)
            sValue:HandleButton(UI.savePresetBtn)
            sValue:HandleButton(UI.startBtn)
            sValue:HandleButton(closeBtn)

            for _, row in ipairs(UI.channelRows) do
                sValue:HandleCheckBox(row.check)
            end
        end
    end

    RefreshAvailableChannels()
    ApplyPresetToUI(GetPresetData(GetCharacterActivePresetName()))
    RefreshPresetActionButtons()
    StopRenameMode()

    return f
end

------------------------------------------------------------
-- INITIALIZATION
------------------------------------------------------------

loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, arg1)
    if arg1 == addonName then
        EnsureSavedVariables()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
