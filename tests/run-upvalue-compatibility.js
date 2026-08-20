"use strict";

const assert = require("assert");
const path = require("path");
const {
    MAX_UPVALUES,
    auditSource,
    auditToc,
} = require("../tools/check-lua51-upvalues");

function capturedSource(count, includeGlobal) {
    const names = Array.from({ length: count }, (_, index) => `value${index + 1}`);
    const values = names.map((_, index) => String(index + 1));
    const returned = includeGlobal ? ["print", ...names] : names;
    return `local ${names.join(",")} = ${values.join(",")}\n`
        + `return function() return ${returned.join(",")} end\n`;
}

function innerFunction(source) {
    const rows = auditSource(source, "generated-boundary.lua");
    return rows.find((row) => row.depth === 1);
}

const atLimit = innerFunction(capturedSource(MAX_UPVALUES, true));
assert.strictEqual(atLimit.count, 60,
    "Lua 5.3 _ENV capture was not excluded from the Lua 5.1 count");
assert.strictEqual(atLimit.overLimit, false,
    "exactly 60 upvalues must remain compatible");

const aboveLimit = innerFunction(capturedSource(MAX_UPVALUES + 1, false));
assert.strictEqual(aboveLimit.count, 61,
    "generated 61-upvalue boundary was not counted exactly");
assert.strictEqual(aboveLimit.overLimit, true,
    "61 upvalues must fail the WoW 3.3.5a compatibility gate");

const root = path.resolve(__dirname, "..");
const toc = auditToc(root, "Nexus.toc");
assert.strictEqual(toc.fileCount, 68,
    "compatibility gate did not cover every current TOC Lua entry");
assert(toc.functionCount > toc.fileCount,
    "compatibility gate did not inspect nested TOC-loaded functions");
const step = toc.functions.find((row) =>
    row.file === "core/AutomationRuntime.lua" && row.name === "Step");
assert(step, "compatibility gate did not identify AutomationRuntime.Step");
assert(step.count <= toc.productionTarget,
    `AutomationRuntime.Step lost its production margin: ${step.count}`);
const reviewedMarginExceptions = toc.nearLimit
    .map((row) => `${row.file}:${row.name}=${row.count}`)
    .sort();
assert.deepStrictEqual(reviewedMarginExceptions, [
    "ui/Panel.lua:EnsureFrame=60",
], "new or changed production-margin exception requires explicit review");

console.log(`upvalue boundary: 60 pass / 61 fail; TOC files=${toc.fileCount} `
    + `functions=${toc.functionCount} max=${toc.highest.count} `
    + `${toc.highest.file}:${toc.highest.line} ${toc.highest.name}; `
    + `AutomationRuntime.Step=${step.count}`);
