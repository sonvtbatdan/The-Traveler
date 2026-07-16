extends Node
## Arena auxiliary (passive) items — the second item class alongside weapons (arena_weapons.gd). Each aux
## item grants a flat run-stat bonus routed into GameManager's upg_* store, and can be leveled up (1..MAX_AUX_LEVEL)
## from the level-up screen; each level re-applies its per-level effect once. No firing logic and no art yet —
## the level-up UI + the aux slot HUD draw a placeholder COLOR per item.
##
## Pure data layer: owns no visuals. Added to group "arena_aux" so the level-up UI and the slot HUD can find it.
## Per-run state lives only here (a fresh node each run) + GameManager.upg_* (zeroed by reset_run), so each run
## starts clean.

const MAX_AUX       := 4    # aux slot count (second HUD row) / acquisition cap
const MAX_AUX_LEVEL := 18   # pooled aux level 1→18; each point spent = +1 level, then EVOLVE

# ── AUX CATALOG ──────────────────────────────────────────────────────────────────
# id        — unique key (also the effect dispatcher key in _apply_effect)
# name      — display name
# color     — placeholder swatch (no art yet) for cards + slots
# weight    — spawn weight in the level-up roll (rarer effects → lower weight)
# effect    — short per-level description for the card
const AUX_DEFS := [
	{"id": "hp",          "name": "Reinforcement Plate", "color": Color(0.40, 0.85, 0.45), "weight": 100, "effect": "+20 Max HP"},
	{"id": "regen",       "name": "Nanobots",            "color": Color(0.45, 0.90, 0.70), "weight": 80,  "effect": "+0.5 HP/s"},
	{"id": "armor",       "name": "Exoskeleton",         "color": Color(0.55, 0.62, 0.70), "weight": 80,  "effect": "+2 Armor"},
	{"id": "force_field", "name": "Force Field",         "color": Color(0.40, 0.70, 1.00), "weight": 50,  "effect": "+20 Max Shield (1/s regen)"},
	{"id": "speed",       "name": "Fins",                "color": Color(0.45, 0.75, 1.00), "weight": 90,  "effect": "+6% Speed"},
	{"id": "damage",      "name": "Art of War",          "color": Color(1.00, 0.45, 0.35), "weight": 70,  "effect": "Damage masteries"},
	{"id": "fire_rate",   "name": "Auto-Loader",         "color": Color(1.00, 0.65, 0.30), "weight": 70,  "effect": "+8% Fire Rate"},
	{"id": "armor_pen",   "name": "Drill Bits",          "color": Color(0.90, 0.80, 0.40), "weight": 40,  "effect": "Armor penetration + bleed"},
	{"id": "crit",        "name": "Aim Assistor",        "color": Color(1.00, 0.35, 0.35), "weight": 50,  "effect": "+5% Crit Chance"},
	{"id": "harmonizer",  "name": "Harmonizer",          "color": Color(0.70, 0.50, 1.00), "weight": 30,  "effect": "+Type Damage"},
	{"id": "aoe",         "name": "Explosivo",           "color": Color(1.00, 0.55, 0.20), "weight": 40,  "effect": "+25 AoE"},
	{"id": "pickup",      "name": "Magnet",              "color": Color(0.55, 0.85, 0.95), "weight": 90,  "effect": "+15% Pickup"},
	{"id": "xp",          "name": "Data Harvester",      "color": Color(0.65, 0.55, 1.00), "weight": 60,  "effect": "+10% EXP"},
	{"id": "spawn",       "name": "Beacon",              "color": Color(0.85, 0.40, 0.55), "weight": 30,  "effect": "+15% Spawns"},
	{"id": "retaliation", "name": "Barbed Wire",         "color": Color(0.80, 0.35, 0.30), "weight": 40,  "effect": "+5 Retaliation"},
	{"id": "revival",     "name": "Backup Image",        "color": Color(1.00, 0.85, 0.35), "weight": 10,  "effect": "+1 Revive"},
	{"id": "coin",        "name": "Credit Extractor",    "color": Color(1.00, 0.90, 0.45), "weight": 60,  "effect": "+25% Coin"},
]

