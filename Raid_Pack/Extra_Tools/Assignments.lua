local addonName, addonTable = ...

local DEFAULTS = {
    raidDelaySeconds = 0.70,
    tankHealthThreshold = 38000,
    whisperPrefix = "TocTools: ",
    debugModeEnabled = false
}

local AUTO_REFRESH_DELAY_SECONDS = 0.15

local CLASS_ORDER = {
    "ROGUE",
    "WARLOCK",
    "PRIEST",
    "WARRIOR",
    "DRUID",
    "DEATHKNIGHT",
    "PALADIN",
    "HUNTER"
}

local ASSIGNMENT_MESSAGES = {
    cc = {
        "CC the Holy Paladin. If Paladin is Ret, CC the Priest.",
        "CC the Priest. If Priest is Shadow, CC the Resto Shaman. If Shaman is Enh, CC the Warlock.",
        "CC the Resto Shaman. If Paladin is Ret and Shaman is Enh, CC the Warlock."
    },
    warlock = "Banish and Fear the enemy Resto Druid.",
    priest = "Spam Mass Dispel. Push in and use Fear mid fight.",
    warrior = "Keep Sunder Armor on the target. Disarm enemy Warrior during Bladestorm.",
    druid = "Watch healer mana. Use Innervate when needed. If free, Cyclone Hunter or Mage.",
    paladin = "If not healing or tanking, stun the main target.",
    hunter = "Keep Frost Trap down at all times.",
    tankMain = "Main Tank: taunt the Warrior and pull him away. Use Chain of Ice.",
    tankOff = "Off Tank: taunt the Death Knight and pull him away."
}

local RAID_LINES = {
    "Enha/Ele Shamans and Priests do purge on our target!",
    "Death Knights use Chain of Ice on our target, and use Army at Start!",
    "Healers stay back in the beginning!",
    "Heroism at start! Everyone Single Target the Mark! DON'T AOE"
}

local UI = {
    tabFrame = nil,
    titleText = nil,
    summaryContainerFrame = nil,
    summaryScrollFrame = nil,
    summaryScrollBar = nil,
    summaryContentFrame = nil,
    summaryText = nil,
    statusText = nil,
    specificAnnouncementsButton = nil,
    raidAnnouncementsButton = nil,
    debugText = nil
}

local STATE = {
    isSending = false,
    currentAssignments = nil,
    raidQueue = {},
    raidQueueElapsed = 0,
    autoRefreshPending = false,
    autoRefreshDelayRemaining = 0
}

local delayFrame = CreateFrame("Frame")
local rosterEventFrame = CreateFrame("Frame")
local autoRefreshFrame = CreateFrame("Frame")

local function TableContains(list, value)
    if not list then
        return false
    end

    for i = 1, #list do
        if list[i] == value then
            return true
        end
    end

    return false
end

local function CopyList(list)
    local out = {}

    if not list then
        return out
    end

    for i = 1, #list do
        out[i] = list[i]
    end

    return out
end

local function RemoveFromSpecialFrames(frame)
    if not frame or not frame.GetName then
        return
    end

    local frameName = frame:GetName()

    if not frameName or not UISpecialFrames then
        return
    end

    for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == frameName then
            table.remove(UISpecialFrames, i)
        end
    end
end

local function AddToSpecialFrames(frame)
    if not frame or not frame.GetName then
        return
    end

    local frameName = frame:GetName()

    if not frameName or not UISpecialFrames then
        return
    end

    if not TableContains(UISpecialFrames, frameName) then
        table.insert(UISpecialFrames, frameName)
    end
end

local function GetRaidMemberCountSafe()
    if DEFAULTS.debugModeEnabled then
        return 10
    end

    if GetNumRaidMembers then
        return GetNumRaidMembers()
    end

    return 0
end

local function IsPlayerInRaidGroup()
    if DEFAULTS.debugModeEnabled then
        return true
    end

    return GetRaidMemberCountSafe() > 0
