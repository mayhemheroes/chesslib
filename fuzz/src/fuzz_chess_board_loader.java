import com.github.bhlangonijr.chesslib.Board;
import java.nio.file.Paths;
import java.nio.file.Files;
import java.nio.file.Path;

public class fuzz_chess_board_loader {
    public static void main(String[] args) throws Exception
    {
        Path path = Paths.get(args[0]);
        byte[] data = Files.readAllBytes(path);
        if(data.length == 0) {
            return;
        }

        System.out.println(new String(data));
        Board board = new Board();
        board.loadFromFen(new String(data));
    }
}
