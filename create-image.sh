#!/bin/sh

# Stop for errors
set -e

# Usage Message
usage() {
	echo "
	Usage: # ${0} [options]
		-h This help
		-k Path to public key for new user.  Will be added to authorized_keys so you can log in.  Required.
		-K Path to private key.  Implies install public and private keys for new user.
		-p Password for new user.  Default: passw0rd.
		-r Release of FreeBSD to use.  Default: 10.2-RELEASE
		-s Image size.  Specify units as G or M.  Default: 2G.
		-w Swap size.  Specify in same units as Image size.  Added to image size.  Default none.
		-u Username for new user.  Default: gceuser.
		-z Use ZFS filesystem.
		"
}

# Show usage if no parameters
if [ -z $1 ]; then
	usage
	exit 0
fi

# Defaults
IMAGESIZE='2G'
SWAPSIZE=''
DEVICEID=''
RELEASE='10.2-RELEASE'
RELEASEDIR=''
TMPMNTPNT=''
TMPCACHE=''
TMPMNTPREFIX='freebsd-gce-tools-tmp'
NEWUSER='gceuser'
NEWPASS='passw0rd'
PUBKEYFILE=''
PRIKEYFILE=''
USEZFS=''
FILETYPE='UFS'

# Switches
while getopts ":hk:K:p:r:s:w:u:z" opt; do
  case $opt in
    h)
      usage
      exit 0
      ;;
    k)
      PUBKEYFILE="${OPTARG}"
      ;;
    K)
			PRIKEYFILE="${OPTARG}"
			;;
    p)
      NEWPASS="${OPTARG}"
      ;;
    r)
      RELEASE="${OPTARG}"
      ;;
    s)
      IMAGESIZE="${OPTARG}"
      ;;
    w)
      SWAPSIZE="${OPTARG}"
      ;;
    u)
      NEWUSER="${OPTARG}"
      ;;
    z)
      USEZFS='YES'
      FILETYPE='ZFS'
      ;;
    \?)
      echo "Invalid option: -${OPTARG}" >&2
      exit 1
      ;;
    :)
      echo "Option -${OPTARG} requires an argument." >&2
      exit 1
      ;;
  esac
done
shift $((OPTIND-1))


# Infrastructure Checks
echo " "
if [ -n "${PRIKEYFILE}" ] && [ -z "${PUBKEYFILE}" ]; then
	echo "If you provide a private key file, a public key file is also required."
	usage
	exit 1
fi
if [ -z "${PUBKEYFILE}" ]; then
	echo "A public key file is required.  You will need this key to log in to your instance when you launch it."
	usage
	exit 1
fi
if [ ! -f "${PUBKEYFILE}" ]; then
	echo "Cannot read public key file: ${PUBKEYFILE}"
	usage
	exit 1
fi
if [ -z "${PUBKEYFILE}" ] && [ ! -f "${PRIKEYFILE}" ]; then
	echo "Cannot read private key file: ${PRIKEYFILE}"
	usage
	exit 1
fi
if [ -z "${NEWUSER}" ]; then
	echo "New username for the image cannot be empty."
	usage
	exit 1
fi
if [ -z "${NEWPASS}" ]; then
	echo "New password for the image cannot be empty."
	usage
	exit 1
fi

# Check for root credentials
if [ `whoami` != "root" ]; then
	echo "Execute as root only!"
	exit 1
fi

# Size Setup
if [ -n "${SWAPSIZE}" ]; then
	IMAGEUNITS=$( echo "${IMAGESIZE}" | sed 's/[0-9.]//g' )
	SWAPUNITS=$( echo "${SWAPSIZE}" | sed 's/[0-9.]//g' )
	if [ "$IMAGEUNITS" != "$SWAPUNITS" ]; then
		echo "Image size and swap size units must match, e.g. 10G, 2G.";
		exit 1
	fi
	IMAGENUM=$( echo "${IMAGESIZE}" | sed 's/[a-zA-Z]//g' )
	echo "Image: ${IMAGENUM}"
	SWAPNUM=$( echo "${SWAPSIZE}" | sed 's/[a-zA-Z]//g' )
	echo "Swap: ${SWAPNUM}"
	TOTALSIZE=$(( ${IMAGENUM} + ${SWAPNUM} ))"${IMAGEUNITS}"
	echo "Size: ${IMAGESIZE} + ${SWAPSIZE} = ${TOTALSIZE}";
