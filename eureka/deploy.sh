#! /bin/bash

if [ "$#" -ne 1 ];then
	echo "project name is needed"
	exit 1
fi

project="$1"
echo "create eureka  in project $project"

manifest=eureka-"$project"-deploy.manifest
echo "" > $manifest

yamlCount=`ls -l *yaml |wc -l`
if [ "$yamlCount" -ne 7 ];then
	echo "ERROR: there should be 7 yaml files in this directory"
	exit 2
fi

for yaml in `ls *yaml`;
do
	sed "s/PROJECT/$project/g" $yaml >> $manifest	
	echo "---" >>$manifest
done
echo "eureka deploy manifest is placed in $manifest"

oc login -u admin -p admin >/dev/null
if [ "$?" -ne 0 ];then
	echo "Openshift Login Failed!"
	exit 3
fi
echo "Openshift Login Success"

oc get project $project >/dev/null
if [ "$?" -ne 0 ];then
        echo "oc failed to get project $project"
        exit 3
fi

oc tag default/eureka:latest $project/eureka:latest
if [ "$?" -ne 0 ];then
	echo "Failed to tag cicd/eureka:latest $project/eureka:latest"
	exit 4
fi
echo "success to tag cicd/eureka:latest $project/eureka:latest"

oc create -f $manifest -n $project
if [ "$?" -ne 0 ];then
	echo "Failed to create $manifest"
	exit 5
fi

echo "success to create $manifest"
echo "Rc"
oc get rc -n $project
echo "Pod"
oc get pod -n $project
echo "Service"
oc get svc -n $project
echo "Route"
oc get route -n $project

