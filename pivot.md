# Level up item spawn logic
Level up allows you to level up current items or pick new ones. Here is the generic logic, with all game-specific references removed.

Level-up item selection logic

When the player levels up, the game should generate a small list of item choices. These choices can be either:

A new item the player does not have yet
An upgrade to an item the player already owns

The system is not fully random. It should be weighted random with priority rules.

1. Build the eligible item pool

Before showing level-up choices, the game creates a list of valid options.

An item is eligible if:

It has been unlocked
It is not banned/removed from the current run
It is not already max level
The player has room for it, if it is a new item
The player already owns it, if it is an upgrade

So the pool can contain:

Owned items that can still be upgraded
+
New items that can still be picked

If the player’s item slots are full, then new items are removed from the pool, and only upgrades can appear.

2. Give owned items priority

The game should try to offer upgrades for already-owned items first.

Example logic:

For each level-up choice slot:
    Roll chance to offer an owned item upgrade.
    
    If successful:
        Pick one upgradeable owned item.
    Else:
        Pick from the general eligible item pool.

This makes the system feel better because once the player chooses an item, they are more likely to see upgrades for it later.

Without this rule, the player may pick an item and then not see its upgrade for too long, which feels bad.

3. Use weighted randomness

Each item should have a spawn weight.

Example:

Common item: weight 100
Uncommon item: weight 50
Rare item: weight 20
Very rare item: weight 5
Legendary item: weight 1

Chance of seeing an item:

item weight / total weight of all eligible items

Example:

Item A weight = 100
Item B weight = 50
Item C weight = 25

Total weight = 175

Item A chance = 100 / 175 = 57.1%
Item B chance = 50 / 175 = 28.6%
Item C chance = 25 / 175 = 14.3%

So it is random, but not equally random.

4. Prevent duplicate choices in the same level-up

The same item should not appear twice in one level-up screen.

Bad:

Upgrade Cannon
Upgrade Cannon
Pick Shield

Good:

Upgrade Cannon
Upgrade Engine
Pick Shield

After an item is selected for one choice slot, temporarily remove it from the pool for the remaining slots.

5. New items vs current item upgrades

A good generic rule is:

If the player owns upgradeable items:
    Give upgrades a higher chance to appear.

If the player has empty item slots:
    Allow new items to appear.

If the player has full item slots:
    Only show upgrades.

Example probability:

70% chance: show upgrade to owned item
30% chance: show new item

This does not have to be fixed. You can change it based on game design.

For example:

Early game
50% upgrade
50% new item

This helps the player build their loadout.

Mid game
70% upgrade
30% new item

This helps the player strengthen their chosen build.

Late game
90% upgrade
10% new item

Or, if item slots are full:

100% upgrade
0% new item
6. Level-up choice algorithm

A simple version:

function generateLevelUpChoices(player, choiceCount):
    choices = []

    ownedPool = getOwnedUpgradeableItems(player)
    newPool = getNewAvailableItems(player)
    generalPool = ownedPool + newPool

    repeat until choices has choiceCount items:
        remove items already in choices from all pools

        if ownedPool is not empty and randomChance(ownedUpgradePriority):
            item = weightedRandom(ownedPool)
        else:
            item = weightedRandom(generalPool)

        add item to choices

    return choices
7. Cleaner version with fallback logic
function generateLevelUpChoices(player, choiceCount):
    choices = []

    while choices.count < choiceCount:
        ownedPool = getOwnedUpgradeableItems(player)
        newPool = getNewAvailableItems(player)

        remove choices from ownedPool
        remove choices from newPool

        if player.itemSlotsAreFull:
            candidatePool = ownedPool
        else:
            if ownedPool is not empty and roll(ownedUpgradeChance):
                candidatePool = ownedPool
            else:
                candidatePool = ownedPool + newPool

        if candidatePool is empty:
            break

        selectedItem = weightedRandom(candidatePool)
        choices.add(selectedItem)

    return choices
8. Example behavior

Suppose the player has:

Owned items:
- Cannon, level 2 / 5
- Shield, level 1 / 5
- Engine, max level

Available new items:
- Drone
- Missile
- Armor
- Reactor

The eligible pool becomes:

Cannon upgrade
Shield upgrade
Drone
Missile
Armor
Reactor

The maxed item is excluded:

Engine is removed because it cannot be upgraded anymore.

If the system prioritizes owned upgrades, the player is more likely to see:

Cannon upgrade
Shield upgrade
Missile

Instead of:

Drone
Missile
Armor

This helps the player complete their build instead of being flooded with new options.

9. Item spawn summary

A strong item spawn system should use:

Eligibility rules
+ Spawn weights
+ Owned-item priority
+ No duplicate choices
+ Slot limits
+ Fallback behavior

The result feels random, but controlled.

The player still gets surprises, but the game does not feel unfair. Early choices matter because once an item is picked, it becomes part of the upgrade pool and will appear more often later.

Also add in these items that could drop at random as well. They are also items that could be picked up. These items slots will be similar to the weapons but in a lower row. No images for them right now so just generate some color for place holder | Effect       | Auxiliary Item Name      |
| ------------ | ------------------------ |
| +HP          | **Reinforcement plate**          |
| +Regen       | **Nanobots**       |
| +Armor       | **Exoskeleton** |
| +Speed       | **Fins**        |
| +Damage      | **Accelerated muzzle**        |
| +Fire Rate   | **Auto-Loader**          |
| +Pierce %    | **Penetrator Rounds**    |
| +AOE         | **Explosivo**      |
| +Pick Up     | **Magnet**       |
| +EXP         | **Data Harvester**       |
| +Enemy Spawn | **Beacon**        |
|+ Retaliation (return flat damage on taking damage) | Barbed wire
| +Revival     | **Backup image**       |
| +Coin        | **Credit Extractor**     |
