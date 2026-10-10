package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
)

func newTestServer(token string) *server {
	ready := &atomic.Bool{}
	ready.Store(true)
	return &server{store: newStore(), apiToken: token, ready: ready}
}

func do(t *testing.T, h http.Handler, method, path, body string, headers map[string]string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestHealthAndReadiness(t *testing.T) {
	s := newTestServer("")
	h := s.routes()

	if rec := do(t, h, http.MethodGet, "/healthz", "", nil); rec.Code != http.StatusOK {
		t.Fatalf("healthz: got %d, want 200", rec.Code)
	}
	if rec := do(t, h, http.MethodGet, "/readyz", "", nil); rec.Code != http.StatusOK {
		t.Fatalf("readyz: got %d, want 200", rec.Code)
	}

	s.ready.Store(false)
	if rec := do(t, h, http.MethodGet, "/readyz", "", nil); rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("readyz while shutting down: got %d, want 503", rec.Code)
	}
	if rec := do(t, h, http.MethodGet, "/healthz", "", nil); rec.Code != http.StatusOK {
		t.Fatalf("healthz while shutting down: got %d, want 200", rec.Code)
	}
}

func TestItemsRoundTrip(t *testing.T) {
	h := newTestServer("").routes()

	rec := do(t, h, http.MethodPost, "/api/v1/items", `{"name":"  widget "}`, nil)
	if rec.Code != http.StatusCreated {
		t.Fatalf("create: got %d, want 201", rec.Code)
	}
	var created item
	if err := json.Unmarshal(rec.Body.Bytes(), &created); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if created.ID != 1 || created.Name != "widget" {
		t.Fatalf("create: got %+v", created)
	}

	rec = do(t, h, http.MethodGet, "/api/v1/items/1", "", nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("get: got %d, want 200", rec.Code)
	}

	rec = do(t, h, http.MethodGet, "/api/v1/items", "", nil)
	var list []item
	if err := json.Unmarshal(rec.Body.Bytes(), &list); err != nil || len(list) != 1 {
		t.Fatalf("list: got %q (err %v)", rec.Body.String(), err)
	}
}

func TestItemErrors(t *testing.T) {
	h := newTestServer("").routes()

	cases := []struct {
		name, method, path, body string
		want                     int
	}{
		{"missing item", http.MethodGet, "/api/v1/items/42", "", http.StatusNotFound},
		{"non-numeric id", http.MethodGet, "/api/v1/items/abc", "", http.StatusBadRequest},
		{"empty name", http.MethodPost, "/api/v1/items", `{"name":" "}`, http.StatusBadRequest},
		{"invalid json", http.MethodPost, "/api/v1/items", `{`, http.StatusBadRequest},
		{"wrong method", http.MethodDelete, "/api/v1/items", "", http.StatusMethodNotAllowed},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if rec := do(t, h, tc.method, tc.path, tc.body, nil); rec.Code != tc.want {
				t.Fatalf("got %d, want %d", rec.Code, tc.want)
			}
		})
	}
}

func TestWritesRequireTokenWhenConfigured(t *testing.T) {
	h := newTestServer("s3cret").routes()
	body := `{"name":"widget"}`

	if rec := do(t, h, http.MethodPost, "/api/v1/items", body, nil); rec.Code != http.StatusUnauthorized {
		t.Fatalf("no token: got %d, want 401", rec.Code)
	}
	bad := map[string]string{"Authorization": "Bearer nope"}
	if rec := do(t, h, http.MethodPost, "/api/v1/items", body, bad); rec.Code != http.StatusUnauthorized {
		t.Fatalf("wrong token: got %d, want 401", rec.Code)
	}
	good := map[string]string{"Authorization": "Bearer s3cret"}
	if rec := do(t, h, http.MethodPost, "/api/v1/items", body, good); rec.Code != http.StatusCreated {
		t.Fatalf("right token: got %d, want 201", rec.Code)
	}
	// Reads stay open.
	if rec := do(t, h, http.MethodGet, "/api/v1/items", "", nil); rec.Code != http.StatusOK {
		t.Fatalf("read: got %d, want 200", rec.Code)
	}
}
