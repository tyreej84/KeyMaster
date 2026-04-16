local ns = _G.KeyMasterNS
if type(ns) ~= "table" then
    ns = {}
    _G.KeyMasterNS = ns
end

local Sync = {}
ns.Sync = Sync

local lastGuildSyncRequestAt = 0

local function BuildSyncChannels(ctx)
    local channels = {}
    local seen = {}

    local function AddChannel(channel)
        if seen[channel] then
            return
        end

        seen[channel] = true
        table.insert(channels, channel)
    end

    if ctx.IsPlayerInGuildSafe and ctx.IsPlayerInGuildSafe() then
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

local function ClampNumber(value, minValue, maxValue, defaultValue)
    local numberValue = tonumber(value)
    if type(numberValue) ~= "number" then
        return defaultValue
    end

    numberValue = math.floor(numberValue + 0.5)
    if numberValue < minValue or numberValue > maxValue then
        return defaultValue
    end

    return numberValue
end

local function NormalizeClassFile(ctx, classFile)
    if type(classFile) ~= "string" then
        return nil
    end

    local normalized = strupper(classFile)
    if normalized:match("^[A-Z]+$") ~= normalized then
        return nil
    end

    if RAID_CLASS_COLORS and RAID_CLASS_COLORS[normalized] then
        return normalized
    end

    for _, knownClassFile in pairs(ctx.CLASS_ID_TO_FILE or {}) do
        if knownClassFile == normalized then
            return normalized
        end
    end

    return nil
end

local function ParseGuildSyncPayload(ctx, message)
    if type(message) ~= "string" or message == "" then
        return nil
    end

    local version, classFile, mapIDText, keyLevelText, ratingText = strsplit("\t", message)
    if version == ctx.KSM_GUILD_SYNC_VERSION then
        return {
            class = NormalizeClassFile(ctx, classFile),
            mapID = ClampNumber(mapIDText, 0, 20000, 0),
            keyLevel = ClampNumber(keyLevelText, 0, 50, 0),
            rating = ClampNumber(ratingText, 0, 20000, 0),
            source = "keystonemastery",
        }
    end

    -- Compatibility parser for Name:MapID:Level payloads.
    local _, mapIDColon, keyLevelColon = strsplit(":", message)
    local parsedMapID = ClampNumber(mapIDColon, 0, 20000, nil)
    local parsedKeyLevel = ClampNumber(keyLevelColon, 0, 50, nil)
    if parsedMapID and parsedKeyLevel then
        return {
            mapID = parsedMapID,
            keyLevel = parsedKeyLevel,
            source = "keystonemastery",
        }
    end

    local genericMapID, genericKeyLevel = message:match(":(%d+):(%d+):")
    genericMapID = ClampNumber(genericMapID, 0, 20000, nil)
    genericKeyLevel = ClampNumber(genericKeyLevel, 0, 50, nil)
    if genericMapID and genericKeyLevel then
        return {
            mapID = genericMapID,
            keyLevel = genericKeyLevel,
            source = "keystonemastery",
        }
    end

    local trailingMapID, trailingKeyLevel = message:match(":(%d+):(%d+)$")
    trailingMapID = ClampNumber(trailingMapID, 0, 20000, nil)
    trailingKeyLevel = ClampNumber(trailingKeyLevel, 0, 50, nil)
    if trailingMapID and trailingKeyLevel then
        return {
            mapID = trailingMapID,
            keyLevel = trailingKeyLevel,
            source = "keystonemastery",
        }
    end

    return nil
end

local function GetLibDeflateInstance(ctx)
    if not LibStub then
        return nil
    end

    local ok, libDeflate = pcall(LibStub.GetLibrary, LibStub, "LibDeflate", true)
    if ok and libDeflate then
        return libDeflate
    end

    return nil
end

local function SendDetailsOpenRaidKeystoneRequest(ctx, channel)
    if type(channel) ~= "string" or channel == "" then
        return false
    end

    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then
        return false
    end

    local libDeflate = GetLibDeflateInstance(ctx)
    if not libDeflate then
        return false
    end

    local compressed = libDeflate:CompressDeflate(ctx.DETAILS_OPENRAID_KEYSTONE_REQUEST_PREFIX, { level = 9 })
    if type(compressed) ~= "string" then
        return false
    end

    local encoded = libDeflate:EncodeForWoWAddonChannel(compressed)
    if type(encoded) ~= "string" or encoded == "" then
        return false
    end

    pcall(C_ChatInfo.SendAddonMessage, ctx.DETAILS_OPENRAID_PREFIX, encoded, channel)
    return true
end

function Sync.RequestGuildSnapshots(ctx)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then
        return
    end

    for _, channel in ipairs(BuildSyncChannels(ctx)) do
        pcall(C_ChatInfo.SendAddonMessage, ctx.KSM_ADDON_PREFIX, ctx.KSM_GUILD_SYNC_REQUEST, channel)
    end
end

