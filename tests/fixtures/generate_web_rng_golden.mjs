import { createHash } from "node:crypto";
import { access, readFile, writeFile } from "node:fs/promises";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const fixtureDirectory = dirname(fileURLToPath(import.meta.url));
const fixturePath = join(fixtureDirectory, "web_rng_golden.json");
const sequenceLength = 1000;
const masterSeed = "弈者🎴-M0-B";
const defaultStreamNames = ["combat", "allyPolicy", "enemyPolicy", "run"];

async function findWebRandomSource() {
  let cursor = fixtureDirectory;
  for (let depth = 0; depth < 8; depth += 1) {
    const candidate = join(cursor, "新弈者", "Html", "scripts", "core", "random.js");
    try {
      await access(candidate);
      return candidate;
    } catch {
      cursor = resolve(cursor, "..");
    }
  }
  throw new Error("Unable to locate 新弈者/Html/scripts/core/random.js from fixture directory");
}

function collectUint32Numerators(randomSource, length) {
  return Array.from({ length }, () => Math.floor(randomSource.next() * 4294967296));
}

const sourcePath = await findWebRandomSource();
const sourceBytes = await readFile(sourcePath);
const sourceSha256 = createHash("sha256").update(sourceBytes).digest("hex");
const sourceModule = await import(`${pathToFileURL(sourcePath).href}?sha256=${sourceSha256}`);
const { createNamedRandomStreams, createSeededRandom, deriveSeed } = sourceModule;

const directSequence = collectUint32Numerators(createSeededRandom(masterSeed), sequenceLength);
const namedSources = createNamedRandomStreams(masterSeed, defaultStreamNames);
const namedSequences = Object.fromEntries(
  defaultStreamNames.map((name) => [name, collectUint32Numerators(namedSources[name], sequenceLength)]),
);

const fixture = {
  schema_version: 1,
  provenance: {
    authoritative_module: relative(resolve(fixtureDirectory, "../../../../.."), sourcePath).replaceAll("\\", "/"),
    source_sha256: sourceSha256,
    generated_utc: new Date().toISOString(),
    algorithm: "Web random.js createSeededRandom outputs converted to exact uint32 numerators",
  },
  master_seed: masterSeed,
  sequence_length: sequenceLength,
  default_stream_names: defaultStreamNames,
  derive_seeds: Object.fromEntries(defaultStreamNames.map((name) => [name, deriveSeed(masterSeed, name)])),
  direct_seeded_u32: directSequence,
  named_streams_u32: namedSequences,
  edge_cases: {
    utf16_seed: "中文😀seed",
    utf16_first_u32: collectUint32Numerators(createSeededRandom("中文😀seed"), 8),
    utf16_derive_probe: deriveSeed("中文😀seed", "流🎴"),
    numeric_seed: 4294967297,
    numeric_equivalent_seed: 1,
    numeric_first_u32: collectUint32Numerators(createSeededRandom(4294967297), 8),
    zero_seed: 0,
    zero_first_u32: collectUint32Numerators(createSeededRandom(0), 8),
    nan_first_u32: collectUint32Numerators(createSeededRandom(Number.NaN), 8),
    positive_infinity_first_u32: collectUint32Numerators(createSeededRandom(Number.POSITIVE_INFINITY), 8),
    negative_infinity_first_u32: collectUint32Numerators(createSeededRandom(Number.NEGATIVE_INFINITY), 8),
  },
};

await writeFile(fixturePath, `${JSON.stringify(fixture, null, 2)}\n`, "utf8");
console.log(`Wrote ${fixturePath}`);
console.log(`Source SHA-256: ${sourceSha256}`);
console.log(`Sequences: direct=${sequenceLength}, named=${defaultStreamNames.length}x${sequenceLength}`);
