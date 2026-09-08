import { createHash } from "node:crypto";
import { access, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const MODULE_PATHS = Object.freeze({
  map_system: "scripts/systems/roguelike/map-system.js",
  roguelike_content: "scripts/data/roguelike-content.js",
  random: "scripts/core/random.js",
  skills: "scripts/data/skills.js",
  relics: "scripts/data/relics.js",
  piece_classes: "scripts/data/piece_classes.js",
  enemy_specials: "scripts/data/enemy-specials.js",
});
const DEFAULT_OUTPUT = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "web_m5_map_golden.json",
);
const DEFAULT_WEB_ROOT = "C:\\Users\\78566\\Documents\\ChatGPT\\弈者-独立版\\Html";

function parseArgs(argv) {
  let webRoot = process.env.YIZHE_WEB_ROOT || DEFAULT_WEB_ROOT;
  let output = DEFAULT_OUTPUT;
  for (let index = 0; index < argv.length; index += 1) {
    if (argv[index] === "--web-root") {
      webRoot = argv[index + 1] || "";
      index += 1;
    } else if (argv[index] === "--output") {
      output = argv[index + 1] || "";
      index += 1;
    } else {
      throw new Error(`unknown argument: ${argv[index]}`);
    }
  }
  if (!webRoot) {
    throw new Error(
      "--web-root is required (or set YIZHE_WEB_ROOT to 弈者-独立版/Html)",
    );
  }
  return { webRoot: path.resolve(webRoot), output: path.resolve(output) };
}

function normalizeNode(node) {
  return {
    id: node.id,
    chapter: node.chapter,
    row: node.row,
    column: node.column,
    type: node.type,
    available: node.available,
    completed: node.completed,
    next_node_ids: node.nextNodeIds,
  };
}

function normalizeEncounter(encounter) {
  return {
    id: encounter.id,
    name: encounter.name,
    hp_scale: encounter.hpScale,
    atk_scale: encounter.atkScale,
    slots: encounter.slots.map((slot) => ({
      unit_id: slot.unitId,
      piece_class_id: slot.pieceClassId,
      special_id: slot.specialId,
      class_name: slot.className,
      hp_scale: slot.hpScale,
      atk_scale: slot.atkScale,
      special_hp_scale: slot.specialHpScale,
      special_atk_scale: slot.specialAtkScale,
      total_hp_scale: slot.totalHpScale,
      total_atk_scale: slot.totalAtkScale,
      empty: slot.empty,
    })),
  };
}

async function main() {
  const { webRoot, output } = parseArgs(process.argv.slice(2));
  const absolute = {};
  for (const [id, relativePath] of Object.entries(MODULE_PATHS)) {
    absolute[id] = path.join(webRoot, ...relativePath.split("/"));
    await access(absolute[id]);
  }
  const [mapModule, contentModule, randomModule, skillsModule, relicsModule, piecesModule, specialsModule] = await Promise.all([
    import(pathToFileURL(absolute.map_system).href),
    import(pathToFileURL(absolute.roguelike_content).href),
    import(pathToFileURL(absolute.random).href),
    import(pathToFileURL(absolute.skills).href),
    import(pathToFileURL(absolute.relics).href),
    import(pathToFileURL(absolute.piece_classes).href),
    import(pathToFileURL(absolute.enemy_specials).href),
  ]);
  const createCatalog = (chapters = contentModule.ROGUELIKE_CHAPTER_DEFINITIONS) => (
    contentModule.createRoguelikeContentCatalog({
      chapters,
      encounters: contentModule.ROGUELIKE_ENCOUNTER_DEFINITIONS,
      shentongs: contentModule.SHENTONG_DEFINITIONS,
      freeSkills: skillsModule.FREE_SKILL_CATALOG,
      relics: relicsModule.RELIC_CATALOG,
      pieceClasses: piecesModule.PIECE_CLASSES,
      enemySpecials: specialsModule.ENEMY_SPECIAL_CATALOG,
    })
  );
  const catalog = createCatalog();
  const mapCases = [1, 2, 3].map((chapter) => {
    const seed = `M5-MAP-CHAPTER-${chapter}-v1`;
    return {
      chapter,
      seed,
      nodes: mapModule.buildRoguelikeChapterMap({
        catalog,
        chapter,
        rng: randomModule.createSeededRandom(seed),
      }).map(normalizeNode),
    };
  });

  const weightedPool = [
    { type: "battle", weight: 5 },
    { type: "event", weight: 2 },
    { type: "shop", weight: 1 },
    { type: "forge", weight: 1 },
    { type: "elite", weight: 1 },
  ];
  const weightedChapters = contentModule.ROGUELIKE_CHAPTER_DEFINITIONS.map((chapter) => (
    chapter.chapter !== 1 ? chapter : {
      ...chapter,
      columnRules: chapter.columnRules.map((rule) => (
        rule.column !== 1 ? rule : { column: 1, fixedByRow: null, pool: weightedPool }
      )),
    }
  ));
  const weightedSeed = "M5-MAP-WEIGHTED-v1";
  const weightedNodes = mapModule.buildRoguelikeChapterMap({
    catalog: createCatalog(weightedChapters),
    chapter: 1,
    rng: randomModule.createSeededRandom(weightedSeed),
  }).map(normalizeNode);

  const encounterCases = [
    { id: "normal", seed: "M5-ENCOUNTER-normal", node: { chapter: 1, row: 0, column: 0, type: "battle" } },
    { id: "elite_core", seed: "M5-ENCOUNTER-elite", node: { chapter: 2, row: 1, column: 6, type: "elite" } },
    { id: "boss_core", seed: "M5-ENCOUNTER-boss", node: { chapter: 3, row: 0, column: 9, type: "boss" } },
  ].map((definition) => ({
    ...definition,
    expected: normalizeEncounter(mapModule.resolveRoguelikeEncounter({
      catalog,
      node: definition.node,
      rng: randomModule.createSeededRandom(definition.seed),
    })),
  }));

  const hashes = {};
  for (const [id, absolutePath] of Object.entries(absolute)) {
    hashes[id] = createHash("sha256").update(await readFile(absolutePath)).digest("hex");
  }
  const fixture = {
    schema_version: 1,
    fixture_id: "web-m5-map-golden-v1",
    generated_utc: new Date().toISOString(),
    authoritative_modules: MODULE_PATHS,
    authoritative_sha256: hashes,
    map_cases: mapCases,
    weighted_case: {
      chapter: 1,
      column: 1,
      seed: weightedSeed,
      pool: weightedPool,
      expected_nodes: weightedNodes.filter((node) => node.column === 1),
    },
    encounter_cases: encounterCases,
  };
  await writeFile(output, `${JSON.stringify(fixture, null, 2)}\n`, "utf8");
  process.stdout.write(`wrote M5 Web map golden to ${output}\n`);
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exitCode = 1;
});
