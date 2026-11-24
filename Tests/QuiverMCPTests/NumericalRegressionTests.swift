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


import Testing
@testable import QuiverMCP

struct NumericalRegressionTests {
    @Test func regressionIsStableForLargeOffsets() throws {
        let features = [1e9, 1e9 + 1.0, 1e9 + 2.0]
        let result = try _QuiverCalculation.fitLinearRegression.calculate(arguments: [
            "features": features, "targets": [1, 2, 3], "predict": features
        ])
        #expect(result["intercept"] as? Double == -999_999_999.0)
        #expect(result["slope"] as? Double == 1.0)
        #expect(result["predictions"] as? [Double] == [1.0, 2.0, 3.0])
    }

    @Test(arguments: [1e-8, 1e200, 1e-200])
    func regressionPreservesUnitsAcrossScales(_ scale: Double) throws {
        let result = try _QuiverCalculation.fitLinearRegression.calculate(arguments: [
            "features": [scale, 2.0 * scale], "targets": [1, 2], "predict": [3.0 * scale]
        ])
        let slope = try #require(result["slope"] as? Double)
        let intercept = try #require(result["intercept"] as? Double)
        let prediction = try #require((result["predictions"] as? [Double])?.first)
        #expect(abs(slope * scale - 1.0) < 1e-14)
        #expect(abs(intercept) < 1e-14)
        #expect(abs(prediction - 3.0) < 1e-14)
    }

    @Test func summaryPreservesCancellationAndMaximumValues() throws {
        let cancellation = try _QuiverCalculation.vectorSummary.calculate(arguments: [
            "values": [1e16, 1.0, -1e16]
        ])
        #expect(cancellation["mean"] as? Double == 1.0 / 3.0)

        let maximum = Double.greatestFiniteMagnitude
        let identical = try _QuiverCalculation.vectorSummary.calculate(arguments: ["values": [maximum, maximum]])
        for field in ["mean", "firstQuartile", "median", "thirdQuartile", "minimum", "maximum"] {
            #expect(identical[field] as? Double == maximum)
        }
        #expect(identical["sampleStandardDeviation"] as? Double == 0.0)
    }

    @Test func summaryAvoidsIntermediateOverflowAndUnderflow() throws {
        let large = try _QuiverCalculation.vectorSummary.calculate(arguments: ["values": [-1e200, 1e200]])
        let deviation = try #require(large["sampleStandardDeviation"] as? Double)
        #expect(abs(deviation / 1e200 - 2.0.squareRoot()) < 1e-14)
        #expect(large["median"] as? Double == 0.0)
        #expect(large["firstQuartile"] as? Double == -5e199)
        #expect(large["thirdQuartile"] as? Double == 5e199)

        let small = try _QuiverCalculation.vectorSummary.calculate(arguments: [
            "values": [0.0, Double.leastNonzeroMagnitude]
        ])
        #expect(small["sampleStandardDeviation"] as? Double == Double.leastNonzeroMagnitude)
    }

    @Test func cosineStaysInItsMathematicalRange() throws {
        let positive = try _QuiverCalculation.cosineSimilarity.calculate(arguments: ["left": [1, 1, 1], "right": [1, 1, 1]])
        let negative = try _QuiverCalculation.cosineSimilarity.calculate(arguments: ["left": [1, 1, 1], "right": [-1, -1, -1]])
        #expect(positive["similarity"] as? Double == 1.0)
        #expect(negative["similarity"] as? Double == -1.0)
    }
}
