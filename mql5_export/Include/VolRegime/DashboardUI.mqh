#ifndef __VOLREGIME_DASHBOARD_UI_MQH__
#define __VOLREGIME_DASHBOARD_UI_MQH__

#include <VolRegime/Types.mqh>

string VRPanelName(const long chart_id, const string suffix)
{
   return "VRM_" + IntegerToString((int)chart_id) + "_" + suffix;
}

void VRCreateOrUpdateLabel(const long chart_id,
                           const string name,
                           const int x,
                           const int y,
                           const string text,
                           const color clr,
                           const int font_size,
                           const string font = "Consolas")
{
   if(ObjectFind(chart_id, name) < 0)
   {
      ObjectCreate(chart_id, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(chart_id, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(chart_id, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   }
   ObjectSetInteger(chart_id, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(chart_id, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(chart_id, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(chart_id, name, OBJPROP_FONTSIZE, font_size);
   ObjectSetString(chart_id, name, OBJPROP_FONT, font);
   ObjectSetString(chart_id, name, OBJPROP_TEXT, text);
}

void VRCreateOrUpdateRect(const long chart_id,
                          const string name,
                          const int x,
                          const int y,
                          const int w,
                          const int h,
                          const color bg,
                          const color border)
{
   if(ObjectFind(chart_id, name) < 0)
   {
      ObjectCreate(chart_id, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(chart_id, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(chart_id, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(chart_id, name, OBJPROP_BACK, true);
   }
   ObjectSetInteger(chart_id, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(chart_id, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(chart_id, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(chart_id, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(chart_id, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(chart_id, name, OBJPROP_COLOR, border);
}

color VRProbColor(const double p, const double threshold)
{
   if(p >= threshold + 0.15) return clrLime;
   if(p >= threshold) return clrGold;
   return clrTomato;
}

string VRRegimeLabel(const double p, const double threshold, const string high_label, const string low_label)
{
   if(p >= threshold) return high_label;
   return low_label;
}

void VRRenderPanel(const long chart_id,
                   const VRDashboardLayout &layout,
                   const string panel_id,
                   const int x,
                   const int y,
                   const int w,
                   const int h,
                   const string title,
                   const string line1,
                   const string line2,
                   const color accent)
{
   VRCreateOrUpdateRect(chart_id, panel_id + "_BG", x, y, w, h, layout.bg_panel, layout.border);
   VRCreateOrUpdateLabel(chart_id, panel_id + "_TITLE", x + 10, y + 8, title, layout.text_main, 10, "Consolas Bold");
   VRCreateOrUpdateLabel(chart_id, panel_id + "_LINE1", x + 10, y + 30, line1, accent, 11, "Consolas Bold");
   VRCreateOrUpdateLabel(chart_id, panel_id + "_LINE2", x + 10, y + 52, line2, layout.text_dim, 9, "Consolas");
}

void VRRenderDashboard(const long chart_id,
                       const VRDashboardLayout &layout,
                       const VRInferenceSnapshot &snapshot,
                       const double threshold)
{
   int x = layout.x;
   int y = layout.y;
   int w = layout.panel_width;
   int h = layout.panel_height;
   int g = layout.gap;

   string header = snapshot.symbol + " | " + TimeToString(snapshot.source_time, TIME_DATE|TIME_MINUTES);
   VRCreateOrUpdateLabel(chart_id, VRPanelName(chart_id, "HEADER"), x, y - 22, header, layout.text_main, 11, "Consolas Bold");

   string line1 = StringFormat("1H Vol: %.1f%%  %s", snapshot.vol_1h_prob * 100.0, VRRegimeLabel(snapshot.vol_1h_prob, threshold, "EXPANSIVE", "COMPRESSIVE"));
   string line2 = StringFormat("4H Vol: %.1f%%  %s", snapshot.vol_4h_prob * 100.0, VRRegimeLabel(snapshot.vol_4h_prob, threshold, "EXPANSIVE", "COMPRESSIVE"));
   VRRenderPanel(chart_id, layout, VRPanelName(chart_id, "VOL"), x, y, w, h, "Volatility Regime", line1, line2, VRProbColor(snapshot.vol_1h_prob, threshold));

   line1 = StringFormat("Tape: %.1f%%  %s", snapshot.tape_prob * 100.0, VRRegimeLabel(snapshot.tape_prob, threshold, "FAST", "SLOW"));
   line2 = StringFormat("AR %.3f  Silent %.3f  Mom %.3f", snapshot.features.latest_active_ratio, snapshot.features.latest_silent_ratio, snapshot.features.latest_tape_momentum);
   VRRenderPanel(chart_id, layout, VRPanelName(chart_id, "TAPE"), x + w + g, y, w, h, "Speed of Tape", line1, line2, VRProbColor(snapshot.tape_prob, threshold));

   line1 = StringFormat("Micro: %.1f%%  %s", snapshot.micro_prob * 100.0, VRRegimeLabel(snapshot.micro_prob, threshold, "FAST", "SLOW"));
   line2 = StringFormat("RSI %.1f  BB %.3f  RTV %.3f", snapshot.features.latest_rsi_14, snapshot.features.latest_bb_pos, snapshot.features.latest_rtv);
   VRRenderPanel(chart_id, layout, VRPanelName(chart_id, "MICRO"), x, y + h + g, w, h, "Micro Regime", line1, line2, VRProbColor(snapshot.micro_prob, threshold));

   line1 = StringFormat("VWAP: %.1f%%  z=%.3f", snapshot.vwap_prob * 100.0, snapshot.features.latest_vwap_zscore);
   line2 = StringFormat("H32 %.3f  H90 %.3f  Accel %.3f", snapshot.features.latest_hurst_32, snapshot.features.latest_hurst_90, snapshot.features.latest_tickvol_accel);
   VRRenderPanel(chart_id, layout, VRPanelName(chart_id, "VWAP"), x + w + g, y + h + g, w, h, "VWAP Copilot", line1, line2, VRProbColor(snapshot.vwap_prob, threshold));

   string exec_mode = "CASH";
   color exec_clr = clrSilver;
   if(snapshot.news.is_blackout)
   {
      exec_mode = "NEWS BLACKOUT";
      exec_clr = clrOrangeRed;
   }
   else if(snapshot.vol_1h_prob >= threshold + 0.05 && snapshot.tape_prob >= threshold)
   {
      exec_mode = "TREND EXECUTION";
      exec_clr = clrLimeGreen;
   }
   else if(snapshot.vwap_prob >= threshold + 0.05 && snapshot.features.latest_hurst_32 < 0.50)
   {
      exec_mode = "MEAN REVERSION";
      exec_clr = clrDeepSkyBlue;
   }

   line1 = exec_mode;
   line2 = snapshot.news.is_blackout
           ? StringFormat("%s @ %s", snapshot.news.event_title, TimeToString(snapshot.news.event_time, TIME_MINUTES))
           : StringFormat("R.Ratio %.3f  VWAP z %.3f", snapshot.features.latest_range_ratio, snapshot.features.latest_vwap_zscore);
   VRRenderPanel(chart_id, layout, VRPanelName(chart_id, "EXEC"), x, y + (h + g) * 2, (w * 2) + g, h, "Execution Matrix", line1, line2, exec_clr);
}

#endif
