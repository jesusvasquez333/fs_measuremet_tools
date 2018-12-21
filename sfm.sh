#!/usr/bin/env bash

######################################
### Capture invocation information ###
######################################

# Get the scrip name
THIS_SCRIPT_NAME=$0

# Get the script location
TOP="$(dirname -- "$(readlink -f $0)")/"

###################
### Definitions ###
###################

# Test file name
TEST_FILE_NAME="tempfile"

# Default output result directory
RESULT_DIR="."

# Read operation result output file
R_RESULT_FILE_NAME="r_results.data"
R_PLOT_FILE_NAME=${R_RESULT_FILE_NAME%.*}.png

# Write operation result output file
W_RESULT_FILE_NAME="w_results.data"
W_PLOT_FILE_NAME=${W_RESULT_FILE_NAME%.*}.png

# Log file name
LOG_FILE_NAME="run.log"

# gnuplot script file
GP_SCRIPT_FILE_NAME="extra/plot.gp"

#################
### Functions ###
#################

# Exit trap function, used to clean up before exit
clean_up() {
    # Remove the test output file, created during the test
    rm -f $TEST_FILE
}
trap clean_up EXIT

# Usage message
usage() {
    echo "Utility to measure disk's R/W rates. The utility uses 'dd' to write a file into disk and then read it back extracting the R/W rates."
    echo
    echo "The user specifies the path where the file will be written, the size of the file, and how many times the file will be written and read back."
    echo
    echo "The final results are printed on screen at the end of the test, written to two output files, and plotted to two png files."
    echo " - Read operation results are written to '$R_RESULT_FILE_NAME', and plotted to '$R_PLOT_FILE_NAME'"
    echo " - Write operation results are written to '$W_RESULT_FILE_NAME', and plotted to '$W_PLOT_FILE_NAME'"
    echo " - A log file is written to '$LOG_FILE_NAME'"
    echo "The location of of the output files can be specified by the user."
    echo
    echo "usage: $THIS_SCRIPT_NAME -i|--iterations iterations -s|--size[k,M,G] file_size -d|--dir directory [-n|--no-cache] [-f|--flush-cache] [-c|--clean] [-r|--ro][-h|--help]"
    echo "    -i|--iterations iterations : Number of times the file will be written and read back."
    echo "    -s|--size file_size[k,G,B] : Size of the file. Units identifiers ('k'=kilo, 'M'=Mega, 'G'=Giga) can be used; if omitted, 'k' is assumed."
    echo "                                 There must not be white spaces between the size and the units. A valid example will be: 2G."
    echo "    -d|--dir directory         : Directory where the file will be written. The filename '$TEST_FILE_NAME' will be added to this path."
    echo "    -n|--no-cache              : Disable cache in R/W operations by using dd's iflag/oflag=direct."
    echo "    -f|--flush                 : Flush the local cache before each R/W operation by performing 'echo 3 > /proc/sys/vm/drop_caches'"
    echo "                                 The test needs to be runt as root with this option."
    echo "    -c|--clean                 : Delete the test file before each iteration. If not specified the test file will not be deleted before a new iteration."
    echo "    -r|--ro                    : Only perform read operations: in this mode the test file will be written once and the local cache will be flushed (like using the -f option)."
    echo "                                 Them each iteration will only perform read operations. The test needs to be runt as root with this option."
    echo "    -o|--out-dir               : Directory to save the results. If not specified the current directory will be used."
    echo "    -h|--help                  : show this message."
    echo
}

# Send error message and exit
error_message() {
    echo "$1" >&2
    exit
}

# Flush local cache, if enables
flush_cache() {
    if [ ! -z ${FLUSH_CACHE+x} ]; then
        $(echo 3 > /proc/sys/vm/drop_caches)
    fi
}

