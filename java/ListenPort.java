import java.io.*;
import java.net.*;

/**
 * http://www.koutou-software.net/misc/java-socket/Sv.java
 *
 * @author bono
 * @version 1.0
 * @since 1.0
 */

public class ListenPort implements Runnable {

    private Socket sock_ = null;

    /**
     * @param sock
     */
    public ListenPort(Socket sock) {
        this.sock_ = sock;
    }

    protected void finalize() {
        try {
            //sock_.close();
        } catch (Exception e) {
        }
    }

    public void run() {
        try {

            DataOutputStream out = new DataOutputStream(sock_.getOutputStream());
            out.writeBytes("Hello!\n");
            sock_.close();

        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    public static void main(String[] args) {

        if (args.length != 1) {
            System.err.println("usage: java ListenPort port");
            return;
        }

        try {
            ServerSocket svsock = new ServerSocket(Integer.parseInt(args[0]));
            for (; ; ) {
                Socket sock = svsock.accept();

                ListenPort sv = new ListenPort(sock);
                Thread tr = new Thread(sv);
                tr.start();
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

    }
}