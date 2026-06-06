"""
On-device Python execution module for EcoInference.

Called from Kotlin via Chaquopy:
    Python.getInstance().getModule("runner").callAttr("run_code", code)

Returns a list [type, value] where:
    type  = "text" | "image" | "html" | "error"
    value = string (plain text / base64 PNG / full HTML / error message)
"""

import os
import sys
import io
import traceback
import base64

# Force Agg (non-interactive) backend before matplotlib is imported anywhere.
os.environ["MPLBACKEND"] = "Agg"


def run_code(code: str) -> list:
    """Execute code and return [type, value]."""

    # ── Capture stdout ────────────────────────────────────────────────────────
    old_stdout = sys.stdout
    sys.stdout = captured = io.StringIO()

    namespace: dict = {}

    try:
        exec(compile(code, "<run_code>", "exec"), namespace)  # noqa: S102
    except Exception:
        sys.stdout = old_stdout
        return ["error", traceback.format_exc().strip()]
    finally:
        sys.stdout = old_stdout

    stdout_val = captured.getvalue()

    # ── Priority 1: matplotlib figure → PNG base64 ────────────────────────────
    try:
        import matplotlib.pyplot as plt  # noqa: PLC0415
        if plt.get_fignums():
            buf = io.BytesIO()
            plt.gcf().savefig(buf, format="png", bbox_inches="tight", dpi=150)
            plt.close("all")
            buf.seek(0)
            return ["image", base64.b64encode(buf.read()).decode("ascii")]
    except ImportError:
        pass

    # ── Priority 2: plotly figure in namespace → full HTML ────────────────────
    try:
        import plotly.basedatatypes as _pbt  # noqa: PLC0415
        for v in reversed(list(namespace.values())):
            if isinstance(v, _pbt.BaseFigure):
                return ["html", v.to_html(include_plotlyjs="cdn", full_html=True)]
    except ImportError:
        pass

    # ── Priority 3: explicit `result` variable ────────────────────────────────
    result = namespace.get("result")
    if result is not None:
        s = str(result).strip()
        if s.startswith("data:image/png;base64,"):
            return ["image", s.removeprefix("data:image/png;base64,")]
        if s.lstrip().startswith("<!DOCTYPE") or s.lstrip().startswith("<html"):
            return ["html", s]
        if s:
            return ["text", s]

    # ── Priority 4: stdout from print() ──────────────────────────────────────
    if stdout_val.strip():
        return ["text", stdout_val.strip()]

    # ── Nothing produced ──────────────────────────────────────────────────────
    return [
        "error",
        "Code ran but produced no output. "
        "Assign your answer to 'result' or use print().",
    ]


def generate_qr(text: str, box_size: int = 10, border: int = 4) -> list:
    """
    Generate a QR code PNG from any text, URL, or structured data.

    Returns [type, value] with type="image" and value=base64 PNG.
    The image uses EcoInference brand colours (green on dark).
    """
    import qrcode  # noqa: PLC0415
    from PIL import Image as _Image  # noqa: PLC0415

    if not text or not text.strip():
        return ["error", "text must not be empty"]

    qr = qrcode.QRCode(
        version=None,           # auto-pick smallest version that fits
        error_correction=qrcode.constants.ERROR_CORRECT_M,
        box_size=max(1, min(box_size, 20)),
        border=max(0, min(border, 10)),
    )
    qr.add_data(text)
    qr.make(fit=True)

    img = qr.make_image(fill_color="#22C55E", back_color="#0F2415")

    buf = io.BytesIO()
    img.save(buf, format="PNG")
    buf.seek(0)
    return ["image", base64.b64encode(buf.read()).decode("ascii")]


def edit_image(image_b64: str, code: str) -> list:
    """
    Edit an image using Pillow and return the result as a PNG.

    The input image is decoded from `image_b64` (base64 JPEG/PNG) and
    injected into the execution namespace as `img` (PIL.Image.Image).
    The code must assign the edited image to `result_img`.

    Returns [type, value] with the same contract as run_code().
    """
    from PIL import Image, ImageEnhance, ImageFilter, ImageOps, ImageDraw  # noqa: PLC0415

    # ── Decode input image ────────────────────────────────────────────────────
    try:
        img_bytes = base64.b64decode(image_b64)
        img = Image.open(io.BytesIO(img_bytes))
        img.load()  # force decode so errors surface here
    except Exception:
        return ["error", "Failed to decode input image:\n" + traceback.format_exc().strip()]

    # ── Build namespace with Pillow helpers pre-imported ─────────────────────
    namespace: dict = {
        "img":           img,
        "Image":         Image,
        "ImageEnhance":  ImageEnhance,
        "ImageFilter":   ImageFilter,
        "ImageOps":      ImageOps,
        "ImageDraw":     ImageDraw,
    }

    # ── Capture stdout ────────────────────────────────────────────────────────
    old_stdout = sys.stdout
    sys.stdout = io.StringIO()

    try:
        exec(compile(code, "<edit_image>", "exec"), namespace)  # noqa: S102
    except Exception:
        sys.stdout = old_stdout
        return ["error", traceback.format_exc().strip()]
    finally:
        sys.stdout = old_stdout

    # ── Extract result image ──────────────────────────────────────────────────
    # Primary: look for the canonical `result_img` variable.
    # Fallback: if the model used a different name (output, edited, new_img …)
    # accept the last PIL Image assigned in the namespace that isn't `img`.
    _injected_keys = {"img", "Image", "ImageEnhance", "ImageFilter", "ImageOps", "ImageDraw"}
    result_img = namespace.get("result_img")
    if result_img is None:
        for _key, _val in reversed(list(namespace.items())):
            if _key not in _injected_keys and isinstance(_val, Image.Image):
                result_img = _val
                break
    if result_img is None:
        return [
            "error",
            "Code must assign the edited image to `result_img`.\n"
            "Example: result_img = img.rotate(90)",
        ]
    if not isinstance(result_img, Image.Image):
        return ["error", f"`result_img` must be a PIL.Image.Image, got {type(result_img).__name__}"]

    # ── Encode result as PNG base64 ───────────────────────────────────────────
    try:
        buf = io.BytesIO()
        result_img.save(buf, format="PNG")
        buf.seek(0)
        return ["image", base64.b64encode(buf.read()).decode("ascii")]
    except Exception:
        return ["error", "Failed to encode result image:\n" + traceback.format_exc().strip()]
