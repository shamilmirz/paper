# STAGE 4A — REAL SCANNER/GROWTH PIPELINE FINAL COMPLETION

## 0. Назначение документа

Это финальное техническое задание на завершение первой части Stage 4:

```text
Scanner + Growth
```

Документ продолжает работу в существующей ветке и не создаёт новый этап проектирования.

Текущий код уже содержит полезный фундамент:

- Stage 4 schema и migration 009;
- Candidate/Growth модели;
- часть вычислительных функций;
- PostgreSQL functions и роли;
- два Docker application container;
- config loader;
- начальные unit/integration/load tests.

Но текущий runtime всё ещё не выполняет реальный pipeline. Он в основном проверяет доступность таблиц и публикует heartbeat. Это ТЗ должно соединить существующие части в настоящий исполняемый, транзакционный, перезапускаемый Scanner/Growth сервис.

После независимого PASS этого задания следующей работой будет Stage 4B — Levels.

Levels в этом задании не начинать.

---

# 1. Конечная цель

После выполнения должна работать цепочка:

```text
Disposable Market DB fixtures
→ PostgresMarketDataReader
→ ACTIVE market_universe
→ exchange-scoped Scanner
→ primitive event calculations
→ immutable Scanner Candidates
→ Scanner watermarks/errors/heartbeat
→ exchange-scoped Growth
→ discovery/state transitions
→ immutable Growth events/Candidates
→ Growth watermarks/errors/heartbeat
→ Candidate expiry
→ restart/replay without duplicates
```

Должны существовать ровно два Stage 4 application container:

```text
paper-scanner-binance
paper-scanner-bybit
```

Внутри каждого одновременно работают два независимых логических компонента:

```text
<service>.scanner
<service>.growth
```

Candidate expiry работает через отдельную status writer role и не даёт Scanner/Growth прямого права менять статус Candidate.

---

# 2. Git baseline

Репозиторий разработки:

```text
shamilmirz/paper-trading-engine
```

Рабочая ветка:

```text
stage/04-scanner-growth-levels
```

Ожидаемый начальный локальный и удалённый HEAD:

```text
cdc2b96b113e53a9d744bc43c2656b295647ee7d
```

Ожидаемый `origin/main`:

```text
0f745642f49262e3d714a377bb3811ffdc2dae36
```

Перед работой выполнить:

```bash
git fetch origin
git branch --show-current
git rev-parse HEAD
git rev-parse origin/stage/04-scanner-growth-levels
git rev-parse origin/main
git status --short
git log --oneline origin/main..HEAD
```

Продолжать только если:

```text
branch = stage/04-scanner-growth-levels
HEAD = origin/stage/04-scanner-growth-levels
HEAD = cdc2b96b113e53a9d744bc43c2656b295647ee7d
origin/main = 0f745642f49262e3d714a377bb3811ffdc2dae36
```

Существующие untracked-файлы:

```text
docker-compose.stage4-test.yml.orig
runtime_service.py.orig
```

не изменять, не удалять и не добавлять в commit.

---

# 3. Разрешённые действия

Разрешено:

- изменять только текущую Stage 4 ветку;
- изменять ещё не слитую migration `009_stage4_scanner_growth.sql`;
- добавлять Stage 4 runtime, repositories, services, fixtures и tests;
- добавлять disposable Market DB service;
- удалять и пересоздавать только disposable Stage 4 Docker containers, networks и volumes;
- повторно применять migrations `001–009` на чистую disposable Paper DB;
- создавать test-only source contracts только для явно disposable Market DB;
- создавать один новый commit;
- выполнять обычный push в существующую ветку.

---

# 4. Запрещённые действия

Запрещено:

```text
не менять main
не создавать PR
не выполнять merge
не выполнять rebase опубликованной истории
не выполнять amend старых commit
не использовать force-push
не выполнять deployment
не использовать production Paper DB
не использовать production Market DB
не изменять monitor-data
не изменять production Docker services
не начинать Levels
не начинать Stage 5
не исправлять посторонние Stage 2 mypy-проблемы
не изменять migrations 001–008
не удалять сохранённые .orig-файлы
```

Production source contracts не объявлять доказанными и не ослаблять их fail-closed поведение.

---

# 5. Уже принятый фундамент — не переделывать без причины

Следующие решения считаются правильным направлением и должны быть сохранены:

- два application container: Binance и Bybit;
- один общий Stage 4 application image;
- non-root runtime;
- отсутствие bind mounts;
- изолированная disposable сеть;
- отдельные Scanner/Growth/Status роли;
- отдельные semantic SQL functions для Scanner и Growth Candidate;
- immutable Candidate payload;
- monotonic watermarks;
- config loader с `Decimal`, `timedelta`, запретом неизвестных полей и batch limit ≤100;
- Candidate TTL 15 минут от `event_window_end`;
- time-based Growth expiry остаётся provisional;
- production source-contract gate остаётся открытым.

Не тратить новый цикл только на повторную проверку этих пунктов. Изменять их только при необходимости для реального pipeline.

---

# 6. Известные блокирующие дефекты текущего HEAD

Новый код обязан исправить все перечисленные проблемы.

## 6.1 Runtime

Текущий runtime запускает два одинаковых generic heartbeat loop и не запускает:

- `PostgresMarketDataReader`;
- Scanner service;
- Growth service;
- Candidate expiry;
- реальные repositories;
- processing cycles.

Healthy сейчас подтверждает только доступность таблиц и свежесть heartbeat, а не функциональную работу.

## 6.2 Scanner

- нет полного цикла Universe → Reader → calculations → Candidate → DB;
- `PRICE_UP_30M` допускает разреженное окно;
- OI compatibility неполная;
- `VOLUME_SPIKE_3M` не привязан строго к UTC 3m boundary;
- liquidation baseline выбирает крупнейшие непустые buckets вместо предыдущих 480 последовательных окон;
- текущий load test вручную считает Reader request и напрямую создаёт Candidates;
- watermark продвигается даже при искусственной ошибке symbol.

