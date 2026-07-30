# ТЗ ДЛЯ `paper-trading-architect`

## Stage 2 — Correction 5

## Финальная целостность ledger и подготовка ветки к merge

### Репозиторий

```text
shamilmirz/paper-trading-engine
```

### Ветка

```text
stage/02-database-ledger
```

### Текущий SHA

```text
9b5674c4c897bc5ca2a6499f62632d27231387e2
```

### Утверждённый Stage 1 SHA

```text
6d3e869f3583d9ad8d2d23b692d4143ceb9a6e92
```

### Текущий `origin/main`, обнаруженный аудитом

```text
3dcbafb4a53ea0d6a5d337c48789f810c9997f88
```

---

# 1. Цель

Исправить последние блокирующие ошибки Stage 2:

1. Связать каждую ledger row с тем же account, что и financial transaction.
2. Проверять точный operation set по transaction type.
3. Улучшить независимость и доказательства integrity-тестов.
4. Исправить классификацию TX-17 commit/retry в логах.
5. Закрыть ошибки конфигурации, permissions и документации.
6. Перенести Stage 2 поверх актуального `main`, сохранив один Stage 2 commit.

Stage 3 не начинать.

---

# 2. Git preflight

```bash
git fetch origin --prune
git switch stage/02-database-ledger

git rev-parse HEAD
git rev-parse origin/stage/02-database-ledger
git rev-parse origin/main
git merge-base origin/main HEAD
git status --short
```

Ожидаемый текущий Stage 2 SHA:

```text
9b5674c4c897bc5ca2a6499f62632d27231387e2
```

Если `origin/main` отличается от:

```text
3dcbafb4a53ea0d6a5d337c48789f810c9997f88
```

использовать фактический новый SHA и зафиксировать его в отчёте.

---

# 3. Перенести ветку поверх актуального main

Сейчас Stage 2 и `main` расходятся от Stage 1.

Не создавать merge commit.

Перенести единственный Stage 2 commit поверх текущего `origin/main`:

```bash
git rebase --onto origin/main \
  6d3e869f3583d9ad8d2d23b692d4143ceb9a6e92 \
  stage/02-database-ledger
```

При add/add конфликте с файлом Correction 2 сохранить одну копию. Позже перенести task-файл в правильную директорию.

После rebase проверить:

```bash
git merge-base origin/main HEAD
git rev-list --count origin/main..HEAD
```

Ожидается:

```text
merge-base = текущий origin/main
commits ahead = 1
```

---

# 4. Новая migration 006

Не изменять migrations 001–005.

Создать:

```text
migrations/006_stage2_correction_5.sql
```

---

# 5. Связать ledger account с transaction account

Добавить уникальный ключ:

```sql
ALTER TABLE financial_transactions
ADD CONSTRAINT financial_transactions_id_account_uq
UNIQUE (id, account_id);
```

Добавить composite foreign key:

```sql
ALTER TABLE account_ledger
ADD CONSTRAINT account_ledger_transaction_account_fk
FOREIGN KEY (financial_transaction_id, account_id)
REFERENCES financial_transactions(id, account_id);
```

Существующие отдельные foreign keys можно сохранить.

PostgreSQL должна отвергать ledger row, у которой:

```text
ledger.account_id != financial_transactions.account_id
```

---

# 6. Исправить replay account ownership

В запрос ledger rows добавить:

```text
account_id
```

Для каждой строки проверить:

```text
row.account_id == replayed account_id
```

При несовпадении:

```text
LedgerIntegrityError("ledger account ownership mismatch")
```

Добавить corruption test:

1. Взять transaction счёта A.
2. В rollback-транзакции временно удалить composite FK.
3. Изменить ledger row так, чтобы она ссылалась на счёт B.
4. Replay счёта A обязан вернуть точную ошибку ownership mismatch.
5. После rollback clean replay обоих счетов должен пройти.

---

# 7. Канонический operation set

Добавить в migration 006 DB constraint:

