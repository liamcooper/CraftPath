-- CraftPath :: Core
-- Namespace, saved data, events, formatting, and the small game lookups every module shares.

local ADDON, CPath = ...
_G.CraftPath = CPath

CPath.ID = "CraftPath" -- identifier passed to Auctionator
CPath.TRADES = { "Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering", "First Aid", "Leatherworking", "Tailoring" }
local TRADE_SPELL = {
	Alchemy = 2259, Blacksmithing = 2018, Enchanting = 7411, Engineering = 4036,
	Leatherworking = 2108, Tailoring = 3908, Cooking = 2550, ["First Aid"] = 3273,
}

CPath.defaults = {
	recovery = "strict",   -- keep | strict | flip
	de = false,            -- count disenchant value (needs an enchanter on the account)
	listHours = 24,        -- auction listing length used for the deposit: 2, 8 or 24
	depositPer24 = 0.60,   -- deposit for 24 hours as a share of vendor sell value (measured on Forever)
	cut = 0.05,            -- auction house cut
	flipDepth = 20,        -- items assumed sellable when Auctionator has no listed quantity
	showOptions = false,   -- the options panel in the window is open
	woMult = false,        -- Working Overtime multiplies the chance instead of adding to it
}
CPath.charDefaults = { trade = "Tailoring", target = 300, wo = 0, barter = 0, chef = 0, cap = 16 }

---------------------------------------------------------------------------
-- Output
---------------------------------------------------------------------------

function CPath:Print(msg, ...)
	if select("#", ...) > 0 then msg = string.format(msg, ...) end
	(DEFAULT_CHAT_FRAME or ChatFrame1):AddMessage("|cffffd100CraftPath:|r " .. tostring(msg))
end

