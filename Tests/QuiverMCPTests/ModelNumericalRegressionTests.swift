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

struct ModelNumericalRegressionTests {
    @Test func knnPreservesDistancesWhenSquaresWouldOverflow() throws {
        let result = try _QuiverCalculation.classifyWithKNN.calculate(arguments: [
            "features": [[-1e200], [1e200]], "labels": [0, 1], "k": 1, "predict": [[9e199]]
        ])
        #expect(result["predictedLabels"] as? [Int] == [1])
    }

    @Test(arguments: [false, true])
    func pipelineClassifiesAFarQueryWithoutOverflow(_ usePCA: Bool) throws {
        let maximum = Double.greatestFiniteMagnitude
        var arguments: [String: Any] = [
            "features": [[0.0], [1.0]], "labels": [0, 1], "k": 1,
            "predict": [[maximum], [-maximum]]
        ]
        if usePCA { arguments["componentCount"] = 1 }
        let result = try _QuiverCalculation.fitKNNPipeline.calculate(arguments: arguments)
        #expect(result["predictedLabels"] as? [Int] == [1, 0])
    }

    @Test func kmeansPreservesCentroidUnitsAndQueryOrder() throws {
        let result = try _QuiverCalculation.fitKMeans.calculate(arguments: [
            "features": [[-1e200], [1e200]], "k": 2, "seed": 0, "predict": [[9e199]]
        ])
        #expect(result["centroids"] as? [[Double]] == [[-1e200], [1e200]])
        #expect(result["assignments"] as? [Int] == [0, 1])
        #expect(result["predictedAssignments"] as? [Int] == [1])
        #expect(result["inertia"] as? Double == 0.0)
    }

    @Test func gaussianUsesBothDensitiesForMaximumFiniteClasses() throws {
        let maximum = Double.greatestFiniteMagnitude
        let result = try _QuiverCalculation.fitGaussianNaiveBayes.calculate(arguments: [
            "features": [[-maximum], [-maximum], [maximum], [maximum]],
            "labels": [0, 0, 1, 1], "predict": [[-maximum], [maximum]]
        ])
        #expect(result["classLabels"] as? [Int] == [0, 1])
        #expect(result["predictedLabels"] as? [Int] == [0, 1])
        #expect(result["probabilities"] as? [[Double]] == [[1.0, 0.0], [0.0, 1.0]])
    }

    @Test func gaussianRejectsAQueryWithNoRepresentableClassLikelihood() {
        let maximum = Double.greatestFiniteMagnitude
        #expect(throws: _CalculationError.self) {
            _ = try _QuiverCalculation.fitGaussianNaiveBayes.calculate(arguments: [
                "features": [[-maximum], [-maximum], [maximum], [maximum]],
                "labels": [0, 0, 1, 1], "predict": [[0.0]]
            ])
        }
    }

    @Test func pipelineRejectsUnrepresentableMultidimensionalTransforms() {
        #expect(throws: _CalculationError.self) {
            _ = try _QuiverCalculation.fitKNNPipeline.calculate(arguments: [
                "features": [[0.0, 0.0], [1.0, 1.0]], "labels": [0, 1], "k": 1,
                "predict": [[Double.greatestFiniteMagnitude, 0.0]]
            ])
        }
    }

    @Test func knnRejectsRoundedTiesAndPreservesActualTies() throws {
        #expect(throws: _CalculationError.self) {
            _ = try _QuiverCalculation.classifyWithKNN.calculate(arguments: [
                "features": [[0.0, 0.0], [0.0, 1.0]], "labels": [0, 1], "k": 1,
                "predict": [[1e100, 0.9]]
            ])
        }
        let result = try _QuiverCalculation.classifyWithKNN.calculate(arguments: [
            "features": [[3.0, 4.0], [0.0, 5.0]], "labels": [0, 1], "k": 1,
            "predict": [[0.0, 0.0]]
        ])
        #expect(result["predictedLabels"] as? [Int] == [0])
    }

    @Test func residualAnalysisUsesTheStableScalarFit() throws {
        let result = try _QuiverCalculation.analyzeResiduals.calculate(arguments: [
            "features": [[1e9], [1e9 + 1.0], [1e9 + 2.0]], "targets": [1, 2, 3],
            "observedFeatures": [[1e9 + 3.0], [1e9 + 4.0]], "observedTargets": [5, 3]
        ])
        #expect(result["coefficients"] as? [Double] == [-999_999_999.0, 1.0])
        #expect(result["predictions"] as? [Double] == [4.0, 5.0])
        #expect(result["residuals"] as? [Double] == [1.0, -2.0])
    }
}
