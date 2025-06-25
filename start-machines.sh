source input.local

# Start services in both CPU and GPU nodes
for i in "${!cpu_name[@]}"; do
    pdsh -w ${cpu_name[$i]} systemctl start munge
    pdsh -w ${cpu_name[$i]} systemctl start slurmd
    pdsh -w ${cpu_name[$i]} "/usr/sbin/nhc-genconf -H '*' -c -" | dshbak -c
done

for i in "${!gpu_name[@]}"; do
    pdsh -w ${gpu_name[$i]} systemctl start munge
    pdsh -w ${gpu_name[$i]} systemctl start slurmd
    pdsh -w ${gpu_name[$i]} "/usr/sbin/nhc-genconf -H '*' -c -" | dshbak -c
done

# Force file resync
for i in "${!cpu_name[@]}"; do
    pdsh -w ${cpu_name[$i]} /warewulf/bin/wwgetfiles
done

for i in "${!gpu_name[@]}"; do
    pdsh -w ${gpu_name[$i]} /warewulf/bin/wwgetfiles
done
