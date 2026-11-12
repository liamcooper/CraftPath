# CraftPath

A personal World of Warcraft Forever addon: the cheapest route to a profession skill target, measured in net gold.

Type `/craftpath` in game. Needs ForeverMaster and Auctionator.

- Route for any of 8 professions to any target, with a receipt on every step
- Recovery modes: Keep, Strict (vendor), Flip (auction house, after cut and lost deposits), optional disenchant
- Legacy perks per character, with a no-points against best-points comparison
- Auctionator shopping list with quantities, less bags and bank
- Compare board, opportunity crafts, craft and vendor-restock buttons, skill-up log

Requirements and decisions are in `REQUIREMENTS.md`.

## Not for distribution

`Solver.lua` is derived from ForeverMaster's solver and `DisenchantData.lua` from Auctionator's classic disenchant table. Keep this repository private.

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
