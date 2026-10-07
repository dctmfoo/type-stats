// Prints the text Vision finds in a PNG, one line per text block.
// Usage: swift scripts/ocr.swift image.png
import Foundation
import Vision

guard CommandLine.arguments.count > 1 else { FileHandle.standardError.write(Data("usage: ocr.swift image.png\n".utf8)); exit(2) }
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
let handler = VNImageRequestHandler(url: URL(fileURLWithPath: CommandLine.arguments[1]))
try handler.perform([request])
for observation in request.results ?? [] {
    if let line = observation.topCandidates(1).first?.string { print(line) }
}
