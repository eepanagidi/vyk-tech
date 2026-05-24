package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"time"

	_ "github.com/go-sql-driver/mysql"
)

// ── Domain model ─────────────────────────────────────────────────────────────

type Item struct {
	ID        int       `json:"id"`
	Name      string    `json:"name"`
	CreatedAt time.Time `json:"created_at"`
}

type CreateItemRequest struct {
	Name string `json:"name"`
}

type HealthResponse struct {
	Status   string `json:"status"`
	Database string `json:"database"`
}

// ── Server ────────────────────────────────────────────────────────────────────

type Server struct {
	db *sql.DB
}

func main() {
	dsn := buildDSN()
	db, err := connectWithRetry(dsn, 30, 2*time.Second)
	if err != nil {
		log.Fatalf("failed to connect to database: %v", err)
	}
	defer db.Close()

	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(10)
	db.SetConnMaxLifetime(5 * time.Minute)

	srv := &Server{db: db}

	mux := http.NewServeMux()
	mux.HandleFunc("/", srv.handleRoot)         // greeting on "/", 404 otherwise
	mux.HandleFunc("/healthz", srv.handleLivez) // liveness/startup — no DB dependency
	mux.HandleFunc("/health", srv.handleHealth) // readiness — checks DB connectivity
	mux.HandleFunc("/items", srv.handleItems)
	mux.HandleFunc("/items/", srv.handleItemByID)

	port := getEnv("PORT", "8080")
	log.Printf("vyking-backend listening on :%s", port)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Fatalf("server error: %v", err)
	}
}

// ── Handlers ──────────────────────────────────────────────────────────────────

// handleRoot returns a friendly greeting on "/" (the frontend proxies this as
// /api/) and 404 for any other unmatched path.
func (s *Server) handleRoot(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	fmt.Fprintln(w, "Hello from Vyking Backend!")
}

// handleLivez is a liveness/startup probe with NO external dependencies — it
// only reports that the process is up. DB connectivity is checked by readiness
// (/health), so a transient DB blip never triggers a pod restart.
func (s *Server) handleLivez(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	fmt.Fprintln(w, "ok")
}

// handleHealth is the readiness probe — 200 only when the DB is reachable.
func (s *Server) handleHealth(w http.ResponseWriter, _ *http.Request) {
	resp := HealthResponse{Status: "ok", Database: "ok"}
	status := http.StatusOK
	if err := s.db.Ping(); err != nil {
		resp.Database = "unreachable"
		status = http.StatusServiceUnavailable
	}
	writeJSON(w, status, resp)
}

func (s *Server) handleItems(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		s.listItems(w, r)
	case http.MethodPost:
		s.createItem(w, r)
	default:
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

func (s *Server) handleItemByID(w http.ResponseWriter, r *http.Request) {
	idStr := r.URL.Path[len("/items/"):]
	id, err := strconv.Atoi(idStr)
	if err != nil {
		http.Error(w, "invalid id", http.StatusBadRequest)
		return
	}
	switch r.Method {
	case http.MethodGet:
		s.getItem(w, r, id)
	case http.MethodDelete:
		s.deleteItem(w, r, id)
	default:
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

// ── CRUD operations ───────────────────────────────────────────────────────────

func (s *Server) listItems(w http.ResponseWriter, _ *http.Request) {
	rows, err := s.db.Query("SELECT id, name, created_at FROM items ORDER BY id DESC LIMIT 100")
	if err != nil {
		http.Error(w, "db error", http.StatusInternalServerError)
		log.Printf("listItems query error: %v", err)
		return
	}
	defer rows.Close()

	items := []Item{}
	for rows.Next() {
		var it Item
		if err := rows.Scan(&it.ID, &it.Name, &it.CreatedAt); err != nil {
			log.Printf("listItems scan error: %v", err)
			continue
		}
		items = append(items, it)
	}
	writeJSON(w, http.StatusOK, items)
}

func (s *Server) createItem(w http.ResponseWriter, r *http.Request) {
	var req CreateItemRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Name == "" {
		http.Error(w, "name is required", http.StatusBadRequest)
		return
	}
	res, err := s.db.Exec("INSERT INTO items (name) VALUES (?)", req.Name)
	if err != nil {
		http.Error(w, "db error", http.StatusInternalServerError)
		log.Printf("createItem exec error: %v", err)
		return
	}
	id, _ := res.LastInsertId()
	item := Item{ID: int(id), Name: req.Name, CreatedAt: time.Now()}
	writeJSON(w, http.StatusCreated, item)
}

func (s *Server) getItem(w http.ResponseWriter, _ *http.Request, id int) {
	var it Item
	err := s.db.QueryRow("SELECT id, name, created_at FROM items WHERE id = ?", id).
		Scan(&it.ID, &it.Name, &it.CreatedAt)
	if err == sql.ErrNoRows {
		http.Error(w, "not found", http.StatusNotFound)
		return
	}
	if err != nil {
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, it)
}

func (s *Server) deleteItem(w http.ResponseWriter, _ *http.Request, id int) {
	res, err := s.db.Exec("DELETE FROM items WHERE id = ?", id)
	if err != nil {
		http.Error(w, "db error", http.StatusInternalServerError)
		return
	}
	affected, _ := res.RowsAffected()
	if affected == 0 {
		http.Error(w, "not found", http.StatusNotFound)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// ── Helpers ───────────────────────────────────────────────────────────────────

func buildDSN() string {
	return fmt.Sprintf("%s:%s@tcp(%s:%s)/%s?parseTime=true&timeout=5s",
		getEnv("MYSQL_USER", "appuser"),
		getEnv("MYSQL_PASSWORD", ""),
		getEnv("MYSQL_HOST", "localhost"),
		getEnv("MYSQL_PORT", "3306"),
		getEnv("MYSQL_DATABASE", "appdb"),
	)
}

func connectWithRetry(dsn string, attempts int, delay time.Duration) (*sql.DB, error) {
	for i := 1; i <= attempts; i++ {
		db, err := sql.Open("mysql", dsn)
		if err == nil {
			if err = db.Ping(); err == nil {
				log.Printf("connected to database (attempt %d/%d)", i, attempts)
				return db, nil
			}
		}
		log.Printf("database not ready (attempt %d/%d): %v", i, attempts, err)
		time.Sleep(delay)
	}
	return nil, fmt.Errorf("could not connect after %d attempts", attempts)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
