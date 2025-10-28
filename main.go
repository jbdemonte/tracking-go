package main

import (
	"context"
	"encoding/json"
	"log"
	"math/rand"
	"net/http"
	"os/signal"
	"sync"
	"syscall"
	"time"
)

/* ---------------------------- Data definitions ---------------------------- */

// Rect is a bounding-box in pixels, relative to the original image.
type Rect struct {
	X      int `json:"x"`
	Y      int `json:"y"`
	Width  int `json:"width"`
	Height int `json:"height"`
}

// Point is a 2D landmark point (pixel coords).
type Point struct {
	X int `json:"x"`
	Y int `json:"y"`
}

// Detection represents a single detected face.
type Detection struct {
	ID        int       `json:"id"`
	BBox      Rect      `json:"bbox"`
	Landmarks []Point   `json:"landmarks,omitempty"`
	Score     float64   `json:"score"` // confidence/probability if available
	Timestamp time.Time `json:"ts"`
}

// Snapshot is the payload returned by /faces.
type Snapshot struct {
	Source     string      `json:"source"` // e.g. "camera0", "file:foo.jpg"
	Frame      int64       `json:"frame"`  // frame index if applicable
	Detections []Detection `json:"detections"`
}

/* --------------------------- Thread-safe storage -------------------------- */

type FaceStore struct {
	mu   sync.RWMutex
	snap Snapshot
}

func NewFaceStore() *FaceStore {
	return &FaceStore{}
}

// Set overwrites the latest snapshot (to be called by your detection loop).
func (s *FaceStore) Set(snap Snapshot) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.snap = snap
}

// Get returns a copy of the latest snapshot.
func (s *FaceStore) Get() Snapshot {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.snap
}

/* ------------------------------ HTTP server -------------------------------- */

func StartHTTPServer(ctx context.Context, addr string, store *FaceStore) error {
	mux := http.NewServeMux()

	// Health check
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	// Latest detections as JSON
	mux.HandleFunc("/faces", func(w http.ResponseWriter, r *http.Request) {
		// Simple CORS (optional)
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Content-Type", "application/json; charset=utf-8")

		// Optional cache busting
		w.Header().Set("Cache-Control", "no-store")

		snap := store.Get()

		enc := json.NewEncoder(w)
		enc.SetIndent("", "  ")
		if err := enc.Encode(snap); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
	})

	srv := &http.Server{
		Addr:              addr,
		Handler:           loggingMiddleware(mux),
		ReadHeaderTimeout: 5 * time.Second,
	}

	// Graceful shutdown
	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = srv.Shutdown(shutdownCtx)
	}()

	log.Printf("HTTP server listening on %s\n", addr)
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		return err
	}
	return nil
}

// loggingMiddleware adds minimal request logs.
func loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t0 := time.Now()
		next.ServeHTTP(w, r)
		log.Printf("%s %s %s", r.Method, r.URL.Path, time.Since(t0))
	})
}

/* --------------------------- Example integration --------------------------- */

func main() {
	// Create the shared store
	store := NewFaceStore()

	// Simulate your detection loop (replace with real detector)
	go fakeDetectorLoop(store)

	// OS signal handling + context
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	// Start HTTP server
	if err := StartHTTPServer(ctx, ":8080", store); err != nil {
		log.Fatal(err)
	}
}

// fakeDetectorLoop simulates updates from your face detector.
// Replace this with your real detection function and call store.Set(...) on each frame.
func fakeDetectorLoop(store *FaceStore) {
	ticker := time.NewTicker(800 * time.Millisecond)
	defer ticker.Stop()

	var frame int64
	for range ticker.C {
		frame++
		n := rand.Intn(3) // 0..2 faces
		dets := make([]Detection, 0, n)
		for i := 0; i < n; i++ {
			dets = append(dets, Detection{
				ID: i,
				BBox: Rect{
					X:      rand.Intn(800),
					Y:      rand.Intn(450),
					Width:  80 + rand.Intn(120),
					Height: 80 + rand.Intn(120),
				},
				Landmarks: []Point{
					{X: rand.Intn(1024), Y: rand.Intn(768)},
					{X: rand.Intn(1024), Y: rand.Intn(768)},
					{X: rand.Intn(1024), Y: rand.Intn(768)},
				},
				Score:     0.7 + rand.Float64()*0.3,
				Timestamp: time.Now().UTC(),
			})
		}

		store.Set(Snapshot{
			Source:     "camera0",
			Frame:      frame,
			Detections: dets,
		})
	}
}
