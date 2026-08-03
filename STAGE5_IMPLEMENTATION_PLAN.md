# STAGE 5 — UNIVERSAL TRADING CORE IMPLEMENTATION PLAN

## Назначение документа

Этот файл — главный рабочий план реализации `Stage 5 — Universal Trading Core` в репозитории:

```text
shamilmirz/paper-trading-engine
```

Он предназначен сразу для трёх ролей:

```text
1. Новый ChatGPT-чат — пишет и исправляет код через GitHub.
2. Агент paper-trading-architect на сервере — запускает реальные disposable-тесты и собирает evidence.
3. Архитектор-критик — проверяет код, тесты и отчёт, затем выдаёт следующему новому чату узкое корректирующее ТЗ.
```

Главный принцип работы:

```text
Не пытаться бесконечно доводить один и тот же чат до идеала.
Каждый новый чат получает точную следующую задачу от последнего доказанного SHA.
Принятые блоки не открываются заново без нового факта, регрессии или нарушения контракта.
Каждое следующее ТЗ должно уменьшать остаточный риск и приближать проект к полной цепочке сделки.
```

Этот план не разрешает `merge`, production deployment или начало Stage 6.

---

# 1. Актуальный старт Stage 5

## 1.1. Репозиторий реализации

```text
shamilmirz/paper-trading-engine
```

## 1.2. Закрытый предыдущий этап

```text
Stage 4: MERGED AND CLOSED
Stage 4B final SHA: 5bc45d002b0ca7265f8c21d89538f1a6aac64c6d
Stage 4 merge SHA: c8c4ac348c338ffa0ea64acd1efb5396914722b6
Stage 4 primary closeout SHA: 5d7c01445b47c04f87afb95b57928e83d40b52cb
Stage 4 final closeout SHA: c6b6b2d881d71ff596550febb5cd3746081d1cbb
GitHub Actions run: 30811265858
static-unit: success
docker-acceptance: success
177 tests passed
```

## 1.3. Точный стартовый base

Плановый base Stage 5:

```text
origin/main
c6b6b2d881d71ff596550febb5cd3746081d1cbb
```

Рабочая ветка:

```text
stage/05-trading-core
```

Плановая следующая миграция:

```text
migrations/012_stage5_trading_core.sql
```

Миграции `001–011` уже принадлежат предыдущим этапам и не изменяются.

Если к фактическому началу `origin/main` изменился, исполнитель обязан:

1. проверить, что новый commit является разрешённым продолжением закрытого Stage 4;
2. зафиксировать новый Base SHA в отчёте;
3. проверить последнюю migration version;
4. использовать следующий свободный номер только при наличии нового уже слитого migration;
5. не начинать работу от неизвестного или dirty base.

---

# 2. Приоритет источников требований

При конфликте исполнитель использует следующий порядок:

```text
1. docs/architecture/DATABASE_CONTRACT.md
2. docs/architecture/STATE_MACHINES.md
3. docs/architecture/ACCOUNTING_CONTRACT.md
4. docs/architecture/EXECUTION_CONTRACT.md
5. docs/architecture/SERVICE_BOUNDARIES.md
6. docs/architecture/FAILURE_RECOVERY.md
7. docs/architecture/DOMAIN_MODEL.md
8. DECISIONS.md
9. docs/architecture/TEST_STRATEGY.md
10. docs/MASTER_IMPLEMENTATION_PLAN.md
11. docs/PROJECT_MASTER_CHECKLIST.md
12. этот план
```

Если в плане обнаружена формулировка, противоречащая более высокому контракту, исполнитель не должен молча выбирать удобный вариант. Он обязан:

```text
- сохранить более высокий контракт;
- записать расхождение в STAGE_05_OPEN_ISSUES.md;
- предложить минимальную синхронизацию документации;
- не менять принятый финансовый смысл без отдельного решения владельца.
```

---

# 3. Конечная цель Stage 5

Создать универсальное торговое ядро, которое не знает математику конкретного детектора, но умеет безопасно обработать любой корректный универсальный сигнал.

Полная синтетическая цепочка Stage 5:

```text
Synthetic Universal Signal
→ Signal Validator
→ exact next canonical 1m entry candle
→ Position Sizing
→ TX-10 OPEN_POSITION
→ Reservation
→ Entry Commission
→ OPEN Trade
→ LONG или SHORT Trade Manager
→ TX-16 management candles
→ TX-11 Funding
→ TP / SL / TIMEOUT
→ TX-12 CLOSE_POSITION
→ Release Reservation
→ Exit Commission
→ Realized PnL
→ Ledger
→ Account Projection
→ Reconciliation
```

Stage 5 считается завершённым, только когда синтетические LONG и SHORT сценарии проходят весь путь в настоящем disposable PostgreSQL и после restart сохраняют корректный финансовый результат.

---

# 4. Что входит в Stage 5

Обязательно реализуются:

```text
Universal Signal schema и domain contract
Signal lifecycle TX-09
Signal Validator
entry window и exact-candle identity
Position Sizing
instrument rules abstraction для synthetic acceptance
Paper Entry TX-10
Reservations
immutable ENTRY snapshot
Trade financial lifecycle
Trade management lifecycle
Trade Manager LONG
Trade Manager SHORT
TP
SL
SL FIRST
TIMEOUT
adverse slippage
entry и exit commissions
Funding TX-11
late eligible funding для CLOSED trade
Trade Close TX-12
approved Accounting Adjustment TX-13
Reconciliation incidents TX-14
Account lifecycle/reconciliation status TX-15
Trade management TX-16A/B/C
execution events
immutable execution market snapshots
restart/replay/idempotency/concurrency
least-privilege database roles
Stage 5 runtime services
Docker disposable acceptance
GitHub Actions Stage 5 contract
Stage 5 report/evidence/open issues
```

---

# 5. Что не входит в Stage 5

Запрещено реализовывать:

```text
реальную математику Level Divergence
реальную математику Short Squeeze
Detector runtime
Detector attempts TX-08 production path
production synthetic signal generator
production Scheduler
Dashboard
production Health Monitor
production deployment
реальный rebuild Levels
исправление monitor-data
изменение старых collectors
Stage 6 или Stage 7
```

Stage 5 может создать универсальную таблицу `signals` и полный TX-09/TX-10 consumer contract, но реальные сигналы детекторов появятся только на Stage 6 и Stage 7.

Для acceptance разрешён только тестовый synthetic signal publisher:

```text
- fixture, test helper или one-shot acceptance script;
- существует только в tests/scripts/disposable Compose;
- не входит в production Compose;
- не запускается как production service;
- не маскируется под реальный detector.
```

---

# 6. Неподвижные архитектурные инварианты

## 6.1. Финансовая истина

```text
Ledger — единственный источник финансовой истины.
```

Инварианты:

```text
cash_balance = available_balance + reserved_balance
equity = cash_balance
realized_pnl = sum(account_ledger.realized_delta)
```

Stage 5 не создаёт вторую бухгалтерию и не хранит отдельный «быстрый баланс», способный расходиться с ledger.

## 6.2. Существующий Stage 2 foundation переиспользуется

Нельзя дублировать:

```text
trader_profiles
paper_accounts
financial_transactions
account_ledger
account_status_events
TX-17 initialization
canonical_operation_set
account replay
```

Новые TX-10/11/12/13 должны использовать существующие:

```text
financial_transactions
account_ledger
account version
canonical operation sets
ownership constraints
append-only ledger
```

## 6.3. Decimal only

Запрещён `float` для:

```text
price
quantity
notional
collateral
commission
funding
PnL
risk
leverage
slippage
percent
instrument limits
```

Разрешены:

