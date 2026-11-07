package main

import (
	"context"
	"log"
	"sync"
	"syscall"
	"time"
)

// dirWatchStopIdent:叫醒监听 goroutine 退出用的那个用户事件的标识。
const dirWatchStopIdent = 1

// startDirWatch 用 kqueue 盯一个目录:目录里有条目新建、删除、改名时往 out 里塞一个信号。「临时文件 + 改名」
// 的原子写落盘就是一次改名,所以盯目录而不盯文件本身(改名换上来的是新文件,盯着旧文件收不到事件)。
// out 要带缓冲;塞不进(上一个信号还没被取走)就丢,收到的一方自己去看到底哪个文件变了。
// 打不开目录或建不起 kqueue 时返回 false,调用方照旧靠定时器。等事件时不定时醒:ctx 结束时触发一个用户事件叫它退出。
// 目录本身被删、被改名时退出(之后描述符盯着的是已经不在原处的目录,再也收不到事件)。
func startDirWatch(ctx context.Context, dir string, out chan<- struct{}) (<-chan struct{}, bool) {
	fd, err := syscall.Open(dir, syscall.O_EVTONLY|syscall.O_CLOEXEC, 0)
	if err != nil {
		return nil, false
	}
	kq, err := syscall.Kqueue()
	if err != nil {
		syscall.Close(fd)
		return nil, false
	}
	var vnode, stop syscall.Kevent_t
	syscall.SetKevent(&vnode, fd, syscall.EVFILT_VNODE, syscall.EV_ADD|syscall.EV_CLEAR)
	vnode.Fflags = syscall.NOTE_WRITE | syscall.NOTE_DELETE | syscall.NOTE_RENAME
	syscall.SetKevent(&stop, dirWatchStopIdent, syscall.EVFILT_USER, syscall.EV_ADD|syscall.EV_CLEAR)
	if _, err := syscall.Kevent(kq, []syscall.Kevent_t{vnode, stop}, nil, nil); err != nil {
		syscall.Close(kq)
		syscall.Close(fd)
		return nil, false
	}
	// 触发退出事件和关描述符互斥:关掉的描述符号可能已经被别的文件复用,不能再往它上面发 kevent。
	var closeMu sync.Mutex
	closed := false
	stopped := make(chan struct{})
	go func() {
		select {
		case <-ctx.Done():
		case <-stopped:
			return
		}
		closeMu.Lock()
		defer closeMu.Unlock()
		if closed {
			return
		}
		var trigger syscall.Kevent_t
		syscall.SetKevent(&trigger, dirWatchStopIdent, syscall.EVFILT_USER, 0)
		trigger.Fflags = syscall.NOTE_TRIGGER
		_, _ = syscall.Kevent(kq, []syscall.Kevent_t{trigger}, nil, nil)
	}()
	go func() {
		defer func() {
			closeMu.Lock()
			closed = true
			syscall.Close(kq)
			syscall.Close(fd)
			closeMu.Unlock()
			close(stopped)
		}()
		events := make([]syscall.Kevent_t, 4)
		for {
			n, err := syscall.Kevent(kq, nil, events, nil)
			if err == syscall.EINTR {
				continue
			}
			if err != nil {
				log.Printf("dirwatch: stopped watching dir=%s, falling back to the timer: %v", dir, err)
				return
			}
			if ctx.Err() != nil {
				return
			}
			for _, ev := range events[:n] {
				if ev.Filter != syscall.EVFILT_VNODE {
					continue
				}
				if ev.Fflags&(syscall.NOTE_DELETE|syscall.NOTE_RENAME) != 0 {
					log.Printf("dirwatch: dir=%s was moved or deleted, falling back to the timer", dir)
					return
				}
				select {
				case out <- struct{}{}:
				default:
				}
				break
			}
		}
	}()
	return stopped, true
}

// requestWatchFallback:目录监听正常时的补扫间隔，用于发现文件内写入。
const requestWatchFallback = 10 * time.Second

// requestWakeups:歌词缓存扫描的两个触发来源。盯着 dir,目录一变就从返回的通道收到信号;另配一个定时器,
// 盯得了时每 requestWatchFallback 一次,盯不了时按 poll,盯到一半停了(目录被删、改名)也退回按 poll。
// 调用方负责 Stop 定时器。
func requestWakeups(ctx context.Context, dir string, poll time.Duration) (<-chan struct{}, *time.Ticker) {
	writes := make(chan struct{}, 1)
	stopped, ok := startDirWatch(ctx, dir, writes)
	if !ok {
		return writes, time.NewTicker(poll)
	}
	ticker := time.NewTicker(requestWatchFallback)
	go func() {
		<-stopped
		if ctx.Err() == nil {
			ticker.Reset(poll)
		}
	}()
	return writes, ticker
}
