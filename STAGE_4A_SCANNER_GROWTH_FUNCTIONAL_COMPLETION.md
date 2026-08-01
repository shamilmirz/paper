# STAGE 4A — SCANNER + GROWTH FUNCTIONAL COMPLETION AND REPAIR

## 1. Цель блока

Продолжить работу в существующей ветке и превратить текущий Scanner/Growth-каркас в реально исполняемый, транзакционный и перезапускаемый pipeline:

```text
Market Data Reader
→ ACTIVE Universe
→ Scanner calculations
→ Scanner Candidate
→ Growth discovery/state transitions
→ Growth Candidate
→ Paper DB
→ independent watermarks/errors/heartbeats
```

Этот блок должен завершить Scanner и Growth.

После его независимого PASS следующей задачей будет реализация Levels. Не начинать Levels в этом блоке.

---

## 2. Git baseline

Репозиторий:

```text
shamilmirz/paper-trading-engine
```

Рабочая ветка:

```text
stage/04-scanner-growth-levels
```

Ожидаемый исходный HEAD:

```text
f86e02113fc400ee0a18e02cd66ca41e24565822
```

Ожидаемый `origin/main`:

```text
0f745642f49262e3d714a377bb3811ffdc2dae36
```

Перед изменениями выполнить:

```bash
git fetch origin
git branch --show-current
git rev-parse HEAD
git rev-parse origin/main
git status --short
git log --oneline origin/main..HEAD
```

При несовпадении ветки, HEAD, base или при грязном рабочем дереве остановиться.

Не создавать новую ветку.

---

## 3. Разрешённые действия

Разрешено:

- изменять код только в текущей Stage 4 ветке;
- остановить и удалить старые disposable Stage 4 контейнеры;
- удалить и заново создать только disposable Stage 4 базы и volumes;
- перестроить Stage 4 image;
- изменить ещё не слитую migration `009_stage4_scanner_growth.sql`;
- заново применить migrations `001–009` на чистую disposable БД;
- создать один новый commit;
- выполнить обычный push в существующую ветку.

Финальный исправленный disposable runtime оставить запущенным и healthy.

---

## 4. Запрещённые действия

Запрещено:

```text
не менять origin/main
не создавать PR
не выполнять merge
не использовать force-push
не выполнять rebase опубликованной истории
не выполнять deployment
не подключаться к production Paper DB
не подключаться к production Market DB для тестов
не изменять monitor-data
не изменять production Docker services
не начинать Levels
не начинать Stage 5
не исправлять посторонние Stage 2 mypy-проблемы
```

Migrations `001–008` неизменяемы.

---

# ЧАСТЬ A — ФИНАЛЬНАЯ ФИЗИЧЕСКАЯ АРХИТЕКТУРА

## 5. Исправить Docker topology

Удалить отдельные application services:

```text
stage4-scanner
stage4-growth
```

Должны остаться ровно два Stage 4 application service:

```text
paper-scanner-binance
paper-scanner-bybit
```

Оба используют один image.

Переменные каждого контейнера:

```text
SERVICE_MODE=scanner
EXCHANGE=binance | bybit
SCANNER_DB_DSN=<scanner role>
GROWTH_DB_DSN=<growth role>
CANDIDATE_STATUS_DB_DSN=<status role>
HEARTBEAT_DATABASE_DSN=<heartbeat role>
MARKET_DATA_DSN=<read-only Market Data Reader role>
CONFIG_PATH=/app/configs/services/stage4-scanner-growth-v1.yaml
```

Внутри каждого контейнера одновременно работают два независимых логических worker:

```text
<service-name>.scanner
<service-name>.growth
```

У них должны быть отдельные:

- классы;
- repository instances;
- подключения и роли Paper DB;
- циклы обработки;
- watermarks;
- heartbeat identities;
- processing errors;
- retry state;
- метрики;
- terminal startup status.

Scanner не должен импортировать реализацию Growth.

Growth не должен импортировать реализацию Scanner.

Ошибка одного symbol не должна останавливать второй worker.

Terminal failure одного worker переводит container health в `DEGRADED`, но второй worker продолжает работу до controlled shutdown.

## 6. Disposable Compose

`docker-compose.stage4-test.yml` должен использовать отдельное Compose project name, чтобы существующий `paper-db` не появлялся как orphan.

Не использовать `network_mode: host`.

Создать изолированную disposable сеть и необходимые disposable DB services или использовать явно созданные disposable containers в этой сети.

