"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const workflow = fs.readFileSync(path.join(root, ".github/workflows/quality-gate.yml"), "utf8");
const release = fs.readFileSync(path.join(root, ".github/workflows/release-policy.yml"), "utf8")
    .replace(/\r\n?/g, "\n");
const normalLuaRunnerFiles = fs.readdirSync(path.join(root, "tests"))
    .filter((name) => /^run_.*\.lua$/.test(name) && name !== "run_legacy_backup_smoke.lua");

assert.match(workflow, /\non:\s*\n\s+pull_request:\s*\n\s+push:[\s\S]*branches:[\s\S]*- main[\s\S]*workflow_dispatch:/);
assert(!workflow.includes("pull_request_target"));
assert.match(workflow, /permissions:\s*\n\s+contents: read/);
assert.match(workflow, /group: better-nexus-quality-\$\{\{ github\.workflow \}\}-\$\{\{ github\.ref \}\}/);
assert.match(workflow, /cancel-in-progress: true/);
for (const job of ["candidate", "preflight", "fast-quality", "security-quality", "full-quality",
    "package-quality", "quality-gate"]) {
    assert.match(workflow, new RegExp(`^  ${job}:`, "m"), `missing job: ${job}`);
}
const uses = [...workflow.matchAll(/^\s+uses:\s+([^\s]+)$/gm)].map((match) => match[1]);
assert(uses.length > 0);
for (const use of uses) assert.match(use, /^[^@]+@[0-9a-f]{40}$/, `non-immutable action: ${use}`);
assert.strictEqual((workflow.match(/persist-credentials: false/g) || []).length, 5);
assert.strictEqual((workflow.match(/fetch-depth: 0/g) || []).length, 5);
assert.match(workflow, /candidate_sha: \$\{\{ steps\.resolve\.outputs\.candidate_sha \}\}/);
assert.match(workflow, /base_ref: \$\{\{ steps\.resolve\.outputs\.base_ref \}\}/);
assert.strictEqual((workflow.match(/ref: \$\{\{ needs\.(?:candidate|preflight)\.outputs\.candidate_sha \}\}/g) || []).length, 5);
assert.strictEqual((workflow.match(/Verify exact candidate checkout/g) || []).length, 5);
assert.strictEqual((workflow.match(/git rev-parse HEAD/g) || []).length, 5);
for (const mode of ["Fast", "Full", "Security", "Package"]) {
    assert.match(workflow, new RegExp(`Invoke-QualityGate\\.ps1 -Mode ${mode} -BaseRef \\$env:BASE_REF`),
        `${mode} does not inspect the committed base range`);
}
assert.match(workflow, /Get-ChangedTestPlan\.ps1 -BaseRef \$base/,
    "workflow must delegate base-range parsing to the shared path classifier");
const classifyStep = workflow.match(/- name: Classify reviewed paths[\s\S]*?(?=^  fast-quality:)/m)?.[0] || "";
assert.match(classifyStep, /EVENT_NAME: \$\{\{ github\.event_name \}\}/,
    "path classification cannot distinguish push and manual full-forcing events");
assert(!workflow.includes("git diff --name-only"),
    "workflow bypasses the shared binary-safe path classifier");
const fullJob = workflow.match(/^  full-quality:[\s\S]*?(?=^  package-quality:)/m)?.[0] || "";
assert.match(fullJob, /needs: preflight/);
assert(!/^    if:/m.test(fullJob), "complete primary inventory must not be optional");
assert.match(workflow, /\$fullRequired = \$true/);
assert.match(workflow, /quality-gate:[\s\S]*if: always\(\)/);
assert.match(workflow, /quality-gate:[\s\S]*needs: \[preflight, fast-quality, security-quality, full-quality, package-quality\]/);
assert.match(workflow, /PACKAGE_RESULT: \$\{\{ needs\.package-quality\.result \}\}/);
assert.match(workflow, /\$env:PACKAGE_RESULT -ne 'success'/,
    "failed or skipped Package must fail aggregation");
const packageJob = workflow.match(/^  package-quality:[\s\S]*?(?=^  quality-gate:)/m)?.[0] || "";
assert.match(packageJob, /if: failure\(\)[\s\S]*name: package-quality-logs[\s\S]*path: build\/verify\/logs/);
assert(!/inputs\.upload_logs/.test(packageJob),
    "successful Package workflow dispatch can upload evidence");
