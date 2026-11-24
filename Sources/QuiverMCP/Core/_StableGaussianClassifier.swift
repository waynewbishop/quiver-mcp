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

/// Scores Gaussian classes with scaled population moments and Quiver's standard normal density.
enum _StableGaussianClassifier {
    /// Fits class statistics and returns labels and probabilities for the requested rows.
    static func classify(features: [[Double]], labels: [Int], queries: [[Double]]) throws -> [String: Any] {
        var groups: [Int: [[Double]]] = [:]
        for (label, row) in zip(labels, features) {
            groups[label, default: []].append(row)
        }
        let classLabels = groups.keys.sorted()
        let classes = try classLabels.map { label in
            try fitClass(groups[label, default: []], totalCount: features.count)
        }

        var probabilities: [[Double]] = []
        var predictedLabels: [Int] = []
        for query in queries {
            let scores = classes.map { $0.score(query) }
            guard let best = scores.indices.max(by: { scores[$0] < scores[$1] }),
                  scores[best].isFinite else {
                throw _CalculationError(message: "All Gaussian class likelihoods are outside the representable range.")
            }
            predictedLabels.append(classLabels[best])
            probabilities.append((scores - scores[best]).softMax())
        }
        return ["predictedLabels": predictedLabels, "classLabels": classLabels, "probabilities": probabilities]
    }

    /// Fits a class while preserving Quiver's population-variance convention and variance floor.
    private static func fitClass(_ rows: [[Double]], totalCount: Int) throws -> ClassMoments {
        var means: [Double] = []
        var deviations: [Double] = []
        for column in rows.transposed() {
            let moments = _StableStatistics.moments(column, degreesOfFreedom: 0)
            guard moments.mean.isFinite, moments.standardDeviation.isFinite else {
                throw _CalculationError(message: "The Gaussian class statistics exceed the finite range.")
            }
            means.append(moments.mean)
            deviations.append(max(1e-9.squareRoot(), moments.standardDeviation))
        }
        return ClassMoments(logPrior: log(Double(rows.count) / Double(totalCount)),
                            means: means, deviations: deviations)
    }

    /// Holds the class prior and the Gaussian parameters for its features.
    private struct ClassMoments {
        let logPrior: Double
        let means: [Double]
        let deviations: [Double]

        /// Scores a query, retaining a vanishing density as negative infinity.
        func score(_ query: [Double]) -> Double {
            var score = logPrior
            for index in query.indices {
                let value = query[index]
                let mean = means[index]
                let deviation = deviations[index]
                let difference = value - mean
                let standardized = difference.isFinite ? difference / deviation
                    : value / deviation - mean / deviation
                guard let logDensity = Distributions.normal.logPDF(
                    x: standardized, mean: 0.0, standardDeviation: 1.0
                ) else {
                    return -.infinity
                }
                score += logDensity - log(deviation)
            }
            return score
        }
    }
}
