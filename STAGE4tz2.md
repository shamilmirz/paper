# STAGE 4 / ТЗ №2 — LEVELS BUILDER

## 1. Цель задания

Реализовать два физически отдельных Levels-контейнера:

```text
paper-levels-binance
paper-levels-bybit
```

Каждый контейнер работает только со своей биржей.

Разрешается:

```text
одна кодовая база
один Docker image
разный EXCHANGE
```

Levels Builder должен:

* строить price-volume зоны;
* сохранять immutable определение зоны;
* сохранять lineage и исходные свечи;
* поддерживать историю касаний, реакций, пробоев и ретестов;
* поддерживать текущую projection;
* классифицировать значимость и свежесть;
* публиковать только полный READY;
* сохранять предыдущий READY при ошибке.

Levels Builder не создаёт:

```text
Scanner Candidate
Growth Candidate
Signal
Trade
Reservation
Ledger entry
```

---

## 2. Исходное состояние

```text
Repository: shamilmirz/paper-trading-engine
Original Stage 4 Base SHA: 0f745642f49262e3d714a377bb3811ffdc2dae36
Branch: stage/04-scanner-growth-levels
Required predecessor: выполненное ТЗ №1 без merge
Migration predecessor: 009_stage4_scanner_growth.sql
New migration: 010_stage4_levels.sql
```

До изменений повторить:

```bash
git branch --show-current
git rev-parse HEAD
git rev-parse origin/main
git status --short
git log -5 --oneline
```

Убедиться, что изменения ТЗ №1 принадлежат этой же Stage 4 работе.

Не создавать вторую Stage 4 ветку без прямого указания владельца.

---

## 3. Обязательное чтение

Помимо общего набора документов и результата ТЗ №1, обязательно прочитать:

```text
docs/architecture/DATABASE_CONTRACT.md
docs/architecture/DATA_FLOW.md
docs/architecture/SERVICE_BOUNDARIES.md
docs/architecture/STATE_MACHINES.md
docs/architecture/TEST_STRATEGY.md
docs/architecture/MARKET_DATA_CONTRACT.md

docs/market_data/SOURCE_SCHEMA_AUDIT.md
docs/market_data/SOURCE_MAPPING.md
docs/market_data/TIMESTAMP_CONTRACT.md
docs/market_data/FEATURE_CONTRACT.md
docs/market_data/STAGE_03_PERFORMANCE_REPORT.md

migrations/008_stage3_market_data.sql
migrations/009_stage4_scanner_growth.sql
```

Проверить отсутствие действующего Levels implementation. Старые документы с `level_price` не считать достаточным zone contract.

---

## 4. Границы ответственности

Levels Builder:

* читает ACTIVE Universe;
* получает реальные закрытые свечи через Market Data Reader;
* строит зоны только по цене и объёму;
* хранит formation evidence;
* обслуживает зоны;
* поддерживает текущий рыночный контекст будущего Detector.

Levels Builder не зависит от:

```text
Scanner
Growth
Candidate
Detector
Signal
Account
Ledger
Trade
```

OI, funding и ликвидации не участвуют в:

```text
создании базовой зоны
расчёте zone_low/zone_high
перемещении зоны
удалении зоны
```

Они могут быть сохранены только как отдельный optional context при formation/touch/reaction после доказательства source semantics.

---

## 5. Источники данных

### Market DB

Только через Market Data Reader.

Запрещён raw SQL из Levels modules.

Текущий Reader читает только `candles_1m`. Для Levels разрешено расширить Reader contract, но только при соблюдении Stage 3 invariants.

Допустимые варианты:

1. Провести read-only audit `candles_1h` и добавить отдельный canonical method:

```text
fetch_hourly_candles(...)
```

2. Если hourly source не доказан — агрегировать canonical закрытые 1m свечи в 1h внутри проекта.

Запрещено считать `candles_1h` доказанным только потому, что таблица существует.

Reader extension должна сохранить:

* explicit exchange;
* timezone-aware `as_of`;
* UTC;
* closed-candle rule;
* Decimal;
* no future rows;
* max 100 symbols per call;
* read-only startup gate;
* source contract version;
* отдельные unit/integration tests.

### Paper DB

Чтение:

```text
market_universe
market_features
собственные levels tables
data_quality_incidents
service_heartbeats
```

Запись только в Levels-owned tables через narrow functions.

---

## 6. История и rebuild

Первичный rebuild:

```text
вся доступная качественная история
```

