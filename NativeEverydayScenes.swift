import UIKit
import AVFoundation

/// Implemented by scenes that own active resources (player, keyboard, observers).
/// `NativeSuiteController` should call this before removing the current scene.
protocol NativeSceneLifecycle: AnyObject {
    func stopScene()
    func pauseScene()
    func resumeScene()
}

extension NativeSceneLifecycle {
    /// Temporary application inactivity must not destroy scene state.
    func pauseScene() {}
    func resumeScene() {}
}

/// Native UIKit implementations of the everyday interaction test scenes.
/// No scene in this factory uses HTML, JavaScript, WKWebView, or a network resource.
enum NativeEverydayScenes {
    static func make(mode: String, frame: CGRect, assetFolder: URL?) -> UIView? {
        let view: UIView?
        switch mode.lowercased() {
        case "pinch": view = NativePhotoZoomView(assetFolder: assetFolder)
        case "map": view = NativeOfflineMapView()
        case "read": view = NativeReadingView()
        case "video": view = NativeVideoView(assetFolder: assetFolder)
        case "ui": view = NativeSettingsView()
        case "menu": view = NativeMenuView()
        case "type": view = NativeTypingView()
        default: view = nil
        }
        view?.frame = frame
        view?.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return view
    }
}

// MARK: - Shared presentation

private enum EverydayTheme {
    static let background = UIColor.black
    static let panel = UIColor(white: 0.10, alpha: 0.96)
    static let line = UIColor(white: 0.34, alpha: 1)
    static let cyan = UIColor.white
    static let green = UIColor(red: 0.28, green: 0.90, blue: 0.55, alpha: 1)

    static func title(_ text: String, detail: String? = nil) -> UIView {
        let container = UIView()
        container.backgroundColor = panel
        container.layer.cornerRadius = 14
        container.layer.borderWidth = 1
        container.layer.borderColor = line.cgColor

        let title = UILabel()
        title.text = text
        title.textColor = .white
        title.font = .systemFont(ofSize: 17, weight: .bold)
        title.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(title)

        let detailLabel = UILabel()
        detailLabel.text = detail
        detailLabel.textColor = UIColor.white.withAlphaComponent(0.68)
        detailLabel.font = .systemFont(ofSize: 11, weight: .regular)
        detailLabel.numberOfLines = 2
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(detailLabel)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            title.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            detailLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 1),
            detailLabel.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -7)
        ])
        return container
    }

    static func button(_ title: String, image: String? = nil) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.baseBackgroundColor = panel
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .capsule
        configuration.imagePadding = 6
        if let image { configuration.image = UIImage(systemName: image) }
        let button = UIButton(configuration: configuration)
        button.layer.borderColor = line.cgColor
        button.layer.borderWidth = 1
        button.clipsToBounds = true
        return button
    }
}

// MARK: - Pinch / photo

