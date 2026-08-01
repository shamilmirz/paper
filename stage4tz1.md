# ТЗ №1. Scanner + Growth State

## 1. Цель этапа

Реализовать поиск рыночных событий и состояний роста отдельно для Binance и Bybit.

Физически должны работать два контейнера:

```text
paper-scanner-binance
paper-scanner-bybit
```

Использовать одну кодовую базу и один Docker-образ с параметром:

```text
EXCHANGE=BINANCE
EXCHANGE=BYBIT
```

Каждый контейнер работает только со своей биржей.

Внутри каждого контейнера находятся два независимых логических модуля:

```text
Primitive Scanner
Growth State
```

Дополнительные отдельные Growth-контейнеры в v1 не создавать.

---

# 2. Обязательная предварительная проверка

Перед изменением кода:

1. Прочитать:

   * `README.md`;
   * `docs/architecture/SERVICE_BOUNDARIES.md`;
   * `docs/stages/STAGE_03_REPORT.md`;
   * `docs/market_data/TIMESTAMP_CONTRACT.md`;
   * `docs/market_data/FEATURE_CONTRACT.md`;
   * `docs/market_data/SOURCE_MAPPING.md`.

2. Проверить фактическое состояние ветки `main`.

3. Зафиксировать расхождение:

   * `STAGE_03_REPORT.md` сообщает, что Stage 3 прошёл и объединён с `main`;
   * README может содержать старый статус `REJECT`.

4. Не менять торговую логику для устранения документального расхождения.

5. Работать в отдельной ветке:

```text
stage/04-scanners
```

Не выполнять merge в `main` и не запускать production-развёртывание без отдельного разрешения.

---

# 3. Архитектурные ограничения

## Разрешено

Scanner и Growth:

```text
читают Universe
читают immutable Features
читают данные через Market Data Reader
пишут события, состояния и Candidates в Paper DB
```

## Запрещено

```text
изменять monitor-data
изменять Market DB
писать в Market DB
читать физические таблицы Market DB напрямую в обход Reader
открывать сделки
создавать торговые сигналы
резервировать баланс
изменять счета и ledger
зависеть от Levels
объединять Binance и Bybit
```

Scanner не должен зависеть от Growth.

Growth не должен зависеть от Scanner.

Они находятся в одном контейнере только физически, но имеют:

```text
отдельные модули
отдельные watermarks
отдельные записи состояний
отдельные метрики
отдельные правила идемпотентности
```

---

# 4. Работа с рыночными данными

Обязательные правила:

```text
только Decimal
float запрещён
только timezone-aware UTC
обязательный явный as_of
только закрытые свечи
будущие данные исключаются
missing остаётся None
None никогда не превращается в 0
funding не forward-fill
```

OI используется только в базовом количестве монет:

```text
oi_base
```

OI в долларах или quote currency не использовать.

Данные Binance и Bybit не смешивать.

Максимальный запрос Market Data Layer:

```text
не более 100 символов
```

Если Universe содержит больше символов, обрабатывать его последовательными пакетами до 100 символов.

---

# 5. Primitive Scanner

Каждое условие создаёт отдельный Candidate.

Условия между собой не объединять.

По одной монете одновременно могут существовать:

```text
PRICE_UP_30M
OI_UP_30M
VOLUME_SPIKE_3M
OI_UP_2H
FUNDING_NEGATIVE_EXTREME
LONG_LIQUIDATION_SPIKE
SHORT_LIQUIDATION_SPIKE
```

Detector позже самостоятельно решает, какие события использовать вместе.

---

## 5.1 PRICE_UP_30M

Использовать только закрытые свечи за последние 30 минут.

Формула:

```text
(latest_close - minimum_close_30m)
/
minimum_close_30m
× 100
```

Условие:

```text
рост ≥ 3%
```

Candidate:

```text
PRICE_UP_30M
```

Сохранить:

```text
latest_close
minimum_close
change_pct
window_start
window_end
feature_snapshot_id
quality_status
```

---

## 5.2 OI_UP_30M

Использовать совместимые наблюдения `oi_base` за последние 30 минут.

Формула:

```text
(latest_oi - minimum_oi_30m)
/
minimum_oi_30m
× 100
```

Условие:

```text
рост OI ≥ 3%
```

Candidate:

```text
OI_UP_30M
```

При пропусках, несовместимом OI или нулевом знаменателе Candidate не создавать.

---

## 5.3 VOLUME_SPIKE_3M

Построить закрытую 3-минутную свечу из трёх закрытых минутных свечей:

```text
open   = open первой минутной свечи
high   = максимальный high
low    = минимальный low
close  = close последней минутной свечи
volume = сумма quote volume
```

Запрещено использовать `MAX(close)` вместо фактического последнего close.

Сравнить объём последней закрытой 3-минутной свечи со средним объёмом предыдущих девяти закрытых 3-минутных свечей.

Условия:

```text
latest_volume_3m ≥ 10 × average_previous_9
close > open
```

Candidate:

