local ns = _G.KeyMasterNS
if type(ns) ~= "table" then
    ns = {}
    _G.KeyMasterNS = ns
end

local Sync = {}
ns.Sync = Sync

local lastGuildSyncRequestAt = 0

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

local function SendDetailsOpenRaidKeystoneRequest(ctx)
    if not (IsInGuild and IsInGuild() and C_ChatInfo and C_ChatInfo.SendAddonMessage) then
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

    pcall(C_ChatInfo.SendAddonMessage, ctx.DETAILS_OPENRAID_PREFIX, encoded, "GUILD")
    return true
end

function Sync.RequestGuildSnapshots(ctx)
    if not (ctx.IsPlayerInGuildSafe() and C_ChatInfo and C_ChatInfo.SendAddonMessage) then
        return
    end

    pcall(C_ChatInfo.SendAddonMessage, ctx.KSM_ADDON_PREFIX, ctx.KSM_GUILD_SYNC_REQUEST, "GUILD")
end

function Sync.RequestGuildKeysFromAllSources(ctx, force, includeExternal)
    if not ctx.IsPlayerInGuildSafe() then
        return false
    end

    local now = GetTime and GetTime() or 0
    if not force and now > 0 and (now - lastGuildSyncRequestAt) < 8 then
        return false
    end
    lastGuildSyncRequestAt = now

    if C_GuildInfo and C_GuildInfo.GuildRoster then
        pcall(C_GuildInfo.GuildRoster)
    elseif GuildRoster then
        pcall(GuildRoster)
    end

    Sync.RequestGuildSnapshots(ctx)

    if includeExternal and C_ChatInfo and C_ChatInfo.SendAddonMessage then
        pcall(C_ChatInfo.SendAddonMessage, ctx.ASTRAL_KEYS_PREFIX, "request", "GUILD")
        SendDetailsOpenRaidKeystoneRequest(ctx)
    end

    return true
end

local function HandleKeyMasterAddonMessage(ctx, message, sender)
    if type(message) ~= "string" or type(sender) ~= "string" then
        return
    end

    if message == ctx.KSM_GUILD_SYNC_REQUEST then
        local playerName = ctx.GetNormalizedPlayerName(UnitName("player"))
        local senderName = ctx.GetNormalizedPlayerName(sender)
        if senderName and playerName and senderName ~= playerName then
            ctx.BroadcastOwnGuildSnapshot()
        end
        return
    end

    local version, classFile, mapIDText, keyLevelText, ratingText = strsplit("\t", message)
    if version ~= ctx.KSM_GUILD_SYNC_VERSION then
        return
    end

    ctx.SaveGuildMemberData(sender, {
        class = classFile,
        mapID = tonumber(mapIDText) or 0,
        keyLevel = tonumber(keyLevelText) or 0,
        rating = tonumber(ratingText) or 0,
        source = "keymaster",
    })
end

local function HandleAstralKeysAddonMessage(ctx, message)
    if type(message) ~= "string" then
        return
    end

    local payload = message:match("^updateV%d+%s+(.+)$")
    if not payload then
        return
    end

    local unit, classFile, dungeonID, keyLevel, _, _, mplusScore = strsplit(":", payload)
    if not unit or not classFile then
        return
    end

    ctx.SaveGuildMemberData(unit, {
        class = classFile,
        mapID = tonumber(dungeonID) or 0,
        keyLevel = tonumber(keyLevel) or 0,
        rating = tonumber(mplusScore) or 0,
        source = "astralkeys",
    })
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
    if channel ~= "GUILD" or not sender then
        return
    end

    if prefix == ctx.KSM_ADDON_PREFIX then
        HandleKeyMasterAddonMessage(ctx, message, sender)
        ctx.RefreshKSMWindowIfVisible()
        return
    end

    if prefix == ctx.ASTRAL_KEYS_PREFIX then
        HandleAstralKeysAddonMessage(ctx, message)
        ctx.RefreshKSMWindowIfVisible()
        return
    end

    if prefix == ctx.DETAILS_OPENRAID_PREFIX then
        HandleDetailsOpenRaidAddonMessage(ctx, message, sender)
        ctx.RefreshKSMWindowIfVisible()
    end
end
