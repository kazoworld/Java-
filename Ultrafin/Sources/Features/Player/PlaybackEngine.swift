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
}

#if canImport(UIKit)
import UIKit
typealias PlatformView = UIView
#else
import AppKit
typealias PlatformView = NSView
#endif
