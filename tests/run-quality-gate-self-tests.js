"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");
const { normalizeSourcePath } = require("../tools/Test-PackageSource.js");
const { normalize: normalizeSummary } = require("../tools/Write-ValidationSummary.js");

const root = path.resolve(__dirname, "..");
const pwsh = process.platform === "win32" ? "pwsh.exe" : "pwsh";

function runPowerShell(script, args = []) {
    return spawnSync(pwsh, ["-NoProfile", "-File", path.join(root, script), ...args], {
        cwd: root,
        encoding: "utf8",
    });
}

function changedPlan(paths) {
    const quote = (value) => `'${String(value).replace(/'/g, "''")}'`;
    const script = `& ${quote(path.join(root, "tools", "Get-ChangedTestPlan.ps1"))}`
        + ` -Paths @(${paths.map(quote).join(",")})`;
    const result = spawnSync(pwsh, ["-NoProfile", "-Command", script], {
        cwd: root,
        encoding: "utf8",
    });
    assert.strictEqual(result.status, 0, `${result.stdout}\n${result.stderr}`);
    return JSON.parse(result.stdout);
}

function changedPlanInRepository(repository, args = []) {
    const result = runPowerShell("tools/Get-ChangedTestPlan.ps1", [
        "-RepositoryRoot", repository,
        "-MapPath", path.join(root, "tests", "validation-map.json"),
        ...args,
    ]);
    assert.strictEqual(result.status, 0, `${result.stdout}\n${result.stderr}`);
    return JSON.parse(result.stdout);
}

function parseNameStatusFixture(...tokens) {
    const bytes = Buffer.from(`${tokens.join("\0")}\0`, "utf8");
    const quote = (value) => `'${String(value).replace(/'/g, "''")}'`;
    const helper = quote(path.join(root, "tools", "GitPathRecords.ps1"));
    const encoded = bytes.toString("base64");
    const script = `. ${helper}; $bytes = [Convert]::FromBase64String('${encoded}'); `
        + `@(ConvertFrom-GitNameStatusOutput -Bytes $bytes) | ConvertTo-Json -Depth 3`;
    const result = spawnSync(pwsh, ["-NoProfile", "-Command", script], {
        cwd: root,
        encoding: "utf8",
    });
    assert.strictEqual(result.status, 0, `${result.stdout}\n${result.stderr}`);
    const parsed = JSON.parse(result.stdout);
    return Array.isArray(parsed) ? parsed : [parsed];
}

function runGit(repository, args) {
    const result = spawnSync("git", [
        "-c", `safe.directory=${repository.replace(/\\/g, "/")}`,
        ...args,
    ], { cwd: repository, encoding: "utf8" });
    assert.strictEqual(result.status, 0,
        `git ${args.join(" ")} failed:\n${result.stdout}\n${result.stderr}`);
    return result.stdout.trim();
}

function initializeRepository(repository, files) {
    fs.mkdirSync(repository, { recursive: true });
    runGit(repository, ["init", "-b", "main"]);
    runGit(repository, ["config", "user.name", "Quality Gate Self-Test"]);
    runGit(repository, ["config", "user.email", "quality-gate@example.invalid"]);
    for (const [relative, contents] of Object.entries(files)) {
        const target = path.join(repository, ...relative.split("/"));
        fs.mkdirSync(path.dirname(target), { recursive: true });
        fs.writeFileSync(target, contents);
    }
    runGit(repository, ["add", "--all"]);
    runGit(repository, ["commit", "-m", "baseline"]);
    return runGit(repository, ["rev-parse", "HEAD"]);
}

const syncPlan = changedPlan(["core\\Sync.lua"]);
assert.deepStrictEqual(syncPlan.paths, ["core/Sync.lua"]);
assert(syncPlan.groups.includes("sync"));
assert(syncPlan.tests.includes("tests/run_sync_hostile_fuzz.lua"));
assert.strictEqual(syncPlan.full_required, true);

