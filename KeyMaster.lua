local addonName = ...
local KMNS = _G.KeyMasterNS or {}


local floor = math.floor
local max = math.max
local min = math.min
local band = bit and bit.band or bit32 and bit32.band
local strfind = string.find
local strlower = string.lower
local strmatch = string.match
local strtrim = strtrim or function(s) return (s:gsub("^%s*(.-)%s*$", "%1")) end
local IsChallengeModeRunActive
local IsInMythicDungeonInstance
local RefreshMythicUI

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

local RUNTIME_EVENTS = {
    "CHAT_MSG_ADDON",
    "GUILD_ROSTER_UPDATE",
    "PLAYER_LOGIN",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_LOGOUT",
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
    "CHAT_MSG_OFFICER",
}

local runtimeEventsRegistered = false
local databaseSanitized = false
local runtimeRegistrationDeferred = false

for _, eventName in ipairs(RUNTIME_EVENTS) do
    if not (frame.IsEventRegistered and frame:IsEventRegistered(eventName)) then
        frame:RegisterEvent(eventName)
    end
end
runtimeEventsRegistered = true
runtimeRegistrationDeferred = false

local function RegisterRuntimeEvents()
    -- Runtime events are registered at load time to avoid protected RegisterEvent calls later.
    runtimeRegistrationDeferred = false
    return true
end

local REPLY_PREFIX = _G.KeyMasterNS and _G.KeyMasterNS.REPLY_PREFIX or "KSM:"
local KEYSTONE_ITEM_IDS = _G.KeyMasterNS and _G.KeyMasterNS.KEYSTONE_ITEM_IDS or { [180653] = true, [158923] = true, [151086] = true }
local KEYSTONE_BAG_SLOTS = _G.KeyMasterNS and _G.KeyMasterNS.KEYSTONE_BAG_SLOTS or { Enum.BagIndex.Backpack, Enum.BagIndex.Bag_1, Enum.BagIndex.Bag_2, Enum.BagIndex.Bag_3, Enum.BagIndex.Bag_4 }
local KSM_PORTAL_SPELL_IDS = _G.KeyMasterNS and _G.KeyMasterNS.KSM_PORTAL_SPELL_IDS or {}
local KSM_PORTAL_SPELL_IDS_HORDE = _G.KeyMasterNS and _G.KeyMasterNS.KSM_PORTAL_SPELL_IDS_HORDE or {}
local KEYS_TEXT_COMMAND = _G.KeyMasterNS and _G.KeyMasterNS.KEYS_TEXT_COMMAND or "!keys"
local KEY_TEXT_COMMAND = _G.KeyMasterNS and _G.KeyMasterNS.KEY_TEXT_COMMAND or "!key"
local SCORE_TEXT_COMMAND = _G.KeyMasterNS and _G.KeyMasterNS.SCORE_TEXT_COMMAND or "!score"
local SCORES_TEXT_COMMAND = _G.KeyMasterNS and _G.KeyMasterNS.SCORES_TEXT_COMMAND or "!scores"
local BEST_TEXT_COMMAND = _G.KeyMasterNS and _G.KeyMasterNS.BEST_TEXT_COMMAND or "!best"
local KSM_ADDON_PREFIX = _G.KeyMasterNS and _G.KeyMasterNS.KSM_ADDON_PREFIX or "KeyMaster"
local KSM_GUILD_SYNC_VERSION = _G.KeyMasterNS and _G.KeyMasterNS.KSM_GUILD_SYNC_VERSION or "g1"
local KSM_GUILD_SYNC_REQUEST = _G.KeyMasterNS and _G.KeyMasterNS.KSM_GUILD_SYNC_REQUEST or "req1"
local ASTRAL_KEYS_PREFIX = _G.KeyMasterNS and _G.KeyMasterNS.ASTRAL_KEYS_PREFIX or "AstralKeys"
local DETAILS_OPENRAID_PREFIX = _G.KeyMasterNS and _G.KeyMasterNS.DETAILS_OPENRAID_PREFIX or "LRS"
local DETAILS_OPENRAID_KEYSTONE_REQUEST_PREFIX = _G.KeyMasterNS and _G.KeyMasterNS.DETAILS_OPENRAID_KEYSTONE_REQUEST_PREFIX or "J"
local DETAILS_OPENRAID_KEYSTONE_DATA_PREFIX = _G.KeyMasterNS and _G.KeyMasterNS.DETAILS_OPENRAID_KEYSTONE_DATA_PREFIX or "K"
local CLASS_ID_TO_FILE = _G.KeyMasterNS and _G.KeyMasterNS.CLASS_ID_TO_FILE or {}
local CHALLENGERS_PERIL_AFFIX_ID = _G.KeyMasterNS and _G.KeyMasterNS.CHALLENGERS_PERIL_AFFIX_ID or 152
local BREAK_TIMER_BLUE = _G.KeyMasterNS and _G.KeyMasterNS.BREAK_TIMER_BLUE or { 0.15, 0.55, 1.00, 0.90 }
local DEFAULT_DB = _G.KeyMasterNS and _G.KeyMasterNS.DEFAULT_DB or {
    ui = {
        enabled = true,
        hideTrackerInMythicPlus = true,
        hideOfflineGuild = false,
        locked = true,
        hidden = false,
        scale = 1,
        point = { "TOPRIGHT", "UIParent", "TOPRIGHT", -24, -210 },
    },
    guild = {
        members = {},
    },
    characters = {},
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
    ksmFrame = nil,
    ksmMainTab = nil,
    ksmPartyTab = nil,
    ksmGuildTab = nil,
    ksmRecentsTab = nil,
    ksmWarbandTab = nil,
    ksmMainContent = nil,
    ksmPartyContent = nil,
    ksmGuildContent = nil,
    ksmRecentsContent = nil,
    ksmWarbandContent = nil,
    ksmPartyLines = {},
    ksmPartyRows = {},
    ksmGuildLines = {},
    ksmGuildRows = {},
    ksmRecentsLines = {},
    ksmRecentsRows = {},
    ksmWarbandLines = {},
    ksmWarbandRows = {},
    ksmGuildPage = 1,
    ksmGuildTotalPages = 1,
    ksmGuildPrevButton = nil,
    ksmGuildNextButton = nil,
    ksmGuildPageText = nil,
    ksmRecentsPage = 1,
    ksmRecentsTotalPages = 1,
    ksmRecentsPrevButton = nil,
    ksmRecentsNextButton = nil,
    ksmRecentsPageText = nil,
    ksmWarbandPage = 1,
    ksmWarbandTotalPages = 1,
    ksmWarbandPrevButton = nil,
    ksmWarbandNextButton = nil,
    ksmWarbandPageText = nil,
    ksmGuildHideOfflineCheck = nil,
    ksmHideOffline = false,
    ksmPortalButtons = {},
    ksmActiveTab = "main",
}

local ENEMY_FORCES_TOTAL_UNITS_BY_MAP_ID = _G.KeyMasterNS and _G.KeyMasterNS.ENEMY_FORCES_TOTAL_UNITS_BY_MAP_ID or {}

local ENEMY_FORCES_TOTAL_UNITS_BY_DUNGEON = _G.KeyMasterNS and _G.KeyMasterNS.ENEMY_FORCES_TOTAL_UNITS_BY_DUNGEON or {}

local CHAT_EVENTS = _G.KeyMasterNS and _G.KeyMasterNS.CHAT_EVENTS or {}

local CHAT_EVENT_TO_CHANNEL = _G.KeyMasterNS and _G.KeyMasterNS.CHAT_EVENT_TO_CHANNEL or {}

local MAX_DEFERRED_CHAT_MESSAGES = _G.KeyMasterNS and _G.KeyMasterNS.MAX_DEFERRED_CHAT_MESSAGES or 10
local MergeNormalizedNameStore
local TrimStoreByEntryLimit
local MAX_GUILD_MEMBER_ENTRIES = 800
local MAX_CHARACTER_ENTRIES = 120

local function ClampNumber(value, minimum, maximum, fallback)
    local n = tonumber(value)
    if not n then
        return fallback
    end
    if minimum and n < minimum then
        n = minimum
    end
    if maximum and n > maximum then
        n = maximum
    end
    return n
end


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

    local normalizedName = strtrim(name)
    if normalizedName == "" then
        return "Unknown"
    end

    -- Storage must not synthesize realm suffixes from local context.
    -- Keep the incoming name as authoritative; only normalize whitespace around an existing suffix.
    local baseName, existingRealm = normalizedName:match("^([^-]+)%-(.+)$")
    if baseName and existingRealm then
        local realmTag = existingRealm:gsub("%s+", "")
        if realmTag ~= "" then
            return string.format("%s-%s", strtrim(baseName), realmTag)
        end
        return strtrim(baseName)
    end

    return normalizedName
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

    if type(KeyMasterDB.ui.hideOfflineGuild) ~= "boolean" then
        KeyMasterDB.ui.hideOfflineGuild = DEFAULT_DB.ui.hideOfflineGuild
    end

    if type(KeyMasterDB.ui.locked) ~= "boolean" then
        KeyMasterDB.ui.locked = DEFAULT_DB.ui.locked
    end

    if type(KeyMasterDB.ui.hidden) ~= "boolean" then
        KeyMasterDB.ui.hidden = DEFAULT_DB.ui.hidden
    end

    if type(KeyMasterDB.guild) ~= "table" then
        KeyMasterDB.guild = CopyDefaults(DEFAULT_DB.guild, {})
    end

    if type(KeyMasterDB.guild.members) ~= "table" then
        KeyMasterDB.guild.members = {}
    end

    if type(KeyMasterDB.characters) ~= "table" then
        KeyMasterDB.characters = {}
    end

    if not databaseSanitized and type(MergeNormalizedNameStore) == "function" then
        KeyMasterDB.guild.members = MergeNormalizedNameStore(KeyMasterDB.guild.members)
        KeyMasterDB.characters = MergeNormalizedNameStore(KeyMasterDB.characters)
        TrimStoreByEntryLimit(KeyMasterDB.guild.members, MAX_GUILD_MEMBER_ENTRIES)
        TrimStoreByEntryLimit(KeyMasterDB.characters, MAX_CHARACTER_ENTRIES)
        databaseSanitized = true
    end

    -- Legacy cleanup: debugLog should not persist in SavedVariables.
    if KeyMasterDB.debugLog ~= nil then
        KeyMasterDB.debugLog = nil
    end

    return KeyMasterDB
end

local function GetGuildMemberStore()
    local db = InitializeDatabase()
    db.guild = db.guild or {}
    db.guild.members = db.guild.members or {}
    return db.guild.members
end

local function GetOwnCharacterStore()
    local db = InitializeDatabase()
    db.characters = db.characters or {}
    return db.characters
end

local function BuildSanitizedStoreEntry(normalizedName, rawEntry)
    if type(normalizedName) ~= "string" or normalizedName == "" then
        return nil
    end
    if type(rawEntry) ~= "table" then
        return nil
    end

    local mapID = ClampNumber(rawEntry.mapID, 0, 20000, 0) or 0
    local keyLevel = ClampNumber(rawEntry.keyLevel, 0, 50, 0) or 0
    local rating = ClampNumber(rawEntry.rating, 0, 20000, 0) or 0
    local updatedAt = ClampNumber(rawEntry.updatedAt, 0, nil, 0) or 0
    local hiddenInRecents = rawEntry.hiddenInRecents == true

    -- Keep stores key-focused: drop entries that do not have a valid keystone.
    if mapID <= 0 or keyLevel <= 0 then
        return nil
    end

    local classFile = type(rawEntry.class) == "string" and rawEntry.class or nil
    if classFile and #classFile > 24 then
        classFile = classFile:sub(1, 24)
    end

    local source = nil
    if type(rawEntry.source) == "string" then
        source = strlower(rawEntry.source)
        if source == "manual-seed" then
            source = nil
        elseif #source > 32 then
            source = source:sub(1, 32)
        end
    end

    local sanitized = {
        name = normalizedName,
        mapID = mapID,
        keyLevel = keyLevel,
        rating = rating,
        updatedAt = updatedAt,
    }

    if classFile and classFile ~= "" then
        sanitized.class = classFile
    end
    if source and source ~= "" then
        sanitized.source = source
    end
    if hiddenInRecents then
        sanitized.hiddenInRecents = true
    end

    return sanitized
end

TrimStoreByEntryLimit = function(store, maxEntries)
    if type(store) ~= "table" then
        return
    end
    local limit = tonumber(maxEntries) or 0
    if limit <= 0 then
        return
    end

    local entries = {}
    local count = 0
    for key, entry in pairs(store) do
        count = count + 1
        entries[#entries + 1] = {
            key = key,
            updatedAt = type(entry) == "table" and (tonumber(entry.updatedAt) or 0) or 0,
            keyLevel = type(entry) == "table" and (tonumber(entry.keyLevel) or 0) or 0,
        }
    end

    if count <= limit then
        return
    end

    table.sort(entries, function(left, right)
        if left.updatedAt ~= right.updatedAt then
            return left.updatedAt > right.updatedAt
        end
        if left.keyLevel ~= right.keyLevel then
            return left.keyLevel > right.keyLevel
        end
        return tostring(left.key) < tostring(right.key)
    end)

    for index = limit + 1, #entries do
        store[entries[index].key] = nil
    end
end

local function NormalizeRealmTag(realm)
    if type(realm) ~= "string" or realm == "" then
        return nil
    end

    local function CollapseTrailingRepeatedSegment(token)
        if type(token) ~= "string" then
            return token
        end

        local length = #token
        if length < 6 then
            return token
        end

        for unitLength = 3, math.floor(length / 2) do
            local unit = token:sub(length - unitLength + 1)
            if unit ~= "" then
                local repeats = 0
                local cursor = length
                while cursor - unitLength + 1 >= 1 and token:sub(cursor - unitLength + 1, cursor) == unit do
                    repeats = repeats + 1
                    cursor = cursor - unitLength
                end

                if repeats >= 2 then
                    local prefix = token:sub(1, cursor)
                    if prefix ~= "" and prefix ~= unit then
                        return prefix
                    end
                    return unit
                end
            end
        end

        return token
    end

    local function CollapseRepeatedRealmWord(token)
        if type(token) ~= "string" then
            return token
        end

        local length = #token
        if length < 6 then
            return token
        end

        for unitLength = 3, math.floor(length / 2) do
            if (length % unitLength) == 0 then
                local unit = token:sub(1, unitLength)
                local repeats = length / unitLength
                if repeats >= 2 then
                    local rebuilt = ""
                    for _ = 1, repeats do
                        rebuilt = rebuilt .. unit
                    end
                    if rebuilt == token then
                        return unit
                    end
                end
            end
        end

        return token
    end

    local normalized = realm:gsub("%f[%a][Ss][Ee][Rr][Vv][Ee][Rr]%f[%A]", "")
    normalized = normalized:gsub("[%s_]+", "")
    normalized = normalized:gsub("[Ss][Ee][Rr][Vv][Ee][Rr]$", "")
    normalized = normalized:gsub("^-+", ""):gsub("-+$", "")
    normalized = CollapseTrailingRepeatedSegment(normalized)
    normalized = CollapseRepeatedRealmWord(normalized)
    if normalized == "" then
        return nil
    end

    return normalized
