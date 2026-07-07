import os
import joblib
import json
import datetime

def generate_mql5_tree_code(model, model_name, features, scaler=None):
    """
    Converts a LightGBM model into a standalone MQL5 function.
    No ONNX required. Pure native execution.
    """
    dump = model.booster_.dump_model()
    trees = dump['tree_info']
    
    # We will flatten the trees into arrays for O(1) memory access in MQL5
    # For each node we need:
    # 1. is_leaf (bool)
    # 2. split_feature_idx (int)
    # 3. threshold (double)
    # 4. left_child_idx (int)
    # 5. right_child_idx (int)
    # 6. leaf_value (double)
    
    nodes_is_leaf = []
    nodes_feature = []
    nodes_threshold = []
    nodes_left = []
    nodes_right = []
    nodes_value = []
    
    tree_start_indices = []
    current_node_idx = 0
    
    def traverse(node):
        nonlocal current_node_idx
        my_idx = current_node_idx
        current_node_idx += 1
        
        nodes_is_leaf.append(False)
        nodes_feature.append(0)
        nodes_threshold.append(0.0)
        nodes_left.append(0)
        nodes_right.append(0)
        nodes_value.append(0.0)
        
        if 'leaf_value' in node:
            nodes_is_leaf[my_idx] = True
            nodes_value[my_idx] = node['leaf_value']
        else:
            nodes_is_leaf[my_idx] = False
            nodes_feature[my_idx] = node['split_feature']
            nodes_threshold[my_idx] = node['threshold']
            
            left_idx = traverse(node['left_child'])
            right_idx = traverse(node['right_child'])
            
            nodes_left[my_idx] = left_idx
            nodes_right[my_idx] = right_idx
            
        return my_idx

    for tree in trees:
        tree_start_indices.append(current_node_idx)
        traverse(tree['tree_structure'])
        
    # Build MQL5 string
    mqh = f"// Auto-generated LightGBM Model: {model_name}\n"
    mqh += f"// Generated on: {datetime.datetime.now()}\n"
    mqh += f"// Features: {len(features)}\n"
    mqh += f"// Trees: {len(trees)}\n\n"
    
    mqh += f"int {model_name}_NumFeatures = {len(features)};\n\n"
    
    # Export scaler if exists
    if scaler is not None:
        mqh += f"double {model_name}_ScalerMean[] = {{" + ",".join(map(str, scaler.mean_)) + "};\n"
        mqh += f"double {model_name}_ScalerScale[] = {{" + ",".join(map(str, scaler.scale_)) + "};\n\n"
    
    # Export Tree Arrays
    mqh += f"int {model_name}_TreeStarts[] = {{" + ",".join(map(str, tree_start_indices)) + "};\n"
    
    # Convert booleans to 1/0
    is_leaf_str = ",".join(["1" if x else "0" for x in nodes_is_leaf])
    mqh += f"int {model_name}_IsLeaf[] = {{{is_leaf_str}}};\n"
    
    mqh += f"int {model_name}_Feature[] = {{" + ",".join(map(str, nodes_feature)) + "};\n"
    mqh += f"double {model_name}_Threshold[] = {{" + ",".join(map(str, nodes_threshold)) + "};\n"
    mqh += f"int {model_name}_Left[] = {{" + ",".join(map(str, nodes_left)) + "};\n"
    mqh += f"int {model_name}_Right[] = {{" + ",".join(map(str, nodes_right)) + "};\n"
    mqh += f"double {model_name}_Value[] = {{" + ",".join(map(str, nodes_value)) + "};\n\n"
    
    # Export Evaluator Function
    has_scaler = "true" if scaler is not None else "false"
    
    mqh += f"double Predict_{model_name}(double &features[]) {{\n"
    mqh += f"   double sum = 0.0;\n"
    if scaler is not None:
        mqh += f"   double scaled_features[{len(features)}];\n"
        mqh += f"   for(int i=0; i<{len(features)}; i++) {{\n"
        mqh += f"       scaled_features[i] = (features[i] - {model_name}_ScalerMean[i]) / {model_name}_ScalerScale[i];\n"
        mqh += f"   }}\n"
        
    mqh += f"   for(int t=0; t<{len(trees)}; t++) {{\n"
    mqh += f"       int node = {model_name}_TreeStarts[t];\n"
    mqh += f"       while({model_name}_IsLeaf[node] == 0) {{\n"
    mqh += f"           int f_idx = {model_name}_Feature[node];\n"
    mqh += f"           double val = " + (f"scaled_features[f_idx]" if scaler else "features[f_idx]") + ";\n"
    mqh += f"           if (val <= {model_name}_Threshold[node]) {{\n"
    mqh += f"               node = {model_name}_Left[node];\n"
    mqh += f"           }} else {{\n"
    mqh += f"               node = {model_name}_Right[node];\n"
    mqh += f"           }}\n"
    mqh += f"       }}\n"
    mqh += f"       sum += {model_name}_Value[node];\n"
    mqh += f"   }}\n"
    
    # Sigmoid for probability (assuming binary classification)
    mqh += f"   return 1.0 / (1.0 + MathExp(-sum));\n"
    mqh += f"}}\n"
    
    return mqh

def process_artifacts():
    models_dir = "../../models"
    output_mql5_dir = "../Include/VolRegime/Models"
    output_manifest_dir = "../output/manifests"
    
    os.makedirs(output_mql5_dir, exist_ok=True)
    os.makedirs(output_manifest_dir, exist_ok=True)
    
    manifest = {}
    
    artifacts = {
        'nas100_vol_regime': 'vol',
        'gold_vol_regime': 'vol',
        'nas100_speed_tape_v2': 'tape',
        'gold_speed_tape_v2': 'tape',
        'nas100_micro_regime': 'micro',
        'gold_micro_regime': 'micro',
        'nas100_vwap_copilot': 'vwap',
        'gold_vwap_copilot': 'vwap'
    }
    
    for filename, type_ in artifacts.items():
        filepath = os.path.join(models_dir, f"{filename}.joblib")
        if not os.path.exists(filepath):
            print(f"Warning: Artifact {filepath} not found.")
            continue
            
        print(f"Processing {filename}...")
        obj = joblib.load(filepath)
        
        if type_ == 'vol':
            for tf in ['1h', '4h']:
                model, scaler, features = obj[tf]
                export_name = f"{filename}_{tf}"
                mqh_code = generate_mql5_tree_code(model, export_name, features, scaler)
                
                with open(os.path.join(output_mql5_dir, f"{export_name}.mqh"), "w") as f:
                    f.write(mqh_code)
                    
                manifest[export_name] = {"num_features": len(features), "features": features}
                print(f"  Exported {export_name}.mqh")
        else:
            model = obj['model']
            features = obj['features']
            export_name = filename
            mqh_code = generate_mql5_tree_code(model, export_name, features, None)
            
            with open(os.path.join(output_mql5_dir, f"{export_name}.mqh"), "w") as f:
                f.write(mqh_code)
                
            manifest[export_name] = {"num_features": len(features), "features": features}
            print(f"  Exported {export_name}.mqh")
            
    with open(os.path.join(output_manifest_dir, "feature_manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2)
    print("Done!")

if __name__ == "__main__":
    process_artifacts()