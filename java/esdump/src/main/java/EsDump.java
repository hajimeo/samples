/**
 * Based on:
 *  https://lucene.apache.org/core/5_5_2/demo/src-html/org/apache/lucene/demo/SearchFiles.html
 *  https://ishanupamanyu.com/blog/get-all-documents-in-lucene/
 */

import com.google.common.hash.Hashing;
import org.apache.lucene.analysis.standard.StandardAnalyzer;
import org.apache.lucene.document.Document;
import org.apache.lucene.index.DirectoryReader;
import org.apache.lucene.index.IndexReader;
import org.apache.lucene.index.IndexableField;
import org.apache.lucene.queryparser.classic.ParseException;
import org.apache.lucene.queryparser.classic.QueryParser;
import org.apache.lucene.search.*;
import org.apache.lucene.store.Directory;
import org.apache.lucene.store.FSDirectory;

import java.io.File;
import java.io.IOException;
import java.util.List;


public class EsDump {
    static int RETRIEVE_NUM = 10;
    static String FIELD_NAME = "_source";

    public EsDump() {
    }

    public static void main(String[] args) throws IOException, ParseException {
        if (args.length == 0) {
            System.out.println("EsDump ./sonatype-work/nexus3/elasticsearch/nexus/nodes/0/indices raw-hosted");
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

        Directory index = openIndex(luceneIndiesPath, repoNameOrIndexHash);
        IndexReader reader = DirectoryReader.open(index);
        try {
            StandardAnalyzer analyzer = new StandardAnalyzer();
            QueryParser queryParser = new QueryParser("title", analyzer);
            Query q = queryParser.parse(queryStr);
            //Query q = new MatchAllDocsQuery();
            IndexSearcher indexSearcher = new IndexSearcher(reader);
            searchAndPrintResults(indexSearcher, q);
        } finally {
            reader.close();
            index.close();
        }
    }

    public static String repoName2IndexHash(String repoName) {
        return Hashing.sha1().hashUnencodedChars(repoName).toString();
    }

    public static Directory openIndex(String luceneIndiesPath, String repoNameOrIndexHash) throws IOException {
        File probablyDir = new File(luceneIndiesPath, repoNameOrIndexHash);
        if (!probablyDir.isDirectory()) {
            probablyDir = new File(luceneIndiesPath, repoName2IndexHash(repoNameOrIndexHash));
        }
        return FSDirectory.open(probablyDir.toPath());
    }

    public static void printDoc(Document doc) {
        //System.out.printf("# toString: %s%n", doc.toString());
        List<IndexableField> fields = doc.getFields();
        for (IndexableField field : fields) {
            System.out.println("  " + field.name() + " = ");
            String[] values = doc.getValues(field.name());
            for (String value : values) {
                System.out.println("    " + value);
            }
        }
    }

    public static void searchAndPrintResults(IndexSearcher indexSearcher, Query query) throws IOException {
        TopDocs topDocs = indexSearcher.search(query, RETRIEVE_NUM);

        long totalHits = topDocs.totalHits;
        System.out.printf("Found %d hits.%n", totalHits);

        while (topDocs.scoreDocs.length != 0) {
            ScoreDoc[] results = topDocs.scoreDocs;
            for (ScoreDoc scoreDoc : results) {
                int docId = scoreDoc.doc;
                Document doc = indexSearcher.doc(docId);
                printDoc(doc);
            }
            break;
            //Get next 10 documents after lastDoc. This gets us the next page of search results.
            //ScoreDoc lastDoc = results[results.length - 1];
            //topDocs = indexSearcher.searchAfter(lastDoc, query, RETRIEVE_NUM);
        }
    }
}