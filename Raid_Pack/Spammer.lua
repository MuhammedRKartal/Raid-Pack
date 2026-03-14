-- Spammer.lua

local addonName = ...
local addonTable = select(2, ...)

local isSpamming = false
local channelRows = {}
local msgEditBox, charCountText, startBtn, msgLabel
local presetDropdownButton, presetDropdownText
local renamePresetBtn, renamePresetBG, renamePresetEditBox, deletePresetBtn, savePresetBtn
local saveFeedbackResetAt = 0

local CREATE_NEW_PRESET_LABEL = "Create New"
local CREATE_NEW_PRESET_BASE_NAME = "New Message"
local DEFAULT_PRESET_NAME = "Weakauras Discord"
local DEFAULT_PRESET_MESSAGE = "Need a new UI or nice Weakauras to track everything?  Come Join the Weakaura Center: https://discord.gg/7E6jAPsJD9"
local PRESET_NAME_MAX_LENGTH = 21

local defaultCurrentSettings = {
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
}

local defaultEmbeddedPreset = {
    message = DEFAULT_PRESET_MESSAGE
}

local channelPool = {
    { name = "General", chatType = "CHANNEL" },
    { name = "Trade", chatType = "CHANNEL" },
    { name = "World", chatType = "CHANNEL" },
    { name = "YELL", chatType = "YELL" },
}

local selectedPresetName = nil
local updateFrame = CreateFrame("Frame")

local CopyCurrentSettings
local CopyPresetSettings
local GetSelectedPresetName

function RT_IsSpammerEnabled()
    return isSpamming
end

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

    for channelName, intervalValue in pairs(defaultCurrentSettings.intervals) do
        if result.intervals[channelName] == nil then
            result.intervals[channelName] = intervalValue
        end
    end

    for channelName, enabledValue in pairs(defaultCurrentSettings.enabledChannels) do
        if result.enabledChannels[channelName] == nil then
            result.enabledChannels[channelName] = enabledValue
        end
    end

    return result
end

CopyPresetSettings = function(source)
    local result = {
        message = ""
    }

    if source then
        result.message = source.message or ""
    end

    return result
end

local function EnsureSavedVariables()
    if not RTSpammerSave then
        RTSpammerSave = {}
    end

    if type(RTSpammerSave) ~= "table" then
        RTSpammerSave = {}
    end

    if type(RTSpammerSave.current) ~= "table" then
        RTSpammerSave.current = CopyCurrentSettings(defaultCurrentSettings)
    else
        RTSpammerSave.current = CopyCurrentSettings(RTSpammerSave.current)
    end

    if type(RTSpammerSave.presets) ~= "table" then
        RTSpammerSave.presets = {}
    end

    for presetName, presetData in pairs(RTSpammerSave.presets) do
        RTSpammerSave.presets[presetName] = CopyPresetSettings(presetData)
    end

    if RTSpammerSave.activePresetName ~= nil and type(RTSpammerSave.activePresetName) ~= "string" then
        RTSpammerSave.activePresetName = nil
    end

    RTSpammerSave.presets[DEFAULT_PRESET_NAME] = CopyPresetSettings(defaultEmbeddedPreset)
end

local function DisableSpammingOnly()
    isSpamming = false
    RefreshStatusOverlay()

    if startBtn then
        startBtn:SetText("Start Spamming")
    end
end

local function StopSpammingState()
    isSpamming = false
    RefreshStatusOverlay()

    if startBtn then
        startBtn:SetText("Start Spamming")
    end

    for _, row in ipairs(channelRows) do
        row.nextSend = 0

        if row.cdText then
            row.cdText:SetText("|cff888888Ready|r")
        end
    end
end

local function GetSavedMessageForCurrentSelection()
    EnsureSavedVariables()

    local presetName = GetSelectedPresetName()

    if presetName and presetName ~= "" and presetName ~= CREATE_NEW_PRESET_LABEL then
        if RTSpammerSave.presets[presetName] then
            return RTSpammerSave.presets[presetName].message or ""
        end
    end

    return ""
end

