
# ---------------------------------------
# Install Development Tools (Section 4.1)
# ---------------------------------------
yum -y install ohpc-autotools
yum -y install EasyBuild-ohpc
yum -y install hwloc-ohpc
yum -y install spack-ohpc
yum -y install valgrind-ohpc

# -------------------------------
# Install Compilers (Section 4.2)
# -------------------------------
yum -y install gnu12-compilers-ohpc

# --------------------------------
# Install MPI Stacks (Section 4.3)
# --------------------------------
if [[ ${enable_mpi_defaults} -eq 1 ]];then
     yum -y install openmpi4-pmix-gnu12-ohpc mpich-ofi-gnu12-ohpc
fi

# ---------------------------------------
# Install Performance Tools (Section 4.4)
# ---------------------------------------
yum -y install ohpc-gnu12-perf-tools

yum -y install lmod-defaults-gnu12-openmpi4-ohpc

# ---------------------------------------------------
# Install 3rd Party Libraries and Tools (Section 4.6)
# ---------------------------------------------------
yum -y install ohpc-gnu12-serial-libs
yum -y install ohpc-gnu12-io-libs
yum -y install ohpc-gnu12-python-libs
yum -y install ohpc-gnu12-runtimes

if [[ ${enable_mpi_defaults} -eq 1 ]];then
     yum -y install ohpc-gnu12-mpich-parallel-libs
     yum -y install ohpc-gnu12-openmpi4-parallel-libs
fi

# ----------------------------------------
# Install Intel oneAPI tools (Section 4.7)
# ----------------------------------------
if [[ ${enable_intel_packages} -eq 1 ]];then
     yum -y install intel-oneapi-toolkit-release-ohpc
     rpm --import https://yum.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB
     yum -y install intel-compilers-devel-ohpc
     yum -y install intel-mpi-devel-ohpc
     yum -y install openmpi4-pmix-intel-ohpc
     yum -y install ohpc-intel-serial-libs
     yum -y install ohpc-intel-geopm
     yum -y install ohpc-intel-io-libs
     yum -y install ohpc-intel-perf-tools
     yum -y install ohpc-intel-python3-libs
     yum -y install ohpc-intel-mpich-parallel-libs
     yum -y install ohpc-intel-mvapich2-parallel-libs
     yum -y install ohpc-intel-openmpi4-parallel-libs
     yum -y install ohpc-intel-impi-parallel-libs
fi

# ------------------------------------
# Resource Manager Startup (Section 5)
# ------------------------------------
systemctl enable munge
systemctl enable slurmctld
systemctl start munge
systemctl start slurmctld

for i in "${!cpu_names[@]}"; do
     pdsh -w ${cpu_names[$i]} systemctl start munge
     pdsh -w ${cpu_names[$i]} systemctl start slurmd
     pdsh -w ${cpu_names[$i]} "usr/sbin/nhc-genconf -H '*' -c -" | dshbak -c
done

for i in "${!gpu_names[@]}"; do
     pdsh -w ${gpu_names[$i]} systemctl start munge
     pdsh -w ${gpu_names[$i]} systemctl start slurmd
     pdsh -w ${gpu_names[$i]} "usr/sbin/nhc-genconf -H '*' -c -" | dshbak -c
done

useradd -m test
wwsh file resync passwd shadow group
sleep 2

for i in "${!cpu_names[@]}"; do
     pdsh -w ${cpu_names[$i]} /warewulf/bin/wwgetfiles
done

for i in "${!gpu_names[@]}"; do
     pdsh -w ${gpu_names[$i]} /warewulf/bin/wwgetfiles
done