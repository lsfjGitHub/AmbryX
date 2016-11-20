#!/bin/bash
# Author : Hash Zhang

# Constants definition:
#利用cd `dirname $0`切换到脚本当前目录，$0代表脚本文件，pwd获取目录绝对路径
BIN_DIR=$(cd `dirname $0`;pwd)
#获取项目根目录
DEPLOY_DIR=$(cd $BIN_DIR;cd ..;pwd)
CONF_DIR=$DEPLOY_DIR/conf
LIB_DIR=$DEPLOY_DIR/lib
LIB_JARS=`ls $LIB_DIR|grep .jar|awk '{print "'$LIB_DIR'/"$0}'|tr "\n" ":"`
LOG_DIR=$DEPLOY_DIR/logs
JVM_PARAS=" -Dlog4j.configuration=file:${CONF_DIR}/log4j.properties "
JVM_DEBUG_OPTS=""
JVM_JMX_OPTS=""
JVM_MEM_OPTS=" -server -Xmx2g -Xms1g -Xmn64m -XX:PermSize=64m -Xss256k -XX:+DisableExplicitGC -XX:+UseConcMarkSweepGC -XX:+CMSParallelRemarkEnabled -XX:+UseCMSCompactAtFullCollection -XX:LargePageSizeInBytes=128m -XX:+UseFastAccessorMethods -XX:+UseCMSInitiatingOccupancyOnly -XX:CMSInitiatingOccupancyFraction=70 "
SYS_PROPERTIES=""
SYS_CLUSTER_PARA=""
#读取传入参数，遍历
for arg in $*
do
    #参数debug，则激活debug参数
    if [ "debug"x = "$arg"x ]
    then
        echo "In debug mode!"
        JVM_DEBUG_OPTS=" -Xdebug -Xnoagent -Djava.compiler=NONE -Xrunjdwp:transport=dt_socket,address=8000,server=y,suspend=n "
    #参数为jmx，则激活jmx参数
    elif [ "jmx"x = "$arg"x ]
    then
        echo "Enable JMX!"
        JVM_JMX_OPTS=" -Dcom.sun.management.jmxremote.port=1099 -Dcom.sun.management.jmxremote.ssl=false -Dcom.sun.management.jmxremote.authenticate=false "
    #参数为minMem，则修改JVM_MEM_OPTS参数
    elif [ "minMem"x = "$arg"x ]
    then
        echo "In min memory mode!"
        JVM_MEM_OPTS=" -server -Xmx256m -Xms128m "
    fi
done

watchBootstrap () {
    ret=0;
    while [ $ret -eq 0 ]
    do
        #因为每种类型的日志如果成功日志最后一行都是包含Server start,所以根据这个来判断是否启动成功
        #注意指定了日志文件的文职和目录，所以待会java 启动命令最后需要加上 > ${LOG_DIR}/stdout.out
        output=`cat ${LOG_DIR}/stdout.out|grep "Server start"`
        if [[ $output != "" ]]
        then
            ret=1
        else
            #因为有任意异常日志最后一行都是包含Server shutdown,所以根据这个来判断是否启动成功
            output=`cat ${LOG_DIR}/stdout.out|grep "Server shutdown"`
            if [[ $output != "" ]]
            then
                 ret=2
            fi
        fi
        sleep 1
        echo -ne "."
    done
    if [ $ret -eq 2 ]
    then
        echo -e "\n************************Failed to start $1!************************\n"
        cat ${LOG_DIR}/stdout.out
    else
        echo -e "\n************************$1 started!************************\n"
    fi
}

specifyConfiguration(){
    echo "which is the server properties(please put your configuration files in the configuration folder:${CONF_DIR})?"
    #利用``执行ls命令获取CONF_DIR目录下的所有文件
    configurations=`ls ${CONF_DIR}`
    #遍历返回，展示文件列表
    count=1
    #注意，shell脚本语法很严格，for do done不能在同一行，如果要在同一行，则需要加;
    for var in $configurations
    do
        echo "${count}. ${var}"
        count=`expr $count + 1`
    done
    echo -n "Please input the sequence number of the Configuration for server properties: "
    #获取用户选择的文件
    read number
    count=1
    for var in $configurations
    do
        #注意，shell脚本语法很严格，if then fi，如果要在同一行，则需要加;
        #这里已经确保了count不为空，如果输入为空则会报错
        #注意，if 后面的 [ 条件 ] 之间的空格是必须的
        if [ $count -eq $number ]
        then
            SYS_PROPERTIES="--serverPropsFilePath ${CONF_DIR}/${var}"
        fi
        count=`expr $count + 1`
    done
    count=1
    for var in $configurations
    do
        echo "${count}. ${var}"
        count=`expr $count + 1`
    done
    echo -n "Please input the sequence number of the Configuration for hardwareLayout: "
    #获取用户选择的文件
    read number
    count=1
    for var in $configurations
    do
        if [ $count -eq $number ]
        then
            SYS_CLUSTER_PARA="--hardwareLayoutFilePath ${CONF_DIR}/${var}"
        fi
        count=`expr $count + 1`
    done
    count=1
    for var in $configurations
    do
        echo "${count}. ${var}"
        count=`expr $count + 1`
    done
    echo -n "Please input the sequence number of the Configuration for partitionLayout: "
    #获取用户选择的文件
    read number
    count=1
    for var in $configurations
    do
        if [ $count -eq $number ]
        then
            SYS_CLUSTER_PARA="${SYS_CLUSTER_PARA} --partitionLayoutFilePath ${CONF_DIR}/${var}"
        fi
        count=`expr $count + 1`
    done
}

