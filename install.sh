#!/bin/bash

filepath=$(cd "$(dirname "$0")"; pwd)
host_ip=`ip addr show dev eth0|egrep 'inet '|egrep -o '([0-9]{1,}\.){3}[0-9]{1,}'|awk -F '' 'NR==1{print}'`
if [[ ${host_ip}x == x ]];then
	host_ip=`ip addr show dev ens160|egrep 'inet '|egrep -o '([0-9]{1,}\.){3}[0-9]{1,}'|awk -F '' 'NR==1{print}'`
fi

#update yum repodata
sudo yum makecache fast

#install required packages
sudo yum install -y yum-utils \
  device-mapper-persistent-data \
  lvm2 \
  wget \
  ansible \
  git

#config yum resource
sudo yum-config-manager -y \
    --add-repo \
    https://download.docker.com/linux/centos/docker-ce.repo

#install docker-ce
sudo yum install -y docker-ce

#start docker 
sudo systemctl start docker
sudo systemctl enable docker

#pull jenkins docker iamge
sudo docker pull jenkins

#run jenkins
DOCKER_NAME=tmp_jenkins
JENKINS_HOME="/jenkins_home"
sudo mkdir -p ${JENKINS_HOME}
sudo chmod 777 ${JENKINS_HOME}
sudo docker run -d --name=${DOCKER_NAME} -p 8899:8080 -p 50000:50000 -v ${JENKINS_HOME}:/var/jenkins_home jenkins
sleep 30
OCKER_ID=`sudo docker ps --filter name=${DOCKER_NAME} -q`
JENKINS_USER=admin
JENKINS_PASSWD=`cat ${JENKINS_HOME}/secrets/initialAdminPassword`

#页面配置
echo "************************"
echo "请访问 http://${host_ip}:8899 登录并初始配置化后再继续"
echo "登录密码: ${JENKINS_PASSWD}"
echo "************************"

#等待继续
sleep 10
read -p "页面初始化是否完成？(yes/no)" answer
if [[ ${answer} != yes  ]];then
	sudo docker stop ${DOCKER_ID}
	sudo docker rm ${DOCKER_ID}
	exit 0
fi

#install jenkins cli
cd ${JENKINS_HOME} && sudo wget http://${host_ip}:8899/jnlpJars/jenkins-cli.jar

cd ${filepath} && git clone https://github.com/xcl001987/nginx-test.git
cp ${filepath}/nginx-test/test_job_config.xml /${JENKINS_HOME}
cp ${filepath}/nginx-test/test.yml /${JENKINS_HOME}
sed -i "s/10.82.12.62/${host_ip}/" /${JENKINS_HOME}/test_job_config.xml

#create job
DOCKER_ID=`sudo docker ps --filter name=${DOCKER_NAME} -q`
(sudo docker exec -i -w /var/jenkins_home ${DOCKER_ID} java -jar jenkins-cli.jar -auth ${JENKINS_USER}:${JENKINS_PASSWD} -s http://${host_ip}:8899/ create-job test) < /${JENKINS_HOME}/test_job_config.xml

#create docker ssh key
docker exec -ti ${DOCKER_ID} bash -c "ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa"
sudo mkdir -p ~/.ssh && sudo chmod 700 ~/.ssh
(docker exec -ti ${DOCKER_ID} bash -c "cat ~/.ssh/id_rsa.pub") >> ~/.ssh/authorized_keys
sudo chmod 600 ~/.ssh/authorized_keys

#create ansible inventory file
cat << EOF > /jenkins_home/ansible_hosts.txt
[dev]
127.0.0.1
[prod]
127.0.0.1
EOF
