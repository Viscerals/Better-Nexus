#!/usr/bin/env node
"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const VALID_CLASSES = new Set([
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "DRUID", "UNKNOWN",
]);

const BUILD_FIELD_ORDER = [
    "id", "title", "description", "author", "ownerKey", "class",
    "echoes", "postedAt", "lastModified", "autoDps", "fingerprint",
    "fingerprintHash", "echoCount", "loadoutAvailable",
    "legacyRecovered", "legacyOwnership", "legacySource", "link", "linkHash",
];

const PERSONAL_ROW_FIELDS = [
    "importedSavedBuild", "serverSlot", "serverTitle", "destinationWishlistName",
    "destinationWishlistSlot", "destinationProgress", "destinationTotal",
    "activeServerBuild", "_savedSignature",
];

function parseArgs(argv) {
    const out = { sourceVersion: "1.19.4" };
    for (let i = 0; i < argv.length; i += 1) {
        const arg = argv[i];
        if (arg === "--input") out.input = argv[++i];
        else if (arg === "--output") out.output = argv[++i];
        else if (arg === "--report") out.report = argv[++i];
        else if (arg === "--source-version") out.sourceVersion = argv[++i];
        else if (arg === "--help" || arg === "-h") out.help = true;
        else throw new Error(`unknown argument: ${arg}`);
    }
    return out;
}

function usage() {
    return [
        "Usage: node tools/export-bundled-builds.js --input <Nexus.lua>",
        "  --output <data/BundledBuilds.lua> --report <report.json>",
        "  [--source-version <addon-version>]",
    ].join("\n");
}

function encodeForLuaParser(sourceText) {
    return Buffer.from(sourceText, "utf8").toString("latin1")
        .replace(/[\x80-\xff]/g, (character) =>
            String.fromCharCode(0xf700 | character.charCodeAt(0)));
}

function decodeLuaString(value) {
    const bytes = [];
    for (const character of value || "") {
        const code = character.charCodeAt(0);
        if (code >= 0xf780 && code <= 0xf7ff) bytes.push(code & 0xff);
        else if (code <= 0x7f) bytes.push(code);
        else throw new Error(`unexpected parser string code unit U+${code.toString(16)}`);
    }
    return Buffer.from(bytes).toString("utf8");
}

function loadLuaParser() {
    const candidates = [
        path.resolve(__dirname, "..", ".tools", "fengari", "node_modules", "luaparse"),
        "luaparse",
    ];
    for (const candidate of candidates) {
        try {
            return require(candidate);
        } catch (error) {
            if (error && error.code !== "MODULE_NOT_FOUND") throw error;
        }
    }
    throw new Error("luaparse is unavailable; restore .tools/fengari before exporting");
}

function scalar(node) {
    if (!node) throw new Error("missing Lua value");
    if (node.type === "StringLiteral") return decodeLuaString(node.value);
    if (node.type === "NumericLiteral" || node.type === "BooleanLiteral") return node.value;
    if (node.type === "NilLiteral") return null;
    if (node.type === "UnaryExpression" && node.operator === "-"
        && node.argument && node.argument.type === "NumericLiteral") {
        return -node.argument.value;
    }
    throw new Error(`unsupported Lua value ${node.type}`);
}

function fieldKey(field, nextIndex) {
    if (field.type === "TableValue") return nextIndex;
    if (field.type === "TableKeyString") return field.key.name;
    if (field.type === "TableKey") return scalar(field.key);
    throw new Error(`unsupported Lua table field ${field.type}`);
}

function tableFieldNode(table, wanted) {
    let nextIndex = 1;
    for (const field of table.fields || []) {
        const key = fieldKey(field, nextIndex);
        if (field.type === "TableValue") nextIndex += 1;
        if (String(key) === String(wanted)) return field.value;
    }
    return null;
}

function evaluate(node, location) {
    if (!node) throw new Error(`missing Lua value at ${location}`);
    if (node.type !== "TableConstructorExpression") return scalar(node);
    const out = Object.create(null);
    const seen = new Set();
    let nextIndex = 1;
    for (const field of node.fields || []) {
        const key = fieldKey(field, nextIndex);
        if (field.type === "TableValue") nextIndex += 1;
        const normalizedKey = String(key);
        if (seen.has(normalizedKey)) {
            throw new Error(`duplicate Lua table key ${normalizedKey} at ${location}`);
        }
        seen.add(normalizedKey);
        out[normalizedKey] = evaluate(field.value, `${location}.${normalizedKey}`);
    }
    return out;
}

