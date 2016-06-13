#!/bin/bash
# Copyright 20s16  Tsinghua University (Author: Dong Wang, Xuewei Zhang).
# Apache 2.0.

. ./cmd.sh ## You'll want to change cmd.sh to something that will work on your system.
           ## This relates to the queue.
. ./path.sh
. utils/parse_options.sh || exit 1;

P=`pwd`  #exp home
n=8      #parallel jobs

uyghurcorpuspath=/work3/zxw/thuyg20-openslr

# prepare data and produce 0db noise data
local/make_thuyg_data_sre.sh $P $uyghurcorpuspath || exit 1;

# extract mfcc features
for i in enroll_30s_female_clean enroll_30s_male_clean test_female_clean test_male_clean ubm_clean ubm_female_clean ubm_male_clean; do
    steps/make_mfcc.sh --mfcc-config conf/mfcc.conf --nj $n --cmd "$train_cmd" $P/data/$i exp/make_mfcc/$i mfcc/$i || exit 1;
done

#segment 10s/20s for 30s enrollment features
local/segment_thuyg_feats.sh data/enroll_30s_female_clean 
local/segment_thuyg_feats.sh data/enroll_30s_male_clean

#train in clean conditions:
# VAD
for x in enroll_30s_female_clean enroll_20s_female_clean enroll_10s_female_clean enroll_30s_male_clean enroll_20s_male_clean enroll_10s_male_clean test_female_clean test_male_clean ubm_clean ubm_female_clean ubm_male_clean; do
  sid/compute_vad_decision.sh --nj $n --cmd "$train_cmd" data/$x exp/make_vad_clean/$x $P/mfcc/$x || exit 1;
done

split_data.sh data/ubm_clean 2 && mv data/ubm_clean/split2/1 data/ubm_clean_1 && \
mv data/ubm_clean/split2/2 data/ubm_clean_2 || exit 1;

sid/train_diag_ubm.sh --nj $n --cmd "$train_cmd" data/ubm_clean_1 2048 exp/diag_ubm_clean_2048
sid/train_full_ubm.sh --nj $n --cmd "$train_cmd" data/ubm_clean_2 exp/diag_ubm_clean_2048 exp/full_ubm_clean_2048

#Get female versions of the UBM
sid/train_full_ubm.sh --nj $n --remove-low-count-gaussians false --num-iters 1 --cmd "$train_cmd" \
   data/ubm_female_clean exp/full_ubm_clean_2048 exp/full_ubm_female_clean_2048 &

#Get male versions of the UBM
sid/train_full_ubm.sh --nj $n --remove-low-count-gaussians false --num-iters 1 --cmd "$train_cmd" \
   data/ubm_male_clean exp/full_ubm_clean_2048 exp/full_ubm_male_clean_2048 &
wait

mkdir results && resultsdir=results #the result dir

local/make_trials.sh  data/test_female_clean female
local/make_trials.sh  data/test_male_clean male

for i in female male; do #male and female test and train respectively 
  # The same for female/male speakers.
 sid/train_ivector_extractor.sh --cmd "$train_cmd" \
    --num-iters 5 exp/full_ubm_${i}_clean_2048/final.ubm data/ubm_${i}_clean \
    exp/extractor_${i}_clean_2048

  # Extract the iVectors for the UBM data.
  sid/extract_ivectors.sh --cmd "$train_cmd" --nj $n \
    exp/extractor_${i}_clean_2048 data/ubm_${i}_clean exp/ivectors_ubm_${i}_clean
  sid/extract_ivectors.sh --cmd "$train_cmd" --nj $n \
    exp/extractor_${i}_clean_2048 data/test_${i}_clean exp/ivectors_test_${i}_clean
  for k in 30s 20s 10s;do
   sid/extract_ivectors.sh --cmd "$train_cmd" --nj $n \
      exp/extractor_${i}_clean_2048 data/enroll_${k}_${i}_clean exp/ivectors_enroll_${k}_${i}_clean

    trials=data/trials/${i}.trials
    #Demonstrate cosine-distance scoring:
    cat $trials | awk '{print $1, $2}' | \
      ivector-compute-dot-products - \
      "ark:copy-vector scp:exp/ivectors_enroll_${k}_${i}_clean/spk_ivector.scp ark:- |ivector-normalize-length ark:- ark:- |" \
      "ark:copy-vector scp:exp/ivectors_test_${i}_clean/spk_ivector.scp ark:- |ivector-normalize-length ark:- ark:- |" \
      score_cosine_norm_${k}_${i}_cleanT_cleantest
    local/score.sh $trials score_cosine_norm_${k}_${i}_cleanT_cleantest
    rm score_cosine_norm_${k}_${i}_cleanT_cleantest
    #Demonstrate LDA scoring:
    ivector-compute-lda --dim=150  --total-covariance-factor=0.1 \
      "ark:ivector-normalize-length scp:exp/ivectors_ubm_${i}_clean/ivector.scp  ark:- |" ark:data/ubm_${i}_clean/utt2spk \
      exp/ivectors_ubm_${i}_clean/transform.mat
    cat $trials | awk '{print $1, $2}' | ivector-compute-dot-products - \
      "ark:ivector-transform exp/ivectors_ubm_${i}_clean/transform.mat scp:exp/ivectors_enroll_${k}_${i}_clean/spk_ivector.scp ark:- | \
      ivector-normalize-length ark:- ark:- |" "ark:ivector-transform exp/ivectors_ubm_${i}_clean/transform.mat \
      scp:exp/ivectors_test_${i}_clean/spk_ivector.scp ark:- | ivector-normalize-length ark:- ark:- |" \
      score_lda_norm_${k}_${i}_cleanT_cleantest
    local/score.sh $trials score_lda_norm_${k}_${i}_cleanT_cleantest
    rm score_lda_norm_${k}_${i}_cleanT_cleantest

    #Demonstrate PLDA scoring:
    ivector-compute-plda ark:data/ubm_${i}_clean/spk2utt \
      "ark:ivector-normalize-length scp:exp/ivectors_ubm_${i}_clean/ivector.scp  ark:- |" \
      exp/ivectors_ubm_${i}_clean/plda 2>exp/ivectors_ubm_${i}_clean/log/plda.log 
    ivector-plda-scoring --num-utts=ark:exp/ivectors_enroll_${k}_${i}_clean/num_utts.ark \
      "ivector-copy-plda --smoothing=0.0 exp/ivectors_ubm_${i}_clean/plda - |" \
      "ark:ivector-subtract-global-mean scp:exp/ivectors_enroll_${k}_${i}_clean/spk_ivector.scp ark:- |" \
      "ark:ivector-subtract-global-mean scp:exp/ivectors_test_${i}_clean/ivector.scp ark:- |" \
      "cat '$trials' | awk '{print \$1, \$2}' |" score_plda_norm_${k}_${i}_cleanT_cleantest || exit 1;
    local/score.sh $trials score_plda_norm_${k}_${i}_cleanT_cleantest || exit 1;
    rm score_plda_norm_${k}_${i}_cleanT_cleantest || exit 1;
 done
done

#train in noise 0db conditions:
local/run_noise_training.sh --stage 0 --nj $n --dwntest false --stdtest false $P $uyghurcorpuspath 

