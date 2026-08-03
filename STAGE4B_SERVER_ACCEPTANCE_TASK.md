# ТЗ ДЛЯ СЕРВЕРНОГО АГЕНТА — STAGE 4B LEVELS ACCEPTANCE

## 1. Цель

Провести независимую серверную приёмку реализации `Stage 4B — Levels Builder` из репозитория:

```text
shamilmirz/paper-trading-engine
```

Проверяемая ветка и точный commit:

```text
branch: stage/04b-levels
base SHA: 41547df810918dad7eb7d1dffe49f1ac26a2013a
final SHA: 4ecfcbad0bed7344c1ac5857aa2c010980a88c56
```

Цель проверки:

```text
подтвердить или опровергнуть готовность Stage 4B к merge
```

Это не production deployment.

---

## 2. Главные ограничения

Запрещено:

```text
делать merge
создавать PR без отдельного разрешения
изменять main
запускать production deployment
подключать текущие legacy candles_1m/candles_1h
изменять monitor-data
перезапускать monitor-data collectors
менять production Paper DB
начинать Stage 5
писать Detector, Signal, Paper Entry или Trade Manager
```

Текущий production candle source остаётся заблокированным.

Разрешено использовать только:

```text
disposable Docker Compose
временную PostgreSQL 16
fixture canonical candles
чистый clone/worktree
```

Если для выполнения проверки требуется изменить код — не исправлять молча. Сначала зафиксировать проблему и остановить соответствующую проверку.

---

## 3. Обязательные файлы для чтения

Перед запуском прочитать в `paper-trading-engine` на SHA `4ecfcbad...`:

```text
HANDOFF.md
CURRENT_STATE.md
TODO.md
README.md

docs/architecture/LEVELS_CONTRACT.md
docs/stages/STAGE_04_REPORT.md
docs/stages/STAGE_04_EVIDENCE.md
docs/stages/STAGE_04_OPEN_ISSUES.md
docs/stages/STAGE_04B_CI_EVIDENCE.md

.github/workflows/stage4b-contract.yml

docker-compose.stage4.yml
docker-compose.stage4-test.yml

migrations/011_stage4_levels.sql
migrations/011a_stage4_levels_schema.sql
migrations/011b_stage4_levels_runs.sql
migrations/011c_stage4_levels_publish.sql
migrations/011d_stage4_levels_events.sql
migrations/011e_stage4_levels_views.sql
migrations/011f_stage4_levels_atomic_lifecycle.sql
migrations/011g_stage4_levels_runtime_contract.sql
migrations/011h_stage4_levels_checkpoint_lease.sql
migrations/011i_stage4_levels_run_identity.sql
migrations/011j_stage4_levels_retest_confirmation.sql
migrations/011k_stage4_levels_retest_publish_order.sql
migrations/011l_stage4_levels_event_integrity.sql
migrations/011m_stage4_levels_retest_observations.sql

scripts/migrate.py
scripts/stage4_levels_acceptance.sql
scripts/stage4_levels_rebuild.py
scripts/init_stage4_roles.sql
scripts/init_stage4_levels_runtime_roles.sql

src/paper_engine/market_data/canonical_candle_reader.py
src/paper_engine/market_data/levels/engine.py
src/paper_engine/market_data/levels/repository.py
src/paper_engine/runtime/stage4_levels.py
src/paper_engine/runtime/stage4_levels_once.py

tests/unit/test_stage4b_levels_engine.py
tests/unit/test_stage4b_levels_load.py
tests/unit/test_stage4b_migration_bundle.py
```

Не доверять только итоговому отчёту. Проверять фактический код и runtime.

---

## 4. Безопасная подготовка Git

Работать только в новом чистом clone или отдельном worktree.

Не использовать существующий dirty worktree проекта.

Рекомендуемый порядок:

```bash
mkdir -p ~/stage4b-acceptance
cd ~/stage4b-acceptance

git clone git@github.com:shamilmirz/paper-trading-engine.git
cd paper-trading-engine

git fetch origin --prune
git checkout --detach 4ecfcbad0bed7344c1ac5857aa2c010980a88c56
```

Зафиксировать:

```bash
git branch --show-current
git rev-parse HEAD
git rev-parse origin/main
git status --short
git log -5 --oneline
```

Ожидается:

```text
HEAD = 4ecfcbad0bed7344c1ac5857aa2c010980a88c56
origin/main = 41547df810918dad7eb7d1dffe49f1ac26a2013a
working tree clean
```

Дополнительно:

```bash
git diff --check origin/main...HEAD
git diff --stat origin/main...HEAD
git diff --name-only origin/main...HEAD
```

