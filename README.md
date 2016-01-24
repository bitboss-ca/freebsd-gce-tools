FreeBSD Google Compute Engine Tools
===================================

This script will create a FreeBSD image suitable for booting in the Google Compute Engine (GCE).

Thanks to vascokk for the original Gist posted here: https://gist.github.com/vascokk/b17f8c59446399db5c97
Thanks to calomel.org for the zfs example posted here: https://calomel.org/zfs_freebsd_root_install.html

## Creating Images
Use the `create-image.sh` script to create images suitable for writing to GCE disks and booting into FreeBSD.  Run it with the -h switch for usage information.

### Keys
* If you provide only a public key, it will be added to .ssh/authorized_keys for the new user so that you can log in via ssh.
* If you provide both public and private keys, those keys will be installed under .ssh/ for the new user as well.

### Other Notes
* The script will use the current directory as a working directory.
* Note that you are not required to have the specified image size available as free space on your local hard drive.  The truncate(1) command "does not cause space to be allocated" unless written to.  This script only requires about 1GB to run.
* If you use ZFS, the above no longer applies; you will need to have the storage available for your specificed image size.

## Writing Images
Use any running *nix machine in the GCE to write your image to a new GCE disk.  If this is your first image, spin up an instance of debian, copy your new image to it, attach a new disk as big as your image target size, and write your image to the new disk.  Detach the new disk, and then you can create a new instance using your new disk.

**NOTE: The example commands below will _destroy data_ unless you are careful to specify the correct target device!
Simply write the image directly to a blank GCE disk, like so:
    
    gunzip [Image File] > [GCE Blank Disk]

Example for Debian or FreeBSD:

    sudo sh -c 'gunzip -c [TheImageFile.gz] > [Your device, e.g. /dev/daX]'