```text
Decimal
PostgreSQL NUMERIC
строковая сериализация Decimal в JSON evidence
```

## 6.4. UTC only

Все timestamps:

```text
timezone-aware
normalized to UTC
stored as TIMESTAMPTZ
```

Naive datetime должен fail closed.

## 6.5. Положительное quantity

```text
trade.quantity > 0
```

Знак направления хранится только в:

```text
trade.side = LONG или SHORT
```

## 6.6. Финансовый и операционный статусы сделки разделены

Финансовые состояния:

```text
OPEN
CLOSED_TP
CLOSED_SL
CLOSED_TIMEOUT
```

Операционные management states:

```text
ACTIVE
WAITING_FOR_DATA
RECONCILIATION_REQUIRED
```

Запрещено добавлять финансовые trade states:

```text
DATA_ERROR
CANCELLED
ERROR
```

Отсутствие market data не закрывает и не отменяет финансово открытую сделку.

## 6.7. Collateral-only reservation

Резервируется только:

```text
original collateral
```

Не резервируются:

```text
entry fee
exit fee
safety buffer
будущий funding
ожидаемый убыток
```

Комиссия входа списывается с available balance. Safety buffer является только входной проверкой.

## 6.8. Cash-based sizing

Риск рассчитывается от cash balance, а не от mark-to-market unrealized equity.

Нереализованный PnL открытых сделок не должен менять размер новой сделки.

## 6.9. Exact next candle

Решение существует на закрытой trigger-свече.

Вход разрешён только по `open` точной следующей канонической минутной свечи:

```text
expected_entry_open_ts = trigger_candle_close_ts
```

Запрещено:

```text
заменить отсутствующую свечу более поздней;
использовать текущую незакрытую свечу;
входить по close trigger-свечи;
входить по текущей цене;
```

## 6.10. Immutable execution evidence

Для каждого ENTRY/MANAGEMENT/EXIT/TIMEOUT сохраняется immutable snapshot с:

```text
exchange
symbol
interval
open_ts
close_ts
OHLC
source identity
source timestamps
quality
checksum
purpose
trade_id
```

Исправление внешней свечи задним числом не меняет уже сохранённый snapshot.

## 6.11. Один финансовый group — одно обновление projection

TX-10, TX-11, TX-12 и TX-13:

```text
- создают immutable financial header;
- создают точный обязательный набор ledger rows;
- обновляют account projection один раз;
- увеличивают account.version ровно на 1;
- либо commit целиком, либо rollback целиком.
```

## 6.12. Reconciliation не исправляет деньги

TX-14 только обнаруживает и сохраняет incident.

Reconciliation не имеет права:

```text
менять balances;
писать ledger;
закрывать trade;
освобождать reserve;
менять solvency;
менять trade.management_status напрямую.
```

---

# 7. Производственная граница

На момент Stage 5:

```text
Production canonical candles: BLOCKED
Production funding source proof: недостаточен для финансового production use
Production deployment: запрещён
```

Это не блокирует Stage 5 implementation, потому что Stage 5 должен быть доказан на:

```text
- disposable Paper DB;
- disposable canonical candle fixtures;
- synthetic FundingEvent fixtures;
- synthetic Universal Signals;
- отдельном Docker Compose project;
- без production DSN.
```

Production-конфигурация Stage 5 должна fail closed, если source contract не `APPROVED`.

Ни один test, script или Compose Stage 5 не должен случайно принять production Market DB DSN по умолчанию.

---

# 8. Организация работы по новым чатам

Stage 5 делится на последовательные блоки:

```text
Stage 5A — Inventory, schema, roles and immutable evidence
Stage 5B — Domain math, Signal Validator and Position Sizing
Stage 5C — TX-09 and TX-10 Paper Entry
Stage 5D — TX-16 management and TX-12 close
Stage 5E — TX-11 funding and financial revision
Stage 5F — TX-13/14/15 reconciliation and corrections boundary
Stage 5G — Runtime, Docker, restart, concurrency and E2E
Stage 5H — CI, evidence, documentation and independent audit readiness
```

Каждый блок может выполняться новым чатом. Новый чат обязан:

1. прочитать этот план полностью;
2. прочитать текущий `CURRENT_STATE.md`, `HANDOFF.md`, `TODO.md` и Stage 5 evidence;
3. проверить фактический branch SHA;
4. не переделывать принятые блоки без доказанной необходимости;
5. писать код и тесты только своего блока и необходимых общих исправлений;
6. завершать логическим commit;
7. отдавать SHA и точный список недоказанного.

Архитектор-критик после каждого блока выдаёт один из verdict:

```text
ACCEPT BLOCK
ACCEPT WITH FORWARD DEBT
CORRECTION REQUIRED
REJECT BLOCK
```

`ACCEPT WITH FORWARD DEBT` означает:

```text
блок не открывается заново;
некритический долг переносится в конкретный будущий блок;
долг имеет owner, проверку и крайний Stage;
```

`CORRECTION REQUIRED` создаёт новому чату узкое ТЗ только на подтверждённые дефекты.

---

# 9. Обязательный Git preflight

Перед первым изменением кода:

```bash
git fetch origin --prune
git switch main
git pull --ff-only origin main
git branch --show-current
git rev-parse HEAD
git rev-parse origin/main
git status --short
git diff --stat
git diff --name-only
git log -10 --oneline --decorate
```

Ожидаемый старт:

```text
branch: main
HEAD: c6b6b2d881d71ff596550febb5cd3746081d1cbb
origin/main: c6b6b2d881d71ff596550febb5cd3746081d1cbb
worktree: clean
```

Затем:

```bash
git switch -c stage/05-trading-core
```

Запрещено:

```text
git reset --hard
git clean
git add .
git add -A
git stash без разрешения владельца
force-push без отдельного разрешения
rebase уже опубликованных проверенных SHA без причины
```

Если рабочее дерево содержит чужие изменения, исполнитель не удаляет их и не смешивает со Stage 5.

---

# 10. Stage 5A — Inventory, schema, roles and immutable evidence

## 10.1. Цель

Создать database foundation Stage 5 поверх уже существующего Stage 2 accounting foundation.

## 10.2. До написания миграции

Исполнитель составляет и сохраняет schema gap matrix:

| Контрактная сущность | Уже существует | Что отсутствует | Что расширяется | Writer | Readers |
|---|---:|---|---|---|---|
| trader_profiles | да | только если нужны constraints | без дублирования | Profile Admin | Entry |
| paper_accounts | да | Stage 5 projection usage | только необходимые refs/indexes | financial TX | Entry/Managers/Reconciliation |
| financial_transactions | да | Stage 5 trade/source refs при необходимости | immutable additive columns | TX-10/11/12/13 | Audit |
| account_ledger | да | ничего параллельного | только additive integrity | financial TX | Replay/Audit |
| account_status_events | да | TX-15 paths | additive evidence fields при необходимости | status owner | Audit |
| execution_events | да | Stage 5 event contract | additive trade/snapshot refs | TX-10/11/12/16 | Audit |
| signals | нет | создать | новая таблица | TX-08 create, TX-09/10 update | Entry/Audit |
| signal_events | нет | создать | append-only | TX-08/09/10 | Audit |
| reservations | нет | создать | lifecycle projection | TX-10 create, TX-12 release | Managers/Audit |
| paper_trades | нет | создать | financial + management dimensions | TX-10, matching Manager | Audit |
| execution_market_snapshots | нет | создать | immutable | TX-10/12/16 | Replay/Audit |
| funding_charges | нет | создать | immutable financial evidence | TX-11 | Audit |
| reconciliation_incidents | нет | создать | incident lifecycle | TX-14 owner | Accounting/Managers |

Gap matrix добавляется в:

