// edgecheck reads an Edge config.json on stdin and loads it with the Edge's own
// loader, so the chart's rendered config is checked against the real validation.
// It is built by run.sh via `go build -overlay`, which injects this file into
// the Edge module without writing to the Edge checkout.
package main

import (
	"fmt"
	"os"

	"github.com/NOFireAI/agent/internal/edge/config"
)

func main() {
	if _, err := config.LoadConfigFromReader(os.Stdin); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
