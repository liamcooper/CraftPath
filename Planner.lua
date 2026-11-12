-- CraftPath :: Planner
-- Turns the character's settings into solver runs: the route, the no-points and best-points comparison, the
-- recipes that would save gold, the compare board and the opportunity list. Everything runs a few
-- milliseconds a frame; a newer request cancels an older one.

local _, CPath = ...
local Planner = {}
CPath.Planner = Planner

local S = CPath.Solver
local Perks = CPath.Perks
local CANCEL = {}
local gen, boardGen = 0, 0

Planner.state = { status = "idle" }
Planner.board = nil
Planner.dirty = true

local function copy(t) local o = {}; for k, v in pairs(t) do o[k] = v end; return o end

-- Recipes this character can use beyond the ones every trainer teaches: learned, marked by hand, or the
-- recipe item is in the bags or bank.
local function Owned(trade, input, hasTrade)
	local marks = CPath:Char().owned[trade] or {}
	local list, seen = {}, {}
	for _, r in ipairs(input.recipes) do
		if not seen[r.spell] then
			if marks[r.spell] or (hasTrade and CPath:RecipeKnown(r.spell)) or (r.taught_by and CPath:ItemCount(r.taught_by) > 0) then
				seen[r.spell] = true
				list[#list + 1] = r.spell
			end
		end
	end
	return list
end

-- Recipes that can be bought: on the auction house at the last scanned price. The solver uses one only when
-- the route is cheaper with it after paying for it (and a margin, since the listing may be gone).
local function Market(input, owned)
	local have, market = {}, {}
	for _, spell in ipairs(owned) do have[spell] = true end
	for _, r in ipairs(input.recipes) do
		if r.taught_by and not have[r.spell] and r.source ~= "trainer" and market[r.spell] == nil then
			local price = CPath.Prices:Auction(r.taught_by)
			if price then market[r.spell] = price end
		end
	end
	return market
end

local function BaseOpts(trade, input, from, to, hasTrade)
	local priceOpts, stats = CPath.Prices:Build(input)
	local opts = { from = from, to = to, goal = "cheap", side = CPath:Side(), owned = Owned(trade, input, hasTrade) }
	opts.market = Market(input, opts.owned)
	opts.buyLimited = true
	opts.exclude = CPath:Char().excluded[trade] or {}
	for k, v in pairs(priceOpts) do opts[k] = v end
	return opts, stats
end

local function With(opts, alloc, trade)
	local o = copy(opts)
	for k, v in pairs(Perks:Opts(alloc, trade)) do o[k] = v end
	return o
end

local function Start(trade)
	local prof = CPath:Professions()[trade]
	return prof and math.max(1, prof.rank) or 1, prof ~= nil, prof and prof.max or nil
end

---------------------------------------------------------------------------
-- The route for the selected profession
---------------------------------------------------------------------------

function Planner:Plan()
	gen = gen + 1
	local mine = gen
	self.dirty = false
	local c = CPath:Char()
	local trade, to = c.trade, c.target
	local st = { trade = trade, to = to, status = "working", alloc = Perks:Current(), cap = c.cap }
	self.state = st
	local problem = CPath:DataProblem()
	if problem then st.status, st.error = "error", problem; CPath:Fire("PLAN"); return end
	local input = S.levelingInput(trade)
	st.from, st.known, st.max = Start(trade)
	if st.from >= to then st.status, st.reached = "done", true; CPath:Fire("PLAN"); return end
	local opts, stats = BaseOpts(trade, input, st.from, to, st.known)
	st.stats = stats
	CPath:Fire("PLAN")
	local alloc = st.alloc
	S.levelingAsync(function(yield)
		local function y() if gen ~= mine then error(CANCEL, 0) end; yield() end
		local result = S.solveBest(input, With(opts, alloc, trade), y)
		st.result, st.status = result, "comparing"
		CPath:Fire("PLAN")

		local zero = { wo = 0, barter = 0, chef = 0 }
		st.zero = Perks:Same(alloc, zero) and result or S.solveBest(input, With(opts, zero, trade), y)

		local bestAlloc, best = alloc, result
		for _, a in ipairs(Perks:Frontier(alloc, st.cap, trade)) do
			if not Perks:Same(a, alloc) then
				local r = S.solveBest(input, With(opts, a, trade), y)
				if r.net and r["end"] >= best["end"] and (not best.net or r.net < best.net) then bestAlloc, best = a, r end
			end
		end
		st.bestAlloc, st.best = bestAlloc, best

		st.solo = {}
		for _, key in ipairs(Perks.ORDER) do
			local rank = bestAlloc[key] or 0
			if rank > 0 and Perks:Max(key, trade) > 0 then
				local a = { wo = 0, barter = 0, chef = 0 }
				a[key] = rank
				local r = Perks:Same(a, bestAlloc) and best or S.solveBest(input, With(opts, a, trade), y)
				st.solo[#st.solo + 1] = { key = key, rank = rank, net = r.net, crafts = r.totals.crafts }
			end
		end
		st.status = "options"
		CPath:Fire("PLAN")

		local found = S.levelingOptions(input, With(opts, alloc, trade), result, 5, y)
		for _, o in ipairs(found) do
			o.recipeItem = o.taught_by
			o.recipePrice = o.taught_by and CPath.Prices:Auction(o.taught_by) or nil
		end
		st.options = found
		st.status = "done"
		return true
	end, function(ok, err)
		if gen ~= mine or err == CANCEL then return end
		if not ok then st.status, st.error = "error", "The planner hit an error: " .. tostring(err) end
		CPath:Fire("PLAN")
	end)
end

-- Ask for a fresh plan soon. With the window closed the plan is only marked stale.
function Planner:Invalidate()
	self.dirty = true
	if CPath.UI and CPath.UI:IsShown() then
		CPath:Debounce("plan", 0.3, function() Planner:Plan() end)
	end
end

-- "I can't get it": plan without a recipe the route wanted to buy (sold out, not listed any more).
function Planner:MarkExcluded(spell, excluded)
	local c = CPath:Char()
	c.excluded[c.trade] = c.excluded[c.trade] or {}
	c.excluded[c.trade][spell] = excluded and true or nil
	self:Invalidate()
end

function Planner:MarkOwned(spell, owned)
	local c = CPath:Char()
	c.owned[c.trade] = c.owned[c.trade] or {}
	c.owned[c.trade][spell] = owned and true or nil
	self:Invalidate()
end

---------------------------------------------------------------------------
-- Compare board: every profession to 150 and 300
---------------------------------------------------------------------------

Planner.BOARD_TARGETS = { 150, 300 }

function Planner:Board()
	boardGen = boardGen + 1
	local mine = boardGen
	local board = { rows = {}, status = "working", recovery = CPath.settings.recovery }
	self.board = board
	local problem = CPath:DataProblem()
	if problem then board.status, board.error = "error", problem; CPath:Fire("BOARD"); return end
	local alloc = Perks:Current()
	CPath:Fire("BOARD")
	S.levelingAsync(function(yield)
		local function y() if boardGen ~= mine then error(CANCEL, 0) end; yield() end
		for _, trade in ipairs(CPath.TRADES) do
			local input = S.levelingInput(trade)
			local from, known = Start(trade)
			local row = { trade = trade, from = from, known = known, cells = {} }
			local opts, stats = BaseOpts(trade, input, from, 300, known)
			row.priced, row.wanted = stats.priced, stats.wanted
			for _, to in ipairs(Planner.BOARD_TARGETS) do
				if from >= to then
					row.cells[to] = { reached = true }
				else
					local o = With(opts, alloc, trade)
					o.to = to
					local r = S.solveBest(input, o, y)
					row.cells[to] = { net = r.net, crafts = r.totals.crafts, stop = r["end"] }
				end
			end
			board.rows[#board.rows + 1] = row
			CPath:Fire("BOARD")
		end
		board.status = "done"
		return true
	end, function(ok, err)
		if boardGen ~= mine or err == CANCEL then return end
		if not ok then board.status, board.error = "error", "The board hit an error: " .. tostring(err) end
		CPath:Fire("BOARD")
	end)
end

---------------------------------------------------------------------------
-- Opportunity crafts: recipes whose result is worth more than its mats right now
---------------------------------------------------------------------------

function Planner:Opportunities()
	local st = self.state
	if not (st and st.result and st.result.econ) then return nil end
	local rows = st.result.econ(st.from, "flip")
	local out = {}
	for _, e in ipairs(rows) do
		if e.profit > 0 and st.result.totals.spent ~= nil then out[#out + 1] = e end
	end
	table.sort(out, function(a, b) return a.profit > b.profit end)
	return out
end

---------------------------------------------------------------------------
-- When to replan
---------------------------------------------------------------------------

CPath:On("SETTINGS_CHANGED", function() Planner:Invalidate() end)
CPath:On("DB_CHANGED", function() Planner:Invalidate() end)
CPath:On("PRICES_CHANGED", function() Planner:Invalidate() end)
CPath:On("ITEMS_LOADED", function()
	local st = Planner.state
	if CPath.settings and CPath.settings.de and st and st.stats and st.stats.dePending > 0 and CPath.itemsPending == 0 then
		Planner:Invalidate()
	end
end)
local function SkillChanged()
	CPath:Debounce("skill", 1.5, function()
		local st = Planner.state
		if not st or not st.trade then return end
		local from = Start(st.trade)
		if from ~= st.from then Planner:Invalidate() end
	end)
end
CPath:RegisterEvent("SKILL_LINES_CHANGED", SkillChanged)
CPath:RegisterEvent("CHAT_MSG_SKILL", SkillChanged)
