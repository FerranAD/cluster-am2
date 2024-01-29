source input.local
for i in "${!gpu_name[@]}"; do
    if [[ ${enable_kargs} -eq 1 ]]; then
        pdsh -w "${gpu_name[$i]}" uptime
    fi
done

for i in "${!cpu_name[@]}"; do
    if [[ ${enable_kargs} -eq 1 ]]; then
        pdsh -w "${cpu_name[$i]}" uptime
    fi
done
