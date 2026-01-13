#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 <fastq_directory> <log_file> <metalign_data_dir> <output_directory> [threads] [output_suffix]"
    echo "  fastq_directory:    Path to directory containing FASTQ files (gzipped or unzipped)"
    echo "  log_file:           Path to log file where processing details will be stored"
    echo "  metalign_data_dir:  Path to Metalign data directory"
    echo "  output_directory:   Path where Metalign output will be stored"
    echo "  threads:            Number of threads to use (default: 1)"
    echo "  output_suffix:      Suffix for output files (default: metalign_abundances)"
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
metalign_data_dir="$3"
output_directory="$4"
threads="${5:-1}"
output_suffix="${6:-metalign_abundances}"

# Validate directory exists
if [ ! -d "$fastq_directory" ]; then
    echo "Error: Directory '$fastq_directory' does not exist"
    exit 1
fi

# Validate Metalign data directory exists
if [ ! -d "$metalign_data_dir" ]; then
    echo "Error: Metalign data directory '$metalign_data_dir' does not exist"
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

# Function to get sample name
get_sample_name() {
    local input_file="$1"
    local base_name=$(basename "$input_file")
    
    # Remove extensions
    base_name="${base_name%%.*}"
    base_name="${base_name%.fastq}"
    base_name="${base_name%.fq}"
    
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

# Check if metalign.py is available
if ! command -v metalign.py &> /dev/null; then
    echo "Warning: 'metalign.py' command not found in PATH. Trying to find it..."
    # Try to find metalign.py in common locations
    metalign_path=$(find / -name "metalign.py" 2>/dev/null | head -1)
    if [ -n "$metalign_path" ]; then
        echo "Found metalign.py at: $metalign_path"
        metalign_cmd="$metalign_path"
    else
        echo "Error: 'metalign.py' command not found. Please ensure Metalign is installed."
        exit 1
    fi
else
    metalign_cmd="metalign.py"
fi

# Log the processing parameters
echo "Metalign Processing Parameters:" >> "$log_file"
echo "FASTQ Directory: $fastq_directory" >> "$log_file"
echo "Metalign Data Directory: $metalign_data_dir" >> "$log_file"
echo "Output Directory: $output_directory" >> "$log_file"
echo "Number of threads: $threads" >> "$log_file"
echo "Output suffix: $output_suffix" >> "$log_file"
echo "Strain level: enabled" >> "$log_file"
echo "" >> "$log_file"

# Process all FASTQ files (both compressed and uncompressed)
while IFS= read -r -d '' fastq_file; do
    echo "Processing file: $fastq_file" | tee -a "$log_file"
    
    # Get sample name
    sample_name=$(get_sample_name "$fastq_file")
    output_file="${output_directory}/${sample_name}_${output_suffix}.tsv"
    
    # Build Metalign command
    metalign_command="$metalign_cmd '$fastq_file' '$metalign_data_dir' --output '$output_file' --threads '$threads' --strain_level"
    
    # Measure time and memory usage
    echo "Starting Metalign processing..." >> "$log_file"
    echo "Command: $metalign_command" >> "$log_file"
    
    time_output=$( { /usr/bin/time -v bash -c "$metalign_command" 2>&1; } 2>&1 )
    
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
    echo "Completed processing: $fastq_file" | tee -a "$log_file"
    echo "Output file: $output_file" >> "$log_file"
    echo "----------------------------------------" >> "$log_file"
    
done < <(find "$fastq_directory" -type f \( -name "*.fastq" -o -name "*.fastq.gz" -o -name "*.fq" -o -name "*.fq.gz" \) -print0)

# Print summary
echo "========================================" >> "$log_file"
echo "PROCESSING SUMMARY" >> "$log_file"
echo "========================================" >> "$log_file"
echo "Total files processed: $file_count" >> "$log_file"
echo "Metalign Data Directory: $metalign_data_dir" >> "$log_file"
echo "Number of threads: $threads" >> "$log_file"
echo "Output Directory: $output_directory" >> "$log_file"
echo "Output suffix: $output_suffix" >> "$log_file"
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
echo "Processed ${file_count} files with Metalign"
echo "Output stored in: $output_directory"
