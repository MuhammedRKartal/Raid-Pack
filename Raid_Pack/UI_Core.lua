-- UI_Core.lua
local addonName, addonTable = ...

local MAIN_FRAME_NAME = "RTMainFrame"
local MAIN_FRAME_WIDTH = 880
local MAIN_FRAME_HEIGHT = 600
local TAB_SPACING = 130

local mainFrame = nil
local tabButtons = {}
local tabFrames = {}
local activeTabIndex = 1

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

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    if CreateMinimapButtonIfNeeded then
        CreateMinimapButtonIfNeeded()
    end
end)