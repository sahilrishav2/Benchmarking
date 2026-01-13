#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 <fastq_directory> <log_file> <midasdb_dir> <output_directory> [num_cores] [midasdb_name]"
    echo "  fastq_directory:  Path to directory containing FASTQ files (gzipped or unzipped)"
    echo "  log_file:         Path to log file where processing details will be stored"
    echo "  midasdb_dir:      Path to MIDAS database directory"
    echo "  output_directory: Path where MIDAS2 output will be stored"
    echo "  num_cores:        Number of CPU cores to use (default: 1)"
    echo "  midasdb_name:     MIDAS database name (default: gtdb)"
    exit 1
}

# Check if correct number of arguments provided
if [ $# -lt 4 ]; then
    echo "Error: Invalid number of arguments"
    usage
fi

# Get command line arguments
fastq_directory="$1"
log_file="$2"
midasdb_dir="$3"
output_directory="$4"
num_cores="${5:-1}"
midasdb_name="${6:-gtdb}"

# Validate directory exists
if [ ! -d "$fastq_directory" ]; then
    echo "Error: Directory '$fastq_directory' does not exist"
    exit 1
fi

# Validate MIDAS database directory exists
if [ ! -d "$midasdb_dir" ]; then
    echo "Error: MIDAS database directory '$midasdb_dir' does not exist"
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
file_count=0

# Function to find R2 file
find_r2_file() {
    local r1_file="$1"
    local r2_file=""
    
    # Try different possible R2 file patterns
    if [[ "$r1_file" == *_R1.* ]]; then
        # Pattern: _R1. to _R2.
        r2_file="${r1_file/_R1./_R2.}"
    elif [[ "$r1_file" == *_1.* ]]; then
        # Pattern: _1. to _2.
        r2_file="${r1_file/_1./_2.}"
    elif [[ "$r1_file" == *R1_001.* ]]; then
        # Pattern: R1_001 to R2_001
        r2_file="${r1_file/R1_001/R2_001}"
    fi
    
    # Check if R2 file exists
    if [ -f "$r2_file" ]; then
        echo "$r2_file"
        return 0
    fi
    
    # If not found with pattern, try common extensions
    local base_r1=$(basename "$r1_file")
    local dir_r1=$(dirname "$r1_file")
    
    # Remove extensions to get base name
    local base_name="${base_r1%%.*}"
    base_name="${base_name%_R1}"
    base_name="${base_name%_1}"
    base_name="${base_name%R1_001}"
    
    # Try common R2 patterns
    local patterns=("_R2" "_2" "R2_001")
    local extensions=(".fastq.gz" ".fastq" ".fq.gz" ".fq")
    
    for pattern in "${patterns[@]}"; do
        for ext in "${extensions[@]}"; do
            local test_file="${dir_r1}/${base_name}${pattern}${ext}"
            if [ -f "$test_file" ]; then
                echo "$test_file"
                return 0
            fi
        done
    done
    
    return 1
}

# Function to get sample name
get_sample_name() {
    local input_file="$1"
    local base_name=$(basename "$input_file")
    
    # Remove extensions and R1 identifier
    base_name="${base_name%%.*}"
    base_name="${base_name%_R1}"
    base_name="${base_name%_1}"
    base_name="${base_name%R1_001}"
    
    echo "$base_name"
}

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

# Check if midas2 is available
if ! command -v midas2 &> /dev/null; then
    echo "Error: 'midas2' command not found. Please ensure MIDAS2 is installed and in your PATH."
    exit 1
fi

# Log the processing parameters
echo "MIDAS2 Processing Parameters:" >> "$log_file"
echo "FASTQ Directory: $fastq_directory" >> "$log_file"
echo "MIDAS DB Directory: $midasdb_dir" >> "$log_file"
echo "MIDAS DB Name: $midasdb_name" >> "$log_file"
echo "Number of cores: $num_cores" >> "$log_file"
echo "Output Directory: $output_directory" >> "$log_file"
echo "" >> "$log_file"

# Find all R1 files (both compressed and uncompressed)
while IFS= read -r -d '' r1_file; do
    echo "Processing file: $r1_file" | tee -a "$log_file"
    
    # Find corresponding R2 file
    r2_file=$(find_r2_file "$r1_file")
    if [ -z "$r2_file" ] || [ ! -f "$r2_file" ]; then
        echo "Warning: Could not find R2 file for $r1_file, skipping..." | tee -a "$log_file"
        continue
    fi
    
    echo "Found R2 file: $r2_file" >> "$log_file"
    
    # Get sample name
    sample_name=$(get_sample_name "$r1_file")
    sample_output_dir="${output_directory}/${sample_name}_output"
    
    # Create sample output directory
    mkdir -p "$sample_output_dir"
    
    # Build MIDAS2 command
    midas_cmd="midas2 run_species --sample_name '$sample_name' -1 '$r1_file' -2 '$r2_file' --midasdb_name '$midasdb_name' --midasdb_dir '$midasdb_dir' --num_cores '$num_cores' '$sample_output_dir'"
    
    # Measure time and memory usage
    echo "Starting MIDAS2 processing..." >> "$log_file"
    echo "Command: $midas_cmd" >> "$log_file"
    
    time_output=$( { /usr/bin/time -v bash -c "$midas_cmd" 2>&1; } 2>&1 )
    
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
    
    ((file_count++))
    echo "Completed processing: $r1_file" | tee -a "$log_file"
    echo "Output directory: $sample_output_dir" >> "$log_file"
    echo "----------------------------------------" >> "$log_file"
    
done < <(find "$fastq_directory" -type f \( -name "*_R1.fastq" -o -name "*_R1.fastq.gz" -o -name "*_1.fastq" -o -name "*_1.fastq.gz" -o -name "*R1_001.fastq" -o -name "*R1_001.fastq.gz" \) -print0)

# Print summary
echo "========================================" >> "$log_file"
echo "PROCESSING SUMMARY" >> "$log_file"
echo "========================================" >> "$log_file"
echo "Total files processed: $file_count" >> "$log_file"
echo "MIDAS DB Name: $midasdb_name" >> "$log_file"
echo "MIDAS DB Directory: $midasdb_dir" >> "$log_file"
echo "Number of cores: $num_cores" >> "$log_file"
echo "Output Directory: $output_directory" >> "$log_file"
echo "Total User Time (seconds): $total_user_time" >> "$log_file"
echo "Total System Time (seconds): $total_system_time" >> "$log_file"
echo "Total Elapsed Time (seconds): $total_elapsed_time" >> "$log_file"
echo "Total Maximum Memory (kbytes): $total_max_memory" >> "$log_file"

if [ $file_count -gt 0 ]; then
    avg_memory=$(echo "$total_max_memory / $file_count" | bc -l 2>/dev/null)
    if [ -n "$avg_memory" ]; then
        echo "Average Memory per file (kbytes): $avg_memory" >> "$log_file"
    else
        echo "Average Memory per file (kbytes): N/A" >> "$log_file"
    fi
fi

echo "Processing complete. Log saved to: $log_file"
echo "Processed ${file_count} files with MIDAS2"
echo "Output stored in: $output_directory"
