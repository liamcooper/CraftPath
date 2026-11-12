-- CraftPath :: Depth
-- How auction prices climb as you buy more. Auctionator only remembers the cheapest listing, so the planner
-- would price 1,500 Linen Cloth as if all of it cost what the first few do. This reads the real listings
-- of chosen items at the auction house, one item at a time, and keeps them as a ladder of
-- { unit price, quantity } tiers, cheapest first.
--
-- The search handling follows CraftProfit's Scanner.lua, which found out the hard way how this client
-- behaves: commodities are searched with a plain item key and no sorts, an unanswered search times out and
-- is retried the other way (commodity or item), and nothing is sent while the client says it is throttled.

local _, CPath = ...
local Depth = {}
CPath.Depth = Depth

local MAX_TIERS, MAX_QTY = 60, 20000
local KEEP_TIERS = 30            -- tiers saved per item
local FRESH = 24 * 3600          -- a ladder older than this is ignored
local TIMEOUT = 6                -- seconds without an answer before a search counts as lost
local AH = _G.C_AuctionHouse

local ahOpen = false
local queue, current, waitingThrottle = nil, nil, false
local want = {}                  -- itemID -> units the caller needs (how deep to read)
local commodity = {}             -- itemID -> true | false once known
local job                        -- { total, done, onDone }

local function Store()
	local db = CPath.db
	if type(db.ladders) ~= "table" then db.ladders = {} end
	return db.ladders
end

