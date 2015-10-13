FreeBSD Google Compute Engine Tools
===================================

This script will create a FreeBSD image suitable for booting in the Google Compute Engine (GCE).

Thanks to vascokk for the original Gist posted here: https://gist.github.com/vascokk/b17f8c59446399db5c97

## Creating Images
Use the script to create images suitable for writing to GCE disks and booting into FreeBSD.  Run it with the -h switch for usage information.

### Keys
* If you provide only a public key, it will be added to .ssh/authorized_keys for the new user so that you can log in via ssh.
* If you provide both public and private keys, those keys will be installed under .ssh/ for the new user as well.

### Other Notes
* The script will use the current directory as a working directory.
* Note that you are not required to have the specified image size available as free space on your local hard drive.  The truncate(1) command "does not cause space to be allocated" unless written to.  This script only requires about 1GB to run.

## Writing Images
**NOTE: The example commands below will _destroy data_ unless you are careful to specify the correct target device!
Simply write the image directly to a blank GCE disk, like so:
gzcat [Image File] > [GCE Blank Disk]

DEBIAN or FreeBSD: sudo sh -c 'gunzip -c [TheImageFile.gz] > [Your device, e.g. /dev/sdb]'