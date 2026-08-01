# Stage 3 — Final Capacity Contract and Acceptance

## Цель

Закрыть Stage 3 одним финальным work item.

Зафиксировать поддерживаемую ёмкость:

```text
Не более 100 symbols в одном Market Data batch.
```

После этого выполнить один финальный acceptance:

```text
3 warm-up cycles
20 measured cycles
100 symbols
полная 24-hour history
```

Никаких новых архитектурных экспериментов и оптимизаций.

---

# 1. Исходная точка

```text
Repository:
shamilmirz/paper-trading-engine

Branch:
stage/03-market-data

Published SHA:
84340acc807e76eea545ce429f410b6005b54d47

Base:
ee72737406461df90980c51063fce297d7faa0be

Published commit count:
3
```

Remote должен оставаться на `84340acc...` до финального commit.

---

# 2. Удалить failed prototype из рабочей ветки

Предыдущий failed incremental prototype имеет локальный SHA:

```text
0aabb5c3b7890253e435f5be3ca4b7d3684a82ad
```

Сначала проверить:

```bash
git fetch origin
git status --short
git rev-parse HEAD
git rev-parse origin/stage/03-market-data
git diff --name-only 84340acc807e76eea545ce429f410b6005b54d47..HEAD
```

Допустимы только два состояния.

## Состояние A

```text
HEAD = 84340acc...
remote = 84340acc...
worktree clean
```

Тогда продолжить без reset.

## Состояние B

```text
HEAD = 0aabb5c...
remote = 84340acc...
worktree clean

Единственное изменение:
tests/load/test_stage3_incremental_state_prototype.py
```

Тогда сохранить failed experiment только локальной архивной веткой:

```bash
git branch archive/stage3-failed-incremental-prototype \
  0aabb5c3b7890253e435f5be3ca4b7d3684a82ad

git reset --hard origin/stage/03-market-data
```

Архивную ветку не публиковать.

Если Git-состояние отличается:

```text
STOP — GIT BASELINE MISMATCH
```

После очистки должно быть:

```text
HEAD = remote = 84340acc...
worktree clean
Base..HEAD = 3 commits
```

---

# 3. Финальный performance contract

Stage 3 гарантирует:

```text
maximum batch size = 100 symbols
```

Это лимит одного вызова Market Data Reader и одного Feature batch.

Stage 3 не гарантирует:

```text
500 symbols;
1000 symbols;
одновременный полный пересчёт всего рынка;
1000 symbols каждую минуту.
```

Выбор конкретных 100 активных symbols выполняется upstream Universe/orchestration.

Если upstream передал больше 100 symbols, Reader обязан завершиться fail-closed до SQL-запроса.

---

# 4. Разрешённые runtime-файлы

Изменять только:

```text
src/paper_engine/common/config.py
src/paper_engine/market_data/postgres_reader.py
```

## 4.1. Settings

Изменить:

```python
market_data_batch_size: int = Field(default=100, ge=1, le=100)
```

Требования:

```text
default = 100;
минимум = 1;
максимум = 100;
101 и выше запрещены конфигурацией.
```

## 4.2. Reader

Добавить в `PostgresMarketDataReader`:

```python
max_batch_size: int = 100
```

Проверять при создании:

```text
max_batch_size >= 1
```

В `_symbols()` после удаления дубликатов проверять:

```text
len(symbols) <= max_batch_size
```

При превышении:

```python
raise ValueError("market data batch exceeds configured maximum")
```

Ошибка должна возникать:

```text
до SQL;
до connection acquisition;
без увеличения query count.
```

Factory `create_market_data_reader()` должна передавать:

```python
max_batch_size=settings.market_data_batch_size
```

Не менять:

```text
Reader SQL;
query budget;
normalization;
Features;
checksum;
Universe formulas;
publication;
migrations.
```

---

# 5. Обязательные unit tests

Разрешено изменить:

```text
tests/unit/test_reader_startup.py
tests/unit/test_stage3_policy_factory.py
tests/unit/test_market_data.py
```

Покрыть:

```text
MarketDataSettings default batch size = 100;
MarketDataSettings принимает 1 и 100;
MarketDataSettings отклоняет 0 и 101;
factory передаёт configured batch size Reader;
Reader принимает ровно 100 unique symbols;
Reader отклоняет 101 unique symbols;
при отклонении SQL query не выполняется;
дубликаты не позволяют обойти лимит;
пустой список остаётся запрещён.
```

