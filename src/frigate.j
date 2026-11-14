# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0
# pragma-jennifer-capability: net

/**
 * A client for the HTTP API of Frigate, the self-hosted network video
 * recorder with object detection: sign in, list and filter the tracked
 * objects (events) with their snapshots and clips, create and end events by
 * hand, read and mark review items, read recordings and cut clips and
 * frames from them, export stretches of recording and download them, and
 * look after the cameras: configuration, live stats, the latest frame,
 * features switched on and off. `call` and `fetch` reach any other
 * endpoint. Frigate's live feed is MQTT (the `mqtt` module), not this API.
 *
 * Every request has a deadline and a response cap (one for JSON, one for
 * images and video); plain `http` is refused except to this machine unless
 * allowed. A request the server refused throws `HttpError` (kind
 * `frigate.http`) with its `status` and validation `fields`; a response
 * over a cap is kind `"limit"`, a deadline that passed kind `"timeout"`, a
 * connection the server closed mid-answer kind `"closed"`; every other
 * failure is `Error{kind: "frigate"}`.
 *
 * | topic | covers |
 * | --- | --- |
 * | `core` | `Client`, settings, sign-in, the exchange, errors, `version`, `profile`, `call`, `fetch` |
 * | `events` | events, their media, manual events, sub labels, review items |
 * | `recordings` | recordings, clips and frames, storage, exports |
 * | `cameras` | config, cameras, stats, latest frame, labels, switches, restart |
 *
 * @module frigate
 * @see https://docs.frigate.video/integrations/api/frigate-http-api
 * @example
 *   def c as frigate.Client init frigate.login(frigate.client("https://nvr.example.org:8971"), "admin", $password);
 *   for (def e in frigate.events($c, ["labels=person", "limit=10"])) {
 *       io.printf("%s %s %s\n", $e.camera, $e.label, $e.id);
 *   }
 */
use convert;
use io;
use json;
use lists;
use maps;
use regex;
use strings;
use task;
use time;

import "http.j" as http;
import "uri.j" as uri;

include "topics/version.j";
include "topics/core.j";
include "topics/events.j";
include "topics/recordings.j";
include "topics/cameras.j";
