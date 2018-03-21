/**
 * java SocketLocalAddrTest remote_host remote_port local_host [message]
 * java SocketLocalAddrTest ZK_HOST 2181 `hostname -f` ruok
 * java SocketLocalAddrTest WEB_SERVER 80 `hostname -f` 'GET / HTTP/1.0\r\n'
 */

import java.io.*;
import java.net.*;

public class SocketLocalAddrTest {
    public static void main(String[] args) throws Exception {
        Socket socket = null;
        String hostname = args[0];
        int port = Integer.parseInt(args[1]);

        String local_addr_ip = System.getenv("HADOOP_LOCAL_ADDR_IP");

        if (args.length > 2) {
            InetAddress local_addr = InetAddress.getByName(args[2]);
            socket = new Socket(hostname, port, local_addr, 0);
        } else if (local_addr_ip != null) {
            InetAddress local_addr = InetAddress.getByName(local_addr_ip);
            socket = new Socket(hostname, port, local_addr, 0);
        } else {
            socket = new Socket(hostname, port);
        }

        if (args.length > 3) {
            PrintWriter out = new PrintWriter(socket.getOutputStream(), false); // 'true' would be OK and no flush
            InputStream in = socket.getInputStream();
            InputStreamReader in_reader = new InputStreamReader(in);
            BufferedReader buf_reader = new BufferedReader(in_reader);

            // Sending...
            out.println(args[3]);
            out.flush();
            // Below is to read from stdin as user input
            //BufferedReader in = new BufferedReader(new InputStreamReader(socket.getInputStream()));
            //BufferedReader stdIn = new BufferedReader(new InputStreamReader(System.in));

            // Receiving/reading...
            int c;
            while ((c = buf_reader.read()) != -1) {
                System.out.print((char) c);
            }
            System.out.println("");
        }

        InetAddress ia = socket.getLocalAddress();
        System.out.println("LocalAddress: "+ia);
        socket.close();
    }
}