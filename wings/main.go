package main

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"

	"github.com/docker/docker/api/types"
	"github.com/docker/docker/api/types/container"
	"github.com/docker/docker/client"
)

const version = "0.7.0"

type Wings struct {
	secret                 string
	docker                 *client.Client
	panelURL, nodeID, root string
}

func sha256Hex(b []byte) string { h := sha256.Sum256(b); return hex.EncodeToString(h[:]) }
func parseInt64(s string) int64 { n, _ := strconv.ParseInt(s, 10, 64); return n }
func (w *Wings) signMaterial(r *http.Request, body []byte) string {
	ts := r.Header.Get("X-JZ-Timestamp")
	material := fmt.Sprintf("%s\n%s\n%s\n%s", ts, r.Method, r.URL.Path, sha256Hex(body))
	mac := hmac.New(sha256.New, []byte(w.secret))
	_, _ = mac.Write([]byte(material))
	return hex.EncodeToString(mac.Sum(nil))
}
func (w *Wings) auth(r *http.Request, body []byte) bool {
	sig, ts := r.Header.Get("X-JZ-Signature"), r.Header.Get("X-JZ-Timestamp")
	if sig == "" || ts == "" {
		return false
	}
	if d := time.Now().Unix() - parseInt64(ts); d > 60 || d < -60 {
		return false
	}
	want := w.signMaterial(r, body)
	a, e1 := hex.DecodeString(sig)
	b, e2 := hex.DecodeString(want)
	return e1 == nil && e2 == nil && hmac.Equal(a, b)
}
func (w *Wings) guard(next http.Handler) http.Handler {
	return http.HandlerFunc(func(rw http.ResponseWriter, r *http.Request) {
		body, err := io.ReadAll(io.LimitReader(r.Body, 8<<20))
		if err != nil {
			http.Error(rw, "invalid body", 400)
			return
		}
		r.Body = io.NopCloser(strings.NewReader(string(body)))
		if !w.auth(r, body) {
			http.Error(rw, "unauthorized", 401)
			return
		}
		next.ServeHTTP(rw, r)
	})
}
func jsonOut(rw http.ResponseWriter, v any) {
	rw.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(rw).Encode(v)
}
func ptrInt(v int) *int { return &v }
func (w *Wings) heartbeat() {
	if w.panelURL == "" || w.nodeID == "" {
		return
	}
	for {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		info, err := w.docker.Info(ctx)
		cancel()
		if err == nil {
			cpu, mu, mt, du, dt := hostMetrics()
			payload := map[string]any{"wings_version": version, "docker_version": info.ServerVersion, "cpu_percent": cpu, "ram_used_bytes": mu, "ram_total_bytes": mt, "disk_used_bytes": du, "disk_total_bytes": dt, "running_servers": info.ContainersRunning}
			body, _ := json.Marshal(payload)
			path := "/api/node/v1/heartbeat"
			ts := strconv.FormatInt(time.Now().Unix(), 10)
			material := fmt.Sprintf("%s\nPOST\n%s\n%s", ts, path, sha256Hex(body))
			mac := hmac.New(sha256.New, []byte(w.secret))
			_, _ = mac.Write([]byte(material))
			req, _ := http.NewRequest(http.MethodPost, strings.TrimRight(w.panelURL, "/")+path, strings.NewReader(string(body)))
			req.Header.Set("Content-Type", "application/json")
			req.Header.Set("X-JZ-Node-ID", w.nodeID)
			req.Header.Set("X-JZ-Timestamp", ts)
			req.Header.Set("X-JZ-Signature", hex.EncodeToString(mac.Sum(nil)))
			c := &http.Client{Timeout: 10 * time.Second}
			if resp, e := c.Do(req); e == nil {
				_ = resp.Body.Close()
			}
		}
		time.Sleep(10 * time.Second)
	}
}
func (w *Wings) safePath(id, rel string) (string, error) {
	if id == "" || strings.Contains(id, "/") || strings.Contains(id, "\\") || id == "." || id == ".." {
		return "", fmt.Errorf("invalid server id")
	}
	root, err := filepath.Abs(filepath.Join(w.root, id))
	if err != nil {
		return "", err
	}
	target, err := filepath.Abs(filepath.Join(root, filepath.Clean("/"+rel)))
	if err != nil {
		return "", err
	}
	if target != root && !strings.HasPrefix(target, root+string(os.PathSeparator)) {
		return "", fmt.Errorf("path traversal denied")
	}
	return target, nil
}
func (w *Wings) createServer(rw http.ResponseWriter, r *http.Request) {
	var b struct {
		ContainerID string   `json:"container_id"`
		Image       string   `json:"image"`
		Name        string   `json:"name"`
		Memory      int64    `json:"memory"`
		NanoCPUs    int64    `json:"nano_cpus"`
		Command     []string `json:"command"`
	}
	if err := json.NewDecoder(r.Body).Decode(&b); err != nil {
		http.Error(rw, "invalid request", 400)
		return
	}
	if b.ContainerID == "" {
		http.Error(rw, "container_id required", 400)
		return
	}
	if b.Image == "" {
		b.Image = "ubuntu:24.04"
	}
	if b.Memory < 0 || b.NanoCPUs < 0 {
		http.Error(rw, "invalid resource limits", 400)
		return
	}
	if b.Name == "" {
		b.Name = "jz-" + b.ContainerID
	}
	pull, err := w.docker.ImagePull(r.Context(), b.Image, types.ImagePullOptions{})
	if err != nil {
		http.Error(rw, "image pull failed", 502)
		return
	}
	_, _ = io.Copy(io.Discard, pull)
	_ = pull.Close()
	cfg := &container.Config{Image: b.Image, Cmd: b.Command, WorkingDir: "/home/container", Tty: true, OpenStdin: true, AttachStdout: true, AttachStderr: true}
	hc := &container.HostConfig{Memory: b.Memory, NanoCPUs: b.NanoCPUs}
	hostRoot, _ := filepath.Abs(filepath.Join(w.root, b.ContainerID))
	if err := os.MkdirAll(hostRoot, 0700); err != nil {
		http.Error(rw, "filesystem unavailable", 500)
		return
	}
	hc.Binds = []string{hostRoot + ":/home/container"}
	resp, err := w.docker.ContainerCreate(r.Context(), cfg, hc, nil, nil, b.Name)
	if err != nil {
		http.Error(rw, "container create failed", 409)
		return
	}
	jsonOut(rw, map[string]any{"ok": true, "container_id": resp.ID, "warnings": resp.Warnings})
}
func (w *Wings) fileAction(rw http.ResponseWriter, r *http.Request) {
	p := strings.TrimPrefix(r.URL.Path, "/v1/servers/")
	parts := strings.Split(strings.Trim(p, "/"), "/")
	if len(parts) < 2 {
		http.Error(rw, "bad path", 400)
		return
	}
	id := parts[0]
	action := parts[1]
	rel := r.URL.Query().Get("path")
	target, err := w.safePath(id, rel)
	if err != nil {
		http.Error(rw, err.Error(), 400)
		return
	}
	switch action {
	case "files-list":
		entries, e := os.ReadDir(target)
		if e != nil {
			http.Error(rw, "directory unavailable", 404)
			return
		}
		out := make([]map[string]any, 0, len(entries))
		for _, x := range entries {
			inf, _ := x.Info()
			out = append(out, map[string]any{"name": x.Name(), "directory": x.IsDir(), "size": func() int64 {
				if inf == nil {
					return 0
				}
				return inf.Size()
			}()})
		}
		jsonOut(rw, map[string]any{"ok": true, "path": rel, "entries": out})
	case "files-read":
		b, e := os.ReadFile(target)
		if e != nil {
			http.Error(rw, "file unavailable", 404)
			return
		}
		if len(b) > 8<<20 {
			http.Error(rw, "file too large", 413)
			return
		}
		jsonOut(rw, map[string]any{"ok": true, "path": rel, "content": string(b)})
	case "files-write":
		var body struct {
			Content string `json:"content"`
		}
		if json.NewDecoder(r.Body).Decode(&body) != nil {
			http.Error(rw, "invalid body", 400)
			return
		}
		if err := os.MkdirAll(filepath.Dir(target), 0700); err != nil {
			http.Error(rw, "directory unavailable", 500)
			return
		}
		if err := os.WriteFile(target, []byte(body.Content), 0600); err != nil {
			http.Error(rw, "write failed", 500)
			return
		}
		jsonOut(rw, map[string]any{"ok": true})
	case "files-mkdir":
		if err := os.MkdirAll(target, 0700); err != nil {
			http.Error(rw, "mkdir failed", 500)
			return
		}
		jsonOut(rw, map[string]any{"ok": true})
	case "files-delete":
		if err := os.RemoveAll(target); err != nil {
			http.Error(rw, "delete failed", 500)
			return
		}
		jsonOut(rw, map[string]any{"ok": true})
	default:
		http.Error(rw, "unsupported action", 400)
	}
}
func (w *Wings) serverAction(rw http.ResponseWriter, r *http.Request) {
	p := strings.TrimPrefix(r.URL.Path, "/v1/servers/")
	parts := strings.Split(strings.Trim(p, "/"), "/")
	if len(parts) != 2 {
		http.Error(rw, "bad path", 400)
		return
	}
	id, action := parts[0], parts[1]
	ctx := r.Context()
	var err error
	switch action {
	case "start":
		err = w.docker.ContainerStart(ctx, id, types.ContainerStartOptions{})
	case "stop":
		err = w.docker.ContainerStop(ctx, id, container.StopOptions{Timeout: ptrInt(10)})
	case "restart":
		err = w.docker.ContainerRestart(ctx, id, container.StopOptions{Timeout: ptrInt(10)})
	case "kill":
		err = w.docker.ContainerKill(ctx, id, "SIGKILL")
	case "delete":
		err = w.docker.ContainerRemove(ctx, id, types.ContainerRemoveOptions{Force: true, RemoveVolumes: false})
	case "command":
		var b struct { Command string `json:"command"` }
		if json.NewDecoder(r.Body).Decode(&b) != nil || strings.TrimSpace(b.Command) == "" { http.Error(rw, "command required", 400); return }
		ex, e := w.docker.ContainerExecCreate(ctx, id, types.ExecConfig{Cmd: []string{"/bin/sh", "-lc", b.Command}, AttachStdout: true, AttachStderr: true, Tty: false})
		if e != nil { http.Error(rw, "exec create failed", 409); return }
		stream, e := w.docker.ContainerExecAttach(ctx, ex.ID, types.ExecStartCheck{})
		if e != nil { http.Error(rw, "exec attach failed", 409); return }
		bout, _ := io.ReadAll(io.LimitReader(stream.Reader, 8<<20)); _ = stream.Close()
		info, _ := w.docker.ContainerExecInspect(ctx, ex.ID)
		jsonOut(rw, map[string]any{"ok": true, "output": string(bout), "exit_code": info.ExitCode})
		return
	case "logs":
		out, e := w.docker.ContainerLogs(ctx, id, types.ContainerLogsOptions{ShowStdout: true, ShowStderr: true, Tail: "200"})
		if e != nil {
			http.Error(rw, "logs unavailable", 409)
			return
		}
		defer out.Close()
		b, _ := io.ReadAll(io.LimitReader(out, 8<<20))
		jsonOut(rw, map[string]any{"ok": true, "logs": string(b)})
		return
	case "inspect":
		info, e := w.docker.ContainerInspect(ctx, id)
		if e != nil {
			http.Error(rw, "inspect failed", 404)
			return
		}
		jsonOut(rw, map[string]any{"ok": true, "container": info})
		return
	default:
		http.Error(rw, "unsupported action", 400)
		return
	}
	if err != nil {
		http.Error(rw, "docker operation failed", 409)
		return
	}
	jsonOut(rw, map[string]any{"ok": true, "server_id": id, "action": action})
}
func main() {
	dc, err := client.NewClientWithOpts(client.FromEnv, client.WithAPIVersionNegotiation())
	if err != nil {
		panic(err)
	}
	secret := os.Getenv("WINGS_SHARED_SECRET")
	if len(secret) < 16 {
		panic("WINGS_SHARED_SECRET is required")
	}
	root := os.Getenv("WINGS_SERVERS_ROOT")
	if root == "" {
		root = "/var/lib/jz-wings/servers"
	}
	if err := os.MkdirAll(root, 0700); err != nil {
		panic(err)
	}
	w := &Wings{secret: secret, docker: dc, panelURL: os.Getenv("JZ_PANEL_URL"), nodeID: os.Getenv("JZ_NODE_ID"), root: root}
	go w.heartbeat()
	mux := http.NewServeMux()
	mux.HandleFunc("/health", func(rw http.ResponseWriter, r *http.Request) {
		jsonOut(rw, map[string]any{"ok": true, "service": "jz-wings", "version": version, "go": runtime.Version(), "time": time.Now().UTC()})
	})
	mux.Handle("/v1/docker/info", w.guard(http.HandlerFunc(func(rw http.ResponseWriter, r *http.Request) {
		info, e := w.docker.Info(r.Context())
		if e != nil {
			http.Error(rw, "docker unavailable", 503)
			return
		}
		jsonOut(rw, map[string]any{"containers": info.Containers, "running": info.ContainersRunning, "paused": info.ContainersPaused, "stopped": info.ContainersStopped, "images": info.Images, "docker_version": info.ServerVersion, "os": info.OperatingSystem, "memory": info.MemTotal})
	})))
	mux.Handle("/v1/servers", w.guard(http.HandlerFunc(w.createServer)))
	mux.Handle("/v1/servers/", w.guard(http.HandlerFunc(func(rw http.ResponseWriter, r *http.Request) {
		if strings.Contains(r.URL.Path, "/files-") {
			w.fileAction(rw, r)
			return
		}
		w.serverAction(rw, r)
	})))
	addr := os.Getenv("WINGS_BIND")
	if addr == "" {
		addr = ":8080"
	}
	s := http.Server{Addr: addr, Handler: mux, ReadHeaderTimeout: 10 * time.Second, ReadTimeout: 30 * time.Second, WriteTimeout: 30 * time.Second, IdleTimeout: 60 * time.Second}
	fmt.Println("J&Z Wings listening on", addr)
	if err := s.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		panic(err)
	}
}