Нельзя ограничивать rebuild последними семью днями.

Старый уровень не удаляется только из-за возраста.

Полный rebuild разрешён:

```text
первый запуск
изменение builder_version
ручная команда
обнаруженное расхождение
```

Ежедневный full-history scan запрещён.

Для многолетней истории использовать:

* последовательные symbol batches;
* Reader batch ≤100;
* time pagination;
* durable rebuild checkpoints;
* bounded memory;
* resume после restart;
* immutable source checksum per chunk.

Рекомендуемый initial default:

```text
hourly_history_chunk_days: 90
rebuild_symbol_batch_size: 25
```

Это технические defaults, не бизнес-правила.

---

## 7. Модель run и безопасная публикация

Создать общую модель run:

```text
BUILDING
READY
FAILED
```

Run kinds:

```text
INITIAL_REBUILD
MANUAL_REBUILD
ALGORITHM_REBUILD
HOURLY_DISCOVERY
MINUTE_PROJECTION
DAILY_MAINTENANCE
```

Поля `level_runs`:

```text
run_id
exchange
run_kind
status
builder_version
configuration_version
quality_policy_version
input_start
input_cutoff
source_checksum
started_at
heartbeat_at
ready_at
failed_at
failure_class
failure_message
symbols_total
symbols_completed
levels_created
levels_updated
projection_rows
previous_ready_run_id
metadata
```

Требования:

* не более одного активного BUILDING run одного kind на exchange;
* Binance и Bybit имеют независимые locks;
* staging rows невидимы Detector;
* READY публикуется атомарно;
* при FAILED предыдущий READY остаётся доступным;
* retry того же run не создаёт duplicate definitions/events;
* новый builder version создаёт новый rebuild, не мутирует старую историю.

Для больших minute runs использовать staging:

```text
level_projection_stage
```

Порядок:

```text
BUILDING run
→ последовательные batch updates в staging
→ validation
→ одна publish transaction
→ READY pointer
```

Нельзя публиковать частичный набор после каждого batch.

---

## 8. Таблицы Levels

Создать:

```text
migrations/010_stage4_levels.sql
```

### 8.1. levels

Immutable определение зоны:

```text
level_id UUID
exchange
symbol
formation_type
zone_low
zone_high
center_price
zone_width_pct
formed_at
first_formation_at
last_formation_at
formation_volume_quote
baseline_volume_quote
formation_volume_multiple
formation_volume_class
post_formation_move_pct
builder_version
configuration_version
quality_policy_version
definition_checksum
source_timeframe
created_by_run_id
created_at
```

Constraints:

```text
zone_low > 0
zone_high >= zone_low
zone_low <= center_price <= zone_high
zone_width_pct >= 0
volume values >= 0 or NULL
```

Immutable trigger запрещает UPDATE/DELETE.

### 8.2. level_source_candles

Сохраняет все исходные свечи:

```text
level_id
source_identity
open_ts
close_ts
open
high
low
close
volume_base
volume_quote
role                     FORMATION | CONFIRMATION
ordinal
source_checksum
```

### 8.3. level_components

Lineage объединённых зон:

```text
parent_level_id
component_level_id
component_type
added_at
run_id
```

При merge нельзя терять первоначальные определения.

### 8.4. level_status_events

Append-only:

```text
level_id
from_status
to_status
event_at
run_id
reason
source_candle
idempotency_key
payload
```

Статусы:

```text
BUILDING
ACTIVE
BROKEN
RETESTED
INACTIVE
FAILED
```

### 8.5. level_touch_events

```text
touch_id
level_id
exchange
symbol
touch_at
touch_price
touch_direction
touch_volume_quote
touch_volume_multiple
source_candle
run_id
quality
idempotency_key
```

### 8.6. level_reaction_events

```text
reaction_id
touch_id
level_id
observation_started_at
observation_ended_at
reaction_direction
reaction_pct
reaction_class
reaction_volume_quote
reaction_volume_multiple
confirmed
failure_reason
run_id
idempotency_key
```

### 8.7. level_break_events

```text
break_id
level_id
broken_at
break_direction
confirmation_candles
break_volume_multiple
run_id
idempotency_key
```

### 8.8. level_retest_events

```text
retest_id
level_id
retest_at
approach_side
reaction_pct
confirmed
run_id
idempotency_key
```

### 8.9. level_metrics

Mutable projection, не источник истории:

