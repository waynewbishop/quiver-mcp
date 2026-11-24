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
    static func describe(_ input: _CalculationInput) throws -> [String: Any] {
        let values = try input.vector("values")
        try require(values.count <= 10_000, "Use at most 10,000 observations.")
        let ddof = try input.integer("ddof", within: 0...10_000, default: 1)
        let bias = try input.boolean("bias", default: true)
        let threshold = try input.number("threshold", default: 2)
        let percentiles = try input.optionalVector("percentiles") ?? [25, 50, 75]
        try require(threshold >= 0, "threshold must be nonnegative.")
        try require(percentiles.count <= 100 && percentiles.allSatisfy { (0...100).contains($0) },
                    "Supply up to 100 percentile levels between zero and 100.")

        var result: [String: Any] = values.count >= 2 ? _StableStatistics.summarize(values) : [
            "count": 1, "mean": values[0], "minimum": values[0], "median": values[0], "maximum": values[0]
        ]
        let deviation = values.standardDeviation(ddof: ddof)
        result["variance"] = nullable(values.variance(ddof: ddof))
        result["standardDeviation"] = nullable(deviation)
        result["standardError"] = nullable(values.standardError(ddof: ddof))
        result["ddof"] = ddof
        result["sum"] = nullable(values.sum())
        result["product"] = nullable(values.product())
        result["cumulativeSum"] = values.cumulativeSum().map { nullable($0) }
        result["cumulativeProduct"] = values.cumulativeProduct().map { nullable($0) }
        result["argMin"] = values.argMin()
        result["argMax"] = values.argMax()
        result["modes"] = values.mode()
        result["skewness"] = nullable(values.skewness(bias: bias))
        result["bowleySkewness"] = nullable(values.bowleySkewness())
        result["kurtosis"] = nullable(values.kurtosis(bias: bias))
        result["percentiles"] = percentiles.map { ["percentile": $0, "value": nullable(values.percentile($0))] }
        result["percentileRanks"] = values.percentileRanks().map { nullable($0) }
        if let rule = values.empiricalRule() {
            result["empiricalRule"] = try jsonObject(rule)
        } else {
            result["empiricalRule"] = NSNull()
        }
        if let deviation, deviation.isFinite {
            result["outlierMask"] = values.outlierMask(threshold: threshold, standardDeviation: deviation)
        } else {
            result["outlierMask"] = NSNull()
        }
        if input.contains("score") {
            let score = try input.number("score")
            result["zScore"] = nullable(values.zScore(of: score, ddof: ddof))
            result["percentileRank"] = nullable(values.percentileRank(of: score))
        }
        return result
    }

    static func distribution(_ input: _CalculationInput) throws -> [String: Any] {
        let family = try input.choice("distribution", options: ["normal", "t", "chi_squared", "poisson", "binomial"])
        let operation = try input.choice("operation", options: [
            "pdf", "log_pdf", "pmf", "log_pmf", "cdf", "quantile", "mean", "variance"
        ])
        let value: Double?
        switch (family, operation) {
        case ("normal", "pdf"):
            value = try Distributions.normal.pdf(x: input.number("x"), mean: input.number("mean", default: 0),
                                                 standardDeviation: input.number("standardDeviation", default: 1))
        case ("normal", "log_pdf"):
            value = try Distributions.normal.logPDF(x: input.number("x"), mean: input.number("mean", default: 0),
                                                    standardDeviation: input.number("standardDeviation", default: 1))
        case ("normal", "cdf"):
            value = try Distributions.normal.cdf(x: input.number("x"), mean: input.number("mean", default: 0),
                                                 standardDeviation: input.number("standardDeviation", default: 1))
        case ("normal", "quantile"):
            value = try Distributions.normal.quantile(p: input.number("p"), mean: input.number("mean", default: 0),
                                                      standardDeviation: input.number("standardDeviation", default: 1))
        case ("t", "cdf"):
            value = try Distributions.t.cdf(x: input.number("x"), df: input.number("df"))
        case ("t", "quantile"):
            value = try Distributions.t.quantile(p: input.number("p"), df: input.number("df"))
        case ("chi_squared", "cdf"):
            value = try Distributions.chiSquared.cdf(x: input.number("x"), df: input.number("df"))
        case ("poisson", _):
            let lambda = try input.number("lambda")
            switch operation {
            case "pmf": value = try Distributions.poisson.pmf(k: eventCount(input), lambda: lambda)
            case "log_pmf": value = try Distributions.poisson.logPMF(k: eventCount(input), lambda: lambda)
            case "cdf": value = try Distributions.poisson.cdf(k: eventCount(input), lambda: lambda)
            case "quantile":
                let p = try input.number("p")
                try require(lambda > 0 && (0...1).contains(p), "Poisson requires lambda > 0 and p between zero and one.")
                if p == 0 { return ["value": 0] }
                if p == 1 { return ["value": NSNull()] }
                // Quiver 1.6 walks one count at a time after converting a floating-point seed to Int.
                let upper = 9_007_199_254_740_990
                let value = try discreteQuantile(p, upper: upper) { Distributions.poisson.cdf(k: $0, lambda: lambda) }
                return ["value": value]
            case "mean": value = Distributions.poisson.mean(lambda: lambda)
            case "variance": value = Distributions.poisson.variance(lambda: lambda)
            default: throw _CalculationError(message: "This operation is unavailable for Poisson.")
            }
        case ("binomial", _):
            let n = try input.integer("n", within: 0...1_000_000_000)
            switch operation {
            case "pmf": value = try Distributions.binomial.pmf(k: eventCount(input), n: n, p: input.number("p"))
            case "log_pmf": value = try Distributions.binomial.logPMF(k: eventCount(input), n: n, p: input.number("p"))
            case "cdf": value = try Distributions.binomial.cdf(k: eventCount(input), n: n, p: input.number("p"))
            case "quantile":
                let p = try input.number("p")
                let probability = try input.number("probability")
                try require((0...1).contains(p) && (0...1).contains(probability),
                            "Binomial probabilities must be between zero and one.")
                if p == 0 { return ["value": 0] }
                if p == 1 { return ["value": n] }
                let value = try discreteQuantile(p, upper: n) { Distributions.binomial.cdf(k: $0, n: n, p: probability) }
                return ["value": value]
            case "mean": value = try Distributions.binomial.mean(n: n, p: input.number("p"))
            case "variance": value = try Distributions.binomial.variance(n: n, p: input.number("p"))
            default: throw _CalculationError(message: "This operation is unavailable for binomial.")
            }
        default: throw _CalculationError(message: "This operation is unavailable for the requested distribution.")
        }
        guard let value else { throw _CalculationError(message: "The distribution is undefined for these parameters.") }
        return ["value": nullable(value)]
    }

    /// Finds the first count at or above the cutoff with logarithmic CDF calls.
    private static func discreteQuantile(_ p: Double, upper: Int, cdf: (Int) -> Double?) throws -> Int {
        guard let upperProbability = cdf(upper), upperProbability >= p else {
            throw _CalculationError(message: "The quantile is outside the supported count range.")
        }
        var lower = 0
        var upper = upper
        while lower < upper {
            let midpoint = lower + (upper - lower) / 2
            guard let probability = cdf(midpoint) else {
                throw _CalculationError(message: "The cumulative probability could not be evaluated.")
            }
            if probability >= p {
                upper = midpoint
            } else {
                lower = midpoint + 1
            }
        }
        return lower
    }

    private static func eventCount(_ input: _CalculationInput) throws -> Int {
        try input.integer("k", within: -1_000_000_000...1_000_000_000)
    }

    static func histogram(_ input: _CalculationInput) throws -> [String: Any] {
        let values = try input.vector("values")
        try require(values.count <= 10_000, "Use at most 10,000 observations.")
        try require(input.contains("bins") != input.contains("rule"), "Supply either bins or rule.")
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        try require((maxValue - minValue).isFinite, "The range of values is too large.")
        let count: Int
        if input.contains("bins") {
            count = try input.integer("bins", within: 1...512)
        } else {
            let rule = try input.choice("rule", options: ["square_root", "sturges", "freedman_diaconis"])
            let n = Double(values.count)
            let sturges = Int(ceil(log2(n) + 1))
            switch rule {
            case "square_root":
                count = Int(ceil(sqrt(n)))
            case "freedman_diaconis":
                // Preflight the rule's conversion to Int and allocation.
                if let quartiles = values.quartiles(), quartiles.iqr > 0, maxValue > minValue {
                    let width = 2 * quartiles.iqr / pow(n, 1.0 / 3.0)
                    let bins = ceil((maxValue - minValue) / width)
                    try require(bins.isFinite && bins <= 512, "The bin rule requires more than 512 bins.")
                    count = max(1, Int(bins))
                } else {
                    count = sturges
                }
            default:
                count = sturges
            }
        }
        try require(maxValue == minValue || (maxValue - minValue) / Double(count) > 0,
                    "The bin width is too small to represent.")
        let bins = values.histogram(bins: count)
        return ["bins": bins.map { ["midpoint": $0.midpoint, "count": $0.count] as [String: Any] }]
    }

    static func contingency(_ input: _CalculationInput) throws -> [String: Any] {
        let rows = try input.strings("rowLabels")
        let columns = try input.strings("columnLabels")
        let counts = try boundedMatrix(input, "counts").map { row in
            try row.map { value in
                try require(value >= 0 && value <= 1_000_000_000 && value.rounded() == value,
                            "counts must contain nonnegative integers up to one billion.")
                return Int(value)
            }
        }
        try require(Set(rows).count == rows.count && Set(columns).count == columns.count,
                    "Row and column labels must be unique.")
        guard let table = ContingencyTable(rowLabels: rows, columnLabels: columns, counts: counts) else {
            throw _CalculationError(message: "Supply one count per row and column label pair.")
        }
        try require(table.grandTotal > 0, "At least one count must be positive.")
        let joint = table.jointDistribution()
        var result: [String: Any] = [
            "rowLabels": rows, "columnLabels": columns, "counts": counts, "rowTotals": table.rowTotals,
            "columnTotals": table.columnTotals, "grandTotal": table.grandTotal, "joint": joint,
            "conditionalByRow": table.conditionalByRow(), "conditionalByColumn": table.conditionalByColumn()
        ]
        if try input.boolean("compareIndependence", default: false) {
            let total = Double(table.grandTotal)
            let rowMarginals = table.rowTotals.map { Double($0) / total }
            let columnMarginals = table.columnTotals.map { Double($0) / total }
            // Under independence P(row and column) equals P(row) × P(column).
            let products = rowMarginals.map { row in columnMarginals.map { row * $0 } }
            result["independenceComparison"] = [
                "observedJoint": joint, "productOfMarginals": products,
                "rowMarginals": rowMarginals, "columnMarginals": columnMarginals
            ]
        }
        return result
    }

    static func bayes(_ input: _CalculationInput) throws -> [String: Any] {
        let groups = [
            ["prior", "likelihood", "evidence"], ["prior", "trueRate", "falsePositiveRate"],
            ["hypotheses", "priors", "likelihoods"]
        ]
        let supplied = Set(groups.flatMap { $0 }.filter { input.contains($0) })
        guard let group = groups.firstIndex(where: { Set($0) == supplied }) else {
            throw _CalculationError(message: "Supply a complete set of parameters for one Bayesian update.")
        }
        if group == 2 {
            let hypotheses = try input.strings("hypotheses")
            try require(hypotheses.count <= 10_000 && Set(hypotheses).count == hypotheses.count,
                        "Supply up to 10,000 unique hypothesis names.")
            guard let prior = try BayesPrior(hypotheses: hypotheses, probabilities: input.vector("priors")),
                  let likelihood = try BayesLikelihood(input.vector("likelihoods")),
                  let posterior = Bayes.posterior(prior: prior, likelihood: likelihood) else {
                throw _CalculationError(message: "The Bayesian update is undefined for these parameters.")
            }
            return ["hypotheses": posterior.hypotheses, "probabilities": posterior.probabilities]
        }
        let prior = try input.number("prior")
        let posterior = group == 0
            ? try Bayes.posterior(prior: prior, likelihood: input.number("likelihood"), evidence: input.number("evidence"))
            : try Bayes.posterior(prior: prior, trueRate: input.number("trueRate"), falsePositiveRate: input.number("falsePositiveRate"))
        guard let posterior else { throw _CalculationError(message: "The Bayesian update is undefined for these parameters.") }
        return ["probability": posterior]
    }

    static func samplingDistribution(_ input: _CalculationInput) throws -> [String: Any] {
        let values = try input.vector("values", minimumCount: 2)
        try require(values.count <= 10_000, "Use at most 10,000 observations.")
        let size = try input.integer("sampleSize", within: 2...10_000, default: values.count)
        let iterations = try input.integer("iterations", within: 2...10_000, default: 1000)
        let level = try input.number("level", default: 0.95)
        let seed = try seed(input)
        try require(size <= 5_000_000 / iterations, "Reduce sampleSize or iterations to at most five million draws.")
        try require(level > 0 && level < 1, "level must be between zero and one.")
        let replicates: [Double]
        switch try input.choice("statistic", options: ["mean", "median", "standard_deviation"]) {
        case "mean": replicates = values.samplingDistributionOfMean(sampleSize: size, iterations: iterations, seed: seed)
        case "median": replicates = values.samplingDistributionOfMedian(sampleSize: size, iterations: iterations, seed: seed)
        default:
            replicates = values.samplingDistributionOfStandardDeviation(sampleSize: size, iterations: iterations, seed: seed)
        }
        guard let interval = replicates.percentileCI(level: level) else {
            throw _CalculationError(message: "A percentile interval could not be computed.")
        }
        return ["replicates": replicates, "interval": ["lower": interval.lower, "upper": interval.upper], "level": level]
    }

    static func regression(_ input: _CalculationInput) throws -> [String: Any] {
        let features = try boundedMatrix(input, "features", minimumRows: 2)
        let targets = try input.targets(count: features.count)
        let intercept = try input.boolean("intercept", default: true)
        let level = try input.number("level", default: 0.95)
        try require(level > 0 && level < 1, "level must be between zero and one.")
        try require(features.count > features[0].count + (intercept ? 1 : 0),
                    "Regression inference requires more observations than fitted coefficients.")
        let model = try LinearRegression.fit(features: features, targets: targets, intercept: intercept)
        let summary = try model.summary(features: features, targets: targets, level: level)
        return [
            "coefficients": summary.coefficients.map { nullable($0) },
            "standardErrors": summary.standardErrors.map { nullable($0) },
            "tStatistics": summary.tStatistics.map { nullable($0) },
            "pValues": summary.pValues.map { nullable($0) },
            "confidenceIntervals": summary.confidenceIntervals.map {
                ["lower": nullable($0.lower), "upper": nullable($0.upper)]
            },
            "rSquared": nullable(summary.rSquared), "adjustedRSquared": nullable(summary.adjustedRSquared),
            "n": summary.n, "degreesOfFreedom": summary.degreesOfFreedom,
            "residualStandardError": nullable(summary.residualStandardError), "confidenceLevel": summary.confidenceLevel
        ]
    }

    static func evaluate(_ input: _CalculationInput) throws -> [String: Any] {
        let predictions = try input.vector("predictions")
        let actual = try input.targets("actual", count: predictions.count)
        try require(predictions.count <= 10_000, "Use at most 10,000 observations.")
        if try input.choice("kind", options: ["regression", "classification"]) == "regression" {
            try require(!input.contains("positiveLabel"), "positiveLabel applies only to classification.")
            return [
                "rSquared": nullable(predictions.rSquared(actual: actual)),
                "meanSquaredError": nullable(predictions.meanSquaredError(actual: actual)),
                "rootMeanSquaredError": nullable(predictions.rootMeanSquaredError(actual: actual))
            ]
        }
        let safeLabels = -9_007_199_254_740_991...9_007_199_254_740_991
        func labels(_ values: [Double]) throws -> [Int] {
            try values.map { value in
                guard let label = Int(exactly: value), safeLabels.contains(label) else {
                    throw _CalculationError(message: "Classification labels must be JSON-safe integers.")
                }
                return label
            }
        }
        let predictedLabels = try labels(predictions)
        let actualLabels = try labels(actual)
        let positiveLabel = try input.integer("positiveLabel", within: safeLabels, default: 1)
        let matrix = predictedLabels.confusionMatrix(actual: actualLabels, positiveLabel: positiveLabel)
        let counts = actualLabels.classDistribution()
        return [
            "classificationReport": try jsonObject(predictedLabels.classificationReport(actual: actualLabels)),
            "confusionMatrix": try jsonObject(matrix), "positiveLabel": positiveLabel,
            "classDistribution": counts.keys.sorted().map { ["label": $0, "count": counts[$0, default: 0]] },
            "imbalanceRatio": nullable(actualLabels.imbalanceRatio())
        ]
    }
}
