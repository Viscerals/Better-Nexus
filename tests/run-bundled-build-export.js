"use strict";

const assert = require("assert");
const exporter = require("../tools/export-bundled-builds.js");

const fixture = `NexusDB = {
    ["settings"] = { ["accountName"] = "secret" },
    ["dpsCapture"] = { ["personalBest"] = { ["private"] = true } },
    ["communityBuilds"] = {
        ["good"] = {
            ["id"] = "good", ["title"] = "Good", ["description"] = "D — café",
            ["author"] = "Alice", ["ownerKey"] = "alice@realm",
            ["class"] = "MAGE", ["postedAt"] = 10, ["lastModified"] = 11,
            ["isMine"] = true, ["_nexusBestDps"] = 123,
            ["fingerprint"] = "100x2,101x1", ["echoCount"] = 3,
            ["echoes"] = {
                { ["spellId"] = 101, ["quality"] = 0, ["stacks"] = 1 },
                { ["spellId"] = 100, ["quality"] = 2, ["stacks"] = 2 },
            },
        },
        ["legacy"] = {
            ["id"] = "legacy", ["title"] = "Legacy", ["description"] = "D",
            ["author"] = "Historic", ["class"] = "MAGE",
            ["postedAt"] = 9, ["lastModified"] = 9,
            ["legacyRecovered"] = true,
            ["legacyOwnership"] = "unverified", ["legacySource"] = "relay",
            ["fingerprint"] = "105x1", ["echoCount"] = 1,
            ["echoes"] = { { ["spellId"] = 105, ["stacks"] = 1 } },
        },
        ["saved-local"] = {
            ["id"] = "saved-local", ["title"] = "Local", ["author"] = "Me",
            ["class"] = "MAGE", ["postedAt"] = 1, ["lastModified"] = 1,
            ["importedSavedBuild"] = true, ["fingerprint"] = "100x1",
            ["echoes"] = { { ["spellId"] = 100, ["stacks"] = 1 } },
        },
        ["incomplete"] = {
            ["id"] = "incomplete", ["title"] = "Missing", ["author"] = "Bob",
            ["class"] = "ROGUE", ["postedAt"] = 1, ["lastModified"] = 1,
            ["fingerprint"] = "@deadbeef", ["echoes"] = {},
        },
        ["badfp"] = {
            ["id"] = "badfp", ["title"] = "Bad", ["author"] = "Bob",
            ["class"] = "ROGUE", ["postedAt"] = 1, ["lastModified"] = 1,
            ["fingerprint"] = "wrong", ["echoes"] = {
                { ["spellId"] = 102, ["stacks"] = 1 },
            },
        },
        ["gone"] = {
            ["id"] = "gone", ["title"] = "Gone", ["author"] = "Bob",
            ["class"] = "ROGUE", ["postedAt"] = 1, ["lastModified"] = 1,
            ["tombstoned"] = true, ["fingerprint"] = "103x1",
            ["echoes"] = { { ["spellId"] = 103, ["stacks"] = 1 } },
        },
    },
}`;

const first = exporter.generate(fixture, { sourceVersion: "test" });
const second = exporter.generate(fixture, { sourceVersion: "test" });
assert.strictEqual(first.output, second.output, "same snapshot was not byte deterministic");
assert.strictEqual(first.metadata.included, 2);
assert.strictEqual(first.metadata.prunableBaselineRows, 1);
assert.strictEqual(first.metadata.locallyMarkedIncluded, 1);
assert.strictEqual(first.metadata.excludedTotal, 4);
assert.strictEqual(first.metadata.excluded.personalSavedLoadout, 1);
assert.strictEqual(first.metadata.excluded.incompleteLoadout, 1);
assert.strictEqual(first.metadata.excluded.invalidFingerprint, 1);
assert.strictEqual(first.metadata.excluded.tombstoned, 1);
assert.strictEqual(first.builds[0].id, "good");
assert.strictEqual(first.builds[0].fingerprint, "100x2,101x1");
assert.strictEqual(first.builds[0].echoes[0].spellId, 100,
    "Echo rows were not deterministically sorted");
assert.strictEqual(first.builds[1].id, "legacy");
assert.strictEqual(first.builds[1].legacyRecovered, true);
assert.strictEqual(first.builds[1].legacyOwnership, "unverified");
assert.strictEqual(first.builds[1].legacySource, "relay",
    "future exports erased recovered source/authority limitations");
assert(first.output.includes("D — café"), "Unicode text did not round-trip");
for (const forbidden of ["accountName", "personalBest", "isMine",
    "importedSavedBuild", "_nexusBestDps", "destinationWishlistName"]) {
    assert(!first.output.includes(forbidden), `export leaked ${forbidden}`);
}

const duplicate = `NexusDB = { ["communityBuilds"] = {
    ["dup"] = { ["id"] = "dup" }, ["dup"] = { ["id"] = "dup" },
} }`;
assert.throws(() => exporter.generate(duplicate, { sourceVersion: "test" }),
    /duplicate Lua table key dup/, "duplicate build IDs were not rejected");

const zeroStack = `NexusDB = { ["communityBuilds"] = {
    ["zero"] = {
        ["id"] = "zero", ["title"] = "Zero", ["author"] = "Alice",
        ["class"] = "MAGE", ["postedAt"] = 1, ["lastModified"] = 1,
        ["fingerprint"] = "104x1", ["echoes"] = {
            { ["spellId"] = 104, ["quality"] = 0, ["stacks"] = 0 },
        },
    },
} }`;
const zeroResult = exporter.generate(zeroStack, { sourceVersion: "test" });
assert.strictEqual(zeroResult.metadata.included, 0,
    "zero-stack Echo was silently defaulted to one");
assert.strictEqual(zeroResult.metadata.excluded.malformedEcho, 1,
    "zero-stack Echo did not report malformedEcho");

assert.throws(() => exporter.generate(`${fixture}\nNexusDB = {}`, {
    sourceVersion: "test",
}), /expected exactly one literal NexusDB table assignment/,
"extra top-level NexusDB assignment was ignored");

console.log("bundled build exporter determinism and exclusion policy -- OK");