function Depth:IsOpen() return ahOpen end
function Depth:IsRunning() return current ~= nil or (queue ~= nil and #queue > 0) end
function Depth:Progress() if job then return job.done, job.total end end
function Depth:Available() return AH ~= nil and AH.SendSearchQuery ~= nil and AH.MakeItemKey ~= nil end

-- The saved ladder for an item, when it is recent enough to trust.
function Depth:Ladder(id)
	local l = Store()[id]
	if type(l) ~= "table" or not l.t or time() - l.t > FRESH then return nil end
	return l
end

function Depth:Age(id)
	local l = self:Ladder(id)
	return l and (time() - l.t) or nil
end

-- What buying `qty` of an item costs at the listings last read.
-- Returns total, average unit price, info { qty, avg, covered, short, full, first, firstQty, last, listed, age }.
-- `short` units are not covered: with info.full they are not on the auction house at all, otherwise they lie
-- beyond what was read; either way they are priced at the dearest listing seen.
-- When nothing was listed: nil, nil, { none = true, qty, short = qty }. No ladder at all: nil.
function Depth:Cost(id, qty)
	local l = self:Ladder(id)
	if not l then return nil end
	qty = math.max(1, math.floor(qty))
	local tiers = l.tiers or {}
	if #tiers == 0 then return nil, nil, { none = true, qty = qty, short = qty, age = time() - l.t } end
	local left, total, last = qty, 0, tiers[1][1]
	for _, tier in ipairs(tiers) do
		if left <= 0 then break end
		local take = math.min(left, tier[2])
		total, left, last = total + take * tier[1], left - take, tier[1]
	end
	if left > 0 then
		last = tiers[#tiers][1]
		total = total + left * last
	end
	return total, total / qty, {
		qty = qty, avg = total / qty, covered = qty - left, short = left, full = l.full and true or false,
		first = tiers[1][1], firstQty = tiers[1][2], last = last, listed = l.total or 0, age = time() - l.t,
	}
end

local function Save(id, tiers, full)
	local total, kept = 0, {}
	for i, tier in ipairs(tiers) do
		total = total + tier[2]
		if i <= KEEP_TIERS then kept[i] = { tier[1], tier[2] } end
	end
	-- tiers past the cap are folded into the last one kept, at its price: a little optimistic, never short
	if #tiers > KEEP_TIERS then
		local folded = 0
		for i = KEEP_TIERS + 1, #tiers do folded = folded + tiers[i][2] end
		kept[KEEP_TIERS][2] = kept[KEEP_TIERS][2] + folded
	end
	Store()[id] = { t = time(), full = full and true or false, total = total, tiers = kept }
	CPath:Fire("DEPTH", id)
end

---------------------------------------------------------------------------
-- Reading results
---------------------------------------------------------------------------

local function ReadCommodity(id)
	if not (AH.GetNumCommoditySearchResults and AH.GetCommoditySearchResultInfo) then return nil end
	local ok, n = pcall(AH.GetNumCommoditySearchResults, id)
	if not ok or not n then return nil end
	local tiers, last, qty = {}, nil, 0
	for i = 1, n do
		local ok2, r = pcall(AH.GetCommoditySearchResultInfo, id, i)
		if ok2 and r and r.unitPrice and r.quantity then
			if last and last[1] == r.unitPrice then last[2] = last[2] + r.quantity
			else last = { r.unitPrice, r.quantity }; tiers[#tiers + 1] = last end
			qty = qty + r.quantity
			if #tiers >= MAX_TIERS or qty >= MAX_QTY then break end
		end
	end
	local full = true
	if AH.HasFullCommoditySearchResults then
		local ok3, f = pcall(AH.HasFullCommoditySearchResults, id)
		full = ok3 and f or false
	end
	return tiers, full, qty
end

local function ReadItems(key)
	if not (AH.GetNumItemSearchResults and AH.GetItemSearchResultInfo) then return nil end
	local ok, n = pcall(AH.GetNumItemSearchResults, key)
	if not ok or not n then return nil end
	local tiers = {}
	for i = 1, n do
		local ok2, r = pcall(AH.GetItemSearchResultInfo, key, i)
		local price = ok2 and r and r.buyoutAmount
		if price and price > 0 then
			local q = r.quantity or 1
			tiers[#tiers + 1] = { price / q, q }
			if #tiers >= MAX_TIERS then break end
		end
	end
	table.sort(tiers, function(a, b) return a[1] < b[1] end)
	local full = true
	if AH.HasFullItemSearchResults then
		local ok3, f = pcall(AH.HasFullItemSearchResults, key)
		full = ok3 and f or false
	end
	return tiers, full
end

---------------------------------------------------------------------------
-- The queue
---------------------------------------------------------------------------

local Next

local function Finish(id)
	if not (current and current.id == id) then return end
	current = nil
	if job then job.done = job.done + 1 end
	CPath:Fire("DEPTH_PROGRESS")
	Next()
end

local function IsCommodity(id, key)
	if commodity[id] ~= nil then return commodity[id] end
	if AH.GetItemKeyInfo and key then
		local ok, info = pcall(AH.GetItemKeyInfo, key)
		if ok and type(info) == "table" and info.isCommodity ~= nil then
			commodity[id] = info.isCommodity and true or false
			return commodity[id]
		end
	end
	-- not known yet: things that stack are commodities
	local fn = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
	if fn then
		local ok, name, _, _, _, _, _, _, stack = pcall(fn, id)
		if ok and name and type(stack) == "number" then return stack > 1 end
	end
	return true
end

local function BuyPageOpen()
	local ah, modes = _G.AuctionHouseFrame, _G.AuctionHouseFrameDisplayMode
	if not (ah and modes and ah.displayMode) then return false end
	return ah.displayMode == modes.CommoditiesBuy or ah.displayMode == modes.ItemBuy
end

local function Arm(cur)
	cur.seq = (cur.seq or 0) + 1
	local seq = cur.seq
	CPath:After(TIMEOUT, function()
		if current ~= cur or cur.seq ~= seq then return end
		if not cur.retried then
			-- lost: try once more the other way round (its kind may have been guessed wrong)
			commodity[cur.id] = not cur.commodity
			current = nil
			queue = queue or {}
			table.insert(queue, 1, cur.id)
			want["retried" .. cur.id] = true
			Next()
		else
			Finish(cur.id)
		end
	end)
end

Next = function()
	if current then return end
	if not ahOpen then queue = nil end
	local id = queue and queue[1]
	if not id then
		queue = nil
		local j = job
		job = nil
		if j then
			CPath:Fire("DEPTH_PROGRESS")
			if j.onDone then j.onDone(j.done, j.total) end
		end
		return
	end
	if BuyPageOpen() then
		-- a search would replace the one the buy page is using: wait until the player leaves it
		CPath:After(1, Next)
		return
	end
	if AH.IsThrottledMessageSystemReady and not AH.IsThrottledMessageSystemReady() then
		waitingThrottle = true
		return
	end
	table.remove(queue, 1)
	local okKey, key = pcall(AH.MakeItemKey, id)
	if not okKey or not key then return Next() end
	local isCommodity = IsCommodity(id, key)
	local sorts = {}
	if not isCommodity then
		sorts = { { sortOrder = (Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price) or 0, reverseSort = false } }
	end
	local ok = pcall(AH.SendSearchQuery, key, sorts, false)
	if not ok then
		if job then job.done = job.done + 1 end
		return Next()
	end
	current = { id = id, commodity = isCommodity, retried = want["retried" .. id] }
	want["retried" .. id] = nil
	Arm(current)
end

-- Reads the listings of these items. needs: itemID -> units wanted (how deep to read). AH must be open.
-- onDone(done, total) is called when the queue drains. Returns ok, message.
function Depth:Scan(needs, onDone)
	if not self:Available() then return false, "This client has no per-item auction search CraftPath can use." end
	if not ahOpen then return false, "Open the auction house first." end
	queue = queue or {}
	local queued = {}
	for _, id in ipairs(queue) do queued[id] = true end
	if current then queued[current.id] = true end
	local added = 0
	for id, units in pairs(needs) do
		want[id] = math.max(want[id] or 0, units or 0)
		if not queued[id] then queue[#queue + 1] = id; added = added + 1 end
	end
	if added == 0 and not self:IsRunning() then
		if onDone then onDone(0, 0) end
		return true, "Nothing to check."
	end
	job = job or { total = 0, done = 0 }
	job.total = job.total + added
	job.onDone = onDone or job.onDone
	CPath:Fire("DEPTH_PROGRESS")
	Next()
	return true
end

function Depth:Cancel()
	queue, current, job, waitingThrottle = nil, nil, nil, false
	CPath:Fire("DEPTH_PROGRESS")
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local function OnCommodity(_, id)
	if not CPath.db then return end
	if not id and current and current.commodity then id = current.id end
	if not id then return end
	commodity[id] = true
	local mine = current and current.id == id
	local tiers, full, qty = ReadCommodity(id)
	if not tiers then return end
	if #tiers == 0 then
		if mine then Save(id, {}, true); Finish(id) end
		return
	end
	local enough = (qty or 0) >= math.max(200, (want[id] or 0) * 1.5)
	if mine and not full and not enough and #tiers < MAX_TIERS and (qty or 0) < MAX_QTY and AH.RequestMoreCommoditySearchResults
		and (not AH.IsThrottledMessageSystemReady or AH.IsThrottledMessageSystemReady()) then
		if pcall(AH.RequestMoreCommoditySearchResults, id) then
			Arm(current)   -- a page that never comes must not hold up the queue
			return
		end
	end
	Save(id, tiers, full)
	if mine then Finish(id) end
end

local function OnItems(_, key)
	if not CPath.db then return end
	local id = type(key) == "table" and key.itemID or nil
	if not id then return end
	local mine = current and current.id == id
	if not mine then return end   -- someone else's search may be for one variant only
	local tiers, full = ReadItems(key)
	if tiers then Save(id, tiers, full) end
	Finish(id)
end

if AH then
	CPath:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED", OnCommodity)
	CPath:RegisterEvent("COMMODITY_SEARCH_RESULTS_ADDED", OnCommodity)
	CPath:RegisterEvent("COMMODITY_SEARCH_RESULTS_RECEIVED", function(event, id)
		-- may carry no item, and may arrive before the rows can be read: UPDATED brings them
		local target = id or (current and current.commodity and current.id)
		if not target or not AH.GetNumCommoditySearchResults then return end
		local ok, n = pcall(AH.GetNumCommoditySearchResults, target)
		if ok and n and n > 0 then OnCommodity(event, target) end
	end)
	CPath:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED", OnItems)
	CPath:RegisterEvent("ITEM_SEARCH_RESULTS_ADDED", OnItems)
	CPath:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function()
		if waitingThrottle then waitingThrottle = false; Next() end
	end)
end
CPath:RegisterEvent("AUCTION_HOUSE_SHOW", function() ahOpen = true; CPath:Fire("DEPTH_PROGRESS") end)
CPath:RegisterEvent("AUCTION_HOUSE_CLOSED", function()
	ahOpen = false
	local j = job
	queue, current, job, waitingThrottle = nil, nil, nil, false
	CPath:Fire("DEPTH_PROGRESS")
	if j and j.onDone then j.onDone(j.done, j.total, true) end
end)

-- Drop ladders too old to use, so the saved file stays small.
CPath:On("LOGIN", function()
	local store = Store()
	for id, l in pairs(store) do
		if type(l) ~= "table" or not l.t or time() - l.t > FRESH then store[id] = nil end
	end
end)
