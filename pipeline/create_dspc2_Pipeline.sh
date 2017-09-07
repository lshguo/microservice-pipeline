#!/bin/bash

#
# 需要一个参数：项目名称
#

set -e

if [ "$#" -ne 1 ];then
	echo "this script is for Test Department."
	echo "you have to enter name of the project where you wanna create pipeline"
	exit 1
fi

echo "pipeline template will be created in project $1" 

#pipeline name 创建流水线的名字
export NAME="dspc2"

# spring boot jar file url ，springboot的jar存放位置
export JAR_URL="http://10.10.0.205/dspc2-1.0.0-SNAPSHOT.jar"

# pod port，springboot的服务内部端口号
export PORT="5004"

# oc cmd，不要修改此环境变量
export CMD="cat /var/run/secrets/kubernetes.io/serviceaccount/token"

# namespace ，选择的项目名称
export NAMESPACE="$1"

# domain，
export DOMAIN="picc.yun"

mkdir -p /tmp/$NAMESPACE/$NAME/

ocuser=`oc whoami`
oc login -u admin -p admin
oc tag cicd/centos-java:8 $NAMESPACE/$NAME:latest
oc tag cicd/centos-java:8 $NAMESPACE/centos-java:8
oc login -u "$ocuser" -p "$ocuser" >/dev/null

cat <<EOF >/tmp/$NAMESPACE/$NAME/bc.yaml
apiVersion: v1
kind: BuildConfig
metadata:
  name: $NAME
  namespace: $NAMESPACE
spec:
  postCommit: {}
  resources: {}
  runPolicy: Serial
  source:
    dockerfile: |-
      from cicd/centos-java:8
      RUN wget -O /app.jar $JAR_URL
      RUN sh -c 'touch /app.jar'
      ENTRYPOINT ["java","-Djava.security.egd=file:/dev/./urandom","-Xmx1536m","-Xms1536m","-XX:MetaspaceSize=512m","-XX:MaxMetaspaceSize=512m","-Xss256k","-XX:NewRatio=2","-XX:SurvivorRatio=8","-XX:LargePageSizeInBytes=128m","-XX:+UseFastAccessorMethods","-XX:+OptimizeStringConcat","-XX:+DisableExplicitGC","-XX:+HeapDumpOnOutOfMemoryError","-XX:+UseG1GC","-XX:ParallelGCThreads=8","-Dspring.profiles.active=qyos-test-local","-Deureka.client.serviceUrl.defaultZone=\${eurekaurl}","-jar","/app.jar"]
    type: Dockerfile
  strategy:
    dockerStrategy:
      from:
        kind: ImageStreamTag
        name: centos-java:8
        namespace: $NAMESPACE
      noCache: true
    type: Docker
  output:
    to:
      kind: ImageStreamTag
      namespace: $NAMESPACE
      name: '$NAME:latest'
  triggers: []
status:
  lastVersion: 0
EOF

