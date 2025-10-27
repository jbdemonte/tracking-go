package main

import (
	"image"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"gocv.io/x/gocv"
)

func must(err error, what string) {
	if err != nil {
		log.Fatalf("%s: %v", what, err)
	}
}

func main() {
	// --- Camera
	cam, err := gocv.OpenVideoCapture(0)
	must(err, "open video capture")
	defer cam.Close()

	// Optionnel: tenter un format raisonnable (on ignore le bool de retour)
	cam.Set(gocv.VideoCaptureFrameWidth, 640)
	cam.Set(gocv.VideoCaptureFrameHeight, 480)
	cam.Set(gocv.VideoCaptureFPS, 30)

	// --- DNN face detector (Caffe)
	prototxt := "models/deploy.prototxt"
	model := "models/res10_300x300_ssd_iter_140000.caffemodel"

	if _, err := os.Stat(prototxt); err != nil {
		log.Fatalf("missing prototxt: %s", prototxt)
	}
	if _, err := os.Stat(model); err != nil {
		log.Fatalf("missing model: %s", model)
	}

	net := gocv.ReadNetFromCaffe(prototxt, model)
	if net.Empty() {
		log.Fatalf("failed to load DNN model")
	}
	defer net.Close()

	net.SetPreferableBackend(gocv.NetBackendDefault)
	net.SetPreferableTarget(gocv.NetTargetCPU)

	// --- loop
	img := gocv.NewMat()
	defer img.Close()

	// Stop propre (Ctrl+C)
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)

	log.Printf("ready: capturing camera and logging face boxes (no display)")
	lastLogNoFace := time.Time{}

	go func() {
		for {
			if ok := cam.Read(&img); !ok || img.Empty() {
				time.Sleep(10 * time.Millisecond)
				continue
			}

			// Blob pour le modèle SSD (taille 300, mean BGR 104,177,123)
			blob := gocv.BlobFromImage(img, 1.0, image.Pt(300, 300), gocv.NewScalar(104.0, 177.0, 123.0, 0), false, false)
			net.SetInput(blob, "")
			dets := net.Forward("")
			blob.Close()

			// dets est [1,1,N,7] -> reshape en [N,7] pour accès 2D i,j
			if dets.Empty() || dets.Total() < 7 {
				dets.Close()
				continue
			}
			rows := int(dets.Total() / 7)
			flat := dets.Reshape(1, rows) // channels=1, rows=N => cols=7
			dets.Close()
			defer flat.Close() // close à la fin de l'itération

			foundAny := false
			h := float32(img.Rows())
			w := float32(img.Cols())

			for i := 0; i < flat.Rows(); i++ {
				conf := flat.GetFloatAt(i, 2)
				if conf < 0.5 {
					continue
				}
				x1 := int(flat.GetFloatAt(i, 3) * w)
				y1 := int(flat.GetFloatAt(i, 4) * h)
				x2 := int(flat.GetFloatAt(i, 5) * w)
				y2 := int(flat.GetFloatAt(i, 6) * h)
				rect := image.Rect(x1, y1, x2, y2)

				foundAny = true
				log.Printf("face conf=%.2f box=[x=%d y=%d w=%d h=%d]",
					conf, rect.Min.X, rect.Min.Y, rect.Dx(), rect.Dy())
			}

			// log “no face” max 1/s pour éviter le spam
			if !foundAny {
				if time.Since(lastLogNoFace) >= time.Second {
					log.Printf("no face")
					lastLogNoFace = time.Now()
				}
			}

			flat.Close() // ferme avant de boucler
		}
	}()

	<-stop
	log.Println("stopping… bye")
}
