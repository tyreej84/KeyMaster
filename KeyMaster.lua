local addonName = ...

local floor = math.floor
local max = math.max
local min = math.min
local band = bit and bit.band or bit32 and bit32.band
local strfind = string.find
local strlower = string.lower
local strmatch = string.match
local strtrim = strtrim or function(s) return (s:gsub("^%s*(.-)%s*$", "%1")) end
local tonumber = tonumber
local unpack = unpack or table.unpack
local IsChallengeModeRunActive
local IsInMythicDungeonInstance

local frame = CreateFrame("Frame")
local REPLY_PREFIX = "KeyMaster:"
local KEYSTONE_ITEM_IDS = { [180653] = true, [158923] = true, [151086] = true }
local KEYSTONE_BAG_SLOTS = { Enum.BagIndex.Backpack, Enum.BagIndex.Bag_1, Enum.BagIndex.Bag_2, Enum.BagIndex.Bag_3, Enum.BagIndex.Bag_4 }
local KEYS_TEXT_COMMAND = "!keys"
local KEY_TEXT_COMMAND = "!key"
local SCORE_TEXT_COMMAND = "!score"
local SCORES_TEXT_COMMAND = "!scores"
local BEST_TEXT_COMMAND = "!best"
local REQUEST_COMMAND_SET = {
    ["!key"] = true,
    ["!keys"] = true,
    ["!score"] = true,
    ["!scores"] = true,
    ["!best"] = true,
}
local MISMATCH_TOAST_COOLDOWN_SECONDS = 2
local UI_REFRESH_INTERVAL_SECONDS = 0.2
local COMPLETION_DISPLAY_SECONDS = 90
local CHALLENGERS_PERIL_AFFIX_ID = 152
local BREAK_TIMER_BLUE = { 0.15, 0.55, 1.00, 0.90 }
local DEFAULT_DB = {
    ui = {
        enabled = true,
        hideTrackerInMythicPlus = true,
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
    inChallengeMode = false,
    lastRunState = nil,
    completedRun = nil,
    deathLog = {},
    deadUnitState = {},
    observedKeystoneSnapshot = nil,
    enemyForcesTotalUnits = nil,
    enemyForcesMapID = nil,
    loginInitialized = false,
    deferredChatMessages = {},
}

local ENEMY_FORCES_TOTAL_UNITS_BY_MAP_ID = {
    [402] = 460, -- Algethar Academy
    [239] = 568, -- Seat of the Triumvirate
    [556] = 643, -- Pit of Saron
    [557] = 591, -- Windrunner Spire
    [558] = 597, -- Magisters Terrace
    [559] = 596, -- Nexus Point Xenas
    [560] = 607, -- Maisara Caverns
    [161] = 431, -- Skyreach
    [12345] = 470, -- Murder Row (custom map id in reference data)
}

local ENEMY_FORCES_TOTAL_UNITS_BY_DUNGEON = {
    ["algethar academy"] = 460,
    ["pit of saron"] = 643,
    ["seat of the triumvirate"] = 568,
    ["windrunners spire"] = 591,
    ["magisters terrace"] = 597,
    ["magisters terrace"] = 597,
    ["nexus point xenas"] = 596,
    ["maisara caverns"] = 607,
    ["skyreach"] = 431,
    ["murder row"] = 470,
}

local CHAT_EVENTS = {
    CHAT_MSG_PARTY = true,
    CHAT_MSG_PARTY_LEADER = true,
    CHAT_MSG_RAID = true,
    CHAT_MSG_RAID_LEADER = true,
    CHAT_MSG_INSTANCE_CHAT = true,
    CHAT_MSG_INSTANCE_CHAT_LEADER = true,
    CHAT_MSG_GUILD = true,
}

local CHAT_EVENT_TO_CHANNEL = {
    CHAT_MSG_PARTY = "PARTY",
    CHAT_MSG_PARTY_LEADER = "PARTY",
    CHAT_MSG_RAID = "RAID",
    CHAT_MSG_RAID_LEADER = "RAID",
    CHAT_MSG_INSTANCE_CHAT = "INSTANCE_CHAT",
    CHAT_MSG_INSTANCE_CHAT_LEADER = "INSTANCE_CHAT",
    CHAT_MSG_GUILD = "GUILD",
}

local MAX_DEFERRED_CHAT_MESSAGES = 10

local function IsCombatLockdownActive()
    return InCombatLockdown and InCombatLockdown() == true
end

local function QueueDeferredChatMessage(message, chatType)
    if type(message) ~= "string" or message == "" or type(chatType) ~= "string" or chatType == "" then
        return
    end

    local queue = ui.deferredChatMessages
    local lastEntry = queue[#queue]
    if lastEntry and lastEntry.message == message and lastEntry.chatType == chatType then
        return
    end

    if #queue >= MAX_DEFERRED_CHAT_MESSAGES then
        table.remove(queue, 1)
    end

    table.insert(queue, {
        message = message,
        chatType = chatType,
    })
end

local function SendOrQueueChatMessage(message, chatType)
    if IsCombatLockdownActive() then
        QueueDeferredChatMessage(message, chatType)
        return false
    end

    return pcall(SendChatMessage, message, chatType)
end

local function FlushDeferredChatMessages()
    if IsCombatLockdownActive() then
        return
    end

    local queue = ui.deferredChatMessages
    if not queue or #queue == 0 then
        return
    end

    ui.deferredChatMessages = {}
    for _, entry in ipairs(queue) do
        if type(entry) == "table" and type(entry.message) == "string" and entry.message ~= "" and type(entry.chatType) == "string" and entry.chatType ~= "" then
            pcall(SendChatMessage, entry.message, entry.chatType)
        end
    end
end

local function ResetDeathLog()
    ui.deathLog = {}
    ui.deadUnitState = {}
end

local function ResetEnemyForcesCalibration()
    ui.enemyForcesTotalUnits = nil
    ui.enemyForcesMapID = nil
end

local function NormalizePlayerDisplayName(name, realm)
    if type(name) ~= "string" or name == "" then
        return "Unknown"
    end

    if type(realm) == "string" and realm ~= "" then
        return string.format("%s-%s", name, realm)
    end

    return name
end

local function RecordDeathEntry(playerName)
    if type(playerName) ~= "string" or playerName == "" then
        return
    end

    local existing = ui.deathLog[playerName]
    if existing then
        existing.count = existing.count + 1
        existing.lastAt = GetTime()
        return
    end

    ui.deathLog[playerName] = {
        name = playerName,
        count = 1,
        lastAt = GetTime(),
    }
end

local function ShouldTrackDeathAttribution()
    return ui.inChallengeMode
        or (IsInMythicDungeonInstance and IsInMythicDungeonInstance())
        or (IsChallengeModeRunActive and IsChallengeModeRunActive())
end

local function SyncGroupDeathLogFromUnits()
    if not ShouldTrackDeathAttribution() then
        ui.deadUnitState = {}
        return
    end

    local nextDeadUnitState = {}
    local groupUnits = { "player", "party1", "party2", "party3", "party4" }

    for _, unitToken in ipairs(groupUnits) do
        if UnitExists and UnitExists(unitToken) then
            local unitGUID = UnitGUID and UnitGUID(unitToken) or nil
            if type(unitGUID) == "string" and unitGUID ~= "" then
                local isDead = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unitToken)
                if isDead then
                    nextDeadUnitState[unitGUID] = true
                    if not ui.deadUnitState[unitGUID] then
                        local unitName, unitRealm = UnitName(unitToken)
                        RecordDeathEntry(NormalizePlayerDisplayName(unitName, unitRealm))
                    end
                end
            end
        end
    end

    ui.deadUnitState = nextDeadUnitState
end

local function ResolveCombatLogPlayerName(destGUID, destName)
    if GetPlayerInfoByGUID and type(destGUID) == "string" then
        local _, _, _, _, _, resolvedName, resolvedRealm = GetPlayerInfoByGUID(destGUID)
        if type(resolvedName) == "string" and resolvedName ~= "" then
            return NormalizePlayerDisplayName(resolvedName, resolvedRealm)
        end
    end

    if type(destName) == "string" and destName ~= "" then
        return destName
    end

    return "Unknown"
end

local function IsPlayerGUID(guid)
    return type(guid) == "string" and guid:match("^Player%-%d+%-%x+") ~= nil
end

local function IsTrackedGroupDeath(destGUID, destFlags)
    if IsPlayerGUID(destGUID) then
        return true
    end

    if type(destFlags) ~= "number" then
        return false
    end

    if band and COMBATLOG_OBJECT_TYPE_PLAYER and COMBATLOG_OBJECT_AFFILIATION_MINE and COMBATLOG_OBJECT_AFFILIATION_PARTY and COMBATLOG_OBJECT_AFFILIATION_RAID then
        local isPlayer = band(destFlags, COMBATLOG_OBJECT_TYPE_PLAYER) > 0
        local isMine = band(destFlags, COMBATLOG_OBJECT_AFFILIATION_MINE) > 0
        local isParty = band(destFlags, COMBATLOG_OBJECT_AFFILIATION_PARTY) > 0
        local isRaid = band(destFlags, COMBATLOG_OBJECT_AFFILIATION_RAID) > 0
        return isPlayer and (isMine or isParty or isRaid)
    end

    if CombatLog_Object_IsA then
        local isGroup = CombatLog_Object_IsA(destFlags, COMBATLOG_FILTER_GROUP)
        local isPlayerType = CombatLog_Object_IsA(destFlags, COMBATLOG_FILTER_TYPE_PLAYER)
        return isGroup and isPlayerType
    end

    return false
end

local function RecordGroupDeath(destGUID, destName, destFlags)
    if not ShouldTrackDeathAttribution() then
        return
    end

    if not IsTrackedGroupDeath(destGUID, destFlags) then
        return
    end

    local playerName = ResolveCombatLogPlayerName(destGUID, destName)
    RecordDeathEntry(playerName)
end

local function BuildDeathTooltipLines(deathLog)
    local entries = {}
    for _, entry in pairs(deathLog or {}) do
        table.insert(entries, entry)
    end

    table.sort(entries, function(left, right)
        if left.count == right.count then
            return left.name < right.name
        end

        return left.count > right.count
    end)

    return entries
end

local function CopyDeathLog(source)
    local result = {}
    for name, entry in pairs(source or {}) do
        result[name] = {
            name = entry.name or name,
            count = entry.count or 0,
            lastAt = entry.lastAt,
        }
    end

    return result
end

local function GetDisplayedDeathLog()
    if ui.inChallengeMode then
        return ui.deathLog
    end

    if ui.completedRun and ui.completedRun.deathLog then
        return ui.completedRun.deathLog
    end

    return nil
end

local function GetDisplayedDeathCount()
    if ui.inChallengeMode and ui.lastRunState then
        return ui.lastRunState.deathCount or 0
    end

    if ui.completedRun then
        return ui.completedRun.deathCount or 0
    end

    return 0
end

local function ShowDeathTooltip(owner)
    local deathEntries = BuildDeathTooltipLines(GetDisplayedDeathLog())
    local totalDeaths = GetDisplayedDeathCount()
    if totalDeaths <= 0 then
        return
    end

    GameTooltip:Hide()
    GameTooltip:ClearLines()
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(string.format("Deaths: %d", totalDeaths), 1, 1, 1)

    if #deathEntries == 0 then
        GameTooltip:AddDoubleLine("Unattributed", tostring(totalDeaths), 1, 1, 1, 1, 0.82, 0)
        GameTooltip:AddLine("Per-player names were unavailable for these deaths (combat-log range or timing).", 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
        return
    end

    for _, entry in ipairs(deathEntries) do
        GameTooltip:AddDoubleLine(entry.name, tostring(entry.count), 1, 1, 1, 1, 0.82, 0)
    end

    GameTooltip:Show()
end

local function UpdateDeathTooltipArea()
    if not ui.deathHitArea or not ui.deathLine then
        return
    end

    if not ui.deathLine:IsShown() then
        ui.deathHitArea:Hide()
        return
    end

    local width = max(ui.deathLine:GetWidth() or 0, ui.deathLine:GetStringWidth() or 0)
    local height = ui.deathLine:GetStringHeight() or 0

    if width <= 0 and ui.frame then
        width = max(120, (ui.frame:GetWidth() or 0) - 24)
    end

    if height <= 0 then
        height = 16
    end

    ui.deathHitArea:ClearAllPoints()
    ui.deathHitArea:SetPoint("TOPLEFT", ui.deathLine, "TOPLEFT", -2, 2)
    ui.deathHitArea:SetSize(width + 4, height + 4)
    ui.deathHitArea:Show()
end

local function PrintDeathLogSummary()
    local totalDeaths = GetDisplayedDeathCount()
    local entries = BuildDeathTooltipLines(GetDisplayedDeathLog())

    if totalDeaths <= 0 then
        PrintLocal("No deaths recorded in the current or most recent Mythic+ run")
        return
    end

    PrintLocal(string.format("Deaths tracked: %d", totalDeaths))
    if #entries == 0 then
        PrintLocal("No per-player death attribution captured")
        return
    end

    for _, entry in ipairs(entries) do
        PrintLocal(string.format("%s: %d", entry.name, entry.count))
    end
end

local function PrintCriteriaDebugSummary()
    local challengeActive = false
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive then
        challengeActive = C_ChallengeMode.IsChallengeModeActive() == true
    end
    PrintLocal(string.format("Criteria debug: M+ detected=%s", challengeActive and "yes" or "no"))

    local criteriaCount = 0
    if C_Scenario and C_Scenario.GetStepInfo then
        local _, _, count = C_Scenario.GetStepInfo()
        if type(count) == "number" and count > 0 then
            criteriaCount = count
        end
    end

    if criteriaCount <= 0 then
        PrintLocal("No scenario criteria available")
        return
    end

    PrintLocal(string.format("Criteria count: %d", criteriaCount))
    for index = 1, criteriaCount do
        local info
        if C_ScenarioInfo and C_ScenarioInfo.GetCriteriaInfo then
            local ok, criteriaInfo = pcall(C_ScenarioInfo.GetCriteriaInfo, index)
            if ok and type(criteriaInfo) == "table" then
                info = {
                    name = criteriaInfo.criteriaString or criteriaInfo.description or criteriaInfo.name or string.format("Objective %d", index),
                    completed = criteriaInfo.completed == true,
                    quantity = type(criteriaInfo.quantity) == "number" and criteriaInfo.quantity or 0,
                    totalQuantity = type(criteriaInfo.totalQuantity) == "number" and criteriaInfo.totalQuantity or 0,
                    quantityString = criteriaInfo.quantityString,
                    isWeightedProgress = criteriaInfo.isWeightedProgress == true,
                }
            end
        end

        if not info and C_Scenario and C_Scenario.GetCriteriaInfo then
            local ok, name, _, completed, quantity, totalQuantity, _, _, quantityString, _, _, _, _, isWeightedProgress = pcall(C_Scenario.GetCriteriaInfo, index)
            if ok then
                info = {
                    name = name or string.format("Objective %d", index),
                    completed = completed == true,
                    quantity = type(quantity) == "number" and quantity or 0,
                    totalQuantity = type(totalQuantity) == "number" and totalQuantity or 0,
                    quantityString = quantityString,
                    isWeightedProgress = isWeightedProgress == true,
                }
            end
        end

        if info then
            PrintLocal(string.format(
                "%d) %s | weighted=%s | completed=%s | quantity=%s | total=%s | qstr=%s",
                index,
                info.name or "?",
                info.isWeightedProgress and "yes" or "no",
                info.completed and "yes" or "no",
                tostring(info.quantity),
                tostring(info.totalQuantity),
                tostring(info.quantityString)
            ))
        end
    end
end

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

    if type(KeyMasterDB.ui.hideTrackerInMythicPlus) ~= "boolean" then
        KeyMasterDB.ui.hideTrackerInMythicPlus = DEFAULT_DB.ui.hideTrackerInMythicPlus
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

local function IsKeystoneLink(link)
    return type(link) == "string" and link:find("|Hkeystone:", 1, true) ~= nil
end

local function FindKeystoneBagSlot()
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemID) then
        return nil, nil, nil
    end

    for _, bagID in ipairs(KEYSTONE_BAG_SLOTS) do
        local slotCount = C_Container.GetContainerNumSlots(bagID) or 0
        for slotIndex = 1, slotCount do
            local itemID = C_Container.GetContainerItemID(bagID, slotIndex)
            local bagLink = C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bagID, slotIndex) or nil
            if KEYSTONE_ITEM_IDS[itemID] or IsKeystoneLink(bagLink) then
                return bagID, slotIndex, bagLink
            end
        end
    end

    return nil, nil, nil
