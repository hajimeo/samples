/*
 * Simple mail sending class
 * Based on https://pepipost.com/tutorials/examples-for-sending-emails-from-javamail-api/
 *
 * NOTE: Java 8 only!!!
 *       Java 11 gets java.lang.NoClassDefFoundError: javax/activation/DataHandler
 *
 * cd /var/tmp/share/java/
 * curl -O https://repo1.maven.org/maven2/com/sun/mail/javax.mail/1.6.2/javax.mail-1.6.2.jar
 * javac -cp ./javax.mail-1.6.2.jar SendMail.java
 * java -cp ./javax.mail-1.6.2.jar:. -Djavax.net.debug=ssl,keymanager -Djavax.net.ssl.trustStore=/var/tmp/share/cert/standalone.localdomain.jks \
   -Dfrom=from@test.com -Dto=to@test.com -Dsubject=test -Dtext="this is test" \
   -Dmail.smtp.host=localhost -Dmail.smtp.port=25 -Dmail.smtp.starttls.enable=true SendMail
 */
import java.util.Properties;
import javax.mail.Message;
import javax.mail.MessagingException;
import javax.mail.PasswordAuthentication;
import javax.mail.Session;
import javax.mail.Transport;
import javax.mail.internet.InternetAddress;
import javax.mail.internet.MimeMessage;

public class SendMail
{
  public static void main(String[] args) {
    // Get system properties
    Properties props = System.getProperties();
    // NOTE: Expecting above includes from, to, subject, text, mail.smtp.host, mail.smtp.port, mail.smtp.starttls.enable (optional)
    // @see: https://javaee.github.io/javamail/docs/api/com/sun/mail/smtp/package-summary.html
    Session session = Session.getInstance(props);

    // Used to debug SMTP issues
    session.setDebug(true);

    try {
      // Create a default MimeMessage object.
      MimeMessage message = new MimeMessage(session);

      // Set From: header field of the header.
      message.setFrom(new InternetAddress(props.getProperty("from")));

      // Set To: header field of the header.
      message.addRecipient(Message.RecipientType.TO, new InternetAddress(props.getProperty("to")));

      // Set Subject: header field
      message.setSubject(props.getProperty("subject"));

      // Now set the actual message
      message.setText(props.getProperty("text"));

      System.out.println("sending...");
      // Send message
      Transport.send(message);
      System.out.println("Sent message successfully....");
    }
    catch (MessagingException mex) {
      mex.printStackTrace();
    }
  }
}