```text
INITIAL_DEPOSIT
→ INITIAL_DEPOSIT

OPEN_POSITION
→ RESERVE_POSITION, ENTRY_COMMISSION

APPLY_FUNDING
→ FUNDING

CLOSE_POSITION
→ EXIT_COMMISSION, REALIZED_PNL, RELEASE_RESERVE

ACCOUNT_ADJUSTMENT
→ ADJUSTMENT
```

Проверка должна учитывать точный состав и порядок.

Допустимый вариант:

```sql
CHECK (
    expected_operation_set =
    CASE transaction_type
        WHEN 'INITIAL_DEPOSIT'
            THEN ARRAY['INITIAL_DEPOSIT']::TEXT[]
        WHEN 'OPEN_POSITION'
            THEN ARRAY['RESERVE_POSITION', 'ENTRY_COMMISSION']::TEXT[]
        WHEN 'APPLY_FUNDING'
            THEN ARRAY['FUNDING']::TEXT[]
        WHEN 'CLOSE_POSITION'
            THEN ARRAY['EXIT_COMMISSION', 'REALIZED_PNL', 'RELEASE_RESERVE']::TEXT[]
        WHEN 'ACCOUNT_ADJUSTMENT'
            THEN ARRAY['ADJUSTMENT']::TEXT[]
    END
)
```

---

# 8. Исправить replay operation-set validation

Создать в Python каноническую immutable mapping:

```text
transaction type → exact ordered operation list
```

Replay должен проверять по порядку:

1. Transaction type известен.
2. Header operation set совпадает с каноническим набором.
3. Ledger rows совпадают с header.
4. Число строк совпадает с expected и actual count.

Ошибки разделить:

```text
transaction operation set mismatch
ledger operation set mismatch
operation count mismatch
actual operation count mismatch
```

---

# 9. Coordinated corruption test

Добавить тест, который портит header и ledger одинаково.

Пример:

```text
transaction_type = OPEN_POSITION
header expected set = FUNDING
ledger operation = FUNDING
```

Остальные balances, versions, sequence и counts сделать внутренне согласованными.

Текущий replay принял бы такую группу. Исправленный обязан вернуть:

```text
LedgerIntegrityError("transaction operation set mismatch")
```

Все изменения выполнить внутри rollback-транзакции.

---

# 10. Улучшить database snapshot

Текущий snapshot проверяет только counts и каталог.

Добавить:

## Financial data digest

Вычислить детерминированный SHA-256 содержимого:

```text
trader_profiles
paper_accounts
financial_transactions
account_ledger
account_status_events
execution_events
```

Строки сортировать по стабильным primary keys.

## Trigger state

Использовать `pg_trigger` и сохранять:

```text
tgname
tgrelid
tgenabled
```

Проверять, что immutable triggers имеют:

```text
tgenabled = O
```

## Полная проверка

До и после каждого corruption test:

```text
row counts equal
financial row digest equal
constraints equal
indexes equal
trigger definitions equal
trigger enabled states equal
```

После rollback обязательно выполнить:

```text
replay_account(account) → success
```

---

# 11. Честно считать integrity tests

В отчёте не писать:

```text
24 corruption cases
```

Указывать реальный breakdown, например:

```text
5 TX-17 rollback cases
19 replay corruption cases
1 clean four-account replay
1 migration checksum test
total integrity file tests: 26
```

Использовать фактические числа после исправлений.

---

# 12. TX-17 result identity

Не определять commit/retry через сравнение correlation ID.

Изменить PostgreSQL procedure, добавив в результат:

```text
was_created BOOLEAN
```

Поведение:

```text
новый account создан → TRUE
существующий idempotent result → FALSE
```

Python repository:

```text
was_created = TRUE
→ TX17_COMMITTED

was_created = FALSE
→ TX17_IDEMPOTENT_RETRY
```

Повтор с тем же correlation ID всё равно должен логироваться как retry.

Financial transaction сохраняет correlation ID первого успешного commit.

Attempt log использует correlation ID текущего вызова.

---

