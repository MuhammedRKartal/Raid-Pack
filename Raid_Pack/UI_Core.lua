-- UI_Core.lua
local addonName, addonTable = ...

local MAIN_FRAME_NAME = "RTMainFrame"
local MAIN_FRAME_WIDTH = 880
local MAIN_FRAME_HEIGHT = 600
local TAB_SPACING = 95

local STATUS_OVERLAY_NAME = "RTStatusOverlayFrame"
local STATUS_OVERLAY_WIDTH = 180
local STATUS_OVERLAY_HEIGHT = 60

local STATUS_ON_TEXT = "|cff00ff00ON|r"
local STATUS_OFF_TEXT = "|cffff3b30OFF|r"
local DEFAULT_POINT = "CENTER"

local mainFrame = nil
local statusOverlayFrame = nil
local tabButtons = {}
local tabFrames = {}
local activeTabIndex = 1

local TAB_DEFINITIONS = {
    {
        name = "Spammer",
        creator = CreateSpammerTabContent
    },
    {
        name = "Auto Reply",
        creator = CreateAutoResponseTabContent
    },
    {
        name = "Master Looter",
        creator = addonTable.CreateMasterLooterTabContent
    },
    {
        name = "Roll Manager",
        creator = CreateRollManagerTabContent
    },
    {
        name = "Extra Tools",
        creator = addonTable.CreateExtraToolsContent
    }
}

local function EnsureStatusOverlaySavedVariables()
    if type(RTStatusOverlaySave) ~= "table" then
        RTStatusOverlaySave = {}
    end

    if RTStatusOverlaySave.point == nil then
        RTStatusOverlaySave.point = DEFAULT_POINT
    end

    if RTStatusOverlaySave.relativePoint == nil then
        RTStatusOverlaySave.relativePoint = DEFAULT_POINT
    end

    if RTStatusOverlaySave.x == nil then
        RTStatusOverlaySave.x = 0
    end

    if RTStatusOverlaySave.y == nil then
        RTStatusOverlaySave.y = 0
    end

    if RTStatusOverlaySave.enabled == nil then
        RTStatusOverlaySave.enabled = true
    end
end

local function GetPlayerRaidRank()
    if not IsInRaid() then
        return nil
    end

    local playerName = UnitName("player")

    for i = 1, GetNumGroupMembers() do
        local raidMemberName, raidRank = GetRaidRosterInfo(i)
        if raidMemberName == playerName then
            return raidRank
        end
    end

    return nil
end

function IsPlayerLeaderOrAssist()
    local raidRank = GetPlayerRaidRank()

    if raidRank == nil then
        return false
    end

    return raidRank > 0
end

function GetRaidChatType()
    if IsPlayerLeaderOrAssist() then
        return "RAID_WARNING"
    end

    return "RAID"
end

local function SetFrameShown(frame, shouldShow)
    if not frame then
        return
    end

    if shouldShow then
        frame:Show()
    else
        frame:Hide()
    end
end

local function ShowTab(index)
    activeTabIndex = index

    for i = 1, #tabFrames do
        local frame = tabFrames[i]
        SetFrameShown(frame, i == index)
    end

    for i = 1, #tabButtons do
        local button = tabButtons[i]
        if button and button.SetChecked then
            button:SetChecked(i == index)
        end
    end
end

local function CreateTabButtons(parent)
    for i = 1, #TAB_DEFINITIONS do
        local tabDefinition = TAB_DEFINITIONS[i]
        local button = CreateFrame("CheckButton", "RTMainTabBtn" .. i, parent, "UICheckButtonTemplate")

        if i == 1 then
            button:SetPoint("TOPLEFT", 18, -40)
        else
            button:SetPoint("LEFT", tabButtons[i - 1], "RIGHT", TAB_SPACING, 0)
        end

        local buttonText = _G[button:GetName() .. "Text"]
        if buttonText then
            buttonText:SetText(tabDefinition.name)
        end

        button:SetScript("OnClick", function()
            ShowTab(i)
        end)

        tabButtons[i] = button
    end
end

local function CreateContentFrame(parent)
    local contentFrame = CreateFrame("Frame", nil, parent)
    contentFrame:SetPoint("TOPLEFT", 12, -72)
    contentFrame:SetPoint("BOTTOMRIGHT", -12, 12)
    return contentFrame
end

local function CreateTabFrames(contentFrame, onClose)
    for i = 1, #TAB_DEFINITIONS do
        local tabDefinition = TAB_DEFINITIONS[i]
        local frame = nil

        if type(tabDefinition.creator) == "function" then
            frame = tabDefinition.creator(contentFrame, onClose)
        else
            frame = CreateFrame("Frame", nil, contentFrame)
            frame:SetAllPoints(contentFrame)
        end

        frame:Hide()
        tabFrames[i] = frame
    end
end

local function ApplySkin()
    if not SkinMainFrameWithElvUIIfAvailable then
        return
    end

    SkinMainFrameWithElvUIIfAvailable(mainFrame, mainFrame._closeX, unpack(tabButtons))
end

