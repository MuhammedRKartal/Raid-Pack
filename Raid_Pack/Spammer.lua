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

local DATA = {
    defaultCurrentSettings = {
        intervals = {
            ["General"] = "23",
            ["Trade"] = "17",
            ["World"] = "61",
            ["YELL"] = "37"
        },
        enabledChannels = {
            ["General"] = true,
            ["Trade"] = true,
            ["World"] = true,
            ["YELL"] = false
        }
    },

    defaultEmbeddedPreset = {
        message = "Need a new UI or nice Weakauras to track everything? Come Join the Weakaura Center: https://discord.gg/7E6jAPsJD9",
        isDefault = true,
        isReadOnly = true,
        order = 0,
    },

    channelPool = {
        { name = "General", chatType = "CHANNEL" },
        { name = "Trade", chatType = "CHANNEL" },
        { name = "World", chatType = "CHANNEL" },
        { name = "YELL", chatType = "YELL" },
    },
}

local CONST = {
    CREATE_NEW_PRESET_LABEL = "Create New",
    CREATE_NEW_PRESET_BASE_NAME = "New Message",
    DEFAULT_PRESET_NAME = "Weakauras Discord",
    DEFAULT_PRESET_MESSAGE = "Need a new UI or nice Weakauras to track everything? Come Join the Weakaura Center: https://discord.gg/7E6jAPsJD9",
    DEFAULT_PRESET_READONLY_TEXT = "Need a new UI or nice Weakauras to track everything? Come Join the Weakaura Center: https://discord.gg/7E6jAPsJD9\n(Default preset is read-only)",
    PRESET_NAME_MAX_LENGTH = 21,
}

CONST.SPAMMER_PRESET_DELETE_POPUP = addonName .. "SpammerPresetDeletePopup"

local eventFrame = CreateFrame("Frame")

local CopyCurrentSettings
local CopyPresetSettings
local GetSelectedPresetName

------------------------------------------------------------
-- PUBLIC STATUS HELPERS
------------------------------------------------------------

function RT_IsSpammerEnabled()
    return STATE.isSpamming
end

------------------------------------------------------------
-- DATA COPY / SAVE HELPERS
------------------------------------------------------------

local function CopyIntervals(source)
    local result = {}

    if source then
        for key, value in pairs(source) do
            result[key] = tostring(value)
        end
    end

    return result
end

local function CopyEnabledChannels(source)
    local result = {}

    if source then
        for key, value in pairs(source) do
            result[key] = value and true or false
        end
    end

    return result
end

CopyCurrentSettings = function(source)
    local result = {
        intervals = {},
        enabledChannels = {}
    }

    if source then
        result.intervals = CopyIntervals(source.intervals)
        result.enabledChannels = CopyEnabledChannels(source.enabledChannels)
    end

    for channelName, intervalValue in pairs(DATA.defaultCurrentSettings.intervals) do
        if result.intervals[channelName] == nil then
            result.intervals[channelName] = intervalValue
        end
    end

    for channelName, enabledValue in pairs(DATA.defaultCurrentSettings.enabledChannels) do
        if result.enabledChannels[channelName] == nil then
            result.enabledChannels[channelName] = enabledValue
        end
    end

    return result
end

CopyPresetSettings = function(source)
    local result = {
        message = "",
        order = nil,
        isDefault = false,
        isReadOnly = false,
    }

    if source then
        result.message = source.message or ""

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

local function GetCharacterKey()
    local characterName = UnitName("player") or "Unknown"
    local realmName = GetRealmName() or "UnknownRealm"
    return tostring(realmName) .. " - " .. tostring(characterName)
end

