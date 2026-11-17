#!/usr/bin/env python3
"""Actual theme input, soft particles and offscreen Metal contracts.

No windows, player data, screenshots or UI automation. Metal checks are skipped
when the host has no device; Core and actual input checks still run.
"""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BIN = ROOT / '.build/debug'


def declaration(path, signature):
    source = (ROOT / path).read_text()
    start = source.index(signature)
    opening = source.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


# Controller/keyboard order must match the actual rows, not a second manual list.
import re
look_source = (ROOT / 'Sources/NXLibrary/Views/Settings/SettingsLookSection.swift').read_text()
look_body = look_source[look_source.index('    var body:'):look_source.index('    private func publishActions')]
visible_rows = re.findall(r'Selene(?:Cycle|Toggle)Row\("([^"]+)"', look_body)
actions = declaration('Sources/NXLibrary/Views/Settings/SettingsLookSection.swift', '    private func publishActions(')
action_rows = [a or b for a, b in re.findall(
    r'\.value\("[^"]+", "([^"]+)"|\.init\(id: "[^"]+", title: "([^"]+)"', actions)]
assert visible_rows == action_rows, ('Look navigation order differs from visible rows', visible_rows, action_rows)


host = r'''
import Foundation
import AppKit
import SwiftUI
import Metal
import NXLibraryCore

@MainActor enum LaunchReveal { static func moonlightShown() {} }
@MainActor final class SoundEffectService {
    enum Cue { case focus, key, click }
    static let shared = SoundEffectService()
    func play(_ cue: Cue) {}
}
final class PaletteController {
    var applied: [String] = []
    func apply(id: String) { applied.append(id) }
}
struct BrowseCategory { var isSearch = false }
struct BrowseState { var focusedItem: Int?; var category = BrowseCategory() }
final class Browser { var state: BrowseState? }
@MainActor final class Host {
    var state = ThemePickerState(themeIndex: 0, backgroundIndex: 0)
    let palettes: [SelenePalette]
    let settings: AppSettingsStore
    let theme = PaletteController()
    let browser = Browser()
    var searchFocused = false
    var placements: [String?] = []
    var backgrounds: [ThemeBackgroundChoice] { [.none] }
    var focusedBackground: ThemeBackgroundChoice { .none }
    init(palettes: [SelenePalette], settings: AppSettingsStore) { self.palettes = palettes; self.settings = settings }
    func focusSetting(themeID: String) { state.backgroundIndex = 0 }
    func choose(_ item: Int) {}
    func addOwn() {}
    func askPlacement(_ id: String?) { placements.append(id) }
    func openSource(_ id: BackgroundSourceID) {}
    // ACTUAL_METHODS
    func key(_ direction: GridDirection) { move(direction) }
    func next() { accept() }
    func click(_ index: Int) { tap(index) }
}
// ACTUAL_STEPPING

@main struct Check {
    @MainActor static func main() throws {
        let scratch = URL(fileURLWithPath: CommandLine.arguments[1])
        let settingsURL = scratch.appendingPathComponent("settings.json")
        let settings = AppSettingsStore(fileURL: settingsURL)
        let palettes = SelenePaletteCatalog.pickerOrder(try SelenePaletteCatalog.load(from:
            URL(fileURLWithPath: "Resources/Selene/palettes.json")))
        precondition(palettes[0].name == AppIdentity.name && palettes[0].id == "selene")
        precondition(palettes[0].surface == .classic && SelenePalette.fallback.surface == .classic)
        precondition(palettes.first { $0.id == "arcane-crystal" }?.surface == .arcane)
        precondition(palettes.first { $0.id == "arcane-flow" }?.surface == .flow)
        let host = Host(palettes: palettes, settings: settings)
        host.state.themeIndex = palettes.count - 1
        host.key(.down)
        host.key(.right)
        precondition(host.state.step == .theme && host.state.themeIndex == palettes.count - 1)
        host.state.themeIndex = 4
        host.key(.right)
        precondition(host.state.themeIndex == 4)
        host.click(0)
        precondition(host.state.themeIndex == 0 && host.state.step == .theme)
        host.next()
        precondition(host.state.step == .background && settings.settings.colorThemeID == "selene")
        precondition(host.theme.applied == ["selene"] && host.placements.isEmpty)
        host.next()
        precondition(host.placements == [WallpaperCatalog.none])
        print("Theme input: grid edges, mouse refocus and Next to background without a particle row: PASS")

        guard MTLCreateSystemDefaultDevice() != nil else {
            print("Metal unavailable: offscreen rendering checks skipped.")
            return
        }
        guard let engine = MoonlightEngine.shared else { fatalError("Moonlight shaders failed to initialize") }
        let soft = MoonlightColors(accent: .blue, ink: .white)
        let arcane = MoonlightColors(accent: .blue, ink: .white, surface: .arcane)
        let flow = MoonlightColors(accent: .blue, ink: .white, surface: .flow)
        let gold = MoonlightColors(accent: .yellow, ink: .white, tint: 1)
        let s = MoonlightEngine.uniforms(width: 640, height: 360, time: 24, breath: 0.75, colors: soft)
        let a = MoonlightEngine.uniforms(width: 640, height: 360, time: 24, breath: 0.75, colors: arcane)
        let g = MoonlightEngine.uniforms(width: 640, height: 360, time: 24, breath: 0.75, colors: gold)
        precondition(s.look.z == 0 && s.look.w == 0 && a.look.z == 0 && a.look.w == 1)
        precondition(g.look.w == 0 && g.tintTop.w == 1 && g.look.z == 0)
        func pixels(_ colors: MoonlightColors, _ time: Float = 24) -> Data {
            let frame = engine.snapshot(width: 640, height: 360, colors: colors, time: time)!
            return frame.dataProvider!.data! as Data
        }
        let fixed = pixels(arcane)
        precondition(fixed == pixels(arcane), "a still frame keeps both motion and colour fixed")
        precondition(fixed != pixels(arcane, 27))
        let flowPixels = pixels(flow)
        precondition(flowPixels != fixed && flowPixels != pixels(flow, 44))
        precondition(flowPixels == pixels(flow))
        var blended = flow
        blended.flow = 0.5; blended.arcane = 0.5; blended.tint = 0.5
        precondition(pixels(blended) != fixed && pixels(blended) != flowPixels)
        for var hidden in [arcane, flow, blended] {
            hidden.presence = 0
            precondition(pixels(hidden).allSatisfy { $0 == 0 }, "covered surfaces and particles must remain transparent")
        }
        precondition(MoonlightEngine.uniforms(width: 640, height: 360, time: 24, breath: 0.75, colors: flow).look.z == 1)
        precondition(fixed != pixels(soft), "the colour field reaches soft particles too")
        precondition(pixels(gold) != fixed)

        // Exercise the very function the real fragment/vertex entry points call.
        let source = MoonlightShaders.source + """
        kernel void sampleArcane(device float4 *out [[buffer(0)]], uint i [[thread_position_in_grid]]) {
            out[i] = float4(arcaneSpectrum(float2(float(i) * 0.13, 0.3 + float(i) * 0.05), float(i) * 35.3, 0.0), 1.0);
        }
        kernel void sampleWind(device float4 *out [[buffer(0)]], uint i [[thread_position_in_grid]]) {
            float phase = float(i)*0.4;
            out[i] = float4(filamentY(0.5,float2(0.1,0.3),float2(0.9,0.7),0.0,phase,0.0),
                            filamentProfile(0.0), filamentProfile(1.0),
                            filamentY(0.7,float2(0.1,0.3),float2(0.9,0.7),0.0,phase,0.0));
        }
        """
        let device = engine.device
        let library = try device.makeLibrary(source: source, options: nil)
        let pipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "sampleArcane")!)
        let buffer = device.makeBuffer(length: 6 * MemoryLayout<SIMD4<Float>>.stride, options: .storageModeShared)!
        let command = device.makeCommandQueue()!.makeCommandBuffer()!
        let encoder = command.makeComputeCommandEncoder()!
        encoder.setComputePipelineState(pipeline); encoder.setBuffer(buffer, offset: 0, index: 0)
        encoder.dispatchThreads(MTLSize(width: 6, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 6, height: 1, depth: 1))
        encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
        precondition(command.status == .completed)
        let values = buffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: 6)
        for i in 0..<6 {
            let expected = MoonlightChromatics.sample(x: Float(i) * 0.13, y: 0.3 + Float(i) * 0.05, time: Float(i) * 35.3)
            for k in 0..<3 { precondition(abs(values[i][k] - expected[k]) < 0.00002) }
        }
        let windPipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "sampleWind")!)
        let windBuffer = device.makeBuffer(length: 16 * MemoryLayout<SIMD4<Float>>.stride, options: .storageModeShared)!
        let windCommand = device.makeCommandQueue()!.makeCommandBuffer()!
        let windEncoder = windCommand.makeComputeCommandEncoder()!
        windEncoder.setComputePipelineState(windPipeline)
        windEncoder.setBuffer(windBuffer, offset: 0, index: 0)
        windEncoder.dispatchThreads(MTLSize(width: 16,height: 1,depth: 1), threadsPerThreadgroup: MTLSize(width: 16,height: 1,depth: 1))
        windEncoder.endEncoding(); windCommand.commit(); windCommand.waitUntilCompleted()
        precondition(windCommand.status == .completed)
        let wind = windBuffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: 16)
        let heights = (0..<16).map { wind[$0].x }
        precondition(heights.max()! - heights.min()! > 0.025 && heights.max()! - heights.min()! < 0.08,
                     "wind must bend the curve visibly, within a small part of the height")
        precondition(wind[0].z < wind[0].y * 0.2, "one pixel from the core, light must be faint")
        precondition(abs((wind[3].x-wind[0].x)-(wind[3].w-wind[0].w)) > 0.001,
                     "wind deforms the curve instead of translating a rigid line")
        for i in 1..<16 { precondition(abs(wind[i].x-wind[i-1].x) < 0.025) }
        print("Actual Metal: thin core and bounded travelling wind deformation: PASS")
        print("Actual Metal: local colour parity, distinct moving surfaces, soft particles, fixed frame and distinct Mods uniforms: PASS")
    }
}
'''

path = 'Sources/NXLibrary/Views/Theme/ThemePickerView.swift'
methods = '\n'.join(declaration(path, signature) for signature in (
    '    private func move(', '    private func tap(', '    private func accept('))
host = host.replace('// ACTUAL_METHODS', methods)
host = host.replace('// ACTUAL_STEPPING', declaration(
    'Sources/NXLibrary/Views/Components/SeleneSettingsRow.swift', 'extension CaseIterable where Self: Equatable'))

with tempfile.TemporaryDirectory(prefix='arcane-theme-check-') as folder:
    scratch = Path(folder)
    swift = scratch / 'check.swift'
    swift.write_text(host)
    executable = scratch / 'check'
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-I', str(BIN), str(swift),
                    str(ROOT / 'Sources/NXLibrary/Views/Theme/MoonlightRenderer.swift'),
                    str(ROOT / 'Sources/NXLibrary/Views/Theme/MoonlightShaders.swift'),
                    str(BIN / 'NXLibraryCore.o'), '-o', str(executable)], cwd=ROOT, check=True)
    subprocess.run([str(executable), str(scratch)], cwd=ROOT, check=True,
                   env=dict(os.environ, PACKAGE_RESOURCE_BUNDLE_PATH=str(BIN)))
