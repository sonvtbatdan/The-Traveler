Add a character level/XP system to my Godot 4 game. I'm not a programmer — plain language, phases, pause between them. I want Diablo 2 / Borderlands 2-style progression: fast and rewarding early, deliberately slow grind at higher levels. First read the code and report findings before building.
Phase 0 — Investigate and report (no code). Tell me:

Where player stats live (HP, armor, energy) and how max values are computed now — I want levels to add to these.
How XP-worthy events work: how asteroids are destroyed and how boss kills are detected (so I can award XP from both).
The existing item-tier system: confirm WEAPON_ROLL_TIER and the Low/Mid/High affix tiers, and how boss drops choose a tier — I want level to influence drop tier later.
Where the Character Sheet panel is, so I can add Level + an XP bar to it.
Pause and report.

Phase 1 — Core XP + level data and the curve.

Add player level (start at 1) and current XP, stored and saved like other player data.
XP-to-next-level uses an accelerating curve: xp_to_next(level) = round(BASE_XP * pow(GROWTH, level - 1)). Start with BASE_XP = 100 and GROWTH = 1.12 as tunable constants. This makes early levels quick and later levels progressively much longer (the intended "drags out late" feel). Add a MAX_LEVEL constant (say 50 to start, tunable).
Gaining XP past the threshold levels up (handle multiple level-ups from one big XP gain, e.g. a boss). On level-up, emit a signal so UI/effects can react.
Add a clear add_xp(amount) function as the single entry point.
Pause so I can call add_xp from a debug button and watch levels go up with the widening curve. Show me the XP required for levels 2, 10, 30, and 50 so I can sanity-check the pacing before we tune.

Phase 2 — Award XP from gameplay.

Asteroids: award a small XP trickle per asteroid destroyed (tunable per asteroid, or scaled by asteroid size if size exists).
Bosses: award a large XP chunk on boss kill (tunable, much bigger than asteroids — bosses are the "event" rewards).
Make both amounts tunable constants. Tell me roughly how many asteroids / bosses it takes to hit level 5, 10, 20 with current numbers, so I can judge the pace.
Pause so I can play, kill things, and feel the early pace.

Phase 3 — Level-up rewards (keep them meaningful but not explosive).
On each level-up, grant a small permanent boost to the player's base stats — a tunable amount of max HP, armor, and max energy per level (start small, e.g. +5 HP, +2 armor, +1 energy/level — tunable). These stack with gear. Make sure the Character Sheet reflects the level-based bonuses separately or folded into the totals (tell me which).
Pause so I can confirm leveling makes me tangibly stronger.
Phase 4 — UI: Level + XP bar.
Add Level and an XP progress bar (current XP / xp-to-next) to the Character Sheet panel, styled to match. A small level-up visual/flash when it happens is a nice touch if easy. Pause so I can see it.
Phase 5 (design hook only, don't fully build) — tie drop tier to level.
Leave a clearly-marked, easy-to-edit spot where the boss-drop tier (Low/Mid/High, currently WEAPON_ROLL_TIER) can be chosen based on player level instead of a fixed value — e.g. low levels → Low tier drops, mid → Mid, high → High. Don't fully implement the thresholds yet; just wire the hook and a placeholder mapping, and tell me where to set the level breakpoints. This is the Diablo "better gear as you climb" loop and I'll tune it separately.
Throughout: all pacing numbers (BASE_XP, GROWTH, MAX_LEVEL, XP per asteroid/boss, per-level stat gains) must be clearly-named tunable constants in one easy-to-find place, since I'll be balancing these by feel. Don't change combat, generation, or the firing systems. At the end, summarize every constant I can tune and what each does to the pacing.