local function EnsureSavedVariables()
    if not RTSpammerSave then
        RTSpammerSave = {}
    end

    if type(RTSpammerSave) ~= "table" then
        RTSpammerSave = {}
    end

    if type(RTSpammerSave.current) ~= "table" then
        RTSpammerSave.current = CopyCurrentSettings(DATA.defaultCurrentSettings)
    else
        RTSpammerSave.current = CopyCurrentSettings(RTSpammerSave.current)
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

    for presetName, presetData in pairs(RTSpammerSave.presets) do
        local copiedPresetData = CopyPresetSettings(presetData)

        if presetName == CONST.DEFAULT_PRESET_NAME then
            copiedPresetData.message = CONST.DEFAULT_PRESET_MESSAGE
            copiedPresetData.order = 0
            copiedPresetData.isDefault = true
            copiedPresetData.isReadOnly = true
        else
            copiedPresetData.isDefault = false
            copiedPresetData.isReadOnly = false

            if type(presetData) == "table" and type(presetData.order) == "number" then
                copiedPresetData.order = presetData.order
            else
                RTSpammerSave.presetOrderCounter = RTSpammerSave.presetOrderCounter + 1
                copiedPresetData.order = RTSpammerSave.presetOrderCounter
            end
        end

        RTSpammerSave.presets[presetName] = copiedPresetData
    end

    RTSpammerSave.presets[CONST.DEFAULT_PRESET_NAME] = CopyPresetSettings(DATA.defaultEmbeddedPreset)
    RTSpammerSave.presets[CONST.DEFAULT_PRESET_NAME].message = CONST.DEFAULT_PRESET_MESSAGE
    RTSpammerSave.presets[CONST.DEFAULT_PRESET_NAME].order = 0
    RTSpammerSave.presets[CONST.DEFAULT_PRESET_NAME].isDefault = true
    RTSpammerSave.presets[CONST.DEFAULT_PRESET_NAME].isReadOnly = true

    local characterKey = GetCharacterKey()

    if type(RTSpammerSave.characterSettings[characterKey]) ~= "table" then
        RTSpammerSave.characterSettings[characterKey] = {}
    end

    if type(RTSpammerSave.characterSettings[characterKey].activePresetName) ~= "string" then
        RTSpammerSave.characterSettings[characterKey].activePresetName = nil
    end

    if RTSpammerSave.characterSettings[characterKey].activePresetName == nil
        and type(RTSpammerSave.activePresetName) == "string"
        and RTSpammerSave.activePresetName ~= ""
        and RTSpammerSave.presets[RTSpammerSave.activePresetName] then
        RTSpammerSave.characterSettings[characterKey].activePresetName = RTSpammerSave.activePresetName
    end

    if RTSpammerSave.activePresetName ~= nil and type(RTSpammerSave.activePresetName) ~= "string" then
        RTSpammerSave.activePresetName = nil
    end
end

local function GetPresetData(presetName)
    EnsureSavedVariables()

    if type(presetName) ~= "string" or presetName == "" then
        return nil
    end

    if not RTSpammerSave.presets then
        return nil
    end

    return RTSpammerSave.presets[presetName]
end

local function IsDefaultPreset(presetName)
    local presetData = GetPresetData(presetName)

    if not presetData then
        return false
    end

    return presetData.isDefault == true
end

local function IsPresetReadOnly(presetName)
    local presetData = GetPresetData(presetName)

    if not presetData then
        return false
    end

    return presetData.isReadOnly == true
end

local function CanRenamePreset(presetName)
    if type(presetName) ~= "string" or presetName == "" then
        return false
    end

    if presetName == CONST.CREATE_NEW_PRESET_LABEL then
        return false
    end

    return GetPresetData(presetName) ~= nil and not IsPresetReadOnly(presetName)
end

local function CanDeletePreset(presetName)
    if type(presetName) ~= "string" or presetName == "" then
        return false
    end

    if presetName == CONST.CREATE_NEW_PRESET_LABEL then
        return false
    end

    return GetPresetData(presetName) ~= nil and not IsDefaultPreset(presetName)
end

local function CanSavePreset(presetName)
    if type(presetName) ~= "string" or presetName == "" then
        return false
    end

    if presetName == CONST.CREATE_NEW_PRESET_LABEL then
        return false
    end

    return GetPresetData(presetName) ~= nil and not IsPresetReadOnly(presetName)
