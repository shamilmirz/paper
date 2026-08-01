# STAGE 4 / ТЗ №1 — SCANNER + GROWTH STATE

## 1. Цель задания

Реализовать для проекта `paper-trading-engine` два физически отдельных worker-контейнера:

```text
paper-scanner-binance
paper-scanner-bybit
```

Каждый контейнер должен включать два логически независимых компонента:

```text
Primitive Scanner
Growth State
```

Разрешается:

```text
одна кодовая база
один Docker image
два контейнера
разный EXCHANGE
```

Запрещается создавать:

```text
paper-growth-binance
paper-growth-bybit
```

Объединение Scanner и Growth в одном контейнере не должно объединять их ответственность, состояние, транзакции, роли, watermarks, метрики или обработку ошибок.

Stage 4 не создаёт торговые решения. Результат этого задания:

```text
canonical market data
→ primitive market event
→ immutable Candidate

canonical market data
→ Growth episode/state
→ Growth Candidate
```

Detector, Signal и торговые операции в задание не входят.

---

## 2. Исходное состояние

```text
Repository: shamilmirz/paper-trading-engine
Base branch: main
Required Base SHA: 0f745642f49262e3d714a377bb3811ffdc2dae36
Stage branch: stage/04-scanner-growth-levels
Previous Stage merge: 87df939c31dc5ee1a72f0a49c1345127a11ba74e
```

Перед любыми изменениями выполнить:

```bash
git fetch origin --prune
git branch --show-current
git rev-parse HEAD
git rev-parse origin/main
git status --short
git log -5 --oneline
```

Условия начала:

```text
origin/main == 0f745642f49262e3d714a377bb3811ffdc2dae36
новая ветка создаётся от origin/main
чужие tracked-изменения отсутствуют
untracked-файлы зафиксированы в отчёте и не удаляются
```

Создание ветки:

```bash
git switch main
git pull --ff-only origin main
git switch -c stage/04-scanner-growth-levels
```

Если ветка уже существует, сначала установить её происхождение и состояние. Нельзя force-reset чужой работы без разрешения владельца.

---

## 3. Обязательное чтение

До разработки прочитать полностью:

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

docs/stages/STAGE_03_REPORT.md
docs/stages/STAGE_03_EVIDENCE.md
docs/stages/STAGE_03_OPEN_ISSUES.md

docs/architecture/DATABASE_CONTRACT.md
docs/architecture/DATA_FLOW.md
docs/architecture/SCANNER_CONTRACT.md
docs/architecture/SERVICE_BOUNDARIES.md
docs/architecture/STATE_MACHINES.md
docs/architecture/TEST_STRATEGY.md
docs/architecture/MARKET_DATA_CONTRACT.md

docs/market_data/SOURCE_SCHEMA_AUDIT.md
docs/market_data/SOURCE_MAPPING.md
docs/market_data/TIMESTAMP_CONTRACT.md
docs/market_data/FEATURE_CONTRACT.md
docs/market_data/STAGE_03_PERFORMANCE_REPORT.md

migrations/001_stage2_foundation.sql
migrations/003_stage2_correction_2.sql
migrations/008_stage3_market_data.sql