const docsPlan = changedPlan(["README.md", "docs/QUALITY.md"]);
assert.strictEqual(docsPlan.documentation_only, true);
assert.strictEqual(docsPlan.full_required, false);
assert.deepStrictEqual(docsPlan.tests, []);

const toolingPlan = changedPlan(["tools/Invoke-QualityGate.ps1", "package-lock.json"]);
assert(toolingPlan.groups.includes("tooling"));
assert(toolingPlan.tests.includes("tests/run-quality-gate-self-tests.js"));
assert.strictEqual(toolingPlan.full_required, true);

const workflowPlan = changedPlan([".github/workflows/quality-gate.yml"]);
assert.deepStrictEqual(workflowPlan.paths, [".github/workflows/quality-gate.yml"]);
assert(workflowPlan.groups.includes("workflow"));
assert(workflowPlan.groups.includes("security"));
assert(workflowPlan.tests.includes("tests/run-quality-workflow-policy.js"));

for (const policyPath of ["AGENTS.md", "AI_POLICY.md", "SECURITY.md", "LICENSE.md",
    "NOTICE", "CONTRACTS.md", "RELEASE_SECURITY.md", "UPSTREAM.md"]) {
    const policyPlan = changedPlan([policyPath]);
    assert.strictEqual(policyPlan.documentation_only, false,
        `${policyPath} was treated as ordinary documentation`);
    assert.strictEqual(policyPlan.full_required, true,
        `${policyPath} did not require the full quality gate`);
    assert(policyPlan.groups.includes("policy"), `${policyPath} missed policy ownership`);
}

for (const hiddenToolingPath of [".gitleaks.toml", ".luarc.json", ".luacheckrc",
    ".pre-commit-config.yaml"]) {
    const hiddenPlan = changedPlan([hiddenToolingPath]);
    assert.deepStrictEqual(hiddenPlan.paths, [hiddenToolingPath]);
    assert(hiddenPlan.groups.includes("tooling"), `${hiddenToolingPath} missed tooling`);
}
assert(changedPlan([".gitleaks.toml"]).groups.includes("security"));
assert.deepStrictEqual(changedPlan(["./core/Main.lua"]).paths, ["core/Main.lua"]);
assert.deepStrictEqual(changedPlan(["core\\Main.lua"]).paths, ["core/Main.lua"]);
assert.deepStrictEqual(changedPlan([".ai/prompt.md"]).paths, [".ai/prompt.md"]);
const hiddenArtifact = runPowerShell("tools/Test-StagedArtifacts.ps1",
    ["-Mode", "All", ".ai/prompt.md"]);
assert.notStrictEqual(hiddenArtifact.status, 0, "leading-dot artifact path was accepted");

for (const unsafe of ["../Nexus.lua", "/root/Nexus.lua", "C:/Nexus.lua", "a//b.lua"]) {
    assert.throws(() => normalizeSourcePath(unsafe), /unsafe package source path/);
}
assert.strictEqual(normalizeSourcePath("core\\Main.lua"), "core/Main.lua");

const scratch = path.join(root, "build", "quality-gate-self-test");
fs.rmSync(scratch, { recursive: true, force: true });
fs.mkdirSync(path.join(scratch, "logs"), { recursive: true });

function summaryWithResult(result, blocking = true, includeResult = true) {
    const check = {
        id: "matrix-check",
        count: "0/1",
        duration_seconds: 0,
        log: "logs/matrix.log",
        command: "fixture",
        blocking,
    };
    if (includeResult) check.result = result;
    return normalizeSummary({
        schema: 1,
        mode: "Fast",
        head: "fixture",
        duration_seconds: 0,
        checks: [check],
    });
}

assert.strictEqual(summaryWithResult("pass").result, "pass");
assert.strictEqual(summaryWithResult(" PASS ").result, "pass");
for (const result of ["skipped", "unavailable", "fail", "error", "unknown", null]) {
    assert.strictEqual(summaryWithResult(result).result, "fail",
        `blocking ${result} produced aggregate success`);
}
assert.strictEqual(summaryWithResult(undefined, true, false).result, "fail",
    "blocking missing result produced aggregate success");
