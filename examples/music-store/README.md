# Example: a music store

A small set of specs for a store that sells albums, so you can see what Recipe-Driven
Development looks like partway through a project. There's no app here, just the specs, plus the
one small module that's been built and verified.

The specs are at different stages on purpose:

| spec | kind | status | what it shows |
|---|---|---|---|
| [`Album`](specs/models/Album.md) | model | `verified` | the finished state: built (`src/album.mjs`), every rule has a tagged test, and [the report](specs/_reports/Album.md) is stamped with the spec's fingerprint. Decisions records a trade-off and when to revisit it |
| [`AlbumDetail`](specs/screens/AlbumDetail.md) | screen | `approved` | a layout tree with a shared component, a one-off, copy keys and tokens; Decisions records one accepted and one rejected amendment |
| [`PrimaryButton`](specs/components/PrimaryButton.md) | component | `approved` | variants and states, plus a generated Used by |
| [`GetAlbum`](specs/apis/GetAlbum.md) | api | `approved` | an **open amendment**: Claude found the spec was missing something while building, and work on it is paused until you accept or reject |
| [`CreateOrder`](specs/apis/CreateOrder.md) | api | `draft` | error codes that other specs point at |
| [`CanBuyAlbum`](specs/policies/CanBuyAlbum.md) | policy | `approved` | one decision the screen, GetAlbum and CreateOrder all rely on, so the buy button, `owned` and `already_owned` can't drift apart |
| [`BuyAlbum`](specs/flows/BuyAlbum.md) | flow | `draft` | steps with branches on API errors; still being written |
| [`GetAlbumPrice`](specs/apis/GetAlbumPrice.md) | api | `deprecated` | off the menu: GetAlbum replaced it. The spec stays as a frozen record, with the date and the reason, and nothing points at it any more |

Start with [`outline.md`](specs/outline.md), the one-line-per-spec list everything else grew from.

## Try it

From the repo root:

```
node template/scripts/spec-lint.mjs --root examples/music-store             # lint: specs OK
node template/scripts/spec-lint.mjs --root examples/music-store --summary   # status dashboard
node --test examples/music-store/src/album.test.mjs                         # Album's tagged tests
```

To see the lock in action, change a rule in `Album.md` and lint again: the report no longer
matches the spec's fingerprint, so lint fails until it's re-verified.
