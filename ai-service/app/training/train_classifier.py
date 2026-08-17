# Training pipeline placeholder.
#
# A labelled waste-photo dataset (plastic/metal/paper/other) plus a trained
# artifact are NOT yet present in this repository. Until a model exists:
#
#   1. build/collect a labelled dataset of station-top camera captures
#   2. train a small CNN (see train_classifier.py) and export to ONNX
#   3. set AI_SERVICE_CLASSIFIER=real and AI_MODEL_PATH=/app/models/model.onnx
#
# Before that, the service -- and only the service -- may run the clearly
# labelled DevelopmentClassifier (source=demo) so the pipeline is exercisable
# end-to-end. Nothing in the backend or hardware loop needs to change.
from __future__ import annotations

import os
import sys


def requires_torch():
    try:
        import torch  # noqa: F401
    except ImportError:
        sys.exit("torch is required for training; install extras or use the dev classifier for now")


def main() -> None:
    requires_torch()
    dataset_dir = os.environ.get("DATASET_DIR", "data")
    print(f"[TRAIN] placeholder — training on {dataset_dir} is not part of this deliverable.")
    print("Export the checkpoint with torch.onnx.export once training exists.")


if __name__ == "__main__":
    main()