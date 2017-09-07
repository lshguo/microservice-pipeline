#!/bin/bash

#
# 需要一个参数：项目名称
#

set -e

if [ "$#" -ne 1 ];then
	echo "this script is for Test Department."
	echo "you have to enter name of the project where you wanna create bps pipeline"
	exit 1
fi

echo "pipeline template will be created in project $1" 

#pipeline name 创建流水线的名字
export NAME="bps"

# spring boot jar file url ，springboot的jar存放位置
export JAR_URL="http://10.10.0.205/bps-1.0.0-SNAPSHOT.jar"

# pod port，springboot的服务内部端口号
export PORT="5002"

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
      from $NAMESPACE/centos-java:8
      RUN wget -O /app.jar $JAR_URL
      RUN sh -c 'touch /app.jar'
      ENTRYPOINT ["java","-Djava.security.egd=file:/dev/./urandom","-Xmx2048m","-Xms2048m","-XX:MetaspaceSize=256m","-XX:MaxMetaspaceSize=512m","-Dspring.profiles.active=qyos-test-local","-Deureka.client.serviceUrl.defaultZone=\${eurekaurl}","-jar","/app.jar"]
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
        - name: eurekaurl
          value: $EUREKA_URL
        resources: {}
        terminationMessagePath: /dev/termination-log
      dnsPolicy: ClusterFirst
      restartPolicy: Always
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
