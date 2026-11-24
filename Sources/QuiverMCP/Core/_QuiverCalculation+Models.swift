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
    /// Fits a model or runs a workflow for the current request.
    /// - Parameter input: Validated argument keys with request-local values.
    /// - Returns: The model readouts and any requested predictions.
    func calculateModel(_ input: _CalculationInput) throws -> [String: Any] {
        switch self {
        case .fitRidgeRegression: return try Self.fitRidge(input)
        case .fitLogisticRegression: return try Self.fitLogistic(input)
        case .fitGaussianNaiveBayes: return try Self.fitNaiveBayes(input)
        case .fitBernoulliNaiveBayes: return try Self.fitBernoulliNaiveBayes(input)
        case .classifyWithKNN, .fitKNNPipeline: return try classify(input)
        case .fitKMeans: return try Self.fitClusters(input)
        case .fitPCA: return try Self.projectComponents(input)
        case .calculateTrueEffortScore: return try Self.scoreWorkout(input)
        case .fitGradientDescent: return try Self.fitGradient(input)
        case .analyzeResiduals: return try Self.residuals(input)
        default:
            throw _CalculationError(message: "The requested calculation does not fit a model.")
        }
    }

    /// Reads the shared optimization controls and validates Quiver's fitting domains.
    private static func optimization(_ input: _CalculationInput) throws
        -> (learningRate: Double, maxIterations: Int, tolerance: Double)
    {
        let learningRate = try input.number("learningRate", default: 0.01)
        let tolerance = try input.number("tolerance", default: 1.0e-6)
        guard learningRate > 0.0, tolerance > 0.0 else {
            throw _CalculationError(message: "learningRate and tolerance must be positive.")
        }
        return (learningRate, try input.integer("maxIterations", within: 1...10_000, default: 1_000), tolerance)
    }

    /// Fits Quiver ridge regression and returns its loss trace and optional predictions.
    private static func fitRidge(_ input: _CalculationInput) throws -> [String: Any] {
        let features = try input.matrix("features", minimumRows: 2)
        let targets = try input.targets(count: features.count)
        let predictions = try input.predictionRows(width: features[0].count)
        let lambda = try input.number("lambda")
        guard lambda >= 0.0 else {
            throw _CalculationError(message: "lambda must be nonnegative.")
        }
        let settings = try optimization(input)
        let model = try Ridge.fit(features: features, targets: targets, lambda: lambda,
                                  learningRate: settings.learningRate, maxIterations: settings.maxIterations,
                                  tolerance: settings.tolerance)
        var fields: [String: Any] = ["coefficients": model.coefficients, "lossHistory": model.lossHistory,
                                     "outcome": model.outcome.rawValue]
        if !predictions.isEmpty { fields["predictions"] = model.predict(predictions) }
        return fields
    }

    /// Fits a binary logistic classifier and reports class 1 probabilities for query rows.
    private static func fitLogistic(_ input: _CalculationInput) throws -> [String: Any] {
        let features = try input.matrix("features", minimumRows: 2)
        let labels = try input.labels(count: features.count)
        guard Set(labels) == [0, 1] else {
            throw _CalculationError(message: "Logistic regression requires both binary labels 0 and 1.")
        }
        let predictions = try input.predictionRows(width: features[0].count)
        let settings = try optimization(input)
        let model = try LogisticRegression.fit(features: features, labels: labels,
                                               learningRate: settings.learningRate, maxIterations: settings.maxIterations,
                                               tolerance: settings.tolerance)
        var fields: [String: Any] = ["coefficients": model.coefficients, "lossHistory": model.lossHistory,
                                     "outcome": model.outcome.rawValue]
        if !predictions.isEmpty {
            fields["predictedLabels"] = model.predict(predictions)
            fields["probabilityOfClassOne"] = model.predictProbabilities(predictions)
        }
        return fields
    }

    /// Fits Gaussian Naive Bayes and labels each probability column in the response.
    private static func fitNaiveBayes(_ input: _CalculationInput) throws -> [String: Any] {
        let features = try input.matrix("features")
        let labels = try input.labels(count: features.count)
        let predictions = try input.matrix("predict", width: features[0].count)
        return try _StableGaussianClassifier.classify(features: features, labels: labels, queries: predictions)
    }

    /// Fits Quiver's Bernoulli classifier and optionally predicts query rows.
    /// - Parameter input: Binary feature rows, integer labels, smoothing, and optional query rows.
    /// - Returns: Learned class statistics and optional predictions ordered by class label.
    /// - Throws: A calculation error for invalid binary inputs, shapes, or smoothing.
    private static func fitBernoulliNaiveBayes(_ input: _CalculationInput) throws -> [String: Any] {
        let features = try boundedMatrix(input, "features")
        let labels = try input.labels(count: features.count)
        let alpha = try input.number("alpha", default: 1.0)
        try require(alpha > 0.0 && (2.0 * alpha).isFinite,
                    "alpha must be positive and small enough to double without overflow.")
        try validateBernoulliFeatures(features, named: "features")

        let predictions = try input.contains("predict") ? boundedMatrix(input, "predict") : []
        if let first = predictions.first {
            try require(first.count == features[0].count, "predict must have the same column count as features.")
            try validateBernoulliFeatures(predictions, named: "predict")
        }

        let model = BernoulliNaiveBayes.fit(features: features, labels: labels, alpha: alpha)
        // Rounded endpoints make the logarithm of presence or absence undefined.
        try require(model.classes.allSatisfy { classStats in
            classStats.featureProbabilities.allSatisfy { $0 > 0.0 && $0 < 1.0 }
        }, "alpha must produce feature probabilities strictly between zero and one.")

        var result: [String: Any] = [
            "alpha": model.alpha,
            "classLabels": model.classes.map(\.label),
            "classes": model.classes.map { classStats in
                ["label": classStats.label, "prior": classStats.prior, "count": classStats.count,
                 "featureProbabilities": classStats.featureProbabilities] as [String: Any]
            }
        ]
        if !predictions.isEmpty {
            try require(predictions.count <= 100_000 / model.classes.count,
                        "Use at most 100,000 query and class combinations.")
            result["predictedLabels"] = model.predict(predictions)
            result["probabilities"] = model.predictProbabilities(predictions)
        }
        return result
    }

    /// Checks the binary domain before passing a matrix to Quiver.
    /// - Parameters:
    ///   - rows: The feature rows to validate.
    ///   - name: The MCP argument name used in any error.
    /// - Throws: A calculation error if any value differs from zero or one.
    private static func validateBernoulliFeatures(_ rows: [[Double]], named name: String) throws {
        try require(rows.allSatisfy { row in row.allSatisfy { $0 == 0.0 || $0 == 1.0 } },
                    "\(name) must contain only 0 or 1.")
    }

    /// Runs KNN directly or fits a pipeline on the training rows before classifying.
    private func classify(_ input: _CalculationInput) throws -> [String: Any] {
        let features = try input.matrix("features")
        let labels = try input.labels(count: features.count)
        let width = features[0].count
        let predictions = try input.matrix("predict", width: width)
        let k = try input.integer("k", within: 1...features.count)
        let bounded = _EuclideanInputs.boundedQueries(predictions, features: features)
        if self == .classifyWithKNN {
            return ["predictedLabels": try Self.classify(features: features, labels: labels, queries: bounded, k: k)]
        }

        let scaler = try Self.checkedScaler(features)
        let scaledFeatures = scaler.transform(features)
        let scaledQueries = scaler.transform(bounded)
        if input.contains("componentCount") {
            let count = try input.integer("componentCount", within: 1...width)
            try Self.validateCovariance(scaledFeatures)
            let reducer = PCA.fit(features: scaledFeatures, componentCount: count)
            let labels = try Self.classify(features: reducer.transform(scaledFeatures), labels: labels,
                                           queries: reducer.transform(scaledQueries), k: k)
            return ["predictedLabels": labels, "componentCount": count]
        }

        return ["predictedLabels": try Self.classify(features: scaledFeatures, labels: labels,
                                                    queries: scaledQueries, k: k)]
    }

    /// Uses Quiver's uniform KNN voting on conditioned Euclidean coordinates.
    private static func classify(features: [[Double]], labels: [Int], queries: [[Double]], k: Int) throws -> [Int] {
        let inputs = try _EuclideanInputs(features: features, queries: queries)
        let model = KNearestNeighbors.fit(features: inputs.features, labels: labels, k: k)
        return model.predict(inputs.queries)
    }

    /// Fits k-means and returns the training assignments and optional query assignments.
    private static func fitClusters(_ input: _CalculationInput) throws -> [String: Any] {
        let features = try input.matrix("features")
        let k = try input.integer("k", within: 1...features.count)
        let maxIterations = try input.integer("maxIterations", within: 1...10_000, default: 100)
        let predictions = try input.predictionRows(width: features[0].count)
        let training = try _EuclideanInputs(features: features)
        let model = KMeans.fit(data: training.features, k: k, maxIterations: maxIterations, seed: try input.seed())
        let centroids = model.centroids.map { $0 * training.scale }
        let inertia = _StableStatistics.rescale(model.inertia, by: 2 * training.scale.exponent)
        guard inertia.isFinite, inertia > 0.0 || model.inertia == 0.0 else {
            throw _CalculationError(message: "K-means inertia is outside the representable range.")
        }

        var fields: [String: Any] = ["centroids": centroids, "assignments": model.labels,
                                     "inertia": inertia, "iterations": model.iterations]
        if !predictions.isEmpty {
            let bounded = _EuclideanInputs.boundedQueries(predictions, features: centroids)
            fields["predictedAssignments"] = try classify(features: centroids, labels: Array(centroids.indices),
                                                           queries: bounded, k: 1)
        }
        return fields
    }

    /// Fits PCA and projects training or query rows with the fitted training transform.
    private static func projectComponents(_ input: _CalculationInput) throws -> [String: Any] {
        var features = try input.matrix("features", minimumRows: 2)
        let width = features[0].count
        let count = try input.integer("componentCount", within: 1...width)
        var predictions = try input.predictionRows(width: width)
        let standardize = try input.boolean("standardize", default: false)
        if standardize {
            let scaler = try checkedScaler(features)
            features = scaler.transform(features)
            predictions = scaler.transform(predictions)
        }
        try validateCovariance(features)
        let model = PCA.fit(features: features, componentCount: count)
        return [
            "components": model.components, "explainedVariances": model.explainedVariances,
            "explainedVarianceRatios": model.explainedVarianceRatios,
            "projected": model.transform(predictions.isEmpty ? features : predictions),
            "standardized": standardize
        ]
    }

    /// Fits a scaler and rejects intermediate statistics that overflowed.
    private static func checkedScaler(_ features: [[Double]]) throws -> StandardScaler {
        let scaler = StandardScaler.fit(features: features)
        guard scaler.means.allSatisfy(\.isFinite), scaler.stds.allSatisfy(\.isFinite) else {
            throw _CalculationError(message: "The feature scale exceeds the finite range of standardization.")
        }
        let columns = features.transposed()
        for index in scaler.stds.indices where scaler.stds[index] == 0.0 {
            if columns[index].min() != columns[index].max() {
                throw _CalculationError(message: "A nonconstant feature underflowed during standardization.")
            }
        }
        return scaler
    }

    /// Validates covariance before entering Quiver's nonthrowing PCA fit.
    private static func validateCovariance(_ features: [[Double]]) throws {
        guard features.count >= 2, let covariance = features.covarianceMatrix(),
              covariance.allSatisfy({ $0.allSatisfy(\.isFinite) }) else {
            throw _CalculationError(message: "PCA requires at least two rows and finite covariance.")
        }
    }

    /// Scores one workout with a fresh TES model and returns the session breakdown.
    private static func scoreWorkout(_ input: _CalculationInput) throws -> [String: Any] {
        let samples = try input.samples()
        let fields = ["timestamp", "heartRate", "pace", "cadence", "grade", "verticalOscillation", "altitude"]
        let allowed = Set(fields + ["hrTrust"])
        var model = TrueEffortScore()
        var previousTimestamp: Double?
        for sample in samples {
            guard Set(sample.keys).isSubset(of: allowed) else {
                throw _CalculationError(message: "A workout sample contains an unknown field.")
            }
            let timestamp = try _CalculationInput.number(sample["timestamp"], named: "timestamp")
            if let previousTimestamp {
                let delta = timestamp - previousTimestamp
                guard delta.isFinite, delta > 0.0 else {
                    throw _CalculationError(message: "Sample timestamps must be strictly increasing in seconds.")
                }
            }
            previousTimestamp = timestamp
            let heartRate = try _CalculationInput.number(sample["heartRate"], named: "heartRate")
            let pace = try _CalculationInput.number(sample["pace"], named: "pace")
            let cadence = try _CalculationInput.number(sample["cadence"], named: "cadence")
            let grade = try _CalculationInput.number(sample["grade"], named: "grade")
            let oscillation = try _CalculationInput.number(sample["verticalOscillation"], named: "verticalOscillation")
            let altitude = try _CalculationInput.number(sample["altitude"], named: "altitude")
            let trust = try _CalculationInput.number(sample["hrTrust"] ?? 1.0, named: "hrTrust")
            guard heartRate > 0.0, pace > 0.0, cadence >= 0.0, oscillation >= 0.0,
                  (0.0...1.0).contains(trust) else {
                throw _CalculationError(message: "Use positive heartRate and pace, nonnegative cadence and verticalOscillation, and hrTrust from 0 to 1.")
            }
            model.record(heartRate: heartRate, pace: pace, cadence: cadence, grade: grade,
                         verticalOscillation: oscillation, altitude: altitude,
                         at: Date(timeIntervalSince1970: timestamp), hrTrust: trust)
        }
        guard let result = model.finalize() else {
            throw _CalculationError(message: "TES requires at least 60 seconds of active time.")
        }
        let distribution = Dictionary(uniqueKeysWithValues: result.effortDistribution.map { ($0.key.rawValue, $0.value) })
        return [
            "raw": result.raw, "adjusted": result.adjusted, "averageHeartRate": result.averageHeartRate,
            "expectedHeartRate": result.expectedHeartRate.map { $0 as Any } ?? NSNull(),
            "meanResidual": result.meanResidual.map { $0 as Any } ?? NSNull(),
            "effortDistribution": distribution, "varianceMultiplier": result.varianceMultiplier,
            "durationFactor": result.durationFactor, "transitionLoad": result.transitionLoad,
            "activeSeconds": result.timerTime, "elapsedSeconds": result.elapsedTime, "loadCurve": result.loadCurve
        ]
    }

    /// Fits linear regression with batch gradient descent and returns its loss trace.
    private static func fitGradient(_ input: _CalculationInput) throws -> [String: Any] {
        let features = try input.matrix("features", minimumRows: 2)
        let targets = try input.targets(count: features.count)
        let predictions = try input.predictionRows(width: features[0].count)
        let settings = try optimization(input)
        let model = try GradientDescent.fit(features: features, targets: targets,
                                            learningRate: settings.learningRate, maxIterations: settings.maxIterations,
                                            tolerance: settings.tolerance)
        var fields: [String: Any] = ["coefficients": model.coefficients, "lossHistory": model.lossHistory,
                                     "outcome": model.outcome.rawValue]
        if !predictions.isEmpty { fields["predictions"] = model.predict(predictions) }
        return fields
    }

    /// Fits a linear baseline and returns observed-minus-predicted differences for separate rows.
    private static func residuals(_ input: _CalculationInput) throws -> [String: Any] {
        let features = try input.matrix("features", minimumRows: 2)
        let targets = try input.targets(count: features.count)
        let observations = try input.matrix("observedFeatures", width: features[0].count)
        let observedTargets = try input.targets("observedTargets", count: observations.count)
        if features[0].count == 1 {
            let line = try _StableStatistics.centeredLine(features: features.map { $0[0] }, targets: targets)
            let intercept = line.referenceResponse.addingProduct(-line.slope, line.referencePredictor)
            let predictions = _StableStatistics.evaluateLine(line, intercept: intercept, at: observations.map { $0[0] })
            return ["coefficients": [intercept, line.slope], "predictions": predictions,
                    "residuals": observedTargets.subtract(predictions)]
        }

        let model = try LinearRegression.fit(features: features, targets: targets)
        let residualModel = ResidualModel(model: model)
        return ["coefficients": model.coefficients, "predictions": model.predict(observations),
                "residuals": residualModel.residuals(features: observations, targets: observedTargets)]
    }
}
