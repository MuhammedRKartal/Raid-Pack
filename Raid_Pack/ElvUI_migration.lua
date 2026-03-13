-- ElvUI_migration.lua (PATCH: skin dropdowns + editboxes)

local addonName, addonTable = ...

local _G = _G
local unpack = unpack
local pcall = pcall

function TryGetElvUISkinModule()
    if not _G.ElvUI then
        return nil, nil
    end

    local ok, e = pcall(unpack, _G.ElvUI)
    if not ok or not e or not e.GetModule then
        return nil, nil
    end

    local okSkin, skinModule = pcall(e.GetModule, e, "Skins")
    if not okSkin then
        return e, nil
    end

    return e, skinModule
end

local function HandleCheckBoxIfPossible(s, checkBox)
    if checkBox and s.HandleCheckBox then
        s:HandleCheckBox(checkBox)
    end
end

local function HandleButtonIfPossible(s, button)
    if button and s.HandleButton then
        s:HandleButton(button)
    end
end

local function GetScrollBarFromScrollFrame(scrollFrame)
    if not scrollFrame then
        return nil
    end

    if scrollFrame.ScrollBar then
        return scrollFrame.ScrollBar
    end

    if scrollFrame.GetName then
        local scrollFrameName = scrollFrame:GetName()
        if scrollFrameName then
            return _G[scrollFrameName .. "ScrollBar"]
        end
    end

    return nil
end

function SkinMainFrameWithElvUIIfAvailable(mainFrame, closeX, tab1Button, tab2Button)
    local e, s = TryGetElvUISkinModule()
    if not e or not s or not mainFrame then
        return false
    end

    if mainFrame.StripTextures then
        mainFrame:StripTextures()
    end

    if mainFrame.SetTemplate then
        mainFrame:SetTemplate("Transparent", nil, true)
    end

    if closeX and s.HandleCloseButton then
        s:HandleCloseButton(closeX, mainFrame)
    end

    HandleCheckBoxIfPossible(s, tab1Button)
    HandleCheckBoxIfPossible(s, tab2Button)

    return true
end

function SkinAssignmentsControlsWithElvUIIfAvailable(sendButton, closeButton, checkWhisper, checkRaid, previewScroll)
    local e, s = TryGetElvUISkinModule()
    if not e or not s then
        return false
    end

    HandleButtonIfPossible(s, sendButton)
    HandleButtonIfPossible(s, closeButton)
    HandleCheckBoxIfPossible(s, checkWhisper)
    HandleCheckBoxIfPossible(s, checkRaid)

    local scrollBar = GetScrollBarFromScrollFrame(previewScroll)
    if scrollBar and s.HandleScrollBar then
        s:HandleScrollBar(scrollBar)
    end

    return true
end

local function SkinEditBoxIfPossible(s, editBox)
    if not s or not editBox then
        return
    end

    if s.HandleEditBox then
        s:HandleEditBox(editBox)
        return
    end

    if editBox.SetTemplate then
        editBox:SetTemplate("Transparent")
    end
end

local function SkinDropDownIfPossible(s, dd)
    if not s or not dd then
        return
    end

    if s.HandleDropDownBox then
        s:HandleDropDownBox(dd)
        return
    end

    if not dd.GetName then
        return
    end

    local dropDownName = dd:GetName()
    if not dropDownName then
        return
    end

    local left = _G[dropDownName .. "Left"]
    local middle = _G[dropDownName .. "Middle"]
    local right = _G[dropDownName .. "Right"]

    if left and left.Hide then
        left:Hide()
    end

    if middle and middle.Hide then
        middle:Hide()
    end

    if right and right.Hide then
        right:Hide()
    end
end