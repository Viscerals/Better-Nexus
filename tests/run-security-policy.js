"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const root = path.resolve(__dirname, "..");
const pwsh = process.platform === "win32" ? "pwsh.exe" : "pwsh";

function run(script, args) {
    return spawnSync(pwsh, ["-NoProfile", "-File", path.join(root, script), ...args], {
        cwd: root,
        encoding: "utf8",
    });
}

function runGit(repository, args, options = {}) {
    const result = spawnSync("git", [
        "-c", `safe.directory=${repository.replace(/\\/g, "/")}`,
        "-C", repository,
        ...args,
    ], { encoding: "utf8", ...options });
    assert.strictEqual(result.status, 0,
        `git ${args.join(" ")} failed:\n${result.stdout}\n${result.stderr}`);
    return String(result.stdout || "").trim();
}

function initializeRepository(repository) {
    fs.mkdirSync(repository, { recursive: true });
    runGit(repository, ["init", "-b", "main"]);
    runGit(repository, ["config", "user.name", "Artifact Policy Self-Test"]);
    runGit(repository, ["config", "user.email", "artifact-policy@example.invalid"]);
    fs.writeFileSync(path.join(repository, "safe.lua"), "return true\n");
    runGit(repository, ["add", "safe.lua"]);
    runGit(repository, ["commit", "-m", "baseline"]);
}

function stageIndexPath(repository, hostilePath) {
    const hash = runGit(repository, ["hash-object", "-w", "--stdin"],
        { input: "hostile fixture\n" });
    runGit(repository,
        ["update-index", "--add", "--cacheinfo", "100644", hash, hostilePath]);
}

function artifactScan(repository, mode = "Staged", paths = []) {
    return run("tools/Test-StagedArtifacts.ps1",
        ["-RepositoryRoot", repository, "-Mode", mode, ...paths]);
}

const artifact = run("tools/Test-StagedArtifacts.ps1", ["-SelfTest"]);
assert.strictEqual(artifact.status, 0, `${artifact.stdout}\n${artifact.stderr}`);
assert.match(artifact.stdout, /7 rejected \/ 4 allowed/);
const pssaBaseline = run("tests/Test-PSScriptAnalyzerBaseline.ps1", []);
assert.strictEqual(pssaBaseline.status, 0, `${pssaBaseline.stdout}\n${pssaBaseline.stderr}`);
assert.match(pssaBaseline.stdout, /owner\/message drift, case-distinct owners, duplicates, stale and malformed entries -- OK/);
const bootstrapPolicy = run("tests/Test-SecurityBootstrapPolicy.ps1", []);
assert.strictEqual(bootstrapPolicy.status, 0, `${bootstrapPolicy.stdout}\n${bootstrapPolicy.stderr}`);
assert.match(bootstrapPolicy.stdout, /shared download URIs, manifest containment, ZIP\/tar layouts, 8 hostile archives plus link rejection, checksum\/hash lock, failure cleanup -- OK/);

