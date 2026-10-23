local _, AJ = ...

-- The Professions tab: the overview page, in the single-page window (Layouts.lua). The crafting page opens the wider singleRight window.
-- Two primary cards on the left, stacked; three secondary cards across the
-- bottom. Spell rows can be dragged to the action bars, as in the spellbook.
-- Right-edge tabs switch between the overview and each profession's crafting
-- page (Crafting.lua).
--
-- Values marked EST are estimates from prof_main_page.jpg. Check them in game.

local UI = AJ.UI
local W = UI.Widgets
local C = UI.Components
local H = AJ.Helpers
-- The overview as an open double page when expanded. Its sizes are shares of the folded window
-- (UI.Layouts.single). EST from the screenshots: the whole window is about 1.4 times the folded one,
-- and the left page with the cards about 0.6 times it.
local OVERVIEW_BOOK_SHARE = 1.4
local OVERVIEW_LEFT_SHARE = 1


local ICON = "Interface\\ICONS\\INV_SideTab_Professions_c60"
-- The section's toolbar tab icon: the atlas, which Components draws with
-- SetAtlas. The file path above stays for the side tabs, which use SetTexture.
local TAB_ICON = "Professions-up-c60"
local pickupSpell = (C_Spell and C_Spell.PickupSpell) or PickupSpell

local PAD = 12                  -- EST: page inset around the cards
local GAP = -4                   -- EST: gap between cards
local PRIMARY_SHARE = 0.31      -- EST: each primary card's share of the stacked height
local ROW_HEIGHT = 36           -- EST: a spell row (icon height)
local ROW_GAP = 2               -- EST: between spell rows
local BAR_HEIGHT = 24           -- EST: the progress bar's height in pixels
local TITLE_ROOM = 26           -- EST: room under a card's title for its bar
local UNLEARN_SIZE = 20         -- the unlearn button's size (Blizzard's book template)
local BAR_SHARE = 1           -- EST: a primary card's bar, as a share of its width
local TWO_ROW_TOP = 48          -- EST: distance from a primary card's top to its first row, when it has two or more spells
local NAME_OVERRIDES = { ["Bait and Tackle"] = "Bait & Tackle" }   -- shorter names shown on the row (English names)

-- Background and card art: Blizzard's book atlases (Blizzard_ProfessionsFrame.lua,
-- Blizzard_ProfessionsBookTemplates.xml, Blizzard_ProfessionsBook.lua)
local PRIMARY_ART = "Profession-overview-Card"   -- fallback; each profession's own card is tried first

local SECONDARY_ART = {
	"Profession-overview-card-generic-cooking",
	"Profession-overview-card-generic-fishing",
	"Profession-overview-card-generic-firstaid",
}

-- The right-edge tabs: the same placement as the spellbook's skill-line tabs (SpellBookPage.lua)
local TAB_X, TAB_TOP, TAB_STEP = -1, -40, 52

-- Reads the cards from the game's profession list. The order follows
-- Blizzard_ProfessionsBook.lua: the last three returns are cooking, fishing
-- and first aid, in that order, counting back from the end.
local function ProfessionIndexes()
	local prim1, prim2, faid, fish, cook = GetProfessions()
	return prim1, prim2, cook, fish, faid
end

-- Blizzard's rank bar, the same frame the book uses (Blizzard_ProfessionsBookTemplates.xml,
-- StatusBar; the layers are in Blizzard_ProfessionsRankBar.xml). CreateFrame cannot take the
-- book's KeyValues, so the overrides are set here and OnLoad applies them, as the template does.
local RANK_BAR_TEMPLATE = "ProfessionsRankBarTemplate"

-- Blizzard's primary-card mask offset (Blizzard_ProfessionsBookTemplates.xml, PrimaryProfessionTemplate).
-- Used for all bars. The secondary template uses -5; we keep -7.
local BAR_MASK_RIGHT_OFFSET = -7

local function MakeBar(parent, width, fillLeft)
	local bar = CreateFrame("Frame", nil, parent, RANK_BAR_TEMPLATE)
	bar.overrideBorderAtlas = "Profession-ProgressBar-frame"
	bar.overrideBackgroundAtlas = "Profession-ProgressBar-BG"
	bar.overrideWidth = width
	bar.overrideFillAnchorLeft = fillLeft
	bar.overrideMaskRightOffset = BAR_MASK_RIGHT_OFFSET
	bar.ownerManagesEvents = true
	bar:SetFrameStrata("HIGH")
	bar:OnLoad()
	return bar
end

-- Updates the bar the way the book does (Blizzard_ProfessionsBook.lua, UpdateRankBar).
local function UpdateRankBar(bar, skillLine, rank, maxRank, rankModifier)
	local info = C_TradeSkillUI.GetProfessionInfoBySkillLineID(skillLine)
	if bar and info then
		if info.skillLevel == 0 and info.maxSkillLevel == 0 then
			info.skillLevel = rank
			info.maxSkillLevel = maxRank
			info.skillModifier = rankModifier
		end
		bar.lastInfo = info
		bar:Update(info)
		bar:Show()
	end
end

-- Dragging a row picks up a character-specific macro instead of the spell. P1/P2/S1..S3 open our crafting
-- page for that profession; the second spell's macro (P1bis, S1bis ...) casts that spell.
local function PickupProfessionMacro(row)
	if InCombatLockdown() then AJ:Print("Macros cannot be made in combat."); return end
	local name = row.name:GetText() or row.key
	local body
	if row.bis then
		local spellName = row.spellID and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(row.spellID)
		if not spellName then return end
		body = "/cast " .. spellName
	else
		if not row.skillLine then return end
		body = "/jprof " .. row.skillLine
	end
	local icon = (row.spellID and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(row.spellID)) or "INV_Misc_QuestionMark"
	local index = GetMacroIndexByName(name)
	if index == 0 then
		local _, numPerChar = GetNumMacros()
		if numPerChar >= (MAX_CHARACTER_MACROS or 138) then AJ:Print("No free character macro slot."); return end
		index = CreateMacro(name, icon, body)
		if not index or index == 0 then AJ:Print("Could not create the macro."); return end
	else
		EditMacro(index, name, icon, body)
	end
	PickupMacro(index)
