// Copyright 2025 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

//go:build wasip1

package exec

import (
	"errors"
)

// ErrNotFound is the error resulting if a path search failed to find an executable file.
// On wasip1, LookPath always returns an error because subprocess execution
// is not supported.
var ErrNotFound = errors.New("executable file not found in $PATH")

func lookPath(file string) (string, error) {
	return "", &Error{file, ErrNotFound}
}

// lookExtensions is a no-op on non-Windows platforms, since
// they do not restrict executables to specific extensions.
func lookExtensions(path, dir string) (string, error) {
	return path, nil
}
