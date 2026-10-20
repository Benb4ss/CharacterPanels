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


local ICON = "Interface\\ICONS\\INV_SideTab_Professions_c60"
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
		body = "/jprof " .. row.key
	end
	local icon = (row.spellID and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(row.spellID)) or "INV_Misc_QuestionMark"
	local index = GetMacroIndexByName(name)
	if index == 0 then
		local _, numPerChar = GetNumMacros()
		if numPerChar >= (MAX_CHARACTER_MACROS or 138) then AJ:Print("No free character macro slot."); return end
		index = CreateMacro(name, icon, body, true)
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
			row.icon:Set(info.iconID)
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
local gameProfessionsSaved = nil

local function MakeGameProfessionsInert(f)
	if not gameProfessionsSaved then
		gameProfessionsSaved = { alpha = f:GetAlpha(), strata = f:GetFrameStrata() }
	end
	f:SetAlpha(0)
	f:SetFrameStrata("BACKGROUND")
end

local function RestoreGameProfessions()
	local f = ProfessionsFrame
	if not f or not gameProfessionsSaved then return end
	f:SetAlpha(gameProfessionsSaved.alpha or 1)
	f:SetFrameStrata(gameProfessionsSaved.strata or "HIGH")
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
	section.crafting = AJ.Crafting.Build(frame, craftLeft, craftRight)

	-- The overview, built at its own width.
	frame:SetWidth(overviewWidth)
	return frame, C.CreatePage(frame)
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
local Section = existingSection or UI:NewSection("professions", { label = "Professions", icon = ICON, order = 10 })

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
	frame:HookScript("OnHide", function()
		selfOpenUntil = 0
		suppressGameProfessions = false
		if ProfessionsFrame then
			RestoreGameProfessions()
			if ProfessionsFrame:IsShown() then ProfessionsFrame:Hide() end
		end
	end)
	InstallGameHooks()
	self.overview = BuildOverview(page)
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

-- Shows the overview page and selects its tab.
function Section:ShowOverview()
	self.view = "overview"
	self.frame:SetWidth(UI.Layouts.single.width)
	self.craftBook:Hide()
	self.overview.container:Show()
	self.crafting:Hide()
	self.overviewTab.selected:Show()
	for _, tab in ipairs(self.professionTabs) do
		tab.selected:Hide()
	end
end

-- Shows a profession's crafting page and selects its tab.
function Section:OpenCrafting(tab, skipOpen)
	if not tab or not tab:IsShown() then return end
	-- Make the game's trade skill this profession, so the crafting page reads it.
	if not skipOpen and tab.skillLine and C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill then
	    if InCombatLockdown() then
			AJ:Print("Professions cannot be switched in combat.")
			return
		end
		suppressGameProfessions = true
		selfOpenUntil = GetTime() + 1
		
		local ok, err = pcall(C_TradeSkillUI.OpenTradeSkill, tab.skillLine)
		if not ok then AJ:Print("could not open " .. tostring(tab.professionName) .. ": " .. tostring(err)) end
	end
	self.view = "crafting"
	self.craftSkillLine = tab.skillLine
	self.overview.container:Hide()
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
	local o = self.overview
	if not o then return end
	self.signature = ProfessionSignature()

	local prim1, prim2, cook, fish, faid = ProfessionIndexes()

	local primaryMissing = "Visit a profession trainer in a major city to learn a new profession."
	SetCard(o.primary[1], prim1, H.L("PROFESSIONS_FIRST_PROFESSION", "First Profession"), primaryMissing)
	SetCard(o.primary[2], prim2, H.L("PROFESSIONS_SECOND_PROFESSION", "Second Profession"), primaryMissing)

	SetCard(o.secondary[1], cook, H.L("PROFESSIONS_COOKING", "Cooking"),
		H.L("PROFESSIONS_COOKING_MISSING", "Visit a trainer to learn cooking."))
	SetCard(o.secondary[2], fish, H.L("PROFESSIONS_FISHING", "Fishing"),
		H.L("PROFESSIONS_FISHING_MISSING", "Visit a trainer to learn fishing."))
	SetCard(o.secondary[3], faid, H.L("PROFESSIONS_FIRST_AID", "First Aid"),
		H.L("PROFESSIONS_FIRST_AID_MISSING", "Visit a trainer to learn first aid."))

	ApplyBarLayouts(o)

	-- Profession tabs: one per profession the character has, in the order above.
	local slot = 0
	local indexes = { prim1, prim2, cook, fish, faid }
	for i = 1, 5 do
		local index = indexes[i]
		if index then
			slot = slot + 1
			local tab = self.professionTabs[slot]
			local name, texture, _, _, _, _, skillLine = GetProfessionInfo(index)
			tab.professionName = name
			tab.skillLine = skillLine
			tab.icon:SetTexture(texture)
			tab.tipText = name
			tab:ClearAllPoints()
			tab:SetPoint("TOPLEFT", self.frame, "TOPRIGHT", TAB_X, TAB_TOP - slot * TAB_STEP)
			tab:Show()
		end
	end
	for i = slot + 1, #self.professionTabs do
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
	local key = ((msg or ""):upper():gsub("%s", ""))
	local function CardFor(o)
		if not o then return nil end
		if key == "P1" then return o.primary[1] end
		if key == "P2" then return o.primary[2] end
		if key:match("^S[1-3]$") then return o.secondary[tonumber(key:sub(2))] end
	end
	local card = CardFor(Section.overview)
	if card and card.skillLine and Section.frame and Section.frame:IsShown()
		and Section.view == "crafting" and Section.craftSkillLine == card.skillLine then
		Section.frame:Hide()   -- the same macro again closes the page
		return
	end
	UI:Open("professions")
	card = CardFor(Section.overview)
	if not card or not card.skillLine then return end
	for _, tab in ipairs(Section.professionTabs or {}) do
		if tab.skillLine == card.skillLine and tab:IsShown() then
			Section:OpenCrafting(tab)
			return
		end
	end
end
