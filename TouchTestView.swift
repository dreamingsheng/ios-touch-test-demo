import SwiftUI
import UIKit

// MARK: - Native multi-touch sampler

enum SamplePhase { case began, moved, ended, cancelled }

struct TouchSample: Identifiable {
    let id: Int
    let location: CGPoint
    let timestamp: TimeInterval
    let force: CGFloat
    let radius: CGFloat
    let phase: SamplePhase
}

struct TouchSurface: UIViewRepresentable {
    var onUpdate: ([TouchSample], [TouchSample]) -> Void

    func makeUIView(context: Context) -> SamplingView {
        let view = SamplingView()
        view.isMultipleTouchEnabled = true
        view.backgroundColor = .clear
        view.onUpdate = onUpdate
        return view
    }

    func updateUIView(_ uiView: SamplingView, context: Context) { uiView.onUpdate = onUpdate }
}

final class SamplingView: UIView {
    var onUpdate: (([TouchSample], [TouchSample]) -> Void)?
    private var active: [ObjectIdentifier: UITouch] = [:]
    private var ids: [ObjectIdentifier: Int] = [:]
    private var nextID = 1

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { process(touches, event, .began) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { process(touches, event, .moved) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { process(touches, event, .ended) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { process(touches, event, .cancelled) }

    private func process(_ touches: Set<UITouch>, _ event: UIEvent?, _ phase: SamplePhase) {
        var batch: [TouchSample] = []
        for touch in touches {
            let key = ObjectIdentifier(touch)
            if ids[key] == nil { ids[key] = nextID; nextID += 1 }
            guard let id = ids[key] else { continue }
            for item in event?.coalescedTouches(for: touch) ?? [touch] {
                batch.append(sample(item, id, phase))
            }
            if phase == .ended || phase == .cancelled { active[key] = nil } else { active[key] = touch }
        }
        let current = active.compactMap { key, touch in ids[key].map { sample(touch, $0, .moved) } }.sorted { $0.id < $1.id }
        onUpdate?(batch, current)
        if phase == .ended || phase == .cancelled {
            touches.forEach { ids[ObjectIdentifier($0)] = nil }
        }
    }

    private func sample(_ touch: UITouch, _ id: Int, _ phase: SamplePhase) -> TouchSample {
        let maximum = touch.maximumPossibleForce
        return TouchSample(
            id: id,
            location: touch.location(in: self),
            timestamp: touch.timestamp,
            force: maximum > 0 ? min(max(touch.force / maximum, 0), 1) : 0,
            radius: max(touch.majorRadius, 8),
            phase: phase
        )
    }
}

private let palette: [Color] = [.cyan, .yellow, .mint, .orange, .pink, .purple, .green, .blue, .red, .indigo]
private func touchColor(_ id: Int) -> Color { palette[abs(id) % palette.count] }

private struct Metric: View {
    let title: String
    let value: String
    var color: Color = .cyan
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.system(.headline, design: .rounded).bold())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 11))
    }
}

private struct OverlayHeader: View {
    let title: String
    let help: String
    let reset: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(help).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: reset) {
                Image(systemName: "arrow.counterclockwise").font(.headline).padding(9).background(.thinMaterial, in: Circle())
            }.buttonStyle(.plain)
        }
        .padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16)).padding(10)
    }
}

// MARK: - Test menu

