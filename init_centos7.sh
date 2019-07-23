#!/bin/bash

# Author: Euphie
# date:2019-05-28
# des: system_init_shell
# version: 1.0

if [[ "$(whoami)" != "root" ]]; then
    echo "please run this script as root ." >&2
    exit 1
fi

#set network interface to ONBOOT=YES
set_network()
{
    sed -i '/ONBOOT/s#no#yes#' /etc/sysconfig/network-scripts/ifcfg-${IF_NAME}
    /etc/init.d/network restart
}

restart_sshd()
{
    service sshd restart
}

#install system pack
init_yum(){
    yum -y install wget net-tools lrzsz gcc gcc-c++ make cmake libxml2-devel openssl-devel curl curl-devel unzip sudo ntp libaio-devel wget vim ncurses-devel autoconf automake zlib-devel  python-devel
    yum -y install epel-release
}

#set ntp
init_zone_time()
{
    cp  /usr/share/zoneinfo/Asia/Hong_Kong  /etc/localtime
    echo 'ZONE="Asia/Hong_Kong"\nUTC=false\nARC=false' > /etc/sysconfig/clock
    /usr/sbin/ntpdate pool.ntp.org
    echo "* */5 * * * /usr/sbin/ntpdate pool.ntp.org > /dev/null 2>&1" > /var/spool/cron/root;chmod 600 /var/spool/cron/root
    echo 'LANG="en_US.UTF-8"' > /etc/sysconfig/i18n
    source  /etc/sysconfig/i18n
}

#set ulimit
init_ulimit_config()
{
    echo "ulimit -SHn 102400" >> /etc/rc.local
    cat >> /etc/security/limits.conf << EOF
 *           soft   nofile       102400
 *           hard   nofile       102400
 *           soft   nproc        102400
 *           hard   nproc        102400
EOF
}

#set ssh
init_sshd_config()
{
    sed -i 's/^GSSAPIAuthentication yes$/GSSAPIAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/#UseDNS yes/UseDNS no/' /etc/ssh/sshd_config
    systemctl start crond
}

#set sysctl
init_sysctl_config()
{
    cat > /etc/sysctl.conf << EOF
net.ipv4.ip_forward = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.default.accept_source_route = 0
kernel.sysrq = 0
kernel.core_uses_pid = 1
net.ipv4.tcp_syncookies = 1
kernel.msgmnb = 65536
kernel.msgmax = 65536
kernel.shmmax = 68719476736
kernel.shmall = 4294967296
net.ipv4.tcp_max_tw_buckets = 6000
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_rmem = 4096 87380 4194304
net.ipv4.tcp_wmem = 4096 16384 4194304
net.core.wmem_default = 8388608
net.core.rmem_default = 8388608
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.netdev_max_backlog = 262144
net.ipv4.tcp_max_orphans = 3276800
net.ipv4.tcp_max_syn_backlog = 262144
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_synack_retries = 1
net.ipv4.tcp_syn_retries = 1
net.ipv4.tcp_tw_recycle = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_mem = 94500000 915000000 927000000
net.ipv4.tcp_fin_timeout = 1
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.ip_local_port_range = 1024 65535
EOF
    /sbin/sysctl -p
}

#disable selinux
init_selinux_config()
{
    sed -i '/SELINUX/s/enforcing/disabled/' /etc/selinux/config
    setenforce 0
}

