import SeamtypeCore
import Foundation

// Usage:
//   seamtype-cli "dkssudgktpdy rmfjgek hello world"   convert arguments
//   seamtype-cli -v "..."                              also print per-word scores
//   echo "..." | seamtype-cli                          convert stdin line by line
//   seamtype-cli --compose < keys.txt                  print "keys<TAB>hangul" per line
//   seamtype-cli --decide < keys_prev.tsv              heuristic verdict for "keys<TAB>previous" lines
//   seamtype-cli --type [--japanese] < keys.txt        "keys<TAB>text" after typing keys + Space into a session

var args = Array(CommandLine.arguments.dropFirst())

switch args.first {
case "--compose":
    while let keys = readLine() {
        print("\(keys)\t\(HangulComposer.compose(keys: keys)?.text ?? keys)")
    }
    exit(0)
case "--convert":
    // kana per line → top candidates (SEAMTYPE_ENGINE=apple for macOS's engine, else AzooKey)
    MainActor.assumeIsolated {
        let apple = ProcessInfo.processInfo.environment["SEAMTYPE_ENGINE"] == "apple"
        guard let converter: JapaneseConverter = apple ? AppleJapaneseConverter(learning: nil) : AzooKeyConverter() else {
            print("no Japanese converter"); exit(1)
        }
        while let kana = readLine() {
            let start = Date()
            let candidates = converter.candidates(for: kana)
            let ms = Date().timeIntervalSince(start) * 1000
            print("\(kana) [\(String(format: "%.0f", ms))ms]: " + candidates.prefix(8).map { "\($0.text)(\($0.kanaCount))" }.joined(separator: " "))
        }
    }
    exit(0)
case "--convert-all":
    // kana per line → all whole-reading candidates, tab-separated (conversion eval)
    MainActor.assumeIsolated {
        // Fresh, learning-free memory so evaluation isn't affected by earlier runs.
        let memory = FileManager.default.temporaryDirectory.appendingPathComponent("seamtype-eval-\(UUID().uuidString)")
        let nBest = ProcessInfo.processInfo.environment["SEAMTYPE_NBEST"].flatMap(Int.init) ?? 20
        let weight = args.count > 1 ? Double(args[1]) : 1.0 // optional: --convert-all <rerank weight | none>
        let converter: JapaneseConverter
        if ProcessInfo.processInfo.environment["SEAMTYPE_ENGINE"] == "apple" {
            guard let apple = AppleJapaneseConverter(learning: nil) else { print("macOS's engine not available"); exit(1) }
            apple.rerankWeight = weight
            converter = apple
        } else {
            guard let azooKey = AzooKeyConverter(memory: memory, nBest: nBest) else { print("no Japanese dictionary found"); exit(1) }
            azooKey.rerankWeight = weight
            converter = azooKey
        }
        while let kana = readLine() {
            let full = converter.candidates(for: kana).filter { $0.kanaCount == kana.count && !$0.isPrediction }
            print(full.map(\.text).joined(separator: "\t"))
        }
    }
    exit(0)
case "--kana":
    // romaji per line → "hiragana<TAB>stray letters"
    while let romaji = readLine() {
        let r = RomajiComposer.compose(romaji)
        print("\(r.text)\t\(r.strayLetters)")
    }
    exit(0)
case "--decide":
    // Optional: --decide --japanese [offset]
    let withJapanese = args.count > 1 && args[1] == "--japanese"
    // Experiments: SEAMTYPE_KO_SOURCE=tiers|corpus|max, SEAMTYPE_KO_OFFSET=<double>
    let env = ProcessInfo.processInfo.environment
    let korean = env["SEAMTYPE_KO_SOURCE"].flatMap(KoreanModel.Source.init(rawValue:)).map(KoreanModel.init(source:)) ?? KoreanModel()
    let heuristic = HeuristicEngine(korean: korean,
                                    japanese: withJapanese ? JapaneseModel.shared : nil)
    if let offset = env["SEAMTYPE_KO_OFFSET"].flatMap(Double.init) { heuristic.koreanOffset = offset }
    if let bias = env["SEAMTYPE_JA_CONTEXT"].flatMap(Double.init) { heuristic.japaneseContextBias = bias }
    if let bias = env["SEAMTYPE_CONTEXT"].flatMap(Double.init) { heuristic.contextBias = bias }
    if let factor = env["SEAMTYPE_SWITCH"].flatMap(Double.init) { heuristic.switchBiasFactor = factor }
    if let penalty = env["SEAMTYPE_RARE"].flatMap(Double.init) { heuristic.rareWordFloorPenalty = penalty }
    if let floors = env["SEAMTYPE_KO_FLOOR"]?.split(separator: ",").compactMap({ Double($0) }), floors.count == 2 {
        heuristic.koreanKnownFloor = (floors[0], floors[1])
    }
    if withJapanese, args.count > 2, let offset = Double(args[2]) { heuristic.japaneseOffset = offset }
    let engine = SplittingEngine(base: heuristic, english: heuristic.english, japanese: heuristic.segmenter)
    // SEAMTYPE_TIMING=1: also time the preview decision (every keystroke) and the final one
    // (once, at Space/Return) per line.
    let timing = env["SEAMTYPE_TIMING"] != nil
    var times: [Double] = [], finals: [Double] = []
    while let line = readLine() {
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        let previous = fields.count > 1 ? Language(rawValue: fields[1]) : nil
        var start = DispatchTime.now().uptimeNanoseconds
        if timing {
            _ = engine.decide(fields[0], context: DecisionContext(previousLanguage: previous, partial: true))
            times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
            start = DispatchTime.now().uptimeNanoseconds
        }
        let d = engine.decide(fields[0], context: DecisionContext(previousLanguage: previous))
        if timing { finals.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6) }
        print("\(fields[0])\t\(d.language.rawValue)\t\(String(format: "%.4f", d.confidence))\t\(d.output)\t\(d.explanation)\t\(d.runnerUp?.rawValue ?? "")"
              + (timing ? String(format: "\t%.2fms\t%.2fms", times.last!, finals.last!) : ""))
    }
    if timing, times.count > 1 {
        times.removeFirst() // the first line also loads the models
        finals.removeFirst()
        FileHandle.standardError.write(String(format: "keystroke avg %.2f max %.2f ms; final avg %.2f max %.2f ms\n",
                                              times.reduce(0, +) / Double(times.count), times.max()!,
                                              finals.reduce(0, +) / Double(finals.count), finals.max()!).data(using: .utf8)!)
    }
    exit(0)