Application containers:

- без bind mounts;
- запускаются не от root;
- исходный код находится внутри image;
- зависимости устанавливаются только во время image build;
- restart policy сохраняется;
- healthcheck проверяет не только таблицы, но и свежесть обоих логических heartbeat.

---

# ЧАСТЬ B — CONFIGURATION

## 7. Реальный config loader

Текущий YAML не должен просто копироваться в image.

Реализовать загрузку и строгую валидацию:

```text
policy_version
producer_version
candidate_ttl_minutes
scanner_batch_size
growth_bootstrap_batch_size
growth_incremental_batch_size
safe overlaps
все Scanner thresholds
все Growth thresholds
poll_interval
heartbeat_interval
```

Требования:

- проценты и денежные значения загружаются как `Decimal`;
- duration преобразуются в `timedelta`;
- неизвестные поля запрещены;
- отсутствующие обязательные поля вызывают terminal startup error;
- отрицательные и нулевые интервалы запрещены;
- `scanner_batch_size` не может превышать лимит Reader `100`;
- конфигурация Scanner и Growth представлена отдельными immutable policy-моделями;
- `episode_expiry: provisional` не должно автоматически создавать поведение.

---

# ЧАСТЬ C — DATABASE CONTRACT

## 8. Переработать migration 009

Migration `009_stage4_scanner_growth.sql` ещё не находится в `main`, поэтому исправить её напрямую и пересоздать disposable БД с нуля.

Не добавлять correction migration поверх заведомо неправильной 009.

## 9. TX-03A — Candidate publication

Разделить semantic ownership.

Scanner writer не должен иметь возможности создать Candidate с:

```text
producer=GROWTH
```

Growth writer не должен иметь возможности создать Candidate с:

```text
producer=SCANNER
```

Использовать отдельные функции либо функции с жёстко заданным producer:

```text
publish_scanner_candidate(...)
publish_growth_candidate(...)
```

На replay той же identity:

- одинаковый checksum возвращает фактически существующий `candidate_id`;
- другой checksum вызывает fail-closed conflict;
- новая строка не создаётся;
- возвращаемый UUID всегда существует в таблице.

Добавить или проверить:

- FK `liquidation_event_id`;
- FK `growth_episode_id`;
- допустимые quality statuses;
- UTC event window;
- необходимые индексы для producer identity, status и expiry;
- immutable payload и immutable identity.

## 10. TX-03B/TX-03C — Candidate status

Исправить status transition:

- блокировать Candidate `FOR UPDATE`;
- проверить исходный status;
- проверить idempotency key;
- append status event и изменение projection должны быть одной транзакцией;
- idempotency collision с другим Candidate должен завершаться ошибкой;
- status не может измениться без созданного audit event;
- первая terminal transition побеждает;
- повтор той же операции возвращает существующий результат;
- Scanner role не получает право invalidation;
- Growth role не получает право expiry/invalidation;
- используется отдельная status writer role.

## 11. Liquidation spike publication

Исправить функцию публикации spike:

- replay возвращает существующий `event_id`;
- checksum conflict завершается ошибкой;
- возвращаемый UUID существует;
- LONG и SHORT независимы;
- source identity set сохраняется канонически;
- запрещены записи неизвестной стороны или неподходящего quality status.

## 12. Идемпотентный early liquidation mark

Текущий `event_count += 1` при каждом replay запрещён.

Добавить уникальную фиксацию обработанного source liquidation event, например:

```text
liquidation_window_mark_events
```

Identity должна включать как минимум:

```text
exchange
symbol
liquidation_side
open_3m_bucket
policy_version
source deduplication identity
```

Aggregate mark изменяется только после успешной вставки нового уникального source event.

Replay:

```text
не увеличивает event_count
не меняет first_large_event_at
не создаёт дубликат
```

## 13. TX-04 — Growth transition function

Создать реальную атомарную DB-операцию для:

```text
growth_episodes
growth_episode_events
optional Growth Candidate
Growth watermark
```

Операция должна:

1. блокировать активный episode;
2. проверять ожидаемый `from_state`;
3. проверять source candle identity;
4. проверять transition/policy version;
5. проверять idempotency key;
6. обновлять episode projection;
7. добавлять immutable episode event;
8. при первом `AT_PEAK → CORRECTING` создавать ровно один Growth Candidate;
9. продвигать Growth watermark только после успешных записей;
10. полностью откатываться при любой ошибке.

Growth writer должен иметь EXECUTE только этой и других Growth-owned функций.