init_iptables_config()
{
    systemctl stop firewalld.service
    systemctl disable firewalld.service
    yum install iptables-services -y
    cat > /etc/sysconfig/iptables << EOF
# Firewall configuration written by system-config-securitylevel
# Manual customization of this file is not recommended.
*filter
:INPUT DROP [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:syn-flood - [0:0]
-A INPUT -i lo -j ACCEPT
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT
-A INPUT -p tcp -m state --state NEW -m tcp --dport 80 -j ACCEPT
-A INPUT -p icmp -m limit --limit 100/sec --limit-burst 100 -j ACCEPT
-A INPUT -p icmp -m limit --limit 1/s --limit-burst 10 -j ACCEPT
-A INPUT -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -j syn-flood
-A INPUT -j REJECT --reject-with icmp-host-prohibited
-A syn-flood -p tcp -m limit --limit 3/sec --limit-burst 6 -j RETURN
-A syn-flood -j REJECT --reject-with icmp-port-unreachable
COMMIT
EOF
    sleep 1
    /sbin/service iptables restart
}

init_ipvs()
{
    cat > /etc/sysconfig/modules/ipvs.modules << EOF
#!/bin/bash
modprobe -- ip_vs
modprobe -- ip_vs_rr
modprobe -- ip_vs_wrr
modprobe -- ip_vs_sh
modprobe -- nf_conntrack_ipv4
EOF
    chmod 755 /etc/sysconfig/modules/ipvs.modules
    /etc/sysconfig/modules/ipvs.modules
}

set_host_name()
{
    cat > /etc/hosts << EOF
127.0.0.1   localhost ${HOST_NAME} ${HOST_NAME}.euphie.me
::1         localhost ${HOST_NAME} ${HOST_NAME}.euphie.me
EOF
    cat > /etc/hostname << EOF
${HOST_NAME}
EOF
    hostnamectl set-hostname ${HOST_NAME}
}

disable_firewall()
{
    systemctl stop firewalld.service
    systemctl disable firewalld.service
    systemctl stop iptables.service
    systemctl disable iptables.service
}

update_kernel()
{
    rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
    rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-2.el7.elrepo.noarch.rpm
    yum --enablerepo=elrepo-kernel install kernel-ml -y
}

install_docker()
{
    init_selinux_config
    disable_firewall
    mkdir /etc/docker/
    yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
    yum install -y docker-ce
    cat > /etc/docker/daemon.json << EOF
{
    "bip": "10.10.9.1/24",
    "default-gateway": "10.10.9.2",
    "fixed-cidr": "10.10.9.100/26",
    "registry-mirrors": ["https://26en6bei.mirror.aliyuncs.com"],
    "insecure-registries": ["harbor.euphie.me:60200"]
}
EOF
    systemctl start docker
    systemctl enable docker
}

install_k8s()
{
    init_selinux_config
    disable_firewall
    cat > /etc/yum.repos.d/kubernetes.repo << EOF
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
exclude=kube*
EOF
    yum -y repolist
    yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
    cat > /etc/sysctl.d/k8s.conf << EOF
vm.swappiness=0
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
    sysctl --system
    swapoff -a
    sed -i 's?/dev/mapper/centos-swap?#/dev/mapper/centos-swap?' /etc/fstab
    if [ "$ROLE" = "master" ] ; then
        kubeadm init --pod-network-cidr=10.244.0.0/16 --service-cidr=10.96.0.0/12 --image-repository=gcr.azk8s.cn/google_containers
        kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
    fi
}

# chmod +x init_centos7.sh && ./init_centos7.sh init_system && ./init_centos7.sh install_docker && ./init_centos7.sh install_k8s
help()
{
    echo "Usage: $0
    init_system|
    init_yum|
    init_zone_time|
    init_ulimit_config|
    init_sshd_config|
    init_sysctl_config|
    init_selinux_config|
    init_iptables_config|
    init_ipvs|
    set_host_name [host_name]|
    install_docker|
    install_k8s [role]"
}

init_system()
{
    echo -e "\033[31m This is a centos7 system initialization script, please run carefully! It will start execution after 5 seconds! Press Ctrl+C to cancel. \033[0m"
    # sleep 5
    init_yum
    init_zone_time
    init_ulimit_config
    init_sshd_config
    init_sysctl_config
    init_selinux_config
    init_iptables_config
    init_ipvs
    set_host_name
}

if [ "$1" = "set_network" ] ; then
    IF_NAME="${2:-ens33}"
fi

if [ "$1" = "set_host_name" ] ; then
    HOST_NAME="${2:-vm}"
fi

if [ "$1" = "install_k8s" ] ; then
    ROLE="${2:-node}"
fi

if [ "$1" = "" ] || [ "$1" = "init_system" ] ; then
    HOST_NAME="${2:-vm}"
fi

${1:-help}