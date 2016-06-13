#!/bin/bash
# Copyright 20s16  Tsinghua University (Author: Dong Wang, Xuewei Zhang).
# Apache 2.0.

nj=8
dwntest=false
stdtest=false
stage=0

. ./cmd.sh ## You'll want to change cmd.sh to something that will work on your system.
           ## This relates to the queue.
. ./path.sh

. utils/parse_options.sh || exit 1;
P=$1
corpus_dir=$2
thuyg=$corpus_dir/data_thuyg20_sre

if [ $stage -le 0 ]; then
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
      for x in ubm ubm_female enroll_30s_female ubm_male enroll_30s_male; do
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
          mkdir -p wav/test_noise && cd wav && \
          wget http://www.openslr.org/resources/19/test_noise_sre.tgz || exit 1
          tar xvf test_noise_sre.tgz && mv test_noise_sre/wav/0db test_noise && rm -rf test_noise_sre || exit 1
        )
		 for x in car cafe white; do
            for i in test_female test_male; do
              rm -rf data/${i}_noise/0db/$x && mkdir -p  data/${i}_noise/0db/$x && \
              cp -L data/${i}_clean/{spk2utt,utt2spk,spk2gender} data/${i}_noise/0db/$x || exit 1
              awk '{print $1 " wav/test_noise/0db/'$x'/"$1".wav"}' data/${i}_clean/wav.scp > \
              data/${i}_noise/0db/$x/wav.scp || exit 1
            done
         done
     fi

   else
     #generate test data randomly
     sigma0=0 #no random in SNR
     noise_level=0
     echo "generating noisy test data randomly"
     for i in car white cafe; do
       echo "generating noisy wav for $x"

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
       for j in test_female test_male; do
         wavdir=wav/${j}_noise/${noise_level}db/$i
         rm -rf data/${j}_noise/${noise_level}db/$i && mkdir -p data/${j}_noise/${noise_level}db/$i && \
         cp -L data/${j}_clean/{spk2utt,utt2spk,spk2gender} data/${j}_noise/${noise_level}db/$i || exit 1
         mkdir -p $wavdir && awk '{print $1 " '$wavdir'/"$1".wav"}' data/${j}_clean/wav.scp > \
         data/${j}_noise/${noise_level}db/$i/wav.scp || exit 1
         split_scps=""
         for n in $(seq $nj); do
           split_scps="$split_scps exp/noise_data/gendata/test_split_${n}.scp"
         done
         utils/split_scp.pl data/${j}_clean/wav.scp  $split_scps || exit 1
         $train_cmd JOB=1:$nj exp/noise_data/gendata/add_noise_test.JOB.log \
         local/add-noise-mod.py --noise-level $noise_level \
           --sigma0 $sigma0 --seed $seed --verbose $verbose \
           --noise-prior $noise_prior --noise-src $noise_scp \
           --wav-src exp/noise_data/gendata/test_split_JOB.scp --wavdir $wavdir \
           || exit 1
     done
   done
  fi 
fi

