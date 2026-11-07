package main

import (
	"regexp"
	"sort"
	"strconv"
	"strings"
)

var (
	kuwoLrcxHeaderRe   = regexp.MustCompile(`^\[kuwo:(\d+)`)
	kuwoLrcxLineRe     = regexp.MustCompile(`^\[(\d{1,3}):(\d{2})(?:\.(\d{1,3}))?\](.*)$`)
	kuwoLrcxWordTimeRe = regexp.MustCompile(`<(-?\d+),(-?\d+)(?:,-?\d+)?>`)
)

func kuwoLrcxCoefficients(text string) (k1, k2 int, ok bool) {
	for _, line := range strings.Split(text, "\n") {
		m := kuwoLrcxHeaderRe.FindStringSubmatch(strings.TrimSpace(line))
		if m == nil {
			continue
		}
		v, err := strconv.ParseInt(m[1], 8, 64)
		if err != nil {
			return 0, 0, false
		}
		k1, k2 = int(v/10), int(v%10)
		return k1, k2, k1 != 0 && k2 != 0
	}
	return 0, 0, false
}

// 两个数值按歌词头部给出的系数换算成相对行首的毫秒。
func kuwoLrcxWordTiming(a, b, k1, k2 int) (start, end int) {
	start = absInt(a+b) / (2 * k1)
	end = absInt(a-b)/(2*k2) + start
	return start, end
}

func absInt(v int) int {
	if v < 0 {
		return -v
	}
	return v
}

// parseLyrics 解码波点本地 LRC/LRCX。只剥离时间标记，原文与译文直接进入缓存。
func parseLyrics(raw string) []lyricLine {
	decoded := bodianDecodeLyrics(raw)
	decoded = strings.ReplaceAll(strings.ReplaceAll(decoded, "\r\n", "\n"), "\r", "\n")
	k1, k2, wordTimed := kuwoLrcxCoefficients(decoded)
	var lines []lyricLine
	var translation string
	var translationStamp int
	var endMarks []int
	for _, rawLine := range strings.Split(decoded, "\n") {
		m := kuwoLrcxLineRe.FindStringSubmatch(rawLine)
		if m == nil {
			continue
		}
		minute, _ := strconv.Atoi(m[1])
		second, _ := strconv.Atoi(m[2])
		fraction, _ := strconv.Atoi(m[3] + strings.Repeat("0", 3-len(m[3])))
		start := (minute*60+second)*1000 + fraction
		body := m[4]
		if !wordTimed {
			if strings.TrimSpace(body) == "" {
				endMarks = append(endMarks, start)
			} else {
				lines = append(lines, lyricLine{StartMs: start, Text: body})
			}
			continue
		}

		tokens := kuwoLrcxWordTimeRe.FindAllStringSubmatchIndex(body, -1)
		if len(tokens) == 0 {
			continue
		}
		line := lyricLine{StartMs: start}
		var text strings.Builder
		text.WriteString(body[:tokens[0][0]])
		allZero := true
		for i, token := range tokens {
			a, _ := strconv.Atoi(body[token[2]:token[3]])
			b, _ := strconv.Atoi(body[token[4]:token[5]])
			allZero = allZero && a == 0 && b == 0
			from, to := kuwoLrcxWordTiming(a, b, k1, k2)
			from, to = start+from, start+to
			if n := len(line.Words); n > 0 {
				last := &line.Words[n-1]
				if from < last.StartMs+last.DurationMs {
					last.StartMs = min(last.StartMs, from)
					last.DurationMs = from - last.StartMs
				}
			}
			textEnd := len(body)
			if i+1 < len(tokens) {
				textEnd = tokens[i+1][0]
			}
			word := body[token[1]:textEnd]
			text.WriteString(word)
			if i == 0 {
				word = body[:token[0]] + word
			}
			line.Words = append(line.Words, lyricWord{word, from, to - from})
		}
		line.Text = text.String()

		// A translation carries the following lyric's timestamp and all-zero
		// word markers. Blank all-zero rows are placeholders.
		if allZero {
			translation, translationStamp = line.Text, start
			continue
		}
		if translationStamp == start && strings.TrimSpace(translation) != "" && len(lines) > 0 {
			lines[len(lines)-1].Translation = translation
		}
		translation = ""
		if strings.TrimSpace(line.Text) == "" {
			continue
		}
		line.Words = mergeWhitespaceWords(line.Words)
		for _, word := range line.Words {
			line.EndMs = max(line.EndMs, word.StartMs+word.DurationMs)
		}
		lines = append(lines, line)
	}
	sort.SliceStable(lines, func(i, j int) bool { return lines[i].StartMs < lines[j].StartMs })
	if !wordTimed {
		// Line-timed caches have no word duration. Use the original engine's
		// assumed singing cap, or the explicit end mark or next line if sooner.
		for i := range lines {
			line := &lines[i]
			line.EndMs = line.StartMs + 8000
			if i+1 < len(lines) {
				line.EndMs = min(line.EndMs, lines[i+1].StartMs)
			}
			for _, end := range endMarks {
				if end > line.StartMs {
					line.EndMs = min(line.EndMs, end)
				}
			}
		}
	}
	return lines
}

// Whitespace carries its timing into the preceding word, as in the original
// YRC converter. Concatenating the result still yields the original text.
func mergeWhitespaceWords(words []lyricWord) []lyricWord {
	out := words[:0]
	prefix := ""
	for _, word := range words {
		if word.Text != "" && strings.TrimSpace(word.Text) == "" {
			if n := len(out); n > 0 {
				last := &out[n-1]
				last.Text += word.Text
				last.DurationMs = max(last.DurationMs, word.StartMs+word.DurationMs-last.StartMs)
			} else {
				prefix += word.Text
			}
			continue
		}
		word.Text = prefix + word.Text
		prefix = ""
		out = append(out, word)
	}
	return out
}
