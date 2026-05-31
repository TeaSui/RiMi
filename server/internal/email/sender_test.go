// Package email — tests for the email sender implementations.
package email

import (
	"testing"
)

// TestNewSMTPSender verifies the constructor.
func TestNewSMTPSender(t *testing.T) {
	s := NewSMTPSender("localhost", 1025, "user", "pass", "from@test.com")
	if s == nil {
		t.Fatal("expected non-nil sender")
	}
	if s.host != "localhost" {
		t.Errorf("host: got %q", s.host)
	}
	if s.port != 1025 {
		t.Errorf("port: got %d", s.port)
	}
	if s.from != "from@test.com" {
		t.Errorf("from: got %q", s.from)
	}
}

// TestSMTPSenderInterface verifies SMTPSender satisfies the Sender interface.
func TestSMTPSenderInterface(t *testing.T) {
	var _ Sender = &SMTPSender{}
	var _ Sender = &NoopSender{}
}

// TestNoopSenderNeverErrors verifies the noop sender always returns nil.
func TestNoopSenderNeverErrors(t *testing.T) {
	s := &NoopSender{}
	if err := s.SendVerificationToken("any@test.com", "token"); err != nil {
		t.Errorf("SendVerificationToken: %v", err)
	}
	if err := s.SendPasswordResetToken("any@test.com", "token"); err != nil {
		t.Errorf("SendPasswordResetToken: %v", err)
	}
}

// TestSMTPSenderFailsWithoutServer verifies that SendMail fails when there's no
// SMTP server at the configured address. This exercises the send() method's error path.
func TestSMTPSenderFailsWithoutServer(t *testing.T) {
	// Use port 19999 which is almost certainly not listening.
	s := NewSMTPSender("127.0.0.1", 19999, "", "", "from@test.com")

	// Should fail because no server is listening.
	err := s.SendVerificationToken("to@test.com", "token123")
	if err == nil {
		t.Error("expected error when no SMTP server is listening")
	}
	// The error path is now covered.
}
