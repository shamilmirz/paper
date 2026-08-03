# STAGE 4B — SERVER CORRECTION TASK

## Repository

```text
shamilmirz/paper-trading-engine
```

## Working branch

```text
stage/04b-levels
```

## Rejected baseline

```text
rejected SHA: 4ecfcbad0bed7344c1ac5857aa2c010980a88c56
base/main SHA: 41547df810918dad7eb7d1dffe49f1ac26a2013a
verdict: REJECT
```

Continue on `stage/04b-levels`. Do not merge, deploy, modify or restart `monitor-data`, touch production databases, or start Stage 5.

## Objective

Correct every blocking defect found by the independent server acceptance, then repeat the complete acceptance in a clean clone on server2. Do not declare PASS from unit tests alone.

## Confirmed defects

1. `ruff format --check` fails for:
   - `src/paper_engine/runtime/stage4_levels_once.py`
   - `tests/unit/test_stage4b_levels_load.py`
2. `mypy --strict` reports 17 errors in 5 files.
3. `pytest -q tests/unit` fails during collection because `tests/unit/test_stage4b_migration_bundle.py` imports `scripts.migrate`.
4. Clean PostgreSQL 16.4 init fails because `011a_stage4_levels_schema.sql` executes before `level_runs` exists.
5. Legacy candle SQL remains in shared Stage 3/4A modules; the Stage 4B Levels runtime must be proven independent of those query paths.
6. `git diff --check` fails because five migration files contain extra blank lines at EOF.
7. The prior SHA has no green independent Docker/PostgreSQL acceptance.

# Required corrections

## A. Repair migration 011 as one real deployment unit

The current Python migration bundler is not enough. The official PostgreSQL image executes every `*.sql` file under `/docker-entrypoint-initdb.d`, so the `011a…011m.sql` fragments are treated as independent migrations.

Implement this exact boundary:

1. Keep one executable canonical migration:

```text
migrations/011_stage4_levels.sql
```

2. Rename every Stage 4B fragment to a non-entrypoint extension, for example:

```text
011a_stage4_levels_schema.inc
011b_stage4_levels_runs.inc
...
011m_stage4_levels_retest_observations.inc
```

No `011[a-z]*.sql` files may remain.

3. Make `011_stage4_levels.sql` execute the fragments explicitly and deterministically with `\ir`, in exact dependency order. The base `level_runs`/core tables must exist before any staging table or function references them.

4. Update `scripts/migrate.py` so that:
   - canonical files are discovered from `NNN_*.sql`;
   - fragments are discovered from `NNN[a-z]_*.inc`;
   - version 011 has one combined checksum covering canonical plus every fragment name and byte content;
   - asyncpg execution strips/does not send psql meta-command lines such as `\ir`;
   - canonical SQL body and fragments execute inside one asyncpg transaction;
   - versions 001–010 retain their historical single-file checksum behavior;
   - orphan fragments, duplicate versions, missing fragments and ordering conflicts fail closed.

5. Update migration tests for the `.inc` contract.

6. Remove trailing blank lines at EOF from all migration files. Require:

```bash
git diff --check
```

7. Prove on a clean PostgreSQL 16.4 database:
   - first application succeeds;
   - second application is idempotent;
   - `schema_migrations` has exactly one row for version 11;
   - the stored checksum equals the complete bundle checksum;
   - no fragment was applied as an independent migration.

Do not solve this by merely renaming `011_stage4_levels.sql` to sort earlier. The fragments must stop being independent PostgreSQL entrypoint scripts.

## B. Remove the `scripts` import failure correctly

Do not rely on the repository root accidentally being present in `sys.path`.

Preferred correction:

1. Move reusable migration discovery/checksum logic from `scripts/migrate.py` into an importable package module, for example:

```text
src/paper_engine/migrations.py
```

2. Keep `scripts/migrate.py` as a thin executable wrapper.
3. Change tests to import from `paper_engine.migrations`.
4. Do not add global `sys.path` mutations in tests or production code.

At minimum, collection must pass in a clean installed environment using:

```bash
python -m pip install -e '.[test]'
pytest -q tests/unit
```

## C. Fix all strict mypy errors

Run exactly:

```bash
mypy --strict src scripts/migrate.py
```

Requirements:

- fix all 17 errors at their source;
- preserve precise `LevelsReader` and `LevelsRepository` protocols;
- make test doubles satisfy the same protocols;
- type asyncpg pools/connections/records explicitly;
- use narrowing before passing optional production settings;
- do not add `ignore_errors`, broad `disable_error_code`, `Any` escapes, or blanket `# type: ignore`;
- a narrow ignore is allowed only for a verified third-party stub defect and must include the exact error code and explanation.

