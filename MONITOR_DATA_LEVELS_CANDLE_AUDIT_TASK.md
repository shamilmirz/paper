# ТЗ ДЛЯ MONITOR-DATA — АУДИТ СВЕЧЕЙ ДЛЯ STAGE 4B LEVELS

## 1. Цель

Провести строго read-only аудит реальных свечей Binance и Bybit в `monitor-data` и определить безопасный источник для Levels Builder проекта `paper-trading-engine`.

Нужно дать однозначный итог по каждой бирже:

```text
APPROVED_DIRECT_1H
APPROVED_AGGREGATE_FROM_1M
BLOCKED
```

Аудит не должен изменять код, таблицы, роли, контейнеры, Compose, scheduler или данные `monitor-data`.

---

## 2. Что требуется Levels Builder

Базовые price-volume зоны будут строиться только из закрытых часовых свечей.

Минутные свечи будут использоваться только после создания уровня для:

```text
current price
distance to level
touch
reaction
break
retest
freshness/significance evidence
```

Поэтому аудит должен отдельно доказать контракты `candles_1h` и `candles_1m`.

---

## 3. Git и безопасность

Перед аудитом зафиксировать:

```bash
git branch --show-current
git rev-parse HEAD
git status --short
git log -5 --oneline
```

Также зафиксировать список и состояние контейнеров без перезапуска:

```bash
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
```

Запрещено:

```text
DDL
DML
VACUUM FULL
REINDEX
ANALYZE вручную
изменение grants/roles
перезапуск контейнеров
изменение collector code
создание индексов
изменение Timescale policies
```

Разрешены только безопасные `SELECT`, чтение кода и `EXPLAIN` без `ANALYZE`, если реальный запрос может быть тяжёлым.

---

## 4. Аудит physical schema

Для `public.candles_1m` и `public.candles_1h` вернуть:

```text
тип объекта: table/view/materialized view/continuous aggregate
полный список колонок и типов
nullable
primary/unique keys
indexes
hypertable/continuous aggregate metadata
compression/retention policies
owner и SELECT grants
```

Отдельно указать точные физические поля:

```text
timestamp/bucket
exchange
symbol
open
high
low
close
volume
turnover или quote volume
```

Проверить, существуют ли:

```text
ingested_at
updated_at
source_updated_at
is_closed
confirm
source event id
```

---

## 5. Семантика timestamp и закрытия свечи

Для Binance и Bybit отдельно доказать по collector code и реальным данным:

1. Что означает timestamp в `candles_1m.ts`:
   - open time;
   - close time;
   - другое.
2. Что означает `candles_1h.bucket`.
3. UTC ли это значение.
4. Как определяется закрытая свеча.
5. Может ли незакрытая текущая свеча попасть в таблицу.
6. Отличаются ли WebSocket и REST/backfill пути.
7. Может ли backfill записать незакрытую свечу.
8. Может ли уже сохранённая свеча обновляться задним числом.
9. Какой ключ используется при UPSERT.
10. Есть ли разница между Binance и Bybit.

Привести точные пути файлов, функции и короткие фрагменты логики collector code. Не ограничиваться пересказом.

---

## 6. Семантика OHLCV

Для каждой биржи и каждого timeframe доказать:

```text
open/high/low/close units
volume = base volume или другое
turnover = quote volume или другое
есть ли контрактные множители
есть ли inverse instruments
включены ли только USDT perpetual
```

Проверить базовые инварианты:

```text
open > 0
high >= max(open, close)
low <= min(open, close)
high >= low
volume >= 0
turnover >= 0
```

Вернуть количество нарушений отдельно для Binance/Bybit и 1m/1h.

---

## 7. Покрытие истории

Для Binance и Bybit отдельно вернуть по `candles_1m` и `candles_1h`:

```text
минимальный timestamp
максимальный timestamp
общее число строк
число уникальных symbols
число symbols с историей >= 30 дней
число symbols с историей >= 90 дней
число symbols с историей >= 365 дней
```

Также вернуть минимум/медиану/p95/max длины истории по символам.

Не выгружать все строки; вернуть агрегаты и небольшие выборки.

---

## 8. Дубли, пропуски и свежесть

Для каждой биржи отдельно проверить:

### Дубли

```text
(exchange, symbol, ts) для 1m
(exchange, symbol, bucket) для 1h
```

Вернуть количество duplicate groups и duplicate rows.

### Пропуски

На репрезентативной выборке минимум 20 активных symbols каждой биржи за последние 30 дней вернуть:

```text
число ожидаемых интервалов
число фактических интервалов
число gap episodes
максимальный gap
процент полноты
```

