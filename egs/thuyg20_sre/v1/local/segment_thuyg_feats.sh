#!/bin/bash
#Copyright 2016  Tsinghua University (Author: Dong Wang, Xuewei Zhang).  Apache 2.0.

#Thuyg20 releses 30s enrollment data. 
#This script produces 10s/20s enrollment feats as the training data of ivector system.


. ./path.sh ## Source the tools/utils (import the queue.pl)
enroll_dir=$1

echo "creating data/{enroll_20s,enroll_10s}"
for i in 20 10;do
  xx=`echo "$enroll_dir" | sed "s/30/${i}/g"`
  echo "$xx"
  mkdir -p $xx && cp $enroll_dir/{wav.scp,utt2spk,spk2utt,spk2gender} $xx
  num_row=`cat $enroll_dir/feats.scp | feat-to-len scp:- ark,t:- | cut -d ' ' -f 2 | sed -n '1p' `
  num_row=$[$num_row / 30]
  num_row=$[$num_row * $i]
  cat $enroll_dir/feats.scp | while read line
  do
    spkid=`echo "$line" | awk '{print $1}'`
    echo "$spkid $spkid 0 $num_row" >> $xx/segment_${i}
  done
  extract-rows $xx/segment_${i} scp:$enroll_dir/feats.scp ark,scp:$xx/feats.ark,$xx/feats.scp
done
  

