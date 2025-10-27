# =========================
# Project / binaries
# =========================
SHELL := /bin/bash

APP        := face-pos
OUT_DIR    := out
LINUX_BIN  := $(OUT_DIR)/$(APP)-linux
MAC_BIN    := $(OUT_DIR)/$(APP)-macos

# =========================
# Model files (OpenCV face detector)
# =========================
PROTO_URL := https://raw.githubusercontent.com/opencv/opencv/master/samples/dnn/face_detector/deploy.prototxt
MODEL_URL := https://raw.githubusercontent.com/Isfhan/face-detection-python/master/res10_300x300_ssd_iter_140000.caffemodel


# =========================
# macOS (Homebrew) detection for mac build
# =========================
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

# =========================
# Linux pkg-config search path (OpenCV installé via gocv -> /usr/local)
# =========================
LINUX_PKGCONFIG_PATH := /usr/local/lib/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:$(PKG_CONFIG_PATH)

# =========================
# Phony
# =========================
.PHONY: help linux mac models clean

# =========================
# Help
# =========================
help:
	@echo ""
	@echo "=== Build Targets ==="
	@echo "  make linux   → Build Linux binaire natif -> $(LINUX_BIN)"
	@echo "                 (utilise pkg-config opencv4)"
	@echo "  make mac     → Build macOS binaire natif -> $(MAC_BIN)"
	@echo "  make models  → Télécharge les modèles DNN (si absents)"
	@echo "  make clean   → Supprime $(OUT_DIR)/"
	@echo ""
	@echo "Exécution sous Linux si nécessaire :"
	@echo "  export LD_LIBRARY_PATH=/usr/local/lib:\$$LD_LIBRARY_PATH && ./$(LINUX_BIN)"
	@echo "ou bien (persistant) :"
	@echo "  echo '/usr/local/lib' | sudo tee /etc/ld.so.conf.d/opencv-local.conf >/dev/null && sudo ldconfig"
	@echo ""

# =========================
# Build Linux nativement
# =========================
linux: models
	@echo "==> Building Linux binary ($(LINUX_BIN))"
	mkdir -p "$(OUT_DIR)"
	PKG_CONFIG_PATH="$(LINUX_PKGCONFIG_PATH)" \
	CGO_ENABLED=1 \
	CGO_CFLAGS="$$(pkg-config --cflags opencv4)" \
	CGO_LDFLAGS="$$(pkg-config --libs opencv4)" \
	go build -o "$(LINUX_BIN)" ./main.go
	@echo "✅ Linux binary ready: $(LINUX_BIN)"

# =========================
# Build macOS nativement
# =========================
mac: models
	@echo "==> Building macOS binary ($(MAC_BIN))"
	@echo "   Using OpenCV from $(BREW_PREFIX)"
	mkdir -p "$(OUT_DIR)"
	PKG_CONFIG_PATH="$(PKG_PATH)" \
	DYLD_FALLBACK_LIBRARY_PATH="$(DYLD_PATH)" \
	CGO_ENABLED=1 \
	go build -o "$(MAC_BIN)" ./main.go
	@echo "✅ macOS binary ready: $(MAC_BIN)"

# =========================
# Download model files (idempotent)
# =========================
models:
	@mkdir -p models
	@[ -f models/deploy.prototxt ] || (echo "==> Downloading deploy.prototxt" && curl -L -o models/deploy.prototxt "$(PROTO_URL)")
	@[ -f models/res10_300x300_ssd_iter_140000.caffemodel ] || (echo "==> Downloading res10_300x300_ssd_iter_140000.caffemodel" && curl -L -o models/res10_300x300_ssd_iter_140000.caffemodel "$(MODEL_URL)")
	@echo "✅ Models OK"

# =========================
# Clean
# =========================
clean:
	rm -rf "$(OUT_DIR)"