end

local function GetCharacterActivePresetName()
    EnsureSavedVariables()

    local characterKey = GetCharacterKey()

    if type(RTSpammerSave.characterSettings) ~= "table" then
        RTSpammerSave.characterSettings = {}
    end

    if type(RTSpammerSave.characterSettings[characterKey]) ~= "table" then
        RTSpammerSave.characterSettings[characterKey] = {}
    end

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

    if type(RTSpammerSave.characterSettings) ~= "table" then
        RTSpammerSave.characterSettings = {}
    end

    if type(RTSpammerSave.characterSettings[characterKey]) ~= "table" then
        RTSpammerSave.characterSettings[characterKey] = {}
    end

    if type(presetName) == "string" and presetName ~= "" and RTSpammerSave.presets[presetName] then
        RTSpammerSave.characterSettings[characterKey].activePresetName = presetName
    else
        RTSpammerSave.characterSettings[characterKey].activePresetName = CONST.DEFAULT_PRESET_NAME
    end
end

local function DisableSpammingOnly()
    STATE.isSpamming = false
    RefreshStatusOverlay()

    if UI.startBtn then
        UI.startBtn:SetText("Start Spamming")
    end
end

local function StopSpammingState()
    STATE.isSpamming = false
    RefreshStatusOverlay()

    if UI.startBtn then
        UI.startBtn:SetText("Start Spamming")
    end

    for _, row in ipairs(UI.channelRows) do
        row.nextSend = 0

        if row.cdText then
            row.cdText:SetText("|cff888888Ready|r")
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
    else
        UI.msgLabel:SetText("Message to Spam:")
    end
end

------------------------------------------------------------
-- TEXT HELPERS
------------------------------------------------------------

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

local function GetFixedChannelInfo(logicalChannelName)
    if logicalChannelName == "General" then
        local channelId, channelName = GetChannelName(1)
        if channelId and channelId > 0 then
            return channelId, channelName
        end
        return nil, nil
    end

    if logicalChannelName == "Trade" then
        local channelId, channelName = GetChannelName(2)
        if channelId and channelId > 0 then
            return channelId, channelName
        end
        return nil, nil
    end

    if logicalChannelName == "World" then
        local candidateIds = { 4, 5, 6 }
        local i = 1

        while i <= #candidateIds do
            local candidateId = candidateIds[i]
            local channelId, channelName = GetChannelName(candidateId)

            if channelId and channelId > 0 and channelName then
                local normalizedChannelName = NormalizeChannelName(channelName)

                if string.find(normalizedChannelName, "global", 1, true) or string.find(normalizedChannelName, "world", 1, true) then
                    return channelId, channelName
                end
            end

            i = i + 1
        end

        return nil, nil
    end

    return nil, nil
end

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
        UI.msgEditBox:ClearFocus()
        UI.msgEditBox:EnableMouse(false)
        UI.msgEditBox:SetTextColor(0.6, 0.6, 0.6)
    else
        UI.msgEditBox:EnableMouse(true)
        UI.msgEditBox:SetTextColor(1, 1, 1)
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, arg1)
    if arg1 == addonName then
        EnsureSavedVariables()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

local function GetCurrentSettings()
    EnsureSavedVariables()
    return RTSpammerSave.current
end

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

------------------------------------------------------------
-- UI STATE REFRESH
------------------------------------------------------------

local function RefreshPresetActionButtons()
    local presetName = STATE.selectedPresetName
    local canRename = CanRenamePreset(presetName)
    local canDelete = CanDeletePreset(presetName)
    local canSave = CanSavePreset(presetName)

    if UI.savePresetBtn then
        if canSave then
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

