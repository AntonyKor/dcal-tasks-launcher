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
    property double lastRefreshMs: 0

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
        lastRefreshMs = Date.now()
        if (!tasksProcess.running)
            tasksProcess.running = true
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

        stdout: StdioCollector {
            onStreamFinished: {
                const result = TaskItems.parseTasks(text)
                if (result.ok) {
                    root.tasks = result.tasks
                    root.tasksLoaded = true
                    root.lastError = ""
                } else {
                    root.lastError = result.error
                }
            }
        }

        onExited: root.notifyLauncher()
    }

    Process {
        id: calendarsProcess
        command: ["dcal", "ipc", "calendars.list"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
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
