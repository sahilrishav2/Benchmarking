#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 <config_file> <output_directory> <num_strains> <depth> [threads]"
    echo "  config_file:       Path to text file containing directories of bacterial genomes (one per line)"
    echo "  output_directory:  Path where output files will be stored"
    echo "  num_strains:       Number of strains to include in the metagenome (e.g., 10, 100, 500, 1355)"
    echo "  depth:          Sequencing depth (10, 50, or 100)"
    echo "  threads:           Number of CPU threads to use (default: 20)"
    echo ""
    echo "Example:"
    echo "  $0 list.txt /path/to/output 10 10"
    echo "  $0 list.txt /path/to/output 100 50"
    echo "  $0 list.txt /path/to/output 500 100"
    exit 1
}

# Function to check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Function to print colored output
print_color() {
    local color_code=$1
    shift
    echo -e "\033[${color_code}m$*\033[0m"
}

# Function to get random element from array
get_random_element() {
    local arr=("$@")
    local arr_size=${#arr[@]}
    if [ $arr_size -eq 0 ]; then
        echo ""
    else
        echo "${arr[$((RANDOM % arr_size))]}"
    fi
}

# Function to shuffle array
shuffle_array() {
    local arr=("$@")
    local shuffled=()
    local indices=($(seq 0 $((${#arr[@]} - 1)) | shuf))
    for i in "${indices[@]}"; do
        shuffled+=("${arr[$i]}")
    done
    echo "${shuffled[@]}"
}

# Main function to run the simulation
main() {
    # Check if correct number of arguments provided
    if [ $# -lt 4 ]; then
        echo "Error: Invalid number of arguments"
        usage
    fi

    # Get command line arguments
    CONFIG_FILE="$1"
    OUTPUT_DIR="$2"
    NUM_STRAINS="$3"
    depth="$4"
    THREADS="${5:-20}"

    # Validate inputs
    if [ ! -f "$CONFIG_FILE" ]; then
        print_color "31" "Error: Config file '$CONFIG_FILE' does not exist"
        exit 1
    fi

    if [[ ! "$NUM_STRAINS" =~ ^[0-9]+$ ]]; then
        print_color "31" "Error: Number of strains must be a positive integer"
        exit 1
    fi

    if [[ ! "$depth" =~ ^(10|50|100)$ ]]; then
        print_color "31" "Error: depth must be 10, 50, or 100"
        exit 1
    fi

    if [[ ! "$THREADS" =~ ^[0-9]+$ ]] || [ "$THREADS" -lt 1 ]; then
        print_color "31" "Error: Threads must be a positive integer"
        exit 1
    fi

    # Check if InSilicoSeq is installed
    if ! command_exists iss; then
        print_color "31" "Error: InSilicoSeq (iss) is not installed or not in PATH"
        echo "Please install with: pip install in_silico_sequencing"
        exit 1
    fi

    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    if [ $? -ne 0 ]; then
        print_color "31" "Error: Cannot create output directory '$OUTPUT_DIR'"
        exit 1
    fi

    # Create log file
    LOG_FILE="${OUTPUT_DIR}/simulation_${NUM_STRAINS}_strains_${depth}X.log"
    echo "Metagenome Simulation Log" > "$LOG_FILE"
    echo "==========================" >> "$LOG_FILE"
    echo "Date: $(date)" >> "$LOG_FILE"
    echo "Number of strains: $NUM_STRAINS" >> "$LOG_FILE"
    echo "depth: ${depth}X" >> "$LOG_FILE"
    echo "Threads: $THREADS" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"

    # Read directories from config file
    print_color "34" "Reading genome directories from $CONFIG_FILE..."
    declare -a GENOME_DIRS
    while IFS= read -r line || [ -n "$line" ]; do
        # Trim whitespace and skip empty lines/comments
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -n "$line" ] && [[ ! "$line" =~ ^# ]]; then
            if [ -d "$line" ]; then
                GENOME_DIRS+=("$line")
                echo "Found directory: $line" >> "$LOG_FILE"
            else
                print_color "33" "Warning: Directory '$line' does not exist, skipping"
                echo "Warning: Directory '$line' does not exist, skipping" >> "$LOG_FILE"
            fi
        fi
    done < "$CONFIG_FILE"

    if [ ${#GENOME_DIRS[@]} -eq 0 ]; then
        print_color "31" "Error: No valid genome directories found in '$CONFIG_FILE'"
        exit 1
    fi

    NUM_DIRS=${#GENOME_DIRS[@]}
    print_color "32" "Found $NUM_DIRS genome directories"

    # Calculate target genomes per directory
    TARGET_PER_DIR=$(( (NUM_STRAINS + NUM_DIRS - 1) / NUM_DIRS ))  # Ceiling division
    print_color "34" "Target genomes per directory: $TARGET_PER_DIR"

    # Scan all directories and collect genome files
    declare -A DIR_GENOMES  # Associative array: directory -> array of genomes
    TOTAL_GENOMES=0

    print_color "34" "Scanning for genome files (with .fna, .fa, .fasta extensions)..."
    for dir in "${GENOME_DIRS[@]}"; do
        # Find all genome files with common extensions
        declare -a genomes_in_dir=()
        while IFS= read -r -d '' genome; do
            genomes_in_dir+=("$genome")
        done < <(find "$dir" -type f \( -name "*.fna" -o -name "*.fa" -o -name "*.fasta" -o -name "*.fna.gz" -o -name "*.fa.gz" -o -name "*.fasta.gz" \) -print0)
        
        # Shuffle genomes in this directory
        if [ ${#genomes_in_dir[@]} -gt 0 ]; then
            genomes_in_dir=($(shuffle_array "${genomes_in_dir[@]}"))
            DIR_GENOMES["$dir"]="${genomes_in_dir[*]}"
            TOTAL_GENOMES=$((TOTAL_GENOMES + ${#genomes_in_dir[@]}))
            echo "Directory '$dir': ${#genomes_in_dir[@]} genomes found" >> "$LOG_FILE"
        else
            echo "Directory '$dir': No genome files found" >> "$LOG_FILE"
            print_color "33" "Warning: No genome files found in '$dir'"
        fi
    done

    if [ $TOTAL_GENOMES -eq 0 ]; then
        print_color "31" "Error: No genome files found in any directory"
        exit 1
    fi

    print_color "32" "Total genomes available: $TOTAL_GENOMES"

    if [ $TOTAL_GENOMES -lt $NUM_STRAINS ]; then
        print_color "33" "Warning: Only $TOTAL_GENOMES genomes available, using all available genomes"
        NUM_STRAINS=$TOTAL_GENOMES
    fi

    # Select genomes for simulation
    print_color "34" "Selecting $NUM_STRAINS genomes for simulation..."
    SELECTED_GENOMES=()
    SELECTED_MANIFEST="${OUTPUT_DIR}/selected_genomes_${NUM_STRAINS}_strains_${depth}X.txt"
    echo "# Selected Genomes Manifest" > "$SELECTED_MANIFEST"
    echo "# Date: $(date)" >> "$SELECTED_MANIFEST"
    echo "# Number of strains: $NUM_STRAINS" >> "$SELECTED_MANIFEST"
    echo "# depth: ${depth}X" >> "$SELECTED_MANIFEST"
    echo "" >> "$SELECTED_MANIFEST"
    echo "Filepath\tSpecies" >> "$SELECTED_MANIFEST"

    # First pass: Try to get target_per_dir from each directory
    for dir in "${GENOME_DIRS[@]}"; do
        if [ ${#SELECTED_GENOMES[@]} -ge $NUM_STRAINS ]; then
            break
        fi
        
        genomes_str="${DIR_GENOMES[$dir]:-}"
        if [ -n "$genomes_str" ]; then
            IFS=' ' read -ra genomes <<< "$genomes_str"
            available=${#genomes[@]}
            
            # Calculate how many to take from this directory
            to_take=$(( NUM_STRAINS - ${#SELECTED_GENOMES[@]} ))
            if [ $to_take -gt $TARGET_PER_DIR ]; then
                to_take=$TARGET_PER_DIR
            fi
            if [ $to_take -gt $available ]; then
                to_take=$available
            fi
            
            # Take genomes
            for ((i=0; i<to_take && i<available; i++)); do
                SELECTED_GENOMES+=("${genomes[$i]}")
                # Extract species name from directory
                species_name=$(basename "$dir")
                echo -e "${genomes[$i]}\t$species_name" >> "$SELECTED_MANIFEST"
            done
            
            # Remove taken genomes from the array
            if [ $to_take -gt 0 ]; then
                DIR_GENOMES["$dir"]="${genomes[*]:$to_take}"
            fi
        fi
    done

    # Second pass: If we still need more genomes, get them from directories with remaining genomes
    if [ ${#SELECTED_GENOMES[@]} -lt $NUM_STRAINS ]; then
        print_color "34" "Second pass: Selecting additional genomes..."
        
        # Create a list of directories that still have genomes
        declare -a dirs_with_genomes
        for dir in "${GENOME_DIRS[@]}"; do
            genomes_str="${DIR_GENOMES[$dir]:-}"
            if [ -n "$genomes_str" ]; then
                IFS=' ' read -ra genomes <<< "$genomes_str"
                if [ ${#genomes[@]} -gt 0 ]; then
                    dirs_with_genomes+=("$dir")
                fi
            fi
        done
        
        # Randomly select from directories with remaining genomes
        while [ ${#SELECTED_GENOMES[@]} -lt $NUM_STRAINS ] && [ ${#dirs_with_genomes[@]} -gt 0 ]; do
            # Pick a random directory
            random_dir=$(get_random_element "${dirs_with_genomes[@]}")
            
            # Get genomes from this directory
            genomes_str="${DIR_GENOMES[$random_dir]}"
            IFS=' ' read -ra genomes <<< "$genomes_str"
            
            if [ ${#genomes[@]} -gt 0 ]; then
                # Take the first genome
                SELECTED_GENOMES+=("${genomes[0]}")
                species_name=$(basename "$random_dir")
                echo -e "${genomes[0]}\t$species_name" >> "$SELECTED_MANIFEST"
                
                # Remove taken genome
                DIR_GENOMES["$random_dir"]="${genomes[*]:1}"
                
                # If directory has no more genomes, remove it from the list
                if [ ${#genomes[@]} -eq 1 ]; then
                    # Remove directory from dirs_with_genomes
                    declare -a new_dirs=()
                    for d in "${dirs_with_genomes[@]}"; do
                        if [ "$d" != "$random_dir" ]; then
                            new_dirs+=("$d")
                        fi
                    done
                    dirs_with_genomes=("${new_dirs[@]}")
                fi
            fi
        done
    fi

    print_color "32" "Successfully selected ${#SELECTED_GENOMES[@]} genomes"

    # Calculate number of reads based on depth and number of strains
    print_color "34" "Calculating number of reads for ${depth}X depth..."
    
    # Define reads per strain based on depth
    declare -A READS_PER_STRAIN=(
        ["10"]=360000   # 0.36M per strain
        ["50"]=1800000  # 1.8M per strain
        ["100"]=3600000 # 3.6M per strain
    )
    
    READS_PER_STRAIN=${READS_PER_STRAIN[$depth]}
    TOTAL_READS=$(( NUM_STRAINS * READS_PER_STRAIN ))
    
    # Format for human readability
    if [ $TOTAL_READS -ge 1000000 ]; then
        TOTAL_READS_READABLE=$(echo "scale=2; $TOTAL_READS / 1000000" | bc)
        TOTAL_READS_READABLE="${TOTAL_READS_READABLE}M"
    else
        TOTAL_READS_READABLE="${TOTAL_READS}"
    fi
    
    print_color "32" "Total reads to generate: $TOTAL_READS ($TOTAL_READS_READABLE)"
    echo "Total reads: $TOTAL_READS ($TOTAL_READS_READABLE)" >> "$LOG_FILE"

    # Create a temporary directory with symlinks to selected genomes
    print_color "34" "Creating temporary directory with genome symlinks..."
    TEMP_DIR=$(mktemp -d -p "$OUTPUT_DIR" temp_genomes_XXXXXX)
    GENOME_LIST_FILE="${TEMP_DIR}/genome_list.txt"
    
    for genome in "${SELECTED_GENOMES[@]}"; do
        # Create symlink in temp directory
        ln -sf "$genome" "$TEMP_DIR/"
    done
    
    # Create a file listing all genomes
    find "$TEMP_DIR" -type l -name "*.fna" -o -name "*.fa" -o -name "*.fasta" -o -name "*.fna.gz" -o -name "*.fa.gz" -o -name "*.fasta.gz" | sort > "$GENOME_LIST_FILE"

    # Generate output filename
    OUTPUT_PREFIX="${OUTPUT_DIR}/synthetic_reads_${NUM_STRAINS}_strains_${depth}X"

    # Run InSilicoSeq
    print_color "34" "Starting InSilicoSeq simulation..."
    echo "Command: iss generate --draft \"$TEMP_DIR/*.fna\" --model novaseq --output \"$OUTPUT_PREFIX\" --cpus \"$THREADS\" --n_reads \"$TOTAL_READS\"" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    echo "=== Simulation Output ===" >> "$LOG_FILE"

    # Run the simulation
    if command_exists iss; then
        print_color "36" "Running: iss generate --draft \"$TEMP_DIR/*.fna\" --model novaseq --output \"$OUTPUT_PREFIX\" --cpus \"$THREADS\" --n_reads \"$TOTAL_READS\""
        
        # Run iss and capture output
        ISS_OUTPUT=$(iss generate --draft "$TEMP_DIR/*.fna" --model novaseq --output "$OUTPUT_PREFIX" --cpus "$THREADS" --n_reads "$TOTAL_READS" 2>&1)
        
        # Save output to log
        echo "$ISS_OUTPUT" >> "$LOG_FILE"
        
        # Check if successful
        if [ $? -eq 0 ]; then
            print_color "32" "Simulation completed successfully!"
            print_color "32" "Output files:"
            print_color "32" "  Reads: ${OUTPUT_PREFIX}_R1.fastq and ${OUTPUT_PREFIX}_R2.fastq"
            print_color "32" "  Log: $LOG_FILE"
            print_color "32" "  Manifest: $SELECTED_MANIFEST"
            
            # Also list generated files
            echo "" >> "$LOG_FILE"
            echo "=== Generated Files ===" >> "$LOG_FILE"
            for file in "${OUTPUT_PREFIX}"*.fastq "${OUTPUT_PREFIX}"*.log; do
                if [ -f "$file" ]; then
                    echo "$(basename "$file")" >> "$LOG_FILE"
                fi
            done
        else
            print_color "31" "Error: Simulation failed"
            echo "$ISS_OUTPUT"
        fi
    else
        print_color "31" "Error: 'iss' command not found after checking"
    fi

    # Clean up temporary directory
    print_color "34" "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"

    # Create summary file
    SUMMARY_FILE="${OUTPUT_DIR}/simulation_summary_${NUM_STRAINS}_strains_${depth}X.txt"
    cat > "$SUMMARY_FILE" << EOF
Metagenome Simulation Summary
=============================
Date: $(date)
Number of strains requested: $NUM_STRAINS
Number of strains selected: ${#SELECTED_GENOMES[@]}
depth: ${depth}X
Total reads generated: $TOTAL_READS ($TOTAL_READS_READABLE)
Threads used: $THREADS

Output Files:
- Reads: ${OUTPUT_PREFIX}_R1.fastq, ${OUTPUT_PREFIX}_R2.fastq
- Log: $(basename "$LOG_FILE")
- Manifest: $(basename "$SELECTED_MANIFEST")
- This summary: $(basename "$SUMMARY_FILE")

Selected Genome Directories ($NUM_DIRS total):
EOF

    for dir in "${GENOME_DIRS[@]}"; do
        echo "- $dir" >> "$SUMMARY_FILE"
    done

    print_color "32" "Simulation complete! Summary saved to: $SUMMARY_FILE"
}

# Run main function
main "$@"
