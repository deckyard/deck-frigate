<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# frigate cheatsheet

Every export of `@deckyard/frigate`. Guides are listed in
[the introduction](index.md).

```jennifer
import "@deckyard/frigate/" as frigate;
```

A request the server refused throws `HttpError` (kind `frigate.http`) with
the HTTP `status` and, for a 422, the validation errors as `fields`
(`query.limit` -> message); a response over a cap (or nested past the JSON
decoder's caps) is kind `"limit"`, a
deadline that passed kind `"timeout"`, a connection the server closed
mid-answer kind `"closed"`, a network failure (refused, reset, unreachable,
DNS, TLS) kind `"net"`, the `net.NetError` that `http` threw; every other
failure is `Error{kind: "frigate"}`
(a cancelled task stays kind `"cancelled"`). A `c`
argument is a `Client`; a `query` is a `list of string` of `name=value`
parameters with Frigate's snake_case names. Times are `float` Unix seconds.
"Admin" calls need the admin role.

## Constants

| Constant | Value | Meaning |
|---|---|---|
| `DEFAULT_TIMEOUT_MS` | `30000` | how long one request may take |
| `DEFAULT_MAX_BYTES` | `16777216` | the largest JSON response read |
| `DEFAULT_MAX_MEDIA_BYTES` | `268435456` | the largest image or video read |
| `MAX_SUB_LABEL` | `100` | the longest sub label |
| `MAX_SPAN_SECONDS` | `86400` | the longest range of a clip or an export |
| `MAX_RECORDINGS_SPAN_SECONDS` | `21600` | the longest range of one `recordings` call (a day is four) |

## The client

| Function | Returns | Does |
|---|---|---|
| `client(baseUrl)` | `Client` | a client for the server's root URL, not signed in; requests refuse plain http to another machine |
| `login(c, username, password)` | `Client` | sign in; the client carries the JWT (`Client.token`) |
| `withToken(c, token)` | `Client` | sign in with a JWT kept from an earlier `login` |
| `withPlainHttp(c)` | `Client` | allow plain http to another machine (port 5000 on the LAN) |
| `withTls(c, tls)` | `Client` | certificate options (`caCert`, `skipVerify`) |
| `withTimeout(c, ms)` | `Client` | the deadline of one request, 1000 to 86400000 ms |
| `withMaxBytes(c, most)` | `Client` | the largest JSON response, 65536 to 268435456 bytes |
| `withMaxMediaBytes(c, most)` | `Client` | the largest image or video, 65536 to 2147483647 bytes |
| `version(c)` | `string` | the Frigate version, such as `0.18.2-cfa08c5` |
| `profile(c)` | `Profile` | who the client is signed in as |
| `call(c, method, path, query, body)` | `json.Value` | any other API request below `/api` |
| `fetch(c, path, query)` | `bytes` | any other image or video below `/api` |

## Events and review items

| Function | Returns | Does |
|---|---|---|
| `events(c, query)` | `list of Event` | events, newest first, filtered by the server; thumbnails left out |
| `event(c, id)` | `Event` | one event |
| `deleteEvent(c, id)` | `null` | admin; delete an event with its media |
| `retainEvent(c, id, keep)` | `null` | admin; keep an event regardless of retention, or stop keeping it |
| `setSubLabel(c, id, subLabel, score)` | `null` | admin; set or clear (`""`) the sub label; score 0 for none |
| `createEvent(c, camera, label, subLabel, seconds)` | `string` | admin; a manual event, the new id; 0 seconds keeps it open; a label may have single inner spaces (`traffic light`) |
| `endEvent(c, id)` | `null` | admin; end a manual event left open |
| `eventSnapshot(c, id)` | `bytes` | the event's snapshot, a JPEG |
| `eventThumbnail(c, id, format)` | `bytes` | its thumbnail, `jpg`, `png` or `webp` |
| `eventClip(c, id, padding)` | `bytes` | its clip, an MP4, with `padding` seconds either side |
| `reviews(c, query)` | `list of Review` | review items, newest first, filtered by the server |
| `review(c, id)` | `Review` | one review item |
| `markReviewed(c, ids, reviewed)` | `null` | mark items reviewed or not, for the signed-in user |

Changes to events go through the server's event queue: `event` shows them
after a moment. Every other read sees a change at once: each GET carries
`X-Cache-Bypass: 1`, past the 5-second cache in front of port 8971.

## Recordings and exports

| Function | Returns | Does |
|---|---|---|
| `recordings(c, camera, after, before)` | `list of Recording` | the recorded segments in a range of at most 6 hours |
| `recordingHours(c, camera)` | `list of RecordingHour` | the hours recorded, in UTC, newest day first |
| `storage(c)` | `list of Storage` | admin; the disk space each camera's recordings take |
| `recordingClip(c, camera, start, end)` | `bytes` | an MP4 cut from the recordings |
| `recordingFrame(c, camera, at, format, height)` | `bytes` | one recorded frame, `jpg` or `png`; height 0 for the recorded size |
| `startExport(c, camera, start, end, name)` | `string` | queue an export; its id |
| `exports(c, query)` | `list of Export` | exports, newest first, filtered by the server (`cameras`, `start_date`, `end_date`, `export_case_id`; `[]` for all) |
| `exportInfo(c, id)` | `Export` | one export |
| `waitExport(c, id, ms)` | `Export` | wait until it is written; kind `"timeout"` after `ms` |
| `exportFile(c, e)` | `bytes` | a finished export's MP4 |
| `deleteExports(c, ids)` | `null` | admin; delete exports, all or none |

## Cameras and the server

| Function | Returns | Does |
|---|---|---|
| `config(c)` | `json.Value` | the configuration in use, defaults filled in |
| `cameras(c)` | `list of string` | the camera names, sorted |
| `stats(c)` | `json.Value` | the live numbers: cameras, detectors, processes, storage |
| `cameraStats(c)` | `list of CameraStats` | each camera's frame rates and stream state |
| `latestFrame(c, camera, format, height)` | `bytes` | the camera's latest frame; height 0 for the detect size |
| `labels(c, camera)` | `list of string` | the labels events were recorded with, of one camera or all (`""`) |
| `switchCamera(c, camera, feature, on)` | `null` | admin; a feature on or off until restart, `*` for every camera |
| `switchPart(c, camera, part, name, on)` | `null` | admin; a `zone`, `motion_mask` or `object_mask` on or off |
| `restart(c)` | `null` | admin; restart Frigate |

`switchCamera` features: `enabled`, `detect`, `motion`, `recordings`,
`snapshots`, `audio`, `audio_transcription`, `notifications`,
`review_alerts`, `review_detections`, `object_descriptions`,
`review_descriptions`, `improve_contrast`, `ptz_autotracker`, `birdseye`.

## Types

### `Client`

| Field | Meaning |
|---|---|
| `baseUrl as string` | the server's root URL without a trailing slash |
| `token as string` | the JWT, `""` when not signed in |
| `tls as http.TlsOptions` | certificate checks for https |
| `allowPlainHttp as bool` | plain http to another machine allowed |
| `timeoutMs as int` | the deadline of one request |
| `maxBytes as int` | the largest JSON response |
| `maxMediaBytes as int` | the largest image or video |

### `Profile`

| Field | Meaning |
|---|---|
| `username as string` | the user; `anonymous` on port 5000 |
| `role as string` | `admin`, `viewer` or a custom role |
| `cameras as list of string` | the cameras the user may see |

### `HttpError`

| Field | Meaning |
|---|---|
| `kind as string` | always `"frigate.http"` |
| `message as string` | `frigate: <request>: <why> (HTTP nnn)` |
| `status as int` | the HTTP status, such as 401, 404 or 422 |
| `fields as map of string to string` | a 422's validation errors, `query.limit` -> message; empty otherwise |

### `Event`

| Field | Meaning |
|---|---|
| `id as string` | the event's id, such as `1794646971.714268-8qyqhn` |
| `camera as string` | the camera |
| `label as string` | `person`, `car`, ... |
| `subLabel as string` | a recognised name or a set sub label, `""` if none |
| `score as float` | the best score, 0 to 1 |
| `startTime as float` | first seen, Unix seconds |
| `endTime as float` | last seen, 0 while tracked |
| `inProgress as bool` | still tracked |
| `zones as list of string` | the zones entered |
| `hasClip as bool` | a clip exists |
| `hasSnapshot as bool` | a snapshot exists |
| `retained as bool` | kept regardless of retention |
| `raw as json.Value` | the event as the server sent it |

### `Review`

| Field | Meaning |
|---|---|
| `id as string` | the item's id |
| `camera as string` | the camera |
| `severity as string` | `alert` or `detection` |
| `startTime as float` | its start, Unix seconds |
| `endTime as float` | its end, 0 while going on |
| `inProgress as bool` | still going on |
| `reviewed as bool` | reviewed by the signed-in user; false from `review` |
| `events as list of string` | the ids of its events |
| `objects as list of string` | what was seen, such as `person: alice` |
| `zones as list of string` | the zones entered |
| `raw as json.Value` | the item as the server sent it |

### `Recording`

| Field | Meaning |
|---|---|
| `id as string` | the segment's id |
| `startTime as float` | its start, Unix seconds |
| `endTime as float` | its end, Unix seconds |
| `duration as float` | its length in seconds |
| `motion as int` | the motion in it |
| `objects as int` | the object detections in it |
| `sizeMb as float` | its size in MB |

### `RecordingHour`

| Field | Meaning |
|---|---|
| `day as string` | `YYYY-MM-DD`, UTC |
| `hour as int` | 0 to 23, UTC |
| `events as int` | the events in it |
| `motion as int` | the motion in it |
| `objects as int` | the object detections in it |
| `duration as float` | the seconds recorded |

### `Storage`

| Field | Meaning |
|---|---|
| `camera as string` | the camera |
| `usageMb as float` | the space taken, MB |
| `bandwidthMb as float` | MB recorded per hour |
| `usagePercent as float` | its share of the disk, 0 to 100 |

### `Export`

| Field | Meaning |
|---|---|
| `id as string` | the export's id |
| `camera as string` | the camera |
| `name as string` | its name |
| `date as float` | the start of the stretch, Unix seconds |
| `videoPath as string` | the file on the server |
| `inProgress as bool` | still being written |

### `CameraStats`

| Field | Meaning |
|---|---|
| `name as string` | the camera |
| `cameraFps as float` | frames per second from the camera |
| `processFps as float` | frames per second processed |
| `detectionFps as float` | detections per second |
| `detectionEnabled as bool` | detection is on |
| `connection as string` | the stream's state, such as `excellent` |
| `reconnects as int` | reconnects in the last hour |
