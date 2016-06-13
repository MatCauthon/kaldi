#!/bin/bash
#Copyright 2016  Tsinghua University (Author: Dong Wang, Xuewei Zhang).  Apache 2.0.

#add 0db noise to ubm, enroll and test audio 

dwntest=false
stdtest=false
nj=8

. ./cmd.sh ## You'll want to change cmd.sh to something that will work on your system.
           ## This relates to the queue.

. ./path.sh ## Source the tools/utils (import the queue.pl)
. utils/parse_options.sh || exit 1;

corpus_dir=$1
thuyg=$corpus_dir/data_thuyg20_sre

  #generate noisy data with SNR mean=0, variance=0 with one cafe noise
  echo "add 0db noise to ubm, enroll and test audio"
  #generate noise.scp
   mkdir -p data/noise && \
   awk '{print $1 " '$corpus_dir'/resource/noise/"$2}' $corpus_dir/resource/noise/noise.scp > data/noise/noise.scp || exit 1
  #generate ubm,enroll data with 0db cafe noise
   echo "Generate ubm, enroll with 0db cafe/car/white noise"
   noise_scp=data/noise/noise.scp
   noise_level=0 #0db condition
   sigma0=0 #some random in SNR
   seed=32
   verbose=0
   for i in car white cafe; do
      echo "generating noisy wav for $x"  #define noise type to sample. [S_clean, S_white, S_car, S_cafe]

      case $i in
        car)
          noise_prior="0.0,0.0,10.0,0.0"
          ;;
        white)
          noise_prior="0.0,10.0,0.0,0.0"
          ;;
        cafe)
          noise_prior="0.0,0.0,0.0,10.0"
          ;;
      esac

      for x in ubm ubm_female enroll_30s_female; do
         wavdir=wav/${x}_noise/${noise_level}db/$i
         rm -rf data/${x}_noise/${noise_level}db/$i && mkdir -p data/${x}_noise/${noise_level}db/${i} || exit 1
	     cp data/${x}_clean/{spk2utt,utt2spk,spk2gender} data/${x}_noise/${noise_level}db/${i} || exit 1
         mkdir -p $wavdir && awk '{print $1 " '$wavdir'/"$1".wav"}' data/${x}_clean/wav.scp > \
		   data/${x}_noise/${noise_level}db/${i}/wav.scp || exit 1	 
	     mkdir -p exp/noise_data/gendata
	     split_scps=""
	     for n in $(seq $nj); do
		   split_scps="$split_scps exp/noise_data/gendata/${x}_split_${n}.scp"
         done
	     utils/split_scp.pl data/${x}_clean/wav.scp  $split_scps || exit 1
	     $train_cmd JOB=1:$nj exp/noise_data/gendata/add_noise_${x}.JOB.log \
	     local/add-noise-mod.py --noise-level $noise_level \
	       --sigma0 $sigma0 --seed $seed --verbose $verbose \
           --noise-prior $noise_prior --noise-src $noise_scp \
	       --wav-src exp/noise_data/gendata/${x}_split_JOB.scp --wavdir $wavdir \
	     || exit 1
      done
   done
  #genreate test data. Just the 0db condition is produced. Note that if you want to compare with the standard results, set stdtest=true
   echo "Generate test data with 0db cafe/car/white noise"
   if [ $stdtest = true ]; then
     #download noisy wav if use the standard test data
	  echo "using standard test data"
	  if [ $dwntest = true ];then
	    echo "downloading the noisy test data from openslr..."
		(
		  mkdir -p wav/test_female_noise && cd wav && \
		  wget http://www.openslr.org/resources/19/test_noise_sre.tgz || exit 1
     	  tar xvf test_noise_sre.tgz && mv test_noise_sre/wav/0db test_female_noise && rm -rf test_noise_sre || exit 1 
		)
        for i in car white cafe; do
          rm -rf data/test_female_noise/0db/${i} && mkdir -p data/test_female_noise/0db/${i} && \
          cp -L data/test_female_clean/{spk2utt,utt2spk,spk2gender} data/test_female_noise/0db/${i} || exit 1
          awk '{print $1 " '$wavdir'/"$1".wav"}' data/test_female_clean/wav.scp > \
            data/test_female_noise/0db/${i}/wav.scp || exit 1
        done

	 fi

   else
     #generate test data randomly
     sigma0=0 #no random in SNR
     noise_level=0
     echo "generating noisy test data randomly"
     for i in car white cafe; do
       echo "generating noisy wav for $x"

       case $x in
         car)
            noise_prior="0.0,0.0,10.0,0.0"
            ;;
         white)
            noise_prior="0.0,10.0,0.0,0.0"
            ;;
         cafe)
            noise_prior="0.0,0.0,0.0,10.0"
            ;;
       esac
  
       wavdir=wav/test_female_noise/${noise_level}db/$i
       rm -rf data/test_female_nosie/${noise_level}db/$i && mkdir -p data/test_female_nosie/${noise_level}db/$i && \
       cp -L data/test_female_clean/{spk2utt,utt2spk,spk2gender} data/test_female_nosie/${noise_level}db/$i || exit 1
       mkdir -p $wavdir && awk '{print $1 " '$wavdir'/"$1".wav"}' data/test_female_clean/wav.scp > \
         data/test_female_nosie/${noise_level}db/$i/wav.scp || exit 1
       split_scps=""
       for n in $(seq $nj); do
         split_scps="$split_scps exp/noise_data/gendata/test_split_${n}.scp"
       done
       utils/split_scp.pl data/test_female_clean/wav.scp  $split_scps || exit 1
       $train_cmd JOB=1:$nj exp/noise_data/gendata/add_noise_test.JOB.log \
        local/add-noise-mod.py --noise-level $noise_level \
           --sigma0 $sigma0 --seed $seed --verbose $verbose \
           --noise-prior $noise_prior --noise-src $noise_scp \
           --wav-src exp/noise_data/gendata/test_split_JOB.scp --wavdir $wavdir \
           || exit 1
    done
  fi
