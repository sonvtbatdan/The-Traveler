Big update: add 5 new normal enemies to my Godot 4 space shooter. I'm not a programmer — plain language, and this MUST be built in phases with a pause after EACH enemy so I can test it in isolation before moving on. Do NOT build all five at once. Build the simplest first and the most complex last. First investigate and report.
Phase 0 — Investigate and report (no code yet). Tell me in plain language:

How existing damageable things (asteroids, boss) are structured — is there a base "enemy/damageable" pattern I can reuse, or does each define its own? I want all 5 new enemies to share ONE common base for HP, taking damage, and dying.
Confirm enemies take damage through the existing enemy armor / damage-reduction system (DR = 0.005*armor/(1+0.005*armor)) so my weapons and the acid gun's armor-shred work on them. New enemies default to 0 armor unless I specify otherwise.
How the player takes damage and how player collision is detected (several enemies damage the player on contact).
How to award XP on kill (I have a level system with an add_xp function) — I want these enemies to grant XP. For loot drops: none from normal enemies for now (XP only), but tell me where I'd add drops later.
Where enemy bullets/projectiles are handled (several enemies shoot).
Whether there's a spawn director/manager, or if I should spawn these on simple tunable timers for now.
Pause and report before building.

Phase 1 — Shared enemy foundation. Create a common base for normal enemies: HP, armor (default 0, using the existing DR formula), taking damage, dying (award XP via add_xp, no loot), and a simple way for me to spawn each type for testing. Build a basic reusable enemy bullet (damages player on hit, tunable damage) for the ones that shoot. Get this skeleton working with ONE trivial placeholder enemy before the real five. Pause so I can confirm: an enemy spawns, takes damage from my weapons (and acid armor-shred affects it), dies, and gives XP.
Build each enemy as its own phase. Pause after each. Every number below is a tunable constant grouped per enemy.
Phase 2 — Kingfisher (do first, simplest):

Enters from any of the 4 screen edges, lined up with the player's current position.
A warning sign appears at the entry point; 1 second later the Kingfisher enters at that exact point and zooms in a straight line at 1000px/s.
HP 40. Explodes on contact with the player only, collision damage 10.
Which edges it can spawn from must be configurable per stage/map (e.g. map 1 = top only; map 2 = top + left). Make this a tunable list so different stages use different edge sets.
Pause.

Phase 3 — Jet_fighter:

Enters at a 45° angle from the top 25% of the screen, travels ~1cm inward, then stops advancing.
Then fires decently fast, non-aimed bullets toward the player's position at the moment of each shot (aimed once at launch, bullets do NOT track). Fire rate 1/s. Bullet damage 5.
HP 50.
Pause.

Phase 4 — Sentinels:

Enter from the top, 2 at a time, descend to 35% down the screen, then stay stationary.
Fire 3 rays of bullets, 5 bullets per ray, each ray ~25° apart (a spread fan). Fire rate: 1 volley per second.
HP 70. Bullet damage 5.
Pause.

Phase 5 — Bombing_wanderer:

Enters from the left or right edge at 80% height (measured from the bottom up), travels horizontally at 300px/s.
Drops a bomb when it starts traveling horizontally, then every 3 seconds after (every 3s — ignore any "2s" interpretation).
Wanderer HP 120.
Bombs are a SEPARATE enemy type: HP 50. A bomb explodes on contact with the player, AND explodes when its HP reaches 0. The explosion damages EVERYTHING — other enemies, the boss, AND the player (explosion damage 20). Bombs give no loot and no XP. Tell me how you made the explosion hit all factions (enemies + boss + player).
Pause.

Phase 6 — Swarm (do LAST, most complex):

Spawns as a flock of 8. They enter from the top quarter of the screen (either side edge) in a straight line, travel ~2cm straight, then curve upward and bend around to form a circle made up of all 8 enemies.
Once the circle is complete, wait 0.5 seconds, then all 8 zoom toward the player at 900px/s — but with turn-rate-limited homing, NOT aim-once and NOT instant turning:

Each swarm enemy moves forward at 900px/s.
Every frame it computes the direction to the player's CURRENT position, but it can only rotate its heading toward that direction by a maximum turn rate (degrees per second) — a tunable constant. So it bends/curves toward the player gradually; it cannot pivot in place or snap to face the player.
Consequence (intended): if the player dodges sharply, a swarm enemy overshoots and has to arc back around for another pass. The max turn rate is the single knob that controls how dangerous the homing feels — high = hard to dodge, low = easy to juke. Start moderate and let me tune it. (This is the same turn-rate-limited homing concept as my homing missile — reuse that approach if it helps.)


HP 20 each. Explode on contact with the player only, collision damage 10.
The circle-formation movement is the hard part — build it carefully and let me watch the 8 form the circle before the zoom, so I can tune the formation separately from the homing.
Pause.

Throughout: every HP, speed, damage, fire rate, count, timing, spawn-edge list, and the swarm's max turn rate must be a clearly-named tunable constant grouped per enemy. All enemies use the shared base from Phase 1 and take damage through the armor/DR system. Killing them grants XP (except bombs). After all phases, give me a summary of every enemy's tunable constants and how to spawn each one for testing.