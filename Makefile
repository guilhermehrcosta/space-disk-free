APP := build/Space Disk Free.app
SOURCES := Package.swift Sources Tests

ifneq (,$(findstring CommandLineTools,$(shell xcode-select -p)))
CLT_FRAMEWORKS := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
TEST_FLAGS := --build-system native \
	-Xswiftc -F -Xswiftc $(CLT_FRAMEWORKS) \
	-Xlinker -F -Xlinker $(CLT_FRAMEWORKS) \
	-Xlinker -rpath -Xlinker $(CLT_FRAMEWORKS)
endif

.PHONY: app run install dmg icon strings strings-check test lint format clean

app:
	./Scripts/build-app.sh

run: app
	-pkill -x SpaceDiskFree
	open "$(APP)"

install: app
	-pkill -x SpaceDiskFree
	rm -rf "/Applications/Space Disk Free.app"
	cp -R "$(APP)" /Applications/
	open "/Applications/Space Disk Free.app"

dmg:
	ARCHS="arm64 x86_64" ./Scripts/build-app.sh
	./Scripts/make-dmg.sh

icon:
	swift Scripts/make-icon.swift

strings:
	rm -rf .build/strings .build/strings-build
	mkdir -p .build/strings
	swift build --scratch-path .build/strings-build \
		-Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc $(CURDIR)/.build/strings
	xcrun xcstringstool sync Resources/Localizable.xcstrings --stringsdata .build/strings/*.stringsdata

strings-check: strings
	git diff --exit-code -- Resources/Localizable.xcstrings

test:
	swift test $(TEST_FLAGS)

lint:
	swift format lint --strict --recursive --parallel $(SOURCES)

format:
	swift format format --in-place --recursive --parallel $(SOURCES)

clean:
	rm -rf .build build
