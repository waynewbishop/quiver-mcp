# The MCP Session

Follow version negotiation, tool discovery, and tool calls over standard input and output.

## Overview

**JSON-RPC** gives each request a method name, parameters, and an ID. A response echoes the ID so the host can match it to the request. A **notification** omits the ID and receives no response. In the stdio transport, each message occupies one line, so line breaks inside strings are encoded as JSON escapes.

## Initialization

1. The host sends `initialize` with its protocol version, capabilities, and client information.
2. The server replies with its selected version, identity, and tools capability. It echoes a supported requested version and otherwise proposes `2025-11-25`.
3. The host sends `notifications/initialized`. The connection now accepts tool discovery and calls.

The connection state in ``_MCPServer`` follows those steps in order. The ``_MCPServer/serve()`` loop reads and responds to one message at a time. The server also responds to `ping` before the handshake finishes.

## Discovery and dispatch

The `tools/list` response contains each tool’s name, description, and **input schema**, a JSON object that describes the arguments the host can supply. The server dispatches a tool call to ``_QuiverCalculation/calculate(arguments:)`` with the numeric arrays from the request. The advertised descriptions include the linked Quiver version.

The response carries named fields in `structuredContent` and a serialized copy in a text item in `content`. Malformed UTF-8 or JSON produces a parse error. Malformed request parameters produce a JSON-RPC error, and a malformed initialization notification is ignored. A known tool with a valid arguments object containing invalid inputs produces a tool result with `isError` set.

## Stream ownership

Standard output carries only protocol messages. Launch and transport diagnostics go to standard error. A calculation result is written as a response line, after which the server reads the next message.

See <doc:Calculating-with-Quiver> for the tool contracts and <doc:Fitting-a-Line> for the terminal exchange.

- [MCP lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle)
- [MCP stdio transport](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)
- [MCP tools](https://modelcontextprotocol.io/specification/2025-11-25/server/tools)
