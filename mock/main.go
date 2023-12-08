package main

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"io"
	"log"
	"log/slog"
	"math/big"
	"net/http"
	"os"
	"time"
)

func init() {
	slog.SetDefault(NewLogger(os.Stderr))
}

func main() {
	http.HandleFunc("/api/oauth2.access", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{
    "access_token": "xoxp-XXXXXXXX-XXXXXXXX-XXXXX",
    "token_type": "bearer",
    "expires_in": 1000,
}`))
	})

	httpServer := &http.Server{Addr: ":8080", Handler: LoggingHandler(http.DefaultServeMux)}
	httpsServer := &http.Server{Addr: ":8443", Handler: LoggingHandler(http.DefaultServeMux)}
	httpsServer.TLSConfig = &tls.Config{
		NextProtos:         []string{"http/1.1"},
		Certificates:       []tls.Certificate{genX509KeyPair()},
		InsecureSkipVerify: true,
		VerifyPeerCertificate: func(rawCerts [][]byte, verifiedChains [][]*x509.Certificate) error {
			return nil
		},
		VerifyConnection: func(state tls.ConnectionState) error {
			return nil
		},
	}

	go func() {
		if err := httpServer.ListenAndServe(); err != nil {
			log.Println(err)
		}
	}()
	go func() {
		if err := httpsServer.ListenAndServeTLS("", ""); err != nil {
			log.Println(err)
		}
	}()
}

func genX509KeyPair() tls.Certificate {
	now := time.Now()
	template := &x509.Certificate{
		SerialNumber: big.NewInt(now.Unix()),
		DNSNames: []string{
			"slack.com",
		},
		Subject: pkix.Name{
			CommonName:         "slack.com",
			Country:            []string{"US"},
			Organization:       []string{"slack.com"},
			OrganizationalUnit: []string{"slack"},
		},
		NotBefore:             now,
		NotAfter:              now.AddDate(0, 0, 1), // Valid for one day
		SubjectKeyId:          []byte{113, 117, 105, 99, 107, 115, 101, 114, 118, 101},
		BasicConstraintsValid: true,
		IsCA:                  true,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		KeyUsage: x509.KeyUsageKeyEncipherment |
			x509.KeyUsageDigitalSignature | x509.KeyUsageCertSign,
	}

	priv, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		panic(err)
	}

	cert, err := x509.CreateCertificate(rand.Reader, template, template,
		priv.Public(), priv)
	if err != nil {
		panic(err)
	}

	var outCert tls.Certificate
	outCert.Certificate = append(outCert.Certificate, cert)
	outCert.PrivateKey = priv

	return outCert
}

func LoggingHandler(h http.Handler) http.Handler {
	lh := &loggingHandler{
		orig: h,
	}
	return lh
}

type loggingHandler struct {
	orig          http.Handler
	getClientAddr func(http.Header) string
}

func (h *loggingHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	st := time.Now()
	ctx := r.Context()
	logger := slog.Default()
	reqAttrs := []any{
		slog.Time("start_at", st),
		slog.String("remote_address", r.RemoteAddr),
		slog.String("method", r.Method),
		slog.String("host", r.Host),
		slog.String("protocol", r.Proto),
		slog.String("path", r.URL.Path),
	}
	reqAttr := slog.Group("request", reqAttrs...)
	h.orig.ServeHTTP(w, r)
	respAttr := slog.Group("response",
		slog.Duration("elapsed", time.Since(st)),
	)
	logger.InfoContext(ctx, "http access", slog.Group("http", reqAttr, respAttr))
}

// NewLogger creates a *slog.Logger that outputs one-line JSON logs to w.
func NewLogger(w io.Writer) *slog.Logger {
	var h slog.Handler
	h = slog.NewJSONHandler(w, &slog.HandlerOptions{})
	logger := slog.New(h)
	hname, err := os.Hostname()
	if err == nil {
		logger = logger.With(slog.String("hostname", hname))
	}
	return logger
}