end

local function GetCurrentRealmTag()
    if UnitFullName then
        local _, unitRealm = UnitFullName("player")
        local normalizedUnitRealm = NormalizeRealmTag(unitRealm)
        if normalizedUnitRealm then
            return normalizedUnitRealm
        end
    end

    if GetRealmName then
        return NormalizeRealmTag(GetRealmName())
    end

    return nil
end

local function CollapseRepeatedRealmSuffix(name)
    if type(name) ~= "string" then
        return nil
    end

    -- Defensive cap: malformed names can explode into repeated realm chains and stall the UI.
    if #name > 128 then
        name = name:sub(1, 128)
    end

    local baseName, realmSuffix = name:match("^([^-]+)%-(.+)$")
    if not baseName or not realmSuffix then
        return name
    end

    local normalizedRealmSuffix = realmSuffix:gsub("[%s%-]+", "")
    if normalizedRealmSuffix == "" then
        return baseName
    end

    -- Some inputs can include display-style realms with a hyphen (e.g. Earthen-Ring).
    -- Normalize the full suffix so we keep EarthenRing instead of truncating to Earthen.
    local canonicalRealm = NormalizeRealmTag(normalizedRealmSuffix)
    if not canonicalRealm then
        return string.format("%s-%s", baseName, normalizedRealmSuffix)
    end

    return string.format("%s-%s", baseName, canonicalRealm)
end

local function NormalizeLoosePlayerName(name)
    if type(name) ~= "string" then
        return nil
    end

    local cleaned = strtrim(name)
    if cleaned == "" then
        return nil
    end

    cleaned = cleaned:gsub("%s*%-%s*", "-")

    local baseName, realmSuffix = cleaned:match("^([^-]+)%-(.+)$")
    if baseName and realmSuffix then
        baseName = strtrim(baseName)
        realmSuffix = strtrim(realmSuffix)
        if baseName == "" then
            return nil
        end

        -- Preserve full realm identity even when source text includes hyphenated realm display forms.
        local canonicalRealm = NormalizeRealmTag(realmSuffix:gsub("[%s%-]+", ""))

        if not canonicalRealm then
            return baseName
        end

        return string.format("%s-%s", baseName, canonicalRealm)
    end

    -- Character names cannot contain spaces; do not synthesize cross-realm names from loose text.
    if cleaned:find("%s") then
        return nil
    end

    return cleaned
end

local function GetNormalizedPlayerName(name)
    local trimmed = NormalizeLoosePlayerName(name)
    if type(trimmed) ~= "string" or trimmed == "" then
        return nil
    end

    if #trimmed > 128 then
        trimmed = trimmed:sub(1, 128)
    end

    if #trimmed > 80 then
        return nil
    end

    return trimmed
end

MergeNormalizedNameStore = function(store)
    if type(store) ~= "table" then
        return {}
    end

    local merged = {}

    local function ShouldReplaceEntry(existing, candidate)
        if type(existing) ~= "table" then
            return true
        end
        if type(candidate) ~= "table" then
            return false
        end

        local existingUpdated = tonumber(existing.updatedAt) or 0
        local candidateUpdated = tonumber(candidate.updatedAt) or 0
        if candidateUpdated ~= existingUpdated then
            return candidateUpdated > existingUpdated
        end

        local existingKey = tonumber(existing.keyLevel) or 0
        local candidateKey = tonumber(candidate.keyLevel) or 0
        if candidateKey ~= existingKey then
            return candidateKey > existingKey
        end

        local existingRating = tonumber(existing.rating) or 0
        local candidateRating = tonumber(candidate.rating) or 0
        return candidateRating > existingRating
    end

    for rawKey, rawEntry in pairs(store) do
        if type(rawKey) == "string" and type(rawEntry) == "table" then
            local normalizedKey = GetNormalizedPlayerName(rawEntry.name) or GetNormalizedPlayerName(rawKey)
            if type(normalizedKey) == "string" and normalizedKey ~= "" then
                local candidate = BuildSanitizedStoreEntry(normalizedKey, rawEntry)

                if candidate and ShouldReplaceEntry(merged[normalizedKey], candidate) then
                    merged[normalizedKey] = candidate
                end
            end
        end
    end

    return merged
end

local function SaveGuildMemberData(name, data)
    local normalized = GetNormalizedPlayerName(name)
    if not normalized or type(data) ~= "table" then
        return
    end

    local store = GetGuildMemberStore()
    local now = GetServerTime and GetServerTime() or time()
    local candidate = BuildSanitizedStoreEntry(normalized, data) or {}
    if not next(candidate) then
        store[normalized] = nil
        local shortName = normalized:match("^([^-]+)")
        if shortName and shortName ~= normalized then
            store[shortName] = nil
        end
        return
    end
    candidate.updatedAt = now
    candidate.name = normalized
    store[normalized] = candidate
    TrimStoreByEntryLimit(store, MAX_GUILD_MEMBER_ENTRIES)
end

local function SaveOwnCharacterData(name, data)
    local normalized = GetNormalizedPlayerName(name)
    if not normalized or type(data) ~= "table" then
        return
    end

    local store = GetOwnCharacterStore()
    local now = GetServerTime and GetServerTime() or time()
    local candidate = BuildSanitizedStoreEntry(normalized, data) or {}
    if not next(candidate) then
        store[normalized] = nil
        local shortName = normalized:match("^([^-]+)")
        if shortName and shortName ~= normalized then
            store[shortName] = nil
        end
        return
    end
    candidate.updatedAt = now
    candidate.name = normalized
    store[normalized] = candidate
    TrimStoreByEntryLimit(store, MAX_CHARACTER_ENTRIES)
end

local function GetGuildMemberData(name)
    local normalized = GetNormalizedPlayerName(name)
    if not normalized then
        return nil
    end

    local store = GetGuildMemberStore()
    local entry = store[normalized]
    if entry then
        return entry
    end

    local shortName = normalized:match("^([^-]+)")
    if shortName and shortName ~= normalized then
        local legacyEntry = store[shortName]
        if type(legacyEntry) == "table" then
            store[normalized] = legacyEntry
            store[shortName] = nil
            legacyEntry.name = normalized
            return legacyEntry
        end
    end

    return nil
end

local function InvitePlayerByName(name)
    local normalized = GetNormalizedPlayerName(name)
    if type(normalized) ~= "string" or normalized == "" then
        return false
    end

    if C_PartyInfo and C_PartyInfo.InviteUnit then
        local ok = pcall(C_PartyInfo.InviteUnit, normalized)
        if ok then
            return true
        end
    end

    if InviteUnit then
        local ok = pcall(InviteUnit, normalized)
        if ok then
            return true
        end
    end

    return false
end

local function RemoveRecentEntryByName(name)
    local normalized = GetNormalizedPlayerName(name)
    if type(normalized) ~= "string" or normalized == "" then
        return 0
    end

    local store = GetGuildMemberStore()
    local hidden = 0
    for key, entry in pairs(store) do
        local normalizedKey = GetNormalizedPlayerName(key) or key
        local normalizedEntryName = type(entry) == "table" and GetNormalizedPlayerName(entry.name) or nil
        if (normalizedKey == normalized or normalizedEntryName == normalized) and type(entry) == "table" then
            entry.hiddenInRecents = true
            hidden = hidden + 1
        end
    end

    return hidden
end

local function GetPlayerClassFile(unitToken)
    if UnitClass then
        local _, classFile = UnitClass(unitToken or "player")
        if type(classFile) == "string" and classFile ~= "" then
            return classFile
        end
    end

    return "PRIEST"
end

local function GetClassColorInfo(classFile)
    if type(classFile) ~= "string" or classFile == "" then
        return 1, 1, 1
    end

    if C_ClassColor and C_ClassColor.GetClassColor then
        local color = C_ClassColor.GetClassColor(classFile)
        if color then
            return color.r or 1, color.g or 1, color.b or 1
        end
    end

    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if color then
        return color.r or 1, color.g or 1, color.b or 1
    end

    return 1, 1, 1
end

local function ApplyClassIcon(texture, classFile)
    if not texture then
        return
    end

    texture:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile or ""]
    if coords then
        texture:SetTexCoord((unpack or table.unpack)(coords))
    else
        texture:SetTexCoord(0, 1, 0, 1)
    end
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

    for _, bagID in ipairs((_G.KeyMasterNS and _G.KeyMasterNS.KEYSTONE_BAG_SLOTS) or { Enum.BagIndex.Backpack, Enum.BagIndex.Bag_1, Enum.BagIndex.Bag_2, Enum.BagIndex.Bag_3, Enum.BagIndex.Bag_4 }) do
        local slotCount = C_Container.GetContainerNumSlots(bagID) or 0
        for slotIndex = 1, slotCount do
            local itemID = C_Container.GetContainerItemID(bagID, slotIndex)
            local bagLink = C_Container.GetContainerItemLink and C_Container.GetContainerItemLink(bagID, slotIndex) or nil
            if (((_G.KeyMasterNS and _G.KeyMasterNS.KEYSTONE_ITEM_IDS) or { [180653] = true, [158923] = true, [151086] = true })[itemID]) or IsKeystoneLink(bagLink) then
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
    if (now - lastMismatchToastAt) < ((_G.KeyMasterNS and _G.KeyMasterNS.MISMATCH_TOAST_COOLDOWN_SECONDS) or 2) then
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

    local mapID, keyLevel = GetOwnedKeystoneSnapshot()
    if type(keyLevel) == "number" and keyLevel > 0 then
        local dungeonLabel = (type(mapID) == "number" and mapID > 0 and FormatDungeonLabel(mapID)) or "Unknown Dungeon"
        return string.format("%s +%d %s", REPLY_PREFIX, keyLevel, dungeonLabel)
    end

    return string.format("%s Keystone unavailable", REPLY_PREFIX)
end

local function GetOwnedKeystoneSnapshot()
    local mapID = GetOwnedKeystoneMapID()
    local keyLevel = GetOwnedKeystoneLevel()

    if (type(mapID) ~= "number" or mapID <= 0) or (type(keyLevel) ~= "number" or keyLevel <= 0) then
        local keyLink = GetOwnedKeystoneLink()
        local parsedMapID, parsedLevel = KMNS.ParseKeystoneFromMessage(keyLink)
        mapID = (type(mapID) == "number" and mapID > 0) and mapID or parsedMapID
        keyLevel = (type(keyLevel) == "number" and keyLevel > 0) and keyLevel or parsedLevel
    end

    if type(mapID) ~= "number" or mapID <= 0 or type(keyLevel) ~= "number" or keyLevel <= 0 then
        return nil, nil
    end

    return mapID, keyLevel
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
    local currentSnapshotKey = KMNS.BuildKeystoneSnapshotKey(mapID, keyLevel)

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
        BroadcastOwnGuildSnapshot()
        return
    end

    AnnounceNewOwnedKeystone(mapID, keyLevel)
    BroadcastOwnGuildSnapshot()
end

local function BuildActiveSyncChannels()
    local channels = {}
    local seen = {}

    local function AddChannel(channel)
        if seen[channel] then
            return
        end

        seen[channel] = true
        table.insert(channels, channel)
    end

    if KMNS.IsPlayerInGuildSafe() then
        AddChannel("GUILD")
    end

    local inInstanceGroup = IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
    if inInstanceGroup then
        AddChannel("INSTANCE_CHAT")
    elseif IsInRaid and IsInRaid() then
        AddChannel("RAID")
    elseif IsInGroup and IsInGroup() then
        AddChannel("PARTY")
    end

    return channels
end

local function ResolveCurrentPlayerMythicPlusScore()
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

local function BuildOwnGuildSyncMessage()
    local mapID, keyLevel = GetOwnedKeystoneSnapshot()
    local score = ResolveCurrentPlayerMythicPlusScore() or 0
    local classFile = GetPlayerClassFile("player")

    return table.concat({
        KSM_GUILD_SYNC_VERSION,
        classFile,
        tostring(mapID or 0),
        tostring(keyLevel or 0),
        tostring(floor(score + 0.5)),
    }, "\t")
end

local function PersistOwnGuildSnapshot()
    local shortName = UnitName and UnitName("player")
    if type(shortName) ~= "string" or shortName == "" then
        return false
    end

    local fullName = shortName
    if UnitFullName then
        local unitName, unitRealm = UnitFullName("player")
        if type(unitName) == "string" and unitName ~= "" then
            local trimmedUnitName = strtrim(unitName)
            local normalizedRealm = NormalizeRealmTag(unitRealm)
            if trimmedUnitName ~= "" and normalizedRealm and normalizedRealm ~= "" then
                fullName = string.format("%s-%s", trimmedUnitName, normalizedRealm)
            elseif trimmedUnitName ~= "" then
                fullName = trimmedUnitName
            end
        end
    end

    if fullName == shortName then
        local currentRealm = GetCurrentRealmTag()
        if currentRealm and currentRealm ~= "" then
            fullName = string.format("%s-%s", shortName, currentRealm)
        end
    end

    local canonicalFullName = GetNormalizedPlayerName(fullName) or fullName
    local canonicalShortName = GetNormalizedPlayerName(shortName) or shortName

    local ownStore = GetOwnCharacterStore()
    local previousOwn = ownStore[canonicalFullName]
    if type(previousOwn) ~= "table" then
        previousOwn = ownStore[canonicalShortName]
    end

    local snapshot = {
        class = GetPlayerClassFile("player"),
        mapID = GetOwnedKeystoneMapID() or 0,
        keyLevel = GetOwnedKeystoneLevel() or 0,
        rating = floor((ResolveCurrentPlayerMythicPlusScore() or 0) + 0.5),
        source = "keystonemastery",
    }

    -- Keep last known key/rating when the API is temporarily empty during login/logout transitions.
    if (tonumber(snapshot.mapID) or 0) <= 0 and type(previousOwn) == "table" and (tonumber(previousOwn.mapID) or 0) > 0 then
        snapshot.mapID = tonumber(previousOwn.mapID) or snapshot.mapID
    end
    if (tonumber(snapshot.keyLevel) or 0) <= 0 and type(previousOwn) == "table" and (tonumber(previousOwn.keyLevel) or 0) > 0 then
        snapshot.keyLevel = tonumber(previousOwn.keyLevel) or snapshot.keyLevel
    end
    if (tonumber(snapshot.rating) or 0) <= 0 and type(previousOwn) == "table" and (tonumber(previousOwn.rating) or 0) > 0 then
        snapshot.rating = tonumber(previousOwn.rating) or snapshot.rating
    end

    SaveGuildMemberData(canonicalFullName, snapshot)
    SaveOwnCharacterData(canonicalFullName, snapshot)

    -- Keep own character storage on canonical full name only.
    if canonicalShortName ~= canonicalFullName then
        local guildStore = GetGuildMemberStore()
        local ownCharacterStore = GetOwnCharacterStore()
        guildStore[canonicalShortName] = nil
        ownCharacterStore[canonicalShortName] = nil
    end

    return true
