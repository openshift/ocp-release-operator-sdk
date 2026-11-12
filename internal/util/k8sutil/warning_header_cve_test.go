// Copyright 2024 The Operator-SDK Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package k8sutil

import (
	"strings"
	"testing"
	"time"

	utilnet "k8s.io/apimachinery/pkg/util/net"
)

// TestParseWarningHeader_NormalText verifies that standard (non-RFC2047)
// warning headers still parse correctly after the RFC2047 decoding removal
// that dropped the mime.WordDecoder.DecodeHeader fallback.
func TestParseWarningHeader_NormalText(t *testing.T) {
	cases := []struct {
		name   string
		header string
		code   int
		agent  string
		text   string
	}{
		{
			name:   "simple deprecation warning",
			header: `299 - "this API version is deprecated"`,
			code:   299,
			agent:  "-",
			text:   "this API version is deprecated",
		},
		{
			name:   "named agent",
			header: `299 kube-apiserver "field xyz is deprecated"`,
			code:   299,
			agent:  "kube-apiserver",
			text:   "field xyz is deprecated",
		},
		{
			name:   "warning with escaped quote",
			header: `299 - "use \"newField\" instead"`,
			code:   299,
			agent:  "-",
			text:   `use "newField" instead`,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			result, remainder, err := utilnet.ParseWarningHeader(tc.header)
			if err != nil {
				t.Fatalf("Unexpected error: %v", err)
			}
			if remainder != "" {
				t.Errorf("Unexpected remainder: %q", remainder)
			}
			if result.Code != tc.code {
				t.Errorf("Code: got %d, want %d", result.Code, tc.code)
			}
			if result.Agent != tc.agent {
				t.Errorf("Agent: got %q, want %q", result.Agent, tc.agent)
			}
			if result.Text != tc.text {
				t.Errorf("Text: got %q, want %q", result.Text, tc.text)
			}
		})
	}
}

// TestParseWarningHeader_RFC2047Literal verifies that RFC2047-encoded warning
// text is returned in its literal encoded form after the RFC2047 decoding
// removal. Previously, the code decoded it via mime.WordDecoder.DecodeHeader;
// now the text passes through unchanged. This is correct per RFC7234 §5.5,
// which removed RFC2047 encoding from Warning headers.
func TestParseWarningHeader_RFC2047Literal(t *testing.T) {
	// This text contains an RFC2047 encoded-word for "André"
	encodedText := `=?UTF-8?B?QW5kcsOp?=`
	header := `299 - "` + encodedText + `"`

	result, _, err := utilnet.ParseWarningHeader(header)
	if err != nil {
		t.Fatalf("Unexpected error: %v", err)
	}
	// After RFC2047 decoding removal: text stays in encoded form
	if result.Text != encodedText {
		t.Errorf("Expected literal encoded text %q, got %q", encodedText, result.Text)
	}
}

// TestParseWarningHeader_ManyInvalidEncodedWords verifies that headers with
// many invalid encoded-words complete in bounded time (the removed
// mime.WordDecoder.DecodeHeader path had quadratic CPU complexity). After the
// RFC2047 decoding removal, DecodeHeader is not called at all, so this is a
// belt-and-suspenders check.
func TestParseWarningHeader_ManyInvalidEncodedWords(t *testing.T) {
	// Build a warning text with many =?...?= patterns that would have
	// triggered quadratic behaviour in the old DecodeHeader path
	var b strings.Builder
	for i := 0; i < 5000; i++ {
		b.WriteString("=?bad?x?y?= ")
	}
	text := strings.TrimSpace(b.String())
	header := `299 - "` + text + `"`

	done := make(chan struct{})
	go func() {
		_, _, _ = utilnet.ParseWarningHeader(header)
		close(done)
	}()

	select {
	case <-done:
		// completed promptly — pass
	case <-time.After(5 * time.Second):
		t.Fatal("ParseWarningHeader took >5s on crafted input — possible CPU exhaustion")
	}
}
