# Аудит и сдача по ворк-ордеру #18 — 2026-10-08

**Задача:** [issue #18](https://github.com/bestdeejay-design/sweet-no-sleep/issues/18)
«Kot-Arbuz promo — English copy, portfolio page on dajet.ru (ksu), README character section»
+ комментарий maintainer'а от 8 октября: черновик ksu лежит в ветке
`maintainer/kot-arbuz-draft` @ `97b8a1b`, его нужно отрецензировать, допилить и
открыть PR в `ksu/main`.

**Что сделано:**

1. Аудит черновика `97b8a1b` (9 файлов, +145/−4) и всего, что накопилось вокруг
   задачи (PR #16, коммит `6ee44ce` с `characterName`, артефакты приёмки).
2. Ветка `arena/57b7e7fa-ksu` @ `d4fdd7a` — черновик доведён: **207/207 зелёных**,
   сборка идемпотентна, sitemap содержит project-0…project-16.
3. P1 в этом репозитории: раздел **«The cats»** в README (English only).
4. **Блокер:** токен сессии даёт запись только в `sweet-no-sleep`. Пуш в `ksu`
   — `403 Permission to bestdeejay-design/ksu.git denied`. Ветка упакована в
   git-бандл, инструкция ниже.

---

## 1. Аудит черновика `maintainer/kot-arbuz-draft`

### Что было сделано правильно (принято как есть)

| Пункт ворк-ордера | Проверка | Итог |
|---|---|---|
| Запись в `const projects` (индекс 16, без перенумерации) | `script.js:479` | ✅ поля, обложка, `colors` — дословно |
| Ключи `proj.16.*` в обоих словарях | 48 proj-ключей, паритет en/ru | ✅ утверждённый текст — дословно, пропусков нет |
| `case 16` в оверлее по образцу `case 15` | ссылки + 3 галереи | ✅ обе ссылки, `rel="noopener"`, три 1-колоночные галереи |
| `16` первым в `WORKS_ORDER` | `script.js:487` | ✅ карточка ведёт сетку |
| Картинки в `portfolio/characters/kot-arbuz/` | размеры, вес, источник | ✅ JPEG, 2000×2000 / 2200×443 / 480×320, 161/108/18 КБ |
| `og-16.jpg` 1200×630 | размер, фон | ✅ 1200×630, фон `#0b0b0b`, персонаж по центру |
| Заглушка `project-16/index.html` | сверка с `project-7` и `project-15` | ✅ побайтово тот же шаблон, canonical + редирект верные |
| Баг `buildSitemap()` | `tools/build.mjs` | ✅ генератор сканирует `project-*/`, сортировка числовая |
| Идемпотентность `node tools/build.mjs` | два прогона + `git diff` | ✅ ноль изменений, sitemap совпадает с закоммиченным |

Обложка на белом фоне — это не ошибка, а продолжение прецедента:
`portfolio/stickers/kiwi-cat.jpg` (проект 7, персонаж Киви) — тоже квадрат
3545×3545 на белом.

### Находки

| # | Находка | Критичность | Что сделано |
|---|---|---|---|
| 1 | **`node tools/check.mjs` — 206/207, а не 207/207.** Проверка `C8 sitemap.clean` утверждает «sitemap не содержит redirect-заглушки project-\*/», а ворк-ордер требует обратного. Более того, на `main` эта проверка **уже красная** (205/206): `sitemap.xml` там содержит `project-15/`, дописанный руками | 🔴 блокер приёмки | Проверка переписана: `C8 sitemap.stubs` требует, чтобы все каталоги `project-N/` из корня были в sitemap. Стало **207/207** |
| 2 | **`og-16.jpg` — белый квадрат на тёмном фоне.** Мастер-арт `Resources/Characters/kot-arbuz/kot-arbuz.png` — RGBA с **непрозрачным** белым фоном (альфа 255 по всему полотну 3756²). «Отфлаттенить в белое и положить на `#0b0b0b`» даёт белую карточку 47 % ширины × 88 % высоты, а сам кот внутри занимает ≈22 % площади кадра | 🟠 качество | Переделано: персонаж берётся из вырезанных слоёв `body.png` + `tail.png`, подрезается по силуэту, ставится 520 px по высоте строго по центру, за ним — мягкое свечение в его палитре (корка `#7FAF5E`, мякоть `#FD5D5D`). Контроль: попиксельная корреляция с мастер-артом **0.989** |
| 3 | **`skin-card.jpg` 480×320 мылится.** В 1-колоночной галерее CSS даёт `width:100%` при ширине контента оверлея 1120 px — растяжение в 2.3 раза | 🟠 качество | Перерендерен в **1200×800** из тех же спрайт-слоёв: та же композиция, что в `Scripts/prepare-character-assets.py::preview_images`, только `scale = 5` (спрайт 1024 → 752, апскейла нет). 67 КБ |
| 4 | **Проект 16 не попал в JSON-LD `ItemList`** в `index.html` (там 12 записей, последняя — `project-15`) | 🟡 SEO | Добавлен `position: 13` → `https://dajet.ru/project-16/` |
| 5 | **Документация отстала:** `README.md` / `README.ru.md` считают 16 проектов и `og-0…og-15`, `DESIGN_RULES.md` §5.1 утверждает «все URL проектов (11 шт.)», а sitemap теперь генерируется | 🟡 консистентность | Обновлено до 17 проектов / `og-0…og-16`; §5.1 переписан под генератор; в обе таблицы проектов добавлена строка 17; `CHANGELOG.md` получил раздел `Unreleased` |
| 6 | **Регистр RU-копии.** Сайт говорит с читателем на «ты» («ноль запросов без твоего действия», «заполните форму»), а утверждённый текст — «когда один ждёт **вашего** ответа» | 🟡 на решение maintainer'а | Оставлено **дословно** (прямое указание ворк-ордера). Вариант на «ты» — одна замена слова, см. §5 |
| 7 | `test_runner.py` (97 e2e-проверок, `DESIGN_RULES` §9) не запускается в этой среде — нужен `playwright` + браузер | ⚪ среда | Не проверено, оставлено на Мака |

### Что намеренно не тронуто

- **Цены, услуги, `js/config.js`.** В оверлее проекта 16 поэтому нет кнопки
  «Заказать» (она появляется только если у услуги в конфиге стоит `project: N`);
 对应关系 услуг: logo:1, identity:0, illustration:4, poster:2, packaging:1,
 stickers:7, retouch:10, book:9, website:11. Кнопка «Поделиться» есть.
- **Порядок и нумерацию старых проектов.**
- **Утверждённый текст копии** (EN и RU) — ни одного слова не изменено.

---

## 2. Итоговая ветка `arena/57b7e7fa-ksu` @ `d4fdd7a`

```
97b8a1b  wip(reference): Kot-Arbuz portfolio page       (черновик maintainer'а)
d4fdd7a  feat(portfolio): Kot-Arbuz as project 17 (index 16) + sitemap generator fix
```

Изменения поверх черновика:

| Файл | Что и почему |
|---|---|
| `tools/check.mjs` | `C8 sitemap.clean` → `C8 sitemap.stubs` (находка 1) |
| `og-16.jpg` | новая композиция, 49 КБ (находка 2) |
| `portfolio/characters/kot-arbuz/skin-card.jpg` | 480×320 → 1200×800, 67 КБ (находка 3) |
| `portfolio/characters/kot-arbuz/kot-arbuz.jpg` | пересобран из мастер-арта, 152 КБ (было 161) |
| `portfolio/characters/kot-arbuz/app-states.jpg` | пересобран из `artifacts/…pr16-acceptance-evidence.png`, 105 КБ (было 108) |
| `index.html` | `ItemList` position 13 (находка 4) |
| `README.md`, `README.ru.md` | 17 проектов, `og-0…og-16`, `project-0…project-16`, строка 17 в таблицах |
| `DESIGN_RULES.md` | §5.1 про sitemap |
| `CHANGELOG.md` | раздел `Unreleased` |

Проверено в чистом клоне `ksu` (ветка взята из бандла):

```
node tools/check.mjs   →  Пройдено: 207   Провалено: 0
node tools/build.mjs   →  Обновлено файлов: 0   (повторный прогон: git status чист)
grep -c '<loc>' sitemap.xml → 28, project-0 … project-16 на месте
```

Медиа пересобираются из исходников этого репозитория (коммит `6ee44ce`):
мастер-арт `Resources/Characters/kot-arbuz/kot-arbuz.png`, слои
`Resources/PetSkins/kot-arbuz/{body,tail}.png`, полоса состояний
`artifacts/2026-10-08-pr16-acceptance-evidence.png`. Рецепт — в §4.

---

## 3. Блокер: пуш в `ksu` запрещён

```
$ git push -u origin arena/57b7e7fa-ksu
remote: Permission to bestdeejay-design/ksu.git denied to bestdeejay-design.
fatal: unable to access 'https://github.com/bestdeejay-design/ksu.git/': 403

$ gh api -X POST repos/bestdeejay-design/ksu/git/refs ...
{"message":"Resource not accessible by integration","status":"403"}
```

Токен этой сессии (GitHub App installation) выдаёт запись **только** на
`bestdeejay-design/sweet-no-sleep`. Читать `ksu` он умеет, писать — нет:
ни ветку, ни PR, ни коммит через API.

**Решение:** ветка упакована в git-бандл
`ksu-kot-arbuz-project16.bundle` (641 КБ, лежит в корне рабочей области).
На Маках, где есть доступ к `ksu`:

```bash
cd ~/Projects/ksu                 # или где лежит ksu
git fetch /путь/к/ksu-kot-arbuz-project16.bundle arena/57b7e7fa-ksu:arena/57b7e7fa-ksu
git push -u origin arena/57b7e7fa-ksu
gh pr create --repo bestdeejay-design/ksu --base main \
  --head arena/57b7e7fa-ksu \
  --title "Kot-Arbuz — the watermelon cat as project 17 (index 16)" \
  --body "closes bestdeejay-design/sweet-no-sleep#18"
```

Бандл проверен: чистый клон `ksu` → `git fetch` из бандла → 207/207, сборка
идемпотентна, все четыре картинки на месте. При желании ветку можно поднять и
без пуша — `git checkout -b arena/57b7e7fa-ksu FETCH_HEAD` после fetch'а.

Рядом лежит `ksu-kot-arbuz-project16-text.patch` — текстовый diff без картинок,
для чтения (377 строк).

---

## 4. Как пересобрать медиа (рецепт)

Источники — этот репозиторий, `@2x`-превью и спрайт-слои уже закоммичены.

| Выход | Источник | Правило |
|---|---|---|
| `portfolio/characters/kot-arbuz/kot-arbuz.jpg` | `Resources/Characters/kot-arbuz/kot-arbuz.png` (3756², **непрозрачный белый фон**) | отфлаттенить в белое, 2000×2000, JPEG q85 progressive |
| `portfolio/characters/kot-arbuz/app-states.jpg` | `artifacts/2026-10-08-pr16-acceptance-evidence.png` (2590×522) | ширина 2200, JPEG q85 |
| `portfolio/characters/kot-arbuz/skin-card.jpg` | `Resources/PetSkins/kot-arbuz/{body,tail}.png` (1024², уже вырезаны) | композиция `preview_images()` из `Scripts/prepare-character-assets.py` при `scale = 5` → 1200×800, JPEG q85 |
| `og-16.jpg` | те же `body.png` + `tail.png` | 1200×630, фон `#0b0b0b`; `tail` под `body` на 1024², обрезать по альфа-bbox, вписать по высоте 520 px, по центру, свечение в палитре персонажа, JPEG q85 |

Важно: **`skin-card.jpg` и `og-16.jpg` нельзя собирать из `kot-arbuz.png`** —
у мастер-арта нет прозрачности, получится белый прямоугольник (ровно это и
было в черновике). Прозрачность есть только у производных слоёв.

---

## 5. Открытый вопрос: регистр RU-копии

Утверждённый текст (в ветке — дословно):

> Персонаж для Sweet No Sleep — macOS-приложения, которое не даёт Mac уснуть,
> пока работают ИИ-агенты. Арбузный кот собран как послойный спрайт-пак:
> полосатая корка, красная сердцевина, хвост качается, пока агенты работают, и
> загорается янтарный знак вопроса, когда один ждёт **вашего** ответа.

Весь остальной сайт говорит на «ты» («ноль запросов без твоего действия»,
«заполните форму — 3–4 минуты», «я держу за вами слот» — впрочем, в FAQ
«вы» тоже встречается). Если решишь привести проект к «ты», правка ровно одна:

```diff
- …и загорается янтарный знак вопроса, когда один ждёт вашего ответа.
+ …и загорается янтарный знак вопроса, когда один ждёт твоего ответа.
```

Сейчас в ветке — утверждённый вариант.

---

## 6. Что осталось на Мака (приёмка maintainer'а)

ksu:

1. `python3 -m http.server` в `ksu` → `/#project-16`: оверлей показывает hero,
   EN-копию, обе кнопки-ссылки, три галереи; переключатель RU — русскую копию;
   переключатель темы не ломает контраст.
2. Сетка «Работы» начинается с карточки Котя-арбуза, обложка рендерится
   (нет битой картинки, нет белой вспышки на тёмной теме).
3. `/project-16/` редиректит в оверлей; `og-16.jpg` — 1200×630.
4. `node tools/build.mjs && git diff --exit-code` на втором прогоне; sitemap —
   project-0…16; `node tools/check.mjs` — зелёный.
5. По желанию: `python3 test_runner.py` (playwright) — 97 e2e-проверок.

sweet-no-sleep:

6. README рендерится на GitHub: раздел «The cats», инлайновое превью
   `Resources/Art/Rendered/preview-kot-arbuz.png`, ссылка на
   `https://dajet.ru/#project-16`.

**CI:** в `ksu` нет workflow и нет ни одного PR — проверять нечего, зелёного
значка не будет. В `sweet-no-sleep` — `.github/workflows/macos.yml`.
