import { createHash } from "node:crypto";
import { access, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const SCHEMA_VERSION = 1;
const FIXTURE_ID = "web-m2-damage-golden-v1";
const ROOT_SEED = "M2-DAMAGE-GOLDEN-v1";
const RNG_STREAM = "combat";
const MODULE_PATHS = Object.freeze({
  damage: "scripts/core/damage.js",
  contexts: "scripts/core/contexts.js",
  random: "scripts/core/random.js",
});
const DEFAULT_OUTPUT = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "web_m2_damage_golden.json",
);

function parseArgs(argv) {
  let webRoot = "";
  let output = DEFAULT_OUTPUT;
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--web-root") {
      webRoot = argv[index + 1] || "";
      index += 1;
    } else if (argument === "--output") {
      output = argv[index + 1] || "";
      index += 1;
    } else {
      throw new Error(`unknown argument: ${argument}`);
    }
  }
  if (!webRoot) throw new Error("--web-root is required");
  if (!output) throw new Error("--output requires a path");
  return { webRoot: path.resolve(webRoot), output: path.resolve(output) };
}

function effect(overrides = {}) {
  return {
    source_type: "basic_attack",
    source_id: "golden_basic",
    source_name: "Golden 普攻",
    source_side: "ally",
    source_actor_id: "hero-9",
    counts_as_skill_cast: false,
    spent_skill_points: false,
    free_cast: false,
    counts_as_basic_attack: true,
    counts_as_attack: true,
    triggers_enemy_kill_effects: true,
    ...overrides,
  };
}

function context(overrides = {}) {
  return {
    target_id: "enemy-1",
    raw_amount: 20,
    category: "direct",
    effect: effect(),
    dealer_type: "piece",
    dealer_name: "Golden 攻击",
    dealer_id: "hero-9",
    attacker_unit_id: "piece-3",
    can_crit: false,
    crit_rate: 0,
    guaranteed_crit: false,
    can_block: false,
    ...overrides,
  };
}

function target(overrides = {}) {
  return {
    id: "enemy-1",
    side: "enemy",
    hp: 100,
    max_hp: 100,
    alive: true,
    hp_threshold_crossed: false,
    base_block_rate: 0,
    ...overrides,
  };
}

function cases() {
  return [
    {
      id: "direct_plain",
      coverage: ["direct", "plain", "no_rng"],
      input: {
        target: target(),
        context: context({ raw_amount: 20 }),
        metadata: { case_id: "direct_plain", damage_multiplier: 1.25 },
      },
    },
    {
      id: "direct_crit",
      coverage: ["direct", "crit", "one_rng_draw"],
      input: {
        target: target(),
        context: context({ raw_amount: 20, can_crit: true, crit_rate: 0.95 }),
        metadata: { case_id: "direct_crit", damage_multiplier: 1 },
      },
    },
    {
      id: "direct_block",
      coverage: ["direct", "block", "one_rng_draw"],
      input: {
        target: target({ base_block_rate: 0.95 }),
        context: context({ raw_amount: 40, can_block: true }),
        metadata: { case_id: "direct_block", damage_multiplier: 1 },
      },
    },
    {
      id: "direct_crit_block_order",
      coverage: ["direct", "crit", "block", "crit_then_block_rng_order", "two_rng_draws"],
      input: {
        target: target({ hp: 200, max_hp: 200, base_block_rate: 0.95 }),
        context: context({
          raw_amount: 40,
          can_crit: true,
          crit_rate: 0.95,
          can_block: true,
        }),
        metadata: { case_id: "direct_crit_block_order", damage_multiplier: 1 },
      },
    },
    {
      id: "direct_lethal",
      coverage: ["direct", "lethal", "death_context", "no_rng"],
      input: {
        target: target({ hp: 30, max_hp: 100 }),
        context: context({ raw_amount: 50 }),
        metadata: { case_id: "direct_lethal", damage_multiplier: 1 },
      },
    },
    {
      id: "delayed_forces_no_rng",
      coverage: ["delayed", "forced_no_crit", "forced_no_block", "no_rng"],
      input: {
        target: target(),
        context: context({
          raw_amount: 15,
          category: "delayed",
          effect: effect({
            source_type: "delayed_damage",
            source_id: "golden_burn",
            source_name: "Golden 灼烧",
            counts_as_basic_attack: false,
            counts_as_attack: false,
          }),
          can_crit: true,
          crit_rate: 0.95,
          guaranteed_crit: true,
          can_block: true,
        }),
        metadata: { case_id: "delayed_forces_no_rng", damage_multiplier: 1 },
      },
    },
  ];
}