src/paper_engine/domain/market_data/models.py
src/paper_engine/market_data/reader.py
src/paper_engine/market_data/postgres_reader.py
src/paper_engine/market_data/source_contracts.py
src/paper_engine/market_data/features.py
src/paper_engine/market_data/universe.py
src/paper_engine/market_data/publication.py
```

Обязательно зафиксировать отдельным разделом отчёта:

```text
что уже является утверждённой бизнес-логикой;
что следует из действующих архитектурных контрактов;
что является временным техническим default;
что остаётся production-блокером.
```

---

## 4. Жёсткие границы ответственности

### 4.1. Primitive Scanner

Scanner:

* читает только ACTIVE Universe;
* проверяет отдельные краткосрочные рыночные события;
* создаёт отдельный Candidate на каждое событие;
* не объединяет события в готовый setup;
* не выбирает LONG или SHORT;
* не определяет точку входа;
* не создаёт Signal;
* не читает счета и ledger;
* не открывает сделку;
* не зависит от Growth.

### 4.2. Growth State

Growth:

* ведёт отдельный episode для `exchange + symbol`;
* отслеживает длительный рост, OI-подтверждение, peak и correction;
* создаёт Growth Candidate только в утверждённых переходах;
* может связать собственный Candidate с общим liquidation event;
* не зависит от Scanner;
* не использует Scanner Candidate как обязательный вход;
* не определяет точку входа;
* не создаёт Signal или сделку.

### 4.3. Общая физическая изоляция

Один контейнер может запускать оба event loop, но обязательно:

```text
отдельные Python-модули
отдельные классы worker
отдельные Paper DB роли/DSN
отдельные watermarks
отдельные repository methods
отдельные метрики
отдельные heartbeat identities
отдельные error records
отдельные retry policy
```

Рекомендуемые heartbeat identities:

```text
paper-scanner-binance.scanner
paper-scanner-binance.growth
paper-scanner-bybit.scanner
paper-scanner-bybit.growth
```

Ошибка или остановка Growth не должна останавливать Scanner. Ошибка Scanner не должна блокировать Growth.

---

## 5. Источники и разрешённые записи

### Разрешённое чтение Market DB

Только через:

```text
MarketDataReader
PostgresMarketDataReader
canonical models
```

Запрещены raw SQL-запросы из Scanner/Growth к:

```text
candles_1m
candles_1h
oi_snapshots
funding
liq_snapshots
```

Запрещено обходить:

```text
source_contracts
quality policy
as_of
closed-candle cutoff
Reader batch limit
```

### Разрешённое чтение Paper DB

```text
market_universe
market_features
data_quality_incidents
собственные Stage 4 таблицы
service_heartbeats
```

### Разрешённые записи Paper DB

Только через узкие repository functions или `SECURITY DEFINER` функции:

```text
candidate_events
candidate_status_events
liquidation_spike_events
liquidation_window_marks
growth_episodes
growth_episode_events
producer_watermarks
stage4_processing_errors
service_heartbeats
```

### Запрещённые записи

```text
market_universe
market_features
trader_profiles
paper_accounts
financial_transactions
account_ledger
reservations
signals
paper_trades
execution_events
levels
Market DB
monitor-data
```

---

## 6. Production source gate

До реализации production runtime провести read-only повторную проверку source contracts.

Не изменять `monitor-data`.

Не менять коллекторы, таблицы, views или данные.

Нужно установить, можно ли документально доказать отдельно для Binance и Bybit:

```text
candle timestamp = OPEN_TS
OI unit и способ получения oi_base
funding row = actual funding event
liquidation side = liquidated LONG/SHORT position
notional = доказанный USD/USDT notional
```

Если доказательство отсутствует:

* не ослаблять `require_candle_open_ts`;
* не ставить `SourceUnit.BASE_ASSET` по предположению;
* не считать funding actual;
* не преобразовывать BUY/SELL в LONG/SHORT;
* не считать отсутствие данных нулём;
* продолжить unit/integration-разработку на canonical fixtures;
* production worker должен стартовать как `DEGRADED` или fail-closed;
* в `STAGE_04_OPEN_ISSUES.md` записать hard blocker;
* не заявлять production-runtime PASS.

---

## 7. Миграция и модели данных

Создать:

```text
migrations/009_stage4_scanner_growth.sql
```

Миграции `001–008` не изменять.

### 7.1. candidate_events

Минимальные поля:

```text
id UUID PRIMARY KEY
exchange
symbol
producer                 SCANNER | GROWTH
event_type
closed_event_bucket
event_window_start
event_window_end
detected_at
expires_at
status                   AVAILABLE | EXPIRED | INVALID
producer_version
quality_policy_version
quality_status
quality_reason_codes
as_of
source_cutoff
source_checksum
liquidation_event_id NULL
growth_episode_id NULL
payload JSONB
created_at
status_updated_at
```

Уникальность:

```text
exchange
+ symbol
+ producer
+ event_type
+ closed_event_bucket
+ producer_version
```

Candidate payload после создания immutable.

Разрешено менять только status projection и связанные status-поля через TX-03B/TX-03C.

Создать append-only:

```text
candidate_status_events
```

Каждый переход статуса должен иметь:

```text
candidate_id
from_status
to_status
transition_at
reason
policy_version
incident_id
idempotency_key
```

### 7.2. liquidation_spike_events

Один подтверждённый исходный event:

```text
event_id UUID
exchange
symbol
liquidation_side         LONG | SHORT
closed_3m_bucket
window_start
window_end
total_notional_quote
largest_single_notional_quote
liquidation_count
baseline_window_count
baseline_average_quote
multiple
quality_status
quality_reason_codes
source_checksum
source_identity_set
policy_version
created_at
```

Уникальность:

```text
exchange
+ symbol
+ liquidation_side
+ closed_3m_bucket
+ policy_version
```

Primitive Scanner и Growth имеют право ссылаться на один `event_id`, но создают разные Candidate с разными producer.

### 7.3. liquidation_window_marks

Для раннего триггера:

```text
exchange
symbol
liquidation_side
open_3m_bucket
first_large_event_at
largest_event_notional
event_count
policy_version
checked_at
```

Уникальность:

```text
exchange + symbol + liquidation_side + open_3m_bucket + policy_version
```

Mark не является Candidate.

### 7.4. growth_episodes

Поля:

```text
episode_id UUID
exchange
symbol
state
started_at
start_price
start_oi
growth_confirmed_at
peak_price
peak_at
peak_volume
peak_oi
current_price
price_growth_pct
oi_growth_pct
correction_started_at
correction_pct
last_processed_candle
producer_version
quality_policy_version
transition_version
created_at
updated_at
expired_at
```

Обязателен partial unique index:

```text
не более одного не-EXPIRED episode на exchange + symbol
```

### 7.5. growth_episode_events

Append-only история:

```text
event_id
episode_id
event_type
from_state
to_state
source_candle_open
source_candle_close
event_at
old_peak_price
new_peak_price
price_growth_pct
oi_growth_pct
correction_pct
quality_status
source_checksum
transition_version
idempotency_key
payload
```

История каждого обновления peak должна сохраняться.

### 7.6. producer_watermarks

Минимальные stream keys:

```text
SCANNER_1M
SCANNER_3M
SCANNER_FUNDING
SCANNER_LIQUIDATION
GROWTH_1M
GROWTH_LIQUIDATION
CANDIDATE_EXPIRY
```

Поля:

```text
component
exchange
stream_key
last_committed_bucket
last_source_event_ts
last_source_identity
producer_version
quality_policy_version
updated_at
```

Scanner и Growth не должны использовать общий watermark.

### 7.7. stage4_processing_errors

```text
id
component
exchange
symbol NULL
stream_key
bucket
error_class
retryable
message
correlation_id
run_id
first_seen_at
last_seen_at
attempt_count
resolved_at
metadata
```

Не записывать credentials, DSN или полный exception environment.

---

## 8. DB ownership и роли

Добавить least-privilege роли:

```text
paper_scanner_writer
paper_growth_writer
paper_candidate_status_writer
paper_stage4_auditor
```

Scanner container должен использовать отдельные Paper DB DSN:

```text
SCANNER_PAPER_DATABASE_DSN
GROWTH_PAPER_DATABASE_DSN
HEARTBEAT_DATABASE_DSN
```

Даже внутри одного контейнера Scanner не должен иметь UPDATE/INSERT прав на Growth tables, а Growth — на Scanner-only records.

Рекомендуемые функции:

```text
publish_scanner_candidate(...)
publish_growth_candidate(...)
expire_candidate(...)
invalidate_candidate(...)
publish_liquidation_spike(...)
mark_liquidation_window(...)
apply_growth_transition(...)
record_growth_peak(...)
advance_producer_watermark(...)
record_stage4_processing_error(...)
```

Требования:

* revoke from `PUBLIC`;
* execute только соответствующей роли;
* прямые широкие INSERT/UPDATE права не выдавать;
* payload conflict при той же identity должен завершаться ошибкой и DataQualityIncident;
* watermark и соответствующая запись должны фиксироваться атомарно;
* ошибка записи не продвигает watermark.

---

## 9. Candidate contract

Candidate TTL:

```text
15 минут
```

Рекомендуемая семантика:

```text
expires_at = event_window_end + 15 minutes
```

TTL нельзя начинать от времени позднего replay, иначе старое событие станет новым.

При поздней обработке:

* immutable Candidate может быть зарегистрирован;
* его status должен немедленно стать EXPIRED через TX-03B;
* Detector не должен увидеть его как AVAILABLE.

Глобальный cooldown по монете отсутствует.

По одной монете одновременно допустимы:

```text
PRICE_UP_30M
OI_UP_30M
VOLUME_SPIKE_3M
другие события
```

Новый закрытый bucket может создать новый Candidate.

Повтор того же bucket не создаёт дубль.

---

## 10. Primitive Scanner events

Все проценты хранить как `Decimal`.

`None` не превращать в `0`.

### 10.1. PRICE_UP_30M

На каждом закрытом минутном bucket:

```text
latest_close = close фактической последней закрытой 1m свечи
window_min_close = минимальный close в закрытом 30m окне
pct = (latest_close - window_min_close) / window_min_close × 100
```

Candidate создаётся при:

```text
pct >= 3
```

Требовать:

* непрерывные закрытые свечи;
* отсутствие future rows;
* положительный знаменатель;
* actual latest close, а не `MAX(close)` вместо последнего close.

Event type:

```text
PRICE_UP_30M
```

Payload:

```text
latest_close
minimum_close
minimum_close_at
price_change_pct
window_start
window_end
candle_count
quality
source identities/checksum
```

### 10.2. OI_UP_30M

Использовать только совместимый `oi_base`.

```text
latest_oi_base
minimum compatible oi_base внутри 30m окна
pct = (latest - minimum) / minimum × 100
```

Candidate при:

```text
pct >= 3
```

Не создавать при:

* `oi_base is None`;
* UNKNOWN/QUOTE/USD OI;
* несовместимом instrument type;
* несовместимом contract multiplier;
* нулевом знаменателе;
* недостаточном покрытии окна;
* устаревшем последнем OI.

Event type:

```text
OI_UP_30M
```

### 10.3. OI_UP_2H

Та же логика, закрытое окно 2 часа.

Candidate при:

```text
pct >= 5
```

Event type:

```text
OI_UP_2H
```

### 10.4. VOLUME_SPIKE_3M

Строить канонические 3m свечи из трёх последовательных закрытых 1m свечей, aligned по UTC:

```text
open   = open первой свечи
high   = max(high)
low    = min(low)
close  = close третьей свечи
volume = sum(volume_quote)
```

Если `volume_quote` отсутствует хотя бы у одной свечи — fail-closed.

Baseline:

```text
9 предыдущих полностью закрытых 3m свечей
```

Текущую 3m свечу в baseline не включать.

Условия:

```text
current_volume >= 10 × mean(previous_9_volumes)
close > open
baseline > 0
```

Event type:

```text
VOLUME_SPIKE_3M
```

Payload хранит OHLC, текущий объём, все baseline buckets, baseline average и multiple.

### 10.5. FUNDING_NEGATIVE_EXTREME

Обрабатывается только новое actual funding event.

Условие:

```text
normalized_rate <= Decimal("-0.02")
```

Event type:

```text
FUNDING_NEGATIVE_EXTREME
```

Запрещено:

* forward-fill;
* повторно считать одну запись новым event;
* считать отсутствие funding нулём;
* использовать observational funding;
* подключаться к exchange WebSocket.

`closed_event_bucket` для funding должен быть равен точному нормализованному `funding_event_ts`.

Хранить `source_identity` и checksum.

---

## 11. Ликвидационные всплески

LONG и SHORT обрабатываются полностью отдельно.

### 11.1. UTC 3m buckets

Все события группируются в закрытые UTC-окна:

```text
[00:00,00:03)
[00:03,00:06)
...
```

### 11.2. Ранний mark

Если отдельное событие:

```text
notional_quote >= 50 000
```

создать или обновить `liquidation_window_marks`.

Mark не создаёт Candidate.

### 11.3. Финальная проверка

После закрытия bucket проверить отдельно каждую сторону.

Условия:

```text
window_total >= 100 000

