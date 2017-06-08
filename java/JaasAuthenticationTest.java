import javax.security.auth.login.LoginContext;
import javax.security.auth.login.LoginException;
import java.io.IOException;

import javax.security.auth.callback.Callback;
import javax.security.auth.callback.CallbackHandler;
import javax.security.auth.callback.NameCallback;
import javax.security.auth.callback.PasswordCallback;
import javax.security.auth.callback.UnsupportedCallbackException;

public class JaasAuthenticationTest {
    public static class TestCallbackHandler implements CallbackHandler {

        String name;
        String password;

        public TestCallbackHandler(String name, String password) {
            System.out.println("Callback Handler - constructor called");
            this.name = name;
            this.password = password;
        }

        public void handle(Callback[] callbacks) throws IOException, UnsupportedCallbackException {
            System.out.println("Callback Handler - handle called");

            for (int i = 0; i < callbacks.length; i++) {
                if (callbacks[i] instanceof NameCallback) {
                    NameCallback nameCallback = (NameCallback) callbacks[i];
                    nameCallback.setName(name);
                } else if (callbacks[i] instanceof PasswordCallback) {
                    PasswordCallback passwordCallback = (PasswordCallback) callbacks[i];
                    passwordCallback.setPassword(password.toCharArray());
                } else {
                    throw new UnsupportedCallbackException(callbacks[i], "The submitted Callback is unsupported");
                }
            }
        }
    }

    public static void main(String[] args) {
        System.setProperty("java.security.auth.login.config", args[0]);

        String name = "myName";
        String password = "myPassword";

        try {
            LoginContext lc = new LoginContext(args[1], new TestCallbackHandler(name, password));
            lc.login();
        } catch (LoginException e) {
            e.printStackTrace();
        }
    }
}
