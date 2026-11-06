import UIKit
import AVFoundation
import PhotosUI

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
        view?.accessibilityIdentifier = "native-scene-"+mode
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

private final class NativePhotoZoomView: UIView, UIScrollViewDelegate, PHPickerViewControllerDelegate, NativeSceneLifecycle, NativeResettableScene {
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let heading = EverydayTheme.title("双指缩放照片", detail: "双指缩放、拖动并快速改变方向，检查手势连续性")
    private let changeButton = EverydayTheme.button("更换图片", image: "photo.on.rectangle")
    private let resetButton = EverydayTheme.button("复位", image: "arrow.counterclockwise")
    private let sizeSlider = UISlider()
    private let zoomLabel = UILabel()
    private var lastContainerSize: CGSize = .zero
    private var builtInImages: [(name: String, image: UIImage)] = []
    private var selectedBuiltInIndex: Int?
    private weak var presentedPicker: PHPickerViewController?
    private var sceneIsActive = true

    init(assetFolder: URL?) {
        super.init(frame: .zero)
        backgroundColor = .black
        isMultipleTouchEnabled = true

        scrollView.delegate = self
        scrollView.minimumZoomScale = 0.25
        scrollView.maximumZoomScale = 8
        scrollView.bouncesZoom = true
        scrollView.decelerationRate = .fast
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        // Keep the scroll view as a container so the image's own stable
        // accessibility identifier and live zoom value remain discoverable.
        scrollView.isAccessibilityElement = false
        scrollView.accessibilityIdentifier = "photo-zoom-canvas"
        scrollView.accessibilityLabel = "图片缩放画布"
        addSubview(scrollView)

        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.backgroundColor = UIColor(white: 0.06, alpha: 1)
        imageView.layer.cornerRadius = 8
        imageView.layer.borderWidth = 1
        imageView.layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
        imageView.isUserInteractionEnabled = true
        imageView.isAccessibilityElement = true
        imageView.accessibilityIdentifier = "native-photo-image"
        imageView.accessibilityLabel = "当前缩放测试图片"
        builtInImages = NativePhotoZoomView.loadBuiltInImages(from: assetFolder)
        selectedBuiltInIndex = 0
        imageView.image = builtInImages[0].image
        scrollView.addSubview(imageView)
        addSubview(heading)

        changeButton.accessibilityIdentifier = "photo-change"
        changeButton.showsMenuAsPrimaryAction = true
        addSubview(changeButton)
        resetButton.accessibilityIdentifier = "photo-reset"
        resetButton.addTarget(self, action: #selector(resetPhoto), for: .touchUpInside)
        addSubview(resetButton)

        sizeSlider.minimumValue = 0.25
        sizeSlider.maximumValue = 8
        sizeSlider.value = 1
        sizeSlider.minimumTrackTintColor = .white
        sizeSlider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.32)
        sizeSlider.accessibilityIdentifier = "photo-size"
        sizeSlider.accessibilityLabel = "图片显示大小"
        sizeSlider.addTarget(self, action: #selector(sizeSliderChanged), for: .valueChanged)
        addSubview(sizeSlider)
        zoomLabel.textColor = .white
        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        zoomLabel.textAlignment = .center
        zoomLabel.backgroundColor = UIColor.black.withAlphaComponent(0.60)
        zoomLabel.layer.cornerRadius = 9
        zoomLabel.clipsToBounds = true
        addSubview(zoomLabel)
        rebuildImageMenu()

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
        changeButton.frame = CGRect(x: safe.left + 12, y: safe.top + 78, width: 128, height: 40)
        resetButton.frame = CGRect(x: changeButton.frame.maxX + 8, y: changeButton.frame.minY, width: 92, height: 40)
        let sliderBottom = bounds.height - safe.bottom - 18
        sizeSlider.frame = CGRect(x: safe.left + 18, y: sliderBottom - 34,
                                  width: max(150, bounds.width - safe.left - safe.right - 36), height: 30)
        zoomLabel.frame = CGRect(x: safe.left + 18, y: sizeSlider.frame.minY - 28, width: 100, height: 24)

        // Only rebuild base geometry when the container actually changes
        // (initial layout or rotation). Routine zoom layout never resets it.
        if bounds.size != lastContainerSize, bounds.width > 0, bounds.height > 0 {
            rebuildImageGeometry(preserveZoom: lastContainerSize != .zero)
        }
        centerImageIfNeeded()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImageIfNeeded()
        sizeSlider.value = Float(scrollView.zoomScale)
        updateZoomAccessibility()
    }

    private func centerImageIfNeeded() {
        let horizontal = max(0, (bounds.width - imageView.frame.width) / 2)
        let vertical = max(0, (bounds.height - imageView.frame.height) / 2)
        scrollView.contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }

    @objc private func doubleTapped(_ recognizer: UITapGestureRecognizer) {
        if scrollView.zoomScale > 1.15 {
            scrollView.setZoomScale(1, animated: true)
        } else {
            let location = recognizer.location(in: imageView)
            let targetZoom: CGFloat = 2.5
            let size = CGSize(width: scrollView.bounds.width / targetZoom, height: scrollView.bounds.height / targetZoom)
            scrollView.zoom(to: CGRect(x: location.x - size.width / 2, y: location.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }

    @objc private func sizeSliderChanged() {
        scrollView.setZoomScale(CGFloat(sizeSlider.value), animated: false)
    }

    @objc private func resetPhoto() {
        scrollView.setZoomScale(1, animated: false)
        centerImageIfNeeded()
        centerCurrentImage()
        updateZoomAccessibility()
    }

    func resetScene() { resetPhoto() }

    private func selectBuiltIn(at index: Int) {
        guard builtInImages.indices.contains(index) else { return }
        selectedBuiltInIndex = index
        setPhoto(builtInImages[index].image)
        rebuildImageMenu()
    }

    private func setPhoto(_ image: UIImage) {
        imageView.image = image
        rebuildImageGeometry(preserveZoom: false)
    }

    private func rebuildImageGeometry(preserveZoom: Bool) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let oldZoom = preserveZoom ? scrollView.zoomScale : 1
        scrollView.setZoomScale(1, animated: false)
        imageView.transform = .identity
        let source = imageView.image?.size ?? CGSize(width: 4, height: 3)
        let maximum = CGSize(width: bounds.width * 0.80, height: bounds.height * 0.60)
        let scale = min(maximum.width / max(source.width, 1), maximum.height / max(source.height, 1))
        let fitted = CGSize(width: max(44, source.width * scale), height: max(44, source.height * scale))
        imageView.frame = CGRect(origin: .zero, size: fitted)
        scrollView.contentSize = fitted
        scrollView.setZoomScale(min(max(oldZoom, scrollView.minimumZoomScale), scrollView.maximumZoomScale), animated: false)
        lastContainerSize = bounds.size
        centerImageIfNeeded()
        centerCurrentImage()
        updateZoomAccessibility()
    }

    private func centerCurrentImage() {
        let inset = scrollView.contentInset
        let scaledSize = imageView.frame.size
        let minimumX = -inset.left, minimumY = -inset.top
        let maximumX = max(minimumX, scaledSize.width - scrollView.bounds.width + inset.right)
        let maximumY = max(minimumY, scaledSize.height - scrollView.bounds.height + inset.bottom)
        scrollView.contentOffset = CGPoint(x: (minimumX + maximumX) / 2, y: (minimumY + maximumY) / 2)
    }

    private func updateZoomAccessibility() {
        let value = String(format: "scale %.2f", Double(scrollView.zoomScale))
        imageView.accessibilityLabel = selectedBuiltInIndex.flatMap {builtInImages.indices.contains($0) ? builtInImages[$0].name : nil} ?? "系统选择的测试图片"
        scrollView.accessibilityValue = value
        imageView.accessibilityValue = value
        sizeSlider.accessibilityValue = value
        zoomLabel.text = "\(Int(round(scrollView.zoomScale * 100)))%"
    }

    private func rebuildImageMenu() {
        var actions: [UIMenuElement] = builtInImages.enumerated().map { index, item in
            UIAction(title: item.name, image: UIImage(systemName: "photo"), state: selectedBuiltInIndex == index ? .on : .off) { [weak self] _ in
                self?.selectBuiltIn(at: index)
            }
        }
        actions.append(UIAction(title: "从系统相册选择…", image: UIImage(systemName: "photo.on.rectangle.angled")) { [weak self] _ in
            self?.presentPhotoPicker()
        })
        changeButton.menu = UIMenu(title: "选择测试图片", children: actions)
    }

    private func presentPhotoPicker() {
        guard sceneIsActive, presentedPicker == nil, let controller = nearestViewController() else { return }
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        presentedPicker = picker
        controller.present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        presentedPicker = nil
        guard sceneIsActive, let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let image = object as? UIImage else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.sceneIsActive else { return }
                self.selectedBuiltInIndex = nil
                self.setPhoto(image)
                self.rebuildImageMenu()
            }
        }
    }

    private func nearestViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController { return controller }
            responder = current.next
        }
        return nil
    }

    func stopScene() {
        sceneIsActive = false
        presentedPicker?.delegate = nil
        presentedPicker?.dismiss(animated: false)
        presentedPicker = nil
    }

    private static func loadBuiltInImages(from folder: URL?) -> [(name: String, image: UIImage)] {
        let definitions = [
            ("湖景照片", "lake-photo-v1.png", UIColor(red: 0.10, green: 0.48, blue: 0.62, alpha: 1)),
            ("战场细节", "moba-battlefield-v1.png", UIColor(red: 0.30, green: 0.52, blue: 0.25, alpha: 1)),
            ("靶场细节", "shooter-training-v1.png", UIColor(red: 0.50, green: 0.32, blue: 0.20, alpha: 1))
        ]
        return definitions.map { name, file, color in
            let image = folder.flatMap { UIImage(contentsOfFile: $0.appendingPathComponent(file).path) }
                ?? placeholderPhoto(title: name, accent: color)
            return (name, image)
        }
    }

    private static func placeholderPhoto(title: String, accent: UIColor) -> UIImage {
        let size = CGSize(width: 1400, height: 1000)
        return UIGraphicsImageRenderer(size: size).image { renderer in
            let cg = renderer.cgContext
            let colors = [UIColor(red: 0.05, green: 0.16, blue: 0.29, alpha: 1).cgColor,
                          accent.cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            accent.withAlphaComponent(0.75).setFill()
            UIBezierPath(roundedRect: CGRect(x: 0, y: 590, width: 1400, height: 410), cornerRadius: 0).fill()
            UIColor.white.withAlphaComponent(0.72).setFill()
            UIBezierPath(ovalIn: CGRect(x: 1030, y: 100, width: 170, height: 170)).fill()
            let text = title
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

private final class NativeReadingView: UIView, UITextViewDelegate {
    private let heading = EverydayTheme.title("原生阅读", detail: "默认上下连续滚动，也可切换为横向逐页翻阅")
    private let modeControl = UISegmentedControl(items: ["上下连续", "横向翻页"])
    private let verticalTextView = UITextView()
    private let pagedScrollView = UIScrollView()
    private let pageControl = UIPageControl()
    private let fontControl = UISegmentedControl(items: ["A−", "18 pt", "A+"])
    private var bodyFontSize: CGFloat = 18
    private var pageViews: [UIView] = []
    private let pages: [(String, String)] = [
        ("第一章 · 雨停时", "傍晚六点，雨声忽然从屋檐上退了下去。林澈推开窗，潮湿的风带着栀子叶的气味，穿过安静的房间。街面像一块刚擦亮的玻璃，红绿灯和行人的伞都在水光里留下细长的倒影。\n\n他拿起外套下楼，没有带伞。巷口卖栗子的老人重新掀开炉盖，白汽在暮色中慢慢散开；两个孩子踩着积水跑过，笑声撞在墙上，又轻轻落回路边。林澈沿着熟悉的石板路往河边走，鞋底每一步都发出清脆的水声。\n\n这座城在雨后显得比平日宽阔。许多被车声和尘土遮住的小事重新出现：窗台上的蓝花盆、修鞋铺门前睡醒的猫、远处钟楼被云隙照亮的一角。林澈忽然想起，多年前的一个雨天，也有人与他并肩走过这里，只是那时他们都急着赶路，没有认真看过这座城。"),
        ("第二章 · 旧书店", "河岸转角有一家旧书店，木门上的铜铃被风吹得轻响。林澈原以为它早已关门，没想到门内仍亮着一盏暖黄的灯。店主是一位头发花白的女人，正把受潮的书一本本摊开放在桌上。她抬头看见他，只说：“雨停了，进来坐坐吧。”\n\n书架比记忆里更拥挤，过道只容一人侧身经过。林澈在最里面发现一本绿色封皮的旅行笔记，纸页间夹着一张褪色车票，日期恰好是十二年前的今天。车票背面写着一行铅笔字：如果错过末班车，就在城里多留一晚。字迹陌生，却让他站了很久。\n\n店主端来一杯热茶，说那本书曾属于一位常客。那人喜欢在雨天来，把走过的地方画成小小的地图，后来去了北方，再没有回来。林澈翻到最后一页，那里只画着这座城的河流和桥，桥边标了一颗星。星的位置，正是他每天经过却从未停留的旧码头。"),
        ("第三章 · 桥上的灯", "夜色完全落下时，林澈带着那本笔记来到旧码头。河水涨了些，落叶向东流去。桥栏上的灯一盏接一盏亮起，把湿漉漉的石阶照成柔和的金色。笔记里的星落在桥中央，那里只有一张面向河面的长椅。\n\n长椅上坐着一个抱小提琴盒的女孩。她说自己在等最后一班公交，却因为喜欢雨后的河面，故意错过了两班。林澈把笔记上的地图给她看，女孩认真对照远处的屋顶，发现图里少了一座新建的高楼，也多了一排已经拆掉的仓库。时间像两层透明的纸，在灯影里慢慢叠在一起。\n\n女孩打开琴盒，取出小提琴，试着拉了一段很短的旋律。声音起初有些犹豫，随后顺着河面飘远。桥上的行人放慢脚步，卖花的人停下自行车，连水边觅食的鸟也安静了一会儿。曲子结束后，林澈在笔记空白处补上今晚的桥灯，并写道：有些地方并不等待谁，它只是一直亮着，让偶然停下的人看见彼此。"),
        ("第四章 · 清晨来信", "第二天清晨，云层散开，阳光从楼群之间落进街道。林澈把旅行笔记送回书店，又买下一叠素白的信纸。他坐在临窗的小桌旁，给多年未见的朋友写信，没有解释迟来的原因，只写昨夜的河、桥上的琴声，以及那张夹在书里的旧车票。\n\n写到最后，他停笔看向窗外。城市正在醒来：面包店拉开卷帘门，清洁车慢慢驶过，学生背着书包在路口等待绿灯。昨夜积水里的倒影已经消失，石板路恢复了寻常的灰色，可他知道，那些被雨洗亮的细节并没有真正离开，只是重新藏进忙碌的日子里。\n\n店主替他找来信封，又从抽屉里取出一枚旧邮票。她说，旅行笔记的主人曾相信，每一封认真写下的信都能改变一条路的方向。林澈笑着把信封好，走到街角的邮筒前。投信的一刻，钟楼敲响了八点。他没有立刻回家，而是沿着河岸继续向前，准备去看看地图上那些尚未画出的地方。")
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.94, green: 0.92, blue: 0.85, alpha: 1)
        modeControl.selectedSegmentIndex = 0
        modeControl.selectedSegmentTintColor = UIColor(white: 0.20, alpha: 1)
        modeControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        modeControl.addTarget(self, action: #selector(readingModeChanged), for: .valueChanged)
        addSubview(modeControl)

        verticalTextView.isEditable = false
        verticalTextView.isSelectable = true
        verticalTextView.alwaysBounceVertical = true
        verticalTextView.showsVerticalScrollIndicator = true
        verticalTextView.backgroundColor = .clear
        verticalTextView.textColor = UIColor(red: 0.25, green: 0.21, blue: 0.16, alpha: 1)
        verticalTextView.textContainerInset = UIEdgeInsets(top: 20, left: 20, bottom: 34, right: 20)
        verticalTextView.delegate = self
        verticalTextView.accessibilityIdentifier = "native-reader-scroll"
        verticalTextView.accessibilityLabel = "上下连续阅读内容"
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {verticalTextView.accessibilityValue = "offsetY 0"}
        addSubview(verticalTextView)

        pagedScrollView.isPagingEnabled = true
        pagedScrollView.isDirectionalLockEnabled = true
        pagedScrollView.showsHorizontalScrollIndicator = false
        pagedScrollView.alwaysBounceHorizontal = true
        pagedScrollView.delegate = self
        pagedScrollView.contentInsetAdjustmentBehavior = .never
        pagedScrollView.isHidden = true
        addSubview(pagedScrollView)
        for (title, body) in pages {
            let page = UIView(); page.backgroundColor = .clear
            let titleLabel = UILabel(); titleLabel.text = title; titleLabel.textColor = UIColor(red: 0.18, green: 0.14, blue: 0.10, alpha: 1); titleLabel.font = .systemFont(ofSize: 25, weight: .bold); titleLabel.numberOfLines = 2
            let bodyText = UITextView(); bodyText.text = body; bodyText.textColor = UIColor(red: 0.25, green: 0.21, blue: 0.16, alpha: 1); bodyText.font = .systemFont(ofSize: 18, weight: .regular)
            bodyText.isEditable = false; bodyText.isSelectable = true; bodyText.alwaysBounceVertical = true; bodyText.isDirectionalLockEnabled = true
            bodyText.backgroundColor = .clear; bodyText.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 24, right: 0)
            page.addSubview(titleLabel); page.addSubview(bodyText)
            titleLabel.tag = 101; bodyText.tag = 102
            pagedScrollView.addSubview(page); pageViews.append(page)
        }
        pageControl.numberOfPages = pages.count
        pageControl.currentPage = 0
        pageControl.isHidden = true
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
        rebuildContinuousText()
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        let safe = safeAreaInsets
        heading.frame = CGRect(x: safe.left + 12, y: safe.top + 10,
                               width: max(150, bounds.width - safe.left - safe.right - 96), height: 58)
        modeControl.frame = CGRect(x: safe.left + 14, y: safe.top + 76, width: 190, height: 34)
        fontControl.frame = CGRect(x: safe.left + 14, y: safe.top + 116, width: 190, height: 34)
        let top = safe.top + 158
        verticalTextView.frame = CGRect(x: safe.left, y: top, width: bounds.width - safe.left - safe.right,
                                        height: max(100, bounds.height - top - safe.bottom - 8))
        let pagedBottom = safe.bottom + 38
        pagedScrollView.frame = CGRect(x: 0, y: top, width: bounds.width, height: max(100, bounds.height - top - pagedBottom))
        for (index, page) in pageViews.enumerated() {
            page.frame = CGRect(x: CGFloat(index) * pagedScrollView.bounds.width, y: 0, width: pagedScrollView.bounds.width, height: pagedScrollView.bounds.height)
            let inset = max(26, safe.left + 22)
            let title = page.viewWithTag(101) as? UILabel
            title?.frame = CGRect(x: inset, y: 25, width: page.bounds.width - inset * 2, height: 72)
            let body = page.viewWithTag(102) as? UITextView
            body?.frame = CGRect(x: inset, y: 108, width: page.bounds.width - inset * 2, height: max(44, page.bounds.height - 130))
        }
        pagedScrollView.contentSize = CGSize(width: pagedScrollView.bounds.width * CGFloat(pageViews.count), height: pagedScrollView.bounds.height)
        if !pagedScrollView.isDragging && !pagedScrollView.isDecelerating { pagedScrollView.contentOffset.x = CGFloat(pageControl.currentPage) * pagedScrollView.bounds.width }
        pageControl.frame = CGRect(x: safe.left, y: bounds.height - safe.bottom - 36, width: bounds.width - safe.left - safe.right, height: 28)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView === verticalTextView {
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {verticalTextView.accessibilityValue = String(format: "offsetY %.1f", Double(max(0, scrollView.contentOffset.y)))}
        } else if scrollView === pagedScrollView, scrollView.bounds.width > 0 {
            pageControl.currentPage = max(0, min(pages.count - 1, Int(round(scrollView.contentOffset.x / scrollView.bounds.width))))
        }
    }

    @objc private func pageChanged() {
        pagedScrollView.setContentOffset(CGPoint(x: CGFloat(pageControl.currentPage) * pagedScrollView.bounds.width, y: 0), animated: true)
    }

    @objc private func readingModeChanged() {
        let continuous = modeControl.selectedSegmentIndex == 0
        verticalTextView.isHidden = !continuous
        pagedScrollView.isHidden = continuous
        pageControl.isHidden = continuous
    }

    @objc private func fontControlChanged() {
        if fontControl.selectedSegmentIndex == 0 { bodyFontSize = max(14, bodyFontSize - 1) }
        if fontControl.selectedSegmentIndex == 2 { bodyFontSize = min(28, bodyFontSize + 1) }
        fontControl.setTitle("\(Int(bodyFontSize)) pt", forSegmentAt: 1)
        fontControl.selectedSegmentIndex = 1
        for page in pageViews {
            (page.viewWithTag(102) as? UITextView)?.font = .systemFont(ofSize: bodyFontSize, weight: .regular)
        }
        rebuildContinuousText()
    }

    private func rebuildContinuousText() {
        let output = NSMutableAttributedString()
        for (index, page) in pages.enumerated() {
            if index > 0 { output.append(NSAttributedString(string: "\n\n")) }
            output.append(NSAttributedString(string: page.0 + "\n", attributes: [
                .font: UIFont.systemFont(ofSize: bodyFontSize + 7, weight: .bold),
                .foregroundColor: UIColor(red: 0.18, green: 0.14, blue: 0.10, alpha: 1)
            ]))
            let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 5; paragraph.paragraphSpacing = 9
            output.append(NSAttributedString(string: page.1, attributes: [
                .font: UIFont.systemFont(ofSize: bodyFontSize, weight: .regular),
                .foregroundColor: UIColor(red: 0.25, green: 0.21, blue: 0.16, alpha: 1),
                .paragraphStyle: paragraph
            ]))
        }
        verticalTextView.attributedText = output
    }
}

// MARK: - Local video player

private final class NativeVideoView: UIView, NativeSceneLifecycle, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate, UIGestureRecognizerDelegate {
    private struct FeedEntry {
        let title: String
        let caption: String
        let startFraction: Double
        let endFraction: Double
        let baseLikes: Int
    }

    /// These are explicitly four practice ranges cut from the same bundled
    /// clip. The UI never presents them as four independent videos.
    private let entries: [FeedEntry] = [
        FeedEntry(title: "慢速跟手", caption: "缓慢上下滑动，观察画面切换和触点连续性。", startFraction: 0.00, endFraction: 0.25, baseLikes: 18),
        FeedEntry(title: "快速连刷", caption: "连续短距离上刷，检查是否漏触或误触按钮。", startFraction: 0.25, endFraction: 0.50, baseLikes: 26),
        FeedEntry(title: "暂停与拖动", caption: "暂停后拖动进度，再恢复播放检查控制精度。", startFraction: 0.50, endFraction: 0.75, baseLikes: 14),
        FeedEntry(title: "边缘操作", caption: "从左右边缘开始操作，并测试评论输入。", startFraction: 0.75, endFraction: 1.00, baseLikes: 31)
    ]

    private let playerLayer = AVPlayerLayer()
    private let feedFilter = UISegmentedControl(items: ["关注", "推荐"])
    private let rangeLabel = UILabel()
    private let titleLabel = UILabel()
    private let captionLabel = UILabel()
    private let progressSlider = UISlider()
    private let playButton = EverydayTheme.button("暂停", image: "pause.fill")
    private let rightActions = UIStackView()
    private let avatarButton = UIButton(type: .system)
    private let likeButton = UIButton(type: .system)
    private let commentButton = UIButton(type: .system)
    private let shareButton = UIButton(type: .system)
    private let bottomBar = UIView()
    private var bottomButtons: [UIButton] = []

    private let commentsPanel = UIView()
    private let commentsTitle = UILabel()
    private let commentsTable = UITableView(frame: .zero, style: .plain)
    private let commentField = UITextField()
    private let sendButton = UIButton(type: .system)
    private let closeCommentsButton = UIButton(type: .system)

    private let sectionOverlay = UIView()
    private let sectionTitle = UILabel()
    private let sectionBody = UILabel()
    private let closeSectionButton = UIButton(type: .system)

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var periodicObserver: Any?
    private var keyboardObservers: [NSObjectProtocol] = []
    private var keyboardOffset: CGFloat = 0
    private var sourceURL: URL?
    private var feedOrder = [0, 1, 2, 3]
    private var feedPosition = 0
    private var liked = Array(repeating: false, count: 4)
    private var comments: [[String]] = [
        ["这里可以测试评论输入和键盘。"], ["连续上刷时按钮不应被误触。"], [], ["试试从屏幕边缘开始滑动。"]
    ]
    private var userIsScrubbing = false
    private var wasPlayingBeforePause = false
    private var isLifecyclePaused = false

    private var currentEntryIndex: Int { feedOrder[feedPosition] }

    init(assetFolder: URL?) {
        super.init(frame: .zero)
        backgroundColor = .black
        layer.addSublayer(playerLayer)
        playerLayer.videoGravity = .resizeAspectFill

        feedFilter.selectedSegmentIndex = 1
        feedFilter.selectedSegmentTintColor = UIColor.white.withAlphaComponent(0.92)
        feedFilter.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
        feedFilter.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        feedFilter.backgroundColor = UIColor.black.withAlphaComponent(0.40)
        feedFilter.addTarget(self, action: #selector(feedFilterChanged), for: .valueChanged)
        addSubview(feedFilter)

        rangeLabel.textColor = UIColor.white.withAlphaComponent(0.82)
        rangeLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        rangeLabel.backgroundColor = UIColor.black.withAlphaComponent(0.42)
        rangeLabel.layer.cornerRadius = 9; rangeLabel.clipsToBounds = true
        rangeLabel.textAlignment = .center
        rangeLabel.accessibilityIdentifier = "video-index"
        addSubview(rangeLabel)

        titleLabel.textColor = .white; titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        captionLabel.textColor = .white; captionLabel.font = .systemFont(ofSize: 14, weight: .regular); captionLabel.numberOfLines = 2
        addSubview(titleLabel); addSubview(captionLabel)

        progressSlider.minimumValue = 0; progressSlider.maximumValue = 1
        progressSlider.minimumTrackTintColor = .white
        progressSlider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.35)
        progressSlider.addTarget(self, action: #selector(scrubStarted), for: .touchDown)
        progressSlider.addTarget(self, action: #selector(scrubChanged), for: .valueChanged)
        progressSlider.addTarget(self, action: #selector(scrubEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        progressSlider.accessibilityIdentifier = "video-progress"
        progressSlider.accessibilityLabel = "当前练习片段进度"
        addSubview(progressSlider)

        playButton.addTarget(self, action: #selector(togglePlay), for: .touchUpInside)
        addSubview(playButton)

        configureActionButton(avatarButton, image: "person.crop.circle.fill", title: "本地")
        configureActionButton(likeButton, image: "heart", title: "赞")
        configureActionButton(commentButton, image: "bubble.right", title: "评论")
        configureActionButton(shareButton, image: "square.and.arrow.up", title: "分享")
        likeButton.accessibilityIdentifier = "video-like"
        commentButton.accessibilityIdentifier = "video-comment"
        avatarButton.addTarget(self, action: #selector(showLocalProfile), for: .touchUpInside)
        likeButton.addTarget(self, action: #selector(toggleLike), for: .touchUpInside)
        commentButton.addTarget(self, action: #selector(showComments), for: .touchUpInside)
        shareButton.addTarget(self, action: #selector(shareEntry), for: .touchUpInside)
        rightActions.axis = .vertical; rightActions.spacing = 8; rightActions.distribution = .fillEqually
        [avatarButton, likeButton, commentButton, shareButton].forEach { rightActions.addArrangedSubview($0) }
        addSubview(rightActions)

        configureBottomBar()
        configureCommentsPanel()
        configureSectionOverlay()
        let center = NotificationCenter.default
        keyboardObservers = [UIResponder.keyboardWillChangeFrameNotification, UIResponder.keyboardWillHideNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in self?.keyboardFrameChanged(note) }
        }

        let up = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:))); up.direction = .up; up.delegate = self
        let down = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:))); down.direction = .down; down.delegate = self
        addGestureRecognizer(up); addGestureRecognizer(down)

        if let folder = assetFolder, let contents = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            sourceURL = contents.filter { ["mp4", "mov", "m4v"].contains($0.pathExtension.lowercased()) }.sorted { $0.lastPathComponent < $1.lastPathComponent }.first
        }
        if sourceURL == nil, let folder = assetFolder {
            let fallback = folder.appendingPathComponent("flower-cc0.mp4")
            if FileManager.default.fileExists(atPath: fallback.path) { sourceURL = fallback }
        }
        preparePlayer()
        updateFeedUI()
    }

    required init?(coder: NSCoder) { nil }
    deinit { stopScene() }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
        let safe = safeAreaInsets
        let topAvailableRight = safe.right + 72
        feedFilter.frame = CGRect(x: max(safe.left + 12, (bounds.width - topAvailableRight - 174) / 2), y: safe.top + 10, width: 174, height: 34)
        rangeLabel.frame = CGRect(x: safe.left + 12, y: safe.top + 52, width: min(250, bounds.width - safe.left - topAvailableRight - 18), height: 24)

        let tabHeight: CGFloat = 56
        bottomBar.frame = CGRect(x: 0, y: bounds.height - safe.bottom - tabHeight, width: bounds.width, height: tabHeight)
        let buttonWidth = bottomBar.bounds.width / CGFloat(max(bottomButtons.count, 1))
        for (index, button) in bottomButtons.enumerated() { button.frame = CGRect(x: CGFloat(index) * buttonWidth, y: 0, width: buttonWidth, height: tabHeight) }

        rightActions.frame = CGRect(x: bounds.width - safe.right - 70,
                                    y: max(safe.top + 94, bounds.height - safe.bottom - 390), width: 58, height: 250)
        let copyRight = safe.right + 84
        let copyBottom = bottomBar.frame.minY - 8
        progressSlider.frame = CGRect(x: safe.left + 14, y: copyBottom - 36,
                                      width: max(120, bounds.width - safe.left - copyRight - 14), height: 28)
        playButton.frame = CGRect(x: safe.left + 14, y: progressSlider.frame.minY - 48, width: 104, height: 40)
        captionLabel.frame = CGRect(x: safe.left + 14, y: playButton.frame.minY - 52,
                                    width: max(130, bounds.width - safe.left - copyRight - 16), height: 48)
        titleLabel.frame = CGRect(x: safe.left + 14, y: captionLabel.frame.minY - 30,
                                  width: max(130, bounds.width - safe.left - copyRight - 16), height: 26)

        layoutCommentsPanel()
        sectionOverlay.frame = CGRect(x: safe.left + 10, y: safe.top + 82,
                                      width: bounds.width - safe.left - safe.right - 20,
                                      height: max(220, bottomBar.frame.minY - safe.top - 94))
        closeSectionButton.frame = CGRect(x: sectionOverlay.bounds.width - 48, y: 10, width: 38, height: 38)
        sectionTitle.frame = CGRect(x: 20, y: 16, width: sectionOverlay.bounds.width - 78, height: 34)
        sectionBody.frame = CGRect(x: 20, y: 58, width: sectionOverlay.bounds.width - 40, height: sectionOverlay.bounds.height - 76)
    }

    private func configureActionButton(_ button: UIButton, image: String, title: String) {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: image)
        configuration.title = title
        configuration.imagePlacement = .top
        configuration.imagePadding = 3
        configuration.baseForegroundColor = .white
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var result = incoming; result.font = .systemFont(ofSize: 11, weight: .semibold); return result
        }
        button.configuration = configuration
        button.backgroundColor = UIColor.black.withAlphaComponent(0.40)
        button.layer.cornerRadius = 22
    }

    private func configureBottomBar() {
        bottomBar.backgroundColor = UIColor.black.withAlphaComponent(0.78)
        addSubview(bottomBar)
        let tabs = [("首页", "house.fill"), ("发现", "magnifyingglass"), ("创建", "plus.app.fill"), ("消息", "message.fill"), ("我的", "person.fill")]
        for (index, item) in tabs.enumerated() {
            let button = UIButton(type: .system)
            var configuration = UIButton.Configuration.plain()
            configuration.title = item.0; configuration.image = UIImage(systemName: item.1)
            configuration.imagePlacement = .top; configuration.imagePadding = 2
            configuration.baseForegroundColor = index == 0 ? .white : UIColor.white.withAlphaComponent(0.55)
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var result = incoming; result.font = .systemFont(ofSize: 10, weight: .semibold); return result
            }
            button.configuration = configuration; button.tag = index
            button.addTarget(self, action: #selector(bottomTabSelected(_:)), for: .touchUpInside)
            bottomBar.addSubview(button); bottomButtons.append(button)
        }
    }

    private func configureCommentsPanel() {
        commentsPanel.backgroundColor = UIColor(white: 0.08, alpha: 0.98)
        commentsPanel.layer.cornerRadius = 20; commentsPanel.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        commentsPanel.isHidden = true
        addSubview(commentsPanel)
        commentsTitle.text = "本地评论"; commentsTitle.textColor = .white; commentsTitle.font = .systemFont(ofSize: 18, weight: .bold)
        closeCommentsButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal); closeCommentsButton.tintColor = .white
        closeCommentsButton.addTarget(self, action: #selector(hideComments), for: .touchUpInside)
        commentsTable.backgroundColor = .clear; commentsTable.separatorColor = UIColor.white.withAlphaComponent(0.15)
        commentsTable.dataSource = self; commentsTable.delegate = self
        commentsTable.register(UITableViewCell.self, forCellReuseIdentifier: "comment")
        commentField.placeholder = "写一条本地评论…"; commentField.textColor = .white; commentField.tintColor = .white
        commentField.attributedPlaceholder = NSAttributedString(string: "写一条本地评论…", attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.45)])
        commentField.backgroundColor = UIColor.white.withAlphaComponent(0.10); commentField.layer.cornerRadius = 17
        commentField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1)); commentField.leftViewMode = .always
        commentField.returnKeyType = .send; commentField.delegate = self
        commentField.accessibilityIdentifier = "video-comment-input"
        sendButton.setTitle("发送", for: .normal); sendButton.setTitleColor(.white, for: .normal); sendButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        sendButton.accessibilityIdentifier = "video-comment-send"
        sendButton.addTarget(self, action: #selector(sendComment), for: .touchUpInside)
        closeCommentsButton.accessibilityIdentifier = "video-close-comments"
        [commentsTitle, closeCommentsButton, commentsTable, commentField, sendButton].forEach { commentsPanel.addSubview($0) }
    }

    private func layoutCommentsPanel() {
        let safe = safeAreaInsets
        let panelHeight = min(360, max(250, bounds.height - safe.top - 100))
        commentsPanel.frame = CGRect(x: 0, y: bounds.height - safe.bottom - panelHeight - keyboardOffset, width: bounds.width, height: panelHeight)
        commentsTitle.frame = CGRect(x: 18, y: 14, width: commentsPanel.bounds.width - 80, height: 32)
        closeCommentsButton.frame = CGRect(x: commentsPanel.bounds.width - 52, y: 10, width: 42, height: 42)
        commentField.frame = CGRect(x: 14, y: commentsPanel.bounds.height - 52, width: commentsPanel.bounds.width - 92, height: 38)
        sendButton.frame = CGRect(x: commentsPanel.bounds.width - 72, y: commentsPanel.bounds.height - 52, width: 62, height: 38)
        commentsTable.frame = CGRect(x: 0, y: 54, width: commentsPanel.bounds.width, height: commentsPanel.bounds.height - 112)
    }

    private func configureSectionOverlay() {
        sectionOverlay.backgroundColor = UIColor(white: 0.06, alpha: 0.97)
        sectionOverlay.layer.cornerRadius = 22; sectionOverlay.layer.borderWidth = 1; sectionOverlay.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
        sectionOverlay.isHidden = true
        sectionTitle.textColor = .white; sectionTitle.font = .systemFont(ofSize: 23, weight: .bold)
        sectionBody.textColor = UIColor.white.withAlphaComponent(0.78); sectionBody.font = .systemFont(ofSize: 16); sectionBody.numberOfLines = 0; sectionBody.textAlignment = .center
        closeSectionButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal); closeSectionButton.tintColor = .white
        closeSectionButton.addTarget(self, action: #selector(closeSection), for: .touchUpInside)
        [sectionTitle, sectionBody, closeSectionButton].forEach { sectionOverlay.addSubview($0) }
        addSubview(sectionOverlay)
    }

    private func keyboardFrameChanged(_ notification: Notification) {
        let endFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
        let localFrame = convert(endFrame, from: nil)
        keyboardOffset = notification.name == UIResponder.keyboardWillHideNotification ? 0 : max(0, bounds.maxY - localFrame.minY - safeAreaInsets.bottom)
        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
        UIView.animate(withDuration: duration) { self.layoutCommentsPanel() }
    }

    private func preparePlayer() {
        guard let sourceURL else {
            rangeLabel.text = "未找到本地视频资源"
            playButton.isEnabled = false; progressSlider.isEnabled = false
            return
        }
        let item = AVPlayerItem(url: sourceURL)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer; playerLayer.player = newPlayer
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            self?.seekToCurrentEntry(autoplay: true)
        }
        periodicObserver = newPlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
            self?.playerTimeChanged(time)
        }
        seekToCurrentEntry(autoplay: true)
    }

    private func segmentBounds() -> (start: Double, end: Double)? {
        guard let duration = player?.currentItem?.duration.seconds, duration.isFinite, duration > 0.2 else { return nil }
        let entry = entries[currentEntryIndex]
        let start = min(duration - 0.1, max(0, duration * entry.startFraction))
        let end = min(duration, max(start + min(0.8, duration), duration * entry.endFraction))
        return (start, end)
    }

    private func seekToCurrentEntry(autoplay: Bool) {
        guard let player else { return }
        let start = segmentBounds()?.start ?? 0
        player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self, autoplay, !self.isLifecyclePaused else { return }
            self.player?.play(); self.setPlayingUI(true)
        }
    }

    private func playerTimeChanged(_ time: CMTime) {
        guard let limits = segmentBounds(), !userIsScrubbing else { return }
        let seconds = time.seconds
        if seconds < limits.start - 0.15 {
            seekToCurrentEntry(autoplay: player?.timeControlStatus == .playing)
            return
        }
        if seconds >= limits.end - 0.03 {
            seekToCurrentEntry(autoplay: player?.timeControlStatus == .playing)
            return
        }
        progressSlider.value = Float(max(0, min(1, (seconds - limits.start) / max(0.01, limits.end - limits.start))))
        progressSlider.accessibilityValue = "\(Int(round(progressSlider.value * 100)))%"
    }

    private func updateFeedUI() {
        let entry = entries[currentEntryIndex]
        let list = feedFilter.selectedSegmentIndex == 0 ? "关注列表" : "推荐列表"
        rangeLabel.text = "\(list) · 同一离线素材分段 \(currentEntryIndex + 1)/4"
        rangeLabel.accessibilityValue = "index \(currentEntryIndex + 1) of 4"
        titleLabel.text = entry.title; captionLabel.text = entry.caption
        let count = entry.baseLikes + (liked[currentEntryIndex] ? 1 : 0)
        setActionButton(likeButton, image: liked[currentEntryIndex] ? "heart.fill" : "heart", title: "\(count)", highlighted: liked[currentEntryIndex])
        likeButton.accessibilityValue = "\(liked[currentEntryIndex] ? "selected" : "not-selected") count \(count)"
        setActionButton(commentButton, image: "bubble.right", title: "\(comments[currentEntryIndex].count)", highlighted: false)
        commentsTable.reloadData()
    }

    private func setActionButton(_ button: UIButton, image: String, title: String, highlighted: Bool) {
        var configuration = button.configuration
        configuration?.image = UIImage(systemName: image); configuration?.title = title
        configuration?.baseForegroundColor = highlighted ? .systemPink : .white
        button.configuration = configuration
    }

    private func setPlayingUI(_ playing: Bool) {
        var configuration = playButton.configuration
        configuration?.title = playing ? "暂停" : "播放"
        configuration?.image = UIImage(systemName: playing ? "pause.fill" : "play.fill")
        playButton.configuration = configuration
    }

    @objc private func feedFilterChanged() {
        feedOrder = feedFilter.selectedSegmentIndex == 0 ? [0, 2] : [0, 1, 2, 3]
        feedPosition = 0; progressSlider.value = 0; updateFeedUI(); seekToCurrentEntry(autoplay: true)
    }

    @objc private func togglePlay() {
        guard let player else { return }
        if player.timeControlStatus == .playing { player.pause(); setPlayingUI(false) }
        else { player.play(); setPlayingUI(true) }
    }

    @objc private func swiped(_ gesture: UISwipeGestureRecognizer) {
        guard !feedOrder.isEmpty else { return }
        let delta = gesture.direction == .up ? 1 : -1
        feedPosition = (feedPosition + delta + feedOrder.count) % feedOrder.count
        progressSlider.value = 0; updateFeedUI(); seekToCurrentEntry(autoplay: true)
    }

    @objc private func toggleLike() {
        liked[currentEntryIndex].toggle(); updateFeedUI()
    }

    @objc private func showComments() {
        sectionOverlay.isHidden = true; commentsPanel.isHidden = false
        bringSubviewToFront(commentsPanel); commentsTable.reloadData()
    }

    @objc private func hideComments() { commentField.resignFirstResponder(); commentsPanel.isHidden = true }
    @objc private func sendComment() {
        let text = commentField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return }
        comments[currentEntryIndex].append(text); commentField.text = ""; updateFeedUI()
        let row = comments[currentEntryIndex].count - 1
        commentsTable.scrollToRow(at: IndexPath(row: row, section: 0), at: .bottom, animated: true)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool { sendComment(); return true }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { comments[currentEntryIndex].count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "comment", for: indexPath)
        var content = cell.defaultContentConfiguration(); content.text = comments[currentEntryIndex][indexPath.row]
        content.textProperties.color = .white; content.textProperties.font = .systemFont(ofSize: 14)
        cell.contentConfiguration = content; cell.backgroundColor = .clear; cell.selectionStyle = .none
        return cell
    }

    @objc private func showLocalProfile() {
        showSection(title: "本地练习账户", body: "这是离线触控练习入口。\n\n当前 feed 使用同一段内置素材划分为四个播放区间，不会上传头像、观看记录、评论或点赞。")
    }

    @objc private func shareEntry() {
        let entry = entries[currentEntryIndex]
        let text = "Touch Test 离线短视频练习：\(entry.title)（同一内置素材的第 \(currentEntryIndex + 1) 个练习区间）"
        guard let controller = nearestViewController() else { showSection(title: "分享", body: text); return }
        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = shareButton
        activity.popoverPresentationController?.sourceRect = shareButton.bounds
        controller.present(activity, animated: true)
    }

    @objc private func bottomTabSelected(_ sender: UIButton) {
        for button in bottomButtons {
            var configuration = button.configuration
            configuration?.baseForegroundColor = button === sender ? .white : UIColor.white.withAlphaComponent(0.55)
            button.configuration = configuration
        }
        switch sender.tag {
        case 0: closeSection()
        case 1: showSection(title: "发现", body: "本地练习列表\n\n• 慢速跟手\n• 快速连刷\n• 暂停与拖动\n• 边缘操作\n\n四项均复用同一内置素材的不同播放区间。")
        case 2: showSection(title: "创建", body: "离线模式不会发布内容。\n\n这里用于测试中央按钮点击、页面切换和长文案触控，不会调用相机或上传文件。")
        case 3: showSection(title: "消息", body: "本地通知\n\n触控练习已就绪。所有评论与点赞仅保存在当前运行会话。")
        default: showLocalProfile()
        }
    }

    private func showSection(title: String, body: String) {
        hideComments(); sectionTitle.text = title; sectionBody.text = body; sectionOverlay.isHidden = false
        bringSubviewToFront(sectionOverlay)
    }

    @objc private func closeSection() {
        sectionOverlay.isHidden = true
        if let home = bottomButtons.first {
            for button in bottomButtons {
                var configuration = button.configuration
                configuration?.baseForegroundColor = button === home ? .white : UIColor.white.withAlphaComponent(0.55)
                button.configuration = configuration
            }
        }
    }

    @objc private func scrubStarted() { userIsScrubbing = true }
    @objc private func scrubChanged() {}
    @objc private func scrubEnded() {
        userIsScrubbing = false
        guard let limits = segmentBounds() else { return }
        let seconds = limits.start + Double(progressSlider.value) * (limits.end - limits.start)
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let touched = touch.view else { return true }
        if touched is UIControl { return false }
        if touched.isDescendant(of: commentsPanel) || touched.isDescendant(of: sectionOverlay) || touched.isDescendant(of: rightActions) || touched.isDescendant(of: bottomBar) { return false }
        return true
    }

    private func nearestViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController { return controller }
            responder = current.next
        }
        return nil
    }

    func stopScene() {
        isLifecyclePaused = false; wasPlayingBeforePause = false
        commentField.resignFirstResponder(); player?.pause()
        if let periodicObserver, let player { player.removeTimeObserver(periodicObserver) }
        periodicObserver = nil
        playerLayer.player = nil; player = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver); self.endObserver = nil }
        keyboardObservers.forEach { NotificationCenter.default.removeObserver($0) }
        keyboardObservers.removeAll()
    }

    func pauseScene() {
        guard !isLifecyclePaused else { return }
        isLifecyclePaused = true
        wasPlayingBeforePause = player?.timeControlStatus == .playing || player?.timeControlStatus == .waitingToPlayAtSpecifiedRate
        player?.pause(); commentField.resignFirstResponder()
        if wasPlayingBeforePause { setPlayingUI(false) }
    }

    func resumeScene() {
        guard isLifecyclePaused else { return }
        isLifecyclePaused = false
        if wasPlayingBeforePause { player?.play(); setPlayingUI(true) }
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