Scanner writer не должен иметь возможности писать Growth episode/event.

## 14. Processing errors

Сделать deterministic error identity.

Повтор одной ошибки должен:

- обновлять `last_seen_at`;
- увеличивать `attempt_count`;
- сохранять первоначальный `first_seen_at`;
- не создавать неограниченные дубликаты одной ошибки.

Успешная повторная обработка должна позволять установить `resolved_at`.

---

# ЧАСТЬ D — REPOSITORIES

## 15. Реализовать Postgres repositories

Интерфейсов `Protocol` недостаточно.

Реализовать:

```text
PostgresScannerRepository
PostgresGrowthRepository
PostgresCandidateStatusRepository
PostgresHeartbeatRepository
```

Repository обязаны:

- использовать только свои DSN/role;
- вызывать разрешённые функции;
- использовать явные транзакции;
- не выполнять прямые INSERT/UPDATE owned tables;
- проверять возвращённые IDs;
- правильно обрабатывать serialization/unique conflicts;
- различать retryable и terminal errors;
- не скрывать rollback;
- не продвигать watermark вне успешной публикационной транзакции.

---

# ЧАСТЬ E — SCANNER

## 16. Реализовать настоящий Scanner worker loop

Scanner должен:

1. получить ACTIVE и quality-eligible symbols из `market_universe`;
2. обрабатывать только свой `EXCHANGE`;
3. делить symbols на batches не более 100;
4. использовать существующий `MarketDataReader`;
5. не выполнять raw SQL к Market DB;
6. использовать только закрытые данные относительно явного UTC `as_of`;
7. применять safe overlap после restart;
8. рассчитывать primitive events;
9. публиковать Candidates;
10. фиксировать ошибки;
11. продвигать соответствующий watermark только после полного успешного bucket.

Обязательные stream keys:

```text
SCANNER_1M
SCANNER_3M
SCANNER_FUNDING
SCANNER_LIQUIDATION
CANDIDATE_EXPIRY
```

При ошибке одного symbol:

- обработать остальные symbols;
- записать symbol-scoped error;
- не продвигать общий bucket watermark;
- при следующем цикле безопасно повторить bucket;
- не создавать дубликаты уже опубликованных Candidates.

## 17. Исправить PRICE_UP_30M

Требования:

- только закрытые `1m` свечи;
- один exchange и один symbol;
- UTC;
- последнее закрытое окно;
- непрерывность окна проверяется;
- gap/duplicate/out-of-order/invalid вызывают fail-closed;
- latest close сравнивается с minimum close окна;
- порог включительный `>= 3%`;
- sparse набор из двух свечей не считается полноценным 30m окном.

## 18. Исправить OI_UP_30M и OI_UP_2H

Совместимость OI должна включать:

```text
exchange
symbol
instrument_type
source_unit/conversion contract
contract_multiplier contract
quality
```

Использовать только `oi_base`.

UNKNOWN, stale, invalid, incompatible или отсутствующий `oi_base`:

```text
Candidate не создаётся
```

Порог:

```text
30m: >= 3%
2h: >= 5%
```

Сохранять в payload minimum/latest OI, timestamps, compatibility evidence и identities.

## 19. Исправить VOLUME_SPIKE_3M

Использовать только UTC-aligned полностью закрытый bucket:

```text
[boundary - 3m, boundary)
```

Не строить скользящее невыравненное окно из последних трёх свечей.

Требования:

- ровно три непрерывные 1m свечи текущего bucket;
- предыдущие девять полностью закрытых и выровненных 3m buckets;
- quote volume;
- baseline mean > 0;
- current volume `>= 10 × baseline`;
- current 3m close > current 3m open;
- любой gap/duplicate/invalid input вызывает fail-closed.

## 20. Исправить liquidation baseline

Baseline должен состоять из **предыдущих 480 последовательных закрытых UTC 3m buckets**:

```text
current_start - 480 × 3m
→ current_start
```

Правила:

- нулевые buckets входят в average как zero;
- нельзя выбирать крупнейшие buckets;
- нельзя использовать события старше baseline window;
- события дедуплицируются по canonical deduplication key;
- invalid/unknown events исключаются с fail-closed quality evidence;
- exchange, symbol и side фильтруются явно;
- LONG и SHORT рассчитываются отдельно;
- absolute threshold `>= 100000`;
- relative threshold `>= 5 × average`;
- baseline считается доступным только при доказанном полном временном окне.

