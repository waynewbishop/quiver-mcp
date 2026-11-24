# Fitting a Line

Send paired numeric observations over MCP and inspect Quiver’s fitted coefficients.

## Overview

We can fit a line to the observations (1, 3), (2, 5), (3, 7), and (4, 9). The request carries both arrays, and Quiver returns the intercept and slope. This exercise needs no model session.

## Sending the requests

```sh
cd /path/to/quiver-mcp
swift run <<'JSONL'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"terminal","version":"1.0"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list"}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"fit_linear_regression","arguments":{"features":[1,2,3,4],"targets":[3,5,7,9]}}}
JSONL
```

The server emits three response lines. ID 1 carries the protocol version, ID 2 lists the calculation tools, and ID 3 carries the fitted coefficients. The initialization notification has no response.

## Reading the result

In response 3, inspect `result.structuredContent`. The `intercept` is approximately 1 and the `slope` is approximately 2. That gives the line y = 1 + 2x. The calculation is dispatched through ``_QuiverCalculation/calculate(arguments:)``.

Send a second request with a different target array to fit a different line. Each response depends on the values in that request.
