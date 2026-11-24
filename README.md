# Quiver MCP

**Statistics, machine learning, and numerical computing for your AI assistant, running locally in Swift.**

Ask Claude Code, Codex, or another Model Context Protocol (MCP) client to analyze a dataset, fit a model, solve a linear system, or score a workout. Quiver MCP runs the calculation on your Mac and returns structured results your assistant can explain. It can also look up documentation for [Quiver](https://github.com/waynewbishop/quiver), the Swift library that does the work.

[![Swift 6.1+](https://img.shields.io/badge/Swift-6.1%2B-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Apache 2.0](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)

> **Developer preview.** Quiver MCP runs locally on your Mac.

## See it work

> Use Quiver to fit a line to these house sizes and sale prices. The sizes are 1,000, 1,500, 2,000, and 2,500 square feet. The prices are $250,000, $325,000, $400,000, and $475,000. What does the fitted line predict for a 1,800-square-foot house?

Quiver returns an intercept of **$100,000** and a slope of **$150 per square foot**. At 1,800 square feet, the fitted line predicts **$370,000**.

## What it does

MCP gives an assistant a standard way to discover and call tools. Quiver MCP exposes [49 tools](#available-tools), including two for searching and reading Quiver’s documentation. The toolkit covers descriptive statistics, probability, regression, classification, clustering, PCA, linear algebra, signal processing, vector search, and True Effort Score.

Each tool describes the inputs it accepts. Results include named fields such as `intercept` and `slope`, so the assistant can use those values directly in its explanation. The documentation tools search the DocC bundled with the pinned Quiver release and can return full sections with source links, Swift examples, and equations.

## Learn with it

Start with the house-price example above. Once you have the fitted line, ask how Quiver chose it.

> Using Quiver’s Linear Regression overview, explain why the best-fit line minimizes the sum of squared residuals. Cite the section you used.

Then change one sale price and fit the line again. Compare the new slope and the predicted price for a 1,800-square-foot house.

You can also ask Quiver to check a system of equations.

> Use Quiver to solve `2x + y = 5` and `x + 3y = 10`. Substitute the result into both equations to check it.

## Ask about Swift

Quiver is written in Swift, so some questions are about the language as much as the math: how data is organized, why a call can fail, and why a fitted model behaves the way it does. Ask for a small code example when you want to try an API yourself.

> Using Quiver’s Panel Workflows guide, show how to split a Panel into training and test rows while keeping its columns aligned. Cite the section you used.

> Using Quiver’s Linear Regression documentation, explain why duplicate features make the normal equation singular. Cite the section you used.

You can also ask in your own words, such as why a fitted Quiver model is ready to use the moment it’s created, or how a Panel compares to other tabular tools you know. Quiver’s documentation covers the Swift side of those answers. Anything beyond the documentation comes from your assistant, not from Quiver.

## Get started

### Requirements

- macOS 15 or later
- Swift 6.1 or later
- An MCP client that supports local stdio servers. The client launches Quiver MCP and communicates with it through standard input and output.

### 1. Build Quiver MCP

```sh
git clone https://github.com/waynewbishop/quiver-mcp.git
cd quiver-mcp
swift build -c release
QUIVER_MCP="$(pwd -P)/.build/release/quiver-mcp"
```

Swift Package Manager may download Quiver 1.7.0 on the first build. The last command captures the executable’s absolute path. Run the registration command in the same terminal window.

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

### 3. Try it

Start a new client session and paste the [house-price prompt](#see-it-work). You can ask in plain language. The client can discover the available tools and select one based on your request.

For a complete MCP exchange in the terminal, see [Fitting a Line](Sources/QuiverMCP/QuiverMCP.docc/Worked-Examples/Fitting-a-Line.md).

## How it handles your data

Quiver MCP performs calculations in memory on your Mac and requires no API key of its own. Each call supplies the data it needs. Quiver MCP retains no inputs, results, or fitted models between calls. When a tool fits a model and makes predictions, it does both in the same request.

Your MCP client may include tool inputs and results in the model conversation. How that conversation is processed or stored depends on your client and its settings.

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

The MCP `tools/list` response is the authoritative source for each tool’s description and input schema. See the [model guide](Sources/QuiverMCP/QuiverMCP.docc/Essentials/Fitting-Models-with-Quiver.md) for required arguments, optional controls, and result fields.

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
