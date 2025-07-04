
#!/usr/bin/bash
# -----------------------------------------------------------------------------------------
#  Example Installation Script Template
#  
#  This convenience script encapsulates command-line instructions highlighted in
#  an OpenHPC Install Guide that can be used as a starting point to perform a local
#  cluster install beginning with bare-metal. Necessary inputs that describe local
#  hardware characteristics, desired network settings, and other customizations
#  are controlled via a companion input file that is used to initialize variables 
#  within this script.
#   
#  Please see the OpenHPC Install Guide(s) for more information regarding the
#  procedure. Note that the section numbering included in this script refers to
#  corresponding sections from the companion install guide.
# -----------------------------------------------------------------------------------------
#

# Update system
yum update -y

# Set local vars

inputFile="input.local"

if [ ! -e ${inputFile} ];then
   echo "Error: Unable to access local input file -> ${inputFile}"
   exit 1
else
   . ${inputFile} || { echo "Error sourcing ${inputFile}"; exit 1; }
fi


# Set hostname
echo ${sms_ip} ${sms_name} >> /etc/hosts

# ---------------------------- Begin OpenHPC Recipe ---------------------------------------
# Commands below are extracted from an OpenHPC install guide recipe and are intended for 
# execution on the master SMS host.
# -----------------------------------------------------------------------------------------

# Disable firewall 
systemctl disable firewalld
systemctl stop firewalld

yum install -y http://repos.openhpc.community/OpenHPC/3/EL_9/x86_64/ohpc-release-3-1.el9.x86_64.rpm
yum install -y dnf-plugins-core
yum config-manager --set-enabled crb

# Verify OpenHPC repository has been enabled before proceeding

yum repolist | grep -q OpenHPC
if [ $? -ne 0 ];then
   echo "Error: OpenHPC repository must be enabled locally"
   exit 1
fi


# ------------------------------------------------------------
# Add baseline OpenHPC and provisioning services (Section 3.3)
# ------------------------------------------------------------
yum -y install ohpc-base
yum -y install ohpc-warewulf

# Enable NTP services on SMS host
systemctl enable chronyd.service
echo "local stratum 10" >> /etc/chrony.conf
echo "server ${ntp_server}" >> /etc/chrony.conf
echo "allow 172.30.0.0/16" >> /etc/chrony.conf
systemctl restart chronyd

# -------------------------------------------------------------
# Add resource management services on master node (Section 3.4)
# -------------------------------------------------------------
yum -y install ohpc-slurm-server
cp /etc/slurm/slurm.conf.ohpc /etc/slurm/slurm.conf
cp /etc/slurm/cgroup.conf.example /etc/slurm/cgroup.conf
perl -pi -e "s/SlurmctldHost=\S+/SlurmctldHost=${sms_name}/" /etc/slurm/slurm.conf

# ----------------------------------------
# Update node configuration for slurm.conf
# ----------------------------------------
if [[ ${update_slurm_nodeconfig} -eq 1 ]];then
     perl -pi -e "s/^NodeName=.+$/#/" /etc/slurm/slurm.conf
     perl -pi -e "s/^PartitionName=.+$/#/" /etc/slurm/slurm.conf
     echo -e ${slurm_node_config} >> /etc/slurm/slurm.conf
     for i in "${!cpu_name[@]}"; do
        echo "NodeName=${cpu_name[$i]} Sockets=2 CoresPerSocket=6 ThreadsPerCore=1 State=UNKNOWN" >> /etc/slurm/slurm.conf
     done
     for i in "${!gpu_name[@]}"; do
        echo "NodeName=${gpu_name[$i]} Sockets=1 CoresPerSocket=8 ThreadsPerCore=2 State=UNKNOWN" >> /etc/slurm/slurm.conf
     done
     echo "PartitionName=cpu Nodes=cpu[1-${#cpu_name[@]}] Default=NO MaxTime=UNLIMITED State=UP Oversubscribe=EXCLUSIVE" >> /etc/slurm/slurm.conf
     echo "PartitionName=gpu Nodes=gpu[1-${#gpu_name[@]}] Default=NO MaxTime=UNLIMITED State=UP Oversubscribe=EXCLUSIVE" >> /etc/slurm/slurm.conf
fi

# -----------------------------------------------------------
# Complete basic Warewulf setup for master node (Section 3.7)
# -----------------------------------------------------------
perl -pi -e "s/device = eth1/device = ${sms_eth_internal}/" /etc/warewulf/provision.conf
ip link set dev ${sms_eth_internal} up
ip address add ${sms_ip}/${internal_netmask} broadcast + dev ${sms_eth_internal}
systemctl enable httpd.service
systemctl restart httpd
systemctl enable dhcpd.service
systemctl enable tftp.socket
systemctl start tftp.socket
if [ ! -z ${BOS_MIRROR+x} ]; then
     export YUM_MIRROR=${BOS_MIRROR}
