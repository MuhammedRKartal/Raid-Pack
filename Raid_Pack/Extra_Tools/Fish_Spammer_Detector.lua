local addonName, addonTable = ...

local TITLE_TEXT = "Fish Spammer Detector"
local CONTENT_INSET = 12
local BUTTON_WIDTH = 140
local BUTTON_HEIGHT = 26
local CHECKBOX_SIZE = 24

local DEFAULT_SETTINGS = {
    spamWindowSeconds = 3,
    postSpamWindowSeconds = 6,
    cleanupWindowSeconds = 180,
    initialSpamThreshold = 4,
    hardSpamThreshold = 10,
    enableHarshMessage = true,
    enabled = true,
    debugMode = false,
}

local SETTINGS = nil
local FEAST_SPELL_NAMES = {
    ["Great Feast"] = true,
    ["Fish Feast"] = true,
}

local feastSpammingPlayers = {}
local detectorFrame = CreateFrame("Frame")

local function InitializeDB()
    if not RTFishSpammerDetectorDB then
        RTFishSpammerDetectorDB = {}
    end

    for key, value in pairs(DEFAULT_SETTINGS) do
        if RTFishSpammerDetectorDB[key] == nil then
            RTFishSpammerDetectorDB[key] = value
        end
    end

    SETTINGS = RTFishSpammerDetectorDB
end

local function GetSettings()
    if not SETTINGS then
        InitializeDB()
    end

    return SETTINGS
end

detectorFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
detectorFrame:RegisterEvent("GROUP_ROSTER_UPDATE")

local function DebugPrint(message)
    local settings = GetSettings()

    if not settings.debugMode then
        return
    end

    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99FishSpammerDetector:|r " .. tostring(message))
end

local function GetOutputChannel()
    if IsInRaid and IsInRaid() then
        return "RAID"
    end

    if IsInGroup and IsInGroup() then
        return "PARTY"
    end

    return nil
end

local function SendWarningMessage(message)
    local settings = GetSettings()

    if not settings.enabled then
        return
    end

    if not message or message == "" then
        return
    end

    local outputChannel = GetOutputChannel()
    if not outputChannel then
        return
    end

    SendChatMessage(message, outputChannel)
end

local function CleanupOldEntries(currentTime)
    local settings = GetSettings()
    local playerName = nil
    local playerData = nil

    for playerName, playerData in pairs(feastSpammingPlayers) do
        if (currentTime - playerData.lastSeenTime) > settings.cleanupWindowSeconds then
            feastSpammingPlayers[playerName] = nil
        end
    end
end

local function IsInAnyGroup()
    local isInRaidGroup = false
    local isInPartyGroup = false

    if IsInRaid then
        isInRaidGroup = IsInRaid()
    end

    if IsInGroup then
        isInPartyGroup = IsInGroup()
    elseif GetNumPartyMembers then
        isInPartyGroup = GetNumPartyMembers() > 0
    end

    return isInRaidGroup or isInPartyGroup
end

local function UpdateDetectorRegistration()
    local settings = GetSettings()

    detectorFrame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

    if settings.enabled and IsInAnyGroup() then
        detectorFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        DebugPrint("Registered COMBAT_LOG_EVENT_UNFILTERED")
        return
    end

    DebugPrint("Unregistered COMBAT_LOG_EVENT_UNFILTERED")
end

local function GetOrCreatePlayerData(sourceName, currentTime)
    if not feastSpammingPlayers[sourceName] then
        feastSpammingPlayers[sourceName] = {
            count = 0,
            firstCastTime = currentTime,
            lastCastTime = 0,
            lastSeenTime = currentTime,
            isSpamming = false,
        }
    end

    return feastSpammingPlayers[sourceName]
end

local function BuildSpamMessage(sourceName, count)
    local settings = GetSettings()

    if count >= settings.hardSpamThreshold and settings.enableHarshMessage then
        return sourceName .. " STOP IT YOU DUMB FUCK! x" .. count
    end

    return sourceName .. " is spamming the feast! x" .. count
end

local function IsPlayerMe(sourceName)
    if not sourceName or sourceName == "" then
        return false
    end

    local playerName = UnitName("player")
    if sourceName == playerName then
        return true
    end

    if GetUnitName then
        local playerNameWithRealm = GetUnitName("player", true)
        if sourceName == playerNameWithRealm then
            return true
        end
    end

    return false
end

local function HandleFeastCast(sourceName)
    local settings = GetSettings()

    if not settings.enabled then
        return
    end

    if not sourceName or sourceName == "" then
        return
    end

    if IsPlayerMe(sourceName) then
        DebugPrint("Ignored own feast cast: " .. tostring(sourceName))
        return
    end

    local currentTime = GetTime()

    CleanupOldEntries(currentTime)

    local playerData = GetOrCreatePlayerData(sourceName, currentTime)
    playerData.lastSeenTime = currentTime

    if playerData.isSpamming then
        if (currentTime - playerData.lastCastTime) <= settings.postSpamWindowSeconds then
            playerData.count = playerData.count + 1
        else
            playerData.count = 1
            playerData.firstCastTime = currentTime
            playerData.isSpamming = false
        end
    else
        if (currentTime - playerData.firstCastTime) <= settings.spamWindowSeconds then
            playerData.count = playerData.count + 1
        else
            playerData.count = 1
            playerData.firstCastTime = currentTime
        end

        if playerData.count >= settings.initialSpamThreshold then
            playerData.isSpamming = true
        end
    end

    playerData.lastCastTime = currentTime

    if playerData.isSpamming then
        SendWarningMessage(BuildSpamMessage(sourceName, playerData.count))
    end

    DebugPrint(sourceName .. " count=" .. tostring(playerData.count) .. " isSpamming=" .. tostring(playerData.isSpamming))