end

local function FindKeystoneItemLocation()
    local bagID, slotIndex = FindKeystoneBagSlot()
    if bagID == nil or slotIndex == nil or not (ItemLocation and ItemLocation.CreateFromBagAndSlot) then
        return nil
    end

    return ItemLocation:CreateFromBagAndSlot(bagID, slotIndex)
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

local function FormatSignedSeconds(seconds)
    if type(seconds) ~= "number" then
        return FormatSeconds(0)
    end

    if seconds < 0 then
        return string.format("-%s", FormatSeconds(-seconds))
    end

    return FormatSeconds(seconds)
end

local function ParsePercentValue(text)
    if type(text) ~= "string" then
        return nil
    end

    -- Strip WoW color/format control bytes and tolerate localized spacing like "88 %".
    local normalizedText = text
        :gsub("|c%x%x%x%x%x%x%x%x", "")
        :gsub("|r", "")
        :gsub(",", ".")
    local percentText = strmatch(normalizedText, "(%d+%.?%d*)%s*%%")
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

    local _, _, bagLink = FindKeystoneBagSlot()
    if bagLink then
        return bagLink
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

    return string.format("%s Keystone unavailable", REPLY_PREFIX)
end

local function GetOwnedKeystoneSnapshot()
    local mapID = GetOwnedKeystoneMapID()
    local keyLevel = GetOwnedKeystoneLevel()

    if type(mapID) ~= "number" or mapID <= 0 or type(keyLevel) ~= "number" or keyLevel <= 0 then
        return nil, nil
    end

    return mapID, keyLevel
