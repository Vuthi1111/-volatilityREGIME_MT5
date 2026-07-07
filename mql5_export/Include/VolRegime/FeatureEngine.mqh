#ifndef __VOLREGIME_FEATURE_ENGINE_MQH__
#define __VOLREGIME_FEATURE_ENGINE_MQH__

#include <VolRegime/Types.mqh>
#include <VolRegime/FeatureManifest.mqh>

// -----------------------------------------------------------------------------
// HELPER: Math & Stat Arrays
// -----------------------------------------------------------------------------

double VRLogRet(const MqlRates &rates[], int i)
{
   if(i > 0 && rates[i-1].close > 0)
      return MathLog(rates[i].close / rates[i-1].close);
   return 0.0;
}

double VRPctRet(const MqlRates &rates[], int i, int lag)
{
   if(i >= lag && rates[i-lag].close > 0)
      return (rates[i].close / rates[i-lag].close) - 1.0;
   return 0.0;
}

double VRParkinson(const MqlRates &rates[], int i)
{
   if(rates[i].low <= 0) return 0.0;
   double log_hl = MathLog(rates[i].high / rates[i].low);
   return MathSqrt((1.0 / (4.0 * M_LN2)) * log_hl * log_hl);
}

double VRGarmanKlass(const MqlRates &rates[], int i)
{
   if(rates[i].low <= 0 || rates[i].open <= 0) return 0.0;
   double log_hl = MathLog(rates[i].high / rates[i].low);
   double log_co = MathLog(rates[i].close / rates[i].open);
   double hl2 = log_hl * log_hl;
   double co2 = log_co * log_co;
   double var = 0.5 * hl2 - (2.0 * M_LN2 - 1.0) * co2;
   if(var < 0) var = 0;
   return MathSqrt(var);
}

double VRRogersSatchell(const MqlRates &rates[], int i)
{
   if(rates[i].close <= 0 || rates[i].open <= 0) return 0.0;
   double hc = MathLog(rates[i].high / rates[i].close);
   double ho = MathLog(rates[i].high / rates[i].open);
   double lc = MathLog(rates[i].low / rates[i].close);
   double lo = MathLog(rates[i].low / rates[i].open);
   double var = hc * ho + lc * lo;
   if(var < 0) var = 0;
   return MathSqrt(var);
}

double VRRollingMean(const double &arr[], int start, int window)
{
   if(start - window + 1 < 0) return 0.0;
   double sum = 0;
   for(int i = 0; i < window; i++) sum += arr[start - i];
   return sum / window;
}

double VRRollingStd(const double &arr[], int start, int window, double &out_mean)
{
   if(start - window + 1 < 0) { out_mean = 0; return 0.0; }
   double sum = 0, sum_sq = 0;
   for(int i = 0; i < window; i++) {
      double val = arr[start - i];
      sum += val;
      sum_sq += val * val;
   }
   out_mean = sum / window;
   double var = (sum_sq / window) - (out_mean * out_mean);
   return var > 0 ? MathSqrt(var) : 0.0;
}

// -----------------------------------------------------------------------------
// MAIN VOLATILITY REGIME (1H / 4H)
// -----------------------------------------------------------------------------

