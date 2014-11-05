#! /bin/sh

# Multiple benchmarks - set DO_VERIFY=0 and
#
# wdt/wdt_e2e_test.sh |& awk '/All data.*Total throughput/ \
# {print $30} /^(real|user|sys)/ {print $0}'

# 100 loops:
#
# for i in {1..100} ;do date; wdt/wdt_e2e_test.sh \
# |& awk '/All data.*Total throughput/ {print int($30+.5)}' \
# >> ~/wdt_perfRes100; done &
#
# $ histogram -offset 7000 -divider 100 -percentile1 25 -percentile2 50 < ~/wdt_perfRes100
# # count,avg,min,max,stddev,100,8433.43,6506,9561,690.083
# # range, mid point, percentile, count
# < 7100 , 7050 , 3, 3
# >= 7100 < 7200 , 7150 , 7, 4
# >= 7200 < 7300 , 7250 , 10, 3
# >= 7300 < 7400 , 7350 , 10, 0
# >= 7400 < 7500 , 7450 , 11, 1
# >= 7500 < 7600 , 7550 , 12, 1
# >= 7600 < 7700 , 7650 , 14, 2
# >= 7700 < 7800 , 7750 , 15, 1
# >= 7800 < 7900 , 7850 , 15, 0
# >= 7900 < 8000 , 7950 , 19, 4
# >= 8000 < 8100 , 8050 , 27, 8
# >= 8100 < 8200 , 8150 , 35, 8
# >= 8200 < 8400 , 8300 , 43, 8
# >= 8400 < 8600 , 8500 , 59, 16
# >= 8600 < 8800 , 8700 , 68, 9
# >= 8800 < 9000 , 8900 , 80, 12
# >= 9000 < 9500 , 9250 , 97, 17
# >= 9500 < 10000 , 9750 , 100, 3
# # target 25.0%,8075.0
# # target 50.0%,8487.5

echo "Run from ~/fbcode - or fbmake runtests"

# Set DO_VERIFY:
# to 1 : slow/expensive but checks correctness
# to 0 : fast for repeated benchmarking not for correctness
DO_VERIFY=1

# Verbose:
#WDTBIN="_bin/wdt/wdt -minloglevel 0"
# Fastest:
BS=`expr 256 \* 1024`
#WDTBIN_OPTS="-buffer_size=$BS -num_sockets=8 -minloglevel 2 -sleep_ms 1 -max_retries 999"
WDTBIN_OPTS="-minloglevel 2 -sleep_ms 1 -max_retries 999"
WDTBIN="_bin/wdt/wdt $WDTBIN_OPTS"

BASEDIR=/dev/shm/tmpWDT
#BASEDIR=/data/wdt/tmpWDT
mkdir -p $BASEDIR
DIR=`mktemp -d --tmpdir=$BASEDIR`
echo "Testing in $DIR"

pkill -x wdt

mkdir $DIR/src
mkdir $DIR/dst


#cp -R wdt folly /usr/bin /usr/lib /usr/lib64 /usr/libexec /usr/share $DIR/src
#cp -R wdt folly /usr/bin /usr/lib /usr/lib64 /usr/libexec $DIR/src
#cp -R wdt folly /usr/share $DIR/src
cp -R wdt folly $DIR/src
#cp -R wdt $DIR/src

#for size in 1k 64K 512K 1M 16M 256M 512M 1G
#for size in 512K 1M 16M 256M 512M 1G
for size in 1k 64K 512K 1M 16M 256M 512M
do
    base=inp$size
    echo dd if=/dev/... of=$DIR/src/$base.1 bs=$size count=1
#    dd if=/dev/urandom of=$DIR/src/$base.1 bs=$size count=1
    dd if=/dev/zero of=$DIR/src/$base.1 bs=$size count=1
    for i in {2..8}
    do
        cp $DIR/src/$base.1 $DIR/src/$base.$i
    done
done
echo "done with setup"

# test symlink issues
(cd $DIR/src ; touch a; ln -s doesntexist badlink; touch c; ln -s wdt wdt_2)


# Various smaller tests if the bigger one fails and logs are too hard to read:
#cp wdt/wdtlib.cpp wdt/wdtlib.h $DIR/src
#cp wdt/*.cpp $DIR/src
#cp /usr/bin/* $DIR/src
#cp wdt/wdtlib.cpp $DIR/src/a
#cp wdt/wdtlib.h  $DIR/src/b
#head -30 wdt/wdtlib.cpp >  $DIR/src/c

# Can't have both client and server send to stdout in parallel or log lines
# get mangled/are missing - so we redirect the server one
$WDTBIN -directory $DIR/dst > $DIR/server.log 2>&1 &

# client now retries connects so no need wait for server to be up

# Only 1 socket (single threaded send/receive)
#$WDTBIN -num_sockets=1 -directory $DIR/src -destination ::1
# Normal

#time trickle -d 1000 -u 1000 $WDTBIN -directory $DIR/src -destination $HOSTNAME |& tee $DIR/client.log
time $WDTBIN -directory $DIR/src -destination $HOSTNAME |& tee $DIR/client.log

# rsync test:
#time rsync --stats -v -W -r $DIR/src/ $DIR/dst/

# No need to wait for transfer to finish, client now exits when last byte is saved


if [ $DO_VERIFY -eq 1 ] ; then
    echo "Checking for difference `date`"

    NUM_FILES=`(cd $DIR/dst ; ( find . -type f | wc -l))`
    echo "Transfered `du -ks $DIR/dst` kbytes across $NUM_FILES files"

    (cd $DIR/src ; ( find . -type f | /bin/fgrep -v "/." | xargs md5sum | sort ) > ../src.md5s )
    (cd $DIR/dst ; ( find . -type f | xargs md5sum | sort ) > ../dst.md5s )

    echo "Should be no diff"
    (cd $DIR; diff -u src.md5s dst.md5s)
    STATUS=$?
#(cd $DIR; ls -lR src/ dst/ )
else
    echo "Skipping independant verification"
    STATUS=0
fi

pkill -x wdt

echo "Server logs:"
cat $DIR/server.log

if [ $STATUS -eq 0 ] ; then
  echo "Good run, deleting logs in $DIR"
  find $DIR -type d | xargs chmod 755 # cp -r makes lib/locale not writeable somehow
  rm -rf $DIR
else
  echo "Bad run ($STATUS) - keeping full logs and partial transfer in $DIR"
fi

exit $STATUS
