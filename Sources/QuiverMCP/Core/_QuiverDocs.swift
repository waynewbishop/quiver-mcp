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

enum _QuiverDocs: String, CaseIterable {
    case search = "search_quiver_docs"
    case read = "read_quiver_doc"

    var definition: [String: Any] {
        let parameter: String
        let description: String
        switch self {
        case .search:
            parameter = "query"
            description = "Find relevant sections of Quiver’s versioned DocC documentation by topic or Swift API name. Returns excerpts and section IDs. Use read_quiver_doc to retrieve the full section before explaining Quiver behavior."
        case .read:
            parameter = "section_id"
            description = "Read one section of Quiver’s versioned DocC documentation using an ID from search_quiver_docs. Returns original Markdown and a source URL for citation."
        }
        return [
            "name": rawValue,
            "description": description,
            "inputSchema": [
                "type": "object",
                "properties": [parameter: ["type": "string", "minLength": 1, "maxLength": 512]],
                "required": [parameter],
                "additionalProperties": false
            ],
            "annotations": ["readOnlyHint": true, "openWorldHint": false]
        ]
    }

    func call(arguments: [String: Any]) throws -> [String: Any] {
        let parameter = self == .search ? "query" : "section_id"
        guard arguments.count == 1, let value = arguments[parameter] as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.count <= 512 else {
            throw Failure(message: "Specify \(parameter) as a nonempty string of at most 512 characters.")
        }

        let index = try Self.index.get()
        switch self {
        case .search:
            return ["quiverVersion": _QuiverDocCorpus.version, "matches": index.search(value)]
        case .read:
            guard let section = index.sections[value] else {
                throw Failure(message: "Unknown section ID. Use search_quiver_docs to find a section.")
            }
            var fields = section.metadata
            fields["markdown"] = section.markdown
            fields["quiverVersion"] = _QuiverDocCorpus.version
            return fields
        }
    }

    private static let index = Result { try Index() }

    private struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private struct Section: Decodable, Sendable {
        let id: String
        let title: String
        let heading: String
        let markdown: String
        let source: String

        var metadata: [String: String] {
            ["section_id": id, "title": title, "heading": heading, "source": source]
        }

        var excerpt: String {
            let text = markdown.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return text.count > 240 ? String(text.prefix(240)) + "…" : text
        }
    }

    private struct Index: Sendable {
        private struct Posting: Sendable {
            let id: String
            let weight: Double
        }

        let sections: [String: Section]
        private let postings: [String: [Posting]]

        init() throws {
            let corpus = try JSONDecoder().decode([Section].self, from: Data(_QuiverDocCorpus.json.utf8))
            sections = Dictionary(uniqueKeysWithValues: corpus.map { ($0.id, $0) })
            var postings: [String: [Posting]] = [:]
            for section in corpus {
                var frequencies: [String: Int] = [:]
                for word in Self.words(section.markdown) {
                    frequencies[word, default: 0] += 1
                }
                var weights = frequencies.mapValues { Double($0) / (Double($0) + 2) }
                for word in Set(Self.words(section.title + " " + section.id)) {
                    weights[word, default: 0] += 3
                }
                for word in Set(Self.words(section.heading)) {
                    weights[word, default: 0] += 2
                }
                for (word, weight) in weights {
                    postings[word, default: []].append(Posting(id: section.id, weight: weight))
                }
            }
            self.postings = postings
        }

        func search(_ query: String) -> [[String: String]] {
            let words = Set(Self.words(query)).subtracting(Self.stopWords).sorted()
            var scores: [String: Double] = [:]
            for word in words {
                guard let matches = postings[word] else { continue }
                let rarity = log1p(Double(sections.count) / Double(matches.count))
                for match in matches {
                    scores[match.id, default: 0] += match.weight * rarity
                }
            }
            // Prefer the canonical worked example for an explicit API lookup.
            let lookup = query.trimmingCharacters(in: CharacterSet(charactersIn: "`() ").union(.newlines)).lowercased()
            if let example = Self.workedExamples[lookup], let highestScore = scores.values.max(),
               let section = scores.keys.sorted().first(where: { id in
                   guard let section = sections[id], section.title == example.title else { return false }
                   return section.heading == example.heading || section.heading.hasSuffix(" / " + example.heading)
               }) {
                scores[section] = highestScore + 1.0
            }
            return scores.sorted {
                $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
            }.prefix(5).compactMap { match in
                guard let section = sections[match.key] else { return nil }
                var fields = section.metadata
                fields["excerpt"] = section.excerpt
                return fields
            }
        }

        private static let workedExamples = [
            "transformedby": (title: "Linear Algebra Primer", heading: "What matrices do")
        ]

        private static let stopWords: Set<String> = [
            "a", "an", "and", "are", "can", "do", "does", "for", "from", "how", "i", "in", "is", "it",
            "of", "on", "or", "quiver", "the", "to", "what", "when", "which", "with"
        ]

        private static func words(_ text: String) -> [String] {
            let separated = text.replacingOccurrences(
                of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression
            )
            return separated.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        }
    }
}
