# Forever Profession Planner: Requirements

Status: draft from chat with Liam, Maz, and Bob (Nov 2026). Revised 12 Nov 2026 after a feasibility review against the installed addons.
Name: CraftPath. Public repository: https://github.com/liamcooper/CraftPath (made public 12 Nov 2026).

---

## 1. Goal

Find the cheapest path to a profession skill target, measured in **net gold**, not sticker craft cost.

- Net cost of a craft = reagent spend − recovery (vendor sale, AH sale after haircut, or Disenchant expected value).
- Routes are ranked on **net cost per expected skill point**: net cost ÷ skill-up chance at the current skill.
- Example: craft A costs 1g and vendors for 80s, so it costs 20s net. Craft B costs 50s and vendors for 5s, so it costs 45s net. A is the better route even though it costs twice as much up front. If A is yellow at a 50% skill-up chance and B is orange, A costs 40s per point and B 45s: still A, but only just.

### Targets

| Who | Skill target | Why |
|---|---|---|
| Main | 300 | Full profession |
| Alt / legacy | 150 | Legacy points (for example, Cooking 10% extra crafts) |

- Targets are configurable (1 to 300, or the expansion max). 150 and 300 are presets.
- The start skill is the character's current skill, or 1 for a profession it has not learned.

### What "cheapest" means

The solver is a heuristic, not a proof of the optimum. The acceptance bar: at the same prices, with all perks off and Strict recovery, the route is never more expensive than ForeverMaster's "cheap" route for the same profession and range.

---

## 2. What already exists, and what we add

ForeverMaster already ships a route solver (`Lib/Leveling.lua`) and a Leveling page. It covers: cheapest, fastest and most-profitable goals; expected crafts on yellow and green; crafted intermediates; recipe and trainer costs; limited-stock and one-faction vendor recipes; AH resale with a haircut; "recipes that would save you gold"; bags and bank; a name-only Auctionator list.