```text
level_id
touch_count
confirmed_reaction_count
failed_reaction_count
break_count
retest_count
last_touched_at
last_confirmed_at
last_reaction_pct
max_reaction_pct
average_reaction_pct
significance_category
significance_reason_codes
freshness_at
freshness_category
updated_by_run_id
updated_at
```

### 8.10. level_projections

```text
exchange
symbol
level_id
current_price
distance_to_level_pct
price_position
interaction_state
updated_at
updated_by_run_id
source_candle
```

Хранить раздельно:

```text
price_position:
ABOVE_LEVEL
BELOW_LEVEL
INSIDE_LEVEL

interaction_state:
NEAR_LEVEL
TOUCHING_LEVEL
MOVED_AWAY
BROKEN_LEVEL
NONE
```

Это устраняет неоднозначность единого enum и сохраняет все утверждённые состояния.

### 8.11. levels_watermarks

Отдельно:

```text
LEVELS_REBUILD
LEVELS_HOURLY
LEVELS_MINUTE
LEVELS_DAILY
```

Binance и Bybit имеют независимые watermarks.

### 8.12. levels_processing_errors

Отдельные ошибки:

```text
exchange
symbol
run_id
run_kind
bucket
error_class
retryable
message
attempt_count
first_seen_at
last_seen_at
resolved_at
metadata
```

---

## 9. Ownership и роли

Добавить:

```text
paper_levels_binance_writer
paper_levels_bybit_writer
paper_levels_auditor
```

Биржевые роли должны быть технически ограничены своей биржей.

Реализация допустима через:

* отдельные `SECURITY DEFINER` функции с exchange check;
* отдельные views/functions;
* RLS, если оно доказано тестами и не усложняет migrations.

Ни одна Levels role не получает права на:

```text
paper_accounts
account_ledger
financial_transactions
signals
paper_trades
candidate_events
growth_episodes
```

Рекомендуемые functions:

```text
start_level_run(...)
stage_level_definition(...)
stage_level_projection(...)
publish_level_run_ready(...)
fail_level_run(...)
record_level_touch(...)
record_level_reaction(...)
record_level_break(...)
record_level_retest(...)
advance_levels_watermark(...)
```

---

## 10. Formation types

Поддержать:

```text
VOLUME_IMPULSE_LEVEL
VOLUME_CLUSTER_LEVEL
```

### 10.1. Volume baseline

Рекомендуемый default:

```text
timeframe: 1h
baseline candles: предыдущие 30 закрытых 1h свечей
baseline statistic: median
formation candle excluded
```

Причина:

* median устойчивее к редким volume spikes;
* 30 часов покрывают больше суток;
* окно достаточно локально для текущего режима.

Это versioned технический default, а не утверждённая бизнес-константа.

### 10.2. Volume classes

```text
multiple < 3      → level не создаётся
3 <= x < 5        → NORMAL
5 <= x < 10       → STRONG
x >= 10           → EXTREME
```

Границы должны быть однозначно покрыты тестами.

Хранить отдельно:

```text
formation_volume_quote
baseline_volume_quote
formation_volume_multiple
formation_volume_class
```

Нельзя заменять одним score.

---

## 11. VOLUME_IMPULSE_LEVEL

Рекомендуемый deterministic default:

```text
formation length: 1–3 последовательные закрытые 1h свечи
minimum volume multiple: 3
confirmation window: следующие 6 закрытых 1h свечей
minimum post-formation move: 3%
```

Алгоритм:

1. Найти отдельную аномальную свечу.
2. Допускается присоединить до двух следующих соседних свечей, если они продолжают импульс и имеют overlapping/adjacent price area.
3. Рассчитать общую formation volume.
4. Построить zone geometry только по formation candles.
5. Уровень публикуется только после закрытого confirmation window и доказанного движения.
6. `formed_at` — момент, когда подтверждение стало доступно.
7. Confirmation candles сохраняются отдельно от formation candles.
8. До `formed_at` уровень не существует и не может быть прочитан Detector.

Порог движения и длина окна должны находиться в versioned config и open issues.

---

## 12. VOLUME_CLUSTER_LEVEL

Рекомендуемый default:

```text
minimum candles: 2
maximum candles: 6
maximum gap between candles: 0
minimum aggregate volume multiple: 3
minimum price-area overlap: 50%
```

Алгоритм:

