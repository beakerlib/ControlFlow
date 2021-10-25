#!/usr/bin/expect

if { $argc != 3 } {
  exit 1
}

set session_prog [lindex $argv 0]
set input_socket [lindex $argv 1]
set output_socket [lindex $argv 2]

spawn -noecho $session_prog

set fd_input [open "$::input_socket" "RDONLY NONBLOCK"]

while {1} {
  puts stderr "waiting"
  set input ""
  while {1} {
    append input [read $fd_input]
    if { [eof $fd_input] && "$input" != "" } break
    after 250
  }
  puts stderr "input=$input"
  eval "$input"
}

close $fd_input
