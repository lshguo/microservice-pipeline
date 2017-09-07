#! /bin/bash

#
#  需要输入项目名称
#

if [ "$#" -ne 1 ];then
	echo "need project name"
	exit 1
fi

NAMESPACE="$1"

 
