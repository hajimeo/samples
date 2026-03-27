# simpleWebServer

A minimal Java HTTP server that accepts file uploads on `http://localhost:8080/upload`.

## Requirements

- Java 8 or newer
- Maven 3.x

## Build

```bash
cd /Users/hosako/IdeaProjects/samples/java/simpleWebServer
mvn clean package
```

This creates:

```text
target/simpleWebServer-1.0-SNAPSHOT.jar
```

## Run

Start the server from the project directory:

```bash
java -jar target/simpleWebServer-1.0-SNAPSHOT.jar
```

Use a custom port with a command-line argument:

```bash
java -jar target/simpleWebServer-1.0-SNAPSHOT.jar 9090
```

Or with an environment variable:

```bash
PORT=9090 java -jar target/simpleWebServer-1.0-SNAPSHOT.jar
```

If both are provided, the command-line argument takes precedence.

You should see output similar to:

```text
Minimal server running.
Send a PUT request to: http://localhost:8080/upload
```

## Upload a File

Send a `PUT` or `POST` request to `/upload`:

```bash
curl -X PUT --data-binary @somefile.bin http://localhost:8080/upload
```

Or:

```bash
curl -X POST --data-binary @somefile.bin http://localhost:8080/upload
```

When the upload succeeds, the server writes the content to:

```text
uploaded_test_file.bin
```

The file is created in the server's current working directory.

## Notes

- Only `PUT` and `POST` are accepted on `/upload`.
- Other HTTP methods return `405 Method Not Allowed`.
- The default port is `8080`.
