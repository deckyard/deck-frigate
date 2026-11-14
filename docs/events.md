<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Events and review

## Events

An event is one tracked object: a person, car or dog that a camera saw from
a start to an end time, with a label, an optional sub label (a recognised
face or plate, or one set by hand), zones, a snapshot and a clip.

```jennifer
for (def e in frigate.events($c, ["cameras=front", "labels=person", "has_snapshot=1", "limit=20"])) {
    io.printf("%s %s %f|prec=2\n", $e.id, $e.label, $e.score);
}
```

`events` passes the query to the server, which filters and sorts: newest
first, at most 100 unless `limit` says otherwise, `offset` for the next
page. Useful parameters: `cameras`, `labels`, `sub_labels` and `zones`
(comma lists), `after` / `before` (Unix seconds), `has_clip` /
`has_snapshot` / `in_progress` / `favorites` (`0` or `1`; favourites are
retained events), `min_score` / `max_score`, `sort` (`date_asc`,
`date_desc`, `score_asc`, ...). A parameter the server cannot parse is
`HttpError` status 422 with `fields`, such as `query.limit`.

The server sends each event's thumbnail inline (a base64 JPEG) unless told
not to, so `events` adds `include_thumbnails=0` unless the query sets it.
`Event.raw` holds the whole answer, for fields the struct leaves out
(`data.box`, `data.region`, `data.attributes`, ...).

An event still being tracked has `inProgress` true and `endTime` 0.

## Media

```jennifer
fs.writeBytes($e.id + ".jpg", frigate.eventSnapshot($c, $e.id));
fs.writeBytes($e.id + ".mp4", frigate.eventClip($c, $e.id, 5));
def thumb as bytes init frigate.eventThumbnail($c, $e.id, "webp");
```

The snapshot has the bounding box drawn; a snapshot of an event that is
still tracked comes from the live frame and may be missing (404). The clip
is cut from the recordings with `padding` seconds either side, so it needs
recording turned on for the camera.

## Manual events

A program can mark a moment itself, such as a doorbell press, and Frigate
keeps the recording around it:

```jennifer
def id as string init frigate.createEvent($c, "front", "doorbell", "", 30);
```

With 0 seconds the event stays open until `endEvent`. `setSubLabel` names
an event's object (`""` clears it), `retainEvent` keeps an event regardless
of the retention settings, `deleteEvent` removes it with its media. All of
these need the admin role.

Frigate applies every change to an event through its event queue, after it
has answered: a new event is not found (404) for a moment, and an `event`
read right after a change may still show the old state.

## Review items

The UI's review page lists review items: stretches of activity on one
camera, each an `alert` (by default people and cars) or a `detection`,
holding the events in it. Reviewed marks are per user.

```jennifer
def open as list of frigate.Review init frigate.reviews($c, ["severity=alert", "reviewed=0"]);
for (def r in $open) {
    io.printf("%s %s %a\n", $r.camera, $r.id, $r.objects);
}
def ids as list of string init [];
for (def r in $open) {
    $ids[] = $r.id;
}
if (len($ids) > 0) {
    frigate.markReviewed($c, $ids, true);
}
```

`reviews` takes `cameras`, `labels`, `zones`, `severity`, `reviewed`,
`after`, `before` and `limit`. `review` reads one item; the server leaves
its reviewed mark out there, so `Review.reviewed` is false from it.
`fetch(c, "/review/<id>/clip.mp4", [])` reads an item's clip.
