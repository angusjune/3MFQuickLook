import Foundation
import libxml2

/// Shared libxml2 DOM helpers for the small XML parts (OPC rels, slicer
/// configs). Model parts stream through the SAX parser instead.
enum LibXML {
    /// Parses `data` as XML and hands the document to `body`; nil when the
    /// data is not well-formed. The document is freed on return.
    static func withDocument<T>(_ data: Data, _ body: (xmlDocPtr) -> T?) -> T? {
        let doc: xmlDocPtr? = data.withUnsafeBytes { buffer in
            xmlReadMemory(
                buffer.bindMemory(to: CChar.self).baseAddress, Int32(buffer.count),
                nil, nil, Int32(XML_PARSE_NONET.rawValue))
        }
        guard let doc else { return nil }
        defer { xmlFreeDoc(doc) }
        return body(doc)
    }

    /// The element children of `node` with the given name.
    static func children(of node: xmlNodePtr, named name: String) -> [xmlNodePtr] {
        var result: [xmlNodePtr] = []
        var child = node.pointee.children
        while let current = child {
            if current.pointee.type == XML_ELEMENT_NODE,
               xmlStrEqual(current.pointee.name, name) != 0 {
                result.append(current)
            }
            child = current.pointee.next
        }
        return result
    }

    /// Reads an attribute's text without `xmlGetProp` — that would allocate
    /// and require `xmlFree`, a mutable libxml2 global Swift 6 rejects.
    static func attribute(of node: xmlNodePtr, named name: String) -> String? {
        guard let attribute = xmlHasProp(node, name),
              let text = attribute.pointee.children,
              let content = text.pointee.content
        else { return nil }
        return String(cString: content)
    }
}
