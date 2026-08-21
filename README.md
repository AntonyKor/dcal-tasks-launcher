# Dcal Tasks

A [Dank Material Shell](https://danklinux.com/docs/dankmaterialshell) launcher
plugin for [dcal](https://github.com/AvengeMedia/dankcalendar) tasks. It lists,
searches, creates, and completes tasks from any dcal calendar directly in the
DMS launcher.

## Requirements

- DankMaterialShell >= 1.5.0
- [dcal](https://github.com/AvengeMedia/dankcalendar) installed, with its
  daemon running (`dcal run -d`)

No other runtime dependencies. Unlike some other dcal-related DMS plugins,
this one does not shell out to `jq` — task and calendar JSON is parsed in
QML/JS.

## Installation

Manual install:

```bash
git clone <your-fork-url> ~/.config/DankMaterialShell/plugins/dcalTasks
```

Then reload plugins from DMS settings, or restart the shell.

Nix flake input (adapt to your own flake, replacing the placeholder URL with
your fork):

```nix
inputs.dms-plugin-dcal-tasks = {
  url = "<your-fork-url>";
  flake = false;
};

programs.dank-material-shell.plugins.dcalTasks = {
  enable = true;
  src = inputs.dms-plugin-dcal-tasks;
};
```

## Setup

Open DMS Settings → Plugins → Dcal Tasks and pick a **Default task list**.
Until a default is set, `defaultCalendarId` is empty and task creation is
disabled: the launcher still shows the "Create task" row, but instead of
creating anything it tells you to set a default list in plugin settings.

The default list only controls where *new* tasks are filed. Existing tasks
are read from every dcal calendar with `holdsTasks: true`, regardless of
which one is set as default.

## Usage

- Type `;` (or your configured trigger) to list open tasks. Which tasks that
  first list holds is set by **Show by default** (see Settings).
- Type `;<text>` to filter by task summary or calendar name, and to get
  `Create task: <text>` as the first result. Searching always covers every
  task, whatever **Show by default** is set to.
- Press Enter on a task to toggle it: open tasks are marked complete,
  completed tasks are reopened.
- Press Enter on `Create task: <text>` to create a task with that summary in
  the default task list.
- End the text with a date phrase — `; publish tasks plugin tomorrow at 6PM` —
  to give the new task a due date. See **Due dates when creating** below.

## Due dates when creating

A date phrase at the **end** of what you type is read as a due date and taken
out of the task title:

```
; publish tasks plugin tomorrow at 6PM
    → "publish tasks plugin"   due Aug 22, 6:00 PM
```

Only a trailing phrase counts, so `; buy milk for saturday party` keeps its
saturday and gets no due date.

| You type | You get |
|---|---|
| `today`, `tomorrow` | that day, all-day |
| `tonight` | today at 20:00 |
| `friday`, `fri`, `on tuesday` | the nearest such weekday, today included |
| `this friday` | same as bare `friday` |
| `next friday` | that weekday in the *following* Mon–Sun week |
| `in 3 days`, `in a week`, `in 2 months` | that far out, all-day |
| `aug 30`, `august 30th`, `30 aug`, `30 august 2027` | that date |
| `2026-08-30` | that date |
| `30/8`, `30/8/26`, `30.8.2026` | that date, **day first** |
| any of the above + `at 6PM` / `6:30pm` / `at 18:00` | that date, at that time |
| `at 6PM` on its own | today if 6PM is still ahead, otherwise tomorrow |

A date with no year means the next one to come: `jan 5` typed in August is
next January, not four months ago. A date that does not exist (`feb 30`,
`32/8`) is not treated as a date at all.

`2/9` is 2 September, never 9 February — day-first, always. Give a year if
you want the other reading to be unambiguous to a reader.

### When the guess is wrong

Whenever a date is detected the launcher offers **two** create rows:

```
+ Create task: publish tasks plugin
  in Inbox · due Aug 22, 6:00 PM

+ Create task: publish tasks plugin tomorrow at 6PM
  in Inbox · no due date
```

The second row creates the task with the literal text you typed and no due
date. That is the escape hatch for a task genuinely titled "… tomorrow", and
it means a wrong guess is one arrow key away from being harmless. A query
that is *only* a date (`; tomorrow`) has no title left over, so it offers the
literal row alone.

Due dates are shown on task rows too: `due Aug 30` for an all-day task and
`due Aug 22, 6:00 PM` for one with a time.

## Settings

| Key | Default | Effect |
|---|---|---|
| `trigger` | `;` | Prefix that opens this launcher in DMS. Reload the plugin after changing it. |
| `defaultCalendarId` | `""` | dcal calendar ID that new tasks are created in. Empty disables task creation. |
| `defaultView` | `all` | Which tasks the launcher lists before you type. `all` shows everything, `today` shows tasks due today or already overdue, `defaultList` shows only the default task list. Typing a query always searches everything. |
| `showCompleted` | `false` | When true, completed tasks are listed below the open ones, most recently completed first. |

`defaultView: today` hides undated tasks — with no due date there is nothing
placing a task in today. All-day due dates are compared as calendar dates, so
a task due today stays visible all day regardless of your timezone.

`defaultView: defaultList` falls back to showing all tasks when no default
task list is set, or when the one that is set no longer exists in dcal. That
is a misconfiguration rather than a filter, and honouring it would leave the
launcher permanently empty with no explanation.

A failed create or complete raises an error toast naming the reason dcal
gave. The launcher closes as soon as you press Enter, so the toast is the
only place that failure can surface.

## Not supported yet

- Editing task text
- Deleting tasks
- Subtasks

## Development

Pure, decidable logic — parsing dcal's JSON, sorting and filtering tasks,
building launcher rows, encoding/decoding the action strings used by
`executeItem` — lives in `TaskItems.js`, has no QML or Qt dependency, and is
covered by `tests/tst_TaskItems.qml`. Reading a due date out of typed text
lives in `DateParser.js`, is likewise pure, takes its clock as an argument
(`nowMs`) so every case is deterministic, and is covered by
`tests/tst_DateParser.qml`. Everything with a side effect — the
`Process` calls that shell out to `dcal ipc`, and plugin settings I/O — lives
in `DcalTasksLauncher.qml` and `DcalTasksSettings.qml` and is not unit
tested; it is exercised manually by loading the plugin in DMS.

Run the tests with:

```bash
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests
```

On Arch, `/usr/bin/qmltestrunner` is usually the Qt5 build from
`qt5-declarative`. Run it against this Qt6 QML and it exits 1 with **no
output at all** — no failure message, nothing — which reads as a hang rather
than a wrong binary. Use the full path to the Qt6 binary above, not whatever
`qmltestrunner` resolves to on `$PATH`.

The all-day due-date tests (`test_dueLabel_allDayUsesUtcCalendarDate` and
related) and the whole of `tst_DateParser.qml` only catch a wrong
implementation outside UTC — all-day dues are UTC midnight while timed dues
are local instants, and the two only diverge away from UTC. Also run:

```bash
TZ=America/Los_Angeles QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests
```

Under `TZ=UTC`, a version of `dueLabel` that reads all-day dates with local
getters instead of UTC getters passes anyway, because UTC and local agree
there.

One test — `test_selectTasks_todayViewAllDayIsTimezoneIndependent` — fails at
`TZ=Pacific/Kiritimati` (UTC+14). That predates the due-date parser and is a
`defaultView: today` bug, not a formatting one.

### Reloading during development

`dms ipc call plugins reload dcalTasks` reloads the launcher component, but
**not** the settings panel. DMS loads that through a `Loader` pointed at
`DcalTasksSettings.qml`, and Qt caches QML components by URL for the life of
the process, so edits to the settings panel — and a settings file that did not
exist the first time the URL was resolved — are not picked up until the shell
restarts:

```bash
systemctl --user restart dms
```

A settings panel that fails to load looks identical to one that has no
settings at all: DMS's `settingsContainer` sets `clip: true` and collapses to
zero height when the loader has no item, so the "Failed to load settings"
message is clipped away. If the panel is blank, restart before debugging.

## License

MIT