assert(!/path: .*\.(?:zip|7z|rar)/i.test(packageJob), "Package job uploads a package archive");
assert.match(packageJob, /Verify no package output was retained[\s\S]*Test-Path build\/package-root[\s\S]*-Filter \*\.zip/);
assert.match(workflow, /failure\(\) \|\| \(github\.event_name == 'workflow_dispatch' && inputs\.upload_logs\)/);
assert.strictEqual((workflow.match(/retention-days: 5/g) || []).length, 4);
assert(!/^\s+paths(?:-ignore)?:/m.test(workflow));
for (const job of ["candidate", "release-policy", "lua-regression"]) {
    assert.match(release, new RegExp(`^  ${job}:`, "m"), `missing release job: ${job}`);
}
assert.match(release, /Run-LuaSuite\.js --runtime luajit --timeout-seconds 600/);
assert(!release.includes("--expected-count"), "workflow must use the shared reviewed inventory");
const expected = require("../tools/lua-inventory.json");
assert.deepStrictEqual([...expected.runnable].sort(), normalLuaRunnerFiles.sort().map((name) => `tests/${name}`));
assert.match(release, /candidate_sha: \$\{\{ steps\.resolve\.outputs\.candidate_sha \}\}/);
assert.strictEqual((release.match(/ref: \$\{\{ needs\.candidate\.outputs\.candidate_sha \}\}/g) || []).length, 2);
assert.strictEqual((release.match(/Verify exact candidate checkout/g) || []).length, 2);
assert.strictEqual((release.match(/git rev-parse HEAD/g) || []).length, 2);
assert.strictEqual((release.match(/persist-credentials: false/g) || []).length, 2);
assert(!release.includes("pull_request_target"));
assert.strictEqual((release.match(/Run-LuaSuite\.js --runtime luajit/g) || []).length, 1);
assert(!/luajit tests\/run_/.test(release), "focused fixtures must not duplicate inventory work");
assert.match(release, /historical=6f6204dc9e94b0339f2c9cbacf0c5de8b98a539f/);
assert.match(release, /expected_tree=0d293768d6c7a14d78a9b9ee9b3844d2b9bad3b6/);
assert.match(release, /lua-regression:[\s\S]*timeout-minutes: 15/);
for (const profile of ["Fast", "Full"]) {
    assert.match(workflow, new RegExp(`Invoke-QualityGate\\.ps1 -Mode ${profile} -BaseRef \\$env:BASE_REF -LuaRuntime luajit -BudgetSeconds 1500`));
}
assert.strictEqual((workflow.match(/sudo apt-get install --yes luajit/g) || []).length, 3);
const gate = fs.readFileSync(path.join(root, "tools/Invoke-QualityGate.ps1"), "utf8");
assert.match(gate, /\[string\] \$LuaRuntime = 'luajit'/);
assert.match(gate, /'tools\/Run-LuaSuite.js', '--runtime', \$LuaRuntime, '--timeout-seconds', '600'/);
assert.match(gate, /'pr58-expected-red'[\s\S]*'catalog-authority-expected-red'/);
assert(!gate.includes("'tools/run-lua.js'"), "quality profile silently uses supplementary runtime");
assert(!/continue-on-error/.test(workflow + release));
assert.strictEqual((workflow.match(/if: failure\(\) \|\| cancelled\(\)/g) || []).length, 2);
assert.match(release, /Upload failed or interrupted Lua diagnostics\s+if: \(failure\(\) \|\| cancelled\(\)\) && steps\.diagnostics\.outcome == 'success'/);
assert.strictEqual((workflow.match(/if: \(failure\(\) \|\| cancelled\(\)\) && steps\.diagnostics\.outcome == 'success'/g) || []).length, 2);
for (const source of [workflow, release]) {
    assert.match(source, /Test-ArtifactPathSet -RepositoryRoot \$root -Candidates \$paths -ReadContent/);
    assert.match(source, /Length -gt 1048576 -or \$_.LinkType/);
    assert.match(source, /if \(\$unexpected.Count\) \{ throw/);
}
for (const [name, body, files] of [
    ["fast-quality-logs", workflow, ["build/verify/logs/*.log", "build/verify/progress.json", "build/verify/summary.json", "build/verify/summary.md"]],
    ["full-quality-logs", workflow, ["build/verify/logs/*.log", "build/verify/progress.json", "build/verify/summary.json", "build/verify/summary.md", "build/lua-suite/manifest.json", "build/lua-suite/*.log"]],
    ["luajit-inventory-diagnostics", release, ["build/lua-suite/manifest.json", "build/lua-suite/*.log"]],
]) {
    const paths = body.match(new RegExp(`name: ${name}\\s+path: \\|\\r?\\n([\\s\\S]*?)\\s+retention-days: 5`));
    assert(paths, `missing bounded artifact ${name}`);
    assert.deepStrictEqual(paths[1].trim().split(/\r?\n/).map((line) => line.trim()), files);
}

// Execute the real aggregation expression against absent/cancelled/failed jobs.
// Only its synthetic step-summary file is writable; no workflow is dispatched.
const { spawnSync } = require("child_process");
const os = require("os");
const aggregateBody = workflow.match(/Aggregate required results[\s\S]*?run: \|\r?\n([\s\S]*)$/)?.[1];
assert(aggregateBody, "required aggregation script is missing");
const aggregateScript = aggregateBody.replace(/^          /gm, "");
const aggregateScratch = fs.mkdtempSync(path.join(os.tmpdir(), "nexus-aggregate-"));
try {
    const baseEnvironment = { ...process.env, PREFLIGHT_RESULT: "success", FAST_RESULT: "success",
        SECURITY_RESULT: "success", FULL_RESULT: "success", PACKAGE_RESULT: "success", FULL_REQUIRED: "true",
        GITHUB_STEP_SUMMARY: path.join(aggregateScratch, "summary.md") };
    const runAggregate = (values) => spawnSync(process.platform === "win32" ? "pwsh.exe" : "pwsh",
        ["-NoProfile", "-Command", aggregateScript], {
            encoding: "utf8", timeout: 10000, env: { ...baseEnvironment, ...values },
        });
    assert.strictEqual(runAggregate({}).status, 0);
    for (const job of ["PREFLIGHT_RESULT", "FAST_RESULT", "SECURITY_RESULT", "FULL_RESULT", "PACKAGE_RESULT"]) {
        for (const result of ["failure", "cancelled", "", "skipped"]) {
            assert.notStrictEqual(runAggregate({ [job]: result }).status, 0, `${job}=${result} passed`);
        }
    }
    assert.notStrictEqual(runAggregate({ FULL_REQUIRED: "false", FULL_RESULT: "skipped" }).status, 0,
        "same-candidate primary inventory cannot be skipped");
} finally {
    fs.rmSync(aggregateScratch, { recursive: true, force: true });
}

console.log("quality workflow policy: triggers, permissions, pins, concurrency, jobs, skips, artifacts, release ownership -- OK");
