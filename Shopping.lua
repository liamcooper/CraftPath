-- CraftPath :: Shopping
-- What the route needs bought, net of bags and bank: an Auctionator list with quantities, a vendor list,
-- and a plain-text copy.

local _, CPath = ...
local Shopping = {}
CPath.Shopping = Shopping

-- st: a planner state with a result. Returns { ah, vendor, have, recipes } rows.
function Shopping:Build(st)
	local r = st and st.result
	if not (r and r.list) then return nil end
	local out = { ah = {}, vendor = {}, have = {}, recipes = {}, ahCost = 0, vendorCost = 0 }
	for _, x in ipairs(r.list.buy) do
		local have = CPath:ItemCount(x.id)
		local need = math.max(0, x.count - have)
		local row = { id = x.id, count = need, want = x.count, have = math.min(have, x.count), unit = r.price and r.price[x.id], src = r.sources and r.sources[x.id] }
		if need > 0 then
			if row.src == "vendor" then
				out.vendor[#out.vendor + 1] = row
				out.vendorCost = out.vendorCost + need * (row.unit or 0)
			else
				out.ah[#out.ah + 1] = row
				out.ahCost = out.ahCost + need * (row.unit or 0)
			end
		end
		if row.have > 0 then out.have[#out.have + 1] = row end
	end
	for _, p in ipairs(r.purchases or {}) do
		local rec = r.recipes[p.spell]
		out.recipes[#out.recipes + 1] = { spell = p.spell, price = p.price, fee = p.fee, makes = rec and rec.makes, source = rec and rec.source, item = rec and rec.taught_by }
	end
	return out
end

function Shopping:ListName(st)
	return string.format("CraftPath: %s %d-%d", st.trade, st.from, st.result["end"] or st.to)
end

-- Creates (or replaces) the Auctionator shopping list. Returns ok, message.
function Shopping:CreateList(st)
	local list = self:Build(st)
	if not list then return false, "There is no route yet." end
	local api = _G.Auctionator and _G.Auctionator.API and _G.Auctionator.API.v1
	if not (api and api.CreateShoppingList and api.ConvertToSearchString) then return false, "Auctionator's shopping list API is not available." end
	if #list.ah == 0 then return false, "Nothing to buy at the auction house: you have it all, or the rest comes from vendors." end
	local terms, loading = {}, 0
	for _, row in ipairs(list.ah) do
		local name, known = CPath:ItemName(row.id)
		if known then
			local ok, term = pcall(api.ConvertToSearchString, CPath.ID, { searchString = name, isExact = true, quantity = row.count })
			if ok and term then terms[#terms + 1] = term end
		else
			loading = loading + 1
		end
	end
	if loading > 0 then return false, loading .. " item names are still loading from the server. Try again in a few seconds." end
	local name = self:ListName(st)
	local ok, err = pcall(api.CreateShoppingList, CPath.ID, name, terms)
	if not ok then return false, "Auctionator refused the list: " .. tostring(err) end
	return true, string.format("Auctionator list \"%s\" created with %d items. An older list with the same name was replaced.", name, #terms)
end

-- Plain text for Discord or an alt.
function Shopping:Text(st)
	local list = self:Build(st)
	if not list then return "" end
	local r = st.result
	local lines = { string.format("CraftPath: %s %d to %d (%s)", st.trade, st.from, r["end"] or st.to, CPath.settings.recovery) }
	local function section(title, rows)
		if #rows == 0 then return end
		lines[#lines + 1] = ""
		lines[#lines + 1] = title
		for _, row in ipairs(rows) do
			local name = CPath:ItemName(row.id)
			local each = row.unit and (" @ " .. CPath:Money(row.unit, true)) or ""
			lines[#lines + 1] = string.format("%d x %s%s", row.count, name, each)
		end
	end
	section("Auction house (" .. CPath:Money(list.ahCost, true) .. ")", list.ah)
	section("Vendor (" .. CPath:Money(list.vendorCost, true) .. ")", list.vendor)
	if #list.recipes > 0 then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "Recipes"
		for _, p in ipairs(list.recipes) do
			local cost = (p.price or 0) + (p.fee or 0)
			lines[#lines + 1] = string.format("%s (%s) %s", CPath:RecipeName(p.spell, p.makes), p.source or "?", CPath:Money(cost, true))
		end
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "Steps"
	for _, s in ipairs(r.steps) do
		local rec = r.recipes[s.spell]
		lines[#lines + 1] = string.format("%d-%d: %s x%d", s.from, s.to, CPath:RecipeName(s.spell, rec and rec.makes), s.crafts)
	end
	local more = {}
	for id, units in pairs(r.list.more or {}) do more[#more + 1] = { id = id, units = units } end
	if #more > 0 then
		table.sort(more, function(a, b) return a.id < b.id end)
		lines[#lines + 1] = ""
		lines[#lines + 1] = "Also make (materials for the steps)"
		for _, m in ipairs(more) do lines[#lines + 1] = string.format("%d x %s", m.units, CPath:ItemName(m.id)) end
	end
	if r.net then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "Net cost: " .. CPath:Money(r.net, true)
	end
	return table.concat(lines, "\n")
end
