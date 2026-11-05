import Foundation
import SceneKit
import GLTFKit2

/// One imported scene. Keep GLTFKit2's original root hierarchy intact: its
/// animation key paths are relative to that root, not to our preview container.
final class GLBSceneLoader {
    struct Loaded {
        let root: SCNNode
        let animationTarget: SCNNode
        let animations: [GLTFSCNAnimation]
        let filename: String
        let meshCount: Int
    }

    /// Bounds in glTF scene coordinates, including nested nodes and transforms.
    /// A container's own boundingBox must not be used as a substitute for all meshes.
    static func geometryBounds(in sourceRoot: SCNNode) -> (SCNVector3, SCNVector3, Int)? {
        var minimum = SCNVector3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var maximum = SCNVector3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
        var count = 0
        func visit(_ node: SCNNode) {
            if let geometry = node.geometry {
                let (low, high) = geometry.boundingBox
                for x in [low.x, high.x] {
                    for y in [low.y, high.y] {
                        for z in [low.z, high.z] {
                            let position = node.convertPosition(SCNVector3(x, y, z), to: sourceRoot)
                            guard position.x.isFinite && position.y.isFinite && position.z.isFinite else { continue }
                            minimum.x = min(minimum.x, position.x)
                            minimum.y = min(minimum.y, position.y)
                            minimum.z = min(minimum.z, position.z)
                            maximum.x = max(maximum.x, position.x)
                            maximum.y = max(maximum.y, position.y)
                            maximum.z = max(maximum.z, position.z)
                        }
                    }
                }
                count += 1
            }
            for child in node.childNodes { visit(child) }
        }
        visit(sourceRoot)
        guard count > 0, minimum.x <= maximum.x, minimum.y <= maximum.y, minimum.z <= maximum.z else { return nil }
        return (minimum, maximum, count)
    }

    static func load(from url: URL, completion: @escaping (Result<Loaded, Error>) -> Void) {
        GLTFAsset.load(with: url, options: [:]) { _, status, maybeAsset, maybeError, _ in
            if status == .complete, let asset = maybeAsset {
                // SceneKit's node graph is created and configured on the main thread.
                DispatchQueue.main.async {
                    let source = GLTFSCNSceneSource(asset: asset)
                    guard let scene = source.defaultScene else {
                        completion(.failure(NSError(domain: "GLBSceneLoader", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Brak sceny w pliku GLB."])))
                        return
                    }
                    let gltfRoot = scene.rootNode
                    guard let (lo, hi, meshCount) = geometryBounds(in: gltfRoot) else {
                        completion(.failure(NSError(domain: "GLBSceneLoader", code: 3,
                            userInfo: [NSLocalizedDescriptionKey: "Model GLB nie zawiera widocznej geometrii."])))
                        return
                    }
                    let center = SCNVector3((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5, (lo.z + hi.z) * 0.5)
                    let span = max(hi.x - lo.x, max(hi.y - lo.y, hi.z - lo.z))
                    let fitScale: Float = span > 0.00001 ? 2.0 / span : 1
                    let pivot = SCNNode()
                    pivot.name = "gltf-preview-pivot"
                    let fitted = SCNNode()
                    fitted.name = "gltf-preview-fit"
                    fitted.scale = SCNVector3(fitScale, fitScale, fitScale)
                    fitted.position = SCNVector3(-center.x * fitScale, -center.y * fitScale, -center.z * fitScale)
                    // Never detach glTF children one by one; animation target paths,
                    // skeleton relationships and source transforms must remain intact.
                    fitted.addChildNode(gltfRoot)
                    pivot.addChildNode(fitted)
                    completion(.success(Loaded(root: pivot, animationTarget: gltfRoot,
                                               animations: source.animations,
                                               filename: url.lastPathComponent, meshCount: meshCount)))
                }
            } else if status == .error {
                DispatchQueue.main.async {
                    completion(.failure(maybeError ?? NSError(domain: "GLBSceneLoader", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Nie udało się załadować GLB."])))
                }
            }
        }
    }
}