# ── Skill-point POOLS for aux items (mirrors arena_weapons' weapon pools). Only items listed here use the
# 2-tier "pick a perk" flow + level rewards + evolution; every other aux still levels simply via _apply_effect.
# id → {pool_id → {name, max, per, desc}}.
const AUX_POOL := {
	"hp": {
		"plating":   {"name": "Reinforced Plating",   "max": 10, "per": "+20 Max HP",            "desc": "The alloy cladding panels reinforce the ship's hull structure, enhancing its structural integrity.", "desc_vi": "Tấm ốp hợp kim gia cố cấu trúc thân tàu, tăng cường tính toàn vẹn cấu trúc."},
		"bulwark":   {"name": "Bulwark",              "max": 10, "per": "+10 HP, +1 Armor",      "desc": "The multi-layered defensive armor system optimizes shock absorption and core protection.", "desc_vi": "Hệ thống giáp phòng ngự nhiều lớp, tối ưu hóa khả năng hấp thụ chấn động và bảo vệ lõi."},
		"ablative":  {"name": "Ablative Layer",       "max": 10, "per": "+10 HP, +2% Speed",     "desc": "The heat-dissipating coating protects the hull from damage without increasing the static weight.", "desc_vi": "Lớp phủ tản nhiệt tiêu hao, bảo vệ thân tàu khỏi sát thương mà không làm tăng khối lượng tĩnh."},
		"sacrifice": {"name": "Sacrificial Armor",    "max": 5,  "per": "-5% Max HP, +5% Damage", "desc": "The protocol redirects energy from the protective shield to the core weapon system.", "desc_vi": "Giao thức chuyển hướng năng lượng từ màng chắn bảo vệ sang hệ thống vũ khí cốt lõi."},
		"mastery":   {"name": "Reinforcement Mastery", "max": 5, "per": "+5% to all HP gains",    "desc": "The algorithm optimizes the microstructure, amplifying the performance of every hull reinforcement module.", "desc_vi": "Thuật toán tối ưu hóa cấu trúc vi mô, khuếch đại hiệu suất của mọi mô-đun gia cố thân tàu."},
		"overall":   {"name": "Overall Improvement",  "max": 5,  "per": "+1% HP/Dmg/Speed/Armor", "desc": "This comprehensive micro-patch involves fine-tuning the entire mechatronics system of the warship.", "desc_vi": "Bản vá vi chương trình toàn diện, tinh chỉnh vi mô toàn bộ hệ thống cơ điện tử của chiến hạm."},
	},
	"regen": {
		"regen_flat":    {"name": "Repair Swarm",        "max": 10, "per": "+0.2 HP regen/s",         "desc": "The protocol deploys swarms of nanobots to automatically repair micro-cracks on the ship's hull surface.", "desc_vi": "Giao thức triển khai bầy nanobot tự động hàn gắn các vi nứt trên bề mặt vỏ tàu."},
		"regen_hp":      {"name": "Mending Cloud",       "max": 10, "per": "+0.1 HP regen, +10 HP",   "desc": "The intelligent nanoparticle cloud clings to the shell, continuously renewing the material and reinforcing its underlying strength.", "desc_vi": "Đám mây hạt nano thông minh bám quanh vỏ, liên tục tái tạo vật liệu và củng cố độ bền cơ bản."},
		"regen_shield":  {"name": "Shield Weavers",      "max": 10, "per": "+0.1 HP regen, +0.1 shield/s", "desc": "The bipolar system simultaneously intertwines protective force fields and activates a self-repairing matrix.", "desc_vi": "Hệ thống lưỡng cực, đồng thời đan xen trường lực bảo vệ và kích hoạt ma trận tự sửa chữa."},
		"regen_mastery": {"name": "Regeneration Mastery", "max": 5, "per": "+5% to ALL regen",        "desc": "The recovery protocol has been upgraded, accelerating the molecular regeneration rate of both the hull and the force field.", "desc_vi": "Nâng cấp giao thức phục hồi, đẩy nhanh tốc độ tái tạo phân tử của cả vỏ tàu và trường lực."},
		"automation":    {"name": "Automation Speed",    "max": 5,  "per": "+5% automation wpn speed", "desc": "Overriding the processor limitations of automated weapon systems enhances machine response speed.", "desc_vi": "Ghi đè giới hạn vi xử lý của các hệ thống vũ khí tự động, tăng cường tốc độ phản hồi máy móc."},
		"overregen":     {"name": "Overflow Plating",    "max": 5,  "per": "Over-regen → shield, +10 Max Shield", "desc": "Excess energy conversion: when the hull is intact, renewable materials are converted into an additional shielding layer.", "desc_vi": "Bộ chuyển đổi năng lượng dư thừa: khi thân tàu nguyên vẹn, vật liệu tái tạo được chuyển hóa thành lớp màng chắn bổ sung."},
	},
	"armor": {
		"ex_armor":    {"name": "Plate Layering",   "max": 10, "per": "+2 Armor",                 "desc": "The technique of stacking multi-layered reactive armor neutralizes the kinetic energy of direct collisions.", "desc_vi": "Kỹ thuật xếp chồng giáp phản ứng đa lớp, triệt tiêu động năng của các vụ va chạm trực tiếp."},
		"ex_armor_hp": {"name": "Reinforced Joints", "max": 10, "per": "+1 Armor, +1 HP",          "desc": "Reinforcing mechanical joints with titanium-carbon alloy minimizes the risk of structural fracture.", "desc_vi": "Gia cố các điểm nối cơ học bằng hợp kim titan-cacbon, giảm thiểu nguy cơ đứt gãy cấu trúc."},
		"ex_predr":    {"name": "Damping Mesh",      "max": 5,  "per": "+3% DR (pre-armor)",       "desc": "The electromagnetic grid disperses the impact force, weakening the beam and kinetic energy before they reach the main armor layer.", "desc_vi": "Lưới điện từ phân tán lực tác động, làm suy yếu chùm tia và động năng trước khi chúng chạm vào lớp giáp chính."},
		"ex_reflect":  {"name": "Caltrop Plating",   "max": 5,  "per": "+8% projectile reflect",   "desc": "The ship's hull surface incorporates a micro-field of force reflection, capable of deflecting or bouncing back incoming flying objects.", "desc_vi": "Bề mặt vỏ tàu tích hợp vi trường lực phản hồi, có khả năng làm chệch hướng hoặc dội ngược các vật thể bay tới."},
		"ex_mastery":  {"name": "Harden Mastery",    "max": 5,  "per": "+5% armor effectiveness",  "desc": "Optimizing the molecular bonds of the entire armor system maximizes its resistance to external forces.", "desc_vi": "Tối ưu hóa liên kết phân tử của toàn bộ hệ thống giáp, tối đa hóa khả năng chống chịu ngoại lực."},
		"ex_crit":     {"name": "Weak-Point Optics", "max": 5,  "per": "+5% kinetic crit chance",  "desc": "The optical module analyzes the spectral structure, locating weak points on the target's armor for kinetic energy weapons.", "desc_vi": "Mô-đun quang học phân tích cấu trúc quang phổ, định vị điểm yếu trên vỏ giáp mục tiêu cho vũ khí động năng."},
	},
	"armor_pen": {
		"pen_flat":      {"name": "Carbide Tips",   "max": 10, "per": "+2 flat armor penetration",  "desc": "The warhead is coated with a super-hard carbide alloy, easily penetrating standard armor plating.", "desc_vi": "Đầu đạn được bọc lớp hợp kim carbide siêu cứng, dễ dàng xuyên thủng các lớp giáp tiêu chuẩn."},
		"pen_pct":       {"name": "Spiral Fluting", "max": 10, "per": "+5% armor penetration",      "desc": "The aerodynamic rifling design on the ammunition creates a drilling effect that penetrates the integrity of heavy armor.", "desc_vi": "Thiết kế rãnh xoắn khí động học trên đạn dược, tạo hiệu ứng khoan phá vỡ tính toàn vẹn của giáp hạng nặng."},
		"serrated":      {"name": "Serrated Heads", "max": 1,  "per": "Bleed on kinetic/contact hit", "desc": "The serrated warhead causes continuous structural damage and tears through the target's microcircuit system.", "desc_vi": "Đầu đạn vi răng cưa, gây tổn thương cấu trúc liên tục và xé rách hệ thống vi mạch của mục tiêu."},
		"bleed_mastery": {"name": "Bleed Mastery",  "max": 5,  "per": "+50 max bleed stacks (global)", "desc": "Turning off the structural damage limit allows micro-tears to accumulate indefinitely on the hull of enemy ships.", "desc_vi": "Tắt bộ giới hạn sát thương cấu trúc, cho phép các vết rách vi mô tích tụ vô hạn trên vỏ tàu địch."},
		"critbreak":     {"name": "Critical Break", "max": 10, "per": "Crits strip 2% of dmg as armor", "desc": "Weak point attacks trigger localized electromagnetic pulses, temporarily weakening the target's defenses.", "desc_vi": "Các đòn tấn công điểm yếu kích hoạt xung điện từ cục bộ, làm suy giảm tạm thời khả năng phòng ngự của mục tiêu."},
	},
	"fire_rate": {
		"rate_all":     {"name": "Auto-Loader",      "max": 10, "per": "+2.5% fire rate (global)", "desc": "The highly automated electromechanical loading system shortens the reload cycle of all launchers.", "desc_vi": "Hệ thống nạp đạn cơ điện tử tự động hóa cao, rút ngắn chu kỳ nạp lại của mọi bệ phóng."},
		"rate_kinetic": {"name": "Kinetic Cadence",  "max": 10, "per": "+5% kinetic fire rate",    "desc": "Optimizing the combustion chamber and gas extraction system increases the rate of fire of kinetic energy weapons.", "desc_vi": "Tối ưu hóa buồng đốt và hệ thống trích khí, gia tăng tốc độ xả đạn của các vũ khí sử dụng động năng."},
		"rate_energy":  {"name": "Energy Cadence",   "max": 10, "per": "+5% energy fire rate",     "desc": "Upgrading the plasma chamber cooling system reduces the reload time of the energy cannons.", "desc_vi": "Nâng cấp hệ thống tản nhiệt buồng plasma, giảm thời gian nạp lại của các khẩu pháo năng lượng."},
		"rate_bio":     {"name": "Biotic Cadence",   "max": 10, "per": "+5% biochemical fire rate", "desc": "Increasing the pump pressure of the biochemical delivery system accelerates the rate of corrosive substance ejection.", "desc_vi": "Tăng áp suất bơm của hệ thống dẫn xuất sinh hóa, đẩy nhanh tốc độ phun trào các chất ăn mòn."},
		"intensity":    {"name": "Intensity Mastery", "max": 5, "per": "-5% tick cooldown (global)", "desc": "It amplifies the physicochemical reaction of sustained damaging effects, accelerating the rate of target decay.", "desc_vi": "Khuếch đại phản ứng hóa-lý của các hiệu ứng sát thương duy trì, đẩy nhanh tốc độ phân rã của mục tiêu."},
		"tradeoff":     {"name": "Heavy Rounds",     "max": 5,  "per": "-2.5% fire rate, +5% damage", "desc": "Using ultra-high-density warheads, sacrificing reloading cycles in exchange for tremendous destructive power.", "desc_vi": "Sử dụng lõi đạn mật độ siêu cao, hi sinh chu kỳ nạp để đổi lấy sức công phá khủng khiếp."},
	},
	"damage": {
		"kinetic": {"name": "Kinetic Mastery",      "max": 10, "per": "+10% kinetic damage", "desc": "Fine-tuning the magnetic field acceleration within the gun barrel maximizes the kinetic energy output of any physical projectile.", "desc_vi": "Tinh chỉnh gia tốc từ trường trong nòng súng, tối đa hóa động năng đầu ra của mọi đầu đạn vật lý."},
		"energy":  {"name": "Energy Mastery",       "max": 10, "per": "+10% energy damage",  "desc": "Enhance the plasma reactor core, amplifying the intensity of energy beams and charged particles.", "desc_vi": "Tăng cường lõi lò phản ứng plasma, khuếch đại cường độ của các chùm tia năng lượng và hạt tích điện."},
		"bio":     {"name": "Biochemical Mastery",  "max": 10, "per": "+10% bio damage",     "desc": "It alters the molecular structure of biochemical compounds, increasing their corrosive and toxic properties to the maximum level.", "desc_vi": "Biến đổi cấu trúc phân tử của các hợp chất sinh hóa, gia tăng đặc tính ăn mòn và độc tính lên mức tối đa."},
		"general": {"name": "General Weapon Mastery","max": 10, "per": "+2.5% ALL damage",   "desc": "Synchronizing the micro-targeting system enhances accuracy and overall damage output.", "desc_vi": "Đồng bộ hóa hệ thống nhắm mục tiêu vi mô, tăng cường độ chính xác và hiệu năng sát thương tổng thể."},
		"luck":    {"name": "Stroke of Luck",       "max": 5,  "per": "+1% to ALL proc chances", "desc": "The algorithm bends quantum probability, increasing the likelihood of triggering secondary lethal protocols.", "desc_vi": "Thuật toán bẻ cong xác suất lượng tử, tăng khả năng kích hoạt các giao thức sát thương thứ cấp."},
	},
	"speed": {
		"sp_ms":      {"name": "Streamlining",   "max": 10, "per": "+6% Move Speed",          "desc": "Reshaping the protective force field based on quantum aerodynamic principles, minimizing spatial drag.", "desc_vi": "Tái định hình trường lực bảo vệ theo nguyên lý khí động học lượng tử, giảm thiểu lực cản không gian."},
		"sp_dodge":   {"name": "Evasion Thrusters", "max": 5, "per": "+5% Dodge",            "desc": "It incorporates a system of variable-geometry jet engines, allowing for sudden evasive maneuvers.", "desc_vi": "Tích hợp hệ thống động cơ phản lực vi hướng, cho phép thực hiện các thao tác chuyển hướng đột ngột để né tránh."},
		"sp_shrink":  {"name": "Compact Frame",  "max": 5,  "per": "-3% ship size",           "desc": "Optimizing interior space and shrinking the physical structure of the warship reduces the cross-sectional area susceptible to projectile hits.", "desc_vi": "Tối ưu hóa không gian bên trong, thu gọn cấu trúc vật lý của chiến hạm để giảm tiết diện trúng đạn."},
		"sp_iframe":  {"name": "Reflex Booster", "max": 5,  "per": "+20% i-frame duration",   "desc": "Emergency Reflex System: Automatically overloads the force field in an instant upon taking damage, creating a brief period of physical invisibility.", "desc_vi": "Hệ thống phản xạ khẩn cấp: tự động quá tải trường lực trong chớp mắt khi nhận sát thương, tạo ra pha tàng hình vật lý ngắn."},
		"sp_ms_fire": {"name": "Overdrive",      "max": 10, "per": "+2% Move Speed, +2% Fire Rate", "desc": "Activating the full overclocking protocol pushes both the propulsion system and the weapon system beyond safe limits.", "desc_vi": "Kích hoạt giao thức ép xung toàn diện, đẩy cả động cơ đẩy và hệ thống vũ khí vượt quá thông số an toàn."},
		"sp_mastery": {"name": "Speed Mastery",  "max": 5,  "per": "+15% of MS → weapon speed", "desc": "The warship's acceleration is synchronized with the launch system, transferring kinetic energy from the hull to the launched objects.", "desc_vi": "Đồng bộ hóa gia tốc của chiến hạm với hệ thống phóng, truyền động năng từ thân tàu sang các vật thể được giải phóng."},
	},
	"force_field": {
		"ff_max":     {"name": "Capacitor Bank",  "max": 10, "per": "+15 Max Shield",          "desc": "The addition of next-generation superconducting capacitors expands the energy storage capacity of the protective shield.", "desc_vi": "Bổ sung các tụ điện siêu dẫn thế hệ mới, mở rộng dung lượng lưu trữ năng lượng cho màng chắn bảo vệ."},
		"ff_regen":   {"name": "Recharge Coils",  "max": 10, "per": "+0.5 shield/s regen",     "desc": "Upgrading the induction coil increases the speed of energy conversion from the reactor into a protective force field.", "desc_vi": "Nâng cấp cuộn dây cảm ứng từ, tăng tốc độ chuyển hóa năng lượng từ lò phản ứng thành trường lực bảo vệ."},
		"ff_delay":   {"name": "Fast Boot",       "max": 10, "per": "-0.5s regen delay",       "desc": "Reduce the restart time of the diaphragm generator after being subjected to shock from attacks.", "desc_vi": "Rút ngắn thời gian tái khởi động của máy phát màng chắn sau khi chịu xung kích từ các đòn tấn công."},
		"ff_mastery": {"name": "Shield Mastery",  "max": 10, "per": "+5% total shield",        "desc": "The algorithm optimizes the topology of the force field, increasing the density of energy particles across the entire surface.", "desc_vi": "Thuật toán tối ưu hóa cấu trúc liên kết của trường lực, gia tăng mật độ hạt năng lượng trên toàn bề mặt."},
		"ff_quick":   {"name": "Quick Shield",    "max": 5,  "per": "-15 Max Shield, ++regen & boot", "desc": "Restructuring the diaphragm: reducing thickness to maximize regeneration rate and instantaneous responsiveness.", "desc_vi": "Tái cấu trúc màng chắn: giảm độ dày để tối đa hóa tốc độ tái tạo và khả năng phản hồi tức thời."},
		"ff_panic":   {"name": "Panic Button",    "max": 10, "per": "+0.5s i-frames on break", "desc": "Emergency survival protocol: releasing all reserve energy to create an absolutely safe space when the barrier collapses.", "desc_vi": "Giao thức sinh tồn khẩn cấp: giải phóng toàn bộ năng lượng dự phòng tạo ra vùng không gian an toàn tuyệt đối khi màng chắn sụp đổ."},
	},
	"crit": {
		"cc_chance": {"name": "Steady Aim",      "max": 10, "per": "+5% crit chance",   "desc": "The system uses quantum gyroscope-based stabilization to target structural weaknesses, increasing the probability of hitting them.", "desc_vi": "Hệ thống nhắm mục tiêu ổn định bằng con quay hồi chuyển lượng tử, tăng xác suất đánh trúng các điểm yếu cấu trúc."},
		"cc_dmg":    {"name": "Killing Blow",    "max": 10, "per": "+10% crit damage",  "desc": "Optimize the angle of attack, maximizing destructive power when striking joints or energy cores.", "desc_vi": "Tối ưu hóa góc tới của các đòn tấn công, tối đa hóa sức công phá khi đánh trúng các khớp nối hoặc lõi năng lượng."},
		"cc_bleed":  {"name": "Critical Bleed",  "max": 10, "per": "+2 bleed on crit",  "desc": "Attacks targeting vulnerable points trigger tearing micro-bullets, causing severe and continuous structural damage.", "desc_vi": "Các đòn tấn công điểm yếu kích hoạt vi đạn xé rách, gây tổn thương cấu trúc nghiêm trọng và liên tục."},
		"cc_burn":   {"name": "Ignition Rounds", "max": 5,  "per": "burn on crit",      "desc": "The warhead contains an unstable plasma compound that ignites intensely upon penetrating the target's armor.", "desc_vi": "Đầu đạn chứa hợp chất plasma bất ổn, bốc cháy mãnh liệt khi xuyên thủng vỏ giáp mục tiêu."},
		"cc_freeze": {"name": "Cryo Rounds",     "max": 5,  "per": "freeze on crit",    "desc": "Integrating an absolute cooling core, it instantly freezes microcircuits and drive systems at the point of impact.", "desc_vi": "Tích hợp lõi làm lạnh tuyệt đối, đóng băng tức thời các vi mạch và hệ thống truyền động tại điểm va chạm."},
		"cc_shock":  {"name": "Shock Rounds",    "max": 5,  "per": "stun on crit",      "desc": "It releases extremely powerful electromagnetic pulses upon impact with weak points, causing short circuits and paralyzing the enemy's control systems.", "desc_vi": "Giải phóng xung điện từ cực mạnh khi va chạm điểm yếu, làm đoản mạch và tê liệt hệ thống điều khiển của địch."},
	},
	"aoe": {
		"ao_wider":   {"name": "Wider Blast",         "max": 10, "per": "+5% AoE",                     "desc": "Using spatially dispersed explosives expands the radius of effect of all types of wide-area weapons.", "desc_vi": "Sử dụng chất nổ khuếch tán không gian, mở rộng bán kính ảnh hưởng của mọi loại vũ khí diện rộng."},
		"ao_cadence": {"name": "Concussive Cadence",  "max": 5,  "per": "-3% AoE, +5% DoT tick speed", "desc": "Concentrating explosive energy to increase the destructive oscillation frequency, this method trades surface area for structural erosion speed.", "desc_vi": "Cô đặc năng lượng nổ để tăng tần số dao động hủy diệt, đánh đổi diện tích lấy tốc độ ăn mòn cấu trúc."},
		"ao_frag":    {"name": "Frag Rounds",         "max": 10, "per": "+2.5% AoE, +3% fire rate",    "desc": "The intelligent fragmentation warhead creates secondary explosions while simultaneously reducing the pressure on the launch system.", "desc_vi": "Đầu đạn phân mảnh thông minh, tạo ra các vụ nổ thứ cấp đồng thời giảm tải áp lực cho hệ thống phóng."},
		"ao_bombard": {"name": "Bombardment Mastery", "max": 5,  "per": "+5% AoE-weapon damage",       "desc": "Refine the spatial damage distribution algorithm to maximize the shock wave output of heavy weapon systems.", "desc_vi": "Tinh chỉnh thuật toán phân bổ sát thương không gian, tối đa hóa sóng xung kích của các hệ thống vũ khí hạng nặng."},
	},
	"pickup": {
		"pk_range":  {"name": "Wider Reach",       "max": 10, "per": "+10% pickup range",             "desc": "Amplify the warship's local gravitational field, collecting matter and resources from greater distances.", "desc_vi": "Khuếch đại trường hấp dẫn cục bộ của chiến hạm, thu thập vật chất và tài nguyên từ khoảng cách xa hơn."},
		"pk_pulse":  {"name": "Singularity Pulse", "max": 5,  "per": "-1 min pulse cooldown",         "desc": "Creating a temporary micro-singularity, bending spacetime to pull all free objects toward the ship's hull.", "desc_vi": "Tạo ra một điểm kỳ dị vi mô tạm thời, uốn cong không-thời gian để kéo mọi vật thể tự do về phía thân tàu."},
		"pk_heal":   {"name": "Recovery Field",    "max": 5,  "per": "+0.1 HP/s for 5s on pickup",    "desc": "Waste resource converter: separates collected materials to synthesize hull patching membranes.", "desc_vi": "Bộ chuyển hóa tài nguyên rác: phân tách vật liệu thu thập được để tổng hợp thành màng vá thân tàu."},
		"pk_dmg":    {"name": "Power Surge",       "max": 5,  "per": "+1% damage for 5s on pickup",   "desc": "The kinetic energy of the collected objects is converted into additional energy for the weapon system.", "desc_vi": "Chuyển hóa động năng của các vật thể được thu thập thành năng lượng bổ sung cho hệ thống vũ khí."},
		"pk_rev":    {"name": "Reverse Polarity",  "max": 5,  "per": "-5% enemy speed in range",      "desc": "Reversing the polarity of the collecting gravitational field creates a drag force in space that slows the movement of hostile entities.", "desc_vi": "Đảo ngược cực tính của trường hấp dẫn thu thập, tạo ra lực cản không gian làm chậm chuyển động của các thực thể thù địch."},
		"pk_shield": {"name": "Shield Recovery",   "max": 5,  "per": "+0.1 shield/s for 5s on pickup","desc": "Reusing electrostatic energy from collected debris to reinforce the protective barrier.", "desc_vi": "Tái sử dụng năng lượng tĩnh điện từ các mảnh vỡ thu thập được để gia cố màng chắn bảo vệ cục bộ."},
	},
	"xp": {
		"xp_gain":   {"name": "Deep Learning",   "max": 10, "per": "+2% EXP",                    "desc": "Upgrading the core AI module accelerates the analysis of combat data and optimizes combat algorithms.", "desc_vi": "Nâng cấp mô-đun AI lõi, đẩy nhanh quá trình phân tích dữ liệu chiến đấu và tối ưu hóa các thuật toán tác chiến."},
		"xp_req":    {"name": "Efficient Study", "max": 10, "per": "-2% EXP to level",           "desc": "Optimizing the neural network architecture of the central computer reduces the amount of raw data required to achieve a leap in performance.", "desc_vi": "Tối ưu hóa kiến trúc mạng nơ-ron của máy tính trung tâm, giảm lượng dữ liệu thô cần thiết để đạt bước nhảy vọt về hiệu năng."},
		"xp_double": {"name": "Data Mining",     "max": 10, "per": "+2% double-orb chance",      "desc": "Enabling deep data mining protocols increases the probability of extracting high-value tactical information cores.", "desc_vi": "Kích hoạt giao thức khai phá dữ liệu sâu, tăng xác suất trích xuất được các lõi thông tin chiến thuật giá trị cao."},
		"xp_heal":   {"name": "Eureka",          "max": 5,  "per": "heal 20% on level up",       "desc": "Each core software update triggers an emergency restructuring process, significantly restoring the hull's integrity.", "desc_vi": "Mỗi lần cập nhật phần mềm lõi sẽ kích hoạt quy trình tái cấu trúc khẩn cấp, khôi phục đáng kể tính toàn vẹn của vỏ tàu."},
		"xp_blast":  {"name": "Knowledge Bomb",  "max": 10, "per": "50 kinetic AoE on level up", "desc": "The excess thermal energy from the AI upgrade process is released as a physical shockwave that sweeps around.", "desc_vi": "Xả năng lượng nhiệt dư thừa từ quá trình nâng cấp AI thành một làn sóng xung kích vật lý càn quét xung quanh."},
	},
	"spawn": {
		"sp_rate":  {"name": "Broadcast",       "max": 0, "per": "+15% enemy spawns",     "desc": "Broadcasting broadband quantum signals attracts the attention of hostile entities in the surrounding space.", "desc_vi": "Phát sóng tín hiệu lượng tử dải rộng, thu hút sự chú ý của các thực thể thù địch trong khu vực không gian lân cận."},
		"sp_hp":    {"name": "Reinforced Foes", "max": 0, "per": "+10% enemy HP",         "desc": "The radiation from the emitted signal inadvertently reinforces the molecular structure of hostile targets.", "desc_vi": "Bức xạ từ tín hiệu phát ra vô tình cường hóa cấu trúc phân tử của các mục tiêu thù địch."},
		"sp_dmg":   {"name": "Armed Foes",      "max": 0, "per": "+10% enemy damage",     "desc": "Spatial turbulence provides additional energy to the weapon systems of the invading entities.", "desc_vi": "Sự nhiễu loạn không gian cung cấp thêm năng lượng cho hệ thống vũ khí của các thực thể xâm nhập."},
		"sp_speed": {"name": "Frenzy",          "max": 0, "per": "+5% enemy speed",       "desc": "The broadcast frequency stimulates the enemy's guidance system, increasing their acceleration as they approach.", "desc_vi": "Tần số phát sóng kích thích hệ thống dẫn đường của kẻ địch, gia tăng gia tốc tiếp cận của chúng."},
		"sp_boss":  {"name": "Rival Beacon",    "max": 0, "per": "+1 boss per boss fight", "desc": "Sending a high-level challenge signal to attract the attention of fleet commanders or alpha-level entities.", "desc_vi": "Phát tín hiệu thách thức mức độ cao, thu hút sự chú ý của các chỉ huy hạm đội hoặc thực thể cấp độ alpha.", "gate_first": 6, "gate_step": 5},
	},
	"retaliation": {
		"bw_armor":     {"name": "Plating",          "max": 10, "per": "+2 Armor",              "desc": "Adding rudimentary armor plates on the outside creates a layer of physical protection against basic impacts.", "desc_vi": "Gắn thêm các tấm giáp thô sơ bên ngoài, tạo lớp bảo vệ vật lý chống lại các va chạm cơ bản."},
		"bw_contact":   {"name": "Spiked Hull",      "max": 10, "per": "+5 contact damage",      "desc": "Reinforcing the bow with sharp, polygonal structures transforms the hull into a penetrating weapon.", "desc_vi": "Gia cố mũi tàu bằng cấu trúc đa giác sắc nhọn, biến thân tàu thành một vũ khí đâm xuyên."},
		"bw_bleed":     {"name": "Barbs",            "max": 5,  "per": "+2 bleed on contact",    "desc": "The ship's surface is coated with nano-cutting blades, tearing through the protective layer of any entity that dares to make physical contact.", "desc_vi": "Bề mặt tàu được phủ các lưỡi cắt nano, xé rách lớp bảo vệ của bất kỳ thực thể nào dám tiếp xúc vật lý."},
		"bw_dr":        {"name": "Riot Shielding",   "max": 5,  "per": "+2% damage reduction",   "desc": "Install a system of localized kinetic energy shields to disperse the impact force from direct attacks.", "desc_vi": "Lắp đặt hệ thống màng cản động năng cục bộ, phân tán lực tác động từ các đòn tấn công trực diện."},
		"bw_reflect":   {"name": "Retaliation",      "max": 10, "per": "reflect 100% of damage taken", "desc": "Integrated explosive reactive armor: automatically detonates micro-modules upon taking damage, creating a shockwave that pushes enemies back.", "desc_vi": "Tích hợp giáp phản ứng nổ: tự động kích nổ các module vi mô khi nhận sát thương, tạo sóng xung kích đẩy lùi kẻ thù."},
		"bw_proximity": {"name": "Proximity Mastery","max": 5,  "per": "+10% close-range damage (global)", "desc": "Optimizing the beam focusing system and proximity fuse maximizes destructive power at close range.", "desc_vi": "Tối ưu hóa hệ thống hội tụ tia và ngòi nổ tiệm cận, tối đa hóa sức hủy diệt ở cự ly gần."},
	},
	"coin": {
		"co_mult":   {"name": "Extraction",   "max": 5,  "per": "+5% coin value",                       "desc": "The algorithm for mining energy crystals has been upgraded, allowing for more efficient extraction of value from destroyed fragments.", "desc_vi": "Nâng cấp thuật toán khai thác tinh thể năng lượng, chiết xuất hiệu quả hơn giá trị từ các mảnh vỡ bị tiêu diệt."},
		"co_magic":  {"name": "Magic Find",   "max": 10, "per": "+5% coin drop (×), +5% enemy HP",      "desc": "Activating the high-risk analysis protocol enhances resource gathering but inadvertently triggers the target's defenses.", "desc_vi": "Kích hoạt giao thức phân tích rủi ro cao: tăng cường thu thập tài nguyên nhưng vô tình kích thích hệ thống phòng ngự của mục tiêu."},
		"co_skew":   {"name": "Higher Yield", "max": 10, "per": "richer coins",                         "desc": "Fine-tuning the optical spectrum sensor prioritizes the identification and acquisition of high-purity energy cores.", "desc_vi": "Tinh chỉnh cảm biến phổ quang, ưu tiên xác định và thu thập các lõi năng lượng có độ tinh khiết cao."},
		"co_heal":   {"name": "Blood Money",  "max": 5,  "per": "+0.1 HP/s for 5s on coin",             "desc": "A portion of the energy from the collected crystals is converted to power the self-repairing system.", "desc_vi": "Chuyển hóa một phần năng lượng từ các tinh thể thu thập được để cung cấp năng lượng cho hệ thống tự sửa chữa."},
		"co_shield": {"name": "Insurance",    "max": 5,  "per": "+0.1 shield/s for 5s on coin",         "desc": "Reroute the current from newly collected resources to reinforce the local protective barrier.", "desc_vi": "Tái định tuyến dòng điện từ các tài nguyên mới thu thập để gia cố màng chắn bảo vệ cục bộ."},
		"co_haste":  {"name": "Adrenaline",   "max": 5,  "per": "+5% speed & fire rate for 5s on coin", "desc": "Temporarily overclock the drive and ammunition loading systems using raw energy extracted from the recently collected crystals.", "desc_vi": "Ép xung tạm thời hệ thống truyền động và nạp đạn bằng năng lượng thô trích xuất từ các tinh thể vừa thu thập."},
	},
}

