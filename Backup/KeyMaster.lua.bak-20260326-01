local addonName = ...

local floor = math.floor
local strlower = string.lower
local strtrim = strtrim

local frame = CreateFrame("Frame")
local REPLY_PREFIX = "KeyMaster:"
local KEYSTONE_ITEM_IDS = { [180653] = true, [158923] = true, [151086] = true }
local KEYSTONE_BAG_SLOTS = { Enum.BagIndex.Backpack, Enum.BagIndex.Bag_1, Enum.BagIndex.Bag_2, Enum.BagIndex.Bag_3, Enum.BagIndex.Bag_4 }
local KEYS_TEXT_COMMAND = "!keys"
local KEY_TEXT_COMMAND = "!key"
local SCORE_TEXT_COMMAND = "!score"
local BEST_TEXT_COMMAND = "!best"
local MISMATCH_TOAST_COOLDOWN_SECONDS = 2
local lastMismatchToastAt = 0

SLASH_KEYMASTER1 = "/keymaster"
SLASH_KEYMASTER2 = "/km"
SlashCmdList.KEYMASTER = function()
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

    -- Sanity check: key levels are 2-40; anything outside that range is not a key level
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
    -- Use run history as primary source (proven reliable); API map-lookup as fallback
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
        return
    end

    HandleChatMessage(event, ...)
end)
