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
		-r Release of FreeBSD to use.  Default: 10.1-RELEASE
		-s Image size.  Specify units as G or M.  Default: 2G.
		-w Swap size.  Specify in same units as Image size.  Subtracted from usable image size.  Default none.
		-u Username for new user.  Default: gceuser.
		"
}

# Check for root credentials
if [ `whoami` != "root" ]; then
	echo "Execute as root only!"
	exit 1
fi

# Defaults
IMAGESIZE='2G'
SWAPSIZE=''
DEVICEID=''
RELEASE='10.1-RELEASE'
RELEASEDIR=''
TMPMNTPNT=''
NEWUSER='gceuser'
NEWPASS='passw0rd'
PUBKEYFILE=''
PRIKEYFILE=''

# Switches
while getopts ":hk:K:p:r:s:w:u:" opt; do
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

# Size Setup
if [ -n "${SWAPSIZE}" ]; then
	IMAGEUNITS=$( echo "${IMAGESIZE}" | sed 's/[0-9.]//g' )
	SWAPUNITS=$( echo "${SWAPSIZE}" | sed 's/[0-9.]//g' )
	if [ "$IMAGEUNITS" != "$SWAPUNITS" ]; then
		echo "Image size and swap size units must match, e.g. 10G, 2G.";
		exit 1
	fi
fi

# Create The Image
echo "Creating image..."
truncate -s $IMAGESIZE temporary.img

# Get a device ID for the image
DEVICEID=$( mdconfig -a -t vnode -f temporary.img )

# Create a temporary mount point
TMPMNTPNT=$( mktemp -d /tmp/freebsd-img-mnt.XXXXXXXX )

# Partition the image
echo "Adding partitions..."
gpart create -s gpt /dev/${DEVICEID}
gpart add -s 222 -t freebsd-boot -l boot0 ${DEVICEID}
if [ -n "${SWAPSIZE}" ]; then
	gpart add -t freebsd-swap -s ${SWAPSIZE} -l swap0 ${DEVICEID}
fi
gpart add -t freebsd-ufs -l root0 ${DEVICEID}
gpart bootcode -b /boot/pmbr -p /boot/gptboot -i 1 ${DEVICEID}

# Create and mount file system
echo "Creating and mounting filesystem..."
newfs -U /dev/${DEVICEID}p2
mount /dev/${DEVICEID}p2 ${TMPMNTPNT}

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

### /etc/fstab
if [ -n $SWAPSIZE ]; then
cat >> $TMPMNTPNT/etc/fstab << __EOF__
/dev/da0p2	none	swap	sw									0	0
/dev/da0p3	/			ufs		rw,noatime,suiddir	1	1
__EOF__
else
cat >> $TMPMNTPNT/etc/fstab << __EOF__
/dev/da0p2	/			ufs		rw,noatime,suiddir	1	1
__EOF__
fi

### /boot.config
echo -Dh > $TMPMNTPNT/boot.config

### /boot/loader.conf
cat >> $TMPMNTPNT/boot/loader.conf << __EOF__
# GCE Console
console="comconsole"
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

### /etc/ntp.conf
/usr/bin/sed -Ei.original 's/^server/#server/' $TMPMNTPNT/etc/ntp.conf
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
umount $TMPMNTPNT
mdconfig -d -u ${DEVICEID}

# Name the image
echo "Compressing image..."
mv temporary.img FreeBSD-GCE-$RELEASE.img
gzip FreeBSD-GCE-$RELEASE.img
shasum FreeBSD-GCE-$RELEASE.img.gz > FreeBSD-GCE-$RELEASE.img.gz.sha

echo "Done."
