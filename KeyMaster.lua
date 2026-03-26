local addonName = ...

local floor = math.floor
local max = math.max
local min = math.min
local strfind = string.find
local strlower = string.lower
local strmatch = string.match
local strtrim = strtrim
local tonumber = tonumber
local unpack = unpack or table.unpack

local frame = CreateFrame("Frame")
local REPLY_PREFIX = "KeyMaster:"
local KEYSTONE_ITEM_IDS = { [180653] = true, [158923] = true, [151086] = true }
local KEYSTONE_BAG_SLOTS = { Enum.BagIndex.Backpack, Enum.BagIndex.Bag_1, Enum.BagIndex.Bag_2, Enum.BagIndex.Bag_3, Enum.BagIndex.Bag_4 }
local KEYS_TEXT_COMMAND = "!keys"
local KEY_TEXT_COMMAND = "!key"
local SCORE_TEXT_COMMAND = "!score"
local BEST_TEXT_COMMAND = "!best"
local MISMATCH_TOAST_COOLDOWN_SECONDS = 2
local UI_REFRESH_INTERVAL_SECONDS = 0.2
local CHALLENGERS_PERIL_AFFIX_ID = 152
local BREAK_TIMER_BLUE = { 0.15, 0.55, 1.00, 0.90 }
local DEFAULT_DB = {
    ui = {
        enabled = true,
        locked = true,
        hidden = false,
        scale = 1,
        point = { "TOPRIGHT", "UIParent", "TOPRIGHT", -24, -210 },
    },
}

local lastMismatchToastAt = 0
local ui = {
    objectiveLines = {},
    lastRefreshAt = 0,
    challengesFrameHooked = false,
    trackerSuppressed = false,
}

local CHAT_EVENTS = {
    CHAT_MSG_PARTY = true,
    CHAT_MSG_RAID = true,
    CHAT_MSG_GUILD = true,
}

local CHAT_EVENT_TO_CHANNEL = {
    CHAT_MSG_PARTY = "PARTY",
    CHAT_MSG_RAID = "RAID",
    CHAT_MSG_GUILD = "GUILD",
}

local function CopyDefaults(source, destination)
    if type(destination) ~= "table" then
        destination = {}
    end

    for key, value in pairs(source) do
        if type(value) == "table" then
            destination[key] = CopyDefaults(value, destination[key])
        elseif destination[key] == nil then
            destination[key] = value
        end
    end

    return destination
end

local function InitializeDatabase()
    if type(KeyMasterDB) ~= "table" then
        KeyMasterDB = {}
    end

    KeyMasterDB = CopyDefaults(DEFAULT_DB, KeyMasterDB)

    if type(KeyMasterDB.ui) ~= "table" then
        KeyMasterDB.ui = CopyDefaults(DEFAULT_DB.ui, {})
    end

    if type(KeyMasterDB.ui.point) ~= "table" or #KeyMasterDB.ui.point < 5 then
        KeyMasterDB.ui.point = CopyDefaults(DEFAULT_DB.ui.point, {})
    end

    if type(KeyMasterDB.ui.scale) ~= "number" or KeyMasterDB.ui.scale <= 0 then
        KeyMasterDB.ui.scale = DEFAULT_DB.ui.scale
    end

    if type(KeyMasterDB.ui.enabled) ~= "boolean" then
        KeyMasterDB.ui.enabled = DEFAULT_DB.ui.enabled
    end

    if type(KeyMasterDB.ui.locked) ~= "boolean" then
        KeyMasterDB.ui.locked = DEFAULT_DB.ui.locked
    end

    if type(KeyMasterDB.ui.hidden) ~= "boolean" then
        KeyMasterDB.ui.hidden = DEFAULT_DB.ui.hidden
    end

    return KeyMasterDB
end

local function GetOwnedKeystoneLevel()
    if C_MythicPlus and C_MythicPlus.GetOwnedKeystoneLevel then
        return C_MythicPlus.GetOwnedKeystoneLevel()
    end

    if C_ChallengeMode and C_ChallengeMode.GetOwnedKeystoneLevel then
        return C_ChallengeMode.GetOwnedKeystoneLevel()
    end

    return nil
end

local function GetOwnedKeystoneMapID()
    if C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID then
        return C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    end

    if C_MythicPlus and C_MythicPlus.GetOwnedKeystoneMapID then
        return C_MythicPlus.GetOwnedKeystoneMapID()
    end

    if C_ChallengeMode and C_ChallengeMode.GetOwnedKeystoneChallengeMapID then
        return C_ChallengeMode.GetOwnedKeystoneChallengeMapID()
    end

    return nil
end

local function FindKeystoneItemLocation()
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemID) then
        return nil
    end

    for _, bagID in ipairs(KEYSTONE_BAG_SLOTS) do
        local slotCount = C_Container.GetContainerNumSlots(bagID) or 0
        for slotIndex = 1, slotCount do
            if KEYSTONE_ITEM_IDS[C_Container.GetContainerItemID(bagID, slotIndex)] then
                return ItemLocation:CreateFromBagAndSlot(bagID, slotIndex)
            end
        end
    end

    return nil
end

local function GetKeystoneMapName(mapID)
    if not mapID then
        return nil
    end

    if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        local name = C_ChallengeMode.GetMapUIInfo(mapID)
        if type(name) == "string" and name ~= "" then
            return name
        end
    end

    return nil
end

local function GetChallengeMapTimeLimit(mapID)
    if not (mapID and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo) then
        return nil
    end

    local ok, _, _, timeLimit = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
    if ok and type(timeLimit) == "number" and timeLimit > 0 then
        return timeLimit
    end

    return nil
