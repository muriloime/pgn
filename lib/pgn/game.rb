module PGN
  class Game
    attr_accessor :tags, :moves, :result

    LEFT  = "a"
    RIGHT = "d"
    EXIT  = "\u{0003}"

    def initialize(tags, moves, result)
      self.tags   = tags
      self.moves  = moves
      self.result = result
    end

    def positions
      @positions ||= begin
        position = PGN::Position.start
        arr = [position]
        self.moves.each do |move|
          new_pos = position.move(move)
          arr << new_pos
          position = new_pos
        end
        arr
      end
    end

    def fen_list
      self.positions.map {|p| p.to_fen.inspect }
    end

    def play
      index = 0
      loop do
        puts "\e[H\e[2J"
        puts self.positions[index].inspect
        case STDIN.getch
        when LEFT
          index -= 1 if index > 0
        when RIGHT
          index += 1 if index < self.moves.length
        when EXIT
          break
        end
      end
    end
  end
end
