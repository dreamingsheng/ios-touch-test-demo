import UIKit

// Native UIKit interaction scene. Background art is a local test asset; no HTML,
// web event forwarding, game SDK, or online game account is used here.
final class NativeGameScene: UIView, NativeSceneLifecycle {
    private enum Role { case move, look, control(String), ignored }
    private let mode: String
    private let picture: UIImage?
    private var controls: [String: NativeHUDControl] = [:]
    private var roles: [ObjectIdentifier: Role] = [:]
    private var previous: [ObjectIdentifier: CGPoint] = [:]
    private var moveID: ObjectIdentifier?
    private var lookID: ObjectIdentifier?
    private var stickOrigin = CGPoint.zero
    private var stickHome = CGPoint.zero
    private var vector = CGPoint.zero
    private var player = CGPoint.zero
    private var reticle = CGPoint.zero
    private var castVectors: [ObjectIdentifier: CGPoint] = [:]
    private var cancelledCasts: Set<ObjectIdentifier> = []
    private var pressed: [String: Set<ObjectIdentifier>] = [:]
    private var timer: Timer?
    private var notification: NSObjectProtocol?
    private var lastTick = CACurrentMediaTime()
    private var lastShot: CFTimeInterval = 0
    private var eventCount = 0
    private var fireCount = 0
    private var skillCount = 0
    private var cancelledCount = 0
    private var magazine = 40
    private var reserve = 180
    private var scoped = false
    private var stance = "站立"
    private var sensitivity: CGFloat = 1
    private var settingsPanel: UIView?
    private var lastSize = CGSize.zero
    private var lastSafe = UIEdgeInsets.zero
    private var feedback = ""
    private var feedbackUntil: CFTimeInterval = 0
    private var jumpUntil: CFTimeInterval = 0

    var editingLayout = false {
        didSet {
            clearPressed()
            controls.values.forEach {
                $0.isUserInteractionEnabled = editingLayout
                $0.layer.borderColor = (editingLayout ? UIColor.systemYellow : UIColor.clear).cgColor
                $0.layer.borderWidth = editingLayout ? 1 : 0
                $0.gestureRecognizers?.forEach { $0.isEnabled = editingLayout }
            }
            setNeedsDisplay()
        }
    }
    var diagnostics: String {
        "触点 \(roles.count) · 事件 \(eventCount) · 左轴 \(String(format: "%.2f,%.2f", Double(vector.x), Double(vector.y))) · " +
        (mode == "aim" ? "开火 \(fireCount) · 弹药 \(magazine)/\(reserve) · \(stance)" : "施放 \(skillCount) · 取消 \(cancelledCount)")
    }

