# Benchmarking of reference-based tools for strain level identification of plant microbiome

Our study focused on a comprehensive benchmarking of reference-based tools for strain level resolution of bacteria from plant metagenome data.

The benchmarking of tools was performed on several datasets including simulated metagenomes of varying strain diversity, short read real metagenomes (inoculated and non-inoculated), and long read real metagenome data.

The findings revealed that few tools are good for targeted strain identification, however, as strain complexity increased, tools became computationally expensive and took much longer time to process the data.

<img width="7800" height="4388" alt="Image" src="https://github.com/user-attachments/assets/d73e9842-a354-45d9-9edf-638ed2689726" />


## System requirements

- **Operating System**: Linux (Ubuntu/Debian, CentOS/RHEL)
- **Memory**: Minimum 16GB RAM (32GB+ recommended for large datasets)
- **Storage**: Sufficient space for databases and output files

## Common dependencies

```
conda (https://docs.conda.io/projects/conda/en/latest/user-guide/install/linux.html)
ncbi-genome-download (https://github.com/kblin/ncbi-genome-download)
InSilicoSeq (https://insilicoseq.readthedocs.io/en/latest/)
```


## For downloading the bacterial sequences, we can use ncbi-genome-download:
```
ncbi-genome-download -T #species-taxids  bacteria -F fasta,assembly-report -s genbank -p 20
## Here 'species-taxids' you need to provide species taxomony id of the species whose genome you want to download

##   Species                       taxids
##   Dyella japonica               1440762
##   Azospirillum humicireducens   1226968
##   Agrobacterium tumefaciens     358
##   Agrobacterium radiobacter     362
##   Erwinia amylovora             552
##   Ensifer medicae               110321
##   Ensifer meliloti              382
##   Pseudomonas fluorescens       294
##   Pseudomonas syringae          317
##   Xanthomonas campestris        359385
##   Xanthomonas oryzae            129394
##   Xylella fastidiosa            2371

```


## For simulating datasets by giving the number of strains of which you want to generate datasets and at which sequencing depth:

```
bash Simulation_of_metagenomic_data.sh genome_directories.txt /path/to/output number_of_strains sequencing_depth

## genome_directories.txt file contains full path to bacterial genomes where genomes in fasta file would be available:
##/full_path/E.meliloti
##/full_path/A.humicireducens

```


## Tools installation and processing:

##### StrainScan
Install StrainScan using conda
`conda install -c bioconda strainscan bowtie2 samtools`

###### Database customization:
`python StrainScan_build.py -i Bacterial_genomes_directory -o bacterial_database`

###### Processing of data:
```
# Run the script with the database list file
bash StrainScan.sh /path/to/fastq_files /path/to/processing.log list.txt

# where list.txt contains database full path like this:
#/full_path/E.meliloti
#/full_path/A.humicireducens 

# provide full path to processing.log where you want to store tool's running details
```


##### StrainGE
Install StrainGE using conda
```
conda create -n strainge python=3
source activate strainge
conda config --add channels bioconda
conda config --add channels conda-forge
conda install strainge
```

###### Additional dependencies required to install (hdf5 library):
```
sudo apt-get install -y libhdf5-dev  # Ubuntu/Debian
# or
sudo yum install -y hdf5-devel       # RHEL/CentOS
```

###### Database customization:
```
python3 prepare_strainge_db.py /home/user/StrainGE/bin/bacteria/ -o bacteria_db   ##### bacteria folder should contain assembly report file too in .txt extension along with genomes in .fa extension

bash -c 'for f in bacteria_db/*.fa.gz; do straingst kmerize -o ${f%.fa.gz}.hdf5 $f; done;'

straingst kmersim --all-vs-all -t 20 -S jaccard -S subset bacteria_db/*.hdf5 > bacteria_similarities.tsv

straingst cluster -i  bacteria_similarities.tsv -d -C 0.99 -c 0.90 --clusters-out bacteria_clusters.tsv bacteria_db/*.hdf5 > bacteria_references_to_keep.txt

straingst createdb -f bacteria_references_to_keep.txt -o bacteria_pan-genome-db.hdf5
```

###### Processing of data:
```
# Run the script with the database list file
bash StrainGE.sh /path/to/fastq_files /path/to/processing.log list.txt

# where list.txt contains database full path like this:
#/full_path/E.meliloti
#/full_path/A.humicireducens

# provide full path to processing.log where you want to store tool's running details
```


