//go:build linux

package main

import (
	"bufio"
	"fmt"
	"os"
	"syscall"
)

var previousTotal uint64
var previousIdle uint64

func hostMetrics() (float64, int64, int64, int64, int64) {
	var cpu float64
	if f, err := os.Open("/proc/stat"); err == nil {
		defer f.Close()
		sc := bufio.NewScanner(f)
		if sc.Scan() {
			var user, nice, system, idle, iowait, irq, softirq, steal uint64
			_, _ = fmt.Sscanf(sc.Text(), "cpu %d %d %d %d %d %d %d %d", &user, &nice, &system, &idle, &iowait, &irq, &softirq, &steal)
			total := user + nice + system + idle + iowait + irq + softirq + steal
			idleAll := idle + iowait
			if previousTotal > 0 && total > previousTotal {
				cpu = float64((total-previousTotal)-(idleAll-previousIdle)) * 100 / float64(total-previousTotal)
			}
			previousTotal = total
			previousIdle = idleAll
		}
	}
	var memTotal, memAvail int64
	if f, err := os.Open("/proc/meminfo"); err == nil {
		defer f.Close()
		sc := bufio.NewScanner(f)
		for sc.Scan() {
			var k string
			var v int64
			var unit string
			fmt.Sscanf(sc.Text(), "%s %d %s", &k, &v, &unit)
			switch k {
			case "MemTotal:":
				memTotal = v * 1024
			case "MemAvailable:":
				memAvail = v * 1024
			}
		}
	}
	var diskTotal, diskFree uint64
	var st syscall.Statfs_t
	if err := syscall.Statfs("/var/lib/jz-wings", &st); err == nil {
		diskTotal = st.Blocks * uint64(st.Bsize)
		diskFree = st.Bfree * uint64(st.Bsize)
	}
	return cpu, memTotal - memAvail, memTotal, int64(diskTotal - diskFree), int64(diskTotal)
}