1. Найти соседние закрытые 1h свечи с повышенным объёмом.
2. Свечи должны концентрироваться в общей ценовой области.
3. Рассчитать пересечение или устойчивую общую область.
4. Построить единый volume-distribution proxy.
5. Сохранить каждую исходную свечу и её вклад.
6. Не объединять свечи через временной разрыв.
7. Не использовать будущие свечи.

Все параметры versioned.

---

## 13. Геометрия зоны

Физические источники содержат OHLCV, но не содержат настоящего volume-at-price внутри свечи. Поэтому нельзя заявлять, что точное внутрисвечное распределение известно.

Реализовать детерминированный proxy и явно назвать его proxy.

Рекомендуемый алгоритм `ZONE_GEOMETRY_V1`:

1. Для formation range создать 20 равных price bins.
2. Для каждой свечи распределить:

   * 70% её quote volume равномерно по candle body;
   * 30% равномерно по полному low-high range.
3. Для zero-range candle весь объём отнести в bin, содержащий close.
4. Суммировать volume каждого bin.
5. `center_price` = midpoint volume-weighted median bin.
6. Начиная с bin с максимальным объёмом, расширять область к соседнему bin с большим следующим объёмом.
7. Остановиться при достижении 70% cumulative formation volume.
8. Внешние границы выбранных bins становятся:

   ```text
   zone_low
   zone_high
   ```
9. Рассчитать:

   ```text
   zone_width_pct = (zone_high - zone_low) / center_price × 100
   ```
10. Сохранить параметры bins и алгоритм в versioned config.

Обязательно сравнить эту рекомендацию минимум с двумя альтернативами:

```text
полный candle range
body-only zone
ATR/percentage zone
```

В отчёте объяснить выбор.

Истинный volume profile не выдумывать.

---

## 14. Объединение зон

Merge разрешён только при:

```text
одинаковая биржа
одинаковая монета
zones пересекаются
или gap <= merge_gap_pct
нет отдельной значимой зоны между ними
```

Рекомендуемый default:

```text
merge_gap_pct = 0.25%
```

Детерминированный merge:

* новая геометрия рассчитывается повторно по всем source components;
* earliest formation сохраняется;
* latest formation сохраняется;
* total formation volume суммируется;
* maximum multiple сохраняется отдельно;
* все component IDs сохраняются;
* touch/reaction/break/retest history не переписывается;
* старые level definitions не удаляются;
* создаётся новый immutable parent level;
* старые компоненты могут перейти в INACTIVE с reason `MERGED_INTO`.

«Нет отдельной значимой зоны» означает, что между центрами merge-кандидатов отсутствует ACTIVE/RETESTED уровень категории NORMAL или выше.

---

## 15. Значимость

Хранить отдельно:

```text
formation_volume_class
formation_volume_multiple
post_formation_move_pct
confirmed_reaction_count
failed_reaction_count
max_reaction_pct
average_reaction_pct
break_count
retest_count
```

Категории:

```text
WEAK
NORMAL
STRONG
EXTREME
```

Рекомендуемые прозрачные правила:

### EXTREME

Хотя бы одно:

```text
formation class EXTREME и post move >= 10%
confirmed reactions >= 3 и max reaction >= 10%
confirmed retest с reaction >= 10%
```

### STRONG

Хотя бы одно:

```text
formation class STRONG/EXTREME и post move >= 5%
confirmed reactions >= 2 и max reaction >= 5%
confirmed retest с reaction >= 5%
```

### NORMAL

Хотя бы одно:

```text
formation class NORMAL и post move >= 3%
confirmed reactions >= 1
```

### WEAK

Все остальные валидные уровни.

Хранить `significance_reason_codes`.

Не вычислять скрытый weighted score.

Эти rules должны быть versioned и отмечены как provisional defaults.

---

## 16. Свежесть

Хранить:

```text
formed_at
last_confirmed_at
freshness_at = max(formed_at, last_confirmed_at)
```

Категории:

```text
HOT    <= 7 дней
FRESH  >7 и <=30 дней
AGED   >30 и <=90 дней
OLD    >90 дней
```

Простое касание не меняет `last_confirmed_at`.

Обновляют свежесть только:

```text
confirmed reaction
confirmed retest
```

Возраст не переводит уровень в INACTIVE.

---

## 17. Minute projection

После каждой закрытой минутной свечи пакетно:

1. Получить новые свечи всех ACTIVE symbols пакетами ≤100.
2. Соединить символы с ACTIVE/RETESTED levels в Paper DB.
3. Сначала выполнить дешёвый distance filter.
4. Подробно проверять только близкие зоны.
5. Записать staging projection.
6. После успешной обработки всех symbol batches атомарно опубликовать READY minute run.

