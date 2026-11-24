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

/// Describes the calculations available through MCP and dispatches them to Quiver.
///
/// Inputs and results belong to the current request. Calculations keep no
/// history or fitted models between calls.
@_documentation(visibility: internal)
enum _QuiverCalculation: String, CaseIterable {
    /// Summarizes one numeric sample.
    case vectorSummary = "vector_summary"

    /// Compares the directions of two vectors.
    case cosineSimilarity = "cosine_similarity"

    /// Fits a line to paired predictor and target observations.
    case fitLinearRegression = "fit_linear_regression"

    /// Fits a ridge regression with an L2 penalty.
    case fitRidgeRegression = "fit_ridge_regression"

    /// Fits a binary logistic classifier.
    case fitLogisticRegression = "fit_logistic_regression"

    /// Fits a Gaussian Naive Bayes classifier.
    case fitGaussianNaiveBayes = "fit_gaussian_naive_bayes"

    /// Fits a Naive Bayes classifier for binary features.
    case fitBernoulliNaiveBayes = "fit_bernoulli_naive_bayes"

    /// Classifies queries with k-nearest neighbors.
    case classifyWithKNN = "classify_with_knn"

    /// Clusters supplied observations with k-means.
    case fitKMeans = "fit_kmeans"

    /// Fits principal components and projects rows.
    case fitPCA = "fit_pca"

    /// Scores one timestamped workout.
    case calculateTrueEffortScore = "calculate_true_effort_score"

    /// Fits linear regression by batch gradient descent.
    case fitGradientDescent = "fit_gradient_descent"

    /// Fits a linear baseline and measures prediction residuals.
    case analyzeResiduals = "analyze_residuals"

    /// Fits a standardization and k-nearest neighbors pipeline.
    case fitKNNPipeline = "fit_knn_pipeline"

    case describeSample = "describe_sample"
    case correlation = "correlation"
    case correlationMatrix = "correlation_matrix"
    case covarianceMatrix = "covariance_matrix"
    case evaluateDistribution = "evaluate_distribution"
    case frequencyTable = "frequency_table"
    case histogram = "histogram"
    case contingencyTable = "contingency_table"
    case bayesPosterior = "bayes_posterior"
    case sample = "sample"
    case estimateSamplingDistribution = "estimate_sampling_distribution"
    case summarizeRegression = "summarize_regression"
    case evaluatePredictions = "evaluate_predictions"
    case summarizeColumns = "summarize_columns"
    case groupValues = "group_values"
    case prepareSeries = "prepare_series"
    case splitIndices = "split_indices"
    case fourierSpectrum = "fourier_spectrum"
    case dotProduct = "dot_product"
    case vectorMagnitude = "vector_magnitude"
    case euclideanDistance = "euclidean_distance"
    case normalizeVector = "normalize_vector"
    case projectVector = "project_vector"
    case multiplyMatrixVector = "multiply_matrix_vector"
    case multiplyMatrices = "multiply_matrices"
    case transposeMatrix = "transpose_matrix"
    case invertMatrix = "invert_matrix"
    case matrixDeterminant = "matrix_determinant"
    case renderMath = "render_math"
    case solveLinearSystem = "solve_linear_system"
    case decomposeMatrix = "decompose_matrix"
    case fitPolynomial = "fit_polynomial"
    case searchEmbeddings = "search_embeddings"

    /// The tool description and input schema advertised during discovery.
    var definition: [String: Any] {
        [
            "name": rawValue,
            "description": "\(contract.description) Uses Quiver \(Quiver.version).",
            "inputSchema": contract.schema
        ]
    }

    /// Validates the request arguments and performs one Quiver calculation.
    /// - Parameter arguments: The JSON object containing the numeric input arrays.
    /// - Returns: Named result fields that can be encoded as JSON.
    /// - Throws: An input or calculation error if the requested result is undefined.
    func calculate(arguments: Any?) throws -> [String: Any] {
        guard let values = arguments as? [String: Any] else {
            throw _CalculationError(message: "Supply an arguments object.")
        }

        let arguments = try _CalculationInput(values, contract: contract)
        let fields: [String: Any]
        switch self {
        case .vectorSummary:
            fields = try _StableStatistics.summarize(arguments.vector("values", minimumCount: 2))
        case .cosineSimilarity:
            fields = ["similarity": try Self.cosineSimilarity(
                between: arguments.vector("left"), and: arguments.vector("right")
            )]
        case .dotProduct, .vectorMagnitude, .euclideanDistance, .normalizeVector, .projectVector,
             .multiplyMatrixVector, .multiplyMatrices, .transposeMatrix, .invertMatrix, .matrixDeterminant:
            fields = try calculateLinearAlgebra(arguments)
        case .renderMath:
            fields = try _MathRendering.render(arguments)
        case .fitLinearRegression:
            fields = try Self.fitLinearRegression(arguments)
        case .describeSample, .correlation, .correlationMatrix, .covarianceMatrix, .evaluateDistribution, .frequencyTable, .histogram, .contingencyTable, .bayesPosterior, .sample, .estimateSamplingDistribution, .summarizeRegression, .evaluatePredictions, .summarizeColumns, .groupValues, .prepareSeries, .splitIndices, .fourierSpectrum, .solveLinearSystem, .decomposeMatrix, .fitPolynomial, .searchEmbeddings:
            fields = try calculateAnalysis(arguments)
        default:
            fields = try calculateModel(arguments)
        }

        guard JSONSerialization.isValidJSONObject(fields) else {
            throw _CalculationError(message: "The calculation produced a non-finite result.")
        }
        return fields
    }

    /// Computes cosine similarity after scaling each vector by its largest absolute component.
    ///
    /// Positive scaling preserves direction and makes the magnitude calculation
    /// stable for vectors whose components are very large or very small.
    ///
    /// - Parameters:
    ///   - left: The first vector.
    ///   - right: The second vector, with the same dimension as the first.
    /// - Returns: Quiver's cosine similarity between the vectors.
    /// - Throws: An error if the vectors have different lengths or either is zero.
    private static func cosineSimilarity(between left: [Double], and right: [Double]) throws -> Double {
        guard left.count == right.count else {
            throw _CalculationError(message: "left and right must have the same length.")
        }
        guard let leftScale = left.map({ abs($0) }).max(), leftScale > 0.0,
              let rightScale = right.map({ abs($0) }).max(), rightScale > 0.0 else {
            throw _CalculationError(message: "Cosine similarity requires two nonzero vectors.")
        }

        let scaledLeft = left / leftScale
        let scaledRight = right / rightScale
        let similarity = scaledLeft.cosineOfAngle(with: scaledRight)
        guard similarity.isFinite else {
            throw _CalculationError(message: "The calculation produced a non-finite cosine similarity.")
        }
        return min(1.0, max(-1.0, similarity))
    }

    /// Fits a single-predictor regression and optionally predicts supplied values.
    /// - Parameter input: The training arrays and optional prediction vector.
    /// - Returns: The intercept, slope, and any requested predictions.
    private static func fitLinearRegression(_ input: _CalculationInput) throws -> [String: Any] {
        let features = try input.vector("features", minimumCount: 2)
        let targets = try input.vector("targets", minimumCount: 2)
        guard features.count == targets.count else {
            throw _CalculationError(message: "features and targets must have the same length.")
        }
        let predictionValues = try input.optionalVector("predict")
        return try _StableStatistics.fitLine(features: features, targets: targets, predictions: predictionValues)
    }
}
