# Scan to Quote

iPad app: LiDAR room scan → accurate wall, ceiling, door and window measurements.
This is the scanning core only; quoting, voice notes and the PDF come next.

## What's here

| Path | What |
| --- | --- |
| `ScanCore/` | Pure-Swift measurement engine (no RoomPlan/UIKit). All the maths, unit-tested on any platform. |
| `App/Scanning/` | RoomPlan capture, live guidance HUD (instructions, checklist, mini-map with gaps). |
| `App/Rooms/` | Saved rooms, results screen, tape-measure corrections, floor plan drawing. |
| `project.yml` | XcodeGen spec. The `.xcodeproj` is generated, not committed. |
| `.github/workflows/build.yml` | Runs ScanCore tests and builds an unsigned IPA on every push. |

## Getting the IPA

Every push builds `ScanToQuote-ipa` under the run's **Artifacts** on the Actions tab.
It's unsigned: sideload with Sideloadly or AltStore, which sign it with your Apple ID.

## Building locally

```sh
brew install xcodegen
xcodegen generate
open ScanToQuote.xcodeproj
swift test --package-path ScanCore   # measurement tests
```

Without LiDAR (Simulator, older iPads) use **⋯ → Add demo room** or **Load scan file…**,
which accepts this app's `room.json` or a raw RoomPlan `CapturedRoom` JSON
(e.g. from Apple's RoomPlan sample app).

## How the measurements work

- **Walls**: RoomPlan's processed result, refined so each corner sits where the two
  neighbouring wall planes intersect. LiDAR fixes a wall's face far better than its ends,
  so this gives tighter lengths and floor area than raw wall widths.
- **Heights**: walls within 3 cm of the room's median height are snapped to it (that spread
  is scan noise). A wall that comes up clearly shorter than the rest (almost always a missed
  ceiling line) takes the room height and is flagged for a tape check.
- **Corrections**: tap any door or window to change what it is (window → door) or remove it
  as a false detection; walls can be removed too (a wardrobe front read as a wall). Doors and
  windows with furniture in front of them are flagged, since clutter causes most false
  detections. Furniture is drawn on the floor plan.
- **Furniture**: anything RoomPlan recognises (appliances aside) can be switched on for
  painting. Area is estimated from its outline (front, exposed sides and top; faces against a
  wall are skipped) or typed in, and totalled separately from the walls.
- **Openings**: doors/windows are attached to their wall (RoomPlan's parent id, else nearest
  plane), clipped to the wall, and overlaps are counted once.
- **Sloped and curved walls** use their real outline or arc length, not width × height.
- **Ceiling** = floor outline from the wall corners (flat-ceiling assumption), falling back
  to RoomPlan's floor polygon when the walls don't close.
- **Trim**: skirting (perimeter less doorways), door architraves (one side), window frames.

### Accuracy

LiDAR is not tape-exact: expect roughly ±1–3 cm per wall. Tap any wall, door or window
to enter a tape measurement; it re-flows through every total, and the **Tape check** card
shows LiDAR-vs-tape error in cm. Tape a few walls on real rooms to see the true accuracy
on your iPad.

`AccuracyTests` checks the engine against hundreds of random rooms with known answers
(rectangles, L-shapes, angled walls, arbitrary position/rotation) to 1e-9 m, and against
simulated scanner noise.