# Evolution (level-6) options per aux id → [ {id, name, desc} ].
const AUX_CAPSTONES := {
	"hp": [
		{"id": "juggernaut", "name": "Juggernaut",         "desc": "For every 50 Max HP you have, gain 1 Armor."},
		{"id": "calm",       "name": "Calm Under Pressure", "desc": "+5% fire rate and +5% damage for each 5% of missing HP."},
		{"id": "reckless",   "name": "Reckless Abandon",    "desc": "Set HP to 50; +1% damage for every 10 HP lost this way."},
	],
	"regen": [
		{"id": "attack",        "name": "Nanobots, Attack!", "desc": "Set HP regen to 0; +1% automation-weapon damage per 0.1 regen lost this way."},
		{"id": "will_to_live",  "name": "Will to Live",      "desc": "+200% HP regen while below 30% Max HP."},
		{"id": "bodies",        "name": "BFFs!",             "desc": "Weapons that have bodies gain +2 segments."},
	],
	"armor": [
		{"id": "fortress", "name": "Fortress",        "desc": "-30% move speed, but +1% DR per 10 armor (total DR capped at 75%)."},
		{"id": "bastion",  "name": "Bastion",         "desc": "Gain Max HP and Max Shield each equal to half your armor."},
		{"id": "reactive", "name": "Reactive Plating", "desc": "Every 500 damage you mitigate, erupt a 400px shockwave for 100 kinetic damage."},
	],
	"armor_pen": [
		{"id": "less_than_nothing", "name": "Less Than Nothing", "desc": "Enemy armor can be driven down to -20 (negative armor amplifies your damage)."},
		{"id": "fortification",     "name": "Fortification Knowledge", "desc": "+20% armor penetration, and gain +20% of your own armor."},
		{"id": "hurt",              "name": "Hurt", "desc": "Your bleeds are improved by your armor penetration."},
	],
	"fire_rate": [
		{"id": "charged_up",     "name": "Charged Up",     "desc": "Weapons WITH a cooldown gain +20% damage for every 0.5s of that cooldown."},
		{"id": "absolute_focus", "name": "Absolute Focus", "desc": "+1% fire rate every 5s without taking damage (up to +60%, reset on hit)."},
		{"id": "speed_is_force", "name": "Speed is Force",  "desc": "100% of your fire-rate bonus is also added as damage to contact weapons."},
	],
	"damage": [
		{"id": "kinetic_truth", "name": "Kinetic Truth", "desc": "Disable all non-kinetic weapons. Kinetic weapons gain +50% damage for each weapon disabled this way."},
		{"id": "energy_truth",  "name": "Energy Truth",  "desc": "Disable all non-energy weapons. Energy weapons gain +50% damage for each weapon disabled this way."},
		{"id": "bio_truth",     "name": "Biochemical Truth", "desc": "Disable all non-biochemical weapons. Biochemical weapons gain +50% damage for each weapon disabled this way."},
	],
	"speed": [
		{"id": "glass",     "name": "Glass Cannon",  "desc": "Lose 25% Max HP and 25% ship size; gain +25% Dodge."},
		{"id": "daredevil", "name": "Daredevil",     "desc": "Take +20% damage, but gain +1% damage every 3s without being hit (up to +100%, reset on hit)."},
		{"id": "momentum",  "name": "Momentum",      "desc": "100% of your move-speed bonus is also added to global fire rate."},
	],
	"force_field": [
		{"id": "void_shield", "name": "Void Shield",         "desc": "Your hull deals contact damage each tick equal to 10% of your current shield."},
		{"id": "impervious",  "name": "Impervious",          "desc": "While your shield is up, take 20% less damage."},
		{"id": "energy_guns", "name": "Energy to the Guns!", "desc": "Disable your shield entirely — but energy weapons gain +50% fire rate."},
	],
	"crit": [
		{"id": "deadly",    "name": "Deadly",             "desc": "+100% crit chance; any crit chance over 100% is converted into crit damage."},
		{"id": "challenge", "name": "Challenge Accepted", "desc": "-20% crit chance, but each critical grants a Fervor stack: +5% damage for 5s (max 5)."},
	],
	"aoe": [
		{"id": "saturation",     "name": "Saturation",     "desc": "-50% AoE, but damage-over-time ticks twice as fast (+100% intensity)."},
		{"id": "chain_reaction", "name": "Chain Reaction", "desc": "A slain enemy has a 25% chance to explode for 50 kinetic damage in a small area."},
		{"id": "overpressure",   "name": "Overpressure",   "desc": "+30% AoE."},
	],
	"pickup": [
		{"id": "wide_net", "name": "Wide Net",           "desc": "+30% pickup range."},
		{"id": "refuel",   "name": "Next Gen Refueling", "desc": "Collecting anything grants +1 HP regen, +1 shield regen, and +10% damage for 5s."},
		{"id": "treasure", "name": "Treasure",           "desc": "-70% pickup range, but +30% EXP gain."},
	],
	"xp": [
		{"id": "applied_learning", "name": "Applied Learning", "desc": "Gain +0.2% damage per player level."},
		{"id": "unlearn",          "name": "Unlearn",          "desc": "Disable this item and drop your level by 15 (you keep every upgrade) — re-level for the rewards."},
		{"id": "xp_boost",         "name": "Overclocked Mind", "desc": "+25% EXP."},
	],
	"retaliation": [
		{"id": "blood_thirsty", "name": "Blood Thirsty",     "desc": "Heal for 5% of the contact damage you deal."},
		{"id": "contact_boost", "name": "Overdriven Spikes", "desc": "+30% contact damage."},
		{"id": "fortify",       "name": "Fortify",           "desc": "+5 flat damage reduction for each contact-damage weapon you own."},
	],
	"coin": [
		{"id": "greedisgood",   "name": "Greedisgood",   "desc": "+50% coin value."},
		{"id": "whosyourdaddy", "name": "Whosyourdaddy", "desc": "Enemies drop far more coins — but gain +50% HP and +50% damage."},
	],
}

