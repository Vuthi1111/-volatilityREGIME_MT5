import sys, os, asyncio
sys.path.insert(0, '/Users/macos/Documents/ALGO/projects/volatility_regime_model/src')
sys.path.insert(0, '/Users/macos/Documents/ALGO/projects/volatility_regime_model')
import dashboard

async def main():
    app = dashboard.DashboardApp()
    # Mock news events
    app.news_events = []
    
    # Run boot sequence manually
    await app.boot_sequence()
    
    print("--- Running update_dashboard ---")
    await app.update_dashboard()
    print("--- Done ---")
    
    print(f"NAS100 raw_state: {app.asset_last_raw_state.get('NAS100') is not None}")
    print(f"GOLD raw_state: {app.asset_last_raw_state.get('GOLD') is not None}")

asyncio.run(main())
