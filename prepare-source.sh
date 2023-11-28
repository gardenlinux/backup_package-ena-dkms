#!/bin/bash
set -e
set -o pipefail

# - Set default variables
SOURCE_NAME="${SOURCE_NAME:-ena}"

# -- get latest version from upstream
latest_tag=$(git ls-remote --tags https://github.com/amzn/amzn-drivers.git \
  | grep -o 'refs/tags/ena_linux_[0-9]*\.[0-9]*\.[0-9]*' \
  | sort -V \
  | tail -n1 \
  | cut -d'/' -f3)

# -- set always to latest available upstream version
upstream_version=${latest_tag##*_}
echo "### Using upstream_version=$upstream_version"

# -- make sure we mark the package version to avoid potential conflicts with non-garden linux package versions
if [[ ${CI_MERGE_REQUEST_IID:-} ]]; then
    version="${upstream_version}-0gardenlinux~${CI_MERGE_REQUEST_IID}.${CI_PIPELINE_ID}.${CI_COMMIT_SHORT_SHA}"
else
    version="${upstream_version}-0gardenlinux~local"
fi


OUTPUT_DIR="_output"
PACKAGE_DIR="${OUTPUT_DIR}/${SOURCE_NAME}-${upstream_version}"
rm -rf ${OUTPUT_DIR}
mkdir -p ${PACKAGE_DIR}

# - Get upstream code
git clone --depth 1 --branch $latest_tag https://github.com/amzn/amzn-drivers.git "${PACKAGE_DIR}"

# -- Remove parts not relevant for garden linux ena dkms driver
echo "### reduce source package to ena only"
rm -rf ${PACKAGE_DIR}/userspace
rm -rf ${PACKAGE_DIR}/kernel/fbsd
rm -rf ${PACKAGE_DIR}/kernel/linux/efa
rm -rf ${PACKAGE_DIR}/kernel/linux/rpm
rm -rf ${PACKAGE_DIR}/.git
rm -f ${PACKAGE_DIR}/README.md

# -- Setup dkms.conf for ena
cp dkms.conf.template ${PACKAGE_DIR}/dkms.conf
sed -i "s/^PACKAGE_VERSION=\".*\"/PACKAGE_VERSION=\"$upstream_version\"/" ${PACKAGE_DIR}/dkms.conf

# - create orig tar
pushd "${OUTPUT_DIR}"
echo "### create orig tar"
tar -czf ${SOURCE_NAME}_${upstream_version}.orig.tar.gz ${SOURCE_NAME}-${upstream_version}
popd

# - Prepare Debian folder
echo "### prepare debian folder"
cp -R debian ${PACKAGE_DIR}

# - Prepare changelog
pushd "$PACKAGE_DIR"
echo "### create changelog"
if [[ ${CI_COMMIT_TAG:-} ]]; then
    dch --create --package "$SOURCE_NAME" --newversion "$version" --distribution gardenlinux --force-distribution -- \
        'Rebuild for Garden Linux.'
elif [[ ${CI_MERGE_REQUEST_IID:-} ]]; then
    dch --create --package "$SOURCE_NAME" --newversion "$version" --distribution UNRELEASED --force-distribution -- \
        'Rebuild for Garden Linux.' \
        "Snapshot from merge request ${CI_MERGE_REQUEST_IID}."
else
    dch --create --package "$SOURCE_NAME" --newversion "$version" --distribution UNRELEASED --force-distribution -- \
        'Rebuild for Garden Linux.' \
        "Local development}."
fi
popd

# - create debian source packages
pushd "$PACKAGE_DIR"
echo "### create source package"
dpkg-buildpackage -us -uc -S -nc -d
popd 