AND

window_total >= 5 × average(previous 480 closed 3m windows)
```

Baseline:

* только та же биржа;
* только та же монета;
* только та же liquidation side;
* текущее окно исключено;
* должно быть 480 закрытых окон;
* нулевые окна допустимы только когда источник доказан доступным и полным;
* missing/unavailable window не превращать в ноль;
* baseline `0` не должен приводить к делению на ноль: при полном baseline и нулевом среднем достаточно absolute threshold, а multiple сохранять как `None`/специальный детерминированный признак согласно versioned policy.

Создать один `liquidation_spike_event`.

Primitive Scanner создаёт:

```text
LONG_LIQUIDATION_SPIKE
SHORT_LIQUIDATION_SPIKE
```

с `producer=SCANNER` и ссылкой на `event_id`.

---

## 12. Growth State

Состояния:

```text
IDLE
GROWTH_STARTED
GROWTH_CONFIRMED
AT_PEAK
CORRECTING
EXPIRED
```

### 12.1. Рекомендуемый versioned default для discovery

Это технический default, а не новая бизнес-константа:

```text
discovery timeframe: закрытые 1h свечи
price basis: close
lookback: 7 дней
minimum move duration: 3 дня
maximum move duration: 7 дней
```

Детерминированный поиск:

1. Построить все допустимые пары `trough → later peak`.
2. Duration пары должна быть от 3 до 7 дней.
3. Рассчитать рост close-to-close.
4. Выбрать пару с максимальным ростом.
5. При равенстве выбрать более ранний trough, затем более ранний peak.
6. Использовать только свечи, закрытые к `as_of`.

Нельзя использовать будущие свечи.

### 12.2. GROWTH_STARTED

Переход:

```text
IDLE → GROWTH_STARTED
```

при:

```text
price_growth_pct >= 20
```

Сохранить:

```text
started_at
start_price
peak_price
peak_at
price_growth_pct
source candles/checksum
```

### 12.3. GROWTH_CONFIRMED

Переход:

```text
GROWTH_STARTED → GROWTH_CONFIRMED
```

при:

```text
compatible oi_base growth >= 5%
```

Начальный и текущий OI должны быть совместимы.

Если OI отсутствует, неизвестен, устарел или несовместим — переход не выполнять.

### 12.4. AT_PEAK

Переход:

```text
GROWTH_CONFIRMED → AT_PEAK
```

Peak после активации обновлять по фактическому close последней закрытой 1m свечи.

Сохранять:

```text
peak_price
peak_at
peak_volume
peak_oi
```

Каждое обновление peak записывать append-only в `growth_episode_events`.

### 12.5. CORRECTING

Correction:

```text
(peak_price - current_close) / peak_price × 100
```

При первом попадании в диапазон:

```text
10% <= correction <= 30%
```

выполнить:

```text
AT_PEAK → CORRECTING
```

и создать один Candidate:

```text
event_type = GROWTH_CORRECTION
producer = GROWTH
```

Повторный Candidate на каждой свече запрещён.

### 12.6. Новый peak после correction

Требование обновлять новый максимум конфликтует с неполной старой state-table.

Реализовать и документировать переход:

```text
CORRECTING → AT_PEAK
```

если новая закрытая свеча формирует close выше сохранённого peak.

Обновить:

```text
STATE_MACHINES.md
DECISIONS.md
GROWTH_CONTRACT.md
```

Не скрывать это как внутреннюю реализацию.

### 12.7. EXPIRED

Точный lifecycle expiry пока не является утверждённой бизнес-константой.

Предложить versioned defaults, покрыть тестами и записать в open issues. Минимально:

```text
correction > 30% → EXPIRED
```

Дополнительный time-based expiry должен быть конфигурационным и явно отмеченным как provisional.

### 12.8. Growth + liquidation

При подтверждённом liquidation spike Growth может создать отдельный Candidate, только если существует активный Growth episode.

Event types:

```text
GROWTH_LONG_LIQUIDATION_SPIKE
GROWTH_SHORT_LIQUIDATION_SPIKE
```

Payload:

```text
episode_id
growth_state
liquidation_side
price_growth_pct
oi_growth_pct
correction_pct
liquidation_event_id
peak data
quality
```

Ликвидация не изменяет:

```text
start_price
peak
correction
episode state
```

---

## 13. Scheduling, batches и restart

### Scanner schedules

После каждой закрытой 1m свечи:

```text
PRICE_UP_30M
OI_UP_30M
OI_UP_2H
```

После закрытия 3m окна:

```text
VOLUME_SPIKE_3M
LONG_LIQUIDATION_SPIKE
SHORT_LIQUIDATION_SPIKE
```

На новом actual funding event:

```text
FUNDING_NEGATIVE_EXTREME
```

### Growth schedules

После каждой закрытой 1m свечи:

```text
state transition
peak update
correction check
```

После liquidation spike:

```text
optional Growth Candidate
```

### Batch rules

```text
Reader request <= 100 unique symbols
```

Рекомендуемые initial defaults:

```text
scanner_batch_size: 100
growth_bootstrap_batch_size: 10
growth_incremental_batch_size: 100
```

Они являются техническими defaults и должны быть конфигурационными.

### Restart

После запуска каждый компонент:

1. Читает свой watermark.
2. Определяет safe overlap.
3. Повторно обрабатывает overlap.
4. Полагается на DB uniqueness, а не на память процесса.
5. Не создаёт дублей.
6. Продолжает с последнего полностью подтверждённого bucket.

Рекомендуемый overlap:

```text
1m streams: 5 минут
3m streams: 15 минут
funding: 24 часа
growth bootstrap: последние 7 дней только при отсутствии episode/checkpoint
```

Ошибка одной монеты:

* записывается отдельно;
* не останавливает обработку остальных монет;
* не продвигает общий watermark bucket;
* успешные записи остальных монет сохраняются идемпотентно;
* retry снова обрабатывает весь bucket без дублей.

---

## 14. Конфигурация

Создать:

```text
configs/services/stage4-scanner-growth-v1.yaml
configs/services/stage4-scanner-growth-v1.yaml.example
```

Обязательные versioned параметры:

```text
policy_version
producer_version
candidate_ttl_minutes
scanner_batch_size
growth_bootstrap_batch_size
growth_incremental_batch_size
safe_overlap
price_up_30m_pct
oi_up_30m_pct
oi_up_2h_pct
volume_spike_multiple
volume_baseline_3m_count
funding_negative_threshold
liquidation_early_notional
liquidation_absolute_notional
liquidation_multiple
liquidation_baseline_buckets
growth_price_threshold_pct
growth_oi_threshold_pct
growth_min_days
growth_max_days
correction_min_pct
correction_max_pct
episode_expiry
poll_interval
heartbeat_interval
```

Запрещены скрытые числовые constants в business calculators.

---

## 15. Структура кода

Минимально:

```text
src/paper_engine/domain/candidates/
src/paper_engine/domain/growth/

