# ТЗ ДЛЯ `paper-trading-architect`

## Stage 2 — Correction 4

## Изоляция integrity-тестов и финальное закрытие Stage 2

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
a07424e4e5db44ffc19f2889e85753c60625986c
```

### Base SHA

```text
6d3e869f3583d9ad8d2d23b692d4143ceb9a6e92
```

---

# 1. Цель

Исправить оставшиеся ошибки Stage 2:

1. Сделать replay corruption tests полностью изолированными.
2. Доказать, что test suite не изменяет схему и финансовые данные.
3. Исправить загрузку role-specific конфигурации.
4. Нормализовать TX-17 Decimal checksum.
5. Завершить permission, logging и reservation tests.
6. Исправить документацию.

Stage 3 не начинать.

---

# 2. Git preflight

```bash
git fetch origin --prune
git switch stage/02-database-ledger

git branch --show-current
git rev-parse HEAD
git rev-parse origin/stage/02-database-ledger
git rev-parse origin/main
git status --short
```

Ожидается:

```text
HEAD = a07424e4e5db44ffc19f2889e85753c60625986c
origin/stage/02-database-ledger = тот же SHA
origin/main = 6d3e869f3583d9ad8d2d23b692d4143ceb9a6e92
worktree clean
```

При несовпадении остановиться и зафиксировать реальные значения.

---

# 3. Не изменять миграции 001–004

Запрещено редактировать:

```text
001_stage2_foundation.sql
002_replay_and_immutability.sql
003_stage2_correction_2.sql
004_stage2_correction_3.sql
```

Создать:

```text
migrations/005_stage2_correction_4.sql
```

---

# 4. Исправить replay corruption tests

Текущая конструкция запрещена:

```python
async with conn.transaction():
    disable_triggers()
    corrupt_data()

    with pytest.raises(LedgerIntegrityError):
        await replay_account(...)
```

Так как ожидаемое исключение поглощается `pytest.raises`, внешняя PostgreSQL-транзакция завершается успешно и сохраняет повреждения.

## Требуемый вариант

Каждый corruption case должен гарантированно завершаться rollback.

Допустимые способы:

```text
1. После проверки выбросить test-only exception за пределы pytest.raises.
2. Явно вызвать transaction.rollback().
3. Использовать отдельную временную database для каждого сценария.
```

Предпочтительный шаблон:

```python
class RollbackCorruption(Exception):
    pass

with pytest.raises(RollbackCorruption):
    async with conn.transaction():
        apply_corruption()

        with pytest.raises(LedgerIntegrityError, match=EXPECTED_MESSAGE):
            await replay_account(conn, account_id)

        raise RollbackCorruption()
```

---

# 5. Проверять конкретную ошибку

Недостаточно проверять только:

```python
pytest.raises(LedgerIntegrityError)
```

Для каждого сценария проверять ожидаемое сообщение или error code:

```text
operation set mismatch
aggregate mismatch
ledger sequence mismatch
account projection mismatch
there must be exactly one INITIAL_DEPOSIT
invalid INITIAL_DEPOSIT version
unknown transaction type
account version continuity mismatch
```

Это исключает ситуацию, когда все тесты проходят из-за одной старой поломки.

---

# 6. Восстановить обязательные corruption cases

Отдельно и независимо проверить:

```text
expected operation count mismatch
actual operation count mismatch
operation set mismatch
aggregate mismatch
ledger sequence mismatch
available before mismatch
available after mismatch
reserved continuity mismatch
realized continuity mismatch
account projection mismatch
initial balance mismatch
missing INITIAL_DEPOSIT
duplicate INITIAL_DEPOSIT
wrong initial version
unknown transaction type
duplicate account version
missing account version
```

Каждый параметр должен начинаться с чистого валидного account.

Перед применением corruption:

```text
replay_account(account) → success
```

После rollback:

```text
replay_account(account) → success
```

---

# 7. Проверить отсутствие загрязнения БД

До integrity suite сохранить:

```text
schema-only dump SHA-256
число accounts
число financial_transactions
число ledger rows
число status events
список constraints
список indexes
состояние immutable triggers
```

После suite повторить.

Обязательное равенство:

```text
schema hash before == schema hash after
row counts before == row counts after
constraints before == constraints after
indexes before == indexes after
trigger states before == trigger states after
```

Проверить, что существуют:

```text
financial_transactions_one_initial_deposit_uq
financial_transactions_account_version_after_uq
financial_transactions_type_allowed
```

Проверить, что immutable triggers включены:

```text
account_ledger_no_update
financial_transactions_immutable
account_status_events_immutable
execution_events_immutable
```

Для всех ожидается обычное enabled-состояние PostgreSQL.

---

# 8. Исправить test cleanup

Любой тест, который временно отключает trigger или удаляет constraint/index, обязан восстанавливать состояние через `finally`.

Запрещено полагаться на порядок pytest.

Обязательные проверки:

```bash
pytest tests/integration/test_stage2_integrity.py -q
pytest tests/integration/test_stage2_integrity.py -q
```

Оба последовательных запуска должны пройти на одной базе.

Также запустить corruption parameters по одному, включая обратный порядок.

---

# 9. Исправить role-specific Settings

Текущий общий файл:

```text
.env.stage2-tools
```

содержит много полей, но отдельные Settings-классы используют:

```python
extra="forbid"
```

и объявляют только часть полей.

Выбрать один вариант.

## Предпочтительный вариант

Создать единый:

```python
Stage2ToolsSettings
```

с полями:

```text
paper_database_migrator_dsn
paper_database_profile_admin_dsn
paper_database_admin_dsn
paper_database_auditor_dsn
paper_database_heartbeat_dsn
paper_migrator_password
paper_account_admin_password
paper_auditor_password
paper_heartbeat_password
paper_profile_admin_password
```

Использовать:

```python
env_file=".env.stage2-tools"
extra="forbid"
```

Runtime оставить отдельным:

```python
RuntimeSettings
env_file=".env.runtime"
```

---

# 10. Скрипты должны использовать Settings

Исправить:

```text
scripts/migrate.py
scripts/seed_profiles.py
```

Запрещено читать role-specific DSN непосредственно через:

```python
os.environ["..."]
```

Использовать соответствующий typed Settings object.

Добавить smoke tests:

```text
.env.runtime.example загружается RuntimeSettings
.env.stage2-tools.example загружается Stage2ToolsSettings
неизвестная переменная отклоняется
отсутствующий обязательный DSN отклоняется
pool max < pool min отклоняется
```

Не использовать реальные пароли в тестах.

---

# 11. Воспроизводимый Compose запуск

Документировать точную команду:

```bash
docker compose \
  --env-file .env.stage2-tools \
  -f docker-compose.stage2-test.yml \
  up -d
