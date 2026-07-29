import Foundation
import ImageInfoKit
import TCPluginSDK

/// The content plugin: it answers with field *values*, never with anything
/// drawn. Those values become custom columns, searchable fields, and
/// Multi-Rename `[=field]` placeholders — sortable by the number behind
/// them, not by the text shown.
struct Runner {
    private let provider = ImagePropertiesProvider()
    private let input = FileHandle.standardInput
    private let output = FileHandle.standardOutput
    private var buffer = Data()

    mutating func run() async {
        while let frame = nextFrame() {
            guard let request = try? JSONDecoder().decode(PluginWire.Request.self, from: frame)
            else { continue }
            await handle(request)
        }
    }

    private mutating func nextFrame() -> Data? {
        guard let header = read(4), let length = try? PluginWire.frameLength(header) else {
            return nil
        }
        return read(length)
    }

    private mutating func read(_ count: Int) -> Data? {
        while buffer.count < count {
            let chunk = input.availableData
            if chunk.isEmpty { return nil }
            buffer.append(chunk)
        }
        defer { buffer.removeFirst(count) }
        return Data(buffer.prefix(count))
    }

    private func handle(_ request: PluginWire.Request) async {
        do {
            switch request.method {
            case PluginWire.Method.hello:
                try reply(request.id, PluginWire.Hello(
                    id: "com.tc4mac.sample.imageinfo",
                    displayName: "Image properties (sample)"))

            case PluginWire.Method.contentFields:
                try reply(request.id, PluginPayload.Fields(
                    fields: provider.fields().map {
                        PluginPayload.Field(
                            id: $0.id.rawValue, displayName: $0.displayName,
                            kind: $0.kind.rawValue)
                    }))

            case PluginWire.Method.contentValue:
                let ask: PluginPayload.FieldRequest = try decode(request)
                let value = try await provider.value(
                    of: FieldID(rawValue: ask.field), forFileAt: URL(filePath: ask.path))
                // A file with no value for a field is a blank cell, not an
                // error — most files are not images.
                guard let value else {
                    try send(PluginWire.Response(id: request.id))
                    return
                }
                try reply(request.id, FieldValueDTO(value))

            default:
                try fail(request.id, .notSupported(request.method))
            }
        } catch let error as PluginError {
            try? fail(request.id, error)
        } catch {
            try? fail(request.id, .failed("\(error)"))
        }
    }

    private func decode<T: Decodable>(_ request: PluginWire.Request) throws -> T {
        try JSONDecoder().decode(T.self, from: request.payload)
    }

    private func reply<T: Encodable>(_ id: Int, _ value: T) throws {
        try send(PluginWire.Response(id: id, payload: try JSONEncoder().encode(value)))
    }

    private func fail(_ id: Int, _ error: PluginError) throws {
        try send(PluginWire.Response(id: id, error: PluginWire.ErrorPayload(error)))
    }

    private func send(_ response: PluginWire.Response) throws {
        try output.write(contentsOf: PluginWire.frame(try JSONEncoder().encode(response)))
    }
}

await Task {
    var runner = Runner()
    await runner.run()
}.value
