class_name Seal
## Sealed monoliths (刻紋の封碑): the map event that gives 刻紋の熾石, the currency that carves a special modifier
## into a rare item. Some maps hide one monolith in a room; breaking its seal frees its wardens, and while any
## of them stands the monolith keeps hurling runes at the player. Felling every warden pays the stones.

const COLOR := Color("#5ff0c0")
const CHANCE := 0.55        # share of maps that have a monolith
const RADIUS := 8.0         # m: the wardens come out within this
const PULSE := 3.2          # s between the monolith's rune blasts while wardens stand
const BLAST_R := 2.4


## how many wardens a monolith at area level `level` holds
static func wardens(level: int) -> int:
	return mini(6, 3 + level / 4)


## what the seal pays once every warden is down: 刻紋の熾石 (more deeper in), items and ember
static func reward(level: int, roll := randf()) -> Dictionary:
	return {"brand": 1 + (1 if roll < 0.3 + level * 0.03 else 0), "items": 1, "rarity": 1.0}


## the damage of one rune blast at area level `level`
static func blast_dmg(level: int) -> float:
	return 8.0 + level * 4.0