end

-- A spell row: framed icon, name, and the rank line under it (for the
-- profession spell this reads "Apprentice"). Drag it to an action bar.
local function MakeRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(ROW_HEIGHT)
	row:RegisterForDrag("LeftButton")

	row.icon = W.CreateFramedIcon(row)
	row.icon:SetPoint("LEFT", 0, 0)

	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -2)

	row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)

	row:SetScript("OnDragStart", function(self)
		if self.key then PickupProfessionMacro(self) elseif self.spellID then pickupSpell(self.spellID) end
	end)
	row:SetScript("OnEnter", function(self)
		if not self.spellID then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetSpellByID(self.spellID)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip_Hide() end)
	return row
end

-- Shows the first atlas in `candidates` that the client has; hides the texture if none.
local function ShowArt(tex, candidates)
	for _, atlas in ipairs(candidates) do
		if atlas and C_Texture.GetAtlasInfo(atlas) then
			tex:SetAtlas(atlas)
			tex:Show()
			return
		end
	end
	tex:Hide()
end

local function MakeCard(parent, width, height, primary)
	local card = CreateFrame("Frame", nil, parent)
	card:SetSize(width, height)
	card.rows = {}
	card.primary = primary
	card.art = card:CreateTexture(nil, "BACKGROUND")
	card.art:SetAllPoints(card)
	card.art:Hide()

	card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	card.missing = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	card.missing:SetWidth(width - 2 * PAD)
	card.missing:SetJustifyH("CENTER")
	card.missing:SetPoint("CENTER")

	if primary then
		card.art:ClearAllPoints()
		card.art:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -(PAD + TITLE_ROOM))
		card.art:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 0, 0)
		-- Title at the left, bar and unlearn button on the same line at the right.
		card.title:SetPoint("CENTER", card, "TOPLEFT", (width/2), -PAD)
		card.bar = MakeBar(card, math.floor(width * BAR_SHARE), 2)
		card.bar:SetPoint("TOPRIGHT", card, "TOPRIGHT", -(PAD + UNLEARN_SIZE + 6), -PAD - 4)

		card.unlearn = CreateFrame("Button", nil, card)
		card.unlearn:SetSize(UNLEARN_SIZE, UNLEARN_SIZE)
		card.unlearn:SetPoint("TOPRIGHT", card, "TOPRIGHT", GAP, -2*BAR_HEIGHT+6)
		card.unlearn.Icon = card.unlearn:CreateTexture(nil, "ARTWORK")
		card.unlearn.Icon:SetAtlas("Profession-button-red-crossmark", true)
		card.unlearn.Icon:SetPoint("CENTER")
		card.unlearn.Overlay = card.unlearn:CreateTexture(nil, "OVERLAY")
		card.unlearn.Overlay:SetAtlas("Profession-button-red-crossmark-pressed", true)
		card.unlearn.Overlay:SetPoint("CENTER")
		card.unlearn.Overlay:Hide()
		card.unlearn:SetScript("OnMouseDown", function(self) self.Overlay:Show() end)
		card.unlearn:SetScript("OnMouseUp", function(self) self.Overlay:Hide() end)
		card.unlearn:SetScript("OnHide", function(self) self.Overlay:Hide() end)
		card.unlearn:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(UNLEARN_SKILL_TOOLTIP)
		end)
		card.unlearn:SetScript("OnLeave", function() GameTooltip_Hide() end)
		card.unlearn:SetScript("OnClick", function(self)
			if not self.skillLine then return end
			local popupName = InputUtil.IsGamepadUIEnabled() and "UNLEARN_SKILL_GAMEPAD" or "UNLEARN_SKILL"
			StaticPopup_Show(popupName, self.skillName, nil, self.skillLine)
		end)
	else
		-- Title centred at the top, bar across the full width beneath it.
		card.title:SetPoint("TOP", card, "TOP", 0, -PAD)
		card.bar = MakeBar(card, width - 2 * PAD, 0)
		card.bar:SetPoint("TOPLEFT", card, "TOPLEFT", PAD, -(PAD + TITLE_ROOM))
	end

	return card
end

-- Spell rows. Primary cards stack down from under the title; secondary cards
-- stack up from the bottom.
local function FillRows(card, spellOffset, numSpells)

	local width = card:GetWidth() - 2 * PAD
	-- Primary cards: one spell's icon sits at the middle of the card; two or more
	-- start at TWO_ROW_TOP.
	local startY = (card:GetHeight() - ROW_HEIGHT) / 1.4
	if card.primary and numSpells >= 2 then startY = TWO_ROW_TOP end
	for i = 1, numSpells do
		local row = card.rows[i] or MakeRow(card)
		card.rows[i] = row
		row.key = card.key
		row.skillLine = card.skillLine
		row.bis = i > 1
		row:SetWidth(width)
		row:SetHitRectInsets(0, width - ROW_HEIGHT, 0, 0)
		row:ClearAllPoints()

		if card.primary then
			if i == 1 then
				row:SetPoint("TOPLEFT", card, "TOPLEFT", PAD, -startY)
			else
				row:SetPoint("TOPLEFT", card.rows[i - 1], "BOTTOMLEFT", 0, -ROW_GAP)
			end
		else
			if i == 1 then
				row:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", PAD, PAD)
			else
				row:SetPoint("BOTTOMLEFT", card.rows[i - 1], "TOPLEFT", 0, ROW_GAP)
			end
		end

		local info = C_SpellBook.GetSpellBookItemInfo(spellOffset + i, Enum.SpellBookSpellBank.Player)
		row.spellID = info and info.spellID or nil
		if info then
			row.icon:Set(info.iconID, true)   -- the square frame; the shopping list keeps the round one
			row.name:SetText(NAME_OVERRIDES[info.name] or info.name or "")
			row.sub:SetText(info.subName or "")
			-- Two lines (name and rank) sit at the top of the row; one line is centred on the icon.
			row.name:ClearAllPoints()
			if info.subName and info.subName ~= "" then
				row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -2)
			else
				row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
			end
		end
		row:Show()
	end

	for i = numSpells + 1, #card.rows do
		card.rows[i]:Hide()
	end
