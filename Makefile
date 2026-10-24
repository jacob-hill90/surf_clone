
BUILD_DIR := build-mac
APP := $(BUILD_DIR)/SurfEngine.app

.PHONY: all configure build run clean rebuild

all: build

configure:
	cmake -S . -B $(BUILD_DIR) -DCMAKE_BUILD_TYPE=Release

build: configure
	cmake --build $(BUILD_DIR) --parallel

run: build
	open $(APP)

clean:
	cmake -E rm -rf $(BUILD_DIR)

rebuild: clean build