function toWebEffect(value) {
  return {
    sourceType: value.source_type,
    sourceId: value.source_id,
    sourceName: value.source_name,
    sourceSide: value.source_side,
    sourceActorId: value.source_actor_id,
    countsAsSkillCast: value.counts_as_skill_cast,
    spentSkillPoints: value.spent_skill_points,
    freeCast: value.free_cast,
    countsAsBasicAttack: value.counts_as_basic_attack,
    countsAsAttack: value.counts_as_attack,
    triggersEnemyKillEffects: value.triggers_enemy_kill_effects,
  };
}

function toWebContext(value) {
  return {
    targetId: value.target_id,
    rawAmount: value.raw_amount,
    category: value.category,
    effect: toWebEffect(value.effect),
    dealerType: value.dealer_type,
    dealerName: value.dealer_name,
    dealerId: value.dealer_id,
    attackerUnitId: value.attacker_unit_id,
    canCrit: value.can_crit,
    critRate: value.crit_rate,
    guaranteedCrit: value.guaranteed_crit,
    canBlock: value.can_block,
  };
}

function toWebTarget(value) {
  return {
    id: value.id,
    side: value.side,
    hp: value.hp,
    maxHp: value.max_hp,
    alive: value.alive,
    hpThresholdCrossed: value.hp_threshold_crossed,
    baseBlockRate: value.base_block_rate,
  };
}

function normalizeEffect(value) {
  return {
    source_type: value.sourceType,
    source_id: value.sourceId,
    source_name: value.sourceName,
    source_side: value.sourceSide,
    source_actor_id: value.sourceActorId,
    counts_as_skill_cast: value.countsAsSkillCast,
    spent_skill_points: value.spentSkillPoints,
    free_cast: value.freeCast,
    counts_as_basic_attack: value.countsAsBasicAttack,
    counts_as_attack: value.countsAsAttack,
    triggers_enemy_kill_effects: value.triggersEnemyKillEffects,
  };
}

function normalizeDamageContext(value) {
  return {
    target_id: value.targetId,
    raw_amount: value.rawAmount,
    category: value.category,
    effect: normalizeEffect(value.effect),
    dealer_type: value.dealerType,
    dealer_name: value.dealerName,
    dealer_id: value.dealerId,
    attacker_unit_id: value.attackerUnitId,
    can_crit: value.canCrit,
    crit_rate: value.critRate,
    guaranteed_crit: value.guaranteedCrit,
    can_block: value.canBlock,
  };
}

function normalizeDeathContext(value) {
  if (value == null) return null;
  return {
    source_kind: value.sourceKind,
    effect: normalizeEffect(value.effect),
    source_side: value.sourceSide,
    source_actor_id: value.sourceActorId,
    triggers_enemy_kill_effects: value.triggersEnemyKillEffects,
  };
}

function normalizeTarget(value) {
  return {
    id: value.id,
    side: value.side,
    hp: value.hp,
    max_hp: value.maxHp,
    alive: value.alive,
    hp_threshold_crossed: value.hpThresholdCrossed,
    base_block_rate: value.baseBlockRate,
  };
}

function normalizeDamagePayload(value) {
  return {
    amount: value.amount,
    calculated_amount: value.calculatedAmount,
    blocked: value.blocked,
    crit: value.crit,
    died: value.died,
    old_hp: value.oldHp,
    new_hp: value.newHp,
    raw_amount_before_block: value.rawAmountBeforeBlock,
    damage_context: normalizeDamageContext(value.damageContext),
    death_context: null,
  };
}

function normalizeDeathPayload(value) {
  return {
    target: normalizeTarget(value.unit),
    old_hp: value.oldHp,
    damage_context: normalizeDamageContext(value.damageContext),
    effect_context: normalizeEffect(value.effectContext),
    death_context: normalizeDeathContext(value.deathContext),
    metadata: value.metadata,
  };
}

function normalizeEvent(type, payload) {
  const damage = payload.damageContext ? normalizeDamageContext(payload.damageContext) : null;
  const death = payload.deathContext ? normalizeDeathContext(payload.deathContext) : null;
  return {
    type,
    amount: payload.amount ?? null,
    calculated_amount: payload.calculatedAmount ?? null,
    blocked: payload.blocked ?? null,
    crit: payload.crit ?? null,
    died: payload.died ?? null,
    old_hp: payload.oldHp ?? null,
    new_hp: payload.newHp ?? null,
    raw_amount_before_block: payload.rawAmountBeforeBlock ?? null,
    damage_context: damage,
    death_context: death,
  };
}

