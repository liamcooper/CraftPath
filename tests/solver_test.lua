-- Runs CraftPath's solver against ForeverMaster's own on the installed data. Usage: lua solver_test.lua <ForeverMaster dir> <CraftPath dir>
local FM, CPDIR = arg[1], arg[2]
_G._G = _G
dofile(FM .. "/Data/Leveling.lua")
local FC = { data = ForeverMasterData }
assert(loadfile(FM .. "/Lib/Leveling.lua"))("ForeverMaster", FC)
local CPath = {}
assert(loadfile(CPDIR .. "/Solver.lua"))("CraftPath", CPath)
local S = CPath.Solver
local TRADES = { "Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering", "First Aid", "Leatherworking", "Tailoring" }
local fails = 0
local function check(ok, msg) if not ok then fails = fails + 1; print("FAIL " .. msg) end end
-- Deterministic made-up auction prices around each item's weight, with a listed quantity.
local function prices(seed)
  local p, ids = {}, {}
  for id in pairs(S.levelingIds()) do ids[#ids + 1] = id end
  table.sort(ids)
  local x = seed
  for _, id in ipairs(ids) do
    x = (x * 1103515245 + 12345) % 2147483648
    if x % 10 < 8 then p[id] = { 20 + x % 5000, x % 40 } end
  end
  return p
end
local function g(c) return c and string.format("%.2fg", c / 10000) or "-" end
for _, seed in ipairs({ 7, 99 }) do
  local P = prices(seed)
  for _, key in ipairs(TRADES) do
    local a, b = FC.levelingInput(key), S.levelingInput(key)
    check(a and b, key .. " input")
    for _, to in ipairs({ 150, 300 }) do
      local ref = FC.levelingSolve(a, { from = 1, to = to, goal = "cheap", side = "h", prices = P })
      local mine = S.levelingSolve(b, { from = 1, to = to, goal = "cheap", side = "h", prices = P, recovery = "keep" })
      check(mine.totals.spent == ref.totals.spent and mine.totals.crafts == ref.totals.crafts,
        string.format("%s to %d keep: mine %s/%d ref %s/%d", key, to, g(mine.totals.spent), mine.totals.crafts, g(ref.totals.spent), ref.totals.crafts))
      check(mine["end"] == ref["end"], key .. " end skill")
      local base = { from = 1, to = to, goal = "cheap", side = "h", prices = P }
      local function run(extra) local o = {}; for k, v in pairs(base) do o[k] = v end; for k, v in pairs(extra) do o[k] = v end; return S.solveBest(b, o) end
      local strict, flip = run({ recovery = "strict" }), run({ recovery = "flip", depositRate = 0.6 })
      if mine.net then
        check(strict.net <= mine.net + 1, string.format("%s to %d strict net %s should not exceed keep %s", key, to, g(strict.net), g(mine.net)))
        check(flip.net <= strict.net, string.format("%s to %d flip net %s vs strict %s", key, to, g(flip.net), g(strict.net)))
      end
      local wo = run({ recovery = "keep", wo = 0.20 })
      check(wo.totals.crafts <= mine.totals.crafts, string.format("%s to %d WO crafts %d vs %d", key, to, wo.totals.crafts, mine.totals.crafts))
      local woM = run({ recovery = "keep", wo = 0.20, woMult = true })
      check(woM.totals.crafts <= mine.totals.crafts, key .. " WO multiplied helps")
      local bart = run({ recovery = "keep", barter = 0.10 })
      if mine.net then check(bart.net <= mine.net, string.format("%s to %d barter %s vs %s", key, to, g(bart.net), g(mine.net))) end
      if key == "Cooking" then
        local chef = run({ recovery = "strict", chef = 0.5 })
        check(chef.net <= strict.net, "chef improves recovery")
      end
      if to == 300 and seed == 7 then
        print(string.format("%-15s keep %9s  strict %9s  flip %9s  WO5 %9s (%d->%d crafts)  barter2 %9s", key, g(mine.net), g(strict.net), g(flip.net), g(wo.net), mine.totals.crafts, wo.totals.crafts, g(bart.net)))
        check(#mine.stepInfo == #mine.steps, "stepInfo per step")
        local e = flip.econ(1)
        check(#e > 0, "econ rows")
      end
    end
  end
end
-- recipes bought on the auction house or from limited-stock vendors
do
  local P = prices(7)
  for _, key in ipairs(TRADES) do
    local b = S.levelingInput(key)
    local base = { from = 1, to = 300, goal = "cheap", side = "h", prices = P, recovery = "strict" }
    local function run(extra) local o = {}; for k, v in pairs(base) do o[k] = v end; for k, v in pairs(extra) do o[k] = v end; return S.solveBest(b, o) end
    local plain = run({})
    local cheap, dear = {}, {}
    for _, r in ipairs(b.recipes) do if r.taught_by and r.source ~= "trainer" then cheap[r.spell] = 100; dear[r.spell] = 100000000 end end
    local withCheap, withDear = run({ market = cheap, buyLimited = true }), run({ market = dear })
    local viaAh, viaAhDear, spells = 0, 0, {}
    for _, p in ipairs(withCheap.purchases) do if p.via == "ah" then viaAh = viaAh + 1; spells[p.spell] = true; check(p.price == 100, key .. " report uses the real recipe price") end end
    for _, p in ipairs(withDear.purchases) do if p.via == "ah" then viaAhDear = viaAhDear + 1 end end
    check(withCheap.net <= plain.net, string.format("%s cheap recipes never raise the net: %s vs %s", key, g(withCheap.net), g(plain.net)))
    check(withDear["end"] > plain["end"] or (withDear.net <= plain.net and viaAhDear == 0), string.format("%s absurdly dear recipes are not bought (%d bought, %s vs %s)", key, viaAhDear, g(withDear.net), g(plain.net)))
    if viaAh > 0 then
      local without = run({ market = cheap, buyLimited = true, exclude = spells })
      for _, p in ipairs(without.purchases) do check(not spells[p.spell], key .. " an excluded recipe is not bought") end
      for _, st in ipairs(without.steps) do check(not spells[st.spell], key .. " an excluded recipe is not used") end
    end
    print(string.format("%-15s plain %9s  with 1s recipes %9s (%d bought on AH)", key, g(plain.net), g(withCheap.net), viaAh))
  end
end
-- no prices at all, and a start above 1
for _, key in ipairs(TRADES) do
  local b = S.levelingInput(key)
  local r = S.levelingSolve(b, { from = 120, to = 150, side = "a", recovery = "strict" })
  check(r and r.steps and r["end"] >= 120, key .. " unpriced")
end
print(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
os.exit(fails == 0 and 0 or 1)
