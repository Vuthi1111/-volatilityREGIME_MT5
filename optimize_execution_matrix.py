"""
optimize_execution_matrix.py
═══════════════════════════════════════════════════════════════════════════════
Execution Matrix Optimizer — finds optimal Trend/MeanRev/Neutral conditions

Pipeline:
  1. Load 15M Gold data (common denominator for all 5 models)
  2. Build features for all 5 model families
  3. Generate probability streams via walk-forward:
       - Vol 1H  (hourly volatility regime)
       - Vol 4H  (4-hour volatility regime)
       - Tape    (speed-of-tape regime)
       - Micro   (micro-regime for next 15min)
       - VWAP    (VWAP copilot scalp probability)
  4. Define forward-looking strategy target per bar:
       - TREND: price moves directionally > 1R
       - MEAN_REV: price reverts to mean > 1R
       - NEUTRAL: neither
  5. Train Decision Tree (max_depth=3) to extract IF-THEN rules
  6. Output MQL5-ready conditions
═══════════════════════════════════════════════════════════════════════════════
"""

import sys, warnings, os
warnings.filterwarnings("ignore")
import numpy as np
import pandas as pd
import lightgbm as lgb
from sklearn.metrics import roc_auc_score
from sklearn.tree import DecisionTreeClassifier, export_text
from sklearn.ensemble import RandomForestClassifier
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "src"))
from feature_engineering import (
    load_mt5_csv, resample_to_15m,
    garman_klass, parkinson, rogers_satchell,
    range_ratio, tick_vol_acceleration,
    build_vol_regime_labels,
)

ARTIFACT_DIR = "/Users/macos/.gemini/antigravity/brain/a79aad02-781a-4a03-8ce4-594372872646"
SPREAD_PIPS = 3.0

# ── HURST (inline, no external dep) ──

def hurst_rs(series, min_n=8):
    n = len(series)
    if n < min_n * 2: return np.nan
    max_k = int(np.log2(n))
    if max_k < 2: return np.nan
    ns, rs_vals = [], []
    for k in range(1, max_k + 1):
        chunk_size = n // (2 ** k)
        if chunk_size < min_n: break
        rs_list = []
        for start in range(0, n - chunk_size + 1, chunk_size):
            chunk = series[start:start + chunk_size]
            mean_c = np.mean(chunk)
            dev = np.cumsum(chunk - mean_c)
            r = np.max(dev) - np.min(dev)
            s = np.std(chunk, ddof=1)
            if s > 1e-12: rs_list.append(r / s)
        if rs_list:
            ns.append(chunk_size)
            rs_vals.append(np.mean(rs_list))
    if len(ns) < 2: return np.nan
    slope = np.polyfit(np.log(ns), np.log(rs_vals), 1)[0]
    return np.clip(slope, 0, 1)

# ── 5 MODEL FEATURE BUILDERS ──

def build_vol_features(df_15m):
    """Features for 1H/4H Vol Regime model (built on 15M resampled to 1H)."""
    df = df_15m.copy()
    lr = np.log(df["Close"] / df["Close"].shift(1))

    feat = pd.DataFrame(index=df.index)
    feat["ret_lag1"] = lr.shift(1)
    feat["ret_lag2"] = lr.shift(2)
    feat["ret_lag4"] = lr.shift(4)
    feat["ret_lag8"] = lr.shift(8)

    for w in [4, 8, 16]:
        feat[f"GK_{w}"]  = garman_klass(df, w).shift(1)
        feat[f"PK_{w}"]  = parkinson(df, w).shift(1)
        feat[f"RS_{w}"]  = rogers_satchell(df, w).shift(1)

    feat["HV_16"] = lr.rolling(16).std().shift(1)
    feat["HV_96"] = lr.rolling(96).std().shift(1)
    feat["vol_ratio_16_96"] = feat["HV_16"] / (feat["HV_96"] + 1e-9)

    feat["range_ratio"] = range_ratio(df).shift(1)
    feat["tickvol_accel"] = tick_vol_acceleration(df).shift(1)

    delta = lr.copy()
    gain = delta.clip(lower=0).rolling(14).mean()
    loss = (-delta).clip(lower=0).rolling(14).mean()
    rs = gain / (loss + 1e-9)
    feat["rsi_14"] = (100 - 100 / (1 + rs)).shift(1)

    ma20 = df["Close"].rolling(20).mean()
    std20 = df["Close"].rolling(20).std()
    feat["bb_pos"] = ((df["Close"] - ma20) / (2 * std20 + 1e-9)).shift(1)

    closes = df["Close"].values
    hurst_vals = np.full(len(closes), np.nan)
    for i in range(32, len(closes)):
        hurst_vals[i] = hurst_rs(closes[i-32:i])
    feat["hurst_32"] = pd.Series(hurst_vals, index=df.index).shift(1)

    feat["roc_4"]  = (df["Close"] / df["Close"].shift(4) - 1).shift(1)
    feat["roc_16"] = (df["Close"] / df["Close"].shift(16) - 1).shift(1)
    feat["roc_96"] = (df["Close"] / df["Close"].shift(96) - 1).shift(1)

    hours = df.index.hour + df.index.minute / 60.0
    feat["hour_sin"] = pd.Series(np.sin(2 * np.pi * hours / 24.0), index=df.index).shift(1)
    feat["hour_cos"] = pd.Series(np.cos(2 * np.pi * hours / 24.0), index=df.index).shift(1)
    dow = df.index.dayofweek
    feat["dow_sin"] = pd.Series(np.sin(2 * np.pi * dow / 5.0), index=df.index).shift(1)
    feat["dow_cos"] = pd.Series(np.cos(2 * np.pi * dow / 5.0), index=df.index).shift(1)

    return feat