else
	TOTALSIZE=$IMAGESIZE
fi

# Create The Image
echo "Creating image..."
truncate -s $TOTALSIZE temporary.img

# Get a device ID for the image
DEVICEID=$( mdconfig -a -t vnode -f temporary.img )

# Create a temporary mount point
TMPMNTPNT=$( mktemp -d "/tmp/${TMPMNTPREFIX}.XXXXXXXX" )

if [ $USEZFS ]; then

	TMPCACHE=$( mktemp -d "/tmp/${TMPMNTPREFIX}.XXXXXXXX" )


	echo "Creating ZFS boot root partitions..."
	gpart create -s gpt ${DEVICEID}
	gpart add -a 4k -s 512k -t freebsd-boot ${DEVICEID}
	gpart add -a 4k -t freebsd-zfs -l root0 ${DEVICEID}
	gpart bootcode -b /boot/pmbr -p /boot/gptzfsboot -i 1 ${DEVICEID}

	echo "Creating zroot pool..."
	#gnop create -S 4096 /dev/${DEVICEID}
	#zpool create -o altroot=${TMPMNTPNT} -o cachefile=${TMPCACHE}/zpool.cache zroot /dev/${DEVICEID}.nop
	zpool create -o altroot=${TMPMNTPNT} -o cachefile=${TMPCACHE}/zpool.cache zroot /dev/${DEVICEID}
	zpool export zroot
	#gnop destroy /dev/${DEVICEID}.nop
	zpool import -o altroot=${TMPMNTPNT} -o cachefile=${TMPCACHE}/zpool.cache zroot
	mount | grep zroot


	echo "Setting ZFS properties..."
	zpool set bootfs=zroot zroot
	# zpool set listsnapshots=on zroot
	# zpool set autoreplace=on zroot
	# #zpool set autoexpand=on zroot
	# zfs set checksum=fletcher4 zroot
	# zfs set compression=lz4 zroot
	# zfs set atime=off zroot
	# zfs set copies=2 zroot
	# #zfs set mountpoint=/ zroot

	if [ -n "${SWAPSIZE}" ]; then
		echo "# Adding swap space..."
		zfs create -V ${SWAPSIZE} zroot/swap
		zfs set org.freebsd:swap=on zroot/swap
	fi

	# Add the extra component to the path for root
	TMPMNTPNT="${TMPMNTPNT}/zroot"

else

	# Partition the image
	echo "Adding partitions..."
	gpart create -s gpt /dev/${DEVICEID}
	echo -n "Adding boot: "
	gpart add -s 222 -t freebsd-boot -l boot0 ${DEVICEID}
	echo -n "Adding root: "
	gpart add -t freebsd-ufs -s ${IMAGESIZE} -l root0 ${DEVICEID}
	gpart bootcode -b /boot/pmbr -p /boot/gptboot -i 1 ${DEVICEID}
	if [ -n "${SWAPSIZE}" ]; then
		echo -n "Adding swap: "
		gpart add -t freebsd-swap -l swap0 ${DEVICEID}
	fi

	# Create and mount file system
	echo "Creating and mounting filesystem..."
	newfs -U /dev/${DEVICEID}p2
	mount /dev/${DEVICEID}p2 ${TMPMNTPNT}

fi

# Fetch FreeBSD into the image
RELEASEDIR="FETCH_${RELEASE}"
mkdir -p ${RELEASEDIR}
if [ ! -f ${RELEASEDIR}/base.txz ]; then
	echo "Fetching base..."
	fetch -q -o ${RELEASEDIR}/base.txz http://ftp.freebsd.org/pub/FreeBSD/releases/amd64/${RELEASE}/base.txz < /dev/tty
fi
echo "Extracting base..."
tar -C ${TMPMNTPNT} -xpf ${RELEASEDIR}/base.txz < /dev/tty
if [ ! -f ${RELEASEDIR}/doc.txz ]; then
	echo "Fetching doc..."
	fetch -q -o ${RELEASEDIR}/doc.txz http://ftp.freebsd.org/pub/FreeBSD/releases/amd64/${RELEASE}/doc.txz < /dev/tty
