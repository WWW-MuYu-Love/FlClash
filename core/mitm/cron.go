package mitm

import (
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/metacubex/mihomo/log"
)

// cronSchedule is one parsed five-field cron expression (minute hour
// day-of-month month day-of-week), with Vixie semantics: when both the
// day-of-month and the day-of-week are restricted, either one matching
// fires the script.
type cronSchedule struct {
	minute [60]bool
	hour   [24]bool
	dom    [32]bool
	month  [13]bool
	dow    [7]bool
	domSet bool
	dowSet bool
}

var cronMonthNames = map[string]int{
	"jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
	"jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
}

var cronDowNames = map[string]int{
	"sun": 0, "mon": 1, "tue": 2, "wed": 3, "thu": 4, "fri": 5, "sat": 6,
}

func parseCron(expr string) (*cronSchedule, error) {
	fields := strings.Fields(expr)
	if len(fields) != 5 {
		return nil, fmt.Errorf("cron expression %q needs five fields", expr)
	}
	minute, _, err := parseCronField(fields[0], 0, 59, nil)
	if err != nil {
		return nil, fmt.Errorf("minute: %w", err)
	}
	hour, _, err := parseCronField(fields[1], 0, 23, nil)
	if err != nil {
		return nil, fmt.Errorf("hour: %w", err)
	}
	dom, domSet, err := parseCronField(fields[2], 1, 31, nil)
	if err != nil {
		return nil, fmt.Errorf("day-of-month: %w", err)
	}
	month, _, err := parseCronField(fields[3], 1, 12, cronMonthNames)
	if err != nil {
		return nil, fmt.Errorf("month: %w", err)
	}
	dow, dowSet, err := parseCronField(fields[4], 0, 7, cronDowNames)
	if err != nil {
		return nil, fmt.Errorf("day-of-week: %w", err)
	}
	s := &cronSchedule{domSet: domSet, dowSet: dowSet}
	for v := range minute {
		s.minute[v] = true
	}
	for v := range hour {
		s.hour[v] = true
	}
	for v := range dom {
		s.dom[v] = true
	}
	for v := range month {
		s.month[v] = true
	}
	for v := range dow {
		s.dow[v%7] = true
	}
	return s, nil
}

// parseCronField parses one field into its allowed values, reporting whether
// the field restricts anything: a bare * or ? does not. Items are *, a,
// a-b, a/n, a-b/n, and comma lists of those; month and day-of-week names
// are accepted, and 7 is Sunday.
func parseCronField(field string, min, max int, names map[string]int) (map[int]bool, bool, error) {
	field = strings.ToLower(strings.TrimSpace(field))
	if field == "" {
		return nil, false, fmt.Errorf("empty field")
	}
	set := map[int]bool{}
	if field == "*" || field == "?" {
		for v := min; v <= max; v++ {
			set[v] = true
		}
		return set, false, nil
	}
	for _, item := range strings.Split(field, ",") {
		item = strings.TrimSpace(item)
		if item == "" {
			return nil, false, fmt.Errorf("empty list item")
		}
		step := 1
		base := item
		if before, after, ok := strings.Cut(item, "/"); ok {
			base = before
			n, err := strconv.Atoi(strings.TrimSpace(after))
			if err != nil || n <= 0 {
				return nil, false, fmt.Errorf("bad step in %q", item)
			}
			step = n
		}
		lo, hi := min, max
		if base != "*" && base != "?" {
			if before, after, ok := strings.Cut(base, "-"); ok {
				var err error
				if lo, err = cronValue(before, names); err != nil {
					return nil, false, err
				}
				if hi, err = cronValue(after, names); err != nil {
					return nil, false, err
				}
			} else {
				v, err := cronValue(base, names)
				if err != nil {
					return nil, false, err
				}
				lo, hi = v, v
			}
		}
		if lo < min || hi > max || lo > hi {
			return nil, false, fmt.Errorf("value out of range in %q", item)
		}
		for v := lo; v <= hi; v += step {
			set[v] = true
		}
	}
	return set, true, nil
}

