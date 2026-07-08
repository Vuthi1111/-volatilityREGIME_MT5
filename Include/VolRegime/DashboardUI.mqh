#ifndef __VOLREGIME_DASHBOARD_UI_MQH__
#define __VOLREGIME_DASHBOARD_UI_MQH__

#include <VolRegime/Types.mqh>
#include <VolRegime/DashboardPrimitives.mqh>

color VRProbColor(const double p, const double threshold)
{
   if(p >= threshold + 0.15) return clrLime;
   if(p >= threshold) return clrGold;
   return clrTomato;
}

class CVolRegimeDashboard
{
private:
   long              m_chart_id;
   VRDashboardLayout m_layout;
   string            m_prefix;
   bool              m_minimized;
   
   int               m_x, m_y, m_w;

   // Rolling history buffers
   double            m_hist_vol_1h[6];
   double            m_hist_vol_4h[6];
   double            m_hist_tape[6];
   double            m_hist_micro[6];
   double            m_hist_vwap[6];
   
   string ObjName(string suffix)
   {
      return m_prefix + "_" + suffix;
   }

public:
   CVolRegimeDashboard(long chart_id, VRDashboardLayout &layout)
   {
      m_chart_id = chart_id;
      m_layout = layout;
      m_prefix = "VRM_" + IntegerToString((int)chart_id);
      m_minimized = false;
      m_x = layout.x;
      m_y = layout.y;
      m_w = layout.panel_width;
      
      ArrayInitialize(m_hist_vol_1h, 0.0);
      ArrayInitialize(m_hist_vol_4h, 0.0);
      ArrayInitialize(m_hist_tape, 0.0);
      ArrayInitialize(m_hist_micro, 0.0);
      ArrayInitialize(m_hist_vwap, 0.0);
   }
   
   ~CVolRegimeDashboard()
   {
      Remove();
   }
   
   void Remove()
   {
      ObjectsDeleteAll(m_chart_id, m_prefix);
   }

   void SetPosition(int x, int y, int w)
   {
      m_x = x;
      m_y = y;
      m_w = w;
   }
   
   void ToggleMinimize()
   {
      m_minimized = !m_minimized;
      Remove(); // Clear everything before re-rendering in new state
   }
   
   bool IsMinimized() const { return m_minimized; }
   
   void PushHistory(double v1, double v4, double tape, double micro, double vwap)
   {
      // Shift array right (older data moves to higher index, newest at index 0)
      for(int i = 5; i > 0; i--)
      {
         m_hist_vol_1h[i] = m_hist_vol_1h[i-1];
         m_hist_vol_4h[i] = m_hist_vol_4h[i-1];
         m_hist_tape[i] = m_hist_tape[i-1];
         m_hist_micro[i] = m_hist_micro[i-1];
         m_hist_vwap[i] = m_hist_vwap[i-1];
      }
      
      m_hist_vol_1h[0] = v1;
      m_hist_vol_4h[0] = v4;
      m_hist_tape[0] = tape;
      m_hist_micro[0] = micro;
      m_hist_vwap[0] = vwap;
   }
   