## 21. Funding

Обрабатывать только новый actual funding event.

Требования:

```text
normalized_rate <= -0.02
exact funding timestamp as event bucket
replay by source identity is idempotent
forecast/observation funding is ignored
unknown actualness fails closed
```

## 22. Canonical checksum

Не использовать:

```python
repr(sorted(payload.items()))
```

Реализовать canonical serialization:

- sorted JSON keys;
- Decimal как нормализованная строка;
- datetime как UTC ISO-8601;
- UUID как строка;
- стабильная обработка list/tuple/map;
- без float;
- checksum включает source identities, cutoff, policy version и calculation payload.

## 23. Candidate expiry

Добавить исполняемый expiry loop под отдельной status writer role.

Он переводит:

```text
AVAILABLE → EXPIRED
```

когда:

```text
now >= expires_at
```

Replay идемпотентен.

Scanner и Growth worker не получают прямого права самостоятельно менять Candidate status.

---

# ЧАСТЬ F — GROWTH

## 24. Growth discovery input

Технический default:

```text
closed 1h candles
7-day lookback
minimum duration 3 days
maximum duration 7 days
price growth >= 20%
```

Если Reader отдаёт 1m candles, построить 1h candles только из:

```text
60 непрерывных закрытых 1m свечей
```

Неполный час запрещено превращать в 1h candle.

Discovery должна явно проверять `interval`.

Не допускать квадратичный алгоритм по 10 080 минутным свечам на symbol. Использовать hourly rows и ограниченный/эффективный deterministic алгоритм.

## 25. Стартовый OI

При создании episode сохранить:

```text
start_oi
start OI timestamp
start OI source identity
compatibility fields
```

Стартовый OI выбирается относительно start/trough time по документированному правилу без future leakage.

Current OI должен быть совместим со start OI.

Без совместимого start/current `oi_base` переход в `GROWTH_CONFIRMED` невозможен.

## 26. Исправить state machine

Обязательные состояния:

```text
IDLE
GROWTH_STARTED
GROWTH_CONFIRMED
AT_PEAK
CORRECTING
EXPIRED
```

Точная логика:

```text
IDLE → GROWTH_STARTED
price growth >= 20%, duration 3–7 days
```

```text
GROWTH_STARTED → GROWTH_CONFIRMED
price condition всё ещё действительно
совместимый OI growth >= 5%
```

```text
GROWTH_CONFIRMED → AT_PEAK
сохранить фактический current closed 1m close как current/peak evidence
```

```text
AT_PEAK → AT_PEAK
любой новый close выше peak создаёт immutable PEAK_UPDATED event
```

```text
AT_PEAK → CORRECTING
первая коррекция 10%..30% включительно
```

Формула только:

```text
(peak_price - current_close) / peak_price × 100
```

```text
AT_PEAK → EXPIRED
если одна закрытая свеча сразу перескочила correction > 30%
```

```text
CORRECTING → AT_PEAK
только при close > сохранённого peak
from_state обязан быть CORRECTING
```

```text
CORRECTING → EXPIRED
correction > 30%
```

Новый peak обновляет:

```text
peak_price
peak_at
current_price
last_processed_candle
```

Каждая успешно обработанная свеча обновляет необходимый processing checkpoint, даже если state transition не возник.

## 27. Growth Candidate

Ровно один Candidate создаётся на первый переход:

```text
AT_PEAK → CORRECTING
```

Identity должна быть привязана к:

```text
exchange
symbol
producer=GROWTH
event_type=GROWTH_CORRECTION
closed event bucket
producer version
growth episode id
```

Replay той же correction transition не создаёт второй Candidate.

Новый пик после коррекции начинает новую возможную correction phase, которая может создать новый Candidate только на новом переходе `AT_PEAK → CORRECTING`.

## 28. Liquidation и Growth

Liquidation spike может создать отдельный Growth Candidate только при существующем активном episode.

Он:

- не изменяет Growth state;
- не изменяет start/peak/correction;
- содержит ссылку на существующий liquidation spike event;
- сохраняет LONG/SHORT отдельно;
- идемпотентен по spike identity и Growth producer version.

## 29. Time-based expiry

Не реализовывать непроверенную time-based expiry.

Оставить её в `STAGE_04_OPEN_ISSUES.md` как provisional decision.

---

# ЧАСТЬ G — RUNTIME ORCHESTRATOR

## 30. Заменить текущий runtime_service

Текущий бесконечный DB contract heartbeat не является worker runtime.

