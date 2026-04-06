-- Minimap_Settings.lua
local addonName, addonTable = ...

local BUTTON_ICON = "Interface\\Icons\\INV_Scroll_04"
local LDB_OBJECT_NAME = "RaidTools"
local minimapDataObject = nil
local minimapIconLibrary = nil

local function EnsureMinimapSettings()
    if not RTRollManagerSave then
        RTRollManagerSave = {}
    end

    if not RTRollManagerSave.minimap then
        RTRollManagerSave.minimap = {}
    end

    if RTRollManagerSave.minimap.hide == nil then
        RTRollManagerSave.minimap.hide = false
    end

    if RTRollManagerSave.minimap.minimapPos == nil then
        RTRollManagerSave.minimap.minimapPos = 220
    end
end

local function OnMinimapClick(frame, button)
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

local function OnMinimapTooltipShow(tooltip)
    tooltip:AddLine("Raid Tools", 1, 0.82, 0)
    tooltip:AddLine("by HirohitoW", 0.7, 0.7, 0.7)
    tooltip:AddLine(" ")
    tooltip:AddLine("Left Click:", 0, 1, 0)
    tooltip:AddLine("  Open / Close Addon UI", 1, 1, 1)
    tooltip:AddLine("Right Click:", 0, 1, 0)
    tooltip:AddLine("  Toggle Status Overlay", 1, 1, 1)
end

local function CreateMinimapDataObject()
    local ldbLibrary = LibStub("LibDataBroker-1.1")

    minimapDataObject = ldbLibrary:NewDataObject(LDB_OBJECT_NAME, {
        type = "data source",
        text = "Raid Tools",
        icon = BUTTON_ICON,
        OnClick = OnMinimapClick,
        OnTooltipShow = OnMinimapTooltipShow,
    })
end

local function RegisterMinimapIcon()
    minimapIconLibrary = LibStub("LibDBIcon-1.0")
    minimapIconLibrary:Register(LDB_OBJECT_NAME, minimapDataObject, RTRollManagerSave.minimap)
end

function CreateMinimapButtonIfNeeded()
    if minimapDataObject then
        return
    end

    EnsureMinimapSettings()
    CreateMinimapDataObject()
    RegisterMinimapIcon()
end

function ShowMinimapButton()
    EnsureMinimapSettings()

    if not minimapDataObject then
        CreateMinimapButtonIfNeeded()
        return
    end

    RTRollManagerSave.minimap.hide = false
    minimapIconLibrary:Show(LDB_OBJECT_NAME)
    minimapIconLibrary:Refresh(LDB_OBJECT_NAME, RTRollManagerSave.minimap)
end

function HideMinimapButton()
    EnsureMinimapSettings()

    if not minimapDataObject then
        CreateMinimapButtonIfNeeded()
    end

    RTRollManagerSave.minimap.hide = true
    minimapIconLibrary:Hide(LDB_OBJECT_NAME)
end

function ToggleMinimapButton()
    EnsureMinimapSettings()

    if RTRollManagerSave.minimap.hide then
        ShowMinimapButton()
        return
    end

    HideMinimapButton()
end