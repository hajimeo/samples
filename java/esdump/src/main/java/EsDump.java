/**
 * Based on:
 * https://lucene.apache.org/core/5_5_2/demo/src-html/org/apache/lucene/demo/SearchFiles.html
 * https://ishanupamanyu.com/blog/get-all-documents-in-lucene/
 *
 * mvn clean package && cp -v -f ./target/esdump-1.0-SNAPSHOT-jar-with-dependencies.jar ../../misc/esdump.jar
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

    public EsDump() {
    }

    public static void main(String[] args) throws IOException, ParseException {
        if (args.length == 0) {
            System.err.println("EsDump './sonatype-work/nexus3/elasticsearch/nexus/nodes/0/indices' 'raw-hosted' '.+name_aka_path.+'");
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
        IndexReader reader = DirectoryReader.open(index);
        try {
            StandardAnalyzer analyzer = new StandardAnalyzer();
            QueryParser queryParser = new QueryParser(queryField, analyzer);
            Query q = queryParser.parse(queryStr);
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
        File probablyDir = new File(luceneIndiesPath, repoName);
        if (!probablyDir.isDirectory()) {
            probablyDir = new File(luceneIndiesPath, repoName2IndexHash(repoName) + File.separator + "0/index");
        }
        return FSDirectory.open(probablyDir.toPath());
    }

    public static void printDoc(Document doc) {
        System.out.printf("%s%n", doc.getBinaryValue(FIELD_NAME).utf8ToString());
    }

    public static long searchAndPrintResults(IndexSearcher indexSearcher, Query query) throws IOException {
        long i = 0L;
        TopDocs topDocs = indexSearcher.search(query, RETRIEVE_NUM);
        long totalHits = topDocs.totalHits;
        System.err.printf("Found %d hits.%n", totalHits);
        while (topDocs.scoreDocs.length != 0) {
            ScoreDoc[] results = topDocs.scoreDocs;
            for (ScoreDoc scoreDoc : results) {
                int docId = scoreDoc.doc;
                Document doc = indexSearcher.doc(docId);
                i++;
                System.err.printf("# Doc %d:%n", i);
                printDoc(doc);
                if (MAX_LIMIT > 0 && MAX_LIMIT <= i) {
                    return i;
                }
            }
            //Get next 10 documents after lastDoc. This gets us the next page of search results.
            ScoreDoc lastDoc = results[results.length - 1];
            topDocs = indexSearcher.searchAfter(lastDoc, query, RETRIEVE_NUM);
        }
        return i;
    }
}