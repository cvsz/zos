# OpenCode Instructions for zOS

Use `AGENTS.md` as the canonical operating contract.

Resolve repository state before editing, preserve production fail-closed behavior, do not invent topology or credentials, and keep behavior/evidence/documentation changes together.

Use `docs/INDEX.md` for documentation ownership and `docs/TESTING.md` for the validation matrix.

For end-to-end implementation use `docs/OPENCODE-MASTER-PROMPT.md` as the task prompt. It supplements but never overrides `AGENTS.md`. As of the documented 2026-09-22 baseline, live RouterOS apply remains disabled until independently verified CHR Safe Mode/rollback evidence exists.

~~~bash
make validate
make docs
make evidence
~~~
