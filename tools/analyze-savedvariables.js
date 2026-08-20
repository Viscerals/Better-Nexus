#!/usr/bin/env node
"use strict";

// Aggregate-only, read-only Nexus SavedVariables analyzer. It never evaluates
// Lua, writes the input, emits record contents, or performs a migration.

const fs = require("fs");
const path = require("path");
const { parseNexusDb } = require("./export-bundled-builds.js");

function parseArgs(argv) {
    const args = {};
    for (let index = 0; index < argv.length; index += 1) {
        const arg = argv[index];
        if (arg === "--input") args.input = argv[++index];
        else if (arg === "--help" || arg === "-h") args.help = true;
        else throw new Error(`unknown argument: ${arg}`);
    }
    return args;
}

function usage() {
    return "Usage: node tools/analyze-savedvariables.js --input <Nexus.lua>";
}

function own(value, key) {
    return Object.prototype.hasOwnProperty.call(value || {}, key);
}

function objectList(value) {
    if (!value || typeof value !== "object" || Array.isArray(value)) return null;
    const keys = Object.keys(value);
    if (keys.length === 0) return [];
    if (!keys.every((key) => /^[1-9]\d*$/.test(key))) return null;
    const indices = keys.map(Number).sort((left, right) => left - right);
    if (indices.some((valueAt, index) => valueAt !== index + 1)) return null;
    return indices.map((index) => value[String(index)]);
}

function finiteInteger(value, minimum, maximum) {
    const number = Number(value);
    return Number.isFinite(number) && Math.floor(number) === number
        && number >= minimum && number <= maximum ? number : null;
}

function luaTruthy(value) {
    return value !== false && value != null;
}

function luaOr(...values) {
    for (const value of values) {
        if (luaTruthy(value)) return value;
    }
    return values[values.length - 1];
}

function luaNumber(value) {
    if (typeof value === "number") return Number.isFinite(value) ? value : null;
    if (typeof value !== "string" || value.trim() === "") return null;
    const number = Number(value);
    return Number.isFinite(number) ? number : null;
}

function canonical(source, forceLocked = false) {
    const sourceRows = objectList(source);
    if (!sourceRows || sourceRows.length < 1 || sourceRows.length > 256) {
        return { error: "malformed" };
    }
    const grouped = new Map();
    let total = 0;
    for (const echo of sourceRows) {
        if (!echo || typeof echo !== "object") return { error: "malformed" };
        const spellId = finiteInteger(luaOr(echo.spellId, echo.id),
            1, 2147483647);
        const quality = finiteInteger(luaOr(echo.quality, 0),
            0, 2147483647);
        const stacks = finiteInteger(luaOr(
            echo.stacks, echo.count, echo.stack, 1), 1, 10000);
        if (spellId == null || quality == null || stacks == null) {
            return { error: "malformed" };
        }
        total += stacks;
        if (total > 10000) return { error: "malformed" };
        const locked = forceLocked || luaTruthy(echo.locked);
        const groupKey = `${spellId}:${quality}:${locked ? 1 : 0}`;
        const existing = grouped.get(groupKey);
        if (existing) {
            existing.stacks += stacks;
            if (existing.stacks > 10000) return { error: "malformed" };
        } else {
            grouped.set(groupKey, {
                spellId, quality, stacks, ...(locked ? { locked: true } : {}),
            });
        }
    }
    const rows = [...grouped.values()].sort((left, right) =>
        left.spellId - right.spellId || left.quality - right.quality
        || Number(Boolean(left.locked)) - Number(Boolean(right.locked))
        || left.stacks - right.stacks);
    const key = `v1|${rows.map((row) => [row.spellId, row.quality, row.stacks,
        row.locked ? 1 : 0].join(":")).join("|")}`;
    return { key, rows, sourceRows };
}