end

local function QueueOwnSnapshotPersistRetry(delaySeconds)
    if type(delaySeconds) ~= "number" or delaySeconds <= 0 then
        PersistOwnGuildSnapshot()
        return
    end

    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(delaySeconds, function()
            PersistOwnGuildSnapshot()
        end)
    else
        PersistOwnGuildSnapshot()
    end
end

local function BroadcastOwnGuildSnapshot()
    PersistOwnGuildSnapshot()

    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then
        return
    end

    local channels = BuildActiveSyncChannels()
    if #channels == 0 then
        return
    end

    local payload = BuildOwnGuildSyncMessage()
    local sendAddonMessageSafe = KMNS and KMNS.SendAddonMessageSafe
    for _, channel in ipairs(channels) do
        if type(sendAddonMessageSafe) == "function" then
            sendAddonMessageSafe(KSM_ADDON_PREFIX, payload, channel)
        else
            pcall(C_ChatInfo.SendAddonMessage, KSM_ADDON_PREFIX, payload, channel)
        end
    end
end

local function BuildSyncContext()
    return {
        KSM_ADDON_PREFIX = KSM_ADDON_PREFIX,
        KSM_GUILD_SYNC_VERSION = KSM_GUILD_SYNC_VERSION,
        KSM_GUILD_SYNC_REQUEST = KSM_GUILD_SYNC_REQUEST,
        ASTRAL_KEYS_PREFIX = ASTRAL_KEYS_PREFIX,
        DETAILS_OPENRAID_PREFIX = DETAILS_OPENRAID_PREFIX,
        DETAILS_OPENRAID_KEYSTONE_REQUEST_PREFIX = DETAILS_OPENRAID_KEYSTONE_REQUEST_PREFIX,
        DETAILS_OPENRAID_KEYSTONE_DATA_PREFIX = DETAILS_OPENRAID_KEYSTONE_DATA_PREFIX,
        CLASS_ID_TO_FILE = CLASS_ID_TO_FILE,
        IsPlayerInGuildSafe = KMNS.IsPlayerInGuildSafe,
        GetNormalizedPlayerName = GetNormalizedPlayerName,
        PrintLocal = PrintLocal,
        BroadcastOwnGuildSnapshot = BroadcastOwnGuildSnapshot,
        SaveGuildMemberData = SaveGuildMemberData,
        RefreshKSMWindowIfVisible = RefreshKSMWindowIfVisible,
    }
end

local function RequestGuildSnapshots()
    local syncModule = _G.KeyMasterNS and _G.KeyMasterNS.Sync
    if syncModule and syncModule.RequestGuildSnapshots then
        syncModule.RequestGuildSnapshots(BuildSyncContext())
    end
end

local function RequestGuildKeysFromAllSources(force, includeExternal)
    local syncModule = _G.KeyMasterNS and _G.KeyMasterNS.Sync
    if syncModule and syncModule.RequestGuildKeysFromAllSources then
        return syncModule.RequestGuildKeysFromAllSources(BuildSyncContext(), force, includeExternal)
    end
    return false
end

local function HandleAddonMessage(prefix, message, channel, sender)
    local syncModule = _G.KeyMasterNS and _G.KeyMasterNS.Sync
    if syncModule and syncModule.HandleAddonMessage then
        syncModule.HandleAddonMessage(BuildSyncContext(), prefix, message, channel, sender)
    end
end

local BuildRunStateContext

local function ScheduleOwnedKeystoneObservation(allowAnnounce, delaySeconds)
    local runStateModule = _G.KeyMasterNS and _G.KeyMasterNS.RunState
    if runStateModule and runStateModule.ScheduleOwnedKeystoneObservation then
        runStateModule.ScheduleOwnedKeystoneObservation(BuildRunStateContext(), allowAnnounce, delaySeconds)
    else
        if not (C_Timer and C_Timer.After) then
            ObserveOwnedKeystone(allowAnnounce)
            return
        end

        local delay = type(delaySeconds) == "number" and max(0, delaySeconds) or 0
        C_Timer.After(delay, function()
            ObserveOwnedKeystone(allowAnnounce)
        end)
    end
end

local function GetMythicPlusScore()
    return ResolveCurrentPlayerMythicPlusScore()
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

    local function ResolveLookupScore(result1, result2)
        local score

        if type(result1) == "table" then
            score = result1.mapScore or result1.score or result1.rating or result1.bestRunScore or result1.currentSeasonScore or result1.overallScore
        elseif type(result2) == "table" then
            score = result2.mapScore or result2.score or result2.rating or result2.bestRunScore or result2.currentSeasonScore or result2.overallScore
        end

        score = tonumber(score)
        if type(score) == "number" and score > 0 then
            return score
        end

        return nil
    end

    for _, mapID in ipairs(maps) do
        local ok, result1, result2 = pcall(C_MythicPlus[funcName], mapID)
        if ok then
            local level = ResolveBestLevel(result1, result2)
            if type(level) == "number" and level > 0 then
                local entry = {
                    level = level,
                    mapID = mapID,
                    score = ResolveLookupScore(result1, result2),
                }

                if not best then
                    best = entry
                elseif type(entry.score) == "number" and type(best.score) == "number" and entry.score ~= best.score then
                    if entry.score > best.score then
                        best = entry
                    end
                elseif type(entry.score) == "number" and type(best.score) ~= "number" then
                    best = entry
                elseif (entry.level or 0) > (best.level or 0) then
                    best = entry
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

    local function ResolveRunScore(run)
        if type(run) ~= "table" then
            return nil
        end

        local score = run.mapScore
            or run.score
            or run.rating
            or run.bestRunScore
            or run.currentSeasonScore
            or run.overallScore
            or run.dungeonScore

        score = tonumber(score)
        if type(score) == "number" and score > 0 then
            return score
        end

        return nil
    end

    local function IsWeeklyRun(run)
        if type(run) ~= "table" then
            return false
        end

        return run.thisWeek == true
            or run.currentWeek == true
            or run.completedThisWeek == true
            or run.isThisWeek == true
    end

    local function IsBetterRun(candidate, current)
        if not candidate then
            return false
        end

        if not current then
            return true
        end

        if type(candidate.score) == "number" and type(current.score) == "number" then
            if candidate.score ~= current.score then
                return candidate.score > current.score
            end
        elseif type(candidate.score) == "number" then
            return true
        elseif type(current.score) == "number" then
            return false
        end

        return (candidate.level or 0) > (current.level or 0)
    end

    for _, run in ipairs(history) do
        if run and run.completed ~= false then
            local level = ResolveRunLevel(run)
            local mapID = ResolveRunMapID(run)
            if level then
                local entry = {
                    level = level,
                    mapID = mapID,
                    score = ResolveRunScore(run),
                }

                if IsBetterRun(entry, seasonBest) then
                    seasonBest = entry
                end

                if IsWeeklyRun(run) and IsBetterRun(entry, weekBest) then
                    weekBest = entry
                end
            end
        end
    end

    local mapWeekBest = GetBestRunFromMapLookup("GetWeeklyBestForMap")
    local mapSeasonBest = GetBestRunFromMapLookup("GetSeasonBestForMap")

    if IsBetterRun(mapWeekBest, weekBest) then
        weekBest = mapWeekBest
    end
    if IsBetterRun(mapSeasonBest, seasonBest) then
        seasonBest = mapSeasonBest
    end

    return weekBest, seasonBest
end

local function FormatBestRun(bestRun)
    if type(bestRun) ~= "table" then
        return "None"
    end

    local level = tonumber(bestRun.level)
    if not level then
        return "None"
    end

    local mapLabel = FormatDungeonLabel(bestRun.mapID)

    if type(bestRun.score) == "number" and bestRun.score > 0 then
        return string.format("+%d %s (%d)", level, mapLabel, floor(bestRun.score + 0.5))
    end

    return string.format("+%d %s", level, mapLabel)
end

local function FormatBestRunNoScore(bestRun)
    if type(bestRun) ~= "table" then
        return "None"
    end

    local level = tonumber(bestRun.level)
    if not level then
        return "None"
    end

    return string.format("+%d %s", level, FormatDungeonLabel(bestRun.mapID))
end

local function BuildBestReply()
    local weekBest, seasonBest = GetBestRunsFromHistory()

    if not weekBest or not seasonBest then
        local mapWeekBest = GetBestRunFromMapLookup("GetWeeklyBestForMap")
        local mapSeasonBest = GetBestRunFromMapLookup("GetSeasonBestForMap")
        weekBest = weekBest or mapWeekBest
        seasonBest = seasonBest or mapSeasonBest
    end

    return string.format(
        "%s Best - Week: %s / Season: %s",
        REPLY_PREFIX,
        FormatBestRun(weekBest),
        FormatBestRun(seasonBest)
    )
end

local function RequestAbandonKeyVote()
    if not IsInMythicDungeonInstance() then
        PrintLocal("Abandon vote is only available inside Mythic+ dungeons")
        return
    end

    if not IsChallengeModeRunActive() then
        PrintLocal("Abandon vote is only available during an active Mythic+ run")
        return
    end

    local started = false

    if C_ChallengeMode then
        if type(C_ChallengeMode.RequestLeaverVote) == "function" then
            local ok = pcall(C_ChallengeMode.RequestLeaverVote)
            started = ok == true
        elseif type(C_ChallengeMode.StartLeaverVote) == "function" then
            local ok = pcall(C_ChallengeMode.StartLeaverVote)
            started = ok == true
        end
    end

    if started then
        PrintLocal("Started vote to abandon the key")
    else
        PrintLocal("Unable to start abandon vote in this client build")
    end
end

local function BuildChatContext()
    return {
        REPLY_PREFIX = REPLY_PREFIX,
        KEY_TEXT_COMMAND = KEY_TEXT_COMMAND,
        KEYS_TEXT_COMMAND = KEYS_TEXT_COMMAND,
        SCORE_TEXT_COMMAND = SCORE_TEXT_COMMAND,
        SCORES_TEXT_COMMAND = SCORES_TEXT_COMMAND,
        BEST_TEXT_COMMAND = BEST_TEXT_COMMAND,
        CHAT_EVENTS = CHAT_EVENTS,
        CHAT_EVENT_TO_CHANNEL = CHAT_EVENT_TO_CHANNEL,
        strtrim = strtrim,
        strlower = strlower,
        BuildKeystoneReply = BuildKeystoneReply,
        BuildScoreReply = BuildScoreReply,
        BuildBestReply = BuildBestReply,
        PrintLocal = PrintLocal,
        ParseKeystoneFromMessage = KMNS.ParseKeystoneFromMessage,
        SaveGuildMemberData = SaveGuildMemberData,
        ExtractRequestCommand = KMNS.ExtractRequestCommand,
        CanReadChatPayload = KMNS.CanReadChatPayload,
        RequestGuildSnapshots = RequestGuildSnapshots,
        SendOrQueueChatMessage = SendOrQueueChatMessage,
        RefreshKSMWindowIfVisible = RefreshKSMWindowIfVisible,
    }
end

BuildRunStateContext = function()
    return {
        ui = ui,
        max = max,
        IsChallengeModeRunActive = IsChallengeModeRunActive,
        IsInMythicDungeonInstance = IsInMythicDungeonInstance,
        ObserveOwnedKeystone = ObserveOwnedKeystone,
        GetOwnedKeystoneMapID = GetOwnedKeystoneMapID,
        GetKeystoneMapName = GetKeystoneMapName,
        GetChallengeMapTimeLimit = GetChallengeMapTimeLimit,
        GetWorldElapsedSeconds = GetWorldElapsedSeconds,
        GetActiveKeystoneDetails = GetActiveKeystoneDetails,
        GetCriteriaState = GetCriteriaState,
        GetDeathState = GetDeathState,
        CalculateChestTimerLimits = CalculateChestTimerLimits,
        GetAffixSummary = GetAffixSummary,
        FormatDungeonLabel = FormatDungeonLabel,
        CopyDeathLog = CopyDeathLog,
        ResetDeathLog = ResetDeathLog,
        ResetEnemyForcesCalibration = ResetEnemyForcesCalibration,
        SyncGroupDeathLogFromUnits = SyncGroupDeathLogFromUnits,
        RecordGroupDeath = RecordGroupDeath,
        FlushDeferredChatMessages = FlushDeferredChatMessages,
        RefreshMythicUI = RefreshMythicUI,
        RefreshKSMWindowIfVisible = RefreshKSMWindowIfVisible,
    }
end

local function HandleChatMessage(event, message, sender)
    local chatModule = _G.KeyMasterNS and _G.KeyMasterNS.Chat
    if chatModule and chatModule.HandleChatMessage then
        chatModule.HandleChatMessage(BuildChatContext(), event, message, sender)
    end
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

