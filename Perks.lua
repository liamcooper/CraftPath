-- CraftPath :: Perks
-- The three Legacy perks that change a route's cost, and the allocations worth comparing.

local _, CPath = ...
local Perks = {}
CPath.Perks = Perks

-- One point per rank, 16 points per character (Wowhead Legacy calculator, Nov 2026).
Perks.ORDER = { "wo", "barter", "chef" }
Perks.DEFS = {
	wo     = { name = "Working Overtime", max = 5, per = 0.04, what = "skill-up chance on yellow and green" },
	barter = { name = "Bartering",        max = 2, per = 0.05, what = "off vendor reagents and vendor recipes" },
	chef   = { name = "Master Chef",      max = 5, per = 0.10, what = "extra results per Cooking craft", trade = "Cooking" },
}
-- Perks that need another perk first: perk -> { needs = other perk, rank = ranks needed }. None of the three
-- is known to have one; add an entry here if the Legacy window shows otherwise.
Perks.PREREQ = {}

function Perks:Max(key, trade)
	local d = self.DEFS[key]
	if d.trade and d.trade ~= trade then return 0 end
	return d.max
end

function Perks:Current()
	local c = CPath:Char()
	return { wo = c.wo or 0, barter = c.barter or 0, chef = c.chef or 0 }
end

function Perks:Points(alloc)
	return (alloc.wo or 0) + (alloc.barter or 0) + (alloc.chef or 0)
end

-- The solver options for an allocation.
function Perks:Opts(alloc, trade)
	return {
		wo = (alloc.wo or 0) * self.DEFS.wo.per,
		woMult = CPath.settings.woMult and true or false,
		barter = (alloc.barter or 0) * self.DEFS.barter.per,
		chef = (trade == "Cooking") and (alloc.chef or 0) * self.DEFS.chef.per or 0,
	}
end

local function Allowed(alloc)
	for key, need in pairs(Perks.PREREQ) do
		if (alloc[key] or 0) > 0 and (alloc[need.needs] or 0) < need.rank then return false end
	end
	return true
end

-- Every allocation at or above `floor` (what is already spent) that fits in `cap` points and cannot take one
-- more rank anywhere. More ranks never make a route dearer, so only these need solving.
function Perks:Frontier(floor, cap, trade)
	local out = {}
	local maxWo, maxB, maxC = self:Max("wo", trade), self:Max("barter", trade), self:Max("chef", trade)
	local fw, fb, fc = math.min(floor.wo or 0, maxWo), math.min(floor.barter or 0, maxB), math.min(floor.chef or 0, maxC)
	-- points already spent on a perk that does nothing for this trade still count against the cap
	local idle = self:Points(floor) - (fw + fb + fc)
	for w = fw, maxWo do
		for b = fb, maxB do
			for c = fc, maxC do
				local a = { wo = w, barter = b, chef = c }
				local used = w + b + c + idle
				if used <= math.max(cap, self:Points(floor)) and Allowed(a) then
					local full = used >= cap
					local canGrow = false
					if not full then
						for _, t in ipairs({ { wo = w + 1, barter = b, chef = c }, { wo = w, barter = b + 1, chef = c }, { wo = w, barter = b, chef = c + 1 } }) do
							if t.wo <= maxWo and t.barter <= maxB and t.chef <= maxC and Allowed(t) then canGrow = true end
						end
					end
					if not canGrow then out[#out + 1] = a end
				end
			end
		end
	end
	if #out == 0 then out[1] = { wo = fw, barter = fb, chef = fc } end
	return out
end

function Perks:Same(a, b)
	return (a.wo or 0) == (b.wo or 0) and (a.barter or 0) == (b.barter or 0) and (a.chef or 0) == (b.chef or 0)
end

function Perks:Describe(alloc, trade)
	local parts = {}
	for _, key in ipairs(self.ORDER) do
		local n = alloc[key] or 0
		if n > 0 and self:Max(key, trade) > 0 then parts[#parts + 1] = self.DEFS[key].name .. " " .. n end
	end
	return #parts > 0 and table.concat(parts, ", ") or "no points"
end
