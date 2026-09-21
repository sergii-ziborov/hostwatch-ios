import SceneKit
import simd

enum TopologyCamera {
    static let minPitch: Float = 0.22
    static let maxPitch: Float = 1.12
    static let minDistance: Float = 5.2
    static let maxDistance: Float = 42

    struct Pose {
        var target: SCNVector3
        var yaw: Float = 0.55
        var pitch: Float = 0.62
        var distance: Float
    }

    static func clamp(_ pose: Pose) -> Pose {
        var next = pose
        next.pitch = min(maxPitch, max(minPitch, next.pitch))
        next.distance = min(maxDistance, max(minDistance, next.distance))
        return next
    }

    static func eye(of pose: Pose) -> SCNVector3 {
        let held = clamp(pose)
        return SCNVector3(
            held.target.x + held.distance * cos(held.pitch) * sin(held.yaw),
            held.target.y + held.distance * sin(held.pitch),
            held.target.z + held.distance * cos(held.pitch) * cos(held.yaw)
        )
    }

    /// Orbit pose → camera transform. World up stays +Y; pitch is clamped so the basis never flips.
    static func apply(_ camera: SCNNode, pose: Pose) {
        let held = clamp(pose)
        let from = eye(of: held)
        camera.simdTransform = basis(eye: from, target: held.target)
    }

    static func basis(eye: SCNVector3, target: SCNVector3) -> simd_float4x4 {
        let from = SIMD3<Float>(eye.x, eye.y, eye.z)
        let dest = SIMD3<Float>(target.x, target.y, target.z)
        var forward = dest - from
        let length = simd_length(forward)
        guard length > 0.0001 else { return matrix_identity_float4x4 }
        forward /= length
        var up = SIMD3<Float>(0, 1, 0)
        up = simd_normalize(up - forward * simd_dot(up, forward))
        let right = simd_normalize(simd_cross(forward, up))
        up = simd_cross(right, forward)
        return simd_float4x4(
            SIMD4<Float>(right.x, right.y, right.z, 0),
            SIMD4<Float>(up.x, up.y, up.z, 0),
            SIMD4<Float>(-forward.x, -forward.y, -forward.z, 0),
            SIMD4<Float>(from.x, from.y, from.z, 1)
        )
    }

    static func basisUpY(of pose: Pose) -> Float {
        let held = clamp(pose)
        return basis(eye: eye(of: held), target: held.target).columns.1.y
    }

    static func capture(eye: SCNVector3, target: SCNVector3) -> Pose {
        let dx = eye.x - target.x, dy = eye.y - target.y, dz = eye.z - target.z
        let distance = max(minDistance, sqrt(dx * dx + dy * dy + dz * dz))
        return clamp(Pose(
            target: target,
            yaw: atan2(dx, dz),
            pitch: asin(max(-1, min(1, dy / distance))),
            distance: distance
        ))
    }

    /// Keep the selected tower on the left and reserve the right side for its callouts.
    static func lock(base: SCNVector3, height: Float, aspect: Float = 0.65) -> Pose {
        let yaw: Float = 0.52
        let distance = max(7.5, height * 1.45)
        let halfWidth = distance * tan(52 * Float.pi / 360) * max(0.45, aspect)
        let shift = halfWidth * 0.42
        let look = SCNVector3(base.x + cos(yaw) * shift,
                              max(0.7, height * 0.52),
                              base.z - sin(yaw) * shift)
        return Pose(target: look, yaw: yaw, pitch: 0.55, distance: distance)
    }

    static func pan(_ pose: inout Pose, translation: CGPoint, in size: CGSize) {
        let scale = pose.distance * 0.0024
        let yaw = pose.yaw
        let right = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
        let forward = SIMD3<Float>(sin(yaw), 0, cos(yaw))
        pose.target.x -= Float(translation.x) * scale * right.x + Float(translation.y) * scale * forward.x
        pose.target.z -= Float(translation.x) * scale * right.z + Float(translation.y) * scale * forward.z
        _ = size
    }
}
