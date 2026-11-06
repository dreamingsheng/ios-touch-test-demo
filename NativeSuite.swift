import UIKit
import SwiftUI

protocol NativeResettableScene: AnyObject { func resetScene() }

struct NativeSuiteView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> NativeSuiteController { NativeSuiteController() }
    func updateUIViewController(_ controller: NativeSuiteController, context: Context) {}
    static func dismantleUIViewController(_ controller: NativeSuiteController, coordinator: ()) { controller.stop() }
}

final class NativeSuiteController: UIViewController, UIGestureRecognizerDelegate {
    static let modes: [(String, String)] = [
        ("multi","多点轨迹"),("draw","自由画画"),("line","引导划线"),("ghost","鬼点监测"),
        ("auto","移动靶点跟随"),("grid","触控覆盖网格"),("edge","四边与四角"),
        ("pinch","图片拖拽缩放"),("map","地图手势"),("read","阅读翻页"),("video","短视频"),
        ("moba","MOBA 轮盘"),("aim","射击瞄准"),("ui","常用控件"),("menu","多级设置"),
        ("type","键盘输入"),("cross","十字轴与光标"),("tap","点击精度"),("hold","长按漂移"),
        ("colors","纯色切换"),("bars","标准色条")]
    private var mode = "multi"
    private var scene: UIView?
    private let menuButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private let metrics = UILabel()
    private var clock: Timer?
    private var smokeSequence = ""
    private var smokeLandscape: Bool?
    private var stableSize: CGSize = .zero
    private var stableObservations = 0
    private var previousBounds: CGSize = .zero
    private var restoreControls: UILongPressGestureRecognizer!
    private var metricsWereVisible=false
    private var menuTouchStart:CGPoint?
    private var menuDragCenter:CGPoint?
    private var assetFolder: URL? { Bundle.main.url(forResource: "Media", withExtension: nil) }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        menuButton.setTitle("项目 ▾", for: .normal)
        menuButton.setTitleColor(.white, for: .normal)
        menuButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        menuButton.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        menuButton.layer.cornerRadius = 16
        menuButton.layer.borderWidth = 0.5
        menuButton.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.accessibilityIdentifier = "native-project-menu"
        menuButton.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(moveMenu(_:))))
        menuButton.addTarget(self,action:#selector(beginMenuDrag(_:event:)),for:.touchDown)
        clearButton.setTitle("清除",for:.normal)
        clearButton.setTitleColor(.white,for:.normal)
        clearButton.titleLabel?.font = .systemFont(ofSize:12,weight:.medium)
        clearButton.backgroundColor=UIColor.black.withAlphaComponent(0.3)
        clearButton.layer.cornerRadius=16
        clearButton.layer.borderWidth=0.5
        clearButton.layer.borderColor=UIColor.white.withAlphaComponent(0.5).cgColor
        clearButton.accessibilityIdentifier="native-clear"
        clearButton.addTarget(self,action:#selector(clearCurrentTest),for:.touchUpInside)
        restoreControls=UILongPressGestureRecognizer(target:self,action:#selector(restoreFloatingControls(_:)))
        restoreControls.numberOfTouchesRequired=2;restoreControls.minimumPressDuration=1.1
        restoreControls.cancelsTouchesInView=false;restoreControls.isEnabled=false;restoreControls.delegate=self
        view.addGestureRecognizer(restoreControls)
        metrics.numberOfLines = 3
        metrics.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        metrics.textColor = .white
        metrics.isHidden = true
        metrics.isUserInteractionEnabled = false
        metrics.accessibilityIdentifier = "native-metrics"
        let arguments=ProcessInfo.processInfo.arguments
        metrics.isHidden = !arguments.contains("--ui-testing")
        let startIndex=arguments.firstIndex(of:"--native-mode")
        let requested=startIndex.flatMap{ $0+1<arguments.count ? arguments[$0+1] : nil } ?? "multi"
        let initial=Self.modes.contains(where:{$0.0==requested}) ? requested : "multi"
        showMode(initial, automaticOrientation: false)
        clock = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            if let surface = self.scene as? NativeDiagnosticSurface { self.metrics.text = surface.diagnostics }
            if let game = self.scene as? NativeGameScene { self.metrics.text = game.diagnostics }
            if ProcessInfo.processInfo.arguments.contains("--smoke-evidence") { self.pollSmoke() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resumed), name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scene?.frame = view.bounds
        let safe = view.safeAreaInsets
        if previousBounds != view.bounds.size {
            previousBounds = view.bounds.size
            let key = "native-menu-" + (view.bounds.width > view.bounds.height ? "landscape" : "portrait")
            let saved = UserDefaults.standard.array(forKey: key) as? [Double]
            let center = saved?.count == 2 ? CGPoint(x: saved![0] * view.bounds.width, y: saved![1] * view.bounds.height) : CGPoint(x: view.bounds.width-safe.right-40, y: safe.top+26)
            menuButton.frame = CGRect(x: center.x-32,y: center.y-16,width:64,height:32)
        }
        clampMenu()
        metrics.frame = CGRect(x: safe.left+10,y: safe.top+10,width:max(0,view.bounds.width-safe.left-safe.right-95),height:52)
        view.bringSubviewToFront(metrics); view.bringSubviewToFront(menuButton);view.bringSubviewToFront(clearButton)
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setNeedsStatusBarAppearanceUpdate(); setNeedsUpdateOfHomeIndicatorAutoHidden()
        if ["moba","aim"].contains(mode) {requestOrientation(true)}
    }
    private func showMode(_ next: String, automaticOrientation: Bool = true) {
        guard Self.modes.contains(where: { $0.0 == next }) else { return }
        (scene as? NativeSceneLifecycle)?.stopScene()
        scene?.removeFromSuperview(); mode = next
        if ["moba","aim"].contains(next) {
            scene = NativeGameScene(mode: next, assetFolder: assetFolder)
        } else if let everyday = NativeEverydayScenes.make(mode: next, frame: view.bounds, assetFolder: assetFolder) {
            scene = everyday
        } else { scene = NativeDiagnosticSurface(mode: next) }
        scene!.frame = view.bounds
        scene!.autoresizingMask = [.flexibleWidth,.flexibleHeight]
        view.addSubview(scene!)
        view.addSubview(metrics); view.addSubview(menuButton);view.addSubview(clearButton)
        refreshMenu(); view.setNeedsLayout()
        if automaticOrientation && ["moba","aim"].contains(next) { requestOrientation(true) }
    }
    private func requestOrientation(_ landscape: Bool) {
        setNeedsUpdateOfSupportedInterfaceOrientations()
        view.window?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: landscape ? .landscapeRight : .portrait))
    }
    private func refreshMenu() {
        let groups = [Array(Self.modes[0...6]),Array(Self.modes[7...12]),Array(Self.modes[13...20])]
        var children: [UIMenuElement] = groups.map { group in
            UIMenu(options: .displayInline, children: group.map { item in
                UIAction(title: item.1, state: item.0 == mode ? .on : .off) { [weak self] _ in self?.showMode(item.0) }
            })
        }
        var tools: [UIMenuElement] = [
            UIAction(title: "重置本项", image: UIImage(systemName:"arrow.counterclockwise")) { [weak self] _ in self?.clearCurrentTest() },
            UIAction(title: metrics.isHidden ? "显示实时数据" : "隐藏实时数据") { [weak self] _ in guard let self else { return }; self.metrics.isHidden.toggle(); self.refreshMenu() },
            UIAction(title: "隐藏悬浮工具（双指长按恢复）") { [weak self] _ in guard let self else{return};self.metricsWereVisible = !self.metrics.isHidden;self.menuButton.isHidden=true;self.clearButton.isHidden=true;self.metrics.isHidden=true;self.restoreControls.isEnabled=true },
            UIAction(title: "导出原生采样 JSON") { [weak self] _ in self?.exportSamples() },
            UIAction(title: "导出原生采样 CSV") { [weak self] _ in self?.exportSamples(format:"csv") }
        ]
        if let game = scene as? NativeGameScene {
            tools.append(UIAction(title: game.editingLayout ? "完成控件移动" : "移动游戏按钮与菜单") { [weak self, weak game] _ in game?.editingLayout.toggle(); self?.refreshMenu() })
            tools.append(UIAction(title: "恢复默认键位") { [weak game] _ in game?.resetLayout() })
        }
        children.append(UIMenu(options:.displayInline,children:tools))
        menuButton.menu = UIMenu(title: "Touch Test · 原生测试", children: children)
    }
    @objc private func moveMenu(_ pan: UIPanGestureRecognizer) {
        if menuTouchStart==nil {let p=pan.location(in:view),d=pan.translation(in:view);menuTouchStart=CGPoint(x:p.x-d.x,y:p.y-d.y);menuDragCenter=menuButton.center}
        guard let start=menuTouchStart,let original=menuDragCenter else{return}
        let point=pan.location(in:view)
        menuButton.center = CGPoint(x:original.x+point.x-start.x,y:original.y+point.y-start.y)
        clampMenu()
        if pan.state == .ended {
            let key = "native-menu-" + (view.bounds.width > view.bounds.height ? "landscape" : "portrait")
            UserDefaults.standard.set([Double(menuButton.center.x/view.bounds.width),Double(menuButton.center.y/view.bounds.height)],forKey:key)
        }
        if pan.state == .ended || pan.state == .cancelled || pan.state == .failed {menuTouchStart=nil;menuDragCenter=nil}
    }
    @objc private func beginMenuDrag(_ sender:UIButton,event:UIEvent) {
        guard let touch=event.touches(for:sender)?.first else{return}
        menuTouchStart=touch.location(in:view);menuDragCenter=sender.center
    }
    @objc private func restoreFloatingControls(_ gesture:UILongPressGestureRecognizer) {
        guard gesture.state == .began else{return}
        menuButton.isHidden=false;clearButton.isHidden=false;metrics.isHidden = !metricsWereVisible
        gesture.isEnabled=false
    }
    func gestureRecognizer(_ gestureRecognizer:UIGestureRecognizer,shouldRecognizeSimultaneouslyWith otherGestureRecognizer:UIGestureRecognizer)->Bool {gestureRecognizer === restoreControls || otherGestureRecognizer === restoreControls}
    private func clampMenu() {
        let inset = view.safeAreaInsets
        menuButton.center.x = min(max(inset.left+36,menuButton.center.x),view.bounds.width-inset.right-36)
        menuButton.center.y = min(max(inset.top+20,menuButton.center.y),view.bounds.height-inset.bottom-20)
        let below=menuButton.frame.maxY+6
        let y=below+32<=view.bounds.height-inset.bottom ? below : menuButton.frame.minY-38
        clearButton.frame=CGRect(x:menuButton.frame.minX,y:y,width:64,height:32)
    }
    @objc private func clearCurrentTest() {
        if let resettable=scene as? NativeResettableScene {resettable.resetScene()}
        else {showMode(mode,automaticOrientation:false)}
    }
    private func exportSamples(format:String="json") {
        guard let surface = scene as? NativeDiagnosticSurface else {
            let alert = UIAlertController(title:"原生采样报告",message:"请在多点、画画、网格或其他诊断测试中采集触控后导出。",preferredStyle:.alert)
            alert.addAction(UIAlertAction(title:"继续",style:.default)); present(alert,animated:true); return
        }
        do {
            let report=surface.report()
            let data:Data
            if format=="csv" {
                let keys=["mode","phase","id","timestamp","x","y","force","maximumPossibleForce","majorRadius","source","coalescedBatch","stageWidth","stageHeight"]
                let rows=report["samples"] as? [[String:Any]] ?? []
                let csv=keys.joined(separator:",")+"\r\n"+rows.map{ row in keys.map{ key in "\""+String(describing:row[key] ?? "").replacingOccurrences(of:"\"",with:"\"\"")+"\"" }.joined(separator:",") }.joined(separator:"\r\n")
                data=Data(csv.utf8)
            } else {data=try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])}
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("TouchTest-native-\(Int(Date().timeIntervalSince1970)).\(format)")
            try data.write(to:url,options:.atomic)
            let share = UIActivityViewController(activityItems:[url],applicationActivities:nil)
            share.popoverPresentationController?.sourceView = menuButton
            share.popoverPresentationController?.sourceRect = menuButton.bounds
            present(share,animated:true)
        } catch { metrics.text = "导出失败：\(error.localizedDescription)"; metrics.isHidden = false }
    }
    @objc private func interrupted() { (scene as? NativeDiagnosticSurface)?.interrupt(); (scene as? NativeGameScene)?.stopScene(); (scene as? NativeSceneLifecycle)?.pauseScene() }
    @objc private func resumed() { (scene as? NativeSceneLifecycle)?.resumeScene() }
    func stop() { clock?.invalidate(); clock=nil; (scene as? NativeSceneLifecycle)?.stopScene(); NotificationCenter.default.removeObserver(self) }
    deinit { clock?.invalidate(); NotificationCenter.default.removeObserver(self) }

    // Simulator-only command transport. No web renderer or JavaScript is involved.
    private func pollSmoke() {
        guard let folder = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask).first else { return }
        if let data = try? Data(contentsOf:folder.appendingPathComponent("smoke-command.json")),
           let command = try? JSONSerialization.jsonObject(with:data) as? [String:String],
           let sequence = command["sequence"], sequence != smokeSequence, let next = command["mode"] {
            smokeSequence=sequence; stableObservations=0
            smokeLandscape = command["orientation"] == "landscape" || command["orientation"] == "automatic"
            showMode(next,automaticOrientation:command["orientation"] == "automatic")
            if command["orientation"] != "automatic" { requestOrientation(smokeLandscape!) }
        }
        view.layoutIfNeeded()
        if stableSize == view.bounds.size { stableObservations += 1 } else { stableObservations=0;stableSize=view.bounds.size }
        let landscape = view.window?.windowScene?.interfaceOrientation.isLandscape ?? false
        guard let window=view.window else{return}
        let size=window.bounds.size, inset=window.safeAreaInsets
        let appFrame=view.convert(view.bounds,to:window)
        let sceneFrame=scene?.convert(scene!.bounds,to:window) ?? .zero
        func rect(_ r:CGRect)->[String:CGFloat] { ["left":r.minX,"top":r.minY,"right":r.maxX,"bottom":r.maxY,"width":r.width,"height":r.height] }
        let zero:[String:CGFloat] = ["left":0,"top":0,"right":0,"bottom":0,"width":0,"height":0]
        let full:[String:CGFloat] = ["left":0,"top":0,"right":size.width,"bottom":size.height,"width":size.width,"height":size.height]
        let menu=menuButton.convert(menuButton.bounds,to:window)
        let clear=clearButton.convert(clearButton.bounds,to:window)
        let version=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "unknown"
        let data:[String:Any] = ["implementation":"UIKit","title":"Touch Test \(version) native","version":version,"modeCount":Self.modes.count,"activeMode":mode,"requestSequence":smokeSequence.isEmpty ? "initial" : smokeSequence,
            "layoutStable":stableObservations>=3 && (smokeLandscape == nil || landscape == smokeLandscape) && scene?.bounds.size == view.bounds.size,
            "viewport":["width":size.width,"height":size.height],"viewWidth":view.bounds.width,"viewHeight":view.bounds.height,
            "orientation":view.window?.windowScene?.interfaceOrientation.rawValue ?? 0,"stage":rect(sceneFrame),"app":rect(appFrame),"body":full,"header":zero,"nav":zero,
            "safeInsets":["top":inset.top,"left":inset.left,"bottom":inset.bottom,"right":inset.right],
            "menu":["left":menu.minX,"right":menu.maxX,"top":menu.minY,"bottom":menu.maxY],
            "clear":["left":clear.minX,"right":clear.maxX,"top":clear.minY,"bottom":clear.maxY],
            "statusBarHidden":view.window?.windowScene?.statusBarManager?.isStatusBarHidden ?? false]
        if let encoded=try? JSONSerialization.data(withJSONObject:data,options:.prettyPrinted) { try? encoded.write(to:folder.appendingPathComponent("layout-evidence.json"),options:.atomic) }
    }
}