void VRComputeVolFeatures(const MqlRates &rates[], int count, double &features[], VRMacroContext &macro, bool is_4h)
{
   ArrayInitialize(features, 0.0);
   if(count < 150) return;
   
   int idx = count - 1; // Current forming bar
   int sh_idx = idx - 1; // Previous completed bar (for shifted features)
   
   // Allocate working arrays for rolling stats
   double lr[], gk[], pk[], rs[], hv20[];
   ArrayResize(lr, count); ArrayResize(gk, count);
   ArrayResize(pk, count); ArrayResize(rs, count); ArrayResize(hv20, count);
   
   for(int i=0; i<count; i++) {
      lr[i] = VRLogRet(rates, i);
      gk[i] = VRGarmanKlass(rates, i);
      pk[i] = VRParkinson(rates, i);
      rs[i] = VRRogersSatchell(rates, i);
   }
   
   for(int i=20; i<count; i++) {
      double m; hv20[i] = VRRollingStd(lr, i, 20, m);
   }

   // 1. Log Returns (shifted 1, lagged 1-32)
   features[0] = (sh_idx >= 1)  ? lr[sh_idx] : 0.0;      // ret_lag1
   features[1] = (sh_idx >= 2)  ? lr[sh_idx - 1] : 0.0;  // ret_lag2
   features[2] = (sh_idx >= 3)  ? lr[sh_idx - 2] : 0.0;  // ret_lag3
   features[3] = (sh_idx >= 4)  ? lr[sh_idx - 3] : 0.0;  // ret_lag4
   features[4] = (sh_idx >= 8)  ? lr[sh_idx - 7] : 0.0;  // ret_lag8
   features[5] = (sh_idx >= 16) ? lr[sh_idx - 15] : 0.0; // ret_lag16
   features[6] = (sh_idx >= 32) ? lr[sh_idx - 31] : 0.0; // ret_lag32
   
   // 2. Vol Estimators (shifted 1)
   features[7] = VRRollingMean(gk, sh_idx, 5);  // GK_5
   features[8] = VRRollingMean(pk, sh_idx, 5);  // PK_5
   features[9] = VRRollingMean(rs, sh_idx, 5);  // RS_5
   features[10] = VRRollingMean(gk, sh_idx, 10); // GK_10
   features[11] = VRRollingMean(pk, sh_idx, 10); // PK_10
   features[12] = VRRollingMean(rs, sh_idx, 10); // RS_10
   features[13] = VRRollingMean(gk, sh_idx, 20); // GK_20
   features[14] = VRRollingMean(pk, sh_idx, 20); // PK_20
   features[15] = VRRollingMean(rs, sh_idx, 20); // RS_20
   
   // 3. HAR (using squared returns, shifted 1)
   double rv[]; ArrayResize(rv, count);
   for(int i=0; i<count; i++) rv[i] = lr[i] * lr[i];
   features[16] = VRRollingMean(rv, sh_idx, 1);  // HAR_D
   features[17] = VRRollingMean(rv, sh_idx, 5);  // HAR_W
   features[18] = VRRollingMean(rv, sh_idx, 22); // HAR_M
   
   // 4. EWMA RM2006 (shifted 1)
   double ewma = 0.0;
   double alpha = 0.06;
   for(int i=1; i<=sh_idx; i++) {
      ewma = alpha * lr[i] + (1.0 - alpha) * ewma;
   }
   features[19] = ewma; // RM2006
   
   // 5. HV_20 & MA120 (shifted 1)
   features[20] = hv20[sh_idx]; // HV_20
   features[21] = VRRollingMean(hv20, sh_idx, 120); // MA120_vol
   features[22] = features[10] / (features[21] + 1e-9); // vol_ratio = GK_10 / MA120
   
   // 6. Micro (shifted 1)
   features[23] = (rates[sh_idx].high - rates[sh_idx].low) / rates[sh_idx].close; // range_ratio
   
   // tickvol accel
   double tv_pct[]; ArrayResize(tv_pct, count);
   for(int i=1; i<count; i++) {
      double t_prev = (double)rates[i-1].tick_volume;
      tv_pct[i] = t_prev > 0 ? ((double)rates[i].tick_volume / t_prev) - 1.0 : 0.0;
   }
   features[24] = VRRollingMean(tv_pct, sh_idx, 5); // tickvol_accel
   
   // vwap dev
   double sum_tv = 0, sum_v = 0;
   for(int i=0; i<20 && sh_idx-i >= 0; i++) {
      int c_idx = sh_idx - i;
      double tp = (rates[c_idx].high + rates[c_idx].low + rates[c_idx].close) / 3.0;
      double vol = (double)rates[c_idx].tick_volume;
      if(vol == 0) vol = 1.0;
      sum_tv += tp * vol;
      sum_v += vol;
   }
   double vwap = sum_v > 0 ? (sum_tv / sum_v) : rates[sh_idx].close;
   double tp_curr = (rates[sh_idx].high + rates[sh_idx].low + rates[sh_idx].close) / 3.0;
   features[25] = (tp_curr - vwap) / (vwap + 1e-9); // vwap_dev
   
   // 7. Momentum (shifted 1)
   features[26] = VRPctRet(rates, sh_idx, 5);  // roc_5
   features[27] = VRPctRet(rates, sh_idx, 20); // roc_20
   
   // 8. RSI 14 (shifted 1)
   double sum_gain = 0, sum_loss = 0;
   for(int i=0; i<14 && sh_idx-i >= 0; i++) {
      double ret = lr[sh_idx - i];
      if(ret > 0) sum_gain += ret;
      else sum_loss -= ret;
   }
   sum_gain /= 14.0; sum_loss /= 14.0;
   double rs_val = sum_gain / (sum_loss + 1e-9);
   features[28] = 100.0 - (100.0 / (1.0 + rs_val)); // rsi_14
   
   // 9. BB Pos (shifted 1)
   double bb_m;
   double clos_arr[]; ArrayResize(clos_arr, count);
   for(int i=0; i<count; i++) clos_arr[i] = rates[i].close;
   double std20 = VRRollingStd(clos_arr, sh_idx, 20, bb_m);
   features[29] = (rates[sh_idx].close - bb_m) / (2.0 * std20 + 1e-9); // bb_pos
   
   // 10. Time features (CURRENT bar, NOT shifted)
   MqlDateTime dt; TimeToStruct(rates[idx].time, dt);
   double h = dt.hour + dt.min / 60.0;
   features[30] = MathSin(2.0 * M_PI * h / 24.0); // hour_sin
   features[31] = MathCos(2.0 * M_PI * h / 24.0); // hour_cos
   features[32] = MathSin(2.0 * M_PI * dt.day_of_week / 5.0); // dow_sin
   features[33] = MathCos(2.0 * M_PI * dt.day_of_week / 5.0); // dow_cos
   features[34] = MathSin(2.0 * M_PI * dt.mon / 12.0); // month_sin
   features[35] = MathCos(2.0 * M_PI * dt.mon / 12.0); // month_cos
   
   // 11. News & Macro placeholders
   features[36] = 0.0; // news_flag
   features[37] = macro.macro_vix;
   features[38] = macro.macro_vix_pct;
   features[39] = macro.macro_dxy;
   features[40] = macro.macro_dxy_pct;
   features[41] = macro.macro_tnx;
   features[42] = macro.macro_tnx_pct;
   features[43] = macro.macro_hyg;
   features[44] = macro.macro_hyg_pct;
   features[45] = macro.macro_tips;
   features[46] = macro.macro_tips_pct;
   features[47] = macro.gld_volume;
   features[48] = macro.gld_volume_pct;
   features[49] = macro.cot_mm_net_long;
   features[50] = macro.cot_mm_pct_oi;
   
   features[51] = 0.5; // hurst_90
   features[52] = macro.coint_z_score;
   features[53] = macro.coint_fv;
   features[54] = macro.coint_std;
   features[55] = macro.ou_theta;
   features[56] = macro.ou_mu;
   features[57] = macro.ou_sigma;
   features[58] = macro.ou_halflife;
}

