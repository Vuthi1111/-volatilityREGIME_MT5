# Volatility Regime MQL5 Dashboard

An institutional-grade, zero-latency Heads-Up Display (HUD) for MetaTrader 5, driven by mathematically optimized Machine Learning models. 

This repository contains **strictly the MQL5 Indicator code**. The Python ML model pipelines, feature engineering, and training routines are maintained in a separate research repository.

## The Architecture

The dashboard serves as the visual execution gate for five independent LightGBM inference cores:
1. **1H Volatility Predictor:** The primary expansive/compressive state predictor.
2. **4H Volatility Predictor:** The structural higher-timeframe trend context.
3. **Speed of Tape:** Measures 1M tick flow acceleration and burstiness.
4. **Micro-Regime:** Detects short-term liquidity vacuums and chop.
5. **VWAP Copilot:** Identifies extreme statistical deviations from the Anchored Daily VWAP.

### The Execution Meta-Model

Instead of using hardcoded human heuristics to combine these 5 models, we trained a **Decision Tree Optimizer** on 390,000 historical 15M Gold bars (2004–2021) using Walk-Forward Validation.

The optimizer analyzed Out-of-Sample data (2015-2021) and discovered the exact mathematical rules for when to execute trend, when to mean-revert, and when to stay out of the market. These optimal rules are hardcoded into `DashboardUI.mqh`.

## Key Features

- **Live Multi-Model Heatmaps & Progress Bars:** Real-time visual tracking of all 5 ML models.
- **Microstructure Telemetry:** Live tracking of Active Ratio, Hurst Exponent, Bollinger Band positioning, and VWAP Z-Scores.
- **The Execution Gate:** Displays the mathematically derived execution regime (`TREND EXECUTION`, `MEAN REVERSION`, `NEWS BLACKOUT`, or `CASH/NEUTRAL`) and the exact logic that triggered it.
- **HUD Background Tinting:** The dashboard dynamically tints the entire MetaTrader 5 chart background (Green = Trend, Blue = Mean Reversion, Red = News) to provide immediate, peripheral awareness of the model's stance without needing to read the text.

## Installation & Setup

1. **Download the Repository** or clone it to your local machine.
2. **Open MetaTrader 5's Data Folder:** Go to `File -> Open Data Folder`.
3. **Install the Include Files:** Copy the `Include/VolRegime` folder into your MT5's `MQL5/Include/` directory.
   - You should have `MQL5/Include/VolRegime/DashboardUI.mqh`, `MQL5/Include/VolRegime/DashboardPrimitives.mqh`, etc.
4. **Install the Indicator:** Copy `Indicators/VolRegimeMatrix.mq5` and `.ex5` into your MT5's `MQL5/Indicators/` directory.
5. **Attach to Chart:** Drag the `VolRegimeMatrix` indicator onto any chart (Gold or NAS100) to start the dashboard.

*(Note: The models are pre-compiled into MQL5 headers `gold_vol_regime_1h.mqh`, etc., meaning no external Python bridge or DLLs are required. The execution runs 100% natively inside MT5).*