case "--type":
    // Each line's keys and a Space through a fresh InputSession (real engines, no converter):
    // what ends up in the field, as typed. SEAMTYPE_THRESHOLD=0.97: as in a Strict app.
    let withJapanese = args.count > 1 && args[1] == "--japanese"
    let heuristic = HeuristicEngine(japanese: withJapanese ? JapaneseModel.shared : nil)
    let threshold = ProcessInfo.processInfo.environment["SEAMTYPE_THRESHOLD"].flatMap(Double.init)
    let policies = AppPolicies(overrides: threshold.map { ["*": AppPolicy.Override(conversionThreshold: $0)] } ?? [:])
    MainActor.assumeIsolated {
        let engine = LearningEngine(base: SplittingEngine(base: heuristic, english: heuristic.english, japanese: heuristic.segmenter),
                                    storeURL: FileManager.default.temporaryDirectory.appendingPathComponent("seamtype-type-\(UUID().uuidString).json"))
        while let keys = readLine() {
            let field = PlainTextField()
            let session = InputSession(engine: engine, policies: policies, japaneseEnabled: withJapanese)
            for ch in keys + " " {
                let handled = ch.isLetter ? session.handle(.letter(ch), client: field) : session.handle(.printable(ch), client: field)
                if !handled { field.insertText(String(ch), replacing: nil) } // the app types keys passed on
            }
            print("\(keys)\t\(field.text)")
        }
    }
    exit(0)
default:
    break
}

let verbose = args.first == "-v"
if verbose { args.removeFirst() }

let heuristic = HeuristicEngine()
let converter = TextConverter(engine: SplittingEngine(base: heuristic, english: heuristic.english, japanese: heuristic.segmenter))

func run(_ line: String) {
    let result = converter.convert(line)
    print(result.output)
    guard verbose else { return }
    for word in result.words {
        let d = word.decision
        let lang = ["english": "en", "korean": "ko", "mixed": "mixed", "japanese": "ja"][d.language.rawValue] ?? d.language.rawValue
        print(String(format: "  %-16@ → %@ [%@ %.2f] %@", word.keys as NSString, d.output, lang, d.confidence, d.explanation))
    }
}

if args.isEmpty {
    while let line = readLine() { run(line) }
} else {
    run(args.joined(separator: " "))
}

/// A text field for `--type`: committed text, an optional marked span, and a caret.
final class PlainTextField: TextClient {
    var text = ""
    var marked = NSRange(location: NSNotFound, length: 0)
    var cursor = 0

    func setMarkedText(_ s: String) {
        setMarkedText(s, replacing: NSRange(location: cursor, length: 0))
    }

    func setMarkedText(_ s: String, replacing range: NSRange) {
        let target = marked.location != NSNotFound ? NSUnionRange(range, marked) : range
        text = (text as NSString).replacingCharacters(in: target, with: s)
        let length = (s as NSString).length
        marked = length > 0 ? NSRange(location: target.location, length: length) : NSRange(location: NSNotFound, length: 0)
        cursor = target.location + length
    }

    func insertText(_ s: String, replacing range: NSRange?) {
        let target = range ?? (marked.location != NSNotFound ? marked : NSRange(location: cursor, length: 0))
        text = (text as NSString).replacingCharacters(in: target, with: s)
        marked = NSRange(location: NSNotFound, length: 0)
        cursor = target.location + (s as NSString).length
    }

    func selectedRange() -> NSRange { NSRange(location: cursor, length: 0) }
    func markedRange() -> NSRange { marked }
    func text(in range: NSRange) -> String? {
        NSMaxRange(range) <= (text as NSString).length ? (text as NSString).substring(with: range) : nil
    }
}
