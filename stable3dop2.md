# Техническое задание

## Stage 3 Market Data Layer — Correctness Remediation 3

---

# 0. Исходная точка

```text
Repository: shamilmirz/paper-trading-engine
Branch: stage/03-market-data

Base SHA:
ee72737406461df90980c51063fce297d7faa0be

Published remediation SHA:
8459f4157aa87495df306f11ebfcd124bfac07f3

Current independent verdict:
REJECT
```

Основные оставшиеся дефекты:

```text
1. OI changes 5m/30m/2h не работают с текущей freshness policy.
2. oi_lookup_max_lag загружается, но не используется.
3. funding_feature_max_age не применяется.
4. candle_max_age не применяется.
5. liquidation_data_available остаётся необязательным.
6. Feature serializer обращается к __dict__ у slots dataclass.
7. Publication batch выполняет N SQL-запросов для N символов.
8. Stage3PublicationRepository не покрыт реальными integration tests.
9. PyYAML не указан в зависимостях.
10. Quality policy не подключена через штатный construction path.
11. Load test недостаточно проверяет correctness.
12. EXPLAIN не соответствует реальным Reader queries.
13. Документация не соответствует опубликованному Git-состоянию.
14. Performance acceptance остаётся заблокированным.
15. Production source contracts остаются недоказанными.
```

---

# 1. Цель работы

Исправить только перечисленные дефекты.

Не переписывать весь Market Data Layer.

После работы ожидается:

```text
Correctness remediation completed locally.
Correctness tests passed.
Publication repository tested.
Load diagnostic prepared.
Performance acceptance still handled separately if full matrix remains blocked.

Status:
READY FOR INDEPENDENT CORRECTNESS RE-AUDIT
NOT PASS
NOT MERGED
NOT PUSHED
```

Агент не имеет права самостоятельно объявлять Stage 3 `PASS`.

---

# 2. Главный принцип

Перед каждым изменением агент обязан определить:

```text
Какой конкретный пункт независимого аудита закрывает это изменение?
```

Если изменение не закрывает конкретный пункт — не выполнять его.

Запрещены:

```text
общий рефакторинг;
переименование всех моделей;
перенос пакетов;
новый framework;
новый ORM;
новая service architecture;
переписывание Stage 1–2;
оптимизация без profiling;
изменение producer-кода monitor-data.
```

---

# 3. Git baseline

Перед изменениями выполнить:

```bash
git fetch origin
git checkout stage/03-market-data
git status --short
git rev-parse HEAD
git rev-parse origin/stage/03-market-data
git merge-base HEAD origin/main
git log --oneline --decorate -4
```

Ожидается:

```text
HEAD:
8459f4157aa87495df306f11ebfcd124bfac07f3

origin/stage/03-market-data:
8459f4157aa87495df306f11ebfcd124bfac07f3

merge-base:
ee72737406461df90980c51063fce297d7faa0be

worktree:
clean
```

При несовпадении:

```text
STOP — GIT BASELINE MISMATCH
```

Не выполнять reset, rebase или удаление чужих изменений.

---

# 4. Разрешённые runtime-файлы

Основные изменения разрешены только в:

```text
pyproject.toml

src/paper_engine/common/config.py

src/paper_engine/market_data/features.py
src/paper_engine/market_data/policy.py
src/paper_engine/market_data/postgres_reader.py
src/paper_engine/market_data/publication.py
src/paper_engine/market_data/reader.py
src/paper_engine/market_data/universe.py
```

Допустимы точечные изменения в:

```text
src/paper_engine/market_data/source_contracts.py
src/paper_engine/domain/market_data/models.py
migrations/008_stage3_market_data.sql
```

Но только при наличии конкретного failing test.

Без failing test не изменять:

```text
source_contracts.py
models.py
migration 008
```

---

# 5. Разрешённые тестовые файлы

Изменять:

```text
tests/unit/test_features_correctness.py
tests/unit/test_market_data.py
tests/unit/test_market_data_semantics.py
tests/unit/test_reader_startup.py
tests/unit/test_market_data_architecture.py

tests/integration/test_stage3_reader.py
tests/integration/test_stage3_oi_reader.py
tests/integration/test_stage3_publication.py
tests/integration/test_stage3_permissions.py

tests/load/test_stage3_market_reader_load.py
```

Разрешено создать максимум два новых тестовых файла:

```text
tests/unit/test_stage3_feature_policy.py
tests/integration/test_stage3_publication_repository.py
```