```text
VOLUME_SPIKE_3M
```

Если отсутствует хотя бы одна необходимая свеча или quote volume недоступен, Candidate не создавать.

---

## 5.4 OI_UP_2H

Использовать совместимые закрытые наблюдения `oi_base` за последние два часа.

Условие:

```text
рост текущего OI от минимального OI окна ≥ 5%
```

Candidate:

```text
OI_UP_2H
```

---

## 5.5 FUNDING_NEGATIVE_EXTREME

Условие для обеих бирж:

```text
funding ≤ −2%
```

Candidate:

```text
FUNDING_NEGATIVE_EXTREME
```

Обрабатывать только новое подтверждённое actual funding event:

```text
Binance — при появлении нового часового значения
Bybit — при появлении нового подтверждённого события из WebSocket-цепочки
```

Scanner не подключается напрямую к биржевому WebSocket. Он читает нормализованное подтверждённое событие через Market Data Layer.

Повторная обработка одного funding event запрещена.

---

# 6. Ликвидации

## 6.1 Разделение направлений

LONG- и SHORT-ликвидации считать отдельно:

```text
long_liquidations_usd
short_liquidations_usd
```

Запрещено:

```text
суммировать LONG и SHORT
сравнивать LONG с историей SHORT
сравнивать SHORT с историей LONG
```

---

## 6.2 Ранняя отметка окна

Одна отдельная ликвидация:

```text
≥ 50 000 USD
```

помечает текущее 3-минутное окно для обязательной проверки.

Это не создаёт Candidate.

Окончательное решение принимается только после закрытия 3-минутного окна.

---

## 6.3 Условия ликвидационного всплеска

После закрытия окна каждая сторона проверяется отдельно.

Одновременно должны выполняться условия:

```text
сумма стороны за 3 минуты ≥ 100 000 USD
```

и:

```text
сумма стороны за 3 минуты
≥ 5 × среднего этой же стороны
за предыдущие 24 часа
```

Предыдущие 24 часа:

```text
480 закрытых 3-минутных окон
```

Текущее окно в baseline не включать.

При недоступных данных, неизвестной стороне ликвидации, отсутствующем timestamp, невалидном amount или недостаточном качестве Candidate не создавать.

---

## 6.4 Единое исходное событие

Каждый подтверждённый ликвидационный всплеск сохраняется один раз:

```text
liquidation_spike_event
```

Уникальность события:

```text
exchange
+ symbol
+ liquidation_side
+ closed_3m_bucket
+ policy_version
```

Событие получает:

```text
event_id
```

Хранить:

```text
exchange
symbol
side
bucket_start
bucket_end
total_liquidations_usd
largest_single_liquidation_usd
liquidation_count
baseline_24h
multiple
source_feature_snapshot
quality_status
policy_version
```

---

## 6.5 Candidates от одного события

Primitive Scanner создаёт собственный Candidate:

```text
LONG_LIQUIDATION_SPIKE
или
SHORT_LIQUIDATION_SPIKE
```

со ссылкой:

```text
source_event_id = event_id
```

Growth может создать отдельный Candidate со ссылкой на тот же `event_id`, только если существует собственный Growth-контекст.

Это не считается дублем, потому что:

```text
разный producer
разный контекст
разное назначение
```

Два полностью одинаковых Candidate одного producer не создавать.

---

# 7. Growth State

Growth ведёт отдельный episode для каждой пары:

```text
exchange + symbol
```

Состояния:

```text
IDLE
GROWTH_STARTED
GROWTH_CONFIRMED
AT_PEAK
CORRECTING
EXPIRED
```

---

## 7.1 GROWTH_STARTED

Найти рост цены:

```text
не менее 20%
```

за период:

```text
от 3 до 7 дней
```

Считать движение:

```text
от минимальной цены начала episode
до последующего максимума
```

При создании episode сохранить:

```text
episode_id
start_at
start_price
current_high
current_high_at
price_growth_pct
```

---

## 7.2 GROWTH_CONFIRMED

Рост подтверждается, если совместимый `oi_base` вырос:

```text
не менее чем на 5%
```

от значения начала episode.

Сохранить:

```text
start_oi
current_oi
oi_growth_pct
```

Если OI отсутствует или несовместим, состояние не подтверждать.

---

## 7.3 AT_PEAK

После подтверждённого роста сохранять максимум:

```text
peak_price
peak_at
peak_volume
peak_oi
```

При новом максимуме обновлять peak.

Историю изменений peak не терять.

---

## 7.4 CORRECTING

Рассчитать снижение от подтверждённого peak:

```text
(peak_price - current_price)
/
peak_price
× 100
```

Условие:

```text
коррекция от 10% до 30%
```

При первом переходе:

```text
AT_PEAK → CORRECTING
```

создать отдельный Candidate:

```text
GROWTH_CORRECTION
```

Повторно создавать Candidate на каждой следующей свече запрещено.

Коррекция меньше 10% не переводит episode в `CORRECTING`.