##### MIDAS2
Install MIDAS2 using conda
```
conda create -n midas2 python=3.9
conda activate midas2
conda install -c bioconda midas2
```

###### Database download
```
midas2 database \
  --download \
  --midasdb_name gtdb \
  --midasdb_dir my_midasdb_gtdb \
  --species all
```

###### Processing of data:
```
# Run the script with the database list file
bash MIDAS2.sh /path/to/fastq_files /path/to/processing.log /path/to/midas_db /path/to/output

# provide full path to processing.log where you want to store tool's running details
```


##### Metalign
Install Metalign using conda
`conda install -c conda-forge -c bioconda Metalign`

###### Database download
```
git clone https://github.com/nlapier2/Metalign.git
cd Metalign
./setup_data.sh
```

###### Processing of data:
```
# Run the script with the database list file
bash Metalign.sh /path/to/fastq_files /path/to/processing.log /path/to/metalign_data /path/to/output

# provide full path to processing.log where you want to store tool's running details
```

##### KrakenUniq
Install KrakenUniq using conda
`conda install -c bioconda krakenuniq`

###### Database customization
```
krakenuniq-download --db DBDIR --threads 20  'genbank/bacteria/Any/species_taxid=#bacterial_species_taxonomy_id'         

#### Here '#bacterial_species_taxonomy_id' you need to give taxonomy id of bacterial species whose all genomes you want to download

krakenuniq-build --db DBDIR --kmer-len 31 --threads 20 --taxids-for-genomes --taxids-for-sequences
```

###### Processing of data:
```
# Run the script with the database list file
bash KrakenUniq.sh /path/to/fastq_files /path/to/processing.log list.txt /path/to/output

# where list.txt contains database full path like this:
#A.tumefaciens:/path/to/A.tumefaciens_DBDIR
#E.amylovora:/path/to/E.amylovora_DBDIR 

# provide full path to processing.log where you want to store tool's running details
```


##### PStrain
Install PStrain using conda
```
git clone https://github.com/wshuai294/PStrain.git --depth 1
cd PStrain/
conda env create --name pstrain -f pstrain_metaphlan4_env.yml
conda activate pstrain
```

###### Database download
`bash scripts/collect_metaphlan_datbase.sh -x mpa_vOct22_CHOCOPhlAnSGB_202403 -m 4 -d ./`

###### Processing of data:
```
# Run the script with the database list file
bash PStrain.sh /path/to/configs /path/to/processing.log /path/to/PStrain.py /path/to/bowtie2db index_name /path/to/output

# provide full path to processing.log where you want to store tool's running details
# provide full path to configs where config.txt should be available and it contains path to fastq files like this:
#cat config.txt
#//
#sample : read1
#fq1 : /full_path/read1_R1.fastq.gz
#fq2 : /full_path/read1_R2.fastq.gz
#//
#sample : read2
#fq1 : /full_path/read2_R1.fastq.gz
#fq2 : /full_path/read2_R2.fastq.gz

```


##### StrainEst
Install StrainEst using conda
```
conda create -n strainest python=2.7
conda install 'Click>=5.1' 'pandas' 'pysam>=0.12' 'scikit-learn>=0.16.1,<0.20' 'biopython>=1.50'
wget https://github.com/compmetagen/strainest/archive/refs/tags/1.2.4.tar.gz
tar -zxvf strainest-1.2.4.tar.gz
cd strainest-1.2.4
sudo python setup.py install 
```

###### Database customization
```

strainest mapgenomes *.fna bacterial_species_reference_genome.fna mapped.fna
strainest map2snp reference_genome.fna mapped.fna snp.dgrp
bowtie2-build mapped.fna mapped --threads 20
```

###### Processing of data:
```
bash StrainEst.sh /path/to/fastq_files /path/to/processing.log list.txt /path/to/reference /path/to/output

# where list.txt contains database full path like this:
#/full_path/E.meliloti
#/full_path/A.humicireducens 

# provide full path to processing.log where you want to store tool's running details
# "Path to reference" provides path to bowtie2 indexes and SNP files
```


## For calculating F1 scores:

```
Rscript F1_scores.R #Total strains #Identified strains #Correct identifications
```
Example usage
```
Rscript F1_scores.R 18 10 8
```
It will give output like this
```
Performance Metrics:
=====================
Total strains            : 18
Identified strains       : 10
Correct identifications  : 8
True Positives (TP)      : 8
False Positives (FP)     : 2
False Negatives (FN)     : 10
Precision                : 0.8000
Recall                   : 0.4444
F1 Score                 : 0.5714
```