var _owned: Dictionary = {}   # id → level (1..MAX_AUX_LEVEL)
var _points: Dictionary = {}  # id → skill points invested toward the NEXT level (skill-point progression)
var _order: Array = []        # acquisition order (stable slot order for the HUD)
var _by_id: Dictionary = {}   # id → def dict (built in _ready)
var _pool: Dictionary = {}    # pooled aux id → {pool_id → rank invested}
var _capstone: Dictionary = {}# pooled aux id → chosen evolution id ("" / absent = none)

# Reinforcement-plate (hp) HP recompute: flat HP grants are scaled by Reinforcement Mastery and Overall adds a
# % of base ship HP. We keep the contribution here and push DELTAS into GameManager so Mastery is retroactive.
var _rp_flat: float = 0.0     # sum of flat HP grants (pre-multiplier)
var _rp_mastery: float = 0.0  # Reinforcement Mastery (+x applied to flat HP gains)
var _rp_overall: float = 0.0  # Overall Improvement HP fraction (× base ship HP)
var _rp_applied: int = 0      # HP already pushed to GameManager (for delta application)
# Dynamic trackers (delta-applied via a signal-driven recompute — only when the source value changes).
var _jug_armor: int = 0        # Juggernaut: armor currently granted from MAX-HP scaling
var _calm_bonus: float = 0.0   # Calm Under Pressure: dmg/fire-rate fraction currently granted
var _ov_armor: int = 0         # Overall Improvement: armor granted (= ceil(other armor × Overall%))
var _bastion_hp: int = 0       # Bastion evo: Max HP currently granted (= half armor)
var _bastion_shield: float = 0.0 # Bastion evo: Max Shield currently granted (= half armor)
var _recomputing: bool = false # reentrancy guard (our add_* calls re-emit the signals we listen to)

