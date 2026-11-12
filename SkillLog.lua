-- CraftPath :: SkillLog
-- Counts crafts and skill-ups on yellow and green recipes, to show whether Working Overtime adds to the
-- skill-up chance or multiplies it. Kept per character and per Working Overtime rank as running totals.

local _, CPath = ...
local SkillLog = {}
CPath.SkillLog = SkillLog

local S = CPath.Solver
local index            -- spell -> { trade, recipe }
local before = {}      -- trade -> skill when the current cast started

local function Index()
	if index then return index end
	index = {}
	for _, trade in ipairs(CPath.TRADES) do
		local input = S.levelingInput(trade)
		if input then
			for _, r in ipairs(input.recipes) do
				if not index[r.spell] then index[r.spell] = { trade = trade, r = r } end
			end
		end
	end
	return index
end

local function Find(...)
	local idx = Index()
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		if type(v) == "number" and idx[v] then return idx[v] end
	end
end

local function Bucket(rank)
	local log = CPath:Char().log
	local key = "wo" .. rank
	if type(log[key]) ~= "table" then log[key] = { n = 0, ups = 0, base = 0, add = 0, mul = 0, llAdd = 0, llMul = 0 } end
	return log[key]
end

local function LogLik(p, up)
	local q = up and p or (1 - p)
	if q < 1e-6 then q = 1e-6 end
	return math.log(q)
end

local function Record(base, up)
	local rank = CPath:Char().wo or 0
	local bonus = rank * CPath.Perks.DEFS.wo.per
	local pa, pm = math.min(1, base + bonus), math.min(1, base * (1 + bonus))
	local b = Bucket(rank)
	b.n, b.ups = b.n + 1, b.ups + (up and 1 or 0)
	b.base, b.add, b.mul = b.base + base, b.add + pa, b.mul + pm
	b.llAdd, b.llMul = b.llAdd + LogLik(pa, up), b.llMul + LogLik(pm, up)
	CPath:Fire("SKILLLOG")
end

CPath:RegisterEvent("UNIT_SPELLCAST_START", function(_, unit, ...)
	if unit ~= "player" or not CPath.db then return end
	local e = Find(...)
	if not e then return end
	local prof = CPath:Professions()[e.trade]
	if prof then before[e.trade] = prof.rank end
end)

CPath:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, ...)
	if unit ~= "player" or not CPath.db then return end
	local e = Find(...)
	if not e then return end
	local was = before[e.trade]
	before[e.trade] = nil
	if not was then return end
	local base = S.levelingChance(e.r, was)
	if base <= 0 or base >= 1 then return end   -- orange and grey crafts say nothing about the perk
	CPath:After(0.7, function()
		local prof = CPath:Professions()[e.trade]
		if prof then Record(base, prof.rank > was) end
	end)
end)

-- Lines for the Log tab.
function SkillLog:Lines()
	local lines = {}
	local log = CPath:Char().log
	local any = false
	for rank = 0, CPath.Perks.DEFS.wo.max do
		local b = log["wo" .. rank]
		if type(b) == "table" and b.n > 0 then
			any = true
			lines[#lines + 1] = { text = string.format("Working Overtime rank %d: %d yellow and green crafts, %d skill-ups.", rank, b.n, b.ups), header = true }
			if rank == 0 then
				lines[#lines + 1] = { text = string.format("Predicted with no perk: %.1f skill-ups.", b.base), muted = true, indent = 1 }
			else
				lines[#lines + 1] = { text = string.format("Predicted if the perk adds to the chance: %.1f. If it multiplies it: %.1f. With no perk it would be %.1f.", b.add, b.mul, b.base), muted = true, indent = 1 }
				local diff = b.llAdd - b.llMul
				local verdict
				if b.n < 60 then verdict = string.format("Too few crafts to call it yet (%d of about 60).", b.n)
				elseif diff > 3 then verdict = "This fits \"added\" clearly better."
				elseif diff < -3 then verdict = "This fits \"multiplied\" clearly better. Switch the Working Overtime setting to \"multiplied\"."
				else verdict = "The two are still too close to call. Keep crafting." end
				lines[#lines + 1] = { text = verdict, indent = 1 }
			end
		end
	end
	if not any then
		lines[#lines + 1] = { text = "Nothing recorded yet.", header = true }
		lines[#lines + 1] = { text = "CraftPath counts every craft of a yellow or green recipe and whether it gave a skill point. Set your Working Overtime rank above so the crafts are filed under the right rank. After about 60 crafts with the perk it can tell you whether the perk adds to the skill-up chance or multiplies it.", muted = true, indent = 1 }
	end
	return lines
end
