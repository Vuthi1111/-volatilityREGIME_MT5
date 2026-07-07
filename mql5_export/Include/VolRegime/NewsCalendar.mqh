#ifndef __VOLREGIME_NEWS_CALENDAR_MQH__
#define __VOLREGIME_NEWS_CALENDAR_MQH__

#include <VolRegime/Types.mqh>

struct VRNewsEvent
{
   datetime time;
   string   title;
   string   impact;
};

VRNewsEvent g_vr_news_events[];
int g_vr_news_blackout_before_seconds = 120;
int g_vr_news_blackout_after_seconds  = 120;

void VRNewsClear()
{
   ArrayResize(g_vr_news_events, 0);
}

void VRNewsAdd(const datetime event_time, const string title, const string impact)
{
   int size = ArraySize(g_vr_news_events);
   ArrayResize(g_vr_news_events, size + 1);
   g_vr_news_events[size].time = event_time;
   g_vr_news_events[size].title = title;
   g_vr_news_events[size].impact = impact;
}

void VRNewsLoadDefaultTemplate()
{
   VRNewsClear();
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   dt.hour = 13; dt.min = 30; dt.sec = 0;
   VRNewsAdd(StructToTime(dt), "US Macro Release", "HIGH");

   dt.hour = 15; dt.min = 0; dt.sec = 0;
   VRNewsAdd(StructToTime(dt), "Fed / Treasury Window", "MEDIUM");
}

bool VRNewsEvaluate(const datetime now_time, VRNewsState &state)
{
   VRResetNewsState(state);
   int n = ArraySize(g_vr_news_events);
   for(int i = 0; i < n; i++)
   {
      int delta = (int)(now_time - g_vr_news_events[i].time);
      if(delta >= -g_vr_news_blackout_before_seconds && delta <= g_vr_news_blackout_after_seconds)
      {
         state.is_blackout = true;
         state.event_time = g_vr_news_events[i].time;
         state.event_title = g_vr_news_events[i].title;
         state.impact = g_vr_news_events[i].impact;
         return true;
      }
   }
   return false;
}

#endif