    init(mode: String, assetFolder: URL?) {
        self.mode = mode
        let filename = mode == "aim" ? "shooter-training-v1.png" : "moba-battlefield-v1.png"
        picture = assetFolder.flatMap { UIImage(contentsOfFile: $0.appendingPathComponent(filename).path) }
        super.init(frame: .zero)
        backgroundColor = .black
        isMultipleTouchEnabled = true
        clipsToBounds = true
        accessibilityIdentifier = "native-game-\(mode)"
        add("stick", "", symbol: nil, size: 126, kind: .stick)
        add("map", "小地图", symbol: "map.fill", size: 76, kind: .square)
        controls["map"]?.mapImage = picture
        add("score", mode == "aim" ? "剩余 99  淘汰 0" : "0  :  0   00:00", symbol: nil, size: 120, kind: .bar)
        add("settings", "设置", symbol: "gearshape.fill", size: 34)
        if mode == "aim" {
            add("fire-left", "开火", symbol: "burst.fill", size: 56)
            add("fire", "开火", symbol: "burst.fill", size: 76)
            add("scope", "开镜", symbol: "scope", size: 47)
            add("reload", "换弹", symbol: "arrow.clockwise", size: 43)
            add("crouch", "蹲", symbol: "figure.seated.side", size: 43)
            add("prone", "趴", symbol: "figure.strengthtraining.traditional", size: 43)
            add("jump", "跳", symbol: "figure.jumprope", size: 43)
            add("weapon", "M416   40 / 180", symbol: nil, size: 160, kind: .bar)
            add("health", "██████████", symbol: nil, size: 160, kind: .bar)
        } else {
            add("attack", "攻击", symbol: "target", size: 82)
            add("skill1", "斩击", symbol: "sparkles", size: 58)
            add("skill2", "突进", symbol: "bolt.fill", size: 58)
            add("skill3", "爆发", symbol: "flame.fill", size: 64)
            add("flash", "闪现", symbol: "bolt.horizontal.fill", size: 43)
            add("recall", "回城", symbol: "house.fill", size: 40)
            add("heal", "恢复", symbol: "cross.fill", size: 40)
            add("health", "██████████", symbol: nil, size: 90, kind: .bar)
        }
        startTimer()
        notification = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.clearPressed() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { timer?.invalidate(); if let notification { NotificationCenter.default.removeObserver(notification) } }

    private func add(_ key: String, _ title: String, symbol: String?, size: CGFloat, kind: NativeHUDControl.Kind = .circle) {
        let control = NativeHUDControl(title: title, symbol: symbol, kind: kind)
        control.accessibilityIdentifier = "game-control-\(key)"
        control.isAccessibilityElement = true
        control.accessibilityLabel = title.isEmpty ? "移动轮盘" : title
        control.bounds = CGRect(x: 0, y: 0, width: size, height: kind == .bar ? 28 : size)
        control.isUserInteractionEnabled = false
        let pan = UIPanGestureRecognizer(target: self, action: #selector(moveControl(_:)))
        pan.isEnabled = false; pan.maximumNumberOfTouches = 1
        control.addGestureRecognizer(pan)
        controls[key] = control; addSubview(control)
    }
    private var layoutStorageKey: String { "native-game-layout.\(mode).\(bounds.width > bounds.height ? "landscape" : "portrait")" }
    private var safeRect: CGRect { bounds.inset(by: UIEdgeInsets(top: safeAreaInsets.top + 5, left: safeAreaInsets.left + 5, bottom: safeAreaInsets.bottom + 5, right: safeAreaInsets.right + 5)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, bounds.size != lastSize || safeAreaInsets != lastSafe else { return }
        clearPressed(); lastSize = bounds.size; lastSafe = safeAreaInsets
        let r = safeRect, landscape = bounds.width > bounds.height
        let scale: CGFloat = landscape && bounds.height < 430 ? 0.86 : (bounds.width < 400 ? 0.88 : 1)
        for (key, control) in controls {
            let base: CGFloat
            switch key {
            case "stick": base = 126
            case "map": base = 76
            case "score": base = 120
            case "weapon", "health": base = mode == "aim" ? 160 : 90
            case "attack": base = 82
            case "skill3": base = 64
            case "skill1", "skill2": base = 58
            case "fire": base = 76
            case "fire-left": base = 56
            case "scope": base = 47
            case "settings": base = 34
            default: base = key == "recall" || key == "heal" ? 40 : 43
            }
            control.bounds.size = CGSize(width: base * scale, height: control.kind == .bar ? 28 : base * scale)
        }
        func put(_ key: String, _ x: CGFloat, _ y: CGFloat) { controls[key]?.center = CGPoint(x: x, y: y) }
        put("stick", r.minX + 90 * scale, r.maxY - (landscape ? 84 : 110) * scale)
        put("map", r.minX + 42 * scale, r.minY + 43 * scale)
        put("score", r.midX, r.minY + 15)
        put("settings", r.maxX - 90, r.minY + 20)
        if mode == "aim" {
            put("fire-left", r.minX + 114 * scale, r.minY + 100 * scale)
            put("fire", r.maxX - 68 * scale, r.maxY - 136 * scale)
            put("scope", r.maxX - 133 * scale, r.maxY - 199 * scale)
            put("reload", r.maxX - 142 * scale, r.maxY - 70 * scale)
            put("crouch", r.maxX - 119 * scale, r.maxY - 27 * scale)
            put("prone", r.maxX - 71 * scale, r.maxY - 27 * scale)
            put("jump", r.maxX - 23 * scale, r.maxY - 27 * scale)
            put("weapon", landscape ? r.midX : r.minX + 85 * scale, r.maxY - 43)
            put("health", r.midX, r.maxY - 12)
        } else {
            put("attack", r.maxX - 51 * scale, r.maxY - 53 * scale)
            put("skill1", r.maxX - 145 * scale, r.maxY - 51 * scale)
            put("skill2", r.maxX - 116 * scale, r.maxY - 132 * scale)
            put("skill3", r.maxX - 44 * scale, r.maxY - 191 * scale)
            put("flash", landscape ? r.maxX - 207 * scale : r.minX + 30 * scale, r.maxY - (landscape ? 42 : 205) * scale)
            put("recall", landscape ? r.midX - 26 * scale : r.minX + 80 * scale, r.maxY - (landscape ? 22 : 205) * scale)
            put("heal", landscape ? r.midX + 26 * scale : r.minX + 130 * scale, r.maxY - (landscape ? 22 : 205) * scale)
            put("health", r.midX, r.midY - 33)
        }
        let stored = UserDefaults.standard.dictionary(forKey: layoutStorageKey) as? [String: [String: Double]] ?? [:]
        for (key, position) in stored {
            if let x = position["x"], let y = position["y"], let control = controls[key] {
                control.center = clamp(CGPoint(x: CGFloat(x) * bounds.width, y: CGFloat(y) * bounds.height), size: control.bounds.size)
            }
        }
        stickHome = controls["stick"]?.center ?? .zero
        player = CGPoint(x: bounds.midX, y: bounds.midY)
        reticle = player
        settingsPanel?.frame = bounds
        setNeedsDisplay()
    }

    private func clamp(_ point: CGPoint, size: CGSize) -> CGPoint {
        let r = safeRect
        return CGPoint(x: max(r.minX + size.width / 2, min(r.maxX - size.width / 2, point.x)), y: max(r.minY + size.height / 2, min(r.maxY - size.height / 2, point.y)))
    }
    @objc private func moveControl(_ recognizer: UIPanGestureRecognizer) {
        guard editingLayout, let control = recognizer.view else { return }
        let delta = recognizer.translation(in: self)
        control.center = clamp(CGPoint(x: control.center.x + delta.x, y: control.center.y + delta.y), size: control.bounds.size)
        recognizer.setTranslation(.zero, in: self)
        if recognizer.state == .ended || recognizer.state == .cancelled {
            var stored: [String: [String: Double]] = [:]
            for (key, item) in controls { stored[key] = ["x": Double(item.center.x / bounds.width), "y": Double(item.center.y / bounds.height)] }
            UserDefaults.standard.set(stored, forKey: layoutStorageKey)
            stickHome = controls["stick"]?.center ?? stickHome
        }
    }
    func resetLayout() {
        UserDefaults.standard.removeObject(forKey: layoutStorageKey)
        lastSize = .zero; setNeedsLayout(); layoutIfNeeded()
    }
    func stopScene() { clearPressed(); timer?.invalidate(); timer = nil; settingsPanel?.removeFromSuperview(); settingsPanel = nil }
    private func startTimer() {
        guard timer == nil else { return }
        lastTick = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func clearPressed() {
        roles.removeAll(); previous.removeAll(); pressed.removeAll(); castVectors.removeAll(); cancelledCasts.removeAll()
        moveID = nil; lookID = nil; vector = .zero
        controls.values.forEach { $0.pressed = false; $0.stickVector = .zero }
        controls["stick"]?.center = stickHome
        setNeedsDisplay()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !editingLayout, settingsPanel == nil else { return }
        startTimer()
        for touch in touches {
            let id = ObjectIdentifier(touch), p = touch.location(in: self)
            eventCount += 1; previous[id] = p
            // Match the visible stacking order when the user has moved controls.
            let hit = subviews.reversed().compactMap { item -> String? in
                guard let control = item as? NativeHUDControl, control.frame.contains(p) else { return nil }
                return controls.first { $0.value === control && !["stick", "health", "score"].contains($0.key) }?.key
            }.first
            if let key = hit {
                roles[id] = .control(key); pressed[key, default: []].insert(id); controls[key]?.pressed = true
                if key == "fire" || key == "fire-left" { shoot(); lastShot = CACurrentMediaTime() }
                if key.hasPrefix("skill") { castVectors[id] = p }
            } else if p.x < bounds.width * 0.46 && p.y > safeRect.minY + 55 && moveID == nil {
                moveID = id; roles[id] = .move; stickOrigin = p
                controls["stick"]?.center = p; vector = .zero
            } else if mode == "aim", lookID == nil {
                lookID = id; roles[id] = .look
            } else { roles[id] = .ignored }
        }
        setNeedsDisplay()
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            let samples = (event?.coalescedTouches(for: touch) ?? [touch]).sorted { $0.timestamp < $1.timestamp }
            for sample in samples {
                let p = sample.location(in: self), old = previous[id] ?? p
                eventCount += 1
                switch roles[id] {
                case .move?:
                    let radius = (controls["stick"]?.bounds.width ?? 126) * 0.34
                    let dx = p.x - stickOrigin.x, dy = p.y - stickOrigin.y, distance = max(1, hypot(dx, dy))
                    let factor = min(1, radius / distance)
                    vector = CGPoint(x: dx * factor / radius, y: dy * factor / radius)
                    controls["stick"]?.stickVector = vector
                case .look?:
                    reticle.x = max(0, min(bounds.width, reticle.x + (p.x - old.x) * sensitivity))
                    reticle.y = max(0, min(bounds.height, reticle.y + (p.y - old.y) * sensitivity))
                case .control(let key)? where key.hasPrefix("skill"):
                    castVectors[id] = p
                    if cancelRect.contains(p) { cancelledCasts.insert(id) } else { cancelledCasts.remove(id) }
                default: break
                }
                previous[id] = p
            }
        }
        setNeedsDisplay()
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches, cancelled: false) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches, cancelled: true) }
    private func end(_ touches: Set<UITouch>, cancelled: Bool) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            if case .control(let key)? = roles[id] {
                pressed[key]?.remove(id); controls[key]?.pressed = !(pressed[key]?.isEmpty ?? true)
                let inside = controls[key]?.frame.insetBy(dx: -8, dy: -8).contains(touch.location(in: self)) ?? false
                if !cancelled && (key.hasPrefix("skill") || inside) {
                    switch key {
                    case "scope": scoped.toggle(); controls["scope"]?.selected = scoped
                    case "reload": let amount = min(40 - magazine, reserve); magazine += amount; reserve -= amount; showFeedback("换弹完成"); updateAmmo()
                    case "crouch": stance = stance == "蹲下" ? "站立" : "蹲下"; showFeedback(stance)
                    case "prone": stance = stance == "趴下" ? "站立" : "趴下"; showFeedback(stance)
                    case "jump": jumpUntil = CACurrentMediaTime() + 0.4; showFeedback("跳跃")
                    case "settings": showSettings()
                    case "map": showMap()
                    case "skill1", "skill2", "skill3":
                        if cancelledCasts.contains(id) || cancelRect.contains(touch.location(in: self)) { cancelledCount += 1; showFeedback("取消施法") }
                        else { skillCount += 1; showFeedback("\(controls[key]?.title ?? "技能") 施放") }
                    case "attack", "flash", "recall", "heal": skillCount += 1; showFeedback(controls[key]?.title ?? "")
                    default: break
                    }
                }
            }
            if id == moveID { moveID = nil; vector = .zero; controls["stick"]?.stickVector = .zero; controls["stick"]?.center = stickHome }
            if id == lookID { lookID = nil }
            castVectors[id] = nil; cancelledCasts.remove(id); roles[id] = nil; previous[id] = nil
        }
        setNeedsDisplay()
    }
    private func shoot() {
        guard magazine > 0 else { showFeedback("弹匣已空 · 点击换弹"); return }
        magazine -= 1; fireCount += 1; updateAmmo(); showFeedback("开火 \(fireCount)")
    }
    private func updateAmmo() { controls["weapon"]?.title = "M416   \(magazine) / \(reserve)" }
    private func showFeedback(_ text: String) { feedback = text; feedbackUntil = CACurrentMediaTime() + 0.8 }
    private func tick() {
        let now = CACurrentMediaTime(), dt = min(0.05, now - lastTick); lastTick = now
        if mode == "moba", moveID != nil {
            player.x = max(20, min(bounds.width - 20, player.x + vector.x * CGFloat(dt) * 120))
            player.y = max(20, min(bounds.height - 20, player.y + vector.y * CGFloat(dt) * 120))
        }
        if mode == "aim", (!(pressed["fire"]?.isEmpty ?? true) || !(pressed["fire-left"]?.isEmpty ?? true)), now - lastShot >= 0.1 {
            shoot(); lastShot = now
        }
        if moveID != nil || !castVectors.isEmpty || feedbackUntil > now || mode == "aim" { setNeedsDisplay() }
    }
    private var cancelRect: CGRect { CGRect(x: safeRect.maxX - 91, y: safeRect.minY + 55, width: 64, height: 64) }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        if let picture {
            let ratio = max(bounds.width / picture.size.width, bounds.height / picture.size.height)
            let size = CGSize(width: picture.size.width * ratio, height: picture.size.height * ratio)
            picture.draw(in: CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height))
        } else { UIColor(white: 0.14, alpha: 1).setFill(); context.fill(bounds) }
        if mode == "aim" {
            if scoped {
                context.saveGState()
                UIColor.black.withAlphaComponent(0.6).setFill(); context.fill(bounds)
                let diameter = min(bounds.height * 0.72, bounds.width * 0.72)
                let lens = CGRect(x: reticle.x - diameter / 2, y: reticle.y - diameter / 2, width: diameter, height: diameter)
                context.addEllipse(in: lens); context.clip()
                if let picture { picture.draw(in: CGRect(x: -bounds.width * 0.3, y: -bounds.height * 0.3, width: bounds.width * 1.6, height: bounds.height * 1.6)) }
                context.restoreGState()
                context.setStrokeColor(UIColor.black.cgColor); context.setLineWidth(7); context.strokeEllipse(in: lens)
            }
            context.setStrokeColor(UIColor.white.cgColor); context.setLineWidth(1.5)
            for (a, b) in [(CGPoint(x: -18, y: 0), CGPoint(x: -5, y: 0)), (CGPoint(x: 5, y: 0), CGPoint(x: 18, y: 0)), (CGPoint(x: 0, y: -18), CGPoint(x: 0, y: -5)), (CGPoint(x: 0, y: 5), CGPoint(x: 0, y: 18))] {
                context.move(to: CGPoint(x: reticle.x + a.x, y: reticle.y + a.y)); context.addLine(to: CGPoint(x: reticle.x + b.x, y: reticle.y + b.y))
            }
            context.strokePath()
        } else {
            let avatar = CGRect(x: player.x - 14, y: player.y - 14, width: 28, height: 28)
            UIColor.systemCyan.withAlphaComponent(0.65).setFill(); context.fillEllipse(in: avatar)
            context.setStrokeColor(UIColor.white.cgColor); context.setLineWidth(2); context.strokeEllipse(in: avatar)
            for (id, point) in castVectors {
                let origin: CGPoint
                if case .control(let key)? = roles[id] { origin = controls[key]?.center ?? point } else { origin = point }
                let angle = atan2(point.y - origin.y, point.x - origin.x), length: CGFloat = 130
                let end = CGPoint(x: player.x + cos(angle) * length, y: player.y + sin(angle) * length)
                context.setStrokeColor((cancelledCasts.contains(id) ? UIColor.systemRed : UIColor.systemCyan).cgColor); context.setLineWidth(18)
                context.move(to: player); context.addLine(to: end); context.strokePath()
                context.setLineWidth(3); context.strokeEllipse(in: CGRect(x: player.x - 135, y: player.y - 135, width: 270, height: 270))
            }
            if !castVectors.isEmpty {
                UIColor.systemRed.withAlphaComponent(0.5).setFill(); context.fillEllipse(in: cancelRect)
                ("取消" as NSString).draw(in: cancelRect.insetBy(dx: 14, dy: 22), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 15), .foregroundColor: UIColor.white])
            }
        }
        if feedbackUntil > CACurrentMediaTime() {
            let textRect = CGRect(x: safeRect.midX - 130, y: safeRect.minY + 40, width: 260, height: 25)
            let style = NSMutableParagraphStyle(); style.alignment = .center
            (feedback as NSString).draw(in: textRect, withAttributes: [.font: UIFont.boldSystemFont(ofSize: 15), .foregroundColor: UIColor.white, .paragraphStyle: style])
        }
        if editingLayout {
            let style = NSMutableParagraphStyle(); style.alignment = .center
            ("拖动虚线控件调整位置 · 布局自动保存" as NSString).draw(in: CGRect(x: safeRect.minX, y: safeRect.minY + 48, width: safeRect.width, height: 24), withAttributes: [.font: UIFont.systemFont(ofSize: 13), .foregroundColor: UIColor.systemYellow, .paragraphStyle: style])
        }
    }

    private func showSettings() {
        clearPressed(); settingsPanel?.removeFromSuperview()
        let overlay = UIView(frame: bounds); overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]; overlay.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        let sheet = UIView(); sheet.backgroundColor = UIColor(red: 0.10, green: 0.14, blue: 0.20, alpha: 0.98); sheet.layer.cornerRadius = 12; sheet.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(sheet)
        NSLayoutConstraint.activate([sheet.centerXAnchor.constraint(equalTo: overlay.centerXAnchor), sheet.centerYAnchor.constraint(equalTo: overlay.centerYAnchor), sheet.widthAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.widthAnchor, multiplier: 0.8), sheet.heightAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.heightAnchor, multiplier: 0.82)])
        let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false; sheet.addSubview(scroll)
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo: sheet.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: sheet.trailingAnchor), scroll.topAnchor.constraint(equalTo: sheet.topAnchor), scroll.bottomAnchor.constraint(equalTo: sheet.bottomAnchor)])
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 14; stack.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 18), stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -18), stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 15), stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -12), stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -36)])
        let title = UILabel(); title.text = "游戏设置"; title.textColor = .white; title.font = .boldSystemFont(ofSize: 20); stack.addArrangedSubview(title)
        let section = UISegmentedControl(items: ["操作", "布局", "灵敏度"]); section.selectedSegmentIndex = 0; section.selectedSegmentTintColor = .systemYellow; stack.addArrangedSubview(section)
        let description = UILabel(); description.textColor = .white; description.numberOfLines = 0; description.font = .systemFont(ofSize: 13); description.text = "浮动轮盘：左侧落指后出现，移动与技能/瞄准独立响应。"; stack.addArrangedSubview(description)
        let sensitivitySlider = UISlider(); sensitivitySlider.minimumValue = 0.25; sensitivitySlider.maximumValue = 2; sensitivitySlider.value = Float(sensitivity); sensitivitySlider.isHidden = true
        sensitivitySlider.addAction(UIAction { [weak self, weak sensitivitySlider, weak description] _ in guard let slider = sensitivitySlider else { return }; self?.sensitivity = CGFloat(slider.value); description?.text = "瞄准灵敏度 \(Int(slider.value * 100))%" }, for: .valueChanged); stack.addArrangedSubview(sensitivitySlider)
        let edit = UIButton(type: .system); edit.setTitle(editingLayout ? "完成布局编辑" : "移动按钮与菜单", for: .normal); edit.setTitleColor(.systemYellow, for: .normal)
        edit.addAction(UIAction { [weak self, weak overlay] _ in guard let self else { return }; self.editingLayout.toggle(); overlay?.removeFromSuperview(); self.settingsPanel = nil }, for: .touchUpInside); stack.addArrangedSubview(edit)
        let reset = UIButton(type: .system); reset.setTitle("恢复默认键位", for: .normal); reset.addAction(UIAction { [weak self] _ in self?.resetLayout() }, for: .touchUpInside); stack.addArrangedSubview(reset)
        section.addAction(UIAction { [weak section, weak description, weak sensitivitySlider, weak edit, weak reset] _ in
            let index = section?.selectedSegmentIndex ?? 0; sensitivitySlider?.isHidden = index != 2; edit?.isHidden = index != 1; reset?.isHidden = index != 1
            description?.text = index == 0 ? "浮动轮盘：左侧落指后出现，移动与技能/瞄准独立响应。" : index == 1 ? "进入编辑后拖动轮盘、技能、开火、地图和菜单；横竖屏分别保存。" : "拖动滑块调整瞄准位移倍率；100% 保持手指实际位移。"
        }, for: .valueChanged)
        edit.isHidden = true; reset.isHidden = true
        let close = UIButton(type: .system); close.setTitle("返回游戏", for: .normal); close.setTitleColor(.white, for: .normal); close.addAction(UIAction { [weak self, weak overlay] _ in overlay?.removeFromSuperview(); self?.settingsPanel = nil }, for: .touchUpInside); stack.addArrangedSubview(close)
        settingsPanel = overlay; addSubview(overlay)
    }
    private func showMap() {
        clearPressed(); settingsPanel?.removeFromSuperview()
        let map = NativeGameMapPanel(image: picture)
        map.frame = bounds; map.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        map.onClose = { [weak self, weak map] in map?.removeFromSuperview(); self?.settingsPanel = nil }
        settingsPanel = map; addSubview(map)
    }
}