end

local function FormatDungeonLabel(mapID)
    if not mapID then
        return "Unknown"
    end

    local name = GetKeystoneMapName(mapID)
    if name and name ~= "" then
        return name
    end

    return string.format("Map %d", mapID)
end

local function FormatSeconds(seconds)
    if type(seconds) ~= "number" then
        seconds = 0
    end

    seconds = max(0, floor(seconds + 0.5))

    local minutes = floor(seconds / 60)
    local remainder = seconds % 60

    return string.format("%02d:%02d", minutes, remainder)
end

local function ParsePercentValue(text)
    if type(text) ~= "string" then
        return nil
    end

    local percentText = strmatch(text, "(%d+%.?%d*)%%")
    if percentText then
        return tonumber(percentText)
    end

    return nil
end

local function ShowLocalToast(message)
    if not message or message == "" then
        return
    end

    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(message, 1.0, 0.1, 0.1, 1.0)
    end
end

local function PrintLocal(message)
    if not message or message == "" then
        return
    end

    print(string.format("%s %s", REPLY_PREFIX, message))
end

local function ShowMismatchToast(ownedMapID, receptacleMapID)
    local now = GetTime()
    if (now - lastMismatchToastAt) < MISMATCH_TOAST_COOLDOWN_SECONDS then
        return
    end

    lastMismatchToastAt = now

    local ownedName = FormatDungeonLabel(ownedMapID)
    local receptacleName = FormatDungeonLabel(receptacleMapID)
    local message = string.format("Key mismatch (%s vs %s)", ownedName, receptacleName)
    ShowLocalToast(string.format("%s %s", REPLY_PREFIX, message))
end

local function GetOwnedKeystoneLink()
    if C_MythicPlus and C_MythicPlus.GetOwnedKeystoneLink then
        local link = C_MythicPlus.GetOwnedKeystoneLink()
        if link then
            return link
        end
    end

    local itemLocation = FindKeystoneItemLocation()
    if itemLocation and C_Item and C_Item.GetItemLink then
        local link = C_Item.GetItemLink(itemLocation)
        if link then
            return link
        end
    end

    local mapID = GetOwnedKeystoneMapID()
    local keyLevel = GetOwnedKeystoneLevel()
    local mapName = GetKeystoneMapName(mapID)
    if not mapID or not keyLevel or not mapName or mapName == "" then
        return nil
    end

    local linkText = string.format("[Keystone: %s (%d)]", mapName, keyLevel)

    return string.format(
        "|cffa335ee|Hkeystone:%d:%d:%d:%d:%d:%d:%d:%d|h%s|h|r",
        180653,
        mapID,
        keyLevel,
        0,
        0,
        0,
        0,
        0,
        linkText
    )
end

local function BuildKeystoneReply()
    local keyLink = GetOwnedKeystoneLink()
    if keyLink then
        return string.format("%s %s", REPLY_PREFIX, keyLink)
    end

    return nil
end

local function GetMythicPlusScore()
    if C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore then
        local score = C_ChallengeMode.GetOverallDungeonScore()
        if type(score) == "number" and score >= 0 then
            return score
        end
    end

    if C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
        local ok, summary = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary)
        if ok and type(summary) == "table" then
            local score = summary.currentSeasonScore or summary.overallScore or summary.score
            if type(score) == "number" and score >= 0 then
                return score
            end
        end
    end

    return nil
end

local function BuildScoreReply()
    local score = GetMythicPlusScore()
    if not score then
        return nil
    end

    return string.format("%s M+ Score: %d", REPLY_PREFIX, floor(score + 0.5))
end

local function ResolveBestLevel(result1, result2)
    local level

    if type(result1) == "number" then
        level = result1
    elseif type(result1) == "table" then
        level = result1.level or result1.bestRunLevel or result1.completedLevel or result1.keystoneLevel
    elseif type(result2) == "number" then
        level = result2
    end

    if type(level) == "number" and level >= 2 and level <= 40 then
        return level
    end

    return nil
end

local function GetBestRunFromMapLookup(funcName)
    if not (C_MythicPlus and C_MythicPlus[funcName] and C_ChallengeMode and C_ChallengeMode.GetMapTable) then
        return nil
    end

    local maps = C_ChallengeMode.GetMapTable()
    if type(maps) ~= "table" then
        return nil
    end

    local best

    for _, mapID in ipairs(maps) do
        local ok, result1, result2 = pcall(C_MythicPlus[funcName], mapID)
        if ok then
            local level = ResolveBestLevel(result1, result2)
            if type(level) == "number" and level > 0 then
                if not best or level > best.level then
                    best = { level = level, mapID = mapID }
                end
            end
        end
    end

    return best
end

local function GetBestRunsFromHistory()
    if not (C_MythicPlus and C_MythicPlus.GetRunHistory) then
        return nil, nil
    end

    local ok, history = pcall(C_MythicPlus.GetRunHistory)
    if not ok or type(history) ~= "table" then
        return nil, nil
    end

    local weekBest
    local seasonBest

    for _, run in ipairs(history) do
        if run and run.completed ~= false then
            local level = run.level or run.bestRunLevel or run.keystoneLevel or run.completedLevel
            local mapID = run.mapChallengeModeID or run.mapID or run.challengeMapID
            if type(level) == "number" and level > 0 and type(mapID) == "number" and mapID > 0 then
                if not seasonBest or level > seasonBest.level then
                    seasonBest = { level = level, mapID = mapID }
                end

                if run.thisWeek == true or run.currentWeek == true then
                    if not weekBest or level > weekBest.level then
                        weekBest = { level = level, mapID = mapID }
                    end
                end
            end
        end
    end

    return weekBest, seasonBest