end

-- Fills a card from a profession index, or shows the missing text if the
-- character has no profession there.
local function SetCard(card, index, title, missingText)
	if not index then
		card.title:SetText(title)
		ShowArt(card.art, card.primary and { PRIMARY_ART } or { card.artDefault })
		card.bar:Hide()
		card.missing:SetText(missingText)
		card.missing:Show()
		for _, row in ipairs(card.rows) do row:Hide() end
		if card.unlearn then card.unlearn:Hide() end
		return
	end

	local name, _, rank, maxRank, numSpells, spellOffset, skillLine, rankModifier = GetProfessionInfo(index)
	card.skillLine = skillLine
	if card.primary then
		ShowArt(card.art, { "Profession-overview-Card-" .. name, PRIMARY_ART })
	else
		ShowArt(card.art, { card.artDefault })
	end

	card.missing:Hide()
	card.title:SetText(name)
	UpdateRankBar(card.bar, skillLine, rank or 0, maxRank, rankModifier)
	if card.unlearn then
		card.unlearn.skillName = name
		card.unlearn.skillLine = skillLine
		card.unlearn:Show()
	end

	FillRows(card, spellOffset, numSpells or 0)
end

-- Per-bar scale and position, set with /profbar and kept in the addon's saved settings.
local BAR_KEYS = { "p1", "p2", "s1", "s2", "s3" }

-- The tuned layout, used when no saved setting exists (a clean install).
local BAR_DEFAULTS = {
	p1 = { x = 0, y = -20, showName = false },
	p2 = { x = 0, y = -20, showName = false },
	s1 = { showName = false },
	s2 = { showName = false },
	s3 = { showName = false },
}

-- Set to true to tune the bars with /profbar. Leave false for the final addon.
local TUNING = false

local function BarCards(o)
	return {
		p1 = o.primary[1], p2 = o.primary[2],
		s1 = o.secondary[1], s2 = o.secondary[2], s3 = o.secondary[3],
	}
end

local function BarSettings()
	AJ.settings = AJ.settings or {}
	AJ.settings.profBars = AJ.settings.profBars or {}
	return AJ.settings.profBars
end

-- Applies one bar's scale and position. With no position set, the bar keeps its default anchor.
local function ApplyBarLayout(card, cfg)
	local bar = card.bar
	if not bar then return end
	bar:SetScale(cfg and cfg.scale or 1)

	local text = bar.Rank and bar.Rank.Text
	if text and bar.defaultFont and bar.defaultFont[1] then
		local path, size, flags = unpack(bar.defaultFont)
		text:SetFont(path, cfg and cfg.fontSize or size, flags)
	end

	if cfg and (cfg.x or cfg.y) then
		bar:ClearAllPoints()
		bar:SetPoint("TOPLEFT", card, "TOPLEFT", cfg.x or 0, cfg.y or 0)
	elseif bar.defaultPoint then
		bar:ClearAllPoints()
		bar:SetPoint(unpack(bar.defaultPoint))
	end

	-- The name ("Alchemy") can be hidden, leaving the numbers. The numbers come from the last update.
	local info = bar.lastInfo
	if info and text then
		if cfg and cfg.showName == false then
			local modifier = info.skillModifier or 0
			if modifier > 0 then
				text:SetText(string.format("%d (+%d)/%d", info.skillLevel, modifier, info.maxSkillLevel))
			else
				text:SetText(string.format("%d/%d", info.skillLevel, info.maxSkillLevel))
			end
		else
			bar:Update(info)   -- Blizzard's text, with the name
		end
	end
end

local function ApplyBarLayouts(o)
	local cards = BarCards(o)
	local settings = BarSettings()
	for _, key in ipairs(BAR_KEYS) do
		ApplyBarLayout(cards[key], settings[key] or BAR_DEFAULTS[key])
	end
end

-- Blizzard's filigree ornament at the top centre of a border (from JournalHelpers.lua).
local TOP_DETAIL_ATLAS = "QuestLog-frame-filigree"

local function FrameTopDetail(host, border)
	-- its own frame, above the host's child frames
	local layer = CreateFrame("Frame", nil, host)
	layer:SetAllPoints(host)
	layer:SetFrameLevel(host:GetFrameLevel() + 50)
	local t = H.Atlas(layer, TOP_DETAIL_ATLAS, "OVERLAY")
	t:SetSize(48, 19)
	t:SetPoint("TOP", border, "TOP", 0, 1)
	t:SetVertexColor(border:GetVertexColor())
	t:SetAlpha(border:GetAlpha())
	return t
end

