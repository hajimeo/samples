import java.net.URI;
import java.util.Optional;

import com.atlassian.sal.api.net.Request.MethodType;
import com.atlassian.sal.api.net.RequestFactory;
import com.atlassian.sal.api.net.ResponseException;

public class SyntaxTest
{
  public static void main(String[] args) {
    final String server = args[0];
    final String username = args[1];
    final String password = args[2];

    try {
      final RequestFactory<?> requestFactory = null;
      URI uri = URI.create(server + "/api/v2/organizations");
      requestFactory
          .createRequest(MethodType.GET, uri.toString())
          .addBasicAuthentication(uri.getHost(), username, password)
          .executeAndReturn(x -> x.isSuccessful() ? Optional.empty() : Optional.of(x.getStatusText()));
    }
    catch (ResponseException | IllegalArgumentException e) {
      System.out.println(e.getMessage());
    }
  }
}
