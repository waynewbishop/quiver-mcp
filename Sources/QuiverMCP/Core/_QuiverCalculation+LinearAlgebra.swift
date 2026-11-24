// Copyright 2026 Wayne W Bishop. All rights reserved.
//
//
// Licensed under the Apache License, Version 2.0 (the "License"); you may not use this
// file except in compliance with the License. You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software distributed under
// the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF
// ANY KIND, either express or implied. See the License for the specific language governing
// permissions and limitations under the License.

import Foundation
import Quiver

extension _QuiverCalculation {
    /// Evaluates a vector or matrix operation with Quiver.
    /// - Parameter input: The numeric arguments from the MCP request.
    /// - Returns: The scalar, vector, or matrix result.
    /// - Throws: A calculation error for incompatible shapes or a singular inverse.
    func calculateLinearAlgebra(_ input: _CalculationInput) throws -> [String: Any] {
        switch self {
        case .dotProduct, .euclideanDistance:
            let left = try input.vector("left")
            let right = try input.targets("right", count: left.count)
            if self == .dotProduct { return ["dotProduct": left.dot(right)] }

            let difference = left.subtract(right)
            return ["distance": Self.vectorMagnitude(difference)]
        case .vectorMagnitude:
            return ["magnitude": Self.vectorMagnitude(try input.vector("vector"))]
        case .normalizeVector:
            return ["vector": Self.scaledVector(try input.vector("vector")).values.normalized]
        case .projectVector:
            let vector = try input.vector("vector")
            let direction = try input.targets("onto", count: vector.count)
            let unitDirection = Self.scaledVector(direction).values.normalized
            let projection = vector.vectorProjection(onto: unitDirection)
            guard projection.allSatisfy({ $0.isFinite }) else {
                // The scalar projection can overflow even when its vector components fit.
                let scaled = Self.scaledVector(vector)
                return ["vector": scaled.values.vectorProjection(onto: unitDirection) * scaled.scale]
            }
            return ["vector": projection]
        case .multiplyMatrixVector:
            let matrix = try Self.boundedMatrix(input, "matrix")
            let vector = try input.targets("vector", count: matrix[0].count)
            // A [rows × columns] times v [columns] yields [rows].
            return ["vector": vector.transformedBy(matrix)]
        case .multiplyMatrices:
            let left = try Self.boundedMatrix(input, "left")
            let right = try Self.boundedMatrix(input, "right")
            try Self.require(left[0].count == right.count,
                             "The left column count must equal the right row count.")
            try Self.require(left.count <= 100_000 / right[0].count,
                             "The resulting matrix must contain at most 100,000 cells.")
            // A [rows × inner] times B [inner × columns] yields [rows × columns].
            return ["matrix": left.multiplyMatrix(right)]
        case .transposeMatrix:
            return ["matrix": try Self.boundedMatrix(input, "matrix").transposed()]
        case .invertMatrix, .matrixDeterminant:
            let matrix = try Self.boundedMatrix(input, "matrix")
            try Self.require(matrix.count == matrix[0].count, "matrix must be square.")
            if self == .matrixDeterminant { return ["determinant": matrix.determinant] }
            return ["matrix": try matrix.inverted()]
        default:
            throw _CalculationError(message: "Unsupported linear algebra operation.")
        }
    }

    /// Measures vector length after rescaling to keep the sum of squares representable.
    /// - Parameter vector: The vector to measure.
    /// - Returns: Its Euclidean length in the original units.
    private static func vectorMagnitude(_ vector: [Double]) -> Double {
        guard vector.allSatisfy({ $0.isFinite }) else { return .infinity }
        let scaled = scaledVector(vector)
        return scaled.values.magnitude * scaled.scale
    }

    /// Rescales a vector by its largest absolute component.
    /// - Parameter vector: The vector with finite components.
    /// - Returns: The scaled vector and the factor that recovers its original units.
    private static func scaledVector(_ vector: [Double]) -> (values: [Double], scale: Double) {
        let scale = vector.lazy.map { abs($0) }.max() ?? 0.0
        guard scale > 0.0 else { return (vector, 1.0) }
        return (vector / scale, scale)
    }
}