Если SHA отличается — остановиться.

---

## 5. Проверка среды

Зафиксировать версии:

```bash
python3 --version
docker --version
docker compose version
git --version
```

Требования:

```text
Python 3.12
Docker доступен
Docker Compose v2
PostgreSQL acceptance через образ PostgreSQL 16 из Stage 4 test Compose
```

Проверить свободное место:

```bash
df -h /
docker system df
```

Не удалять чужие Docker volumes/images/containers.

---

## 6. Статические проверки

Создать локальное окружение проекта и выполнить:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -e '.[test]'

python -m compileall -q src scripts tests
ruff check src scripts tests
ruff format --check src scripts tests
mypy src scripts/migrate.py
pytest -q tests/unit
```

Ожидаемый минимум:

```text
compileall: PASS
ruff check: PASS
ruff format --check: PASS
mypy: PASS
unit tests: 161 passed или больше
```

Если количество тестов изменилось, указать точное фактическое число.

Отдельно выполнить:

```bash
pytest -q tests/unit/test_stage4b_migration_bundle.py
pytest -q tests/unit/test_stage4b_levels_engine.py
pytest -q tests/unit/test_stage4b_levels_load.py
```

Проверка нагрузки должна доказать:

```text
1100 symbols
batch size <= 100
distance prefilter
bounded processing
```

---

## 7. Проверка production Compose-контракта

Использовать только `docker compose config`. Production services не запускать.

Задать временные значения окружения, не содержащие реальных секретов:

```bash
export STAGE4_SCANNER_DB_DSN='postgresql://scanner@paper-db/paper'
export STAGE4_GROWTH_DB_DSN='postgresql://growth@paper-db/paper'
export STAGE4_CANDIDATE_STATUS_DB_DSN='postgresql://status@paper-db/paper'
export STAGE4_HEARTBEAT_DB_DSN='postgresql://heartbeat@paper-db/paper'
export MARKET_DATA_DSN='postgresql://reader@market-db/market'
export LEVELS_BINANCE_SOURCE_CONTRACT_STATUS='BLOCKED'
export LEVELS_BYBIT_SOURCE_CONTRACT_STATUS='BLOCKED'
export LEVELS_BINANCE_DB_DSN='postgresql://levels-binance@paper-db/paper'
export LEVELS_BYBIT_DB_DSN='postgresql://levels-bybit@paper-db/paper'
export LEVELS_BINANCE_SYMBOLS='BTCUSDT'
export LEVELS_BYBIT_SYMBOLS='BTCUSDT'
export LEVELS_BINANCE_HISTORY_START='2024-01-01T00:00:00+00:00'
export LEVELS_BYBIT_HISTORY_START='2024-01-01T00:00:00+00:00'
```

Выполнить:

```bash
docker compose -f docker-compose.stage4.yml config > /tmp/stage4b-production-compose.txt
docker compose -f docker-compose.stage4.yml config --services
```

Должно быть ровно четыре application service:

```text
paper-scanner-binance
paper-scanner-bybit
paper-levels-binance
paper-levels-bybit
```

Доказать отсутствие:

```text
fixture database
LEVELS_FIXTURE_MODE=1
paper-growth-*
per-symbol worker
production credentials в репозитории
```

Production Compose не запускать, потому что canonical candles ещё не одобрены.

---

## 8. Запуск disposable PostgreSQL 16 и Stage 4

Задать только тестовые пароли:

```bash
export PAPER_DB_ADMIN_PASSWORD='paper-admin-test'
export MARKET_DB_ADMIN_PASSWORD='market-admin-test'
export MARKET_READER_PASSWORD='reader-test'
export STAGE4_SCANNER_PASSWORD='scanner-test'
export STAGE4_GROWTH_PASSWORD='growth-test'
export STAGE4_STATUS_PASSWORD='status-test'
export STAGE4_HEARTBEAT_PASSWORD='heartbeat-test'
export STAGE4_LEVELS_BINANCE_PASSWORD='levels-binance-test'
export STAGE4_LEVELS_BYBIT_PASSWORD='levels-bybit-test'
```

Перед запуском:

```bash
docker compose -f docker-compose.stage4-test.yml config > /tmp/stage4b-test-compose.txt
docker compose -f docker-compose.stage4-test.yml config --services
```

Запустить:

```bash
docker compose -f docker-compose.stage4-test.yml up -d --build --wait
```

Зафиксировать:

```bash
docker compose -f docker-compose.stage4-test.yml ps
docker compose -f docker-compose.stage4-test.yml logs --no-color > /tmp/stage4b-initial.log
```

Все обязательные сервисы должны быть `Up/healthy`.

---

## 9. Проверка миграции 011

Главная цель — доказать, что `011` является одной атомарной версией, несмотря на fragments `011a`–`011m`.

В disposable базе проверить:

```sql
SELECT version, name, checksum
FROM schema_migrations
WHERE version = 11;
```

Ожидается ровно одна строка версии `11`.

Затем повторно запустить штатную миграцию проекта тем же способом, которым она запускается в Compose.

Если внутри контейнера доступна команда:

```bash
python scripts/migrate.py
python scripts/migrate.py
```

использовать её.

Если миграция запускается отдельным migration service — повторно выполнить этот service/command.

Доказать:

```text
первый запуск применяет version 11 целиком
второй запуск сообщает already applied
checksum остаётся неизменным
никакие fragments не появляются отдельными версиями
```

Проверить PostgreSQL version:

```sql
SELECT version();
```

Требуется PostgreSQL 16.x.

---

## 10. Основной acceptance SQL

Выполнить:

```bash
docker compose -f docker-compose.stage4-test.yml exec -T stage4-paper-db \
  psql -U paper_admin -d stage4_disposable -v ON_ERROR_STOP=1 \
  -f /dev/stdin < scripts/stage4_levels_acceptance.sql