function parseNexusDb(sourceText, parser = loadLuaParser()) {
    const ast = parser.parse(encodeForLuaParser(sourceText), {
        comments: false,
        encodingMode: "x-user-defined",
        locations: true,
        luaVersion: "5.1",
    });
    const assignments = (ast.body || []).filter((statement) =>
        statement.type === "AssignmentStatement"
        && statement.variables && statement.variables.length === 1
        && statement.variables[0].type === "Identifier"
        && statement.variables[0].name === "NexusDB");
    if (assignments.length !== 1) {
        throw new Error("expected exactly one literal NexusDB table assignment");
    }
    const assignment = assignments[0];
    if (!assignment.init || assignment.init.length !== 1
        || assignment.init[0].type !== "TableConstructorExpression") {
        throw new Error("expected exactly one literal NexusDB table assignment");
    }
    return evaluate(assignment.init[0], "NexusDB");
}

function parseCommunityBuilds(sourceText, parser = loadLuaParser()) {
    const database = parseNexusDb(sourceText, parser);
    const communityNode = database.communityBuilds;
    if (!communityNode || typeof communityNode !== "object") {
        throw new Error("NexusDB.communityBuilds is missing or is not a table");
    }
    return communityNode;
}

function own(object, key) {
    return Object.prototype.hasOwnProperty.call(object || {}, key);
}

function numeric(value) {
    return typeof value === "number" && Number.isFinite(value);
}

function integer(value) {
    return numeric(value) && Math.floor(value) === value;
}

function text(value, max, allowEmpty = false) {
    return typeof value === "string" && value.length <= max
        && (allowEmpty || value.length > 0) && !/[\x00-\x1f|]/.test(value);
}

function objectList(value) {
    if (!value || typeof value !== "object" || Array.isArray(value)) return null;
    const keys = Object.keys(value);
    if (keys.length === 0) return [];
    if (!keys.every((key) => /^(?:0|[1-9]\d*)$/.test(key))) return null;
    const indices = keys.map(Number).sort((a, b) => a - b);
    if (indices[0] !== 1 || indices.some((valueAt, i) => valueAt !== i + 1)) return null;
    return indices.map((index) => value[String(index)]);
}

function canonicalFingerprint(echoes) {
    const counts = new Map();
    for (const echo of echoes) {
        counts.set(echo.spellId, (counts.get(echo.spellId) || 0) + echo.stacks);
    }
    return [...counts.keys()].sort((a, b) => a - b)
        .map((id) => `${id}x${counts.get(id)}`).join(",");
}

function djb2(textValue) {
    let hash = 5381;
    const bytes = Buffer.from(textValue, "utf8");
    for (const byte of bytes) hash = ((hash * 33) + byte) % 2147483648;
    return hash.toString(16);
}

function normalizeEchoes(raw) {
    const rows = objectList(raw);
    if (!rows || rows.length < 1 || rows.length > 256) {
        return { error: "incompleteLoadout" };
    }
    const echoes = [];
    let total = 0;
    for (const row of rows) {
        if (!row || typeof row !== "object") return { error: "malformedEcho" };
        const rawSpellId = row.spellId != null ? row.spellId : row.id;
        const rawStacks = row.stacks != null ? row.stacks
            : row.count != null ? row.count : 1;
        const spellId = Number(rawSpellId);
        const stacks = Number(rawStacks);
        const quality = own(row, "quality") ? Number(row.quality) : 0;
        if (!integer(spellId) || spellId <= 0 || !integer(stacks) || stacks < 1
            || !integer(quality) || quality < -1 || quality > 100) {
            return { error: "malformedEcho" };
        }
        total += stacks;
        if (total > 120) return { error: "oversizedLoadout" };
        echoes.push({
            spellId,
            quality,
            stacks,
            ...(row.locked === true ? { locked: true } : {}),
        });
    }
    echoes.sort((left, right) => left.spellId - right.spellId
        || left.quality - right.quality
        || Number(left.locked === true) - Number(right.locked === true)
        || left.stacks - right.stacks);
    return { echoes, total };
}