При разрушении условий episode переводить в `EXPIRED` по явному versioned policy, а не удалять запись.

---

## 7.5 Ликвидации внутри Growth

Growth получает оба направления ликвидаций.

Growth не суммирует стороны и не меняет из-за них цену, peak или границы episode.

Если ликвидационный всплеск произошёл при состоянии:

```text
GROWTH_CONFIRMED
AT_PEAK
CORRECTING
```

Growth может создать отдельный Candidate:

```text
GROWTH_LIQUIDATION_CONTEXT
```

Candidate обязан содержать:

```text
episode_id
growth_state
liquidation_side
source_event_id
price_growth_pct
oi_growth_pct
correction_pct
```

При `IDLE` отдельный Growth Candidate создавать запрещено.

---

# 8. Candidate contract

Candidate после создания является immutable.

Разрешено менять только его статус в отдельной projection.

Минимальные поля:

```text
candidate_id
producer
producer_version
event_type
exchange
symbol
event_bucket
detected_at
expires_at
as_of_ts
quality_status
feature_snapshot_id
source_event_id
growth_episode_id
evidence
```

Producer:

```text
SCANNER
GROWTH
```

Уникальность Candidate:

```text
exchange
+ symbol
+ producer
+ event_type
+ event_bucket
+ producer_version
```

Поле `producer` обязательно, поскольку одно ликвидационное событие может обоснованно создать два разных Candidate.

Статусы:

```text
AVAILABLE
EXPIRED
INVALID
```

Срок жизни:

```text
15 минут
```

После `expires_at` Candidate переводится в `EXPIRED`.

Просроченный Candidate не передавать Detector как активный.

---

# 9. Частота работы

## Каждую минуту

После закрытия минутной свечи:

```text
PRICE_UP_30M
OI_UP_30M
OI_UP_2H
обновление активных Growth episodes
обновление peak и correction
```

Обработка выполняется пакетами до 100 символов.

## После закрытия 3-минутного окна

```text
VOLUME_SPIKE_3M
LONG_LIQUIDATION_SPIKE
SHORT_LIQUIDATION_SPIKE
```

## При новом funding event

```text
FUNDING_NEGATIVE_EXTREME
```

## Периодически

```text
expiration projection
recovery зависших watermarks
health и heartbeat
```

---

# 10. Идемпотентность и восстановление

После перезапуска контейнер должен:

```text
прочитать watermark
продолжить с последнего подтверждённого закрытого окна
повторно обработать безопасный overlap
не создавать дубли
```

Каждый logical worker имеет собственный watermark:

```text
scanner_watermark
growth_watermark
```

Все записи должны быть защищены уникальными индексами.

Ошибка одной монеты не должна отменять обработку всего пакета.

Ошибка записи не должна продвигать watermark.

---

# 11. Минимальные таблицы или эквивалентные модели

```text
candidate_events
candidate_status_projection
growth_episodes
growth_state_history
liquidation_spike_events
scanner_watermarks
growth_watermarks
service_heartbeats
```

Названия могут соответствовать уже утверждённой схеме проекта, но смысл и ownership менять запрещено.

---

# 12. Проверки и тесты

Обязательные unit-тесты:

```text
каждый тип Scanner-события
точные пороговые значения
закрытые и незакрытые окна
пропущенные свечи
None вместо нуля
Decimal вместо float
раздельные LONG/SHORT-ликвидации
триггер одной ликвидации 50 000 USD
итоговый порог 100 000 USD
кратность 5×
исключение текущего окна из baseline
candidate TTL 15 минут
Growth transitions
новый peak
коррекция 10–30%
идемпотентный replay
```

Обязательные integration-тесты:

```text
Binance полностью изолирован от Bybit
две биржи создают независимые события
один liquidation event_id используется разными producers
повторный запуск не создаёт дубль
batch больше 100 отклоняется или автоматически делится
перезапуск продолжает с watermark
ошибка качества работает fail-closed
```

Обязательный smoke-тест Docker Compose:

```text
paper-scanner-binance healthy
paper-scanner-bybit healthy
разные exchange-конфигурации
разные heartbeats
отсутствуют записи в Market DB
```

---

# 13. Критерии приёмки

Этап принимается только если:

```text
работают ровно два scanner-контейнера
Scanner и Growth логически независимы
все события считаются только по закрытым данным
Binance и Bybit не смешиваются
OI используется в монетах
LONG и SHORT ликвидации разделены
Candidates имеют TTL 15 минут
один исходный liquidation event не дублируется
replay не создаёт дублей
Market DB остаётся read-only
все тесты проходят
```

---

# 14. Отчёт агента

В конце предоставить:

```text
карта реализованных компонентов
список изменённых файлов
схема таблиц и индексов
Docker Compose diff
список конфигурационных параметров
результаты unit/integration/smoke тестов
доказательство отсутствия записей в Market DB
доказательство изоляции Binance/Bybit
известные ограничения
commit SHA
```

Не выполнять merge и deployment без отдельной команды.
