# ТЗ ДЛЯ АГЕНТА — MERGE STAGE 4B И ФОРМАЛЬНЫЙ CLOSEOUT STAGE 4

## 1. Цель

Безопасно выполнить merge проверенной ветки Stage 4B в `main`, затем отдельным documentation commit синхронизировать все документы проекта и формально закрыть Stage 4.

Рабочий репозиторий:

```text
shamilmirz/paper-trading-engine
```

Проверенная ветка:

```text
stage/04b-levels
```

Точный одобренный head:

```text
5bc45d002b0ca7265f8c21d89538f1a6aac64c6d
```

Ожидаемый `origin/main` перед merge:

```text
41547df810918dad7eb7d1dffe49f1ac26a2013a
```

Независимый итог:

```text
Stage 4A: COMPLETE
Stage 4B implementation: COMPLETE
Stage 4B acceptance: COMPLETE
Stage 4B merge readiness: APPROVED
```

Подтверждённая финальная acceptance:

```text
GitHub Actions проверял точный SHA 5bc45d002b0ca7265f8c21d89538f1a6aac64c6d
static-unit: PASS
docker-acceptance: PASS
177 tests passed
scanner/boundary scan runtime: PASS
restart/replay idempotency: PASS
disposable containers, volumes and network removed
```

Агент обязан самостоятельно получить и записать точный GitHub Actions run ID и URL. Не выдумывать их.

---

## 2. Жёсткие ограничения

Разрешено только:

```text
merge stage/04b-levels -> main
обновление документации после merge
формальный Stage 4 closeout
```

Запрещено:

```text
production deployment
запуск production Levels
подключение legacy candles_1m или candles_1h
изменение monitor-data
перезапуск monitor-data collectors
изменение production Paper DB или Market DB
начало Stage 5
добавление Detector, Signal, Entry, Trade, Ledger или Dashboard кода
squash merge
rebase merge
force-push
переписывание истории
удаление проверенной ветки
```

Production-ограничение после merge остаётся обязательным:

```text
Production deployment: NO
Production candle source: BLOCKED
```

---

## 3. Preflight в чистом clone/worktree

Работать только в чистом clone или отдельном чистом worktree.

Выполнить и сохранить вывод:

```bash
git fetch origin --prune
git status --short
git branch --show-current
git rev-parse origin/main
git rev-parse origin/stage/04b-levels
git merge-base origin/main origin/stage/04b-levels
git log --oneline --decorate -10 origin/main
git log --oneline --decorate -10 origin/stage/04b-levels
```

Обязательные значения:

```text
origin/main = 41547df810918dad7eb7d1dffe49f1ac26a2013a
origin/stage/04b-levels = 5bc45d002b0ca7265f8c21d89538f1a6aac64c6d
merge-base = 41547df810918dad7eb7d1dffe49f1ac26a2013a
worktree = clean
```

Если любое значение отличается — остановиться. Не выполнять автоматический rebase, merge main в feature branch или исправление конфликтов.

Проверить ветку:

```bash
git rev-list --left-right --count origin/main...origin/stage/04b-levels
git diff --check origin/main...origin/stage/04b-levels
```

Feature branch не должна быть behind относительно ожидаемого main.

---

## 4. Проверка acceptance перед merge

До merge доказать, что GitHub Actions run относится именно к:

```text
5bc45d002b0ca7265f8c21d89538f1a6aac64c6d
```

Записать:

```text
workflow name
run ID
run URL
trigger
head branch
head SHA
created_at/completed_at
static-unit conclusion
docker-acceptance conclusion
```

Оба job должны иметь:

```text
conclusion: success
```

Также зафиксировать из logs/evidence:

```text
177 tests passed
PostgreSQL 16 disposable initialization passed
migration 011 and role bootstrap passed
production Compose topology = exactly 4 application services
atomic READY/FAILED acceptance passed
Binance/Bybit isolation passed
direct DML denial passed
restart/replay count equality passed
boundary/secret scan passed
cleanup down -v --remove-orphans completed
```

Если run не найден, SHA не совпадает или хотя бы один job не `success` — merge запрещён.

---

## 5. Merge

Создать обычный merge commit, сохранив историю Stage 4B.