func _ready() -> void:
	add_to_group("arena_aux")
	for d: Dictionary in AUX_DEFS:
		_by_id[String(d["id"])] = d
	# Dynamic evolutions recompute only when their source value changes (max HP / armor → player_stats_changed,
	# current HP → ship_hp_changed) — never per-frame.
	if GameManager.has_signal("player_stats_changed"):
		GameManager.player_stats_changed.connect(_recompute_dynamic)
	if GameManager.has_signal("ship_hp_changed"):
		GameManager.ship_hp_changed.connect(func(_hp: int) -> void: _recompute_dynamic())
	if GameManager.has_signal("rebirth_used"):
		GameManager.rebirth_used.connect(_on_rebirth_used)

## Backup Image is consumed when a revive charge is spent — destroy the item.
func _on_rebirth_used() -> void:
	if "revival" in _owned:
		_owned.erase("revival")
		_order.erase("revival")

# ── Acquisition / leveling ────────────────────────────────────────────────────────
## Acquire a NEW aux item (level 1) and apply its effect once. No-op if already owned or slots are full.
func acquire_aux(id: String) -> bool:
	if id in _owned or not _by_id.has(id):
		return false
	if aux_slots_full():
		return false
	_owned[id] = 1
	_order.append(id)
	if not _is_pooled(id):
		_apply_effect(id)   # simple aux: its per-level stat IS the item. Pooled aux: the perk picker is the reward.
	elif id == "force_field":
		_apply_effect(id)   # Force Field grants its base shield on acquire so it works immediately (the pool adds MORE)
	elif id == "coin":
		GameManager.upg_coin_drop = 1.0   # Credit Extractor: enemies begin dropping coins the moment it's picked up
	return true

## Raise an owned aux item's level by one (capped). Pooled items gain NO milestone reward — the level just
## counts toward EVOLVE; simple aux re-apply their per-level effect.
func level_up_aux(id: String) -> void:
	if not (id in _owned):
		return
	if int(_owned[id]) >= MAX_AUX_LEVEL:
		return
	_owned[id] = int(_owned[id]) + 1
	if not _is_pooled(id):
		_apply_effect(id)

# ── Queries (level-up UI + slot HUD) ───────────────────────────────────────────────
func aux_level(id: String) -> int:
	return int(_owned.get(id, 0))

func aux_can_upgrade(id: String) -> bool:
	if id == "revival":
		return false   # Backup Image is a one-shot — it never ranks up
	return id in _owned and int(_owned[id]) < MAX_AUX_LEVEL

# ── Skill-point progression: 1 point = 1 level (acquire at 0→1), max MAX_AUX_LEVEL, then EVOLVE ──
func aux_points(id: String) -> int:
	return int(_points.get(id, 0))

func aux_next_cost(id: String) -> int:
	return 0 if aux_level(id) >= MAX_AUX_LEVEL else 1   # 1 point = 1 level now

## Invest ONE skill point: ALWAYS +1 level (acquire at 0→1). Returns true if a level was gained.
func spend_aux_point(id: String) -> bool:
	if not _by_id.has(id):
		return false
	var lvl := aux_level(id)
	if lvl >= MAX_AUX_LEVEL:
		return false
	if lvl <= 0:
		acquire_aux(id)      # 0→1
	else:
		level_up_aux(id)     # L→L+1
	return true

func aux_slots_full() -> bool:
	return _owned.size() >= MAX_AUX

## Ordered owned ids (acquisition order) — read by the slot HUD.
func owned_aux() -> Array:
	return _order.duplicate()

func def_for(id: String) -> Dictionary:
	return _by_id.get(id, {})

