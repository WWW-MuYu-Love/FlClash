//go:build ios && cgo

// Package main is the iOS C entry point to the core. Xcode links the
// c-archive it produces into both the Runner app (in-app core, for delay
// tests and method calls) and the NECore packet-tunnel extension (which
// owns the TUN device). It re-exports upstream's core API through the
// same C functions the reference fork's NECoreBridge/IOSCoreBridge call,
// so the Swift side is unchanged apart from its package name.
//
// The callback table in bride.h is filled in by the ObjC side at startup:
// result delivers async answers, retain/release balance the retained
// handler objects, and protect/resolve are the no-op iOS answers (the
// extension already owns the tunnel; iOS names no per-connection owner).
package main

/*
#include "bride.h"
#include <stdlib.h>
*/
import "C"
import (
	"encoding/json"
	"sync"
	"unsafe"

	"core"
)

// tunOptions is the JSON the NECore Swift side sends to startTUN. Keys are
// camelCase, matching CoreTunOptions in PacketTunnelProvider.swift.
type tunOptions struct {
	RecvMsgX               bool   `json:"recvMsgX"`
	SendMsgX               bool   `json:"sendMsgX"`
	Stack                  string `json:"stack"`
	Address                string `json:"address"`
	DNS                    string `json:"dns"`
	MTU                    uint32 `json:"mtu"`
	DisableICMPForwarding  bool   `json:"disableIcmpForwarding"`
	EndpointIndependentNAT bool   `json:"endpointIndependentNat"`
	CongestionController   string `json:"congestionController"`
}

// coreTunOptions is what core.StartTun's tun layer parses. Its keys match
// core/tun.startOptions: kebab-case for the mihomo config keys Android
// already sends, camelCase for the iOS-only flags.
type coreTunOptions struct {
	MTU                    uint32 `json:"mtu"`
	CongestionController   string `json:"congestion-controller"`
	RecvMsgX               bool   `json:"recvMsgX"`
	SendMsgX               bool   `json:"sendMsgX"`
	DisableICMPForwarding  bool   `json:"disableIcmpForwarding"`
	EndpointIndependentNAT bool   `json:"endpointIndependentNat"`
	LoopbackAddress        string `json:"loopback-address"`
}

func protect(callback unsafe.Pointer, fd int) bool {
	return C.protect(callback, C.int(fd)) != 0
}

func resolveUid(callback unsafe.Pointer, protocol int, source, target string) int {
	s := C.CString(source)
	defer C.free(unsafe.Pointer(s))
	t := C.CString(target)
	defer C.free(unsafe.Pointer(t))
	return int(C.resolve_uid(callback, C.int(protocol), s, t))
}

func resolvePackage(callback unsafe.Pointer, uid int) string {
	return takeCString(C.resolve_package(callback, C.int(uid)))
}

func invokeResult(callback unsafe.Pointer, data string) {
	s := C.CString(data)
	defer C.free(unsafe.Pointer(s))
	C.result(callback, s)
}

func releaseObject(callback unsafe.Pointer) {
	C.release_object(callback)
}

func retainObject(callback unsafe.Pointer) unsafe.Pointer {
	return C.retain_object(callback)
}

func takeCString(s *C.char) string {
	defer C.free_string(s)
	return C.GoString(s)
}

// iosCallbacks adapts the ObjC callback table to core.TunCallbacks. The
// NECore side answers protect with 1 and resolve with -1/"", so these are
// pass-throughs, not decisions.
type iosCallbacks struct {
	callback unsafe.Pointer
}

func (c iosCallbacks) Protect(fd int) bool {
	return protect(c.callback, fd)
}

func (c iosCallbacks) ResolveUid(protocol int, source, target string) int {
	return resolveUid(c.callback, protocol, source, target)
}

func (c iosCallbacks) ResolvePackage(uid int) string {
	return resolvePackage(c.callback, uid)
}

var (
	eventListenerMu  sync.Mutex
	eventListenerObj unsafe.Pointer
)

//export invokeMethod
func invokeMethod(callback unsafe.Pointer, paramsChar *C.char) {
	params := takeCString(paramsChar)
	var once sync.Once
	core.InvokeMethod(params, func(data []byte) {
		once.Do(func() {
			invokeResult(callback, string(data))
			releaseObject(callback)
		})
	})
}

//export startTUN
func startTUN(callback unsafe.Pointer, fd C.int, optionsChar *C.char) bool {
	options := tunOptions{}
	if err := json.Unmarshal([]byte(takeCString(optionsChar)), &options); err != nil {
		return false
	}
	upstream, err := json.Marshal(coreTunOptions{
		MTU:                    options.MTU,
		CongestionController:   options.CongestionController,
		RecvMsgX:               options.RecvMsgX,
		SendMsgX:               options.SendMsgX,
		DisableICMPForwarding:  options.DisableICMPForwarding,
		EndpointIndependentNAT: options.EndpointIndependentNAT,
		LoopbackAddress:        "10.7.0.1",
	})
	if err != nil {
		return false
	}
	return core.StartTun(
		iosCallbacks{callback: callback},
		int(fd),
		options.Stack,
		options.Address,
		options.DNS,
		string(upstream),
	)
}

//export quickSetup
func quickSetup(callback unsafe.Pointer, initParamsChar *C.char, setupParamsChar *C.char) {
	initParams := takeCString(initParamsChar)
	setupParams := takeCString(setupParamsChar)
	core.QuickSetup(initParams, setupParams, func(message string) {
		invokeResult(callback, message)
		releaseObject(callback)
	})
}

//export setEventListener
func setEventListener(listener unsafe.Pointer) {
	eventListenerMu.Lock()
	old := eventListenerObj
	eventListenerObj = listener
	eventListenerMu.Unlock()
	if listener == nil {
		core.SetEventListener(nil)
	} else {
		core.SetEventListener(func(data []byte) {
			eventListenerMu.Lock()
			current := eventListenerObj
			if current != nil {
				current = retainObject(current)
			}
			eventListenerMu.Unlock()
			if current == nil {
				return
			}
			defer releaseObject(current)
			invokeResult(current, string(data))
		})
	}
	if old != nil {
		releaseObject(old)
	}
}

//export getTotalTraffic
func getTotalTraffic(onlyStatisticsProxy bool) *C.char {
	return C.CString(core.GetTotalTraffic(onlyStatisticsProxy))
}

//export getTraffic
func getTraffic(onlyStatisticsProxy bool) *C.char {
	return C.CString(core.GetTraffic(onlyStatisticsProxy))
}

//export stopTun
func stopTun() {
	core.StopTun()
}

//export startListener
func startListener() {
	core.StartListener()
}

//export stopListener
func stopListener() {
	core.StopListener()
}

//export forceGC
func forceGC() {
	core.ForceGC()
}

//export updateDns
func updateDns(s *C.char) {
	// No-op on iOS, as in the reference fork: DNS is owned by the Network
	// Extension's tunnel settings, not by the core.
	_ = takeCString(s)
}