src/paper_engine/market_data/scanner/
    models.py
    calculators.py
    liquidation.py
    repository.py
    worker.py

src/paper_engine/market_data/growth/
    models.py
    discovery.py
    state_machine.py
    repository.py
    worker.py

src/paper_engine/runtime/stage4_scanner.py
src/paper_engine/health/

scripts/init_stage4_roles.py
scripts/stage4_scanner_smoke.py
```

Scanner не импортирует Growth implementation.

Growth не импортирует Scanner implementation.

Разрешён общий нейтральный модуль для:

```text
Candidate domain model
time bucket helpers
Decimal helpers
quality helpers
Reader batching
```

---

## 16. Docker

Создать Stage 4 image и compose.

Stage 4 application services — ровно:

```text
paper-scanner-binance
paper-scanner-bybit
paper-levels-binance
paper-levels-bybit
```

В рамках ТЗ №1 реализуются первые два. Не создавать growth service.

Scanner services:

```text
same image
SERVICE_MODE=scanner
EXCHANGE=BINANCE/BYBIT
```

Healthcheck контейнера должен проверять оба logical heartbeat:

```text
Scanner heartbeat свежий
Growth heartbeat свежий
нет terminal startup error
```

Если один компонент degraded, контейнер не должен ложно показывать полностью healthy.

Production deployment и перезапуск действующих `monitor-data` контейнеров запрещены.

---

## 17. Обязательные тесты

### Unit

Покрыть минимум:

* Decimal-only;
* naive datetime rejection;
* UTC normalization;
* только закрытые свечи;
* actual latest close;
* min close 30m;
* zero denominator;
* missing candle;
* gapped window;
* OI compatibility;
* OI UNKNOWN/quote rejection;
* min OI in 30m и 2h;
* правильная 3m OHLCV;
* предыдущие девять 3m buckets;
* green candle;
* funding actual/observational/missing/future;
* LONG/SHORT liquidation separation;
* 50k early mark;
* 100k absolute threshold;
* 5× baseline;
* current bucket exclusion;
* 480 baseline buckets;
* unavailable baseline;
* Candidate TTL;
* Candidate uniqueness;
* Growth 3–7 day discovery;
* OI confirmation;
* peak history;
* one correction Candidate;
* correction >30%;
* new peak after correction;
* Growth liquidation Candidate linkage.

### Integration PostgreSQL

Проверить TX-03A/B/C и TX-04:

* clean migration;
* rerun migration;
* role permissions;
* direct forbidden writes;
* Candidate immutability;
* status-only transition;
* concurrent duplicate Candidate;
* conflicting checksum;
* rollback;
* watermark atomicity;
* partial symbol failure;
* restart replay;
* Scanner/Growth role isolation;
* shared liquidation `event_id`;
* previous successful records preserved.

### Restart

Для Scanner и Growth отдельно:

```text
process bucket
crash before watermark
restart
replay overlap
no duplicates
watermark advances only after success
```

### Docker smoke

На disposable Market/Paper DB fixture:

* оба scanner containers стартуют;
* Binance не читает Bybit;
* Bybit не читает Binance;
* оба logical heartbeats появляются;
* canonical events создают ожидаемые Candidates;
* restart не создаёт дублей;
* отсутствие доказанного source contract приводит к DEGRADED/fail-closed, а не к fabricated data.

### Load

Проверить минимум:

```text
100-symbol Scanner batch
последовательную обработку 1100 synthetic Universe symbols
отсутствие Reader вызова >100 symbols
bounded memory
отсутствие N+1 на symbol
```

Не устанавливать latency gate, который противоречит фактической Stage 3 производительности. Сначала измерить и зафиксировать результаты.

---

## 18. Команды проверки

Минимальный набор:

```bash
python -m pytest tests/unit -q
python -m pytest tests/integration -q
python -m pytest tests/restart -q
python -m pytest tests/concurrency -q
python -m pytest tests/load -q

