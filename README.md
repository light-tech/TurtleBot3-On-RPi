# Set up TurtleBot3 SBC in 5 minutes

[The official instruction](https://emanual.robotis.com/docs/en/platform/turtlebot3/sbc_setup/#sbc-setup) to set up the TurtleBot3 SBC takes a very long time to complete for many reasons:

 1. You have to `sudo apt upgrade` and then `sudo apt install` a ton of packages.
 2. It is inefficient to build the `turtlebot3` packages on the Raspberry Pi. The instruction might not even work for you even: In our case (Raspberry Pi 3B+), `colcon` hangs after about 3 minutes and only passes it after we add the swap file (so we probably did not have sufficient RAM).
 3. It is bad if you have to reflash the OS or have multiple SD cards and redo everything over and over again due to small mistakes here and there.

So we prebuild ROS2 `humble` basic packages and `turtlebot3` packages so that we can simply download, unpack, run a couple of commands on the Raspberry Pi and you are ready to launch the robot.

## Install prebuilt ROS2 turtlebot3 packages on Raspberry Pi

_Assumptions_: [Burn **Ubuntu 22.04** image](https://roboticsbackend.com/install-ubuntu-on-raspberry-pi-without-monitor/) (the instruction is for Ubuntu 20.04 but it works for 22.04 as well) which should come with **Python 3.10** (i.e. it must match the Python version on our build machine).

To use the prebuilt ROS2 on your Raspberry Pi, SSH to the Pi and

 1. First, temporarily give yourself the write permission to `/usr/local` with
    ```shell
    sudo chmod ugo+w /usr/local
    ```

    It is unfortunate that paths are hard-coded in the build process so we cannot use a path that is local at the user's home unless everyone agrees to use the same user name.

 2. Create a Python virtual environment at `/usr/local/ros2pythonenv` and install the required packages
    ```shell
    python3.10 -m venv /usr/local/ros2pythonenv
    source /usr/local/ros2pythonenv/bin/activate
    pip3 install packaging pyyaml lark==1.1.1
    ```

    If you need to run `ros2 topic`, you will need `numpy` and `netifaces` which requires `sudo apt install gcc python3-dev`. We don't need that to launch the robot.

 3. [Download our prebuilt archive](https://github.com/light-tech/TurtleBot3-On-RPi/releases/download/v1.0/tb3.tar.xz), extract with `tar xJf` and move the content to `/usr/local`.

    The archive is created using our script [`build_tb3_rpi.sh`](build_tb3_rpi.sh) on [a Debian 11 virtual machine on macOS](https://github.com/light-tech/Debian-on-macOS).

 4. Setup udev rules to access the OpenCR via USB

    ```shell
    sudo cp /usr/local/ros2/share/turtlebot3_bringup/script/99-turtlebot3-cdc.rules /etc/udev/rules.d/
    sudo udevadm control --reload-rules
    sudo udevadm trigger
    ```

    Restart the device after this so that it can take effect.
 
**Note**: You still need to [setup OpenCR](https://emanual.robotis.com/docs/en/platform/turtlebot3/opencr_setup/#opencr-setup) and your PC (if needed, see [our other repo](https://github.com/light-tech/ROS2-On-iOS) for easy ROS2 setup on a Mac).

## Launch the TurtleBot3

One should put the commands in step 1 and 2 in your `~/.bashrc` so we can go to step 3 in subsequent launch.

 1. Activate python environment and source the ROS2 setup:
    ```shell
    source /usr/local/ros2pythonenv/bin/activate
    source /usr/local/ros2/setup.bash
    ```

 2. Setup the required environment variables
    ```shell
    export ROS_DOMAIN_ID=30
    export LDS_MODEL=LDS-01
    export TURTLEBOT3_MODEL=waffle_pi
    export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
    export LD_LIBRARY_PATH=/usr/local/ros2deps/lib:/usr/local/ros2deps/lib/aarch64-linux-gnu:$LD_LIBRARY_PATH
    ```

 3. Bring up the TurtleBot with
    ```shell
    ros2 launch turtlebot3_bringup robot.launch.py
    ```
    and if you want to stream the camera, do
    ```shell
    ros2 run camera_ros camera_node
    ```
