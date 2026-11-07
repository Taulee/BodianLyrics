package main

import (
	"encoding/json"
	"errors"
	"os"
	"time"
	"unicode/utf16"
)

type lyricWord struct {
	Text       string `json:"text"`
	StartMs    int    `json:"startMs"`
	DurationMs int    `json:"durationMs"`
}

type lyricLine struct {
	StartMs     int         `json:"startMs"`
	EndMs       int         `json:"endMs"`
	Text        string      `json:"text"`
	Words       []lyricWord `json:"words"`
	Translation string      `json:"translation,omitempty"`
}

type parsedLyrics struct {
	Modified time.Time   `json:"modified"`
	Size     int64       `json:"size"`
	Lines    []lyricLine `json:"lines"`
}

func bodianDecodeLyrics(raw string) string {
	const key = "BD1BYDH79nXZ"
	units := utf16.Encode([]rune(raw))
	for i := range units {
		units[i] ^= uint16(key[i%len(key)])
	}
	return string(utf16.Decode(units))
}

func readParsed(path string) (parsedLyrics, error) {
	var parsed parsedLyrics
	raw, err := os.ReadFile(path)
	if err != nil {
		return parsed, err
	}
	err = json.Unmarshal(raw, &parsed)
	return parsed, err
}

func refreshLyrics(source, destination string) error {
	info, err := os.Stat(source)
	if err != nil {
		return err
	}
	parsed, err := readParsed(destination)
	if err == nil && parsed.Size == info.Size() && parsed.Modified.Equal(info.ModTime()) {
		return nil
	}
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	raw, err := os.ReadFile(source)
	if err != nil {
		return err
	}
	parsed = parsedLyrics{Modified: info.ModTime(), Size: info.Size(), Lines: parseLyrics(string(raw))}
	data, err := json.Marshal(parsed)
	if err != nil {
		return err
	}
	return writeFileAtomic(destination, data)
}
