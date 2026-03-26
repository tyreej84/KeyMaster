local addonName = ...

local floor = math.floor
local min = math.min
local tconcat = table.concat
local strlower = string.lower
local strtrim = strtrim

local frame = CreateFrame("Frame")
local REPLY_PREFIX = "KeyMaster:"
local KEYSTONE_ITEM_IDS = { [180653] = true, [158923] = true, [151086] = true }
local KEYSTONE_BAG_SLOTS = { Enum.BagIndex.Backpack, Enum.BagIndex.Bag_1, Enum.BagIndex.Bag_2, Enum.BagIndex.Bag_3, Enum.BagIndex.Bag_4 }
local KEYS_TEXT_COMMAND = "!keys"
local KEY_TEXT_COMMAND = "!key"
local SCORE_TEXT_COMMAND = "!score"
local VAULT_TEXT_COMMAND = "!vault"
local WEEKLY_TEXT_COMMAND = "!weekly"
local BEST_TEXT_COMMAND = "!best"
local MISMATCH_TOAST_COOLDOWN_SECONDS = 2
local lastMismatchToastAt = 0
local DEBUG_HISTORY_LIMIT = 25

local function IsDebugEnabled()
    return KeyMasterDB and KeyMasterDB.debug == true
end

local function AppendDebugHistory(message)
    if not KeyMasterDB then
        KeyMasterDB = {}
    end

    if type(KeyMasterDB.debugLog) ~= "table" then
        KeyMasterDB.debugLog = {}
    end

    table.insert(KeyMasterDB.debugLog, message)
    while #KeyMasterDB.debugLog > DEBUG_HISTORY_LIMIT do
        table.remove(KeyMasterDB.debugLog, 1)
    end
end

local function DebugPrint(...)
    if not IsDebugEnabled() then
        return
    end

    local parts = { ... }
    local message = tconcat(parts, " ")
    AppendDebugHistory(message)

    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage("KeyMaster Debug: " .. message, 0.2, 1.0, 0.4, 1.0)
    end

    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99KeyMaster Debug:|r " .. message)
    else
        print("KeyMaster Debug: " .. message)
    end
end

local function SafeDebugValue(value)
    if value == nil then
        return "<nil>"
    end

    return tostring(value)
end