# Return the value expressed in B, kB, MB or GB units
eng_value() {
    # Supported units
    local UNITS=("B" "kB" "MB" "GB")
    # Maximum index
    local MAX_I=3

    # Get the index for the input value.
    # It is calculated from how many blocks of 3 digits the value's (number of digits - 1) has.
    local I=$(( ( ${#1} - 1 ) / 3 ))

    # Limit the index to the maximum allowed value
    if [ $I -gt $MAX_I ]; then
        I=$MAX_I
    fi

    # Calculate the division factor (block of 1024 bytes for each unit)
    local FACTOR=1
    for i in `seq $I`; do
        FACTOR=$((FACTOR*1024))
    done

    # Calculate the scaled value
    local VAL=$(echo $((  100 * $1 / FACTOR )) | sed 's/..$/.&/')
    # Alternative method using 'bc'
    #VAL=$(echo "scale=2; $VAL/$FACTOR" | bc -l)

    # Return the scaled value and its units
    echo "${VAL} ${UNITS[I]}"
}

get_free_mem() {
    local MEM=$(free -b | grep '^Mem:*' | awk '{print $4}')
    echo $(eng_value $(free -b | grep '^Mem:*' | awk '{print $4}'))
}

# Verify that the output path exist
verify_dir() {
    # Read the passed directory name
    local DIR=$1

    # Check if the directory exist
    if [ ! -d $DIR ]; then
        error_message "ERROR: Directory $DIR does not exist!"
    fi
}

# Check and fix the format of a directory name
format_dir_name() {
    # Read passed directory name
    local DIR=$1

    # Add '/' to dir name if it is missing
    if ! [[ $DIR == */ ]]; then
        DIR="$DIR/"
    fi

    # Return process directory name
    echo $DIR
}
###############################
### Process input arguments ###
###############################

# Verify inputs arguments
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -i|--iteration)
    N="$2"
    shift
    shift
    ;;

    -s|--size)
    SIZE="$2"
    shift
    shift
    ;;

    -d|--dir)
    TEST_DIR="$2"
    shift
    shift
    ;;

    -n|--no-cahe)
    NO_CACHE="YES"
    shift
    ;;

    -f|--flush)
    FLUSH_CACHE="YES"
    shift
    ;;

    -c|--clean)
    DELETE_TEST_FILE="YES"
    shift
    ;;

    -r|--ro)
    READ_ONLY="YES"
    shift
    ;;

    -o|--out-dir)
    RESULT_DIR="$2"
    shift
    shift
    ;;

    -h|--help)
    usage
    exit
    ;;

    *)
    echo
    error_message "Unknown option"
    ;;
esac
done

# Verify mandatory arguments
if [ -z "$N" ]; then
    error_message "ERROR: Number of iterations not defined!"
fi

if [ -z "$SIZE" ]; then
    error_message "ERROR: File size not defined!"
fi

if [ -z ${TEST_DIR+x} ]; then
    error_message "ERROR: Output directory not defined!"
fi

#############################################################
### Check is we are running the test are root when needed ###
#############################################################

# -r|ro and -f|--flush need root access
if ( [ ! -z ${FLUSH_CACHE+x} ] || [ ! -z ${READ_ONLY+x} ] ) && [ $(whoami) != "root" ]; then
    error_message "ERROR: Root access is need"
fi

##########################################################
### Check results path and generate results file names ###
##########################################################

# Verify that the result directory exist.
verify_dir $RESULT_DIR

# Add '/' at the end of the path if it is missing
RESULT_DIR=$(format_dir_name $RESULT_DIR)

# Generate result file paths
R_RESULT_FILE=${RESULT_DIR}${R_RESULT_FILE_NAME}
W_RESULT_FILE=${RESULT_DIR}${W_RESULT_FILE_NAME}
R_PLOT_FILE=${RESULT_DIR}${R_PLOT_FILE_NAME}
W_PLOT_FILE=${RESULT_DIR}${W_PLOT_FILE_NAME}
LOG_FILE=${RESULT_DIR}${LOG_FILE_NAME}

##########################################################
### Check test path and generate output test file name ###
##########################################################

# Verify that the output path exist
verify_dir $TEST_DIR

# Add '/' at the end of the path if it is missing
TEST_DIR=$(format_dir_name $TEST_DIR)

# Generate test file path
TEST_FILE="${TEST_DIR}${TEST_FILE_NAME}"

#############################
### Generate script paths ###
#############################

# gnuplot script path
GP_SCRIPT_FILE=${TOP}${GP_SCRIPT_FILE_NAME}

##########################################
### Check and adjust the file size and ###
### Calculate the number of R/W blocks ###
##########################################

# Extract size units, if any, and adjust the file size accordingly
UNIT=$(echo $SIZE | sed -E 's/^[0-9]+([^0-9]*)$/\1/g')

# Choose the correct multiplier based on the units
# Only k (kilo), M (Mega), and G (Giga) are supported.
case $UNIT in
    "k"|"")
    # This is the default.
    MULT=1024
    ;;

    "M")
    MULT=1024*1024
    ;;

    "G")
    MULT=1024*1024*1024
    ;;

    *)
    # Not supported unit identifier found. Exit here.
    error_message "ERROR: Invalid unit identified ($UNIT)!"
