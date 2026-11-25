#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

/**
 * events example: sign in to a Frigate server, list the alerts nobody has
 * reviewed yet, and the last ten events with their labels and scores.
 *
 *   FRIGATE_PASSWORD=... jennifer run examples/events.j https://nvr.example.org:8971 admin
 *
 * With a certificate from a private CA, point FRIGATE_CA at the CA's PEM
 * file. Frigate's own default certificate names no host, so nothing can
 * verify it: FRIGATE_INSECURE=1 turns the checks off. Without arguments it prints this usage, so CI
 * runs it without a server.
 */

use convert;
use fs;
use io;
use os;
use strings;

import "../src/frigate.j" as frigate;
import "http.j" as http;

def args as list of string init os.ARGS;
if (len($args) != 3) {
    io.printf("usage: FRIGATE_PASSWORD=... [FRIGATE_CA=ca.pem | FRIGATE_INSECURE=1] jennifer run examples/events.j <url> <user>\n");
    exit 0;
}

try {
    def c as frigate.Client init frigate.client($args[1]);
    if (os.getEnv("FRIGATE_INSECURE") == "1") {
        $c = frigate.withTls($c, http.TlsOptions{skipVerify: true});
    } elseif (os.getEnv("FRIGATE_CA") != "") {
        $c = frigate.withTls(
            $c,
            http.TlsOptions{skipVerify: false, caCert: fs.readBytes(os.getEnv("FRIGATE_CA"))});
    }
    $c = frigate.login($c, $args[2], os.getEnv("FRIGATE_PASSWORD"));
    io.printf("Frigate %s\n\nalerts to review:\n", frigate.version($c));
    for (def r in frigate.reviews($c, ["severity=alert", "reviewed=0", "limit=20"])) {
        io.printf("  %s  %s  %s\n", $r.camera, $r.id, strings.join($r.objects, ", "));
    }
    io.printf("\nlast events:\n");
    for (def e in frigate.events($c, ["limit=10"])) {
        def label as string init $e.label;
        if ($e.subLabel != "") {
            $label = $label + " (" + $e.subLabel + ")";
        }
        def state as string init "";
        if ($e.inProgress) {
            $state = "  still tracked";
        }
        io.printf(
            "  %s  %s  %s  %d%%%s\n",
            $e.camera,
            $e.id,
            $label,
            convert.toInt($e.score * 100.0),
            $state);
    }
} catch (e) {
    io.eprintf("%s\n", $e.message);
    exit 1;
}
