package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"log"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
	"unicode"
)

type metadata struct {
	Title        string  `json:"title"`
	Artist       string  `json:"artist"`
	Album        string  `json:"album"`
	Duration     float64 `json:"duration"`
	Position     float64 `json:"anchorElapsedTime"`
	Timestamp    float64 `json:"timestamp"`
	PlaybackRate float64 `json:"playbackRate"`
	Playing      bool    `json:"playing"`
	Artwork      []byte  `json:"artworkData,omitempty"`
}

type track struct {
	ID       int64   `json:"id"`
	Name     string  `json:"name"`
	Artist   string  `json:"artist"`
	Album    string  `json:"album"`
	Duration float64 `json:"duration"`
}

type playback struct {
	Running bool      `json:"running"`
	Track   *metadata `json:"track"`
	ID      string    `json:"id"`
}

func cleanName(s string) string {
	return strings.TrimSpace(strings.Map(func(r rune) rune {
		if unicode.Is(unicode.Cf, r) {
			return -1
		}
		return r
	}, s))
}

func trackKey(s string) string {
	return strings.Map(func(r rune) rune {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			return unicode.ToLower(r)
		}
		return -1
	}, s)
}

func trackID(db string, current metadata) (string, error) {
	data, err := exec.Command("/usr/bin/sqlite3", "-readonly", db,
		`SELECT json_group_array(json(json)) FROM (SELECT json FROM hist_song ORDER BY ord DESC)`).Output()
	if err != nil {
		return "", err
	}
	var tracks []track
	if err := json.Unmarshal(data, &tracks); err != nil {
		return "", err
	}
	for _, candidate := range tracks {
		if trackKey(candidate.Name) != trackKey(current.Title) ||
			trackKey(candidate.Artist) != trackKey(current.Artist) {
			continue
		}
		diff := math.Abs(candidate.Duration - current.Duration)
		hasDuration := candidate.Duration > 0 && current.Duration > 0
		if hasDuration && diff/math.Max(candidate.Duration, current.Duration) > 0.12 {
			continue
		}
		if candidate.Album != "" && current.Album != "" &&
			trackKey(candidate.Album) != trackKey(current.Album) && (!hasDuration || diff > 1) {
			continue
		}
		return strconv.FormatInt(candidate.ID, 10), nil
	}
	return "", nil
}

func nowPlaying(resources string, artwork bool) (*metadata, error) {
	args := []string{filepath.Join(resources, "nowplaying.pl"), filepath.Join(resources, "libnowplaying.dylib")}
	if artwork {
		args = append(args, "artwork")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	raw, err := exec.CommandContext(ctx, "/usr/bin/perl", args...).Output()
	if err != nil {
		return nil, err
	}
	var result *metadata
	if err := json.Unmarshal(raw, &result); err != nil {
		return nil, err
	}
	if result != nil {
		result.Title = cleanName(result.Title)
		result.Artist = cleanName(result.Artist)
		result.Album = cleanName(result.Album)
	}
	return result, nil
}

func scanLyrics(source, destination string) {
	files, err := os.ReadDir(source)
	if errors.Is(err, os.ErrNotExist) {
		return
	}
	if err != nil {
		log.Print(err)
		return
	}
	for _, file := range files {
		name := file.Name()
		id, ext := strings.CutSuffix(name, ".lrc")
		if _, err := strconv.ParseInt(id, 10, 64); file.IsDir() || !ext || err != nil {
			continue
		}
		if err := refreshLyrics(filepath.Join(source, name), filepath.Join(destination, id+".json")); err != nil {
			log.Print(err)
		}
	}
}

func followLaunch(data string) bool {
	raw, err := os.ReadFile(filepath.Join(data, "follow-launch"))
	if errors.Is(err, os.ErrNotExist) {
		return true
	}
	if err != nil {
		log.Print(err)
		return false
	}
	return string(raw) == "true"
}

func main() {
	home, err := os.UserHomeDir()
	if err != nil {
		log.Fatal(err)
	}
	app := os.Args[1]
	resources := filepath.Join(app, "Contents", "Resources")
	data := filepath.Join(home, "Library", "Application Support", "Bodian Lyrics")
	parsed := filepath.Join(data, "Parsed")
	if err := os.MkdirAll(parsed, 0700); err != nil {
		log.Fatal(err)
	}
	cache := filepath.Join(home, "Library", "Caches", "cn.wenyu.bodian.bodianPc")
	lyricDir := filepath.Join(cache, "cache", "lyric")
	db := filepath.Join(cache, "database", "songDB.db")

	go func() {
		changes, timer := requestWakeups(context.Background(), lyricDir, 3*time.Second)
		defer timer.Stop()
		for {
			scanLyrics(lyricDir, parsed)
			select {
			case <-changes:
			case <-timer.C:
			}
		}
	}()

	poll := time.NewTicker(750 * time.Millisecond)
	defer poll.Stop()
	var previousPID, id string
	var previousTrack metadata
	var lastState []byte
	for {
		pidBytes, _ := exec.Command("/usr/bin/pgrep", "-x", "波点音乐").Output()
		pid := string(pidBytes)
		state := playback{Running: pid != ""}
		if state.Running {
			if pid != previousPID && followLaunch(data) {
				if err := exec.Command("/usr/bin/open", "-gj", app).Run(); err != nil {
					log.Print(err)
				}
			}
			current, err := nowPlaying(resources, false)
			if err != nil {
				log.Print(err)
			}
			if current != nil && current.Title != "" {
				changed := current.Title != previousTrack.Title || current.Artist != previousTrack.Artist ||
					current.Album != previousTrack.Album || current.Duration != previousTrack.Duration || pid != previousPID
				if changed || id == "" {
					id, err = trackID(db, *current)
					if err != nil {
						log.Print(err)
					}
				}
				if changed || (id != "" && previousTrack.Title == "") {
					art, err := nowPlaying(resources, true)
					if err != nil {
						log.Print(err)
					} else if art != nil && art.Title == current.Title && art.Artist == current.Artist && id != "" && len(art.Artwork) > 0 {
						if err := writeFileAtomic(filepath.Join(parsed, id+".cover"), art.Artwork); err != nil {
							log.Print(err)
						}
					}
				}
				previousTrack = *current
				state.Track, state.ID = current, id
			}
		} else {
			previousTrack, id = metadata{}, ""
		}
		previousPID = pid
		raw, err := json.Marshal(state)
		if err != nil {
			log.Print(err)
		} else if !bytes.Equal(lastState, raw) {
			if err := writeFileAtomic(filepath.Join(data, "playback.json"), raw); err != nil {
				log.Print(err)
			} else {
				lastState = raw
			}
		}
		<-poll.C
	}
}