private final class NativePhotoZoomView: UIView, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let heading = EverydayTheme.title("双指缩放照片", detail: "双指缩放、拖动并快速改变方向，检查手势连续性")
    private var lastContainerSize: CGSize = .zero

    init(assetFolder: URL?) {
        super.init(frame: .zero)
        backgroundColor = .black
        isMultipleTouchEnabled = true

        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 8
        scrollView.bouncesZoom = true
        scrollView.decelerationRate = .fast
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        addSubview(scrollView)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .black
        imageView.isUserInteractionEnabled = true
        imageView.image = NativePhotoZoomView.loadPhoto(from: assetFolder) ?? NativePhotoZoomView.placeholderPhoto()
        scrollView.addSubview(imageView)
        addSubview(heading)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        let safe = safeAreaInsets
        heading.frame = CGRect(x: safe.left + 12,
                               y: safe.top + 10,
                               width: max(150, bounds.width - safe.left - safe.right - 96),
                               height: 58)
        // Only rebuild the base geometry when the actual container size changes
        // (initial layout or rotation). Zoom callbacks must never reset the image.
        if bounds.size != lastContainerSize, bounds.width > 0, bounds.height > 0 {
            let source = imageView.image?.size ?? bounds.size
            let fillScale = max(bounds.width / max(source.width, 1), bounds.height / max(source.height, 1))
            let filled = CGSize(width: source.width * fillScale, height: source.height * fillScale)
            scrollView.setZoomScale(1, animated: false)
            imageView.transform = .identity
            imageView.frame = CGRect(origin: .zero, size: filled)
            scrollView.contentSize = filled
            scrollView.contentInset = .zero
            scrollView.contentOffset = CGPoint(x: max(0, (filled.width - bounds.width) / 2),
                                               y: max(0, (filled.height - bounds.height) / 2))
            lastContainerSize = bounds.size
        }
        centerImageIfNeeded()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImageIfNeeded() }

    private func centerImageIfNeeded() {
        let horizontal = max(0, (bounds.width - imageView.frame.width) / 2)
        let vertical = max(0, (bounds.height - imageView.frame.height) / 2)
        scrollView.contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }

    @objc private func doubleTapped(_ recognizer: UITapGestureRecognizer) {
        if scrollView.zoomScale > 1.05 {
            scrollView.setZoomScale(1, animated: true)
        } else {
            let location = recognizer.location(in: imageView)
            let size = CGSize(width: bounds.width / 3, height: bounds.height / 3)
            scrollView.zoom(to: CGRect(x: location.x - size.width / 2, y: location.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }

    private static func loadPhoto(from folder: URL?) -> UIImage? {
        guard let folder else { return nil }
        let candidates = ["lake-photo-v1.png", "lake-photo-v1.jpg", "lake-photo-v1.jpeg"]
        for name in candidates {
            let url = folder.appendingPathComponent(name)
            if let image = UIImage(contentsOfFile: url.path) { return image }
        }
        return nil
    }

    private static func placeholderPhoto() -> UIImage {
        let size = CGSize(width: 1400, height: 1000)
        return UIGraphicsImageRenderer(size: size).image { renderer in
            let cg = renderer.cgContext
            let colors = [UIColor(red: 0.05, green: 0.16, blue: 0.29, alpha: 1).cgColor,
                          UIColor(red: 0.14, green: 0.57, blue: 0.67, alpha: 1).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            UIColor(red: 0.05, green: 0.35, blue: 0.28, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 0, y: 590, width: 1400, height: 410), cornerRadius: 0).fill()
            UIColor.white.withAlphaComponent(0.72).setFill()
            UIBezierPath(ovalIn: CGRect(x: 1030, y: 100, width: 170, height: 170)).fill()
            let text = "离线缩放测试照片"
            text.draw(at: CGPoint(x: 54, y: 50), withAttributes: [.font: UIFont.systemFont(ofSize: 45, weight: .bold), .foregroundColor: UIColor.white])
        }
    }
}

// MARK: - Offline map

private final class NativeOfflineMapView: UIView, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
    private let map = NativeMapCanvasView(frame: CGRect(x: 0, y: 0, width: 1800, height: 1800))
    private let heading = EverydayTheme.title("离线地图拖动", detail: "单指平移、双指缩放；道路和地点均为本地绘制")
    private var setInitialZoom = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = EverydayTheme.background
        scrollView.delegate = self
        scrollView.minimumZoomScale = 0.25
        scrollView.maximumZoomScale = 3.5
        scrollView.bouncesZoom = true
        scrollView.decelerationRate = .fast
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentSize = map.bounds.size
        scrollView.addSubview(map)
        addSubview(scrollView)
        addSubview(heading)
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        let safe = safeAreaInsets
        heading.frame = CGRect(x: safe.left + 12, y: safe.top + 10,
                               width: max(150, bounds.width - safe.left - safe.right - 96), height: 58)
        if !setInitialZoom, bounds.width > 0 {
            let zoom = max(scrollView.minimumZoomScale, min(0.62, bounds.width / 930))
            scrollView.zoomScale = zoom
            scrollView.contentOffset = CGPoint(x: 490 * zoom, y: 540 * zoom)
            setInitialZoom = true
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { map }
}

private final class NativeMapCanvasView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        backgroundColor = UIColor(red: 0.88, green: 0.90, blue: 0.85, alpha: 1)
    }
    required init?(coder: NSCoder) { nil }

    override func draw(_ rect: CGRect) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        UIColor(red: 0.88, green: 0.90, blue: 0.85, alpha: 1).setFill(); cg.fill(bounds)

        UIColor(red: 0.55, green: 0.78, blue: 0.88, alpha: 1).setFill()
        UIBezierPath(roundedRect: CGRect(x: 80, y: 640, width: 1640, height: 280), cornerRadius: 120).fill()
        UIColor(red: 0.69, green: 0.84, blue: 0.64, alpha: 1).setFill()
        for i in 0..<18 {
            let x = CGFloat((i * 307) % 1600 + 60), y = CGFloat((i * 193) % 1550 + 80)
            UIBezierPath(ovalIn: CGRect(x: x, y: y, width: 145, height: 105)).fill()
        }

        cg.setLineCap(.round)
        cg.setStrokeColor(UIColor.white.cgColor)
        cg.setLineWidth(44)
        for i in 0..<9 {
            let offset = CGFloat(i * 185 + 90)
            cg.move(to: CGPoint(x: 40, y: offset))
            cg.addCurve(to: CGPoint(x: 1760, y: offset + CGFloat((i % 3 - 1) * 90)), control1: CGPoint(x: 600, y: offset - 120), control2: CGPoint(x: 1180, y: offset + 130))
            cg.strokePath()
        }
        for i in 0..<8 {
            let x = CGFloat(i * 215 + 120)
            cg.move(to: CGPoint(x: x, y: 30)); cg.addLine(to: CGPoint(x: x + CGFloat((i % 2) * 140 - 70), y: 1770)); cg.strokePath()
        }
        cg.setStrokeColor(UIColor(red: 0.92, green: 0.70, blue: 0.25, alpha: 1).cgColor)
        cg.setLineWidth(13)
        cg.move(to: CGPoint(x: 20, y: 1480)); cg.addCurve(to: CGPoint(x: 1780, y: 240), control1: CGPoint(x: 500, y: 1000), control2: CGPoint(x: 1200, y: 900)); cg.strokePath()

        let labels = [("中心广场", 760, 430), ("滨水公园", 980, 790), ("测试大道", 330, 1230), ("科技馆", 1370, 1090), ("西站", 190, 410), ("东湖", 1440, 710)]
        for (text, x, y) in labels {
            let box = CGRect(x: CGFloat(x), y: CGFloat(y), width: 180, height: 54)
            UIColor.white.withAlphaComponent(0.92).setFill(); UIBezierPath(roundedRect: box, cornerRadius: 14).fill()
            text.draw(in: box.insetBy(dx: 10, dy: 14), withAttributes: [.font: UIFont.systemFont(ofSize: 19, weight: .semibold), .foregroundColor: UIColor.darkText])
        }
        UIColor.systemRed.setFill(); UIBezierPath(ovalIn: CGRect(x: 872, y: 858, width: 56, height: 56)).fill()
        UIColor.white.setFill(); UIBezierPath(ovalIn: CGRect(x: 889, y: 875, width: 22, height: 22)).fill()
    }
}

