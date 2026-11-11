import AVFoundation
import AVKit
import UIKit

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
final class BackgroundKeepAlive {
  static let shared = BackgroundKeepAlive()

  private enum Mode {
    case off
    case silentAudio
    case pictureInPicture
  }

  private var mode: Mode = .off
  private var audioEngine: AVAudioEngine?
  private var audioPlayerNode: AVAudioPlayerNode?
  private var pipPlayer: AVPlayer?
  private var pipPlayerLayer: AVPlayerLayer?
  private var pipContainerView: UIView?
  private var pipController: AVPictureInPictureController?
  private var pipObserver: NSObjectProtocol?
  private var foregroundObserver: NSObjectProtocol?
  private var backgroundObserver: NSObjectProtocol?

  private init() {
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
    if let pipObserver {
      NotificationCenter.default.removeObserver(pipObserver)
    }
  }

  /// The mode name Dart sends: "off", "silentAudio", "pictureInPicture".
  /// Unknown values stop the keepalive.
  func setMode(_ name: String) {
    let next: Mode
    switch name {
    case "silentAudio":
      next = .silentAudio
    case "pictureInPicture":
      next = .pictureInPicture
    default:
      next = .off
    }
    guard next != mode else {
      return
    }
    mode = next
    stopAll()
    switch next {
    case .off:
      break
    case .silentAudio:
      startSilentAudio()
    case .pictureInPicture:
      startPictureInPicture()
    }
  }

  private func stopAll() {
    stopSilentAudio()
    stopPictureInPicture()
  }

  // MARK: - Silent audio

  private func startSilentAudio() {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(
        .playback,
        mode: .default,
        options: [.mixWithOthers],
      )
      try session.setActive(true)
    } catch {
      return
    }
    let engine = AVAudioEngine()
    let playerNode = AVAudioPlayerNode()
    engine.attach(playerNode)
    let format = AVAudioFormat(
      standardFormatWithSampleRate: 44100,
      channels: 1,
    )
    guard let format else {
      return
    }
    engine.connect(playerNode, to: engine.mainMixerNode, format: format)
    // One second of silence, looped forever. The buffer is all zeros, so
    // nothing is audible; the point is only that audio keeps playing.
    guard let buffer = AVAudioPCMBuffer(
      pcmFormat: format,
      frameCapacity: AVAudioFrameCount(format.sampleRate),
    ) else {
      return
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
      return
    }
    playerNode.play()
    audioEngine = engine
    audioPlayerNode = playerNode
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

  private func startPictureInPicture() {
    guard AVPictureInPictureController.isPictureInPictureSupported() else {
      return
    }
    guard let videoURL = Bundle.main.url(
      forResource: "keepalive",
      withExtension: "mp4",
    ) else {
      return
    }
    let player = AVPlayer(url: videoURL)
    player.actionAtItemEnd = .none
    pipObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: player.currentItem,
      queue: .main,
    ) { _ in
      player.seek(to: .zero)
      player.play()
    }
    let layer = AVPlayerLayer(player: player)
    // PiP can only start when the layer is in a view hierarchy, so host it
    // in a 1x1 view in the key window. The view itself is invisible; the
    // PiP window is what the user sees.
    let container = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
    layer.frame = container.bounds
    container.layer.addSublayer(layer)
    if let window = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .flatMap({ $0.windows })
      .first(where: { $0.isKeyWindow })
    {
      window.addSubview(container)
    }
    let controller = AVPictureInPictureController(playerLayer: layer)
    pipPlayer = player
    pipPlayerLayer = layer
    pipContainerView = container
    pipController = controller
    player.play()
    // Already backgrounded (mode switched while the app was backgrounded):
    // open PiP right away instead of waiting for the next backgrounding.
    if UIApplication.shared.applicationState == .background {
      startPipIfNeeded()
    }
  }

  private func stopPictureInPicture() {
    if let pipObserver {
      NotificationCenter.default.removeObserver(pipObserver)
      self.pipObserver = nil
    }
    if pipController?.isPictureInPictureActive == true {
      pipController?.stopPictureInPicture()
    }
    pipPlayer?.pause()
    pipPlayer = nil
    pipPlayerLayer = nil
    pipContainerView?.removeFromSuperview()
    pipContainerView = nil
    pipController = nil
  }

  private func didEnterBackground() {
    guard mode == .pictureInPicture else {
      return
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
      !controller.isPictureInPictureActive,
      controller.isPictureInPicturePossible
    else {
      return
    }
    controller.startPictureInPicture()
  }
}
