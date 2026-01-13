#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 <fastq_directory> <log_file> <bacteria_list_file> <reference_directory> <output_directory> [threads] [output_suffix]"
    echo "  fastq_directory:      Path to directory containing FASTQ files (gzipped or unzipped)"
    echo "  log_file:             Path to log file where processing details will be stored"
    echo "  bacteria_list_file:   Path to text file containing bacteria names (one per line)"
    echo "  reference_directory:  Path to directory containing bowtie2 indexes and SNP files"
    echo "  output_directory:     Path where StrainEst output will be stored"
    echo "  threads:              Number of threads to use (default: 20)"
    echo "  output_suffix:        Suffix for output files (default: 100X_110S)"
    exit 1
}

# Check if correct number of arguments provided
if [ $# -lt 5 ]; then
    echo "Error: Invalid number of arguments"
    usage
fi

# Get command line arguments
fastq_directory="$1"
log_file="$2"
bacteria_list_file="$3"
reference_directory="$4"
output_directory="$5"
threads="${6:-20}"
output_suffix="${7:-100X_110S}"

# Validate directories and files exist
if [ ! -d "$fastq_directory" ]; then
    echo "Error: FASTQ directory '$fastq_directory' does not exist"
    exit 1
fi

if [ ! -f "$bacteria_list_file" ]; then
    echo "Error: Bacteria list file '$bacteria_list_file' does not exist"
    exit 1
fi

if [ ! -d "$reference_directory" ]; then
    echo "Error: Reference directory '$reference_directory' does not exist"
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

# Read bacteria list from file
if [ ! -s "$bacteria_list_file" ]; then
    echo "Error: Bacteria list file '$bacteria_list_file' is empty"
    exit 1
fi

# Read bacteria names from file, skipping empty lines and trimming whitespace
bacteria_list=()
while IFS= read -r line || [ -n "$line" ]; do
    # Trim leading/trailing whitespace and skip empty lines
    bacteria=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -n "$bacteria" ]; then
        bacteria_list+=("$bacteria")
    fi
done < "$bacteria_list_file"

