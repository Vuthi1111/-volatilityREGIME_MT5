import xml.etree.ElementTree as ET
import requests
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

NEWS_BUFFER_MINUTES = 2

def get_forexfactory_calendar():
    """Fetches today's high-impact and holiday USD news from ForexFactory."""
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
            
            if country == "USD" and impact in ["High", "Holiday"] and d_str == today_str:
                try:
                    if not t_str or "all day" in t_str.lower() or "day" in t_str.lower() or impact == "Holiday":
                        # Holidays are all day. Let's place them at 00:00 local time
                        local_naive = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
                    else:
                        # Parse ForexFactory time (which is returned in UTC/GMT by default)
                        naive_dt = datetime.strptime(f"{d_str} {t_str}", "%m-%d-%Y %I:%M%p")
                        utc_dt = naive_dt.replace(tzinfo=ZoneInfo("UTC"))
                        
                        # Convert to system's local timezone, then make it naive for compatibility
                        local_dt = utc_dt.astimezone()
                        local_naive = local_dt.replace(tzinfo=None)

                    
                    events.append({
                        "title": title, 
                        "dt": local_naive,
                        "impact": impact
                    })
                except Exception:
                    pass
        return events
    except Exception:
        return []

def check_news_blackout(events):
    now = datetime.now()
    for ev in events:
        if ev.get('impact') == "Holiday":
            continue # Holidays do not trigger a short-term trading blackout
        if ev['dt'] - timedelta(minutes=NEWS_BUFFER_MINUTES) <= now <= ev['dt'] + timedelta(minutes=NEWS_BUFFER_MINUTES):
            return True, ev['title']
    return False, None

