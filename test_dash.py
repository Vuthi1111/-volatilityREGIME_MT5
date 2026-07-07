import asyncio
from src.dashboard import DashboardApp

async def run_test():
    app = DashboardApp()
    asyncio.create_task(app.run_async(headless=True))
    await asyncio.sleep(2)
    print("Test finished successfully.")
    app.exit()

asyncio.run(run_test())
