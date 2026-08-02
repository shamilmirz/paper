# STAGE 4B — LEVELS BUILDER IMPLEMENTATION PLAN

## Назначение

Этот файл — рабочий план реализации `Stage 4B Levels Builder` в репозитории:

```text
shamilmirz/paper-trading-engine
```

Основа требований:

```text
shamilmirz/paper/STAGE4tz2.md
```

План не заменяет полное ТЗ. Он задаёт порядок разработки, промежуточные контрольные точки и критерии остановки.

---

# 1. Актуализированный старт

На момент создания плана:

```text
Stage 4A Scanner/Growth уже слит в main
main SHA: 41547df810918dad7eb7d1dffe49f1ac26a2013a
существующая последняя миграция: 010_stage4_growth_catchup.sql
```

Поэтому устаревшие значения из первоначального ТЗ заменить:

```text
ветка: stage/04b-levels
base: актуальный origin/main на момент начала работы
новая миграция: 011_stage4_levels.sql
```

Перед началом кода повторно проверить:

```bash
git fetch origin
git branch --show-current
git rev-parse HEAD
git rev-parse origin/main
git status --short
git log -5 --oneline
```

Создать ветку только от актуального чистого `origin/main`.

---

# 2. Неподвижные границы этапа

Реализуются только:

```text
Levels database model
Levels Reader extension
historical rebuild
hourly formation
minute projection
level lifecycle
READY/FAILED publication
restart/replay recovery
Binance/Bybit Levels containers
тесты и evidence
```

Запрещено реализовывать:

```text
Detector
Signal
Paper Entry
Trade
Account/Reservation/Ledger changes
Dashboard
production deployment
изменения monitor-data
```

Базовый уровень формируется только по:

```text
price + volume
```

OI, funding и liquidations не влияют на создание и геометрию зоны.

---

# 3. Порядок реализации

## Блок A — аудит и контракты

1. Прочитать обязательные документы проекта и результаты Stage 4A.
2. Проверить текущий Market Data Reader, Paper DB, runtime и Compose.
3. Проверить физический источник часовых свечей.
4. Зафиксировать решение:

```text
A. доказанный candles_1h через canonical Reader
или
B. агрегация закрытых canonical candles_1m в 1h внутри Paper Engine
```

5. Обновить архитектурные контракты до написания основной логики.

Контрольная точка A:

```text
понятен источник 1h свечей
нет raw SQL внутри Levels modules
нет future/unclosed candles
есть точные границы Levels ownership
```

---

## Блок B — миграция, роли и безопасная публикация

Создать:

```text
migrations/011_stage4_levels.sql
```

Минимальные сущности:

```text
level_runs
levels
level_source_candles
level_components
level_status_events
level_touch_events
level_reaction_events
level_break_events
level_retest_events
level_metrics
level_projections
level_projection_stage
levels_watermarks
levels_processing_errors
rebuild checkpoints
READY pointers
```

Добавить отдельные роли:

```text
paper_levels_binance_writer
paper_levels_bybit_writer
paper_levels_auditor
```

Обязательные свойства:

```text
immutable level definitions
append-only evidence/events
один BUILDING run каждого kind на exchange
Binance/Bybit write isolation
staging невидим до READY
FAILED не удаляет previous READY
publish выполняется одной транзакцией
```

Контрольная точка B:

```text
миграция проходит с чистой базы и повторно
роли не могут писать finance/scanner/growth/trading tables
частичная публикация технически невозможна
```

---

## Блок C — доменная модель и конфигурация

Создать versioned config:

```text
configs/services/stage4-levels-v1.yaml
configs/services/stage4-levels-v1.yaml.example
```

Создать доменные типы:

```text
run kinds/statuses
formation types
volume classes
level statuses
freshness/significance
price position
interaction state
source identities/checksums
```

Все цены, объёмы, проценты и пороги:

```text
Decimal only
```

Config должен fail-closed при неизвестной версии, пропущенном параметре, неверном диапазоне или float.

Контрольная точка C:

```text
вся логика получает параметры из versioned config
нет скрытых magic numbers
нет float
```

---

## Блок D — построение уровней

Реализовать по отдельности:

```text
volume baseline
VOLUME_IMPULSE_LEVEL
VOLUME_CLUSTER_LEVEL
ZONE_GEOMETRY_V1
merge с сохранением lineage
checksums и deterministic identities
```

Правила:

```text
только закрытые свечи
formation candle исключена из baseline
confirmation не использует будущее
уровень существует только после formed_at
истинный intrabar volume profile не выдумывается
source candles сохраняются полностью
merge создаёт новый immutable parent
```

Сначала unit-тесты на маленьких искусственных наборах, затем repository publication.

Контрольная точка D:

```text
для известных свечей заранее известны ожидаемые zone_low/zone_high
повторный расчёт даёт тот же checksum
replay не создаёт дубли
```

---

## Блок E — исторический rebuild

Первый запуск обрабатывает всю доступную качественную историю:

```text
symbols последовательно
symbol batch <= 100
рекомендуемый рабочий batch 25
временные chunks, начальный default 90 дней
bounded memory
checkpoint после каждого подтверждённого chunk
resume после crash/restart
```

Полный rebuild запускается только:

```text
первый запуск
новая builder_version
ручная команда
обнаруженное расхождение
```

Ежедневный full-history scan запрещён.

Контрольная точка E:

```text
crash между chunks не теряет прогресс
resume не создаёт duplicate levels
old READY доступен до полной публикации нового READY
```

---

