# ТЗ ДЛЯ MONITOR-DATA — КАНОНИЧЕСКИЕ СВЕЧИ ДЛЯ PAPER TRADING ENGINE

## 1. Цель

Создать в `monitor-data` надёжный канонический источник закрытых минутных свечей Binance и Bybit для всего `paper-trading-engine`:

```text
Scanner
Growth
Levels Builder
Detectors
Paper Entry
Trade Managers
replay и аналитика
```

Одна биржа + одна монета + один интервал + начало интервала должны соответствовать ровно одной окончательной свече.

Итоговый контракт:

```text
exchange + symbol + interval + open_ts
```

Все даты — UTC. Все свечи — только закрытые.

---

## 2. Исходные факты аудита

Read-only аудит от `2026-08-02` установил:

### Binance

- WebSocket сохраняет только `x=true`, но пишет `k['T']` — время закрытия;
- REST пишет `k[0]` — время открытия;
- REST не доказывает, что свеча закрыта;
- в одной календарной минуте встречаются записи с open-time и close-time;
- уникального candle key нет.

### Bybit

- `confirm` не используется как обязательный фильтр;
- промежуточные обновления одной свечи сохраняются как отдельные строки;
- timestamp записи не доказан как начало candle interval;
- уникального candle key нет.

### `candles_1h`

- является continuous aggregate поверх текущей `candles_1m`;
- наследует семантические дубли и смешанные timestamps;
- не содержит `turnover`;
- не разрешена как источник Levels.

Текущий итог по обеим биржам:

```text
BLOCKED
```

---

## 3. Главное архитектурное решение

Не исправлять историческую таблицу опасным UPDATE/DELETE на месте.

Создать рядом новый канонический candle contract и переключать потребителей только после доказательства.

Рекомендуемое имя физической таблицы:

```text
candles_1m_canonical
```

Допускается другое имя, но оно должно быть явно versioned и не путаться с legacy `candles_1m`.

Legacy-таблицу:

```text
не удалять
не переписывать
не переименовывать
не использовать как доказанный источник после переключения
```

---

## 4. Безопасность Git и текущий dirty worktree

На аудите `monitor-data/main` был dirty. Изменены:

```text
collector/main.py
collector_binance/main.py
collector_binance/storage/db.py
scripts/health_monitor.sh
```

Также были untracked-файлы.

Перед работой обязательно:

```bash
git fetch origin
git branch --show-current
git rev-parse HEAD
git rev-parse origin/main
git status --short
git diff --stat
git diff --name-only
git log -5 --oneline
```

Запрещено:

```text
удалять или перезаписывать чужие dirty/untracked файлы
использовать git reset --hard
git clean
git stash без разрешения владельца
разрабатывать прямо в main
```

Правильный вариант:

```text
создать отдельный чистый git worktree от актуального origin/main
создать отдельную ветку
```

Рекомендуемая ветка:

```text
fix/canonical-candles-v2
```

Если происхождение существующих dirty-изменений неизвестно и отдельный clean worktree создать нельзя — остановиться.

---

## 5. Каноническая модель свечи