## 6.3 Growth

- нет реального worker loop;
- нет нормальной операции создания episode;
- discovery не доказывает непрерывные 1h данные;
- start OI evidence хранится неполно;
- OI confirmation не проверяет, что price condition всё ещё выполняется;
- нет полного `AT_PEAK → AT_PEAK` поведения;
- нет прямого `AT_PEAK → EXPIRED` при correction >30%;
- processing checkpoint обновляется не на каждой успешно обработанной свече;
- Correction Candidate не создаётся текущим repository path.

## 6.4 Persistence и SQL

- `PostgresGrowthRepository` имеет несоответствие SQL placeholders и аргументов;
- реализация Growth repository не покрывает весь Protocol;
- Scanner Candidates и watermark публикуются отдельными транзакциями;
- durable UUID для status transition строится через нестабильный Python `hash()`;
- Candidate expiry repository не реализован;
- Growth Candidate получает неправильный TTL в SQL path;
- Growth replay не проверяет checksum/policy/payload conflict;
- liquidation spike replay может вернуть UUID, отсутствующий в таблице;
- processing error dedup не обеспечен реальной uniqueness semantics;
- нет разрешённого resolved path для processing error;
- SQL и Python role bootstrap расходятся.

## 6.5 Tests и документация

- нет настоящего end-to-end runtime test;
- нет отдельной disposable Market DB;
- нет restart/replay evidence;
- нет настоящего failure isolation;
- нет real Reader 100-symbol load;
- отсутствуют Stage 4 evidence/report/open-issues документы;
- `CURRENT_STATE.md`, `TODO.md`, `HANDOFF.md` всё ещё описывают Stage 3.

---

# 7. Целевая структура runtime

Реализовать отдельные компоненты. Допускаются другие имена, но обязанности должны быть физически разделены.

Рекомендуемая структура:

```text
src/paper_engine/stage4/
├── runtime.py
├── scanner_service.py
├── growth_service.py
├── expiry_service.py
├── heartbeat_service.py
├── universe_repository.py
├── factories.py
└── runtime_state.py
```

Существующий `runtime_service.py` может остаться entrypoint, но не должен содержать всю бизнес-логику.

Обязательные объекты:

```text
ScannerService
GrowthService
CandidateExpiryService
HeartbeatService
Stage4Runtime
```

У Scanner и Growth должны быть отдельные:

- service objects;
- repository objects;
- Paper DB pools;
- stream keys;
- watermarks;
- retry state;
- processing errors;
- metrics;
- heartbeat identity;
- terminal startup status.

Scanner не импортирует реализацию Growth.

Growth не импортирует реализацию Scanner.

---

# 8. Startup и shutdown

## 8.1 Startup sequence

При запуске каждого application container:

1. загрузить и валидировать Stage 4 config;
2. проверить `SERVICE_MODE=scanner`;
3. проверить `EXCHANGE=binance|bybit`;
4. создать Market DB pool;
5. создать Scanner Paper DB pool;
6. создать Growth Paper DB pool;
7. создать Candidate Status Paper DB pool;
8. создать heartbeat Paper DB pool;
9. проверить фактический `current_user` каждого DSN;
10. проверить разрешения каждого пользователя;
11. создать `PostgresMarketDataReader`;
12. выполнить `MarketDataReader.startup()`;
13. загрузить ACTIVE symbols своего exchange;
14. выполнить первый Scanner cycle;
15. выполнить первый Growth cycle;
16. выполнить первый expiry cycle;
17. только после этого публиковать `HEALTHY`.

## 8.2 Обязательные DB users

Startup должен проверить:

```text
SCANNER_DB_DSN          → paper_scanner_writer
GROWTH_DB_DSN           → paper_growth_writer
CANDIDATE_STATUS_DB_DSN → paper_candidate_status_writer
MARKET_DATA_DSN         → paper_market_reader
```

Heartbeat DSN должен использовать отдельную least-privilege login-role либо явно документированную роль с доступом только к `service_heartbeats`.

Проверки только имени БД в DSN недостаточно.

## 8.3 Shutdown

Обработать:

```text
SIGTERM
SIGINT
```

Shutdown должен:

- остановить новые cycles;
- дождаться завершения текущих DB transactions;
- отменить background tasks;
- записать terminal heartbeat/status;
- закрыть все pools;
- завершить процесс без dangling task warnings.

---

# 9. Реальный health contract

Компонент становится `HEALTHY` только после успешного processing cycle.

Heartbeat metadata каждого logical worker содержит:

```text
exchange
component
service_name
instance_id
started_at
last_cycle_started_at
last_cycle_finished_at
last_successful_bucket
processed_symbols
failed_symbols
last_watermark
last_error_class
last_error_at
producer_version
policy_version
```

Допустимые состояния:

```text
STARTING
HEALTHY
DEGRADED
FAILED
STOPPING
```

Container health успешен только если:

- Scanner heartbeat свежий;
- Growth heartbeat свежий;
- оба завершили хотя бы один cycle;
- нет terminal startup error;
- heartbeat age меньше установленного порога.

Ошибка Growth не останавливает Scanner loop.

Ошибка Scanner не останавливает Growth loop.

При terminal failure одного worker контейнер становится `DEGRADED`, второй worker продолжает работать до controlled shutdown.

---

# 10. Disposable Docker topology

`docker-compose.stage4-test.yml` должен содержать:

```text
stage4-paper-db
stage4-market-db
paper-scanner-binance
paper-scanner-bybit
```

Application services ровно два.

DB services не считаются application containers.

## 10.1 Требования

- отдельный Compose project;
- отдельная network;
- отдельные volumes Paper DB и Market DB;
- без `network_mode: host`;
- без bind mounts application code;
- application containers работают non-root;
- зависимости ставятся только при build;
- secrets передаются только environment variables;
- реальные пароли не находятся в Git;
- startup ordering использует DB healthchecks;
- final disposable runtime остаётся запущенным.