end

local function BuildKeystoneSnapshotKey(mapID, keyLevel)
    if type(mapID) ~= "number" or type(keyLevel) ~= "number" then
        return "none"
    end

    return string.format("%d:%d", mapID, keyLevel)
end

local function AnnounceNewOwnedKeystone(mapID, keyLevel)
    if not IsInGroup() then
        return
    end

    local link = GetOwnedKeystoneLink()
    if not link and mapID and keyLevel then
        local mapName = GetKeystoneMapName(mapID)
        if mapName and mapName ~= "" then
            local linkText = string.format("[Keystone: %s (%d)]", mapName, keyLevel)
            link = string.format(
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
    end

    if not link then
        return
    end

    SendOrQueueChatMessage(string.format("%s New key %s", REPLY_PREFIX, link), "PARTY")
end

local function ObserveOwnedKeystone(allowAnnounce)
    local mapID, keyLevel = GetOwnedKeystoneSnapshot()
    local currentSnapshotKey = BuildKeystoneSnapshotKey(mapID, keyLevel)

    if not ui.observedKeystoneSnapshot then
        ui.observedKeystoneSnapshot = currentSnapshotKey
        return
    end

    if ui.observedKeystoneSnapshot == currentSnapshotKey then
        return
    end

    local previousSnapshotKey = ui.observedKeystoneSnapshot
    ui.observedKeystoneSnapshot = currentSnapshotKey

    if allowAnnounce ~= true then
        return
    end

    if previousSnapshotKey == "none" or currentSnapshotKey == "none" then
        return
    end

    AnnounceNewOwnedKeystone(mapID, keyLevel)
end

local function ScheduleOwnedKeystoneObservation(allowAnnounce, delaySeconds)
    if not (C_Timer and C_Timer.After) then
        ObserveOwnedKeystone(allowAnnounce)
        return
    end

    local delay = type(delaySeconds) == "number" and max(0, delaySeconds) or 0
    C_Timer.After(delay, function()
        ObserveOwnedKeystone(allowAnnounce)
    end)
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
    if type(score) == "number" and score >= 0 then
        return string.format("%s M+ Score: %d", REPLY_PREFIX, floor(score + 0.5))
    end

    return string.format("%s M+ Score unavailable", REPLY_PREFIX)
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

    local function ResolveRunLevel(run)
        if type(run) ~= "table" then
            return nil
        end

        local level = run.level or run.bestRunLevel or run.keystoneLevel or run.completedLevel
        level = tonumber(level)
        if type(level) == "number" and level >= 2 and level <= 40 then
            return level
        end

        return nil
    end

    local function ResolveRunMapID(run)
        if type(run) ~= "table" then
            return nil
        end

        local mapID = run.mapChallengeModeID or run.mapID or run.challengeMapID
        mapID = tonumber(mapID)
        if type(mapID) == "number" and mapID > 0 then
            return mapID
        end

        return nil
    end

    for _, run in ipairs(history) do
        if run and run.completed ~= false then
            local level = ResolveRunLevel(run)
            local mapID = ResolveRunMapID(run)
            if level then
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

    if not weekBest and seasonBest then
        weekBest = seasonBest
    end

    return string.format(
        "%s Best - Week: %s / Season: %s",
        REPLY_PREFIX,
        FormatBestRun(weekBest),
        FormatBestRun(seasonBest)
    )
end

local function ExtractRequestCommand(message)
    local ok, command = pcall(function(rawMessage)
        local msg = string.format("%s", rawMessage)
        msg = strtrim(strlower(msg))
        msg = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")

        local parsed = msg:match("^(![%a]+)") or msg:match("%s(![%a]+)")
        if type(parsed) ~= "string" then
            return nil
        end

        parsed = parsed:gsub("[,%.%?!;:]+$", "")
        parsed = string.format("%s", parsed)
        if REQUEST_COMMAND_SET[parsed] then
            return parsed
        end

        return nil
    end, message)

    if ok then
        return command
    end

    return nil
end

local function BuildReplyForCommand(command)
    if type(command) ~= "string" or command == "" then
        return nil
    end

    if command == KEY_TEXT_COMMAND or command == KEYS_TEXT_COMMAND then
        return BuildKeystoneReply()
    end

    if command == SCORE_TEXT_COMMAND or command == SCORES_TEXT_COMMAND then
        return BuildScoreReply()
    end

    if command == BEST_TEXT_COMMAND then
        return BuildBestReply()
    end

    return nil
end

local function CanReadChatPayload(message)
    if type(message) ~= "string" then
        return false
    end

    if type(canaccessvalue) == "function" then
        local ok, readable = pcall(canaccessvalue, message)
        return ok and readable == true
    end

    return true
end

local function HandleChatMessage(event, message)
    if not CHAT_EVENTS[event] then
        return
    end

    if not CanReadChatPayload(message) then
        return
    end

    local command = ExtractRequestCommand(message)
    if not command then
        return
    end

    local ok, reply = pcall(BuildReplyForCommand, command)
    if not ok or not reply then
        return
    end

    local chatType = CHAT_EVENT_TO_CHANNEL[event]
    if not chatType then
        return
    end

    SendOrQueueChatMessage(reply, chatType)
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

IsChallengeModeRunActive = function()
    -- First check: if we explicitly received a CHALLENGE_MODE_START event, trust that
    if ui.inChallengeMode then
        return true
    end

    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive() then
        return true
    end

    if C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID then
        local activeMapID = C_ChallengeMode.GetActiveChallengeMapID()
        if type(activeMapID) == "number" and activeMapID > 0 then
            return true
        end
    end

    return false
end

IsInMythicDungeonInstance = function()
    local _, instanceType, difficultyID = GetInstanceInfo()
    return instanceType == "party" and difficultyID == 8
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

local function NormalizeObjectiveText(text)
    if type(text) ~= "string" then
        return ""
    end

    local normalized = text
        :gsub("|c%x%x%x%x%x%x%x%x", "")
        :gsub("|r", "")
        :gsub("[\226\128\153\226\128\152`']", "")
        :gsub("[%-%_%./]", " ")
    normalized = strlower(normalized)
    normalized = normalized:gsub("[%(%):;,]", " ")
    normalized = normalized:gsub("%s+", " ")
    return strtrim(normalized)
end

local function GetKnownEnemyForcesTotalUnits(mapID, mapName)
    if type(mapID) == "number" and mapID > 0 then
        local totalByMapID = ENEMY_FORCES_TOTAL_UNITS_BY_MAP_ID[mapID]
        if type(totalByMapID) == "number" and totalByMapID > 0 then
            return totalByMapID
        end
    end

    local normalizedMapName = NormalizeObjectiveText(mapName)
    if normalizedMapName == "" then
        return nil
    end

    return ENEMY_FORCES_TOTAL_UNITS_BY_DUNGEON[normalizedMapName]
end

local function IsEnemyForcesName(name)
    local normalizedName = NormalizeObjectiveText(name)
    if normalizedName == "" then
        return false
    end

    local enemyForcesLabel = NormalizeObjectiveText(CHALLENGE_MODE_ENEMY_FORCES)
    if enemyForcesLabel ~= "" and normalizedName == enemyForcesLabel then
        return true
    end

    return normalizedName == "enemy forces"
end

local function ResolveEnemyForcesPercent(criteriaInfo, mapID, mapName)
    if not criteriaInfo then
        return nil
    end

    if type(mapID) == "number" and mapID > 0 and ui.enemyForcesMapID ~= mapID then
        ui.enemyForcesMapID = mapID
        ui.enemyForcesTotalUnits = nil
    end

    if type(ui.enemyForcesTotalUnits) ~= "number" or ui.enemyForcesTotalUnits <= 0 then
        local knownTotalUnits = GetKnownEnemyForcesTotalUnits(mapID, mapName)
        if type(knownTotalUnits) == "number" and knownTotalUnits > 0 then
            ui.enemyForcesTotalUnits = knownTotalUnits
        end
    end

    if criteriaInfo.completed then
        return 100
    end

    -- Mirror MythicPlusTimer behavior first:
    -- 1) treat weighted quantity as percent-like by default
    -- 2) but if quantityString includes %, parse and use it as current value
    -- 3) when parsed-from-string, compute percent via value/totalQuantity
    local quantityValue = type(criteriaInfo.quantity) == "number" and criteriaInfo.quantity or nil
    local useDirectPercent = criteriaInfo.isWeightedProgress == true

    local quantityStringPercent = ParsePercentValue(criteriaInfo.quantityString)
    if criteriaInfo.isWeightedProgress and type(quantityStringPercent) == "number" then
        quantityValue = quantityStringPercent
        useDirectPercent = false

        if type(criteriaInfo.quantity) == "number" and criteriaInfo.quantity > 0 and quantityStringPercent > 0 then
            local estimatedTotalUnits = (criteriaInfo.quantity * 100) / quantityStringPercent
            if estimatedTotalUnits > 100 and estimatedTotalUnits < 5000 then
                ui.enemyForcesTotalUnits = estimatedTotalUnits
            end
        end
    end

    if type(quantityValue) == "number" then
        if useDirectPercent then
            return min(100, max(0, quantityValue))
        end

        if type(criteriaInfo.totalQuantity) == "number" and criteriaInfo.totalQuantity > 0 then
            return min(100, max(0, (quantityValue / criteriaInfo.totalQuantity) * 100))
        end
    end

    if type(criteriaInfo.quantity) == "number" and type(ui.enemyForcesTotalUnits) == "number" and ui.enemyForcesTotalUnits > 0 then
        return min(100, max(0, (criteriaInfo.quantity / ui.enemyForcesTotalUnits) * 100))
    end

    return nil
