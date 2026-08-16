# PaceMan for Omarchy

Follow live Minecraft RSG speedrunning paces from [PaceMan.gg](https://paceman.gg/)
without leaving the Omarchy bar.

The bar uses a compact Minecraft icon, with active-run details in its tooltip
and panel. Qualifying rows use bold text and carry an explicit `★ HIGH QUALITY`
marker in the active theme's foreground color. Open the panel for the global
pace board, completed
splits, estimated current times, Twitch links, version/streaming filters, and
favorite runners.

## Install

```bash
omarchy plugin add https://github.com/nille/omarchy-paceman --enable
```

Without `--enable`, add it through **Omarchy menu -> Bar -> Widgets** or run:

```bash
omarchy plugin enable nille.paceman --section right
```

There is no build step, account login, API key, helper daemon, or extra package.
The widget reads PaceMan's public liveruns endpoint directly from QML.

## Use

- Left-click the bar counter to open or close the pace board.
- Middle-click to refresh immediately.
- Right-click to open PaceMan.gg.
- Click the freshness text to set the automatic refresh interval
  (`2–60` seconds), or use the widget settings.
- Use the bell tool to edit notification thresholds for every standard split.
- Use the header star tool to enable or disable favorite-runner alerts, add
  usernames manually, review the complete favorites list, and remove runners.
- Click a run to expand its splits; double-click or use the external-link action
  to open its Twitch stream or PaceMan profile.
- Collapse expanded run details with the close action in its header.
- Star a runner to persist them as a favorite.
- Keyboard navigation supports `j`/`k`, `Enter`, `f` to favorite, `o` to open,
  `r` to refresh, and `Esc` to close.

## Notifications

Three independent notification sources are available in widget settings:

- A favorite runner starts a newly reported run.
- A split is reported at or below its configured `MM:SS` threshold.
- A run reaches PaceMan's current high-quality criteria.

The bell tool exposes the high-quality toggle, the split-alert master toggle,
and an individual enable switch for every standard split. Turning a split off
preserves its configured threshold.

Enable **Streaming runners only** in the bell menu to suppress every alert
from runners PaceMan does not currently report as streaming on Twitch.

When more than one condition applies to the same split, the widget sends one
combined notification. The first API snapshot and reconnect snapshots never
replay alerts for runs that were already active.

Notifications include an action that opens the live Twitch stream when
available, or the runner's PaceMan profile otherwise. They use the bundled
Minecraft face icon rather than a generic system icon.

Default thresholds:

| Split | Time |
| --- | ---: |
| Enter Nether | 02:00 |
| Enter Bastion | 04:30 |
| Enter Fortress | 04:30 |
| First Portal | 06:00 |
| Second Portal | 07:00 |
| Enter Stronghold | 07:30 |
| Enter End | 08:00 |
| Finish | 10:00 |

Blank or `0` disables an individual threshold.

## Development

```bash
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/qml
tests/harness/run
```

`Model.js` contains the pure API, sorting, formatting, favorites, and alert
logic. `Panel.qml` owns transport and rendering. The harness uses live PaceMan
data but disables desktop notifications.

## Privacy and scope

The plugin sends no Minecraft credentials and does not use PaceMan tracker
access keys. It only reads public PaceMan RSG data. All Advancements runs use a
separate PaceMan feed and are not included in this version.
