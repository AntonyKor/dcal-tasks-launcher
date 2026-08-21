import QtQuick
import Quickshell.Io
import "TaskItems.js" as TaskItems

Item {
    id: root

    property var pluginService: null
    property string trigger: ";"

    readonly property string pluginName: "dcalTasks"

    signal itemsChanged

    property string defaultCalendarId: ""
    property bool showCompleted: false

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
            showCompleted: root.showCompleted
        }, query || "")
    }

    function executeItem(item) {
        const parsed = TaskItems.parseAction(item ? item.action : "")

        if (parsed.type === "create") {
            if (!defaultCalendarId)
                return
            mutateProcess.command = ["dcal", "ipc", "tasks.create",
                                     "calendarId=" + defaultCalendarId,
                                     "summary=" + parsed.summary]
            mutateProcess.running = true
        } else if (parsed.type === "toggle") {
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

        // Force the next getItems to refetch rather than serve the pre-mutation
        // cache. The launcher normally closes right after executeItem, so this
        // is usually observed on the next open.
        onExited: {
            root.lastRefreshMs = 0
            root.refresh()
        }
    }
}