local function GetAffixDisplayInfo(affixID)
    if type(affixID) ~= "number" then
        return nil, nil, nil
    end

    if C_Affixes and C_Affixes.GetAffixInfo then
        local ok, result1, result2, result3 = pcall(C_Affixes.GetAffixInfo, affixID)
        if ok then
            if type(result1) == "table" then
                local info = result1
                return info.name or info.displayName, info.description, info.icon or info.fileDataID
            end

            if type(result1) == "string" or type(result3) == "number" or type(result3) == "string" then
                return result1, result2, result3
            end
        end
    end

    if C_ChallengeMode and C_ChallengeMode.GetAffixInfo then
        local ok, result1, result2, result3, result4 = pcall(C_ChallengeMode.GetAffixInfo, affixID)
        if ok then
            local name = type(result1) == "string" and result1 or type(result2) == "string" and result2 or nil
            local description = type(result2) == "string" and result2 ~= name and result2 or type(result3) == "string" and result3 or nil
            local icon = (type(result3) == "number" or type(result3) == "string") and result3
                or (type(result4) == "number" or type(result4) == "string") and result4
                or nil
            return name, description, icon
        end
    end

    return nil, nil, nil
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

    local quantityStringPercent = KMNS.ParsePercentValue(criteriaInfo.quantityString)
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
                if KMNS.ParsePercentValue(info.quantityString) ~= nil then
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

    local percent = KMNS.ParsePercentValue(enemyInfo.quantityString)
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
    local runStateModule = _G.KeyMasterNS and _G.KeyMasterNS.RunState
    if runStateModule and runStateModule.GetActiveRunState then
        return runStateModule.GetActiveRunState(BuildRunStateContext())
    end
    return nil
end

local function CaptureCompletedRunState()
    local runStateModule = _G.KeyMasterNS and _G.KeyMasterNS.RunState
    if runStateModule and runStateModule.CaptureCompletedRunState then
        runStateModule.CaptureCompletedRunState(BuildRunStateContext())
    end
end

local function RefreshCompletedRunTimingFromAPI()
    local runStateModule = _G.KeyMasterNS and _G.KeyMasterNS.RunState
    if runStateModule and runStateModule.RefreshCompletedRunTimingFromAPI then
        runStateModule.RefreshCompletedRunTimingFromAPI(BuildRunStateContext())
    end
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
    if not settings.locked then ui.dragLabel:Show() else ui.dragLabel:Hide() end
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
                ui.timerLine:SetText(string.format("%s (%s / %s)", KMNS.FormatSeconds(state.timeLeftSeconds), KMNS.FormatSeconds(state.elapsedSeconds), KMNS.FormatSeconds(state.maxTimeSeconds)))
            else
                ui.timerLine:SetText(KMNS.FormatSeconds(state.elapsedSeconds))
            end
            ui.timerLine:SetTextColor(1, 1, 1, 1)
            ui.timerLine:SetWidth(width)
            ui.timerLine:ClearAllPoints()
            ui.timerLine:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", xPadding, y)
            y = y - ui.timerLine:GetStringHeight() - 4

            if state.twoChestLimit then
                ui.twoChestLine:SetText(string.format("+2 (%s): %s", KMNS.FormatSeconds(state.twoChestLimit), KMNS.FormatSeconds(max(0, state.twoChestLimit - state.elapsedSeconds))))
            else
                ui.twoChestLine:SetText("+2: --:--")
            end
            ui.twoChestLine:SetWidth(width)
            ui.twoChestLine:ClearAllPoints()
            ui.twoChestLine:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", xPadding, y)
            y = y - ui.twoChestLine:GetStringHeight() - 4

            if state.threeChestLimit then
                ui.threeChestLine:SetText(string.format("+3 (%s): %s", KMNS.FormatSeconds(state.threeChestLimit), KMNS.FormatSeconds(max(0, state.threeChestLimit - state.elapsedSeconds))))
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
                ui.deathLine:SetText(string.format("Deaths: %d (-%s)", state.deathCount, KMNS.FormatSeconds(state.deathPenalty or 0)))
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

            ui.abandonButton:ClearAllPoints()
            ui.abandonButton:SetPoint("TOP", ui.frame, "TOP", 0, y - 2)
            ui.abandonButton:Show()
            y = y - ui.abandonButton:GetHeight() - 8

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
            ui.timerLine:SetText(string.format("%s (waiting for challenge data)", KMNS.FormatSeconds(elapsedSeconds)))
            ui.timerLine:SetTextColor(1, 1, 1, 1)
            ui.timerLine:SetWidth(width)
            ui.timerLine:ClearAllPoints()
            ui.timerLine:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", xPadding, y)

            ui.affixesLine:Hide()
            ui.twoChestLine:Hide()
            ui.threeChestLine:Hide()
            ui.deathLine:Hide()
            UpdateDeathTooltipArea()
            ui.abandonButton:ClearAllPoints()
            ui.abandonButton:SetPoint("TOP", ui.frame, "TOP", 0, y - 8)
            ui.abandonButton:Show()
            ui.enemyBar:Hide()
            for index = 1, #ui.objectiveLines do
                ui.objectiveLines[index]:Hide()
            end

            ui.frame:SetHeight(118)
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
                ui.timerLine:SetText(string.format("Completed: %s (%s left)", KMNS.FormatSeconds(completed.elapsedSeconds or 0), KMNS.FormatSignedSeconds(completed.timeLeftSeconds or 0)))
                if type(completed.timeLeftSeconds) == "number" and completed.timeLeftSeconds < 0 then
                    ui.timerLine:SetTextColor(1, 0.25, 0.25, 1)
                else
                    ui.timerLine:SetTextColor(1, 1, 1, 1)
                end
            else
                ui.timerLine:SetText(string.format("Completed: %s", KMNS.FormatSeconds(completed.elapsedSeconds or 0)))
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
                ui.threeChestLine:SetText(string.format("Timer: %s / %s", KMNS.FormatSeconds(completed.elapsedSeconds or 0), KMNS.FormatSeconds(completed.maxTimeSeconds)))
            else
                ui.threeChestLine:SetText("Timer: --:--")
            end
            ui.threeChestLine:SetWidth(width)
            ui.threeChestLine:ClearAllPoints()
            ui.threeChestLine:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", xPadding, y)
            ui.threeChestLine:Show()
            y = y - ui.threeChestLine:GetStringHeight() - 6

            if completed.deathCount and completed.deathCount > 0 then
                ui.deathLine:SetText(string.format("Deaths: %d (-%s)", completed.deathCount, KMNS.FormatSeconds(completed.deathPenalty or 0)))
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

            ui.abandonButton:Hide()

            ui.enemyBar:Hide()
            for index = 1, #ui.objectiveLines do
                ui.objectiveLines[index]:Hide()
            end

            ui.frame:SetHeight(max(120, -y + 12))
        else
            ui.abandonButton:Hide()
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

    local abandonButton = CreateFrame("Button", nil, mythicFrame, "UIPanelButtonTemplate")
    abandonButton:SetSize(176, 20)
    abandonButton:SetText("Vote: Abandon Key")
    abandonButton:SetScript("OnClick", function()
        RequestAbandonKeyVote()
    end)
    abandonButton:Hide()
    ui.abandonButton = abandonButton

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
        if ui.lastRefreshAt < ((_G.KeyMasterNS and _G.KeyMasterNS.UI_REFRESH_INTERVAL_SECONDS) or 0.2) then
            return
        end

        ui.lastRefreshAt = 0
        RenderMythicUI()
    end)

    ApplyMythicFrameSettings()
end

RefreshMythicUI = function()
    if not ui.frame then
        CreateMythicUI()
    end

    ui.lastRefreshAt = ((_G.KeyMasterNS and _G.KeyMasterNS.UI_REFRESH_INTERVAL_SECONDS) or 0.2)
    RenderMythicUI()
end

local function TryAutoSlotKeystone()
    if not (C_ChallengeMode and C_ChallengeMode.SlotKeystone) then return end
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemID and C_Container.PickupContainerItem) then return end
    for _, bagID in ipairs((_G.KeyMasterNS and _G.KeyMasterNS.KEYSTONE_BAG_SLOTS) or { Enum.BagIndex.Backpack, Enum.BagIndex.Bag_1, Enum.BagIndex.Bag_2, Enum.BagIndex.Bag_3, Enum.BagIndex.Bag_4 }) do
        local slotCount = C_Container.GetContainerNumSlots(bagID) or 0
        for slotIndex = 1, slotCount do
            local itemID = C_Container.GetContainerItemID(bagID, slotIndex)
            if (((_G.KeyMasterNS and _G.KeyMasterNS.KEYSTONE_ITEM_IDS) or { [180653] = true, [158923] = true, [151086] = true })[itemID]) then
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
            local parsedPercent = KMNS.ParsePercentValue(info.quantityString)
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

local function GetPortalSpellIDForMap(mapID)
    if type(mapID) ~= "number" then
        return nil
    end

    if UnitFactionGroup and UnitFactionGroup("player") == "Horde" then
        return KSM_PORTAL_SPELL_IDS_HORDE[mapID] or KSM_PORTAL_SPELL_IDS[mapID]
    end

    return KSM_PORTAL_SPELL_IDS[mapID]
end

local function IsPortalSpellKnown(spellID)
    if type(spellID) ~= "number" or spellID <= 0 then
        return false
    end

    if IsSpellKnownOrOverridesKnown and IsSpellKnownOrOverridesKnown(spellID) then
        return true
    end

    if IsSpellKnown and IsSpellKnown(spellID) then
        return true
    end

    if IsPlayerSpell and IsPlayerSpell(spellID) then
        return true
    end

    if type(C_SpellBook) == "table" and type(C_SpellBook.IsSpellKnown) == "function" then
        local ok, known = pcall(C_SpellBook.IsSpellKnown, spellID)
        if ok and known then
            return true
        end
    end

    return false
end

local function GetPortalSecureSpellToken(spellID)
    if type(spellID) ~= "number" or spellID <= 0 then
        return nil
    end

    if type(C_Spell) == "table" and type(C_Spell.GetSpellName) == "function" then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end

    if GetSpellInfo then
        local name = GetSpellInfo(spellID)
        if type(name) == "string" and name ~= "" then
            return name
        end
    end

    return string.format("spell:%d", spellID)
end

local function TryCastPortalSpell(spellID)
    -- Deprecated on purpose: portal casts are bound through SecureActionButtonTemplate.
    -- Keeping this function as a non-casting guard avoids accidental protected calls.
    local _ = spellID
    return false
end

local function ConfigurePortalActionButton(button, spellID)
    if not button then
        return false
    end

    button.spellID = spellID
    local known = IsPortalSpellKnown(spellID)
    local hasSpell = type(spellID) == "number" and spellID > 0

    if not button.SetAttribute then
        return known
    end

    if InCombatLockdown and InCombatLockdown() then
        return known
    end

    if hasSpell then
        -- Always resolve the spell name for macrotext
        local spellName = nil
        if type(C_Spell) == "table" and type(C_Spell.GetSpellName) == "function" then
            local ok, name = pcall(C_Spell.GetSpellName, spellID)
            if ok and type(name) == "string" and name ~= "" then
                spellName = name
            end
        end
        if not spellName and GetSpellInfo then
            local name = GetSpellInfo(spellID)
            if type(name) == "string" and name ~= "" then
                spellName = name
            end
        end
        if not spellName then
            spellName = tostring(spellID)
        end

        local macrotext = string.format("/cast %s", spellName)
        button:SetAttribute("type", "macro")
        button:SetAttribute("macrotext", macrotext)
        button:SetAttribute("type1", "macro")
        button:SetAttribute("macrotext1", macrotext)

        -- Remove spell attributes to avoid secure confusion
        button:SetAttribute("spell", nil)
        button:SetAttribute("spell1", nil)

    else
        button:SetAttribute("type", nil)
        button:SetAttribute("macrotext", nil)
        button:SetAttribute("type1", nil)
        button:SetAttribute("macrotext1", nil)
        button:SetAttribute("spell", nil)
        button:SetAttribute("spell1", nil)
    end

    return known
end

local function GetCurrentSeasonPortalEntries()
    local entries = {}
    local addedByMapID = {}

    local function AddPortalEntry(mapID)
        if type(mapID) ~= "number" or addedByMapID[mapID] then
            return
        end

        local spellID = GetPortalSpellIDForMap(mapID)

        addedByMapID[mapID] = true
        table.insert(entries, {
            mapID = mapID,
            mapName = FormatDungeonLabel(mapID),
            spellID = spellID,
            known = spellID and IsPortalSpellKnown(spellID) == true,
        })
    end

    if C_ChallengeMode and C_ChallengeMode.GetMapTable then
        local ok, maps = pcall(C_ChallengeMode.GetMapTable)
        if ok and type(maps) == "table" then
            for _, mapID in ipairs(maps) do
                AddPortalEntry(mapID)
            end
        end
    end

    -- Fallback: always include configured season portals even if map table is unavailable.
    local factionGroup = UnitFactionGroup and UnitFactionGroup("player") or nil
    for mapID in pairs(KSM_PORTAL_SPELL_IDS) do
        AddPortalEntry(mapID)
    end
    if factionGroup == "Horde" then
        for mapID in pairs(KSM_PORTAL_SPELL_IDS_HORDE) do
            AddPortalEntry(mapID)
        end
    end

    if #entries == 0 then
        local weekBest, seasonBest = GetBestRunsFromHistory()
        if weekBest and weekBest.mapID then
            AddPortalEntry(tonumber(weekBest.mapID))
        end
        if seasonBest and seasonBest.mapID then
            AddPortalEntry(tonumber(seasonBest.mapID))
        end
    end

    table.sort(entries, function(left, right)
        return (left.mapName or "") < (right.mapName or "")
    end)

    return entries
end

local function TryOpenGreatVaultUI()
    if WeeklyRewards_ShowUI and pcall(WeeklyRewards_ShowUI) then
        return true
    end

    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.LoadAddOn and not C_AddOns.IsAddOnLoaded("Blizzard_WeeklyRewards") then
        pcall(C_AddOns.LoadAddOn, "Blizzard_WeeklyRewards")
    end

    if WeeklyRewardsFrame and ShowUIPanel then
        pcall(ShowUIPanel, WeeklyRewardsFrame)
        return true
    end

    return false
end

local function GetVaultUnlockCounts()
    if not (C_WeeklyRewards and C_WeeklyRewards.GetActivities) then
        return nil, nil
    end

    local ok, activities = pcall(C_WeeklyRewards.GetActivities)
    if not ok or type(activities) ~= "table" then
        return nil, nil
    end

    local totalSlots = 0
    local unlockedSlots = 0

    for _, activity in ipairs(activities) do
        if type(activity) == "table" and type(activity.threshold) == "number" and type(activity.progress) == "number" then
            totalSlots = totalSlots + 1
            if activity.progress >= activity.threshold then
                unlockedSlots = unlockedSlots + 1
            end
        end
    end

    if totalSlots <= 0 then
        return nil, nil
    end

    return unlockedSlots, totalSlots