```text
docs/stages/STAGE_05_SCHEMA_GAP.md
```

## 10.3. Migration bundle

Плановая canonical migration:

```text
migrations/012_stage5_trading_core.sql
```

Если файл становится слишком большим, разрешён migration bundle:

```text
012_stage5_trading_core.sql
012a_stage5_types_and_tables.inc
012b_stage5_constraints_and_triggers.inc
012c_stage5_transaction_functions.inc
012d_stage5_roles_and_grants.inc
```

Canonical файл обязан включать fragments в точном отсортированном порядке через `\ir`.

Запрещено изменять checksums миграций `001–011`.

## 10.4. Таблица signals

Минимальный контракт:

```text
id UUID primary key
trader_profile_id UUID not null
candidate_event_id UUID nullable для synthetic/будущего detector handoff
exchange TEXT not null
symbol TEXT not null
side TEXT not null
strategy_version TEXT not null
detector_type TEXT not null
decision_ts TIMESTAMPTZ not null
trigger_candle_open_ts TIMESTAMPTZ not null
trigger_candle_close_ts TIMESTAMPTZ not null
expected_entry_open_ts TIMESTAMPTZ not null
entry_window_expires_at TIMESTAMPTZ not null
tp_price NUMERIC(38,18) not null
sl_price NUMERIC(38,18) not null
timeout_at TIMESTAMPTZ not null
level_run_id UUID nullable
market_snapshot JSONB not null
data_quality JSONB not null
signal_checksum TEXT not null
status TEXT not null
entry_status TEXT nullable
transition_version BIGINT not null
reason_code TEXT nullable
opened_trade_id UUID nullable
created_at TIMESTAMPTZ not null
updated_at TIMESTAMPTZ not null
```

Обязательные ограничения:

```text
side IN (LONG, SHORT)
status IN (NEW, VALIDATED, WAITING_ENTRY, OPENED, REJECTED, EXPIRED, DATA_ERROR, CANCELLED, ERROR)
entry_status IN (ACTIVE, WAITING_FOR_DATA) или NULL до инициализации
prices > 0
LONG: sl_price < expected entry area < tp_price
SHORT: tp_price < expected entry area < sl_price
trigger_candle_open_ts < trigger_candle_close_ts
expected_entry_open_ts = trigger_candle_close_ts
entry_window_expires_at >= expected_entry_open_ts
timeout_at > expected_entry_open_ts
one opened trade per signal
```

Проверка ориентации TP/SL повторяется после фактической entry fill до TX-10 commit.

## 10.5. Таблица signal_events

Append-only lifecycle evidence:

```text
id
signal_id
transition_version
path
status_before
status_after
entry_status_before
entry_status_after
reason_code
candle_identity
quality_evidence
correlation_id
created_at
```

Уникальность:

```text
signal_id + transition_version
```

UPDATE/DELETE запрещены trigger-ом.

## 10.6. Таблица paper_trades

Минимальный контракт:

```text
id UUID primary key
signal_id UUID unique not null
trader_profile_id UUID not null
account_id UUID not null
exchange TEXT not null
symbol TEXT not null
side TEXT not null
financial_status TEXT not null
management_status TEXT not null
entry_price_raw NUMERIC(38,18) not null
entry_price_effective NUMERIC(38,18) not null
quantity NUMERIC(38,18) not null
notional NUMERIC(38,18) not null
collateral_amount NUMERIC(38,18) not null
entry_fee NUMERIC(38,18) not null
tp_price NUMERIC(38,18) not null
sl_price NUMERIC(38,18) not null
opened_at TIMESTAMPTZ not null
opened_candle_open_ts TIMESTAMPTZ not null
timeout_at TIMESTAMPTZ not null
last_processed_candle_open_ts TIMESTAMPTZ nullable
closed_at TIMESTAMPTZ nullable
closed_candle_open_ts TIMESTAMPTZ nullable
close_reason TEXT nullable
exit_price_raw NUMERIC(38,18) nullable
exit_price_effective NUMERIC(38,18) nullable
gross_pnl NUMERIC(38,18) not null default 0
entry_commission_total NUMERIC(38,18) not null
exit_commission_total NUMERIC(38,18) not null default 0
funding_total NUMERIC(38,18) not null default 0
net_pnl NUMERIC(38,18) not null default 0
financial_version BIGINT not null
management_version BIGINT not null
open_financial_transaction_id UUID not null
close_financial_transaction_id UUID nullable
entry_snapshot_id UUID not null
exit_snapshot_id UUID nullable
financial_updated_at TIMESTAMPTZ not null
created_at TIMESTAMPTZ not null
updated_at TIMESTAMPTZ not null
```

Constraints:

```text
quantity > 0
notional > 0
collateral_amount > 0
financial_status IN (OPEN, CLOSED_TP, CLOSED_SL, CLOSED_TIMEOUT)
management_status IN (ACTIVE, WAITING_FOR_DATA, RECONCILIATION_REQUIRED)
financial_version >= 1
management_version >= 1
OPEN не имеет close fields
CLOSED_* имеет полный close evidence
один successful close financial transaction
```

`financial_version`:

```text
TX-10 successful open → 1
successful TX-11 funding → +1
successful TX-12 close → +1
late successful TX-11 funding on CLOSED trade → +1
```

Trade lifecycle при late funding не открывается заново.

## 10.7. Таблица reservations

```text
id UUID primary key
account_id UUID not null
trade_id UUID unique not null
open_financial_transaction_id UUID unique not null
release_financial_transaction_id UUID unique nullable
original_collateral NUMERIC(38,18) not null
status TEXT not null
created_at TIMESTAMPTZ not null
released_at TIMESTAMPTZ nullable
```

Statuses:

```text
ACTIVE
RELEASED
```

Constraints:

```text
original_collateral > 0
ACTIVE → released_at/release_tx null
RELEASED → released_at/release_tx not null
one reservation per trade
release amount always equals original collateral
TX-11 не изменяет reservation
TX-14 не изменяет reservation
```

## 10.8. execution_market_snapshots

```text
id
trade_id
purpose
exchange
symbol
interval
open_ts
close_ts
open
high
low
close
volume_base
volume_quote
quality
source_identity
source_updated_at
ingested_at
source_checksum
snapshot_checksum
created_at
```

Purposes:

```text
ENTRY
MANAGEMENT
EXIT
TIMEOUT
```

Snapshot immutable. Purpose после вставки не меняется.

## 10.9. funding_charges

```text
id
trade_id
account_id
financial_transaction_id
exchange
symbol
funding_event_ts
source_identity
normalized_rate
reference_price
quantity
side_multiplier
signed_funding
trade_financial_version_after
created_at
```

Уникальность:

```text
trade_id + exchange + funding_event_ts + source_identity
```

## 10.10. reconciliation_incidents

```text
id
entity_type
entity_id
account_id nullable
trade_id nullable
check_type
observation_identity
status
severity
evidence JSONB
checksum
opened_at
acknowledged_at nullable
resolved_at nullable
resolution_evidence JSONB nullable
```

Statuses:

```text
OPEN
ACKNOWLEDGED
RESOLVED
```

## 10.11. Database roles

Минимальные роли:

```text
paper_entry_writer
paper_trade_manager_long_writer
paper_trade_manager_short_writer
paper_reconciliation_writer
paper_accounting_status_writer
paper_accounting_adjustment_writer
paper_trading_auditor
```

Рекомендуемая модель прав:

```text
runtime roles не получают прямой DML на финансовые таблицы;
они получают EXECUTE только на свои SECURITY DEFINER transaction functions;
каждая функция использует фиксированный search_path;
PUBLIC execute revoked;
manager LONG не может управлять SHORT;
manager SHORT не может управлять LONG;
Reconciliation не может вызвать financial functions;
Dashboard/auditor SELECT-only;
```

