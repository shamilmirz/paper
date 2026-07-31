# ТЕХНИЧЕСКОЕ ЗАДАНИЕ АГЕНТУ `paper-trading-architect`

## Paper Trading Engine — Этап 3 — Market Data Layer

---

# 1. Цель этапа

Создать безопасный, строго read-only слой доступа к рыночной TimescaleDB внешнего проекта `monitor-data`, нормализовать рыночные данные Binance и Bybit в единые внутренние модели, реализовать Market Universe и пакетный расчёт Market Features.

Итоговая граница этапа:

```text
monitor-data TimescaleDB
→ SELECT-only Market Data Reader
→ Binance/Bybit normalization
→ Data Quality
→ Universe
→ Features
```

На этом этапе запрещено продолжать цепочку дальше:

```text
Scanner
Growth State
Levels Builder
Candidate
Detector
Signal
Paper Entry
Trade Manager
```

Market Data Reader не должен знать о:

```text
trader profiles
accounts
ledger
signals
trades
positions
TP
SL
TIMEOUT
fees
funding charges по сделкам
```

Финальный результат этапа:

```text
Binance и Bybit возвращают одинаковые канонические модели.
Незакрытые и будущие свечи исключены.
Gaps, stale и duplicate data определяются.
Universe и Features работают пакетно.
monitor-data остаётся неизменённым.
```

---

# 2. Исходное состояние

## Репозиторий

```text
shamilmirz/paper-trading-engine
```

## Base branch

```text
main
```

## Base SHA

```text
ee72737406461df90980c51063fce297d7faa0be
```

## Merge commit

```text
ee72737406461df90980c51063fce297d7faa0be
```

Указанные родители merge-коммита:

```text
3dcbafb4a53ea0d6a5d337c48789f810c9997f88
1cc3e0a6808420063212031b9db80957f08a007a
```

Stage 2 уже влит в `main`.

Stage 3 не начат.

Целевая ветка:

```text
stage/03-market-data
```

На момент аудита удалённая ветка с таким именем отсутствовала.

---

# 3. Обязательная проверка до любых изменений

Выполнить:

```bash
git fetch origin --prune

git branch --show-current
git rev-parse HEAD
git rev-parse origin/main
git status --short
git log -5 --oneline
git merge-base --is-ancestor \
  1cc3e0a6808420063212031b9db80957f08a007a \
  origin/main
```

Обязательное ожидаемое состояние:

```text
Current branch: main
HEAD: ee72737406461df90980c51063fce297d7faa0be
origin/main: ee72737406461df90980c51063fce297d7faa0be
Worktree: clean
Stage 2 commit is an ancestor of origin/main
```

Если:

* `HEAD != origin/main`;
* SHA отличается от Base SHA;
* worktree содержит изменения;
* появились неизвестные untracked-файлы;
* Stage 2 отсутствует в истории;

то остановиться.

Ничего не удалять, не stash-ить, не reset-ить и не исправлять самостоятельно.

После успешной проверки создать ветку:

```bash
git switch -c stage/03-market-data
```

Запрещено начинать разработку непосредственно в `main`.

---

# 4. Что обязательно изучить

До реализации полностью прочитать:

```text
README.md
AGENT_INSTRUCTIONS.md
PROJECT_RULES.md
docs/MASTER_IMPLEMENTATION_PLAN.md
docs/PROJECT_MASTER_CHECKLIST.md
CURRENT_STATE.md
DECISIONS.md
HANDOFF.md
TODO.md
```

Документы предыдущего этапа:

```text
docs/stages/STAGE_02_REPORT.md
docs/stages/STAGE_02_EVIDENCE.md
docs/stages/STAGE_02_OPEN_ISSUES.md
```

Архитектурные контракты:

```text
docs/architecture/MARKET_DATA_CONTRACT.md
docs/architecture/DATABASE_CONTRACT.md
docs/architecture/DATA_FLOW.md
docs/architecture/SERVICE_BOUNDARIES.md
docs/architecture/DOMAIN_MODEL.md
docs/architecture/OBSERVABILITY_CONTRACT.md
docs/architecture/TEST_STRATEGY.md
docs/architecture/FAILURE_RECOVERY.md
docs/architecture/SYSTEM_CONTEXT.md
```

Текущую реализацию и соглашения:

```text
pyproject.toml
src/paper_engine/common/config.py
src/paper_engine/common/errors.py
src/paper_engine/common/logging.py
src/paper_engine/accounting/domain.py
scripts/migrate.py
tests/integration/test_permissions.py
migrations/001_stage2_foundation.sql
...
migrations/007_stage2_final_contract_sync.sql
```

Не доверять старым описаниям схем `monitor-data`. Истиной являются только фактические PostgreSQL-схемы и код работающих коллекторов, прочитанные без изменений.

---

# 5. Предварительный permission gate

Это обязательный первый технический checkpoint.

Нужно проверить, существует ли в Market Database пользователь:

```text
paper_market_reader
```

Он должен:

```text
иметь CONNECT к Market Database;
иметь USAGE только на необходимые схемы;
иметь SELECT только на подтверждённые рыночные таблицы;
не состоять в write-ролях;
не иметь CREATEDB;
не иметь CREATEROLE;
не иметь SUPERUSER;
не иметь REPLICATION;
не иметь BYPASSRLS;
не иметь CREATE в рабочих схемах;
иметь default_transaction_read_only=on.
```

## Если пользователь уже существует

Проверить фактические grants и продолжить только после доказательства отсутствия write-прав.

## Если пользователя нет

Создание production-роли является изменением внешней production-инфраструктуры.

В этом случае:

1. Не создавать роль самостоятельно.
2. Не изменять production PostgreSQL.
3. Не изменять `monitor-data`.
4. Не начинать реализацию Stage 3.
5. Подготовить владельцу отдельный запрос разрешения.
6. Остановиться со статусом:

```text
STOPPED — OWNER PERMISSION REQUIRED
```

В запросе владельцу показать предполагаемые grants, но не выполнять их:

```sql
CREATE ROLE paper_market_reader
LOGIN
NOINHERIT
NOSUPERUSER
NOCREATEDB
NOCREATEROLE
NOREPLICATION
NOBYPASSRLS;

ALTER ROLE paper_market_reader
SET default_transaction_read_only = on;

GRANT CONNECT ON DATABASE <market_database>
TO paper_market_reader;

GRANT USAGE ON SCHEMA <confirmed_schema>
TO paper_market_reader;

GRANT SELECT ON TABLE
    <confirmed_schema>.candles_1m,
    <confirmed_schema>.candles_1h,
    <confirmed_schema>.oi_snapshots,
    <confirmed_schema>.funding,
    <confirmed_schema>.liq_snapshots
TO paper_market_reader;
```

Фактические schema/table names нельзя подставлять до аудита.

Пароль или DSN в отчёт не включать.

---

# 6. Разрешённые изменения

Разрешено изменять только репозиторий:

```text
paper-trading-engine
```

Разрешено:

1. Создать Market Data domain models.
2. Создать общий Reader interface.
3. Создать PostgreSQL read-only adapter.
4. Создать отдельную нормализацию Binance и Bybit.
5. Создать Data Quality policy и evaluator.
6. Создать Universe.
7. Создать Features.
8. Добавить typed configuration для Market DB.
9. Добавить миграции Paper DB для Stage 3.
10. Добавить отдельные роли Paper DB для Universe и Features.
11. Добавить unit, integration и load tests.
12. Добавить Stage 3 dev/test окружение.
13. Дополнить архитектурные документы фактическим physical mapping.
14. Создать итоговые Stage 3 документы.
15. Обновить корневые state-документы.

Reader не имеет права писать даже в Paper DB.

Запись в Paper DB разрешена только отдельным компонентам:

```text
Universe → market_universe
Features → market_features
Market Quality → data_quality_incidents
```

---

# 7. Запрещённые изменения

Запрещено:

```text
изменять monitor-data;
изменять код его коллекторов;
изменять его Markdown;
изменять его таблицы;
создавать в нём таблицы;
создавать в нём индексы;
изменять существующие индексы;
выполнять VACUUM FULL;
выполнять CLUSTER;
выполнять REINDEX;
перезапускать его контейнеры;
изменять его Compose;
изменять его scheduler;
останавливать сервисы;
удалять или исправлять старые данные;
изменять старые paper trades.
```

В `paper-trading-engine` запрещено:

```text
изменять миграции 001–007;
создавать Scanner;
создавать Growth State;
строить Levels;
создавать Candidate;
создавать Detector;
создавать Signal;
создавать сделки;
изменять account balances;
писать ledger;
реализовывать Entry;
реализовывать Trade Manager;
создавать production Compose;
создавать production scheduler;
включать trader profiles.
```

Запрещены прямые зависимости:

```text
paper_engine.market_data → paper_engine.accounting
paper_engine.market_data → paper_engine.execution
paper_engine.market_data → paper_engine.trading
paper_engine.market_data → paper_engine.detectors
```

Запрещено:

```bash
git add .
git add -A
git push origin main
git merge
```

---

# 8. Пошаговая реализация

## Шаг 1. Аудит физических источников

Проверить фактическое существование таблиц:

```text
candles_1m
candles_1h
oi_snapshots
funding
liq_snapshots
```

Названия являются предположением из master plan. Если физические названия отличаются, зафиксировать реальные.

Для каждой таблицы определить:

```text
schema;
table name;
owner;
columns;
PostgreSQL types;
nullable;
defaults;
primary key;
unique constraints;
foreign keys;
indexes;
hypertable status;
partition/chunk structure;
timestamp columns;
exchange column;
symbol format;
source update timestamp;
ingestion timestamp;
retention;
compression;
row count;
symbol count;
latest timestamp;
age of latest data.
```

Использовать read-only catalog queries:

```text
information_schema.columns
pg_catalog.pg_class
pg_catalog.pg_namespace
pg_catalog.pg_constraint
pg_catalog.pg_indexes
pg_catalog.pg_roles
timescaledb_information.hypertables
timescaledb_information.chunks
```

Запрещено предполагать natural key до проверки constraints и данных.

Для каждого источника проверить:

```text
duplicate natural keys;
duplicate timestamps;
out-of-order rows;
NULL в обязательных полях;
negative price/volume/OI;
zero price;
future timestamps;
large gaps;
stale symbols;
различия Binance/Bybit;
symbol collision между биржами.
```

Результат сохранить в:

```text
docs/market_data/STAGE_03_SOURCE_SCHEMA_AUDIT.md
```

Документ должен содержать фактический SQL, но не DSN, пароль, IP или секреты.

---

## Шаг 2. Зафиксировать source mapping

Создать явную таблицу соответствия:

```text
physical source column
→ source meaning
→ canonical field
→ conversion
→ quality failure
```

Отдельно для:

```text
Binance candles
Bybit candles
Binance OI
Bybit OI
Binance funding
Bybit funding
Binance liquidations
Bybit liquidations
```

Не использовать скрытые fallback-правила.

Если физическая колонка отсутствует, canonical field не должен заполняться выдуманным значением.

Результат:

```text
docs/market_data/STAGE_03_SOURCE_MAPPING.md
```

---

## Шаг 3. Реализовать typed configuration

Добавить отдельный конфигурационный класс, например:

```text
MarketDataSettings
```

Минимальные поля:

```text
paper_market_database_dsn
market_database_pool_min
market_database_pool_max
market_database_statement_timeout
market_database_lock_timeout
market_database_application_name
market_database_ssl_mode
market_data_quality_policy_path
market_data_query_budget
market_data_batch_size
```

DSN должен поступать только через environment.

Пример env-файла не должен содержать:

```text
production hostname;
production database;
реальный username, кроме согласованного имени роли;
пароль;
token;
полный credential DSN.
```

Reader при старте обязан проверить:

```text
current_user;
transaction_read_only;
default_transaction_read_only;
server timezone;
доступность необходимых таблиц;
отсутствие неожиданных write-привилегий.
```

При нарушении — fail closed.

---

## Шаг 4. Канонические модели

Реализовать immutable модели.

### `CanonicalCandle`

Минимальные поля:

```text
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
trade_count, если источник подтверждён
source_updated_at
ingested_at, если источник содержит поле
source_identity
quality
```

Правила:

```text
UTC timezone-aware timestamps;
open_ts < close_ts;
high >= max(open, close, low);
low <= min(open, close, high);
цены > 0;
volume >= 0;
Decimal, не float;
identity = exchange + symbol + interval + open_ts.
```

### `OpenInterestSnapshot`

Минимальные поля:

```text
exchange
symbol
event_ts
source_value
source_unit
oi_base
oi_quote
conversion_price
conversion_price_ts
source_updated_at
source_identity
quality
```

`source_unit` должен быть явным:

```text
BASE_ASSET
QUOTE_ASSET
CONTRACTS
USD
USDT
UNKNOWN
```

### `FundingEvent`

Минимальные поля:

```text
exchange
symbol
funding_event_ts
normalized_rate
source_rate
reference_price
reference_price_ts
period
is_actual_funding_event
source_updated_at
source_identity
quality
```

### `LiquidationEvent`

Минимальные поля:

```text
exchange
symbol
event_ts
liquidated_position_side
price
quantity_base
notional_quote
source_event_id
deduplication_key
source_updated_at
quality
```

Использовать название:

```text
liquidated_position_side
```

Не использовать неоднозначное поле `side`.

### `MarketDataQuality`

Минимальные поля:

```text
status
reason_codes
policy_version
as_of
latest_required_source_ts
age
missing_intervals
duplicate_count
out_of_order_count
invalid_count
source_count
checksum
```

Допустимые статусы:

```text
COMPLETE
PARTIAL
STALE
GAPPED
DUPLICATED
OUT_OF_ORDER
INVALID
UNAVAILABLE
```

Все модели должны быть immutable.

Для цен, OI, funding, volume и liquidation quantity запрещено использовать `float`.

---

## Шаг 5. Timestamp normalization и защита от look-ahead

Все публичные Reader-методы обязаны принимать явный параметр:

```text
as_of
```

Скрытое использование текущего времени внутри запросов запрещено.

Clock должен передаваться как зависимость.

Для каждой биржи документально доказать:

```text
какая колонка является candle open timestamp;
есть ли candle close timestamp;
является ли timestamp временем открытия или закрытия;
в каких единицах он хранится;
есть ли миллисекунды;
есть ли timezone;
когда строка становится финальной;
может ли строка обновляться после закрытия;
что означает source_updated_at;
что означает ingestion timestamp.
```

Канонический контракт:

```text
candle identity = exchange + symbol + interval + open_ts
close_ts = open_ts + interval
```

Свеча может быть возвращена как CLOSED только если:

```text
close_ts <= as_of - candle_ingestion_grace
```

и источник не помечает её незавершённой.

Если источник не содержит признака финальности, это должно быть явно отражено в quality policy.

Reader должен исключать:

```text
текущую незакрытую свечу;
будущие свечи;
строки, появившиеся после replay cutoff, если ingestion timestamp доступен;
свечи с INVALID quality.
```

Следующая свеча определяется строго:

```text
next.open_ts = current.open_ts + interval
```

Первая более поздняя свеча не считается автоматически следующей.

