# STAGE 4B — ЗАДАНИЕ НОВОМУ ЧАТУ НА РЕАЛИЗАЦИЮ

## Роль

Ты основной исполнитель `Stage 4B — Levels Builder` проекта:

```text
shamilmirz/paper-trading-engine
```

Твоя задача — полностью написать код этапа, тесты и документацию. После завершения остановиться и передать результат отдельному аудиторскому чату. Самостоятельно не выполнять merge.

---

## 1. Сначала прочитай источники задания

Репозиторий с ТЗ и решениями:

```text
shamilmirz/paper
```

Обязательные файлы, читать полностью и в указанном порядке:

```text
/STAGE4tz2.md
/STAGE4B_IMPLEMENTATION_PLAN.md
/STAGE4B_CANDLE_SOURCE_DECISION.md
/MONITOR_DATA_CANONICAL_CANDLES_FIX_TASK.md
```

Правила работы, полный Levels contract, тесты, evidence и запреты уже находятся в этих файлах. Не проси пользователя повторно вставлять их содержимое в чат.

После этого изучи фактический код и обязательные документы в `shamilmirz/paper-trading-engine`, перечисленные в `/STAGE4tz2.md`. Не доверяй пересказу — проверяй текущий Git и файлы репозитория.

---

## 2. Актуализированный старт

Stage 4A уже слит в `main`.

Последний известный SHA на момент подготовки задания:

```text
41547df810918dad7eb7d1dffe49f1ac26a2013a
```

Перед началом обязательно проверить актуальный `origin/main`. Если он изменился, использовать новый актуальный SHA и зафиксировать это в отчёте.

Рабочая ветка:

```text
stage/04b-levels
```

Создавать её только от чистого актуального `origin/main`.

Новая миграция:

```text
migrations/011_stage4_levels.sql
```

Миграция `010_stage4_growth_catchup.sql` уже существует. Не создавать второй файл с номером `010`.

---

## 3. Обязательный Git preflight

Перед изменениями выполнить и сохранить результат:

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

Не удалять и не изменять чужие dirty/untracked файлы. Не использовать:

```text
git reset --hard
git clean
git stash без разрешения владельца
git add .
git add -A
```

Если чистую ветку или worktree безопасно создать нельзя — остановиться и сообщить причину.

---

## 4. Что реализовать

Полностью выполнить Stage 4B по указанным файлам:

```text
Levels schema и роли
Market Data Reader boundary для canonical hourly/minute candles
VOLUME_IMPULSE_LEVEL
VOLUME_CLUSTER_LEVEL
ZONE_GEOMETRY_V1
merge и lineage
исторический chunked rebuild
checkpoints и resume
BUILDING / READY / FAILED
minute projection
touch / reaction / break / retest
freshness / significance
ALL / RELEVANT / PRIORITY
hourly / minute / daily runs
paper-levels-binance
paper-levels-bybit
heartbeat / watermarks / recovery
unit / integration / restart / concurrency / load / Docker tests
dокументация и evidence
```

Работать небольшими логическими коммитами согласно `/STAGE4B_IMPLEMENTATION_PLAN.md`.

---

## 5. Свечной источник — жёсткое ограничение

Текущий production source `monitor-data` имеет статус:

```text
BINANCE: BLOCKED
BYBIT: BLOCKED
```

Поэтому:

- код Stage 4B реализовать полностью на доказанных canonical fixtures;
- реальный Market DB startup должен fail closed без `LEVELS_SOURCE_CONTRACT_STATUS=APPROVED`;
- не публиковать реальные READY levels из текущих legacy `candles_1m` или `candles_1h`;
- не изменять `monitor-data`;
- не включать исправление collectors в эту ветку;
- не выдавать fixture acceptance за production source proof.

Максимально честный итог до отдельного исправления `monitor-data`:

```text
IMPLEMENTATION COMPLETE — PRODUCTION SOURCE BLOCKED
```

---

## 6. Запрещённые границы

Не реализовывать и не менять:

```text
Detector
Signal
Signal Validator
Paper Entry
Trade Manager
Trades
Accounts
Reservations
Ledger
Dashboard
production deployment
monitor-data code или database
Stage 5+
```

Levels Builder не создаёт Candidates, Signals, Trades или финансовые записи.

---

## 7. Самопроверка перед завершением

Выполнить все проверки и evidence из:

```text
paper/STAGE4tz2.md
paper/STAGE4B_IMPLEMENTATION_PLAN.md
```

Обязательно доказать минимум:

```text
Binance/Bybit isolation
immutable level definitions
source candles и lineage
no future candles
Decimal-only calculations
atomic READY publication
FAILED keeps previous READY
restart/replay без дублей
chunked rebuild и resume
Reader batches <= 100 symbols
staging invisibility
least-privilege roles
ровно четыре Stage 4 application containers
отсутствие Detector/Signal/Trade writes
секреты отсутствуют
monitor-data не изменён
```

Не скрывать skipped, failed или недоказанные проверки. Все существенные результаты записать в Markdown evidence, а не оставлять только в `/tmp` или выводе терминала.

---

## 8. Git и остановка

После завершения:

```bash
git status --short
git diff --check
git log -10 --oneline
git rev-parse HEAD
git rev-parse origin/main
```

Не выполнять:

```text
merge в main
создание или merge PR
production deployment
начало Stage 5
```

Остановиться на финальном commit ветки `stage/04b-levels`.

---

## 9. Итоговый ответ

Вернуть пользователю один итоговый отчёт:

```text
STAGE 4B — IMPLEMENTATION REPORT

1. Base SHA.
2. Final SHA.
3. Branch.
4. Список коммитов.
5. Changed files.
6. Что реализовано.
7. Архитектура Levels.
8. Миграция и DB roles.
9. Reader/source gate.
10. Formation/geometry/merge.
11. Rebuild/restart/replay.
12. Minute lifecycle.
13. Docker services.
14. Результаты каждого набора тестов.
15. Load metrics.
16. Evidence files.
17. Что доказано.
18. Что не доказано.
19. Production source blockers.
20. Проверка monitor-data.
21. Secret scan.
22. git status и diff check.
23. Рекомендация для независимого аудита.
```

Не просить разрешения на промежуточные очевидные шаги. Выполнить весь безопасно доступный объём работы, исправить найденные ошибки и только после этого передать Final SHA на аудит.