function normalizeBuild(key, raw) {
    if (!raw || typeof raw !== "object") return { error: "malformedBuild" };
    if (raw.tombstoned === true) return { error: "tombstoned" };
    if (raw.importedSavedBuild === true || String(key).startsWith("saved-")) {
        return { error: "personalSavedLoadout" };
    }
    if (PERSONAL_ROW_FIELDS.some((field) => own(raw, field))) {
        return { error: "personalSavedLoadout" };
    }
    if (!text(key, 96) || raw.id !== key) return { error: "invalidId" };
    if (!text(raw.title, 120) || !text(raw.author, 80)) {
        return { error: "invalidIdentity" };
    }
    const className = typeof raw.class === "string" ? raw.class.toUpperCase() : "";
    if (!VALID_CLASSES.has(className)) return { error: "invalidClass" };
    if (raw.ownerKey != null && (!text(raw.ownerKey, 160)
        || !/^[^@]+@[^@]+$/.test(raw.ownerKey))) return { error: "invalidOwnerKey" };
    if (raw.description != null && !text(raw.description, 4000, true)) {
        return { error: "invalidDescription" };
    }
    if (raw.link != null && !text(raw.link, 400, true)) return { error: "invalidLink" };
    const revision = Number(raw.lastModified != null ? raw.lastModified : raw.postedAt);
    const postedAt = Number(raw.postedAt != null ? raw.postedAt : revision);
    if (!integer(revision) || revision < 0 || !integer(postedAt) || postedAt < 0) {
        return { error: "invalidRevision" };
    }
    if (raw.needsFullBuild === true || raw.loadoutAvailable === false) {
        return { error: "incompleteLoadout" };
    }
    const normalized = normalizeEchoes(raw.echoes);
    if (normalized.error) return normalized;
    const fingerprint = canonicalFingerprint(normalized.echoes);
    if (typeof raw.fingerprint !== "string" || raw.fingerprint !== fingerprint) {
        return { error: raw.fingerprint == null ? "missingFingerprint" : "invalidFingerprint" };
    }
    const fingerprintHash = djb2(fingerprint);
    if (raw.fingerprintHash != null
        && String(raw.fingerprintHash).toLowerCase() !== fingerprintHash) {
        return { error: "invalidFingerprintHash" };
    }
    if (raw.echoCount != null && Number(raw.echoCount) !== normalized.total) {
        return { error: "invalidEchoCount" };
    }
    const build = {
        id: key,
        title: raw.title,
        description: raw.description || "",
        author: raw.author,
        ...(raw.ownerKey ? { ownerKey: String(raw.ownerKey).toLowerCase() } : {}),
        class: className,
        echoes: normalized.echoes,
        postedAt,
        lastModified: revision,
        ...(raw.autoDps === true ? { autoDps: true } : {}),
        fingerprint,
        fingerprintHash,
        echoCount: normalized.total,
        loadoutAvailable: true,
        ...(raw.legacyRecovered === true ? {
            legacyRecovered: true,
            legacyOwnership: ["verified", "unverified"].includes(
                raw.legacyOwnership) ? raw.legacyOwnership : "unverified",
            legacySource: ["relay", "mixed", "direct-or-unknown"].includes(
                raw.legacySource) ? raw.legacySource : "direct-or-unknown",
        } : {}),
        ...(raw.link ? { link: raw.link, linkHash: djb2(raw.link) } : {}),
    };
    return { build, localMarker: raw.isMine === true };
}

function luaString(value) {
    let out = '"';
    for (const character of String(value)) {
        const code = character.codePointAt(0);
        if (character === "\\") out += "\\\\";
        else if (character === '"') out += '\\"';
        else if (character === "\n") out += "\\n";
        else if (character === "\r") out += "\\r";
        else if (character === "\t") out += "\\t";
        else if (character === "\b") out += "\\b";
        else if (character === "\f") out += "\\f";
        else if (code < 32 || code === 127) out += `\\${String(code).padStart(3, "0")}`;
        else out += character;
    }
    return `${out}"`;
}

function luaValue(value) {
    if (typeof value === "string") return luaString(value);
    if (typeof value === "number") return String(value);
    if (typeof value === "boolean") return value ? "true" : "false";
    throw new Error(`unsupported output value ${typeof value}`);
}

function serializeEcho(echo) {
    const locked = echo.locked ? ", locked = true" : "";
    return `{ spellId = ${echo.spellId}, quality = ${echo.quality}, stacks = ${echo.stacks}${locked} }`;
}

function serializeBuild(build) {
    const lines = ["{"];
    for (const field of BUILD_FIELD_ORDER) {
        if (!own(build, field)) continue;
        if (field === "echoes") {
            lines.push("            echoes = {");
            for (const echo of build.echoes) {
                lines.push(`                ${serializeEcho(echo)},`);
            }
            lines.push("            },");
        } else {
            lines.push(`            ${field} = ${luaValue(build[field])},`);
        }
    }
    lines.push("        }");
    return lines.join("\n");
}