------------------------------------------------------------
-- PRESET HELPERS
------------------------------------------------------------

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
end

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

        return tostring(leftValue) > tostring(rightValue)
    end)

    local result = { CONST.CREATE_NEW_PRESET_LABEL }

    local index = 1
    while index <= #presetNames do
        result[#result + 1] = presetNames[index]
        index = index + 1
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

local function SaveCurrentSettingsFromUI()
    EnsureSavedVariables()

    local currentSettings = GetCurrentSettings()

    currentSettings.intervals = {}
    currentSettings.enabledChannels = {}

    for _, row in ipairs(UI.channelRows) do
        currentSettings.intervals[row.config.name] = row.timer:GetText() or ""
        currentSettings.enabledChannels[row.config.name] = row.check:GetChecked() and true or false
    end
end

local function SaveCurrentSettings()
    SaveCurrentSettingsFromUI()
end

local function ApplyCurrentSettingsToUI(settingsData)
    if not settingsData then
        return
    end

    for _, row in ipairs(UI.channelRows) do
        local channelName = row.config.name
        local intervalValue = DATA.defaultCurrentSettings.intervals[channelName] or "30"
        local enabledValue = false

        if settingsData.intervals and settingsData.intervals[channelName] ~= nil then
            intervalValue = tostring(settingsData.intervals[channelName])
        end

        if settingsData.enabledChannels and settingsData.enabledChannels[channelName] then
            enabledValue = true
        end

        row.timer:SetText(intervalValue)
        row.check:SetChecked(enabledValue)
    end
end

local function ApplyPresetMessageToUI(presetData)
    if not UI.msgEditBox then
        return
    end

    local presetName = GetSelectedPresetName()
    local isReadOnly = IsPresetReadOnly(presetName)

    if isReadOnly then
        UI.msgEditBox:SetText(CONST.DEFAULT_PRESET_READONLY_TEXT)
    elseif presetData then
        UI.msgEditBox:SetText(presetData.message or "")
    else
        UI.msgEditBox:SetText("")
    end

    SetMessageEditBoxReadOnly(isReadOnly)
    UpdateMessageDirtyState()
end

local function LoadCurrentSettingsToUI()
    local currentSettings = GetCurrentSettings()
    ApplyCurrentSettingsToUI(currentSettings)
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

local function SaveActivePreset()
    EnsureSavedVariables()

    local presetName = GetSelectedPresetName()

    if not CanSavePreset(presetName) then
        return
    end

    local currentMessage = ""

    if UI.msgEditBox then
        currentMessage = UI.msgEditBox:GetText() or ""
    end

    RTSpammerSave.presets[presetName] = CopyPresetSettings({
        message = currentMessage,
        order = RTSpammerSave.presets[presetName] and RTSpammerSave.presets[presetName].order or nil,
        isDefault = false,
        isReadOnly = false,
    })

    SetCharacterActivePresetName(presetName)

    UpdateMessageDirtyState()
end

local function CreateNewPreset()
    EnsureSavedVariables()
    DisableSpammingOnly()

    local presetName = GetNextNewPresetName()

    RTSpammerSave.presetOrderCounter = (RTSpammerSave.presetOrderCounter or 0) + 1

    RTSpammerSave.presets[presetName] = CopyPresetSettings({
        message = "",
        order = RTSpammerSave.presetOrderCounter,
        isDefault = false,
        isReadOnly = false,
    })

    SetCharacterActivePresetName(presetName)
    SetSelectedPresetName(presetName)
    StopRenameMode()

    LoadCurrentSettingsToUI()
    ApplyPresetMessageToUI(RTSpammerSave.presets[presetName])
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

    if not GetPresetData(presetName) then
        return
    end

    DisableSpammingOnly()

    SetCharacterActivePresetName(presetName)
    SetSelectedPresetName(presetName)
    StopRenameMode()

    LoadCurrentSettingsToUI()
    ApplyPresetMessageToUI(GetPresetData(presetName))
end

local function DeletePreset(presetName)
    if not CanDeletePreset(presetName) then
        return
    end

    EnsureSavedVariables()
    DisableSpammingOnly()

    RTSpammerSave.presets[presetName] = nil

    local characterKey = GetCharacterKey()
    if RTSpammerSave.characterSettings
        and RTSpammerSave.characterSettings[characterKey]
        and RTSpammerSave.characterSettings[characterKey].activePresetName == presetName then
        RTSpammerSave.characterSettings[characterKey].activePresetName = CONST.DEFAULT_PRESET_NAME
    end

    SetCharacterActivePresetName(CONST.DEFAULT_PRESET_NAME)
    SetSelectedPresetName(CONST.DEFAULT_PRESET_NAME)
    StopRenameMode()

    LoadCurrentSettingsToUI()
    ApplyPresetMessageToUI(GetPresetData(CONST.DEFAULT_PRESET_NAME))
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
    preferredIndex = 3
}

