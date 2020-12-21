import static org.junit.jupiter.api.Assertions.*;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import org.junit.jupiter.api.Test;

class BlobPathTest
{
  @Test
  void isBlobId() {
    String blobId = "aaaa";
    assertFalse(BlobPath.isBlobId(blobId));
    blobId = "f3fb8f3a-1cd4-494d-855f-75820aabbf2a";
    assertTrue(BlobPath.isBlobId(blobId));
  }

  @Test
  void blobPath() {
    String blobId = "f3fb8f3a-1cd4-494d-855f-75820aabbf2a";
    String blob_path = BlobPath.blobPath(blobId);
    assertEquals("vol-13/chap-43/f3fb8f3a-1cd4-494d-855f-75820aabbf2a", blob_path);
  }

  @Test
  void genPropertiesContent() {
    String jsontStr =
        "{\"blob_ref\":\"default@9C281...:56df5d9d-a...\",\"created_by\":\"admin\",\"size\":1461,\"repository_name\":\"maven-releases\",\"blob_created\":\"2020-01-23 01:46:07\",\"created_by_ip\":\"192.168.1.31\",\"content_type\":\"application/java-archive\",\"name\":\"com/example/nexus-proxy/1.1/nexus-proxy-1.1.jar\",\"sha1\":\"9c024...\"}";
    JsonObject js = new JsonParser().parse(jsontStr).getAsJsonObject();
    String obj_str = BlobPath.genPropertiesContent(js);
    assertEquals("#<null>,000+0000\n" +
        "#Mon Jan 01 00:00:00 UTC 2020\n" +
        "@BlobStore.created-by=admin\n" +
        "size=1461\n" +
        "@Bucket.repo-name=maven-releases\n" +
        "creationTime=2020-01-23 01:46:07\n" +
        "@BlobStore.created-by-ip=192.168.1.31\n" +
        "@BlobStore.content-type=application/java-archive\n" +
        "@BlobStore.blob-name=com/example/nexus-proxy/1.1/nexus-proxy-1.1.jar\n" +
        "sha1=9c024...", obj_str);
  }

  @Test
  void get() {
    String jsontStr =
        "{\"blob_ref\":\"default@9C281...:56df5d9d-a...\",\"created_by\":\"admin\",\"size\":1461,\"repository_name\":\"maven-releases\",\"blob_created\":\"2020-01-23 01:46:07\",\"created_by_ip\":\"192.168.1.31\",\"content_type\":\"application/java-archive\",\"name\":\"com/example/nexus-proxy/1.1/nexus-proxy-1.1.jar\",\"sha1\":\"9c024...\"}";
    JsonObject js = new JsonParser().parse(jsontStr).getAsJsonObject();
    assertEquals("<null>", BlobPath.get(js, "test"));
    assertEquals("default@9C281...:56df5d9d-a...", BlobPath.get(js, "blob_ref"));
    // At this moment, converting everything to string
    assertEquals("1461", BlobPath.get(js, "size"));
  }
}