Если точной следующей свечи нет:

```text
gap = true
exact_next = unavailable
```

Не перескакивать через gap.

Обязательный тест должен содержать будущую строку в базе и доказывать, что она не влияет на результат при более раннем `as_of`.

Результат аудита:

```text
docs/market_data/STAGE_03_TIMESTAMP_CONTRACT.md
```

---

## Шаг 6. OI semantics

Для Binance и Bybit отдельно доказать:

```text
что означает исходное значение;
base asset это, quote value или contracts;
меняется ли значение вместе с ценой;
есть ли multiplier контракта;
какой timestamp относится к observation;
как часто значение обновляется;
может ли быть duplicate;
как определяется stale;
как выбирается последнее значение на cutoff.
```

Нельзя сравнивать Binance и Bybit OI без явной единицы.

Требования:

1. Сохранять исходное значение и исходную единицу.
2. Не маркировать quote OI как base OI.
3. Не делить OI на произвольную текущую цену.
4. Конверсию выполнять только при доказанном контракте.
5. Для конверсии использовать цену с совместимым timestamp.
6. Сохранять conversion price и timestamp.
7. Не смешивать данные разных бирж.
8. Не forward-fill stale OI как свежий.

Для ACTIVE Universe поле `oi_base` должно быть либо доказано источником, либо корректно вычислено по доказанному контракту.

Если получить base OI невозможно:

```text
пара становится INACTIVE;
reason = INVALID_OI_UNIT или OI_CONVERSION_UNAVAILABLE.
```

---

## Шаг 7. Funding semantics

Для обеих бирж определить:

```text
таблица содержит actual funding events;
периодические snapshots;
change-only записи;
текущий прогноз;
последнюю известную ставку;
исторически применённую ставку.
```

Запрещено:

```text
считать отсутствие строки funding_rate=0;
создавать funding event каждую минуту;
forward-fill funding как фактическое начисление;
смешивать forecast и settled funding.
```

Canonical `FundingEvent` создаётся только для фактического funding timestamp.

Для Feature допускается последнее известное значение, но обязательно сохраняются:

```text
funding_event_ts;
funding_age;
is_actual_funding_event;
quality.
```

Funding gap должен означать отсутствие ожидаемого события по доказанному schedule, а не отсутствие минутной строки.

---

## Шаг 8. Liquidation semantics

Для Binance и Bybit доказать:

```text
означает ли Long ликвидированную LONG-позицию;
означает ли Short ликвидированную SHORT-позицию;
не является ли source side стороной market order;
какая quantity;
какая currency;
что является event timestamp;
есть ли source event ID;
может ли одно событие поступить повторно.
```

Если source semantics неоднозначна, не угадывать.

Дедупликация:

```text
source_event_id
```

используется при его наличии.

Если source ID отсутствует, создать детерминированный ключ из подтверждённых полей, например:

```text
exchange
symbol
event_ts
liquidated_position_side
price
quantity
source discriminator
```

Ключ должен иметь версию алгоритма.

Liquidation windows:

```text
1m
5m
15m
```

считаются по `event_ts`, строго до `as_of`.

Событие с `event_ts > as_of` исключается.

---

## Шаг 9. Read-only PostgreSQL adapter

Создать общий интерфейс Reader.

Минимальные batch-методы:

```text
fetch_candles(...)
fetch_latest_open_interest(...)
fetch_funding_events(...)
fetch_liquidation_events(...)
fetch_instrument_metadata(...)
```

Каждый метод обязан принимать:

```text
exchange;
symbols как collection;
time range;
as_of;
quality policy/version.
```

Каждый SQL-запрос обязан содержать явный exchange filter.

Запрещён exchange по умолчанию.

Требования:

```text
только параметризованный SQL;
никакой конкатенации symbol в SQL;
стабильная сортировка;
statement timeout;
read-only transaction;
корреляционный ID;
query duration;
row count;
source cutoff;
никаких долгих открытых транзакций.
```

Reader не должен иметь методов:

```text
execute_write
insert
update
delete
upsert
migrate
create_table
create_index
```

---

## Шаг 10. Market Universe

Реализовать модель:

```text
ACTIVE
INACTIVE
```

Причина не должна кодироваться отдельным псевдостатусом.

Использовать reason codes:

```text
STALE_CANDLE
STALE_OI
MISSING_OI
MISSING_HISTORY
INSUFFICIENT_VOLUME
BLACKLISTED
INVALID_DATA
INVALID_OI_UNIT
OI_CONVERSION_UNAVAILABLE
GAPPED_CANDLES
DUPLICATED_DATA
UNSUPPORTED_INSTRUMENT
```

Минимальный контракт Universe:

```text
exchange
symbol
status
reason_codes
source_watermark
quality_policy_version
candles_fresh_at
oi_fresh_at
history_start_at
volume_24h_quote
updated_at
```

Eligibility:

```text
USDT perpetual;
поддерживаемый инструмент;
закрытая свежая минутная свеча;
достаточная история;
свежий OI;
доказанная OI unit;
достаточный оборот;
нет blacklist;
нет mandatory INVALID quality.
```

Universe не должен:

```text
искать торговый вход;
использовать параметры детектора;
строить уровни;
создавать кандидатов;
читать accounts;
читать balances.
```

Публикация в Paper DB должна соответствовать TX-01:

```text
одна projection на exchange + symbol;
stale watermark не может перезаписать новый;
одинаковый watermark и policy version — no-op;
batch upsert;
никаких финансовых изменений.
```

---

## Шаг 11. Market Features

Рассчитывать пакетно и отдельно по каждой бирже.

Минимальные поля snapshot:

```text
exchange
symbol
as_of
feature_version
quality_policy_version
source_cutoff
source_checksum

price
price_change_5m
price_change_15m
price_change_30m
price_change_2h
price_change_24h

oi_base
oi_quote
oi_change_5m
oi_change_30m
oi_change_2h

volume_3m
volume_15m
volume_24h_quote
volume_ratio

funding_rate
funding_event_ts
funding_age

long_liquidation_1m
long_liquidation_5m
long_liquidation_15m

short_liquidation_1m
short_liquidation_5m
short_liquidation_15m

volatility
data_quality
```

Все формулы описать в:

```text
docs/market_data/STAGE_03_FEATURE_CONTRACT.md
```

Особенно определить:

```text
price change denominator;
OI change denominator;
поведение при нуле;
volume ratio baseline;
volatility formula;
window boundaries;
inclusive/exclusive timestamps;
missing-data behavior;
rounding;
Decimal precision.
```

Features должны:

```text
использовать только CLOSED candles;
использовать один общий as_of cutoff;
не загружать будущие строки;
не смешивать exchange;
не forward-fill INVALID данные;
не превращать missing в zero;
не повторять запрос для каждого symbol.
```

Публикация в Paper DB соответствует TX-02:

```text
immutable snapshot;
identity = exchange + symbol + as_of + feature_version;
одинаковая identity и checksum = idempotent no-op;
одинаковая identity и другой checksum = incident/fail closed;
update существующего snapshot запрещён.
```

---

## Шаг 12. Paper DB migration Stage 3

Не изменять миграции:

```text
001–007
```

Добавить новую последовательную миграцию, начиная с:

```text
008_stage3_market_data.sql
```

При необходимости разрешена дополнительная Stage 3 migration, но только с обоснованием.

Минимальные сущности:

```text
market_universe
market_features
data_quality_incidents
```

Минимальные ограничения:

```text
exchange обязателен;
symbol обязателен;
UTC timestamps;
unique Universe projection;
unique immutable Feature identity;
feature snapshot update запрещён;
financial tables не затрагиваются;
foreign key к accounts/trades/signals отсутствует.
```

Роли Paper DB:

```text
paper_universe_writer
paper_features_writer
paper_market_quality_writer
paper_market_auditor
```

Каждая роль получает права только на свои объекты.

Reader role Market Database и writer roles Paper Database не должны использовать один DSN или один pool.

Нужны permission tests:

```text
Universe не пишет market_features;
Features не пишет market_universe;
Market Quality не пишет finance;
Reader не пишет Paper DB;
финансовые роли не изменяют market_features;
Dashboard/auditor не пишет ничего.
```

---

## Шаг 13. Производительность и N+1

Запрещён любой SQL-запрос внутри цикла по symbol.

Обязательная структурная гарантия:

```text
количество Market DB запросов не зависит от количества пар.
```

Начальный query budget:

```text
не более 6 Market DB SELECT-запросов
на одну биржу за один Feature cycle
```

Если требуется больше, остановиться и обосновать каждую дополнительную категорию запроса.

Ожидаемая модель:

```text
candles 1m batch;
candles 1h/history batch;
OI batch;
funding batch;
liquidations batch;
instrument metadata/universe batch.
```

Запись в Paper DB:

```text
один batch Universe upsert на биржу;
одна batch Feature publication на биржу;
batch incident publication при необходимости.
```

Запрещено загружать полную 24-часовую историю всех symbols в Python, если расчёты можно выполнить серверной агрегацией.

Результат batch-запроса должен быть порядка:

```text
O(number of symbols)
```

а не:

```text
O(number of symbols × number of candles)
```

Нагрузочный тест выполнять только на отдельной test/replica database.

Наборы:

```text
100 symbols
500 symbols
1000 symbols
```

Для каждого набора измерить:

```text
число Market DB запросов;
число Paper DB запросов;
rows read;
rows returned;
query duration;
полный cycle duration;
p50;
p95;
peak RSS;
Python allocation peak;
размер batch;
PostgreSQL execution plan.
```

Методика:

```text
не менее 3 warm-up cycles;
не менее 20 измеряемых cycles;
одинаковый dataset;
одинаковая конфигурация;
записать CPU/RAM/PostgreSQL/TimescaleDB версии.
```

Документировать лимиты в:

```text
docs/market_data/STAGE_03_PERFORMANCE_REPORT.md
```

Если производительность требует нового индекса в `monitor-data`:

1. Не создавать индекс.
2. Не менять запрос скрытым N+1.
3. Зафиксировать query plan.
4. Описать предлагаемый индекс.
5. Остановиться и запросить разрешение владельца.

---

# 9. Обязательные файлы

## Domain и Reader