## 10.12. Transaction function surface

Плановые функции:

```text
transition_signal_tx09(...)
open_position_tx10(...)
apply_funding_tx11(...)
close_position_tx12(...)
apply_account_adjustment_tx13(...)
open_reconciliation_incident_tx14(...)
transition_reconciliation_incident_tx14(...)
transition_account_status_tx15(...)
process_management_candle_tx16a(...)
enter_trade_reconciliation_tx16b(...)
resolve_trade_reconciliation_tx16c(...)
```

Python repository не должен выполнять вручную набор несвязанных INSERT/UPDATE для финансовой транзакции.

## 10.13. Контрольная точка Stage 5A

Блок принимается только если:

```text
migration 012 проходит на clean DB;
migration rerun idempotent;
checksums 001–011 не изменены;
таблицы и constraints соответствуют contract;
immutable triggers работают;
roles изолированы;
Reconciliation не имеет финансовых write permissions;
LONG manager не может управлять SHORT;
SHORT manager не может управлять LONG;
нет production detector или production synthetic publisher;
```

---

# 11. Stage 5B — Domain math, Signal Validator and Position Sizing

## 11.1. Domain modules

Плановая структура:

```text
src/paper_engine/domain/signals/
src/paper_engine/domain/trades/
src/paper_engine/execution/signal_validator.py
src/paper_engine/execution/position_sizing.py
src/paper_engine/execution/slippage.py
src/paper_engine/execution/instrument_rules.py
src/paper_engine/trading/pnl.py
src/paper_engine/trading/commissions.py
src/paper_engine/trading/funding.py
src/paper_engine/trading/exit_decision.py
```

Фактические пути могут быть адаптированы к текущей структуре, но domain, persistence и runtime не должны смешиваться в одном монолитном файле.

## 11.2. Universal Signal contract

Signal Validator проверяет минимум:

```text
profile существует;
profile enabled;
profile exchange == signal exchange;
profile side == signal side;
profile detector_type == signal detector_type;
profile strategy_version == signal strategy_version;
account существует;
account lifecycle ACTIVE;
account solvency SOLVENT;
account reconciliation CLEAN;
signal status NEW или VALIDATED по path;
signal checksum и required fields валидны;
trigger candle закрыта;
expected entry candle identity корректна;
entry window не истёк;
data quality допустима;
нет duplicate signal identity;
нет уже открытой сделки по signal;
cooldown соблюдён;
max_open_positions соблюдён;
max_open_positions_per_symbol соблюдён;
allow_same_symbol_across_profiles соблюдён;
TP/SL ориентированы правильно;
нет float;
нет future timestamp;
```

Каждый reject имеет стабильный `reason_code`, а не произвольный текст.

Пример групп reason codes:

```text
PROFILE_DISABLED
PROFILE_MISMATCH
ACCOUNT_NOT_ACTIVE
ACCOUNT_INSOLVENT
ACCOUNT_RECONCILIATION_REQUIRED
SIGNAL_DUPLICATE
SIGNAL_EXPIRED
ENTRY_CANDLE_MISSING
ENTRY_CANDLE_INVALID
DATA_QUALITY_REJECTED
COOLDOWN_ACTIVE
MAX_OPEN_POSITIONS
MAX_SYMBOL_POSITIONS
SAME_SYMBOL_FORBIDDEN
INVALID_TP_SL
INSTRUMENT_RULES_UNAVAILABLE
INSUFFICIENT_AVAILABLE_CASH
POSITION_BELOW_MINIMUM
POSITION_ROUNDS_TO_ZERO
```

## 11.3. Position sizing inputs

```text
cash_balance
available_balance
risk_pct
leverage
max_position_notional
instrument_notional_cap
minimum_notional
quantity_step
price_tick
raw_entry_price
sl_price
entry_fee_rate
entry_safety_buffer_amount
slippage_bps
side
```

В Stage 5 production instrument metadata остаётся fail closed. Для disposable tests используется versioned synthetic `InstrumentTradingRules` fixture.

## 11.4. Entry slippage

```text
slippage_fraction = slippage_bps / 10000
LONG effective_entry  = raw_entry * (1 + slippage_fraction)
SHORT effective_entry = raw_entry * (1 - slippage_fraction)
```

Effective entry должен оставаться положительным.

## 11.5. Stop distance

```text
LONG stop_distance_fraction  = (effective_entry - sl_price) / effective_entry
SHORT stop_distance_fraction = (sl_price - effective_entry) / effective_entry
```

Обязательно:

```text
stop_distance_fraction > 0
```

## 11.6. Risk and notional

```text
cash_balance = available_balance + reserved_balance
risk_amount = cash_balance * risk_pct
risk_based_notional = risk_amount / stop_distance_fraction
```

Затем:

```text
candidate_notional = min(
    risk_based_notional,
    max_position_notional,
    instrument_notional_cap,
    available leverage capacity
)
```

Quantity:

```text
raw_quantity = candidate_notional / effective_entry
quantity = floor_to_step(raw_quantity, quantity_step)
notional = quantity * effective_entry
collateral = notional / leverage
entry_fee = notional * entry_fee_rate
```

Входной cash gate:

```text
available_balance >= collateral + entry_fee + entry_safety_buffer_amount
```

Safety buffer не создаёт ledger row.

После округления повторно проверяются:

```text
quantity > 0
notional >= minimum_notional
notional <= max_position_notional
notional <= instrument_notional_cap
collateral > 0
post_transaction_cash_balance >= 0
```

## 11.7. Rounding

Рекомендуемый безопасный контракт:

```text
quantity округляется вниз к quantity_step;
TP/SL/price приводятся к price_tick детерминированно по versioned rule;
финансовые суммы quantize к currency precision только в одном утверждённом месте;
никакого implicit binary float rounding;
```

Конкретный rounding mode записывается в config и immutable execution event.

## 11.8. Commission formulas

```text
entry_fee = effective_entry_price * quantity * entry_fee_rate
exit_fee  = effective_exit_price  * quantity * exit_fee_rate
```

Ledger signs:

```text
ENTRY_COMMISSION available_delta = -entry_fee
ENTRY_COMMISSION realized_delta  = -entry_fee
EXIT_COMMISSION available_delta  = -exit_fee
EXIT_COMMISSION realized_delta   = -exit_fee
```

Обязательные ledger rows создаются даже при нулевой fee rate.

## 11.9. PnL formulas

```text
LONG gross_pnl  = (effective_exit - effective_entry) * quantity
SHORT gross_pnl = (effective_entry - effective_exit) * quantity
```

```text
net_pnl = gross_pnl - entry_fee - exit_fee + cumulative_signed_funding
```

Account realized result получается из ledger, а не из прямой записи `trade.net_pnl`.

## 11.10. Контрольная точка Stage 5B

Unit tests обязаны доказать:

```text
LONG/SHORT sizing;
cash-based risk;
reserved cash не считается available, но входит в cash risk base;
all caps;
minimum notional;
quantity step floor;
price tick behavior;
entry safety buffer;
zero fee rows contract;
negative/zero stop rejection;
float rejection;
UTC enforcement;
entry adverse slippage;
LONG/SHORT PnL;
positive quantity;
```

---

# 12. Stage 5C — TX-09 and TX-10 Paper Entry

## 12.1. TX-09 Signal lifecycle

Полный путь:

```text
NEW
→ VALIDATED
→ WAITING_ENTRY
→ OPENED
```

Terminal paths:

```text
REJECTED
EXPIRED
DATA_ERROR
CANCELLED
ERROR
```

Entry status:

