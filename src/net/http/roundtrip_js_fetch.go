// Copyright 2025 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

//go:build js && wasm

package http

func init() {
	// Override jsFetchDisabled to use the Fetch API for HTTP requests
	// even when running in Node.js. Without this override, Go's
	// js/wasm port falls through to the fake in-memory network
	// (net_fake.go) which cannot reach real internet hosts.
	jsFetchDisabled = false
}
