

Pre-requis sur mac

```shell
# 1) OpenCV + pkg-config
brew install opencv pkg-config

# 2) PKG_CONFIG_PATH (Apple Silicon /opt/homebrew… ; Intel /usr/local…)
# Apple Silicon :
export PKG_CONFIG_PATH="/opt/homebrew/opt/opencv/lib/pkgconfig:${PKG_CONFIG_PATH}"
# Intel :
# export PKG_CONFIG_PATH="/usr/local/opt/opencv/lib/pkgconfig:${PKG_CONFIG_PATH}"

# 3) CGO ON (obligatoire pour gocv)
export CGO_ENABLED=1

# 4) GoCV (dans le projet)
go mod tidy
```

Pre-requis sur linux

```shell
sudo apt update
sudo apt install -y build-essential pkg-config libopencv-dev
export CGO_ENABLED=1
go mod tidy
```




export CGO_ENABLED=1
export PKG_CONFIG_PATH="/opt/homebrew/opt/opencv/lib/pkgconfig:$PKG_CONFIG_PATH"
export DYLD_FALLBACK_LIBRARY_PATH="/opt/homebrew/opt/opencv/lib:$DYLD_FALLBACK_LIBRARY_PATH"





curl -L -O https://raw.githubusercontent.com/opencv/opencv/master/samples/dnn/face_detector/deploy.prototxt
curl -L -O https://raw.githubusercontent.com/opencv/opencv_3rdparty/97e4a8b/res10_300x300_ssd_iter_140000.caffemodel

