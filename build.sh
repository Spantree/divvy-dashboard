#!/bin/bash
npm install
bower install
cd data
for f in `ls *.csv.gz`
do
  target=`basename $f .gz`
  gunzip -kf $f > $target
done