Store the complete before/after mypy output in the final evidence report.

## D. Apply formatter and preserve lint

Run the pinned project toolchain:

```bash
ruff check src scripts tests
ruff format src/paper_engine/runtime/stage4_levels_once.py tests/unit/test_stage4b_levels_load.py
ruff format --check src scripts tests
```

Do not change the pinned Ruff version merely to make the check pass.

## E. Decouple Levels from legacy candle query paths

The legacy references reported in these files belong to existing Stage 3/4A code:

```text
src/paper_engine/market_data/normalization.py
src/paper_engine/market_data/postgres_reader.py
scripts/init-stage4-market.sh
```

Do not delete or rewrite unrelated Stage 3/4A behavior merely to satisfy a grep.

Instead make the Stage 4B boundary explicit and testable:

1. `CanonicalCandlePostgresReader` must not inherit a method that can query legacy `candles_1m`/`candles_1h` tables.
2. Extract or implement a small read-only canonical reader/session whose only candle relation is:

```text
public.candles_1m_canonical
```

3. The Levels runtime and one-shot rebuild must depend only on that canonical interface.
4. Add a focused test/static assertion proving the Levels source files contain no legacy relation names and cannot call the legacy fetch path.
5. Keep the production source gate fail closed while canonical production candles remain `BLOCKED`.

A repository-wide grep finding legacy names in unchanged Stage 3/4A modules is not itself a Stage 4B failure; a reachable legacy query from the Levels runtime is a failure.

## F. Repair and strengthen CI contract

1. Add `workflow_dispatch:` to `.github/workflows/stage4b-contract.yml` so it can be started from the GitHub UI without `gh` on server2.
2. CI must run:
   - compileall;
   - Ruff check;
   - Ruff format check;
   - strict mypy;
   - complete unit tests;
   - clean PostgreSQL 16.4/Docker acceptance;
   - migration double-run and checksum assertions;
   - READY/FAILED atomicity;
   - Binance/Bybit role and exchange isolation;
   - direct-DML denial;
   - restart/replay idempotency;
   - heartbeat/recovery checks;
   - production Compose topology and fixture absence;
   - scoped canonical-reader/legacy-path boundary check.
3. Diagnostic logs must be collected on failure before containers are removed.
4. Absence of the `gh` binary on server2 must not be reported as a product-code defect. The independent server acceptance remains authoritative; GitHub UI dispatch is supplementary.

# Mandatory clean-server acceptance

Perform from a new directory, not the development worktree:

```bash
git clone --branch stage/04b-levels --single-branch \
  https://github.com/shamilmirz/paper-trading-engine.git stage4b-acceptance
cd stage4b-acceptance
git rev-parse HEAD
git status --short
python3.12 -m venv .venv
. .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -e '.[test]'
python -m compileall -q src scripts tests
ruff check src scripts tests
ruff format --check src scripts tests
mypy --strict src scripts/migrate.py
pytest -q tests/unit
git diff --check
```

Then run the disposable PostgreSQL 16.4/Docker acceptance from `docker-compose.stage4-test.yml` and record:

- exact tested SHA;
- Docker/Compose/PostgreSQL versions;
- migration first-run and second-run results;
- version-11 checksum row;
- table/function/view counts;
- READY pointers and watermarks;
- FAILED-run invisibility and previous READY preservation;
- writer-role exchange isolation;
- direct table DML rejection;
- restart counts before and after;
- heartbeat/recovery evidence;
- complete container health and logs;
- cleanup confirmation.

# Required final response

Return only after all checks pass:

```text
Final SHA
Branch
Base SHA
Commits created
Files changed
compileall result
ruff check result
ruff format result
mypy result
pytest result
git diff --check result
PostgreSQL 16.4 migration first-run result
Migration second-run result
schema_migrations version-11 checksum evidence
Docker service health
READY/FAILED atomicity evidence
Role/exchange isolation evidence
Direct-DML denial evidence
Restart/replay evidence
Heartbeat/recovery evidence
Legacy-path boundary evidence
Cleanup result
Remaining blockers
Final verdict
```

The only acceptable implementation verdict before the separate candle-source audit is:

```text
STAGE 4B IMPLEMENTATION ACCEPTANCE PASS — PRODUCTION CANONICAL SOURCE STILL BLOCKED
```

If any mandatory command fails, return `REJECT`, include the exact command and full relevant error, and do not merge or deploy.