end

local function GetVaultProgressSummary()
    local unlockedSlots, totalSlots = GetVaultUnlockCounts()
    if not unlockedSlots or not totalSlots then
        return "Great Vault progress unavailable"
    end

    return string.format("Vault slots unlocked: %d/%d", unlockedSlots, totalSlots)
end

local function ResolveBestScore(result1, result2)
    local function ExtractScoreFromTable(value, depth)
        if depth <= 0 or type(value) ~= "table" then
            return nil
        end

        local bestScore
        for key, entry in pairs(value) do
            if type(entry) == "number" then
                local keyName = type(key) == "string" and strlower(key) or ""
                if keyName ~= "" and (strfind(keyName, "score", 1, true) or strfind(keyName, "rating", 1, true)) then
                    if entry > 0 and (not bestScore or entry > bestScore) then
                        bestScore = entry
                    end
                end
            elseif type(entry) == "table" then
                local nested = ExtractScoreFromTable(entry, depth - 1)
                if nested and (not bestScore or nested > bestScore) then
                    bestScore = nested
                end
            end
        end

        return bestScore
    end

    local score

    if type(result1) == "table" then
        score = result1.mapScore or result1.score or result1.rating or result1.bestRunScore or result1.currentSeasonScore
        score = score or ExtractScoreFromTable(result1, 3)
    elseif type(result2) == "table" then
        score = result2.mapScore or result2.score or result2.rating or result2.bestRunScore or result2.currentSeasonScore
        score = score or ExtractScoreFromTable(result2, 3)
    end

    score = tonumber(score)
    if type(score) == "number" and score > 0 then
        return score
    end

    return nil
end

local function GetBestSeasonRunForMap(mapID)
    if not (type(mapID) == "number" and C_MythicPlus and C_MythicPlus.GetSeasonBestForMap) then
        return nil
    end

    local ok, result1, result2 = pcall(C_MythicPlus.GetSeasonBestForMap, mapID)
    if not ok then
        return nil
    end

    local level = ResolveBestLevel(result1, result2)
    if not level then
        return nil
    end

    local score = ResolveBestScore(result1, result2)
    if (not score) and C_MythicPlus and C_MythicPlus.GetSeasonBestAffixScoreInfoForMap then
        local infoOk, scoreInfo = pcall(C_MythicPlus.GetSeasonBestAffixScoreInfoForMap, mapID)
        if infoOk and type(scoreInfo) == "table" then
            score = ResolveBestScore(scoreInfo, nil)
            if (not score) and type(scoreInfo.overallScore) == "number" then
                score = scoreInfo.overallScore
            end
        end
    end

    return {
        mapID = mapID,
        level = level,
        score = score,
    }
end

local function GetBestSeasonRunForMapFromHistory(mapID)
    if not (type(mapID) == "number" and mapID > 0 and C_MythicPlus and C_MythicPlus.GetRunHistory) then
        return nil
    end

    local ok, history = pcall(C_MythicPlus.GetRunHistory)
    if not ok or type(history) ~= "table" then
        return nil
    end

    local best

    local function ResolveRunLevel(run)
        local level = run and (run.level or run.bestRunLevel or run.keystoneLevel or run.completedLevel)
        level = tonumber(level)
        if type(level) == "number" and level >= 2 and level <= 40 then
            return level
        end
        return nil
    end

    local function ResolveRunMapID(run)
        local resolvedMapID = run and (run.mapChallengeModeID or run.mapID or run.challengeMapID)
        resolvedMapID = tonumber(resolvedMapID)
        if type(resolvedMapID) == "number" and resolvedMapID > 0 then
            return resolvedMapID
        end
        return nil
    end

    local function ResolveRunScore(run)
        local score = run and (run.mapScore or run.score or run.rating or run.bestRunScore or run.currentSeasonScore or run.overallScore or run.dungeonScore)
        if (not score) and type(run) == "table" then
            for key, value in pairs(run) do
                if type(value) == "number" and type(key) == "string" then
                    local keyName = strlower(key)
                    if (strfind(keyName, "score", 1, true) or strfind(keyName, "rating", 1, true)) and value > 0 then
                        score = value
                        break
                    end
                end
            end
        end
        score = tonumber(score)
        if type(score) == "number" and score > 0 then
            return score
        end
        return nil
    end

    local function IsBetter(candidate, current)
        if not candidate then
            return false
        end
        if not current then
            return true
        end

        local candidateScore = tonumber(candidate.score)
        local currentScore = tonumber(current.score)
        if candidateScore and currentScore and candidateScore ~= currentScore then
            return candidateScore > currentScore
        end
        if candidateScore and not currentScore then
            return true
        end
        if currentScore and not candidateScore then
            return false
        end

        return (candidate.level or 0) > (current.level or 0)
    end

    for _, run in ipairs(history) do
        if run and run.completed ~= false and ResolveRunMapID(run) == mapID then
            local level = ResolveRunLevel(run)
            if level then
                local candidate = {
                    mapID = mapID,
                    level = level,
                    score = ResolveRunScore(run),
                }
                if IsBetter(candidate, best) then
                    best = candidate
                end
            end
        end
    end

    return best
end

local function GetBestPortalRunForMap(mapID)
    local byMapAPI = GetBestSeasonRunForMap(mapID)
    local byHistory = GetBestSeasonRunForMapFromHistory(mapID)

    if not byMapAPI then
        return byHistory
    end
    if not byHistory then
        return byMapAPI
    end

    local apiScore = tonumber(byMapAPI.score)
    local historyScore = tonumber(byHistory.score)
    if apiScore and historyScore and apiScore ~= historyScore then
        return apiScore > historyScore and byMapAPI or byHistory
    end
    if apiScore and not historyScore then
        return byMapAPI
    end
    if historyScore and not apiScore then
        return byHistory
    end

    return (byMapAPI.level or 0) >= (byHistory.level or 0) and byMapAPI or byHistory
end

local function GetBestSeasonRunFromKnownMaps()
    local best
    local seen = {}

    local function ConsiderMap(mapID)
        mapID = tonumber(mapID)
        if not mapID or mapID <= 0 or seen[mapID] then
            return
        end
        seen[mapID] = true

        local candidate = GetBestSeasonRunForMap(mapID)
        if not candidate then
            return
        end

        if not best then
            best = candidate
            return
        end

        local candidateScore = tonumber(candidate.score)
        local bestScore = tonumber(best.score)
        if candidateScore and bestScore and candidateScore ~= bestScore then
            if candidateScore > bestScore then
                best = candidate
            end
            return
        end

        if candidateScore and not bestScore then
            best = candidate
            return
        end

        if (candidate.level or 0) > (best.level or 0) then
            best = candidate
        end
    end

    if C_ChallengeMode and C_ChallengeMode.GetMapTable then
        local ok, maps = pcall(C_ChallengeMode.GetMapTable)
        if ok and type(maps) == "table" then
            for _, mapID in ipairs(maps) do
                ConsiderMap(mapID)
            end
        end
    end

    for mapID in pairs(KSM_PORTAL_SPELL_IDS) do
        ConsiderMap(mapID)
    end

    if UnitFactionGroup and UnitFactionGroup("player") == "Horde" then
        for mapID in pairs(KSM_PORTAL_SPELL_IDS_HORDE) do
            ConsiderMap(mapID)
        end
    end

    return best
end

local function ResolveSpellIconTexture(spellID)
    if type(spellID) ~= "number" or spellID <= 0 then
        return nil
    end

    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok then
            if type(info) == "table" then
                local icon = info.iconID or info.iconFileID or info.iconTexture
                if type(icon) == "number" or type(icon) == "string" then
                    return icon
                end
            elseif type(info) == "number" or type(info) == "string" then
                return info
            end
        end
    end

    if GetSpellInfo then
        local _, _, icon = GetSpellInfo(spellID)
        if type(icon) == "number" or type(icon) == "string" then
            return icon
        end
    end

    return nil
end

local function GetDungeonTileTexture(mapID, spellID)
    local spellIcon = ResolveSpellIconTexture(spellID)
    if spellIcon then
        return spellIcon, true
    end

    if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        local ok, result1, result2, result3, result4, result5, result6 = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
        if ok then
            local candidates = { result6, result5, result4, result3, result2, result1 }
            for _, candidate in ipairs(candidates) do
                if type(candidate) == "string" then
                    return candidate, false
                end
                if type(candidate) == "number" and candidate > 10000 then
                    return candidate, false
                end
            end
        end
    end

    return "Interface\\Icons\\INV_Misc_QuestionMark", false
end

local function TrySetGreatVaultTexture(texture)
    if not texture then
        return false
    end

    local unlockedSlots, totalSlots = GetVaultUnlockCounts()
    local hasAnyUnlockedSlot = type(unlockedSlots) == "number" and unlockedSlots > 0
    local _ = totalSlots
    texture:SetTexture(hasAnyUnlockedSlot
        and ((_G.KeyMasterNS and _G.KeyMasterNS.KSM_VAULT_TEXTURE_GLOWY) or "Interface\\AddOns\\KeyMaster\\Assets\\UI\\Vault_Glowy.png")
        or ((_G.KeyMasterNS and _G.KeyMasterNS.KSM_VAULT_TEXTURE_EMPTY) or "Interface\\AddOns\\KeyMaster\\Assets\\UI\\Vault.png"))
    texture:SetTexCoord(0, 1, 0, 1)
    texture:SetBlendMode("BLEND")
    return true
end

local function TryGetMythicScoreForIdentifier(identifier)
    if not identifier or not (C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary) then
        return nil
    end

    local ok, summary = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, identifier)
    if not ok or type(summary) ~= "table" then
        return nil
    end

    local score = summary.currentSeasonScore or summary.overallScore or summary.score
    score = tonumber(score)
    if type(score) == "number" and score >= 0 then
        return score
    end

    return nil
end

local function TryGetUnitMythicScore(unitToken)
    if unitToken == "player" then
        return GetMythicPlusScore()
    end

    local score = TryGetMythicScoreForIdentifier(unitToken)
    if type(score) == "number" then
        return score
    end

    local guid = UnitGUID and UnitGUID(unitToken)
    score = TryGetMythicScoreForIdentifier(guid)
    if type(score) == "number" then
        return score
    end

    return nil
end

local function TryGetBestSeasonRunForIdentifier(identifier)
    if not (identifier and C_MythicPlus and C_MythicPlus.GetSeasonBestForMap and C_ChallengeMode and C_ChallengeMode.GetMapTable) then
        return nil
    end

    local okMaps, maps = pcall(C_ChallengeMode.GetMapTable)
    if not okMaps or type(maps) ~= "table" then
        return nil
    end

    local bestRun
    for _, mapID in ipairs(maps) do
        local ok, result1, result2 = pcall(C_MythicPlus.GetSeasonBestForMap, mapID, identifier)
        if ok then
            local level = ResolveBestLevel(result1, result2)
            if type(level) == "number" and (not bestRun or level > bestRun.level) then
                bestRun = { level = level, mapID = mapID }
            end
        end
    end

    return bestRun
end

local function EnsureKSMDataLine(pool, parent, index)
    if pool[index] then
        return pool[index]
    end

    pool[index] = CreateLine(parent, 12)
    return pool[index]
end

