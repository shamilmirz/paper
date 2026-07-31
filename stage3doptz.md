# Техническое задание

## Paper Trading Engine — Stage 3 Market Data Layer

### Задача

Исправить только оставшиеся замечания независимого аудита Stage 3.

Не переписывать Market Data Layer с нуля. Не менять общую архитектуру проекта. Не создавать Scanner, Detector, Trading или Stage 4 компоненты.

Текущая исходная точка:

```text
Repository: shamilmirz/paper-trading-engine
Branch: stage/03-market-data
Base SHA: ee72737406461df90980c51063fce297d7faa0be
Published Stage 3 SHA: 95fdcecd1c2330bf5e452386722b3d30f8d9d48e
Current verdict: REJECT
```

Конечный результат этой работы:

```text
Stage 3 remediation completed locally
READY FOR INDEPENDENT RE-AUDIT
NOT MERGED
NOT CLOSED
NOT PUSHED without separate owner approval
```

---

# 1. Главный принцип работы

Исправлять только найденные дефекты.

Запрещено проводить общий рефакторинг «для красоты», переименовывать существующие сущности без необходимости, переносить весь код между пакетами, вводить новый framework или менять уже работающие Stage 1–2 компоненты.

Перед каждым изменением ответить на вопрос:

```text
Какое конкретное замечание аудита закрывает это изменение?
```

Если изменение не закрывает конкретное замечание — не выполнять его.

---

# 2. Git-проверка перед началом

Выполнить:

```bash
git fetch origin
git checkout stage/03-market-data
git status --short
git rev-parse HEAD
git rev-parse origin/stage/03-market-data
git merge-base HEAD origin/main
git log --oneline --decorate -5
```

Ожидается:

```text
HEAD = 95fdcecd1c2330bf5e452386722b3d30f8d9d48e
origin/stage/03-market-data = тот же SHA
merge-base с main = ee72737406461df90980c51063fce297d7faa0be
worktree clean
```

Если SHA отличается или worktree не чистый:

```text
STOP — GIT BASELINE MISMATCH
```

Не выполнять reset, rebase, checkout чужих файлов или удаление изменений без разрешения владельца.

---

# 3. Разрешённый scope

Разрешено изменять только следующие существующие файлы:

```text
src/paper_engine/common/config.py

src/paper_engine/domain/market_data/models.py

src/paper_engine/market_data/reader.py
src/paper_engine/market_data/postgres_reader.py
src/paper_engine/market_data/normalization.py
src/paper_engine/market_data/features.py
src/paper_engine/market_data/universe.py
src/paper_engine/market_data/quality.py

migrations/008_stage3_market_data.sql

configs/services/stage3-quality-policy.yaml
configs/services/stage3-quality-policy.yaml.example

tests/unit/test_market_data.py
tests/unit/test_market_data_semantics.py
tests/unit/test_features_correctness.py
tests/unit/test_reader_startup.py
tests/unit/test_market_data_architecture.py

tests/integration/test_stage3_reader.py
tests/integration/test_stage3_oi_reader.py
tests/integration/test_stage3_publication.py
tests/integration/test_stage3_permissions.py

tests/load/test_stage3_market_reader_load.py

CURRENT_STATE.md
TODO.md
HANDOFF.md
README.md
DECISIONS.md

docs/architecture/MARKET_DATA_CONTRACT.md
docs/architecture/DATABASE_CONTRACT.md
docs/architecture/SERVICE_BOUNDARIES.md
docs/architecture/TEST_STRATEGY.md

docs/market_data/SOURCE_MAPPING.md
docs/market_data/SOURCE_SCHEMA_AUDIT.md
docs/market_data/TIMESTAMP_CONTRACT.md
docs/market_data/FEATURE_CONTRACT.md
docs/market_data/READ_ONLY_EVIDENCE.md
docs/market_data/STAGE_03_PERFORMANCE_REPORT.md

docs/stages/STAGE_03_REPORT.md
docs/stages/STAGE_03_EVIDENCE.md
docs/stages/STAGE_03_OPEN_ISSUES.md
```

Разрешено создать не более трёх новых runtime-файлов:

```text
src/paper_engine/market_data/source_contracts.py
src/paper_engine/market_data/policy.py
src/paper_engine/market_data/publication.py
```

И не более трёх новых тестовых файлов, только если существующие тестовые файлы невозможно логично расширить.

Любой другой новый runtime-файл требует отдельного обоснования в финальном отчёте.

---

# 4. Категорически запрещено

Не изменять:

```text
migrations/001–007
accounting
accounts
ledger
financial transactions
execution
trading
scanner
detector
signals
growth state
levels
dashboard
Docker Compose
scheduler
production services
GitHub Actions
main
monitor-data
```

Не выполнять:

```text
git merge
git rebase
git push
git push --force
git push --force-with-lease
создание PR
изменение main
production restart
production DDL/DML
изменение paper_market_reader
изменение Timescale grants
```

Репозиторий `monitor-data` разрешено только читать.

Не исправлять коллекторы в рамках этого задания.

---

# 5. Исправление source contracts

## 5.1. Проблема

Текущий Reader предполагает:

```text
physical candles_1m.ts = canonical open_ts
```

Это не доказано.

В `monitor-data` наблюдается:

```text
Binance WebSocket:
ts берётся из k["T"] — close timestamp.

Binance REST:
ts берётся из k[0] — open timestamp.

Bybit:
ts берётся из timestamp/start fallback;
confirm закрытой свечи не проверяется.
```

Поэтому запрещено продолжать считать все физические `ts` временем открытия свечи без отдельного контракта.

## 5.2. Требуемое минимальное изменение

Создать:

```text
src/paper_engine/market_data/source_contracts.py
```

Добавить только минимальные typed contracts.

Ожидаемые сущности:

```python
class CandleTimestampSemantics(StrEnum):
    OPEN_TS = "OPEN_TS"
    CLOSE_TS = "CLOSE_TS"
    MIXED = "MIXED"
    UNKNOWN = "UNKNOWN"


class FundingSemantics(StrEnum):
    ACTUAL_SETTLED_EVENT = "ACTUAL_SETTLED_EVENT"
    OBSERVATION = "OBSERVATION"
    UNKNOWN = "UNKNOWN"


class LiquidationSemantics(StrEnum):
    PROVEN_CANONICAL = "PROVEN_CANONICAL"
    UNKNOWN = "UNKNOWN"


@dataclass(frozen=True, slots=True)
class ExchangeSourceContract:
    exchange: str
    candle_timestamp_semantics: CandleTimestampSemantics
    oi_source_unit: SourceUnit
    oi_contract_multiplier: Decimal | None
    oi_instrument_type: str | None
    funding_semantics: FundingSemantics
    liquidation_semantics: LiquidationSemantics
```

Названия могут незначительно отличаться, но смысл менять нельзя.

## 5.3. Production contracts

Текущие production contracts должны оставаться fail-closed:

```text
Binance candles: MIXED или UNKNOWN
Bybit candles: UNKNOWN

Binance OI: UNKNOWN
Bybit OI: UNKNOWN

Binance funding: OBSERVATION
Bybit funding: OBSERVATION

Binance liquidations: UNKNOWN
Bybit liquidations: UNKNOWN
```

Запрещено выставлять `OPEN_TS`, `BASE_ASSET`, `ACTUAL_SETTLED_EVENT` или `PROVEN_CANONICAL` только на основании названия поля или комментария в старом коде.

## 5.4. Reader behavior

Перед чтением конкретного source Reader должен проверять contract.

Для candles:

```text
OPEN_TS:
разрешить текущую canonical нормализацию.

CLOSE_TS:
не реализовывать приблизительное вычитание одной минуты;
fail closed до точного exchange contract.

MIXED или UNKNOWN:
не выполнять production query;
raise SourceContractUnavailable.
```

Для OI:

```text
BASE_ASSET:
source_value можно использовать как oi_base.

CONTRACTS:
oi_base только при наличии доказанного multiplier.

QUOTE_ASSET/USD/USDT/UNKNOWN:
oi_base = None.
```

Для funding:

```text
ACTUAL_SETTLED_EVENT:
is_actual_funding_event = True.

OBSERVATION/UNKNOWN:
is_actual_funding_event = False.
```

Для liquidations:

```text
PROVEN_CANONICAL:
разрешить SQL aliases:
side → liquidated_position_side
qty → quantity_base
usd_value → notional_quote
только если это прямо зафиксировано в contract.

UNKNOWN:
не выполнять query;
raise SourceContractUnavailable.
```

Нельзя возвращать пустой список, имитируя доказанное отсутствие событий, если source contract недоступен.

## 5.5. Исключение

Добавить отдельное исключение:

```python
class SourceContractUnavailable(RuntimeError):
    ...
```

Не использовать общий `ValueError` для отсутствующего production contract.

## 5.6. Тесты

Обязательные unit tests:

```text
UNKNOWN candle contract блокирует Reader query.
MIXED candle contract блокирует Reader query.
UNKNOWN liquidation contract блокирует Reader query.
UNKNOWN OI возвращает oi_base=None.
CONTRACTS без multiplier возвращает oi_base=None.
CONTRACTS с multiplier вычисляет oi_base.
OBSERVATION funding не становится actual funding.
```

Проверить, что при fail-closed состоянии SQL вообще не выполнялся.

---

# 6. Reader timestamp boundary

Файл:

```text
src/paper_engine/market_data/postgres_reader.py
```

