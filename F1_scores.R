#!/usr/bin/env Rscript

# Custom function to calculate performance metrics
calculate_metrics <- function(total_strains, identified_strains, correct_identifications) {
  TP <- correct_identifications
  FP <- identified_strains - correct_identifications
  FN <- total_strains - correct_identifications
  
  precision <- TP / (TP + FP)
  recall <- TP / (TP + FN)
  f1_score <- 2 * (precision * recall) / (precision + recall)
  
  return(list(TP = TP, FP = FP, FN = FN,
              Precision = precision, Recall = recall, F1_Score = f1_score))
}

# Get command-line arguments (skip script name)
args <- commandArgs(trailingOnly = TRUE)

# Check that exactly three arguments are provided
if (length(args) != 3) {
  stop("Usage: Rscript F1_scores.R total_strains identified_strains correct_identifications")
}

# Convert arguments to numeric
total_strains <- as.numeric(args[1])
identified_strains <- as.numeric(args[2])
correct_identifications <- as.numeric(args[3])

# Check for NA (non-numeric input)
if (any(is.na(c(total_strains, identified_strains, correct_identifications)))) {
  stop("All arguments must be numeric.")
}

# Calculate metrics
metrics <- calculate_metrics(total_strains, identified_strains, correct_identifications)

# Print results (formatted nicely)
cat("\nPerformance Metrics:\n")
cat("=====================\n")
cat(sprintf("Total strains            : %d\n", total_strains))
cat(sprintf("Identified strains       : %d\n", identified_strains))
cat(sprintf("Correct identifications  : %d\n", correct_identifications))
cat(sprintf("True Positives (TP)      : %d\n", metrics$TP))
cat(sprintf("False Positives (FP)     : %d\n", metrics$FP))
cat(sprintf("False Negatives (FN)     : %d\n", metrics$FN))
cat(sprintf("Precision                : %.4f\n", metrics$Precision))
cat(sprintf("Recall                   : %.4f\n", metrics$Recall))
cat(sprintf("F1 Score                 : %.4f\n", metrics$F1_Score))
cat("\n")
