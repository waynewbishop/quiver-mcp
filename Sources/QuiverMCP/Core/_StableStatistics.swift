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

/// Supplies scaled statistics and fits for the Quiver 1.6.0 numerical adapters.
enum _StableStatistics {
    /// Summarizes finite samples using compensated summation and scaled deviations.
    /// - Parameter values: At least two finite observations.
    /// - Returns: Descriptive fields with the same quartile convention as Quiver.
    static func summarize(_ values: [Double]) -> [String: Any] {
        let sorted = values.sorted()
        let minimum = sorted[0]
        let maximum = sorted[sorted.count - 1]
        let moments = moments(values, degreesOfFreedom: 1)

        let firstQuartile = percentile(0.25, sorted: sorted)
        let median = percentile(0.5, sorted: sorted)
        let thirdQuartile = percentile(0.75, sorted: sorted)
        return [
            "count": values.count, "mean": moments.mean, "sampleStandardDeviation": moments.standardDeviation,
            "minimum": minimum, "firstQuartile": firstQuartile, "median": median,
            "thirdQuartile": thirdQuartile, "maximum": maximum,
            "interquartileRange": thirdQuartile - firstQuartile
        ]
    }

    /// Computes a compensated mean and scaled sample or population standard deviation.
    /// - Parameters:
    ///   - values: Nonempty finite observations.
    ///   - degreesOfFreedom: One for a sample or zero for a population.
    /// - Returns: The mean and standard deviation in the original units.
    static func moments(_ values: [Double], degreesOfFreedom: Double)
        -> (mean: Double, standardDeviation: Double)
    {
        let minimum = values.min() ?? 0.0
        let maximum = values.max() ?? 0.0
        let scale = powerOfTwo(for: max(abs(minimum), abs(maximum)))
        let scaled = values / scale
        let count = Double(values.count)
        let scaledMean = min(maximum / scale, max(minimum / scale, compensatedSum(scaled) / count))
        let rawSum = compensatedSum(values)
        let mean = rawSum.isFinite ? rawSum / count : scaledMean * scale

        // Center before rounding the mean back to the original units.
        let offsets = scaled - scaled[0]
        let deviations = offsets - (compensatedSum(offsets) / count)
        let normalizedDeviation = (deviations.dot(deviations) / (count - degreesOfFreedom)).squareRoot()
        return (mean, normalizedDeviation * scale)
    }

    /// Fits Quiver regression on centered, scaled coordinates and restores the caller's units.
    /// - Parameters:
    ///   - features: The nonconstant predictor values.
    ///   - targets: Responses paired with the predictor values.
    /// - Returns: A reference point and slope in the original units.
    /// - Throws: A Quiver fitting error or an error for an unrepresentable slope.
    static func centeredLine(features: [Double], targets: [Double]) throws
        -> (referenceResponse: Double, referencePredictor: Double, slope: Double)
    {
        let x = Coordinates(features)
        guard features.min() != features.max() else {
            throw _CalculationError(message: "Linear regression requires at least two distinct predictor values.")
        }
        let y = Coordinates(targets)
        let model = try LinearRegression.fit(features: x.values, targets: y.values)
        let scaledSlope = model.coefficients[1] * (y.span / x.span)
        let slope = rescale(scaledSlope, by: y.scale.exponent - x.scale.exponent)
        guard slope.isFinite, slope != 0.0 || scaledSlope == 0.0 else {
            throw _CalculationError(message: "The slope is outside the representable range.")
        }

        return (referenceResponse: y.center.addingProduct(model.coefficients[0], y.span) * y.scale,
                referencePredictor: x.center * x.scale, slope: slope)
    }

    /// Returns the prediction and original-unit coefficients for the scalar MCP tool.
    static func fitLine(features: [Double], targets: [Double], predictions: [Double]?) throws -> [String: Any] {
        let line = try centeredLine(features: features, targets: targets)
        let intercept = line.referenceResponse.addingProduct(-line.slope, line.referencePredictor)
        var result: [String: Any] = ["intercept": intercept, "slope": line.slope]
        if let predictions {
            result["predictions"] = evaluateLine(line, intercept: intercept, at: predictions)
        }
        return result
    }

    /// Evaluates a centered fit without cancellation between a large intercept and predictor.
    static func evaluateLine(
        _ line: (referenceResponse: Double, referencePredictor: Double, slope: Double),
        intercept: Double, at values: [Double]
    ) -> [Double] {
        var predictions: [Double] = []
        predictions.reserveCapacity(values.count)
        for value in values {
            let offset = value - line.referencePredictor
            let prediction = offset.isFinite ? line.referenceResponse.addingProduct(line.slope, offset)
                : intercept.addingProduct(line.slope, value)
            predictions.append(prediction)
        }
        return predictions
    }

    /// Uses a power-of-two scale so that division preserves nearby representable values.
    static func powerOfTwo(for magnitude: Double) -> Double {
        guard magnitude > 0.0 else { return 1.0 }
        return Double(sign: .plus, exponent: magnitude.exponent, significand: 1.0)
    }

    /// Shifts the binary exponent without first constructing a potentially overflowing factor.
    static func rescale(_ value: Double, by exponent: Int) -> Double {
        guard value.isFinite, value != 0.0 else { return value }
        return Double(sign: value.sign, exponent: value.exponent + exponent, significand: abs(value.significand))
    }

    /// Accumulates low-order terms lost by ordinary floating-point summation.
    static func compensatedSum(_ values: [Double]) -> Double {
        var sum = 0.0
        var correction = 0.0
        for value in values {
            let next = sum + value
            if !next.isFinite { return next }
            correction += abs(sum) >= abs(value) ? (sum - next) + value : (value - next) + sum
            sum = next
        }
        return sum + correction
    }

    /// Interpolates adjacent sorted values using Quiver's fractional rank convention.
    private static func percentile(_ fraction: Double, sorted: [Double]) -> Double {
        let position = fraction * Double(sorted.count - 1)
        let index = Int(position)
        let lower = sorted[index]
        let upper = sorted[min(index + 1, sorted.count - 1)]
        let weight = position - Double(index)
        let difference = upper - lower
        if difference.isFinite { return lower.addingProduct(weight, difference) }
        return (lower * (1.0 - weight)).addingProduct(weight, upper)
    }

    /// Represents a vector in centered coordinates bounded by its observed span.
    private struct Coordinates {
        let scale: Double
        let center: Double
        let span: Double
        let values: [Double]

        /// Centers in scaled units so opposite-sign endpoints cannot overflow.
        init(_ original: [Double]) {
            let minimum = original.min() ?? 0.0
            let maximum = original.max() ?? 0.0
            let scale = powerOfTwo(for: max(abs(minimum), abs(maximum)))
            let lower = minimum / scale
            let upper = maximum / scale
            let center = (lower + upper) * 0.5
            let span = lower == upper ? 1.0 : upper - lower
            self.scale = scale
            self.center = center
            self.span = span
            self.values = ((original / scale) - center) / span
        }
    }
}
