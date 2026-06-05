import Foundation

/// Registers the `edit_image` agentic tool.
///
/// The tool uses the Pillow library to edit the most recently user-attached
/// image.  The image is stored in `ImageStore.shared` by ChatView when the
/// user picks a photo, and is passed to Python as `img` (PIL.Image.Image).
/// The model writes Pillow code that edits `img` and assigns the result to
/// `result_img`.  The edited image is returned as a PNG.
///
/// Call `ImageEditTools.register()` once from `AIiOSApp.registerTools()`.
enum ImageEditTools {

    static func register() {
        ToolRegistry.shared.register(ToolDefinition(
            name: "edit_image",
            description: """
                Edits the user's most recently attached image using Python Pillow. \
                `img` is a PIL.Image.Image. Write code — the LAST line MUST assign to `result_img`. \
                CRITICAL: every code path must end with `result_img = <something>`. \
                Pre-imported: Image, ImageEnhance, ImageFilter, ImageOps, ImageDraw. \
                CORRECT API PATTERNS — always use these exact forms: \
                Rotate: result_img = img.rotate(90, expand=True) \
                Flip horizontal: result_img = ImageOps.mirror(img) \
                Flip vertical: result_img = ImageOps.flip(img) \
                Grayscale: result_img = img.convert('L') \
                Resize: result_img = img.resize((width, height), Image.LANCZOS) \
                Center crop to square: w,h=img.size; s=min(w,h); result_img=img.crop(((w-s)//2,(h-s)//2,(w+s)//2,(h+s)//2)) \
                Crop center half: w,h=img.size; result_img=img.crop((w//4,h//4,3*w//4,3*h//4)) \
                Brightness (>1=brighter): result_img = ImageEnhance.Brightness(img).enhance(1.5) \
                Contrast (>1=more): result_img = ImageEnhance.Contrast(img).enhance(1.5) \
                Sharpness (>1=sharper): result_img = ImageEnhance.Sharpness(img).enhance(2.0) \
                Color/saturation (0=gray,>1=vivid): result_img = ImageEnhance.Color(img).enhance(1.5) \
                Blur: result_img = img.filter(ImageFilter.GaussianBlur(radius=3)) \
                Sharpen filter: result_img = img.filter(ImageFilter.SHARPEN) \
                Edge detection: result_img = img.filter(ImageFilter.FIND_EDGES) \
                Emboss: result_img = img.filter(ImageFilter.EMBOSS) \
                Multi-step example (crop then enhance contrast): \
                w,h=img.size; cropped=img.crop((w//4,h//4,3*w//4,3*h//4)); result_img=ImageEnhance.Contrast(cropped).enhance(1.5) \
                NEVER call img.enhance() — that method does not exist. \
                NEVER call result_img = img.crop().enhance() — chain calls are invalid. \
                Always use ImageEnhance.Brightness/Contrast/Sharpness/Color(img).enhance(factor).
                """,
            parametersDoc: "code: string — Pillow Python code that edits `img` and assigns result to `result_img`",
            argsExample: #"{"code":"w,h=img.size; cropped=img.crop((w//4,h//4,3*w//4,3*h//4)); result_img=ImageEnhance.Contrast(cropped).enhance(1.5)"}"#,
            execute: { args in
                guard let code = args["code"] as? String, !code.isEmpty else {
                    return .text(#"{"error":"'code' parameter is required"}"#)
                }
                guard let imageData = ImageStore.shared.currentImageData else {
                    return .text(#"{"error":"No image attached. Please attach an image before asking me to edit it."}"#)
                }
                let imageB64 = imageData.base64EncodedString()
                return await PythonRunner.executeImageEdit(imageB64: imageB64, code: code)
            }
        ))
    }
}