def build_tape_features(df_15m):
    """Tape speed features at 15M."""
    feat = pd.DataFrame(index=df_15m.index)
    tv = df_15m["Tick_Volume"].astype(float)
    feat["sum_tickvol"] = tv.rolling(4).sum().shift(1)  # ~1 hour
    feat["avg_tickvol"] = tv.rolling(4).mean().shift(1)
    feat["max_tickvol"] = tv.rolling(16).max().shift(1)
    feat["std_tickvol"] = tv.rolling(16).std().shift(1)
    feat["tape_cv"] = feat["std_tickvol"] / (feat["avg_tickvol"] + 1e-9)

    price_range = (df_15m["High"] - df_15m["Low"]).rolling(4).mean().shift(1)
    feat["range_per_tick"] = price_range / (feat["sum_tickvol"] + 1e-9)
    feat["tick_density"] = feat["sum_tickvol"] / (price_range + 1e-9)

    for w, name in [(96, "tv_zscore_20"), (576, "tv_zscore_96")]:
        roll_mu  = tv.rolling(w).mean()
        roll_std = tv.rolling(w).std().replace(0, np.nan)
        feat[name] = ((tv - roll_mu) / roll_std).fillna(0).shift(1)

    feat["log_sum_tickvol"] = np.log1p(feat["sum_tickvol"])

    hours = df_15m.index.hour + df_15m.index.minute / 60.0
    feat["hour_sin"] = np.sin(2 * np.pi * hours / 24.0)
    feat["hour_cos"] = np.cos(2 * np.pi * hours / 24.0)
    dow = df_15m.index.dayofweek
    feat["dow_sin"] = np.sin(2 * np.pi * dow / 5.0)
    feat["dow_cos"] = np.cos(2 * np.pi * dow / 5.0)
    feat["is_ny"] = ((df_15m.index.hour >= 14) & (df_15m.index.hour < 21)).astype(float)
    feat["is_london"] = ((df_15m.index.hour >= 8) & (df_15m.index.hour < 17)).astype(float)
    feat["is_overlap"] = ((df_15m.index.hour >= 14) & (df_15m.index.hour < 17)).astype(float)

    return feat


def build_vwap_features(df_15m):
    """VWAP copilot features at 15M."""
    feat = pd.DataFrame(index=df_15m.index)
    df_temp = df_15m.copy()
    df_temp["date"] = df_temp.index.date
    df_temp["typ_price"] = (df_temp["High"] + df_temp["Low"] + df_temp["Close"]) / 3.0
    df_temp["tv"] = df_temp["typ_price"] * df_temp["Tick_Volume"]
    cum_vol = df_temp.groupby("date")["Tick_Volume"].cumsum()
    cum_tv = df_temp.groupby("date")["tv"].cumsum()
    vwap = cum_tv / cum_vol.replace(0, np.nan)
    df_temp["tv2"] = (df_temp["typ_price"] ** 2) * df_temp["Tick_Volume"]
    cum_tv2 = df_temp.groupby("date")["tv2"].cumsum()
    vwap_var = (cum_tv2 / cum_vol.replace(0, np.nan)) - (vwap ** 2)
    vwap_std = np.sqrt(vwap_var.clip(lower=1e-9))
    feat["vwap"] = vwap.shift(1)
    feat["vwap_std"] = vwap_std.shift(1)
    feat["vwap_zscore"] = ((df_15m["Close"] - vwap) / vwap_std.replace(0, np.nan)).shift(1)
    lr = np.log(df_15m["Close"] / df_15m["Close"].shift(1))
    for lag in [1, 2, 4, 8, 16]:
        feat[f"ret_lag{lag}"] = lr.shift(lag)
    for w in [4, 8, 16]:
        feat[f"GK_{w}"] = garman_klass(df_15m, w).shift(1)
    feat["HV_16"] = lr.rolling(16).std().shift(1)
    feat["HV_96"] = lr.rolling(96).std().shift(1)
    feat["vol_ratio"] = feat["HV_16"] / (feat["HV_96"] + 1e-9)
    feat["roc_4"] = (df_15m["Close"] / df_15m["Close"].shift(4) - 1).shift(1)
    feat["roc_16"] = (df_15m["Close"] / df_15m["Close"].shift(16) - 1).shift(1)
    feat["roc_96"] = (df_15m["Close"] / df_15m["Close"].shift(96) - 1).shift(1)
    delta = lr.copy()
    gain = delta.clip(lower=0).rolling(14).mean()
    loss = (-delta).clip(lower=0).rolling(14).mean()
    rs_vec = gain / (loss + 1e-9)
    feat["rsi_14"] = (100 - 100 / (1 + rs_vec)).shift(1)
    ma20 = df_15m["Close"].rolling(20).mean()
    std20 = df_15m["Close"].rolling(20).std()
    feat["bb_pos"] = ((df_15m["Close"] - ma20) / (2 * std20 + 1e-9)).shift(1)
    feat["range_ratio"] = range_ratio(df_15m).shift(1)
    feat["tickvol_accel"] = tick_vol_acceleration(df_15m).shift(1)
    vol_4 = df_15m["Tick_Volume"].rolling(4).sum()
    vol_96_avg = df_15m["Tick_Volume"].rolling(96).mean() * 4
    feat["rtv"] = (vol_4 / vol_96_avg.replace(0, np.nan)).shift(1)
    closes = df_15m["Close"].values
    hurst_vals = np.full(len(closes), np.nan)
    for i in range(32, len(closes)):
        hurst_vals[i] = hurst_rs(closes[i-32:i])
    feat["hurst_32"] = pd.Series(hurst_vals, index=df_15m.index).shift(1)
    return feat


