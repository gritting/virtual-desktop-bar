pragma Singleton
import QtQuick
import org.kde.taskmanager as TaskManager
import "../common" as Common

QtObject {
    id: root

    property TaskManager.TasksModel tasksModel: TaskManager.TasksModel {
        id: tasksModel
        filterByVirtualDesktop: true
        filterByActivity: true
        filterByScreen: false
        screenGeometry: Qt.rect(0, 0, 0, 0)
    }

    property var activeWindowCache: ({})

    signal screenFilteringChanged()

    function setScreenFiltering(enabled, geometry) {
        // Retained for compatibility with older call sites. The actual screen-scoped state
        // must be provided per call and not stored on the shared singleton.
        if (enabled && geometry) {
            tasksModel.filterByScreen = true;
            tasksModel.screenGeometry = geometry;
        } else {
            tasksModel.filterByScreen = false;
            tasksModel.screenGeometry = Qt.rect(0, 0, 0, 0);
        }
        screenFilteringChanged();
    }

    function withDesktopContext(desktopUuid, activityId, callback, screenFilteringEnabled = false, screenGeometry = Qt.rect(0, 0, 0, 0)) {
        if (!desktopUuid) {
            return callback();
        }

        const oldVirtualDesktop = tasksModel.virtualDesktop;
        const oldActivity = tasksModel.activity;
        const oldFilterByScreen = tasksModel.filterByScreen;
        const oldScreenGeometry = tasksModel.screenGeometry;

        tasksModel.virtualDesktop = desktopUuid;
        tasksModel.activity = activityId || "";
        tasksModel.filterByScreen = screenFilteringEnabled;
        tasksModel.screenGeometry = screenFilteringEnabled ? (screenGeometry || Qt.rect(0, 0, 0, 0)) : Qt.rect(0, 0, 0, 0);

        try {
            return callback();
        } finally {
            tasksModel.virtualDesktop = oldVirtualDesktop;
            tasksModel.activity = oldActivity;
            tasksModel.filterByScreen = oldFilterByScreen;
            tasksModel.screenGeometry = oldScreenGeometry;
        }
    }

    function getActiveWindowName(desktopUuid, activityId, screenFilteringEnabled = false, screenGeometry = Qt.rect(0, 0, 0, 0)) {
        if (!desktopUuid) return "";

        return withDesktopContext(desktopUuid, activityId, function() {
            for (let i = 0; i < tasksModel.count; i++) {
                const taskIndex = tasksModel.index(i, 0);
                const isActive = tasksModel.data(taskIndex, TaskManager.AbstractTasksModel.IsActive);

                if (isActive) {
                    const displayName = tasksModel.data(taskIndex, TaskManager.AbstractTasksModel.DisplayRole) || "";
                    activeWindowCache[desktopUuid] = displayName;
                    return displayName;
                }
            }

            activeWindowCache[desktopUuid] = "";
            return "";
        }, screenFilteringEnabled, screenGeometry);
    }

    function hasWindows(desktopUuid, activityId, screenFilteringEnabled = false, screenGeometry = Qt.rect(0, 0, 0, 0)) {
        if (!desktopUuid) return false;

        return withDesktopContext(desktopUuid, activityId, function() {
            return tasksModel.count > 0;
        }, screenFilteringEnabled, screenGeometry);
    }

    function getWindowsForDesktop(desktopUuid, activityId, screenFilteringEnabled = false, screenGeometry = Qt.rect(0, 0, 0, 0)) {
        const windows = [];
        if (!desktopUuid) return windows;

        return withDesktopContext(desktopUuid, activityId, function() {
            for (let i = 0; i < tasksModel.count; i++) {
                const taskIndex = tasksModel.index(i, 0);
                const appId = tasksModel.data(taskIndex, TaskManager.AbstractTasksModel.AppId) || "application-x-executable";
                const appName = tasksModel.data(taskIndex, TaskManager.AbstractTasksModel.AppName) || "Unknown Application";
                const isActive = tasksModel.data(taskIndex, TaskManager.AbstractTasksModel.IsActive) || false;
                const genericName = tasksModel.data(taskIndex, TaskManager.AbstractTasksModel.GenericName) || "";
                const isDemandingAttention = tasksModel.data(taskIndex, TaskManager.AbstractTasksModel.IsDemandingAttention) || false;
                const rawWinId = tasksModel.data(taskIndex, TaskManager.AbstractTasksModel.WinIdList) || []
                const rawActivities = tasksModel.data(taskIndex, TaskManager.AbstractTasksModel.Activities || []);
                const desktopList = tasksModel.data(taskIndex, TaskManager.AbstractTasksModel.VirtualDesktops);
                const skipPager = tasksModel.data(taskIndex, TaskManager.AbstractTasksModel.SkipPager) || false;
                const skipTaskBar = false;

                if (skipPager || skipTaskBar) {
                    continue;
                }

                if (!String(desktopList).includes(desktopUuid)) { continue; }

                let str = String(rawWinId);
                let matches = str.match(/{([^}]+)}/);
                const winId = matches && matches[1] ? matches[1] : str;

                str = String(rawActivities);
                matches = str.match(/{([^}]+)}/);
                const taskActivities = matches && matches[1] ? matches[1] : str;

                windows.push({
                    appId: appId,
                    appName: appName,
                    isActive: isActive,
                    genericName: genericName,
                    isDemandingAttention: isDemandingAttention,
                    winId: winId,
                    activityId: taskActivities,
                    skipTaskBar: skipTaskBar,
                    skipPager: skipPager,
                });
            }

            return windows;
        }, screenFilteringEnabled, screenGeometry);
    }

    function desktopNeedsAttention(desktopUuid, activityId, screenFilteringEnabled = false, screenGeometry = Qt.rect(0, 0, 0, 0)) {
        if (!desktopUuid) return false;

        return withDesktopContext(desktopUuid, activityId, function() {
            for (let i = 0; i < tasksModel.count; i++) {
                const taskIndex = tasksModel.index(i, 0);
                const isDemandingAttention = tasksModel.data(taskIndex, TaskManager.AbstractTasksModel.IsDemandingAttention);
                const desktopList = tasksModel.data(taskIndex, TaskManager.AbstractTasksModel.VirtualDesktops);
                if ((desktopList && String(desktopList).includes(desktopUuid)) && isDemandingAttention) {
                    return true;
                }
            }

            return false;
        }, screenFilteringEnabled, screenGeometry);
    }

    function activateWindow(winId, desktopId, activityId) {
        if (!winId || !desktopId || !activityId) return false;

        return withDesktopContext(desktopId, activityId, function() {
            for (let i = 0; i < tasksModel.count; i++) {
                const taskIndex = tasksModel.index(i, 0);
                let rawWinId = tasksModel.data(taskIndex, TaskManager.AbstractTasksModel.WinIdList) || [];

                const str = String(rawWinId);
                const matches = str.match(/{([^}]+)}/);
                const compWinId = matches && matches[1] ? matches[1] : str;

                if (winId === compWinId) {
                    tasksModel.requestActivate(taskIndex);
                }
            }
        });
    }

    // Request entering the window at the given index on the specified virtual desktops.
    // On Wayland, virtual desktop ids are QStrings. On X11, they are uint >0.
    // An empty list has a special meaning: The window is entered on all virtual desktops in the session.
    // On X11, a window can only be on one or all virtual desktops. Therefore, only the first list entry is actually used.
    // On X11, the id 0 has a special meaning: The window is entered on all virtual desktops in the session.
    function requestVirtualDesktops(winId, sourceDesktopId, destDesktopIdList, activityId) {
        if (!winId || !sourceDesktopId || !activityId) return false;

        return withDesktopContext(sourceDesktopId, activityId, function() {
            for (let i = 0; i < tasksModel.count; i++) {
                const taskIndex = tasksModel.index(i, 0);
                let rawWinId = tasksModel.data(taskIndex, TaskManager.AbstractTasksModel.WinIdList) || [];

                const str = String(rawWinId);
                const matches = str.match(/{([^}]+)}/);
                const compWinId = matches && matches[1] ? matches[1] : str;

                if (winId === compWinId) {
                    tasksModel.requestVirtualDesktops(taskIndex, destDesktopIdList);
                }
            }
        });
    }
}