local function GetMessageToSend()
    EnsureSavedVariables()

    local presetName = GetSelectedPresetName()

    if presetName and presetName ~= "" and presetName ~= CREATE_NEW_PRESET_LABEL then
        local presetData = RTSpammerSave.presets[presetName]

        if presetData and (presetData.message or "") ~= "" then
            return presetData.message or ""
        end

        return ""
    end

    return ""
end

local function UpdateMessageDirtyState()
    if not msgLabel then
        return
    end

    local currentMessage = ""
    local savedMessage = GetSavedMessageForCurrentSelection()

    if msgEditBox then
        currentMessage = msgEditBox:GetText() or ""
    end

    if currentMessage ~= savedMessage then
        msgLabel:SetText("Message to Spam |cffffcc00(Not Saved)|r")
    else
        msgLabel:SetText("Message to Spam:")
    end
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

local function SetSaveButtonVisual(textValue, redValue, greenValue, blueValue)
    if not savePresetBtn then
        return
    end

    savePresetBtn:SetText(textValue)

    local buttonText = savePresetBtn:GetFontString()
    if buttonText then
        buttonText:SetTextColor(redValue, greenValue, blueValue)
    end
end

local function ShowSavedFeedback()
    SetSaveButtonVisual("Saved", 0, 1, 0)
    saveFeedbackResetAt = GetTime() + 3
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

local function IsProtectedPreset(presetName)
    if presetName == DEFAULT_PRESET_NAME then
        return true
    end

    return false
end

local function RefreshPresetActionButtons()
    local presetName = selectedPresetName
    local canRenameOrDelete = false
    local canSave = false

    EnsureSavedVariables()

    if presetName and presetName ~= "" and presetName ~= CREATE_NEW_PRESET_LABEL and RTSpammerSave.presets[presetName] then
        if not IsProtectedPreset(presetName) then
            canRenameOrDelete = true
            canSave = true
        end
    end

    if savePresetBtn then
        if canSave then
            savePresetBtn:Enable()
            SetSaveButtonVisual("Save", 1, 0.82, 0)
        else
            SetSaveButtonVisual("Save", 0.5, 0.5, 0.5)
            savePresetBtn:Disable()
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

local function SetSelectedPresetName(presetName)
    selectedPresetName = presetName

    if presetDropdownText then
        if presetName and presetName ~= "" then
            presetDropdownText:SetText(presetName)
        else
            presetDropdownText:SetText("Select Preset")
        end
    end

    RefreshPresetActionButtons()
end

GetSelectedPresetName = function()
    return selectedPresetName
end

local function GetSortedPresetNames()
    EnsureSavedVariables()

    local presetNames = {}

    for presetName in pairs(RTSpammerSave.presets) do
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

    table.insert(presetNames, 1, CREATE_NEW_PRESET_LABEL)

    return presetNames
end

local function GetUniquePresetName(baseName)
    EnsureSavedVariables()

    local trimmedBaseName = LimitTextLength(TrimText(baseName or ""), PRESET_NAME_MAX_LENGTH)

    if trimmedBaseName == "" then
        return ""
    end

    if not RTSpammerSave.presets[trimmedBaseName] then
        return trimmedBaseName
    end

    local copySuffix = " (copy)"
    local indexedPrefix = " (copy "

    local candidateName = LimitTextLength(trimmedBaseName, PRESET_NAME_MAX_LENGTH - string.len(copySuffix)) .. copySuffix
    if not RTSpammerSave.presets[candidateName] then
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
        local candidateName = CREATE_NEW_PRESET_BASE_NAME .. " (" .. tostring(newIndex) .. ")"

        if string.len(candidateName) > PRESET_NAME_MAX_LENGTH then
            candidateName = LimitTextLength(candidateName, PRESET_NAME_MAX_LENGTH)
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

    for _, row in ipairs(channelRows) do
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

    for _, row in ipairs(channelRows) do
        local channelName = row.config.name
        local intervalValue = defaultCurrentSettings.intervals[channelName] or "30"
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
    if not msgEditBox then
        return
    end

    if presetData then
        msgEditBox:SetText(presetData.message or "")
    else
        msgEditBox:SetText("")
    end

    UpdateMessageDirtyState()
