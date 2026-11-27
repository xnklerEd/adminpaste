BIN  := adminpaste
SRC  := adminpaste.swift
FLAGS := -framework Carbon -framework AppKit

all: $(BIN)

$(BIN): $(SRC)
	swiftc -O -o $@ $< $(FLAGS)

universal: $(SRC)
	swiftc -O -target arm64-apple-macos11.0  -o .ap-arm64  $< $(FLAGS)
	swiftc -O -target x86_64-apple-macos11.0 -o .ap-x86_64 $< $(FLAGS)
	lipo -create -output $(BIN) .ap-arm64 .ap-x86_64
	@rm -f .ap-arm64 .ap-x86_64
	@lipo -info $(BIN)

release: universal
	@echo "打包: adminpaste-universal.zip"
	rm -rf .dist && mkdir -p .dist/bin
	cp $(BIN) .dist/bin/
	cp adminpaste.swift install.sh uninstall.sh test-dialog.sh README.md README.zh-CN.md LICENSE .dist/
	ditto -c -k --norsrc .dist adminpaste-universal.zip
	@rm -rf .dist
	@shasum -a 256 adminpaste-universal.zip

clean:
	rm -f $(BIN) .ap-arm64 .ap-x86_64

.PHONY: all universal release clean