const scratch = path.join(root, "build", "staged-artifact-hostile-tests");
fs.rmSync(scratch, { recursive: true, force: true });
try {
    const hostilePaths = [
        ".codex/context\n.txt",
        ".ai/prompt\tcopy.md",
        ".chatgpt/session log.txt",
        "build/test.zip",
        "BUILD/test.zip",
        "tests/fixtures/sanitized/.codex/context.txt",
        "tests/fixtures/sanitized/build/test.zip",
    ];
    for (const [index, hostilePath] of hostilePaths.entries()) {
        const repository = path.join(scratch, `index-${index}`);
        initializeRepository(repository);
        const cannotRepresentOnWindows = process.platform === "win32"
            && /[\t\r\n]/.test(hostilePath);
        if (!cannotRepresentOnWindows) {
            stageIndexPath(repository, hostilePath);
            const indexed = runGit(repository, ["ls-files", "-z"]);
            assert(indexed.includes(hostilePath),
                `hostile fixture was not written to the Git index: ${JSON.stringify(indexed)}`);
        }
        const staged = artifactScan(repository, "Staged",
            cannotRepresentOnWindows ? [hostilePath] : []);
        assert.notStrictEqual(staged.status, 0,
            `staged hostile path was accepted: ${JSON.stringify(hostilePath)}\n${staged.stdout}\n${staged.stderr}`);
        if (!cannotRepresentOnWindows && (index === 0 || index === 2 || index >= 5)) {
            const tracked = artifactScan(repository, "All");
            assert.notStrictEqual(tracked.status, 0,
                `all-tracked scan accepted hostile path: ${JSON.stringify(hostilePath)}`);
        }
    }

    const forceAddedRepository = path.join(scratch, "force-added");
    initializeRepository(forceAddedRepository);
    fs.writeFileSync(path.join(forceAddedRepository, ".gitignore"), "build/\n");
    fs.mkdirSync(path.join(forceAddedRepository, "build"), { recursive: true });
    fs.writeFileSync(path.join(forceAddedRepository, "build", "forced.zip"), "fixture\n");
    runGit(forceAddedRepository, ["add", ".gitignore"]);
    runGit(forceAddedRepository, ["add", "-f", "build/forced.zip"]);
    assert.notStrictEqual(artifactScan(forceAddedRepository).status, 0,
        "force-added ignored archive was accepted");

    const safeRepository = path.join(scratch, "safe-source");
    initializeRepository(safeRepository);
    fs.writeFileSync(path.join(safeRepository, "safe.lua"), "return false\n");
    runGit(safeRepository, ["add", "safe.lua"]);
    const safeScan = artifactScan(safeRepository);
    assert.strictEqual(safeScan.status, 0, `${safeScan.stdout}\n${safeScan.stderr}`);

    const sanitizedRepository = path.join(scratch, "sanitized-content");
    initializeRepository(sanitizedRepository);
    const sanitizedPath = path.join(sanitizedRepository, "tests", "fixtures", "sanitized", "private-content-example.txt");
    fs.mkdirSync(path.dirname(sanitizedPath), { recursive: true });
    fs.writeFileSync(sanitizedPath, "C:\\Users\\Sanitized\\fixture.txt\n");
    runGit(sanitizedRepository, ["add", "tests/fixtures/sanitized/private-content-example.txt"]);
    const sanitizedScan = artifactScan(sanitizedRepository);
    assert.strictEqual(sanitizedScan.status, 0,
        `sanitized content fixture was rejected: ${sanitizedScan.stdout}\n${sanitizedScan.stderr}`);

    for (const separatorPath of ["build\\test.zip", "BUILD\\test.zip",
        ".codex\\context.txt"]) {
        const separated = artifactScan(safeRepository, "Staged", [separatorPath]);
        assert.notStrictEqual(separated.status, 0,
            `backslash-separated hostile path was accepted: ${separatorPath}`);
    }
}
finally {
    fs.rmSync(scratch, { recursive: true, force: true });
}

