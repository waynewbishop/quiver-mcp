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

/// Reads JSON arguments before they reach Quiver's model APIs.
struct _CalculationInput {
    /// The fields from the current request.
    private let values: [String: Any]

    /// Rejects missing required fields and unknown fields.
    init(_ values: [String: Any], contract: _CalculationContract) throws {
        let missing = contract.required.keys.filter { values[$0] == nil }.sorted()
        guard missing.isEmpty else {
            throw _CalculationError(message: "Missing arguments: \(missing.joined(separator: ", ")).")
        }
        let unknown = values.keys.filter { contract.required[$0] == nil && contract.optional[$0] == nil }.sorted()
        guard unknown.isEmpty else {
            throw _CalculationError(message: "Unexpected arguments: \(unknown.joined(separator: ", ")).")
        }
        self.values = values
    }

    /// Reads a finite number or applies an explicit default when the field is absent.
    func number(_ name: String, default fallback: Double? = nil) throws -> Double {
        if values[name] == nil, let fallback { return fallback }
        return try Self.number(values[name], named: name)
    }

    /// Reads an exact integer constrained to the argument's allowed range.
    func integer(_ name: String, within range: ClosedRange<Int>, default fallback: Int? = nil) throws -> Int {
        if values[name] == nil, let fallback { return fallback }
        let number = try number(name)
        guard let value = Int(exactly: number), range.contains(value) else {
            throw _CalculationError(message: "\(name) must be an integer from \(range.lowerBound) to \(range.upperBound).")
        }
        return value
    }

    /// Reads an optional nonnegative seed.
    func seed() throws -> UInt64? {
        guard values["seed"] != nil else { return nil }
        let number = try number("seed")
        guard let seed = UInt64(exactly: number), seed <= 9_007_199_254_740_991 else {
            throw _CalculationError(message: "seed must be a nonnegative JSON-safe integer.")
        }
        return seed
    }

    /// Reports whether an optional field was supplied.
    func contains(_ name: String) -> Bool { values[name] != nil }

    /// Reads a string from a fixed set of supported values.
    func choice(_ name: String, options: [String]) throws -> String {
        guard let value = values[name] as? String, options.contains(value) else {
            throw _CalculationError(message: "\(name) must be one of: \(options.joined(separator: ", ")).")
        }
        return value
    }

    /// Reads a nonblank display name or applies the default when absent.
    /// - Parameters:
    ///   - name: The argument key.
    ///   - fallback: The value to use when the argument is absent.
    /// - Returns: The validated name.
    /// - Throws: A calculation error for an invalid or oversized name.
    func string(_ name: String, default fallback: String) throws -> String {
        guard let raw = values[name] else { return fallback }
        guard let value = raw as? String, value.count <= 128,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw _CalculationError(message: "\(name) must be a nonempty string of at most 128 characters.")
        }
        return value
    }

    /// Reads a nonempty string array.
    func strings(_ name: String) throws -> [String] {
        guard let strings = values[name] as? [String], !strings.isEmpty else {
            throw _CalculationError(message: "\(name) must be a nonempty array of strings.")
        }
        return strings
    }

    /// Reads a JSON boolean or applies a default when absent.
    func boolean(_ name: String, default fallback: Bool) throws -> Bool {
        guard let raw = values[name] else { return fallback }
        guard let number = raw as? NSNumber, String(cString: number.objCType) == "c" else {
            throw _CalculationError(message: "\(name) must be a boolean.")
        }
        return number.boolValue
    }

    /// Reads finite numeric values with a minimum length.
    func vector(_ name: String, minimumCount: Int = 1) throws -> [Double] {
        try Self.vector(values[name], named: name, minimumCount: minimumCount)
    }

    /// Reads a vector if the caller supplied it.
    func optionalVector(_ name: String) throws -> [Double]? {
        guard contains(name) else { return nil }
        return try vector(name)
    }

    /// Reads a nonempty rectangular matrix with finite values.
    func matrix(_ name: String, minimumRows: Int = 1, width: Int? = nil) throws -> [[Double]] {
        guard let rows = values[name] as? [Any], rows.count >= minimumRows,
              let first = rows.first as? [Any], !first.isEmpty else {
            throw _CalculationError(message: "\(name) must contain at least \(minimumRows) nonempty rows.")
        }
        let columns = width ?? first.count
        return try rows.map { row in
            let row = try Self.vector(row, named: name, minimumCount: 1)
            guard row.count == columns else {
                throw _CalculationError(message: "Each row in \(name) must have \(columns) values.")
            }
            return row
        }
    }

    /// Reads prediction rows when supplied and validates their feature count.
    func predictionRows(width: Int) throws -> [[Double]] {
        guard contains("predict") else { return [] }
        return try matrix("predict", width: width)
    }

    /// Reads numeric targets paired with the supplied row count.
    func targets(_ name: String = "targets", count: Int) throws -> [Double] {
        let targets = try vector(name)
        guard targets.count == count else {
            throw _CalculationError(message: "\(name) must contain one value per corresponding row.")
        }
        return targets
    }

    /// Reads integer class labels paired with the supplied row count.
    func labels(count: Int) throws -> [Int] {
        try targets("labels", count: count).map { number in
            guard let label = Int(exactly: number), abs(number) <= 9_007_199_254_740_991 else {
                throw _CalculationError(message: "labels must contain JSON-safe integers.")
            }
            return label
        }
    }

    /// Reads the complete series of timestamped workout samples.
    func samples() throws -> [[String: Any]] {
        guard let samples = values["samples"] as? [[String: Any]], samples.count >= 2 else {
            throw _CalculationError(message: "samples must contain at least two sample objects.")
        }
        return samples
    }

    /// Reads a finite JSON number while rejecting booleans.
    static func number(_ value: Any?, named name: String) throws -> Double {
        guard let number = value as? NSNumber, String(cString: number.objCType) != "c",
              number.doubleValue.isFinite else {
            throw _CalculationError(message: "\(name) must contain only finite numbers.")
        }
        return number.doubleValue
    }

    /// Reads a JSON array of finite numbers.
    private static func vector(_ value: Any?, named name: String, minimumCount: Int) throws -> [Double] {
        guard let values = value as? [Any], values.count >= minimumCount else {
            throw _CalculationError(message: "\(name) requires at least \(minimumCount) numeric values.")
        }
        return try values.map { try number($0, named: name) }
    }
}