local function IsRenameBlocked(presetName)
    return not CanRenamePreset(presetName)
end

local function StartRenameMode()
    EnsureSavedVariables()

    local presetName = GetSelectedPresetName()
    if IsRenameBlocked(presetName) then
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
    if IsRenameBlocked(oldName) then
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

    RTSpammerSave.presets[finalName] = CopyPresetSettings(RTSpammerSave.presets[oldName])

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
                isTitle = true
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
                    end
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

local isLinkHooksInstalled = false
local originalSetItemRef = nil
local originalChatEdit_InsertLink = nil

local isLinkHooksInstalled = false
local originalChatEdit_InsertLink = nil
local originalChatEdit_GetActiveWindow = nil

local function IsMessageBoxActive()
    if not UI.msgEditBox then
        return false
    end

    if not UI.msgEditBox:IsShown() then
        return false
    end

    if UI.msgEditBox:HasFocus() then
        return true
    end

    return false
end

local function InsertLinkIntoMessageBox(link)
    local presetName = GetSelectedPresetName()

    if IsPresetReadOnly(presetName) then
        return false
    end

    if not IsMessageBoxActive() then
        return false
    end

    if not link or link == "" then
        return false
    end

    local currentText = UI.msgEditBox:GetText() or ""
    local insertText = link

    if string.len(currentText) + string.len(insertText) > 255 then
        return false
    end

    UI.msgEditBox:Insert(insertText)
    UI.msgEditBox:SetFocus()

    if UI.charCountText then
        UI.charCountText:SetText(string.format("Characters: %d/255", string.len(UI.msgEditBox:GetText() or "")))
    end

    UpdateMessageDirtyState()

    return true
end

