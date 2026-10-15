pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import "../Singletons"

/**
 * NotificationService Singleton
 * 
 * Central Notification Data Layer:
 *  - Maintains notifications list in memory with unread status, timestamps, and tab classification (All, Chat, System).
 *  - Tracks unread count for badges and DND state.
 *  - Categorizes notifications based on desktop entry, appName, hints, and summary.
 *  - Exposes actions to invoke freedesktop action keys (via Action.invoke() or D-Bus ActionInvoked) and dismiss (CloseNotification).
 *  - Signals incoming notifications for toast presentation (suppressed when DND is active).
 */
Singleton {
    id: root

    // Reference to Quickshell NotificationServer (bound from shell.qml)
    property var server: null

    // Do Not Disturb state (synced with Theme.dnd)
    property bool dnd: Theme.dnd
    onDndChanged: {
        if (Theme.dnd !== root.dnd) {
            Theme.dnd = root.dnd
        }
    }

    Connections {
        target: Theme
        function onDndChanged() {
            if (root.dnd !== Theme.dnd) {
                root.dnd = Theme.dnd
            }
        }
    }

    function toggleDnd() {
        root.dnd = !root.dnd
    }

    property bool notificationsEnabled: true
    property int toastTimeoutMs: 5000

    FileView {
        id: notifConfigFile
        path: (Quickshell.env("CARBON_CONFIG_DIR") || ((Quickshell.env("HOME") || "") + "/.config/carbon")) + "/carbon-notifications.json"
        watchChanges: true
        blockLoading: true
        printErrors: false
        onLoaded: root.reloadNotifConfig()
        onFileChanged: root.reloadNotifConfig()
    }

    FileView {
        id: hyprNotifConfigFile
        path: ((Quickshell.env("HOME") || "") + "/.config/hypr/carbon-notifications.json")
        watchChanges: true
        blockLoading: true
        printErrors: false
        onLoaded: root.reloadNotifConfig()
        onFileChanged: root.reloadNotifConfig()
    }

    function reloadNotifConfig() {
        try {
            var txt = notifConfigFile.text()
            if (!txt || txt.trim().length === 0) txt = hyprNotifConfigFile.text()
            if (!txt || txt.trim().length === 0) return
            var d = JSON.parse(txt)
            if (d.enabled !== undefined) root.notificationsEnabled = Boolean(d.enabled)
            if (d.dnd !== undefined && Boolean(d.dnd) !== root.dnd) root.dnd = Boolean(d.dnd)
            if (d.timeout !== undefined) root.toastTimeoutMs = Math.max(1000, (parseInt(d.timeout) || 5) * 1000)
        } catch (e) {}
    }

    // List of notification objects stored in memory:
    // [{
    //    id: string/number,
    //    rawNotification: var,
    //    appName: string,
    //    summary: string,
    //    body: string,
    //    appIcon: string,
    //    timeStr: string,
    //    timestamp: number,
    //    urgency: int (0: Low, 1: Normal, 2: Critical),
    //    category: string ("chat" | "system"),
    //    unread: bool,
    //    actions: array of { key: string, text: string, rawAction: var, invoke: function() },
    //    expireTimeout: int
    // }]
    property var list: []
    property int unreadCount: 0

    // Signal emitted when a new notification arrives (carries item data for toast)
    signal notificationArrived(var item)

    // Signal emitted when a specific notification is dismissed or cleared
    signal notificationRemoved(var item)

    // Signal emitted when notifications are cleared
    signal allCleared()

    function classifyCategory(notif) {
        if (!notif) return "system"
        var appName = String(notif.appName || "")
        var desktopEntry = String(notif.desktopEntry || "")
        var hints = notif.hints || {}
        var hintCat = String(hints["category"] || hints.category || "")

        var chatRegex = /discord|vesktop|telegram|signal|element|matrix|slack|whatsapp|thunderbird|hexchat/i
        if (chatRegex.test(appName) || chatRegex.test(desktopEntry) || hintCat === "im.received") {
            return "chat"
        }
        return "system"
    }

    function formatRelativeTime(ts) {
        var diffMs = Date.now() - ts
        var diffSec = Math.floor(diffMs / 1000)
        var diffMin = Math.floor(diffSec / 60)
        var diffHour = Math.floor(diffMin / 60)
        var diffDay = Math.floor(diffHour / 24)

        if (diffSec < 45) return "now"
        if (diffMin < 60) return diffMin + "m"
        if (diffHour < 24) return diffHour + "h"
        return diffDay + "d"
    }

    Timer {
        id: relativeTimeTimer
        interval: 30000
        running: root.list.length > 0
        repeat: true
        onTriggered: {
            var updated = []
            for (var i = 0; i < root.list.length; i++) {
                var it = root.list[i]
                var newTimeStr = root.formatRelativeTime(it.timestamp)
                if (newTimeStr !== it.timeStr) {
                    updated.push(Object.assign({}, it, { timeStr: newTimeStr }))
                } else {
                    updated.push(it)
                }
            }
            root.list = updated
        }
    }

    function cleanBody(raw) {
        if (!raw) return ""
        return String(raw).replace(/<[^>]*>/g, "").trim()
    }

    function addNotification(notif) {
        if (!notif) return
        console.log("[NotificationService] addNotification appName:", notif.appName, "summary:", notif.summary, "body:", notif.body, "desktopEntry:", notif.desktopEntry)

        // Extract actions safely
        var parsedActions = []
        if (notif.actions) {
            var actCount = notif.actions.length !== undefined ? notif.actions.length : (notif.actions.count || 0)
            for (var a = 0; a < actCount; a++) {
                var act = notif.actions[a]
                if (act) {
                    parsedActions.push({
                        key: act.identifier || act.key || ("action_" + a),
                        text: act.text || act.name || "Action",
                        rawAction: act,
                        invoke: function() {
                            if (this.rawAction && typeof this.rawAction.invoke === "function") {
                                try { this.rawAction.invoke() } catch(e) {}
                            }
                        }
                    })
                }
            }
        }

        var now = Date.now()
        var app = (notif.appName && notif.appName.length > 0)
            ? notif.appName
            : ((notif.desktopEntry && notif.desktopEntry.length > 0) ? notif.desktopEntry : "System")
        var sum = (notif.summary && notif.summary.length > 0)
            ? notif.summary
            : ((notif.title && notif.title.length > 0) ? notif.title : "Notification")
        var bod = root.cleanBody(notif.body)
        var iconStr = notif.appIcon || notif.image || ""

        var item = {
            id: notif.id !== undefined ? notif.id : ("notif_" + now + "_" + Math.floor(Math.random() * 10000)),
            rawNotification: notif,
            appName: app,
            summary: sum,
            body: bod,
            appIcon: iconStr,
            timeStr: root.formatRelativeTime(now),
            timestamp: now,
            urgency: notif.urgency !== undefined ? notif.urgency : 1,
            category: root.classifyCategory(notif),
            unread: true,
            actions: parsedActions,
            expireTimeout: notif.expireTimeout !== undefined ? notif.expireTimeout : -1
        }

        // Insert at beginning of list (newest first)
        var nextList = [item].concat(root.list)
        root.list = nextList
        root.recalculateUnread()

        // Emit signal for toast and live panels
        root.notificationArrived(item)
    }

    function recalculateUnread() {
        var count = 0
        for (var i = 0; i < root.list.length; i++) {
            if (root.list[i].unread) count++
        }
        root.unreadCount = count
    }

    function markRead(id) {
        var changed = false
        var next = []
        for (var i = 0; i < root.list.length; i++) {
            var it = root.list[i]
            if (it.id === id && it.unread) {
                var copy = Object.assign({}, it, { unread: false })
                next.push(copy)
                changed = true
            } else {
                next.push(it)
            }
        }
        if (changed) {
            root.list = next
            root.recalculateUnread()
        }
    }

    function markAllRead() {
        var next = []
        for (var i = 0; i < root.list.length; i++) {
            next.push(Object.assign({}, root.list[i], { unread: false }))
        }
        root.list = next
        root.recalculateUnread()
    }

    function dismiss(id) {
        var removedItem = null
        var next = []
        for (var i = 0; i < root.list.length; i++) {
            var it = root.list[i]
            if (it.id === id) {
                removedItem = it
                if (it.rawNotification && typeof it.rawNotification.dismiss === "function") {
                    try {
                        it.rawNotification.dismiss()
                    } catch(e) {
                        console.warn("[NotificationService] Error dismissing rawNotification:", e)
                    }
                }
            } else {
                next.push(it)
            }
        }
        root.list = next
        root.recalculateUnread()
        if (removedItem) {
            root.notificationRemoved(removedItem)
        }
    }

    function invokeAction(item, actionObj) {
        if (!item || !actionObj) return
        
        if (actionObj.rawAction && typeof actionObj.rawAction.invoke === "function") {
            try {
                actionObj.rawAction.invoke()
            } catch(e) {
                console.warn("[NotificationService] Error invoking rawAction:", e)
            }
        } else if (typeof actionObj.invoke === "function") {
            try {
                actionObj.invoke()
            } catch(e) {
                console.warn("[NotificationService] Error invoking actionObj:", e)
            }
        }

        root.markRead(item.id)
    }

    function clearCategory(cat) {
        var normalizedCat = String(cat || "all").toLowerCase()
        var toDismiss = []
        var remaining = []
        for (var i = 0; i < root.list.length; i++) {
            var it = root.list[i]
            if (normalizedCat === "all" || it.category === normalizedCat) {
                toDismiss.push(it)
            } else {
                remaining.push(it)
            }
        }

        for (var j = 0; j < toDismiss.length; j++) {
            var item = toDismiss[j]
            if (item.rawNotification && typeof item.rawNotification.dismiss === "function") {
                try {
                    item.rawNotification.dismiss()
                } catch(e) {}
            }
        }

        root.list = remaining
        root.recalculateUnread()
        root.allCleared()
    }

    function clearAll() {
        root.clearCategory("all")
    }


}
