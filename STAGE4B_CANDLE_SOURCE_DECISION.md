# STAGE 4B — CANDLE SOURCE DECISION

## Audit input

Audit UTC: `2026-08-02 15:20:10`

Monitor-data:

```text
repository state: dirty before audit
branch: main
HEAD: 8d4175a5fe0b8dbd0c2179328f58a055f64ae9bb
audit mode: read-only
```

## Verdict

```text
BINANCE: BLOCKED
BYBIT: BLOCKED
```

Current `candles_1h` must not be connected directly to Levels Builder.
Current `candles_1m` must not be used for production Levels without a proven normalization contract.

## Reasons

### Binance

- WebSocket persists candle close timestamp.
- REST persists candle open timestamp.
- REST does not prove the selected kline is closed.
- Both forms can exist for the same logical minute.
- No unique canonical candle key exists.

### Bybit

- `confirm` is not enforced before persistence.
- Multiple updates of one logical minute are stored as separate rows.
- Physical timestamp does not provide a proven unique closed-candle identity.
- No unique canonical candle key exists.

### Hourly aggregate

- `candles_1h` is built from the ambiguous `candles_1m` source.
- It therefore inherits duplicate and timestamp-semantic errors.
- It has no turnover/quote-volume field required by the Levels price-volume contract.

## Architecture decision

Stage 4B is split into two boundaries.

### Boundary A — implementation may continue

Implement and test independently of production market data:

```text
Levels domain models
011_stage4_levels.sql
formation algorithms
zone geometry
merge and lineage
BUILDING/READY/FAILED publication
historical rebuild checkpoints
minute lifecycle logic
Binance/Bybit isolation
Docker fixture runtime
unit/integration/restart/load tests
```

All tests use canonical fixtures with explicit:

```text
exchange
symbol
candle_start
candle_close
is_closed
OHLCV
turnover_quote
source_identity
source_contract_version
```

### Boundary B — production source remains disabled

Real Market DB startup must fail closed until the source audit verdict changes from `BLOCKED`.

Required startup gate:

```text
LEVELS_SOURCE_CONTRACT_STATUS=APPROVED
```

Any of these states must prevent real Levels publication:

```text
BLOCKED
UNKNOWN
UNVERIFIED
```

No real READY level run may be published from the current source.

## Required monitor-data correction

A future monitor-data correction must produce one canonical row per:

```text
(exchange, symbol, candle_start)
```

Required rules:

### Binance

- Store one timestamp meaning only: candle start in UTC.
- WebSocket persists only `x=true` closed candles.
- REST excludes the current unclosed kline.
- REST and WebSocket upsert the same canonical key.

### Bybit

- Store candle start in UTC.
- Persist only `confirm=true` closed candles.
- Updates of the same kline must upsert one canonical key.

### Shared

- Add a unique constraint for the canonical candle key.
- Preserve base volume and quote volume/turnover.
- Expose source/update or ingestion timestamps when possible.
- Rebuild or repair historical canonical candles before approval.
- Recreate or validate hourly candles from the corrected canonical minutes.
- Repeat duplicate, gap, freshness and 1h-vs-1m comparison tests.

## Level-building rule after approval

```text
1h candles create VOLUME_IMPULSE_LEVEL and VOLUME_CLUSTER_LEVEL.
1m candles create zero base levels.
1m candles only maintain distance, touch, reaction, break and retest state.
```

## Development consequence

Stage 4B code can be completed against canonical fixtures, but final production acceptance cannot be `PASS` until monitor-data returns:

```text
APPROVED_DIRECT_1H
```

or:

```text
APPROVED_AGGREGATE_FROM_1M
```

Until then the maximum honest verdict is:

```text
IMPLEMENTATION COMPLETE — PRODUCTION SOURCE BLOCKED
```