function serializeCatalog(builds, metadata) {
    const exclusionKeys = Object.keys(metadata.excluded).sort();
    const lines = [
        "-- Nexus: immutable build catalog generated from validated community data.",
        "-- Do not edit by hand; use tools/export-bundled-builds.js.",
        "",
        "Nexus = Nexus or {}",
        "",
        "Nexus.BundledBuilds = {",
        "    schemaVersion = 1,",
        `    catalogVersion = ${luaString(metadata.catalogVersion)},`,
        `    sourceVersion = ${luaString(metadata.sourceVersion)},`,
        `    generatedAt = ${metadata.generatedAt},`,
        "    generation = {",
        `        sourceBytes = ${metadata.sourceBytes},`,
        `        sourceRows = ${metadata.sourceRows},`,
        `        included = ${metadata.included},`,
        `        prunableBaselineRows = ${metadata.prunableBaselineRows},`,
        `        locallyMarkedIncluded = ${metadata.locallyMarkedIncluded},`,
        `        excludedTotal = ${metadata.excludedTotal},`,
        `        echoRows = ${metadata.echoRows},`,
        "        excluded = {",
    ];
    for (const key of exclusionKeys) {
        lines.push(`            ${key} = ${metadata.excluded[key]},`);
    }
    lines.push("        },", "    },", "    builds = {");
    for (const build of builds) {
        lines.push(`        [${luaString(build.id)}] = ${serializeBuild(build)},`);
    }
    lines.push("    },", "}", "");
    return lines.join("\n");
}

function generate(sourceText, options = {}) {
    const sourceVersion = String(options.sourceVersion || "1.19.4");
    const rows = parseCommunityBuilds(sourceText, options.parser);
    const ids = Object.keys(rows).sort();
    const builds = [];
    const excluded = Object.create(null);
    let generatedAt = 0;
    let echoRows = 0;
    let locallyMarkedIncluded = 0;
    for (const id of ids) {
        const result = normalizeBuild(id, rows[id]);
        if (result.error) {
            excluded[result.error] = (excluded[result.error] || 0) + 1;
        } else {
            builds.push(result.build);
            if (result.localMarker) locallyMarkedIncluded += 1;
            generatedAt = Math.max(generatedAt, result.build.lastModified);
            echoRows += result.build.echoes.length;
        }
    }
    const digestInput = JSON.stringify(builds);
    const contentSha256 = crypto.createHash("sha256").update(digestInput).digest("hex");
    const metadata = {
        sourceVersion,
        catalogVersion: `${sourceVersion}-${contentSha256.slice(0, 12)}`,
        generatedAt,
        sourceBytes: Buffer.byteLength(sourceText, "utf8"),
        sourceRows: ids.length,
        included: builds.length,
        prunableBaselineRows: builds.length - locallyMarkedIncluded,
        locallyMarkedIncluded,
        excludedTotal: ids.length - builds.length,
        echoRows,
        excluded,
        contentSha256,
    };
    const output = serializeCatalog(builds, metadata);
    return { builds, metadata, output };
}

function writeFile(target, content) {
    fs.mkdirSync(path.dirname(path.resolve(target)), { recursive: true });
    fs.writeFileSync(target, content, "utf8");
}

function main(argv = process.argv.slice(2)) {
    const args = parseArgs(argv);
    if (args.help) {
        process.stdout.write(`${usage()}\n`);
        return 0;
    }
    if (!args.input || !args.output || !args.report) throw new Error(usage());
    const sourceText = fs.readFileSync(args.input, "utf8");
    const result = generate(sourceText, { sourceVersion: args.sourceVersion });
    writeFile(args.output, result.output);
    const outputSha256 = crypto.createHash("sha256").update(result.output).digest("hex");
    const report = {
        schemaVersion: 1,
        sourceVersion: result.metadata.sourceVersion,
        catalogVersion: result.metadata.catalogVersion,
        sourceBytes: result.metadata.sourceBytes,
        sourceRows: result.metadata.sourceRows,
        included: result.metadata.included,
        prunableBaselineRows: result.metadata.prunableBaselineRows,
        locallyMarkedIncluded: result.metadata.locallyMarkedIncluded,
        excludedTotal: result.metadata.excludedTotal,
        echoRows: result.metadata.echoRows,
        generatedAt: result.metadata.generatedAt,
        excluded: result.metadata.excluded,
        contentSha256: result.metadata.contentSha256,
        outputSha256,
    };
    writeFile(args.report, `${JSON.stringify(report, null, 2)}\n`);
    process.stdout.write(`${JSON.stringify(report)}\n`);
    return 0;
}

module.exports = {
    canonicalFingerprint,
    djb2,
    generate,
    normalizeBuild,
    parseCommunityBuilds,
    parseNexusDb,
};

if (require.main === module) {
    try {
        process.exitCode = main();
    } catch (error) {
        process.stderr.write(`export-bundled-builds: ${error.message}\n`);
        process.exitCode = 1;
    }
}
