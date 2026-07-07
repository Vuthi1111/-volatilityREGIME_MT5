#ifndef __VOLREGIME_MODEL_RUNTIME_MQH__
#define __VOLREGIME_MODEL_RUNTIME_MQH__

#include <VolRegime/Types.mqh>
#include <VolRegime/FeatureManifest.mqh>

#include <VolRegime/Models/nas100_vol_regime_1h.mqh>
#include <VolRegime/Models/nas100_vol_regime_4h.mqh>
#include <VolRegime/Models/nas100_speed_tape_v2.mqh>
#include <VolRegime/Models/nas100_micro_regime.mqh>
#include <VolRegime/Models/nas100_vwap_copilot.mqh>
#include <VolRegime/Models/gold_vol_regime_1h.mqh>
#include <VolRegime/Models/gold_vol_regime_4h.mqh>
#include <VolRegime/Models/gold_speed_tape_v2.mqh>
#include <VolRegime/Models/gold_micro_regime.mqh>
#include <VolRegime/Models/gold_vwap_copilot.mqh>

bool VRIsGoldSymbol(const string symbol)
{
   string s = symbol;
   StringToUpper(s);
   return (StringFind(s, "XAU") >= 0 || StringFind(s, "GOLD") >= 0);
}

bool VRIsNasdaqSymbol(const string symbol)
{
   string s = symbol;
   StringToUpper(s);
   return (StringFind(s, "NAS") >= 0 || StringFind(s, "USTEC") >= 0 || StringFind(s, "NDX") >= 0 || StringFind(s, "US100") >= 0);
}

double VRPredictVol1H(const string symbol, double &features[])
{
   if(VRIsGoldSymbol(symbol))
      return Predict_gold_vol_regime_1h(features);
   return Predict_nas100_vol_regime_1h(features);
}

double VRPredictVol4H(const string symbol, double &features[])
{
   if(VRIsGoldSymbol(symbol))
      return Predict_gold_vol_regime_4h(features);
   return Predict_nas100_vol_regime_4h(features);
}

double VRPredictTape(const string symbol, double &features[])
{
   if(VRIsGoldSymbol(symbol))
      return Predict_gold_speed_tape_v2(features);
   return Predict_nas100_speed_tape_v2(features);
}

double VRPredictMicro(const string symbol, double &features[])
{
   if(VRIsGoldSymbol(symbol))
      return Predict_gold_micro_regime(features);
   return Predict_nas100_micro_regime(features);
}

double VRPredictVWAP(const string symbol, double &features[])
{
   if(VRIsGoldSymbol(symbol))
      return Predict_gold_vwap_copilot(features);
   return Predict_nas100_vwap_copilot(features);
}

void VRRunInference(const string symbol, VRFeatureSnapshot &feature_snapshot, VRInferenceSnapshot &out)
{
   out.symbol = symbol;
   out.source_time = feature_snapshot.source_time;
   out.vol_1h_prob = VRPredictVol1H(symbol, feature_snapshot.vol_1h);
   out.vol_4h_prob = VRPredictVol4H(symbol, feature_snapshot.vol_4h);
   out.tape_prob   = VRPredictTape(symbol, feature_snapshot.tape);
   out.micro_prob  = VRPredictMicro(symbol, feature_snapshot.micro);
   out.vwap_prob   = VRPredictVWAP(symbol, feature_snapshot.vwap);
   out.features    = feature_snapshot;
}

#endif
