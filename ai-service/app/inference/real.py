"""Deep-learning classifier backed by a trained model artifact.

Swappable backends (onnxruntime, TensorFlow Lite, PyTorch) are probed lazily.
If no trained artifact exists at `AI_MODEL_PATH` a clear [ModelNotReadyError]
is raised — the system never pretends an untrained model works.

To plug in a real model:
  1. export it to ONNX (or provide a .tflite / torch checkpoint).
  2. set AI_MODEL_PATH=/data/model.onnx
  3. set AI_SERVICE_CLASSIFIER=real
No backend code changes required beyond the (small) preprocessing hook in
`_preprocess`.
"""
from __future__ import annotations

import os
from pathlib import Path

import numpy as np
import PIL.Image

from .base import ClassificationResult, WasteClassifier

# Adversarial classes the service can never report.
VALID = {"plastic", "metal", "paper", "other"}


class ModelNotReadyError(RuntimeError):
    pass


class RealInferenceClassifier(WasteClassifier):
    def __init__(self, model_path: str | None = None, backend: str = "auto") -> None:
        self.model_path = Path(model_path or os.environ.get("AI_MODEL_PATH", "") or "")
        self.backend_name = self._detect_backend(self.model_path, backend)
        if self.backend_name is None:
            raise ModelNotReadyError(
                "No trained model artifact found at "
                f"{self.model_path or '<unset>'}. "
                "Train/export a model and set AI_MODEL_PATH, or run the "
                "isolated DevelopmentClassifier (AI_SERVICE_CLASSIFIER=development) "
                "which is explicitly labeled as non-real."
            )
        self._session = self._load(self.model_path, self.backend_name)

    @staticmethod
    def _detect_backend(model_path: Path, backend: str) -> str | None:
        if not model_path.exists():
            return None
        if model_path.suffix == ".onnx":
            try:
                import onnxruntime  # noqa: F401

                return "onnx"
            except ImportError:
                return None
        if model_path.suffix == ".tflite":
            try:
                import tflite_runtime  # noqa: F401

                return "tflite"
            except ImportError:
                return None
        if model_path.suffix in (".pt", ".pth"):
            try:
                import torch  # noqa: F401

                return "torch"
            except ImportError:
                return None
        return None

    @staticmethod
    def _load(model_path: Path, backend: str):
        if backend == "onnx":
            import onnxruntime as ort

            return ort.InferenceSession(str(model_path), providers=["CPUExecutionProvider"])
        if backend == "tflite":
            import tflite_runtime.interpreter as tflite

            interp = tflite.Interpreter(model_path=str(model_path))
            interp.allocate_tensors()
            return interp
        if backend == "torch":
            import torch

            return torch.jit.load(str(model_path), map_location="cpu")
        raise ModelNotReadyError(f"Unsupported backend {backend}")

    @property
    def model_name(self) -> str:
        return "real"

    def predict(self, image_data: bytes) -> ClassificationResult:
        image = PIL.Image.open(__import__("io").BytesIO(image_data)).convert("RGB")
        tensor = self._preprocess(image)
        probabilities = self._forward(tensor)
        if self.backend_name == "tflite":
            probabilities = probabilities[0]
        idx = int(np.argmax(probabilities).item())
        predicted = ("plastic", "metal", "paper", "other")[idx]
        confidence = float(np.clip(probabilities[idx], 0.0, 1.0))
        return ClassificationResult(
            predicted_class=predicted if predicted in VALID else "other",
            confidence=confidence,
            model="real",
        )

    def _preprocess(self, image: PIL.Image.Image) -> np.ndarray:
        """Resize + normalize — the only hook that depends on the chosen model.
        Default: MobileNet-style 224x224, ImageNet mean/std."""
        resized = image.resize((224, 224))
        arr = np.asarray(resized, dtype=np.float32) / 255.0
        mean = np.array([0.485, 0.456, 0.406], dtype=np.float32)
        std = np.array([0.229, 0.224, 0.225], dtype=np.float32)
        arr = (arr - mean) / std
        return np.transpose(arr, (2, 0, 1))[None, ...]

    def _forward(self, tensor: np.ndarray) -> np.ndarray:
        if self.backend_name == "onnx":
            input_name = self._session.get_inputs()[0].name
            outputs = self._session.run(None, {input_name: tensor})
            return np.asarray(outputs[0], dtype=np.float32)
        if self.backend_name == "tflite":
            det = self._session.get_input_details()
            out = self._session.get_output_details()
            self._session.set_tensor(det[0]["index"], tensor)
            self._session.invoke()
            return np.asarray(self._session.get_tensor(out[0]["index"]), dtype=np.float32)
        import torch

        with torch.no_grad():
            logits = self._session(torch.from_numpy(tensor))
            return torch.softmax(logits, dim=1).squeeze(0).numpy()