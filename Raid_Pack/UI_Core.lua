-- UI_Core.lua
local addonName, addonTable = ...

local MAIN_FRAME_NAME = "RTMainFrame"
local MAIN_FRAME_WIDTH = 880
local MAIN_FRAME_HEIGHT = 600
local TAB_SPACING = 130

local STATUS_OVERLAY_NAME = "RTStatusOverlayFrame"

local mainFrame = nil
local tabButtons = {}
local tabFrames = {}
local activeTabIndex = 1
local statusOverlayFrame = nil

local TAB_DEFINITIONS = {
    {
        name = "Spammer",
        creator = CreateSpammerTabContent
    },
    {
        name = "Master Looter",
        creator = CreateMasterLooterTabContent
    }
}

local function EnsureStatusOverlaySavedVariables()
    if not RTStatusOverlaySave then
        RTStatusOverlaySave = {}
    end

    if type(RTStatusOverlaySave) ~= "table" then
        RTStatusOverlaySave = {}
    end

    if RTStatusOverlaySave.point == nil then
        RTStatusOverlaySave.point = "CENTER"
    end

    if RTStatusOverlaySave.relativePoint == nil then
        RTStatusOverlaySave.relativePoint = "CENTER"
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

local function ShowTab(index)
    activeTabIndex = index

    for i = 1, #tabFrames do
        local frame = tabFrames[i]
        if frame then
            if i == index then
                frame:Show()
            else
                frame:Hide()
            end
        end
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
    local content = CreateFrame("Frame", nil, parent)
    content:SetPoint("TOPLEFT", 12, -72)
    content:SetPoint("BOTTOMRIGHT", -12, 12)
    return content
end

local function CreateTabFrames(content, onClose)
    for i = 1, #TAB_DEFINITIONS do
        local tabDefinition = TAB_DEFINITIONS[i]
        local frame = nil

        if type(tabDefinition.creator) == "function" then
            frame = tabDefinition.creator(content, onClose)
        else
            frame = CreateFrame("Frame", nil, content)
            frame:SetAllPoints(content)
        end

        frame:Hide()
        tabFrames[i] = frame
    end
end

local function ApplySkin()
    if not SkinMainFrameWithElvUIIfAvailable then
        return
    end

    SkinMainFrameWithElvUIIfAvailable(mainFrame, mainFrame._closeX, tabButtons[1], tabButtons[2])
end

local function CreateMainFrameIfNeeded()
    if mainFrame then
        return
    end

    mainFrame = CreateFrame("Frame", MAIN_FRAME_NAME, UIParent, "UIPanelDialogTemplate")
    mainFrame:SetSize(MAIN_FRAME_WIDTH, MAIN_FRAME_HEIGHT)
    mainFrame:SetPoint("CENTER", 0, 0)
    mainFrame:Hide()
    mainFrame:SetFrameStrata("DIALOG")
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetClampedToScreen(true)

    mainFrame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)

    mainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)

    tinsert(UISpecialFrames, MAIN_FRAME_NAME)

    local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Raid Tools")

    CreateTabButtons(mainFrame)

    local content = CreateContentFrame(mainFrame)

    CreateTabFrames(content, function()
        mainFrame:Hide()
    end)

    ApplySkin()
    ShowTab(activeTabIndex)
end

function ToggleMainUI()
    CreateMainFrameIfNeeded()

    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show()
    end
end

local function SaveStatusOverlayPosition()
    if not statusOverlayFrame then
        return
    end

    EnsureStatusOverlaySavedVariables()

    local point, _, relativePoint, xOfs, yOfs = statusOverlayFrame:GetPoint(1)

    RTStatusOverlaySave.point = point or "CENTER"
    RTStatusOverlaySave.relativePoint = relativePoint or "CENTER"
    RTStatusOverlaySave.x = xOfs or 0
    RTStatusOverlaySave.y = yOfs or 0
end

local function GetStatusText(isEnabled, label)
    if isEnabled then
        return "|cffffffff" .. label .. ": |r|cff00ff00ON|r"
    end

    return "|cffffffff" .. label .. ": |r|cffff3b30OFF|r"
end

function RefreshStatusOverlay()
    if not statusOverlayFrame then
        return
    end

    local spammerEnabled = false
    local masterLooterEnabled = false

    if RT_IsSpammerEnabled then
        spammerEnabled = RT_IsSpammerEnabled() and true or false
    end

    if RT_IsMasterLooterEnabled then
        masterLooterEnabled = RT_IsMasterLooterEnabled() and true or false
    end

    if statusOverlayFrame.spammerText then
        statusOverlayFrame.spammerText:SetText(GetStatusText(spammerEnabled, "Spammer"))
    end

    if statusOverlayFrame.masterLooterText then
        statusOverlayFrame.masterLooterText:SetText(GetStatusText(masterLooterEnabled, "MLooter"))
    end
end

local function CreateStatusOverlayIfNeeded()
    if statusOverlayFrame then
        return
    end

    EnsureStatusOverlaySavedVariables()

    statusOverlayFrame = CreateFrame("Button", STATUS_OVERLAY_NAME, UIParent)
    statusOverlayFrame:SetSize(180, 42)
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

    statusOverlayFrame.spammerText = statusOverlayFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    statusOverlayFrame.spammerText:SetPoint("TOPLEFT", statusOverlayFrame, "TOPLEFT", 0, 0)
    statusOverlayFrame.spammerText:SetJustifyH("LEFT")
    statusOverlayFrame.spammerText:SetWidth(180)
    statusOverlayFrame.spammerText:SetText("Spammer: |cff00ff00ON|r")

    statusOverlayFrame.masterLooterText = statusOverlayFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    statusOverlayFrame.masterLooterText:SetPoint("TOPLEFT", statusOverlayFrame.spammerText, "BOTTOMLEFT", 0, -4)
    statusOverlayFrame.masterLooterText:SetJustifyH("LEFT")
    statusOverlayFrame.masterLooterText:SetWidth(180)
    statusOverlayFrame.masterLooterText:SetText("MLooter: |cffff3b30OFF|r")

    statusOverlayFrame:SetScript("OnUpdate", function()
        RefreshStatusOverlay()
    end)

    if RTStatusOverlaySave.enabled then
        statusOverlayFrame:Show()
    else
        statusOverlayFrame:Hide()
    end
end

function ToggleStatusOverlayVisibility()
    EnsureStatusOverlaySavedVariables()
    CreateStatusOverlayIfNeeded()

    RTStatusOverlaySave.enabled = not RTStatusOverlaySave.enabled

    if RTStatusOverlaySave.enabled then
        statusOverlayFrame:Show()
    else
        statusOverlayFrame:Hide()
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    EnsureStatusOverlaySavedVariables()
    CreateMainFrameIfNeeded()
    CreateStatusOverlayIfNeeded()

    if CreateMinimapButtonIfNeeded then
        CreateMinimapButtonIfNeeded()
    end
end)