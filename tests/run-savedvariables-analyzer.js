"use strict";

const assert = require("assert");
const { analyze } = require("../tools/analyze-savedvariables.js");
const { canonical } = require("../tools/analyze-savedvariables.js");

const source = `NexusDB = {
  ["communityBuilds"] = {
    ["a"] = { ["id"] = "a", ["autoDps"] = true,
      ["fingerprint"] = "100x2,101x1", ["echoes"] = {
        { ["spellId"] = 100, ["quality"] = 3, ["stacks"] = 2 },
        { ["spellId"] = 101, ["quality"] = 2, ["stacks"] = 1 },
      },
    },
    ["b"] = { ["id"] = "b", ["fingerprint"] = "100x2,101x1",
      ["echoes"] = {
        { ["spellId"] = 100, ["quality"] = 3, ["stacks"] = 2 },
        { ["spellId"] = 101, ["quality"] = 2, ["stacks"] = 1 },
      },
    },
    ["bad"] = { ["id"] = "bad", ["echoes"] = {
      { ["spellId"] = 0, ["stacks"] = 1 },
    } },
  },
  ["dpsCapture"] = { ["characterBest"] = { ["dummy"] = {
    ["peer"] = { ["dps"] = 2000000, ["fingerprint"] = "200x1",
      ["echoes"] = { { ["spellId"] = 200, ["count"] = 1 } },
    },
  } } },
}`;

const report = analyze(source, "fixture-Nexus.lua");
assert.strictEqual(report.readOnly, true);
assert.strictEqual(report.builds, 3);
assert.strictEqual(report.autoPages, 1);
assert.strictEqual(report.dpsRows, 1);
assert.strictEqual(report.inlineArrays, 4);
assert.strictEqual(report.compactableArrays, 3);
assert.strictEqual(report.retainedInlineArrays, 1);
assert.strictEqual(report.conflicts.malformed, 1);
assert(report.duplicateEchoRowsRemoved > 0);
assert(report.projectedStoredEchoRows < report.inlineEchoRows);

// Analyzer semantics must match Lua 5.1: only nil/false are false, so numeric
// zero is a truthy legacy locked marker and a truthy automatic-page flag.
const zeroLocked = canonical({
    "1": { spellId: 300, quality: 3, stacks: 1, locked: 0 },
});
assert.strictEqual(zeroLocked.rows[0].locked, true);
const zeroTruthSource = `NexusDB = { ["communityBuilds"] = {
  ["zero"] = { ["autoDps"] = 0, ["echoes"] = {
    { ["spellId"] = 300, ["quality"] = 3, ["stacks"] = 1,
      ["locked"] = 0 },
  } },
} }`;
assert.strictEqual(analyze(zeroTruthSource, "zero.lua").autoPages, 1);

const collisionSource = `NexusDB = {
  ["loadoutEvidence"] = { ["schemaVersion"] = 1, ["entries"] = {
    ["v1|400:3:1:0"] = {
      { ["spellId"] = 401, ["quality"] = 3, ["stacks"] = 1 },
    },
  } },
  ["communityBuilds"] = { ["collision"] = {
    ["id"] = "collision", ["fingerprint"] = "400x1",
    ["evidenceKey"] = "v1|400:3:1:0", ["echoes"] = {
      { ["spellId"] = 400, ["quality"] = 3, ["stacks"] = 1 },
    },
  } },
}`;
const collision = analyze(collisionSource, "collision.lua");
assert.strictEqual(collision.conflicts.corruptPoolEntry, 1);
assert.strictEqual(collision.conflicts.storedEvidenceCollision, 1);
assert.strictEqual(collision.compactableArrays, 0);
assert.strictEqual(collision.retainedInlineArrays, 1);
assert.strictEqual(collision.projectedReachablePoolEntries, 1);
assert.strictEqual(collision.projectedStoredEchoRows, 2);

console.log("read-only SavedVariables analyzer aggregate projection -- OK");
