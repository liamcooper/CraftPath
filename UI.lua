-- CraftPath :: UI
-- One window: the controls on top, then tabs (Route, Shopping, Perks, Board, Opportunities, Log) that are
-- all drawn as lines of text with an optional button, so there is one renderer to get right.

local _, CPath = ...
local UI = {}
CPath.UI = UI

local Planner, Perks = CPath.Planner, CPath.Perks
local WIDTH, HEIGHT = 860, 620
local LIST_W = WIDTH - 58
local TABS = { "Route", "Shopping", "Perks", "Board", "Opportunities", "Log" }
local MODES = { { "keep", "Keep" }, { "strict", "Strict" }, { "flip", "Flip" } }
local MODE_HELP = {
	keep = "Keep: nothing you make is sold. The cost is what you spend.",
	strict = "Strict: what you make is sold to a vendor.",
	flip = "Flip: what you make is sold on the auction house where that beats the vendor, after the cut, the lost deposits and a haircut for what will not sell.",
}
local HOW = { vendor = "vendor", ah = "auction", de = "disenchant" }
local DOT = "  \194\183  "   -- a middle dot between facts on one line
local SHORT = { drop = "drop", vendor = "vendor", ["one side"] = "other faction's vendor", reputation = "reputation", quest = "quest", favor = "favour", trainer = "trainer" }
local FROM = { drop = "a drop", vendor = "a vendor", ["one side"] = "the other faction's vendor", reputation = "a reputation reward", quest = "a quest", favor = "a favour reward" }

local frame, ui
local tab = "Route"
local expanded, expandAll = {}, false   -- which steps show their detail

local function col(hex, text) return "|cff" .. hex .. tostring(text) .. "|r" end
local function muted(t) return col("9a8d74", t) end
local function gold(t) return col("ffd100", t) end
local function good(t) return col("4cd137", t) end
local function bad(t) return col("ff5b4b", t) end
local function M(c) return CPath:Money(c) end
local function pct(p) return string.format("%d%%", math.floor(p * 100 + 0.5)) end

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------