local function BuildOverview(page)
	-- The content frame: holds the cards. It has no background of its own,
	-- so the page's paper shows through.
	local container = CreateFrame("Frame", nil, page)
	container:SetAllPoints(page)

	local pageWidth, pageHeight = page:GetWidth(), page:GetHeight()
	local inner = pageWidth - 2 * PAD
	local usable = pageHeight - 2 * PAD - 2 * GAP
	local primaryHeight = math.floor(usable * PRIMARY_SHARE)
	local secondaryHeight = usable - 2 * primaryHeight
	local secondaryWidth = math.floor((inner - 2 * GAP) / 3)

	local overview = { container = container, primary = {}, secondary = {} }

	overview.primary[1] = MakeCard(container, inner, primaryHeight, true)
	overview.primary[1].key = "P1"
	overview.primary[1]:SetPoint("TOPLEFT", container, "TOPLEFT", PAD-4, -PAD+8)

	overview.primary[2] = MakeCard(container, inner, primaryHeight, true)
	overview.primary[2].key = "P2"
	overview.primary[2]:SetPoint("TOPLEFT", overview.primary[1], "BOTTOMLEFT", 0, -GAP)

	local dark = H.TrackPanel(
		H.Atlas(container, "UI-Character-Info-General-BG", "BACKGROUND", -8),
		container, "profstat"
	)

	local border = H.FrameBorder(container, "common-insideframe", "profborder", "OVERLAY")
	FrameTopDetail(container, border)

	for i = 1, 3 do
		local card = MakeCard(container, secondaryWidth, secondaryHeight, false)
		card.key = "S" .. i
		card:SetPoint("TOPLEFT", overview.primary[2], "BOTTOMLEFT", (i - 1) * (secondaryWidth + GAP)+1, -GAP-3)
		card.artDefault = SECONDARY_ART[i]
		overview.secondary[i] = card
	end

	return overview
end

-- A right-edge tab, placed the way the spellbook places its skill-line tabs.
local function NewSideTab(frame, slot, icon, onClick, tipText)
	local tab = C.CreateSideTab(frame)
	tab:SetPoint("TOPLEFT", frame, "TOPRIGHT", TAB_X, TAB_TOP - (slot - 1) * TAB_STEP)
	tab.icon:SetTexture(icon)
	tab.tipText = tipText
	tab:SetScript("OnClick", function()
		W.PlayUISound(W.Sounds.PAGE)
		onClick()
	end)
	tab:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.tipText or "", 1, 1, 1)
		GameTooltip:Show()
	end)
	tab:SetScript("OnLeave", function() GameTooltip_Hide() end)
	tab:Hide()
	return tab
end

-- The window: made at the crafting page's width, so its scale is set for that
-- width, then narrowed to the overview's. The overview is one page (single);
-- the crafting page is an open book (singleRight).
-- True while the Journal's crafting page is open: the game's profession window is hidden as it shows.
local suppressGameProfessions = false

-- Blizzard's profession window stays shown, because the game loads a tab's trade skill through it.
-- It is made invisible and sent behind our page, so it cannot catch clicks. The settings are saved
-- and put back when the Journal's page closes.
-- In combat the frame strata is protected (the taint log shows SetFrameStrata blocked), so the
-- strata change waits until PLAYER_REGEN_ENABLED. Alpha is still set at once.
local gameProfessionsSaved = nil
local pendingStrata = nil   -- { frame, strata }, applied when combat ends

local function SetGameProfessionsStrata(f, strata)
	if InCombatLockdown() then
		pendingStrata = { frame = f, strata = strata }
		return
	end
	pendingStrata = nil
	f:SetFrameStrata(strata)
end

local strataWatcher = CreateFrame("Frame")
strataWatcher:SetScript("OnEvent", function()
	local p = pendingStrata
	if not p then return end
	pendingStrata = nil
	p.frame:SetFrameStrata(p.strata)
end)
strataWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")

local function MakeGameProfessionsInert(f)
	if not gameProfessionsSaved then
		gameProfessionsSaved = { alpha = f:GetAlpha(), strata = f:GetFrameStrata() }
	end
	f:SetAlpha(0)
	SetGameProfessionsStrata(f, "BACKGROUND")
end

local function RestoreGameProfessions()
	local f = ProfessionsFrame
	if not f or not gameProfessionsSaved then return end
	f:SetAlpha(gameProfessionsSaved.alpha or 1)
	SetGameProfessionsStrata(f, gameProfessionsSaved.strata or "HIGH")
	gameProfessionsSaved = nil
end


local function BuildFrame(section)
	local craftWidth = UI.Layouts.singleRight.width
	local overviewWidth = UI.Layouts.single.width

	local frame = C.CreateWindow("Journal_professionsFrame", section.label, craftWidth, 508, 16, -104,
		W.Sounds.SPELLBOOK_OPEN, W.Sounds.SPELLBOOK_CLOSE)
	frame:Hide()

	-- The crafting page, built at its own width.
	local book, craftLeft, craftRight = C.CreateSplitBook(frame, UI.Layouts.singleRight.left)
	book:Hide()
	section.craftBook = book
	section.craftLeft = craftLeft
	section.crafting = AJ.Crafting.Build(frame, craftLeft, craftRight)

	-- The folded window: the single page. Its width is the left page's width, so the cards keep their size.
	frame:SetWidth(overviewWidth)
	local singlePage = C.CreatePage(frame)
	local leftWidth = singlePage:GetWidth()

	-- The overview as an open double page, the same width as the crafting page.
	local bookWidth = craftWidth
	section.bookWidth = bookWidth
	frame:SetWidth(bookWidth)
	
	local obook, obookLeft, obookRight = C.CreateSplitBook(frame, leftWidth)
	obook:Hide()
	section.overviewBook = obook
	section.overviewLeft = obookLeft
	section.overviewRight = obookRight

	frame:SetWidth(overviewWidth)
	return frame, singlePage
end

