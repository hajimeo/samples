/*
Based on https://raw.githubusercontent.com/drael/GOnetstat/master/gonetstat.go
Ref: https://www.kernel.org/doc/Documentation/networking/proc_net_tcp.txt

go mod init github.com/hajimeo/samples/golang/GoNetStat
go get -u -t && go mod tidy

env GOOS=linux GOARCH=amd64 go build -o ../../misc/gonetstat_Linux_amd64 GoNetstat.go && \
env GOOS=darwin GOARCH=amd64 go build -o ../../misc/gonetstat_Darwin_amd64 GoNetstat.go && \
env GOOS=darwin GOARCH=arm64 go build -o ../../misc/gonetstat_Darwin_arm64 GoNetstat.go && date
*/

package main

import (
	"fmt"
	"github.com/hajimeo/samples/golang/helpers"
	"os"
	"os/user"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

// Proto    Recv-Q     Send-Q     Local Adress           Foregin Adress         State          Inode      Pid/Program          timeout
var DisplayFmt = "%-8v %-10v %-10v %-22v %-22v %-14v %-10v %-20v %v %v"

var STATE = map[string]string{
	"01": "ESTABLISHED",
	"02": "SYN_SENT",
	"03": "SYN_RECV",
	"04": "FIN_WAIT1",
	"05": "FIN_WAIT2",
	"06": "TIME_WAIT",
	"07": "CLOSE",
	"08": "CLOSE_WAIT",
	"09": "LAST_ACK",
	"0A": "LISTEN",
	"0B": "CLOSING",
}

type Socket struct {
	User        string
	Name        string
	Pid         string
	Exe         string
	State       string
	Ip          string
	Port        int64
	ForeignIp   string
	ForeignPort int64
	Inode       string
	RecvQ       int64
	SendQ       int64
	timeout     string
	misc        string
}

type FdLink struct {
	path string
	link string
}

func getLines(path string) []string {
	// just return lines (without header line) as list
	data, err := os.ReadFile(path)
	helpers.PanicIfErr(err)
	lines := strings.Split(string(data), "\n")
	// Return lines without Header line and blank line on the end
	return lines[1 : len(lines)-1]
}

func hexToDec(h string) int64 {
	// convert hexadecimal to decimal (int64).
	d, err := strconv.ParseInt(h, 16, 32)
	helpers.PanicIfErr(err)
	return d
}

func padStrToDec(s string) int64 {
	// convert 00000001 to decimal (int64).
	d, err := strconv.ParseInt(s, 10, 64)
	//helpers.PanicIfErr(err)
	if err != nil {
		d = -1
		helpers.Log("DEBUG", "Can't cast "+s)
	}
	return d
}

func convertIp(ip string) string {
	// Convert the ipv4 to decimal. Have to rearrange the ip because the
	// default value is in little Endian order.

	var out string

	// Check ip size if greater than 8 is ipv6 type
	if len(ip) > 8 {
		i := []string{ip[30:32],
			ip[28:30],
			ip[26:28],
			ip[24:26],
			ip[22:24],
			ip[20:22],
			ip[18:20],
			ip[16:18],
			ip[14:16],
			ip[12:14],
			ip[10:12],
			ip[8:10],
			ip[6:8],
			ip[4:6],
			ip[2:4],
			ip[0:2]}
		out = fmt.Sprintf("%v%v:%v%v:%v%v:%v%v:%v%v:%v%v:%v%v:%v%v",
			i[14], i[15], i[13], i[12],
			i[10], i[11], i[8], i[9],
			i[6], i[7], i[4], i[5],
			i[2], i[3], i[0], i[1])

	} else {
		i := []int64{hexToDec(ip[6:8]),
			hexToDec(ip[4:6]),
			hexToDec(ip[2:4]),
			hexToDec(ip[0:2])}

		out = fmt.Sprintf("%v.%v.%v.%v", i[0], i[1], i[2], i[3])
	}
	return out
}

func findPid(inode string, inodes *[]FdLink) string {
	// Loop through all fd dirs of process on /proc to compare the inode and
	// get the pid.

	pid := "-"

	re := regexp.MustCompile(inode)
	for _, item := range *inodes {
		out := re.FindString(item.link)
		if len(out) != 0 {
			pid = strings.Split(item.path, "/")[2]
		}
	}
	return pid
}

func getProcessExe(pid string) string {
	exe := fmt.Sprintf("/proc/%s/exe", pid)
	path, _ := os.Readlink(exe)
	return path
}

func getProcessName(exe string) string {
	n := strings.Split(exe, "/")
	name := n[len(n)-1]
	return strings.Title(name)
}

func getUser(uid string) string {
	u, err := user.LookupId(uid)
	if err != nil {
		return "Unknown"
	}
	return u.Username
}

func removeEmpty(array []string) []string {
	// remove empty data from line
	var newArray []string
	for _, i := range array {
		if i != "" {
			newArray = append(newArray, i)
		}
	}
	return newArray
}

func processNetstatLine(line string, fileDescriptors *[]FdLink) Socket {
	l := removeEmpty(strings.Split(strings.TrimSpace(line), " "))

	ipPort := strings.Split(l[1], ":")
	ip := convertIp(ipPort[0])
	port := hexToDec(ipPort[1])

	// foreign ip and port
	fipPort := strings.Split(l[2], ":")
	fIp := convertIp(fipPort[0])
	fPort := hexToDec(fipPort[1])

	state := STATE[l[3]]
	// TODO: add tx_queue and rx_queue bytes
	uid := getUser(l[7])
	pid := findPid(l[9], fileDescriptors)
	exe := getProcessExe(pid)
	name := getProcessName(exe)

	sendRecvQ := strings.Split(l[4], ":")
	sendQ := padStrToDec(sendRecvQ[0])
	recvQ := padStrToDec(sendRecvQ[1])
	return Socket{uid, name, pid, exe, state, ip, port, fIp, fPort, l[9], recvQ, sendQ, l[8], strings.Join(l[10:], " ")}
}

func getFileDescriptors() []string {
	// This works only for live system
	d, _ := filepath.Glob("/proc/[0-9]*/fd/[0-9]*")
	return d
}

func getLocalInodes() []FdLink {
	fileDescriptors := getFileDescriptors()
	inodes := make([]FdLink, len(fileDescriptors))
	res := make(chan FdLink, len(fileDescriptors))

	go func(fileDescriptors *[]string, output chan<- FdLink) {
		for _, fd := range *fileDescriptors {
			link, _ := os.Readlink(fd)
			output <- FdLink{fd, link}
		}
	}(&fileDescriptors, res)

	for _, _ = range fileDescriptors {
		inode := <-res
		inodes = append(inodes, inode)
	}
	return inodes
}

func netstat(path string) []Socket {
	lines := getLines(path)
	Sockets := make([]Socket, len(lines))

	localFdLinks := getLocalInodes()

	for i, line := range lines {
		Sockets[i] = processNetstatLine(line, &localFdLinks)
	}

	return Sockets
}

func genHeader() string {
	return fmt.Sprintf(DisplayFmt, "Proto", "Recv-Q", "Send-Q", "Local Adress", "Foregin Adress",
		"State", "Inode", "Pid/Program", "timeout", "misc.")
}

func genPrintLine(s Socket, netType string) string {
	ipPort := fmt.Sprintf("%v:%v", s.Ip, s.Port)
	fipPort := fmt.Sprintf("%v:%v", s.ForeignIp, s.ForeignPort)
	pidProgram := fmt.Sprintf("%v/%v", s.Pid, s.Name)

	return fmt.Sprintf(DisplayFmt,
		netType, s.RecvQ, s.SendQ, ipPort, fipPort, s.State, s.Inode, pidProgram, s.timeout, s.misc)
}

func main() {
	netType := "tcp"
	procNetFile := "/proc/net/" + netType
	// If a file (output of /proc/net/tcp) is given, parse it
	if len(os.Args) > 1 {
		switch os.Args[1] {
		case
			"tcp",
			"tcp6",
			"udp",
			"udp6":
			netType = os.Args[1]
			procNetFile = "/proc/net/" + netType
		default:
			procNetFile = os.Args[1]
		}
	}

	sockets := netstat(procNetFile)
	fmt.Println(genHeader())
	for _, s := range sockets {
		fmt.Println(genPrintLine(s, netType))
	}
}
