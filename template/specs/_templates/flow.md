---
flow: FlowName
status: draft
---
## Goal
<!-- Who is going through this, and what counts as done. -->

## Entry
<!-- Where the flow starts, e.g. "Buy on [[screen:AlbumDetail]]", and what must already be true. -->

## Steps
<!-- Numbered. Each step is a screen, an API call, or both. Branches are sub-bullets ending in
     → step N, → end, or → [[flow:Other]].
1. [[screen:Cart]]
   - ?empty → end                                   → R1
2. [[screen:Payment]] calls [[api:CreateOrder]]
   - ?[[api:CreateOrder#card_declined]] → step 2    → R2
3. [[screen:OrderConfirmation]]
-->

## Exits
<!-- Every way the flow can end (done, cancelled, abandoned, failed) and what happens to partial state. -->

## Rules
<!-- - FlowName.R1: one checkable statement per bullet. -->

## Open amendments

## Decisions
