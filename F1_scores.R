# Custom function to calculate performance metrics                                                      
calculate_metrics <- function(total_strains, identified_strains, correct_identifications) {
  TP <- correct_identifications
  FP <- identified_strains - correct_identifications
  FN <- total_strains - correct_identifications
  
  precision <- TP / (TP + FP)
  recall <- TP / (TP + FN)
  f1_score <- 2 * (precision * recall) / (precision + recall)
  
  return(list(TP = TP, FP = FP, FN = FN, Precision = precision, Recall = recall, F1_Score = f1_score))
}

# Example usage with Tool1 data1:
#total_strains <- 10                                                                                     
#identified_strains_tool <- 10
#correct_identifications_tool <- 8
#metrics_tool <- calculate_metrics(total_strains, identified_strains_tool, correct_identifications_tool)
#print(metrics_tool)
