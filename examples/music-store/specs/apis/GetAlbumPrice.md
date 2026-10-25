---
api: GetAlbumPrice
status: deprecated
deprecated: 2026-10-20
replaced_by: GetAlbum
endpoint: GET /albums/{id}/price
---
## Purpose
Fetch an album's current price, so the detail page can show it.

## Auth
Public.

## Request
| field | type | required | notes |
|---|---|---|---|
| id | uuid | yes | path |

## Response
200: `{ priceCents: integer }`

## Errors
| code | status | when |
|---|---|---|
| not_found | 404 | no album with that id, or it's unlisted |

## Rules
- R1: An unlisted album returns not_found, never 403, so its existence isn't revealed.

## Open amendments

## Decisions
- 2026-10-20: Deprecated: GetAlbum already returns the whole [[model:Album]], price included, so AlbumDetail makes one call instead of two.
