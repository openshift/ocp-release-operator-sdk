package http2

import (
	"bytes"
	"sync"
	"testing"

	"golang.org/x/net/http2/hpack"
)

// TestProcessSettingsRejectsInvalidMaxFrameSize exercises the
// processSettingsNoWrite function to verify it rejects invalid
// SETTINGS_MAX_FRAME_SIZE values per RFC 9113 Section 6.5.2.
//
// Before the fix for CVE-2026-33814 / GO-2026-4918,
// processSettingsNoWrite accepted any value for
// SETTINGS_MAX_FRAME_SIZE without calling Setting.Valid().
// With SETTINGS_MAX_FRAME_SIZE=0, writeHeaders enters an
// infinite loop writing zero-length CONTINUATION frames.
//
// This test FAILS on the vulnerable (unpatched) code because
// processSettingsNoWrite returns nil for invalid settings.
// It PASSES after the fix adds a s.Valid() call.
func TestProcessSettingsRejectsInvalidMaxFrameSize(t *testing.T) {
	tests := []struct {
		name    string
		val     uint32
		wantErr bool
	}{
		{"zero", 0, true},
		{"below_minimum", 16383, true},
		{"minimum_valid", 16384, false},
		{"above_maximum", 1 << 24, true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var buf bytes.Buffer
			fr := NewFramer(&buf, &buf)
			if err := fr.WriteSettings(Setting{ID: SettingMaxFrameSize, Val: tt.val}); err != nil {
				t.Fatal(err)
			}

			f, err := fr.ReadFrame()
			if err != nil {
				t.Fatal(err)
			}
			sf, ok := f.(*SettingsFrame)
			if !ok {
				t.Fatalf("expected SettingsFrame, got %T", f)
			}

			cc := &ClientConn{
				maxFrameSize:         16 << 10,
				maxConcurrentStreams: 1000,
				initialWindowSize:    65535,
				streams:              make(map[uint32]*clientStream),
				seenSettingsChan:     make(chan struct{}),
			}
			cc.cond = sync.NewCond(&cc.mu)
			cc.henc = hpack.NewEncoder(&cc.hbuf)

			rl := &clientConnReadLoop{cc: cc}

			err = rl.processSettingsNoWrite(sf)
			if tt.wantErr && err == nil {
				t.Errorf("processSettingsNoWrite accepted invalid SETTINGS_MAX_FRAME_SIZE=%d (cc.maxFrameSize=%d); want connection error",
					tt.val, cc.maxFrameSize)
			}
			if !tt.wantErr && err != nil {
				t.Errorf("processSettingsNoWrite rejected valid SETTINGS_MAX_FRAME_SIZE=%d: %v",
					tt.val, err)
			}
		})
	}
}
