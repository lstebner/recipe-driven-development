import assert from "node:assert/strict"
import { test } from "node:test"
import { makeAlbum } from "./album.mjs"

const base = { id: "a1", title: "Blue Train", artistName: "John Coltrane", priceCents: 1999, releasedOn: "1958-01-01" }

test("[Album.R1] rejects a negative price", () => {
  assert.throws(() => makeAlbum({ ...base, priceCents: -1 }))
  assert.equal(makeAlbum({ ...base, priceCents: 0 }).priceCents, 0)
})

test("[Album.R2] trims the title and enforces its length", () => {
  assert.equal(makeAlbum({ ...base, title: "  Blue Train  " }).title, "Blue Train")
  assert.throws(() => makeAlbum({ ...base, title: "   " }))
  assert.throws(() => makeAlbum({ ...base, title: "x".repeat(201) }))
})

test("[Album.R3] is unlisted unless explicitly listed", () => {
  assert.equal(makeAlbum(base).listed, false)
  assert.equal(makeAlbum({ ...base, listed: true }).listed, true)
})