end

local function GetCriteriaState(mapID, mapName)
    local criteriaCount = GetCriteriaCount()
    local objectives = {}
    local enemyForcesIndex
    local enemyForcesPercent
    local bestConfidence = -1

    for index = 1, criteriaCount do
        local info = NormalizeCriteriaInfo(index)
        if info then
            table.insert(objectives, info)

            if IsEnemyForcesName(info.name) then
                local percent = ResolveEnemyForcesPercent(info, mapID, mapName)

                local confidence = 0
                if ParsePercentValue(info.quantityString) ~= nil then
                    confidence = confidence + 3
                end
                if info.isWeightedProgress then
                    confidence = confidence + 2
                end
                if type(info.totalQuantity) == "number" and info.totalQuantity > 0 then
                    confidence = confidence + 1
                end
                if info.completed then
                    confidence = confidence + 1
                end

                if type(percent) == "number" and confidence > bestConfidence then
                    bestConfidence = confidence
                    enemyForcesPercent = percent
                    enemyForcesIndex = #objectives
                end
            end
        end
    end

    if enemyForcesIndex and type(enemyForcesPercent) == "number" then
        table.remove(objectives, enemyForcesIndex)
    else
        enemyForcesPercent = nil
    end

    return objectives, enemyForcesPercent
end