end

local function FormatBestRun(bestRun)
    if not bestRun then
        return "None"
    end

    return string.format("+%d %s", bestRun.level, FormatDungeonLabel(bestRun.mapID))
end

local function BuildBestReply()
    local weekBest, seasonBest = GetBestRunsFromHistory()

    if not weekBest or not seasonBest then
        local mapWeekBest = GetBestRunFromMapLookup("GetWeeklyBestForMap")
        local mapSeasonBest = GetBestRunFromMapLookup("GetSeasonBestForMap")
        weekBest = weekBest or mapWeekBest
        seasonBest = seasonBest or mapSeasonBest
    end

    if not weekBest and not seasonBest then
        return nil
    end

    return string.format(
        "%s Best - Week: %s / Season: %s",
        REPLY_PREFIX,
        FormatBestRun(weekBest),
        FormatBestRun(seasonBest)
    )
end

local function IsKeyRequestMessage(message)
    if not message then
        return false
    end

    local msg = strtrim(strlower(message))
    return msg == KEY_TEXT_COMMAND
        or msg == KEYS_TEXT_COMMAND
        or msg == SCORE_TEXT_COMMAND
        or msg == BEST_TEXT_COMMAND
end

local function BuildReplyForCommand(message)
    local msg = strtrim(strlower(message or ""))

    if msg == KEY_TEXT_COMMAND or msg == KEYS_TEXT_COMMAND then
        return BuildKeystoneReply()
    end

    if msg == SCORE_TEXT_COMMAND then
        return BuildScoreReply()
    end

    if msg == BEST_TEXT_COMMAND then
        return BuildBestReply()
    end

    return nil
end

local function HandleChatMessage(event, message)
    if not CHAT_EVENTS[event] then
        return
    end

    if not IsKeyRequestMessage(message) then
        return
    end

    local reply = BuildReplyForCommand(message)
    if not reply then
        return
    end

    local chatType = CHAT_EVENT_TO_CHANNEL[event]
    if not chatType then
        return
    end

    pcall(SendChatMessage, reply, chatType)
end

local function NormalizeAffixIDs(...)
    local affixIDs = {}
    local seen = {}

    local function AddAffixID(value)
        if type(value) == "number" and value > 0 and not seen[value] then
            seen[value] = true
            table.insert(affixIDs, value)
        end
    end

    local function AddFromTable(value)
        if type(value) ~= "table" then
            return
        end

        for _, entry in ipairs(value) do
            if type(entry) == "table" then
                AddAffixID(entry.id or entry.affixID or entry.keystoneAffixID)
            else
                AddAffixID(entry)
            end
        end
    end

    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if type(value) == "table" then
            AddFromTable(value)
        else
            AddAffixID(value)
        end
    end

    return affixIDs
end

