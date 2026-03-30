-- Auto_Response.lua

local addonName = ...
local addonTable = select(2, ...)

------------------------------------------------------------
-- STATE / REFS / CONSTANTS
------------------------------------------------------------

local STATE = {
    isAutoResponseEnabled = false,
    selectedPresetName = nil,
    selectedCommandRow = nil,
    defaultResponseSaveResetAt = 0,
    presetTransferMode = nil,
    defaultResponseThrottleBySender = {},
    draggedCommandRow = nil,
    isDraggingCommandRow = false,
    dragHoverTargetRow = nil,
    lastSelectedPresetName = nil
}

local UI = {
    root = nil,

    presetDropdownButton = nil,
    presetDropdownText = nil,
    renamePresetBtn = nil,
    renamePresetBG = nil,
    renamePresetEditBox = nil,
    deletePresetBtn = nil,
    importPresetBtn = nil,
    exportPresetBtn = nil,

    presetTransferFrame = nil,
    presetTransferTitleText = nil,
    presetTransferScrollFrame = nil,
    presetTransferEditBox = nil,
    presetTransferConfirmBtn = nil,
    presetTransferCancelBtn = nil,
    presetTransferMeasureText = nil,
    presetTransferStatusText = nil,

    defaultResponseLabel = nil,
    defaultResponseEditBox = nil,
    defaultResponseCharCountText = nil,
    defaultResponseSaveBtn = nil,

    addCommandBtn = nil,
    commandScrollFrame = nil,
    commandContentFrame = nil,
    commandListButtons = {},
    commandDragInfoText = nil,

    commandDetailPanel = nil,
    commandDetailEmptyText = nil,
    commandDetailCommandLabel = nil,
    commandDetailCommandEditBG = nil,
    commandDetailCommandEditBox = nil,
    commandDetailResponseLabel = nil,
    commandDetailResponseBG = nil,
    commandDetailResponseEditBox = nil,
    commandDetailSaveBtn = nil,
    commandDetailDeleteBtn = nil,
    commandDetailStatusText = nil,
    commandBottomDropZone = nil,

    helpHintCheckbox = nil,
    sendCommandListCheckbox = nil,
    enableBtn = nil,
    closeBtn = nil,
}

local DATA = {
    commandRows = {},
}

local CONST = {
    CREATE_NEW_PRESET_LABEL = "Create New",
    CREATE_NEW_PRESET_BASE_NAME = "New Preset",
    DEFAULT_PRESET_NAME = "Weakauras Center",

    PRESET_NAME_MAX_LENGTH = 21,
    COMMAND_NAME_MAX_LENGTH = 12,
    RESPONSE_MAX_LENGTH = 255,
    CHAT_MESSAGE_MAX_LENGTH = 255,
    DEFAULT_RESPONSE_COOLDOWN_SECONDS = 450,

    HELP_COMMAND_DISPLAY_TEXT = "?help / ?command / ?commands",
    HELP_COMMAND_PRIMARY = "?help",
    HELP_COMMAND_SECONDARY = "?commands",
    HELP_COMMAND_TERTIARY = "?command",
    HELP_COMMAND_AUTO_RESPONSE = "Shows the full command list.",

    DEFAULT_RESPONSE_HELP_SUFFIX = " Type ?help or ?command anytime you need help.",
    HELP_HINT_CHECKBOX_LABEL = "Add Help Hint",
    COMMAND_LIST_CHECKBOX_LABEL = "Send Command List",

    PRESET_TRANSFER_EXPORT_TITLE = "Export Preset",
    PRESET_TRANSFER_IMPORT_TITLE = "Import Preset",
}

CONST.AUTO_RESPONSE_PRESET_DELETE_POPUP = addonName .. "AutoResponsePresetDeletePopup"
CONST.AUTO_RESPONSE_COMMAND_DELETE_POPUP = addonName .. "AutoResponseCommandDeletePopup"

local eventFrame = CreateFrame("Frame")
local loader = CreateFrame("Frame")

local DEFAULT_PRESET_TEMPLATE = {
    defaultResponse = "Hello, welcome to Weakauras Center.",
    commands = {
        {
            command = "?discord",
            response = "You can join the discord by this link: https://discord.gg/Q9ZnDAR7F8"
        },
        {
            command = "?free",
            response = "Yes there are some free content, you can also share since its a public community, but most of the content is paid with in-game gold."
        },
        {
            command = "?ownership",
            response = "All content is created by me or other creators. Nothing is stolen or used without permission."
        },
        {
            command = "?ui",
            response = "User Interfaces are complete screen setups built with multiple addons. The channel includes ElvUI, BlizzUI, and PvP UI configurations. No worries its easy to setup."
        },
        {
            command = "?weakauras",
            response = "This channel includes WeakAuras for v4.0.0 and v5.19+, with setups for all classes and specs, raid helper WeakAuras, PvP WeakAuras, and plenty of extra utilities."
        },
        {
            command = "?wtb",
            response = "Please log discord and check all channels, then contact me >>HirohitoW<<. Discord Link: https://discord.gg/Q9ZnDAR7F8"
        }
    }
}

local SYSTEM_HELP_ROW = {
    isSystemCommand = true,
    isDeleted = false,
    hasDuplicate = false,
    command = CONST.HELP_COMMAND_DISPLAY_TEXT,
    response = CONST.HELP_COMMAND_AUTO_RESPONSE
}

------------------------------------------------------------
-- TEXT HELPERS
------------------------------------------------------------

local function TrimText(text)
    local result = text or ""
    result = string.gsub(result, "^%s+", "")
    result = string.gsub(result, "%s+$", "")
    return result
end

local function RemoveAllSpaces(text)
    local result = tostring(text or "")
    result = string.gsub(result, "%s+", "")
    return result
end

local function LimitTextLength(text, maxLength)
    local result = text or ""
    if string.len(result) > maxLength then
        result = string.sub(result, 1, maxLength)
    end
    return result
end

local function NormalizeCommandText(text)
    local result = tostring(text or "")
    result = string.lower(result)
    result = RemoveAllSpaces(result)
    result = TrimText(result)
    return result
end

local function NormalizeCommandForMatch(text)
    local result = tostring(text or "")
    result = string.lower(result)
    result = RemoveAllSpaces(result)
    result = TrimText(result)
    result = string.gsub(result, "^[%?%!%.%-/]+", "")
    return result
end

local function DoCommandsMatch(leftText, rightText)
    local leftNormalized = NormalizeCommandForMatch(leftText)
    local rightNormalized = NormalizeCommandForMatch(rightText)

    if leftNormalized == "" or rightNormalized == "" then
        return false
    end

    return leftNormalized == rightNormalized
end

local function IsReservedHelpAlias(text)
    local normalizedText = NormalizeCommandText(text)

    if normalizedText == NormalizeCommandText(CONST.HELP_COMMAND_PRIMARY) then
        return true
    end

    if normalizedText == NormalizeCommandText(CONST.HELP_COMMAND_SECONDARY) then
        return true
    end

    if normalizedText == NormalizeCommandText(CONST.HELP_COMMAND_TERTIARY) then
        return true
    end

    if normalizedText == NormalizeCommandText(CONST.HELP_COMMAND_DISPLAY_TEXT) then
        return true
    end

    return false
end

local function SanitizeCommandText(text)
    local result = tostring(text or "")
    result = RemoveAllSpaces(result)
    result = LimitTextLength(result, CONST.COMMAND_NAME_MAX_LENGTH)
    return result
end

local function EscapeLuaString(text)
    return string.format("%q", tostring(text or ""))
end

local function EncodeTransferValue(text)
    local sourceText = tostring(text or "")
    return (string.gsub(sourceText, ".", function(character)
        return string.format("%02X", string.byte(character))
    end))
end

local function DecodeTransferValue(text)
    local sourceText = tostring(text or "")

    if sourceText == "" then
        return ""
    end

    if string.len(sourceText) % 2 ~= 0 then
        return nil
    end

    local decodedParts = {}
    local index = 1

    while index <= string.len(sourceText) do
        local pairText = string.sub(sourceText, index, index + 1)

        if not string.find(pairText, "^[0-9A-Fa-f][0-9A-Fa-f]$") then
            return nil
        end

        decodedParts[#decodedParts + 1] = string.char(tonumber(pairText, 16))
        index = index + 2
    end

    return table.concat(decodedParts)
end

------------------------------------------------------------
-- UI HELPERS
------------------------------------------------------------

local function ApplyPixelStyle(frame, width, height)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)
    frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    if width and height then
        frame:SetSize(width, height)
    end
end

local function SetEditBoxInteractionEnabled(editBox, isEnabled)
    if not editBox then
        return
    end

    if not isEnabled then
        editBox:ClearFocus()
    end

    if editBox.EnableMouse then
        editBox:EnableMouse(isEnabled and true or false)
    end

    if editBox.EnableKeyboard then
        editBox:EnableKeyboard(isEnabled and true or false)
    end

    if editBox.SetTextColor and not isEnabled then
        editBox:SetTextColor(0.65, 0.65, 0.65)
    end

    if editBox.SetAlpha then
        if isEnabled then
            editBox:SetAlpha(1)
        else
            editBox:SetAlpha(0.8)
        end
    end
end

local function SetEditBoxReadOnly(editBox, isReadOnly)
    if not editBox then return end

    if isReadOnly then
        editBox.isReadOnly = true
        editBox.lastReadOnlyText = tostring(editBox:GetText() or "")
    else
        editBox.isReadOnly = false
        editBox.lastReadOnlyText = nil
    end

    if editBox.EnableKeyboard then
        editBox:EnableKeyboard(true)
    end

    if editBox.EnableMouse then
        editBox:EnableMouse(true)
    end

    if editBox.SetTextColor then
        editBox:SetTextColor(1, 1, 1)
    end
end

local function TrySkinButton(button)
    if not button then
        return
    end

    if TryGetElvUISkinModule then
        local eValue, sValue = TryGetElvUISkinModule()
        if eValue and sValue and not button.isSkinned then
            sValue:HandleButton(button)
            button.isSkinned = true
        end
    end
end

local function TrySkinCheckBox(checkBox)
    if not checkBox or checkBox.isSkinned then
        return
    end

    if not TryGetElvUISkinModule then
        return
    end

    local eValue, sValue = TryGetElvUISkinModule()

    if not eValue or not sValue then
        return
    end

    if sValue.HandleCheckBox then
        sValue:HandleCheckBox(checkBox)
        checkBox.isSkinned = true
    end
end

------------------------------------------------------------
-- PUBLIC STATUS HELPERS
------------------------------------------------------------

function RT_IsAutoResponseEnabled()
    return STATE.isAutoResponseEnabled and true or false
end

local function RefreshAutoResponseOverlayIfAvailable()
    if RefreshStatusOverlay then
        RefreshStatusOverlay()
    end
end

local function DisableAutoResponse()
    STATE.isAutoResponseEnabled = false

    if type(RTAutoResponseSave) == "table" then
        RTAutoResponseSave.enabled = false
    end

    if UI.enableBtn then
        if STATE.isAutoResponseEnabled then
            UI.enableBtn:SetText("|cff00ff00Enabled|r")
        else
            UI.enableBtn:SetText("Enable Auto Reply")
        end
    end

    RefreshAutoResponseOverlayIfAvailable()
end

------------------------------------------------------------
-- DATA COPY / SAVE HELPERS
------------------------------------------------------------

local function CopyCommandEntry(source)
    local result = {
        command = "",
        response = "",
        isDeleted = false,
        hasDuplicate = false,
        isSystemCommand = false
    }

    if source then
        result.command = tostring(source.command or "")
        result.response = tostring(source.response or "")
    end

    result.command = SanitizeCommandText(result.command)
    result.response = LimitTextLength(result.response, CONST.RESPONSE_MAX_LENGTH)

    if IsReservedHelpAlias(result.command) then
        result.command = ""
        result.response = ""
    end

    return result
end

