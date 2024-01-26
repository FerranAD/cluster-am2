for i in "${!gpu_names[@]}"; do
    if [[ ${enable_kargs} -eq 1 ]]; then
        pdsh -w "${gpu_names[$i]}" uptime
    fi
done

for i in "${!cpu_names[@]}"; do
    if [[ ${enable_kargs} -eq 1 ]]; then
        pdsh -w "${cpu_names[$i]}" uptime
    fi
done