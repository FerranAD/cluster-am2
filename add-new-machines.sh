source input.local
# Delete all lines starting with "NodeName=" in the slurm.conf file
sed -i '/^NodeName=/d' /etc/slurm/slurm.conf

# Stop service
systemctl stop slurmctld

# Add nodes to the slurm.conf file
# Warning. Careful if changing architecture!
for i in "${!cpu_name[@]}"; do
    echo "NodeName=${cpu_name[$i]} Sockets=2 CoresPerSocket=6 ThreadsPerCore=1 State=UNKNOWN" >> /etc/slurm/slurm.conf
done
for i in "${!gpu_name[@]}"; do
    echo "NodeName=${gpu_name[$i]} Sockets=1 CoresPerSocket=8 ThreadsPerCore=2 State=UNKNOWN" >> /etc/slurm/slurm.conf
done

for ((i=0; i<${#cpu_name[@]}; i++)); do
    wwsh -y node new "${cpu_name[$i]}" --ipaddr="${cpu_ip[$i]}" --hwaddr="${cpu_mac[$i]}" -D ${eth_provision}
    wwsh provision set --postnetdown=1 "${cpu_name[$i]}" -y
    wwsh provision set "${cpu_name[$i]}" --vnfs=rocky9.2 --bootstrap=`uname -r` --files=dynamic_hosts,passwd,group,shadow,munge.key,network -y
done

for ((i=0; i<${#gpu_name[@]}; i++)); do
    wwsh -y node new "${gpu_name[$i]}" --ipaddr="${gpu_ip[$i]}" --hwaddr="${gpu_mac[$i]}" -D ${eth_provision}
    wwsh provision set --postnetdown=1 "${gpu_name[$i]}" -y
    wwsh provision set "${gpu_name[$i]}" --vnfs=rocky9.2 --bootstrap=`uname -r` --files=dynamic_hosts,passwd,group,shadow,munge.key,network -y
done

wwsh pxe update

# Optionally, add arguments to bootstrap kernel
for i in "${!gpu_name[@]}"; do
    if [[ ${enable_kargs} -eq 1 ]]; then
        wwsh -y provision set "${gpu_name[$i]}" --kargs="${kargs}"
    fi
done

for i in "${!cpu_name[@]}"; do
    if [[ ${enable_kargs} -eq 1 ]]; then
        wwsh -y provision set "${cpu_name[$i]}" --kargs="${kargs}"
    fi
done
