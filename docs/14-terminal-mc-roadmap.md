# Full Terminal + Midnight Commander Roadmap

## Цель
Сделать терминал в приложении полноценным `xterm`-класса, чтобы стабильно запускались и корректно работали полноэкранные TUI-программы, в первую очередь `midnight commander (mc)`.

## Что уже есть (база)
- Реальное SSH-подключение через NIO/NIOSSH (`SSHTerminalRuntime`).
- PTY/Shell request + resize (`window-change`) и синхронизация `stty`.
- Базовый ANSI/VT100 парсер (`VT100Parser`) и буфер (`TerminalEmulator`).
- Мобильный UX с soft-keys, историей команд, копированием/вставкой, mirror на внешний дисплей.

## Ключевой gap для `mc`
`mc` — полноэкранное curses/TUI приложение. Ему нужен **не “логовый текстовый вывод”**, а корректная модель терминала по ячейкам (screen buffer + cursor + modes), с поддержкой расширенных escape-последовательностей и строгого ввода управляющих клавиш.

## Gap-анализ по слоям

### 1) Эмуляция терминала (главный блокер)
Текущее ядро покрывает базовые CSI/SGR, но для `mc` не хватает:
- DEC private modes кроме `?25` (cursor visibility):
  - `?1` (cursor keys mode),
  - `?7` (autowrap),
  - `?47/?1047/?1048/?1049` (alternate screen + cursor save/restore),
  - `?1000/1002/1006` (mouse tracking, optional first pass).
- Scroll region (`CSI r`) и корректный scroll внутри region.
- Character set shifts/line drawing (`ESC ( 0`, `SO/SI`) — важно для псевдографики/рамок.
- Более строгая обработка control chars и режима вставки/замены.
- Корректная логика line wrap на правой границе (DECAWM semantics).

### 2) Рендер
Сейчас основной рендер опирается на `transcript` в `UITextView`.
Для полноэкранного TUI нужен рендер от `TerminalBufferSnapshot` (строгое grid-представление), иначе:
- “лесенка”/ломаные переносы,
- несоответствие курсора,
- артефакты при частых обновлениях.

### 3) Ввод
Для `mc` и подобных приложений нужны предсказуемые key-sequences:
- стрелки/Home/End/PgUp/PgDn/Insert/Delete/F1-F12,
- Tab/Shift+Tab,
- Ctrl/Alt-modified combinations,
- bracketed paste (`CSI ?2004 h/l` + `ESC[200~...ESC[201~`).

### 4) Сессия и протокол
- TERM должен быть согласован с фактической эмуляцией (например `xterm-256color`, либо свой terminfo-профиль).
- Resize должен атомарно переобновлять и runtime, и local buffer (без визуальных “скачков”).

### 5) Тестирование
Сейчас есть unit-тесты базового парсинга, но нет regression-набора под TUI.

## Рекомендуемая стратегия реализации

## Этап 0 (P0): Техническое решение ядра
1. Принять архитектурное решение:
   - `Option A (рекомендуется)`: интегрировать зрелый terminal engine (`SwiftTerm`/`libvterm`-подход).
   - `Option B`: расширять текущий `VT100Parser + TerminalEmulator` до xterm-уровня.
2. Зафиксировать в ADR, чтобы не терять время на смешанную модель.

Критерий выхода:
- Утверждён источник истины для terminal state machine.

## Этап 1 (P0): Buffer-first rendering
1. Перевести phone-терминал и external mirror на единый `buffer-first` рендер:
   - основной источник: `TerminalBufferSnapshot.styledLines + cursor`.
2. `transcript` оставить только как debug/fallback.
3. Выравнивание геометрии:
   - единый расчёт columns/rows,
   - одинаковая модель для phone и external display.

Критерий выхода:
- Нет “мертвого поля”/лестницы,
- курсор стабилен на обоих экранах,
- одинаковый вывод при одинаковом размере PTY.

## Этап 2 (P0): xterm-mode parity для `mc`
1. Реализовать/добавить поддержку:
- alternate screen `?1049 h/l` (+ 47/1047/1048),
- DECSET/DECRST ключевых режимов (`?1`, `?7`, `?25`, `?2004`),
- scroll region (`CSI r`),
- line drawing charset (`ESC(0`, `SO/SI`).
2. Доработать wrap semantics на правой границе.