# ── LABEL GENERATORS FOR EACH MODEL ──

def label_vol_1h(df_15m):
    """Vol 1H label: next 4 bars = High Vol (1) or Low Vol (0)."""
    log_hl = np.log(df_15m["High"] / df_15m["Low"]) ** 2
    log_co = np.log(df_15m["Close"] / df_15m["Open"]) ** 2
    gk = np.sqrt(0.5 * log_hl - (2 * np.log(2) - 1) * log_co)
    fwd = gk.shift(-2).rolling(4).mean().shift(-3)
    roll_high = fwd.shift(1).rolling(480).quantile(0.70)
    roll_low  = fwd.shift(1).rolling(480).quantile(0.30)
    labels = pd.Series(np.nan, index=df_15m.index)
    labels[fwd >= roll_high] = 1
    labels[fwd <= roll_low]  = 0
    return labels


def label_vol_4h(df_15m):
    """Vol 4H label: next 16 bars (4 hours) = High Vol (1) or Low Vol (0)."""
    log_hl = np.log(df_15m["High"] / df_15m["Low"]) ** 2
    log_co = np.log(df_15m["Close"] / df_15m["Open"]) ** 2
    gk = np.sqrt(0.5 * log_hl - (2 * np.log(2) - 1) * log_co)
    fwd = gk.shift(-2).rolling(16).mean().shift(-15)
    roll_high = fwd.shift(1).rolling(480).quantile(0.70)
    roll_low  = fwd.shift(1).rolling(480).quantile(0.30)
    labels = pd.Series(np.nan, index=df_15m.index)
    labels[fwd >= roll_high] = 1
    labels[fwd <= roll_low]  = 0
    return labels


def label_tape_regime(df_15m):
    """Tape regime: next 16 bars (4H) = Fast (1) or Slow (0)."""
    eff = df_15m["Close"] != df_15m["Close"].shift(1)
    ar = eff.rolling(4).mean()
    fwd = ar.shift(-2).rolling(16).mean().shift(-15)
    roll_high = fwd.shift(1).rolling(480).quantile(0.70)
    roll_low  = fwd.shift(1).rolling(480).quantile(0.30)
    labels = pd.Series(np.nan, index=df_15m.index)
    labels[fwd >= roll_high] = 1
    labels[fwd <= roll_low]  = 0
    return labels


def label_micro_regime(df_15m):
    """Micro regime: next 4 bars (1H) = Fast (1) or Slow (0) at 15M level."""
    eff = df_15m["Close"] != df_15m["Close"].shift(1)
    ar = eff.rolling(4).mean()
    fwd = ar.shift(-2).rolling(4).mean().shift(-3)
    roll_high = fwd.shift(1).rolling(480).quantile(0.70)
    roll_low  = fwd.shift(1).rolling(480).quantile(0.30)
    labels = pd.Series(np.nan, index=df_15m.index)
    labels[fwd >= roll_high] = 1
    labels[fwd <= roll_low]  = 0
    return labels


