package main

import (
	"context"
	"log"
	"net/http"

	"golang.org/x/oauth2"
)

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		run()
	})

	http.ListenAndServe(":8080", nil)
}

func run() {
	config := &oauth2.Config{
		ClientID:     "YOUR_CLIENT_ID",
		ClientSecret: "YOUR_CLIENT_SECRET", // doesn't matter, just want to request to https://slack.com
		Endpoint: oauth2.Endpoint{
			TokenURL: "https://slack.com/api/oauth.access",
		},
		RedirectURL: "http://localhost:8080/", // doesn't case
	}

	token, err := config.Exchange(context.Background(), "YOUR_AUTH_CODE")
	if err != nil {
		log.Printf("Error: %v", err)
		return
	}

	log.Printf("Token: %s", token.AccessToken)
}
