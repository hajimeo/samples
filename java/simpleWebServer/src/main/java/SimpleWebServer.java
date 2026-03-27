import com.sun.net.httpserver.HttpServer;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.InetSocketAddress;
import java.net.URI;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

public class SimpleWebServer {
    private static final String DEFAULT_FILENAME = "uploaded_test_file.bin";

    public static void main(String[] args) throws Exception {
        int port = resolvePort(args);
        Path outputDirectory = resolveOutputDirectory(args);
        HttpServer server = HttpServer.create(new InetSocketAddress(port), 0);

        server.createContext("/upload", exchange -> {
            String method = exchange.getRequestMethod();

            if ("PUT".equalsIgnoreCase(method) || "POST".equalsIgnoreCase(method)) {
                String destinationFilename;
                try {
                    destinationFilename = resolveDestinationFilename(exchange.getRequestURI());
                } catch (IllegalArgumentException e) {
                    byte[] response = (e.getMessage() + "\n").getBytes();
                    exchange.sendResponseHeaders(400, response.length);
                    exchange.getResponseBody().write(response);
                    exchange.getResponseBody().close();
                    return;
                }
                Path destinationPath = outputDirectory.resolve(destinationFilename).normalize();
                System.out.println("Receiving file via " + method + "...");

                // Read from the request body and write to a local file
                try (InputStream is = exchange.getRequestBody();
                     FileOutputStream os = new FileOutputStream(destinationPath.toFile())) {

                    copy(is, os);
                }

                String response = "File received successfully!\n";
                exchange.sendResponseHeaders(200, response.length());
                exchange.getResponseBody().write(response.getBytes());
                exchange.getResponseBody().close();
                System.out.println("File saved as '" + destinationPath + "'");

            } else {
                // Reject GET, DELETE, etc.
                exchange.sendResponseHeaders(405, -1);
            }
        });

        server.setExecutor(null);
        server.start();
        System.out.println("Minimal server running.");
        System.out.println("Send a PUT request to: http://localhost:" + port + "/upload");
        System.out.println("Uploads are saved under: " + outputDirectory.toAbsolutePath());
    }

    private static void copy(InputStream input, FileOutputStream output) throws IOException {
        byte[] buffer = new byte[8192];
        int read;
        while ((read = input.read(buffer)) != -1) {
            output.write(buffer, 0, read);
        }
    }

    private static int resolvePort(String[] args) {
        String rawPort = args.length > 0 ? args[0] : System.getenv("PORT");

        if (rawPort == null || rawPort.trim().isEmpty()) {
            return 8080;
        }

        int port = Integer.parseInt(rawPort.trim());
        if (port < 1 || port > 65535) {
            throw new IllegalArgumentException("Port must be between 1 and 65535");
        }

        return port;
    }

    private static Path resolveOutputDirectory(String[] args) throws IOException {
        String rawDirectory = args.length > 1 ? args[1] : System.getenv("OUTPUT_DIR");
        Path outputDirectory;

        if (rawDirectory == null || rawDirectory.trim().isEmpty()) {
            outputDirectory = Paths.get(".").toAbsolutePath().normalize();
        } else {
            outputDirectory = Paths.get(rawDirectory.trim()).toAbsolutePath().normalize();
        }

        Files.createDirectories(outputDirectory);
        return outputDirectory;
    }

    private static String resolveDestinationFilename(URI requestUri) {
        String path = requestUri.getPath();
        if (path == null || "/upload".equals(path) || "/upload/".equals(path)) {
            return DEFAULT_FILENAME;
        }

        String prefix = "/upload/";
        if (!path.startsWith(prefix)) {
            return DEFAULT_FILENAME;
        }

        String candidate = path.substring(prefix.length()).trim();
        if (candidate.isEmpty()) {
            return DEFAULT_FILENAME;
        }

        if (candidate.contains("/") || candidate.contains("\\")) {
            throw new IllegalArgumentException("Nested paths are not allowed in upload filename");
        }

        return candidate;
    }
}