if [ $stage -le  1 ]; then
for k in male female; do
   for i in car cafe white; do
      # extract mfcc features
      for x in enroll_30s_${k}_noise/0db/$i test_${k}_noise/0db/$i ubm_${k}_noise/0db/$i; do
	      steps/make_mfcc.sh --mfcc-config conf/mfcc.conf --nj $nj --cmd "$train_cmd" data/$x exp/make_mfcc/$x mfcc/$x || exit 1;
 	  done
      #segment 10s/20s for 30s enrollment features
      local/segment_thuyg_feats.sh $P/data/enroll_30s_${k}_noise/0db/$i
      #VAD
      for y in enroll_30s_${k}_noise/0db/$i enroll_20s_${k}_noise/0db/$i enroll_10s_${k}_noise/0db/$i test_${k}_noise/0db/$i ubm_${k}_noise/0db/$i; do
	    sid/compute_vad_decision.sh --nj $nj --cmd "$train_cmd" data/$y exp/make_vad_clean/$y $P/mfcc/$y || exit 1;
      done
      #clean UBM, train Tmatrix with 0db noise
        sid/train_ivector_extractor.sh --cmd "$train_cmd" \
	      --num-iters 5 exp/full_ubm_${k}_clean_2048/final.ubm data/ubm_${k}_noise/0db/$i \
          exp/extractor_${k}_${i}0db_2048
      #Extract the iVectors for the UBM data.
        sid/extract_ivectors.sh --cmd "$train_cmd" --nj $nj exp/extractor_${k}_${i}0db_2048  data/ubm_${k}_noise/0db/$i exp/ivectors_ubm_${k}_${i}0db
       sid/extract_ivectors.sh --cmd "$train_cmd" --nj $nj \
          exp/extractor_${k}_${i}0db_2048 data/test_${k}_noise/0db/$i exp/ivectors_test_${k}_${i}0db
	
	  for j in 30s 20s 10s;do
	     sid/extract_ivectors.sh --cmd "$train_cmd" --nj $nj \
			exp/extractor_${k}_${i}0db_2048 data/enroll_${j}_${k}_noise/0db/$i exp/ivectors_enroll_${j}_${k}_${i}0db
		 
		 trials=data/trials/${k}.trials
         #Demonstrate cosine-distance scoring:
         #0db nosie Tmatrix,training data and test data with 0db noise
         cat $trials | awk '{print $1, $2}' | \
            ivector-compute-dot-products - \
            "ark:copy-vector scp:exp/ivectors_enroll_${j}_${k}_${i}0db/spk_ivector.scp ark:- |ivector-normalize-length ark:- ark:- |" \
            "ark:copy-vector scp:exp/ivectors_test_${k}_${i}0db/spk_ivector.scp ark:- |ivector-normalize-length ark:- ark:- |" \
            score_cosine_norm_${j}_${k}_${i}0dbT_${i}0dbtest
        local/score.sh $trials score_cosine_norm_${j}_${k}_${i}0dbT_${i}0dbtest
        rm score_cosine_norm_${j}_${k}_${i}0dbT_${i}0dbtest

        #Demonstrate LDA scoring:
        #0db nosie Tmatrix,training data and test data with 0db noise
        ivector-compute-lda --dim=150  --total-covariance-factor=0.1 \
          "ark:ivector-normalize-length scp:exp/ivectors_ubm_${k}_${i}0db/ivector.scp  ark:- |" ark:data/ubm_${k}_noise/0db/$i/utt2spk \
          exp/ivectors_ubm_${k}_${i}0db/transform.mat
         cat $trials | awk '{print $1, $2}' | ivector-compute-dot-products - \
           "ark:ivector-transform exp/ivectors_ubm_${k}_${i}0db/transform.mat scp:exp/ivectors_enroll_${j}_${k}_${i}0db/spk_ivector.scp ark:- | \
           ivector-normalize-length ark:- ark:- |" "ark:ivector-transform exp/ivectors_ubm_${k}_${i}0db/transform.mat \
           scp:exp/ivectors_test_${k}_${i}0db/spk_ivector.scp ark:- | ivector-normalize-length ark:- ark:- |" \
         score_lda_norm_${j}_${k}_${i}0dbT_${i}0dbtest
         local/score.sh $trials score_lda_norm_${j}_${k}_${i}0dbT_${i}0dbtest
         rm score_lda_norm_${j}_${k}_${i}0dbT_${i}0dbtest

        #Demonstrate PLDA scoring:

		#clean Tmatrix,training data and test data with 0db noise 
        ivector-compute-plda ark:data/ubm_${k}_clean/spk2utt \
           "ark:ivector-normalize-length scp:exp/ivectors_ubm_${k}_clean/ivector.scp  ark:- |" \
           exp/ivectors_ubm_${k}_clean/plda 2>exp/ivectors_ubm_${k}_clean/log/plda.log
        ivector-plda-scoring --num-utts=ark:exp/ivectors_enroll_${j}_${k}_${i}0db/num_utts.ark \
           "ivector-copy-plda --smoothing=0.0 exp/ivectors_ubm_${k}_clean/plda - |" \
           "ark:ivector-subtract-global-mean scp:exp/ivectors_enroll_${j}_${k}_${i}0db/spk_ivector.scp ark:- |" \
           "ark:ivector-subtract-global-mean scp:exp/ivectors_test_${k}_${i}0db/ivector.scp ark:- |" \
        "cat '$trials' | awk '{print \$1, \$2}' |" score_plda_norm_${j}_${k}_cleanT_${i}0dbtest || exit 1;
        local/score.sh $trials score_plda_norm_${j}_${k}_cleanT_${i}0dbtest || exit 1;
        rm score_plda_norm_${j}_${k}_cleanT_${i}0dbtest || exit 1;
        
       #0db nosie Tmatrix,clean training data and clean test data
		ivector-compute-plda ark:data/ubm_${k}_noise/0db/$i/spk2utt \
           "ark:ivector-normalize-length scp:exp/ivectors_ubm_${k}_${i}0db/ivector.scp  ark:- |" \
           exp/ivectors_ubm_${k}_${i}0db/plda 2>exp/ivectors_ubm_${k}_${i}0db/log/plda.log
        ivector-plda-scoring --num-utts=ark:exp/ivectors_enroll_${j}_${k}_clean/num_utts.ark \
           "ivector-copy-plda --smoothing=0.0 exp/ivectors_ubm_${k}_${i}0db/plda - |" \
           "ark:ivector-subtract-global-mean scp:exp/ivectors_enroll_${j}_${k}_clean/spk_ivector.scp ark:- |" \
           "ark:ivector-subtract-global-mean scp:exp/ivectors_test_${k}_clean/ivector.scp ark:- |" \
        "cat '$trials' | awk '{print \$1, \$2}' |" score_plda_norm_${j}_${k}_${i}0dbT_cleantest || exit 1;
        local/score.sh $trials score_plda_norm_${j}_${k}_${i}0dbT_cleantest || exit 1;
        rm score_plda_norm_${j}_${k}_${i}0dbT_cleantest || exit 1;

       #0db nosie Tmatrix,training data and test data with 0db noise
        ivector-compute-plda ark:data/ubm_${k}_noise/0db/$i/spk2utt \
           "ark:ivector-normalize-length scp:exp/ivectors_ubm_${k}_${i}0db/ivector.scp  ark:- |" \
           exp/ivectors_ubm_${k}_${i}0db/plda 2>exp/ivectors_ubm_${k}_${i}0db/log/plda.log
        ivector-plda-scoring --num-utts=ark:exp/ivectors_enroll_${j}_${k}_${i}0db/num_utts.ark \
           "ivector-copy-plda --smoothing=0.0 exp/ivectors_ubm_${k}_${i}0db/plda - |" \
           "ark:ivector-subtract-global-mean scp:exp/ivectors_enroll_${j}_${k}_${i}0db/spk_ivector.scp ark:- |" \
           "ark:ivector-subtract-global-mean scp:exp/ivectors_test_${k}_${i}0db/ivector.scp ark:- |" \
        "cat '$trials' | awk '{print \$1, \$2}' |" score_plda_norm_${j}_${k}_${i}0dbT_${i}0dbtest || exit 1;
        local/score.sh $trials score_plda_norm_${j}_${k}_${i}0dbT_${i}0dbtest || exit 1;
        rm score_plda_norm_${j}_${k}_${i}0dbT_${i}0dbtest || exit 1;
     done
   done
 done
fi
