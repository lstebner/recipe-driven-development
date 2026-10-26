---
screen: AlbumDetail
status: approved
---

## Goal
Let a listener see an album's details and release history, and buy it.

## Layout
- Header: {copy.title} · {copy.artist}
- Body (≥md: row · <md: stack)
  - Artwork
  - Details
    - [[~ReleaseTimeline]]                     → R2
    - Price ($type.heading)
    - ?buy [[PrimaryButton]] {copy.buy}        → R1, R3
    - ?owned {copy.owned}                      → R1

## States
| state | when | looks like |
|---|---|---|
| loading | [[api:GetAlbum]] is in flight | skeleton of Body; no [[PrimaryButton]] |
| not-found | [[api:GetAlbum#not_found]] | {copy.notFound} |

## Rules
- R1: The buy button shows only when [[policy:CanBuyAlbum]] gives `buy`, and {copy.owned} only when it gives `owned`.
- R2: The release timeline shows the newest release first.
- R3: While a purchase is in flight, the buy button shows its loading state and can't be pressed again.

## Copy
| key | text |
|---|---|
| title | {album.title} |
| artist | by {album.artistName} |
| buy | Buy for {price} |
| owned | In your library |
| notFound | We couldn't find that album. |

## Style
- Artwork has $radius.md corners and $shadow.card.
- $space.lg between Artwork and Details at ≥md.

## Open amendments

## Decisions
- 2026-10-21: Accepted A1 (buy button needs a loading state): double-taps created two orders in testing. Added R3 and PrimaryButton's `loading` state.
- 2026-10-21: Rejected A2 (make ReleaseTimeline shared): only AlbumDetail needs it; revisit if a second screen does.
- 2026-10-24: R1 now follows CanBuyAlbum instead of deciding ownership itself, so the buy button can't disagree with CreateOrder.
- 2026-10-26: Moved States into the States table.