end

local function LoadCurrentSettingsToUI()
    local currentSettings = GetCurrentSettings()
    ApplyCurrentSettingsToUI(currentSettings)
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

local function SaveActivePreset()
    EnsureSavedVariables()

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

    if not RTSpammerSave.presets[presetName] then
        return
    end

    local currentMessage = ""

    if msgEditBox then
        currentMessage = msgEditBox:GetText() or ""
    end

    RTSpammerSave.presets[presetName] = CopyPresetSettings({
        message = currentMessage
    })
    RTSpammerSave.activePresetName = presetName

    UpdateMessageDirtyState()
end

local function CreateNewPreset()
    EnsureSavedVariables()
    DisableSpammingOnly()

    local presetName = GetNextNewPresetName()
    RTSpammerSave.presets[presetName] = CopyPresetSettings({
        message = ""
    })
    RTSpammerSave.activePresetName = presetName

    SetSelectedPresetName(presetName)
    StopRenameMode()

    LoadCurrentSettingsToUI()
    ApplyPresetMessageToUI(RTSpammerSave.presets[presetName])
end

local function LoadPreset(presetName)
    if not presetName or presetName == "" then
        return
    end

    if presetName == CREATE_NEW_PRESET_LABEL then
        CreateNewPreset()
        return
    end

    EnsureSavedVariables()

    if not RTSpammerSave.presets[presetName] then
        return
    end
    DisableSpammingOnly()

    RTSpammerSave.activePresetName = presetName

    SetSelectedPresetName(presetName)
    StopRenameMode()

    LoadCurrentSettingsToUI()
    ApplyPresetMessageToUI(RTSpammerSave.presets[presetName])
end

local function DeletePreset(presetName)
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

    if not RTSpammerSave.presets[presetName] then
        return
    end

    DisableSpammingOnly()

    RTSpammerSave.presets[presetName] = nil

    if RTSpammerSave.activePresetName == presetName then
        RTSpammerSave.activePresetName = nil
    end

    SetSelectedPresetName(nil)
    StopRenameMode()

    LoadCurrentSettingsToUI()
    ApplyPresetMessageToUI(nil)
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

    if not RTSpammerSave.presets[presetName] then
        return true
    end

    return false
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

    finalName = GetUniquePresetName(finalName)

    RTSpammerSave.presets[finalName] = CopyPresetSettings(RTSpammerSave.presets[oldName])
    RTSpammerSave.presets[oldName] = nil
    RTSpammerSave.activePresetName = finalName

    SetSelectedPresetName(finalName)
    StopRenameMode()
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

    local menuFrame = CreateFrame("Frame", addonName .. "PresetDropdownMenu", UIParent, "UIDropDownMenuTemplate")
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
                        LoadPreset(presetName)
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

local function HookChatLinks()
    local original = ChatEdit_InsertLink
    ChatEdit_InsertLink = function(link)
        if msgEditBox and msgEditBox:HasFocus() then
            msgEditBox:Insert(link)
            return true
        end

        return original(link)
    end