Другие новые test-файлы не создавать без объяснения.

---

# 6. Категорически запрещено

Не изменять:

```text
monitor-data;
production Market DB;
production TimescaleDB;
paper_market_reader;
production roles/grants;
migrations 001–007;
accounting;
ledger;
accounts;
trades;
scanner;
detector;
signals;
levels;
growth state;
dashboard;
Docker;
scheduler;
runtime services;
main.
```

Не выполнять:

```text
git push;
git push --force;
git push --force-with-lease;
git merge;
git rebase;
создание PR;
изменение main;
production DDL;
production DML;
production restart;
Stage 4.
```

---

# 7. Шаг 1 — исправить OI freshness и historical lookup

Файл:

```text
src/paper_engine/market_data/features.py
```

## 7.1. Текущая ошибка

Сейчас к каждому OI snapshot применяется:

```python
cutoff - snapshot.event_ts <= policy.oi_max_age
```

Это удаляет историю старше трёх минут.

После этого невозможно рассчитать:

```text
oi_change_5m
oi_change_30m
oi_change_2h
```

Также сейчас используется точное равенство:

```python
snapshot.event_ts == target
```

Это неверно для OI snapshots, timestamp которых не обязан лежать на точной минутной сетке.

## 7.2. Требуемая логика

Разделить две операции:

### Latest OI

Latest OI определяется как последний пригодный snapshot:

```text
snapshot.event_ts <= as_of
quality != INVALID
source_updated_at отсутствует или <= as_of
oi_base != None
```

После выбора latest отдельно проверить freshness:

```text
as_of - latest.event_ts <= policy.oi_max_age
```

Если latest OI устарел:

```text
latest_oi = None
oi_base = None
oi_quote = None
все oi_changes = None
```

### Historical OI

Исторические OI snapshots не фильтровать через `oi_max_age`.

Для каждого target:

```text
target = latest_oi.event_ts - window
```

выбрать последний snapshot, удовлетворяющий:

```text
snapshot.event_ts <= target
target - snapshot.event_ts <= policy.oi_lookup_max_lag
```

Нельзя выбирать snapshot после target.

## 7.3. Compatibility

Latest и historical snapshot совместимы только при совпадении:

```text
exchange
symbol
source_unit
instrument_type
contract_multiplier
```

Дополнительно:

```text
оба oi_base != None
оба quality != INVALID
```

## 7.4. Требуемый helper

Добавить небольшой приватный helper:

```python
def _find_oi_at_or_before(
    observations: Sequence[OpenInterestSnapshot],
    *,
    target: datetime,
    latest: OpenInterestSnapshot,
    max_lag: timedelta,
) -> OpenInterestSnapshot | None:
    ...
```

Не создавать новый класс или новый module.

## 7.5. Ожидаемое поведение

```text
snapshot ровно на target:
используется.

snapshot за 30 секунд до target при max_lag=90:
используется.

snapshot за 91 секунду до target:
не используется.

snapshot после target:
не используется.

другой multiplier:
не используется.

другая source unit:
не используется.
```

## 7.6. Обязательные тесты

Добавить:

```text
test_oi_change_5m_uses_snapshot_at_target
test_oi_change_uses_snapshot_before_target_within_lag
test_oi_change_rejects_snapshot_after_target
test_oi_change_rejects_snapshot_outside_max_lag
test_oi_change_rejects_different_source_unit
test_oi_change_rejects_different_multiplier
test_oi_change_constant_base_quantity_is_zero
test_latest_oi_stale_makes_all_oi_features_none
test_historical_oi_is_not_removed_by_latest_freshness
```

Обязательно проверить:

```text
5m
30m
2h
```

Не ограничиваться только `5m`.

---

# 8. Шаг 2 — применить candle freshness policy

Файл:

```text
src/paper_engine/market_data/features.py
```

## 8.1. Требование

После выбора последней закрытой свечи проверить:

```text
as_of - latest.close_ts <= policy.candle_max_age
```

Если latest candle старше допустимого возраста:

```text
price = None
price_changes = None
volume features = None
volatility = None
```

Не использовать старую свечу как текущую цену.

## 8.2. Data quality

Не вводить новый enum.

Использовать существующий `DataQualityStatus`.

Правило:

```text
incoming quality = INVALID:
output remains INVALID.

incoming quality = COMPLETE,
но candle stale:
output quality = PARTIAL.

incoming quality = PARTIAL:
output remains PARTIAL.
```

