#!/bin/bash

## jenkins-test.sh - tools/travis-test.sh without the TTY dependencies

PRESET="internal_mnesia"
SMALL_TESTS="true"
COVER_ENABLED="true"
TESTSPEC="jenkins.spec"
START_AND_QUIT=

while getopts ":Qp:s:t:c:" opt; do
  case $opt in
    p)
      PRESET=$OPTARG
      ;;
    s)
      SMALL_TESTS=$OPTARG
      ;;
    t)
      TESTSPEC=$OPTARG
      ;;
    Q)
      SMALL_TESTS=false
      START_AND_QUIT=yes
      ;;
    c)
      COVER_ENABLED=$OPTARG
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

source tools/travis-common-vars.sh
#source tools/travis-helpers.sh

if [ "$TRAVIS_SECURE_ENV_VARS" == 'true' ]; then
  CT_REPORTS=$(ct_reports_dir)

  echo "Test results will be uploaded to:"
  echo $(s3_url ${CT_REPORTS})
fi
## Print ct_progress_hook output
#echo "" > /tmp/progress
#tail -f /tmp/progress &

# Kill children on exit, but do not kill self on normal exit
trap "trap - SIGTERM && kill -- -$$ 2> /dev/null" SIGINT SIGTERM
trap "trap '' SIGTERM && kill -- -$$ 2> /dev/null" EXIT

echo ${BASE}

EJD1=${BASE}/dev/mongooseim_node1
EJD2=${BASE}/dev/mongooseim_node2
EJD3=${BASE}/dev/mongooseim_node3
FED1=${BASE}/dev/mongooseim_fed1
EJD1CTL=${EJD1}/bin/mongooseimctl
EJD2CTL=${EJD2}/bin/mongooseimctl
EJD3CTL=${EJD3}/bin/mongooseimctl
FED1CTL=${FED1}/bin/mongooseimctl

NODES=(${EJD1CTL} ${EJD2CTL} ${EJD3CTL} ${FED1CTL})

start_node() {
	echo -n "${1} start: "
	${1} start && echo ok || echo failed
	${1} started
	${1} status
	echo
}

stop_node() {
	echo -n "${1} stop: "
	${1} stop
	${1} stopped
	echo
}

# return the most recent N directories, all if N is not a number
summaries_dir() {
	N=$1; shift
	DIRS=($(ls -td "$@"))
	case "$N" in
	[0-9]*) ;;
	*)      N=1;;
	esac
	echo "${DIRS[@]:0:$N}"
}

run_small_tests() {
	echo "############################"
	echo "Running small tests (apps/ejabberd/tests)"
	echo "############################"
	echo "Add option -s false to skip embeded common tests"
	make ct
	SMALL_SUMMARIES_DIRS=${BASE}/apps/ejabberd/logs/ct_run*
	SMALL_SUMMARIES_DIR=$(summaries_dir 1 ${SMALL_SUMMARIES_DIRS})
	${TOOLS}/summarise-ct-results ${SMALL_SUMMARIES_DIR}
}

maybe_run_small_tests() {
	if [ "$SMALL_TESTS" = "true" ]; then
		run_small_tests
	else
		echo "############################"
		echo "Small tests skipped"
		echo "############################"
	fi
}

run_test_preset() {
#	tools/print-dots.sh start
	if [ "$COVER_ENABLED" = "true" ]; then
		make cover_test_preset TESTSPEC=$TESTSPEC PRESET=$PRESET
	else
		make test_preset TESTSPEC=$TESTSPEC PRESET=$PRESET
	fi
#	tools/print-dots.sh stop
}

run_tests() {
	maybe_run_small_tests
	SMALL_STATUS=$?
	echo "SMALL_STATUS=$SMALL_STATUS"
	echo ""
	echo "############################"
	echo "Running big tests (tests/ejabberd_tests)"
	echo "############################"

	for node in ${NODES[@]}; do
		start_node $node;
	done
	test -n "$START_AND_QUIT" && { echo quitting; exit 0; }

	run_test_preset

	RAN_TESTS=`cat /tmp/ct_count`

	for node in ${NODES[@]}; do
		stop_node $node;
	done

	SUMMARIES_DIRS=${BASE}'/test/ejabberd_tests/ct_report/ct_run*'
	SUMMARIES_DIR=$(summaries_dir "${RAN_TESTS}" ${SUMMARIES_DIRS})
	${TOOLS}/summarise-ct-results ${SUMMARIES_DIR}
	BIG_STATUS=$?

	echo
	echo "All tests done."

	if [ $SMALL_STATUS -eq 0 -a $BIG_STATUS -eq 0 ]
	then
		RESULT=0
		echo "Build succeeded"
	else
		RESULT=1
		echo "Build failed:"
		[ $SMALL_STATUS -ne 0 ] && echo "    small tests failed"
		[ $BIG_STATUS -ne 0 ]   && echo "    big tests failed"
	fi

	exit ${RESULT}
}

if [ $PRESET == "dialyzer_only" ]; then
	make dialyzer

else
	run_tests
fi