def label_vwap(df_15m, max_horizon=16):
    """VWAP scalp label: does price revert to VWAP within 16 bars?"""
    prices = df_15m["Close"].values
    df_temp = df_15m.copy()
    df_temp["date"] = df_temp.index.date
    df_temp["typ_price"] = (df_temp["High"] + df_temp["Low"] + df_temp["Close"]) / 3.0
    df_temp["tv"] = df_temp["typ_price"] * df_temp["Tick_Volume"]
    cum_vol = df_temp.groupby("date")["Tick_Volume"].cumsum()
    cum_tv = df_temp.groupby("date")["tv"].cumsum()
    v = cum_tv / cum_vol.replace(0, np.nan)
    df_temp["tv2"] = (df_temp["typ_price"] ** 2) * df_temp["Tick_Volume"]
    cum_tv2 = df_temp.groupby("date")["tv2"].cumsum()
    vwap_var = (cum_tv2 / cum_vol.replace(0, np.nan)) - (v ** 2)
    vs = np.sqrt(vwap_var.clip(lower=1e-9))
    z = ((df_15m["Close"] - v) / vs.replace(0, np.nan))
    labels = pd.Series(np.nan, index=df_15m.index)
    for i in range(len(df_15m) - max_horizon):
        if pd.isna(z.iloc[i]) or abs(z.iloc[i]) < 2.0: continue
        is_long = z.iloc[i] <= -2.0
        fwd_prices = prices[i+1:i+1+max_horizon]
        fwd_v = v.iloc[i+1:i+1+max_horizon].values
        fwd_vs = vs.iloc[i+1:i+1+max_horizon].values
        hit_target = False
        for j, (p, vv, vvs) in enumerate(zip(fwd_prices, fwd_v, fwd_vs)):
            if pd.isna(vv) or pd.isna(vvs): continue
            if is_long:
                if p >= vv: hit_target = True; break
                elif p <= vv - 3.0 * vvs: break
            else:
                if p <= vv: hit_target = True; break
                elif p >= vv + 3.0 * vvs: break
        labels.iloc[i] = 1.0 if hit_target else 0.0
    return labels


# ── WALK-FORWARD PREDICTOR ──

def date_split_predict(features, labels, orig_index, split_date="2015-01-01"):
    """
    Generate OOS predictions using a date-based split.
    All models share the SAME split date, so predictions align perfectly.
    """
    split_dt = pd.Timestamp(split_date)

    train_idx = features.index[features.index < split_dt]
    test_idx  = features.index[features.index >= split_dt]

    X_tr = features.loc[train_idx]
    y_tr = labels.loc[train_idx]
    X_te = features.loc[test_idx]
    y_te = labels.loc[test_idx]

    if len(X_tr) < 1000 or len(X_te) < 100:
        print(f"      Insufficient data: train={len(X_tr)}, test={len(X_te)}")
        return pd.Series(np.nan, index=orig_index)
    if len(np.unique(y_te)) < 2 or len(np.unique(y_tr)) < 2:
        print(f"      Single class in split, skipping")
        return pd.Series(np.nan, index=orig_index)

    X_tr_vals = X_tr.values
    y_tr_vals = y_tr.values.ravel()
    X_te_vals = X_te.values
    y_te_vals = y_te.values.ravel()

    model = lgb.LGBMClassifier(
        objective="binary", metric="auc", boosting_type="gbdt",
        learning_rate=0.05, num_leaves=16, max_depth=5,
        feature_fraction=0.8, verbose=-1, n_estimators=200,
    )
    model.fit(X_tr_vals, y_tr_vals)
    preds = model.predict_proba(X_te_vals)[:, 1]

    all_preds = pd.Series(np.nan, index=orig_index)
    all_preds.loc[X_te.index] = preds

    try: auc = roc_auc_score(y_te_vals, preds)
    except: auc = np.nan
    print(f"      Holdout AUC: {auc:.4f} | Train: {len(X_tr):,} -> Test: {len(X_te):,}")
    print(f"      Test date range: {X_te.index[0].date()} to {X_te.index[-1].date()}")

    return all_preds


# ── EXECUTION MODE TARGET ──