Новый runtime обязан:

1. загрузить config;
2. проверить `EXCHANGE`;
3. проверить все DSNs и роли;
4. выполнить Market Data Reader startup gate;
5. запустить Scanner loop;
6. запустить Growth loop;
7. запустить Candidate expiry loop;
8. запустить heartbeat publisher;
9. поддерживать независимый статус Scanner и Growth;
10. корректно обрабатывать SIGTERM;
11. закрывать pools/connections;
12. выдавать container health на основе фактического состояния workers.

Логи startup:

```text
runtime_started exchange=<exchange>
scanner_ready identity=<service>.scanner
growth_ready identity=<service>.growth
```

Запрещено считать компонент ready только потому, что таблица существует.

---

# ЧАСТЬ H — TESTS

## 31. Обязательные unit tests

Добавить отдельные тесты как минимум для:

### Scanner

- PRICE_UP_30M positive, boundary и below threshold;
- sparse/gapped 30m fail-closed;
- mixed symbol/exchange rejected;
- OI 30m positive;
- OI 2h positive;
- incompatible OI unit/instrument/multiplier fail-closed;
- volume aligned bucket;
- arbitrary poll time не создаёт невыравненный bucket;
- missing current/baseline candle fail-closed;
- liquidation previous exact 480 windows;
- zero buckets входят в average;
- old events вне baseline исключаются;
- duplicate liquidation event не удваивает total;
- LONG/SHORT separation;
- funding actual/replay/forecast;
- canonical checksum stability.

### Growth

- discovery только по 1h;
- incomplete 1h aggregation rejected;
- future leakage rejected;
- duration меньше 3 и больше 7 дней rejected;
- стартовый OI сохраняется;
- OI compatibility;
- price threshold действительно проверяется;
- `GROWTH_STARTED → GROWTH_CONFIRMED`;
- `GROWTH_CONFIRMED → AT_PEAK`;
- `AT_PEAK → AT_PEAK` new peak;
- correction ровно 10%;
- correction ровно 30%;
- direct correction больше 30%;
- `CORRECTING → AT_PEAK` с правильным from_state;
- `CORRECTING → EXPIRED`;
- ровно один Candidate на correction transition;
- replay не создаёт Candidate.

## 32. Обязательные PostgreSQL integration tests

На чистой disposable БД проверить:

- migrations `001–009`;
- роли и запрещённые права;
- Scanner не может публиковать Growth Candidate;
- Growth не может публиковать Scanner Candidate;
- Growth transition реально записывается;
- episode update + event + Candidate + watermark атомарны;
- forced failure откатывает все записи;
- concurrent Candidate publication;
- concurrent Growth transition;
- checksum conflict;
- spike replay возвращает существующий ID;
- early mark replay не увеличивает count;
- status idempotency collision не меняет projection;
- immutable episode events;
- Scanner/Growth не могут писать финансовые таблицы.

## 33. End-to-end disposable test

Создать детерминированные Binance и Bybit fixtures.

Запустить оба application container и доказать:

```text
paper-scanner-binance обрабатывает только Binance
paper-scanner-bybit обрабатывает только Bybit
```

Через реальный Reader/repositories/runtime получить:

- Scanner Candidate;
- Growth episode;
- Growth state events;
- Growth correction Candidate;
- отдельные Scanner/Growth watermarks;
- отдельные heartbeat identities.

После `docker compose restart`:

- записи не дублируются;
- watermarks не откатываются;
- episode сохраняется;
- workers продолжают обработку;
- оба контейнера healthy.

## 34. Failure isolation test

Инъецировать ошибку одного symbol в Growth.

Доказать:

- Scanner продолжает обработку остальных symbols;
- Growth error записан;
- ошибочный watermark не продвинут;
- после исправления fixture replay успешно обрабатывает bucket;
- дубликаты не появляются.

## 35. Load test

Минимальный disposable load:

```text
100 symbols на одну биржу
```

Проверить:

- ни один Reader request не содержит более 100 symbols;
- нет SQL query на каждый symbol там, где допустима batch-операция;
- память ограничена;
- worker loop завершается без N+1 explosion;
- измерены duration, query count и peak RSS.

Production performance не заявлять.

---

# ЧАСТЬ I — QUALITY GATES

## 36. Команды

Выполнить и сохранить полный вывод:

```bash
python -m compileall src tests
ruff check src tests
ruff format --check src tests
mypy <все новые и изменённые Stage 4 Python modules>
pytest -q tests/unit
pytest -q tests/integration/test_stage4_db.py
pytest -q <новые Stage 4 end-to-end tests>
git diff --check
```

Full-repository mypy не является gate из-за уже документированных посторонних ошибок.

Но targeted mypy обязан покрывать все новые и изменённые Stage 4 modules без исключений и blanket ignore.

## 37. Docker gates

На чистом disposable окружении:

```bash
docker compose -p paper-stage4-disposable -f docker-compose.stage4-test.yml config
docker compose -p paper-stage4-disposable -f docker-compose.stage4-test.yml build --no-cache
docker compose -p paper-stage4-disposable -f docker-compose.stage4-test.yml up -d
docker compose -p paper-stage4-disposable -f docker-compose.stage4-test.yml ps
docker compose -p paper-stage4-disposable -f docker-compose.stage4-test.yml restart
docker compose -p paper-stage4-disposable -f docker-compose.stage4-test.yml ps
```

Также сохранить:

```bash
docker inspect <binance-container>
docker inspect <bybit-container>
docker logs <binance-container>
docker logs <bybit-container>
```

Проверить:

```text
ровно два Stage 4 application container
оба non-root
bind mounts отсутствуют
оба logical workers видны в logs
оба healthy до restart
оба healthy после restart
```

---

# ЧАСТЬ J — DOCUMENTATION AND EVIDENCE

## 38. Создать или обновить

```text
docs/stages/STAGE_04_SCANNER_GROWTH_EVIDENCE.md
docs/stages/STAGE_04_OPEN_ISSUES.md
docs/stages/STAGE_04_REPORT.md
CURRENT_STATE.md
TODO.md
HANDOFF.md
```

Не объявлять весь Stage 4 завершённым.

Корректный статус:

```text
Stage 4A Scanner/Growth implementation complete — awaiting independent audit.
Stage 4B Levels not started.
Production source-contract gate remains unresolved.
```

Evidence должен содержать:

- Git base/head;
- список изменённых файлов;
- DB schema/functions/roles;
- реальные test commands;
- реальные counts;
- Docker service names;
- image digest;
- container user;
- mounts;
- health до/после restart;
- фактические созданные Candidate/Growth rows;
- replay results;
- rollback evidence;
- failure-isolation evidence;
- load measurements;
- известные ограничения.

Не использовать слова `PASS` без приложенного результата проверки.

---

# ЧАСТЬ K — COMMIT AND PUSH

## 39. Перед commit

Выполнить:

```bash
git status --short
git diff --check
git diff --stat
git diff -- migrations/009_stage4_scanner_growth.sql
git diff -- docker-compose.stage4-test.yml
git diff -- src/paper_engine
git diff -- tests
```

Проверить отсутствие:

- `.env`;
- паролей;
- DSN;
- токенов;
- private keys;
- runtime database dumps;
- generated caches;
- логов с credentials.

## 40. Commit

Создать один новый commit:

```text
fix(stage4): complete scanner and growth runtime
```

Не изменять старые опубликованные commit через rebase/amend.

## 41. Push

После всех gate:

```bash
git push origin stage/04-scanner-growth-levels
```

Без force-push.

Не создавать PR.

---

# ЧАСТЬ L — ФИНАЛЬНЫЙ ОТЧЁТ АГЕНТА

Вернуть:

```text
STAGE 4A — SCANNER/GROWTH FUNCTIONAL COMPLETION REPORT

Base SHA:
Previous HEAD:
New HEAD:
Remote branch SHA:
Commits ahead of main:
Working tree:

Changed files:

Runtime topology:
- application services:
- logical workers:
- DB roles:
- container users:
- mounts:

Scanner implemented:
- worker loop:
- events:
- expiry:
- watermarks:
- partial failure behavior:

Growth implemented:
- discovery:
- OI confirmation:
- transitions:
- correction Candidate:
- replay behavior:

Database:
- migration:
- functions:
- ownership isolation:
- rollback:
- idempotency:

Tests:
- compileall:
- ruff:
- format:
- targeted mypy:
- unit:
- integration:
- end-to-end:
- load:

Docker:
- image:
- initial health:
- restart health:
- scanner logs:
- growth logs:

Evidence files:

Known open issues:

Production connection performed: NO
monitor-data modified: NO
PR created: NO
Merge performed: NO
Deployment performed: NO
Levels started: NO
Force-push performed: NO
```

После push и отчёта остановиться.

Не начинать Levels самостоятельно.
