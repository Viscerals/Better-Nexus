"use strict";

const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const root = path.resolve(__dirname, "..");
const runner = path.join(root, "tools", "run-lua.js");
const manualTests = new Map([
    ["run_legacy_backup_smoke.lua",
        "requires an explicitly authorized SavedVariables backup path"],
]);
const discovered = fs.readdirSync(path.join(root, "tests"))
    .filter((name) => /^run_.*\.lua$/.test(name))
    .sort();
const tests = discovered.filter((name) => !manualTests.has(name));
const failures = [];

if (process.argv.includes("--list")) {
    process.stdout.write(`${JSON.stringify({
        discovered: discovered.length,
        runnable: tests.map((name) => `tests/${name}`),
        manual: [...manualTests.entries()].map(([name, reason]) => ({
            path: `tests/${name}`,
            reason,
        })),
    })}\n`);
    process.exit(0);
}

for (const name of tests) {
    const relative = `tests/${name}`;
    const result = spawnSync(process.execPath, [runner, relative], {
        cwd: root,
        encoding: "utf8",
    });
    process.stdout.write(`== ${relative} ==\n${result.stdout || ""}`);
    if (result.stderr) process.stderr.write(result.stderr);
    if (result.status !== 0) failures.push(`${relative}: exit ${result.status}`);
}

for (const failure of failures) process.stderr.write(`${failure}\n`);
process.stdout.write(`Lua suite: ${tests.length - failures.length}/${tests.length} passed\n`);
for (const [name, reason] of manualTests) {
    process.stdout.write(`Lua suite manual skip: tests/${name} -- ${reason}\n`);
}
process.exit(failures.length === 0 ? 0 : 1);
