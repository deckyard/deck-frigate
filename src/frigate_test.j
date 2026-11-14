# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

/**
 * White-box tests: jennifer test src/frigate_test.j
 *
 * No test needs a Frigate server. A fake on 127.0.0.1 (`startFake` in the
 * core overlay) answers each request from a script and records what it
 * got; the answers follow what Frigate 0.18.2 sent in a live run. The
 * topic overlays are fragments spliced in here, not standalone suites.
 */
use httpd;
use testing;

include "topics/core_test.j";
include "topics/events_test.j";
include "topics/recordings_test.j";
include "topics/cameras_test.j";