```text
unset
→ ACTIVE
или
→ WAITING_FOR_DATA
```

Разрешён переход:

```text
WAITING_FOR_DATA ↔ ACTIVE
```

только для той же exact entry candle identity и до закрытия entry window.

## 12.2. Exact candle lookup

Stage 5 должен расширить canonical candle boundary удобным exact lookup методом либо безопасным window query wrapper.

Запрос обязан возвращать только:

```text
exchange exact match
symbol exact match
interval 1m
open_ts == expected_entry_open_ts
is_closed = true
quality COMPLETE
close_ts + ingestion_grace <= as_of
```

Результаты:

```text
ровно 1 candle → ACTIVE
0 candles до expiry → WAITING_FOR_DATA
0 candles после expiry → DATA_ERROR или EXPIRED по versioned policy
>1 или checksum conflict → DATA_ERROR + incident
```

Более поздняя свеча никогда не подставляется.

## 12.3. TX-10 lock order

```text
1. signal_id
2. account_id
```

Внутри transaction повторно читаются и проверяются:

```text
Signal WAITING_ENTRY + ACTIVE
account ACTIVE + SOLVENT + CLEAN
profile version
open position limits
exact candle evidence
instrument rules version
position sizing
post cash
```

Внешняя предварительная validation не заменяет повторную проверку под locks.

## 12.4. TX-10 identity

```text
idempotency_key = signal_id + OPEN_POSITION
```

До snapshot создаётся `trade_id`, чтобы immutable ENTRY snapshot сразу имел полный identity.

## 12.5. TX-10 обязательные записи

Одна transaction создаёт:

```text
paper_trade OPEN
reservation ACTIVE
financial_transactions OPEN_POSITION
account_ledger RESERVE_POSITION
account_ledger ENTRY_COMMISSION
execution_market_snapshots ENTRY
execution_events ENTRY_OPENED
signal_events OPENED
```

И обновляет:

```text
signals.status = OPENED
signals.opened_trade_id = trade_id
paper_accounts projection/version
```

## 12.6. TX-10 ledger

Порядок rows:

```text
1. RESERVE_POSITION
2. ENTRY_COMMISSION
```

Deltas:

```text
RESERVE_POSITION:
available_delta = -collateral
reserved_delta  = +collateral
realized_delta  = 0

ENTRY_COMMISSION:
available_delta = -entry_fee
reserved_delta  = 0
realized_delta  = -entry_fee
```

## 12.7. TX-10 rollback

При любой ошибке отсутствуют все Stage 5 side effects:

```text
нет trade;
нет reservation;
нет financial header;
нет ledger rows;
нет snapshot;
нет execution event;
signal не OPENED;
account version не изменён;
solvency не изменена;
```

TX-10 не имеет права переводить account в INSOLVENT. Negative post cash полностью откатывается.

## 12.8. TX-10 concurrency

Обязательные сценарии:

```text
два Entry workers на один signal;
два signals на один account;
одновременно достигается max_open_positions;
одновременный same-symbol gate;
retry после ambiguous DB response;
```

Результат:

```text
один signal → максимум один trade;
один trade → один reservation;
один OPEN_POSITION group;
account versions без пропусков и дублей;
```

## 12.9. Контрольная точка Stage 5C

Блок принимается при доказательстве:

```text
полный TX-09 lifecycle;
exact candle без поздней подстановки;
TX-10 atomicity;
negative post-cash rollback;
idempotent retry;
concurrent double-entry protection;
правильный ledger;
immutable ENTRY snapshot;
правильный account projection;
```

---

# 13. Stage 5D — TX-16 management and TX-12 close

## 13.1. Runtime ownership

```text
paper-trade-manager-long управляет только LONG trades;
paper-trade-manager-short управляет только SHORT trades;
```

Каждый manager проверяет:

```text
trade.side;
profile side;
exchange;
manager identity;
financial_status OPEN;
management status;
next candle identity;
```

## 13.2. Candle processing order

Для каждой OPEN trade manager обрабатывает закрытые canonical 1m candles строго по `open_ts` после последнего watermark.

Запрещено:

```text
перепрыгивать gap;
обрабатывать свечи не по порядку;
продвигать watermark до commit;
обрабатывать незакрытую свечу;
```

## 13.3. Exit cause priority

Для каждой свечи:

```text
1. SL
2. TP
3. TIMEOUT
4. ordinary MANAGEMENT
```

Если TP и SL достигнуты в одной свече:

```text
SL FIRST
```

TIMEOUT не переопределяет SL/TP, если на той же первой допустимой timeout-свече был достигнут barrier.

## 13.4. LONG rules

```text
SL hit: candle.low <= sl_price
TP hit: candle.high >= tp_price
```

## 13.5. SHORT rules

```text
SL hit: candle.high >= sl_price
TP hit: candle.low <= tp_price
```

## 13.6. Conservative gap-aware raw exit

До adverse slippage определяется cause и raw price.

Рекомендуемый детерминированный контракт:

```text
LONG SL raw  = min(candle.open, sl_price)
SHORT SL raw = max(candle.open, sl_price)
LONG TP raw  = tp_price
SHORT TP raw = tp_price
TIMEOUT raw  = candle.close
```

То есть adverse stop gap учитывается, а положительное улучшение TP сверх цели не присваивается автоматически.

Если более высокий архитектурный документ к моменту реализации фиксирует иной gap contract, используется он и синхронизируется evidence.

## 13.7. Exit adverse slippage

```text
LONG effective_exit  = raw_exit * (1 - slippage_fraction)
SHORT effective_exit = raw_exit * (1 + slippage_fraction)
```

## 13.8. TX-16A ordinary management

Если exit cause отсутствует:

```text
create MANAGEMENT snapshot
create MANAGEMENT_CANDLE_PROCESSED execution event
advance last_processed_candle_open_ts
increment management_version
keep financial_status OPEN
no financial header
no ledger rows
```

## 13.9. Market data outage

Если exact next management candle отсутствует или invalid:

```text
financial_status остаётся OPEN
management_status → WAITING_FOR_DATA
watermark не перепрыгивает отсутствующую свечу
создаётся quality/management evidence
```

После появления той же ожидаемой valid candle:

```text
WAITING_FOR_DATA → ACTIVE
обработка продолжается с неё
```

## 13.10. TX-12 close lock order

```text
1. trade_id
2. account_id
```

## 13.11. TX-12 обязательные записи

```text
financial_transactions CLOSE_POSITION
account_ledger EXIT_COMMISSION
account_ledger REALIZED_PNL
account_ledger RELEASE_RESERVE
execution_market_snapshots EXIT или TIMEOUT
execution_events TRADE_CLOSED
reservation ACTIVE → RELEASED
paper_trade OPEN → CLOSED_*
paper_accounts projection/version/solvency
```

Порядок ledger rows:

```text
1. EXIT_COMMISSION
2. REALIZED_PNL
3. RELEASE_RESERVE
```

Deltas:

```text
EXIT_COMMISSION:
available_delta = -exit_fee
reserved_delta  = 0
realized_delta  = -exit_fee

REALIZED_PNL:
available_delta = +signed_gross_pnl
reserved_delta  = 0
realized_delta  = +signed_gross_pnl

RELEASE_RESERVE:
available_delta = +original_collateral
reserved_delta  = -original_collateral
realized_delta  = 0
```

## 13.12. Loss larger than collateral

Valid close не отклоняется и не обрезается.

Если после TX-12 cash отрицателен:

```text
account.solvency_status = INSOLVENT
```

Это происходит атомарно с close financial group.

Запрещено:

```text
clip loss;
оставлять trade OPEN из-за большого убытка;
создавать reconciliation mismatch только из-за отрицательного cash;
```

