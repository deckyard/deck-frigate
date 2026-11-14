#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

/**
 * status example: each camera's frame rates and stream state, and the disk
 * space its recordings take. Uses the unauthenticated port 5000, so it
 * needs no password; that port is only reachable where the operator
 * published it.
 *
 *   jennifer run examples/status.j http://localhost:5000
 *
 * Without arguments it prints this usage, so CI runs it without a server.
 */

use io;
use maps;
use os;

import "../src/frigate.j" as frigate;

def args as list of string init os.ARGS;
if (len($args) != 2) {
    io.printf("usage: jennifer run examples/status.j <url>, such as http://localhost:5000\n");
    exit 0;
}

try {
    def c as frigate.Client init frigate.client($args[1]);
    def used as map of string to float init {};
    for (def s in frigate.storage($c)) {
        $used[$s.camera] = $s.usageMb;
    }
    for (def s in frigate.cameraStats($c)) {
        def mb as float init 0.0;
        if (maps.has($used, $s.name)) {
            $mb = $used[$s.name];
        }
        io.printf(
            "%s|pad=16 %f|prec=1 fps in, %f|prec=1 processed, %s, %d reconnects, %f|prec=0 MB recorded\n",
            $s.name,
            $s.cameraFps,
            $s.processFps,
            $s.connection,
            $s.reconnects,
            $mb);
    }
} catch (e) {
    io.eprintf("%s\n", $e.message);
    exit 1;
}
