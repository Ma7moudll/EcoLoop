"""Station-camera probe: run the real classifier over a folder of captures and
print Prediction / Raw confidence / Calibrated confidence / Level / Latency.

By default inference runs locally with the served ONNX artifact (identical
preprocess math to the deployed ai-service), so Raw and Calibrated confidence
are exact. With `--via-api <base-url>` the same images are ALSO posted to a
running ai-service to confirm the deployed path agrees.

    scripts/test_real_camera.py --folder ./station_shots
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "ai-service"))

from app.training.train import load_onnx_session  # noqa: E402
from app.tools.preprocess import decode_image, to_model_input  # noqa: E402

HIGH = 0.80
MEDIUM = 0.50

VALID_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}


def load_calibration() -> dict | None:
    path = ROOT / "ai-service" / "models" / "calibration.json"
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def temperature_scale(probs, T: float):
    import numpy as np
    logits = np.log(np.clip(probs, 1e-12, 1.0))
    logits = logits / T - logits.max()
    e = np.exp(logits)
    return e / e.sum()


def level(conf: float) -> str:
    if conf >= HIGH:
        return "HIGH"
    if conf >= MEDIUM:
        return "MEDIUM"
    return "LOW"


def infer_local(session, path: Path, model_path: Path):
    import numpy as np
    with open(path, "rb") as fh:
        blob = fh.read()
    t0 = time.perf_counter()
    probs = session.run(
        None,
        {session.get_inputs()[0].name: to_model_input(decode_image(blob), model_path)},
    )[0][0]
    elapsed_ms = (time.perf_counter() - t0) * 1000.0
    idx = int(np.argmax(probs).item())
    return probs, idx, elapsed_ms


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--folder", required=True, help="folder of camera captures")
    p.add_argument("--model", default=str(ROOT / "ai-service" / "models" / "model.onnx"))
    p.add_argument("--via-api", default="", help="optional running ai-service base url")
    p.add_argument("--latency-run", type=int, default=3,
                   help="repeats for the latency column")
    args = p.parse_args()

    folder = Path(args.folder)
    if not folder.is_dir():
        print(f"folder not found: {folder}")
        return 1
    model_path = Path(args.model)
    if not model_path.exists():
        print(f"model not found: {model_path}")
        return 1

    session = load_onnx_session(model_path)
    calib = load_calibration()
    T = calib["temperature"] if calib else None
    images = sorted(p for p in folder.rglob("*") if p.suffix.lower() in VALID_EXTS)
    if not images:
        print(f"no images under {folder}")
        return 1

    print(f"folder           : {folder}")
    print(f"model            : {model_path}")
    print(f"calibration.json : {'T=%.4f' % T if T is not None else 'NOT PRESENT'}")
    print()
    print(f"{'file':<36} {'prediction':<10} {'raw conf':>9} {'calib conf':>10} {'level':<7} {'latency ms':>10}")
    print("-" * 92)

    import httpx

    client = httpx.Client(timeout=30.0) if args.via_api else None
    base = args.via_api.rstrip("/")
    ok = 0
    for path in images:
        probs, idx, ms = infer_local(session, path, model_path)
        raw = float(probs[idx])
        cal = float(temperature_scale(probs, T)[idx]) if T is not None else float("nan")
        cls = ["plastic", "metal", "paper", "other"][idx]
        print(f"{str(path.relative_to(folder))[:36]:<36} {cls:<10} {raw:9.4f} "
              f"{cal:10.4f} {level(raw):<7} {ms:10.1f}")
        if client is not None:
            r = client.post(f"{base}/predict", files={
                "image": (path.name, path.read_bytes(), "image/jpeg")
            })
            body = r.json()
            match = body.get("predicted_class") == cls and r.status_code == 200
            print(f"   [via-api {base}] status={r.status_code} "
                  f"pred={body.get('predicted_class')} "
                  f"conf={body.get('confidence')} elapsed_ms={body.get('elapsed_ms')} "
                  f"{'OK' if match else 'MISMATCH'}")
            ok += 1 if match else 0

    # latency summary over the first image
    if images:
        reps = []
        for _ in range(max(1, args.latency_run)):
            _, _, ms = infer_local(session, images[0], model_path)
            reps.append(ms)
        print(f"\nlatency (n={len(reps)}, {images[0].name}): "
              f"mean {sum(reps)/len(reps):.1f} ms, max {max(reps):.1f} ms")

    if client is not None:
        print(f"\nvia-api agreement: {ok}/{len(images)}")
        client.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())