Current price:

```text
close фактической последней закрытой 1m свечи
```

Distance:

* внутри зоны — `0`;
* выше — расстояние до `zone_high`;
* ниже — расстояние до `zone_low`.

Рекомендуемый default:

```text
near_level_pct = 1.0%
```

Параметр versioned и provisional.

Нельзя запускать отдельный процесс на каждую торговую пару.

---

## 18. Касание

Касание:

```text
candle_high >= zone_low
AND
candle_low <= zone_high
```

Touch direction определяется по предыдущему закрытому close:

```text
previous close > zone_high → FROM_ABOVE
previous close < zone_low  → FROM_BELOW
previous close inside      → FROM_INSIDE
```

Touch price при OHLC-only источнике:

```text
FROM_ABOVE → zone_high
FROM_BELOW → zone_low
FROM_INSIDE → clamp(current close, zone_low, zone_high)
```

Это deterministic proxy; точный tick path неизвестен.

Новое касание создаётся только после:

```text
предыдущего выхода из зоны
+
нового входа
```

Несколько минут внутри зоны — один touch episode.

Touch сам по себе не подтверждает уровень.

---

## 19. Реакция

После выхода из зоны отслеживать движение в направлении, противоположном подходу.

Thresholds:

```text
reaction < 3%       → failed/weak, уровень не подтверждается
3% <= x < 5%        → NORMAL_REACTION
5% <= x < 10%       → STRONG_REACTION
x >= 10%            → EXTREME_REACTION
```

Рекомендуемый observation default:

```text
reaction_observation_minutes = 720
```

Наблюдение заканчивается при первом из:

```text
достигнут threshold
повторное касание
подтверждённый пробой
истёк observation window
уровень стал INACTIVE
```

После confirmed reaction обновить:

```text
confirmed_reaction_count
last_confirmed_at
last_reaction_pct
max_reaction_pct
average_reaction_pct
freshness
significance
```

При отсутствии реакции:

```text
failed_reaction_count
failure_reason
```

---

## 20. Объём при касании и реакции

Хранить отдельно:

```text
touch_volume_quote
touch_volume_multiple
reaction_volume_quote
reaction_volume_multiple
```

Рекомендуемый baseline:

```text
median предыдущих 30 закрытых 1m свечей
```

Объём:

* не создаёт новый уровень;
* не меняет геометрию;
* не подтверждает уровень без движения цены.

---

## 21. Повторные касания

Хранить:

```text
touch_count
confirmed_reaction_count
failed_reaction_count
```

Интерпретацию не превращать в торговое решение:

```text
0 confirmed reactions → untested
1 → confirmed
2–3 → historically strong
4+ → frequently tested, potentially weakening
```

Количество касаний само по себе не удаляет и не усиливает уровень.

---

## 22. Пробой

Один wick не считается пробоем.

Рекомендуемый versioned default:

```text
2 последовательные закрытые 1m свечи
close за границей zone
break_buffer_pct = 0.20%
```

Для пробоя вверх:

```text
close >= zone_high × (1 + buffer)
```

Для пробоя вниз:

```text
close <= zone_low × (1 - buffer)
```

Сохранить:

```text
status = BROKEN
broken_at
break_direction
confirmation candles
break_volume_multiple
break_count
```

Пробитый уровень не удалять.

Параметры должны быть конфигурационными.

---

## 23. Ретест

После BROKEN:

1. Цена должна сначала находиться на противоположной стороне.
2. Затем закрытая свеча возвращается к зоне.
3. Фиксируется retest touch.
4. Применяется тот же reaction observation.
5. Только confirmed reaction переводит уровень в:

   ```text
   RETESTED
   ```
6. Confirmed retest обновляет:

   ```text
   last_confirmed_at
   freshness
   significance metrics
   ```

---

## 24. ALL / RELEVANT / PRIORITY

Реализовать как прозрачные SQL views или repository queries.

### ALL

Все immutable definitions и их полная история.

### RELEVANT

Уровни, удовлетворяющие хотя бы одному:

```text
significance NORMAL/STRONG/EXTREME
confirmed_reaction_count > 0
status RETESTED
```

### PRIORITY

Динамический filter:

```text
status ACTIVE или RETESTED
distance <= near_level_pct
freshness HOT/FRESH
significance NORMAL/STRONG/EXTREME
```