const manifest = JSON.parse(fs.readFileSync(path.join(root, "tools/security-tools.json"), "utf8"));
assert.strictEqual(manifest.schema, 2);
for (const tool of ["gitleaks", "actionlint", "zizmor"]) {
    for (const platform of ["windows-x64", "linux-x64"]) {
        const asset = manifest.tools[tool][platform];
        assert.match(asset.url, /^https:\/\/github\.com\//);
        assert.match(asset.sha256, /^[0-9a-f]{64}$/);
        assert(!asset.url.includes("/latest/"));
        assert(["zip", "tar.gz"].includes(asset.archive_type));
        assert.strictEqual(typeof asset.expected_executable_path, "string");
        assert(asset.allowed_top_level.includes(asset.expected_executable_path.split("/")[0]));
    }
}
assert.match(manifest.psscriptanalyzer.sha256, /^[0-9a-f]{64}$/);
assert.match(manifest.psscriptanalyzer.url, /^https:\/\//);
assert.strictEqual(manifest.psscriptanalyzer.archive_type, "zip");
assert(manifest.psscriptanalyzer.allowed_top_level.includes("PSScriptAnalyzer.psd1"));
assert.deepStrictEqual([...manifest.psscriptanalyzer.allowed_top_level].sort(), [
    ".signature.p7s", "LICENSE", "Microsoft.PowerShell.CrossCompatibility.dll",
    "Microsoft.Windows.PowerShell.ScriptAnalyzer.BuiltinRules.dll",
    "Microsoft.Windows.PowerShell.ScriptAnalyzer.dll", "Newtonsoft.Json.dll",
    "PSScriptAnalyzer.nuspec", "PSScriptAnalyzer.psd1", "PSScriptAnalyzer.psm1",
    "PSv7", "README.md", "ScriptAnalyzer.format.ps1xml",
    "ScriptAnalyzer.types.ps1xml", "SECURITY.md", "Settings",
    "ThirdPartyNotices.txt", "[Content_Types].xml", "_rels",
    "compatibility_profiles", "en-US", "package",
].sort());
assert.strictEqual(manifest.pre_commit.packages[0], `pre-commit==${manifest.pre_commit.version}`);
assert(manifest.pre_commit.packages.every((entry) => /^[A-Za-z0-9_-]+==[^=]+$/.test(entry)), "pre-commit dependency is not exact");
assert.strictEqual(manifest.pre_commit.requirements_file, "tools/pre-commit-requirements.txt");
const requirementLines = fs.readFileSync(path.join(root, manifest.pre_commit.requirements_file), "utf8")
    .split(/\r?\n/).map((line) => line.trim()).filter((line) => line && !line.startsWith("#"));
assert.strictEqual(requirementLines.length, manifest.pre_commit.packages.length);
assert(requirementLines.every((line) => /^\S+==\S+(?: --hash=sha256:[0-9a-f]{64})+$/.test(line)),
    "Python distribution lock contains an unhashed requirement");
assert.deepStrictEqual(requirementLines.map((line) => line.split(/\s+/)[0].toLowerCase()).sort(),
    manifest.pre_commit.packages.map((entry) => entry.toLowerCase()).sort());
const securityBootstrap = fs.readFileSync(path.join(root, "tools", "Bootstrap-SecurityTools.ps1"), "utf8");
const securityPolicy = fs.readFileSync(path.join(root, "tools", "SecurityBootstrapPolicy.ps1"), "utf8");
assert.match(securityPolicy, /function Resolve-SecurityDownloadUri/);
assert.strictEqual((securityPolicy.match(/Resolve-SecurityDownloadUri -Value/g) || []).length, 2,
    "every current manifest download owner must use the shared URI validator");
assert.match(securityBootstrap, /--require-hashes --only-binary=:all: --no-deps/);
assert(securityBootstrap.indexOf("Resolve-SecurityBootstrapManifest") >= 0);
assert(securityBootstrap.indexOf("Resolve-SecurityBootstrapManifest") < securityBootstrap.indexOf("New-Item"),
    "manifest metadata is not validated before filesystem mutation");
assert(!/Get-ChildItem[^\r\n]+-Recurse[^\r\n]+-Filter[^\r\n]+Select-Object -First 1/.test(securityBootstrap));
const advisory = JSON.parse(fs.readFileSync(path.join(root, "tests/security-advisory-baseline.json"), "utf8"));
assert.strictEqual(advisory.schema, 2);
assert.strictEqual(advisory.psscriptanalyzer.length, 6);
assert(advisory.psscriptanalyzer.every((finding) =>
    /^tools\/.+\.ps1$/.test(finding.path)
    && /^PS[A-Za-z]+$/.test(finding.rule)
    && /^[0-9a-f]{64}$/.test(finding.message_sha256)
    && Number.isInteger(finding.occurrence)
    && finding.occurrence > 0
    && finding.fingerprint === `${finding.path}|${finding.rule}|${finding.message_sha256}|${finding.occurrence}`));
assert.strictEqual(new Set(advisory.psscriptanalyzer.map((finding) => finding.fingerprint)).size, 6);
assert.deepStrictEqual(advisory.mixed_line_endings, [
    ".gitignore",
    "tools/check-lua51-upvalues.js",
    "tools/inject-runtime-build-label.js",
]);

const luarc = JSON.parse(fs.readFileSync(path.join(root, ".luarc.json"), "utf8"));
assert.strictEqual(luarc["runtime.version"], "Lua 5.1");
for (const diagnostic of ["undefined-global", "duplicate-local", "unreachable-code", "unbalanced-assignments", "unused-local"]) {
    assert.strictEqual(luarc["diagnostics.neededFileStatus"][diagnostic], "Any");
}

const exceptions = JSON.parse(fs.readFileSync(path.join(root, "tests/static-policy-exceptions.json"), "utf8"));
const ebonhold = exceptions.project_ebonhold_globals;
const allowed = new Set(ebonhold.allowed_paths);
const sourceRoots = ["core", "logic", "ui", "data"];
for (const sourceRoot of sourceRoots) {
    const directory = path.join(root, sourceRoot);
    for (const name of fs.readdirSync(directory)) {
        if (!name.endsWith(".lua")) continue;
        const relative = `${sourceRoot}/${name}`;
        const text = fs.readFileSync(path.join(directory, name), "utf8");
        const usesEbonholdGlobal = ebonhold.patterns.some((pattern) => text.includes(pattern));
        if (usesEbonholdGlobal) assert(allowed.has(relative), `unapproved Project Ebonhold global use: ${relative}`);
    }
}
for (const relative of allowed) assert(fs.existsSync(path.join(root, relative)), `stale static exception: ${relative}`);

const preCommit = fs.readFileSync(path.join(root, ".pre-commit-config.yaml"), "utf8");
assert.match(preCommit, /rev: [0-9a-f]{40}/);
assert.match(preCommit, /mixed-line-ending[\s\S]*--fix=no/);
assert.match(preCommit, /exclude: \^\(\\\.gitignore\|tools\//);
assert.match(preCommit, /stages: \[pre-push\]/);
assert(!preCommit.includes("rev: v"));

const stylua = fs.readFileSync(path.join(root, "stylua.toml"), "utf8");
assert(!stylua.includes("format"));
console.log("security policy self-tests: artifacts, pins, Lua 5.1, pre-commit, advisory formatting -- OK");
