<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Recordings and exports

## Recordings

Frigate records each camera in segments of about 10 seconds. `recordings`
lists those in a range of at most a day, oldest first, with their motion
and object counts:

```jennifer
def now as float init convert.toFloat(time.unix(time.now()));
for (def r in frigate.recordings($c, "front", $now - 3600.0, $now)) {
    if ($r.objects > 0) {
        io.printf("%f|prec=0 %d objects\n", $r.startTime, $r.objects);
    }
}
```

`recordingHours` summarises a camera's recordings by hour, in UTC, newest
day first. `storage` (admin) gives each camera's disk use and how much it
records per hour.

## Clips and frames

```jennifer
fs.writeBytes("front.mp4", frigate.recordingClip($c, "front", $t - 30.0, $t + 30.0));
fs.writeBytes("front.jpg", frigate.recordingFrame($c, "front", $t, "jpg", 0));
```

A clip is cut while you wait and read into memory whole, under the media
cap (`withMaxMediaBytes`, 256 MiB by default). A range with nothing
recorded is `HttpError` status 400 for a clip, 404 for a frame.

## Exports

An export saves a stretch of recording as one file that retention does not
remove; the UI lists them under Exports. The server writes it in the
background:

```jennifer
def id as string init frigate.startExport($c, "front", $t - 60.0, $t + 60.0, "parcel");
def e as frigate.Export init frigate.waitExport($c, $id, 600000);
fs.writeBytes("parcel.mp4", frigate.exportFile($c, $e));
```

`waitExport` asks once a second until `inProgress` is false, and throws
kind `"timeout"` when the time is up. A failed export is removed, so the
wait then ends with `HttpError` status 404. `exportFile` reads the file the
server serves under `/exports/`, outside the API; it refuses a path outside
Frigate's exports directory. `deleteExports` (admin) removes exports and
their files, all or none; `exports` may still list them for a moment.