## 13.13. One-close protection

```text
один successful CLOSE_POSITION на trade
```

Два managers, retry или повторная свеча должны перечитать уже закрытый trade и сделать idempotent no-op.

## 13.14. Контрольная точка Stage 5D

Доказать:

```text
LONG TP;
LONG SL;
SHORT TP;
SHORT SL;
TP+SL same candle → SL;
SL gap;
TIMEOUT;
barrier priority над TIMEOUT;
ordinary TX-16 без ledger;
missing candle → OPEN + WAITING_FOR_DATA;
recovery на exact candle;
one-close concurrency;
negative cash → INSOLVENT;
reservation released exactly once;
```

---

# 14. Stage 5E — TX-11 Funding and financial revision

## 14.1. Funding source contract

Stage 5 принимает только нормализованный `FundingEvent`:

```text
exchange
symbol
funding_event_ts
normalized_rate
reference_price
source_identity
is_actual_funding_event
quality
```

Обязательно:

```text
is_actual_funding_event = true
quality = COMPLETE
reference_price > 0
source_identity non-empty
```

Production funding source остаётся blocked до отдельного доказательства. Disposable tests используют synthetic events.

## 14.2. Eligibility interval

```text
opened_at <= funding_event_ts < closed_at
```

Для OPEN trade:

```text
closed_at отсутствует, верхняя граница пока открыта
```

Funding event ровно в `closed_at` не входит.

## 14.3. Funding formula

```text
funding_notional = quantity * reference_price
side_multiplier:
LONG  = -1
SHORT = +1
signed_funding = funding_notional * normalized_rate * side_multiplier
```

Positive `signed_funding` увеличивает available/realized. Negative уменьшает.

## 14.4. TX-11 lock order

```text
1. trade_id
2. account_id
```

## 14.5. TX-11 writes

```text
financial_transactions APPLY_FUNDING
account_ledger FUNDING
funding_charges
execution_events FUNDING_APPLIED
paper_trade funding_total/net_pnl/financial_version
paper_accounts projection/version/solvency
```

Reservation не изменяется.

## 14.6. Idempotency

```text
trade_id + exchange + funding_event_ts + source_identity
```

Duplicate event:

```text
не создаёт второй charge;
не создаёт второй ledger row;
не увеличивает account/trade versions;
возвращает committed result/no-op evidence.
```

## 14.7. Late CLOSED funding

Eligible event может прийти после TX-12.

В этом случае:

```text
trade financial_status остаётся CLOSED_*;
financial_version увеличивается;
funding_total и net_pnl обновляются;
account projection/version/solvency обновляются;
старый опубликованный PnL считается stale по financial_version;
reservation не меняется;
trade lifecycle не открывается заново;
```

## 14.8. Insolvency from funding

TX-11 может атомарно установить INSOLVENT при отрицательном post cash.

TX-11 не может автоматически очистить INSOLVENT только из-за положительного funding, если contract требует approved capital/recovery path. Точное поведение синхронизируется с Accounting Contract и тестируется.

## 14.9. Контрольная точка Stage 5E

Доказать:

```text
LONG funding sign;
SHORT funding sign;
zero rate обязательный row;
open boundary included;
close boundary excluded;
duplicate no-op;
concurrent duplicate no-op;
late CLOSED funding;
financial_version increment;
negative funding insolvency;
reservation unchanged;
invalid/non-actual funding rejected;
```

---

# 15. Stage 5F — TX-13/14/15 reconciliation and correction boundaries

## 15.1. Reconciliation checks

Минимальный набор:

```text
ACCOUNT_LEDGER_PROJECTION_MISMATCH
FINANCIAL_HEADER_OPERATION_SET_MISMATCH
FINANCIAL_HEADER_COUNT_MISMATCH
FINANCIAL_HEADER_AGGREGATE_MISMATCH
ACCOUNT_VERSION_GAP
CROSS_ACCOUNT_LEDGER_OWNERSHIP
OPEN_TRADE_WITHOUT_ACTIVE_RESERVATION
ACTIVE_RESERVATION_WITHOUT_OPEN_TRADE
CLOSED_TRADE_WITH_ACTIVE_RESERVATION
SIGNAL_OPENED_WITHOUT_TRADE
TRADE_WITHOUT_OPEN_POSITION_GROUP
DUPLICATE_CLOSE_GROUP
DUPLICATE_FUNDING_CHARGE
TRADE_FINANCIAL_VERSION_MISMATCH
EXECUTION_EVENT_WITHOUT_SNAPSHOT
SNAPSHOT_CHECKSUM_MISMATCH
MANAGEMENT_WATERMARK_REGRESSION
STALE_WAITING_ENTRY
STUCK_OPEN_TRADE
```

## 15.2. TX-14 behavior

TX-14:

```text
создаёт incident;
дедуплицирует по entity/check/observation;
сохраняет immutable evidence;
не исправляет данные;
не пишет finance;
```

## 15.3. TX-15 account status

Accounting status owner может изменить только:

```text
lifecycle_status
reconciliation_status
```

Он не меняет:

```text
balances
ledger
solvency
trade
reservation
```

При подтверждённом financial mismatch:

```text
account.reconciliation_status → RECONCILIATION_REQUIRED
```

Это блокирует новые Entry, но не останавливает management/funding/close существующих trades.

## 15.4. TX-16B/C trade reconciliation state

После OPEN incident matching manager выполняет TX-16B:

```text
trade.management_status → RECONCILIATION_REQUIRED
execution event MANAGEMENT_RECONCILIATION_REQUIRED
```

После approved resolution matching manager выполняет TX-16C:

```text
ACTIVE, если next exact candle valid;
WAITING_FOR_DATA, если candle unavailable;
```

Reconciliation worker не обновляет trade напрямую.

## 15.5. TX-13 approved adjustment

Классы:

```text
CAPITAL
REALIZED_RESULT
RESERVE_REPAIR
```

Правила:

```text
CAPITAL:
- approved only;
- может менять cash;
- единственный путь INSOLVENT → SOLVENT при non-negative post cash и CLEAN reconciliation.

REALIZED_RESULT:
- available_delta = realized_delta;
- может сделать SOLVENT → INSOLVENT;
- не очищает INSOLVENT автоматически.

RESERVE_REPAIR:
- available_delta + reserved_delta = 0;
- realized_delta = 0;
- cash не меняется;
- solvency не меняется.
```

TX-13 не создаётся автоматически Reconciliation worker-ом. Требуется approved evidence.

## 15.6. Replay

Расширить существующий account replay так, чтобы он проверял все transaction types:

```text
INITIAL_DEPOSIT
OPEN_POSITION
APPLY_FUNDING
CLOSE_POSITION
ACCOUNT_ADJUSTMENT
```

Replay обязан отклонить:

```text
неполный group;
неправильный order operations;
неверный aggregate delta;
version gap;
cross-account ownership;
координированную порчу header + rows;
```

## 15.7. Контрольная точка Stage 5F

Доказать:

```text
каждый check создаёт только incident;
incident dedup;
TX-14 не может писать finance;
TX-15 меняет только разрешённые dimensions;
Entry блокируется при reconciliation REQUIRED;
existing trade продолжает management/close;
TX-16B/C ownership;
все три adjustment classes;
no silent auto-repair;
replay всех financial groups;
```

---

# 16. Stage 5G — Runtime services and Docker acceptance

## 16.1. Application services Stage 5

Ровно четыре Stage 5 logical/physical services:

```text
paper-entry
paper-trade-manager-long
paper-trade-manager-short
paper-reconciliation
```

Accounting остаётся shared domain/library и database contract, а не обязательным отдельным container.

## 16.2. Общий image

Допускается один image:

