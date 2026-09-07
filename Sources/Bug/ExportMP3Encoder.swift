import Darwin
import Foundation

/// LAME's normalized IEEE float API avoids truncating 24-bit source audio to 16 bits.
final class ExportMP3Encoder {
    typealias Init = @convention(c) () -> OpaquePointer?
    typealias Unary = @convention(c) (OpaquePointer) -> Int32
    typealias Setter = @convention(c) (OpaquePointer, Int32) -> Int32
    typealias Encode = @convention(c) (OpaquePointer, UnsafePointer<Float>, Int32, UnsafeMutablePointer<UInt8>, Int32) -> Int32
    typealias Flush = @convention(c) (OpaquePointer, UnsafeMutablePointer<UInt8>, Int32) -> Int32
    private let library: UnsafeMutableRawPointer
    private let state: OpaquePointer
    private let close: Unary
    private let encodeFunction: Encode
    private let flush: Flush
    private var bytes = [UInt8](repeating: 0, count: 32_768)

    init(url: URL?) throws {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/libmp3lame.dylib")
        let path = (url ?? bundled).path
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            throw AudioExportError.encoder("Unavailable. Bundle libmp3lame.dylib in Contents/Frameworks using scripts/prepare-encoder.sh.")
        }
        func symbol<T>(_ name: String, _: T.Type) throws -> T {
            guard let address = dlsym(handle, name) else { throw AudioExportError.encoder("Missing symbol \(name).") }
            return unsafeBitCast(address, to: T.self)
        }
        var allocated: OpaquePointer?
        var cleanup: Unary?
        do {
            let initialize = try symbol("lame_init", Init.self)
            let closer = try symbol("lame_close", Unary.self)
            cleanup = closer
            guard let context = initialize() else { throw AudioExportError.encoder("Could not allocate encoder.") }
            allocated = context
            for (name, value): (String, Int32) in [
                ("lame_set_in_samplerate", 48_000), ("lame_set_out_samplerate", 48_000),
                ("lame_set_num_channels", 2), ("lame_set_brate", 320), ("lame_set_VBR", 0),
                ("lame_set_quality", 2), ("lame_set_mode", 1),
                // No placeholder Xing header: plain CBR stream with standard encoder delay/padding.
                ("lame_set_bWriteVbrTag", 0)
            ] {
                guard try symbol(name, Setter.self)(context, value) >= 0 else { throw AudioExportError.encoder("Invalid setting \(name).") }
            }
            guard try symbol("lame_init_params", Unary.self)(context) >= 0 else { throw AudioExportError.encoder("Initialization failed.") }
            encodeFunction = try symbol("lame_encode_buffer_interleaved_ieee_float", Encode.self)
            flush = try symbol("lame_encode_flush", Flush.self)
            library = handle
            state = context
            close = closer
        } catch {
            if let allocated, let cleanup { _ = cleanup(allocated) }
            dlclose(handle)
            throw error
        }
    }

    deinit { _ = close(state); dlclose(library) }

    func encode(_ samples: [Float]) throws -> Data {
        let capacity = Int32(bytes.count)
        let count = samples.withUnsafeBufferPointer { input in
            bytes.withUnsafeMutableBufferPointer { output in
                encodeFunction(state, input.baseAddress!, Int32(samples.count / 2), output.baseAddress!, capacity)
            }
        }
        guard count >= 0 else { throw AudioExportError.encoder("Encoding failed (\(count)).") }
        return Data(bytes.prefix(Int(count)))
    }

    func finish() throws -> Data {
        let capacity = Int32(bytes.count)
        let count = bytes.withUnsafeMutableBufferPointer { flush(state, $0.baseAddress!, capacity) }
        guard count >= 0 else { throw AudioExportError.encoder("Finalization failed (\(count)).") }
        return Data(bytes.prefix(Int(count)))
    }
}