local function GetActiveKeystoneDetails()
    local level
    local affixIDs = {}

    if C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then
        local ok, result1, result2, result3, result4, result5 = pcall(C_ChallengeMode.GetActiveKeystoneInfo)
        if ok then
            if type(result1) == "number" then
                level = result1
            end

            affixIDs = NormalizeAffixIDs(result2, result3, result4, result5)
        end
    end

    if (#affixIDs == 0) and C_MythicPlus and C_MythicPlus.GetCurrentAffixes then
        local ok, currentAffixes = pcall(C_MythicPlus.GetCurrentAffixes)
        if ok and type(currentAffixes) == "table" then
            affixIDs = NormalizeAffixIDs(currentAffixes)
        end
    end

    if not level then
        level = GetOwnedKeystoneLevel()
    end

    return level, affixIDs
end

local function GetAffixSummary(affixIDs)
    if type(affixIDs) ~= "table" or #affixIDs == 0 then
        return nil
    end

    local names = {}

    if C_ChallengeMode and C_ChallengeMode.GetAffixInfo then
        for _, affixID in ipairs(affixIDs) do
            local name = C_ChallengeMode.GetAffixInfo(affixID)
            if type(name) == "string" and name ~= "" then
                table.insert(names, name)
            end
        end
    end

    if #names == 0 then
        return nil
    end

    return table.concat(names, " - ")
end

local function GetWorldElapsedSeconds()
    if not GetWorldElapsedTime then
        return nil
    end

    local _, elapsedSeconds = GetWorldElapsedTime(1)
    if type(elapsedSeconds) == "number" then
        return elapsedSeconds
    end

    local firstValue = GetWorldElapsedTime(1)
    if type(firstValue) == "number" then
        return firstValue
    end

    return nil
end

local function IsChallengeModeRunActive()
    if not (C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive()) then
        return false
    end

    local _, _, difficultyID = GetInstanceInfo()
    local elapsedSeconds = GetWorldElapsedSeconds()

    return difficultyID == 8 and type(elapsedSeconds) == "number" and elapsedSeconds >= 0
end

local function GetCriteriaCount()
    if C_Scenario and C_Scenario.GetStepInfo then
        local _, _, criteriaCount = C_Scenario.GetStepInfo()
        if type(criteriaCount) == "number" and criteriaCount > 0 then
            return criteriaCount
        end
    end

    return 0
end

local function NormalizeCriteriaInfo(index)
    if C_ScenarioInfo and C_ScenarioInfo.GetCriteriaInfo then
        local ok, info = pcall(C_ScenarioInfo.GetCriteriaInfo, index)
        if ok and type(info) == "table" then
            return {
                name = info.criteriaString or info.description or info.name or string.format("Objective %d", index),
                completed = info.completed == true,
                quantity = type(info.quantity) == "number" and info.quantity or 0,
                totalQuantity = type(info.totalQuantity) == "number" and info.totalQuantity or 0,
                quantityString = info.quantityString,
                isWeightedProgress = info.isWeightedProgress == true,
            }
        end
    end

    if C_Scenario and C_Scenario.GetCriteriaInfo then
        local ok, name, _, completed, quantity, totalQuantity, _, _, quantityString, _, _, _, _, isWeightedProgress = pcall(C_Scenario.GetCriteriaInfo, index)
        if ok then
            return {
                name = name or string.format("Objective %d", index),
                completed = completed == true,
                quantity = type(quantity) == "number" and quantity or 0,
                totalQuantity = type(totalQuantity) == "number" and totalQuantity or 0,
                quantityString = quantityString,
                isWeightedProgress = isWeightedProgress == true,
            }
        end
    end

    return nil
end

local function IsEnemyForcesCriteria(criteriaInfo)
    if not criteriaInfo then
        return false
    end

    if criteriaInfo.isWeightedProgress then
        return true
    end

    local name = strlower(criteriaInfo.name or "")
    return strfind(name, "enemy forces", 1, true) ~= nil
end

local function GetCriteriaState()
    local criteriaCount = GetCriteriaCount()
    local objectives = {}
    local enemyForces

    for index = 1, criteriaCount do
        local info = NormalizeCriteriaInfo(index)
        if info then
            if IsEnemyForcesCriteria(info) and not enemyForces then
                enemyForces = info
            else
                table.insert(objectives, info)
            end
        end
    end

    return objectives, enemyForces
end

local function CalculateEnemyForcesPercent(enemyInfo)
    if not enemyInfo then
        return nil
    end

    local percent = ParsePercentValue(enemyInfo.quantityString)
    if type(percent) == "number" then
        return min(100, max(0, percent))
    end

    if type(enemyInfo.quantity) == "number" and type(enemyInfo.totalQuantity) == "number" and enemyInfo.totalQuantity > 0 then
        return min(100, max(0, (enemyInfo.quantity / enemyInfo.totalQuantity) * 100))
    end

    return nil
end

local function BuildObjectiveText(criteriaInfo)
    if not criteriaInfo then
        return nil
    end

    if type(criteriaInfo.totalQuantity) == "number" and criteriaInfo.totalQuantity > 0 then
        local quantity = criteriaInfo.completed and criteriaInfo.totalQuantity or criteriaInfo.quantity or 0
        return string.format("- %d/%d %s", quantity, criteriaInfo.totalQuantity, criteriaInfo.name)
    end

    return string.format("- %s", criteriaInfo.name)
end

local function GetDeathState()
    if C_ChallengeMode and C_ChallengeMode.GetDeathCount then
        local ok, deathCount, deathPenalty = pcall(C_ChallengeMode.GetDeathCount)
        if ok then
            return deathCount or 0, deathPenalty or 0
        end
    end

    return 0, 0
end

local function CalculateChestTimerLimits(maxTimeSeconds, affixIDs)
    if type(maxTimeSeconds) ~= "number" or maxTimeSeconds <= 0 then
        return nil, nil
    end

    local twoChestLimit = maxTimeSeconds * 0.8
    local threeChestLimit = maxTimeSeconds * 0.6

    for _, affixID in ipairs(affixIDs or {}) do
        if affixID == CHALLENGERS_PERIL_AFFIX_ID then
            local timeWithoutPenaltyWindow = maxTimeSeconds - 90
            twoChestLimit = (timeWithoutPenaltyWindow * 0.8) + 90
            threeChestLimit = (timeWithoutPenaltyWindow * 0.6) + 90
            break
        end
    end

    return twoChestLimit, threeChestLimit
end

local function GetActiveRunState()
    if not IsChallengeModeRunActive() then
        return nil
    end

    local mapID = C_ChallengeMode.GetActiveChallengeMapID and C_ChallengeMode.GetActiveChallengeMapID() or GetOwnedKeystoneMapID()
    local mapName = GetKeystoneMapName(mapID)
    local maxTimeSeconds = GetChallengeMapTimeLimit(mapID)
    local elapsedSeconds = GetWorldElapsedSeconds() or 0
    local level, affixIDs = GetActiveKeystoneDetails()
    local objectives, enemyForces = GetCriteriaState()
    local deathCount, deathPenalty = GetDeathState()
    local _, _, _, _, _, _, _, instanceMapID = GetInstanceInfo()

    if (not mapName or mapName == "") and instanceMapID then
        mapName = FormatDungeonLabel(instanceMapID)
    end

    if not mapName or mapName == "" then
        local instanceName = GetInstanceInfo()
        if type(instanceName) == "string" and instanceName ~= "" then
            mapName = instanceName
        end
    end

    local twoChestLimit, threeChestLimit = CalculateChestTimerLimits(maxTimeSeconds, affixIDs)

    return {
        mapID = mapID,
        mapName = mapName or "Unknown",
        level = level,
        affixIDs = affixIDs,
        affixSummary = GetAffixSummary(affixIDs),
        elapsedSeconds = elapsedSeconds,
        maxTimeSeconds = maxTimeSeconds,
        timeLeftSeconds = maxTimeSeconds and max(0, maxTimeSeconds - elapsedSeconds) or nil,
        twoChestLimit = twoChestLimit,
        threeChestLimit = threeChestLimit,
        objectives = objectives,
        enemyForces = enemyForces,
        deathCount = deathCount,
        deathPenalty = deathPenalty,
    }
end

local function CreateLine(parent, fontHeight)
    local line = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    line:SetFont(STANDARD_TEXT_FONT, fontHeight, "")
    line:SetTextColor(1, 1, 1, 1)
    line:SetShadowColor(0, 0, 0, 0)
    line:SetShadowOffset(0, 0)
    line:SetJustifyH("LEFT")
    line:SetJustifyV("MIDDLE")
    return line
end

local function SaveMythicFramePoint()
    if not ui.frame then
        return
    end

    local point, relativeTo, relativePoint, xOffset, yOffset = ui.frame:GetPoint(1)
    local relativeName = (relativeTo and relativeTo.GetName and relativeTo:GetName()) or "UIParent"
    KeyMasterDB.ui.point = {
        point or "CENTER",
        relativeName,
        relativePoint or "CENTER",
        xOffset or 0,
        yOffset or 0,
    }
end

local function ApplyMythicFrameSettings()
    if not ui.frame then
        return
    end

    local settings = InitializeDatabase().ui
    local pointData = settings.point
    local relativeFrame = _G[pointData[2] or "UIParent"] or UIParent

    ui.frame:ClearAllPoints()
    ui.frame:SetPoint(pointData[1] or "CENTER", relativeFrame, pointData[3] or "CENTER", pointData[4] or 0, pointData[5] or 0)
    ui.frame:SetScale(settings.scale or 1)
    ui.frame:EnableMouse(not settings.locked)
    if not settings.locked then
        ui.dragLabel:SetText("KeyMaster (drag to move)")
    else
        ui.dragLabel:SetText("KeyMaster")
    end
    ui.dragLabel:SetShown(not settings.locked)
end

local function IsMythicUIEnabled()
    return InitializeDatabase().ui.enabled ~= false
end

local function SetMythicUIEnabled(isEnabled)
    InitializeDatabase().ui.enabled = isEnabled == true

    if ui.settingsCheckbox and ui.settingsCheckbox.SetChecked then
        ui.settingsCheckbox:SetChecked(IsMythicUIEnabled())
    end

    if ui.settingsUnlockButton then
        ui.settingsUnlockButton:SetEnabled(IsMythicUIEnabled())
    end

    if ui.settingsLockButton then
        ui.settingsLockButton:SetEnabled(IsMythicUIEnabled())
    end

    if not IsMythicUIEnabled() and ui.frame then
        ui.frame:Hide()
    end

    RefreshMythicUI()
end

local function EnsureHiddenTrackerFrame()
    if ui.hiddenTrackerFrame then
        return ui.hiddenTrackerFrame
    end

    ui.hiddenTrackerFrame = CreateFrame("Frame", nil, UIParent)
    ui.hiddenTrackerFrame:Hide()
    return ui.hiddenTrackerFrame
end

local function UpdateBlizzardTrackerVisibility(shouldSuppress)
    if not ObjectiveTrackerFrame then
        ui.trackerSuppressed = false
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        return
    end

    if UnitAffectingCombat and UnitAffectingCombat("player") then
        return
    end

    if shouldSuppress then
        local hiddenTrackerFrame = EnsureHiddenTrackerFrame()
        if ObjectiveTrackerFrame:GetParent() ~= hiddenTrackerFrame then
            ObjectiveTrackerFrame:SetParent(hiddenTrackerFrame)
        end
        hiddenTrackerFrame:Hide()
        ui.trackerSuppressed = true
        return
    end

    if ObjectiveTrackerFrame:GetParent() ~= UIParent then
        ObjectiveTrackerFrame:SetParent(UIParent)
    end

    ui.trackerSuppressed = false
end

local function SetMythicFrameLocked(isLocked)
    InitializeDatabase().ui.locked = isLocked == true
    ApplyMythicFrameSettings()
end

local function RegisterSettingsPanel()
    if ui.settingsRegistered then
        return
    end

    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
        return
    end

    local panel = CreateFrame("Frame", addonName .. "SettingsPanel", UIParent)
    panel.name = "KeyMaster"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("KeyMaster")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetWidth(560)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Choose whether KeyMaster uses its custom Mythic+ overlay or leaves Blizzard's default Mythic+ UI visible.")

    local checkbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    checkbox:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -2, -16)
    checkbox.Text:SetText("Use KeyMaster Mythic+ UI")
    checkbox.Text:SetWidth(260)
    checkbox:SetChecked(IsMythicUIEnabled())
    checkbox:SetScript("OnClick", function(self)
        SetMythicUIEnabled(self:GetChecked())
    end)

    local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", checkbox, "BOTTOMLEFT", 6, -6)
    description:SetWidth(560)
    description:SetJustifyH("LEFT")
    description:SetText("Disabled: KeyMaster keeps chat replies and Font of Power auto-slotting, but Blizzard's default Mythic+ UI remains active.")

    local positioning = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    positioning:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -14)
    positioning:SetWidth(560)
    positioning:SetJustifyH("LEFT")
    positioning:SetText("To position the overlay: use /km unlock, drag the frame where you want it, then use /km lock.")

    local unlockButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    unlockButton:SetSize(100, 24)
    unlockButton:SetPoint("TOPLEFT", positioning, "BOTTOMLEFT", 0, -12)
    unlockButton:SetText("Unlock UI")
    unlockButton:SetScript("OnClick", function()
        SetMythicFrameLocked(false)
        PrintLocal("UI unlocked; drag it to reposition, then lock it again when done")
    end)

    local lockButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    lockButton:SetSize(100, 24)
    lockButton:SetPoint("LEFT", unlockButton, "RIGHT", 8, 0)
    lockButton:SetText("Lock UI")
    lockButton:SetScript("OnClick", function()
        SetMythicFrameLocked(true)
        PrintLocal("UI locked")
    end)

    panel:SetScript("OnShow", function()
        checkbox:SetChecked(IsMythicUIEnabled())
        unlockButton:SetEnabled(IsMythicUIEnabled())
        lockButton:SetEnabled(IsMythicUIEnabled())
    end)

    local category = Settings.RegisterCanvasLayoutCategory(panel, "KeyMaster")
    Settings.RegisterAddOnCategory(category)

    ui.settingsPanel = panel
    ui.settingsCheckbox = checkbox
    ui.settingsUnlockButton = unlockButton
    ui.settingsLockButton = lockButton
    ui.settingsCategory = category
    ui.settingsRegistered = true
