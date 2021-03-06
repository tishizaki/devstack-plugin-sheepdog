# DevStack extras script to install Sheepdog

# Dependencies:
#
# - ``functions`` file
# - ``cinder`` configurations
# - ``SHEEPDOG_DATA_DIR`` or ``DATA_DIR`` must be defined

# ``stack.sh`` calls the entry points in this order (via ``extras.d/60-sheepdog.sh``):
#
# - install_sheepdog
# - configure_sheepdog
# - init_sheepdog
# - start_sheepdog
# - stop_sheepdog
# - cleanup_sheepdog

# Defaults
# --------

# Set ``SHEEPDOG_DATA_DIR`` to the location of Sheepdog drives and objects.
# Default is the common DevStack data directory.
SHEEPDOG_DATA_DIR=${SHEEPDOG_DATA_DIR:-${DATA_DIR}/sheepdog}
SHEEPDOG_DISK_IMAGE=${SHEEPDOG_DATA_DIR}/drives/images/sheepdog.img

# DevStack will create a loop-back disk formatted as XFS to store the
# Sheepdog data. Set ``SHEEPDOG_LOOPBACK_DISK_SIZE`` to the disk size in
# kilobytes.
# Default is 8 gigabyte.
SHEEPDOG_LOOPBACK_DISK_SIZE_DEFAULT=8G
SHEEPDOG_LOOPBACK_DISK_SIZE=${SHEEPDOG_LOOPBACK_DISK_SIZE:-$SHEEPDOG_LOOPBACK_DISK_SIZE_DEFAULT}

# Functions
# ------------

# check_os_support_sheepdog() - Check if the operating system provides a decent version of Sheepdog
function check_os_support_sheepdog {
    if [[ ! ${DISTRO} =~ (trusty) && ! ${DISTRO} =~ (xenial) ]]; then
        echo "WARNING: your distro $DISTRO does not provide (at least) the Firefly release. Please use Ubuntu Trusty or Xenial."
        if [[ "$FORCE_SHEEPDOG_INSTALL" != "yes" ]]; then
            die $LINENO "If you wish to install Sheepdog on this distribution anyway run with FORCE_SHEEPDOG_INSTALL=yes"
        fi
        NO_UPDATE_REPOS=False
    fi
}

# stop_sheepdog() - Stop running processes (non-screen)
function stop_sheepdog {
    stop_process sheepdog

    if egrep -q ${SHEEPDOG_DATA_DIR} /proc/mounts; then
        sudo umount ${SHEEPDOG_DATA_DIR}
    fi
}

# cleanup_sheepdog() - Remove residual data files, anything left over from previous
# runs that a clean run would need to clean up
function cleanup_sheepdog {
    stop_sheepdog

    if [[ -e ${SHEEPDOG_DISK_IMAGE} ]]; then
        sudo rm -f ${SHEEPDOG_DISK_IMAGE}
    fi
    uninstall_package sheepdog > /dev/null 2>&1
}

# configure_sheepdog() - Set config files, create data dirs, etc
function configure_sheepdog {
    # create a backing file disk
    create_disk ${SHEEPDOG_DISK_IMAGE} ${SHEEPDOG_DATA_DIR} ${SHEEPDOG_LOOPBACK_DISK_SIZE}
    sudo chown -R ${STACK_USER}: ${SHEEPDOG_DATA_DIR}
}

# install_sheepdog() - Collect source and prepare
function install_sheepdog {
    if [[ ${os_CODENAME} =~ trusty || ${os_CODENAME} =~ xenial ]]; then
        NO_UPDATE_REPOS=False
        install_package sheepdog
        install_package xfsprogs
    else
        exit_distro_not_supported "Sheepdog since your distro doesn't provide (at least) the Firefly release. Please use Ubuntu Trusty or Xenial."
    fi
}

# start_sheepdog() - Start running processes, including screen
function start_sheepdog {
    if [[ ${DISTRO} =~ (trusty) ]]; then
        run_process sheepdog "sheep -f -o -l 7 -c local -n ${SHEEPDOG_DATA_DIR}"
    elif [[ ${DISTRO} =~ (xenial) ]]; then
        run_process sheepdog "sheep -l dst=stdout,level=debug,format=server -c local -n ${SHEEPDOG_DATA_DIR}"
    else
        exit_distro_not_supported "Sheepdog since your distro doesn't provide (at least) the Firefly release. Please use Ubuntu Trusty or Xenial."
    fi

    sleep 3

    dog cluster format -c 1
}

# configure_cinder_backend_sheepdog - Configure Cinder for Sheepdog backends
function configure_cinder_backend_sheepdog {
    local be_name=$1
    iniset $CINDER_CONF $be_name volume_backend_name $be_name
    iniset $CINDER_CONF $be_name volume_driver "cinder.volume.drivers.sheepdog.SheepdogDriver"

    # NOTE(yamada-h):
    # Sheepdog driver is marked as unsupported at Jan 2017.
    # We will remove this config after the driver is supported.
    iniset $CINDER_CONF $be_name enable_unsupported_driver true
}

function configure_sheepdog_glance {
    iniset $GLANCE_API_CONF DEFAULT show_image_direct_url true
    iniset $GLANCE_API_CONF sheepdog default_store sheepdog
    iniset $GLANCE_API_CONF sheepdog stores file,http,sheepdog
    iniset $GLANCE_API_CONF sheepdog sheepdog_store_address 127.0.0.1
}

if [[ "$1" == "source" ]]; then
    # Initial source
    source $TOP_DIR/lib/sheepdog
elif [[ "$1" == "stack" && "$2" == "install" ]]; then
    echo_summary "Installing Sheepdog"
    check_os_support_sheepdog
    install_sheepdog
elif [[ "$1" == "stack" && "$2" == "post-config" ]]; then
    echo_summary "Configuring Sheepdog"
    configure_sheepdog
    configure_sheepdog_glance

    # We need to have Sheepdog started before the main OpenStack components.
    start_sheepdog
fi

if [[ "$1" == "unstack" ]]; then
    stop_sheepdog
fi

if [[ "$1" == "clean" ]]; then
    cleanup_sheepdog
fi

## Local variables:
## mode: shell-script
## End:
