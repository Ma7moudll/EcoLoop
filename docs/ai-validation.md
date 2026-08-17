# AI validation pipeline — station-camera data collection & model validation

The EcoLoop station-top camera will one day feed images into the existing AI
service (`ai-service`). This document describes the production-oriented
**data-collection and model-validation pipeline** that exists today so the
team is ready for that camera — and, crucially, it draws a hard line between
what the current numbers prove and what they do **not** prove.

The pipeline lives under `ai-service/app/tools/` and runs on the venv:

```bash
cd ai-service
../.venv/bin/python -m app.tools.<tool> --help   # every tool is a CLI
```

## Provenance rules (non-negotiable)

- Every real capture is tagged `source=manual-capture` (or a user-supplied
  camera tag) by `collect.py`.
- Every simulated sample is tagged `source=simulated-station-pilot` — the
  constant `PILOT_SOURCE` in `app/tools/common.py` is written on **every**
  generated row of `metadata.csv`. It can never be confused with a real capture.
- All reports carry this disclaimer verbatim:

  > These results validate the training/validation pipeline under simulated
  > camera distribution shift. They do NOT establish performance on the real
  > EcoLoop station camera.

## The three evidence tiers

| tier | what | what it proves |
|---|---|---|
| A — TrashNet benchmark | `reports/eval_report.md` | the served model on the academic dataset it was trained on |
| B — simulated-station-pilot | `reports/dataset_report.md`, `calibration_report.md`, `finetune_report.md`, `model_compare.md`, `open_set_report.md`, `input_gate_report.md` | the pipeline works end-to-end under simulated distribution shift |
| C — real station camera | **none yet** | — |

**Real station-camera accuracy has NOT yet been established because no real
station-camera captures are currently available.**

## Tools

| tool | purpose |
|---|---|
| `app.tools.collect` | interactive capture + **human** labeling (1 plastic / 2 metal / 3 paper / 4 other). Webcam via cv2 → `imagesnap` → falls back to `--input`; never auto-labels |
| `app.tools.dataset_check` | corruption / exact-dup (md5) / near-dup (dHash) / dimension / class-balance gate → `reports/dataset_report.md` |
| `app.tools.split_dataset` | **leakage-free** 70/15/15 split grouped by `session_id`/`object_id` → `data/station_capture_splits/` + `splits.json` |
| `app.tools.make_pilot` | renders the simulated pilot from local TrashNet with session/object identity + realistic station-camera augmentation |
| `app.tools.calibrate` | temperature scaling on the pilot val split; ECE (15 bins) / Brier / NLL before + after → `models/calibration.json` |
| `app.tools.train_finetune` | baseline vs fine-tuned model on the held-out pilot test → `reports/finetune_report.md` |
| `app.tools.model_compare` | served MobileNetV3-Small vs SqueezeNet1.1 candidate → `reports/model_compare.md` |
| `app.tools.open_set` | synthetic OOD false-acceptance at the backend thresholds → `reports/open_set_report.md` |
| `app.tools.quality_gate` | camera/input quality gate + object-presence gate that run **before** classification (see below) |
| `app.tools.preprocess` | the single deterministic preprocess (resize→center-crop→normalize) shared by probe, API and camera |
| `app.tools.gate_report` | gate evaluation (false rejection / false acceptance / latency) → `reports/input_gate_report.md` |

### The input gate (runs before the classifier)

The deployed pipeline is:

```
Camera -> Input Quality Gate -> Object Presence Gate -> Preprocessing
       -> Waste Classifier -> Calibration -> Routing
```

`InputQualityGate` (decode → dimensions → brightness/contrast/entropy →
Laplacian-variance blur) rejects blank, dark, overexposed, flat, low-info,
tiny and corrupt frames as `LOW_QUALITY`/`CORRUPT_IMAGE`. `ObjectPresenceDetector`
then rejects empty frames (nothing in the centre of the frame) as `NO_OBJECT`.
Only `VALID_FRAME` ever reaches the classifier. A rejected frame gets a
structured 422 (`{"code": "NO_OBJECT"|"LOW_QUALITY"|"CORRUPT_IMAGE", ...}`)
from the AI service; the backend passes the code through, persists nothing, and
no deposit session can be created.

> **Disclaimer:** The object-presence gate is a lightweight CV heuristic that
> prevents obvious background/empty frames from reaching the classifier. It
> does **not** establish real-world object-detection performance. Textured
> backgrounds and edge-rich OOD frames can still pass it; the backend
> confidence policy (<0.50 refused, 0.50–0.79 manual review) remains the
> backstop, and `ObjectPresenceDetector` is the swap-in point for a real
> detector later. See `reports/input_gate_report.md` for the honest
> false-rejection / false-acceptance numbers and measured latencies.

### How a station capture should be collected

```bash
cd ai-service
../.venv/bin/python -m app.tools.collect \
    --camera station-001-top --session s2026-08-17-morning \
    --lighting day --background tray --occlusion none --object-count 1
# 1 plastic, 2 metal, 3 paper, 4 other — never an AI label
```

### How to validate after a real capture session

```bash
cd ai-service
../.venv/bin/python -m app.tools.dataset_check
../.venv/bin/python -m app.tools.split_dataset
../.venv/bin/python -m app.tools.calibrate
../.venv/bin/python -m app.tools.train_finetune
../.venv/bin/python -m app.tools.model_compare
../.venv/bin/python -m app.tools.open_set
../.venv/bin/python -m app.tools.gate_report
../.venv/bin/python -m app.training.train --eval-only   # refresh the A-tier baseline
../../scripts/test_real_camera.py --folder <capture-folder>
```

## Why the simulated pilot is not "real data"

- `make_pilot` re-renders **TrashNet** images (the model's own training
  distribution family) through mild station-camera augmentation. It is a
  distribution-shift *simulation*, so tier-B numbers bound the pipeline's
  behavior — not the camera's.
- Real station images will differ in camera pose, height, tray geometry,
  lighting, glare, and background clutter. The open-set report's
  false-acceptance numbers are computed on synthetic non-waste frames and are
  therefore an *estimate*, not a guarantee.

## Open-set / background risk

A fixed camera sees background-only frames (empty tray, hands, bin edges).
The classifier is trained only on waste objects; the open-set probe measures
how often such frames would pass the backend policy thresholds. On the live
system the **input quality + object-presence gate** (`app.tools.quality_gate`)
now runs before classification and rejects obvious blank/empty/background
frames — see `reports/input_gate_report.md`. The gate is deliberately
balanced (permissive on real waste, false-rejection 0% on the pilot test) and
is **not** a real object detector; the classifier confidence policy and a
future detection stage remain the depth layers of defence.

## Model swap discipline

`train_finetune` and `model_compare` only produce **candidate** artifacts under
`data/checkpoints/` (gitignored). Swapping the served `models/model.onnx` is a
separate, explicit decision that requires:

1. a clear, justified improvement on tier-B test (and ideally tier-C real data),
2. re-validation of the E2E chain (`scripts/e2e_real_chain.py`, 30 checks),
3. updated `fixtures.json` + fixture images for the confidence-band tests.

The served model is currently **unchanged** by this pipeline.
