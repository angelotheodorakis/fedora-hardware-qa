#!/bin/bash

# Make sure file is run as root
if [ "$EUID" -ne 0 ]; then
    printf "This script requires root access. You'll be prompted to enter your password, typing will be hidden. \n"
    exec sudo "$0" "$@"
fi

# Launch/relaunch inside tmux as root
if [ -z "$TMUX" ]; then
    exec tmux new-session -s hw_qual "$0" "$@"
fi

# Bash text color
Color_Off='\033[0m' # Text Reset
Yellow='\033[1;93m' # Yellow
Green='\033[1;32m'  # Green

####################################################################
# Welcome message
####################################################################

IFS='' read -r -d '' art <<"EOF"

                       .,,uod8B8bou,,.
              ..,uod8BBBBBBBBBBBBBBBBRPFT?l!i:.
         ,=m8BBBBBBBBBBBBBBBRPFT?!||||||||||||||
         !...:!TVBBBRPFT||||||||||!!^^""'   ||||
         !.......:!?|||||!!^^""'            ||||
         !.........||||                     ||||
         !.........||||  welcome to the     ||||
         !.........||||  Fedora Hardware    ||||
         !.........||||  Validation         ||||
         !.........||||  Testing script     ||||
         !.........||||                     ||||
         `.........||||                    ,||||
          .;.......||||               _.-!!|||||
   .,uodWBBBBb.....||||       _.-!!|||||||||!:'
!YBBBBBBBBBBBBBBb..!|||:..-!!|||||||!iof68BBBBBb....
!..YBBBBBBBBBBBBBBb!!||||||||!iof68BBBBBBRPFT?!::   `.
!....YBBBBBBBBBBBBBBbaaitf68BBBBBBRPFT?!:::::::::     `.
!......YBBBBBBBBBBBBBBBBBBBRPFT?!::::::;:!^"`;:::       `.
!........YBBBBBBBBBBRPFT?!::::::::::^''...::::::;         iBBbo.
`..........YBRPFT?!::::::::::::::::::::::::;iof68bo.      WBBBBbo.
  `..........:::::::::::::::::::::::;iof688888888888b.     `YBBBP^'
    `........::::::::::::::::;iof688888888888888888888b.     `
      `......:::::::::;iof688888888888888888888888888888b.
        `....:::;iof688888888888888888888888888888888899fT!
          `..::!8888888888888888888888888888888899fT|!^"'
            `' !!988888888888888888888888899fT|!^"'
                `!!888888888888888899fT|!^"'
                  `!988888888899fT|!^"'
                    `!9899fT|!^"'
                      `!^"'

EOF

echo "$art"
echo

echo -e "${Green}This script will automatically run a long suite of tests. ${Color_Off}"
echo -e "You will find more info in the PDF document in the user Documents folder."
echo -e "Once the script completes it will generate a report in html format."
echo -e "${Yellow}This script will take many hours to complete! ${Color_Off}. Please allow it time."

# Create log file
FULL_LOG="/root/hardware_validation.log"
touch "$FULL_LOG"

# Function which removes special characters before writing to the log file
log_clean() {
    # Usage: log_clean "command" log_file
    local cmd="$1"
    local logfile="$2"
    eval "$cmd" |& tee >(perl -pe 's/\e([^\[\]]|\[.*?[a-zA-Z]|\].*?\a)//g' | col -b >> "$logfile")
}

# Helper function to run commands in a split tmux window synchronously
run_in_split() {
    local cmd="$1"
    local signal_id="wait_sig_$$_${RANDOM}"

    # Inject log_clean into memory so it's passed down to the subshell, then execute command
    local payload
    payload="$(declare -f log_clean); $cmd"

    tmux split-window -h "bash -c $(printf %q "$payload"); tmux wait -S $signal_id" && tmux wait "$signal_id"
}

# Setup user home directory path for output files
USER_HOME="/home/${SUDO_USER:-root}"
[ "$USER_HOME" = "/home/root" ] && USER_HOME="/root"

# Get script start time and date for report
MYTIMEVAR=$(date +'%a %d %b %Y %k:%M:%S')

# Create report file
REPORTFILE="${USER_HOME}/Documents/$(date +'%Y%m%d-%H%M%S_%N')_Hardware_validation_report.html"
mkdir -p "$(dirname "$REPORTFILE")"
touch "$REPORTFILE"

