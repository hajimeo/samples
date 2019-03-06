/**
 * Ref: https://cloud.google.com/bigquery/docs/reference/libraries#client-libraries-install-go
 *  go get -u cloud.google.com/go/bigquery
 *
 * HOW TO RUN:
 *  export GOOGLE_APPLICATION_CREDENTIALS="/home/user/Downloads/[FILE_NAME].json"
 *  ./GBQClient 'myfirstproject-xxxxxxx' 'SELECT * FROM `bigquery-public-data.usa_names.usa_1910_2013` LIMIT 2'
 *
 * NOTE Do not forget escaping quotes and backtick
 *
 * Ref: https://qiita.com/Sekky0905/items/fd6ff9113d301aaa9e1d
 *  Modified to accept arguments and Removed all non English characters
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
    fetchBigQueryData()
}

func fetchBigQueryData() {
    projectID := os.Args[1]
    query := os.Args[2]

    ctx := context.Background()
    client, err := bigquery.NewClient(ctx, projectID)

    if err != nil {
        log.Printf("Failed to create client:%v", err)
    }

    q := client.Query(query)
    it, err := q.Read(ctx)

    if err != nil {
        log.Println("Failed to Read Query:%v", err)
    }

    for {
        var values []bigquery.Value
        err := it.Next(&values)
        if err == iterator.Done {
            break
        }

        if err != nil {
            log.Println("Failed to Iterate Query:%v", err)
        }

        fmt.Println(values)
    }
}
