module SimulinkSDIImporter

using CSV
using JSON3
using Dates
using TimeZones
using AbstractTrees
using DataFrames
using Statistics

export show_structure, read_data, show_sdi

MATLAB_EXEC = "matlab"
MATLAB_FLAGS = ["-nodisplay", "-batch"]

"""
    show_structure(file)

Print tree showing the hirachy of signals included in `file`. Starts matlab and
creates cache directory if not available.
"""
show_structure(file) = print_tree(read_json(file))

"""
    read_data(file, keys; correctdelay=true)

Load signal matching `keys` from `file`. File is an `*.mldatx` file which represents an Simulink SDI session.
Returns a `DataFrame` of the signal.

On first call, the package will spawn matlab and export signal as a `*.csv` in a
`filename.export` folder. On subsequent runs I'll load directly from CSV for speed.
Cache will be invalidated in case that the timestamp on `mldatx`-file changes.

`keys` is a vector of keys to identify a specific signal. Each key must uniquely identify the next node in the hierachy.

- `key::String`: Only one signal is *start with* the given letters. Equivalent to `r"^key"`.
- `key::Regex`:  Only one signal is allowed to *contain* the Regex.

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

`["Synced V", "Run 1", "U"]` works.

`["Synced", "Run 1", "I"]` does not work as both top level runs start with "Synced".

`[r"Voltage", r"Run 1", "I"]` works.

`[r"Voltage", r"1", "U"]` does not work because of "TargetPC1".

If `corectdelay=true` the timeseries will be shifted in time by the sampling rate.
This helps with aligning data obtained at different sample rates.
"""
function read_data(file, keys; correctdelay=true)
    file = abspath(file)
    basedir = dirname(file)
    bn = basename(file)

    tree = read_json(file)
    @assert isempty(children(tree[keys])) "Key Sequence $keys does not lead to leaf node/signal."

    csvfile = joinpath(basedir, _csv_name(file, keys))

    if !isfile(csvfile)
        @info "Launch matlab to export data..."
        expkeys = _expand_key(tree, keys)
        matlabstr = "pwd(); addpath(\"$(@__DIR__)\"); fh=SDIFileHandler(\"$bn\"); fh.export_signal($(repr(expkeys)))"

        cmd = Cmd(`$MATLAB_EXEC $MATLAB_FLAGS "$matlabstr"`; dir=basedir)
        run(cmd)
    end
    @assert isfile(csvfile)

    if readline(csvfile) != _get_filedate(file)
        @warn "Timestamps do not match, $(basename(file)) was changed after the CSV was exported."
    end

    df = CSV.read(csvfile, DataFrame; header=2)
    @info "Loaded columns: $(names(df))"

    if correctdelay
        _diff = diff(df.Time)
        diffm = mean(_diff)
        diffmin = minimum(_diff) - diffm
        diffmax = maximum(_diff) - diffm
        @assert diffmin > -1e-10 && diffmax < 1e-10 "Not equally sampled, cannot use `correctdealy=true`. Sampling differences to mean ($diffmin, $diffmax)"
        @info "correct for timeshift of $(round(diffm*10^6)) μs"
        df.Time = df.Time .- diffm
    end

    return df
end

"""
    show_sdi(file)

Start Matlab and launch SDI in Background. Will only launch SDI, no Matlabinterface.
"""
function show_sdi(file)
    file = abspath(file)
    basedir = dirname(file)
    bn = basename(file)

    @info "Launch matlab and open SDI..."
    matlabstr = "pwd(); addpath(\"$(@__DIR__)\"); fh=SDIFileHandler(\"$bn\"); fh.open_sdi()"

    cmd = Cmd(`$MATLAB_EXEC $MATLAB_FLAGS "$matlabstr"`; dir=basedir)
    run(cmd; wait=false)
end