local function CalculateEnemyForcesPercent(enemyInfo)
    if type(enemyInfo) == "number" then
        return min(100, max(0, enemyInfo))
    end

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
    local objectives, enemyForcesPercent = GetCriteriaState(mapID, mapName)
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
        enemyForcesPercent = enemyForcesPercent,
        deathCount = deathCount,
        deathPenalty = deathPenalty,
    }
end

local function GetUpgradeLevels(state)
    if not state or type(state.elapsedSeconds) ~= "number" or type(state.maxTimeSeconds) ~= "number" then
        return nil
    end

    if type(state.threeChestLimit) == "number" and state.elapsedSeconds <= state.threeChestLimit then
        return 3
    end

    if type(state.twoChestLimit) == "number" and state.elapsedSeconds <= state.twoChestLimit then
        return 2
    end

    if state.elapsedSeconds <= state.maxTimeSeconds then
        return 1
    end

    return 0
end

local function CaptureCompletedRunState()
    local source = ui.lastRunState or GetActiveRunState()
    if not source then
        return
    end

    local completionMapID
    local completionLevel
    local completionTimeMs
    local completionOnTime
    local completionUpgradeLevels

    if C_ChallengeMode and C_ChallengeMode.GetCompletionInfo then
        local ok, mapChallengeModeID, level, time, onTime, keystoneUpgradeLevels = pcall(C_ChallengeMode.GetCompletionInfo)
        if ok then
            completionMapID = mapChallengeModeID
            completionLevel = level
            completionTimeMs = time
            completionOnTime = onTime
            completionUpgradeLevels = keystoneUpgradeLevels
        end
    end

    local completionElapsedSeconds = source.elapsedSeconds
    if type(completionTimeMs) == "number" and completionTimeMs > 0 then
        completionElapsedSeconds = completionTimeMs / 1000
    end

    local completionMaxTimeSeconds = source.maxTimeSeconds
    local completionTimeLeftSeconds = source.timeLeftSeconds
    if type(completionElapsedSeconds) == "number" and type(completionMaxTimeSeconds) == "number" then
        completionTimeLeftSeconds = completionMaxTimeSeconds - completionElapsedSeconds
    end

    local upgradeLevels = completionUpgradeLevels
    if type(upgradeLevels) ~= "number" then
        local upgradedSource = {
            elapsedSeconds = completionElapsedSeconds,
            maxTimeSeconds = completionMaxTimeSeconds,
            twoChestLimit = source.twoChestLimit,
            threeChestLimit = source.threeChestLimit,
        }
        upgradeLevels = GetUpgradeLevels(upgradedSource)
    elseif completionOnTime == false and upgradeLevels <= 0 then
        upgradeLevels = 0
    end

    local resultText
    if upgradeLevels == 3 then
        resultText = "Result: +3"
    elseif upgradeLevels == 2 then
        resultText = "Result: +2"
    elseif upgradeLevels == 1 then
        resultText = "Result: +1"
    elseif upgradeLevels == 0 then
        resultText = "Result: Depleted"
    else
        resultText = "Result: Completed"
    end

    ui.completedRun = {
        completedAt = GetTime(),
        mapName = GetKeystoneMapName(completionMapID) or source.mapName,
        level = completionLevel or source.level,
        affixSummary = source.affixSummary,
        elapsedSeconds = completionElapsedSeconds,
        maxTimeSeconds = completionMaxTimeSeconds,
        timeLeftSeconds = completionTimeLeftSeconds,
        twoChestLimit = source.twoChestLimit,
        threeChestLimit = source.threeChestLimit,
        deathCount = source.deathCount,
        deathPenalty = source.deathPenalty,
        deathLog = CopyDeathLog(ui.deathLog),
        resultText = resultText,
    }
end

local function RefreshCompletedRunTimingFromAPI()
    if not (ui.completedRun and C_ChallengeMode and C_ChallengeMode.GetCompletionInfo) then
        return
    end

    local ok, _, _, completionTimeMs = pcall(C_ChallengeMode.GetCompletionInfo)
    if not ok or type(completionTimeMs) ~= "number" or completionTimeMs <= 0 then
        return
    end

    local elapsedSeconds = completionTimeMs / 1000
    ui.completedRun.elapsedSeconds = elapsedSeconds

    if type(ui.completedRun.maxTimeSeconds) == "number" then
        ui.completedRun.timeLeftSeconds = ui.completedRun.maxTimeSeconds - elapsedSeconds
    end

    RefreshMythicUI()
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
    ui.frame:EnableMouse(true)
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
    local suppress = shouldSuppress == true

    if ui.trackerSuppressed == suppress then
        return
    end

    if not ObjectiveTrackerFrame then
        ui.trackerSuppressed = suppress
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        return
    end

    local alpha = suppress and 0 or 1
    ObjectiveTrackerFrame:SetAlpha(alpha)
    if ObjectiveTrackerBlocksFrame and ObjectiveTrackerBlocksFrame.SetAlpha then
        ObjectiveTrackerBlocksFrame:SetAlpha(alpha)
    end

    ui.trackerSuppressed = suppress
