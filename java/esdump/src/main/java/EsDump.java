
import org.apache.lucene.index.DirectoryReader;
import org.apache.lucene.index.IndexReader;
import org.apache.lucene.store.Directory;
import org.apache.lucene.store.FSDirectory;

import java.io.IOException;
import java.nio.file.Paths;

public class EsDump {
    public static void main(String[] args) throws IOException {
        String luceneIndexPath = args[0];
        Directory index = FSDirectory.open(Paths.get(luceneIndexPath));

        IndexReader reader = DirectoryReader.open(index);

        System.out.println(reader.maxDoc());

        reader.close();
        index.close();
    }
}