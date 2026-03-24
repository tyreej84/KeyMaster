local addonName = ...

local frame = CreateFrame("Frame")

local CHAT_EVENTS = {
    CHAT_MSG_PARTY = true,
    CHAT_MSG_PARTY_LEADER = true,
    CHAT_MSG_INSTANCE_CHAT = true,
    CHAT_MSG_INSTANCE_CHAT_LEADER = true,
    CHAT_MSG_RAID = true,
    CHAT_MSG_RAID_LEADER = true,
}

local CHAT_EVENT_TO_CHANNEL = {
    CHAT_MSG_PARTY = "PARTY",
    CHAT_MSG_PARTY_LEADER = "PARTY",
    CHAT_MSG_INSTANCE_CHAT = "INSTANCE_CHAT",
    CHAT_MSG_INSTANCE_CHAT_LEADER = "INSTANCE_CHAT",
    CHAT_MSG_RAID = "RAID",
    CHAT_MSG_RAID_LEADER = "RAID",
}

local function NormalizeName(fullName)
    return Ambiguate(fullName or "", "short")
end

local function IsOwnMessage(sender)
    local me = UnitName("player")
    return NormalizeName(sender) == NormalizeName(me)
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

local function GetOwnedKeystoneLink()
    if C_MythicPlus and C_MythicPlus.GetOwnedKeystoneLink then
        return C_MythicPlus.GetOwnedKeystoneLink()
    end

    return nil
end

local function BuildKeystoneReply()
    local level = GetOwnedKeystoneLevel()
    local mapID = GetOwnedKeystoneMapID()

    if not level or level <= 0 or not mapID then
        return nil
    end

    local keyLink = GetOwnedKeystoneLink()
    if keyLink then
        return "I have " .. keyLink
    end

    local mapName = GetKeystoneMapName(mapID)
    if mapName then
        return string.format("I have a +%d %s key.", level, mapName)
    end

    return string.format("I have a +%d key.", level)
end

local function IsKeyRequestMessage(message)
    if not message then
        return false
    end

    local msg = strtrim(string.lower(message))
    return msg == "!key" or msg == "!keys"
end

local function HandleChatMessage(event, message, sender)
    if not CHAT_EVENTS[event] then
        return
    end

    if IsOwnMessage(sender) then
        return
    end

    if not IsKeyRequestMessage(message) then
        return
    end

    local reply = BuildKeystoneReply()
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
    if not ownedMapID then
        return
    end

    local receptacleMapID = GetCurrentReceptacleMapID(...)
    if not receptacleMapID then
        return
    end

    if ownedMapID ~= receptacleMapID then
        return
    end

    C_ChallengeMode.SlotKeystone()
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CHAT_MSG_PARTY")
frame:RegisterEvent("CHAT_MSG_PARTY_LEADER")
frame:RegisterEvent("CHAT_MSG_INSTANCE_CHAT")
frame:RegisterEvent("CHAT_MSG_INSTANCE_CHAT_LEADER")
frame:RegisterEvent("CHAT_MSG_RAID")
frame:RegisterEvent("CHAT_MSG_RAID_LEADER")
frame:RegisterEvent("CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN")

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        if not KeylordDB then
            KeylordDB = {}
        end
        return
    end

    if event == "CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN" then
        TryAutoSlotKeystone(...)
        return
    end

    HandleChatMessage(event, ...)
end)