bootServer () {
    echo -e "\n************************Please specify the module you want to start:************************\n"
    echo "1. Ambry-Server"
    echo "2. Ambry-Frontend"
    echo "3. Ambry-Admin"
    echo -n "Your selection is(input 1,2 or 3):"

    read MODULE
    echo ""
    case $MODULE in
    1)
        specifyConfiguration
        echo "Starting Ambry-Server"
        # 2>&1 代表（0是标准输入，1是标准输出，2是标准错误输出）将标准错误输出也输出到标准输出，末尾的 &代表后台启动，> ${LOG_DIR}/stdout.out代表将所有标准输出输出到文件${LOG_DIR}/stdout.out中
        java $JVM_DEBUG_OPTS $JVM_JMX_OPTS $JVM_MEM_OPTS $JVM_PARAS -classpath $CONF_DIR:$LIB_JARS com.github.ambry.server.AmbryMain ${SYS_PROPERTIES} ${SYS_CLUSTER_PARA} > ${LOG_DIR}/stdout.out 2>&1 &
        watchBootstrap "Ambry-Server"
        echo -e "\n************************************************************************\n"
        ;;
    2)
        specifyConfiguration
        echo "Starting Ambry-Frontend"
        java $JVM_DEBUG_OPTS $JVM_JMX_OPTS $JVM_MEM_OPTS $JVM_PARAS -classpath $CONF_DIR:$LIB_JARS  com.github.ambry.frontend.AmbryFrontendMain ${SYS_PROPERTIES} ${SYS_CLUSTER_PARA} > ${LOG_DIR}/stdout.out 2>&1 &
        watchBootstrap "Ambry-Frontend"
        echo -e "\n************************************************************************\n"
        ;;
    3)
        specifyConfiguration
        echo "Starting Ambry-Admin"
        java $JVM_DEBUG_OPTS $JVM_JMX_OPTS $JVM_MEM_OPTS $JVM_PARAS -classpath $CONF_DIR:$LIB_JARS  com.github.ambry.admin.AdminMain ${SYS_PROPERTIES} ${SYS_CLUSTER_PARA} > ${LOG_DIR}/stdout.out 2>&1 &
        watchBootstrap "Ambry-Admin"
        echo -e "\n************************************************************************\n"
        ;;
    esac
}

stopServer (){
    count=1
    pids=$1
    for var in $pids
    do
        echo "${count}. ${var}"
        count=`expr $count + 1`
    done
    if [ -n "$2" -a $count -gt 1 ]
    then
        echo -n "Please input the sequence number of the PID you want to stop: "
        read pid
        count=1
        for var in $pids
        do
            if [ $count -eq $pid ]
            then
                ret=`kill -9 "${var}"`
                echo $ret
            fi
            count=`expr $count + 1`
        done
    elif [ $count -lt 2 ]
    then
        echo "No Alive Ambry-Server exists!"
    fi
}

showServer () {
    echo ""
    echo "1. Ambry-Server"
    echo "2. Ambry-Frontend"
    echo "3. Ambry-Admin"
    echo -n "Your selection is(input 1,2 or 3):"
    read MODULE
    echo ""
    case $MODULE in
    1)
        pids=`ps -ef|grep ambry|grep "${DEPLOY_DIR}"|grep com.github.ambry.server.AmbryMain|awk '{print $2}'`
        echo -e "\n************************Current Ambry-Server Pids:************************\n"
        stopServer $pids $1
        echo -e "\n************************************************************************\n"
        ;;
    2)
        pids=`ps -ef|grep ambry|grep "${DEPLOY_DIR}"|grep com.github.ambry.frontend.AmbryFrontendMain|awk '{print $2}'`
        echo -e "\n************************Current Ambry-Frontend Pids:************************\n"
        stopServer $pids $1
        echo -e "\n************************************************************************\n"
        ;;
    3)
        pids=`ps -ef|grep ambry|grep "${DEPLOY_DIR}"|grep com.github.ambry.admin.AdminMain|awk '{print $2}'`
        echo -e "\n************************Current Ambry-Admin Pids:************************\n"
        stopServer $pids $1
        echo -e "\n************************************************************************\n"
        ;;
    esac
}


while [ 1 = 1 ]
do
    echo -e "\n************************Welcome to ambry!************************\n"
    echo "1. Boot a server"
    echo "2. Watch the server list in current host"
    echo "3. Stop a server"
    echo -n "Your selection is(input 1,2 or 3):"
    read SELECTION
    echo ""
    case $SELECTION in
    1)
        bootServer
        ;;
    2)
        showServer
        ;;
    3)
        showServer true
        ;;
    esac
done

