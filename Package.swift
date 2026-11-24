// swift-tools-version: 6.1
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

import PackageDescription

let package = Package(
    name: "quiver-mcp",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "quiver-mcp", targets: ["QuiverMCP"])],
    dependencies: [
        .package(url: "https://github.com/waynewbishop/quiver.git", exact: "1.7.0")
    ],
    targets: [
        .executableTarget(
            name: "QuiverMCP",
            dependencies: [.product(name: "Quiver", package: "quiver")]
        ),
        .testTarget(name: "QuiverMCPTests", dependencies: ["QuiverMCP"])
    ]
)
