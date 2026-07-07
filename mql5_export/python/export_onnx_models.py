import os
import json
import joblib
import numpy as np
from hummingbird.ml import convert

def export_model_to_onnx(model, feature_count, output_path, scaler=None):
    """
    Exports a LightGBM model (and optional scaler) to ONNX format.
    Uses hummingbird-ml which creates clean ONNX graphs for tree models.
    """
    try:
        from sklearn.pipeline import Pipeline
    except ImportError:
        print("Please install scikit-learn: pip install scikit-learn")
        return False
        
    try:
        # Create dummy input data with correct shape
        dummy_input = np.random.rand(1, feature_count).astype(np.float32)
        
        if scaler:
            # Wrap scaler and model in pipeline so ONNX handles scaling internally
            pipeline = Pipeline([
                ('scaler', scaler),
                ('lgbm', model)
            ])
            # Hummingbird needs extra initial types info for pipelines sometimes, 
            # but usually convert(pipeline) works directly
            onnx_model = convert(pipeline, 'onnx', dummy_input)
        else:
            onnx_model = convert(model, 'onnx', dummy_input)
            
        with open(output_path, "wb") as f:
            f.write(onnx_model.SerializeToString())
        return True
    except Exception as e:
        print(f"Failed to export {output_path}: {e}")
        return False

def process_artifacts():
    models_dir = "../../models"
    output_onnx_dir = "../output/models"
    output_manifest_dir = "../output/manifests"
    
    os.makedirs(output_onnx_dir, exist_ok=True)
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
            # Volatility models have '1h' and '4h' keys
            for tf in ['1h', '4h']:
                model, scaler, features = obj[tf]
                
                export_name = f"{filename}_{tf}"
                onnx_path = os.path.join(output_onnx_dir, f"{export_name}.onnx")
                
                success = export_model_to_onnx(model, len(features), onnx_path, scaler)
                if success:
                    manifest[export_name] = {
                        "num_features": len(features),
                        "features": features,
                        "has_embedded_scaler": True
                    }
                    print(f"  Exported {export_name}")
        else:
            # Other models just have 'model' and 'features'
            model = obj['model']
            features = obj['features']
            
            onnx_path = os.path.join(output_onnx_dir, f"{filename}.onnx")
            
            # These don't use standard scaler
            success = export_model_to_onnx(model, len(features), onnx_path, None)
            if success:
                manifest[filename] = {
                    "num_features": len(features),
                    "features": features,
                    "has_embedded_scaler": False
                }
                print(f"  Exported {filename}")
                
    # Save master manifest
    manifest_path = os.path.join(output_manifest_dir, "feature_manifest.json")
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)
    print(f"\nManifest saved to {manifest_path}")

if __name__ == "__main__":
    process_artifacts()