```bash
git switch main
git pull --ff-only origin main
git status --short
git merge --no-ff origin/stage/04b-levels -m "Merge stage/04b-levels into main"
```

При любом конфликте остановиться. Не разрешать конфликт самостоятельно в рамках этого задания.

После локального merge проверить:

```bash
git status --short
git diff --check HEAD^1..HEAD
git show --no-patch --pretty=raw HEAD
git rev-parse HEAD^1
git rev-parse HEAD^2
```

Ожидаемые родители merge commit:

```text
first parent:  41547df810918dad7eb7d1dffe49f1ac26a2013a
second parent: 5bc45d002b0ca7265f8c21d89538f1a6aac64c6d
```

Затем:

```bash
git push origin main
git fetch origin
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"
```

Сохранить точный merge SHA. Не считать Stage 4 закрытым до documentation closeout commit.

---

# 6. Полный аудит документации после merge

После merge выполнить поиск по всем tracked Markdown-файлам:

```bash
git grep -nE 'stage/04b-levels|READY FOR INDEPENDENT|INDEPENDENT.*REQUIRED|Do not merge|not merge-ready|merge performed: no|Merge: NO|verification still required before merge|PENDING|FINAL_SHA_PENDING|PENDING_FINAL_CLOSEOUT|161 passed|172 passed|4ecfcbad0bed7344c1ac5857aa2c010980a88c56|5bc3ce999e909f8871fa61e7b759d853b4de340b' -- '*.md' || true
```

Каждый результат проверить вручную.

Правило:

```text
старый SHA можно оставить только как явно подписанный промежуточный исторический SHA;
старый статус нельзя оставлять как текущий статус;
финальные документы должны указывать 5bc45d... как Stage 4B final SHA;
финальные документы должны указывать реальный merge SHA;
финальная acceptance должна указывать 177 tests и точный Actions run.
```

Не выполнять слепую глобальную замену.

---

# 7. Документы, которые обязательно обновить

## 7.1 `CURRENT_STATE.md`

Заменить активный статус ветки/повторного аудита на текущую картину:

```text
Stage 4 COMPLETE AND MERGED INTO MAIN
Stage 4B final SHA: 5bc45d002b0ca7265f8c21d89538f1a6aac64c6d
Stage 4 merge SHA: <ACTUAL_MERGE_SHA>
Stage 4 closeout SHA: pending до documentation commit
GitHub Actions run: <ACTUAL_RUN_ID / URL>
static-unit: success
docker-acceptance: success
177 tests passed
```

Указать:

```text
main содержит Stage 4A Scanner/Growth и Stage 4B Levels Builder;
Stage 4 формально закрыт после closeout commit;
production deployment не выполнялся;
canonical production candles остаются BLOCKED;
Stage 5 не начат;
следующий этап разрешён только отдельным заданием после closeout.
```

Удалить текущие формулировки:

```text
CI boundary-scan correction как active stage
READY FOR INDEPENDENT RE-AUDIT
final commit reported externally
merge prohibited
```

## 7.2 `HANDOFF.md`

Переименовать смысл документа из Stage 4B pre-merge handoff в Stage 4 closeout handoff.

Записать:

```text
branch: main
main before merge: 41547df...
Stage 4B final SHA: 5bc45d...
merge SHA: <ACTUAL_MERGE_SHA>
closeout SHA: pending до commit
Actions run ID/URL
both jobs success
177 tests passed
```

Continuing boundaries:

```text
no production deployment
no current legacy candle usage
canonical candles still BLOCKED
no real production rebuild
no Stage 5 work in this closeout
no monitor-data changes
```

Удалить требования повторно запускать independent workflow и запрет merge — merge уже выполнен.

## 7.3 `TODO.md`

Отметить выполненными:

```text
independent Stage 4B audit
separate merge decision
merge Stage 4B into main
formal Stage 4 documentation closeout
```

Сохранить открытыми:

```text
correct and approve canonical production candles in monitor-data
real bounded historical rebuild after source approval and authorization
mixed active/discovery universe optimization before production deployment
production source verification
production deployment and scheduler integration
Stage 5
```

Stage 5 должен остаться `not started`.

## 7.4 `README.md`

Обновить Current stage:

```text
Stage 4A Scanner/Growth and Stage 4B Levels Builder are merged into main.
Stage 4 implementation and disposable acceptance are complete.
```

Явно сохранить:

```text
production Levels publication remains blocked;
canonical Binance/Bybit candles are not approved;
disposable fixtures are not production proof;
production deployment has not occurred.
```

Убрать текст, что Stage 4B находится на branch для independent review.

## 7.5 `docs/stages/STAGE_04_REPORT.md`

Сделать финальным отчётом полного Stage 4.

Обязательная identity-секция:

```text
Stage 4A merge commit: 8143fb414868cb317f4320c69d8439d5eda25002
main before Stage 4B merge: 41547df810918dad7eb7d1dffe49f1ac26a2013a
Stage 4B final SHA: 5bc45d002b0ca7265f8c21d89538f1a6aac64c6d
Stage 4B merge SHA: <ACTUAL_MERGE_SHA>
Stage 4 closeout SHA: pending до documentation commit
```

Финальный verdict:

```text
STAGE 4 COMPLETE — MERGED INTO MAIN
DISPOSABLE ACCEPTANCE COMPLETE
PRODUCTION SOURCE BLOCKED
PRODUCTION DEPLOYMENT NOT AUTHORIZED
```

Добавить точный Actions run ID/URL, оба success и 177 tests.

Удалить раздел `Verification still required before merge` или заменить его на `Final independent acceptance`.

Не удалять production boundary.

## 7.6 `docs/stages/STAGE_04_EVIDENCE.md`

Обновить Git boundary:

```text
branch: main
merge performed: yes
Stage 4B final SHA
merge SHA
closeout SHA pending
monitor-data modified: no
Stage 5 started: no
production deployment: no
```

Добавить финальное независимое evidence:

```text
clean server clone
exact SHA verification
Python 3.12
Docker 29.1.3
Compose 2.40.3
PostgreSQL 16.4 image
static-unit success
docker-acceptance success
177 tests passed
migration/roles passed
atomic publication passed
exchange isolation passed
restart/replay passed
cleanup passed
```

Удалить или перенести в исторический подраздел утверждения, что ruff/mypy/PostgreSQL/Docker evidence не получено.

Сохранить раздел `Production evidence not claimed`:

```text
no real production historical rebuild
no production READY Levels
no production query-plan/capacity certification
no canonical-candle approval
```

## 7.7 `docs/stages/STAGE_04_OPEN_ISSUES.md`

Удалить закрытый merge blocker:

```text
Independent disposable acceptance — merge blocker
```

В начале явно записать:

```text
No open Stage 4 merge blockers.
Stage 4 is merged and closed.
```

Сохранить открытыми как deployment blockers/technical debt:

```text
production canonical candles
production capacity and real-history rebuild
Stage 4A mixed active/discovery universe optimization
provisional Growth expiry, если всё ещё актуально
```

Удалить формулировки:

```text
until workflow green Stage 4B is not merge-ready
independent audit and merge decision required
```

## 7.8 `docs/stages/STAGE_04B_CI_EVIDENCE.md`

Зафиксировать финальную цепочку:

```text
requested baseline: 5bc3ce999e909f8871fa61e7b759d853b4de340b — только как промежуточный baseline
final accepted SHA: 5bc45d002b0ca7265f8c21d89538f1a6aac64c6d
merge SHA: <ACTUAL_MERGE_SHA>
Actions run ID/URL
static-unit: success
docker-acceptance: success
177 tests passed
```

Уточнить, что последний commit изменил только:

```text
scripts/stage4b_boundary_scan.py
tests/unit/test_stage4b_boundary_scan.py
```

И что он не изменял Levels runtime, migrations, Docker topology или production boundaries.

Заменить:

```text
READY FOR INDEPENDENT RE-AUDIT
Merge: NO
final SHA reported externally
```

на финальный acceptance/merge status.

---

# 8. Документы, которые проверены, но обычно не требуют изменения

Эти файлы не менять только ради merge-статуса, если stale scan не обнаружит реальную проблему:

```text
docs/architecture/LEVELS_CONTRACT.md
docs/market_data/SOURCE_SCHEMA_AUDIT.md
docs/market_data/SOURCE_MAPPING.md
docs/market_data/TIMESTAMP_CONTRACT.md
ROADMAP.md
DECISIONS.md
```

Причины:

```text
LEVELS_CONTRACT описывает архитектуру и правильно сохраняет BLOCKED source gate;
market-data audit документы должны оставаться фактическим доказательством BLOCKED legacy source;
ROADMAP сейчас общий, а не журнал статусов этапов;
DECISIONS является ADR register, merge сам по себе не создаёт новое архитектурное решение.
```

Если агент всё же меняет один из этих файлов, он обязан в отчёте отдельно объяснить необходимость.

Не создавать фиктивный `ADR_037`, если такого принятого ADR в проекте нет.

---

# 9. Documentation closeout commit

После обновления документов выполнить:

```bash
git status --short
git diff --check
git diff --stat
git diff --name-only
git grep -nE 'READY FOR INDEPENDENT|INDEPENDENT.*REQUIRED|Do not merge|not merge-ready|merge performed: no|Merge: NO|verification still required before merge|FINAL_SHA_PENDING|PENDING_FINAL_CLOSEOUT' -- '*.md' || true
```

Оставшиеся совпадения допустимы только в явно помеченном историческом контексте. Агент обязан перечислить их и объяснить.

Создать отдельный commit:

```bash
git add CURRENT_STATE.md HANDOFF.md TODO.md README.md \
  docs/stages/STAGE_04_REPORT.md \
  docs/stages/STAGE_04_EVIDENCE.md \
  docs/stages/STAGE_04_OPEN_ISSUES.md \
  docs/stages/STAGE_04B_CI_EVIDENCE.md

git diff --cached --check
git commit -m "docs(stage4): record Stage 4B merge and close Stage 4"
```

Не использовать:

```text
git add .
git add -A
```

После создания closeout commit получить его SHA и заменить во всех документах временное `pending`, если это можно сделать без рекурсивной попытки самовстраивания SHA.

Правильное правило:

```text
документы внутри closeout commit могут не содержать собственный closeout SHA;
closeout SHA фиксируется внешним итоговым отчётом и, при необходимости, отдельным минимальным follow-up commit;
не создавать бесконечную цепочку commit ради self-embedded SHA.
```

Предпочтительно:

```text
в документах записать merge SHA и final Stage 4B SHA;
closeout SHA записать в итоговом ответе;
не создавать второй documentation commit только ради его собственного SHA.
```

Push:

```bash
git push origin main
git fetch origin
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"
```

---

# 10. Финальные проверки

Выполнить:

```bash
git status --short
git diff --check origin/main
git log -5 --oneline --decorate
git show --no-patch --pretty=raw <MERGE_SHA>
git show --stat --oneline <CLOSEOUT_SHA>
git branch --contains 5bc45d002b0ca7265f8c21d89538f1a6aac64c6d
git merge-base --is-ancestor 5bc45d002b0ca7265f8c21d89538f1a6aac64c6d origin/main
```

Проверить, что:

```text
origin/main указывает на closeout commit
Stage 4B SHA является ancestor main
merge commit имеет правильных двух родителей
worktree clean
нет stale merge-blocker статусов
monitor-data не изменён
production не запускался
Stage 5 не начат
```

Не требуется повторно запускать production services.

---

# 11. Итоговый отчёт агента

Вернуть строго:

```text
Repository
Initial main SHA
Stage 4B final SHA
Actions workflow name
Actions run ID
Actions run URL
static-unit conclusion
docker-acceptance conclusion
Test count
Merge method
Merge SHA
Merge parent 1
Merge parent 2
Closeout commit SHA
Final origin/main SHA
Changed documentation files
Stale-status scan result
Git diff --check result
Worktree status
monitor-data touched: yes/no
production DB touched: yes/no
production containers started/restarted: yes/no
Stage 5 started: yes/no
```

Финальный verdict должен быть одним из:

```text
STAGE 4 MERGED AND CLOSED — PRODUCTION SOURCE BLOCKED
```

или при любой проблеме:

```text
CLOSEOUT REJECTED — MAIN/CI/MERGE/DOCUMENTATION BLOCKER
```

После отчёта остановиться. Не начинать Stage 5 и не выполнять production deployment.
