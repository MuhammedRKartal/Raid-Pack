-- Paladin_Buffs.lua

local addonName, addonTable = ...

-- =========================
-- CONSTANTS / CONFIG
-- =========================

local DEFAULTS = {
    tankHpThreshold = 36000,
    healManaThreshold = 20000
}

local INSTANCE_IDS = {
    ICC = 631
}

local BUFF_ORDER = {
    "GBOS",
    "GBOK",
    "GBOM",
    "GBOW",
    "CLASS"
}

local INSTANCE_THRESHOLD_PRESETS = {
    [INSTANCE_IDS.ICC] = {
        hpMultiplier = 1.30,
        manaMultiplier = 1.30,
        label = "ICC +30%"
    }
}

local BUFF_META = {
    GBOS = {
        title = "GBOS",
        shortText = "Sanctuary",
        previewText = "GBOS",
        whisperText = "Your assignment: Greater Blessing of Salvation"
    },
    GBOK = {
        title = "GBOK",
        shortText = "Kings",
        previewText = "GBOK",
        whisperText = "Your assignment: Greater Blessing of Kings"
    },
    GBOM = {
        title = "GBOM",
        shortText = "Might",
        previewText = "GBOM",
        whisperText = "Your assignment: Greater Blessing of Might"
    },
    GBOW = {
        title = "GBOW",
        shortText = "Wisdom",
        previewText = "GBOW",
        whisperText = "Your assignment: Greater Blessing of Wisdom"
    },
    CLASS = {
        title = "Class Buff",
        shortText = "Class",
        previewText = "Class Buff",
        whisperText = "Your assignment: Class Blessing"
    }
}

local PREVIEW_LINE_HEIGHT = 18
local PREVIEW_LINE_WIDTH = 820
local PREVIEW_MAX_VISIBLE_PALADINS = 7
local REBUILD_THROTTLE_SECONDS = 0.30

-- =========================
-- SESSION STATE
-- =========================

local function CreateBuffMap(defaultValue)
    local map = {}

    for i = 1, #BUFF_ORDER do
        map[BUFF_ORDER[i]] = defaultValue
    end

    return map
end

local PaladinBuffSessionState = {
    selected = CreateBuffMap(nil),
    manual = CreateBuffMap(false),
    baseHpThreshold = DEFAULTS.tankHpThreshold,
    baseManaThreshold = DEFAULTS.healManaThreshold,
    lastRosterSig = nil,
    announceBackups = false
}

local CurrentState = {
    paladins = {},
    rolesByName = {},
    tankCandidates = {},
    healCandidates = {},
    tank = nil,
    holy = nil,
    ret = nil,
    activeBuffs = {},
    hpThreshold = DEFAULTS.tankHpThreshold,
    manaThreshold = DEFAULTS.healManaThreshold
}

-- =========================
-- UI STATE
-- =========================

local tabFrame = nil
local previewPanel = nil
local previewContent = nil
local previewLines = {}

local whisperButton = nil
local raidButton = nil
local announceBackupsCheckBox = nil

local hpEditBox = nil
local manaEditBox = nil
local hpInputHolder = nil
local manaInputHolder = nil
local announceBackupsLabel = nil

local dropDownsByBuff = {}
local columnsAnchorRef = nil
local activeColumnsByKey = nil

local lastRebuildAt = 0
local rosterEventFrame = nil
local pendingDelayedRebuild = false

-- =========================
-- GENERIC HELPERS
-- =========================

local function ToSafeNumber(value)
    if value == nil then
        return 0
    end

    return value
end

local function CopyList(list)
    local out = {}

    for i = 1, #list do
        out[i] = list[i]
    end

    return out
end

local function CompareNameAsc(a, b)
    local aName = a and a.name or ""
    local bName = b and b.name or ""
    return aName < bName
end

local function CompareByFields(a, b, rules)
    for i = 1, #rules do
        local rule = rules[i]
        local aValue = ToSafeNumber(a and a[rule.key] or 0)
        local bValue = ToSafeNumber(b and b[rule.key] or 0)

        if aValue ~= bValue then
            if rule.desc then
                return aValue > bValue
            end

            return aValue < bValue
        end
    end

    return CompareNameAsc(a, b)
end

local function CompareHealthDescManaDescNameAsc(a, b)
    return CompareByFields(a, b, {
        { key = "healthMax", desc = true },
        { key = "manaMax", desc = true }
    })
end

local function CompareManaDescHealthDescNameAsc(a, b)
    return CompareByFields(a, b, {
        { key = "manaMax", desc = true },
        { key = "healthMax", desc = true }
    })
end

local function CompareManaAscHealthDescNameAsc(a, b)
    return CompareByFields(a, b, {
        { key = "manaMax", desc = false },
        { key = "healthMax", desc = true }
    })
end

local function BuildRosterSignature(paladins)
    if not paladins or #paladins == 0 then
        return ""
    end

    local names = {}

    for i = 1, #paladins do
        names[i] = paladins[i].name
    end

    table.sort(names)

    return table.concat(names, "|")
end

local function GetBuffShortText(buffKey)
    local meta = BUFF_META[buffKey]

    if not meta then
        return tostring(buffKey)
    end

    return meta.shortText
end

local function GetBuffWhisperText(buffKey)
    local meta = BUFF_META[buffKey]

    if not meta then
        return "Your assignment: " .. tostring(buffKey)
    end

    return meta.whisperText
end

local function GetBackupWhisperText()
    return "Your assignment: Backup on missing buffs"
end

local function FormatBuffAssignment(name, buffKey)
    return name .. " -> " .. GetBuffShortText(buffKey)
end

local function GetSelectedPaladinForBuff(buffKey)
    return PaladinBuffSessionState.selected[buffKey]
end

local function SetSelectedPaladinForBuff(buffKey, paladinName, isManual)
    PaladinBuffSessionState.selected[buffKey] = paladinName

    if isManual ~= nil then
        PaladinBuffSessionState.manual[buffKey] = isManual
    end
end

local function NormalizeUnitMaxHealth(unitID, value)
    value = ToSafeNumber(value)

    if not UnitExists(unitID) then
        return 0
    end

    if value <= 1 then
        return 0
    end

    return value
end

local function NormalizeUnitMaxMana(unitID, value)
    value = ToSafeNumber(value)

    if not UnitExists(unitID) then
        return 0
    end

    if value <= 1 then
        return 0
    end

    return value
end

local function FindPaladinByName(paladins, name)
    if not name then
        return nil
    end

    for i = 1, #paladins do
        local paladin = paladins[i]

        if paladin and paladin.name == name then
            return paladin
        end
    end

    return nil
end

local function IsPaladinAvailableByName(paladins, name)
    return FindPaladinByName(paladins, name) ~= nil
end

local function IsTankCandidateByName(tankCandidates, name)
    if not name then
        return false
    end

    for i = 1, #tankCandidates do
        local paladin = tankCandidates[i]

        if paladin and paladin.name == name then
            return true
        end
    end

    return false
end

-- =========================
-- INSTANCE / GROUP HELPERS
-- =========================

local function GetGroupMemberCount()
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        return GetNumRaidMembers(), true
    end

    local partyCount = 0

    if GetNumPartyMembers then
        partyCount = GetNumPartyMembers()
    end

    if partyCount > 0 then
        return partyCount + 1, false
    end

    return 1, false
end