Критерий выхода:
- `mc` открывается без артефактов,
- панели/рамки/курсор корректны,
- выход из `mc` возвращает предыдущий shell screen.

## Этап 3 (P1): Полный input profile
1. Ввести слой `TerminalKeyMapper`:
- физическая клавиатура + soft-keys -> единые terminal sequences.
2. Добавить клавиши и комбинации:
- F1-F12, PgUp/PgDn, Home/End, Insert/Delete,
- Shift+Tab, Ctrl/Alt-modified keys.
3. Bracketed paste режим.

Критерий выхода:
- Горячие клавиши `mc` (F-keys, Tab, arrows, Enter, Esc) работают предсказуемо.

## Этап 4 (P1): Performance + scrollback correctness
1. Оптимизировать рендер частых апдейтов (coalescing / diff render).
2. Развести viewport scrollback и live screen state (не смешивать transcript-модель с live grid).

Критерий выхода:
- Стабильный ввод без лагов на длинных сессиях,
- прокрутка истории и live-обновления не конфликтуют.

## Этап 5 (P0): Тестовый контур под TUI

### Unit tests
- CSI/DECSET/DECRST/OSC/SCS/SO-SI сценарии.
- Alternate screen enter/exit.
- Scroll region и cursor motion corner cases.

### Integration tests (runtime)
- connect -> resize -> start `mc` -> navigate -> exit.
- reconnect/background/foreground with active TUI session.

### Manual certification checklist
- `mc`
- `vim`
- `top`/`htop`
- `less -R`
- `nano`
- `tmux` (минимум attach/detach)

Готовность релиза по терминалу:
- Все unit/integration зелёные,
- manual checklist без критических дефектов,
- внешний монитор показывает тот же активный буфер/cursor state (read-only mirror).

## Что менять в текущем коде в первую очередь
1. `Packages/AppModules/Sources/SSHKit/VT100Parser.swift`
   - расширение parser state machine для DEC/xterm modes.
2. `Packages/AppModules/Sources/SSHKit/TerminalEmulator.swift`
   - alternate/main buffer,
   - scroll region,
   - wrap semantics,
   - charset handling.
3. `AdminConsoleApp/ViewControllers/ControlRootViewController.swift` (`RebootTerminalViewController`)
   - переход с transcript-tail рендера на `buffer snapshot`.
4. `AdminConsoleApp/DesktopSceneDelegate.swift`
   - mirror тоже на buffer-first и тот же cursor pipeline.
5. `Packages/AppModules/Tests/SSHKitTests/TerminalEmulatorTests.swift`
   - большой regression-набор под TUI.

## Риски
- Расширять свой parser/emulator дольше, чем интегрировать зрелый движок.
- Смешанная модель `transcript + grid` будет снова возвращать визуальные артефакты.
- Без formal regression-suite дефекты будут возвращаться после UX правок.

## Предлагаемый порядок выполнения (практический)
1. За 1 итерацию выбрать engine strategy (A/B) и зафиксировать.
2. Сразу сделать buffer-first рендер на телефоне и external mirror.
3. Затем добить `mc`-critical escape coverage.
4. После этого — input profile + performance polishing.

## Статус реализации (2026-04-21)
- Выполнен `buffer-first` рендер для phone + external mirror, убраны основные артефакты смешанного transcript/grid.
- Закрыта критическая часть xterm parity:
  - `?47/?1047/?1048/?1049`,
  - `?7`, `?25`, `?2004`, `?1` (DECCKM),
  - `CSI r`,
  - `ESC(0`, `SO/SI`.
- Добавлен mode-aware input routing в UI:
  - стрелки/Home/End автоматически переключаются в application sequences при активном `DECCKM`.
- Добавлена база для mouse private modes:
  - `?1000`, `?1002`, `?1003`, `?1006` (state tracking в snapshot).
- Regression suite расширен под новые режимы (включая `DECCKM` и mouse modes), все тесты зелёные.
