/**
 * Output a regex strings for date range
 * Accept start and end datetime strings
 * ./dateregex "start_ISO_datetime" "end_ISO_datetime" [interval] [input date go-style format] [out date go-style format]
 */
package main

import (
    "fmt"
    "time"
    "os"
    "strconv"
)

func main() {
    // Defaults
    layout_in := "2006-01-02 15:04"
    layout_out := "2006-01-02 15:04"
    loc, _ := time.LoadLocation("UTC")
    interval, err := strconv.ParseInt("600", 10, 64) // 10 mins

    if len(os.Args) > 4 && len(os.Args[4]) > 0 {
        layout_in = os.Args[4]
        //fmt.Println(layout_in)
    }

    start_str := os.Args[1]
    st, err := time.Parse(layout_in, start_str)
    if err != nil {
        fmt.Println(err)
        os.Exit(1)
    }
    stu := st.Unix()

    et := time.Now()
    if len(os.Args) > 2 && len(os.Args[2]) > 0 {
        end_str := os.Args[2]
        et, err = time.Parse(layout_in, end_str)
        if err != nil {
            fmt.Println(err)
            os.Exit(1)
        }
    }
    //fmt.Println(et.Format(layout_in))
    etu := et.Unix()

    if len(os.Args) > 3 && len(os.Args[3]) > 0 {
        interval, err = strconv.ParseInt(os.Args[3], 10, 64)
        if err != nil {
            fmt.Println(err)
            os.Exit(1)
        }
    }

    if len(os.Args) > 5 && len(os.Args[5]) > 0 {
        layout_out = os.Args[5]
    }

    for ctu := stu; ctu <= etu; ctu += interval {
        ct := time.Unix(ctu, 0).In(loc)
        cts := ct.Format(layout_out)
        fmt.Print(cts[:(len(cts)-1)])
        if (ctu + interval) <= etu {
            fmt.Print("|")
        }
    }
    fmt.Println()
}
