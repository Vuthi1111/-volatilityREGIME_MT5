import sys, os, time, asyncio
sys.path.insert(0, '/Users/macos/Documents/ALGO/projects/volatility_regime_model/src')
sys.path.insert(0, '/Users/macos/Documents/ALGO/projects/volatility_regime_model')
from feature_engineering import load_mt5_csv, build_features, resample_to_4h
from dashboard import DashboardApp
from live_inference import load_production_model, compute_speed_of_tape_state, load_speed_of_tape_model, compute_micro_regime_state, load_micro_regime_model, compute_vwap_copilot_state, load_vwap_copilot_model

async def profile_update():
    app = DashboardApp()
    app.news_events = []
    
    t0 = time.time()
    app.models["NAS100"] = load_production_model("NAS100")
    app.speed_tape_models["NAS100"] = load_speed_of_tape_model("NAS100")
    app.micro_regime_models["NAS100"] = load_micro_regime_model("NAS100")
    app.vwap_copilot_models["NAS100"] = load_vwap_copilot_model("NAS100")
    print(f"Load models: {time.time()-t0:.3f}s")
    
    path_1h = os.path.expanduser('~/Library/Application Support/CrossOver/Bottles/MT5/drive_c/Program Files/MetaTrader 5/MQL5/Files/nas100_live.csv')
    path_1m = os.path.expanduser('~/Library/Application Support/CrossOver/Bottles/MT5/drive_c/Program Files/MetaTrader 5/MQL5/Files/nas100_live_1m.csv')
    
    class MockElem:
        def update(self, *a, **k): pass
    app.query_one = lambda *a, **k: MockElem()
    app._log = lambda m: None
    
    t0 = time.time()
    df_live = load_mt5_csv(path_1h)
    print(f"Load 1H CSV ({len(df_live)} rows): {time.time()-t0:.3f}s")
    
    t0 = time.time()
    # Mocking _compute_inference for 1H
    model, scaler, feature_cols = app.models["NAS100"]["1H"]
    lf_1h = build_features(df_live)
    print(f"build_features 1H: {time.time()-t0:.3f}s")
    
    t0 = time.time()
    df_live_4h = resample_to_4h(df_live)
    print(f"resample_to_4h: {time.time()-t0:.3f}s")
    
    t0 = time.time()
    model4, scaler4, feat_cols4 = app.models["NAS100"]["4H"]
    lf_4h = build_features(df_live_4h)
    print(f"build_features 4H: {time.time()-t0:.3f}s")
    
    t0 = time.time()
    df_live_1m = load_mt5_csv(path_1m)
    print(f"Load 1M CSV ({len(df_live_1m)} rows): {time.time()-t0:.3f}s")
    
    t0 = time.time()
    st_model, st_feat = app.speed_tape_models["NAS100"]
    compute_speed_of_tape_state(df_live_1m, st_model, st_feat)
    print(f"compute_speed_of_tape: {time.time()-t0:.3f}s")
    
    t0 = time.time()
    mr_model, mr_feat = app.micro_regime_models["NAS100"]
    compute_micro_regime_state(df_live_1m, mr_model, mr_feat)
    print(f"compute_micro_regime: {time.time()-t0:.3f}s")
    
    t0 = time.time()
    vwap_model, vwap_feat = app.vwap_copilot_models["NAS100"]
    compute_vwap_copilot_state(df_live_1m, vwap_model, vwap_feat)
    print(f"compute_vwap_copilot: {time.time()-t0:.3f}s")

asyncio.run(profile_update())