end

local function EnsureObjectiveLine(index)
    if ui.objectiveLines[index] then
        return ui.objectiveLines[index]
    end

    ui.objectiveLines[index] = CreateLine(ui.frame, 12)
    return ui.objectiveLines[index]
end

local function CreateMythicUI()
    if ui.frame then
        return
    end

    local mythicFrame = CreateFrame("Frame", "KeyMasterMythicFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate")
    mythicFrame:SetClampedToScreen(true)
    mythicFrame:SetMovable(true)
    mythicFrame:SetResizable(false)
    mythicFrame:EnableMouse(true)
    mythicFrame:RegisterForDrag("LeftButton")
    mythicFrame:SetScript("OnDragStart", function(self)
        if KeyMasterDB.ui.locked then
            return
        end

        self:StartMoving()
    end)
    mythicFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveMythicFramePoint()
    end)
    mythicFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false,
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    mythicFrame:SetBackdropColor(0, 0, 0, 0.55)
    mythicFrame:SetBackdropBorderColor(1, 1, 1, 0.12)
    mythicFrame:SetWidth(308)
    mythicFrame:SetHeight(160)
    mythicFrame:Hide()

    local accent = mythicFrame:CreateTexture(nil, "BORDER")
    accent:SetPoint("TOPLEFT", mythicFrame, "TOPLEFT", 1, -1)
    accent:SetPoint("TOPRIGHT", mythicFrame, "TOPRIGHT", -1, -1)
    accent:SetHeight(2)
    accent:SetColorTexture(BREAK_TIMER_BLUE[1], BREAK_TIMER_BLUE[2], BREAK_TIMER_BLUE[3], BREAK_TIMER_BLUE[4])

    ui.frame = mythicFrame
    ui.headerLine = CreateLine(mythicFrame, 15)
    ui.affixesLine = CreateLine(mythicFrame, 12)
    ui.timerLine = CreateLine(mythicFrame, 16)
    ui.twoChestLine = CreateLine(mythicFrame, 12)
    ui.threeChestLine = CreateLine(mythicFrame, 12)
    ui.deathLine = CreateLine(mythicFrame, 12)

    ui.dragLabel = CreateLine(mythicFrame, 11)
    ui.dragLabel:SetText("KeyMaster")
    ui.dragLabel:SetTextColor(1, 1, 1, 0.85)

    local enemyBar = CreateFrame("Frame", nil, mythicFrame, BackdropTemplateMixin and "BackdropTemplate")
    enemyBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false,
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    enemyBar:SetBackdropColor(0, 0, 0, 0.55)
    enemyBar:SetBackdropBorderColor(1, 1, 1, 0.12)
    enemyBar:SetHeight(20)
    enemyBar:Hide()

    enemyBar.track = enemyBar:CreateTexture(nil, "BACKGROUND")
    enemyBar.track:SetPoint("TOPLEFT", 2, -2)
    enemyBar.track:SetPoint("BOTTOMRIGHT", -2, 2)
    enemyBar.track:SetColorTexture(0, 0, 0, 0.40)

    enemyBar.status = CreateFrame("StatusBar", nil, enemyBar)
    enemyBar.status:SetPoint("TOPLEFT", 2, -2)
    enemyBar.status:SetPoint("BOTTOMRIGHT", -2, 2)
    enemyBar.status:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    enemyBar.status:GetStatusBarTexture():SetHorizTile(false)
    enemyBar.status:GetStatusBarTexture():SetVertTile(false)
    enemyBar.status:SetMinMaxValues(0, 1)
    enemyBar.status:SetStatusBarColor(BREAK_TIMER_BLUE[1], BREAK_TIMER_BLUE[2], BREAK_TIMER_BLUE[3], BREAK_TIMER_BLUE[4])

    enemyBar.edge = enemyBar.status:CreateTexture(nil, "OVERLAY")
    enemyBar.edge:SetTexture("Interface\\Buttons\\WHITE8x8")
    enemyBar.edge:SetColorTexture(1, 1, 1, 0.55)
    enemyBar.edge:SetWidth(2)
    enemyBar.edge:Hide()

    enemyBar.text = CreateLine(enemyBar, 12)
    enemyBar.text:SetJustifyH("CENTER")

    ui.enemyBar = enemyBar

    mythicFrame:SetScript("OnUpdate", function(_, elapsed)
        ui.lastRefreshAt = ui.lastRefreshAt + elapsed
        if ui.lastRefreshAt < UI_REFRESH_INTERVAL_SECONDS then
            return
        end

        ui.lastRefreshAt = 0
        if ui.frame and ui.frame:IsShown() then
            local state = GetActiveRunState()
            if state then
                local forceRefresh = true
                if forceRefresh then
                    -- fall through to the shared refresh routine below
                end
            end
        end

        -- Reuse the main event-driven renderer during polling.
        -- This keeps the timer and enemy forces bar live while inside a run.
        if ui.frame then
            local settings = InitializeDatabase().ui
            if not settings.enabled then
                ui.frame:Hide()
                UpdateBlizzardTrackerVisibility(false)
            elseif settings.hidden then
                ui.frame:Hide()
                UpdateBlizzardTrackerVisibility(false)
            else
                local state = GetActiveRunState()
                if state then
                    local width = 288
                    local xPadding = 10
                    local y = -10

                    ui.frame:Show()

                    ui.dragLabel:ClearAllPoints()
                    ui.dragLabel:SetPoint("TOPRIGHT", ui.frame, "TOPRIGHT", -10, -8)

                    ui.headerLine:SetText(state.level and string.format("+%d - %s", state.level, state.mapName) or state.mapName)
                    ui.headerLine:SetWidth(width)
                    ui.headerLine:ClearAllPoints()
                    ui.headerLine:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", xPadding, y)
                    y = y - ui.headerLine:GetStringHeight() - 4

                    if state.affixSummary and state.affixSummary ~= "" then
                        ui.affixesLine:SetText(state.affixSummary)
                        ui.affixesLine:SetWidth(width)
                        ui.affixesLine:ClearAllPoints()
                        ui.affixesLine:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", xPadding, y)
                        ui.affixesLine:Show()
                        y = y - ui.affixesLine:GetStringHeight() - 6
                    else
                        ui.affixesLine:Hide()
                    end

                    if state.maxTimeSeconds then
                        ui.timerLine:SetText(string.format("%s (%s / %s)", FormatSeconds(state.timeLeftSeconds), FormatSeconds(state.elapsedSeconds), FormatSeconds(state.maxTimeSeconds)))
                    else
                        ui.timerLine:SetText(FormatSeconds(state.elapsedSeconds))
                    end
                    ui.timerLine:SetWidth(width)
                    ui.timerLine:ClearAllPoints()
                    ui.timerLine:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", xPadding, y)
                    y = y - ui.timerLine:GetStringHeight() - 4

                    if state.twoChestLimit then
                        ui.twoChestLine:SetText(string.format("+2 (%s): %s", FormatSeconds(state.twoChestLimit), FormatSeconds(max(0, state.twoChestLimit - state.elapsedSeconds))))
                    else
                        ui.twoChestLine:SetText("+2: --:--")
                    end
                    ui.twoChestLine:SetWidth(width)
                    ui.twoChestLine:ClearAllPoints()
                    ui.twoChestLine:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", xPadding, y)
                    y = y - ui.twoChestLine:GetStringHeight() - 4

                    if state.threeChestLimit then
                        ui.threeChestLine:SetText(string.format("+3 (%s): %s", FormatSeconds(state.threeChestLimit), FormatSeconds(max(0, state.threeChestLimit - state.elapsedSeconds))))
                    else
                        ui.threeChestLine:SetText("+3: --:--")
                    end
                    ui.threeChestLine:SetWidth(width)
                    ui.threeChestLine:ClearAllPoints()
                    ui.threeChestLine:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", xPadding, y)
                    y = y - ui.threeChestLine:GetStringHeight() - 8

                    local visibleObjectiveCount = 0
                    for index, objective in ipairs(state.objectives) do
                        local line = EnsureObjectiveLine(index)
                        line:SetText(BuildObjectiveText(objective))
                        line:SetWidth(width)
                        line:ClearAllPoints()
                        line:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", xPadding, y)
                        line:Show()
                        y = y - line:GetStringHeight() - 4
                        visibleObjectiveCount = index
                    end

                    for index = visibleObjectiveCount + 1, #ui.objectiveLines do
                        ui.objectiveLines[index]:Hide()
                    end

                    local enemyPercent = CalculateEnemyForcesPercent(state.enemyForces)
                    if state.enemyForces and type(enemyPercent) == "number" then
                        local barValue = max(0, min(1, enemyPercent / 100))

                        ui.enemyBar:ClearAllPoints()
                        ui.enemyBar:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", xPadding, y)
                        ui.enemyBar:SetPoint("TOPRIGHT", ui.frame, "TOPRIGHT", -xPadding, y)
                        ui.enemyBar:SetHeight(20)
                        ui.enemyBar:Show()
                        ui.enemyBar.status:SetValue(barValue)
                        ui.enemyBar.text:SetText(string.format("Enemy Forces %.0f%%", enemyPercent))
                        ui.enemyBar.text:SetPoint("CENTER", ui.enemyBar, "CENTER", 0, 0)

                        if barValue > 0 and barValue < 1 then
                            ui.enemyBar.edge:ClearAllPoints()
                            ui.enemyBar.edge:SetPoint("CENTER", ui.enemyBar.status, "LEFT", ui.enemyBar.status:GetWidth() * barValue, 0)
                            ui.enemyBar.edge:SetHeight(ui.enemyBar:GetHeight() + 10)
                            ui.enemyBar.edge:Show()
                        else
                            ui.enemyBar.edge:Hide()
                        end

                        y = y - 26
                    else
                        ui.enemyBar:Hide()
                    end

                    if state.deathCount and state.deathCount > 0 then
                        ui.deathLine:SetText(string.format("Deaths: %d (-%s)", state.deathCount, FormatSeconds(state.deathPenalty or 0)))
                        ui.deathLine:SetWidth(width)
                        ui.deathLine:ClearAllPoints()
                        ui.deathLine:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", xPadding, y)
                        ui.deathLine:Show()
                        y = y - ui.deathLine:GetStringHeight() - 4
                    else
                        ui.deathLine:Hide()
                    end

                    ui.frame:SetHeight(max(120, -y + 12))
                    UpdateBlizzardTrackerVisibility(true)
                else
                    ui.frame:Hide()
                    UpdateBlizzardTrackerVisibility(false)
                end
            end
        end
    end)

    ApplyMythicFrameSettings()
