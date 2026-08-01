SET UP THE PROJECT IN DE10 SYSFS
->
# Write the bit-compressed qof file (rbf) from the project directory to the 
# /lib/firmware directory of the soc linux fs. 
quartus_cpf -c -o bitstream_compression=on fpga_project_file.sof fpga_program.rbf
# Impotant notes: do this before mounting the configfs. Otherwise the kernel will not
# update the firmware on the fpga fabric.
# In this case -> moving rbf onto the soc through ssh
scp fpga_project_file.sof root@DE10_IP:/lib/firmware/
## Mount the configfs, make the bridging overlay and write it to the kernel's device-tree
mount -t configfs none /sys/kernel/config 2>/dev/null
mkdir /sys/kernel/config/device-tree/overlays/brg
#Where brg.dts is 
/dts-v1/;
/plugin/;
/ {
    fragment@0 {
        target = <&fpga_bridge0>;
        __overlay__ {
            status = "okay";
        };
    };
};
dtc -@ -O dtb -o /root/brg.dtbo /root/brg.dts
cat /root/brg.dtbo > /sys/kernel/config/device-tree/overlays/brg/dtbo
## Check the status of the bridge (expected disabled)
cat /sys/class/fpga_bridge/br0/state
# Create the overlay for the firmware that runs the 
mkdir /sys/kernel/config/device-tree/overlays/fw
#Where fw.dts is 
/dts-v1/;
/plugin/;
/ {
    fragment@0 {
        target-path = "/soc/base_fpga_region";
        #address-cells = <1>;
        #size-cells = <1>;
        __overlay__ {
            #address-cells = <1>;
            #size-cells = <1>;
            firmware-name = "fpga_program.rbf";
            fpga-bridges = <&fpga_bridge0>;
        };
    };
};
# Sets the firmware binary for the kernel to program onto the fpga fabric as file "fpga_program.rbf" 
#taken by kernel from /lib/firmware
dtc -@ -O dtb -o /root/fw.dtbo /root/fw.dts
cat /root/fw.dtbo > /sys/kernel/config/device-tree/overlays/fw/dtbo
# Check if operating and if bridge is enabled
cat /sys/class/fpga_manager/fpga0/state
cat /sys/class/fpga_bridge/br0/state