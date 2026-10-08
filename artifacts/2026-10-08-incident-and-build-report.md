# Инцидент и сборка — 2026-10-08

**Проект:** Sweet No Sleep · **Окно разбора:** 19:42–20:05 МСК · **Статус:** сборка дособрана и проверена, сессия ждёт разблокировки моделей.

> Контекст: агентская сессия «SNS» (OpenCode, агент Sisyphus) остановилась за шаг до финальной упаковки приложения. Причина — не краш: у ротации кончились все бесплатные модели (рейт-лимиты). Рядом — [HTML-версия отчёта](./2026-10-08-incident-and-build-report.html).

## Хронология

| Время | Событие |
|---|---|
| 17:30–17:35 | Агент доломал три правки: зависший вебхук-сервер («зомби»-слушатель порта), фрейм менюбар-панели, кнопка Copy. Release-билд — успех. |
| 17:35:40 | `check-project.sh` → EXIT=0: 238 ключей локализации, скины, медиа, 9 hook-тестов, panel-smoke. |
| 17:36–19:24 | Все запросы отклонены: «Rate limit exceeded» на моделях ротации (big-pickle, mimo-v2.6-flash-free и др.). Работа стоит. |
| 17:51–19:41 | Попытки возобновления («что делать?» → «??» → «продолжай») — каждая упирается в лимит. |
| 19:41:11 | Последняя попытка (mimo-v2.6-flash-free) — снова лимит. |
| 19:41:17 | Sidecar приложения завершается — сессия останавливается. |
| 19:42–20:05 | Разбор: приложение живо, база цела (`quick_check: ok`), причина — модели. Сборка дособрана, проверки прогнаны. |

За день сессия собрала 16 отказов «Rate limit exceeded», 2 — «модель недоступна в регионе», 1 — «недостаточно средств».

## Сборка и проверки

- `./Scripts/build-app.sh` → **EXIT=0** (19:51:53): свежий подписанный `dist/Sweet No Sleep — Kiwi Cat.app` из текущих правок (после генерации медиа `og-image.png` восстановлен до закоммиченного состояния).
- Реленч: старый тестовый инстанс (pid 13915) остановлен, «золотой» (pid 18180) не тронут; новый инстанс слушает `127.0.0.1:18290`.

### curl-сьют по вебхуку (свежий билд)

| Проверка | Ожидали | Ответ |
|---|---|---|
| start (валидный токен) | 200 | 200 |
| неверный токен | 401 | 401 |
| неверный Host | 403 | 403 |
| сторонний Origin | 403 | 403 |
| неизвестный путь | 404 | 404 |
| GET вместо POST | 405 | 405 |
| тело 5 КБ | 413 | 413 |
| done (завершение) | 200 | 200 |

Отдельно подтверждено: возвратная проблема «зависшего» вебхука (HTTP 000, зомби-слушатель) на свежем билде не воспроизводится — последние правки рабочие.

## Состояние правок

Рабочее дерево `sweet-no-sleep-pr9` (ветка `tmp-build`), незакоммичено:

- `Sources/SweetNoSleep/AgentWebhookServer.swift` — синхронный `stop()`, ретраи на `EADDRINUSE`;
- `Sources/SweetNoSleep/SettingsView.swift` — кнопка Copy для hook-команд;
- `Sources/SweetNoSleep/SweetNoSleepApp.swift` — `minWidth/minHeight + fixedSize` для панели.

## План агента: статус

| Пункт | Статус |
|---|---|
| Вебхук: синхронный `stop()` + ретраи | сделано (в дереве) |
| Фрейм менюбар-панели (`fixedSize`) | сделано |
| Кнопка Copy | сделано |
| Сборка + проверки | дособрано и проверено |
| Реленч + curl-сьют | выполнено (8/8) |
| MCP-запись `sweet-no-sleep` в `opencode.jsonc` | не начато |
| UI-проверка футера (скриншот) | не начато |

## Открытые вопросы

1. **Разблокировка сессии.** Дождаться сброса лимитов zen-free или переключить модели ротации на другого провайдера. Проверено из конфига: llm7 — отвечает; ovhcloud — сейчас throttled.
2. **Краш-репорт 11:04.** Падение в сеттере `agentCooldownMinutes` (цепочка Combine → инвалидация SwiftUI). Воспроизводимость на свежем билде не проверена — если повторится, разбирать отдельно.

## Ссылки

- PR #9 (P0–P2, ветка `arena/22936f10-sweet-no-sleep`): https://github.com/bestdeejay-design/sweet-no-sleep/pull/9
- PR #12 (F0–F5, ветка `arena/3331051a-sweet-no-sleep`): https://github.com/bestdeejay-design/sweet-no-sleep/pull/12

## Приложение A. Сырые результаты

```
build-app.sh (19:51:40 → 19:51:53):
  Rendered app icon, menu-bar icons, skin previews, and social images into Resources/Art/Rendered
  Build complete!
  "dist/Sweet No Sleep — Kiwi Cat.app": replacing existing signature
  Built: dist/Sweet No Sleep — Kiwi Cat.app
  EXIT=0

check-project.sh (ранее, от агента):
  Shell syntax checks passed.
  Localization check passed: 238 English source keys match the catalog.
  Media validation passed: 8 editable SVG sources and complete generated outputs.
  Skin validation passed: 3 manifest(s), 3 unique IDs.
  Agent hook smoke tests passed (9 mocked URL events).
  Panel wander smoke test passed: 48 eased frame steps moved pet.panelOrigin to the target.
  EXIT=0

curl-сьют:
  200 valid start → 200 · 401 bad token → 401 · 403 wrong Host → 403
  403 bad Origin → 403 · 404 unknown → 404 · 405 GET → 405
  413 big body → 413 · 200 done → 200
```
