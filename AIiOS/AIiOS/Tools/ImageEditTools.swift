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
                The input image is available as `img` (PIL.Image.Image). \
                Write Pillow code to edit it and assign the result to `result_img`. \
                Pre-imported: Image, ImageEnhance, ImageFilter, ImageOps, ImageDraw. \
                Supported operations: resize, crop, rotate, flip, grayscale, \
                brightness/contrast/colour/sharpness adjustment, blur, sharpen, \
                edge detection, emboss, and any other Pillow operation.
                """,
            parametersDoc: "code: string — Pillow Python code that edits `img` and assigns result to `result_img`",
            argsExample: #"{"code":"result_img = img.rotate(90)"}"#,
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
