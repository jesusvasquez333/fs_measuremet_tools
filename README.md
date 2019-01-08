# fs_measuremet_tools

A collection of tool to measure the performance of I/O operation on file systems.

The tools are based on bash, and use standard gnu Linux applications.

## Tools:

The following tools are available:

Tool      | Description
----------|--------------
sfm.sh    | Measure single file R/W operation rates
mfm.sh    | Measure multiple files R operation rates

### sfm.sh

This tool measures the transfer rate of R/W operation of over single files.

The utility uses 'dd' to write a file into disk and then read it back extracting the R/W rates.

The user specifies the path where the file will be written, the size of the file, and how many times the file will be written and read back.

The final results are printed on screen at the end of the test, written to two output files, and plotted to two png files.
 - Read operation results are written to 'r_results.data', and plotted to 'r_results.png'
 - Write operation results are written to 'w_results.data', and plotted to 'w_results.png'
 - A log file is written to 'run.log'
The location of of the output files can be specified by the user.

```{r, engine='bash', usage}
usage: ./sfm.sh -i|--iterations iterations -s|--size[k,M,G] file_size -d|--dir directory [-n|--no-cache] [-f|--flush-cache] [-h|--help]
    -i|--iterations iterations : Number of times the file will be written and read back.
    -s|--size file_size[k,G,B] : Size of the file. Units identifiers ('k'=kilo, 'M'=Mega, 'G'=Giga) can be used; if omitted, 'k' is assumed.
                                 There must not be white spaces between the size and the units. A valid example will be: 2G.
    -d|--dir directory         : Directory where the file will be written. The filename 'tempfile' will be added to this path.
    -n|--no-cache              : Disable cache in R/W operations by using dd's iflag/oflag=direct.
    -f|--flush                 : Flush the local cache before each R/W operation by performing 'echo 3 > /proc/sys/vm/drop_caches'
                                 The test needs to be runt as root with this option.
    -o|--out-dir               : Directory to save the results. If not specified the current directory will be used.
    -h|--help                  : show this message.
```

### mfm.sh

Utility to measure the average disk's transfer rate while reading multiple files.

First, use this utility in write mode. It will create the test files in the specified path. The number of file and their size will be specified by the user.

After the files are created, the utility can be used in read mode (default). It will find and read all test files in the specified path measuring the total size and elapse time.

The test files are not automatically deleted after reading them, so that the test can be run multiple times if desired. The -c|--clean operation can be used to manually delete all the test files from an specified directory.

The final results are printed on screen at the end of the test.

```{r, engine='bash', usage}
usage: $THIS_SCRIPT_NAME -d|--dir directory [-w|--write -n|--num number_files -s|--size[k,M,G] file_size] [-c|--clean] [-h|--help]"
    -d|--dir directory         : Directory where the files will be read from."
    -w|--write                 : Set 'write mode'. If this option is omitted, 'read mode' is used by default."
    -n|--num number_files      : Number of files to be written (used in 'write mode')"
    -s|--size file_size[k,G,B] : Size of the files (used in 'write mode'). Units identifiers ('k'=kilo, 'M'=Mega, 'G'=Giga) can be used; if omitted, 'k' is assumed."
    -c|--clean                 : Delete the test files from the specified location."
    -h|--help                  : Show this message."
```