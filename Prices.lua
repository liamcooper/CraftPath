-- CraftPath :: Prices
-- Everything the solver is told about money: auction prices and listed quantities (Auctionator), vendor buy
-- prices seen at merchants, vendor sell values, and disenchant values from the bundled classic table.

local _, CPath = ...
local Prices = {}
CPath.Prices = Prices

local DUST = 10940

local function API()
	local a = _G.Auctionator
	return a and a.API and a.API.v1
end

function Prices:HasAuctionator()
	local api = API()
	return api ~= nil and api.GetAuctionPriceByItemID ~= nil
end

function Prices:Auction(id)
	local api = API()
	if not (api and api.GetAuctionPriceByItemID) then return nil end
	local ok, price = pcall(api.GetAuctionPriceByItemID, CPath.ID, id)
	if ok and type(price) == "number" and price > 0 then return price end
	return nil
end

-- How many were listed at the last scan, or nil when Auctionator did not record it.
function Prices:Listed(id)
	local db = _G.Auctionator and _G.Auctionator.Database
	if not (db and db.GetPriceHistory) then return nil end
	local ok, history = pcall(db.GetPriceHistory, db, tostring(id))
	if ok and type(history) == "table" and history[1] and type(history[1].available) == "number" then
		return history[1].available
	end
	return nil
end

---------------------------------------------------------------------------
-- Vendor buy prices, learned from every merchant the player opens
---------------------------------------------------------------------------

-- index -> itemID, unit price, items per purchase, stock (nil = unlimited)
function Prices:MerchantItem(index)
	local id = CPath:ItemIDFromLink(GetMerchantItemLink and GetMerchantItemLink(index))
	if not id then return nil end
	local price, stack, extended, stock
	if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
		local info = C_MerchantFrame.GetItemInfo(index)
		if info then price, stack, extended, stock = info.price, info.stackCount or info.quantity, info.hasExtendedCost, info.numAvailable end
	elseif GetMerchantItemInfo then
		local _, _, p, q, na, _, _, ext = GetMerchantItemInfo(index)
		price, stack, stock, extended = p, q, na, ext
	end
	if GetMerchantItemCostInfo then
		local n = GetMerchantItemCostInfo(index)
		if n and n > 0 then extended = true end
	end
	if not price or price <= 0 or extended then return nil end
	stack = (stack and stack > 0) and stack or 1
	if stock and stock < 0 then stock = nil end
	return id, price / stack, stack, stock
end

local function LearnMerchant()
	if not (CPath.db and GetMerchantNumItems) then return end
	local changed = false
	for i = 1, GetMerchantNumItems() or 0 do
		local ok, id, unit, _, stock = pcall(Prices.MerchantItem, Prices, i)
		if ok and id and unit and not stock then
			unit = math.floor(unit + 0.5)
			if CPath.db.vendor[id] ~= unit then CPath.db.vendor[id] = unit; changed = true end
		end
	end
	if changed then CPath:Fire("PRICES_CHANGED") end
end
CPath:RegisterEvent("MERCHANT_SHOW", LearnMerchant)
CPath:RegisterEvent("MERCHANT_UPDATE", LearnMerchant)

---------------------------------------------------------------------------
-- Disenchant value
---------------------------------------------------------------------------

local function MatPrice(id, cache)
	if cache[id] ~= nil then return cache[id] or nil end
	local price = Prices:Auction(id)
	local greater = CPath.EssenceUpgrade[id]
	if greater then
		local g = Prices:Auction(greater)
		if g and (not price or price * 3 > g) then price = g / 3 end
	end
	cache[id] = price or false
	return price
end

-- Expected, worst and best copper from disenchanting one of this item; nil when it cannot be disenchanted or
-- its details are not loaded yet (second return "pending").
function Prices:Disenchant(id, cache)
	local name, _, quality, ilvl, _, classID = CPath:ItemInfo(id)
	if not name then return nil, "pending" end
	local byQuality = CPath.DisenchantTable[classID or -1]
	local rows = byQuality and byQuality[quality or -1]
	if not rows or not ilvl then return nil end
	cache = cache or {}
	for _, e in ipairs(rows) do
		if ilvl >= e[1] and ilvl <= e[2] then
			local ev, lo, hi, missing = 0, nil, nil, false
			for x = 3, #e, 3 do
				local chance, qty, mat = e[x], e[x + 1], e[x + 2]
				local price = MatPrice(mat, cache)
				if chance > 0 then
					if price then
						local v = qty * price
						ev = ev + chance * v / 100
						lo = (lo == nil or v < lo) and v or lo
						hi = (hi == nil or v > hi) and v or hi
					else
						missing = true
					end
				end
			end
			if ev <= 0 then return nil end
			return { ev = ev, lo = lo or 0, hi = hi or 0, partial = missing }
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- What one solve needs
---------------------------------------------------------------------------

-- input: the decoded trade (Solver.levelingInput). Returns the price fields of the solver's options and a
-- summary { priced, wanted, dePending, auctionator } for the status line.
function Prices:Build(input)
	local s = CPath.settings
	local ids, makes = { [DUST] = true }, {}
	for _, r in ipairs(input.recipes) do
		for _, x in ipairs(r.reagents) do ids[x.id] = true end
		if r.makes then ids[r.makes.id] = true; makes[r.makes.id] = true end
	end
	local prices, priced, wanted = {}, 0, 0
	for id in pairs(ids) do
		wanted = wanted + 1
		local ah = self:Auction(id)
		if ah then
			priced = priced + 1
			local listed = 0
			if makes[id] then listed = self:Listed(id) or s.flipDepth end
			prices[id] = { ah, listed }
		end
	end
	local sell, de, deRange, dePending = {}, {}, {}, 0
	local cache = {}
	for id in pairs(makes) do
		if s.de then
			local d, why = self:Disenchant(id, cache)
			if d then de[id] = d.ev; deRange[id] = d
			elseif why == "pending" then dePending = dePending + 1 end
		end
		-- the game's own sell value when the item is already loaded; ForeverMaster's figure otherwise
		local fn = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
		if fn then
			local ok, name, _, _, _, _, _, _, _, _, _, value = pcall(fn, id)
			if ok and name and type(value) == "number" then sell[id] = value end
		end
	end
	return {
		prices = next(prices) and prices or nil,
		vendor = CPath.db.vendor,
		sell = sell,
		de = de,
		recovery = s.recovery,
		cut = s.cut,
		depositRate = s.depositPer24 * (s.listHours / 24),
	}, { priced = priced, wanted = wanted, dePending = dePending, deRange = deRange, auctionator = self:HasAuctionator() }
end
