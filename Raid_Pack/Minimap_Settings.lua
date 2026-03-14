-- Minimap_Settings.lua
local addonName, addonTable = ...

local MINIMAP_BUTTON_NAME = "RaidToolsMinimapButton"
local MAIN_FRAME_NAME = "RTMainFrame"
local BUTTON_SIZE = 16
local BUTTON_ICON = "Interface\\Icons\\Spell_Holy_ChampionsBond"
local BUTTON_BORDER = "Interface\\Minimap\\MiniMap-TrackingBorder"

local minimapButton = nil

local function OnMinimapButtonDragStart(self)
    self:StartMoving()
end

local function OnMinimapButtonDragStop(self)
    self:StopMovingOrSizing()
end

local function OnMinimapButtonClick(self, button)
    if button == "LeftButton" then
        if ToggleMainUI then
            ToggleMainUI()
        end
        return
    end

    if button == "RightButton" then
        if ToggleStatusOverlayVisibility then
            ToggleStatusOverlayVisibility()
        end
    end
end

local function OnMinimapButtonEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Raid Tools", 1, 0.82, 0)
    GameTooltip:AddLine("by HirohitoW", 0.7, 0.7, 0.7)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left Click:", 0, 1, 0)
    GameTooltip:AddLine("  Open / Close Addon UI", 1, 1, 1)
    GameTooltip:AddLine("Right Click:", 0, 1, 0)
    GameTooltip:AddLine("  Toggle Status Overlay", 1, 1, 1)
    GameTooltip:Show()
end

local function OnMinimapButtonLeave()
    GameTooltip:Hide()
end

local function CreateMinimapButtonTextures(button)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexture(BUTTON_ICON)

    button.border = button:CreateTexture(nil, "OVERLAY")
    button.border:SetAllPoints()
    button.border:SetTexture(BUTTON_BORDER)
end

local function SetupMinimapButtonBehavior(button)
    button:SetMovable(true)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    button:SetScript("OnDragStart", OnMinimapButtonDragStart)
    button:SetScript("OnDragStop", OnMinimapButtonDragStop)
    button:SetScript("OnClick", OnMinimapButtonClick)
    button:SetScript("OnEnter", OnMinimapButtonEnter)
    button:SetScript("OnLeave", OnMinimapButtonLeave)
end

function CreateMinimapButtonIfNeeded()
    if minimapButton then
        return
    end

    minimapButton = CreateFrame("Button", MINIMAP_BUTTON_NAME, Minimap)
    minimapButton:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetFrameLevel(8)
    minimapButton:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -2, -2)

    CreateMinimapButtonTextures(minimapButton)
    SetupMinimapButtonBehavior(minimapButton)
end