fi
echo "Extracting doc..."
tar -C ${TMPMNTPNT} -xpf ${RELEASEDIR}/doc.txz < /dev/tty
if [ ! -f ${RELEASEDIR}/games.txz ]; then
	echo "Fetching games..."
	fetch -q -o ${RELEASEDIR}/games.txz http://ftp.freebsd.org/pub/FreeBSD/releases/amd64/${RELEASE}/games.txz < /dev/tty
fi
echo "Extracting games..."
tar -C ${TMPMNTPNT} -xpf ${RELEASEDIR}/games.txz < /dev/tty
if [ ! -f ${RELEASEDIR}/kernel.txz ]; then
	echo "Fetching kernel..."
	fetch -q -o ${RELEASEDIR}/kernel.txz http://ftp.freebsd.org/pub/FreeBSD/releases/amd64/${RELEASE}/kernel.txz < /dev/tty
fi
echo "Extracting kernel..."
tar -C ${TMPMNTPNT} -xpf ${RELEASEDIR}/kernel.txz < /dev/tty
if [ ! -f ${RELEASEDIR}/lib32.txz ]; then
	echo "Fetching lib32..."
	fetch -q -o ${RELEASEDIR}/lib32.txz http://ftp.freebsd.org/pub/FreeBSD/releases/amd64/${RELEASE}/lib32.txz < /dev/tty
fi
echo "Extracting lib32..."
tar -C ${TMPMNTPNT} -xpf ${RELEASEDIR}/lib32.txz < /dev/tty




if [ $USEZFS ]; then
	echo "Configuring for ZFS..."
	cp ${TMPCACHE}/zpool.cache ${TMPMNTPNT}/boot/zfs/zpool.cache

	# echo ""
	# echo "# Setup ZFS root mount and boot"
	# echo 'zfs_enable="YES"' >> ${TMPMNTPNT}/etc/rc.conf
	# echo 'zfs_load="YES"' >> ${TMPMNTPNT}/loader.conf
	# echo 'vfs.root.mountfrom="zfs:zroot"' >> ${TMPMNTPNT}/boot/loader.conf

cat >> $TMPMNTPNT/etc/rc.conf << __EOF__
# ZFS On Root
zfs_enable="YES"
__EOF__

# Setup ZFS root mount and boot
cat >> $TMPMNTPNT/loader.conf << __EOF__
# ZFS On Root
zfs_load="YES"
__EOF__

# Setup ZFS root mount and boot
cat >> $TMPMNTPNT/boot/loader.conf << __EOF__
# ZFS On Root
vfs.root.mountfrom="zfs:zroot"
__EOF__

	# echo ""
	# echo "# use gpt ids instead of gptids or disks idents"
	# echo 'kern.geom.label.disk_ident.enable="0"' >> ${TMPMNTPNT}/boot/loader.conf

cat >> $TMPMNTPNTboot/loader.conf << __EOF__
# ZFS On Root: use gpt ids instead of gptids or disks idents
kern.geom.label.disk_ident.enable="0"
__EOF__

	# echo 'kern.geom.label.gpt.enable="1"' >> ${TMPMNTPNT}/boot/loader.conf
	# echo 'kern.geom.label.gptid.enable="0"' >> ${TMPMNTPNT}/boot/loader.conf

cat >> $TMPMNTPNTboot/boot/loader.conf << __EOF__
# ZFS on Root: use gpt ids instead of gptids or disks idents
kern.geom.label.gpt.enable="1"
kern.geom.label.gptid.enable="0"
__EOF__


fi


# Configure the new image for new user
echo "Creating ${NEWUSER} and home dir..."
echo $NEWPASS | pw -V $TMPMNTPNT/etc useradd -h 0 -n $NEWUSER -c $NEWUSER -s /bin/csh -m
pw -V $TMPMNTPNT/etc groupmod wheel -m $NEWUSER
NEWUSER_UID=`pw -V $TMPMNTPNT/etc usershow $NEWUSER | cut -f 3 -d :`
NEWUSER_GID=`pw -V $TMPMNTPNT/etc usershow $NEWUSER | cut -f 4 -d :`
NEWUSER_HOME=$TMPMNTPNT/home/$NEWUSER
mkdir -p $NEWUSER_HOME
chown $NEWUSER_UID:$NEWUSER_GID $NEWUSER_HOME

