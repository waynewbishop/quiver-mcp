# Calculating with Quiver

Supply numeric arrays to Quiver and read the result fields for each calculation.

## Overview

``_QuiverCalculation`` defines the tool schemas and calls the corresponding Quiver operations. Arguments are finite JSON numbers. Every call contains the data needed for that calculation.

## Descriptive statistics

The `vector_summary` tool accepts `values`, an array of at least two observations. It uses compensated summation for the mean, scaled deviations for the sample standard deviation, and Quiver’s linear-interpolation convention for quartiles. The response contains the count, mean, sample standard deviation, minimum, first quartile, median, third quartile, maximum, and interquartile range.

## Cosine similarity

The `cosine_similarity` tool accepts `left` and `right`, two nonzero vectors with equal length. The implementation scales each vector by its largest absolute component before calling Quiver’s `cosineOfAngle(with:)`. Positive scaling preserves direction while reducing overflow and underflow in the magnitude calculation. The result field is `similarity`. The server bounds roundoff at the endpoints of the range from −1 to 1.

## Linear regression

The `fit_linear_regression` tool accepts two arrays named `features` and `targets`. Each position pairs one predictor value with one target. Supply at least two observations with at least two distinct predictor values. The server centers and scales both arrays before calling Quiver’s single-predictor `LinearRegression.fit(features:targets:)`, then restores the coefficients to the original units. The tool returns its `intercept` and `slope`. An optional `predict` vector adds predictions at those predictor values. Each call discards the fitted model. See <doc:Fitting-a-Line> for the corresponding MCP request.

See <doc:Fitting-Models-with-Quiver> for matrix-based fits, classification, PCA, and workout scoring.

See <doc:Statistical-Analysis> for probability distributions, sample descriptions, and inference. See <doc:Numerical-Tools> for data preparation, signals, and linear algebra.
