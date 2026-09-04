// This adapter runs the normal Bubble Tea terminal backend. The external PTY
// driver supplies frames, sends keys, and measures completed terminal output.
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"

	tea "charm.land/bubbletea/v2"
	"github.com/charmbracelet/colorprofile"
)

type workload struct {
	Width  int      `json:"width"`
	Height int      `json:"height"`
	FPS    int      `json:"fps"`
	Frames []string `json:"frames"`
}

func (w workload) validate() error {
	if w.Width <= 0 || w.Height <= 0 {
		return fmt.Errorf("width and height must be positive")
	}
	if w.FPS < 1 || w.FPS > 120 {
		return fmt.Errorf("fps must be between 1 and 120")
	}
	if len(w.Frames) != 2 || w.Frames[0] == w.Frames[1] {
		return fmt.Errorf("frames must contain two different screens")
	}
	for i, frame := range w.Frames {
		lines := strings.Split(frame, "\n")
		if len(lines) != w.Height {
			return fmt.Errorf("frame %d must have %d rows", i, w.Height)
		}
		for y, line := range lines {
			if len(line) != w.Width {
				return fmt.Errorf("frame %d row %d must have %d columns", i, y, w.Width)
			}
			for _, cell := range []byte(line) {
				if cell < ' ' || cell > '~' {
					return fmt.Errorf("frame %d must contain printable ASCII cells", i)
				}
			}
		}
	}
	return nil
}

type model struct {
	frames  []string
	counter uint64
}

func (m *model) Init() tea.Cmd { return nil }

func (m *model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	if key, ok := msg.(tea.KeyPressMsg); ok {
		switch key.String() {
		case "n":
			m.counter++
		case "q", "ctrl+c":
			return m, tea.Quit
		}
	}
	return m, nil
}

func (m *model) View() tea.View {
	return tea.View{Content: m.frames[m.counter%2], AltScreen: true}
}

func run() error {
	if len(os.Args) != 2 {
		return fmt.Errorf("usage: bubbletea-bench workload.json")
	}
	data, err := os.ReadFile(os.Args[1])
	if err != nil {
		return err
	}
	var spec workload
	if err := json.Unmarshal(data, &spec); err != nil {
		return fmt.Errorf("read workload: %w", err)
	}
	if err := spec.validate(); err != nil {
		return err
	}
	_, err = tea.NewProgram(
		&model{frames: spec.Frames},
		tea.WithFPS(spec.FPS),
		tea.WithWindowSize(spec.Width, spec.Height),
		tea.WithColorProfile(colorprofile.TrueColor),
	).Run()
	return err
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
