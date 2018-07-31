/**
 * Output a regex strings for date range
 * Accept start and end datetime strings
 * ./dateregex "start_ISO_datetime" "end_ISO_datetime" [input datetime go-style format] [output datetime go-style format]
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

    if len(os.Args) > 3 && len(os.Args[3]) > 0 {
        layout_in = os.Args[3]
        //fmt.Println(layout_in)
    }

    start_str := os.Args[1]
    start_time, err := time.Parse(layout_in, start_str)
    if err != nil {
        fmt.Println(err)
        os.Exit(1)
    }
    start_unixtime := start_time.Unix()

    end_time := time.Now()
    if len(os.Args) > 2 && len(os.Args[2]) > 0 {
        end_str := os.Args[2]
        end_time, err = time.Parse(layout_in, end_str)
        if err != nil {
            fmt.Println(err)
            os.Exit(1)
        }
    }
    //fmt.Println(end_time.Format(layout_in))
    end_unixtime := end_time.Unix()

    if len(os.Args) > 4 && len(os.Args[4]) > 0 {
        layout_out = os.Args[4]
    } else {
        if (end_unixtime - start_unixtime) >= 3600 {
            layout_out = "2006-01-02 15:"
            interval, err = strconv.ParseInt("3600", 10, 64) // 1 hour
        }
        // TODO: need more sophisticated logic
    }

    for current_unixtime := start_unixtime; current_unixtime <= end_unixtime; current_unixtime += interval {
        current_layout_out := layout_out
        current_time := time.Unix(current_unixtime, 0).In(loc)
        hr, _, _ := current_time.Clock()
        if hr == 0 && (end_unixtime-current_unixtime) > (60*60*24) {
            current_layout_out = "2006-01-02"
            current_unixtime += (60*60*24)
        }

        //fmt.Println(current_layout_out)
        current_time_str := current_time.Format(current_layout_out)

        last_c := current_time_str[(len(current_time_str)-1):]
        if last_c == ":" {
            fmt.Print(current_time_str[:(len(current_time_str)-1)])
        } else {
            fmt.Print(current_time_str)
        }
        if (current_unixtime + interval) <= end_unixtime {
            fmt.Print("|")
        }
    }
    fmt.Println()
}
