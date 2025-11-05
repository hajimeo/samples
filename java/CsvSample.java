/**
 * https://stackoverflow.com/questions/66642431/how-to-export-huge-datanear-1-million-data-using-a-csv-file-using-java
 */

import org.h2.jdbcx.JdbcDataSource;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.List;
import java.util.function.Consumer;

public class CsvSample {

    static class Player {
        int id;
        String name;
        int teamId;
        Player(int id, String name, int temId) {
            this.id = id;
            this.name = name;
            this.teamId = temId;
        }
    }

    interface PlayerRepo {
        void save(Player player);
        List<Player> findPlayers(int teamId);
        int processPlayers(int teamId, Consumer<Player> callback);
    }

    static class SimplePlayerRepo implements PlayerRepo {
        JdbcTemplate jdbc;

        SimplePlayerRepo(JdbcTemplate jdbc) {
            this.jdbc = jdbc;
            this.jdbc.execute("create table if not exists Player(id int primary key, name varchar(30), team int)");
        }

        @Override
        public void save(Player player) {
            int n = jdbc.update(
                    "update Player set name=?, team=? where id=?",
                    player.name, player.teamId, player.id);
            if (n == 0) {
                jdbc.update(
                        "insert into Player(name, team, id) values (?, ?, ?)",
                        player.name, player.teamId, player.id);
            }
        }

        @Override
        public List<Player> findPlayers(int teamId) {
            return jdbc.query(
                    "select id, name, team from Player where team=?",
                    (rs, n) -> new Player(rs.getInt(1), rs.getString(2), rs.getInt(3)),
                    teamId);
        }
        @Override
        public int processPlayers(int teamId, Consumer<Player> callback) {
            return jdbc.query(
                    "select id, name, team from Player where team=?",
                    rs -> {
                        int n = 0;
                        while (rs.next()) {
                            Player p = new Player(rs.getInt(1), rs.getString(2), rs.getInt(3));
                            callback.accept(p);
                        }
                        return n;
                    },
                    teamId);
        }
    }

    public static void main(String[] args) throws Exception {
        JdbcDataSource dataSource = new JdbcDataSource();
        dataSource.setUrl("jdbc:h2:mem:csvsample;DB_CLOSE_DELAY=-1");
        PlayerRepo repo = new SimplePlayerRepo(new JdbcTemplate(dataSource));

        // add some players
        repo.save(new Player(1, "Kobe", 1));
        repo.save(new Player(2, "LeBron", 1));
        repo.save(new Player(3, "Shaq", 1));
        repo.save(new Player(4, "Kareem", 1));
        repo.save(new Player(5, "Magic", 1));
        repo.save(new Player(6, "Larry", 2));
        repo.save(new Player(7, "Jason", 2));

        // generate CSV from List
        repo.findPlayers(1).forEach(player -> {
            System.out.println(player.id + "," + player.name);
        });

        System.out.println("----");

        // generate CSV with callback
        repo.processPlayers(1, player -> {
            System.out.println(player.id + "," + player.name);
        });
    }
}