func cronValue(s string, names map[string]int) (int, error) {
	s = strings.ToLower(strings.TrimSpace(s))
	if names != nil {
		if v, ok := names[s]; ok {
			return v, nil
		}
	}
	v, err := strconv.Atoi(s)
	if err != nil {
		return 0, fmt.Errorf("bad value %q", s)
	}
	return v, nil
}

func (s *cronSchedule) matches(t time.Time) bool {
	if !s.minute[t.Minute()] || !s.hour[t.Hour()] || !s.month[int(t.Month())] {
		return false
	}
	domMatch := s.dom[t.Day()]
	dowMatch := s.dow[int(t.Weekday())]
	switch {
	case s.domSet && s.dowSet:
		return domMatch || dowMatch
	case s.domSet:
		return domMatch
	case s.dowSet:
		return dowMatch
	default:
		return true
	}
}

// next returns the first time strictly after from matching the schedule, or
// the zero time when nothing matches within four years.
func (s *cronSchedule) next(from time.Time) time.Time {
	t := from.Truncate(time.Minute).Add(time.Minute)
	for i := 0; i < 4*366*24*60; i++ {
		if s.matches(t) {
			return t
		}
		t = t.Add(time.Minute)
	}
	return time.Time{}
}

type cronEntry struct {
	name     string
	schedule *cronSchedule
}

func (e *Engine) cronEntries() []cronEntry {
	e.mu.RLock()
	lines := append([]string(nil), e.config.Script...)
	e.mu.RUnlock()
	var out []cronEntry
	for _, line := range lines {
		parsed := parseScriptLine(line)
		if parsed == nil || parsed.typ != "cron" {
			continue
		}
		schedule, err := parseCron(parsed.params["cronexp"])
		if err != nil {
			log.Warnln("[MITM] cron script %q: bad expression %q: %v", parsed.name, parsed.params["cronexp"], err)
			continue
		}
		out = append(out, cronEntry{name: parsed.name, schedule: schedule})
	}
	return out
}

// nextCron returns the earliest fire time after from and the scripts due
// then, or the zero time when nothing is scheduled.
func (e *Engine) nextCron(from time.Time) (time.Time, []cronEntry) {
	var next time.Time
	var due []cronEntry
	for _, entry := range e.cronEntries() {
		fire := entry.schedule.next(from)
		if fire.IsZero() {
			continue
		}
		if next.IsZero() || fire.Before(next) {
			next = fire
			due = []cronEntry{entry}
		} else if fire.Equal(next) {
			due = append(due, entry)
		}
	}
	return next, due
}

// StartCron starts the cron scheduler; it is idempotent, so a tunnel
// restart without a stop in between keeps the same loop.
func (e *Engine) StartCron() {
	e.cronMu.Lock()
	defer e.cronMu.Unlock()
	if e.cronRunning {
		return
	}
	e.cronStop = make(chan struct{})
	e.cronWake = make(chan struct{}, 1)
	e.cronRunning = true
	go e.cronLoop(e.cronStop, e.cronWake)
}

// StopCron stops the scheduler; a later StartCron starts a fresh loop.
func (e *Engine) StopCron() {
	e.cronMu.Lock()
	defer e.cronMu.Unlock()
	if !e.cronRunning {
		return
	}
	close(e.cronStop)
	e.cronRunning = false
}

func (e *Engine) wakeCron() {
	e.cronMu.Lock()
	defer e.cronMu.Unlock()
	if e.cronRunning {
		select {
		case e.cronWake <- struct{}{}:
		default:
		}
	}
}

func (e *Engine) cronLoop(stop, wake <-chan struct{}) {
	defer func() {
		if r := recover(); r != nil {
			log.Warnln("[MITM] cron loop stopped on panic: %v", r)
		}
	}()
	from := time.Now()
	for {
		next, due := e.nextCron(from)
		if next.IsZero() {
			select {
			case <-stop:
				return
			case <-wake:
				from = time.Now()
				continue
			}
		}
		timer := time.NewTimer(time.Until(next))
		select {
		case <-stop:
			timer.Stop()
			return
		case <-wake:
			timer.Stop()
			from = time.Now()
			continue
		case <-timer.C:
		}
		for _, entry := range due {
			if out := e.RunScript(entry.name); out.Error != "" {
				log.Warnln("[MITM] cron script %q: %v", entry.name, out.Error)
			}
		}
		from = next
	}
}
