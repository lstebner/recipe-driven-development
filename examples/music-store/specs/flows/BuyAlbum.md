---
flow: BuyAlbum
status: draft
---

## Goal
A listener on an album's page ends up owning it, or knows exactly why not.

## Entry
Buy on [[screen:AlbumDetail]]; the listener is signed in.

## Steps
1. [[screen:AlbumDetail]] calls [[api:CreateOrder]]
   - ?[[api:CreateOrder#already_owned]] → end             → R1
   - ?[[api:CreateOrder#card_declined]] → step 1          → R2
2. [[screen:AlbumDetail]] shows the album as owned

## Exits
- done: the album is in the listener's library
- declined: the listener stays on AlbumDetail and nothing is charged

## Rules
- R1: If the listener already owns the album, they see {copy.owned} and aren't charged.
- R2: A declined card leaves the listener on AlbumDetail with {copy.declined} shown.

## Copy
| key | text |
|---|---|
| owned | You already own this album. |
| declined | Your card was declined. Try another one. |

## Open amendments

## Decisions
