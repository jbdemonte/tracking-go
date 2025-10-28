// go:build linux
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"image"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"gocv.io/x/gocv"
)

/* ---------------------------- Data definitions ---------------------------- */

type Rect struct {
	X      int `json:"x"`
	Y      int `json:"y"`
	Width  int `json:"width"`
	Height int `json:"height"`
}

type Point struct {
	X int `json:"x"`
	Y int `json:"y"`
}

type Detection struct {
	ID        int       `json:"id"`
	BBox      Rect      `json:"bbox"`
	Landmarks []Point   `json:"landmarks,omitempty"`
	Score     float64   `json:"score"`
	Timestamp time.Time `json:"ts"`
}

type Snapshot struct {
	Source      string      `json:"source"`
	Frame       int64       `json:"frame"`
	Detections  []Detection `json:"detections"`
	GeneratedAt time.Time   `json:"generated_at"`
}

/* --------------------------- Thread-safe storage -------------------------- */

type FaceStore struct {
	mu      sync.RWMutex
	snap    Snapshot
	version uint64
}

func (s *FaceStore) Set(snap Snapshot) {
	s.mu.Lock()
	s.snap = snap
	atomic.AddUint64(&s.version, 1)
	s.mu.Unlock()
}

func (s *FaceStore) Get() (Snapshot, uint64) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.snap, atomic.LoadUint64(&s.version)
}

/* ------------------------------ DNN detector ------------------------------ */

type DNNDetector struct {
	cap        *gocv.VideoCapture
	net        gocv.Net
	source     string
	inputSize  image.Point
	meanBGR    gocv.Scalar
	scale      float64
	swapRB     bool
	crop       bool
	confThresh float32
}

type DetectorConfig struct {
	Source         string        // "0" (webcam), ou "rtsp://...", ou "/path/video.mp4"
	ProtoTxtPath   string        // ex: models/deploy.prototxt
	ModelPath      string        // ex: models/res10_300x300_ssd_iter_140000.caffemodel
	Interval       time.Duration // ex: 200 * time.Millisecond
	Confidence     float32       // ex: 0.5
	InputW, InputH int           // ex: 300, 300
}

func NewDNNDetector(cfg DetectorConfig) (*DNNDetector, error) {
	var (
		cap *gocv.VideoCapture
		err error
	)
	if idx, convErr := strconv.Atoi(cfg.Source); convErr == nil {
		cap, err = gocv.OpenVideoCapture(idx)
	} else {
		cap, err = gocv.OpenVideoCapture(cfg.Source)
	}
	if err != nil {
		return nil, fmt.Errorf("open video source: %w", err)
	}
	if !cap.IsOpened() {
		return nil, fmt.Errorf("video source not opened: %s", cfg.Source)
	}

	// Charge le réseau DNN (Caffe)
	net := gocv.ReadNetFromCaffe(cfg.ProtoTxtPath, cfg.ModelPath)
	if net.Empty() {
		cap.Close()
		return nil, fmt.Errorf("failed to load DNN model (prototxt=%s, model=%s)", cfg.ProtoTxtPath, cfg.ModelPath)
	}
	// CPU par défaut (change en OpenVINO/CUDA si dispo)
	net.SetPreferableBackend(gocv.NetBackendDefault)
	net.SetPreferableTarget(gocv.NetTargetCPU)

	if cfg.InputW == 0 {
		cfg.InputW = 300
	}
	if cfg.InputH == 0 {
		cfg.InputH = 300
	}
	if cfg.Confidence <= 0 {
		cfg.Confidence = 0.5
	}

	return &DNNDetector{
		cap:        cap,
		net:        net,
		source:     cfg.Source,
		inputSize:  image.Pt(cfg.InputW, cfg.InputH),
		meanBGR:    gocv.NewScalar(104.0, 177.0, 123.0, 0), // mean du modèle Res10 (BGR)
		scale:      1.0,
		swapRB:     false,
		crop:       false,
		confThresh: cfg.Confidence,
	}, nil
}

func (d *DNNDetector) Close() {
	if d.cap != nil {
		d.cap.Close()
	}
	d.net.Close()
}

