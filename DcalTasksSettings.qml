import QtQuick
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import "TaskItems.js" as TaskItems

PluginSettings {
    id: root

    pluginId: "dcalTasks"

    // Option 0 must never change its label. DankDropdown feeds its ListView
    // through a ScriptModel, which reuses delegates by value; swapping index 0
    // out from under a built delegate leaves the old text rendered behind the
    // new one. So the prompt is the permanent first entry in every state, real
    // lists are appended to it, and failures go to calendarStatus below the
    // picker instead of into the option list. The prompt also gives the closed
    // dropdown a label for the unset "" value, which it otherwise renders blank.
    readonly property var promptOption: ({label: "Select a task list", value: ""})

    property var calendarOptions: [root.promptOption]
    property string calendarStatus: ""

    Component.onCompleted: calendarsProcess.running = true

    Process {
        id: calendarsProcess
        command: ["dcal", "ipc", "calendars.list"]
        running: false

        // See DcalTasksLauncher.qml's tasksProcess.completed: Quickshell's
        // Process fires neither exited nor StdioCollector.onStreamFinished
        // when the binary itself cannot be started, only onRunningChanged.
        property bool completed: false

        onRunningChanged: {
            if (running) {
                completed = false
            } else if (!completed) {
                root.calendarStatus = "dcal could not be started. Is it installed and on your PATH?"
                root.calendarOptions = [root.promptOption]
            }
        }

        stdout: StdioCollector {
            onStreamFinished: {
                calendarsProcess.completed = true
                const result = TaskItems.parseCalendars(text)
                if (!result.ok) {
                    root.calendarStatus = "dcal is not running. Start it with: dcal run -d"
                    root.calendarOptions = [root.promptOption]
                    return
                }

                const options = TaskItems.taskListOptions(result.calendars)
                root.calendarStatus = options.length > 0 ? "" : "No writable task lists found in dcal."
                root.calendarOptions = [root.promptOption].concat(options)
            }
        }
    }

    StyledText {
        width: parent.width
        text: "Reload the plugin after changing the trigger."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "trigger"
        label: "Trigger prefix"
        description: "Type this prefix in the launcher to reach your tasks"
        placeholder: ";"
        defaultValue: ";"
    }

    SelectionSetting {
        settingKey: "defaultCalendarId"
        label: "Default task list"
        description: "New tasks are created in this list"
        defaultValue: ""
        options: root.calendarOptions
    }

    StyledText {
        width: parent.width
        text: root.calendarStatus
        visible: root.calendarStatus !== ""
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.error
        wrapMode: Text.WordWrap
    }

    SelectionSetting {
        settingKey: "defaultView"
        label: "Show by default"
        description: "Which tasks are listed before you type anything. Searching always covers every list."
        defaultValue: "all"
        options: [
            {label: "All tasks", value: "all"},
            {label: "Due today and overdue", value: "today"},
            {label: "Default task list only", value: "defaultList"}
        ]
    }

    ToggleSetting {
        settingKey: "showCompleted"
        label: "Show completed tasks"
        description: "List completed tasks below the open ones"
        defaultValue: false
    }
}
