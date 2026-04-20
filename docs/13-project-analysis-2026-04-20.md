# AdminConsole / Termius Reboot — Project Analysis (2026-04-20)

## 1) Product Intent

Цель проекта — мобильный iOS SSH-клиент с UX и ментальной моделью, максимально близкими к Termius, с приоритетом полной самодостаточности на iPhone.
После стабилизации мобильного baseline добавляется зеркалирование терминала на внешний монитор как дополнительная функция (а не основная зависимость).

Ключевые принципы:
- Phone-first: все основные SSH-сценарии должны работать без внешнего дисплея.
- Termius-like UX: Vaults, Favorites/Recents, quick connect, terminal-first workflow.
- Predictable architecture: явные границы между UI, state/model и runtime слоями.

## 2) Current Functional State

### 2.1 Mobile App Shell
- Вход в reboot shell через `RebootRootViewController`.
- Основные разделы: `Vaults`, `Connections`, `Profile`.
- Экранная компоновка приведена ближе к Termius-паттернам (карточная структура, dark terminal surface, нижние action rows).

### 2.2 Hosts / Persistence
- Реализован `RebootHostStore`.
- Поддерживается CRUD хостов.
- Реализованы `Favorites` и `Recents`.
- Состояние хостов переживает перезапуск приложения.

### 2.3 SSH Connectivity
- Реальное SSH-подключение через `SSHTerminalRuntime` (SwiftNIO SSH + TransportServices).
- Поддержка интерактивного shell channel.
- Поддержка host key trust-on-first-use и host key mismatch.
- Устранено зависание на shell request (перевод на совместимый fire-and-forget PTY/shell requests).

### 2.4 Terminal UX/Input
- Команды отправляются напрямую с системной клавиатуры в SSH (без отдельного поля `Command/Send`).
- Убрана визуальная аномалия повторного символа за счет рендера из `state.buffer` (VT100 state), а не сырого transcript.
- Терминал продолжает корректно исполнять команды.

### 2.5 Error Visibility / Diagnostics
- Добавлен этапный SSH-лог в runtime transcript (`[SSH] ...`).
- Добавлены пользовательские сообщения для типовых ошибок:
  - host/DNS not found,
  - auth failed,
  - timeout,
  - connection refused,
  - network unreachable,
  - host key mismatch.
- На `Connections` показывается `Connection Failed` alert с читаемой причиной.

### 2.6 Keyboard/Prompt UX
- Системный парольный `UIAlertController` заменен кастомным in-app password sheet.
- Это снизило конфликты keyboard-session и стабилизировало ввод.

## 3) Technical Architecture Snapshot

## 3.1 Layers
- UI Layer: UIKit view controllers (`ControlRootViewController` и nested reboot controllers).
- App Model Layer: `RebootAppModel` (state + bridge к runtime).
- Runtime Layer: `SSHTerminalRuntime` (network/session/send/receive/status).
- Persistence/Security Layer:
  - Host persistence (`PersistenceKit`),
  - Keychain abstractions (`SecurityKit`),
  - TOFU host key store.

### 3.2 Notable Runtime Decisions
- Асинхронный actor-based runtime для терминала.
- Многонаблюдательная модель terminal state (устойчива при переходах между экранами).
- Таймауты стадий подключения и человекочитаемая классификация ошибок.

### 3.3 Terminal Rendering Strategy
- VT100 parser + screen buffer.
- На UI отображается `buffer.viewportText(...)` как canonical terminal representation.
- Transcript остаётся для debug/history, но не для финального командного рендера.

## 4) UX Status vs Termius-like Targets

Выполнено:
- Vault-oriented flows.
- Favorites + Recents.
- Quick connect из host details и connections.
- Рабочая SSH shell session на iPhone.
- Inline status и fail feedback.

Существенно улучшено:
- Прямой keyboard->terminal ввод.
- Soft key row, совместимость с реальными серверами.

Ещё не достигнуто:
- Полноценные multi-session tabs/panes.
- Продвинутая история/сниппеты команд.
- Полный Termius-grade terminal ergonomics (selection/copy UX, bigger scrollback).

## 5) Risks / Gaps

- Background/foreground lifecycle устойчивость требует расширенной матрицы тестов на реальном устройстве.
- Нужна дальнейшая hardening-работа для edge-кейсов SSH-серверов (нестандартные auth policies).
- Внешний монитор пока отключен для baseline-стабилизации (по плану это осознанно).

## 6) Roadmap Progress (from `docs/12-termius-reboot-roadmap.md`)

### Phase 0 (Reboot Baseline)
Статус: практически закрыта.
- Mobile shell на reboot flow: сделано.
- Host persistence/favorites/recents: сделано.

### Phase 1 (Core Mobile MVP)
Статус: функционально достигнут baseline.
- SSH connect + command execution на phone-only: сделано.
- Termius-like core layout/flows: в активной шлифовке.

### Phase 2 (Robustness & Realistic Behavior)
Статус: начат частично.
- Better validation/errors: частично сделано.
- Terminal ergonomics: начато (direct input, soft keys, render fidelity).
- Lifecycle hardening: в работе.

### Phase 3 (External Monitor Mirroring)
Статус: еще не начат в reboot track (осознанно, после mobile stability gate).

## 7) Recommended Next Execution Item

Следующий приоритетный пункт roadmap:
- **Phase 2: Session lifecycle improvements (foreground/background handling)**

Почему именно он:
- Core SSH уже работает.
- Основной пользовательский риск теперь в устойчивости long-running session во время app lifecycle transitions.
- Этот шаг критичен перед возвратом к external monitor mirroring.

## 8) Acceptance Criteria for Next Item

Для закрытия следующего пункта нужно обеспечить:
- При `sceneWillResignActive/DidEnterBackground` сессия не теряется мгновенно.
- При `sceneDidBecomeActive` terminal state восстанавливается корректно.
- Пользователь видит ясный статус при реальном разрыве (а не silent freeze).
- Нет regression по direct keyboard input и command execution.