-- 12g 34s 56c, coloured for the game.
function CPath:Money(copper, plain)
	if copper == nil then return "?" end
	local neg = copper < 0
	local v = math.floor(math.abs(copper) + 0.5)
	local g, s, c = math.floor(v / 10000), math.floor((v % 10000) / 100), v % 100
	local G, S, C = "g", "s", "c"
	if not plain then G, S, C = "|cffffd100g|r", "|cffc7c7cfs|r", "|cffeda55fc|r" end
	local parts = {}
	if g > 0 then parts[#parts + 1] = g .. G end
	if s > 0 and g < 1000 then parts[#parts + 1] = s .. S end
	if (c > 0 and g < 10) or #parts == 0 then parts[#parts + 1] = c .. C end
	return (neg and "-" or "") .. table.concat(parts, " ")
end

---------------------------------------------------------------------------
-- Pub/sub and game events
---------------------------------------------------------------------------

local listeners = {}
function CPath:On(name, fn)
	listeners[name] = listeners[name] or {}
	table.insert(listeners[name], fn)
end
function CPath:Fire(name, ...)
	for _, fn in ipairs(listeners[name] or {}) do
		local ok, err = pcall(fn, ...)
		if not ok then geterrorhandler()(err) end
	end
end

local eventFrame = CreateFrame("Frame")
local handlers = {}
function CPath:RegisterEvent(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		pcall(eventFrame.RegisterEvent, eventFrame, event)
	end
	table.insert(handlers[event], fn)
end
eventFrame:SetScript("OnEvent", function(_, event, ...)
	for _, fn in ipairs(handlers[event] or {}) do
		local ok, err = pcall(fn, event, ...)
		if not ok then geterrorhandler()(err) end
	end
end)

function CPath:After(seconds, fn)
	if C_Timer and C_Timer.After then C_Timer.After(seconds, fn) else fn() end
end

-- Runs fn once, `seconds` after the last call with the same key.
local pendingCalls = {}
function CPath:Debounce(key, seconds, fn)
	pendingCalls[key] = (pendingCalls[key] or 0) + 1
	local mine = pendingCalls[key]
	self:After(seconds, function() if pendingCalls[key] == mine then fn() end end)
end

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------
-- On Forever the saved table can arrive after ADDON_LOADED, or only through the machine-wide console file
-- (see CraftProfit's Core.lua, which found this out). So: never create the global at load, look for the saved
-- table for the first five minutes and adopt it when it shows up, and hand the client our table at logout,
-- with a copy in the console vault.

local VAULT = "AddOnVault"
local adopted = false
local touched, touchedChar = {}, {}

local function Vault(create)
	local console = _G.Blizzard_Console_SavedVars
	if type(console) ~= "table" then return nil end
	if type(console[VAULT]) ~= "table" then
		if not create then return nil end
		console[VAULT] = {}
	end
	return console[VAULT]
end

local function Fill(dst, src)
	for k, v in pairs(src) do
		if dst[k] == nil then dst[k] = v
		elseif type(v) == "table" and type(dst[k]) == "table" then Fill(dst[k], v) end
	end
end

local function Use(db)
	db.settings = type(db.settings) == "table" and db.settings or {}
	db.vendor = type(db.vendor) == "table" and db.vendor or {}   -- itemID -> vendor buy price per unit seen at a merchant
	db.chars = type(db.chars) == "table" and db.chars or {}
	for k, v in pairs(CPath.defaults) do if db.settings[k] == nil then db.settings[k] = v end end
	CPath.db, CPath.settings = db, db.settings
end

local function Saved()
	local g = _G.CraftPathDB
	if type(g) == "table" then return g, "saved file" end
	local vault = Vault(false)
	if vault and type(vault[CPath.ID]) == "table" then return vault[CPath.ID], "console vault" end
end

local function CheckSaved()
	if adopted then return end
	local loaded, from = Saved()
	if not loaded or loaded == CPath.db then return end
	local provisional = CPath.db
	local settingsNow, charNow = provisional.settings, provisional.chars[CPath:CharKey()]
	Fill(loaded, provisional)
	Use(loaded)
	for k in pairs(touched) do loaded.settings[k] = settingsNow[k] end
	if charNow then
		local c = CPath:Char()
		for k in pairs(touchedChar) do c[k] = charNow[k] end
	end
	adopted, CPath.loadedFrom = true, from .. " (arrived late)"
	CPath:Fire("DB_CHANGED")
end

local function InitDB()
	local loaded, from = Saved()
	if loaded then adopted, CPath.loadedFrom = true, from end
	Use(loaded or {})
end

function CPath:CharKey()
	local name = (UnitName and UnitName("player")) or "char"
	local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or "realm"
	return tostring(name) .. "-" .. tostring(realm):gsub("[%s%-']", "")
end

-- This character's settings. Always fetch through here: the table can be swapped when saved data arrives late.
function CPath:Char()
	local key = self:CharKey()
	local c = self.db.chars[key]
	if type(c) ~= "table" then c = {}; self.db.chars[key] = c end
	if c.trade == nil then
		-- start on a profession this character has, when it has one
		local have = self:Professions()
		for _, key in ipairs(self.TRADES) do if have[key] then c.trade = key; break end end
	end
	for k, v in pairs(self.charDefaults) do if c[k] == nil then c[k] = v end end
	c.owned = type(c.owned) == "table" and c.owned or {}   -- trade -> { [spell] = true } recipes marked as owned by hand
	c.excluded = type(c.excluded) == "table" and c.excluded or {} -- trade -> { [spell] = true } recipes the player cannot get
	c.log = type(c.log) == "table" and c.log or {}         -- skill-up log, see SkillLog.lua
	return c
end

function CPath:Set(key, value)
	self.settings[key] = value
	touched[key] = true
	self:Fire("SETTINGS_CHANGED", key)
end

function CPath:SetChar(key, value)
	self:Char()[key] = value
	touchedChar[key] = true
	self:Fire("SETTINGS_CHANGED", key)
end

---------------------------------------------------------------------------
-- Game lookups
---------------------------------------------------------------------------

function CPath:ItemIDFromLink(link)
	if type(link) ~= "string" then return nil end
	local id = link:match("item:(%d+)")
	return id and tonumber(id) or nil
end

local GetItemInfoFn = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
local requested = {}
CPath.itemsPending = 0

-- name, link, quality, itemLevel, sellPrice, classID; nil while the client is still loading the item (it is requested).
function CPath:ItemInfo(id)
	if not id or not GetItemInfoFn then return nil end
	local ok, name, link, quality, ilvl, _, _, _, _, _, _, sell, classID = pcall(GetItemInfoFn, id)
	if ok and name then return name, link, quality, ilvl, sell, classID end
	if not requested[id] then
		requested[id] = true
		self.itemsPending = self.itemsPending + 1
		if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
	end
	return nil
end

function CPath:ItemName(id)
	local name = self:ItemInfo(id)
	return name or ("item " .. tostring(id)), name ~= nil
end

-- How many this character has: bags and bank, or bags only.
function CPath:ItemCount(id, bagsOnly)
	local fn = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
	if not fn then return 0 end
	local ok, n = pcall(fn, id, not bagsOnly)
	return ok and tonumber(n) or 0
end

function CPath:SpellName(id)
	if C_Spell and C_Spell.GetSpellName then
		local ok, n = pcall(C_Spell.GetSpellName, id)
		if ok and n then return n end
	end
	if GetSpellInfo then
		local ok, n = pcall(GetSpellInfo, id)
		if ok and n then return n end
	end
end

-- What to call a recipe: the thing it makes, else the spell's own name.
function CPath:RecipeName(spell, makes)
	if makes and makes.id then
		local name, known = self:ItemName(makes.id)
		if known then return name end
	end
	return self:SpellName(spell) or (makes and makes.id and ("item " .. makes.id)) or ("recipe " .. tostring(spell))
end

local localName
local function TradeKey(name)
	if not name then return nil end
	if TRADE_SPELL[name] then return name end
	if not localName then
		localName = {}
		for key, spell in pairs(TRADE_SPELL) do
			local n = CPath:SpellName(spell)
			if n then localName[n] = key end
		end
	end
	return localName[name]
end

-- trade -> { rank, max } for the professions this character has.
function CPath:Professions()
	local out = {}
	if GetProfessions and GetProfessionInfo then
		local ok, a, b, c, d, e = pcall(GetProfessions)
		if ok then
			for _, idx in pairs({ a, b, c, d, e }) do
				local ok2, name, _, rank, maxRank = pcall(GetProfessionInfo, idx)
				local key = ok2 and TradeKey(name)
				if key then out[key] = { rank = rank or 0, max = maxRank or 0 } end
			end
		end
	end
	if next(out) == nil and GetNumSkillLines and GetSkillLineInfo then
		for i = 1, GetNumSkillLines() or 0 do
			local name, header, _, rank, _, _, maxRank = GetSkillLineInfo(i)
			local key = not header and TradeKey(name)
			if key then out[key] = { rank = rank or 0, max = maxRank or 0 } end
		end
	end
	return out
end

function CPath:RecipeKnown(spell)
	if C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
		local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, spell)
		if ok and type(info) == "table" and info.learned ~= nil then return info.learned and true or false end
	end
	if IsPlayerSpell then local ok, k = pcall(IsPlayerSpell, spell); if ok and k then return true end end
	if IsSpellKnown then local ok, k = pcall(IsSpellKnown, spell); if ok and k then return true end end
	return false
end

function CPath:Side()
	local f = UnitFactionGroup and UnitFactionGroup("player")
	return f == "Alliance" and "a" or "h"
end

-- ForeverMaster's data, checked before anything is planned from it.
function CPath:DataProblem()
	local data = _G.ForeverMasterData
	if type(data) ~= "table" or type(data.leveling) ~= "table" then
		return "ForeverMaster's leveling data is missing. Is ForeverMaster enabled?"
	end
	for _, key in ipairs(self.TRADES) do
		local input, err = self.Solver.levelingInput(key)
		if not input then
			return "ForeverMaster's data for " .. key .. " is not in the format CraftPath expects" .. (err and " (" .. err .. ")" or "") .. ". CraftPath needs updating for this ForeverMaster version."
		end
		if #input.recipes == 0 then return "ForeverMaster has no recipes for " .. key .. "." end
	end
	return nil
end

function CPath:DataVersion()
	local pack = _G.ForeverMasterData and _G.ForeverMasterData.pack
	return pack and pack.version or "unknown"
end

---------------------------------------------------------------------------
-- Start-up
---------------------------------------------------------------------------

CPath:RegisterEvent("ADDON_LOADED", function(_, name)
	if name == ADDON then InitDB() else CheckSaved() end
end)
CPath:RegisterEvent("PLAYER_LOGIN", function()
	if not CPath.db then InitDB() end
	CheckSaved()
	if C_Timer and C_Timer.NewTicker then
		local polls, ticker = 0
		ticker = C_Timer.NewTicker(1, function()
			polls = polls + 1
			CheckSaved()
			if (adopted or polls >= 300) and ticker then ticker:Cancel() end
		end)
	end
	CPath:Fire("LOGIN")
end)
CPath:RegisterEvent("PLAYER_ENTERING_WORLD", function() if CPath.db then CheckSaved() end end)
CPath:RegisterEvent("PLAYER_LOGOUT", function()
	if not CPath.db then return end
	_G.CraftPathDB = CPath.db
	local vault = Vault(true)
	if vault then vault[CPath.ID] = CPath.db end
end)

CPath:RegisterEvent("GET_ITEM_INFO_RECEIVED", function(_, id)
	if id and requested[id] then
		requested[id] = nil
		CPath.itemsPending = math.max(0, CPath.itemsPending - 1)
		CPath:Debounce("items", 0.5, function() CPath:Fire("ITEMS_LOADED") end)
	end
end)

SLASH_CRAFTPATH1, SLASH_CRAFTPATH2 = "/craftpath", "/cpath"
SlashCmdList["CRAFTPATH"] = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "status" then
		CPath:Print("ForeverMaster data %s. Saved data: %s. %s", CPath:DataVersion(), CPath.loadedFrom or "none yet (new install, or not loaded)", CPath:DataProblem() or "Data format OK.")
	elseif msg == "minimap" then
		if CPath.MinimapButton then CPath.MinimapButton:Toggle() end
	elseif CPath.UI then
		CPath.UI:Toggle()
	end
end