# Check if we have any bacteria
if [ ${#bacteria_list[@]} -eq 0 ]; then
    echo "Error: No valid bacteria names found in '$bacteria_list_file'"
    exit 1
fi

echo "Loaded ${#bacteria_list[@]} bacteria from $bacteria_list_file"

# Clear the log file if it exists
> "$log_file"

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

# Check if required tools are available
if ! command -v bowtie2 &> /dev/null; then
    echo "Error: 'bowtie2' command not found. Please ensure Bowtie2 is installed and in your PATH."
    exit 1
fi

if ! command -v samtools &> /dev/null; then
    echo "Error: 'samtools' command not found. Please ensure SAMtools is installed and in your PATH."
    exit 1
fi

if ! command -v strainest &> /dev/null; then
    echo "Error: 'strainest' command not found. Please ensure StrainEst is installed and in your PATH."
    exit 1
fi

# Log the processing parameters
echo "StrainEst Processing Parameters:" >> "$log_file"
echo "FASTQ Directory: $fastq_directory" >> "$log_file"
echo "Reference Directory: $reference_directory" >> "$log_file"
echo "Output Directory: $output_directory" >> "$log_file"
echo "Number of threads: $threads" >> "$log_file"
echo "Output suffix: $output_suffix" >> "$log_file"
echo "Bacteria to be processed:" >> "$log_file"
printf "  - %s\n" "${bacteria_list[@]}" >> "$log_file"
echo "" >> "$log_file"

# Outer loop for each bacteria
for bacteria in "${bacteria_list[@]}"; do
    echo "==========================================" >> "$log_file"
    echo "Processing bacteria: $bacteria" >> "$log_file"
    echo "Started at: $(date)" >> "$log_file"
    echo "==========================================" >> "$log_file"
    
    # Check if reference files exist
    bowtie2_index="${reference_directory}/${bacteria}_mapped"
    snp_file="${reference_directory}/${bacteria}_snp.dgrp"
    
    if [ ! -f "${bowtie2_index}.1.bt2" ] && [ ! -f "${bowtie2_index}.1.bt2l" ]; then
        echo "Warning: Bowtie2 index for '$bacteria' not found in '$reference_directory', skipping..." | tee -a "$log_file"
        continue
    fi
    
    if [ ! -f "$snp_file" ]; then
        echo "Warning: SNP file '$snp_file' for '$bacteria' not found, skipping..." | tee -a "$log_file"
        continue
    fi
    
    # Initialize total time and memory variables for this bacteria
    total_user_time=0
    total_system_time=0
    total_elapsed_time=0
    total_max_memory=0
    file_count=0

    # Find all R1 files (both compressed and uncompressed)
    while IFS= read -r -d '' r1_file; do
        echo "Processing file: $r1_file for $bacteria" >> "$log_file"
        
        # Find corresponding R2 file
        r2_file=$(find_r2_file "$r1_file")
        if [ -z "$r2_file" ] || [ ! -f "$r2_file" ]; then
            echo "Warning: Could not find R2 file for $r1_file, skipping..." | tee -a "$log_file"
            continue
        fi
        
        echo "Found R2 file: $r2_file" >> "$log_file"
        
        # Get sample name
        sample_name=$(get_sample_name "$r1_file")
        
        # Create output directory for this sample and bacteria
        sample_output_dir="${output_directory}/${sample_name}_${bacteria}_${output_suffix}_outputdir"
        mkdir -p "$sample_output_dir"
        
        # Build processing commands
        base_output="${output_directory}/${sample_name}_${bacteria}_${output_suffix}"
        
        processing_cmd="
        # Step 1: Bowtie2 alignment
        bowtie2 --very-fast --no-unal -x '$bowtie2_index' -1 '$r1_file' -2 '$r2_file' -S '${base_output}_mapped.sam' -p '$threads'
        
        # Step 2: Convert SAM to BAM
        samtools view -b -o '${base_output}_mapped.bam' '${base_output}_mapped.sam' -@ '$threads'
        
        # Step 3: Sort BAM file
        samtools sort '${base_output}_mapped.bam' -o '${base_output}_mapped.sorted.bam' -@ '$threads'
        
        # Step 4: Index BAM file
        samtools index '${base_output}_mapped.sorted.bam' -@ '$threads'
        
        # Step 5: Run StrainEst
        strainest est '$snp_file' '${base_output}_mapped.sorted.bam' '$sample_output_dir' -t '$threads'
        "
        
        # Measure time and memory usage
        echo "Starting StrainEst processing for $bacteria..." >> "$log_file"
        time_output=$( { /usr/bin/time -v bash -c "$processing_cmd" 2>&1; } 2>&1 )
        
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
        echo "Completed processing: $r1_file for $bacteria" | tee -a "$log_file"
        
    done < <(find "$fastq_directory" -type f \( -name "*_R1.fastq" -o -name "*_R1.fastq.gz" -o -name "*_1.fastq" -o -name "*_1.fastq.gz" -o -name "*R1_001.fastq" -o -name "*R1_001.fastq.gz" \) -print0)

    # Print total time and memory usage for this bacteria
    echo "==========================================" >> "$log_file"
    echo "Summary for $bacteria:" >> "$log_file"
    echo "Total Files Processed: $file_count" >> "$log_file"
    echo "Total User Time (seconds): $total_user_time" >> "$log_file"
    echo "Total System Time (seconds): $total_system_time" >> "$log_file"
    echo "Total Elapsed Time (seconds): $total_elapsed_time" >> "$log_file"
    echo "Total Maximum Memory (kbytes): $total_max_memory" >> "$log_file"
    echo "==========================================" >> "$log_file"
    echo "" >> "$log_file"
    
    echo "Completed processing for $bacteria at: $(date)"
done

echo "All bacteria processing completed!" >> "$log_file"
echo "Processing complete. Log saved to: $log_file"
echo "Output stored in: $output_directory"
