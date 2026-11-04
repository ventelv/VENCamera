# Builds VENCamera.app and installs it into /Applications. No App Store, no Apple account.
APP := /Applications/VENCamera.app

.PHONY: build install uninstall probe

build:
	swift build -c release --product VENCamera

install: build
	-osascript -e 'quit app "VENCamera"' 2>/dev/null
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$$(swift build -c release --show-bin-path)/VENCamera" "$(APP)/Contents/MacOS/VENCamera"
	cp Sources/VENCamera/Info.plist "$(APP)/Contents/Info.plist"
	cp Sources/Syphon/LICENSE.txt "$(APP)/Contents/Resources/Syphon-LICENSE.txt"
	codesign --force --sign - "$(APP)"
	open "$(APP)"

uninstall:
	-osascript -e 'quit app "VENCamera"' 2>/dev/null
	rm -rf "$(APP)"

probe:
	swift run canon-probe 10
