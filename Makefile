APP := build/Space Disk Free.app
SOURCES := Package.swift Sources Tests

# Só com as Command Line Tools o Swift Testing fica fora do caminho padrão e o backend
# padrão do SwiftPM não inicializa. Com o Xcode selecionado nada disso é necessário.
ifneq (,$(findstring CommandLineTools,$(shell xcode-select -p)))
CLT_FRAMEWORKS := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
TEST_FLAGS := --build-system native \
	-Xswiftc -F -Xswiftc $(CLT_FRAMEWORKS) \
	-Xlinker -F -Xlinker $(CLT_FRAMEWORKS) \
	-Xlinker -rpath -Xlinker $(CLT_FRAMEWORKS)
endif

.PHONY: app run install dmg icon test lint format clean

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

# Mesmo artefato do workflow de release: binário universal empacotado em .dmg.
dmg:
	ARCHS="arm64 x86_64" ./Scripts/build-app.sh
	./Scripts/make-dmg.sh

# Redesenha Resources/AppIcon.icns a partir de Scripts/make-icon.swift.
icon:
	swift Scripts/make-icon.swift

test:
	swift test $(TEST_FLAGS)

lint:
	swift format lint --strict --recursive --parallel $(SOURCES)

format:
	swift format format --in-place --recursive --parallel $(SOURCES)

clean:
	rm -rf .build build
