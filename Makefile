APP := build/Space Disk Free.app
# Swift Testing fica fora do caminho padrão quando só há Command Line Tools instaladas.
CLT_FRAMEWORKS := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
TEST_FLAGS := --build-system native \
	-Xswiftc -F -Xswiftc $(CLT_FRAMEWORKS) \
	-Xlinker -F -Xlinker $(CLT_FRAMEWORKS) \
	-Xlinker -rpath -Xlinker $(CLT_FRAMEWORKS)

.PHONY: app run install test clean

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

test:
	swift test $(TEST_FLAGS)

clean:
	rm -rf .build build
