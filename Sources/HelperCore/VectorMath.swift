import Accelerate
import Foundation

public enum VectorMath {
    public static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let dot = vDSP.dot(a, b)
        let na = sqrt(vDSP.sumOfSquares(a))
        let nb = sqrt(vDSP.sumOfSquares(b))
        return na == 0 || nb == 0 ? 0 : dot / (na * nb)
    }
}