echo -e "Installing dependencies..."

# Ensure dependencies are installed
run_in_split "log_clean 'dnf -y install git glmark2 sysbench memtester iozone hdparm stress inxi wget unzip bc php-cli php-common php-gd php-pdo php-process php-xml' '$FULL_LOG'"

PTS_CMD="log_clean 'git clone https://github.com/phoronix-test-suite/phoronix-test-suite /tmp/phoronix-test-suite' '$FULL_LOG'; pushd /tmp/phoronix-test-suite && log_clean './install-sh' '$FULL_LOG' && popd"
run_in_split "$PTS_CMD"

####################################################################
# Configure phoronix-test-suite
####################################################################

# Environment flags for downloads
PTS_ENV="export NO_FILE_HASH_CHECKS=1;"

# Environment flags for test runs
TEST_RUN_ENV="export FORCE_TIMES_TO_RUN=1; export PTS_CONCURRENT_TEST_RUNS=1; export TEST_TIMEOUT_AFTER=30;"

run_in_split "$PTS_ENV log_clean \"printf 'y\\nn\\nn\\nn\\nn\\nn\\nn\\n' | phoronix-test-suite batch-setup\" '$FULL_LOG'"
run_in_split "$PTS_ENV log_clean 'phoronix-test-suite install cachebench coremark deepspeech epoch system/graphics-magick' '$FULL_LOG'"
run_in_split "$PTS_ENV log_clean 'phoronix-test-suite install furmark unigine-super blender' '$FULL_LOG'"
run_in_split "$PTS_ENV log_clean 'phoronix-test-suite install tinymembench ramspeed' '$FULL_LOG'"
run_in_split "$PTS_ENV log_clean 'phoronix-test-suite install fio dbench' '$FULL_LOG'"
run_in_split "$PTS_ENV log_clean 'phoronix-test-suite install glibc-bench osbench' '$FULL_LOG'"

FURMARK_DIR="/var/lib/phoronix-test-suite/installed-tests/pts/furmark-1.0.0"
FURMARK_SETUP_CMD="
    log_clean 'wget -q https://gpumagick.com/downloads/files/2024/furmark2/FurMark_2.1.0.2_linux64.zip -O /tmp/FurMark_2.1.0.2_linux64.zip' '$FULL_LOG'
    mkdir -p '$FURMARK_DIR'
    log_clean 'cp /tmp/FurMark_2.1.0.2_linux64.zip $FURMARK_DIR/' '$FULL_LOG'
    log_clean 'unzip -o -d $FURMARK_DIR/ $FURMARK_DIR/FurMark_2.1.0.2_linux64.zip' '$FULL_LOG'
"
run_in_split "$FURMARK_SETUP_CMD"

####################################################################
# CPU Stress Test
####################################################################

echo -e "Running CPU tests...."

NPROC=$(nproc | tr -d '\n')
run_in_split "log_clean 'stress --cpu $NPROC --io 4 --vm 2 --vm-bytes 128M --timeout 300s' '$FULL_LOG'"
CPU_STRESS=$(grep "successful run completed" "$FULL_LOG" | tail -1)

run_in_split "$TEST_RUN_ENV log_clean \"echo 4 | phoronix-test-suite batch-run cachebench\" '$FULL_LOG'"
CPU_CACHEBENCH=$(awk '/Average: [0-9.]+ MB\/s/ {print $0}' "$FULL_LOG" | tail -1)

run_in_split "$TEST_RUN_ENV log_clean 'phoronix-test-suite batch-run coremark' '$FULL_LOG'"
CPU_COREMARK=$(awk '/Average: [0-9.]+ Iterations\/Sec/ {print $0}' "$FULL_LOG" | tail -1)

run_in_split "$TEST_RUN_ENV log_clean \"echo 8 | phoronix-test-suite batch-run system/graphics-magick\" '$FULL_LOG'"
CPU_GRAPHICS_MAGICK=$(awk '/Average: [0-9.]+ Iterations Per Minute/ {print $0}' "$FULL_LOG" | tail -1)

