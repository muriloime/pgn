# frozen_string_literal: true

module PGN
  # {PGN::Node} is a live, lazily-built view over the {PGN::MoveText} tree.
  #
  # A node represents the position reached by playing +move+ from its
  # +parent+'s position; the root has no move and is the game's starting
  # position. The underlying {PGN::MoveText} structure is the source of
  # truth (the parser builds it and the serializer reads it), so a node
  # tree never disagrees with the serialized output.
  #
  # Mutations edit the underlying +MoveText+ arrays in place and, for
  # sibling reorders, normalize the affected branching point to flat
  # sibling storage. After any structural mutation, {PGN::Game#root}
  # returns a fresh tree — outstanding node references are stale.
  class Node
    attr_reader :move, :parent, :line, :index

    # @param move [PGN::MoveText, nil] the move played to reach this node
    # @param parent [PGN::Node, nil] the parent node (nil for the root)
    # @param line [Array<PGN::MoveText>, nil] the line this node's move
    #   lives in (the mainline for mainline nodes, the variation Array for
    #   variation nodes; nil conceptually for the root, which passes the
    #   mainline)
    # @param index [Integer] index of this node's move within +line+
    #   (-1 for the root)
    # @param starting_position [PGN::Position] the root's position
    # @param game [PGN::Game] back-reference so mutations can return a
    #   fresh root
    def initialize(move:, parent:, line:, index:, starting_position: nil, game: nil)
      @move = move
      @parent = parent
      @line = line
      @index = index
      @starting_position = starting_position
      @game = game
    end

    def root?
      @move.nil?
    end

    def notation
      @move&.notation
    end

    def annotation
      @move&.annotation
    end

    def comment
      @move&.comment
    end

    # All moves playable from this node's position: the continuation move
    # (the next MoveText in this node's line) plus every variation
    # first-move branching at that same position, recursively through
    # nested brackets. The first child is the mainline continuation; the
    # rest are variations in source order.
    def children
      @children ||= begin
        cont = continuation_movetext
        list = []
        collect_first_moves(cont, @line, @index + 1) do |mt, l, idx|
          list << Node.new(move: mt, parent: self, line: l, index: idx, game: @game)
        end
        list
      end
    end

    # The non-mainline alternatives at this node's position.
    def variations
      children[1..] || []
    end

    # The mainline continuation, or nil at a terminal position.
    # (Defined via +define_method+ because +next+ is a Ruby keyword and
    # cannot be used with +def+.)
    define_method(:next) { children.first }

    # The parent node, or nil for the root.
    def previous
      @parent
    end

    def [](idx)
      children[idx]
    end

    # Yields each mainline node from +self.next+ onward (the root is
    # excluded), so +main_line.map(&:notation) == game.moves.map(&:notation)+
    # and +main_line.map(&:position) == game.positions[1..]+. Returns an
    # Enumerator when called without a block.
    def main_line
      return enum_for(:main_line) unless block_given?

      node = self.next
      while node
        yield node
        node = node.next
      end
    end

    # The position reached at this node: the starting position for the
    # root, otherwise +parent.position+ with +move.notation+ applied. Pure
    # Ruby (no native engine); raises on an illegal SAN exactly like
    # {PGN::Game#positions}. Cached on the node.
    def position
      return @position if defined?(@position)

      @position = if root?
                    @starting_position
                  else
                    @parent.position.then { |p| p.move(@move.notation) }
                  end
    end

    # Append a new variation line (a single SAN String or an Array<String>)
    # branching before this node's next mainline move. Returns a fresh
    # +game.root+. Raises +ArgumentError+ at a terminal node (a variation
    # must branch before an existing move; use +add_main_variation+ to
    # extend the line).
    def add_variation(move_or_moves)
      cont = continuation_movetext
      raise ArgumentError, 'cannot add a variation at a terminal node' if cont.nil?

      normalize_branch_point(cont)
      cont.variations << build_movetexts(move_or_moves)
      @game.root
    end

    # Make the given moves the new mainline continuation from this node's
    # position. At a terminal node this extends the line; otherwise the old
    # continuation becomes a variation of the new first move. Returns a
    # fresh +game.root+.
    def add_main_variation(move_or_moves)
      new_line = build_movetexts(move_or_moves)
      cont = continuation_movetext

      if cont.nil?
        @line.push(*new_line)
      else
        normalize_branch_point(cont)
        vars = cont.variations
        pos = @index + 1
        old_tail = @line[(pos + 1)..] || []
        n0 = new_line[0]
        @line[pos] = n0
        @line[(pos + 1)..] = (new_line[1..] || [])
        cont.variations = []
        n0.variations = [[cont, *old_tail], *vars]
      end
      @game.root
    end

    # Move this node one slot toward the mainline among its siblings.
    # No-op for the mainline (index 0) or the first variation (index 1).
    # Returns a fresh +game.root+.
    def promote
      return @game.root if root?

      i = sibling_index
      return @game.root if i.nil? || i <= 1

      cont = parent_continuation
      normalize_branch_point(cont)
      vars = cont.variations
      vars[i - 1], vars[i - 2] = vars[i - 2], vars[i - 1]
      @game.root
    end

    # Move this node one slot toward the end among its siblings. At index 0
    # (the mainline) this is the inverse swap: variation #1 becomes the new
    # mainline and the old mainline becomes variation #1. No-op at the last
    # index. Returns a fresh +game.root+.
    def demote
      return @game.root if root?

      i = sibling_index
      sibs = @parent.children
      return @game.root if i.nil? || i == sibs.size - 1

      cont = parent_continuation
      normalize_branch_point(cont)
      vars = cont.variations
      if i.zero?
        v1 = vars.shift
        make_mainline(cont, v1, vars, old_main_position: :first)
      else
        vars[i - 1], vars[i] = vars[i], vars[i - 1]
      end
      @game.root
    end

    # Make this node the mainline at its branching point (the old mainline
    # becomes variation #1). No-op if already the mainline. Returns a
    # fresh +game.root+.
    def promote_to_main
      return @game.root if root?

      i = sibling_index
      return @game.root if i.nil? || i.zero?

      cont = parent_continuation
      normalize_branch_point(cont)
      vars = cont.variations
      vk = vars.delete_at(i - 1)
      make_mainline(cont, vk, vars, old_main_position: :first)
      @game.root
    end

    # Move this node to the last position among its siblings. At index 0
    # the last variation becomes the new mainline and the old mainline
    # becomes the last variation. Returns a fresh +game.root+.
    def demote_to_last
      return @game.root if root?

      i = sibling_index
      return @game.root if i.nil?

      cont = parent_continuation
      normalize_branch_point(cont)
      vars = cont.variations
      if i.zero?
        return @game.root if vars.empty?

        last = vars.pop
        make_mainline(cont, last, vars, old_main_position: :last)
      else
        el = vars.delete_at(i - 1)
        vars.push(el)
      end
      @game.root
    end

    # Remove this node and its subtree. If it is the mainline continuation,
    # the first remaining variation (if any) takes its place; otherwise the
    # line is truncated at this point. Returns a fresh +game.root+.
    def delete
      return @game.root if root?

      i = sibling_index
      return @game.root if i.nil?

      cont = parent_continuation
      normalize_branch_point(cont)
      vars = cont.variations
      if i.zero?
        delete_mainline_continuation(cont, vars)
      else
        vars.delete_at(i - 1)
      end
      @game.root
    end

    private

    # The MoveText played from this node's position in the current line:
    # the next entry in +line+ (nil at a terminal position). For the root,
    # +index+ is -1, so this is +line[0]+ (the first mainline move).
    def continuation_movetext
      @line && @line[@index + 1]
    end

    # Yield every first-move branching at the position before +m+ (i.e. at
    # this node's position): +m+ itself (in +l+ at +idx+), plus the first
    # move of each of +m+'s variations, plus — recursively — the first
    # moves of any variations nested on those first moves (they branch at
    # the same point, since a variation branches before the move it
    # attaches to).
    def collect_first_moves(movetext, line, idx, &block)
      return if movetext.nil?

      block.call(movetext, line, idx)
      (movetext.variations || []).each do |variation|
        next unless variation && variation[0]

        collect_first_moves(variation[0], variation, 0, &block)
      end
    end

    # Index of this node among its parent's children, or nil if root.
    def sibling_index
      @parent.children.index(self)
    end

    # The MoveText that is the mainline continuation at the PARENT's
    # position (the move this node is an alternative to, or this node
    # itself if it is the continuation).
    def parent_continuation
      @parent.line[@parent.index + 1]
    end

    # Build an Array<PGN::MoveText> from a single SAN String or an Array of
    # SANs, applying the same castling 0->O normalization as Game#moves=.
    def build_movetexts(move_or_moves)
      sans = move_or_moves.is_a?(String) ? [move_or_moves] : move_or_moves
      sans.map { |s| PGN::MoveText.new(normalize_castling(s)) }
    end

    def normalize_castling(san)
      san.include?('0') ? san.gsub('0', 'O') : san
    end

    # Hoist every variation first-move branching at the position before
    # +cont+ (recursively through nested brackets) into a single flat
    # +cont.variations+ array, clearing the first-moves' at-point variations
    # (they are now flat siblings). Internal structure of each variation
    # line (tail moves and their deeper variations) is untouched. After
    # this, +cont.variations+ is a flat Array<Array<MoveText>> in the same
    # order +children+ yields.
    def normalize_branch_point(cont)
      return if cont.nil?

      lines = []
      collect_variation_lines(cont) { |v| lines << v }
      lines.each { |v| v[0].variations = [] }
      cont.variations = lines
    end

    # Yield each variation line branching at the position before +m+ (in
    # DFS order): +m+'s direct variations, plus — recursively — the
    # variations nested on each variation's first move (they branch at the
    # same point).
    def collect_variation_lines(movetext, &block)
      (movetext.variations || []).each do |variation|
        next unless variation && variation[0]

        block.call(variation)
        collect_variation_lines(variation[0], &block)
      end
    end

    # Make +vk+ (= [vk0, *tail]) the new mainline continuation at the
    # parent's position, replacing +cont+. The old mainline (+cont+ and
    # its tail) becomes a variation appended to +others+ either before
    # (+old_main_position == :first+) or after (+:last+). +cont.variations+
    # is cleared (its at-point variations are now +vk0+'s siblings).
    def make_mainline(cont, variation, others, old_main_position:)
      line = @parent.line
      pos = @parent.index + 1
      old_tail = line[(pos + 1)..] || []
      variation0 = variation[0]
      line[pos] = variation0
      line[(pos + 1)..] = (variation[1..] || [])
      cont.variations = []
      old_var = [cont, *old_tail]
      variation0.variations =
        old_main_position == :first ? [old_var, *others] : [*others, old_var]
    end

    # Replace the mainline continuation +cont+ with its first variation
    # (+vars+ is +cont.variations+, flat). If there are no variations, the
    # line is truncated at the continuation; otherwise the first variation
    # takes the continuation's place and the remaining variations become
    # its variations.
    def delete_mainline_continuation(cont, vars)
      line = @parent.line
      pos = @parent.index + 1
      if vars.empty?
        line[pos..] = []
      else
        first_variation = vars.shift
        first_variation_move = first_variation[0]
        line[pos] = first_variation_move
        line[(pos + 1)..] = (first_variation[1..] || [])
        cont.variations = []
        first_variation_move.variations = vars
      end
    end
  end
end