# Set SSH authorized keys && optionally install key pair
echo "Setting authorized ssh key for ${NEWUSER}..."
mkdir $NEWUSER_HOME/.ssh
chmod -R 700 $NEWUSER_HOME/.ssh
cat "${PUBKEYFILE}" > $NEWUSER_HOME/.ssh/authorized_keys
chmod 644 $NEWUSER_HOME/.ssh/authorized_keys
if [ -n "${PRIKEYFILE}" ]; then
	echo "Installing ssh key pair for ${NEWUSER}..."
	cp "${PUBKEYFILE}" $NEWUSER_HOME/.ssh/
	chmod 644 $NEWUSER_HOME/.ssh/$( basename "${PUBKEYFILE}" )
	cp "${PRIKEYFILE}" $NEWUSER_HOME/.ssh/
	chmod 600 $NEWUSER_HOME/.ssh/$( basename "${PRIKEYFILE}" )
fi
chown -R $NEWUSER_UID:$NEWUSER_GID $NEWUSER_HOME/.ssh

# Config File Changes
echo "Configuring image for GCE..."

### Create a Local etc
mkdir $TMPMNTPNT/usr/local/etc

### /etc/fstab
if [ $USEZFS ]; then
	# touch the /etc/fstab else freebsd will not boot properly"
	touch $TMPMNTPNT/etc/fstab
else
cat >> $TMPMNTPNT/etc/fstab << __EOF__
/dev/da0p2	/			ufs		rw,noatime,suiddir	1	1
__EOF__
if [ -n $SWAPSIZE ]; then
cat >> $TMPMNTPNT/etc/fstab << __EOF__
/dev/da0p3	none	swap	sw									0	0
__EOF__
	fi
fi

### /boot.config
echo -Dh > $TMPMNTPNT/boot.config

### /boot/loader.conf
cat >> $TMPMNTPNT/boot/loader.conf << __EOF__
# GCE Console
console="comconsole"
# No Boot Delay
autoboot_delay="0"
__EOF__

### /etc/rc.conf
cat > $TMPMNTPNT/etc/rc.conf << __EOF__
console="comconsole"
hostname="freebsd"
ifconfig_vtnet0="DHCP"
ntpd_enable="YES"
ntpd_sync_on_start="YES"
sshd_enable="YES"
__EOF__

### /etc/ssh/sshd_config
/usr/bin/sed -Ei.original 's/^#UseDNS yes/UseDNS no/' $TMPMNTPNT/etc/ssh/sshd_config
/usr/bin/sed -Ei '' 's/^#UsePAM yes/UsePAM no/' $TMPMNTPNT/etc/ssh/sshd_config

### /etc/ntp.conf > /usr/local/etc/ntp.conf
cp $TMPMNTPNT/etc/ntp.conf $TMPMNTPNT/usr/local/etc/ntp.conf
/usr/bin/sed -Ei.original 's/^server/#server/' $TMPMNTPNT/usr/local/etc/ntp.conf
cat >> $TMPMNTPNT/etc/ntp.conf << __EOF__
# GCE NTP Server
server 169.254.169.254 burst iburst
__EOF__

### /etc/dhclient.conf
cat >> $TMPMNTPNT/etc/dhclient.conf << __EOF__
# GCE DHCP Client
interface "vtnet0" {
  supersede subnet-mask 255.255.0.0;
}
__EOF__

### /etc/rc.local
cat > $TMPMNTPNT/etc/rc.local << __EOF__
# GCE MTU
ifconfig vtnet0 mtu 1460
__EOF__

### Time Zone
chroot $TMPMNTPNT /bin/sh -c 'ln -s /usr/share/zoneinfo/America/Vancouver /etc/localtime'

# Finish up
echo "Detaching image..."
if [ $USEZFS ]; then
	zfs unmount zroot
	zpool export zroot
else
	umount $TMPMNTPNT
fi
mdconfig -d -u ${DEVICEID}

# Name the image
echo "Compressing image..."
mv temporary.img FreeBSD-GCE-${RELEASE}-${FILETYPE}.img
gzip FreeBSD-GCE-${RELEASE}-${FILETYPE}.img
shasum FreeBSD-GCE-${RELEASE}-${FILETYPE}.img.gz > FreeBSD-GCE-${RELEASE}-${FILETYPE}.img.gz.sha

echo "Done."
