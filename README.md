# Tracking GO

## Build on MacOS

```shell
# 1) OpenCV + pkg-config
brew install opencv pkg-config

# 2) PKG_CONFIG_PATH (Apple Silicon /opt/homebrew… ; Intel /usr/local…)
# Apple Silicon :
export PKG_CONFIG_PATH="/opt/homebrew/opt/opencv/lib/pkgconfig:${PKG_CONFIG_PATH}"
# Intel :
# export PKG_CONFIG_PATH="/usr/local/opt/opencv/lib/pkgconfig:${PKG_CONFIG_PATH}"

# 3) CGO ON (required fo gocv)
export CGO_ENABLED=1

# 4) GoCV (in the project)
go mod tidy
```

## Build on Linux

```shell
# 1) Build deps for OpenCV + GoCV
sudo apt update
sudo apt install -y \
  build-essential pkg-config cmake git curl \
  libgtk-3-dev libjpeg-dev libpng-dev libtiff-dev libdc1394-dev \
  libavcodec-dev libavformat-dev libswscale-dev libavutil-dev \
  libv4l-dev libopenexr-dev \
  libtbb-dev libtbb12

# Install Go 1.24 (official binary)
curl -LO https://go.dev/dl/go1.24.0.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.24.0.linux-amd64.tar.gz

# Add Go to PATH
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
source ~/.bashrc

# Check
go version

# Install OpenCV 4.12
git clone https://github.com/hybridgroup/gocv.git
cd gocv
make install 
cd -

## 4) Verify pkg-config points to the /usr/local OpenCV (should be 4.12.x)
pkg-config --modversion opencv4

# 5) Build the project 
#    Usually no extra env is needed, but you can force pkg-config to /usr/local just in case:
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
```