assert.strictEqual(summaryWithResult("unavailable", false).result, "pass",
    "advisory unavailable incorrectly failed the aggregate");

const deletionRepository = path.join(scratch, "deleted-paths");
const deletedPaths = [
    ".github/workflows/deleted.yml",
    ".gitleaks.toml",
    "core/Deleted.lua",
    "tests/run_deleted.lua",
];
const deletionBase = initializeRepository(deletionRepository, Object.fromEntries(
    deletedPaths.map((relative) => [relative, "return true\n"])));
for (const relative of deletedPaths) {
    fs.rmSync(path.join(deletionRepository, ...relative.split("/")));
}
const workingDeletion = changedPlanInRepository(deletionRepository);
assert.deepStrictEqual(workingDeletion.paths, deletedPaths);
assert.deepStrictEqual(workingDeletion.deleted_paths, deletedPaths);
assert.strictEqual(workingDeletion.full_required, true);
assert(workingDeletion.groups.includes("runtime"));
assert(workingDeletion.groups.includes("workflow"));
assert(workingDeletion.groups.includes("security"));
runGit(deletionRepository, ["add", "--all"]);
const stagedDeletion = changedPlanInRepository(deletionRepository);
assert.deepStrictEqual(stagedDeletion.paths, deletedPaths);
assert.deepStrictEqual(stagedDeletion.deleted_paths, deletedPaths);
runGit(deletionRepository, ["commit", "-m", "delete routed files"]);
const rangeDeletion = changedPlanInRepository(deletionRepository,
    ["-BaseRef", deletionBase]);
assert.deepStrictEqual(rangeDeletion.paths, deletedPaths);
assert.deepStrictEqual(rangeDeletion.deleted_paths, deletedPaths);
const explicitDeletion = changedPlan(deletedPaths);
for (const field of ["paths", "groups", "tests", "full_required", "documentation_only"]) {
    assert.deepStrictEqual(rangeDeletion[field], explicitDeletion[field],
        `explicit/range routing differs for ${field}`);
}

function renamedPlan(name, sourcePath, destinationPath) {
    const repository = path.join(scratch, name);
    const base = initializeRepository(repository, { [sourcePath]: "fixture\n" });
    const destination = path.join(repository, ...destinationPath.split("/"));
    fs.mkdirSync(path.dirname(destination), { recursive: true });
    runGit(repository, ["mv", "-f", sourcePath, destinationPath]);
    runGit(repository, ["commit", "-m", "rename fixture"]);
    return changedPlanInRepository(repository, ["-BaseRef", base]);
}

const runtimeToDocsRename = renamedPlan("runtime-to-docs-rename",
    "core/Renamed.lua", "docs/Renamed.md");
assert.deepStrictEqual(runtimeToDocsRename.paths,
    ["core/Renamed.lua", "docs/Renamed.md"]);
assert.deepStrictEqual(runtimeToDocsRename.deleted_paths, ["core/Renamed.lua"]);
assert(runtimeToDocsRename.groups.includes("runtime"));
assert.strictEqual(runtimeToDocsRename.full_required, true);

const workflowToDocsRename = renamedPlan("workflow-to-docs-rename",
    ".github/workflows/renamed.yml", "docs/workflow-notes.md");
assert(workflowToDocsRename.groups.includes("workflow"));
assert(workflowToDocsRename.groups.includes("security"));
assert.strictEqual(workflowToDocsRename.full_required, true);

const policyToDocsRename = renamedPlan("policy-to-docs-rename",
    "AGENTS.md", "docs/agent-notes.md");
assert(policyToDocsRename.groups.includes("policy"));
assert.strictEqual(policyToDocsRename.full_required, true);

const docsToDocsRename = renamedPlan("docs-to-docs-rename",
    "docs/old name.md", "docs/new name.md");
assert.strictEqual(docsToDocsRename.documentation_only, true);
assert.strictEqual(docsToDocsRename.full_required, false);

