pragma Singleton

import QtQuick
import Quickshell
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
    //    category: string ("chat" | "system" | "other"),
    //    unread: bool,
    //    actions: array of { key: string, text: string, rawAction: var },
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

    function classifyCategory(appName, summary, body, hints) {
        var str = ((appName || "") + " " + (summary || "") + " " + (body || "")).toLowerCase()
        
        // Check chat / messaging keywords & apps
        var chatKeywords = [
            "chat", "im", "message", "telegram", "discord", "slack", "signal",
            "whatsapp", "element", "matrix", "wechat", "viber", "skype", "teams",
            "messenger", "sms", "irc", "zulip", "revolt"
        ]
        for (var i = 0; i < chatKeywords.length; i++) {
            if (str.indexOf(chatKeywords[i]) !== -1) return "chat"
        }

        // Check system keywords & apps
        var systemKeywords = [
            "system", "update", "battery", "power", "network", "wifi", "bluetooth",
            "disk", "device", "usb", "audio", "volume", "brightness", "security",
            "hyprland", "quickshell", "kernel", "package", "pacman", "dnf", "apt"
        ]
        for (var j = 0; j < systemKeywords.length; j++) {
            if (str.indexOf(systemKeywords[j]) !== -1) return "system"
        }

        return "other"
    }

    function formatTime(date) {
        var now = new Date()
        var diffMs = now.getTime() - date.getTime()
        var diffSec = Math.floor(diffMs / 1000)
        var diffMin = Math.floor(diffSec / 60)
        var diffHour = Math.floor(diffMin / 60)

        if (diffSec < 60) return "Just now"
        if (diffMin < 60) return diffMin + "m ago"
        if (diffHour < 24) return diffHour + "h ago"
        
        var h = date.getHours()
        var m = date.getMinutes()
        var mStr = m < 10 ? ("0" + m) : m
        return h + ":" + mStr
    }

    function addNotification(notif) {
        if (!notif) return

        // Extract actions
        var parsedActions = []
        if (notif.actions) {
            var actCount = notif.actions.length !== undefined ? notif.actions.length : (notif.actions.count || 0)
            for (var a = 0; a < actCount; a++) {
                var act = notif.actions[a]
                if (act) {
                    parsedActions.push({
                        key: act.identifier || act.key || ("action_" + a),
                        text: act.text || act.name || "Action",
                        rawAction: act
                    })
                }
            }
        }

        var now = new Date()
        var h = now.getHours()
        var m = now.getMinutes()
        var timeLabel = (h < 10 ? "0" + h : h) + ":" + (m < 10 ? "0" + m : m)

        var app = notif.appName || "Application"
        var sum = notif.summary || ""
        var bod = notif.body || ""
        var iconStr = notif.appIcon || ""

        var item = {
            id: notif.id !== undefined ? notif.id : ("notif_" + Date.now() + "_" + Math.random()),
            rawNotification: notif,
            appName: app,
            summary: sum,
            body: bod,
            appIcon: iconStr,
            timeStr: timeLabel,
            timestamp: now.getTime(),
            urgency: notif.urgency !== undefined ? notif.urgency : 1,
            category: classifyCategory(app, sum, bod, notif.hints),
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
        }

        root.markRead(item.id)
    }

    function clearAll() {
        for (var i = 0; i < root.list.length; i++) {
            var it = root.list[i]
            if (it.rawNotification && typeof it.rawNotification.dismiss === "function") {
                try {
                    it.rawNotification.dismiss()
                } catch(e) {}
            }
        }
        root.list = []
        root.unreadCount = 0
        root.allCleared()
    }

    // Connect to Quickshell NotificationServer
    Connections {
        target: root.server
        ignoreUnknownSignals: true

        function onNotification(notification) {
            if (!notification) return
            notification.tracked = true
            root.addNotification(notification)
        }
    }
}