ruff check .
ruff format --check .
mypy src
python -m compileall src scripts

git diff --check
git status --short
git diff --stat
git diff --name-only
```

Миграции:

```bash
python scripts/migrate.py
python scripts/migrate.py
```

Docker:

```bash
docker compose -f docker-compose.stage4.yml config
docker compose -f docker-compose.stage4.yml build
docker compose -f docker-compose.stage4.yml up -d
docker compose -f docker-compose.stage4.yml ps
docker compose -f docker-compose.stage4.yml logs --no-color
docker compose -f docker-compose.stage4.yml restart paper-scanner-binance
docker compose -f docker-compose.stage4.yml restart paper-scanner-bybit
docker compose -f docker-compose.stage4.yml down
```

SQL evidence:

```text
таблицы и constraints существуют
роли имеют только ожидаемые grants
Candidate payload UPDATE/DELETE запрещены
повторная публикация no-op
checksum conflict fail-closed
watermark не продвинулся после rollback
heartbeats Scanner/Growth отдельные
```

---

## 19. Проверка monitor-data и секретов

До и после работы, если репозиторий доступен локально:

```bash
git -C <monitor-data-path> rev-parse HEAD
git -C <monitor-data-path> status --short
```

Не выполнять в `monitor-data`:

```text
checkout
reset
clean
commit
migration
docker compose up/down/restart
SQL write
```

В evidence записать before/after SHA и status.

Если `monitor-data` недоступен, так и написать. Запрещено выдумывать доказательство.

Проверка секретов:

```text
пароли
токены
private keys
реальные DSN с credentials
SSH credentials
exchange API keys
```

В Git допускаются только placeholders и `.example`.

---

## 20. Обязательные документы

Создать или обновить:

```text
docs/architecture/GROWTH_CONTRACT.md
docs/architecture/SCANNER_CONTRACT.md
docs/architecture/DATA_FLOW.md
docs/architecture/SERVICE_BOUNDARIES.md
docs/architecture/STATE_MACHINES.md
docs/architecture/DATABASE_CONTRACT.md
docs/architecture/TEST_STRATEGY.md