Ожидаемая структура:

```text
src/paper_engine/domain/market_data/
src/paper_engine/market_data/reader/
src/paper_engine/market_data/normalization/
src/paper_engine/market_data/quality/
src/paper_engine/market_data/universe/
src/paper_engine/market_data/features/
```

Допускается изменение конкретных имён файлов, но границы пакетов должны сохраниться.

## Configuration

```text
src/paper_engine/common/config.py
.env.example или отдельный безопасный Stage 3 example
configs/services/<stage3-quality-policy>
```

## Database

```text
migrations/008_stage3_market_data.sql
```

При необходимости:

```text
scripts/init_stage3_roles.sh
docker-compose.stage3-test.yml
docs/runbooks/STAGE_03_DEV_TEST.md
```

## Документация источников

Обязательны:

```text
docs/market_data/STAGE_03_SOURCE_SCHEMA_AUDIT.md
docs/market_data/STAGE_03_SOURCE_MAPPING.md
docs/market_data/STAGE_03_TIMESTAMP_CONTRACT.md
docs/market_data/STAGE_03_FEATURE_CONTRACT.md
docs/market_data/STAGE_03_READ_ONLY_EVIDENCE.md
docs/market_data/STAGE_03_PERFORMANCE_REPORT.md
```

## Итоговые документы этапа

```text
docs/stages/STAGE_03_REPORT.md
docs/stages/STAGE_03_EVIDENCE.md
docs/stages/STAGE_03_OPEN_ISSUES.md
```

## Обязательные обновления

```text
CURRENT_STATE.md
TODO.md
HANDOFF.md
DECISIONS.md
README.md
```

Обновить по фактической реализации:

```text
docs/architecture/MARKET_DATA_CONTRACT.md
docs/architecture/DATABASE_CONTRACT.md
docs/architecture/SERVICE_BOUNDARIES.md
docs/architecture/TEST_STRATEGY.md
```

`TEST_STRATEGY.md` должен быть синхронизирован:

```text
closed-candle cutoff;
Reader freshness;
Reader gaps;
Reader duplicate handling;
read-only permissions;
Universe;
Features;
batch/load tests
```

относятся к Stage 3.

Stage 4 сохраняет:

```text
Scanner;
Growth;
Levels;
candidate quality propagation;
worker restart/recovery;
runtime heartbeats.
```

Запрещено изменять:

```text
docs/stages/STAGE_01_*
docs/stages/STAGE_02_*
docs/MASTER_IMPLEMENTATION_PLAN.md
docs/PROJECT_MASTER_CHECKLIST.md
```

кроме отдельного прямого разрешения владельца.

---

# 10. Обязательные тесты

## Unit tests

Обязательны:

```text
Binance candle normalization;
Bybit candle normalization;
millisecond timestamp normalization;
timezone normalization;
closed candle;
open candle excluded;
future candle excluded;
exact next candle;
missing next candle;
missing candle;
duplicate candle;
out-of-order candle;
stale candle;
invalid OHLC;
negative volume;
canonical identity;
Decimal-only market values;
quality status precedence.
```

## OI tests

```text
Binance OI source unit;
Bybit OI source unit;
base OI;
quote OI;
contract multiplier;
same-timestamp conversion;
missing conversion price;
stale OI;
missing OI;
zero denominator;
cross-exchange OI isolation.
```

## Funding tests

```text
actual funding event;
forecast versus settled funding;
change-only source;
periodic source;
funding gap;
missing funding is not zero;
no minute duplication;
future funding excluded;
funding age.
```

## Liquidation tests

```text
Binance liquidation side;
Bybit liquidation side;
liquidated LONG;
liquidated SHORT;
source ID dedup;
fallback dedup key;
duplicate event;
future event excluded;
1m/5m/15m windows;
cross-exchange isolation.
```

## Universe tests

```text
ACTIVE eligibility;
INACTIVE stale candle;
INACTIVE stale OI;
INACTIVE missing OI;
INACTIVE invalid OI unit;
INACTIVE gap;
INACTIVE blacklist;
INACTIVE insufficient history;
new watermark wins;
old watermark cannot overwrite;
equal watermark no-op;
batch upsert.
```

## Feature tests

```text
batch calculation;
price changes;
OI changes;
volume ratio;
funding;
liquidation windows;
volatility;
missing denominator;
quality propagation;
immutable snapshot;
idempotent retry;
checksum conflict;
same symbol on Binance and Bybit;
no look-ahead;
future source correction excluded by cutoff.
```

## Permission tests

На disposable/test database:

```text
paper_market_reader can SELECT;
paper_market_reader cannot INSERT;
paper_market_reader cannot UPDATE;
paper_market_reader cannot DELETE;
paper_market_reader cannot TRUNCATE;
paper_market_reader cannot CREATE TABLE;
paper_market_reader cannot ALTER TABLE;
paper_market_reader cannot DROP TABLE;
paper_market_reader cannot CREATE INDEX;
paper_market_reader cannot change role;
paper_market_reader is read-only by default.
```

Фактические отрицательные DML/DDL проверки production Market DB запрещены без отдельного разрешения владельца.

На production разрешён только catalog privilege audit либо отдельно согласованный controlled test.

