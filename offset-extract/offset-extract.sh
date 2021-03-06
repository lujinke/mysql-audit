#!/bin/sh

if [ $# = 0 ]; then 	
	echo "Usage: $0 <mysqld executable> [optional mysqld symbols]"
	echo "Will extract offsets from mysqld. Requires gdb, md5sum and mysqld symbols."
	exit 1
fi

#extract the version of mysqld

FULL_MYVER=`$1 --version | grep -P  -o 'Ver\s+[\w\.-]+'| awk '{print $2}'`

#extract the md5 digest

MYMD5=`md5sum -b $1 | awk -v Field=1 '{print $1}'`

MYVER="$FULL_MYVER"
echo $FULL_MYVER | grep  'log' > /dev/null


if [ $? = 0 ]; then
	MYVER=`echo "$MYVER" | grep -P  -o '.+(?=-log)'`
fi

COMMAND_MEMBER=command
THREAD_ID=thread_id
SEC_CONTEXT=main_security_ctx
USER=user
HOST=host
IP=ip
PRIV_USER=priv_user
DB=db

#in 5.6 command member is named m_command
echo $MYVER | grep -P '^(5\.6|5\.7|10\.)' > /dev/null
if [ $? = 0 ]; then
	COMMAND_MEMBER=m_command
fi
#in 5.7 thread_id changed to m_thread_id. main_security_ctx changed to m_main_security_ctx
echo $MYVER | grep -P '^(5\.7)' > /dev/null
if [ $? = 0 ]; then
	THREAD_ID=m_thread_id
    SEC_CONTEXT=m_main_security_ctx
    USER=m_user
    HOST=m_host
    IP=m_ip
    PRIV_USER=m_priv_user    
    DB=m_db
fi

cat <<EOF > offsets.gdb
set logging on
define print_offset
  printf ", %d", (size_t)&((\$arg0*)0)->\$arg1
end
printf "{\"$MYVER\",\"$MYMD5\""
print_offset THD query_id
print_offset THD $THREAD_ID
print_offset THD $SEC_CONTEXT
print_offset THD $COMMAND_MEMBER
print_offset THD lex
print_offset LEX comment
print_offset Security_context $USER
print_offset Security_context $HOST
print_offset Security_context $IP
print_offset Security_context $PRIV_USER
print_offset THD $DB
print_offset THD killed
printf "}"
EOF

SYMPARAM=""
if [ -n "$2" ]; then
	SYMPARAM="-s $2 -e"
fi

which gdb > /dev/null 2>&1
if [ $? != 0 ]; then
        echo "ERROR: gdb not found. Make sure gdb is installed and on the path."
        exit 3;
fi

gdb -n -q -batch -x offsets.gdb $SYMPARAM  $1 > /dev/null 2>&1

if [ $? != 0 ]; then
	echo "GDB failed!!!" > /dev/stderr
	exit 2
fi

OFFSETS=`cat gdb.txt`
echo "//offsets for: $1 ($FULL_MYVER)"
echo "$OFFSETS,"

#clean up
rm gdb.txt
rm offsets.gdb

