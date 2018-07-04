/**
 * Output a regex strings for date range
 * Accept start and end datetime strings
 */
package main

import (
    "fmt"
    "time"
    "os"
    "strconv"
)

func main() {
    layout := "2006-01-02 15:04"
    interval, err := strconv.ParseInt("600", 10, 64) // 10 mins

    start_str := os.Args[1]
    st, err := time.Parse(layout, start_str)
    if err != nil {
        fmt.Println(err)
        os.Exit(1)
    }
    stu := st.Unix()

    end_str := os.Args[2]
    et, err := time.Parse(layout, end_str)
    if err != nil {
        fmt.Println(err)
        os.Exit(1)
    }
    etu := et.Unix()

    if len(os.Args) > 3 {
        interval, err = strconv.ParseInt(os.Args[3], 10, 64)
        if err != nil {
            fmt.Println(err)
            os.Exit(1)
        }
    }

    loc, _ := time.LoadLocation("UTC")
    for ctu := stu; ctu <= etu; ctu += interval {
        ct := time.Unix(ctu, 0).In(loc)
        cts := ct.Format(layout)
        fmt.Print(cts[:(len(cts)-1)])
        if (ctu + interval) <= etu {
            fmt.Print("|")
        }
    }
    fmt.Println()
}