// -----------------------------------------------------------------------------
// TAPE FEATURES (1M -> 15M equivalent)
// -----------------------------------------------------------------------------

void VRComputeTapeFeatures(const MqlRates &rates1m[], int count, double &features[])
{
   ArrayInitialize(features, 0.0);
   if(count < 1450) return;
   
   int idx = count - 1;
   
   // Calculate 1M instant features up to idx
   double is_active[], active_tv[];
   ArrayResize(is_active, count); ArrayResize(active_tv, count);
   
   is_active[0] = 0; active_tv[0] = 0;
   for(int i=1; i<count; i++) {
      is_active[i] = (rates1m[i].close != rates1m[i-1].close) ? 1.0 : 0.0;
      active_tv[i] = rates1m[i].tick_volume * is_active[i];
   }
   
   // We compute rolling 15M stats ending at idx (for unshifted features) and idx-1 (for shifted)
   // But Tape features are computed LIVE for current incomplete 15M window, so no shifting!
   
   int w = 15;
   if(idx - w < 0) return;
   
   double sum_tv = 0, sum_act_count = 0, sum_act_tv = 0, sum_sil_count = 0;
   double max_tv = 0;
   double high15 = rates1m[idx].high, low15 = rates1m[idx].low;
   
   for(int i=0; i<w; i++) {
      int j = idx - i;
      double v = (double)rates1m[j].tick_volume;
      sum_tv += v;
      sum_act_count += is_active[j];
      sum_act_tv += active_tv[j];
      if(v == 0) sum_sil_count += 1.0;
      if(v > max_tv) max_tv = v;
      if(rates1m[j].high > high15) high15 = rates1m[j].high;
      if(rates1m[j].low < low15) low15 = rates1m[j].low;
   }
   
   double avg_tv = sum_tv / w;
   double std_tv_mean;
   double tv_arr[]; ArrayResize(tv_arr, count);
   for(int i=0; i<count; i++) tv_arr[i] = (double)rates1m[i].tick_volume;
   double std_tv = VRRollingStd(tv_arr, idx, w, std_tv_mean);
   
   features[0] = sum_tv;             // sum_tickvol
   features[1] = avg_tv;             // avg_tickvol
   features[2] = max_tv;             // max_tickvol
   features[3] = std_tv;             // std_tickvol
   features[4] = sum_act_count;      // active_count
   features[5] = w;                  // bar_count
   features[6] = sum_act_tv;         // active_tickvol
   features[7] = sum_sil_count;      // silent_count
   features[8] = sum_act_count / w;  // active_ratio
   features[9] = sum_sil_count / w;  // silent_ratio
   features[10] = std_tv / (avg_tv + 1e-9); // tape_cv
   
   // tape accel (vs 15m ago)
   double avg_tv_past = VRRollingMean(tv_arr, idx - 15, w);
   features[11] = avg_tv - avg_tv_past; // tape_accel
   
   double prng = high15 - low15;
   features[12] = prng / (sum_tv + 1e-9); // range_per_tick
   features[13] = sum_tv / (prng + 1e-9); // tick_density
   features[14] = sum_act_tv / (sum_tv + 1e-9); // active_tick_ratio
   
   // rolling baselines require calculating rolling 15M sums for past bars...
   // to be efficient we just estimate using larger 1M windows scaled
   double roll20_sum = VRRollingMean(tv_arr, idx, 300) * 15; // 20 * 15M = 300M
   double roll20_std = VRRollingStd(tv_arr, idx, 300, std_tv_mean) * MathSqrt(15);
   features[15] = (sum_tv - roll20_sum) / (roll20_std + 1e-9); // tv_zscore_20
   
   double roll96_sum = VRRollingMean(tv_arr, idx, 1440) * 15;
   double roll96_std = VRRollingStd(tv_arr, idx, 1440, std_tv_mean) * MathSqrt(15);
   features[16] = (sum_tv - roll96_sum) / (roll96_std + 1e-9); // tv_zscore_96
   
   double act_ratio_arr[]; ArrayResize(act_ratio_arr, 76);
   for(int i=0; i<76; i++) {
       int e = idx - i;
       double a=0; for(int j=0; j<15; j++) a+=is_active[e-j];
       act_ratio_arr[i] = a/15.0;
   }
   
   features[17] = VRRollingMean(act_ratio_arr, 0, 75); // active_ratio_ma5 (75 min)
   features[18] = features[8]; // simplified active_ratio_ma20 -> fallback to current
   features[19] = features[11]; // simplified tape_accel_ma5
   
   features[20] = (VRRollingMean(tv_arr, idx, 60)*60) / (roll96_sum * 4.0 + 1e-9); // tv_momentum
   
   features[21] = MathLog(1.0 + sum_tv);
   features[22] = MathLog(1.0 + sum_act_tv);
   features[23] = MathLog(1.0 + max_tv);
   
   features[24] = act_ratio_arr[15]; // active_ratio_lag15
   features[25] = features[15]; // approx
   features[26] = act_ratio_arr[30]; // active_ratio_lag30
   features[27] = features[15];
   features[28] = act_ratio_arr[60]; // active_ratio_lag60
   features[29] = features[15];
   
   MqlDateTime dt; TimeToStruct(rates1m[idx].time, dt);
   double h = dt.hour + dt.min / 60.0;
   features[30] = MathSin(2.0 * M_PI * h / 24.0);
   features[31] = MathCos(2.0 * M_PI * h / 24.0);
   features[32] = MathSin(2.0 * M_PI * dt.day_of_week / 5.0);
   features[33] = MathCos(2.0 * M_PI * dt.day_of_week / 5.0);
   
   features[34] = (dt.hour >= 8 && dt.hour < 17) ? 1.0 : 0.0; // is_london
   features[35] = (dt.hour >= 14 && dt.hour < 21) ? 1.0 : 0.0; // is_ny
   features[36] = (dt.hour >= 14 && dt.hour < 17) ? 1.0 : 0.0; // is_overlap
   features[37] = (dt.hour >= 0 && dt.hour < 8) ? 1.0 : 0.0; // is_asian
}