local function EnsureKSMGuildRow(index)
    if ui.ksmGuildRows[index] then
        return ui.ksmGuildRows[index]
    end

    local row = CreateFrame("Frame", nil, ui.ksmGuildContent)
    row:SetSize(570, 24)

    local classIcon = row:CreateTexture(nil, "ARTWORK")
    classIcon:SetSize(16, 16)
    classIcon:SetPoint("LEFT", row, "LEFT", 4, 0)
    classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
    row.classIcon = classIcon

    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("LEFT", classIcon, "RIGHT", 8, 0)
    nameText:SetWidth(165)
    nameText:SetJustifyH("LEFT")
    row.nameText = nameText

    local nameButton = CreateFrame("Button", nil, row)
    nameButton:SetPoint("LEFT", classIcon, "RIGHT", 4, 0)
    nameButton:SetSize(170, 22)
    nameButton:RegisterForClicks("AnyUp")
    row.nameButton = nameButton

    local keyText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    keyText:SetPoint("LEFT", row, "LEFT", 198, 0)
    keyText:SetWidth(34)
    keyText:SetJustifyH("LEFT")
    row.keyText = keyText

    local dungeonText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    dungeonText:SetPoint("LEFT", row, "LEFT", 240, 0)
    dungeonText:SetWidth(180)
    dungeonText:SetJustifyH("LEFT")
    row.dungeonText = dungeonText

    local ratingText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ratingText:SetPoint("LEFT", row, "LEFT", 430, 0)
    ratingText:SetWidth(54)
    ratingText:SetJustifyH("LEFT")
    row.ratingText = ratingText

    local teleportButton = CreateFrame("Button", nil, row, "SecureActionButtonTemplate")
    teleportButton:SetSize(78, 18)
    teleportButton:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    teleportButton:RegisterForClicks("AnyUp", "AnyDown")

    local bg = teleportButton:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(teleportButton)
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.85)

    local accent = teleportButton:CreateTexture(nil, "OVERLAY")
    accent:SetPoint("TOPLEFT", teleportButton, "TOPLEFT", 0, 0)
    accent:SetPoint("BOTTOMRIGHT", teleportButton, "BOTTOMRIGHT", 0, 0)
    accent:SetColorTexture(BREAK_TIMER_BLUE[1], BREAK_TIMER_BLUE[2], BREAK_TIMER_BLUE[3], 0.18)

    local label = teleportButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetAllPoints(teleportButton)
    label:SetText("Teleport")
    teleportButton.label = label

    teleportButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.spellID then
            GameTooltip:SetSpellByID(self.spellID)
        else
            GameTooltip:AddLine("Portal unavailable", 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    teleportButton:SetScript("OnLeave", GameTooltip_Hide)
    row.teleportButton = teleportButton

    ui.ksmGuildRows[index] = row
    return row
end

local function EnsureKSMRecentRow(index)
    if ui.ksmRecentsRows[index] then
        return ui.ksmRecentsRows[index]
    end

    local row = CreateFrame("Frame", nil, ui.ksmRecentsContent)
    row:SetSize(570, 24)

    local classIcon = row:CreateTexture(nil, "ARTWORK")
    classIcon:SetSize(16, 16)
    classIcon:SetPoint("LEFT", row, "LEFT", 4, 0)
    classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
    row.classIcon = classIcon

    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("LEFT", classIcon, "RIGHT", 8, 0)
    nameText:SetWidth(165)
    nameText:SetJustifyH("LEFT")
    row.nameText = nameText

    local nameButton = CreateFrame("Button", nil, row)
    nameButton:SetPoint("LEFT", classIcon, "RIGHT", 4, 0)
    nameButton:SetSize(170, 22)
    nameButton:RegisterForClicks("AnyUp")
    row.nameButton = nameButton

    local keyText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    keyText:SetPoint("LEFT", row, "LEFT", 198, 0)
    keyText:SetWidth(34)
    keyText:SetJustifyH("LEFT")
    row.keyText = keyText

    local dungeonText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    dungeonText:SetPoint("LEFT", row, "LEFT", 240, 0)
    dungeonText:SetWidth(180)
    dungeonText:SetJustifyH("LEFT")
    row.dungeonText = dungeonText

    local ratingText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ratingText:SetPoint("LEFT", row, "LEFT", 430, 0)
    ratingText:SetWidth(54)
    ratingText:SetJustifyH("LEFT")
    row.ratingText = ratingText

    local teleportButton = CreateFrame("Button", nil, row, "SecureActionButtonTemplate")
    teleportButton:SetSize(78, 18)
    teleportButton:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    teleportButton:RegisterForClicks("AnyUp", "AnyDown")

    local bg = teleportButton:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(teleportButton)
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.85)

    local accent = teleportButton:CreateTexture(nil, "OVERLAY")
    accent:SetPoint("TOPLEFT", teleportButton, "TOPLEFT", 0, 0)
    accent:SetPoint("BOTTOMRIGHT", teleportButton, "BOTTOMRIGHT", 0, 0)
    accent:SetColorTexture(BREAK_TIMER_BLUE[1], BREAK_TIMER_BLUE[2], BREAK_TIMER_BLUE[3], 0.18)

    local label = teleportButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetAllPoints(teleportButton)
    label:SetText("Teleport")
    teleportButton.label = label

    teleportButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.spellID then
            GameTooltip:SetSpellByID(self.spellID)
        else
            GameTooltip:AddLine("Portal unavailable", 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    teleportButton:SetScript("OnLeave", GameTooltip_Hide)
    row.teleportButton = teleportButton

    ui.ksmRecentsRows[index] = row
    return row
end

local function EnsureKSMWarbandRow(index)
    if ui.ksmWarbandRows[index] then
        return ui.ksmWarbandRows[index]
    end

    local row = CreateFrame("Frame", nil, ui.ksmWarbandContent)
    row:SetSize(570, 24)

    local classIcon = row:CreateTexture(nil, "ARTWORK")
    classIcon:SetSize(16, 16)
    classIcon:SetPoint("LEFT", row, "LEFT", 4, 0)
    classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
    row.classIcon = classIcon

    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("LEFT", classIcon, "RIGHT", 8, 0)
    nameText:SetWidth(165)
    nameText:SetJustifyH("LEFT")
    row.nameText = nameText

    local keyText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    keyText:SetPoint("LEFT", row, "LEFT", 198, 0)
    keyText:SetWidth(34)
    keyText:SetJustifyH("LEFT")
    row.keyText = keyText

    local dungeonText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    dungeonText:SetPoint("LEFT", row, "LEFT", 240, 0)
    dungeonText:SetWidth(180)
    dungeonText:SetJustifyH("LEFT")
    row.dungeonText = dungeonText

    local ratingText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ratingText:SetPoint("LEFT", row, "LEFT", 430, 0)
    ratingText:SetWidth(54)
    ratingText:SetJustifyH("LEFT")
    row.ratingText = ratingText

    local teleportButton = CreateFrame("Button", nil, row, "SecureActionButtonTemplate")
    teleportButton:SetSize(78, 18)
    teleportButton:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    teleportButton:RegisterForClicks("AnyUp", "AnyDown")

    local bg = teleportButton:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(teleportButton)
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.85)

    local accent = teleportButton:CreateTexture(nil, "OVERLAY")
    accent:SetPoint("TOPLEFT", teleportButton, "TOPLEFT", 0, 0)
    accent:SetPoint("BOTTOMRIGHT", teleportButton, "BOTTOMRIGHT", 0, 0)
    accent:SetColorTexture(BREAK_TIMER_BLUE[1], BREAK_TIMER_BLUE[2], BREAK_TIMER_BLUE[3], 0.18)

    local label = teleportButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetAllPoints(teleportButton)
    label:SetText("Teleport")
    teleportButton.label = label

    teleportButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.spellID then
            GameTooltip:SetSpellByID(self.spellID)
        else
            GameTooltip:AddLine("Portal unavailable", 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    teleportButton:SetScript("OnLeave", GameTooltip_Hide)
    row.teleportButton = teleportButton

    ui.ksmWarbandRows[index] = row
    return row
end

local function EnsureKSMPartyRow(index)
    if ui.ksmPartyRows[index] then
        return ui.ksmPartyRows[index]
    end

    local row = CreateFrame("Frame", nil, ui.ksmPartyContent)
    row:SetSize(570, 64)

    local cardBG = row:CreateTexture(nil, "BACKGROUND")
    cardBG:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -2)
    cardBG:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -2, 2)
    cardBG:SetColorTexture(0.02, 0.03, 0.04, 0.36)
    row.cardBG = cardBG

    local portraitBG = row:CreateTexture(nil, "BACKGROUND")
    portraitBG:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -8)
    portraitBG:SetSize(42, 42)
    portraitBG:SetColorTexture(0.03, 0.04, 0.05, 0.8)

    local portrait = row:CreateTexture(nil, "ARTWORK")
    portrait:SetPoint("TOPLEFT", portraitBG, "TOPLEFT", 1, -1)
    portrait:SetPoint("BOTTOMRIGHT", portraitBG, "BOTTOMRIGHT", -1, 1)
    portrait:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    row.portrait = portrait

    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("TOPLEFT", portraitBG, "TOPRIGHT", 12, -1)
    nameText:SetWidth(220)
    nameText:SetJustifyH("LEFT")
    row.nameText = nameText

    local keyLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    keyLabel:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -7)
    keyLabel:SetTextColor(0.75, 0.78, 0.82, 1)
    keyLabel:SetText("Weekly Key")
    row.keyLabel = keyLabel

    local scoreText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    scoreText:SetPoint("CENTER", row, "CENTER", -18, 0)
    scoreText:SetWidth(106)
    scoreText:SetJustifyH("CENTER")
    scoreText:SetTextColor(0.72, 0.86, 1, 1)
    row.scoreText = scoreText

    local keyTile = CreateFrame("Button", nil, row, "SecureActionButtonTemplate")
    keyTile:SetSize(46, 46)
    keyTile:SetPoint("TOPLEFT", row, "TOPLEFT", 336, -8)
    keyTile:RegisterForClicks("AnyUp", "AnyDown")

    local tileBG = keyTile:CreateTexture(nil, "BACKGROUND")
    tileBG:SetAllPoints(keyTile)
    tileBG:SetColorTexture(0.02, 0.03, 0.04, 0.82)

    local icon = keyTile:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", keyTile, "TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", keyTile, "BOTTOMRIGHT", -2, 2)
    icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    keyTile.icon = icon

    local levelText = keyTile:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    levelText:SetPoint("TOPLEFT", keyTile, "TOPLEFT", 2, -2)
    levelText:SetTextColor(1.0, 0.82, 0.2, 1)
    keyTile.levelText = levelText

    local dungeonText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dungeonText:SetPoint("LEFT", keyTile, "RIGHT", 12, 0)
    dungeonText:SetWidth(172)
    dungeonText:SetJustifyH("LEFT")
    dungeonText:SetTextColor(0.88, 0.9, 0.93, 1)
    row.dungeonText = dungeonText

    keyTile:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(self.dungeonLabel or "No key", 1, 1, 1)
        if self.keyLevel and self.keyLevel > 0 then
            GameTooltip:AddLine(string.format("Weekly Key: +%d", self.keyLevel), 1, 0.82, 0.2)
        else
            GameTooltip:AddLine("Weekly Key: None", 0.8, 0.8, 0.8)
        end
        if self.spellID then
            GameTooltip:AddLine(IsPortalSpellKnown(self.spellID) and "Click to cast portal" or "Portal not learned", 0.7, 0.82, 1)
        end
        GameTooltip:Show()
    end)
    keyTile:SetScript("OnLeave", GameTooltip_Hide)
    row.keyTile = keyTile

    ui.ksmPartyRows[index] = row
    return row
end

local function BuildKSMContext()
    return {
        ui = ui,
        floor = floor,
        min = min,
        max = max,
        KSM_GUILD_RECENT_DAYS = (_G.KeyMasterNS and _G.KeyMasterNS.KSM_GUILD_RECENT_DAYS) or 7,
        GetMythicPlusScore = GetMythicPlusScore,
        GetBestRunsFromHistory = GetBestRunsFromHistory,
        GetBestRunFromMapLookup = GetBestRunFromMapLookup,
        GetBestSeasonRunFromKnownMaps = GetBestSeasonRunFromKnownMaps,
        GetActiveKeystoneDetails = GetActiveKeystoneDetails,
        GetOwnedKeystoneSnapshot = GetOwnedKeystoneSnapshot,
        GetCurrentSeasonPortalEntries = GetCurrentSeasonPortalEntries,
        GetBestPortalRunForMap = GetBestPortalRunForMap,
        TrySetGreatVaultTexture = TrySetGreatVaultTexture,
        GetAffixDisplayInfo = GetAffixDisplayInfo,
        GetVaultProgressSummary = GetVaultProgressSummary,
        FormatBestRun = FormatBestRun,
        FormatBestRunNoScore = FormatBestRunNoScore,
        FormatDungeonLabel = FormatDungeonLabel,
        GetDungeonTileTexture = GetDungeonTileTexture,
        PrintLocal = PrintLocal,
        IsPortalSpellKnown = IsPortalSpellKnown,
        TryCastPortalSpell = TryCastPortalSpell,
        ConfigurePortalActionButton = ConfigurePortalActionButton,
        TryGetUnitMythicScore = TryGetUnitMythicScore,
        GetGuildMemberData = GetGuildMemberData,
        GetPlayerClassFile = GetPlayerClassFile,
        GetClassColorInfo = GetClassColorInfo,
        ApplyClassIcon = ApplyClassIcon,
        GetPortalSpellIDForMap = GetPortalSpellIDForMap,
        EnsureKSMDataLine = EnsureKSMDataLine,
        EnsureKSMPartyRow = EnsureKSMPartyRow,
        IsPlayerInGuildSafe = KMNS.IsPlayerInGuildSafe,
        RequestGuildRosterSafe = KMNS.RequestGuildRosterSafe,
        RequestGuildKeysFromAllSources = RequestGuildKeysFromAllSources,
        GetNormalizedPlayerName = GetNormalizedPlayerName,
        GetNumGuildMembersSafe = KMNS.GetNumGuildMembersSafe,
        TryGetMythicScoreForIdentifier = TryGetMythicScoreForIdentifier,
        IsGuildMemberRecent = KMNS.IsGuildMemberRecent,
        GetGuildMemberStore = GetGuildMemberStore,
        GetOwnCharacterStore = GetOwnCharacterStore,
        InvitePlayerByName = InvitePlayerByName,
        RemoveRecentEntryByName = RemoveRecentEntryByName,
        EnsureKSMGuildRow = EnsureKSMGuildRow,
        EnsureKSMRecentRow = EnsureKSMRecentRow,
        EnsureKSMWarbandRow = EnsureKSMWarbandRow,
    }
end

local function SetKSMActiveTab(tabName)
    local ksmModule = _G.KeyMasterNS and _G.KeyMasterNS.KSM
    if ksmModule and ksmModule.SetActiveTab then
        ksmModule.SetActiveTab(BuildKSMContext(), tabName)
    end
end

local function RefreshKSMMainTab()
    local ksmModule = _G.KeyMasterNS and _G.KeyMasterNS.KSM
    if ksmModule and ksmModule.RefreshMainTab then
        ksmModule.RefreshMainTab(BuildKSMContext())
    end
end

local function RefreshKSMPartyTab()
    local ksmModule = _G.KeyMasterNS and _G.KeyMasterNS.KSM
    if ksmModule and ksmModule.RefreshPartyTab then
        ksmModule.RefreshPartyTab(BuildKSMContext())
    end
end

local function RefreshKSMGuildTab()
    local ksmModule = _G.KeyMasterNS and _G.KeyMasterNS.KSM
    if ksmModule and ksmModule.RefreshGuildTab then
        ksmModule.RefreshGuildTab(BuildKSMContext())
    end
end

local function RefreshKSMRecentsTab()
    local ksmModule = _G.KeyMasterNS and _G.KeyMasterNS.KSM
    if ksmModule and ksmModule.RefreshRecentsTab then
        ksmModule.RefreshRecentsTab(BuildKSMContext())
    end
end

local function RefreshKSMWarbandTab()
    local ksmModule = _G.KeyMasterNS and _G.KeyMasterNS.KSM
    if ksmModule and ksmModule.RefreshWarbandTab then
        ksmModule.RefreshWarbandTab(BuildKSMContext())
    end
end

function RefreshKSMWindow()
    if not ui.ksmFrame then
        return
    end

    RefreshKSMMainTab()
    RefreshKSMPartyTab()
    RefreshKSMGuildTab()
    RefreshKSMRecentsTab()
    RefreshKSMWarbandTab()
end

function RefreshKSMWindowIfVisible()
    if ui.ksmFrame and ui.ksmFrame:IsShown() then
        RefreshKSMWindow()
    end
end

