import XCTest
import SceneKit
import SpriteKit
import SwiftUI
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
        XCTAssertTrue(renderer.prepare(scene, shouldAbortBlock: nil))
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: 192, height: 192), antialiasingMode: .multisampling4X)
        try XCTUnwrap(image.pngData()).write(to: folder.appendingPathComponent(name.replacingOccurrences(of: "/", with: "_") + ".png"))
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        return try pixels(image)
    }
    func scene(_ mode: Shading3D, shape: Shape3D = .sphere, metal: Double = 0.75, rough: Double = 0.22) -> SCNScene {
        ShaderScene.makeScene(shape: shape, shading: mode, color: color, metalness: metal, roughness: rough)
    }




    func testLandscapeAndTouchAnalogSceneState() {
        let supported = Bundle.main.object(forInfoDictionaryKey: "UISupportedInterfaceOrientations") as? [String] ?? []
        XCTAssertTrue(supported.contains("UIInterfaceOrientationPortrait"),
                      "The application must return to portrait after fullscreen games")
        XCTAssertTrue(supported.contains("UIInterfaceOrientationLandscapeLeft"),
                      "Fullscreen games require landscape left")
        XCTAssertTrue(supported.contains("UIInterfaceOrientationLandscapeRight"),
                      "Fullscreen games require landscape right")
        let scene = AsteroidsArcadeScene(size: CGSize(width: 390, height: 660))
        scene.moveAnalog = CGVector(dx: 0.8, dy: -0.3)
        scene.aimAnalog = CGVector(dx: -0.8, dy: 0.4)
        XCTAssertEqual(scene.moveAnalog.dx, 0.8)
        XCTAssertEqual(scene.aimAnalog.dy, 0.4)
        scene.moveAnalog = .zero
        scene.aimAnalog = .zero
        XCTAssertEqual(scene.moveAnalog.dx, 0)
        XCTAssertEqual(scene.aimAnalog.dy, 0)
    }

    func testFullscreenGameViewsInstantiateWithoutWad() {
        let arcade = AsteroidsArcadeScene(size: CGSize(width: 320, height: 220))
        let arcadeController = UIHostingController(rootView: AsteroidsLandscapeView(scene: arcade, close: {}))
        arcadeController.loadViewIfNeeded()
        XCTAssertNotNil(arcadeController.view)
        let doom = DoomLandscapeView(frame: nil, move: { _ in }, aim: { _ in },
                                     interact: { _ in }, menu: { _ in }, close: {})
        let doomController = UIHostingController(rootView: doom)
        doomController.loadViewIfNeeded()
        XCTAssertNotNil(doomController.view)
    }

    func testDoomNativeSFXMixerAndPanning() {
        // Original Doom 8-bit PCM through the real AudioToolbox mixing backend.
        XCTAssertEqual(doom_audio_selftest(), 1, "Left/right panning and signed PCM mixing must be correct")
        doom_audio_set_volume(0)
        doom_audio_set_volume(0.85)
    }

    func testZZDoomSharewareNativeFirstFrame() async throws {
        // Obtain the historical shareware ZIP only inside the simulator test, not in the IPA.
        let remote = try XCTUnwrap(URL(string: "https://www.jbserver.com/downloads/games/doom/misc/shareware/doom1.wad.zip"))
        var request = URLRequest(url: remote)
        request.timeoutInterval = 35
        let archive: Data
        do {
            let (received, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            archive = received
        } catch {
            throw XCTSkip("External Doom shareware archive unavailable; native gameplay smoke test not run: \(error)")
        }
        let root = FileManager.default.temporaryDirectory
        let zip = root.appendingPathComponent("doom-native-test.zip")
        let wad = root.appendingPathComponent("DOOM1.WAD")
        try archive.write(to: zip)
        defer {
            try? FileManager.default.removeItem(at: zip)
            try? FileManager.default.removeItem(at: wad)
        }
        let unpacked = zip.path.withCString { zipPath in
            wad.path.withCString { wadPath in
                doom_bridge_extract_shareware_zip(zipPath, wadPath)
            }
        }
        XCTAssertEqual(unpacked, 0, "Shareware ZIP must yield valid original WAD")
        guard unpacked == 0 else { return }
        XCTAssertEqual(wad.path.withCString { doom_bridge_start($0) }, 1)
        var frame = [UInt32](repeating: 0, count: 320 * 200)
        var displayed = false
        for _ in 0..<200 {
            if doom_bridge_status() < 0 { break }
            let n = frame.withUnsafeMutableBufferPointer {
                doom_bridge_copy($0.baseAddress, Int32($0.count))
            }
            if n == frame.count && frame.contains(where: { $0 != 0 }) {
                displayed = true
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(displayed, "Native Doom must render a nonblank first frame from shareware data")
        XCTAssertEqual(doom_audio_is_active(), 1,
                       "Native Doom SFX backend must initialize on iOS simulator")
        XCTAssertGreaterThan(doom_audio_callback_count(), 0,
                             "AudioQueue must continuously request audio buffers")
        doom_bridge_pause(1)
    }

    func testSmileQuotesCatalogAndNames() {
        XCTAssertEqual(SmileQuote.catalog.count, 48)
        XCTAssertEqual(Set(SmileQuote.catalog.map(\.id)).count, 48)
        for hero in [SmileHero.hania, .martna, .ania] {
            let quotes = SmileQuote.filtered(hero)
            XCTAssertGreaterThan(quotes.count, 12)
            XCTAssertTrue(quotes.allSatisfy { $0.hero == hero || $0.hero == .all })
            XCTAssertTrue(SmileQuote.catalog.contains { $0.hero == hero })
        }
        XCTAssertEqual(SmileQuote.filtered(.all).count, 48)
        XCTAssertFalse(SmileQuote.catalog.contains { $0.text.isEmpty || $0.signature.isEmpty })
    }

    func testSmileQuotesNeverImmediatelyRepeatWhenAlternativesExist() {
        let quotes = SmileQuote.filtered(.hania)
        let previous = quotes[0].id
        for _ in 0..<200 {
            let next = SmileQuote.next(in: quotes, excluding: previous)
            XCTAssertNotNil(next)
            XCTAssertNotEqual(next?.id, previous)
        }
        XCTAssertNil(SmileQuote.next(in: [], excluding: nil))
        let single = [quotes[0]]
        XCTAssertEqual(SmileQuote.next(in: single, excluding: previous)?.id, previous)
    }

    func testPaintUndoRedoClearAndNewStroke() {
        let doc = PaintDocument(loadExisting: false)
        let one = PaintStroke(points: [PaintPoint(x:0.1,y:0.2), PaintPoint(x:0.7,y:0.8)],
                              paletteIndex:7, thickness:8, eraser:false)
        let two = PaintStroke(points: [PaintPoint(x:0.3,y:0.4)], paletteIndex:2,
                              thickness:15, eraser:true)
        XCTAssertFalse(doc.canUndo)
        doc.append(one)
        doc.append(two)
        XCTAssertEqual(doc.strokes.count, 2)
        doc.undo()
        XCTAssertEqual(doc.strokes, [one])
        XCTAssertTrue(doc.canRedo)
        doc.redo()
        XCTAssertEqual(doc.strokes, [one,two])
        doc.clear()
        XCTAssertEqual(doc.strokes.count,0)
        doc.undo()
        XCTAssertEqual(doc.strokes.count,0)
        doc.redo()
        XCTAssertEqual(doc.strokes, [one])
        doc.redo()
        XCTAssertEqual(doc.strokes, [one,two])
        doc.undo()
        doc.append(two)
        XCTAssertFalse(doc.canRedo, "New paint stroke must invalidate redo history")
    }

    func testPaintExportRendersOpaqueWhiteAndColorPixels() throws {
        let empty = PaintDocument.render([], size: CGSize(width:100,height:100), scale:1)
        let cg = try XCTUnwrap(empty.cgImage)
        XCTAssertEqual(cg.width, 100)
        XCTAssertEqual(cg.height, 100)
        let white = try pixels(empty)
        XCTAssertEqual(white[0],255)
        XCTAssertEqual(white[1],255)
        XCTAssertEqual(white[2],255)

        let red = PaintStroke(points: [PaintPoint(x:0.1,y:0.5),PaintPoint(x:0.9,y:0.5)],
                              paletteIndex:2, thickness:16, eraser:false)
        let painted = PaintDocument.render([red], size:CGSize(width:100,height:100), scale:1)
        let bytes = try pixels(painted)
        let center = (50*100+50)*4
        XCTAssertGreaterThan(bytes[center],bytes[center+1])
        XCTAssertLessThan(bytes[center+1],240)
        let erase = PaintStroke(points:[PaintPoint(x:0.5,y:0.5)], paletteIndex:0,
                                thickness:20, eraser:true)
        let corrected = PaintDocument.render([red,erase],size:CGSize(width:100,height:100),scale:1)
        let correctedBytes = try pixels(corrected)
        XCTAssertEqual(correctedBytes[center],255)
        XCTAssertEqual(correctedBytes[center+1],255)
        XCTAssertEqual(correctedBytes[center+2],255)
    }

    func testAsteroidsSweptProjectileCollision() {
        // A projectile moves from left to right across a small rock in one frame.
        XCTAssertTrue(AsteroidsArcadeScene.segmentIntersectsCircle(
            CGPoint(x:0,y:0), CGPoint(x:100,y:0),
            center:CGPoint(x:50,y:3), radius:6))
        XCTAssertFalse(AsteroidsArcadeScene.segmentIntersectsCircle(
            CGPoint(x:0,y:0), CGPoint(x:100,y:0),
            center:CGPoint(x:50,y:20), radius:6))
        XCTAssertTrue(AsteroidsArcadeScene.segmentIntersectsCircle(
            CGPoint(x:2,y:2), CGPoint(x:2,y:2),
            center:CGPoint(x:3,y:2), radius:2))
    }

    func testAsteroidsElasticImpulseConservesMomentum() {
        let a = CGVector(dx:130,dy:0), b = CGVector(dx:-10,dy:0)
        let ma:CGFloat = 27, mb:CGFloat = 8
        let (afterA, afterB) = AsteroidsArcadeScene.elasticImpulse(
            a,b,massA:ma,massB:mb,normal:CGVector(dx:1,dy:0))
        XCTAssertEqual(ma*a.dx + mb*b.dx, ma*afterA.dx + mb*afterB.dx, accuracy:0.001)
        XCTAssertLessThan(afterA.dx, a.dx)
        XCTAssertGreaterThan(afterB.dx, b.dx)
        let initialEnergy = ma*a.dx*a.dx + mb*b.dx*b.dx
        let finalEnergy = ma*afterA.dx*afterA.dx + mb*afterB.dx*afterB.dx
        XCTAssertLessThanOrEqual(finalEnergy, initialEnergy + 0.01)
        let separating = AsteroidsArcadeScene.elasticImpulse(
            CGVector(dx:-10,dy:0),CGVector(dx:10,dy:0),
            massA:ma,massB:mb,normal:CGVector(dx:1,dy:0))
        XCTAssertEqual(separating.0.dx,-10)
        XCTAssertEqual(separating.1.dx,10)
    }

    func testAsteroidsSceneRestartAndWave() {
        let scene = AsteroidsArcadeScene(size:CGSize(width:390,height:620))
        let view = SKView(frame:CGRect(x:0,y:0,width:390,height:620))
        view.presentScene(scene)
        XCTAssertEqual(scene.lives,3)
        XCTAssertEqual(scene.wave,1)
        XCTAssertFalse(scene.isGameOver)
        scene.activateBoost()
        XCTAssertEqual(scene.boostCooldown,6)
        scene.restart()
        XCTAssertEqual(scene.boostCooldown,0)
        XCTAssertEqual(scene.lives,3)
    }

    func testGLBWithEmbeddedTextureAndNodeAnimation() throws {
        // Embedded 1px PNG, UVs, metallic-roughness material, triangle mesh and glTF rotation clip.
        let data = try XCTUnwrap(Data(base64Encoded: "Z2xURgIAAACwBgAAtAUAAEpTT057ImFzc2V0Ijp7InZlcnNpb24iOiIyLjAiLCJnZW5lcmF0b3IiOiJTaGFkZXJMYWJUZXN0In0sImJ1ZmZlcnMiOlt7ImJ5dGVMZW5ndGgiOjIyNH1dLCJidWZmZXJWaWV3cyI6W3siYnVmZmVyIjowLCJieXRlT2Zmc2V0IjowLCJieXRlTGVuZ3RoIjozNiwidGFyZ2V0IjozNDk2Mn0seyJidWZmZXIiOjAsImJ5dGVPZmZzZXQiOjM2LCJieXRlTGVuZ3RoIjozNiwidGFyZ2V0IjozNDk2Mn0seyJidWZmZXIiOjAsImJ5dGVPZmZzZXQiOjcyLCJieXRlTGVuZ3RoIjoyNCwidGFyZ2V0IjozNDk2Mn0seyJidWZmZXIiOjAsImJ5dGVPZmZzZXQiOjk2LCJieXRlTGVuZ3RoIjo2LCJ0YXJnZXQiOjM0OTYzfSx7ImJ1ZmZlciI6MCwiYnl0ZU9mZnNldCI6MTA0LCJieXRlTGVuZ3RoIjo4fSx7ImJ1ZmZlciI6MCwiYnl0ZU9mZnNldCI6MTEyLCJieXRlTGVuZ3RoIjozMn0seyJidWZmZXIiOjAsImJ5dGVPZmZzZXQiOjE0NCwiYnl0ZUxlbmd0aCI6Nzd9XSwiYWNjZXNzb3JzIjpbeyJidWZmZXJWaWV3IjowLCJjb21wb25lbnRUeXBlIjo1MTI2LCJjb3VudCI6MywidHlwZSI6IlZFQzMiLCJtaW4iOlstMC41LDAsMF0sIm1heCI6WzAuNSwxLDBdfSx7ImJ1ZmZlclZpZXciOjEsImNvbXBvbmVudFR5cGUiOjUxMjYsImNvdW50IjozLCJ0eXBlIjoiVkVDMyJ9LHsiYnVmZmVyVmlldyI6MiwiY29tcG9uZW50VHlwZSI6NTEyNiwiY291bnQiOjMsInR5cGUiOiJWRUMyIn0seyJidWZmZXJWaWV3IjozLCJjb21wb25lbnRUeXBlIjo1MTIzLCJjb3VudCI6MywidHlwZSI6IlNDQUxBUiJ9LHsiYnVmZmVyVmlldyI6NCwiY29tcG9uZW50VHlwZSI6NTEyNiwiY291bnQiOjIsInR5cGUiOiJTQ0FMQVIiLCJtaW4iOlswXSwibWF4IjpbMV19LHsiYnVmZmVyVmlldyI6NSwiY29tcG9uZW50VHlwZSI6NTEyNiwiY291bnQiOjIsInR5cGUiOiJWRUM0In1dLCJpbWFnZXMiOlt7ImJ1ZmZlclZpZXciOjYsIm1pbWVUeXBlIjoiaW1hZ2UvcG5nIn1dLCJ0ZXh0dXJlcyI6W3sic291cmNlIjowfV0sIm1hdGVyaWFscyI6W3sicGJyTWV0YWxsaWNSb3VnaG5lc3MiOnsiYmFzZUNvbG9yVGV4dHVyZSI6eyJpbmRleCI6MH0sIm1ldGFsbGljRmFjdG9yIjowLjYsInJvdWdobmVzc0ZhY3RvciI6MC4yfX1dLCJtZXNoZXMiOlt7InByaW1pdGl2ZXMiOlt7ImF0dHJpYnV0ZXMiOnsiUE9TSVRJT04iOjAsIk5PUk1BTCI6MSwiVEVYQ09PUkRfMCI6Mn0sImluZGljZXMiOjMsIm1hdGVyaWFsIjowfV19XSwibm9kZXMiOlt7Im5hbWUiOiJBbmltYXRlZFRyaWFuZ2xlIiwibWVzaCI6MH1dLCJzY2VuZXMiOlt7Im5vZGVzIjpbMF19XSwic2NlbmUiOjAsImFuaW1hdGlvbnMiOlt7Im5hbWUiOiJzcGluIiwiY2hhbm5lbHMiOlt7InNhbXBsZXIiOjAsInRhcmdldCI6eyJub2RlIjowLCJwYXRoIjoicm90YXRpb24ifX1dLCJzYW1wbGVycyI6W3siaW5wdXQiOjQsIm91dHB1dCI6NSwiaW50ZXJwb2xhdGlvbiI6IkxJTkVBUiJ9XX1dfeAAAABCSU4AAAAAvwAAAAAAAAAAAAAAPwAAAAAAAAAAAAAAAAAAgD8AAAAAAAAAAAAAAAAAAIA/AAAAAAAAAAAAAIA/AAAAAAAAAAAAAIA/AAAAAAAAAAAAAIA/AAAAAAAAAD8AAIA/AAABAAIAAAAAAAAAAACAPwAAAAAAAAAAAAAAAAAAgD8AAAAAAAAAAPMENT/zBDU/iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFElEQVR4nGPcF2Dzn4GBgYGJAQoAI0oCTQRZC54AAAAASUVORK5CYIIAAAA="))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shaderlab-animation-texture-test.glb")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let ready = expectation(description: "GLTFKit2 parses animated textured GLB")
        GLBSceneLoader.load(from: url) { result in
            switch result {
            case .success(let asset):
                XCTAssertEqual(asset.animations.count, 1)
                var materials: [SCNMaterial] = []
                asset.root.enumerateChildNodes { node, _ in
                    if let material = node.geometry?.firstMaterial { materials.append(material) }
                }
                XCTAssertFalse(materials.isEmpty, "GLB must have a visible mesh")
                XCTAssertNotNil(materials.first?.diffuse.contents, "Embedded texture/material missing")
            case .failure(let error):
                XCTFail("GLB import failed: \(error)")
            }
            ready.fulfill()
        }
        wait(for: [ready], timeout: 25)
    }

    func testAllShapesAndNativeLightingModels() throws {
        XCTAssertEqual(Shape3D.allCases.count, 9)
        XCTAssertEqual(Shading3D.allCases.count, 5)
        XCTAssertEqual(Set(Shading3D.allCases.map { $0.lighting.rawValue }).count, 5)
        for shape in Shape3D.allCases where shape != .imported {
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
        for (i, shape) in Shape3D.allCases.enumerated() where shape != .imported {
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
