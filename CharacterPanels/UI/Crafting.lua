local _, AJ = ...

-- The crafting page of the Professions tab: the recipe list on the left page,
-- the schematic on the right page. Built for the singleRight layout (Layouts.lua).
--
-- Data comes from C_TradeSkillUI and C_Item (see the data section). Values
-- marked EST are estimates; check them in game.
--
-- Use: local view = AJ.Crafting.Build(frame, leftPage, rightPage)
--   view.Show(), view.Hide(), view.Select(recipeID), view.Refresh()

local UI = AJ.UI
local W = UI.Widgets

local Crafting = {}
AJ.Crafting = Crafting

-- ---------------------------------------------------------------- settings
local PAD = 14                  -- EST: inset from a page's edges
local TOP = 20                  -- EST: first line below the page top
local BOTTOM = 40               -- EST: room kept at the bottom of the left page
local SEARCH_H = 22             -- EST: search box and Filter button height
local HEADER_H = 24             -- EST: category header row
local ROW_H = 20                -- EST: recipe row
local ICON_SIZE = 40            -- EST: schematic icon
local REAGENT_SLOT = 40         -- EST: reagent slot
local REAGENT_H = 46            -- EST: one reagent row
local MAX_REAGENTS = 8          -- rows made up front; unused rows are hidden

local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local GOLD = { 1, 0.82, 0 }

-- The left page's panel (the recipe list): our background and border behind it,
-- placed by hand with these tables, not by the shared panel insets. Values in
-- pixels, placed as BOX_BORDER places the schematic box below: positive moves an
-- edge inwards, negative outwards. left / right: from the page's left / right edge.
-- top: from the page top. bottom: from the page bottom.
-- corner: the ornate corners' size; nil keeps the border's default.
local LIST_BG = { left = 16, right = 16, top = 12, bottom = 21 }
local LIST_BORDER = { left = 10, right = 12, top = 7, bottom = 19, corner = nil }

-- The skill-up mark, as Blizzard's list reads it (Blizzard_ProfessionsRecipeList.lua):
-- the icon and the count's colour by the recipe's difficulty, the hover text per
-- difficulty. Shown only when the recipe can give skill-ups.
local SKILLUP_ICONS = {
    [Enum.TradeskillRelativeDifficulty.Easy] = "Professions-Icon-Skill-Low",
    [Enum.TradeskillRelativeDifficulty.Medium] = "Professions-Icon-Skill-Medium",
    [Enum.TradeskillRelativeDifficulty.Optimal] = "Professions-Icon-Skill-High",
}
local SKILLUP_COLORS = {
    [Enum.TradeskillRelativeDifficulty.Easy] = EASY_DIFFICULTY_COLOR,
    [Enum.TradeskillRelativeDifficulty.Medium] = FAIR_DIFFICULTY_COLOR,
    [Enum.TradeskillRelativeDifficulty.Optimal] = DIFFICULT_DIFFICULTY_COLOR,
}
local SKILLUP_TEXTS = {
    [Enum.TradeskillRelativeDifficulty.Easy] = "PROFESSIONS_SKILL_UP_EASY",
    [Enum.TradeskillRelativeDifficulty.Medium] = "PROFESSIONS_SKILL_UP_MEDIUM",
    [Enum.TradeskillRelativeDifficulty.Optimal] = "PROFESSIONS_SKILL_UP_OPTIMAL",
}
local function SkillUpTooltipText(difficulty, num)
    -- The strings are Blizzard_Professions' own, so they are read at call time, not load time.
    return (_G[SKILLUP_TEXTS[difficulty]] or "%d skill-ups"):format(num)
end

-- Source: MuteSoundFile (warcraft.wiki.gg). File IDs supplied by Benji, verified in-game by ear.
-- Mutes are session-only and global; they apply to all sources of these files.
local PROFESSIONS_MUTED_SOUND_FILES = {
    567507, -- ucharactersheetopen.ogg
    567433, -- ucharactersheetclose.ogg
}

for _, fileID in ipairs(PROFESSIONS_MUTED_SOUND_FILES) do
    MuteSoundFile(fileID)
end




-- ---------------------------------------------------------------- data
-- Real data, as the probe confirmed it. Shows the recipes the character has
-- learned in the profession open in Blizzard's window; with no profession
-- open there is no list.

-- Calls an API by its path (e.g. "C_Item.GetItemNameByID") and returns its
-- first result, or nil if the function is missing or fails.
local function CallApi(path, ...)
	local fn = _G
	for part in path:gmatch("[^.]+") do
		if type(fn) ~= "table" then return nil end
		fn = fn[part]
	end
	if type(fn) ~= "function" then return nil end
	local ok, result = pcall(fn, ...)
	if ok then return result end
	return nil
end

local Data = {}
Crafting.Data = Data

-- One recipe: { name, icon, favorite, learned }. No makeable count yet: the
-- API for it has not been checked.
function Data.Recipe(id)
	local info = CallApi("C_TradeSkillUI.GetRecipeInfo", id)
	if type(info) ~= "table" then return nil end
	return {
		name = info.name or "?",
		icon = info.icon,
		favorite = info.favorite == true,
		learned = info.learned == true,
		enchanting = info.isEnchantingRecipe == true,   -- needs an item chosen
		salvage = info.isSalvageRecipe == true,         -- needs an item chosen
		skillUp = info.canSkillUp == true,
        numSkillUps = info.numSkillUps or 0,
        difficulty = info.relativeDifficulty,
	}
end

