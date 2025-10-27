SHELL := /bin/bash

APP := face-pos
OUT_DIR := bin
LINUX_BIN := $(OUT_DIR)/$(APP)-linux
MAC_BIN := $(OUT_DIR)/$(APP)-macos
DOCKERFILE := Dockerfile.linux
BUILDER_IMAGE := $(APP)-builder:latest

PROTO_URL := https://raw.githubusercontent.com/opencv/opencv/master/samples/dnn/face_detector/deploy.prototxt
MODEL_URL := https://raw.githubusercontent.com/opencv/opencv_3rdparty/97e4a8b/res10_300x300_ssd_iter_140000.caffemodel

# --- Robust Homebrew prefix detection (no shell else) ---
BREW_PREFIX ?= $(shell command -v brew >/dev/null 2>&1 && brew --prefix || echo __NONE__)
ifeq ($(BREW_PREFIX),__NONE__)
  ifneq ("$(wildcard /opt/homebrew)","")
    BREW_PREFIX := /opt/homebrew
  else
    BREW_PREFIX := /usr/local
  endif
endif

PKG_PATH := $(BREW_PREFIX)/opt/opencv/lib/pkgconfig
DYLD_PATH := $(BREW_PREFIX)/opt/opencv/lib

.PHONY: help models linux mac clean

help:
	@echo ""
	@echo "=== Build Targets ==="
	@echo "  make linux   → Build Linux binary via Docker -> $(LINUX_BIN)"
	@echo "  make mac     → Build macOS binary natively -> $(MAC_BIN)"
	@echo "  make models  → Download DNN model files (deploy.prototxt + caffemodel)"
	@echo "  make clean   → Remove ./$(OUT_DIR)"
	@echo ""

# -------------------------------------------------
# Build Linux binary inside a Docker container
# -------------------------------------------------
linux: models
	@echo "==> Building Docker image ($(BUILDER_IMAGE))"
	docker build -f $(DOCKERFILE) -t $(BUILDER_IMAGE) .
	@echo "==> Compiling inside container"
	mkdir -p $(OUT_DIR)
	docker run --rm \
	  -v "$$(pwd)":/src \
	  -v "$$(pwd)/$(OUT_DIR)":/out \
	  --workdir /src \
	  $(BUILDER_IMAGE) bash -lc 'go build -o /out/$(APP)-linux ./main.go'
	@echo "✅ Linux binary ready: $(LINUX_BIN)"

# -------------------------------------------------
# Build macOS binary natively
# -------------------------------------------------
mac: models
	@echo "==> Building macOS binary ($(MAC_BIN))"
	@echo "   Using OpenCV from $(BREW_PREFIX)"
	mkdir -p $(OUT_DIR)
	PKG_CONFIG_PATH=$(PKG_PATH) \
	DYLD_FALLBACK_LIBRARY_PATH=$(DYLD_PATH) \
	CGO_ENABLED=1 \
	go build -o $(MAC_BIN) ./main.go
	@echo "✅ macOS binary ready: $(MAC_BIN)"

# -------------------------------------------------
# Download DNN model files if missing
# -------------------------------------------------
models:
	@mkdir -p models
	@if [ ! -f models/deploy.prototxt ]; then \
		echo "==> Downloading deploy.prototxt"; \
		curl -L -o models/deploy.prototxt "$(PROTO_URL)"; \
	else echo "==> models/deploy.prototxt already exists"; fi
	@if [ ! -f models/res10_300x300_ssd_iter_140000.caffemodel ]; then \
		echo "==> Downloading res10_300x300_ssd_iter_140000.caffemodel"; \
		curl -L -o models/res10_300x300_ssd_iter_140000.caffemodel "$(MODEL_URL)"; \
	else echo "==> models/res10_300x300_ssd_iter_140000.caffemodel already exists"; fi

# -------------------------------------------------
# Clean build output
# -------------------------------------------------
clean:
	rm -rf $(OUT_DIR)
