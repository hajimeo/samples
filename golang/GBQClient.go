/**
 * @see:
 *  https://cloud.google.com/bigquery/docs/reference/libraries#client-libraries-install-go
 *  https://qiita.com/Sekky0905/items/fd6ff9113d301aaa9e1d
 *      Modified to accept arguments and Removed all non English characters
 *
 * REQUIRED (to compile):
 *  go get -u cloud.google.com/go/bigquery
 *
 * DOWNLOAD:
 *  curl -O https://raw.githubusercontent.com/hajimeo/samples/master/golang/GBQClient_Linux.zip
 *
 * HOW TO RUN:
 *  export GOOGLE_APPLICATION_CREDENTIALS="$HOME/myfirstproject-xxxxxxx.json"
 *  ./GBQClient '<project id>' 'SELECT catalog_name, schema_name, location FROM INFORMATION_SCHEMA.SCHEMATA' [dataset]
 *                          -- 'SELECT * FROM <table_schema>.INFORMATION_SCHEMA.TABLES'
 *
 * NOTE Do not forget escaping quotes and backtick
 *
 */

package main

import (
    "cloud.google.com/go/bigquery"
    "context"
    "fmt"
    "google.golang.org/api/iterator"
    "log"
    "os"
)

func main() {
    projectID := os.Args[1]
    query := os.Args[2]

    ctx := context.Background()
    log.Printf("# Executing bigquery.NewClient for projectId: %v", projectID)
    client, err := bigquery.NewClient(ctx, projectID)
    if err != nil {
        log.Printf("ERROR: bigquery.NewClient failed with: %v", err)
        os.Exit(1)
    }
    log.Printf("# Executing fetchBigQueryData for query: %v", query)
    err = fetchBigQueryData(client, query)
    if err != nil {
        log.Printf("ERROR: fetchBigQueryData failed with: %v", err)
        os.Exit(1)
    }
    if len(os.Args) > 3 {
        datasetId := os.Args[3]
        log.Printf("# Executing listTables for dataset: %v", datasetId)
        err = listTables(client, datasetId)
        if err != nil {
            log.Printf("ERROR: listTables failed with: %v", err)
            os.Exit(1)
        }
    }
}

func listTables(client *bigquery.Client, datasetID string) error {
    ctx := context.Background()
    ts := client.Dataset(datasetID).Tables(ctx)
    for {
        t, err := ts.Next()
        if err == iterator.Done {
            break
        }
        if err != nil {
            return err
        }
        // Example output:
        // [myfirstproject-225906 ds_default dimstyle BASE TABLE YES NO 2019-05-22 14:20:11.941999912 +0000 UTC]
        fmt.Println(t)  //t.TableID
    }
    return nil
}

func fetchBigQueryData(client *bigquery.Client, query string) error {
    ctx := context.Background()
    q := client.Query(query)
    it, err := q.Read(ctx)
    if err != nil {
        return err
    }

    for {
        var values []bigquery.Value
        err := it.Next(&values)
        if err == iterator.Done {
            return nil
        }
        if err != nil {
            return err
        }
        fmt.Println(values)
    }
}
