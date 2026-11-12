-- Loads the whole addon against a stand-in for the game's API and walks through it.
-- Usage: lua addon_test.lua <ForeverMaster dir> <CraftPath dir> [verbose]
local FM, DIR, VERBOSE = arg[1], arg[2], arg[3]
_G._G = _G
local fails = 0
local function check(ok, msg) if not ok then fails = fails + 1; print("FAIL " .. msg) end end
local function strip(s) return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

-- frames -------------------------------------------------------------------------------------------------
local frames, all = {}, {}
local function Mock(name)
  local o = { __shown = true, __text = "", __scripts = {}, __name = name }
  setmetatable(o, { __index = function(_, k)
    if k == "SetText" then return function(self, s) self.__text = s end
    elseif k == "GetText" then return function(self) return self.__text end
    elseif k == "Show" then return function(self) local was = self.__shown; self.__shown = true; if not was and self.__scripts.OnShow then self.__scripts.OnShow(self) end end
    elseif k == "Hide" then return function(self) self.__shown = false end
    elseif k == "IsShown" then return function(self) return self.__shown end
    elseif k == "SetScript" then return function(self, n, f) self.__scripts[n] = f end
    elseif k == "GetScript" then return function(self, n) return self.__scripts[n] end
    elseif k == "GetStringWidth" then return function(self) return #strip(self.__text) * 6 end
    elseif k == "GetStringHeight" then return function() return 12 end
    elseif k == "CreateFontString" or k == "CreateTexture" or k == "GetFontString" then return function() return Mock() end
    elseif k == "RegisterEvent" then return function() end
    else return function() end end
  end })
  if name then frames[name] = o; _G[name] = o end
  all[#all + 1] = o
  return o
end
function CreateFrame(_, name) return Mock(name) end
UIParent = Mock("UIParent")
GameTooltip = Mock("GameTooltip")
MerchantFrame = Mock("MerchantFrame"); MerchantFrame.__shown = false
Minimap = Mock("Minimap"); rawset(Minimap, "GetWidth", function() return 140 end)
BackdropTemplateMixin = {}
UISpecialFrames = {}
SlashCmdList = {}
local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = strip(m); if VERBOSE then print("  [chat] " .. strip(m)) end end }
function geterrorhandler() return function(e) fails = fails + 1; print("FAIL lua error: " .. tostring(e)) end end