## 10.2 Имена ресурсов

Использовать уникальные disposable имена, например:

```text
paper-stage4-functional-disposable
paper-stage4-functional-paper-db
paper-stage4-functional-market-db
```

Существующие production и соседние resources не должны становиться orphan и не должны изменяться.

---

# 11. Disposable Market DB

Создать test-only Market DB, совместимую с существующим `PostgresMarketDataReader`.

Обязательные таблицы:

```text
public.candles_1m
public.oi_snapshots
public.funding
public.liq_snapshots
```

Schema должна соответствовать SQL, который использует текущий Reader.

Создать login-role:

```text
paper_market_reader
```

Требования к роли:

- `LOGIN`;
- SELECT только на необходимые Market DB tables;
- `default_transaction_read_only=on`;
- timezone UTC;
- нет superuser/createdb/createrole/replication/bypassrls;
- нет CREATE на `public`;
- нет INSERT/UPDATE/DELETE/TRUNCATE;
- безопасный `search_path`.

## 11.1 Test-only source contracts

Production source contracts не менять.

Для disposable fixtures разрешено передать Reader явные test-only contracts:

```text
candle timestamp semantics = OPEN_TS
OI source unit = BASE_ASSET
funding semantics = ACTUAL_SETTLED_EVENT
liquidation semantics = PROVEN_CANONICAL
```

Test-only contracts разрешены только при доказанном disposable database name и test mode.

Попытка применить их к другой БД должна завершаться terminal startup error.

---

# 12. Disposable Paper DB fixtures

Создать детерминированные `market_universe` fixtures:

```text
ACTIVE Binance symbols
ACTIVE Bybit symbols
INACTIVE controls
quality-ineligible controls
```

Scanner/Growth должны:

- читать только ACTIVE и quality-eligible symbols;
- читать только свой exchange;
- не создавать и не изменять `market_universe`;
- не читать symbols второй биржи.

SQL bootstrap Docker обязан выдавать Scanner/Growth SELECT на:

```text
market_universe
market_features
```

Python bootstrap и SQL bootstrap должны давать одинаковый набор прав.

---

# 13. ScannerService

## 13.1 Scanner cycle

Один Scanner cycle обязан:

1. получить UTC `as_of`;
2. загрузить собственный watermark;
3. вычислить safe overlap;
4. получить ACTIVE symbols своего exchange;
5. разделить symbols на batches ≤100;
6. вызвать существующий `PostgresMarketDataReader`;
7. получить canonical candles/OI/funding/liquidations;
8. сгруппировать данные по exchange+symbol;
9. выполнить primitive calculations;
10. создать immutable Candidates;
11. атомарно опубликовать successful bucket;
12. записать symbol-scoped errors;
13. обновить metrics;
14. продвинуть watermark только при полном bucket success.

## 13.2 Stream keys

Обязательные stream keys:

```text
SCANNER_1M
SCANNER_3M
SCANNER_FUNDING
SCANNER_LIQUIDATION
```

`CANDIDATE_EXPIRY` принадлежит expiry service/status writer, а не Scanner writer.

## 13.3 Primitive events

Scanner реализует:

```text
PRICE_UP_30M
OI_UP_30M
OI_UP_2H
VOLUME_SPIKE_3M
FUNDING_NEGATIVE_EXTREME
LONG_LIQUIDATION_SPIKE
SHORT_LIQUIDATION_SPIKE
```

Candidate сохраняет:

- exchange;
- symbol;
- producer;
- event type;
- closed bucket;
- event window;
- detected time;
- expiry;
- explicit `as_of`;
- source cutoff;
- source identities;
- canonical checksum;
- producer version;
- policy version;
- quality status/reasons;
- calculation payload.

---

# 14. Partial failure policy

При ошибке одного symbol:

- остальные symbols могут быть рассчитаны;
- их Candidates могут быть идемпотентно опубликованы;
- symbol-scoped processing error записывается;
- общий stream watermark этого bucket не продвигается;
- следующий cycle повторяет overlap/bucket;
- ранее опубликованные Candidates не дублируются;
- после исправления fixture ошибка помечается resolved;
- watermark продвигается только после полного успеха bucket.

Запрещено повторять текущую test-логику:

```text
ошибочный symbol пропущен
watermark всё равно продвинут
```

---

# 15. PRICE_UP_30M

Использовать только:

```text
30 последовательных полностью закрытых 1m candles
```

Требования:

- один exchange;
- один symbol;
- `interval=1m`;
- timezone-aware UTC;
- окно заканчивается на последней допустимой closed candle;
- ровно 30 expected open timestamps;
- отсутствие gaps;
- отсутствие duplicates;
- отсутствие out-of-order;
- все candles `COMPLETE`;
- invalid candle делает всё окно невалидным, а не просто удаляется;
- latest close сравнивается с minimum close в окне;
- threshold включительный `>=3%`.

Sparse набор из двух или нескольких разрозненных свечей должен вернуть fail-closed `None`/quality error и не создавать Candidate.

---

# 16. OI_UP_30M и OI_UP_2H

Использовать только compatible `oi_base`.

Совместимость включает:

```text
exchange
symbol
instrument_type
source_unit
conversion contract
contract_multiplier
quality status
```

Нельзя объединять observations с разными compatibility fields.

Требования:

```text
30m threshold >=3%
2h threshold >=5%
```

UNKNOWN, STALE, INVALID, UNAVAILABLE, отсутствующий `oi_base` или несовместимые observations:

```text
Candidate не создаётся
```

Payload обязан сохранять:

- initial/minimum OI;
- latest OI;
- timestamps;
- source identities;
- source unit;
- instrument type;
- multiplier;
- compatibility evidence;
- observation count.

---

# 17. VOLUME_SPIKE_3M

Определить последнюю полностью закрытую UTC boundary:

```text
boundary = floor(as_of to 3m)
current window = [boundary - 3m, boundary)
```

Требовать:

- ровно три последовательные 1m candles текущего bucket;
- current open = open первой candle;
- current close = close третьей candle;
- quote volume присутствует у всех candles;
- previous baseline = девять предыдущих выровненных fully closed 3m buckets;
- каждый baseline bucket состоит из трёх последовательных 1m candles;
- gaps, duplicates, invalid/out-of-order → fail closed;
- baseline mean >0;
- current volume `>=10 × baseline mean`;
- current close > current open.

Произвольное время poll не должно создавать невыравненный скользящий 3m bucket.

---

# 18. Funding

Обрабатывать только новый actual funding event.

Требования:

```text
normalized_rate <= -0.02
funding_event_ts <= as_of
точный funding timestamp используется как event bucket
source identity участвует в idempotency/checksum
forecast/observation funding игнорируется
unknown actualness fails closed
```

Replay одного actual event не создаёт второй Candidate.

---

# 19. Liquidation calculations

## 19.1 Dedup и фильтры

Перед расчётом фильтровать по:

```text
exchange
symbol
liquidated position side
quality=COMPLETE
time range
canonical deduplication_key
```

LONG и SHORT считаются независимо.

## 19.2 Current bucket

```text
current bucket = последний полностью закрытый UTC 3m bucket
```

Absolute condition:

```text
total_notional_quote >=100000
```

## 19.3 Baseline

Baseline состоит из:

```text
ровно предыдущих 480 последовательных закрытых UTC 3m buckets
```

В average входят нулевые buckets.

Запрещено:

- выбирать top 480;
- использовать buckets старше exact baseline range;
- исключать пустые buckets;
- смешивать другие exchange/symbol/side.

Relative condition:

```text
current total >=5 × previous-480 average
```

Baseline доступен только при доказанном полном временном диапазоне. Если полнота диапазона не доказана, Candidate не создаётся.

## 19.4 Early mark

Каждый source event фиксируется по уникальной identity.

Replay:

- не увеличивает `event_count`;
- не меняет первый event;
- не создаёт duplicate;
- может обновить `largest_event_notional` только новым уникальным event.

## 19.5 Spike publication

Replay одной spike identity:

- одинаковый checksum возвращает существующий фактический `event_id`;
- другой checksum вызывает fail-closed conflict;
- возвращаемый UUID существует в таблице.

---

# 20. Canonical checksum

Использовать deterministic canonical serialization.

Требования:

- sorted JSON keys;
- `Decimal` как нормализованная строка;
- datetime как UTC ISO-8601;
- UUID как строка;
- list/tuple сохраняют порядок;
- map сортируется по ключам;
- float запрещён;
- bool не принимается вместо numeric;
- checksum включает source identities;
- checksum включает source cutoff;
- checksum включает policy/producer version;
- checksum включает calculation payload.

Одинаковый payload должен давать одинаковый SHA-256 в разных Python process и после restart.

---

# 21. Scanner persistence transaction

Создать атомарную operation, принимающую:

```text
exchange
stream_key
bucket
source evidence
Candidates
producer version
policy version
```

В одной транзакции:

1. публикуются все Candidates successful bucket;
2. проверяются idempotency/checksum conflicts;
3. обновляется watermark.

Если публикация одного Candidate завершается ошибкой, watermark не обновляется.

При partial symbol failure операция watermark вообще не вызывается.

Repository не должен выполнять Candidate batch и watermark в двух независимых транзакциях.

---

# 22. GrowthService

## 22.1 Growth cycle

Один Growth cycle обязан:

1. получить UTC `as_of`;
2. загрузить Growth watermark;
3. получить ACTIVE symbols своего exchange;
4. загрузить active episode для каждого symbol;
5. если episode отсутствует — выполнить discovery;
6. получить candles и OI через Market Data Reader;
7. применить state machine по закрытым данным;
8. сохранить episode/checkpoint;
9. атомарно сохранить transition/event/optional Candidate/watermark;
10. записать errors;
11. обновить metrics/heartbeat.

## 22.2 Отсутствующий episode

Нужна разрешённая least-privilege операция создания нового episode.

Запрещено, чтобы integration test создавал episode напрямую администратором, а production path не имел такой операции.

Episode creation должна быть:

- идемпотентной;
- scoped по exchange+symbol;
- совместимой с one-active-episode constraint;
- с immutable start evidence;
- без прямой записи Growth role в таблицу.

---

# 23. Growth discovery

Default:

```text
closed 1h candles
7-day lookback
minimum duration 3 days
maximum duration 7 days
price growth >=20%
```

Требования:

- принимать только `interval=1h`;
- один exchange;
- один symbol;
- future candles запрещены;
- invalid/gapped/duplicated/out-of-order запрещены;
- если Reader отдаёт 1m candles, агрегировать час только из ровно 60 последовательных fully closed candles;
- incomplete hour не использовать;
- не запускать квадратичный алгоритм по 10 080 минутным candles;
- deterministic tie-breaking;
- no future leakage.

---

# 24. Start OI evidence

При создании episode сохранить:

```text
start_oi
start_oi_event_ts
start_oi_source_identity
start_oi_source_unit
start_oi_instrument_type
start_oi_contract_multiplier
start_oi_quality
```

Если требуется, расширить migration 009 и Growth model.

Стартовый OI выбирается по документированному правилу относительно trough/start time без future leakage.

Current OI должен быть совместим со start OI по всем compatibility fields.

Без совместимого start/current `oi_base` подтверждение роста запрещено.

---

# 25. Growth state machine

Обязательные состояния:

```text
IDLE
GROWTH_STARTED
GROWTH_CONFIRMED
AT_PEAK
CORRECTING
EXPIRED
```

## 25.1 IDLE → GROWTH_STARTED

Только если:

```text
price growth >=20%
duration 3–7 days
```

Сохранить start, current и peak evidence.

## 25.2 GROWTH_STARTED → GROWTH_CONFIRMED

Одновременно должны выполняться:

```text
current price growth >= configured price threshold
compatible OI growth >= configured OI threshold
```

Если цена уже потеряла условие роста, переход запрещён даже при OI росте.

