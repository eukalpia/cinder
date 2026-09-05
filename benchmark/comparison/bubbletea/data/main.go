// The workspace-v1 workload uses Bubble Tea's normal Update/View loop.
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"strings"

	tea "charm.land/bubbletea/v2"
	"github.com/charmbracelet/colorprofile"
)

type record struct {
	ID      int    `json:"id"`
	Service string `json:"service"`
	Level   string `json:"level"`
	Score   int    `json:"score"`
	Message string `json:"message"`
}
type workload struct {
	Width   int      `json:"width"`
	Height  int      `json:"height"`
	FPS     int      `json:"fps"`
	Records []record `json:"records"`
}
type model struct {
	width, page, cursor, top, step int
	records, matches               []record
	selected                       map[int]bool
	query, order                   string
	errors                         bool
	logs                           []string
}

var labels = map[string]string{"j": "down", "k": "up", "p": "page", "g": "home", "G": "end", "x": "select", "f": "search", "e": "errors", "s": "sort", "a": "append"}

func (m *model) rebuild() {
	m.matches = make([]record, 0, len(m.records))
	for _, row := range m.records {
		if (!m.errors || row.Level == "ERROR") && strings.Contains(strings.ToLower(row.Service+" "+row.Level+" "+row.Message), m.query) {
			m.matches = append(m.matches, row)
		}
	}
	if m.order != "id" {
		sort.Slice(m.matches, func(i, j int) bool {
			a, b := m.matches[i], m.matches[j]
			if a.Score == b.Score {
				return a.ID < b.ID
			}
			if m.order == "score-desc" {
				return a.Score > b.Score
			}
			return a.Score < b.Score
		})
	}
	m.cursor, m.top = 0, 0
}
func (m *model) apply(key string) {
	label, ok := labels[key]
	if !ok {
		return
	}
	m.step++
	switch key {
	case "j":
		m.cursor++
	case "k":
		m.cursor--
	case "p":
		m.cursor += m.page
	case "g":
		m.cursor = 0
	case "G":
		m.cursor = len(m.matches) - 1
	case "x":
		if len(m.matches) > 0 {
			id := m.matches[m.cursor].ID
			if m.selected[id] {
				delete(m.selected, id)
			} else {
				m.selected[id] = true
			}
		}
	case "f":
		if m.query == "" {
			m.query = "needle"
		} else {
			m.query = ""
		}
		m.rebuild()
	case "e":
		m.errors = !m.errors
		m.rebuild()
	case "s":
		if m.order == "score-desc" {
			m.order = "score-asc"
		} else {
			m.order = "score-desc"
		}
		m.rebuild()
	case "a":
		id := len(m.records)
		word := "regular"
		if id%97 == 0 {
			word = "needle"
		}
		m.records = append(m.records, record{id, fmt.Sprintf("service-%02d", id%17), []string{"INFO", "WARN", "ERROR", "DEBUG"}[id%4], id * 37 % 10000, fmt.Sprintf("request %06d %s", id, word)})
		m.rebuild()
	}
	m.cursor = max(0, min(m.cursor, len(m.matches)-1))
	if m.cursor < m.top {
		m.top = m.cursor
	}
	if m.cursor >= m.top+m.page {
		m.top = m.cursor - m.page + 1
	}
	m.logs = append(m.logs, fmt.Sprintf("%06d %s cursor=%d matches=%d", m.step, label, m.cursor, len(m.matches)))
	if len(m.logs) > 3 {
		m.logs = m.logs[len(m.logs)-3:]
	}
}
func (m *model) Init() tea.Cmd { return nil }
func (m *model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	if key, ok := msg.(tea.KeyPressMsg); ok {
		if key.String() == "q" {
			return m, tea.Quit
		}
		m.apply(key.String())
	}
	return m, nil
}
func (m *model) View() tea.View {
	query := m.query
	if query == "" {
		query = "-"
	}
	errors := 0
	if m.errors {
		errors = 1
	}
	lines := []string{
		fmt.Sprintf("Workspace step=%06d rows=%d matches=%d selected=%d", m.step, len(m.records), len(m.matches), len(m.selected)),
		fmt.Sprintf("query=%s errors=%d sort=%s cursor=%d top=%d", query, errors, m.order, m.cursor, m.top),
		"   ID     SERVICE    LEVEL SCORE MESSAGE",
	}
	for index := m.top; index < m.top+m.page; index++ {
		if index >= len(m.matches) {
			lines = append(lines, "")
			continue
		}
		row := m.matches[index]
		cursor, selected := " ", " "
		if index == m.cursor {
			cursor = ">"
		}
		if m.selected[row.ID] {
			selected = "*"
		}
		lines = append(lines, fmt.Sprintf("%s%s %06d %s %-5s %04d %s", cursor, selected, row.ID, row.Service, row.Level, row.Score, row.Message))
	}
	lines = append(lines, "Event log")
	for i := len(m.logs); i < 3; i++ {
		lines = append(lines, "")
	}
	lines = append(lines, m.logs...)
	lines = append(lines, "j/k move  p page  g/G home/end  x select  f search  e errors  s sort  a append  q quit")
	for i, line := range lines {
		if len(line) > m.width {
			line = line[:m.width]
		}
		lines[i] = line + strings.Repeat(" ", m.width-len(line))
	}
	return tea.View{Content: strings.Join(lines, "\n"), AltScreen: true}
}
func main() {
	if len(os.Args) != 2 {
		panic("usage: bubbletea-data workload.json")
	}
	data, err := os.ReadFile(os.Args[1])
	if err != nil {
		panic(err)
	}
	var spec workload
	if err = json.Unmarshal(data, &spec); err != nil {
		panic(err)
	}
	m := &model{width: spec.Width, page: spec.Height - 8, records: spec.Records, matches: append([]record(nil), spec.Records...), selected: map[int]bool{}, order: "id", logs: []string{"ready"}}
	if _, err = tea.NewProgram(m, tea.WithFPS(spec.FPS), tea.WithWindowSize(spec.Width, spec.Height), tea.WithColorProfile(colorprofile.TrueColor)).Run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