# 13. Реальные structured logging tests

Тесты должны вызывать:

```text
PostgresAccountRepository.initialize_account()
```

а не передавать готовую строку outcome непосредственно в `operation_logger`.

Проверить:

1. Первый вызов → `TX17_STARTED`, затем `TX17_COMMITTED`.
2. Retry с тем же correlation ID → `TX17_IDEMPOTENT_RETRY`.
3. Retry с другим correlation ID → `TX17_IDEMPOTENT_RETRY`.
4. Persisted financial correlation ID не меняется.
5. Conflict → `TX17_CONFLICT`.
6. Database connection failure → `TX17_FAILED`.
7. Пароль и DSN не попадают в log.

---

# 14. Validation `InitializationCommand`

Добавить runtime validation:

```text
profile_id: valid UUID
currency: non-empty canonical uppercase
initial_balance: finite positive Decimal
account_initialization_version: supported integer
correlation_id: non-empty
```

Запретить:

```text
float
NaN
Infinity
-Infinity
zero deposit
negative deposit
empty correlation ID
invalid UUID
```

Ошибки должны быть typed domain errors, а не raw `ValueError`, `decimal.InvalidOperation` или asyncpg error.

---

# 15. DatabaseUnavailableError tests

Добавить тесты настоящего repository boundary:

```text
pool acquisition failure
closed pool
connection loss
```

Ожидается:

```text
DatabaseUnavailableError
```

Business errors не должны превращаться в database unavailable:

```text
ProfileNotFoundError
ProfileSeedConflictError
ProfileAlreadyInitializedError
IdempotencyConflictError
InvalidInitializationVersionError
```

---

# 16. Permission matrix

Дополнить integration tests.

## paper_profile_admin

Разрешено:

```text
SELECT trader_profiles
INSERT trader_profiles
```

Запрещено:

```text
UPDATE trader_profiles
DELETE trader_profiles
schema_migrations
paper_accounts
financial_transactions
account_ledger
account_status_events
execution_events
service_heartbeats
DDL
```

## paper_auditor

Разрешено:

```text
SELECT всех Stage 2 таблиц
```

Запрещены:

```text
INSERT
UPDATE
DELETE
TRUNCATE
DDL
procedure TX-17
```

## paper_heartbeat

Разрешены записи только в:

```text
service_heartbeats
```

---

# 17. Исправить tools env

Compose требует:

```text
PAPER_DB_ADMIN_PASSWORD
```

Добавить это поле в:

```text
.env.stage2-tools.example
Stage2ToolsSettings
```

Добавить config test.

Удалить устаревший:

```text
.env.example
```

или оставить в нём только пояснение:

```text
Use .env.runtime and .env.stage2-tools.
```

Не хранить DSN без пароля как якобы рабочий пример.

---

# 18. Runbook

Создать:

```text
docs/runbooks/STAGE_02_DEV_TEST.md
```

Указать точные действия:

```text
copy example env files
set local passwords
start Stage 2 PostgreSQL
apply migrations
seed profiles
initialize four accounts
run tests
restart
backup
restore
stop database
delete only Stage 2 volume
```

Compose запуск:

```bash
docker compose \
  --env-file .env.stage2-tools \
  -f docker-compose.stage2-test.yml \
  up -d
```

Runbook должен проходить на чистом volume без ручной подмены DSN или переменных.

---

# 19. Исправить документацию

## README

Исправить ветку:

```text
stage/02-paper-db-ledger
→ stage/02-database-ledger
```

Статус:

```text
READY FOR RE-AUDIT
```

Не писать `PASS` или `PASS WITH ISSUES` до решения аудитора.

## DECISIONS

В ADR-032:

```text
Implementation stage: Stage 2
```

Удалить ADR-036.

## CURRENT_STATE

Удалить противоречие:

```text
not yet committed or pushed
```

при одновременно опубликованной ветке.

Указать:

```text
Correction 5
current main base
published remote branch
final SHA supplied after amend
```

## Evidence

Указать точный breakdown тестов.

