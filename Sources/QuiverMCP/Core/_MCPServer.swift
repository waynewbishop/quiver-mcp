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

/// Serves the Quiver calculation tools over a single MCP stdio connection.
///
/// The server owns protocol framing, lifecycle state, and tool result encoding.
/// Each tool passes its request data to ``_QuiverCalculation``. The server
/// retains only the handshake state between requests.
@_documentation(visibility: internal)
struct _MCPServer {
    /// Determines which requests the host can send during initialization.
    private var connection = Connection.awaitingInitialize

    /// Tracks the two messages that must arrive before tool discovery.
    private enum Connection {
        /// Awaits the host's initialization request and proposed protocol version.
        case awaitingInitialize
        /// Awaits the host's notification that initialization is complete.
        case awaitingInitialized
        /// Accepts tool discovery and execution requests.
        case ready
    }

    /// Processes newline-delimited JSON-RPC messages until stdin closes.
    ///
    /// Each calculation finishes before the loop reads the next message.
    /// Encoded JSON fits on one line even when a string contains line breaks.
    ///
    /// - Throws: An error when a response cannot be encoded or written.
    mutating func serve() throws {
        try serve(input: .standardInput, output: .standardOutput)
    }

    /// Frames bytes on LF and writes each response as soon as its frame is complete.
    /// - Parameters:
    ///   - input: The incoming byte stream.
    ///   - output: The JSON-RPC response stream.
    /// - Throws: An error when a response cannot be encoded or written.
    mutating func serve(input: FileHandle, output: FileHandle) throws {
        var frame = Data()
        while true {
            let chunk = input.availableData
            if chunk.isEmpty { break }

            var remaining = chunk[...]
            while let newline = remaining.firstIndex(of: 0x0A) {
                frame.append(contentsOf: remaining[..<newline])
                try writeResponse(to: frame, output: output)
                frame.removeAll(keepingCapacity: true)
                remaining = remaining[remaining.index(after: newline)...]
            }
            frame.append(contentsOf: remaining)
        }
        if !frame.isEmpty { try writeResponse(to: frame, output: output) }
    }

