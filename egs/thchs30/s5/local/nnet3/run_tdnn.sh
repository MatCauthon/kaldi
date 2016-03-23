#!/bin/bash
# Copyright 2016  Tsinghua University (Author: Dong Wang, Xuewei Zhang).  Apache 2.0.
# Train tdnn using multi-gpus

stage=0
train_stage=-10
nj=8
dir=exp/nnet3_tdnn_pnorm

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh || exit 1;

gmmdir=$1

if ! cuda-compiled; then
  cat <<EOF && exit 1 
This script is intended to be used with GPUs but you have not compiled Kaldi with CUDA 
If you want to use GPUs (and have them), go to src/, and configure and make on a machine
where "nvcc" is installed.
EOF
fi

#tdnn training

if [ $stage -le 8 ]; then

    steps/nnet3/train_tdnn.sh --stage $train_stage \
    --num-epochs 8 --num-jobs-initial 2 --num-jobs-final 14 \
    --splice-indexes "-1,0,1  -2,0,2  -2,0,2 0" \
    --feat-type raw \
    --cmvn-opts "--norm-means=true --norm-vars=false" \
    --use-gpu true \
    --io-opts "-tc 12" \
    --pnorm-input-dim 2000 \
    --pnorm-output-dim 250 \
    --initial-effective-lrate 0.008 --final-effective-lrate 0.0008 \
    --cmd "$decode_cmd" \
    data/fbank/train data/lang exp/tri4b_ali $dir  || exit 1;
fi

#tdnn decode
if [ $stage -le 9 ]; then
    (
     steps/nnet3/decode.sh --nj $nj --cmd "$decode_cmd" \
       $gmmdir/graph.word data/fbank/test $dir/decode_test_word || exit 1;
    )&
    (
     steps/nnet3/decode.sh --nj $nj --cmd "$decode_cmd" \
       $gmmdir/graph.phone data/fbank/test.ph $dir/decode_test_phone || exit 1;
    )&

fi

