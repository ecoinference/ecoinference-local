import AVFoundation
import UIKit
import MessageUI

/// Hardware-access tools: battery, torch, SOS, map, SMS.
/// Mirrors Android HardwareTools.kt.
///
/// Note: get_location is registered separately in AIiOSApp.swift via LocationService.
enum HardwareTools {

    static func register() {
        registerBattery()
        registerTorch()
        registerSos()
        registerShowMap()
        registerSendSms()
    }

    // MARK: - Battery

    private static func registerBattery() {
        ToolRegistry.shared.register(ToolDefinition(
            name:          "get_battery",
            description:   "Returns the device battery level (0–100) and charging status.",
            parametersDoc: "(no parameters)",
            argsExample:   "{}",
            execute: { _ in
                let (level, charging) = await MainActor.run {
                    UIDevice.current.isBatteryMonitoringEnabled = true
                    let lvl = UIDevice.current.batteryLevel          // -1 if unavailable
                    let pct = lvl >= 0 ? Int(lvl * 100) : -1
                    let chg = UIDevice.current.batteryState == .charging ||
                              UIDevice.current.batteryState == .full
                    return (pct, chg)
                }
                return .text(#"{"level":\#(level),"charging":\#(charging)}"#)
            }
        ))
    }

    // MARK: - Torch

    private static func registerTorch() {
        ToolRegistry.shared.register(ToolDefinition(
            name:          "toggle_torch",
            description:   "Toggles the device flashlight on or off.",
            parametersDoc: "on: boolean (optional — if omitted, toggles current state)",
            argsExample:   "{\"on\":true}",
            execute: { args in
                guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
                    return .text(#"{"error":"No torch available on this device"}"#)
                }
                do {
                    try device.lockForConfiguration()
                    defer { device.unlockForConfiguration() }
                    let target: Bool
                    if let on = args["on"] as? Bool { target = on }
                    else { target = device.torchMode != .on }
                    device.torchMode = target ? .on : .off
                    return .text(#"{"torch":\#(target)}"#)
                } catch {
                    return .text(#"{"error":"\#(error.localizedDescription)"}"#)
                }
            }
        ))
    }

    // MARK: - SOS

    /// Flashes SOS in ITU Morse code (· · · — — — · · ·) using the torch.
    private static func registerSos() {
        ToolRegistry.shared.register(ToolDefinition(
            name:          "send_sos",
            description:   "Flashes the SOS Morse code (· · · — — — · · ·) using the device torch.",
            parametersDoc: "(no parameters)",
            argsExample:   "{}",
            execute: { _ in
                guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
                    return .text(#"{"error":"No torch available on this device"}"#)
                }
                // (on_ms, off_ms) — off_ms == 0 means no trailing gap on last symbol
                let sos: [(Int, Int)] = [
                    (200, 200), (200, 200), (200, 600),   // S: · · ·
                    (600, 200), (600, 200), (600, 600),   // O: — — —
                    (200, 200), (200, 200), (200, 0),      // S: · · ·
                ]
                do {
                    for (onMs, offMs) in sos {
                        try device.lockForConfiguration()
                        device.torchMode = .on
                        device.unlockForConfiguration()
                        try await Task.sleep(nanoseconds: UInt64(onMs) * 1_000_000)
                        try device.lockForConfiguration()
                        device.torchMode = .off
                        device.unlockForConfiguration()
                        if offMs > 0 {
                            try await Task.sleep(nanoseconds: UInt64(offMs) * 1_000_000)
                        }
                    }
                    return .text(#"{"result":"SOS signal complete (· · · — — — · · ·)"}"#)
                } catch {
                    return .text(#"{"error":"\#(error.localizedDescription)"}"#)
                }
            }
        ))
    }

    // MARK: - Show map

    private static func registerShowMap() {
        ToolRegistry.shared.register(ToolDefinition(
            name:          "show_map",
            description:   "Gets the current GPS location and opens it in the device Maps app.",
            parametersDoc: "(no parameters)",
            argsExample:   "{}",
            execute: { _ in
                do {
                    let loc = try await LocationService.shared.requestLocation()
                    let lat = loc.latitude; let lon = loc.longitude
                    let urlStr = "maps://?q=\(lat),\(lon)&ll=\(lat),\(lon)&z=17"
                    guard let url = URL(string: urlStr) else {
                        return .text(#"{"error":"Could not construct Maps URL"}"#)
                    }
                    await MainActor.run { UIApplication.shared.open(url) }
                    return .text(#"{"result":"Map opened","latitude":\#(lat),"longitude":\#(lon)}"#)
                } catch {
                    return .text(#"{"error":"\#(error.localizedDescription)"}"#)
                }
            }
        ))
    }

    // MARK: - Send SMS

    private static func registerSendSms() {
        ToolRegistry.shared.register(ToolDefinition(
            name:          "send_sms",
            description:   "Opens the Messages app pre-filled with a recipient and message. User must tap Send.",
            parametersDoc: "to: string (phone number), message: string",
            argsExample:   "{\"to\":\"+15551234567\",\"message\":\"Hello!\"}",
            execute: { args in
                guard let to = args["to"] as? String, !to.isEmpty else {
                    return .text(#"{"error":"'to' is required"}"#)
                }
                guard let message = args["message"] as? String, !message.isEmpty else {
                    return .text(#"{"error":"'message' is required"}"#)
                }
                let encoded  = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                let urlStr   = "sms:\(to)&body=\(encoded)"
                guard let url = URL(string: urlStr) else {
                    return .text(#"{"error":"Could not construct SMS URL"}"#)
                }
                let opened = await MainActor.run { UIApplication.shared.canOpenURL(url) }
                if opened {
                    await MainActor.run { UIApplication.shared.open(url) }
                    return .text(#"{"result":"SMS app opened for \#(to)"}"#)
                } else {
                    return .text(#"{"error":"SMS not available on this device"}"#)
                }
            }
        ))
    }
}
