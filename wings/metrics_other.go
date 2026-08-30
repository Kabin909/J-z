//go:build !linux

package main

// J&Z Wings keeps a portable build path for development on Windows/macOS.
// Production node telemetry is fully implemented on Linux; Docker operations
// still use the Docker API and can be pointed at a local/remote daemon through
// DOCKER_HOST. Unsupported host telemetry reports zeroes instead of crashing.
func hostMetrics() (float64, int64, int64, int64, int64) {
	return 0, 0, 0, 0, 0
}