// MARK: - Native paged reading

private final class NativeReadingView: UIView, UIScrollViewDelegate {
    private let heading = EverydayTheme.title("原生多页阅读", detail: "左右翻页；慢速拖动与快速甩动都应稳定跟手")
    private let scrollView = UIScrollView()
    private let pageControl = UIPageControl()
    private let fontControl = UISegmentedControl(items: ["A−", "18 pt", "A+"])
    private var bodyFontSize: CGFloat = 18
    private var pageViews: [UIView] = []
    private let pages: [(String, String)] = [
        ("第一章 · 触摸的节奏", "把手指放在屏幕上，缓慢向左滑动。内容应该紧贴手指移动，不应突然跳页。随后快速轻扫，观察减速动画和翻页落点。\n\n阅读场景能同时检查短距离滑动、长距离拖动、停顿后续滑以及边缘起手。请分别使用拇指和食指，并尝试靠近屏幕四边操作。"),
        ("第二章 · 双手操作", "用一只手握住设备，另一只手连续翻页。再换手重复，比较屏幕左右边缘的响应。\n\n如果贴边起手经常失败，请取下保护壳或保护膜复测。系统返回手势可能会优先识别最外侧的滑动，这属于操作系统行为。"),
        ("第三章 · 连续性", "在这一页进行多次短促的左右往返拖动。文字页面不应丢失，也不应在手指仍按住时自动跳到其他页面。\n\n放开手指后，页面会按照速度停靠到最近的一页。这是原生 UIScrollView 的分页行为。"),
        ("第四章 · 测试结论", "完成慢拖、快甩、边缘起手和双手操作后，可返回项目菜单继续视频、控件、菜单和键盘测试。\n\n本页完全由 UIKit 绘制，不依赖网页、网络或浏览器运行时。")
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.94, green: 0.92, blue: 0.85, alpha: 1)
        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.delegate = self
        scrollView.contentInsetAdjustmentBehavior = .never
        addSubview(scrollView)
        for (title, body) in pages {
            let page = UIView(); page.backgroundColor = .clear
            let titleLabel = UILabel(); titleLabel.text = title; titleLabel.textColor = UIColor(red: 0.18, green: 0.14, blue: 0.10, alpha: 1); titleLabel.font = .systemFont(ofSize: 25, weight: .bold); titleLabel.numberOfLines = 2
            let bodyLabel = UILabel(); bodyLabel.text = body; bodyLabel.textColor = UIColor(red: 0.25, green: 0.21, blue: 0.16, alpha: 1); bodyLabel.font = .systemFont(ofSize: 18, weight: .regular); bodyLabel.numberOfLines = 0
            page.addSubview(titleLabel); page.addSubview(bodyLabel)
            titleLabel.tag = 101; bodyLabel.tag = 102
            scrollView.addSubview(page); pageViews.append(page)
        }
        pageControl.numberOfPages = pages.count
        pageControl.currentPage = 0
        pageControl.currentPageIndicatorTintColor = .darkGray
        pageControl.pageIndicatorTintColor = UIColor.darkGray.withAlphaComponent(0.25)
        pageControl.addTarget(self, action: #selector(pageChanged), for: .valueChanged)
        fontControl.selectedSegmentIndex = 1
        fontControl.setEnabled(false, forSegmentAt: 1)
        fontControl.selectedSegmentTintColor = UIColor(white: 0.20, alpha: 1)
        fontControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        fontControl.addTarget(self, action: #selector(fontControlChanged), for: .valueChanged)
        addSubview(pageControl)
        addSubview(fontControl)
        addSubview(heading)
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        let safe = safeAreaInsets
        heading.frame = CGRect(x: safe.left + 12, y: safe.top + 10,
                               width: max(150, bounds.width - safe.left - safe.right - 96), height: 58)
        fontControl.frame = CGRect(x: safe.left + 14, y: safe.top + 76, width: 190, height: 34)
        let top = safe.top + 118, bottom = safe.bottom + 38
        scrollView.frame = CGRect(x: 0, y: top, width: bounds.width, height: max(100, bounds.height - top - bottom))
        for (index, page) in pageViews.enumerated() {
            page.frame = CGRect(x: CGFloat(index) * scrollView.bounds.width, y: 0, width: scrollView.bounds.width, height: scrollView.bounds.height)
            let inset = max(26, safe.left + 22)
            let title = page.viewWithTag(101) as? UILabel
            title?.frame = CGRect(x: inset, y: 25, width: page.bounds.width - inset * 2, height: 72)
            let body = page.viewWithTag(102) as? UILabel
            body?.frame = CGRect(x: inset, y: 108, width: page.bounds.width - inset * 2, height: page.bounds.height - 130)
        }
        scrollView.contentSize = CGSize(width: scrollView.bounds.width * CGFloat(pageViews.count), height: scrollView.bounds.height)
        if !scrollView.isDragging && !scrollView.isDecelerating { scrollView.contentOffset.x = CGFloat(pageControl.currentPage) * scrollView.bounds.width }
        pageControl.frame = CGRect(x: safe.left, y: bounds.height - safe.bottom - 36, width: bounds.width - safe.left - safe.right, height: 28)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.bounds.width > 0 else { return }
        pageControl.currentPage = max(0, min(pages.count - 1, Int(round(scrollView.contentOffset.x / scrollView.bounds.width))))
    }

    @objc private func pageChanged() {
        scrollView.setContentOffset(CGPoint(x: CGFloat(pageControl.currentPage) * scrollView.bounds.width, y: 0), animated: true)
    }

    @objc private func fontControlChanged() {
        if fontControl.selectedSegmentIndex == 0 { bodyFontSize = max(14, bodyFontSize - 1) }
        if fontControl.selectedSegmentIndex == 2 { bodyFontSize = min(28, bodyFontSize + 1) }
        fontControl.setTitle("\(Int(bodyFontSize)) pt", forSegmentAt: 1)
        fontControl.selectedSegmentIndex = 1
        for page in pageViews {
            (page.viewWithTag(102) as? UILabel)?.font = .systemFont(ofSize: bodyFontSize, weight: .regular)
        }
    }
}

// MARK: - Local video player

private final class NativeVideoView: UIView, NativeSceneLifecycle {
    private let playerLayer = AVPlayerLayer()
    private let heading = EverydayTheme.title("本地视频手势", detail: "点按播放/暂停；上滑下一段，下滑上一段")
    private let playButton = EverydayTheme.button("播放", image: "play.fill")
    private let statusLabel = UILabel()
    private var player: AVPlayer?
    private var observer: NSObjectProtocol?
    private var urls: [URL] = []
    private var currentIndex = 0
    private var wasPlayingBeforePause = false
    private var isLifecyclePaused = false

