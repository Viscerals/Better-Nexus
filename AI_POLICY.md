# AI and Automated Systems Policy

## Scope

This policy defines acceptable AI-assisted development and release behavior for this repository.

## Allowed AI-assisted activities

AI systems and automated assistants may be used by authorized contributors and maintainers for:

- source-code analysis and refactoring;
- code generation and drafting;
- debugging and test generation;
- review and quality checks;
- documentation writing and updates;
- translation and localization support;
- issue/log analysis and release planning;
- performance and security analysis;
- project maintenance and repository hygiene.

## Human responsibility

AI-assisted tooling does not remove human accountability. For every change:

- a contributor must understand the change and run required checks;
- correctness, regression, and compatibility must be validated;
- security and privacy impact must be reviewed;
- license and attribution impact must be reviewed;
- ownership and provenance obligations must be preserved;
- the contributor remains responsible for final merge/release decisions.

AI output is treated as draft input and must receive the same review and validation standards as a human draft. Prompts, chat logs, transcripts, chain-of-thought, scratch files, and private model output are not required repository artifacts.

## Prohibited use

The following are not allowed:

- using AI to copy or transform proprietary/incompatible third-party code and present it as original Better-Nexus work;
- laundering upstream, third-party, or confidential code through translation/refactoring to evade notices or legal constraints;
- removing or obscuring provenance, copyright notices, or license requirements;
- using AI output to bypass security, release, or branch controls;
- implying ownership of transformed upstream/third-party work where ownership cannot be shown;
- uploading credentials, private tokens, private player data, private SavedVariables, private logs, or confidential material to AI systems without explicit authorization;
- committing prompts, chats, transcripts, chain-of-thought, scratch outputs, or private temporary data as source artifacts.

Permission to use AI is not a separate copyright or redistribution license. It does not authorize copying, modifying, repackaging, sublicensing, selling, rebranding, unauthorized redistribution, or model training/use.

## Third-party and upstream respect

Contributors must preserve known upstream provenance, notices, and license files, including:

- Boganic attribution;
- `UPSTREAM.md`;
- other third-party notices and required license terms.

AI-assisted changes derived from upstream/third-party material remain governed by the actual applicable rights.

## Security and privacy

AI tooling must never be used to disclose secrets, credentials, private player data, SavedVariables, exploitable details, or private vulnerability data.

Do not use model output to bypass required reviews, policy checks, or release approvals.
