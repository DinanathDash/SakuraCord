import AppKit
import Lottie

@MainActor
final class NativeTimelineLottieStickerOverlay: NSView {
    let animationView = LottieAnimationView()
    let progressIndicator = NSProgressIndicator()
    var loadingTask: Task<Void, Never>?
    var url: URL?
    private var reduceMotion = false
    private var isPausedForScroll = false

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        animationView.contentMode = .scaleAspectFit
        animationView.loopMode = .loop
        animationView.isHidden = true
        addSubview(animationView)

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.startAnimation(nil)
        addSubview(progressIndicator)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        animationView.frame = bounds
        animationView.needsLayout = true
        animationView.layoutSubtreeIfNeeded()
        let spinnerSize = progressIndicator.fittingSize
        progressIndicator.frame = CGRect(
            x: (bounds.width - spinnerSize.width) / 2,
            y: (bounds.height - spinnerSize.height) / 2,
            width: spinnerSize.width,
            height: spinnerSize.height
        )
    }

    /// A load that finishes later applies the state from the latest call.
    func display(_ url: URL, reduceMotion: Bool, pausedForScroll: Bool = false) {
        self.reduceMotion = reduceMotion
        isPausedForScroll = pausedForScroll
        if self.url != url {
            stop()
            self.url = url
            animationView.isHidden = true
            progressIndicator.isHidden = false
            progressIndicator.startAnimation(nil)
            loadingTask = Task { @MainActor [weak self] in
                let animation = await SharedTimelineLottieAnimationLoader
                    .shared.animation(for: url)
                guard !Task.isCancelled,
                      let self,
                      self.url == url
                else { return }
                self.loadingTask = nil
                self.animationView.animation = animation
                self.animationView.isHidden = animation == nil
                self.progressIndicator.isHidden = animation != nil
                self.updatePlayback()
            }
        } else {
            updatePlayback()
        }
    }

    private func updatePlayback() {
        animationView.loopMode = .loop
        guard animationView.animation != nil else { return }
        if reduceMotion {
            animationView.pause()
            animationView.currentProgress = 0
        } else if isPausedForScroll {
            animationView.pause()
        } else if !animationView.isAnimationPlaying {
            animationView.play()
        }
    }

    func pauseForScroll() {
        isPausedForScroll = true
        animationView.pause()
    }

    func stop() {
        loadingTask?.cancel()
        loadingTask = nil
        animationView.stop()
        animationView.animation = nil
        url = nil
    }

    deinit {
        loadingTask?.cancel()
    }
}

nonisolated enum TimelineLottieLoadingPolicy {
    static let maximumCachedAnimations = 12
    static let maximumConcurrentParses = 1
}

actor SharedTimelineLottieAnimationLoader {
    static let shared = SharedTimelineLottieAnimationLoader()

    typealias DataLoader = @Sendable (URL) async throws -> Data

    private let cache: DefaultAnimationCache = {
        let cache = DefaultAnimationCache()
        cache.cacheSize = TimelineLottieLoadingPolicy.maximumCachedAnimations
        return cache
    }()
    private struct InFlightLoad {
        let task: Task<LottieAnimation?, Never>
        var waiterCount: Int
    }

    private var inFlight: [URL: InFlightLoad] = [:]
    private var isParsing = false
    private struct ParseWaiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private var parseWaiters: [ParseWaiter] = []
    private let loadData: DataLoader

    init(
        loadData: @escaping DataLoader = { url in
            try await SharedMediaDataLoader.shared.data(
                for: url,
                priority: .visible
            )
        }
    ) {
        self.loadData = loadData
    }

    func animation(for url: URL) async -> LottieAnimation? {
        if let cached = cache.animation(forKey: url.absoluteString) {
            return cached
        }
        let task = inFlight[url]?.task ?? makeLoad(for: url)
        inFlight[url, default: InFlightLoad(task: task, waiterCount: 0)].waiterCount += 1
        // A sticker scrolled away mid-load cancels its download once no other
        // overlay is waiting on it, rather than queueing ahead of visible media.
        let animation = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task { await self.cancelWaiter(for: url, task: task) }
        }
        if inFlight[url]?.task == task {
            inFlight[url] = nil
        }
        return animation
    }

    private func makeLoad(for url: URL) -> Task<LottieAnimation?, Never> {
        Task<LottieAnimation?, Never> { [weak self] in
            guard let self else { return nil }
            let data = try? await self.loadData(url)
            guard let data, !Task.isCancelled,
                  await self.acquireParseLane()
            else { return nil }
            guard !Task.isCancelled else {
                await self.releaseParseLane()
                return nil
            }
            let animation = try? LottieAnimation.from(data: data)
            if let animation {
                self.cache.setAnimation(
                    animation,
                    forKey: url.absoluteString
                )
            }
            await self.releaseParseLane()
            return animation
        }
    }

    private func cancelWaiter(for url: URL, task: Task<LottieAnimation?, Never>) {
        guard var load = inFlight[url], load.task == task else { return }
        load.waiterCount -= 1
        if load.waiterCount > 0 {
            inFlight[url] = load
        } else {
            inFlight[url] = nil
            task.cancel()
        }
    }

    private func acquireParseLane() async -> Bool {
        if Task.isCancelled {
            return false
        }
        if !isParsing {
            isParsing = true
            return true
        }
        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                parseWaiters.append(
                    ParseWaiter(
                        id: waiterID,
                        continuation: continuation
                    )
                )
            }
        } onCancel: {
            Task {
                await self.cancelParseWaiter(waiterID)
            }
        }
    }

    private func cancelParseWaiter(_ id: UUID) {
        guard let index = parseWaiters.firstIndex(where: { $0.id == id }) else {
            return
        }
        parseWaiters.remove(at: index).continuation.resume(returning: false)
    }

    private func releaseParseLane() {
        if !parseWaiters.isEmpty {
            parseWaiters.removeFirst().continuation.resume(returning: true)
        } else {
            isParsing = false
        }
    }
}