def build_execution_target(df_15m, forward_horizon=16):
    """
    For each bar, determine the optimal execution mode:
      2 = TREND      (continuation trade would have won)
      1 = MEAN_REV   (reversion trade would have won)
      0 = NEUTRAL    (no clear edge either way)

    Compares two simulated trades at each bar:
      TREND:      enter in direction of 8-bar slope, exit in forward_horizon
      MEAN_REV:   enter against extreme move (z-score > 2), exit at mean

    The winner is the one with higher risk-adjusted outcome.
    """
    closes = df_15m["Close"].values
    L = len(closes)

    tr = pd.DataFrame({
        "hl": df_15m["High"].values - df_15m["Low"].values,
        "hc": np.abs(df_15m["High"].values - np.append(closes[0], closes[:-1])),
        "lc": np.abs(df_15m["Low"].values - np.append(closes[0], closes[:-1])),
    }).max(axis=1).values
    atr = pd.Series(tr).rolling(20).mean().bfill().values

    # Micro-trend direction: 8-bar slope (positive = trending up, negative = down)
    slope = pd.Series(closes).diff(8).fillna(0).values

    # Daily-anchored VWAP z-score for mean reversion detection
    df_temp = df_15m.copy()
    df_temp["date"] = df_temp.index.date
    df_temp["typ_price"] = (df_temp["High"] + df_temp["Low"] + df_temp["Close"]) / 3.0
    df_temp["tv"] = df_temp["typ_price"] * df_temp["Tick_Volume"]
    cum_vol = df_temp.groupby("date")["Tick_Volume"].cumsum()
    cum_tv = df_temp.groupby("date")["tv"].cumsum()
    vwap = cum_tv / cum_vol.replace(0, np.nan)
    df_temp["tv2"] = (df_temp["typ_price"] ** 2) * df_temp["Tick_Volume"]
    cum_tv2 = df_temp.groupby("date")["tv2"].cumsum()
    vwap_var = (cum_tv2 / cum_vol.replace(0, np.nan)) - (vwap ** 2)
    vwap_std = np.sqrt(vwap_var.clip(lower=1e-9))
    vwap_z = ((closes - vwap.values) / vwap_std.replace(0, np.nan).values)

    target = pd.Series(0, index=df_15m.index)

    for i in range(20, L - forward_horizon - 1):
        entry = closes[i]

        # Simulate TREND trade: go in direction of 8-bar slope
        trend_dir = np.sign(slope[i])
        if abs(trend_dir) < 0.01:
            continue  # no clear trend direction

        forward_path = closes[i+1:i+1+forward_horizon]
        if len(forward_path) == 0:
            continue

        if trend_dir > 0:  # expect UP
            trend_pnl = forward_path[-1] - entry
            trend_high = np.max(forward_path)
            trend_low = np.min(forward_path)
        else:  # expect DOWN
            trend_pnl = entry - forward_path[-1]
            trend_high = entry - np.min(forward_path)
            trend_low = np.max(forward_path) - entry

        trend_r = trend_pnl / atr[i]

        # Simulate MEAN_REV trade: only if price is extended (>1.5 ATR from VWAP or MA)
        dist_from_vwap = abs(vwap_z[i]) if not np.isnan(vwap_z[i]) else 0.0

        ma20 = np.mean(closes[i-19:i+1]) if i >= 19 else entry
        dist_from_ma = (entry - ma20) / atr[i]

        if abs(dist_from_ma) >= 1.5 or dist_from_vwap >= 1.5:
            # Enter reversion (fade the move)
            rev_dir = -np.sign(dist_from_ma) if abs(dist_from_ma) >= 1.5 else -np.sign(vwap_z[i]) if not np.isnan(vwap_z[i]) else 0
            if rev_dir > 0:  # expect UP (price was too low)
                rev_pnl = forward_path[-1] - entry
            elif rev_dir < 0:  # expect DOWN (price was too high)
                rev_pnl = entry - forward_path[-1]
            else:
                rev_pnl = 0

            rev_r = rev_pnl / atr[i]

            # Check max adverse excursion for mean-rev
            if rev_dir > 0:
                rev_mae = (entry - np.min(forward_path)) / atr[i]
            elif rev_dir < 0:
                rev_mae = (np.max(forward_path) - entry) / atr[i]
            else:
                rev_mae = 1.0
        else:
            rev_r = -0.2  # no edge, penalise
            rev_mae = 1.0

        # ---- SCORING ----
        # TREND score: reward clean continuation, penalise reversal
        trend_score = trend_r
        if trend_dir > 0:
            max_rev = entry - np.min(forward_path)
            trend_mae = max_rev / atr[i] if max_rev > 0 else 0
        else:
            max_rev = np.max(forward_path) - entry
            trend_mae = max_rev / atr[i] if max_rev > 0 else 0
        trend_score -= trend_mae * 0.3  # penalty for adverse movement

        # MEAN_REV score: reward snap-back, penalise continuation
        rev_score = rev_r - rev_mae * 0.3

        # DECISION
        delta = trend_score - rev_score
        if abs(delta) < 0.3:
            target.iloc[i] = 0  # NEUTRAL (too close to call)
        elif trend_score > rev_score and trend_score > 0.3:
            target.iloc[i] = 2  # TREND
        elif rev_score > trend_score and rev_score > 0.3:
            target.iloc[i] = 1  # MEAN_REV

    return target


# ── MAIN ──