Отдельно для 1m и 1h.

### Свежесть

Вернуть распределение задержки последней свечи:

```text
min
median
p95
max
```

Измерить относительно текущего UTC-времени с учётом полного закрытого интервала.

---

## 9. Сравнение candles_1h с агрегацией candles_1m

Это обязательная часть.

Для минимум 20 symbols каждой биржи и последних 30 полных дней агрегировать закрытые `candles_1m` в UTC-час:

```text
open  = первая минутная open
high  = max(high)
low   = min(low)
close = последняя минутная close
volume = sum(volume)
turnover = sum(turnover)
```

Сравнить с `candles_1h` по каждому часу.

Вернуть:

```text
совпавшие часы
отсутствующие часы только в 1m
отсутствующие часы только в 1h
OHLC mismatches
volume mismatches
turnover mismatches
максимальное абсолютное и относительное расхождение
```

Допуск не придумывать. Сначала показать точные расхождения и объяснить их источник.

Проверить правильность границы UTC-часа и отсутствие смешения open-time/close-time buckets.

---

## 10. Late arrival и corrections

Так как в текущем schema могут отсутствовать ingestion timestamps, провести доступную проверку:

```text
есть ли UPDATE/UPSERT существующих candles
какие collector paths могут переписать историю
есть ли журнал или лог corrections
может ли REST backfill изменить WebSocket row
может ли одна и та же candle прийти с другим OHLCV
```

Если точную историю изменений доказать невозможно, явно написать `NOT PROVEN`.

---

## 11. Индексы и безопасная нагрузка

Показать существующие планы для запросов, необходимых Levels Builder:

```text
1. Последняя закрытая 1m candle для batches до 100 symbols.
2. Диапазон 1m candles по exchange + symbols + time range.
3. Диапазон 1h candles по exchange + symbols + time range.
4. Историческая pagination по времени.
```

Использовать `EXPLAIN` и безопасные ограниченные запросы. Не запускать тяжёлый `EXPLAIN ANALYZE` без отдельного разрешения.

Вернуть:

```text
используемые indexes/chunks
ожидаемые sequential scans
примерное число rows
риски N+1
рекомендуемый безопасный batch size
рекомендуемый history chunk size
```

Не создавать индексы — только описать необходимые изменения как рекомендацию.

---

## 12. Read-only доступ

Проверить роль, которую будет использовать `paper-trading-engine`:

```text
default_transaction_read_only
SELECT grants
отсутствие INSERT/UPDATE/DELETE/DDL
доступ к candles_1m
доступ к candles_1h
```

Секреты, DSN и пароли в отчёт не помещать.

---

## 13. Итоговое решение

Для каждой биржи вернуть одно решение.

### `APPROVED_DIRECT_1H`

Разрешено только если доказано:

```text
единая timestamp semantics
только закрытые 1h candles
правильная UTC bucket alignment
понятная OHLCV semantics
приемлемые gaps/duplicates
candles_1h согласуется с candles_1m
read-only и query plan безопасны
```

### `APPROVED_AGGREGATE_FROM_1M`

Использовать, если `candles_1m` доказана, но `candles_1h` не доказана или расходится. Указать точное правило агрегации и ingestion grace.

### `BLOCKED`

Использовать, если не доказана даже безопасная закрытая `candles_1m`, timestamp semantics неоднозначна или качество данных не позволяет исключить look-ahead.

Можно дать разное решение для Binance и Bybit.

---

## 14. Формат итогового отчёта

```text
MONITOR-DATA CANDLE AUDIT FOR STAGE 4B

1. Audit timestamp UTC.
2. monitor-data branch and SHA.
3. Git/worktree status.
4. Container status without restart.
5. Physical schema 1m/1h.
6. Binance timestamp contract.
7. Bybit timestamp contract.
8. Binance OHLCV contract.
9. Bybit OHLCV contract.
10. History coverage.
11. Duplicates.
12. Gaps and completeness.
13. Freshness/lag.
14. 1h versus aggregated 1m comparison.
15. Late-arrival/correction behavior.
16. Indexes and query plans.
17. Read-only role proof.
18. Binance verdict.
19. Bybit verdict.
20. Exact unresolved facts.
21. Recommended Reader method.
22. Recommended ingestion grace.
23. Recommended batch/chunk sizes.
24. Confirmation that monitor-data was not modified.
```

Приложить используемые SQL-запросы и существенные агрегированные результаты. Не ограничиваться утверждением `PASS` без цифр и доказательств.

После отчёта остановиться. Ничего не исправлять и не внедрять.