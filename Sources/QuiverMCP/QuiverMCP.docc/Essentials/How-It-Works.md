# How It Works

Trace a calculation from the host through the Swift executable and back to the model.

## Overview

The **host** runs the model conversation and launches the MCP server as a subprocess. It discovers the tools and presents their definitions to the model. When the model requests a calculation, the host writes a JSON-RPC message to the subprocess and reads the response from standard output.

```text
Language model
    ↕ Tool definitions, model requests, and tool results
Claude Code or Codex
    ↕ JSON-RPC over stdin and stdout
quiver-mcp
    ↕ Swift method calls
Quiver
```

## Reading the source

| Source | Start here | What to look for |
| --- | --- | --- |
| `QuiverMCP.swift` | ``QuiverMCP/QuiverMCP/main()`` | Starts the message loop and reports launch failures on stderr. |
| `Core/_MCPServer.swift` | ``_MCPServer/serve()`` | Reads requests and writes the corresponding MCP responses. |
| `Core/_QuiverCalculation.swift` | ``_QuiverCalculation/definition`` | Builds the schema the host receives during tool discovery. |
| `Core/_QuiverCalculation.swift` | ``_QuiverCalculation/calculate(arguments:)`` | Validates the numeric arguments and calls Quiver. |

`_QuiverCalculation+Statistics.swift` implements the statistical analyses and inference tools. `_QuiverCalculation+Analysis.swift` dispatches those calculations and implements matrix, series, signal, and retrieval operations.

## Request lifetime

Each tool gets its inputs from the current message. Model tools fit and predict in the same request. See <doc:Fitting-Models-with-Quiver> for each contract. The calculation runs in memory, and the server returns the result in that message’s response. The server keeps only the MCP handshake state between requests. A host can include the tool arguments and result in its model conversation.

Follow <doc:MCP-Session> for the wire protocol or <doc:Fitting-a-Line> for a complete exchange.
