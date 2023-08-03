#!/bin/bash

start_load (){
    export POD_INDEX=$1
    export NODE_NAME=$2
    oc apply --dry-run=client -oyaml -f - <<-END
        apiVersion: v1
        kind: Pod
        metadata:
          name: background-load-$POD_INDEX
          namespace: load-aware
          labels:
            workload: make
            testContext: background
          annotations:
            alpha.image.policy.openshift.io/resolve-names: '*'
        spec:
          containers:
          - name: make-container
            image: load-aware/coreutils:deps
            imagePullPolicy: IfNotPresent
            command: ["/bin/sh"]
            args: ["-c", "for i in {1..999999}; do echo 'making' && make clean && make -j $POD_INDEX; done"]
            resources:
              requests:
                cpu: "100m"
          restartPolicy: Never
          nodeName: ${NODE_NAME}
END | oc apply -f -
}

i=1
for n in $(oc get nodes --no-headers -lonly-workload-pods=yes -o custom-columns=":metadata.name")
do
    start_load $i $n
    i=$(($i+1))
done