def main():
    print("=" * 70)
    print("  EXECUTION MATRIX OPTIMIZER")
    print("  Finds optimal Trend/MeanRev/Neutral conditions from 5 ML models")
    print("=" * 70)

    # ── 1. LOAD DATA ──
    data_path = "/Users/macos/Documents/ALGO/03_Data/raw/GOLD_XAUUSD/XAUUSD_M5.csv"
    print(f"\n[1] Loading {data_path}...")
    df_raw = load_mt5_csv(data_path)
    df_15m = resample_to_15m(df_raw)
    print(f"    {len(df_15m):,} 15M bars ({df_15m.index[0].date()} -> {df_15m.index[-1].date()})")

    # ── 2. GENERATE ALL 5 PROBABILITIES ──
    print("\n[2] Generating 5 model probability streams...")

    models_data = {}
    SPLIT_DATE = "2015-01-01"

    # 2a. Vol 1H
    print("\n  2a. Vol 1H...")
    vol_features = build_vol_features(df_15m)
    vol_label_1h = label_vol_1h(df_15m)
    valid_1h = vol_features.notna().all(axis=1) & vol_label_1h.notna()
    Xv1 = vol_features[valid_1h]
    yv1 = vol_label_1h[valid_1h]
    if len(Xv1) > 5000:
        print(f"      Samples: {len(Xv1):,} | Base rate: {yv1.mean():.2%}")
        prob_vol_1h = date_split_predict(Xv1, yv1, df_15m.index, SPLIT_DATE)
        models_data["vol_1h"] = prob_vol_1h
    else:
        print(f"      Insufficient data: {len(Xv1)}")

    # 2b. Vol 4H
    print("\n  2b. Vol 4H...")
    vol_label_4h = label_vol_4h(df_15m)
    valid_4h = vol_features.notna().all(axis=1) & vol_label_4h.notna()
    Xv4 = vol_features[valid_4h]
    yv4 = vol_label_4h[valid_4h]
    if len(Xv4) > 5000:
        print(f"      Samples: {len(Xv4):,} | Base rate: {yv4.mean():.2%}")
        prob_vol_4h = date_split_predict(Xv4, yv4, df_15m.index, SPLIT_DATE)
        models_data["vol_4h"] = prob_vol_4h
    else:
        print(f"      Insufficient data: {len(Xv4)}")

    # 2c. Tape
    print("\n  2c. Tape Speed...")
    tape_features = build_tape_features(df_15m)
    tape_label = label_tape_regime(df_15m)
    valid_t = tape_features.notna().all(axis=1) & tape_label.notna()
    Xt = tape_features[valid_t]
    yt = tape_label[valid_t]
    if len(Xt) > 5000:
        print(f"      Samples: {len(Xt):,} | Base rate: {yt.mean():.2%}")
        prob_tape = date_split_predict(Xt, yt, df_15m.index, SPLIT_DATE)
        models_data["tape"] = prob_tape
    else:
        print(f"      Insufficient data: {len(Xt)}")

    # 2d. Micro
    print("\n  2d. Micro Regime...")
    micro_label = label_micro_regime(df_15m)
    valid_m = vol_features.notna().all(axis=1) & micro_label.notna()
    Xm = vol_features[valid_m]
    ym = micro_label[valid_m]
    if len(Xm) > 5000:
        print(f"      Samples: {len(Xm):,} | Base rate: {ym.mean():.2%}")
        prob_micro = date_split_predict(Xm, ym, df_15m.index, SPLIT_DATE)
        models_data["micro"] = prob_micro
    else:
        print(f"      Insufficient data: {len(Xm)}")

    # 2e. VWAP
    print("\n  2e. VWAP Copilot...")
    vwap_features = build_vwap_features(df_15m)
    vwap_label = label_vwap(df_15m)
    valid_v = vwap_features.notna().all(axis=1) & vwap_label.notna()
    Xv = vwap_features[valid_v]
    yv = vwap_label[valid_v]
    if len(Xv) > 5000:
        print(f"      Samples: {len(Xv):,} | Base rate: {yv.mean():.2%}")
        prob_vwap = date_split_predict(Xv, yv, df_15m.index, SPLIT_DATE)
        models_data["vwap"] = prob_vwap
    else:
        print(f"      Insufficient data: {len(Xv)}")

    # ── 3. BUILD EXECUTION TARGET ──
    print("\n[3] Building execution mode targets (forward-looking)...")
    exec_target = build_execution_target(df_15m)
    counts = exec_target.value_counts()
    print(f"      TREND (2)    : {counts.get(2, 0):,}")
    print(f"      MEAN_REV (1) : {counts.get(1, 0):,}")
    print(f"      NEUTRAL (0)  : {counts.get(0, 0):,}")

    # ── 4. ALIGN ALL PROBABILITIES INTO A SINGLE MATRIX ──
    print("\n[4] Aligning probability streams...")
    prob_matrix = pd.DataFrame(index=df_15m.index)
    for name, series in models_data.items():
        non_nan = series.notna().sum()
        print(f"      {name}: {non_nan:,} non-NaN values")
        prob_matrix[name] = series.reindex(df_15m.index)
    prob_matrix["exec_target"] = exec_target.reindex(df_15m.index)

    for col in ["hurst_32", "rsi_14", "bb_pos", "vol_ratio_16_96", "roc_16"]:
        prob_matrix[col] = vol_features[col].reindex(df_15m.index) if col in vol_features.columns else np.nan
    vwap_z = vwap_features["vwap_zscore"] if "vwap_zscore" in vwap_features.columns else pd.Series(np.nan, index=df_15m.index)
    prob_matrix["vwap_zscore"] = vwap_z.reindex(df_15m.index)

    prob_cols = [c for c in prob_matrix.columns if c != "exec_target"]
    # Drop columns that are entirely NaN
    prob_cols = [c for c in prob_cols if prob_matrix[c].notna().sum() > 0]
    prob_matrix = prob_matrix[prob_cols + ["exec_target"]].copy()

    valid = prob_matrix[prob_cols].notna().all(axis=1) & prob_matrix["exec_target"].notna()
    df_aligned = prob_matrix[valid].copy()
    print(f"      Aligned samples: {len(df_aligned):,}")
    print(f"      Feature columns: {prob_cols}")

    if len(df_aligned) < 100:
        print("\n  ⚠️  Fewer than 100 aligned samples — trying without raw features...")
        model_cols = [c for c in prob_cols if c in models_data and prob_matrix[c].notna().sum() > 0]
        valid2 = prob_matrix[model_cols].notna().all(axis=1) & prob_matrix["exec_target"].notna()
        df_aligned = prob_matrix[model_cols + ["exec_target"]].loc[valid2].copy()
        prob_cols = model_cols
        print(f"      Aligned samples (model-only): {len(df_aligned):,}")
        if len(df_aligned) < 100:
            # Last resort: pick just the best model (vol_4h)
            fallback_cols = ["vol_4h", "vol_1h", "exec_target"]
            valid3 = prob_matrix[["vol_4h", "vol_1h"]].notna().all(axis=1) & prob_matrix["exec_target"].notna()
            df_aligned = prob_matrix[fallback_cols].loc[valid3].copy()
            prob_cols = ["vol_4h", "vol_1h"]
            print(f"      Aligned samples (fallback vol_4h+vol_1h): {len(df_aligned):,}")

    # ── 5. DECISION TREE RULES ──
    print("\n[5] Training Decision Tree (max_depth=3) for interpretable rules...")
    X_aligned = df_aligned[prob_cols].values
    y_aligned = df_aligned["exec_target"].values.astype(int)

    # Multiclass DT
    dt = DecisionTreeClassifier(max_depth=3, min_samples_leaf=50, random_state=42)
    dt.fit(X_aligned, y_aligned)
    rules = export_text(dt, feature_names=prob_cols)
    print("\n" + "─" * 50)
    print("  DECISION TREE RULES (max_depth=3)")
    print("─" * 50)
    print(rules)

    # Feature importance
    print("\n  FEATURE IMPORTANCE:")
    for name, imp in sorted(zip(prob_cols, dt.feature_importances_),
                            key=lambda x: x[1], reverse=True):
        if imp > 0:
            print(f"    {name:20s} : {imp:.3f}")

    # ── 6. RANDOM FOREST FOR ROBUST IMPORTANCE ──
    print("\n[6] Random Forest for robust importance...")
    rf = RandomForestClassifier(n_estimators=200, max_depth=5,
                                min_samples_leaf=50, random_state=42,
                                n_jobs=-1, verbose=0)
    rf.fit(X_aligned, y_aligned)
    rf_acc = rf.score(X_aligned, y_aligned)
    print(f"      RF In-Sample Accuracy: {rf_acc:.4f}")

    print("\n  RANDOM FOREST FEATURE IMPORTANCE:")
    for name, imp in sorted(zip(prob_cols, rf.feature_importances_),
                            key=lambda x: x[1], reverse=True):
        if imp > 0.01:
            print(f"    {name:20s} : {imp:.3f}")

    # ── 7. EXTRACT THRESHOLD RULES FOR MQL5 ──
    print("\n[7] Extracting threshold rules for MQL5...")
    tree_data = dt.tree_
    feature_names_arr = np.array(prob_cols)
    left = tree_data.children_left
    right = tree_data.children_right
    threshold = tree_data.threshold
    features_idx = tree_data.feature
    value = tree_data.value

    print("\n  IF-THEN rules from Decision Tree:")
    print("  ─────────────────────────────────")

    def recurse(node, depth=0, conditions=None):
        if conditions is None:
            conditions = []
        if left[node] == right[node]:  # leaf
            counts = value[node][0]
            total = counts.sum()
            cls = np.argmax(counts)
            pct = counts[cls] / total * 100 if total > 0 else 0
            label_map = {2: "TREND EXECUTION", 1: "MEAN REVERSION", 0: "CASH / NEUTRAL"}
            label = label_map.get(cls, "UNKNOWN")
            print(f"  → {label}  ({pct:.0f}% of {int(total)} samples)")
            if conditions:
                for c in conditions:
                    print(f"    {c}")
            print()
            return
        feat_name = feature_names_arr[features_idx[node]]
        th = threshold[node]
        left_cond = f"if {feat_name} <= {th:.3f}"
        right_cond = f"if {feat_name} > {th:.3f}"
        recurse(left[node], depth + 1, conditions + [left_cond])
        recurse(right[node], depth + 1, conditions + [right_cond])

    recurse(0)

    # ── 8. BINARY CLASSIFIER FOR EACH MODE ──
    print("\n[8] Binary classifiers for each mode (what best predicts each?)...")
    for mode, mode_name in [(2, "TREND"), (1, "MEAN_REV"), (0, "NEUTRAL")]:
        y_bin = (y_aligned == mode).astype(int)
        if y_bin.sum() < 100:
            print(f"  {mode_name}: too few samples ({y_bin.sum()}), skipping")
            continue
        dt_bin = DecisionTreeClassifier(max_depth=2, min_samples_leaf=50, random_state=42)
        dt_bin.fit(X_aligned, y_bin)
        rules_bin = export_text(dt_bin, feature_names=prob_cols)
        print(f"\n  ── {mode_name} ──")
        print(rules_bin)

    # ── 9. VISUALIZATION ──
    print("\n[9] Generating probability distribution plots...")
    fig, axes = plt.subplots(3, 2, figsize=(16, 14))
    fig.patch.set_facecolor("#0d0d0d")
    fig.suptitle("Execution Matrix: Probability Distributions by Target Mode",
                 color="white", fontsize=14, fontweight="bold")

    mode_colors = {0: "#888888", 1: "#00BFFF", 2: "#FFD700"}
    mode_labels = {0: "NEUTRAL", 1: "MEAN_REV", 2: "TREND"}

    for idx, col in enumerate(prob_cols[:6]):
        row, col_idx = divmod(idx, 2)
        ax = axes[row, col_idx]
        ax.set_facecolor("#141414")
        for mode_val in [0, 1, 2]:
            subset = df_aligned[df_aligned["exec_target"] == mode_val][col].dropna()
            if len(subset) < 10: continue
            ax.hist(subset, bins=30, alpha=0.4, color=mode_colors[mode_val],
                    label=f"{mode_labels[mode_val]} (n={len(subset)})",
                    density=True)
        ax.set_title(col, color="white", fontsize=11)
        ax.legend(facecolor="#1e1e1e", edgecolor="none", labelcolor="white", fontsize=8)
        ax.tick_params(colors="white")
        ax.grid(True, alpha=0.2)

    plt.tight_layout()
    path = f"{ARTIFACT_DIR}/execution_matrix_distributions.png"
    plt.savefig(path, dpi=150, facecolor="#0d0d0d", bbox_inches="tight")
    plt.close()
    print(f"    Saved: {path}")

    # ── 10. CONDITION DISTRIBUTION PLOT ──
    print("\n[10] Generating mode transition heatmap...")
    fig2, ax2 = plt.subplots(figsize=(8, 6))
    fig2.patch.set_facecolor("#0d0d0d")
    ax2.set_facecolor("#141414")

    # Mode counts by quarter
    df_aligned["quarter"] = df_aligned.index.to_period("Q")
    pivot = df_aligned.groupby("quarter")["exec_target"].value_counts(normalize=True).unstack(fill_value=0)
    for c in [0, 1, 2]:
        if c not in pivot.columns:
            pivot[c] = 0.0
    pivot = pivot[[0, 1, 2]]
    pivot.columns = ["NEUTRAL", "MEAN_REV", "TREND"]
    im = ax2.imshow(pivot.values.T, aspect="auto", cmap="RdYlGn", vmin=0, vmax=0.7)
    ax2.set_yticks([0, 1, 2])
    ax2.set_yticklabels(["NEUTRAL", "MEAN_REV", "TREND"], color="white")
    ax2.set_xticks(range(len(pivot)))
    ax2.set_xticklabels([str(q) for q in pivot.index], color="white",
                         fontsize=7, rotation=45)
    ax2.set_title("Execution Mode Distribution Over Time", color="white")
    plt.colorbar(im, ax=ax2)

    plt.tight_layout()
    path2 = f"{ARTIFACT_DIR}/execution_matrix_heatmap.png"
    plt.savefig(path2, dpi=150, facecolor="#0d0d0d", bbox_inches="tight")
    plt.close()
    print(f"    Saved: {path2}")

    # ── 11. BINARY LOGISTIC REGRESSION FEATURE IMPACT ──
    print("\n[11] Logistic Regression coefficients for interpretability...")
    from sklearn.linear_model import LogisticRegression
    from sklearn.preprocessing import StandardScaler
    for mode, mode_name in [(2, "TREND"), (1, "MEAN_REV")]:
        y_bin = (y_aligned == mode).astype(int)
        if y_bin.sum() < 100:
            print(f"  {mode_name}: too few samples ({y_bin.sum()}), skipping")
            continue
        scaler = StandardScaler()
        X_scaled = scaler.fit_transform(X_aligned)
        lr = LogisticRegression(C=1.0, max_iter=1000, class_weight="balanced")
        lr.fit(X_scaled, y_bin)
        coefs = pd.Series(lr.coef_[0], index=prob_cols).sort_values()
        print(f"\n  ── {mode_name} (LogReg coefficients) ──")
        for name, coef in coefs.items():
            if abs(coef) > 0.01:
                arrow = "↑" if coef > 0 else "↓"
                print(f"    {arrow} {name:20s} : {coef:+.4f}")

    print("\n" + "=" * 70)
    print("  OPTIMIZATION COMPLETE")
    print("  Rules above can be copied into MQL5 DashboardUI.mqh")
    print("=" * 70)


if __name__ == "__main__":
    main()