Старый EXTREME уровень может оставаться PRIORITY при отдельном documented rule.

Запрещено оставлять фиксированное количество:

```text
5
10
20
```

Ranking должен быть детерминированным:

```text
1. distance ascending
2. freshness priority
3. significance priority
4. last_confirmed_at descending
5. level_id
```

---

## 25. Hourly и daily jobs

### Каждый закрытый час

```text
искать новые impulse levels
искать новые cluster levels
проверять formation confirmations
обновлять зоны через immutable new definitions
выполнять допустимый merge
```

### Раз в сутки

```text
пересчитать freshness categories
пересчитать significance categories
проверить duplicate definitions
проверить stale BUILDING runs
проверить status consistency
проверить READY pointers
проверить watermarks
```

Daily job не перечитывает многолетнюю историю без причины.

---

## 26. Error handling и recovery

Ошибка одного symbol:

* записывается в `levels_processing_errors`;
* остальные symbols продолжают staging;
* run не публикуется READY, пока не обработаны все обязательные symbols;
* предыдущий READY остаётся;
* retry переиспользует run identity или создаёт documented retry attempt;
* uniqueness не допускает дублей.

Crash во время BUILDING:

* lease имеет expiry;
* другой worker может восстановить run после lease timeout;
* staging rows идентифицируются run_id;
* частичный staging не виден readers;
* watermark не продвигается.

Crash во время publish transaction:

```text
либо весь READY commit
либо полный rollback
```

---

## 27. Health и heartbeat

Отдельные heartbeat identities:

```text
paper-levels-binance
paper-levels-bybit
```

Heartbeat metadata:

```text
exchange
builder_version
config_version
active_run_id
run_kind
run_status
last_ready_run_id
last_minute_watermark
last_hourly_watermark
last_daily_run
symbols_total
symbols_completed
active_levels
near_levels
open_touch_observations
error_count
source_contract_status
```

Statuses:

```text
STARTING
HEALTHY
DEGRADED
STOPPED
```

Нельзя показывать HEALTHY при:

* недоказанном candle source contract;
* stale watermark;
* зависшем BUILDING run;
* отсутствующем предыдущем READY после завершённого bootstrap;
* failed publication.

---

## 28. Конфигурация

Создать:

```text
configs/services/stage4-levels-v1.yaml
configs/services/stage4-levels-v1.yaml.example
```

Versioned параметры:

```text
builder_version
configuration_version
source_timeframe
volume_baseline_candles
volume_baseline_statistic
impulse_min_candles
impulse_max_candles
impulse_confirmation_candles
impulse_confirmation_move_pct
cluster_min_candles
cluster_max_candles
cluster_overlap_pct
geometry_bin_count
geometry_body_volume_share
geometry_value_area_pct
merge_gap_pct
near_level_pct
touch_volume_baseline_candles
reaction_observation_minutes
break_confirmation_candles
break_buffer_pct
rebuild_symbol_batch_size
hourly_symbol_batch_size
minute_symbol_batch_size
history_chunk_days
run_lease_seconds
safe_overlap
heartbeat_interval
```

Config validation должна fail-closed при:

```text
неизвестной версии
отсутствующем параметре
невалидном диапазоне
float вместо Decimal-compatible string
```

---

## 29. Структура кода

Минимально:

```text
src/paper_engine/domain/levels/
    models.py
    enums.py
    policies.py

src/paper_engine/market_data/levels/
    formation.py
    volume_baseline.py
    geometry.py
    merge.py
    significance.py
    freshness.py
    projection.py
    touch.py
    reaction.py
    break_retest.py
    repository.py
    runs.py
    worker.py

src/paper_engine/runtime/stage4_levels.py

scripts/stage4_levels_rebuild.py
scripts/stage4_levels_smoke.py
```

Не импортировать Scanner/Growth implementation.

---

## 30. Docker Compose

Дополнить:

```text
docker-compose.stage4.yml
```

Итоговые Stage 4 application services — ровно:

```text
paper-scanner-binance
paper-scanner-bybit
paper-levels-binance
paper-levels-bybit
```

Levels:

```text
SERVICE_MODE=levels
EXCHANGE=BINANCE/BYBIT
```

Не создавать:

```text
paper-growth-*
paper-level-worker-per-symbol
paper-level-detector
```

Stage 4 compose предназначен для development/integration smoke. Production deployment остаётся отдельным разрешением.

---

## 31. Обязательные тесты

