#!/bin/sh

# run as root
if [ "$(id -u)" -ne 0 ]
then
    echo -e "\nthis script must be run with root privileges\n" >&2;
    exit 1; 
fi

# sync time if no RTC available to avoid TLS errors
chronyc makestep > /dev/null 2&>1
apk update

# rootless podman on diskless alpine linux requires fuse-ovlerlayfs
apk add fuse-overlayfs
echo fuse >> /etc/modules
modprobe fuse

# enable cgroups v2 - 'unified' allows 'podman stats'
# existing /etc/rc.conf will be backed up
read -r -p "enable cgroups v2? (allows 'podman stats') [Yes|No]:  " cgroups_version;
case $cgroups_version in
    Yes|yes|Y|y ) sed -i."$(date -I)".bak -r \
's/[# ]*rc_cgroup_mode=\"(legacy|hybrid|unified)\"/rc_cgroup_mode=\"unified\"/' \
/etc/rc.conf ;;

    * ) ;;
esac
rc-update add cgroups
rc-service cgroups start

# select user to setup subuid and subgid for rootless podman
# user will be created if account doesn't exist
echo
IFS= read -r -p "which user will be using podman?:  " podman_user;

if ! getent passwd "$podman_user" > /dev/null 2>&1
then
    read -r -p "$podman_user does not exist, create new account? [Yes|No]:  " response;
    case $response in
        Yes|yes|Y|y ) echo -e "\n*** creating user $podman_user ***\n";
              adduser -D -s /sbin/nologin "$podman_user";;
        * ) break;;
    esac
fi

if ! grep "$podman_user" /etc/subuid > /dev/null 2>&1
then
    echo "$podman_user":100000:65536 >> /etc/subuid
fi

if ! grep "$podman_user" /etc/subgid > /dev/null 2>&1
then
    echo "$podman_user":100000:65536 >> /etc/subgid
fi

# enable tun module
modprobe tun
echo tun >> /etc/modules

apk add podman

# set mount_program to fuse-overlayfs in /etc/containers/storage.conf
# existing /etc/containers/storage.conf will be backed up
sed -i."$(date -I)".bak -r \
's/^[# ]*mount_program = .+$/mount_program = \"\/usr\/bin\/fuse-overlayfs\"/' \
/etc/containers/storage.conf

# run test container with specified user
su -c 'podman run --rm quay.io/podman/hello' -s /bin/ash "$podman_user"
