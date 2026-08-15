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
  variations in source order. Walking the first-child chain *from the root's
  first child onward* and mapping `&:notation` yields exactly `game.moves`
  (`root.next`, `root.next.next`, … — the root itself is excluded, see
  Navigation notes). This recursion mirrors `Serializer#emit_line` /
  `#move_token` exactly, so the node tree and the serialized output cannot
  disagree.

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
  def previous      # parent (nil for root)
  def children      # Array<PGN::Node>, first_moves_of(continuation)
  def [](i)         # children[i]
  def position       # lazy + cached: parent.position.move(move.notation)
                    #   (root == game.starting_position); pure-Ruby, no
                    #   engine dep; raises on illegal SAN like Game#positions
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
- `previous` returns `parent`. `root.previous` is `nil`. (The root
  participates as the starting position but is not yielded by `main_line`.)
- `main_line` yields `root.next`, then `root.next.next`, … — i.e. the nodes
  reached by each mainline move, **excluding the root**. So
  `main_line.map(&:notation) == game.moves.map(&:notation)` and
  `main_line.map(&:position) == game.positions[1..]`. It is an `Enumerator`
  so it composes with the lazy `each_position` style already in the gem.
  The starting position is available via `game.root.position` (==
  `game.starting_position`).

### `Node#position`

Computed lazily and cached on the node: `node.position = parent.position
.then { |p| p.move(move.notation) }` (recursive; each ancestor caches, so the
first access is O(depth) and subsequent accesses are O(1); `root.position ==
game.starting_position`). Pure Ruby via `PGN::Position#move` — no
`PGN::Bitboard::Engine` dependency. On an illegal SAN it raises exactly as
`Game#positions` does today (the replay path is shared). The cache lives on the
`Node`, so it is dropped implicitly when the node goes stale (after a
structural mutation you fetch a fresh `#root`).

### `add_variation` / `add_main_variation`

Accept a single SAN `String` or an `Array<String>` (a sub-line). Internally
build `MoveText`s with the **same castling `0`→`O` normalization** that
`Game#moves=` / `standardize_castling` uses (so `O-O` stays canonical), then
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
1.. = variations. The catch: in `MoveText` storage, siblings at one branch
point are not always in a single array. The common case —
`cont.variations = [V1, V2, V3]` (flat, as in `( V1 ) ( V2 ) ( V3 )`) — keeps
all siblings in one array. The rare case — `( V1 ( V2 ( V3 ) ) )` — stores
them nested (`cont.variations = [V1]`, `V1[0].variations = [V2]`, …) even
though `V1`, `V2`, `V3` all branch at the same point. `first_moves_of`
flattens both into one sibling list for *reading*; for *reordering* we need
a single array to edit.