# ── Effect dispatch ────────────────────────────────────────────────────────────────
## Apply ONE level's worth of `id`'s effect to GameManager. Called once per acquire + once per level-up,
## so the run-stat store accumulates naturally across levels.
func _apply_effect(id: String) -> void:
	match id:
		"hp":          GameManager.add_max_hp(20)
		"regen":       GameManager.add_hp_regen(0.5)
		"armor":       GameManager.add_base_defense(2)
		"force_field": GameManager.add_force_shield(20.0, 1.0)
		"speed":       GameManager.add_move_speed(0.06)
		"damage":      GameManager.add_damage(0.10)
		"fire_rate":   GameManager.add_fire_rate(0.08)
		"armor_pen":   GameManager.add_mech("armor_pen", 2)   # ignore 2 enemy armour (enemy armour TBD)
		"crit":        GameManager.add_crit_chance(0.05)
		"harmonizer":  pass   # STUB: needs the weapon-type (kinetic/biochemical/energy) damage system — not built yet
		"aoe":         GameManager.add_mech("radius", 25)
		"pickup":      GameManager.add_pickup_radius(0.15)
		"xp":          GameManager.add_xp_gain(0.10)
		"spawn":       GameManager.add_spawn_rate(0.15)
		"retaliation": GameManager.add_retaliation(5.0)
		"revival":     GameManager.add_rebirth(1)
		"coin":        GameManager.add_coin_mult(0.25)

# ── Aux skill-point POOL + EVOLUTION (parallels arena_weapons' pool_*/weapon_capstone API) ──────────────────
func _is_pooled(id: String) -> bool:
	return AUX_POOL.has(id)

func aux_pool(id: String) -> Dictionary:
	return (AUX_POOL as Dictionary).get(id, {})

func aux_has_pool(id: String) -> bool:
	return AUX_POOL.has(id)

func aux_pool_rank(id: String, pool_id: String) -> int:
	var ranks: Dictionary = _pool.get(id, {})
	return int(ranks.get(pool_id, 0))

## Grant ONE rank of a pool perk (applies its effect once). No-op if unknown or maxed.
func aux_pool_grant(id: String, pool_id: String) -> bool:
	var pool: Dictionary = aux_pool(id)
	if not pool.has(pool_id):
		return false
	var maxr := int(pool[pool_id]["max"])
	var ranks: Dictionary = _pool.get(id, {})
	var cur := int(ranks.get(pool_id, 0))
	if maxr > 0 and cur >= maxr:
		return false
	# Level-gated perk (Beacon "Rival Beacon"): rank r needs aux level ≥ gate_first + gate_step×r.
	if pool[pool_id].has("gate_first"):
		if aux_level(id) < int(pool[pool_id]["gate_first"]) + int(pool[pool_id].get("gate_step", 5)) * cur:
			return false
	ranks[pool_id] = cur + 1
	_pool[id] = ranks
	_apply_pool_effect(id, pool_id)
	return true

func aux_capstones(id: String) -> Array:
	return (AUX_CAPSTONES as Dictionary).get(id, [])

func aux_capstone(id: String) -> String:
	return String(_capstone.get(id, ""))

func aux_set_capstone(id: String, cap_id: String) -> void:
	_capstone[id] = cap_id
	if id == "hp":
		if cap_id == "reckless":
			_apply_reckless()
		elif cap_id == "juggernaut":
			GameManager.mul_ship_size(2.0)   # Juggernaut nerf: the ship (visual + hitbox) is twice as big
	elif id == "regen":
		_apply_regen_capstone(cap_id)
	elif id == "armor":
		_apply_armor_capstone(cap_id)
	elif id == "speed":
		_apply_speed_capstone(cap_id)
	elif id == "damage":
		_apply_damage_capstone(cap_id)
	elif id == "fire_rate":
		_apply_firerate_capstone(cap_id)
	elif id == "armor_pen":
		_apply_armorpen_capstone(cap_id)
	elif id == "force_field":
		_apply_forcefield_capstone(cap_id)
	elif id == "crit":
		_apply_crit_capstone(cap_id)
	elif id == "aoe":
		_apply_aoe_capstone(cap_id)
	elif id == "pickup":
		_apply_pickup_capstone(cap_id)
	elif id == "xp":
		_apply_xp_capstone(cap_id)
	elif id == "retaliation":
		_apply_retaliation_capstone(cap_id)
	elif id == "coin":
		_apply_coin_capstone(cap_id)
	_recompute_dynamic()   # Juggernaut/Calm/Will-to-Live/Bastion start applying immediately on the pick

## True when a pooled aux just earned its evolve pick: at max level, has capstones, none chosen yet.
func aux_needs_capstone(id: String) -> bool:
	return aux_level(id) >= MAX_AUX_LEVEL and not aux_capstones(id).is_empty() and aux_capstone(id) == ""

# ── Pool / level / capstone effects ─────────────────────────────────────────────────────────────────────────
## One rank of a pool perk → GameManager run stats.
func _apply_pool_effect(id: String, pool_id: String) -> void:
	if id == "hp":
		_apply_hp_pool_effect(pool_id)
	elif id == "regen":
		_apply_regen_pool_effect(pool_id)
	elif id == "armor":
		_apply_armor_pool_effect(pool_id)
	elif id == "speed":
		_apply_speed_pool_effect(pool_id)
	elif id == "damage":
		_apply_damage_pool_effect(pool_id)
	elif id == "fire_rate":
		_apply_firerate_pool_effect(pool_id)
	elif id == "armor_pen":
		_apply_armorpen_pool_effect(pool_id)
	elif id == "force_field":
		_apply_forcefield_pool_effect(pool_id)
	elif id == "crit":
		_apply_crit_pool_effect(pool_id)
	elif id == "aoe":
		_apply_aoe_pool_effect(pool_id)
	elif id == "pickup":
		_apply_pickup_pool_effect(pool_id)
	elif id == "xp":
		_apply_xp_pool_effect(pool_id)
	elif id == "spawn":
		_apply_spawn_pool_effect(pool_id)
	elif id == "retaliation":
		_apply_retaliation_pool_effect(pool_id)
	elif id == "coin":
		_apply_coin_pool_effect(pool_id)

## One rank of a Credit Extractor perk → coin value / drop / on-coin buffs.
func _apply_coin_pool_effect(pool_id: String) -> void:
	match pool_id:
		"co_mult":   GameManager.add_coin_mult(0.05)
		"co_magic":
			GameManager.upg_coin_drop = maxf(1.0, GameManager.upg_coin_drop) * 1.05   # multiplicative magic find
			GameManager.add_mech("enemy_hp_mult", 0.05)
		"co_skew":   GameManager.add_mech("coin_skew", 0.1)
		"co_heal":   GameManager.upg_coin_heal += 0.1
		"co_shield": GameManager.upg_coin_shield += 0.1
		"co_haste":  GameManager.upg_coin_haste += 0.05

func _apply_coin_capstone(cap_id: String) -> void:
	match cap_id:
		"greedisgood": GameManager.add_coin_mult(0.50)
		"whosyourdaddy":
			GameManager.upg_coin_drop = maxf(1.0, GameManager.upg_coin_drop) * 3.0
			GameManager.add_mech("enemy_hp_mult", 0.50)
			GameManager.add_mech("enemy_dmg_mult", 0.50)

## One rank of a Barbed Wire perk → armor / contact / reflect / proximity.
func _apply_retaliation_pool_effect(pool_id: String) -> void:
	match pool_id:
		"bw_armor":      GameManager.add_base_defense(2)
		"bw_contact":    GameManager.add_contact_damage(5.0)
		"bw_bleed":      GameManager.add_mech("contact_bleed", 2)
		"bw_dr":         GameManager.add_pre_dr(0.02)
		"bw_reflect":    GameManager.add_mech("reflect_taken", 1.0)
		"bw_proximity":  GameManager.add_mech("proximity_dmg", 0.10)

func _apply_retaliation_capstone(cap_id: String) -> void:
	match cap_id:
		"blood_thirsty": GameManager.upg_blood_thirsty = true
		"contact_boost": GameManager.add_mech("contact_dmg_mult", 0.30)
		"fortify":
			var n := 1   # +1 for the ship's own contact
			var aw = get_tree().get_first_node_in_group("arena_weapons")
			if aw != null and aw.has_method("contact_source_count"):
				n += int(aw.call("contact_source_count"))
			GameManager.add_base_defense(5 * n)   # snapshot at pick time

## One rank of a Beacon perk → risk/reward enemy buffs (unlimited ranks; no evolution).
func _apply_spawn_pool_effect(pool_id: String) -> void:
	match pool_id:
		"sp_rate":  GameManager.add_spawn_rate(0.15)
		"sp_hp":    GameManager.add_mech("enemy_hp_mult", 0.10)
		"sp_dmg":   GameManager.add_mech("enemy_dmg_mult", 0.10)
		"sp_speed": GameManager.add_mech("enemy_speed_mult", 0.05)
		"sp_boss":  GameManager.add_mech("extra_bosses", 1)

## One rank of a Data Harvester perk → GameManager XP stats / level-up procs.
func _apply_xp_pool_effect(pool_id: String) -> void:
	match pool_id:
		"xp_gain":   GameManager.add_xp_gain(0.02)
		"xp_req":    GameManager.upg_xp_req_reduction += 0.02
		"xp_double": GameManager.add_mech("double_xp_chance", 0.02)
		"xp_heal":   GameManager.add_mech("levelup_heal", 0.20)
		"xp_blast":  GameManager.add_mech("levelup_dmg", 50.0)

func _apply_xp_capstone(cap_id: String) -> void:
	match cap_id:
		"applied_learning": GameManager.upg_applied_learning = true
		"unlearn":
			GameManager.upg_harvester_off = true
			GameManager.player_level = maxi(1, GameManager.player_level - 15)
			if GameManager.has_signal("level_changed"):
				GameManager.level_changed.emit(GameManager.player_level)
		"xp_boost": GameManager.add_xp_gain(0.25)

## One rank of a Magnet perk → GameManager pickup stats / on-pickup buffs.
func _apply_pickup_pool_effect(pool_id: String) -> void:
	match pool_id:
		"pk_range":  GameManager.add_pickup_radius(0.10)
		"pk_pulse":
			GameManager.upg_magnet_pulse_rank += 1
			GameManager._magnet_pulse_cd = float(10 - GameManager.upg_magnet_pulse_rank) * 60.0   # wait the full cd first
		"pk_heal":   GameManager.upg_pickup_heal += 0.1
		"pk_dmg":    GameManager.upg_pickup_dmg += 0.01
		"pk_rev":    GameManager.add_mech("reverse_polarity", 0.05)
		"pk_shield": GameManager.upg_pickup_shield += 0.1