```

Обычная команда без `--env-file` не должна выдаваться как рабочая, если пароли находятся в `.env.stage2-tools`.

Добавить Stage 2 runbook:

```text
docs/runbooks/STAGE_02_DEV_TEST.md
```

В runbook указать:

```text
создание локальных env-файлов
запуск PostgreSQL
миграции
profile seed
TX-17 initialization
tests
restart
backup/restore
остановка
удаление только Stage 2 volume
```

---

# 12. Удалить устаревший `.env.example`

Удалить или заменить `.env.example` кратким указателем на:

```text
.env.runtime.example
.env.stage2-tools.example
```

В репозитории не должно быть трёх противоречащих вариантов конфигурации.

---

# 13. Нормализовать TX-17 checksum

Текущий checksum зависит от:

```sql
p_initial_balance::TEXT
```

Нормализовать Decimal перед хешированием.

Использовать, например:

```sql
trim_scale(p_initial_balance)::TEXT
```

Канонический payload должен включать:

```text
normalized profile UUID
currency
normalized Decimal initial balance
account initialization version
```

Добавить migration 005 с обновлённой TX-17 procedure.

---

# 14. Проверить Decimal idempotency

Обязательный integration test:

```text
first call: Decimal("1000.00")
retry: Decimal("1000")
```

Ожидается:

```text
один account
один header
одна ledger row
один status event
retry успешен
checksum совпадает
```

Также:

```text
Decimal("1000.000000")
```

должен считаться тем же финансовым значением.

Изменённое значение:

```text
Decimal("1001")
```

должно завершаться `ProfileSeedConflictError` или утверждённой typed ошибкой.

---

# 15. Использовать единый canonical key helper

Python logging и PostgreSQL должны формировать одинаковый operation key.

В Python использовать:

```python
tx17_idempotency_key(
    str(UUID(command.profile_id)),
    command.account_initialization_version,
)
```

Не дублировать строковую формулу вручную.

Тестировать UUID в разных допустимых текстовых формах.

Stored operation key и logged operation key должны совпадать.

---

# 16. DatabaseUnavailableError

В `PostgresAccountRepository` преобразовать ошибки соединения и pool acquisition в:

```text
DatabaseUnavailableError
```

Не преобразовывать business conflicts в эту ошибку.

Добавить тесты:

```text
database unavailable → DatabaseUnavailableError
PROFILE_NOT_FOUND → ProfileNotFoundError
PROFILE_SEED_CONFLICT → ProfileSeedConflictError
PROFILE_ALREADY_INITIALIZED → ProfileAlreadyInitializedError
IDEMPOTENCY_CONFLICT → IdempotencyConflictError
INVALID_INITIALIZATION_VERSION → InvalidInitializationVersionError
```

---

# 17. Structured logging tests

Добавить `caplog` tests для:

```text
TX17_STARTED
TX17_COMMITTED
TX17_IDEMPOTENT_RETRY
TX17_CONFLICT
TX17_FAILED
```

Проверить поля:

```text
service
correlation_id
profile_id
account_id
operation_key
account_initialization_version
outcome
error_type
```

Проверить:

```text
пароль не попадает в log
DSN не попадает в log
retry attempt имеет текущий correlation ID
financial transaction сохраняет первоначальный correlation ID
```

---

# 18. Permission tests

Дополнить matrix.

## `paper_profile_admin`

Разрешено:

```text
SELECT trader_profiles
INSERT trader_profiles
```

Запрещено:

```text
UPDATE trader_profiles
DELETE trader_profiles
DDL
schema_migrations
paper_accounts
financial_transactions
account_ledger
account_status_events
execution_events
service_heartbeats
```

## `paper_auditor`

Разрешено:

```text
SELECT всех Stage 2 audit/account таблиц
```

Запрещены все записи и DDL.

## `paper_heartbeat`

Разрешено писать только:

```text
service_heartbeats
```

После permission suite проверить, что роли не получили лишние privileges.

---

# 19. Reservation domain test

Удалить бессодержательные проверки:

```python
assert Decimal("1.00") > 0
assert ForbiddenOperationError.__name__ == ...
```

Создать schema-only модель:

```python
ReservationSpec
```

Минимум:

```text
collateral_amount: Decimal
```

Проверки:

```text
positive Decimal accepted
zero rejected
negative rejected
float rejected
```

Запрещено создавать runtime:

```text
reserve()
release()
RESERVE_POSITION writer
RELEASE_RESERVE writer
```

Это остаётся Stage 5.

---

# 20. Исправить документацию

## README

Исправить:

```text
stage/02-paper-db-ledger
→ stage/02-database-ledger
```

Использовать статус:

```text
READY FOR RE-AUDIT
```

Не ставить самостоятельно:

```text
PASS
PASS WITH ISSUES
```

## DECISIONS

В ADR-032 изменить:

```text
Implementation stage: Stage 3
→ Implementation stage: Stage 2
```

Удалить ADR-036 как дублирующее и противоречащее решение.

## CURRENT_STATE и HANDOFF

Указать:

```text
Correction 4
ветка опубликована
финальный SHA передаётся после amend/push
Stage 3 не начат
```

## Task-файлы

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

У всех Markdown-файлов должно быть расширение `.md`.

---

# 21. Чистая финальная проверка

Полностью пересоздать только Stage 2 test DB:

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

Затем:

```text
migrations 001–005
4 profile seeds
4 TX-17 groups
idempotent retry
Decimal-scale retry
typed conflicts
rollback matrix
replay corruption matrix
permission matrix
logging tests
restart
backup/restore
```

После test suite выполнить clean replay всех четырёх accounts.

---

# 22. Обязательные команды

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

Повторно:

```bash
python -m pytest tests/integration/test_stage2_integrity.py -q
python -m pytest tests/integration/test_stage2_integrity.py -q
```

Оба запуска должны пройти без пересоздания БД между ними.

---

# 23. Secret scan

Выполнить фиксированным gitleaks:

```text
полное Git history
финальное дерево
финальный Stage 2 diff
exit 0
```

Не включать реальные DSN или пароли в Evidence.

---

# 24. `monitor-data`

До и после:

```bash
cd ~/monitor-data
git rev-parse HEAD
git status --short
```

Требуется полное совпадение.

Контейнеры `monitor-data` не останавливать и не перезапускать.

---

# 25. Git closeout

Перед commit:

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

Сохранить один Stage 2 commit:

```bash
git commit --amend --no-edit
```

Опубликовать:

```bash
git push --force-with-lease origin stage/02-database-ledger
```

После push:

```bash
git rev-parse HEAD
git rev-parse origin/stage/02-database-ledger
git status --short
```

Не выполнять merge, PR или Stage 3.

---

# 26. Итоговый статус

Агент возвращает:

```text
READY FOR RE-AUDIT
```

Агент не выставляет `PASS`.

Формат ответа:

```text
1. Base SHA.
2. Previous SHA.
3. New Final SHA.
4. Remote SHA.
5. Migration 005.
6. Config loading tests.
7. Documented Compose command.
8. Decimal normalization evidence.
9. Canonical key evidence.
10. Production procedure rollback 5/5.
11. Independent corruption matrix.
12. Integrity suite first run.
13. Integrity suite second run.
14. Schema hash before/after.
15. Trigger states before/after.
16. Indexes and constraints before/after.
17. Permission matrix.
18. Typed error matrix.
19. Structured logging tests.
20. Reservation domain tests.
21. Full suite.
22. mypy/ruff/format/float scan.
23. Restart and backup/restore.
24. Gitleaks.
25. monitor-data before/after.
26. Documentation fixes.
27. Merge not performed.
28. Stage 3 not started.
```
