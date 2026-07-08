#ifndef __VOLREGIME_FEATURE_MANIFEST_MQH__
#define __VOLREGIME_FEATURE_MANIFEST_MQH__

#define VR_VOL_FEATURE_COUNT   59
#define VR_TAPE_FEATURE_COUNT  38
#define VR_MICRO_FEATURE_COUNT 52
#define VR_VWAP_FEATURE_COUNT  33

string VR_VOL_FEATURE_NAMES[VR_VOL_FEATURE_COUNT] =
{
   "ret_lag1","ret_lag2","ret_lag3","ret_lag4","ret_lag8","ret_lag16","ret_lag32",
   "GK_5","PK_5","RS_5","GK_10","PK_10","RS_10","GK_20","PK_20","RS_20",
   "HAR_D","HAR_W","HAR_M","RM2006","HV_20","MA120_vol","vol_ratio","range_ratio",
   "tickvol_accel","vwap_dev","roc_5","roc_20","rsi_14","bb_pos","hour_sin","hour_cos",
   "dow_sin","dow_cos","month_sin","month_cos","news_flag","macro_vix","macro_vix_pct",
   "macro_dxy","macro_dxy_pct","macro_tnx","macro_tnx_pct","macro_hyg","macro_hyg_pct",
   "macro_tips","macro_tips_pct","gld_volume","gld_volume_pct","cot_mm_net_long","cot_mm_pct_oi",
   "hurst_90","coint_z_score","coint_fv","coint_std","ou_theta","ou_mu","ou_sigma","ou_halflife"
};

string VR_TAPE_FEATURE_NAMES[VR_TAPE_FEATURE_COUNT] =
{
   "sum_tickvol","avg_tickvol","max_tickvol","std_tickvol","active_count","bar_count","active_tickvol",
   "silent_count","active_ratio","silent_ratio","tape_cv","tape_accel","range_per_tick","tick_density",
   "active_tick_ratio","tv_zscore_20","tv_zscore_96","active_ratio_ma5","active_ratio_ma20","tape_accel_ma5",
   "tv_momentum","log_sum_tickvol","log_active_tickvol","log_max_tickvol","active_ratio_lag15","tv_zscore_20_lag15",
   "active_ratio_lag30","tv_zscore_20_lag30","active_ratio_lag60","tv_zscore_20_lag60","hour_sin","hour_cos",
   "dow_sin","dow_cos","is_london","is_ny","is_overlap","is_asian"
};

string VR_MICRO_FEATURE_NAMES[VR_MICRO_FEATURE_COUNT] =
{
   "bar_range","range_per_tick","tick_density","body_ratio","log_tick_vol","active_ratio_5","active_ratio_15",
   "active_ratio_30","active_ratio_60","tv_mean_5","tv_mean_15","tv_sum_15","tv_sum_60","tv_max_15","tv_cv_15",
   "tv_momentum","range_sum_15","range_mean_15","silent_ratio_15","silent_streak","tv_zscore_60","tv_zscore_240",
   "ar_zscore_60","ar_accel","tv_accel","log_tv_sum_15","log_tv_sum_60","active_ratio_15_lag1","active_ratio_15_lag3",
   "active_ratio_15_lag5","tv_mean_15_lag1","tv_mean_15_lag3","tv_mean_15_lag5","ar_zscore_60_lag1","ar_zscore_60_lag3",
   "ar_zscore_60_lag5","tv_momentum_lag1","tv_momentum_lag3","tv_momentum_lag5","hour_sin","hour_cos","dow_sin",
   "dow_cos","is_london","is_ny","is_overlap","is_asian","minutes_to_ny_close","is_london_open_burst","is_ny_open_burst",
   "is_london_close_drain","is_ny_close_drain"
};

string VR_VWAP_FEATURE_NAMES[VR_VWAP_FEATURE_COUNT] =
{
   "hour_sin","hour_cos","dow_sin","dow_cos","vwap","vwap_std","vwap_zscore","ret_lag1","ret_lag2","ret_lag4",
   "ret_lag8","ret_lag16","GK_4","PK_4","RS_4","GK_8","PK_8","RS_8","GK_16","PK_16","RS_16","HV_16",
   "HV_96","vol_ratio","roc_4","roc_16","roc_96","rsi_14","bb_pos","range_ratio","tickvol_accel","rtv","hurst_32"
};

#endif
