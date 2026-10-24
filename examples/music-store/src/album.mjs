// The Album model. Spec: specs/models/Album.md

export function makeAlbum({ id, title, artistName, priceCents, releasedOn, listed = false }) {
  const trimmed = String(title ?? "").trim()
  if (trimmed.length < 1 || trimmed.length > 200) throw new Error("title must be 1–200 characters")
  if (!Number.isInteger(priceCents) || priceCents < 0) throw new Error("priceCents must be a non-negative integer")
  if (!artistName) throw new Error("artistName is required")
  if (!releasedOn) throw new Error("releasedOn is required")
  return { id, title: trimmed, artistName, priceCents, releasedOn, listed: listed === true }
}