// Detect lit une frame et retourne les détections (bbox + score).
// Sortie Res10: [1,1,N,7] => [image_id, class_id, confidence, x1, y1, x2, y2] (coords normalisées)
func (d *DNNDetector) Detect() (string, []Detection) {
	img := gocv.NewMat()
	if ok := d.cap.Read(&img); !ok || img.Empty() {
		img.Close()
		return d.source, nil
	}
	defer img.Close()

	blob := gocv.BlobFromImage(img, d.scale, d.inputSize, d.meanBGR, d.swapRB, d.crop)
	d.net.SetInput(blob, "")
	dets := d.net.Forward("") // sortie [1,1,N,7]
	blob.Close()
	if dets.Empty() || dets.Total() < 7 {
		dets.Close()
		return d.source, nil
	}
	defer dets.Close()

	rows := int(dets.Total() / 7)
	flat := dets.Reshape(1, rows) // N x 7
	defer flat.Close()

	h := float32(img.Rows())
	w := float32(img.Cols())

	out := make([]Detection, 0, rows)
	now := time.Now().UTC()

	for i := 0; i < rows; i++ {
		conf := flat.GetFloatAt(i, 2)
		if conf < d.confThresh {
			continue
		}
		x1 := int(flat.GetFloatAt(i, 3) * w)
		y1 := int(flat.GetFloatAt(i, 4) * h)
		x2 := int(flat.GetFloatAt(i, 5) * w)
		y2 := int(flat.GetFloatAt(i, 6) * h)

		// Clamp basique (évite coords négatives / out of bounds)
		if x1 < 0 {
			x1 = 0
		}
		if y1 < 0 {
			y1 = 0
		}
		if x2 < x1 {
			x2 = x1
		}
		if y2 < y1 {
			y2 = y1
		}

		out = append(out, Detection{
			ID: i,
			BBox: Rect{
				X:      x1,
				Y:      y1,
				Width:  x2 - x1,
				Height: y2 - y1,
			},
			Score:     float64(conf),
			Timestamp: now,
		})
	}

	return d.source, out
}

/* ------------------------------ Detector loop ----------------------------- */

func StartDetectorLoop(ctx context.Context, cfg DetectorConfig, store *FaceStore) {
	det, err := NewDNNDetector(cfg)
	if err != nil {
		log.Fatalf("[detector] init error: %v", err)
	}
	defer det.Close()

	ticker := time.NewTicker(cfg.Interval)
	defer ticker.Stop()

	var frame int64
	log.Printf("[detector] started (interval=%v, source=%s)", cfg.Interval, cfg.Source)

	for {
		select {
		case <-ctx.Done():
			log.Printf("[detector] stopping")
			return
		case <-ticker.C:
			frame++
			source, faces := det.Detect()
			store.Set(Snapshot{
				Source:      source,
				Frame:       frame,
				Detections:  faces,
				GeneratedAt: time.Now().UTC(),
			})
			// log.Printf("[detector] frame=%d faces=%d", frame, len(faces))
		}
	}
}

/* ------------------------------ HTTP server -------------------------------- */

func StartHTTPServer(ctx context.Context, addr string, store *FaceStore) error {
	mux := http.NewServeMux()

	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	mux.HandleFunc("/faces", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		w.Header().Set("Cache-Control", "no-store")

		snap, ver := store.Get()
		etag := `W/"` + toETag(ver, snap.Frame) + `"`
		if r.Header.Get("If-None-Match") == etag {
			w.WriteHeader(http.StatusNotModified)
			return
		}
		w.Header().Set("ETag", etag)

		enc := json.NewEncoder(w)
		enc.SetIndent("", "  ")
		_ = enc.Encode(snap)
	})

	srv := &http.Server{
		Addr:              addr,
		Handler:           loggingMiddleware(mux),
		ReadHeaderTimeout: 5 * time.Second,
	}

	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = srv.Shutdown(shutdownCtx)
	}()

	log.Printf("[http] listening on %s", addr)
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		return err
	}
	return nil
}

func loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t0 := time.Now()
		next.ServeHTTP(w, r)
		log.Printf("[http] %s %s %s", r.Method, r.URL.Path, time.Since(t0))
	})
}

/* --------------------------------- Utils ---------------------------------- */

func toETag(version uint64, frame int64) string {
	return strconv.FormatUint(version, 36) + "-" + strconv.FormatInt(frame, 36)
}

/* --------------------------------- Main ----------------------------------- */

func main() {
	prototxt := getenvRequired("FACE_PROTOTXT", "models/deploy.prototxt")
	model := getenvRequired("FACE_MODEL", "models/res10_300x300_ssd_iter_140000.caffemodel")
	source := getenvDefault("FACE_SOURCE", "0") // webcam 0 par défaut
	interval := getenvDurationDefault("FACE_INTERVAL", 200*time.Millisecond)
	conf := getenvFloat32Default("FACE_CONF", 0.5)

	store := &FaceStore{}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	go StartDetectorLoop(ctx, DetectorConfig{
		Source:       source,
		ProtoTxtPath: prototxt,
		ModelPath:    model,
		Interval:     interval,
		Confidence:   conf,
		InputW:       300,
		InputH:       300,
	}, store)

	if err := StartHTTPServer(ctx, ":8080", store); err != nil {
		log.Fatal(err)
	}
}

func getenvDefault(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func getenvRequired(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	if _, err := os.Stat(def); err == nil {
		return def
	}
	log.Fatalf("%s not set and default not found on disk: %s", k, def)
	return ""
}

func getenvDurationDefault(k string, def time.Duration) time.Duration {
	if v := os.Getenv(k); v != "" {
		if d, err := time.ParseDuration(v); err == nil {
			return d
		}
	}
	return def
}

func getenvFloat32Default(k string, def float32) float32 {
	if v := os.Getenv(k); v != "" {
		if f, err := strconv.ParseFloat(v, 32); err == nil {
			return float32(f)
		}
	}
	return def
}
