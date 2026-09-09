class_name HeroCardCatalog
extends RefCounted

const Card = preload("res://data/definitions/card_definition.gd")

static func definitions() -> Dictionary:
	return {
		"exclusive:pressOpening": Card.new(
			"exclusive:pressOpening", "pressOpening", "hero_ability", Card.CATEGORY_EXCLUSIVE,
			1, 7, Card.PILE_DISCARD, Card.PILE_DISCARD, false,
			"battle.canCastExclusiveSkill.pressOpening", "battle.castExclusiveSkill.pressOpening",
		)
	}

static func ids() -> Array[String]:
	return ["exclusive:pressOpening"]

static func handler_ids() -> Array[String]:
	return ["battle.castExclusiveSkill.pressOpening"]

static func display(card_id: String) -> Dictionary:
	if card_id == "exclusive:pressOpening":
		return {"name": "乘隙", "description": "消耗1技能点。敌方存在破势目标时，我方攻击最高的存活非傀儡棋子获得2层追击。"}
	return {}