end

local function RefreshMythicUI()
    if not ui.frame then
        CreateMythicUI()
    end

    ui.lastRefreshAt = UI_REFRESH_INTERVAL_SECONDS
end

local function TryAutoSlotKeystone()
    if not (C_ChallengeMode and C_ChallengeMode.SlotKeystone) then
        return
    end

    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemID and C_Container.PickupContainerItem) then
        return
    end

    local ownedMapID = GetOwnedKeystoneMapID()
    local activeMapID = C_ChallengeMode.GetActiveChallengeMapID and C_ChallengeMode.GetActiveChallengeMapID()
    if ownedMapID and activeMapID and activeMapID > 0 and ownedMapID ~= activeMapID then
        ShowMismatchToast(ownedMapID, activeMapID)
        return
    end

    for _, bagID in ipairs(KEYSTONE_BAG_SLOTS) do
        local slotCount = C_Container.GetContainerNumSlots(bagID) or 0
        for slotIndex = 1, slotCount do
            local itemID = C_Container.GetContainerItemID(bagID, slotIndex)
            if KEYSTONE_ITEM_IDS[itemID] then
                C_Container.PickupContainerItem(bagID, slotIndex)
                if CursorHasItem() then
                    C_ChallengeMode.SlotKeystone()
                end
                return
            end
        end
    end