   void Render(const VRInferenceSnapshot &snap, double threshold)
   {
      string font_main = "Trebuchet MS";
      string font_mono = "Consolas";
      
      int curr_y = m_y;
      int pad_x = m_x + 15;
      int inner_w = m_w - 30;
      
      // If minimized, render only header
      if(m_minimized)
      {
         int min_h = 35;
         VRDrawRect(m_chart_id, ObjName("BG"), m_x, m_y, m_w, min_h, m_layout.bg_panel, m_layout.border);
         
         string min_txt = snap.symbol + " [AI RUNNING]";
         VRDrawLabel(m_chart_id, ObjName("HDR"), pad_x, curr_y + 10, min_txt, clrLime, 10, font_main);
         VRDrawLabel(m_chart_id, ObjName("MIN_BTN"), m_x + m_w - 20, curr_y + 10, "[+]", m_layout.text_dim, 10, font_mono);
         return;
      }
      
      // Background Panel (height updated at the end)
      VRDrawRect(m_chart_id, ObjName("BG"), m_x, m_y, m_w, 420, m_layout.bg_panel, m_layout.border);
      
      // Header
      string header_txt = snap.symbol + "  " + TimeToString(snap.source_time, TIME_MINUTES|TIME_SECONDS);
      VRDrawLabel(m_chart_id, ObjName("HDR"), pad_x, curr_y + 10, header_txt, m_layout.text_dim, 12, font_main);
      VRDrawLabel(m_chart_id, ObjName("MIN_BTN"), m_x + m_w - 20, curr_y + 10, "[-]", m_layout.text_dim, 12, font_mono);
      
      curr_y += 35;
      
      // Execution Mode Banner
      string exec_mode = "CASH / NEUTRAL";
      string exec_why = "NO EDGE FOUND";
      color exec_clr = clrSilver;
      color exec_bg = m_layout.bg_main;
      
      if(snap.news.is_blackout)
      {
         exec_mode = "NEWS BLACKOUT";
         exec_why = "MACRO EVENT ZONE";
         exec_clr = clrWhite;
         exec_bg = clrTomato;
      }
      else if(snap.vwap_prob <= 0.70)
      {
         if(snap.vol_4h_prob <= 0.23)
         {
            exec_mode = "MEAN REVERSION";
            exec_why = "[VWAP <= 0.70 | 4H VOL <= 0.23]";
            exec_clr = clrWhite;
            exec_bg = clrDodgerBlue;
         }
         else // 4H vol is medium/high
         {
            if(snap.features.latest_bb_pos <= 0.0) // proxy for negative recent momentum
            {
               exec_mode = "TREND EXECUTION";
               exec_why = "[VWAP <= 0.70 | 4H VOL > 0.23 | MOM DOWN]";
               exec_clr = clrWhite;
               exec_bg = clrForestGreen;
            }
            else 
            {
               exec_mode = "MEAN REVERSION";
               exec_why = "[VWAP <= 0.70 | 4H VOL > 0.23 | MOM UP]";
               exec_clr = clrWhite;
               exec_bg = clrDodgerBlue;
            }
         }
      }
      else // VWAP_prob > 0.70
      {
         if(snap.vol_1h_prob <= 0.05)
         {
            exec_mode = "TREND EXECUTION";
            exec_why = "[VWAP > 0.70 | 1H VOL <= 0.05]";
            exec_clr = clrWhite;
            exec_bg = clrForestGreen;
         }
         else if(snap.vol_4h_prob <= 0.25)
         {
            exec_mode = "CASH / NEUTRAL";
            exec_why = "[VWAP > 0.70 | 1H VOL > 0.05 | 4H VOL <= 0.25]";
            exec_clr = clrWhite;
            exec_bg = clrGray;
         }
         else
         {
            exec_mode = "TREND EXECUTION";
            exec_why = "[VWAP > 0.70 | 1H VOL > 0.05 | 4H VOL > 0.25]";
            exec_clr = clrWhite;
            exec_bg = clrForestGreen;
         }
      }
      
      // Update Chart Background Tint based on mode
      color tint_clr = clrNONE;
      if (exec_mode == "TREND EXECUTION") tint_clr = clrForestGreen;
      else if (exec_mode == "MEAN REVERSION") tint_clr = clrDodgerBlue;
      else if (exec_mode == "NEWS BLACKOUT") tint_clr = clrTomato;
      VRDrawChartBackground(m_chart_id, ObjName("CHART_TINT"), tint_clr, 15);
      
      VRDrawRect(m_chart_id, ObjName("EXEC_BG"), m_x + 5, curr_y, m_w - 10, 40, exec_bg);
      VRDrawLabel(m_chart_id, ObjName("EXEC_TXT"), m_x + (m_w/2), curr_y + 6, exec_mode, exec_clr, 12, font_main, ANCHOR_UPPER);
      VRDrawLabel(m_chart_id, ObjName("EXEC_WHY"), m_x + (m_w/2), curr_y + 24, exec_why, clrWhite, 8, font_mono, ANCHOR_UPPER);
      
      curr_y += 55;
      
      // Core Probabilities rendering helper
      curr_y = RenderProbBlock("VOL_1H", "1H Vol", snap.vol_1h_prob, threshold, m_hist_vol_1h, pad_x, curr_y, inner_w, font_main);
      curr_y = RenderProbBlock("VOL_4H", "4H Vol", snap.vol_4h_prob, threshold, m_hist_vol_4h, pad_x, curr_y, inner_w, font_main);
      curr_y = RenderProbBlock("TAPE", "Tape Speed", snap.tape_prob, threshold, m_hist_tape, pad_x, curr_y, inner_w, font_main);
      curr_y = RenderProbBlock("MICRO", "Micro Regime", snap.micro_prob, threshold, m_hist_micro, pad_x, curr_y, inner_w, font_main);
      curr_y = RenderProbBlock("VWAP", "VWAP Copilot", snap.vwap_prob, threshold, m_hist_vwap, pad_x, curr_y, inner_w, font_main);
      
      curr_y += 10;
      
      // Divider
      VRDrawRect(m_chart_id, ObjName("DIV1"), m_x + 5, curr_y, m_w - 10, 1, m_layout.border);
      curr_y += 10;
      
      // Metrics block
      VRDrawLabel(m_chart_id, ObjName("VWAP_Z_LBL"), pad_x, curr_y, "VWAP z-score", m_layout.text_dim, 10, font_mono);
      VRDrawLabel(m_chart_id, ObjName("VWAP_Z_VAL"), pad_x + inner_w, curr_y, StringFormat("%+.2f", snap.features.latest_vwap_zscore), clrWhite, 10, font_mono, ANCHOR_RIGHT_UPPER);
      curr_y += 18;
      VRDrawZScoreGauge(m_chart_id, ObjName("VWAP_Z_GAUGE"), pad_x, curr_y, inner_w, snap.features.latest_vwap_zscore, m_layout.bg_main);
      curr_y += 20;
      
      VRDrawTypographicRow(m_chart_id, ObjName("MET_HURST"), pad_x, curr_y, inner_w, "Hurst 32", StringFormat("%.3f", snap.features.latest_hurst_32), m_layout.text_dim, clrWhite, font_mono, 10);
      curr_y += 20;
      
      VRDrawLabel(m_chart_id, ObjName("AR_LBL"), pad_x, curr_y, "Active Ratio", m_layout.text_dim, 10, font_mono);
      VRDrawLabel(m_chart_id, ObjName("AR_VAL"), pad_x + inner_w, curr_y, StringFormat("%.2f", snap.features.latest_active_ratio), clrWhite, 10, font_mono, ANCHOR_RIGHT_UPPER);
      curr_y += 18;
      VRDrawPercentileBar(m_chart_id, ObjName("AR_BAR"), pad_x, curr_y, inner_w, snap.features.latest_active_ratio, clrDeepSkyBlue, m_layout.bg_main);
      curr_y += 16;
      
      VRDrawTypographicRow(m_chart_id, ObjName("MET_RSI"), pad_x, curr_y, inner_w, "RSI 14", StringFormat("%.1f", snap.features.latest_rsi_14), m_layout.text_dim, clrWhite, font_mono, 10);
      curr_y += 20;
      VRDrawTypographicRow(m_chart_id, ObjName("MET_BBP"), pad_x, curr_y, inner_w, "BB Pos", StringFormat("%+.2f", snap.features.latest_bb_pos), m_layout.text_dim, clrWhite, font_mono, 10);
      curr_y += 20;
      
      // Adjust total height
      int final_h = curr_y - m_y + 10;
      VRDrawRect(m_chart_id, ObjName("BG"), m_x, m_y, m_w, final_h, m_layout.bg_panel, m_layout.border);
   }
   
private:
   int RenderProbBlock(string id, string label, double prob, double threshold, double &history[], int x, int y, int w, string font)
   {
      color clr = VRProbColor(prob, threshold);
      
      // Top row: Label | Heatmap
      VRDrawLabel(m_chart_id, ObjName("PROB_LBL_" + id), x, y, label, m_layout.text_dim, 10, font);
      int sq_size = 8;
      int gap = 2;
      int heatmap_w = 6 * (sq_size + gap); 
      VRDrawHeatmapStrip(m_chart_id, ObjName("PROB_HM_" + id), x + w - heatmap_w, y + 2, history, 6, threshold, sq_size);
      
      y += 18;
      
      // Progress Bar
      VRDrawProgressBar(m_chart_id, ObjName("PROB_BAR_" + id), x, y, w, 8, prob, clr, m_layout.bg_main);
      
      y += 12;
      
      // Bottom row: pct text + arrow
      string pct_str = StringFormat("%.1f%%", prob * 100.0);
      string arrow = "->";
      if(history[0] > history[1] + 0.05) arrow = "Up"; // Using ASCII arrows to prevent MQL5 unicode issues on some PCs
      else if(history[0] < history[1] - 0.05) arrow = "Dn";
      
      string text = pct_str + " " + arrow;
      VRDrawLabel(m_chart_id, ObjName("PROB_PCT_" + id), x + w, y, text, clr, 10, font, ANCHOR_RIGHT_UPPER);
      
      return y + 24; // Advance Y for next block
   }
};

#endif