esac

# Adjust the size based on the identifier
SIZE=$(echo $SIZE | sed -E 's/^([0-9]+)[^0-9]*$/\1/g')
SIZE=$((SIZE*MULT))

# Number of bytes to R/W (passed to 'dd')
BYTES=$((16*1024))

# Verify that the file size if valid
if [ $SIZE -lt $BYTES ]; then
    error_message "ERROR: File size must be greater that 16kB"
fi

# Round the size to fit in blocks of 16k
SIZE_MOD=$((SIZE % BYTES))
if [ $SIZE_MOD != 0 ]; then
    echo "Adjusting size...."
    SIZE=$(( ( SIZE/BYTES + 1 ) * BYTES ))
fi

# Number of $BYTES blocks to R/W (passed to 'dd')
COUNT=$((SIZE/(BYTES)))

####################################################
### Process extra arguments to be passed to 'dd' ###
####################################################

DD_R_ARGS=""
DD_R_ARGS=""
if [ ! -z ${NO_CACHE+x} ]; then
    DD_R_ARGS+="iflag=direct"
    DD_W_ARGS+="oflag=direct"
fi

######################################
### Report parameters before start ###
######################################

# Remove previous log file
rm -f LOG_FILE

# Add  the current date to the log file
date > $LOG_FILE

echo "============================================" | tee -a $LOG_FILE
echo "Starting test with the following parameters:" | tee -a $LOG_FILE
echo "============================================" | tee -a $LOG_FILE
echo "Number of iterations : $N" | tee -a $LOG_FILE
echo "Test file            : $TEST_FILE" | tee -a $LOG_FILE
echo "Actual file Size     : $(eng_value $((BYTES*COUNT)))" | tee -a $LOG_FILE
echo "dd's 'bs' argument   : $BYTES" | tee -a $LOG_FILE
echo "dd' 'count' argument : $COUNT" | tee -a $LOG_FILE
printf "dd's extra arguments : " | tee -a $LOG_FILE
if [ ! -z ${NO_CACHE+x} ]; then
    echo "for read = '$DD_R_ARGS'" | tee -a $LOG_FILE
    printf "%23s%s\n" " " "for write = '$DD_W_ARGS'" | tee -a $LOG_FILE
else
    echo "None" | tee -a $LOG_FILE
fi
printf "Flush local cache    : " | tee -a $LOG_FILE
if [ ! -z ${FLUSH_CACHE+x} ]; then
    echo "Yes" | tee -a $LOG_FILE
else
    echo "No" | tee -a $LOG_FILE
fi
echo "Result directory     : $RESULT_DIR" | tee -a $LOG_FILE
echo "============================================" | tee -a $LOG_FILE

####################
### Perform test ###
####################

# Set array headers
W_RAW_OUTPUT[0]=$(printf "%12s %12s %12s" "RAM before" "Ram after" "Rate")
R_RAW_OUTPUT[0]=${W_RAW_OUTPUT[0]}