fi

# -------------------------------------------------
# Create compute image for Warewulf (Section 3.8.1)
# -------------------------------------------------
export CHROOT=/opt/ohpc/admin/images/rocky9.2
wwmkchroot -v rocky-9 $CHROOT
dnf -y --installroot $CHROOT install epel-release
cp -p /etc/yum.repos.d/OpenHPC*.repo $CHROOT/etc/yum.repos.d

# ------------------------------------------------------------
# Add OpenHPC base components to compute image (Section 3.8.2)
# ------------------------------------------------------------
yum -y --installroot=$CHROOT install ohpc-base-compute

# -------------------------------------------------------
# Add OpenHPC components to compute image (Section 3.8.2)
# -------------------------------------------------------
cp -p /etc/resolv.conf $CHROOT/etc/resolv.conf
# Add SLURM and other components to compute instance
\cp /etc/passwd /etc/group  $CHROOT/etc
yum -y --installroot=$CHROOT install ohpc-slurm-client
chroot $CHROOT systemctl enable munge
echo SLURMD_OPTIONS="--conf-server ${sms_ip}" > $CHROOT/etc/sysconfig/slurmd
yum -y --installroot=$CHROOT install chrony
echo "server ${sms_ip} iburst" >> $CHROOT/etc/chrony.conf
yum -y --installroot=$CHROOT install kernel-`uname -r`
yum -y --installroot=$CHROOT install lmod-ohpc

#
# ----------------------------------------------
# Customize system configuration (Section 3.8.3)
# ----------------------------------------------
wwinit database
wwinit ssh_keys
echo "${sms_ip}:/home /home nfs nfsvers=4,nodev,nosuid 0 0" >> $CHROOT/etc/fstab
echo "${sms_ip}:/opt/ohpc/pub /opt/ohpc/pub nfs nfsvers=4,nodev 0 0" >> $CHROOT/etc/fstab
echo "/home *(rw,no_subtree_check,fsid=10,no_root_squash)" >> /etc/exports
echo "/opt/ohpc/pub *(ro,no_subtree_check,fsid=11)" >> /etc/exports
if [[ ${enable_intel_packages} -eq 1 ]];then
     mkdir /opt/intel
     echo "/opt/intel *(ro,no_subtree_check,fsid=12)" >> /etc/exports
     echo "${sms_ip}:/opt/intel /opt/intel nfs nfsvers=4,nodev 0 0" >> $CHROOT/etc/fstab
fi
exportfs -a
systemctl restart nfs-server
systemctl enable nfs-server

# -----------------------------------------
# Additional customizations (Section 3.8.4)
# -----------------------------------------

# Enable slurm pam module
# echo "account    required     pam_slurm.so" >> $CHROOT/etc/pam.d/sshd

# -------------------------------------------------------
# Configure rsyslog on SMS and computes (Section 3.8.4.7)
# -------------------------------------------------------
echo 'module(load="imudp")' >> /etc/rsyslog.d/ohpc.conf
echo 'input(type="imudp" port="514")' >> /etc/rsyslog.d/ohpc.conf
systemctl restart rsyslog
echo "*.* @${sms_ip}:514" >> $CHROOT/etc/rsyslog.conf
echo "Target=\"${sms_ip}\" Protocol=\"udp\"" >> $CHROOT/etc/rsyslog.conf
perl -pi -e "s/^\*\.info/\\#\*\.info/" $CHROOT/etc/rsyslog.conf
perl -pi -e "s/^authpriv/\\#authpriv/" $CHROOT/etc/rsyslog.conf
perl -pi -e "s/^mail/\\#mail/" $CHROOT/etc/rsyslog.conf
perl -pi -e "s/^cron/\\#cron/" $CHROOT/etc/rsyslog.conf
perl -pi -e "s/^uucp/\\#uucp/" $CHROOT/etc/rsyslog.conf

# ------------------------------------------------------
# Configure Nagios on SMS and computes (Section 3.8.4.8)
# ------------------------------------------------------

. generate-nagios-config.sh

