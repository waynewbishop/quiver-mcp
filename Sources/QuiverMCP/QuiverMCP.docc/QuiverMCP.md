# ``QuiverMCP``

Calculate statistics and fit Quiver models over the Model Context Protocol.

## Overview

Quiver MCP exposes numerical operations from Quiver 1.7.0 to hosts such as Claude Code and Codex. A tool call carries its complete input in JSON. The server validates the numbers, calls Quiver in the same process, and returns the result over standard output.

Start with <doc:How-It-Works> to follow the source, then read <doc:MCP-Session> for the message sequence. <doc:Calculating-with-Quiver> introduces the basic calculations. <doc:Statistical-Analysis> and <doc:Numerical-Tools> cover the statistics, data preparation, and numerical tools. <doc:Fitting-Models-with-Quiver> describes the dedicated model tools. <doc:Fitting-a-Line> runs a complete exchange from a terminal.

## Topics

### Essentials

- <doc:How-It-Works>
- <doc:MCP-Session>
- <doc:Calculating-with-Quiver>
- <doc:Statistical-Analysis>
- <doc:Numerical-Tools>
- <doc:Fitting-Models-with-Quiver>

### Worked examples

- <doc:Fitting-a-Line>

### Source reference

- ``QuiverMCP/QuiverMCP``
- ``_MCPServer``
- ``_QuiverCalculation``
