class_name HeroCardCatalog
extends RefCounted

const Card = preload("res://data/definitions/card_definition.gd")

static func definitions() -> Dictionary:
	return {
		"exclusive:pressOpening": Card.new(
			"exclusive:pressOpening", "pressOpening", "hero_ability", Card.CATEGORY_EXCLUSIVE,
			1, 7, Card.PILE_DISCARD, Card.PILE_DISCARD, false,
			"battle.canCastExclusiveSkill.pressOpening", "battle.castExclusiveSkill.pressOpening",
		),
		"exclusive:puppetAttunement": Card.new(
			"exclusive:puppetAttunement", "puppetAttunement", "hero_ability", Card.CATEGORY_EXCLUSIVE,
			1, 8, Card.PILE_DISCARD, Card.PILE_DISCARD, false,
			"battle.canCastExclusiveSkill.puppetAttunement", "battle.castExclusiveSkill.puppetAttunement",
		),
	}

static func ids() -> Array[String]:
	return ["exclusive:pressOpening", "exclusive:puppetAttunement"]

static func handler_ids() -> Array[String]:
	return ["battle.castExclusiveSkill.pressOpening", "battle.castExclusiveSkill.puppetAttunement"]

static func display(card_id: String) -> Dictionary:
	if card_id == "exclusive:pressOpening":
		return {"name": "乘隙", "description": "消耗1技能点。敌方存在破势目标时，我方攻击最高的存活非傀儡棋子获得2层追击。"}
	if card_id == "exclusive:puppetAttunement":
		return {"name": "点化", "description": "消耗1技能点。指定一个尚不能附魔的存活傀儡，使其本场获得1个附魔槽；未指定时按阵位自动选择。"}
	return {}
