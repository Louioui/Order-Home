import Foundation
import UserNotifications
import AVFoundation

/// Local kitchen timer alerts. Permission is requested only after a timer is started.
@MainActor
final class KitchenNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = KitchenNotifications()

    enum SchedulingResult {
        case scheduled
        case alertsDisabled
        case superseded
        case failed
    }

    private let center = UNUserNotificationCenter.current()
    private let identifierDefaultsKey = "orderhome.activeTimerNotificationID"
    private var currentRequestIdentifier: String?
    private var timerRevision = 0
    private var bellPlayer: AVAudioPlayer?

    private override init() {
        super.init()
        currentRequestIdentifier = UserDefaults.standard.string(forKey: identifierDefaultsKey)
        installAsDelegate()
    }

    /// Register on launch to show a pending timer's alert while the app is open.
    /// This method never asks for notification permission.
    func installAsDelegate() {
        center.delegate = self
    }

    /// Call only in response to the person's explicit Start Timer action.
    func scheduleTimer(endingAt deadline: Date, title: String) async -> SchedulingResult {
        cancelTimer()
        let revision = timerRevision
        let requestIdentifier = "orderhome.kitchen.timer.\(UUID().uuidString)"
        currentRequestIdentifier = requestIdentifier
        UserDefaults.standard.set(requestIdentifier, forKey: identifierDefaultsKey)

        var settings = await center.notificationSettings()
        guard revision == timerRevision else { return .superseded }
        if settings.authorizationStatus == .notDetermined {
            do {
                let allowed = try await center.requestAuthorization(options: [.alert, .sound])
                guard revision == timerRevision else { return .superseded }
                guard allowed else { return .alertsDisabled }
                settings = await center.notificationSettings()
            } catch {
                return .failed
            }
        }
        guard revision == timerRevision else { return .superseded }
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        default:
            return .alertsDisabled
        }
        guard deadline > .now else { return .superseded }

        let content = UNMutableNotificationContent()
        content.title = "Time’s up, chef!"
        content.body = "\(title) — time to check your food."
        content.sound = .default
        content.threadIdentifier = "orderhome-kitchen"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, deadline.timeIntervalSinceNow), repeats: false)
        let request = UNNotificationRequest(identifier: requestIdentifier, content: content, trigger: trigger)

        do {
            try await center.add(request)
            guard revision == timerRevision else {
                center.removePendingNotificationRequests(withIdentifiers: [requestIdentifier])
                return .superseded
            }
            return .scheduled
        } catch {
            return .failed
        }
    }

    func cancelTimer() {
        timerRevision += 1
        if let identifier = currentRequestIdentifier {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            center.removeDeliveredNotifications(withIdentifiers: [identifier])
        }
        currentRequestIdentifier = nil
        UserDefaults.standard.removeObject(forKey: identifierDefaultsKey)
    }

    private static let cachedBellWaveData = bellWaveData()

    /// A short foreground chime. It respects the device's silent switch and
    /// makes no claim that another person's device has received an alert.
    func playDinnerBell() {
        do {
            bellPlayer = try AVAudioPlayer(data: Self.cachedBellWaveData)
            bellPlayer?.volume = 0.7
            bellPlayer?.play()
        } catch {
            // The view also provides a success haptic and visible served state.
        }
    }

    private static func bellWaveData() -> Data {
        let sampleRate = 22_050
        let sampleCount = sampleRate
        var data = Data()
        func append16(_ value: UInt16) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        func append32(_ value: UInt32) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8)
        append32(UInt32(36 + sampleCount * 2))
        data.append(contentsOf: "WAVEfmt ".utf8)
        append32(16)
        append16(1)
        append16(1)
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate * 2))
        append16(2)
        append16(16)
        data.append(contentsOf: "data".utf8)
        append32(UInt32(sampleCount * 2))
        for index in 0..<sampleCount {
            let time = Double(index) / Double(sampleRate)
            let fundamental = sin(2 * .pi * 880 * time)
            let harmonics = 0.4 * sin(2 * .pi * 1_320 * time) + 0.15 * sin(2 * .pi * 1_760 * time)
            let envelope = min(1, time * 160) * exp(-5 * time)
            let sample = Int16((fundamental + harmonics) * envelope * 14_000)
            append16(UInt16(bitPattern: sample))
        }
        return data
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
