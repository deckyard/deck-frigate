<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Cameras

## Configuration and stats

`config` is the configuration the server runs with, every default filled
in, as a `json.Value`; `cameras` lists the camera names from it.

```jennifer
def cfg as json.Value init frigate.config($c);
for (def name in frigate.cameras($c)) {
    io.printf("%s recording: %t\n", $name, json.asBool($cfg, "/cameras/" + $name + "/record/enabled"));
}
```

`stats` is the server's live numbers (detectors, processes, storage, GPUs,
uptime); `cameraStats` picks out each camera's frame rates, stream state and
reconnects, enough for a health check:

```jennifer
for (def s in frigate.cameraStats($c)) {
    if ($s.cameraFps == 0.0 or $s.reconnects > 5) {
        io.printf("%s: %s, %d reconnects\n", $s.name, $s.connection, $s.reconnects);
    }
}
```

`latestFrame` is the camera's current picture (while it is offline, the
last preview frame); `labels` the labels events were recorded with.

## Switches

`switchCamera` (admin) turns a feature on or off, for one camera or all
(`*`), until the server restarts; the configuration file is not changed:

```jennifer
frigate.switchCamera($c, "*", "detect", false);
```

The features are `enabled`, `detect`, `motion`, `recordings`,
`snapshots`, `audio`, `audio_transcription`, `notifications`,
`review_alerts`, `review_detections`, `object_descriptions`,
`review_descriptions`, `improve_contrast`, `ptz_autotracker` and
`birdseye`. `switchPart` turns a named zone, motion mask or object mask on
or off; Frigate™ 0.18 accepts a name that is not in the configuration and
does nothing. The settings that take a value (`birdseye_mode`,
`motion_threshold`, `motion_contour_area`, `profile`) go through `call`:

```jennifer
frigate.call($c, "PUT", "/camera/front/set/motion_threshold", [], json.map({"value": "30"}));
```

`restart` (admin) restarts Frigate; it answers first and is back after some
seconds. In Docker™ the process exits, so it comes back only when the
container has a restart policy (`restart: unless-stopped`, as Frigate's
install guide sets).