Новая модель должна содержать минимум:

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
is_closed
source
source_event_id        nullable
source_updated_at      nullable
ingested_at
quality_status
source_contract_version
checksum
```

Обязательные правила:

```text
interval = 1 minute для базовой таблицы
open_ts timezone-aware UTC
close_ts = open_ts + interval
is_closed = true
OHLC > 0
high >= max(open, close, low)
low <= min(open, close, high)
volume_base >= 0
volume_quote >= 0 или явно UNAVAILABLE
```

Ключ:

```text
UNIQUE(exchange, symbol, interval, open_ts)
```

Никакой event timestamp не используется как candle identity.

---

## 6. Binance collector contract

### WebSocket

Использовать только окончательную kline:

```text
k['x'] == true
```

Identity:

```text
open_ts = k['t']
close_ts = open_ts + 1 minute
```

`k['T']` можно хранить только как source close/event metadata, но не как candle key.

### REST/backfill

- использовать `k[0]` как `open_ts`;
- вычислять `close_ts = open_ts + 1 minute`;
- не сохранять текущую незакрытую свечу;
- eligibility:

```text
close_ts <= audited_now - ingestion_grace
```

- REST и WebSocket одной свечи должны попадать в один unique key;
- повторная доставка должна быть idempotent upsert, а не новая строка;
- конфликт одинакового key с другим payload должен логироваться и решаться по явной versioned policy.

---

## 7. Bybit collector contract

- использовать точное поле начала candle interval как `open_ts`;
- принимать для канонической таблицы только окончательную свечу:

```text
confirm == true
```

- промежуточные updates не записывать отдельными canonical candles;
- event/update timestamp хранить только как metadata;
- повторная доставка подтверждённой свечи должна быть idempotent;
- одинаковый candle key с отличающимся payload должен стать контролируемым conflict, а не молча создать дубль.

Перед реализацией агент обязан привести доказательство точных Bybit payload fields из официального сообщения/существующего collector code и реального безопасного sample.

---

## 8. Запись и конфликтная политика

Использовать узкую repository-функцию или SQL function, которая выполняет атомарно:

```text
validate canonical candle
calculate checksum
insert new candle
или idempotent no-op при том же checksum
или controlled conflict при другом checksum
```

Запрещено:

```text
INSERT без unique key
SELECT-then-INSERT как единственная защита от race
молчаливое создание второй строки
молчаливое изменение уже опубликованной свечи
```

Если допустима корректировка биржей, она должна иметь отдельную документированную модель revision/history. Простое UPDATE без audit history запрещено.

---

## 9. Quote volume / turnover

Для всего Paper Engine нужны отдельно:

```text
volume_base
volume_quote
```

Нужно доказать для каждой биржи:

```text
какое source field является base volume
какое source field является quote turnover/volume
единицы измерения
```

Нельзя вычислять quote volume через `volume_base * close`, если реальный turnover доступен.

Если quote volume не доказан:

```text
volume_quote = NULL
quality_status != COMPLETE
Levels formation блокируется
```

---

## 10. Новая часовая агрегация

Создать новую каноническую 1h view/continuous aggregate только поверх `candles_1m_canonical`.

Рекомендуемое имя:

```text
candles_1h_canonical
```

Агрегация для каждой пары `(exchange, symbol, hour)`:

```text
open          = первая open по open_ts
high          = max(high)
low           = min(low)
close         = последняя close по open_ts
volume_base   = sum(volume_base)
volume_quote  = sum(volume_quote)
minutes_count = 60
```

Часовая свеча COMPLETE только когда:

```text
ровно 60 уникальных закрытых минут
нет gap
нет duplicate key
нет INVALID/PARTIAL minute candle
hour close <= as_of - ingestion_grace
```

Неполный час нельзя молча выдавать как нормальную свечу.

---

## 11. Исторический backfill

Не считать legacy `candles_1m` автоматически истинной историей.

Порядок:

1. Определить доступные официальные REST history endpoints Binance и Bybit.
2. Заполнить `candles_1m_canonical` из официальных закрытых klines.
3. Выполнять backfill:

```text
по бирже
по symbol batches
по временным chunks
с checkpoints
с rate-limit handling
с resume после restart
```

4. Legacy-данные допускаются только как диагностический источник сравнения, не как автоматический источник истины.
5. Каждый chunk сохраняет:

```text
source range
rows expected
rows received
rows inserted
rows idempotent
conflicts
gaps
checksum
```

Никаких тяжёлых unbounded запросов к production TimescaleDB.

---

## 12. Переключение без остановки старой системы

Порядок rollout:

```text
1. создать новую таблицу и код записи
2. включить dual-run/dual-write без переключения consumers
3. собрать доказательства качества
4. backfill истории
5. создать canonical 1h
6. повторить read-only аудит
7. только после APPROVED переключить paper_market_reader
8. legacy consumers monitor-data не менять без отдельного решения
```

Не выполнять destructive cutover.

---

## 13. Quality statuses

Минимально поддержать:

```text
COMPLETE
PARTIAL
GAPPED
DUPLICATED
OUT_OF_ORDER
INVALID
STALE
UNAVAILABLE
CONFLICT
```

`COMPLETE` разрешён только при доказанном source contract и полной валидации.

---

## 14. Индексы и TimescaleDB

Нужно создать и доказать индексы для запросов:

```text
(exchange, symbol, open_ts DESC)
(exchange, open_ts DESC)
```

Проверить hypertable/chunk policy и планы типовых bounded Reader-запросов.

Не создавать индекс или policy на живой базе без отдельного плана блокировок и rollback.

---

## 15. Обязательные тесты

### Unit

```text
Binance WS open-time normalization
Binance x=false ignored
Binance REST unclosed candle ignored
REST/WS same candle identity
Bybit confirm=false ignored
Bybit confirm=true accepted
Bybit event timestamp not used as identity
UTC and exact close boundary
OHLC constraints
base/quote volume mapping
checksum stability
same key + same checksum = no-op
same key + different checksum = conflict
```

### PostgreSQL integration

```text
unique candle key
concurrent upserts
no semantic duplicate
conflict history
read-only reader grants
exchange isolation
canonical 1h exact 60-minute requirement
volume_quote aggregation
migration clean/rerun
```

### Restart/replay

```text
collector restart
REST replay
WebSocket duplicate delivery
backfill resume
no duplicate rows
no skipped committed checkpoint
```

### Data acceptance

Для Binance и Bybit отдельно минимум:

```text
20 representative symbols
30 consecutive days
exact candle key duplicates = 0
semantic minute duplicates = 0
invalid OHLCV = 0
gap statistics documented
freshness documented
1h rows match independent aggregation from canonical 1m
volume_base and volume_quote match
future/unclosed candles = 0
```

Полный запрос выполнять bounded chunks, не одним тяжёлым aggregate.

---

## 16. Runtime acceptance verdict

По каждой бирже вернуть один итог:

```text
APPROVED_CANONICAL_1M_AND_1H
APPROVED_CANONICAL_1M_ONLY
BLOCKED
```

Для запуска Stage 4B на реальной Market DB требуется минимум:

```text
APPROVED_CANONICAL_1M_AND_1H
```

Либо `APPROVED_CANONICAL_1M_ONLY`, если Paper Engine самостоятельно агрегирует и отдельно доказывает 1h.

---

## 17. Обязательные evidence

Сохранить в Markdown, а не только во временных файлах:

```text
Git preflight и dirty-worktree proof
branch/base/final SHA
schema и constraints
collector field mapping
sample source payloads без секретов
role grants
migration logs
unit/integration/restart results
bounded 30-day data metrics
Binance/Bybit duplicate and gap metrics
1m → 1h comparison
query plans
container status before/after
proof legacy tables not destructively changed
secret scan
git diff --check
final changed-file list
```

---

## 18. Запрещённые изменения

Без отдельного разрешения владельца запрещено:

```text
удалять legacy candles_1m/candles_1h
переписывать legacy историю UPDATE/DELETE
перезапускать несвязанные контейнеры
менять paper-trading-engine
менять paper accounts/ledger/trades
менять OI/funding/liquidation semantics
начинать Stage 4B Levels implementation внутри monitor-data
скрывать source conflicts
выдавать fixture test за production proof
```

---

## 19. Итоговый отчёт агента

```text
MONITOR-DATA CANONICAL CANDLES — FINAL REPORT

1. Verdict Binance.
2. Verdict Bybit.
3. Base SHA / Final SHA / branch.
4. Dirty original worktree handling.
5. Changed files.
6. New schema and keys.
7. Binance normalization.
8. Bybit normalization.
9. Base/quote volume semantics.
10. Idempotency/conflict model.
11. Historical backfill.
12. Canonical 1h aggregation.
13. Duplicate/gap/freshness metrics.
14. Test results.
15. Restart/replay results.
16. Runtime/container evidence.
17. What is proven.
18. What is not proven.
19. Open issues.
20. Recommendation for paper-trading-engine Reader.
21. Git status/diff check.
```

---

## 20. Условие остановки

После создания исправления и evidence:

```text
остановиться
не переключать production consumers без разрешения
не удалять legacy tables
не выполнять merge самостоятельно
не изменять paper-trading-engine
передать Final SHA и отчёт на независимый аудит
```
