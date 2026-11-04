import Foundation
import SceneKit
import GLTFKit2

/// GLTFKit2 keeps glTF node hierarchy, PBR materials, embedded textures and animation channels.
final class GLBSceneLoader {
    struct Loaded {
        let root: SCNNode
        let animations: [GLTFSCNAnimation]
        let filename: String
    }

    static func load(from url: URL, completion: @escaping (Result<Loaded, Error>) -> Void) {
        GLTFAsset.load(with: url, options: [:]) { _, status, maybeAsset, maybeError, _ in
            if status == .complete, let asset = maybeAsset {
                let source = GLTFSCNSceneSource(asset: asset)
                guard let scene = source.defaultScene else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "GLBSceneLoader", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Brak sceny w pliku GLB."])))
                    }
                    return
                }
                let holder = SCNNode()
                holder.name = "imported-gltf-scene"
                for node in Array(scene.rootNode.childNodes) { holder.addChildNode(node) }
                // Transform the entire asset uniformly without rewriting skeleton or animation keyframes.
                let (lo, hi) = holder.boundingBox
                let center = SCNVector3((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5, (lo.z + hi.z) * 0.5)
                let span = max(hi.x-lo.x, max(hi.y-lo.y, hi.z-lo.z))
                let normalized = SCNNode()
                normalized.name = "gltf-pivot"
                let fitScale: Float = span > 0.00001 ? 2.0/span : 1
                holder.scale = SCNVector3(fitScale, fitScale, fitScale)
                holder.position = SCNVector3(-center.x * fitScale, -center.y * fitScale, -center.z * fitScale)
                normalized.addChildNode(holder)
                DispatchQueue.main.async {
                    completion(.success(Loaded(root: normalized, animations: source.animations,
                                               filename: url.lastPathComponent)))
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
