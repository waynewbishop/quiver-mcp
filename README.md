# Quiver MCP

**Statistics, machine learning, and numerical computing for MCP clients—running locally in Swift.**

Quiver MCP gives Claude Code, Codex, and other Model Context Protocol clients 47 calculation tools powered by [Quiver](https://github.com/waynewbishop/quiver). Ask your assistant to analyze a dataset, fit a model, solve a linear system, or analyze a workout without sending the computation to a separate service.

[![Swift 6.1+](https://img.shields.io/badge/Swift-6.1%2B-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Apache 2.0](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)

- **Broad numerical toolkit:** descriptive statistics, probability, regression, classification, clustering, PCA, linear algebra, signal processing, and vector search.
- **Agent-friendly results:** every tool publishes an input schema and returns named fields as structured JSON as well as text.
- **Local and stateless:** no API key or model server is required. Each call contains everything needed for its calculation, and fitted models are discarded after the response.

## Quickstart

### Requirements

- macOS 15 or later
- Swift 6.1 or later
- An MCP client that supports local stdio servers

### 1. Build the server

From the package directory:

```sh
cd /path/to/quiver-mcp
swift build -c release
QUIVER_MCP="$(pwd -P)/.build/release/quiver-mcp"
```

The first build may download Quiver 1.7.0 through Swift Package Manager. The executable is created at `.build/release/quiver-mcp`; the last command stores its absolute path for the registration commands below. Use the same shell for the next step.

### 2. Connect your client

Using an absolute executable path lets the client start Quiver MCP from any working directory.

**Codex**

```sh
codex mcp add quiver -- "$QUIVER_MCP"
```

**Claude Code**

```sh
claude mcp add --scope user --transport stdio quiver -- "$QUIVER_MCP"
```

User scope makes Quiver available in every Claude Code project. For one project, use `--scope local` and run the command from that project’s directory.

<details>
<summary>Other MCP clients</summary>

For a client that uses JSON configuration, add the server with its absolute executable path:

```json
{
  "mcpServers": {
    "quiver": {
      "command": "/absolute/path/to/quiver-mcp/.build/release/quiver-mcp",
      "args": []
    }
  }
}
```

Configuration file locations vary by client; consult the client’s MCP documentation.

</details>

Start a new client session after changing the configuration. The client launches the executable and discovers its tools automatically.

### 3. Try a calculation

Ask:

> Use Quiver’s `fit_linear_regression` tool to fit a line to predictors [1, 2, 3, 4] and targets [3, 5, 7, 9]. Report the intercept and slope.

The tool’s structured result is:

```json
{
  "intercept": 1,
  "slope": 2
}
```

That gives the line **y = 1 + 2x**. Try another request:

> Use `vector_summary` to summarize [4, 8, 15, 16, 23, 42], then explain the spread and quartiles.

For a complete MCP exchange in the terminal, follow [Fitting a Line](Sources/QuiverMCP/QuiverMCP.docc/Worked-Examples/Fitting-a-Line.md).

## Available tools

| Category | Tools |
| --- | --- |
| Describe samples and compare variables | `vector_summary`, `describe_sample`, `correlation`, `correlation_matrix`, `covariance_matrix`, `frequency_table`, `histogram`, `contingency_table` |
| Work with probability and sampling | `evaluate_distribution`, `bayes_posterior`, `sample`, `estimate_sampling_distribution` |
| Fit and evaluate regressions | `fit_linear_regression`, `fit_ridge_regression`, `fit_gradient_descent`, `fit_polynomial`, `summarize_regression`, `analyze_residuals`, `evaluate_predictions` |
| Classify, cluster, or reduce dimensions | `fit_logistic_regression`, `fit_gaussian_naive_bayes`, `fit_bernoulli_naive_bayes`, `classify_with_knn`, `fit_knn_pipeline`, `fit_kmeans`, `fit_pca` |
| Prepare data and analyze signals | `summarize_columns`, `group_values`, `prepare_series`, `split_indices`, `fourier_spectrum` |
| Measure and compare vectors | `dot_product`, `vector_magnitude`, `euclidean_distance`, `normalize_vector`, `project_vector`, `cosine_similarity`, `search_embeddings` |
| Transform vectors and solve matrix problems | `multiply_matrix_vector`, `multiply_matrices`, `transpose_matrix`, `invert_matrix`, `matrix_determinant`, `solve_linear_system`, `decompose_matrix` |
| Format numeric results and equations | `render_math` |
| Score a workout | `calculate_true_effort_score` |
| Look up Quiver documentation | `search_quiver_docs`, `read_quiver_doc` |

The MCP `tools/list` response is the authoritative source for each tool’s description and input schema. Model tools fit and predict in the same request; no separate model-saving step is needed. See the [model guide](Sources/QuiverMCP/QuiverMCP.docc/Essentials/Fitting-Models-with-Quiver.md) for required arguments, optional controls, and result fields.

## Ask about Quiver’s documentation

Try asking your MCP client, “Using Quiver’s documentation, explain how ridge regression handles feature scaling and cite the sections you used.”

`search_quiver_docs` returns up to five relevant DocC sections with excerpts, section IDs, and source links. `read_quiver_doc` takes a section ID and returns its Markdown with Swift examples and equations intact. The executable embeds documentation from the pinned Quiver revision and searches it locally.

## How it works

```text
Claude Code, Codex, or another MCP client
                  ↕ JSON-RPC over stdio
              quiver-mcp
                  ↕ Swift calls
             Quiver 1.7.0
```

Quiver MCP is a local executable, not an HTTP service. Standard output carries MCP messages, diagnostics go to standard error, and calculations run in memory. Running the executable directly waits for protocol input; use the [terminal example](Sources/QuiverMCP/QuiverMCP.docc/Worked-Examples/Fitting-a-Line.md) to exercise it without a client.

The server requires no API key and makes no network requests while performing calculations. Your MCP client can still include tool inputs and results in the model conversation, subject to that client’s privacy settings. Quiver MCP retains only connection handshake state between requests; it does not persist inputs, results, or fitted models.

## Documentation

- [Calculating with Quiver](Sources/QuiverMCP/QuiverMCP.docc/Essentials/Calculating-with-Quiver.md): basic calculation inputs and results.
- [Statistical Analysis](Sources/QuiverMCP/QuiverMCP.docc/Essentials/Statistical-Analysis.md): descriptive statistics, distributions, sampling, and evaluation.
- [Fitting Models with Quiver](Sources/QuiverMCP/QuiverMCP.docc/Essentials/Fitting-Models-with-Quiver.md): regression, classification, clustering, PCA, and workout scoring.
- [Data Preparation and Numerical Tools](Sources/QuiverMCP/QuiverMCP.docc/Essentials/Numerical-Tools.md): transformations, matrices, signals, and similarity search.
- [How It Works](Sources/QuiverMCP/QuiverMCP.docc/Essentials/How-It-Works.md): request flow and source map.
- [The MCP Session](Sources/QuiverMCP/QuiverMCP.docc/Essentials/MCP-Session.md): initialization, discovery, dispatch, and transport behavior.

## Development

Run the debug build and test suite from the package directory:

```sh
swift build
swift test
```

After updating the Quiver pin, run `swift package resolve` and `python3 Scripts/generate-quiver-docs.py` to refresh the embedded documentation. Commit the generated Swift file together with the dependency update.

After changing the source, rebuild the release executable used by your client:

```sh
swift build -c release
```

## License

Quiver MCP is available under the [Apache License 2.0](LICENSE).