function CreateKSMWindow()
    if ui.ksmFrame then
        return
    end

    local frame = CreateFrame("Frame", "KeyStoneMasteryDashboard", UIParent, BackdropTemplateMixin and "BackdropTemplate")
    frame:SetSize(600, 560)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false,
        edgeSize = 12,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    frame:SetBackdropColor(0.02, 0.03, 0.04, 0.62)
    frame:SetBackdropBorderColor(0.22, 0.24, 0.28, 0.75)
    frame:Hide()

    local innerShade = frame:CreateTexture(nil, "BACKGROUND")
    innerShade:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
    innerShade:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    innerShade:SetColorTexture(0, 0, 0, 0.16)

    local accent = frame:CreateTexture(nil, "BORDER")
    accent:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    accent:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    accent:SetHeight(2)
    accent:SetColorTexture(0.24, 0.64, 1, 0.55)

    local title = CreateLine(frame, 16)
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -9)
    title:SetText("Mythic+ Dungeons")

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)

    local tabWidth = 102
    local tabHeight = 22
    local tabGap = 8
    local totalTabsWidth = (tabWidth * 5) + (tabGap * 4)
    local tabsStartX = floor(((frame:GetWidth() or 600) - totalTabsWidth) / 2 + 0.5)

    local function CreateTabButton(text, xOffset)
        local button = CreateFrame("Button", nil, frame)
        button:SetSize(tabWidth, tabHeight)
        button:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", xOffset, 9)

        local bg = button:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(button)
        bg:SetColorTexture(0.04, 0.05, 0.06, 0.58)
        button.bg = bg

        local border = button:CreateTexture(nil, "BORDER")
        border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
        border:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
        border:SetHeight(1)
        border:SetColorTexture(0.24, 0.24, 0.26, 0.95)
        button.borderTop = border
        
        local borderBottom = button:CreateTexture(nil, "BORDER")
        borderBottom:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
        borderBottom:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
        borderBottom:SetHeight(1)
        borderBottom:SetColorTexture(0.24, 0.24, 0.26, 0.95)
        button.borderBottom = borderBottom
        
        local borderLeft = button:CreateTexture(nil, "BORDER")
        borderLeft:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
        borderLeft:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
        borderLeft:SetWidth(1)
        borderLeft:SetColorTexture(0.24, 0.24, 0.26, 0.95)
        button.borderLeft = borderLeft
        
        local borderRight = button:CreateTexture(nil, "BORDER")
        borderRight:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
        borderRight:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
        borderRight:SetWidth(1)
        borderRight:SetColorTexture(0.24, 0.24, 0.26, 0.95)
        button.borderRight = borderRight
        
        local blueAccent = button:CreateTexture(nil, "OVERLAY")
        blueAccent:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 1, 1)
        blueAccent:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        blueAccent:SetHeight(2)
        blueAccent:SetColorTexture(0.24, 0.64, 1, 0)
        button.activeAccent = blueAccent
        
        local fontString = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fontString:SetAllPoints(button)
        fontString:SetText(text)
        fontString:SetTextColor(0.82, 0.84, 0.87, 1)
        fontString:SetFontObject("GameFontHighlightSmall")
        fontString:SetJustifyH("CENTER")
        fontString:SetJustifyV("MIDDLE")
        button.label = fontString
        button.isSelected = false
        
        button:SetScript("OnEnter", function(self)
            if not self.isSelected then
                self.bg:SetColorTexture(0.09, 0.1, 0.12, 0.76)
            end
        end)
        button:SetScript("OnLeave", function(self)
            if not self.isSelected then
                self.bg:SetColorTexture(0.04, 0.05, 0.06, 0.58)
            end
        end)
        
        return button
    end

    local mainTab = CreateTabButton("Main", tabsStartX)
    local partyTab = CreateTabButton("Party", tabsStartX + tabWidth + tabGap)
    local guildTab = CreateTabButton("Guild", tabsStartX + (tabWidth + tabGap) * 2)
    local recentsTab = CreateTabButton("Recents", tabsStartX + (tabWidth + tabGap) * 3)
    local warbandTab = CreateTabButton("Warband", tabsStartX + (tabWidth + tabGap) * 4)

    local mainContent = CreateFrame("Frame", nil, frame)
    mainContent:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -37)
    mainContent:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 40)

    local partyContent = CreateFrame("Frame", nil, frame)
    partyContent:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -37)
    partyContent:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 40)

    local guildContent = CreateFrame("Frame", nil, frame)
    guildContent:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -37)
    guildContent:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 40)

    local recentsContent = CreateFrame("Frame", nil, frame)
    recentsContent:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -37)
    recentsContent:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 40)

    local warbandContent = CreateFrame("Frame", nil, frame)
    warbandContent:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -37)
    warbandContent:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 40)

    ui.ksmFrame = frame
    ui.ksmMainTab = mainTab
    ui.ksmPartyTab = partyTab
    ui.ksmGuildTab = guildTab
    ui.ksmRecentsTab = recentsTab
    ui.ksmWarbandTab = warbandTab
    ui.ksmMainContent = mainContent
    ui.ksmPartyContent = partyContent
    ui.ksmGuildContent = guildContent
    ui.ksmRecentsContent = recentsContent
    ui.ksmWarbandContent = warbandContent

    local weeklyPanel = CreateFrame("Frame", nil, mainContent, BackdropTemplateMixin and "BackdropTemplate")
    weeklyPanel:SetSize(570, 280)
    weeklyPanel:SetPoint("TOP", mainContent, "TOP", 0, -8)
    weeklyPanel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false,
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    weeklyPanel:SetBackdropColor(0.02, 0.03, 0.04, 0.5)
    weeklyPanel:SetBackdropBorderColor(0.14, 0.18, 0.22, 0.0)
    weeklyPanel:SetBackdropColor(0.02, 0.03, 0.04, 0.0)

    local weeklyAccent = weeklyPanel:CreateTexture(nil, "BORDER")
    weeklyAccent:SetPoint("TOPLEFT", weeklyPanel, "TOPLEFT", 10, -4)
    weeklyAccent:SetPoint("TOPRIGHT", weeklyPanel, "TOPRIGHT", -10, -4)
    weeklyAccent:SetHeight(1)
    weeklyAccent:SetColorTexture(1, 1, 1, 0)

    local seasonPanel = CreateFrame("Frame", nil, mainContent, BackdropTemplateMixin and "BackdropTemplate")
    seasonPanel:SetSize(570, 150)
    seasonPanel:SetPoint("TOP", weeklyPanel, "BOTTOM", 0, -24)
    seasonPanel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false,
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    seasonPanel:SetBackdropColor(0.02, 0.03, 0.04, 0.5)
    seasonPanel:SetBackdropBorderColor(0.14, 0.18, 0.22, 0.0)
    seasonPanel:SetBackdropColor(0.02, 0.03, 0.04, 0.0)

    local seasonAccent = seasonPanel:CreateTexture(nil, "BORDER")
    seasonAccent:SetPoint("TOPLEFT", seasonPanel, "TOPLEFT", 10, -4)
    seasonAccent:SetPoint("TOPRIGHT", seasonPanel, "TOPRIGHT", -10, -4)
    seasonAccent:SetHeight(1)
    seasonAccent:SetColorTexture(1, 1, 1, 0)

    ui.ksmWeeklyPanel = weeklyPanel
    ui.ksmSeasonPanel = seasonPanel

    ui.ksmRatingLine = CreateLine(mainContent, 14)
    ui.ksmRatingLine:SetPoint("TOPLEFT", mainContent, "TOPLEFT", 10, -10)
    ui.ksmBestLine = CreateLine(mainContent, 12)
    ui.ksmBestLine:SetPoint("TOPLEFT", mainContent, "TOPLEFT", 10, -34)
    ui.ksmAffixLine = CreateLine(mainContent, 12)
    ui.ksmAffixLine:SetPoint("TOPLEFT", mainContent, "TOPLEFT", 10, -54)
    ui.ksmKeyLine = CreateLine(mainContent, 12)
    ui.ksmKeyLine:SetPoint("TOPLEFT", mainContent, "TOPLEFT", 10, -74)
    ui.ksmVaultLine = CreateLine(mainContent, 12)
    ui.ksmVaultLine:SetPoint("TOPLEFT", mainContent, "TOPLEFT", 10, -94)

    -- Centered Great Vault art button
    local vaultButton = CreateFrame("Button", nil, weeklyPanel)
    vaultButton:SetSize(128, 128)
    vaultButton:SetPoint("TOP", weeklyPanel, "TOP", 0, -106)

    local vaultPlate = vaultButton:CreateTexture(nil, "ARTWORK")
    vaultPlate:SetAllPoints(vaultButton)
    local usingCustomVaultArt = TrySetGreatVaultTexture(vaultPlate)

    local vaultLock = vaultButton:CreateTexture(nil, "OVERLAY")
    vaultLock:SetSize(40, 40)
    vaultLock:SetPoint("CENTER", vaultButton, "CENTER", 0, -2)
    vaultLock:SetTexture("Interface\\Buttons\\LockButton-Locked-Up")
    local _ = usingCustomVaultArt
    vaultLock:Hide()

    vaultButton.plate = vaultPlate
    vaultButton.lock = vaultLock
    vaultButton:SetScript("OnClick", function()
        if not TryOpenGreatVaultUI() then
            PrintLocal("Unable to open Great Vault in this client build")
        end
    end)
    vaultButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Open Great Vault", 1, 1, 1)
        GameTooltip:Show()
    end)
    vaultButton:SetScript("OnLeave", function(self)
        GameTooltip_Hide()
    end)

    ui.ksmVaultButton = vaultButton

    ui.ksmPortalsLabel = CreateLine(mainContent, 12)
    ui.ksmPortalsLabel:SetPoint("TOPLEFT", mainContent, "TOPLEFT", 10, -162)
    ui.ksmPortalsLabel:SetText("Current Season Portals")

    local function CreateGuildHeader(text, x, width)
        local header = guildContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        header:SetPoint("TOPLEFT", guildContent, "TOPLEFT", x, -11)
        header:SetWidth(width)
        header:SetJustifyH("LEFT")
        header:SetTextColor(1, 1, 1, 0.95)
        header:SetText(text)
        return header
    end

    CreateGuildHeader("Class", 10, 44)
    CreateGuildHeader("Player Name", 34, 165)
    CreateGuildHeader("Key", 208, 34)
    CreateGuildHeader("Dungeon", 250, 180)
    CreateGuildHeader("Rating", 440, 54)
    CreateGuildHeader("Portal", 502, 60)

    local function CreateRecentsHeader(text, x, width)
        local header = recentsContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        header:SetPoint("TOPLEFT", recentsContent, "TOPLEFT", x, -11)
        header:SetWidth(width)
        header:SetJustifyH("LEFT")
        header:SetTextColor(1, 1, 1, 0.95)
        header:SetText(text)
        return header
    end

    CreateRecentsHeader("Class", 10, 44)
    CreateRecentsHeader("Player Name", 34, 165)
    CreateRecentsHeader("Key", 208, 34)
    CreateRecentsHeader("Dungeon", 250, 180)
    CreateRecentsHeader("Rating", 440, 54)
    CreateRecentsHeader("Portal", 502, 60)

    local function CreateWarbandHeader(text, x, width)
        local header = warbandContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        header:SetPoint("TOPLEFT", warbandContent, "TOPLEFT", x, -11)
        header:SetWidth(width)
        header:SetJustifyH("LEFT")
        header:SetTextColor(1, 1, 1, 0.95)
        header:SetText(text)
        return header
    end

    CreateWarbandHeader("Class", 10, 44)
    CreateWarbandHeader("Player Name", 34, 165)
    CreateWarbandHeader("Key", 208, 34)
    CreateWarbandHeader("Dungeon", 250, 180)
    CreateWarbandHeader("Rating", 440, 54)
    CreateWarbandHeader("Portal", 502, 60)

    local requestGuildButton = CreateFrame("Button", nil, guildContent)
    requestGuildButton:SetSize(148, 20)
    requestGuildButton:SetPoint("BOTTOM", guildContent, "BOTTOM", 0, 8)

    local requestGuildButtonBg = requestGuildButton:CreateTexture(nil, "BACKGROUND")
    requestGuildButtonBg:SetAllPoints(requestGuildButton)
    requestGuildButtonBg:SetColorTexture(0.06, 0.06, 0.06, 0.88)

    local requestGuildButtonBorder = requestGuildButton:CreateTexture(nil, "BORDER")
    requestGuildButtonBorder:SetPoint("TOPLEFT", requestGuildButton, "TOPLEFT", 0, 0)
    requestGuildButtonBorder:SetPoint("BOTTOMRIGHT", requestGuildButton, "BOTTOMRIGHT", 0, 0)
    requestGuildButtonBorder:SetColorTexture(1, 1, 1, 0.18)

    local requestGuildButtonAccent = requestGuildButton:CreateTexture(nil, "OVERLAY")
    requestGuildButtonAccent:SetPoint("TOPLEFT", requestGuildButton, "TOPLEFT", 0, 0)
    requestGuildButtonAccent:SetPoint("TOPRIGHT", requestGuildButton, "TOPRIGHT", 0, 0)
    requestGuildButtonAccent:SetHeight(2)
    requestGuildButtonAccent:SetColorTexture(0.24, 0.64, 1, 0.85)

    local requestGuildButtonText = requestGuildButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    requestGuildButtonText:SetAllPoints(requestGuildButton)
    requestGuildButtonText:SetText("Request Guild Keys")
    requestGuildButtonText:SetTextColor(0.9, 0.95, 1, 1)

    requestGuildButton:SetScript("OnEnter", function()
        requestGuildButtonBg:SetColorTexture(0.1, 0.1, 0.1, 0.95)
    end)
    requestGuildButton:SetScript("OnLeave", function()
        requestGuildButtonBg:SetColorTexture(0.06, 0.06, 0.06, 0.88)
    end)
    requestGuildButton:SetScript("OnClick", function()
        local requested = RequestGuildKeysFromAllSources(true, true)
        RefreshKSMWindowIfVisible()
        if requested and C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(2, function()
                RequestGuildKeysFromAllSources(true, true)
                RefreshKSMWindowIfVisible()
            end)
            C_Timer.After(8, function()
                RequestGuildKeysFromAllSources(true, true)
                RefreshKSMWindowIfVisible()
            end)
        end
        if requested then
            PrintLocal("Requested guild keystone updates")
        else
            PrintLocal("Unable to request guild keys (not in a guild or request cooldown active)")
        end
    end)
    ui.ksmGuildRequestButton = requestGuildButton

    local function CreateGuildPagerButton(labelText, xOffset)
        local button = CreateFrame("Button", nil, guildContent)
        button:SetSize(46, 20)
        button:SetPoint("BOTTOM", guildContent, "BOTTOM", xOffset, 8)

        local bg = button:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(button)
        bg:SetColorTexture(0.06, 0.06, 0.06, 0.88)

        local border = button:CreateTexture(nil, "BORDER")
        border:SetAllPoints(button)
        border:SetColorTexture(1, 1, 1, 0.16)

        local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetAllPoints(button)
        text:SetText(labelText)
        text:SetTextColor(0.9, 0.95, 1, 1)

        button:SetScript("OnEnter", function()
            if button:IsEnabled() then
                bg:SetColorTexture(0.1, 0.1, 0.1, 0.95)
            end
        end)
        button:SetScript("OnLeave", function()
            bg:SetColorTexture(0.06, 0.06, 0.06, 0.88)
        end)

        return button
    end

    local prevPageButton = CreateGuildPagerButton("<", -122)
    prevPageButton:SetScript("OnClick", function()
        ui.ksmGuildPage = max(1, (ui.ksmGuildPage or 1) - 1)
        RefreshKSMWindowIfVisible()
    end)

    local nextPageButton = CreateGuildPagerButton(">", 122)
    nextPageButton:SetScript("OnClick", function()
        ui.ksmGuildPage = (ui.ksmGuildPage or 1) + 1
        RefreshKSMWindowIfVisible()
    end)

    local guildPageText = guildContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    guildPageText:SetPoint("BOTTOM", guildContent, "BOTTOM", 0, 32)
    guildPageText:SetTextColor(0.82, 0.88, 0.95, 1)
    guildPageText:SetText("Page 1/1")

    local hideOfflineCheck = CreateFrame("CheckButton", nil, guildContent, "UICheckButtonTemplate")
    hideOfflineCheck:SetPoint("BOTTOMLEFT", guildContent, "BOTTOMLEFT", 8, 6)
    local hideOfflineLabel = guildContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hideOfflineLabel:SetPoint("LEFT", hideOfflineCheck, "RIGHT", 2, 0)
    hideOfflineLabel:SetTextColor(0.9, 0.95, 1, 1)
    hideOfflineLabel:SetText("Hide Offline")
    hideOfflineCheck:SetChecked(ui.ksmHideOffline == true)
    hideOfflineCheck:SetScript("OnClick", function(self)
        ui.ksmHideOffline = self:GetChecked() == true
        ui.ksmGuildPage = 1
        InitializeDatabase().ui.hideOfflineGuild = ui.ksmHideOffline
        RefreshKSMWindowIfVisible()
    end)

    ui.ksmGuildPrevButton = prevPageButton
    ui.ksmGuildNextButton = nextPageButton
    ui.ksmGuildPageText = guildPageText
    ui.ksmGuildHideOfflineCheck = hideOfflineCheck

    local requestRecentsButton = CreateFrame("Button", nil, recentsContent)
    requestRecentsButton:SetSize(156, 20)
    requestRecentsButton:SetPoint("BOTTOM", recentsContent, "BOTTOM", 0, 8)

    local requestRecentsButtonBg = requestRecentsButton:CreateTexture(nil, "BACKGROUND")
    requestRecentsButtonBg:SetAllPoints(requestRecentsButton)
    requestRecentsButtonBg:SetColorTexture(0.06, 0.06, 0.06, 0.88)

    local requestRecentsButtonBorder = requestRecentsButton:CreateTexture(nil, "BORDER")
    requestRecentsButtonBorder:SetPoint("TOPLEFT", requestRecentsButton, "TOPLEFT", 0, 0)
    requestRecentsButtonBorder:SetPoint("BOTTOMRIGHT", requestRecentsButton, "BOTTOMRIGHT", 0, 0)
    requestRecentsButtonBorder:SetColorTexture(1, 1, 1, 0.18)

    local requestRecentsButtonAccent = requestRecentsButton:CreateTexture(nil, "OVERLAY")
    requestRecentsButtonAccent:SetPoint("TOPLEFT", requestRecentsButton, "TOPLEFT", 0, 0)
    requestRecentsButtonAccent:SetPoint("TOPRIGHT", requestRecentsButton, "TOPRIGHT", 0, 0)
    requestRecentsButtonAccent:SetHeight(2)
    requestRecentsButtonAccent:SetColorTexture(0.24, 0.64, 1, 0.85)

    local requestRecentsButtonText = requestRecentsButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    requestRecentsButtonText:SetAllPoints(requestRecentsButton)
    requestRecentsButtonText:SetText("Request Group Keys")
    requestRecentsButtonText:SetTextColor(0.9, 0.95, 1, 1)

    requestRecentsButton:SetScript("OnEnter", function()
        requestRecentsButtonBg:SetColorTexture(0.1, 0.1, 0.1, 0.95)
    end)
    requestRecentsButton:SetScript("OnLeave", function()
        requestRecentsButtonBg:SetColorTexture(0.06, 0.06, 0.06, 0.88)
    end)
    requestRecentsButton:SetScript("OnClick", function()
        local requested = RequestGuildKeysFromAllSources(true, true)
        RefreshKSMWindowIfVisible()
        if requested then
            PrintLocal("Requested group and guild keystone updates")
        else
            PrintLocal("Unable to request keys (not grouped/guilded or request cooldown active)")
        end
    end)

    local recentsPrevPageButton = CreateGuildPagerButton("<", -122)
    recentsPrevPageButton:ClearAllPoints()
    recentsPrevPageButton:SetPoint("BOTTOM", recentsContent, "BOTTOM", -122, 8)
    recentsPrevPageButton:SetScript("OnClick", function()
        ui.ksmRecentsPage = max(1, (ui.ksmRecentsPage or 1) - 1)
        RefreshKSMWindowIfVisible()
    end)

    local recentsNextPageButton = CreateGuildPagerButton(">", 122)
    recentsNextPageButton:ClearAllPoints()
    recentsNextPageButton:SetPoint("BOTTOM", recentsContent, "BOTTOM", 122, 8)
    recentsNextPageButton:SetScript("OnClick", function()
        ui.ksmRecentsPage = (ui.ksmRecentsPage or 1) + 1
        RefreshKSMWindowIfVisible()
    end)

    local recentsPageText = recentsContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    recentsPageText:SetPoint("BOTTOM", recentsContent, "BOTTOM", 0, 32)
    recentsPageText:SetTextColor(0.82, 0.88, 0.95, 1)
    recentsPageText:SetText("Page 1/1")

    ui.ksmRecentsRequestButton = requestRecentsButton
    ui.ksmRecentsPrevButton = recentsPrevPageButton
    ui.ksmRecentsNextButton = recentsNextPageButton
    ui.ksmRecentsPageText = recentsPageText

    local warbandRefreshButton = CreateFrame("Button", nil, warbandContent)
    warbandRefreshButton:SetSize(156, 20)
    warbandRefreshButton:SetPoint("BOTTOM", warbandContent, "BOTTOM", 0, 8)

    local warbandRefreshButtonBg = warbandRefreshButton:CreateTexture(nil, "BACKGROUND")
    warbandRefreshButtonBg:SetAllPoints(warbandRefreshButton)
    warbandRefreshButtonBg:SetColorTexture(0.06, 0.06, 0.06, 0.88)

    local warbandRefreshButtonBorder = warbandRefreshButton:CreateTexture(nil, "BORDER")
    warbandRefreshButtonBorder:SetPoint("TOPLEFT", warbandRefreshButton, "TOPLEFT", 0, 0)
    warbandRefreshButtonBorder:SetPoint("BOTTOMRIGHT", warbandRefreshButton, "BOTTOMRIGHT", 0, 0)
    warbandRefreshButtonBorder:SetColorTexture(1, 1, 1, 0.18)

    local warbandRefreshButtonAccent = warbandRefreshButton:CreateTexture(nil, "OVERLAY")
    warbandRefreshButtonAccent:SetPoint("TOPLEFT", warbandRefreshButton, "TOPLEFT", 0, 0)
    warbandRefreshButtonAccent:SetPoint("TOPRIGHT", warbandRefreshButton, "TOPRIGHT", 0, 0)
    warbandRefreshButtonAccent:SetHeight(2)
    warbandRefreshButtonAccent:SetColorTexture(0.24, 0.64, 1, 0.85)

    local warbandRefreshButtonText = warbandRefreshButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    warbandRefreshButtonText:SetAllPoints(warbandRefreshButton)
    warbandRefreshButtonText:SetText("Refresh Warband")
    warbandRefreshButtonText:SetTextColor(0.9, 0.95, 1, 1)

    warbandRefreshButton:SetScript("OnEnter", function()
        warbandRefreshButtonBg:SetColorTexture(0.1, 0.1, 0.1, 0.95)
    end)
    warbandRefreshButton:SetScript("OnLeave", function()
        warbandRefreshButtonBg:SetColorTexture(0.06, 0.06, 0.06, 0.88)
    end)
    warbandRefreshButton:SetScript("OnClick", function()
        RefreshKSMWindowIfVisible()
    end)

    local warbandPrevPageButton = CreateGuildPagerButton("<", -122)
    warbandPrevPageButton:ClearAllPoints()
    warbandPrevPageButton:SetPoint("BOTTOM", warbandContent, "BOTTOM", -122, 8)
    warbandPrevPageButton:SetScript("OnClick", function()
        ui.ksmWarbandPage = max(1, (ui.ksmWarbandPage or 1) - 1)
        RefreshKSMWindowIfVisible()
    end)

    local warbandNextPageButton = CreateGuildPagerButton(">", 122)
    warbandNextPageButton:ClearAllPoints()
    warbandNextPageButton:SetPoint("BOTTOM", warbandContent, "BOTTOM", 122, 8)
    warbandNextPageButton:SetScript("OnClick", function()
        ui.ksmWarbandPage = (ui.ksmWarbandPage or 1) + 1
        RefreshKSMWindowIfVisible()
    end)

    local warbandPageText = warbandContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    warbandPageText:SetPoint("BOTTOM", warbandContent, "BOTTOM", 0, 32)
    warbandPageText:SetTextColor(0.82, 0.88, 0.95, 1)
    warbandPageText:SetText("Page 1/1")

    ui.ksmWarbandRefreshButton = warbandRefreshButton
    ui.ksmWarbandPrevButton = warbandPrevPageButton
    ui.ksmWarbandNextButton = warbandNextPageButton
    ui.ksmWarbandPageText = warbandPageText

    mainTab:SetScript("OnClick", function()
        SetKSMActiveTab("main")
        RefreshKSMWindow()
    end)
    partyTab:SetScript("OnClick", function()
        SetKSMActiveTab("party")
        RefreshKSMWindow()
    end)
    guildTab:SetScript("OnClick", function()
        SetKSMActiveTab("guild")
        RefreshKSMWindow()
    end)
    recentsTab:SetScript("OnClick", function()
        SetKSMActiveTab("recents")
        RefreshKSMWindow()
    end)
    warbandTab:SetScript("OnClick", function()
        SetKSMActiveTab("warband")
        RefreshKSMWindow()
    end)

    frame:SetScript("OnShow", function()
        RefreshKSMWindow()
    end)

    SetKSMActiveTab("main")
