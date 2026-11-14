#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

/**
 * export example: save the last minutes of a camera's recording as an
 * export, wait for the server to write it, and download the MP4.
 *
 *   FRIGATE_PASSWORD=... jennifer run examples/export.j https://nvr.example.org:8971 admin front 5 front.mp4
 *
 * The export stays on the server (Exports in the UI) until deleted.
 * With a certificate from a private CA, point FRIGATE_CA at the CA's PEM
 * file. Frigate's own default certificate names no host, so nothing can
 * verify it: FRIGATE_INSECURE=1 turns the checks off. Without arguments it prints this usage, so CI
 * runs it without a server.
 */

use convert;
use fs;
use io;
use os;
use time;

import "../src/frigate.j" as frigate;
import "http.j" as http;

def args as list of string init os.ARGS;
if (len($args) != 6) {
    io.printf("usage: FRIGATE_PASSWORD=... [FRIGATE_CA=ca.pem | FRIGATE_INSECURE=1] jennifer run examples/export.j <url> <user> <camera> <minutes> <file.mp4>\n");
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
    def minutes as int init convert.toInt($args[4]);
    def now as float init convert.toFloat(time.unix(time.now()));
    def id as string init frigate.startExport(
        $c,
        $args[3],
        $now - convert.toFloat($minutes * 60),
        $now,
        "last " + $args[4] + " minutes");
    io.printf("export %s queued\n", $id);
    def e as frigate.Export init frigate.waitExport($c, $id, 600000);
    def video as bytes init frigate.exportFile($c, $e);
    fs.writeBytes($args[5], $video);
    io.printf("%s: %d bytes\n", $args[5], len($video));
} catch (e) {
    io.eprintf("%s\n", $e.message);
    exit 1;
}
