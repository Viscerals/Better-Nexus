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
assert.match(workflow, /full-quality:[\s\S]*if: needs\.preflight\.outputs\.full_required == 'true'/);
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
const releaseRunnerCount = release.match(/test "\$\{#tests\[@\]\}" -eq (\d+)/);
assert(releaseRunnerCount, "release Lua runner-count guard is missing");
assert.strictEqual(
    Number(releaseRunnerCount[1]),
    normalLuaRunnerFiles.length,
    "release Lua runner-count guard does not match the enumerated normal runner inventory"
);
assert.match(release, /candidate_sha: \$\{\{ steps\.resolve\.outputs\.candidate_sha \}\}/);
assert.strictEqual((release.match(/ref: \$\{\{ needs\.candidate\.outputs\.candidate_sha \}\}/g) || []).length, 2);
assert.strictEqual((release.match(/Verify exact candidate checkout/g) || []).length, 2);
assert.strictEqual((release.match(/git rev-parse HEAD/g) || []).length, 2);
assert.strictEqual((release.match(/persist-credentials: false/g) || []).length, 2);
assert(!release.includes("pull_request_target"));

console.log("quality workflow policy: triggers, permissions, pins, concurrency, jobs, skips, artifacts, release ownership -- OK");
