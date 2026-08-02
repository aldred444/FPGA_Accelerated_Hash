# FPGA Hash-Search Accelerator — FNV-1a Preimage Search (Cyclone V SoC)

A hardware-accelerated brute-force preimage search for the FNV-1a hash, built on
the Terasic DE10-Nano (Intel Cyclone V SoC, `5CSEBA6U23I7`). A custom RTL core
sweeps the 4-character lowercase keyspace (26⁴ = 456,976 candidates), evaluating
**one candidate per clock cycle**, and is driven from Linux on the ARM HPS over
the lightweight HPS-to-FPGA bridge via a memory-mapped register interface.

## What it does

- `fnv1a_core.v` — sequential search engine. Each clock cycle it derives a
  4-char candidate from a running index, computes the full 4-round FNV-1a hash
  combinationally, and compares against the target. On a match it latches
  `match_idx`, raises `found`/`done`, and halts.
- `fnv1a_slave.v` — Avalon-MM slave wrapping the core. Register map:

  | Word addr | Name    | Dir   | Meaning                    |
  |-----------|---------|-------|----------------------------|
  | 0         | TARGET  | write | target hash to search for  |
  | 1         | CONTROL | write | bit0 = start pulse         |
  | 2         | STATUS  | read  | bit0 = done, bit1 = found  |
  | 3         | RESULT  | read  | matching candidate index   |

- `fnv1a_slave_hw.tcl` — packages the slave as a custom Platform Designer
  component so it drops onto the lightweight bridge in Qsys.
- `tle.v` — top-level wrapper instantiating the HPS (`soc_system`) and FPGA-side
  glue.

## Architecture notes (accurate scope)

- **Throughput:** one candidate evaluated per clock cycle at the 50 MHz fabric
  clock (~50M candidates/s). This is a *single-lane* search — one hash datapath,
  sequential index sweep — not a parallel or multi-lane design. Replicated lanes
  over disjoint index ranges (with priority-encoded result aggregation) and a
  pipelined hash datapath are the obvious next steps; on this device the DSP
  budget (112 blocks / 8 per lane) caps replication at roughly a dozen lanes
  before ALMs become the limit.
- **Datapath:** the four chained 32-bit FNV multiplies map to DSP blocks (8 DSPs
  used); the per-cycle hash is a single combinational block rather than a
  registered pipeline, which bounds Fmax.
- **Integration:** the accelerator is bridge-attached, so it has no top-level
  pins — it lives inside the Qsys system and is reached purely through the memory
  map. (The `operand*/result` PIOs in `tle.v` are the initial adder bring-up
  path, retained from early integration.)

## Resource / timing (Quartus 20.1 Lite, rev1)

- Logic: 4,554 / 41,910 ALMs (11%)
- DSP: 8 / 112 (7%)
- Registers: 4,808
- Fabric clock: 50 MHz, timing closed

## Verification

The RTL is checked against a software golden model in `sim/`:

- `fnv1a_tb.v` — self-checking testbench. It contains `fnv1a_ref()`, a Verilog
  reimplementation of the exact FNV-1a algorithm (matching the C reference), and
  verifies the core three ways:
  - a **continuous** per-candidate check — every cycle the core is running, its
    internal hash for the current index must equal the reference (bit-exact);
  - directed vectors — a low index, the `"test"` vector at index 346,235, the
    `MAX-1` boundary, and a not-found sweep;
  - 16 randomized golden vectors, checking the returned preimage actually hashes
    to the target with no overshoot.
- `run.do` — headless ModelSim/Questa runner. `wave.do` — GUI run with the
  signals pre-added for a waveform capture.

Last run: **5,956,732** bit-exact hash comparisons and 20 end-to-end search
checks, **0 errors**. Pure Verilog-2001, so it runs unchanged in
ModelSim-Intel FPGA Starter, Questa, or Icarus.

