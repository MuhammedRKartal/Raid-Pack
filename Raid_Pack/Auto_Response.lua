-- Auto_Response.lua

local addonName = ...
local addonTable = select(2, ...)

local isAutoResponseEnabled = false
local defaultResponseThrottleBySender = {}

local presetDropdownButton = nil
local presetDropdownText = nil
local renamePresetBtn = nil
local renamePresetBG = nil
local renamePresetEditBox = nil
local deletePresetBtn = nil

local defaultResponseLabel = nil
local defaultResponseEditBox = nil
local defaultResponseCharCountText = nil
local defaultResponseSaveBtn = nil
local defaultResponseSaveResetAt = 0

local addCommandBtn = nil
local commandScrollFrame = nil
local commandContentFrame = nil
local commandRows = {}
local commandListButtons = {}

local commandDetailPanel = nil
local commandDetailEmptyText = nil
local commandDetailCommandLabel = nil
local commandDetailCommandEditBG = nil
local commandDetailCommandEditBox = nil
local commandDetailResponseLabel = nil
local commandDetailResponseBG = nil
local commandDetailResponseEditBox = nil
local commandDetailSaveBtn = nil
local commandDetailDeleteBtn = nil
local commandDetailStatusText = nil

local enableBtn = nil

local selectedPresetName = nil
local selectedCommandRow = nil

local CREATE_NEW_PRESET_LABEL = "Create New"
local CREATE_NEW_PRESET_BASE_NAME = "New Preset"
local DEFAULT_PRESET_NAME = "Weakauras Center"

local PRESET_NAME_MAX_LENGTH = 21
local COMMAND_NAME_MAX_LENGTH = 12
local RESPONSE_MAX_LENGTH = 255
local CHAT_MESSAGE_MAX_LENGTH = 255
local DEFAULT_RESPONSE_COOLDOWN_SECONDS = 10

local HELP_COMMAND_DISPLAY_TEXT = "!help & !commands"
local HELP_COMMAND_PRIMARY = "!help"
local HELP_COMMAND_SECONDARY = "!commands"
local HELP_COMMAND_AUTO_RESPONSE = "Shows the full command list."
local COMMAND_HELP_GUIDE_MESSAGE = "!help or !commands to see the full command list."

local AUTO_RESPONSE_PRESET_DELETE_POPUP = addonName .. "AutoResponsePresetDeletePopup"
local AUTO_RESPONSE_COMMAND_DELETE_POPUP = addonName .. "AutoResponseCommandDeletePopup"

local eventFrame = CreateFrame("Frame")
local loader = CreateFrame("Frame")

local DEFAULT_PRESET_TEMPLATE = {
    defaultResponse = "Hello, welcome to Weakauras Center.",
    commands = {
        {
            command = "!discord",
            response = "You can join the discord by this link: https://discord.gg/Q9ZnDAR7F8"
        },
        {
            command = "!free",
            response = "Yes there are some free content, you can also share since its a public community, but most of the content is paid with in-game gold."
        },
        {
            command = "!ownership",
            response = "All content is created by me or other creators. Nothing is stolen or used without permission."
        },
        {
            command = "!ui",
            response = "User Interfaces are complete screen setups built with multiple addons. The channel includes ElvUI, BlizzUI, and PvP UI configurations. No worries its easy to setup."
        },
        {
            command = "!weakauras",
            response = "This channel includes WeakAuras for v4.0.0 and v5.19+, with setups for all classes and specs, raid helper WeakAuras, PvP WeakAuras, and plenty of extra utilities."
        },
        {
            command = "!wtb",
            response = "Please log discord and check all channels, then contact me >>HirohitoW<<. Discord Link: https://discord.gg/Q9ZnDAR7F8"
        }
    }
}

local SYSTEM_HELP_ROW = {
    isSystemCommand = true,
    isDeleted = false,
    hasDuplicate = false,
    command = HELP_COMMAND_DISPLAY_TEXT,
    response = HELP_COMMAND_AUTO_RESPONSE
}

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

local function IsReservedHelpAlias(text)
    local normalizedText = NormalizeCommandText(text)
    if normalizedText == NormalizeCommandText(HELP_COMMAND_PRIMARY) then
        return true
    end
    if normalizedText == NormalizeCommandText(HELP_COMMAND_SECONDARY) then
        return true
    end
    if normalizedText == NormalizeCommandText(HELP_COMMAND_DISPLAY_TEXT) then
        return true
    end
    return false
end

local function SanitizeCommandText(text)
    local result = tostring(text or "")
    result = RemoveAllSpaces(result)
    result = LimitTextLength(result, COMMAND_NAME_MAX_LENGTH)
    return result
end

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
    result.response = LimitTextLength(result.response, RESPONSE_MAX_LENGTH)

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

    result.defaultResponse = LimitTextLength(result.defaultResponse, RESPONSE_MAX_LENGTH)

    return result
end

local function EnsureSavedVariables()
    if type(RTAutoResponseSave) ~= "table" then
        RTAutoResponseSave = {}
    end

    if type(RTAutoResponseSave.presets) ~= "table" then
        RTAutoResponseSave.presets = {}
    end

    if type(RTAutoResponseSave.activePresetName) ~= "string" then
        RTAutoResponseSave.activePresetName = DEFAULT_PRESET_NAME
    end

    if RTAutoResponseSave.enabled == nil then
        RTAutoResponseSave.enabled = false
    else
        RTAutoResponseSave.enabled = RTAutoResponseSave.enabled and true or false
    end

    for presetName, presetData in pairs(RTAutoResponseSave.presets) do
        if presetName ~= DEFAULT_PRESET_NAME then
            RTAutoResponseSave.presets[presetName] = CopyPresetData(presetData)
        end
    end

    RTAutoResponseSave.presets[DEFAULT_PRESET_NAME] = CopyPresetData(DEFAULT_PRESET_TEMPLATE)

    if not RTAutoResponseSave.activePresetName
        or RTAutoResponseSave.activePresetName == ""
        or not RTAutoResponseSave.presets[RTAutoResponseSave.activePresetName] then
        RTAutoResponseSave.activePresetName = DEFAULT_PRESET_NAME
    end
end

local function GetSelectedPresetName()
    EnsureSavedVariables()

    local presetName = RTAutoResponseSave.activePresetName
    if type(presetName) ~= "string" or presetName == "" then
        return DEFAULT_PRESET_NAME
    end

    if not RTAutoResponseSave.presets[presetName] then
        return DEFAULT_PRESET_NAME
    end

    return presetName
end

