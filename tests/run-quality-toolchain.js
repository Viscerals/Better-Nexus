"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const root = path.resolve(__dirname, "..");
const manifest = JSON.parse(fs.readFileSync(path.join(root, "package.json"), "utf8"));
const lock = JSON.parse(fs.readFileSync(path.join(root, "package-lock.json"), "utf8"));

assert.strictEqual(manifest.dependencies.fengari, "0.1.5");
assert.strictEqual(manifest.dependencies.luaparse, "0.3.1");
assert.strictEqual(lock.lockfileVersion, 3);
assert.strictEqual(lock.packages[""].dependencies.fengari, "0.1.5");
assert.strictEqual(lock.packages[""].dependencies.luaparse, "0.3.1");
assert.strictEqual(require("fengari/package.json").version, "0.1.5");
assert.strictEqual(require("luaparse/package.json").version, "0.3.1");

function run(relativeScript, args) {
    const result = spawnSync(process.execPath, [path.join(root, relativeScript), ...args], {
        cwd: root,
        encoding: "utf8",
    });
    assert.strictEqual(result.status, 0,
        `${relativeScript} failed:\n${result.stdout}\n${result.stderr}`);
    return result.stdout.trim();
}

const parseOutput = run("tools/parse-lua51.js", [".", "--tests"]);
assert.match(parseOutput, /^Lua 5\.1 parse: \d+ passed, 0 failed$/);
const integrationOutput = run("tools/run-lua.js", ["tests/run_integration.lua"]);
assert.match(integrationOutput, /checks=70 failures=0/);

const suitePlan = JSON.parse(run("tools/Run-LuaSuite.js", ["--list"]));
assert(suitePlan.runnable.includes("tests/run_integration.lua"));
assert.deepStrictEqual(suitePlan.manual, [{
    path: "tests/run_legacy_backup_smoke.lua",
    reason: "requires an explicitly authorized SavedVariables backup path",
}]);
assert.strictEqual(suitePlan.discovered,
    suitePlan.runnable.length + suitePlan.manual.length);

console.log(`quality toolchain: exact dependencies; ${parseOutput}; integration runner -- OK`);