function save_json(file)
    file = abspath(file)
    basedir = dirname(file)
    bn = basename(file)

    @assert isfile(file) "There is no file $file"

    @info "Launch matlab to export json..."
    matlabstr = "pwd(); addpath(\"$(@__DIR__)\"); fh=SDIFileHandler(\"$bn\");fh.save_json()"

    cmd = Cmd(`$MATLAB_EXEC $MATLAB_FLAGS "$matlabstr"`; dir=basedir)
    run(cmd)
end

function read_json(file)
    jsonf = joinpath(_export_dir(file), "contents.json")
    if !isfile(jsonf)
        save_json(file)
    end

    jsonstr = read(jsonf, String)
    desc = JSON3.read(jsonstr)

    if desc.version !== _get_filedate(file)
        @warn "Timestamps do not match, $(basename(file)) was changed after the json was extracted."
    end
    SDIData(desc)
end

function _get_filedate(file)
    filedate = Dates.unix2datetime(mtime(file))
    zdt = ZonedDateTime(filedate, tz"UTC")
    zdt = astimezone(zdt, tz"Europe/Berlin")
    filedate = DateTime(zdt)
    Dates.format(filedate, dateformat"dd-u-YYYY HH:MM:SS")
end

export SDIData

struct SDIData
    x::String
    children::Vector{SDIData}
end
function SDIData(desc)
    children = [SDIData(c) for c in desc.content]
    SDIData(desc.name, children)
end
function SDIData(str::String)
    children = SDIData[]
    SDIData(str, children)
end

AbstractTrees.children(t::SDIData) = t.children;
AbstractTrees.nodevalue(t::SDIData) = t.x;

Base.getindex(n::SDIData, key::String) = n[Regex("^"*key)]

function Base.getindex(n::SDIData, key::Regex)
# function Base.getindex(n::SDIData, key::Union{AbstractString, AbstractPattern})
    matches = Set{Int}()
    map(enumerate(children(n))) do (i, child)
        name = nodevalue(child)
        contains(name, key) && push!(matches, i)
    end
    if length(matches) == 1
        return children(n)[only(matches)]
    elseif length(matches) > 1
        fullmatches = String[]
        for m in matches
            name = nodevalue(children(n)[m])
            # its fine if it matches on enirely
            if match(key, name).match==name
                push!(fullmatches, name)
            end
        end
        if length(fullmatches) == 1
            return only(fullmatches)
        end
        throw(ArgumentError("Key $(repr(key)) not specific enough to distinguish $(nodevalue.(children(n)[collect(matches)]))"))
    elseif isempty(matches)
        throw(ArgumentError("No match for key $(repr(key)) within $(nodevalue.(children(n)))"))
    end
end

function Base.getindex(n::SDIData, keys)
    for key in keys
        n = n[key]
    end
    n
end
Base.getindex(n::SDIData, keys...) = n[keys]

Base.show(io::IO, ::MIME"text/plain", n::SDIData) = print_tree(io, n)

function Base.haskey(n::SDIData, key)
    try
        n[key]
    catch
        return false
    end
    return true
end

function _reduce_key(n::SDIData, keys)
    keys = _expand_key(n::SDIData, keys)
    shortkeys = String[]
    for key in keys[begin:end-1]
        for i in 0:length(key)
            short = key[1:i]
            if haskey(n, short)
                push!(shortkeys, short)
                break
            end
        end
        n = n[key]
    end
    push!(shortkeys, nodevalue(n[keys[end]]))
    return shortkeys
end

function _expand_key(n::SDIData, keys)
    if !haskey(n, keys)
        @info "Keysequence $keys not valid."
        n[keys]
    end
    longk = String[]
    for k in keys
        n = n[k]
        push!(longk, nodevalue(n))
    end
    longk
end

function _csv_name(file, keys)
    tree = read_json(file)
    tree[keys] # check if getindex works

    return joinpath(_export_dir(file), join(_reduce_key(tree, keys),"-") * ".csv")
end

function _export_dir(file)
    sp = splitpath(file)
    exportdir = joinpath(sp[begin:end-1]..., "sdi_exports")
    if isdir(exportdir)
        joinpath(exportdir, sp[end]*".export")
    else
        file*".export"
    end
end

end
