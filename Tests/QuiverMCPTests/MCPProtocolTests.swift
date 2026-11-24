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
import Testing
@testable import QuiverMCP

struct MCPProtocolTests {
    private let initialize = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}"#
    private let initialized = #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#

    @Test func malformedNotificationCannotCompleteInitialization() throws {
        let replies = try exchange([
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
            #"{"jsonrpc":"2.0","id":0,"method":"tools/list"}"#,
            initialize,
            #"{"jsonrpc":"2.0","method":"notifications/initialized","params":7}"#,
            #"{"jsonrpc":"2.0","method":"notifications/initialized","params":{"_meta":false}}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#,
            initialized,
            #"{"jsonrpc":"2.0","id":3,"method":"tools/list"}"#
        ])
        try #require(replies.count == 4)
        #expect(Self.code(replies[0]) == -32000)
        #expect(replies[1]["result"] != nil)
        #expect(Self.code(replies[2]) == -32000)
        let result = try #require(replies[3]["result"] as? [String: Any])
        #expect((result["tools"] as? [[String: Any]])?.count == 49)
    }

    @Test func documentationSearchReturnsReadableVersionedSections() throws {
        let replies = try exchange([
            initialize, initialized,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"search_quiver_docs","arguments":{"query":"RidgeRegression"}}}"#,
            #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"search_quiver_docs","arguments":{"query":"zzzznonexistentquiverterm"}}}"#,
            #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"read_quiver_doc","arguments":{"section_id":"../../LICENSE"}}}"#
        ])
        let search = try #require(replies[1]["result"] as? [String: Any])
        let fields = try #require(search["structuredContent"] as? [String: Any])
        let matches = try #require(fields["matches"] as? [[String: String]])
        let match = try #require(matches.first)
        #expect(matches.count == 5)
        #expect(match["title"] == "Ridge Regression")
        #expect(fields["quiverVersion"] as? String == _QuiverDocCorpus.version)
        let empty = replies[2]["result"] as? [String: Any]
        #expect((empty?["structuredContent"] as? [String: Any])?["matches"] as? [[String: String]] == [])
        #expect((replies[3]["result"] as? [String: Any])?["isError"] as? Bool == true)

        let id = try #require(match["section_id"])
        let read = try exchange([
            initialize, initialized,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"read_quiver_doc","arguments":{"section_id":"\#(id)"}}}"#
        ])
        let result = try #require(read[1]["result"] as? [String: Any])
        let section = try #require(result["structuredContent"] as? [String: String])
        #expect(result["isError"] as? Bool == false)
        #expect(section["section_id"] == id)
        #expect(section["source"] == match["source"])
        #expect(section["source"]?.hasPrefix("https://github.com/waynewbishop/quiver/blob/") == true)
        #expect(section["markdown"]?.isEmpty == false)
    }

    @Test func rotationUsesThePrimerAndMatchesItsRowDotProducts() throws {
        let search = try tool("search_quiver_docs", arguments: #"{"query":"transformedBy"}"#)
        let matches = try #require(search["matches"] as? [[String: String]])
        let first = try #require(matches.first)
        #expect(first["title"] == "Linear Algebra Primer")
        #expect(first["heading"] == "Overview / What matrices do")
        let section = try #require(first["section_id"])
        let document = try tool("read_quiver_doc", arguments: #"{"section_id":"\#(section)"}"#)
        #expect(document["source"] as? String == first["source"])
        #expect(document["quiverVersion"] as? String == "1.7.0")
        #expect((document["markdown"] as? String)?.contains("point.transformedBy(rotation)") == true)

        let rotation = try tool("multiply_matrix_vector", arguments: #"{"matrix":[[0,-1],[1,0]],"vector":[3,1]}"#)
        let firstRow = try tool("dot_product", arguments: #"{"left":[0,-1],"right":[3,1]}"#)
        let secondRow = try tool("dot_product", arguments: #"{"left":[1,0],"right":[3,1]}"#)
        let vector = try #require(rotation["vector"] as? [Double])
        #expect(vector == [-1.0, 3.0])
        #expect(firstRow["dotProduct"] as? Double == vector.first)
        #expect(secondRow["dotProduct"] as? Double == vector.last)
    }

    @Test func projectionHandlesWidelyDifferentComponentMagnitudes() throws {
        let small = try tool("project_vector", arguments: #"{"vector":[1e308,1e-308],"onto":[0,1]}"#)
        #expect(small["vector"] as? [Double] == [0.0, 1e-308])

        let large = try tool("project_vector", arguments: #"{"vector":[1.7e308,1.7e308],"onto":[1,1]}"#)
        let values = try #require(large["vector"] as? [Double])
        #expect(values.count == 2)
        #expect(values.allSatisfy { abs($0 / 1.7e308 - 1.0) < 1e-12 })
    }

    @Test func inverseRendersAsFractionsWithoutLosingNumericValues() throws {
        let inverse = try tool("invert_matrix", arguments: #"{"matrix":[[3,1],[2,5]]}"#)
        let matrix = try #require(inverse["matrix"] as? [[Double]])
        let result = try tool("render_math", arguments: #"{"kind":"matrix","matrix":\#(matrix),"asFractions":true}"#)
        #expect(result["matrix"] as? [[Double]] == matrix)
        #expect(result["fractions"] as? [[[String: Int]]] == [
            [["numerator": 5, "denominator": 13], ["numerator": -1, "denominator": 13]],
            [["numerator": -2, "denominator": 13], ["numerator": 3, "denominator": 13]]
        ])
        #expect((result["expression"] as? String)?.contains("5/13") == true)
    }

    @Test func independenceComparisonIsOptInAndPreservesTableOrder() throws {
        let arguments = #""rowLabels":["Spam","Legitimate"],"columnLabels":["Phrase","No phrase"],"counts":[[12,8],[3,77]]"#
        let existing = try tool("contingency_table", arguments: "{\(arguments)}")
        #expect(existing["independenceComparison"] == nil)
        let result = try tool("contingency_table", arguments: "{\(arguments),\"compareIndependence\":true}")
        let comparison = try #require(result["independenceComparison"] as? [String: Any])
        #expect(comparison["observedJoint"] as? [[Double]] == [[0.12, 0.08], [0.03, 0.77]])
        let products = try #require(comparison["productOfMarginals"] as? [[Double]])
        #expect(products == [[0.2 * 0.15, 0.2 * 0.85], [0.8 * 0.15, 0.8 * 0.85]])
    }

    @Test func bernoulliReportsSmoothedProbabilitiesInLabelOrder() throws {
        let result = try tool("fit_bernoulli_naive_bayes", arguments:
            #"{"features":[[1],[0]],"labels":[9,-2],"predict":[[1],[0]]}"#)
        #expect(result["alpha"] as? Double == 1.0)
        #expect(result["classLabels"] as? [Int] == [-2, 9])
        #expect(result["predictedLabels"] as? [Int] == [9, -2])
        let probabilities = try #require(result["probabilities"] as? [[Double]])
        let present = try #require(probabilities.first?.last)
        let absent = try #require(probabilities.last?.first)
        #expect(abs(present - 2.0 / 3.0) < 1e-12)
        #expect(abs(absent - 2.0 / 3.0) < 1e-12)

        let fitted = try tool("fit_bernoulli_naive_bayes", arguments:
            #"{"features":[[1]],"labels":[9],"alpha":0.5}"#)
        let classes = try #require(fitted["classes"] as? [[String: Any]])
        #expect(classes.first?["featureProbabilities"] as? [Double] == [0.75])
        #expect(fitted["predictedLabels"] == nil)
    }

    @Test func bernoulliRejectsInvalidInputsBeforeFitting() throws {
        let invalid = [
            #"{"features":[[0.5]],"labels":[1]}"#,
            #"{"features":[[0]],"labels":[1],"predict":[[2]]}"#,
            #"{"features":[[0]],"labels":[1],"predict":[[0,1]]}"#,
            #"{"features":[[0]],"labels":[1],"alpha":0}"#,
            #"{"features":[[1]],"labels":[1],"alpha":1e-100}"#,
            #"{"features":[[1]],"labels":[1],"alpha":1e308}"#
        ]
        for arguments in invalid {
            let request = #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"fit_bernoulli_naive_bayes","arguments":\#(arguments)}}"#
            let responses = try exchange([initialize, initialized, request])
            let response = try #require(responses.last?["result"] as? [String: Any])
            #expect(response["isError"] as? Bool == true)
        }
    }

    @Test func invalidParametersAndToolErrorsHaveDifferentEnvelopes() throws {
        let replies = try exchange([
            initialize, initialized,
            #"{"jsonrpc":"2.0","id":2,"method":"ping","params":7}"#,
            #"{"jsonrpc":"2.0","id":3,"method":"tools/list","params":7}"#,
            #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"vector_summary","arguments":7}}"#,
            #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"vector_summary","arguments":{"values":[1]}}}"#,
            #"{"jsonrpc":"2.0","id":6,"method":"ping","params":{}}"#
        ])
        try #require(replies.count == 6)
        for index in 1...3 {
            #expect(Self.code(replies[index]) == -32602)
            #expect(replies[index]["result"] == nil)
        }
        let toolResult = try #require(replies[4]["result"] as? [String: Any])
        #expect(toolResult["isError"] as? Bool == true)
        #expect(replies[5]["result"] != nil)
    }

    @Test func invalidUTF8IsRejectedWithoutLosingTheNextFrame() throws {
        var bytes = Data((initialize + "\r\n" + initialized + "\n").utf8)
        bytes.append(contentsOf: #"{"jsonrpc":"2.0","id":7,"method":"ping","params":{"text":""#.utf8)
        bytes.append(0xFF)
        bytes.append(contentsOf: "\"}}\n".utf8)
        let utf16 = try #require(#"{"jsonrpc":"2.0","id":9,"method":"ping"}"#.data(using: .utf16LittleEndian))
        bytes.append(utf16)
        bytes.append(0x0A)
        bytes.append(contentsOf: #"{"jsonrpc":"2.0","id":8,"method":"ping"}"#.utf8)
        let replies = try exchange(bytes)
        try #require(replies.count == 4)
        #expect(Self.code(replies[1]) == -32700)
        #expect(Self.code(replies[2]) == -32700)
        #expect(replies[3]["id"] as? Int == 8)
        #expect(replies[3]["result"] != nil)
    }

    /// Calls an MCP tool in an initialized session and decodes its structured response.
    /// - Parameters:
    ///   - name: The name advertised in tool discovery.
    ///   - arguments: The JSON object for the tool call.
    /// - Returns: The structured result of the tool.
    /// - Throws: A transport or test requirement error if the tool call fails.
    private func tool(_ name: String, arguments: String) throws -> [String: Any] {
        let request = #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"\#(name)","arguments":\#(arguments)}}"#
        let responses = try exchange([initialize, initialized, request])
        let response = try #require(responses.last?["result"] as? [String: Any])
        #expect(response["isError"] as? Bool == false)
        return try #require(response["structuredContent"] as? [String: Any])
    }

    /// Exchanges complete wire frames using the production stdio framing loop.
    private func exchange(_ lines: [String]) throws -> [[String: Any]] {
        try exchange(Data((lines.joined(separator: "\n") + "\n").utf8))
    }

    /// Feeds raw bytes through the framing loop and decodes each response independently.
    private func exchange(_ bytes: Data) throws -> [[String: Any]] {
        let input = Pipe()
        let output = Pipe()
        try input.fileHandleForWriting.write(contentsOf: bytes)
        try input.fileHandleForWriting.close()
        var server = _MCPServer()
        try server.serve(input: input.fileHandleForReading, output: output.fileHandleForWriting)
        try output.fileHandleForWriting.close()
        let bytesRead = try output.fileHandleForReading.readToEnd()
        let responses = try #require(bytesRead)
        #expect(responses.last == 0x0A)
        return try responses.split(separator: 0x0A).map { frame in
            let decoded = try JSONSerialization.jsonObject(with: Data(frame))
            return try #require(decoded as? [String: Any])
        }
    }

    /// Reads a JSON-RPC error code from a response, when present.
    private static func code(_ response: [String: Any]) -> Int? {
        (response["error"] as? [String: Any])?["code"] as? Int
    }
}
