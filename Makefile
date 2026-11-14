# Builds VENCamera.app and installs it into /Applications. No App Store, no Apple account.
APP := /Applications/VENCamera.app

.PHONY: build install uninstall probe icon

build:
	swift build -c release --product VENCamera

install: build
	-osascript -e 'quit app "VENCamera"' 2>/dev/null
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$$(swift build -c release --show-bin-path)/VENCamera" "$(APP)/Contents/MacOS/VENCamera"
	cp Sources/VENCamera/Info.plist "$(APP)/Contents/Info.plist"
	cp Resources/AppIcon.icns "$(APP)/Contents/Resources/AppIcon.icns"
	cp Sources/Syphon/LICENSE.txt "$(APP)/Contents/Resources/Syphon-LICENSE.txt"
	codesign --force --sign - "$(APP)"
	open "$(APP)"

uninstall:
	-osascript -e 'quit app "VENCamera"' 2>/dev/null
	rm -rf "$(APP)"

probe:
	swift run canon-probe 10

# Redraws Resources/AppIcon.icns from Tools/make-icon.swift.
ICONSET := .build/AppIcon.iconset
icon:
	mkdir -p $(ICONSET) Resources
	swift Tools/make-icon.swift .build/icon-1024.png
	for size in 16 32 128 256 512; do \
		sips -z $$size $$size .build/icon-1024.png --out $(ICONSET)/icon_$${size}x$${size}.png >/dev/null; \
		sips -z $$((size * 2)) $$((size * 2)) .build/icon-1024.png --out $(ICONSET)/icon_$${size}x$${size}@2x.png >/dev/null; \
	done
	iconutil --convert icns $(ICONSET) --output Resources/AppIcon.icns
