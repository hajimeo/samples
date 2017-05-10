import java.net.InetAddress;
import java.net.Socket;

public class SocketLocalAddrTest {
    public static void main(String[] args) throws Exception {
        String hostname = args[0];
        int port = Integer.parseInt(args[1]);

        Socket socket = new Socket(hostname, port);
        InetAddress ia = socket.getLocalAddress();
        System.out.println(ia);
    }
}