    init(assetFolder: URL?) {
        super.init(frame: .zero)
        backgroundColor = .black
        layer.addSublayer(playerLayer)
        // The test scene itself is full-screen. Fill the entire surface so a
        // landscape/portrait mismatch is expressed as a deliberate crop, not
        // as top/bottom letterboxing that could be mistaken for a dead area.
        playerLayer.videoGravity = .resizeAspectFill
        addSubview(heading)
        playButton.addTarget(self, action: #selector(togglePlay), for: .touchUpInside)
        addSubview(playButton)
        statusLabel.textColor = .white
        statusLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        statusLabel.textAlignment = .center
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        statusLabel.layer.cornerRadius = 10
        statusLabel.clipsToBounds = true
        addSubview(statusLabel)

        let up = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:))); up.direction = .up
        let down = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:))); down.direction = .down
        addGestureRecognizer(up); addGestureRecognizer(down)

        if let folder=assetFolder, let contents = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            urls = contents.filter { ["mp4", "mov", "m4v"].contains($0.pathExtension.lowercased()) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        if urls.isEmpty, let folder=assetFolder {
            let fallback = folder.appendingPathComponent("flower-cc0.mp4")
            if FileManager.default.fileExists(atPath: fallback.path) { urls = [fallback] }
        }
        load(index: 0, autoplay: false)
    }

    required init?(coder: NSCoder) { nil }
    deinit { stopScene() }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
        let safe = safeAreaInsets
        heading.frame = CGRect(x: safe.left + 12, y: safe.top + 10,
                               width: max(150, bounds.width - safe.left - safe.right - 96), height: 58)
        playButton.frame = CGRect(x: (bounds.width - 126) / 2, y: bounds.height - safe.bottom - 70, width: 126, height: 46)
        statusLabel.frame = CGRect(x: safe.left + 14, y: playButton.frame.minY - 36,
                                   width: bounds.width - safe.left - safe.right - 28, height: 26)
    }

    private func load(index: Int, autoplay: Bool) {
        if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
        player?.pause()
        guard !urls.isEmpty else {
            player = nil; playerLayer.player = nil
            statusLabel.text = "未找到本地 MP4 资源"
            playButton.isEnabled = false
            return
        }
        currentIndex = (index % urls.count + urls.count) % urls.count
        let item = AVPlayerItem(url: urls[currentIndex])
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        playerLayer.player = newPlayer
        observer = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.urls.count > 1 { self.load(index: self.currentIndex + 1, autoplay: true) }
            else { self.player?.seek(to: .zero); self.player?.play() }
        }
        updateStatus()
        if autoplay { newPlayer.play(); setPlayingUI(true) } else { setPlayingUI(false) }
    }

    private func updateStatus() {
        guard !urls.isEmpty else { return }
        statusLabel.text = "\(currentIndex + 1)/\(urls.count)  \(urls[currentIndex].lastPathComponent)  ·  上下滑动切换"
    }

    private func setPlayingUI(_ playing: Bool) {
        var configuration = playButton.configuration
        configuration?.title = playing ? "暂停" : "播放"
        configuration?.image = UIImage(systemName: playing ? "pause.fill" : "play.fill")
        playButton.configuration = configuration
    }

    @objc private func togglePlay() {
        guard let player else { return }
        if player.timeControlStatus == .playing { player.pause(); setPlayingUI(false) }
        else { player.play(); setPlayingUI(true) }
    }

    @objc private func swiped(_ gesture: UISwipeGestureRecognizer) {
        guard !urls.isEmpty else { return }
        let delta = gesture.direction == .up ? 1 : -1
        load(index: currentIndex + delta, autoplay: true)
    }

    func stopScene() {
        isLifecyclePaused = false
        wasPlayingBeforePause = false
        player?.pause()
        playerLayer.player = nil
        player = nil
        if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
    }

    func pauseScene() {
        guard !isLifecyclePaused else { return }
        isLifecyclePaused = true
        wasPlayingBeforePause = player?.timeControlStatus == .playing
        player?.pause()
        if wasPlayingBeforePause { setPlayingUI(false) }
    }

    func resumeScene() {
        guard isLifecyclePaused else { return }
        isLifecyclePaused = false
        if wasPlayingBeforePause {
            player?.play()
            setPlayingUI(true)
        }
        wasPlayingBeforePause = false
    }
}

