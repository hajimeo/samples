/**
 * Based on:
 * https://lucene.apache.org/core/5_5_2/demo/src-html/org/apache/lucene/demo/SearchFiles.html
 * https://ishanupamanyu.com/blog/get-all-documents-in-lucene/
 * <p>
 * long totalHits = topDocs.totalHits; // 5.5.2
 * mvn clean package && cp -v -f ./target/esdump-1.0-SNAPSHOT.jar ../../misc/esdump.jar
 * long totalHits = topDocs.totalHits.value; // 8.11.2
 * mvn clean package && cp -v -f ./target/esdump-1.0-SNAPSHOT.jar ../../misc/esdump8.jar
 * <p>
 * curl -O -L https://github.com/hajimeo/samples/raw/master/misc/esdump.jar
 * curl -O -L https://github.com/hajimeo/samples/raw/master/misc/esdump8.jar (for IQ)
 * <p>
 * Due to: Caused by: java.lang.IllegalArgumentException: An SPI class of type org.apache.lucene.codecs.Codec with name... needed to use the shade plugin
 */

import com.google.common.hash.Hashing;
import org.apache.lucene.analysis.standard.StandardAnalyzer;
import org.apache.lucene.document.Document;
import org.apache.lucene.index.DirectoryReader;
import org.apache.lucene.index.IndexReader;
import org.apache.lucene.queryparser.classic.ParseException;
import org.apache.lucene.queryparser.classic.QueryParser;
import org.apache.lucene.search.*;
import org.apache.lucene.store.Directory;
import org.apache.lucene.store.FSDirectory;

import java.io.File;
import java.io.IOException;


public class EsDump {
    static int RETRIEVE_NUM = 10;
    static long MAX_LIMIT = 0L;
    static String FIELD_NAME = "_source";

    public static void main(String[] args) throws IOException, ParseException {
        if (args.length == 0) {
            System.err.println("java -jar ./esdump.jar './sonatype-work/nexus3/elasticsearch/nexus/nodes/0/indices' 'repoName_or_hash' '.+asset_name.+' '*' '10'");
            System.err.println("# NOTE: '/' is a special char in Lucene regex.");
            System.err.println("java -jar ./esdump.jar './sonatype-work/nexus3/elasticsearch/nexus/nodes/0/indices' 'repoName_or_hash' 'component_name' 'name' '10'");
            System.err.println("# To just convert repository name to index hash:");
            System.err.println("java -jar ./esdump.jar '' 'raw-hosted'");
            return;
        }

        String luceneIndiesPath = args[0];
        String repoNameOrIndexHash = "";
        if (args.length > 1) {
            if (!args[1].isEmpty()) {
                repoNameOrIndexHash = args[1];
            }
        }
        // TODO: accept JSON query (using SearchBuilder?)
        String queryStr = "*:*";
        if (args.length > 2) {
            if (!args[2].isEmpty()) {
                queryStr = args[2];
            }
        }
        String queryField = "name"; // = path
        if (args.length > 3) {
            if (!args[3].isEmpty()) {
                queryField = args[3];
            }
        }
        if (args.length > 4) {
            if (!args[4].isEmpty()) {
                MAX_LIMIT = Long.parseLong(args[4]);
            }
        }

        Directory index = openIndex(luceneIndiesPath, repoNameOrIndexHash);
        if (index == null) {
            System.err.printf("No index under %s for %s.%n", luceneIndiesPath, repoNameOrIndexHash);
            return;
        }
        IndexReader reader = DirectoryReader.open(index);
        try {
            StandardAnalyzer analyzer = new StandardAnalyzer();
            QueryParser queryParser = new QueryParser(queryField, analyzer);
            Query q = queryParser.parse(queryStr);
            System.err.printf("Querying field:%s with '%s'%n", queryField, queryStr);
            //Query q = new MatchAllDocsQuery();
            IndexSearcher indexSearcher = new IndexSearcher(reader);
            long printedNum = searchAndPrintResults(indexSearcher, q);
            System.err.printf("Printed %d docs.%n", printedNum);
        } finally {
            reader.close();
            index.close();
        }
    }

    public static String repoName2IndexHash(String repoName) {
        return Hashing.sha1().hashUnencodedChars(repoName).toString();
    }

    public static Directory openIndex(String luceneIndiesPath, String repoName) throws IOException {
        // If repoName does not match with [0-9a-f]+, convert it to hash
        String indexHash = repoName;
        if (!repoName.matches("[0-9a-f]+")) {
            indexHash = repoName2IndexHash(repoName);
            System.err.printf("%s = %s%n", repoName, indexHash);
        }
        if (luceneIndiesPath.isEmpty()) {
            // Just converting repoName to hash
            return null;
        }

        //File probablyDir = new File(luceneIndiesPath, repoName);
        File probablyDir = new File(luceneIndiesPath, indexHash + File.separator + "0/index");
        if (!probablyDir.isDirectory()) {
            // ' || Files.isWritable(probablyDir.toPath())' doesn't work with my SSD
            System.err.printf("%s does not exist or not writable.%n", probablyDir);
            return null;
        }
        return FSDirectory.open(probablyDir.toPath());
    }

    public static long searchAndPrintResults(IndexSearcher indexSearcher, Query query) throws IOException {
        long i = 0L;
        TopDocs topDocs = indexSearcher.search(query, RETRIEVE_NUM);
        //long totalHits = topDocs.totalHits; // 5.5.2
        long totalHits = topDocs.totalHits.value; // 8.11.2
        System.err.printf("Found %d hits.%n", totalHits);
        System.out.printf("[%n");
        while (topDocs.scoreDocs.length != 0) {
            ScoreDoc[] results = topDocs.scoreDocs;
            for (ScoreDoc scoreDoc : results) {
                int docId = scoreDoc.doc;
                Document doc = indexSearcher.doc(docId);
                ++i;
                System.err.printf("# Doc %d:%n", i);
                System.out.printf("%s", doc.getBinaryValue(FIELD_NAME).utf8ToString());
                if (MAX_LIMIT > 0L && MAX_LIMIT <= i) {
                    System.out.printf("%n");
                    System.out.printf("]%n");
                    return i;
                }
                if (i < totalHits) {
                    System.out.printf(",%n");
                }
            }
            //Get next 10 documents after lastDoc. This gets us the next page of search results.
            ScoreDoc lastDoc = results[results.length - 1];
            topDocs = indexSearcher.searchAfter(lastDoc, query, RETRIEVE_NUM);
        }
        System.out.printf("]%n");
        return i;
    }
}