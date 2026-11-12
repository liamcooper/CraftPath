-- CraftPath :: Execute
-- Two buttons on top of the plan: craft a step's items, and buy the plan's missing vendor mats while a
-- merchant window is open. Both only act on a click.

local _, CPath = ...
local Execute = {}
CPath.Execute = Execute

---------------------------------------------------------------------------
-- Craft a step
---------------------------------------------------------------------------

-- Crafts up to `want` of a recipe, as many as the mats in the bags allow.
function Execute:CraftSpell(st, spell, want, rec)
	local name = CPath:RecipeName(spell, rec and rec.makes)
	if not st.known then CPath:Print("Learn %s first: this character does not have it.", st.trade); return end
	local T = _G.C_TradeSkillUI
	if not (T and T.CraftRecipe) then CPath:Print("This client has no craft call CraftPath can use. Craft %s x%d by hand.", name, want); return end
	if st.trade == "Enchanting" and not (rec and rec.makes) then
		if T.OpenRecipe then pcall(T.OpenRecipe, spell) end
		CPath:Print("Enchants are cast one at a time: %s x%d. The recipe has been opened if the game allows it.", name, want)
		return
	end
	local can, short = want, nil
	for _, x in ipairs(rec and rec.reagents or {}) do
		local n = math.floor(CPath:ItemCount(x.id, true) / x.count)
		if n < can then can, short = n, x.id end
	end
	if can <= 0 then
		CPath:Print("No mats in your bags for %s: you are out of %s.", name, CPath:ItemName(short))
		return
	end
	if T.OpenRecipe then pcall(T.OpenRecipe, spell) end
	local ok, err = pcall(T.CraftRecipe, spell, can)
	if not ok then
		CPath:Print("Could not start crafting %s: %s", name, tostring(err))
		return
	end
	if can < want then
		CPath:Print("Crafting %s x%d (mats for %d of %d; short of %s). If nothing happens, open your %s window and click again.", name, can, can, want, CPath:ItemName(short), st.trade)
	else
		CPath:Print("Crafting %s x%d. If nothing happens, open your %s window and click again.", name, can, st.trade)
	end
end

function Execute:Craft(st, k)
	local r = st and st.result
	local step = r and r.steps[k]
	if not step then return end
	self:CraftSpell(st, step.spell, step.crafts, r.recipes[step.spell])
end

---------------------------------------------------------------------------
-- Vendor restock
---------------------------------------------------------------------------

local MAX_CALLS = 60   -- purchases per click
local button

-- What this merchant sells that the plan still needs: { index, id, need, unit, stack, stock }.
local function Offers()
	local st = CPath.Planner.state
	local list = CPath.Shopping:Build(st)
	if not list or not GetMerchantNumItems then return {} end
	local need = {}
	for _, row in ipairs(list.vendor) do need[row.id] = row.count end
	-- vendor-sold recipes the route still needs
	for _, p in ipairs(list.recipes) do
		if p.item and (p.price or 0) > 0 and CPath:ItemCount(p.item) == 0 then need[p.item] = 1 end
	end
	local out = {}
	for i = 1, GetMerchantNumItems() or 0 do
		local ok, id, unit, stack, stock = pcall(CPath.Prices.MerchantItem, CPath.Prices, i)
		if ok and id and need[id] and need[id] > 0 then
			local n = need[id]
			if stock then n = math.min(n, stock * stack) end
			if n > 0 then out[#out + 1] = { index = i, id = id, need = n, unit = unit, stack = stack } end
			need[id] = nil
		end
	end
	return out
end

local function Cost(offers)
	local total = 0
	for _, o in ipairs(offers) do total = total + math.ceil(o.need / o.stack) * o.stack * o.unit end
	return total
end

local function Buy()
	local offers = Offers()
	if #offers == 0 then return end
	local cost = Cost(offers)
	if GetMoney and GetMoney() < cost then
		CPath:Print("Not enough gold: the missing vendor mats cost %s.", CPath:Money(cost))
		return
	end
	local calls, left = 0, false
	for _, o in ipairs(offers) do
		local qty = o.need
		if o.stack > 1 then
			-- sold in bundles: one purchase is one bundle
			local bundles = math.ceil(qty / o.stack)
			while bundles > 0 and calls < MAX_CALLS do
				BuyMerchantItem(o.index)
				bundles, calls = bundles - 1, calls + 1
			end
			if bundles > 0 then left = true end
		else
			local maxStack = (GetMerchantItemMaxStack and GetMerchantItemMaxStack(o.index)) or 1
			if not maxStack or maxStack < 1 then maxStack = 1 end
			while qty > 0 and calls < MAX_CALLS do
				local n = math.min(qty, maxStack)
				BuyMerchantItem(o.index, n)
				qty, calls = qty - n, calls + 1
			end
			if qty > 0 then left = true end
		end
	end
	CPath:Print(left and "Bought as much as one click allows. Click again for the rest." or "Bought the plan's missing vendor mats (%s).", CPath:Money(cost))
end

local function Update()
	if not (CPath.db and MerchantFrame and MerchantFrame:IsShown()) then
		if button then button:Hide() end
		return
	end
	local offers = Offers()
	if #offers == 0 then
		if button then button:Hide() end
		return
	end
	if not button then
		button = CreateFrame("Button", "CraftPathRestockButton", UIParent, "UIPanelButtonTemplate")
		button:SetFrameStrata("HIGH")
		button:SetHeight(24)
		button:SetScript("OnClick", Buy)
		button:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine("CraftPath restock")
			for _, o in ipairs(Offers()) do
				GameTooltip:AddDoubleLine(CPath:ItemName(o.id) .. " x" .. o.need, CPath:Money(math.ceil(o.need / o.stack) * o.stack * o.unit), 1, 1, 1, 1, 1, 1)
			end
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	local n = 0
	for _, o in ipairs(offers) do n = n + o.need end
	button:SetText(string.format("CraftPath: buy %d missing mats (%s)", n, CPath:Money(Cost(offers), true)))
	button:SetWidth(math.max(220, (button:GetFontString() and button:GetFontString():GetStringWidth() or 200) + 30))
	button:ClearAllPoints()
	button:SetPoint("BOTTOMLEFT", MerchantFrame, "TOPLEFT", 0, 4)
	button:Show()
end

local function Soon() CPath:Debounce("restock", 0.3, Update) end
CPath:RegisterEvent("MERCHANT_SHOW", Soon)
CPath:RegisterEvent("MERCHANT_UPDATE", Soon)
CPath:RegisterEvent("BAG_UPDATE_DELAYED", function()
	if MerchantFrame and MerchantFrame:IsShown() then Soon() end
	CPath:Debounce("bags", 0.5, function() CPath:Fire("BAGS") end)
end)
CPath:RegisterEvent("MERCHANT_CLOSED", function() if button then button:Hide() end end)
CPath:On("PLAN", function() if MerchantFrame and MerchantFrame:IsShown() then Soon() end end)
