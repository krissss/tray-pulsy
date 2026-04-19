import Foundation

extension Notification.Name {
    static let skinChanged             = Notification.Name("com.runcatx.skinChanged")
    static let speedSourceChanged      = Notification.Name("com.runcatx.speedSourceChanged")
    static let fpsLimitChanged         = Notification.Name("com.runcatx.fpsLimitChanged")
    static let sampleIntervalChanged   = Notification.Name("com.runcatx.sampleIntervalChanged")
    static let themeChanged            = Notification.Name("com.runcatx.themeChanged")
    static let metricTextChanged       = Notification.Name("com.runcatx.metricTextChanged")
    static let externalSkinPathChanged = Notification.Name("com.runcatx.externalSkinPathChanged")
}

func postNotification(_ name: Notification.Name, object: Any? = nil) {
    NotificationCenter.default.post(name: name, object: object)
}
