import AVFoundation
import AVKit
import os
import UIKit

private let logger = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "love.muyu.flclash",
  category: "BackgroundKeepAlive"
)

/// Keeps the app alive in the background on iOS so the system does not
/// suspend it. Two mechanisms, both making iOS treat the app as still in
/// use:
/// - silent audio: a looping silent buffer through AVAudioEngine. The
///   `audio` background mode lets it keep playing after the app backgrounds.
///   The session mixes with other audio so it never interrupts music.
/// - picture-in-picture: a tiny looping black video. When the app enters
///   the background the PiP window opens, which keeps the app running.
/// The mode is owned by Dart (AppSettingProps.backgroundKeepAliveMode) and
/// pushed here through the service channel; this class only starts and
/// stops the mechanism that is asked for.
final class BackgroundKeepAlive: NSObject {
  static let shared = BackgroundKeepAlive()

  private enum Mode {
    case off
    case silentAudio
    case pictureInPicture
  }

  private var mode: Mode = .off
  private var audioEngine: AVAudioEngine?
  private var audioPlayerNode: AVAudioPlayerNode?
  private var pipPlayer: AVQueuePlayer?
  private var pipLooper: AVPlayerLooper?
  private var pipPlayerLayer: AVPlayerLayer?
  private var pipContainerView: UIView?
  private var pipController: AVPictureInPictureController?
  private var pipPossibleObserver: NSKeyValueObservation?
  private var pipRetryTimer: Timer?
  private var pipRetryCount = 0
  private var pipArmed = false
  private var pipRetryExhausted = false
  private var foregroundObserver: NSObjectProtocol?
  private var backgroundObserver: NSObjectProtocol?