// MARK: - Settings controls

private final class NativeSettingsView: UIView, UIPickerViewDataSource, UIPickerViewDelegate {
    private let heading = EverydayTheme.title("原生控件组合", detail: "开关、滑杆、分段选择、步进器与滚轮选择")
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let status = UILabel()
    private let slider = UISlider()
    private let toggle = UISwitch()
    private let segmented = UISegmentedControl(items: ["轻柔", "标准", "快速"])
    private let stepper = UIStepper()
    private let picker = UIPickerView()
    private let pickerItems = ["跟随系统", "深色主题", "浅色主题", "高对比度"]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = EverydayTheme.background
        addSubview(scrollView); addSubview(heading)
        stack.axis = .vertical; stack.spacing = 14; stack.alignment = .fill
        scrollView.addSubview(stack)

        status.textColor = EverydayTheme.cyan; status.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold); status.textAlignment = .center; status.numberOfLines = 2
        stack.addArrangedSubview(status)
        stack.addArrangedSubview(row(title: "触觉反馈", control: toggle))
        toggle.isOn = true; toggle.addTarget(self, action: #selector(valueChanged), for: .valueChanged)
        slider.minimumValue = 0; slider.maximumValue = 100; slider.value = 62; slider.minimumTrackTintColor = EverydayTheme.cyan; slider.addTarget(self, action: #selector(valueChanged), for: .valueChanged)
        stack.addArrangedSubview(group(title: "灵敏度", control: slider, height: 48))
        segmented.selectedSegmentIndex = 1; segmented.addTarget(self, action: #selector(valueChanged), for: .valueChanged)
        stack.addArrangedSubview(group(title: "跟手速度", control: segmented, height: 50))
        stepper.minimumValue = 1; stepper.maximumValue = 10; stepper.value = 5; stepper.addTarget(self, action: #selector(valueChanged), for: .valueChanged)
        stack.addArrangedSubview(row(title: "测试轮数", control: stepper))
        picker.dataSource = self; picker.delegate = self; picker.selectRow(0, inComponent: 0, animated: false)
        stack.addArrangedSubview(group(title: "显示方案", control: picker, height: 155))
        updateStatus()
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        let safe = safeAreaInsets
        heading.frame = CGRect(x: safe.left + 12, y: safe.top + 10,
                               width: max(150, bounds.width - safe.left - safe.right - 96), height: 58)
        scrollView.frame = CGRect(x: safe.left, y: safe.top + 78,
                                  width: bounds.width - safe.left - safe.right, height: bounds.height - safe.top - safe.bottom - 78)
        let width = max(260, scrollView.bounds.width - 28)
        stack.frame = CGRect(x: 14, y: 4, width: width, height: 500)
        scrollView.contentSize = CGSize(width: scrollView.bounds.width, height: stack.frame.maxY + 20)
    }

    private func row(title: String, control: UIView) -> UIView {
        let box = UIView(); box.backgroundColor = EverydayTheme.panel; box.layer.cornerRadius = 14; box.layer.borderWidth = 1; box.layer.borderColor = EverydayTheme.line.cgColor
        let label = UILabel(); label.text = title; label.textColor = .white; label.font = .systemFont(ofSize: 16, weight: .semibold)
        box.addSubview(label); box.addSubview(control)
        box.heightAnchor.constraint(equalToConstant: 58).isActive = true
        label.translatesAutoresizingMaskIntoConstraints = false; control.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14), label.centerYAnchor.constraint(equalTo: box.centerYAnchor), control.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14), control.centerYAnchor.constraint(equalTo: box.centerYAnchor)])
        return box
    }

    private func group(title: String, control: UIView, height: CGFloat) -> UIView {
        let box = UIView(); box.backgroundColor = EverydayTheme.panel; box.layer.cornerRadius = 14; box.layer.borderWidth = 1; box.layer.borderColor = EverydayTheme.line.cgColor
        let label = UILabel(); label.text = title; label.textColor = .white; label.font = .systemFont(ofSize: 15, weight: .semibold)
        box.addSubview(label); box.addSubview(control); box.heightAnchor.constraint(equalToConstant: height).isActive = true
        label.translatesAutoresizingMaskIntoConstraints = false; control.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14), label.topAnchor.constraint(equalTo: box.topAnchor, constant: 8), control.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14), control.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14), control.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 3), control.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -6)])
        return box
    }

    @objc private func valueChanged() { updateStatus() }
    private func updateStatus() { status.text = "反馈 \(toggle.isOn ? "开" : "关") · 灵敏度 \(Int(slider.value)) · 轮数 \(Int(stepper.value)) · \(pickerItems[picker.selectedRow(inComponent: 0)])" }
    func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int { pickerItems.count }
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? { pickerItems[row] }
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) { updateStatus() }
}

