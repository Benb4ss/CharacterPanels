-- Read-only. Builds the shortfall for all tracked recipes.
-- Uses only calls confirmed in Blizzard's code:
-- C_TradeSkillUI.GetRecipesTracked, ProfessionsUtil.GetRecipeSchematic,
-- ProfessionsUtil.IsReagentSlotBasicRequired, ProfessionsUtil.AccumulateReagentsInPossession.
ShoppingListUtil = {};

local function ReagentKey(reagent)
	if reagent.itemID then
		return "item:" .. reagent.itemID;
	elseif reagent.currencyID then
		return "currency:" .. reagent.currencyID;
	end
	return nil;
end

-- Returns a list of { reagent, required, owned, missing } for reagents still short.
function ShoppingListUtil.GetShortfall()
	local rows = {};
	local byKey = {};

	local function AddRecipe(recipeID, isRecraft)
		local schematic = ProfessionsUtil.GetRecipeSchematic(recipeID, isRecraft);
		for _, slot in ipairs(schematic.reagentSlotSchematics) do
			if ProfessionsUtil.IsReagentSlotBasicRequired(slot) and slot.reagents[1] then
				local reagent = slot.reagents[1];
				local key = ReagentKey(reagent);
				if key then
					local row = byKey[key];
					if not row then
						row = {
							reagent = reagent,
							required = 0,
							owned = ProfessionsUtil.AccumulateReagentsInPossession(slot.reagents),
						};
						byKey[key] = row;
						table.insert(rows, row);
					end
					row.required = row.required + slot:GetQuantityRequired(reagent);
				end
			end
		end
	end

	for _, recipeID in ipairs(C_TradeSkillUI.GetRecipesTracked(false)) do
		AddRecipe(recipeID, false);
	end
	for _, recipeID in ipairs(C_TradeSkillUI.GetRecipesTracked(true)) do
		AddRecipe(recipeID, true);
	end

	local shortfall = {};
	for _, row in ipairs(rows) do
		row.missing = math.max(0, row.required - row.owned);
		if row.missing > 0 then
			table.insert(shortfall, row);
		end
	end
	return shortfall;
end