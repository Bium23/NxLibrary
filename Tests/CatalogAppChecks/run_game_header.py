#!/usr/bin/env python3
"""Evaluate actual common header bodies without a window or app stores."""
from pathlib import Path
import subprocess,tempfile,os
ROOT=Path(__file__).resolve().parents[2]
BIN=ROOT/'.build/debug'
files=[ROOT/'Sources/NXLibrary/Views/Components/GameLogoArea.swift', ROOT/'Sources/NXLibrary/Views/Components/GamePrimaryActions.swift']
actual='\n'.join(p.read_text() for p in files)
host='''import SwiftUI
import NXLibraryCore
struct HeaderCanvas { func u(_ value: CGFloat) -> CGFloat { value } }
private struct CanvasKey: EnvironmentKey { static let defaultValue = HeaderCanvas() }
extension EnvironmentValues { var seleneCanvas: HeaderCanvas { get { self[CanvasKey.self] } set { self[CanvasKey.self] = newValue } } }
extension View { func seleneFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> some View { font(.system(size: size, weight: weight)) } }
enum SeleneTheme { static let ink = Color.white }
struct SelenePillButton: View {
 let title: String?; var icon: MaterialIcon? = nil; var iconSize: CGFloat = 26
 var minWidth: CGFloat = 180; var height: CGFloat = 60; var horizontalPadding: CGFloat = 36
 let focused: Bool; var enabled: Bool = true; let action: () -> Void
 var body: some View { Color.clear }
}
'''+actual+'''
@main struct Check {
 @MainActor static func main() {
  for collection in [true,false] {
   withExtendedLifetime(GameLogoArea(title: "Fixture", logo: nil, collection: collection).body) {}
  }
  for enabled in [true,false] {
   withExtendedLifetime(GamePrimaryActions(primaryTitle: "Play", secondaryTitle: "Options", isFavorite: true, focused: 0, primaryEnabled: enabled, onAction: {_ in}).body) {}
  }
  print("Actual shared game header bodies work without injected stores, for both layouts/action states.")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='game-header-check-') as folder:
 folder=Path(folder);swift=folder/'check.swift';swift.write_text(host);binary=folder/'check'
 subprocess.run(['xcrun','swiftc','-parse-as-library','-I',str(BIN),str(swift),str(BIN/'NXLibraryCore.o'),'-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True,env=dict(os.environ,PACKAGE_RESOURCE_BUNDLE_PATH=str(BIN)))
