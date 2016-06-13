#!/bin/bash

dir=$1
gender=$2
mkdir -p data/trials
cat $dir/utt2spk | awk '{print $1}' |  awk -F _ '{print $1}' | sort -u | while read line
do
   nn=`echo "$line"`
   cat $dir/utt2spk | awk '{print $1}' | sort -u | while read line
     do 
	   xx=`echo "$line" | awk -F _ '{print $1}'`
	   if [ $xx = $nn ];then
         echo $nn $line target >> data/trials/${gender}.trials
	   else 
	     echo $nn $line nontarget >> data/trials/${gender}.trials
	  fi
   done
done

