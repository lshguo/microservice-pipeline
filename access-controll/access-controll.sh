#! /bin/bash

#
#  需要输入项目名称
#

if [ "$#" -ne 1 ];then
	echo "need project name"
	exit 1
fi

NAMESPACE="$1"

user=`oc whoami`
if [ "$user" != "admin" ];then
	echo "access controll need admin user"
	exit 1
fi

oc adm policy add-scc-to-group privileged system:authenticated
#oc adm policy add-scc-to-user  privileged  system:serviceaccount:"$NAMESPACE":default
oc adm policy add-scc-to-user  privileged -z "$NAMESPACE" 
 