function dpsRows(rows, includeLocked) {
    const counts = new Map();
    for (const row of rows || []) {
        if (includeLocked || !row.locked) {
            counts.set(row.spellId, (counts.get(row.spellId) || 0) + row.stacks);
        }
    }
    return [...counts.keys()].sort((left, right) => left - right)
        .map((spellId) => ({ spellId, count: counts.get(spellId) }));
}

function loadoutFingerprint(rows) {
    return dpsRows(rows, false)
        .map((row) => `${row.spellId}x${row.count}`).join(",");
}

function deepEqual(left, right) {
    if (left === right) return true;
    if (!left || !right || typeof left !== "object" || typeof right !== "object") {
        return false;
    }
    const leftKeys = Object.keys(left).sort();
    const rightKeys = Object.keys(right).sort();
    if (leftKeys.length !== rightKeys.length
        || leftKeys.some((key, index) => key !== rightKeys[index])) return false;
    return leftKeys.every((key) => deepEqual(left[key], right[key]));
}

function count(value) {
    return value && typeof value === "object" ? Object.keys(value).length : 0;
}

function analyze(sourceText, inputPath) {
    const database = parseNexusDb(sourceText);
    const builds = database.communityBuilds && typeof database.communityBuilds === "object"
        ? database.communityBuilds : {};
    const pool = database.loadoutEvidence && database.loadoutEvidence.entries
        && typeof database.loadoutEvidence.entries === "object"
        ? database.loadoutEvidence.entries : {};
    const metrics = {
        schemaVersion: 1,
        readOnly: true,
        sourcePath: path.resolve(inputPath),
        sourceBytes: Buffer.byteLength(sourceText, "utf8"),
        builds: count(builds), autoPages: 0, dpsRows: 0,
        inlineArrays: 0, inlineEchoRows: 0,
        pooledEntries: count(pool), pooledEchoRows: 0,
        pooledReferences: 0, missingReferences: 0,
        uniqueCanonicalFingerprints: 0,
        compactableArrays: 0, retainedInlineArrays: 0,
        projectedRetainedInlineEchoRows: 0,
        projectedReachablePoolEntries: 0,
        projectedPooledEchoRows: 0,
        projectedStoredEchoRows: 0,
        duplicateEchoRowsRemoved: 0,
        recordCountsUnchanged: true,
        conflicts: {
            malformed: 0, referenceMismatch: 0,
            semanticFingerprintMismatch: 0, corruptPoolEntry: 0,
            storedEvidenceCollision: 0,
        },
    };
    const projectedReferences = new Set();
    const canonicalRows = new Map();
    const corruptPoolKeys = new Set();
    const poolRowCounts = new Map();

    for (const [key, raw] of Object.entries(pool)) {
        const rawRows = objectList(raw);
        const rawRowCount = rawRows ? rawRows.length : 0;
        poolRowCounts.set(key, rawRowCount);
        metrics.pooledEchoRows += rawRowCount;
        const normalized = canonical(raw);
        if (normalized.error || normalized.key !== key) {
            metrics.conflicts.corruptPoolEntry += 1;
            corruptPoolKeys.add(key);
        } else {
            canonicalRows.set(key, normalized.rows);
        }
    }

    function consider(record, field, referenceField, style, forceLocked = false) {
        if (!record || typeof record !== "object") return;
        const raw = record[field];
        const reference = record[referenceField];
        if (typeof reference === "string" && reference) {
            metrics.pooledReferences += 1;
            projectedReferences.add(reference);
            if (!own(pool, reference)) metrics.missingReferences += 1;
        }
        if (!raw || typeof raw !== "object") return;
        metrics.inlineArrays += 1;
        const sourceRows = objectList(raw);
        metrics.inlineEchoRows += sourceRows ? sourceRows.length : 0;
        const normalized = canonical(raw, forceLocked);
        if (normalized.error) {
            metrics.conflicts.malformed += 1;
            metrics.retainedInlineArrays += 1;
            metrics.projectedRetainedInlineEchoRows += sourceRows ? sourceRows.length : 0;
            return;
        }
        let conflict = false;
        if (corruptPoolKeys.has(normalized.key)) {
            metrics.conflicts.storedEvidenceCollision += 1;
            conflict = true;
        } else {
            canonicalRows.set(normalized.key, normalized.rows);
        }
        if (typeof reference === "string" && reference && reference !== normalized.key) {
            metrics.conflicts.referenceMismatch += 1;
            conflict = true;
        }
        if (field === "echoes" && typeof record.fingerprint === "string"
            && record.fingerprint && !record.fingerprint.startsWith("@")
            && record.fingerprint !== loadoutFingerprint(normalized.rows)) {
            metrics.conflicts.semanticFingerprintMismatch += 1;
            conflict = true;
        }
        const hydrated = style === "build" ? normalized.rows
            : dpsRows(normalized.rows, forceLocked);
        if (conflict || !deepEqual(sourceRows, hydrated)) {
            metrics.retainedInlineArrays += 1;
            metrics.projectedRetainedInlineEchoRows += sourceRows.length;
            return;
        }
        metrics.compactableArrays += 1;
        projectedReferences.add(normalized.key);
    }

    for (const build of Object.values(builds)) {
        if (build && luaTruthy(build.autoDps)) metrics.autoPages += 1;
        consider(build, "echoes", "evidenceKey", "build", false);
    }

    const seen = new Set();
    function walkDps(value) {
        if (!value || typeof value !== "object" || seen.has(value)) return;
        seen.add(value);
        if (luaNumber(value.dps) != null) {
            metrics.dpsRows += 1;
            consider(value, "echoes", "evidenceKey", "dps", false);
            consider(value, "lockedEchoes", "lockedEvidenceKey", "dps", true);
        }
        for (const [key, child] of Object.entries(value)) {
            if (key !== "echoes" && key !== "lockedEchoes") walkDps(child);
        }
    }
    walkDps(database.dpsCapture || {});

    const referenceSeen = new Set();
    function scanReferences(value) {
        if (!value || typeof value !== "object" || value === pool
            || referenceSeen.has(value)) return;
        referenceSeen.add(value);
        for (const [key, child] of Object.entries(value)) {
            if ((key === "evidenceKey" || key === "lockedEvidenceKey")
                && typeof child === "string") projectedReferences.add(child);
            else scanReferences(child);
        }
    }
    scanReferences(database);

    let projectedPoolRows = 0;
    for (const key of projectedReferences) {
        if (own(pool, key)) {
            projectedPoolRows += poolRowCounts.get(key) || 0;
        } else {
            const rows = canonicalRows.get(key);
            if (rows) projectedPoolRows += rows.length;
        }
    }
    metrics.uniqueCanonicalFingerprints = canonicalRows.size;
    metrics.projectedReachablePoolEntries = [...projectedReferences]
        .filter((key) => own(pool, key) || canonicalRows.has(key)).length;
    metrics.projectedPooledEchoRows = projectedPoolRows;
    metrics.projectedStoredEchoRows = metrics.projectedRetainedInlineEchoRows
        + projectedPoolRows;
    metrics.duplicateEchoRowsRemoved = Math.max(0,
        metrics.inlineEchoRows + metrics.pooledEchoRows
        - metrics.projectedStoredEchoRows);
    metrics.conflicts.total = Object.values(metrics.conflicts)
        .reduce((sum, value) => sum + value, 0);
    return metrics;
}

function main(argv = process.argv.slice(2)) {
    const args = parseArgs(argv);
    if (args.help) {
        process.stdout.write(`${usage()}\n`);
        return;
    }
    if (!args.input) throw new Error(usage());
    const sourceText = fs.readFileSync(args.input, "utf8");
    process.stdout.write(`${JSON.stringify(analyze(sourceText, args.input), null, 2)}\n`);
}

module.exports = { analyze, canonical };

if (require.main === module) {
    try {
        main();
    } catch (error) {
        process.stderr.write(`analyze-savedvariables: ${error.message}\n`);
        process.exitCode = 1;
    }
}
