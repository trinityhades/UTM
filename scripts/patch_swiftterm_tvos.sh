#!/bin/sh
set -eu

ROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
DERIVED_ROOT="${HOME}/Library/Developer/Xcode/DerivedData"

find "$DERIVED_ROOT" -path '*/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm' -type d 2>/dev/null | while IFS= read -r swiftterm_sources; do
    package_root="$(cd "$swiftterm_sources/../.." && pwd)"

    if [ ! -f "$package_root/Package.swift" ]; then
        continue
    fi

    perl -pi -e 's/#if os\(macOS\) \|\| os\(iOS\) \|\| os\(visionOS\)/#if os(macOS) || os(iOS) || os(tvOS) || os(visionOS)/g; s/#if os\(iOS\) \|\| os\(visionOS\)/#if os(iOS) || os(tvOS) || os(visionOS)/g; s/@available\(iOS 14\.0, \*\)/@available(iOS 14.0, tvOS 14.0, *)/g' \
        "$swiftterm_sources/Apple/AppleTerminalView.swift" \
        "$swiftterm_sources/Apple/Extensions.swift" \
        "$swiftterm_sources/Apple/TerminalViewDelegate.swift" \
        "$swiftterm_sources/iOS/iOSAccessoryView.swift" \
        "$swiftterm_sources/iOS/iOSCaretView.swift" \
        "$swiftterm_sources/iOS/iOSDoubleButton.swift" \
        "$swiftterm_sources/iOS/iOSExtensions.swift" \
        "$swiftterm_sources/iOS/iOSKeyboardView.swift" \
        "$swiftterm_sources/iOS/iOSTerminalView.swift" \
        "$swiftterm_sources/iOS/iOSTextInput.swift"

    perl -0pi -e 's/disableSelectionPanGesture\(\)\n        if let start = UIPasteboard\.general\.string \{\n            send\(txt: start\)\n            queuePendingDisplay\(\)\n        \}/disableSelectionPanGesture()\n        #if !os(tvOS)\n        if let start = UIPasteboard.general.string {\n            send(txt: start)\n            queuePendingDisplay()\n        }\n        #endif/g; s/UIPasteboard\.general\.string = selection\.getSelectedText\(\)\n        selection\.selectNone\(\)/#if !os(tvOS)\n        UIPasteboard.general.string = selection.getSelectedText()\n        #endif\n        selection.selectNone()/g; s/func showContextMenu \(forRegion: CGRect, pos: Position\) \{\n        var items: \[UIMenuItem\] = \[\]/func showContextMenu (forRegion: CGRect, pos: Position) {\n        #if os(tvOS)\n        lastLongSelect = pos\n        lastLongSelectRegion = forRegion\n        return\n        #else\n        var items: [UIMenuItem] = []/g; s/menuController\.showMenu\(from: self, rect: forRegion\)\n    \}/menuController.showMenu(from: self, rect: forRegion)\n        #endif\n    }/g; s/                if UIMenuController\.shared\.isMenuVisible \{\n                    UIMenuController\.shared\.hideMenu\(\)\n                \} else \{\n                    let location = gestureRecognizer\.location\(in: gestureRecognizer\.view\)\n                    let tapLoc = calculateTapHit\(gesture: gestureRecognizer\)\.grid\n                    let cursorRow = terminal\.buffer\.y\+terminal\.buffer\.yDisp\n                    if abs \(tapLoc\.col-terminal\.buffer\.x\) < 4 && abs \(tapLoc\.row - cursorRow\) < 2 \{\n                        showContextMenu \(forRegion: makeContextMenuRegionForTap \(point: location\), pos: tapLoc\)\n                    \}\n                \}/                #if !os(tvOS)\n                if UIMenuController.shared.isMenuVisible {\n                    UIMenuController.shared.hideMenu()\n                } else {\n                    let location = gestureRecognizer.location(in: gestureRecognizer.view)\n                    let tapLoc = calculateTapHit(gesture: gestureRecognizer).grid\n                    let cursorRow = terminal.buffer.y+terminal.buffer.yDisp\n                    if abs (tapLoc.col-terminal.buffer.x) < 4 && abs (tapLoc.row - cursorRow) < 2 {\n                        showContextMenu (forRegion: makeContextMenuRegionForTap (point: location), pos: tapLoc)\n                    }\n                }\n                #endif/g; s/#if !os\(visionOS\)\n        inputAssistantItem\.leadingBarButtonGroups = \[\]\n        inputAssistantItem\.trailingBarButtonGroups = \[\]\n        #endif/#if !os(visionOS) \&\& !os(tvOS)\n        inputAssistantItem.leadingBarButtonGroups = []\n        inputAssistantItem.trailingBarButtonGroups = []\n        #endif/g; s/            if !self\.selection\.active \{\n                UIMenuController\.shared\.hideMenu\(\)\n                self\.selection\.selectNone\(\)/            if !self.selection.active {\n                #if !os(tvOS)\n                UIMenuController.shared.hideMenu()\n                #endif\n                self.selection.selectNone()/g' \
        "$swiftterm_sources/iOS/iOSTerminalView.swift"

    perl -0pi -e 's/        let pan = UIPanGestureRecognizer \(target: self, action: #selector\(pan\)\)\n        pan\.minimumNumberOfTouches = 1\n        pan\.maximumNumberOfTouches = 1\n        addGestureRecognizer\(pan\)/        let pan = UIPanGestureRecognizer (target: self, action: #selector(pan))\n        #if !os(tvOS)\n        pan.minimumNumberOfTouches = 1\n        pan.maximumNumberOfTouches = 1\n        #endif\n        addGestureRecognizer(pan)/g' \
        "$swiftterm_sources/iOS/iOSDoubleButton.swift"

    perl -pi -e 's/#if !os\(iOS\)/#if !os(iOS) \&\& !os(tvOS)/g' \
        "$swiftterm_sources/HeadlessTerminal.swift" \
        "$swiftterm_sources/LocalProcess.swift"

    echo "Patched SwiftTerm for tvOS: $package_root"
