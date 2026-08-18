# Physical-device validation results — Android camera → real AI

**STATUS: BLOCKED.** Physical-device validation is blocked because no physical
Android device is available. The only attached device is the emulator
(`emulator-5554`), whose virtual-scene camera is explicitly out of scope for
this objective. **No results are reported here, and none may be fabricated.**

The exact reproducible procedure is in `docs/android-physical-camera-e2e.md`.
Once a physical device is attached (`adb devices -l` shows `device`), run that
procedure and fill the tables below with real measurements only.

---

## Device

| field | value |
|---|---|
| model | _(none — blocked)_ |
| Android version | _(none — blocked)_ |
| adb serial | _(none — blocked)_ |

## Real objects & captures

| field | value |
|---|---|
| plastic objects | 0 |
| metal objects | 0 |
| paper objects | 0 |
| other objects | 0 |
| total captures | 0 |
| class distribution | — |

## Per-capture results

| Object | Expected | Predicted | Confidence | Gate | Correct |
|--------|----------|-----------|------------|------|---------|
| _(no captures — blocked)_ |

## Failure cases

| case | gate/classifier behavior |
|---|---|
| empty background | _(not recorded — blocked)_ |
| hand without waste | _(not recorded — blocked)_ |
| very blurry frame | _(not recorded — blocked)_ |
| very dark frame | _(not recorded — blocked)_ |
| multiple unrelated objects | _(not recorded — blocked)_ |
| partially occluded object | _(not recorded — blocked)_ |

## Metrics

| metric | value |
|---|---|
| total samples | 0 |
| correct | 0 |
| incorrect | 0 |
| accuracy | — |
| macro F1 | — |

### Per class

| class | precision | recall | F1 |
|---|---|---|---|
| plastic | — | — | — |
| metal | — | — | — |
| paper | — | — | — |
| other | — | — | — |

### Confusion matrix

_(not computed — blocked)_

## Gate observations

- Gate false rejections: _(blocked)_
- OOD/background behavior: _(blocked)_

## Latency (median / p95, ms)

| stage | median | p95 |
|---|---|---|
| camera capture | — | — |
| upload / network | — | — |
| gate | — | — |
| AI inference | — | — |
| total API | — | — |

## Byte identity

SHA-256 proof for ≥1 physical capture: _(blocked — see procedure §7; the debug
endpoint is mounted only with `DEBUG_IMAGE_HASH=true` and is user-invisible and
never enabled in production)_

## Decision

- `model.onnx` changed: **NO — no change was made; no retraining, no
  fine-tuning, no threshold/gate tuning occurred.**
- Next step: attach a physical Android device and run
  `docs/android-physical-camera-e2e.md` to collect the first tier-C samples.

The ground truth for any future entry in this table is the **human-labelled
`expected` class** — never the AI prediction.