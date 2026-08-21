import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services
import "TaskItems.js" as TaskItems

Item {
    id: root

    property var pluginService: null
    property string trigger: ";"

    readonly property string pluginName: "dcalTasks"

    signal itemsChanged

    property string defaultCalendarId: ""
    property bool showCompleted: false
    property string defaultView: "all"

    property var tasks: []
    property var calendars: ({})
    property bool tasksLoaded: false
    property bool calendarsLoaded: false
    property string lastError: ""
    property string lastErrorKind: ""
    property double lastRefreshMs: 0

    // Set when a mutation invalidates the cache while a refresh triggered by
    // that same refresh() call is already in flight — the in-flight fetch may
    // have started before the mutation landed, so its result cannot be
    // trusted as post-mutation. Consumed by tasksProcess.onExited, which
    // starts exactly one more refresh instead of building a general queue.
    property bool refreshPending: false

    readonly property int staleAfterMs: 2000

    Component.onCompleted: loadSettings()

    onPluginServiceChanged: {
        if (pluginService)
            loadSettings()
    }

    Connections {
        target: root.pluginService
        enabled: root.pluginService !== null

        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === root.pluginName) {
                root.loadSettings()
                root.refresh()
            }
        }
    }

    function loadSettings() {
        if (!pluginService)
            return
        trigger = pluginService.loadPluginData(pluginName, "trigger", ";")
        defaultCalendarId = pluginService.loadPluginData(pluginName, "defaultCalendarId", "")
        showCompleted = pluginService.loadPluginData(pluginName, "showCompleted", false) === true
        defaultView = pluginService.loadPluginData(pluginName, "defaultView", "all")
    }

    // Due times render the way the rest of the shell renders a clock, rather
    // than by a rule of this plugin's own: DMS resolves "auto" against the
    // locale and lets Settings → Time & Weather override it. Guarded the same
    // way DMS guards its own reads of this (see DndPill.qml).
    readonly property bool use24Hour: typeof SettingsData !== "undefined"
                                      ? SettingsData.use24HourClock : true

    // Which number is the day in "2/9". DMS has no setting for this — unlike
    // the clock format — so it comes from the locale's own short date format,
    // read the way DMS reads the locale for its 12/24-hour default. Quoted
    // literals are stripped first so a format like 'de' d/M cannot mislead it.
    readonly property bool dayFirst: {
        const fmt = Qt.locale().dateFormat(Locale.ShortFormat).replace(/'[^']*'/g, "")
        const day = fmt.indexOf("d")
        const month = fmt.indexOf("M")
        return day !== -1 && (month === -1 || day < month)
    }

    // The DMS launcher calls this synchronously on every keystroke, so it must
    // never block. Return whatever is cached and let the refresh land later.
    function getItems(query) {
        refreshIfStale()
        return TaskItems.buildItems({
            tasksLoaded: root.tasksLoaded,
            calendarsLoaded: root.calendarsLoaded,
            error: root.lastError,
            errorKind: root.lastErrorKind,
            tasks: root.tasks,
            calendars: root.calendars,
            defaultCalendarId: root.defaultCalendarId,
            showCompleted: root.showCompleted,
            defaultView: root.defaultView,
            use24Hour: root.use24Hour,
            dayFirst: root.dayFirst,
            nowMs: Date.now()
        }, query || "")
    }

    function executeItem(item) {
        const parsed = TaskItems.parseAction(item ? item.action : "")

        if (parsed.type === "create") {
            if (!defaultCalendarId)
                return
            mutateProcess.actionType = "create"
            const args = ["dcal", "ipc", "tasks.create",
                          "calendarId=" + defaultCalendarId,
                          "summary=" + parsed.summary]
            // allDay only travels with a due — dcal has nothing to apply it to
            // otherwise, and an undated task is neither all-day nor timed.
            if (parsed.due.length > 0) {
                args.push("due=" + parsed.due)
                args.push("allDay=" + (parsed.allDay ? "true" : "false"))
            }
            mutateProcess.command = args
            mutateProcess.running = true
        } else if (parsed.type === "toggle") {
            mutateProcess.actionType = "toggle"
            mutateProcess.command = ["dcal", "ipc", "tasks.complete",
                                     "id=" + parsed.id,
                                     "completed=" + (parsed.completed ? "true" : "false")]
            mutateProcess.running = true
        }
    }

    function refreshIfStale() {
        if (Date.now() - lastRefreshMs < staleAfterMs)
            return
        refresh()
    }

    function refresh() {
        // Stamp lastRefreshMs only when a fetch actually starts. Stamping it
        // unconditionally (even when both guards below skip starting a
        // process) would erase a cache invalidation set by a mutation that
        // landed while a fetch was already in flight — see refreshPending.
        if (!tasksProcess.running) {
            tasksProcess.running = true
            lastRefreshMs = Date.now()
        } else {
            refreshPending = true
        }
        if (!calendarsProcess.running)
            calendarsProcess.running = true
    }

    // Controller.qml:135 re-runs the launcher search on this signal, and
    // early-returns when the launcher is closed, so this is free when nobody
    // is looking.
    function notifyLauncher() {
        if (pluginService && pluginService.requestLauncherUpdate)
            pluginService.requestLauncherUpdate(pluginName)
        itemsChanged()
    }

    Process {
        id: tasksProcess
        command: ["dcal", "ipc", "tasks.list"]
        running: false

        // Quickshell's Process fires neither exited nor
        // StdioCollector.onStreamFinished when the binary itself cannot be
        // started — it only logs "failed to start" and flips running back to
        // false. completed tracks whether this run got as far as a real
        // stdout result, so onRunningChanged can tell a start failure apart
        // from a normal completed run (which always sets completed first).
        property bool completed: false

        onRunningChanged: {
            if (running) {
                completed = false
            } else if (!completed) {
                root.lastError = "dcal could not be started"
                root.lastErrorKind = "missing"
                root.notifyLauncher()
            }
        }

        stdout: StdioCollector {
            onStreamFinished: {
                tasksProcess.completed = true
                const result = TaskItems.parseTasks(text)
                if (result.ok) {
                    root.tasks = result.tasks
                    root.tasksLoaded = true
                    root.lastError = ""
                    root.lastErrorKind = ""
                } else {
                    root.lastError = result.error
                    root.lastErrorKind = result.kind
                }
            }
        }

        onExited: {
            root.notifyLauncher()
            if (root.refreshPending) {
                root.refreshPending = false
                root.refresh()
            }
        }
    }

    Process {
        id: calendarsProcess
        command: ["dcal", "ipc", "calendars.list"]
        running: false

        // See tasksProcess.completed above.
        property bool completed: false

        onRunningChanged: {
            if (running) {
                completed = false
            } else if (!completed) {
                root.lastError = "dcal could not be started"
                root.lastErrorKind = "missing"
                root.notifyLauncher()
            }
        }

        stdout: StdioCollector {
            onStreamFinished: {
                calendarsProcess.completed = true
                const result = TaskItems.parseCalendars(text)
                if (result.ok) {
                    root.calendars = result.calendars
                    root.calendarsLoaded = true
                }
            }
        }

        onExited: root.notifyLauncher()
    }

    Process {
        id: mutateProcess
        running: false

        property string actionType: ""
        // Same start-failure trap as the read processes: when the binary cannot
        // be started, Quickshell fires neither exited nor streamFinished.
        property bool settled: false

        stderr: StdioCollector {
            id: mutateStderr
        }

        onRunningChanged: {
            if (running) {
                settled = false
            } else if (!settled) {
                root.reportMutationFailure("")
            }
        }

        // Force the next getItems to refetch rather than serve the pre-mutation
        // cache. The launcher normally closes right after executeItem, so this
        // is usually observed on the next open.
        onExited: exitCode => {
            settled = true
            if (exitCode !== 0)
                root.reportMutationFailure(mutateStderr.text)

            root.lastRefreshMs = 0
            root.refresh()
        }
    }

    // The launcher closes itself the moment executeItem returns, so a toast is
    // the only surface left to tell the user the write did not happen.
    function reportMutationFailure(stderrText) {
        const failure = TaskItems.mutationFailure(mutateProcess.actionType, stderrText)
        if (typeof ToastService !== "undefined")
            ToastService.showError(failure.message, failure.details)
        else
            console.warn("dcalTasks:", failure.message, "-", failure.details)
    }
}
