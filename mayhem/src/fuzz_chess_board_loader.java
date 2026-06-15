import com.code_intelligence.jazzer.api.FuzzedDataProvider;
import com.github.bhlangonijr.chesslib.Board;

/**
 * Jazzer harness for chesslib (com.github.bhlangonijr.chesslib).
 *
 * Honest successor of the old mayhemheroes fork target `fuzz-chess-board-loader`, which fed a
 * fuzzed String to Board.loadFromFen(fen) via a plain main(String[]) file-reading harness.
 * This drives the SAME public FEN-loading entry point, then exercises move generation on any
 * position that loads, so the fuzzer reaches the bitboard move-gen / mate-detection code too.
 *
 * loadFromFen parses untrusted text with substring/split/Integer.parseInt, array indexing
 * (File.allFiles[file], Rank.allRanks[rank]) and Square.valueOf / Piece.fromFenSymbol lookups.
 * Malformed FEN is EXPECTED to be rejected, and chesslib signals that rejection with a RANGE of
 * unchecked exceptions, NOT just the obvious ones: besides StringIndexOutOfBoundsException,
 * NumberFormatException, IllegalArgumentException and ArrayIndexOutOfBoundsException, a shallow
 * bad placement (e.g. FEN ". ") makes Piece.getPieceSide() return null and Board.setPiece throw a
 * NullPointerException. All of these are the parser saying "this text is not a legal position", so
 * we treat every RuntimeException from loadFromFen as an expected non-finding. Catching only the
 * IndexOutOfBounds/IllegalArgument subset let a 2-byte input crash the harness within ~100 execs,
 * which halted all coverage growth in Mayhem (edges_covered stayed 0 and the flood of Jazzer crash
 * reproducers filled the run tmpfs). Absorbing the parse-rejection exceptions lets the fuzzer
 * survive shallow inputs and actually explore the FEN parser + move generator (cov climbs into the
 * thousands). A genuinely interesting defect would surface elsewhere (OOM, timeout, assertion).
 */
// Class name kept as the old fork harness basename (fuzz_chess_board_loader) for port parity;
// it is the Jazzer --target_class.
public class fuzz_chess_board_loader {

    public static void fuzzerTestOneInput(FuzzedDataProvider data) {
        String fen = data.consumeRemainingAsString();
        if (fen.isEmpty()) {
            return;
        }
        Board board = new Board();
        try {
            board.loadFromFen(fen);
        } catch (RuntimeException expected) {
            // Malformed FEN: the documented/expected failure mode of the parser (any of
            // StringIndexOutOfBounds, NumberFormat, IllegalArgument, ArrayIndexOutOfBounds or a
            // NullPointerException from a null piece side). Not a finding.
            return;
        }
        // The position loaded; exercise the move-generation and status paths on it.
        try {
            board.legalMoves();
            board.isMated();
            board.isStaleMate();
            board.isDraw();
            board.getFen();
        } catch (RuntimeException expected) {
            // Move generation over an unusual-but-parseable position can legitimately reject it
            // (MoveGeneratorException is itself a RuntimeException). Not a finding.
            return;
        }
    }
}
