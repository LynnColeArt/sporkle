#!/bin/bash
# Script to debug PM4 submission with UMR monitoring

echo "=== PRE-SUBMISSION STATE ==="
echo "Checking initial wave status..."
umr -i 1 --waves | tee pre_waves.log

echo -e "\nChecking initial HQD state..."
umr -i 1 --read mmCP_HQD_ACTIVE | tee -a pre_hqd.log
umr -i 1 --read mmCP_HQD_PQ_WPTR_POLL_ADDR | tee -a pre_hqd.log
umr -i 1 --read mmCP_HQD_PQ_DOORBELL_CONTROL | tee -a pre_hqd.log

echo -e "\n=== RUNNING PM4 TEST ==="
./test_pm4_mini_final

echo -e "\n=== POST-SUBMISSION STATE ==="
echo "Checking wave status after submission..."
umr -i 1 --waves | tee post_waves.log

echo -e "\nChecking HQD state after submission..."
umr -i 1 --read mmCP_HQD_ACTIVE | tee -a post_hqd.log
umr -i 1 --read mmCP_HQD_PQ_WPTR_POLL_ADDR | tee -a post_hqd.log
umr -i 1 --read mmCP_HQD_PQ_DOORBELL_CONTROL | tee -a post_hqd.log

echo -e "\n=== Checking for any compute activity ==="
umr -i 1 --ring-read compute_0.0.0 | head -20

echo -e "\n=== Checking shader program registers ==="
umr -i 1 --read mmCOMPUTE_PGM_LO
umr -i 1 --read mmCOMPUTE_PGM_HI
umr -i 1 --read mmCOMPUTE_PGM_RSRC1
umr -i 1 --read mmCOMPUTE_PGM_RSRC2

echo -e "\n=== Wave diff ==="
diff pre_waves.log post_waves.log || echo "No wave changes detected"