end

local function SetMythicFrameLocked(isLocked)
    InitializeDatabase().ui.locked = isLocked == true
    ApplyMythicFrameSettings()
end

local function BuildUIStatusLine()
    local uiSettings = InitializeDatabase().ui
    local point = uiSettings.point or DEFAULT_DB.ui.point
    local anchor = string.format("%s/%s", point[1] or "CENTER", point[3] or "CENTER")
    local offset = string.format("%d,%d", point[4] or 0, point[5] or 0)
    local challengeActive = IsChallengeModeRunActive()

    return string.format(
        "UI status - enabled: %s, hidden: %s, tracker hide in M+: %s, locked: %s, scale: %.2f, M+ detected: %s, anchor: %s (%s)",
        uiSettings.enabled and "on" or "off",
        uiSettings.hidden and "yes" or "no",
        uiSettings.hideTrackerInMythicPlus and "on" or "off",
        uiSettings.locked and "yes" or "no",
        uiSettings.scale or 1,
        challengeActive and "yes" or "no",
        anchor,
        offset
    )
end

local function RestoreUIStateToVisibleDefaults()
    local uiSettings = InitializeDatabase().ui
    uiSettings.enabled = true
    uiSettings.hidden = false
    uiSettings.locked = true
    uiSettings.scale = DEFAULT_DB.ui.scale
    uiSettings.point = CopyDefaults(DEFAULT_DB.ui.point, {})

    ApplyMythicFrameSettings()
    RefreshMythicUI()
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
    description:SetText("Disabled: KeyMaster keeps chat replies while Blizzard's default Mythic+ UI remains active. Automatic keystone slotting is active when this setting is enabled.")

    local trackerCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    trackerCheckbox:SetPoint("TOPLEFT", description, "BOTTOMLEFT", -2, -12)
    trackerCheckbox.Text:SetText("Hide Blizzard objectives during Mythic+")
    trackerCheckbox.Text:SetWidth(320)
    trackerCheckbox:SetChecked(InitializeDatabase().ui.hideTrackerInMythicPlus ~= false)
    trackerCheckbox:SetScript("OnClick", function(self)
        InitializeDatabase().ui.hideTrackerInMythicPlus = self:GetChecked() == true
        RefreshMythicUI()
    end)

    local positioning = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    positioning:SetPoint("TOPLEFT", trackerCheckbox, "BOTTOMLEFT", 6, -10)
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
        trackerCheckbox:SetChecked(InitializeDatabase().ui.hideTrackerInMythicPlus ~= false)
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