```
# ModelSim / Questa (from the folder with fnv1a_core.v + fnv1a_tb.v)
vsim -c -do run.do
```

## A note on performance claims

Reported figure is **throughput** — one candidate per clock cycle, ~50M/s at
50 MHz — which follows directly from the clock rate. No CPU-vs-FPGA *speedup*
number is quoted here, because a fair comparison requires pinning the exact
baseline (HPS Cortex-A9 vs desktop, compiler optimisation level, wall-clock vs
cycle-count); against an optimised CPU baseline a single 50 MHz lane is roughly
break-even, and the real win comes from the parallel lanes / pipelining above.

## Build

1. Open `fnv1a_accelerator.qpf` in Quartus 20.1 Lite.
2. Generate the Qsys system from `soc_system.qsys` (Platform Designer).
3. Compile → produces the `.sof`.
4. Convert the `.sof` to a compressed `.rbf` for HPS-side loading (see below).

## Deploy on the DE10 (Linux on the HPS, sysfs / configfs)

Program the fabric at runtime from Linux via the FPGA manager and device-tree
overlays — no rebuild of the Linux image required.

**1. Make a bit-compressed `.rbf` and copy it to `/lib/firmware` on the board.**
Do this *before* mounting configfs, or the kernel won't reprogram the fabric.

```sh
# on the build host
quartus_cpf -c -o bitstream_compression=on fpga_project_file.sof fpga_program.rbf
scp fpga_program.rbf root@DE10_IP:/lib/firmware/     # copy the .rbf (not the .sof)
```

**2. Mount configfs and apply the bridge overlay** (`brg.dts`), which enables the
HPS-to-FPGA bridge:

```dts
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
```

```sh
mount -t configfs none /sys/kernel/config 2>/dev/null
mkdir /sys/kernel/config/device-tree/overlays/brg
dtc -@ -O dtb -o /root/brg.dtbo /root/brg.dts
cat /root/brg.dtbo > /sys/kernel/config/device-tree/overlays/brg/dtbo
cat /sys/class/fpga_bridge/br0/state          # bridge state (expected: disabled at this point)
```

**3. Apply the firmware overlay** (`fw.dts`), which tells the kernel to program
`fpga_program.rbf` (from `/lib/firmware`) onto the fabric:

```dts
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
```

```sh
mkdir /sys/kernel/config/device-tree/overlays/fw
dtc -@ -O dtb -o /root/fw.dtbo /root/fw.dts
cat /root/fw.dtbo > /sys/kernel/config/device-tree/overlays/fw/dtbo

# confirm the fabric was programmed and the bridge is enabled
cat /sys/class/fpga_manager/fpga0/state       # expected: "operating"
cat /sys/class/fpga_bridge/br0/state          # expected: "enabled"
```

> Overlay order matters: the bridge overlay (`brg`) must be applied before the
> firmware overlay (`fw`).

**4. Drive the accelerator** by writing/reading the register map at the
lightweight bridge base (`/dev/mem` or a UIO mapping): write TARGET, pulse
CONTROL bit0, then poll STATUS for `done`/`found` and read RESULT.

## Repo layout

- `fnv1a_core.v`, `fnv1a_slave.v`, `tle.v` — RTL.
- `fnv1a_slave_hw.tcl` — Platform Designer component definition.
- `soc_system.qsys` — Qsys system.
- `sim/` — `fnv1a_tb.v`, `run.do`, `wave.do` (self-checking testbench).
- `*.qpf`, `*.qsf` — Quartus project/settings.

## Next steps

- [ ] Register the hash datapath into pipeline stages to lift Fmax.
- [ ] Replicate the core into N lanes over disjoint index ranges, with
      priority-encoded result aggregation, for near-linear throughput scaling.
- [ ] Add a documented CPU-vs-FPGA benchmark with a pinned baseline (HPS
      Cortex-A9, compiler flags, wall-clock vs cycle-count) if a speedup figure
      is ever needed.
