<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Recordings and exports

## Recordings

Frigate records each camera in segments of about 10 seconds. `recordings`
lists those in a range of at most 6 hours (`MAX_RECORDINGS_SPAN_SECONDS`),
oldest first, with their motion and object counts; a longer range is
refused before anything is sent. Each segment with motion carries a motion
heatmap of up to 256 cells, about 2.8 KB of JSON: a day of steady motion
is some 24 MB, over the default JSON cap (`withMaxBytes`, 16 MiB), and 6
hours stays under it.

```jennifer
def now as float init convert.toFloat(time.unix(time.now()));
for (def r in frigate.recordings($c, "front", $now - 3600.0, $now)) {
    if ($r.objects > 0) {
        io.printf("%f|prec=0 %d objects\n", $r.startTime, $r.objects);
    }
}
```

A day takes four calls:

```jennifer
def part as float init convert.toFloat(frigate.MAX_RECORDINGS_SPAN_SECONDS);
def day as list of frigate.Recording init [];
for (def i in 0..4) {
    def from as float init $start + convert.toFloat($i) * $part;
    $day = lists.concat($day, frigate.recordings($c, "front", $from, $from + $part));
}
```

`recordingHours` summarises a camera's recordings by hour, in UTC, newest
day first. `storage` (admin) gives each camera's disk use and how much it
records per hour.

## Clips and frames

Clips and exports take ranges of up to a day (`MAX_SPAN_SECONDS`).

```jennifer
fs.writeBytes("front.mp4", frigate.recordingClip($c, "front", $t - 30.0, $t + 30.0));
fs.writeBytes("front.jpg", frigate.recordingFrame($c, "front", $t, "jpg", 0));
```

A clip is cut while you wait and read into memory whole, under the media
cap (`withMaxMediaBytes`, 256 MiB by default). A range with nothing
recorded is `HttpError` status 400 for a clip, 404 for a frame. A frame is
`jpg` or `png`: Frigate renders no other format there.

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
their files, all or none.

`exports` lists them newest first, filtered by the server with the same
`name=value` parameters as `events` (`[]` for all): `cameras=front,back`,
`start_date=<unix>` and `end_date=<unix>` (by the export's start, both
inclusive) and `export_case_id=...`.

```jennifer
def since as int init time.unix(time.now()) - 86400;
for (def e in frigate.exports($c, ["cameras=front", "start_date=" + convert.toString($since)])) {
    io.printf("%s %s\n", $e.id, $e.name);
}
```
