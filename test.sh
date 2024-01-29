#!/bin/bash

. input.local

write_hostgroup() {
    echo "define hostgroup {" >> $compute_file
    echo "    hostgroup_name $1" >> $compute_file
    echo "    alias $2" >> $compute_file
    echo -n "    members " >> $compute_file
    for ((i=0; i<${#cpu_name[@]}; i++)); do
        echo -n "${cpu_prefix}$((i+1))" >> $compute_file
        [ $i -lt $(( ${#cpu_name[@]} - 1 )) ] && echo -n "," >> $compute_file
    done
    echo >> $compute_file
    echo "}" >> $compute_file
    echo >> $compute_file
}

write_host() {
    echo "define host {" >> $compute_file
    echo "    use linux-server" >> $compute_file
    echo "    host_name $1" >> $compute_file
    echo "}" >> $compute_file
    echo >> $compute_file
}

compute_file="compute.cfg"

rm -f $compute_file

echo "define service {" >> compute.cfg
echo "    use                     generic-service" >> compute.cfg
echo "    hostgroup_name          cpu,gpu" >> compute.cfg
echo "    service_description     SSH Monitoring" >> compute.cfg
echo "    check_command           check_ssh" >> compute.cfg
echo "}" >> compute.cfg
echo >> compute.cfg


write_hostgroup "cpu" "CPU Nodes"

write_hostgroup "gpu" "GPU Nodes"

for ((i=0; i<${#cpu_name[@]}; i++)); do
    write_host "${cpu_prefix}$((i+1))"
done

for ((i=0; i<${#cpu_name[@]}; i++)); do
    write_host "${gpu_prefix}$((i+1))"
done