-- timers -------------------------------------------------------------------------------------------------
local queue = {}
C_Timer = { After = function(_, f) queue[#queue + 1] = f end, NewTicker = function() return { Cancel = function() end } end }
local function drain(max)
  local n = 0
  while #queue > 0 do
    local f = table.remove(queue, 1); f(); n = n + 1
    if n > (max or 200000) then error("timer queue did not settle") end
  end
end
function debugprofilestop() return os.clock() * 1000 end
time = os.time

-- character ----------------------------------------------------------------------------------------------
local skills = { Cooking = { 225, 225 }, Tailoring = { 40, 75 } }
function UnitName() return "Tester" end
function GetRealmName() return "Test Realm" end
function GetNormalizedRealmName() return "TestRealm" end
function UnitFactionGroup() return "Horde" end
local profNames = { "Cooking", "Tailoring" }
function GetProfessions() return 1, 2 end
function GetProfessionInfo(i) local n = profNames[i]; return n, nil, skills[n][1], skills[n][2] end
function GetMoney() return 5000000 end
local bags = {}
C_Item = {
  GetItemInfo = function(id) return "Item" .. id, "|Hitem:" .. id .. "|h[Item" .. id .. "]|h", 2, 30, 20, "Armor", "Cloth", 20, "", 1, 25, 4, 1 end,
  GetItemCount = function(id) return bags[id] or 0 end,
  RequestLoadItemDataByID = function() end,
}
C_Spell = { GetSpellName = function(id)
  local n = ({ [2259] = "Alchemy", [2018] = "Blacksmithing", [7411] = "Enchanting", [4036] = "Engineering", [2108] = "Leatherworking", [3908] = "Tailoring", [2550] = "Cooking", [3273] = "First Aid" })[id]
  return n or ("Spell" .. id) end }
local crafted = {}
C_TradeSkillUI = {
  GetRecipeInfo = function() return { learned = false } end,
  OpenRecipe = function() end,
  CraftRecipe = function(spell, n) crafted[#crafted + 1] = { spell, n } end,
}

-- Auctionator --------------------------------------------------------------------------------------------
local created
local function ah(id) local x = (id * 2654435761) % 4294967296; if x % 10 < 8 then return 20 + x % 5000 end end
Auctionator = {
  API = { v1 = {
    GetAuctionPriceByItemID = function(caller, id) assert(caller == "CraftPath"); return ah(id) end,
    ConvertToSearchString = function(_, t) return t.searchString .. ";" .. tostring(t.isExact) .. ";" .. t.quantity end,
    CreateShoppingList = function(_, name, terms) created = { name = name, terms = terms } end,
  } },
  Database = { GetPriceHistory = function(_, key) return { { available = tonumber(key) % 30 } } end },
}

-- auction house listings ---------------------------------------------------------------------------------
-- Every item has plenty at its cheapest price, except `steep`, which runs out fast and then costs 20 times as much.
local steep, searches = nil, 0
local function ladderOf(id)
  local base = ah(id)
  if not base then return {} end
  if id == steep then return { { base, 50 }, { base * 20, 100 } } end
  return { { base, 100000 } }
end
C_AuctionHouse = {
  MakeItemKey = function(id) return { itemID = id } end,
  GetItemKeyInfo = function() return { isCommodity = true } end,
  IsThrottledMessageSystemReady = function() return true end,
  SendSearchQuery = function(key) searches = searches + 1; queue[#queue + 1] = function() __fire("COMMODITY_SEARCH_RESULTS_UPDATED", key.itemID) end end,
  GetNumCommoditySearchResults = function(id) return #ladderOf(id) end,
  GetCommoditySearchResultInfo = function(id, i) local t = ladderOf(id)[i]; return { unitPrice = t[1], quantity = t[2] } end,
  HasFullCommoditySearchResults = function() return true end,
}

-- merchant -----------------------------------------------------------------------------------------------
local merchant, bought = {}, {}
function GetMerchantNumItems() return #merchant end
function GetMerchantItemLink(i) return "|Hitem:" .. merchant[i].id .. "|h" end
function GetMerchantItemInfo(i) local m = merchant[i]; return "x", nil, m.price, m.stack, -1, true, true, false end
function GetMerchantItemMaxStack() return 20 end
function BuyMerchantItem(i, n) bought[#bought + 1] = { merchant[i].id, n or merchant[i].stack }; bags[merchant[i].id] = (bags[merchant[i].id] or 0) + (n or merchant[i].stack) end

-- load ---------------------------------------------------------------------------------------------------
dofile(FM .. "/Data/Pack.lua"); dofile(FM .. "/Data/Leveling.lua")
local CPath = {}
for line in io.lines(DIR .. "/CraftPath.toc") do
  local f = line:gsub("\r", ""):match("^([%w_]+%.lua)%s*$")
  if f then assert(loadfile(DIR .. "/" .. f))("CraftPath", CPath) end
end
local function fire(event, ...)
  for _, f in ipairs(all) do
    local h = f.__scripts.OnEvent
    if h then h(f, event, ...) end
  end
end
__fire = fire
local rendered = {}
local function hookRender()
  local orig = CPath.UI.Render
  CPath.UI.Render = function(self, lines) rendered = lines; return orig(self, lines) end
end
local function dump(title)
  print("==== " .. title)
  print("  summary: " .. strip(CraftPathFrame and "" or ""))
  for _, l in ipairs(rendered) do
    local t = string.rep("  ", (l.indent or 0) + 1) .. strip(l.text or "")
    if l.right and l.right ~= "" then t = t .. "   >>> " .. strip(l.right) end
    if l.action then t = t .. "   [" .. l.action.label .. "]" end
    if #t > 230 then t = t:sub(1, 230) .. "..." end
    print(t)
  end
end
local function tabText() local t = {}; for _, l in ipairs(rendered) do t[#t + 1] = strip(l.text or "") .. " " .. strip(l.right or "") end; return table.concat(t, "\n") end
local function settle() drain(); CPath.UI:Refresh() end
local function show(name, quiet) CPath.UI:SetTab(name); settle(); if VERBOSE and not quiet then dump(name) end; check(not tabText():find("could not draw"), name .. " tab drew: " .. tabText():sub(1, 200)) end

fire("ADDON_LOADED", "CraftPath")
fire("PLAYER_LOGIN")
drain()
check(CPath.db ~= nil, "db ready")
check(CPath:DataProblem() == nil, "data format: " .. tostring(CPath:DataProblem()))
hookRender()

-- 1. open on the default profession (Tailoring, known at 40)
CPath:SetChar("trade", "Tailoring")
SlashCmdList.CRAFTPATH("")
check(CPath.UI:IsShown(), "window shown")
settle()
local st = CPath.Planner.state
check(st.status == "done", "plan finished: " .. tostring(st.status) .. " " .. tostring(st.error))
check(st.from == 40 and st.known, "starts from the character's skill")
check(st.result and st.result.net, "route has a net cost")
check(st.zero and st.best and st.bestAlloc, "perk comparison ran")
check(st.best.net <= st.zero.net, "best points not worse than none")
for _, t in ipairs({ "Route", "Shopping", "Perks", "Board", "Opportunities", "Log" }) do show(t) end
check(CPath.Planner.board and CPath.Planner.board.status == "done" and #CPath.Planner.board.rows == 8, "board has 8 rows")

-- 1b. a typed target survives redraws while typing and is committed when focus leaves the box
do
  local box = frames.CraftPathTargetBox
  local focused = false
  rawset(box, "HasFocus", function() return focused end)
  rawset(box, "ClearFocus", function(self) if focused then focused = false; self.__scripts.OnEditFocusLost(self) end end)
  focused = true
  box:SetText("87")
  CPath.UI:Refresh(); CPath.UI:RefreshControls()
  check(box:GetText() == "87", "typing is not overwritten by a redraw: " .. tostring(box:GetText()))
  box.__scripts.OnEnterPressed(box)
  settle()
  check(CPath:Char().target == 87 and CPath.Planner.state.to == 87 and box:GetText() == "87", "custom target 87 is used: " .. tostring(CPath:Char().target))
  focused = true; box:SetText("120"); box.__scripts.OnEscapePressed(box)
  check(CPath:Char().target == 87 and box:GetText() == "87", "Escape puts the old target back")
  focused = true; box:SetText("999"); box:ClearFocus(); settle()
  check(CPath:Char().target == 300, "target is clamped to 300")
end

-- 1c. minimap button: opens and closes the window, and can be hidden
do
  local b = frames.CraftPathMinimapButton
  check(b and b:IsShown(), "minimap button exists")
  local was = CPath.UI:IsShown()
  b.__scripts.OnClick(b); check(CPath.UI:IsShown() ~= was, "minimap click toggles the window")
  b.__scripts.OnClick(b); check(CPath.UI:IsShown() == was, "and back")
  SlashCmdList.CRAFTPATH("minimap"); check(not b:IsShown() and CPath.db.minimap.hide, "slash command hides it")
  SlashCmdList.CRAFTPATH("minimap"); check(b:IsShown(), "and shows it again")
  CraftPath_OnCompartmentClick(); CraftPath_OnCompartmentClick()
  check(CPath.UI:IsShown() == was, "addon list entry toggles too")
  settle()
end

-- 2. modes, disenchant, perks
show("Route", true)
local nets = {}
for _, mode in ipairs({ "keep", "strict", "flip" }) do
  CPath:Set("recovery", mode); settle()
  nets[mode] = CPath.Planner.state.result.net
  check(CPath.Planner.state.status == "done", mode .. " done")
end
check(nets.strict <= nets.keep and nets.flip <= nets.strict, string.format("mode order keep %d strict %d flip %d", nets.keep, nets.strict, nets.flip))
CPath:Set("de", true); settle()
check(CPath.Planner.state.result.net <= nets.flip, "disenchant never raises the net")
local sawDe = false
for _, h in pairs(CPath.Planner.state.result.how) do if h == "de" then sawDe = true end end
check(sawDe, "some results are disenchanted in the test data")
if VERBOSE then show("Route") end
CPath:Set("de", false)
CPath:SetChar("wo", 5); CPath:SetChar("barter", 2); settle()
st = CPath.Planner.state
check(st.alloc.wo == 5 and st.result.totals.crafts <= st.zero.totals.crafts, "Working Overtime cuts crafts")
show("Perks")
CPath:SetChar("wo", 0); CPath:SetChar("barter", 0); CPath:SetChar("cap", 3); settle()
st = CPath.Planner.state
check(CPath.Perks:Points(st.bestAlloc) <= 3, "best allocation respects the cap: " .. CPath.Perks:Describe(st.bestAlloc, st.trade))
show("Perks")
-- "Use this"
for _, l in ipairs(rendered) do if l.action and l.action.label == "Use this" then l.action.fn() end end
settle()
check(CPath.Perks:Points(CPath.Perks:Current()) == CPath.Perks:Points(st.bestAlloc), "Use this sets the ranks")
CPath:SetChar("cap", 16); CPath:SetChar("wo", 0); CPath:SetChar("barter", 0); CPath:SetChar("chef", 0)

-- 3. an unlearned profession, a target of 150, and Cooking with Master Chef
CPath:SetChar("trade", "Engineering"); CPath:SetChar("target", 150); CPath:Set("recovery", "strict"); settle()
st = CPath.Planner.state
check(st.from == 1 and not st.known and st.result["end"] <= 150, "unlearned profession plans from 1 to 150")
show("Route", true)
local hasCraft = false
for _, l in ipairs(rendered) do if l.action and l.action.label:find("^Craft") then hasCraft = true end end
check(not hasCraft, "no craft button for an unlearned profession")
CPath:SetChar("trade", "Cooking"); CPath:SetChar("target", 300); settle()
st = CPath.Planner.state
check(st.from == 225, "cooking from 225")
local n0 = st.result.net
CPath:SetChar("chef", 5); settle()
check(CPath.Planner.state.result.net <= n0, "Master Chef does not raise the net")
show("Perks", true)
CPath:SetChar("chef", 0)
CPath:SetChar("trade", "Enchanting"); settle()
check(CPath.Planner.state.status == "done", "enchanting plans: " .. tostring(CPath.Planner.state.error))
show("Route")

-- 3b. recipes on the auction house are bought when cheaper, go on the shopping list, and can be ruled out
do
  CPath:SetChar("trade", "Tailoring"); CPath:SetChar("target", 300); CPath:Set("recovery", "strict"); settle()
  local st2 = CPath.Planner.state
  local ahRecipe
  for _, p in ipairs(st2.result.purchases) do if p.via == "ah" then ahRecipe = ahRecipe or p end end
  check(ahRecipe ~= nil, "the test prices make at least one auction-house recipe worth buying")
  if ahRecipe then
    local item = st2.result.recipes[ahRecipe.spell].taught_by
    local onList = false
    for _, r in ipairs(CPath.Shopping:Build(st2).ah) do if r.id == item and r.recipe and r.count == 1 then onList = true end end
    check(onList, "the recipe is on the auction list")
    show("Route", true)
    local n = 0
    for _, l in ipairs(rendered) do if l.action and l.action.label == "Can't get it" then n = n + 1; if n == 1 then l.action.fn() end end end
    check(n > 0, "a Can't get it button is shown")
    settle()
    local barred = CPath:Char().excluded.Tailoring
    local spell = barred and next(barred)
    check(spell ~= nil, "the recipe is recorded as unobtainable")
    for _, p in ipairs(CPath.Planner.state.result.purchases) do check(p.spell ~= spell, "and the new route does not buy it") end
    show("Route", true)
    for _, l in ipairs(rendered) do if l.action and l.action.label == "Undo" then l.action.fn() end end
    settle()
    check(next(CPath:Char().excluded.Tailoring) == nil, "Undo clears it")
  end
end

-- 3c. Check prices: listings are read, and a material that is dear in bulk costs what it really costs
do
  CPath:SetChar("trade", "Tailoring"); CPath:SetChar("target", 300); CPath:Set("recovery", "strict"); settle()
  local before = CPath.Planner.state.result
  local needs = CPath.Planner.AhNeeds(before)
  local top, topQty = nil, 0
  for id, q in pairs(needs) do if q > topQty and ah(id) then top, topQty = id, q end end
  check(top ~= nil and topQty > 150, "a material is bought in bulk: " .. tostring(topQty))
  steep = top
  CPath.Planner:CheckPrices(); settle()
  check(#chat > 0 and chat[#chat]:find("Open the auction house first"), "needs the auction house open: " .. tostring(chat[#chat]))
  fire("AUCTION_HOUSE_SHOW")
  CPath.Planner:CheckPrices(); settle()
  check(not CPath.Planner:Checking() and searches > 0, "the check ran and finished (" .. searches .. " searches)")
  local after = CPath.Planner.state.result
  check(CPath.Planner.state.status == "done", "planned again after the check")
  local unread = 0
  for id in pairs(CPath.Planner.AhNeeds(after)) do if not CPath.Depth:Age(id) then unread = unread + 1 end end
  check(unread == 0, "every material the final route buys has had its listings read (" .. unread .. " unread)")
  check(after.net >= before.net, string.format("the real cost is not below the cheapest-listing cost: %d vs %d", after.net, before.net))
  local qtyAfter = CPath.Planner.AhNeeds(after)[top] or 0
  local d = after.depth[top]
  check(qtyAfter < topQty or (d and d.short > 0), string.format("the dear material is used less (%d to %d) or flagged short", topQty, qtyAfter))
  if qtyAfter > 0 then
    local total = CPath.Depth:Cost(top, qtyAfter)
    check(d and d.avg and math.abs(after.price[top] * qtyAfter - total) <= qtyAfter, "its unit price shown is the real average")
  end
  -- what the route would have cost had it stayed put: the new route must not be dearer than that
  local stay = 0
  for id, q in pairs(needs) do local t = CPath.Depth:Cost(id, q); if t then stay = stay + (t - ah(id) * q) end end
  check(after.net <= before.net + stay + 1, string.format("moving away never costs more than staying: %d vs %d", after.net, before.net + stay))
  print(string.format("  depth: %s need %d -> %d; net %.2fg -> %.2fg (staying put would be %.2fg)", tostring(top), topQty, qtyAfter, before.net / 10000, after.net / 10000, (before.net + stay) / 10000))
  show("Shopping"); show("Route", true)
  local n = searches
  CPath.Planner:CheckPrices(); settle()
  check(searches == n, "a second check straight away reads nothing again")
  -- a shorter route with alternatives: the planner should move off a material that is dear in bulk
  for k in pairs(CPath.db.ladders) do CPath.db.ladders[k] = nil end
  steep = nil
  for _, target in ipairs({ 100, 150, 200 }) do
    CPath:SetChar("target", target); settle()
    local b = CPath.Planner.state.result
    local nd, t2, q2 = CPath.Planner.AhNeeds(b), nil, 0
    for id, q in pairs(nd) do if q > q2 and ah(id) then t2, q2 = id, q end end
    steep = t2
    CPath.Planner:CheckPrices(); settle()
    local a2 = CPath.Planner.state.result
    local qa = CPath.Planner.AhNeeds(a2)[t2] or 0
    local stay2 = 0
    for id, q in pairs(nd) do local t = CPath.Depth:Cost(id, q); if t then stay2 = stay2 + (t - ah(id) * q) end end
    check(a2.net <= b.net + stay2 + 1, string.format("to %d: moving never costs more than staying: %d vs %d", target, a2.net, b.net + stay2))
    print(string.format("  depth to %d: %s need %d -> %d; net %.2fg -> %.2fg (staying put %.2fg)", target, tostring(t2), q2, qa, b.net / 10000, a2.net / 10000, (b.net + stay2) / 10000))
    steep = nil
    for k in pairs(CPath.db.ladders) do CPath.db.ladders[k] = nil end
  end
  CPath:SetChar("target", 300); settle()
  fire("AUCTION_HOUSE_CLOSED")
  steep = nil
  for k in pairs(CPath.db.ladders) do CPath.db.ladders[k] = nil end
  CPath.Planner:Plan(); settle()
end

-- 4. shopping list, Auctionator, text, bags
CPath:SetChar("trade", "Tailoring"); CPath:SetChar("target", 150); settle()
st = CPath.Planner.state
local list = CPath.Shopping:Build(st)
check(#list.ah > 0, "something to buy at the AH")
local first = list.ah[1]
bags[first.id] = 5
local list2 = CPath.Shopping:Build(st)
local found
for _, r in ipairs(list2.ah) do if r.id == first.id then found = r end end
check((first.count <= 5 and not found) or (found and found.count == first.count - 5), "bags are subtracted")
local ok, msg = CPath.Shopping:CreateList(st)
check(ok and created and created.name == "CraftPath: Tailoring 40-150" and #created.terms == #list2.ah, "Auctionator list: " .. tostring(msg) .. " / " .. tostring(created and created.name))
check(created.terms[1]:match(";true;%d+$"), "terms carry exact and quantity: " .. tostring(created.terms[1]))
local text = CPath.Shopping:Text(st)
check(text:find("Auction house") and text:find("Steps") and not text:find("|c"), "plain text export")
CPath.UI:ShowCopy("t", text)
show("Shopping")

-- 5. craft button
show("Route", true)
local craft
for _, l in ipairs(rendered) do if l.action and l.action.label:find("^Craft") then craft = craft or l.action end end
check(craft ~= nil, "craft button present for a known profession")
for k in pairs(bags) do bags[k] = nil end
craft.fn()
check(#crafted == 0, "no craft without mats")
local step = st.result.steps[1]
for _, x in ipairs(st.result.recipes[step.spell].reagents) do bags[x.id] = x.count * 3 end
craft.fn()
check(#crafted == 1 and crafted[1][1] == step.spell and crafted[1][2] == math.min(3, step.crafts), "crafts what the bags allow")

-- 6. vendor restock
st = CPath.Planner.state
list = CPath.Shopping:Build(st)
local vend = list.vendor[1]
bought = {}
if vend then
  merchant = { { id = vend.id, price = 50, stack = 1 }, { id = 999999, price = 10, stack = 5 } }
  MerchantFrame.__shown = true
  fire("MERCHANT_SHOW"); drain()
  local b = frames.CraftPathRestockButton
  check(b and b:IsShown(), "restock button shows")
  -- seeing the merchant's real price replans the route, so read the need again
  local want = 0
  for _, r in ipairs(CPath.Shopping:Build(CPath.Planner.state).vendor) do if r.id == vend.id then want = r.count end end
  if b then b.__scripts.OnClick(b); local total = 0; for _, x in ipairs(bought) do if x[1] == vend.id then total = total + x[2] end end
    check(total == want and want > 0, "restock buys the missing amount: " .. total .. " of " .. want) end
  check(CPath.db.vendor[999999] == 2, "vendor prices are learned per unit")
  fire("MERCHANT_CLOSED")
else
  print("  (no vendor mats on this route; restock not exercised)")
end

-- 7. skill-up log
CPath:SetChar("wo", 5)
local input = CPath.Solver.levelingInput("Tailoring")
local yellow
for _, r in ipairs(input.recipes) do local p = CPath.Solver.levelingChance(r, 40); if p > 0 and p < 1 then yellow = r; break end end
check(yellow ~= nil, "a yellow tailoring recipe at 40")
for i = 1, 80 do
  fire("UNIT_SPELLCAST_START", "player", "guid", yellow.spell)
  if i % 3 ~= 0 then skills.Tailoring[1] = skills.Tailoring[1] + 0 end
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", yellow.spell)
  drain()
end
local b5 = CPath:Char().log.wo5
check(b5 and b5.n == 80 and b5.ups == 0, "log counts crafts: " .. tostring(b5 and b5.n))
show("Log")
CPath:SetChar("wo", 0)

-- 8. saved data: logout hands the table over; a late-arriving file is adopted
fire("PLAYER_LOGOUT")
check(CraftPathDB == CPath.db and Blizzard_Console_SavedVars == nil, "logout assigns the global")
settle()
print(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
os.exit(fails == 0 and 0 or 1)