struct TouchTestView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("常规触控测试套件", systemImage: "waveform.path.ecg.rectangle").font(.title3.bold())
                        Text("建议擦净屏幕并拔掉充电器，依次测试多点、网格、边缘、点击和长按；异常时取下保护膜复测。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
                    TestLink("hand.tap.fill", .cyan, "多点触控与轨迹", "上限、坐标、接触面、事件率和疑似断触") { MultiTouchView() }
                    TestLink("square.grid.3x3.fill", .green, "全屏网格死区", "涂满 12×24 网格，查找无法触达的区域") { GridView() }
                    TestLink("rectangle.dashed", .orange, "边缘与四角", "分段扫描四边，检查贴边响应") { EdgeView() }
                    TestLink("scope", .pink, "点击精度", "随机靶心测试，统计平均和最大偏差") { AccuracyView() }
                    TestLink("dot.scope", .purple, "长按稳定性", "统计固定按压时的坐标漂移") { HoldView() }
                    TestLink("paintpalette.fill", .red, "显示与坏点辅助", "红绿蓝、黑白、灰阶和彩条检查") { DisplayView() }
                    VStack(alignment: .leading, spacing: 5) {
                        Label("测试边界", systemImage: "info.circle").font(.subheadline.bold())
                        Text("本工具读取 iOS 的 UITouch 事件，不能访问 Goodix 等触控 IC 的原始电容矩阵、固件寄存器或工厂校准通道。压力仅在设备提供时有效。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                }.padding()
            }
            .background(Color(uiColor: .systemGroupedBackground)).navigationTitle("触控诊断")
        }.tint(.cyan)
    }
}

private struct TestLink<D: View>: View {
    let icon: String; let color: Color; let title: String; let detail: String; let destination: () -> D
    init(_ icon: String, _ color: Color, _ title: String, _ detail: String, @ViewBuilder destination: @escaping () -> D) {
        self.icon = icon; self.color = color; self.title = title; self.detail = detail; self.destination = destination
    }
    var body: some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 13) {
                Image(systemName: icon).font(.title2).foregroundStyle(color).frame(width: 42, height: 42).background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer(); Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }.padding(13).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 17))
        }.buttonStyle(.plain)
    }
}

// MARK: - Multi-touch, sampling rate and continuity

@MainActor final class MultiModel: ObservableObject {
    @Published var active: [TouchSample] = []
    @Published var trails: [Int: [CGPoint]] = [:]
    @Published var maximum = 0
    @Published var rate = 0
    @Published var gaps = 0
    private var recent: [TimeInterval] = []
    private var previous: [Int: TouchSample] = [:]

    func update(_ batch: [TouchSample], _ current: [TouchSample]) {
        active = current; maximum = max(maximum, current.count)
        for item in batch {
            trails[item.id, default: []].append(item.location)
            if let count = trails[item.id]?.count, count > 180 { trails[item.id]?.removeFirst(count - 180) }
            if let old = previous[item.id], item.phase == .moved {
                let distance = hypot(item.location.x - old.location.x, item.location.y - old.location.y)
                if item.timestamp - old.timestamp > 0.08 && distance > 24 { gaps += 1 }
            }
            if item.phase == .ended || item.phase == .cancelled { previous[item.id] = nil } else { previous[item.id] = item }
            recent.append(item.timestamp)
        }
        if let now = recent.last { recent.removeAll { now - $0 > 1 }; rate = recent.count }
    }
    func reset() { active = []; trails = [:]; maximum = 0; rate = 0; gaps = 0; recent = []; previous = [:] }
}

private struct MultiTouchView: View {
    @StateObject private var model = MultiModel()
    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            Canvas { context, _ in
                for (id, points) in model.trails where points.count > 1 {
                    var path = Path(); path.move(to: points[0]); points.dropFirst().forEach { path.addLine(to: $0) }
                    context.stroke(path, with: .color(touchColor(id).opacity(0.8)), lineWidth: 4)
                }
                for item in model.active {
                    let diameter = max(item.radius * 2, 48)
                    let rect = CGRect(x: item.location.x - diameter / 2, y: item.location.y - diameter / 2, width: diameter, height: diameter)
                    context.fill(Path(ellipseIn: rect), with: .color(touchColor(item.id).opacity(0.28)))
                    context.stroke(Path(ellipseIn: rect), with: .color(touchColor(item.id)), lineWidth: 2)
                    context.draw(Text("\(item.id)").font(.headline).foregroundColor(.white), at: item.location)
                }
            }.allowsHitTesting(false)
            TouchSurface { model.update($0, $1) }.ignoresSafeArea()
            VStack(spacing: 5) {
                OverlayHeader(title: "多点触控与连续性", help: "同时放入多根手指缓慢划动；轨迹应连续且触点不应跳跃。", reset: model.reset)
                HStack(spacing: 6) {
                    Metric(title: "当前", value: "\(model.active.count)")
                    Metric(title: "最高", value: "\(model.maximum)", color: .green)
                    Metric(title: "事件/秒", value: "\(model.rate)", color: .blue)
                    Metric(title: "可疑断线", value: "\(model.gaps)", color: model.gaps == 0 ? .green : .red)
                }.padding(.horizontal, 10)
                if let p = model.active.first {
                    Text("#\(p.id)  x \(Int(p.location.x))  y \(Int(p.location.y))  压力 \(Int(p.force * 100))%  半径 \(Int(p.radius))pt")
                        .font(.system(.caption2, design: .monospaced)).foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
            }.allowsHitTesting(false)
        }.fullScreenTestStyle()
    }
}