## 6.1. Добавить единый validator

Добавить приватную функцию или метод:

```python
def _validated_window(
    start: datetime,
    end: datetime,
    as_of: datetime,
) -> tuple[datetime, datetime, datetime]:
    ...
```

Обязательное поведение:

```text
start timezone-aware;
end timezone-aware;
as_of timezone-aware;

все timestamps привести в UTC;

start < end;
as_of >= start;
naive timestamp → ValueError;
bool/float/int вместо datetime → TypeError.
```

Не полагаться на неявное преобразование asyncpg/PostgreSQL.

## 6.2. Использование

Validator должен вызываться в начале каждого метода:

```text
fetch_candles
fetch_latest_open_interest
fetch_open_interest_history
fetch_funding_events
fetch_liquidation_events
fetch_instrument_metadata
```

## 6.3. Candle SQL

Сохранить исправленное условие:

```sql
ts + interval '1 minute' + $grace::interval <= $as_of
```

Но выполнять этот SQL только при доказанном:

```text
candle_timestamp_semantics = OPEN_TS
```

## 6.4. Тесты

Добавить tests:

```text
naive start rejected;
naive end rejected;
naive as_of rejected;
start == end rejected;
start > end rejected;
as_of < start rejected;
timezone-aware non-UTC input normalized to UTC;
candle earlier than close+grace excluded;
candle exactly at close+grace included.
```

Последние два теста должны использовать настоящий disposable PostgreSQL Reader, а не mock.

---

# 7. Reader Protocol

Файл:

```text
src/paper_engine/market_data/reader.py
```

Добавить в `MarketDataReader Protocol`:

```python
async def fetch_open_interest_history(
    self,
    exchange: str,
    symbols: Sequence[str],
    start: datetime,
    end: datetime,
    as_of: datetime,
    quality_policy_version: str,
) -> list[OpenInterestSnapshot]:
    ...
```

Protocol и `PostgresMarketDataReader` должны совпадать.

Добавить architecture/type test, который подтверждает наличие метода в Protocol и implementation.

Не создавать второй альтернативный Reader interface.

---

# 8. Versioned Quality Policy

## 8.1. Проблема

Сейчас YAML существует, но runtime не использует его как единый policy object.

## 8.2. Реализация

Создать:

```text
src/paper_engine/market_data/policy.py
```

Добавить immutable typed model:

```python
@dataclass(frozen=True, slots=True)
class MarketDataQualityPolicy:
    version: str
    candle_ingestion_grace: timedelta
    candle_max_age: timedelta
    oi_max_age: timedelta
    oi_lookup_max_lag: timedelta
    funding_feature_max_age: timedelta
    liquidation_max_age: timedelta
    minimum_volume_24h_quote: Decimal
```

Допустимо использовать Pydantic вместо dataclass, но итоговый объект должен быть immutable.

Добавить функцию:

```python
def load_quality_policy(path: Path) -> MarketDataQualityPolicy:
    ...
```

Разрешено добавить только одну небольшую dependency для безопасного YAML parsing, если она ещё отсутствует:

```text
PyYAML
```

Не писать самодельный общий YAML parser.

## 8.3. YAML

Добавить поле:

```yaml
oi_lookup_max_lag_seconds: 90
```

То же поле добавить в `.example`.

Значение должно быть явно документировано как policy, а не спрятано в Python default.

## 8.4. Использование policy

Policy должен реально использоваться в:

```text
PostgresMarketDataReader
calculate_features / calculate_feature_batch
decide_universe
```

Не оставлять независимые hardcoded значения:

```text
timedelta(seconds=5)
timedelta(seconds=180)
```

в runtime-функциях.

Допустимы hardcoded значения только в тестовых fixtures.

## 8.5. Version check

Если caller передал:

```text
quality_policy_version != loaded_policy.version
```

операция должна завершиться fail-closed с `ValueError`.

## 8.6. Tests

Проверить:

```text
valid YAML loads;
missing field rejected;
negative seconds rejected;
float minimum_volume rejected;
version mismatch rejected;
policy действительно влияет на candle grace;
policy действительно влияет на stale OI;
policy действительно влияет на OI lookup max lag.
```

---

# 9. Open Interest history и changes

## 9.1. Владелец зафиксировал

Канонический OI проекта:

```text
oi_base
```

измеряется только в количестве базовой монеты.

```text
BTCUSDT → BTC
ETHUSDT → ETH
SOLUSDT → SOL
```

Долларовый OI запрещено использовать для:

```text
OI changes
Universe eligibility
Features
Scanner
Detector
```

## 9.2. Не использовать exact timestamp для OI

Текущую логику:

```python
x.event_ts == target
```

заменить на:

```text
выбрать последний snapshot, для которого:

snapshot.event_ts <= target
target - snapshot.event_ts <= policy.oi_lookup_max_lag
```

Запрещено:

```text
использовать snapshot после target;
использовать слишком старый snapshot;
смешивать exchange;
смешивать symbol;
смешивать instrument type;
смешивать source unit;
смешивать contract multiplier.
```

## 9.3. Совместимость OI observations

Две OI строки совместимы только когда совпадают:

```text
exchange
symbol
source_unit
instrument_type
contract_multiplier
```

Если одна строка `BASE_ASSET`, а другая `CONTRACTS`, изменение не рассчитывать.

## 9.4. Latest OI freshness

Features и Universe должны учитывать:

```text
as_of - latest_oi.event_ts <= policy.oi_max_age
```

Если OI старый:

```text
oi_base feature = None
OI changes = None
Universe = INACTIVE
reason = STALE_OI
```

## 9.5. Reader cycle

Для расчёта Features не выполнять одновременно:

```text
fetch_latest_open_interest
fetch_open_interest_history
```

Получить историю одним batch query и определить latest snapshot в Python из этой истории.

Таким образом один полный Reader cycle должен использовать:

```text
1 candles query
1 historical OI query
1 funding query
1 liquidation query
```

Максимум:

```text
4 Market DB queries per exchange cycle
```

при доказанных source contracts.

## 9.6. Tests

Добавить:

```text
snapshot ровно на target используется;
snapshot раньше target в пределах max lag используется;
snapshot после target не используется;
snapshot старше max lag не используется;
разные source units не сравниваются;
разные multipliers не сравниваются;
изменение цены при неизменном oi_base даёт OI change = 0;
UNKNOWN OI unit оставляет OI features = None;
stale latest OI оставляет OI features = None.
```

---

# 10. Liquidation availability и deduplication

Файл:

```text
src/paper_engine/market_data/features.py
```

## 10.1. Не определять доступность по непустому списку

Запрещена логика:

```python
Decimal(0) if liquidations else None
```

Добавить явный аргумент:

```python
liquidation_data_available: bool
```

или эквивалентный typed availability object.

Аргумент должен быть обязательным, без default.

Поведение:

```text
liquidation_data_available=False
→ все liquidation features = None.

liquidation_data_available=True и пригодных событий нет
→ все liquidation features = Decimal(0).

liquidation_data_available=True и события есть
→ рассчитать суммы.
```

## 10.2. Фильтрация

Сначала отфильтровать по:

```text
exchange
symbol
event_ts <= as_of
event_ts >= as_of - policy.liquidation_max_age
quality != INVALID
source_updated_at <= as_of
```

Только после этого определять totals.

Наличие событий другого symbol/exchange не должно превращать `None` в zero.

## 10.3. Deduplication conflicts

Для одинакового `deduplication_key`:

```text
same key + полностью одинаковый canonical payload
→ оставить один event.

same key + различающийся payload
→ fail closed.
```

Различающийся payload:

```text
event_ts
side
price
quantity_base
notional_quote
source_event_id
quality
source_updated_at
```

При конфликте:

```python
raise DataQualityConflict(...)
```

Допустимо создать отдельное исключение в `features.py` или `models.py`.

Нельзя молча оставлять последний элемент dictionary.

## 10.4. Tests

Обязательные tests:

```text
empty but available → zero;
unavailable → None;
only other-exchange events → None/zero согласно availability текущего source, но не по общей длине списка;
only future events → zero при доказанно доступном source;
same duplicate payload → counted once;
same key different notional → conflict;
same key different side → conflict;
INVALID event excluded.
```

---

# 11. Feature checksum

Сохранить исправление, при котором checksum включает значения source data.

Дополнительно убедиться, что checksum включает:

```text
exchange
symbol
as_of
feature_version
quality_policy_version

candle identity and OHLCV
candle quality/timestamps

OI source value
OI source unit
oi_base
instrument type
contract multiplier
OI quality/timestamps

funding rate
funding actualness
funding timestamps/quality

liquidation key
side
price
quantity
notional
timestamps/quality
```

Исправить текущую техническую ошибку формирования списка:

Не использовать `list.extend()` для добавления плоской последовательности:

```python
("feature_version", feature_version, ...)
```

Добавить одну детерминированную identity string через `_identity(...)`.

Например:

```python
identities.append(
    _identity(
        "feature_context",
        exchange,
        symbol,
        cutoff.isoformat(),
        feature_version,
        quality_policy_version,
    )
)
```

Tests:

```text
same inputs → same checksum;
same source identity + changed close → changed checksum;
changed OI value → changed checksum;
changed quality policy version → changed checksum;
changed as_of → changed checksum;
input order does not change checksum.
```

---

# 12. Batch Feature calculation

Не создавать новый service или worker.

Добавить в существующий:

```text
src/paper_engine/market_data/features.py
```

одну функцию:

```python
def calculate_feature_batch(
    *,
    exchange: str,
    symbols: Sequence[str],
    as_of: datetime,
    candles: Sequence[CanonicalCandle],
    oi: Sequence[OpenInterestSnapshot],
    funding: Sequence[FundingEvent],
    liquidations: Sequence[LiquidationEvent],
    quality_by_symbol: Mapping[str, DataQualityStatus],
    liquidation_availability_by_symbol: Mapping[str, bool],
    policy: MarketDataQualityPolicy,
    feature_version: str,
) -> list[MarketFeatureSnapshot]:
    ...
```

Названия типов могут быть немного изменены, но функция должна:

1. Один раз сгруппировать batch rows по symbol.
2. Не выполнять SQL.
3. Не делать повторный полный проход по общей коллекции для каждого symbol.
4. Вызвать существующую single-symbol calculation только на уже сгруппированных данных.
5. Вернуть snapshots в детерминированном порядке symbols.
6. Отклонить duplicate symbols в запросе либо однозначно дедуплицировать их.
7. Не смешивать Binance и Bybit.

Запрещено переписывать `calculate_features()` полностью, если его можно переиспользовать.

Tests:

```text
batch result равен single-symbol result;
100 symbols не вызывают SQL;
exchange isolation;
symbol isolation;
deterministic order;
missing quality entry fails closed.
```

---

# 13. TX-01 Universe idempotency

Файл:

```text
migrations/008_stage3_market_data.sql
```

## 13.1. Semantic equality

При одинаковом watermark обновление разрешено только если изменилась semantic projection:

```text
status
reason_codes
quality_policy_version
candles_fresh_at
oi_fresh_at
history_start_at
volume_24h_quote
```

Поле:

```text
updated_at
```

не должно самостоятельно вызывать UPDATE.

Правило:

```text
same watermark
same semantic projection
different updated_at
→ idempotent no-op
→ function returns false
→ stored updated_at не изменяется.
```

## 13.2. New policy

При одинаковом watermark, но новой policy или новом решении:

```text
update allowed;
function returns true;
updated_at обновляется.
```

## 13.3. Stale watermark

```text
incoming watermark < stored watermark
→ no-op;
function returns false;
никакие поля не меняются.
```

## 13.4. Исправить integration test

Правильная последовательность:

```text
first INACTIVE/v1 → true
exact retry с новым updated_at → false
same watermark ACTIVE/v2 → true
stale INACTIVE/v1 → false
final row remains ACTIVE/v2
```

Итоговый assert:

```python
assert row["status"] == "ACTIVE"
assert row["quality_policy_version"] == "v2"
```

Не оставлять текущий ошибочный assert `INACTIVE`.

## 13.5. Concurrency

Добавить PostgreSQL test:

```text
две параллельные одинаковые TX-01 публикации;
одна создаёт/изменяет projection;
вторая получает idempotent no-op;
финальная строка одна.
```

---

# 14. TX-02 immutable publication

## 14.1. Conflict comparison

При существующей identity сравнивать не только checksum, но также:

```text
quality_policy_version
source_cutoff
payload
```

Правило:

```text
same identity + same checksum + same metadata + same payload
→ false / idempotent no-op.

same identity + different checksum
→ conflict.

same identity + same checksum, но different payload/metadata
→ conflict.
```

Это защищает от ошибки producer-а, который передал неправильный checksum.

## 14.2. Batch publication

Создать минимальный файл:

```text
src/paper_engine/market_data/publication.py
```

Добавить только:

```python
class Stage3PublicationRepository:
    async def publish_universe_batch(...)
    async def publish_feature_batch(...)
```

Требования:

```text
отдельный Paper DB pool;
никаких Market DB credentials;
одна transaction на batch;
никакого commit на каждый symbol;
никаких financial imports;
никаких account/trade writes.
```

Допустимо использовать один SQL statement с:

```text
jsonb_to_recordset
```

который вызывает существующую publication function для каждой строки.

Не добавлять новый ORM.

## 14.3. Batch rollback

Если один TX-02 элемент имеет conflict:

```text
весь batch rollback;
новые элементы этого batch не остаются в БД.
```

## 14.4. Tests

Добавить PostgreSQL integration tests:

```text
batch из двух новых features → обе созданы;
точный retry → обе idempotent;
один conflict в batch → весь batch rollback;
UPDATE/DELETE market_features запрещены;
неправильный writer role не может публиковать;
concurrent same identity → одна строка.
```

---

# 15. Startup permission gate

Сохранить обязательный вызов:

```python
await reader.startup()
```

до первого business query.

Дополнить audit:

```text
current_user совпадает с expected role name;
transaction_read_only = on;
default_transaction_read_only = on;
timezone = UTC;
role not superuser;
role cannot create DB;
role cannot create role;
role cannot replicate;
role cannot bypass RLS;
schema public: USAGE allowed;
schema public: CREATE denied;
required tables: SELECT allowed;
required tables: INSERT/UPDATE/DELETE/TRUNCATE denied where check supported.
```

В Reader constructor добавить:

```python
expected_role_name: str
```

или получить его из `MarketDataSettings`.

Production expected role:

```text
paper_market_reader
```

Disposable tests используют отдельное явно указанное имя.

Не hardcode disposable role в runtime.

`startup()` должен устанавливать `_startup_complete=True` только после полного успешного audit.

При failed audit:

```text
_startup_complete остаётся False.
```

Tests:

```text
query before startup rejected;
failed startup does not unlock queries;
wrong current_user rejected;
schema CREATE privilege rejected;
missing SELECT rejected;
unexpected INSERT rejected;
successful startup unlocks query.
```

---

# 16. Настоящий 24-hour load test

Файл:

```text
tests/load/test_stage3_market_reader_load.py
```

## 16.1. Исправить измеряемое окно

Сейчас fixture содержит 24 часа, но Reader читает только две минуты.

В measured cycle использовать:

```python
fetch_candles(
    exchange,
    symbols,
    HISTORY_START,
    END,
    AS_OF,
    policy.version,
)
```

Не использовать `START` как начало candle query.

Historical OI также читать за полный необходимый период:

```python
fetch_open_interest_history(
    exchange,
    symbols,
    HISTORY_START,
    END,
    AS_OF,
    policy.version,
)
```

## 16.2. Полный измеряемый cycle

Measured cycle должен включать:

```text
Reader startup — отдельно, до warm-up;
fetch candles;
fetch historical OI;
fetch funding;
fetch liquidations при PROVEN disposable contract;
grouping;
calculate_feature_batch;
checksum generation.
```

Не включать fixture creation в latency цикла.

Не вызывать `fetch_latest_open_interest`.

## 16.3. Query budget

Ожидается:

```text
4 Market DB queries per exchange cycle
0 Paper DB queries в Reader+Features benchmark
```

Отдельно разрешено провести publication benchmark, но не смешивать его с Reader benchmark.

## 16.4. Fixture

Для каждого symbol создать:

```text
1-minute candles: минимум полные 24 часа;
OI snapshots: каждые 5 минут за 24 часа;
funding rows;
liquidation rows с canonical disposable contract;
explicit exchange;
indexes, соответствующие Reader predicates.
```

Для 1 000 symbols ожидаемый candle result порядка:

```text
1 440 000 rows
```

Не заявлять 24-hour benchmark, если Reader вернул около 2 000 candle rows.

## 16.5. Assertions

Test должен проверять:

```text
candle row count соответствует 24h × symbols;
OI history row count соответствует fixture;
feature snapshot count = symbols;
query count = 4;
feature symbols unique;
нет N+1;
нет Paper DB query;
все snapshots имеют один as_of;
все snapshots имеют policy.version;
work completes without OOM.
```

## 16.6. Matrix

Выполнить:

```text
100 symbols
500 symbols
1000 symbols
```

Для каждого:

```text
3 warm-up cycles
20 measured cycles
p50
p95
max
rows read
rows returned
feature count
query count
peak RSS
Python allocation peak
```

Если полный matrix объективно не укладывается в ресурсы disposable host:

```text
не уменьшать объём тихо;
остановиться;
сообщить фактический предел и memory evidence;
не публиковать выдуманный результат.
```

## 16.7. EXPLAIN

EXPLAIN должен использовать те же predicates, что реальный Reader:

```text
candle close+grace cutoff;
historical OI query;
funding query;
liquidation query.
```

Не использовать упрощённые SQL версии без production predicates.

Production TimescaleDB capacity не заявлять.

---

# 17. Physical source audit

Дополнить только документацию. `monitor-data` не изменять.

В:

```text
docs/market_data/SOURCE_SCHEMA_AUDIT.md
```

точно записать:

## Binance candles

```text
WebSocket:
x=true проверяется;
ts записывается из k["T"];
это close timestamp.

REST:
ts записывается из k[0];
это open timestamp;
закрытость последней REST candle не проверяется.
```

## Bybit candles

```text
ts выбирается из timestamp с fallback на start;
confirm не проверяется;
незакрытая candle может попасть в buffer.
```

Не писать, что Bybit collector mapping «не был доступен»: он доступен для read-only review.

## Вывод

```text
Physical candles_1m timestamp contract is mixed/unproven.
Paper engine must fail closed.
Owner approval is required for a separate monitor-data remediation task.
```

Отдельно сохранить open issues:

```text
OI unit/multiplier;
funding actualness;
liquidation quantity/currency;
ingestion/update timestamps;
instrument metadata;
production keys/indexes;
Timescale plans;
duplicates/gaps/freshness.
```

---

# 18. Отдельное действие владельца по monitor-data

Текущий агент не должен менять `monitor-data`.

В финальном отчёте он должен подготовить отдельный запрос владельцу:

```text
OWNER ACTION REQUIRED — SOURCE PRODUCER CONTRACT
```

В запросе перечислить минимальное будущее исправление collector-а:

```text
Binance WebSocket candle:
использовать единый open timestamp;
сохранять только x=true.

Binance REST candle:
использовать open timestamp;
проверять закрытость по close timestamp;
не сохранять текущую незакрытую candle.

Bybit candle:
использовать start;
сохранять только confirm=true.

Добавить или доказать:
ingested_at;
source_updated_at;
source path/version;
OI unit;
instrument type;
contract multiplier;
actual funding identity;
liquidation units/side semantics.
```

Это только предложение.

Не выполнять эти изменения в текущем задании.

---

# 19. Документация

Синхронизировать:

```text
CURRENT_STATE.md
TODO.md
HANDOFF.md
README.md

docs/stages/STAGE_03_REPORT.md
docs/stages/STAGE_03_EVIDENCE.md
docs/stages/STAGE_03_OPEN_ISSUES.md

docs/market_data/SOURCE_SCHEMA_AUDIT.md
docs/market_data/SOURCE_MAPPING.md
docs/market_data/TIMESTAMP_CONTRACT.md
docs/market_data/FEATURE_CONTRACT.md
docs/market_data/STAGE_03_PERFORMANCE_REPORT.md
```

Удалить устаревшие утверждения:

```text
remote SHA всё ещё c06a763...
remediation не pushed
full suite 88 passed
load evidence pending
24h benchmark читает 24h, если запрос читает только 2 минуты
```

До нового push статус документов должен быть:

```text
Published audit SHA:
95fdcecd1c2330bf5e452386722b3d30f8d9d48e

Current remediation:
completed locally, not published

Independent verdict:
REJECT

Next:
independent re-audit after owner-authorized push
```

Не встраивать новый локальный final SHA внутрь commit-содержимого, создавая self-reference.

Новый локальный SHA сообщить только в финальном ответе агента.

---

# 20. Обязательные тесты

## Unit

```text
Source contract fail-closed tests
Reader timestamp validation
Quality policy loading/version
OI max-lag lookup
OI compatibility
STALE_OI
Liquidation availability
Liquidation duplicate conflict
Feature checksum values
Batch Features
Architecture imports
Protocol parity
```

## PostgreSQL integration

```text
Reader closed-candle SQL
Historical OI Reader
Reader startup permissions
TX-01 semantic idempotency
TX-01 stale protection
TX-01 policy change
TX-01 concurrency
TX-02 idempotency
TX-02 payload conflict
TX-02 immutable trigger
TX-02 batch rollback
Writer isolation
Migration public revokes
Migration clean apply
Migration idempotent rerun
```

## Load

```text
Actual 24-hour query window
Historical OI
Full batch Feature calculation
100/500/1000 symbols
Constant query count
Memory evidence
Exact Reader SQL EXPLAIN
```

---

# 21. Запуск проверок

Выполнить project-standard environment setup.

Затем минимум:

```bash
pytest -q

pytest -q tests/unit/test_market_data.py
pytest -q tests/unit/test_market_data_semantics.py
pytest -q tests/unit/test_features_correctness.py
pytest -q tests/unit/test_reader_startup.py
pytest -q tests/unit/test_market_data_architecture.py

pytest -q tests/integration/test_stage3_reader.py
pytest -q tests/integration/test_stage3_oi_reader.py
pytest -q tests/integration/test_stage3_publication.py
pytest -q tests/integration/test_stage3_permissions.py

pytest -q tests/load/test_stage3_market_reader_load.py -s

ruff check .
ruff format --check .
mypy src
python -m compileall -q src
git diff --check
```

Также выполнить:

```text
project-standard gitleaks scan;
AST/static float scan;
clean migrations 001–008;
second migration run;
permission role cleanup;
disposable database cleanup.
```

Нельзя засчитывать skipped DB tests как passed.

Финальный отчёт должен разделять:

```text
passed
skipped
not executed
failed
```

Для каждого skipped test указать точную причину.

---

# 22. Evidence

В `STAGE_03_EVIDENCE.md` записать:

```text
Git base;
published pre-remediation SHA;
локальный remediation выполнялся без push;

полные test counts;
точные skipped tests;

migration apply/rerun;
TX-01 results;
TX-02 results;
permission results;

actual 24h row counts;
query counts;
feature counts;
p50/p95/max;
RSS/allocation;
EXPLAIN nodes;

gitleaks;
ruff;
mypy;
compileall;
git diff --check;

monitor-data BEFORE/AFTER:
branch;
HEAD;
tracked tree hash;
tracked diff hash;
status.
```