function normalizedResult(result) {
  return {
    dealt: result.dealt,
    blocked: result.blocked,
    died: result.died,
    crit: result.crit,
    damage_context: normalizeDamageContext(result.damageContext),
    death_context: normalizeDeathContext(result.deathContext),
  };
}

async function main() {
  const { webRoot, output } = parseArgs(process.argv.slice(2));
  const absoluteModules = {};
  for (const [id, relativePath] of Object.entries(MODULE_PATHS)) {
    const absolutePath = path.join(webRoot, ...relativePath.split("/"));
    await access(absolutePath);
    absoluteModules[id] = absolutePath;
  }
  const [{ createDamagePipeline }, { createDamageContext }, { createNamedRandomStreams }] = await Promise.all([
    import(pathToFileURL(absoluteModules.damage).href),
    import(pathToFileURL(absoluteModules.contexts).href),
    import(pathToFileURL(absoluteModules.random).href),
  ]);
  if (typeof createDamagePipeline !== "function" || typeof createDamageContext !== "function" || typeof createNamedRandomStreams !== "function") {
    throw new Error("authoritative Web modules do not expose the required functions");
  }

  const combat = createNamedRandomStreams(ROOT_SEED)[RNG_STREAM];
  let globalDrawIndex = 0;
  const generatedCases = [];
  for (const definition of cases()) {
    const mutableTarget = toWebTarget(definition.input.target);
    const rngTrace = [];
    const callbackTrace = [];
    const eventTrace = [];
    let recorded = null;
    let caseDrawIndex = 0;
    const pipeline = createDamagePipeline({
      random: () => {
        const value = combat.next();
        const draw = { global_index: globalDrawIndex, case_index: caseDrawIndex, value };
        rngTrace.push(draw);
        callbackTrace.push({ op: "rng", value });
        globalDrawIndex += 1;
        caseDrawIndex += 1;
        return value;
      },
      format: (value) => {
        const formatted = Math.max(0, Math.round(value * 10) / 10);
        callbackTrace.push({ op: "format", input: value, output: formatted });
        return formatted;
      },
      getBlockRate: (unit) => {
        callbackTrace.push({ op: "get_block_rate", value: unit.baseBlockRate });
        return unit.baseBlockRate;
      },
      getDamageMultiplier: (_unit, _context, metadata) => {
        callbackTrace.push({ op: "get_damage_multiplier", value: metadata.damage_multiplier });
        return metadata.damage_multiplier;
      },
      onEvent: (type, payload) => {
        callbackTrace.push({ op: "event", type });
        eventTrace.push(normalizeEvent(type, payload));
      },
      onDeath: (unit, deathContext, payload) => {
        callbackTrace.push({
          op: "death",
          target: normalizeTarget(unit),
          death_context: normalizeDeathContext(deathContext),
          payload: normalizeDeathPayload(payload),
        });
      },
      recordDamage: (payload) => {
        callbackTrace.push({ op: "record" });
        recorded = normalizeDamagePayload(payload);
      },
    });
    const result = pipeline.apply(
      mutableTarget,
      createDamageContext(toWebContext(definition.input.context)),
      definition.input.metadata,
    );
    generatedCases.push({
      id: definition.id,
      coverage: definition.coverage,
      input: definition.input,
      expected: {
        result: normalizedResult(result),
        target_after: normalizeTarget(mutableTarget),
        record: recorded,
        event_trace: eventTrace,
        rng_trace: rngTrace,
        callback_trace: callbackTrace,
      },
    });
  }

  const moduleHashes = {};
  for (const [id, absolutePath] of Object.entries(absoluteModules)) {
    moduleHashes[id] = createHash("sha256").update(await readFile(absolutePath)).digest("hex");
  }
  const fixture = {
    schema_version: SCHEMA_VERSION,
    fixture_id: FIXTURE_ID,
    authoritative_modules: MODULE_PATHS,
    authoritative_sha256: moduleHashes,
    root_seed: ROOT_SEED,
    rng_stream: RNG_STREAM,
    format_policy: "max(0, Math.round(value * 10) / 10)",
    case_count: generatedCases.length,
    case_order: generatedCases.map(({ id }) => id),
    cases: generatedCases,
  };
  await writeFile(output, `${JSON.stringify(fixture, null, 2)}\n`, "utf8");
  process.stdout.write(`wrote ${generatedCases.length} cases to ${output}\n`);
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exitCode = 1;
});