### Unit — formation

* Decimal-only;
* UTC/as_of;
* future candle exclusion;
* unclosed hourly candle exclusion;
* mean/median baseline;
* exact volume class boundaries;
* impulse 1/2/3 candles;
* cluster min/max;
* cluster overlap;
* formation confirmation;
* no future confirmation;
* no level при multiple <3;
* true latest close, не `MAX(close)`.

### Unit — geometry

* 20 bins;
* body/wick shares;
* doji/zero range;
* volume-weighted median;
* 70% value area;
* deterministic tie-break;
* zone constraints;
* checksum stability.

### Unit — merge

* intersection;
* merge gap;
* separate significant zone prevents merge;
* exchange/symbol isolation;
* lineage preservation;
* no source loss.

### Unit — lifecycle

* freshness boundaries 7/30/90 days;
* touch intersection;
* repeated inside candles = one touch;
* exit and re-entry = new touch;
* reaction 3/5/10 boundaries;
* failed reaction;
* wick is not break;
* two closes confirm break;
* retest;
* significance reason codes;
* no opaque score.

### Integration PostgreSQL

* migration clean/rerun;
* roles and permissions;
* immutable definitions;
* append-only events;
* one BUILDING run per exchange/kind;
* READY atomicity;
* FAILED keeps previous READY;
* staging invisibility;
* Binance/Bybit role isolation;
* concurrent publishers;
* publish rollback;
* watermark atomicity;
* restart recovery;
* merge lineage.

### Rebuild

* multi-chunk historical rebuild;
* crash between chunks;
* resume;
* no duplicate definitions;
* builder version change;
* old READY retained until new READY.

### Minute load

Synthetic minimum:

```text
1100 symbols
несколько levels на symbol
batch requests <=100 symbols
distance prefilter
только близкие levels проходят detailed processing
bounded query count
bounded memory
```

### Docker smoke

* четыре Stage 4 containers;
* обе биржи изолированы;
* initial READY на fixture;
* minute projection READY;
* touch/reaction;
* failed rebuild сохраняет previous READY;
* restart Levels container;
* heartbeat recovery;
* отсутствуют Detector/Signal/trade writes.

---

## 32. Команды проверки

```bash
python -m pytest tests/unit -q
python -m pytest tests/integration -q
python -m pytest tests/restart -q
python -m pytest tests/concurrency -q
python -m pytest tests/load -q
python -m pytest tests/acceptance -q

ruff check .
ruff format --check .
mypy src
python -m compileall src scripts

python scripts/migrate.py
python scripts/migrate.py

git diff --check
git status --short
git diff --stat
git diff --name-only
```

Docker:

```bash
docker compose -f docker-compose.stage4.yml config
docker compose -f docker-compose.stage4.yml build
docker compose -f docker-compose.stage4.yml up -d
docker compose -f docker-compose.stage4.yml ps
docker compose -f docker-compose.stage4.yml logs --no-color

docker compose -f docker-compose.stage4.yml restart paper-levels-binance
docker compose -f docker-compose.stage4.yml restart paper-levels-bybit

docker compose -f docker-compose.stage4.yml down
```

SQL evidence должно показать:

```text
READY pointer
предыдущий READY
failed run
immutable level
touch history
reaction history
break/retest history
ALL/RELEVANT/PRIORITY
отдельные Binance/Bybit watermarks
least-privilege grants
```

---

## 33. Обязательные evidence

Сохранить:

* Git preflight;
* migration logs;
* schema/constraint dump;
* role grants;
* unit test summary;
* integration test summary;
* restart logs;
* concurrency logs;
* rebuild evidence;
* minute load metrics;
* Docker service list;
* Docker health;
* before/after READY demonstration;
* failed-run demonstration;
* source-contract status;
* monitor-data before/after Git evidence;
* secret scan;
* `git diff --check`;
* final file list.

Не ссылаться только на `/tmp` файл без включения существенных результатов в Stage evidence Markdown.

---

## 34. Документация

Создать или обновить:

```text
docs/architecture/LEVELS_CONTRACT.md
docs/architecture/DATABASE_CONTRACT.md
docs/architecture/DATA_FLOW.md
docs/architecture/SERVICE_BOUNDARIES.md
docs/architecture/STATE_MACHINES.md
docs/architecture/TEST_STRATEGY.md

docs/stages/STAGE_04_REPORT.md
docs/stages/STAGE_04_EVIDENCE.md
docs/stages/STAGE_04_OPEN_ISSUES.md

README.md
CURRENT_STATE.md
TODO.md
HANDOFF.md
DECISIONS.md
docs/MASTER_IMPLEMENTATION_PLAN.md
docs/PROJECT_MASTER_CHECKLIST.md
```