## 25.3 GROWTH_CONFIRMED → AT_PEAK

Переход выполняется по следующей допустимой closed 1m candle.

Сохранить актуальные:

```text
current_price
peak_price
peak_at
last_processed_candle
```

Семантика должна быть явно описана в Growth contract и тестах.

## 25.4 AT_PEAK → AT_PEAK

Если новый close выше сохранённого peak:

- обновить peak;
- добавить immutable `PEAK_UPDATED` event;
- `from_state=AT_PEAK`;
- `to_state=AT_PEAK`;
- обновить checkpoint и watermark атомарно.

## 25.5 AT_PEAK → CORRECTING

На первой correction в диапазоне:

```text
10%..30% включительно
```

Формула:

```text
(peak_price - current_close) / peak_price ×100
```

В одной TX-04:

- обновить episode;
- добавить Growth event;
- создать ровно один `GROWTH_CORRECTION` Candidate;
- обновить Growth watermark.

## 25.6 AT_PEAK → EXPIRED

Если первая correction сразу:

```text
>30%
```

выполнить:

```text
AT_PEAK → EXPIRED
```

Correction Candidate не создаётся.

## 25.7 CORRECTING → AT_PEAK

Только если:

```text
current close > saved peak
```

Требования:

- `from_state=CORRECTING`;
- сохранить новый peak;
- добавить event;
- завершить старую correction phase.

## 25.8 CORRECTING → EXPIRED

Если correction >30%:

```text
CORRECTING → EXPIRED
```

## 25.9 Processing checkpoint

Каждая успешно обработанная closed candle должна обновлять processing checkpoint, даже если state transition не возник.

Нельзя повторно обрабатывать одну candle бесконечно только потому, что состояние не изменилось.

---

# 26. Growth Candidate

Correction Candidate identity включает:

```text
exchange
symbol
producer=GROWTH
event_type=GROWTH_CORRECTION
closed event bucket
producer version
growth episode id
correction phase identity
```

TTL:

```text
expires_at = event_window_end +15 minutes
```

Replay того же transition:

- не создаёт второй Candidate;
- одинаковый checksum возвращает существующий результат;
- конфликт payload/checksum/policy fail closed.

Новый peak после выхода из correction формирует новую correction phase. Следующий новый переход `AT_PEAK → CORRECTING` может создать новый Candidate.

---

# 27. Liquidation Candidate для Growth

Liquidation spike может создать отдельный Growth Candidate только при активном episode.

Он:

- не меняет Growth state;
- не меняет start/peak/correction;
- содержит FK на существующий liquidation spike event;
- содержит FK на Growth episode;
- сохраняет LONG/SHORT отдельно;
- идемпотентен по spike identity + Growth producer version.

---

# 28. TX-04 и Growth persistence

Создать или исправить атомарную SQL operation:

```text
create episode / lock episode
expected from_state check
source candle identity check
transition version check
policy version check
checksum check
idempotency check
projection update
append-only Growth event
optional Growth Candidate
Growth watermark
```

При любой ошибке транзакция полностью откатывается.

Replay:

- идентичный input → no-op/существующий результат;
- другой checksum → fail closed;
- другой policy/transition version → fail closed;
- другой Candidate payload → fail closed.

`PostgresGrowthRepository` обязан:

- иметь правильное количество placeholders;
- реализовать полный Protocol;
- загружать active episode;
- создавать episode разрешённой функцией;
- сохранять transition;
- не публиковать Correction Candidate второй отдельной транзакцией;
- проверять тип и фактическое существование возвращённых IDs.

---

# 29. Stable identifiers

Запрещено использовать Python:

```python
hash()
```

для durable identity.

Использовать:

```text
UUIDv5 с явным namespace
canonical SHA-256
стабильную составную identity
```

Одинаковая операция должна получать одинаковый ID в другом Python process и после restart.

---

# 30. Candidate expiry

Реализовать:

```text
PostgresCandidateStatusRepository.expire_available()
CandidateExpiryService
CANDIDATE_EXPIRY watermark/checkpoint
```

Expiry использует только:

```text
paper_candidate_status_writer
```

Он переводит:

```text
AVAILABLE → EXPIRED
```

при:

```text
now >= expires_at
```

Требования:

- `FOR UPDATE SKIP LOCKED` или эквивалентная безопасная конкуренция;
- status projection и audit event атомарны;
- replay идемпотентен;
- first terminal transition wins;
- Scanner/Growth roles не имеют EXECUTE status functions.

---

# 31. Processing errors

Создать реальную deterministic unresolved error identity, например:

```text
component
exchange
symbol
stream_key
bucket
error_class
correlation_id
resolved_at IS NULL
```

Добавить подходящий unique index/constraint.

Повтор одной ошибки:

- не создаёт новую строку;
- `attempt_count +=1`;
- обновляет `last_seen_at`;
- сохраняет `first_seen_at`;
- обновляет допустимую metadata.

После успешного retry:

- строка получает `resolved_at`;
- сохраняется resolution metadata;
- новый независимый инцидент позже может создать новую строку.

Repository должен записывать реальные exchange, symbol, bucket и stream, а не `unknown`.

---

# 32. Role ownership и grants

Нормативная матрица:

## Scanner writer

Разрешено:

- SELECT `market_universe`, `market_features`;
- SELECT собственных Scanner evidence/watermarks/errors;
- EXECUTE Scanner Candidate batch/TX function;
- EXECUTE liquidation spike/mark functions;
- EXECUTE Scanner watermark/error functions;
- собственный heartbeat path.

Запрещено:

- Growth episode/event writes;
- status transition;
- finance/trades/signals/levels writes;
- direct table INSERT/UPDATE.

## Growth writer

Разрешено:

- SELECT `market_universe`, `market_features`;
- SELECT Growth episodes/events/watermarks/errors;
- EXECUTE episode create/TX-04/Growth Candidate functions;
- Growth watermark/error functions;
- собственный heartbeat path.