end

local function GetClassColorHex(classFile)
    if not classFile then
        return "ffffffff"
    end

    local colorTable = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]

    if not colorTable then
        return "ffffffff"
    end

    local r = math.floor(((colorTable.r or 1) * 255) + 0.5)
    local g = math.floor(((colorTable.g or 1) * 255) + 0.5)
    local b = math.floor(((colorTable.b or 1) * 255) + 0.5)

    return string.format("ff%02x%02x%02x", r, g, b)
end

local function WrapNameWithClassColor(playerName, classFile)
    return "|c" .. GetClassColorHex(classFile) .. (playerName or "Unknown") .. "|r"
end

local function CompareHealthAscNameAsc(a, b)
    local aHealth = (a and a.healthMax) or 0
    local bHealth = (b and b.healthMax) or 0

    if aHealth ~= bHealth then
        return aHealth < bHealth
    end

    local aName = (a and a.name) or ""
    local bName = (b and b.name) or ""

    return aName < bName
end

local function CompareHealthDescNameAsc(a, b)
    local aHealth = (a and a.healthMax) or 0
    local bHealth = (b and b.healthMax) or 0

    if aHealth ~= bHealth then
        return aHealth > bHealth
    end

    local aName = (a and a.name) or ""
    local bName = (b and b.name) or ""

    return aName < bName
end

local function SendPrefixedWhisper(playerName, message)
    if not playerName or not message then
        return
    end

    if DEFAULTS.debugModeEnabled then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cff00ff00[DEBUG Whisper]|r -> " .. playerName .. ": " .. DEFAULTS.whisperPrefix .. message
        )
        return
    end

    SendChatMessage(DEFAULTS.whisperPrefix .. message, "WHISPER", nil, playerName)
end

local function WhisperUnits(units, message)
    if not units or not message then
        return
    end

    for i = 1, #units do
        local unitData = units[i]

        if unitData and unitData.name then
            SendPrefixedWhisper(unitData.name, message)
        end
    end
end

local function CreateDummyUnit(name, classFile, healthMax)
    return {
        name = name,
        unitID = "debug",
        classFile = classFile,
        healthMax = healthMax
    }
end