func _apply_pickup_capstone(cap_id: String) -> void:
	match cap_id:
		"wide_net":  GameManager.add_pickup_radius(0.30)
		"refuel":    GameManager.upg_refuel = true
		"treasure":
			GameManager.add_pickup_radius(-0.70)
			GameManager.add_xp_gain(0.30)

## One rank of an Explosivo perk → GameManager AoE / DoT-tick / bombardment mechs.
func _apply_aoe_pool_effect(pool_id: String) -> void:
	match pool_id:
		"ao_wider":   GameManager.add_mech("aoe_pct", 0.05)
		"ao_cadence":
			GameManager.add_mech("aoe_pct", -0.03)
			GameManager.add_mech("tick_rate", 0.05)
		"ao_frag":
			GameManager.add_mech("aoe_pct", 0.025)
			GameManager.add_fire_rate(0.03)
		"ao_bombard": GameManager.add_mech("bombardment_dmg", 0.05)

func _apply_aoe_capstone(cap_id: String) -> void:
	match cap_id:
		"saturation":
			GameManager.add_mech("aoe_pct", -0.5)
			GameManager.add_mech("tick_rate", 1.0)
		"chain_reaction": GameManager.add_mech("chain_reaction", 1.0)
		"overpressure":   GameManager.add_mech("aoe_pct", 0.30)

## One rank of an Aim Assistor perk → GameManager crit stats / crit-status mechs.
func _apply_crit_pool_effect(pool_id: String) -> void:
	match pool_id:
		"cc_chance": GameManager.add_crit_chance(0.05)
		"cc_dmg":    GameManager.add_crit_damage(0.10)
		"cc_bleed":  GameManager.add_mech("crit_bleed", 2)
		"cc_burn":   GameManager.add_mech("crit_burn", 1)
		"cc_freeze": GameManager.add_mech("crit_freeze", 1)
		"cc_shock":  GameManager.add_mech("crit_shock", 0.3)

func _apply_crit_capstone(cap_id: String) -> void:
	match cap_id:
		"deadly":
			GameManager.add_crit_chance(1.0)
			GameManager.add_mech("crit_overflow", 1.0)   # flag: crit% over 100 → crit damage (in _roll_damage)
		"challenge":
			GameManager.add_crit_chance(-0.2)
			GameManager.upg_fervor = true

## One rank of a Force Field perk → GameManager shield stats.
func _apply_forcefield_pool_effect(pool_id: String) -> void:
	match pool_id:
		"ff_max":     GameManager.upg_force_shield_max += 15.0
		"ff_regen":   GameManager.upg_force_shield_regen += 0.5
		"ff_delay":   GameManager.upg_force_shield_delay_red += 0.5
		"ff_mastery": GameManager.upg_shield_mastery += 0.05
		"ff_quick":   # trade capacity for a much snappier shield (2× the normal regen + boot steps)
			GameManager.upg_force_shield_max -= 15.0
			GameManager.upg_force_shield_regen += 1.0
			GameManager.upg_force_shield_delay_red += 1.0
		"ff_panic":   GameManager.upg_panic_rank += 1

func _apply_forcefield_capstone(cap_id: String) -> void:
	match cap_id:
		"void_shield": GameManager.upg_void_shield = true
		"impervious":  GameManager.upg_impervious = true
		"energy_guns":
			GameManager.upg_shield_disabled = true
			if GameManager.has_method("add_mech"):
				GameManager.add_mech("rate_energy", 0.5)   # +50% energy fire rate

# ── Reinforcement Plate (hp) ──
func _apply_hp_pool_effect(pool_id: String) -> void:
	match pool_id:
		"plating":
			_rp_add_flat_hp(20.0)
		"bulwark":
			_rp_add_flat_hp(10.0)
			GameManager.add_base_defense(1)
		"ablative":
			_rp_add_flat_hp(10.0)
			GameManager.add_move_speed(0.02)
		"sacrifice":
			# -5% Max HP = -5% of base ship HP (flat, not Mastery-boosted: it's a cost, not a gain), +5% damage.
			GameManager.add_max_hp(-int(round(float(GameManager.BASE_SHIP_HP) * 0.05)))
			GameManager.add_damage(0.05)
		"mastery":
			_rp_grant_mastery(0.05)
		"overall":
			_rp_grant_overall(0.01)

# ── Nanobots (regen) ──
## Regeneration Mastery is a live GameManager multiplier (upg_regen_mastery), so flat regen grants here are
## simple add_* calls — Mastery scales them retroactively at rate-computation time. "automation"/"bodies" are
## stored as global mechs (add_mech) pending the automation-weapon / body-segment wiring in arena_weapons.
func _apply_regen_pool_effect(pool_id: String) -> void:
	match pool_id:
		"regen_flat":
			GameManager.add_hp_regen(0.2)
		"regen_hp":
			GameManager.add_hp_regen(0.1)
			GameManager.add_max_hp(10)
		"regen_shield":
			GameManager.add_hp_regen(0.1)
			GameManager.add_force_shield(0.0, 0.1)
		"regen_mastery":
			GameManager.add_regen_mastery(0.05)
		"automation":
			GameManager.add_mech("automation_speed", 0.05)   # STUB: consumed once automation weapons are tagged
		"overregen":
			GameManager.set_overregen_to_shield(true)
			GameManager.add_force_shield(10.0, 0.0)

# ── Exoskeleton (armor) ──
## Harden Mastery is a live GameManager multiplier (upg_harden_mastery) → flat armor gains are simple add_*
## calls, scaled retroactively. Reflect / kinetic-crit are stored as global mechs (STUBs) pending wiring.
func _apply_armor_pool_effect(pool_id: String) -> void:
	match pool_id:
		"ex_armor":
			GameManager.add_base_defense(2)
		"ex_armor_hp":
			GameManager.add_base_defense(1)
			GameManager.add_max_hp(1)
		"ex_predr":
			GameManager.add_pre_dr(0.03)
		"ex_reflect":
			GameManager.add_mech("reflect_chance", 0.08)   # STUB: pending enemy-projectile reflection wiring
		"ex_mastery":
			GameManager.add_harden_mastery(0.05)
		"ex_crit":
			GameManager.add_mech("kinetic_crit_chance", 0.05)   # STUB: pending kinetic-family crit wiring

# ── Drill Bits (armor_pen) — armor penetration + bleed (GLOBAL mechs read in arena_enemy.take_damage). ──
func _apply_armorpen_pool_effect(pool_id: String) -> void:
	match pool_id:
		"pen_flat":
			GameManager.add_mech("armor_pen_flat", 2.0)
		"pen_pct":
			GameManager.add_mech("armor_pen_pct", 0.05)
		"serrated":
			GameManager.add_mech("serrated", 1.0)
		"bleed_mastery":
			GameManager.add_mech("bleed_max_add", 50.0)
		"critbreak":
			GameManager.add_mech("critbreak", 0.02)

## Drill Bits evolution.
func _apply_armorpen_capstone(cap_id: String) -> void:
	match cap_id:
		"less_than_nothing":
			GameManager.add_mech("less_than_nothing", 1.0)
		"fortification":
			GameManager.add_mech("armor_pen_pct", 0.20)
			GameManager.add_base_defense(int(round(float(GameManager.upg_base_defense) * 0.20)))   # +20% of your armor
		"hurt":
			GameManager.add_mech("hurt", 1.0)

# ── Auto-Loader (fire_rate) — global fire-rate + per-family cadence + tick speed (GLOBAL mechs). ──
func _apply_firerate_pool_effect(pool_id: String) -> void:
	match pool_id:
		"rate_all":
			GameManager.add_fire_rate(0.025)
		"rate_kinetic":
			GameManager.add_mech("rate_kinetic", 0.05)
		"rate_energy":
			GameManager.add_mech("rate_energy", 0.05)
		"rate_bio":
			GameManager.add_mech("rate_bio", 0.05)
		"intensity":
			GameManager.add_mech("tick_rate", 0.05)
		"tradeoff":
			GameManager.add_fire_rate(-0.025)
			GameManager.add_mech("all_dmg", 0.05)

## Auto-Loader evolution. Charged Up / Speed is Force are global-mech flags read in _roll_damage; Absolute
## Focus is a GameManager fire-rate ramp.
func _apply_firerate_capstone(cap_id: String) -> void:
	match cap_id:
		"charged_up":
			GameManager.add_mech("charged_up", 1.0)
		"speed_is_force":
			GameManager.add_mech("speed_force", 1.0)
		"absolute_focus":
			GameManager.set_focus(true)

# ── Art of War (damage) — masteries are GLOBAL mechs (shared by name across items). Per-item max = spawn cap. ──
func _apply_damage_pool_effect(pool_id: String) -> void:
	match pool_id:
		"kinetic":
			GameManager.add_mech("kinetic_dmg", 0.10)
		"energy":
			GameManager.add_mech("energy_dmg", 0.10)
		"bio":
			GameManager.add_mech("bio_dmg", 0.10)
		"general":
			GameManager.add_mech("all_dmg", 0.025)
		"luck":
			GameManager.add_mech("proc_luck", 0.01)

## Art of War evolution — the three "Truths". Each disables the other families via arena_weapons.apply_truth.
func _apply_damage_capstone(cap_id: String) -> void:
	var aw := get_tree().get_first_node_in_group("arena_weapons")
	if aw == null or not aw.has_method("apply_truth"):
		return
	match cap_id:
		"kinetic_truth": aw.call("apply_truth", "kinetic")
		"energy_truth":  aw.call("apply_truth", "energy")
		"bio_truth":     aw.call("apply_truth", "biochemical")

