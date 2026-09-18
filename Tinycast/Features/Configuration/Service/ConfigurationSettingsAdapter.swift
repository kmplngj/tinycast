import Foundation

@MainActor
enum ConfigurationSettingsAdapter {
    static func gather(_ s: AppSettings) -> ConfigurationValue {
        .object([
            "compactMode": .bool(s.compactMode),
            "showFavoritesInCompactMode": .bool(s.showFavoritesInCompactMode),
            "openOnCursorScreen": .bool(s.openOnCursorScreen),
            "paletteDraggable": .bool(s.paletteDraggable),
            "customCommandsShowInLauncher": .bool(s.customCommandsShowInLauncher),
            "windowManagementEnabled": .bool(s.windowManagementEnabled),
            "windowManagementShowInLauncher": .bool(s.windowManagementShowInLauncher),
            "windowCycle": .string(s.windowCycle.rawValue),
            "windowLayoutsShowInLauncher": .bool(s.windowLayoutsShowInLauncher),
            "quicklinksEnabled": .bool(s.quicklinksEnabled),
            "quicklinksShowInLauncher": .bool(s.quicklinksShowInLauncher),
            "quicklinkOpensNewWindow": .bool(s.quicklinkOpensNewWindow),
            "quicklinkConfirmsBeforeDelete": .bool(s.quicklinkConfirmsBeforeDelete),
            "calendarShowInLauncher": .bool(s.calendarShowInLauncher),
            "calendarIncludesTomorrow": .bool(s.calendarIncludesTomorrow),
            "menuBarLinkedEventsOnly": .bool(s.menuBarLinkedEventsOnly),
            "supportReminders": .bool(s.supportRemindersEnabled),
            "showInMenuBar": .bool(
                UserDefaults.standard.object(forKey: SettingsKey.showInMenuBar) as? Bool ?? true),
            "escapeKeyBehavior": .string(s.escapeKeyBehavior.rawValue),
            "appearance": .string(s.appearance.rawValue),
            "paletteTransparency": .number(Double(s.paletteTransparency)),
            "emojiSkinTone": .string(s.emojiSkinTone.rawValue),
            "quicklinkSelectionFallback": .string(s.quicklinkSelectionFallback.rawValue),
            "popToRootSeconds": .number(Double(s.popToRootTimeout.rawValue)),
            "calendarLauncherLimit": .number(Double(s.calendarLauncherLimit.rawValue)),
            "joinWindowMinutes": .number(Double(s.joinWindowMinutes.rawValue)),
            "menuBarEvents": .number(Double(s.menuBarEvents.rawValue)),
            "calendarMenuBarDisplay": .number(Double(s.calendarMenuBarDisplay.rawValue)),
            "hideCurrentEvent": .number(Double(s.hideCurrentEvent.rawValue)),
            "windowGap": .number(Double(s.windowGap))
        ])
    }

    static func apply(_ value: ConfigurationValue, to s: AppSettings) {
        s.compactMode = value["compactMode"].bool
        s.showFavoritesInCompactMode = value["showFavoritesInCompactMode"].bool
        s.openOnCursorScreen = value["openOnCursorScreen"].bool
        s.paletteDraggable = value["paletteDraggable"].bool
        s.customCommandsShowInLauncher = value["customCommandsShowInLauncher"].bool
        s.windowManagementEnabled = value["windowManagementEnabled"].bool
        s.windowManagementShowInLauncher = value["windowManagementShowInLauncher"].bool
        s.windowCycle = WindowCycle(rawValue: value["windowCycle"].string)!
        s.windowLayoutsShowInLauncher = value["windowLayoutsShowInLauncher"].bool
        s.quicklinksEnabled = value["quicklinksEnabled"].bool
        s.quicklinksShowInLauncher = value["quicklinksShowInLauncher"].bool
        s.quicklinkOpensNewWindow = value["quicklinkOpensNewWindow"].bool
        s.quicklinkConfirmsBeforeDelete = value["quicklinkConfirmsBeforeDelete"].bool
        s.calendarShowInLauncher = value["calendarShowInLauncher"].bool
        s.calendarIncludesTomorrow = value["calendarIncludesTomorrow"].bool
        s.menuBarLinkedEventsOnly = value["menuBarLinkedEventsOnly"].bool
        s.supportRemindersEnabled = value["supportReminders"].bool
        UserDefaults.standard.set(value["showInMenuBar"].bool, forKey: SettingsKey.showInMenuBar)
        s.escapeKeyBehavior = EscapeKeyBehavior(rawValue: value["escapeKeyBehavior"].string)!
        s.appearance = AppAppearance(rawValue: value["appearance"].string)!
        s.paletteTransparency = Int(value["paletteTransparency"].number)
        s.emojiSkinTone = EmojiSkinTone(rawValue: value["emojiSkinTone"].string)!
        s.quicklinkSelectionFallback = QuicklinkSelectionFallback(
            rawValue: value["quicklinkSelectionFallback"].string)!
        s.popToRootTimeout = PopToRootTimeout(rawValue: Int(value["popToRootSeconds"].number))!
        s.calendarLauncherLimit = CalendarLauncherLimit(rawValue: Int(value["calendarLauncherLimit"].number))!
        s.joinWindowMinutes = JoinWindow(rawValue: Int(value["joinWindowMinutes"].number))!
        s.menuBarEvents = MenuBarEvents(rawValue: Int(value["menuBarEvents"].number))!
        s.calendarMenuBarDisplay = CalendarMenuBarDisplay(
            rawValue: Int(value["calendarMenuBarDisplay"].number))!
        s.hideCurrentEvent = HideCurrentEvent(rawValue: Int(value["hideCurrentEvent"].number))!
        s.windowGap = Int(value["windowGap"].number)
    }
}