local function IterateGroupUnits()
    local units = {}
    local _, isRaid = GetGroupMemberCount()

    if isRaid then
        local raidCount = GetNumRaidMembers()

        for i = 1, raidCount do
            units[#units + 1] = "raid" .. i
        end

        return units
    end

    units[#units + 1] = "player"

    local partyCount = 0

    if GetNumPartyMembers then
        partyCount = GetNumPartyMembers()
    end

    for i = 1, partyCount do
        units[#units + 1] = "party" .. i
    end

    return units
end

local function GetCurrentInstanceID()
    if not GetInstanceInfo then
        return nil
    end

    local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    return instanceID
end

local function IsInIcecrownCitadel()
    local instanceID = GetCurrentInstanceID()
    return instanceID == INSTANCE_IDS.ICC
end

local function GetInstanceThresholdPreset()
    local instanceID = GetCurrentInstanceID()

    if not instanceID then
        return nil
    end

    return INSTANCE_THRESHOLD_PRESETS[instanceID]
end

local function GetEffectiveThresholds()
    local hpThreshold = ToSafeNumber(PaladinBuffSessionState.baseHpThreshold)
    local manaThreshold = ToSafeNumber(PaladinBuffSessionState.baseManaThreshold)
    local preset = GetInstanceThresholdPreset()

    if hpThreshold <= 0 then
        hpThreshold = DEFAULTS.tankHpThreshold
    end

    if manaThreshold <= 0 then
        manaThreshold = DEFAULTS.healManaThreshold
    end

    if preset then
        hpThreshold = math.floor(hpThreshold * ToSafeNumber(preset.hpMultiplier) + 0.5)
        manaThreshold = math.floor(manaThreshold * ToSafeNumber(preset.manaMultiplier) + 0.5)
    end

    return hpThreshold, manaThreshold
end

local function GetUnitMaxMana(unitID)
    if not UnitExists(unitID) then
        return 0
    end

    if UnitPowerType then
        local powerType = UnitPowerType(unitID)

        if powerType ~= 0 then
            return 0
        end
    end

    local manaValue = 0

    if UnitPowerMax then
        manaValue = ToSafeNumber(UnitPowerMax(unitID, 0))
    elseif UnitManaMax then
        manaValue = ToSafeNumber(UnitManaMax(unitID))
    end

    return NormalizeUnitMaxMana(unitID, manaValue)
end

local function GetGroupPaladins()
    local paladins = {}
    local units = IterateGroupUnits()

    for i = 1, #units do
        local unitID = units[i]

        if UnitExists(unitID) and UnitIsConnected(unitID) then
            local name = GetUnitName(unitID, true)

            if name then
                local _, classFile = UnitClass(unitID)

                if classFile == "PALADIN" then
                    local healthMax = NormalizeUnitMaxHealth(unitID, UnitHealthMax(unitID))
                    local manaMax = GetUnitMaxMana(unitID)

                    paladins[#paladins + 1] = {
                        name = name,
                        unitID = unitID,
                        healthMax = healthMax,
                        manaMax = manaMax
                    }
                end
            end
        end
    end

    table.sort(paladins, CompareNameAsc)

    return paladins
end

-- =========================
-- ROLE HEURISTICS
-- =========================

local function ClassifyPaladinRole(paladin, hpThreshold, manaThreshold)
    local isTank = paladin.healthMax >= hpThreshold
    local isHeal = paladin.manaMax >= manaThreshold
    local isDps = (not isTank) and (not isHeal)

    local roleParts = {}

    if isTank then
        roleParts[#roleParts + 1] = "TANK"
    end

    if isHeal then
        roleParts[#roleParts + 1] = "HEAL"
    end

    if isDps then
        roleParts[#roleParts + 1] = "DPS"
    end

    return {
        text = table.concat(roleParts, " + "),
        isTank = isTank,
        isHeal = isHeal,
        isDps = isDps
    }
end

local function ComputeHeuristicRoles(paladins)
    local hpThreshold, manaThreshold = GetEffectiveThresholds()

    local rolesByName = {}
    local tankCandidates = {}
    local healCandidates = {}
    local dpsCandidates = {}

    for i = 1, #paladins do
        local paladin = paladins[i]
        local roleInfo = ClassifyPaladinRole(paladin, hpThreshold, manaThreshold)

        rolesByName[paladin.name] = roleInfo

        if roleInfo.isTank then
            tankCandidates[#tankCandidates + 1] = paladin
        end

        if roleInfo.isHeal then
            healCandidates[#healCandidates + 1] = paladin
        end

        if roleInfo.isDps then
            dpsCandidates[#dpsCandidates + 1] = paladin
        end
    end

    table.sort(tankCandidates, CompareHealthDescManaDescNameAsc)
    table.sort(healCandidates, CompareManaDescHealthDescNameAsc)
    table.sort(dpsCandidates, CompareManaAscHealthDescNameAsc)

    local tank = tankCandidates[1]

    local holy = healCandidates[1]
    if not holy then
        local byManaDesc = CopyList(paladins)
        table.sort(byManaDesc, CompareManaDescHealthDescNameAsc)
        holy = byManaDesc[1]
    end

    local ret = dpsCandidates[1]
    if not ret then
        local byManaAsc = CopyList(paladins)
        table.sort(byManaAsc, CompareManaAscHealthDescNameAsc)

        for i = 1, #byManaAsc do
            local paladin = byManaAsc[i]

            if not tank or paladin.name ~= tank.name then
                ret = paladin
                break
            end
        end

        if not ret then
            ret = byManaAsc[1]
        end
    end

    return rolesByName, tankCandidates, healCandidates, tank, holy, ret, hpThreshold, manaThreshold
end

local function BuildRoleHintText(name, rolesByName)
    local roleInfo = rolesByName[name]

    if not roleInfo then
        return "DPS"
    end

    return roleInfo.text or "DPS"
end

-- =========================
-- ACTIVE BUFF LOGIC
-- =========================

local function BuildActiveBuffList(paladinCount, hasTankCandidates)
    local buffs = {}

    if paladinCount <= 0 then
        return buffs
    end

    if paladinCount == 1 then
        buffs[#buffs + 1] = "GBOK"
        return buffs
    end

    if paladinCount == 2 then
        buffs[#buffs + 1] = "GBOK"
        buffs[#buffs + 1] = "CLASS"
        return buffs
    end

    if paladinCount == 3 then
        buffs[#buffs + 1] = "GBOK"
        buffs[#buffs + 1] = "GBOM"
        buffs[#buffs + 1] = "GBOW"
        return buffs
    end

    if hasTankCandidates then
        buffs[#buffs + 1] = "GBOS"
    end

    buffs[#buffs + 1] = "GBOK"
    buffs[#buffs + 1] = "GBOM"
    buffs[#buffs + 1] = "GBOW"

    return buffs
end

local function BuildGBOSOrder(tankCandidates)
    local ordered = {}

    if tankCandidates and #tankCandidates > 0 then
        for i = 1, #tankCandidates do
            ordered[#ordered + 1] = tankCandidates[i]
        end
    end

    table.sort(ordered, CompareHealthDescManaDescNameAsc)

    return ordered
end

local function BuildGBOWOrder(paladins, holy)
    local ordered = CopyList(paladins)

    table.sort(ordered, function(a, b)
        if holy and a.name == holy.name and b.name ~= holy.name then
            return true
        end

        if holy and b.name == holy.name and a.name ~= holy.name then
            return false
        end

        return CompareManaDescHealthDescNameAsc(a, b)
    end)

    return ordered
end

local function BuildGBOMOrder(paladins, ret)
    local ordered = CopyList(paladins)

    table.sort(ordered, function(a, b)
        if ret and a.name == ret.name and b.name ~= ret.name then
            return true
        end

        if ret and b.name == ret.name and a.name ~= ret.name then
            return false
        end

        return CompareManaAscHealthDescNameAsc(a, b)
    end)

    return ordered
end

local function BuildGBOKOrder(paladins, tank, paladinCount)
    local ordered = CopyList(paladins)

    table.sort(ordered, function(a, b)
        if paladinCount == 2 and tank then
            if a.name == tank.name and b.name ~= tank.name then
                return true
            end

            if b.name == tank.name and a.name ~= tank.name then
                return false
            end
        end

        return CompareHealthDescManaDescNameAsc(a, b)
    end)

    return ordered
end

local function BuildCLASSOrder(paladins)
    local ordered = CopyList(paladins)
    table.sort(ordered, CompareHealthDescManaDescNameAsc)
    return ordered
end

local function BuildOrderedNameListForBuff(paladins, buffKey, tank, holy, ret, paladinCount, tankCandidates)
    if buffKey == "GBOS" then
        return BuildGBOSOrder(tankCandidates)
    end

    if buffKey == "GBOW" then
        return BuildGBOWOrder(paladins, holy)
    end

    if buffKey == "GBOM" then
        return BuildGBOMOrder(paladins, ret)
    end

    if buffKey == "GBOK" then
        return BuildGBOKOrder(paladins, tank, paladinCount)
    end

    if buffKey == "CLASS" then
        return BuildCLASSOrder(paladins)
    end

    return BuildCLASSOrder(paladins)
end

-- =========================
-- ASSIGNMENT LOGIC
-- =========================

local function IsBuffActive(buffKey)
    for i = 1, #CurrentState.activeBuffs do
        if CurrentState.activeBuffs[i] == buffKey then
            return true
        end
    end

    return false
end

local function GetUsedNamesMap(exceptBuffKey)
    local usedNames = {}

    for i = 1, #CurrentState.activeBuffs do
        local buffKey = CurrentState.activeBuffs[i]

        if exceptBuffKey ~= buffKey then
            local selectedName = GetSelectedPaladinForBuff(buffKey)

            if selectedName then
                usedNames[selectedName] = true
            end
        end
    end

    return usedNames
end

local function IsCurrentSelectionStillValid(buffKey, paladins, tankCandidates, usedNames)
    local currentName = PaladinBuffSessionState.selected[buffKey]

    if not currentName then
        return false
    end

    if not IsPaladinAvailableByName(paladins, currentName) then
        return false
    end

    if usedNames[currentName] then
        return false
    end

    if buffKey == "GBOS" and not IsTankCandidateByName(tankCandidates, currentName) then
        return false
    end

    return true
end

local function ResolveCurrentStickyAssignment(buffKey, paladins, tankCandidates, tank, holy, ret)
    local usedNames = GetUsedNamesMap(buffKey)

    if IsCurrentSelectionStillValid(buffKey, paladins, tankCandidates, usedNames) then
        return
    end

    local ordered = BuildOrderedNameListForBuff(
        paladins,
        buffKey,
        tank,
        holy,
        ret,
        #paladins,
        tankCandidates
    )

    PaladinBuffSessionState.selected[buffKey] = nil

    for i = 1, #ordered do
        local paladin = ordered[i]

        if paladin and paladin.name and not usedNames[paladin.name] then
            if buffKey ~= "GBOS" or IsTankCandidateByName(tankCandidates, paladin.name) then
                PaladinBuffSessionState.selected[buffKey] = paladin.name
                return
            end
        end
    end
end

local function AutoAssignDefaults(paladins, tankCandidates, tank, holy, ret, activeBuffs)
    local selected = PaladinBuffSessionState.selected
    local manual = PaladinBuffSessionState.manual

    local availableNames = {}

    for i = 1, #paladins do
        availableNames[paladins[i].name] = true
    end

    for i = 1, #BUFF_ORDER do
        local buffKey = BUFF_ORDER[i]
        local selectedName = selected[buffKey]

        if selectedName and not availableNames[selectedName] then
            selected[buffKey] = nil
            manual[buffKey] = false
        end
    end

    local activeMap = {}

    for i = 1, #activeBuffs do
        activeMap[activeBuffs[i]] = true
    end

    for i = 1, #BUFF_ORDER do
        local buffKey = BUFF_ORDER[i]

        if not activeMap[buffKey] then
            selected[buffKey] = nil
            manual[buffKey] = false
        end
    end

    local usedNames = {}

    local function RebuildUsedNames()
        usedNames = {}

        for i = 1, #BUFF_ORDER do
            local buffKey = BUFF_ORDER[i]
            local selectedName = selected[buffKey]

            if selectedName then
                usedNames[selectedName] = true
            end
        end
    end

    local function PickFirstUnused(orderedList)
        for i = 1, #orderedList do
            local paladin = orderedList[i]

            if paladin and paladin.name and not usedNames[paladin.name] then
                return paladin.name
            end
        end

        return nil
    end

    local function RefillMissingAutoAssignments()
        RebuildUsedNames()

        for i = 1, #activeBuffs do
            local buffKey = activeBuffs[i]

            if (not manual[buffKey]) and (not selected[buffKey]) then
                local ordered = BuildOrderedNameListForBuff(
                    paladins,
                    buffKey,
                    tank,
                    holy,
                    ret,
                    #paladins,
                    tankCandidates
                )

                local pickedName = PickFirstUnused(ordered)

                if pickedName then
                    selected[buffKey] = pickedName
                    usedNames[pickedName] = true
                end
            end
        end
    end

    RebuildUsedNames()

    if activeMap.GBOS and (not manual.GBOS) then
        ResolveCurrentStickyAssignment("GBOS", paladins, tankCandidates, tank, holy, ret)
    end

    RebuildUsedNames()

    if activeMap.GBOK and (not manual.GBOK) then
        ResolveCurrentStickyAssignment("GBOK", paladins, tankCandidates, tank, holy, ret)
    end

    RebuildUsedNames()

    if activeMap.GBOM and (not manual.GBOM) then
        ResolveCurrentStickyAssignment("GBOM", paladins, tankCandidates, tank, holy, ret)
    end

    RebuildUsedNames()

    if activeMap.GBOW and (not manual.GBOW) then
        ResolveCurrentStickyAssignment("GBOW", paladins, tankCandidates, tank, holy, ret)
    end

    RebuildUsedNames()

    if activeMap.CLASS and (not manual.CLASS) and (not selected.CLASS) then
        local orderedClass = BuildOrderedNameListForBuff(paladins, "CLASS", tank, holy, ret, #paladins, tankCandidates)
        selected.CLASS = PickFirstUnused(orderedClass)
    end

    RebuildUsedNames()

    local seenNames = {}

    for i = 1, #activeBuffs do
        local buffKey = activeBuffs[i]
        local selectedName = selected[buffKey]

        if selectedName then
            if seenNames[selectedName] then
                if not manual[buffKey] then
                    selected[buffKey] = nil
                end
            else
                seenNames[selectedName] = true
            end
        end
    end

    RefillMissingAutoAssignments()
end

local function GetAssignedPaladinNamesMap()
    local assignedNames = {}

    for i = 1, #CurrentState.activeBuffs do
        local buffKey = CurrentState.activeBuffs[i]
        local paladinName = PaladinBuffSessionState.selected[buffKey]

        if paladinName then
            assignedNames[paladinName] = true
        end
    end

    return assignedNames
end

local function BuildBackupPaladinList()
    local assignedNames = GetAssignedPaladinNamesMap()
    local backups = {}

    for i = 1, #CurrentState.paladins do
        local paladin = CurrentState.paladins[i]

        if paladin and paladin.name and not assignedNames[paladin.name] then
            backups[#backups + 1] = paladin.name
        end
    end

    table.sort(backups)

    return backups
end

local function BuildDropDownOptionsForBuff(buffKey)
    local ordered = BuildOrderedNameListForBuff(
        CurrentState.paladins,
        buffKey,
        CurrentState.tank,
        CurrentState.holy,
        CurrentState.ret,
        #CurrentState.paladins,
        CurrentState.tankCandidates
    )

    local usedNames = GetUsedNamesMap(buffKey)
    local currentSelected = GetSelectedPaladinForBuff(buffKey)
    local options = {}

    for i = 1, #ordered do
        local paladin = ordered[i]

        if paladin and paladin.name then
            local paladinName = paladin.name

            if (not usedNames[paladinName]) or (currentSelected == paladinName) then
                options[#options + 1] = {
                    value = paladinName,
                    text = paladinName
                }
            end
        end
    end

    return options
end

-- =========================
-- PREVIEW
-- =========================

local function ClearPreviewLines()
    for i = 1, #previewLines do
        local fontString = previewLines[i]

        if fontString then
            fontString:Hide()
            fontString:SetText("")
        end
    end
end

-- 1) Heuristic Roles içindeki yazıların fontSize'ını 12 yap
local function EnsurePreviewLine(index)
    if previewLines[index] then
        return previewLines[index]
    end

    local fontString = previewContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fontString:SetTextColor(0.90, 0.90, 0.90)
    fontString:SetJustifyH("LEFT")
    fontString:SetPoint("TOPLEFT", 10, -10 - ((index - 1) * PREVIEW_LINE_HEIGHT))
    fontString:SetWidth(PREVIEW_LINE_WIDTH)
    fontString:SetHeight(PREVIEW_LINE_HEIGHT)

    local font, _, flags = fontString:GetFont()
    fontString:SetFont(font or "Fonts\\FRIZQT__.TTF", 12, flags or "")

    fontString:Hide()

    previewLines[index] = fontString

    return fontString
end

local function BuildMainRaidAnnouncementString()
    local parts = {}

    for i = 1, #CurrentState.activeBuffs do
        local buffKey = CurrentState.activeBuffs[i]
        local paladinName = PaladinBuffSessionState.selected[buffKey]

        if paladinName then
            parts[#parts + 1] = FormatBuffAssignment(paladinName, buffKey)
        end
    end

    if #parts == 0 then
        return nil
    end

    return table.concat(parts, ", ")
end

local function BuildBackupRaidAnnouncementString()
    local backupPaladins = BuildBackupPaladinList()

    if #backupPaladins == 0 then
        return nil
    end

    return "Backup on Buffs: " .. table.concat(backupPaladins, ", ")
end

local function RenderPreview()
    if not previewContent then
        return
    end

    local lines = {}

    if #CurrentState.paladins == 0 then
        lines[#lines + 1] = "|cffff5555No paladins found in group.|r"
    else
        local paladinsForPreview = CopyList(CurrentState.paladins)
        table.sort(paladinsForPreview, CompareHealthDescManaDescNameAsc)

        local maxVisible = PREVIEW_MAX_VISIBLE_PALADINS
        if #paladinsForPreview < maxVisible then
            maxVisible = #paladinsForPreview
        end

        local assignedNames = GetAssignedPaladinNamesMap()

        for i = 1, maxVisible do
            local paladin = paladinsForPreview[i]
            local roleText = BuildRoleHintText(paladin.name, CurrentState.rolesByName)
            local nameText = paladin.name

            if assignedNames[paladin.name] then
                nameText = "|cff00ff00" .. paladin.name .. "|r"
            end

            lines[#lines + 1] = nameText .. " - " .. roleText .. " (HP " .. paladin.healthMax .. ", Mana " .. paladin.manaMax .. ")"
        end
    end

    ClearPreviewLines()

    for i = 1, #lines do
        local fontString = EnsurePreviewLine(i)
        fontString:SetText(lines[i])
        fontString:Show()
    end

    local totalHeight = 20 + (PREVIEW_MAX_VISIBLE_PALADINS * PREVIEW_LINE_HEIGHT)

    if totalHeight < 1 then
        totalHeight = 1
    end

    previewContent:SetHeight(totalHeight)
end

-- =========================
-- SEND LOGIC
-- =========================

local function SendAssignmentWhispers()
    for i = 1, #CurrentState.activeBuffs do
        local buffKey = CurrentState.activeBuffs[i]
        local paladinName = PaladinBuffSessionState.selected[buffKey]

        if paladinName then
            SendChatMessage(GetBuffWhisperText(buffKey), "WHISPER", nil, paladinName)
        end
    end

    if PaladinBuffSessionState.announceBackups then
        local backupPaladins = BuildBackupPaladinList()

        for i = 1, #backupPaladins do
            SendChatMessage(GetBackupWhisperText(), "WHISPER", nil, backupPaladins[i])
        end
    end
end

local function SendRaidAnnouncement()
    if not GetNumRaidMembers or GetNumRaidMembers() <= 0 then
        return
    end

    local mainMessage = BuildMainRaidAnnouncementString()

    if not mainMessage then
        return
    end

    if TT_SanitizeChatMessage then
        mainMessage = TT_SanitizeChatMessage(mainMessage)
    end

    local chatType = "RAID"

    if (IsRaidLeader and IsRaidLeader()) or (IsRaidOfficer and IsRaidOfficer()) then
        chatType = "RAID_WARNING"
    elseif TT_GetRaidChatType then
        chatType = TT_GetRaidChatType()
    end

    SendChatMessage(mainMessage, chatType)

    if PaladinBuffSessionState.announceBackups then
        local backupMessage = BuildBackupRaidAnnouncementString()

        if backupMessage then
            if TT_SanitizeChatMessage then
                backupMessage = TT_SanitizeChatMessage(backupMessage)
            end

            SendChatMessage(backupMessage, chatType)
        end
    end
end

-- =========================
-- UI HELPERS
-- =========================

local function CreateActionButton(parent, name, text, width, height)
    local button = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    button:SetSize(width, height)
    button:SetText(text)
    return button
end


local DARK_BOX_BACKGROUND_RED = 0.03
local DARK_BOX_BACKGROUND_GREEN = 0.03
local DARK_BOX_BACKGROUND_BLUE = 0.03
local DARK_BOX_BACKGROUND_ALPHA = 0.98

local DARK_BOX_BORDER_RED = 0.18
local DARK_BOX_BORDER_GREEN = 0.18
local DARK_BOX_BORDER_BLUE = 0.18
local DARK_BOX_BORDER_ALPHA = 1

local LIGHT_BOX_TEXT_RED = 0.95
local LIGHT_BOX_TEXT_GREEN = 0.95
local LIGHT_BOX_TEXT_BLUE = 0.95

local function ApplyDarkBoxStyle(frame)
    if not frame then
        return
    end

    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1
    })
    frame:SetBackdropColor(
        DARK_BOX_BACKGROUND_RED,
        DARK_BOX_BACKGROUND_GREEN,
        DARK_BOX_BACKGROUND_BLUE,
        DARK_BOX_BACKGROUND_ALPHA
    )
    frame:SetBackdropBorderColor(
        DARK_BOX_BORDER_RED,
        DARK_BOX_BORDER_GREEN,
        DARK_BOX_BORDER_BLUE,
        DARK_BOX_BORDER_ALPHA
    )
end

local function SkinDropDownDark(dropdown, width, height)
    if not dropdown or not dropdown.GetName then
        return
    end

    local dropDownName = dropdown:GetName()

    if not dropDownName then
        return
    end

    local left = _G[dropDownName .. "Left"]
    local middle = _G[dropDownName .. "Middle"]
    local right = _G[dropDownName .. "Right"]
    local button = _G[dropDownName .. "Button"]
    local textLabel = _G[dropDownName .. "Text"]

    if left and left.Hide then
        left:Hide()
    end

    if middle and middle.Hide then
        middle:Hide()
    end

    if right and right.Hide then
        right:Hide()
    end

    if not dropdown._darkBackground then
        local darkBackground = CreateFrame("Frame", nil, dropdown)
        darkBackground:SetFrameLevel(dropdown:GetFrameLevel() - 1)
        darkBackground:SetPoint("TOPLEFT", 16, -2)
        darkBackground:SetPoint("BOTTOMRIGHT", -20, 8)
        ApplyDarkBoxStyle(darkBackground)
        dropdown._darkBackground = darkBackground
    else
        ApplyDarkBoxStyle(dropdown._darkBackground)
    end

    if width then
        UIDropDownMenu_SetWidth(dropdown, width)
    end

    if height and dropdown.SetHeight then
        dropdown:SetHeight(height)
    end

    if button then
        button:ClearAllPoints()
        button:SetPoint("RIGHT", dropdown, "RIGHT", -2, 2)
    end

    if textLabel then
        textLabel:ClearAllPoints()
        textLabel:SetPoint("LEFT", dropdown, "LEFT", 24, 2)
        textLabel:SetPoint("RIGHT", dropdown, "RIGHT", -34, 2)
        textLabel:SetJustifyH("LEFT")
        textLabel:SetTextColor(LIGHT_BOX_TEXT_RED, LIGHT_BOX_TEXT_GREEN, LIGHT_BOX_TEXT_BLUE)
    end
end

local function CreatePixelInput(parent, width, height)
    local background = CreateFrame("Frame", nil, parent)
    background:SetSize(width, height)
    ApplyDarkBoxStyle(background)

    local editBox = CreateFrame("EditBox", nil, background)
    editBox:SetAllPoints(background)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject("GameFontHighlightSmall")
    editBox:SetTextInsets(6, 6, 0, 0)
    editBox:SetJustifyH("CENTER")
    editBox:SetTextColor(LIGHT_BOX_TEXT_RED, LIGHT_BOX_TEXT_GREEN, LIGHT_BOX_TEXT_BLUE)

    background._editBox = editBox
    editBox._background = background

    return background, editBox
end

local function CreateSectionTitle(parent, text, point, relativeTo, relativePoint, offsetX, offsetY, justifyH)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint(point, relativeTo, relativePoint, offsetX, offsetY)
    label:SetText(text)
    label:SetTextColor(1.00, 0.82, 0.00)
    label:SetJustifyH(justifyH or "LEFT")

    local font, _, flags = label:GetFont()
    label:SetFont(font or "Fonts\FRIZQT__.TTF", 16, flags or "")

    return label
end

local function CreateThresholdEdit(parent, defaultValue, width)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width or 140, 24)

    local inputBackground, editBox = CreatePixelInput(holder, width or 140, 24)
    inputBackground:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    inputBackground:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)

    editBox:SetNumeric(true)
    editBox:SetMaxLetters(6)
    editBox:SetText(tostring(defaultValue or ""))

    holder._background = inputBackground
    holder._editBox = editBox

    return holder, editBox
end

local function CreateBuffColumn(parent, buffKey, titleText, dropDownWidth)
    local column = CreateFrame("Frame", nil, parent)
    column:SetSize((dropDownWidth or 176) + 8, 78)

    local label = column:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 0, 0)
    label:SetPoint("TOPRIGHT", 0, 0)
    label:SetJustifyH("LEFT")
    label:SetText(titleText)
    label:SetTextColor(0.95, 0.95, 0.95)

    local dropdown = CreateFrame("Frame", "PaladinBuffsDropDown_" .. buffKey, column, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", label, "BOTTOMLEFT", -14, -4)
    dropdown:SetWidth(dropDownWidth or 176)
    dropdown:SetScale(0.94)

    UIDropDownMenu_SetWidth(dropdown, dropDownWidth or 176)
    UIDropDownMenu_SetText(dropdown, "<Unassign>")
    SkinDropDownDark(dropdown, dropDownWidth or 176, 32)

    column._label = label
    column._dd = dropdown
    column._buffKey = buffKey

    dropdown._column = column
    dropDownsByBuff[buffKey] = dropdown

    return column
end

local function LayoutColumns(columns, parent, startX, startY, gapX)
    local previousColumn = nil

    for i = 1, #columns do
        local column = columns[i]
        column:ClearAllPoints()

        if not previousColumn then
            column:SetPoint("TOPLEFT", parent, "TOPLEFT", startX, startY)
        else
            column:SetPoint("LEFT", previousColumn, "RIGHT", gapX, 0)
        end

        previousColumn = column
    end
end

local function ReflowVisibleColumns(columnsByKey, parent)
    local visibleColumns = {}

    for i = 1, #CurrentState.activeBuffs do
        local buffKey = CurrentState.activeBuffs[i]
        local column = columnsByKey[buffKey]

        if column then
            visibleColumns[#visibleColumns + 1] = column
            column:Show()
        end
    end

    local columnsPerRow = 2
    local columnWidth = 185
    local rowHeight = 78
    local gapX = 12
    local gapY = -12

    for i = 1, #visibleColumns do
        local column = visibleColumns[i]
        local rowIndex = math.floor((i - 1) / columnsPerRow)
        local colIndex = (i - 1) % columnsPerRow

        column:ClearAllPoints()
        column:SetPoint(
            "TOPLEFT",
            parent,
            "TOPLEFT",
            (colIndex * (columnWidth + gapX)),
            -(rowIndex * (rowHeight + gapY))
        )
    end

    for i = 1, #BUFF_ORDER do
        local buffKey = BUFF_ORDER[i]
        local column = columnsByKey[buffKey]

        if column and not IsBuffActive(buffKey) then
            column:Hide()
        end
    end
end

local function UpdateColumnsContainerHeight(parent)
    local visibleCount = #CurrentState.activeBuffs
    local columnsPerRow = 2
    local rowHeight = 78
    local gapY = 4

    local rowCount = math.ceil(visibleCount / columnsPerRow)
    local totalHeight = rowCount * rowHeight

    if rowCount > 1 then
        totalHeight = totalHeight + ((rowCount - 1) * gapY)
    end

    if totalHeight < rowHeight then
        totalHeight = rowHeight
    end

    parent:SetHeight(totalHeight)
end

-- =========================
-- DROPDOWN / BUTTON REFRESH
-- =========================

local function UpdateDropDownLabel(buffKey)
    local dropdown = dropDownsByBuff[buffKey]

    if not dropdown then
        return
    end

    local selectedName = GetSelectedPaladinForBuff(buffKey)

    if not selectedName then
        UIDropDownMenu_SetText(dropdown, "<Unassign>")
        UIDropDownMenu_SetSelectedValue(dropdown, nil)
        return
    end

    UIDropDownMenu_SetText(dropdown, selectedName)
    UIDropDownMenu_SetSelectedValue(dropdown, selectedName)
end

local function UpdateSendButtonState()
    local hasPaladins = (#CurrentState.paladins > 0)
    local isRaidGroup = false

    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        isRaidGroup = true
    end

    if whisperButton then
        if hasPaladins then
            whisperButton:Enable()
        else
            whisperButton:Disable()
        end
    end

    if raidButton then
        if hasPaladins and isRaidGroup then
            raidButton:Enable()
        else
            raidButton:Disable()
        end
    end
end

local function RefreshBuffDropdowns()
    for i = 1, #BUFF_ORDER do
        local buffKey = BUFF_ORDER[i]
        local dropdown = dropDownsByBuff[buffKey]

        if dropdown then
            UIDropDownMenu_Initialize(dropdown, function(self, level)
                local options = BuildDropDownOptionsForBuff(buffKey)
                local selectedValue = GetSelectedPaladinForBuff(buffKey)

                local unassignInfo = UIDropDownMenu_CreateInfo()
                unassignInfo.text = "<Unassign>"
                unassignInfo.value = nil
                unassignInfo.checked = (selectedValue == nil)
                unassignInfo.func = function()
                    SetSelectedPaladinForBuff(buffKey, nil, true)
                    RefreshBuffDropdowns()
                    RenderPreview()
                    UpdateSendButtonState()
                end
                UIDropDownMenu_AddButton(unassignInfo, level)

                for j = 1, #options do
                    local option = options[j]
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = option.text
                    info.value = option.value
                    info.checked = (selectedValue == option.value)
                    info.func = function(buttonSelf)
                        SetSelectedPaladinForBuff(buffKey, buttonSelf.value, true)
                        RefreshBuffDropdowns()
                        RenderPreview()
                        UpdateSendButtonState()
                    end
                    UIDropDownMenu_AddButton(info, level)
                end
            end)

            UpdateDropDownLabel(buffKey)
            SkinDropDownDark(dropdown)
        end
    end
end

-- =========================
-- DATA / VISUAL REBUILD
-- =========================


local function BuildNameMap(paladins)
    local map = {}

    for i = 1, #paladins do
        local paladin = paladins[i]

        if paladin and paladin.name then
            map[paladin.name] = true
        end
    end

    return map
end

local function BuildActiveMap(activeBuffs)
    local map = {}

    for i = 1, #activeBuffs do
        map[activeBuffs[i]] = true
    end

    return map
end

local function GetNewPaladins(previousPaladins, currentPaladins)
    local previousMap = BuildNameMap(previousPaladins)
    local added = {}

    for i = 1, #currentPaladins do
        local paladin = currentPaladins[i]

        if paladin and paladin.name and not previousMap[paladin.name] then
            added[#added + 1] = paladin
        end
    end

    table.sort(added, CompareNameAsc)

    return added
end

local function GetPreviousAssignedBuffForName(previousSelected, paladinName, previousActiveBuffs)
    for i = 1, #previousActiveBuffs do
        local buffKey = previousActiveBuffs[i]

        if previousSelected[buffKey] == paladinName then
            return buffKey
        end
    end

    return nil
end

local function CopySelectedMap(selected)
    local copied = {}

    for i = 1, #BUFF_ORDER do
        local buffKey = BUFF_ORDER[i]
        copied[buffKey] = selected[buffKey]
    end

    return copied
end

local function HandleThreeToFourTransition(previousPaladins, previousActiveBuffs, currentPaladins, currentActiveBuffs, tank)
    if #previousPaladins ~= 3 then
        return
    end

    if #currentPaladins ~= 4 then
        return
    end

    local previousActiveMap = BuildActiveMap(previousActiveBuffs)
    local currentActiveMap = BuildActiveMap(currentActiveBuffs)

    if previousActiveMap.GBOS then
        return
    end

    if not currentActiveMap.GBOS then
        return
    end

    if not tank or not tank.name then
        return
    end

    local selected = PaladinBuffSessionState.selected
    local manual = PaladinBuffSessionState.manual
    local previousSelected = CopySelectedMap(selected)
    local newPaladins = GetNewPaladins(previousPaladins, currentPaladins)

    if #newPaladins ~= 1 then
        return
    end

    local newPaladinName = newPaladins[1].name
    local tankOldBuff = GetPreviousAssignedBuffForName(previousSelected, tank.name, previousActiveBuffs)

    if not tankOldBuff then
        return
    end

    if manual.GBOS or manual[tankOldBuff] then
        return
    end

    selected.GBOS = tank.name

    if tankOldBuff ~= "GBOS" then
        selected[tankOldBuff] = newPaladinName
    end
end

local function ResetInactiveOrMissingSelections(activeBuffs, paladins)
    local availableNames = {}
    local activeMap = {}

    for i = 1, #paladins do
        availableNames[paladins[i].name] = true
    end

    for i = 1, #activeBuffs do
        activeMap[activeBuffs[i]] = true
    end

    for i = 1, #BUFF_ORDER do
        local buffKey = BUFF_ORDER[i]
        local selectedName = PaladinBuffSessionState.selected[buffKey]

        if selectedName and (not availableNames[selectedName]) then
            PaladinBuffSessionState.selected[buffKey] = nil
            PaladinBuffSessionState.manual[buffKey] = false
        end

        if not activeMap[buffKey] then
            PaladinBuffSessionState.selected[buffKey] = nil
            PaladinBuffSessionState.manual[buffKey] = false
        end
    end
end

local function RebuildDataState(keepSessionSelections)
    local previousPaladins = CurrentState.paladins and CopyList(CurrentState.paladins) or {}
    local previousActiveBuffs = CurrentState.activeBuffs and CopyList(CurrentState.activeBuffs) or {}

    CurrentState.paladins = GetGroupPaladins()
    PaladinBuffSessionState.lastRosterSig = BuildRosterSignature(CurrentState.paladins)

    CurrentState.rolesByName,
    CurrentState.tankCandidates,
    CurrentState.healCandidates,
    CurrentState.tank,
    CurrentState.holy,
    CurrentState.ret,
    CurrentState.hpThreshold,
    CurrentState.manaThreshold = ComputeHeuristicRoles(CurrentState.paladins)

    local hasTankCandidates = CurrentState.tankCandidates and (#CurrentState.tankCandidates > 0)
    CurrentState.activeBuffs = BuildActiveBuffList(#CurrentState.paladins, hasTankCandidates)

    if not keepSessionSelections then
        for i = 1, #BUFF_ORDER do
            local buffKey = BUFF_ORDER[i]
            PaladinBuffSessionState.selected[buffKey] = nil
            PaladinBuffSessionState.manual[buffKey] = false
        end
    end

    ResetInactiveOrMissingSelections(CurrentState.activeBuffs, CurrentState.paladins)

    HandleThreeToFourTransition(
        previousPaladins,
        previousActiveBuffs,
        CurrentState.paladins,
        CurrentState.activeBuffs,
        CurrentState.tank
    )

    AutoAssignDefaults(
        CurrentState.paladins,
        CurrentState.tankCandidates,
        CurrentState.tank,
        CurrentState.holy,
        CurrentState.ret,
        CurrentState.activeBuffs
    )
end

local function RefreshColumns(columnsByKey)
    if not columnsByKey then
        return
    end

    for i = 1, #BUFF_ORDER do
        local buffKey = BUFF_ORDER[i]
        local column = columnsByKey[buffKey]

        if column then
            if IsBuffActive(buffKey) then
                column:Show()
            else
                column:Hide()
            end
        end
    end

    if columnsAnchorRef then
        ReflowVisibleColumns(columnsByKey, columnsAnchorRef)
        UpdateColumnsContainerHeight(columnsAnchorRef)
    end
end

local function RefreshVisualState(columnsByKey)
    RefreshColumns(columnsByKey)
    RefreshBuffDropdowns()
    RenderPreview()
    UpdateSendButtonState()
end

local function RebuildDataAndUI(keepSessionSelections, columnsByKey)
    RebuildDataState(keepSessionSelections)
    RefreshVisualState(columnsByKey)
end

local function ApplyThresholdEditsAndRefresh(columnsByKey)
    local hpThreshold = DEFAULTS.tankHpThreshold
    local manaThreshold = DEFAULTS.healManaThreshold

    if hpEditBox then
        hpThreshold = ToSafeNumber(tonumber(hpEditBox:GetText()))
    end

    if manaEditBox then
        manaThreshold = ToSafeNumber(tonumber(manaEditBox:GetText()))
    end

    if hpThreshold <= 0 then
        hpThreshold = DEFAULTS.tankHpThreshold
    end

    if manaThreshold <= 0 then
        manaThreshold = DEFAULTS.healManaThreshold
    end

    PaladinBuffSessionState.baseHpThreshold = hpThreshold
    PaladinBuffSessionState.baseManaThreshold = manaThreshold

    RebuildDataAndUI(true, columnsByKey)
end

local function ThrottledRebuild(columnsByKey)
    local now = GetTime()

    if (now - lastRebuildAt) < REBUILD_THROTTLE_SECONDS then
        return
    end

    lastRebuildAt = now
    ApplyThresholdEditsAndRefresh(columnsByKey)
end

local function ScheduleDelayedRebuild(columnsByKey, delaySeconds)
    if pendingDelayedRebuild then
        return
    end

    pendingDelayedRebuild = true

    local delayFrame = CreateFrame("Frame")
    local elapsedTotal = 0

    delayFrame:SetScript("OnUpdate", function(self, elapsed)
        elapsedTotal = elapsedTotal + elapsed

        if elapsedTotal >= (delaySeconds or 0.8) then
            pendingDelayedRebuild = false
            self:SetScript("OnUpdate", nil)
            ApplyThresholdEditsAndRefresh(columnsByKey)
        end
    end)
end

-- =========================
-- EVENTS
-- =========================

local function EnsureRosterEventFrame(columnsByKey)
    activeColumnsByKey = columnsByKey

    if rosterEventFrame then
        return
    end

    rosterEventFrame = CreateFrame("Frame")
    rosterEventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    rosterEventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
    rosterEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    rosterEventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    rosterEventFrame:RegisterEvent("UNIT_MAXHEALTH")
    rosterEventFrame:RegisterEvent("UNIT_DISPLAYPOWER")
    rosterEventFrame:RegisterEvent("UNIT_NAME_UPDATE")

    if rosterEventFrame.RegisterEvent and UnitPowerMax then
        pcall(function()
            rosterEventFrame:RegisterEvent("UNIT_MAXPOWER")
        end)
    end

    rosterEventFrame:SetScript("OnEvent", function(self, event, unitID)
        if not activeColumnsByKey then
            return
        end

        if event == "UNIT_MAXHEALTH"
            or event == "UNIT_DISPLAYPOWER"
            or event == "UNIT_NAME_UPDATE"
            or event == "UNIT_MAXPOWER" then
            if not unitID then
                return
            end

            if string.sub(unitID, 1, 4) ~= "raid"
                and string.sub(unitID, 1, 5) ~= "party"
                and unitID ~= "player" then
                return
            end
        end

        ThrottledRebuild(activeColumnsByKey)

        if event == "GROUP_ROSTER_UPDATE"
            or event == "RAID_ROSTER_UPDATE"
            or event == "PLAYER_ENTERING_WORLD" then
            ScheduleDelayedRebuild(activeColumnsByKey, 0.8)
        end
    end)
end


local function SkinFrameTransparentIfPossible(frame)
    if not frame then
        return
    end

    if frame.SetTemplate then
        frame:SetTemplate("Transparent")
    end
end

local function SkinCheckBoxIfPossible(s, checkBox)
    if not s or not checkBox then
        return
    end

    if s.HandleCheckBox then
        s:HandleCheckBox(checkBox)
    end
end

local function SkinButtonIfPossible(s, button)
    if not s or not button then
        return
    end

    if s.HandleButton then
        s:HandleButton(button)
    end
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

local function SkinDropDownIfPossible(s, dropdown)
    if not s or not dropdown then
        return
    end

    if s.HandleDropDownBox then
        s:HandleDropDownBox(dropdown)
        return
    end

    if not dropdown.GetName then
        return
    end

    local dropDownName = dropdown:GetName()

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

local function SkinThresholdHolderIfPossible(holder)
    if not holder then
        return
    end

    SkinFrameTransparentIfPossible(holder)
    SkinFrameTransparentIfPossible(holder._background)
end

local function SkinPaladinBuffControlsWithElvUI(dropDownMap, hpHolder, hpBox, manaHolder, manaBox, whisperActionButton, raidActionButton, previewFrame, backupsCheckBox)
    local e = nil
    local s = nil

    if TryGetElvUISkinModule then
        e, s = TryGetElvUISkinModule()
    end

    if hpHolder and hpHolder._background then
        ApplyDarkBoxStyle(hpHolder._background)
    end

    if manaHolder and manaHolder._background then
        ApplyDarkBoxStyle(manaHolder._background)
    end

    if previewFrame then
        ApplyDarkBoxStyle(previewFrame)
    end

    if hpBox and hpBox.SetTextColor then
        hpBox:SetTextColor(LIGHT_BOX_TEXT_RED, LIGHT_BOX_TEXT_GREEN, LIGHT_BOX_TEXT_BLUE)
    end

    if manaBox and manaBox.SetTextColor then
        manaBox:SetTextColor(LIGHT_BOX_TEXT_RED, LIGHT_BOX_TEXT_GREEN, LIGHT_BOX_TEXT_BLUE)
    end

    if dropDownMap then
        for _, dropdown in pairs(dropDownMap) do
            SkinDropDownDark(dropdown)
        end
    end

    if not e or not s then
        return false
    end

    SkinButtonIfPossible(s, whisperActionButton)
    SkinButtonIfPossible(s, raidActionButton)
    SkinCheckBoxIfPossible(s, backupsCheckBox)

    return true
end

-- =========================
-- TAB CONTENT
-- =========================

function CreatePaladinBuffsTabContent(parent, onClose)
    tabFrame = CreateFrame("Frame", nil, parent)
    tabFrame:SetAllPoints()

    local topInset = 18
    local sideInset = 18
    local panelWidth = 350

    local thresholdHeaderRow = CreateFrame("Frame", nil, tabFrame)
    thresholdHeaderRow:SetPoint("TOPLEFT", sideInset, -topInset)
    thresholdHeaderRow:SetPoint("TOPRIGHT", -sideInset, -topInset)
    thresholdHeaderRow:SetHeight(20)

    local hpLabel = CreateSectionTitle(thresholdHeaderRow, "HP Threshold", "TOPLEFT", thresholdHeaderRow, "TOPLEFT", 0, 0, "LEFT")
    local manaLabel = CreateSectionTitle(thresholdHeaderRow, "Mana Threshold", "TOPRIGHT", thresholdHeaderRow, "TOPRIGHT", 0, 0, "RIGHT")

    local thresholdInputRow = CreateFrame("Frame", nil, tabFrame)
    thresholdInputRow:SetPoint("TOPLEFT", thresholdHeaderRow, "BOTTOMLEFT", 0, -8)
    thresholdInputRow:SetPoint("TOPRIGHT", thresholdHeaderRow, "BOTTOMRIGHT", 0, -8)
    thresholdInputRow:SetHeight(30)

    local createdHpHolder, createdHpEditBox = CreateThresholdEdit(thresholdInputRow, PaladinBuffSessionState.baseHpThreshold, 140)
    createdHpHolder:SetPoint("LEFT", 0, 0)
    hpInputHolder = createdHpHolder
    hpEditBox = createdHpEditBox

    local createdManaHolder, createdManaEditBox = CreateThresholdEdit(thresholdInputRow, PaladinBuffSessionState.baseManaThreshold, 140)
    createdManaHolder:SetPoint("RIGHT", 0, 0)
    manaInputHolder = createdManaHolder
    manaEditBox = createdManaEditBox

    local heuristicTitle = CreateSectionTitle(tabFrame, "Heuristic Roles", "TOPLEFT", thresholdInputRow, "BOTTOMLEFT", 0, -18, "LEFT")

    announceBackupsCheckBox = CreateFrame("CheckButton", "PaladinBuffsAnnounceBackupsCheckBox", tabFrame, "UICheckButtonTemplate")
    announceBackupsCheckBox:ClearAllPoints()
    announceBackupsCheckBox:SetPoint("RIGHT", tabFrame, "TOPRIGHT", -12, -100)
    announceBackupsCheckBox:SetChecked(PaladinBuffSessionState.announceBackups and true or false)
    announceBackupsCheckBox:SetScript("OnClick", function(self)
        PaladinBuffSessionState.announceBackups = self:GetChecked() and true or false
    end)
    

    announceBackupsLabel = tabFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    announceBackupsLabel:SetPoint("RIGHT", announceBackupsCheckBox, "LEFT", -4, 0)
    announceBackupsLabel:SetText("Announce Backups")
    announceBackupsLabel:SetTextColor(0.95, 0.95, 0.95)

    previewPanel = CreateFrame("Frame", nil, tabFrame)
    previewPanel:SetPoint("TOPLEFT", heuristicTitle, "BOTTOMLEFT", 0, -8)
    previewPanel:SetPoint("TOPRIGHT", tabFrame, "TOPRIGHT", -sideInset, 0)
    previewPanel:SetHeight(20 + (PREVIEW_MAX_VISIBLE_PALADINS * PREVIEW_LINE_HEIGHT))

    ApplyDarkBoxStyle(previewPanel)

    previewContent = CreateFrame("Frame", nil, previewPanel)
    previewContent:SetPoint("TOPLEFT", 0, 0)
    previewContent:SetPoint("TOPRIGHT", 0, 0)
    previewContent:SetHeight(1)

    local buffOrderTitle = CreateSectionTitle(tabFrame, "Buff Order", "TOPLEFT", previewPanel, "BOTTOMLEFT", 0, -18, "LEFT")

    columnsAnchorRef = CreateFrame("Frame", nil, tabFrame)
    columnsAnchorRef:SetPoint("TOPLEFT", buffOrderTitle, "BOTTOMLEFT", 0, -8)
    columnsAnchorRef:SetPoint("RIGHT", tabFrame, "RIGHT", -sideInset, 0)
    columnsAnchorRef:SetHeight(260)

    dropDownsByBuff = {}

    local columnsByKey = {}
    columnsByKey.GBOS = CreateBuffColumn(columnsAnchorRef, "GBOS", BUFF_META.GBOS.title, 160)
    columnsByKey.GBOK = CreateBuffColumn(columnsAnchorRef, "GBOK", BUFF_META.GBOK.title, 160)
    columnsByKey.GBOM = CreateBuffColumn(columnsAnchorRef, "GBOM", BUFF_META.GBOM.title, 160)
    columnsByKey.GBOW = CreateBuffColumn(columnsAnchorRef, "GBOW", BUFF_META.GBOW.title, 160)
    columnsByKey.CLASS = CreateBuffColumn(columnsAnchorRef, "CLASS", BUFF_META.CLASS.title, 160)

    activeColumnsByKey = columnsByKey

    local actionsRow = CreateFrame("Frame", nil, tabFrame)
    actionsRow:SetPoint("TOPLEFT", columnsAnchorRef, "BOTTOMLEFT", 0, -8)
    actionsRow:SetPoint("TOPRIGHT", columnsAnchorRef, "BOTTOMRIGHT", 0, -8)
    actionsRow:SetHeight(24)

    whisperButton = CreateActionButton(actionsRow, "PaladinBuffsWhisperButton", "Whisper Paladins", 170, 26)
    whisperButton:ClearAllPoints()
    whisperButton:SetPoint("BOTTOMLEFT", tabFrame, "BOTTOMLEFT", 12, 12)


    raidButton = CreateActionButton(actionsRow, "PaladinBuffsRaidButton", "Announce in Raid Chat", 190, 26)
    raidButton:ClearAllPoints()
    raidButton:SetPoint("BOTTOMRIGHT", tabFrame, "BOTTOMRIGHT", -12, 12)

    hpEditBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        ApplyThresholdEditsAndRefresh(columnsByKey)
    end)

    manaEditBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        ApplyThresholdEditsAndRefresh(columnsByKey)
    end)

    hpEditBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then
            return
        end

        ThrottledRebuild(columnsByKey)
    end)

    manaEditBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then
            return
        end

        ThrottledRebuild(columnsByKey)
    end)

    whisperButton:SetScript("OnClick", function()
        SendAssignmentWhispers()
        UpdateSendButtonState()
    end)

    raidButton:SetScript("OnClick", function()
        SendRaidAnnouncement()
        UpdateSendButtonState()
    end)

    if TT_SkinPaladinBuffInputsWithElvUIIfAvailable then
        TT_SkinPaladinBuffInputsWithElvUIIfAvailable(
            dropDownsByBuff,
            hpEditBox,
            manaEditBox,
            whisperButton,
            raidButton,
            previewPanel
        )

        if TT_SkinCheckBoxWithElvUIIfAvailable then
            TT_SkinCheckBoxWithElvUIIfAvailable(announceBackupsCheckBox)
        elseif TryGetElvUISkinModule then
            local _, skinModule = TryGetElvUISkinModule()

            if skinModule and skinModule.HandleCheckBox then
                skinModule:HandleCheckBox(announceBackupsCheckBox)
            end
        end
    else
        SkinPaladinBuffControlsWithElvUI(
            dropDownsByBuff,
            hpInputHolder,
            hpEditBox,
            manaInputHolder,
            manaEditBox,
            whisperButton,
            raidButton,
            previewPanel,
            announceBackupsCheckBox
        )
    end

    RebuildDataAndUI(true, columnsByKey)
    EnsureRosterEventFrame(columnsByKey)

    return tabFrame
end

function RefreshPaladinBuffsPreview()
    if hpEditBox and hpEditBox.GetText then
        local hpValue = tonumber(hpEditBox:GetText())

        if hpValue and hpValue > 0 then
            PaladinBuffSessionState.baseHpThreshold = hpValue
        end
    end

    if manaEditBox and manaEditBox.GetText then
        local manaValue = tonumber(manaEditBox:GetText())

        if manaValue and manaValue > 0 then
            PaladinBuffSessionState.baseManaThreshold = manaValue
        end
    end

    local columnsByKey = {}

    for i = 1, #BUFF_ORDER do
        local buffKey = BUFF_ORDER[i]
        local dropdown = dropDownsByBuff[buffKey]

        if dropdown and dropdown._column then
            columnsByKey[buffKey] = dropdown._column
        end
    end

    RebuildDataAndUI(true, columnsByKey)
end


function TT_SkinCheckBoxWithElvUIIfAvailable(checkBox)
    local e = nil
    local s = nil

    if TryGetElvUISkinModule then
        e, s = TryGetElvUISkinModule()
    end

    if not e or not s or not checkBox then
        return false
    end

    SkinCheckBoxIfPossible(s, checkBox)
    return true
end