end

SLASH_KEYSTONEMASTER1 = "/ksm"
SlashCmdList.KEYSTONEMASTER = function(message)
    CreateKSMWindow()
    local command = strtrim(strlower(message or ""))

    if command == "" or command == "toggle" then
        if ui.ksmFrame:IsShown() then
            ui.ksmFrame:Hide()
        else
            ui.ksmFrame:Show()
            SetKSMActiveTab("main")
            RefreshKSMWindow()
        end
        return
    end

    if command == "show" then
        ui.ksmFrame:Show()
        SetKSMActiveTab("main")
        RefreshKSMWindow()
        return
    end

    if command == "hide" then
        ui.ksmFrame:Hide()
        return
    end

    if command == "main" or command == "party" or command == "guild" or command == "recents" or command == "warband" then
        ui.ksmFrame:Show()
        SetKSMActiveTab(command)
        RefreshKSMWindow()
        return
    end

    if command == "refresh" then
        RefreshKSMWindowIfVisible()
        return
    end

    PrintLocal("unknown /ksm command. Use: show, hide, toggle, main, party, guild, recents, warband, refresh")
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
        PrintLocal("Use /ksm for the tabbed Mythic+ dashboard window")
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

function PerformLoginInitialization()
    if ui.loginInitialized then
        return
    end

    ui.loginInitialized = true
    local db = InitializeDatabase()
    ui.ksmHideOffline = db.ui.hideOfflineGuild == true
    CreateMythicUI()
    RegisterSettingsPanel()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, KSM_ADDON_PREFIX)
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, ASTRAL_KEYS_PREFIX)
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, DETAILS_OPENRAID_PREFIX)
    end
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_ChallengesUI") then
        HookChallengesFrame()
    end
    ObserveOwnedKeystone(false)
    BroadcastOwnGuildSnapshot()
    QueueOwnSnapshotPersistRetry(2)
    QueueOwnSnapshotPersistRetry(8)
    RequestGuildKeysFromAllSources(true, true)
    RefreshMythicUI()
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
        RegisterRuntimeEvents()
        PerformLoginInitialization()
        return
    end

    if event == "PLAYER_REGEN_ENABLED" and runtimeRegistrationDeferred and not runtimeEventsRegistered then
        RegisterRuntimeEvents()
    end

    if event == "PLAYER_ENTERING_WORLD" then
        PersistOwnGuildSnapshot()
        QueueOwnSnapshotPersistRetry(2)
        QueueOwnSnapshotPersistRetry(8)
        return
    end

    if event == "PLAYER_LOGOUT" then
        PersistOwnGuildSnapshot()
        return
    end

    if event == "CHAT_MSG_ADDON" then
        HandleAddonMessage(...)
        return
    end

    if event == "GUILD_ROSTER_UPDATE" then
        RequestGuildKeysFromAllSources(false, true)
        RefreshKSMWindowIfVisible()
        return
    end

    if event == "GROUP_ROSTER_UPDATE" then
        RequestGuildKeysFromAllSources(false, true)
        RefreshKSMWindowIfVisible()
        return
    end

    local runStateModule = _G.KeyMasterNS and _G.KeyMasterNS.RunState

    if runStateModule and runStateModule.HandleChallengeLifecycleEvent
        and runStateModule.HandleChallengeLifecycleEvent(BuildRunStateContext(), event) then
        return
    end

    if runStateModule and runStateModule.HandleCombatLogEvent
        and runStateModule.HandleCombatLogEvent(BuildRunStateContext(), event) then
        return
    end

    if runStateModule and runStateModule.HandleGroupStateEvent
        and runStateModule.HandleGroupStateEvent(BuildRunStateContext(), event) then
        return
    end

    if runStateModule and runStateModule.HandleRunRefreshEvent
        and runStateModule.HandleRunRefreshEvent(BuildRunStateContext(), event) then
        return
    end

    HandleChatMessage(event, ...)
end)
