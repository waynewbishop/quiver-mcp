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
    /// Dispatches stateless statistics, data preparation, and numerical tools.
    func calculateAnalysis(_ input: _CalculationInput) throws -> [String: Any] {
        switch self {
        case .describeSample: return try Self.describe(input)
        case .evaluateDistribution: return try Self.distribution(input)
        case .histogram: return try Self.histogram(input)
        case .contingencyTable: return try Self.contingency(input)
        case .bayesPosterior: return try Self.bayes(input)
        case .estimateSamplingDistribution: return try Self.samplingDistribution(input)
        case .summarizeRegression: return try Self.regression(input)
        case .evaluatePredictions: return try Self.evaluate(input)
        case .prepareSeries: return try Self.prepareSeries(input)
        case .splitIndices: return try Self.split(input)
        case .searchEmbeddings: return try Self.search(input)
        case .correlation:
            let left = try input.vector("left", minimumCount: 2)
            let right = try input.targets("right", count: left.count)
            try Self.require(left.count <= 100_000, "Use at most 100,000 observations.")
            return ["correlation": Self.pearson(Self.rescaled(left), Self.rescaled(right))]
        case .correlationMatrix, .covarianceMatrix:
            let rows = try Self.boundedMatrix(input, "rows", minimumRows: 2)
            if self == .covarianceMatrix {
                let ddof = try input.integer("ddof", within: 0...(rows.count - 1), default: 1)
                guard let covariance = rows.covarianceMatrix(ddof: ddof) else {
                    throw _CalculationError(message: "Covariance is undefined for these observations.")
                }
                return ["matrix": covariance]
            }
            let columns = rows[0].indices.map { column in Self.rescaled(rows.map { $0[column] }) }
            return ["matrix": columns.map { left in columns.map { Self.pearson(left, $0) } }]
        case .frequencyTable:
            let values = try input.vector("values")
            try Self.require(values.count <= 10_000, "Use at most 10,000 observations.")
            return ["frequencies": values.distinctCounts().map {
                ["value": $0.value, "count": $0.count, "probability": Double($0.count) / Double(values.count)] as [String: Any]
            }]
        case .sample:
            let values = try input.vector("values")
            try Self.require(values.count <= 10_000, "Use at most 10,000 observations.")
            let count = try input.integer("count", within: 1...10_000)
            let replace = try input.boolean("replace", default: true)
            try Self.require(replace || count <= values.count, "Without replacement, count cannot exceed the number of observations.")
            return ["values": values.sample(count, replace: replace, seed: try Self.seed(input))]
        case .summarizeColumns:
            let rows = try Self.boundedMatrix(input, "rows")
            let columns = try input.strings("columns")
            try Self.require(columns.count == rows[0].count && Set(columns).count == columns.count,
                             "Provide one unique name per column.")
            return try Self.jsonObject(Panel(matrix: rows, columns: columns).summary())
        case .groupValues:
            let values = try input.vector("values")
            let categories = try input.strings("categories")
            try Self.require(values.count == categories.count && values.count <= 10_000,
                             "Provide matching values and categories, up to 10,000 observations.")
            let methods: [String: AggregationMethod] = [
                "sum": .sum, "mean": .mean, "count": .count, "min": .min, "max": .max, "percentage": .percentage
            ]
            let method = try input.choice("aggregation", options: methods.keys.sorted())
            guard let aggregation = methods[method] else { throw _CalculationError(message: "Unknown aggregation.") }
            return ["groups": values.groupedData(by: categories, using: aggregation).map {
                ["category": $0.category, "value": $0.value] as [String: Any]
            }]
        case .fourierSpectrum:
            let values = try input.vector("values", minimumCount: 2)
            let rate = try input.number("sampleRate")
            try Self.require(rate > 0 && values.count <= 65_536, "Use a positive sample rate and at most 65,536 samples.")
            let spectrum = values.fourierSpectrum(sampleRate: rate, windowed: try input.boolean("windowed", default: false))
            return ["spectrum": spectrum.map { ["frequency": $0.frequency, "magnitude": $0.magnitude] }]
        case .solveLinearSystem, .decomposeMatrix:
            let matrix = try Self.boundedMatrix(input, "matrix")
            try Self.require(matrix.count == matrix[0].count, "matrix must be square.")
            if self == .solveLinearSystem {
                let rhs = try input.targets("rhs", count: matrix.count)
                guard let solution = matrix.solve(rhs) else {
                    throw _CalculationError(message: "The linear system has no unique solution.")
                }
                return ["solution": solution]
            }
            if try input.choice("method", options: ["lu", "eigen"]) == "lu" {
                let lu = try matrix.luDecomposed()
                return ["lower": lu.l, "upper": lu.u, "permutation": lu.p, "determinant": lu.determinant]
            }
            let eigen = try matrix.eigenDecomposed()
            return ["eigenvalues": eigen.eigenvalues, "eigenvectors": eigen.eigenvectors,
                    "converged": eigen.converged, "sweepsUsed": eigen.sweepsUsed]
        case .fitPolynomial:
            let x = try input.vector("x")
            let y = try input.targets("y", count: x.count)
            let degree = try input.integer("degree", within: 0...min(32, x.count - 1))
            try Self.require(x.count <= 10_000, "Use at most 10,000 observations.")
            guard let polynomial = [Double].polyfit(x: x, y: y, degree: degree) else {
                throw _CalculationError(message: "A polynomial of this degree could not be fitted.")
            }
            var result: [String: Any] = ["coefficients": polynomial.coefficients, "degree": polynomial.degree]
            if let predict = try input.optionalVector("predict") {
                try Self.require(predict.count <= 10_000, "Use at most 10,000 prediction points.")
                result["predictions"] = polynomial(predict)
            }
            return result
        default:
            throw _CalculationError(message: "Unsupported analysis.")
        }
    }

    /// Positive scaling preserves Pearson correlation and prevents overflow in its products.
    private static func rescaled(_ values: [Double]) -> [Double] {
        let scale = values.map { abs($0) }.max() ?? 0
        return scale > 0 ? values.map { $0 / scale } : values
    }

    private static func pearson(_ left: [Double], _ right: [Double]) -> Any {
        guard let correlation = left.correlation(with: right), correlation.isFinite else { return NSNull() }
        return min(1, max(-1, correlation))
    }

    /// Rejects values that would violate a Quiver API precondition or a tool limit.
    static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw _CalculationError(message: message) }
    }

    /// Limits matrix dimensions and the total number of cells.
    static func boundedMatrix(_ input: _CalculationInput, _ name: String, minimumRows: Int = 1) throws -> [[Double]] {
        let rows = try input.matrix(name, minimumRows: minimumRows)
        try require(rows[0].count <= 128 && rows.count <= 100_000 / rows[0].count,
                    "Use at most 128 columns and 100,000 cells.")
        return rows
    }

    /// Reads the required seed without rounding JSON integers.
    static func seed(_ input: _CalculationInput) throws -> UInt64 {
        guard let seed = try input.seed() else { throw _CalculationError(message: "Supply a seed.") }
        return seed
    }

    /// Represents undefined scalar values as JSON null.
    static func nullable(_ value: Double?) -> Any {
        guard let value, value.isFinite else { return NSNull() }
        return value
    }

    /// Serializes a framework report using its Codable representation.
    static func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw _CalculationError(message: "The report could not be encoded as a JSON object.")
        }
        return object
    }

    private static func prepareSeries(_ input: _CalculationInput) throws -> [String: Any] {
        let values = try input.vector("values")
        try require(values.count <= 10_000, "Use at most 10,000 observations.")
        let operation = try input.choice("operation", options: [
            "standardize", "rolling_mean", "exponential_mean", "difference", "percent_change"
        ])
        let result: [Double]
        switch operation {
        case "standardize": result = values.standardized()
        case "rolling_mean": result = values.rollingMean(window: try input.integer("window", within: 1...values.count))
        case "exponential_mean":
            try require(input.contains("span") != input.contains("alpha"), "Supply either span or alpha.")
            if input.contains("span") {
                result = values.exponentialMean(span: try input.integer("span", within: 1...10_000))
            } else {
                let alpha = try input.number("alpha")
                try require(alpha > 0 && alpha <= 1, "alpha must be greater than zero and at most one.")
                result = values.exponentialMean(alpha: alpha)
            }
        case "difference", "percent_change":
            let lag = try input.integer("lag", within: 1...10_000, default: 1)
            try require(lag < values.count, "lag must be less than the observation count.")
            result = operation == "difference" ? values.diff(lag: lag) : values.percentChange(lag: lag)
        default: throw _CalculationError(message: "Unknown series operation.")
        }
        return ["values": result.map { nullable($0) }]
    }

    private static func split(_ input: _CalculationInput) throws -> [String: Any] {
        let count = try input.integer("count", within: 2...10_000)
        let indices = Array(0..<count)
        let seed = try seed(input)
        try require(input.contains("folds") != input.contains("testRatio"), "Supply either folds or testRatio.")
        if input.contains("folds") {
            let folds = try input.integer("folds", within: 2...min(20, count))
            return ["folds": indices.kFoldIndices(k: folds, seed: seed).map {
                ["train": $0.train, "validation": $0.validation]
            }]
        }
        let ratio = try input.number("testRatio")
        try require(ratio > 0 && ratio < 1, "testRatio must be between zero and one.")
        let partitions = indices.trainTestSplit(testRatio: ratio, seed: seed)
        return ["train": partitions.train, "test": partitions.test]
    }

    private static func search(_ input: _CalculationInput) throws -> [String: Any] {
        let vectors = try boundedMatrix(input, "vectors")
        let labels = try input.strings("labels")
        let query = try input.targets("query", count: vectors[0].count)
        let k = try input.integer("k", within: 1...min(100, vectors.count))
        try require(labels.count == vectors.count && Set(labels).count == labels.count, "Supply one unique label per vector.")
        let normalized = try (vectors + [query]).map { vector in
            let scale = vector.map { abs($0) }.max() ?? 0
            try require(scale > 0, "Cosine search requires nonzero vectors.")
            return vector / scale
        }
        let entries = Dictionary(uniqueKeysWithValues: zip(labels, normalized))
        return ["hits": entries.nearest(to: normalized[vectors.count], k: k).map {
            ["rank": $0.rank, "label": $0.word, "score": $0.score] as [String: Any]
        }]
    }
}
