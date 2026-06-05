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
