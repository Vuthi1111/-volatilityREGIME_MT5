#ifndef __VOLREGIME_TYPES_MQH__
#define __VOLREGIME_TYPES_MQH__

struct VRMacroContext
{
   double macro_vix;
   double macro_vix_pct;
   double macro_dxy;
   double macro_dxy_pct;
   double macro_tnx;
   double macro_tnx_pct;
   double macro_hyg;
   double macro_hyg_pct;
   double macro_tips;
   double macro_tips_pct;
   double gld_volume;
   double gld_volume_pct;
   double cot_mm_net_long;
   double cot_mm_pct_oi;
   double coint_z_score;
   double coint_fv;
   double coint_std;
   double ou_theta;
   double ou_mu;
   double ou_sigma;
   double ou_halflife;
};

struct VRSessionConfig
{
   int london_open_hour;
   int london_close_hour;
   int ny_open_hour;
   int ny_open_minute;
   int ny_close_hour;
   int ny_close_minute;
};

struct VRNewsState
{
   bool     is_blackout;
   datetime event_time;
   string   event_title;
   string   impact;
};

struct VRFeatureSnapshot
{
   datetime source_time;
   double   vol_1h[59];
   double   vol_4h[59];
   double   tape[38];
   double   micro[52];
   double   vwap[33];

   double latest_vwap_zscore;
   double latest_hurst_32;
   double latest_hurst_90;
   double latest_active_ratio;
   double latest_silent_ratio;
   double latest_tape_momentum;
   double latest_rsi_14;
   double latest_bb_pos;
   double latest_range_ratio;
   double latest_tickvol_accel;
   double latest_rtv;
};

struct VRInferenceSnapshot
{
   string   symbol;
   datetime source_time;
   double   vol_1h_prob;
   double   vol_4h_prob;
   double   tape_prob;
   double   micro_prob;
   double   vwap_prob;
   VRNewsState news;
   VRFeatureSnapshot features;
};

struct VRDashboardLayout
{
   int x;
   int y;
   int panel_width;
   int panel_height;
   int gap;
   
   color bg_main;
   color bg_panel;
   color border;
   color text_main;
   color text_dim;
};

enum ENUM_VR_CORNER
{
   VR_CORNER_TOP_LEFT = 0,
   VR_CORNER_TOP_RIGHT = 1,
   VR_CORNER_BOTTOM_LEFT = 2,
   VR_CORNER_BOTTOM_RIGHT = 3
};

enum ENUM_VR_THEME
{
   VR_THEME_DARK = 0,
   VR_THEME_LIGHT = 1
};

enum ENUM_VR_SENSITIVITY
{
   VR_SENSITIVITY_AGGRESSIVE = 0,   // Aggressive (50%)
   VR_SENSITIVITY_STANDARD = 1,     // Standard (55%)
   VR_SENSITIVITY_CONSERVATIVE = 2  // Conservative (65%)
};

void VRZeroMacroContext(VRMacroContext &ctx)
{
   ctx.macro_vix = 0.0;
   ctx.macro_vix_pct = 0.0;
   ctx.macro_dxy = 0.0;
   ctx.macro_dxy_pct = 0.0;
   ctx.macro_tnx = 0.0;
   ctx.macro_tnx_pct = 0.0;
   ctx.macro_hyg = 0.0;
   ctx.macro_hyg_pct = 0.0;
   ctx.macro_tips = 0.0;
   ctx.macro_tips_pct = 0.0;
   ctx.gld_volume = 0.0;
   ctx.gld_volume_pct = 0.0;
   ctx.cot_mm_net_long = 0.0;
   ctx.cot_mm_pct_oi = 0.0;
   ctx.coint_z_score = 0.0;
   ctx.coint_fv = 0.0;
   ctx.coint_std = 0.0;
   ctx.ou_theta = 0.0;
   ctx.ou_mu = 0.0;
   ctx.ou_sigma = 0.0;
   ctx.ou_halflife = 0.0;
}

void VRDefaultSessionConfig(VRSessionConfig &cfg)
{
   cfg.london_open_hour = 8;
   cfg.london_close_hour = 17;
   cfg.ny_open_hour = 13;
   cfg.ny_open_minute = 30;
   cfg.ny_close_hour = 20;
   cfg.ny_close_minute = 0;
}

void VRResetNewsState(VRNewsState &state)
{
   state.is_blackout = false;
   state.event_time = 0;
   state.event_title = "";
   state.impact = "";
}

#endif
