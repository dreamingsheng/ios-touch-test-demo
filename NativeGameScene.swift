import UIKit

// Native UIKit interaction scene. Background art is a local test asset; no HTML,
// web event forwarding, game SDK, or online game account is used here.
final class NativeGameScene: UIView, NativeSceneLifecycle, NativeResettableScene {
    private enum Role { case move, look, camera, control(String), ignored }
    private let mode: String
    private var picture: UIImage?
    private let practicePictures: [UIImage?]
    private var backgroundIndex = 0
    private var backgroundZoom: CGFloat = 1
    private var hudScale: CGFloat = 1
    private var hudPreset = 0
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
    private var maximumTouches = 0
    private var cameraOffset = CGPoint.zero
    private var lockedTarget: Int?
    private var signal = ""
    private var chatMessages = ["系统：进入触控练习场。"]
    private var coins = 3000
    private var equipment: [String] = []
    private var skillLevels = ["skill1": 1, "skill2": 1, "skill3": 1]
    private var activeUntil: CFTimeInterval = 0
    private var beganAt = CACurrentMediaTime()
    private struct Item {
        let id: String; let name: String; let category: Int; let cost: Int; let symbol: String; let detail: String
    }
    private let catalog: [Item] = [
        Item(id:"sword",name:"练习长剑",category:0,cost:250,symbol:"bolt.fill",detail:"攻击 +20 · 测试购买、装备与出售"),
        Item(id:"bow",name:"练习战弓",category:0,cost:420,symbol:"arrow.up.right",detail:"攻速 +15% · 练习装备"),
        Item(id:"staff",name:"练习法杖",category:1,cost:300,symbol:"sparkles",detail:"法术 +40 · 练习装备"),
        Item(id:"orb",name:"练习法球",category:1,cost:500,symbol:"sun.max.fill",detail:"法术 +70 · 练习装备"),
        Item(id:"armor",name:"练习护甲",category:2,cost:280,symbol:"shield.fill",detail:"护甲 +60 · 练习装备"),
        Item(id:"cloak",name:"练习披风",category:2,cost:450,symbol:"shield.lefthalf.filled",detail:"生命 +300 · 练习装备"),
        Item(id:"boots",name:"练习战靴",category:3,cost:260,symbol:"figure.walk",detail:"移速 +30 · 练习装备"),
        Item(id:"dash",name:"练习疾步",category:3,cost:480,symbol:"hare.fill",detail:"移动 +45 · 练习装备")]
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
    // Exposed through diagnostics only in XCTest launches, so a failed gesture
    // records what UIKit actually received without changing recognition rules.
    private var layoutTrace: [String] = []

    var editingLayout = false {
        didSet {
            clearPressed()
            controls.values.forEach {
                $0.isUserInteractionEnabled = editingLayout
                $0.layer.borderColor = (editingLayout ? UIColor.systemYellow : UIColor.clear).cgColor
                $0.layer.borderWidth = editingLayout ? 1 : 0
                $0.gestureRecognizers?.forEach { $0.isEnabled = editingLayout }
            }
            traceLayout("edit=\(editingLayout) enabled=\(controls.values.filter(\.isUserInteractionEnabled).count)")
            setNeedsDisplay()
        }
    }
    var diagnostics: String {
        "触点 \(roles.count) · 最大 \(maximumTouches) · 落指 \(Int(stickOrigin.x)),\(Int(stickOrigin.y)) · 事件 \(eventCount) · 左轴 \(String(format: "%.2f,%.2f", Double(vector.x), Double(vector.y))) · " +
        (mode == "aim" ? "开火 \(fireCount) · 弹药 \(magazine)/\(reserve) · \(stance)" : "施放 \(skillCount) · 取消 \(cancelledCount)") +
        (layoutTrace.isEmpty ? "" : " · HUD " + layoutTrace.suffix(6).joined(separator:" | "))
    }
    private func traceLayout(_ message:String) {
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        layoutTrace.append(message)
        if layoutTrace.count > 12 { layoutTrace.removeFirst(layoutTrace.count-12) }
        accessibilityValue = diagnostics
        print("NativeHUD \(message)")
    }