// MARK: - Dead-zone grid

private struct GridView: View {
    let columns = 12, rows = 24
    @State private var hit: Set<Int> = []
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()
                Canvas { context, size in
                    let w = size.width / CGFloat(columns), h = size.height / CGFloat(rows)
                    for row in 0..<rows { for col in 0..<columns {
                        let index = row * columns + col
                        let rect = CGRect(x: CGFloat(col) * w, y: CGFloat(row) * h, width: w, height: h).insetBy(dx: 1, dy: 1)
                        context.fill(Path(rect), with: .color(hit.contains(index) ? .green.opacity(0.78) : .gray.opacity(0.16)))
                        context.stroke(Path(rect), with: .color(.white.opacity(0.14)), lineWidth: 0.5)
                    }}
                }.allowsHitTesting(false)
                TouchSurface { batch, _ in mark(batch, proxy.size) }.ignoresSafeArea()
                OverlayHeader(title: "网格死区 \(hit.count)/\(columns * rows) · \(hit.count * 100 / (columns * rows))%", help: "用单指逐行涂满。始终无法点亮的格子可能是死区。", reset: { hit.removeAll() }).allowsHitTesting(false)
            }
        }.fullScreenTestStyle()
    }
    private func mark(_ batch: [TouchSample], _ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        for p in batch {
            let x = min(max(Int(p.location.x / size.width * CGFloat(columns)), 0), columns - 1)
            let y = min(max(Int(p.location.y / size.height * CGFloat(rows)), 0), rows - 1)
            hit.insert(y * columns + x)
        }
    }
}

// MARK: - Edge segments

private struct EdgeView: View {
    let count = 10; let band: CGFloat = 38
    @State private var hit: Set<Int> = []
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()
                Canvas { context, size in draw(context, size) }.allowsHitTesting(false)
                TouchSurface { batch, _ in mark(batch, proxy.size) }.ignoresSafeArea()
                VStack {
                    OverlayHeader(title: "边缘扫描 \(hit.count)/\(count * 4)", help: "沿四边缓慢滑动并覆盖四角；全部分段应变绿。", reset: { hit.removeAll() })
                    Spacer()
                    Text(hit.count == count * 4 ? "四边已全部触达" : "还剩 \(count * 4 - hit.count) 段")
                        .font(.headline).padding(.horizontal, 16).padding(.vertical, 9).background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 25)
                }.allowsHitTesting(false)
            }
        }.fullScreenTestStyle()
    }
    private func draw(_ context: GraphicsContext, _ size: CGSize) {
        let w = size.width / CGFloat(count), h = size.height / CGFloat(count)
        for i in 0..<count {
            let rects = [
                CGRect(x: CGFloat(i) * w, y: 0, width: w, height: band),
                CGRect(x: size.width - band, y: CGFloat(i) * h, width: band, height: h),
                CGRect(x: CGFloat(count - i - 1) * w, y: size.height - band, width: w, height: band),
                CGRect(x: 0, y: CGFloat(count - i - 1) * h, width: band, height: h)
            ]
            for side in 0..<4 {
                context.fill(Path(rects[side].insetBy(dx: 2, dy: 2)), with: .color(hit.contains(side * count + i) ? .green.opacity(0.85) : .orange.opacity(0.22)))
            }
        }
    }
    private func mark(_ batch: [TouchSample], _ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        for p in batch {
            if p.location.y <= band { hit.insert(min(Int(p.location.x / size.width * CGFloat(count)), count - 1)) }
            if p.location.x >= size.width - band { hit.insert(count + min(Int(p.location.y / size.height * CGFloat(count)), count - 1)) }
            if p.location.y >= size.height - band { hit.insert(count * 2 + min(Int((size.width - p.location.x) / size.width * CGFloat(count)), count - 1)) }
            if p.location.x <= band { hit.insert(count * 3 + min(Int((size.height - p.location.y) / size.height * CGFloat(count)), count - 1)) }
        }
    }
}

