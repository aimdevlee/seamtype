// Registers an installed input method and enables its input source (as adding it in
// System Settings → Keyboard → Input Sources would). It doesn't select it.
//
// usage: swift scripts/enable-input-source.swift <path to .app> <input source ID>
//        swift scripts/enable-input-source.swift --check <input source ID>   (exit 0 if enabled)
//
// Recent macOS answers noErr to enabling but leaves a third-party input method off until the
// user adds it. One the user already added is listed as enabled again a few seconds after a
// reinstall, but only to a process started after that (the list is cached per process), so
// the install script re-checks with --check.
import Carbon
import Foundation

let args = CommandLine.arguments
guard args.count == 3 else { print("usage: enable-input-source <app>|--check <source id>"); exit(2) }
let wanted = args[2]
let filter = [kTISPropertyInputSourceID as String: wanted] as CFDictionary

func sourceID(_ s: TISInputSource) -> String {
    guard let p = TISGetInputSourceProperty(s, kTISPropertyInputSourceID) else { return "" }
    return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
}

func list(includeDisabled: Bool) -> [TISInputSource] {
    ((TISCreateInputSourceList(filter, includeDisabled)?.takeRetainedValue() as? [TISInputSource]) ?? [])
        .filter { sourceID($0) == wanted }
}

if args[1] == "--check" { exit(list(includeDisabled: false).isEmpty ? 3 : 0) }

let existing = list(includeDisabled: true).first
let registered = existing == nil ? TISRegisterInputSource(URL(fileURLWithPath: args[1]) as CFURL) : noErr
guard registered == noErr else { print("could not register \(args[1]) (\(registered))"); exit(1) }
if let source = existing ?? list(includeDisabled: true).first {
    let enabled = TISEnableInputSource(source)
    guard enabled == noErr else { print("could not enable input source (\(enabled))"); exit(1) }
}
exit(list(includeDisabled: false).isEmpty ? 3 : 0)
