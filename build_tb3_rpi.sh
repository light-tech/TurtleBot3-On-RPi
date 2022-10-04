# Build ROS2 core and turtlebot3 packages for distribution
#
# This script should be run on efficient build machine such as an Google Cloud aarch64-linux-gnu VM or your own qemu.
#
# Assumptions:
#
#  1. The build machine has Python 3.10 installed (to match with the current python version distributed on Ubuntu 22.04 image).
#  2. If you install Python from source, you must overwrite any existing Python in `/usr` i.e. run `./configure --prefix=/usr --enable-optimizations && make -j 4 && sudo make install`.
#  3. Remove other Python executable such as `/usr/bin/python3.9`.
#     CMake seems to default to latest-known Python in `/usr/bin`.
#  4. Ensure that you have CMake 3.23 (but not 3.24) as earlier version won't be able to find Python 3.10 due to hard-coded available versions.
#  5. Ideally, we would like to put everything at `$HOME` but ROS2 hard-coded many paths.
#     So to make things portable, we are to put everything under `/usr/local` instead.
#     In particular, we
#       * create a Python environment at `/usr/local/ros2pythonenv`
#       * build and install the dependencies such as Boost at `/usr/local/ros2deps`
#       * install the ROS2 and turtlebot3 packages at `/usr/local/ros2`
#     But to do this without `sudo`, we need to temporarily change permission of `/usr/local` on the build machine to 777.

ros2_install_path=/usr/local/ros2               # These paths are hard-coded by colcon so we use a location that is common to all users /usr/local
ros2_deps_install_path=/usr/local/ros2deps
ros2_python_venv_path=/usr/local/ros2pythonenv

ros2_ws_path=$HOME/ros2_ws                      # Where to put the workspace
deps_src_path=$HOME/deps                        # Where to download and extract source archives

preparePythonVirtualEnvironment() {
    python3.10 -m venv $ros2_python_venv_path
    source $ros2_python_venv_path/bin/activate
    test -f requirements.txt || curl -L -o requirements.txt https://raw.githubusercontent.com/light-tech/ROS2-On-iOS/main/requirements.txt
    python3 -m pip install -r requirements.txt
}

buildBoost() {
    export CFLAGS="-fPIC -isystem /usr/include/python3.10/"
    export CXXFLAGS="-fPIC -isystem /usr/include/python3.10/"

    cd $deps_src_path
    test -f boost.tar.gz || curl -L -o boost.tar.gz https://boostorg.jfrog.io/artifactory/main/release/1.80.0/source/boost_1_80_0.tar.gz
    tar xzf boost.tar.gz
    cd boost_1_80_0
    ./bootstrap.sh --prefix=$ros2_deps_install_path
    ./b2 install
    cd ..

    export CFLAGS=
    export CXXFLAGS=
}

copySystemLibs() {
    cp /usr/lib/aarch64-linux-gnu/libssl.so.1.1 $ros2_deps_install_path/lib/
    cp /usr/lib/aarch64-linux-gnu/libcrypto.so.1.1 $ros2_deps_install_path/lib/
    cp /usr/lib/aarch64-linux-gnu/libtinyxml2.so.8 $ros2_deps_install_path/lib/
}

buildLibCamera() {
    source $ros2_python_venv_path/bin/activate
    cd $deps_src_path
    # sudo apt install cmake pkg-config meson libyaml-dev python3-yaml python3-ply python3-jinja2
    pip3 install meson jinja2 ply pyyaml
    git clone https://git.libcamera.org/libcamera/libcamera.git
    cd libcamera
    meson build --prefix $ros2_deps_install_path
    ninja -C build install
}

buildExif() {
    cd $deps_src_path
    test -f libexif.zip || curl -L -o libexif.zip https://github.com/libexif/libexif/releases/download/v0.6.24/libexif-0.6.24.zip
    unzip libexif.zip
    cd libexif-0.6.24
    ./configure --prefix=$ros2_deps_install_path
    make && make install
}

buildJpeg() {
    cd $deps_src_path
    test -f libjpeg.tar.gz || curl -L -o libjpeg.tar.gz http://www.ijg.org/files/jpegsrc.v9e.tar.gz
    tar xzf libjpeg.tar.gz
    cd jpeg-9e
    ./configure --prefix=$ros2_deps_install_path
    make && make install
}

buildTiff() {
    cd $deps_src_path
    test -f libtiff.tar.gz || curl -L -o libtiff.tar.gz http://download.osgeo.org/libtiff/tiff-4.4.0.tar.gz
    tar xzf libtiff.tar.gz
    cd tiff-4.4.0
    ./configure --prefix=$ros2_deps_install_path
    make && make install
}