const caseOnlyRename = renamedPlan("case-only-rename",
    "docs/Case.md", "docs/case.md");
assert.deepStrictEqual(caseOnlyRename.paths, ["docs/Case.md", "docs/case.md"]);

const copyRepository = path.join(scratch, "copy-with-spaces");
const copyBase = initializeRepository(copyRepository,
    { "core/source with spaces.lua": "return true\n" });
fs.mkdirSync(path.join(copyRepository, "docs"), { recursive: true });
fs.copyFileSync(path.join(copyRepository, "core", "source with spaces.lua"),
    path.join(copyRepository, "docs", "copied notes.md"));
runGit(copyRepository, ["add", "--all"]);
runGit(copyRepository, ["commit", "-m", "copy fixture"]);
const copyPlan = changedPlanInRepository(copyRepository, ["-BaseRef", copyBase]);
assert.deepStrictEqual(copyPlan.paths,
    ["core/source with spaces.lua", "docs/copied notes.md"]);
assert.deepStrictEqual(copyPlan.deleted_paths, []);
assert(copyPlan.groups.includes("runtime"));
assert.strictEqual(copyPlan.full_required, true);

const unusualRecords = parseNameStatusFixture(
    "R100", "core/old\tname.lua", "docs/new\nname.md",
    "C100", "core/source\nname.lua", "docs/copy\tname.md");
assert.deepStrictEqual(unusualRecords.map((record) => record.Path), [
    "core/old\tname.lua", "docs/new\nname.md",
    "core/source\nname.lua", "docs/copy\tname.md",
]);
assert.deepStrictEqual(unusualRecords.map((record) => record.Deleted),
    [true, false, false, false]);

function createDiffRepository(name, nextContents, staged = false) {
    const repository = path.join(scratch, name);
    const base = initializeRepository(repository, { "sample.txt": "clean\n" });
    fs.writeFileSync(path.join(repository, "sample.txt"), nextContents);
    if (staged || nextContents !== "bad working   \n") {
        runGit(repository, ["add", "--all"]);
    }
    if (!staged && nextContents !== "bad working   \n") {
        runGit(repository, ["commit", "-m", "candidate"]);
    }
    return { repository, base };
}

const committedBad = createDiffRepository("committed-bad", "bad committed   \n");
const badRange = runPowerShell("tools/Test-GitDiffCheck.ps1", [
    "-Mode", "Range", "-RepositoryRoot", committedBad.repository,
    "-BaseRef", committedBad.base,
]);
assert.notStrictEqual(badRange.status, 0, "committed whitespace defect was accepted");

const committedClean = createDiffRepository("committed-clean", "clean candidate\n");
const cleanRange = runPowerShell("tools/Test-GitDiffCheck.ps1", [
    "-Mode", "Range", "-RepositoryRoot", committedClean.repository,
    "-BaseRef", committedClean.base,
]);
assert.strictEqual(cleanRange.status, 0, `${cleanRange.stdout}\n${cleanRange.stderr}`);

const workingBad = createDiffRepository("working-bad", "bad working   \n");
const badWorking = runPowerShell("tools/Test-GitDiffCheck.ps1", [
    "-Mode", "Working", "-RepositoryRoot", workingBad.repository,
]);
assert.notStrictEqual(badWorking.status, 0, "working whitespace defect was accepted");

const stagedBad = createDiffRepository("staged-bad", "bad staged   \n", true);
const badStaged = runPowerShell("tools/Test-GitDiffCheck.ps1", [
    "-Mode", "Staged", "-RepositoryRoot", stagedBad.repository,
]);
assert.notStrictEqual(badStaged.status, 0, "staged whitespace defect was accepted");

