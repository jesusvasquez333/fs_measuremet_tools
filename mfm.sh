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

# Test file name prefix. "_$(N)" will be append
# to this prefix to form the file name, where
# N start at 1 and increments for each file.
FILE_NAME_PREFIX='tempfile'

#################
### Functions ###
#################

# Usage message
usage() {
    echo "Utility to measure the average disk's transfer rate while reading multiple files."
    echo
    echo "First, use this utility in write mode. It will create the test files in the specified path. The number of file and their size will be specified by the user."
    echo
    echo "After the files are created, the utility can be used in read mode (default). It will find and read all test files in the specified path measuring the total size and elapse time."
    echo
    echo "The test files are not automatically deleted after reading them, so that the test can be run multiple times if desired. The -c|--clean operation can be used to manually delete all the test files from an specified directory."
    echo
    echo "The final results are printed on screen at the end of the test."
    echo
    echo "usage: $THIS_SCRIPT_NAME -d|--dir directory [-w|--write -n|--num number_files -s|--size[k,M,G] file_size] [-c|--clean] [-h|--help]"
    echo "    -d|--dir directory         : Directory where the files will be read from."
    echo "    -w|--write                 : Set 'write mode'. If this option is omitted, 'read mode' is used by default."
    echo "    -n|--num number_files      : Number of files to be written (used in 'write mode')"
    echo "    -s|--size file_size[k,G,B] : Size of the files (used in 'write mode'). Units identifiers ('k'=kilo, 'M'=Mega, 'G'=Giga) can be used; if omitted, 'k' is assumed."
    echo "    -c|--clean                 : Delete the test files from the specified location."
    echo "    -h|--help                  : Show this message."
}

# Send error message and exit
error_message() {
    echo "$1" >&2
    exit
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
    #local VAL=$(echo "scale=2; $VAL/$FACTOR" | bc -l)

    # Return the scaled value and its units
    echo "${VAL} ${UNITS[I]}"
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
    -n|--num)
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

    -w|--write)
    WRITE_MODE="YES"
    shift
    ;;

    -c|--clean)
    CLEAN_MODE="YES"
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

if [ -z ${TEST_DIR+x} ]; then
    error_message "ERROR: Test directory not defined!"
fi

if [ ! -z ${WRITE_MODE+x} ]; then
    echo "Write mode"
    if [ -z "$N" ]; then
        error_message "ERROR: Number of files not defined!"
    fi

    if [ -z "$SIZE" ]; then
        error_message "ERROR: File size not defined!"
    fi
else
    echo "Read mode"
fi

###################
### Check paths ###
###################

# Verify that the test directory exist
verify_dir ${TEST_DIR}

# Add '/' at the end of the path if it is missing
TEST_DIR=$(format_dir_name ${TEST_DIR})

####################################
### Verify if clean mode is used ###
####################################

if [ ! -z ${CLEAN_MODE+x} ]; then
    echo "Cleaning test files from '${TEST_DIR}'..."
    rm -rf ${TEST_DIR}${FILE_NAME_PREFIX}_*
    echo "Done!"
    echo
    exit
fi

##########################################
### Check and adjust the file size and ###
### Calculate the number of R/W blocks ###
##########################################

# Number of bytes to R/W (passed to 'dd')
BYTES=$((16*1024))

if [ ! -z ${WRITE_MODE+x} ]; then
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
fi

###############################
### Read or write the files ###
###############################

if [ -z ${WRITE_MODE+x} ]; then
    echo "Reading files..."

    # Make time only output elapsed time in seconds
    TIMEFORMAT=%R

    # Read all the files, measuring the total size of all files and the time elapse
    R=$( {
        TOTAL_SIZE=0
        NUM_FILES=0
        time for line in $(find ${TEST_DIR} -name "${FILE_NAME_PREFIX}_*"); do
            R=$(dd if=${line} of=/dev/null bs=${BYTES} 2>&1)

            # Get the transfered file size
            R_SIZE=$(echo "$R" | tail -n1 | awk '{print $1}')
            TOTAL_SIZE=$(( TOTAL_SIZE + R_SIZE ))
            NUM_FILES=$(( NUM_FILES + 1 ))
        done
        echo "$TOTAL_SIZE $NUM_FILES"
    } 2>&1 )

    #
    R_TIME=$(echo $R | awk '{print $1}')
    R_SIZE=$(echo $R | awk '{print $2}')
    R_NUM=$(echo $R | awk '{print $3}')
    R_RATE=$(echo "scale=0; $R_SIZE/$R_TIME" | bc -l)

    echo
    echo "==================================="
    echo "Read Results:"
    echo "==================================="
    echo "Number of files found : ${R_NUM}"
    echo "Total size transfered : $(eng_value ${R_SIZE})"
    echo "Total time elapse     : ${R_TIME} s"
    echo "Average total rate    : $(eng_value ${R_RATE})"
    echo "==================================="
else
    echo "Writting files...."
    for i in `seq $N`; do
        FILE_NAME="${TEST_DIR}${FILE_NAME_PREFIX}_${i}"
        dd if=/dev/zero of=${FILE_NAME} bs=${BYTES} count=${COUNT} 2>/dev/null
    done

    echo
    echo "==================================="
    echo "Write results: "
    echo "==================================="
    echo "Test directory  : ${TEST_DIR}"
    echo "Number of files : ${SIZE}"
    echo "Size of files   : ${N}"
    echo "==================================="
fi
