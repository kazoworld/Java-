import Foundation
import Combine

/// State broadcast by a playback engine to the view layer.
struct PlaybackState: Equatable {
    enum Status: Equatable { case idle, buffering, playing, paused, ended, failed(String) }
    var status: Status = .idle
    var currentTime: Double = 0      // seconds
    var duration: Double = 0          // seconds
    var bufferedTime: Double = 0      // seconds

    var progress: Double { duration > 0 ? min(1, currentTime / duration) : 0 }
}

/// A selectable subtitle (or audio) track exposed by an engine.
struct MediaTrack: Identifiable, Equatable, Sendable {
    let id: Int
    let name: String
}

/// Abstraction over a concrete media backend (AVFoundation or VLCKit). The view
/// model talks only to this protocol, so the hybrid coordinator can pick the
/// best engine per item without the UI knowing or caring which is in use.
@MainActor
protocol PlaybackEngine: AnyObject {
    /// A SwiftUI/UIKit-embeddable view hosting the video output.
    var playerLayerView: PlatformView { get }

    /// Continuously-updated playback state.
    var statePublisher: AnyPublisher<PlaybackState, Never> { get }

    func load(url: URL, startAt seconds: Double)
    func play()
    func pause()
    func seek(to seconds: Double)
    func teardown()

    /// Subtitle/closed-caption tracks for the loaded media.
    var subtitleTracks: [MediaTrack] { get }
    /// The selected subtitle track id, or `nil` when captions are off.
    var currentSubtitleID: Int? { get }
    /// Select a subtitle track, or `nil` to turn captions off.
    func selectSubtitle(id: Int?)

    /// Selectable audio tracks for the loaded media.
    var audioTracks: [MediaTrack] { get }
    /// The selected audio track id.
    var currentAudioID: Int? { get }
    /// Select an audio track by id.
    func selectAudio(id: Int)
}

// Default (no-op) track support so engines without subtitles still conform.
extension PlaybackEngine {
    var subtitleTracks: [MediaTrack] { [] }
    var currentSubtitleID: Int? { nil }
    func selectSubtitle(id: Int?) {}
    var audioTracks: [MediaTrack] { [] }
    var currentAudioID: Int? { nil }
    func selectAudio(id: Int) {}
}

#if canImport(UIKit)
import UIKit
typealias PlatformView = UIView
#else
import AppKit
typealias PlatformView = NSView
#endif