for (const invalidArgs of [
    ["-Mode", "Range", "-RepositoryRoot", committedClean.repository],
    ["-Mode", "Range", "-RepositoryRoot", committedClean.repository,
        "-BaseRef", "refs/heads/missing"],
]) {
    const invalidRange = runPowerShell("tools/Test-GitDiffCheck.ps1", invalidArgs);
    assert.notStrictEqual(invalidRange.status, 0,
        "missing or invalid BaseRef was accepted");
}
fs.writeFileSync(path.join(scratch, "logs", "a.log"), "SUCCESS-DETAIL-MUST-NOT-LEAK\n");
fs.writeFileSync(path.join(scratch, "logs", "z.log"), "failure detail\n");
const payload = {
    schema: 1,
    mode: "Full",
    head: "abcdef0123456789",
    duration_seconds: 1.25,
    checks: [
        { id: "z-fail", result: "fail", count: "0/1", duration_seconds: 1,
            log: "logs/z.log", command: "node C:\\Users\\Private\\fail.js", blocking: true,
            reason: "command exited 9" },
        { id: "a-pass", result: "pass", count: "1/1", duration_seconds: 0.25,
            log: "logs/a.log", command: "node pass.js", blocking: true },
    ],
};
const payloadPath = path.join(scratch, "payload.json");
fs.writeFileSync(payloadPath, JSON.stringify(payload));
const summaryResult = spawnSync(process.execPath, [
    path.join(root, "tools", "Write-ValidationSummary.js"),
    "--input", payloadPath,
    "--output-dir", scratch,
], { cwd: root, encoding: "utf8" });
assert.strictEqual(summaryResult.status, 0, summaryResult.stderr);
const summary = JSON.parse(fs.readFileSync(path.join(scratch, "summary.json"), "utf8"));
assert.strictEqual(summary.result, "fail");
assert.deepStrictEqual(summary.checks.map((check) => check.id), ["a-pass", "z-fail"]);
assert(summary.checks[1].command.includes("<local-path>"));
const markdown = fs.readFileSync(path.join(scratch, "summary.md"), "utf8");
assert(!markdown.includes("SUCCESS-DETAIL-MUST-NOT-LEAK"));
assert(markdown.includes("logs/z.log"));

if (process.env.BETTER_NEXUS_QUALITY_GATE_ACTIVE !== "1") {
    const multiple = runPowerShell("tools/Invoke-QualityGate.ps1",
        ["-Mode", "Fast", "-SelfTestScenario", "MultipleFailures"]);
    assert.notStrictEqual(multiple.status, 0, "multiple failing checks returned success");
    const multipleSummary = JSON.parse(fs.readFileSync(
        path.join(root, "build", "verify", "summary.json"), "utf8"));
    assert.strictEqual(multipleSummary.failed, 2);
    assert.strictEqual(multipleSummary.passed, 1);
    assert.deepStrictEqual(multipleSummary.checks.map((check) => check.id),
        ["self-fail-a", "self-fail-b", "self-pass"]);

    const unavailable = runPowerShell("tools/Invoke-QualityGate.ps1",
        ["-Mode", "Security", "-SelfTestScenario", "UnavailableTool"]);
    assert.notStrictEqual(unavailable.status, 0, "unavailable blocking tool returned success");
    const unavailableSummary = JSON.parse(fs.readFileSync(
        path.join(root, "build", "verify", "summary.json"), "utf8"));
    assert.strictEqual(unavailableSummary.result, "fail");
    assert.strictEqual(unavailableSummary.unavailable, 1);
    assert.match(unavailableSummary.checks[0].reason, /required tool missing/);

    const deletedFast = runPowerShell("tools/Invoke-QualityGate.ps1",
        ["-Mode", "Fast", "-ChangedPath", "core/DefinitelyDeleted.lua"]);
    assert.strictEqual(deletedFast.status, 0, `${deletedFast.stdout}\n${deletedFast.stderr}`);
    const deletedSummary = JSON.parse(fs.readFileSync(
        path.join(root, "build", "verify", "summary.json"), "utf8"));
    assert(!deletedSummary.checks.some((check) => check.id === "lua-parse-DefinitelyDeleted"),
        "Fast attempted to parse a deleted Lua path");
}

fs.rmSync(scratch, { recursive: true, force: true });
console.log("quality gate self-tests: routing, modes, failures, unavailable tools, compact summaries, ordering, portability, exit status -- OK");