if [[ ${enable_nagios} -eq 1 ]];then
     # Install Nagios on master and vnfs image
     yum -y install --skip-broken nagios nrpe nagios-plugins-*
     yum -y --installroot=$CHROOT install nrpe nagios-plugins-ssh
     chroot $CHROOT systemctl enable nrpe
     perl -pi -e "s/^allowed_hosts=/# allowed_hosts=/" $CHROOT/etc/nagios/nrpe.cfg
     echo "nrpe : ${sms_ip}  : ALLOW"    >> $CHROOT/etc/hosts.allow
     echo "nrpe : ALL : DENY"            >> $CHROOT/etc/hosts.allow
     cp compute.cfg /etc/nagios/objects
     echo "cfg_file=/etc/nagios/objects/compute.cfg" >> /etc/nagios/nagios.cfg
     perl -pi -e "s/ \/bin\/mail/ \/usr\/bin\/mailx/g" /etc/nagios/objects/commands.cfg
     perl -pi -e "s/nagios\@localhost/root\@${sms_name}/" /etc/nagios/objects/contacts.cfg
     echo command[check_ssh]=/usr/lib64/nagios/plugins/check_ssh localhost $CHROOT/etc/nagios/nrpe.cfg
     htpasswd -bc /etc/nagios/passwd nagiosadmin ${nagios_web_password}
     systemctl enable nagios
     systemctl start nagios
     chmod u+s `which ping`
fi

if [[ ${enable_clustershell} -eq 1 ]];then
     # Install clustershell
     yum -y install clustershell
     cd /etc/clustershell/groups.d
     mv local.cfg local.cfg.orig
     echo "adm: ${sms_name}" > local.cfg
     echo "compute: cpu[1-4],gpu[1-4]" >> local.cfg
     echo "all: @adm,@compute" >> local.cfg
fi

if [[ ${enable_magpie} -eq 1 ]];then
     # Install magpie
     yum -y install magpie-ohpc
fi

# Enable nhc and configure (health check)
yum -y install nhc-ohpc
yum -y --installroot=$CHROOT install nhc-ohpc

echo "HealthCheckProgram=/usr/sbin/nhc" >> /etc/slurm/slurm.conf
echo "HealthCheckInterval=300" >> /etc/slurm/slurm.conf  # execute every five minutes

# It might be necessary to reinstall perl if "Could not find syscall.ph", if so, run:
yum install -y perl

# ----------------------------
# Import files (Section 3.8.5)
# ----------------------------
wwsh file import /etc/passwd -y
wwsh file import /etc/group -y
wwsh file import /etc/shadow  -y
wwsh file import /etc/munge/munge.key

# --------------------------------------
# Assemble bootstrap image (Section 3.9)
# --------------------------------------
export WW_CONF=/etc/warewulf/bootstrap.conf
echo "drivers += updates/kernel/" >> $WW_CONF
wwbootstrap `uname -r`
# Assemble VNFS
wwvnfs --chroot $CHROOT


# Add hosts to cluster
echo "GATEWAYDEV=${eth_provision}" > /tmp/network.$$
wwsh -y file import /tmp/network.$$ --name network
wwsh -y file set network --path /etc/sysconfig/network --mode=0644 --uid=0

# Re-assign ip just in case
ip address add ${sms_ip}/${internal_netmask} broadcast + dev ${sms_eth_internal}
systemctl restart dhcpd

for ((i=0; i<${#cpu_name[@]}; i++)); do
    wwsh -y node new "${cpu_name[$i]}" --ipaddr="${cpu_ip[$i]}" --hwaddr="${cpu_mac[$i]}" -D ${eth_provision}
    wwsh provision set --postnetdown=1 "${cpu_name[$i]}" -y
    wwsh provision set "${cpu_name[$i]}" --vnfs=rocky9.2 --bootstrap=`uname -r` --files=dynamic_hosts,passwd,group,shadow,munge.key,network -y
done

for ((i=0; i<${#gpu_name[@]}; i++)); do
    wwsh -y node new "${gpu_name[$i]}" --ipaddr="${gpu_ip[$i]}" --hwaddr="${gpu_mac[$i]}" -D ${eth_provision}
    wwsh provision set --postnetdown=1 "${gpu_name[$i]}" -y
    wwsh provision set "${gpu_name[$i]}" --vnfs=rocky9.2 --bootstrap=`uname -r` --files=dynamic_hosts,passwd,group,shadow,munge.key,network -y
done


systemctl restart dhcpd
wwsh pxe update

wwvnfs --chroot $CHROOT

# Optionally, add arguments to bootstrap kernel
for i in "${!gpu_name[@]}"; do
    if [[ ${enable_kargs} -eq 1 ]]; then
        wwsh -y provision set "${gpu_name[$i]}" --kargs="${kargs}"
    fi
done

for i in "${!cpu_name[@]}"; do
    if [[ ${enable_kargs} -eq 1 ]]; then
        wwsh -y provision set "${cpu_name[$i]}" --kargs="${kargs}"
    fi
done

cd

echo "\n\nDone! Boot compute nodes and once they are up, run stage2.sh. Use status.sh to check on the nodes."