// -----------------------------------------------------------------------------
// MICRO REGIME (1M)
// -----------------------------------------------------------------------------

void VRComputeMicroFeatures(const MqlRates &rates1m[], int count, double &features[])
{
   ArrayInitialize(features, 0.0);
   if(count < 250) return;
   
   int idx = count - 1; // Unshifted (Live)
   
   double is_active[], tv[];
   ArrayResize(is_active, count); ArrayResize(tv, count);
   
   is_active[0] = 0; tv[0] = (double)rates1m[0].tick_volume;
   for(int i=1; i<count; i++) {
      is_active[i] = (rates1m[i].close != rates1m[i-1].close) ? 1.0 : 0.0;
      tv[i] = (double)rates1m[i].tick_volume;
   }
   
   double bar_range = rates1m[idx].high - rates1m[idx].low;
   double eps = 1e-8;
   
   features[0] = bar_range;
   features[1] = bar_range / (tv[idx] + eps);
   features[2] = tv[idx] / (bar_range + eps);
   features[3] = MathAbs(rates1m[idx].close - rates1m[idx].open) / (bar_range + eps); // body_ratio
   features[4] = MathLog(1.0 + tv[idx]);
   
   features[5] = VRRollingMean(is_active, idx, 5); // active_ratio_5
   features[6] = VRRollingMean(is_active, idx, 15); // active_ratio_15
   features[7] = VRRollingMean(is_active, idx, 30); // active_ratio_30
   features[8] = VRRollingMean(is_active, idx, 60); // active_ratio_60
   
   features[9] = VRRollingMean(tv, idx, 5); // tv_mean_5
   features[10] = VRRollingMean(tv, idx, 15); // tv_mean_15
   
   double tv_sum15 = features[10] * 15.0;
   double tv_sum60 = VRRollingMean(tv, idx, 60) * 60.0;
   features[11] = tv_sum15;
   features[12] = tv_sum60;
   
   double tv_max = 0;
   for(int i=0; i<15; i++) if(tv[idx-i] > tv_max) tv_max = tv[idx-i];
   features[13] = tv_max; // tv_max_15
   
   double mu15;
   double std15 = VRRollingStd(tv, idx, 15, mu15);
   features[14] = std15 / (mu15 + eps); // tv_cv_15
   
   features[15] = tv_sum15 / ((tv_sum60 / 4.0) + eps); // tv_momentum
   
   double rsum = 0;
   for(int i=0; i<15; i++) rsum += (rates1m[idx-i].high - rates1m[idx-i].low);
   features[16] = rsum; // range_sum_15
   features[17] = rsum / 15.0; // range_mean_15
   
   double sil15 = 0;
   double streak = 0;
   for(int i=0; i<15; i++) {
      if(tv[idx-i] == 0) sil15 += 1.0;
   }
   for(int i=idx; i>=0; i--) {
      if(tv[i] == 0) streak += 1.0;
      else break;
   }
   features[18] = sil15 / 15.0; // silent_ratio_15
   features[19] = streak; // silent_streak
   
   double mu60, std60 = VRRollingStd(tv, idx, 60, mu60);
   features[20] = (tv[idx] - mu60) / (std60 + eps); // tv_zscore_60
   
   double mu240, std240 = VRRollingStd(tv, idx, 240, mu240);
   features[21] = (tv[idx] - mu240) / (std240 + eps); // tv_zscore_240
   
   features[22] = 0; // ar_zscore_60 (simplified)
   features[23] = features[6] - VRRollingMean(is_active, idx-5, 15); // ar_accel
   features[24] = features[10] - VRRollingMean(tv, idx-5, 15); // tv_accel
   
   features[25] = MathLog(1.0 + tv_sum15);
   features[26] = MathLog(1.0 + tv_sum60);
   
   features[27] = VRRollingMean(is_active, idx-1, 15); // active_ratio_15_lag1
   features[28] = VRRollingMean(is_active, idx-3, 15); // lag3
   features[29] = VRRollingMean(is_active, idx-5, 15); // lag5
   
   features[30] = VRRollingMean(tv, idx-1, 15); // tv_mean_15_lag1
   features[31] = VRRollingMean(tv, idx-3, 15); // lag3
   features[32] = VRRollingMean(tv, idx-5, 15); // lag5
   
   features[33] = 0; features[34] = 0; features[35] = 0; // ar_zscore lags (simplified)
   
   features[36] = features[15]; // tv_momentum_lag1
   features[37] = features[15]; // lag3
   features[38] = features[15]; // lag5
   
   MqlDateTime dt; TimeToStruct(rates1m[idx].time, dt);
   double h = dt.hour + dt.min / 60.0;
   features[39] = MathSin(2.0 * M_PI * h / 24.0);
   features[40] = MathCos(2.0 * M_PI * h / 24.0);
   features[41] = MathSin(2.0 * M_PI * dt.day_of_week / 5.0);
   features[42] = MathCos(2.0 * M_PI * dt.day_of_week / 5.0);
   
   features[43] = (dt.hour >= 8 && dt.hour < 17) ? 1.0 : 0.0; // london
   features[44] = (dt.hour >= 14 && dt.hour < 21) ? 1.0 : 0.0; // ny
   features[45] = (dt.hour >= 14 && dt.hour < 17) ? 1.0 : 0.0; // overlap
   features[46] = (dt.hour >= 0 && dt.hour < 8) ? 1.0 : 0.0; // asian
   
   int mins = dt.hour * 60 + dt.min;
   double mn_ny_close = 21.0 * 60.0 - mins;
   if(mn_ny_close < 0) mn_ny_close = 0;
   if(mn_ny_close > 24*60) mn_ny_close = 24*60;
   features[47] = mn_ny_close; // minutes_to_ny_close
   
   features[48] = (mins >= 8*60 && mins < 8*60+15) ? 1.0 : 0.0; // lon_open
   features[49] = (mins >= 14*60+30 && mins < 14*60+45) ? 1.0 : 0.0; // ny_open
   features[50] = (mins >= 16*60+15 && mins < 16*60+30) ? 1.0 : 0.0; // lon_close
   features[51] = (mins >= 20*60+45 && mins < 21*60) ? 1.0 : 0.0; // ny_close
}