```text
paper-trading-engine:<git-sha>
```

Service выбирается через явный mode:

```text
SERVICE_MODE=entry
SERVICE_MODE=trade-manager
SERVICE_MODE=reconciliation
TRADE_SIDE=LONG или SHORT
```

Missing/unknown mode fail closed.

## 16.3. DSN separation

Каждый service получает только свой DSN:

```text
PAPER_ENTRY_DB_DSN
PAPER_MANAGER_LONG_DB_DSN
PAPER_MANAGER_SHORT_DB_DSN
PAPER_RECONCILIATION_DB_DSN
HEARTBEAT_DATABASE_DSN при необходимости тестового heartbeat
MARKET_DATA_DSN только для Reader path
```

Запрещён общий superuser DSN для всех workers.

## 16.4. Runtime loops

Entry loop:

```text
claim/read eligible signals без destructive claim;
TX-09 validate/open window;
exact candle lookup;
TX-10;
bounded retry;
```

Manager loop:

```text
read own OPEN trades;
fetch bounded next candle/funding batches;
process oldest exact evidence first;
TX-11/TX-12/TX-16;
commit watermark atomically;
```

Reconciliation loop:

```text
run bounded checks;
TX-14 incidents;
no repair;
```

## 16.5. Disposable Compose

Создать отдельный тестовый topology, например:

```text
docker-compose.stage5-test.yml
```

Он содержит минимум:

```text
stage5-paper-db
stage5-market-fixture-db или in-process fixture boundary
paper-entry
paper-trade-manager-long
paper-trade-manager-short
paper-reconciliation
one-shot fixture/acceptance runner
```

Disposable Compose:

```text
не использует production DSN;
не монтирует production volumes;
использует отдельный project name;
создаёт synthetic profiles/accounts/signals/candles/funding;
удаляется down -v --remove-orphans;
```

## 16.6. Synthetic acceptance matrix

Минимальные end-to-end scenarios:

```text
A. LONG → TP
B. LONG → SL
C. LONG → TIMEOUT
D. SHORT → TP
E. SHORT → SL
F. SHORT → TIMEOUT
G. TP и SL в одной свече → SL
H. Missing entry candle → WAITING_FOR_DATA → exact candle → OPENED
I. Missing entry candle до конца window → terminal без trade/reserve
J. Missing management candle → OPEN + WAITING_FOR_DATA → recovery
K. Funding на OPEN trade
L. Duplicate funding
M. Late funding на CLOSED trade
N. Loss larger than collateral → CLOSED + INSOLVENT
O. Duplicate Entry workers
P. Duplicate Manager workers
Q. Reconciliation mismatch incident без auto-fix
R. Restart Entry после ambiguous TX-10
S. Restart Manager после ambiguous TX-12
T. Full container restart и replay без дублей
```

## 16.7. Acceptance SQL assertions

Финальный SQL должен доказать:

```text
каждый synthetic signal имеет ожидаемый terminal status;
каждый OPENED signal имеет ровно один trade;
каждый trade имеет ровно одну reservation;
каждая closed trade имеет RELEASED reservation;
OPEN_POSITION groups имеют 2 rows exact order;
APPLY_FUNDING groups имеют 1 row;
CLOSE_POSITION groups имеют 3 rows exact order;
account versions монотонны;
ledger replay = account projection;
realized_pnl = sum(realized_delta);
equity = available + reserved;
нет duplicate close/funding/open groups;
нет cross-profile/exchange/side writes;
```

## 16.8. Restart proof

Перед restart сохранить digest/counts:

```text
signals
signal_events
trades
reservations
financial_transactions
account_ledger
snapshots
execution_events
funding_charges
incidents
account projections
```

После restart:

```text
повторный replay не создаёт лишние записи;
незавершённые legitimate operations завершаются по idempotency key;
closed trades не закрываются повторно;
funding не списывается повторно;
management watermark не регрессирует;
```

## 16.9. Контрольная точка Stage 5G

Блок принимается, если все scenarios выполняются в clean disposable topology, затем повторяются после restart и cleanup удаляет containers, volumes и network.

---

# 17. Stage 5H — CI, security, evidence and audit readiness

## 17.1. GitHub Actions workflow

Создать:

```text
.github/workflows/stage5-trading-core-contract.yml
```

Рекомендуемые jobs:

```text
static-unit
postgres-contract
concurrency-restart
docker-acceptance
```

Минимальные static checks:

```text
python -m compileall -q src scripts tests
ruff check src scripts tests
ruff format --check src scripts tests
mypy --strict src scripts/migrate.py
pytest -q tests/unit
```

PostgreSQL contract:

```text
clean migrations 001–012
migration rerun
permissions
immutability
TX-09–TX-16 integration
ledger replay
```

Docker acceptance:

```text
synthetic LONG/SHORT E2E
restart/replay
secret/boundary scan
always cleanup
```

## 17.2. Boundary scan

Stage 5 scan должен отклонять:

```text
изменения monitor-data;
production DSN/credentials;
private keys/tokens;
raw write SQL к Market DB;
Detector implementation;
Level Divergence/Short Squeeze strategy conditions;
Dashboard code;
Stage 6+ files;
прямые financial DML из Reconciliation;
прямые opposite-side manager writes;
float в financial/trading modules;
```

## 17.3. Required tests by layer

### Unit

```text
Signal validation
state transitions
sizing
rounding
slippage
commissions
PnL
funding
exit priority
gap behavior
timeout
checksum
UTC/Decimal
```

### PostgreSQL integration

```text
migrations
roles
TX-09
TX-10
TX-11
TX-12
TX-13
TX-14
TX-15
TX-16A/B/C
immutability
rollback
replay
```

### Concurrency

```text
double Entry
double Manager
double Funding
close versus funding
close versus reconciliation status
account version serialization
```

Close/funding race должен иметь deterministic serializable result:

```text
funding eligibility определяется event interval;
не теряется eligible event;
не возникает duplicate financial group;
```

### Restart

```text
crash TX-10
crash TX-11
crash TX-12
crash TX-16
stuck WAITING_ENTRY
stuck OPEN
reconciliation recovery
```

### Acceptance

Полный synthetic matrix A–T.

## 17.4. Skips

Запрещены скрытые skips критических Stage 5 tests.

Допустимо не запускать production source tests, потому что source blocked, но это должно быть оформлено как:

```text
NOT IN STAGE 5 ACCEPTANCE — PRODUCTION SOURCE BLOCKED
```

а не как зелёный production PASS.

---

# 18. Серверная проверка агентом

После каждого крупного implementation milestone новый чат публикует SHA. Серверный агент проверяет именно этот SHA.

## 18.1. Перед проверкой

```bash
git fetch origin --prune
git switch stage/05-trading-core
git pull --ff-only
git rev-parse HEAD
git status --short
```

Серверный отчёт обязан назвать exact SHA.

## 18.2. Разрешённые действия

```text
build disposable images;
start disposable Stage 5 Compose;
run test suites;
run SQL assertions;
restart disposable services;
measure runtime/resource behavior;
collect logs;
down -v cleanup;
```

## 18.3. Запрещённые действия

```text
restart production monitor-data;
write production Market DB;
write production Paper DB;
start production Stage 5;
reuse production volumes;
merge branch;
start Stage 6;
```

## 18.4. Обязательный server evidence

```text
host/runtime versions;
exact SHA;
Compose project name;
container list;
commands;
all test results;
SQL output;
restart before/after digests;
role permission proof;
resource usage for acceptance workload;
cleanup proof;
monitor-data untouched proof;
```

Server evidence переносится в Markdown в repository, а не остаётся только в terminal history или `/tmp`.

---

# 19. Предлагаемый порядок коммитов