end

local function HookChallengesFrame()
    if ui.challengesFrameHooked or not ChallengesKeystoneFrame then
        return
    end

    ChallengesKeystoneFrame:HookScript("OnShow", TryAutoSlotKeystone)
    ui.challengesFrameHooked = true
end

SLASH_KEYMASTER1 = "/keymaster"
SLASH_KEYMASTER2 = "/km"
SlashCmdList.KEYMASTER = function(message)
    InitializeDatabase()
    CreateMythicUI()
    RegisterSettingsPanel()

    local command = strtrim(strlower(message or ""))
    if command == "" then
        PrintLocal("loaded. UI commands: settings, ui on, ui off, lock, unlock, hide, show, reset, scale <value>. Unlock the UI, then drag it where you want it.")
        return
    end

    if command == "settings" then
        if ui.settingsCategory and Settings and Settings.OpenToCategory then
            Settings.OpenToCategory(ui.settingsCategory:GetID())
        else
            PrintLocal("settings panel is unavailable in this client build")
        end
        return
    end

    if command == "ui on" then
        SetMythicUIEnabled(true)
        PrintLocal("KeyMaster Mythic+ UI enabled")
        return
    end

    if command == "ui off" then
        SetMythicUIEnabled(false)
        PrintLocal("KeyMaster Mythic+ UI disabled; Blizzard UI restored")
        return
    end

    if command == "lock" then
        SetMythicFrameLocked(true)
        PrintLocal("UI locked")
        return
    end

    if command == "unlock" then
        SetMythicFrameLocked(false)
        PrintLocal("UI unlocked; drag it to reposition, then use /km lock when done")
        return
    end

    if command == "hide" then
        KeyMasterDB.ui.hidden = true
        RefreshMythicUI()
        PrintLocal("UI hidden")
        return
    end

    if command == "show" then
        KeyMasterDB.ui.hidden = false
        RefreshMythicUI()
        PrintLocal("UI shown")
        return
    end

    if command == "reset" then
        KeyMasterDB.ui.point = CopyDefaults(DEFAULT_DB.ui.point, {})
        KeyMasterDB.ui.scale = DEFAULT_DB.ui.scale
        ApplyMythicFrameSettings()
        RefreshMythicUI()
        PrintLocal("UI position and scale reset to the default top-right location")
        return
    end

    local scaleValue = strmatch(command, "^scale%s+([%d%.]+)$")
    if scaleValue then
        local numericScale = tonumber(scaleValue)
        if numericScale and numericScale >= 0.7 and numericScale <= 1.5 then
            KeyMasterDB.ui.scale = numericScale
            ApplyMythicFrameSettings()
            RefreshMythicUI()
            PrintLocal(string.format("UI scale set to %.2f", numericScale))
        else
            PrintLocal("scale must be between 0.70 and 1.50")
        end
        return
    end

    PrintLocal("unknown command. Use: settings, ui on, ui off, lock, unlock, hide, show, reset, scale <value>")
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("CHALLENGE_MODE_START")
frame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
frame:RegisterEvent("CHALLENGE_MODE_RESET")
frame:RegisterEvent("SCENARIO_CRITERIA_UPDATE")
frame:RegisterEvent("CHAT_MSG_PARTY")
frame:RegisterEvent("CHAT_MSG_RAID")
frame:RegisterEvent("CHAT_MSG_GUILD")

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            InitializeDatabase()
        elseif loadedAddon == "Blizzard_ChallengesUI" then
            HookChallengesFrame()
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        InitializeDatabase()
        CreateMythicUI()
        RegisterSettingsPanel()
        if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_ChallengesUI") then
            HookChallengesFrame()
        end
        RefreshMythicUI()
        return
    end

    if event == "PLAYER_ENTERING_WORLD"
        or event == "PLAYER_REGEN_ENABLED"
        or event == "CHALLENGE_MODE_START"
        or event == "CHALLENGE_MODE_COMPLETED"
        or event == "CHALLENGE_MODE_RESET"
        or event == "SCENARIO_CRITERIA_UPDATE" then
        RefreshMythicUI()
        return
    end

    HandleChatMessage(event, ...)
end)
