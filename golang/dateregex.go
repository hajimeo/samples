/**
 * Output a regex strings for date range
 * Accept start and end datetime strings
 * ./dateregex "start_ISO_datetime" "end_ISO_datetime"
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
    // TODO: it doesn't work with YYYY/MM/DD
    layout_in := "2006-01-02 15:04"
    layout_out := "2006-01-02 15:0"
    loc, _ := time.LoadLocation("UTC")
    interval, err := strconv.ParseInt("600", 10, 64) // 10 mins

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

    end_unixtime := end_time.Unix()
    last_date_str := ""

    // TODO: need more sophisticated logic
    for current_unixtime := start_unixtime; current_unixtime < (end_unixtime+interval); current_unixtime += interval {
        current_layout_out := layout_out
        current_time := time.Unix(current_unixtime, 0).In(loc)
        current_date_str := current_time.Format("2006-01-02")
        hr, _, _ := current_time.Clock()
        //fmt.Println("# "+strconv.Itoa(hr))
        //fmt.Println("# "+strconv.FormatInt(interval, 10))

        // Cover whole day
        if hr == 0 && (end_unixtime-current_unixtime) >= (60*60*24) {
            current_layout_out = "2006-01-02"
            current_unixtime += (60 * 60 * 24)
        } else if last_date_str == current_date_str {
            fmt.Printf("|%02d", hr)
            current_unixtime += (3600)
            continue
        } else if (end_unixtime-current_unixtime) >= (60*60) {
            // Next date
            if last_date_str != current_date_str {
                if last_date_str != "" {
                    fmt.Print(")|")
                }
                fmt.Print(current_date_str+" (")
                fmt.Printf("%02d", hr)
            }
            current_unixtime += (3599)  // Strange. 3600 doesn't work. Skips last hour
            last_date_str = current_date_str
            continue
        }

        if last_date_str != "" {
            fmt.Print(")|")
            last_date_str = ""
        }

        current_time_str := current_time.Format(current_layout_out)

        last_c := current_time_str[(len(current_time_str) - 1):]
        if last_c == ":" {
            fmt.Print(current_time_str[:(len(current_time_str) - 1)])
        } else {
            fmt.Print(current_time_str)
        }
        if (current_unixtime + interval) <= end_unixtime {
            fmt.Print("|")
        }
    }
    if last_date_str != "" {
        fmt.Print(")")
    }
    fmt.Println()
}
