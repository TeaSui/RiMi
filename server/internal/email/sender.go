// Package email provides a pluggable EmailSender interface.
// Phase 1 ships an SMTP implementation (Mailpit for local, configurable for prod).
// EMAIL-06: tokens are delivered in the email body, never in query strings.
// PII-01/SECRETS-04: SMTP credentials come from env; never logged.
package email

import (
	"fmt"
	"net/smtp"
	"strings"
)

// Sender is the pluggable email interface.
type Sender interface {
	SendVerificationToken(to, token string) error
	SendPasswordResetToken(to, token string) error
}

// SMTPSender sends emails via SMTP.
type SMTPSender struct {
	host     string
	port     int
	user     string
	password string
	from     string
}

// NewSMTPSender constructs a sender. Credentials come from the config (env only).
func NewSMTPSender(host string, port int, user, password, from string) *SMTPSender {
	return &SMTPSender{
		host:     host,
		port:     port,
		user:     user,
		password: password,
		from:     from,
	}
}

// SendVerificationToken sends the email verification token to the user.
// EMAIL-06: the token is in the body, not a URL query string.
// Phase 1 interim flow: paste the token into the app.
func (s *SMTPSender) SendVerificationToken(to, token string) error {
	subject := "Verify your RiMi email"
	body := fmt.Sprintf("Your verification code is: %s\n\nPaste this code into the RiMi app to verify your email.", token)
	return s.send(to, subject, body)
}

// SendPasswordResetToken sends a password reset token.
func (s *SMTPSender) SendPasswordResetToken(to, token string) error {
	subject := "Reset your RiMi password"
	body := fmt.Sprintf("Your password reset code is: %s\n\nPaste this code into the RiMi app to reset your password.\n\nThis code expires in 30 minutes.", token)
	return s.send(to, subject, body)
}

func (s *SMTPSender) send(to, subject, body string) error {
	addr := fmt.Sprintf("%s:%d", s.host, s.port)
	msg := strings.Join([]string{
		"From: " + s.from,
		"To: " + to,
		"Subject: " + subject,
		"MIME-Version: 1.0",
		"Content-Type: text/plain; charset=utf-8",
		"",
		body,
	}, "\r\n")

	var auth smtp.Auth
	if s.user != "" && s.password != "" {
		auth = smtp.PlainAuth("", s.user, s.password, s.host)
	}

	if err := smtp.SendMail(addr, auth, s.from, []string{to}, []byte(msg)); err != nil {
		return fmt.Errorf("smtp send: %w", err)
	}
	return nil
}

// NoopSender silently drops emails (useful for tests that don't need Mailpit).
type NoopSender struct{}

func (n *NoopSender) SendVerificationToken(_, _ string) error    { return nil }
func (n *NoopSender) SendPasswordResetToken(_, _ string) error   { return nil }
