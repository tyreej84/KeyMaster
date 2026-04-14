local ns = _G.KeyMasterNS
if type(ns) ~= "table" then
    ns = {}
    _G.KeyMasterNS = ns
end

local KSM = {}
ns.KSM = KSM

function KSM.SetActiveTab(ctx, tabName)
    local ui = ctx.ui
    if not ui or not ui.ksmFrame then
        return
    end

    ui.ksmActiveTab = tabName or "main"

    local showMain = ui.ksmActiveTab == "main"
    local showParty = ui.ksmActiveTab == "party"
    local showGuild = ui.ksmActiveTab == "guild"

    if ui.ksmMainContent then if showMain then ui.ksmMainContent:Show() else ui.ksmMainContent:Hide() end end
    if ui.ksmPartyContent then if showParty then ui.ksmPartyContent:Show() else ui.ksmPartyContent:Hide() end end
    if ui.ksmGuildContent then if showGuild then ui.ksmGuildContent:Show() else ui.ksmGuildContent:Hide() end end

    if ui.ksmMainTab then
        ui.ksmMainTab.isSelected = showMain
        if ui.ksmMainTab.bg then
            ui.ksmMainTab.bg:SetColorTexture(showMain and 0.09 or 0.04, showMain and 0.09 or 0.04, showMain and 0.11 or 0.05, showMain and 0.96 or 0.85)
        end
        if ui.ksmMainTab.activeAccent then
            ui.ksmMainTab.activeAccent:SetColorTexture(0.24, 0.64, 1, showMain and 0.95 or 0)
        end
        local mainLabel = ui.ksmMainTab.label or (ui.ksmMainTab.GetFontString and ui.ksmMainTab:GetFontString())
        if mainLabel then
            mainLabel:SetTextColor(showMain and 1 or 0.8, showMain and 0.9 or 0.83, showMain and 0.68 or 0.86, 1)
        end
    end
    if ui.ksmPartyTab then
        ui.ksmPartyTab.isSelected = showParty
        if ui.ksmPartyTab.bg then
            ui.ksmPartyTab.bg:SetColorTexture(showParty and 0.09 or 0.04, showParty and 0.09 or 0.04, showParty and 0.11 or 0.05, showParty and 0.96 or 0.85)
        end
        if ui.ksmPartyTab.activeAccent then
            ui.ksmPartyTab.activeAccent:SetColorTexture(0.24, 0.64, 1, showParty and 0.95 or 0)
        end
        local partyLabel = ui.ksmPartyTab.label or (ui.ksmPartyTab.GetFontString and ui.ksmPartyTab:GetFontString())
        if partyLabel then
            partyLabel:SetTextColor(showParty and 1 or 0.8, showParty and 0.9 or 0.83, showParty and 0.68 or 0.86, 1)
        end
    end
    if ui.ksmGuildTab then
        ui.ksmGuildTab.isSelected = showGuild
        if ui.ksmGuildTab.bg then
            ui.ksmGuildTab.bg:SetColorTexture(showGuild and 0.09 or 0.04, showGuild and 0.09 or 0.04, showGuild and 0.11 or 0.05, showGuild and 0.96 or 0.85)
        end
        if ui.ksmGuildTab.activeAccent then
            ui.ksmGuildTab.activeAccent:SetColorTexture(0.24, 0.64, 1, showGuild and 0.95 or 0)
        end
        local guildLabel = ui.ksmGuildTab.label or (ui.ksmGuildTab.GetFontString and ui.ksmGuildTab:GetFontString())
        if guildLabel then
            guildLabel:SetTextColor(showGuild and 1 or 0.8, showGuild and 0.9 or 0.83, showGuild and 0.68 or 0.86, 1)
        end
    end
end

