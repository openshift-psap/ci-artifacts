#! /bin/bash
echo "in create_pvc.sh!!!!!"
oc create -f "./nvidia-data-pvc.yaml"
# /workspace/download_dataset.sh "/storage"
echo "creating pvc!!!"
