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