// MARK: - Hierarchical menu

private final class NativeMenuView: UIView, UITableViewDataSource, UITableViewDelegate {
    private struct Node {
        let title: String
        let subtitle: String
        let children: [Node]
        static func leaf(_ title: String, _ subtitle: String) -> Node { Node(title: title, subtitle: subtitle, children: []) }
    }

    private let heading = EverydayTheme.title("原生多级菜单", detail: "进入子菜单、返回上级并选择末级项目")
    private let backButton = EverydayTheme.button("返回", image: "chevron.left")
    private let pathLabel = UILabel()
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private var levels: [[Node]] = []
    private var path: [String] = []
    private var selectedLeaves = Set<String>()

    private let root: [Node] = [
        Node(title: "显示与触控", subtitle: "屏幕、手势与响应", children: [
            Node(title: "触控参数", subtitle: "灵敏度与防误触", children: [.leaf("边缘防误触", "标准"), .leaf("手套模式", "关闭"), .leaf("三指手势", "开启")]),
            Node(title: "显示效果", subtitle: "色彩和刷新率", children: [.leaf("自然色彩", "推荐"), .leaf("高刷新率", "自动"), .leaf("护眼模式", "日落开启")])
        ]),
        Node(title: "声音与振动", subtitle: "媒体、铃声、触感", children: [
            Node(title: "触感反馈", subtitle: "强度与场景", children: [.leaf("键盘触感", "中等"), .leaf("系统触感", "开启")]),
            .leaf("媒体音量", "65%")
        ]),
        Node(title: "辅助功能", subtitle: "操作和显示辅助", children: [
            Node(title: "触控辅助", subtitle: "按住持续时间", children: [.leaf("忽略重复触控", "关闭"), .leaf("轻点唤醒", "开启")]),
            .leaf("放大显示", "标准")
        ])
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = EverydayTheme.background
        levels = [root]
        selectedLeaves = defaultLeafKeys(in: root, prefix: [])
        pathLabel.textColor = EverydayTheme.cyan; pathLabel.font = .systemFont(ofSize: 13, weight: .semibold); pathLabel.numberOfLines = 1
        backButton.addTarget(self, action: #selector(goBack), for: .touchUpInside)
        table.backgroundColor = .clear; table.dataSource = self; table.delegate = self; table.rowHeight = 68
        table.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        addSubview(table); addSubview(pathLabel); addSubview(backButton); addSubview(heading)
        refreshChrome()
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        let safe = safeAreaInsets
        heading.frame = CGRect(x: safe.left + 12, y: safe.top + 10,
                               width: max(150, bounds.width - safe.left - safe.right - 96), height: 58)
        backButton.frame = CGRect(x: safe.left + 12, y: safe.top + 77, width: 86, height: 38)
        pathLabel.frame = CGRect(x: backButton.frame.maxX + 10, y: safe.top + 77,
                                 width: bounds.width - backButton.frame.maxX - safe.right - 22, height: 38)
        table.frame = CGRect(x: 0, y: safe.top + 121, width: bounds.width, height: bounds.height - safe.top - safe.bottom - 121)
    }

    private var nodes: [Node] { levels.last ?? [] }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { nodes.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let node = nodes[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = node.title; content.secondaryText = node.subtitle
        content.textProperties.color = .white; content.secondaryTextProperties.color = UIColor.white.withAlphaComponent(0.55)
        cell.contentConfiguration = content
        cell.backgroundColor = EverydayTheme.panel
        if node.children.isEmpty {
            let key = fullKey(node.title)
            let toggle = UISwitch()
            toggle.isOn = selectedLeaves.contains(key)
            toggle.onTintColor = EverydayTheme.green
            toggle.accessibilityIdentifier = key
            toggle.accessibilityLabel = node.title
            toggle.addTarget(self, action: #selector(leafSwitchChanged(_:)), for: .valueChanged)
            cell.accessoryView = toggle
            cell.accessoryType = .none
        } else {
            cell.accessoryView = nil
            cell.accessoryType = .disclosureIndicator
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let node = nodes[indexPath.row]
        if node.children.isEmpty {
            let key = fullKey(node.title)
            if selectedLeaves.contains(key) { selectedLeaves.remove(key) } else { selectedLeaves.insert(key) }
            tableView.reloadRows(at: [indexPath], with: .automatic)
        } else {
            path.append(node.title); levels.append(node.children); refreshChrome(); table.reloadSections(IndexSet(integer: 0), with: .right)
        }
    }

    private func fullKey(_ leaf: String) -> String { (path + [leaf]).joined(separator: "/") }
    private func defaultLeafKeys(in nodes: [Node], prefix: [String]) -> Set<String> {
        var result = Set<String>()
        for node in nodes {
            let next = prefix + [node.title]
            if node.children.isEmpty {
                // Preserve meaningful initial state instead of presenting a
                // decorative switch: explicit "关闭" leaves start off.
                if !node.subtitle.contains("关闭") { result.insert(next.joined(separator: "/")) }
            } else {
                result.formUnion(defaultLeafKeys(in: node.children, prefix: next))
            }
        }
        return result
    }

    @objc private func leafSwitchChanged(_ sender: UISwitch) {
        guard let key = sender.accessibilityIdentifier else { return }
        if sender.isOn { selectedLeaves.insert(key) } else { selectedLeaves.remove(key) }
    }
    private func refreshChrome() { backButton.isEnabled = levels.count > 1; backButton.alpha = levels.count > 1 ? 1 : 0.4; pathLabel.text = path.isEmpty ? "全部设置" : "全部设置 / " + path.joined(separator: " / ") }
    @objc private func goBack() { guard levels.count > 1 else { return }; levels.removeLast(); path.removeLast(); refreshChrome(); table.reloadSections(IndexSet(integer: 0), with: .fade) }
}

// MARK: - Native keyboard / typing

private final class NativeTypingView: UIView, NativeSceneLifecycle, UITextViewDelegate {
    private let heading = EverydayTheme.title("原生键盘输入", detail: "连续输入、移动光标、选词、删除并切换中英文键盘")
    private let textView = UITextView()
    private let counter = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = EverydayTheme.background
        heading.translatesAutoresizingMaskIntoConstraints = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        counter.translatesAutoresizingMaskIntoConstraints = false
        addSubview(heading); addSubview(textView); addSubview(counter)

        textView.delegate = self
        textView.backgroundColor = EverydayTheme.panel
        textView.textColor = .white
        textView.tintColor = EverydayTheme.cyan
        textView.font = .systemFont(ofSize: 19)
        textView.layer.cornerRadius = 16
        textView.layer.borderWidth = 1
        textView.layer.borderColor = EverydayTheme.line.cgColor
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        textView.keyboardDismissMode = .interactive
        textView.autocorrectionType = .yes
        textView.spellCheckingType = .yes
        textView.text = "请在这里输入一段文字，测试连续打字、删除、选词和光标拖动。\n\n"

        counter.textColor = UIColor.white.withAlphaComponent(0.7)
        counter.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        counter.textAlignment = .right
        updateCounter()

        let toolbar = UIToolbar(); toolbar.sizeToFit()
        toolbar.items = [UIBarButtonItem(title: "清空", style: .plain, target: self, action: #selector(clearText)), UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil), UIBarButtonItem(title: "完成", style: .done, target: self, action: #selector(doneTyping))]
        textView.inputAccessoryView = toolbar

        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 12),
            heading.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 10),
            heading.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -84),
            heading.heightAnchor.constraint(equalToConstant: 58),
            counter.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16),
            counter.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -16),
            counter.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 8),
            counter.heightAnchor.constraint(equalToConstant: 20),
            textView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 12),
            textView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -12),
            textView.topAnchor.constraint(equalTo: counter.bottomAnchor, constant: 7),
            textView.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor, constant: -12)
        ])
    }

    required init?(coder: NSCoder) { nil }
    func textViewDidChange(_ textView: UITextView) { updateCounter() }
    private func updateCounter() { counter.text = "字符 \(textView.text.count) · 行数 \(textView.text.components(separatedBy: .newlines).count)" }
    @objc private func clearText() { textView.text = ""; updateCounter() }
    @objc private func doneTyping() { textView.resignFirstResponder() }
    func stopScene() { textView.resignFirstResponder() }
    func pauseScene() { endEditing(true) }
    func resumeScene() {}
}
