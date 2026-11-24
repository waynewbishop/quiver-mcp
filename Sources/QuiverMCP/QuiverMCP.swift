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

/// Launches the local Quiver MCP calculation server.
@main
enum QuiverMCP {
    /// Serves the connection until the host closes stdin.
    static func main() {
        guard CommandLine.arguments.count == 1 else {
            reportStartupError("Quiver MCP takes no arguments. Run swift run from the package directory.")
        }

        do {
            var server = _MCPServer()
            try server.serve()
        } catch {
            reportStartupError(error.localizedDescription)
        }
    }

    /// Reports a launch or transport failure without writing to the protocol stream.
    /// - Parameter message: A diagnostic for the host or terminal.
    private static func reportStartupError(_ message: String) -> Never {
        FileHandle.standardError.write(Data("quiver-mcp: \(message)\n".utf8))
        exit(EXIT_FAILURE)
    }
}