local function BuildDummyRaidData()
    local raidData = {
        byClass = {},
        potentialTanks = {},
        byName = {}
    }

    for i = 1, #CLASS_ORDER do
        raidData.byClass[CLASS_ORDER[i]] = {}
    end

    local dummyUnits = {
        CreateDummyUnit("Sneakyy", "ROGUE", 24500),
        CreateDummyUnit("Cutstab", "ROGUE", 25100),
        CreateDummyUnit("Shadowcut", "ROGUE", 26300),

        CreateDummyUnit("Hexbolt", "WARLOCK", 22800),

        CreateDummyUnit("Massholy", "PRIEST", 21500),
        CreateDummyUnit("Discspam", "PRIEST", 22100),

        CreateDummyUnit("Bladestormx", "WARRIOR", 31200),

        CreateDummyUnit("Treeformz", "DRUID", 23600),

        CreateDummyUnit("Maindk", "DEATHKNIGHT", 46200),
        CreateDummyUnit("Gripchain", "DEATHKNIGHT", 44100),
        CreateDummyUnit("Chillrot", "DEATHKNIGHT", 27400),

        CreateDummyUnit("Holybuddy", "PALADIN", 24000),
        CreateDummyUnit("Retpunch", "PALADIN", 26800),

        CreateDummyUnit("Trapshot", "HUNTER", 25500),
        CreateDummyUnit("Deadeyeqt", "HUNTER", 24800)
    }

    for i = 1, #dummyUnits do
        local unitData = dummyUnits[i]

        if unitData.classFile and raidData.byClass[unitData.classFile] then
            raidData.byClass[unitData.classFile][#raidData.byClass[unitData.classFile] + 1] = unitData
        end

        raidData.byName[unitData.name] = unitData

        if unitData.healthMax > DEFAULTS.tankHealthThreshold then
            raidData.potentialTanks[#raidData.potentialTanks + 1] = {
                name = unitData.name,
                classFile = unitData.classFile,
                healthMax = unitData.healthMax
            }
        end
    end

    table.sort(raidData.byClass.ROGUE, CompareHealthAscNameAsc)
    table.sort(raidData.byClass.WARLOCK, CompareHealthAscNameAsc)
    table.sort(raidData.byClass.DEATHKNIGHT, CompareHealthAscNameAsc)
    table.sort(raidData.potentialTanks, CompareHealthDescNameAsc)

    return raidData
end

local function CollectRaidUnits()
    if DEFAULTS.debugModeEnabled then
        return BuildDummyRaidData()
    end

    local raidData = {
        byClass = {},
        potentialTanks = {},
        byName = {}
    }

    for i = 1, #CLASS_ORDER do
        raidData.byClass[CLASS_ORDER[i]] = {}
    end

    local raidCount = GetRaidMemberCountSafe()

    for i = 1, raidCount do
        local unitID = "raid" .. i

        if UnitExists(unitID) and UnitIsConnected(unitID) then
            local unitName = GetUnitName(unitID, true)

            if unitName then
                local _, classFile = UnitClass(unitID)
                local unitHealthMax = UnitHealthMax(unitID) or 0
                local unitData = {
                    name = unitName,
                    unitID = unitID,
                    classFile = classFile,
                    healthMax = unitHealthMax
                }

                if classFile and raidData.byClass[classFile] then
                    raidData.byClass[classFile][#raidData.byClass[classFile] + 1] = unitData
                end

                raidData.byName[unitName] = unitData

                if unitHealthMax > DEFAULTS.tankHealthThreshold then
                    raidData.potentialTanks[#raidData.potentialTanks + 1] = {
                        name = unitName,
                        classFile = classFile,
                        healthMax = unitHealthMax
                    }
                end
            end
        end
    end

    table.sort(raidData.byClass.ROGUE, CompareHealthAscNameAsc)
    table.sort(raidData.byClass.WARLOCK, CompareHealthAscNameAsc)
    table.sort(raidData.byClass.DEATHKNIGHT, CompareHealthAscNameAsc)
    table.sort(raidData.potentialTanks, CompareHealthDescNameAsc)

    return raidData
end

local function PickTankNames(potentialTanks)
    local tanks = {}

    if not potentialTanks then
        return tanks
    end

    local maxTanks = math.min(2, #potentialTanks)

    for i = 1, maxTanks do
        if potentialTanks[i] and potentialTanks[i].name then
            tanks[#tanks + 1] = potentialTanks[i].name
        end
    end

    return tanks
end

local function BuildCCAssignments(rogueUnits, deathKnightUnits, tankNames)
    local ccAssignments = {}
    local rogueIndex = 1
    local deathKnightIndex = 1

    for i = 1, 3 do
        if rogueUnits and rogueUnits[rogueIndex] then
            local rogueUnit = rogueUnits[rogueIndex]

            ccAssignments[#ccAssignments + 1] = {
                player = rogueUnit.name,
                classFile = rogueUnit.classFile,
                message = ASSIGNMENT_MESSAGES.cc[i]
            }

            rogueIndex = rogueIndex + 1
        else
            local pickedDeathKnight = nil

            while deathKnightUnits and deathKnightUnits[deathKnightIndex] do
                local deathKnightUnit = deathKnightUnits[deathKnightIndex]
                deathKnightIndex = deathKnightIndex + 1

                if deathKnightUnit and deathKnightUnit.name and not TableContains(tankNames, deathKnightUnit.name) then
                    pickedDeathKnight = deathKnightUnit
                    break
                end
            end

            if pickedDeathKnight then
                ccAssignments[#ccAssignments + 1] = {
                    player = pickedDeathKnight.name,
                    classFile = pickedDeathKnight.classFile,
                    message = ASSIGNMENT_MESSAGES.cc[i]
                }
            else
                break
            end
        end
    end

    return ccAssignments
end

local function BuildWarlockAssignment(warlockUnits)
    if warlockUnits and warlockUnits[1] and warlockUnits[1].name then
        return {
            player = warlockUnits[1].name,
            classFile = warlockUnits[1].classFile,
            message = ASSIGNMENT_MESSAGES.warlock
        }
    end

    return nil
end

local function BuildTankAssignments(tankNames, byName)
    local tankAssignments = {}

    if tankNames and tankNames[1] then
        local unitData = byName and byName[tankNames[1]]
        tankAssignments[#tankAssignments + 1] = {
            player = tankNames[1],
            classFile = unitData and unitData.classFile or nil,
            message = ASSIGNMENT_MESSAGES.tankMain
        }
    end

    if tankNames and tankNames[2] then
        local unitData = byName and byName[tankNames[2]]
        tankAssignments[#tankAssignments + 1] = {
            player = tankNames[2],
            classFile = unitData and unitData.classFile or nil,
            message = ASSIGNMENT_MESSAGES.tankOff
        }
    end

    return tankAssignments
end

local function BuildAssignments()
    local raidData = CollectRaidUnits()
    local tankNames = PickTankNames(raidData.potentialTanks)

    return {
        rogueUnits = raidData.byClass.ROGUE,
        warlockUnits = raidData.byClass.WARLOCK,
        priestUnits = raidData.byClass.PRIEST,
        warriorUnits = raidData.byClass.WARRIOR,
        druidUnits = raidData.byClass.DRUID,
        paladinUnits = raidData.byClass.PALADIN,
        hunterUnits = raidData.byClass.HUNTER,

        ccAssignments = BuildCCAssignments(raidData.byClass.ROGUE, raidData.byClass.DEATHKNIGHT, tankNames),
        warlockAssignment = BuildWarlockAssignment(raidData.byClass.WARLOCK),
        tankAssignments = BuildTankAssignments(tankNames, raidData.byName),

        priestMessage = ASSIGNMENT_MESSAGES.priest,
        warriorMessage = ASSIGNMENT_MESSAGES.warrior,
        druidMessage = ASSIGNMENT_MESSAGES.druid,
        paladinMessage = ASSIGNMENT_MESSAGES.paladin,
        hunterMessage = ASSIGNMENT_MESSAGES.hunter,

        raidLines = CopyList(RAID_LINES)
    }
end

local function SetStatusText(textValue, r, g, b)
    if not UI.statusText then
        return
    end

    UI.statusText:SetText(textValue or "")
    UI.statusText:SetTextColor(r or 1, g or 1, b or 1)
end

local function BuildColoredNamesFromUnits(unitList)
    local names = {}

    if not unitList then
        return names
    end

    for i = 1, #unitList do
        local unitData = unitList[i]

        if unitData and unitData.name then
            names[#names + 1] = WrapNameWithClassColor(unitData.name, unitData.classFile)
        end
    end

    return names
end

local function BuildActiveAssignmentSummaryText(assignments)
    if not assignments then
        return ""
    end

    local lines = {}

    if assignments.tankAssignments and assignments.tankAssignments[1] and assignments.tankAssignments[1].player then
        lines[#lines + 1] = "Main Tank: " .. WrapNameWithClassColor(
            assignments.tankAssignments[1].player,
            assignments.tankAssignments[1].classFile
        )
    end

    if assignments.tankAssignments and assignments.tankAssignments[2] and assignments.tankAssignments[2].player then
        lines[#lines + 1] = "Off Tank: " .. WrapNameWithClassColor(
            assignments.tankAssignments[2].player,
            assignments.tankAssignments[2].classFile
        )
    end

    if assignments.ccAssignments and #assignments.ccAssignments > 0 then
        local names = {}

        for i = 1, #assignments.ccAssignments do
            local assignment = assignments.ccAssignments[i]
            names[#names + 1] = WrapNameWithClassColor(assignment.player, assignment.classFile)
        end

        lines[#lines + 1] = "Assigned CC: " .. table.concat(names, ", ")
    end

    if assignments.warlockAssignment and assignments.warlockAssignment.player then
        lines[#lines + 1] = "Warlock: " .. WrapNameWithClassColor(
            assignments.warlockAssignment.player,
            assignments.warlockAssignment.classFile
        )
    end

    local priestNames = BuildColoredNamesFromUnits(assignments.priestUnits)
    local warriorNames = BuildColoredNamesFromUnits(assignments.warriorUnits)
    local druidNames = BuildColoredNamesFromUnits(assignments.druidUnits)
    local paladinNames = BuildColoredNamesFromUnits(assignments.paladinUnits)
    local hunterNames = BuildColoredNamesFromUnits(assignments.hunterUnits)

    if #priestNames > 0 then
        lines[#lines + 1] = "Priests: " .. table.concat(priestNames, ", ")
    end

    if #warriorNames > 0 then
        lines[#lines + 1] = "Warriors: " .. table.concat(warriorNames, ", ")
    end

    if #druidNames > 0 then
        lines[#lines + 1] = "Druids: " .. table.concat(druidNames, ", ")
    end

    if #paladinNames > 0 then
        lines[#lines + 1] = "Paladins: " .. table.concat(paladinNames, ", ")
    end

    if #hunterNames > 0 then
        lines[#lines + 1] = "Hunters: " .. table.concat(hunterNames, ", ")
    end

    if #lines == 0 then
        return "No active assignments found."
    end

    return table.concat(lines, "\n")
end

local function UpdateSummaryContentHeight()
    if not UI.summaryText or not UI.summaryContentFrame or not UI.summaryScrollFrame then
        return
    end

    local textHeight = UI.summaryText:GetStringHeight() or 0
    local minHeight = UI.summaryScrollFrame:GetHeight() or 0
    local contentHeight = math.max(textHeight + 8, minHeight)

    UI.summaryContentFrame:SetHeight(contentHeight)
end

local function RefreshSummaryText()
    if not UI.summaryText then
        return
    end

    if not IsPlayerInRaidGroup() then
        UI.summaryText:SetText("No active assignments found.")
        UpdateSummaryContentHeight()
        return
    end

    if not STATE.currentAssignments then
        UI.summaryText:SetText("No active assignments found.")
        UpdateSummaryContentHeight()
        return
    end

    UI.summaryText:SetText(BuildActiveAssignmentSummaryText(STATE.currentAssignments))
    UpdateSummaryContentHeight()
end

local function RefreshAssignmentsData()
    if not IsPlayerInRaidGroup() then
        STATE.currentAssignments = nil
        RefreshSummaryText()
        SetStatusText("You aren't in the raid.", 1.0, 0.2, 0.2)
        return
    end

    STATE.currentAssignments = BuildAssignments()
    RefreshSummaryText()

    if DEFAULTS.debugModeEnabled then
        SetStatusText("Assignments ready. Debug mode enabled.", 0.2, 1.0, 0.2)
        return
    end

    SetStatusText("Assignments ready.", 0.2, 1.0, 0.2)
end

local function FinishSend(parentFrame)
    STATE.isSending = false

    if UI.specificAnnouncementsButton then
        UI.specificAnnouncementsButton:Enable()
    end

    if UI.raidAnnouncementsButton then
        UI.raidAnnouncementsButton:Enable()
    end

    if parentFrame and parentFrame.GetParent then
        local mainFrame = parentFrame:GetParent()

        if mainFrame then
            AddToSpecialFrames(mainFrame)
        end
    end

    RefreshAssignmentsData()
end

local function StartRaidQueue(parentFrame, messages)
    STATE.raidQueue = {}
    STATE.raidQueueElapsed = 0

    if messages then
        for i = 1, #messages do
            STATE.raidQueue[#STATE.raidQueue + 1] = messages[i]
        end
    end

    if #STATE.raidQueue == 0 then
        delayFrame:SetScript("OnUpdate", nil)
        FinishSend(parentFrame)
        return
    end

    delayFrame:SetScript("OnUpdate", function(self, elapsed)
        STATE.raidQueueElapsed = STATE.raidQueueElapsed + elapsed

        if STATE.raidQueueElapsed < DEFAULTS.raidDelaySeconds then
            return
        end

        STATE.raidQueueElapsed = 0

        if #STATE.raidQueue == 0 then
            self:SetScript("OnUpdate", nil)
            FinishSend(parentFrame)
            return
        end

        local message = table.remove(STATE.raidQueue, 1)
        local chatType = "RAID"

        if TT_GetRaidChatType then
            chatType = TT_GetRaidChatType()
        elseif (IsRaidLeader and IsRaidLeader()) or (IsRaidOfficer and IsRaidOfficer()) then
            chatType = "RAID_WARNING"
        end

        if DEFAULTS.debugModeEnabled then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[DEBUG Raid]|r " .. message)
        else
            SendChatMessage(message, chatType)
        end

        if #STATE.raidQueue == 0 then
            self:SetScript("OnUpdate", nil)
            FinishSend(parentFrame)
        end
    end)
end

local function SendWhispersImmediate(assignments)
    if not assignments then
        return
    end

    for i = 1, #(assignments.ccAssignments or {}) do
        local assignment = assignments.ccAssignments[i]
        SendPrefixedWhisper(assignment.player, assignment.message)
    end

    if assignments.warlockAssignment then
        SendPrefixedWhisper(assignments.warlockAssignment.player, assignments.warlockAssignment.message)
    end

    for i = 1, #(assignments.tankAssignments or {}) do
        local tankAssignment = assignments.tankAssignments[i]
        SendPrefixedWhisper(tankAssignment.player, tankAssignment.message)
    end

    WhisperUnits(assignments.priestUnits, assignments.priestMessage)
    WhisperUnits(assignments.warriorUnits, assignments.warriorMessage)
    WhisperUnits(assignments.druidUnits, assignments.druidMessage)
    WhisperUnits(assignments.paladinUnits, assignments.paladinMessage)
    WhisperUnits(assignments.hunterUnits, assignments.hunterMessage)
end

local function HandleSpecificAnnouncements(parentFrame)
    if STATE.isSending then
        return
    end

    if not IsPlayerInRaidGroup() then
        SetStatusText("You aren't in the raid.", 1.0, 0.2, 0.2)
        RefreshSummaryText()
        return
    end

    if not STATE.currentAssignments then
        RefreshAssignmentsData()
    end

    if not STATE.currentAssignments then
        SetStatusText("No assignments available.", 1.0, 0.2, 0.2)
        return
    end

    STATE.isSending = true
    SetStatusText("Sending specific announcements...", 1.0, 0.82, 0.0)

    if UI.specificAnnouncementsButton then
        UI.specificAnnouncementsButton:Disable()
    end

    if UI.raidAnnouncementsButton then
        UI.raidAnnouncementsButton:Disable()
    end

    if parentFrame and parentFrame.GetParent then
        local mainFrame = parentFrame:GetParent()

        if mainFrame then
            RemoveFromSpecialFrames(mainFrame)
        end
    end

    SendWhispersImmediate(STATE.currentAssignments)
    FinishSend(parentFrame)
end

local function HandleRaidAnnouncements(parentFrame)
    if STATE.isSending then
        return
    end

    if not IsPlayerInRaidGroup() then
        SetStatusText("You aren't in the raid.", 1.0, 0.2, 0.2)
        RefreshSummaryText()
        return
    end

    if not STATE.currentAssignments then
        RefreshAssignmentsData()
    end

    if not STATE.currentAssignments then
        SetStatusText("No assignments available.", 1.0, 0.2, 0.2)
        return
    end

    STATE.isSending = true
    SetStatusText("Sending raid announcements...", 1.0, 0.82, 0.0)

    if UI.specificAnnouncementsButton then
        UI.specificAnnouncementsButton:Disable()
    end

    if UI.raidAnnouncementsButton then
        UI.raidAnnouncementsButton:Disable()
    end

    if parentFrame and parentFrame.GetParent then
        local mainFrame = parentFrame:GetParent()

        if mainFrame then
            RemoveFromSpecialFrames(mainFrame)
        end
    end

    StartRaidQueue(parentFrame, STATE.currentAssignments.raidLines or {})
end

local function ShouldAutoRefresh()
    if STATE.isSending then
        return false
    end

    if not UI.tabFrame then
        return false
    end

    return true
end

local function QueueAutoRefresh()
    if STATE.autoRefreshPending then
        return
    end

    if not ShouldAutoRefresh() then
        return
    end

    STATE.autoRefreshPending = true
    STATE.autoRefreshDelayRemaining = AUTO_REFRESH_DELAY_SECONDS

    autoRefreshFrame:SetScript("OnUpdate", function(self, elapsed)
        STATE.autoRefreshDelayRemaining = STATE.autoRefreshDelayRemaining - elapsed

        if STATE.autoRefreshDelayRemaining > 0 then
            return
        end

        self:SetScript("OnUpdate", nil)
        STATE.autoRefreshPending = false
        RefreshAssignmentsData()
    end)
end

rosterEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
rosterEventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
rosterEventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
rosterEventFrame:RegisterEvent("UNIT_NAME_UPDATE")

rosterEventFrame:SetScript("OnEvent", function(_, event, ...)
    if DEFAULTS.debugModeEnabled then
        QueueAutoRefresh()
        return
    end

    if event == "UNIT_NAME_UPDATE" then
        local unitID = ...

        if not unitID then
            return
        end

        if string.sub(unitID, 1, 4) ~= "raid" and string.sub(unitID, 1, 5) ~= "party" then
            return
        end
    end

    QueueAutoRefresh()
end)

local function CreateActionButton(parent, name, width, height, text)
    local button = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    button:SetSize(width, height)
    button:SetText(text)
    return button
end

local function CreateTitle(parent)
    local fontString = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fontString:SetPoint("TOP", 0, -18)
    fontString:SetText("Trial of the Crusader Assignments")
    fontString:SetTextColor(1.0, 0.82, 0.0)

    local fontObject = fontString:GetFontObject()
    if fontObject then
        local fontPath, _, fontFlags = fontObject:GetFont()
        fontString:SetFont(fontPath, 16, fontFlags)
    end

    return fontString
end

local function CreateDebugText(parent)
    if not DEFAULTS.debugModeEnabled then
        return nil
    end

    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOP", 0, -38)
    text:SetWidth(520)
    text:SetJustifyH("CENTER")
    text:SetText("|cff00ff00DEBUG MODE ENABLED|r")
    return text
end

local function ApplyPanelStyle(frame)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1
    })
    frame:SetBackdropColor(0, 0, 0, 0.85)
    frame:SetBackdropBorderColor(0.30, 0.30, 0.30, 1)
end

local function SkinScrollBarIfPossible(scrollBar)
    if not scrollBar then
        return
    end

    if SkinAssignmentsControlsWithElvUIIfAvailable then
        SkinAssignmentsControlsWithElvUIIfAvailable(nil, nil, nil, nil, scrollBar)
    end
end

local function CreateSummaryScrollArea(parent)
    local topOffset = DEFAULTS.debugModeEnabled and -62 or -50
    local scrollFrameName = "RaidPackAssignmentsSummaryScrollFrame"

    if _G[scrollFrameName] then
        _G[scrollFrameName]:Hide()
        _G[scrollFrameName]:SetParent(nil)
        _G[scrollFrameName] = nil
    end

    if _G[scrollFrameName .. "ScrollBar"] then
        _G[scrollFrameName .. "ScrollBar"]:Hide()
        _G[scrollFrameName .. "ScrollBar"]:SetParent(nil)
        _G[scrollFrameName .. "ScrollBar"] = nil
    end

    local containerFrame = CreateFrame("Frame", nil, parent)
    containerFrame:SetPoint("TOPLEFT", 16, topOffset)
    containerFrame:SetPoint("TOPRIGHT", -16, topOffset)
    containerFrame:SetPoint("BOTTOM", 0, 80)
    ApplyPanelStyle(containerFrame)

    local scrollFrame = CreateFrame("ScrollFrame", scrollFrameName, containerFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 8, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 8)

    local contentFrame = CreateFrame("Frame", nil, scrollFrame)
    contentFrame:SetWidth(484)
    contentFrame:SetHeight(1)
    scrollFrame:SetScrollChild(contentFrame)

    local text = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", 0, 0)
    text:SetWidth(484)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetSpacing(3)
    text:SetText("")

    local scrollBar = _G[scrollFrameName .. "ScrollBar"]

    UI.summaryContainerFrame = containerFrame
    UI.summaryScrollFrame = scrollFrame
    UI.summaryScrollBar = scrollBar
    UI.summaryContentFrame = contentFrame
    UI.summaryText = text

    SkinScrollBarIfPossible(scrollBar)

    return text
end

local function CreateStatusText(parent)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("BOTTOM", 0, 48)
    text:SetWidth(520)
    text:SetJustifyH("CENTER")
    text:SetText("")
    return text
end

local function InitializeUI(parent, onClose)
    UI.tabFrame = CreateFrame("Frame", nil, parent)
    UI.tabFrame:SetAllPoints()

    UI.titleText = CreateTitle(UI.tabFrame)
    UI.debugText = CreateDebugText(UI.tabFrame)
    CreateSummaryScrollArea(UI.tabFrame)
    UI.statusText = CreateStatusText(UI.tabFrame)

    UI.specificAnnouncementsButton = CreateActionButton(
        UI.tabFrame,
        "ToCAssignmentsSpecificAnnouncementsButton",
        184,
        26,
        "Specific Announcements"
    )
    UI.specificAnnouncementsButton:SetPoint("BOTTOMLEFT", 16, 14)

    UI.raidAnnouncementsButton = CreateActionButton(
        UI.tabFrame,
        "ToCAssignmentsRaidAnnouncementsButton",
        184,
        26,
        "Raid Announcements"
    )
    UI.raidAnnouncementsButton:SetPoint("LEFT", UI.specificAnnouncementsButton, "RIGHT", 12, 0)

    UI.specificAnnouncementsButton:SetScript("OnClick", function()
        HandleSpecificAnnouncements(UI.tabFrame)
    end)

    UI.raidAnnouncementsButton:SetScript("OnClick", function()
        HandleRaidAnnouncements(UI.tabFrame)
    end)

    if SkinAssignmentsControlsWithElvUIIfAvailable then
        SkinAssignmentsControlsWithElvUIIfAvailable(
            UI.specificAnnouncementsButton,
            UI.raidAnnouncementsButton,
            nil,
            nil,
            UI.summaryScrollBar
        )
    end

    RefreshAssignmentsData()

    return UI.tabFrame
end

function CreateToCAssignmentsTabContent(parent, onClose)
    return InitializeUI(parent, onClose)
end

function RefreshToCAssignmentsPreview()
    RefreshAssignmentsData()
end