-- The game's own tooltip frame: dark fill, soft gold border.
local BACKDROP = {
	bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local function Skin(f, r, g, b, a)
	if f.SetBackdrop then
		f:SetBackdrop(BACKDROP)
		f:SetBackdropColor(r or 0.05, g or 0.04, b or 0.03, a or 0.97)
		f:SetBackdropBorderColor(0.8, 0.66, 0.4, 1)
	else
		local t = f:CreateTexture(nil, "BACKGROUND")
		t:SetAllPoints()
		t:SetColorTexture(r or 0.05, g or 0.04, b or 0.03, a or 0.97)
	end
end

local function NewFrame(kind, name, parent)
	return CreateFrame(kind, name, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
end

-- The game's red button. SetSelected(true) marks the current choice of a group (mode, tab, a switch that
-- is on): white text and the highlight held on.
local function Button(parent, text, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	function b:SetSelected(on)
		if on then
			if self.LockHighlight then self:LockHighlight() end
			if self.SetNormalFontObject then self:SetNormalFontObject(GameFontHighlight) end
		else
			if self.UnlockHighlight then self:UnlockHighlight() end
			if self.SetNormalFontObject then self:SetNormalFontObject(GameFontNormal) end
		end
	end
	return b
end

local function Icon(itemID, spellID)
	if itemID then
		if C_Item and C_Item.GetItemIconByID then
			local ok, t = pcall(C_Item.GetItemIconByID, itemID)
			if ok and t and t ~= 0 then return t end
		end
		if GetItemIcon then
			local ok, t = pcall(GetItemIcon, itemID)
			if ok and t and t ~= 0 then return t end
		end
	end
	if spellID then
		local fn = (C_Spell and C_Spell.GetSpellTexture) or _G.GetSpellTexture
		if fn then
			local ok, t = pcall(fn, spellID)
			if ok and t and t ~= 0 then return t end
		end
	end
	return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function Label(parent, text, template)
	local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
	fs:SetJustifyH("LEFT")
	fs:SetText(text or "")
	return fs
end

local function Tip(widget, text)
	widget:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
		GameTooltip:AddLine(type(text) == "function" and text() or text, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

---------------------------------------------------------------------------
-- Copy window
---------------------------------------------------------------------------

local copyFrame
function UI:ShowCopy(title, text)
	if not copyFrame then
		copyFrame = NewFrame("Frame", "CraftPathCopyFrame", UIParent)
		copyFrame:SetSize(520, 420)
		copyFrame:SetPoint("CENTER")
		copyFrame:SetFrameStrata("DIALOG")
		Skin(copyFrame)
		copyFrame.title = Label(copyFrame, "", "GameFontNormal")
		copyFrame.title:SetPoint("TOPLEFT", 12, -10)
		local hint = Label(copyFrame, muted("Press Ctrl+C to copy, then Escape."))
		hint:SetPoint("TOPLEFT", 12, -28)
		local close = Button(copyFrame, "Close", 70, function() copyFrame:Hide() end)
		close:SetPoint("TOPRIGHT", -8, -8)
		local scroll = CreateFrame("ScrollFrame", "CraftPathCopyScroll", copyFrame, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", 12, -48)
		scroll:SetPoint("BOTTOMRIGHT", -32, 12)
		local edit = CreateFrame("EditBox", nil, scroll)
		edit:SetMultiLine(true)
		edit:SetAutoFocus(false)
		edit:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
		edit:SetWidth(460)
		edit:SetScript("OnEscapePressed", function() copyFrame:Hide() end)
		scroll:SetScrollChild(edit)
		copyFrame.edit = edit
	end
	copyFrame.title:SetText(title)
	copyFrame.edit:SetText(text)
	copyFrame:Show()
	copyFrame.edit:SetFocus()
	copyFrame.edit:HighlightText()
end

---------------------------------------------------------------------------
-- Line renderer
---------------------------------------------------------------------------
-- A line: { text, right, indent, header, muted, item, icon, bg, onClick, action = { label, fn, tip } }
-- bg draws the row as a band (the head of a step); onClick makes the whole row clickable.

local rows = {}
local function Row(i)
	if rows[i] then return rows[i] end
	local row = CreateFrame("Button", nil, ui.content)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetColorTexture(1, 0.9, 0.7, 0.07)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(16, 16)
	row.icon:SetPoint("TOPLEFT", 4, -3)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.left = Label(row)
	row.left:SetJustifyV("TOP")
	if row.left.SetWordWrap then row.left:SetWordWrap(true) end
	row.right = Label(row)
	row.right:SetJustifyH("RIGHT")
	row.action = Button(row, "", 92, nil)
	row.action:SetSize(92, 20)
	row.right:SetPoint("TOPRIGHT", row.action, "TOPLEFT", -8, -2)
	row:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
	row:SetScript("OnEnter", function(self)
		if not self.item then return end
		GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
		local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.item)
		if ok then GameTooltip:Show() else GameTooltip:Hide() end
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	rows[i] = row
	return row
end

function UI:Render(lines)
	local y = 0
	for i, l in ipairs(lines) do
		local row = Row(i)
		local indent = (l.indent or 0) * 16
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", ui.content, "TOPLEFT", indent, -y)
		row:SetWidth(LIST_W - indent)
		row.item, row.onClick = l.item, l.onClick
		if l.bg then row.bg:Show() else row.bg:Hide() end
		local x = l.bg and 6 or 0
		if l.icon then
			row.icon:SetTexture(l.icon)
			row.icon:Show()
			x = 26
		else
			row.icon:Hide()
		end
		row.left:ClearAllPoints()
		row.left:SetPoint("TOPLEFT", x, l.bg and -4 or -1)
		row.action:ClearAllPoints()
		row.action:SetPoint("TOPRIGHT", l.bg and -3 or 0, l.bg and -2 or 0)
		row.left:SetFontObject(l.header and GameFontNormal or GameFontHighlightSmall)
		local text = l.text or ""
		if l.muted then text = muted(text) end
		row.right:SetText(l.right or "")
		local rightW = (l.right and l.right ~= "") and (row.right:GetStringWidth() + 12) or 0
		row.left:SetWidth(LIST_W - indent - rightW - 104 - x)
		row.left:SetText(text)
		if l.action then
			row.action:SetText(l.action.label)
			row.action:SetScript("OnClick", l.action.fn)
			if l.action.tip then Tip(row.action, l.action.tip) else row.action:SetScript("OnEnter", nil); row.action:SetScript("OnLeave", nil) end
			row.action:Show()
		else
			row.action:Hide()
		end
		local h = math.max(l.bg and 22 or (l.header and 20 or 15), (row.left:GetStringHeight() or 12) + (l.bg and 8 or 4))
		row:SetHeight(h)
		row:Show()
		y = y + h + (l.gap or 0)
	end
	for i = #lines + 1, #rows do rows[i]:Hide() end
	ui.content:SetHeight(math.max(y, 10))
end

---------------------------------------------------------------------------
-- Tab contents
---------------------------------------------------------------------------

local function StatusLines(st)
	if st.status == "error" then return { { text = bad(st.error or "Something went wrong."), header = true } } end
	if st.reached then
		return { { text = string.format("%s is already at %d, which is at or past the target of %d.", st.trade, st.from, st.to), header = true } }
	end
	if not st.result then return { { text = "Working out the route...", header = true } } end
end

-- The step's reagents: what you buy, what an earlier step made, and what one craft costs in things you
-- actually buy (a reagent the route makes itself is already paid for where it is made).
local TAG = { vendor = "vendor", ah = "AH", guess = "estimate" }
local function ReagentText(r, rec, made, bought)
	local buy, own, cost = {}, {}, 0
	for _, x in ipairs(rec.reagents or {}) do
		local name = CPath:ItemName(x.id) .. (x.count > 1 and (" x" .. x.count) or "")
		if made[x.id] and not bought[x.id] then
			own[#own + 1] = name
		else
			local unit = r.price and r.price[x.id]
			local tag = r.sources and TAG[r.sources[x.id] or ""] or nil
			if unit then
				name = name .. " " .. M(unit) .. (tag and (" (" .. tag .. ")") or "")
				cost = cost + unit * x.count
			end
			buy[#buy + 1] = name
		end
	end
	local parts = {}
	if #buy > 0 then parts[#parts + 1] = "Buy: " .. table.concat(buy, ", ") end
	if #own > 0 then parts[#parts + 1] = "Made earlier: " .. table.concat(own, ", ") end
	return table.concat(parts, DOT), cost, #own > 0
end

-- What the listings say about buying this much of an item; nil when there is nothing worth saying.
local function DepthNote(d)
	if not d then return nil end
	if d.none then return bad("none listed right now") .. muted(": the price shown is from the last full scan") end
	if d.unread then return bad(string.format("need %d, about %d listed", d.qty, d.listed)) .. muted(": press Check prices at the auction house for the real cost") end
	local parts = {}
	if d.last > d.first * 1.05 then parts[#parts + 1] = "cheapest " .. M(d.first) .. ", dearest you would pay " .. M(d.last) end
	if d.short > 0 then
		parts[#parts + 1] = bad(d.full and (d.short .. " more than are listed") or (d.short .. " beyond the listings read")) .. muted(", priced at the dearest listing")
	end
	if #parts == 0 then return nil end
	return table.concat(parts, DOT)
end

local function PerPoint(v)
	if v < 0 then return "earns " .. M(-v) .. " per point" end
	return M(v) .. " per point"
end

local function RouteLines()
	local st = Planner.state
	local lines = StatusLines(st)
	if lines then return lines end
	lines = {}
	local r = st.result
	local priced = r.totals.spent ~= nil
	local purchase = {}
	for _, p in ipairs(r.purchases or {}) do purchase[p.spell] = p end
	local stop = r["end"] or st.from
	local made, bought = {}, {}
	for _, x in ipairs(r.list and r.list.made or {}) do made[x.id] = true end
	for _, x in ipairs(r.list and r.list.buy or {}) do bought[x.id] = true end
	lines[#lines + 1] = { text = string.format("%s %d to %d", st.trade, st.from, stop), header = true }
	if not st.known then lines[#lines + 1] = { text = "This character has not learned " .. st.trade .. ". The route starts from skill 1.", muted = true } end
	if stop < st.to then
		lines[#lines + 1] = { text = bad(string.format("The recipes this character can get stop giving skill-ups at %d, short of %d.", stop, st.to)) }
	end
	if st.known and st.max and st.max < st.to and st.max > 0 then
		lines[#lines + 1] = { text = string.format("Your skill is capped at %d until you train the next rank at a trainer.", st.max), muted = true }
	end
	if not priced then
		lines[#lines + 1] = { text = bad("No auction prices for this profession's materials yet. Run an Auctionator scan at the auction house to see costs.") }
	end
	-- materials there are not enough of, on one line (the Shopping tab has the detail)
	local short, unread = {}, false
	for id, d in pairs(r.depth or {}) do
		if d.unread then unread = true end
		if d.none then short[#short + 1] = CPath:ItemName(id) .. " (none listed)"
		elseif d.unread then short[#short + 1] = string.format("%s (need %d, about %d listed)", CPath:ItemName(id), d.qty, d.listed)
		elseif (d.short or 0) > 0 then short[#short + 1] = string.format("%s (need %d, %d listed)", CPath:ItemName(id), d.qty, d.covered) end
	end
	if #short > 0 then
		table.sort(short)
		local extra = #short > 5 and (", and " .. (#short - 5) .. " more") or ""
		for i = #short, 6, -1 do short[i] = nil end
		lines[#lines + 1] = { text = bad("Not enough on the auction house: ") .. table.concat(short, ", ") .. extra .. "." }
	end
	if unread then
		lines[#lines + 1] = { text = "Costs below assume everything sells at the cheapest listing. Press Check prices at the auction house and the route is re-worked at what these quantities really cost.", muted = true }
	end
	lines[#lines + 1] = { text = "Click a step to see what to buy and why it was chosen.", muted = true, gap = 6,
		action = { label = expandAll and "Less detail" or "All detail", fn = function() expandAll = not expandAll; UI:Refresh() end } }
	for k, s in ipairs(r.steps) do
		local rec, info = r.recipes[s.spell], r.stepInfo[k]
		local name = CPath:RecipeName(s.spell, rec.makes)
		local matsText, matsCost, usesOwn = ReagentText(r, rec, made, bought)
		local net = priced and (s.crafts * (matsCost - info.sale)) or nil
		local key = s.spell .. ":" .. s.from
		local open = expandAll or expanded[key]
		local line = { text = string.format("%s   %s", gold(s.from .. "-" .. s.to), s.rod and ("Make one " .. name .. " (tool for later enchants)") or (name .. muted("  x" .. s.crafts))),
			right = net and (net < 0 and good("earns " .. M(-net)) or M(net)) or nil, item = rec.makes and rec.makes.id,
			icon = Icon(rec.makes and rec.makes.id, s.spell), bg = true,
			onClick = function() expanded[key] = not expanded[key] or nil; UI:Refresh() end }
		if st.known then
			line.action = { label = "Craft " .. s.crafts, fn = function() CPath.Execute:Craft(st, k) end,
				tip = "Crafts as many of this step as the mats in your bags allow." }
		end
		lines[#lines + 1] = line
		local p = purchase[s.spell]
		local recipeLine
		if priced then
			local facts = {}
			if s.rod then facts[#facts + 1] = "Tool, kept"
			elseif s.keep then facts[#facts + 1] = "Kept for later steps"
			elseif info.sale > 0 and rec.makes then
				local how = r.how[rec.makes.id] or "vendor"
				local de = how == "de" and st.stats and st.stats.deRange and st.stats.deRange[rec.makes.id]
				if how == "de" then facts[#facts + 1] = "Disenchants for " .. M(info.sale) .. (de and (" (" .. M(de.lo) .. " to " .. M(de.hi) .. ")") or "")
				else facts[#facts + 1] = "Sells " .. M(info.sale) .. " (" .. (HOW[how] or how) .. ")" end
			elseif r.recovery == "keep" then facts[#facts + 1] = "Not sold (Keep mode)"
			else facts[#facts + 1] = "Cannot be sold" end
			if not s.rod then
				facts[#facts + 1] = pct(info.p) .. " skill-up"
				if info.perPoint then facts[#facts + 1] = PerPoint(info.perPoint) end
			end
			if p and (p.fee or 0) > 0 then facts[#facts + 1] = "Train " .. M(p.fee) end
			if p and (p.price or 0) > 0 and not (p.via == "ah" or p.limited) then facts[#facts + 1] = "Recipe " .. M(p.price) .. " (" .. (SHORT[rec.source or ""] or "?") .. ")" end
			lines[#lines + 1] = { text = table.concat(facts, DOT), muted = true, indent = 2 }
			if open and matsText ~= "" then lines[#lines + 1] = { text = matsText, muted = true, indent = 2 } end
			if open and info.alt and not s.rod then
				local alt = info.alt
				local altName = CPath:RecipeName(alt.spell, alt.makes)
				local text
				if info.perPoint and alt.perPoint >= info.perPoint then
					text = "Next best: " .. altName .. ", " .. PerPoint(alt.perPoint)
				else
					local reason
					if s.keep then reason = "You need these for later steps."
					elseif (alt.once or 0) > 0 then reason = "Its recipe costs " .. M(alt.once) .. " to get."
					elseif usesOwn then reason = "This step uses materials you already made."
					else reason = "This step is cheaper over the whole route." end
					text = "Why not " .. altName .. " (" .. PerPoint(alt.perPoint) .. ")? " .. reason
				end
				lines[#lines + 1] = { text = text, muted = true, indent = 2 }
			end
		elseif p and (p.fee or 0) > 0 then
			lines[#lines + 1] = { text = "Train " .. M(p.fee), muted = true, indent = 2 }
		end
		if p and (p.price or 0) > 0 and (p.via == "ah" or p.limited or not priced) then
			local text
			if p.via == "ah" then text = "Recipe: " .. M(p.price) .. " on the AH (normally " .. (FROM[rec.source or ""] or "from elsewhere") .. ")"
			elseif p.limited then text = "Recipe: " .. M(p.price) .. " from a limited-stock vendor"
			else text = "Recipe: " .. M(p.price) .. " (" .. (SHORT[rec.source or ""] or "?") .. ")" end
			recipeLine = { text = text, indent = 2, item = rec.taught_by }
			if p.via == "ah" or p.limited then
				recipeLine.action = { label = "Can't get it", fn = function() Planner:MarkExcluded(s.spell, true) end,
					tip = "Plans the route again without this recipe: use this if it is sold out or no longer listed." }
			end
			lines[#lines + 1] = recipeLine
		end
		lines[#lines].gap = 4
	end
	-- Materials the steps use that are cheaper to make than to buy, beyond what the steps themselves make.
	local extra = {}
	for id, units in pairs(r.list and r.list.more or {}) do
		local spell, rec
		for sp, x in pairs(r.recipes) do if x.makes and x.makes.id == id then spell, rec = sp, x end end
		if not spell and r.parts and r.parts[id] then spell, rec = r.parts[id].spell, r.parts[id] end
		if rec and rec.makes then extra[#extra + 1] = { id = id, units = units, crafts = math.ceil(units / rec.makes.count), spell = spell, rec = rec } end
	end
	if #extra > 0 then
		table.sort(extra, function(a, b) return a.id < b.id end)
		lines[#lines + 1] = { text = "Also make these materials, before the steps that use them", header = true }
		for _, e in ipairs(extra) do
			local line = { text = CPath:ItemName(e.id) .. muted("  x" .. e.units), item = e.id, icon = Icon(e.id), bg = true }
			if st.known and e.spell then
				line.action = { label = "Craft " .. e.crafts, fn = function() CPath.Execute:CraftSpell(st, e.spell, e.crafts, e.rec) end,
					tip = "Crafts as many as the mats in your bags allow." }
			end
			lines[#lines + 1] = line
			local from = ReagentText(r, e.rec, made, bought)
			lines[#lines + 1] = { text = (from ~= "" and (from .. DOT) or "") .. "no skill-ups counted", muted = true, indent = 2 }
		end
		lines[#lines].gap = 6
	end
	if priced then
		lines[#lines + 1] = { text = "Totals", header = true }
		lines[#lines + 1] = { text = "Materials and recipes to buy", right = M(r.totals.spent), indent = 1 }
		if (r.totals.oneTime or 0) > 0 then lines[#lines + 1] = { text = "of which training and recipes", right = M(r.totals.oneTime), indent = 2, muted = true } end
		if r.recovery ~= "keep" then lines[#lines + 1] = { text = "Back from what you make", right = good(M(r.totals.resale or 0)), indent = 1 } end
		lines[#lines + 1] = { text = "Net cost", right = gold(M(r.net)), indent = 1, gap = 6 }
	end
	if st.options and #st.options > 0 then
		lines[#lines + 1] = { text = "Recipes that would save gold (not on the AH or at a vendor right now)", header = true }
		for _, o in ipairs(st.options) do
			local name = CPath:RecipeName(o.spell, o.makes)
			local where = SHORT[o.source or ""] or (o.source or "?")
			local text = string.format("%s (%s, skill %d): saves %s", name, where, o.learn or 0, o.gold and M(o.gold) or (o.crafts .. " crafts"))
			if o.recipePrice and o.gold then
				text = text .. DOT .. string.format("recipe %s on the AH, so %s after buying it", M(o.recipePrice), M(o.gold - o.recipePrice))
			end
			lines[#lines + 1] = { text = text, indent = 1, item = o.recipeItem,
				action = { label = "I have it", fn = function() Planner:MarkOwned(o.spell, true) end, tip = "Plans the route as if this character knows the recipe." } }
		end
	elseif st.status ~= "done" then
		lines[#lines + 1] = { text = "Checking which other recipes would save gold...", muted = true }
	end
	local barred = CPath:Char().excluded[st.trade]
	if barred and next(barred) then
		lines[#lines + 1] = { text = "Recipes you said you cannot get", header = true }
		for spell in pairs(barred) do
			lines[#lines + 1] = { text = CPath:SpellName(spell) or ("recipe " .. spell), indent = 1,
				action = { label = "Undo", fn = function() Planner:MarkExcluded(spell, false) end } }
		end
	end
	local marks = CPath:Char().owned[st.trade]
	if marks and next(marks) then
		lines[#lines + 1] = { text = "Recipes you marked as owned", header = true }
		for spell in pairs(marks) do
			lines[#lines + 1] = { text = CPath:SpellName(spell) or ("recipe " .. spell), indent = 1,
				action = { label = "Unmark", fn = function() Planner:MarkOwned(spell, false) end } }
		end
	end
	return lines
end

local function ShoppingLines()
	local st = Planner.state
	local lines = StatusLines(st)
	if lines then return lines end
	lines = {}
	local list = CPath.Shopping:Build(st)
	local function section(title, rows, total, empty)
		lines[#lines + 1] = { text = title, header = true, right = (#rows > 0 and total) and M(total) or nil }
		if #rows == 0 then lines[#lines + 1] = { text = empty, muted = true, indent = 1 } end
		for _, row in ipairs(rows) do
			local text = string.format("%s x%d", CPath:ItemName(row.id), row.count)
			if row.recipe then text = text .. muted("  (recipe for the route)") end
			if row.have > 0 then text = text .. muted(string.format("  (need %d, have %d)", row.want, row.have)) end
			local d = st.result.depth and st.result.depth[row.id]
			lines[#lines + 1] = { text = text, indent = 1, item = row.id, icon = Icon(row.id),
				right = row.unit and (((d and d.avg and d.last > d.first * 1.005) and "average " or "") .. M(row.unit) .. " each = " .. M(row.unit * row.count)) or muted("no price") }
			local note = DepthNote(d)
			if note then lines[#lines + 1] = { text = note, indent = 2, muted = true } end
		end
		lines[#lines].gap = 6
	end
	section("Buy at the auction house", list.ah, list.ahCost, "Nothing: you have it all, or the rest comes from vendors.")
	do
		local read, total = 0, 0
		for id in pairs(Planner.AhNeeds(st.result)) do
			total = total + 1
			if CPath.Depth:Age(id) then read = read + 1 end
		end
		if total > 0 and read < total then
			lines[#lines + 1] = { text = string.format("%d of %d materials are priced at the cheapest listing only, however many you need. Press Check prices at the auction house to read the real listings.", total - read, total), muted = true, indent = 1, gap = 6 }
		end
	end
	section("Buy from a vendor", list.vendor, list.vendorCost, "Nothing.")
	if #list.vendor > 0 then
		lines[#lines + 1] = { text = "Open a vendor that sells these and CraftPath shows a button above the vendor window to buy what is missing.", muted = true, indent = 1, gap = 6 }
	end
	if #list.recipes > 0 then
		lines[#lines + 1] = { text = "Recipes to train or buy", header = true }
		for _, p in ipairs(list.recipes) do
			local bits = {}
			if (p.fee or 0) > 0 then bits[#bits + 1] = "train " .. M(p.fee) end
			if (p.price or 0) > 0 then bits[#bits + 1] = "buy " .. M(p.price) end
			local where = p.via == "ah" and "auction house, on the list above" or (p.limited and "limited-stock vendor" or (p.source or "?"))
			if p.got then where = where .. ", already in your bags" end
			lines[#lines + 1] = { text = CPath:RecipeName(p.spell, p.makes) .. muted("  (" .. where .. ")"), indent = 1, right = table.concat(bits, ", "), item = p.item }
		end
		lines[#lines].gap = 6
	end
	if #list.have > 0 then
		lines[#lines + 1] = { text = "Already in your bags or bank", header = true }
		for _, row in ipairs(list.have) do
			lines[#lines + 1] = { text = string.format("%s x%d", CPath:ItemName(row.id), row.have), indent = 1, muted = true, item = row.id }
		end
		lines[#lines + 1] = { text = "Bank counts are from the last time the game saw your bank.", muted = true, indent = 1 }
	end
	return lines
end

local function PerkLines()
	local st = Planner.state
	local lines = StatusLines(st)
	if lines then return lines end
	lines = {}
	local r = st.result
	if r.net == nil then return { { text = "The comparison needs auction prices. Run an Auctionator scan first.", header = true } } end
	local function row(title, res, extra)
		lines[#lines + 1] = { text = title, right = res.net and (M(res.net) .. muted("  " .. res.totals.crafts .. " crafts")) or "?", header = true }
		if extra then lines[#lines + 1] = extra end
	end
	local spent = Perks:Points(st.alloc)
	lines[#lines + 1] = { text = "Net cost of " .. st.trade .. " " .. st.from .. " to " .. (r["end"] or st.to) .. ", with and without Legacy points", header = true, gap = 6 }
	if not st.zero then
		lines[#lines + 1] = { text = "Comparing allocations...", muted = true }
		return lines
	end
	row("No points spent", st.zero)
	if spent > 0 then row("As spent now (" .. Perks:Describe(st.alloc, st.trade) .. ")", r) end
	if st.best and st.bestAlloc then
		local base = st.zero.net
		local same = Perks:Same(st.bestAlloc, st.alloc)
		local pts = Perks:Points(st.bestAlloc)
		local title = (spent > 0 and "Best use of what is left" or "Best points spent") .. " (" .. Perks:Describe(st.bestAlloc, st.trade) .. ")"
		row(title, st.best)
		if st.best.net and base then
			local saved = base - st.best.net
			local text = string.format("Saves %s against no points: %s per point over %d points.", M(saved), pts > 0 and M(saved / pts) or "-", pts)
			lines[#lines + 1] = { text = text, indent = 1,
				action = (not same) and { label = "Use this", fn = function()
					CPath:SetChar("wo", st.bestAlloc.wo); CPath:SetChar("barter", st.bestAlloc.barter); CPath:SetChar("chef", st.bestAlloc.chef)
				end, tip = "Sets this character's perk ranks to this allocation, so the Route tab shows that route." } or nil }
		end
		if same and spent > 0 then lines[#lines + 1] = { text = "Your current ranks are already the best use of the points allowed.", muted = true, indent = 1 } end
		lines[#lines].gap = 6
		if st.solo and #st.solo > 0 then
			lines[#lines + 1] = { text = "Where the saving comes from (each perk on its own)", header = true }
			for _, s in ipairs(st.solo) do
				local d = Perks.DEFS[s.key]
				local saved = (base and s.net) and (base - s.net) or nil
				lines[#lines + 1] = { text = string.format("%s %d: %s", d.name, s.rank, d.what), indent = 1,
					right = saved and (M(saved) .. muted(" saved, " .. CPath:Money(saved / s.rank) .. " per point")) or "?" }
			end
			lines[#lines].gap = 6
		end
	end
	lines[#lines + 1] = { text = string.format("The planner may spend up to %d of this character's 16 points. Lower \"May spend\" above to hold points back for other perks.", st.cap), muted = true }
	lines[#lines + 1] = { text = "Working Overtime is counted as " .. (CPath.settings.woMult and "multiplying the skill-up chance (50% becomes 60% at rank 5)" or "adding to the skill-up chance (50% becomes 70% at rank 5)") .. ". The Log tab shows which fits once you have crafted enough.", muted = true }
	lines[#lines + 1] = { text = "Routes are found by a step-by-step search, so two allocations that are nearly equal can come out a little out of order.", muted = true }
	return lines
end

local function BoardLines()
	local b = Planner.board
	local lines = {}
	local run = { label = b and "Work out again" or "Work it out", fn = function() Planner:Board() end }
	lines[#lines + 1] = { text = "Net cost of every profession for this character, in " .. (CPath.settings.recovery) .. " mode with the perks set above", header = true, action = run, gap = 6 }
	if not b then
		lines[#lines + 1] = { text = "Press \"Work it out\" to compare all eight professions. It takes a few seconds.", muted = true }
		return lines
	end
	if b.status == "error" then lines[#lines + 1] = { text = bad(b.error) }; return lines end
	local function cell(c)
		if not c then return "?" end
		if c.reached then return good("done") end
		if c.net == nil then return muted("no prices") end
		return M(c.net)
	end
	local sorted = {}
	for _, row in ipairs(b.rows) do sorted[#sorted + 1] = row end
	table.sort(sorted, function(x, y)
		local a, c = x.cells[300] and x.cells[300].net, y.cells[300] and y.cells[300].net
		if a and c then return a < c end
		return (a ~= nil) and (c == nil)
	end)
	for _, row in ipairs(sorted) do
		local c150, c300 = row.cells[150], row.cells[300]
		local text = string.format("%s%s", gold(row.trade), row.known and muted("  (at " .. row.from .. ")") or "")
		local right = "to 150: " .. cell(c150) .. "    to 300: " .. cell(c300)
		lines[#lines + 1] = { text = text, right = right,
			action = { label = "Open", fn = function() CPath:SetChar("trade", row.trade); UI:SetTab("Route") end } }
		local notes = {}
		if c300 and c300.stop and c300.stop < 300 then notes[#notes + 1] = "trainer and vendor recipes stop at " .. c300.stop end
		if row.wanted and row.priced and row.priced < row.wanted then notes[#notes + 1] = (row.wanted - row.priced) .. " of " .. row.wanted .. " items have no auction price" end
		if c300 and c300.crafts then notes[#notes + 1] = c300.crafts .. " crafts to 300" end
		if #notes > 0 then lines[#lines + 1] = { text = table.concat(notes, "; ") .. ".", muted = true, indent = 2 } end
	end
	if b.status == "working" then lines[#lines + 1] = { text = string.format("Working... %d of %d", #b.rows, #CPath.TRADES), muted = true } end
	if b.recovery ~= CPath.settings.recovery then lines[#lines + 1] = { text = "These figures are for " .. b.recovery .. " mode. Work it out again for the current mode.", muted = true } end
	return lines
end

local function OpportunityLines()
	local st = Planner.state
	local lines = StatusLines(st)
	if lines then return lines end
	lines = {}
	local list = Planner:Opportunities() or {}
	lines[#lines + 1] = { text = st.trade .. " recipes worth more than their mats right now", header = true }
	lines[#lines + 1] = { text = "Sold the best way open to them: vendor, auction house after the cut and lost deposits" .. (CPath.settings.de and ", or disenchanted" or "") .. ". Auction sales are capped by how many are listed.", muted = true, gap = 6 }
	if #list == 0 then
		lines[#lines + 1] = { text = "None at current prices.", indent = 1 }
		return lines
	end
	for i, e in ipairs(list) do
		if i > 60 then break end
		local name = CPath:RecipeName(e.spell, e.makes)
		local tag
		if e.learn > st.from then tag = muted("  needs skill " .. e.learn)
		elseif e.p >= 1 then tag = col("ff8040", "  skill-up certain")
		elseif e.p > 0 then tag = col("ffff00", "  skill-up " .. pct(e.p))
		else tag = muted("  no skill-up") end
		if not e.usable then tag = tag .. muted("  recipe from " .. (e.source or "?")) end
		lines[#lines + 1] = { text = name .. tag, indent = 1, item = e.makes and e.makes.id, icon = Icon(e.makes and e.makes.id, e.spell),
			right = good("+" .. M(e.profit)) .. muted("  mats " .. CPath:Money(e.cost) .. ", back " .. CPath:Money(e.sale) .. " " .. (HOW[e.how] or e.how)) }
	end
	return lines
end

local BUILDERS = {
	Route = RouteLines, Shopping = ShoppingLines, Perks = PerkLines, Board = BoardLines,
	Opportunities = OpportunityLines, Log = function() return CPath.SkillLog:Lines() end,
}

---------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------

local function Summary()
	local st = Planner.state
	local r = st.result
	if st.status == "error" then return bad(st.error or "") end
	if st.reached then return "Already at the target." end
	if not r then return "Working out the route..." end
	local a
	if r.net then
		a = "Net cost " .. gold(M(r.net))
		if r.recovery ~= "keep" then a = a .. muted(" = spend ") .. M(r.totals.spent) .. muted(" less ") .. M(r.totals.resale or 0) .. muted(" back") end
		a = a .. muted("  -  ") .. r.totals.crafts .. " crafts"
	else
		a = r.totals.crafts .. " crafts. " .. bad("No auction prices yet.")
	end
	local b = ""
	if st.zero and st.best and st.zero.net and st.best.net and r.net then
		if Perks:Points(st.alloc) == 0 then
			if Perks:Points(st.bestAlloc) > 0 and st.best.net < st.zero.net then
				b = "With no points: " .. M(st.zero.net) .. ". Best points spent (" .. Perks:Describe(st.bestAlloc, st.trade) .. "): " .. M(st.best.net) .. ", saving " .. good(M(st.zero.net - st.best.net)) .. ". See the Perks tab."
			else
				b = "Legacy points would not make this route cheaper."
			end
		else
			b = "With no points this would be " .. M(st.zero.net) .. ": your ranks save " .. good(M(st.zero.net - r.net)) .. "."
			if not Perks:Same(st.bestAlloc, st.alloc) and st.best.net < r.net then b = b .. " Spending the rest could save another " .. good(M(r.net - st.best.net)) .. "." end
		end
	elseif st.status ~= "done" then
		b = muted("Comparing Legacy point allocations...")
	end
	return a, b
end

local function StatusText()
	local st = Planner.state
	local s = st.stats
	local bits = {}
	if s then
		if not s.auctionator then bits[#bits + 1] = bad("Auctionator is not loaded")
		elseif s.priced == 0 then bits[#bits + 1] = bad("no auction prices: scan with Auctionator")
		else bits[#bits + 1] = string.format("%d of %d items have an auction price", s.priced, s.wanted) end
		if s.dePending > 0 then bits[#bits + 1] = s.dePending .. " items still loading for disenchant values" end
	end
	if Planner:Checking() then
		local done, total = CPath.Depth:Progress()
		bits[#bits + 1] = total and string.format("checking prices %d/%d", done, total) or "checking prices"
	elseif st.result then
		local read, total = 0, 0
		for id in pairs(Planner.AhNeeds(st.result)) do
			total = total + 1
			if CPath.Depth:Age(id) then read = read + 1 end
		end
		if total > 0 then bits[#bits + 1] = string.format("listings read for %d of %d materials", read, total) end
	end
	return muted(table.concat(bits, "  -  "))
end

function UI:RefreshControls()
	if not frame then return end
	local c, s = CPath:Char(), CPath.settings
	ui.trade:SetText(c.trade)
	-- never overwrite the box while it is being typed in
	if not (ui.target.HasFocus and ui.target:HasFocus()) then ui.target:SetText(tostring(c.target)) end
	for _, m in ipairs(MODES) do
		ui.mode[m[1]]:SetSelected(s.recovery == m[1])
	end
	ui.de:SetText("Disenchant: " .. (s.de and "on" or "off"))
	ui.de:SetSelected(s.de)
	ui.optsBtn:SetSelected(s.showOptions)
	-- with the panel shut, say what is set in it
	local note = {}
	local perks = Perks:Describe(Perks:Current(), c.trade)
	note[#note + 1] = perks == "no points" and "No Legacy points" or perks
	if s.de then note[#note + 1] = "Disenchant on" end
	if s.recovery == "flip" then note[#note + 1] = "Listing " .. s.listHours .. "h" end
	ui.optsNote:SetText(s.showOptions and "" or muted(table.concat(note, DOT)))
	UI:Layout()
	ui.hours:SetText("Listing: " .. s.listHours .. "h")
	for _, key in ipairs(Perks.ORDER) do
		local d, w = Perks.DEFS[key], ui.perk[key]
		local max = Perks:Max(key, c.trade)
		local text = string.format("%s %d/%d", d.name, c[key] or 0, d.max)
		w.label:SetText(max == 0 and muted(text) or text)
	end
	ui.cap:SetText("May spend " .. c.cap)
	ui.woMode:SetText("Working Overtime: " .. (s.woMult and "multiplied" or "added"))
	for _, name in ipairs(TABS) do
		ui.tabs[name]:SetSelected(tab == name)
	end
end

function UI:Refresh()
	if not (frame and frame:IsShown()) then return end
	self:RefreshControls()
	local headline, detail = Summary()
	ui.summary:SetText(headline or "")
	ui.sub:SetText(detail or "")
	ui.status:SetText(StatusText())
	local ok, lines = pcall(BUILDERS[tab])
	if not ok then lines = { { text = bad("CraftPath could not draw this tab: " .. tostring(lines)) } } end
	self:Render(lines)
end

function UI:Soon()
	CPath:Debounce("ui", 0.05, function() UI:Refresh() end)
end

function UI:SetTab(name)
	tab = name
	if ui and ui.scroll.SetVerticalScroll then ui.scroll:SetVerticalScroll(0) end
	if name == "Board" and not Planner.board then Planner:Board() end
	self:Refresh()
end

local function Stepper(parent, getText, onMinus, onPlus)
	local w = {}
	w.minus = Button(parent, "-", 22, onMinus)
	w.label = Label(parent, "")
	w.plus = Button(parent, "+", 22, onPlus)
	w.label:SetPoint("LEFT", w.minus, "RIGHT", 4, 0)
	w.plus:SetPoint("LEFT", w.label, "RIGHT", 4, 0)
	return w
end

-- Places everything under the first row, lower when the options panel is open.
function UI:Layout()
	if not frame then return end
	local open = CPath.settings.showOptions and true or false
	local y = open and -126 or -72
	if open then ui.opts:Show() else ui.opts:Hide() end
	ui.summary:ClearAllPoints()
	ui.summary:SetPoint("TOPLEFT", 14, y)
	ui.sub:ClearAllPoints()
	ui.sub:SetPoint("TOPLEFT", 14, y - 21)
	ui.tabs[TABS[1]]:ClearAllPoints()
	ui.tabs[TABS[1]]:SetPoint("TOPLEFT", 14, y - 42)
	ui.well:ClearAllPoints()
	ui.well:SetPoint("TOPLEFT", 12, y - 68)
	ui.well:SetPoint("BOTTOMRIGHT", -12, 44)
end

local function Build()
	frame = NewFrame("Frame", "CraftPathFrame", UIParent)
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("HIGH")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetClampedToScreen(true)
	Skin(frame)
	if UISpecialFrames then table.insert(UISpecialFrames, "CraftPathFrame") end
	ui = { mode = {}, perk = {}, tabs = {} }

	local band = frame:CreateTexture(nil, "ARTWORK")
	band:SetPoint("TOPLEFT", 4, -4)
	band:SetPoint("TOPRIGHT", -4, -4)
	band:SetHeight(29)
	band:SetColorTexture(1, 0.82, 0, 0.07)
	local title = Label(frame, "CraftPath", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 14, -9)
	local sub = Label(frame, muted("cheapest route to a profession skill, in net gold"))
	sub:SetPoint("LEFT", title, "RIGHT", 10, -1)
	local close = Button(frame, "Close", 60, function() frame:Hide() end)
	close:SetPoint("TOPRIGHT", -8, -6)

	-- Row 1: profession, target, mode
	local y1 = -42
	ui.trade = Button(frame, "", 120, function() if ui.menu:IsShown() then ui.menu:Hide() else ui.menu:Show() end end)
	ui.trade:SetPoint("TOPLEFT", 14, y1)
	Tip(ui.trade, "Pick a profession. It does not need to be learned on this character.")
	ui.menu = NewFrame("Frame", nil, frame)
	ui.menu:SetFrameStrata("DIALOG")
	ui.menu:SetSize(130, #CPath.TRADES * 22 + 8)
	ui.menu:SetPoint("TOPLEFT", ui.trade, "BOTTOMLEFT", 0, -2)
	Skin(ui.menu, 0.04, 0.03, 0.02, 1)
	ui.menu:Hide()
	for i, key in ipairs(CPath.TRADES) do
		local b = Button(ui.menu, key, 122, function() ui.menu:Hide(); CPath:SetChar("trade", key) end)
		b:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 22)
	end

	local tl = Label(frame, "Target")
	tl:SetPoint("LEFT", ui.trade, "RIGHT", 14, 0)
	ui.target = CreateFrame("EditBox", "CraftPathTargetBox", frame, "InputBoxTemplate")
	ui.target:SetSize(40, 20)
	ui.target:SetAutoFocus(false)
	ui.target:SetNumeric(true)
	ui.target:SetMaxLetters(3)
	ui.target:SetPoint("LEFT", tl, "RIGHT", 10, 0)
	-- Typing a number and pressing Enter, or clicking anywhere else, sets the target. Escape puts the old one back.
	local cancelled = false
	local function commit()
		local n = tonumber(ui.target:GetText())
		if n and not cancelled then
			n = math.max(2, math.min(300, math.floor(n)))
			if n ~= CPath:Char().target then CPath:SetChar("target", n) end
		end
		cancelled = false
		ui.target:SetText(tostring(CPath:Char().target))
	end
	ui.target:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	ui.target:SetScript("OnEscapePressed", function(self) cancelled = true; self:ClearFocus() end)
	ui.target:SetScript("OnEditFocusLost", commit)
	ui.target:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	Tip(ui.target, "Type any skill from 2 to 300 and press Enter.")
	local b150 = Button(frame, "150", 40, function() CPath:SetChar("target", 150) end)
	b150:SetPoint("LEFT", ui.target, "RIGHT", 6, 0)
	local b300 = Button(frame, "300", 40, function() CPath:SetChar("target", 300) end)
	b300:SetPoint("LEFT", b150, "RIGHT", 2, 0)

	local ml = Label(frame, "Recovery")
	ml:SetPoint("LEFT", b300, "RIGHT", 16, 0)
	local prev = ml
	for i, m in ipairs(MODES) do
		local b = Button(frame, m[2], 62, function() CPath:Set("recovery", m[1]) end)
		b:SetPoint("LEFT", prev, "RIGHT", i == 1 and 8 or 2, 0)
		Tip(b, MODE_HELP[m[1]])
		ui.mode[m[1]] = b
		prev = b
	end
	-- Everything set once and then left alone lives in a panel that opens under the first row.
	ui.optsBtn = Button(frame, "Options", 80, function() CPath:Set("showOptions", not CPath.settings.showOptions) end)
	ui.optsBtn:SetPoint("LEFT", prev, "RIGHT", 16, 0)
	Tip(ui.optsBtn, "Legacy perk ranks, disenchanting, auction listing length and the Working Overtime formula.")
	ui.optsNote = Label(frame, "")
	ui.optsNote:SetPoint("LEFT", ui.optsBtn, "RIGHT", 10, 0)
	ui.optsNote:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
	ui.opts = CreateFrame("Frame", nil, frame)
	ui.opts:SetPoint("TOPLEFT", 12, -68)
	ui.opts:SetSize(WIDTH - 24, 54)
	ui.de = Button(ui.opts, "", 124, function() CPath:Set("de", not CPath.settings.de) end)
	ui.de:SetPoint("TOPLEFT", 2, -30)
	Tip(ui.de, "Counts what a green or better result is worth disenchanted, when that beats selling it. Only turn this on if you have an enchanter to send things to. It is an average, not a promise.")
	ui.hours = Button(ui.opts, "", 104, function()
		local h = CPath.settings.listHours
		CPath:Set("listHours", h == 24 and 2 or (h == 2 and 8 or 24))
	end)
	ui.hours:SetPoint("LEFT", ui.de, "RIGHT", 4, 0)
	Tip(ui.hours, "How long you list auctions for in Flip mode. The deposit you lose on things that do not sell is 60% of vendor value for 24 hours, less for shorter listings.")

	-- Row 2: perks
	local pl = Label(ui.opts, "Legacy perks")
	pl:SetPoint("TOPLEFT", 2, -7)
	local anchor, first = pl, true
	local function perkStep(key, delta)
		return function()
			local c = CPath:Char()
			local n = math.max(0, math.min(Perks.DEFS[key].max, (c[key] or 0) + delta))
			if n ~= c[key] then CPath:SetChar(key, n) end
		end
	end
	for _, key in ipairs(Perks.ORDER) do
		local w = Stepper(ui.opts, nil, perkStep(key, -1), perkStep(key, 1))
		w.minus:SetPoint("LEFT", anchor, "RIGHT", first and 10 or 14, 0)
		Tip(w.minus, Perks.DEFS[key].name .. ": " .. Perks.DEFS[key].what .. ". Set this to the rank this character has.")
		ui.perk[key] = w
		anchor, first = w.plus, false
	end
	local capMinus = Button(ui.opts, "-", 22, function() CPath:SetChar("cap", math.max(0, CPath:Char().cap - 1)) end)
	capMinus:SetPoint("LEFT", anchor, "RIGHT", 18, 0)
	ui.cap = Label(ui.opts, "")
	ui.cap:SetPoint("LEFT", capMinus, "RIGHT", 4, 0)
	local capPlus = Button(ui.opts, "+", 22, function() CPath:SetChar("cap", math.min(16, CPath:Char().cap + 1)) end)
	capPlus:SetPoint("LEFT", ui.cap, "RIGHT", 4, 0)
	Tip(capMinus, "How many of this character's 16 Legacy points the planner may spend on these perks when it works out the best allocation.")
	ui.woMode = Button(ui.opts, "", 220, function() CPath:Set("woMult", not CPath.settings.woMult) end)
	ui.woMode:SetPoint("LEFT", ui.hours, "RIGHT", 4, 0)
	Tip(ui.woMode, "Whether Working Overtime adds its bonus to the skill-up chance (50% becomes 70% at rank 5) or multiplies it (50% becomes 60%). The game's wording does not say. The Log tab works out which fits from your own crafting.")

	-- Summary
	ui.summary = Label(frame, "", "GameFontHighlightLarge")
	ui.summary:SetWidth(WIDTH - 28)
	ui.sub = Label(frame, "")
	ui.sub:SetWidth(WIDTH - 28)

	-- Tabs
	local px
	for i, name in ipairs(TABS) do
		local b = Button(frame, name, 104, function() UI:SetTab(name) end)
		if i > 1 then b:SetPoint("LEFT", px, "RIGHT", 2, 0) end
		ui.tabs[name] = b
		px = b
	end

	-- List
	local well = NewFrame("Frame", nil, frame)
	ui.well = well
	Skin(well, 0.03, 0.025, 0.02, 1)
	ui.scroll = CreateFrame("ScrollFrame", "CraftPathScroll", well, "UIPanelScrollFrameTemplate")
	ui.scroll:SetPoint("TOPLEFT", 8, -6)
	ui.scroll:SetPoint("BOTTOMRIGHT", -28, 6)
	ui.content = CreateFrame("Frame", nil, ui.scroll)
	ui.content:SetSize(LIST_W, 10)
	ui.scroll:SetScrollChild(ui.content)

	-- Bottom bar
	local list = Button(frame, "Auctionator list", 130, function()
		local ok, msg = CPath.Shopping:CreateList(Planner.state)
		CPath:Print(msg)
	end)
	list:SetPoint("BOTTOMLEFT", 12, 12)
	Tip(list, "Creates an Auctionator shopping list of what this route needs from the auction house, with quantities, less what is in your bags and bank. Replaces any list with the same name.")
	local copy = Button(frame, "Copy as text", 110, function()
		if not Planner.state.result then return end
		UI:ShowCopy("CraftPath: " .. Planner.state.trade, CPath.Shopping:Text(Planner.state))
	end)
	copy:SetPoint("LEFT", list, "RIGHT", 4, 0)
	local refresh = Button(frame, "Refresh", 80, function() Planner:Plan() end)
	refresh:SetPoint("LEFT", copy, "RIGHT", 4, 0)
	Tip(refresh, "Reads prices, bags and skill again and works the route out afresh.")
	local checkBtn = Button(frame, "Check prices", 110, function() Planner:CheckPrices() end)
	checkBtn:SetPoint("LEFT", refresh, "RIGHT", 4, 0)
	Tip(checkBtn, "At the auction house: reads the real listings of the materials this route buys, so the plan uses what they cost in the quantities you need, not just the cheapest listing. If a material gets dear in bulk the route moves to another.")
	ui.status = Label(frame, "")
	ui.status:SetPoint("LEFT", checkBtn, "RIGHT", 12, 0)
	ui.status:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
	ui.status:SetJustifyH("RIGHT")

	UI:Layout()
	frame:SetScript("OnShow", function()
		if Planner.dirty or not Planner.state.trade then Planner:Plan() end
		UI:Refresh()
	end)
	frame:Hide()
end

function UI:IsShown()
	return frame ~= nil and frame:IsShown()
end

function UI:Toggle()
	if not CPath.db then CPath:Print("Still loading. Try again in a moment."); return end
	if not frame then
		local ok, err = pcall(Build)
		if not ok then
			frame = nil
			CPath:Print("Could not build the window: %s", tostring(err))
			return
		end
	end
	if frame:IsShown() then frame:Hide() else frame:Show() end
end

for _, event in ipairs({ "PLAN", "BOARD", "ITEMS_LOADED", "BAGS", "SKILLLOG", "DB_CHANGED", "DEPTH_PROGRESS" }) do
	CPath:On(event, function() UI:Soon() end)
end
CPath:On("SETTINGS_CHANGED", function() if frame then UI:RefreshControls() end end)
CPath:On("LOGIN", function()
	CPath:After(4, function()
		local problem = CPath:DataProblem()
		if problem then CPath:Print(problem) else CPath:Print("Type /craftpath to open the planner.") end
	end)
end)
