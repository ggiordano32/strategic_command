// Command scserver is the Strategic Command server: it serves the web
// build, collects playtest telemetry and stores co-op campaigns. See
// docs/SERVER.md. Every flag can also be set by an environment variable
// (SC_ADDR, SC_DATA_DIR, ...); flags win.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"strategiccommand/server/internal/server"
)

func env(k, def string) string {
	if v, ok := os.LookupEnv(k); ok {
		return v
	}
	return def
}

func envBool(k string, def bool) bool {
	if v, ok := os.LookupEnv(k); ok {
		b, err := strconv.ParseBool(v)
		if err == nil {
			return b
		}
	}
	return def
}

func main() {
	addr := flag.String("addr", env("SC_ADDR", ":8060"), "listen address (SC_ADDR)")
	data := flag.String("data", env("SC_DATA_DIR", "./data"), "data directory: database, backups, cache (SC_DATA_DIR)")
	web := flag.String("web", env("SC_WEB_DIR", "./build/web"), "web export directory (SC_WEB_DIR)")
	logs := flag.String("log-dir", env("SC_LOG_DIR", "./playtest_logs"), "telemetry JSONL directory (SC_LOG_DIR)")
	invite := flag.String("invite-key", env("SC_INVITE_KEY", ""), "if set, needed to create campaigns (SC_INVITE_KEY)")
	trusted := flag.String("trusted-proxy", env("SC_TRUSTED_PROXY", server.DefaultTrusted), "proxies whose X-Forwarded-For is believed, CIDRs (SC_TRUSTED_PROXY)")
	backupEvery := flag.Duration("backup-every", mustDur(env("SC_BACKUP_EVERY", "6h")), "periodic SQLite backup interval, 0 = off (SC_BACKUP_EVERY)")
	backupKeep := flag.Int("backup-keep", mustInt(env("SC_BACKUP_KEEP", "12")), "backups to keep (SC_BACKUP_KEEP)")
	compress := flag.Bool("compress", envBool("SC_COMPRESS", true), "precompress the web build (SC_COMPRESS)")
	brMax := flag.Bool("brotli-max", envBool("SC_BROTLI_MAX", true), "also make quality-11 brotli copies in the background (SC_BROTLI_MAX)")
	testMode := flag.Bool("test-mode", envBool("SC_TEST_MODE", false), "enable /api/test/* and any webhook URL: tests only (SC_TEST_MODE)")
	lease := flag.Duration("lease", mustDur(env("SC_LEASE", "120s")), "battle lease duration (SC_LEASE)")
	logLevel := flag.String("log-level", env("SC_LOG_LEVEL", "info"), "debug, info, warn, error (SC_LOG_LEVEL)")
	backupNow := flag.Bool("backup-now", false, "write one backup and exit")
	flag.Parse()

	var lvl slog.Level
	lvl.UnmarshalText([]byte(*logLevel))
	log := slog.New(slog.NewJSONHandler(os.Stderr, &slog.HandlerOptions{Level: lvl}))

	tp, err := server.ParsePrefixes(*trusted)
	if err != nil {
		fmt.Fprintln(os.Stderr, "bad -trusted-proxy:", err)
		os.Exit(2)
	}
	cfg := server.Config{Addr: *addr, DataDir: *data, WebDir: *web, LogDir: *logs, InviteKey: *invite,
		TrustedProxy: tp, BackupEvery: *backupEvery, BackupKeep: *backupKeep, TestMode: *testMode,
		CompressWeb: *compress, BrotliMax: *brMax, LeaseDuration: *lease}
	srv, err := server.New(cfg, log, nil)
	if err != nil {
		log.Error("startup failed", "err", err)
		os.Exit(1)
	}
	if *backupNow {
		p, err := srv.Backup()
		srv.Close()
		if err != nil {
			log.Error("backup failed", "err", err)
			os.Exit(1)
		}
		fmt.Println(p)
		return
	}
	if *testMode {
		log.Warn("TEST MODE: clock control and any webhook URL are enabled; never use this in production")
	}
	if _, err := os.Stat(strings.TrimRight(*web, "/") + "/index.html"); err != nil {
		log.Warn("no web build found; only the API will work", "web", *web)
	}
	srv.Start()
	hs := &http.Server{
		Addr:              *addr,
		Handler:           srv.Handler(),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       60 * time.Second,
		IdleTimeout:       120 * time.Second,
		MaxHeaderBytes:    32 << 10,
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	errc := make(chan error, 1)
	go func() {
		log.Info("listening", "addr", *addr, "data", *data, "web", *web, "log_dir", *logs,
			"invite_required", *invite != "", "version", server.Version)
		errc <- hs.ListenAndServe()
	}()
	select {
	case err := <-errc:
		if err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Error("server failed", "err", err)
			srv.Close()
			os.Exit(1)
		}
	case <-ctx.Done():
	}
	log.Info("shutting down")
	sctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	srv.Drain() // wake long-polls and close websockets first
	if err := hs.Shutdown(sctx); err != nil {
		log.Warn("shutdown", "err", err)
	}
	srv.Close()
	log.Info("stopped")
}

func mustDur(s string) time.Duration {
	d, err := time.ParseDuration(s)
	if err != nil {
		fmt.Fprintln(os.Stderr, "bad duration:", s)
		os.Exit(2)
	}
	return d
}

func mustInt(s string) int {
	n, err := strconv.Atoi(s)
	if err != nil {
		fmt.Fprintln(os.Stderr, "bad number:", s)
		os.Exit(2)
	}
	return n
}