Обязательно синхронизировать карту контейнеров:

```text
без paper-growth-binance
без paper-growth-bybit
ровно четыре Stage 4 application containers
```

---

## 35. Open technical parameters

Следующие defaults не выдавать за окончательную бизнес-логику:

```text
hourly source method
volume baseline = median 30
impulse length = 1–3
confirmation = 6h / 3%
cluster length = 2–6
cluster overlap = 50%
geometry = 20 bins / 70% body / 70% value area
merge gap = 0.25%
near distance = 1.0%
reaction observation = 720 minutes
break confirmation = 2 candles
break buffer = 0.20%
rebuild batch sizes
history chunk size
```

Для каждого параметра в `STAGE_04_OPEN_ISSUES.md` указать:

```text
default
почему выбран
какие альтернативы рассматривались
какие тесты его фиксируют
какие исторические проверки ещё нужны
что произойдёт при изменении версии
```

---

## 36. Критерии приёмки ТЗ №2

ТЗ №2 выполнено, если:

1. Есть два Levels-контейнера и нет per-symbol процессов.
2. Binance и Bybit полностью изолированы.
3. Базовая зона строится только по цене и объёму.
4. Уровень хранится зоной, не одной ценой.
5. Formation definitions immutable.
6. Source candles и lineage не теряются.
7. Geometry детерминирована и versioned.
8. Истинный intrabar volume profile не выдумывается.
9. Поддерживаются impulse и cluster.
10. Полная история обрабатывается chunked rebuild.
11. Daily job не перечитывает всю историю.
12. Touch не дублируется каждую минуту внутри зоны.
13. Reaction подтверждается только движением цены.
14. Wick не считается break.
15. Broken level не удаляется.
16. Retest сохраняется отдельно.
17. Significance прозрачна и без opaque score.
18. Freshness обновляется только confirmed reaction/retest.
19. ALL/RELEVANT/PRIORITY не имеют фиксированного количества.
20. Каждый run имеет BUILDING/READY/FAILED.
21. Failed run сохраняет previous READY.
22. Watermarks и locks отдельны по биржам.
23. Restart/replay не создаёт дублей.
24. Reader request не превышает 100 symbols.
25. Market DB read-only.
26. monitor-data не изменён.
27. Нет секретов.
28. Нет Detector/Signal/trading реализации.

---

## 37. Итоговый Git

После успешного выполнения обоих ТЗ:

```bash
git status --short
git diff --check
git diff --stat
git diff --name-only
```

Добавить только ожидаемые файлы явным списком.

Запрещено:

```text
git add .
git add -A
```

Создать один итоговый commit Stage 4:

```text
feat(stage4): implement scanner growth and levels
```

После commit:

```bash
git rev-parse HEAD
git status --short
git log -3 --oneline
```

Не создавать PR и не выполнять merge.

---

## 38. Итоговый отчёт агента

```text
STAGE 4 — FINAL REPORT

1. Base SHA.
2. Final SHA.
3. Branch.
4. Changed files.
5. Final container map.
6. Scanner architecture.
7. Growth architecture.
8. Levels architecture.
9. Migrations.
10. Ownership and DB roles.
11. Candidate events.
12. Growth episodes.
13. Level definitions.
14. Level runs and READY publication.
15. Touch/reaction/break/retest.
16. Watermarks and locks.
17. Restart/replay.
18. Unit tests.
19. Integration tests.
20. Concurrency tests.
21. Load tests.
22. Docker smoke.
23. Market source audit.
24. Production source blockers.
25. monitor-data proof.
26. Secret scan.
27. What is proven.
28. What is not proven.
29. Provisional parameters.
30. Open issues.
31. git diff/status.
32. Recommendation for independent audit.
```

---

## 39. Условие остановки

После итогового Stage 4 commit:

* остановиться;
* не создавать PR;
* не выполнять merge;
* не менять `main`;
* не запускать production deployment;
* не начинать Stage 5;
* не реализовывать Detector;
* не реализовывать Signal;
* не реализовывать Paper Entry;
* не изменять Accounts или Ledger;
* не создавать Dashboard;
* передать Final SHA, evidence и open issues куратору.