Запрещено:

- Scanner-only records;
- status transition;
- finance/trades/signals/levels writes;
- direct table INSERT/UPDATE.

## Candidate status writer

Разрешено:

- SELECT Candidate/status rows;
- EXECUTE expiry/invalidation functions.

Запрещено:

- изменение Candidate payload;
- Scanner/Growth publication;
- finance writes.

SQL bootstrap и Python bootstrap должны давать одинаковые permissions.

Добавить автоматический grant-parity test.

---

# 33. Regression tests — сначала доказать текущие дефекты

Перед исправлением добавить тесты, которые падают на текущем HEAD:

```text
runtime создаёт настоящий PostgresMarketDataReader
runtime создаёт разные ScannerService и GrowthService
runtime запускает CandidateExpiryService
generic heartbeat loop не считается processing loop
DB users проверяются по current_user
Growth repository SQL arity совпадает
Growth repository реализует полный Protocol
Growth episode может быть создан least-privilege role
Correction Candidate создаётся внутри TX-04
Growth Candidate TTL =15 минут
stable ID одинаков в разных Python processes
PRICE_UP_30M требует ровно 30 continuous candles
invalid candle делает окно fail closed
OI compatibility проверяется полностью
VOLUME_SPIKE использует UTC-aligned bucket
liquidation baseline использует exact previous 480 buckets
zero liquidation buckets входят в average
старые liquidation events исключаются
AT_PEAK сразу expires при correction >30%
OI confirmation повторно проверяет price threshold
AT_PEAK new peak создаёт AT_PEAK→AT_PEAK event
processing checkpoint обновляется без transition
processing error replay увеличивает attempt_count
processing error может быть resolved
spike replay возвращает существующий UUID
Docker bootstrap даёт Universe/Features SELECT
```

После этого исправить код до PASS.

---

# 34. Unit tests

Минимальный обязательный набор Scanner:

- PRICE 30m positive;
- exact threshold;
- below threshold;
- sparse window;
- missing candle;
- duplicate candle;
- invalid candle;
- mixed symbol;
- mixed exchange;
- future candle;
- OI 30m positive;
- OI 2h positive;
- incompatible unit;
- incompatible instrument;
- incompatible multiplier;
- missing OI;
- volume exact UTC alignment;
- arbitrary poll time;
- missing current candle;
- missing baseline candle;
- zero baseline;
- funding actual;
- funding forecast;
- funding future;
- funding replay;
- liquidation exact 480 windows;
- zero buckets in average;
- old event excluded;
- duplicate event deduped;
- LONG/SHORT independence;
- canonical checksum stable;
- float forbidden.

Минимальный обязательный набор Growth:

- discovery only 1h;
- 1m→1h requires 60 candles;
- incomplete hour rejected;
- future leakage rejected;
- duration <3 days rejected;
- duration >7 days rejected;
- deterministic tie-breaking;
- start OI full evidence;
- incompatible OI rejected;
- price threshold at start;
- price threshold rechecked at confirmation;
- OI threshold boundary;
- GROWTH_CONFIRMED→AT_PEAK;
- AT_PEAK→AT_PEAK;
- correction exactly 10%;
- correction exactly 30%;
- AT_PEAK direct >30% expiry;
- CORRECTING new peak;
- CORRECTING >30% expiry;
- checkpoint without transition;
- one Candidate per correction phase;
- replay no duplicate Candidate;
- Growth liquidation Candidate does not mutate state.

---

# 35. PostgreSQL integration tests

На чистой disposable Paper DB проверить:

- migrations `001–009`;
- повторный запуск migration 009;
- role creation;
- role grant parity;
- Scanner cannot publish Growth Candidate;
- Growth cannot publish Scanner Candidate;
- Scanner/Growth cannot direct INSERT/UPDATE;
- Scanner/Growth cannot write financial tables;
- Candidate replay same checksum;
- Candidate checksum conflict;
- status idempotency collision;
- first terminal transition wins;
- expiry replay;
- early mark replay;
- spike replay existing ID;
- spike checksum conflict;
- episode creation;
- one active episode constraint;
- TX-04 full commit;
- TX-04 optional Candidate;
- TX-04 rollback on forced Candidate error;
- Growth replay same input;
- Growth checksum/policy conflict;
- concurrent Candidate publication;
- concurrent Growth transition;
- immutable Candidate payload;
- immutable Growth event;
- processing error replay;
- processing error resolution;
- watermark monotonicity.

Tests не должны использовать admin direct INSERT как замену отсутствующему application path, кроме подготовки явно внешних prerequisite fixtures.

---

# 36. Настоящий end-to-end runtime test

Запустить полный disposable Compose:

```text
Paper DB
Market DB
Binance application container
Bybit application container
```

Fixtures должны привести к реальным результатам через Reader/runtime/repositories.

## Binance evidence

Получить как минимум:

- один Scanner Candidate;
- один active Growth episode;
- один Growth event;
- один `GROWTH_CORRECTION` Candidate;
- Scanner watermark;
- Growth watermark;
- Scanner heartbeat;
- Growth heartbeat.

## Bybit evidence

Получить как минимум:

- отдельный Scanner Candidate;
- отдельный Growth episode/event;
- отдельные Scanner/Growth watermarks;
- отдельные heartbeat identities.

Проверить:

- Binance container не обрабатывает Bybit symbols;
- Bybit container не обрабатывает Binance symbols;
- Candidate/Growth rows не смешивают exchange;
- DSN users соответствуют ролям;
- application containers non-root;
- bind mounts отсутствуют.

---

# 37. Restart/replay acceptance

После первого успешного processing:

```bash
docker compose -p paper-stage4-functional-disposable -f docker-compose.stage4-test.yml restart
```

После restart доказать:

- Candidate count не увеличился от replay;
- Growth event count не увеличился от replay;
- Correction Candidate не задублирован;
- episode state сохранился;
- watermarks не откатились;
- processing продолжился с bounded overlap;
- heartbeat восстановились;
- оба application containers healthy.