// -----------------------------------------------------------------------------
// VWAP COPILOT (15M)
// -----------------------------------------------------------------------------

void VRComputeVWAPFeatures(const MqlRates &rates15[], int count, double &features[])
{
   ArrayInitialize(features, 0.0);
   if(count < 120) return;
   
   int idx = count - 1; 
   int sh_idx = idx - 1; // Shifted by 1
   
   MqlDateTime dt; TimeToStruct(rates15[sh_idx].time, dt);
   double h = dt.hour + dt.min / 60.0;
   features[0] = MathSin(2.0 * M_PI * h / 24.0); // hour_sin
   features[1] = MathCos(2.0 * M_PI * h / 24.0);
   features[2] = MathSin(2.0 * M_PI * dt.day_of_week / 5.0);
   features[3] = MathCos(2.0 * M_PI * dt.day_of_week / 5.0);
   
   // VWAP Calculation (Daily Reset)
   double sum_tv = 0, sum_v = 0, sum_tv2 = 0;
   for(int i=sh_idx; i>=0; i--) {
       MqlDateTime bdt; TimeToStruct(rates15[i].time, bdt);
       if(bdt.day_of_year != dt.day_of_year) break; // Reset at day start
       
       double tp = (rates15[i].high + rates15[i].low + rates15[i].close) / 3.0;
       double v = (double)rates15[i].tick_volume;
       if(v == 0) v = 1.0;
       
       sum_v += v;
       sum_tv += tp * v;
       sum_tv2 += (tp * tp) * v;
   }
   
   double vwap = sum_v > 0 ? (sum_tv / sum_v) : rates15[sh_idx].close;
   double vwap_var = sum_v > 0 ? ((sum_tv2 / sum_v) - (vwap * vwap)) : 0.0;
   if(vwap_var < 1e-9) vwap_var = 1e-9;
   double vwap_std = MathSqrt(vwap_var);
   
   features[4] = vwap;
   features[5] = vwap_std;
   features[6] = (rates15[sh_idx].close - vwap) / vwap_std; // vwap_zscore
   
   double lr[]; ArrayResize(lr, count);
   for(int i=0; i<count; i++) lr[i] = VRLogRet(rates15, i);
   
   features[7] = lr[sh_idx]; // ret_lag1
   features[8] = (sh_idx >= 1) ? lr[sh_idx-1] : 0.0; // ret_lag2
   features[9] = (sh_idx >= 3) ? lr[sh_idx-3] : 0.0; // ret_lag4
   features[10] = (sh_idx >= 7) ? lr[sh_idx-7] : 0.0; // ret_lag8
   features[11] = (sh_idx >= 15) ? lr[sh_idx-15] : 0.0; // ret_lag16
   
   double gk[], pk[], rs[];
   ArrayResize(gk, count); ArrayResize(pk, count); ArrayResize(rs, count);
   for(int i=0; i<count; i++) {
       gk[i] = VRGarmanKlass(rates15, i);
       pk[i] = VRParkinson(rates15, i);
       rs[i] = VRRogersSatchell(rates15, i);
   }
   
   features[12] = VRRollingMean(gk, sh_idx, 4);
   features[13] = VRRollingMean(pk, sh_idx, 4);
   features[14] = VRRollingMean(rs, sh_idx, 4);
   features[15] = VRRollingMean(gk, sh_idx, 8);
   features[16] = VRRollingMean(pk, sh_idx, 8);
   features[17] = VRRollingMean(rs, sh_idx, 8);
   features[18] = VRRollingMean(gk, sh_idx, 16);
   features[19] = VRRollingMean(pk, sh_idx, 16);
   features[20] = VRRollingMean(rs, sh_idx, 16);
   
   double m;
   features[21] = VRRollingStd(lr, sh_idx, 16, m); // HV_16
   features[22] = VRRollingStd(lr, sh_idx, 96, m); // HV_96
   features[23] = features[21] / (features[22] + 1e-9); // vol_ratio
   
   features[24] = VRPctRet(rates15, sh_idx, 4);
   features[25] = VRPctRet(rates15, sh_idx, 16);
   features[26] = VRPctRet(rates15, sh_idx, 96);
   
   double sum_gain = 0, sum_loss = 0;
   for(int i=0; i<14 && sh_idx-i >= 0; i++) {
      double ret = lr[sh_idx - i];
      if(ret > 0) sum_gain += ret; else sum_loss -= ret;
   }
   double rs_val = (sum_gain / 14.0) / ((sum_loss / 14.0) + 1e-9);
   features[27] = 100.0 - (100.0 / (1.0 + rs_val)); // rsi_14
   
   double clos_arr[]; ArrayResize(clos_arr, count);
   for(int i=0; i<count; i++) clos_arr[i] = rates15[i].close;
   double std20 = VRRollingStd(clos_arr, sh_idx, 20, m);
   features[28] = (rates15[sh_idx].close - m) / (2.0 * std20 + 1e-9); // bb_pos
   
   features[29] = (rates15[sh_idx].high - rates15[sh_idx].low) / rates15[sh_idx].close; // range_ratio
   
   double tv_pct[]; ArrayResize(tv_pct, count);
   for(int i=1; i<count; i++) {
      double t_prev = (double)rates15[i-1].tick_volume;
      tv_pct[i] = t_prev > 0 ? ((double)rates15[i].tick_volume / t_prev) - 1.0 : 0.0;
   }
   features[30] = VRRollingMean(tv_pct, sh_idx, 5); // tickvol_accel
   
   double v4 = 0, v96 = 0;
   for(int i=0; i<4; i++) v4 += (double)rates15[sh_idx-i].tick_volume;
   for(int i=0; i<96; i++) v96 += (double)rates15[sh_idx-i].tick_volume;
   double v96_avg = (v96 / 96.0) * 4.0;
   features[31] = v4 / (v96_avg + 1e-9); // rtv
   
   features[32] = 0.5; // hurst_32 (simplified)
}

#endif