done

find "$DERIVED_ROOT" -path '*/SourcePackages/checkouts/CocoaSpice/Sources' -type d 2>/dev/null | while IFS= read -r cocoaspice_sources; do
    package_root="$(cd "$cocoaspice_sources/.." && pwd)"

    if [ ! -f "$package_root/Package.swift" ]; then
        continue
    fi

    perl -0pi -e 's/- \(void\)drawRegion:\(CGRect\)rect \{\n    if \(!self\.canvasData \|\| !self\.canvasBuffer\) \{\n        return; \/\/ not ready to draw yet\n    \}/- (void)drawRegion:(CGRect)rect {\n    rect = CGRectIntersection(rect, self.visibleArea);\n    if (CGRectIsEmpty(rect) || !self.canvasData || !self.canvasBuffer) {\n        return; \/\/ not ready to draw yet\n    }/g' \
        "$cocoaspice_sources/CocoaSpice/CSDisplay.m"

    perl -0pi -e 's/    \[blitEncoder copyFromBuffer:sourceBuffer\n                   sourceOffset:sourceOffset\n              sourceBytesPerRow:sourceBytesPerRow\n            sourceBytesPerImage:0\n                     sourceSize:region\.size\n                      toTexture:sourceData\.texture\n               destinationSlice:0\n               destinationLevel:0\n              destinationOrigin:region\.origin\];/    MTLOrigin destinationOrigin = region.origin;\n    MTLSize sourceSize = region.size;\n    if (destinationOrigin.x >= sourceData.texture.width || destinationOrigin.y >= sourceData.texture.height) {\n        [blitEncoder endEncoding];\n        [commandBuffer commit];\n        if (completion) {\n            completion();\n        }\n        return;\n    }\n    sourceSize.width = MIN(sourceSize.width, sourceData.texture.width - destinationOrigin.x);\n    sourceSize.height = MIN(sourceSize.height, sourceData.texture.height - destinationOrigin.y);\n\n    [blitEncoder copyFromBuffer:sourceBuffer\n                   sourceOffset:sourceOffset\n              sourceBytesPerRow:sourceBytesPerRow\n            sourceBytesPerImage:0\n                     sourceSize:sourceSize\n                      toTexture:sourceData.texture\n               destinationSlice:0\n               destinationLevel:0\n              destinationOrigin:destinationOrigin];/g' \
        "$cocoaspice_sources/CocoaSpiceRenderer/CSMetalRenderer.m"

    echo "Patched CocoaSpice for tvOS: $package_root"
done
