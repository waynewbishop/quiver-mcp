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


/// Describes a calculation and its required and optional JSON fields.
struct _CalculationContract {
    /// The description shown during tool discovery.
    let description: String
    /// The JSON schemas for required fields.
    let required: [String: [String: Any]]
    /// The JSON schemas for optional fields.
    let optional: [String: [String: Any]]

    /// Builds a closed JSON object schema from the declared fields.
    var schema: [String: Any] {
        [
            "type": "object",
            "properties": required.merging(optional) { required, _ in required },
            "required": required.keys.sorted(),
            "additionalProperties": false
        ]
    }

    /// Records a tool description and its argument fields.
    init(_ description: String, required: [String: [String: Any]], optional: [String: [String: Any]] = [:]) {
        self.description = description
        self.required = required
        self.optional = optional
    }
}

extension _QuiverCalculation {
    /// The input contract for this tool.
    var contract: _CalculationContract {
        let number = ["type": "number"]
        let positive = ["type": "number", "exclusiveMinimum": 0] as [String: Any]
        let integer = ["type": "integer"]
        let positiveInteger = ["type": "integer", "minimum": 1] as [String: Any]
        let vector = Self.array(of: number)
        let sample = Self.array(of: number, minimumCount: 2)
        let matrix = Self.array(of: vector)
        let training = Self.array(of: vector, minimumCount: 2)
        let labels = Self.array(of: integer)
        let iterations = ["type": "integer", "minimum": 1, "maximum": 10_000] as [String: Any]
        let optimizer = ["learningRate": positive, "maxIterations": iterations, "tolerance": positive, "predict": matrix]

        switch self {
        case .describeSample:
            return .init("Describe a numeric sample with selectable percentiles and outlier settings.", required: ["values": vector], optional: ["ddof": integer, "percentiles": vector, "score": number, "threshold": number, "bias": ["type": "boolean"]])
        case .correlation:
            return .init("Calculate Pearson correlation for paired observations.", required: ["left": vector, "right": vector])
        case .correlationMatrix:
            return .init("Calculate Pearson correlations between columns of row-oriented observations.", required: ["rows": matrix])
        case .covarianceMatrix:
            return .init("Calculate covariance between columns of row-oriented observations.", required: ["rows": matrix], optional: ["ddof": integer])
        case .evaluateDistribution:
            return .init("Evaluate a normal, Student t, chi-square, Poisson or binomial distribution.", required: ["distribution": ["type": "string", "enum": ["normal", "t", "chi_squared", "poisson", "binomial"]], "operation": ["type": "string", "enum": ["pdf", "log_pdf", "pmf", "log_pmf", "cdf", "quantile", "mean", "variance"]]], optional: ["x": number, "mean": number, "standardDeviation": number, "df": number, "k": integer, "n": integer, "lambda": number, "p": number, "probability": number])
        case .frequencyTable:
            return .init("Count distinct numeric observations and report their relative frequencies.", required: ["values": vector])
        case .histogram:
            return .init("Bin observations with a fixed bin count or a named rule.", required: ["values": vector], optional: ["bins": integer, "rule": ["type": "string", "enum": ["square_root", "sturges", "freedman_diaconis"]]])
        case .contingencyTable:
            return .init("Calculate joint and conditional probabilities for categorical counts. Optionally compare the observed joint probabilities with the products of the marginals.",
                         required: ["rowLabels": Self.array(of: ["type": "string"]), "columnLabels": Self.array(of: ["type": "string"]), "counts": matrix],
                         optional: ["compareIndependence": ["type": "boolean"]])
        case .bayesPosterior:
            return .init("Update a prior using evidence, diagnostic rates, or likelihoods for named hypotheses.", required: [:], optional: ["prior": number, "likelihood": number, "evidence": number, "trueRate": number, "falsePositiveRate": number, "hypotheses": Self.array(of: ["type": "string"]), "priors": vector, "likelihoods": vector])
        case .sample:
            return .init("Draw a reproducible sample with or without replacement.", required: ["values": vector, "count": integer, "seed": integer], optional: ["replace": ["type": "boolean"]])
        case .estimateSamplingDistribution:
            return .init("Compute seeded mean, median or standard-deviation replicates and a percentile interval.", required: ["values": vector, "statistic": ["type": "string", "enum": ["mean", "median", "standard_deviation"]], "seed": integer], optional: ["sampleSize": integer, "iterations": integer, "level": number])
        case .summarizeRegression:
            return .init("Fit OLS and report coefficient inference and fit diagnostics.", required: ["features": matrix, "targets": vector], optional: ["level": number, "intercept": ["type": "boolean"]])
        case .evaluatePredictions:
            return .init("Evaluate regression predictions or integer classification labels.", required: ["kind": ["type": "string", "enum": ["regression", "classification"]], "predictions": vector, "actual": vector], optional: ["positiveLabel": integer])
        case .summarizeColumns:
            return .init("Summarize named numeric columns in a row-oriented table.", required: ["rows": matrix, "columns": Self.array(of: ["type": "string"])])
        case .groupValues:
            return .init("Aggregate numeric observations by category.", required: ["values": vector, "categories": Self.array(of: ["type": "string"]), "aggregation": ["type": "string", "enum": ["sum", "mean", "min", "max", "count", "percentage"]]])
        case .prepareSeries:
            return .init("Apply standardization, smoothing, differencing or percent change.", required: ["values": vector, "operation": ["type": "string", "enum": ["standardize", "rolling_mean", "exponential_mean", "difference", "percent_change"]]], optional: ["window": integer, "alpha": number, "span": integer, "lag": integer])
        case .splitIndices:
            return .init("Return reproducible train/test or k-fold validation indices.", required: ["count": integer, "seed": integer], optional: ["testRatio": number, "folds": integer])
        case .fourierSpectrum:
            return .init("Compute frequencies and magnitudes from evenly spaced samples.", required: ["values": vector, "sampleRate": number], optional: ["windowed": ["type": "boolean"]])
        case .dotProduct:
            return .init("Compute the dot product of two equal-length vectors.", required: ["left": vector, "right": vector])
        case .vectorMagnitude:
            return .init("Compute the Euclidean length of a vector.", required: ["vector": vector])
        case .euclideanDistance:
            return .init("Compute the Euclidean distance between two equal-length vectors.", required: ["left": vector, "right": vector])
        case .normalizeVector:
            return .init("Scale a vector to unit length. A zero vector stays zero.", required: ["vector": vector])
        case .projectVector:
            return .init("Project a vector onto an equal-length direction vector. A zero direction gives a zero projection.",
                         required: ["vector": vector, "onto": vector])
        case .multiplyMatrixVector:
            return .init("Compute A times v. Each output entry is a row dot product.", required: ["matrix": matrix, "vector": vector])
        case .multiplyMatrices:
            return .init("Compute left times right; the left column count must equal the right row count.",
                         required: ["left": matrix, "right": matrix])
        case .transposeMatrix:
            return .init("Swap a matrix’s rows and columns.", required: ["matrix": matrix])
        case .invertMatrix:
            return .init("Invert a nonsingular square matrix.", required: ["matrix": matrix])
        case .matrixDeterminant:
            return .init("Compute the determinant of a square matrix.", required: ["matrix": matrix])
        case .renderMath:
            return _MathRendering.contract
        case .solveLinearSystem:
            return .init("Solve a square linear system Ax = b.", required: ["matrix": matrix, "rhs": vector])
        case .decomposeMatrix:
            return .init("Compute LU or symmetric eigen decomposition of a square matrix.", required: ["matrix": matrix, "method": ["type": "string", "enum": ["lu", "eigen"]]])
        case .fitPolynomial:
            return .init("Fit a polynomial to paired observations and optionally evaluate it.", required: ["x": vector, "y": vector, "degree": integer], optional: ["predict": vector])
        case .searchEmbeddings:
            return .init("Rank caller-supplied vectors by cosine similarity.", required: ["vectors": matrix, "labels": Self.array(of: ["type": "string"]), "query": vector, "k": integer])
        case .vectorSummary:
            return .init("Summarize one numeric sample.", required: ["values": sample])
        case .cosineSimilarity:
            return .init("Compute the cosine similarity of two nonzero vectors.", required: ["left": vector, "right": vector])
        case .fitLinearRegression:
            return .init("Fit a straight line with an intercept.", required: ["features": sample, "targets": sample],
                         optional: ["predict": vector])
        case .fitRidgeRegression:
            return .init("Fit linear regression with an L2 penalty.",
                         required: ["features": training, "targets": sample, "lambda": ["type": "number", "minimum": 0]],
                         optional: optimizer)
        case .fitLogisticRegression:
            return .init("Fit a binary classifier and optionally predict class 1 probabilities.",
                         required: ["features": training, "labels": Self.array(of: ["type": "integer", "enum": [0, 1]], minimumCount: 2)],
                         optional: optimizer)
        case .fitGaussianNaiveBayes:
            return .init("Fit a Gaussian classifier and return predictions and per-class probabilities.",
                         required: ["features": matrix, "labels": labels, "predict": matrix])
        case .fitBernoulliNaiveBayes:
            return .init("Fit Bernoulli Naive Bayes to binary features and optionally classify new rows.",
                         required: ["features": matrix, "labels": labels],
                         optional: ["predict": matrix, "alpha": positive])
        case .classifyWithKNN:
            return .init("Classify query rows with Euclidean distance and uniform voting.",
                         required: ["features": matrix, "labels": labels, "predict": matrix, "k": positiveInteger])
        case .fitKMeans:
            return .init("Cluster observations and return centroids, assignments, and inertia.",
                         required: ["features": matrix, "k": positiveInteger],
                         optional: ["seed": ["type": "integer", "minimum": 0, "maximum": 9_007_199_254_740_991],
                                    "maxIterations": iterations, "predict": matrix])
        case .fitPCA:
            return .init("Fit PCA and project training or query rows.",
                         required: ["features": training, "componentCount": positiveInteger],
                         optional: ["standardize": ["type": "boolean"], "predict": matrix])
        case .calculateTrueEffortScore:
            let requiredFields = ["timestamp", "heartRate", "pace", "cadence", "grade", "verticalOscillation", "altitude"]
            var properties: [String: [String: Any]] = ["hrTrust": ["type": "number", "minimum": 0, "maximum": 1]]
            for field in requiredFields { properties[field] = number }
            let sampleSchema: [String: Any] = [
                "type": "object", "required": requiredFields, "additionalProperties": false,
                "properties": properties
            ]
            return .init("Score a complete workout using Unix timestamps in seconds.",
                         required: ["samples": Self.array(of: sampleSchema, minimumCount: 2)])
        case .fitGradientDescent:
            return .init("Fit linear regression with batch gradient descent and report its loss history.",
                         required: ["features": training, "targets": sample], optional: optimizer)
        case .analyzeResiduals:
            return .init("Fit a linear baseline on training rows and compare predictions with separate observations.",
                         required: ["features": training, "targets": sample, "observedFeatures": matrix, "observedTargets": vector])
        case .fitKNNPipeline:
            return .init("Fit a scaler and KNN on training rows, optionally applying PCA before classification.",
                         required: ["features": matrix, "labels": labels, "predict": matrix, "k": positiveInteger],
                         optional: ["componentCount": positiveInteger])
        }
    }

    /// Builds the schema for an array of a specified item type.
    private static func array(of items: [String: Any], minimumCount: Int = 1) -> [String: Any] {
        ["type": "array", "items": items, "minItems": minimumCount]
    }
}
