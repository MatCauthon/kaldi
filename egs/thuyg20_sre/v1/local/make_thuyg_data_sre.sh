#!/bin/bash
#Copyright 2016  Tsinghua University (Author: Dong Wang, Xuewei Zhang).  Apache 2.0.

#This script pepares the data directory for thuyg20_sre recipe.
#It reads the corpus and get wav.scp, utt2spk, spk2utt, spk2gender.

nj=8

. ./cmd.sh ## You'll want to change cmd.sh to something that will work on your system.
           ## This relates to the queue.

. ./path.sh ## Source the tools/utils (import the queue.pl)
. utils/parse_options.sh || exit 1;

dir=$1
corpus_dir=$2
thuyg=$corpus_dir/data_thuyg20_sre

cd $dir
echo "creating data/{ubm,enroll,test}"
mkdir -p data/{ubm,enroll,test}
#create wav.scp, utt2spk.scp, spk2utt.scp, spk2gender.scp
(
 for x in ubm enroll test;do
   echo "cleaning data/$x"
   cd $dir/data/$x
   rm -rf wav.scp utt2spk spk2utt spk2gender
   echo "preparing scps in data/$x"
   for uttid in `find  $thuyg/$x/*.wav | sort -u | xargs -i basename {} .wav`; do
     spkid=`echo "$uttid" | awk -F _ '{print $1}'`
     genderid=`echo "$spkid" | tr -d "[0-9][]" | tr A-Z a-z`  
     echo $uttid $thuyg/$x/$uttid.wav >> wav.scp
	 if [ $x = test ];then
	   echo $uttid $uttid >> utt2spk
	   echo $uttid $genderid >> tmp
	 else
       echo $uttid $spkid >> utt2spk
	   echo $spkid $genderid >> tmp
	 fi
   done
   sort -u tmp > spk2gender && rm tmp
   cat utt2spk | sort -u | $dir/utils/utt2spk_to_spk2utt.pl > spk2utt
   
   #only consider female data
   mkdir $dir/data/${x}_female_clean
   cd $dir
   grep -w f data/$x/spk2gender | awk '{print $1}' > $dir/data/${x}_female_clean/tmp
   $dir/utils/subset_data_dir.sh --spk-list $dir/data/${x}_female_clean/tmp $dir/data/$x $dir/data/${x}_female_clean
   rm data/${x}_female_clean/tmp

   #only consider male data
   mkdir $dir/data/${x}_male_clean
   cd $dir
   grep -w m data/$x/spk2gender | awk '{print $1}' > $dir/data/${x}_male_clean/tmp
   $dir/utils/subset_data_dir.sh --spk-list $dir/data/${x}_male_clean/tmp $dir/data/$x $dir/data/${x}_male_clean
   rm data/${x}_male_clean/tmp
 done
) || exit 1
   mv $dir/data/enroll_female_clean $dir/data/enroll_30s_female_clean && mv $dir/data/enroll_male_clean $dir/data/enroll_30s_male_clean && \
   mv $dir/data/ubm $dir/data/ubm_clean && \
   rm -rf $dir/data/test $dir/data/enroll || exit 1;

