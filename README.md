# @deckyard/frigate

[![test](https://github.com/deckyard/deck-frigate/actions/workflows/test.yml/badge.svg)](https://github.com/deckyard/deck-frigate/actions/workflows/test.yml)
[![Documentation](https://img.shields.io/badge/docs-github%20pages-blue)](https://deckyard.github.io/deck-frigate/)
[![release](https://img.shields.io/github/v/release/deckyard/deck-frigate)](https://github.com/deckyard/deck-frigate/releases/latest)

A client for the HTTP API of [Frigate](https://frigate.video/), the
self-hosted network video recorder with object detection, for
[Jennifer](https://jennifer-lang.dev/) programs: sign in, list and filter
events and review items, fetch snapshots and clips, create events by hand,
read recordings and cut clips and frames from them, export and download
stretches of recording, and look after the cameras (configuration, live
stats, the latest frame, features switched on and off).

**[Documentation](https://deckyard.github.io/deck-frigate/)**

## Install

```sh
jvc add @deckyard/frigate
```

This vendors the deck to `vendor/<scope>/frigate/`. Without `jvc`, unpack the
`src/` subtree of a release archive (`<scope>-frigate-<version>.tar.gz`) there.

## Usage

```jennifer
import "@deckyard/frigate/" as frigate;

def c as frigate.Client init frigate.login(
    frigate.client("https://nvr.example.org:8971"),
    "admin",
    os.getEnv("FRIGATE_PASSWORD"));
for (def e in frigate.events($c, ["labels=person", "has_snapshot=1", "limit=5"])) {
    fs.writeBytes($e.id + ".jpg", frigate.eventSnapshot($c, $e.id));
}
```

`examples/` has three programs: `events.j` (open alerts and the last
events), `export.j` (export and download the last minutes of a camera) and
`status.j` (frame rates and disk use per camera).

## Requirements

Jennifer 0.26.0 or newer, with the `net` capability: the deck talks HTTP(S)
to a Frigate server. Checked against Frigate 0.18.2.

## Development

```sh
tools/check-all.sh                   # the full gate, as CI runs it
jennifer test src/frigate_test.j      # the test overlay
tools/check-docs.sh                  # docs against the code
tools/pack.sh dist                   # build the release archive
```

## Licence

LGPL-3.0-only, see [LICENSE](LICENSE). Copyright (C) 2026 mplx &lt;mplx@jennifer-lang.dev&gt;.

`tools/check-headers.sh` checks every source file's SPDX header against
`deck.toml`.