---

# 6. Исправить acceptance harness

Изменять:

```text
tests/load/test_stage3_market_reader_load.py
```

## 6.1. Acceptance configuration

Финальный режим:

```text
STAGE3_LOAD_MODE=acceptance
STAGE3_LOAD_SIZE=100
warm-ups = 3
measured = 20
```

В acceptance mode:

```text
другой size запрещён;
другой warm-up count запрещён;
другой measured count запрещён.
```

Diagnostic режимы 500/1000 могут остаться как исторический stress tooling, но они не входят в поддерживаемый runtime contract.

Для test-only stress Reader разрешено явно передавать `max_batch_size=size`.

Production factory остаётся ограничен значением 100.

## 6.2. Убрать дополнительный profile cycle

В acceptance mode должно быть выполнено ровно:

```text
3 warm-up
20 measured
0 profile cycles
```

Добавить evidence:

```text
warmup_cycles_executed
measured_cycles_executed
profile_cycles_executed
total_cycles_executed
```

Ожидается:

```text
3
20
0
23
```

## 6.3. Memory boundary

Измерять:

```text
warm-up завершён;
gc.collect();
tracemalloc.start();
20 measured cycles;
tracemalloc.stop();
```

Profile cycle не должен попадать:

```text
в latency;
в RSS acceptance result;
в tracemalloc result.
```

---

# 7. Final acceptance dataset

```text
100 symbols
1440 candles per symbol
288 OI rows per symbol
1 actual funding event per symbol
0 liquidations
aware UTC
Decimal only
```

Ожидаемые строки одного цикла:

```text
candles = 144000
OI = 28800
funding = 100
liquidations = 0
features = 100
```

Запросы:

```text
Market DB = 4
Paper DB = 0
```

Fixture setup не включать в cycle latency.

---

# 8. Финальные PASS-критерии

Все 20 measured cycles должны пройти correctness.

Обязательные performance gates:

```text
p95 <= 45000 ms
max <= 60000 ms
peak RSS <= 1073741824 bytes
```

Обязательные functional gates:

```text
100 feature snapshots;
100 unique symbols;
4 Market DB queries на цикл;
0 Paper DB queries;
общий aware UTC as_of;
price present;
volume_24h_quote present;
oi_base present;
OI changes 5m/30m/2h = 0;
funding rate = Decimal("0.0001");
liquidation totals = 0;
no float;
no checksum conflict;
no correctness failure.
```

Все критерии должны быть assertions внутри test, а не только текстом в отчёте.

---

# 9. Финальная команда acceptance

Использовать disposable PostgreSQL database:

```bash
STAGE3_LOAD_MODE=acceptance \
STAGE3_LOAD_SIZE=100 \
STAGE3_LOAD_EVIDENCE_PATH=/tmp/stage3-final-acceptance-100.json \
pytest -q tests/load/test_stage3_market_reader_load.py \
  -k market_reader_load_size -s
```

Не использовать production Market DB.

TimescaleDB в этом финальном gate не обязателен.

Зафиксировать в документации:

```text
Stage 3 capacity доказана на disposable PostgreSQL schema.
Production TimescaleDB deployment verification относится к deployment/runtime validation, а не к Stage 3 library acceptance.
```

---

# 10. Результат теста

## Если acceptance прошёл

Продолжить финальную проверку и commit.

## Если acceptance не прошёл

Немедленно остановиться:

```text
FINAL ACCEPTANCE FAILED
STAGE 3 NOT PASS
OWNER DECISION REQUIRED
```

Запрещено после провала:

```text
оптимизировать;
ослаблять SLO;
повторять тест с другими параметрами;
уменьшать history;
уменьшать measured cycles;
изменять formulas;
возвращаться к incremental prototype.
```

---

# 11. Полная финальная проверка

После успешного acceptance выполнить:

```bash
pytest -q tests/unit

pytest -q \
  tests/integration/test_stage3_permissions.py \
  tests/integration/test_stage3_reader.py \
  tests/integration/test_stage3_oi_reader.py \
  tests/integration/test_stage3_publication.py \
  tests/integration/test_stage3_publication_repository.py \
  -rs

pytest -q tests/load/test_stage3_market_reader_load.py \
  -k full_history_single_symbol_correctness -s

ruff check .
ruff format --check .
mypy src
python -m compileall -q src
git diff --check
```

