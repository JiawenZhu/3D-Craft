import SceneKit

/// Physical display furniture. Model normalization puts the feet at y = 0;
/// both the stage top and the contact shadow use that same world-space plane.
enum CraftDisplayStage {
    static let height: CGFloat = 0.11

    static func make(size: SIMD3<Float>) -> SCNNode {
        let root = SCNNode()
        root.name = "displayStage"
        let radius = CGFloat(CraftCameraFraming.platformRadius(size: size))
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(white: 0.94, alpha: 1)
        material.roughness.contents = 0.72
        material.metalness.contents = 0.05
        let cylinder = SCNCylinder(radius: radius, height: height)
        cylinder.radialSegmentCount = 128
        cylinder.materials = [material]
        let plinth = SCNNode(geometry: cylinder)
        plinth.name = "plinth"
        plinth.position.y = -Float(height / 2)
        root.addChildNode(plinth)

        // A fine inset edge, below the top surface, rather than another disc.
        let edge = SCNTorus(ringRadius: radius + 0.002, pipeRadius: 0.006)
        edge.ringSegmentCount = 128
        edge.pipeSegmentCount = 8
        let edgeMaterial = SCNMaterial()
        edgeMaterial.lightingModel = .physicallyBased
        edgeMaterial.roughness.contents = 0.45
        edge.materials = [edgeMaterial]
        let rim = SCNNode(geometry: edge)
        rim.name = "rim"
        rim.position.y = -0.018
        root.addChildNode(rim)
        return root
    }
}
