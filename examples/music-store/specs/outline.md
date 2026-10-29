# Outline

A small store that sells albums. Each entry below has a spec; the stage it's at is noted in
`examples/music-store/README.md`.

## Screens
- [AlbumDetail](screens/AlbumDetail.md): let a listener see an album and buy it

## Components
- [PrimaryButton](components/PrimaryButton.md): the single call-to-action on a screen

## Flows
- [BuyAlbum](flows/BuyAlbum.md): a listener on an album's page ends up owning it
  - still a draft: haven't decided what happens on a declined card

## Models
- [Album](models/Album.md): an album listed for sale

## APIs
- [GetAlbum](apis/GetAlbum.md): GET /albums/{id} — fetch one album for its detail page
- [CreateOrder](apis/CreateOrder.md): POST /orders — buy an album

## Policies
- [CanBuyAlbum](policies/CanBuyAlbum.md): whether a listener can buy an album, already owns it, or can't get it