    init(mode: String, assetFolder: URL?) {
        self.mode = mode
        practicePictures = ["moba-battlefield-v1.png", "shooter-training-v1.png"].map { filename in assetFolder.flatMap { UIImage(contentsOfFile: $0.appendingPathComponent(filename).path) } }
        let preferences = UserDefaults.standard.dictionary(forKey: "native-game-presentation.\(mode)") ?? [:]
        backgroundIndex = max(0, min(1, preferences["background"] as? Int ?? (mode == "aim" ? 1 : 0)))
        backgroundZoom = CGFloat(max(0.55, min(1.25, preferences["zoom"] as? Double ?? 1)))
        hudScale = CGFloat(max(0.65, min(1.1, preferences["controls"] as? Double ?? 1)))
        hudPreset = max(0, min(2, preferences["preset"] as? Int ?? 0))
        picture = practicePictures[backgroundIndex]
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
            add("shop", "金币 3000", symbol: "cart.fill", size: 88, kind: .bar)
            add("chat", "聊天", symbol: "message.fill", size: 35)
            add("signal-attack", "进攻", symbol: "flag.fill", size: 34)
            add("signal-retreat", "撤退", symbol: "arrow.uturn.backward", size: 34)
            add("signal-gather", "集合", symbol: "person.3.fill", size: 34)
            add("last-hit", "补刀", symbol: "scope", size: 40)
            add("tower", "推塔", symbol: "building.2.fill", size: 40)
            add("eye", "视角", symbol: "eye.fill", size: 38)
            add("target1", "目标1", symbol: "person.crop.circle.fill", size: 34)
            add("target2", "目标2", symbol: "person.crop.circle.fill", size: 34)
            add("target3", "目标3", symbol: "person.crop.circle.fill", size: 34)
            add("upgrade1", "+", symbol: nil, size: 25)
            add("upgrade2", "+", symbol: nil, size: 25)
            add("upgrade3", "+", symbol: nil, size: 25)
            for slot in 0..<6 { add("equip\(slot)", "空槽", symbol: nil, size: 32, kind: .square) }
            add("active", "主动", symbol: "wand.and.stars", size: 40)
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
        if key == "health" { control.accessibilityTraits = .staticText }
        control.bounds = CGRect(x: 0, y: 0, width: size, height: kind == .bar ? 28 : size)
        control.isUserInteractionEnabled = false
        let pan = UIPanGestureRecognizer(target: self, action: #selector(moveControl(_:)))
        pan.isEnabled = false; pan.maximumNumberOfTouches = 1
        control.addGestureRecognizer(pan)
        controls[key] = control; addSubview(control)
    }
    private var layoutStorageKey: String { "native-game-layout.\(mode).\(bounds.width > bounds.height ? "landscape" : "portrait").preset\(hudPreset)" }
    private var legacyLayoutStorageKey: String { "native-game-layout.\(mode).\(bounds.width > bounds.height ? "landscape" : "portrait")" }
    private var safeRect: CGRect { bounds.inset(by: UIEdgeInsets(top: safeAreaInsets.top + 5, left: safeAreaInsets.left + 5, bottom: safeAreaInsets.bottom + 5, right: safeAreaInsets.right + 5)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, bounds.size != lastSize || safeAreaInsets != lastSafe else { return }
        traceLayout("layout old=\(lastSize) new=\(bounds.size) oldSafe=\(lastSafe) newSafe=\(safeAreaInsets)")
        clearPressed(); lastSize = bounds.size; lastSafe = safeAreaInsets
        let r = safeRect, landscape = bounds.width > bounds.height
        let scale: CGFloat = (landscape && bounds.height < 430 ? 0.86 : (bounds.width < 400 ? 0.88 : 1)) * hudScale
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
            case "shop": base = 88
            case "chat": base = 35
            case "signal-attack", "signal-retreat", "signal-gather", "target1", "target2", "target3": base = 34
            case "eye": base = 38
            case "last-hit", "tower", "active": base = 40
            case "upgrade1", "upgrade2", "upgrade3": base = 25
            case "equip0", "equip1", "equip2", "equip3", "equip4", "equip5": base = 32
            default: base = key == "recall" || key == "heal" ? 40 : 43
            }
            control.bounds.size = CGSize(width: base * scale, height: control.kind == .bar ? max(18,28 * scale) : base * scale)
        }
        func put(_ key: String, _ x: CGFloat, _ y: CGFloat) { controls[key]?.center = CGPoint(x: x, y: y) }
        put("stick", r.minX + 90 * scale, r.maxY - (landscape ? 84 : 110) * scale)
        put("map", r.minX + 42 * scale, r.minY + 43 * scale)
        put("score", r.midX - (landscape ? 0 : 18), r.minY + 15)
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
            put("skill3", r.maxX - 44 * scale, r.maxY - 170 * scale)
            put("flash", landscape ? r.maxX - 207 * scale : r.minX + 30 * scale, r.maxY - (landscape ? 42 : 205) * scale)
            put("recall", landscape ? r.midX - 26 * scale : r.minX + 80 * scale, r.maxY - (landscape ? 22 : 205) * scale)
            put("heal", landscape ? r.midX + 26 * scale : r.minX + 130 * scale, r.maxY - (landscape ? 22 : 205) * scale)
            put("health", r.midX, r.midY - 33)
            put("shop", r.minX + 44, r.minY + 101 * scale)
            put("chat", r.maxX - 25 * scale, r.minY + 112)
            put("signal-attack", r.maxX - 100 * scale, r.minY + 66)
            put("signal-retreat", r.maxX - 142 * scale, r.minY + 66)
            put("signal-gather", r.maxX - 184 * scale, r.minY + 66)
            put("eye", r.maxX - 235 * scale, r.minY + 65)
            for index in 1...3 { put("target\(index)", r.midX + CGFloat(index - 2) * 43 * scale, r.minY + (landscape ? 80 : 182)) }
            put("last-hit", r.maxX - 112 * scale, r.maxY - 10 * scale)
            put("tower", r.maxX - 10 * scale, r.maxY - 110 * scale)
            for index in 1...3 {
                if let skill = controls["skill\(index)"] { put("upgrade\(index)", skill.center.x - 28 * scale, skill.center.y - 29 * scale) }
            }
            for index in 0..<6 { put("equip\(index)", r.minX + CGFloat(20 + index * 36) * scale, r.minY + 137 * scale) }
            put("active", r.midX + 83 * scale, r.maxY - 25 * scale)
            if hudPreset == 1 {
                // Extended spread moves additional targets toward the upper battlefield.
                for index in 1...3 { put("target\(index)", r.midX + CGFloat(index - 2) * 47 * scale, r.minY + 64 * scale) }
                put("active", r.midX + 85 * scale, r.maxY - 74 * scale)
            }
        }
        if hudPreset == 2 {
            let keep = Set(["map", "score", "settings", "shop", "chat", "signal-attack", "signal-retreat", "signal-gather", "health"])
            for (key, control) in controls where !keep.contains(key) && !key.hasPrefix("equip") { control.center.x = r.minX + r.maxX - control.center.x }
        }
        for control in controls.values { control.center = clamp(control.center, size: control.bounds.size) }
        let savedLayout = UserDefaults.standard.dictionary(forKey: layoutStorageKey) ?? (hudPreset == 0 ? UserDefaults.standard.dictionary(forKey: legacyLayoutStorageKey) : nil)
        let stored = savedLayout as? [String: [String: Double]] ?? [:]
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
        guard editingLayout, let control = recognizer.view else { traceLayout("blocked pan state=\(recognizer.state.rawValue) edit=\(editingLayout)"); return }
        let delta = recognizer.translation(in: self)
        let before = control.center
        control.center = clamp(CGPoint(x: control.center.x + delta.x, y: control.center.y + delta.y), size: control.bounds.size)
        if recognizer.state == .began || recognizer.state == .ended || recognizer.state == .cancelled {
            traceLayout("pan \(control.accessibilityIdentifier ?? "?") state=\(recognizer.state.rawValue) location=\(recognizer.location(in:self)) delta=\(delta) center=\(before)->\(control.center)")
        }
        recognizer.setTranslation(.zero, in: self)
        if recognizer.state == .ended || recognizer.state == .cancelled {
            var stored: [String: [String: Double]] = [:]
            for (key, item) in controls { stored[key] = ["x": Double(item.center.x / bounds.width), "y": Double(item.center.y / bounds.height)] }
            UserDefaults.standard.set(stored, forKey: layoutStorageKey)
            stickHome = controls["stick"]?.center ?? stickHome
        }
    }
    func resetLayout() {
        // An explicit empty preset also overrides an older, migrated layout.
        UserDefaults.standard.set([String:[String:Double]](), forKey: layoutStorageKey)
        lastSize = .zero; setNeedsLayout(); layoutIfNeeded()
    }
    func resetScene() {
        clearPressed(); settingsPanel?.endEditing(true); settingsPanel?.removeFromSuperview(); settingsPanel = nil
        editingLayout = false; eventCount = 0; maximumTouches = 0; fireCount = 0; skillCount = 0; cancelledCount = 0
        magazine = 40; reserve = 180; scoped = false; stance = "站立"; lockedTarget = nil; signal = ""; chatMessages = ["系统：进入触控练习场。"]
        coins = 3000; equipment.removeAll(); activeUntil = 0; stickOrigin = .zero; player = CGPoint(x:bounds.midX,y:bounds.midY); reticle = player
        skillLevels = ["skill1":1,"skill2":1,"skill3":1]; controls.values.forEach { $0.selected = false; $0.badge = nil }
        beganAt = CACurrentMediaTime(); feedback = ""; feedbackUntil = 0; jumpUntil = 0
        updateAmmo(); refreshEquipment(); startTimer(); setNeedsDisplay()
    }
    func stopScene() { clearPressed(); timer?.invalidate(); timer = nil; settingsPanel?.endEditing(true); settingsPanel?.removeFromSuperview(); settingsPanel = nil }
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
        cameraOffset = .zero
        controls.values.forEach { $0.pressed = false; $0.stickVector = .zero }
        controls["stick"]?.center = stickHome
        setNeedsDisplay()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !editingLayout, settingsPanel == nil else {
            if editingLayout, let touch = touches.first { traceLayout("edit-touch \(touch.view?.accessibilityIdentifier ?? "?") point=\(touch.location(in:self))") }
            return
        }
        startTimer()
        for touch in touches {
            let id = ObjectIdentifier(touch), p = touch.location(in: self)
            eventCount += 1; previous[id] = p
            // Match the visible stacking order when the user has moved controls.
            let hit = subviews.reversed().compactMap { item -> String? in
                guard let control = item as? NativeHUDControl, control.frame.contains(p) else { return nil }
                return controls.first { $0.value === control && !["stick", "health"].contains($0.key) }?.key
            }.first
            if let key = hit {
                roles[id] = .control(key); pressed[key, default: []].insert(id); controls[key]?.pressed = true
                if key == "fire" || key == "fire-left" { shoot(); lastShot = CACurrentMediaTime() }
                if key.hasPrefix("skill") { castVectors[id] = p }
                if key == "eye" { roles[id] = .camera }
            } else if (hudPreset == 2 ? p.x > bounds.width * 0.54 : p.x < bounds.width * 0.46) && p.y > safeRect.minY + 55 && moveID == nil {
                moveID = id; roles[id] = .move; stickOrigin = p
                controls["stick"]?.center = p; vector = .zero
            } else if mode == "aim", lookID == nil {
                lookID = id; roles[id] = .look
            } else { roles[id] = .ignored }
            maximumTouches = max(maximumTouches, roles.count)
        }
        accessibilityValue = diagnostics
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
                case .camera?:
                    cameraOffset.x = max(-bounds.width * 0.2, min(bounds.width * 0.2, cameraOffset.x + p.x - old.x))
                    cameraOffset.y = max(-bounds.height * 0.2, min(bounds.height * 0.2, cameraOffset.y + p.y - old.y))
                case .control(let key)? where key.hasPrefix("skill"):
                    castVectors[id] = p
                    if cancelRect.contains(p) { cancelledCasts.insert(id) } else { cancelledCasts.remove(id) }
                default: break
                }
                previous[id] = p
            }
        }
        accessibilityValue = diagnostics
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
                    case "shop": showShop()
                    case "score": showScoreboard()
                    case "chat": showChat()
                    case "signal-attack", "signal-retreat", "signal-gather":
                        signal = controls[key]?.title ?? "信号"; showFeedback("已发送信号：\(signal)"); appendMessage("信号：\(signal)")
                    case "upgrade1", "upgrade2", "upgrade3":
                        let skill = "skill" + String(key.suffix(1))
                        let level = min(6, (skillLevels[skill] ?? 1) + 1); skillLevels[skill] = level
                        controls[skill]?.badge = "Lv\(level)"; controls[key]?.selected = level == 6; showFeedback("技能 \(key.suffix(1)) 升至 \(level) 级")
                    case "last-hit", "tower": skillCount += 1; showFeedback(key == "tower" ? "优先攻击防御塔" : "优先攻击小兵")
                    case "target1", "target2", "target3":
                        let target = Int(key.suffix(1)) ?? 1; lockedTarget = lockedTarget == target ? nil : target
                        for index in 1...3 { controls["target\(index)"]?.selected = lockedTarget == index }; showFeedback(lockedTarget == nil ? "取消目标锁定" : "锁定目标 \(target)")
                    case "active":
                        if equipment.isEmpty { showFeedback("先在商店购买装备") }
                        else if CACurrentMediaTime() < activeUntil { showFeedback("主动装备冷却中") }
                        else { activeUntil = CACurrentMediaTime() + 5; skillCount += 1; showFeedback("主动装备已使用") }
                    case "skill1", "skill2", "skill3":
                        if cancelledCasts.contains(id) || cancelRect.contains(touch.location(in: self)) { cancelledCount += 1; showFeedback("取消施法") }
                        else { skillCount += 1; showFeedback("\(controls[key]?.title ?? "技能") 施放") }
                    case "attack", "flash", "recall", "heal": skillCount += 1; showFeedback(controls[key]?.title ?? "")
                    default:
                        if key.hasPrefix("equip"), let index = Int(key.dropFirst(5)) { showEquipment(slot: index) }
                    }
                }
            }
            if id == moveID { moveID = nil; vector = .zero; controls["stick"]?.stickVector = .zero; controls["stick"]?.center = stickHome }
            if id == lookID { lookID = nil }
            if case .camera? = roles[id] { cameraOffset = .zero; pressed["eye"]?.remove(id); controls["eye"]?.pressed = false }
            castVectors[id] = nil; cancelledCasts.remove(id); roles[id] = nil; previous[id] = nil
        }
        accessibilityValue = diagnostics
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
        if mode == "moba" {
            let seconds = Int(now - beganAt)
            controls["score"]?.title = "练习 0:0 \(String(format:"%02d:%02d", seconds / 60, seconds % 60))"
            controls["active"]?.badge = activeUntil > now ? String(Int(ceil(activeUntil - now))) : nil
        }
        if moveID != nil || !castVectors.isEmpty || feedbackUntil > now || mode == "aim" { setNeedsDisplay() }
    }
    private var cancelRect: CGRect { CGRect(x: safeRect.maxX - 91, y: safeRect.minY + 55, width: 64, height: 64) }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        UIColor(red: mode == "aim" ? 0.30 : 0.10, green: mode == "aim" ? 0.37 : 0.21, blue: mode == "aim" ? 0.28 : 0.17, alpha: 1).setFill(); context.fill(bounds)
        if let picture {
            let ratio = max(bounds.width / picture.size.width, bounds.height / picture.size.height)
            let size = CGSize(width: picture.size.width * ratio, height: picture.size.height * ratio)
            // A low-contrast cover layer always fills the window. Shrinking the
            // foreground reveals that extended scene, never a black letterbox.
            picture.draw(in: CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height), blendMode: .normal, alpha: 0.40)
            let fit = min(bounds.width / picture.size.width, bounds.height / picture.size.height) * backgroundZoom
            let foreground = CGSize(width: picture.size.width * fit, height: picture.size.height * fit)
            picture.draw(in: CGRect(x: bounds.midX - foreground.width / 2 + cameraOffset.x, y: bounds.midY - foreground.height / 2 + cameraOffset.y, width: foreground.width, height: foreground.height))
        }
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
            if let target = lockedTarget {
                let targetPoint = CGPoint(x: bounds.width * (0.52 + CGFloat(target) * 0.08), y: bounds.height * 0.39)
                context.setStrokeColor(UIColor.systemRed.cgColor); context.setLineWidth(2)
                context.strokeEllipse(in: CGRect(x: targetPoint.x-19, y: targetPoint.y-19, width: 38, height: 38))
                context.move(to: player); context.addLine(to: targetPoint); context.strokePath()
            }
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

    private func savePresentation() {
        let preferences: [String:Any] = ["background":backgroundIndex,"zoom":Double(backgroundZoom),"controls":Double(hudScale),"preset":hudPreset]
        UserDefaults.standard.set(preferences, forKey:"native-game-presentation.\(mode)")
    }
    private func refreshEquipment() {
        controls["shop"]?.title = "金币 \(coins)"
        for index in 0..<6 {
            let item = index < equipment.count ? catalog.first(where: { $0.id == equipment[index] }) : nil
            controls["equip\(index)"]?.title = item == nil ? "空槽" : "装备\(index+1)"
            controls["equip\(index)"]?.symbol = item?.symbol
            controls["equip\(index)"]?.accessibilityLabel = item?.name ?? "空装备槽 \(index+1)"
        }
    }
    private func appendMessage(_ text:String) {
        chatMessages.append(String(text.prefix(180)))
        if chatMessages.count > 50 { chatMessages.removeFirst(chatMessages.count-50) }
    }
    private func panel(title: String) -> (UIView, UIStackView) {
        clearPressed(); settingsPanel?.removeFromSuperview()
        let overlay = UIView(frame: bounds); overlay.autoresizingMask = [.flexibleWidth,.flexibleHeight]; overlay.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        overlay.accessibilityIdentifier = "game-panel-\(title)"
        let sheet = UIView(); sheet.translatesAutoresizingMaskIntoConstraints = false; sheet.backgroundColor = UIColor(red:0.08,green:0.12,blue:0.18,alpha:0.98); sheet.layer.cornerRadius = 12; overlay.addSubview(sheet)
        NSLayoutConstraint.activate([sheet.topAnchor.constraint(equalTo:overlay.safeAreaLayoutGuide.topAnchor,constant:44),sheet.bottomAnchor.constraint(equalTo:overlay.keyboardLayoutGuide.topAnchor,constant:-10),sheet.centerXAnchor.constraint(equalTo:overlay.centerXAnchor),sheet.widthAnchor.constraint(equalTo:overlay.safeAreaLayoutGuide.widthAnchor,multiplier:0.9)])
        let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false; scroll.keyboardDismissMode = .interactive; sheet.addSubview(scroll)
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo:sheet.leadingAnchor),scroll.trailingAnchor.constraint(equalTo:sheet.trailingAnchor),scroll.topAnchor.constraint(equalTo:sheet.topAnchor),scroll.bottomAnchor.constraint(equalTo:sheet.bottomAnchor)])
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:scroll.contentLayoutGuide.leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:scroll.contentLayoutGuide.trailingAnchor,constant:-16),stack.topAnchor.constraint(equalTo:scroll.contentLayoutGuide.topAnchor,constant:14),stack.bottomAnchor.constraint(equalTo:scroll.contentLayoutGuide.bottomAnchor,constant:-14),stack.widthAnchor.constraint(equalTo:scroll.frameLayoutGuide.widthAnchor,constant:-32)])
        let header = UIStackView(); header.axis = .horizontal; header.alignment = .center; header.spacing = 14
        let label = UILabel(); label.text = title; label.textColor = .white; label.font = .boldSystemFont(ofSize:19); header.addArrangedSubview(label)
        let close = actionButton("返回游戏") { [weak self, weak overlay] in overlay?.endEditing(true); overlay?.removeFromSuperview(); self?.settingsPanel = nil }; header.addArrangedSubview(close); stack.addArrangedSubview(header)
        settingsPanel = overlay; addSubview(overlay); return (overlay,stack)
    }
    private func actionButton(_ title: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type:.system); button.setTitle(title,for:.normal); button.setTitleColor(.white,for:.normal); button.titleLabel?.font = .systemFont(ofSize:14); button.titleLabel?.numberOfLines = 0
        button.backgroundColor = UIColor.white.withAlphaComponent(0.08); button.layer.cornerRadius = 7; button.layer.borderWidth = 0.5; button.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
        button.contentEdgeInsets = UIEdgeInsets(top:10,left:12,bottom:10,right:12)
        button.addAction(UIAction { _ in action() },for:.touchUpInside); return button
    }
    private func note(_ text: String) -> UILabel {
        let label = UILabel(); label.text = text; label.textColor = UIColor.white.withAlphaComponent(0.8); label.font = .systemFont(ofSize:13); label.numberOfLines = 0; return label
    }
    private func showShop() {
        let (_, stack) = panel(title:"金币商店 · 练习装备")
        let gold = note("金币 \(coins) · 装备 \(equipment.count)/6"); gold.accessibilityIdentifier = "shop-gold"; stack.addArrangedSubview(gold)
        let categories = UISegmentedControl(items:["攻击","法术","防御","移动"]); categories.selectedSegmentIndex = 0; categories.selectedSegmentTintColor = .systemYellow; stack.addArrangedSubview(categories)
        let grid = UIStackView(); grid.axis = .vertical; grid.spacing = 10; stack.addArrangedSubview(grid)
        rebuildShop(grid,category:0,gold:gold)
        categories.addAction(UIAction { [weak self, weak categories, weak grid, weak gold] _ in guard let self, let grid, let gold else { return }; self.rebuildShop(grid,category:categories?.selectedSegmentIndex ?? 0,gold:gold) },for:.valueChanged)
        stack.addArrangedSubview(actionButton("重置练习金币和装备") { [weak self, weak grid, weak gold, weak categories] in guard let self, let grid, let gold else { return }; self.coins = 3000; self.equipment.removeAll(); self.refreshEquipment(); self.rebuildShop(grid,category:categories?.selectedSegmentIndex ?? 0,gold:gold) })
        stack.addArrangedSubview(note("本商店只使用练习金币。购买后点屏幕左侧装备槽可查看、出售；主动装备有独立冷却反馈。"))
    }
    private func rebuildShop(_ grid:UIStackView,category:Int,gold:UILabel) {
        grid.arrangedSubviews.forEach { grid.removeArrangedSubview($0); $0.removeFromSuperview() }
        gold.text = "金币 \(coins) · 装备 \(equipment.count)/6"
        let items = catalog.filter { $0.category == category }
        for start in stride(from:0,to:items.count,by:2) {
            let row = UIStackView(); row.axis = .horizontal; row.distribution = .fillEqually; row.spacing = 10
            for item in items[start..<min(start+2,items.count)] {
                let button = actionButton("\(item.name)  ¥\(item.cost)\n\(item.detail)\n购买") { [weak self, weak grid, weak gold] in
                    guard let self, let grid, let gold else { return }
                    guard self.equipment.count < 6, self.coins >= item.cost else { return }
                    self.coins -= item.cost; self.equipment.append(item.id); self.refreshEquipment(); self.rebuildShop(grid,category:category,gold:gold)
                }
                button.accessibilityIdentifier = "shop-buy-\(item.id)"; button.isEnabled = equipment.count < 6 && coins >= item.cost; button.alpha = button.isEnabled ? 1 : 0.4; row.addArrangedSubview(button)
                button.heightAnchor.constraint(greaterThanOrEqualToConstant:92).isActive = true
            }
            grid.addArrangedSubview(row)
        }
    }
    private func showEquipment(slot:Int) {
        guard slot < equipment.count, let item = catalog.first(where:{ $0.id == equipment[slot] }) else { showShop(); return }
        let (overlay,stack) = panel(title:"装备槽 \(slot+1) · \(item.name)")
        stack.addArrangedSubview(note("\(item.detail)\n练习价格 \(item.cost)，出售返还 \(item.cost * 3 / 5) 金币。"))
        stack.addArrangedSubview(actionButton("出售装备") { [weak self, weak overlay] in guard let self,slot < self.equipment.count else { return }; self.coins += item.cost * 3 / 5; self.equipment.remove(at:slot); self.refreshEquipment(); overlay?.removeFromSuperview(); self.settingsPanel = nil; self.showFeedback("已出售 \(item.name)") })
        stack.addArrangedSubview(actionButton("使用主动装备") { [weak self, weak overlay] in guard let self else { return }; if CACurrentMediaTime() >= self.activeUntil { self.activeUntil = CACurrentMediaTime()+5; self.skillCount += 1; self.showFeedback("主动装备已使用") }; overlay?.removeFromSuperview(); self.settingsPanel = nil })
    }
    private func showScoreboard() {
        let (_,stack) = panel(title:"比分与战绩")
        let tabs = UISegmentedControl(items:["战绩","属性","经济"]); tabs.selectedSegmentIndex = 0; tabs.selectedSegmentTintColor = .systemYellow; stack.addArrangedSubview(tabs)
        let detail = note("练习对局 0 : 0 · 技能施放 \(skillCount) · 信号 \(signal.isEmpty ? "未发送" : signal)"); stack.addArrangedSubview(detail)
        let rows = UIStackView(); rows.axis = .vertical; rows.spacing = 6; stack.addArrangedSubview(rows)
        func populate(_ index:Int) {
            rows.arrangedSubviews.forEach { rows.removeArrangedSubview($0); $0.removeFromSuperview() }
            for team in 0..<2 { for playerIndex in 1...5 {
                let suffix = index == 0 ? "0 / 0 / 0" : index == 1 ? "等级 1 · 生命 100%" : "金币 \(team == 0 && playerIndex == 1 ? coins : 3000)"
                let row = actionButton("\(team == 0 ? "蓝方" : "红方") 练习英雄 \(playerIndex)     \(suffix)") { [weak self, weak detail] in guard let self else { return }; self.lockedTarget = (playerIndex-1)%3+1; detail?.text = "已选中\(team == 0 ? "蓝方" : "红方")英雄 \(playerIndex)，目标头像 \(self.lockedTarget ?? 1) 已锁定。" }
                row.backgroundColor = (team == 0 ? UIColor.systemBlue : UIColor.systemRed).withAlphaComponent(0.18); rows.addArrangedSubview(row)
            } }
        }
        populate(0)
        tabs.addAction(UIAction { [weak self, weak tabs, weak rows, weak detail] _ in
            guard let self,let rows,let detail else { return }
            rows.arrangedSubviews.forEach { rows.removeArrangedSubview($0); $0.removeFromSuperview() }
            let index = tabs?.selectedSegmentIndex ?? 0
            for team in 0..<2 { for playerIndex in 1...5 {
                let suffix = index == 0 ? "0 / 0 / 0" : index == 1 ? "等级 1 · 生命 100%" : "金币 \(team == 0 && playerIndex == 1 ? self.coins : 3000)"
                rows.addArrangedSubview(self.actionButton("\(team == 0 ? "蓝方" : "红方") 练习英雄 \(playerIndex)     \(suffix)") { [weak self, weak detail] in self?.lockedTarget = (playerIndex-1)%3+1; detail?.text = "选择英雄 \(playerIndex)，已锁定对应练习目标。" })
            } }
        },for:.valueChanged)
    }
    private func showChat() {
        let (_,stack) = panel(title:"队伍聊天与信号")
        let log = note(chatMessages.joined(separator:"\n")); log.accessibilityIdentifier = "game-chat-log"; stack.addArrangedSubview(log)
        let row = UIStackView(); row.axis = .horizontal; row.spacing = 10
        let field = UITextField(); field.borderStyle = .roundedRect; field.placeholder = "输入练习消息…"; field.backgroundColor = .white; field.textColor = .black; field.font = .systemFont(ofSize:16); field.accessibilityIdentifier = "game-chat-input"; row.addArrangedSubview(field)
        let send = actionButton("发送") { [weak self, weak field, weak log] in guard let self,let field,let log else { return }; let text = (field.text ?? "").trimmingCharacters(in:.whitespacesAndNewlines); guard !text.isEmpty else { return }; self.appendMessage("我："+String(text.prefix(160))); log.text = self.chatMessages.joined(separator:"\n"); field.text = ""; field.resignFirstResponder() }; send.accessibilityIdentifier = "game-chat-send"; row.addArrangedSubview(send); stack.addArrangedSubview(row)
        for text in ["进攻","撤退","集合","技能准备就绪","请求支援"] {
            stack.addArrangedSubview(actionButton("发送信号："+text) { [weak self, weak log] in guard let self else { return }; self.signal = text; self.appendMessage("信号："+text); log?.text = self.chatMessages.joined(separator:"\n"); self.showFeedback("已发送："+text) })
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
        let section = UISegmentedControl(items: ["操作", "布局", "灵敏度", "画面"]); section.selectedSegmentIndex = 0; section.selectedSegmentTintColor = .systemYellow; stack.addArrangedSubview(section)
        let description = UILabel(); description.textColor = .white; description.numberOfLines = 0; description.font = .systemFont(ofSize: 13); description.text = "浮动轮盘：左侧落指后出现，移动与技能/瞄准独立响应。"; stack.addArrangedSubview(description)
        let sensitivitySlider = UISlider(); sensitivitySlider.minimumValue = 0.25; sensitivitySlider.maximumValue = 2; sensitivitySlider.value = Float(sensitivity); sensitivitySlider.isHidden = true
        sensitivitySlider.addAction(UIAction { [weak self, weak sensitivitySlider, weak description] _ in guard let slider = sensitivitySlider else { return }; self?.sensitivity = CGFloat(slider.value); description?.text = "瞄准灵敏度 \(Int(slider.value * 100))%" }, for: .valueChanged); stack.addArrangedSubview(sensitivitySlider)
        let edit = UIButton(type: .system); edit.setTitle(editingLayout ? "完成布局编辑" : "移动按钮与菜单", for: .normal); edit.setTitleColor(.systemYellow, for: .normal)
        edit.addAction(UIAction { [weak self, weak overlay] _ in guard let self else { return }; self.editingLayout.toggle(); overlay?.removeFromSuperview(); self.settingsPanel = nil }, for: .touchUpInside); stack.addArrangedSubview(edit)
        let reset = UIButton(type: .system); reset.setTitle("恢复默认键位", for: .normal); reset.addAction(UIAction { [weak self] _ in self?.resetLayout() }, for: .touchUpInside); stack.addArrangedSubview(reset)
        let layoutOptions = UIStackView(); layoutOptions.axis = .vertical; layoutOptions.spacing = 10; layoutOptions.isHidden = true; stack.addArrangedSubview(layoutOptions)
        layoutOptions.addArrangedSubview(note("键位预设：每套布局和横竖屏分别保存。"))
        let presets = UISegmentedControl(items:["标准","扩展","左手"]); presets.selectedSegmentIndex = hudPreset; presets.selectedSegmentTintColor = .systemYellow; presets.accessibilityIdentifier = "game-hud-preset"; layoutOptions.addArrangedSubview(presets)
        presets.addAction(UIAction { [weak self, weak presets] _ in guard let self else { return }; self.hudPreset = presets?.selectedSegmentIndex ?? 0; self.savePresentation(); self.lastSize = .zero; self.setNeedsLayout(); self.layoutIfNeeded() },for:.valueChanged)
        let sizeLabel = note("控件大小 \(Int(hudScale * 100))%"); layoutOptions.addArrangedSubview(sizeLabel)
        let controlSize = UISlider(); controlSize.minimumValue = 0.65; controlSize.maximumValue = 1.1; controlSize.value = Float(hudScale); controlSize.accessibilityIdentifier = "game-hud-scale"; layoutOptions.addArrangedSubview(controlSize)
        controlSize.addAction(UIAction { [weak self, weak controlSize, weak sizeLabel] _ in guard let self,let slider = controlSize else { return }; self.hudScale = CGFloat(slider.value); sizeLabel?.text = "控件大小 \(Int(slider.value*100))%"; self.savePresentation(); self.lastSize = .zero; self.setNeedsLayout(); self.layoutIfNeeded() },for:.valueChanged)
        let sceneOptions = UIStackView(); sceneOptions.axis = .vertical; sceneOptions.spacing = 10; sceneOptions.isHidden = true; stack.addArrangedSubview(sceneOptions)
        sceneOptions.addArrangedSubview(note("背景均为本地练习场景素材；不代表真实游戏地图。"))
        let background = UISegmentedControl(items:["峡谷练习","训练练习"]); background.selectedSegmentIndex = backgroundIndex; background.selectedSegmentTintColor = .systemYellow; background.accessibilityIdentifier = "game-background-picker"; sceneOptions.addArrangedSubview(background)
        background.addAction(UIAction { [weak self, weak background] _ in guard let self else { return }; self.backgroundIndex = background?.selectedSegmentIndex ?? 0; self.picture = self.practicePictures[self.backgroundIndex]; self.controls["map"]?.mapImage = self.picture; self.savePresentation(); self.setNeedsDisplay() },for:.valueChanged)
        let zoomLabel = note("背景缩放 \(Int(backgroundZoom*100))%"); sceneOptions.addArrangedSubview(zoomLabel)
        let zoom = UISlider(); zoom.minimumValue = 0.55; zoom.maximumValue = 1.25; zoom.value = Float(backgroundZoom); zoom.accessibilityIdentifier = "game-background-zoom"; sceneOptions.addArrangedSubview(zoom)
        zoom.addAction(UIAction { [weak self, weak zoom, weak zoomLabel] _ in guard let self,let slider = zoom else { return }; self.backgroundZoom = CGFloat(slider.value); zoomLabel?.text = "背景缩放 \(Int(slider.value*100))%"; self.savePresentation(); self.setNeedsDisplay() },for:.valueChanged)
        section.addAction(UIAction { [weak section, weak description, weak sensitivitySlider, weak edit, weak reset, weak layoutOptions, weak sceneOptions] _ in
            let index = section?.selectedSegmentIndex ?? 0; sensitivitySlider?.isHidden = index != 2; edit?.isHidden = index != 1; reset?.isHidden = index != 1
            layoutOptions?.isHidden = index != 1; sceneOptions?.isHidden = index != 3
            description?.text = index == 0 ? "浮动轮盘：落指后出现，移动与技能/瞄准独立响应。" : index == 1 ? "拖动全部 HUD 调整位置。控件大小同时改变可见区域和实际命中区域。" : index == 2 ? "拖动滑块调整瞄准位移倍率；100% 保持手指实际位移。" : "缩小背景会露出同色延展场景，画面始终覆盖整个窗口。"
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
    var title: String { didSet { if oldValue != title { accessibilityLabel = title; setNeedsDisplay() } } }
    var symbol: String? { didSet { if oldValue != symbol { setNeedsDisplay() } } }
    var badge: String? { didSet { if oldValue != badge { setNeedsDisplay() } } }
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
        if let badge {
            let badgeRect = CGRect(x:bounds.maxX-28,y:0,width:28,height:14)
            UIColor.black.withAlphaComponent(0.7).setFill(); context.fill(badgeRect)
            (badge as NSString).draw(in:badgeRect,withAttributes:[.font:UIFont.boldSystemFont(ofSize:9),.foregroundColor:UIColor.systemYellow,.paragraphStyle:style])
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