SLASH_KEYMASTER1 = "/keymaster"
SLASH_KEYMASTER2 = "/km"
SlashCmdList.KEYMASTER = function(message)
    local msg = strtrim(strlower(message or ""))

    if msg == "debug" then
        KeyMasterDB = KeyMasterDB or {}
        KeyMasterDB.debug = not KeyMasterDB.debug
        print(string.format("KeyMaster: debug %s", KeyMasterDB.debug and "enabled" or "disabled"))
        return
    end

    if msg == "debuglog" then
        KeyMasterDB = KeyMasterDB or {}
        local debugLog = KeyMasterDB.debugLog or {}
        print(string.format("KeyMaster: debug log entries: %d", #debugLog))
        for index, entry in ipairs(debugLog) do
            print(string.format("KeyMaster Debug[%d]: %s", index, tostring(entry)))
        end
        return
    end

    if msg ~= "" then
        print("KeyMaster: slash command is active.")
        return
    end

    print("KeyMaster: loaded")
end

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
        return name
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

    -- Keep this local-only and out of chat by using UI error text.
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(message, 1.0, 0.1, 0.1, 1.0)
    end
end

local function ShowMismatchToast(ownedMapID, receptacleMapID)
    local now = GetTime()
    if (now - lastMismatchToastAt) < MISMATCH_TOAST_COOLDOWN_SECONDS then
        return
    end

    lastMismatchToastAt = now

    local ownedName = FormatDungeonLabel(ownedMapID)
    local receptacleName = FormatDungeonLabel(receptacleMapID)
    local message = string.format("KeyMaster: Key mismatch (%s vs %s)", ownedName, receptacleName)
    ShowLocalToast(message)
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
        KEYSTONE_ITEM_ID,
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
        DebugPrint("Resolved keystone link:", SafeDebugValue(keyLink))
        return string.format("%s %s", REPLY_PREFIX, keyLink)
    end

    DebugPrint("Failed to resolve keystone link")
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

local function BuildVaultReply()
    if not (C_WeeklyRewards and C_WeeklyRewards.GetActivities) then
        return nil
    end

    local ok, activities = pcall(C_WeeklyRewards.GetActivities)
    if not ok or type(activities) ~= "table" then
        return nil
    end

    local activitiesType = Enum and Enum.WeeklyRewardChestThresholdType and Enum.WeeklyRewardChestThresholdType.Activities or 1
    local byThreshold = {}

    for _, activity in ipairs(activities) do
        local threshold = activity and (activity.threshold or activity.level)
        local progress = activity and activity.progress
        local activityType = activity and activity.type
        if type(threshold) == "number" and type(progress) == "number" and (activityType == activitiesType or activityType == 1) then
            local capped = min(progress, threshold)
            byThreshold[threshold] = string.format("%d/%d", capped, threshold)
        end
    end

    local t1 = byThreshold[1] or "0/1"
    local t4 = byThreshold[4] or "0/4"
    local t8 = byThreshold[8] or "0/8"

    return string.format("%s Vault M+: %s %s %s", REPLY_PREFIX, t1, t4, t8)
end

local function ResolveBestLevel(result1, result2)
    if type(result1) == "number" then
        return result1
    end

    if type(result1) == "table" then
        return result1.level or result1.bestRunLevel or result1.completedLevel or result1.keystoneLevel
    end

    if type(result2) == "number" then
        return result2
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
    local weekBest = GetBestRunFromMapLookup("GetWeeklyBestForMap")
    local seasonBest = GetBestRunFromMapLookup("GetSeasonBestForMap")

    if not weekBest or not seasonBest then
        local historyWeekBest, historySeasonBest = GetBestRunsFromHistory()
        weekBest = weekBest or historyWeekBest
        seasonBest = seasonBest or historySeasonBest
    end

    if not weekBest and not seasonBest then
        return nil
    end

    return string.format(
        "%s Best - Week: %s | Season: %s",
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
        or msg == VAULT_TEXT_COMMAND
        or msg == WEEKLY_TEXT_COMMAND
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

    if msg == VAULT_TEXT_COMMAND or msg == WEEKLY_TEXT_COMMAND then
        return BuildVaultReply()
    end

    if msg == BEST_TEXT_COMMAND then
        return BuildBestReply()
    end

    return nil
end

local function HandleChatMessage(event, message, sender)
    if not CHAT_EVENTS[event] then
        return
    end

    DebugPrint("Event:", tostring(event), "Message:", tostring(message), "Sender:", tostring(sender))

    if not IsKeyRequestMessage(message) then
        return
    end

    local reply = BuildReplyForCommand(message)
    if not reply then
        DebugPrint("No reply generated for command:", tostring(message))
        return
    end

    DebugPrint("Built reply:", SafeDebugValue(reply))

    local chatType = CHAT_EVENT_TO_CHANNEL[event]
    if not chatType then
        DebugPrint("No chat type mapping for event:", tostring(event))
        return
    end

    DebugPrint("Sending reply via channel:", SafeDebugValue(chatType))

    local ok, err
    if chatType == "WHISPER" then
        ok, err = pcall(SendChatMessage, reply, chatType, nil, sender)
    else
        ok, err = pcall(SendChatMessage, reply, chatType)
    end

    if not ok then
        DebugPrint("SendChatMessage failed:", SafeDebugValue(err))
        return
    end

    DebugPrint("Sent reply:", tostring(reply), "Channel:", tostring(chatType))
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
    if ChallengesKeystoneFrame then
        ChallengesKeystoneFrame:HookScript("OnShow", TryAutoSlotKeystone)
        DebugPrint("Hooked ChallengesKeystoneFrame OnShow for auto-slot")
    end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CHAT_MSG_PARTY")
frame:RegisterEvent("CHAT_MSG_RAID")
frame:RegisterEvent("CHAT_MSG_GUILD")

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == "Blizzard_ChallengesUI" then
            HookChallengesFrame()
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        if not KeyMasterDB then
            KeyMasterDB = {}
        end
        if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_ChallengesUI") then
            HookChallengesFrame()
        end
        DebugPrint("Player logged in, initialized KeyMasterDB")
        return
    end

    DebugPrint("Chat event received:", tostring(event))
    HandleChatMessage(event, ...)
end)