-- A profession spell (action bar icon) opens the game's window. The crafting page for that same
-- profession is shown instead, and the game's window is made inert.
local selfOpenUntil = 0
local redirecting = false
local redirectPending = false
local function RedirectToSkill(section, skillLine, f)
	if redirecting then return end
	redirecting = true
	suppressGameProfessions = true
	if f then MakeGameProfessionsInert(f) end
	UI:Open("professions")   -- builds the page the first time, and refreshes its tabs
	for _, tab in ipairs(section.professionTabs or {}) do
		if tab.skillLine == skillLine and tab:IsShown() then
			--AJ:Print("DIAG redirect to " .. tostring(tab.professionName) .. " crafting page")
			section:OpenCrafting(tab, true)
			break
		end
	end
	redirecting = false
end

local existingSection
for _, sec in ipairs(UI:GetSections()) do
	if sec.key == "professions" then existingSection = sec end
end
local Section = existingSection or UI:NewSection("professions", { label = "Professions", icon = TAB_ICON, order = 10 })

local MAX_PROFESSIONS = 5

-- What the overview shows: each profession, with its name and rank. Compared
-- when the game fires an event, so the overview only redraws when something changed.
local function ProfessionSignature()
	local parts = {}
	for i = 1, 7 do
		local index = select(i, GetProfessions())
		if index then
			local name, _, rank, maxRank = GetProfessionInfo(index)
			parts[#parts + 1] = tostring(index) .. ":" .. tostring(name) .. ":" .. tostring(rank) .. "/" .. tostring(maxRank)
		else
			parts[#parts + 1] = "-"
		end
	end
	return table.concat(parts, "|")
end

-- Spell ID of each profession's main spell -> its skill line. The action bar icon casts this spell.
local professionSpells = {}
local function BuildProfessionSpells()
	for _, index in pairs({ GetProfessions() }) do
		local _, _, _, _, _, spellOffset, skillLine = GetProfessionInfo(index)
		local info = skillLine and C_SpellBook and C_SpellBook.GetSpellBookItemInfo(spellOffset + 1, Enum.SpellBookSpellBank.Player)
		if info and info.spellID then professionSpells[info.spellID] = skillLine end
	end
end

-- The hooks on the game's profession window. Installed when Blizzard_Professions loads, so the
-- first spell press is already redirected, even before our page has been built.
local gameHooksInstalled = false
local function InstallGameHooks()
	if gameHooksInstalled or not ProfessionsFrame then return end
	gameHooksInstalled = true
	BuildProfessionSpells()
	hooksecurefunc(ProfessionsFrame, "Hide", function()
		if suppressGameProfessions and Section.frame and Section.frame:IsShown() then Section.frame:Hide() end
	end)
	hooksecurefunc(ProfessionsFrame, "Show", function(f)
		if suppressGameProfessions then MakeGameProfessionsInert(f) end
	end)
end

local gameHookLoader = CreateFrame("Frame")
gameHookLoader:RegisterEvent("ADDON_LOADED")
gameHookLoader:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
gameHookLoader:SetScript("OnEvent", function(_, event, a1, _, a3)
	if event == "ADDON_LOADED" then
		if a1 == "Blizzard_Professions" then InstallGameHooks() end
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" and a1 == "player" and gameHooksInstalled then
		local skillLine = professionSpells[a3]
		if not skillLine then return end
		if GetTime() < selfOpenUntil then return end   -- our own switch; ignore both lines' casts
		-- While our page is open, only a cast for the trade skill that is open switches it. A tab click
		-- can make the game cast another profession's spell; that cast is ignored.
		if Section.frame and Section.frame:IsShown() and Professions and Professions.GetEffectiveSkillLineID
			and Professions.GetEffectiveSkillLineID() ~= skillLine then return end
		if Section.frame and Section.frame:IsShown() and Section.view == "crafting" and Section.craftSkillLine == skillLine then
			Section.frame:Hide()   -- the same spell again closes the page, as the game's window does
		else
			RedirectToSkill(Section, skillLine, ProfessionsFrame)
		end
	end
end)

function Section:Create()
	C_AddOns.LoadAddOn("Blizzard_Professions")
	local frame, page = BuildFrame(self)
	self.frame = frame
	-- The game's profession window comes back when the Journal's page closes.
	local gameRestorePending = false
	local restoreWatcher = CreateFrame("Frame")
	restoreWatcher:SetScript("OnEvent", function()
		if not gameRestorePending then return end
		gameRestorePending = false
		-- If the page was opened again during combat, the restore waits for its next close.
		if frame:IsShown() then return end
		RestoreGameProfessions()
		if ProfessionsFrame and ProfessionsFrame:IsShown() then ProfessionsFrame:Hide() end
	end)
	restoreWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")

	frame:HookScript("OnHide", function()
		selfOpenUntil = 0
		suppressGameProfessions = false
		if not ProfessionsFrame then return end
		-- In combat the game's window cannot be hidden or re-stacked (the taint log shows
		-- Hide and SetFrameStrata blocked), so this waits for PLAYER_REGEN_ENABLED.
		if InCombatLockdown() then
			gameRestorePending = true
			return
		end
		RestoreGameProfessions()
		if ProfessionsFrame:IsShown() then ProfessionsFrame:Hide() end
	end)
	InstallGameHooks()
	self.page = page
	self.overview = BuildOverview(page)
	
	-- The right page gets the cards' panel: background, border and top detail, ready for the shopping list.
	self.rightPanel = CreateFrame("Frame", nil, self.overviewRight)
	self.rightPanel:ClearAllPoints()
	self.rightPanel:SetPoint("TOPLEFT", self.overviewRight, "TOPLEFT", 8, -8)
	self.rightPanel:SetPoint("BOTTOMRIGHT", self.overviewRight, "BOTTOMRIGHT", 0, 8)
	H.TrackPanel(
		H.Atlas(self.rightPanel, "UI-Character-Info-General-BG", "BACKGROUND", -8),
		self.rightPanel, "profstat"
	)
	local rightBorder = H.FrameBorder(self.rightPanel, "common-insideframe", "profborder", "OVERLAY")
	FrameTopDetail(self.rightPanel, rightBorder)
	
	-- The Shopping List plate over the right page, built as Character's stats plate is (Character.lua 620-630).
	local SHOPPING_TITLE_W, SHOPPING_TITLE_H = 150, 32   -- plate size, as Character.lua 63
	local SHOPPING_TITLE_Y = 24                          -- above the page's top edge, as Character.lua 64
	self.shoppingTitle = CreateFrame("Frame", nil, self.overviewRight)
	self.shoppingTitle:SetFrameLevel(frame:GetFrameLevel() + 30)   -- EST: above the page art
	self.shoppingTitle:SetSize(SHOPPING_TITLE_W, SHOPPING_TITLE_H)
	self.shoppingTitle:SetPoint("CENTER", self.overviewRight, "TOP", 0, SHOPPING_TITLE_Y)
	H.Atlas(self.shoppingTitle, "UI-Character-Info-Title", "BACKGROUND"):SetAllPoints()
	local shoppingTitleText = self.shoppingTitle:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	shoppingTitleText:SetPoint("CENTER")
	shoppingTitleText:SetText("Shopping List")
	self.shoppingTitle:SetWidth(math.max(SHOPPING_TITLE_W, shoppingTitleText:GetStringWidth() + 40))
	
	-- The shopping list: a scroll area with the client's scroll bar, as Character's stat list has.
	local scroll = CreateFrame("ScrollFrame", nil, self.rightPanel)
	scroll:SetPoint("TOPLEFT", self.rightPanel, "TOPLEFT", 14, -14)
	scroll:SetPoint("BOTTOMRIGHT", self.rightPanel, "BOTTOMRIGHT", -20, 20)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)
	-- In combat the client returns a secret number here, so the range is worked out from the heights (as Character.lua does).
	scroll.GetVerticalScrollRange = function(self)
		return math.max(0, content:GetHeight() - self:GetHeight())
	end
	local bar = CreateFrame("EventFrame", nil, self.rightPanel, "MinimalScrollBar")
	bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 8, -8)
	bar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 2, 8)
	scroll:EnableMouseWheel(true)
	ScrollUtil.InitScrollFrameWithScrollBar(scroll, bar)
	self.shoppingScroll, self.shoppingContent, self.shoppingBar = scroll, content, bar
	self.shoppingRows = {}

	-- Keeps the content as wide as the box, the thumb the right size, and the bar shown only when needed.
	self.updateShoppingRange = function()
		local w = scroll:GetWidth()
		if w and w > 0 then content:SetWidth(w) end
		local h = scroll:GetHeight()
		local max = math.max(0, content:GetHeight() - h)
		if scroll:GetVerticalScroll() > max then scroll:SetVerticalScroll(max) end
		bar:SetVisibleExtentPercentage(h > 0 and h / (max + h) or 0)
		bar:SetShown(max > 0.5)
	end
	scroll:SetScript("OnSizeChanged", function() self.updateShoppingRange() end)
	scroll:SetScript("OnScrollRangeChanged", function() self.updateShoppingRange() end)
	
	-- Shown when nothing is short: how to track a recipe, with the crafting page's tracking mark.
	self.shoppingEmpty = self.rightPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	self.shoppingEmpty:SetPoint("TOPLEFT", self.rightPanel, "TOPLEFT", 40, -44)
	self.shoppingEmpty:SetPoint("RIGHT", self.rightPanel, "RIGHT", -40, 0)
	self.shoppingEmpty:SetJustifyH("CENTER")
	self.shoppingEmpty:SetWordWrap(true)
	self.shoppingEmpty:SetText("No recipe tracked |TInterface\\GossipFrame\\AvailableQuestIcon:16|t")
	self.shoppingEmpty:Hide()
	
	for _, card in pairs(BarCards(self.overview)) do
		card.bar.defaultPoint = { card.bar:GetPoint(1) }
		card.bar.defaultFont = { card.bar.Rank.Text:GetFont() }
	end

	-- The arrow sits 413 px into the left page: the single page when folded, the book's left page when open.
	self.expanded = true
	self.expandAnchor = CreateFrame("Frame", nil, frame)
	self.expandAnchor:SetSize(413, 1)
	self.expandToggle = C.CreateExpandToggle(frame, self.expandAnchor, function()
		self.expanded = not self.expanded
		C.SetExpandArrow(self.expandToggle, self.expanded)
		self:ShowOverview()
	end)
	for _, card in pairs(BarCards(self.overview)) do
		card.bar.defaultPoint = { card.bar:GetPoint(1) }
		card.bar.defaultFont = { card.bar.Rank.Text:GetFont() }
	end
	-- self.crafting and self.craftBook were made in BuildFrame.

	self.overviewTab = NewSideTab(frame, 1, ICON, function() self:ShowOverview() end, "Overview")
	self.overviewTab:Show()

	self.professionTabs = {}
	for i = 1, MAX_PROFESSIONS do
		self.professionTabs[i] = NewSideTab(frame, i + 1, ICON, function()
			self:OpenCrafting(self.professionTabs[i])
		end, "")
	end

	-- Learning or unlearning a profession changes the lists. Rebuild the tab then, if it is open.
	local eventFrame = CreateFrame("Frame")
	eventFrame:RegisterEvent("SKILL_LINES_CHANGED")
	eventFrame:RegisterEvent("SPELLS_CHANGED")
	eventFrame:SetScript("OnEvent", function()
		if frame:IsShown() and ProfessionSignature() ~= self.signature then self:Refresh() end
	end)
	self.eventFrame = eventFrame

	self:ShowOverview()
	return frame