// MARK: - Tap accuracy

private struct AccuracyView: View {
    @State private var target = CGPoint(x: 0.5, y: 0.55)
    @State private var errors: [CGFloat] = []
    @State private var misses = 0
    @State private var last: CGPoint?
    var body: some View {
        GeometryReader { proxy in
            let point = CGPoint(x: target.x * proxy.size.width, y: target.y * proxy.size.height)
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()
                Canvas { context, _ in
                    context.stroke(Path(ellipseIn: CGRect(x: point.x - 32, y: point.y - 32, width: 64, height: 64)), with: .color(.cyan), lineWidth: 3)
                    context.stroke(Path { p in
                        p.move(to: CGPoint(x: point.x - 42, y: point.y)); p.addLine(to: CGPoint(x: point.x + 42, y: point.y))
                        p.move(to: CGPoint(x: point.x, y: point.y - 42)); p.addLine(to: CGPoint(x: point.x, y: point.y + 42))
                    }, with: .color(.cyan), lineWidth: 1)
                    if let last { context.fill(Path(ellipseIn: CGRect(x: last.x - 5, y: last.y - 5, width: 10, height: 10)), with: .color(.pink)) }
                }.allowsHitTesting(false)
                TouchSurface { batch, _ in
                    if let tap = batch.first(where: { $0.phase == .began }) { register(tap.location, point) }
                }.ignoresSafeArea()
                VStack(spacing: 4) {
                    OverlayHeader(title: "点击精度", help: "准确点击十字靶心；粉点是实际落点。", reset: reset)
                    HStack(spacing: 6) {
                        Metric(title: "次数", value: "\(errors.count)", color: .green)
                        Metric(title: "偏离", value: "\(misses)", color: .red)
                        Metric(title: "平均误差", value: errors.isEmpty ? "--" : "\(Int(errors.reduce(0, +) / CGFloat(errors.count)))pt", color: .blue)
                        Metric(title: "最大误差", value: errors.max().map { "\(Int($0))pt" } ?? "--", color: .orange)
                    }.padding(.horizontal, 10)
                    Spacer()
                }.allowsHitTesting(false)
            }
        }.fullScreenTestStyle()
    }
    private func register(_ actual: CGPoint, _ expected: CGPoint) {
        let error = hypot(actual.x - expected.x, actual.y - expected.y)
        errors.append(error); if error > 32 { misses += 1 }; last = actual
        target = CGPoint(x: .random(in: 0.12...0.88), y: .random(in: 0.25...0.88))
    }
    private func reset() { target = CGPoint(x: 0.5, y: 0.55); errors = []; misses = 0; last = nil }
}

// MARK: - Long-press drift