EUREKA_URL="http://eureka-""$NAMESPACE"".picc.yun/eureka"
cat <<EOF >/tmp/$NAMESPACE/$NAME/dc.yaml
apiVersion: v1
kind: DeploymentConfig
metadata:
  annotations:
    openshift.io/generated-by: OpenShiftWebConsole
  labels:
    app: $NAME
  name: $NAME
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    app: $NAME
    deploymentconfig: $NAME
  strategy:
    resources: {}
    rollingParams:
      intervalSeconds: 1
      maxSurge: 25%
      maxUnavailable: 25%
      timeoutSeconds: 600
      updatePeriodSeconds: 1
    type: Rolling
  template:
    metadata:
      annotations:
        openshift.io/generated-by: OpenShiftWebConsole
      creationTimestamp: null
      labels:
        app: $NAME
        deploymentconfig: $NAME
    spec:
      containers:
      - image: ' '
        imagePullPolicy: Always
        name: $NAME
        ports:
        - containerPort: $PORT
        env:
        - name: eureka_instance_preferIpAddress
          value: 'true'
        - name: server_port
          value: '$PORT'
        - name: endpoints_shutdown_enabled
          value: "true"
        - name: endpoints_shutdown_sensitive
          value: "false"
        - name: eurekaurl
          value: $EUREKA_URL
        lifecycle:
          preStop:
            exec:
              command:
              - /bin/bash
              - -c
              - export IP=\`ifconfig eth0|grep inet|grep -v 127.0.0.1|grep -v inet6|awk
                '{print \$2}'|tr -d "addr:"\`;while [[ "200" -ne \`curl -o /dev/null
                -s -w %{http_code} -X PUT http://peer2.$NAMESPACE.svc.cluster.local/eureka/apps/DSPA2/\$IP:5001/status?value=OUT_OF_SERVICE\`
                ]]; do  sleep 10; done && export IP=\`ifconfig eth0|grep inet|grep
                -v 127.0.0.1|grep -v inet6|awk '{print \$2}'|tr -d "addr:"\`;while [[
                "200" -ne \`curl -o /dev/null -s -w %{http_code} -X PUT http://peer3.$NAMESPACE.svc.cluster.local/eureka/apps/DSPA2/\$IP:5001/status?value=OUT_OF_SERVICE\`
                ]]; do  sleep 10; done && export IP=\`ifconfig eth0|grep inet|grep
                -v 127.0.0.1|grep -v inet6|awk '{print \$2}'|tr -d "addr:"\`;while [[
                "200" -ne \`curl -o /dev/null -s -w %{http_code} -X PUT http://peer4.$NAMESPACE.svc.cluster.local/eureka/apps/DSPA2/\$IP:5001/status?value=OUT_OF_SERVICE\`
                ]]; do  sleep 10; done && export IP=\`ifconfig eth0|grep inet|grep
                -v 127.0.0.1|grep -v inet6|awk '{print \$2}'|tr -d "addr:"\`;sleep 95;curl
                -X POST \$IP:5001/shutdown;sleep 95; curl  -X DELETE http://peer2.$NAMESPACE.svc.cluster.local/eureka/apps/DSPA2/\$IP:5001;curl  -X
                DELETE http://peer3.$NAMESPACE.svc.cluster.local/eureka/apps/DSPA2/\$IP:5001;curl  -X
                DELETE http://peer4.$NAMESPACE.svc.cluster.local/eureka/apps/DSPA2/\$IP:5001;sleep
                95
        resources: 
          requests:
            cpu: "1"
            memory: 1Gi
        ports:
        - containerPort: $PORT
          hostPort: $PORT
          protocol: TCP
        readinessProbe:
          failureThreshold: 3
          initialDelaySeconds: 30
          periodSeconds: 10
          successThreshold: 1
          tcpSocket:
            port: $PORT
          timeoutSeconds: 3
        terminationMessagePath: /dev/termination-log
        volumeMounts:
        - mountPath: /etc/localtime
          name: time
          readOnly: true
        - mountPath: /home
          name: log
      dnsPolicy: ClusterFirst
      nodeSelector:
        app2: dsp2
      restartPolicy: Always
      volumes:
      - hostPath:
          path: /etc/localtime
        name: time
      - hostPath:
          path: /var/log/logstash
        name: log
      securityContext: {}
      terminationGracePeriodSeconds: 30
  test: false
  triggers:
  - type: ConfigChange
  - imageChangeParams:
      automatic: true
      containerNames:
      - $NAME
      from:
        kind: ImageStreamTag
        name: $NAME:latest
        namespace: $NAMESPACE
    type: ImageChange
status:
  availableReplicas: 1
  details:
    causes:
    - imageTrigger:
        from:
          kind: ImageStreamTag
          name: $NAME:latest
          namespace: $NAMESPACE
      type: ImageChange
    message: caused by an image change
  latestVersion: 1
  observedGeneration: 2
  replicas: 1
  updatedReplicas: 1
EOF
echo "1"
cat <<EOF >/tmp/$NAMESPACE/$NAME/pipeline.yaml
apiVersion: v1
kind: BuildConfig
metadata:
  labels:
    app: $NAME-pipeline
    name: $NAME-pipeline
  name: $NAME-pipeline
  namespace: $NAMESPACE
spec:
  nodeSelector: null
  output: {}
  postCommit: {}
  resources: {}
  runPolicy: Serial
  source:
    type: None
  strategy:
    jenkinsPipelineStrategy:
      jenkinsfile: "node('maven') {\n   // define commands\n   def ocCmd = \"oc --token=\`cat
        /var/run/secrets/kubernetes.io/serviceaccount/token\` --server=https://openshift.default.svc.cluster.local
        --certificate-authority=/run/secrets/kubernetes.io/serviceaccount/ca.crt\"\n
        \  \n   stage '启动构建'\n   sh \"export oldBc=\`oc get bc $NAME -n $NAMESPACE -o wide|awk
        '{print \\\\\$4}'|awk 'NR==2'\`; \${ocCmd} start-build $NAME -n $NAMESPACE; until [ \`oc
        get bc $NAME -n $NAMESPACE -o wide|awk '{print \\\\\$4}'|awk 'NR==2'\` -eq \\\\\$[\\\\\$oldBc+1]
        ]; do sleep 5 ; echo 'start build ......' ; done\"\n   \n   stage '构建中......'\n
        \  sh \"export newBc=\`oc get bc $NAME -n $NAMESPACE -o wide|awk '{print \\\\\$4}'|awk
        'NR==2'\`; until [ \`oc get build $NAME-\\\\\$newBc -n $NAMESPACE -o wide|awk '{print \\\\\$4}'|awk
        'NR==2'\` = Complete ]; do sleep 5 ; echo 'waiting build ......' ; done\"\n
        \  \n   stage '构建成功'\n   echo \"build success !!!\"\n   \n   stage '启动部署'\n
        \  sh \"oc rollout latest dc $NAME -n $NAMESPACE\"\n   \n   stage '部署中......'\n   sh
        \"export newDc=\`oc get dc $NAME -n $NAMESPACE|awk '{print \\\\\$2}'|awk 'NR==2'\`; until
        [ \`oc get rc $NAME-\\\\\$newDc -n $NAMESPACE |awk '{print \\\\\$3}'|awk 'NR==2'\` = \`oc get
        dc $NAME -n $NAMESPACE -o wide|awk '{print \\\\\$4}'|awk 'NR==2'\` ]; do sleep 5 ; echo
        'waiting deploy ......' ; done\"\n   \n   stage '部署完成'\n   echo \"deploy complete\"\n
        \  \n   \n   \n}"
    type: JenkinsPipeline
  triggers: []
status:
  lastVersion: 0
EOF
echo "2"
cat <<EOF >/tmp/$NAMESPACE/$NAME/svc.yaml
apiVersion: v1
kind: Service
metadata:
  name: $NAME
  labels:
    app: $NAME
spec:
  ports:
    - port: 80
      name: $NAME
  selector:
    app: $NAME
    deploymentconfig: $NAME
EOF
echo "3"
cat <<EOF >/tmp/$NAMESPACE/$NAME/route.yaml
apiVersion: v1
kind: Route
metadata:
  name: $NAME
  labels:
    app: $NAME
spec:
  to:
    kind: Service
    name: $NAME
EOF


oc create -f /tmp/$NAMESPACE/$NAME -n $NAMESPACE

oc start-build $NAME -n $NAMESPACE