**Flatten-on-mutation invariant.** Every structural mutation that reorders
or removes siblings (`promote`, `demote`, `promote_to_main`, `demote_to_last`,
`delete`) first **normalizes the affected branching point to flat sibling
storage**, then performs the edit on that flat `variations` array.
`add_variation` / `add_main_variation` also normalize so the sibling set stays
flat and uniform. After normalization, every sibling at the point is a direct
element of one `variations` array (the continuation's, or the new
continuation's after a swap).

Normalization is localized to one branch point: it hoists every variation
first-move that branches at that point (recursively through nested brackets)
into the continuation's `variations` array, and clears those first-moves'
`variations` (the hoisted lines now live as separate flat siblings). The
*internal* structure of each variation line (its tail moves and their own
deeper variations) is untouched — only the nesting *at this branch point* is
flattened. This is a documented mutation side-effect (a same-point-nested
`( V1 ( V2 ) )` becomes `( V1 ) ( V2 )` after any reorder at that point); it
is idempotent and the round-trip gate (below) asserts the mutated structure
re-parses to itself. All current fixtures are already flat at every branch
point, so for them normalization is a no-op.

**Normalization algorithm** at a branching point whose continuation is `cont`
(`cont = line[i]`):

```
def normalize(cont):
  lines = []                       # flat sibling variation lines, DFS order
  collect = ->(m) {
    (m.variations || []).each do |v|   # v branches before m == at this point
      lines << v
      collect.call(v[0])           # nested same-point variations hoist too
    end
  }
  collect.call(cont)
  lines.each { |v| v[0].variations = (v[0].variations || []).clear }
  # NB: each v[0]'s at-this-point variations are now hoisted into `lines`;
  #     v[0]'s tail moves (v[1..]) and their deeper variations are untouched.
  cont.variations = lines
  lines
end
```

After normalization `cont.variations = [V1, V2, …]` is a flat array of
variation lines, in the same order `first_moves_of(cont)` yields. Reorders
are then plain array edits:

**`promote`** — move this node's line one slot toward index 0 in
`cont.variations` (swap with the previous element); no-op if it is already
the continuation (index 0) or the first variation (index 1).

**`demote`** — move one slot toward the end (swap with the next element).
At index 0 (the node *is* the continuation `cont`), `demote` is the
**inverse swap**: the first variation `V1 = cont.variations[0]` is promoted
to continuation (see `promote_to_main` applied to `V1`), so the old
mainline drops to variation #1. At the last index, `demote` is a no-op.

**`promote_to_main`** — promote variation `Vk = [vk0, *vk_tail]` (currently
`cont.variations[k]`) to the new mainline at this point:

```
flat      = cont.variations          # already normalized: [V1, …, Vk, …]
vk        = flat.delete_at(k)        # [vk0, *vk_tail]
old_tail  = line[i+1..]              # the old mainline tail (Array<MoveText>)
line[i]   = vk0
line[i+1..] = vk_tail                # V becomes the mainline
cont.variations = []                 # old continuation no longer owns these
vk0.variations = [[cont, *old_tail], *flat]   # old mainline → variation, others stay
```

**`demote_to_last`** — repeat `demote` until the node is the last sibling
(equivalently: move its line to the end of `cont.variations`; if it was the
continuation, that is one `promote_to_main`-of-the-next-variation plus a
move-to-end — simplest implemented as repeated `demote`).

**`delete`** — after normalization:
- if the node is a variation `Vk`: `cont.variations.delete_at(k)`.
- if the node is the continuation `cont`: remove it from the line. If
  `cont.variations` is now non-empty, the first variation `V1` becomes the new
  continuation (`line[i] = V1[0]`, `line[i+1..] = V1[1..]`, `V1[0].variations =
  cont.variations[1..]`); otherwise the line is truncated at `i`
  (`line[i..] = []`).

**`add_variation(move_or_moves)`** — normalize, then append the new sub-line
to `cont.variations`.

**`add_main_variation(move_or_moves)`** — if the node is terminal
(`cont`/continuation is `nil`), extend `line` with the new `MoveText`s (the
natural "continue the game" operation). Otherwise normalize, build the new
sub-line `N = [n0, *n_tail]`, insert it as the new continuation
(`line[i] = n0`, `line[i+1..] = n_tail`) and set
`n0.variations = [[cont, *old_tail], *cont.variations]` (the inverse of
`promote_to_main`).

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
- **Positions:** `game.root.main_line.map(&:position) == game.positions[1..]`
  (root excluded). For variation nodes, assert against a hand-replayed FEN
  on `spec/pgn_files/variations.pgn` (e.g. the `Nc3` variation node's
  position == the FEN after `1. e4 e5 2. Nc3`).
- **Children/variation count:** assert `node.children.size` and
  `node.variations.size` against fixture structure (e.g. the node after
  `1.e4 e5` has 3 children: `Nf3`, `Nc3`, `f4`).
- **`add_variation`:** append a SAN, assert the new `MoveText` appears in the
  target `MoveText.variations`, and `game.to_pgn` re-parses with the variation
  present.
- **`add_variation` at terminal node raises `ArgumentError`**; at a
  non-terminal node appends correctly.
- **`promote_to_main` / `promote` / `demote` / `demote_to_last` / `delete`:**
  assert the resulting `MoveText` structure (notations + variation layout)
  and that `game.to_pgn` round-trips.
- **`demote` at index 0 is the inverse swap** (covered by a dedicated test).
- **Flatten-on-mutation:** a synthetic `( V1 ( V2 ) )` same-point-nested
  fixture, after a `promote`, re-serializes to flat `( V1 ) ( V2 )` and
  re-parses idempotently.

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
- **`promote`/`demote` on deeply nested variations.** Mitigation: the
  flatten-on-mutation invariant reduces every reorder to a flat-array edit;
  dedicated tests use `spec/pgn_files/variations.pgn` (flat at every branch
  point) and a synthetic same-point-nested `( V1 ( V2 ) )` fixture to cover
  the normalization path.
- **Backward-compat drift in `Game#moves`.** Mitigation: `@moves` is mutated
  in place (not replaced with a new object type); existing specs compare
  `map(&:notation)` and `MoveText` structure — all still hold.

## Decisions settled during self-review

- `main_line` excludes the root (yields `root.next`, `root.next.next`, …) so
  it lines up 1:1 with `game.moves` and `game.positions[1..]`.
- `previous` is simply `parent` everywhere; `root.previous` is `nil`.
- Structural mutations normalize the affected branching point to flat
  sibling storage before editing (see "Flatten-on-mutation invariant"). This
  resolves the nested-variation reorder case that the first draft hand-waved.
- No runtime stale-check on `Node`; the "re-`root` after mutation" contract is
  documented and enforced by the round-trip gate, not by per-node bookkeeping.
