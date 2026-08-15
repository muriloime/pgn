# Richer game-tree API — node abstraction, variations management, promote/demote

**Status:** design (awaiting plan)
**Date:** 2026-08-15
**Sub-project:** 1 of 3 (game-tree API → engine wrapper → Polyglot/Syzygy)
**Branch:** `feature/game-tree-engine-book` (worktree `.worktrees/game-tree-engine-book`)
**TODO ref:** `TODO.md` Group 1 — "Richer game-tree API: node-style mainline/variations, add/promote/demote variations."

## Goal

Give `pgn2` a first-class, navigable, mutable game tree: a `PGN::Node`
abstraction over the existing `MoveText` structure with parent/child/variation
links, per-node `Position` (lazy replay), and variation-management operations
(`add_variation`, `promote`, `demote`, `promote_to_main`, `demote_to_last`,
`delete`). Non-breaking: the existing `Game#moves` / `MoveText` /
`Serializer` surface stays intact and byte-identical.

## Non-goals

- Legality validation of SAN on `add_variation` / `Node#position`. The gem is
  structural throughout (parser and `Game.new` don't validate); `Node#position`
  replays via pure-Ruby `Position#move` and raises on an illegal SAN exactly as
  `Game#positions` does today. No new native-engine dependency.
- Nested-comment / brace-escaping round-trip improvements (separate TODO item).
- The UCI/XBoard engine wrapper and Polyglot/Syzygy parsers — separate
  sub-projects on this same branch, designed and planned independently after
  this one lands.
- Streaming/lazy PGN reader, EPD, tolerant parse mode — other TODO items.

## Source of truth

`MoveText` remains the source of truth.

- The parser builds `MoveText` trees as today; the serializer reads them. This
  is what makes PGN round-trip byte-identical, and it stays untouched on the
  read side.
- `PGN::Node` is a **live, lazily-built view** over the `MoveText` tree.
  `Game#root` builds a fresh wrapper tree on each call: it wraps the existing
  `MoveText` objects (no copy), recording each node's `MoveText`, its parent
  `Node`, and the line + index it lives in (so it can locate its continuation).
- **All mutations go through `Node` methods that edit the underlying `MoveText`
  arrays in place.** Because both `Serializer` and `Game#moves` read
  `MoveText` / `@moves`, they reflect mutations automatically — there is no
  second source of truth and no sync surface.
- After any structural mutation, `Node` objects from a previous `#root` call
  are **stale**; call `game.root` again. Mutation methods return the
  freshly-affected `Node`(s) for convenience. This mirrors python-chess, where
  structural mutations invalidate outstanding node references.

## Backward compatibility

- `Game#moves` continues to return the flat mainline `Array<MoveText>`,
  reflecting any mutations applied through the node API. Its reader/writer
  shapes are unchanged.
- `MoveText` keeps `notation` / `annotation` / `comment` / `variations`
  (`variations` still an `Array<Array<MoveText>>`). The node API is purely
  additive over it.
- The 241-example suite stays green; no existing spec is edited for behavior.
- `Game#to_pgn` byte-identical output is preserved by construction (serializer
  unchanged, reads `MoveText`).

## Topology

The existing `MoveText.variations` model has variations branching **from the
position *before* the move** they attach to (confirmed against
`Serializer#move_token`, which emits `( #{emit_line(variation, fullmove,
player)} )` from the position before the move, and the parser's
`san_move_annotated variation_list { result.variations = val[1] }`).

So:

- A **`Node`** represents a position reached by playing `node.move` from
  `node.parent`'s position.
- `root` = the game's starting position: `root.move == nil`, `root.parent ==
  nil`, `root.position == game.starting_position`.
- A node's **children** = all moves playable from that node's position =
  the continuation move (the next `MoveText` in the node's own line) **plus**
  all variation first-moves branching at that same position — recursively
  through nested brackets, because `( A ( B ) )` means both `A` and `B` branch
  at the same point (both are alternatives from that position).
- Formally, for the continuation move `m = line[index+1]`:
  `first_moves_of(m) = [m] + m.variations.flat_map { |v| first_moves_of(v[0]) }`
  and `node.children = first_moves_of(m)` (each first move wrapped in a child
  `Node` whose line is `m`'s line for `m` itself, or the variation array `v`
  for a variation's first move). When `m` is `nil` (end of line), `children` is
  empty.
- The **first child** of each node is the mainline continuation; the rest are
  variations in source order. `Game#moves` ≡ walking `root`'s first-child
  chain and mapping `&:notation` (verified by a spec).
- This recursion mirrors `Serializer#emit_line` / `#move_token` exactly, so
  the node tree and the serialized output cannot disagree.

### Why nested-variation flattening is correct

`( 1...Nf6 ( 1...d5 ) )` after `1.e4`: `e5.variations = [[Nf6, ...]]` and
`Nf6.variations = [[d5, ...]]`. Both `Nf6` and `d5` branch from the position
after `1.e4` (before `Nf6` == before `d5` == after `e4`). So the node for
"after e4" has children `{e5, Nf6, d5}`. `first_moves_of(e5)` produces exactly
this set, matching what the serializer emits.

## Node API

```ruby
class PGN::Node
  # construction — internal, built by Game#root
  #   move:   the MoveText played to reach this node (nil for root)
  #   line:   the Array<MoveText> this node's move lives in
  #           (the mainline for mainline nodes, the variation array for
  #           variation nodes; nil for root)
  #   index:  this node's move's index within `line` (-1 for root)

  attr_reader :move, :parent, :line, :index

  def root?         # node.move.nil? (the root)
  def notation      # move.notation (nil for root)
  def annotation    # move.annotation
  def comment       # move.comment
  def variations    # children[1..] (the non-mainline alternatives)
  def main_line     # Enumerator<PGN::Node> of the first-child chain
  def next          # children.first (mainline continuation)
  def previous      # parent (or nil for root / if parent is root and this is
                    #   the root's first child — see note)
  def children      # Array<PGN::Node>, first_moves_of(continuation)
  def [](i)         # children[i]
  def position       # lazy + cached: replay from root along parent chain
                    #   via pure-Ruby PGN::Position#move(move.notation);
                    #   raises on illegal SAN, same as Game#positions today
  def promote        # move this node one slot toward index 0 in parent.children
  def demote         # move one slot toward the end (inverse-swap at index 0:
                    #   swap mainline down to variation #1 — see semantics)
  def promote_to_main  # become parent.children[0]
  def demote_to_last   # become parent.children[-1]
  def delete         # remove this node (and subtree) from parent
  def add_variation(move_or_moves)      # append a variation line to this
                    # node's branching point (a non-mainline child)
  def add_main_variation(move_or_moves) # prepend as the new mainline child
end

class PGN::Game
  def root  # build and return a fresh PGN::Node tree (root) over @moves
end
```

### Navigation notes

- `next` returns `children.first` (the mainline continuation) or `nil` at a
  terminal position.
- `previous` returns `parent`. For the root's first child, `parent` is the
  root; `previous` returns the root (whose `move` is `nil`). `root.previous`
  is `nil`. (The root participates in the chain as the starting position, so
  `main_line` includes it as the first element.)
- `main_line` yields `root`, then `root.next`, then `root.next.next`, … It is
  an `Enumerator` so it composes with the lazy `each_position` style already
  in the gem.

### `Node#position`

Computed lazily and cached on the node: walk the parent chain to the root,
then replay `root.position` forward applying each ancestor's `move.notation`
via `PGN::Position#move`. Pure Ruby — no `PGN::Bitboard::Engine` dependency.
On an illegal SAN it raises exactly as `Game#positions` does today (the
replay path is shared). Cache is dropped implicitly when the node goes stale
(after a structural mutation you fetch a fresh `#root`).

### `add_variation` / `add_main_variation`

Accept a single SAN `String` or an `Array<String>` (a sub-line). Internally
build `MoveText`s through the same `standardize_castling` path that
`Game#moves=` uses (so castling `0`↔`O` normalization is consistent), then
attach the new sub-line to the correct `MoveText.variations`:

- The branching point for a node's children is the position **before** the
  node's *next* mainline move `m = line[index+1]`. So `add_variation` appends
  the new sub-line to `m.variations` (creating it if `nil`).
- If the node is terminal (`m` is `nil`, i.e. end of its line), there is no
  `MoveText` to attach a variation *before*. Two options: (a) append the new
  line as a continuation extension of the line itself — but that changes the
  line, not a variation; (b) raise. We **raise `ArgumentError`** for
  `add_variation` at a terminal node (a variation must branch before an
  existing move; to extend the line, use `add_main_variation` on the last
  node, or push onto `Game#moves` directly). `add_main_variation` at a
  terminal node *extends the line* (appends the moves to `line`), since that
  is the natural "continue the game" operation.
- `add_main_variation` prepends the new sub-line as the new first child:
  it inserts the new `MoveText`s at the front of `line` at the branching
  index and re-parents the old continuation as a variation of the new first
  move (the inverse of `promote_to_main`'s swap).

### promote / demote / delete — `MoveText`-level edits

Siblings in `parent.children` are ordered: index 0 = mainline continuation,
1.. = variations. Reordering edits the underlying arrays.

**`promote_to_main`** — promote variation `V = [v0, *v_tail]` at a branching
point where the current continuation is `cont` with tail `cont_tail`, and
`cont.variations == [V, *others]` (V may be nested deeper; the edit targets
the array containing `V`):

```
before: line[i]   = cont            ; line[i+1..] = cont_tail
        cont.variations = [V, *others]
after:  line[i]   = v0              ; line[i+1..] = v_tail       # V becomes mainline
        v0.variations = [[cont, *cont_tail], *others]            # old mainline → variation
```

(When `V` is found nested inside another variation's `variations` rather than
directly in `cont.variations`, the swap is performed at the array that
actually holds `V`, and the "old continuation becomes a variation" step
attaches to `v0` at the correct level. The general rule: the array element
holding `v0`'s line is swapped to hold `cont`'s line and vice versa, and the
tail arrays move with their heads.)

**`promote`** — move one slot toward index 0 (swap with the previous sibling);
no-op if already index 0.

**`demote`** — move one slot toward the end (swap with the next sibling). At
index 0 this is the **inverse swap**: the current mainline (`cont`) is
swapped down to become a variation, and variation #1 (`V`) becomes the new
mainline — exactly the `promote_to_main` transformation applied to `V`. At the
last index, `demote` is a no-op.

**`demote_to_last`** — repeat `demote` until the node is the last sibling.

**`delete`** — remove this node's line from its parent's branching array
(remove `V` from `cont.variations`, or remove the continuation `cont` and its
tail from `line` if this node *is* the mainline). Removing the mainline
continuation makes the next variation (if any) the new continuation; if there
are no variations, the line is truncated.

### After mutation

- `Game#moves` (the `@moves` array) is mutated in place for mainline swaps, so
  its reader reflects the new mainline. `MoveText.variations` arrays are
  replaced/augmented for variation swaps.
- The serializer reads the same `MoveText`/`@moves`, so `to_pgn` reflects the
  mutation. The round-trip gate (below) asserts this.
- Node objects from the prior `#root` are stale; re-fetch via `game.root`.
  Mutation methods return the affected `Node`(s) from a freshly-built tree
  so callers can chain without an explicit re-`root`.

## Files

- `lib/pgn/node.rb` — new. `PGN::Node`.
- `lib/pgn/game.rb` — add `#root` (builds the tree) and require `pgn/node`.
  No change to existing methods' behavior.
- `lib/pgn.rb` — require `pgn/node` (if not pulled in via `pgn/game`).
- `spec/node_spec.rb` — new.
- `spec/game_spec.rb` — extend the round-trip test to exercise mutations
  (additive; existing assertions untouched).
- No change to `serializer.rb`, `pgn_parser.y`, `move.rb`, `move_text`.

## Testing

### New `spec/node_spec.rb`

- **Shape:** for each fixture game, `game.root.main_line.map(&:notation) ==
  game.moves.map(&:notation)`.
- **Positions:** for mainline nodes, `node.position.to_fen.to_s ==
  game.positions[i].to_fen.to_s` (root ↔ `game.positions[0]`, etc.). For
  variation nodes, assert against a hand-replayed FEN on a fixture with a
  known variation (`spec/pgn_files/variations.pgn`).
- **Children/variation count:** assert `node.children.size` and
  `node.variations.size` against fixture structure.
- **`add_variation`:** append a SAN, assert the new `MoveText` appears in the
  target `MoveText.variations`, and `game.to_pgn` re-parses with the variation
  present.
- **`add_variation` at terminal node raises `ArgumentError`**; at a
  non-terminal node appends correctly.
- **`promote_to_main` / `promote` / `demote` / `demote_to_last` / `delete`:**
  assert the resulting `MoveText` structure (notations + variation layout)
  and that `game.to_pgn` round-trips.
- **`demote` at index 0 is the inverse swap** (covered by a dedicated test).

### Extended round-trip gate (`spec/game_spec.rb`)

Add an additive block that, for each non-`non_round_trip` fixture, after
parsing: builds `game.root`, performs a scripted `promote`+`demote`+`add_variation`
on the first branching point (skip fixtures with no variations), re-serializes,
re-parses, and asserts `expect_moves_equal` still holds against the mutated
structure. Existing assertions unchanged.

### Existing suite

Unchanged; 241 examples stay green.

## Risks & mitigations

- **Topology bug → serializer disagreement.** Mitigation: the node builder
  mirrors `Serializer#emit_line`/`#move_token` recursion, and a spec asserts
  `main_line` ↔ `Game#moves` equivalence on every fixture.
- **Stale-node misuse after mutation.** Mitigation: documented; mutation
  methods return fresh nodes from a re-built tree. We do **not** add a runtime
  stale-check (would need per-mutation bookkeeping on every `Node`); the
  round-trip gate catches structural mistakes, and the documentation makes the
  "re-`root` after mutation" contract explicit.
- **`promote`/`demote` on deeply nested variations.** Mitigation: the edit
  targets the array that actually holds the node's line; dedicated tests for
  nested-variation fixtures (`spec/pgn_files/nested_comments.pgn` and a
  synthetic nested-variation fixture).
- **Backward-compat drift in `Game#moves`.** Mitigation: `@moves` is mutated
  in place (not replaced with a new object type); existing specs compare
  `map(&:notation)` and `MoveText` structure — all still hold.

## Open question (to resolve in plan, not blocking spec)

- Exact shape of `previous` for the root's first child (return root vs. nil).
  Lean: return root (the starting position is a real node in `main_line`), so
  `previous` is simply `parent` everywhere and `root.previous` is `nil`.
  Finalized in the implementation plan.
