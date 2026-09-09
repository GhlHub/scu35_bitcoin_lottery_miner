connect -url tcp:10.0.1.109:3121
puts [targets]
puts [jtag targets]
puts [targets -target-properties -filter {name =~ "MicroBlaze*"}]
disconnect
exit