```text
1. docs(stage5): record schema gap and implementation boundary
2. feat(stage5): add trading schema roles and immutable evidence
3. feat(stage5): add signal validation sizing and execution math
4. feat(stage5): implement TX-09 signal lifecycle
5. feat(stage5): implement atomic TX-10 paper entry
6. feat(stage5): implement TX-16 management and TX-12 close
7. feat(stage5): implement TX-11 funding and late revisions
8. feat(stage5): add TX-13 adjustments and TX-14/15 reconciliation
9. feat(stage5): add entry manager and reconciliation runtimes
10. test(stage5): add integration concurrency restart and acceptance
11. ci(stage5): add trading-core contract workflow
12. docs(stage5): close implementation evidence and audit handoff
```

Коммиты могут быть разделены ещё мельче. Запрещён один непроверяемый giant commit со всем Stage 5.

---

# 20. Документация Stage 5

Обязательные файлы в `paper-trading-engine`:

```text
docs/stages/STAGE_05_SCHEMA_GAP.md
docs/stages/STAGE_05_REPORT.md
docs/stages/STAGE_05_EVIDENCE.md
docs/stages/STAGE_05_OPEN_ISSUES.md
docs/stages/STAGE_05_SERVER_ACCEPTANCE.md
```

При необходимости:

```text
docs/operations/STAGE_05_DISPOSABLE_RUNBOOK.md
docs/architecture/STAGE_05_TRANSACTION_MAPPING.md
```

Обновить только после фактической реализации:

```text
CURRENT_STATE.md
HANDOFF.md
TODO.md
README.md
DECISIONS.md — только если появилось настоящее новое решение
```

Запрещено заранее писать `COMPLETE`, `PASS` или тестовые числа до получения evidence.

---

# 21. Evidence format

Для каждого TX:

```text
Transaction ID
Purpose
Initiator role
Lock order
Preconditions
Records created
Records updated
Immutable evidence
Ledger operation set
Idempotency key
Unique constraints
Rollback result
Retry result
Concurrent result
Forbidden writer proof
Test command
Test result
```

Для каждого acceptance scenario:

```text
initial account state
signal
candles/funding fixtures
expected transitions
expected financial groups
expected ledger rows
expected final trade
expected final account
actual SQL evidence
verdict
```

---

# 22. Критерии PASS Stage 5

Stage 5 готов к независимому аудиту только при одновременном выполнении всего списка:

```text
Stage 4 base подтверждён;
branch создан от чистого origin/main;
миграции 001–011 не изменены;
012 clean/rerun PASS;
Universal Signal contract реализован;
TX-09 реализован;
TX-10 atomic/idempotent/concurrent-safe;
TX-11 funding и late CLOSED funding реализованы;
TX-12 close atomic/idempotent/concurrent-safe;
TX-13 approved adjustments реализованы;
TX-14 incidents без financial writes;
TX-15 status dimensions без solvency writes;
TX-16A/B/C реализованы;
LONG/SHORT managers изолированы;
SL FIRST доказан;
TIMEOUT доказан;
exact entry candle доказана;
missing market data не закрывает OPEN trade;
immutable snapshots доказаны;
reservation collateral-only;
ledger exact operation sets;
account projection = replay;
negative valid close не клипуется;
INSOLVENT блокирует новые entries, но не management/close;
synthetic LONG и SHORT E2E PASS;
concurrency PASS;
restart/replay PASS;
Docker disposable cleanup PASS;
secret scan PASS;
boundary scan PASS;
monitor-data не изменён;
production DB не затронута;
Stage 6 не начат;
GitHub Actions exact final SHA green;
worktree clean;
git diff --check PASS;
```

Максимально честный итог Stage 5 до исправления production source:

```text
STAGE 5 IMPLEMENTATION COMPLETE — DISPOSABLE ACCEPTANCE PASSED — PRODUCTION SOURCE BLOCKED
```

---

# 23. Причины REJECT

Немедленный REJECT, если найдено хотя бы одно:

```text
trade или balance обновляются вне ledger group;
Reconciliation исправляет деньги напрямую;
двойной reserve, funding, commission, PnL или close возможен;
Entry использует более позднюю свечу вместо exact next candle;
OPEN trade переводится в DATA_ERROR/CANCELLED из-за market outage;
TP имеет приоритет над SL в same candle;
loss клипуется collateral;
quantity имеет отрицательный знак для SHORT;
используется float;
manager может менять opposite side;
TX-10 меняет solvency;
TX-11 меняет reservation;
TX-14 меняет account/trade/ledger;
immutable evidence можно UPDATE/DELETE;
production DB использована как test fixture;
production source BLOCKED выдан как APPROVED;
monitor-data изменён;
Stage 6 detector logic попала в branch;
критический test skipped;
финальный SHA не совпадает с проверенным SHA;
```

---

# 24. Политика критики без зацикливания

При аудите дефекты делятся на три уровня.

## Blocker

Нарушает финансовую истину, atomicity, idempotency, source boundary, state machine или может создать неверную сделку.

```text
Исправляется до принятия текущего блока.
```

## Forward-required

Не ломает уже доказанный блок, но обязательно для следующего Stage 5 блока.

```text
Переносится в следующее ТЗ с точным owner и test.
```

## Deferred technical debt

Не влияет на Stage 5 PASS и имеет более подходящий будущий этап.

```text
Записывается в STAGE_05_OPEN_ISSUES.md с target Stage.
Не используется как причина бесконечной переделки.
```

Запрещено формулировать корректирующее ТЗ как:

```text
«ещё раз всё проверь и улучши»
```

Каждое корректирующее ТЗ должно содержать:

```text
exact base SHA;
список доказанных дефектов;
почему это blocker;
точные файлы/контракты;
обязательный test;
что нельзя менять;
условие остановки;
```

---

# 25. Финальный отчёт исполнителя

После завершения ветки вернуть:

```text
STAGE 5 — IMPLEMENTATION REPORT

1. Repository.
2. Branch.
3. Base SHA.
4. Final SHA.
5. Commit list.
6. Changed files.
7. Migration 012 and fragments.
8. Existing Stage 2 foundation reused.
9. New tables and constraints.
10. Database roles and permissions.
11. Universal Signal contract.
12. TX-09 implementation.
13. Position sizing and rounding.
14. TX-10 Paper Entry.
15. Reservations.
16. LONG Manager.
17. SHORT Manager.
18. TX-16 management.
19. Exit priority and gap rules.
20. TX-12 close.
21. Commissions and PnL.
22. TX-11 funding and late revisions.
23. TX-13 adjustment classes.
24. TX-14/15 reconciliation boundary.
25. Replay.
26. Unit tests.
27. PostgreSQL integration tests.
28. Concurrency tests.
29. Restart tests.
30. Docker acceptance scenarios.
31. GitHub Actions run and exact tested SHA.
32. Server acceptance SHA and evidence.
33. Secret/boundary scan.
34. monitor-data proof.
35. Production DB proof.
36. Open issues.
37. What is proven.
38. What is not proven.
39. git status and diff check.
40. Recommendation for independent audit.
```

---

# 26. Условие остановки

После готовности Stage 5 к независимому аудиту:

```text
остановиться;
не выполнять merge;
не создавать production deployment;
не запускать production containers;
не исправлять monitor-data;
не начинать Stage 6;
не реализовывать реальные detectors;
передать Final SHA, Actions run, server evidence и open issues.
```

Следующий разрешённый шаг после независимого Stage 5 PASS:

```text
отдельное решение о merge Stage 5 в main
```

Только после merge и formal closeout Stage 5 разрешается создавать ТЗ на:

```text
Stage 6 — Level Divergence SHORT
```