Не называть каталог/count snapshot финансовым data digest, если содержимое строк не хешировалось.

## Task files

Перенести:

```text
docs/Stage 2 — Correction 2.md
docs/Stage 2 — Correction 3
```

в:

```text
docs/tasks/STAGE_02_CORRECTION_2_TASK.md
docs/tasks/STAGE_02_CORRECTION_3_TASK.md
```

Все Markdown-файлы должны иметь `.md`.

---

# 20. Чистая проверка

Пересоздать только Stage 2 database:

```bash
docker compose \
  --env-file .env.stage2-tools \
  -f docker-compose.stage2-test.yml \
  down -v

docker compose \
  --env-file .env.stage2-tools \
  -f docker-compose.stage2-test.yml \
  up -d
```

Выполнить:

```text
migrations 001–006
migration idempotent rerun
4 profile seeds
4 TX-17 groups
same-correlation retry
different-correlation retry
Decimal-scale retry
rollback 5/5
all corruption tests
cross-account ledger corruption
coordinated operation-set corruption
permission matrix
logging matrix
restart
backup/restore
```

Integrity suite запустить дважды подряд на одной DB.

После обоих запусков выполнить clean replay всех четырёх accounts.

---

# 21. Статические проверки

```bash
python3.12 --version

python -m pytest tests/unit -q
python -m pytest tests/integration -q
python -m pytest tests/concurrency -q
python -m pytest -q

python -m mypy src
python -m ruff check .
python -m ruff format --check .
python scripts/float_scan.py

git diff --check
```

Integration tests не должны skip при отсутствии DB configuration.

---

# 22. Secret scan

Выполнить фиксированным gitleaks:

```text
полная Git history
финальное дерево
diff текущего main → Stage 2
exit 0
```

Не записывать реальные пароли и DSN в Evidence.

---

# 23. monitor-data

До и после:

```bash
cd ~/monitor-data
git rev-parse HEAD
git status --short
```

HEAD и полный status должны совпадать.

Не останавливать и не перезапускать контейнеры `monitor-data`.

---

# 24. Финальный commit

Обновить сообщение единственного Stage 2 commit:

```text
feat(stage-02): add paper database and accounting foundation
```

Перед amend:

```bash
git status --short
git diff
git diff --check
```

Не использовать:

```bash
git add .
git add -A
```

Добавлять только ожидаемые файлы явным списком.

```bash
git commit --amend
```

После amend проверить:

```bash
git rev-list --count origin/main..HEAD
```

Ожидается:

```text
1
```

---

# 25. Публикация

```bash
git push --force-with-lease origin stage/02-database-ledger
```

После push:

```bash
git rev-parse HEAD
git rev-parse origin/stage/02-database-ledger
git merge-base origin/main HEAD
git status --short
```

Требуется:

```text
local SHA = remote SHA
merge-base = origin/main
worktree clean
```

Не создавать PR и не выполнять merge.

---

# 26. Итоговый ответ

Вернуть:

```text
1. Verdict: READY FOR RE-AUDIT.
2. Current main SHA.
3. Previous Stage 2 SHA.
4. New final SHA.
5. Remote SHA.
6. Ahead of main count.
7. Migration 006.
8. Composite ledger/account FK proof.
9. Canonical operation-set DB proof.
10. Cross-account corruption result.
11. Coordinated header+ledger corruption result.
12. Exact integrity test breakdown.
13. First integrity run.
14. Second integrity run.
15. Clean replay after both runs.
16. Financial row digest before/after.
17. Trigger enabled states before/after.
18. TX-17 created/retry logging results.
19. Typed command-validation results.
20. DatabaseUnavailableError tests.
21. Permission matrix.
22. Config and runbook smoke result.
23. Full test suite.
24. mypy/ruff/format/float scan.
25. Restart and backup/restore.
26. Gitleaks.
27. monitor-data before/after.
28. Documentation fixes.
29. Merge not performed.
30. Stage 3 not started.
```

Агент не выставляет `PASS`.