local function HookLinkInsertion()
    if isLinkHooksInstalled then
        return
    end

    isLinkHooksInstalled = true

    originalChatEdit_GetActiveWindow = ChatEdit_GetActiveWindow
    ChatEdit_GetActiveWindow = function(...)
        if IsMessageBoxActive() then
            return UI.msgEditBox
        end

        if originalChatEdit_GetActiveWindow then
            return originalChatEdit_GetActiveWindow(...)
        end

        return nil
    end

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
        SaveCurrentSettings()
        SaveActivePreset()
        UpdateMessageDirtyState()
        ShowSavedFeedback()
    end)

    local msgBG = CreateFrame("Frame", nil, f)
    ApplyPixelStyle(msgBG, 0, 80)
    msgBG:SetPoint("TOPLEFT", 25, -84)
    msgBG:SetPoint("TOPRIGHT", -25, -84)

    UI.msgEditBox = CreateFrame("EditBox", nil, msgBG)
    UI.msgEditBox:SetMultiLine(true)
    UI.msgEditBox:SetMaxLetters(255)
    UI.msgEditBox:SetFontObject(ChatFontNormal)
    UI.msgEditBox:SetPoint("TOPLEFT", 8, -8)
    UI.msgEditBox:SetPoint("BOTTOMRIGHT", -8, 8)
    UI.msgEditBox:SetAutoFocus(false)

    UI.msgEditBox:SetScript("OnTextChanged", function(self)
        local textValue = self:GetText() or ""
        local textLength = string.len(textValue)

        if UI.charCountText then
            UI.charCountText:SetText(string.format("Characters: %d/255", textLength))
        end

        UpdateMessageDirtyState()
    end)

    UI.msgEditBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    UI.msgEditBox:SetScript("OnMouseDown", function(self)
        local presetName = GetSelectedPresetName()

        if IsPresetReadOnly(presetName) then
            self:ClearFocus()
            return
        end

        self:SetFocus()
    end)

    UI.msgEditBox:SetScript("OnEditFocusGained", function(self)
        local presetName = GetSelectedPresetName()

        if IsPresetReadOnly(presetName) then
            self:ClearFocus()
            return
        end

        self:SetFocus()
    end)

    UI.charCountText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.charCountText:SetPoint("TOPRIGHT", msgBG, "BOTTOMRIGHT", 0, -5)
    UI.charCountText:SetText("Characters: 0/255")

    for i, config in ipairs(DATA.channelPool) do
        local row = CreateFrame("Frame", nil, f)
        row:SetSize(600, 30)
        row:SetPoint("TOPLEFT", 25, -206 - ((i - 1) * 32))

        row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.check:SetPoint("LEFT", 0, 0)
        row.check:SetSize(24, 24)
        row.check:SetScript("OnClick", function()
            SaveCurrentSettingsFromUI()
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
        row.timer:SetScript("OnTextChanged", function()
            SaveCurrentSettingsFromUI()
        end)

        row.cdText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.cdText:SetPoint("LEFT", tBG, "RIGHT", 15, 0)
        row.cdText:SetText("|cff888888Ready|r")

        row.config = config
        row.nextSend = 0
        UI.channelRows[i] = row
    end

    eventFrame:SetScript("OnUpdate", function(self, elapsed)
        if UI.savePresetBtn and STATE.saveFeedbackResetAt > 0 and GetTime() >= STATE.saveFeedbackResetAt then
            SetSaveButtonVisual("Save", 1, 0.82, 0)
            STATE.saveFeedbackResetAt = 0
        end

        local now = GetTime()

        for _, row in ipairs(UI.channelRows) do
            local remaining = row.nextSend - now

            if remaining > 0 then
                if row:IsShown() then
                    local colorCode = "|cff888888"

                    if STATE.isSpamming and row.check:GetChecked() then
                        colorCode = "|cff00ff00"
                    end

                    row.cdText:SetText(string.format("%s%.1fs|r", colorCode, remaining))
                end
            elseif STATE.isSpamming and row.check:GetChecked() then
                if row:IsShown() then
                    row.cdText:SetText("|cffffcc00SENDING|r")
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
                    row.cdText:SetText("|cff888888Ready|r")
                end
            end
        end
    end)

    f:SetScript("OnShow", function()
        EnsureSavedVariables()

        LoadCurrentSettingsToUI()

        local presetName = GetCharacterActivePresetName()

        if presetName and GetPresetData(presetName) then
            SetSelectedPresetName(presetName)
            ApplyPresetMessageToUI(GetPresetData(presetName))
        else
            SetSelectedPresetName(CONST.DEFAULT_PRESET_NAME)
            ApplyPresetMessageToUI(GetPresetData(CONST.DEFAULT_PRESET_NAME))
        end

        StopRenameMode()

        local visibleCount = 0

        for _, row in ipairs(UI.channelRows) do
            local isAvailable = false
            local displayName = row.config.name

            if row.config.chatType == "YELL" then
                isAvailable = true
                displayName = CapitalizeWords(row.config.name)
            else
                local channelIndex = nil
                local channelName = nil

                channelIndex, channelName = GetFixedChannelInfo(row.config.name)

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
            RefreshStatusOverlay()
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
            STATE.isSpamming = false
            RefreshStatusOverlay()
            UI.startBtn:SetText("Start Spamming")
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

    LoadCurrentSettingsToUI()
    RefreshPresetActionButtons()
    StopRenameMode()

    return f
end
