# Fitting Models with Quiver

Fit a Quiver model and request its numerical results in one MCP call.

## Overview

Each tool accepts its training observations and any prediction rows in the same request. The server fits the model, returns selected outputs, and discards the fitted value. For matrix inputs, each row is an observation and each column is a feature. Prediction rows use the same feature order and width as the training rows.

See ``_QuiverCalculation/calculate(arguments:)`` for the dispatch entry point and <doc:MCP-Session> for the wire format.

## Regression and classification

| Tool | Required arguments | Optional arguments | Result |
| --- | --- | --- | --- |
| `fit_linear_regression` | `features` and `targets` as vectors | `predict` vector | Intercept, slope, and predictions when requested |
| `fit_ridge_regression` | `features` matrix, `targets` vector, nonnegative `lambda` | Optimization controls and `predict` matrix | Intercept-first coefficients, loss history, outcome, and requested predictions |
| `fit_logistic_regression` | `features` matrix and `labels` vector containing both 0 and 1 | Optimization controls and `predict` matrix | Intercept-first coefficients, loss history, outcome, and requested labels and probabilities of class 1 |
| `fit_gaussian_naive_bayes` | `features` and `predict` matrices, integer `labels` | | Predicted labels and probability rows whose columns follow `classLabels` |
| `fit_bernoulli_naive_bayes` | Binary `features` matrix and integer `labels` | Binary `predict` matrix and positive `alpha` (default 1.0) | Class counts, priors, and smoothed feature-presence probabilities. With `predict`, returns labels and probability rows whose columns follow ascending `classLabels`. |
| `classify_with_knn` | `features` and `predict` matrices, integer `labels`, and `k` | | Predicted labels using Euclidean distance and uniform votes |
| `fit_gradient_descent` | `features` matrix and `targets` vector | Optimization controls and `predict` matrix | Intercept-first coefficients, loss history, outcome, and requested predictions |

The Euclidean tools use a common binary scale to preserve distances without overflowing their squared terms. A query beyond a one-dimensional training interval has the same neighbor ordering as the nearest endpoint, so the server can classify it without forming the full distance. The server returns a tool error when a transformed query or a distance loses its finite representation.

Gaussian Naive Bayes scores classes in log space. A query whose likelihood is outside the representable range for every class returns a tool error.

The iterative tools accept positive `learningRate` and `tolerance`, and `maxIterations` from 1 to 10,000. Defaults are 0.01, 0.000001, and 1,000. Inspect the outcome and loss history before interpreting coefficients from a fit that reached its iteration limit.

## Clustering and projection

`fit_kmeans` accepts a `features` matrix and a `k` between one and the number of training rows. Supply an optional nonnegative JSON-safe integer `seed` for reproducible initialization. The `maxIterations` default is 100. The result contains the centroids, zero-based training assignments, inertia, and iteration count. Optional `predict` rows add cluster assignments.

`fit_pca` accepts a `features` matrix with at least two rows and `componentCount` between one and the feature count. Set `standardize` to true to fit a scaler on the training rows before PCA. The response gives component vectors in the coordinates used for fitting, their explained variances and ratios, and the projected rows. Supply `predict` to project new rows using the training transform. When omitted, the result contains the projected training rows.

> Experiment: Fit one component to `[[1, 10], [2, 20], [3, 30]]`. Compare the component direction with and without standardization. The columns vary together, so the first component captures their variation in both fits. Standardization changes the coordinate scale used to represent that direction.

## Residuals and pipelines

`analyze_residuals` fits an ordinary linear regression on `features` and `targets`. It predicts the separate rows in `observedFeatures` and subtracts those predictions from `observedTargets`. Positive residuals indicate that the observed value exceeded the prediction. For a single feature, this workflow uses the same centered and scaled fit as `fit_linear_regression`.

`fit_knn_pipeline` accepts the same required fields as `classify_with_knn`. It fits a standard scaler on the training rows, then applies that scaler to the query rows. Pass `componentCount` to fit PCA on the scaled training rows before classification. The pipeline uses those same fitted components to project the queries.

## True Effort Score

`calculate_true_effort_score` accepts one outdoor workout as a `samples` array. Each sample supplies seven numeric fields:

| Field | Unit |
| --- | --- |
| `timestamp` | Unix seconds, strictly increasing |
| `heartRate` | Beats per minute |
| `pace` | Minutes per kilometer |
| `cadence` | Steps per minute |
| `grade` | Signed percentage, negative for downhill |
| `verticalOscillation` | Centimeters |
| `altitude` | Meters |

An optional `hrTrust` value from 0 to 1 defaults to 1. Supply at least 60 seconds of active time. The response includes the raw and adjusted scores, average heart rate, effort distribution, adjustment terms, and cumulative load curve. The tool starts with a fresh model for each workout, so `expectedHeartRate` and `meanResidual` are null without a personalized baseline.
