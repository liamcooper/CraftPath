# CraftPath

A World of Warcraft Forever addon that finds the cheapest route to a profession skill target, measured in net gold: what you spend on materials and recipes, less what you get back for the things you make.

Type `/craftpath` in game, or click the minimap button. Needs ForeverMaster and Auctionator.

## What's in it

- **Route.** The cheapest route for any of 8 professions (Alchemy, Blacksmithing, Cooking, Enchanting, Engineering, First Aid, Leatherworking, Tailoring) to any skill target, whether or not the character has learned it. Each step shows what to buy, what you get back, the skill-up chance, the cost per skill point, and the next-best alternative or the reason it was passed over.
- **Recovery modes.** Keep (nothing is sold), Strict (sold to a vendor) and Flip (sold on the auction house where that beats the vendor, after the 5% cut, a haircut for what will not sell, and the deposit lost on it). Disenchant value is a separate switch, for accounts with an enchanter.
- **Legacy perks.** Set Working Overtime, Bartering and Master Chef ranks per character. The Perks tab compares no points against the best use of the points you allow, with the saving per point and per perk, and a "Use this" button.
- **Recipes worth buying.** A recipe on the auction house, or at a limited-stock vendor, goes into the route automatically when the route is cheaper with it after paying for it. A "Can't get it" button plans again without it. Recipes you cannot simply buy are listed with what they would save.
- **Check prices.** At the auction house, reads the real listings of the materials the route buys. The route is then costed at what those quantities really cost, not at the cheapest listing, and moves to another material when one gets dear in bulk.
- **Shopping.** An Auctionator shopping list with quantities, less what is in your bags and bank, a separate vendor list, and a copy-as-text window for Discord or an alt.
- **Board.** Every profession to 150 and 300 for this character, cheapest first.
- **Opportunities.** Recipes whose result is worth more than its materials right now.
- **Buttons.** "Craft N" on each step, and a "buy missing mats" button above the vendor window.
- **Log.** Counts your yellow and green crafts and works out whether Working Overtime adds to the skill-up chance or multiplies it.
- **Minimap button.** Click to open, drag to move, `/craftpath minimap` to hide or show.

## Check prices in detail

Auctionator remembers only the cheapest listing of an item. If a route needs 1,500 Linen Cloth and 300 are listed at 6c, pricing all 1,500 at 6c makes that route look far cheaper than it is.

Press **Check prices** with the auction house open and CraftPath:

1. Reads the listings for each material the route buys, one search per material.
2. Plans the route again at what those quantities cost, a few times over. A material that gets dear in bulk pushes the route to another one, and the route with the lowest real cost is kept.
3. Reads any material the route moved to, so an alternative never looks cheap only because nobody looked.

What you see afterwards:

- **Shopping tab:** bulk buys show an average price, with a line such as "cheapest 6c, dearest you would pay 3g, 250 more than are listed".
- **Route tab:** a red line for any material there is not enough of.
- **Status bar:** how many of the route's materials have had their listings read.

Units beyond what is listed are priced at the dearest listing and flagged. Listings are a snapshot: they are kept for 24 hours and not read again within 10 minutes. Before any check, the planner uses the cheapest listing and warns when Auctionator saw fewer listed than the route needs.

## Things to know

- **Extra material crafts.** Routes often need more intermediates (bolts of cloth, bars) than the steps themselves make. These appear under "Also make these materials" with their own Craft button.
- **Auction-house recipes** must still win at 20% over their scanned price plus 50s, because the listing may have gone. If the target cannot be reached without a recipe, the route buys it whatever it costs.
- **Deposits** are estimated at 60% of vendor value for a 24-hour listing, measured on Forever, and are only lost on what does not sell.
- **Disenchant values** come from the classic disenchant table and are an average, not a promise.
- **Legacy perk prerequisites** are assumed to be none for the three perks.
- **Known recipes.** If trainer fees are counted for recipes you already know, open the profession window once and press Refresh.
- **Saved data.** Settings, perk ranks and the skill-up log are kept per character.

Requirements and decisions are in `REQUIREMENTS.md`.

## Credits

CraftPath builds on two other addons:

- `Solver.lua` is derived from the route solver in [ForeverMaster](https://foreverchanges.pro) (`Lib/Leveling.lua`), extended with Legacy perks, recovery modes, disenchant value and recipe buying. It also reads ForeverMaster's recipe data at runtime.
- `DisenchantData.lua` is derived from the classic disenchant table in Auctionator, by plusmouse and Borjamacare.

Those parts remain the work of their authors and are not covered by any licence granted here.

## Build and test

`Solver.lua` and `DisenchantData.lua` are generated. Rerun after ForeverMaster or Auctionator update:

```
python3 tools/make_solver.py "<AddOns>/ForeverMaster/Lib/Leveling.lua" Solver.lua
python3 tools/make_disenchant.py "<AddOns>/Auctionator/Source_Classic/Enchant/DisenchantingProbabilities.lua" DisenchantData.lua
```

Tests need a Lua 5.1 interpreter:

```
lua tests/solver_test.lua "<AddOns>/ForeverMaster" .
lua tests/addon_test.lua "<AddOns>/ForeverMaster" .
```

To install, copy `CraftPath.toc` and the `.lua` files into `<AddOns>/CraftPath`.
