#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 <config_directory> <log_file> <pstrain_script> <bowtie2db_path> <index_name> <output_directory> [proc] [nproc] [config_pattern]"
    echo "  config_directory: Path to directory containing configuration files"
    echo "  log_file:         Path to log file where processing details will be stored"
    echo "  pstrain_script:   Path to PStrain.py script"
    echo "  bowtie2db_path:   Path to bowtie2 database directory"
    echo "  index_name:       Name of the index (e.g., mpa_vOct22_CHOCOPhlAnSGB_202403)"
    echo "  output_directory: Path where PStrain output will be stored"
    echo "  proc:             Number of processes for --proc (default: 20)"
    echo "  nproc:            Number of processes for --nproc (default: 20)"
    echo "  config_pattern:   Pattern for config files (default: config*.txt)"
    exit 1
}

# Check if correct number of arguments provided
if [ $# -lt 6 ]; then
    echo "Error: Invalid number of arguments"
    usage
fi

# Get command line arguments
config_directory="$1"
log_file="$2"
pstrain_script="$3"
bowtie2db_path="$4"
index_name="$5"
output_directory="$6"
proc="${7:-20}"
nproc="${8:-20}"
config_pattern="${9:-config*.txt}"

# Validate directories and files exist
if [ ! -d "$config_directory" ]; then
    echo "Error: Config directory '$config_directory' does not exist"
    exit 1
fi

if [ ! -f "$pstrain_script" ]; then
    echo "Error: PStrain script '$pstrain_script' does not exist"
    exit 1
fi

if [ ! -d "$bowtie2db_path" ]; then
    echo "Error: Bowtie2 database directory '$bowtie2db_path' does not exist"
    exit 1
fi

# Create output directory if it doesn't exist
if [ ! -d "$output_directory" ]; then
    mkdir -p "$output_directory"
    if [ $? -ne 0 ]; then
        echo "Error: Cannot create output directory '$output_directory'"
        exit 1
    fi
fi

# Create log file directory if it doesn't exist
log_dir=$(dirname "$log_file")
if [ ! -d "$log_dir" ]; then
    mkdir -p "$log_dir"
    if [ $? -ne 0 ]; then
        echo "Error: Cannot create log directory '$log_dir'"
        exit 1
    fi
fi

# Clear the log file if it exists
> "$log_file"

# Initialize total time and memory variables
total_user_time=0
total_system_time=0
total_elapsed_time=0
total_max_memory=0
config_count=0

# Function to convert time to seconds
convert_to_seconds() {
    local time_str="$1"
    # Handle format: h:mm:ss or m:ss
    if [[ "$time_str" =~ ^([0-9]+):([0-9]+):([0-9.]+)$ ]]; then
        # h:mm:ss format
        local hours="${BASH_REMATCH[1]}"
        local minutes="${BASH_REMATCH[2]}"
        local seconds="${BASH_REMATCH[3]}"
        echo "$hours * 3600 + $minutes * 60 + $seconds" | bc -l
    elif [[ "$time_str" =~ ^([0-9]+):([0-9.]+)$ ]]; then
        # m:ss format
        local minutes="${BASH_REMATCH[1]}"
        local seconds="${BASH_REMATCH[2]}"
        echo "$minutes * 60 + $seconds" | bc -l
    else
        echo "0"
    fi
}

# Check if bc is available for calculations
if ! command -v bc &> /dev/null; then
    echo "Warning: 'bc' command not found. Time calculations may not work properly."
    echo "Install bc using: sudo apt-get install bc (Ubuntu/Debian) or sudo yum install bc (RHEL/CentOS)"
fi

# Check if python3 is available
if ! command -v python3 &> /dev/null; then
    echo "Error: 'python3' command not found. Please ensure Python 3 is installed."
    exit 1
fi

# Log the processing parameters
echo "PStrain Processing Parameters:" >> "$log_file"
echo "Config Directory: $config_directory" >> "$log_file"
echo "Config Pattern: $config_pattern" >> "$log_file"
echo "PStrain Script: $pstrain_script" >> "$log_file"
echo "Bowtie2 DB Path: $bowtie2db_path" >> "$log_file"
echo "Index Name: $index_name" >> "$log_file"
echo "Output Directory: $output_directory" >> "$log_file"
echo "Processes (--proc): $proc" >> "$log_file"
echo "Processes (--nproc): $nproc" >> "$log_file"
echo "" >> "$log_file"

# Find all configuration files matching the pattern
config_files=()
while IFS= read -r -d '' config_file; do
    config_files+=("$config_file")
done < <(find "$config_directory" -maxdepth 1 -type f -name "$config_pattern" -print0)

# Check if any config files were found
if [ ${#config_files[@]} -eq 0 ]; then
    echo "Error: No configuration files found matching pattern '$config_pattern' in '$config_directory'"
    exit 1
fi

echo "Found ${#config_files[@]} configuration files"

# Loop through each configuration file
for config_file in "${config_files[@]}"; do
    config_base=$(basename "$config_file")
    config_name="${config_base%.*}"
    
    echo "Processing configuration file: $config_file" | tee -a "$log_file"
    
    # Create output directory for this config
    config_output_dir="${output_directory}/out_${config_name}"
    mkdir -p "$config_output_dir"
    
    # Build PStrain command
    pstrain_cmd="python3 '$pstrain_script' -c '$config_file' -o '$config_output_dir' --bowtie2db '$bowtie2db_path' -x '$index_name' --proc '$proc' --nproc '$nproc'"
    
    # Measure time and memory usage
    echo "Starting PStrain processing..." >> "$log_file"
    echo "Command: $pstrain_cmd" >> "$log_file"
    
    time_output=$( { /usr/bin/time -v bash -c "$pstrain_cmd" 2>&1; } 2>&1 )
    
    echo "$time_output" >> "$log_file"
    
    # Extract timing and memory information
    user_time=$(echo "$time_output" | grep "User time (seconds)" | awk '{print $4}' || echo "0")
    system_time=$(echo "$time_output" | grep "System time (seconds)" | awk '{print $4}' || echo "0")
    elapsed_time=$(echo "$time_output" | grep "Elapsed (wall clock) time" | awk -F': ' '{print $2}' || echo "0")
    max_memory=$(echo "$time_output" | grep "Maximum resident set size (kbytes)" | awk '{print $6}' || echo "0")
    
    # Convert elapsed time to seconds
    elapsed_seconds=$(convert_to_seconds "$elapsed_time")
    
    # Add to total time and memory usage (only if we have valid numbers)
    if [[ "$user_time" =~ ^[0-9.]+$ ]]; then
        total_user_time=$(echo "$total_user_time + $user_time" | bc -l 2>/dev/null || echo "$total_user_time")
    fi
    
    if [[ "$system_time" =~ ^[0-9.]+$ ]]; then
        total_system_time=$(echo "$total_system_time + $system_time" | bc -l 2>/dev/null || echo "$total_system_time")
    fi
    
    if [[ "$elapsed_seconds" =~ ^[0-9.]+$ ]] && [ -n "$(command -v bc)" ]; then
        total_elapsed_time=$(echo "$total_elapsed_time + $elapsed_seconds" | bc -l)
    fi
    
    if [[ "$max_memory" =~ ^[0-9]+$ ]]; then
        total_max_memory=$((total_max_memory + max_memory))
    fi
    
    ((config_count++))
    echo "Completed processing: $config_file" | tee -a "$log_file"
    echo "Output directory: $config_output_dir" >> "$log_file"
    echo "----------------------------------------" >> "$log_file"
done

# Print summary
echo "========================================" >> "$log_file"
echo "PROCESSING SUMMARY" >> "$log_file"
echo "========================================" >> "$log_file"
echo "Total config files processed: $config_count" >> "$log_file"
echo "Config Directory: $config_directory" >> "$log_file"
echo "Config Pattern: $config_pattern" >> "$log_file"
echo "Bowtie2 DB Path: $bowtie2db_path" >> "$log_file"
echo "Index Name: $index_name" >> "$log_file"
echo "Output Directory: $output_directory" >> "$log_file"
echo "Processes (--proc): $proc" >> "$log_file"
echo "Processes (--nproc): $nproc" >> "$log_file"
echo "Total User Time (seconds): $total_user_time" >> "$log_file"
echo "Total System Time (seconds): $total_system_time" >> "$log_file"
echo "Total Elapsed Time (seconds): $total_elapsed_time" >> "$log_file"
echo "Total Maximum Memory (kbytes): $total_max_memory" >> "$log_file"

if [ $config_count -gt 0 ]; then
    avg_memory=$(echo "$total_max_memory / $config_count" | bc -l 2>/dev/null)
    if [ -n "$avg_memory" ]; then
        echo "Average Memory per config (kbytes): $avg_memory" >> "$log_file"
    else
        echo "Average Memory per config (kbytes): N/A" >> "$log_file"
    fi
fi

echo "Processing complete. Log saved to: $log_file"
echo "Processed ${config_count} configuration files with PStrain"
echo "Output stored in: $output_directory"
