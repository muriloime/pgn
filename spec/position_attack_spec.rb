# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PGN::Position, 'attack helpers' do
  describe '#in_check?' do
    it 'is false for the start position' do
      expect(PGN::Position.start.in_check?).to be(false)
    end

    it 'is true when the side to move is checked' do
      # White king on e1, black rook on e2 giving check.
      pos = PGN::FEN.new('4k3/8/8/8/8/8/4r3/4K3 w - - 0 1').to_position
      expect(pos.in_check?).to be(true)
    end

    it 'is false when a piece blocks the check' do
      pos = PGN::FEN.new('4k3/8/8/8/8/8/4p3/4R1K1 w - - 0 1').to_position
      expect(pos.in_check?).to be(false)
    end

    it 'is false for black to move when black is not in check' do
      pos = PGN::FEN.new('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1').to_position
      expect(pos.in_check?).to be(false)
    end
  end

  describe '#attackers' do
    it 'lists the attacking squares for the opponent color' do
      pos = PGN::FEN.new('4k3/8/8/8/8/8/4r3/4K3 w - - 0 1').to_position
      # White king on e1 is attacked by the black rook on e2.
      expect(pos.attackers('e1')).to include('e2')
    end

    it 'lists pawn attackers' do
      # White pawn d5 attacks e6 and c6; ask for attackers of e6 by white.
      pos = PGN::FEN.new('4k3/8/8/3P4/8/8/8/4K3 w - - 0 1').to_position
      expect(pos.attackers('e6', 'w')).to include('d5')
    end

    it 'lists knight attackers' do
      pos = PGN::FEN.new('4k3/8/8/8/8/2N5/8/4K3 w - - 0 1').to_position
      expect(pos.attackers('e4', 'w')).to include('c3')
    end

    it 'lists bishop/rook/queen attackers' do
      pos = PGN::FEN.new('4k3/8/8/8/8/8/8/Q3K3 w - - 0 1').to_position
      expect(pos.attackers('a8', 'w')).to include('a1')
    end

    it 'returns an empty array when nothing attacks the square' do
      pos = PGN::Position.start
      expect(pos.attackers('e4')).to eq([])
    end
  end
end
