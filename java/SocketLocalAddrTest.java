import java.net.InetAddress;
import java.net.Socket;

public class SocketLocalAddrTest {
    public static void main(String[] args) throws Exception {
        Socket socket=null;
        String hostname = args[0];
        int port = Integer.parseInt(args[1]);

        String local_addr_ip = System.getenv("HADOOP_LOCAL_ADDR_IP");

        if (args.length > 2) {
            InetAddress local_addr = InetAddress.getByName(args[2]);
            socket = new Socket(hostname, port, local_addr, 0);
        }
        else if (local_addr_ip != null) {
            InetAddress local_addr = InetAddress.getByName(local_addr_ip);
            socket = new Socket(hostname, port, local_addr, 0);
        }
        else {
            socket = new Socket(hostname, port);
        }
        InetAddress ia = socket.getLocalAddress();
        System.out.println(ia);
    }
}
