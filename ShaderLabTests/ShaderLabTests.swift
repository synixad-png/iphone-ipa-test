import XCTest
import SceneKit
import Metal
@testable import HelloIPhone

@MainActor
final class ShaderLabTests: XCTestCase {
    let color = UIColor(red: 0.25, green: 0.45, blue: 0.7, alpha: 1)
    var folder: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("ShaderLabEvidence")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func record(_ name: String, _ data: Any) throws {
        try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent(name + ".json"))
    }
    func pixels(_ image: UIImage) throws -> [UInt8] {
        let cg = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let ok = bytes.withUnsafeMutableBytes { ptr -> Bool in
            guard let ctx = CGContext(data: ptr.baseAddress, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height)); return true
        }
        XCTAssertTrue(ok)
        return bytes
    }
    func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count && !a.isEmpty else { return 1 }
        return zip(a, b).enumerated().filter { $0.offset % 4 != 3 }.reduce(0.0) { $0 + abs(Double($1.element.0) - Double($1.element.1)) } / Double(a.count / 4 * 3) / 255
    }
    func render(_ scene: SCNScene, name: String) throws -> [UInt8] {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal device unavailable: visual rendering is not verified on this runner") }
        let renderer = SCNRenderer(device: device, options: nil)
        XCTAssertEqual(renderer.renderingAPI, .metal)
        renderer.scene = scene
        renderer.pointOfView = scene.rootNode.childNode(withName: "camera", recursively: false)
        XCTAssertTrue(renderer.prepare([scene], shouldAbortBlock: nil))
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: 192, height: 192), antialiasingMode: .multisampling4X)
        try XCTUnwrap(image.pngData()).write(to: folder.appendingPathComponent(name + ".png"))
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        return try pixels(image)
    }
    func scene(_ mode: Shading3D, shape: Shape3D = .sphere, metal: Double = 0.75, rough: Double = 0.22) -> SCNScene {
        ShaderScene.makeScene(shape: shape, shading: mode, color: color, metalness: metal, roughness: rough)
    }
    func testAllShapesAndNativeLightingModels() throws {
        XCTAssertEqual(Shape3D.allCases.count, 7)
        XCTAssertEqual(Shading3D.allCases.count, 5)
        XCTAssertEqual(Set(Shading3D.allCases.map { $0.lighting.rawValue }).count, 5)
        for shape in Shape3D.allCases {
            for mode in Shading3D.allCases {
                let s = scene(mode, shape: shape)
                let model = try XCTUnwrap(s.rootNode.childNode(withName: "model", recursively: false))
                let geometry = try XCTUnwrap(model.geometry)
                XCTAssertFalse(geometry.sources(for: .vertex).isEmpty)
                XCTAssertEqual(geometry.firstMaterial?.lightingModel, mode.lighting)
            }
        }
    }
    func testRenderAll35CombinationsAndDistinctModes() throws {
        var spherePixels: [[UInt8]] = []
        var matrix: [[String: Any]] = []
        for (i, shape) in Shape3D.allCases.enumerated() {
            for (j, mode) in Shading3D.allCases.enumerated() {
                let image = try autoreleasepool { try render(scene(mode, shape: shape), name: "shape-\(i)-mode-\(j)") }
                // A visible silhouette must differ from the corner background in many pixels.
                let reference = Array(image.prefix(3))
                let visible = stride(from: 0, to: image.count, by: 4).filter { k in (0..<3).contains { abs(Int(image[k+$0]) - Int(reference[$0])) > 8 } }.count
                XCTAssertGreaterThan(visible, 1000, "No visible object for \(shape.rawValue), \(mode.rawValue)")
                matrix.append(["shape": shape.rawValue, "mode": mode.rawValue, "visible_pixels": visible])
                if shape == .sphere { spherePixels.append(image) }
            }
        }
        var differences: [[String: Any]] = []
        for i in 0..<spherePixels.count {
            for j in (i+1)..<spherePixels.count {
                let delta = difference(spherePixels[i], spherePixels[j])
                differences.append(["a": Shading3D.allCases[i].rawValue, "b": Shading3D.allCases[j].rawValue, "mean_pixel_difference": delta])
                XCTAssertGreaterThan(delta, 0.0001, "Modes \(i) and \(j) render identically")
            }
        }
        try record("render-matrix", matrix); try record("mode-differences", differences)
    }
    func testPBRMetalnessRoughnessAndMaterialColorChangePixels() throws {
        let base = try render(scene(.pbr, metal: 0, rough: 0.15), name: "pbr-dielectric")
        let metal = try render(scene(.pbr, metal: 1, rough: 0.15), name: "pbr-metal")
        let rough = try render(scene(.pbr, metal: 1, rough: 0.9), name: "pbr-rough")
        let alternate = ShaderScene.makeScene(shading: .pbr, color: .red, metalness: 1, roughness: 0.15)
        let recolored = try render(alternate, name: "pbr-recolored")
        let metrics = ["metalness_difference": difference(base, metal), "roughness_difference": difference(metal, rough), "color_difference": difference(metal, recolored)]
        for (key, value) in metrics { XCTAssertGreaterThan(value, 0.001, key) }
        try record("pbr-controls", metrics)
    }
    func testUnlitIgnoresLightsAndLambertReacts() throws {
        var metrics: [String: Double] = [:]
        for mode in [Shading3D.constant, .lambert] {
            let s = scene(mode)
            let lit = try render(s, name: "\(mode.id)-lights-on")
            s.lightingEnvironment.intensity = 0
            s.rootNode.enumerateChildNodes { node, _ in node.light?.intensity = 0 }
            let dark = try render(s, name: "\(mode.id)-lights-off")
            let delta = difference(lit, dark); metrics[mode.id] = delta
            if mode == .constant { XCTAssertLessThan(delta, 0.0001) }
            else { XCTAssertGreaterThan(delta, 0.001) }
        }
        try record("light-response", metrics)
    }
    func testCameraAndContinuousMaterialUpdates() throws {
        let view = ShaderScene.makeView()
        XCTAssertTrue(view.allowsCameraControl)
        XCTAssertEqual(view.renderingAPI, .metal)
        let s = try XCTUnwrap(view.scene)
        let node = try XCTUnwrap(s.rootNode.childNode(withName: "model", recursively: false))
        ShaderScene.update(s, shape: .sphere, shading: .pbr, color: color, metalness: 0.2, roughness: 0.3, spinning: true)
        let geometry = node.geometry
        let spin = node.action(forKey: "spin")
        ShaderScene.update(s, shape: .sphere, shading: .pbr, color: color, metalness: 0.8, roughness: 0.7, spinning: true)
        XCTAssertTrue(node.geometry === geometry, "Changing a slider must not recreate geometry")
        XCTAssertTrue(node.action(forKey: "spin") === spin, "Changing a slider must not restart rotation")
        XCTAssertEqual((node.geometry?.firstMaterial?.metalness.contents as? NSNumber)?.doubleValue, 0.8)
        ShaderScene.update(s, shape: .cube, shading: .blinn, color: color, metalness: 0.8, roughness: 0.7, spinning: false)
        XCTAssertTrue(node.geometry is SCNBox)
        XCTAssertNil(node.action(forKey: "spin"))
    }
}