```

Должно быть доказано:

```text
Binance initial READY
Bybit initial READY
Binance minute READY
Bybit minute READY
immutable definitions
staging invisibility
FAILED run preserves previous READY
one BUILDING run per exchange/kind
atomic lifecycle events
atomic metrics
atomic watermarks
retest observation separated from confirmed retest
```

Сохранить полный вывод:

```bash
... > /tmp/stage4b-acceptance-sql.log 2>&1
```

---

## 11. Проверка ролей и изоляции бирж

Проверить, что Binance writer не может писать Bybit:

```bash
docker compose -f docker-compose.stage4-test.yml exec -T stage4-paper-db \
  sh -ec 'if PGPASSWORD="$STAGE4_LEVELS_BINANCE_PASSWORD" \
  psql -h 127.0.0.1 -U paper_levels_binance_writer -d stage4_disposable \
  -v ON_ERROR_STOP=1 \
  -c "SELECT public.levels_assert_exchange('"'"'bybit'"'"')"; \
  then exit 1; else exit 0; fi'
```

Аналогично проверить Bybit writer против Binance.

Проверить, что Levels writers не имеют прямого DML на Levels-owned tables и используют только разрешённые функции.

Проверить отсутствие write privileges на:

```text
accounts
reservations
account_ledger
financial_transactions
signals
paper_trades
candidate_events
scanner/growth-owned tables
```

Проверить, что старые неатомарные функции закрыты для writer-ролей.

---

## 12. Restart/replay idempotency

До restart получить counts:

```sql
SELECT concat_ws(',',
  (SELECT count(*) FROM levels),
  (SELECT count(*) FROM level_source_candles),
  (SELECT count(*) FROM level_touch_events),
  (SELECT count(*) FROM level_reaction_events),
  (SELECT count(*) FROM level_break_events),
  (SELECT count(*) FROM level_retest_events),
  (SELECT count(*) FROM level_retest_observation_events)
);
```

Перезапустить только Levels-контейнеры disposable среды:

```bash
docker compose -f docker-compose.stage4-test.yml restart \
  paper-levels-binance paper-levels-bybit
```

Дождаться health:

```bash
for attempt in $(seq 1 30); do
  docker compose -f docker-compose.stage4-test.yml ps
  sleep 2
