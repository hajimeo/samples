package hadoop;

import java.io.IOException;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Arrays;
import java.util.List;

import org.apache.lucene.document.Document;
import org.apache.lucene.index.DirectoryReader;
import org.apache.lucene.index.IndexableField;
import org.apache.lucene.store.Directory;
import org.apache.lucene.store.FSDirectory;

/**
 * Created by hosako on 18/7/17.
 *
 * javac -classpath /usr/lib/ambari-infra-solr/server/solr-webapp/webapp/WEB-INF/lib/*:. SolrIndexReader.java
 * java -cp /usr/lib/ambari-infra-solr/server/solr-webapp/webapp/WEB-INF/lib/*:. SolrIndexReader /opt/ambari_infra_solr/data/ranger_audits_shard1_replica1/data/index 1
 *
 * Minimum jars:
 * /usr/lib/ambari-infra-solr/server/solr-webapp/webapp/WEB-INF/lib/lucene-core-5.5.2.jar:/usr/lib/ambari-infra-solr/server/solr-webapp/webapp/WEB-INF/lib/lucene-queryparser-5.5.2.jar:/usr/lib/ambari-infra-solr/server/solr-webapp/webapp/WEB-INF/lib/solr-solrj-5.5.2.jar
 *
 * @ref https://stackoverflow.com/questions/17849946/how-to-read-data-from-solr-data-index
 */
public class SolrIndexReader {

    public static void main(String[] args) throws IOException {
        Path fp = Paths.get(args[0]);
        Directory dirIndex = FSDirectory.open(fp);
        DirectoryReader directoryReader = DirectoryReader.open(dirIndex);
        Document doc = null;
        int num = directoryReader.numDocs();

        if (args.length > 1) {
            num = Integer.parseInt(args[1]);
        }
        System.err.println("Retrieving "+num+" documents.");

        for (int i = 0; i < num; i++) {
            System.err.println("Document ID "+i);
            doc = directoryReader.document(i);
            List l = doc.getFields();
            for (int j = 0; i < l.size(); j++) {
                try {
                    IndexableField f = (IndexableField) l.get(j);
                    System.out.println("Field: "+f.name());
                    System.out.println("Values: "+ Arrays.toString(doc.getValues(f.name())));
                }
                catch (IndexOutOfBoundsException e) {
                    System.err.println("TODO: IndexOutOfBoundsException on Document ID "+i+". Moving to next doc.");
                    break;
                }
            }
        }

        directoryReader.close();
        dirIndex.close();
    }
}