local function CopyPresetData(source)
    local result = {
        defaultResponse = "",
        commands = {}
    }

    if source then
        result.defaultResponse = tostring(source.defaultResponse or "")

        if type(source.commands) == "table" then
            local index = 1
            while source.commands[index] do
                local copiedEntry = CopyCommandEntry(source.commands[index])
                if copiedEntry.command ~= "" or copiedEntry.response ~= "" then
                    result.commands[#result.commands + 1] = copiedEntry
                end
                index = index + 1
            end
        end
    end

    result.defaultResponse = LimitTextLength(result.defaultResponse, CONST.RESPONSE_MAX_LENGTH)

    return result
end

local function GetCharacterKey()
    local characterName = UnitName("player") or "Unknown"
    local realmName = GetRealmName() or "UnknownRealm"
    return tostring(realmName) .. " - " .. tostring(characterName)
end

local function EnsureSavedVariables()
    if type(RTAutoResponseSave) ~= "table" then
        RTAutoResponseSave = {}
    end

    if type(RTAutoResponseSave.presets) ~= "table" then
        RTAutoResponseSave.presets = {}
    end

    if type(RTAutoResponseSave.characterSettings) ~= "table" then
        RTAutoResponseSave.characterSettings = {}
    end

    local characterKey = GetCharacterKey()

    if type(RTAutoResponseSave.characterSettings[characterKey]) ~= "table" then
        RTAutoResponseSave.characterSettings[characterKey] = {}
    end

    if type(RTAutoResponseSave.characterSettings[characterKey].activePresetName) ~= "string" then
        if type(RTAutoResponseSave.activePresetName) == "string"
            and RTAutoResponseSave.activePresetName ~= ""
            and RTAutoResponseSave.presets[RTAutoResponseSave.activePresetName] then
            RTAutoResponseSave.characterSettings[characterKey].activePresetName = RTAutoResponseSave.activePresetName
        else
            RTAutoResponseSave.characterSettings[characterKey].activePresetName = CONST.DEFAULT_PRESET_NAME
        end
    end

    if RTAutoResponseSave.enabled == nil then
        RTAutoResponseSave.enabled = false
    else
        RTAutoResponseSave.enabled = RTAutoResponseSave.enabled and true or false
    end

    if RTAutoResponseSave.enableHelpHint == nil then
        RTAutoResponseSave.enableHelpHint = true
    else
        RTAutoResponseSave.enableHelpHint = RTAutoResponseSave.enableHelpHint and true or false
    end

    if RTAutoResponseSave.sendCommandListAfterDefault == nil then
        RTAutoResponseSave.sendCommandListAfterDefault = true
    else
        RTAutoResponseSave.sendCommandListAfterDefault = RTAutoResponseSave.sendCommandListAfterDefault and true or false
    end

    if type(RTAutoResponseSave.presetOrderCounter) ~= "number" then
        RTAutoResponseSave.presetOrderCounter = 0
    end

    for presetName, presetData in pairs(RTAutoResponseSave.presets) do
        local copiedPresetData = CopyPresetData(presetData)

        if presetName == CONST.DEFAULT_PRESET_NAME then
            copiedPresetData.order = -1
        else
            if type(presetData) == "table" and type(presetData.order) == "number" then
                copiedPresetData.order = presetData.order
            else
                RTAutoResponseSave.presetOrderCounter = RTAutoResponseSave.presetOrderCounter + 1
                copiedPresetData.order = RTAutoResponseSave.presetOrderCounter
            end
        end

        RTAutoResponseSave.presets[presetName] = copiedPresetData
    end

    local embeddedDefaultPresetData = CopyPresetData(DEFAULT_PRESET_TEMPLATE)
    embeddedDefaultPresetData.order = -1
    RTAutoResponseSave.presets[CONST.DEFAULT_PRESET_NAME] = embeddedDefaultPresetData

    local activePresetName = RTAutoResponseSave.characterSettings[characterKey].activePresetName

    if not activePresetName
        or activePresetName == ""
        or not RTAutoResponseSave.presets[activePresetName] then
        RTAutoResponseSave.characterSettings[characterKey].activePresetName = CONST.DEFAULT_PRESET_NAME
    end

    if type(RTAutoResponseSave.activePresetName) ~= "string"
        or RTAutoResponseSave.activePresetName == ""
        or not RTAutoResponseSave.presets[RTAutoResponseSave.activePresetName] then
        RTAutoResponseSave.activePresetName = RTAutoResponseSave.characterSettings[characterKey].activePresetName
    end
end

local function IsHelpHintEnabled()
    EnsureSavedVariables()
    return RTAutoResponseSave.enableHelpHint ~= false
end

local function IsCommandListAfterDefaultEnabled()
    EnsureSavedVariables()
    return RTAutoResponseSave.sendCommandListAfterDefault ~= false
end

local function RefreshBottomOptionCheckboxes()
    if UI.helpHintCheckbox and UI.helpHintCheckbox.SetChecked then
        UI.helpHintCheckbox:SetChecked(IsHelpHintEnabled())
    end

    if UI.sendCommandListCheckbox and UI.sendCommandListCheckbox.SetChecked then
        UI.sendCommandListCheckbox:SetChecked(IsCommandListAfterDefaultEnabled())
    end
end

local function ForceDisableOnLogin()
    STATE.isAutoResponseEnabled = false

    if type(RTAutoResponseSave) == "table" then
        RTAutoResponseSave.enabled = false
    end
end

local function GetCharacterActivePresetName()
    EnsureSavedVariables()

    local characterKey = GetCharacterKey()

    if type(RTAutoResponseSave.characterSettings) ~= "table" then
        RTAutoResponseSave.characterSettings = {}
    end

    if type(RTAutoResponseSave.characterSettings[characterKey]) ~= "table" then
        RTAutoResponseSave.characterSettings[characterKey] = {}
    end

    local presetName = RTAutoResponseSave.characterSettings[characterKey].activePresetName

    if type(presetName) ~= "string" or presetName == "" or not RTAutoResponseSave.presets[presetName] then
        return CONST.DEFAULT_PRESET_NAME
    end

    return presetName
end


local function FlushActivePresetToSavedVariables()
    EnsureSavedVariables()

    local presetName = STATE.selectedPresetName

    if not presetName or presetName == "" then
        local characterKey = GetCharacterKey()
        presetName = RTAutoResponseSave.characterSettings[characterKey].activePresetName
    end

    if not presetName or presetName == "" then
        presetName = CONST.DEFAULT_PRESET_NAME
    end

    if presetName == CONST.CREATE_NEW_PRESET_LABEL then
        RTAutoResponseSave.enabled = STATE.isAutoResponseEnabled and true or false
        return
    end

    local characterKey = GetCharacterKey()
    if type(RTAutoResponseSave.characterSettings) ~= "table" then
        RTAutoResponseSave.characterSettings = {}
    end
    if type(RTAutoResponseSave.characterSettings[characterKey]) ~= "table" then
        RTAutoResponseSave.characterSettings[characterKey] = {}
    end

    RTAutoResponseSave.characterSettings[characterKey].activePresetName = presetName
    RTAutoResponseSave.activePresetName = presetName
    RTAutoResponseSave.enabled = STATE.isAutoResponseEnabled and true or false

    if presetName == CONST.DEFAULT_PRESET_NAME then
        return
    end

    if not RTAutoResponseSave.presets[presetName] then
        RTAutoResponseSave.presets[presetName] = {
            defaultResponse = "",
            commands = {}
        }
    end

    local presetData = RTAutoResponseSave.presets[presetName]

    if UI.defaultResponseEditBox then
        presetData.defaultResponse = LimitTextLength(UI.defaultResponseEditBox:GetText() or "", CONST.RESPONSE_MAX_LENGTH)
    else
        presetData.defaultResponse = LimitTextLength(presetData.defaultResponse or "", CONST.RESPONSE_MAX_LENGTH)
    end

    local sourceRows = DATA.commandRows
    if type(sourceRows) ~= "table" or #sourceRows == 0 then
        sourceRows = presetData.commands or {}
    end

    local newCommands = {}
    local saveIndex = 1
    local rowIndex = 1

    while rowIndex <= #sourceRows do
        local row = sourceRows[rowIndex]

        if row and not row.isDeleted and not row.isSystemCommand then
            local sanitizedCommand = SanitizeCommandText(row.command or "")
            local limitedResponse = LimitTextLength(row.response or "", CONST.RESPONSE_MAX_LENGTH)

            if sanitizedCommand ~= "" and limitedResponse ~= "" and not IsReservedHelpAlias(sanitizedCommand) then
                newCommands[saveIndex] = {
                    command = sanitizedCommand,
                    response = limitedResponse
                }
                saveIndex = saveIndex + 1
            end
        end

        rowIndex = rowIndex + 1
    end

    presetData.commands = newCommands

end

------------------------------------------------------------
-- PRESET HELPERS
------------------------------------------------------------

local function GetSelectedPresetName()
    EnsureSavedVariables()

    local presetName = STATE.selectedPresetName

    if type(presetName) == "string"
        and presetName ~= ""
        and presetName ~= CONST.CREATE_NEW_PRESET_LABEL
        and RTAutoResponseSave.presets[presetName] then
        return presetName
    end

    presetName = GetCharacterActivePresetName()

    if type(presetName) == "string"
        and presetName ~= ""
        and RTAutoResponseSave.presets[presetName] then
        return presetName
    end

    return CONST.DEFAULT_PRESET_NAME
end

local function SetSelectedPresetName(presetName)
    local currentPresetName = STATE.selectedPresetName

    if currentPresetName
        and currentPresetName ~= ""
        and currentPresetName ~= CONST.CREATE_NEW_PRESET_LABEL
        and currentPresetName ~= presetName
        and RTAutoResponseSave
        and RTAutoResponseSave.presets
        and RTAutoResponseSave.presets[currentPresetName] then
        STATE.lastSelectedPresetName = currentPresetName
    end

    STATE.selectedPresetName = presetName

    if presetName
        and presetName ~= ""
        and presetName ~= CONST.CREATE_NEW_PRESET_LABEL
        and RTAutoResponseSave
        and RTAutoResponseSave.presets
        and RTAutoResponseSave.presets[presetName] then
        local characterKey = GetCharacterKey()
        if type(RTAutoResponseSave.characterSettings) ~= "table" then
            RTAutoResponseSave.characterSettings = {}
        end
        if type(RTAutoResponseSave.characterSettings[characterKey]) ~= "table" then
            RTAutoResponseSave.characterSettings[characterKey] = {}
        end
        RTAutoResponseSave.characterSettings[characterKey].activePresetName = presetName
        RTAutoResponseSave.activePresetName = presetName
    end

    if UI.presetDropdownText then
        if presetName and presetName ~= "" then
            UI.presetDropdownText:SetText(presetName)
        else
            UI.presetDropdownText:SetText("Select Preset")
        end
    end
end

local function IsProtectedPreset(presetName)
    return presetName == CONST.DEFAULT_PRESET_NAME
end

local function IsDefaultPresetSelected()
    return GetSelectedPresetName() == CONST.DEFAULT_PRESET_NAME
end

local function IsCurrentPresetEditable()
    return not IsDefaultPresetSelected()
end

local function IsRenameBlocked(presetName)
    if not presetName or presetName == "" then
        return true
    end

    if presetName == CONST.CREATE_NEW_PRESET_LABEL then
        return true
    end

    if IsProtectedPreset(presetName) then
        return true
    end

    if not RTAutoResponseSave.presets[presetName] then
        return true
    end

    return false
end

local function GetSortedPresetNames()
    EnsureSavedVariables()

    local presetNames = {}

    for presetName in pairs(RTAutoResponseSave.presets) do
        presetNames[#presetNames + 1] = presetName
    end

    table.sort(presetNames, function(leftValue, rightValue)
        local leftPreset = RTAutoResponseSave.presets[leftValue]
        local rightPreset = RTAutoResponseSave.presets[rightValue]

        local leftOrder = -1
        local rightOrder = -1

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

    if not RTAutoResponseSave.presets[trimmedBaseName] then
        return trimmedBaseName
    end

    local copySuffix = " (copy)"
    local indexedPrefix = " (copy "
    local candidateName = LimitTextLength(trimmedBaseName, CONST.PRESET_NAME_MAX_LENGTH - string.len(copySuffix)) .. copySuffix

    if not RTAutoResponseSave.presets[candidateName] then
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

        if not RTAutoResponseSave.presets[candidateName] then
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

        if not RTAutoResponseSave.presets[candidateName] then
            return candidateName
        end

        newIndex = newIndex + 1
    end
end

local function GetActivePresetData()
    EnsureSavedVariables()

    local presetName = GetCharacterActivePresetName()
    if not presetName or presetName == "" then
        return nil
    end

    if presetName == CONST.CREATE_NEW_PRESET_LABEL then
        return nil
    end

    return RTAutoResponseSave.presets[presetName]
end

local function IsDefaultResponseDirty()
    if not UI.defaultResponseEditBox then
        return false
    end

    local presetData = GetActivePresetData()
    if not presetData then
        return false
    end

    local currentValue = LimitTextLength(UI.defaultResponseEditBox:GetText() or "", CONST.RESPONSE_MAX_LENGTH)
    local savedValue = LimitTextLength(presetData.defaultResponse or "", CONST.RESPONSE_MAX_LENGTH)

    return currentValue ~= savedValue
end

local function GetDeletePresetFallbackName(deletedPresetName)
    EnsureSavedVariables()

    local fallbackPresetName = STATE.lastSelectedPresetName

    if fallbackPresetName
        and fallbackPresetName ~= ""
        and fallbackPresetName ~= deletedPresetName
        and fallbackPresetName ~= CONST.CREATE_NEW_PRESET_LABEL
        and RTAutoResponseSave.presets[fallbackPresetName] then
        return fallbackPresetName
    end

    local sortedPresetNames = GetSortedPresetNames()
    local index = 1

    while index <= #sortedPresetNames do
        local presetName = sortedPresetNames[index]
        if presetName ~= CONST.CREATE_NEW_PRESET_LABEL and presetName ~= deletedPresetName and RTAutoResponseSave.presets[presetName] then
            return presetName
        end
        index = index + 1
    end

    return CONST.DEFAULT_PRESET_NAME
end

------------------------------------------------------------
-- COMMAND DATA HELPERS
------------------------------------------------------------

local function ClearCommandRows()
    wipe(DATA.commandRows)
    STATE.selectedCommandRow = nil
end

local function GetVisibleCommandRows()
    local visibleRows = {}
    local index = 1

    while index <= #DATA.commandRows do
        local row = DATA.commandRows[index]
        if row and not row.isDeleted then
            visibleRows[#visibleRows + 1] = row
        end
        index = index + 1
    end

    visibleRows[#visibleRows + 1] = SYSTEM_HELP_ROW
    return visibleRows
end

local function GetCommandRowIndex(targetRow)
    local index = 1

    while index <= #DATA.commandRows do
        if DATA.commandRows[index] == targetRow then
            return index
        end
        index = index + 1
    end

    return nil
end

local function SwapCommandRows(firstRow, secondRow)
    if not firstRow or not secondRow then
        return false
    end

    if firstRow == secondRow then
        return false
    end

    local firstIndex = GetCommandRowIndex(firstRow)
    local secondIndex = GetCommandRowIndex(secondRow)

    if not firstIndex or not secondIndex then
        return false
    end

    DATA.commandRows[firstIndex], DATA.commandRows[secondIndex] =
        DATA.commandRows[secondIndex], DATA.commandRows[firstIndex]

    return true
end

local function DoesCommandExist(commandText, ignoredRow)
    local normalizedTarget = NormalizeCommandText(commandText)
    if normalizedTarget == "" then
        return false
    end

    if IsReservedHelpAlias(normalizedTarget) then
        return true
    end

    local index = 1
    while index <= #DATA.commandRows do
        local row = DATA.commandRows[index]
        if row and not row.isDeleted and row ~= ignoredRow and not row.isSystemCommand then
            local normalizedExisting = NormalizeCommandText(row.command or "")
            if normalizedExisting ~= "" and normalizedExisting == normalizedTarget then
                return true
            end
        end
        index = index + 1
    end

    return false
end

local function GetSelectedCommandDraftValues()
    local commandText = ""
    local responseText = ""

    if UI.commandDetailCommandEditBox then
        commandText = SanitizeCommandText(UI.commandDetailCommandEditBox:GetText() or "")
    end

    if UI.commandDetailResponseEditBox then
        responseText = LimitTextLength(UI.commandDetailResponseEditBox:GetText() or "", CONST.RESPONSE_MAX_LENGTH)
    end

    return commandText, responseText
end

local function IsSelectedCommandDirty()
    if not STATE.selectedCommandRow or STATE.selectedCommandRow.isDeleted or STATE.selectedCommandRow.isSystemCommand then
        return false
    end

    local commandText, responseText = GetSelectedCommandDraftValues()

    return commandText ~= tostring(STATE.selectedCommandRow.command or "")
        or responseText ~= tostring(STATE.selectedCommandRow.response or "")
end

local function CanSaveSelectedCommand()
    if not IsCurrentPresetEditable() then
        return false
    end

    if not STATE.selectedCommandRow or STATE.selectedCommandRow.isDeleted or STATE.selectedCommandRow.isSystemCommand then
        return false
    end

    local commandText, responseText = GetSelectedCommandDraftValues()

    if commandText == tostring(STATE.selectedCommandRow.command or "")
        and responseText == tostring(STATE.selectedCommandRow.response or "") then
        return false
    end

    if TrimText(commandText) == "" then
        return false
    end

    if TrimText(responseText) == "" then
        return false
    end

    if IsReservedHelpAlias(commandText) then
        return false
    end

    if DoesCommandExist(commandText, STATE.selectedCommandRow) then
        return false
    end

    return true
end

local function RefreshCommandDuplicateState(row)
    if not row or row.isSystemCommand then
        return
    end

    row.hasDuplicate = false

    if TrimText(row.command or "") == "" then
        return
    end

    if IsReservedHelpAlias(row.command or "") then
        row.hasDuplicate = true
        return
    end

    row.hasDuplicate = DoesCommandExist(row.command or "", row)
end

local function RefreshAllDuplicateStates()
    local index = 1
    while index <= #DATA.commandRows do
        local row = DATA.commandRows[index]
        if row and not row.isDeleted then
            RefreshCommandDuplicateState(row)
        end
        index = index + 1
    end
end

local function SaveAllCommandRowsToPreset()
    if not IsCurrentPresetEditable() then
        return
    end

    FlushActivePresetToSavedVariables()
end

local function CreateCommandRow(commandValue, responseValue)
    local row = {
        command = SanitizeCommandText(commandValue or ""),
        response = LimitTextLength(responseValue or "", CONST.RESPONSE_MAX_LENGTH),
        isDeleted = false,
        hasDuplicate = false,
        isSystemCommand = false
    }

    if IsReservedHelpAlias(row.command) then
        row.command = ""
        row.response = ""
    end

    DATA.commandRows[#DATA.commandRows + 1] = row

    RefreshAllDuplicateStates()
    return row
end

------------------------------------------------------------
-- UI STATE REFRESH
------------------------------------------------------------

local function RefreshPresetActionButtons()
    local presetName = STATE.selectedPresetName
    local canRenameOrDelete = false
    local canImport = false
    local canExport = false

    EnsureSavedVariables()

    if presetName
        and presetName ~= ""
        and presetName ~= CONST.CREATE_NEW_PRESET_LABEL
        and RTAutoResponseSave.presets[presetName] then

        canExport = false
        canImport = true

        if not IsProtectedPreset(presetName) then
            canRenameOrDelete = true
            canExport = true
        end

    end

    if UI.renamePresetBtn then
        if canRenameOrDelete then UI.renamePresetBtn:Enable()
        else UI.renamePresetBtn:Disable() end
    end

    if UI.deletePresetBtn then
        if canRenameOrDelete then UI.deletePresetBtn:Enable()
        else UI.deletePresetBtn:Disable() end
    end

    if UI.importPresetBtn then
        if canImport then UI.importPresetBtn:Enable()
        else UI.importPresetBtn:Disable() end
    end

    if UI.exportPresetBtn then
        if canExport then UI.exportPresetBtn:Enable()
        else UI.exportPresetBtn:Disable() end
    end
end

local function RefreshEnableButton()
    if not UI.enableBtn then
        return
    end

    if STATE.isAutoResponseEnabled then
        UI.enableBtn:SetText("|cff00ff00Enabled|r")
    else
        UI.enableBtn:SetText("Enable Auto Reply")
    end
end

local function RefreshDefaultResponseSaveButton()
    if not UI.defaultResponseSaveBtn then
        return
    end

    local canSave = false

    if IsCurrentPresetEditable() and IsDefaultResponseDirty() then
        canSave = true
    end

    if STATE.defaultResponseSaveResetAt > 0 and GetTime() < STATE.defaultResponseSaveResetAt then
        UI.defaultResponseSaveBtn:SetText("|cff00ff00Saved|r")
    else
        UI.defaultResponseSaveBtn:SetText("Save")
        STATE.defaultResponseSaveResetAt = 0
    end

    if canSave then
        UI.defaultResponseSaveBtn:Enable()
    else
        UI.defaultResponseSaveBtn:Disable()
    end
end

local function RefreshDefaultResponseInputColor()
    if not UI.defaultResponseEditBox then
        return
    end

    if not IsCurrentPresetEditable() then
        UI.defaultResponseEditBox:SetTextColor(0.65, 0.65, 0.65)
        return
    end

    local presetData = GetActivePresetData()
    local currentValue = tostring(UI.defaultResponseEditBox:GetText() or "")
    local savedValue = ""

    if presetData then
        savedValue = tostring(presetData.defaultResponse or "")
    end

    if currentValue ~= savedValue then
        UI.defaultResponseEditBox:SetTextColor(0, 1, 0)
    else
        UI.defaultResponseEditBox:SetTextColor(1, 1, 1)
    end
end

local function RefreshDefaultResponseControlStates()
    local isEditable = IsCurrentPresetEditable()

    if UI.defaultResponseEditBox then
        SetEditBoxInteractionEnabled(UI.defaultResponseEditBox, isEditable)
    end

    if UI.commandDragInfoText then
        if isEditable then
            UI.commandDragInfoText:Show()
        else
            UI.commandDragInfoText:Hide()
        end
    end

    RefreshDefaultResponseSaveButton()
end

local function RefreshAddCommandButtonState()
    if not UI.addCommandBtn then
        return
    end

    if not IsCurrentPresetEditable() then
        UI.addCommandBtn:Disable()
        return
    end

    local lastRow = nil
    local index = #DATA.commandRows

    while index >= 1 do
        local row = DATA.commandRows[index]
        if row and not row.isDeleted and not row.isSystemCommand then
            lastRow = row
            break
        end
        index = index - 1
    end

    if not lastRow then
        UI.addCommandBtn:Enable()
        return
    end

    local commandText = TrimText(lastRow.command or "")
    local responseText = TrimText(lastRow.response or "")

    if commandText == "" or responseText == "" then
        UI.addCommandBtn:Disable()
    else
        UI.addCommandBtn:Enable()
    end
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

    if RTAutoResponseSave.presets[finalName] then
        return
    end

    RTAutoResponseSave.presets[finalName] = CopyPresetData(RTAutoResponseSave.presets[oldName])
    if type(RTAutoResponseSave.presets[oldName]) == "table" and type(RTAutoResponseSave.presets[oldName].order) == "number" then
        RTAutoResponseSave.presets[finalName].order = RTAutoResponseSave.presets[oldName].order
    end
    RTAutoResponseSave.presets[oldName] = nil

    SetSelectedPresetName(finalName)
    StopRenameMode()
    RefreshPresetActionButtons()
end

------------------------------------------------------------
-- COMMAND DETAIL UI
------------------------------------------------------------

local RefreshCommandDragVisuals

local function RefreshCommandListButtonText(button)
    if not button or not button.row then
        return
    end

    local commandText = TrimText(button.row.command or "")

    if button.row.isSystemCommand then
        commandText = CONST.HELP_COMMAND_DISPLAY_TEXT
    elseif commandText == "" then
        commandText = "<New Command>"
    end

    if button.row.hasDuplicate then
        commandText = commandText .. " |cffff3b30(Dup)|r"
    end

    button:SetText(commandText)
end

local function RefreshSelectedCommandListPreview()
    if not STATE.selectedCommandRow or STATE.selectedCommandRow.isDeleted or STATE.selectedCommandRow.isSystemCommand then
        return
    end

    if not UI.commandDetailCommandEditBox then
        return
    end

    local buttonIndex = 1
    local selectedButton = nil

    while buttonIndex <= #UI.commandListButtons do
        local currentButton = UI.commandListButtons[buttonIndex]
        if currentButton and currentButton.row == STATE.selectedCommandRow then
            selectedButton = currentButton
            break
        end
        buttonIndex = buttonIndex + 1
    end

    if not selectedButton then
        return
    end

    local draftCommandText = SanitizeCommandText(UI.commandDetailCommandEditBox:GetText() or "")
    local displayText = TrimText(draftCommandText or "")

    if displayText == "" then
        displayText = "<New Command>"
    end

    if IsReservedHelpAlias(draftCommandText or "") or DoesCommandExist(draftCommandText or "", STATE.selectedCommandRow) then
        displayText = displayText .. " |cffff3b30(Dup)|r"
    end

    if STATE.isDraggingCommandRow and selectedButton.row == STATE.draggedCommandRow then
        displayText = "<< " .. displayText .. " >>"
    elseif STATE.isDraggingCommandRow
        and STATE.dragHoverTargetRow
        and selectedButton.row == STATE.dragHoverTargetRow
        and selectedButton.row ~= STATE.draggedCommandRow then
        displayText = "[[ " .. displayText .. " ]]"
    end

    selectedButton:SetText(displayText)

    if selectedButton:GetFontString() then
        selectedButton:GetFontString():SetTextColor(0, 1, 0)
    end
end

local function RefreshCommandButtonSelection()
    local index = 1

    while index <= #UI.commandListButtons do
        local button = UI.commandListButtons[index]
        if button and button.row and button:GetFontString() then
            RefreshCommandListButtonText(button)

            if button.row == STATE.selectedCommandRow then
                button:GetFontString():SetTextColor(0, 1, 0)
            elseif button.row.isSystemCommand then
                button:GetFontString():SetTextColor(0.75, 0.75, 0.75)
            else
                button:GetFontString():SetTextColor(1, 0.82, 0)
            end
        end
        index = index + 1
    end

    RefreshSelectedCommandListPreview()
end

local function RefreshCommandDetailInputColors()
    if not STATE.selectedCommandRow or STATE.selectedCommandRow.isDeleted then
        if UI.commandDetailCommandEditBox then
            UI.commandDetailCommandEditBox:SetTextColor(0.65, 0.65, 0.65)
        end

        if UI.commandDetailResponseEditBox then
            UI.commandDetailResponseEditBox:SetTextColor(0.65, 0.65, 0.65)
        end
        return
    end

    if not IsCurrentPresetEditable() then
        if UI.commandDetailCommandEditBox then
            if STATE.selectedCommandRow.isSystemCommand then
                UI.commandDetailCommandEditBox:SetTextColor(1, 0.82, 0)
            else
                UI.commandDetailCommandEditBox:SetTextColor(0.65, 0.65, 0.65)
            end
        end

        if UI.commandDetailResponseEditBox then
            UI.commandDetailResponseEditBox:SetTextColor(0.65, 0.65, 0.65)
        end
        return
    end

    if STATE.selectedCommandRow.isSystemCommand then
        if UI.commandDetailCommandEditBox then
            UI.commandDetailCommandEditBox:SetTextColor(1, 0.82, 0)
        end

        if UI.commandDetailResponseEditBox then
            UI.commandDetailResponseEditBox:SetTextColor(1, 1, 1)
        end
        return
    end

    local currentCommandText = ""
    local currentResponseText = ""

    if UI.commandDetailCommandEditBox then
        currentCommandText = SanitizeCommandText(UI.commandDetailCommandEditBox:GetText() or "")
    end

    if UI.commandDetailResponseEditBox then
        currentResponseText = LimitTextLength(UI.commandDetailResponseEditBox:GetText() or "", CONST.RESPONSE_MAX_LENGTH)
    end

    if UI.commandDetailCommandEditBox then
        if currentCommandText ~= tostring(STATE.selectedCommandRow.command or "") then
            UI.commandDetailCommandEditBox:SetTextColor(0, 1, 0)
        else
            UI.commandDetailCommandEditBox:SetTextColor(1, 1, 1)
        end
    end

    if UI.commandDetailResponseEditBox then
        if currentResponseText ~= tostring(STATE.selectedCommandRow.response or "") then
            UI.commandDetailResponseEditBox:SetTextColor(0, 1, 0)
        else
            UI.commandDetailResponseEditBox:SetTextColor(1, 1, 1)
        end
    end
end

local function RefreshCommandDetailControlStates()
    if not UI.commandDetailCommandEditBox or not UI.commandDetailResponseEditBox or not UI.commandDetailSaveBtn or not UI.commandDetailDeleteBtn then
        return
    end

    if not STATE.selectedCommandRow or STATE.selectedCommandRow.isDeleted then
        SetEditBoxInteractionEnabled(UI.commandDetailCommandEditBox, false)
        SetEditBoxInteractionEnabled(UI.commandDetailResponseEditBox, false)
        UI.commandDetailSaveBtn:Disable()
        UI.commandDetailDeleteBtn:Disable()
        return
    end

    if not IsCurrentPresetEditable() then
        SetEditBoxInteractionEnabled(UI.commandDetailCommandEditBox, false)
        SetEditBoxInteractionEnabled(UI.commandDetailResponseEditBox, false)
        UI.commandDetailSaveBtn:Disable()
        UI.commandDetailDeleteBtn:Disable()
        return
    end

    if STATE.selectedCommandRow.isSystemCommand then
        SetEditBoxInteractionEnabled(UI.commandDetailCommandEditBox, false)
        SetEditBoxInteractionEnabled(UI.commandDetailResponseEditBox, false)
        UI.commandDetailSaveBtn:Disable()
        UI.commandDetailDeleteBtn:Disable()
        return
    end

    SetEditBoxInteractionEnabled(UI.commandDetailCommandEditBox, true)
    SetEditBoxInteractionEnabled(UI.commandDetailResponseEditBox, true)

    if CanSaveSelectedCommand() then
        UI.commandDetailSaveBtn:Enable()
    else
        UI.commandDetailSaveBtn:Disable()
    end

    UI.commandDetailDeleteBtn:Enable()
end

local function UpdateCommandDetailDirtyState()
    if not UI.commandDetailStatusText then
        return
    end

    if not STATE.selectedCommandRow or STATE.selectedCommandRow.isDeleted then
        UI.commandDetailStatusText:SetText("")
        UI.commandDetailStatusText:Hide()
        RefreshCommandDetailInputColors()
        return
    end

    if not IsCurrentPresetEditable() then
        UI.commandDetailStatusText:SetText("|cffaaaaaaDefault preset is locked and cannot be edited.|r")
        UI.commandDetailStatusText:Show()
        RefreshCommandDetailInputColors()
        return
    end

    if STATE.selectedCommandRow.isSystemCommand then
        UI.commandDetailStatusText:SetText("|cffaaaaaaThis command is built-in and cannot be edited or deleted.|r")
        UI.commandDetailStatusText:Show()
        RefreshCommandDetailInputColors()
        return
    end

    local currentCommandText = ""
    local currentResponseText = ""

    if UI.commandDetailCommandEditBox then
        currentCommandText = SanitizeCommandText(UI.commandDetailCommandEditBox:GetText() or "")
    end

    if UI.commandDetailResponseEditBox then
        currentResponseText = LimitTextLength(UI.commandDetailResponseEditBox:GetText() or "", CONST.RESPONSE_MAX_LENGTH)
    end

    RefreshCommandDetailInputColors()

    if currentCommandText ~= tostring(STATE.selectedCommandRow.command or "") or currentResponseText ~= tostring(STATE.selectedCommandRow.response or "") then
        if TrimText(currentCommandText) == "" then
            UI.commandDetailStatusText:SetText("|cffff3b30Command Required|r")
            UI.commandDetailStatusText:Show()
        elseif TrimText(currentResponseText) == "" then
            UI.commandDetailStatusText:SetText("|cffff3b30Response Required|r")
            UI.commandDetailStatusText:Show()
        elseif IsReservedHelpAlias(currentCommandText) then
            UI.commandDetailStatusText:SetText("|cffff3b30Reserved Command|r")
            UI.commandDetailStatusText:Show()
        elseif DoesCommandExist(currentCommandText, STATE.selectedCommandRow) then
            UI.commandDetailStatusText:SetText("|cffff3b30Duplicate Command|r")
            UI.commandDetailStatusText:Show()
        else
            UI.commandDetailStatusText:SetText("|cffffff00Not Saved|r")
            UI.commandDetailStatusText:Show()
        end
    else
        UI.commandDetailStatusText:SetText("")
        UI.commandDetailStatusText:Hide()
    end

    RefreshCommandDetailControlStates()
    RefreshCommandDragVisuals()
end

local function LoadSelectedCommandToDetailPanel()
    if not UI.commandDetailPanel then
        return
    end

    if not STATE.selectedCommandRow or STATE.selectedCommandRow.isDeleted then
        UI.commandDetailPanel:Hide()

        if UI.commandDetailEmptyText then
            UI.commandDetailEmptyText:Show()
        end

        RefreshCommandDetailControlStates()
        RefreshCommandDetailInputColors()
        return
    end

    if UI.commandDetailEmptyText then
        UI.commandDetailEmptyText:Hide()
    end

    UI.commandDetailPanel:Show()

    if STATE.selectedCommandRow.isSystemCommand then
        if UI.commandDetailCommandEditBox then
            UI.commandDetailCommandEditBox:SetText(CONST.HELP_COMMAND_DISPLAY_TEXT)
        end

        if UI.commandDetailResponseEditBox then
            UI.commandDetailResponseEditBox:SetText("This is a built-in command. Players can type ?help, ?command or ?commands to receive the full command list.")
        end
    else
        if UI.commandDetailCommandEditBox then
            UI.commandDetailCommandEditBox:SetText(STATE.selectedCommandRow.command or "")
        end

        if UI.commandDetailResponseEditBox then
            UI.commandDetailResponseEditBox:SetText(STATE.selectedCommandRow.response or "")
        end
    end

    RefreshCommandDetailControlStates()
    RefreshCommandDetailInputColors()
    UpdateCommandDetailDirtyState()
    RefreshCommandButtonSelection()
end

local function SelectCommandRow(row)
    STATE.selectedCommandRow = row
    LoadSelectedCommandToDetailPanel()
end

local function SelectTopVisibleCommandRow()
    local visibleRows = GetVisibleCommandRows()

    if visibleRows[1] then
        SelectCommandRow(visibleRows[1])
    else
        SelectCommandRow(nil)
    end
end

local function ClearCommandListButtons()
    local index = 1

    while index <= #UI.commandListButtons do
        local button = UI.commandListButtons[index]
        if button then
            button:Hide()
            button:ClearAllPoints()
            button.row = nil
            button:SetText("")
            button:SetParent(UI.commandContentFrame)
        end
        index = index + 1
    end
end

RefreshCommandDragVisuals = function()
    local index = 1

    while index <= #UI.commandListButtons do
        local button = UI.commandListButtons[index]

        if button then
            RefreshCommandListButtonText(button)

            local text = button:GetText() or ""
            text = text:gsub("^<<%s*", "")
            text = text:gsub("%s*>>$", "")
            text = text:gsub("^%[%[%s*", "")
            text = text:gsub("%s*%]%]$", "")

            if STATE.isDraggingCommandRow and button.row == STATE.draggedCommandRow then
                button:SetText("<< " .. text .. " >>")
            elseif STATE.isDraggingCommandRow and STATE.dragHoverTargetRow and button.row == STATE.dragHoverTargetRow and button.row ~= STATE.draggedCommandRow then
                button:SetText("[[ " .. text .. " ]]")
            end
        end

        index = index + 1
    end
end

local function StartCommandRowDrag(row)
    if not row or row.isDeleted or row.isSystemCommand then
        return
    end

    if not IsCurrentPresetEditable() then
        return
    end

    STATE.draggedCommandRow = row
    STATE.dragHoverTargetRow = nil
    STATE.isDraggingCommandRow = true

    SelectCommandRow(row)
    RefreshCommandButtonSelection()
    RefreshCommandDragVisuals()
end

local function StopCommandRowDrag()
    STATE.draggedCommandRow = nil
    STATE.dragHoverTargetRow = nil
    STATE.isDraggingCommandRow = false
    RefreshCommandDragVisuals()
end

local function RefreshCommandListUI()
    if not UI.commandContentFrame then
        return
    end

    ClearCommandListButtons()

    local visibleRows = GetVisibleCommandRows()
    local index = 1

    while index <= #visibleRows do
        local row = visibleRows[index]
        local button = UI.commandListButtons[index]

        if not button then
            button = CreateFrame("Button", nil, UI.commandContentFrame, "UIPanelButtonTemplate")
            button:SetHeight(24)
            button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            TrySkinButton(button)

            UI.commandListButtons[index] = button
        end

        button:Show()
        button:SetParent(UI.commandContentFrame)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", 0, -((index - 1) * 28))
        button:SetPoint("TOPRIGHT", 0, -((index - 1) * 28))
        button.row = row

        RefreshCommandListButtonText(button)

                button:SetScript("OnClick", function(self, mouseButton)
            local row = self.row

            if not row then
                return
            end

            if row.isSystemCommand or row.isDeleted then
                if STATE.isDraggingCommandRow then
                    StopCommandRowDrag()
                end
                return
            end

            if not IsCurrentPresetEditable() then
                if mouseButton == "LeftButton" then
                    SelectCommandRow(row)
                end
                return
            end

            if mouseButton == "RightButton" then
                if STATE.isDraggingCommandRow and STATE.draggedCommandRow then
                    if STATE.draggedCommandRow == row then
                        SelectCommandRow(row)
                        RefreshCommandButtonSelection()
                        RefreshCommandDragVisuals()
                        return
                    end

                    if SwapCommandRows(STATE.draggedCommandRow, row) then
                        FlushActivePresetToSavedVariables()
                        StopCommandRowDrag()
                        RefreshCommandListUI()
                        SelectCommandRow(row)
                    else
                        StopCommandRowDrag()
                    end
                    return
                end

                StartCommandRowDrag(row)
                return
            end

            if STATE.isDraggingCommandRow and STATE.draggedCommandRow then
                if STATE.draggedCommandRow == row then
                    SelectCommandRow(row)
                    RefreshCommandButtonSelection()
                    RefreshCommandDragVisuals()
                    return
                end

                if SwapCommandRows(STATE.draggedCommandRow, row) then
                    FlushActivePresetToSavedVariables()
                    StopCommandRowDrag()
                    RefreshCommandListUI()
                    SelectCommandRow(row)
                else
                    StopCommandRowDrag()
                end
                return
            end

            if mouseButton == "LeftButton" then
                SelectCommandRow(row)
                return
            end
        end)

        button:SetScript("OnEnter", function(self)
            if not STATE.isDraggingCommandRow then
                return
            end

            if not self.row or self.row.isDeleted or self.row.isSystemCommand then
                STATE.dragHoverTargetRow = nil
                RefreshCommandDragVisuals()
                return
            end

            if self.row == STATE.draggedCommandRow then
                STATE.dragHoverTargetRow = nil
            else
                STATE.dragHoverTargetRow = self.row
            end

            RefreshCommandDragVisuals()
        end)

        button:SetScript("OnLeave", function(self)
            if not STATE.isDraggingCommandRow then
                return
            end

            if STATE.dragHoverTargetRow == self.row then
                STATE.dragHoverTargetRow = nil
                RefreshCommandDragVisuals()
            end
        end)

        button:SetScript("OnMouseDown", nil)
        button:SetScript("OnMouseUp", nil)

        index = index + 1
    end

    local hideIndex = #visibleRows + 1
    while hideIndex <= #UI.commandListButtons do
        local button = UI.commandListButtons[hideIndex]
        if button then
            button:Hide()
            button:ClearAllPoints()
            button.row = nil
            button:SetText("")
            if button.dragHighlight then
                button.dragHighlight:Hide()
            end
        end
        hideIndex = hideIndex + 1
    end

    local totalHeight = (#visibleRows * 28)
    if totalHeight < 1 then
        totalHeight = 1
    end

    UI.commandContentFrame:SetHeight(totalHeight)

    RefreshCommandButtonSelection()
    RefreshCommandDragVisuals()
end

------------------------------------------------------------
-- COMMAND ACTIONS
------------------------------------------------------------

local function SaveSelectedCommandDetail()
    if not IsCurrentPresetEditable() then
        if UI.commandDetailStatusText then
            UI.commandDetailStatusText:SetText("|cffaaaaaaDefault preset is locked and cannot be edited.|r")
            UI.commandDetailStatusText:Show()
        end
        return
    end

    if not STATE.selectedCommandRow or STATE.selectedCommandRow.isDeleted then
        return
    end

    if STATE.selectedCommandRow.isSystemCommand then
        return
    end

    local commandText = SanitizeCommandText(UI.commandDetailCommandEditBox:GetText() or "")
    local responseText = LimitTextLength(UI.commandDetailResponseEditBox:GetText() or "", CONST.RESPONSE_MAX_LENGTH)

    if TrimText(commandText) == "" then
        if UI.commandDetailStatusText then
            UI.commandDetailStatusText:SetText("|cffff3b30Command Required|r")
            UI.commandDetailStatusText:Show()
        end
        return
    end

    if TrimText(responseText) == "" then
        if UI.commandDetailStatusText then
            UI.commandDetailStatusText:SetText("|cffff3b30Response Required|r")
            UI.commandDetailStatusText:Show()
        end
        return
    end

    if IsReservedHelpAlias(commandText) then
        if UI.commandDetailStatusText then
            UI.commandDetailStatusText:SetText("|cffff3b30Reserved Command|r")
            UI.commandDetailStatusText:Show()
        end
        return
    end

    if DoesCommandExist(commandText, STATE.selectedCommandRow) then
        if UI.commandDetailStatusText then
            UI.commandDetailStatusText:SetText("|cffff3b30Duplicate Command|r")
            UI.commandDetailStatusText:Show()
        end
        return
    end

    STATE.selectedCommandRow.command = commandText
    STATE.selectedCommandRow.response = responseText

    RefreshAllDuplicateStates()
    FlushActivePresetToSavedVariables()
    RefreshCommandListUI()
    RefreshAddCommandButtonState()
    LoadSelectedCommandToDetailPanel()
    RefreshCommandDetailInputColors()
    RefreshCommandDetailControlStates()
    RefreshSelectedCommandListPreview()

    if UI.commandDetailStatusText then
        UI.commandDetailStatusText:SetText("")
        UI.commandDetailStatusText:Hide()
    end
end

local function DeleteSelectedCommandDetailConfirmed()
    if not IsCurrentPresetEditable() then
        return
    end

    if not STATE.selectedCommandRow or STATE.selectedCommandRow.isDeleted then
        return
    end

    if STATE.selectedCommandRow.isSystemCommand then
        return
    end

    STATE.selectedCommandRow.isDeleted = true
    STATE.selectedCommandRow = nil

    RefreshAllDuplicateStates()
    FlushActivePresetToSavedVariables()
    RefreshCommandListUI()
    SelectTopVisibleCommandRow()
    RefreshAddCommandButtonState()
end

local function GetSelectedCommandDisplayName()
    if not STATE.selectedCommandRow or STATE.selectedCommandRow.isDeleted then
        return "this command"
    end

    if STATE.selectedCommandRow.isSystemCommand then
        return CONST.HELP_COMMAND_DISPLAY_TEXT
    end

    local commandText = TrimText(STATE.selectedCommandRow.command or "")
    if commandText == "" then
        return "<New Command>"
    end

    return commandText
end

local function ShowDeleteSelectedCommandPopup()
    if not STATE.selectedCommandRow or STATE.selectedCommandRow.isDeleted then
        return
    end

    if STATE.selectedCommandRow.isSystemCommand then
        return
    end

    if not IsCurrentPresetEditable() then
        return
    end

    StaticPopup_Show(CONST.AUTO_RESPONSE_COMMAND_DELETE_POPUP, GetSelectedCommandDisplayName())
end

------------------------------------------------------------
-- DEFAULT RESPONSE ACTIONS
------------------------------------------------------------

local function SaveDefaultResponse()
    if not IsCurrentPresetEditable() then
        return
    end

    local presetData = GetActivePresetData()
    if not presetData then
        return
    end

    if not UI.defaultResponseEditBox then
        return
    end

    presetData.defaultResponse = LimitTextLength(UI.defaultResponseEditBox:GetText() or "", CONST.RESPONSE_MAX_LENGTH)

    FlushActivePresetToSavedVariables()

    STATE.defaultResponseSaveResetAt = GetTime() + 3
    RefreshDefaultResponseSaveButton()
    RefreshDefaultResponseInputColor()
    RefreshDefaultResponseControlStates()
end

------------------------------------------------------------
-- PRESET LOAD / CREATE / DELETE
------------------------------------------------------------

local function LoadPresetIntoUI(presetName, shouldDisableAutoResponse)
    EnsureSavedVariables()

    if not presetName or presetName == "" then
        return
    end

    if not RTAutoResponseSave.presets[presetName] then
        return
    end

    local presetData = RTAutoResponseSave.presets[presetName]

    if shouldDisableAutoResponse then
        DisableAutoResponse()
    end

    SetSelectedPresetName(presetName)
    RefreshPresetActionButtons()
    StopRenameMode()

    if UI.defaultResponseEditBox then
        UI.defaultResponseEditBox:SetText(presetData.defaultResponse or "")
    end

    if UI.defaultResponseCharCountText and UI.defaultResponseEditBox then
        local currentLength = string.len(UI.defaultResponseEditBox:GetText() or "")
        UI.defaultResponseCharCountText:SetText(string.format("Characters: %d/%d", currentLength, CONST.RESPONSE_MAX_LENGTH))
    end

    STATE.defaultResponseSaveResetAt = 0
    RefreshDefaultResponseSaveButton()
    RefreshDefaultResponseInputColor()

    ClearCommandRows()
    ClearCommandListButtons()

    local index = 1
    while presetData.commands and presetData.commands[index] do
        local commandData = presetData.commands[index]
        CreateCommandRow(commandData.command or "", commandData.response or "")
        index = index + 1
    end

    RefreshAllDuplicateStates()
    RefreshAddCommandButtonState()
    RefreshCommandListUI()
    SelectTopVisibleCommandRow()
    RefreshDefaultResponseControlStates()
end

local function CreateNewPreset()
    EnsureSavedVariables()
    FlushActivePresetToSavedVariables()

    local presetName = GetNextNewPresetName()
    local newPresetData = CopyPresetData({
        defaultResponse = "",
        commands = {}
    })

    RTAutoResponseSave.presetOrderCounter = RTAutoResponseSave.presetOrderCounter + 1
    newPresetData.order = RTAutoResponseSave.presetOrderCounter

    RTAutoResponseSave.presets[presetName] = newPresetData
    local characterKey = GetCharacterKey()
    if type(RTAutoResponseSave.characterSettings) ~= "table" then
        RTAutoResponseSave.characterSettings = {}
    end
    if type(RTAutoResponseSave.characterSettings[characterKey]) ~= "table" then
        RTAutoResponseSave.characterSettings[characterKey] = {}
    end
    RTAutoResponseSave.characterSettings[characterKey].activePresetName = presetName
    RTAutoResponseSave.activePresetName = presetName

    LoadPresetIntoUI(presetName, true)
end

local function DeletePresetConfirmed(presetName)
    if not presetName or presetName == "" then
        return
    end

    EnsureSavedVariables()

    if presetName == CONST.CREATE_NEW_PRESET_LABEL then
        return
    end

    if IsProtectedPreset(presetName) then
        return
    end

    if not RTAutoResponseSave.presets[presetName] then
        return
    end

    RTAutoResponseSave.presets[presetName] = nil

    local fallbackPresetName = GetDeletePresetFallbackName(presetName)
    SetSelectedPresetName(fallbackPresetName)
    LoadPresetIntoUI(fallbackPresetName, true)
end

local function GetSelectedPresetDisplayName()
    local presetName = GetSelectedPresetName()
    if not presetName or presetName == "" then
        return "this preset"
    end
    return presetName
end

local function ShowDeletePresetPopup()
    local presetName = GetSelectedPresetName()
    if not presetName or presetName == "" then
        return
    end

    if presetName == CONST.CREATE_NEW_PRESET_LABEL then
        return
    end

    if IsProtectedPreset(presetName) then
        return
    end

    StaticPopup_Show(CONST.AUTO_RESPONSE_PRESET_DELETE_POPUP, GetSelectedPresetDisplayName())
end

------------------------------------------------------------
-- IMPORT / EXPORT
------------------------------------------------------------

local function ParseTransferRecord(line)
    local normalizedLine = tostring(line or "")

    normalizedLine = string.gsub(normalizedLine, "|+", "|")

    local firstSeparatorIndex = string.find(normalizedLine, "|", 1, true)
    if not firstSeparatorIndex then
        return nil, nil, nil
    end

    local recordType = string.sub(normalizedLine, 1, firstSeparatorIndex - 1)
    local payload = string.sub(normalizedLine, firstSeparatorIndex + 1)

    if recordType == "NAME" or recordType == "DEFAULT" then
        return recordType, payload, nil
    end

    if recordType == "COMMAND" then
        local secondSeparatorIndex = string.find(payload, "|", 1, true)
        if not secondSeparatorIndex then
            return recordType, nil, nil
        end

        local firstValue = string.sub(payload, 1, secondSeparatorIndex - 1)
        local secondValue = string.sub(payload, secondSeparatorIndex + 1)
        return recordType, firstValue, secondValue
    end

    return recordType, payload, nil
end

local function SerializePresetToString(presetName)
    EnsureSavedVariables()
    FlushActivePresetToSavedVariables()

    if not presetName or presetName == "" then
        return ""
    end

    local presetData = RTAutoResponseSave.presets[presetName]
    if not presetData then
        return ""
    end

    local resultLines = {}
    resultLines[#resultLines + 1] = "ARPRESET|1"
    resultLines[#resultLines + 1] = "NAME|" .. EncodeTransferValue(presetName)
    resultLines[#resultLines + 1] = "DEFAULT|" .. EncodeTransferValue(presetData.defaultResponse or "")

    local index = 1
    while presetData.commands and presetData.commands[index] do
        local commandData = presetData.commands[index]
        resultLines[#resultLines + 1] =
            "COMMAND|" ..
            EncodeTransferValue(commandData.command or "") ..
            "|" ..
            EncodeTransferValue(commandData.response or "")
        index = index + 1
    end

    return table.concat(resultLines, "\n")
end

local function BuildImportedPresetData(importedData)
    local result = {
        defaultResponse = "",
        commands = {}
    }

    if type(importedData) ~= "table" then
        return nil
    end

    result.defaultResponse = LimitTextLength(tostring(importedData.defaultResponse or ""), CONST.RESPONSE_MAX_LENGTH)

    if type(importedData.commands) == "table" then
        local index = 1
        while importedData.commands[index] do
            local entry = importedData.commands[index]
            if type(entry) == "table" then
                local copiedEntry = CopyCommandEntry(entry)
                if copiedEntry.command ~= "" and copiedEntry.response ~= "" then
                    result.commands[#result.commands + 1] = {
                        command = copiedEntry.command,
                        response = copiedEntry.response
                    }
                end
            end
            index = index + 1
        end
    end

    return result
end

local function HidePresetTransferFrame()
    STATE.presetTransferMode = nil

    if UI.presetTransferEditBox then
        UI.presetTransferEditBox:ClearFocus()
    end

    if UI.presetTransferStatusText then
        UI.presetTransferStatusText:SetText("")
        UI.presetTransferStatusText:Hide()
    end

    if UI.presetTransferFrame then
        UI.presetTransferFrame:Hide()
    end
end

local function ImportPresetFromText(rawText)
    EnsureSavedVariables()

    local importText = tostring(rawText or "")

    -- Safer normalize
    importText = string.gsub(importText, "^\239\187\191", "")
    importText = string.gsub(importText, "\r\n", "\n")
    importText = string.gsub(importText, "\r", "\n")
    importText = string.gsub(importText, "\194\160", " ")

    local function CleanLineText(text)
        local result = tostring(text or "")
        result = string.gsub(result, "^\239\187\191", "")
        result = string.gsub(result, "\194\160", " ")
        result = string.gsub(result, "[\r\t]", "")
        result = string.gsub(result, "^%s+", "")
        result = string.gsub(result, "%s+$", "")
        result = string.gsub(result, "[%z\1-\8\11\12\14-\31\127-\159]", "")
        return result
    end

    local function ToByteString(text)
        local result = {}
        local index = 1

        while index <= string.len(text) do
            result[#result + 1] = tostring(string.byte(text, index))
            index = index + 1
        end

        return table.concat(result, ",")
    end

    importText = TrimText(importText)

    if importText == "" then
        return false, "Import text is empty."
    end

    local parsedData = {
        name = "",
        defaultResponse = "",
        commands = {}
    }

    local normalizedLines = {}

    for line in string.gmatch(importText, "([^\n]*)\n?") do
        if line ~= nil and line ~= "" then
            local cleanLine = CleanLineText(line)
            cleanLine = string.gsub(cleanLine, "|+", "|")
            if cleanLine ~= "" then
                normalizedLines[#normalizedLines + 1] = cleanLine
            end
        end
    end

    if #normalizedLines == 0 then
        return false, "Import text is empty."
    end

    local firstLine = string.match(importText, "([^\n]+)") or ""
    firstLine = CleanLineText(firstLine)
    firstLine = string.gsub(firstLine, "|+", "|")

    if firstLine ~= "ARPRESET|1" then
        print(ToByteString(firstLine))
        return false,
            "Import text header is invalid. First line: [" ..
            tostring(firstLine) ..
            "]"
    end

    local lineIndex = 2
    while lineIndex <= #normalizedLines do
        local line = normalizedLines[lineIndex]
        local recordType, firstValue, secondValue = ParseTransferRecord(line)
        recordType = tostring(recordType or "")

        if recordType == "NAME" then
            if firstValue == nil then
                return false, "Invalid NAME line."
            end

            local decodedName = DecodeTransferValue(firstValue)
            if decodedName == nil then
                return false, "Preset name could not be decoded."
            end

            parsedData.name = decodedName

        elseif recordType == "DEFAULT" then
            if firstValue == nil then
                return false, "Invalid DEFAULT line."
            end

            local decodedDefaultResponse = DecodeTransferValue(firstValue)
            if decodedDefaultResponse == nil then
                return false, "Default response could not be decoded."
            end

            parsedData.defaultResponse = decodedDefaultResponse

        elseif recordType == "COMMAND" then
            if firstValue == nil or secondValue == nil then
                return false, "Invalid COMMAND line."
            end

            local decodedCommand = DecodeTransferValue(firstValue)
            local decodedResponse = DecodeTransferValue(secondValue)

            if decodedCommand == nil or decodedResponse == nil then
                return false, "A command line could not be decoded."
            end

            parsedData.commands[#parsedData.commands + 1] = {
                command = decodedCommand,
                response = decodedResponse
            }

        else
            return false, "Unknown import line: " .. recordType
        end

        lineIndex = lineIndex + 1
    end

    local importedPresetData = BuildImportedPresetData(parsedData)
    if not importedPresetData then
        return false, "Imported preset data is invalid."
    end

    local importedName = LimitTextLength(TrimText(parsedData.name or ""), CONST.PRESET_NAME_MAX_LENGTH)
    if importedName == "" then
        importedName = CONST.CREATE_NEW_PRESET_BASE_NAME
    end

    if importedName == CONST.DEFAULT_PRESET_NAME then
        importedName = CONST.CREATE_NEW_PRESET_BASE_NAME
    end

    if importedName == CONST.CREATE_NEW_PRESET_LABEL then
        importedName = CONST.CREATE_NEW_PRESET_BASE_NAME
    end

    local finalPresetName = GetUniquePresetName(importedName)
    if finalPresetName == "" then
        finalPresetName = GetNextNewPresetName()
    end

    local finalPresetData = CopyPresetData(importedPresetData)
    RTAutoResponseSave.presetOrderCounter = RTAutoResponseSave.presetOrderCounter + 1
    finalPresetData.order = RTAutoResponseSave.presetOrderCounter

    RTAutoResponseSave.presets[finalPresetName] = finalPresetData
    local characterKey = GetCharacterKey()
    if type(RTAutoResponseSave.characterSettings) ~= "table" then
        RTAutoResponseSave.characterSettings = {}
    end
    if type(RTAutoResponseSave.characterSettings[characterKey]) ~= "table" then
        RTAutoResponseSave.characterSettings[characterKey] = {}
    end
    RTAutoResponseSave.characterSettings[characterKey].activePresetName = finalPresetName
    RTAutoResponseSave.activePresetName = finalPresetName

    LoadPresetIntoUI(finalPresetName, true)
    return true, nil
end

local function ShowPresetTransferFrame(mode)
    if not UI.presetTransferFrame or not UI.presetTransferEditBox or not UI.presetTransferTitleText then
        return
    end

    STATE.presetTransferMode = mode

    if UI.presetTransferStatusText then
        UI.presetTransferStatusText:SetText("")
        UI.presetTransferStatusText:Hide()
    end

    if mode == "export" then
        local presetName = GetSelectedPresetName()
        local exportText = SerializePresetToString(presetName)
        print("EXPORT_FIRST_LINE:", tostring(string.match(exportText, "([^\n]+)") or ""))

        UI.presetTransferTitleText:SetText(CONST.PRESET_TRANSFER_EXPORT_TITLE)
        UI.presetTransferEditBox:SetText(exportText)
        UI.presetTransferEditBox.lastReadOnlyText = exportText
        SetEditBoxReadOnly(UI.presetTransferEditBox, true)

        if UI.presetTransferConfirmBtn then
            UI.presetTransferConfirmBtn:SetText("Copy")
        end

        if UI.presetTransferCancelBtn then
            UI.presetTransferCancelBtn:SetText("Close")
        end
    elseif mode == "import" then
        UI.presetTransferTitleText:SetText(CONST.PRESET_TRANSFER_IMPORT_TITLE)
        UI.presetTransferEditBox:SetText("")
        UI.presetTransferEditBox.lastReadOnlyText = ""
        SetEditBoxReadOnly(UI.presetTransferEditBox, false)

        if UI.presetTransferConfirmBtn then
            UI.presetTransferConfirmBtn:SetText("Import")
        end

        if UI.presetTransferCancelBtn then
            UI.presetTransferCancelBtn:SetText("Cancel")
        end
    else
        return
    end

    UI.presetTransferFrame:ClearAllPoints()
    UI.presetTransferFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    UI.presetTransferFrame:Show()
    UI.presetTransferFrame:Raise()

    if mode == "export" then
        UI.presetTransferEditBox:SetFocus()
        UI.presetTransferEditBox:HighlightText()
    else
        UI.presetTransferEditBox:SetFocus()
    end
end

local function OnPresetTransferConfirmClick()
    if STATE.presetTransferMode == "export" then
        if UI.presetTransferEditBox then
            UI.presetTransferEditBox:SetFocus()
            UI.presetTransferEditBox:HighlightText()
        end

        if UI.presetTransferStatusText then
            UI.presetTransferStatusText:SetText("|cffffff00All text selected. Press Ctrl+C to copy.|r")
            UI.presetTransferStatusText:Show()
        end

        return
    end

    if STATE.presetTransferMode == "import" then
        local didImport, errorMessage = ImportPresetFromText(UI.presetTransferEditBox:GetText() or "")
        if didImport then
            HidePresetTransferFrame()
        else
            if UI.presetTransferStatusText then
                UI.presetTransferStatusText:SetText("|cffff3b30" .. tostring(errorMessage or "Import text is corrupted.") .. "|r")
                UI.presetTransferStatusText:Show()
            end
        end
    end
end

local function OnPresetTransferCancelClick()
    HidePresetTransferFrame()
end

------------------------------------------------------------
-- WHISPER RESPONSE
------------------------------------------------------------

local function GetMatchedResponseForWhisper(messageText)
    EnsureSavedVariables()

    local presetName = GetCharacterActivePresetName()
    if not presetName or presetName == "" then
        return nil, false
    end

    local presetData = RTAutoResponseSave.presets[presetName]
    if not presetData then
        return nil, false
    end

    local index = 1
    while presetData.commands and presetData.commands[index] do
        local commandData = presetData.commands[index]

        if commandData and DoCommandsMatch(commandData.command or "", messageText) then
            local responseText = tostring(commandData.response or "")
            if responseText ~= "" then
                return responseText, false
            end
        end

        index = index + 1
    end

    if tostring(presetData.defaultResponse or "") ~= "" then
        return presetData.defaultResponse, true
    end

    return nil, false
end

local function IsHelpCommand(messageText)
    if DoCommandsMatch(messageText, CONST.HELP_COMMAND_PRIMARY) then
        return true
    end

    if DoCommandsMatch(messageText, CONST.HELP_COMMAND_SECONDARY) then
        return true
    end

    if DoCommandsMatch(messageText, CONST.HELP_COMMAND_TERTIARY) then
        return true
    end

    return false
end

local function GetCommandListMessages()
    EnsureSavedVariables()

    local resultMessages = {}
    local presetName = GetCharacterActivePresetName()
    local presetData = nil

    if presetName and presetName ~= "" then
        presetData = RTAutoResponseSave.presets[presetName]
    end

    if not presetData or not presetData.commands then
        resultMessages[1] = "Available commands:"
        return resultMessages
    end

    local commandNames = {}
    local index = 1

    while presetData.commands[index] do
        local commandText = TrimText(presetData.commands[index].command or "")
        if commandText ~= "" and not IsReservedHelpAlias(commandText) then
            commandNames[#commandNames + 1] = commandText
        end
        index = index + 1
    end

    if #commandNames == 0 then
        resultMessages[1] = "Available commands:"
        return resultMessages
    end

    local prefix = "Available commands: "
    local currentMessage = prefix
    local commandIndex = 1

    while commandIndex <= #commandNames do
        local commandText = commandNames[commandIndex]
        local additionText = commandText

        if currentMessage ~= prefix then
            additionText = ", " .. commandText
        end

        if string.len(currentMessage .. additionText) <= CONST.CHAT_MESSAGE_MAX_LENGTH then
            currentMessage = currentMessage .. additionText
        else
            resultMessages[#resultMessages + 1] = currentMessage

            if string.len(prefix .. commandText) <= CONST.CHAT_MESSAGE_MAX_LENGTH then
                currentMessage = prefix .. commandText
            else
                local oversizedCommand = LimitTextLength(commandText, CONST.CHAT_MESSAGE_MAX_LENGTH - string.len(prefix))
                currentMessage = prefix .. oversizedCommand
            end
        end

        commandIndex = commandIndex + 1
    end

    if currentMessage ~= "" then
        resultMessages[#resultMessages + 1] = currentMessage
    end

    return resultMessages
end

local function SendWhisperMessageList(senderName, messages)
    if not senderName or senderName == "" then
        return
    end

    if type(messages) ~= "table" then
        return
    end

    local index = 1
    while index <= #messages do
        local messageText = tostring(messages[index] or "")
        if messageText ~= "" then
            SendChatMessage(LimitTextLength(messageText, CONST.CHAT_MESSAGE_MAX_LENGTH), "WHISPER", nil, senderName)
        end
        index = index + 1
    end
end

------------------------------------------------------------
-- POPUPS
------------------------------------------------------------

StaticPopupDialogs[CONST.AUTO_RESPONSE_PRESET_DELETE_POPUP] = {
    text = "Are you sure you want to delete \"%s\"?",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self)
        if self then
            self:Hide()
        end
        DeletePresetConfirmed(GetSelectedPresetName())
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3
}

StaticPopupDialogs[CONST.AUTO_RESPONSE_COMMAND_DELETE_POPUP] = {
    text = "Are you sure you want to delete \"%s\"?",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self)
        if self then
            self:Hide()
        end
        DeleteSelectedCommandDetailConfirmed()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3
}

------------------------------------------------------------
-- EVENT HANDLERS
------------------------------------------------------------

eventFrame:RegisterEvent("CHAT_MSG_WHISPER")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        EnsureSavedVariables()
        ForceDisableOnLogin()
        RefreshEnableButton()
        return
    end

    if event ~= "CHAT_MSG_WHISPER" then
        return
    end

    EnsureSavedVariables()

    if not STATE.isAutoResponseEnabled then
        return
    end

    local messageText = ...
    local senderName = select(2, ...)

    if not senderName or senderName == "" then
        return
    end

    if IsHelpCommand(messageText) then
        local commandMessages = GetCommandListMessages()
        SendWhisperMessageList(senderName, commandMessages)
        return
    end

    local responseText, isDefaultResponse = GetMatchedResponseForWhisper(messageText)

    if not responseText or responseText == "" then
        return
    end

    if isDefaultResponse then
        local currentTime = GetTime()
        local lastSentTime = STATE.defaultResponseThrottleBySender[senderName]

        if lastSentTime and (currentTime - lastSentTime) < CONST.DEFAULT_RESPONSE_COOLDOWN_SECONDS then
            return
        end

        STATE.defaultResponseThrottleBySender[senderName] = currentTime
    end

    if isDefaultResponse then
        local firstMessage = tostring(responseText or "")

        if IsHelpHintEnabled() then
            firstMessage = firstMessage .. CONST.DEFAULT_RESPONSE_HELP_SUFFIX
        end

        firstMessage = LimitTextLength(firstMessage, CONST.CHAT_MESSAGE_MAX_LENGTH)
        SendChatMessage(firstMessage, "WHISPER", nil, senderName)

        if IsCommandListAfterDefaultEnabled() then
            local commandMessages = GetCommandListMessages()
            SendWhisperMessageList(senderName, commandMessages)
        end
    else
        SendChatMessage(responseText, "WHISPER", nil, senderName)
    end
end)

loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGOUT")

loader:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        EnsureSavedVariables()

        if not RTAutoResponseSave.presets[CONST.DEFAULT_PRESET_NAME] then
            local defaultPresetData = CopyPresetData(DEFAULT_PRESET_TEMPLATE)
            defaultPresetData.order = -1
            RTAutoResponseSave.presets[CONST.DEFAULT_PRESET_NAME] = defaultPresetData
        end

        STATE.isAutoResponseEnabled = RTAutoResponseSave.enabled and true or false
        RefreshBottomOptionCheckboxes()
        RefreshAutoResponseOverlayIfAvailable()
        return
    end

    if event == "PLAYER_LOGOUT" then
        FlushActivePresetToSavedVariables()
        return
    end
end)

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

    local menuFrame = CreateFrame("Frame", addonName .. "AutoResponsePresetDropdownMenu", UIParent, "UIDropDownMenuTemplate")
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

                        if presetName == CONST.CREATE_NEW_PRESET_LABEL then
                            CreateNewPreset()
                        else
                            local currentPresetName = GetSelectedPresetName()

                            if currentPresetName and currentPresetName ~= CONST.CREATE_NEW_PRESET_LABEL then
                                FlushActivePresetToSavedVariables()
                            end

                            local shouldDisableAutoResponse = currentPresetName ~= presetName
                            LoadPresetIntoUI(presetName, shouldDisableAutoResponse)
                        end
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

local function BuildTopPresetRow(f)
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
        ShowDeletePresetPopup()
    end)

    UI.exportPresetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    UI.exportPresetBtn:SetSize(80, 24)
    UI.exportPresetBtn:SetPoint("TOPRIGHT", -25, -16)
    UI.exportPresetBtn:SetText("Export")
    UI.exportPresetBtn:SetScript("OnClick", function()
        ShowPresetTransferFrame("export")
    end)

    UI.importPresetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    UI.importPresetBtn:SetSize(80, 24)
    UI.importPresetBtn:SetPoint("RIGHT", UI.exportPresetBtn, "LEFT", -8, 0)
    UI.importPresetBtn:SetText("Import")
    UI.importPresetBtn:SetScript("OnClick", function()
        ShowPresetTransferFrame("import")
    end)
end

local function BuildDefaultResponseArea(f)
    UI.defaultResponseLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.defaultResponseLabel:SetPoint("TOPLEFT", 25, -60)
    UI.defaultResponseLabel:SetText("Default Response:")

    UI.defaultResponseSaveBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    UI.defaultResponseSaveBtn:SetSize(80, 24)
    UI.defaultResponseSaveBtn:SetPoint("TOPRIGHT", -25, -56)
    UI.defaultResponseSaveBtn:SetText("Save")
    UI.defaultResponseSaveBtn:SetScript("OnClick", function()
        SaveDefaultResponse()
    end)

    local defaultResponseBG = CreateFrame("Frame", nil, f)
    ApplyPixelStyle(defaultResponseBG)
    defaultResponseBG:SetPoint("TOPLEFT", 25, -84)
    defaultResponseBG:SetPoint("TOPRIGHT", -25, -84)
    defaultResponseBG:SetHeight(60)

    UI.defaultResponseEditBox = CreateFrame("EditBox", nil, defaultResponseBG)
    UI.defaultResponseEditBox:SetMultiLine(true)
    UI.defaultResponseEditBox:SetMaxLetters(CONST.RESPONSE_MAX_LENGTH)
    UI.defaultResponseEditBox:SetFontObject(ChatFontNormal)
    UI.defaultResponseEditBox:SetPoint("TOPLEFT", 8, -8)
    UI.defaultResponseEditBox:SetPoint("BOTTOMRIGHT", -8, 8)
    UI.defaultResponseEditBox:SetAutoFocus(false)

    UI.defaultResponseEditBox:SetScript("OnTextChanged", function(self)
        local textValue = self:GetText() or ""
        local textLength = string.len(textValue)

        if UI.defaultResponseCharCountText then
            UI.defaultResponseCharCountText:SetText(string.format("Characters: %d/%d", textLength, CONST.RESPONSE_MAX_LENGTH))
        end

        RefreshDefaultResponseInputColor()
        RefreshDefaultResponseSaveButton()
    end)

    UI.defaultResponseEditBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    UI.defaultResponseEditBox:SetScript("OnMouseDown", function(self)
        if IsCurrentPresetEditable() then
            self:SetFocus()
        end
    end)

    UI.defaultResponseCharCountText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.defaultResponseCharCountText:SetPoint("TOPRIGHT", defaultResponseBG, "BOTTOMRIGHT", 0, -5)
    UI.defaultResponseCharCountText:SetText("Characters: 0/255")
end

local function BuildCommandListArea(f)
    UI.addCommandBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    UI.addCommandBtn:SetSize(140, 24)
    UI.addCommandBtn:SetPoint("TOPLEFT", 25, -160)
    UI.addCommandBtn:SetText("Add New Command")
    UI.addCommandBtn:SetScript("OnClick", function()
        if not IsCurrentPresetEditable() then
            return
        end

        local row = CreateCommandRow("", "")
        RefreshCommandListUI()
        SelectCommandRow(row)
        RefreshAddCommandButtonState()
    end)

    local leftPaneBG = CreateFrame("Frame", nil, f)
    ApplyPixelStyle(leftPaneBG)
    leftPaneBG:SetPoint("TOPLEFT", 25, -190)
    leftPaneBG:SetPoint("BOTTOMLEFT", 25, 60)
    leftPaneBG:SetWidth(360)

    local leftPaneLabel = leftPaneBG:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    leftPaneLabel:SetPoint("TOPLEFT", 12, -12)
    leftPaneLabel:SetText("Command List")

    UI.commandDragInfoText = leftPaneBG:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.commandDragInfoText:SetPoint("TOPRIGHT", -12, -12)
    UI.commandDragInfoText:SetText("Right click to swap.")

    UI.commandScrollFrame = CreateFrame("ScrollFrame", addonName .. "AutoResponseCommandScrollFrame", leftPaneBG, "UIPanelScrollFrameTemplate")
    UI.commandScrollFrame:SetPoint("TOPLEFT", 10, -34)
    UI.commandScrollFrame:SetPoint("BOTTOMRIGHT", -28, 10)

    UI.commandContentFrame = CreateFrame("Frame", nil, UI.commandScrollFrame)
    UI.commandContentFrame:SetWidth(320)
    UI.commandContentFrame:SetHeight(1)
    UI.commandScrollFrame:SetScrollChild(UI.commandContentFrame)

    UI.commandDetailEmptyText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    UI.commandDetailEmptyText:SetPoint("TOPLEFT", leftPaneBG, "TOPRIGHT", 24, -20)
    UI.commandDetailEmptyText:SetText("Select a command to view details.")

    return leftPaneBG
end

local function BuildCommandDetailArea(f, leftPaneBG)
    UI.commandDetailPanel = CreateFrame("Frame", nil, f)
    ApplyPixelStyle(UI.commandDetailPanel)
    UI.commandDetailPanel:SetPoint("TOPLEFT", leftPaneBG, "TOPRIGHT", 20, 0)
    UI.commandDetailPanel:SetPoint("TOPRIGHT", -25, -190)
    UI.commandDetailPanel:SetPoint("BOTTOMRIGHT", -25, 60)

    UI.commandDetailSaveBtn = CreateFrame("Button", nil, UI.commandDetailPanel, "UIPanelButtonTemplate")
    UI.commandDetailSaveBtn:SetHeight(24)
    UI.commandDetailSaveBtn:SetPoint("TOPLEFT", 12, -12)
    UI.commandDetailSaveBtn:SetPoint("TOPRIGHT", UI.commandDetailPanel, "TOP", -4, -12)
    UI.commandDetailSaveBtn:SetText("Save")
    UI.commandDetailSaveBtn:SetScript("OnClick", function()
        SaveSelectedCommandDetail()
    end)

    UI.commandDetailDeleteBtn = CreateFrame("Button", nil, UI.commandDetailPanel, "UIPanelButtonTemplate")
    UI.commandDetailDeleteBtn:SetHeight(24)
    UI.commandDetailDeleteBtn:SetPoint("TOPLEFT", UI.commandDetailPanel, "TOP", 4, -12)
    UI.commandDetailDeleteBtn:SetPoint("TOPRIGHT", -12, -12)
    UI.commandDetailDeleteBtn:SetText("Delete")
    UI.commandDetailDeleteBtn:SetScript("OnClick", function()
        ShowDeleteSelectedCommandPopup()
    end)

    UI.commandDetailStatusText = UI.commandDetailPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.commandDetailStatusText:SetPoint("TOP", 0, -40)
    UI.commandDetailStatusText:SetText("")

    UI.commandDetailCommandEditBG = CreateFrame("Frame", nil, UI.commandDetailPanel)
    ApplyPixelStyle(UI.commandDetailCommandEditBG)
    UI.commandDetailCommandEditBG:SetPoint("TOPLEFT", 12, -82)
    UI.commandDetailCommandEditBG:SetPoint("TOPRIGHT", -12, -82)
    UI.commandDetailCommandEditBG:SetHeight(28)

    UI.commandDetailCommandLabel = UI.commandDetailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.commandDetailCommandLabel:SetPoint("BOTTOM", UI.commandDetailCommandEditBG, "TOP", 0, 8)
    UI.commandDetailCommandLabel:SetText("Command")

    UI.commandDetailCommandEditBox = CreateFrame("EditBox", nil, UI.commandDetailCommandEditBG)
    UI.commandDetailCommandEditBox:SetAllPoints()
    UI.commandDetailCommandEditBox:SetAutoFocus(false)
    UI.commandDetailCommandEditBox:SetFontObject(ChatFontNormal)
    UI.commandDetailCommandEditBox:SetJustifyH("LEFT")
    UI.commandDetailCommandEditBox:SetMaxLetters(CONST.COMMAND_NAME_MAX_LENGTH)

    UI.commandDetailCommandEditBox:SetScript("OnTextChanged", function(self)
        if STATE.selectedCommandRow and STATE.selectedCommandRow.isSystemCommand then
            return
        end

        if not IsCurrentPresetEditable() then
            RefreshCommandDetailInputColors()
            UpdateCommandDetailDirtyState()
            RefreshCommandDetailControlStates()
            RefreshSelectedCommandListPreview()
            return
        end

        local currentText = self:GetText() or ""
        local sanitizedText = SanitizeCommandText(currentText)

        if currentText ~= sanitizedText then
            local cursorPosition = self:GetCursorPosition()
            self:SetText(sanitizedText)

            if cursorPosition > string.len(sanitizedText) then
                cursorPosition = string.len(sanitizedText)
            end

            self:SetCursorPosition(cursorPosition)
            RefreshCommandDetailInputColors()
            UpdateCommandDetailDirtyState()
            RefreshCommandDetailControlStates()
            RefreshSelectedCommandListPreview()
            return
        end

        RefreshCommandDetailInputColors()
        UpdateCommandDetailDirtyState()
        RefreshCommandDetailControlStates()
        RefreshSelectedCommandListPreview()
    end)

    UI.commandDetailCommandEditBox:SetScript("OnEnterPressed", function()
        SaveSelectedCommandDetail()
    end)

    UI.commandDetailCommandEditBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    UI.commandDetailResponseBG = CreateFrame("Frame", nil, UI.commandDetailPanel)
    ApplyPixelStyle(UI.commandDetailResponseBG)
    UI.commandDetailResponseBG:SetPoint("TOPLEFT", 12, -144)
    UI.commandDetailResponseBG:SetPoint("BOTTOMRIGHT", -12, 12)

    UI.commandDetailResponseLabel = UI.commandDetailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.commandDetailResponseLabel:SetPoint("BOTTOM", UI.commandDetailResponseBG, "TOP", 0, 8)
    UI.commandDetailResponseLabel:SetText("Response")

    UI.commandDetailResponseEditBox = CreateFrame("EditBox", nil, UI.commandDetailResponseBG)
    UI.commandDetailResponseEditBox:SetMultiLine(true)
    UI.commandDetailResponseEditBox:SetFontObject(ChatFontNormal)
    UI.commandDetailResponseEditBox:SetPoint("TOPLEFT", 6, -6)
    UI.commandDetailResponseEditBox:SetPoint("BOTTOMRIGHT", -6, 6)
    UI.commandDetailResponseEditBox:SetAutoFocus(false)
    UI.commandDetailResponseEditBox:SetMaxLetters(CONST.RESPONSE_MAX_LENGTH)

    UI.commandDetailResponseEditBox:SetScript("OnTextChanged", function(self)
        if STATE.selectedCommandRow and STATE.selectedCommandRow.isSystemCommand then
            return
        end

        if not IsCurrentPresetEditable() then
            RefreshCommandDetailInputColors()
            UpdateCommandDetailDirtyState()
            RefreshCommandDetailControlStates()
            RefreshSelectedCommandListPreview()
            return
        end

        local currentText = self:GetText() or ""
        if string.len(currentText) > CONST.RESPONSE_MAX_LENGTH then
            self:SetText(string.sub(currentText, 1, CONST.RESPONSE_MAX_LENGTH))
            self:SetCursorPosition(CONST.RESPONSE_MAX_LENGTH)
            RefreshCommandDetailInputColors()
            UpdateCommandDetailDirtyState()
            RefreshCommandDetailControlStates()
            RefreshSelectedCommandListPreview()
            return
        end

        RefreshCommandDetailInputColors()
        UpdateCommandDetailDirtyState()
        RefreshCommandDetailControlStates()
        RefreshSelectedCommandListPreview()
    end)

    UI.commandDetailResponseEditBox:SetScript("OnEnterPressed", function()
        SaveSelectedCommandDetail()
    end)

    UI.commandDetailResponseEditBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    UI.commandDetailPanel:Hide()
end

local function CreatePresetTransferPopup(parentFrame)
    UI.presetTransferFrame = CreateFrame("Frame", addonName .. "AutoResponsePresetTransferFrame", UIParent)
    ApplyPixelStyle(UI.presetTransferFrame, 520, 280)
    UI.presetTransferFrame:SetFrameStrata("TOOLTIP")
    UI.presetTransferFrame:SetFrameLevel(1000)
    UI.presetTransferFrame:SetToplevel(true)
    UI.presetTransferFrame:EnableMouse(true)
    UI.presetTransferFrame:SetMovable(true)
    UI.presetTransferFrame:RegisterForDrag("LeftButton")
    UI.presetTransferFrame:SetClampedToScreen(true)
    UI.presetTransferFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    UI.presetTransferFrame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    UI.presetTransferFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    UI.presetTransferFrame:Hide()

    UI.presetTransferTitleText = UI.presetTransferFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    UI.presetTransferTitleText:SetPoint("TOP", 0, -14)
    UI.presetTransferTitleText:SetText("Preset Transfer")

    local presetTransferInfoText = UI.presetTransferFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    presetTransferInfoText:SetPoint("TOPLEFT", 14, -38)
    presetTransferInfoText:SetPoint("TOPRIGHT", -14, -38)
    presetTransferInfoText:SetJustifyH("LEFT")
    presetTransferInfoText:SetText("Export gives you the active preset as text. Import adds pasted preset text as a new preset.")

    local presetTransferEditBG = CreateFrame("Frame", nil, UI.presetTransferFrame)
    ApplyPixelStyle(presetTransferEditBG)
    presetTransferEditBG:SetPoint("TOPLEFT", 14, -62)
    presetTransferEditBG:SetPoint("TOPRIGHT", -14, -62)
    presetTransferEditBG:SetHeight(168)
    presetTransferEditBG:SetFrameLevel(UI.presetTransferFrame:GetFrameLevel() + 1)

    UI.presetTransferScrollFrame = CreateFrame("ScrollFrame", addonName .. "AutoResponsePresetTransferScrollFrame", presetTransferEditBG, "UIPanelScrollFrameTemplate")
    UI.presetTransferScrollFrame:SetPoint("TOPLEFT", 6, -6)
    UI.presetTransferScrollFrame:SetPoint("BOTTOMRIGHT", -28, 6)
    UI.presetTransferScrollFrame:SetFrameLevel(UI.presetTransferFrame:GetFrameLevel() + 2)

    local presetTransferScrollChild = CreateFrame("Frame", nil, UI.presetTransferScrollFrame)
    presetTransferScrollChild:SetWidth(460)
    presetTransferScrollChild:SetHeight(168)
    presetTransferScrollChild:SetFrameLevel(UI.presetTransferFrame:GetFrameLevel() + 2)
    UI.presetTransferScrollFrame:SetScrollChild(presetTransferScrollChild)

    UI.presetTransferEditBox = CreateFrame("EditBox", nil, presetTransferScrollChild)
    UI.presetTransferEditBox:SetMultiLine(true)
    UI.presetTransferEditBox:SetAutoFocus(false)
    UI.presetTransferEditBox:SetFontObject(ChatFontNormal)
    UI.presetTransferEditBox:SetPoint("TOPLEFT", 0, 0)
    UI.presetTransferEditBox:SetWidth(460)
    UI.presetTransferEditBox:SetHeight(168)
    UI.presetTransferEditBox:EnableMouse(true)
    UI.presetTransferEditBox:SetFrameLevel(UI.presetTransferFrame:GetFrameLevel() + 3)
    UI.presetTransferEditBox.isReadOnly = false
    UI.presetTransferEditBox.lastReadOnlyText = ""

    UI.presetTransferMeasureText = presetTransferScrollChild:CreateFontString(nil, "ARTWORK", "ChatFontNormal")
    UI.presetTransferMeasureText:SetWidth(460)
    UI.presetTransferMeasureText:SetJustifyH("LEFT")
    UI.presetTransferMeasureText:SetJustifyV("TOP")
    UI.presetTransferMeasureText:SetText(" ")
    UI.presetTransferMeasureText:Hide()

    UI.presetTransferEditBox:SetScript("OnMouseDown", function(self)
        self:SetFocus()

        if self.isReadOnly then
            self:HighlightText()
        end
    end)

    UI.presetTransferEditBox:SetScript("OnChar", function(self)
        if self.isReadOnly then
            self:SetText(self.lastReadOnlyText or "")
            self:HighlightText()
        end
    end)

    UI.presetTransferEditBox:SetScript("OnTextChanged", function(self)
        if self.isReadOnly then
            local currentText = tostring(self:GetText() or "")
            local expectedText = tostring(self.lastReadOnlyText or "")

            if currentText ~= expectedText then
                self:SetText(expectedText)
                self:HighlightText()
            end
            return
        end

        local textValue = self:GetText() or ""

        if textValue == "" then
            textValue = " "
        end

        UI.presetTransferMeasureText:SetText(textValue)

        local textHeight = UI.presetTransferMeasureText:GetHeight()
        if not textHeight or textHeight < 168 then
            textHeight = 168
        end

        self:SetHeight(textHeight + 16)
        presetTransferScrollChild:SetHeight(textHeight + 16)
    end)

    UI.presetTransferEditBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        HidePresetTransferFrame()
    end)

    UI.presetTransferStatusText = UI.presetTransferFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.presetTransferStatusText:SetPoint("BOTTOMLEFT", 14, 38)
    UI.presetTransferStatusText:SetPoint("BOTTOMRIGHT", -14, 38)
    UI.presetTransferStatusText:SetJustifyH("LEFT")
    UI.presetTransferStatusText:SetText("")
    UI.presetTransferStatusText:Hide()

    UI.presetTransferConfirmBtn = CreateFrame("Button", nil, UI.presetTransferFrame, "UIPanelButtonTemplate")
    UI.presetTransferConfirmBtn:SetSize(100, 24)
    UI.presetTransferConfirmBtn:SetPoint("BOTTOMRIGHT", -14, 12)
    UI.presetTransferConfirmBtn:SetText("Import")
    UI.presetTransferConfirmBtn:SetFrameLevel(UI.presetTransferFrame:GetFrameLevel() + 3)
    UI.presetTransferConfirmBtn:SetScript("OnClick", OnPresetTransferConfirmClick)

    UI.presetTransferCancelBtn = CreateFrame("Button", nil, UI.presetTransferFrame, "UIPanelButtonTemplate")
    UI.presetTransferCancelBtn:SetSize(100, 24)
    UI.presetTransferCancelBtn:SetPoint("RIGHT", UI.presetTransferConfirmBtn, "LEFT", -8, 0)
    UI.presetTransferCancelBtn:SetText("Cancel")
    UI.presetTransferCancelBtn:SetFrameLevel(UI.presetTransferFrame:GetFrameLevel() + 3)
    UI.presetTransferCancelBtn:SetScript("OnClick", OnPresetTransferCancelClick)
end

local function BuildBottomButtons(f, onClose)
    UI.helpHintCheckbox = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    TrySkinCheckBox(UI.helpHintCheckbox)
    UI.helpHintCheckbox:SetSize(24, 24)
    UI.helpHintCheckbox:SetPoint("BOTTOMLEFT", 18, 12)
    UI.helpHintCheckbox:SetChecked(true)
    UI.helpHintCheckbox:SetScript("OnClick", function(self)
        EnsureSavedVariables()
        RTAutoResponseSave.enableHelpHint = self:GetChecked() and true or false
    end)

    local helpHintLabel = UI.helpHintCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    helpHintLabel:SetPoint("LEFT", UI.helpHintCheckbox, "RIGHT", 4, 0)
    helpHintLabel:SetJustifyH("LEFT")
    helpHintLabel:SetText(CONST.HELP_HINT_CHECKBOX_LABEL)
    UI.helpHintCheckbox.label = helpHintLabel

    UI.sendCommandListCheckbox = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    TrySkinCheckBox(UI.sendCommandListCheckbox)
    UI.sendCommandListCheckbox:SetSize(24, 24)
    UI.sendCommandListCheckbox:SetPoint("LEFT", UI.helpHintCheckbox.label, "RIGHT", 18, 0)
    UI.sendCommandListCheckbox:SetChecked(true)
    UI.sendCommandListCheckbox:SetScript("OnClick", function(self)
        EnsureSavedVariables()
        RTAutoResponseSave.sendCommandListAfterDefault = self:GetChecked() and true or false
    end)

    local sendCommandListLabel = UI.sendCommandListCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sendCommandListLabel:SetPoint("LEFT", UI.sendCommandListCheckbox, "RIGHT", 4, 0)
    sendCommandListLabel:SetJustifyH("LEFT")
    sendCommandListLabel:SetText(CONST.COMMAND_LIST_CHECKBOX_LABEL)
    UI.sendCommandListCheckbox.label = sendCommandListLabel

    UI.enableBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    UI.enableBtn:SetSize(170, 28)
    UI.enableBtn:SetPoint("BOTTOMRIGHT", -18, 12)
    UI.enableBtn:SetText("Enable Auto Reply")
    UI.enableBtn:SetScript("OnClick", function()
        STATE.isAutoResponseEnabled = not STATE.isAutoResponseEnabled
        RTAutoResponseSave.enabled = STATE.isAutoResponseEnabled and true or false
        RefreshEnableButton()
        RefreshAutoResponseOverlayIfAvailable()
    end)

    UI.closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    UI.closeBtn:SetSize(100, 28)
    UI.closeBtn:SetPoint("RIGHT", UI.enableBtn, "LEFT", -10, 0)
    UI.closeBtn:SetText("Close")
    UI.closeBtn:SetScript("OnClick", function()
        HidePresetTransferFrame()
        if onClose then
            onClose()
        end
    end)

    RefreshBottomOptionCheckboxes()
end

local function SkinStaticButtons()
    TrySkinButton(UI.presetDropdownButton)
    TrySkinButton(UI.renamePresetBtn)
    TrySkinButton(UI.deletePresetBtn)
    TrySkinButton(UI.importPresetBtn)
    TrySkinButton(UI.exportPresetBtn)
    TrySkinButton(UI.defaultResponseSaveBtn)
    TrySkinButton(UI.addCommandBtn)
    TrySkinButton(UI.commandDetailDeleteBtn)
    TrySkinButton(UI.commandDetailSaveBtn)
    TrySkinButton(UI.presetTransferConfirmBtn)
    TrySkinButton(UI.presetTransferCancelBtn)
    TrySkinButton(UI.enableBtn)
    TrySkinButton(UI.closeBtn)
    TrySkinCheckBox(UI.helpHintCheckbox)
    TrySkinCheckBox(UI.sendCommandListCheckbox)
end

------------------------------------------------------------
-- PUBLIC UI ENTRY
------------------------------------------------------------

function CreateAutoResponseTabContent(parent, onClose)
    EnsureSavedVariables()

    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    f:Hide()

    UI.root = f

    BuildTopPresetRow(f)
    BuildDefaultResponseArea(f)

    local leftPaneBG = BuildCommandListArea(f)
    BuildCommandDetailArea(f, leftPaneBG)

    CreatePresetTransferPopup(f)
    BuildBottomButtons(f, onClose)
    SkinStaticButtons()

    f:SetScript("OnUpdate", function()
        RefreshDefaultResponseSaveButton()
    end)

    f:SetScript("OnShow", function()
        EnsureSavedVariables()

        local activePresetName = GetCharacterActivePresetName()
        if not activePresetName or activePresetName == "" or not RTAutoResponseSave.presets[activePresetName] then
            activePresetName = CONST.DEFAULT_PRESET_NAME
        end

        LoadPresetIntoUI(activePresetName, false)
        RefreshPresetActionButtons()
        RefreshEnableButton()
        RefreshBottomOptionCheckboxes()
        RefreshDefaultResponseControlStates()
    end)

    f:SetScript("OnHide", function()
        FlushActivePresetToSavedVariables()
        StopCommandRowDrag()
    end)

    RefreshPresetActionButtons()
    RefreshEnableButton()
    RefreshBottomOptionCheckboxes()
    RefreshAddCommandButtonState()
    StopRenameMode()
    RefreshDefaultResponseSaveButton()
    RefreshDefaultResponseControlStates()

    return f
end