local function CreateMainFrameIfNeeded()
    if mainFrame then
        return
    end

    mainFrame = CreateFrame("Frame", MAIN_FRAME_NAME, UIParent, "UIPanelDialogTemplate")
    mainFrame:SetSize(MAIN_FRAME_WIDTH, MAIN_FRAME_HEIGHT)
    mainFrame:SetPoint("CENTER", 0, 0)
    mainFrame:SetFrameStrata("DIALOG")
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetClampedToScreen(true)
    mainFrame:Hide()

    mainFrame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)

    mainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)

    tinsert(UISpecialFrames, MAIN_FRAME_NAME)

    local titleText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    titleText:SetPoint("TOP", 0, -12)
    titleText:SetText("Tools")

    CreateTabButtons(mainFrame)

    local contentFrame = CreateContentFrame(mainFrame)

    CreateTabFrames(contentFrame, function()
        mainFrame:Hide()
    end)

    ApplySkin()
    ShowTab(activeTabIndex)
end

function ToggleMainUI()
    CreateMainFrameIfNeeded()
    SetFrameShown(mainFrame, not mainFrame:IsShown())
end

local function SaveStatusOverlayPosition()
    if not statusOverlayFrame then
        return
    end

    EnsureStatusOverlaySavedVariables()

    local point, _, relativePoint, xOfs, yOfs = statusOverlayFrame:GetPoint(1)

    RTStatusOverlaySave.point = point or DEFAULT_POINT
    RTStatusOverlaySave.relativePoint = relativePoint or DEFAULT_POINT
    RTStatusOverlaySave.x = xOfs or 0
    RTStatusOverlaySave.y = yOfs or 0
end

local function GetModuleStatusLabel(label, isEnabled)
    local statusText = STATUS_OFF_TEXT

    if isEnabled then
        statusText = STATUS_ON_TEXT
    end

    return "|cffffffff" .. label .. ": |r" .. statusText
end

local function IsSpammerEnabled()
    if not RT_IsSpammerEnabled then
        return false
    end

    return RT_IsSpammerEnabled() and true or false
end

local function IsMasterLooterEnabled()
    if not RT_IsMasterLooterEnabled then
        return false
    end

    return RT_IsMasterLooterEnabled() and true or false
end

local function IsAutoReplyEnabled()
    if not RT_IsAutoResponseEnabled then
        return false
    end

    return RT_IsAutoResponseEnabled() and true or false
end

function RefreshStatusOverlay()
    if not statusOverlayFrame then
        return
    end

    if statusOverlayFrame.spammerText then
        statusOverlayFrame.spammerText:SetText(GetModuleStatusLabel("Spammer", IsSpammerEnabled()))
    end

    if statusOverlayFrame.masterLooterText then
        statusOverlayFrame.masterLooterText:SetText(GetModuleStatusLabel("MLooter", IsMasterLooterEnabled()))
    end

    if statusOverlayFrame.autoReplyText then
        statusOverlayFrame.autoReplyText:SetText(GetModuleStatusLabel("AutoReply", IsAutoReplyEnabled()))
    end
end

local function CreateStatusText(parent, anchorTarget, offsetY, defaultText)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    text:SetPoint("TOPLEFT", anchorTarget, "TOPLEFT", 0, offsetY)
    text:SetJustifyH("LEFT")
    text:SetWidth(STATUS_OVERLAY_WIDTH)
    text:SetText(defaultText)
    return text
end

local function CreateStatusOverlayIfNeeded()
    if statusOverlayFrame then
        return
    end

    EnsureStatusOverlaySavedVariables()

    statusOverlayFrame = CreateFrame("Button", STATUS_OVERLAY_NAME, UIParent)
    statusOverlayFrame:SetSize(STATUS_OVERLAY_WIDTH, STATUS_OVERLAY_HEIGHT)
    statusOverlayFrame:SetFrameStrata("HIGH")
    statusOverlayFrame:SetMovable(true)
    statusOverlayFrame:EnableMouse(true)
    statusOverlayFrame:RegisterForClicks("RightButtonUp")
    statusOverlayFrame:RegisterForDrag("LeftButton")
    statusOverlayFrame:SetClampedToScreen(true)

    statusOverlayFrame:SetPoint(
        RTStatusOverlaySave.point,
        UIParent,
        RTStatusOverlaySave.relativePoint,
        RTStatusOverlaySave.x,
        RTStatusOverlaySave.y
    )

    statusOverlayFrame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)

    statusOverlayFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveStatusOverlayPosition()
    end)

    statusOverlayFrame:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            ToggleMainUI()
        end
    end)

    statusOverlayFrame.spammerText = CreateStatusText(
        statusOverlayFrame,
        statusOverlayFrame,
        0,
        GetModuleStatusLabel("Spammer", false)
    )

    statusOverlayFrame.masterLooterText = CreateStatusText(
        statusOverlayFrame,
        statusOverlayFrame.spammerText,
        -18,
        GetModuleStatusLabel("MLooter", false)
    )

    statusOverlayFrame.autoReplyText = CreateStatusText(
        statusOverlayFrame,
        statusOverlayFrame.masterLooterText,
        -18,
        GetModuleStatusLabel("AutoReply", false)
    )

    RefreshStatusOverlay()
    SetFrameShown(statusOverlayFrame, RTStatusOverlaySave.enabled)
end

function ToggleStatusOverlayVisibility()
    EnsureStatusOverlaySavedVariables()
    CreateStatusOverlayIfNeeded()

    RTStatusOverlaySave.enabled = not RTStatusOverlaySave.enabled
    SetFrameShown(statusOverlayFrame, RTStatusOverlaySave.enabled)
end

local function OnPlayerLogin()
    EnsureStatusOverlaySavedVariables()
    CreateMainFrameIfNeeded()
    CreateStatusOverlayIfNeeded()

    if CreateMinimapButtonIfNeeded then
        CreateMinimapButtonIfNeeded()
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    OnPlayerLogin()
end)