# Benchmarking of reference-based tools for strain level identification of plant microbiome

Our study focused on a comprehensive benchmarking of reference-based tools for strain level resolution of bacteria from plant metagenome data.

The benchmarking of tools was performed on several datasets including simulated metagenomes of varying strain diversity, short read real metagenomes (inoculated and non-inoculated), and long read real metagenome data.

The findings revealed that few tools are good for targeted strain identification, however, as strain complexity increased, tools became computationally expensive and took much longer time to process the data.

<img width="7800" height="4388" alt="Image" src="https://github.com/user-attachments/assets/d73e9842-a354-45d9-9edf-638ed2689726" />


## System requirements

- **Operating System**: Linux (Ubuntu/Debian, CentOS/RHEL)
- **Memory**: Minimum 16GB RAM (32GB+ recommended for large datasets)
- **Storage**: Sufficient space for databases and output files

## Python Dependencies (Common)

```
pip3 install biopython==1.81
pip3 install click==8.1.7
pip3 install Jinja2==3.1.2
pip3 install matplotlib==3.8.2
pip3 install numpy==1.26.2
pip3 install pandas==2.1.3
pip3 install PyYAML==6.0.1
pip3 install requests==2.31.0
pip3 install rich==13.7.0
pip3 install seaborn==0.13.0
pip3 install scikit-learn==1.3.2
pip3 install snakemake==7.32.4
pip3 install pulp==2.7.0
pip3 install h5py==3.10.0
pip3 install tables==3.8.0
```

## Tool Installation:

##### StrainScan
Install StrainScan using conda
`conda install -c bioconda strainscan`

###### Additional dependencies required to install:
1. Bowtie2
2. Samtools


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


##### MIDAS2
Install MIDAS2 using conda
```
conda create -n midas2 python=3.9
conda activate midas2
conda install -c bioconda midas2
```


##### Metalign
Install Metalign using conda
`conda install -c conda-forge -c bioconda Metalign`


##### KrakenUniq
Install KrakenUniq using conda
`conda install -c bioconda krakenuniq`


##### PStrain
Install PStrain using conda
```
git clone https://github.com/wshuai294/PStrain.git --depth 1
cd PStrain/
conda env create --name pstrain -f pstrain_metaphlan4_env.yml
conda activate pstrain
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

