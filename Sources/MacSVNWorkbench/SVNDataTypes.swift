import Foundation

public struct BlameLine: Identifiable, Hashable {
    public let lineNumber: Int
    public let revision: Int64
    public let author: String?
    public let date: Date?
    public let content: String

    public var id: Int { lineNumber }
}

public struct SVNPropertyEntry: Identifiable, Hashable {
    public let name: String
    public let value: String

    public var id: String { name }
}

enum BlameXMLParser {
    static func parse(_ xml: String) -> [BlameLine] {
        let parser = BlameXMLParserDelegate()
        let xmlParser = XMLParser(data: Data(xml.utf8))
        xmlParser.delegate = parser
        xmlParser.parse()
        return parser.lines
    }
}

private final class BlameXMLParserDelegate: NSObject, XMLParserDelegate {
    var lines: [BlameLine] = []
    private var currentLineNumber = 0
    private var currentRevision: Int64 = 0
    private var currentAuthor: String?
    private var currentDate: Date?
    private var currentElement = ""
    private var currentText = ""
    private var inEntry = false

    private static var dateFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        currentElement = elementName
        currentText = ""
        if elementName == "entry" {
            inEntry = true
            currentLineNumber = Int(attributes["line-number"] ?? "0") ?? 0
            currentRevision = 0
            currentAuthor = nil
            currentDate = nil
        } else if elementName == "commit" {
            currentRevision = Int64(attributes["revision"] ?? "0") ?? 0
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if inEntry {
            switch elementName {
            case "author":
                currentAuthor = trimmed
            case "date":
                currentDate = Self.dateFormatter.date(from: trimmed)
            case "entry":
                lines.append(BlameLine(
                    lineNumber: currentLineNumber,
                    revision: currentRevision,
                    author: currentAuthor,
                    date: currentDate,
                    content: ""
                ))
                inEntry = false
            default:
                break
            }
        }
    }
}

enum SVNPropertyXMLParser {
    static func parse(_ xml: String) -> [SVNPropertyEntry] {
        let parser = PropertyXMLParserDelegate()
        let xmlParser = XMLParser(data: Data(xml.utf8))
        xmlParser.delegate = parser
        xmlParser.parse()
        return parser.properties
    }
}

private final class PropertyXMLParserDelegate: NSObject, XMLParserDelegate {
    var properties: [SVNPropertyEntry] = []
    private var currentName: String?
    private var currentText = ""
    private var inProperty = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        currentText = ""
        if elementName == "property" {
            inProperty = true
            currentName = attributes["name"]
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        if elementName == "property", inProperty, let name = currentName {
            properties.append(SVNPropertyEntry(name: name, value: currentText))
            inProperty = false
            currentName = nil
        }
    }
}
