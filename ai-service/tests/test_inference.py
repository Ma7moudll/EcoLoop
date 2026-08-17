"""Development classifier: deterministic behavior + honest labeling.
Real classifier: must refuse to run without a trained artifact."""
from __future__ import annotations

import io

import pytest
from PIL import Image

from app.inference import DevelopmentClassifier, get_classifier
from app.inference.real import ModelNotReadyError, RealInferenceClassifier


def _image_png(color) -> bytes:
    img = Image.new("RGB", (64, 64), color)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def _image_jpeg(color) -> bytes:
    img = Image.new("RGB", (64, 64), color)
    buf = io.BytesIO()
    img.save(buf, format="JPEG")
    return buf.getvalue()


class TestDevelopmentClassifier:
    def test_blue_image_is_plastic(self):
        result = DevelopmentClassifier().predict(_image_png((20, 40, 200)))
        assert result.predicted_class == "plastic"
        assert result.model == "development"

    def test_red_bright_image_is_metal(self):
        result = DevelopmentClassifier().predict(_image_png((230, 160, 60)))
        assert result.predicted_class == "metal"

    def test_light_grey_image_is_paper(self):
        result = DevelopmentClassifier().predict(_image_png((230, 230, 230)))
        assert result.predicted_class == "paper"

    def test_dark_image_is_other(self):
        result = DevelopmentClassifier().predict(_image_png((40, 40, 40)))
        assert result.predicted_class == "other"

    def test_deterministic(self):
        data = _image_jpeg((20, 40, 200))
        a = DevelopmentClassifier().predict(data)
        b = DevelopmentClassifier().predict(data)
        assert a.to_dict() == b.to_dict()

    def test_confidence_clamped_to_unit_interval(self):
        result = DevelopmentClassifier(force_class="plastic", force_confidence=2.0).predict(_image_png((0, 0, 0)))
        assert 0.0 <= result.confidence <= 1.0

    def test_force_class_override(self):
        result = DevelopmentClassifier(force_class="metal", force_confidence=0.88).predict(_image_png((0, 0, 0)))
        assert result.predicted_class == "metal"
        assert result.confidence == 0.88

    def test_model_name(self):
        assert DevelopmentClassifier().model_name == "development"


class TestRealClassifier:
    def test_raises_when_no_artifact(self):
        with pytest.raises(ModelNotReadyError):
            RealInferenceClassifier(model_path="/nonexistent/model.onnx")

    def test_message_explains_how_to_fix(self):
        with pytest.raises(ModelNotReadyError) as exc:
            RealInferenceClassifier(model_path="")
        assert "AI_MODEL_PATH" in str(exc.value)
        assert "development" in str(exc.value)


class TestFactory:
    def test_get_classifier_returns_development_by_default(self):
        assert get_classifier().model_name == "development"

    def test_result_has_wire_shape(self):
        result = get_classifier().predict(_image_png((20, 40, 200)))
        d = result.to_dict()
        assert d == {
            "predicted_class": "plastic",
            "confidence": result.confidence,
            "model": "development",
        }


class TestHttpContract:
    def test_health(self):
        from fastapi.testclient import TestClient

        from app.main import app

        with TestClient(app) as c:
            r = c.get("/health")
            assert r.status_code == 200
            assert r.json()["classifier"] == "development"

    def test_predict_returns_wire_contract(self):
        from fastapi.testclient import TestClient

        from app.main import app

        with TestClient(app) as c:
            r = c.post("/predict", files={"image": ("capture.jpg", _image_jpeg((20, 40, 200)), "image/jpeg")})
            assert r.status_code == 200
            body = r.json()
            assert body["predicted_class"] in ("plastic", "metal", "paper", "other")
            assert 0.0 <= body["confidence"] <= 1.0
            assert body["model"] == "development"
            assert "elapsed_ms" in body

    def test_empty_image_rejected(self):
        from fastapi.testclient import TestClient

        from app.main import app

        with TestClient(app) as c:
            r = c.post("/predict", files={"image": ("empty.jpg", b"", "image/jpeg")})
            assert r.status_code == 422