    /// Writes one response line when the request produces a response.
    private mutating func writeResponse(to frame: Data, output: FileHandle) throws {
        guard let response = try handle(frame) else { return }
        var encoded = try JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])
        encoded.append(0x0A)
        try output.write(contentsOf: encoded)
    }

    // MARK: - JSON-RPC lifecycle

    /// Validates a JSON-RPC envelope and preserves its request ID in the response.
    ///
    /// A request with an ID receives a result or an error bearing the same ID.
    /// The initialized notification advances the connection without writing a reply.
    ///
    /// - Parameter input: One UTF-8 message from the transport.
    /// - Returns: A response object or nil for a notification.
    /// - Throws: An error when the tool result cannot be serialized.
    private mutating func handle(_ input: Data) throws -> [String: Any]? {
        // Foundation autodetects UTF-16 and UTF-32, where ASCII JSON syntax
        // contains raw NUL bytes. A UTF-8 JSON frame may only escape a NUL.
        guard !input.contains(0), String(data: input, encoding: .utf8) != nil else {
            return Self.error(id: NSNull(), code: -32700, message: "Invalid UTF-8")
        }
        let message: Any
        do {
            message = try JSONSerialization.jsonObject(with: input, options: .fragmentsAllowed)
        } catch {
            return Self.error(id: NSNull(), code: -32700, message: "Parse error")
        }

        guard let request = message as? [String: Any],
              request["jsonrpc"] as? String == "2.0",
              let method = request["method"] as? String else {
            return Self.error(id: NSNull(), code: -32600, message: "Invalid Request")
        }

        let id = request["id"]
        if let id, !Self.isRequestIdentifier(id) {
            return Self.error(id: NSNull(), code: -32600, message: "Invalid request ID")
        }
        let parameters = request["params"] as? [String: Any]
        if request["params"] != nil && parameters == nil {
            return id.map { Self.error(id: $0, code: -32602, message: "MCP params must be an object") }
        }

        if let metadata = parameters?["_meta"], !(metadata is [String: Any]) {
            return id.map { Self.error(id: $0, code: -32602, message: "MCP params._meta must be an object") }
        }

        guard let id else {
            if method == "notifications/initialized", connection == .awaitingInitialized {
                connection = .ready
            }
            return nil
        }

        do {
            let result = try respond(to: method, parameters: parameters)
            return ["jsonrpc": "2.0", "id": id, "result": result]
        } catch let failure as RequestError {
            return Self.error(id: id, code: failure.code, message: failure.message)
        }
    }

    /// Negotiates initialization or dispatches a request permitted by the connection state.
    /// - Parameters:
    ///   - method: The JSON-RPC method name.
    ///   - parameters: The associated JSON parameters, when present.
    /// - Returns: The method result before it is wrapped in a JSON-RPC response.
    /// - Throws: A request error or a tool result serialization error.
    private mutating func respond(to method: String, parameters: [String: Any]?) throws -> [String: Any] {
        if method == "initialize" {
            guard connection == .awaitingInitialize else {
                throw RequestError(code: -32600, message: "Connection already initialized")
            }
            guard let values = parameters,
                  let requestedVersion = values["protocolVersion"] as? String,
                  values["capabilities"] is [String: Any],
                  let client = values["clientInfo"] as? [String: Any],
                  client["name"] is String, client["version"] is String else {
                throw RequestError(code: -32602, message: "Invalid initialization parameters")
            }
            let supportedVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
            connection = .awaitingInitialized
            return [
                "protocolVersion": supportedVersions.contains(requestedVersion) ? requestedVersion : "2025-11-25",
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "quiver-mcp", "version": "0.1.0"]
            ]
        }

        if method == "ping" { return [:] }

        guard connection == .ready else {
            throw RequestError(code: -32000, message: "Connection has not been initialized")
        }

        switch method {
        case "tools/list":
            let definitions = _QuiverCalculation.allCases.map(\.definition) + _QuiverDocs.allCases.map(\.definition)
            return ["tools": definitions]
        case "tools/call":
            guard let values = parameters, let name = values["name"] as? String else {
                throw RequestError(code: -32602, message: "Specify a tool name")
            }
            let arguments = values["arguments"] as? [String: Any]
            if values["arguments"] != nil && arguments == nil {
                throw RequestError(code: -32602, message: "Tool arguments must be an object")
            }
            return try callTool(named: name, arguments: arguments ?? [:])
        default:
            throw RequestError(code: -32601, message: "Method not found")
        }
    }

    /// Checks whether an ID can correlate a request and response.
    /// - Parameter value: The decoded JSON ID.
    /// - Returns: Whether the ID is a string or an integral JSON number.
    private static func isRequestIdentifier(_ value: Any) -> Bool {
        if value is String { return true }
        guard let number = value as? NSNumber, String(cString: number.objCType) != "c" else { return false }
        return number.doubleValue.isFinite && number.doubleValue.rounded() == number.doubleValue
    }

    /// Wraps a failure in a JSON-RPC error response.
    /// - Parameters:
    ///   - id: The request ID or a JSON null when the ID is unavailable.
    ///   - code: The JSON-RPC error code.
    ///   - message: A short explanation of the failure.
    /// - Returns: A response object suitable for the stdio transport.
    private static func error(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    // MARK: - Tools

    /// Dispatches a calculation or documentation request and wraps validation failures as tool errors.
    /// - Parameters:
    ///   - name: A registered tool name.
    ///   - arguments: The tool's input arguments.
    /// - Returns: The tool result or a tool error.
    /// - Throws: A request error for unknown tools or an encoding error.
    private func callTool(named name: String, arguments: [String: Any]) throws -> [String: Any] {
        if let documentation = _QuiverDocs(rawValue: name) {
            let fields: [String: Any]
            do {
                fields = try documentation.call(arguments: arguments)
            } catch {
                return try Self.toolResult(["error": error.localizedDescription], isError: true)
            }
            return try Self.toolResult(fields)
        }
        guard let calculation = _QuiverCalculation(rawValue: name) else {
            throw RequestError(code: -32602, message: "Unknown tool: \(name)")
        }

        let fields: [String: Any]
        do {
            fields = try calculation.calculate(arguments: arguments)
        } catch {
            return try Self.toolResult(["error": error.localizedDescription], isError: true)
        }
        return try Self.toolResult(fields)
    }

    /// Encodes the same result fields as structured data and as a text item.
    /// - Parameters:
    ///   - fields: The JSON-compatible fields returned by the tool.
    ///   - isError: Whether the tool reports a failure.
    /// - Returns: The MCP tool result.
    /// - Throws: An error when the fields cannot be serialized as JSON.
    private static func toolResult(_ fields: [String: Any], isError: Bool = false) throws -> [String: Any] {
        let encoded = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .withoutEscapingSlashes])
        let text = String(decoding: encoded, as: UTF8.self)
        return ["content": [["type": "text", "text": text]], "structuredContent": fields, "isError": isError]
    }

    /// Carries a failure reported in the JSON-RPC error envelope.
    private struct RequestError: Error, Equatable, Sendable {
        /// The numeric error code returned to the host.
        let code: Int
        /// The human-readable explanation of the error.
        let message: String
    }
}
