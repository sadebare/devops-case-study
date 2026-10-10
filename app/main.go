// Command items-api is a deliberately small REST API used to exercise the
// container, CI and Kubernetes tooling in this repository.
//
// It uses only the Go standard library, so there is no dependency tree to
// audit and the binary can run in a distroless "static" image.
package main

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
)

// version is set at build time with -ldflags "-X main.version=<git sha>".
var version = "dev"

type item struct {
	ID   int    `json:"id"`
	Name string `json:"name"`
}

type store struct {
	mu     sync.RWMutex
	nextID int
	items  map[int]item
}

func newStore() *store { return &store{nextID: 1, items: map[int]item{}} }

func (s *store) list() []item {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]item, 0, len(s.items))
	for id := 1; id < s.nextID; id++ {
		if it, ok := s.items[id]; ok {
			out = append(out, it)
		}
	}
	return out
}

func (s *store) get(id int) (item, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	it, ok := s.items[id]
	return it, ok
}

func (s *store) add(name string) item {
	s.mu.Lock()
	defer s.mu.Unlock()
	it := item{ID: s.nextID, Name: name}
	s.items[it.ID] = it
	s.nextID++
	return it
}

type server struct {
	store    *store
	apiToken string       // optional; when set, writes need "Authorization: Bearer <token>"
	ready    *atomic.Bool // flipped to false on shutdown so readiness fails first
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func (s *server) routes() http.Handler {
	mux := http.NewServeMux()

	// Liveness: the process is up and able to serve HTTP.
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok", "version": version})
	})
	// Readiness: the process wants traffic. Fails during graceful shutdown.
	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, _ *http.Request) {
		if !s.ready.Load() {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "shutting down"})
			return
		}
		writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
	})

	mux.HandleFunc("GET /api/v1/items", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, s.store.list())
	})
	mux.HandleFunc("GET /api/v1/items/{id}", func(w http.ResponseWriter, r *http.Request) {
		id, err := strconv.Atoi(r.PathValue("id"))
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "id must be an integer"})
			return
		}
		it, ok := s.store.get(id)
		if !ok {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "not found"})
			return
		}
		writeJSON(w, http.StatusOK, it)
	})
	mux.HandleFunc("POST /api/v1/items", func(w http.ResponseWriter, r *http.Request) {
		if !s.authorised(r) {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorised"})
			return
		}
		var in struct {
			Name string `json:"name"`
		}
		r.Body = http.MaxBytesReader(w, r.Body, 1<<16)
		if err := json.NewDecoder(r.Body).Decode(&in); err != nil || strings.TrimSpace(in.Name) == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "body must be JSON with a non-empty \"name\""})
			return
		}
		writeJSON(w, http.StatusCreated, s.store.add(strings.TrimSpace(in.Name)))
	})

	return mux
}

func (s *server) authorised(r *http.Request) bool {
	if s.apiToken == "" {
		return true
	}
	got := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
	return subtle.ConstantTimeCompare([]byte(got), []byte(s.apiToken)) == 1
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func main() {
	level := slog.LevelInfo
	_ = level.UnmarshalText([]byte(getenv("LOG_LEVEL", "info")))
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: level})))

	ready := &atomic.Bool{}
	ready.Store(true)
	s := &server{store: newStore(), apiToken: os.Getenv("API_TOKEN"), ready: ready}

	srv := &http.Server{
		Addr:              ":" + getenv("PORT", "8080"),
		Handler:           s.routes(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	go func() {
		slog.Info("listening", "addr", srv.Addr, "version", version)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			slog.Error("server failed", "error", err)
			os.Exit(1)
		}
	}()

	<-ctx.Done()
	// Fail readiness first and give the endpoints controller a moment to
	// remove this pod before we stop accepting connections.
	ready.Store(false)
	delay, _ := time.ParseDuration(getenv("SHUTDOWN_DELAY", "5s"))
	slog.Info("shutting down", "delay", delay.String())
	time.Sleep(delay)

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		slog.Error("graceful shutdown failed", "error", err)
		os.Exit(1)
	}
}