Добавить небольшой helper для объединения статуса только при необходимости.

Не переписывать весь quality subsystem.

## 8.3. Тесты

```text
test_fresh_latest_candle_produces_price
test_stale_latest_candle_nulls_price_features
test_stale_latest_candle_marks_complete_input_partial
test_invalid_quality_remains_invalid
```

---

# 9. Шаг 3 — применить funding freshness policy

Файл:

```text
src/paper_engine/market_data/features.py
```

Funding event пригоден только если:

```text
is_actual_funding_event = True
exchange совпадает
symbol совпадает
funding_event_ts <= as_of
quality != INVALID
source_updated_at отсутствует или <= as_of
as_of - funding_event_ts <= policy.funding_feature_max_age
```

Если funding устарел:

```text
funding_rate = None
funding_event_ts = None
funding_age = None
```

Не возвращать timestamp устаревшего funding вместе с `rate=None`.

Обязательные тесты:

```text
test_actual_funding_inside_max_age_is_used
test_actual_funding_outside_max_age_is_none
test_observational_funding_is_none
test_future_funding_is_none
test_invalid_funding_is_none
```

---

# 10. Шаг 4 — сделать liquidation availability обязательным

Файл:

```text
src/paper_engine/market_data/features.py
```

## 10.1. Удалить fallback

Запрещено:

```python
liquidation_data_available: bool | None = None
```

Запрещено:

```python
availability = bool(liquidations)
```

Новая сигнатура должна требовать:

```python
liquidation_data_available: bool
```

без default.

Все callers обязаны передать значение явно.

## 10.2. Поведение

```text
liquidation_data_available=False:
все liquidation totals = None.

liquidation_data_available=True,
пригодных событий нет:
все liquidation totals = Decimal(0).

liquidation_data_available=True,
есть пригодные события:
суммировать пригодные события.
```

Общий непустой список другой биржи или другого symbol не должен влиять на availability текущего symbol.

## 10.3. Filtering

До deduplication фильтровать:

```text
exchange
symbol
event_ts <= as_of
as_of - event_ts <= policy.liquidation_max_age
quality != INVALID
source_updated_at отсутствует или <= as_of
```

## 10.4. Deduplication

Сохранить fail-closed conflict:

```text
same key + same canonical payload:
один event.

same key + different payload:
DataQualityConflict.
```

Проверяемый payload:

```text
event_ts
liquidated_position_side
price
quantity_base
notional_quote
source_event_id
quality
source_updated_at
```

## 10.5. Тесты

```text
test_liquidation_unavailable_returns_none
test_available_empty_liquidations_returns_zero
test_other_symbol_events_do_not_define_availability
test_other_exchange_events_do_not_define_availability
test_future_event_not_counted
test_stale_event_not_counted
test_duplicate_same_payload_counted_once
test_duplicate_conflicting_notional_fails
test_duplicate_conflicting_side_fails
```

---

# 11. Шаг 5 — исправить Feature serializer

Файл:

```text
src/paper_engine/market_data/publication.py
```

## 11.1. Ошибка

`MarketFeatureSnapshot` использует:

```python
@dataclass(frozen=True, slots=True)
```

Поэтому запрещено:

```python
snapshot.__dict__
```

## 11.2. Требуемое решение

Добавить явный serializer:

```python
def serialize_feature_snapshot(
    snapshot: MarketFeatureSnapshot,
) -> dict[str, object]:
    ...
```

Не использовать бесконтрольный `default=str` как основной контракт.

Явно преобразовать:

```text
datetime → UTC ISO-8601
Decimal → string
DataQualityStatus → enum.value
tuple pairs → JSON object либо детерминированный list
None → null
```

Рекомендованный payload:

```python
{
    "exchange": snapshot.exchange,
    "symbol": snapshot.symbol,
    "as_of": snapshot.as_of.isoformat(),
    "feature_version": snapshot.feature_version,
    "quality_policy_version": snapshot.quality_policy_version,
    "source_cutoff": snapshot.source_cutoff.isoformat(),
    "source_checksum": snapshot.source_checksum,
    "price": decimal_or_none(snapshot.price),
    "price_changes": dict_of_decimal_strings(snapshot.price_changes),
    "oi_base": decimal_or_none(snapshot.oi_base),
    "oi_quote": decimal_or_none(snapshot.oi_quote),
    "oi_changes": dict_of_decimal_strings(snapshot.oi_changes),
    ...
}
```

Не включать в payload:

```text
Python class names;
memory addresses;
repr objects;
нестабильный tuple repr.
```

## 11.3. Determinism

Два одинаковых snapshots должны давать байт-в-байт одинаковый JSON после:

```python
json.dumps(payload, sort_keys=True, separators=(",", ":"))
```

## 11.4. Тесты

```text
test_slots_feature_snapshot_serializes
test_feature_payload_contains_no_float
test_feature_payload_decimal_is_string
test_feature_payload_datetime_is_utc_iso
test_feature_payload_is_deterministic
```

---

# 12. Шаг 6 — настоящая batch publication без N+1

Файл:

```text
src/paper_engine/market_data/publication.py
```

## 12.1. Запрещённая реализация

Нельзя выполнять:

```python
for item in items:
    await connection.fetchval(...)
```

Для 1000 symbols это 1000 Paper DB queries.

## 12.2. Требуемая реализация

Один batch должен выполнять:

```text
одна transaction;
один SQL call;
N logical calls к существующей SQL publication function внутри PostgreSQL.
```

Не обязательно создавать новую migration function.

Использовать один JSON argument и `jsonb_to_recordset`.

### Feature batch

Пример логики:

```sql
WITH input AS (
    SELECT *
    FROM jsonb_to_recordset($1::jsonb) AS row(
        ordinal integer,
        exchange text,
        symbol text,
        as_of timestamptz,
        feature_version text,
        quality_policy_version text,
        source_cutoff timestamptz,
        source_checksum text,
        payload jsonb
    )
)
SELECT
    ordinal,
    public.publish_market_feature(
        exchange,
        symbol,
        as_of,
        feature_version,
        quality_policy_version,
        source_cutoff,
        source_checksum,
        payload
    ) AS was_created
FROM input
ORDER BY ordinal;
```

### Universe batch

Аналогично:

```sql
jsonb_to_recordset
+
public.publish_market_universe(...)
```

Добавлять `ordinal`, чтобы результаты возвращались в исходном порядке.

## 12.3. Query count

Для каждого метода:

```text
publish_feature_batch:
1 Paper DB query.

publish_universe_batch:
1 Paper DB query.
```

Transaction control statements в query count не считать business queries, но connection-level test должен подтвердить один `fetch()`.

## 12.4. Empty batch

Пустой batch:

```text
не открывает transaction;
не выполняет SQL;
возвращает [].
```

## 12.5. Atomic rollback

Если один feature конфликтует:

```text
весь batch должен rollback;
ни одна новая строка из batch не остаётся.
```

Исключение не перехватывать и не превращать в частичный result.

## 12.6. Universe input

`publish_universe_batch()` должен принимать:

```text
UniverseDecision
```

или строго typed DTO.

Не требовать от caller вручную создавать произвольный dict.

Если сохраняется поддержка dict, она должна быть только внутренним adapter-ом и иметь validation.

## 12.7. Тесты уровня repository

Создать:

```text
tests/integration/test_stage3_publication_repository.py
```

Обязательные tests:

```text
test_feature_repository_publishes_two_rows
test_feature_repository_exact_retry_is_idempotent
test_feature_repository_conflict_rolls_back_entire_batch
test_feature_repository_accepts_slots_snapshot
test_feature_repository_preserves_input_order
test_universe_repository_publishes_batch
test_universe_repository_exact_retry_is_idempotent
test_empty_batch_executes_no_query
```

Дополнительно unit fake/spy test:

```text
test_feature_batch_uses_one_business_query
test_universe_batch_uses_one_business_query
```

Прямые тесты SQL-функций сохранить. Repository tests добавляются поверх них.

---

# 13. Шаг 7 — TX-01/TX-02 migration

Файл:

```text
migrations/008_stage3_market_data.sql
```

Текущие scalar functions в целом сохранить.

Не изменять migration ради batch publication, если repository может использовать:

```text
jsonb_to_recordset
+
существующие scalar functions.
```

Migration изменять только при failing integration test.

Обязательно повторно доказать:

```text
TX-01 exact semantic retry → false.
TX-01 same watermark + changed policy/decision → true.
TX-01 stale watermark → false.
TX-02 exact retry → false.
TX-02 changed checksum → exception.
TX-02 same checksum + changed payload → exception.
TX-02 same checksum + changed cutoff → exception.
TX-02 same checksum + changed policy → exception.
market_features UPDATE/DELETE → exception.
PUBLIC execute remains revoked.
```

---