  override private init() {
    // Swift two-phase init: super.init() first — the observer closures
    // below capture self and cannot run before the superclass is ready.
    super.init()
    backgroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didEnterBackgroundNotification,
      object: nil,
      queue: .main,
    ) { [weak self] _ in
      self?.didEnterBackground()
    }
    foregroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.willEnterForegroundNotification,
      object: nil,
      queue: .main,
    ) { [weak self] _ in
      self?.willEnterForeground()
    }
  }

  deinit {
    if let backgroundObserver {
      NotificationCenter.default.removeObserver(backgroundObserver)
    }
    if let foregroundObserver {
      NotificationCenter.default.removeObserver(foregroundObserver)
    }
    pipPossibleObserver?.invalidate()
    pipRetryTimer?.invalidate()
  }

  /// The mode name Dart sends; unknown values stop the keepalive. Returns
  /// whether the requested mode is actually running: a failed start returns
  /// false (PiP reports armed; its window only opens on backgrounding).
  func setMode(_ name: String) -> Bool {
    let next: Mode
    switch name {
    case "silentAudio":
      next = .silentAudio
    case "pictureInPicture":
      next = .pictureInPicture
    default:
      next = .off
    }
    if next == mode {
      return isArmed(next)
    }
    mode = next
    stopAll()
    switch next {
    case .off:
      return true
    case .silentAudio:
      return startSilentAudio()
    case .pictureInPicture:
      return startPictureInPicture()
    }
  }

  private func isArmed(_ mode: Mode) -> Bool {
    switch mode {
    case .off:
      return true
    case .silentAudio:
      return audioEngine != nil
    case .pictureInPicture:
      if pipArmed {
        return true
      }
      return startPictureInPicture()
    }
  }

  private func stopAll() {
    stopSilentAudio()
    stopPictureInPicture()
  }

  // MARK: - Silent audio

  private func startSilentAudio() -> Bool {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(
        .playback,
        mode: .default,
        options: [.mixWithOthers],
      )
      try session.setActive(true)
    } catch {
      logger.error("silent audio keepalive failed to activate audio session: \(error.localizedDescription, privacy: .public)")
      return false
    }
    let engine = AVAudioEngine()
    let playerNode = AVAudioPlayerNode()
    engine.attach(playerNode)
    let format = AVAudioFormat(
      standardFormatWithSampleRate: 44100,
      channels: 1,
    )
    guard let format else {
      logger.error("silent audio keepalive failed: no audio format")
      return false
    }
    engine.connect(playerNode, to: engine.mainMixerNode, format: format)
    // One second of silence, looped forever. The buffer is all zeros, so
    // nothing is audible; the point is only that audio keeps playing.
    guard let buffer = AVAudioPCMBuffer(
      pcmFormat: format,
      frameCapacity: AVAudioFrameCount(format.sampleRate),
    ) else {
      logger.error("silent audio keepalive failed: no audio buffer")
      return false
    }
    buffer.frameLength = buffer.frameCapacity
    if let channelData = buffer.floatChannelData {
      memset(channelData[0], 0, Int(buffer.frameLength) * MemoryLayout<Float>.size)
    }
    playerNode.scheduleBuffer(buffer, at: nil, options: .loops)
    engine.prepare()
    do {
      try engine.start()
    } catch {
      logger.error("silent audio keepalive failed to start engine: \(error.localizedDescription, privacy: .public)")
      return false
    }
    playerNode.play()
    audioEngine = engine
    audioPlayerNode = playerNode
    return true
  }

  private func stopSilentAudio() {
    audioPlayerNode?.stop()
    audioEngine?.stop()
    audioPlayerNode = nil
    audioEngine = nil
    if mode != .silentAudio {
      try? AVAudioSession.sharedInstance().setActive(false)
    }
  }

  // MARK: - Picture-in-picture

  /// A playback session so the video keeps playing after the app
  /// backgrounds. Silent audio sets its own up; PiP needs the same one.
  private func activatePlaybackSession() {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(
        .playback,
        mode: .default,
        options: [.mixWithOthers],
      )
      try session.setActive(true)
    } catch {
      // PiP can still start without it; the session only makes background
      // playback reliable.
    }
  }

  private func startPictureInPicture() -> Bool {
    guard AVPictureInPictureController.isPictureInPictureSupported() else {
      logger.error("PiP keepalive unavailable: picture in picture not supported")
      return false
    }
    guard let videoURL = Bundle.main.url(
      forResource: "keepalive",
      withExtension: "mp4",
    ) else {
      logger.error("PiP keepalive unavailable: keepalive.mp4 missing from bundle")
      return false
    }
    activatePlaybackSession()
    let item = AVPlayerItem(url: videoURL)
    let player = AVQueuePlayer(playerItem: item)
    // Loop seamlessly. The old seek-to-zero-and-play loop left the player
    // paused between loops, which is exactly when PiP refuses to start.
    let looper = AVPlayerLooper(player: player, templateItem: item)
    let layer = AVPlayerLayer(player: player)
    // PiP can only start when the layer is in a view hierarchy, so host it
    // in a 1x1 view in the key window. The view itself is invisible; the
    // PiP window is what the user sees.
    let container = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
    layer.frame = container.bounds
    container.layer.addSublayer(layer)
    guard attachPipContainer(container) else {
      logger.error("PiP keepalive not armed: no key window to host the player layer")
      return false
    }
    guard let controller = AVPictureInPictureController(playerLayer: layer) else {
      container.removeFromSuperview()
      logger.error("PiP keepalive failed: could not create picture in picture controller")
      return false
    }
    controller.delegate = self
    pipPlayer = player
    pipLooper = looper
    pipPlayerLayer = layer
    pipContainerView = container
    pipController = controller
    pipRetryCount = 0
    pipRetryExhausted = false
    pipArmed = true
    // The player is often not ready the instant the app backgrounds, so
    // PiP is impossible at that moment and never retried. Watch for it
    // becoming possible and start it then.
    pipPossibleObserver = controller.observe(
      \.isPictureInPicturePossible,
      options: [.new],
    ) { [weak self] _, change in
      guard change.newValue == true else {
        return
      }
      self?.startPipIfNeeded()
    }
    player.play()
    // Already backgrounded (mode switched while the app was backgrounded):
    // open PiP right away instead of waiting for the next backgrounding.
    if UIApplication.shared.applicationState == .background {
      startPipIfNeeded()
    }
    return true
  }

  private func attachPipContainer(_ container: UIView) -> Bool {
    guard container.superview == nil else {
      return true
    }
    guard let window = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .flatMap({ $0.windows })
      .first(where: { $0.isKeyWindow })
    else {
      return false
    }
    window.addSubview(container)
    return true
  }

  private func stopPictureInPicture() {
    pipPossibleObserver?.invalidate()
    pipPossibleObserver = nil
    pipRetryTimer?.invalidate()
    pipRetryTimer = nil
    pipRetryCount = 0
    pipArmed = false
    pipRetryExhausted = false
    if pipController?.isPictureInPictureActive == true {
      pipController?.stopPictureInPicture()
    }
    pipPlayer?.pause()
    pipPlayer = nil
    pipLooper = nil
    pipPlayerLayer = nil
    pipContainerView?.removeFromSuperview()
    pipContainerView = nil
    pipController = nil
    if mode != .pictureInPicture {
      try? AVAudioSession.sharedInstance().setActive(false)
    }
  }

  private func didEnterBackground() {
    guard mode == .pictureInPicture else {
      return
    }
    if !pipArmed {
      // A foreground start that failed gets one fresh attempt now.
      _ = startPictureInPicture()
    } else if pipRetryExhausted {
      pipRetryCount = 0
      pipRetryExhausted = false
      logger.debug("retrying picture in picture after earlier retries ran out")
    }
    startPipIfNeeded()
  }

  private func willEnterForeground() {
    guard mode == .pictureInPicture else {
      return
    }
    if pipController?.isPictureInPictureActive == true {
      pipController?.stopPictureInPicture()
    }
  }

  private func startPipIfNeeded() {
    guard let controller = pipController,
      !controller.isPictureInPictureActive
    else {
      return
    }
    guard controller.isPictureInPicturePossible else {
      schedulePipRetry()
      return
    }
    pipRetryTimer?.invalidate()
    pipRetryTimer = nil
    pipRetryCount = 0
    pipRetryExhausted = false
    controller.startPictureInPicture()
  }

  private func schedulePipRetry() {
    guard pipRetryCount < 10 else {
      if !pipRetryExhausted {
        pipRetryExhausted = true
        logger.error("picture in picture keepalive gave up after 10 retries; will try again on the next background entry")
      }
      return
    }
    pipRetryTimer?.invalidate()
    pipRetryCount += 1
    pipRetryTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) {
      [weak self] _ in
      self?.startPipIfNeeded()
    }
  }
}

extension BackgroundKeepAlive: AVPictureInPictureControllerDelegate {
  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error,
  ) {
    // The player is often not ready yet on the first attempt; retry shortly.
    schedulePipRetry()
  }
}
