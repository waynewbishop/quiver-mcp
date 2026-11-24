# Statistical Analysis

Describe samples, evaluate probability distributions, and report uncertainty.

## Samples and relationships

| Tool | Arguments and results |
| --- | --- |
| `describe_sample` | Pass `values` and optionally `ddof` (default 1), `bias` (default true), or an outlier `threshold` (default 2). The result includes descriptive statistics, cumulative totals and products, shape metrics, percentile ranks, and an outlier mask. Pass `percentiles` as levels from 0 to 100 or `score` to request its z-score and percentile rank. |
| `correlation` | Pass equally sized `left` and `right` arrays of at least two paired observations. The result contains the Pearson coefficient. |
| `correlation_matrix` | Pass rectangular `rows`, with observations as rows and variables as columns. The result is a square Pearson correlation matrix in input column order. |
| `covariance_matrix` | Pass rectangular `rows` and optionally `ddof`. The default of 1 gives sample covariance. Use 0 for population covariance. |

An undefined Pearson coefficient, such as a correlation with a constant column, appears as JSON `null`. The compact <doc:Calculating-with-Quiver#Descriptive-statistics> example describes the fields in `vector_summary`.

## Probability distributions

Pass `distribution` and `operation` to `evaluate_distribution`. The result field is `value`.

| Distribution | Operations | Parameters |
| --- | --- | --- |
| `normal` | `pdf`, `log_pdf`, `cdf`, `quantile` | Use `x` for evaluation or `p` for a quantile. Optional `mean` and `standardDeviation` default to 0 and 1. |
| `t` | `cdf`, `quantile` | Pass `df` and either `x` for a CDF or `p` for a quantile. |
| `chi_squared` | `cdf` | Pass `df` and `x`. |
| `poisson` | `pmf`, `log_pmf`, `cdf`, `quantile`, `mean`, `variance` | Pass `lambda`. Use `k` for mass or cumulative probability and `p` for a quantile. |
| `binomial` | `pmf`, `log_pmf`, `cdf`, `quantile`, `mean`, `variance` | Pass `n` and the success probability `p`. For a quantile, pass the success probability as `probability`, and the cumulative cutoff as `p`. Use `k` for mass or cumulative probability. |

The Poisson quantile at `p = 1` returns `null` because its support has no finite upper endpoint.

For example, this request evaluates the standard normal CDF at zero in an initialized session. The structured result is `{"value":0.5}`.

```json
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"evaluate_distribution","arguments":{"distribution":"normal","operation":"cdf","x":0}}}
```

## Counts and Bayesian updates

| Tool | Arguments and results |
| --- | --- |
| `frequency_table` | Pass numeric `values` to get counts and relative frequencies by distinct value. |
| `histogram` | Pass `values` and either `bins` (1–512) or `rule` (`square_root`, `sturges`, or `freedman_diaconis`). The result has each bin’s midpoint and count. |
| `contingency_table` | Pass unique `rowLabels` and `columnLabels` plus a rectangular `counts` matrix of nonnegative integers. The result includes marginals and joint and conditional probabilities. Set `compareIndependence` to true to compare each observed joint probability with the product of its row and column marginals. |
| `bayes_posterior` | Pass `prior`, `likelihood`, and `evidence` for a single event. Use `prior`, `trueRate`, and `falsePositiveRate` for a diagnostic update, or paired arrays `hypotheses`, `priors`, and `likelihoods` for named hypotheses. |

## Sampling and inference

| Tool | Arguments and results |
| --- | --- |
| `sample` | Pass `values`, `count`, and `seed`. Set `replace` to false for sampling without replacement. |
| `estimate_sampling_distribution` | Pass `values`, `seed`, and a `statistic` of `mean`, `median`, or `standard_deviation`. Optional `sampleSize` defaults to the observation count, `iterations` to 1,000, and `level` to 0.95. The result contains replicates and their percentile interval. |
| `summarize_regression` | Pass row-oriented `features` and matching `targets`. Optional `intercept` defaults to true and `level` to 0.95. The result includes coefficient estimates, standard errors, t-statistics, p-values, intervals, R², adjusted R², and residual standard error. |
| `evaluate_predictions` | Pass `kind` (`regression` or `classification`) and paired `predictions` and `actual` arrays. Classification uses integer labels and accepts `positiveLabel` for the binary confusion matrix. |

Use nonnegative JSON-safe integer seeds and confidence levels strictly between zero and one. A sampling-distribution request can make up to five million draws. Regression inference requires more observations than fitted coefficients. Undefined fields in the regression summary appear as JSON `null`.