# 14. Шаг 8 — подключить PyYAML как зависимость

Файл:

```text
pyproject.toml
```

Добавить runtime dependency:

```toml
"PyYAML>=6.0,<7"
```

Не помещать PyYAML только в test dependencies.

После изменения проверить чистую установку:

```bash
python -m venv /tmp/stage3-clean-venv
/tmp/stage3-clean-venv/bin/pip install .
/tmp/stage3-clean-venv/bin/python -c "
from pathlib import Path
from paper_engine.market_data.policy import load_quality_policy
p = load_quality_policy(Path('configs/services/stage3-quality-policy.yaml'))
print(p.version)
"
```

Ожидается:

```text
1
```

После проверки удалить:

```bash
rm -rf /tmp/stage3-clean-venv
```

---

# 15. Шаг 9 — подключить policy через штатный construction path

Сейчас policy создаётся вручную в тестах.

Добавить в:

```text
src/paper_engine/market_data/postgres_reader.py
```

небольшую factory function:

```python
def build_postgres_market_data_reader(
    *,
    pool: object,
    settings: MarketDataSettings,
    source_contracts: Mapping[str, ExchangeSourceContract] | None = None,
) -> PostgresMarketDataReader:
    ...
```

Factory должна:

```text
прочитать settings.market_data_quality_policy_path;
вызвать load_quality_policy();
передать policy в Reader;
передать statement timeout;
передать lock timeout;
передать application name;
передать query budget;
передать expected role name.
```

В `MarketDataSettings` добавить:

```python
market_database_expected_role_name: str = "paper_market_reader"
```

## 15.1. Policy обязательна

Для production construction path policy обязательна.

Убрать из Reader скрытый runtime fallback:

```python
timedelta(seconds=5)
```

Reader должен получать grace только из policy.

Допускается прямой constructor в unit tests, но policy там тоже должна передаваться явно.

## 15.2. Feature functions

`calculate_features()` должен требовать policy явно.

Запрещено:

```python
policy: MarketDataQualityPolicy | None = None
```

Нужно:

```python
policy: MarketDataQualityPolicy
```

без default.

Убрать fallback:

```text
oi_max_age = timedelta.max
liquidation_max_age = timedelta.max
```

## 15.3. Universe

`decide_universe()` должен получать policy явно.

Не хранить одновременно два источника истины:

```text
policy.oi_max_age
и отдельный oi_max_age argument;

policy.minimum_volume_24h_quote
и отдельный min_volume argument.
```

Оставить policy как источник этих значений.

Не переписывать всю Universe модель.

## 15.4. Tests

```text
test_reader_factory_loads_policy_from_settings
test_reader_factory_sets_expected_role
test_reader_rejects_policy_version_mismatch
test_features_require_policy
test_universe_requires_policy
test_clean_install_can_load_yaml_policy
```

---

# 16. Шаг 10 — усилить checksum tests

Существующую checksum implementation полностью не переписывать.

Добавить проверки:

```text
same inputs → same checksum;
input order changes → same checksum;
changed candle close → different checksum;
changed candle volume → different checksum;
changed OI source_value → different checksum;
changed oi_base → different checksum;
changed funding rate → different checksum;
changed liquidation notional → different checksum;
changed quality policy version → different checksum;
changed as_of → different checksum.
```

Обязательно проверить, что checksum context включает:

```text
exchange
symbol
as_of
feature_version
quality_policy_version
```

---

# 17. Шаг 11 — исправить load correctness assertions

Файл:

```text
tests/load/test_stage3_market_reader_load.py
```

Performance optimization пока не выполнять.

Сначала сделать load test корректным.

## 17.1. Fixture OI alignment

OI snapshots должны быть выровнены так, чтобы:

```text
latest OI был fresh;
5m target существовал;
30m target существовал;
2h target существовал.
```

Рекомендованная сетка:

```text
HISTORY_START + 4 minutes
до
END - 1 minute
с шагом 5 minutes
```

Это даёт:

```text
288 OI snapshots на symbol;
latest snapshot = END - 1 minute;
latest OI age относительно AS_OF = около 65 секунд.
```

Не ослаблять `oi_max_age` только ради прохождения теста.

## 17.2. Actual expected rows

Для каждого symbol ожидать:

```text
candles:
1440

OI:
288

funding:
1

liquidations:
0 либо документированное fixture count
```

Обязательные assertions:

```python
assert len(candles) == 1440 * len(symbols)
assert len(oi) == 288 * len(symbols)
assert len(funding) == len(symbols)
assert len(snapshots) == len(symbols)
```

## 17.3. Feature correctness

Для каждого snapshot проверить:

```text
symbol unique;
exchange = binance;
as_of одинаковый;
quality_policy_version = stage3-load;
price not None;
volume_24h_quote not None;
oi_base not None;
oi_change_5m == 0;
oi_change_30m == 0;
oi_change_2h == 0;
liquidation totals = 0 при available=True;
```

Не проверять только количество запросов.

## 17.4. Query count

Full Reader + Feature cycle:

```text
4 Market DB queries;
0 Paper DB queries.
```

Использовать:

```text
candles;
historical OI;
funding;
liquidations.
```

Не вызывать `fetch_latest_open_interest`.

## 17.5. Result report

Перенести в итоговый report:

```text
feature_count;
feature_symbols_unique;
snapshot_policy_versions;
candle_rows;
oi_rows;
funding_rows;
liquidation_rows;
```

---

# 18. Шаг 12 — исправить EXPLAIN

EXPLAIN должен использовать реальные SQL predicates Reader.

## Candle EXPLAIN

Обязательно:

```sql
exchange = $1
symbol = ANY($2)
ts >= HISTORY_START
ts < END
ts + interval '1 minute' + grace <= AS_OF
```

## OI EXPLAIN

Использовать historical query:

```sql
SELECT ts, symbol, ...
FROM oi_snapshots
WHERE exchange = ...
  AND symbol = ANY(...)
  AND ts >= HISTORY_START
  AND ts < END
  AND ts <= AS_OF
ORDER BY symbol, ts
```

Запрещено использовать:

```text
DISTINCT ON latest OI
```

вместо historical query.

## Arguments

Запрещено:

```text
START == END
```

Для EXPLAIN передавать:

```text
HISTORY_START
END
AS_OF
```

## Evidence

Использовать:

```sql
EXPLAIN (
    ANALYZE,
    BUFFERS,
    FORMAT JSON
)
```

только для bounded diagnostic run.

Не запускать `EXPLAIN ANALYZE` полного 1000-symbol запроса до диагностического ограничения.

---

# 19. Шаг 13 — correctness gate

До performance profiling выполнить:

```bash
pytest -q tests/unit
pytest -q \
  tests/integration/test_stage3_reader.py \
  tests/integration/test_stage3_oi_reader.py \
  tests/integration/test_stage3_publication.py \
  tests/integration/test_stage3_publication_repository.py \
  tests/integration/test_stage3_permissions.py

ruff check .
ruff format --check .
mypy src
python -m compileall -q src
git diff --check
```

Дополнительно:

```text
clean migration apply 001–008;
migration rerun;
migration checksum tamper;
disposable role cleanup;
disposable DB cleanup.
```

Если любой correctness test падает:

```text
STOP.
Performance profiling не начинать.
```

---

# 20. Шаг 14 — bounded performance diagnostic

Этот шаг выполнять только после полного прохождения correctness gate.

Не запускать сразу исходную матрицу:

```text
100/500/1000 × 3 warm-up × 20 measured
```

Сначала диагностировать bottleneck.

## 20.1. Отдельный процесс для каждого размера

Выполнить отдельно:

```text
100 symbols
500 symbols
1000 symbols
```

Для каждого:

```text
1 warm-up;
3 measured cycles.
```

Это diagnostic evidence, не acceptance evidence.

## 20.2. Измерить отдельно

Для каждого цикла:

```text
candles SQL/fetch duration;
OI SQL/fetch duration;
funding SQL/fetch duration;
liquidation SQL/fetch duration;
normalization duration;
grouping duration;
single-symbol feature calculation duration;
batch total feature duration;
checksum duration;
total cycle duration;
rows returned;
Python peak allocation;
process peak RSS.
```

Не объединять всё только в один `duration_ms`.

## 20.3. Запрещено оптимизировать заранее

Сначала сформировать таблицу:

```text
component
100 symbols
500 symbols
1000 symbols
share of total time
```

После этого определить один главный bottleneck.

## 20.4. Допустимая точечная оптимизация

Разрешена только если profiling доказал bottleneck.

Допустимые изменения:

```text
устранение повторных сортировок;
устранение повторных проходов по одним спискам;
предварительная индексация candles/OI по timestamp;
deque или mapping для окон;
устранение лишних dataclass/object conversions;
chunked normalization;
server-side cursor;
bounded asyncpg fetch batching.
```

