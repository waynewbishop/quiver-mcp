# Data Preparation and Numerical Tools

Transform arrays, solve linear systems, and compare supplied embeddings.

## Data preparation and signals

| Tool | Arguments and results |
| --- | --- |
| `summarize_columns` | Pass rectangular `rows` and one unique name per column in `columns`. The result includes column summaries keyed by name and a separate array preserving column order. |
| `group_values` | Pass paired numeric `values` and string `categories` with an `aggregation` of `sum`, `mean`, `min`, `max`, `count`, or `percentage`. |
| `prepare_series` | Pass `values` and an `operation`. Use `standardize`, `rolling_mean` with `window`, `exponential_mean` with either `alpha` or `span`, or `difference` and `percent_change` with an optional `lag` of 1 by default. |
| `split_indices` | Pass the observation `count`, a nonnegative JSON-safe integer `seed`, and either a `testRatio` strictly between zero and one or a `folds` count from 2 through 20. The output contains zero-based indices. |
| `fourier_spectrum` | Pass evenly spaced `values` and a positive `sampleRate`. Set `windowed` to true to enable windowing. The result contains pairs of frequencies and magnitudes. |

## Linear algebra and retrieval

| Tool | Arguments and results |
| --- | --- |
| `dot_product`, `euclidean_distance` | Pass equal-length `left` and `right` vectors. |
| `vector_magnitude`, `normalize_vector` | Pass a `vector`. Normalizing a zero vector returns the zero vector. |
| `project_vector` | Pass a `vector` and an equal-length direction vector in `onto`. A zero direction returns a zero projection. |
| `multiply_matrix_vector` | Pass a `matrix` and a `vector` with one entry per matrix column. Each output coordinate is the dot product of a matrix row and the vector. |
| `multiply_matrices` | Pass `left` and `right` matrices. The number of left columns must equal the number of right rows. |
| `transpose_matrix`, `invert_matrix`, `matrix_determinant` | Pass a `matrix`. Inverse and determinant require a square matrix. Inversion of a singular matrix returns a tool error. |
| `solve_linear_system` | Pass a square `matrix` and a matching right-hand-side vector `rhs`. The result is the solution vector. |
| `decompose_matrix` | Pass a square `matrix` and `method` of `lu` or `eigen`. LU returns the triangular factors, row permutation, and determinant. Eigen decomposition requires a symmetric matrix and returns eigenvalues, eigenvectors, and convergence information. |
| `fit_polynomial` | Pass paired `x` and `y` vectors and a `degree` from 0 through 32 that is smaller than the observation count. Pass an optional `predict` vector to evaluate the fit at those points. Coefficients are ordered from the constant term upward. |
| `search_embeddings` | Pass equal-width, nonzero `vectors`, one unique name per vector in `labels`, a nonzero `query` vector of the same width, and the desired hit count `k`. The result contains ranked labels and cosine scores. |

For example, send this request in an initialized session to solve a two-variable system. The structured result is `{"solution":[2,3]}`.

```json
{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"solve_linear_system","arguments":{"matrix":[[2,0],[0,3]],"rhs":[4,9]}}}
```

See <doc:Statistical-Analysis> for correlation and covariance matrices.

## Rendering math

Call `render_math` with one of these input shapes. The result preserves the supplied numeric fields and adds a Unicode `expression`.

| Kind | Arguments |
| --- | --- |
| `scalar` | Pass `value`. |
| `vector` | Pass `vector`. Choose `vectorForm` of `inline` or `column` (the default). |
| `matrix` | Pass a rectangular `matrix`. |
| `polynomial` | Pass `coefficients` in ascending power order. Set `relativeZeroTolerance` to control which small terms are hidden. |
| `model` | Pass `coefficients` in feature order with the intercept first by default. Use `hasIntercept: false` for weights alone. Optionally supply `variables` and a linear `response` name. Choose `modelForm` of `linear` (the default), `log_odds`, or `probability`. |

Set `asFractions` to true for rational approximations. The `fractions` field contains numerator and denominator pairs in the same shape as the input. Scalar, vector, and matrix expressions display the fractions directly. Polynomial and model expressions keep Quiver’s equation notation and include fraction pairs for the coefficients. Use `maxDenominator` to limit the approximation, up to the default of 1,000.

For example, pass `[[3,1],[2,5]]` to `invert_matrix`, then pass its result as the `matrix` argument to `render_math` with `asFractions: true`. The expression shows `5/13` and `-1/13` on the first row and `-2/13` and `3/13` on the second row.
