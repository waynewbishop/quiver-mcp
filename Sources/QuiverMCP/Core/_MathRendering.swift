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

enum _MathRendering {
    static var contract: _CalculationContract {
        let number = ["type": "number"]
        let vector = ["type": "array", "items": number] as [String: Any]
        return .init(
            "Render a scalar, vector, matrix, polynomial, or regression equation as Unicode. Fractions render directly for scalars, vectors, and matrices; polynomial and model fractions describe the coefficients.",
            required: ["kind": ["type": "string", "enum": ["scalar", "vector", "matrix", "polynomial", "model"]]],
            optional: [
                "value": number, "vector": vector, "matrix": ["type": "array", "items": vector],
                "coefficients": vector,
                "asFractions": ["type": "boolean"],
                "maxDenominator": ["type": "integer", "minimum": 1, "maximum": 1000],
                "vectorForm": ["type": "string", "enum": ["column", "inline"]],
                "relativeZeroTolerance": ["type": "number", "minimum": 0],
                "modelForm": ["type": "string", "enum": ["linear", "log_odds", "probability"]],
                "hasIntercept": ["type": "boolean"],
                "variables": ["type": "array", "items": ["type": "string"]],
                "response": ["type": "string"]
            ]
        )
    }

    /// Renders a numeric result and preserves the supplied values alongside the display.
    /// - Parameter input: The type, numeric values, and display options from the MCP request.
    /// - Returns: The expression, numeric input, and requested rational representations.
    /// - Throws: A calculation error for invalid shapes, display options, or fraction ranges.
    static func render(_ input: _CalculationInput) throws -> [String: Any] {
        let kind = try input.choice("kind", options: ["scalar", "vector", "matrix", "polynomial", "model"])
        let fractionForm = try input.boolean("asFractions", default: false)
        try _QuiverCalculation.require(fractionForm || !input.contains("maxDenominator"),
                                       "maxDenominator requires asFractions to be true.")
        let maxDenominator = try input.integer("maxDenominator", within: 1...1000, default: 1000)
        var result: [String: Any] = ["kind": kind]
        switch kind {
        case "scalar":
            try validateOptions(input, allowing: ["value"])
            let value = try input.number("value")
            result["value"] = value
            if fractionForm {
                try validateFractionRange([value], maxDenominator: maxDenominator)
                let fraction = value.asFraction(maxDenominator: maxDenominator)
                result["expression"] = fraction.asExpression()
                result["fractions"] = fractionFields(fraction)
            } else {
                result["expression"] = [value].asExpression()
            }
        case "vector":
            try validateOptions(input, allowing: ["vector", "vectorForm"])
            let vector = try input.vector("vector", minimumCount: 0)
            try _QuiverCalculation.require(vector.count <= 1_000, "Render at most 1,000 values.")
            let requestedForm = try input.contains("vectorForm")
                ? input.choice("vectorForm", options: ["column", "inline"]) : "column"
            let form: VectorForm = requestedForm == "inline" ? .inline : .column
            result["vector"] = vector
            if fractionForm {
                try validateFractionRange(vector, maxDenominator: maxDenominator)
                let fractions = vector.asFractions(maxDenominator: maxDenominator)
                result["expression"] = fractions.asExpression(form: form)
                result["fractions"] = fractions.map(fractionFields)
            } else {
                result["expression"] = vector.asExpression(form: form)
            }
        case "matrix":
            try validateOptions(input, allowing: ["matrix"])
            let matrix = try _QuiverCalculation.boundedMatrix(input, "matrix")
            try _QuiverCalculation.require(matrix.count <= 1_000 / matrix[0].count, "Render at most 1,000 values.")
            result["matrix"] = matrix
            if fractionForm {
                try validateFractionRange(matrix.flatMap { $0 }, maxDenominator: maxDenominator)
                let fractions = matrix.asFractions(maxDenominator: maxDenominator)
                result["expression"] = fractions.asExpression()
                result["fractions"] = fractions.map { $0.map(fractionFields) }
            } else {
                result["expression"] = matrix.asExpression()
            }
        default:
            let coefficients = try input.vector("coefficients")
            try _QuiverCalculation.require(coefficients.count <= 1_000, "Render at most 1,000 coefficients.")
            result["coefficients"] = coefficients
            if kind == "polynomial" {
                try validateOptions(input, allowing: ["coefficients", "relativeZeroTolerance"])
                let tolerance = try input.number("relativeZeroTolerance", default: 1e-12)
                try _QuiverCalculation.require(tolerance >= 0.0, "relativeZeroTolerance must be nonnegative.")
                result["expression"] = Polynomial(coefficients).asExpression(relativeZeroTolerance: tolerance)
            } else {
                try validateOptions(input, allowing: ["coefficients", "modelForm", "hasIntercept", "variables", "response"])
                result["expression"] = try modelExpression(input, coefficients: coefficients)
            }
            if fractionForm {
                try validateFractionRange(coefficients, maxDenominator: maxDenominator)
                result["fractions"] = coefficients.asFractions(maxDenominator: maxDenominator).map(fractionFields)
            }
        }
        return result
    }

