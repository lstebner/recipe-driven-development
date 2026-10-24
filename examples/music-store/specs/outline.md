# Outline

A small store that sells albums. Each entry below has a spec; the stage it's at is noted in
`examples/music-store/README.md`.

## Screens
- AlbumDetail: let a listener see an album and buy it

## Components
- PrimaryButton: the single call-to-action on a screen

## Flows
- BuyAlbum: a listener on an album's page ends up owning it
  - still a draft: haven't decided what happens on a declined card

## Models
- Album: an album listed for sale

## APIs
- GetAlbum: GET /albums/{id} — fetch one album for its detail page
- CreateOrder: POST /orders — buy an album
