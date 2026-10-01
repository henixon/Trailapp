import Foundation

/// A named route point from a GPX <rte> segment, used as a turn cue.
public struct GPXRoutePoint {
    public var point: RoutePoint
    public var name: String?
    public var comment: String?

    public init(point: RoutePoint, name: String? = nil, comment: String? = nil) {
        self.point = point
        self.name = name
        self.comment = comment
    }
}

public struct ParsedGPX {
    public var name: String?
    public var trackPoints: [RoutePoint] = []
    public var routePoints: [GPXRoutePoint] = []
    public var waypoints: [RoutePoint] = []
}

public enum GPXError: Error, LocalizedError {
    case parseFailed(String)
    case noUsablePoints

    public var errorDescription: String? {
        switch self {
        case .parseFailed(let detail): return "Could not parse GPX file: \(detail)"
        case .noUsablePoints: return "GPX file contains no track or route points."
        }
    }
}

/// Minimal GPX 1.0/1.1 parser. Handles <trk>/<trkseg>/<trkpt>, <rte>/<rtept>
/// (names become turn cues), and <wpt>. Namespace prefixes are tolerated.
public enum GPXParser {
    public static func parse(data: Data) throws -> ParsedGPX {
        let delegate = ParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() else {
            throw GPXError.parseFailed(parser.parserError?.localizedDescription ?? "unknown error")
        }
        let parsed = delegate.result
        guard !parsed.trackPoints.isEmpty || !parsed.routePoints.isEmpty else {
            throw GPXError.noUsablePoints
        }
        return parsed
    }

    public static func parse(url: URL) throws -> ParsedGPX {
        try parse(data: Data(contentsOf: url))
    }
}

// MARK: - Private delegate

private struct PointBuilder {
    var latitude: Double
    var longitude: Double
    var elevation: Double?
    var timestamp: Date?
    var name: String?
    var comment: String?

    func build() -> RoutePoint {
        RoutePoint(latitude: latitude, longitude: longitude, elevation: elevation, timestamp: timestamp)
    }
}

private final class ParserDelegate: NSObject, XMLParserDelegate {
    var result = ParsedGPX()

    private var stack: [String] = []
    private var text = ""
    private var builder: PointBuilder?
    private var inTrack = false
    private var inRoute = false

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterNoFraction: ISO8601DateFormatter = {
        ISO8601DateFormatter()
    }()

    /// Strips any namespace prefix ("gpx:trkpt" -> "trkpt").
    private func local(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = local(elementName)
        stack.append(name)
        text = ""
        switch name {
        case "trk":
            inTrack = true
        case "rte":
            inRoute = true
        case "trkpt", "rtept", "wpt":
            if let lat = attributeDict["lat"].flatMap(Double.init),
               let lon = attributeDict["lon"].flatMap(Double.init) {
                builder = PointBuilder(latitude: lat, longitude: lon)
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = local(elementName)
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            text = ""
            _ = stack.popLast()
        }

        switch name {
        case "ele":
            builder?.elevation = Double(value)
        case "time":
            builder?.timestamp = Self.isoFormatter.date(from: value)
                ?? Self.isoFormatterNoFraction.date(from: value)
        case "name":
            if builder != nil {
                builder?.name = value.isEmpty ? nil : value
            } else if inTrack, !inRoute {
                result.name = value.isEmpty ? nil : value
            }
        case "cmt", "desc":
            if builder != nil, !value.isEmpty {
                builder?.comment = value
            }
        case "trkpt":
            if let b = builder { result.trackPoints.append(b.build()) }
            builder = nil
        case "rtept":
            if let b = builder {
                result.routePoints.append(GPXRoutePoint(
                    point: b.build(), name: b.name, comment: b.comment))
            }
            builder = nil
        case "wpt":
            if let b = builder { result.waypoints.append(b.build()) }
            builder = nil
        case "trk":
            inTrack = false
        case "rte":
            inRoute = false
        default:
            break
        }
    }
}
