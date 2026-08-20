# Runtime build identity

Better Nexus keeps public compatibility identity separate from private test
artifact identity:

- `data/Release.lua` `version` remains the public semantic version used by
  update comparison and presence traffic.
- DPS/Sync protocol remains protocol 7.
- `data/Release.lua` `buildLabel` is display-only. A source checkout uses the
  deterministic `source` fallback.

Private packaging may run `tools/inject-runtime-build-label.js` against the
staged package copy of `data/Release.lua`. The tool accepts a label shaped like
`test.<number>-<7-to-12-lowercase-hex-head>` and replaces exactly this line:

```lua
    buildLabel = "source",
```

No reviewed source file is edited during packaging. In the generated package,
that one metadata line is the sole permitted byte difference from the reviewed
TOC-listed source. Package verification must compare every staged file, account
for that exact line, and reject missing or duplicate anchors.

The runtime label appears in `/nexus status`, the full diagnostic export, and
Peer Test. It is never an update, wire, authorization, ownership, or gameplay
input.