function Sync.RequestGuildKeysFromAllSources(ctx, force, includeExternal)
    local now = GetTime and GetTime() or 0
    if not force and now > 0 and (now - lastGuildSyncRequestAt) < 8 then
        return false
    end

    local channels = BuildSyncChannels(ctx)
    if #channels == 0 then
        return false
    end

    lastGuildSyncRequestAt = now

    if ctx.IsPlayerInGuildSafe and ctx.IsPlayerInGuildSafe() and C_GuildInfo and C_GuildInfo.GuildRoster then
        pcall(C_GuildInfo.GuildRoster)
    elseif ctx.IsPlayerInGuildSafe and ctx.IsPlayerInGuildSafe() and GuildRoster then
        pcall(GuildRoster)
    end

    for _, channel in ipairs(channels) do
        pcall(C_ChatInfo.SendAddonMessage, ctx.KSM_ADDON_PREFIX, ctx.KSM_GUILD_SYNC_REQUEST, channel)
    end

    if includeExternal and C_ChatInfo and C_ChatInfo.SendAddonMessage then
        for _, channel in ipairs(channels) do
            pcall(C_ChatInfo.SendAddonMessage, ctx.ASTRAL_KEYS_PREFIX, "request", channel)
            SendDetailsOpenRaidKeystoneRequest(ctx, channel)
        end
    end

    return true
end

local function HandleKeyMasterAddonMessage(ctx, message, sender)
    if type(message) ~= "string" or type(sender) ~= "string" then
        return
    end

    if message == ctx.KSM_GUILD_SYNC_REQUEST or message == "REQUEST_KEYS" or message == "req" then
        local playerName = ctx.GetNormalizedPlayerName(UnitName("player"))
        local senderName = ctx.GetNormalizedPlayerName(sender)
        if senderName and playerName and senderName ~= playerName then
            ctx.BroadcastOwnGuildSnapshot()
        end
        return
    end

    local payload = ParseGuildSyncPayload(ctx, message)
    if not payload then
        return
    end

    ctx.SaveGuildMemberData(sender, payload)
end

local function HandleAstralKeysAddonMessage(ctx, message)
    if type(message) ~= "string" then
        return
    end

    local function SaveAstralRecord(unit, classFile, dungeonID, keyLevel, mplusScore)
        if type(unit) ~= "string" or unit == "" then
            return
        end

        ctx.SaveGuildMemberData(unit, {
            class = NormalizeClassFile(ctx, classFile),
            mapID = ClampNumber(dungeonID, 0, 20000, 0),
            keyLevel = ClampNumber(keyLevel, 0, 50, 0),
            rating = ClampNumber(mplusScore, 0, 20000, 0),
            source = "astralkeys",
        })
    end

    local updatePayload = message:match("^updateV%d+%s+(.+)$")
    if updatePayload then
        local unit, classFile, dungeonID, keyLevel, _, _, mplusScore = strsplit(":", updatePayload)
        SaveAstralRecord(unit, classFile, dungeonID, keyLevel, mplusScore)
        return
    end

    local syncPayload = message:match("^sync%d+%s+(.+)$")
    if not syncPayload then
        return
    end

    if syncPayload:sub(-1) ~= "_" then
        syncPayload = syncPayload .. "_"
    end

    for entry in syncPayload:gmatch("([^_]+)_") do
        local unit, classFile, dungeonID, keyLevel, _, _, _, mplusScore = strsplit(":", entry)
        SaveAstralRecord(unit, classFile, dungeonID, keyLevel, mplusScore)
    end
end

local function HandleDetailsOpenRaidAddonMessage(ctx, message, sender)
    if type(message) ~= "string" or message == "" or type(sender) ~= "string" then
        return
    end

    local libDeflate = GetLibDeflateInstance(ctx)
    if not libDeflate then
        return
    end

    local decoded = libDeflate:DecodeForWoWAddonChannel(message)
    if type(decoded) ~= "string" then
        return
    end

    local inflated = libDeflate:DecompressDeflate(decoded)
    if type(inflated) ~= "string" or inflated == "" then
        return
    end

    local dataType, levelText, mapIDText, challengeMapIDText, classIDText, ratingText, mythicPlusMapIDText = strsplit(",", inflated)
    if dataType ~= ctx.DETAILS_OPENRAID_KEYSTONE_DATA_PREFIX then
        return
    end

    local level = tonumber(levelText) or 0
    local mapID = tonumber(challengeMapIDText) or tonumber(mythicPlusMapIDText) or tonumber(mapIDText) or 0
    local classID = tonumber(classIDText) or 0
    local classFile = ctx.CLASS_ID_TO_FILE[classID]
    local rating = tonumber(ratingText) or 0

    ctx.SaveGuildMemberData(sender, {
        class = classFile,
        mapID = mapID,
        keyLevel = level,
        rating = rating,
        source = "details-openraid",
    })
end

function Sync.HandleAddonMessage(ctx, prefix, message, channel, sender)
    if type(channel) ~= "string" or not sender then
        return
    end

    local isGuildChannel = channel == "GUILD"
    local isGroupChannel = channel == "PARTY" or channel == "RAID" or channel == "INSTANCE_CHAT"

    if prefix == ctx.KSM_ADDON_PREFIX and (isGuildChannel or isGroupChannel) then
        HandleKeyMasterAddonMessage(ctx, message, sender)
        ctx.RefreshKSMWindowIfVisible()
        return
    end

    if prefix == ctx.ASTRAL_KEYS_PREFIX and (isGuildChannel or isGroupChannel) then
        HandleAstralKeysAddonMessage(ctx, message)
        ctx.RefreshKSMWindowIfVisible()
        return
    end

    if prefix == ctx.DETAILS_OPENRAID_PREFIX and (isGuildChannel or isGroupChannel) then
        HandleDetailsOpenRaidAddonMessage(ctx, message, sender)
        ctx.RefreshKSMWindowIfVisible()
    end
end