-- The learned recipes, grouped by category, in the game's category order:
-- { { name, order, recipes = { id, ... } }, ... }
function Data.Categories()
	local ids = CallApi("C_TradeSkillUI.GetFilteredRecipeIDs") or CallApi("C_TradeSkillUI.GetAllRecipeIDs") or {}
	local byCategory, categoryOrder, names, favorites = {}, {}, {}, {}
	for _, id in ipairs(ids) do
		local info = CallApi("C_TradeSkillUI.GetRecipeInfo", id)
		if type(info) == "table" and info.learned and not info.isDummyRecipe then
			local cat = info.categoryID or 0
			if not byCategory[cat] then
				byCategory[cat] = {}
				categoryOrder[#categoryOrder + 1] = cat
			end
			table.insert(byCategory[cat], id)
			names[id] = info.name or ""
			if info.favorite then favorites[#favorites + 1] = id end
		end
	end

	local result = {}
	for _, cat in ipairs(categoryOrder) do
		local catInfo = CallApi("C_TradeSkillUI.GetCategoryInfo", cat)
		local list = byCategory[cat]
		table.sort(list, function(a, b) return names[a] < names[b] end)
		result[#result + 1] = {
			name = (type(catInfo) == "table" and catInfo.name) or "Other",
			order = (type(catInfo) == "table" and catInfo.uiOrder) or 0,
			recipes = list,
		}
	end
	-- The Favorites section at the top, as Blizzard's list has it. A favourite also
	-- stays in its own category.
	if #favorites > 0 then
		table.sort(favorites, function(a, b) return names[a] < names[b] end)
		table.insert(result, { name = _G.PROFESSIONS_CATEGORY_FAVORITE or "Favorites", order = 0, recipes = favorites })
	end

	table.sort(result, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return a.name < b.name
	end)
	return result
end

-- The reagents of a recipe: the first reagent of each slot.
-- { itemID, name (nil until the item has loaded), icon, perCraft, owned }
function Data.Reagents(id)
	local out = {}
	local schematic = CallApi("C_TradeSkillUI.GetRecipeSchematic", id, false)
	if type(schematic) ~= "table" or type(schematic.reagentSlotSchematics) ~= "table" then
		return out
	end
	for _, slot in ipairs(schematic.reagentSlotSchematics) do
		local reagent = slot.reagents and slot.reagents[1]
		local itemID = reagent and reagent.itemID
		if itemID then
			local name = CallApi("C_Item.GetItemNameByID", itemID)
			if not name then CallApi("C_Item.RequestLoadItemDataByID", itemID) end
			out[#out + 1] = {
				itemID = itemID,
				name = name,
				icon = CallApi("C_Item.GetItemIconByID", itemID),
				perCraft = slot.quantityRequired or 1,
				owned = CallApi("C_Item.GetItemCount", itemID),   -- nil if the call fails; shown as "?"
			}
		end
	end
	return out
end

-- How many crafts the bags can cover: the game's own count, the same call
-- Blizzard's recipe list uses. nil if the call fails.
function Data.MakeableCount(id)
	local count = CallApi("C_TradeSkillUI.GetCraftableCount", id)
	return type(count) == "number" and count or nil
end

-- Whether the recipe is tracked (read only).
function Data.IsTracked(id)
	return CallApi("C_TradeSkillUI.IsRecipeTracked", id, false) == true
end

-- ---------------------------------------------------------------- list (left page)
-- The search box filters the rows. The rows are rebuilt each time the page
-- opens and each time the search text changes.
local function BuildList(left, onPick)
	local root = CreateFrame("Frame", nil, left)
	root:SetAllPoints(left)

	-- The left page's panel: the Journal's own dark background and ornate border,
	-- with the filigree ornament on top, as the character pane and the professions
	-- overview have them (Character.lua, Professions.lua). Both are placed by hand
	-- from the LIST_BG and LIST_BORDER tables at the top of the file, in the same
	-- way BOX_BORDER places the schematic box below.
	local H = AJ.Helpers
	local bg = H.Atlas(root, "UI-Character-Info-General-BG", "BACKGROUND", -8)
	bg:ClearAllPoints()
	bg:SetPoint("TOPLEFT", root, "TOPLEFT", LIST_BG.left, -LIST_BG.top)
	bg:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -LIST_BG.right, LIST_BG.bottom)
	local listBorder = H.FrameBorder(root, "common-insideframe", "border", "BORDER", LIST_BORDER.corner)
	listBorder:ClearAllPoints()
	listBorder:SetPoint("TOPLEFT", root, "TOPLEFT", LIST_BORDER.left, -LIST_BORDER.top)
	listBorder:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -LIST_BORDER.right, LIST_BORDER.bottom)
	H.FrameTopDetail(root, listBorder)

		local list = { root = root, rows = {}, needle = "", collapsed = {}, selectedID = nil }
	local made = {}   -- frames from the last rebuild; hidden before the next one

	local search = CreateFrame("EditBox", nil, root, "SearchBoxTemplate")
	search:SetSize(160, SEARCH_H)
	search:SetPoint("TOPLEFT", PAD+10, -TOP)
	search:SetAutoFocus(false)
	-- HookScript, so the template's own search hint keeps working.
	search:HookScript("OnTextChanged", function(self)
		list.needle = (self:GetText() or ""):lower()
		list.Rebuild()
	end)

	local filter = CreateFrame("Button", nil, root, "SharedButtonSmallTemplate")
	filter:SetSize(68, SEARCH_H)
	filter:SetPoint("LEFT", search, "RIGHT", 6, 0)

	filter:SetText("Filter")

	local icon = filter:CreateTexture(nil, "ARTWORK")
	if C_Texture.GetAtlasInfo("common-dropdown-icon-next") then
		icon:SetAtlas("common-dropdown-icon-next")
		icon:SetSize(14, 14)
	end
	icon:SetPoint("LEFT", filter:GetFontString(), "RIGHT", 0, 0)


	-- Filter menu: the same checkboxes, getters and setters as Blizzard's filter menu
	-- (Blizzard_Professions.lua: InitSkillUpFilter, InitMakeableFilter). The game keeps
	-- these settings, so Blizzard's own window shows them too.
	local function AddFilter(root, label, getter, setter)
		root:CreateCheckbox(label, function() return CallApi(getter) == true end, function()
			CallApi(setter, not (CallApi(getter) == true))
			list.Rebuild()
		end)
	end
	filter:SetScript("OnClick", function(self)
		MenuUtil.CreateContextMenu(self, function(_, root)
			AddFilter(root, _G.TRADESKILL_FILTER_HAS_SKILL_UP or "Has skill-up",
				"C_TradeSkillUI.GetOnlyShowSkillUpRecipes", "C_TradeSkillUI.SetOnlyShowSkillUpRecipes")
			AddFilter(root, _G.CRAFT_IS_MAKEABLE or "Makeable",
				"C_TradeSkillUI.GetOnlyShowMakeableRecipes", "C_TradeSkillUI.SetOnlyShowMakeableRecipes")
			-- Inventory slots: a submenu with check all, uncheck all and one checkbox per slot,
			-- built as Blizzard's InitSlotsFilter builds it (same calls, same arguments).
			local slots = root:CreateButton(_G.TRADESKILL_FILTER_SLOTS or "Slots")
			local function SetAllSlots(filtered)
				for i = 1, (CallApi("C_TradeSkillUI.GetAllFilterableInventorySlotsCount") or 0) do
					CallApi("C_TradeSkillUI.SetInventorySlotFilter", i, filtered)
				end
				list.Rebuild()
			end
			slots:CreateButton(_G.CHECK_ALL or "Check all", function() SetAllSlots(true) end)
			slots:CreateButton(_G.UNCHECK_ALL or "Uncheck all", function() SetAllSlots(false) end)
			for index = 1, (CallApi("C_TradeSkillUI.GetAllFilterableInventorySlotsCount") or 0) do
				local name = CallApi("C_TradeSkillUI.GetFilterableInventorySlotName", index) or ("Slot " .. index)
				slots:CreateCheckbox(name, function()
					return CallApi("C_TradeSkillUI.IsInventorySlotFiltered", index) ~= true
				end, function()
					-- Blizzard's SetSlotChecked passes the current filtered state; mirrored here.
					CallApi("C_TradeSkillUI.SetInventorySlotFilter", index, CallApi("C_TradeSkillUI.IsInventorySlotFiltered", index) == true)
					list.Rebuild()
				end)
			end
		end)
	end)

	-- The list scrolls, with Blizzard's minimal scroll bar (as Blizzard's crafting page and
	-- Widgets.lua's scroll lists have it).
	local scroll = CreateFrame("ScrollFrame", nil, root)
	scroll:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -8)
	scroll:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -PAD - 14, BOTTOM)
	local bar = CreateFrame("EventFrame", nil, scroll, "MinimalScrollBar")
	bar:SetHideIfUnscrollable(true)
	bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, -4)
	bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 4)
	ScrollUtil.InitScrollFrameWithScrollBar(scroll, bar)
	local content = CreateFrame("Frame", nil, scroll)
	scroll:SetScrollChild(content)
	scroll:HookScript("OnSizeChanged", function(_, width) content:SetWidth(width) end)
	
	-- Shown when no recipe is listed: none learned, or none that matches the search and filters.
	local empty = root:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	empty:SetPoint("TOPLEFT", scroll, "TOPLEFT", 10, -10)
	empty:SetPoint("RIGHT", scroll, "RIGHT", -10, 0)
	empty:SetJustifyH("CENTER")
	empty:SetWordWrap(true)
	empty:SetText("You haven't learned any recipe yet.\n Or there are no results with your current filters.")
	empty:Hide()
	list.empty = empty

	function list.Rebuild()
		for _, f in ipairs(made) do f:Hide() end
		made = {}
		list.rows = {}
		local anyMatch = false

		local y = 0
		for _, category in ipairs(Data.Categories()) do
			local matches = {}
			for _, id in ipairs(category.recipes) do
				local recipe = Data.Recipe(id)
				local recipeName = recipe and recipe.name or ""
				if list.needle == "" or recipeName:lower():find(list.needle, 1, true) then
					matches[#matches + 1] = id
				end
			end

			if #matches > 0 then
				anyMatch = true

				local collapsed = list.collapsed[category.name] == true

				-- Source: ListTemplates.xml (ListHeaderVisualTemplate: arrow and header art, title
				-- font), ListTemplates.lua (ListHeaderMixin), Blizzard_ProfessionsRecipeList.xml
				-- (category template, lines 122-132) and .lua (category OnClick order).
				-- GUESS: CreateFrame applies the template's mixin (ListHeaderVisualMixin). Not checked in game.
				local header = CreateFrame("Button", nil, content, "ListHeaderVisualTemplate")
				header:SetHeight(HEADER_H)
				header:SetPoint("TOPLEFT", 0, y)
				header:SetPoint("TOPRIGHT", 0, y)
								-- The visual template has only the visual methods. ListHeaderMixin's methods
				-- (CheckUpdateTooltip, OnEnter, OnLeave) are copied onto this frame, as Mixin does.
				-- Blizzard's category gets them from CreateFromMixins (Blizzard_ProfessionsRecipeList.lua, line 178).
				for key, fn in pairs(ListHeaderMixin) do
					if header[key] == nil then header[key] = fn end
				end
				made[#made + 1] = header

				-- ListHeaderMixin's methods, called directly: this frame is not built from that mixin.
				ListHeaderMixin.OnLoad(header)
				header:SetHeaderText(category.name)
				-- Our gold title for both states. Blizzard uses its own font colours here.
				local gold = { GetRGB = function() return GOLD[1], GOLD[2], GOLD[3] end }
				header:SetTitleColor(false, gold)
				header:SetTitleColor(true, gold)
				ListHeaderMixin.UpdateCollapsedState(header, collapsed)

				header:SetScript("OnEnter", ListHeaderMixin.OnEnter)
				header:SetScript("OnLeave", ListHeaderMixin.OnLeave)
				-- Same order as Blizzard's category OnClick: the header's click, then the toggle.
				-- The second argument of ListHeaderMixin.OnClick is the mouse button name.
				header:SetScript("OnClick", function(self, button)
					ListHeaderMixin.OnClick(self, button)
					list.collapsed[category.name] = not collapsed
					list.Rebuild()
				end)

				W.AddRule(header, 0, 0, -HEADER_H + 1)
				y = y - HEADER_H - 2

				for _, id in ipairs(collapsed and {} or matches) do
					local recipe = Data.Recipe(id) or { name = "?" }
					local makeable = Data.MakeableCount(id)

					local row = CreateFrame("Button", nil, content)
					made[#made + 1] = row
					row.id = id
					row:SetHeight(ROW_H)
					row:SetPoint("TOPLEFT", -16, y)
					row:SetPoint("TOPRIGHT", 0, y)

				-- Blizzard's SelectedOverlay (Blizzard_ProfessionsRecipeList.xml, ProfessionsRecipeListRecipeTemplate):
				-- atlas at its own size, centred with offset (0, -1), OVERLAY sub-level 2, hidden until selected.
				-- GUESS: the 4th argument of CreateTexture (sub-level) is not confirmed by the uploaded files.
				row.selected = row:CreateTexture(nil, "OVERLAY", nil, 2)
				row.selected:SetAtlas("Professions_Recipe_Active", TextureKitConstants.UseAtlasSize)
				row.selected:SetPoint("LEFT", row, "LEFT", 16, -1)
				row.selected:SetPoint("RIGHT", row, "RIGHT", 2, -1)
				row.selected:SetHeight(ROW_H)
							row.selected:SetShown(row.id == list.selectedID)

					-- The skill-up mark, as Blizzard's list has it: shown only when the recipe
					-- can give skill-ups; the icon follows the difficulty, the count sits left
					-- of it in the difficulty's colour, the hover text names the number.
					row.mark = row:CreateTexture(nil, "ARTWORK")
					row.mark:SetSize(12, 12)
					row.mark:SetPoint("LEFT", 18, 0)   -- EST: room for the count left of the icon
					row.ups = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
					row.ups:SetPoint("RIGHT", row.mark, "LEFT", -2, 0)

local skillAtlas = recipe.skillUp and SKILLUP_ICONS[recipe.difficulty]
					if skillAtlas and C_Texture.GetAtlasInfo(skillAtlas) then
						row.mark:SetAtlas(skillAtlas)
						row.mark:Show()
						-- Several points and the optimal difficulty show the count, as Blizzard
						-- shows it; otherwise only the icon and the hover text.
						local optimal = recipe.difficulty == Enum.TradeskillRelativeDifficulty.Optimal
						row.ups:SetShown(recipe.numSkillUps > 1 and optimal)
						row.ups:SetText(recipe.numSkillUps)
						local color = SKILLUP_COLORS[recipe.difficulty]
						if color then row.ups:SetVertexColor(color:GetRGB()) end

						-- Create a dedicated hover button specifically for the skill-up icon/count area
						if not row.skillButton then
							row.skillButton = CreateFrame("Button", nil, row)
							row.skillButton:SetSize(28, ROW_H)
							row.skillButton:SetPoint("LEFT", row, "LEFT", 12, 0)
						end
						row.skillButton:SetScript("OnEnter", function(self)
							GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
							GameTooltip:SetText(SkillUpTooltipText(recipe.difficulty, recipe.numSkillUps))
							GameTooltip:Show()
						end)
						row.skillButton:SetScript("OnLeave", GameTooltip_Hide)
						row.skillButton:Show()
					else
						row.mark:Hide()
						row.ups:Hide()
						if row.skillButton then
							row.skillButton:Hide()
						end
					end
					
local function SafeMeasure(func)
    local success, result = pcall(func)
    if success then
        return result
    end
    return nil
end

-- UTF-8 safe first character removal to prevent splitting multibyte characters
local function TrimFirstChar(str)
    local len = #str
    if len == 0 then return "" end
    local pos = 2
    while pos <= len do
        local c = str:byte(pos)
        if c < 128 or c >= 192 then
            break
        end
        pos = pos + 1
    end
    return str:sub(pos)
end

-- Standalone measurement frame (hidden from the Blizzard frame tree)
local measureFrame = CreateFrame("Frame")
measureFrame:Hide()

local measureText = measureFrame:CreateFontString(
    nil,
    "OVERLAY",
    "GameFontHighlight"
)

local function MeasureText(text)
    return SafeMeasure(function()
        measureText:SetText(text)
        return measureText:GetStringWidth()
    end)
end

local function FitRecipeText(row, recipe, makeable)
    -- Construct the full target string
    local fullText = makeable and ("%s [%d]"):format(recipe.name, makeable) or recipe.name

    -- Calculate maxWidth based on the row's width minus left offsets and right padding
    local maxWidth = SafeMeasure(function()
        local markWidth = row.mark and row.mark:GetWidth() or 0
        return row:GetWidth() - (markWidth + 22)
    end)

    if maxWidth and maxWidth > 0 then
        row.text.lastGoodWidth = maxWidth
    else
        maxWidth = row.text.lastGoodWidth or 200
    end

    local textWidth = MeasureText(fullText)

    if not maxWidth or not textWidth then
        -- Fallback if measurement is unavailable
        local fit = row.text.fits and row.text.fits[fullText]
        row.text:SetText(fit or fullText)
        return
    end

    if fullText == row.text.lastName and maxWidth == row.text.lastWidth then
        return
    end

    row.text.lastName = fullText
    row.text.lastWidth = maxWidth
    row.text.fits = row.text.fits or {}

    local fitted = fullText

    if maxWidth > 0 and textWidth > maxWidth then
        -- Trim from the left of the recipe name while preserving the makeable count suffix
        local namePart = recipe.name
        local suffix = makeable and (" [%d]"):format(makeable) or ""

        while #namePart > 0 do
            namePart = TrimFirstChar(namePart)
            fitted = "..." .. namePart .. suffix

            local width = MeasureText(fitted)
            if not width then
                fitted = row.text.fits[fullText] or fullText
                break
            end

            if width <= maxWidth then
                break
            end
        end
    end

    row.text:SetText(fitted)
    row.text.fits[fullText] = fitted

    -- Keep the fit cache bounded
    local count = 0
    for _ in pairs(row.text.fits) do
        count = count + 1
    end

    if count > 50 then
        wipe(row.text.fits)
        row.text.fits[fullText] = fitted
    end
end
-- When creating the row:
row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
row.text:SetPoint("LEFT", row.mark, "RIGHT", 6, 0)
-- Optional: If you want right alignment anchoring support, ensure right constraint is handled or let FitRecipeText handle truncation.

-- When updating the row with recipe data:
FitRecipeText(row, recipe, makeable)

					    -- Blizzard's HighlightOverlay (Blizzard_ProfessionsRecipeList.xml, ProfessionsRecipeListRecipeTemplate):
    -- atlas at its own size, centred with offset (0, -1), HIGHLIGHT layer, alpha 0.5.
    -- Shown only while the row is not selected (Blizzard's SetSelected).
    row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.highlight:SetAtlas("Professions_Recipe_Hover", TextureKitConstants.UseAtlasSize)
    row.highlight:SetPoint("LEFT", row, "LEFT", 16, -1)
    row.highlight:SetPoint("RIGHT", row, "RIGHT", 24, -1)
    row.highlight:SetHeight(ROW_H)
    row.highlight:SetAlpha(0.5)
    			row.highlight:SetShown(row.id ~= list.selectedID)
					
					row:SetScript("OnClick", function() onPick(id) end)

					list.rows[#list.rows + 1] = row
					y = y - ROW_H
				end
			end
		end
		list.empty:SetShown(not anyMatch)
		content:SetHeight(math.max(1, -y))
		bar:Update()
	end

	list.Rebuild()
	return list
end

-- --------------------------------- schematic (right page)
-- Blizzard's filigree ornament at the top centre of a border (from JournalHelpers.lua).
local TOP_DETAIL_ATLAS = "QuestLog-frame-filigree"

local function FrameTopDetail(host, border)
	local H = AJ.Helpers
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

-- Icon buttons have no text: their name shows as a tooltip on hover.
local function ShowIconTooltip(button, text)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(text)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
end

local function BuildSchematic(right)
	local root = CreateFrame("Frame", nil, right)
	root:SetAllPoints(right)

	local slot = W.CreateSlot(root, ICON_SIZE)
	slot:SetPoint("TOPLEFT", PAD, -TOP)

	local name = root:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	name:SetPoint("TOPLEFT", slot, "TOPRIGHT", 10, -4)
	name:SetPoint("RIGHT", root, "RIGHT", -PAD, 0)
	name:SetJustifyH("LEFT")

	local label = root:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("TOPLEFT", slot, "BOTTOMLEFT", 0, -18)
	label:SetText("Reagents:")
	label:SetTextColor(unpack(GOLD))

	local reagents = {}
	for i = 1, MAX_REAGENTS do
		local row = CreateFrame("Frame", nil, root)
		row:SetSize(300, REAGENT_SLOT)
		row:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -8 - (i - 1) * REAGENT_H)

		row.slot = W.CreateSlot(row, REAGENT_SLOT)
		row.slot:SetPoint("LEFT", 0, 0)

		row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.text:SetFont("Fonts\\ARIALN.TTF", 12, "")
		row.text:SetPoint("LEFT", row.slot, "RIGHT", 10, 0)

		row:Hide()
		reagents[i] = row
	end

	-- Bottom bar, from the right: Create, the quantity controls, then Create All on the left.
	local track = CreateFrame("CheckButton", nil, root, "UICheckButtonTemplate")
	track:SetSize(24, 24)

	-- The quests tab's own icon (QuestMapFrame.QuestsTab.Icon: "QuestLog-tab-icon-quest",
	-- 29x29). It has no off/checked pair, so off is the icon desaturated and dimmed,
	-- checked is the icon in color.
	local tabIcon = QuestMapFrame and QuestMapFrame.QuestsTab and QuestMapFrame.QuestsTab.Icon
	local trackAtlas = tabIcon and tabIcon:GetAtlas()
	if trackAtlas and C_Texture.GetAtlasInfo(trackAtlas) then
		track:SetNormalAtlas(trackAtlas)
		track:GetNormalTexture():SetSize(20, 20)
		track:GetNormalTexture():SetDesaturated(true)
		track:GetNormalTexture():SetAlpha(0.6)
		track:GetCheckedTexture():SetAtlas(trackAtlas)
		track:GetCheckedTexture():SetSize(20, 20)
	else
		track:SetNormalAtlas("auctionhouse-icon-favorite-off")
		track:GetCheckedTexture():SetAtlas("auctionhouse-icon-favorite")
	end
	-- The mouseover highlight: the quest bang (the gossip frame's available-quest
	-- exclamation mark, a file every client has) instead of the checkbox template's
	-- blue square, drawn as a glow over the icon.
	local hl = track:GetHighlightTexture()
	hl:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
	hl:SetBlendMode("ADD")
	hl:ClearAllPoints()
	hl:SetPoint("CENTER", track, "CENTER", 0, 0)
	hl:SetSize(20, 20)
	-- The template's pressed box (white square with a border) is removed too:
	-- pressed then looks the same as hover.
	local pushed = track:GetPushedTexture()
	if pushed then pushed:SetTexture(nil) end



	local enchantTarget = CreateFrame("Button", nil, root, "SharedButtonSmallTemplate")
	enchantTarget:SetSize(200, 22)
	enchantTarget:SetPoint("BOTTOMLEFT", PAD, 40)
	enchantTarget:Hide()

	local create = CreateFrame("Button", nil, root, "SharedButtonSmallTemplate")
	create:SetSize(100, 22)
	create:SetPoint("BOTTOMLEFT", 26, 28)
	create:SetText("Create")

	local createAll = CreateFrame("Button", nil, root, "SharedButtonSmallTemplate")
	createAll:SetSize(80, 22)
	createAll:SetPoint("BOTTOMRIGHT", -34, 28)

	local nextBtn = W.CreatePageArrowButton(root, "next")
	nextBtn:SetSize(22, 22)
	nextBtn:SetPoint("RIGHT", createAll, "LEFT", -8, 0)

	local qty = CreateFrame("EditBox", nil, root, "InputBoxTemplate")
	qty:SetSize(24, 16)
	qty:SetPoint("RIGHT", nextBtn, "LEFT", 0, 0)
	qty:SetAutoFocus(false)
	qty:SetNumeric(true)
	qty:SetMaxLetters(3)
	qty:SetText("1")

	local prevBtn = W.CreatePageArrowButton(root, "prev")
	prevBtn:SetSize(22, 22)
	prevBtn:SetPoint("RIGHT", qty, "LEFT", -6, 0)


	-- Step 1: our schematic pieces are replaced by Blizzard's form, so they stay hidden.
	for _, f in ipairs({ slot, name, label, track, enchantTarget }) do f:Hide() end
	for _, r in ipairs(reagents) do r:Hide() end

	-- Blizzard's schematic form on the right page, created as its Inspect Recipe window creates it.
	-- Its background and frame art are hidden, so our paper shows.
	C_AddOns.LoadAddOn("Blizzard_ProfessionsTemplates")
	local form = CreateFrame("Frame", nil, right, "ProfessionsRecipeSchematicFormTemplate")
	-- Panel size: from just under the page top to the bottom bar, as in the design.
	form:SetPoint("TOPLEFT", right, "TOPLEFT", 18, -12)
	form:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -26, 24)
	-- The form template does not create these; Blizzard's Inspect window adds them. We add
	-- the same pieces, hidden, so the form finds what it expects.
	if not form.Background then form.Background = form:CreateTexture(nil, "BACKGROUND") end
	if not form.MinimalBackground then form.MinimalBackground = form:CreateTexture(nil, "BACKGROUND") end
	if not form.NineSlice then form.NineSlice = CreateFrame("Frame", nil, form, "NineSlicePanelTemplate") end
	-- The dark panel: Blizzard's crafting XML sets the form's NineSlice to InsetFrameTemplate.
	-- The form shows it when a recipe is set (its Init); NineSliceUtil builds the pieces.
	if NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
		NineSliceUtil.ApplyLayoutByName(form.NineSlice, "InsetFrameTemplate")
	end
	form.Background:SetAllPoints(form)
	form.MinimalBackground:Hide()
	form.NineSlice:Hide()
	form:Hide()
	-- Blizzard's own Track checkbox (with its text) stays hidden: we show our star toggle instead.
	hooksecurefunc(form.TrackRecipeCheckbox, "Show", function(self)
		self:Hide()
	end)
	form.TrackRecipeCheckbox:Hide()
	-- Blizzard's own Track checkbox (with its text) and favourite star are moved into a hidden
	-- holder, so nothing of them can show, however the game shows them.
	local blizzardHidden = CreateFrame("Frame")
	blizzardHidden:Hide()
	form.TrackRecipeCheckbox:SetParent(blizzardHidden)
	form.FavoriteButton:SetParent(blizzardHidden)
	-- Our own favourite star, placed by us inside the panel. Blizzard's star is moved by its layout,
	-- which differs with the way the page is opened, so it is hidden for good.
	form.FavoriteButton:Hide()
	hooksecurefunc(form.FavoriteButton, "Show", function(self) self:Hide() end)
	local favStar = CreateFrame("CheckButton", nil, form, "UICheckButtonTemplate")
	favStar:SetSize(24, 24)
	favStar:SetPoint("TOPRIGHT", form, "TOPRIGHT", -6, -50)
	-- The Track star sits right below the favourite star.
	track:SetPoint("TOP", favStar, "BOTTOM", 0, -6)
	
    -- The chat link button, under the Track star: posts the recipe list link, as
    -- Blizzard's LinkButton does (Blizzard_ProfessionsCrafting.lua). Same icon-only
    -- pattern as the favourite and Track stars: icon, glow on hover, no pressed box.
    local chatLink = CreateFrame("CheckButton", nil, form, "UICheckButtonTemplate")
    chatLink:SetSize(24, 24)
    chatLink:SetPoint("TOP", track, "BOTTOM", 0, -6)
    ShowIconTooltip(chatLink, _G.LINK_TRADESKILL_TOOLTIP or "Post your recipe list in chat.")
    chatLink:SetNormalAtlas("common-icon-chatlink")
    chatLink:GetCheckedTexture():SetAtlas("common-icon-chatlink")
    local chatHl = chatLink:GetHighlightTexture()
    chatHl:SetAtlas("common-icon-chatlink")
    chatHl:SetBlendMode("ADD")
    chatHl:ClearAllPoints()
    chatHl:SetPoint("CENTER", chatLink, "CENTER", 0, 0)
    chatHl:SetSize(20, 20)   -- EST
    local chatPushed = chatLink:GetPushedTexture()
    if chatPushed then chatPushed:SetTexture(nil) end
    chatLink:SetScript("OnClick", function(self)
        self:SetChecked(false)   -- momentary: it never stays checked
        local link = CallApi("C_TradeSkillUI.GetTradeSkillListLink")
        if not link then return end
        if MacroFrameText and MacroFrameText:IsShown() and MacroFrameText:HasFocus() then
            if strlenutf8(MacroFrameText:GetText()) + strlenutf8(link) <= MacroFrameText:GetMaxLetters() then
                MacroFrameText:Insert(link)
            end
        elseif ChatFrameUtil and ChatFrameUtil.GetActiveWindow() then
            ChatFrameUtil.InsertLink(link)
        else
            MenuUtil.CreateContextMenu(self, function(_, root)
                root:CreateTitle(_G.TRADESKILL_POST or "Post to")
                local function AddChannel(slashChannel, text, enabled)
                    local button = root:CreateButton(text, function()
                        ChatFrameUtil.OpenChat(("%s %s"):format(slashChannel, link), DEFAULT_CHAT_FRAME)
                    end)
                    button:SetEnabled(enabled)
                end
                AddChannel(SLASH_GUILD1 or "/guild", _G.GUILD or "Guild", IsInGuild())
                AddChannel(SLASH_PARTY1 or "/party", _G.PARTY or "Party", GetNumSubgroupMembers() > 0)
                AddChannel(SLASH_RAID1 or "/raid", _G.RAID or "Raid", IsInRaid())
                -- GetChannelList returns triples; the third value marks an unusable
                -- channel (Blizzard's own check, copied as it is).
                local channels = { GetChannelList() }
                for index = 1, #channels, 3 do
                    local slashChannel = "/" .. channels[index]
                    local text = ChatFrameUtil.ResolveChannelName(channels[index + 1])
                    AddChannel(slashChannel, text or channels[index], not channels[index + 2])
                end
            end)
        end
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end)
    chatLink:Hide()
	
	
	ShowIconTooltip(favStar, "Favourite")
	ShowIconTooltip(track, "Track Recipe")
	favStar:SetNormalAtlas("auctionhouse-icon-favorite-off")
	favStar:GetCheckedTexture():SetAtlas("auctionhouse-icon-favorite")
	-- Mouseover and press: the filled star as a glow over the icon instead of the checkbox
	-- template's blue highlight square, and the pressed white box is removed.
	local favHl = favStar:GetHighlightTexture()
	favHl:SetAtlas("auctionhouse-icon-favorite")
	favHl:SetBlendMode("ADD")
	favHl:ClearAllPoints()
	favHl:SetPoint("CENTER", favStar, "CENTER", 0, 0)
	favHl:SetSize(20, 20)
	local favPushed = favStar:GetPushedTexture()
	if favPushed then favPushed:SetTexture(nil) end
	favStar:SetScript("OnClick", function(self)
		if not self.recipeID then
			self:SetChecked(false)
			return
		end
		CallApi("C_TradeSkillUI.SetRecipeFavorite", self.recipeID, self:GetChecked() and true or false)
		self:SetChecked(CallApi("C_TradeSkillUI.IsRecipeFavorite", self.recipeID) == true)
	end)
	favStar:Hide()
	-- Our border around the schematic box: the same ornate border as the Journal's side panels
	-- (JournalHelpers.lua). Blizzard's own border pieces are hidden, so only ours shows; the dark
	-- centre of the panel stays.
	local H = AJ.Helpers
	local boxBorder = CreateFrame("Frame", nil, form)
	boxBorder:SetAllPoints(form)
	boxBorder:SetFrameLevel(form:GetFrameLevel() + 5)
	-- Box border tuning, in pixels. left / right: inwards from the box's left / right edge.
	-- top: down from the top edge (positive moves inwards). bottom: up from the bottom edge
	-- (positive moves inwards). corner: the size of the ornate corners.
	local BOX_BORDER = { left = -4, right = -4, top = -5, bottom = -5, corner = 106 }
	local boxTexture = H.FrameBorder(boxBorder, "common-insideframe", "border", "BORDER", BOX_BORDER.corner)
	boxTexture:ClearAllPoints()
	boxTexture:SetPoint("TOPLEFT", boxBorder, "TOPLEFT", BOX_BORDER.left, -BOX_BORDER.top)
	boxTexture:SetPoint("BOTTOMRIGHT", boxBorder, "BOTTOMRIGHT", -BOX_BORDER.right, BOX_BORDER.bottom)
	FrameTopDetail(boxBorder, boxTexture)
	for _, piece in ipairs({ "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner", "TopEdge", "BottomEdge", "LeftEdge", "RightEdge" }) do
		if form.NineSlice[piece] then form.NineSlice[piece]:Hide() end
	end
	-- Blizzard_ProfessionsRecipeSchematicFormOverride.lua is not loaded by our TOC, so its
	-- settings are copied onto this form as they are.
	function form:GetDescriptionWidth() return math.max(200, self:GetWidth() - 60) end
	function form:GetRequiredToolsTextLayout(_minimized) return 250, true end
		local function SizeReagentSlots(self)
		for slot in self.reagentSlotPool:EnumerateActive() do
			slot:SetWidth(160)
			slot:SetScale(1 / 1.2)
		end
	end
	hooksecurefunc(form, "Init", SizeReagentSlots)
	hooksecurefunc(form, "Refresh", SizeReagentSlots)
	function form:GetOutputItemMaxWidth() return math.max(100, self:GetWidth() - 80) end
	function form:ShouldAllowMultiline() return true end
	

	-- Blizzard's crafting page adjusts its form in OverrideArt (Blizzard_ProfessionsCrafting): the
	-- output icon is 53 px, and Track Recipe sits at the bottom right. Copied as it is.
	form.OutputIcon:SetSize(38, 38)
	form.OutputIcon.Icon:SetSize(48, 48)
	local function PositionOutputIcon()
		form.OutputIcon:ClearAllPoints()
		form.OutputIcon:SetPoint("TOPLEFT", 18, -22)
	end

	hooksecurefunc(form, "Init", PositionOutputIcon)
	hooksecurefunc(form, "Refresh", PositionOutputIcon)
	
	local formTrack = form.TrackRecipeCheckbox
	local textWidth = formTrack.Text:GetStringWidth()
	formTrack:ClearAllPoints()
	formTrack:SetPoint("BOTTOMRIGHT", -(textWidth + 20), 84)

	-- Empty state: our own dark panel with the same border as the schematic box.
	-- Shown when no recipe is selected.
	local emptyPanel = CreateFrame("Frame", nil, root)
	emptyPanel:SetPoint("TOPLEFT", right, "TOPLEFT", 18, -12)
	emptyPanel:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -26, 24)
	local emptyFill = emptyPanel:CreateTexture(nil, "BACKGROUND")
		emptyFill:SetAllPoints(emptyPanel)

	local emptyBorder = CreateFrame("Frame", nil, emptyPanel)
	emptyBorder:SetAllPoints(emptyPanel)
	emptyBorder:SetFrameLevel(emptyPanel:GetFrameLevel() + 5)
	local emptyTexture = H.FrameBorder(emptyBorder, "common-insideframe", "border", "BORDER", BOX_BORDER.corner)
	emptyTexture:ClearAllPoints()
	emptyTexture:SetPoint("TOPLEFT", emptyBorder, "TOPLEFT", BOX_BORDER.left, -BOX_BORDER.top)
	emptyTexture:SetPoint("BOTTOMRIGHT", emptyBorder, "BOTTOMRIGHT", -BOX_BORDER.right, BOX_BORDER.bottom)
	FrameTopDetail(emptyBorder, emptyTexture)
	emptyPanel:Hide()

	-- The progress bar above the book: Blizzard's rank bar, raised above the page art.
	local rankBar = CreateFrame("Frame", nil, root, "ProfessionsRankBarTemplate")
	rankBar:SetFrameStrata("HIGH")
	rankBar:SetScale(0.85)
	rankBar:SetPoint("BOTTOMRIGHT", right, "TOPRIGHT", 0, 22)
	

	return {
		rankBar = rankBar,
		form = form,
		root = root,
		slot = slot,
		name = name,
		reagents = reagents,
		track = track,
		favorite = favStar,
		enchantTarget = enchantTarget,
		create = create,
		createAll = createAll,
		qty = qty,
		prev = prevBtn,
		next = nextBtn,
		emptyPanel = emptyPanel,
		emptyFill = emptyFill,
		chatLink = chatLink,
	}
end

-- Fills the bottom bar and the form for a recipe. The form shows the recipe itself; the
-- form is initialised once per recipe and refreshed otherwise.
local function FillSchematic(s, id, resetQuantity)
	local recipe = Data.Recipe(id) or { name = "" }
	local makeable = Data.MakeableCount(id)
	local max = makeable or 0
	s.createAll:SetText(makeable and ("All [%d]"):format(makeable) or "All")
	-- The list link needs the game's own list, as Blizzard's Refresh gates it.
    s.chatLink:SetShown(CallApi("C_TradeSkillUI.CanTradeSkillListLink") == true)

	-- Blizzard's rule for the box: after a craft or a new recipe it starts at the remaining
	-- recasts + 1, between 1 and the craftable count.
	local start = resetQuantity and ((CallApi("C_TradeSkillUI.GetRemainingRecasts") or 0) + 1) or (tonumber(s.qty:GetText()) or 1)
	s.qty:SetText(tostring(math.max(1, math.min(start, max))))

	local active = max > 0
	-- Salvaging is not wired yet. An enchant target is chosen on the form.
	local canCreate = active and not recipe.salvage
	s.create:SetEnabled(canCreate)
	s.createAll:SetEnabled(canCreate)
	s.prev:SetEnabled(active)
	s.next:SetEnabled(active)
	if s.qty.SetEnabled then s.qty:SetEnabled(active) end
	if not active then s.qty:SetText("0") end

	-- An enchant makes one at a time, so it shows an Enchant button alone.
	local isEnchant = recipe.enchanting == true
	s.createAll:SetShown(not isEnchant)
	s.qty:SetShown(not isEnchant)
	s.prev:SetShown(not isEnchant)
	s.next:SetShown(not isEnchant)
	s.create:SetText(isEnchant and "Enchant" or "Create")
	local form = s.form
	if id == nil then
		s.formRecipe = nil
		form:Hide()
		s.emptyPanel:Show()
		s.track:Hide()
		s.create:Hide()
		s.createAll:Hide()
		s.qty:Hide()
		s.prev:Hide()
		s.next:Hide()
		return
	end
	s.emptyPanel:Hide()
	s.create:Show()
	if s.formRecipe ~= id then
		s.formRecipe = id
		local info = CallApi("C_TradeSkillUI.GetRecipeInfo", id)
		if type(info) == "table" then form:Init(info) end
	else
		form:Refresh()
	end
	form.TrackRecipeCheckbox:Hide()
	-- The favourite star moves 50 px left, inside the panel. Its anchor is kept; only x changes.
	form.FavoriteButton:Hide()
	s.favorite.recipeID = id
	s.favorite:SetShown(recipe.learned == true)
	s.favorite:SetChecked(CallApi("C_TradeSkillUI.IsRecipeFavorite", id) == true)
	s.track.recipeID = id
	s.track.tracked = Data.IsTracked(id)
	s.track:SetChecked(s.track.tracked)
	s.track:Show()
	-- The dark interior: the profession's background, as Blizzard's crafting page sets it.
	local professionInfo = CallApi("C_TradeSkillUI.GetProfessionInfoByRecipeID", id)
	if professionInfo and Professions and Professions.GetProfessionBackgroundAtlas then
		form.Background:SetAtlas(Professions.GetProfessionBackgroundAtlas(professionInfo), TextureKitConstants.IgnoreAtlasSize)
		form.Background:Show()
	end
	if professionInfo and s.rankBar then
		s.rankBar:Update(professionInfo)
	end
	form:Show()
end

-- ---------------------------------------------------------------- craft
-- Makes a transaction for a recipe with Blizzard's own transaction code. Returns nil,
-- with a chat message, if it cannot be made.
local function MakeTransaction(recipeID)
	if not CreateProfessionsRecipeTransaction then
		C_AddOns.LoadAddOn("Blizzard_ProfessionsTemplates")
	end
	if not CreateProfessionsRecipeTransaction then
		AJ:Print("could not craft: the transaction code is not loaded.")
		return nil
	end
	local schematic = CallApi("C_TradeSkillUI.GetRecipeSchematic", recipeID, false)
	if type(schematic) ~= "table" then
		AJ:Print("could not craft: no recipe data.")
		return nil
	end
	return CreateProfessionsRecipeTransaction(schematic)
end

-- The items an enchant can be applied to, as the game lists them for the recipe.
-- Returns Item objects, in the same way Blizzard's enchant flyout gets them.
local function EnchantCandidates(recipeID)
	local transaction = MakeTransaction(recipeID)
	if not transaction then return {} end
	local guids = CallApi("C_TradeSkillUI.GetEnchantItems", recipeID, transaction:CreateCraftingReagentInfoTbl()) or {}
	local items = {}
	for _, guid in ipairs(guids) do
		items[#items + 1] = Item:CreateFromItemGUID(guid)
	end
	return items
end

-- Crafts with the form's transaction, as Blizzard's CreateInternal does: an enchant target
-- set on the form makes an enchant; otherwise the plain recipe is crafted.
local function CraftRecipeNow(recipeID, count, transaction, recipeLevel)
	if not recipeID or not count or count < 1 or not transaction then return false end
	if transaction:GetEnchantAllocation() then
		transaction:CraftEnchant(recipeID, count)
	else
		transaction:CraftRecipe(recipeID, count, recipeLevel)
	end
	return true
end

-- Views that show item names and the game's state. They are redrawn when an item's data
-- arrives, when the bags change, and when a craft, cast, tracking or favourite changes.
local liveViews = {}
local itemEvents = CreateFrame("Frame")
itemEvents:SetScript("OnEvent", function(_, event, arg1, arg2)
	if event == "TRADE_SKILL_FAVORITES_CHANGED" then
		for _, v in ipairs(liveViews) do
			if v.frame:IsShown() then v.SetFavorite(arg2, arg1) end
		end
		return
	end
	if event == "TRACKED_RECIPE_UPDATE" then
		for _, v in ipairs(liveViews) do
			if v.frame:IsShown() then v.SetTracked(arg1, arg2) end
		end
		return
	end
	-- A finished craft, or a craft that was stopped, cancelled or interrupted, resets the
	-- box to the game's remaining recasts + 1, as Blizzard's page does (its Cleanup).
	local resetQuantity = false
	if event == "TRADE_SKILL_ITEM_CRAFTED_RESULT" then
		resetQuantity = true
	elseif event == "UPDATE_TRADESKILL_CAST_STOPPED" then
		resetQuantity = not arg1   -- arg1 is true for scrapping, which Blizzard leaves alone
	elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
		resetQuantity = arg1 == "player"
	end
	for _, v in ipairs(liveViews) do
		if v.frame:IsShown() then v.Refresh(resetQuantity) end
	end
end)
itemEvents:RegisterEvent("GET_ITEM_INFO_RECEIVED")
itemEvents:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
itemEvents:RegisterEvent("BAG_UPDATE_DELAYED")
itemEvents:RegisterEvent("TRADE_SKILL_ITEM_CRAFTED_RESULT")
itemEvents:RegisterEvent("UPDATE_TRADESKILL_CAST_STOPPED")
itemEvents:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
itemEvents:RegisterEvent("UNIT_SPELLCAST_FAILED")
itemEvents:RegisterEvent("TRACKED_RECIPE_UPDATE")
itemEvents:RegisterEvent("TRADE_SKILL_FAVORITES_CHANGED")

-- ---------------------------------------------------------------- view
-- frame: the window. left, right: the two pages of the singleRight layout.
function Crafting.Build(frame, left, right)
	local view = { frame = frame, selected = nil }
	local list
	local schematic = BuildSchematic(right)
	-- The empty panel uses the same background as a recipe's form: the profession's
	-- background atlas from Professions.GetProfessionBackgroundAtlas, as FillSchematic sets it.
	function view.SetProfession(skillLine)
		local info = skillLine and CallApi("C_TradeSkillUI.GetProfessionInfoBySkillLineID", skillLine)
		if type(info) == "table" and Professions and Professions.GetProfessionBackgroundAtlas then
			schematic.emptyFill:SetAtlas(Professions.GetProfessionBackgroundAtlas(info), TextureKitConstants.IgnoreAtlasSize)
		end
	end

	-- Quantity arrows.
	schematic.prev:SetScript("OnClick", function()
		schematic.qty:SetText(tostring(math.max(1, (tonumber(schematic.qty:GetText()) or 1) - 1)))
	end)
	schematic.next:SetScript("OnClick", function()
		local limit = Data.MakeableCount(view.selected) or 0
		schematic.qty:SetText(tostring(math.min(limit, (tonumber(schematic.qty:GetText()) or 1) + 1)))
	end)
	-- Track Recipe: sets the tracking, then shows the game's state.
	-- SetRecipeTracked(recipeID, tracked, isRecraft): the signature follows
	-- IsRecipeTracked; check it in game.
	schematic.track:SetScript("OnClick", function(self)
		if not self.recipeID then
			self:SetChecked(false)
			return
		end
		CallApi("C_TradeSkillUI.SetRecipeTracked", self.recipeID, self:GetChecked() and true or false, false)
		self.tracked = Data.IsTracked(self.recipeID)
		self:SetChecked(self.tracked)
	end)
	-- Favourite: sets the game's favourite, as Blizzard's favourite button does.
	schematic.favorite:SetScript("OnClick", function(self)
		if not self.recipeID then
			self:SetChecked(false)
			return
		end
		CallApi("C_TradeSkillUI.SetRecipeFavorite", self.recipeID, self:GetChecked() and true or false)
		self:SetChecked(CallApi("C_TradeSkillUI.IsRecipeFavorite", self.recipeID) == true)
	end)

	-- Create and Create All craft with the form's transaction, so the target and reagent
	-- choices on the form are the ones used.
	schematic.create:SetScript("OnClick", function()
		local recipe = Data.Recipe(view.selected)
		local limit = Data.MakeableCount(view.selected) or 0
		local count = (recipe and recipe.enchanting) and 1 or math.min(limit, tonumber(schematic.qty:GetText()) or 1)
		CraftRecipeNow(view.selected, count, schematic.form:GetTransaction(), schematic.form:GetCurrentRecipeLevel())
	end)
	schematic.createAll:SetScript("OnClick", function()
		local max = Data.MakeableCount(view.selected) or 0
		schematic.qty:SetText(tostring(math.max(1, max)))
		CraftRecipeNow(view.selected, max, schematic.form:GetTransaction(), schematic.form:GetCurrentRecipeLevel())
	end)

	-- Chooses the enchant target (nil clears it) and refreshes the page to match.
	local function ChooseEnchantItem(item)
		schematic.enchantItem = item
		FillSchematic(schematic, view.selected, false)
	end

	-- The enchant target: a menu of the items the game allows, as Blizzard's enchant flyout lists them.
	schematic.enchantTarget:SetScript("OnClick", function(self)
		MenuUtil.CreateContextMenu(self, function(_, root)
			for _, item in ipairs(EnchantCandidates(view.selected)) do
				root:CreateButton(item:GetItemName() or "Item", function() ChooseEnchantItem(item) end)
			end
			root:CreateButton(_G.CLEAR or "Clear", function() ChooseEnchantItem(nil) end)
		end)
	end)

	function view.Select(id, resetQuantity)
		if id ~= view.selected then schematic.enchantItem = nil end
			view.selected = id; list.selectedID = id
		FillSchematic(schematic, id, resetQuantity)
		for _, row in ipairs(list.rows) do
			    row.selected:SetShown(row.id == id)
				row.highlight:SetShown(row.id ~= id)   -- Blizzard's SetSelected: hover art hidden on the selected row
		end
	end

	list = BuildList(left, view.Select)
	liveViews[#liveViews + 1] = view

	function view.Show(resetQuantity)
		list.Rebuild()
		list.root:Show()
		schematic.root:Show()

		-- Keep the recipe that was open if it is still in the list.
		local previous = view.selected
		local pick = list.rows[1] and list.rows[1].id
		for _, row in ipairs(list.rows) do
			if row.id == view.selected then pick = row.id end
		end
		if pick then
			view.Select(pick, resetQuantity or pick ~= previous)
		else
			view.selected = nil
			FillSchematic(schematic, nil)
		end
	end

	function view.Hide()
		list.root:Hide()
		schematic.root:Hide()
	end

	-- Re-shows the current recipe. The list itself is not rebuilt yet.
	-- The game reports a favourite change. Show it if it is this recipe.
	function view.SetFavorite(recipeID, isFavorite)
		if view.selected == recipeID then
			schematic.favorite:SetChecked(isFavorite == true)
		end
	end

	-- The game reports a tracking change, also from the quest tracker. Show it if it is this recipe.
	function view.SetTracked(recipeID, tracked)
		if view.selected == recipeID then
			schematic.track.tracked = tracked
			schematic.track:SetChecked(tracked)
		end
	end

	function view.Refresh(resetQuantity)
		view.Show(resetQuantity)
	end

	return view
end