# ── Fins (speed) ──
func _apply_speed_pool_effect(pool_id: String) -> void:
	match pool_id:
		"sp_ms":
			GameManager.add_move_speed(0.06)
		"sp_dodge":
			GameManager.add_dodge(0.05)
		"sp_shrink":
			GameManager.mul_ship_size(0.97)   # -3% ship size
		"sp_iframe":
			GameManager.add_iframe_mult(0.20)
		"sp_ms_fire":
			GameManager.add_move_speed(0.02)
			GameManager.add_fire_rate(0.02)
		"sp_mastery":
			GameManager.add_speed_mastery(0.15)

## Fins evolution (Glass Cannon is one-time; Daredevil/Momentum are toggles handled live in GameManager).
func _apply_speed_capstone(cap_id: String) -> void:
	match cap_id:
		"glass":
			GameManager.add_max_hp(-int(round(float(GameManager.ship_max_hp) * 0.25)))   # -25% Max HP
			GameManager.mul_ship_size(0.75)                                              # -25% ship size
			GameManager.add_dodge(0.25)                                                  # +25% Dodge
		"daredevil":
			GameManager.set_damage_taken_mult(1.20)   # +20% damage taken
			GameManager.set_daredevil(true)           # +1%/3s damage ramp (reset on hit)
		"momentum":
			GameManager.set_ms_to_firerate(true)

## Exoskeleton evolution (Bastion is dynamic in _recompute_dynamic; Fortress/Reactive are one-time toggles).
func _apply_armor_capstone(cap_id: String) -> void:
	match cap_id:
		"fortress":
			GameManager.add_move_speed(-0.30)        # -30% move speed
			GameManager.set_armor_to_dr(true)        # +1% DR per 10 armor
			GameManager.set_dr_cap(0.75)             # total % DR capped at 75%
		"reactive":
			GameManager.set_mitigation_shockwave(true)
		# bastion handled live in _recompute_dynamic

## Nanobots evolution (one-time effects; Will to Live is handled live in _recompute_dynamic).
func _apply_regen_capstone(cap_id: String) -> void:
	match cap_id:
		"attack":
			# Set HP regen to 0; +1% automation-weapon damage per 0.1 regen lost this way.
			var steps := int(GameManager.upg_hp_regen / 0.1)
			if steps > 0:
				GameManager.add_mech("automation_dmg", 0.01 * float(steps))   # STUB: pending automation wiring
			GameManager.disable_hp_regen()
		"bodies":
			GameManager.add_mech("body_count", 2)   # STUB: pending body-segment wiring (e.g. Space Snake)

## Per-level reward for a pooled aux (applied once when each level is reached). Lv6 = evolution only (no stat).
func _apply_aux_level_reward(id: String, level: int) -> void:
	if id == "hp":
		_apply_hp_level_reward(level)
	elif id == "regen":
		_apply_regen_level_reward(level)
	elif id == "armor":
		_apply_armor_level_reward(level)
	elif id == "speed":
		_apply_speed_level_reward(level)
	elif id == "damage":
		_apply_damage_level_reward(level)

func _apply_hp_level_reward(level: int) -> void:
	match level:
		1:
			_rp_add_flat_hp(50.0)
		2:
			_rp_add_flat_hp(20.0)
			GameManager.add_base_defense(2)
		3:
			_rp_add_flat_hp(20.0)
			GameManager.add_move_speed(0.05)
		4:
			_rp_grant_overall(0.05)
		5:
			_rp_grant_mastery(0.10)
		# 6: evolution only

func _apply_regen_level_reward(level: int) -> void:
	match level:
		1:
			GameManager.add_force_shield(20.0, 0.0)   # +20 Max Shield
		2:
			GameManager.add_hp_regen(0.5)
		3:
			GameManager.add_max_hp(50)
		4:
			GameManager.add_mech("automation_speed", 0.15)
		5:
			GameManager.add_regen_mastery(0.10)
		# 6: evolution only

func _apply_armor_level_reward(level: int) -> void:
	match level:
		1:
			GameManager.add_base_defense(10)                      # +10 armor
		2:
			GameManager.add_pre_dr(0.10)                          # +10% DR (pre-armor)
		3:
			GameManager.add_harden_mastery(0.10)                  # +10% Harden Mastery
		4:
			GameManager.add_mech("reflect_chance", 0.10)          # STUB: +10% projectile reflect
		5:
			GameManager.add_mech("kinetic_crit_dmg", 0.10)        # STUB: +10% kinetic crit damage
		# 6: evolution only

func _apply_damage_level_reward(level: int) -> void:
	match level:
		1:
			GameManager.add_mech("kinetic_dmg", 0.10)
		2:
			GameManager.add_mech("energy_dmg", 0.10)
		3:
			GameManager.add_mech("bio_dmg", 0.10)
		4:
			GameManager.add_mech("proc_luck", 0.05)
		5:
			GameManager.add_mech("all_dmg", 0.075)
		# 6: evolution only

func _apply_speed_level_reward(level: int) -> void:
	match level:
		1:
			GameManager.add_dodge(0.10)            # +10% Dodge
		2:
			GameManager.add_move_speed(0.15)       # +15% Move Speed
		3:
			GameManager.mul_ship_size(0.90)        # -10% ship size
		4:
			GameManager.add_fire_rate(0.07)        # +7% Fire Rate
		5:
			GameManager.add_speed_mastery(0.25)    # +25% Speed Mastery
		# 6: evolution only

func _rp_add_flat_hp(n: float) -> void:
	_rp_flat += n
	_rp_recompute_hp()

func _rp_grant_mastery(amt: float) -> void:
	_rp_mastery += amt
	_rp_recompute_hp()

func _rp_grant_overall(amt: float) -> void:
	_rp_overall += amt
	_rp_recompute_hp()           # +HP part (% of base ship HP)
	GameManager.add_damage(amt)  # +% damage
	GameManager.add_move_speed(amt)  # +% move speed
	_recompute_dynamic()         # +armor = a % of your TOTAL armor (rounded up) — see _recompute_dynamic

## Recompute the reinforcement HP contribution and push the DELTA into GameManager (keeps Mastery retroactive).
func _rp_recompute_hp() -> void:
	var target := int(round(_rp_flat * (1.0 + _rp_mastery) + float(GameManager.BASE_SHIP_HP) * _rp_overall))
	var delta := target - _rp_applied
	if delta != 0:
		GameManager.add_max_hp(delta)
		_rp_applied = target

## Reckless Abandon (one-time on pick): drop to 50 HP, +1% damage for every 10 HP lost this way.
func _apply_reckless() -> void:
	var cur := int(GameManager.ship_hp)
	if cur > 50:
		var steps := int((cur - 50) / 10)
		if steps > 0:
			GameManager.add_damage(0.01 * float(steps))
		GameManager.ship_hp = 50
		GameManager.ship_hp_changed.emit(50)

## Recompute the value-driven evolutions + Overall armor. Called from GameManager's stat/HP signals (and once
## when the capstone is chosen), NOT per-frame — so each only recomputes when its source value actually changes.
## Guarded against the re-entrant signals our own add_* calls emit; Juggernaut runs before Overall so Overall's
## "% of total armor" sees the up-to-date Juggernaut armor in the same pass.
func _recompute_dynamic(_arg = null) -> void:
	if _recomputing:
		return
	_recomputing = true
	var cap := aux_capstone("hp")
	# Juggernaut — armor scales with MAX HP only (not current HP). +1 armor per 50 max HP.
	if cap == "juggernaut":
		var jt := int(GameManager.ship_max_hp / 50)
		if jt != _jug_armor:
			GameManager.add_base_defense(jt - _jug_armor)
			_jug_armor = jt
	# Calm Under Pressure — +5% fire rate & damage per 5% of MISSING HP (this one IS current-HP driven).
	if cap == "calm":
		var maxhp := maxf(1.0, float(GameManager.ship_max_hp))
		var missing := clampf(1.0 - float(GameManager.ship_hp) / maxhp, 0.0, 1.0)
		var bonus := float(int(missing / 0.05)) * 0.05
		if absf(bonus - _calm_bonus) > 0.0001:
			GameManager.add_damage(bonus - _calm_bonus)
			GameManager.add_fire_rate(bonus - _calm_bonus)
			_calm_bonus = bonus
	# Overall Improvement armor — a PERCENTAGE of your total armor (from every other source), rounded up.
	if _rp_overall > 0.0:
		var base_armor := int(GameManager.upg_base_defense) - _ov_armor   # total armor minus our own contribution
		var ot := ceili(float(base_armor) * _rp_overall)
		if ot != _ov_armor:
			GameManager.add_base_defense(ot - _ov_armor)
			_ov_armor = ot
	# Will to Live — ×3 HP regen while below 30% Max HP (current-HP driven). GameManager's setter no-ops if unchanged.
	if aux_capstone("regen") == "will_to_live":
		var rmax := maxf(1.0, float(GameManager.ship_max_hp))
		var low: bool = float(GameManager.ship_hp) / rmax < 0.30
		GameManager.set_regen_wtl_mult(3.0 if low else 1.0)
	# Bastion — Max HP and Max Shield each track HALF your (flat) armor. Delta-applied off the armor value.
	if aux_capstone("armor") == "bastion":
		var half := int(GameManager.upg_base_defense / 2)
		var dh := half - _bastion_hp
		if dh != 0:
			GameManager.add_max_hp(dh)
			_bastion_hp = half
		var ds := float(half) - _bastion_shield
		if absf(ds) > 0.01:
			GameManager.add_force_shield(ds, 0.0)
			_bastion_shield = float(half)
	_recomputing = false