end

local function ApplyButtonState(button)
    local settings = GetSettings()

    if not button then
        return
    end

    if settings.enabled then
        button:SetText("|cff00ff00Enabled|r")
    else
        button:SetText("Enable")
    end
end

local function SkinButtonIfPossible(button)
    local skinModule = nil

    if type(TryGetElvUISkinModule) == "function" then
        local _, foundSkinModule = TryGetElvUISkinModule()
        skinModule = foundSkinModule
    elseif addonTable and type(addonTable.TryGetElvUISkinModule) == "function" then
        local _, foundSkinModule = addonTable.TryGetElvUISkinModule()
        skinModule = foundSkinModule
    end

    if skinModule and skinModule.HandleButton then
        skinModule:HandleButton(button)
    end
end

local function SkinCheckBoxIfPossible(checkBox)
    local skinModule = nil

    if type(TryGetElvUISkinModule) == "function" then
        local _, foundSkinModule = TryGetElvUISkinModule()
        skinModule = foundSkinModule
    elseif addonTable and type(addonTable.TryGetElvUISkinModule) == "function" then
        local _, foundSkinModule = addonTable.TryGetElvUISkinModule()
        skinModule = foundSkinModule
    end

    if skinModule and skinModule.HandleCheckBox then
        skinModule:HandleCheckBox(checkBox)
    end
end

local function CreateTitle(parent)
    local titleText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_INSET, -CONTENT_INSET)
    titleText:SetText("|cffffd200" .. TITLE_TEXT .. "|r")

    local fontName = titleText:GetFont()
    titleText:SetFont(fontName, 16, "OUTLINE")

    return titleText
end

local function CreateHarshModeCheckBox(parent, anchorFrame)
    local settings = GetSettings()

    local checkBox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    checkBox:SetSize(CHECKBOX_SIZE, CHECKBOX_SIZE)
    checkBox:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", -2, -12)
    checkBox:SetChecked(settings.enableHarshMessage)
    SkinCheckBoxIfPossible(checkBox)

    local text = checkBox.text or _G[checkBox:GetName() and (checkBox:GetName() .. "Text") or ""]
    if not text then
        text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("LEFT", checkBox, "RIGHT", 4, 0)
        checkBox.text = text
    end

    text:SetText("Enable harsh mode")

    checkBox:SetScript("OnClick", function(self)
        local currentSettings = GetSettings()
        currentSettings.enableHarshMessage = self:GetChecked() and true or false
    end)

    return checkBox
end

local function CreateEnableButton(parent)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    button:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -CONTENT_INSET, CONTENT_INSET)
    SkinButtonIfPossible(button)
    ApplyButtonState(button)

    button:SetScript("OnClick", function(self)
        local settings = GetSettings()
        settings.enabled = not settings.enabled
        ApplyButtonState(self)
        UpdateDetectorRegistration()
    end)

    return button
end

detectorFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        InitializeDB()
        UpdateDetectorRegistration()
        return
    end

    if event == "GROUP_ROSTER_UPDATE" then
        UpdateDetectorRegistration()
        return
    end

    if event ~= "COMBAT_LOG_EVENT_UNFILTERED" then
        return
    end

    local timestamp = nil
    local subEvent = nil
    local sourceGUID = nil
    local sourceName = nil
    local sourceFlags = nil
    local destGUID = nil
    local destName = nil
    local destFlags = nil
    local spellId = nil
    local spellName = nil
    local spellSchool = nil

    timestamp,
    subEvent,
    sourceGUID,
    sourceName,
    sourceFlags,
    destGUID,
    destName,
    destFlags,
    spellId,
    spellName,
    spellSchool = ...

    if subEvent ~= "SPELL_CAST_SUCCESS" then
        return
    end

    if not spellName or not FEAST_SPELL_NAMES[spellName] then
        return
    end

    HandleFeastCast(sourceName)
end)

function addonTable.CreateFishSpammerDetector(parent)
    local containerFrame = CreateFrame("Frame", nil, parent)
    containerFrame:SetAllPoints(parent)

    local titleText = CreateTitle(containerFrame)
    local harshModeCheckBox = CreateHarshModeCheckBox(containerFrame, titleText)
    local enableButton = CreateEnableButton(containerFrame)

    containerFrame.titleText = titleText
    containerFrame.harshModeCheckBox = harshModeCheckBox
    containerFrame.enableButton = enableButton

    return containerFrame
end

InitializeDB()
UpdateDetectorRegistration()