docs/stages/STAGE_04_REPORT.md
docs/stages/STAGE_04_EVIDENCE.md
docs/stages/STAGE_04_OPEN_ISSUES.md

README.md
CURRENT_STATE.md
TODO.md
HANDOFF.md
DECISIONS.md
```

Исправить stale Stage 3 merge status.

Не отмечать provisional технические defaults как окончательно утверждённые бизнес-параметры.

---

## 21. Критерии приёмки ТЗ №1

ТЗ №1 выполнено, если доказано:

1. Существуют только два scanner-контейнера, без growth-контейнеров.
2. Scanner и Growth логически и по DB ownership независимы.
3. Primitive события создают отдельные immutable Candidates.
4. Candidate uniqueness включает producer и producer version.
5. TTL равен 15 минутам и привязан к event time.
6. LONG/SHORT ликвидации не смешиваются.
7. Один liquidation event может использоваться двумя producers.
8. Growth ведёт durable episode и полную peak history.
9. Correction Candidate создаётся один раз.
10. Restart/replay не создаёт дублей.
11. Watermark не продвигается при ошибке записи.
12. Один symbol failure не останавливает остальные.
13. Reader batch никогда не превышает 100 symbols.
14. Market DB остаётся read-only.
15. monitor-data не изменён.
16. Нет секретов.
17. Production source limitations не скрыты.
18. Detector/Signal/trading код отсутствует.

---

## 22. Git

Использовать только:

```text
stage/04-scanner-growth-levels
```

Запрещено:

```text
разрабатывать в main
git add .
git add -A
force push
удалять чужие untracked
создавать PR
merge в main
```

Добавлять файлы только явным списком.

Оба ТЗ Stage 4 должны завершиться одним итоговым Stage 4 commit после выполнения Scanner/Growth и Levels.

Рекомендуемое сообщение:

```text
feat(stage4): implement scanner growth and levels
```

До завершения ТЗ №2 не выполнять итоговый Stage 4 commit, если владелец не дал другое указание.

---

## 23. Формат отчёта агента

```text
STAGE 4 — SCANNER/GROWTH REPORT

1. Base branch.
2. Base SHA.
3. origin/main SHA.
4. Stage branch.
5. Final working-tree state.
6. Список изменённых файлов.
7. Реализованная архитектура.
8. Таблицы и миграции.
9. Роли и permissions.
10. Scanner events.
11. Candidate contract.
12. Liquidation event contract.
13. Growth state machine.
14. Watermarks/restart.
15. Quality handling.
16. Unit tests.
17. Integration tests.
18. Concurrency tests.
19. Restart tests.
20. Docker smoke.
21. Load evidence.
22. Source-contract evidence.
23. Что доказано на canonical fixtures.
24. Что доказано на physical source.
25. Что не доказано.
26. monitor-data before/after proof.
27. Secret scan.
28. Open technical defaults.
29. Git diff/status.
30. Final SHA или причина отсутствия commit.
```

---

## 24. Условие остановки

После выполнения ТЗ №1:

* не начинать Detector;
* не создавать Signal;
* не открывать сделки;
* не изменять Accounts или Ledger;
* не начинать Stage 5;
* не создавать PR;
* не выполнять merge;
* перейти к ТЗ №2 только в той же Stage 4 ветке;
* при недоказанных production source semantics сохранить fail-closed и явно зафиксировать blocker.