private struct HoldView: View {
    @State private var origin: CGPoint?
    @State private var current: CGPoint?
    @State private var began: TimeInterval?
    @State private var duration: TimeInterval = 0
    @State private var drift: CGFloat = 0
    @State private var samples = 0
    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height * 0.58)
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()
                Canvas { context, _ in
                    let circle = CGRect(x: center.x - 70, y: center.y - 70, width: 140, height: 140)
                    context.fill(Path(ellipseIn: circle), with: .color(.purple.opacity(0.18)))
                    context.stroke(Path(ellipseIn: circle), with: .color(.purple), lineWidth: 3)
                    if let origin, let current {
                        var path = Path(); path.move(to: origin); path.addLine(to: current)
                        context.stroke(path, with: .color(.yellow), lineWidth: 2)
                        context.fill(Path(ellipseIn: CGRect(x: current.x - 7, y: current.y - 7, width: 14, height: 14)), with: .color(.yellow))
                    }
                }.allowsHitTesting(false)
                TouchSurface { update($0, $1) }.ignoresSafeArea()
                VStack(spacing: 4) {
                    OverlayHeader(title: "长按稳定性", help: "在中央圆圈内单指保持 5 秒，漂移越小越稳定。", reset: reset)
                    HStack(spacing: 6) {
                        Metric(title: "持续", value: String(format: "%.1fs", duration), color: .purple)
                        Metric(title: "最大漂移", value: String(format: "%.1fpt", drift), color: drift < 8 ? .green : .orange)
                        Metric(title: "采样数", value: "\(samples)", color: .blue)
                    }.padding(.horizontal, 10)
                    Spacer()
                    Text(duration >= 5 ? "已完成 5 秒长按" : "请在圆圈中长按").font(.headline).foregroundStyle(duration >= 5 ? .green : .white).padding(.bottom, 35)
                }.allowsHitTesting(false)
            }
        }.fullScreenTestStyle()
    }
    private func update(_ batch: [TouchSample], _ active: [TouchSample]) {
        for p in batch {
            if origin == nil && p.phase == .began { origin = p.location; began = p.timestamp }
            if let origin, let began {
                current = p.location; duration = max(duration, p.timestamp - began)
                drift = max(drift, hypot(p.location.x - origin.x, p.location.y - origin.y)); samples += 1
            }
        }
        if active.isEmpty && batch.contains(where: { $0.phase == .ended || $0.phase == .cancelled }) { origin = nil; current = nil; began = nil }
    }
    private func reset() { origin = nil; current = nil; began = nil; duration = 0; drift = 0; samples = 0 }
}

// MARK: - Display patterns

private struct DisplayView: View {
    let names = ["红色", "绿色", "蓝色", "白色", "黑色", "50% 灰", "灰阶", "彩条"]
    @State private var index = 0
    var body: some View {
        ZStack {
            pattern.ignoresSafeArea()
            VStack {
                Text("\(index + 1)/\(names.count) · \(names[index])").font(.headline).padding(.horizontal, 14).padding(.vertical, 8).background(.ultraThinMaterial, in: Capsule()).padding()
                Spacer()
                Text("轻点切换 · 检查亮点、暗点、色斑、残影和漏光").font(.caption.bold()).padding(.horizontal, 14).padding(.vertical, 8).background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 25)
            }.foregroundStyle(index == 3 ? .black : .white).allowsHitTesting(false)
        }.contentShape(Rectangle()).onTapGesture { index = (index + 1) % names.count }.fullScreenTestStyle()
    }
    @ViewBuilder var pattern: some View {
        switch index {
        case 0: Color.red
        case 1: Color.green
        case 2: Color.blue
        case 3: Color.white
        case 4: Color.black
        case 5: Color(white: 0.5)
        case 6: LinearGradient(colors: stride(from: 0.0, through: 1.0, by: 0.1).map { Color(white: $0) }, startPoint: .leading, endPoint: .trailing)
        default: HStack(spacing: 0) { Color.white; Color.yellow; Color.cyan; Color.green; Color.magenta; Color.red; Color.blue; Color.black }
        }
    }
}

private extension View {
    func fullScreenTestStyle() -> some View {
        navigationBarTitleDisplayMode(.inline).statusBarHidden().persistentSystemOverlays(.hidden)
    }
}