local function RenderMythicUI()
    if not ui.frame then
        return
    end

    local settings = InitializeDatabase().ui
    local challengeActive = IsChallengeModeRunActive()
    local shouldSuppressTracker = settings.enabled
        and not settings.hidden
        and challengeActive
        and (settings.hideTrackerInMythicPlus ~= false)

    if not settings.enabled then
        ui.frame:Hide()
    elseif settings.hidden then
        ui.frame:Hide()
    else
        local state = challengeActive and GetActiveRunState() or nil
        if state then
            ui.lastRunState = state
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
            ui.timerLine:SetTextColor(1, 1, 1, 1)
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

            local enemyPercent = CalculateEnemyForcesPercent(state.enemyForcesPercent)
            if type(enemyPercent) == "number" then
                local barValue = max(0, min(1, enemyPercent / 100))
                local displayEnemyPercent = min(100, max(0, floor(enemyPercent + 0.000001)))

                ui.enemyBar:ClearAllPoints()
                ui.enemyBar:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", xPadding, y)
                ui.enemyBar:SetPoint("TOPRIGHT", ui.frame, "TOPRIGHT", -xPadding, y)
                ui.enemyBar:SetHeight(20)
                ui.enemyBar:Show()
                ui.enemyBar.status:SetValue(barValue)
                ui.enemyBar.text:SetText(string.format("Enemy Forces %d%%", displayEnemyPercent))
                ui.enemyBar.text:SetTextColor(1, 1, 1, 1)
                ui.enemyBar.text:SetShadowColor(0, 0, 0, 0)
                ui.enemyBar.text:SetShadowOffset(0, 0)

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
                UpdateDeathTooltipArea()
                y = y - ui.deathLine:GetStringHeight() - 4
            else
                ui.deathLine:Hide()
                UpdateDeathTooltipArea()
            end

            ui.frame:SetHeight(max(120, -y + 12))
        elseif challengeActive then
            local width = 288
            local xPadding = 10
            local y = -10

            ui.frame:Show()

            ui.dragLabel:ClearAllPoints()
            ui.dragLabel:SetPoint("TOPRIGHT", ui.frame, "TOPRIGHT", -10, -8)

            ui.headerLine:SetText("Mythic+ active")
            ui.headerLine:SetWidth(width)
            ui.headerLine:ClearAllPoints()
            ui.headerLine:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", xPadding, y)
            y = y - ui.headerLine:GetStringHeight() - 4

            local elapsedSeconds = GetWorldElapsedSeconds() or 0
            ui.timerLine:SetText(string.format("%s (waiting for challenge data)", FormatSeconds(elapsedSeconds)))
            ui.timerLine:SetTextColor(1, 1, 1, 1)
            ui.timerLine:SetWidth(width)
            ui.timerLine:ClearAllPoints()
            ui.timerLine:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", xPadding, y)

            ui.affixesLine:Hide()
            ui.twoChestLine:Hide()
            ui.threeChestLine:Hide()
            ui.deathLine:Hide()
            UpdateDeathTooltipArea()
            ui.enemyBar:Hide()
            for index = 1, #ui.objectiveLines do
                ui.objectiveLines[index]:Hide()
            end

            ui.frame:SetHeight(90)
        elseif ui.completedRun and IsInMythicDungeonInstance() then
            local completed = ui.completedRun
            local width = 288
            local xPadding = 10
            local y = -10

            ui.frame:Show()

            ui.dragLabel:ClearAllPoints()
            ui.dragLabel:SetPoint("TOPRIGHT", ui.frame, "TOPRIGHT", -10, -8)

            ui.headerLine:SetText(completed.level and string.format("+%d - %s", completed.level, completed.mapName or "Mythic+") or (completed.mapName or "Mythic+"))
            ui.headerLine:SetWidth(width)
            ui.headerLine:ClearAllPoints()
            ui.headerLine:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", xPadding, y)
            y = y - ui.headerLine:GetStringHeight() - 4

            if completed.affixSummary and completed.affixSummary ~= "" then
                ui.affixesLine:SetText(completed.affixSummary)
                ui.affixesLine:SetWidth(width)
                ui.affixesLine:ClearAllPoints()
                ui.affixesLine:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", xPadding, y)
                ui.affixesLine:Show()
                y = y - ui.affixesLine:GetStringHeight() - 6
            else
                ui.affixesLine:Hide()
            end

            if completed.maxTimeSeconds then
                ui.timerLine:SetText(string.format("Completed: %s (%s left)", FormatSeconds(completed.elapsedSeconds or 0), FormatSignedSeconds(completed.timeLeftSeconds or 0)))
                if type(completed.timeLeftSeconds) == "number" and completed.timeLeftSeconds < 0 then
                    ui.timerLine:SetTextColor(1, 0.25, 0.25, 1)
                else
                    ui.timerLine:SetTextColor(1, 1, 1, 1)
                end
            else
                ui.timerLine:SetText(string.format("Completed: %s", FormatSeconds(completed.elapsedSeconds or 0)))
                ui.timerLine:SetTextColor(1, 1, 1, 1)
            end
            ui.timerLine:SetWidth(width)
            ui.timerLine:ClearAllPoints()
            ui.timerLine:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", xPadding, y)
            y = y - ui.timerLine:GetStringHeight() - 4

            ui.twoChestLine:SetText(completed.resultText or "Result: Completed")
            ui.twoChestLine:SetWidth(width)
            ui.twoChestLine:ClearAllPoints()
            ui.twoChestLine:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", xPadding, y)
            ui.twoChestLine:Show()
            y = y - ui.twoChestLine:GetStringHeight() - 4

            if completed.maxTimeSeconds then
                ui.threeChestLine:SetText(string.format("Timer: %s / %s", FormatSeconds(completed.elapsedSeconds or 0), FormatSeconds(completed.maxTimeSeconds)))
            else
                ui.threeChestLine:SetText("Timer: --:--")
            end
            ui.threeChestLine:SetWidth(width)
            ui.threeChestLine:ClearAllPoints()
            ui.threeChestLine:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", xPadding, y)
            ui.threeChestLine:Show()
            y = y - ui.threeChestLine:GetStringHeight() - 6

            if completed.deathCount and completed.deathCount > 0 then
                ui.deathLine:SetText(string.format("Deaths: %d (-%s)", completed.deathCount, FormatSeconds(completed.deathPenalty or 0)))
                ui.deathLine:SetWidth(width)
                ui.deathLine:ClearAllPoints()
                ui.deathLine:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", xPadding, y)
                ui.deathLine:Show()
                UpdateDeathTooltipArea()
                y = y - ui.deathLine:GetStringHeight() - 4
            else
                ui.deathLine:Hide()
                UpdateDeathTooltipArea()
            end

            ui.enemyBar:Hide()
            for index = 1, #ui.objectiveLines do
                ui.objectiveLines[index]:Hide()
            end

            ui.frame:SetHeight(max(120, -y + 12))
        else
            ui.frame:Hide()
            UpdateDeathTooltipArea()
        end
    end

    UpdateBlizzardTrackerVisibility(shouldSuppressTracker)
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

    local deathHitArea = CreateFrame("Frame", nil, mythicFrame)
    deathHitArea:EnableMouse(true)
    deathHitArea:SetFrameStrata(mythicFrame:GetFrameStrata())
    deathHitArea:SetFrameLevel(mythicFrame:GetFrameLevel() + 20)
    deathHitArea:Hide()
    deathHitArea:SetScript("OnEnter", function(self)
        ShowDeathTooltip(self)
    end)
    deathHitArea:SetScript("OnLeave", GameTooltip_Hide)
    ui.deathHitArea = deathHitArea

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

    enemyBar.labelBackdrop = enemyBar:CreateTexture(nil, "ARTWORK")
    enemyBar.labelBackdrop:SetTexture("Interface\\Buttons\\WHITE8x8")
    enemyBar.labelBackdrop:SetPoint("TOPLEFT", enemyBar, "TOPLEFT", 2, -2)
    enemyBar.labelBackdrop:SetPoint("BOTTOMRIGHT", enemyBar, "BOTTOMRIGHT", -2, 2)
    enemyBar.labelBackdrop:SetColorTexture(0, 0, 0, 0.20)

    enemyBar.textLayer = CreateFrame("Frame", nil, enemyBar)
    enemyBar.textLayer:SetAllPoints(enemyBar)
    enemyBar.textLayer:SetFrameStrata(enemyBar:GetFrameStrata())
    enemyBar.textLayer:SetFrameLevel(enemyBar:GetFrameLevel() + 50)

    enemyBar.text = CreateLine(enemyBar.textLayer, 12)
    enemyBar.text:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    enemyBar.text:SetJustifyH("CENTER")
    enemyBar.text:SetPoint("CENTER", enemyBar.textLayer, "CENTER", 0, 0)

    ui.enemyBar = enemyBar

    mythicFrame:SetScript("OnUpdate", function(_, elapsed)
        ui.lastRefreshAt = ui.lastRefreshAt + elapsed
        if ui.lastRefreshAt < UI_REFRESH_INTERVAL_SECONDS then
            return
        end

        ui.lastRefreshAt = 0
        RenderMythicUI()
    end)

    ApplyMythicFrameSettings()
end

local function RefreshMythicUI()
    if not ui.frame then
        CreateMythicUI()
    end

    ui.lastRefreshAt = UI_REFRESH_INTERVAL_SECONDS
    RenderMythicUI()
end

local function TryAutoSlotKeystone()
    if not (C_ChallengeMode and C_ChallengeMode.SlotKeystone) then return end
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemID and C_Container.PickupContainerItem) then return end
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

