# SimulinkSDIImporter

Package to import timeseries from a saved SDI Session (`.mldatx`-file) to julia. 

Main entry point is the `read_data` function. Given a SDI state as `mldatx` file
`data.mldatx` with contents

```
├─ "Synced Voltage Setpoint Change"
│  ├─ "Run 1: Converter_Model @ TargetPC1"
│  │  ├─ "U_INV_dq"
│  │  └─ "I_INV_dq"
│  └─ "Run 2: Converter_Model @ TargetPC2"
│     ├─ "U_INV_dq"
│     └─ "I_INV_dq"
└─ "Synced Current Setpoint Change"
    ├─ "Run 4: Converter_Model @ TargetPC1"
    |  ├─ "U_INV_dq"
    |  └─ "I_INV_dq"
    └─ "Run 5: Converter_Model @ TargetPC2"
        ├─ "U_INV_dq"
        └─ "I_INV_dq"
```

the command

```julia
read_data(data.mldatx, [r"Voltage", "Run 1", "U"])
```

will launch MATLAB in the background, export the timeseries to `data.export`
folder in CSV format and return a `DataFrame` of the `U_INV_dq` signal. If the
cached CSV is already available, it reads the CSV directly which is reasonably
fast.

The `matlab` command(path) and the flags can be changed by changing
`SimulinkSDIImporter.MATLAB_EXEC` and `SimulinkSDIImporter.MATLAB_FLAGS`.

Its possible launch the SDI to check the data without opening the MATLAB SDI
using `show_sdi(file)`.

`show_structure(file)` prints a tree of all signals in the file.


## Disclaimer
Tested with MATLAB 2022b for with data recorded from a SpeedGoat Realtime
Computer using a Mac. I hope it is more general though.
