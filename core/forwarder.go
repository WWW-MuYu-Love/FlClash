package core

import (
	"io"
	"net"
	"strconv"
	"sync"
	"time"

	"github.com/metacubex/mihomo/config"
)

const forwardDialTimeout = 2 * time.Second

// The app core never binds the extension core's real ports: it forwards
// them on port+1 instead, so the dashboard and the system proxy keep
// working while the app is in the background and the app process is
// suspended. The ports come from the effective config, never from a
// constant: a settings change can move them, and the forwarders follow.
var (
	mixedPortSkipped  bool
	forwardMixedPort  int
	forwardController string
	portForwarders    = map[string]*portForwarder{}
	portForwardersMu  sync.Mutex
)

type forwardTarget struct {
	listen string
	target string
}

func desiredForwarders(cfg *config.Config) map[string]forwardTarget {
	desired := map[string]forwardTarget{}
	if mixedPortSkipped && forwardMixedPort > 0 && forwardMixedPort < 65535 {
		desired["mixed"] = forwardTarget{
			listen: forwardListenAddr(cfg.General.BindAddress, forwardMixedPort+1, cfg.General.AllowLan),
			target: forwardTargetAddr(cfg.General.BindAddress, forwardMixedPort, cfg.General.AllowLan),
		}
	}
	if externalControllerSkipped && forwardController != "" {
		if listen, target, ok := controllerForwardAddrs(forwardController); ok {
			desired["controller"] = forwardTarget{listen: listen, target: target}
		}
	}
	return desired
}

// forwardListenAddr mirrors the listener package's address choice for a
// port: all interfaces when the bind address is "*", loopback otherwise.
func forwardListenAddr(host string, port int, allowLan bool) string {
	if !allowLan {
		return net.JoinHostPort("127.0.0.1", strconv.Itoa(port))
	}
	if host == "*" || host == "" {
		return net.JoinHostPort("", strconv.Itoa(port))
	}
	return net.JoinHostPort(host, strconv.Itoa(port))
}

// forwardTargetAddr is the address the extension core listens on for the
// same port: loopback covers "*", a named host is dialed as-is.
func forwardTargetAddr(host string, port int, allowLan bool) string {
	if !allowLan || host == "*" || host == "" {
		return net.JoinHostPort("127.0.0.1", strconv.Itoa(port))
	}
	return net.JoinHostPort(host, strconv.Itoa(port))
}

func controllerForwardAddrs(addr string) (listen, target string, ok bool) {
	host, portStr, err := net.SplitHostPort(addr)
	if err != nil {
		return "", "", false
	}
	port, err := strconv.Atoi(portStr)
	if err != nil || port <= 0 || port >= 65535 {
		return "", "", false
	}
	if host == "0.0.0.0" || host == "" || host == "*" {
		return net.JoinHostPort("0.0.0.0", strconv.Itoa(port+1)), net.JoinHostPort("127.0.0.1", strconv.Itoa(port)), true
	}
	return net.JoinHostPort(host, strconv.Itoa(port+1)), net.JoinHostPort(host, strconv.Itoa(port)), true
}

func reconcilePortForwarders(cfg *config.Config) {
	portForwardersMu.Lock()
	defer portForwardersMu.Unlock()
	if cfg == nil || !isRunning.Load() {
		stopPortForwardersLocked()
		return
	}
	desired := desiredForwarders(cfg)
	for key, want := range desired {
		if cur := portForwarders[key]; cur != nil {
			if cur.listenAddr == want.listen && cur.targetAddr == want.target {
				continue
			}
			cur.stop()
			delete(portForwarders, key)
		}
		fw := &portForwarder{}
		if err := fw.start(want.listen, want.target); err != nil {
			logError("port forwarder %s listen %s failed: %v", key, want.listen, err)
			continue
		}
		portForwarders[key] = fw
	}
	for key, cur := range portForwarders {
		if _, ok := desired[key]; !ok {
			cur.stop()
			delete(portForwarders, key)
		}
	}
}

func stopPortForwarders() {
	portForwardersMu.Lock()
	defer portForwardersMu.Unlock()
	stopPortForwardersLocked()
}

func stopPortForwardersLocked() {
	for key, fw := range portForwarders {
		fw.stop()
		delete(portForwarders, key)
	}
}

type portForwarder struct {
	listenAddr string
	targetAddr string
	listener   net.Listener
	done       chan struct{}
	wg         sync.WaitGroup
	connsMu    sync.Mutex
	conns      map[net.Conn]struct{}
}

func (f *portForwarder) start(listenAddr, targetAddr string) error {
	ln, err := net.Listen("tcp", listenAddr)
	if err != nil {
		return err
	}
	f.listenAddr = listenAddr
	f.targetAddr = targetAddr
	f.listener = ln
	f.done = make(chan struct{})
	f.conns = make(map[net.Conn]struct{})
	f.wg.Add(1)
	go f.acceptLoop()
	return nil
}

func (f *portForwarder) stop() {
	if f.listener == nil {
		return
	}
	close(f.done)
	f.listener.Close()
	f.connsMu.Lock()
	for conn := range f.conns {
		conn.Close()
	}
	f.connsMu.Unlock()
	f.wg.Wait()
}

func (f *portForwarder) acceptLoop() {
	defer f.wg.Done()
	for {
		conn, err := f.listener.Accept()
		if err != nil {
			select {
			case <-f.done:
				return
			default:
				time.Sleep(10 * time.Millisecond)
				continue
			}
		}
		f.wg.Add(1)
		go f.handleConn(conn)
	}
}

func (f *portForwarder) handleConn(client net.Conn) {
	defer f.wg.Done()
	f.trackConn(client)
	defer f.untrackConn(client)
	target, err := net.DialTimeout("tcp", f.targetAddr, forwardDialTimeout)
	if err != nil {
		// The extension is not running (VPN off): drop this connection
		// and keep serving the next one.
		client.Close()
		return
	}
	f.trackConn(target)
	defer f.untrackConn(target)
	done := make(chan struct{}, 2)
	go func() {
		io.Copy(target, client)
		done <- struct{}{}
	}()
	go func() {
		io.Copy(client, target)
		done <- struct{}{}
	}()
	<-done
	client.Close()
	target.Close()
	<-done
}

func (f *portForwarder) trackConn(conn net.Conn) {
	f.connsMu.Lock()
	f.conns[conn] = struct{}{}
	f.connsMu.Unlock()
}

func (f *portForwarder) untrackConn(conn net.Conn) {
	f.connsMu.Lock()
	delete(f.conns, conn)
	f.connsMu.Unlock()
}
