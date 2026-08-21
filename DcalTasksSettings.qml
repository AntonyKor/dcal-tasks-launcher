import QtQuick
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import "TaskItems.js" as TaskItems

PluginSettings {
    id: root

    pluginId: "dcalTasks"

    property var calendarOptions: [{label: "Loading task lists…", value: ""}]

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
                root.calendarOptions = [{label: "dcal could not be started", value: ""}]
            }
        }

        stdout: StdioCollector {
            onStreamFinished: {
                calendarsProcess.completed = true
                const result = TaskItems.parseCalendars(text)
                if (!result.ok) {
                    root.calendarOptions = [{label: "dcal is not running", value: ""}]
                    return
                }

                const options = []
                for (const id in result.calendars) {
                    const cal = result.calendars[id]
                    if (!cal.holdsTasks || cal.readOnly)
                        continue
                    options.push({
                        label: cal.accountName ? cal.accountName + " — " + cal.name : cal.name,
                        value: cal.id
                    })
                }
                options.sort((a, b) => a.label < b.label ? -1 : (a.label > b.label ? 1 : 0))

                root.calendarOptions = options.length > 0
                    ? options
                    : [{label: "No writable task lists found", value: ""}]
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

    ToggleSetting {
        settingKey: "showCompleted"
        label: "Show completed tasks"
        description: "List completed tasks below the open ones"
        defaultValue: false
    }
}
