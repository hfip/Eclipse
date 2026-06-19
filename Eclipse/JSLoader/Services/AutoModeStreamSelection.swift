//
//  AutoModeStreamSelection.swift
//  Eclipse
//
//  Shared, pure stream-quality scoring used by Auto Mode selection. The logic mirrors the
//  scoring originally implemented privately in ServicesResultsSheet so that background
//  features (e.g. next-episode warmup pre-resolution) pick the SAME stream the real playback
//  flow would — which is what makes the warmup cache actually hit.
//
//  Keep this in sync with the equivalent scoring in ServicesResultsSheet. These functions are
//  pure (no UI / no state) and safe to call from any thread.
//

import Foundation

enum AutoModeStreamSelection {
    struct StreamQualityInfo {
        let resolutionHeight: Int?
        let sizeMB: Double?
        let sourceScore: Double
        let featureScore: Double
    }

    static func streamQualityInfo(from label: String) -> StreamQualityInfo {
        let lower = label.lowercased()
        let resolutionHeight: Int?
        if lower.contains("2160") || lower.contains("4k") || lower.contains("uhd") {
            resolutionHeight = 2160
        } else if lower.contains("1440") {
            resolutionHeight = 1440
        } else if lower.contains("1080") {
            resolutionHeight = 1080
        } else if lower.contains("720") {
            resolutionHeight = 720
        } else if lower.contains("480") {
            resolutionHeight = 480
        } else if lower.contains("360") {
            resolutionHeight = 360
        } else {
            resolutionHeight = nil
        }

        let sizeMB = largestFileSizeMB(in: label)

        let sourceScore: Double
        if lower.contains("remux") {
            sourceScore = 9
        } else if lower.contains("bluray") || lower.contains("blu-ray") || lower.contains("bdrip") || lower.contains("brrip") {
            sourceScore = 8
        } else if lower.contains("web-dl") || lower.contains("webdl") {
            sourceScore = 7
        } else if lower.contains("webrip") || lower.contains(" web ") || lower.contains(".web.") {
            sourceScore = 6
        } else if lower.contains("hdtv") || lower.contains("hdrip") {
            sourceScore = 5
        } else if lower.contains("dvdrip") || lower.contains("dvd") {
            sourceScore = 4
        } else if lower.contains("cam") || lower.contains("hdcam") || lower.contains(" telesync") || lower.contains(" ts ") {
            sourceScore = 1
        } else {
            sourceScore = 3
        }

        var featureScore = 0.0
        if lower.contains("cached") || lower.contains("cache") { featureScore += 0.4 }
        if lower.contains("hdr") || lower.contains("dolby vision") || lower.contains(" dv ") { featureScore += 0.2 }
        if lower.contains("hevc") || lower.contains("x265") || lower.contains("h265") || lower.contains("h.265") { featureScore += 0.1 }

        return StreamQualityInfo(
            resolutionHeight: resolutionHeight,
            sizeMB: sizeMB,
            sourceScore: sourceScore,
            featureScore: featureScore
        )
    }

    static func largestFileSizeMB(in label: String) -> Double? {
        let pattern = #"(\d+(?:\.\d+)?)\s*(gb|gib|mb|mib)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsRange = NSRange(label.startIndex..<label.endIndex, in: label)
        let matches = regex.matches(in: label, range: nsRange)
        let sizes = matches.compactMap { match -> Double? in
            guard let valueRange = Range(match.range(at: 1), in: label),
                  let unitRange = Range(match.range(at: 2), in: label),
                  let value = Double(String(label[valueRange])) else {
                return nil
            }
            let unit = label[unitRange].lowercased()
            return unit.hasPrefix("g") ? value * 1024 : value
        }
        return sizes.max()
    }