end
HookChatLinks()

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
        DeletePreset(GetSelectedPresetName())
    end)

    msgLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    msgLabel:SetPoint("TOPLEFT", 25, -60)
    msgLabel:SetText("Message to Spam:")

    savePresetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    savePresetBtn:SetSize(80, 24)
    savePresetBtn:SetPoint("TOPRIGHT", -25, -56)
    savePresetBtn:SetText("Save")
    savePresetBtn:SetScript("OnClick", function()
        SaveCurrentSettings()
        SaveActivePreset()
        UpdateMessageDirtyState()
        ShowSavedFeedback()
    end)

    local msgBG = CreateFrame("Frame", nil, f)
    ApplyPixelStyle(msgBG, 0, 80)
    msgBG:SetPoint("TOPLEFT", 25, -84)
    msgBG:SetPoint("TOPRIGHT", -25, -84)

    msgEditBox = CreateFrame("EditBox", nil, msgBG)
    msgEditBox:SetMultiLine(true)
    msgEditBox:SetMaxLetters(255)
    msgEditBox:SetFontObject(ChatFontNormal)
    msgEditBox:SetPoint("TOPLEFT", 8, -8)
    msgEditBox:SetPoint("BOTTOMRIGHT", -8, 8)
    msgEditBox:SetAutoFocus(false)

    msgEditBox:SetScript("OnTextChanged", function(self)
        local textValue = self:GetText() or ""
        local textLength = string.len(textValue)

        if charCountText then
            charCountText:SetText(string.format("Characters: %d/255", textLength))
        end

        UpdateMessageDirtyState()
    end)

    charCountText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    charCountText:SetPoint("TOPRIGHT", msgBG, "BOTTOMRIGHT", 0, -5)
    charCountText:SetText("Characters: 0/255")

    for i, config in ipairs(channelPool) do
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
        channelRows[i] = row
    end

    updateFrame:SetScript("OnUpdate", function(self, elapsed)
        if savePresetBtn and saveFeedbackResetAt > 0 and GetTime() >= saveFeedbackResetAt then
            SetSaveButtonVisual("Save", 1, 0.82, 0)
            saveFeedbackResetAt = 0
        end

        local now = GetTime()

        for _, row in ipairs(channelRows) do
            local remaining = row.nextSend - now

            if remaining > 0 then
                if row:IsShown() then
                    local colorCode = "|cff888888"

                    if isSpamming and row.check:GetChecked() then
                        colorCode = "|cff00ff00"
                    end

                    row.cdText:SetText(string.format("%s%.1fs|r", colorCode, remaining))
                end
            elseif isSpamming and row.check:GetChecked() then
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

        if RTSpammerSave.activePresetName and RTSpammerSave.activePresetName ~= "" and RTSpammerSave.presets[RTSpammerSave.activePresetName] then
            SetSelectedPresetName(RTSpammerSave.activePresetName)
            ApplyPresetMessageToUI(RTSpammerSave.presets[RTSpammerSave.activePresetName])
        else
            SetSelectedPresetName(nil)
            ApplyPresetMessageToUI(nil)
        end

        StopRenameMode()

        local visibleCount = 0

        for _, row in ipairs(channelRows) do
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

    startBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    startBtn:SetSize(170, 28)
    startBtn:SetPoint("BOTTOMRIGHT", -18, 12)
    startBtn:SetText("Start Spamming")

    startBtn:SetScript("OnClick", function()
        if not isSpamming then
            local textValue = ""

            local textValue = GetMessageToSend()

            if textValue == "" then
                return
            end

            isSpamming = true
            RefreshStatusOverlay()
            startBtn:SetText("|cff00ff00Enabled|r")

            local now = GetTime()

            for _, row in ipairs(channelRows) do
                local intervalValue = tonumber(row.timer:GetText()) or 30

                if row.config.name == "General" or row.config.name == "Trade" then
                    row.nextSend = now + intervalValue
                else
                    row.nextSend = now
                end
            end
        else
            isSpamming = false
            RefreshStatusOverlay()
            startBtn:SetText("Start Spamming")
        end
    end)

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    closeBtn:SetSize(100, 28)
    closeBtn:SetPoint("RIGHT", startBtn, "LEFT", -10, 0)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", onClose)

    if TryGetElvUISkinModule then
        local eValue, sValue = TryGetElvUISkinModule()

        if eValue and sValue then
            sValue:HandleButton(presetDropdownButton)
            sValue:HandleButton(renamePresetBtn)
            sValue:HandleButton(deletePresetBtn)
            sValue:HandleButton(savePresetBtn)
            sValue:HandleButton(startBtn)
            sValue:HandleButton(closeBtn)

            for _, row in ipairs(channelRows) do
                sValue:HandleCheckBox(row.check)
            end
        end
    end

    LoadCurrentSettingsToUI()
    RefreshPresetActionButtons()
    StopRenameMode()

    return f
end