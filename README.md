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

- Setting a due date when creating a task
- Editing task text
- Deleting tasks
- Subtasks

## Development

Pure, decidable logic — parsing dcal's JSON, sorting and filtering tasks,
building launcher rows, encoding/decoding the action strings used by
`executeItem` — lives in `TaskItems.js`, has no QML or Qt dependency, and is
covered by `tests/tst_TaskItems.qml`. Everything with a side effect — the
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
related) only catch a wrong implementation outside UTC. Also run:

```bash
TZ=America/Los_Angeles QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests
```

Under `TZ=UTC`, a version of `dueLabel` that reads all-day dates with local
getters instead of UTC getters passes anyway, because UTC and local agree
there.

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
