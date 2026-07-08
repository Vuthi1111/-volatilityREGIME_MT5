#ifndef __VOLREGIME_DASHBOARD_PRIMITIVES_MQH__
#define __VOLREGIME_DASHBOARD_PRIMITIVES_MQH__

// Primitive: Create or update a text label
void VRDrawLabel(const long chart_id,
                 const string name,
                 const int x,
                 const int y,
                 const string text,
                 const color clr,
                 const int font_size,
                 const string font = "Consolas",
                 const ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT_UPPER)
{
   if(ObjectFind(chart_id, name) < 0)
   {
      ObjectCreate(chart_id, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(chart_id, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(chart_id, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(chart_id, name, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(chart_id, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(chart_id, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(chart_id, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(chart_id, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(chart_id, name, OBJPROP_FONTSIZE, font_size);
   ObjectSetString(chart_id, name, OBJPROP_FONT, font);
   ObjectSetString(chart_id, name, OBJPROP_TEXT, text);
}

// Primitive: Create or update a filled rectangle (used for backgrounds, bars)
void VRDrawRect(const long chart_id,
                const string name,
                const int x,
                const int y,
                const int w,
                const int h,
                const color bg,
                const color border = clrNONE)
{
   if(ObjectFind(chart_id, name) < 0)
   {
      ObjectCreate(chart_id, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(chart_id, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(chart_id, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(chart_id, name, OBJPROP_BACK, true);
      ObjectSetInteger(chart_id, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(chart_id, name, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(chart_id, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(chart_id, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(chart_id, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(chart_id, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(chart_id, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(chart_id, name, OBJPROP_COLOR, border == clrNONE ? bg : border);
}

// Primitive: Draw a Progress Bar (0.0 to 1.0)
void VRDrawProgressBar(const long chart_id,
                       const string base_name,
                       const int x,
                       const int y,
                       const int w,
                       const int h,
                       const double pct,
                       const color fill_clr,
                       const color bg_clr)
{
   // Clamped percentage
   double p = MathMax(0.0, MathMin(1.0, pct));
   int fill_w = (int)MathRound(w * p);
   
   // Background
   VRDrawRect(chart_id, base_name + "_bg", x, y, w, h, bg_clr);
   
   // Fill
   if (fill_w > 0)
      VRDrawRect(chart_id, base_name + "_fill", x, y, fill_w, h, fill_clr);
   else 
   {
      // If width is 0, we can just draw a 1px bar or hide it by moving it offscreen
      VRDrawRect(chart_id, base_name + "_fill", -100, -100, 1, 1, fill_clr);
   }
}

// Primitive: Draw a single LED (square dot)
void VRDrawLED(const long chart_id,
               const string name,
               const int x,
               const int y,
               const int size,
               const color clr)
{
   VRDrawRect(chart_id, name, x, y, size, size, clr);
}

// Primitive: Typographic Row (Label on left, Value on right)
void VRDrawTypographicRow(const long chart_id,
                          const string base_name,
                          const int x,
                          const int y,
                          const int w,
                          const string label_text,
                          const string value_text,
                          const color label_clr,
                          const color value_clr,
                          const string font = "Consolas",
                          const int font_size = 9)
{
   // Left-aligned label
   VRDrawLabel(chart_id, base_name + "_lbl", x, y, label_text, label_clr, font_size, font, ANCHOR_LEFT_UPPER);
   // Right-aligned value
   VRDrawLabel(chart_id, base_name + "_val", x + w, y, value_text, value_clr, font_size, font, ANCHOR_RIGHT_UPPER);
}

// Primitive: Z-Score Gauge (-3 to +3)
void VRDrawZScoreGauge(const long chart_id,
                       const string base_name,
                       const int x,
                       const int y,
                       const int w,
                       const double zscore,
                       const color bg_clr)
{
   int h = 6;
   
   // Background bar
   VRDrawRect(chart_id, base_name + "_bg", x, y, w, h, bg_clr);
   
   // Center tick (zero)
   int center_x = x + (w / 2);
   VRDrawRect(chart_id, base_name + "_t0", center_x, y - 2, 1, h + 4, clrSilver);
   
   // +/- 2 std ticks
   int p2_x = x + (int)MathRound(w * (5.0 / 6.0));
   int m2_x = x + (int)MathRound(w * (1.0 / 6.0));
   VRDrawRect(chart_id, base_name + "_tP2", p2_x, y, 1, h, clrDimGray);
   VRDrawRect(chart_id, base_name + "_tM2", m2_x, y, 1, h, clrDimGray);
   
   // Calculate pip position
   double clamped_z = MathMax(-3.0, MathMin(3.0, zscore));
   double pct = (clamped_z + 3.0) / 6.0; // Map [-3, 3] to [0, 1]
   int pip_x = x + (int)MathRound(w * pct) - 2; // -2 for centering the 4px pip
   
   color pip_clr = clrWhite;
   if(clamped_z <= -2.0) pip_clr = clrDodgerBlue;
   if(clamped_z >= 2.0) pip_clr = clrTomato;
   
   // Pip
   VRDrawRect(chart_id, base_name + "_pip", pip_x, y - 2, 4, h + 4, pip_clr);
}

// Primitive: Percentile Bar
void VRDrawPercentileBar(const long chart_id,
                         const string base_name,
                         const int x,
                         const int y,
                         const int w,
                         const double pct,
                         const color fill_clr,
                         const color bg_clr)
{
   // Clamped percentage
   double p = MathMax(0.0, MathMin(1.0, pct));
   int fill_w = (int)MathRound(w * p);
   int h = 4;
   
   // Background
   VRDrawRect(chart_id, base_name + "_bg", x, y, w, h, bg_clr);
   
   // 50% Tick
   int center_x = x + (w / 2);
   VRDrawRect(chart_id, base_name + "_t50", center_x, y - 1, 1, h + 2, clrDimGray);
   
   // Fill
   if(fill_w > 0)
      VRDrawRect(chart_id, base_name + "_fill", x, y, fill_w, h, fill_clr);
   else
      VRDrawRect(chart_id, base_name + "_fill", -100, -100, 1, 1, fill_clr);
}

// Primitive: Heatmap Strip
// history array must have at least 'count' elements (newest at index 0)
void VRDrawHeatmapStrip(const long chart_id,
                        const string base_name,
                        const int x,
                        const int y,
                        const double &history[],
                        const int count,
                        const double threshold,
                        const int sq_size = 6)
{
   int gap = 2;
   
   for(int i = 0; i < count; i++)
   {
      // Oldest on the left, newest on the right
      // i = 0 (newest) -> rightmost
      int draw_idx = (count - 1) - i;
      int draw_x = x + (draw_idx * (sq_size + gap));
      
      color clr = clrDimGray; // default if no data
      
      // we check if we have data for this history point. 
      // simple check: if prob == 0 and not initialized, it's gray, but let's just use the threshold function
      if(i < ArraySize(history))
      {
         double p = history[i];
         if (p > 0.001) // ignore exact 0s as unitialized
         {
            if(p >= threshold + 0.15) clr = clrLime;
            else if(p >= threshold) clr = clrGold;
            else clr = clrTomato;
         }
      }
      
      VRDrawRect(chart_id, base_name + "_hm_" + IntegerToString(i), draw_x, y, sq_size, sq_size, clr);
   }
}

// Primitive: Draw Chart Background Tint
void VRDrawChartBackground(const long chart_id,
                           const string name,
                           const color bg_color,
                            const uchar alpha = 15) // alpha 0-255 (15 is ~6%)
{
   if(ObjectFind(chart_id, name) < 0)
   {
      ObjectCreate(chart_id, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(chart_id, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(chart_id, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(chart_id, name, OBJPROP_BACK, true); // Behind candles
      ObjectSetInteger(chart_id, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(chart_id, name, OBJPROP_HIDDEN, true);
   }
   
   // Cover entire chart dynamically
   int chart_w = (int)ChartGetInteger(chart_id, CHART_WIDTH_IN_PIXELS);
   int chart_h = (int)ChartGetInteger(chart_id, CHART_HEIGHT_IN_PIXELS);
   
   ObjectSetInteger(chart_id, name, OBJPROP_XDISTANCE, 0);
   ObjectSetInteger(chart_id, name, OBJPROP_YDISTANCE, 0);
   ObjectSetInteger(chart_id, name, OBJPROP_XSIZE, chart_w);
   ObjectSetInteger(chart_id, name, OBJPROP_YSIZE, chart_h);
   
   // Only apply color if not clrNONE
   if(bg_color == clrNONE)
   {
      ObjectSetInteger(chart_id, name, OBJPROP_BGCOLOR, clrNONE);
      ObjectSetInteger(chart_id, name, OBJPROP_COLOR, clrNONE);
      return;
   }
   
   // Apply ARGB for transparency if supported, or just use raw color
    uint argb = ColorToARGB(bg_color, alpha);
   ObjectSetInteger(chart_id, name, OBJPROP_BGCOLOR, argb);
   ObjectSetInteger(chart_id, name, OBJPROP_COLOR, clrNONE);
}

#endif