run_in_split "$TEST_RUN_ENV log_clean 'phoronix-test-suite batch-run epoch' '$FULL_LOG'"
CPU_EPOCH=$(awk '
/Epoch3D Deck: Cone:/ {
    print $0
    getline; print $0
    while (getline) {
        if ($0 ~ /Average: [0-9.]+ Seconds/) {
            print $0
            break
        }
    }
}
' "$FULL_LOG")

run_in_split "$TEST_RUN_ENV log_clean 'phoronix-test-suite batch-run deepspeech' '$FULL_LOG'"
CPU_DEEPSPEECH=$(awk '
/Acceleration: CPU:/ {
    print $0
    getline; print $0
    while (getline) {
        if ($0 ~ /Average: [0-9.]+ Seconds/) {
            print $0
            break
        }
    }
}
' "$FULL_LOG")

####################################################################
# GPU Stress Test
####################################################################

echo -e "Running GPU tests...."

has_nvidia=false
if /usr/sbin/lspci -mnn | grep -E 'VGA|3D controller' | grep NVIDIA | grep -q 10de; then
  has_nvidia=true
fi

has_dual_gpus=false
gpu_count=$(lspci | grep -i "VGA compatible controller" -c)
if [ "$gpu_count" -gt 1 ]; then
  has_dual_gpus=true
fi

# Environment flags for GPU selection
GPU_ENV=""
if $has_nvidia && $has_dual_gpus; then
  GPU_ENV="export __NV_PRIME_RENDER_OFFLOAD=1; export __GLX_VENDOR_LIBRARY_NAME=nvidia; export __VK_LAYER_NV_optimus=NVIDIA_only; export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G1;"
fi

run_in_split "$TEST_RUN_ENV $GPU_ENV log_clean \"printf '5\\n5\\n1\\n' | phoronix-test-suite batch-run furmark\" '$FULL_LOG'"
GPU_FURMARK=$(awk '/Average: [0-9.]+ FPS/ {print $0}' "$FULL_LOG" | tail -1)

run_in_split "$GPU_ENV log_clean \"machinectl shell \\\"$SUDO_USER\\\"@.host /usr/bin/glmark2-wayland --fullscreen\" '$FULL_LOG'"
GPU_GLMARK2=$(grep "glmark2 Score:" "$FULL_LOG" | tail -1)

run_in_split "$TEST_RUN_ENV $GPU_ENV log_clean \"printf '5\\n1\\n4\\n' | phoronix-test-suite batch-run unigine-super\" '$FULL_LOG'"
GPU_UNIGINE=$(awk '/Average: [0-9.]+ Frames Per Second/ {print $0}' "$FULL_LOG" | tail -1)

run_in_split "$TEST_RUN_ENV $GPU_ENV log_clean \"printf '7\\n3\\n' | phoronix-test-suite batch-run blender\" '$FULL_LOG'"
GPU_BLENDER=$(awk '/Blend File: .* - Compute: .*:/ {print $0; getline; print $0}' "$FULL_LOG")

####################################################################
# Memory Stress Test
####################################################################

echo -e "Running RAM tests...."

RAM_FREE="$(free -g | grep -w 'Mem' | awk '{print $4}')"
RAM_FREE_80=$(bc <<< "$RAM_FREE * 0.8")
RAM_FREE_80=$(printf "%.0f" "$RAM_FREE_80")

run_in_split "log_clean 'memtester \"$RAM_FREE_80\"G 1' '$FULL_LOG'"
RAM_MEMTESTER=$(grep "Done." "$FULL_LOG" | tail -1)

run_in_split "log_clean 'sysbench memory run' '$FULL_LOG'"
RAM_SYSBENCH_OPS=$(awk '/Total operations:/ {print $0}' "$FULL_LOG" | tail -1)
RAM_SYSBENCH_MB=$(awk '/MiB transferred/ {print $0}' "$FULL_LOG" | tail -1)

run_in_split "$TEST_RUN_ENV log_clean 'phoronix-test-suite batch-run tinymembench' '$FULL_LOG'"
RAM_TINYMEMBENCH_MEMCPY_AVG=$(awk '/Average: [0-9.]+ MB\/s/ {print $0}' "$FULL_LOG" | tail -1)
RAM_TINYMEMBENCH_MEMSET_AVG=$(awk '/Average: [0-9.]+ MB\/s/ {print $0}' "$FULL_LOG" | tail -1)

run_in_split "$TEST_RUN_ENV log_clean \"printf '6\\n3\\n' | phoronix-test-suite batch-run ramspeed\" '$FULL_LOG'"
RAM_RAMSPEED=$(awk '/Average: [0-9.]+ MB\/s/ {print $0}' "$FULL_LOG" | tail -1)

####################################################################
# Drive Stress Test
####################################################################

echo -e "Running Drive tests...."

run_in_split "log_clean 'sysbench fileio --file-total-size=15G --file-test-mode=rndrw --time=300 --max-requests=0 prepare' '$FULL_LOG'"
run_in_split "log_clean 'sysbench fileio --file-total-size=15G --file-test-mode=rndrw --time=300 --max-requests=0 run' '$FULL_LOG'"
run_in_split "log_clean 'sysbench fileio --file-total-size=15G --file-test-mode=rndrw --time=300 --max-requests=0 cleanup' '$FULL_LOG'"
DRIVE_SYSBENCH_READS=$(awk '/reads\/s:/ {print $0}' "$FULL_LOG" | tail -1)
DRIVE_SYSBENCH_WRITES=$(awk '/writes\/s:/ {print $0}' "$FULL_LOG" | tail -1)
DRIVE_SYSBENCH_FSYNCS=$(awk '/fsyncs\/s:/ {print $0}' "$FULL_LOG" | tail -1)
DRIVE_SYSBENCH_THROUGHPUT_READ=$(awk '/read, MiB\/s:/ {print $0}' "$FULL_LOG" | tail -1)
DRIVE_SYSBENCH_THROUGHPUT_WRITTEN=$(awk '/written, MiB\/s:/ {print $0}' "$FULL_LOG" | tail -1)
DRIVE_SYSBENCH_TOTAL_TIME=$(awk '/total time:/ {print $0}' "$FULL_LOG" | tail -1)

run_in_split "log_clean 'iozone -t1 -i0 -i2 -r1k -s1g -F /tmp/testfile' '$FULL_LOG'"
DRIVE_IOZONE=$(grep "Avg throughput per process" "$FULL_LOG" | tail -1)

run_in_split "log_clean 'hdparm -tT /dev/nvme0n1' '$FULL_LOG'"
DRIVE_HDPARM_CACHED=$(grep "Timing cached reads:" "$FULL_LOG" | tail -1)
DRIVE_HDPARM_BUFFERED=$(grep "Timing buffered disk reads:" "$FULL_LOG" | tail -1)

run_in_split "$TEST_RUN_ENV log_clean \"printf '5\\n4\\n3\\n1,5,11\\n1\\n1\\n' | phoronix-test-suite batch-run fio\" '$FULL_LOG'"
DRIVE_FIO=$(awk '/Type: Random Read .* Block Size: 4KB .* Disk Target: Default Test Directory:/ {getline; print $0}' "$FULL_LOG")
DRIVE_FIO_AVG=$(awk '/Average: [0-9.]+ MB\/s/ {print $0}' "$FULL_LOG" | tail -1)

run_in_split "$TEST_RUN_ENV log_clean \"echo 7 | phoronix-test-suite batch-run dbench\" '$FULL_LOG'"
DRIVE_DBENCH=$(awk '/Average: [0-9.]+ MB\/s/ {print $0}' "$FULL_LOG" | tail -1)

####################################################################
# Full System Benchmark
####################################################################

echo -e "Running Full system tests...."

run_in_split "$TEST_RUN_ENV log_clean \"echo 6 | phoronix-test-suite batch-run osbench\" '$FULL_LOG'"
SYSTEM_OSBENCH=$(awk '
/Test: [A-Za-z ]+:/ {
    test_line = $0
    while (getline) {
        if ($0 ~ /Average:/) {
            avg_line = $0
            print test_line
            print avg_line
            break
        }
    }
}
' "$FULL_LOG")

####################################################################
# generate report
####################################################################

echo -e "Generating report...."

cat >>"$REPORTFILE" <<END_OF_LOGFILENAMEA1
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">
<html>
<head>
<meta http-equiv="content-type" content="text/html; charset=ISO-8859-1">
<title>Hardware Stress Testing and Benchmarks Report</title>
<style type="text/css">
body {
    font-family: Arial, Helvetica, sans-serif;
    background-color: #fff;
}
p.p1 {
    font-size: 200%;
    font-style: normal;
    font-family: arial, helvetica, sans-serif;
    font-weight: bolder;
    color: green;
}
p.p3 {
    font-size: 100%;
    font-style: normal;
    font-family: arial, helvetica, sans-serif;
    font-weight: bold;
    color: black;
}
th {
    text-align: left;
    font-size: 95%;
    font-style: normal;
    font-family: arial, helvetica, sans-serif;
    font-weight: bold;
    color: green;
    padding: 4px;
    background-color: #fff;
    border: 1px solid #000;
}
td {
    font-size: 95%;
    font-style: normal;
    font-family: arial, helvetica, sans-serif;
    font-weight: normal;
    color: black;
    padding: 4px;
    border: 1px solid #000;
}
table {
    border-collapse: collapse;
}
</style>
</head>
<body>

<p class="p1">Hardware Stress Testing and Benchmarks Report</p>
<p class="p3">Start Time: $MYTIMEVAR</p>

END_OF_LOGFILENAMEA1

SYSTEM=$(inxi -S)
MACHINE=$(inxi -M)
CPU=$(inxi -C)
GRAPHICS=$(inxi -G)
MEMORY=$(inxi -m)
AUDIO=$(inxi -A)
NETWORK=$(inxi -N)
BLUETOOTH=$(inxi -E)
DRIVES=$(inxi -D)
PARTITIONS=$(inxi -P)
BATTERY=$(inxi -B)

# HTML template left table section, device spec gathered from inxi
cat >>"$REPORTFILE" <<END_OF_LOGFILENAMEA2
<table border="1" width="100%">
    <tr>
        <th width="50%">System Info</th>
        <th width="50%">Test Results</th>
    </tr>
    <tr>
        <td valign="top">
            <table width="100%">
                <tr>
                    <th>Category</th>
                    <th>Value</th>
                </tr>
                <!-- System -->
                <tr><td><strong>System</strong></td><td><pre>$SYSTEM</pre></td></tr>
                <!-- Machine -->
                <tr><td><strong>Machine</strong></td><td><pre>$MACHINE</pre></td></tr>
                <!-- CPU -->
                <tr><td><strong>CPU</strong></td><td><pre>$CPU</pre></td>
                <!-- Graphics -->
                <tr><td><strong>Graphics</strong></td><td><pre>$GRAPHICS</pre></td>
                <!-- Memory -->
                <tr><td><strong>Memory</strong></td><td><pre>$MEMORY</pre></td></tr>
                <!-- Audio -->
                <tr><td><strong>Audio</strong></td><td><pre>$AUDIO</pre></td></tr>
                <!-- Network -->
                <tr><td><strong>Network</strong></td><td><pre>$NETWORK</pre></td></tr>
                <!-- Bluetooth -->
                <tr><td><strong>Bluetooth</strong></td><td><pre>$BLUETOOTH</pre></td></tr>
                <!-- Drives -->
                <tr><td><strong>Drives</strong></td><td><pre>$DRIVES</pre></td></tr>
                <!-- Partitions -->
                <tr><td><strong>Partitions</strong></td><td><pre>$PARTITIONS</pre></td></tr>
                <!-- Battery -->
                <tr><td><strong>Battery</strong></td><td><pre>$BATTERY</pre></td></tr>
            </table>
        </td>
END_OF_LOGFILENAMEA2

# HTML template right table section, hardware tests
cat >>"$REPORTFILE" <<END_OF_LOGFILENAMEA3
        <td valign="top">
            <table width="100%">
                <tr>
                    <th>Category</th>
                    <th>Test</th>
                    <th>Sample Result</th>
                </tr>
                <!-- CPU Stress Test -->
                <tr><td><strong>CPU Stress Test</strong></td><td>stress</td><td><pre>$CPU_STRESS</pre></td></tr>
                <!-- CPU Benchmark -->
                <tr><td rowspan="5"><strong>CPU Benchmark</strong></td><td>cachebench</td><td><pre>$CPU_CACHEBENCH</pre></td></tr>
                <tr><td>coremark</td><td><pre>$CPU_COREMARK</pre></td></tr>
                <tr><td>graphics-magick</td><td><pre>$CPU_GRAPHICS_MAGICK</pre></td></tr>
                <tr><td>epoch</td><td><pre>$CPU_EPOCH</pre></td></tr>
                <tr><td>deepspeech</td><td><pre>$CPU_DEEPSPEECH</pre></td></tr>
                <!-- GPU Stress Test -->
                <tr><td><strong>GPU Stress Test</strong></td><td>furmark</td><td><pre>$GPU_FURMARK</pre></td></tr>
                <!-- GPU Benchmark -->
                <tr><td rowspan="3"><strong>GPU Benchmark</strong></td><td>glmark2-wayland</td><td><pre>$GPU_GLMARK2</pre></td></tr>
                <tr><td>unigine-super</td><td><pre>$GPU_UNIGINE</pre></td></tr>
                <tr><td>blender</td><td><pre>$GPU_BLENDER</pre></td></tr>
                <!-- RAM Stress Test -->
                <tr><td rowspan="2"><strong>RAM Stress Test</strong></td><td>memtester</td><td><pre>$RAM_MEMTESTER</pre></td></tr>
                <tr><td>sysbench memory</td><td><pre>$RAM_SYSBENCH_OPS
                $RAM_SYSBENCH_MB</pre></td></tr>
                <!-- RAM Benchmark -->
                <tr><td rowspan="2"><strong>RAM Benchmark</strong></td><td>tinymembench</td><td><pre>$RAM_TINYMEMBENCH_MEMCPY_AVG
                $RAM_TINYMEMBENCH_MEMSET_AVG</pre></td></tr>
                <tr><td>ramspeed</td><td><pre>$RAM_RAMSPEED</pre></td></tr>
                <!-- Drive Stress Test -->
                <tr><td rowspan="3"><strong>Drive Stress Test</strong></td><td>sysbench fileio</td><td><pre>$DRIVE_SYSBENCH_READS
                $DRIVE_SYSBENCH_WRITES
                $DRIVE_SYSBENCH_FSYNCS
                $DRIVE_SYSBENCH_THROUGHPUT_READ
                $DRIVE_SYSBENCH_THROUGHPUT_WRITTEN
                $DRIVE_SYSBENCH_TOTAL_TIME</pre></td></tr>
                <tr><td>iozone</td><td><pre>$DRIVE_IOZONE</pre></td></tr>
                <tr><td>hdparm</td><td><pre>$DRIVE_HDPARM_CACHED
                $DRIVE_HDPARM_BUFFERED</pre></td></tr>
                <!-- Drive Benchmark -->
                <tr><td rowspan="2"><strong>Drive Benchmark</strong></td><td>fio</td><td><pre>$DRIVE_FIO
                $DRIVE_FIO_AVG</pre></td></tr>
                <tr><td>dbench</td><td><pre>$DRIVE_DBENCH</pre></td></tr>
                <!-- System Benchmark -->
                <tr><td><strong>System Benchmark</strong></td><td>osbench</td><td><pre>$SYSTEM_OSBENCH</pre></td></tr>
            </table>
        </td>
    </tr>
</table>
END_OF_LOGFILENAMEA3


# HTML template bottom section, completion date and full log
MYTIMEVAR=$(date +'%a %d %b %Y %k:%M:%S')
cat >>"$REPORTFILE" <<END_OF_LOGFILENAMEA4
<p class="p3">Completion time: $MYTIMEVAR</p>

<table border="1" width="100%" style="margin-top:2em;">
    <tr>
        <th width="10%">Full Log</th>
        <td width="90%">
          <pre style="
              width: 100%;
              height: 300px;
              overflow-y: auto;
              overflow-x: hidden;
              border: 1px solid #000;
              background: #f9f9f9;
              font-size: 95%;
              padding: 8px;
              margin: 0;
              box-sizing: border-box;
              white-space: pre-wrap;
              word-break: break-all;
          ">
          $(cat $FULL_LOG)
          </pre>
        </td>
    </tr>
</table>

</body>
</html>
END_OF_LOGFILENAMEA4

# Clean up temp files
rm -rf /tmp/phoronix-test-suite /tmp/FurMark_2.1.0.2_linux64.zip /tmp/testfile

echo -e "\n ${Green}Testing complete!${Color_Off}\n"
echo -e "You will find the generated report in the user's Documents folder in html format."
read -n 1 -s -r -p "Press any key to exit..."
sleep 5