//
//  DeviceClassifier.swift
//  BRB
//
//  Infers device categories (buds, headphones, phone, computer, etc.)
//  using Bluetooth SIG standards (Appearance UUID 0x2A01, Company IDs),
//  Apple Continuity protocol signatures (Nearby Info, AirPods, AirTag),
//  Google Fast Pair, and curated device name patterns.
//

import SwiftUI

// MARK: - Device Category Definition

enum DeviceCategory: String, Codable, CaseIterable {
    case buds
    case headphones
    case phone
    case computer
    case tablet
    case watch
    case mouse
    case keyboard
    case speaker
    case tag
    case unknown

    var symbol: String {
        switch self {
        case .buds: return "airpodspro"
        case .headphones: return "headphones"
        case .phone: return "iphone"
        case .computer: return "macbook"
        case .tablet: return "ipad"
        case .watch: return "applewatch"
        case .mouse: return "computermouse"
        case .keyboard: return "keyboard"
        case .speaker: return "hifispeaker"
        case .tag: return "airtag"
        case .unknown: return "antenna.radiowaves.left.and.right"
        }
    }

    /// Dark-enough stops throughout: the 28pt glyph is white, so every
    /// gradient must keep contrast (no yellows / light greys / cyans).
    var gradient: (Color, Color) {
        switch self {
        case .buds: return (.purple, .blue)
        case .headphones: return (.indigo, .teal)
        case .phone: return (.green, .teal)
        case .computer: return (Color(red: 0.32, green: 0.35, blue: 0.43), .black)
        case .tablet: return (.blue, .indigo)
        case .watch: return (.orange, .pink)
        case .mouse: return (.orange, .brown)
        case .keyboard: return (.purple, .pink)
        case .speaker: return (.red, .orange)
        case .tag: return (.teal, .blue)
        case .unknown: return (Color(white: 0.35), .black)
        }
    }

    /// Short spoken/written label for accessibility.
    var label: String {
        switch self {
        case .buds: return "Earbuds"
        case .headphones: return "Headphones"
        case .phone: return "Phone"
        case .computer: return "Computer"
        case .tablet: return "Tablet"
        case .watch: return "Watch"
        case .mouse: return "Mouse"
        case .keyboard: return "Keyboard"
        case .speaker: return "Speaker"
        case .tag: return "Tracker tag"
        case .unknown: return "Bluetooth device"
        }
    }
}

// MARK: - Bluetooth SIG Appearance (UUID 0x2A01)
// Standard 16-bit appearance categories defined by Bluetooth SIG:
// Category = appearance >> 6, Subcategory = appearance & 0x3F.

func categoryFromSIGAppearance(_ appearance: UInt16) -> DeviceCategory {
    let category = appearance >> 6
    let sub = appearance & 0x3F

    switch category {
    case 1: // Generic Phone (64...127)
        return .phone
    case 2: // Generic Computer (128...191)
        return .computer
    case 3: // Generic Watch / Sports Watch (192...255)
        return .watch
    case 15: // HID (960...1023)
        if sub == 1 { return .keyboard }
        if sub == 2 { return .mouse }
        return .mouse
    case 32: // Generic Audio (2048...2111)
        switch sub {
        case 4: return .buds // Earbud / TWS (2052)
        case 2: return .headphones // Headphones (2050)
        case 1: return .headphones // Headset (2049)
        case 5, 7: return .speaker // Soundbar / Speaker (2053, 2055)
        default: return .buds
        }
    default:
        // Direct value fallback for standard codes
        switch appearance {
        case 64...127: return .phone
        case 128...191: return .computer
        case 192...255: return .watch
        case 961: return .keyboard
        case 962: return .mouse
        case 2049, 2050: return .headphones
        case 2052: return .buds
        case 2054, 2055: return .speaker
        default: return .unknown
        }
    }
}

private func isPlaceholderName(_ name: String) -> Bool {
    let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return n.isEmpty || n.lowercased().contains("(unnamed)")
}

// MARK: - Classifier