local function PrintEnemyForcesDebugSummary()
    local activeMapID
    if C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID then
        local ok, mapID = pcall(C_ChallengeMode.GetActiveChallengeMapID)
        if ok and type(mapID) == "number" and mapID > 0 then
            activeMapID = mapID
        end
    end

    local mapName = GetKeystoneMapName(activeMapID)
    if (not mapName or mapName == "") and activeMapID then
        mapName = FormatDungeonLabel(activeMapID)
    end

    local knownTotal = GetKnownEnemyForcesTotalUnits(activeMapID, mapName)
    PrintLocal(string.format(
        "Enemy Forces debug: mapID=%s map=%s knownTotal=%s cachedTotal=%s",
        tostring(activeMapID or "?"),
        tostring(mapName or "?"),
        tostring(knownTotal or "nil"),
        tostring(ui.enemyForcesTotalUnits or "nil")
    ))

    local criteriaCount = GetCriteriaCount()
    if criteriaCount <= 0 then
        PrintLocal("Enemy Forces debug: no criteria available")
        return
    end

    local found = false
    for index = 1, criteriaCount do
        local info = NormalizeCriteriaInfo(index)
        if info and IsEnemyForcesName(info.name) then
            found = true
            local parsedPercent = ParsePercentValue(info.quantityString)
            local inferredTotal
            if type(info.quantity) == "number" and info.quantity > 0 and type(parsedPercent) == "number" and parsedPercent > 0 then
                inferredTotal = (info.quantity * 100) / parsedPercent
            end

            PrintLocal(string.format(
                "Enemy criteria[%d]: quantity=%s totalQuantity=%s qstr=%s parsed%%=%s inferredTotal=%s weighted=%s completed=%s",
                index,
                tostring(info.quantity),
                tostring(info.totalQuantity),
                tostring(info.quantityString),
                tostring(parsedPercent),
                tostring(inferredTotal and floor(inferredTotal + 0.5) or "nil"),
                info.isWeightedProgress and "yes" or "no",
                info.completed and "yes" or "no"
            ))
        end
    end

    if not found then
        PrintLocal("Enemy Forces debug: no Enemy Forces criterion matched")
    end
end

SLASH_KEYMASTER1 = "/keymaster"
SLASH_KEYMASTER2 = "/km"
SlashCmdList.KEYMASTER = function(message)
    InitializeDatabase()
    CreateMythicUI()
    RegisterSettingsPanel()

    local command = strtrim(strlower(message or ""))
    if command == "" then
        PrintLocal(BuildUIStatusLine())
        PrintLocal("UI commands: settings, status, ui on, ui off, ui restore, lock, unlock, hide, show, reset, scale <value>. Unlock the UI, then drag it where you want it.")
        return
    end

    if command == "status" then
        PrintLocal(BuildUIStatusLine())
        return
    end

    if command == "deaths" then
        local ok, err = pcall(PrintDeathLogSummary)
        if not ok then
            PrintLocal(string.format("deaths debug error: %s", tostring(err)))
        end
        return
    end

    if command == "criteria" then
        local ok, err = pcall(PrintCriteriaDebugSummary)
        if not ok then
            PrintLocal(string.format("criteria debug error: %s", tostring(err)))
        end
        return
    end

    if command == "forces" then
        local ok, err = pcall(PrintEnemyForcesDebugSummary)
        if not ok then
            PrintLocal(string.format("forces debug error: %s", tostring(err)))
        end
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

    if command == "ui restore" then
        RestoreUIStateToVisibleDefaults()
        PrintLocal("KeyMaster Mythic+ UI restored and reset to the default top-right location")
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

    PrintLocal("unknown command. Use: settings, status, deaths, criteria, forces, ui on, ui off, ui restore, lock, unlock, hide, show, reset, scale <value>")
end

local FRAME_EVENTS = {
    "ADDON_LOADED",
    "PLAYER_LOGIN",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_ENABLED",
    "CHALLENGE_MODE_START",
    "CHALLENGE_MODE_COMPLETED",
    "CHALLENGE_MODE_RESET",
    "COMBAT_LOG_EVENT_UNFILTERED",
    "SCENARIO_CRITERIA_UPDATE",
    "GROUP_ROSTER_UPDATE",
    "UNIT_FLAGS",
    "PLAYER_DEAD",
    "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_GUILD",
}

local function PerformLoginInitialization()
    if ui.loginInitialized then
        return
    end

    ui.loginInitialized = true
    InitializeDatabase()
    CreateMythicUI()
    RegisterSettingsPanel()
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_ChallengesUI") then
        HookChallengesFrame()
    end
    ObserveOwnedKeystone(false)
    RefreshMythicUI()
end

for _, eventName in ipairs(FRAME_EVENTS) do
    frame:RegisterEvent(eventName)
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            InitializeDatabase()
            if IsLoggedIn and IsLoggedIn() then
                PerformLoginInitialization()
            end
        elseif loadedAddon == "Blizzard_ChallengesUI" then
            HookChallengesFrame()
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        PerformLoginInitialization()
        return
    end

    -- Challenge mode event tracking - these fire immediately on entering/leaving M+
    if event == "CHALLENGE_MODE_START" then
        ui.inChallengeMode = true
        ui.completedRun = nil
        ui.lastRunState = nil
        ResetDeathLog()
        ResetEnemyForcesCalibration()
        ObserveOwnedKeystone(false)
        SyncGroupDeathLogFromUnits()
        RefreshMythicUI()
        return
    end

    if event == "CHALLENGE_MODE_COMPLETED" then
        SyncGroupDeathLogFromUnits()
        CaptureCompletedRunState()
        ui.inChallengeMode = false
        -- Check shortly after completion so the rerolled key can be observed.
        ScheduleOwnedKeystoneObservation(true, 3)
        if C_Timer and C_Timer.After then
            C_Timer.After(2, RefreshCompletedRunTimingFromAPI)
        end
        RefreshMythicUI()
        return
    end

    if event == "CHALLENGE_MODE_RESET" then
        ui.inChallengeMode = false
        ui.lastRunState = nil
        ui.completedRun = nil
        ResetDeathLog()
        ResetEnemyForcesCalibration()
        ScheduleOwnedKeystoneObservation(true, 1)
        RefreshMythicUI()
        return
    end

    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, subEvent, _, _, _, _, _, destGUID, destName, destFlags = CombatLogGetCurrentEventInfo()
        if subEvent == "UNIT_DIED" then
            RecordGroupDeath(destGUID, destName, destFlags)
        end
        return
    end

    if event == "GROUP_ROSTER_UPDATE" or event == "UNIT_FLAGS" or event == "PLAYER_DEAD" then
        SyncGroupDeathLogFromUnits()
        return
    end

    if event == "PLAYER_ENTERING_WORLD"
        or event == "PLAYER_REGEN_ENABLED"
        or event == "SCENARIO_CRITERIA_UPDATE" then
        if event == "PLAYER_ENTERING_WORLD" and not IsInMythicDungeonInstance() then
            ui.completedRun = nil
            ui.lastRunState = nil
            ui.inChallengeMode = false
            ResetEnemyForcesCalibration()
        end
        if event == "PLAYER_ENTERING_WORLD" then
            ScheduleOwnedKeystoneObservation(false, 1)
        end
        if event == "PLAYER_REGEN_ENABLED" then
            FlushDeferredChatMessages()
        end
        SyncGroupDeathLogFromUnits()
        RefreshMythicUI()
        return
    end

    HandleChatMessage(event, ...)
end)
