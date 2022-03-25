#!/bin/bash

release_name="$1"
job_name="gadgtron-test-$RANDOM"

cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${job_name}
spec:
  backoffLimit: 0
  template:
    spec:
      containers:
      - name: gt-test
        image: ghcr.io/gadgetron/gadgetron/gadgetron_ubuntu_rt_cuda:latest
        command: [ "/bin/bash", "-c", "/opt/scripts/gadgetron_test.sh" ]
        volumeMounts:
        - name: script-volume
          mountPath: /opt/scripts
      restartPolicy: Never
      volumes:
      - name: script-volume
        configMap:
          name: gadgetron-test-scripts
          defaultMode: 0777
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: gadgetron-test-scripts
data:
  gadgetron_test.sh: |
    #!/bin/bash

    set -eo pipefail

    # enable conda for this shell
    . /opt/conda/etc/profile.d/conda.sh
    conda activate gadgetron

    cd /opt/integration-test
    python get_data.py
    python ./run_gadgetron_test.py -e -a ${release_name}-gadgetron -p 9002 cases/generic_grappa_snr_R1_PEFOV100_PERes100.cfg
EOF

for wait in {0..20}; do
    if [[ "$(kubectl get job "$job_name" -o jsonpath={.status.active})" == "1" ]]; then
        echo "Waiting for end to end test to finish"
        sleep 30
    else
        break
    fi
done

if [[ "$(kubectl get job "$job_name" -o jsonpath={.status.succeeded})" == "1" ]]; then
    echo "End to end test pass"
else
    echo "End to end test failed"
    kubectl logs "job.batch/${job_name}"
    exit 1 
fi  

# Checking the number of replicas, which should have increased:
if [[ "$(kubectl get deployment ${release_name}-gadgetron -o jsonpath={.spec.replicas})" -gt 1 ]]; then
    echo "Number of replicas has increased"
else
    echo "The number of replicas has not increased as expected"
    exit 1
fi