/// Classifies a device based on name, appearance, Apple Continuity headers,
/// and vendor profiles.
func classifyDevice(
    name: String,
    companyID: UInt16? = nil,
    appleContinuityType: UInt8? = nil,
    sigAppearance: UInt16? = nil,
    hasFastPair: Bool = false
) -> DeviceCategory {
    // 1. Bluetooth SIG Appearance (UUID 0x2A01) takes priority when present
    // as it is an explicit declaration by the device firmware.
    if let sigAppearance {
        let cat = categoryFromSIGAppearance(sigAppearance)
        if cat != .unknown { return cat }
    }

    // 2. Name-based heuristics for named devices
    if !isPlaceholderName(name) {
        let n = name.lowercased()

        // --- Earbuds / TWS (Checked early to match "buds" and specific models) ---
        if n.contains("airpods max") {
            return .headphones
        }
        if n.contains("airpods") {
            return .buds
        }
        if n.contains("buds") || n.contains("freebuds") || n.contains("soundcore")
            || n.contains("r60i") || n.contains("aero") || n.contains("life ")
            || n.contains("pixel buds") || n.contains("echo buds") || n.contains("galaxy buds")
            || n.contains("earbuds") || n.contains("earphone") || n.contains("linkbuds")
            || n.contains("tone free") || n.contains("wf-1000") || n.contains("wf-c")
            || n.contains("tws") || n.contains("liberty") || n.contains("space a") {
            return .buds
        }

        // --- Headphones / Over-ear / Headsets ---
        if n.contains("headphone") || n.contains("headset")
            || n.contains("wh-1000") || n.contains("wh-ch") || n.contains("wh-xb")
            || n.contains("bose") || n.contains("beats") || n.contains("sennheiser")
            || n.contains("shure") || n.contains("audio-technica") || n.contains("arctis")
            || n.contains("hyperx") || n.contains("marshall") || n.contains("plantronics")
            || n.contains("poly") {
            return .headphones
        }
        if n.contains("sony") && !n.contains("xperia") {
            return .headphones
        }
        if n.contains("jbl") && !n.contains("flip") && !n.contains("charge") && !n.contains("go ") && !n.contains("clip") && !n.contains("pulse") {
            return .headphones
        }

        // --- Phones / Mobiles ---
        // Match explicit brand names, series, model numbers, and generic "phone" / "mobile"
        if n.contains("iphone")
            || (n.contains("phone") && !n.contains("headphone") && !n.contains("earphone"))
            || n.contains("mobile") || n.contains("cellphone") || n.contains("handset")
            // Infinix / Transsion
            || n.contains("infinix") || n.contains("tecno") || n.contains("itel")
            || n.contains("x68") || n.contains("x67") || n.contains("x65") || n.contains("x69") || n.contains("x60") || n.contains("x57")
            // Google
            || (n.contains("pixel") && !n.contains("watch") && !n.contains("tablet"))
            // Samsung
            || (n.contains("galaxy") && !n.contains("watch") && !n.contains("tab") && !n.contains("book"))
            || n.contains("sm-s") || n.contains("sm-g") || n.contains("sm-a") || n.contains("sm-f") || n.contains("sm-n") || n.contains("sm-m")
            // Xiaomi / Redmi / POCO / Black Shark
            || n.contains("redmi") || n.contains("poco") || n.contains("xiaomi") || n.contains("black shark")
            // BBK: OnePlus / OPPO / Vivo / Realme / iQOO
            || n.contains("oneplus") || n.contains("nord")
            || n.contains("oppo") || n.contains("find x") || n.contains("reno")
            || n.contains("vivo") || n.contains("iqoo") || n.contains("realme") || n.contains("narzo")
            // Motorola
            || n.contains("motorola") || n.contains("moto ")
            // Sony
            || n.contains("xperia")
            // Nothing / CMF
            || n.contains("nothing phone") || n.contains("cmf phone")
            // Asus
            || n.contains("zenfone") || n.contains("rog phone")
            // Huawei / Honor
            || n.contains("huawei") || n.contains("mate ") || n.contains("honor")
            || n.contains("pura") || n.contains("p30") || n.contains("p40") || n.contains("p50") || n.contains("p60")
            // ZTE / Nubia / RedMagic / Meizu / TCL / Nokia / Sharp
            || n.contains("nubia") || n.contains("redmagic") || n.contains("zte") || n.contains("blade")
            || n.contains("meizu") || n.contains("fairphone") || n.contains("alcatel") || n.contains("aquos") {
            return .phone
        }

        // --- Computers / Laptops ---
        if n.contains("macbook") || n.contains("thinkpad") || n.contains("surface")
            || n.contains("laptop") || n.contains("desktop") || n.contains("imac")
            || n.contains("mac mini") || n.contains("mac studio") || n.contains("mac pro")
            || n.contains("dell") || n.contains("hp ") || n.contains("lenovo")
            || n.contains("chromebook") || n.contains("galaxy book") || n.contains("alienware") {
            return .computer
        }

        // --- Tablets ---
        if n.contains("ipad") || n.contains("tablet") || n.contains("tab s") || n.contains("tab a")
            || n.contains("kindle") || n.contains("fire hd") {
            return .tablet
        }

        // --- Wearables / Watches ---
        if n.contains("watch") || n.contains("fitbit") || n.contains("garmin")
            || n.contains("amazfit") || n.contains("versa") || n.contains("sense")
            || n.contains("charge 5") || n.contains("charge 6") || n.contains("band ") {
            return .watch
        }

        // --- Tags / Trackers ---
        if n.contains("airtag") || n.contains("tile") || n.contains("chipolo")
            || n.contains("smarttag") || n.contains("smart tag") {
            return .tag
        }

        // --- Desk Peripherals ---
        if n.contains("mouse") || n.contains("mx master") || n.contains("magic mouse")
            || n.contains("m350") || n.contains("m650") || n.contains("g pro")
            || n.contains("deathadder") || n.contains("trackpad") {
            return .mouse
        }
        if n.contains("keyboard") || n.contains("mx keys") || n.contains("k380")
            || n.contains("k780") || n.contains("magic keyboard") || n.contains("keychron") {
            return .keyboard
        }

        // --- Speakers ---
        if n.contains("speaker") || n.contains("homepod") || n.contains("echo ")
            || n.contains("nest") || n.contains("sonos") || n.contains("flip")
            || n.contains("charge 4") || n.contains("go 3") || n.contains("soundbar")
            || n.contains("soundlink") || n.contains("megaboom") || n.contains("wonderboom") {
            return .speaker
        }
    }

    // 3. Unnamed / Privacy-protected devices: infer from Bluetooth packet signatures
    // Apple Continuity Protocol (Company ID 0x004C)
    if companyID == 0x004C {
        if let appleContinuityType {
            switch appleContinuityType {
            case 0x07: // Proximity Pairing (AirPods, AirPods Pro, Beats)
                return .buds
            case 0x0B: // Watch Nearby
                return .watch
            case 0x12: // Find My beacon (AirTag)
                return .tag
            case 0x10, 0x05: // Nearby Info (iPhone / iPad / Mac) or AirDrop
                return .phone
            default:
                break
            }
        }
    }

    // Transsion / Infinix / Tecno Company IDs
    if companyID == 0x0660 || companyID == 0x098A || companyID == 0x08A8 {
        return .phone
    }

    // Google Fast Pair service data (0xFE2C) without a name is almost universally TWS audio
    if hasFastPair {
        return .buds
    }

    return .unknown
}