## Architecture tests

Добавить тест, запрещающий imports:

```text
market_data → accounting
market_data → execution
market_data → trading
market_data → detectors
```

## Query-count test

Проверить на одинаковом коде:

```text
10 symbols
100 symbols
1000 symbols
```

Количество Market DB запросов должно оставаться одинаковым.

## Load test

Отдельный suite:

```text
tests/load/
```

Он не должен случайно запускаться против production.

Без явного test DSN тест обязан fail closed или skip с однозначным сообщением.

---

# 11. Обязательные команды проверки

Минимум:

```bash
python3 -m pytest tests/unit -q
python3 -m pytest tests/integration -q
python3 -m pytest tests/load -q

python3 -m pytest -q

python3 -m ruff check src tests scripts
python3 -m ruff format --check src tests scripts
python3 -m mypy src

python3 scripts/float_scan.py
git diff --check
```

Миграции на чистой Paper DB:

```bash
python3 scripts/migrate.py
python3 scripts/migrate.py
```

Второй запуск должен быть идемпотентным.

Проверка migration history:

```sql
SELECT version, name, checksum, applied_at
FROM schema_migrations
ORDER BY version;
```

Проверка grants:

```sql
SELECT current_user;
SHOW transaction_read_only;
SHOW default_transaction_read_only;

SELECT *
FROM information_schema.role_table_grants
WHERE grantee = 'paper_market_reader';

SELECT
    rolname,
    rolsuper,
    rolcreaterole,
    rolcreatedb,
    rolcanlogin,
    rolreplication,
    rolbypassrls
FROM pg_roles
WHERE rolname = 'paper_market_reader';
```

Проверка секретов:

```bash
docker run --rm \
  -v "$PWD:/repo" \
  zricethezav/gitleaks:latest \
  detect --source=/repo --no-git --redact

git grep -nEi \
  '(password|secret|token|api[_-]?key|private[_-]?key|postgres(ql)?://[^[:space:]]+:[^@[:space:]]+@)' \
  -- ':!docs/stages/STAGE_03_EVIDENCE.md'
```

Любое совпадение разобрать вручную. Нельзя просто исключить файл или pattern без объяснения.

---

# 12. Доказательство отсутствия изменений в `monitor-data`

Перед первым чтением внешнего проекта зафиксировать:

```bash
git -C <monitor-data-path> branch --show-current
git -C <monitor-data-path> rev-parse HEAD
git -C <monitor-data-path> status --short
git -C <monitor-data-path> diff --stat
git -C <monitor-data-path> diff --binary | sha256sum
git -C <monitor-data-path> diff --cached --binary | sha256sum
```

Сохранить вывод как BEFORE evidence.

После завершения повторить те же команды как AFTER evidence.

Обязательно доказать:

```text
HEAD before = HEAD after;
branch before = branch after;
tracked diff hash before = tracked diff hash after;
cached diff hash before = cached diff hash after;
agent не выполнял write-команд;
agent не перезапускал контейнеры;
agent не изменял Compose;
agent не изменял таблицы или индексы.
```

Если до начала были чужие изменения:

```text
не удалять;
не исправлять;
не stash-ить;
не включать в commit;
не заявлять, что monitor-data clean.
```

В отчёте написать:

```text
Pre-existing state preserved unchanged.
```

только если BEFORE и AFTER действительно совпадают.

---

# 13. Git-требования

Весь этап выполняется в:

```text
stage/03-market-data
```

Перед staging:

```bash
git status --short
git diff --stat
git diff
```

Добавлять только явно перечисленные Stage 3 файлы:

```bash
git add <exact-file-1> <exact-file-2> ...
```

Запрещено:

```bash
git add .
git add -A
```

После staging:

```bash
git diff --cached --stat
git diff --cached
git status --short
```

Требование проекта:

```text
один этап — один implementation commit
```

Рекомендуемое сообщение:

```text
feat(stage-03): add read-only market data layer
```

После commit:

```bash
git rev-parse HEAD
git log -3 --oneline
git status --short
git diff \
  ee72737406461df90980c51063fce297d7faa0be...HEAD \
  --stat
git diff \
  ee72737406461df90980c51063fce297d7faa0be...HEAD
```

Затем разрешено опубликовать только ветку:

```bash
git push -u origin stage/03-market-data
```

Не создавать PR.

Не выполнять merge.

Не изменять `main`.

## Final SHA

Не пытаться записывать SHA коммита внутрь этого же коммита с повторными бесконечными amend.

В Stage 3 документах использовать:

```text
Base SHA: ee72737406461df90980c51063fce297d7faa0be
Final SHA: supplied externally in agent final report
```

Фактический Final SHA показать в итоговом ответе агента после commit и push.

---

# 14. Формат Stage 3 Evidence

`STAGE_03_EVIDENCE.md` должен содержать:

```text
1. Base branch и Base SHA.
2. Permission gate.
3. Фактического Market DB пользователя.
4. Таблицы и схемы.
5. Column/type mapping.
6. Keys и indexes.
7. Timestamp evidence.
8. Closed-candle evidence.
9. No-look-ahead evidence.
10. OI units Binance.
11. OI units Bybit.
12. Funding semantics Binance.
13. Funding semantics Bybit.
14. Liquidation semantics Binance.
15. Liquidation semantics Bybit.
16. Duplicate/gap/stale evidence.
17. Read-only permission matrix.
18. Canonical model parity.
19. Universe eligibility.
20. Feature formulas.
21. Query-count evidence.
22. Load-test methodology.
23. p50/p95 и memory.
24. Migration output.
25. Unit tests.
26. Integration tests.
27. Load tests.
28. Full test suite.
29. Ruff/mypy.
30. Secret scan.
31. monitor-data BEFORE/AFTER.
32. Git diff.
33. Final branch и внешний Final SHA.
```

Команды и результаты должны быть реальными.

Запрещены формулировки:

```text
should pass
expected to pass
appears correct
probably read-only
likely no look-ahead
```

Допустимы только доказанные результаты или явное:

```text
NOT PROVEN
```

---

# 15. Формат итогового отчёта агента

Итоговый ответ агента должен содержать:

```text
1. Implementation status:
   COMPLETE / STOPPED / BLOCKED

2. Base branch:
   main

3. Base SHA:
   ee72737406461df90980c51063fce297d7faa0be

4. Final branch:
   stage/03-market-data

5. Final SHA:
   <actual commit SHA>

6. origin branch SHA:
   <actual remote branch SHA>

7. Worktree:
   clean / exact remaining files

8. Changed files:
   <complete list>

9. Source schema findings:
   <short summary>

10. Timestamp findings:
    <short summary>

11. OI findings:
    <Binance and Bybit separately>

12. Funding findings:
    <Binance and Bybit separately>

13. Liquidation findings:
    <Binance and Bybit separately>

14. Read-only proof:
    <what was actually proven>

15. Canonical models:
    <implemented contracts>

16. Universe:
    <implemented behavior>

17. Features:
    <implemented formulas and cutoff>

18. Performance:
    <query count, p50, p95, memory>

19. Tests:
    <exact commands and exact results>

20. Migration:
    <clean apply and rerun>

21. monitor-data:
    <before/after SHA and diff evidence>

22. Secrets:
    <scan result>

23. Not proven:
    <complete list>

24. Open issues:
    <complete list>

25. Forbidden work verification:
    no Scanner;
    no Growth;
    no Levels;
    no Detector;
    no Signal;
    no Trading;
    no monitor-data modifications.

26. Next-stage statement:
    Stage 4 was not started.
    No permission to proceed was assumed.
```

Агент не выставляет себе `PASS`.

Допустимый финальный статус агента:

```text
READY FOR INDEPENDENT AUDIT
```

Verdict `PASS / PASS WITH ISSUES / REJECT` принимает отдельный аудиторский чат.

---

# 16. Условия немедленной остановки

Немедленно остановиться, если:

1. Base SHA не совпал.
2. Worktree не clean.
3. Обнаружены неизвестные локальные изменения.
4. `paper_market_reader` отсутствует и требуется production role creation.
5. Для продолжения нужно изменить `monitor-data`.
6. Для продолжения нужен новый индекс в `monitor-data`.
7. Требуется перезапуск старого контейнера.
8. Фактическая схема отличается так, что mapping нельзя доказать.
9. Нельзя доказать timestamp semantics.
10. Нельзя доказать closed-candle semantics.
11. Нельзя определить OI unit.
12. Нельзя определить liquidation side.
13. Funding table смешивает forecast и actual events без способа разделения.
14. Нет способа исключить future rows при replay.
15. Обнаружено смешивание Binance и Bybit.
16. Load test показывает N+1.
17. Query count растёт вместе с числом symbols.
18. Найден секрет.
19. Тест требует production write.
20. Появилась необходимость начать Stage 4.

При остановке:

```text
не обходить проблему;
не создавать временное предположение;
не менять архитектуру молча;
не продолжать следующие шаги;
зафиксировать точный blocker;
подготовить владельцу минимальный вопрос или запрос разрешения.
```

---

# 17. Критерии готовности к независимому аудиту

Этап может быть передан аудитору только если одновременно доказано:

```text
Binance и Bybit преобразуются в единый контракт;
Reader физически и логически read-only;
Reader не пишет Paper DB;
Universe и Features имеют отдельные Paper DB writers;
closed candle определена однозначно;
future candle исключается;
exact-next candle не перескакивает через gap;
gaps обнаруживаются;
duplicates обнаруживаются;
stale data обнаруживаются;
OI unit доказана;
funding semantics доказана;
liquidation side доказана;
cross-exchange mixing невозможно;
Features рассчитываются пакетно;
количество запросов не зависит от количества symbols;
нагрузка измерена;
формулы документированы;
в коде Market Data Layer нет trading-зависимостей;
monitor-data не изменён;
секретов нет;
Stage 4 не начат;
ветка опубликована отдельно от main;
worktree clean.
```

Если хотя бы один обязательный пункт не доказан, статус должен быть:

```text
BLOCKED
```

или:

```text
READY FOR AUDIT WITH EXPLICIT OPEN ISSUE
```

Но агент не имеет права самостоятельно объявлять `PASS`.