---

# 38. Failure isolation acceptance

Подготовить fixture с одной контролируемой ошибкой одного symbol.

## Первый cycle

Доказать:

- остальные symbols обработаны;
- symbol-scoped error создан;
- `attempt_count=1`;
- общий соответствующий watermark не продвинут;
- другой logical worker продолжает работу;
- контейнер отражает `DEGRADED`, а не ложный `HEALTHY`.

## Retry

Исправить fixture и дождаться следующего cycle.

Доказать:

- тот же bucket повторён;
- ранее опубликованные Candidates не продублированы;
- ошибочный symbol обработан;
- error получает `resolved_at`;
- watermark продвигается;
- component возвращается в `HEALTHY`.

---

# 39. Настоящий 100-symbol load

Создать 100 ACTIVE symbols одной биржи в disposable fixtures.

Load test обязан вызвать настоящий `ScannerService.run_cycle()` или эквивалентный production path.

Запрещено вручную задавать:

```python
reader_requests += 1
```

Использовать фактические метрики:

```text
PostgresMarketDataReader.last_query_count
PostgresMarketDataReader.query_stats
Paper repository query count
service metrics
```

Зафиксировать:

```text
symbol_count
actual Reader query count
Reader batch sizes
Paper DB query count
duration
peak RSS
tracemalloc peak
Candidates created
errors
watermark before
watermark after
```

Требования:

- batch ≤100;
- нет Market query per symbol;
- нет Paper DB insert per Candidate там, где существует batch function;
- bounded memory;
- no N+1 explosion;
- cycle завершается;
- при одном bad symbol watermark не продвигается;
- после retry watermark продвигается.

Не заявлять production performance.

---

# 40. Quality gates

Выполнить:

```bash
python -m compileall src tests
ruff check src tests
ruff format --check src tests
mypy \
  src/paper_engine/runtime_service.py \
  src/paper_engine/stage4_config.py \
  src/paper_engine/persistence.py \
  src/paper_engine/domain/candidates \
  src/paper_engine/domain/growth \
  src/paper_engine/market_data/scanner \
  <все новые Stage 4 modules> \
  scripts/init_stage4_roles.py
pytest -q tests/unit
pytest -q tests/integration/test_stage4_db.py
pytest -q <Stage 4 runtime integration suite>
pytest -q tests/load/test_stage4_load.py
git diff --check
```

Требования:

- integration tests не skipped;
- runtime integration не skipped;
- load test не skipped;
- targeted mypy покрывает все новые/изменённые Stage 4 modules;
- blanket ignore не используется для сокрытия новых ошибок.

Full repository mypy не является gate из-за уже известных посторонних Stage 2 проблем.

---

# 41. Docker acceptance commands

На чистом disposable окружении:

```bash
docker compose \
  -p paper-stage4-functional-disposable \
  -f docker-compose.stage4-test.yml \
  down -v --remove-orphans

docker compose \
  -p paper-stage4-functional-disposable \
  -f docker-compose.stage4-test.yml \
  config

docker compose \
  -p paper-stage4-functional-disposable \
  -f docker-compose.stage4-test.yml \
  build --no-cache

docker compose \
  -p paper-stage4-functional-disposable \
  -f docker-compose.stage4-test.yml \
  up -d

docker compose \
  -p paper-stage4-functional-disposable \
  -f docker-compose.stage4-test.yml \
  ps
```

Сохранить:

```bash
docker inspect <binance-container>
docker inspect <bybit-container>
docker logs <binance-container>
docker logs <bybit-container>
```

Доказать:

- ровно два application containers;
- отдельные Paper DB и Market DB;
- application containers non-root;
- bind mounts отсутствуют;
- реальные Scanner/Growth cycles видны в logs;
- реальные Candidate/Growth rows созданы;
- health до restart;
- health после restart;
- idempotency после restart.

Final disposable runtime оставить запущенным.

---

# 42. Documentation и evidence

Создать:

```text
docs/stages/STAGE_04A_EVIDENCE.md
docs/stages/STAGE_04_OPEN_ISSUES.md
docs/stages/STAGE_04_REPORT.md
```

Обновить:

```text
CURRENT_STATE.md
TODO.md
HANDOFF.md
```

Корректный статус до независимой проверки:

```text
Stage 4A Scanner/Growth real pipeline published — awaiting independent audit.
Stage 4B Levels not started.
Production source contracts remain unresolved.
```

Не объявлять весь Stage 4 завершённым.

## 42.1 Evidence должен содержать

- base SHA;
- previous HEAD;
- new HEAD;
- changed files;
- architecture diagram;
- actual runtime classes;
- actual DB users;
- role grants;
- migration/schema/functions;
- unit/integration/runtime/load commands;
- exact pass counts;
- fixture description;
- Candidate rows;
- Growth rows;
- watermarks;
- heartbeat metadata;
- restart before/after counts;
- failure-isolation evidence;
- error resolution evidence;
- rollback evidence;
- load measurements;
- Docker image digests;
- container users;
- mounts;
- open production source blockers.

Слово `PASS` использовать только рядом с конкретным выполненным gate и его результатом.

---

# 43. Selective staging

Перед staging:

```bash
git diff --name-status
git ls-files --others --exclude-standard
```

Не использовать:

```bash
git add .
git add -A
git add --all
```

Добавлять только точные Stage 4 paths.

Не добавлять:

```text
*.orig
.env
пароли
DSN с credentials
логи
DB dumps
Docker volumes
__pycache__
.pytest_cache
.mypy_cache
.ruff_cache
посторонние файлы
```

После staging:

```bash
git diff --cached --name-status
git diff --cached --stat
git diff --cached --check
git diff --cached -- migrations/009_stage4_scanner_growth.sql
git diff --cached -- docker-compose.stage4-test.yml
git diff --cached -- src/paper_engine
git diff --cached -- tests
git diff --name-status
```

Проверить:

- migrations 001–008 не изменены;
- Levels отсутствует;
- monitor-data отсутствует;
- `.orig` отсутствуют;
- credentials отсутствуют;
- все tracked Stage 4 changes staged.

---

# 44. Commit

Создать один новый commit:

```text
fix(stage4): wire real scanner growth pipeline
```

Не выполнять:

```text
amend
rebase
squash
reset опубликованной истории
force-push
```

После commit:

```bash
git rev-parse HEAD
git show --stat --oneline --decorate HEAD
git diff HEAD^ HEAD --check
```

---

# 45. Проверка commit snapshot

Создать detached worktree из нового HEAD:

```bash
VERIFY_DIR=$(mktemp -d /tmp/paper-stage4a-final.XXXXXX)
git worktree add --detach "$VERIFY_DIR" HEAD
```

Внутри snapshot повторить:

```text
compileall
ruff check
ruff format --check
targeted mypy
unit tests
DB integration tests
runtime integration tests
load test
Docker Compose config
```

Тесты не должны зависеть от незакоммиченных файлов.

После проверки удалить только временный worktree.

Основной final disposable runtime не останавливать.

---

# 46. Push

После всех gate:

```bash
git push origin stage/04-scanner-growth-levels
```

Без force-push.

Проверить:

```bash
LOCAL_HEAD=$(git rev-parse HEAD)
REMOTE_HEAD=$(git ls-remote origin refs/heads/stage/04-scanner-growth-levels | awk '{print $1}')
printf 'LOCAL_HEAD=%s\nREMOTE_HEAD=%s\n' "$LOCAL_HEAD" "$REMOTE_HEAD"
test "$LOCAL_HEAD" = "$REMOTE_HEAD"
```

Не создавать PR.

Не выполнять merge.

---

# 47. Definition of Done

Stage 4A считается готовым к независимому аудиту только если одновременно выполнено всё:

```text
1. Runtime реально использует PostgresMarketDataReader.
2. Runtime реально запускает разные ScannerService и GrowthService.
3. CandidateExpiryService реально запущен.
4. Scanner создаёт Candidates из Market fixtures.
5. Growth создаёт episode/events/Correction Candidate из Market fixtures.
6. Binance и Bybit физически изолированы.
7. Scanner/Growth используют разные DB roles и pools.
8. Watermark не продвигается при partial failure.
9. Replay/restart не создаёт duplicates.
10. Growth TX-04 атомарен.
11. Candidate expiry работает отдельной role.
12. Processing errors deduplicated и resolved.
13. PRICE/OI/VOLUME/FUNDING/LIQUIDATION формулы соответствуют контракту.
14. Настоящий 100-symbol load использует Reader/service path.
15. Unit, DB integration, runtime integration и load tests PASS.
16. Evidence и status docs обновлены.
17. Один новый commit опубликован без force-push.
18. Levels не начат.
19. Production DB и monitor-data не затронуты.
```

Healthy heartbeat без фактических Candidate/Growth результатов не считается выполнением.

---

# 48. Финальный отчёт агента

Вернуть строго следующий отчёт:

```text
STAGE 4A — REAL PIPELINE FINAL REPORT

Baseline HEAD:
Previous remote HEAD:
New local HEAD:
New remote HEAD:
Commits ahead of main:
Tracked working tree:
Preserved untracked .orig files:

Runtime wiring:
- entrypoint:
- Stage4Runtime class:
- ScannerService class:
- GrowthService class:
- CandidateExpiryService class:
- HeartbeatService class:
- MarketDataReader class:
- graceful shutdown:

Actual DB users:
- scanner:
- growth:
- candidate status:
- heartbeat:
- market reader:

Docker topology:
- Compose project:
- Paper DB service:
- Market DB service:
- Binance application service:
- Bybit application service:
- application container users:
- bind mounts:
- networks:
- volumes:

Scanner evidence:
- ACTIVE Binance symbols:
- ACTIVE Bybit symbols:
- actual Reader query count:
- event types produced:
- Candidate rows:
- partial failure behavior:
- watermark before failure:
- watermark after failure:
- watermark after retry:

Growth evidence:
- episode creation:
- start OI evidence:
- transitions:
- peak update:
- direct >30% expiry:
- Correction Candidate:
- Candidate TTL:
- atomic TX-04:
- replay result:

Database evidence:
- migrations 001–009:
- migration 009 replay:
- role grant parity:
- forbidden writes:
- Candidate checksum conflict:
- Growth checksum conflict:
- liquidation spike replay:
- early mark replay:
- expiry replay:
- processing error replay:
- processing error resolution:
- rollback:
- concurrency:

Runtime integration:
- Binance Candidate count:
- Binance Growth episode/event count:
- Bybit Candidate count:
- Bybit Growth episode/event count:
- cross-exchange leakage:
- initial health:
- restart health:
- Candidate count before/after restart:
- Growth event count before/after restart:

Failure isolation:
- injected symbol:
- unaffected symbols:
- error row:
- attempt count:
- watermark while failing:
- resolution:
- watermark after retry:

100-symbol load:
- actual Reader query count:
- Reader batch sizes:
- Paper DB query count:
- duration:
- peak RSS:
- tracemalloc peak:
- Candidates:
- errors:
- watermark:

Quality gates:
- compileall:
- ruff check:
- ruff format:
- targeted mypy:
- unit tests:
- DB integration tests:
- runtime integration tests:
- load test:
- git diff --check:
- detached commit snapshot:

Evidence files:
- STAGE_04A_EVIDENCE.md:
- STAGE_04_OPEN_ISSUES.md:
- STAGE_04_REPORT.md:
- CURRENT_STATE.md:
- TODO.md:
- HANDOFF.md:

Production Paper DB used: NO
Production Market DB used: NO
Production source contracts changed: NO
monitor-data modified: NO
Levels started: NO
PR created: NO
Merge performed: NO
Deployment performed: NO
Force-push performed: NO
Remote SHA matches local SHA:
```

После push и отчёта остановиться.

Не начинать Levels самостоятельно.
