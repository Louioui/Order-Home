import AVFoundation
import Foundation
import Observation
import Speech

// MARK: - Hands-Free Kitchen Voice Controller

@MainActor
@Observable
final class SpeechStepNavigator {
    static let shared = SpeechStepNavigator()

    var isListening: Bool = false
    var recognizedPhrase: String = ""
    var lastCommand: String? = nil
    var permissionDenied: Bool = false
    var isAvailable: Bool {
        speechRecognizer?.isAvailable ?? false
    }

    @ObservationIgnored
    private var audioEngine: AVAudioEngine?
    @ObservationIgnored
    private var speechRecognizer: SFSpeechRecognizer?
    @ObservationIgnored
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored
    private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored
    var onCommand: ((KitchenVoiceCommand) -> Void)?

    enum KitchenVoiceCommand: String {
        case next = "next"
        case previous = "previous"
        case ringBell = "ringBell"
    }

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    /// Sets the command handler callback when voice keywords are detected.
    func configure(onCommand: @escaping (KitchenVoiceCommand) -> Void) {
        self.onCommand = onCommand
    }

    /// Toggles continuous listening for kitchen navigation commands.
    func toggleListening() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }

    func startListening() {
        guard !isListening else { return }

        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch authStatus {
                case .authorized:
                    self.permissionDenied = false
                    AVAudioApplication.requestRecordPermission { [weak self] granted in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            if granted {
                                do {
                                    try self.beginAudioSession()
                                } catch {
                                    self.stopListening()
                                }
                            } else {
                                self.permissionDenied = true
                            }
                        }
                    }
                default:
                    self.permissionDenied = true
                }
            }
        }
    }

    private func beginAudioSession() throws {
        stopListening()

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        audioEngine = AVAudioEngine()
        guard let audioEngine else { return }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Install audio tap
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        isListening = true

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    let transcribed = result.bestTranscription.formattedString
                    self.recognizedPhrase = transcribed
                    self.evaluateTranscription(transcribed)
                }
                if error != nil {
                    self.stopListening()
                }
            }
        }
    }

    func stopListening() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        isListening = false
        recognizedPhrase = ""
    }

    /// Parses incoming spoken text and detects key kitchen commands.
    func evaluateTranscription(_ text: String) {
        let lower = text.lowercased()
        let words = lower.split(separator: " ").map(String.init)
        guard let lastWord = words.last else { return }

        if ["next", "forward", "continue", "skip"].contains(lastWord) {
            triggerCommand(.next, phrase: lastWord)
        } else if ["back", "previous", "reverse", "again"].contains(lastWord) {
            triggerCommand(.previous, phrase: lastWord)
        } else if ["bell", "done", "finish", "served", "ready"].contains(lastWord) {
            triggerCommand(.ringBell, phrase: lastWord)
        }
    }

    private func triggerCommand(_ command: KitchenVoiceCommand, phrase: String) {
        lastCommand = phrase.capitalized
        onCommand?(command)
        // Reset phrase after triggering so we don't repeat immediately
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            if self?.lastCommand == phrase.capitalized {
                self?.lastCommand = nil
            }
        }
    }
}