done
```

После restart получить те же counts.

Обязательное условие:

```text
counts before = counts after
никаких duplicate definitions/events
READY pointers не откатились
watermarks не продвинулись ошибочно
heartbeats восстановились
```

---

## 13. Проверка FAILED run

Создать только в disposable базе контролируемый FAILED run согласно существующим acceptance functions.

Доказать:

```text
previous READY pointer не меняется
staging definitions не видны readers
staging events не видны readers
watermark не продвигается
run получает failure_class и failure_message
```

Не менять production DB.

---

## 14. Проверка source gate

Проверить fail-closed поведение production runtime без запуска production Compose.

При статусах:

```text
BLOCKED
UNKNOWN
UNVERIFIED
```

Levels runtime должен завершаться ошибкой до Market Data processing.

Проверить, что production Reader обращается только к:

```text
public.candles_1m_canonical
```

И не содержит обращений к:

```text
public.candles_1m
public.candles_1h
public.candles_1h_raw
```

Проверить read-only startup gate для роли:

```text
paper_market_reader
```

Текущую реальную Market DB не подключать до отдельного `APPROVED` по canonical candles.

---

## 15. GitHub Actions

После локальной серверной проверки запустить вручную workflow:

```text
stage4b-contract
branch: stage/04b-levels
```

Через GitHub UI:

```text
Actions
→ stage4b-contract
→ Run workflow
→ stage/04b-levels
```

Либо через `gh`, если авторизация уже безопасно настроена:

```bash
gh workflow run stage4b-contract.yml --ref stage/04b-levels
gh run list --workflow stage4b-contract.yml --branch stage/04b-levels --limit 5
```

Не выводить токены.

Обязательные зелёные jobs:

```text
static-unit
docker-acceptance
```

Сохранить:

```text
workflow run ID
URL
commit SHA
job names
conclusion
```

Если workflow падает — скачать/сохранить точные job logs и не выдавать PASS.

---

## 16. Secret и boundary scan

Выполнить:

```bash
git grep -nE 'BEGIN (RSA|OPENSSH|EC) PRIVATE KEY|ghp_[A-Za-z0-9]{20,}' -- . || true
git grep -nE 'postgresql://[^$][^ ]+:[^$][^ ]+@' -- . || true
git diff origin/main...HEAD --name-only | grep -E '(^|/)monitor-data/' || true
git grep -nE 'INSERT INTO .*\b(signals|paper_trades|account_ledger|financial_transactions)\b' -- src migrations/011*.sql || true
```

Ожидается отсутствие секретов, `monitor-data` изменений и кода следующих этапов.

Не публиковать реальные DSN или пароли в отчёте.

---

## 17. Завершение disposable среды

После сбора evidence:

```bash
docker compose -f docker-compose.stage4-test.yml ps -a
docker compose -f docker-compose.stage4-test.yml logs --no-color > /tmp/stage4b-final.log
docker compose -f docker-compose.stage4-test.yml down -v --remove-orphans
```

Убедиться, что production containers не затронуты.

---

## 18. Критерии verdict

### PASS

Разрешён только если одновременно:

```text
HEAD точно 4ecfcbad...
working tree clean
static/unit PASS
PostgreSQL 16 migration bundle применён и повторно проверен
Docker acceptance PASS
ровно четыре application services
roles/exchange isolation PASS
atomic READY/FAILED PASS
restart/replay без дублей PASS
source gate PASS
secret/boundary scan PASS
GitHub Actions static-unit GREEN
GitHub Actions docker-acceptance GREEN
```

Даже при PASS production deployment остаётся запрещён до approval canonical candles.

### PASS WITH ISSUES

Допустим только при некритичных документированных проблемах, которые не нарушают:

```text
атомарность
изоляцию бирж
restart/replay
source gate
миграции
безопасность ролей
```

### REJECT

Обязателен при любом из:

```text
migration failure/checksum conflict
Docker acceptance failure
partial READY publication
previous READY потерян после FAILED
duplicate definitions/events после restart
writer может писать другую биржу
writer имеет запрещённый direct DML
runtime читает legacy candles
production source запускается при BLOCKED
секреты в репозитории
несовпадение проверяемого SHA
```

---

## 19. Итоговый отчёт

Вернуть владельцу строго в формате:

```text
STAGE 4B — INDEPENDENT SERVER ACCEPTANCE REPORT

1. Verdict: PASS / PASS WITH ISSUES / REJECT
2. Repository
3. Branch
4. Expected SHA
5. Actual SHA
6. origin/main SHA
7. Working tree status
8. Server/OS
9. Python version
10. Docker version
11. Docker Compose version
12. PostgreSQL version
13. Static checks
14. Unit tests — exact count
15. Migration first run
16. Migration second run
17. schema_migrations version 11 evidence
18. Production Compose topology
19. Disposable Compose topology
20. Docker health
21. READY runs by exchange/kind
22. FAILED previous READY preservation
23. Atomic definitions/events/metrics/watermarks
24. Binance/Bybit isolation
25. Direct DML denial
26. Restart counts before
27. Restart counts after
28. Heartbeat recovery
29. 1100-symbol load result
30. Source gate result
31. Legacy candle reference scan
32. Secret scan
33. monitor-data unchanged proof
34. GitHub Actions run ID and URL
35. static-unit conclusion
36. docker-acceptance conclusion
37. What is proven
38. What is not proven
39. Found defects
40. Recommendation: merge / fix / reject
```

Приложить существенные команды и результаты в Markdown. Не ссылаться только на `/tmp` файлы.

---

## 20. Условие остановки

После отчёта:

```text
остановиться
не делать merge
не создавать production containers
не подключать реальную Market DB
не менять monitor-data
не начинать Stage 5
```

Окончательное решение о merge принимает владелец после независимой проверки отчёта.
