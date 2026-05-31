package middleware

import (
	"strings"
	"testing"
)

// TestMaskEmail verifies PII-01 email masking.
func TestMaskEmail(t *testing.T) {
	cases := []struct {
		input string
		want  string
	}{
		{"user@example.com", "us***@***.com"},
		{"ab@b.co", "ab***@***.co"},
		{"notanemail", "***"},
		{"", "***"},
	}
	for _, tc := range cases {
		got := MaskEmail(tc.input)
		if got != tc.want {
			t.Errorf("MaskEmail(%q) = %q, want %q", tc.input, got, tc.want)
		}
	}
}

// TestMaskPhone verifies PII-01 phone masking.
func TestMaskPhone(t *testing.T) {
	cases := []struct {
		input string
		want  string
	}{
		{"+84912345678", "+84****5678"},
		{"short", "***"},
	}
	for _, tc := range cases {
		got := MaskPhone(tc.input)
		if got != tc.want {
			t.Errorf("MaskPhone(%q) = %q, want %q", tc.input, got, tc.want)
		}
	}
}

// TestMaskEmailNoPIILeak ensures the masked form contains no useful PII.
func TestMaskEmailNoPIILeak(t *testing.T) {
	email := "john.doe@company.org"
	masked := MaskEmail(email)
	// The full local-part should not appear.
	if strings.Contains(masked, "john.doe") {
		t.Errorf("masked email leaks local-part: %q", masked)
	}
	// The full domain should not appear.
	if strings.Contains(masked, "company") {
		t.Errorf("masked email leaks domain: %q", masked)
	}
}