That solver cannot be called from another addon (it sits in ForeverMaster's private namespace), but CraftPath is a personal addon that will not be distributed, so we copy `Lib/Leveling.lua` into CraftPath as the starting point and extend it. We read ForeverMaster's data (the global `ForeverMasterData`) at runtime.

The repository was made public on 12 Nov 2026 at Liam's decision, with the derived files included and credited. ForeverMaster has no licence file and Auctionator is All Rights Reserved, so neither author has given permission; if either objects, the fix is to drop `Solver.lua` and `DisenchantData.lua` from the repository and have people generate them from their own installs with the scripts in `tools/`.

What this addon adds over ForeverMaster:

| Addition | Section |
|---|---|
| Any target, not only 300 | 1 |
| Legacy perks per character | 3.4 |
| Disenchant recovery | 3.2 |
| Compare board across professions | 3.1 |
| Recovery modes (Strict, Flip, Keep) | 3.2 |
| Auctionator list with quantities, net of bags and bank | 3.5 |
| Receipts on every step | 3.6 |
| Craft and vendor-restock buttons | 5 |

---

## 3. Requirements

### 3.1 Planning

- **Plan without learning the profession.** Pick Enchanting, Tailoring, and so on on an empty alt and see the route (Bob).
- **Compare board.** One view showing net gold to 150 and 300 for every crafting profession, so the cheapest one is visible without checking each (Bob). Solves run a few milliseconds a frame and results are cached until prices or settings change.
- **Recursive craft-vs-buy for reagents.** If a reagent is cheaper to craft than to buy, use the craft sub-route in the parent cost. Include chains (ore → bar → tube → item).
- **Recipe acquisition cost.** Include trainer fees and vendor recipe prices in the path. Count each once, and not at all for recipes the character already knows.
- **Recipes you can go and buy (Liam, 12 Nov 2026).** A recipe that is on the auction house, or sold by a limited-stock vendor, is put in the route automatically when the route is cheaper with it after paying for it. Leveling costs far more than the trip to fetch a recipe. An auction-house recipe has to win even at 20% over its scanned price plus 50s, since the listing may have gone. The recipe goes on the Auctionator list. A "Can't get it" button plans again without it (sold out, no longer listed).
- **Recipes you cannot simply buy.** Drop, quest and reputation recipes with no auction price stay out of the route and are listed as "would save X if you get it". The player can mark one as owned to include it (Bob).
- **Useful overcraft.** Craft past the skill-up point when the extra items are needed later. Example: "craft 100, skill-ups go grey after 50, but you need 100 later" (Liam).
- **Opportunity crafts.** Surface recipes that are currently profitable or better to vendor than to force through (Maz: wands, Working Overtime).

### 3.2 Prices

- **AH buy price:** Auctionator (`Auctionator.API.v1.GetAuctionPriceByItemID`).
- **Vendor buy price for vendor mats:** ForeverMaster's leveling data flags which items a vendor sells and gives the price. The planner also records the real price from every merchant the player opens, and that overrides the data. Use the vendor price when it is cheaper than AH. Apply Bartering if the character has it.
  - Not Auctionator's `GetVendorPriceByItemID`: that is what a vendor **pays** for the item, not what it charges.
- **Vendor sell price (recovery):** the item's own sell price from the game client, or Auctionator's `GetVendorPriceByItemID`.
- **Disenchant (DE) value:** expected value, not a perfect table.
  - CraftPath carries its own copy of Auctionator's classic disenchant probability table (the file is in the install but Forever does not load it), multiplied by current dust/essence/shard AH prices from Auctionator.
  - Only offered when the player says the account has an enchanter who can disenchant the item.
  - Show a range: worst and best outcome alongside the expected value. Maz: DE is a chance, not a fixed price (10g or 50s). We own the table, so the range comes for free.
  - Accept that this is an assumption. Liam: "I'd prefer an accurate assumption than trying to get a perfect DE."
  - The classic table is an assumption for Forever's own items (IDs above 200000): it is applied by item level and quality, and not verified against real disenchants.
- **Recovery modes**, chosen per plan:
  - **Strict:** vendor sale or guaranteed recovery only.
  - **Flip:** AH sale after the AH cut, the deposit, and a sell-rate haircut, capped by how many are listed. Never treat a listed price as cash.
  - **Keep:** zero recovery if the items are kept for later crafts.
- **Flip defaults (decided):** 5% AH cut. Sell rate by item kind, from 0.35 to 0.9, the same figures ForeverMaster uses.
- **Deposit (decided: counted).** The deposit comes back when an item sells and is lost when it does not, so it is charged against the share that fails to sell:
  - Flip recovery per item = sell rate × AH price × 0.95 + (1 − sell rate) × vendor sell − (1 − sell rate) × deposit.
  - If that is below the vendor sell price, the plan vendors the item instead.
  - The game only reports the real deposit at the auction house with the item in the sell slot (`GetAuctionDeposit`), so the planner estimates it: 60% of the item's vendor sell price for a 24-hour listing. That is measured on Forever (check V7) from one item, and is double the classic rate.
  - Listing length is a setting: 2, 8 or 24 hours, default 24. Shorter listings are assumed to scale with time (5% and 20%) until measured.
  - Confirmed in game: the deposit is refunded when the item sells and the 5% fee is kept. Each receipt shows the deposit it assumed.
- **Prices by quantity (Liam, 12 Nov 2026).** The cheapest listing is not the price of 1,500 of something. A "Check prices" button at the auction house reads the real listings of the materials the route buys, as a ladder of prices and quantities. CraftPath does this itself; it does not use CraftProfit.
  - The planner costs each route by walking up those ladders, gives each material its average price for the quantity used, and plans again, a few times over. A material that gets dear in bulk moves the route to another. The route with the lowest real cost is kept.
  - After each read the route is planned again, and any material it now uses that is still unread is read too, so an alternative never looks cheap only because nobody looked.
  - Units beyond what is listed are priced at the dearest listing and flagged as not available right now.
  - Without a read, the planner falls back to the cheapest listing and warns when Auctionator saw fewer listed than the route needs.
  - Ladders are a snapshot: kept for 24 hours, re-read after 10 minutes.
- **Gathered mats (decided):** herbs, ore, leather and other farmable mats are counted at AH price, since a mat you farm could have been sold.
- **Missing prices.** An item with no AH or vendor price is shown as unpriced and the route says how many reagents were priced. No silent zeros.

### 3.3 Skill-up model

- Yellow and green skill-ups are not guaranteed. Chance = (grey − skill) ÷ (grey − yellow), 100% below yellow, 0% at grey.
- **Default (decided): expected crafts.** Optimistic and pessimistic are optional views.
- Working Overtime changes the skill-up chance, so it changes expected crafts.
- **Skill-up log.** While the player crafts, CraftPath records each craft and whether it gave a skill point, along with the recipe's colour thresholds, the skill at the time and the Working Overtime rank set for the character. A small readout compares the skill-ups seen with the skill-ups predicted. Once there are enough yellow and green crafts it says whether Working Overtime looks added or multiplied, and the player can switch the setting to match. This replaces any manual test.

### 3.4 Legacy perks (per character)

Legacy points are shared across the account. Each character spends up to 16 points on its own trees. The planner must model each character's allocation separately, especially for alts.

| Perk | Ranks | Planner effect |
|---|---|---|
| Working Overtime | 5 (4% to 20% skill-up chance) | Fewer expected crafts on yellow and green |
| Bartering | 2 (5% and 10% off vendor gold) | Cheaper vendor reagents and recipe purchases |
| Master Chef | 5 (10% to 50% extra result, Cooking only) | Better recovery EV for Cooking. Shopping list still buys listed reagents per craft |

- Perk ranks are **set by hand** per character and saved. No addon in the install reads perk allocation from the game, so auto-detect is not assumed.
- The planner shows how each perk changes the result.
- **With and without points.** When a character has unspent Legacy points, the planner shows two routes side by side:
  - **No points spent:** the route and net cost with every perk at rank 0.
  - **Best points spent:** the cheapest route over every allowed allocation of the points available, with the allocation it chose, the gold it saves in total and per point, and which perk the saving comes from.
  - The search is small: at most 6 × 3 × 6 combinations of Working Overtime, Bartering and Master Chef (18 outside Cooking), each one a normal solve.
  - Points are also wanted for non-profession perks, so the player can cap how many points the planner may spend (0 to 16). Gold saved per point is there to make that call.
  - If the character has already spent points, the first column is "as spent" and the second is "best use of what is left".
  - One point per rank (confirmed, check V8).
- Working Overtime's in-game wording at rank 5: "Increases your chance to gain a skill increase from using any primary, secondary, or class-based tradeskill by 20%." That does not say whether 20% is added or multiplied. It is modelled as added percentage points on yellow and green (a 50% chance becomes 70%), capped at 100%, with a setting to switch to multiplied (50% becomes 60%). The skill-up log (3.3) shows which one fits.
- **Point rules (confirmed):** one point per rank, 16 points per character. The Professions tree has prerequisite arrows between some perks and markers at 5 and 10 points. The best-points search only proposes allocations the tree allows; the exact prerequisites are read off the Wowhead Legacy calculator at build time.

Out of scope for v1: Dedicated Study (+1 skill per day is time, not gold; later it can be an "I have N days" option), Bountiful Harvest (gathering), Luremaster (fishing), Performance Bonus (crate turn-ins), Reagent Economy (class abilities).

### 3.5 Shopping list (Auctionator)

- Create a real Auctionator shopping list with **quantities**, using `Auctionator.API.v1.CreateShoppingList(callerID, name, searchStrings)` and `ConvertToSearchString` with `quantity` and `isExact`. Both are confirmed in the installed Auctionator.
- Creating a list replaces any list with the same name. Say so on the button.
- Subtract bags and bank before writing quantities. Bank counts are from the last time the bank was open.
- Leave vendor-bought items off the AH list; show them in a separate "buy from vendor" list.
- Name lists clearly, for example `CraftPath: Tailoring 1-150`.
- Include a copyable text version for Discord or alts.

### 3.6 Transparency

- Every step shows: price source, unit net cost, and why it beat the alternative.
- Bob does not trust Profession Master's black box. Earn trust with receipts.

---

## 4. Data sources

| Data | Source | Notes |
|---|---|---|
| Recipes, skill colours, output counts, recipe source and cost | ForeverMaster `ForeverMasterData.leveling` | Primary source. 8 trades: Alchemy, Blacksmithing, Cooking, Enchanting, Engineering, First Aid, Leatherworking, Tailoring |
| Item vendor-sell value and sold-by-vendor flag | ForeverMaster `ForeverMasterData.leveling[trade].items` | |
| Wider recipe catalogue | ForeverMaster `ForeverMasterData.recipes` | For opportunity crafts only |
| AH prices | Auctionator API v1 | |
| Vendor buy prices | ForeverMaster leveling data, overridden by prices seen at merchants | |
| Vendor sell prices | Game item data, Auctionator vendor cache | |
| DE probabilities | Copy of Auctionator's classic disenchant table, bundled in CraftPath | Assumption. Auctionator's own DE API does not work on Forever (check V1) |
| Shopping lists | Auctionator API v1 | `CreateShoppingList`, `ConvertToSearchString` |
| Bags and bank | Own scan | |

Dependencies: ForeverMaster and Auctionator are required. Nothing else. The planner does not use CraftProfit.

ForeverMaster's data is an undocumented packed format that can change with any data pack (currently `2026-10-22.0744`). The planner validates the shape on load and, on a mismatch, disables itself with a clear message instead of producing wrong routes.

Known gaps:

- No Herbalism or Skinning recipe trees (gathering, not a craft path).
- Mining has recipes but no leveling table, so no Mining route in v1.
- Fishing has 3 recipes and no leveling table.
- Enchanting needs rods and its output is mostly enchants with nothing to sell, so its net cost is close to its gross cost.

---

## 5. Execution (v1.5)

Planner-first. Execution is a layer on top, not the core product. Both items depend on the checks in section 8.

- **Craft N from the path.** Call: `C_TradeSkillUI.CraftRecipe(recipeID, numCasts)`, confirmed present on Forever. The profession window must be open and the craft starts from a button click. Example: "Craft this step's 47." Enchanting is untested (no enchanter on the account), so its button only opens the recipe.
- **Vendor restock.** On `MERCHANT_SHOW`, buy the path's missing vendor mats with `BuyMerchantItem`. The player is at the vendor and clicks to confirm the restock. Not a world-walking bot.

---

## 6. Build

One build, no phases (Liam, 12 Nov 2026): everything in sections 3 and 5 ships together as CraftPath 1.0.0.

- Source: `~/Projects/CraftPath`. Installed copy: the `_forever_` AddOns folder.
- `Solver.lua` and `DisenchantData.lua` are generated from ForeverMaster and Auctionator by the scripts in `tools/`. Rerun them after either addon updates.
- `tests/solver_test.lua` checks the solver against ForeverMaster's own on the installed data. `tests/addon_test.lua` loads the whole addon against a stand-in for the game and clicks through it.

---

## 7. Out of scope

- A Profession Master clone or a craft dashboard that only wraps the Blizzard window. Use PM for UX ideas only.
- Gathering leveling guides (Herbalism, Skinning, Mining farming).
- Auto-buy from the AH without the player present.
- Auto-posting or undercutting on the AH.
- Perfect DE loot tables.
- Walking vendors automatically (bot behaviour).

---

## 8. Checks to run in game

These cannot be settled from the files. Results so far are from Liam's run on 12 Nov 2026.

| # | Check | Status | Result or how to run |
|---|---|---|---|
| V1 | Auctionator's disenchant tables load on Forever | Done: they do not | Forever loads Auctionator's retail disenchant code, which only knows items from later expansions, so its API returns nothing for Forever items. CraftPath carries its own copy of Auctionator's classic table instead (3.2) |
| V2 | Which craft call exists | Done | `C_TradeSkillUI.CraftRecipe` exists; `DoTradeSkill` does not |
| V3 | Vendor buying | Done | `BuyMerchantItem` exists |
| V4 | Working Overtime maths | Automatic | No manual test. CraftPath counts crafts and skill-ups itself while you level (3.3) and reports which formula fits |
| V5 | Enchanting's window | Parked | No enchanter on the account. Enchanting routes are planned, but its step button only opens the recipe |
| V6 | Perk allocation readable | Dropped | Not worth chasing. Perk ranks are typed in per character (3.4) |
| V7 | Deposit amount and refund | Done | Refunded when the item sells; the 5% fee is kept. Measured: 20 Gooey Spider Cake (vendor 1s each) cost 12s to list for 24 hours, which is 60% of vendor value, double the classic rate |
| V8 | Point cost per perk rank | Done | One point per rank, 16 points per character (Wowhead Legacy calculator: Working Overtime 5/5 plus a 2/2 perk shows 7/16). The tree also has prerequisite arrows and 5-point and 10-point markers; see 3.4 |

---

## 9. Later or optional

- **Alt perk presets.** Example: Working Overtime 5 + Bartering 2 for cheap leveling. Master Chef 5 for a Cooking alt.
- **Price-history awareness.** Show whether today's price is cheap or high versus normal, as CraftProfit does.
- **Alt batch planner.** Level N alts to 150, one shared buy list, total legacy-point ROI.
- **Gathering cost toggle.** Let the player count farmable mats at zero or at a time cost instead of the AH price.
- **Dedicated Study** as an "I have N days" option.
- **Export and share** the route.

---

## 10. Decisions

| Question | Decision |
|---|---|
| Inside CraftProfit or separate | Separate addon with no link to CraftProfit |
| Name | CraftPath |
| Distribution | Public GitHub repository, derived files credited (Liam, 12 Nov 2026) |
| Solver | Start from a copy of ForeverMaster's solver and extend it, over ForeverMaster's data |
| Flip defaults | 5% cut, sell rate 0.35 to 0.9 by item kind, capped by listed quantity, deposit counted on the share that does not sell (24-hour listing, 60% of vendor sell) |
| Skill-up default | Expected |
| Perk detection | Manual toggles per character |
| Gathered mats | Counted at AH price, since a mat you farm could have been sold |
| New alt with unspent points | Show both: no points spent, and the best allocation of the points available |

## 11. Open questions

- None.

---

## 12. Sources consulted

- Chat notes: Liam, Maz, Bob (Discord).
- ForeverMaster addon (`_forever_` install): `Data/Recipes.lua`, `Data/Leveling.lua`, `Lib/Leveling.lua`, `Lib/Owned.lua`, `UI/Pages/Leveling.lua`.
- CraftProfit (`~/Projects/CraftProfit`), for reference only: `Missing.lua`, `PriceSources.lua`, `VendorPrices.lua`, `README.md`.
- Auctionator (`_forever_` install): `Auctionator.toc`, `Source/API/v1/ShoppingLists.lua`, `GetDisenchantPrice.lua`, `GetVendorPrice.lua`, Classic disenchant probability tables.
- Legacy perk details: azeroth.wiki Legacy profession perks and Legacy points guides, WoW Campfire legacy system guide.
- Craft and vendor APIs: Warcraft Wiki `C_TradeSkillUI.CraftRecipe`, `BuyMerchantItem`.
