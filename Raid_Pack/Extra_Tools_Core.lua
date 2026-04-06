local addonName, addonTable = ...

local PANEL_INSET = 0
local PANEL_GAP = 10
local DIVIDER_WIDTH = 1
local RIGHT_PANEL_GAP = 10
local RIGHT_TOP_PANEL_HEIGHT = 260
local CONTENT_INSET = 6

local function ApplyPanelStyle(frame)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)
    frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
end

local function CreatePanel(parent)
    local panelFrame = CreateFrame("Frame", nil, parent)
    ApplyPanelStyle(panelFrame)
    return panelFrame
end

local function AttachContent(contentFrame, hostFrame)
    if not contentFrame or not hostFrame then
        return
    end

    contentFrame:SetParent(hostFrame)
    contentFrame:ClearAllPoints()
    contentFrame:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", CONTENT_INSET, -CONTENT_INSET)
    contentFrame:SetPoint("BOTTOMRIGHT", hostFrame, "BOTTOMRIGHT", -CONTENT_INSET, CONTENT_INSET)
    contentFrame:Show()
end

local function CreateFallbackFrame(parent, textValue)
    local fallbackFrame = CreateFrame("Frame", nil, parent)
    fallbackFrame:SetAllPoints(parent)

    local messageText = fallbackFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    messageText:SetPoint("CENTER")
    messageText:SetText(textValue)

    return fallbackFrame
end

local function CreatePaladinBuffsContentCompat(parent, onClose)
    if type(addonTable.CreatePaladinBuffsContent) == "function" then
        return addonTable.CreatePaladinBuffsContent(parent, onClose)
    end

    if type(CreatePaladinBuffsTabContent) == "function" then
        return CreatePaladinBuffsTabContent(parent, onClose)
    end

    return CreateFallbackFrame(parent, "Paladin_Buffs.lua yüklenemedi.")
end

local function CreateAssignmentsContentCompat(parent, onClose)
    if type(addonTable.CreateToCAssignmentsTabContent) == "function" then
        return addonTable.CreateToCAssignmentsTabContent(parent, onClose)
    end

    if type(CreateToCAssignmentsTabContent) == "function" then
        return CreateToCAssignmentsTabContent(parent, onClose)
    end

    return CreateFallbackFrame(parent, "Assignments.lua yüklenemedi.")
end

local function CreateFishSpammerDetectorCompat(parent, onClose)
    if type(addonTable.CreateFishSpammerDetector) == "function" then
        return addonTable.CreateFishSpammerDetector(parent, onClose)
    end

    if type(CreateFishSpammerDetector) == "function" then
        return CreateFishSpammerDetector(parent, onClose)
    end

    return CreateFallbackFrame(parent, "Fish Spammer Detector içeriği henüz bağlı değil.")
end

local function CreateVerticalDivider(parent)
    local dividerTexture = parent:CreateTexture(nil, "ARTWORK")
    dividerTexture:SetTexture(1, 1, 1, 0.14)
    dividerTexture:SetWidth(DIVIDER_WIDTH)
    dividerTexture:SetPoint("TOP", parent, "TOP", 0, -PANEL_INSET)
    dividerTexture:SetPoint("BOTTOM", parent, "BOTTOM", 0, PANEL_INSET)
    return dividerTexture
end

local function CreateLeftPanel(rootFrame, dividerTexture)
    local leftPanelFrame = CreatePanel(rootFrame)
    leftPanelFrame:SetPoint("TOPLEFT", rootFrame, "TOPLEFT", PANEL_INSET, -PANEL_INSET)
    leftPanelFrame:SetPoint("BOTTOMLEFT", rootFrame, "BOTTOMLEFT", PANEL_INSET, PANEL_INSET)
    leftPanelFrame:SetPoint("RIGHT", dividerTexture, "LEFT", -(PANEL_GAP / 2), 0)
    return leftPanelFrame
end

local function CreateRightTopPanel(rootFrame, dividerTexture)
    local rightTopPanelFrame = CreatePanel(rootFrame)
    rightTopPanelFrame:SetPoint("TOPLEFT", dividerTexture, "TOPRIGHT", PANEL_GAP / 2, -PANEL_INSET)
    rightTopPanelFrame:SetPoint("TOPRIGHT", rootFrame, "TOPRIGHT", -PANEL_INSET, -PANEL_INSET)
    rightTopPanelFrame:SetHeight(RIGHT_TOP_PANEL_HEIGHT)
    return rightTopPanelFrame
end

local function CreateRightBottomPanel(rootFrame, dividerTexture, rightTopPanelFrame)
    local rightBottomPanelFrame = CreatePanel(rootFrame)
    rightBottomPanelFrame:SetPoint("TOPLEFT", rightTopPanelFrame, "BOTTOMLEFT", 0, -RIGHT_PANEL_GAP)
    rightBottomPanelFrame:SetPoint("TOPRIGHT", rightTopPanelFrame, "BOTTOMRIGHT", 0, -RIGHT_PANEL_GAP)
    rightBottomPanelFrame:SetPoint("BOTTOMLEFT", dividerTexture, "BOTTOMRIGHT", PANEL_GAP / 2, PANEL_INSET)
    rightBottomPanelFrame:SetPoint("BOTTOMRIGHT", rootFrame, "BOTTOMRIGHT", -PANEL_INSET, PANEL_INSET)
    return rightBottomPanelFrame
end

function addonTable.CreateExtraToolsContent(parent, onClose)
    local rootFrame = CreateFrame("Frame", nil, parent)
    rootFrame:SetAllPoints(parent)

    local dividerTexture = CreateVerticalDivider(rootFrame)

    local leftPanelFrame = CreateLeftPanel(rootFrame, dividerTexture)
    local rightTopPanelFrame = CreateRightTopPanel(rootFrame, dividerTexture)
    local rightBottomPanelFrame = CreateRightBottomPanel(rootFrame, dividerTexture, rightTopPanelFrame)

    local paladinBuffsContentFrame = CreatePaladinBuffsContentCompat(leftPanelFrame, onClose)
    local assignmentsContentFrame = CreateAssignmentsContentCompat(rightTopPanelFrame, onClose)
    local bottomRightContentFrame = CreateFishSpammerDetectorCompat(rightBottomPanelFrame, onClose)

    AttachContent(paladinBuffsContentFrame, leftPanelFrame)
    AttachContent(assignmentsContentFrame, rightTopPanelFrame)
    AttachContent(bottomRightContentFrame, rightBottomPanelFrame)

    rootFrame.leftPanelFrame = leftPanelFrame
    rootFrame.rightTopPanelFrame = rightTopPanelFrame
    rootFrame.rightBottomPanelFrame = rightBottomPanelFrame

    rootFrame.paladinBuffsContentFrame = paladinBuffsContentFrame
    rootFrame.assignmentsContentFrame = assignmentsContentFrame
    rootFrame.bottomRightContentFrame = bottomRightContentFrame

    return rootFrame
end
