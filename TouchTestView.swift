import SwiftUI
import UIKit

struct TouchPoint: Identifiable {
    let id: ObjectIdentifier
    let location: CGPoint
    let force: CGFloat
}

@MainActor
final class TouchModel: ObservableObject {
    @Published var points: [TouchPoint] = []
}

struct TouchTestView: View {
    @StateObject private var model = TouchModel()

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            TouchCanvas(model: model).ignoresSafeArea()

            ForEach(Array(model.points.enumerated()), id: \.element.id) { index, point in
                ZStack {
                    Circle()
                        .fill(Color.cyan.opacity(0.35))
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .frame(width: 72, height: 72)
                    Text("\(index + 1)")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
                .position(point.location)
                .allowsHitTesting(false)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Touch Test")
                    .font(.title2.bold())
                Text("触点数量：\(model.points.count)")
                ForEach(Array(model.points.enumerated()), id: \.element.id) { index, point in
                    Text("#\(index + 1)  x: \(Int(point.location.x))  y: \(Int(point.location.y))  force: \(point.force, specifier: "%.2f")")
                        .font(.system(.caption, design: .monospaced))
                }
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
            .padding()
            .allowsHitTesting(false)
        }
        .statusBarHidden()
    }
}

struct TouchCanvas: UIViewRepresentable {
    @ObservedObject var model: TouchModel

    func makeUIView(context: Context) -> TouchCanvasUIView {
        let view = TouchCanvasUIView()
        view.isMultipleTouchEnabled = true
        view.backgroundColor = .clear
        view.onChange = { touches in
            model.points = touches
        }
        return view
    }

    func updateUIView(_ uiView: TouchCanvasUIView, context: Context) {}
}

final class TouchCanvasUIView: UIView {
    var onChange: (([TouchPoint]) -> Void)?
    private var activeTouches: [ObjectIdentifier: UITouch] = [:]

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        update(touches, removing: false)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        update(touches, removing: false)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        update(touches, removing: true)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        update(touches, removing: true)
    }

    private func update(_ touches: Set<UITouch>, removing: Bool) {
        for touch in touches {
            let key = ObjectIdentifier(touch)
            if removing {
                activeTouches.removeValue(forKey: key)
            } else {
                activeTouches[key] = touch
            }
        }

        let snapshot = activeTouches.map { key, touch in
            TouchPoint(id: key, location: touch.location(in: self), force: touch.force)
        }
        .sorted { String(describing: $0.id) < String(describing: $1.id) }
        onChange?(snapshot)
    }
}