## Блок F — minute lifecycle

После каждой закрытой 1m свечи пакетно реализовать:

```text
current projection
distance prefilter
touch episode
reaction observation
confirmed/failed reaction
break confirmation
retest confirmation
metrics projection
freshness/significance recalculation
```

Ключевые ограничения:

```text
несколько свечей внутри зоны = одно касание
одно касание не подтверждает уровень
wick не является пробоем
пробой подтверждают закрытия по versioned rule
BROKEN уровень не удаляется
RETESTED только после подтверждённой реакции
history append-only
```

Контрольная точка F:

```text
каждое событие воспроизводимо из source candles
replay не дублирует touch/reaction/break/retest
projection можно полностью восстановить из immutable history
```

---

## Блок G — hourly, minute и daily runs

Реализовать независимые потоки:

```text
INITIAL/MANUAL/ALGORITHM_REBUILD
HOURLY_DISCOVERY
MINUTE_PROJECTION
DAILY_MAINTENANCE
```

Каждый run:

```text
BUILDING
→ staging и validation
→ одна publish transaction
→ READY
```

При ошибке:

```text
BUILDING → FAILED
previous READY остаётся рабочим
watermark не продвигается
```

Hourly:

```text
новые impulse/cluster
formation confirmations
immutable merge/new definitions
```

Minute:

```text
projection и lifecycle близких уровней
```

Daily:

```text
freshness/significance
consistency
stale BUILDING
READY pointers
watermarks
duplicates
```

Контрольная точка G:

```text
частичный batch никогда не виден читателю
ошибка одного symbol записана и не маскируется
run не становится READY при неполном обязательном наборе
```

---

## Блок H — runtime и Docker

Добавить два физических сервиса:

```text
paper-levels-binance
paper-levels-bybit
```

Допускается:

```text
один image
SERVICE_MODE=levels
разный EXCHANGE
```

У каждого сервиса отдельно:

```text
DB writer role
run locks
watermarks
heartbeat
processing errors
restart state
```

Итоговая Stage 4 карта application containers:

```text
paper-scanner-binance
paper-scanner-bybit
paper-levels-binance
paper-levels-bybit
```

Не создавать `paper-growth-*` и worker на каждую монету.

Контрольная точка H:

```text
падение Binance Levels не останавливает Bybit Levels
restart продолжает BUILDING/rebuild безопасно
HEALTHY невозможен при stale watermark, failed publication или недоказанном source contract
```

---

# 4. Тестирование по слоям

## Слой 1 — Unit

Проверить:

```text
formation
geometry
merge
freshness/significance
touch/reaction
break/retest
Decimal/UTC/no-future
checksum stability
```

## Слой 2 — PostgreSQL integration

Проверить:

```text
migration rerun
permissions
immutability
append-only history
READY atomicity
FAILED keeps previous READY
role/exchange isolation
concurrent publication
rollback
watermark atomicity
```

## Слой 3 — Restart/rebuild/replay

Проверить:

```text
crash between chunks
resume
crash during BUILDING
crash during publish
no duplicates
new builder version
```

## Слой 4 — Load

Минимальная синтетическая проверка:

```text
1100 symbols
несколько levels на symbol
Reader request <= 100 symbols
сначала distance prefilter
bounded query count
bounded memory
```

## Слой 5 — Docker acceptance

Доказать:

```text
ровно четыре Stage 4 application containers
initial READY обеих бирж
minute READY
touch/reaction lifecycle
failed rebuild сохраняет previous READY
restart и heartbeat recovery
нет Detector/Signal/Trade writes
```

## Слой 6 — реальная Market DB

После прохождения disposable acceptance агент с доступом к серверу выполняет read-only проверку:

```text
source schema/closed candle semantics
реальный historical rebuild на ограниченной выборке
реальные Binance/Bybit зоны
нагрузка и query plans
визуальная сверка source candles → zone
доказательство, что monitor-data не изменён
```

Эта проверка не разрешает production deployment.

---

# 5. Порядок коммитов

Рекомендуемый порядок небольших проверяемых коммитов:

```text
1. docs(stage4b): refresh levels contracts and boundaries
2. feat(stage4b): add levels schema roles and run publication
3. feat(stage4b): add canonical hourly reader support
4. feat(stage4b): implement level formation geometry and merge
5. feat(stage4b): implement rebuild checkpoints and publication
6. feat(stage4b): implement projection and level lifecycle
7. feat(stage4b): add levels runtime containers and configuration
8. test(stage4b): add integration restart load and acceptance evidence
9. docs(stage4b): close levels implementation report
```

Не использовать:

```text
git add .
git add -A
```

PR и merge выполнять только после независимого аудита и разрешения владельца.

---

# 6. Финальный критерий PASS

Stage 4B можно передавать на аудит, только если одновременно доказано:

```text
две биржи изолированы
уровень является зоной, а не одной ценой
price-volume formation детерминирована
source candles и lineage сохранены
нет future data
полная история обрабатывается chunked rebuild
READY публикуется только целиком
FAILED сохраняет previous READY
restart/replay не создаёт дублей
touch/reaction/break/retest имеют immutable evidence
Reader batches не превышают 100 symbols
Market DB остаётся read-only
monitor-data не изменён
нет секретов
нет кода следующих этапов
```

---

# 7. Условие остановки

После готовности к независимому аудиту:

```text
остановиться
не выполнять merge
не запускать production deployment
не начинать Stage 5
не писать Detector/Signal/Trading Core
передать Final SHA, diff, тесты, evidence и open issues
```