private final class NativeHUDControl: UIView {
    enum Kind { case circle, square, bar, stick }
    var title: String { didSet { setNeedsDisplay() } }
    let symbol: String?
    let kind: Kind
    var pressed = false { didSet { setNeedsDisplay() } }
    var selected = false { didSet { setNeedsDisplay() } }
    var stickVector = CGPoint.zero { didSet { setNeedsDisplay() } }
    var mapImage: UIImage? { didSet { setNeedsDisplay() } }
    init(title: String, symbol: String?, kind: Kind) { self.title = title; self.symbol = symbol; self.kind = kind; super.init(frame: .zero); backgroundColor = .clear; isOpaque = false; isAccessibilityElement = true; accessibilityTraits = .button }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let shape = bounds.insetBy(dx: 2, dy: 2), bright = pressed || selected
        context.setFillColor(UIColor(white: bright ? 0.8 : 0.1, alpha: bright ? 0.55 : 0.24).cgColor)
        context.setStrokeColor(UIColor.white.withAlphaComponent(bright ? 0.95 : 0.55).cgColor); context.setLineWidth(bright ? 3 : 1)
        if kind == .circle || kind == .stick { context.fillEllipse(in: shape); context.strokeEllipse(in: shape) }
        else { let path = UIBezierPath(roundedRect: shape, cornerRadius: kind == .square ? 8 : 3); context.addPath(path.cgPath); context.drawPath(using: .fillStroke) }
        if kind == .square, let mapImage {
            context.saveGState(); context.addPath(UIBezierPath(roundedRect: shape.insetBy(dx: 1, dy: 1), cornerRadius: 7).cgPath); context.clip()
            mapImage.draw(in: shape)
            UIColor.systemCyan.setFill(); context.fillEllipse(in: CGRect(x: bounds.width * 0.33, y: bounds.height * 0.6, width: 6, height: 6))
            UIColor.systemRed.setFill(); context.fillEllipse(in: CGRect(x: bounds.width * 0.67, y: bounds.height * 0.3, width: 6, height: 6))
            context.restoreGState(); return
        }
        if kind == .stick {
            let radius = bounds.width * 0.34, size = bounds.width * 0.42
            let knob = CGRect(x: bounds.midX + stickVector.x * radius - size / 2, y: bounds.midY + stickVector.y * radius - size / 2, width: size, height: size)
            context.setFillColor(UIColor.white.withAlphaComponent(0.35).cgColor); context.fillEllipse(in: knob); context.strokeEllipse(in: knob); return
        }
        let style = NSMutableParagraphStyle(); style.alignment = .center
        if let symbol, let image = UIImage(systemName: symbol)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
            let size = min(bounds.width * 0.45, 31)
            image.draw(in: CGRect(x: bounds.midX - size / 2, y: bounds.midY - size / 2 - 6, width: size, height: size))
            (title as NSString).draw(in: CGRect(x: 1, y: bounds.maxY - 18, width: bounds.width - 2, height: 14), withAttributes: [.font: UIFont.systemFont(ofSize: bounds.width < 50 ? 9 : 10), .foregroundColor: UIColor.white, .paragraphStyle: style])
        } else {
            (title as NSString).draw(in: CGRect(x: 3, y: bounds.midY - 7, width: bounds.width - 6, height: 18), withAttributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium), .foregroundColor: UIColor.white, .paragraphStyle: style])
        }
    }
}

private final class NativeGameMapPanel: UIView, UIScrollViewDelegate {
    var onClose: (() -> Void)?
    private let scroll = UIScrollView()
    private let imageView: UIImageView
    private let close = UIButton(type: .system)
    init(image: UIImage?) {
        imageView = UIImageView(image: image)
        super.init(frame: .zero)
        backgroundColor = UIColor.black.withAlphaComponent(0.93)
        scroll.delegate = self; scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 4; scroll.bouncesZoom = true
        imageView.contentMode = .scaleAspectFill; imageView.clipsToBounds = true
        scroll.addSubview(imageView); addSubview(scroll)
        close.setTitle("返回游戏", for: .normal); close.setTitleColor(.white, for: .normal); close.backgroundColor = UIColor.black.withAlphaComponent(0.65); close.layer.cornerRadius = 8
        close.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside); addSubview(close)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds.inset(by: safeAreaInsets)
        if scroll.zoomScale == 1 { imageView.frame = CGRect(origin: .zero, size: scroll.bounds.size); scroll.contentSize = imageView.bounds.size }
        close.frame = CGRect(x: bounds.width-safeAreaInsets.right-90, y: safeAreaInsets.top+10, width: 80, height: 36)
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
}