final class NativeDiagnosticSurface: UIView, NativeSceneLifecycle {
    private let mode: String
    private var timer: Timer?
    private var identities:[ObjectIdentifier:Int]=[:]
    private var nextID=1
    private var active:[Int:CGPoint]=[:]
    private var radii:[Int:CGFloat]=[:]
    private var livePaths:[Int:UIBezierPath]=[:]
    private var livePointCount=0
    private var trailImage:UIImage?
    private var canvasSize=CGSize.zero
    private var axisTouch:Int?,cursorTouch:Int?
    private var cursorPoint=CGPoint.zero
    private var sampleRows:[[String:Any]]=[]
    private var total=0, maximum=0, ghost=0, taps=0, hits=0
    private var covered=Set<Int>(),edges=Set<Int>(),lineCovered=Set<Int>()
    private var started=ProcessInfo.processInfo.systemUptime
    private var ghostValid=true
    private var ghostFinished=false
    private var holdID:Int?,holdStart=0.0,holdOrigin=CGPoint.zero,holdDrift:CGFloat=0
    private var target=CGPoint.zero
    private var solid=0
    private var follows=0, errorSum:CGFloat=0
    private var eventCount=0,rate=0,lastRate=ProcessInfo.processInfo.systemUptime
    private let colors:[UIColor]=[.systemCyan,.systemYellow,.systemGreen,.systemOrange,.systemPink,.systemPurple,.systemBlue,.systemRed]
    init(mode:String) {
        self.mode=mode;super.init(frame:.zero)
        backgroundColor = .black; isOpaque=true; isMultipleTouchEnabled=true
        if mode=="colors" { solid=1 }
        accessibilityIdentifier="native-scene-"+mode
        isAccessibilityElement=true
        accessibilityLabel=NativeSuiteController.modes.first(where:{$0.0==mode})?.1 ?? mode
        accessibilityTraits = .allowsDirectInteraction
        let timer=Timer(timeInterval:mode=="auto" ? 1.0/60 : 0.1,repeats:true) { [weak self] _ in self?.tick() }
        self.timer=timer;RunLoop.main.add(timer,forMode:.common)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() { super.layoutSubviews();if canvasSize != bounds.size {canvasSize=bounds.size;trailImage=nil;livePaths.removeAll();livePointCount=0}; if target == .zero || !bounds.contains(target) { target=CGPoint(x:bounds.midX,y:bounds.midY) };if cursorPoint == .zero {cursorPoint=CGPoint(x:bounds.width*0.75,y:bounds.midY)}; setNeedsDisplay() }
    var diagnostics:String {
        let elapsed=ProcessInfo.processInfo.systemUptime-started
        switch mode {
        case "ghost": return ghostValid ? "鬼点 \(ghost) · 剩余 \(max(0,20-Int(elapsed))) 秒\n仅记录实际触控，未输入不能证明硬件合格" : "测试中断，结果无效；请重置"
        case "grid": return "覆盖 \(covered.count)/288 · \(rate) 采样/秒"
        case "edge": return "四边 \(edges.count)/80 · \(rate) 采样/秒"
        case "line": return "引导覆盖 \(lineCovered.count)/150 · \(rate) 采样/秒"
        case "hold": return "长按 \(String(format:"%.1f",holdID == nil ? holdStart : ProcessInfo.processInfo.systemUptime-holdStart))s · 最大漂移 \(String(format:"%.1f",Double(holdDrift)))pt"
        case "tap": return "点击 \(taps) · 命中 \(hits)"
        case "auto": return "跟随 \(follows) 帧 · 平均误差 \(follows == 0 ? "—" : String(format:"%.1f",Double(errorSum/CGFloat(follows))))pt"
        default:return "触点 \(active.count) · 最大 \(maximum) · \(rate) 采样/秒\n保留 \(sampleRows.count)/\(total) 条 UITouch 采样"
        }
    }
    private func tick() {
        let now=ProcessInfo.processInfo.systemUptime
        if mode=="ghost" && now-started>=20 && !ghostFinished {ghostFinished=true;active.removeAll();identities.removeAll();timer?.invalidate();timer=nil}
        if now-lastRate>=1 { rate=eventCount;eventCount=0;lastRate=now }
        if mode=="auto" { target=CGPoint(x:bounds.width*(0.5+0.38*sin((now-started)*0.83)),y:bounds.height*(0.5+0.35*sin((now-started)*1.27)));if let p=active.sorted(by:{$0.key<$1.key}).first?.value { errorSum += hypot(p.x-target.x,p.y-target.y);follows += 1 } }
        if ["auto","ghost","hold"].contains(mode) { setNeedsDisplay() }
    }
    override func touchesBegan(_ touches:Set<UITouch>,with event:UIEvent?) { process(touches,event:event,phase:"down") }
    override func touchesMoved(_ touches:Set<UITouch>,with event:UIEvent?) { process(touches,event:event,phase:"move") }
    override func touchesEnded(_ touches:Set<UITouch>,with event:UIEvent?) { process(touches,event:event,phase:"up") }
    override func touchesCancelled(_ touches:Set<UITouch>,with event:UIEvent?) { process(touches,event:event,phase:"cancel") }
    private func process(_ touches:Set<UITouch>,event:UIEvent?,phase:String) {
        if mode=="ghost" && (!ghostValid || ghostFinished || ProcessInfo.processInfo.systemUptime-started>=20) {return}
        for touch in touches.sorted(by:{$0.timestamp<$1.timestamp}) {
            let key=ObjectIdentifier(touch)
            if identities[key]==nil { identities[key]=nextID;nextID += 1 }
            let id=identities[key]!, p=touch.location(in:self)
            if phase=="down" {
                active[id]=p;maximum=max(maximum,active.count)
                if mode=="cross" {if p.x<bounds.midX && axisTouch==nil {axisTouch=id};if p.x>=bounds.midX && cursorTouch==nil {cursorTouch=id}}
                if mode=="ghost" && ghostValid && ProcessInfo.processInfo.systemUptime-started<20 { ghost += 1 }
                if mode=="colors" { solid=(solid+1)%6 }
                if mode=="tap" { taps += 1;if hypot(p.x-target.x,p.y-target.y)<=28 { hits += 1 };randomTarget() }
                if mode=="hold" && holdID==nil && hypot(p.x-bounds.midX,p.y-bounds.midY)<=48 { holdID=id;holdStart=ProcessInfo.processInfo.systemUptime;holdOrigin=p;holdDrift=0 }
            }
            let delivered=phase=="move" ? (event?.coalescedTouches(for:touch) ?? [touch]) : [touch]
            for sample in delivered.sorted(by:{$0.timestamp<$1.timestamp}) {
                let point=sample.location(in:self);total += 1;eventCount += 1
                active[id]=point
                if sampleRows.count<10000 { sampleRows.append(["mode":mode,"phase":phase,"id":id,"timestamp":sample.timestamp,"x":point.x,"y":point.y,"force":sample.force,"maximumPossibleForce":sample.maximumPossibleForce,"majorRadius":sample.majorRadius,"source":"UITouch","coalescedBatch":delivered.count>1,"stageWidth":bounds.width,"stageHeight":bounds.height]) }
                if ["multi","draw","line"].contains(mode) {
                    let path=livePaths[id] ?? UIBezierPath()
                    if path.isEmpty {path.append(UIBezierPath(ovalIn:CGRect(x:point.x-2,y:point.y-2,width:4,height:4)));path.move(to:point)} else {path.addLine(to:point)}
                    livePaths[id]=path;livePointCount += 1
                    if livePointCount>=1000 {flattenTrails()}
                }
                if mode=="grid" { let x=min(11,max(0,Int(point.x/max(1,bounds.width)*12))),y=min(23,max(0,Int(point.y/max(1,bounds.height)*24)));covered.insert(y*12+x) }
                if mode=="edge" { markEdges(point) }
                if mode=="line" { markLine(point) }
                if id==holdID { holdDrift=max(holdDrift,hypot(point.x-holdOrigin.x,point.y-holdOrigin.y)) }
                if id==cursorTouch {cursorPoint=CGPoint(x:min(bounds.width,max(bounds.midX,point.x)),y:min(bounds.height,max(0,point.y)))}
            }
            if phase=="up" || phase=="cancel" { active[id]=nil;radii[id]=nil;identities[key]=nil;if axisTouch==id {axisTouch=nil};if cursorTouch==id {cursorTouch=nil};if holdID==id { holdStart=ProcessInfo.processInfo.systemUptime-holdStart;holdID=nil } }
            else { active[id]=p;radii[id]=touch.majorRadius }
        }
        setNeedsDisplay()
    }
    private func strokeTrails() {
        for (id,path) in livePaths {colors[(id-1)%colors.count].setStroke();path.lineWidth=mode=="draw" ? 5 : 2;path.lineCapStyle = .round;path.lineJoinStyle = .round;path.stroke()}
    }
    private func flattenTrails() {
        guard bounds.width>0,bounds.height>0 else{return}
        let format=UIGraphicsImageRendererFormat();format.opaque=false;format.scale=window?.screen.scale ?? UIScreen.main.scale
        trailImage=UIGraphicsImageRenderer(size:bounds.size,format:format).image{_ in trailImage?.draw(in:bounds);strokeTrails()}
        livePaths.removeAll();livePointCount=0
        // Continue at the actual last delivered position without inventing a
        // straight segment between unrelated fingers or across cancelled input.
        for (id,p) in active {let path=UIBezierPath();path.move(to:p);livePaths[id]=path}
    }
    private func randomTarget() { target=CGPoint(x:CGFloat.random(in:45...max(45,bounds.width-45)),y:CGFloat.random(in:60...max(60,bounds.height-45))) }
    private func markEdges(_ p:CGPoint) {
        let x=min(19,max(0,Int(p.x/max(1,bounds.width)*20))),y=min(19,max(0,Int(p.y/max(1,bounds.height)*20)))
        if p.y<30 {edges.insert(x)};if p.y>bounds.height-30 {edges.insert(20+x)};if p.x<30 {edges.insert(40+y)};if p.x>bounds.width-30 {edges.insert(60+y)}
    }
    private func markLine(_ p:CGPoint) {
        let x=min(49,max(0,Int(p.x/max(1,bounds.width)*50))),y=min(49,max(0,Int(p.y/max(1,bounds.height)*50)))
        if abs(p.y-bounds.midY)<24 { lineCovered.insert(x) };if abs(p.x-bounds.midX)<24 {lineCovered.insert(50+y)}
        if abs(p.y-(bounds.height*0.18+p.x/max(1,bounds.width)*bounds.height*0.64))<24 {lineCovered.insert(100+x)}
    }
    override func draw(_ rect:CGRect) {
        guard let c=UIGraphicsGetCurrentContext() else{return}
        UIColor.black.setFill();c.fill(bounds)
        if mode=="colors" { [.black,.white,.red,.green,.blue,UIColor(white:0.5,alpha:1)][solid].setFill();c.fill(bounds);return }
        if mode=="bars" { for (i,color) in [UIColor.white,.yellow,.cyan,.green,.magenta,.red,.blue].enumerated() {color.setFill();c.fill(CGRect(x:CGFloat(i)*bounds.width/7,y:0,width:bounds.width/7+1,height:bounds.height))};return }
        if mode=="grid" { for i in 0..<288 { let r=CGRect(x:CGFloat(i%12)*bounds.width/12,y:CGFloat(i/12)*bounds.height/24,width:bounds.width/12,height:bounds.height/24);(covered.contains(i) ? UIColor.systemGreen : UIColor(white:0.08,alpha:1)).setFill();c.fill(r);UIColor.darkGray.setStroke();c.stroke(r,width:0.5) } }
        if mode=="edge" {for i in 0..<80 {let n=CGFloat(i%20);let r:CGRect;switch i/20 {case 0:r=CGRect(x:n*bounds.width/20,y:0,width:bounds.width/20,height:20);case 1:r=CGRect(x:n*bounds.width/20,y:bounds.height-20,width:bounds.width/20,height:20);case 2:r=CGRect(x:0,y:n*bounds.height/20,width:20,height:bounds.height/20);default:r=CGRect(x:bounds.width-20,y:n*bounds.height/20,width:20,height:bounds.height/20)};(edges.contains(i) ? UIColor.systemGreen : .darkGray).setFill();c.fill(r.insetBy(dx:0.5,dy:0.5))} }
        if mode=="line" {c.setStrokeColor(UIColor.darkGray.cgColor);c.setLineWidth(16);c.setLineDash(phase:0,lengths:[12,9]);for pair in [(CGPoint(x:0,y:bounds.midY),CGPoint(x:bounds.width,y:bounds.midY)),(CGPoint(x:bounds.midX,y:0),CGPoint(x:bounds.midX,y:bounds.height)),(CGPoint(x:0,y:bounds.height*0.18),CGPoint(x:bounds.width,y:bounds.height*0.82))] {c.move(to:pair.0);c.addLine(to:pair.1);c.strokePath()};c.setLineDash(phase:0,lengths:[]) }
        trailImage?.draw(in:bounds);strokeTrails()
        if ["tap","auto","hold"].contains(mode) {let p=mode=="hold" ? CGPoint(x:bounds.midX,y:bounds.midY) : target;c.setStrokeColor(UIColor.white.cgColor);c.setLineWidth(2);c.strokeEllipse(in:CGRect(x:p.x-28,y:p.y-28,width:56,height:56))}
        for (id,p) in active {
            let color=colors[(id-1)%colors.count];c.setStrokeColor(color.cgColor);c.setLineWidth(1);c.move(to:CGPoint(x:0,y:p.y));c.addLine(to:CGPoint(x:bounds.width,y:p.y));c.move(to:CGPoint(x:p.x,y:0));c.addLine(to:CGPoint(x:p.x,y:bounds.height));c.strokePath()
            let radius=max(8,radii[id] ?? 8);c.setFillColor(color.withAlphaComponent(0.5).cgColor);c.fillEllipse(in:CGRect(x:p.x-radius,y:p.y-radius,width:radius*2,height:radius*2))
            ("\(id)" as NSString).draw(at:CGPoint(x:p.x+radius+3,y:p.y-7),withAttributes:[.font:UIFont.monospacedSystemFont(ofSize:12,weight:.bold),.foregroundColor:UIColor.white])
        }
        if mode=="ghost" { centered(ghostValid ? "\(max(0,20-Int(ProcessInfo.processInfo.systemUptime-started)))s · 意外触控 \(ghost)" : "中断 · 请重置",in:c) }
        if mode=="hold" { centered(diagnostics,in:c) }
        if mode=="cross" {
            let center=CGPoint(x:bounds.width*0.25,y:bounds.height*0.55),radius=min(bounds.width*0.21,bounds.height*0.32)
            c.setStrokeColor(UIColor.gray.cgColor);c.strokeEllipse(in:CGRect(x:center.x-radius,y:center.y-radius,width:radius*2,height:radius*2));c.move(to:CGPoint(x:bounds.midX,y:0));c.addLine(to:CGPoint(x:bounds.midX,y:bounds.height));c.move(to:CGPoint(x:center.x-radius,y:center.y));c.addLine(to:CGPoint(x:center.x+radius,y:center.y));c.move(to:CGPoint(x:center.x,y:center.y-radius));c.addLine(to:CGPoint(x:center.x,y:center.y+radius));c.strokePath()
            let p=axisTouch.flatMap{active[$0]} ?? center,dx=p.x-center.x,dy=p.y-center.y,d=max(1,hypot(dx,dy)),k=min(1,radius/d)
            c.setFillColor(UIColor.white.cgColor);c.fillEllipse(in:CGRect(x:center.x+dx*k-12,y:center.y+dy*k-12,width:24,height:24));c.strokeEllipse(in:CGRect(x:cursorPoint.x-14,y:cursorPoint.y-14,width:28,height:28))
        }
    }
    private func centered(_ text:String,in context:CGContext) {let attributes:[NSAttributedString.Key:Any]=[.font:UIFont.systemFont(ofSize:17,weight:.medium),.foregroundColor:UIColor.white];let size=(text as NSString).size(withAttributes:attributes);(text as NSString).draw(at:CGPoint(x:bounds.midX-size.width/2,y:bounds.midY+55),withAttributes:attributes)}
    func report()->[String:Any] { ["implementation":"UIKit","source":"UITouch","coordinateUnit":"pt in full-window native canvas","timeUnit":"UITouch timestamp in monotonic seconds","mode":mode,"device":UIDevice.current.model,"systemVersion":UIDevice.current.systemVersion,"viewport":["width":bounds.width,"height":bounds.height],"limits":["limit":10000,"retained":sampleRows.count,"totalObserved":total,"dropped":total-sampleRows.count],"metrics":diagnostics,"ghost":["count":ghost,"durationSeconds":20,"status":!ghostValid ? "interrupted" : (ProcessInfo.processInfo.systemUptime-started>=20 ? "completed" : "running")],"verdict":"未人工验收","samples":sampleRows.sorted{($0["timestamp"] as? Double ?? 0)<($1["timestamp"] as? Double ?? 0)}] }
    func interrupt() {active.removeAll();identities.removeAll();axisTouch=nil;cursorTouch=nil;if mode=="ghost" && ProcessInfo.processInfo.systemUptime-started<20 {ghostValid=false;ghostFinished=true;timer?.invalidate();timer=nil};if holdID != nil {holdStart=ProcessInfo.processInfo.systemUptime-holdStart;holdID=nil};setNeedsDisplay()}
    func stopScene() {timer?.invalidate();timer=nil;interrupt()}
    deinit {timer?.invalidate()}
}
