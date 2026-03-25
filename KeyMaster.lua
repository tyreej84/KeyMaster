local addonName = ...

local frame = CreateFrame("Frame")
local REPLY_PREFIX = "KeyMaster:"
local KEYSTONE_ITEM_ID = 180653
local KEYS_TEXT_COMMAND = "!keys"
local KEY_TEXT_COMMAND = "!key"
local SCORE_TEXT_COMMAND = "!score"
local VAULT_TEXT_COMMAND = "!vault"
local WEEKLY_TEXT_COMMAND = "!weekly"
local BEST_TEXT_COMMAND = "!best"
local MISMATCH_TOAST_COOLDOWN_SECONDS = 2
local lastMismatchToastAt = 0

local CHAT_EVENTS = {
    CHAT_MSG_PARTY = true,
    CHAT_MSG_PARTY_LEADER = true,
    CHAT_MSG_RAID = true,
    CHAT_MSG_RAID_LEADER = true,
    CHAT_MSG_GUILD = true,
}

local CHAT_EVENT_TO_CHANNEL = {
    CHAT_MSG_PARTY = "PARTY",
    CHAT_MSG_PARTY_LEADER = "PARTY",
    CHAT_MSG_RAID = "RAID",
    CHAT_MSG_RAID_LEADER = "RAID",
    CHAT_MSG_GUILD = "GUILD",
}

local function NormalizeName(fullName)
    return Ambiguate(fullName or "", "short")
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

    if C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo then
        for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
            local slots = C_Container.GetContainerNumSlots(bag)
            for slot = 1, slots do
                local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
                if itemInfo and itemInfo.itemID == KEYSTONE_ITEM_ID then
                    return itemInfo.hyperlink or C_Container.GetContainerItemLink(bag, slot)
                end
            end
        end
    end

    return nil
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

    local msg = strtrim(string.lower(message))
    return msg == KEY_TEXT_COMMAND
        or msg == KEYS_TEXT_COMMAND
        or msg == SCORE_TEXT_COMMAND
        or msg == VAULT_TEXT_COMMAND
        or msg == WEEKLY_TEXT_COMMAND
        or msg == BEST_TEXT_COMMAND
end

local function BuildReplyForCommand(message)
    local msg = strtrim(string.lower(message or ""))

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

    SendChatMessage(reply, chatType)
end

local function GetCurrentReceptacleMapID(...)
    local arg1 = ...
    if type(arg1) == "number" and arg1 > 0 then
        return arg1
    end

    if C_Map and C_Map.GetBestMapForUnit and C_ChallengeMode and C_ChallengeMode.GetMapIDFromWorldMapAreaID then
        local uiMapID = C_Map.GetBestMapForUnit("player")
        if uiMapID then
            local challengeMapID = C_ChallengeMode.GetMapIDFromWorldMapAreaID(uiMapID)
            if challengeMapID and challengeMapID > 0 then
                return challengeMapID
            end
        end
    end

    if C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID then
        local activeMapID = C_ChallengeMode.GetActiveChallengeMapID()
        if activeMapID and activeMapID > 0 then
            return activeMapID
        end
    end

    return nil
end

local function TryAutoSlotKeystone(...)
    if not (C_ChallengeMode and C_ChallengeMode.SlotKeystone) then
        return
    end

    local ownedMapID = GetOwnedKeystoneMapID()

    local receptacleMapID = GetCurrentReceptacleMapID(...)
    if ownedMapID and receptacleMapID and ownedMapID ~= receptacleMapID then
        ShowMismatchToast(ownedMapID, receptacleMapID)
        return
    end

    C_ChallengeMode.SlotKeystone()
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CHAT_MSG_PARTY")
frame:RegisterEvent("CHAT_MSG_PARTY_LEADER")
frame:RegisterEvent("CHAT_MSG_RAID")
frame:RegisterEvent("CHAT_MSG_RAID_LEADER")
frame:RegisterEvent("CHAT_MSG_GUILD")
frame:RegisterEvent("CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN")
frame:RegisterEvent("CHALLENGE_MODE_KEYSTONE_RECEPTACLE_OPEN")

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        if not KeyMasterDB then
            KeyMasterDB = {}
        end
        return
    end

    if event == "CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN" or event == "CHALLENGE_MODE_KEYSTONE_RECEPTACLE_OPEN" then
        TryAutoSlotKeystone(...)
        return
    end

    HandleChatMessage(event, ...)
end)