    /// Renders an intercept-first regression equation using Quiver's coefficient formatter.
    /// - Parameters:
    ///   - input: The intercept flag, equation form, and optional variable and response names.
    ///   - coefficients: The supplied intercept and weights, or weights alone.
    /// - Returns: The linear, log-odds, or sigmoid equation.
    /// - Throws: A calculation error when labels do not match the equation.
    private static func modelExpression(_ input: _CalculationInput, coefficients: [Double]) throws -> String {
        let hasIntercept = try input.boolean("hasIntercept", default: true)
        let form = try input.contains("modelForm")
            ? input.choice("modelForm", options: ["linear", "log_odds", "probability"]) : "linear"
        let model = _EquationCoefficients(coefficients: coefficients, hasIntercept: hasIntercept)
        let response = try input.string("response", default: "y")
        try _QuiverCalculation.require(form == "linear" || !input.contains("response"),
                                       "response is only available for linear equations.")
        let equation: String
        if input.contains("variables") {
            let variables = try input.strings("variables")
            let weightCount = coefficients.count - (hasIntercept ? 1 : 0)
            try _QuiverCalculation.require(variables.count == weightCount && variables.allSatisfy {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 128
            }, "Supply one nonempty variable name of at most 128 characters per model weight.")
            equation = model.equation(variables: variables)
        } else {
            equation = model.equation()
        }

        // Quiver formats the linear score for all three forms. Logistic equations
        // display that score as log-odds or place it inside the sigmoid.
        let score = equation.dropFirst("y = ".count)
        switch form {
        case "log_odds": return "log-odds = " + score
        case "probability": return "p = σ(" + score + ")"
        default: return response + " = " + score
        }
    }

    /// Rejects rendering fields that belong to a different kind.
    /// - Parameters:
    ///   - input: The request to validate.
    ///   - allowed: Kind-specific fields that are meaningful for the selected renderer.
    /// - Throws: A calculation error naming the mismatched arguments.
    private static func validateOptions(_ input: _CalculationInput, allowing allowed: Set<String>) throws {
        let common: Set<String> = ["kind", "asFractions", "maxDenominator"]
        let supplied = Set(contract.optional.keys.filter { input.contains($0) })
        let unexpected = supplied.subtracting(common.union(allowed)).sorted()
        try _QuiverCalculation.require(unexpected.isEmpty,
                                       "Unexpected rendering arguments: " + unexpected.joined(separator: ", ") + ".")
    }

    /// Bounds potential numerators to the JSON-safe integer range before calling Quiver.
    /// - Parameters:
    ///   - values: The finite values to convert.
    ///   - maxDenominator: The largest denominator to consider.
    /// - Throws: A calculation error if a potential numerator is too large.
    private static func validateFractionRange(_ values: [Double], maxDenominator: Int) throws {
        let maximum = Foundation.floor(9_007_199_254_740_991.0 / Double(maxDenominator))
        try _QuiverCalculation.require(values.allSatisfy { abs($0) <= maximum },
                                       "Values are too large for JSON-safe numerators at this denominator limit.")
    }

    /// Converts a Quiver fraction to structured JSON fields.
    /// - Parameter fraction: The rational approximation returned by Quiver.
    /// - Returns: The numerator and positive denominator.
    private static func fractionFields(_ fraction: Fraction) -> [String: Int] {
        ["numerator": fraction.numerator, "denominator": fraction.denominator]
    }
}
