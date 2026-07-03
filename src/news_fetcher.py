import xml.etree.ElementTree as ET
import requests
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

NEWS_BUFFER_MINUTES = 2

def get_forexfactory_calendar():
    """Fetches today's high-impact USD news from ForexFactory."""
    try:
        url = "https://nfs.faireconomy.media/ff_calendar_thisweek.xml"
        response = requests.get(url, timeout=10)
        root = ET.fromstring(response.content)
        events, today_str = [], datetime.now().strftime("%m-%d-%Y")
        for event in root.findall('event'):
            country = event.find('country').text
            impact  = event.find('impact').text
            d_str   = event.find('date').text
            t_str   = event.find('time').text
            title   = event.find('title').text
            if country == "USD" and impact == "High" and d_str == today_str:
                try:
                    # Parse ForexFactory time (which is US Eastern Time)
                    naive_dt = datetime.strptime(f"{d_str} {t_str}", "%m-%d-%Y %I:%M%p")
                    eastern_dt = naive_dt.replace(tzinfo=ZoneInfo("America/New_York"))
                    
                    # Convert to system's local timezone, then make it naive for compatibility
                    local_dt = eastern_dt.astimezone()
                    local_naive = local_dt.replace(tzinfo=None)
                    
                    events.append({"title": title, "dt": local_naive})
                except Exception:
                    pass
        return events
    except Exception:
        return []

def check_news_blackout(events):
    now = datetime.now()
    for ev in events:
        if ev['dt'] - timedelta(minutes=NEWS_BUFFER_MINUTES) <= now <= ev['dt'] + timedelta(minutes=NEWS_BUFFER_MINUTES):
            return True, ev['title']
    return False, None