Не писать секреты, DSN или passwords.

---

# 23. Git после исправлений

Проверить список изменённых файлов:

```bash
git diff --name-only 95fdcecd1c2330bf5e452386722b3d30f8d9d48e
git diff --stat 95fdcecd1c2330bf5e452386722b3d30f8d9d48e
git diff --check
git status --short
```

Убедиться, что нет файлов вне разрешённого scope.

Не использовать:

```bash
git add .
git add -A
```

Добавлять только конкретные проверенные файлы:

```bash
git add <exact-file-1> <exact-file-2> ...
```

Затем amend единственного Stage 3 commit:

```bash
git commit --amend --no-edit
```

После amend:

```bash
git status --short
git rev-parse HEAD
git log --oneline --decorate -3
git diff ee72737406461df90980c51063fce297d7faa0be...HEAD --stat
```

Ожидается:

```text
один Stage 3 commit поверх Base;
worktree clean;
новый локальный SHA;
remote остаётся на 95fdcecd...
```

---

# 24. Push запрещён

После исправления не выполнять push.

Запрещено:

```bash
git push
git push --force
git push --force-with-lease
```

В финальном отчёте запросить отдельное разрешение владельца на:

```bash
git push --force-with-lease origin stage/03-market-data
```

До разрешения:

```text
local SHA != remote SHA
```

допустимо и ожидаемо.

---

# 25. Stop conditions

Немедленно остановиться и сообщить владельцу, если:

```text
требуется изменение monitor-data;
требуется production Market DB DDL/DML;
требуется изменение paper_market_reader;
требуется новый production index;
требуется изменение migrations 001–007;
требуется изменение Stage 4+ кода;
не удаётся доказать OI unit;
не удаётся выполнить настоящий 24h load test;
полный DB suite падает;
найден секрет;
обнаружены чужие изменения в worktree;
изменился origin/main или Base SHA;
для исправления требуется более трёх новых runtime-файлов.
```

Не обходить blocker временной заглушкой или предположением.

---

# 26. Критерии готовности к повторному аудиту

Работа считается готовой только когда одновременно выполнено:

```text
Reader rejects unproven candle semantics;
Reader rejects unproven liquidation semantics;
Reader validates timezone-aware windows;
historical OI is in Protocol;
OI target lookup uses <= target + max lag;
STALE_OI works from runtime policy;
liquidation availability is explicit;
conflicting duplicates fail closed;
checksum includes values and context;
batch Features implemented;
TX-01 exact retry is no-op even with new updated_at;
TX-01 integration final state is ACTIVE/v2;
TX-02 payload conflicts fail closed;
batch TX-02 rollback proven;
startup audit checks expected role and schema CREATE;
actual 24h benchmark reads actual 24h rows;
full Feature cycle included in benchmark;
query count is bounded;
docs match the real state;
full tests and DB tests pass;
worktree clean;
one Stage 3 commit;
no push performed.
```

Production activation не считается доказанной, пока владелец отдельно не утвердит source producer contracts.

---

# 27. Финальный отчёт агента

Формат ответа:

```text
STAGE 3 REMEDIATION — READY FOR INDEPENDENT RE-AUDIT

1. Git
- Base SHA
- Published pre-remediation SHA
- New local SHA
- Remote SHA
- Commit count
- Worktree status

2. Files
- Modified files
- New files
- Confirmation that no files outside scope changed

3. Closed audit findings
- One line for every finding
- File/function/test evidence

4. Source contracts
- Binance candle status
- Bybit candle status
- Binance/Bybit OI status
- Funding status
- Liquidation status
- Explicit fail-closed behavior

5. Tests
- Full suite
- Unit
- Integration
- Permission
- Publication
- Load
- Skipped tests and reasons

6. 24h performance
- Actual query window
- Actual candle rows
- Actual OI rows
- Feature snapshots
- Query count
- p50/p95/max
- memory
- EXPLAIN

7. Database
- Migration clean apply
- Idempotent rerun
- TX-01
- TX-02
- PUBLIC revokes
- Disposable cleanup

8. Isolation
- monitor-data BEFORE/AFTER
- Production Market DB unchanged
- paper_market_reader unchanged
- main unchanged
- no PR
- no merge
- no push

9. Open owner actions
- Source producer timestamp contract
- OI unit/multiplier
- Funding semantics
- Liquidation semantics
- Timescale grants/indexes

10. Status
READY FOR INDEPENDENT RE-AUDIT
NOT PASS
NOT MERGED
NOT PUSHED
```

Самостоятельно объявлять `PASS` запрещено.