function KSM.RefreshMainTab(ctx)
    local ui = ctx.ui
    if not ui or not ui.ksmMainContent then
        return
    end

    local floor = ctx.floor
    local max = ctx.max
    local min = ctx.min
    local GetMythicPlusScore = ctx.GetMythicPlusScore
    local GetBestRunsFromHistory = ctx.GetBestRunsFromHistory
    local GetBestRunFromMapLookup = ctx.GetBestRunFromMapLookup
    local GetBestSeasonRunFromKnownMaps = ctx.GetBestSeasonRunFromKnownMaps
    local GetActiveKeystoneDetails = ctx.GetActiveKeystoneDetails
    local GetOwnedKeystoneSnapshot = ctx.GetOwnedKeystoneSnapshot
    local GetCurrentSeasonPortalEntries = ctx.GetCurrentSeasonPortalEntries
    local GetBestPortalRunForMap = ctx.GetBestPortalRunForMap
    local TrySetGreatVaultTexture = ctx.TrySetGreatVaultTexture
    local GetAffixDisplayInfo = ctx.GetAffixDisplayInfo
    local GetVaultProgressSummary = ctx.GetVaultProgressSummary
    local FormatBestRun = ctx.FormatBestRun
    local FormatBestRunNoScore = ctx.FormatBestRunNoScore
    local FormatDungeonLabel = ctx.FormatDungeonLabel
    local GetDungeonTileTexture = ctx.GetDungeonTileTexture
    local PrintLocal = ctx.PrintLocal

    local weeklyPanel = ui.ksmWeeklyPanel or ui.ksmMainContent
    local seasonPanel = ui.ksmSeasonPanel or ui.ksmMainContent

    local score = GetMythicPlusScore()
    local weekBest, seasonBest = GetBestRunsFromHistory()
    if not weekBest or not seasonBest then
        weekBest = weekBest or GetBestRunFromMapLookup("GetWeeklyBestForMap")
        seasonBest = seasonBest or GetBestRunFromMapLookup("GetSeasonBestForMap")
    end

    local mapSeasonBest = GetBestSeasonRunFromKnownMaps()
    if mapSeasonBest then
        local mapScore = tonumber(mapSeasonBest.score)
        local currentScore = seasonBest and tonumber(seasonBest.score)
        if not seasonBest
            or (mapScore and currentScore and mapScore > currentScore)
            or (mapScore and not currentScore)
            or ((not mapScore or not currentScore) and (mapSeasonBest.level or 0) > (seasonBest.level or 0))
        then
            seasonBest = mapSeasonBest
        end
    end

    local _, affixIDs = GetActiveKeystoneDetails()
    local keyMapID, keyLevel = GetOwnedKeystoneSnapshot()
    local portalEntries = GetCurrentSeasonPortalEntries()

    local function IsBetterSeasonCandidate(candidate, current)
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

    local portalSeasonBest
    for _, entry in ipairs(portalEntries) do
        local bestForMap = GetBestPortalRunForMap(entry.mapID)
        if bestForMap and IsBetterSeasonCandidate(bestForMap, portalSeasonBest) then
            portalSeasonBest = bestForMap
        end
    end

    if IsBetterSeasonCandidate(portalSeasonBest, seasonBest) then
        seasonBest = portalSeasonBest
    end

    if ui.ksmRatingLine then ui.ksmRatingLine:Hide() end
    if ui.ksmBestLine then ui.ksmBestLine:Hide() end
    if ui.ksmAffixLine then ui.ksmAffixLine:Hide() end
    if ui.ksmKeyLine then ui.ksmKeyLine:Hide() end
    if ui.ksmVaultLine then ui.ksmVaultLine:Hide() end
    if ui.ksmPortalsLabel then ui.ksmPortalsLabel:Hide() end

    if not ui.ksmSeasonHeader then
        ui.ksmSeasonHeader = weeklyPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ui.ksmSeasonHeader:SetPoint("TOP", weeklyPanel, "TOP", 0, -10)
        ui.ksmSeasonHeader:SetTextColor(1.0, 0.84, 0.15, 1)
        ui.ksmSeasonHeader:SetText("Mythic+ Dungeons")
        ui.ksmSeasonHeader:SetFontObject("GameFontHighlight")
    end

    if not ui.ksmWeekHeader then
        ui.ksmWeekHeader = weeklyPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        ui.ksmWeekHeader:SetPoint("TOP", weeklyPanel, "TOP", 0, -26)
        ui.ksmWeekHeader:SetTextColor(1, 1, 1, 1)
        ui.ksmWeekHeader:SetText("This Week")
        ui.ksmWeekHeader:SetFontObject("GameFontHighlightLarge")
    end

    if not ui.ksmVaultPrompt then
        ui.ksmVaultPrompt = weeklyPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        ui.ksmVaultPrompt:SetTextColor(1.0, 0.8, 0.1, 1)
        ui.ksmVaultPrompt:SetText("Complete Mythic+ dungeons to earn:")
    end
    ui.ksmVaultPrompt:ClearAllPoints()
    ui.ksmVaultPrompt:SetPoint("TOP", weeklyPanel, "TOP", 0, -92)

    if not ui.ksmAffixButtons then
        ui.ksmAffixButtons = {}
    end

    local affixCount = type(affixIDs) == "table" and #affixIDs or 0
    local affixSize = 42
    local affixGap = 12
    local affixStartX = -(((affixCount * affixSize) + ((max(affixCount - 1, 0)) * affixGap)) / 2)

    for index = 1, affixCount do
        local affixID = affixIDs[index]
        local button = ui.ksmAffixButtons[index]
        if not button then
            button = CreateFrame("Button", nil, weeklyPanel)
            button:SetSize(affixSize, affixSize)

            local bg = button:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(button)
            bg:SetColorTexture(0.02, 0.02, 0.02, 0.9)

            local icon = button:CreateTexture(nil, "ARTWORK")
            icon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
            icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
            button.icon = icon

            local border = button:CreateTexture(nil, "OVERLAY")
            border:SetAllPoints(button)
            border:SetColorTexture(1, 1, 1, 0.2)

            button:SetScript("OnEnter", function(self)
                if not self.affixID then
                    return
                end

                local name, description = GetAffixDisplayInfo(self.affixID)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:ClearLines()
                GameTooltip:AddLine(name or string.format("Affix %d", self.affixID), 1, 1, 1)
                if type(description) == "string" and description ~= "" then
                    GameTooltip:AddLine(description, 0.85, 0.85, 0.85, true)
                end
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave", GameTooltip_Hide)

            ui.ksmAffixButtons[index] = button
        end

        local _, _, affixTexture = GetAffixDisplayInfo(affixID)
        button.icon:SetTexture(affixTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
        button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button.affixID = affixID
        button:ClearAllPoints()
        button:SetPoint("TOP", weeklyPanel, "TOP", affixStartX + ((index - 1) * (affixSize + affixGap)) + (affixSize / 2), -46)
        button:Show()
    end

    for index = affixCount + 1, #ui.ksmAffixButtons do
        ui.ksmAffixButtons[index]:Hide()
    end

    if ui.ksmVaultButton then
        if ui.ksmVaultButton.plate then
            local usingCustomVaultArt = TrySetGreatVaultTexture(ui.ksmVaultButton.plate)
            if ui.ksmVaultButton.lock then
                local _ = usingCustomVaultArt
                ui.ksmVaultButton.lock:Hide()
            end
        end
    end

    if not ui.ksmRatingText then
        ui.ksmRatingText = weeklyPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        ui.ksmRatingText:SetTextColor(1.0, 0.72, 0.2, 1)
    end
    ui.ksmRatingText:ClearAllPoints()
    ui.ksmRatingText:SetPoint("TOP", ui.ksmVaultButton or weeklyPanel, "BOTTOM", 0, -24)
    ui.ksmRatingText:SetJustifyH("CENTER")
    ui.ksmRatingText:SetText(score and tostring(floor(score + 0.5)) or "—")

    if not ui.ksmRatingLabel then
        ui.ksmRatingLabel = weeklyPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        ui.ksmRatingLabel:SetTextColor(1, 1, 1, 0.95)
        ui.ksmRatingLabel:SetText("Mythic+ Rating")
        ui.ksmRatingLabel:SetFontObject("GameFontHighlight")
    end
    ui.ksmRatingLabel:ClearAllPoints()
    ui.ksmRatingLabel:SetPoint("BOTTOM", ui.ksmRatingText, "TOP", 0, 6)
    ui.ksmRatingLabel:SetJustifyH("CENTER")

    if not ui.ksmRecordsBox then
        local recordsBox = CreateFrame("Frame", nil, weeklyPanel, BackdropTemplateMixin and "BackdropTemplate")
        recordsBox:SetSize(236, 106)
        recordsBox:SetPoint("BOTTOMLEFT", weeklyPanel, "BOTTOMLEFT", 12, 12)

        local recordsTitle = recordsBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        recordsTitle:SetPoint("TOPLEFT", recordsBox, "TOPLEFT", 8, -8)
        recordsTitle:SetTextColor(1.0, 0.82, 0.22, 1)
        recordsTitle:SetText("Records")

        local keyLine = recordsBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        keyLine:SetPoint("TOPLEFT", recordsTitle, "BOTTOMLEFT", 0, -6)
        keyLine:SetJustifyH("LEFT")
        keyLine:SetTextColor(0.86, 0.9, 0.95, 1)

        local vaultLine = recordsBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        vaultLine:SetPoint("TOPLEFT", keyLine, "BOTTOMLEFT", 0, -4)
        vaultLine:SetJustifyH("LEFT")
        vaultLine:SetTextColor(0.86, 0.9, 0.95, 1)

        local weekLine = recordsBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        weekLine:SetPoint("TOPLEFT", vaultLine, "BOTTOMLEFT", 0, -4)
        weekLine:SetJustifyH("LEFT")
        weekLine:SetTextColor(0.86, 0.9, 0.95, 1)

        local seasonLine = recordsBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        seasonLine:SetPoint("TOPLEFT", weekLine, "BOTTOMLEFT", 0, -4)
        seasonLine:SetJustifyH("LEFT")
        seasonLine:SetTextColor(0.86, 0.9, 0.95, 1)

        ui.ksmRecordsBox = recordsBox
        ui.ksmRecordsKeyLine = keyLine
        ui.ksmRecordsVaultLine = vaultLine
        ui.ksmRecordsWeekLine = weekLine
        ui.ksmRecordsSeasonLine = seasonLine
    end

    if ui.ksmRecordsKeyLine then
        ui.ksmRecordsKeyLine:SetText(keyLevel and string.format("Keystone: +%d %s", keyLevel, FormatDungeonLabel(keyMapID)) or "Keystone: Unavailable")
    end
    if ui.ksmRecordsVaultLine then
        ui.ksmRecordsVaultLine:SetText(GetVaultProgressSummary())
    end
    if ui.ksmRecordsWeekLine then
        ui.ksmRecordsWeekLine:SetText(string.format("Weekly Best: %s", FormatBestRun(weekBest)))
    end
    if ui.ksmRecordsSeasonLine then
        ui.ksmRecordsSeasonLine:SetText(string.format("Season Best: %s", FormatBestRunNoScore(seasonBest)))
    end

    if not ui.ksmPortalLabel then
        ui.ksmPortalLabel = seasonPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        ui.ksmPortalLabel:SetPoint("TOP", seasonPanel, "TOP", 0, -10)
        ui.ksmPortalLabel:SetTextColor(1, 1, 1, 1)
        ui.ksmPortalLabel:SetText("Season Portals")
        ui.ksmPortalLabel:SetFontObject("GameFontHighlight")
    end

    local entries = portalEntries
    local bestForMapCache = {}
    local function GetBestForMapCached(mapID)
        if bestForMapCache[mapID] == nil then
            bestForMapCache[mapID] = GetBestPortalRunForMap(mapID) or false
        end
        return bestForMapCache[mapID] ~= false and bestForMapCache[mapID] or nil
    end

    table.sort(entries, function(left, right)
        local leftBest = GetBestForMapCached(left.mapID)
        local rightBest = GetBestForMapCached(right.mapID)
        local leftScore = leftBest and tonumber(leftBest.score) or nil
        local rightScore = rightBest and tonumber(rightBest.score) or nil

        if leftScore and rightScore and leftScore ~= rightScore then
            return leftScore > rightScore
        end
        if leftScore and not rightScore then
            return true
        end
        if rightScore and not leftScore then
            return false
        end

        local leftLevel = leftBest and tonumber(leftBest.level) or 0
        local rightLevel = rightBest and tonumber(rightBest.level) or 0
        if leftLevel ~= rightLevel then
            return leftLevel > rightLevel
        end

        return (left.mapName or "") < (right.mapName or "")
    end)

    local maxTiles = min(#entries, 8)
    local tileWidth = 60
    local tileHeight = 52
    local tileGap = 4

    if ui.ksmPortalLabel then
        ui.ksmPortalLabel:SetText(maxTiles > 0 and "Season Portals" or "Season Portals (No Data)")
    end

    for index = 1, maxTiles do
        local entry = entries[index]
        local button = ui.ksmPortalButtons[index]
        if not button then
            button = CreateFrame("Button", nil, seasonPanel)
            button:SetSize(tileWidth, tileHeight)

            local icon = button:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints(button)
            button.icon = icon

            local dim = button:CreateTexture(nil, "OVERLAY")
            dim:SetAllPoints(button)
            dim:SetColorTexture(0, 0, 0, 0.12)
            button.dim = dim

            local levelText = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            levelText:SetPoint("TOPLEFT", button, "TOPLEFT", 4, -3)
            levelText:SetTextColor(1.0, 0.72, 0.2, 1)
            button.levelText = levelText

            button:SetScript("OnClick", function(self)
                if not self.spellID then
                    PrintLocal("Portal spell is not configured for this dungeon")
                    return
                end

                if not (IsSpellKnown and IsSpellKnown(self.spellID)) then
                    PrintLocal("Portal is locked for this dungeon")
                    return
                end

                if CastSpellByID then
                    pcall(CastSpellByID, self.spellID)
                end
            end)

            button:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:ClearLines()
                GameTooltip:AddLine(self.mapName or "Dungeon", 1, 1, 1)
                if self.bestLevel then
                    GameTooltip:AddLine(string.format("Season Best: +%d", self.bestLevel), 1, 0.82, 0.2)
                else
                    GameTooltip:AddLine("Season Best: None", 0.8, 0.8, 0.8)
                end
                if self.bestScore then
                    GameTooltip:AddLine(string.format("Dungeon Score: %d", floor(self.bestScore + 0.5)), 0.8, 0.95, 1)
                end
                if not self.spellID then
                    GameTooltip:AddLine("Portal spell not configured", 0.85, 0.3, 0.3)
                else
                    GameTooltip:AddLine(self.known and "Click to cast portal" or "Portal locked", self.known and 0.5 or 0.8, self.known and 1 or 0.2, self.known and 0.5 or 0.2)
                end
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave", GameTooltip_Hide)

            ui.ksmPortalButtons[index] = button
        end

        local bestForMap = GetBestForMapCached(entry.mapID)
        button.bestLevel = bestForMap and bestForMap.level or nil
        button.bestScore = bestForMap and bestForMap.score or nil
        button.overallScore = score
        button.spellID = entry.spellID
        button.mapName = entry.mapName
        button.known = entry.known

        local iconTexture, isSpellIcon = GetDungeonTileTexture(entry.mapID, entry.spellID)
        button.icon:SetTexture(iconTexture)
        if isSpellIcon then
            button.icon:SetTexCoord(0, 1, 0, 1)
        else
            button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        button.levelText:SetText(bestForMap and tostring(bestForMap.level) or "-")
        if entry.known then button.dim:Hide() else button.dim:Show() end

        local totalWidth = (maxTiles * tileWidth) + (max(0, maxTiles - 1) * tileGap)
        local rowStartX = -(totalWidth / 2)
        local rowY = -48

        button:ClearAllPoints()
        button:SetPoint("TOP", seasonPanel, "TOP", rowStartX + ((index - 1) * (tileWidth + tileGap)) + (tileWidth / 2), rowY)
        button:Show()
    end

    for index = maxTiles + 1, #ui.ksmPortalButtons do
        ui.ksmPortalButtons[index]:Hide()
    end
end

function KSM.RefreshPartyTab(ctx)
    local ui = ctx.ui
    if not ui or not ui.ksmPartyContent then
        return
    end

    local floor = ctx.floor
    local GetOwnedKeystoneSnapshot = ctx.GetOwnedKeystoneSnapshot
    local GetPlayerClassFile = ctx.GetPlayerClassFile
    local GetGuildMemberData = ctx.GetGuildMemberData
    local TryGetUnitMythicScore = ctx.TryGetUnitMythicScore
    local GetPortalSpellIDForMap = ctx.GetPortalSpellIDForMap
    local EnsureKSMDataLine = ctx.EnsureKSMDataLine
    local EnsureKSMPartyRow = ctx.EnsureKSMPartyRow
    local GetClassColorInfo = ctx.GetClassColorInfo
    local ApplyClassIcon = ctx.ApplyClassIcon
    local GetDungeonTileTexture = ctx.GetDungeonTileTexture
    local FormatDungeonLabel = ctx.FormatDungeonLabel

    local entries = {}
    local units = { "player", "party1", "party2", "party3", "party4" }
    for _, unitToken in ipairs(units) do
        if UnitExists(unitToken) then
            local name = UnitName(unitToken) or "Unknown"
            local mapID, keyLevel
            local classFile = GetPlayerClassFile(unitToken)

            if unitToken == "player" then
                mapID, keyLevel = GetOwnedKeystoneSnapshot()
            else
                local cache = GetGuildMemberData(name)
                mapID = cache and tonumber(cache.mapID) or 0
                keyLevel = cache and tonumber(cache.keyLevel) or 0
                if cache and cache.class then
                    classFile = cache.class
                end
            end

            local score = TryGetUnitMythicScore(unitToken)
            if (not score or score <= 0) and unitToken ~= "player" then
                local cache = GetGuildMemberData(name)
                score = cache and tonumber(cache.rating) or nil
            end

            mapID = tonumber(mapID) or 0
            keyLevel = tonumber(keyLevel) or 0

            table.insert(entries, {
                unitToken = unitToken,
                name = name,
                classFile = classFile,
                mapID = mapID,
                keyLevel = keyLevel,
                score = score and floor(score + 0.5) or 0,
                spellID = GetPortalSpellIDForMap(mapID),
            })
        end
    end

    if #entries == 0 then
        local line = EnsureKSMDataLine(ui.ksmPartyLines, ui.ksmPartyContent, 1)
        line:SetWidth(570)
        line:SetPoint("TOPLEFT", ui.ksmPartyContent, "TOPLEFT", 10, -48)
        line:SetText("No party members found")
        line:Show()
        for index = 1, #ui.ksmPartyRows do
            ui.ksmPartyRows[index]:Hide()
        end
        return
    end

    for index = 1, #ui.ksmPartyLines do
        ui.ksmPartyLines[index]:Hide()
    end

    local y = -42
    for index, entry in ipairs(entries) do
        local row = EnsureKSMPartyRow(index)
        local r, g, b = GetClassColorInfo(entry.classFile)

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", ui.ksmPartyContent, "TOPLEFT", 10, y)
        row.nameText:SetText(entry.name)
        row.nameText:SetTextColor(r, g, b, 1)

        if SetPortraitTexture and UnitExists(entry.unitToken) then
            SetPortraitTexture(row.portrait, entry.unitToken)
            row.portrait:SetTexCoord(0, 1, 0, 1)
        else
            ApplyClassIcon(row.portrait, entry.classFile)
        end

        local iconTexture = "Interface\\Icons\\INV_Misc_QuestionMark"
        local useSpellCoords = false
        if entry.mapID > 0 then
            local tileTexture, fromSpellIcon = GetDungeonTileTexture(entry.mapID, entry.spellID)
            if tileTexture then
                iconTexture = tileTexture
                useSpellCoords = fromSpellIcon and true or false
            end
        end

        row.keyTile.icon:SetTexture(iconTexture)
        row.keyTile.icon:SetTexCoord(useSpellCoords and 0.08 or 0.06, useSpellCoords and 0.92 or 0.94, useSpellCoords and 0.08 or 0.06, useSpellCoords and 0.92 or 0.94)
        row.keyTile.levelText:SetText(entry.keyLevel > 0 and string.format("+%d", entry.keyLevel) or "")
        row.scoreText:SetText(entry.score > 0 and string.format("M+ %d", entry.score) or "M+ -")
        row.dungeonText:SetText(entry.mapID > 0 and FormatDungeonLabel(entry.mapID) or "No key data")

        row.keyTile.mapID = entry.mapID
        row.keyTile.keyLevel = entry.keyLevel
        row.keyTile.spellID = entry.spellID
        row.keyTile.dungeonLabel = entry.mapID > 0 and FormatDungeonLabel(entry.mapID) or "No key"
        row.keyTile:SetAlpha(entry.keyLevel > 0 and 1 or 0.55)
        if row.cardBG then
            row.cardBG:SetColorTexture(0.02, 0.03, 0.04, entry.keyLevel > 0 and 0.44 or 0.3)
        end

        row:Show()
        y = y - 68
    end

    for index = #entries + 1, #ui.ksmPartyRows do
        ui.ksmPartyRows[index]:Hide()
    end
end

function KSM.RefreshGuildTab(ctx)
    local ui = ctx.ui
    if not ui or not ui.ksmGuildContent then
        return
    end

    local floor = ctx.floor
    local max = ctx.max
    local min = ctx.min
    local IsPlayerInGuildSafe = ctx.IsPlayerInGuildSafe
    local EnsureKSMGuildRow = ctx.EnsureKSMGuildRow
    local RequestGuildRosterSafe = ctx.RequestGuildRosterSafe
    local RequestGuildKeysFromAllSources = ctx.RequestGuildKeysFromAllSources
    local GetNormalizedPlayerName = ctx.GetNormalizedPlayerName
    local GetMythicPlusScore = ctx.GetMythicPlusScore
    local GetOwnedKeystoneSnapshot = ctx.GetOwnedKeystoneSnapshot
    local GetPlayerClassFile = ctx.GetPlayerClassFile
    local GetNumGuildMembersSafe = ctx.GetNumGuildMembersSafe
    local GetGuildMemberData = ctx.GetGuildMemberData
    local TryGetMythicScoreForIdentifier = ctx.TryGetMythicScoreForIdentifier
    local IsGuildMemberRecent = ctx.IsGuildMemberRecent
    local GetPortalSpellIDForMap = ctx.GetPortalSpellIDForMap
    local GetGuildMemberStore = ctx.GetGuildMemberStore
    local KSM_GUILD_RECENT_DAYS = ctx.KSM_GUILD_RECENT_DAYS
    local GetClassColorInfo = ctx.GetClassColorInfo
    local ApplyClassIcon = ctx.ApplyClassIcon
    local FormatDungeonLabel = ctx.FormatDungeonLabel

    if ui.ksmGuildHideOfflineCheck then
        ui.ksmGuildHideOfflineCheck:SetChecked(ui.ksmHideOffline == true)
    end

    local inGuild = IsPlayerInGuildSafe()
    if not inGuild then
        local row = EnsureKSMGuildRow(1)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", ui.ksmGuildContent, "TOPLEFT", 10, -52)
        row.classIcon:Hide()
        row.nameText:SetText("You are not in a guild")
        row.nameText:SetTextColor(1, 1, 1, 1)
        row.keyText:SetText("")
        row.dungeonText:SetText("")
        row.ratingText:SetText("")
        row.teleportButton:Hide()
        row:Show()

        for index = 2, #ui.ksmGuildRows do
            ui.ksmGuildRows[index]:Hide()
        end
        for index = 1, #ui.ksmGuildLines do
            ui.ksmGuildLines[index]:Hide()
        end
        return
    end

    RequestGuildRosterSafe()
    RequestGuildKeysFromAllSources(false)

    local entries = {}
    local entryByName = {}
    local rosterByName = {}
    local playerName = GetNormalizedPlayerName(UnitName("player"))
    local playerScore = floor((GetMythicPlusScore() or 0) + 0.5)
    local playerMapID, playerKeyLevel = GetOwnedKeystoneSnapshot()
    local playerClass = GetPlayerClassFile("player")

    local total = GetNumGuildMembersSafe()
    for index = 1, total do
        local fullName, _, _, _, _, _, _, _, _, online, _, classFile = GetGuildRosterInfo(index)
        if fullName then
            local name = GetNormalizedPlayerName(fullName)
            local cache = GetGuildMemberData(name) or {}
            local isPlayer = name == playerName
            local guid = select(17, GetGuildRosterInfo(index))
            rosterByName[name] = {
                online = online and true or false,
                classFile = classFile,
                guid = guid,
            }

            local mapID = isPlayer and playerMapID or cache.mapID
            local keyLevel = isPlayer and playerKeyLevel or cache.keyLevel
            local rating = isPlayer and playerScore or cache.rating

            if (not rating or rating <= 0) and guid then
                local apiScore = TryGetMythicScoreForIdentifier(guid)
                if apiScore then
                    rating = floor(apiScore + 0.5)
                end
            end

            local normalizedMapID = tonumber(mapID) or 0
            local normalizedKeyLevel = tonumber(keyLevel) or 0
            local normalizedRating = tonumber(rating) or 0
            local hasCachedData = normalizedMapID > 0 or normalizedKeyLevel > 0 or normalizedRating > 0
            local isRecent = IsGuildMemberRecent(index, online and true or false, cache)

            if isPlayer or (isRecent and hasCachedData) then
                local rowEntry = {
                    name = name or fullName,
                    class = isPlayer and playerClass or cache.class or classFile,
                    mapID = normalizedMapID,
                    keyLevel = normalizedKeyLevel,
                    rating = normalizedRating,
                    spellID = GetPortalSpellIDForMap(normalizedMapID),
                    online = isPlayer or (online and true or false),
                }
                table.insert(entries, rowEntry)
                entryByName[rowEntry.name] = true
            end
        end
    end

    local store = GetGuildMemberStore()
    for cachedName, cache in pairs(store) do
        local normalized = GetNormalizedPlayerName(cachedName) or cachedName
        if not entryByName[normalized] then
            local isPlayer = normalized == playerName
            local roster = rosterByName[normalized]
            local mapID = isPlayer and playerMapID or cache.mapID
            local keyLevel = isPlayer and playerKeyLevel or cache.keyLevel
            local rating = isPlayer and playerScore or cache.rating
            local normalizedMapID = tonumber(mapID) or 0
            local normalizedKeyLevel = tonumber(keyLevel) or 0
            local normalizedRating = tonumber(rating) or 0

            if (not normalizedRating or normalizedRating <= 0) and roster and roster.guid then
                local apiScore = TryGetMythicScoreForIdentifier(roster.guid)
                if apiScore then
                    normalizedRating = floor(apiScore + 0.5)
                end
            end

            local updatedAt = tonumber(cache and cache.updatedAt)
            local now = GetServerTime and GetServerTime() or time()
            local isRecent = updatedAt and ((now - updatedAt) <= (KSM_GUILD_RECENT_DAYS * 86400)) or false
            local hasCachedData = normalizedMapID > 0 or normalizedKeyLevel > 0 or normalizedRating > 0

            if isPlayer or (isRecent and hasCachedData) then
                local rowEntry = {
                    name = normalized,
                    class = isPlayer and playerClass or cache.class or (roster and roster.classFile),
                    mapID = normalizedMapID,
                    keyLevel = normalizedKeyLevel,
                    rating = normalizedRating,
                    spellID = GetPortalSpellIDForMap(normalizedMapID),
                    online = isPlayer or (roster and roster.online or false),
                }
                table.insert(entries, rowEntry)
                entryByName[rowEntry.name] = true
            end
        end
    end

    table.sort(entries, function(left, right)
        local leftOnline = left.online and 1 or 0
        local rightOnline = right.online and 1 or 0
        if leftOnline ~= rightOnline then
            return leftOnline > rightOnline
        end

        local leftLevel = tonumber(left.keyLevel) or 0
        local rightLevel = tonumber(right.keyLevel) or 0
        if leftLevel ~= rightLevel then
            return leftLevel > rightLevel
        end

        local leftRating = tonumber(left.rating) or 0
        local rightRating = tonumber(right.rating) or 0
        if leftRating ~= rightRating then
            return leftRating > rightRating
        end

        return (left.name or "") < (right.name or "")
    end)

    if ui.ksmHideOffline then
        local visibleEntries = {}
        for _, entry in ipairs(entries) do
            if entry.online then
                table.insert(visibleEntries, entry)
            end
        end
        entries = visibleEntries
    end

    ui.ksmGuildTotalPages = max(1, math.ceil(#entries / 15))
    ui.ksmGuildPage = min(max(ui.ksmGuildPage or 1, 1), ui.ksmGuildTotalPages)

    if ui.ksmGuildPageText then
        ui.ksmGuildPageText:SetText(string.format("Page %d/%d", ui.ksmGuildPage, ui.ksmGuildTotalPages))
    end
    if ui.ksmGuildPrevButton then
        if ui.ksmGuildPage > 1 then
            ui.ksmGuildPrevButton:Enable()
            ui.ksmGuildPrevButton:SetAlpha(1)
        else
            ui.ksmGuildPrevButton:Disable()
            ui.ksmGuildPrevButton:SetAlpha(0.45)
        end
    end
    if ui.ksmGuildNextButton then
        if ui.ksmGuildPage < ui.ksmGuildTotalPages then
            ui.ksmGuildNextButton:Enable()
            ui.ksmGuildNextButton:SetAlpha(1)
        else
            ui.ksmGuildNextButton:Disable()
            ui.ksmGuildNextButton:SetAlpha(0.45)
        end
    end

    if #entries == 0 then
        local row = EnsureKSMGuildRow(1)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", ui.ksmGuildContent, "TOPLEFT", 10, -52)
        row.classIcon:Hide()
        row.nameText:SetText(ui.ksmHideOffline and "No online guild key data" or "No recent guild key data (last 7 days)")
        row.nameText:SetTextColor(1, 1, 1, 1)
        row.keyText:SetText("")
        row.dungeonText:SetText("")
        row.ratingText:SetText("")
        row.teleportButton:Hide()
        row:Show()
        for index = 2, #ui.ksmGuildRows do
            ui.ksmGuildRows[index]:Hide()
        end
        for index = 1, #ui.ksmGuildLines do
            ui.ksmGuildLines[index]:Hide()
        end
        return
    end

    local pageStart = ((ui.ksmGuildPage - 1) * 15) + 1
    local pageEnd = min(pageStart + 15 - 1, #entries)

    local y = -56
    local renderedCount = 0
    for index = pageStart, pageEnd do
        local entry = entries[index]
        renderedCount = renderedCount + 1
        local row = EnsureKSMGuildRow(renderedCount)
        local r, g, b = GetClassColorInfo(entry.class)

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", ui.ksmGuildContent, "TOPLEFT", 10, y)
        ApplyClassIcon(row.classIcon, entry.class)
        row.classIcon:Show()
        row.nameText:SetText(entry.online and (entry.name or "Unknown") or string.format("%s (offline)", entry.name or "Unknown"))
        row.nameText:SetTextColor(r, g, b, entry.online and 1 or 0.65)
        row.keyText:SetText(entry.keyLevel > 0 and string.format("+%d", entry.keyLevel) or "-")
        row.dungeonText:SetText(entry.mapID > 0 and FormatDungeonLabel(entry.mapID) or "No key")
        row.keyText:SetTextColor(1, 0.82, 0.2, entry.online and 1 or 0.65)
        row.dungeonText:SetTextColor(0.95, 0.95, 0.95, entry.online and 1 or 0.65)
        row.ratingText:SetText(entry.rating > 0 and tostring(entry.rating) or "-")
        row.ratingText:SetTextColor(0.95, 0.95, 0.95, entry.online and 1 or 0.65)

        if entry.spellID then
            row.teleportButton.spellID = entry.spellID
            row.teleportButton:Show()
            row.teleportButton.label:SetText("Teleport")
            row.teleportButton.label:SetTextColor(IsSpellKnown and IsSpellKnown(entry.spellID) and 1 or 0.55, IsSpellKnown and IsSpellKnown(entry.spellID) and 1 or 0.55, IsSpellKnown and IsSpellKnown(entry.spellID) and 1 or 0.55, 1)
        else
            row.teleportButton.spellID = nil
            row.teleportButton:Hide()
        end

        row:Show()
        y = y - 24
    end

    for index = renderedCount + 1, #ui.ksmGuildRows do
        ui.ksmGuildRows[index]:Hide()
    end

    for index = 1, #ui.ksmGuildLines do
        ui.ksmGuildLines[index]:Hide()
    end
end