buildPng() {
    cd $deps_src_path
    test -f libpng.tar.gz || curl -L -o libpng.tar.gz https://download.sourceforge.net/libpng/libpng-1.6.38.tar.gz
    tar xzf libpng.tar.gz
    cd libpng-1.6.38
    ./configure --prefix=$ros2_deps_install_path
    make && make install
}

buildLibCameraApps() {
    cd $deps_src_path
    test -d libcamera-apps || git clone https://github.com/raspberrypi/libcamera-apps.git
    cd libcamera-apps
    sed -i.bak "s,\(project.*\),\1\ninclude_directories(\"$ros2_deps_install_path/include\" SYSTEM)\nlink_directories(\"$ros2_deps_install_path/lib\"),g" CMakeLists.txt
    export PKG_CONFIG_PATH=$ros2_deps_install_path/lib/aarch64-linux-gnu/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig
    mkdir build
    cd build
    cmake .. -DENABLE_X11=0 -DENABLE_QT=0 -DENABLE_OPENCV=0 -DENABLE_TFLITE=0 -DENABLE_DRM=0 -DCMAKE_INSTALL_PREFIX=$ros2_deps_install_path -DCMAKE_PREFIX_PATH=$ros2_deps_install_path -DBOOST_INCLUDEDIR=$ros2_deps_install_path/include -DBOOST_LIBRARYDIR=$ros2_deps_install_path/lib
    cmake --build . --target install
}

buildOpenCV() {
    cd $deps_src_path
    test -f opencv-4.6.0.zip || curl -L https://github.com/opencv/opencv/archive/4.6.0.zip -o opencv-4.6.0.zip
    unzip opencv-4.6.0.zip
    cd opencv-4.6.0
    mkdir build
    cd build
    cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$ros2_deps_install_path ..
    make -j7
    make install
}

prepareWorkspaceSource() {
    mkdir -p $ros2_ws_path/src
    cd $ros2_ws_path

    test -f ros2.repos || curl -L -o ros2.repos https://raw.githubusercontent.com/ros2/ros2/humble/ros2.repos
    test -f tb3.repos || curl -L -o tb3.repos https://raw.githubusercontent.com/light-tech/TurtleBot3-On-RPi/main/tb3.repos
    vcs import src < ros2.repos
    vcs import src < tb3.repos

    # Force disable packages such as `eclipse-cyclonedds`, `eclipse-iceoryx`, `rviz`, `turtlebot3_cartographer` and `turtlebot3_navigation2` and others

    touch src/eclipse-cyclonedds/AMENT_IGNORE \
        src/eclipse-iceoryx/AMENT_IGNORE \
        src/ros-visualization/AMENT_IGNORE \
        src/ros2/rmw_connextdds/AMENT_IGNORE \
        src/ros2/rmw_cyclonedds/AMENT_IGNORE \
        src/ros2/rviz/AMENT_IGNORE \
        src/tb3/turtlebot3/turtlebot3_cartographer/AMENT_IGNORE \
        src/tb3/turtlebot3/turtlebot3_navigation2/AMENT_IGNORE
}

buildWorkspace() {
    # Should build about 154 packages in total
    cd $ros2_ws_path
    export PKG_CONFIG_PATH=$ros2_deps_install_path/lib/aarch64-linux-gnu/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig
    colcon build --install-base $ros2_install_path --merge-install \
        --packages-up-to turtlebot3_bringup camera_ros ros2cli ros2pkg ros2run ros2topic ros2launch \
        --cmake-force-configure \
        --cmake-args -DBUILD_TESTING=NO -DTHIRDPARTY=FORCE -DCOMPILE_TOOLS=NO -DFORCE_BUILD_VENDOR_PKG=ON -DBUILD_MEMORY_TOOLS=OFF -DRCL_LOGGING_IMPLEMENTATION=rcl_logging_noop -DCV_BRIDGE_ENABLE_PYTHON=OFF -DCMAKE_PREFIX_PATH=$ros2_deps_install_path
}

createArchive() {
    tar cJf tb3.tar.xz $ros2_deps_install_path $ros2_install_path
}

test -d $ros2_python_venv_path || preparePythonVirtualEnvironment
source $ros2_python_venv_path/bin/activate

buildBoost
buildLibCamera
buildExif
buildJpeg
buildTiff
buildPng
buildLibCameraApps
buildOpenCV
copySystemLibs

prepareWorkspaceSource
buildWorkspace

createArchive