Без отдельного разрешения запрещено:

```text
полностью переносить Features в SQL;
менять feature formulas;
удалять Decimal;
уменьшать 24h history;
уменьшать количество symbols;
подменять full cycle Reader-only тестом;
добавлять production indexes;
изменять monitor-data.
```

## 20.5. Stop condition performance

Если bottleneck требует:

```text
новой архитектуры cache service;
production index;
Timescale continuous aggregate;
изменения collector schema;
изменения monitor-data;
переноса Features в SQL;
```

остановиться и сообщить:

```text
OWNER DECISION REQUIRED — PERFORMANCE ARCHITECTURE
```

Не выполнять это самостоятельно.

---

# 21. Шаг 15 — acceptance performance run

Acceptance run выполнять только если bounded diagnostic и точечная оптимизация укладываются в разрешённый scope.

Матрица:

```text
100 symbols:
3 warm-up + 20 measured

500 symbols:
3 warm-up + 20 measured

1000 symbols:
3 warm-up + 20 measured
```

Каждый размер запускать отдельным процессом.

Не запускать всю матрицу одним pytest process.

Перед запуском рассчитать ожидаемый timeout:

```text
measured duration одного cycle
× 23
× safety factor 1.5
```

Timeout не увеличивать молча.

В отчёте указать:

```text
расчёт timeout;
реальный timeout;
фактическое время;
exit code.
```

Если acceptance снова не завершается:

```text
не публиковать partial p50/p95/max;
не считать test passed;
оставить PERFORMANCE BLOCKED.
```

---

# 22. Шаг 16 — production source contracts

Не изменять текущие fail-closed contracts:

```text
Binance candle = MIXED
Bybit candle = UNKNOWN
Binance OI = UNKNOWN
Bybit OI = UNKNOWN
Funding = OBSERVATION
Liquidations = UNKNOWN
```

Не пытаться сделать production contract рабочим предположением.

Сохранить:

```text
production candles fail closed;
production liquidations fail closed;
production oi_base unavailable;
Universe remains INACTIVE.
```

Это отдельный owner action.

В отчёте написать:

```text
OWNER ACTION REQUIRED — MONITOR-DATA SOURCE CONTRACT
```

Не менять `monitor-data`.

---

# 23. Шаг 17 — документация

Обновить:

```text
CURRENT_STATE.md
TODO.md
HANDOFF.md
README.md

docs/stages/STAGE_03_REPORT.md
docs/stages/STAGE_03_EVIDENCE.md
docs/stages/STAGE_03_OPEN_ISSUES.md

docs/market_data/FEATURE_CONTRACT.md
docs/market_data/STAGE_03_PERFORMANCE_REPORT.md
```

До нового push документы должны говорить:

```text
Published baseline:
8459f4157aa87495df306f11ebfcd124bfac07f3

Current correction:
local only

Push:
not performed after current correction

Independent verdict:
REJECT

Correctness remediation:
completed / incomplete — по факту

Performance:
diagnostic complete / blocked — по факту
```

Не писать:

```text
current remediation uncommitted
```

после создания amended commit.

Внутри commit не писать его собственный SHA.

Новый локальный SHA указывать только в ответе агента.

---

# 24. Полная проверка

После всех разрешённых изменений:

```bash
pytest -q
```

Отдельно:

```bash
pytest -q tests/unit
pytest -q tests/integration -rs
```

Load acceptance — отдельными командами по размеру.

Статические проверки:

```bash
ruff check .
ruff format --check .
mypy src
python -m compileall -q src
git diff --check
```

Security:

```text
project-standard gitleaks scan;
AST float scan;
секреты и DSN не публиковать.
```

Database:

```text
clean migrations 001–008;
rerun migrations;
checksum tamper;
TX-01;
TX-02;
repository batch rollback;
permission tests;
PUBLIC revoke checks.
```

---

# 25. Git после исправлений

Проверить:

```bash
git diff --name-only 8459f4157aa87495df306f11ebfcd124bfac07f3
git diff --stat 8459f4157aa87495df306f11ebfcd124bfac07f3
git diff --check
git status --short
```

Никаких файлов вне scope.

Не использовать:

```bash
git add .
git add -A
```

Добавлять точные пути:

```bash
git add <exact-paths>
```

После полного correctness verification:

```bash
git commit --amend --no-edit
```

Затем:

```bash
git rev-parse HEAD
git rev-parse origin/stage/03-market-data
git status --short
git log --oneline --decorate -3
git diff ee72737406461df90980c51063fce297d7faa0be...HEAD --stat
```

Ожидается:

```text
local SHA новый;
remote SHA остаётся 8459f415...;
worktree clean;
один Stage 3 commit поверх Base.
```

---

# 26. Push запрещён

Не выполнять:

```bash
git push
git push --force
git push --force-with-lease
```

После отчёта владельцу потребуется отдельное разрешение только на:

```bash
git push --force-with-lease origin stage/03-market-data
```

---

# 27. Stop conditions

Немедленно остановиться при любом из условий:

```text
требуется изменение monitor-data;
требуется production DB modification;
требуется production index;
требуется изменение migrations 001–007;
требуется изменение financial/trading code;
требуется новый service;
требуется Redis/cache daemon;
требуется изменение feature formulas;
требуется больше двух новых runtime modules;
correctness suite падает;
batch rollback не доказан;
clean install не загружает policy;
performance bottleneck требует архитектурного решения;
worktree содержит чужие изменения.
```

Не обходить blocker фиктивным test fixture или ослаблением policy.

---

# 28. Критерии готовности к re-audit

Все условия должны выполняться одновременно:

```text
OI latest freshness отделена от historical lookup.
oi_lookup_max_lag реально используется.
OI changes 5m/30m/2h доказаны тестами.
Candle max age применяется.
Funding max age применяется.
Liquidation availability обязательна.
Conflicting liquidation duplicates fail closed.
Slots snapshot сериализуется.
Feature JSON детерминирован.
Publication batch использует один SQL query.
Repository batch rollback доказан.
Repository принимает реальный MarketFeatureSnapshot.
PyYAML устанавливается как runtime dependency.
Policy загружается через штатную factory.
No hidden runtime policy defaults.
Load test проверяет actual row counts.
Load test проверяет actual feature correctness.
EXPLAIN соответствует Reader SQL.
Correctness suite полностью проходит.
Документация соответствует Git.
Worktree clean.
Один Stage 3 commit.
Push не выполнен.
```

Performance acceptance может оставаться заблокированным только при наличии:

```text
полного diagnostic report;
доказанного bottleneck;
честного stop condition;
отсутствия ложных capacity claims.
```

---

# 29. Формат финального отчёта агента

```text
STAGE 3 CORRECTNESS REMEDIATION 3 — REPORT

1. Git
- Base SHA
- Published baseline SHA
- New local SHA
- Remote SHA
- Commit count
- Worktree status

2. Scope
- Modified files
- New files
- Confirmation: no out-of-scope files

3. OI
- Latest freshness rule
- Historical lookup rule
- max lag
- 5m result
- 30m result
- 2h result
- Tests

4. Candle/Funding freshness
- candle_max_age behavior
- funding_feature_max_age behavior
- Tests

5. Liquidations
- Availability behavior
- Deduplication
- Conflict behavior
- Tests

6. Serialization
- Serializer
- Decimal format
- Datetime format
- Determinism tests

7. Publication
- Feature batch query count
- Universe batch query count
- Empty batch
- Exact retry
- Conflict rollback
- Repository integration tests

8. Policy
- PyYAML dependency
- Clean install result
- Factory path
- Version mismatch behavior

9. Database
- Migrations clean apply
- Rerun
- Checksum tamper
- TX-01
- TX-02
- PUBLIC revokes
- Disposable cleanup

10. Correctness tests
- Unit passed
- Integration passed
- Skipped
- Failed
- Not executed

11. Performance diagnostic
- 100 symbols
- 500 symbols
- 1000 symbols
- Component timings
- Rows
- RSS
- Allocation
- Bottleneck
- Optimization performed or OWNER DECISION REQUIRED

12. Acceptance load
- Executed/not executed
- Exact commands
- Exact timeout
- Complete/blocked
- No partial claims

13. Isolation
- monitor-data HEAD before/after
- monitor-data tree/diff hash
- production DB unchanged
- runtime unchanged
- main unchanged
- no PR
- no merge
- no push

14. Open owner actions
- monitor-data candle contract
- OI units/multiplier
- actual funding
- liquidation semantics
- production Timescale permissions/performance

15. Status
READY FOR INDEPENDENT CORRECTNESS RE-AUDIT
NOT PASS
NOT MERGED
NOT PUSHED
```

Запрещено самостоятельно писать:

```text
Stage 3 PASS
Stage 3 complete
Ready to merge
```