    static func streamPreferenceScore(label: String, preference: AutoModeQualityPreference, index: Int) -> Double {
        let info = streamQualityInfo(from: label)
        let earlierTieBreak = -Double(index) * 0.001
        let sizeScore = min(info.sizeMB ?? 0, 80_000) / 10_000
        let qualityBonus = info.sourceScore + info.featureScore + sizeScore + earlierTieBreak

        switch preference {
        case .manual:
            return qualityBonus
        case .auto, .highest:
            return Double(info.resolutionHeight ?? 0) * 10 + qualityBonus
        case .lowest:
            let resolution = info.resolutionHeight ?? 10_000
            return -Double(resolution) + (qualityBonus * 0.1)
        case .quality2160, .quality1080, .quality720, .quality480:
            guard let target = preference.targetResolutionHeight else {
                return qualityBonus
            }
            guard let resolution = info.resolutionHeight else {
                return -10_000 + qualityBonus
            }
            if resolution == target {
                return 20_000 + qualityBonus
            }
            if resolution < target {
                return 10_000 - Double(target - resolution) + qualityBonus
            }
            return 8_000 - Double(resolution - target) + qualityBonus
        }
    }

    static func streamLabelHasDetectedQuality(_ label: String) -> Bool {
        streamQualityInfo(from: label).resolutionHeight != nil
    }

    /// Mirrors `ServicesResultsSheet.bestPluginStream`. Returns nil unless Auto Quality is on
    /// and at least one stream exposes a detectable resolution (matching the real flow, which
    /// otherwise shows a manual picker).
    static func bestPluginStream(from streams: [NuvioPluginStream]) -> NuvioPluginStream? {
        guard !streams.isEmpty else { return nil }
        guard AutoModeQualityPreference.current.usesAutomaticSelection else { return nil }
        guard streams.contains(where: { streamLabelHasDetectedQuality($0.qualitySearchLabel) }) else { return nil }
        return streams.enumerated().max(by: { lhs, rhs in
            let lhsScore = streamPreferenceScore(label: lhs.element.qualitySearchLabel, preference: AutoModeQualityPreference.current, index: lhs.offset)
            let rhsScore = streamPreferenceScore(label: rhs.element.qualitySearchLabel, preference: AutoModeQualityPreference.current, index: rhs.offset)
            if lhsScore == rhsScore {
                return lhs.offset > rhs.offset
            }
            return lhsScore < rhsScore
        })?.element
    }

    // MARK: - Stremio

    /// Mirrors `ServicesResultsSheet.bestStremioStream`. Returns nil unless Auto Quality is on and
    /// at least one stream exposes a detectable resolution (matching the real flow, which otherwise
    /// shows a manual picker). NOTE: unlike plugins, a single label-less Stremio stream is NOT
    /// auto-selected — the real auto flow returns nil for that addon too, so warmup stays in sync.
    static func bestStremioStream(from streams: [StremioStream]) -> StremioStream? {
        guard !streams.isEmpty else { return nil }
        guard AutoModeQualityPreference.current.usesAutomaticSelection else {
            return nil
        }
        guard streams.contains(where: { streamLabelHasDetectedQuality(smartPlayerMetadata(for: $0)) }) else {
            return nil
        }
        return streams.enumerated().max(by: { lhs, rhs in
            let lhsLabel = smartPlayerMetadata(for: lhs.element)
            let rhsLabel = smartPlayerMetadata(for: rhs.element)
            let lhsScore = streamPreferenceScore(label: lhsLabel, preference: AutoModeQualityPreference.current, index: lhs.offset)
                + legacyStremioStreamScore(lhs.element)
            let rhsScore = streamPreferenceScore(label: rhsLabel, preference: AutoModeQualityPreference.current, index: rhs.offset)
                + legacyStremioStreamScore(rhs.element)
            if lhsScore == rhsScore {
                return lhs.offset > rhs.offset
            }
            return lhsScore < rhsScore
        })?.element
    }