# Run the test the numbers time specified by the user
for i in `seq $N`; do

    # Clean up before start
    if [ ! -z ${DELETE_TEST_FILE+x} ]; then
        clean_up
    fi

    ######################################
    ### Measure write operation rates ###
    ######################################

    # Check if the write operation is enabled.
    # It will be disable after the first write is read-only mode is enabled.
    if [ -z ${DO_NOT_WRITE+x} ]; then

        # Flush cache, if needed
        flush_cache

        # Get the free RAM before 'dd'
        W_RAM_BEFORE=$(get_free_mem)

        # Execute the 'dd' command
        W=$(dd if=/dev/zero of=$TEST_FILE bs=$BYTES count=$COUNT $DD_W_ARGS 2>&1)

        # Get the free RAM after 'dd'
        W_RAM_AFTER=$(get_free_mem)

        # Extarct rate value and units from the output of 'dd'
        W_RATE=$(echo "$W" | tail -n1 | awk '{print $(NF-1)}')
        W_RATE_UNITS=$(echo "$W" | tail -n1 | awk '{print $(NF)}')

        # Save the raw information
        #W_RAW_OUTPUT[i]="$RAM_BEFORE $RAM_AFTER $RATE $RATE_UNITS"
        W_RAW_OUTPUT[i]=$(printf "%9s %2s%9s%3s%9s %3s" $W_RAM_BEFORE $W_RAM_AFTER $W_RATE $W_RATE_UNITS)

        # Adjust the rate to be expressed in MB/s
        case $RATE_UNITS in
            "kB/s"|"")
            RATE=$(echo "$RATE" | sed -E 's/([0-9]+)\.([0-9])/0.0\1\2/g')
            ;;

            "MB/s")
            # This is the default, do not modified the value
            ;;

            "GB/s")
            RATE=$(echo "$RATE" | sed -E 's/([0-9]+)\.([0-9])/\1\200/g')
            ;;

            *)
            # Not supported unit identifier found.
            #Use '-1' as process rate value and continue
            RATE="-1"
        esac

        # Save the processed data
        W_RESULTS[i-1]="$W_RATE"

        # If we are running in read-only mode, flush the cache and set the flag here to stop further write operations
        if [ ! -z ${READ_ONLY+x} ]; then
            flush_cache
            DO_NOT_WRITE="YES"
        fi
    fi

    ####################################
    ### Measure read operation rates ###
    ####################################

    # Flush cache, if needed
    flush_cache

    # Get the free RAM before 'dd'
    R_RAM_BEFORE=$(get_free_mem)

    # Execute the 'dd' command
    R=$(dd if=$TEST_FILE of=/dev/null bs=$BYTES $DD_R_ARGS 2>&1)

    # Get the free RAM after 'dd'
    R_RAM_AFTER=$(get_free_mem)

    # Extarct rate value and units from the output of 'dd'
    R_RATE=$(echo "$R" | tail -n1 | awk '{print $(NF-1)}')
    R_RATE_UNITS=$(echo "$R" | tail -n1 | awk '{print $(NF)}')

    # Save the raw information
    #R_RAW_OUTPUT[i-1]="$RATE $RATE_UNITS"
    R_RAW_OUTPUT[i]=$(printf "%9s %2s%9s%3s%9s %3s" $R_RAM_BEFORE $R_RAM_AFTER $R_RATE $R_RATE_UNITS)

    # Adjust the rate to be expressed in MB/s
    case $RATE_UNITS in
        "kB/s"|"")
        RATE=$(echo "$RATE" | sed -E 's/([0-9]+)\.([0-9])/0.0\1\2/g')
        ;;

        "MB/s")
        # This is the default, do not modified the value
        ;;

        "GB/s")
        RATE=$(echo "$RATE" | sed -E 's/([0-9]+)\.([0-9])/\1\200/g')
        ;;

        *)
        # Not supported unit identifier found.
        #Use '-1' as process rate value and continue
        RATE="-1"
    esac

    # Save the processed data
    R_RESULTS[i-1]="$R_RATE"

    #####################################
done

##########################################################
### Present results, write output files, and plot data ###
##########################################################

# Remove previous data files
rm -f $R_RESULT_FILE
rm -f $W_RESULT_FILE

# Present write operation results in screen and write the data
# to the output file
echo "============================" | tee -a $LOG_FILE
echo "Write results:" | tee -a $LOG_FILE
echo "============================" | tee -a $LOG_FILE
echo "Raw values obtained:" | tee -a $LOG_FILE
for i in `seq $((N+1))`; do
    echo "${W_RAW_OUTPUT[i-1]}" | tee -a $W_RESULT_FILE | tee -a $LOG_FILE
done

#echo "Process values (MB/s):"
#for i in `seq $N`; do
#   echo "${W_RESULTS[i-1]}"
#done
echo "============================" | tee -a $LOG_FILE

# Present read operation results in screen and write the data
# to the output file
echo "============================" | tee -a $LOG_FILE
echo "Read results:" | tee -a $LOG_FILE
echo "============================" | tee -a $LOG_FILE
echo "Raw values obtained:" | tee -a $LOG_FILE
for i in `seq $((N+1))`; do
    echo "${R_RAW_OUTPUT[i-1]}" | tee -a $R_RESULT_FILE | tee -a $LOG_FILE
done

#echo "Process values (MB/s):"
#for i in `seq $N`; do
#   echo "${R_RESULTS[i-1]}"
#done
echo "============================" | tee -a $LOG_FILE

# Plot the results to PNG files
gnuplot -e "input_file='$R_RESULT_FILE'" -e "output_file='$R_PLOT_FILE'" $GP_SCRIPT_FILE 2>/dev/null
gnuplot -e "input_file='$W_RESULT_FILE'" -e "output_file='$W_PLOT_FILE'" $GP_SCRIPT_FILE 2>/dev/null