end

local SHOPPING_ROW_H = 38   -- one reagent row, as the crafting page's reagent rows

-- A row: framed icon, then "owned/required name" beside it.
local function MakeShoppingRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(SHOPPING_ROW_H)
	row.icon = W.CreateFramedIcon(row)
	row.icon:SetPoint("LEFT", 0, 0)
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.text:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -2)
	row.text:SetPoint("RIGHT", row, "RIGHT", 0, 0)   -- the right edge is the row's, so the text wraps inside the box
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(true)
	return row
end

-- Fills the Shopping List with one row per reagent still short for the tracked recipes (read only).
function Section:RefreshShoppingList()
	if not self.shoppingContent then return end
	local ok, rows = pcall(ShoppingListUtil.GetShortfall)
	for _, row in ipairs(self.shoppingRows) do row:Hide() end
	if not ok then
		AJ:Print("Shopping list: " .. tostring(rows))
		return
	end
	self.shoppingEmpty:SetShown(#rows == 0)
	local content = self.shoppingContent
	local y = 0
	for i, entry in ipairs(rows) do
		local row = self.shoppingRows[i] or MakeShoppingRow(content)
		self.shoppingRows[i] = row
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
		row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
		y = y + SHOPPING_ROW_H

		local reagent = entry.reagent
		local iconID, name
		if reagent.itemID then
			iconID = C_Item.GetItemIconByID(reagent.itemID)
			name = Item:CreateFromItemID(reagent.itemID):GetItemName()
		elseif reagent.currencyID then
			local info = C_CurrencyInfo.GetCurrencyInfo(reagent.currencyID)
			iconID = info and info.iconFileID
			name = info and info.name
		end
		row.icon:Set(iconID or "Interface\\Icons\\INV_Misc_QuestionMark")
		row.text:SetText(string.format("%s/%s %s", tostring(entry.owned or "?"), tostring(entry.required), name or "..."))
		row.text:SetTextColor(0.5, 0.5, 0.5)
		row:Show()
	end

	content:SetHeight(math.max(1, y))
	self.updateShoppingRange()
end

-- Shows the overview page and selects its tab.
function Section:ShowOverview()
	self.view = "overview"
	local open = self.expanded == true
	self.frame:SetWidth(open and self.bookWidth or UI.Layouts.single.width)
	-- One set of cards: it moves to the book's left page when open, so its numbers stay.
	local host = open and self.overviewLeft or self.page
	local container = self.overview.container
	container:ClearAllPoints()
	container:SetParent(host)
	container:SetAllPoints(host)
	container:Show()
	self.page:SetShown(not open)
	self.overviewBook:SetShown(open)
	self.craftBook:Hide()
	self.expandAnchor:ClearAllPoints()
	self.expandAnchor:SetSize(413, 1)
	self.expandAnchor:SetPoint("TOPLEFT", open and self.overviewLeft or self.page, "TOPLEFT")
	self.expandToggle:Show()
	self.crafting:Hide()
	self.overviewTab.selected:Show()
	for _, tab in ipairs(self.professionTabs) do
		tab.selected:Hide()
	end
	self:RefreshShoppingList()
end

-- Shows a profession's crafting page and selects its tab.
function Section:OpenCrafting(tab, skipOpen)
	if not tab or not tab:IsShown() then return end
	-- Make the game's trade skill this profession, so the crafting page reads it.
	if not skipOpen and tab.skillLine and C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill then
	    --[[
		if InCombatLockdown() then
			AJ:Print("Professions cannot be switched in combat.")
			return
		end
		]]--
		suppressGameProfessions = true
		selfOpenUntil = GetTime() + 1
		
		local ok, err = pcall(C_TradeSkillUI.OpenTradeSkill, tab.skillLine)
		if not ok then AJ:Print("could not open " .. tostring(tab.professionName) .. ": " .. tostring(err)) end
	end
	self.view = "crafting"
	self.expandToggle:Hide()   -- the arrow belongs to the overview only
	self.craftSkillLine = tab.skillLine
	self.overview.container:Hide()
	self.overviewBook:Hide()
	self.frame:SetWidth(UI.Layouts.singleRight.width)
	self.crafting.SetProfession(tab.skillLine)
	self.craftBook:Show()
	self.crafting:Show()
	-- The crafting page has no title yet; the open tab shows the profession.
	self.overviewTab.selected:Hide()
	for _, other in ipairs(self.professionTabs) do
		other.selected:SetShown(other == tab)
	end
end

-- Called each time the tab opens: reads the professions again and rebuilds the
-- right-edge tabs for the professions the character has.
function Section:Refresh()


	if self.view == "crafting" and self.frame and not self.frame:IsShown() then
		self:ShowOverview()
	end
	
	
	if not self.overview then return end
	self.signature = ProfessionSignature()

	local prim1, prim2, cook, fish, faid = ProfessionIndexes()
	
	local primaryMissing = "Visit a profession trainer in a major city to learn a new profession."
	for _, o in ipairs({ self.overview }) do
		SetCard(o.primary[1], prim1, H.L("PROFESSIONS_FIRST_PROFESSION", "First Profession"), primaryMissing)
		SetCard(o.primary[2], prim2, H.L("PROFESSIONS_SECOND_PROFESSION", "Second Profession"), primaryMissing)

		SetCard(o.secondary[1], cook, H.L("PROFESSIONS_COOKING", "Cooking"),
			H.L("PROFESSIONS_COOKING_MISSING", "Visit a trainer to learn cooking."))
		SetCard(o.secondary[2], fish, H.L("PROFESSIONS_FISHING", "Fishing"),
			H.L("PROFESSIONS_FISHING_MISSING", "Visit a trainer to learn fishing."))
		SetCard(o.secondary[3], faid, H.L("PROFESSIONS_FIRST_AID", "First Aid"),
			H.L("PROFESSIONS_FIRST_AID_MISSING", "Visit a trainer to learn first aid."))

		ApplyBarLayouts(o)
	end

	-- Profession tabs, placed in the order saved in AJ.settings.profTabOrder (a list of skill lines,
	-- the same idea as Character.lua's GetTabOrder). Professions not in the saved list keep the default order.
	local present, byLine = {}, {}
	local indexes = { prim1, prim2, faid, cook, fish }
	for i = 1, 5 do
		local index = indexes[i]
		if index then
			local name, texture, _, _, _, _, skillLine = GetProfessionInfo(index)
			if skillLine then
				local p = { name = name, texture = texture, skillLine = skillLine }
				present[#present + 1] = p
				byLine[skillLine] = p
			end
		end
	end

	local saved = AJ.settings and AJ.settings.profTabOrder
	local ordered, used = {}, {}
	if type(saved) == "table" then
		for _, skillLine in ipairs(saved) do
			local p = byLine[skillLine]
			if p and not used[skillLine] then
				ordered[#ordered + 1] = p
				used[skillLine] = true
			end
		end
	end
	for _, p in ipairs(present) do
		if not used[p.skillLine] then
			ordered[#ordered + 1] = p
			used[p.skillLine] = true
		end
	end

	for slot, p in ipairs(ordered) do
		local tab = self.professionTabs[slot]
		tab.professionName = p.name
		tab.skillLine = p.skillLine
		tab.icon:SetTexture(p.texture)
		tab.tipText = p.name
		tab:ClearAllPoints()
		tab:SetPoint("TOPLEFT", self.frame, "TOPRIGHT", TAB_X, TAB_TOP - slot * TAB_STEP)
		tab:Show()
	end
	for i = #ordered + 1, #self.professionTabs do
		self.professionTabs[i]:Hide()
	end

	-- If the open profession is no longer there, go back to the overview.
	if self.view == "crafting" then
		local open = false
		for _, tab in ipairs(self.professionTabs) do
			if tab:IsShown() and tab.selected:IsShown() then open = true end
		end
		if not open then self:ShowOverview() end
	end
		self:RefreshShoppingList()   -- read each time the tab opens, not only when the arrow is pressed
end

-- /profbar list
-- /profbar <p1|p2|s1|s2|s3> scale <number>
-- /profbar <p1|p2|s1|s2|s3> pos <x> <y>     (offset from the card's top left)
-- /profbar <p1|p2|s1|s2|s3> reset
local HELP = "/profbar list | <p1|p2|s1|s2|s3> scale <n> | <key> pos <x> <y> | <key> font <size> | <key> name on|off | <key> reset"

if TUNING then
SLASH_PROFBAR1 = "/profbar"
SlashCmdList["PROFBAR"] = function(msg)
	local words = {}
	for w in (msg or ""):gmatch("%S+") do table.insert(words, w:lower()) end
	local key, cmd = words[1], words[2]

	if not key or key == "help" then
		print(HELP)
		return
	end
	local o = Section.overview
	if not o then
		print("Journal: open the Professions tab first.")
		return
	end

	local settings = BarSettings()
	if key == "list" then
		for _, k in ipairs(BAR_KEYS) do
			local c = settings[k] or {}
			print(string.format("%s: scale %s, pos %s %s, font %s, name %s", k, tostring(c.scale or 1),
				tostring(c.x or "default"), tostring(c.y or ""), tostring(c.fontSize or "default"),
				c.showName == false and "off" or "on"))
		end
		return
	end

	local card = BarCards(o)[key]
	if not card then
		print("Journal: unknown bar '" .. key .. "'. " .. HELP)
		return
	end

	if cmd == "reset" then
		settings[key] = nil
		ApplyBarLayout(card, BAR_DEFAULTS[key])
		return
	end

	local cfg = settings[key] or {}
	if cmd == "scale" then
		local n = tonumber(words[3])
		if not n or n <= 0 then
			print("Journal: scale needs a number above 0.")
			return
		end
		cfg.scale = n
	elseif cmd == "font" then
		local n = tonumber(words[3])
		if not n or n <= 0 then
			print("Journal: font needs a size above 0.")
			return
		end
		cfg.fontSize = n
	elseif cmd == "name" then
		if words[3] == "on" then
			cfg.showName = true
		elseif words[3] == "off" then
			cfg.showName = false
		else
			print("Journal: name needs on or off.")
			return
		end
	elseif cmd == "pos" then
		local x, y = tonumber(words[3]), tonumber(words[4])
		if not x or not y then
			print("Journal: pos needs two numbers, x and y.")
			return
		end
		cfg.x, cfg.y = x, y
	else
		print("Journal: " .. HELP)
		return
	end

	settings[key] = cfg
	ApplyBarLayout(card, cfg)
end
end

SLASH_JPROF1 = "/jprof"
SlashCmdList.JPROF = function(msg)
	-- The macro body is "/jprof <skillLine>": the profession itself, not a slot.
	local skillLine = tonumber((msg or ""):match("^%s*(%d+)%s*$"))
	if not skillLine then
		AJ:Print("This profession macro is out of date. Drag the profession again to rebuild it.")
		return
	end
	if Section.frame and Section.frame:IsShown() and Section.view == "crafting" and Section.craftSkillLine == skillLine then
		Section.frame:Hide()   -- the same macro again closes the page
		return
	end
	UI:Open("professions")
	for _, tab in ipairs(Section.professionTabs or {}) do
		if tab.skillLine == skillLine and tab:IsShown() then
			Section:OpenCrafting(tab)
			return
		end
	end
	AJ:Print("This profession is not on this character.")
end