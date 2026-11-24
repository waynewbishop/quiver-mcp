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
import Testing
@testable import QuiverMCP

struct AnalysisTests {
    @Test func correlationUsesColumnsAndReturnsNullForConstantColumns() throws {
        let result = try _QuiverCalculation.correlationMatrix.calculate(arguments: [
            "rows": [[1, 4, 7], [2, 3, 7], [3, 2, 7], [4, 1, 7]]
        ])
        let matrix = try #require(result["matrix"] as? [[Any]])
        #expect(matrix.count == 3)
        #expect(abs((try #require(matrix[0][1] as? Double)) + 1) < 1e-12)
        #expect(matrix[0][2] is NSNull)
        #expect(matrix[2][2] is NSNull)
    }

    @Test func histogramRejectsUnsafeWidthsAndAllocations() throws {
        #expect(throws: _CalculationError.self) {
            try _QuiverCalculation.histogram.calculate(arguments: ["values": [0.0, Double.leastNonzeroMagnitude], "bins": 2])
        }
        #expect(throws: _CalculationError.self) {
            try _QuiverCalculation.histogram.calculate(arguments: [
                "values": [0.0, 1.0, 2.0, 3.0, 1e100], "rule": "freedman_diaconis"
            ])
        }
        let normal = try _QuiverCalculation.histogram.calculate(arguments: ["values": [0, 1, 2, 3], "bins": 2])
        let bins = try #require(normal["bins"] as? [[String: Any]])
        #expect(bins.compactMap { $0["count"] as? Int } == [2, 2])
    }

    @Test func regressionInferenceUsesPositiveResidualDegreesOfFreedom() throws {
        let result = try _QuiverCalculation.summarizeRegression.calculate(arguments: [
            "features": [[1], [2], [3], [4]], "targets": [2, 3, 5, 6]
        ])
        #expect(result["degreesOfFreedom"] as? Int == 2)
        #expect((result["pValues"] as? [Double])?.count == 2)
        #expect(throws: _CalculationError.self) {
            try _QuiverCalculation.summarizeRegression.calculate(arguments: [
                "features": [[1], [2]], "targets": [2, 3]
            ])
        }
    }

    @Test func samplingIsSeededAndBounded() throws {
        let input: [String: Any] = ["values": [1, 2, 3, 4], "statistic": "median", "seed": 42, "iterations": 8]
        let first = try _QuiverCalculation.estimateSamplingDistribution.calculate(arguments: input)
        let second = try _QuiverCalculation.estimateSamplingDistribution.calculate(arguments: input)
        #expect((first["replicates"] as? [Double])?.count == 8)
        #expect(first["replicates"] as? [Double] == second["replicates"] as? [Double])
        #expect(throws: _CalculationError.self) {
            try _QuiverCalculation.estimateSamplingDistribution.calculate(arguments: [
                "values": [1, 2], "statistic": "mean", "seed": 42, "iterations": 10_000, "sampleSize": 10_000
            ])
        }
    }
}
