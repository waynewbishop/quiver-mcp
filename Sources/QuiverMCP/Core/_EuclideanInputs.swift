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

import Quiver

/// Conditions Euclidean coordinates before passing them to the pinned Quiver kernels.
/// A common positive scale preserves geometry. Query transformations that overflow
/// or collapse distinct candidate distances are reported as calculation errors.
struct _EuclideanInputs {
    /// Training rows in bounded coordinates.
    let features: [[Double]]
    /// Query rows in the same coordinates.
    let queries: [[Double]]
    /// The power-of-two scale for restoring original units.
    let scale: Double

    /// Normalizes coordinates and verifies that distinct values survive the scaling.
    init(features: [[Double]], queries: [[Double]] = []) throws {
        let rows = features + queries
        var maximum = 0.0
        for row in rows {
            for value in row {
                guard value.isFinite else {
                    throw _CalculationError(message: "A transformed feature is outside the finite range.")
                }
                maximum = max(maximum, abs(value))
            }
        }
        let scale = _StableStatistics.powerOfTwo(for: maximum)
        let scaledFeatures = try Self.normalize(features, by: scale)
        let scaledQueries = try Self.normalize(queries, by: scale)
        try Self.validateTrainingResolution(scaledFeatures)
        for query in scaledQueries {
            try Self.validateDistances(from: query, to: scaledFeatures)
        }
        self.scale = scale
        self.features = scaledFeatures
        self.queries = scaledQueries
    }

    /// Clips one-dimensional queries outside the training interval to its boundary.
    /// The ordering of all distances is preserved along either ray.
    static func boundedQueries(_ queries: [[Double]], features: [[Double]]) -> [[Double]] {
        guard features[0].count == 1 else { return queries }
        let column = features.map { $0[0] }
        guard let minimum = column.min(), let maximum = column.max(), minimum < maximum else {
            return queries
        }
        var bounded: [[Double]] = []
        bounded.reserveCapacity(queries.count)
        for query in queries {
            bounded.append([min(maximum, max(minimum, query[0]))])
        }
        return bounded
    }

    /// Rejects a scale conversion when it would lose a feature value.
    private static func normalize(_ rows: [[Double]], by scale: Double) throws -> [[Double]] {
        var result: [[Double]] = []
        result.reserveCapacity(rows.count)
        for row in rows {
            let scaled = row / scale
            for column in row.indices where scaled[column] * scale != row[column] {
                throw _CalculationError(message: "The feature range is too wide to preserve Euclidean distances.")
            }
            result.append(scaled)
        }
        return result
    }

    /// Checks the smallest nonzero separation in each training column before fitting.
    private static func validateTrainingResolution(_ rows: [[Double]]) throws {
        for column in rows.transposed() {
            let sorted = column.sorted()
            for index in sorted.indices.dropFirst() {
                let delta = sorted[index] - sorted[index - 1]
                if delta != 0.0 && delta * delta == 0.0 {
                    throw _CalculationError(message: "A distinct training coordinate is too small for squared Euclidean distance.")
                }
            }
        }
    }

    /// Rejects squared distances when arithmetic erases a nonzero displacement.
    private static func validateDistances(from query: [Double], to features: [[Double]]) throws {
        var candidates: [Double: (row: [Double], delta: [Double])] = [:]
        for row in features {
            let delta = query.subtract(row)
            let distance = delta.dot(delta).squareRoot()
            if distance == 0.0 && query != row {
                throw _CalculationError(message: "A nonzero Euclidean distance underflowed.")
            }
            if let other = candidates[distance], other.row != row,
               delta == other.delta || Self.differenceOfSquares(delta, other.delta) != 0.0 {
                throw _CalculationError(message: "Distinct Euclidean distances rounded to the same value.")
            }
            candidates[distance] = (row, delta)
        }
    }

    /// Compares a rounded tie by cancelling shared squared terms before summing.
    private static func differenceOfSquares(_ left: [Double], _ right: [Double]) -> Double {
        let a = left.map(abs).sorted()
        let b = right.map(abs).sorted()
        var terms: [Double] = []
        terms.reserveCapacity(a.count)
        for index in a.indices {
            terms.append((a[index] - b[index]) * (a[index] + b[index]))
        }
        return _StableStatistics.compensatedSum(terms)
    }
}