    static func legacyStremioStreamScore(_ stream: StremioStream) -> Double {
        let shortDescription = stream.description.map { String($0.prefix(120)) }
        let label = [stream.displayName, shortDescription, stream.behaviorHints?.filename]
            .compactMap { $0 }
            .joined(separator: " ")
        let lower = label.lowercased()

        // Stremio addon lookups are already ID-based, so Auto Mode should rank
        // streams by quality/usefulness instead of title similarity.
        var score = 1.0

        if lower.contains("cached") || lower.contains("cache") {
            score += 0.12
        }

        if lower.contains("2160") || lower.contains("4k") {
            score += 0.08
        } else if lower.contains("1080") {
            score += 0.06
        } else if lower.contains("720") {
            score += 0.04
        }

        if lower.contains("hdr") {
            score += 0.02
        }

        if lower.contains("remux") {
            score += 0.02
        }

        if stream.isDirectHTTP {
            score += 0.01
        }

        return score
    }

    static func smartPlayerMetadata(for stream: StremioStream) -> String {
        [
            stream.name,
            stream.title,
            stream.description,
            stream.behaviorHints?.filename,
            stream.formattedVideoSize,
            stremioStreamLabel(for: stream)
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    static func stremioStreamLabel(for stream: StremioStream) -> String {
        var parts: [String] = []
        if let name = stream.name, !name.isEmpty { parts.append(name) }

        // Parse quality info from title lines (Torrentio/Comet format)
        if let title = stream.title, !title.isEmpty {
            let lines = title.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let qualityTags = extractQualityTags(from: lines)
            if !qualityTags.isEmpty {
                parts.append(qualityTags)
            } else if let firstLine = lines.first, firstLine != stream.name {
                parts.append(firstLine)
            }
        }
        if let languageLabel = stremioLanguageLabel(for: stream),
           !stremioLanguageLabel(languageLabel, isAlreadyIncludedIn: parts) {
            parts.append(languageLabel)
        }
        let hasDisplayedSize = parts.joined(separator: " ").range(
            of: #"\d+(?:\.\d+)?\s*(?:KB|MB|GB|TB)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        if !hasDisplayedSize, let size = stream.formattedVideoSize {
            parts.append(size)
        }

        return parts.isEmpty ? "Stream" : parts.joined(separator: " · ")
    }

    static func stremioLanguageLabel(for stream: StremioStream) -> String? {
        let metadata = [
            stream.name,
            stream.title,
            stream.description,
            stream.behaviorHints?.filename
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

        var languages = stream.languageHints
            .flatMap(splitStremioLanguageHint)
            .compactMap(normalizedStremioLanguageName)
        languages.append(contentsOf: detectedStremioLanguageNames(in: metadata.joined(separator: " ")))

        var seen = Set<String>()
        let uniqueLanguages = languages.filter { seen.insert($0).inserted }
        if uniqueLanguages.contains("Multi Audio") || uniqueLanguages.count > 3 {
            return "Multi Audio"
        }

        let namedLanguages = uniqueLanguages.filter { $0 != "Dual Audio" }
        if !namedLanguages.isEmpty {
            return namedLanguages.joined(separator: "/")
        }

        let metadataText = metadata.joined(separator: " ")
        if containsStremioLanguageMarker("multi audio", in: metadataText)
            || containsStremioLanguageMarker("multi-language", in: metadataText)
            || containsStremioLanguageMarker("multilang", in: metadataText) {
            return "Multi Audio"
        }
        if uniqueLanguages.contains("Dual Audio")
            || containsStremioLanguageMarker("dual audio", in: metadataText) {
            return "Dual Audio"
        }
        return nil
    }

    static func splitStremioLanguageHint(_ value: String) -> [String] {
        value.components(separatedBy: CharacterSet(charactersIn: ",/|;+"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func normalizedStremioLanguageName(_ value: String) -> String? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "dual", "dual audio", "dual-audio": return "Dual Audio"
        case "multi", "multi audio", "multi-audio", "multilang", "multi-language": return "Multi Audio"
        case "eng", "en", "english": return "English"
        case "jpn", "ja", "jp", "japanese": return "Japanese"
        case "hin", "hi", "hindi": return "Hindi"
        case "kor", "ko", "korean": return "Korean"
        case "chi", "zho", "zh", "chinese", "mandarin", "cantonese": return "Chinese"
        case "spa", "es", "esp", "spanish": return "Spanish"
        case "lat", "latin", "latino": return "Latino"
        case "fre", "fra", "fr", "french": return "French"
        case "ger", "deu", "de", "german": return "German"
        case "ita", "it", "italian": return "Italian"
        case "por", "pt", "portuguese": return "Portuguese"
        case "rus", "ru", "russian": return "Russian"
        case "ara", "ar", "arabic": return "Arabic"
        case "tam", "ta", "tamil": return "Tamil"
        case "tel", "te", "telugu": return "Telugu"
        case "ben", "bn", "bengali": return "Bengali"
        case "mal", "ml", "malayalam": return "Malayalam"
        case "kan", "kn", "kannada": return "Kannada"
        case "mar", "mr", "marathi": return "Marathi"
        case "tur", "tr", "turkish": return "Turkish"
        case "pol", "pl", "polish": return "Polish"
        case "dut", "nld", "nl", "dutch": return "Dutch"
        case "ind", "id", "indonesian": return "Indonesian"
        case "tha", "th", "thai": return "Thai"
        case "vie", "vi", "vietnamese": return "Vietnamese"
        case "ukr", "uk", "ukrainian": return "Ukrainian"
        default: return nil
        }
    }

    static func detectedStremioLanguageNames(in value: String) -> [String] {
        let languages: [(name: String, markers: [String])] = [
            ("English", ["english", "eng"]),
            ("Japanese", ["japanese", "jpn"]),
            ("Hindi", ["hindi", "hin"]),
            ("Korean", ["korean", "kor"]),
            ("Chinese", ["chinese", "mandarin", "cantonese", "zho", "chi"]),
            ("Spanish", ["spanish", "spa"]),
            ("Latino", ["latino", "latin", "lat"]),
            ("French", ["french", "fra", "fre"]),
            ("German", ["german", "deu", "ger"]),
            ("Italian", ["italian", "ita"]),
            ("Portuguese", ["portuguese", "por"]),
            ("Russian", ["russian", "rus"]),
            ("Arabic", ["arabic", "ara"]),
            ("Tamil", ["tamil", "tam"]),
            ("Telugu", ["telugu", "tel"]),
            ("Bengali", ["bengali", "ben"]),
            ("Malayalam", ["malayalam", "mal"]),
            ("Kannada", ["kannada", "kan"]),
            ("Marathi", ["marathi", "mar"]),
            ("Turkish", ["turkish", "tur"]),
            ("Polish", ["polish", "pol"]),
            ("Dutch", ["dutch", "nld", "dut"]),
            ("Indonesian", ["indonesian", "ind"]),
            ("Thai", ["thai", "tha"]),
            ("Vietnamese", ["vietnamese", "vie"]),
            ("Ukrainian", ["ukrainian", "ukr"])
        ]

        return languages.compactMap { language in
            language.markers.contains { containsStremioLanguageMarker($0, in: value) }
                ? language.name
                : nil
        }
    }

    static func containsStremioLanguageMarker(_ marker: String, in value: String) -> Bool {
        let escapedMarker = NSRegularExpression.escapedPattern(for: marker)
        return value.range(
            of: "(?i)(^|[^a-z])\(escapedMarker)([^a-z]|$)",
            options: .regularExpression
        ) != nil
    }

    static func stremioLanguageLabel(_ languageLabel: String, isAlreadyIncludedIn parts: [String]) -> Bool {
        let displayedText = parts.joined(separator: " ")
        if displayedText.range(of: languageLabel, options: .caseInsensitive) != nil {
            return true
        }

        let displayedLanguages = Set(detectedStremioLanguageNames(in: displayedText))
        let expectedLanguages = languageLabel.components(separatedBy: "/")
        return !expectedLanguages.isEmpty && expectedLanguages.allSatisfy(displayedLanguages.contains)
    }

    static func extractQualityTags(from lines: [String]) -> String {
        let resolutionPatterns = ["4k", "2160p", "1080p", "720p", "480p", "360p"]
        let qualityPatterns = ["bluray", "blu-ray", "bdrip", "brrip", "dvdrip", "dvd", "webrip", "web-dl", "webdl", "web", "hdtv", "hdrip", "cam", "ts", "hdcam", "remux"]
        let codecPatterns = ["hevc", "h265", "h.265", "x265", "h264", "h.264", "x264", "av1", "vp9", "xvid"]
        let hdrPatterns = ["hdr10+", "hdr10", "hdr", "dolby vision", "dv", "sdr"]
        let audioPatterns = ["atmos", "truehd", "dts-hd", "dts", "dd5.1", "dd+", "aac", "5.1", "7.1"]

        var tags: [String] = []
        let allText = lines.joined(separator: " ").lowercased()

        // Resolution
        for pattern in resolutionPatterns {
            if allText.contains(pattern) {
                tags.append(pattern == "4k" ? "4K" : pattern.uppercased())
                break
            }
        }

        // Source quality
        for pattern in qualityPatterns {
            if allText.contains(pattern) {
                let display: String
                switch pattern {
                case "bluray", "blu-ray": display = "BluRay"
                case "bdrip": display = "BDRip"
                case "brrip": display = "BRRip"
                case "dvdrip": display = "DVDRip"
                case "dvd": display = "DVD"
                case "webrip": display = "WEBRip"
                case "web-dl", "webdl": display = "WEB-DL"
                case "web": display = "WEB"
                case "hdtv": display = "HDTV"
                case "hdrip": display = "HDRip"
                case "cam": display = "CAM"
                case "ts": display = "TS"
                case "hdcam": display = "HDCAM"
                case "remux": display = "Remux"
                default: display = pattern.uppercased()
                }
                tags.append(display)
                break
            }
        }

        // Codec
        for pattern in codecPatterns {
            if allText.contains(pattern) {
                let display: String
                switch pattern {
                case "hevc", "h265", "h.265", "x265": display = "HEVC"
                case "h264", "h.264", "x264": display = "H.264"
                case "av1": display = "AV1"
                default: display = pattern.uppercased()
                }
                tags.append(display)
                break
            }
        }

        // HDR
        for pattern in hdrPatterns {
            if allText.contains(pattern) {
                let display: String
                switch pattern {
                case "hdr10+": display = "HDR10+"
                case "hdr10": display = "HDR10"
                case "hdr": display = "HDR"
                case "dolby vision", "dv": display = "DV"
                default: display = pattern.uppercased()
                }
                tags.append(display)
                break
            }
        }

        // Audio
        for pattern in audioPatterns {
            if allText.contains(pattern) {
                let display: String
                switch pattern {
                case "atmos": display = "Atmos"
                case "truehd": display = "TrueHD"
                case "dts-hd": display = "DTS-HD"
                case "dts": display = "DTS"
                case "dd5.1": display = "DD5.1"
                case "dd+": display = "DD+"
                default: display = pattern
                }
                tags.append(display)
                break
            }
        }

        // File size (look for patterns like "2.5 GB", "800 MB")
        let sizeRegex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?\s*(?:GB|MB|gb|mb))"#)
        if let match = sizeRegex?.firstMatch(in: lines.joined(separator: " "), range: NSRange(location: 0, length: lines.joined(separator: " ").utf16.count)) {
            if let range = Range(match.range(at: 1), in: lines.joined(separator: " ")) {
                tags.append(String(lines.joined(separator: " ")[range]))
            }
        }

        return tags.joined(separator: " · ")
    }
}