local function SetSelectedPresetName(presetName)
    selectedPresetName = presetName

    if presetName
        and presetName ~= ""
        and presetName ~= CREATE_NEW_PRESET_LABEL
        and RTAutoResponseSave
        and RTAutoResponseSave.presets
        and RTAutoResponseSave.presets[presetName] then
        RTAutoResponseSave.activePresetName = presetName
    end

    if presetDropdownText then
        if presetName and presetName ~= "" then
            presetDropdownText:SetText(presetName)
        else
            presetDropdownText:SetText("Select Preset")
        end
    end
end

local function IsProtectedPreset(presetName)
    if presetName == DEFAULT_PRESET_NAME then
        return true
    end
    return false
end

local function IsDefaultPresetSelected()
    local presetName = GetSelectedPresetName()
    return presetName == DEFAULT_PRESET_NAME
end

local function IsCurrentPresetEditable()
    return not IsDefaultPresetSelected()
end

local function IsRenameBlocked(presetName)
    if not presetName or presetName == "" then
        return true
    end

    if presetName == CREATE_NEW_PRESET_LABEL then
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
        if leftValue == DEFAULT_PRESET_NAME then
            return true
        end

        if rightValue == DEFAULT_PRESET_NAME then
            return false
        end

        return string.lower(leftValue) < string.lower(rightValue)
    end)

    local result = { CREATE_NEW_PRESET_LABEL }
    local index = 1
    while index <= #presetNames do
        result[#result + 1] = presetNames[index]
        index = index + 1
    end

    return result
end

local function GetUniquePresetName(baseName)
    EnsureSavedVariables()

    local trimmedBaseName = LimitTextLength(TrimText(baseName or ""), PRESET_NAME_MAX_LENGTH)

    if trimmedBaseName == "" then
        return ""
    end

    if not RTAutoResponseSave.presets[trimmedBaseName] then
        return trimmedBaseName
    end

    local copySuffix = " (copy)"
    local indexedPrefix = " (copy "

    local candidateName = LimitTextLength(trimmedBaseName, PRESET_NAME_MAX_LENGTH - string.len(copySuffix)) .. copySuffix
    if not RTAutoResponseSave.presets[candidateName] then
        return candidateName
    end

    local copyIndex = 2
    while true do
        local suffix = indexedPrefix .. tostring(copyIndex) .. ")"
        local maxBaseLength = PRESET_NAME_MAX_LENGTH - string.len(suffix)
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
        local candidateName = CREATE_NEW_PRESET_BASE_NAME .. " (" .. tostring(newIndex) .. ")"

        if string.len(candidateName) > PRESET_NAME_MAX_LENGTH then
            candidateName = LimitTextLength(candidateName, PRESET_NAME_MAX_LENGTH)
        end

        if not RTAutoResponseSave.presets[candidateName] then
            return candidateName
        end

        newIndex = newIndex + 1
    end
end

local function GetActivePresetData()
    EnsureSavedVariables()

    local presetName = RTAutoResponseSave.activePresetName
    if not presetName or presetName == "" then
        return nil
    end

    if presetName == CREATE_NEW_PRESET_LABEL then
        return nil
    end

    return RTAutoResponseSave.presets[presetName]
end

local function RefreshPresetActionButtons()
    local presetName = selectedPresetName
    local canRenameOrDelete = false

    EnsureSavedVariables()

    if presetName and presetName ~= "" and presetName ~= CREATE_NEW_PRESET_LABEL and RTAutoResponseSave.presets[presetName] then
        if not IsProtectedPreset(presetName) then
            canRenameOrDelete = true
        end
    end

    if renamePresetBtn then
        if canRenameOrDelete then
            renamePresetBtn:Enable()
        else
            renamePresetBtn:Disable()
        end
    end

    if deletePresetBtn then
        if canRenameOrDelete then
            deletePresetBtn:Enable()
        else
            deletePresetBtn:Disable()
        end
    end
end

local function StopRenameMode()
    if presetDropdownButton then
        presetDropdownButton:Show()
    end

    if renamePresetBG then
        renamePresetBG:Hide()
    end

    if renamePresetEditBox then
        renamePresetEditBox:Hide()
        renamePresetEditBox:ClearFocus()
    end

    if renamePresetBtn then
        renamePresetBtn:SetText("Rename")
        renamePresetBtn.isRenaming = false
    end
end

local function StartRenameMode()
    EnsureSavedVariables()

    local presetName = GetSelectedPresetName()
    if IsRenameBlocked(presetName) then
        return
    end

    if presetDropdownButton then
        presetDropdownButton:Hide()
    end

    if renamePresetBG then
        renamePresetBG:Show()
    end

    if renamePresetEditBox then
        renamePresetEditBox:Show()
        renamePresetEditBox:SetText(presetName)
        renamePresetEditBox:SetFocus()
        renamePresetEditBox:HighlightText()
    end

    if renamePresetBtn then
        renamePresetBtn:SetText("|cff00ff00Save|r")
        renamePresetBtn.isRenaming = true
    end
end

local function RenameSelectedPreset(newName)
    EnsureSavedVariables()

    local oldName = GetSelectedPresetName()
    if IsRenameBlocked(oldName) then
        StopRenameMode()
        return
    end

    local finalName = LimitTextLength(TrimText(newName or ""), PRESET_NAME_MAX_LENGTH)
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
    RTAutoResponseSave.presets[oldName] = nil

    SetSelectedPresetName(finalName)
    StopRenameMode()
    RefreshPresetActionButtons()
end

local function ClearCommandRows()
    wipe(commandRows)
    selectedCommandRow = nil
end

local function GetVisibleCommandRows()
    local visibleRows = {}
    local index = #commandRows

    while index >= 1 do
        local row = commandRows[index]
        if row and not row.isDeleted then
            visibleRows[#visibleRows + 1] = row
        end
        index = index - 1
    end

    visibleRows[#visibleRows + 1] = SYSTEM_HELP_ROW

    return visibleRows
end

local function DoesCommandExist(commandText, ignoredRow)
    local normalizedTarget = NormalizeCommandText(commandText)
    local index = 1

    if normalizedTarget == "" then
        return false
    end

    if IsReservedHelpAlias(normalizedTarget) then
        return true
    end

    while index <= #commandRows do
        local row = commandRows[index]
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
    while index <= #commandRows do
        local row = commandRows[index]
        if row and not row.isDeleted then
            RefreshCommandDuplicateState(row)
        end
        index = index + 1
    end
end

local function SaveAllCommandRowsToPreset()
    local presetData = GetActivePresetData()
    if not presetData then
        return
    end

    if not IsCurrentPresetEditable() then
        return
    end

    presetData.commands = {}

    local saveIndex = 1
    local rowIndex = 1

    while rowIndex <= #commandRows do
        local row = commandRows[rowIndex]
        if row and not row.isDeleted and not row.isSystemCommand then
            local sanitizedCommand = SanitizeCommandText(row.command or "")
            local limitedResponse = LimitTextLength(row.response or "", RESPONSE_MAX_LENGTH)

            if sanitizedCommand ~= "" or limitedResponse ~= "" then
                if not IsReservedHelpAlias(sanitizedCommand) then
                    presetData.commands[saveIndex] = {
                        command = sanitizedCommand,
                        response = limitedResponse
                    }
                    saveIndex = saveIndex + 1
                end
            end
        end
        rowIndex = rowIndex + 1
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

    if editBox.SetTextColor then
        if isEnabled then
            editBox:SetTextColor(1, 1, 1)
        else
            editBox:SetTextColor(0.65, 0.65, 0.65)
        end
    end

    if editBox.SetAlpha then
        if isEnabled then
            editBox:SetAlpha(1)
        else
            editBox:SetAlpha(0.8)
        end
    end
end

local function RefreshAddCommandButtonState()
    if not addCommandBtn then
        return
    end

    if not IsCurrentPresetEditable() then
        addCommandBtn:Disable()
        return
    end

    local lastRow = nil
    local index = #commandRows

    while index >= 1 do
        local row = commandRows[index]
        if row and not row.isDeleted and not row.isSystemCommand then
            lastRow = row
            break
        end
        index = index - 1
    end

    if not lastRow then
        addCommandBtn:Enable()
        return
    end

    local commandText = TrimText(lastRow.command or "")
    local responseText = TrimText(lastRow.response or "")

    if commandText == "" or responseText == "" then
        addCommandBtn:Disable()
    else
        addCommandBtn:Enable()
    end
end

local function ClearCommandListButtons()
    local index = 1

    while index <= #commandListButtons do
        local button = commandListButtons[index]
        if button then
            button:Hide()
            button:ClearAllPoints()
            button.row = nil
            button:SetText("")
            button:SetParent(commandContentFrame)
        end
        index = index + 1
    end
end

local function RefreshDefaultResponseSaveButton()
    if not defaultResponseSaveBtn then
        return
    end

    if not IsCurrentPresetEditable() then
        defaultResponseSaveBtn:SetText("Save")
        defaultResponseSaveResetAt = 0
        return
    end

    if defaultResponseSaveResetAt > 0 and GetTime() < defaultResponseSaveResetAt then
        defaultResponseSaveBtn:SetText("|cff00ff00Saved|r")
    else
        defaultResponseSaveBtn:SetText("Save")
        defaultResponseSaveResetAt = 0
    end
end

local function RefreshDefaultResponseInputColor()
    if not defaultResponseEditBox then
        return
    end

    if not IsCurrentPresetEditable() then
        defaultResponseEditBox:SetTextColor(0.65, 0.65, 0.65)
        return
    end

    local presetData = GetActivePresetData()
    local currentValue = tostring(defaultResponseEditBox:GetText() or "")
    local savedValue = ""

    if presetData then
        savedValue = tostring(presetData.defaultResponse or "")
    end

    if currentValue ~= savedValue then
        defaultResponseEditBox:SetTextColor(0, 1, 0)
    else
        defaultResponseEditBox:SetTextColor(1, 1, 1)
    end
end

local function RefreshDefaultResponseControlStates()
    local isEditable = IsCurrentPresetEditable()

    if defaultResponseEditBox then
        SetEditBoxInteractionEnabled(defaultResponseEditBox, isEditable)
    end

    if defaultResponseSaveBtn then
        if isEditable then
            defaultResponseSaveBtn:Enable()
        else
            defaultResponseSaveBtn:Disable()
        end
    end
end

local function RefreshCommandDetailInputColors()
    if not selectedCommandRow or selectedCommandRow.isDeleted then
        if commandDetailCommandEditBox then
            commandDetailCommandEditBox:SetTextColor(0.65, 0.65, 0.65)
        end

        if commandDetailResponseEditBox then
            commandDetailResponseEditBox:SetTextColor(0.65, 0.65, 0.65)
        end
        return
    end

    if not IsCurrentPresetEditable() then
        if commandDetailCommandEditBox then
            if selectedCommandRow.isSystemCommand then
                commandDetailCommandEditBox:SetTextColor(1, 0.82, 0)
            else
                commandDetailCommandEditBox:SetTextColor(0.65, 0.65, 0.65)
            end
        end

        if commandDetailResponseEditBox then
            commandDetailResponseEditBox:SetTextColor(0.65, 0.65, 0.65)
        end
        return
    end

    if selectedCommandRow.isSystemCommand then
        if commandDetailCommandEditBox then
            commandDetailCommandEditBox:SetTextColor(1, 0.82, 0)
        end

        if commandDetailResponseEditBox then
            commandDetailResponseEditBox:SetTextColor(1, 1, 1)
        end
        return
    end

    local currentCommandText = ""
    local currentResponseText = ""

    if commandDetailCommandEditBox then
        currentCommandText = SanitizeCommandText(commandDetailCommandEditBox:GetText() or "")
    end

    if commandDetailResponseEditBox then
        currentResponseText = LimitTextLength(commandDetailResponseEditBox:GetText() or "", RESPONSE_MAX_LENGTH)
    end

    if commandDetailCommandEditBox then
        if currentCommandText ~= tostring(selectedCommandRow.command or "") then
            commandDetailCommandEditBox:SetTextColor(0, 1, 0)
        else
            commandDetailCommandEditBox:SetTextColor(1, 1, 1)
        end
    end

    if commandDetailResponseEditBox then
        if currentResponseText ~= tostring(selectedCommandRow.response or "") then
            commandDetailResponseEditBox:SetTextColor(0, 1, 0)
        else
            commandDetailResponseEditBox:SetTextColor(1, 1, 1)
        end
    end
end

local function UpdateCommandDetailDirtyState()
    if not commandDetailStatusText then
        return
    end

    if not selectedCommandRow or selectedCommandRow.isDeleted then
        commandDetailStatusText:SetText("")
        commandDetailStatusText:Hide()
        RefreshCommandDetailInputColors()
        return
    end

    if not IsCurrentPresetEditable() then
        commandDetailStatusText:SetText("|cffaaaaaaDefault preset is locked and cannot be edited.|r")
        commandDetailStatusText:Show()
        RefreshCommandDetailInputColors()
        return
    end

    if selectedCommandRow.isSystemCommand then
        commandDetailStatusText:SetText("|cffaaaaaaThis command is built-in and cannot be edited or deleted.|r")
        commandDetailStatusText:Show()
        RefreshCommandDetailInputColors()
        return
    end

    local currentCommandText = ""
    local currentResponseText = ""

    if commandDetailCommandEditBox then
        currentCommandText = SanitizeCommandText(commandDetailCommandEditBox:GetText() or "")
    end

    if commandDetailResponseEditBox then
        currentResponseText = LimitTextLength(commandDetailResponseEditBox:GetText() or "", RESPONSE_MAX_LENGTH)
    end

    RefreshCommandDetailInputColors()

    if currentCommandText ~= tostring(selectedCommandRow.command or "") or currentResponseText ~= tostring(selectedCommandRow.response or "") then
        if TrimText(currentCommandText) == "" then
            commandDetailStatusText:SetText("|cffff3b30Command Required|r")
            commandDetailStatusText:Show()
        elseif TrimText(currentResponseText) == "" then
            commandDetailStatusText:SetText("|cffff3b30Response Required|r")
            commandDetailStatusText:Show()
        elseif IsReservedHelpAlias(currentCommandText) then
            commandDetailStatusText:SetText("|cffff3b30Reserved Command|r")
            commandDetailStatusText:Show()
        elseif DoesCommandExist(currentCommandText, selectedCommandRow) then
            commandDetailStatusText:SetText("|cffff3b30Duplicate Command|r")
            commandDetailStatusText:Show()
        else
            commandDetailStatusText:SetText("|cffffff00Not Saved|r")
            commandDetailStatusText:Show()
        end
    else
        commandDetailStatusText:SetText("")
        commandDetailStatusText:Hide()
    end
end

local function RefreshCommandListButtonText(button)
    if not button or not button.row then
        return
    end

    local commandText = TrimText(button.row.command or "")

    if button.row.isSystemCommand then
        commandText = HELP_COMMAND_DISPLAY_TEXT
    elseif commandText == "" then
        commandText = "<New Command>"
    end

    if button.row.hasDuplicate then
        commandText = commandText .. " |cffff3b30(Dup)|r"
    end

    button:SetText(commandText)
end

local function RefreshSelectedCommandListPreview()
    if not selectedCommandRow or selectedCommandRow.isDeleted or selectedCommandRow.isSystemCommand then
        return
    end

    if not commandDetailCommandEditBox then
        return
    end

    local buttonIndex = 1
    local selectedButton = nil

    while buttonIndex <= #commandListButtons do
        local currentButton = commandListButtons[buttonIndex]
        if currentButton and currentButton.row == selectedCommandRow then
            selectedButton = currentButton
            break
        end
        buttonIndex = buttonIndex + 1
    end

    if not selectedButton then
        return
    end

    local draftCommandText = SanitizeCommandText(commandDetailCommandEditBox:GetText() or "")
    local displayText = TrimText(draftCommandText or "")

    if displayText == "" then
        displayText = "<New Command>"
    end

    if IsReservedHelpAlias(draftCommandText or "") or DoesCommandExist(draftCommandText or "", selectedCommandRow) then
        displayText = displayText .. " |cffff3b30(Dup)|r"
    end

    selectedButton:SetText(displayText)

    if selectedButton:GetFontString() then
        selectedButton:GetFontString():SetTextColor(0, 1, 0)
    end
end

local function RefreshCommandButtonSelection()
    local index = 1
    while index <= #commandListButtons do
        local button = commandListButtons[index]
        if button and button.row and button:GetFontString() then
            RefreshCommandListButtonText(button)

            if button.row == selectedCommandRow then
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

local function RefreshCommandDetailControlStates()
    if not commandDetailCommandEditBox or not commandDetailResponseEditBox or not commandDetailSaveBtn or not commandDetailDeleteBtn then
        return
    end

    if not selectedCommandRow or selectedCommandRow.isDeleted then
        SetEditBoxInteractionEnabled(commandDetailCommandEditBox, false)
        SetEditBoxInteractionEnabled(commandDetailResponseEditBox, false)
        commandDetailSaveBtn:Disable()
        commandDetailDeleteBtn:Disable()
        return
    end

    if not IsCurrentPresetEditable() then
        SetEditBoxInteractionEnabled(commandDetailCommandEditBox, false)
        SetEditBoxInteractionEnabled(commandDetailResponseEditBox, false)
        commandDetailSaveBtn:Disable()
        commandDetailDeleteBtn:Disable()
        return
    end

    if selectedCommandRow.isSystemCommand then
        SetEditBoxInteractionEnabled(commandDetailCommandEditBox, false)
        SetEditBoxInteractionEnabled(commandDetailResponseEditBox, false)
        commandDetailSaveBtn:Disable()
        commandDetailDeleteBtn:Disable()
    else
        SetEditBoxInteractionEnabled(commandDetailCommandEditBox, true)
        SetEditBoxInteractionEnabled(commandDetailResponseEditBox, true)
        commandDetailSaveBtn:Enable()
        commandDetailDeleteBtn:Enable()
    end
end

local function LoadSelectedCommandToDetailPanel()
    if not commandDetailPanel then
        return
    end

    if not selectedCommandRow or selectedCommandRow.isDeleted then
        commandDetailPanel:Hide()

        if commandDetailEmptyText then
            commandDetailEmptyText:Show()
        end

        RefreshCommandDetailControlStates()
        RefreshCommandDetailInputColors()
        return
    end

    if commandDetailEmptyText then
        commandDetailEmptyText:Hide()
    end

    commandDetailPanel:Show()

    if selectedCommandRow.isSystemCommand then
        if commandDetailCommandEditBox then
            commandDetailCommandEditBox:SetText(HELP_COMMAND_DISPLAY_TEXT)
        end

        if commandDetailResponseEditBox then
            commandDetailResponseEditBox:SetText("This is a built-in command. Players can type !help or !commands to receive the full command list.")
        end
    else
        if commandDetailCommandEditBox then
            commandDetailCommandEditBox:SetText(selectedCommandRow.command or "")
        end

        if commandDetailResponseEditBox then
            commandDetailResponseEditBox:SetText(selectedCommandRow.response or "")
        end
    end

    RefreshCommandDetailControlStates()
    RefreshCommandDetailInputColors()
    UpdateCommandDetailDirtyState()
    RefreshCommandButtonSelection()
end

local function SelectCommandRow(row)
    selectedCommandRow = row
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

local function RefreshCommandListUI()
    if not commandContentFrame then
        return
    end

    ClearCommandListButtons()

    local visibleRows = GetVisibleCommandRows()
    local index = 1

    while index <= #visibleRows do
        local row = visibleRows[index]
        local button = commandListButtons[index]

        if not button then
            button = CreateFrame("Button", nil, commandContentFrame, "UIPanelButtonTemplate")
            button:SetHeight(24)
            commandListButtons[index] = button
        end

        button:Show()
        button:SetParent(commandContentFrame)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", 0, -((index - 1) * 28))
        button:SetPoint("TOPRIGHT", 0, -((index - 1) * 28))
        button.row = row

        RefreshCommandListButtonText(button)

        button:SetScript("OnClick", function(self)
            if self.row then
                SelectCommandRow(self.row)
            end
        end)

        index = index + 1
    end

    local hideIndex = #visibleRows + 1
    while hideIndex <= #commandListButtons do
        local button = commandListButtons[hideIndex]
        if button then
            button:Hide()
            button:ClearAllPoints()
            button.row = nil
            button:SetText("")
        end
        hideIndex = hideIndex + 1
    end

    local totalHeight = (#visibleRows * 28)
    if totalHeight < 1 then
        totalHeight = 1
    end

    commandContentFrame:SetHeight(totalHeight)
    RefreshCommandButtonSelection()

    if TryGetElvUISkinModule then
        local eValue, sValue = TryGetElvUISkinModule()
        if eValue and sValue then
            local buttonIndex = 1
            while buttonIndex <= #visibleRows do
                local button = commandListButtons[buttonIndex]
                if button and not button.isSkinned then
                    sValue:HandleButton(button)
                    button.isSkinned = true
                end
                buttonIndex = buttonIndex + 1
            end
        end
    end
end

local function CreateCommandRow(commandValue, responseValue)
    local row = {
        command = SanitizeCommandText(commandValue or ""),
        response = LimitTextLength(responseValue or "", RESPONSE_MAX_LENGTH),
        isDeleted = false,
        hasDuplicate = false,
        isSystemCommand = false
    }

    if IsReservedHelpAlias(row.command) then
        row.command = ""
        row.response = ""
    end

    commandRows[#commandRows + 1] = row

    RefreshAllDuplicateStates()
    RefreshAddCommandButtonState()

    return row
end

local function SaveSelectedCommandDetail()
    if not IsCurrentPresetEditable() then
        if commandDetailStatusText then
            commandDetailStatusText:SetText("|cffaaaaaaDefault preset is locked and cannot be edited.|r")
            commandDetailStatusText:Show()
        end
        return
    end

    if not selectedCommandRow or selectedCommandRow.isDeleted then
        return
    end

    if selectedCommandRow.isSystemCommand then
        return
    end

    local commandText = SanitizeCommandText(commandDetailCommandEditBox:GetText() or "")
    local responseText = TrimText(commandDetailResponseEditBox:GetText() or "")

    responseText = LimitTextLength(responseText, RESPONSE_MAX_LENGTH)

    if commandText == "" then
        if commandDetailStatusText then
            commandDetailStatusText:SetText("|cffff3b30Command Required|r")
            commandDetailStatusText:Show()
        end
        return
    end

    if responseText == "" then
        if commandDetailStatusText then
            commandDetailStatusText:SetText("|cffff3b30Response Required|r")
            commandDetailStatusText:Show()
        end
        return
    end

    if IsReservedHelpAlias(commandText) then
        if commandDetailStatusText then
            commandDetailStatusText:SetText("|cffff3b30Reserved Command|r")
            commandDetailStatusText:Show()
        end
        return
    end

    if DoesCommandExist(commandText, selectedCommandRow) then
        if commandDetailStatusText then
            commandDetailStatusText:SetText("|cffff3b30Duplicate Command|r")
            commandDetailStatusText:Show()
        end
        return
    end

    selectedCommandRow.command = commandText
    selectedCommandRow.response = responseText

    RefreshAllDuplicateStates()
    SaveAllCommandRowsToPreset()
    RefreshCommandListUI()
    RefreshAddCommandButtonState()
    LoadSelectedCommandToDetailPanel()

    if commandDetailStatusText then
        commandDetailStatusText:SetText("")
        commandDetailStatusText:Hide()
    end
end

local function DeleteSelectedCommandDetailConfirmed()
    if not IsCurrentPresetEditable() then
        return
    end

    if not selectedCommandRow or selectedCommandRow.isDeleted then
        return
    end

    if selectedCommandRow.isSystemCommand then
        return
    end

    selectedCommandRow.isDeleted = true
    selectedCommandRow = nil

    RefreshAllDuplicateStates()
    SaveAllCommandRowsToPreset()
    RefreshCommandListUI()
    SelectTopVisibleCommandRow()
    RefreshAddCommandButtonState()
end

local function GetSelectedCommandDisplayName()
    if not selectedCommandRow or selectedCommandRow.isDeleted then
        return "this command"
    end

    if selectedCommandRow.isSystemCommand then
        return HELP_COMMAND_DISPLAY_TEXT
    end

    local commandText = TrimText(selectedCommandRow.command or "")
    if commandText == "" then
        return "<New Command>"
    end

    return commandText
end

local function GetSelectedPresetDisplayName()
    local presetName = GetSelectedPresetName()
    if not presetName or presetName == "" then
        return "this preset"
    end
    return presetName
end

local function ShowDeleteSelectedCommandPopup()
    if not selectedCommandRow or selectedCommandRow.isDeleted then
        return
    end

    if selectedCommandRow.isSystemCommand then
        return
    end

    if not IsCurrentPresetEditable() then
        return
    end

    StaticPopup_Show(AUTO_RESPONSE_COMMAND_DELETE_POPUP, GetSelectedCommandDisplayName())
end

local function SaveDefaultResponse()
    if not IsCurrentPresetEditable() then
        return
    end

    local presetData = GetActivePresetData()
    if not presetData then
        return
    end

    if not defaultResponseEditBox then
        return
    end

    presetData.defaultResponse = LimitTextLength(defaultResponseEditBox:GetText() or "", RESPONSE_MAX_LENGTH)

    defaultResponseSaveResetAt = GetTime() + 3
    RefreshDefaultResponseSaveButton()
    RefreshDefaultResponseInputColor()
end

local function LoadPresetIntoUI(presetName)
    EnsureSavedVariables()

    if not presetName or presetName == "" then
        return
    end

    if not RTAutoResponseSave.presets[presetName] then
        return
    end

    local presetData = RTAutoResponseSave.presets[presetName]

    SetSelectedPresetName(presetName)
    RefreshPresetActionButtons()
    StopRenameMode()

    if defaultResponseEditBox then
        defaultResponseEditBox:SetText(presetData.defaultResponse or "")
    end

    if defaultResponseCharCountText and defaultResponseEditBox then
        local currentLength = string.len(defaultResponseEditBox:GetText() or "")
        defaultResponseCharCountText:SetText(string.format("Characters: %d/%d", currentLength, RESPONSE_MAX_LENGTH))
    end

    defaultResponseSaveResetAt = 0
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

    local presetName = GetNextNewPresetName()

    RTAutoResponseSave.presets[presetName] = CopyPresetData({
        defaultResponse = "",
        commands = {}
    })

    RTAutoResponseSave.activePresetName = presetName
    LoadPresetIntoUI(presetName)
end

local function DeletePresetConfirmed(presetName)
    if not presetName or presetName == "" then
        return
    end

    EnsureSavedVariables()

    if presetName == CREATE_NEW_PRESET_LABEL then
        return
    end

    if IsProtectedPreset(presetName) then
        return
    end

    if not RTAutoResponseSave.presets[presetName] then
        return
    end

    RTAutoResponseSave.presets[presetName] = nil

    SetSelectedPresetName(DEFAULT_PRESET_NAME)
    LoadPresetIntoUI(DEFAULT_PRESET_NAME)
end

local function ShowDeletePresetPopup()
    local presetName = GetSelectedPresetName()
    if not presetName or presetName == "" then
        return
    end

    if presetName == CREATE_NEW_PRESET_LABEL then
        return
    end

    if IsProtectedPreset(presetName) then
        return
    end

    StaticPopup_Show(AUTO_RESPONSE_PRESET_DELETE_POPUP, GetSelectedPresetDisplayName())
end

local function CreatePresetDropdown(parentFrame)
    local dropdownWidth = 220
    local dropdownHeight = 24

    presetDropdownButton = CreateFrame("Button", nil, parentFrame, "UIPanelButtonTemplate")
    presetDropdownButton:SetSize(dropdownWidth, dropdownHeight)
    presetDropdownButton:SetText("")

    presetDropdownText = presetDropdownButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    presetDropdownText:SetPoint("LEFT", presetDropdownButton, "LEFT", 10, 0)
    presetDropdownText:SetJustifyH("LEFT")
    presetDropdownText:SetWidth(dropdownWidth - 20)

    SetSelectedPresetName(nil)

    local menuFrame = CreateFrame("Frame", addonName .. "AutoResponsePresetDropdownMenu", UIParent, "UIDropDownMenuTemplate")
    local isMenuOpen = false

    presetDropdownButton:SetScript("OnClick", function(self)
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

                if presetName == CREATE_NEW_PRESET_LABEL then
                    menuText = "|cff00ff00" .. presetName .. "|r"
                end

                menuList[menuIndex] = {
                    text = menuText,
                    checked = presetName ~= CREATE_NEW_PRESET_LABEL and GetSelectedPresetName() == presetName,
                    func = function()
                        isMenuOpen = false

                        if presetName == CREATE_NEW_PRESET_LABEL then
                            CreateNewPreset()
                        else
                            LoadPresetIntoUI(presetName)
                        end
                    end
                }

                menuIndex = menuIndex + 1
            end
        end

        EasyMenu(menuList, menuFrame, self, 0, 0, "MENU")
        isMenuOpen = true
    end)

    presetDropdownButton:HookScript("OnHide", function()
        isMenuOpen = false
    end)
end

local function RefreshEnableButton()
    if not enableBtn then
        return
    end

    if isAutoResponseEnabled then
        enableBtn:SetText("|cff00ff00Enabled|r")
    else
        enableBtn:SetText("Enable Auto Response")
    end
end

local function GetMatchedResponseForWhisper(messageText)
    EnsureSavedVariables()

    local presetName = RTAutoResponseSave.activePresetName
    if not presetName or presetName == "" then
        return nil, false
    end

    local presetData = RTAutoResponseSave.presets[presetName]
    if not presetData then
        return nil, false
    end

    local normalizedIncomingMessage = NormalizeCommandText(messageText)

    local index = 1
    while presetData.commands and presetData.commands[index] do
        local commandData = presetData.commands[index]
        local normalizedCommand = NormalizeCommandText(commandData.command or "")

        if normalizedCommand ~= "" and normalizedIncomingMessage == normalizedCommand then
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
    local normalizedIncomingMessage = NormalizeCommandText(messageText)
    if normalizedIncomingMessage == NormalizeCommandText(HELP_COMMAND_PRIMARY) then
        return true
    end
    if normalizedIncomingMessage == NormalizeCommandText(HELP_COMMAND_SECONDARY) then
        return true
    end
    return false
end

local function GetCommandListMessages()
    EnsureSavedVariables()

    local resultMessages = {}
    local presetName = RTAutoResponseSave.activePresetName
    local presetData = nil

    if presetName and presetName ~= "" then
        presetData = RTAutoResponseSave.presets[presetName]
    end

    if not presetData or not presetData.commands then
        resultMessages[1] = "There are no saved commands in this preset."
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
        resultMessages[1] = "There are no saved commands in this preset."
        return resultMessages
    end

    table.sort(commandNames, function(leftValue, rightValue)
        return string.lower(leftValue) < string.lower(rightValue)
    end)

    local prefix = "Available commands: "
    local currentMessage = prefix
    local commandIndex = 1

    while commandIndex <= #commandNames do
        local commandText = commandNames[commandIndex]
        local additionText = commandText

        if currentMessage ~= prefix then
            additionText = ", " .. commandText
        end

        if string.len(currentMessage .. additionText) <= CHAT_MESSAGE_MAX_LENGTH then
            currentMessage = currentMessage .. additionText
        else
            resultMessages[#resultMessages + 1] = currentMessage

            if string.len(prefix .. commandText) <= CHAT_MESSAGE_MAX_LENGTH then
                currentMessage = prefix .. commandText
            else
                local oversizedCommand = LimitTextLength(commandText, CHAT_MESSAGE_MAX_LENGTH - string.len(prefix))
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
            SendChatMessage(LimitTextLength(messageText, CHAT_MESSAGE_MAX_LENGTH), "WHISPER", nil, senderName)
        end
        index = index + 1
    end
end

StaticPopupDialogs[AUTO_RESPONSE_PRESET_DELETE_POPUP] = {
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

StaticPopupDialogs[AUTO_RESPONSE_COMMAND_DELETE_POPUP] = {
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

eventFrame:RegisterEvent("CHAT_MSG_WHISPER")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event ~= "CHAT_MSG_WHISPER" then
        return
    end

    EnsureSavedVariables()

    if not isAutoResponseEnabled then
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
        local lastSentTime = defaultResponseThrottleBySender[senderName]

        if lastSentTime and (currentTime - lastSentTime) < DEFAULT_RESPONSE_COOLDOWN_SECONDS then
            return
        end

        defaultResponseThrottleBySender[senderName] = currentTime
    end

    SendChatMessage(responseText, "WHISPER", nil, senderName)

    if isDefaultResponse then
        SendChatMessage(COMMAND_HELP_GUIDE_MESSAGE, "WHISPER", nil, senderName)
    end
end)

loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, arg1)
    if arg1 == addonName then
        EnsureSavedVariables()
        isAutoResponseEnabled = RTAutoResponseSave.enabled and true or false
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

function CreateAutoResponseTabContent(parent, onClose)
    EnsureSavedVariables()

    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    f:Hide()

    local topLeftX = 25
    local topRowY = -20

    local loadPresetLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    loadPresetLabel:SetPoint("TOPLEFT", topLeftX, topRowY)
    loadPresetLabel:SetText("Load Preset:")

    CreatePresetDropdown(f)
    presetDropdownButton:SetPoint("LEFT", loadPresetLabel, "RIGHT", 10, 0)

    renamePresetBG = CreateFrame("Frame", nil, f)
    ApplyPixelStyle(renamePresetBG, 220, 24)
    renamePresetBG:SetPoint("LEFT", loadPresetLabel, "RIGHT", 10, 0)
    renamePresetBG:Hide()

    renamePresetEditBox = CreateFrame("EditBox", nil, renamePresetBG)
    renamePresetEditBox:SetAllPoints()
    renamePresetEditBox:SetAutoFocus(false)
    renamePresetEditBox:SetFontObject(ChatFontNormal)
    renamePresetEditBox:SetJustifyH("LEFT")
    renamePresetEditBox:SetMaxLetters(PRESET_NAME_MAX_LENGTH)
    renamePresetEditBox:Hide()

    renamePresetEditBox:SetScript("OnTextChanged", function(self)
        local currentText = self:GetText() or ""
        if string.len(currentText) > PRESET_NAME_MAX_LENGTH then
            self:SetText(string.sub(currentText, 1, PRESET_NAME_MAX_LENGTH))
            self:SetCursorPosition(PRESET_NAME_MAX_LENGTH)
        end
    end)

    renamePresetEditBox:SetScript("OnEnterPressed", function(self)
        RenameSelectedPreset(self:GetText() or "")
    end)

    renamePresetEditBox:SetScript("OnEscapePressed", function()
        StopRenameMode()
    end)

    renamePresetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    renamePresetBtn:SetSize(80, 24)
    renamePresetBtn:SetPoint("LEFT", presetDropdownButton, "RIGHT", 8, 0)
    renamePresetBtn:SetText("Rename")
    renamePresetBtn.isRenaming = false
    renamePresetBtn:SetScript("OnClick", function()
        if renamePresetBtn.isRenaming then
            RenameSelectedPreset(renamePresetEditBox:GetText() or "")
        else
            StartRenameMode()
        end
    end)

    deletePresetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    deletePresetBtn:SetSize(80, 24)
    deletePresetBtn:SetPoint("LEFT", renamePresetBtn, "RIGHT", 8, 0)
    deletePresetBtn:SetText("Delete")
    deletePresetBtn:SetScript("OnClick", function()
        ShowDeletePresetPopup()
    end)

    defaultResponseLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    defaultResponseLabel:SetPoint("TOPLEFT", 25, -60)
    defaultResponseLabel:SetText("Default Response:")

    defaultResponseSaveBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    defaultResponseSaveBtn:SetSize(80, 24)
    defaultResponseSaveBtn:SetPoint("TOPRIGHT", -25, -56)
    defaultResponseSaveBtn:SetText("Save")
    defaultResponseSaveBtn:SetScript("OnClick", function()
        SaveDefaultResponse()
    end)

    local defaultResponseBG = CreateFrame("Frame", nil, f)
    ApplyPixelStyle(defaultResponseBG)
    defaultResponseBG:SetPoint("TOPLEFT", 25, -84)
    defaultResponseBG:SetPoint("TOPRIGHT", -25, -84)
    defaultResponseBG:SetHeight(60)

    defaultResponseEditBox = CreateFrame("EditBox", nil, defaultResponseBG)
    defaultResponseEditBox:SetMultiLine(true)
    defaultResponseEditBox:SetMaxLetters(RESPONSE_MAX_LENGTH)
    defaultResponseEditBox:SetFontObject(ChatFontNormal)
    defaultResponseEditBox:SetPoint("TOPLEFT", 8, -8)
    defaultResponseEditBox:SetPoint("BOTTOMRIGHT", -8, 8)
    defaultResponseEditBox:SetAutoFocus(false)

    defaultResponseEditBox:SetScript("OnTextChanged", function(self)
        local textValue = self:GetText() or ""
        local textLength = string.len(textValue)

        if defaultResponseCharCountText then
            defaultResponseCharCountText:SetText(string.format("Characters: %d/%d", textLength, RESPONSE_MAX_LENGTH))
        end

        RefreshDefaultResponseInputColor()
        RefreshDefaultResponseSaveButton()
    end)

    defaultResponseEditBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    defaultResponseEditBox:SetScript("OnMouseDown", function(self)
        if IsCurrentPresetEditable() then
            self:SetFocus()
        end
    end)

    defaultResponseCharCountText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    defaultResponseCharCountText:SetPoint("TOPRIGHT", defaultResponseBG, "BOTTOMRIGHT", 0, -5)
    defaultResponseCharCountText:SetText("Characters: 0/255")

    addCommandBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    addCommandBtn:SetSize(140, 24)
    addCommandBtn:SetPoint("TOPLEFT", 25, -160)
    addCommandBtn:SetText("Add New Command")
    addCommandBtn:SetScript("OnClick", function()
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

    commandScrollFrame = CreateFrame("ScrollFrame", addonName .. "AutoResponseCommandScrollFrame", leftPaneBG, "UIPanelScrollFrameTemplate")
    commandScrollFrame:SetPoint("TOPLEFT", 10, -34)
    commandScrollFrame:SetPoint("BOTTOMRIGHT", -28, 10)

    commandContentFrame = CreateFrame("Frame", nil, commandScrollFrame)
    commandContentFrame:SetWidth(320)
    commandContentFrame:SetHeight(1)
    commandScrollFrame:SetScrollChild(commandContentFrame)

    commandDetailEmptyText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    commandDetailEmptyText:SetPoint("TOPLEFT", leftPaneBG, "TOPRIGHT", 24, -20)
    commandDetailEmptyText:SetText("Select a command to view details.")

    commandDetailPanel = CreateFrame("Frame", nil, f)
    ApplyPixelStyle(commandDetailPanel)
    commandDetailPanel:SetPoint("TOPLEFT", leftPaneBG, "TOPRIGHT", 20, 0)
    commandDetailPanel:SetPoint("TOPRIGHT", -25, -190)
    commandDetailPanel:SetPoint("BOTTOMRIGHT", -25, 60)

    commandDetailSaveBtn = CreateFrame("Button", nil, commandDetailPanel, "UIPanelButtonTemplate")
    commandDetailSaveBtn:SetHeight(24)
    commandDetailSaveBtn:SetPoint("TOPLEFT", 12, -12)
    commandDetailSaveBtn:SetPoint("TOPRIGHT", commandDetailPanel, "TOP", -4, -12)
    commandDetailSaveBtn:SetText("Save")
    commandDetailSaveBtn:SetScript("OnClick", function()
        SaveSelectedCommandDetail()
    end)

    commandDetailDeleteBtn = CreateFrame("Button", nil, commandDetailPanel, "UIPanelButtonTemplate")
    commandDetailDeleteBtn:SetHeight(24)
    commandDetailDeleteBtn:SetPoint("TOPLEFT", commandDetailPanel, "TOP", 4, -12)
    commandDetailDeleteBtn:SetPoint("TOPRIGHT", -12, -12)
    commandDetailDeleteBtn:SetText("Delete")
    commandDetailDeleteBtn:SetScript("OnClick", function()
        ShowDeleteSelectedCommandPopup()
    end)

    commandDetailStatusText = commandDetailPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    commandDetailStatusText:SetPoint("TOP", 0, -40)
    commandDetailStatusText:SetText("")

    commandDetailCommandEditBG = CreateFrame("Frame", nil, commandDetailPanel)
    ApplyPixelStyle(commandDetailCommandEditBG)
    commandDetailCommandEditBG:SetPoint("TOPLEFT", 12, -82)
    commandDetailCommandEditBG:SetPoint("TOPRIGHT", -12, -82)
    commandDetailCommandEditBG:SetHeight(28)

    commandDetailCommandLabel = commandDetailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    commandDetailCommandLabel:SetPoint("BOTTOM", commandDetailCommandEditBG, "TOP", 0, 8)
    commandDetailCommandLabel:SetJustifyH("CENTER")
    commandDetailCommandLabel:SetText("Command")

    commandDetailCommandEditBox = CreateFrame("EditBox", nil, commandDetailCommandEditBG)
    commandDetailCommandEditBox:SetAllPoints()
    commandDetailCommandEditBox:SetAutoFocus(false)
    commandDetailCommandEditBox:SetFontObject(ChatFontNormal)
    commandDetailCommandEditBox:SetJustifyH("LEFT")
    commandDetailCommandEditBox:SetMaxLetters(COMMAND_NAME_MAX_LENGTH)

    commandDetailCommandEditBox:SetScript("OnTextChanged", function(self)
        if selectedCommandRow and selectedCommandRow.isSystemCommand then
            return
        end

        if not IsCurrentPresetEditable() then
            RefreshCommandDetailInputColors()
            UpdateCommandDetailDirtyState()
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
            RefreshSelectedCommandListPreview()
            UpdateCommandDetailDirtyState()
            return
        end

        UpdateCommandDetailDirtyState()
        RefreshSelectedCommandListPreview()
    end)

    commandDetailCommandEditBox:SetScript("OnEnterPressed", function()
        SaveSelectedCommandDetail()
    end)

    commandDetailCommandEditBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    commandDetailResponseBG = CreateFrame("Frame", nil, commandDetailPanel)
    ApplyPixelStyle(commandDetailResponseBG)
    commandDetailResponseBG:SetPoint("TOPLEFT", 12, -144)
    commandDetailResponseBG:SetPoint("BOTTOMRIGHT", -12, 12)

    commandDetailResponseLabel = commandDetailPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    commandDetailResponseLabel:SetPoint("BOTTOM", commandDetailResponseBG, "TOP", 0, 8)
    commandDetailResponseLabel:SetJustifyH("CENTER")
    commandDetailResponseLabel:SetText("Response")

    commandDetailResponseEditBox = CreateFrame("EditBox", nil, commandDetailResponseBG)
    commandDetailResponseEditBox:SetMultiLine(true)
    commandDetailResponseEditBox:SetFontObject(ChatFontNormal)
    commandDetailResponseEditBox:SetPoint("TOPLEFT", 6, -6)
    commandDetailResponseEditBox:SetPoint("BOTTOMRIGHT", -6, 6)
    commandDetailResponseEditBox:SetAutoFocus(false)
    commandDetailResponseEditBox:SetMaxLetters(RESPONSE_MAX_LENGTH)

    commandDetailResponseEditBox:SetScript("OnTextChanged", function(self)
        if selectedCommandRow and selectedCommandRow.isSystemCommand then
            return
        end

        if not IsCurrentPresetEditable() then
            RefreshCommandDetailInputColors()
            UpdateCommandDetailDirtyState()
            return
        end

        local currentText = self:GetText() or ""
        if string.len(currentText) > RESPONSE_MAX_LENGTH then
            self:SetText(string.sub(currentText, 1, RESPONSE_MAX_LENGTH))
            self:SetCursorPosition(RESPONSE_MAX_LENGTH)
            RefreshSelectedCommandListPreview()
            UpdateCommandDetailDirtyState()
            return
        end

        UpdateCommandDetailDirtyState()
        RefreshSelectedCommandListPreview()
    end)

    commandDetailResponseEditBox:SetScript("OnEnterPressed", function()
        SaveSelectedCommandDetail()
    end)

    commandDetailResponseEditBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    commandDetailPanel:Hide()

    enableBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    enableBtn:SetSize(170, 28)
    enableBtn:SetPoint("BOTTOMRIGHT", -18, 18)
    enableBtn:SetText("Enable Auto Response")
    enableBtn:SetScript("OnClick", function()
        isAutoResponseEnabled = not isAutoResponseEnabled
        RTAutoResponseSave.enabled = isAutoResponseEnabled and true or false
        RefreshEnableButton()
    end)

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    closeBtn:SetSize(100, 28)
    closeBtn:SetPoint("RIGHT", enableBtn, "LEFT", -10, 0)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", onClose)

    f:SetScript("OnUpdate", function()
        RefreshDefaultResponseSaveButton()
    end)

    f:SetScript("OnShow", function()
        EnsureSavedVariables()

        local activePresetName = RTAutoResponseSave.activePresetName
        if not activePresetName or activePresetName == "" or not RTAutoResponseSave.presets[activePresetName] then
            activePresetName = DEFAULT_PRESET_NAME
        end

        LoadPresetIntoUI(activePresetName)
        RefreshPresetActionButtons()
        RefreshEnableButton()
        RefreshDefaultResponseControlStates()
    end)

    if TryGetElvUISkinModule then
        local eValue, sValue = TryGetElvUISkinModule()
        if eValue and sValue then
            sValue:HandleButton(presetDropdownButton)
            sValue:HandleButton(renamePresetBtn)
            sValue:HandleButton(deletePresetBtn)
            sValue:HandleButton(defaultResponseSaveBtn)
            sValue:HandleButton(addCommandBtn)
            sValue:HandleButton(commandDetailDeleteBtn)
            sValue:HandleButton(commandDetailSaveBtn)
            sValue:HandleButton(enableBtn)
            sValue:HandleButton(closeBtn)
        end
    end

    RefreshPresetActionButtons()
    RefreshEnableButton()
    RefreshAddCommandButtonState()
    StopRenameMode()
    RefreshDefaultResponseSaveButton()
    RefreshDefaultResponseControlStates()

    return f
end