Также проверить:

```text
migration 008 unchanged;
publication unchanged;
Features unchanged;
normalization unchanged.
```

---

# 12. Документация

Обновить:

```text
CURRENT_STATE.md
HANDOFF.md
TODO.md

docs/market_data/STAGE_03_PERFORMANCE_REPORT.md
docs/stages/STAGE_03_EVIDENCE.md
docs/stages/STAGE_03_OPEN_ISSUES.md
docs/stages/STAGE_03_REPORT.md
```

Записать:

```text
Correctness gates: PASS
Certified batch capacity: 100 symbols
Final acceptance: PASS
Warm-up/measured: 3/20
p50/p95/max
peak RSS
tracemalloc peak
query count
row count
environment
evidence JSON path
```

Отдельно записать ограничения:

```text
500/1000 symbols are unsupported operational batch sizes;
1000-symbol stress result не является Stage 3 requirement;
failed incremental prototype не входит в branch;
production deployment и Timescale validation выполняются отдельно.
```

Статус документации:

```text
STAGE 3 TECHNICAL GATES: PASS
MERGE PENDING INDEPENDENT OWNER AUDIT
```

Не писать, что Stage 3 уже merged.

---

# 13. Разрешённые файлы итогового commit

```text
src/paper_engine/common/config.py
src/paper_engine/market_data/postgres_reader.py

tests/unit/test_reader_startup.py
tests/unit/test_stage3_policy_factory.py
tests/unit/test_market_data.py
tests/load/test_stage3_market_reader_load.py

CURRENT_STATE.md
HANDOFF.md
TODO.md

docs/market_data/STAGE_03_PERFORMANCE_REPORT.md
docs/stages/STAGE_03_EVIDENCE.md
docs/stages/STAGE_03_OPEN_ISSUES.md
docs/stages/STAGE_03_REPORT.md
```

Другие файлы запрещены.

---

# 14. Git и публикация

Только если все gates прошли:

```bash
git add <только точные разрешённые изменённые пути>

git commit -m "perf(stage3): certify 100-symbol market data capacity"
```

Проверить:

```bash
git status --short
git rev-parse HEAD
git rev-parse origin/stage/03-market-data
git rev-list --count ee72737406461df90980c51063fce297d7faa0be..HEAD
git diff --stat 84340acc807e76eea545ce429f410b6005b54d47..HEAD
git diff --name-only 84340acc807e76eea545ce429f410b6005b54d47..HEAD
```

Ожидается:

```text
worktree clean
Base..HEAD = 4 commits
remote = 84340acc...
```

После этого разрешён один обычный push:

```bash
git push origin stage/03-market-data
```

Запрещено:

```text
force push;
amend;
squash;
rebase;
PR;
merge;
main changes.
```

После push выполнить только Git verification и остановиться.

---

# 15. Финальный отчёт

```text
STAGE 3 — FINAL ACCEPTANCE REPORT

1. Git
- Base
- Previous published SHA
- Final SHA
- Remote SHA
- Commit count
- Worktree
- ordinary push confirmation

2. Failed prototype cleanup
- previous local SHA
- archived locally: yes/no
- branch reset to published baseline
- prototype absent from final diff

3. Capacity contract
- settings default
- settings maximum
- Reader maximum
- factory wiring
- >100 fail-closed evidence

4. Acceptance
- command
- database
- environment
- symbols
- warm-ups
- measured
- profile cycles
- p50
- p95
- max
- peak RSS
- tracemalloc

5. Correctness
- query counts
- row counts
- feature count
- unique symbols
- OI
- funding
- liquidations
- Decimal
- UTC

6. Regression
- unit
- integration
- smoke
- ruff
- format
- mypy
- compileall
- diff check

7. Isolation
- no Features changes
- no normalization changes
- no migration changes
- no production DB
- no monitor-data
- no Docker
- no scheduler
- no PR
- no merge
- no Stage 4

8. Status
STAGE 3 TECHNICAL GATES PASS
READY FOR FINAL INDEPENDENT AUDIT
MERGE NOT PERFORMED
```

После отчёта не выполнять других действий.
