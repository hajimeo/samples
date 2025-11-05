import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.sql.Statement;

public class SerializationFailureSimulation {

    public static void main(String[] args) {
        Thread transaction1 = new Thread(() -> {
            try (Connection conn = DriverManager.getConnection("jdbc:yourdatabaseurl", "username", "password")) {
                conn.setTransactionIsolation(Connection.TRANSACTION_SERIALIZABLE);
                conn.setAutoCommit(false);
                try (Statement stmt = conn.createStatement()) {
                    stmt.executeQuery("SELECT * FROM your_table WHERE id = 1 FOR UPDATE");
                    Thread.sleep(2000); // Wait to simulate delay
                    stmt.executeUpdate("UPDATE your_table SET column_name = value WHERE id = 1");
                    conn.commit();
                } catch (SQLException | InterruptedException e) {
                    conn.rollback();
                    throw new RuntimeException("Transaction 1 failed", e);
                }
            } catch (SQLException e) {
                e.printStackTrace();
            }
        });

        Thread transaction2 = new Thread(() -> {
            try (Connection conn = DriverManager.getConnection("jdbc:yourdatabaseurl", "username", "password")) {
                conn.setTransactionIsolation(Connection.TRANSACTION_SERIALIZABLE);
                conn.setAutoCommit(false);
                try (Statement stmt = conn.createStatement()) {
                    Thread.sleep(1000); // Start after transaction 1 but overlap
                    stmt.executeQuery("SELECT * FROM your_table WHERE id = 1 FOR UPDATE");
                    stmt.executeUpdate("UPDATE your_table SET column_name = value WHERE id = 1");
                    conn.commit();
                } catch (SQLException | InterruptedException e) {
                    conn.rollback();
                    throw new RuntimeException("Transaction 2 failed", e);
                }
            } catch (SQLException e) {
                e.printStackTrace();
            }
        });

        transaction1.start();
        transaction2.start();
    }
}