#!/bin/bash

host_ip=`ip addr show dev eth0|egrep 'inet '|egrep -o '([0-9]{1,}\.){3}[0-9]{1,}'|awk -F '' 'NR==1{print}'`
if [[ ${host_ip}x == x ]];then
	host_ip=`ip addr show dev ens160|egrep 'inet '|egrep -o '([0-9]{1,}\.){3}[0-9]{1,}'|awk -F '' 'NR==1{print}'`
fi

#update yum repodata
sudo yum makecache fast

#remove docker
#sudo yum remove -y docker \
#                   docker-client \
#                   docker-client-latest \
#                   docker-common \
#                   docker-latest \
#                   docker-latest-logrotate \
#                   docker-logrotate \
#                   docker-selinux \
#                   docker-engine-selinux \
#                   docker-engine

#install required packages
sudo yum install -y yum-utils \
  device-mapper-persistent-data \
  lvm2 \
  wget \
  ansible

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

#create job config.xml
cat << EOF > /${JENKINS_HOME}/test_job_config.xml
<?xml version='1.0' encoding='UTF-8'?>
<project>
  <actions/>
  <description></description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <hudson.model.ParametersDefinitionProperty>
      <parameterDefinitions>
        <hudson.model.ChoiceParameterDefinition>
          <name>env</name>
          <description></description>
          <choices class="java.util.Arrays$ArrayList">
            <a class="string-array">
              <string>dev</string>
              <string>prod</string>
            </a>
          </choices>
        </hudson.model.ChoiceParameterDefinition>
      </parameterDefinitions>
    </hudson.model.ParametersDefinitionProperty>
  </properties>
  <scm class="hudson.plugins.git.GitSCM" plugin="git@3.8.0">
    <configVersion>2</configVersion>
    <userRemoteConfigs>
      <hudson.plugins.git.UserRemoteConfig>
        <url>https://github.com/xcl001987/nginx-test.git</url>
      </hudson.plugins.git.UserRemoteConfig>
    </userRemoteConfigs>
    <branches>
      <hudson.plugins.git.BranchSpec>
        <name>*/master</name>
      </hudson.plugins.git.BranchSpec>
    </branches>
    <doGenerateSubmoduleConfigurations>false</doGenerateSubmoduleConfigurations>
    <submoduleCfg class="list"/>
    <extensions/>
  </scm>
  <canRoam>true</canRoam>
  <disabled>false</disabled>
  <blockBuildWhenDownstreamBuilding>false</blockBuildWhenDownstreamBuilding>
  <blockBuildWhenUpstreamBuilding>false</blockBuildWhenUpstreamBuilding>
  <triggers/>
  <concurrentBuild>false</concurrentBuild>
  <builders>
    <hudson.tasks.Shell>
      <command>ssh -o stricthostkeychecking=no root@10.82.12.62 &quot;cd /jenkins_home/workspace/${JOB_NAME} &amp;&amp; docker build -t nginx:${BUILD_NUMBER} .&quot;
ssh -o stricthostkeychecking=no root@10.82.12.62 &quot;ansible-playbook -i ~/ansible_hosts.txt -e host_group=${env} -e version=${BUILD_NUMBER} ~/test.yml&quot;</command>
    </hudson.tasks.Shell>
  </builders>
  <publishers/>
  <buildWrappers/>
</project>
EOF
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
cat << EOF > ~/ansible_hosts.txt
[dev]
127.0.0.1
[prod]
127.0.0.1
EOF

#create ansible playbook file
cat << EOF > ~/test.yml
- hosts: '{{host_group}}'
  tasks:
    - name: 'stop docker'
      shell: "docker_id=`docker ps --filter name='nginx-test' -q` && (docker stop ${docker_id} || exit 0) && sleep 10" 
    - name: 'run docker'
      shell: 'docker run -d --name=nginx-test -p 9999:80 nginx:{{version}}'
...
EOF

