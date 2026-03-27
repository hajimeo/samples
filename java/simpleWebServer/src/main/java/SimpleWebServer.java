import com.sun.net.httpserver.HttpServer;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.InetSocketAddress;

public class SimpleWebServer {
    public static void main(String[] args) throws Exception {
        // Start server on port 8080
        HttpServer server = HttpServer.create(new InetSocketAddress(8080), 0);

        server.createContext("/upload", exchange -> {
            String method = exchange.getRequestMethod();

            if ("PUT".equalsIgnoreCase(method) || "POST".equalsIgnoreCase(method)) {
                System.out.println("Receiving file via " + method + "...");

                // Read from the request body and write to a local file
                try (InputStream is = exchange.getRequestBody();
                     FileOutputStream os = new FileOutputStream("uploaded_test_file.bin")) {

                    copy(is, os);
                }

                String response = "File received successfully!\n";
                exchange.sendResponseHeaders(200, response.length());
                exchange.getResponseBody().write(response.getBytes());
                exchange.getResponseBody().close();
                System.out.println("File saved as 'uploaded_test_file.bin'");

            } else {
                // Reject GET, DELETE, etc.
                exchange.sendResponseHeaders(405, -1);
            }
        });

        server.setExecutor(null);
        server.start();
        System.out.println("Minimal server running.");
        System.out.println("Send a PUT request to: http://localhost:8080/upload");
    }

    private static void copy(InputStream input, FileOutputStream output) throws IOException {
        byte[] buffer = new byte[8192];
        int read;
        while ((read = input.read(buffer)) != -1) {
            output.write(buffer, 0, read);
        }
    }
}
